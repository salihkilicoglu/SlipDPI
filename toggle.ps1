# SlipDPI : on / off  (stops it if it is running, starts it if it is stopped)
# While off, the machine behaves as it did before install; installed files and the DNS rule stay in place.
# Usage:  toggle.ps1            -> toggles the state (asks for administrator rights)
#         toggle.ps1 -Status     -> only shows the state (no administrator needed)
param([switch]$Status)

. (Join-Path $PSScriptRoot 'common.ps1')
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) { Write-Host (T 'SlipDPI is not installed. Run install.ps1 first.');Wait-BeforeClose; return }
if ($Status) { Write-Host (T 'SlipDPI: {0}   startup: {1}' $svc.Status $svc.StartType);Wait-BeforeClose; return }

if (-not (Test-Admin)) { Invoke-Elevated $PSCommandPath ''; return }
if ($svc.Status -eq 'Running') {
    Stop-Service -Name $ServiceName -Force
    Set-Service  -Name $ServiceName -StartupType Manual
    Write-Host (T 'SlipDPI is now OFF (it will not start at boot either).') -ForegroundColor Yellow
} else {
    Set-Service   -Name $ServiceName -StartupType Automatic
    Start-Service -Name $ServiceName
    Write-Host (T 'SlipDPI is now ON (it will start automatically at boot).') -ForegroundColor Green
}
