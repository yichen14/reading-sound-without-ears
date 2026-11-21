# Score the full test-mini run. Reads <Out>\ans_<Cond>.tsv and the hidden key; prints only aggregate accuracy.
# Only questions answered in every listed condition (and in -IdsFile, if given) are scored, so the conditions are compared on the same items.
# A question whose key text matches several (duplicated) choices counts as correct for any of those letters.
param([string]$Root, [string[]]$Conds = @('A', 'B', 'C', 'D'), [string]$Out = 'full', [string]$IdsFile = '', [string]$Csv = 'results.csv')
$ErrorActionPreference = 'Stop'
Set-Location $Root
function Norm([string]$s) { (($s -replace '^\s*\(([A-Pa-p])\)\s*', '') -replace '[^\p{L}\p{N}]+', ' ').Trim().ToLowerInvariant() }
$q = Get-Content "$Out\questions.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$key = @{}; (Get-Content "$Out\answer_key.json" -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { $key[$_.qid] = $_.answer }
$only = $null; if ($IdsFile) { $only = @{}; Get-Content $IdsFile | ForEach-Object { if ($_.Trim()) { $only[$_.Trim()] = 1 } } }
$LET = 'ABCDEFGH'
$ans = @{}
foreach ($c in $Conds) { $h = @{}; foreach ($l in [System.IO.File]::ReadAllLines((Join-Path $Root "$Out\ans_$c.tsv"))) { $p = $l.Split("`t"); if ($p.Count -ge 2) { $h[$p[0]] = $p } }; $ans[$c] = $h }
$carried = @{}; foreach ($l in [System.IO.File]::ReadAllLines((Join-Path $Root "$Out\ans_A.tsv"))) { $p = $l.Split("`t"); if ($p.Count -ge 3 -and $p[2] -like 'carried over*') { $carried[$p[0]] = 1 } }
$rows = @(); $nokey = 0; $stat = @{}
foreach ($x in $q) {
    if ($null -ne $only -and -not $only.ContainsKey($x.qid)) { continue }
    $all = $true; foreach ($c in $Conds) { if (-not $ans[$c].ContainsKey($x.qid)) { $all = $false } }; if (-not $all) { continue }
    $k = Norm $key[$x.qid]; $gold = @(); for ($i = 0; $i -lt $x.choices.Count; $i++) { if ((Norm $x.choices[$i]) -eq $k) { $gold += [string]$LET[$i] } }
    if ($gold.Count -eq 0) { $nokey++; continue }
    $row = [ordered]@{ qid = $x.qid; task = $x.task; subcategory = $x.subcategory; difficulty = $x.difficulty; nchoices = $x.choices.Count; gold = ($gold -join '/'); fresh = [int](-not $carried.ContainsKey($x.qid)) }
    foreach ($c in $Conds) {
        $ok = $gold -contains $ans[$c][$x.qid][1]; $row[$c] = $ans[$c][$x.qid][1]; $row["${c}_ok"] = [int]$ok
        $groups = @('ALL', "task: $($x.task)"); if (-not $carried.ContainsKey($x.qid)) { $groups += 'ALL (not in the earlier 90-question run)' }
        foreach ($g in $groups) { $kk = "$g|$c"; if (-not $stat.ContainsKey($kk)) { $stat[$kk] = @(0, 0) }; $stat[$kk][1]++; if ($ok) { $stat[$kk][0]++ } }
    }
    $rows += [pscustomobject]$row
}
"scored questions: $($rows.Count) (unmatched key: $nokey)"
foreach ($g in ($stat.Keys | ForEach-Object { $_.Split('|')[0] } | Sort-Object -Unique)) {
    $line = "{0,-44}" -f $g
    foreach ($c in $Conds) { $s = $stat["$g|$c"]; $line += " {0}: {1,3}/{2,-4} {3,6:p1} " -f $c, $s[0], $s[1], ($s[0] / [math]::Max(1, $s[1])) }
    $line
}
if ($rows.Count) { $rows | Export-Csv "$Out\$Csv" -NoTypeInformation -Encoding UTF8 }
$ch = ($rows | ForEach-Object { 1.0 / $_.nchoices } | Measure-Object -Average).Average
"uniform random guessing on these questions: {0:p1}" -f $ch
