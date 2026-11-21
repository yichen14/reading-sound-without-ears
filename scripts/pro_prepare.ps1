# MMAU-Pro pilot: take the 30 MMAU-Pro questions drawn by sample.ps1 (out\questions.json, seed 20261110,
# 10 per sound/music/speech, single-audio multiple choice) into pro\, then render both spectrograms,
# measure durations and transcribe. The audio must already be on disk (download_audio.ps1).
# Afterwards: api_eval.ps1 -Out pro -Cond A|L|B|D|C for each model, then pro_score.ps1.
param([string]$Root)
$ErrorActionPreference = 'Stop'
Set-Location $Root
$enc = New-Object Text.UTF8Encoding($false)
New-Item -ItemType Directory -Force pro | Out-Null
$q = @(Get-Content out\questions.json -Raw -Encoding UTF8 | ConvertFrom-Json | Where-Object { $_.dataset -eq 'MMAU-Pro' })
$k = @(Get-Content out\answer_key.json -Raw -Encoding UTF8 | ConvertFrom-Json | Where-Object { $_.qid -like 'pro_*' })
[IO.File]::WriteAllText("$Root\pro\questions.json", (ConvertTo-Json -InputObject $q -Depth 6), $enc)
[IO.File]::WriteAllText("$Root\pro\answer_key.json", (ConvertTo-Json -InputObject $k -Depth 4 -Compress), $enc)
"pro questions: $($q.Count)"
& (Join-Path $PSScriptRoot 'full_thumbs.ps1') -Root $Root -Out pro      # spec_small + durations.csv
& (Join-Path $PSScriptRoot 'full_lowspec.ps1') -Root $Root -Out pro     # spec_low
& (Join-Path $PSScriptRoot 'asr.ps1') -Root $Root -Out pro              # Whisper transcripts (slow for the ~10 min clips)
# Three of the 30 clips (pro_0765, pro_0854, pro_0944) are corrupted in the public data.zip (see pro_check_long.ps1);
# pro\excluded_corrupt_audio.txt lists them and the reported pilot numbers leave them out.
