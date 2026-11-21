# Launch the full run: one background process per model and condition (E is split into parts because
# its tool loops are slow). Each process calls api_eval.ps1 and logs to full\api\logs\<tag>.log/.err.
# Results already on disk are skipped, so this can be re-run to resume. Needs ANTHROPIC_API_KEY.
param([string]$Root, [int]$Workers = 10)
Set-Location $Root
New-Item -ItemType Directory -Force "$Root\full\api\logs" | Out-Null
$runs = @()
foreach ($m in 'claude-opus-5-5', 'claude-fable-5-2') { foreach ($c in 'A', 'L', 'B', 'C', 'D') { $runs += , @($m, $c, '') } }
for ($k = 0; $k -lt 3; $k++) { $runs += , @('claude-opus-5-5', 'E', "full\e_splits\E_opus-5-5_$k.txt") }
for ($k = 0; $k -lt 4; $k++) { $runs += , @('claude-fable-5-2', 'E', "full\e_splits\E_fable-5-2_$k.txt") }
$procs = foreach ($r in $runs) {
    $tag = ($r[0] -replace 'claude-', '') + "_" + $r[1] + $(if ($r[2]) { '_p' + $r[2].Substring($r[2].Length - 5, 1) } else { '' })
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$Root\scripts\api_eval.ps1`" -Root `"$Root`" -Model $($r[0]) -Cond $($r[1]) -Workers $Workers"
    if ($r[2]) { $args += " -IdsFile `"$($r[2])`"" }
    Start-Process powershell -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput "$Root\full\api\logs\$tag.log" -RedirectStandardError "$Root\full\api\logs\$tag.err"
}
"started $(@($procs).Count) processes at $(Get-Date -Format HH:mm)"
$procs | Wait-Process
"all finished at $(Get-Date -Format HH:mm)"
# Explanation re-runs on 32 questions (observations + answer), used for the examples in the blog:
#   api_eval.ps1 -Root . -Model <model> -Cond B -Explain -Tag _explain -IdsFile full\explain_ids.txt   (same for E and L)
