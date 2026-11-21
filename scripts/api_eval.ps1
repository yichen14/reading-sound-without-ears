# API evaluation of MMAU test-mini without audio input. One independent API request (or tool loop) per
# question, model and condition. Conditions:
#   A  question text only
#   B  question + clip length + two spectrogram images (0-8 kHz and 0-2 kHz)
#   C  B + Whisper transcript
#   D  question + clip length + Whisper transcript
#   E  question + clip length + a tool that queries the clip's numeric spectrogram file (no image, no transcript)
# Results: full\api\<model>\<cond>\<qid>.json  (resumable: existing files are skipped)
# The API key is read from -KeyFile and never printed. The answer key is never read here.
param(
    [string]$Root, [string]$Model, [string]$Cond, [string]$IdsFile = '', [int]$Limit = 0,
    [int]$Workers = 6, [string]$Effort = 'high', [int]$MaxTokens = 16000, [int]$MaxToolRounds = 12,
    # The API key is read from the ANTHROPIC_API_KEY environment variable, or from -KeyFile if given.
    [string]$KeyFile = '',
    [string]$Out = 'full',
    # -Explain: the JSON answer also carries an "observations" field (what evidence was used), written before the answer.
    # -Tag: suffix for the output folder, e.g. "_explain".  Cond L = question + clip length only (control for B/E).
    [switch]$Explain, [string]$Tag = ''
)
$ErrorActionPreference = 'Stop'
Set-Location $Root
if (-not ('Spec' -as [type])) { Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $Root 'scripts\specq.cs'))) }
$key = if ($KeyFile) { ([IO.File]::ReadAllText($KeyFile)).Trim() } else { "$env:ANTHROPIC_API_KEY".Trim() }
if (-not $key) { throw 'Set ANTHROPIC_API_KEY or pass -KeyFile.' }
$short = ($Model -replace '^claude-', '')
$dir = Join-Path $Root "$Out\api\$short\$Cond$Tag";New-Item -ItemType Directory -Force $dir | Out-Null
$q = Get-Content "$Out\questions.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$dur = @{}; Import-Csv "$Out\durations.csv" | ForEach-Object { $dur[$_.qid] = $_.seconds }
$todo = @($q)
if ($IdsFile) { $only = @{}; Get-Content $IdsFile | ForEach-Object { if ($_.Trim()) { $only[$_.Trim()] = 1 } }; $todo = @($todo | Where-Object { $only.ContainsKey($_.qid) }) }
$todo = @($todo | Where-Object { -not (Test-Path (Join-Path $dir "$($_.qid).json")) })
if ($Limit -gt 0) { $todo = @($todo | Select-Object -First $Limit) }
"[$short/$Cond] to run: $($todo.Count)"
if ($todo.Count -eq 0) { return }

