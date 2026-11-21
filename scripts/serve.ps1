# Minimal static file server for previewing the blog: http://localhost:8765/
# Supports single HTTP Range requests (206), which browsers need to seek inside audio files.
param([string]$Dir = (Join-Path $PSScriptRoot '..\blog'), [int]$Port = 8765, [string]$Index = 'reading-sound-without-ears.html')
$Dir = (Resolve-Path $Dir).Path
$l = New-Object Net.HttpListener; $l.Prefixes.Add("http://localhost:$Port/"); $l.Start()
"serving $Dir on http://localhost:$Port/"
$types = @{ '.html' = 'text/html; charset=utf-8'; '.mp3' = 'audio/mpeg'; '.jpg' = 'image/jpeg'; '.png' = 'image/png'; '.pdf' = 'application/pdf'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8' }
while ($l.IsListening) {
    $c = $l.GetContext(); $p = [Uri]::UnescapeDataString($c.Request.Url.AbsolutePath.TrimStart('/')); if (-not $p) { $p = $Index }
    $f = Join-Path $Dir $p
    if ((Test-Path $f -PathType Leaf) -and ((Resolve-Path $f).Path.StartsWith($Dir))) {
        $b = [IO.File]::ReadAllBytes($f); $t = $types[[IO.Path]::GetExtension($f)]; if ($t) { $c.Response.ContentType = $t }
        $c.Response.AddHeader('Accept-Ranges', 'bytes'); $c.Response.AddHeader('Cache-Control', 'no-cache')
        $start = 0; $end = $b.Length - 1
        $range = $c.Request.Headers['Range']
        if ($range -match '^bytes=(\d*)-(\d*)$') {
            if ($Matches[1]) { $start = [long]$Matches[1]; if ($Matches[2]) { $end = [math]::Min([long]$Matches[2], $b.Length - 1) } }
            elseif ($Matches[2]) { $start = [math]::Max(0, $b.Length - [long]$Matches[2]) }
            $c.Response.StatusCode = 206; $c.Response.AddHeader('Content-Range', "bytes $start-$end/$($b.Length)")
        }
        $len = $end - $start + 1
        $c.Response.ContentLength64 = $len; try { $c.Response.OutputStream.Write($b, [int]$start, [int]$len) } catch {}
    } else { $c.Response.StatusCode = 404 }
    try { $c.Response.Close() } catch {}
}
