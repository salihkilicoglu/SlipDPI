# dpi-lite : dagitim dosyalarini uretir
#
#   cikti\dpi-lite-<surum>.zip            : paket (ac, kur.cmd calistir)
#   cikti\dpi-lite-kurulum-<surum>.exe    : kurulum programi (Inno Setup)
#   cikti\SHA256SUMS.txt                  : ikisinin ozetleri
#
# Yalnizca commit'lenmis dosyalari paketler (git archive HEAD); zip ile exe ayni icerikten uretilir.
# Gerekenler: git, Inno Setup 6 (winget install JRSoftware.InnoSetup).  Yonetici gerekmez.
# Kullanim:  powershell -ExecutionPolicy Bypass -File paketle.ps1 -Surum 1.0.0
param([Parameter(Mandatory = $true)][string]$Surum)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if ($Surum -notmatch '^\d+\.\d+\.\d+$') { throw "Surum x.y.z biciminde olmali (verilen: $Surum)" }
if (git -C $root status --porcelain) { Write-Host 'Uyari: commitlenmemis degisiklikler var; paket yalnizca son commiti (HEAD) icerir.' -ForegroundColor Yellow }

$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 bulunamadi (ISCC.exe). Kurmak icin: winget install JRSoftware.InnoSetup' }

$cikti   = Join-Path $root 'cikti'
$derleme = Join-Path $cikti '_derleme'
New-Item -ItemType Directory -Force $cikti | Out-Null
if (Test-Path $derleme) { Remove-Item $derleme -Recurse -Force }
$zip = Join-Path $cikti "dpi-lite-$Surum.zip"
$exe = Join-Path $cikti "dpi-lite-kurulum-$Surum.exe"
Remove-Item $zip, $exe -Force -ErrorAction SilentlyContinue

Write-Host "== zip (git archive HEAD: $(git -C $root rev-parse --short HEAD)) ==" -ForegroundColor Cyan
git -C $root archive --format=zip --prefix=dpi-lite/ -o $zip HEAD
if ($LASTEXITCODE -ne 0) { throw 'git archive basarisiz' }

Write-Host '== kurulum programi (Inno Setup) ==' -ForegroundColor Cyan
Expand-Archive -Path $zip -DestinationPath $derleme -Force
$kaynak = Join-Path $derleme 'dpi-lite'
# Paketteki motor dosyalari depodaki ozet listesiyle ayni mi?
foreach ($line in (Get-Content (Join-Path $kaynak 'bin\SHA256SUMS.txt') | Where-Object { $_.Trim() })) {
    $p = $line.Trim() -split '\s+', 2
    if ((Get-FileHash (Join-Path $kaynak "bin\$($p[1])") -Algorithm SHA256).Hash.ToLowerInvariant() -ne $p[0].ToLowerInvariant()) { throw "Paketteki bin\$($p[1]) ozeti eslesmiyor" }
}
$log = & $iscc "/DAppVer=$Surum" "/DKaynak=$kaynak" "/DCikti=$cikti" (Join-Path $root 'kurulum\dpi-lite.iss')
$kod = $LASTEXITCODE
$log | Set-Content -Path (Join-Path $cikti 'iscc.log') -Encoding UTF8
if ($kod -ne 0) { $log | Select-Object -Last 15 | Out-Host; throw "ISCC basarisiz (cikis kodu $kod)" }
Write-Host ("Kurulum programina giren dosya sayisi: {0}   (ayrinti: cikti\iscc.log)" -f @($log | Where-Object { $_ -match '^\s*Compressing: ' }).Count)
Remove-Item $derleme -Recurse -Force

$sums = foreach ($f in $zip, $exe) { "{0}  {1}" -f (Get-FileHash $f -Algorithm SHA256).Hash.ToLowerInvariant(), (Split-Path $f -Leaf) }
[IO.File]::WriteAllText((Join-Path $cikti 'SHA256SUMS.txt'), (($sums -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
Write-Host '== cikti ==' -ForegroundColor Cyan
Get-Item $zip, $exe | ForEach-Object { "{0,-40} {1,8:N0} KB" -f $_.Name, ($_.Length / 1KB) }
$sums
