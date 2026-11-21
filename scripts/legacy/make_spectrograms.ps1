# Render one PNG per clip: top panel = linear frequency 0-8 kHz, bottom panel = log frequency full band.
# Long clips are additionally cut into chunks so detail stays visible.
param([string]$Root, [string]$Only = '', [int]$ChunkSec = 0)
$ErrorActionPreference = 'Continue'
$q = Get-Content (Join-Path $Root 'out\questions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$outDir = Join-Path $Root 'out\spec'
New-Item -ItemType Directory -Force $outDir | Out-Null
$fc = '[0:a]aformat=channel_layouts=mono,asplit=2[x][y];' +
      '[x]aresample=16000,showspectrumpic=s=1280x400:legend=1:scale=log:fscale=lin:color=magma:drange=85,scale=1500:520[a];' +
      '[y]showspectrumpic=s=1280x400:legend=1:scale=log:fscale=log:color=magma:drange=85,scale=1500:520[b];[a][b]vstack[v]'
$n = 0
foreach ($x in $q) {
    if ($Only -and ($x.qid -notmatch $Only)) { continue }
    $in = Join-Path $Root $x.audio[0]
    if ($ChunkSec -le 0) {
        $png = Join-Path $outDir "$($x.qid).png"
        & ffmpeg -hide_banner -loglevel error -y -i $in -filter_complex $fc -map '[v]' -frames:v 1 $png
        $n++
    }
    else {
        $dur = [double](& ffprobe -v error -show_entries format=duration -of csv=p=0 $in)
        $k = 0
        for ($t = 0; $t -lt $dur; $t += $ChunkSec) {
            $png = Join-Path $outDir ("{0}_part{1:d2}_{2}s.png" -f $x.qid, $k, $t)
            & ffmpeg -hide_banner -loglevel error -y -ss $t -t $ChunkSec -i $in -filter_complex $fc -map '[v]' -frames:v 1 $png
            $k++; $n++
        }
    }
}
"rendered $n images"
