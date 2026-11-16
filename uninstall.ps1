# SlipDPI : full uninstall
#
# What it reverts: the SlipDPI service, the WinDivert driver, the DNS (NRPT) rule, the DoH server setting
# if it was changed during install, the browser Secure DNS policy, the auto list and the state files.
#
# If installed from the repository it also deletes C:\Program Files\SlipDPI; the repository is not touched.
# If installed with the setup program (setup.exe), the uninstaller deletes the program files and calls this
# script (-Silent). If run by hand, use Apps > SlipDPI > Uninstall to remove the program files.
param([switch]$Silent)

. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-64Bit $PSCommandPath $(if ($Silent) { '-Silent' } else { '' })
if (-not (Test-Admin)) { Invoke-Elevated $PSCommandPath ''; return }

Disable-QuickEdit      # so the uninstall does not freeze when the window is clicked
$installedLayout = Test-InstalledLayout $PSScriptRoot
# In the installed layout the local\ folder gets deleted too, so the log is written to the temp folder.
if ($installedLayout) { $logPath = Join-Path $env:TEMP 'SlipDPI-uninstall.log' } else { $logPath = Join-Path (Get-LocalDir $PSScriptRoot) 'uninstall.log' }
Start-Transcript -Path $logPath -Force | Out-Null
$st = Read-State

Write-Step (T '1/5  Service and driver')
if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $ServiceName | Out-Host
} else { Write-Host (T 'No service.') }
Get-Process winws -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\WinDivert') {
    # Once the driver is stopped its registration usually removes itself, so "delete" may report an error.
    sc.exe stop windivert   | Out-Null
    sc.exe delete windivert | Out-Null
    Start-Sleep -Milliseconds 500
    if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\WinDivert') { Write-Host (T 'The WinDivert driver was stopped; its registration will be removed after a restart.') -ForegroundColor Yellow }
    else { Write-Host (T 'The WinDivert driver was removed.') }
} else { Write-Host (T 'The WinDivert driver is not registered.') }

Write-Step (T '2/5  DNS rule')
$names = @(); if ($st -and $st.nrptNames) { $names = @($st.nrptNames) }
$rules = @(Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object { $_.Comment -eq $Label -or $_.DisplayName -eq $Label -or ($names -contains $_.Name) })
if ($rules.Count -eq 0) { Write-Host (T 'No rule.') }
foreach ($r in $rules) { Remove-DnsClientNrptRule -Name $r.Name -Force; Write-Host (T 'Deleted: {0}' $r.Name) }

Write-Step (T '3/5  DoH server setting')
$restored = $false
if ($st -and $st.dohPrevious -and (Get-Command Set-DnsClientDohServerAddress -ErrorAction SilentlyContinue)) {
    foreach ($p in @($st.dohPrevious)) {
        if (-not $p -or -not $p.ServerAddress) { continue }
        try {
            Set-DnsClientDohServerAddress -ServerAddress $p.ServerAddress -AutoUpgrade ([bool]$p.AutoUpgrade) -AllowFallbackToUdp ([bool]$p.AllowFallbackToUdp) -ErrorAction Stop | Out-Null
            Write-Host (T 'Restored: {0}  AutoUpgrade={1}' $p.ServerAddress $p.AutoUpgrade)
            $restored = $true
        } catch { Write-Host (T 'Could not be restored ({0}): {1}' $p.ServerAddress $_.Exception.Message) -ForegroundColor Yellow }
    }
}
if (-not $restored) { Write-Host (T 'No DoH setting was changed.') }
Clear-DnsClientCache

Write-Step (T '4/5  Browser Secure DNS policy')
$pol = @(); if ($st -and $st.policies) { $pol = @($st.policies | Where-Object { $_ -and $_.root }) }
if ($pol.Count -eq 0) { Write-Host (T 'No policy set by us.') }
foreach ($e in $pol) { Remove-Policy $e; Write-Host (T 'Reverted: {0}  ({1})' $e.root (@($e.values) -join ', ')) }

Write-Step (T '5/5  Files')
if ($installedLayout) {
    # The uninstaller deletes the program files; only the files created at runtime are cleaned up here.
    foreach ($f in $AutoList, $AutoLog, $StatePath) { if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue } }
    $y = Join-Path $InstallDir 'local'; if (Test-Path $y) { Remove-Item $y -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Host (T 'The auto list, the state file and the local logs were deleted.')
} elseif (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $InstallDir) { Start-Sleep -Seconds 2; Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue }   # the driver file may stay locked for a few seconds
    if (Test-Path $InstallDir) { Write-Host (T 'Could not be deleted completely (the driver file may still be locked); it can be deleted by hand after a restart: {0}' $InstallDir) -ForegroundColor Yellow }
    else { Write-Host (T 'Deleted: {0}' $InstallDir) }
} else { Write-Host (T 'No folder.') }

Write-Step (T 'SUMMARY')
Write-Host ((T 'Service: ')  + $(if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) { T 'STILL PRESENT (removed after a restart)' } else { T 'none' }))
Write-Host ((T 'DNS rule: ') + @(Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object { $_.Comment -eq $Label -or $_.DisplayName -eq $Label -or ($names -contains $_.Name) }).Count)
Write-Host ("Internet: "   + $(if (Test-Connection 1.1.1.1 -Count 2 -Quiet) { T 'working' } else { T 'DOWN' }))
Write-Host (T 'Uninstall complete. Blocked sites will be closed again.') -ForegroundColor Green
if ($installedLayout -and -not $Silent) { Write-Host (T 'To delete the program files too: Settings > Apps > SlipDPI > Uninstall.') -ForegroundColor Yellow }
Stop-Transcript | Out-Null
if ($Silent) { exit 0 }