# ---------- shared text ----------
$L = 'ABCDEFGH'
$intro = 'You are answering a multiple-choice question about an audio clip. You cannot listen to the audio.'
$evidence = @{
    'A' = 'You get only the question and the answer options, no information from the audio itself.'
    'B' = 'You get two spectrogram images of the clip. Image 1: linear frequency axis 0-8 kHz (audio resampled to 16 kHz), time axis in seconds along the top, colour = level (magma palette, 85 dB range, brighter = louder). Image 2: the same clip zoomed to 0-2 kHz on a linear frequency axis (bottom = 0 Hz, top = 2 kHz), the full clip duration left to right, 70 dB range, no axis labels.'
    'C' = 'You get two spectrogram images of the clip and an automatic speech-recognition transcript. Image 1: linear frequency axis 0-8 kHz (audio resampled to 16 kHz), time axis in seconds along the top, colour = level (magma palette, 85 dB range, brighter = louder). Image 2: the same clip zoomed to 0-2 kHz on a linear frequency axis (bottom = 0 Hz, top = 2 kHz), the full clip duration left to right, 70 dB range, no axis labels. The transcript comes from Whisper (small model, language auto-detected); it can contain recognition errors, and on music or noise it can contain hallucinated text.'
    'D' = 'You get an automatic speech-recognition transcript of the clip. It comes from Whisper (small model, language auto-detected); it can contain recognition errors, and on music or noise it can contain hallucinated text.'
    'E' = 'You cannot see a picture of the audio either. Instead you have a tool, query_spectrogram, that computes measurements from the clip''s spectrogram (16 kHz mono, 2048-point FFT, 32 ms hop). Call it as often as you find useful (at most 12 rounds of calls), then answer.'
}
$evidence['L'] = 'You get only the question, the answer options and the length of the clip, no other information from the audio itself.'
$closing = 'Choose the single best option. Reply with JSON of the form {"answer": "<letter>"}.'
if ($Explain) { $closing = 'Choose the single best option. Reply with JSON of the form {"observations": "<text>", "answer": "<letter>"}. In "observations", list briefly the concrete evidence you relied on (for images or measurements: what you saw, with approximate times and frequencies; otherwise: what general knowledge or cues in the question), and say which option it rules in or out.' }
$toolDef = [ordered]@{
    name = 'query_spectrogram'
    description = @'
Measurements from the clip's spectrogram. Times are in seconds, frequencies in Hz; leave out t0/t1 for the whole clip.
Commands:
- info: duration, loudness envelope (one digit per 0.25 s, 9 = loudest, each step 6 dB lower), 10-band level profile, spectral centroid, noisiness (0 tonal .. 9 noise-like).
- bands (t0, t1, step): per time step, 10 band-level digits for 0-125, 125-250, 250-500, 500-1k, 1-1.5k, 1.5-2k, 2-3k, 3-4k, 4-6k, 6-8k Hz (9 = loudest cell, each step 6 dB lower) plus a noisiness digit.
- peaks (t0, t1, fmin, fmax): the strongest spectral peaks of the mean spectrum in the window, as Hz:dB relative to the strongest.
- track (t0, t1, step, fmin, fmax): the strongest peak frequency per time step inside a band (pitch contours, sweeps, sirens).
- f0 (t0, t1, step): fundamental-frequency estimate per step (60-800 Hz) with a salience percentage.
- chroma (t0, t1, step): pitch-class strengths and the best-matching major/minor triad, per step or for the whole window.
- onsets (t0, t1): onset times from spectral flux and the strongest onset periodicity in beats per minute (could be double or half the tempo).
- raw (t0, t1, fmin, fmax): the level values themselves in dB, averaged down to at most 16 x 16 cells.
'@
    input_schema = [ordered]@{
        type = 'object'
        properties = [ordered]@{
            command = [ordered]@{ type = 'string'; enum = @('info', 'bands', 'peaks', 'track', 'f0', 'chroma', 'onsets', 'raw') }
            t0 = [ordered]@{ type = 'number' }; t1 = [ordered]@{ type = 'number' }; step = [ordered]@{ type = 'number' }
            fmin = [ordered]@{ type = 'number' }; fmax = [ordered]@{ type = 'number' }
        }
        required = @('command')
    }
}

function Transcript([string]$qid) {
    $f = Join-Path $Root "$Out\asr\$qid.srt"
    if (-not (Test-Path $f)) { return '(no transcript produced)' }
    $o = @(); $t = ''
    foreach ($l in [IO.File]::ReadAllLines($f, [Text.Encoding]::UTF8)) {
        if ($l -match '^(\d\d):(\d\d):(\d\d)[,.](\d)\d* --> (\d\d):(\d\d):(\d\d)[,.](\d)') {
            $t = '{0}.{1}-{2}.{3}s' -f ([int]$Matches[2] * 60 + [int]$Matches[3]), $Matches[4], ([int]$Matches[6] * 60 + [int]$Matches[7]), $Matches[8]
        } elseif ($l.Trim() -and $l -notmatch '^\d+$') { $o += "[$t] $($l.Trim())" }
    }
    if ($o.Count -eq 0) { '(no speech recognised)' } else { $o -join "`n" }
}
function Img([string]$path) { [ordered]@{ type = 'image'; source = [ordered]@{ type = 'base64'; media_type = 'image/jpeg'; data = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) } } }

