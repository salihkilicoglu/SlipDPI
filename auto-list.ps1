# SlipDPI : show the auto list / remove a site from it
#
# Usage:
#   auto-list.ps1                        -> shows the sites the engine added by itself (no admin needed)
#   auto-list.ps1 -Sil example.com       -> removes the site from the auto list AND adds it to
#                                                lists\exclude.txt, so the engine never adds it again
#   auto-list.ps1 -HaricSil example.com  -> removes the site from the exclude list (engine may relearn it)
# Re-runs the install after a change (asks for UAC).
# -Panel: the control window calls it with this switch (the window closes by itself when the work is done).
param([string]$Sil, [string]$HaricSil, [switch]$Panel)

. (Join-Path $PSScriptRoot 'common.ps1')
$haric = Join-Path $PSScriptRoot 'lists\exclude.txt'

if (-not $Sil -and -not $HaricSil) {
    if (-not (Test-Path $AutoListe)) { Write-Host 'Otomatik liste yok (SlipDPI kurulu degil).'; Kapanmadan-Bekle; return }
    $l = @(Satirlar $AutoListe)
    Write-Host ("Otomatik listede {0} alan adi var:" -f $l.Count) -ForegroundColor Cyan
    $l | ForEach-Object { Write-Host "  $_" }
    $h = @(Satirlar $haric)
    Write-Host ("`nHaric tutulanlar ({0}): {1}" -f $h.Count, ($h -join ', ')) -ForegroundColor Cyan
    Write-Host "`nListe dosyasi: $AutoListe"
    Write-Host "Ne zaman ve neden eklendigi: $AutoKayit"
    Kapanmadan-Bekle
    return
}

$ham = $Sil; if (-not $ham) { $ham = $HaricSil }
$d = "$ham".Trim().ToLowerInvariant() -replace '^https?://', '' -replace '/.*$', '' -replace '^www\.', ''
if ($d -notmatch '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$') { Write-Host "Gecersiz alan adi: $ham" -ForegroundColor Red; Kapanmadan-Bekle; return }

if (-not (Yonetici-Mi)) { Yukselt $PSCommandPath $(if ($Sil) { "-Sil $d" } else { "-HaricSil $d" }); return }

if ($Sil) {
    # stop the service first so we do not modify the file while the engine is writing to it
    Stop-Service -Name $ServisAdi -Force -ErrorAction SilentlyContinue
    Get-Process winws -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    if (Test-Path $AutoListe) {
        $keep = @(Get-Content $AutoListe | Where-Object { $_.Trim() -and $_.Trim().ToLowerInvariant() -ne $d })
        if ($keep.Count -gt 0) { Set-Content -Path $AutoListe -Value $keep -Encoding ASCII } else { Set-Content -Path $AutoListe -Value $null -Encoding ASCII }
        Write-Host "Otomatik listeden cikarildi: $d"
    }
    if (@(Satirlar $haric) -notcontains $d) { Add-Content -Path $haric -Value $d -Encoding ASCII; Write-Host "Haric listesine eklendi: $d" }
} else {
    $kalan = @(Satirlar $haric | Where-Object { $_ -ne $d })
    if ($kalan.Count -gt 0) { Set-Content -Path $haric -Value $kalan -Encoding ASCII } else { Set-Content -Path $haric -Value $null -Encoding ASCII }
    Write-Host "Haric listesinden cikarildi: $d"
}

& (Join-Path $PSScriptRoot 'install.ps1') -Kurulumdan:$Panel
