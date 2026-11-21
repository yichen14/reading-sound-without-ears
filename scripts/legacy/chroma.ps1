# Semitone-energy (chroma) analysis without Python: ffmpeg decodes to raw PCM, a small C# routine
# measures energy at every semitone (Hann-windowed single-bin DFT) and reports, per time step,
# the bass note, the strongest pitch classes and the best-matching major/minor triad.
param([string]$File, [double]$From = 0, [double]$To = 30, [double]$Step = 0.5, [double]$Win = 0.5)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Text;
public static class Chroma {
    static readonly string[] N = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"};
    public static string Run(short[] x, int sr, double from, double to, double step, double win) {
        var sb = new StringBuilder();
        int wl = (int)(win * sr);
        double[] w = new double[wl];
        for (int i = 0; i < wl; i++) w[i] = 0.5 - 0.5 * Math.Cos(2 * Math.PI * i / (wl - 1));
        int lo = 28, hi = 84;                        // E1 .. C6
        double[] tot = new double[12];
        for (double t = from; t + win <= to + 1e-9 && (int)((t + win) * sr) <= x.Length; t += step) {
            int s0 = (int)(t * sr);
            double[] mag = new double[hi + 1];
            for (int m = lo; m <= hi; m++) {
                double f = 440.0 * Math.Pow(2, (m - 69) / 12.0);
                double re = 0, im = 0, k = 2 * Math.PI * f / sr;
                for (int i = 0; i < wl; i++) { double v = x[s0 + i] * w[i]; re += v * Math.Cos(k * i); im -= v * Math.Sin(k * i); }
                mag[m] = Math.Sqrt(re * re + im * im);
            }
            double[] ch = new double[12];
            for (int m = 36; m <= hi; m++) ch[m % 12] += mag[m] * (m <= 72 ? 1.0 : 0.5);
            int bass = lo; for (int m = lo; m <= 55; m++) if (mag[m] > mag[bass]) bass = m;
            double mx = 0; for (int i = 0; i < 12; i++) { if (ch[i] > mx) mx = ch[i]; tot[i] += ch[i]; }
            int[] idx = new int[12]; for (int i = 0; i < 12; i++) idx[i] = i;
            Array.Sort(idx, (a, b) => ch[b].CompareTo(ch[a]));
            string best = Triad(ch);
            sb.AppendFormat("{0,6:F2}s bass={1,-3} top: ", t, N[bass % 12] + (bass / 12 - 1));
            for (int i = 0; i < 5; i++) sb.AppendFormat("{0}({1:F0}) ", N[idx[i]], 100 * ch[idx[i]] / (mx + 1e-9));
            sb.AppendFormat(" chord~ {0}\n", best);
        }
        sb.Append("overall: ");
        double tm = 0; for (int i = 0; i < 12; i++) if (tot[i] > tm) tm = tot[i];
        for (int i = 0; i < 12; i++) sb.AppendFormat("{0}={1:F0} ", N[i], 100 * tot[i] / (tm + 1e-9));
        sb.AppendFormat(" | overall triad~ {0}\n", Triad(tot));
        return sb.ToString();
    }
    static string Triad(double[] ch) {
        double bestS = -1, secondS = -1; string best = "", second = "";
        for (int r = 0; r < 12; r++) for (int q = 0; q < 2; q++) {
            double s = ch[r] + ch[(r + (q == 0 ? 4 : 3)) % 12] * 0.9 + ch[(r + 7) % 12] * 0.9;
            string nm = N[r] + (q == 0 ? "" : "m");
            if (s > bestS) { secondS = bestS; second = best; bestS = s; best = nm; }
            else if (s > secondS) { secondS = s; second = nm; }
        }
        return best + " (2nd " + second + ")";
    }
}
'@
$sr = 11025
$tmp = [System.IO.Path]::GetTempFileName()
& ffmpeg -hide_banner -loglevel error -y -i $File -ac 1 -ar $sr -f s16le $tmp
$bytes = [System.IO.File]::ReadAllBytes($tmp); Remove-Item $tmp
$pcm = New-Object 'System.Int16[]' ($bytes.Length / 2)
[System.Buffer]::BlockCopy($bytes, 0, $pcm, 0, $bytes.Length)
[Chroma]::Run($pcm, $sr, $From, $To, $Step, $Win)
