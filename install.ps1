# SlipDPI : install  (re-runnable; same script for a first install and for installing over an existing copy)
#
# What it does:
#   1) Runs the strategy test if no strategy has been picked for this line yet (local\strategy.json).
#   2) Syncs the bin, filters and lists folders into C:\Program Files\SlipDPI.
#   3) Creates an auto-start Windows service named "SlipDPI" (zapret winws):
#        lists\discord.txt + lists\sites.txt : domains that are always processed
#        auto.txt                          : the list the engine fills in by itself
#        lists\exclude.txt                       : domains never processed / never auto-added
#   4) Routes DNS to the encrypted DNS server ONLY for the domains in the lists (NRPT rule).
#      All other names stay on the modem/ISP DNS.
#   5) Turns on "Secure DNS" by policy in the selected browsers ($TarayiciDns below).
#   6) Connects and verifies the result, tests that the auto list learns; writes to local\install.log.
#
# Undo: uninstall.ps1
#
# -FromSetup : the setup program and the control window call it with this switch. At the end the script
#               does not close the window right away and reports the result via its exit code (0 = ok,
#               1 = stopped, 2 = verification did not fully pass).
# -Retest: sets the saved strategy choice aside, tests the line from scratch and picks again.
param([switch]$FromSetup, [switch]$Retest)

# ---- SETTINGS --------------------------------------------------------------------------------------
# DNS for the names in the lists. Google: returns a nearby server because it forwards the client location.
$DnsServers      = @('8.8.8.8', '8.8.4.4')
$DohTemplates      = @{ '8.8.8.8' = 'https://dns.google/dns-query'; '8.8.4.4' = 'https://dns.google/dns-query'
                     '1.1.1.1' = 'https://cloudflare-dns.com/dns-query'; '1.0.0.1' = 'https://cloudflare-dns.com/dns-query' }
# Known fake addresses that ISPs return for blocked names (Turk Telekom). The list may be incomplete;
# the real check is done by comparing the answer with the encrypted DNS answer.
$KnownBlockIps = @('195.175.254.2')
# Browsers in which Secure DNS is turned on by policy: 'chrome', 'edge', 'brave'. If left empty ( @() )
# the browser setting is not touched. Once the policy is set the browser shows "managed by your
# organization" and the Secure DNS setting is locked; uninstall.ps1 reverts it.
$BrowserDns    = @('chrome')
$BrowserDoh    = [ordered]@{ DnsOverHttpsMode = 'automatic'; DnsOverHttpsTemplates = 'https://dns.google/dns-query{?dns}' }
# A name that is blocked but NOT in the manual lists; used at the end of install to test the auto list.
$LearnTestDomain   = 'wattpad.com'
$QuicRepeats     = 4
# ------------------------------------------------------------------------------------------------

. (Join-Path $PSScriptRoot 'common.ps1')
$extraArgs = @(); if ($FromSetup) { $extraArgs += '-FromSetup' }; if ($Retest) { $extraArgs += '-Retest' }
Ensure-64Bit $PSCommandPath ($extraArgs -join ' ')
# (-FromSetup is not passed on when self-elevating: that window stays open anyway.)
if (-not (Test-Admin)) { Invoke-Elevated $PSCommandPath $(if ($Retest) { '-Retest' } else { '' }); return }

Disable-QuickEdit      # so that clicking the window does not freeze the install
$root  = $PSScriptRoot
$localDir = Get-LocalDir $root
Start-Transcript -Path (Join-Path $localDir 'install.log') -Force | Out-Null
function Q($p) { '"' + $p + '"' }
function Fail($msg) {
    Write-Host ("`n" + (T 'STOPPED: {0}' $msg)) -ForegroundColor Red
    Stop-Transcript | Out-Null
    if ($FromSetup) { Read-Host ("`n" + (T 'Press Enter to close')) | Out-Null; exit 1 }
    throw (T 'SlipDPI install stopped: {0}' $msg)
}

