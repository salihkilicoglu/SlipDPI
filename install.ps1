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
# -Kurulumdan : the setup program and the control window call it with this switch. At the end the script
#               does not close the window right away and reports the result via its exit code (0 = ok,
#               1 = stopped, 2 = verification did not fully pass).
# -YenidenTest: sets the saved strategy choice aside, tests the line from scratch and picks again.
param([switch]$Kurulumdan, [switch]$YenidenTest)

# ---- SETTINGS --------------------------------------------------------------------------------------
# DNS for the names in the lists. Google: returns a nearby server because it forwards the client location.
$DnsSunucu      = @('8.8.8.8', '8.8.4.4')
$DohSablon      = @{ '8.8.8.8' = 'https://dns.google/dns-query'; '8.8.4.4' = 'https://dns.google/dns-query'
                     '1.1.1.1' = 'https://cloudflare-dns.com/dns-query'; '1.0.0.1' = 'https://cloudflare-dns.com/dns-query' }
# Known fake addresses that ISPs return for blocked names (Turk Telekom). The list may be incomplete;
# the real check is done by comparing the answer with the encrypted DNS answer.
$BilinenEngelIp = @('195.175.254.2')
# Browsers in which Secure DNS is turned on by policy: 'chrome', 'edge', 'brave'. If left empty ( @() )
# the browser setting is not touched. Once the policy is set the browser shows "managed by your
# organization" and the Secure DNS setting is locked; uninstall.ps1 reverts it.
$TarayiciDns    = @('chrome')
$TarayiciDoh    = [ordered]@{ DnsOverHttpsMode = 'automatic'; DnsOverHttpsTemplates = 'https://dns.google/dns-query{?dns}' }
# A name that is blocked but NOT in the manual lists; used at the end of install to test the auto list.
$OgrenmeTesti   = 'wattpad.com'
$QuicTekrar     = 4
# ------------------------------------------------------------------------------------------------

. (Join-Path $PSScriptRoot 'common.ps1')
$ek = @(); if ($Kurulumdan) { $ek += '-Kurulumdan' }; if ($YenidenTest) { $ek += '-YenidenTest' }
AltmisDort-Bit $PSCommandPath ($ek -join ' ')
# (-Kurulumdan is not passed on when self-elevating: that window stays open anyway.)
if (-not (Yonetici-Mi)) { Yukselt $PSCommandPath $(if ($YenidenTest) { '-YenidenTest' } else { '' }); return }

HizliDuzenleme-Kapat      # so that clicking the window does not freeze the install
$root  = $PSScriptRoot
$yerel = Yerel-Klasor $root
Start-Transcript -Path (Join-Path $yerel 'install.log') -Force | Out-Null
function Q($p) { '"' + $p + '"' }
function Fail($msg) {
    Write-Host "`nDURDU: $msg" -ForegroundColor Red
    Stop-Transcript | Out-Null
    if ($Kurulumdan) { Read-Host "`nKapatmak icin Enter" | Out-Null; exit 1 }
    throw "SlipDPI kurulumu durdu: $msg"
}

function Probe($url, $name, $ip) {
    $a = @('-s', '-o', 'NUL', '-w', '%{http_code}|%{time_appconnect}|%{exitcode}', '--ssl-no-revoke', '--connect-timeout', '4', '--max-time', '8')
    if ($ip) { $a += @('--resolve', "${name}:443:${ip}") }
    $o = & curl.exe @a $url
    $p = "$o".Split('|')
    [pscustomobject]@{ url = $url; ok = ($p[0] -ne '000' -and $p[0] -ne ''); code = $p[0]; tls = $p[1]; exit = $p[2] }
}

