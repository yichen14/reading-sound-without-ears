# Build blog\reading-sound-without-ears.html from blog\template.html: computes all numbers from the result files
# and embeds audio and spectrograms as data URIs so the page is a single self-contained file.
# -SiteDir: also export the bilingual post for the personal site (yichen14.github.io layout): writes
#   <SiteDir>\posts\reading-sound-without-ears.html from blog\site_post.html, and
#   <SiteDir>\posts\reading-sound-without-ears\ (data.js, audio, spectrograms; figures.js is copied from blog\site_figures.js)
param([string]$Root, [string]$SiteDir = '')
$ErrorActionPreference = 'Stop'
Set-Location $Root
$enc = New-Object Text.UTF8Encoding($false)
$LET = 'ABCDEFGH'
function Norm([string]$s) { (($s -replace '^\s*\(([A-Pa-p])\)\s*', '') -replace '[^\p{L}\p{N}]+', ' ').Trim().ToLowerInvariant() }
$qs = Get-Content full\questions.json -Raw -Encoding UTF8 | ConvertFrom-Json
$key = @{}; (Get-Content full\answer_key.json -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { $key[$_.qid] = $_.answer }
$dur = @{}; Import-Csv full\durations.csv | ForEach-Object { $dur[$_.qid] = [double]$_.seconds }
$Q = @{}; $gold = @{}
foreach ($x in $qs) { $Q[$x.qid] = $x; $k = Norm $key[$x.qid]; $g = @(); for ($i = 0; $i -lt $x.choices.Count; $i++) { if ((Norm $x.choices[$i]) -eq $k) { $g += [string]$LET[$i] } }; $gold[$x.qid] = $g }
function Res($model, $cond) { $h = @{}; foreach ($f in Get-ChildItem "full\api\$model\$cond\*.json") { $j = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json; $h[$j.qid] = $j }; $h }
$models = [ordered]@{ opus = 'opus-5-5'; fable = 'fable-5-2' }
$R = @{}; foreach ($m in $models.Keys) { $R[$m] = @{}; foreach ($c in 'A', 'L', 'B', 'C', 'D', 'E') { $R[$m][$c] = Res $models[$m] $c } }
function Ok($m, $c, $qid) { $a = $R[$m][$c][$qid]; if (-not $a) { return $null }; [int]($gold[$qid] -contains $a.answer) }

# ---- accuracy per condition and task ----
$res = [ordered]@{}; $n = [ordered]@{ sound = 0; music = 0; speech = 0 }; foreach ($x in $qs) { $n[$x.task]++ }
foreach ($m in $models.Keys) { $res[$m] = [ordered]@{}; foreach ($c in 'A', 'L', 'B', 'C', 'D', 'E') {
    $cnt = $R[$m][$c].Count; if ($cnt -lt 1000) { Write-Warning "$m $c has $cnt results"; }
    $o = [ordered]@{}; foreach ($t in 'all', 'sound', 'music', 'speech') { $sel = @($qs | Where-Object { $t -eq 'all' -or $_.task -eq $t }); $ok = 0; foreach ($x in $sel) { $ok += [int](Ok $m $c $x.qid) }; $o[$t] = [math]::Round(100 * $ok / $sel.Count, 1) }
    $res[$m][$c] = $o } }

# ---- heat table ----
$cols = @(@('fable', 'A', 'L', 'Fable L−A'), @('opus', 'L', 'B', 'Opus B−L'), @('fable', 'L', 'B', 'Fable B−L'), @('opus', 'L', 'E', 'Opus E−L'), @('fable', 'L', 'E', 'Fable E−L'), @('fable', 'D', 'C', 'Fable C−D'))
$heat = @(); foreach ($grp in ($qs | Group-Object task, subcategory | Where-Object Count -ge 20 | Sort-Object { $_.Group[0].task }, Name)) {
    $from = @(); $to = @(); $d = @()
    foreach ($cdef in $cols) { $a = 0; $b = 0; foreach ($x in $grp.Group) { $a += [int](Ok $cdef[0] $cdef[1] $x.qid); $b += [int](Ok $cdef[0] $cdef[2] $x.qid) }; $pa = 100 * $a / $grp.Count; $pb = 100 * $b / $grp.Count; $from += [math]::Round($pa); $to += [math]::Round($pb); $d += [math]::Round($pb - $pa, 1) }
    $heat += [ordered]@{ task = $grp.Group[0].task; name = $grp.Group[0].subcategory; n = $grp.Count; from = $from; to = $to; d = $d } }
$heat = @($heat | Sort-Object { - [math]::Abs($_.d[2]) })

# ---- timing vs sound quality: grouped sub-skills, L -> B and L -> E with McNemar chi2 ----
$groups = [ordered]@{
    timing  = @{ label = 'When things happen'; sub = 'event timing, order, counting'; skills = @('sound|Temporal Event Reasoning', 'speech|Counting') }
    rhythm  = @{ label = 'Rhythm and tempo'; sub = 'music'; skills = @('music|Rhythm and Tempo Understanding') }
    quality = @{ label = 'How it sounds'; sub = 'melody, harmony, timbre, texture, genre, emotion'; skills = @('music|Melodic Structure Interpretation', 'music|Harmony and Chord Progressions', 'music|Instrumentation', 'music|Musical Texture Interpretation', 'music|Musical Genre Reasoning', 'music|Emotional Tone Interpretation', 'speech|Emotion State summarisation', 'speech|Emotion Flip Detection') }
}
$split = @(); foreach ($k in $groups.Keys) {
    $sel = @($qs | Where-Object { $groups[$k].skills -contains "$($_.task)|$($_.subcategory)" }); $rows = @()
    foreach ($m in $models.Keys) { foreach ($c in 'B', 'E') {
        $a = 0; $b = 0; $g = 0; $l = 0
        foreach ($x in $sel) { $okL = [int](Ok $m 'L' $x.qid); $okC = [int](Ok $m $c $x.qid); $a += $okL; $b += $okC; if ($okL -eq 0 -and $okC -eq 1) { $g++ }; if ($okL -eq 1 -and $okC -eq 0) { $l++ } }
        $chi = if ($g + $l) { [math]::Pow([math]::Abs($g - $l) - 1, 2) / ($g + $l) } else { 0 }
        $rows += [ordered]@{ m = $m; c = $c; from = [math]::Round(100 * $a / $sel.Count, 1); to = [math]::Round(100 * $b / $sel.Count, 1); gain = $g; loss = $l; p = $(if ($chi -gt 10.83) { '<0.001' } elseif ($chi -gt 6.63) { '<0.01' } elseif ($chi -gt 3.84) { '<0.05' } else { 'n.s.' }) } } }
    $split += [ordered]@{ key = $k; label = $groups[$k].label; sub = $groups[$k].sub; n = $sel.Count; rows = $rows } }

# explicit tempo / BPM questions: how often the E runs asked for onsets, and accuracy
$tempoQ = @($qs | Where-Object { $_.task -eq 'music' -and $_.question -match '(?i)\btempo\b|\bbpm\b|beat count' })
$tempo = [ordered]@{ n = $tempoQ.Count }
foreach ($m in $models.Keys) { $on = 0; $okE = 0; $okL = 0; foreach ($x in $tempoQ) { $j = $R[$m]['E'][$x.qid]; if (@($j.tool_calls | Where-Object { $_ -like 'onsets*' }).Count) { $on++ }; $okE += [int](Ok $m 'E' $x.qid); $okL += [int](Ok $m 'L' $x.qid) }; $tempo[$m] = [ordered]@{ onsets = $on; E = $okE; L = $okL } }

# ---- tool calls ----
$tools = [ordered]@{}; $avgCalls = @{}; $zero = @{}
foreach ($m in $models.Keys) { $b = @{}; $tot = 0; foreach ($j in $R[$m]['E'].Values) { $k = [math]::Min(@($j.tool_calls).Count, 9); $tot += @($j.tool_calls).Count; if (-not $b[$k]) { $b[$k] = @(0, 0) }; $b[$k][0]++; $b[$k][1] += [int]($gold[$j.qid] -contains $j.answer) }
    $avgCalls[$m] = [math]::Round($tot / 1000, 1); $zero[$m] = $b[0][0]
    $tools[$m] = @(0..9 | ForEach-Object { $v = $b[$_]; [ordered]@{ k = $(if ($_ -eq 9) { '9+' } else { "$_" }); n = $v[0]; acc = [math]::Round(100 * $v[1] / [math]::Max(1, $v[0]), 1) } }) }

# ---- cost ----
$price = @{ 'opus-5-5' = @(4, 20, 0.2, 5); 'fable-5-2' = @(8, 40, 0.2, 10) }; $cost = 0
foreach ($md in Get-ChildItem full\api -Directory) { if (-not $price[$md.Name]) { continue }; $p = $price[$md.Name]
    foreach ($f in Get-ChildItem "$($md.FullName)\*\*.json") { $j = Get-Content $f.FullName -Raw | ConvertFrom-Json; $cost += ($j.input_tokens * $p[0] + $j.output_tokens * $p[1] + $j.cache_read * $p[2] + $j.cache_write * $p[3]) / 1e6 } }

# ---- run-to-run flips (B vs B_explain on the 32 re-asked questions) ----
$flip = 0; $pairs = 0
foreach ($m in $models.Keys) { foreach ($f in Get-ChildItem "full\api\$($models[$m])\B_explain\*.json") { $j = Get-Content $f.FullName -Raw | ConvertFrom-Json; $pairs++; if ($j.answer -ne $R[$m]['B'][$j.qid].answer) { $flip++ } } }

# ---- examples ----
# Invoke-RestMethod in PowerShell 5.1 decoded some API responses as Latin-1, so UTF-8 punctuation (– → ≈) arrives as "â.." sequences.
function FixMojibake([string]$s) {
    if ($s -notmatch '[Â-ô][\u0080-¿]') { return $s }
    foreach ($c in $s.ToCharArray()) { if ([int]$c -gt 255) { return $s } }
    [Text.Encoding]::UTF8.GetString([Text.Encoding]::GetEncoding(28591).GetBytes($s))
}
function DataUri($path, $mime) { "data:$mime;base64," + [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $Root $path))) }
$marks = @{
    mini_0054 = @{ points = @(@(0.05, 'switch clicks'), @(4.5, 'boiling water'), @(9.1, 'doorbell'), @(11.6, 'clock ticks')); hlines = @(@(750, 'chime ~750 Hz'), @(4150, 'chime ~4.1 kHz')) }
    mini_0061 = @{ points = @(@(0.02, 'tap 1'), @(2.8, 'tap 2'), @(5.6, 'tap 3'), @(8.4, 'tap 4')); hlines = @(@(2700, 'ring ~2.7 kHz'), @(6400, 'ring ~6.4 kHz')) }
    mini_0080 = @{ spans = @(@(0.1, 2.0, 'moo 1'), @(2.8, 4.9, 'moo 2'), @(5.6, 7.6, 'moo 3'), @(8.4, 10.5, 'moo 4'), @(11.3, 13.4, 'moo 5')) }
    mini_0068 = @{ spans = @(@(0, 3.5, 'hiss'), @(3.9, 8.7, 'hiss continues')); points = @(@(0.3, 'speech'), @(4.3, 'speech'), @(6.0, 'speech')); hlines = @(@(3200, 'hiss band starts ~3.2 kHz')) }
    mini_0854 = @{ spans = @(@(0, 10, 'steady tone the whole clip')); hlines = @(@(2750, '~2.7 kHz alarm tone'), @(5650, '2nd harmonic ~5.6 kHz')) }
    mini_0864 = @{ spans = @(@(0, 2.7, 'spin-down'), @(4.6, 7.3, 'spin-up, hold'), @(7.3, 9.2, 'spin-down')) }
    mini_0825 = @{ points = @(@(0.5, 'wave'), @(8, 'wave'), @(15.5, 'wave'), @(22, 'wave')) }
    mini_0001 = @{ hlines = @(@(225, 'models (B): F0 ~225 Hz'), @(173, 'tool (E): F0 173 Hz')); view = 'low' }
    mini_0145 = @{ spans = @(@(0, 3.3, '~100 Hz'), @(4.1, 6.3, '~150 Hz'), @(6.5, 7.9, '~350–400 Hz'), @(8.1, 9.4, '~170–200 Hz')); view = 'low' }
    mini_0352 = @{ points = @(@(1.6, 'glide'), @(4.1, 'glide'), @(6.0, 'glide')); spans = @(@(2.5, 4.3, 'vibrato')) }
    mini_0391 = @{ spans = @(@(0, 3, 'flat reed-like notes'), @(3.5, 10, 'a voice enters')) }
    mini_0174 = @{ spans = @(@(0, 14.5, '~40 syllable bursts ≈ 30–40 words')) }
    mini_0542 = @{ hlines = @(@(730, 'sung F0 ~730 Hz')); spans = @(@(1.5, 3.2, 'measured ~710–760 Hz')); view = 'low' }
    mini_0423 = @{ spans = @(@(0, 4.8, 'A'), @(4.8, 7.2, 'B = key'), @(7.2, 9.6, 'C'), @(9.6, 10.8, 'D = both models')); view = 'low' }
    mini_0711 = @{ spans = @(@(0, 1.6, 'loud noise, then drop')); points = @(@(2.2, 'streak?'), @(4.3, 'streak?'), @(6.8, 'streak?')) }
}
$notes = @{
    mini_0054 = '<b>Reading:</b> sparse vertical clicks, then a block of low-weighted noise, then two horizontal tones that decay slowly, then a regular comb of clicks. Both models named all four segments and their times within a fraction of a second.'
    mini_0061 = '<b>Reading:</b> four identical vertical transients 2.8 s apart, each followed by ringing partials. Our onset detector found only three of them (it missed the one at 0 s); both models counted four, which is correct. Without the picture both picked "3".'
    mini_0080 = '<b>Reading:</b> five harmonic blocks of about 2 s with dark gaps between them. The onset detector reports 20 onsets here (each moo has several), so a naive tool count would be wrong; the picture makes the grouping obvious.'
    mini_0068 = '<b>Reading:</b> a band of noise above about 3 kHz runs almost the whole clip, while voiced harmonics appear only in shorter bursts. Duration questions reduce to measuring horizontal extent, which the models do well.'
    mini_0854 = '<b>Reading:</b> one narrow horizontal line near 2.7 kHz for the full 10 s, with a weaker harmonic near 5.6 kHz. Both models connect "constant tone near 3 kHz" with a piezo alarm. Our peak finder places the strongest peak above 1 kHz at 2,742 Hz.'
    mini_0864 = '<b>Reading:</b> harmonics that slide down, silence, an abrupt onset with harmonics sweeping up to a steady pitch, then sliding down again. Both models describe a motor spinning up and down and rule out frying, typing and a washing machine on the shape alone.'
    mini_0825 = '<b>Reading:</b> broadband noise that surges and recedes about every 7&ndash;8 s, with no harmonic structure. Both models infer breaking waves and argue that wind would be more irregular.'
    mini_0001 = '<b>Reading:</b> in the zoom view both models estimated a harmonic spacing of about 200&ndash;250 Hz and concluded adult female, which is correct. The numeric tool shows the true fundamental is lower, about 175 Hz (harmonics at 173, 351, 524 Hz), a low female voice in the male&ndash;female overlap; with those exact numbers both models answered "adult man". The picture reading was right, but partly by luck.'
    mini_0145 = '<b>Reading:</b> four turns separated by short gaps, each with a different harmonic spacing (about 100, 150, 350&ndash;400 and 170&ndash;200 Hz). Fable assigns turns 2 and 4 to the same voice and concludes three speakers. The text-only answer was "two".'
    mini_0352 = '<b>Reading:</b> wavy partials (vibrato) and smooth glides between notes point to a bowed string; closely spaced harmonics with energy reaching down to 100&ndash;200 Hz suggest a cello rather than a violin. Both models flag the cello-versus-violin call as the uncertain part.'
    mini_0391 = '<b>Reading:</b> flat, dense harmonic stacks with no decay and no vibrato in the first three seconds: a free reed. Piano partials would fade after each attack; flute would have few upper harmonics.'
    mini_0174 = '<b>Reading:</b> near-continuous voiced speech for 14.7 s, roughly 40 syllable-like bursts, so about 35&ndash;40 words, so "32" is the only plausible option. %%L0174%%'
    mini_0542 = '<b>Reading:</b> a single gliding vocal line with its lowest strong harmonic near 700&ndash;800 Hz. The measurement is right; the inference "too high for a male singer" is not. The answer key says "flat male vocals".'
    mini_0423 = '<b>Reading:</b> the question asks when the chord <code>E:9(*1)/3</code> (G#, B, D, F# over G#) sounds. Both models picked the 9.6&ndash;10.8 s window because a partial near 415 Hz looked like G#. The key says 4.8&ndash;7.2 s. With the numeric <code>chroma</code> tool (condition E) both models got it right.'
    mini_0711 = '<b>Reading:</b> broadband noise under speech, loud at the start and then dropping. Opus reads the short vertical streaks as raindrops; Fable reads the gusty level changes as wind (correct). In the main run both had answered "rainy"; with the numeric tool (condition E) both answered "windy".'
}
$etraceIds = @('mini_0001', 'mini_0061', 'mini_0854')
$exIds = @($marks.Keys)
$ex = [ordered]@{}
foreach ($id in $exIds) {
    $x = $Q[$id]; $ch = @(); foreach ($c in $x.choices) { $s = "$c".Trim(); $s = $s -replace '^\(([A-H])\)\s*', ''; $ch += $s }
    $ans = [ordered]@{}; $obs = [ordered]@{}
    foreach ($m in $models.Keys) { $ans[$m] = [ordered]@{}; foreach ($c in 'A', 'L', 'B', 'E', 'C', 'D') { $ans[$m][$c] = [string]$R[$m][$c][$id].answer }
        $f = "full\api\$($models[$m])\B_explain\$id.json"; if (Test-Path $f) { $j = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json; $t = try { ($j.text | ConvertFrom-Json).observations } catch { $j.text }; $obs[$m] = [ordered]@{ a = [string]$j.answer; t = (FixMojibake ([string]$t)) } } }
    $et = $null; if ($etraceIds -contains $id) { $et = (@('opus', 'fable') | ForEach-Object { $j = $R[$_]['E'][$id]; "$($_.PadRight(6)) -> " + ((@($j.tool_calls) | ForEach-Object { $_.Trim() }) -join '  |  ') + "   => answered $($j.answer)" }) -join "`n" }
    $mk = $marks[$id]; $view = 'full'; if ($mk.view) { $view = $mk.view }
    $mm = [ordered]@{}; foreach ($k in 'spans', 'points', 'hlines') { if ($mk[$k]) { $mm[$k] = @($mk[$k] | ForEach-Object { , @($_) }) } }
    $ex[$id] = [ordered]@{ id = $id; question = $x.question; choices = $ch; gold = $gold[$id]; task = $x.task; sub = $x.subcategory; dur = $dur[$id]
        audio = (DataUri "blog\assets\$id.mp3" 'audio/mpeg'); full = (DataUri "blog\assets\${id}_full.jpg" 'image/jpeg'); low = (DataUri "blog\assets\${id}_low.jpg" 'image/jpeg')
        ans = $ans; obs = $obs; etrace = $et; marks = $mm; view = $view; note = $notes[$id] }
}