function Probe($url, $name, $ip) {
    $a = @('-s', '-o', 'NUL', '-w', '%{http_code}|%{time_appconnect}|%{exitcode}', '--ssl-no-revoke', '--connect-timeout', '4', '--max-time', '8')
    if ($ip) { $a += @('--resolve', "${name}:443:${ip}") }
    $o = & curl.exe @a $url
    $p = "$o".Split('|')
    [pscustomobject]@{ url = $url; ok = ($p[0] -ne '000' -and $p[0] -ne ''); code = $p[0]; tls = $p[1]; exit = $p[2] }
}

# Gets a name's real addresses from encrypted DNS, which the ISP cannot tamper with.
function Resolve-RealIp($name) {
    foreach ($u in "https://dns.google/resolve?name=$name&type=A", "https://cloudflare-dns.com/dns-query?name=$name&type=A") {
        try {
            $a = @((Invoke-RestMethod -Uri $u -Headers @{ accept = 'application/dns-json' } -TimeoutSec 8).Answer | Where-Object { $_.type -eq 1 } | ForEach-Object { $_.data })
            if ($a.Count -gt 0) { return $a }
        } catch { }
    }
    @()
}

# Does the system DNS answer correctly for this name?  It counts as "dirty" if a known fake address
# comes back or the answer is not in the same network (/16) as the real addresses.
function Test-DnsClean($name, $ref) {
    try { $sys = @(Resolve-DnsName -Name $name -Type A -DnsOnly -ErrorAction Stop | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress }) } catch { return $false }
    if ($sys.Count -eq 0) { return $false }
    foreach ($ip in $sys) { if ($KnownBlockIps -contains $ip) { return $false } }
    if (@($ref).Count -eq 0) { return $true }
    $refNets = @($ref | ForEach-Object { ($_ -split '\.')[0..1] -join '.' })
    foreach ($ip in $sys) { if ($refNets -contains (($ip -split '\.')[0..1] -join '.')) { return $true } }
    $false
}

