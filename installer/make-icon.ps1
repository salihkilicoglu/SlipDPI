# SlipDPI : generates the icon file (SlipDPI.ico). Developer only; the icon is kept in the repository.
# A green dot inside a dark rounded square: the same as the "running" indicator in the window.
# Writes a classic (BMP-based, 32-bit) ICO: Inno Setup, shortcuts and WinForms read it without trouble.
#
# Pixels are computed directly, not with a drawing library (8x8 samples per pixel): this keeps the
# shape symmetric about the exact center of the canvas at every size. In the earlier version drawn
# with GDI+ the dot was off by about half a pixel.
param([string]$OutFile = (Join-Path (Split-Path $PSScriptRoot -Parent) 'SlipDPI.ico'))

Add-Type -TypeDefinition @'
using System;
public static class SlipIcon {
    static double InSquare(double px, double py, double s, double r) {      // inside the rounded square?
        double h = s / 2.0, dx = Math.Abs(px - h) - (h - r), dy = Math.Abs(py - h) - (h - r);
        if (dx <= 0 || dy <= 0) return (Math.Max(dx, dy) <= r) ? 1 : 0;
        return (dx * dx + dy * dy <= r * r) ? 1 : 0;
    }
    // BGRA, rows top to bottom
    public static byte[] Draw(int s) {
        const int N = 8;
        double h = s / 2.0, r = s * 0.22;
        double dotR = Math.Round(s * 0.28);            // radius: whole pixels, even diameter
        double haloR = dotR + s * 0.07;
        byte[] o = new byte[s * s * 4];
        for (int y = 0; y < s; y++) for (int x = 0; x < s; x++) {
            double a = 0, rr = 0, gg = 0, bb = 0;
            for (int j = 0; j < N; j++) for (int i = 0; i < N; i++) {
                double px = x + (i + 0.5) / N, py = y + (j + 0.5) / N;
                if (InSquare(px, py, s, r) == 0) continue;
                double d2 = (px - h) * (px - h) + (py - h) * (py - h);
                double cr = 15, cg = 23, cb = 42;                         // background
                if (d2 <= dotR * dotR) { cr = 34; cg = 197; cb = 94; }  // dot
                else if (d2 <= haloR * haloR) { double k = 70 / 255.0; cr += (34 - cr) * k; cg += (197 - cg) * k; cb += (94 - cb) * k; }
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

$sizes = 16, 20, 24, 32, 40, 48, 64
$images = @()
foreach ($s in $sizes) {
    $rawPixels = [SlipIcon]::Draw($s)
    $ms = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter($ms)
    # BITMAPINFOHEADER (height is doubled: color + mask)
    $w.Write([int]40); $w.Write([int]$s); $w.Write([int]($s * 2)); $w.Write([int16]1); $w.Write([int16]32)
    $w.Write([int]0); $w.Write([int]($s * $s * 4)); $w.Write([int]0); $w.Write([int]0); $w.Write([int]0); $w.Write([int]0)
    for ($y = $s - 1; $y -ge 0; $y--) { $w.Write($rawPixels, $y * $s * 4, $s * 4) }      # rows bottom to top
    $maskRowBytes = [int]([math]::Floor(($s + 31) / 32) * 4)
    $w.Write((New-Object byte[] ($maskRowBytes * $s)))                                 # AND mask: all 0 (transparency is in the alpha channel)
    $w.Flush()
    $images += , $ms.ToArray()
}

$fs = [IO.File]::Create($OutFile)
$w = New-Object IO.BinaryWriter($fs)
$w.Write([int16]0); $w.Write([int16]1); $w.Write([int16]$sizes.Count)
$ofs = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $data = $images[$i]
    $w.Write([byte]($s -band 255)); $w.Write([byte]($s -band 255)); $w.Write([byte]0); $w.Write([byte]0)   # 256 -> 0
    $w.Write([int16]1); $w.Write([int16]32); $w.Write([int]$data.Length); $w.Write([int]$ofs)
    $ofs += $data.Length
}
foreach ($data in $images) { $w.Write($data) }
$w.Flush(); $fs.Close()
"Written: $OutFile  ($((Get-Item $OutFile).Length) bytes, sizes: $($sizes -join ', '))"
