# dpi-lite : elle listeye site ekleme / listeden cikarma
# Kullanim:  site-ekle.ps1 ornek.com           (ad verilmezse sorar)
#            site-ekle.ps1 ornek.com -Cikar    (listeden cikarir)
# lists\siteler.txt dosyasini degistirir ve kur.ps1 i yeniden calistirir
# (servis ve DNS kurali yeni listeyle yenilenir; birkac saniye surer, UAC onayi ister).
# Ust alan adini eklemek butun alt adlari da kapsar (ornek.com -> www.ornek.com, cdn.ornek.com ...).
# -Panel: kontrol penceresi bu anahtarla cagirir (is bitince pencere kendiliginden kapanir).
param([string]$Alan, [switch]$Cikar, [switch]$Panel)

. (Join-Path $PSScriptRoot 'ortak.ps1')
if (-not $Alan) { $Alan = Read-Host 'Site adi (ornek: ornek.com)' }
$d = "$Alan".Trim().ToLowerInvariant() -replace '^https?://', '' -replace '/.*$', '' -replace '^www\.', ''
if ($d -notmatch '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$') { Write-Host "Gecersiz alan adi: $Alan" -ForegroundColor Red; Kapanmadan-Bekle; return }

# Liste kurulu duzende Program Files altinda durdugu icin dosyaya yazmadan once yukselt.
if (-not (Yonetici-Mi)) { Yukselt $PSCommandPath ("-Alan $d" + $(if ($Cikar) { ' -Cikar' } else { '' })); return }

$list = Join-Path $PSScriptRoot 'lists\siteler.txt'
$var  = @(Satirlar $list)
if ($Cikar) {
    if ($var -notcontains $d) { Write-Host "$d listede yok." }
    else {
        $kalan = @($var | Where-Object { $_ -ne $d })
        if ($kalan.Count -gt 0) { Set-Content -Path $list -Value $kalan -Encoding ASCII } else { Set-Content -Path $list -Value $null -Encoding ASCII }
        Write-Host "Cikarildi: $d" -ForegroundColor Green
    }
} elseif ($var -contains $d) { Write-Host "$d zaten listede." }
else { Add-Content -Path $list -Value $d -Encoding ASCII; Write-Host "Eklendi: $d" -ForegroundColor Green }

& (Join-Path $PSScriptRoot 'kur.ps1') -Kurulumdan:$Panel
