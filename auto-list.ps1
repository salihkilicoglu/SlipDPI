# SlipDPI : show the auto list / remove a site from it
#
# Usage:
#   auto-list.ps1                        -> shows the sites the engine added by itself (no admin needed)
#   auto-list.ps1 -Delete example.com       -> removes the site from the auto list AND adds it to
#                                                lists\exclude.txt, so the engine never adds it again
#   auto-list.ps1 -Unexclude example.com  -> removes the site from the exclude list (engine may relearn it)
# Re-runs the install after a change (asks for UAC).
# -Panel: the control window calls it with this switch (the window closes by itself when the work is done).
param([string]$Delete, [string]$Unexclude, [switch]$Panel)

. (Join-Path $PSScriptRoot 'common.ps1')
$exclFile = Join-Path $PSScriptRoot 'lists\exclude.txt'

if (-not $Delete -and -not $Unexclude) {
    if (-not (Test-Path $AutoList)) { Write-Host 'Otomatik liste yok (SlipDPI kurulu degil).'; Wait-BeforeClose; return }
    $l = @(Get-Lines $AutoList)
    Write-Host ("Otomatik listede {0} alan adi var:" -f $l.Count) -ForegroundColor Cyan
    $l | ForEach-Object { Write-Host "  $_" }
    $h = @(Get-Lines $exclFile)
    Write-Host ("`nHaric tutulanlar ({0}): {1}" -f $h.Count, ($h -join ', ')) -ForegroundColor Cyan
    Write-Host "`nListe dosyasi: $AutoList"
    Write-Host "Ne zaman ve neden eklendigi: $AutoLog"
    Wait-BeforeClose
    return
}

$rawPixels = $Delete; if (-not $rawPixels) { $rawPixels = $Unexclude }
$d = "$rawPixels".Trim().ToLowerInvariant() -replace '^https?://', '' -replace '/.*$', '' -replace '^www\.', ''
if ($d -notmatch '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$') { Write-Host "Gecersiz alan adi: $rawPixels" -ForegroundColor Red; Wait-BeforeClose; return }

if (-not (Test-Admin)) { Invoke-Elevated $PSCommandPath $(if ($Delete) { "-Delete $d" } else { "-Unexclude $d" }); return }

if ($Delete) {
    # stop the service first so we do not modify the file while the engine is writing to it
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Get-Process winws -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    if (Test-Path $AutoList) {
        $keep = @(Get-Content $AutoList | Where-Object { $_.Trim() -and $_.Trim().ToLowerInvariant() -ne $d })
        if ($keep.Count -gt 0) { Set-Content -Path $AutoList -Value $keep -Encoding ASCII } else { Set-Content -Path $AutoList -Value $null -Encoding ASCII }
        Write-Host "Otomatik listeden cikarildi: $d"
    }
    if (@(Get-Lines $exclFile) -notcontains $d) { Add-Content -Path $exclFile -Value $d -Encoding ASCII; Write-Host "Haric listesine eklendi: $d" }
} else {
    $remaining = @(Get-Lines $exclFile | Where-Object { $_ -ne $d })
    if ($remaining.Count -gt 0) { Set-Content -Path $exclFile -Value $remaining -Encoding ASCII } else { Set-Content -Path $exclFile -Value $null -Encoding ASCII }
    Write-Host "Haric listesinden cikarildi: $d"
}

& (Join-Path $PSScriptRoot 'install.ps1') -FromSetup:$Panel
