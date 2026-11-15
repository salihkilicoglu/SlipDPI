# dpi-lite : ac / kapat  (calisiyorsa durdurur, duruyorsa baslatir)
# Kapaliyken makine kurulumdan onceki gibi davranir; kurulu dosyalar ve DNS kurali yerinde kalir.
# Kullanim:  ac-kapat.ps1            -> durumu degistirir (yonetici izni ister)
#            ac-kapat.ps1 -Durum     -> yalnizca durumu gosterir (yonetici gerekmez)
param([switch]$Durum)

. (Join-Path $PSScriptRoot 'ortak.ps1')
$svc = Get-Service -Name $ServisAdi -ErrorAction SilentlyContinue
if (-not $svc) { Write-Host 'dpi-lite kurulu degil. Once kur.ps1 calistir.'; return }
if ($Durum) { Write-Host "dpi-lite: $($svc.Status)   baslangic: $($svc.StartType)"; return }

if (-not (Yonetici-Mi)) { Yukselt $PSCommandPath ''; return }
if ($svc.Status -eq 'Running') {
    Stop-Service -Name $ServisAdi -Force
    Set-Service  -Name $ServisAdi -StartupType Manual
    Write-Host 'dpi-lite KAPATILDI (acilista da baslamayacak).' -ForegroundColor Yellow
} else {
    Set-Service   -Name $ServisAdi -StartupType Automatic
    Start-Service -Name $ServisAdi
    Write-Host 'dpi-lite ACILDI (acilista otomatik baslayacak).' -ForegroundColor Green
}
