# dpi-lite : listeye engelli site ekleme
# Kullanim:  site-ekle.ps1 ornek.com
# Alan adini lists\siteler.txt dosyasina ekler ve kur.ps1 i yeniden calistirir
# (servis ve DNS kurali yeni listeyle yenilenir; birkac saniye surer, UAC onayi ister).
# Ust alan adini eklemek butun alt adlari da kapsar (ornek.com -> www.ornek.com, cdn.ornek.com ...).
param([Parameter(Mandatory = $true)][string]$Alan)

. (Join-Path $PSScriptRoot 'ortak.ps1')
$d = $Alan.Trim().ToLowerInvariant() -replace '^https?://', '' -replace '/.*$', '' -replace '^www\.', ''
if ($d -notmatch '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$') { Write-Host "Gecersiz alan adi: $Alan" -ForegroundColor Red; return }

$list = Join-Path $PSScriptRoot 'lists\siteler.txt'
if (@(Satirlar $list) -contains $d) { Write-Host "$d zaten listede." }
else { Add-Content -Path $list -Value $d -Encoding ASCII; Write-Host "Eklendi: $d" -ForegroundColor Green }

& (Join-Path $PSScriptRoot 'kur.ps1')
