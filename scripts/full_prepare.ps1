# Full MMAU test-mini run: refresh metadata (fresh signed audio URLs), write
#   full\questions.json  - all 1000 questions, no answers
#   full\answer_key.json - ground truth, only read by full_score.ps1
# and download every clip that is not on disk yet. Prints only counts.
param([string]$Root)
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
$enc = New-Object System.Text.UTF8Encoding($false)
Set-Location $Root

# ---- metadata ----
$all = New-Object System.Collections.ArrayList
$offset = 0; $total = $null
while ($true) {
    $url = "https://datasets-server.huggingface.co/rows?dataset=gamma-lab-umd/MMAU-test-mini&config=default&split=test&offset=$offset&length=100"
    $r = $null
    for ($try = 0; $try -lt 6; $try++) { try { $r = Invoke-RestMethod -Uri $url -TimeoutSec 120; break } catch { Start-Sleep -Seconds (3 * ($try + 1)) } }
    if ($null -eq $r) { throw "failed at offset $offset" }
    if ($null -eq $total) { $total = $r.num_rows_total }
    foreach ($x in $r.rows) { [void]$all.Add($x) }
    $offset += 100
    if ($offset -ge $total) { break }
}
"rows: $($all.Count)"

# ---- questions / key / download list ----
New-Item -ItemType Directory -Force 'full', 'data\mmau_mini\audio' | Out-Null
$questions = New-Object System.Collections.ArrayList
$key = New-Object System.Collections.ArrayList
$cfg = New-Object System.Collections.ArrayList
foreach ($x in ($all | Sort-Object row_idx)) {
    $a = $x.row.other_attributes | ConvertFrom-Json
    $qid = 'mini_{0:d4}' -f $x.row_idx
    $dest = "data/mmau_mini/audio/$qid.wav"
    [void]$questions.Add([pscustomobject]@{
        qid = $qid; dataset = 'MMAU-test-mini'; task = $a.task
        category = $a.category; subcategory = $a.'sub-category'; difficulty = $a.difficulty
        question = $x.row.instruction; choices = @($x.row.choices)
        audio = @($dest -replace '/', '\')
    })
    [void]$key.Add([pscustomobject]@{ qid = $qid; answer = $x.row.answer })
    if (-not ((Test-Path $dest) -and (Get-Item $dest).Length -gt 0)) {
        [void]$cfg.Add("url = `"$($x.row.context.src)`""); [void]$cfg.Add("output = `"$dest`"")
    }
}
[System.IO.File]::WriteAllText((Join-Path $Root 'full\questions.json'), (ConvertTo-Json -InputObject $questions -Depth 6), $enc)
[System.IO.File]::WriteAllText((Join-Path $Root 'full\answer_key.json'), (ConvertTo-Json -InputObject $key -Depth 4 -Compress), $enc)
"questions: $($questions.Count)"
$questions | Group-Object task | ForEach-Object { "  $($_.Name): $($_.Count)" }

# ---- download ----
"to download: $($cfg.Count / 2)"
if ($cfg.Count -gt 0) {
    $cfgFile = Join-Path $Root 'full\_curl.cfg'
    [System.IO.File]::WriteAllLines($cfgFile, $cfg, $enc)
    & curl.exe -sS -L --retry 5 --retry-delay 3 --parallel --parallel-max 8 -K $cfgFile
    Remove-Item $cfgFile
}
$files = Get-ChildItem 'data\mmau_mini\audio\mini_*.wav'
$missing = @($questions | Where-Object { -not ((Test-Path $_.audio[0]) -and (Get-Item $_.audio[0]).Length -gt 1000) })
"on disk: $($files.Count) files, {0:n1} MB, missing or tiny: $($missing.Count)" -f (($files | Measure-Object Length -Sum).Sum / 1MB)
if ($missing.Count) { ($missing | Select-Object -First 10 | ForEach-Object qid) -join ', ' }
