# SlipDPI : on / off  (stops it if it is running, starts it if it is stopped)
# While off, the machine behaves as it did before install; installed files and the DNS rule stay in place.
# Usage:  toggle.ps1            -> toggles the state (asks for administrator rights)
#         toggle.ps1 -Status     -> only shows the state (no administrator needed)
param([switch]$Status)

. (Join-Path $PSScriptRoot 'common.ps1')
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) { Write-Host 'SlipDPI kurulu degil. Once install.ps1 calistir.'; Wait-BeforeClose; return }
if ($Status) { Write-Host "SlipDPI: $($svc.Status)   baslangic: $($svc.StartType)"; Wait-BeforeClose; return }

if (-not (Test-Admin)) { Invoke-Elevated $PSCommandPath ''; return }
if ($svc.Status -eq 'Running') {
    Stop-Service -Name $ServiceName -Force
    Set-Service  -Name $ServiceName -StartupType Manual
    Write-Host 'SlipDPI KAPATILDI (acilista da baslamayacak).' -ForegroundColor Yellow
} else {
    Set-Service   -Name $ServiceName -StartupType Automatic
    Start-Service -Name $ServiceName
    Write-Host 'SlipDPI ACILDI (acilista otomatik baslayacak).' -ForegroundColor Green
}