# ---------- build one job per question ----------
$jobs = foreach ($x in $todo) {
    $n = $x.choices.Count; $letters = @(); $opts = @()
    for ($i = 0; $i -lt $n; $i++) {
        $c = "$($x.choices[$i])".Trim(); if ($c -match '^\(([A-H])\)\s*(.*)$' -and $Matches[1] -eq $L[$i]) { $c = $Matches[2] }
        $letters += [string]$L[$i]; $opts += "($($L[$i])) $c"
    }
    $qtext = "Question: $($x.question)`nOptions:`n" + ($opts -join "`n")
    $content = @()
    if ($Cond -in 'B', 'C') {
        $content += [ordered]@{ type = 'text'; text = 'Image 1 (0-8 kHz spectrogram):' }; $content += Img (Join-Path $Root "$Out\spec_small\$($x.qid).jpg")
        $content += [ordered]@{ type = 'text'; text = 'Image 2 (0-2 kHz zoom):' }; $content += Img (Join-Path $Root "$Out\spec_low\$($x.qid).jpg")
    }
    $t = ''
    if ($Cond -ne 'A') { $t += "Clip length: $($dur[$x.qid]) s`n" }
    if ($Cond -in 'C', 'D') { $t += "Transcript:`n$(Transcript $x.qid)`n" }
    $t += "`n$qtext"
    $content += [ordered]@{ type = 'text'; text = $t }
    $body = [ordered]@{
        model = $Model; max_tokens = $MaxTokens
        system = "$intro $($evidence[$Cond]) $closing"
        output_config = [ordered]@{ effort = $Effort; format = [ordered]@{ type = 'json_schema'; schema = [ordered]@{
            type = 'object'; properties = $(if ($Explain) { [ordered]@{ observations = [ordered]@{ type = 'string' }; answer = [ordered]@{ type = 'string'; enum = $letters } } } else { [ordered]@{ answer = [ordered]@{ type = 'string'; enum = $letters } } })
            required = [string[]]$(if ($Explain) { @('observations', 'answer') } else { @('answer') }); additionalProperties = $false } } }
        messages = @([ordered]@{ role = 'user'; content = $content })
    }
    if ($Cond -eq 'E') { $body.tools = @($toolDef); $body.cache_control = [ordered]@{ type = 'ephemeral' } }
    [pscustomobject]@{ qid = $x.qid; body = $body; spec = (Join-Path $Root "$Out\specdata\$($x.qid).csv"); out = (Join-Path $dir "$($x.qid).json"); stop = (Join-Path $Root "$Out\api\STOP_credit") }
}

