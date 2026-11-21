# Batch semitone-energy (chroma) analysis, same method as chroma.ps1 but one compact line per window.
# -Specs "NNNN:from:to[:step]; NNNN:from:to ..."  (NNNN = question index; step omitted = one window for the whole span)
param([string]$Root, [string]$Specs, [string]$Out = 'full')
$ErrorActionPreference = 'Stop'
Set-Location $Root
Add-Type -TypeDefinition @'
using System;
using System.Text;
public static class Chq {
    static readonly string[] N = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"};
    public static string Run(short[] x, int sr, double from, double to, double step) {
        var sb = new StringBuilder();
        if (to * sr > x.Length) to = (double)x.Length / sr;
        for (double t = from; t + step <= to + 1e-6; t += step) {
            int s0 = (int)(t * sr), wl = (int)(step * sr);
            if (wl < 256) break;
            int lo = 28, hi = 84;
            double[] mag = new double[hi + 1];
            for (int m = lo; m <= hi; m++) {
                double f = 440.0 * Math.Pow(2, (m - 69) / 12.0), re = 0, im = 0, k = 2 * Math.PI * f / sr;
                for (int i = 0; i < wl; i++) { double w = 0.5 - 0.5 * Math.Cos(2 * Math.PI * i / (wl - 1)); double v = x[s0 + i] * w; re += v * Math.Cos(k * i); im -= v * Math.Sin(k * i); }
                mag[m] = Math.Sqrt(re * re + im * im);
            }
            double[] ch = new double[12];
            for (int m = 36; m <= hi; m++) ch[m % 12] += mag[m] * (m <= 72 ? 1.0 : 0.5);
            int bass = lo; for (int m = lo; m <= 55; m++) if (mag[m] > mag[bass]) bass = m;
            double mx = 0; for (int i = 0; i < 12; i++) if (ch[i] > mx) mx = ch[i];
            int[] idx = new int[12]; for (int i = 0; i < 12; i++) idx[i] = i;
            Array.Sort(idx, (a, b) => ch[b].CompareTo(ch[a]));
            sb.AppendFormat("{0,6:F2}-{1,-6:F2} bass={2,-3} ", t, t + step, N[bass % 12] + (bass / 12 - 1));
            for (int i = 0; i < 6; i++) sb.AppendFormat("{0}{1:F0} ", N[idx[i]], 100 * ch[idx[i]] / (mx + 1e-9));
            double bestS = -1; string best = "";
            for (int r = 0; r < 12; r++) for (int q = 0; q < 2; q++) {
                double s = ch[r] + ch[(r + (q == 0 ? 4 : 3)) % 12] * 0.9 + ch[(r + 7) % 12] * 0.9;
                if (s > bestS) { bestS = s; best = N[r] + (q == 0 ? "" : "m"); }
            }
            sb.AppendFormat("~{0}\n", best);
        }
        return sb.ToString();
    }
}
'@
$sr = 11025; $cache = @{}
foreach ($s in ($Specs -split ';')) {
    $p = $s.Trim() -split ':'; if ($p.Count -lt 3) { continue }
    $qid = "mini_$($p[0])"
    if (-not $cache.ContainsKey($qid)) {
        $tmp = [System.IO.Path]::GetTempFileName()
        & ffmpeg -hide_banner -loglevel error -y -i "data\mmau_mini\audio\$qid.wav" -ac 1 -ar $sr -f s16le $tmp
        $bytes = [System.IO.File]::ReadAllBytes($tmp); Remove-Item $tmp
        $pcm = New-Object 'System.Int16[]' ([int]($bytes.Length / 2)); [System.Buffer]::BlockCopy($bytes, 0, $pcm, 0, $pcm.Length * 2); $cache[$qid] = $pcm
    }
    $from = [double]$p[1]; $to = [double]$p[2]; $step = if ($p.Count -ge 4) { [double]$p[3] } else { $to - $from }
    "$($p[0]):"; [Chq]::Run($cache[$qid], $sr, $from, $to, $step).TrimEnd()
}
