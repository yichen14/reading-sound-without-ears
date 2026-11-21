# Collect API results into answer files for full_score.ps1 and report token use and cost.
#   writes <Out>\ans_<model>_<cond>.tsv  (e.g. ans_opus55_B.tsv)
# Prices per million tokens (standard API, no batch discount): input, output, cache read, cache write (5 min).
param([string]$Root, [string]$Out = 'full', [string]$IdsFile = '')
Set-Location $Root
$price = @{
    'opus-5-5'  = @{ in = 4.0; out = 20.0; cr = 0.20; cw = 5.0 }
    'fable-5-2' = @{ in = 8.0; out = 40.0; cr = 0.20; cw = 10.0 }
}
$only = $null; if ($IdsFile) { $only = @{}; Get-Content $IdsFile | ForEach-Object { if ($_.Trim()) { $only[$_.Trim()] = 1 } } }
$enc = New-Object Text.UTF8Encoding($false)
$rows = @()
foreach ($md in (Get-ChildItem "$Out\api" -Directory -ErrorAction SilentlyContinue)) {
    foreach ($cd in (Get-ChildItem $md.FullName -Directory)) {
        $lines = @(); $n = 0; $na = 0; $err = 0; $in = 0; $outT = 0; $cr = 0; $cw = 0; $rounds = 0; $refuse = 0; $maxtok = 0
        foreach ($f in (Get-ChildItem "$($cd.FullName)\*.json")) {
            $r = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $only -and -not $only.ContainsKey($r.qid)) { continue }
            $n++; $in += $r.input_tokens; $outT += $r.output_tokens; $cr += $r.cache_read; $cw += $r.cache_write; $rounds += $r.rounds
            if ($r.error) { $err++ }
            if ($r.stop_reason -eq 'refusal') { $refuse++ }
            if ($r.stop_reason -eq 'max_tokens') { $maxtok++ }
            if ($r.answer) { $lines += "$($r.qid)`t$($r.answer)`tapi" } else { $na++; $lines += "$($r.qid)`t-`tno answer ($($r.stop_reason) $($r.error))" }
        }
        $tag = ($md.Name -replace '-', '') + "_$($cd.Name)"
        if ($null -eq $only) { [IO.File]::WriteAllLines((Join-Path $Root "$Out\ans_$tag.tsv"), [string[]]$lines, $enc) }
        $p = $price[$md.Name]; $cost = ($in * $p.in + $outT * $p.out + $cr * $p.cr + $cw * $p.cw) / 1e6
        $rows += [pscustomobject]@{ model = $md.Name; cond = $cd.Name; n = $n; no_answer = $na; errors = $err; refusals = $refuse; max_tokens = $maxtok
            avg_rounds = [math]::Round($rounds / [math]::Max(1, $n), 2); avg_in = [int]($in / [math]::Max(1, $n)); avg_out = [int]($outT / [math]::Max(1, $n))
            avg_cache_read = [int]($cr / [math]::Max(1, $n)); cost_usd = [math]::Round($cost, 3); cost_per_q = [math]::Round($cost / [math]::Max(1, $n), 4) }
    }
}
$rows | Format-Table -AutoSize | Out-String -Width 220