# ---- trace for the pictures-vs-numbers section ----
if (-not ('Spec' -as [type])) { Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $Root 'scripts\specq.cs'))) }
$sp = [Spec]::Load((Join-Path $Root 'full\specdata\mini_0001.csv'))
$pk = $sp.Run('peaks', [double[]]@(0, 0.5, 60, 1200))
$fe = Get-Content 'full\api\fable-5-2\E_explain\mini_0001.json' -Raw -Encoding UTF8 | ConvertFrom-Json
$trace = "mini_0001  (key: B, a woman)   condition E, Fable 5.2`n" +
    "calls: " + ((@($fe.tool_calls) | ForEach-Object { $_.Trim() }) -join '  |  ') + "`n`n" +
    "> query_spectrogram(command='peaks', t0=0, t1=0.5, fmin=60, fmax=1200)`n" + $pk + "`n`n" +
    "Fable (E): ""A clear harmonic series confirms this: peaks at about 173, 351, 524, 700 ... Hz"" ... ""an animated adult man (C) is the best fit""   -> C  ✗`n" +
    "Fable (B): ""harmonics spaced roughly 200-250 Hz apart ... an adult female voice is the best fit""   -> B  ✓"

# L control, phonemic question
$l0174 = @($models.Keys | ForEach-Object { "$(if ($_ -eq 'opus') { 'Opus' } else { 'Fable' }) answered $($R[$_]['L']['mini_0174'].answer)" }) -join ' and '
$lsum = "Opus {0:N1}% &rarr; {1:N1}%, Fable {2:N1}% &rarr; {3:N1}% from A to L" -f $res.opus.A.all, $res.opus.L.all, $res.fable.A.all, $res.fable.L.all