# Syncs the source folder to the target file by file: leaves identical files alone (fine even if locked),
# overwrites differing ones, deletes files and subfolders that are not in the source.
function Sync-File($src, $dst) {
    New-Item -ItemType Directory -Force $dst | Out-Null
    $srcFiles = @(Get-ChildItem $src -File)
    foreach ($f in $srcFiles) {
        $t = Join-Path $dst $f.Name
        $same = $false
        if (Test-Path $t) { try { $same = ((Get-FileHash $t -Algorithm SHA256 -ErrorAction Stop).Hash -eq (Get-FileHash $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash) } catch { $same = $false } }
        if ($same) { continue }
        try { Copy-Item $f.FullName $t -Force -ErrorAction Stop } catch { Fail (T 'Could not copy: {0}  ({1})' $t $_.Exception.Message) }
    }
    $names = @($srcFiles | ForEach-Object { $_.Name })
    foreach ($x in @(Get-ChildItem $dst -Force)) {
        if ($x.PSIsContainer -or ($names -notcontains $x.Name)) { Remove-Item $x.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ---- 0) pre-checks --------------------------------------------------------------------------
Write-Step (T '0/7  Pre-checks')
if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { Fail (T 'Only 64-bit (x64) Windows is supported. This machine: {0}' $env:PROCESSOR_ARCHITECTURE) }
foreach ($f in 'bin\winws.exe', 'bin\WinDivert.dll', 'bin\WinDivert64.sys', 'bin\cygwin1.dll', 'bin\SHA256SUMS.txt',
               'filters\windivert_part.quic_initial_ietf.txt', 'filters\windivert_part.discord_media.txt',
               'lists\discord.txt', 'lists\sites.txt', 'lists\exclude.txt') {
    if (-not (Test-Path (Join-Path $root $f))) { Fail (T 'Missing file: {0}' $f) }
}
# Do the engine files match the hashes stored in the repository? (detects download corruption or tampering)
foreach ($line in (Get-Lines (Join-Path $root 'bin\SHA256SUMS.txt'))) {
    $parts = $line -split '\s+', 2
    if ($parts.Count -ne 2) { continue }
    $got = (Get-FileHash (Join-Path $root "bin\$($parts[1])") -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($got -ne $parts[0]) { Fail (T 'The hash of bin\{0} does not match SHA256SUMS.txt. Download the repository again.' $parts[1]) }
}
$foreign = @(Get-Process goodbyedpi, ciadpi, winws2 -ErrorAction SilentlyContinue)
if ($foreign.Count -gt 0) { Fail (T 'Another DPI tool is running: {0}. Close it first.' $foreign[0].ProcessName) }
$dohPresent = [bool](Get-Command Set-DnsClientDohServerAddress -ErrorAction SilentlyContinue)
if (-not $dohPresent) { Write-Host (T 'Note: this Windows version has no system-level encrypted DNS (DoH) (Windows 11 is required). The DNS block may not be bypassed in apps other than the browser.') -ForegroundColor Yellow }
Write-Host (T 'OK: files are in place and their hashes are correct.')

# ---- 1) stop the old install -------------------------------------------------------------------
Write-Step (T '1/7  Previous install')
$old = Read-State
if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
    Write-Host (T 'Stopping and removing the previous SlipDPI service...')
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $ServiceName | Out-Null
    for ($i = 0; $i -lt 20; $i++) { if (-not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) { break }; Start-Sleep -Milliseconds 300 }
} else { Write-Host (T 'No previous service.') }
Get-Process winws -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
# The WinDivert driver stays loaded after the engine exits and locks the .sys file; unload it too.
# (The service loads the driver again by itself when it restarts.)
if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\WinDivert') {
    sc.exe stop windivert   | Out-Null
    sc.exe delete windivert | Out-Null
    for ($i = 0; $i -lt 10; $i++) {
        if (-not (Get-CimInstance Win32_SystemDriver -Filter "Name='WinDivert'" -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Running' })) { break }
        Start-Sleep -Milliseconds 300
    }
}

# ---- 2) strategy -------------------------------------------------------------------------------
Write-Step (T '2/7  Strategy')
$strategyFile = Join-Path $localDir 'strategy.json'
if ($Retest -and (Test-Path $strategyFile)) {
    Move-Item $strategyFile (Join-Path $localDir 'strategy.previous.json') -Force
    Write-Host (T 'The previous choice was set aside (strategy.previous.json); the line will be tested again.')
}
if (-not (Test-Path $strategyFile)) {
    Write-Host (T 'No strategy has been picked for this line; running the strategy test (takes a few minutes)...')
    try { & (Join-Path $root 'strategy-test.ps1') -Nested } catch { Fail (T 'The strategy test did not run: {0}' $_.Exception.Message) }
    if (-not (Test-Path $strategyFile)) { Fail (T 'The strategy test found no working setting on this line. Details: local\strategy-test.json') }
}
try { $strat = Get-Content $strategyFile -Raw | ConvertFrom-Json } catch { Fail (T 'Could not read local\strategy.json: {0}' $_.Exception.Message) }
$TcpStrategy = "$($strat.tcp)".Trim()
$Ttl = 0; if ($strat.ttl) { $Ttl = [int]$strat.ttl }
if (-not $TcpStrategy -or $TcpStrategy -notmatch '^--dpi-desync=') { Fail (T 'There is no valid strategy in local\strategy.json. Delete the file and run install.ps1 again.') }
Write-Host (T 'Strategy: {0}   (source: {1}, {2})' $TcpStrategy $strat.source $strat.selectedAt)
if ($Ttl -le 0) { Write-Host (T 'This strategy does not use TTL; the QUIC and voice rules will not be added (the browser falls back to TCP).') -ForegroundColor Yellow }

# ---- 3) files -------------------------------------------------------------------------------
Write-Step (T '3/7  Files')
New-Item -ItemType Directory -Force $InstallDir | Out-Null
if (Test-InstalledLayout $root) {
    Write-Host (T 'The package was installed into this folder by the setup program; no copying needed: {0}' $InstallDir)
} else {
    foreach ($d in 'bin', 'filters', 'lists') { Sync-File (Join-Path $root $d) (Join-Path $InstallDir $d) }
    Write-Host (T 'Synced: {0}' $InstallDir)
}
# the auto list is kept across reinstalls; created empty if missing
if (-not (Test-Path $AutoList)) { Set-Content -Path $AutoList -Value $null -Encoding ASCII }
Write-Host (T 'The auto list currently has {0} domains.' (@(Get-Lines $AutoList).Count))

# ---- 4) engine config and service ------------------------------------------------------------------
Write-Step (T '4/7  Engine and service')
$hl   = '--hostlist=' + (Q "$InstallDir\lists\discord.txt") + ' --hostlist=' + (Q "$InstallDir\lists\sites.txt")
$exc  = '--hostlist-exclude=' + (Q "$InstallDir\lists\exclude.txt")
$auto = '--hostlist-auto=' + (Q $AutoList) + ' --hostlist-auto-debug=' + (Q $AutoLog)
$wfFilter   = @('--wf-tcp=443')
$profiles = @("--filter-tcp=443 $hl $exc $auto $TcpStrategy")
if ($Ttl -gt 0) {
    $wfFilter += ('--wf-raw-part=@' + (Q "$InstallDir\filters\windivert_part.quic_initial_ietf.txt"))
    $wfFilter += ('--wf-raw-part=@' + (Q "$InstallDir\filters\windivert_part.discord_media.txt"))
    $profiles += ("--filter-l7=quic $hl --hostlist=" + (Q $AutoList) + " $exc --dpi-desync=fake --dpi-desync-repeats=$QuicRepeats --dpi-desync-ttl=$Ttl")
    $profiles += "--filter-l7=discord --dpi-desync=fake --dpi-desync-repeats=$QuicRepeats --dpi-desync-ttl=$Ttl"
}
$engineArgs = ($wfFilter -join ' ') + ' ' + ($profiles -join ' --new ')
$exe = "$InstallDir\bin\winws.exe"
foreach ($f in 'winws.exe', 'WinDivert.dll', 'WinDivert64.sys', 'cygwin1.dll') {
    if (-not (Test-Path (Join-Path "$InstallDir\bin" $f))) { Fail (T 'An engine file is missing in the install folder: {0}' "$InstallDir\bin\$f") }
}
# The engine's full command line is long and unreadable, so it is written to a file, not the screen.
Set-Content -Path (Join-Path $localDir 'engine-args.txt') -Value $engineArgs -Encoding ASCII
Write-Host (T 'Rules: {0}   (full command line: {1})' $profiles.Count (Join-Path $localDir 'engine-args.txt'))
$dry = Start-Process -FilePath $exe -ArgumentList "$engineArgs --dry-run" -WorkingDirectory "$InstallDir\bin" -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput (Join-Path $localDir 'install-dryrun.out.txt') -RedirectStandardError (Join-Path $localDir 'install-dryrun.err.txt')
if ($dry.ExitCode -ne 0) {
    Get-Content (Join-Path $localDir 'install-dryrun.out.txt'), (Join-Path $localDir 'install-dryrun.err.txt') -ErrorAction SilentlyContinue | Select-Object -Last 8 | Out-Host
    Fail (T 'The engine configuration could not be validated (exit code {0}). The service was not created.' $dry.ExitCode)
}
Write-Host (T 'The engine itself accepted the configuration.') -ForegroundColor Green

try {
    New-Service -Name $ServiceName -BinaryPathName ((Q $exe) + ' ' + $engineArgs) -DisplayName 'SlipDPI (zapret winws)' `
        -Description (T 'Modifies the opening packet of connections going only to the blocked domains on the list. To remove: SlipDPI\uninstall.ps1') `
        -StartupType Automatic -ErrorAction Stop | Out-Null
} catch { Fail (T 'Could not create the service: {0}' $_.Exception.Message) }
sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/5000/restart/60000 | Out-Null
try { Start-Service -Name $ServiceName -ErrorAction Stop } catch { Write-Host (T 'Could not start the service: {0}' $_.Exception.Message) -ForegroundColor Yellow }
Start-Sleep -Seconds 2
$svc = Get-Service -Name $ServiceName
if ($svc.Status -ne 'Running' -or -not (Get-Process winws -ErrorAction SilentlyContinue)) { Fail (T 'The service is not running (status: {0}). Antivirus may be blocking the WinDivert driver.' $svc.Status) }
Write-Host (T 'The service is running and will start automatically at boot.') -ForegroundColor Green

# ---- 5) DNS: only for the names in the lists --------------------------------------------------
Write-Step (T '5/7  DNS (only the domains in the lists)')
$oldNames = @(); if ($old -and $old.nrptNames) { $oldNames = @($old.nrptNames) }

# Servers whose DoH setting we changed in a previous install: keep the record if still in use,
# restore the original setting if no longer in use.
$kept = @()
if ($dohPresent -and $old -and $old.dohPrevious) {
    foreach ($p in @($old.dohPrevious)) {
        if (-not $p -or -not $p.ServerAddress) { continue }
        if ($DnsServers -contains $p.ServerAddress) { $kept += $p; continue }
        try {
            Set-DnsClientDohServerAddress -ServerAddress $p.ServerAddress -AutoUpgrade ([bool]$p.AutoUpgrade) -AllowFallbackToUdp ([bool]$p.AllowFallbackToUdp) -ErrorAction Stop | Out-Null
            Write-Host (T 'A DNS server that is no longer used was restored to its original setting: {0}' $p.ServerAddress)
        } catch { Write-Host (T 'Could not restore the DNS server setting ({0}): {1}' $p.ServerAddress $_.Exception.Message) -ForegroundColor Yellow }
    }
}

$exclFile   = Get-Lines "$InstallDir\lists\exclude.txt"
$domains = @(@(Get-Lines "$InstallDir\lists\discord.txt") + @(Get-Lines "$InstallDir\lists\sites.txt") + @(Get-Lines $AutoList) | Where-Object { $exclFile -notcontains $_ } | Select-Object -Unique)
$namespaces = @(); foreach ($d in $domains) { $namespaces += $d; $namespaces += ".$d" }
foreach ($r in @(Get-DnsClientNrptRule -ErrorAction SilentlyContinue)) {
    if ($r.Comment -eq $Label -or $r.DisplayName -eq $Label -or ($oldNames -contains $r.Name)) { Remove-DnsClientNrptRule -Name $r.Name -Force }
}
$rule = Add-DnsClientNrptRule -Namespace $namespaces -NameServers $DnsServers -Comment $Label -DisplayName $Label -PassThru
Clear-DnsClientCache
Start-Sleep -Seconds 1

$dnsName  = 'discord.com'
$dnsRef = Resolve-RealIp $dnsName
$enforced = ($kept.Count -gt 0)
$dnsOk = Test-DnsClean $dnsName $dnsRef
if (-not $dnsOk -and $dohPresent) {
    Write-Host (T 'Plain DNS queries are being dropped or altered. Enforcing encrypted DNS (DoH) for these servers...')
    foreach ($s in $DnsServers) {
        $cur = Get-DnsClientDohServerAddress -ServerAddress $s -ErrorAction SilentlyContinue
        if ($cur) {
            if (-not (@($kept | ForEach-Object { $_.ServerAddress }) -contains $s)) {
                $kept += [pscustomobject]@{ ServerAddress = $s; AutoUpgrade = [bool]$cur.AutoUpgrade; AllowFallbackToUdp = [bool]$cur.AllowFallbackToUdp }
            }
            Set-DnsClientDohServerAddress -ServerAddress $s -AutoUpgrade $true -AllowFallbackToUdp $false | Out-Null
        } else {
            Add-DnsClientDohServerAddress -ServerAddress $s -DohTemplate $DohTemplates[$s] -AutoUpgrade $true -AllowFallbackToUdp $false | Out-Null
        }
    }
    $enforced = $true
    Clear-DnsClientCache
    Start-Sleep -Seconds 2
    $dnsOk = Test-DnsClean $dnsName $dnsRef
}
$level = 0
if ($dnsOk) { if ($enforced) { $level = 2 } else { $level = 1 } }
if ($dnsOk) { Write-Host (T 'DNS for {0} domains is resolved through {1} (level {2}); other names stay on the modem DNS.' $domains.Count ($DnsServers -join ', ') $level) -ForegroundColor Green }
else        { Write-Host (T 'DNS step FAILED: {0} still does not resolve correctly. The engine is running but apps other than the browser (Discord) may not open.' $dnsName) -ForegroundColor Yellow }
try { Write-Host ("$dnsName -> " + ((Resolve-DnsName $dnsName -Type A -DnsOnly -ErrorAction Stop | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress }) -join ', ')) } catch { Write-Host (T '{0} -> could not be resolved' $dnsName) }

# ---- 6) browser: Secure DNS policy -------------------------------------------------------
Write-Step (T '6/7  Browser Secure DNS')
$oldPolicy = @(); if ($old -and $old.policies) { $oldPolicy = @($old.policies | Where-Object { $_ -and $_.root }) }
$newPolicy = @()
# revert the policy we set earlier in browsers that are no longer wanted
$wantedRoots = @($BrowserDns | ForEach-Object { $PolicyRoots[$_] } | Where-Object { $_ })
foreach ($e in $oldPolicy) {
    if ($wantedRoots -notcontains $e.root) { Remove-Policy $e; Write-Host (T 'Policy reverted: {0}' $e.root) }
}
if (@($BrowserDns).Count -eq 0) { Write-Host (T 'Browser setting left untouched ($BrowserDns is empty).') }
foreach ($t in @($BrowserDns)) {
    $rootKey = $PolicyRoots[$t]
    if (-not $rootKey) { Write-Host (T 'Unknown browser name: {0} (skipped)' $t) -ForegroundColor Yellow; continue }
    $previous = $oldPolicy | Where-Object { $_.root -eq $rootKey } | Select-Object -First 1
    if (-not (Test-BrowserInstalled $t) -and -not $previous) { Write-Host (T '{0} is not installed, skipped.' $t); continue }
    $result = Apply-Policy $rootKey $BrowserDoh $previous
    $newPolicy += $result.record
    foreach ($n in $result.notes) { Write-Host "  ${t}: $n" -ForegroundColor Yellow }
    Write-Host (T '{0}: Secure DNS policy written ({1}). The browser picks it up within a few seconds; the setting now appears locked.' $t (@($result.record.values) -join ', ')) -ForegroundColor Green
}

$state = [ordered]@{ installedAt = (Get-Date).ToString('s'); strategy = $TcpStrategy; ttl = $Ttl; dnsLevel = $level; dnsServers = $DnsServers
                     nrptNames = @($rule | ForEach-Object { $_.Name }); dohPrevious = @($kept); policies = @($newPolicy) }
[pscustomobject]$state | ConvertTo-Json -Depth 6 | Set-Content -Path $StatePath -Encoding UTF8

# ---- 7) end-to-end verification (system DNS + engine together) ------------------------------------
Write-Step (T '7/7  Verification')
$blocked  = 'https://discord.com/api/v9/gateway', 'https://gateway.discord.gg/', 'https://cdn.discordapp.com/', 'https://updates.discord.com/'
$controls = 'https://www.google.com/generate_204', 'https://github.com/', 'https://www.cloudflare.com/cdn-cgi/trace'
$bOk = 0; $cOk = 0
foreach ($u in $blocked)  { $r = Probe $u; if ($r.ok) { $bOk++ }; Write-Host ("  {0,-6} {1,-42} http={2} tls={3}s" -f $(if ($r.ok) { T 'OPEN' } else { T 'CLOSED' }), $u, $r.code, $r.tls) }
foreach ($u in $controls) { $r = Probe $u; if ($r.ok) { $cOk++ }; Write-Host (T '  {0,-6} {1,-42} http={2} tls={3}s   (control)' $(if ($r.ok) { T 'OPEN' } else { T 'CLOSED' }) $u $r.code $r.tls) }

# Auto list: keep connecting to a blocked name not in the manual lists and wait for the engine to learn it.
Write-Step (T 'Auto list test ({0})' $LearnTestDomain)
$autoResult = 'not-run'
$staticList = @(@(Get-Lines "$InstallDir\lists\discord.txt") + @(Get-Lines "$InstallDir\lists\sites.txt"))
if ($staticList -contains $LearnTestDomain) {
    $autoResult = 'skipped'
    Write-Host (T '{0} is on the manual list, so the test was skipped.' $LearnTestDomain)
} elseif ($exclFile -contains $LearnTestDomain) {
    $autoResult = 'skipped'
    Write-Host (T '{0} is on the exclude list, so the test was skipped.' $LearnTestDomain)
} else {
    $ip = Resolve-RealIp $LearnTestDomain | Select-Object -First 1
    if (-not $ip) { Write-Host (T 'Could not get the real address; the test was not run.') -ForegroundColor Yellow }
    else {
        $existedBefore = @(Get-Lines $AutoList) -contains $LearnTestDomain
        Write-Host (T 'Real address: {0}   in the auto list before the test: {1}' $ip $(if ($existedBefore) { T 'yes' } else { T 'no' }))
        $opened = 0
        for ($i = 1; $i -le 8; $i++) {
            $r = Probe "https://$LearnTestDomain/" $LearnTestDomain $ip
            Write-Host (T '  attempt {0}: {1}  http={2} exit={3}' $i $(if ($r.ok) { T 'OPEN' } else { T 'CLOSED' }) $r.code $r.exit)
            if ($r.ok) { $opened = $i; break }
            Start-Sleep -Milliseconds 1200
        }
        Start-Sleep -Milliseconds 500
        $presentNow = @(Get-Lines $AutoList) -contains $LearnTestDomain
        if ($opened -eq 1 -and -not $presentNow -and -not $existedBefore) { $autoResult = 'unblocked';  Write-Host (T 'This name is not blocked on this line; learning could not be tested.') -ForegroundColor Yellow }
        elseif ($opened -gt 0 -and $presentNow -and $existedBefore)       { $autoResult = 'already';     Write-Host (T 'Already learned, opened right away.') -ForegroundColor Green }
        elseif ($opened -gt 0 -and $presentNow)                       { $autoResult = 'learned';   Write-Host (T 'The engine added the site to the list by itself on attempt {0} and opened it.' $opened) -ForegroundColor Green }
        elseif ($opened -gt 0)                                      { $autoResult = 'unclear';  Write-Host (T 'The site opened but is not in the auto list.') -ForegroundColor Yellow }
        else                                                        { $autoResult = 'not-learned'; Write-Host (T 'Did not open in 8 attempts. In the auto list: {0}' $(if ($presentNow) { T 'present' } else { T 'absent' })) -ForegroundColor Yellow }
    }
}
Write-Host (T 'The auto list has {0} domains.' (@(Get-Lines $AutoList).Count))

Write-Step (T 'SUMMARY')
$autoText = switch ($autoResult) {
    'skipped'     { T 'skipped' }
    'unblocked'   { T 'not blocked' }
    'already'     { T 'already learned' }
    'learned'     { T 'learned' }
    'unclear'     { T 'unclear' }
    'not-learned' { T 'not learned' }
    default       { T 'not run' }
}
Write-Host (T 'Blocked addresses: {0}/{1} open     Control addresses: {2}/{3} open     DNS level: {4}     Auto list test: {5}' $bOk $blocked.Count $cOk $controls.Count $level $autoText)
$allOk = ($bOk -eq $blocked.Count -and $cOk -eq $controls.Count -and ('learned', 'already', 'skipped', 'unblocked') -contains $autoResult)
if ($allOk) {
    Write-Host (T 'Install complete.') -ForegroundColor Green
} else {
    Write-Host (T 'Install finished but verification did not fully pass. Details: {0}' (Join-Path $localDir 'install.log')) -ForegroundColor Yellow
}
Stop-Transcript | Out-Null
if ($FromSetup) {
    if ($allOk) { Write-Host ("`n" + (T 'This window will close in 8 seconds.')); Start-Sleep -Seconds 8; exit 0 }
    Read-Host ("`n" + (T 'Press Enter to close')) | Out-Null
    exit 2
}
