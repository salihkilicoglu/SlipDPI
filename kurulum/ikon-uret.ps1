# SlipDPI : simge dosyasini (SlipDPI.ico) uretir. Yalnizca gelistirici icin; simge depoda kayitlidir.
# Koyu yuvarlak kose kare icinde yesil nokta: penceredeki "calisiyor" gostergesiyle ayni.
# Klasik (BMP tabanli, 32 bit) ICO yazar: Inno Setup, kisayollar ve WinForms sorunsuz okur.
#
# Pikseller cizim kutuphanesiyle degil dogrudan hesaplanir (piksel basina 8x8 ornek): boylece sekil
# her boyutta tuvalin tam ortasina gore simetrik olur. GDI+ ile cizilen onceki surumde nokta yarim
# piksel kadar kayiyordu.
param([string]$Cikti = (Join-Path (Split-Path $PSScriptRoot -Parent) 'SlipDPI.ico'))

Add-Type -TypeDefinition @'
using System;
public static class SlipIkon {
    static double Kare(double px, double py, double s, double r) {      // yuvarlak koseli karenin icinde mi
        double h = s / 2.0, dx = Math.Abs(px - h) - (h - r), dy = Math.Abs(py - h) - (h - r);
        if (dx <= 0 || dy <= 0) return (Math.Max(dx, dy) <= r) ? 1 : 0;
        return (dx * dx + dy * dy <= r * r) ? 1 : 0;
    }
    // BGRA, satirlar ustten alta
    public static byte[] Ciz(int s) {
        const int N = 8;
        double h = s / 2.0, r = s * 0.22;
        double nokta = Math.Round(s * 0.28);            // yaricap: tam piksel, cap cift sayi
        double hale = nokta + s * 0.07;
        byte[] o = new byte[s * s * 4];
        for (int y = 0; y < s; y++) for (int x = 0; x < s; x++) {
            double a = 0, rr = 0, gg = 0, bb = 0;
            for (int j = 0; j < N; j++) for (int i = 0; i < N; i++) {
                double px = x + (i + 0.5) / N, py = y + (j + 0.5) / N;
                if (Kare(px, py, s, r) == 0) continue;
                double d2 = (px - h) * (px - h) + (py - h) * (py - h);
                double cr = 15, cg = 23, cb = 42;                         // zemin
                if (d2 <= nokta * nokta) { cr = 34; cg = 197; cb = 94; }  // nokta
                else if (d2 <= hale * hale) { double k = 70 / 255.0; cr += (34 - cr) * k; cg += (197 - cg) * k; cb += (94 - cb) * k; }
                a += 1; rr += cr; gg += cg; bb += cb;
            }
            int p = (y * s + x) * 4;
            if (a > 0) {
                o[p] = (byte)Math.Round(bb / a); o[p + 1] = (byte)Math.Round(gg / a); o[p + 2] = (byte)Math.Round(rr / a);
                o[p + 3] = (byte)Math.Round(255 * a / (N * N));
            }
        }
        return o;
    }
}
'@

$boyutlar = 16, 20, 24, 32, 40, 48, 64
$resimler = @()
foreach ($s in $boyutlar) {
    $ham = [SlipIkon]::Ciz($s)
    $ms = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter($ms)
    # BITMAPINFOHEADER (yukseklik iki kat: renk + maske)
    $w.Write([int]40); $w.Write([int]$s); $w.Write([int]($s * 2)); $w.Write([int16]1); $w.Write([int16]32)
    $w.Write([int]0); $w.Write([int]($s * $s * 4)); $w.Write([int]0); $w.Write([int]0); $w.Write([int]0); $w.Write([int]0)
    for ($y = $s - 1; $y -ge 0; $y--) { $w.Write($ham, $y * $s * 4, $s * 4) }      # satirlar alttan uste
    $maskeSatir = [int]([math]::Floor(($s + 31) / 32) * 4)
    $w.Write((New-Object byte[] ($maskeSatir * $s)))                                 # AND maskesi: hepsi 0 (seffaflik alfa kanalinda)
    $w.Flush()
    $resimler += , $ms.ToArray()
}

$fs = [IO.File]::Create($Cikti)
$w = New-Object IO.BinaryWriter($fs)
$w.Write([int16]0); $w.Write([int16]1); $w.Write([int16]$boyutlar.Count)
$ofs = 6 + 16 * $boyutlar.Count
for ($i = 0; $i -lt $boyutlar.Count; $i++) {
    $s = $boyutlar[$i]; $veri = $resimler[$i]
    $w.Write([byte]($s -band 255)); $w.Write([byte]($s -band 255)); $w.Write([byte]0); $w.Write([byte]0)   # 256 -> 0
    $w.Write([int16]1); $w.Write([int16]32); $w.Write([int]$veri.Length); $w.Write([int]$ofs)
    $ofs += $veri.Length
}
foreach ($veri in $resimler) { $w.Write($veri) }
$w.Flush(); $fs.Close()
"Yazildi: $Cikti  ($((Get-Item $Cikti).Length) bayt, boyutlar: $($boyutlar -join ', '))"
