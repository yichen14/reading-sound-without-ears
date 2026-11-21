# Spectrogram thumbnails for every question in <Out>\questions.json (same picture as the earlier
# out\spec_small thumbnails: linear 0-8 kHz panel, magma, 85 dB range, 1000 px wide JPEG).
# Also writes <Out>\durations.csv (qid, seconds).
param([string]$Root, [string]$Out = 'full', [int]$Parallel = 12)
Set-Location $Root
$q = Get-Content "$Out\questions.json" -Raw -Encoding UTF8 | ConvertFrom-Json
New-Item -ItemType Directory -Force "$Out\spec_small" | Out-Null
$vf = 'aformat=channel_layouts=mono,aresample=16000,showspectrumpic=s=1280x400:legend=1:scale=log:fscale=lin:color=magma:drange=85,scale=1500:520,crop=1420:440:0:40,scale=1000:-2'
$running = @()
foreach ($x in $q) {
    $jpg = "$Out\spec_small\$($x.qid).jpg"
    if (Test-Path $jpg) { continue }
    while (@($running | Where-Object { -not $_.HasExited }).Count -ge $Parallel) { Start-Sleep -Milliseconds 100 }
    $args = @('-hide_banner', '-loglevel', 'error', '-y', '-i', "`"$($x.audio[0])`"", '-lavfi', "`"$vf`"", '-frames:v', '1', '-q:v', '3', "`"$jpg`"")
    $running += Start-Process -FilePath 'ffmpeg' -ArgumentList $args -NoNewWindow -PassThru
}
while (@($running | Where-Object { -not $_.HasExited }).Count -gt 0) { Start-Sleep -Milliseconds 200 }
$rows = foreach ($x in $q) {
    $d = & ffprobe -v error -show_entries format=duration -of csv=p=0 $x.audio[0]
    [pscustomobject]@{ qid = $x.qid; seconds = [math]::Round([double]$d, 1) }
}
$rows | Export-Csv "$Out\durations.csv" -NoTypeInformation -Encoding UTF8
$m = $rows | Measure-Object seconds -Average -Minimum -Maximum -Sum
"thumbs: $((Get-ChildItem "$Out\spec_small\*.jpg").Count); duration avg={0:n1}s min={1}s max={2}s total={3:n0}s" -f $m.Average, $m.Minimum, $m.Maximum, $m.Sum
