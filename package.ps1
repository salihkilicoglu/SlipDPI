# SlipDPI : builds the distribution files
#
#   dist\SlipDPI-<version>.zip          : package (extract, run install.cmd)
#   dist\SlipDPI-setup-<version>.exe  : installer (Inno Setup)
#   dist\SHA256SUMS.txt                  : hashes of both
#
# Packages only committed files (git archive HEAD); the zip and the exe are built from the same content.
# Requires: git, Inno Setup 6 (winget install JRSoftware.InnoSetup).  Administrator rights not needed.
# Usage:  powershell -ExecutionPolicy Bypass -File package.ps1 -Version 1.0.0
param([Parameter(Mandatory = $true)][string]$Version)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Surum x.y.z biciminde olmali (verilen: $Version)" }
if (git -C $root status --porcelain) { Write-Host 'Uyari: commitlenmemis degisiklikler var; paket yalnizca son commiti (HEAD) icerir.' -ForegroundColor Yellow }

$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 bulunamadi (ISCC.exe). Kurmak icin: winget install JRSoftware.InnoSetup' }

$outDir   = Join-Path $root 'dist'
$buildDir = Join-Path $outDir '_build'
New-Item -ItemType Directory -Force $outDir | Out-Null
if (Test-Path $buildDir) { Remove-Item $buildDir -Recurse -Force }
$zip = Join-Path $outDir "SlipDPI-$Version.zip"
$exe = Join-Path $outDir "SlipDPI-setup-$Version.exe"
Remove-Item $zip, $exe -Force -ErrorAction SilentlyContinue

Write-Host "== zip (git archive HEAD: $(git -C $root rev-parse --short HEAD)) ==" -ForegroundColor Cyan
git -C $root archive --format=zip --prefix=SlipDPI/ -o $zip HEAD
if ($LASTEXITCODE -ne 0) { throw 'git archive basarisiz' }

Write-Host '== kurulum programi (Inno Setup) ==' -ForegroundColor Cyan
Expand-Archive -Path $zip -DestinationPath $buildDir -Force
$sourceDir = Join-Path $buildDir 'SlipDPI'
# Do the engine files in the package match the hash list in the repository?
foreach ($line in (Get-Content (Join-Path $sourceDir 'bin\SHA256SUMS.txt') | Where-Object { $_.Trim() })) {
    $p = $line.Trim() -split '\s+', 2
    if ((Get-FileHash (Join-Path $sourceDir "bin\$($p[1])") -Algorithm SHA256).Hash.ToLowerInvariant() -ne $p[0].ToLowerInvariant()) { throw "Paketteki bin\$($p[1]) ozeti eslesmiyor" }
}
$log = & $iscc "/DAppVer=$Version" "/DSourceDir=$sourceDir" "/DOutputDir=$outDir" (Join-Path $root 'installer\SlipDPI.iss')
$exitCode = $LASTEXITCODE
$log | Set-Content -Path (Join-Path $outDir 'iscc.log') -Encoding UTF8
if ($exitCode -ne 0) { $log | Select-Object -Last 15 | Out-Host; throw "ISCC basarisiz (cikis kodu $exitCode)" }
Write-Host ("Kurulum programina giren dosya sayisi: {0}   (ayrinti: dist\iscc.log)" -f @($log | Where-Object { $_ -match '^\s*Compressing: ' }).Count)
Remove-Item $buildDir -Recurse -Force

$sums = foreach ($f in $zip, $exe) { "{0}  {1}" -f (Get-FileHash $f -Algorithm SHA256).Hash.ToLowerInvariant(), (Split-Path $f -Leaf) }
[IO.File]::WriteAllText((Join-Path $outDir 'SHA256SUMS.txt'), (($sums -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
Write-Host '== cikti ==' -ForegroundColor Cyan
Get-Item $zip, $exe | ForEach-Object { "{0,-40} {1,8:N0} KB" -f $_.Name, ($_.Length / 1KB) }
$sums
