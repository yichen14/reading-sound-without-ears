# Record answers for one condition. -Lines is a block of lines "NNNN L optional note" (NNNN = 4-digit question index).
# Appends to <Out>\ans_<Cond>.tsv (qid, letter, note); refuses unknown ids, letters out of range and duplicates.
param([string]$Root, [string]$Cond, [string]$Lines, [string]$Out = 'full')
Set-Location $Root
$q = Get-Content "$Out\questions.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$n = @{}; foreach ($x in $q) { $n[$x.qid] = $x.choices.Count }
$f = Join-Path $Root "$Out\ans_$Cond.tsv"
$have = @{}; if (Test-Path $f) { foreach ($l in [System.IO.File]::ReadAllLines($f)) { $have[$l.Split("`t")[0]] = 1 } }
$add = @(); $bad = @()
foreach ($l in ($Lines -split "`n")) {
    $l = $l.Trim(); if (-not $l) { continue }
    if ($l -notmatch '^(\d{4})\s+([A-H])(?:\s+(.*))?$') { $bad += "unparsed: $l"; continue }
    $qid = "mini_$($Matches[1])"; $let = $Matches[2]; $note = "$($Matches[3])" -replace "`t", ' '
    if (-not $n.ContainsKey($qid)) { $bad += "unknown: $qid"; continue }
    if ('ABCDEFGH'.IndexOf($let) -ge $n[$qid]) { $bad += "letter out of range: $l"; continue }
    if ($have.ContainsKey($qid)) { $bad += "duplicate: $qid"; continue }
    $have[$qid] = 1; $add += "$qid`t$let`t$note"
}
if ($add.Count) { [System.IO.File]::AppendAllLines($f, [string[]]$add, (New-Object System.Text.UTF8Encoding($false))) }
"[$Cond] recorded $($add.Count), total $($have.Count)/$($q.Count)"
$bad
