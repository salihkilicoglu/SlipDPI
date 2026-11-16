# SlipDPI : on / off  (stops it if it is running, starts it if it is stopped)
# While off, the machine behaves as it did before install; installed files and the DNS rule stay in place.
# Usage:  toggle.ps1            -> toggles the state (asks for administrator rights)
#         toggle.ps1 -Durum     -> only shows the state (no administrator needed)
param([switch]$Durum)

. (Join-Path $PSScriptRoot 'common.ps1')
$svc = Get-Service -Name $ServisAdi -ErrorAction SilentlyContinue
if (-not $svc) { Write-Host 'SlipDPI kurulu degil. Once install.ps1 calistir.'; Kapanmadan-Bekle; return }
if ($Durum) { Write-Host "SlipDPI: $($svc.Status)   baslangic: $($svc.StartType)"; Kapanmadan-Bekle; return }

if (-not (Yonetici-Mi)) { Yukselt $PSCommandPath ''; return }
if ($svc.Status -eq 'Running') {
    Stop-Service -Name $ServisAdi -Force
    Set-Service  -Name $ServisAdi -StartupType Manual
    Write-Host 'SlipDPI KAPATILDI (acilista da baslamayacak).' -ForegroundColor Yellow
} else {
    Set-Service   -Name $ServisAdi -StartupType Automatic
    Start-Service -Name $ServisAdi
    Write-Host 'SlipDPI ACILDI (acilista otomatik baslayacak).' -ForegroundColor Green
}
