# dpi-lite : simge dosyasini (dpi-lite.ico) uretir. Yalnizca gelistirici icin; simge depoda kayitlidir.
# Koyu yuvarlak kose kare icinde yesil nokta: penceredeki "calisiyor" gostergesiyle ayni.
# Klasik (BMP tabanli, 32 bit) ICO yazar: Inno Setup, kisayollar ve WinForms sorunsuz okur.
param([string]$Cikti = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dpi-lite.ico'))

Add-Type -AssemblyName System.Drawing

function Ciz([int]$s) {
    $bmp = New-Object Drawing.Bitmap($s, $s, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([Drawing.Color]::Transparent)
    $r = [single]($s * 0.22); $d = $r * 2; $m = [single]($s - 1)
    $yol = New-Object Drawing.Drawing2D.GraphicsPath
    $yol.AddArc(0, 0, $d, $d, 180, 90); $yol.AddArc($m - $d, 0, $d, $d, 270, 90)
    $yol.AddArc($m - $d, $m - $d, $d, $d, 0, 90); $yol.AddArc(0, $m - $d, $d, $d, 90, 90); $yol.CloseFigure()
    $zemin = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 15, 23, 42))
    $g.FillPath($zemin, $yol)
    $c = [single]($s * 0.56); $o = [single](($s - $c) / 2)
    $hale = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(70, 34, 197, 94))
    $g.FillEllipse($hale, $o - $s * 0.07, $o - $s * 0.07, $c + $s * 0.14, $c + $s * 0.14)
    $yesil = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 34, 197, 94))
    $g.FillEllipse($yesil, $o, $o, $c, $c)
    $g.Dispose()
    $bmp
}

$boyutlar = 16, 24, 32, 48, 64
$resimler = @()
foreach ($s in $boyutlar) {
    $bmp = Ciz $s
    $kilit = $bmp.LockBits((New-Object Drawing.Rectangle(0, 0, $s, $s)), 'ReadOnly', [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $ham = New-Object byte[] ($s * $s * 4)
    [Runtime.InteropServices.Marshal]::Copy($kilit.Scan0, $ham, 0, $ham.Length)
    $bmp.UnlockBits($kilit); $bmp.Dispose()
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
    $w.Write([byte]$s); $w.Write([byte]$s); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([int16]1); $w.Write([int16]32); $w.Write([int]$veri.Length); $w.Write([int]$ofs)
    $ofs += $veri.Length
}
foreach ($veri in $resimler) { $w.Write($veri) }
$w.Flush(); $fs.Close()
"Yazildi: $Cikti  ($((Get-Item $Cikti).Length) bayt, boyutlar: $($boyutlar -join ', '))"