$data = [ordered]@{ res = $res; n = $n; heat = $heat; heatCols = @($cols | ForEach-Object { [ordered]@{ label = $_[3] } }); tools = $tools; ex = $ex; trace = $trace; split = $split }
$json = $data | ConvertTo-Json -Depth 12 -Compress
$html = [IO.File]::ReadAllText((Join-Path $Root 'blog\template.html'), [Text.Encoding]::UTF8)
$html = $html.Replace('/*__DATA__*/', $json)
$html = $html.Replace('%%COST_TOTAL%%', ('{0:N0}' -f $cost)).Replace('%%L_SUMMARY%%', $lsum).Replace('%%E_CALLS_O%%', "$($avgCalls.opus)").Replace('%%E_CALLS_F%%', "$($avgCalls.fable)")
$html = $html.Replace('%%E_ZERO_O%%', "$($zero.opus)").Replace('%%FLIP%%', ("{0} of {1} ({2:N0}%)" -f $flip, $pairs, (100 * $flip / [math]::Max(1, $pairs))))
$html = $html.Replace('%%TEMPO_N%%', "$($tempo.n)").Replace('%%TEMPO_ON%%', "$([math]::Min($tempo.opus.onsets, $tempo.fable.onsets))").Replace('%%TEMPO_EO%%', "$($tempo.opus.E)").Replace('%%TEMPO_EF%%', "$($tempo.fable.E)")
$html = $html.Replace('%%L0174%%', "But with only the clip length and no picture at all (condition L), ${l0174}: the duration alone gives this one away.")
[IO.File]::WriteAllText((Join-Path $Root 'blog\reading-sound-without-ears.html'), $html, $enc)
# ---- personal-site export (bilingual) ----
if ($SiteDir) {
    $postDir = Join-Path $SiteDir 'posts\reading-sound-without-ears'; New-Item -ItemType Directory -Force $postDir | Out-Null
    $taskZh = @{ sound = '声音'; music = '音乐'; speech = '语音' }
    $skillZh = @{
        'Temporal Reasoning' = '时间推理'; 'Phonemic Stress Pattern Analysis' = '音素重音模式分析'; 'Phonological Sequence Decoding' = '音位序列解码'
        'Acoustic Scene Reasoning' = '声学场景推理'; 'Event-Based Sound Reasoning' = '基于事件的声音推理'; 'Ambient Sound Interpretation' = '环境声理解'
        'Acoustic Source Inference' = '声源推断'; 'Temporal Event Reasoning' = '时序事件推理'; 'Eco-Acoustic Knowledge' = '生态声学知识'
        'Sound-Based Event Recognition' = '基于声音的事件识别'; 'Rhythm and Tempo Understanding' = '节奏与速度理解'; 'Emotion State summarisation' = '情绪状态概括'
        'Dissonant Emotion Interpretation' = '矛盾情绪理解'; 'Instrumentation' = '乐器与配器'; 'Musical Texture Interpretation' = '音乐织体理解'
        'Musical Genre Reasoning' = '曲风推理'; 'Harmony and Chord Progressions' = '和声与和弦进行'; 'Emotional Tone Interpretation' = '情感基调理解'
        'Event-Based Knowledge Retrieval' = '基于事件的知识检索'; 'Melodic Structure Interpretation' = '旋律结构理解'; 'Counting' = '计数'
        'Multi Speaker Role Mapping' = '多说话人角色对应'; 'Conversational Fact Retrieval' = '对话事实检索'; 'Key highlight Extraction' = '要点提取'
        'Emotion Flip Detection' = '情绪转折检测'; 'Socio-cultural Interpretation' = '社会文化理解'; 'Lyrical Reasoning' = '歌词推理'
    }
    $labelZh = @{
        'switch clicks' = '开关咔嗒声'; 'boiling water' = '水沸腾'; 'doorbell' = '门铃'; 'clock ticks' = '钟表滴答'; 'chime ~750 Hz' = '铃声 ~750 Hz'; 'chime ~4.1 kHz' = '铃声 ~4.1 kHz'
        'ring ~2.7 kHz' = '余振 ~2.7 kHz'; 'ring ~6.4 kHz' = '余振 ~6.4 kHz'; 'hiss' = '嘶嘶声'; 'hiss continues' = '嘶嘶声持续'; 'speech' = '说话'
        'hiss band starts ~3.2 kHz' = '嘶声频带始于 ~3.2 kHz'; 'steady tone the whole clip' = '整段持续的单音'; '~2.7 kHz alarm tone' = '~2.7 kHz 报警音'
        '2nd harmonic ~5.6 kHz' = '二次谐波 ~5.6 kHz'; 'spin-down' = '减速'; 'spin-up, hold' = '加速并保持'; 'wave' = '浪'
        'models (B): F0 ~225 Hz' = '模型读图 (B)：F0 ~225 Hz'; 'tool (E): F0 173 Hz' = '工具测量 (E)：F0 173 Hz'
        'glide' = '滑音'; 'vibrato' = '颤音'; 'flat reed-like notes' = '平直的簧片音'; 'a voice enters' = '人声进入'
        '~40 syllable bursts ≈ 30–40 words' = '约 40 个音节簇 ≈ 30–40 个词'; 'sung F0 ~730 Hz' = '演唱 F0 ~730 Hz'; 'measured ~710–760 Hz' = '实测 ~710–760 Hz'
        'B = key' = 'B = 标准答案'; 'D = both models' = 'D = 两个模型'; 'loud noise, then drop' = '先响后弱的噪声'; 'streak?' = '竖纹？'
    }
    function LZh([string]$s) { if ($labelZh.ContainsKey($s)) { return $labelZh[$s] }; if ($s -match '^tap (\d)$') { return "敲击 $($Matches[1])" }; if ($s -match '^moo (\d)$') { return "哞 $($Matches[1])" }; $s }
    $notesZh = @{
        mini_0054 = '<b>读图：</b>先是稀疏的竖向咔嗒声，然后是一块偏低频的噪声，接着是两条缓慢衰减的水平音，最后是一排规则的梳状咔嗒声。两个模型都说出了全部四段及其时间，误差不到一秒。'
        mini_0061 = '<b>读图：</b>四个相同的竖向瞬态，间隔 2.8 秒，每个后面都跟着余振泛音。我们的起音检测器只找到其中三个（漏掉了 0 秒那个）；两个模型都数出四个，这是对的。没有图时两者都选了"3"。'
        mini_0080 = '<b>读图：</b>五块约 2 秒长的谐波块，中间隔着暗色空隙。起音检测器在这里报告了 20 个起音（每声"哞"都有好几个），所以直接数工具输出会出错；而在图上，分组一目了然。'
        mini_0068 = '<b>读图：</b>3 kHz 以上的一条噪声带几乎贯穿全段，而浊音谐波只出现在较短的片段里。"持续多久"的问题就变成了测量水平长度，模型做得很好。'
        mini_0854 = '<b>读图：</b>整整 10 秒里 2.7 kHz 附近有一条窄窄的水平线，5.6 kHz 附近还有一条较弱的谐波。两个模型都把"3 kHz 附近的恒定单音"和压电报警器联系起来。我们的峰值检测把 1 kHz 以上最强的峰定在 2,742 Hz。'
        mini_0864 = '<b>读图：</b>谐波先向下滑，静默，然后突然起音、谐波上扫到稳定音高，再次下滑。两个模型都描述为电机加速和减速，并仅凭形状排除了煎炸、打字和洗衣机。'
        mini_0825 = '<b>读图：</b>宽带噪声大约每 7&ndash;8 秒涌起又退去，没有谐波结构。两个模型都推断是海浪拍岸，并认为风声会更不规则。'
        mini_0001 = '<b>读图：</b>在放大视图里，两个模型都估计谐波间距约 200&ndash;250 Hz，判断为成年女性，这是对的。数值工具显示真实基频更低，约 175 Hz（谐波在 173、351、524 Hz），属于男女声重叠区间里偏低的女声；拿到这些精确数字后，两个模型都答成了"成年男性"。读图答对了，但部分是运气。'
        mini_0145 = '<b>读图：</b>四个轮次，之间有短暂停顿，每个轮次的谐波间距不同（约 100、150、350&ndash;400 和 170&ndash;200 Hz）。Fable 把第 2 和第 4 段归为同一人，结论是三个说话人。只看题目时的答案是"两个"。'
        mini_0352 = '<b>读图：</b>波动的泛音（颤音）和音与音之间平滑的滑音指向弓弦乐器；谐波间距紧密、能量下探到 100&ndash;200 Hz，说明更可能是大提琴而不是小提琴。两个模型都指出大提琴还是小提琴是最不确定的一步。'
        mini_0391 = '<b>读图：</b>前三秒是平直、密集的谐波堆叠，没有衰减也没有颤音：自由簧片乐器。钢琴的泛音会在每次击键后衰减；长笛的高次谐波很少。'
        mini_0174 = '<b>读图：</b>14.7 秒里几乎都是连续的浊音语音，大约 40 个类似音节的簇，所以约 35&ndash;40 个词，于是"32"是唯一合理的选项。%%L0174ZH%%'
        mini_0542 = '<b>读图：</b>一条滑动的人声旋律线，最低的强谐波在 700&ndash;800 Hz 附近。测量是对的；"对男歌手来说太高"的推断是错的。标准答案是"flat male vocals"（平直的男声）。'
        mini_0423 = '<b>读图：</b>题目问和弦 <code>E:9(*1)/3</code>（以 G# 为低音的 G#、B、D、F#）出现在哪个时间段。两个模型都选了 9.6&ndash;10.8 秒，因为 415 Hz 附近有一个泛音看起来像 G#。标准答案是 4.8&ndash;7.2 秒。在条件 E 里使用数值 <code>chroma</code> 工具后，两个模型都答对了。'
        mini_0711 = '<b>读图：</b>说话声底下有宽带噪声，开头很响然后减弱。Opus 把短的竖向条纹读成雨滴；Fable 把一阵阵的电平变化读成风（正确）。在主实验里两者都答了"下雨"；用数值工具（条件 E）时两者都答了"刮风"。'
    }
    $l0174zh = (@($models.Keys | ForEach-Object { "$(if ($_ -eq 'opus') { 'Opus' } else { 'Fable' }) 选了 $($R[$_]['L']['mini_0174'].answer)" }) -join '，')
    $sex = [ordered]@{}
    foreach ($id in $ex.Keys) {
        $e = $ex[$id]; $c = [ordered]@{}; foreach ($k in $e.Keys) { $c[$k] = $e[$k] }
        foreach ($f in @("$id.mp3", "${id}_full.jpg", "${id}_low.jpg")) { Copy-Item (Join-Path $Root "blog\assets\$f") (Join-Path $postDir $f) -Force }
        $c.audio = "reading-sound-without-ears/$id.mp3"; $c.full = "reading-sound-without-ears/${id}_full.jpg"; $c.low = "reading-sound-without-ears/${id}_low.jpg"
        $c.note = $e.note.Replace('%%L0174%%', "But with only the clip length and no picture at all (condition L), ${l0174}: the duration alone gives this one away.")
        $c.noteZh = $notesZh[$id].Replace('%%L0174ZH%%', "但在只给时长、完全不给图的条件 L 下，${l0174zh}：仅凭时长就能猜到这一题。")
        $c.taskZh = $taskZh[$e.task]; $c.subZh = $(if ($skillZh.ContainsKey($e.sub)) { $skillZh[$e.sub] } else { $e.sub })
        $mk = [ordered]@{}
        foreach ($k in 'spans', 'points', 'hlines') { if ($e.marks[$k]) { $mk[$k] = @($e.marks[$k] | ForEach-Object { $a = @($_); $lab = [string]$a[-1]; , @($a + @(LZh $lab)) }) } }
        $c.marks = $mk
        $sex[$id] = $c
    }
    $sheat = @($heat | ForEach-Object { $h = [ordered]@{}; foreach ($k in $_.Keys) { $h[$k] = $_[$k] }; $h.taskZh = $taskZh[$_.task]; $h.nameZh = $(if ($skillZh.ContainsKey($_.name)) { $skillZh[$_.name] } else { $_.name }); $h })
    $splitZh = @{ timing = @('声音何时发生', '事件时序、顺序、计数'); rhythm = @('节奏与速度', '音乐'); quality = @('听起来是什么样', '旋律、和声、音色、织体、曲风、情绪') }
    $ssplit = @($split | ForEach-Object { $g = [ordered]@{}; foreach ($k in $_.Keys) { $g[$k] = $_[$k] }; $g.labelZh = $splitZh[$_.key][0]; $g.subZh = $splitZh[$_.key][1]; $g })
    $sdata = [ordered]@{ res = $res; n = $n; heat = $sheat; heatCols = @($cols | ForEach-Object { [ordered]@{ label = $_[3] } }); tools = $tools; ex = $sex; trace = $trace; split = $ssplit }
    [IO.File]::WriteAllText((Join-Path $postDir 'data.js'), "window.RSWE = " + ($sdata | ConvertTo-Json -Depth 12 -Compress) + ";`n", $enc)
    Copy-Item (Join-Path $Root 'blog\site_figures.js') (Join-Path $postDir 'figures.js') -Force
    $lsumZh = "Opus {0:N1}% &rarr; {1:N1}%，Fable {2:N1}% &rarr; {3:N1}%" -f $res.opus.A.all, $res.opus.L.all, $res.fable.A.all, $res.fable.L.all
    $sp = [IO.File]::ReadAllText((Join-Path $Root 'blog\site_post.html'), [Text.Encoding]::UTF8)
    $sp = $sp.Replace('%%COST_TOTAL%%', ('{0:N0}' -f $cost)).Replace('%%L_SUMMARY_ZH%%', $lsumZh).Replace('%%L_SUMMARY%%', $lsum).Replace('%%E_CALLS_O%%', "$($avgCalls.opus)").Replace('%%E_CALLS_F%%', "$($avgCalls.fable)")
    $sp = $sp.Replace('%%E_ZERO_O%%', "$($zero.opus)").Replace('%%FLIP_ZH%%', ("{1} 组中有 {0} 组（{2:N0}%）" -f $flip, $pairs, (100 * $flip / [math]::Max(1, $pairs)))).Replace('%%FLIP%%', ("{0} of {1} ({2:N0}%)" -f $flip, $pairs, (100 * $flip / [math]::Max(1, $pairs))))
    $sp = $sp.Replace('%%TEMPO_N%%', "$($tempo.n)").Replace('%%TEMPO_ON%%', "$([math]::Min($tempo.opus.onsets, $tempo.fable.onsets))").Replace('%%TEMPO_EO%%', "$($tempo.opus.E)").Replace('%%TEMPO_EF%%', "$($tempo.fable.E)")
    [IO.File]::WriteAllText((Join-Path $SiteDir 'posts\reading-sound-without-ears.html'), $sp, $enc)
    $left = [regex]::Matches($sp, '%%[A-Z_0-9]+%%') | ForEach-Object Value | Sort-Object -Unique
    "site post written; assets: $((Get-ChildItem $postDir -File).Count) files, {0:N1} MB; unreplaced: $($left -join ',')" -f ((Get-ChildItem $postDir -File | Measure-Object Length -Sum).Sum / 1MB)
}

"cost={0:N2} flips={1}/{2} L: {3}" -f $cost, $flip, $pairs, $lsum
"size: {0:N1} MB" -f ((Get-Item blog\reading-sound-without-ears.html).Length / 1MB)
$res | ConvertTo-Json -Depth 4 -Compress
