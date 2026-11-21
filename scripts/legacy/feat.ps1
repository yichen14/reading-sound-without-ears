# Condition E: numeric spectral features instead of a spectrogram picture.
# For each clip writes <Out>\feat\<qid>.txt : a few global lines plus one row per time step:
#   time  L<loudness digit>  <10 band digits>  f<flatness digit>  <F0 Hz or ->  <up to 3 spectral peaks Hz>  <top 3 pitch classes>
# Digits: 9 = within 6 dB of the clip's loudest value, each step down = 6 dB, 0 = more than 54 dB below.
# Bands (Hz): 0-125, 125-250, 250-500, 500-1k, 1k-1.5k, 1.5k-2k, 2k-3k, 3k-4k, 4k-6k, 6k-8k.
# Flatness: 0 = pure tones ... 9 = noise-like.
param([string]$Root, [string]$Ids, [string]$Out = 'full')
$ErrorActionPreference = 'Stop'
Set-Location $Root
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
public static class Feat {
    static readonly string[] PC = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"};
    static void FFT(double[] re, double[] im) {
        int n = re.Length;
        for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; (j & bit) != 0; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { double t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; } }
        for (int len = 2; len <= n; len <<= 1) {
            double ang = -2 * Math.PI / len; double wr = Math.Cos(ang), wi = Math.Sin(ang);
            for (int i = 0; i < n; i += len) { double cr = 1, ci = 0;
                for (int k = 0; k < len / 2; k++) { int a = i + k, b = i + k + len / 2;
                    double xr = re[b] * cr - im[b] * ci, xi = re[b] * ci + im[b] * cr;
                    re[b] = re[a] - xr; im[b] = im[a] - xi; re[a] += xr; im[a] += xi;
                    double nr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = nr; } } }
    }
    static int Dig(double v, double max) { if (v <= 0) return 0; double db = 10 * Math.Log10(v / max); int d = 9 + (int)Math.Ceiling(db / 6.0 - 1e-9); return d < 0 ? 0 : (d > 9 ? 9 : d); }
    public static string Run(short[] x, int sr) {
        int N = 1024, hop = 256, K = N / 2 + 1;
        int F = (x.Length - N) / hop + 1; if (F < 4) return "too short";
        double dur = (double)x.Length / sr;
        double[] win = new double[N]; for (int i = 0; i < N; i++) win[i] = 0.5 - 0.5 * Math.Cos(2 * Math.PI * i / (N - 1));
        double[] edges = {0, 125, 250, 500, 1000, 1500, 2000, 3000, 4000, 6000, 8000};
        double[][] P = new double[F][]; double[] tot = new double[F], flat = new double[F], flux = new double[F], f0 = new double[F];
        double[] re = new double[N], im = new double[N], prev = new double[K];
        for (int f = 0; f < F; f++) {
            int s0 = f * hop; double e0 = 0;
            for (int i = 0; i < N; i++) { re[i] = x[s0 + i] * win[i]; im[i] = 0; e0 += (double)x[s0 + i] * x[s0 + i]; }
            FFT(re, im);
            double[] p = new double[K]; double sum = 0, ls = 0, fl = 0; int cnt = 0;
            for (int k = 0; k < K; k++) { p[k] = re[k] * re[k] + im[k] * im[k]; sum += p[k]; double m = Math.Sqrt(p[k]); if (m > prev[k]) fl += m - prev[k]; prev[k] = m;
                if (k >= 6) { ls += Math.Log(p[k] + 1e-3); cnt++; } }
            double am = 0; for (int k = 6; k < K; k++) am += p[k]; am /= cnt;
            P[f] = p; tot[f] = sum; flat[f] = am > 0 ? Math.Exp(ls / cnt) / (am + 1e-3) : 0; flux[f] = fl;
            // F0 by normalized autocorrelation (60-500 Hz)
            f0[f] = 0;
            if (e0 > 0) { double best = 0; int bl = 0;
                for (int lag = sr / 500; lag <= sr / 60; lag++) { double r = 0, ea = 0, eb = 0;
                    for (int i = 0; i + lag < N; i += 2) { double a = x[s0 + i], b = x[s0 + i + lag]; r += a * b; ea += a * a; eb += b * b; }
                    double nr = r / Math.Sqrt(ea * eb + 1e-9); if (nr > best) { best = nr; bl = lag; } }
                if (best > 0.6 && bl > 0) f0[f] = (double)sr / bl; }
        }
        double maxTot = 0; for (int f = 0; f < F; f++) if (tot[f] > maxTot) maxTot = tot[f];
        var sb = new StringBuilder();
        // ---- global: active segments ----
        var segs = new List<double[]>(); bool on = false; double st = 0; double thr = maxTot * Math.Pow(10, -2.5);
        for (int f = 0; f <= F; f++) { bool a = f < F && tot[f] > thr; double t = (double)f * hop / sr;
            if (a && !on) { if (segs.Count > 0 && t - segs[segs.Count - 1][1] < 0.15) { st = segs[segs.Count - 1][0]; segs.RemoveAt(segs.Count - 1); } else st = t; on = true; }
            else if (!a && on) { segs.Add(new double[] { st, t + (double)(N - hop) / sr }); on = false; } }
        sb.AppendFormat("dur={0:F1}s; loud segments (>-25dB of peak): ", dur);
        for (int i = 0; i < segs.Count && i < 24; i++) sb.AppendFormat("{0:F2}-{1:F2} ", segs[i][0], Math.Min(dur, segs[i][1]));
        if (segs.Count > 24) sb.AppendFormat("... ({0} total)", segs.Count);
        sb.Append("\n");
        // ---- global: onsets + tempo ----
        double mean = 0, sd = 0; for (int f = 0; f < F; f++) mean += flux[f]; mean /= F; for (int f = 0; f < F; f++) sd += (flux[f] - mean) * (flux[f] - mean); sd = Math.Sqrt(sd / F);
        var ons = new List<double>(); double last = -1;
        for (int f = 1; f < F - 1; f++) if (flux[f] > mean + 1.5 * sd && flux[f] >= flux[f - 1] && flux[f] > flux[f + 1]) { double t = (double)f * hop / sr; if (t - last > 0.08) { ons.Add(t); last = t; } }
        sb.AppendFormat("onsets n={0}: ", ons.Count); for (int i = 0; i < ons.Count && i < 48; i++) sb.AppendFormat("{0:F2} ", ons[i]); if (ons.Count > 48) sb.Append("..."); sb.Append("\n");
        double fps = (double)sr / hop; double bestA = 0, secA = 0; int bestL = 0, secL = 0; double r0 = 0; for (int f = 0; f < F; f++) r0 += (flux[f] - mean) * (flux[f] - mean);
        double[] ac = new double[(int)(fps * 1.5) + 2];
        for (int lag = (int)(fps * 0.3); lag <= (int)(fps * 1.5) && lag < F / 2; lag++) { double r = 0; for (int f = 0; f + lag < F; f++) r += (flux[f] - mean) * (flux[f + lag] - mean); ac[lag] = r / (r0 + 1e-9); }
        for (int lag = (int)(fps * 0.3) + 1; lag < ac.Length - 1; lag++) if (ac[lag] > ac[lag - 1] && ac[lag] >= ac[lag + 1]) { if (ac[lag] > bestA) { secA = bestA; secL = bestL; bestA = ac[lag]; bestL = lag; } else if (ac[lag] > secA) { secA = ac[lag]; secL = lag; } }
        sb.Append("periodicity of onsets: "); if (bestL > 0) sb.AppendFormat("{0:F0} bpm (strength {1:F2})", 60 * fps / bestL, bestA); if (secL > 0) sb.AppendFormat(", {0:F0} bpm ({1:F2})", 60 * fps / secL, secA); if (bestL == 0) sb.Append("none"); sb.Append("\n");
        // ---- global: voicing ----
        var v = new List<double>(); int act = 0; for (int f = 0; f < F; f++) if (tot[f] > thr) { act++; if (f0[f] > 0) v.Add(f0[f]); } v.Sort();
        if (v.Count > 0) sb.AppendFormat("periodic(voiced) frames {0:F0}% of loud frames; F0 median {1:F0} Hz, 10-90% range {2:F0}-{3:F0} Hz\n", 100.0 * v.Count / Math.Max(1, act), v[v.Count / 2], v[v.Count / 10], v[Math.Min(v.Count - 1, v.Count * 9 / 10)]);
        else sb.Append("periodic(voiced) frames 0%\n");
        // ---- rows ----
        int R = (int)Math.Round(dur / 0.25); if (R < 8) R = 8; if (R > 40) R = 40; if (R > F) R = F;
        double[][] band = new double[R][]; double[] rl = new double[R]; double bandMax = 0, rlMax = 0;
        double[][] avg = new double[R][];
        for (int r = 0; r < R; r++) { int a = r * F / R, b = Math.Max(a + 1, (r + 1) * F / R); band[r] = new double[10]; avg[r] = new double[K];
            for (int f = a; f < b; f++) { for (int k = 0; k < K; k++) avg[r][k] += P[f][k] / (b - a); rl[r] += tot[f] / (b - a); }
            for (int k = 0; k < K; k++) { double hz = (double)k * sr / N; for (int bi = 0; bi < 10; bi++) if (hz >= edges[bi] && hz < edges[bi + 1]) { band[r][bi] += avg[r][k]; break; } }
            for (int bi = 0; bi < 10; bi++) if (band[r][bi] > bandMax) bandMax = band[r][bi]; if (rl[r] > rlMax) rlMax = rl[r]; }
        double[] gch = new double[12];
        for (int r = 0; r < R; r++) { int a = r * F / R, b = Math.Max(a + 1, (r + 1) * F / R);
            sb.AppendFormat("{0,5:F2} L{1} ", (double)a * hop / sr, Dig(rl[r], rlMax));
            for (int bi = 0; bi < 10; bi++) sb.Append(Dig(band[r][bi], bandMax));
            double fm = 0; var vv = new List<double>(); for (int f = a; f < b; f++) { fm += flat[f] / (b - a); if (f0[f] > 0 && tot[f] > thr) vv.Add(f0[f]); }
            int fd = (int)Math.Round(9 + 1.5 * Math.Log(Math.Max(fm, 1e-6) / 0.5, 2)); fd = fd < 0 ? 0 : (fd > 9 ? 9 : fd);
            sb.AppendFormat(" f{0} ", fd);
            if (vv.Count * 10 >= (b - a) * 3) { vv.Sort(); sb.AppendFormat("{0,3:F0}", vv[vv.Count / 2]); } else sb.Append("  -");
            // peaks
            var pk = new List<double[]>(); double pmax = 0;
            for (int k = 4; k < K - 1; k++) if (avg[r][k] > avg[r][k - 1] && avg[r][k] >= avg[r][k + 1]) { pk.Add(new double[] { avg[r][k], k }); if (avg[r][k] > pmax) pmax = avg[r][k]; }
            pk.Sort((p1, p2) => p2[0].CompareTo(p1[0])); var sel = new List<double>();
            for (int i = 0; i < pk.Count && sel.Count < 3; i++) if (pk[i][0] > pmax * 0.003) { int k = (int)pk[i][1]; double al = Math.Log(avg[r][k - 1] + 1e-9), be = Math.Log(avg[r][k] + 1e-9), ga = Math.Log(avg[r][k + 1] + 1e-9); double d = 0.5 * (al - ga) / (al - 2 * be + ga); sel.Add((k + d) * sr / N); }
            sel.Sort(); sb.Append(" "); for (int i = 0; i < sel.Count; i++) sb.AppendFormat("{0:F0}{1}", sel[i], i < sel.Count - 1 ? "/" : "");
            // pitch classes
            double[] ch = new double[12];
            for (int k = 4; k < K; k++) { double hz = (double)k * sr / N; if (hz < 65 || hz > 2100) continue; int m = (int)Math.Round(69 + 12 * Math.Log(hz / 440.0, 2)); ch[((m % 12) + 12) % 12] += Math.Sqrt(avg[r][k]); }
            for (int i = 0; i < 12; i++) gch[i] += ch[i];
            int[] idx = new int[12]; for (int i = 0; i < 12; i++) idx[i] = i; Array.Sort(idx, (p1, p2) => ch[p2].CompareTo(ch[p1]));
            sb.AppendFormat(" {0},{1},{2}\n", PC[idx[0]], PC[idx[1]], PC[idx[2]]);
        }
        int[] gi = new int[12]; for (int i = 0; i < 12; i++) gi[i] = i; Array.Sort(gi, (p1, p2) => gch[p2].CompareTo(gch[p1]));
        sb.Append("overall pitch classes: "); for (int i = 0; i < 6; i++) sb.AppendFormat("{0}{1:F0} ", PC[gi[i]], 100 * gch[gi[i]] / (gch[gi[0]] + 1e-9));
        return sb.ToString();
    }
}
'@
New-Item -ItemType Directory -Force "$Out\feat" | Out-Null
$sr = 16000; $n = 0
foreach ($id in ($Ids -split '[,\s]+' | Where-Object { $_ })) {
    $qid = if ($id -match '^mini_') { $id } else { "mini_$id" }
    $dst = "$Out\feat\$qid.txt"; if (Test-Path $dst) { continue }
    $tmp = [System.IO.Path]::GetTempFileName()
    & ffmpeg -hide_banner -loglevel error -y -i "data\mmau_mini\audio\$qid.wav" -ac 1 -ar $sr -f s16le $tmp
    $bytes = [System.IO.File]::ReadAllBytes($tmp); Remove-Item $tmp
    $pcm = New-Object 'System.Int16[]' ([int]($bytes.Length / 2)); [System.Buffer]::BlockCopy($bytes, 0, $pcm, 0, $pcm.Length * 2)
    [System.IO.File]::WriteAllText((Join-Path $Root $dst), [Feat]::Run($pcm, $sr)); $n++
}
"features written: $n"
