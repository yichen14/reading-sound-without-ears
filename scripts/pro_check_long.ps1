# Check whether MMAU-Pro audio files open with the corrupted pattern seen in the ~10-minute sound clips:
# identical L/R samples, full-band noise at about -6.5 dBFS RMS, ~18,800 zero crossings per second.
# Fetches only the first $Bytes of each zip member (byte range), inflates what it can and measures it.
# Writes pro\long_audio_check.csv (row, MB, bad, stats).
param([string]$Root, [long]$MinMB = 90, [int]$Bytes = 400000,
      [string]$ZipUrl = 'https://huggingface.co/datasets/gamma-lab-umd/MMAU-Pro/resolve/main/data.zip')
Set-Location $Root
if (-not ('HeadScan' -as [type])) { Add-Type -ReferencedAssemblies System.IO.Compression -TypeDefinition @'
using System; using System.IO; using System.IO.Compression;
public static class HeadScan {
  public static string Run(byte[] b){
    if (BitConverter.ToUInt32(b,0)!=0x04034b50) return "badhdr";
    int start=30+BitConverter.ToUInt16(b,26)+BitConverter.ToUInt16(b,28);
    var outp=new MemoryStream(); try{ using(var ds=new DeflateStream(new MemoryStream(b,start,b.Length-start),CompressionMode.Decompress)){ var buf=new byte[65536]; int n; while((n=ds.Read(buf,0,buf.Length))>0) outp.Write(buf,0,n);} } catch {}
    var w=outp.ToArray(); if(w.Length<100) return "short";
    int pos=12, ch=0, sr=0, bits=0, data=-1; while(pos+8<w.Length){ string id=System.Text.Encoding.ASCII.GetString(w,pos,4); int sz=BitConverter.ToInt32(w,pos+4); if(id=="fmt "){ch=BitConverter.ToUInt16(w,pos+10); sr=BitConverter.ToInt32(w,pos+12); bits=BitConverter.ToUInt16(w,pos+22);} if(id=="data"){data=pos+8;break;} pos+=8+sz+(sz&1); }
    if(data<0||bits!=16) return "fmt ch="+ch+" sr="+sr+" bits="+bits;
    int fr=ch*2; long m=(w.Length-data)/fr; double s=0; long same=0, zc=0; int prev=0;
    for(long i=0;i<m;i++){ int l=BitConverter.ToInt16(w,(int)(data+i*fr)); int r= ch>1? BitConverter.ToInt16(w,(int)(data+i*fr+2)) : l; s+=(double)l*l; if(l==r) same++; if((l>=0)!=(prev>=0)) zc++; prev=l; }
    double secs=(double)m/sr; return string.Format("ch={0} sr={1} secs={2:0.0} rms={3:0.0}dB L==R={4:0.00} zc/s={5:0}", ch, sr, secs, 20*Math.Log10(Math.Sqrt(s/m)/32768+1e-9), (double)same/m, zc/secs);
  }
}
'@ }
$pro = Get-Content data\mmau_pro\rows_full.json -Raw -Encoding UTF8 | ConvertFrom-Json
$idx = @{}; Import-Csv data\mmau_pro\zip_index.csv | ForEach-Object { $idx[$_.name] = $_ }
$h = @($pro | Where-Object { $a = @($_.row.audio_path); $a.Count -eq 1 -and $idx[$a[0]] -and [long]$idx[$a[0]].usize -gt $MinMB * 1MB })
New-Item -ItemType Directory -Force pro\_tmp | Out-Null
$tmp = Join-Path $Root 'pro\_tmp\head.bin'
$out = foreach ($x in $h) {
    $e = $idx[@($x.row.audio_path)[0]]; [long]$off = $e.offset
    & curl.exe -sS -L --retry 3 -r "$off-$($off + $Bytes)" -o $tmp $ZipUrl
    $r = [HeadScan]::Run([IO.File]::ReadAllBytes($tmp))
    $bad = ($r -match 'L==R=1\.00') -and ($r -match 'rms=-6\.\d+dB') -and ($r -match 'zc/s=1[78]\d\d\d')
    [pscustomobject]@{ row = $x.row_idx; MB = [math]::Round([long]$e.usize / 1MB); bad = [int]$bad; stats = $r }
}
$out | Export-Csv pro\long_audio_check.csv -NoTypeInformation -Encoding UTF8
"checked $($out.Count) files > $MinMB MB; corrupted opening: $(($out | Measure-Object bad -Sum).Sum)"
$out | Where-Object { -not $_.bad } | Format-Table -AutoSize | Out-String -Width 200
