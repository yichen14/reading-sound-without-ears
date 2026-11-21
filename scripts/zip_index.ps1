# Read the central directory of a remote (zip64) archive with HTTP range requests and save it as CSV,
# so single files can be pulled out of the 47 GB MMAU-Pro data.zip without downloading all of it.
param([string]$Root, [string]$Url = 'https://huggingface.co/datasets/gamma-lab-umd/MMAU-Pro/resolve/main/data.zip', [long]$Size = 47506239410)
$ErrorActionPreference = 'Stop'
$tmp = Join-Path $Root 'data\mmau_pro\_tmp'
New-Item -ItemType Directory -Force $tmp | Out-Null

function Get-Range([long]$from, [long]$to, [string]$name) {
    $f = Join-Path $tmp $name
    & curl.exe -sS -L --retry 5 --retry-delay 3 -r "$from-$to" -o $f $Url
    if ($LASTEXITCODE -ne 0) { throw "curl failed ($LASTEXITCODE)" }
    $b = [System.IO.File]::ReadAllBytes($f)
    if ($b.Length -ne ($to - $from + 1)) { throw "short read: got $($b.Length), wanted $($to - $from + 1)" }
    return , $b
}

$tailLen = 131072
$tail = Get-Range ($Size - $tailLen) ($Size - 1) 'tail.bin'
# locate zip64 end-of-central-directory locator (PK\x06\x07), scanning backwards
$loc = -1
for ($i = $tail.Length - 20; $i -ge 0; $i--) {
    if ($tail[$i] -eq 0x50 -and $tail[$i + 1] -eq 0x4b -and $tail[$i + 2] -eq 0x06 -and $tail[$i + 3] -eq 0x07) { $loc = $i; break }
}
if ($loc -lt 0) { throw 'zip64 locator not found' }
$eocd64Off = [BitConverter]::ToInt64($tail, $loc + 8)
$rel = $eocd64Off - ($Size - $tailLen)
if ($rel -lt 0) { $rec = Get-Range $eocd64Off ($eocd64Off + 55) 'eocd64.bin'; $rel = 0 } else { $rec = $tail }
if ([BitConverter]::ToUInt32($rec, $rel) -ne 0x06064b50) { throw 'bad zip64 EOCD signature' }
$total = [BitConverter]::ToInt64($rec, $rel + 32)
$cdSize = [BitConverter]::ToInt64($rec, $rel + 40)
$cdOff = [BitConverter]::ToInt64($rec, $rel + 48)
"entries=$total cdSize=$cdSize cdOffset=$cdOff"

$cd = Get-Range $cdOff ($cdOff + $cdSize - 1) 'cd.bin'
$utf8 = [System.Text.Encoding]::UTF8
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('name,method,csize,usize,offset')
$p = 0; $n = 0
while ($p + 46 -le $cd.Length -and [BitConverter]::ToUInt32($cd, $p) -eq 0x02014b50) {
    $method = [BitConverter]::ToUInt16($cd, $p + 10)
    [long]$csize = [BitConverter]::ToUInt32($cd, $p + 20)
    [long]$usize = [BitConverter]::ToUInt32($cd, $p + 24)
    $nl = [BitConverter]::ToUInt16($cd, $p + 28)
    $el = [BitConverter]::ToUInt16($cd, $p + 30)
    $cl = [BitConverter]::ToUInt16($cd, $p + 32)
    [long]$off = [BitConverter]::ToUInt32($cd, $p + 42)
    $name = $utf8.GetString($cd, $p + 46, $nl)
    # zip64 extra field
    $e = $p + 46 + $nl; $eEnd = $e + $el
    while ($e + 4 -le $eEnd) {
        $id = [BitConverter]::ToUInt16($cd, $e); $sz = [BitConverter]::ToUInt16($cd, $e + 2)
        if ($id -eq 1) {
            $q = $e + 4
            if ($usize -eq 4294967295) { $usize = [BitConverter]::ToInt64($cd, $q); $q += 8 }
            if ($csize -eq 4294967295) { $csize = [BitConverter]::ToInt64($cd, $q); $q += 8 }
            if ($off -eq 4294967295) { $off = [BitConverter]::ToInt64($cd, $q); $q += 8 }
        }
        $e += 4 + $sz
    }
    [void]$sb.AppendLine(('"{0}",{1},{2},{3},{4}' -f $name.Replace('"', '""'), $method, $csize, $usize, $off))
    $p += 46 + $nl + $el + $cl; $n++
}
[System.IO.File]::WriteAllText((Join-Path $Root 'data\mmau_pro\zip_index.csv'), $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
"parsed $n entries"
