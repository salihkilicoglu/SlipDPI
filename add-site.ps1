# SlipDPI : add a site to the manual list / remove it from the list
# Usage:  add-site.ps1 example.com           (prompts if no name is given)
#         add-site.ps1 example.com -Cikar    (removes it from the list)
# Modifies lists\sites.txt and re-runs install.ps1
# (the service and the DNS rule are refreshed with the new list; takes a few seconds, asks for UAC approval).
# Adding a parent domain covers all its subdomains too (example.com -> www.example.com, cdn.example.com ...).
# -Panel: the control window calls it with this switch (the window closes by itself when the work is done).
param([string]$Alan, [switch]$Cikar, [switch]$Panel)

. (Join-Path $PSScriptRoot 'common.ps1')
if (-not $Alan) { $Alan = Read-Host 'Site adi (ornek: ornek.com)' }
$d = "$Alan".Trim().ToLowerInvariant() -replace '^https?://', '' -replace '/.*$', '' -replace '^www\.', ''
if ($d -notmatch '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$') { Write-Host "Gecersiz alan adi: $Alan" -ForegroundColor Red; Kapanmadan-Bekle; return }

# In the installed layout the list lives under Program Files, so elevate before writing to the file.
if (-not (Yonetici-Mi)) { Yukselt $PSCommandPath ("-Alan $d" + $(if ($Cikar) { ' -Cikar' } else { '' })); return }

$list = Join-Path $PSScriptRoot 'lists\sites.txt'
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

& (Join-Path $PSScriptRoot 'install.ps1') -Kurulumdan:$Panel
