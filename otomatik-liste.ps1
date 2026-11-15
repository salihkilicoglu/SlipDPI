# dpi-lite : otomatik listeyi gosterme / listeden site cikarma
#
# Kullanim:
#   otomatik-liste.ps1                 -> motorun kendi ekledigi siteleri gosterir (yonetici gerekmez)
#   otomatik-liste.ps1 -Sil ornek.com  -> siteyi otomatik listeden cikarir VE lists\haric.txt dosyasina ekler,
#                                         boylece motor onu bir daha eklemez. Kurulumu yeniler (UAC ister).
param([string]$Sil)

. (Join-Path $PSScriptRoot 'ortak.ps1')

if (-not $Sil) {
    if (-not (Test-Path $AutoListe)) { Write-Host 'Otomatik liste yok (dpi-lite kurulu degil).'; return }
    $l = @(Satirlar $AutoListe)
    Write-Host ("Otomatik listede {0} alan adi var:" -f $l.Count) -ForegroundColor Cyan
    $l | ForEach-Object { Write-Host "  $_" }
    $h = @(Satirlar (Join-Path $PSScriptRoot 'lists\haric.txt'))
    Write-Host ("`nHaric tutulanlar ({0}): {1}" -f $h.Count, ($h -join ', ')) -ForegroundColor Cyan
    Write-Host "`nNe zaman ve neden eklendigi: $AutoKayit"
    return
}

$d = $Sil.Trim().ToLowerInvariant() -replace '^https?://', '' -replace '/.*$', '' -replace '^www\.', ''
if ($d -notmatch '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$') { Write-Host "Gecersiz alan adi: $Sil" -ForegroundColor Red; return }

if (-not (Yonetici-Mi)) { Yukselt $PSCommandPath "-Sil $d"; return }

# motor dosyaya yazarken degistirmemek icin once servisi durdur
Stop-Service -Name $ServisAdi -Force -ErrorAction SilentlyContinue
Get-Process winws -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
if (Test-Path $AutoListe) {
    $keep = @(Get-Content $AutoListe | Where-Object { $_.Trim() -and $_.Trim().ToLowerInvariant() -ne $d })
    if ($keep.Count -gt 0) { Set-Content -Path $AutoListe -Value $keep -Encoding ASCII } else { Set-Content -Path $AutoListe -Value $null -Encoding ASCII }
    Write-Host "Otomatik listeden cikarildi: $d"
}
$haric = Join-Path $PSScriptRoot 'lists\haric.txt'
if (@(Satirlar $haric) -notcontains $d) { Add-Content -Path $haric -Value $d -Encoding ASCII; Write-Host "Haric listesine eklendi: $d" }

& (Join-Path $PSScriptRoot 'kur.ps1')
