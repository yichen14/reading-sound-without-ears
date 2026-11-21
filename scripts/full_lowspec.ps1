# Second spectrogram image for conditions B and C: the 0-2 kHz zoom (audio resampled to 4 kHz, so the
# full height is 0-2 kHz), linear frequency, magma, 70 dB range, no axis labels, 1000x240 JPEG.
# Writes <Out>\spec_low\<qid>.jpg for every question in <Out>\questions.json.
param([string]$Root, [string]$Out = 'full', [int]$Parallel = 12)
Set-Location $Root
$q = Get-Content "$Out\questions.json" -Raw -Encoding UTF8 | ConvertFrom-Json
New-Item -ItemType Directory -Force "$Out\spec_low" | Out-Null
$vf = 'aformat=channel_layouts=mono,aresample=4000,showspectrumpic=s=1000x240:legend=0:scale=log:fscale=lin:color=magma:drange=70'
$running = @()
foreach ($x in $q) {
    $jpg = "$Out\spec_low\$($x.qid).jpg"
    if (Test-Path $jpg) { continue }
    while (@($running | Where-Object { -not $_.HasExited }).Count -ge $Parallel) { Start-Sleep -Milliseconds 100 }
    $args = @('-hide_banner', '-loglevel', 'error', '-y', '-i', "`"$($x.audio[0])`"", '-lavfi', "`"$vf`"", '-frames:v', '1', '-q:v', '3', "`"$jpg`"")
    $running += Start-Process -FilePath 'ffmpeg' -ArgumentList $args -NoNewWindow -PassThru
}
while (@($running | Where-Object { -not $_.HasExited }).Count -gt 0) { Start-Sleep -Milliseconds 200 }
"spec_low: $((Get-ChildItem "$Out\spec_low\*.jpg").Count)"
