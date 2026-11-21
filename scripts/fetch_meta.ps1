# Fetch all question metadata for MMAU test-mini and MMAU-Pro via the HF datasets-server rows API.
# Writes the raw rows (including answers) to data\<name>\rows_full.json. Nothing answer-related is printed.
param([string]$Root)
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

function Get-Rows($dataset, $outFile) {
    $all = New-Object System.Collections.ArrayList
    $offset = 0; $total = $null
    while ($true) {
        $url = "https://datasets-server.huggingface.co/rows?dataset=$dataset&config=default&split=test&offset=$offset&length=100"
        $r = $null
        for ($try = 0; $try -lt 6; $try++) {
            try { $r = Invoke-RestMethod -Uri $url -TimeoutSec 120; break }
            catch { Start-Sleep -Seconds (3 * ($try + 1)) }
        }
        if ($null -eq $r) { throw "failed at offset $offset" }
        if ($null -eq $total) { $total = $r.num_rows_total }
        foreach ($x in $r.rows) { [void]$all.Add($x) }
        $offset += 100
        if ($offset -ge $total) { break }
    }
    New-Item -ItemType Directory -Force (Split-Path $outFile) | Out-Null
    $json = ConvertTo-Json -InputObject $all -Depth 8 -Compress
    [System.IO.File]::WriteAllText($outFile, $json, (New-Object System.Text.UTF8Encoding($false)))
    "$dataset : $($all.Count) rows -> $outFile"
}

Get-Rows 'gamma-lab-umd/MMAU-test-mini' (Join-Path $Root 'data\mmau_mini\rows_full.json')
Get-Rows 'gamma-lab-umd/MMAU-Pro'       (Join-Path $Root 'data\mmau_pro\rows_full.json')
