# Condition E2: save each clip's spectrogram as a numeric file that the answering model opens with tools on demand.
# <Out>\specdata\<qid>.csv : STFT magnitude in dB (16 kHz mono, FFT 2048, hop 512 -> 7.8 Hz x 32 ms cells)
#   line 1: comment with the parameters;  line 2: "t\f" then the centre frequency of every column (Hz)
#   then one line per frame: time (s), then dB values relative to the loudest cell of the clip (0 = loudest, floor -90)
param([string]$Root, [string]$Ids, [string]$Out = 'full')
$ErrorActionPreference = 'Stop'
Set-Location $Root
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.IO;
public static class SpecFile {
    static void FFT(double[] re, double[] im) {
        int n = re.Length;
        for (int i = 1, j = 0; i < n; i++) { int bit = n >> 1; for (; (j & bit) != 0; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { double t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; } }
        for (int len = 2; len <= n; len <<= 1) { double ang = -2 * Math.PI / len, wr = Math.Cos(ang), wi = Math.Sin(ang);
            for (int i = 0; i < n; i += len) { double cr = 1, ci = 0;
                for (int k = 0; k < len / 2; k++) { int a = i + k, b = i + k + len / 2; double xr = re[b] * cr - im[b] * ci, xi = re[b] * ci + im[b] * cr;
                    re[b] = re[a] - xr; im[b] = im[a] - xi; re[a] += xr; im[a] += xi; double nr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = nr; } } }
    }
    public static void Write(short[] x, int sr, string path) {
        int N = 2048, hop = 512, K = N / 2 + 1; int F = Math.Max(1, (x.Length - N) / hop + 1);
        double[] win = new double[N]; for (int i = 0; i < N; i++) win[i] = 0.5 - 0.5 * Math.Cos(2 * Math.PI * i / (N - 1));
        double[][] P = new double[F][]; double max = 1e-9; double[] re = new double[N], im = new double[N];
        for (int f = 0; f < F; f++) { int s0 = f * hop;
            for (int i = 0; i < N; i++) { re[i] = (s0 + i < x.Length ? x[s0 + i] : 0) * win[i]; im[i] = 0; }
            FFT(re, im); P[f] = new double[K];
            for (int k = 0; k < K; k++) { P[f][k] = re[k] * re[k] + im[k] * im[k]; if (P[f][k] > max) max = P[f][k]; } }
        using (var w = new StreamWriter(path, false, new UTF8Encoding(false))) {
            w.WriteLine("# spectrogram: sr=" + sr + " nfft=" + N + " hop=" + hop + " rows=frame time (s) cols=frequency (Hz) values=dB relative to loudest cell (0), floor -90");
            var sb = new StringBuilder("t\\f"); for (int k = 0; k < K; k++) sb.Append(',').Append(((double)k * sr / N).ToString("0.#")); w.WriteLine(sb.ToString());
            for (int f = 0; f < F; f++) { sb.Length = 0; sb.Append(((double)f * hop / sr).ToString("0.000"));
                for (int k = 0; k < K; k++) { double db = 10 * Math.Log10(P[f][k] / max + 1e-12); if (db < -90) db = -90; sb.Append(',').Append(Math.Round(db).ToString("0")); }
                w.WriteLine(sb.ToString()); } }
    }
}
'@
New-Item -ItemType Directory -Force "$Out\specdata" | Out-Null
$sr = 16000; $n = 0
foreach ($id in ($Ids -split '[,\s]+' | Where-Object { $_ })) {
    $qid = if ($id -match '^mini_') { $id } else { "mini_$id" }
    $dst = Join-Path $Root "$Out\specdata\$qid.csv"; if (Test-Path $dst) { continue }
    $tmp = [System.IO.Path]::GetTempFileName()
    & ffmpeg -hide_banner -loglevel error -y -i "data\mmau_mini\audio\$qid.wav" -ac 1 -ar $sr -f s16le $tmp
    $bytes = [System.IO.File]::ReadAllBytes($tmp); Remove-Item $tmp
    $pcm = New-Object 'System.Int16[]' ([int]($bytes.Length / 2)); [System.Buffer]::BlockCopy($bytes, 0, $pcm, 0, $pcm.Length * 2)
    [SpecFile]::Write($pcm, $sr, $dst); $n++
}
"spectrogram files written: $n; folder size {0:n1} MB" -f ((Get-ChildItem "$Out\specdata\*.csv" | Measure-Object Length -Sum).Sum / 1MB)