# ---------- worker ----------
$worker = {
    param($job, $key, $cond, $maxRounds)
    $ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
    if (Test-Path $job.out) { return "$($job.qid) skipped (already done)" }
    # credit exhausted in any process: stop without writing a result, so a later run resumes cleanly
    if (Test-Path $job.stop) { return "$($job.qid) skipped (HTTP credit stop)" }
    function Call($body) {
        $json = $body | ConvertTo-Json -Depth 30 -Compress
        for ($try = 0; $try -lt 8; $try++) {
            try {
                return Invoke-RestMethod -Uri 'https://api.anthropic.com/v1/messages' -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($json)) `
                    -ContentType 'application/json' -Headers @{ 'x-api-key' = $key; 'anthropic-version' = '2026-10-21' } -TimeoutSec 900
            } catch {
                $resp = $_.Exception.Response; $code = 0; $msg = $_.Exception.Message
                if ($resp) { $code = [int]$resp.StatusCode; try { $msg = (New-Object IO.StreamReader($resp.GetResponseStream())).ReadToEnd() } catch {} }
                if ($code -in 400, 401, 403, 404, 413) { throw "HTTP $code $msg" }
                $wait = [math]::Min(120, 5 * [math]::Pow(2, $try)); if ($resp -and $resp.Headers['retry-after']) { $wait = [int]$resp.Headers['retry-after'] + 1 }
                Start-Sleep -Seconds $wait
            }
        }
        throw "gave up after retries: $msg"
    }
    $res = [ordered]@{ qid = $job.qid; answer = $null; stop_reason = $null; rounds = 0; tool_calls = @(); input_tokens = 0; output_tokens = 0; cache_read = 0; cache_write = 0; text = ''; error = $null }
    try {
        $body = $job.body; $spec = $null
        for ($round = 0; ; $round++) {
            if ($cond -eq 'E' -and $round -ge $maxRounds) { $body.tool_choice = [ordered]@{ type = 'none' } }
            $r = Call $body
            $res.input_tokens += [int]$r.usage.input_tokens; $res.output_tokens += [int]$r.usage.output_tokens
            if ($r.usage.cache_read_input_tokens) { $res.cache_read += [int]$r.usage.cache_read_input_tokens }
            if ($r.usage.cache_creation_input_tokens) { $res.cache_write += [int]$r.usage.cache_creation_input_tokens }
            $res.stop_reason = $r.stop_reason; $res.rounds = $round + 1
            $uses = @($r.content | Where-Object { $_.type -eq 'tool_use' })
            if ($r.stop_reason -eq 'tool_use' -and $uses.Count -gt 0) {
                if ($null -eq $spec) { $spec = [Spec]::Load($job.spec) }
                $results = @()
                foreach ($u in $uses) {
                    $in = $u.input; $a = @()
                    $t0 = if ($null -ne $in.t0) { [double]$in.t0 } else { 0 }; $t1 = if ($null -ne $in.t1) { [double]$in.t1 } else { $spec.dur }
                    switch ($in.command) {
                        'bands'  { $a = @($t0, $t1); if ($null -ne $in.step) { $a += [double]$in.step } }
                        'peaks'  { $a = @($t0, $t1); if ($null -ne $in.fmin -or $null -ne $in.fmax) { $a += @($(if ($null -ne $in.fmin) { [double]$in.fmin } else { 40 }), $(if ($null -ne $in.fmax) { [double]$in.fmax } else { 8000 })) } }
                        'track'  { $a = @($t0, $t1, $(if ($null -ne $in.step) { [double]$in.step } else { 0.25 }), $(if ($null -ne $in.fmin) { [double]$in.fmin } else { 40 }), $(if ($null -ne $in.fmax) { [double]$in.fmax } else { 8000 })) }
                        'f0'     { $a = @($t0, $t1); if ($null -ne $in.step) { $a += [double]$in.step } }
                        'chroma' { $a = @($t0, $t1); if ($null -ne $in.step) { $a += [double]$in.step } }
                        'onsets' { $a = @($t0, $t1) }
                        'raw'    { $a = @($t0, $t1, $(if ($null -ne $in.fmin) { [double]$in.fmin } else { 0 }), $(if ($null -ne $in.fmax) { [double]$in.fmax } else { 8000 })) }
                        default  { $a = @() }
                    }
                    $txt = try { $spec.Run([string]$in.command, [double[]]$a) } catch { "error: $($_.Exception.Message)" }
                    if ($txt.Length -gt 6000) { $txt = $txt.Substring(0, 6000) + "`n...(truncated)" }
                    $res.tool_calls += ("$($in.command) " + ($a -join ' '))
                    $results += [ordered]@{ type = 'tool_result'; tool_use_id = $u.id; content = $txt }
                }
                $body.messages += [ordered]@{ role = 'assistant'; content = $r.content }
                $body.messages += [ordered]@{ role = 'user'; content = $results }
                continue
            }
            $txt = (@($r.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join '').Trim(); $res.text = $txt
            try { $res.answer = ($txt | ConvertFrom-Json).answer } catch { if ($txt -match '"answer"\s*:\s*"([A-H])"') { $res.answer = $Matches[1] } }
            break
        }
    } catch { $res.error = "$($_.Exception.Message)" }
    if ($res.error -match 'credit balance') { [IO.File]::WriteAllText($job.stop, 'credit'); return "$($job.qid) HTTP credit stop (not saved)" }
    [IO.File]::WriteAllText($job.out, ($res | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
    "$($job.qid) $($res.answer) $($res.stop_reason) r$($res.rounds) $($res.error)"
}

$pool = [RunspaceFactory]::CreateRunspacePool(1, $Workers); $pool.Open()
$running = foreach ($j in $jobs) {
    $ps = [PowerShell]::Create(); $ps.RunspacePool = $pool
    [void]$ps.AddScript($worker).AddArgument($j).AddArgument($key).AddArgument($Cond).AddArgument($MaxToolRounds)
    [pscustomobject]@{ ps = $ps; h = $ps.BeginInvoke() }
}
$done = 0; $errs = 0
foreach ($r in $running) {
    $o = $r.ps.EndInvoke($r.h); $done++
    if ($r.ps.Streams.Error.Count -gt 0 -or ("$o" -match ' (HTTP|gave up)')) { $errs++; "  $o $($r.ps.Streams.Error | Select-Object -First 1)" }
    $r.ps.Dispose()
}
$pool.Close()
"[$short/$Cond] finished $done, with errors: $errs"
