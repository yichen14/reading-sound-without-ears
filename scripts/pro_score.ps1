# Score the MMAU-Pro pilot: pro\api\<model>\<cond>\<qid>.json against pro\answer_key.json (answer text -> option letter).
# Writes pro\results.csv and prints accuracy per model, condition and task, plus cost.
param([string]$Root, [string[]]$Conds = @('A', 'L', 'B', 'D', 'C'))
Set-Location $Root
$L = 'ABCDEFGH'
$q = Get-Content pro\questions.json -Raw -Encoding UTF8 | ConvertFrom-Json
$key = @{}; (Get-Content pro\answer_key.json -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object { $key[$_.qid] = "$($_.answer)".Trim() }
$dur = @{}; Import-Csv pro\durations.csv | ForEach-Object { $dur[$_.qid] = [double]$_.seconds }
$models = [ordered]@{ opus = 'opus-5-5'; fable = 'fable-5-2' }
$price = @{ 'opus-5-5' = @(4, 20); 'fable-5-2' = @(8, 40) }
$rows = foreach ($x in $q) {
    $gold = $null
    for ($i = 0; $i -lt $x.choices.Count; $i++) { $t = "$($x.choices[$i])" -replace '^\([A-H]\)\s*', ''; if ($t.Trim() -eq $key[$x.qid]) { $gold = [string]$L[$i] } }
    $r = [ordered]@{ qid = $x.qid; task = $x.task; seconds = $dur[$x.qid]; nchoices = $x.choices.Count; gold = $gold }
    foreach ($m in $models.Keys) { foreach ($c in $Conds) {
        $f = "pro\api\$($models[$m])\$c\$($x.qid).json"; $a = ''
        if (Test-Path $f) { $j = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json; $a = "$($j.answer)" }
        $r["${m}_$c"] = $a; $r["${m}_${c}_ok"] = [int]($a -eq $gold)
    } }
    [pscustomobject]$r
}
if (@($rows | Where-Object { -not $_.gold }).Count) { 'WARNING: gold not found for ' + (($rows | Where-Object { -not $_.gold } | ForEach-Object qid) -join ', ') }
$rows | Export-Csv pro\results.csv -NoTypeInformation -Encoding UTF8
foreach ($m in $models.Keys) {
    "{0,-6} {1,-7} " -f $m, 'all/n' + (($Conds | ForEach-Object { '{0,6}' -f $_ }) -join '')
    foreach ($t in 'all', 'sound', 'music', 'speech') {
        $s = @($rows | Where-Object { $t -eq 'all' -or $_.task -eq $t })
        "{0,-6} {1,-7} " -f '', "$t/$($s.Count)" + (($Conds | ForEach-Object { $c = $_; $k = @($s | Where-Object { $_."${m}_$c" }); if ($k.Count) { '{0,6}' -f ($s | Measure-Object "${m}_${c}_ok" -Sum).Sum } else { '     -' } }) -join '')
    }
}
$cost = 0
foreach ($m in $models.Values) { foreach ($c in $Conds) { Get-ChildItem "pro\api\$m\$c\*.json" -ErrorAction SilentlyContinue | ForEach-Object {
    $j = Get-Content $_.FullName -Raw | ConvertFrom-Json; $cost += ($j.input_tokens * $price[$m][0] + $j.output_tokens * $price[$m][1]) / 1e6 } } }
"cost: {0:n2} USD" -f $cost
