# Transcribe the selected clips with ffmpeg's built-in whisper filter (whisper.cpp, small multilingual model).
# Runs a few ffmpeg processes in parallel. Output: out\asr\<qid>.srt
param([string]$Root, [string]$Match = '.', [int]$Parallel = 3, [int]$MaxSec = 100000, [string]$Out = 'out')
Set-Location $Root
$q = Get-Content "$Out\questions.json" -Raw -Encoding UTF8 | ConvertFrom-Json
New-Item -ItemType Directory -Force "$Out\asr" | Out-Null
$todo = @($q | Where-Object { $_.qid -match $Match -and -not (Test-Path "$Out\asr\$($_.qid).srt") })
$running = @()
foreach ($x in $todo) {
    while (@($running | Where-Object { -not $_.HasExited }).Count -ge $Parallel) { Start-Sleep -Milliseconds 500 }
    $in = $x.audio[0]
    $af = "aformat=channel_layouts=mono,aresample=16000,whisper=model=data/models/ggml-small.bin:language=auto:queue=30:destination=$Out/asr/$($x.qid).srt:format=srt"
    $args = @('-hide_banner', '-loglevel', 'error', '-y', '-t', "$MaxSec", '-i', "`"$in`"", '-af', "`"$af`"", '-f', 'null', '-')
    $running += Start-Process -FilePath 'ffmpeg' -ArgumentList $args -NoNewWindow -PassThru
}
while (@($running | Where-Object { -not $_.HasExited }).Count -gt 0) { Start-Sleep -Milliseconds 500 }
"asr done: $($todo.Count) clips"
