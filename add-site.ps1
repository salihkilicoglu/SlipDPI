# SlipDPI : add a site to the manual list / remove it from the list
# Usage:  add-site.ps1 example.com           (prompts if no name is given)
#         add-site.ps1 example.com -Remove    (removes it from the list)
# Modifies lists\sites.txt and re-runs install.ps1
# (the service and the DNS rule are refreshed with the new list; takes a few seconds, asks for UAC approval).
# Adding a parent domain covers all its subdomains too (example.com -> www.example.com, cdn.example.com ...).
# -Panel: the control window calls it with this switch (the window closes by itself when the work is done).
param([string]$Domain, [switch]$Remove, [switch]$Panel)

. (Join-Path $PSScriptRoot 'common.ps1')
if (-not $Domain) { $Domain = Read-Host (T 'Site name (example: example.com)') }
$d = "$Domain".Trim().ToLowerInvariant() -replace '^https?://', '' -replace '/.*$', '' -replace '^www\.', ''
if ($d -notmatch '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$') { Write-Host (T 'Invalid domain name: {0}' $Domain) -ForegroundColor Red; Wait-BeforeClose; return }

# In the installed layout the list lives under Program Files, so elevate before writing to the file.
if (-not (Test-Admin)) { Invoke-Elevated $PSCommandPath ("-Domain $d" + $(if ($Remove) { ' -Remove' } else { '' })); return }

$list = Join-Path $PSScriptRoot 'lists\sites.txt'
$existing  = @(Get-Lines $list)
if ($Remove) {
    if ($existing -notcontains $d) { Write-Host (T '{0} is not on the list.' $d) }
    else {
        $remaining = @($existing | Where-Object { $_ -ne $d })
        if ($remaining.Count -gt 0) { Set-Content -Path $list -Value $remaining -Encoding ASCII } else { Set-Content -Path $list -Value $null -Encoding ASCII }
        Write-Host (T 'Removed: {0}' $d) -ForegroundColor Green
    }
} elseif ($existing -contains $d) { Write-Host (T '{0} is already on the list.' $d) }
else { Add-Content -Path $list -Value $d -Encoding ASCII; Write-Host (T 'Added: {0}' $d) -ForegroundColor Green }

& (Join-Path $PSScriptRoot 'install.ps1') -FromSetup:$Panel
