# Minimal static file server for previewing the blog: http://localhost:8765/
param([string]$Dir = (Join-Path $PSScriptRoot '..\blog'), [int]$Port = 8765)
$Dir = (Resolve-Path $Dir).Path
$l = New-Object Net.HttpListener; $l.Prefixes.Add("http://localhost:$Port/"); $l.Start()
"serving $Dir on http://localhost:$Port/"
$types = @{ '.html' = 'text/html; charset=utf-8'; '.mp3' = 'audio/mpeg'; '.jpg' = 'image/jpeg'; '.js' = 'text/javascript'; '.css' = 'text/css' }
while ($l.IsListening) {
    $c = $l.GetContext(); $p = [Uri]::UnescapeDataString($c.Request.Url.AbsolutePath.TrimStart('/')); if (-not $p) { $p = 'reading-sound-without-ears.html' }
    $f = Join-Path $Dir $p
    if ((Test-Path $f -PathType Leaf) -and ((Resolve-Path $f).Path.StartsWith($Dir))) {
        $b = [IO.File]::ReadAllBytes($f); $t = $types[[IO.Path]::GetExtension($f)]; if ($t) { $c.Response.ContentType = $t }
        $c.Response.ContentLength64 = $b.Length; try { $c.Response.OutputStream.Write($b, 0, $b.Length) } catch {}
    } else { $c.Response.StatusCode = 404 }
    try { $c.Response.Close() } catch {}
}