# Gets a name's real addresses from encrypted DNS, which the ISP cannot tamper with.
function GercekIp($name) {
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
function DnsTemiz($name, $ref) {
    try { $sys = @(Resolve-DnsName -Name $name -Type A -DnsOnly -ErrorAction Stop | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress }) } catch { return $false }
    if ($sys.Count -eq 0) { return $false }
    foreach ($ip in $sys) { if ($BilinenEngelIp -contains $ip) { return $false } }
    if (@($ref).Count -eq 0) { return $true }
    $refAg = @($ref | ForEach-Object { ($_ -split '\.')[0..1] -join '.' })
    foreach ($ip in $sys) { if ($refAg -contains (($ip -split '\.')[0..1] -join '.')) { return $true } }
    $false
}

# Syncs the source folder to the target file by file: leaves identical files alone (fine even if locked),
# overwrites differing ones, deletes files and subfolders that are not in the source.
function Esitle($src, $dst) {
    New-Item -ItemType Directory -Force $dst | Out-Null
    $srcFiles = @(Get-ChildItem $src -File)
    foreach ($f in $srcFiles) {
        $t = Join-Path $dst $f.Name
        $same = $false
        if (Test-Path $t) { try { $same = ((Get-FileHash $t -Algorithm SHA256 -ErrorAction Stop).Hash -eq (Get-FileHash $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash) } catch { $same = $false } }
        if ($same) { continue }
        try { Copy-Item $f.FullName $t -Force -ErrorAction Stop } catch { Fail "Kopyalanamadi: $t  ($($_.Exception.Message))" }
    }
    $names = @($srcFiles | ForEach-Object { $_.Name })
    foreach ($x in @(Get-ChildItem $dst -Force)) {
        if ($x.PSIsContainer -or ($names -notcontains $x.Name)) { Remove-Item $x.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ---- 0) pre-checks --------------------------------------------------------------------------
Say '0/7  On kontroller'
if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { Fail "Yalnizca 64 bit (x64) Windows desteklenir. Bu makine: $env:PROCESSOR_ARCHITECTURE" }
foreach ($f in 'bin\winws.exe', 'bin\WinDivert.dll', 'bin\WinDivert64.sys', 'bin\cygwin1.dll', 'bin\SHA256SUMS.txt',
               'filters\windivert_part.quic_initial_ietf.txt', 'filters\windivert_part.discord_media.txt',
               'lists\discord.txt', 'lists\sites.txt', 'lists\exclude.txt') {
    if (-not (Test-Path (Join-Path $root $f))) { Fail "Eksik dosya: $f" }
}
# Do the engine files match the hashes stored in the repository? (detects download corruption or tampering)
foreach ($line in (Satirlar (Join-Path $root 'bin\SHA256SUMS.txt'))) {
    $parts = $line -split '\s+', 2
    if ($parts.Count -ne 2) { continue }
    $got = (Get-FileHash (Join-Path $root "bin\$($parts[1])") -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($got -ne $parts[0]) { Fail "bin\$($parts[1]) dosyasinin ozeti SHA256SUMS.txt ile eslesmiyor. Depoyu yeniden indir." }
}
$foreign = @(Get-Process goodbyedpi, ciadpi, winws2 -ErrorAction SilentlyContinue)
if ($foreign.Count -gt 0) { Fail "Baska bir DPI araci calisiyor: $($foreign[0].ProcessName). Once onu kapat." }
$dohVar = [bool](Get-Command Set-DnsClientDohServerAddress -ErrorAction SilentlyContinue)
if (-not $dohVar) { Write-Host 'Not: bu Windows surumunde sistem duzeyinde sifreli DNS (DoH) yok (Windows 11 gerekir). Tarayici disindaki uygulamalarda DNS engeli asilamayabilir.' -ForegroundColor Yellow }
Write-Host 'Tamam: dosyalar yerinde ve ozetleri dogru.'

# ---- 1) stop the old install -------------------------------------------------------------------
Say '1/7  Onceki kurulum'
$old = Durum-Oku
if (Get-Service -Name $ServisAdi -ErrorAction SilentlyContinue) {
    Write-Host 'Onceki SlipDPI servisi durdurulup kaldiriliyor...'
    Stop-Service -Name $ServisAdi -Force -ErrorAction SilentlyContinue
    sc.exe delete $ServisAdi | Out-Null
    for ($i = 0; $i -lt 20; $i++) { if (-not (Get-Service -Name $ServisAdi -ErrorAction SilentlyContinue)) { break }; Start-Sleep -Milliseconds 300 }
} else { Write-Host 'Onceki servis yok.' }
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
Say '2/7  Strateji'
$stratDosya = Join-Path $yerel 'strategy.json'
if ($YenidenTest -and (Test-Path $stratDosya)) {
    Move-Item $stratDosya (Join-Path $yerel 'strategy.previous.json') -Force
    Write-Host 'Onceki secim kenara alindi (strategy.previous.json); hat yeniden test edilecek.'
}
if (-not (Test-Path $stratDosya)) {
    Write-Host 'Bu hat icin strateji secilmemis; strateji testi calistiriliyor (birkac dakika surer)...'
    try { & (Join-Path $root 'strategy-test.ps1') -Icerden } catch { Fail "Strateji testi calismadi: $($_.Exception.Message)" }
    if (-not (Test-Path $stratDosya)) { Fail 'Strateji testi bu hatta calisan bir ayar bulamadi. Ayrinti: local\strategy-test.json' }
}
try { $strat = Get-Content $stratDosya -Raw | ConvertFrom-Json } catch { Fail "local\strategy.json okunamadi: $($_.Exception.Message)" }
$TcpStrateji = "$($strat.tcp)".Trim()
$Ttl = 0; if ($strat.ttl) { $Ttl = [int]$strat.ttl }
if (-not $TcpStrateji -or $TcpStrateji -notmatch '^--dpi-desync=') { Fail 'local\strategy.json icinde gecerli bir strateji yok. Dosyayi silip install.ps1 i yeniden calistir.' }
Write-Host ("Strateji: {0}   (kaynak: {1}, {2})" -f $TcpStrateji, $strat.kaynak, $strat.secildi)
if ($Ttl -le 0) { Write-Host 'Bu strateji TTL kullanmiyor; QUIC ve ses kurallari eklenmeyecek (tarayici TCP ye duser).' -ForegroundColor Yellow }

# ---- 3) files -------------------------------------------------------------------------------
Say '3/7  Dosyalar'
New-Item -ItemType Directory -Force $Hedef | Out-Null
if (Kurulu-Duzen $root) {
    Write-Host "Paket kurulum programiyla bu klasore kurulmus; kopyalama gerekmiyor: $Hedef"
} else {
    foreach ($d in 'bin', 'filters', 'lists') { Esitle (Join-Path $root $d) (Join-Path $Hedef $d) }
    Write-Host "Esitlendi: $Hedef"
}
# the auto list is kept across reinstalls; created empty if missing
if (-not (Test-Path $AutoListe)) { Set-Content -Path $AutoListe -Value $null -Encoding ASCII }
Write-Host ("Otomatik listede su an {0} alan adi var." -f @(Satirlar $AutoListe).Count)

# ---- 4) engine config and service ------------------------------------------------------------------
Say '4/7  Motor ve servis'
$hl   = '--hostlist=' + (Q "$Hedef\lists\discord.txt") + ' --hostlist=' + (Q "$Hedef\lists\sites.txt")
$exc  = '--hostlist-exclude=' + (Q "$Hedef\lists\exclude.txt")
$auto = '--hostlist-auto=' + (Q $AutoListe) + ' --hostlist-auto-debug=' + (Q $AutoKayit)
$filtre   = @('--wf-tcp=443')
$profiller = @("--filter-tcp=443 $hl $exc $auto $TcpStrateji")
if ($Ttl -gt 0) {
    $filtre += ('--wf-raw-part=@' + (Q "$Hedef\filters\windivert_part.quic_initial_ietf.txt"))
    $filtre += ('--wf-raw-part=@' + (Q "$Hedef\filters\windivert_part.discord_media.txt"))
    $profiller += ("--filter-l7=quic $hl --hostlist=" + (Q $AutoListe) + " $exc --dpi-desync=fake --dpi-desync-repeats=$QuicTekrar --dpi-desync-ttl=$Ttl")
    $profiller += "--filter-l7=discord --dpi-desync=fake --dpi-desync-repeats=$QuicTekrar --dpi-desync-ttl=$Ttl"
}
$engineArgs = ($filtre -join ' ') + ' ' + ($profiller -join ' --new ')
$exe = "$Hedef\bin\winws.exe"
foreach ($f in 'winws.exe', 'WinDivert.dll', 'WinDivert64.sys', 'cygwin1.dll') {
    if (-not (Test-Path (Join-Path "$Hedef\bin" $f))) { Fail "Kurulu klasorde motor dosyasi eksik: $Hedef\bin\$f" }
}
# The engine's full command line is long and unreadable, so it is written to a file, not the screen.
Set-Content -Path (Join-Path $yerel 'engine-args.txt') -Value $engineArgs -Encoding ASCII
Write-Host ("Kurallar: {0}   (tam komut satiri: {1})" -f $profiller.Count, (Join-Path $yerel 'engine-args.txt'))
$dry = Start-Process -FilePath $exe -ArgumentList "$engineArgs --dry-run" -WorkingDirectory "$Hedef\bin" -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput (Join-Path $yerel 'install-dryrun.out.txt') -RedirectStandardError (Join-Path $yerel 'install-dryrun.err.txt')
if ($dry.ExitCode -ne 0) {
    Get-Content (Join-Path $yerel 'install-dryrun.out.txt'), (Join-Path $yerel 'install-dryrun.err.txt') -ErrorAction SilentlyContinue | Select-Object -Last 8 | Out-Host
    Fail "Motor ayari dogrulanamadi (cikis kodu $($dry.ExitCode)). Servis olusturulmadi."
}
Write-Host 'Ayar motorun kendi denetiminden gecti.' -ForegroundColor Green

try {
    New-Service -Name $ServisAdi -BinaryPathName ((Q $exe) + ' ' + $engineArgs) -DisplayName 'SlipDPI (zapret winws)' `
        -Description 'Yalnizca listedeki engelli alan adlarina giden baglantilarin acilis paketini duzenler. Kaldirmak icin: SlipDPI\uninstall.ps1' `
        -StartupType Automatic -ErrorAction Stop | Out-Null
} catch { Fail "Servis olusturulamadi: $($_.Exception.Message)" }
sc.exe failure $ServisAdi reset= 86400 actions= restart/5000/restart/5000/restart/60000 | Out-Null
try { Start-Service -Name $ServisAdi -ErrorAction Stop } catch { Write-Host "Servis baslatilamadi: $($_.Exception.Message)" -ForegroundColor Yellow }
Start-Sleep -Seconds 2
$svc = Get-Service -Name $ServisAdi
if ($svc.Status -ne 'Running' -or -not (Get-Process winws -ErrorAction SilentlyContinue)) { Fail "Servis calismiyor (durum: $($svc.Status)). Antivirus WinDivert surucusunu engelliyor olabilir." }
Write-Host 'Servis calisiyor ve acilista otomatik baslayacak.' -ForegroundColor Green

# ---- 5) DNS: only for the names in the lists --------------------------------------------------
Say '5/7  DNS (yalnizca listelerdeki alan adlari)'
$oldNames = @(); if ($old -and $old.nrptAdlari) { $oldNames = @($old.nrptAdlari) }

# Servers whose DoH setting we changed in a previous install: keep the record if still in use,
# restore the original setting if no longer in use.
$kept = @()
if ($dohVar -and $old -and $old.dohOnceki) {
    foreach ($p in @($old.dohOnceki)) {
        if (-not $p -or -not $p.ServerAddress) { continue }
        if ($DnsSunucu -contains $p.ServerAddress) { $kept += $p; continue }
        try {
            Set-DnsClientDohServerAddress -ServerAddress $p.ServerAddress -AutoUpgrade ([bool]$p.AutoUpgrade) -AllowFallbackToUdp ([bool]$p.AllowFallbackToUdp) -ErrorAction Stop | Out-Null
            Write-Host "Artik kullanilmayan DNS sunucusu ozgun ayarina dondu: $($p.ServerAddress)"
        } catch { Write-Host "DNS sunucusu ayari geri alinamadi ($($p.ServerAddress)): $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}

$haric   = Satirlar "$Hedef\lists\exclude.txt"
$domains = @(@(Satirlar "$Hedef\lists\discord.txt") + @(Satirlar "$Hedef\lists\sites.txt") + @(Satirlar $AutoListe) | Where-Object { $haric -notcontains $_ } | Select-Object -Unique)
$namespaces = @(); foreach ($d in $domains) { $namespaces += $d; $namespaces += ".$d" }
foreach ($r in @(Get-DnsClientNrptRule -ErrorAction SilentlyContinue)) {
    if ($r.Comment -eq $Etiket -or $r.DisplayName -eq $Etiket -or ($oldNames -contains $r.Name)) { Remove-DnsClientNrptRule -Name $r.Name -Force }
}
$rule = Add-DnsClientNrptRule -Namespace $namespaces -NameServers $DnsSunucu -Comment $Etiket -DisplayName $Etiket -PassThru
Clear-DnsClientCache
Start-Sleep -Seconds 1

$dnsAd  = 'discord.com'
$dnsRef = GercekIp $dnsAd
$enforced = ($kept.Count -gt 0)
$dnsOk = DnsTemiz $dnsAd $dnsRef
if (-not $dnsOk -and $dohVar) {
    Write-Host 'Duz DNS sorgusu kesiliyor ya da degistiriliyor. Bu sunucular icin sifreli DNS (DoH) zorunlu kiliniyor...'
    foreach ($s in $DnsSunucu) {
        $cur = Get-DnsClientDohServerAddress -ServerAddress $s -ErrorAction SilentlyContinue
        if ($cur) {
            if (-not (@($kept | ForEach-Object { $_.ServerAddress }) -contains $s)) {
                $kept += [pscustomobject]@{ ServerAddress = $s; AutoUpgrade = [bool]$cur.AutoUpgrade; AllowFallbackToUdp = [bool]$cur.AllowFallbackToUdp }
            }
            Set-DnsClientDohServerAddress -ServerAddress $s -AutoUpgrade $true -AllowFallbackToUdp $false | Out-Null
        } else {
            Add-DnsClientDohServerAddress -ServerAddress $s -DohTemplate $DohSablon[$s] -AutoUpgrade $true -AllowFallbackToUdp $false | Out-Null
        }
    }
    $enforced = $true
    Clear-DnsClientCache
    Start-Sleep -Seconds 2
    $dnsOk = DnsTemiz $dnsAd $dnsRef
}
$seviye = 0
if ($dnsOk) { if ($enforced) { $seviye = 2 } else { $seviye = 1 } }
if ($dnsOk) { Write-Host ("{0} alan adi icin DNS {1} uzerinden cozuluyor (seviye {2}); diger adlar modem DNS inde." -f $domains.Count, ($DnsSunucu -join ', '), $seviye) -ForegroundColor Green }
else        { Write-Host "DNS adimi BASARISIZ: $dnsAd hala dogru cozulmuyor. Motor calisiyor ama tarayici disindaki uygulamalar (Discord) acilmayabilir." -ForegroundColor Yellow }
try { Write-Host ("$dnsAd -> " + ((Resolve-DnsName $dnsAd -Type A -DnsOnly -ErrorAction Stop | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress }) -join ', ')) } catch { Write-Host "$dnsAd -> cozulemedi" }

# ---- 6) browser: Secure DNS policy -------------------------------------------------------
Say '6/7  Tarayici Guvenli DNS'
$eskiPol = @(); if ($old -and $old.politikalar) { $eskiPol = @($old.politikalar | Where-Object { $_ -and $_.kok }) }
$yeniPol = @()
# revert the policy we set earlier in browsers that are no longer wanted
$istenenKokler = @($TarayiciDns | ForEach-Object { $PolitikaKok[$_] } | Where-Object { $_ })
foreach ($e in $eskiPol) {
    if ($istenenKokler -notcontains $e.kok) { Politika-Kaldir $e; Write-Host "Politika geri alindi: $($e.kok)" }
}
if (@($TarayiciDns).Count -eq 0) { Write-Host 'Tarayici ayarina dokunulmadi ($TarayiciDns bos).' }
foreach ($t in @($TarayiciDns)) {
    $kok = $PolitikaKok[$t]
    if (-not $kok) { Write-Host "Bilinmeyen tarayici adi: $t (atlandi)" -ForegroundColor Yellow; continue }
    $eski = $eskiPol | Where-Object { $_.kok -eq $kok } | Select-Object -First 1
    if (-not (Tarayici-Kurulu $t) -and -not $eski) { Write-Host "$t kurulu degil, atlandi."; continue }
    $sonuc = Politika-Uygula $kok $TarayiciDoh $eski
    $yeniPol += $sonuc.kayit
    foreach ($n in $sonuc.notlar) { Write-Host "  ${t}: $n" -ForegroundColor Yellow }
    Write-Host ("{0}: Guvenli DNS politikasi yazildi ({1}). Tarayici bunu birkac saniye icinde alir; ayar artik kilitli gorunur." -f $t, (@($sonuc.kayit.degerler) -join ', ')) -ForegroundColor Green
}

$state = [ordered]@{ kurulum = (Get-Date).ToString('s'); strateji = $TcpStrateji; ttl = $Ttl; dnsSeviye = $seviye; dnsSunucu = $DnsSunucu
                     nrptAdlari = @($rule | ForEach-Object { $_.Name }); dohOnceki = @($kept); politikalar = @($yeniPol) }
[pscustomobject]$state | ConvertTo-Json -Depth 6 | Set-Content -Path $DurumYolu -Encoding UTF8

# ---- 7) end-to-end verification (system DNS + engine together) ------------------------------------
Say '7/7  Dogrulama'
$blocked  = 'https://discord.com/api/v9/gateway', 'https://gateway.discord.gg/', 'https://cdn.discordapp.com/', 'https://updates.discord.com/'
$controls = 'https://www.google.com/generate_204', 'https://github.com/', 'https://www.cloudflare.com/cdn-cgi/trace'
$bOk = 0; $cOk = 0
foreach ($u in $blocked)  { $r = Probe $u; if ($r.ok) { $bOk++ }; Write-Host ("  {0,-6} {1,-42} http={2} tls={3}s" -f $(if ($r.ok) { 'ACIK' } else { 'KAPALI' }), $u, $r.code, $r.tls) }
foreach ($u in $controls) { $r = Probe $u; if ($r.ok) { $cOk++ }; Write-Host ("  {0,-6} {1,-42} http={2} tls={3}s   (kontrol)" -f $(if ($r.ok) { 'ACIK' } else { 'KAPALI' }), $u, $r.code, $r.tls) }

# Auto list: keep connecting to a blocked name not in the manual lists and wait for the engine to learn it.
Say "Otomatik liste testi ($OgrenmeTesti)"
$autoSonuc = 'yapilamadi'
$statik = @(@(Satirlar "$Hedef\lists\discord.txt") + @(Satirlar "$Hedef\lists\sites.txt"))
if ($statik -contains $OgrenmeTesti) {
    $autoSonuc = 'atlandi'
    Write-Host "$OgrenmeTesti elle listede oldugu icin test atlandi."
} elseif ($haric -contains $OgrenmeTesti) {
    $autoSonuc = 'atlandi'
    Write-Host "$OgrenmeTesti haric listesinde oldugu icin test atlandi."
} else {
    $ip = GercekIp $OgrenmeTesti | Select-Object -First 1
    if (-not $ip) { Write-Host 'Gercek adres alinamadi, test yapilamadi.' -ForegroundColor Yellow }
    else {
        $onceVardi = @(Satirlar $AutoListe) -contains $OgrenmeTesti
        Write-Host ("Gercek adres: {0}   testten once otomatik listede: {1}" -f $ip, $(if ($onceVardi) { 'evet' } else { 'hayir' }))
        $acildi = 0
        for ($i = 1; $i -le 8; $i++) {
            $r = Probe "https://$OgrenmeTesti/" $OgrenmeTesti $ip
            Write-Host ("  deneme {0}: {1}  http={2} cikis={3}" -f $i, $(if ($r.ok) { 'ACIK' } else { 'KAPALI' }), $r.code, $r.exit)
            if ($r.ok) { $acildi = $i; break }
            Start-Sleep -Milliseconds 1200
        }
        Start-Sleep -Milliseconds 500
        $simdiVar = @(Satirlar $AutoListe) -contains $OgrenmeTesti
        if ($acildi -eq 1 -and -not $simdiVar -and -not $onceVardi) { $autoSonuc = 'engelsiz';  Write-Host 'Bu ad bu hatta engelli degil; ogrenme sinanamadi.' -ForegroundColor Yellow }
        elseif ($acildi -gt 0 -and $simdiVar -and $onceVardi)       { $autoSonuc = 'zaten';     Write-Host 'Onceden ogrenilmis, hemen acildi.' -ForegroundColor Green }
        elseif ($acildi -gt 0 -and $simdiVar)                       { $autoSonuc = 'ogrendi';   Write-Host ("Motor siteyi {0}. denemede kendisi listeye ekledi ve acti." -f $acildi) -ForegroundColor Green }
        elseif ($acildi -gt 0)                                      { $autoSonuc = 'belirsiz';  Write-Host 'Site acildi ama otomatik listede gorunmuyor.' -ForegroundColor Yellow }
        else                                                        { $autoSonuc = 'ogrenmedi'; Write-Host ("8 denemede acilmadi. Otomatik listede: {0}" -f $(if ($simdiVar) { 'var' } else { 'yok' })) -ForegroundColor Yellow }
    }
}
Write-Host ("Otomatik listede {0} alan adi var." -f @(Satirlar $AutoListe).Count)

Say 'OZET'
Write-Host ("Engelli adresler: {0}/{1} acik     Kontrol adresleri: {2}/{3} acik     DNS seviyesi: {4}     Otomatik liste testi: {5}" -f $bOk, $blocked.Count, $cOk, $controls.Count, $seviye, $autoSonuc)
$tamam = ($bOk -eq $blocked.Count -and $cOk -eq $controls.Count -and ('ogrendi', 'zaten', 'atlandi', 'engelsiz') -contains $autoSonuc)
if ($tamam) {
    Write-Host 'Kurulum tamam.' -ForegroundColor Green
} else {
    Write-Host ("Kurulum bitti ama dogrulama tam gecmedi. Ayrinti: " + (Join-Path $yerel 'install.log')) -ForegroundColor Yellow
}
Stop-Transcript | Out-Null
if ($Kurulumdan) {
    if ($tamam) { Write-Host "`nBu pencere 8 saniye sonra kapanacak."; Start-Sleep -Seconds 8; exit 0 }
    Read-Host "`nKapatmak icin Enter" | Out-Null
    exit 2
}
