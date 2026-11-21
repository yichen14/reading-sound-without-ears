# Print the next batch of questions for one condition, with only the information that condition may use.
#   A : question + choices
#   B : + clip length + my A answer            (spectrogram is viewed separately)
#   D : + my A answer + Whisper transcript     (no spectrogram information)
#   C : + my A/B/D answers + B note + transcript
# The batch is the next <Count> questions (index order) that have no recorded answer for the condition.
# Never reads the answer key.
#   E : + clip length + my A answer + numeric spectral features (no picture, no transcript)
# -IdsFile restricts the batch to the question ids listed in that file (one per line).
param([string]$Root, [string]$Cond, [int]$Count = 10, [string]$Out = 'full', [string]$Task = '', [string]$IdsFile = '')
Set-Location $Root
$q = Get-Content "$Out\questions.json" -Raw -Encoding UTF8 | ConvertFrom-Json
function Load($c) {
    $h = @{}; $f = "$Out\ans_$c.tsv"
    if (Test-Path $f) { foreach ($l in [System.IO.File]::ReadAllLines((Join-Path $Root $f))) { $p = $l.Split("`t"); if ($p.Count -ge 2) { $h[$p[0]] = $p } } }
    $h
}
$done = Load $Cond
$a = if ($Cond -ne 'A') { Load 'A' } else { @{} }
$b = if ($Cond -eq 'C') { Load 'B' } else { @{} }
$d = if ($Cond -eq 'C') { Load 'D' } else { @{} }
$dur = @{}; if (Test-Path "$Out\durations.csv") { Import-Csv "$Out\durations.csv" | ForEach-Object { $dur[$_.qid] = $_.seconds } }
function Transcript($qid) {
    $f = "$Out\asr\$qid.srt"
    if (-not (Test-Path $f)) { return '(no transcript file)' }
    $lines = [System.IO.File]::ReadAllLines((Join-Path $Root $f), [System.Text.Encoding]::UTF8)
    $o = @(); $t = ''
    foreach ($l in $lines) {
        if ($l -match '^(\d\d):(\d\d):(\d\d)[,.](\d)\d* --> (\d\d):(\d\d):(\d\d)[,.](\d)') {
            $t = '{0}.{1}-{2}.{3}' -f ([int]$Matches[2] * 60 + [int]$Matches[3]), $Matches[4], ([int]$Matches[6] * 60 + [int]$Matches[7]), $Matches[8]
        }
        elseif ($l.Trim() -and $l -notmatch '^\d+$') { $o += "[$t] $($l.Trim())" }
    }
    if ($o.Count -eq 0) { '(empty)' } else { $o -join ' ' }
}
$only = $null; if ($IdsFile) { $only = @{}; Get-Content $IdsFile | ForEach-Object { if ($_.Trim()) { $only[$_.Trim()] = 1 } } }
$todo = @($q | Where-Object { -not $done.ContainsKey($_.qid) -and (-not $Task -or $_.task -eq $Task) -and ($null -eq $only -or $only.ContainsKey($_.qid)) })
"[$Cond] remaining $($todo.Count) of $($q.Count)"
$L = 'ABCDEFGH'
foreach ($x in ($todo | Select-Object -First $Count)) {
    $ch = for ($i = 0; $i -lt $x.choices.Count; $i++) { $c = "$($x.choices[$i])".Trim(); if ($c -match '^\(([A-H])\)\s*(.*)$' -and $Matches[1] -eq $L[$i]) { "$($L[$i])) $($Matches[2])" } else { "$($L[$i])) $c" } }
    $head = "$($x.qid.Substring(5)) [$($x.task)]"
    if ($Cond -ne 'A') { $head += " $($dur[$x.qid])s A=$($a[$x.qid][1])" }
    if ($Cond -eq 'C') { $head += " B=$($b[$x.qid][1]) D=$($d[$x.qid][1])"; if ($b[$x.qid].Count -ge 3 -and $b[$x.qid][2]) { $head += " note: $($b[$x.qid][2])" } }
    "$head | $($x.question) | $($ch -join ' | ')"
    if ($Cond -in 'D', 'C') { "    T: $(Transcript $x.qid)" }
    if ($Cond -eq 'E') { $ff = "$Out\feat\$($x.qid).txt"; if (Test-Path $ff) { Get-Content $ff } else { '(no features)' } }
}
