# Score answer files against the hidden key. Usage: score.ps1 -Root . -Files out\answers_A_text_only.json,out\answers_B...
param([string]$Root, [string[]]$Files)
$ErrorActionPreference = 'Stop'
function Norm([string]$s) { (($s -replace '^\s*\(([A-Pa-p])\)\s*', '') -replace '[^\p{L}\p{N}]+', ' ').Trim().ToLowerInvariant() }
$q = Get-Content (Join-Path $Root 'out\questions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$key = @{}; (Get-Content (Join-Path $Root 'out\answer_key.json') -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { $key[$_.qid] = $_.answer }
$letters = 'ABCDEFGHIJKLMNOP'
# resolve the correct letter for every question
$gold = @{}; $bad = @()
foreach ($x in $q) {
    $k = Norm $key[$x.qid]; $hit = @()
    for ($i = 0; $i -lt $x.choices.Count; $i++) { if ((Norm $x.choices[$i]) -eq $k) { $hit += $letters[$i] } }
    if ($hit.Count -eq 1) { $gold[$x.qid] = [string]$hit[0] } else { $bad += $x.qid }
}
if ($bad.Count) { "WARNING: key did not match exactly one choice for: $($bad -join ', ')" }
$rows = @{}
foreach ($x in $q) { $rows[$x.qid] = [ordered]@{ qid = $x.qid; dataset = $x.dataset; task = $x.task; nchoices = $x.choices.Count; gold = $gold[$x.qid] } }
foreach ($f in $Files) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($f) -replace '^answers_', ''
    $a = Get-Content (Join-Path $Root $f) -Raw -Encoding UTF8 | ConvertFrom-Json
    ""; "===== $name ====="
    $stat = @{}
    foreach ($x in $q) {
        if (-not $gold.ContainsKey($x.qid)) { continue }
        $mine = $a.($x.qid); $ok = ($mine -eq $gold[$x.qid])
        $rows[$x.qid][$name] = $mine; $rows[$x.qid]["${name}_ok"] = [int]$ok
        foreach ($g in @("$($x.dataset)", "$($x.dataset) / $($x.task)", 'ALL')) {
            if (-not $stat.ContainsKey($g)) { $stat[$g] = @(0, 0) }
            $stat[$g][1]++; if ($ok) { $stat[$g][0]++ }
        }
    }
    foreach ($g in ($stat.Keys | Sort-Object)) { "{0,-28} {1,2}/{2,-2} = {3,5:p1}" -f $g, $stat[$g][0], $stat[$g][1], ($stat[$g][0] / $stat[$g][1]) }
}
$rows.Values | ForEach-Object { [pscustomobject]$_ } | Sort-Object qid | Export-Csv (Join-Path $Root 'out\results.csv') -NoTypeInformation -Encoding UTF8
# chance level
$ch = ($q | ForEach-Object { 1.0 / $_.choices.Count } | Measure-Object -Average).Average
""; "expected accuracy of uniform random guessing over this sample: {0:p1}" -f $ch
