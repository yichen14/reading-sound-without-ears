# Query tool for the saved spectrogram files (<Out>\specdata\<qid>.csv). It reads ONLY those files, never the audio.
# -Q "NNNN cmd args; NNNN cmd args; ..."   (times in seconds, frequencies in Hz; omitted t0 t1 = whole clip)
#   info                      duration, loudness envelope (one digit per 0.25 s, 9 = loudest, -6 dB per step), 10-band profile, noisiness
#   bands  t0 t1 step         per step: 10 band digits (0-125,-250,-500,-1k,-1.5k,-2k,-3k,-4k,-6k,-8k Hz) + noisiness digit (0 tonal .. 9 noise)
#   peaks  t0 t1 [fmin fmax]  strongest spectral peaks of the mean spectrum in the window (Hz:dB)
#   track  t0 t1 step fmin fmax   strongest peak frequency per step inside a band (pitch contour / sweeps)
#   f0     t0 t1 step         fundamental estimate per step by harmonic summation (60-800 Hz) with a salience score
#   chroma t0 t1 [step]       pitch-class strengths and best major/minor triad
#   onsets t0 t1              onset times (spectral flux) and tempo estimate
#   raw    t0 t1 fmin fmax    the dB values themselves, averaged down to at most 16 x 16 cells
param([string]$Root, [string]$Q, [string]$Out = 'full')
$ErrorActionPreference = 'Stop'
Set-Location $Root
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.IO;
using System.Collections.Generic;
public class Spec {
    public double[] fr; public double[] tm; public double[][] P; public double dt; public double df; public double dur;
    static readonly string[] PC = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"};
    static readonly double[] E = {0, 125, 250, 500, 1000, 1500, 2000, 3000, 4000, 6000, 8001};
    public static Spec Load(string path) {
        var s = new Spec(); var rows = new List<double[]>(); var ts = new List<double>();
        foreach (var line in File.ReadLines(path)) {
            if (line.Length == 0 || line[0] == '#') continue;
            var p = line.Split(',');
            if (line[0] == 't') { s.fr = new double[p.Length - 1]; for (int i = 1; i < p.Length; i++) s.fr[i - 1] = double.Parse(p[i], System.Globalization.CultureInfo.InvariantCulture); continue; }
            ts.Add(double.Parse(p[0], System.Globalization.CultureInfo.InvariantCulture)); var r = new double[p.Length - 1];
            for (int i = 1; i < p.Length; i++) r[i - 1] = Math.Pow(10, int.Parse(p[i]) / 10.0); rows.Add(r);
        }
        s.P = rows.ToArray(); s.tm = ts.ToArray(); s.dt = s.tm.Length > 1 ? s.tm[1] - s.tm[0] : 0.032; s.df = s.fr[1] - s.fr[0]; s.dur = s.tm[s.tm.Length - 1] + s.dt * 4; return s;
    }
    int Fa(double t) { int f = (int)Math.Round(t / dt); return f < 0 ? 0 : (f > P.Length - 1 ? P.Length - 1 : f); }
    int Fb(double t) { int f = (int)Math.Round(t / dt); return f < 1 ? 1 : (f > P.Length ? P.Length : f); }
    double[] Mean(int a, int b) { if (b <= a) b = a + 1; if (b > P.Length) { b = P.Length; a = Math.Min(a, b - 1); } var m = new double[fr.Length]; for (int f = a; f < b; f++) for (int k = 0; k < m.Length; k++) m[k] += P[f][k] / (b - a); return m; }
    static int Dig(double v, double max) { if (v <= 0 || max <= 0) return 0; int d = 9 + (int)Math.Ceiling(10 * Math.Log10(v / max) / 6.0 - 1e-9); return d < 0 ? 0 : (d > 9 ? 9 : d); }
    double[] Bands(double[] m) { var b = new double[10]; for (int k = 0; k < m.Length; k++) for (int i = 0; i < 10; i++) if (fr[k] >= E[i] && fr[k] < E[i + 1]) { b[i] += m[k]; break; } return b; }
    int Noisy(double[] m) { double ls = 0, am = 0; int c = 0; for (int k = 8; k < m.Length; k++) { ls += Math.Log(m[k] + 1e-12); am += m[k]; c++; } double fl = Math.Exp(ls / c) / (am / c + 1e-12); int d = (int)Math.Round(9 + 1.5 * Math.Log(Math.Max(fl, 1e-6) / 0.5, 2)); return d < 0 ? 0 : (d > 9 ? 9 : d); }
    List<double[]> Peaks(double[] m, double fmin, double fmax, int n) {
        var pk = new List<double[]>(); double top = 0; for (int k = 0; k < m.Length; k++) if (m[k] > top) top = m[k];
        for (int k = 2; k < m.Length - 1; k++) { if (fr[k] < fmin || fr[k] > fmax) continue; if (m[k] > m[k - 1] && m[k] >= m[k + 1]) {
            double al = Math.Log(m[k - 1] + 1e-12), be = Math.Log(m[k] + 1e-12), ga = Math.Log(m[k + 1] + 1e-12), d = 0.5 * (al - ga) / (al - 2 * be + ga);
            pk.Add(new double[] { (k + d) * df, 10 * Math.Log10(m[k] / top + 1e-12), m[k] }); } }
        pk.Sort((x, y) => y[2].CompareTo(x[2])); if (pk.Count > n) pk.RemoveRange(n, pk.Count - n); return pk;
    }
    double[] Chroma(double[] m) { var ch = new double[12]; foreach (var p in Peaks(m, 60, 2100, 40)) { if (p[1] < -40) continue; int midi = (int)Math.Round(69 + 12 * Math.Log(p[0] / 440.0, 2)); ch[((midi % 12) + 12) % 12] += Math.Sqrt(p[2]); } return ch; }
    static string ChromaStr(double[] ch) { int[] idx = new int[12]; for (int i = 0; i < 12; i++) idx[i] = i; Array.Sort(idx, (a, b) => ch[b].CompareTo(ch[a])); var sb = new StringBuilder(); double mx = ch[idx[0]] + 1e-12;
        for (int i = 0; i < 6; i++) sb.AppendFormat("{0}{1:F0} ", PC[idx[i]], 100 * ch[idx[i]] / mx);
        double best = -1; string bn = ""; for (int r = 0; r < 12; r++) for (int q = 0; q < 2; q++) { double sc = ch[r] + 0.9 * ch[(r + (q == 0 ? 4 : 3)) % 12] + 0.9 * ch[(r + 7) % 12]; if (sc > best) { best = sc; bn = PC[r] + (q == 0 ? "" : "m"); } }
        return sb.ToString() + "~" + bn; }
    public string Run(string cmd, double[] a) {
        var sb = new StringBuilder(); double t0 = a.Length > 0 ? a[0] : 0, t1 = a.Length > 1 ? a[1] : dur; int fa = Fa(t0), fb = Fb(t1);
        double[] tot = new double[P.Length]; double mt = 0; for (int f = 0; f < P.Length; f++) { for (int k = 0; k < fr.Length; k++) tot[f] += P[f][k]; if (tot[f] > mt) mt = tot[f]; }
        if (cmd == "info") {
            sb.AppendFormat("dur {0:F1}s | loudness per 0.25s: ", dur); int st = Math.Max(1, (int)Math.Round(0.25 / dt));
            for (int f = 0; f < P.Length; f += st) { double m = 0; for (int g = f; g < Math.Min(P.Length, f + st); g++) if (tot[g] > m) m = tot[g]; sb.Append(Dig(m, mt)); }
            var mm = Mean(0, P.Length); var b = Bands(mm); double bm = 0; foreach (var v in b) if (v > bm) bm = v; sb.Append(" | bands "); foreach (var v in b) sb.Append(Dig(v, bm));
            double c = 0, s = 0; for (int k = 0; k < mm.Length; k++) { c += fr[k] * mm[k]; s += mm[k]; } sb.AppendFormat(" | centroid {0:F0}Hz | noisiness {1}", c / (s + 1e-12), Noisy(mm));
        } else if (cmd == "bands") {
            double step = a.Length > 2 ? a[2] : Math.Max(0.25, (t1 - t0) / 20); var list = new List<double[]>(); var ns = new List<int>(); var tt = new List<double>(); double bm = 0;
            for (double t = t0; t < t1 - 1e-6; t += step) { var m = Mean(Fa(t), Fb(Math.Min(t1, t + step))); var b = Bands(m); foreach (var v in b) if (v > bm) bm = v; list.Add(b); ns.Add(Noisy(m)); tt.Add(t); }
            for (int i = 0; i < list.Count; i++) { sb.AppendFormat("{0,6:F2} ", tt[i]); foreach (var v in list[i]) sb.Append(Dig(v, bm)); sb.AppendFormat(" n{0}\n", ns[i]); }
        } else if (cmd == "peaks") {
            var pk = Peaks(Mean(fa, fb), a.Length > 2 ? a[2] : 40, a.Length > 3 ? a[3] : 8000, 10); pk.Sort((x, y) => x[0].CompareTo(y[0])); foreach (var p in pk) sb.AppendFormat("{0:F0}:{1:F0} ", p[0], p[1]);
        } else if (cmd == "track") {
            double step = a.Length > 2 ? a[2] : 0.25, fmin = a.Length > 3 ? a[3] : 40, fmax = a.Length > 4 ? a[4] : 8000;
            for (double t = t0; t < t1 - 1e-6; t += step) { var pk = Peaks(Mean(Fa(t), Fb(Math.Min(t1, t + step))), fmin, fmax, 1); if (pk.Count > 0) sb.AppendFormat("{0:F2}:{1:F0}({2:F0}) ", t, pk[0][0], pk[0][1]); else sb.AppendFormat("{0:F2}:- ", t); }
        } else if (cmd == "f0") {
            double step = a.Length > 2 ? a[2] : 0.25;
            for (double t = t0; t < t1 - 1e-6; t += step) { var m = Mean(Fa(t), Fb(Math.Min(t1, t + step))); double best = 0, bf = 0, all = 0; for (int k = 4; k < m.Length; k++) all += Math.Sqrt(m[k]);
                for (double f = 60; f <= 800; f *= 1.01) { double sc = 0; for (int h = 1; h <= 8; h++) { double x = f * h / df; int k = (int)Math.Round(x); if (k >= m.Length - 1) break; sc += Math.Sqrt(Math.Max(m[k], Math.Max(m[k - 1], m[k + 1]))) / Math.Sqrt(h); } if (sc > best) { best = sc; bf = f; } }
                sb.AppendFormat("{0:F2}:{1:F0}({2:F0}%) ", t, bf, 100 * best / (all + 1e-12)); }
        } else if (cmd == "chroma") {
            if (a.Length > 2) { for (double t = t0; t < t1 - 1e-6; t += a[2]) sb.AppendFormat("{0,6:F2} {1}\n", t, ChromaStr(Chroma(Mean(Fa(t), Fb(Math.Min(t1, t + a[2])))))); }
            else sb.Append(ChromaStr(Chroma(Mean(fa, fb))));
        } else if (cmd == "onsets") {
            double[] fl = new double[P.Length]; for (int f = 1; f < P.Length; f++) for (int k = 0; k < fr.Length; k++) { double d = Math.Sqrt(P[f][k]) - Math.Sqrt(P[f - 1][k]); if (d > 0) fl[f] += d; }
            double mean = 0, sd = 0; for (int f = 0; f < P.Length; f++) mean += fl[f]; mean /= P.Length; for (int f = 0; f < P.Length; f++) sd += (fl[f] - mean) * (fl[f] - mean); sd = Math.Sqrt(sd / P.Length);
            int n = 0; double last = -1; var os = new StringBuilder(); for (int f = Math.Max(1, fa); f < fb - 1; f++) if (fl[f] > mean + 1.5 * sd && fl[f] >= fl[f - 1] && fl[f] > fl[f + 1] && tm[f] - last > 0.08) { last = tm[f]; n++; if (n <= 60) os.AppendFormat("{0:F2} ", tm[f]); }
            sb.AppendFormat("n={0}: {1}", n, os); double r0 = 0; for (int f = 0; f < P.Length; f++) r0 += (fl[f] - mean) * (fl[f] - mean); double bA = 0; int bL = 0; double fps = 1 / dt;
            double prev = 0, cur = 0; for (int lag = (int)(fps * 0.25); lag <= (int)(fps * 1.5) && lag < P.Length / 2; lag++) { double r = 0; for (int f = 0; f + lag < P.Length; f++) r += (fl[f] - mean) * (fl[f + lag] - mean); r /= r0 + 1e-12; if (cur > prev && cur >= r && cur > bA) { bA = cur; bL = lag - 1; } prev = cur; cur = r; }
            if (bL > 0) sb.AppendFormat("| periodicity {0:F0} bpm (or x2/half) strength {1:F2}", 60 * fps / bL, bA);
        } else if (cmd == "raw") {
            double fmin = a.Length > 2 ? a[2] : 0, fmax = a.Length > 3 ? a[3] : 8000; int ka = (int)Math.Floor(fmin / df), kb = Math.Min(fr.Length, (int)Math.Ceiling(fmax / df) + 1); int nt = Math.Min(16, fb - fa), nf = Math.Min(16, kb - ka); if (nt < 1) nt = 1; if (nf < 1) nf = 1;
            sb.Append("t\\Hz   "); for (int j = 0; j < nf; j++) sb.AppendFormat("{0,5:F0}", fr[ka + (int)((j + 0.5) * (kb - ka) / nf)]); sb.Append("\n");
            for (int i = 0; i < nt; i++) { int a0 = fa + i * (fb - fa) / nt, a1 = Math.Max(a0 + 1, fa + (i + 1) * (fb - fa) / nt); var m = Mean(a0, a1); sb.AppendFormat("{0,6:F2} ", tm[a0]);
                for (int j = 0; j < nf; j++) { int k0 = ka + j * (kb - ka) / nf, k1 = Math.Max(k0 + 1, ka + (j + 1) * (kb - ka) / nf); double v = 0; for (int k = k0; k < k1; k++) if (m[k] > v) v = m[k]; sb.AppendFormat("{0,5:F0}", 10 * Math.Log10(v + 1e-12)); } sb.Append("\n"); }
        } else sb.Append("unknown command");
        return sb.ToString().TrimEnd();
    }
}
'@
$cache = @{}
foreach ($one in ($Q -split ';')) {
    $p = @($one.Trim() -split '\s+' | Where-Object { $_ }); if ($p.Count -lt 2) { continue }
    $qid = "mini_$($p[0])"
    if (-not $cache.ContainsKey($qid)) { $cache[$qid] = [Spec]::Load((Join-Path $Root "$Out\specdata\$qid.csv")) }
    $args2 = @(); if ($p.Count -gt 2) { $args2 = $p[2..($p.Count - 1)] | ForEach-Object { [double]$_ } }
    $r = $cache[$qid].Run($p[1], [double[]]$args2)
    $lab = "$($p[0]) $($p[1])"; if ($p.Count -gt 2) { $lab += " " + ($p[2..($p.Count-1)] -join " ") }
    if ($r -match "`n") { "${lab}:"; $r } else { "${lab}: $r" }
}
