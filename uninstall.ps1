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

Write-Step '1/5  Servis ve surucu'
if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $ServiceName | Out-Host
} else { Write-Host 'Servis yok.' }
Get-Process winws -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\WinDivert') {
    # Once the driver is stopped its registration usually removes itself, so "delete" may report an error.
    sc.exe stop windivert   | Out-Null
    sc.exe delete windivert | Out-Null
    Start-Sleep -Milliseconds 500
    if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\WinDivert') { Write-Host 'WinDivert surucusu durduruldu; kaydi yeniden baslatinca silinecek.' -ForegroundColor Yellow }
    else { Write-Host 'WinDivert surucusu kaldirildi.' }
} else { Write-Host 'WinDivert surucusu kayitli degil.' }

Write-Step '2/5  DNS kurali'
$names = @(); if ($st -and $st.nrptNames) { $names = @($st.nrptNames) }
$rules = @(Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object { $_.Comment -eq $Label -or $_.DisplayName -eq $Label -or ($names -contains $_.Name) })
if ($rules.Count -eq 0) { Write-Host 'Kural yok.' }
foreach ($r in $rules) { Remove-DnsClientNrptRule -Name $r.Name -Force; Write-Host "Silindi: $($r.Name)" }

Write-Step '3/5  DoH sunucu ayari'
$restored = $false
if ($st -and $st.dohPrevious -and (Get-Command Set-DnsClientDohServerAddress -ErrorAction SilentlyContinue)) {
    foreach ($p in @($st.dohPrevious)) {
        if (-not $p -or -not $p.ServerAddress) { continue }
        try {
            Set-DnsClientDohServerAddress -ServerAddress $p.ServerAddress -AutoUpgrade ([bool]$p.AutoUpgrade) -AllowFallbackToUdp ([bool]$p.AllowFallbackToUdp) -ErrorAction Stop | Out-Null
            Write-Host "Eski haline dondu: $($p.ServerAddress)  AutoUpgrade=$($p.AutoUpgrade)"
            $restored = $true
        } catch { Write-Host "Geri alinamadi ($($p.ServerAddress)): $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}
if (-not $restored) { Write-Host 'Degistirilmis bir DoH ayari yok.' }
Clear-DnsClientCache

Write-Step '4/5  Tarayici Guvenli DNS politikasi'
$pol = @(); if ($st -and $st.policies) { $pol = @($st.policies | Where-Object { $_ -and $_.root }) }
if ($pol.Count -eq 0) { Write-Host 'Bizim koydugumuz politika yok.' }
foreach ($e in $pol) { Remove-Policy $e; Write-Host "Geri alindi: $($e.root)  ($(@($e.values) -join ', '))" }

Write-Step '5/5  Dosyalar'
if ($installedLayout) {
    # The uninstaller deletes the program files; only the files created at runtime are cleaned up here.
    foreach ($f in $AutoList, $AutoLog, $StatePath) { if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue } }
    $y = Join-Path $InstallDir 'local'; if (Test-Path $y) { Remove-Item $y -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Host 'Otomatik liste, durum dosyasi ve yerel kayitlar silindi.'
} elseif (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $InstallDir) { Start-Sleep -Seconds 2; Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue }   # the driver file may stay locked for a few seconds
    if (Test-Path $InstallDir) { Write-Host "Tam silinemedi (surucu dosyasi hala kilitli olabilir); yeniden baslattiktan sonra elle silinebilir: $InstallDir" -ForegroundColor Yellow }
    else { Write-Host "Silindi: $InstallDir" }
} else { Write-Host 'Klasor yok.' }

Write-Step 'OZET'
Write-Host ("Servis: "     + $(if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) { 'HALA VAR (yeniden baslatinca silinir)' } else { 'yok' }))
Write-Host ("DNS kurali: " + @(Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object { $_.Comment -eq $Label -or $_.DisplayName -eq $Label -or ($names -contains $_.Name) }).Count)
Write-Host ("Internet: "   + $(if (Test-Connection 1.1.1.1 -Count 2 -Quiet) { 'calisiyor' } else { 'YOK' }))
Write-Host 'Kaldirma tamam. Engelli siteler tekrar kapali olacak.' -ForegroundColor Green
if ($installedLayout -and -not $Silent) { Write-Host 'Program dosyalarini da silmek icin: Ayarlar > Uygulamalar > SlipDPI > Kaldir.' -ForegroundColor Yellow }
Stop-Transcript | Out-Null
if ($Silent) { exit 0 }
