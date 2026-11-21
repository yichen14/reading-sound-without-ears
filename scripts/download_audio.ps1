# Download only the sampled audio clips listed in out\downloads.json.
#  kind=url : direct file from the HF datasets-server
#  kind=zip : one member of the remote MMAU-Pro data.zip, fetched by byte range and inflated locally
param([string]$Root, [string]$ZipUrl = 'https://huggingface.co/datasets/gamma-lab-umd/MMAU-Pro/resolve/main/data.zip')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
$dl = Get-Content (Join-Path $Root 'out\downloads.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$idx = @{}
Import-Csv (Join-Path $Root 'data\mmau_pro\zip_index.csv') | ForEach-Object { $idx[$_.name] = $_ }
$tmp = Join-Path $Root 'data\mmau_pro\_tmp'
New-Item -ItemType Directory -Force $tmp | Out-Null
$ok = 0; $fail = 0; $bytes = 0
foreach ($d in $dl) {
    $dest = Join-Path $Root $d.dest
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    if ((Test-Path $dest) -and (Get-Item $dest).Length -gt 0) { $ok++; $bytes += (Get-Item $dest).Length; continue }
    try {
        if ($d.kind -eq 'url') {
            & curl.exe -sS -L --retry 5 --retry-delay 3 -o $dest $d.src
            if ($LASTEXITCODE -ne 0) { throw "curl $LASTEXITCODE" }
        }
        else {
            $e = $idx[$d.src]
            if ($null -eq $e) { throw "not in zip index: $($d.src)" }
            [long]$off = $e.offset; [long]$cs = $e.csize
            $nameLen = [System.Text.Encoding]::UTF8.GetByteCount($e.name)
            $slack = 30 + $nameLen + 1024           # local header + generous room for its extra field
            $part = Join-Path $tmp 'member.bin'
            & curl.exe -sS -L --retry 5 --retry-delay 3 -r "$off-$($off + $slack + $cs - 1)" -o $part $ZipUrl
            if ($LASTEXITCODE -ne 0) { throw "curl $LASTEXITCODE" }
            $b = [System.IO.File]::ReadAllBytes($part)
            if ([BitConverter]::ToUInt32($b, 0) -ne 0x04034b50) { throw 'bad local header' }
            $start = 30 + [BitConverter]::ToUInt16($b, 26) + [BitConverter]::ToUInt16($b, 28)
            if ($e.method -eq '0') {
                $fs = [System.IO.File]::Create($dest); $fs.Write($b, $start, $cs); $fs.Close()
            }
            else {
                $ms = New-Object System.IO.MemoryStream($b, $start, $cs)
                $ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
                $fs = [System.IO.File]::Create($dest); $ds.CopyTo($fs); $fs.Close(); $ds.Close()
            }
            if ((Get-Item $dest).Length -ne [long]$e.usize) { throw "size mismatch for $($d.qid)" }
        }
        $ok++; $bytes += (Get-Item $dest).Length
    }
    catch { $fail++; "FAIL $($d.qid): $($_.Exception.Message)" }
}
"downloaded ok=$ok fail=$fail total={0:n1} MB" -f ($bytes / 1MB)
