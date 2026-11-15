# dpi-lite : tamamen kaldirma
#
# Geri aldiklari: dpi-lite servisi, WinDivert surucusu, DNS (NRPT) kurali, kurulum sirasinda
# degistirildiyse DoH sunucu ayari, tarayici Guvenli DNS politikasi, C:\Program Files\dpi-lite klasoru
# (otomatik liste dahil). Bu depo klasorune dokunmaz.

. (Join-Path $PSScriptRoot 'ortak.ps1')
if (-not (Yonetici-Mi)) { Yukselt $PSCommandPath ''; return }

$yerel = Yerel-Klasor $PSScriptRoot
Start-Transcript -Path (Join-Path $yerel 'kaldir.log') -Force | Out-Null
$st = Durum-Oku

Say '1/5  Servis ve surucu'
if (Get-Service -Name $ServisAdi -ErrorAction SilentlyContinue) {
    Stop-Service -Name $ServisAdi -Force -ErrorAction SilentlyContinue
    sc.exe delete $ServisAdi | Out-Host
} else { Write-Host 'Servis yok.' }
Get-Process winws -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\WinDivert') {
    sc.exe stop windivert   | Out-Null
    sc.exe delete windivert | Out-Host
} else { Write-Host 'WinDivert surucusu kayitli degil.' }

Say '2/5  DNS kurali'
$names = @(); if ($st -and $st.nrptAdlari) { $names = @($st.nrptAdlari) }
$rules = @(Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object { $_.Comment -eq $Etiket -or $_.DisplayName -eq $Etiket -or ($names -contains $_.Name) })
if ($rules.Count -eq 0) { Write-Host 'Kural yok.' }
foreach ($r in $rules) { Remove-DnsClientNrptRule -Name $r.Name -Force; Write-Host "Silindi: $($r.Name)" }

Say '3/5  DoH sunucu ayari'
$restored = $false
if ($st -and $st.dohOnceki -and (Get-Command Set-DnsClientDohServerAddress -ErrorAction SilentlyContinue)) {
    foreach ($p in @($st.dohOnceki)) {
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

Say '4/5  Tarayici Guvenli DNS politikasi'
$pol = @(); if ($st -and $st.politikalar) { $pol = @($st.politikalar | Where-Object { $_ -and $_.kok }) }
if ($pol.Count -eq 0) { Write-Host 'Bizim koydugumuz politika yok.' }
foreach ($e in $pol) { Politika-Kaldir $e; Write-Host "Geri alindi: $($e.kok)  ($(@($e.degerler) -join ', '))" }

Say '5/5  Dosyalar'
if (Test-Path $Hedef) {
    Remove-Item $Hedef -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $Hedef) { Start-Sleep -Seconds 2; Remove-Item $Hedef -Recurse -Force -ErrorAction SilentlyContinue }   # surucu dosyasi birkac saniye kilitli kalabilir
    if (Test-Path $Hedef) { Write-Host "Tam silinemedi (surucu dosyasi hala kilitli olabilir); yeniden baslattiktan sonra elle silinebilir: $Hedef" -ForegroundColor Yellow }
    else { Write-Host "Silindi: $Hedef" }
} else { Write-Host 'Klasor yok.' }

Say 'OZET'
Write-Host ("Servis: "     + $(if (Get-Service -Name $ServisAdi -ErrorAction SilentlyContinue) { 'HALA VAR (yeniden baslatinca silinir)' } else { 'yok' }))
Write-Host ("DNS kurali: " + @(Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object { $_.Comment -eq $Etiket -or $_.DisplayName -eq $Etiket -or ($names -contains $_.Name) }).Count)
Write-Host ("Internet: "   + $(if (Test-Connection 1.1.1.1 -Count 2 -Quiet) { 'calisiyor' } else { 'YOK' }))
Write-Host 'Kaldirma tamam. Engelli siteler tekrar kapali olacak.' -ForegroundColor Green
Stop-Transcript | Out-Null
