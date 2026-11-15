# dpi-lite : strateji testi ve secimi
#
# Ne yapar: winws motorunu sirayla farkli ayarlarla GECICI olarak calistirir, her birinde engelli
# adreslere (Discord, Roblox, Wattpad) ve engelsiz kontrol adreslerine baglanmayi dener, bu hatta
# calisan ayari secer ve yerel\strateji.json dosyasina yazar. kur.ps1 o dosyayi kullanir.
#
# Kalici hicbir sey kurmaz. dpi-lite servisi calisiyorsa test suresince durdurur, sonunda geri baslatir.
# Bitince test motorunu durdurur ve WinDivert surucusunu bellekten kaldirir.
#
# Tek basina:  strateji-test.ps1          (yonetici izni ister)
# kur.ps1 icinden cagrilirken -Icerden kullanilir (yukseltme ve kayit dosyasi kur.ps1'e aittir).
param([switch]$Icerden)

. (Join-Path $PSScriptRoot 'ortak.ps1')
if (-not $Icerden -and -not (Yonetici-Mi)) { Yukselt $PSCommandPath ''; return }

$root   = $PSScriptRoot
$yerel  = Yerel-Klasor $root
$bin    = Join-Path $root 'bin'
$winws  = Join-Path $bin  'winws.exe'
$logDir = Join-Path $yerel 'test-log'
New-Item -ItemType Directory -Force $logDir | Out-Null
if (-not $Icerden) { HizliDuzenleme-Kapat; Start-Transcript -Path (Join-Path $yerel 'strateji-test.log') -Force | Out-Null }

function Bitir($msg) {
    if ($msg) { Write-Host $msg -ForegroundColor Yellow }
    if (-not $Icerden) { Stop-Transcript | Out-Null }
}

# --- hedefler: Turkiye'de engelli oldugu bilinen adlar. IP'ler basta DoH ile tazelenir. ----------
$targets = @(
    @{ name = 'discord.com';         url = 'https://discord.com/api/v9/gateway'; ip = '162.159.138.232' },
    @{ name = 'gateway.discord.gg';  url = 'https://gateway.discord.gg/';        ip = '162.159.133.234' },
    @{ name = 'cdn.discordapp.com';  url = 'https://cdn.discordapp.com/';        ip = '162.159.129.233' },
    @{ name = 'updates.discord.com'; url = 'https://updates.discord.com/';       ip = '162.159.138.232' },
    @{ name = 'roblox.com';          url = 'https://roblox.com/';                ip = '128.116.44.3' },
    @{ name = 'wattpad.com';         url = 'https://wattpad.com/';               ip = '13.224.106.74' }
)
$controls = @('https://www.google.com/generate_204', 'https://github.com/', 'https://www.cloudflare.com/cdn-cgi/trace')
# Test motoru yalnizca bu adlara dokunur (kullanicinin liste dosyalarindan bagimsiz):
$testListe = '--hostlist-domains=discord.com,discord.gg,discordapp.com,roblox.com,wattpad.com'

function Probe($url, $name, $ip) {
    $a = @('-s', '-o', 'NUL', '-w', '%{http_code}|%{time_appconnect}|%{exitcode}', '--ssl-no-revoke', '--connect-timeout', '3', '--max-time', '5')
    if ($ip) { $a += @('--resolve', "${name}:443:${ip}") }
    $o = & curl.exe @a $url
    $p = "$o".Split('|')
    [pscustomobject]@{ ok = ($p[0] -ne '000' -and $p[0] -ne ''); code = $p[0]; tls = $p[1]; exit = $p[2] }
}

function RunProbes {
    $res = [ordered]@{}
    foreach ($t in $targets) { $res[$t.name] = @() }
    for ($try = 1; $try -le 3; $try++) {
        foreach ($t in $targets) { $res[$t.name] += Probe $t.url $t.name $t.ip }
        if ($try -eq 1) {
            $any = @($res.Values | ForEach-Object { $_ } | Where-Object { $_.ok }).Count
            if ($any -eq 0) { break }      # hicbiri gecmediyse ayni seyi 3 kez denemeye gerek yok
        }
    }
    $ctl = [ordered]@{}
    foreach ($c in $controls) { $ctl[$c] = Probe $c $null $null }
    [pscustomobject]@{ targets = $res; controls = $ctl }
}

function Summarize($r) {
    $ok = 0; $n = 0; $parts = @()
    foreach ($k in $r.targets.Keys) {
        $v = @($r.targets[$k]); $g = @($v | Where-Object { $_.ok }).Count
        $ok += $g; $n += $v.Count
        $parts += ("{0} {1}/{2}" -f $k, $g, $v.Count)
    }
    $cok = @($r.controls.Values | Where-Object { $_.ok }).Count
    [pscustomobject]@{ ok = $ok; n = $n; text = ($parts -join ', '); controlsOk = $cok; controlsN = $r.controls.Count }
}

# Test sonuclarindan bu hat icin strateji secer.
#  1) TTL'li sahte paket: sunucuya hic ulasmadigi icin en guvenlisi. Gecen en dusuk TTL, denetim
#     kutusunun uzakligidir; bir fazlasi da geciyorsa o secilir (kutu bir atlama uzaklasirsa pay kalsin).
#  2) TTL'siz yontemler, tercih sirasiyla. Bunlarda sahte paket sunucuya ulasir ve sunucunun onu
#     atmasina guvenilir; bu yuzden QUIC ve ses kurallari eklenmez (ttl = 0).
function Sec-Strateji($report) {
    $tam = @($report | Where-Object { $_.started -and $_.n -gt 0 -and $_.ok -eq $_.n -and $_.controlsOk -eq $_.controlsN })
    $ttl = @($tam | ForEach-Object { if ($_.name -match '^fake_ttl(\d+)$') { [int]$Matches[1] } } | Sort-Object)
    if ($ttl.Count -gt 0) {
        $sec = $ttl[0]
        if ($ttl -contains ($ttl[0] + 1)) { $sec = $ttl[0] + 1 }
        return [ordered]@{ ad = "fake_ttl$sec"; tcp = "--dpi-desync=fake --dpi-desync-ttl=$sec"; ttl = $sec; gecenTtl = @($ttl) }
    }
    foreach ($n in 'fake_md5sig', 'multidisorder_ovl', 'fake_mdisorder_md5', 'fakedsplit_md5', 'fake_badseq') {
        $c = $tam | Where-Object { $_.name -eq $n } | Select-Object -First 1
        if ($c) { return [ordered]@{ ad = $c.name; tcp = $c.args; ttl = 0; gecenTtl = @() } }
    }
    return $null
}

# --- adaylar ------------------------------------------------------------------------------------
$candidates = @()
foreach ($t in 1..8) { $candidates += @{ name = "fake_ttl$t"; args = "--dpi-desync=fake --dpi-desync-ttl=$t" } }
$candidates += @{ name = 'fake_md5sig';        args = '--dpi-desync=fake --dpi-desync-fooling=md5sig' }
$candidates += @{ name = 'multidisorder_ovl';  args = '--dpi-desync=multidisorder --dpi-desync-split-pos=2 --dpi-desync-split-seqovl=1' }
$candidates += @{ name = 'fake_mdisorder_md5'; args = '--dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-fooling=md5sig' }
$candidates += @{ name = 'fakedsplit_md5';     args = '--dpi-desync=fakedsplit --dpi-desync-split-pos=midsld --dpi-desync-fooling=md5sig' }
$candidates += @{ name = 'fake_badseq';        args = '--dpi-desync=fake --dpi-desync-fooling=badseq' }

# --- on kosullar --------------------------------------------------------------------------------
$servisCalisiyordu = $false
if (-not $Icerden) {
    $svc = Get-Service -Name $ServisAdi -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Host 'dpi-lite servisi test suresince durduruluyor (sonunda geri baslatilacak)...'
        Stop-Service -Name $ServisAdi -Force
        $servisCalisiyordu = $true
        Start-Sleep -Seconds 1
    }
}
$busy = @(Get-Process winws, winws2, goodbyedpi, ciadpi -ErrorAction SilentlyContinue)
if ($busy.Count -gt 0) {
    Bitir "Baska bir DPI araci calisiyor ($($busy[0].ProcessName)). Once onu kapat, sonra tekrar dene."
    if ($Icerden) { throw 'strateji testi yapilamadi: baska bir DPI araci calisiyor' }
    return
}

Say 'Hedef IP adresleri DoH ile tazeleniyor'
foreach ($t in $targets) {
    try {
        $j = Invoke-RestMethod -Uri "https://dns.google/resolve?name=$($t.name)&type=A" -TimeoutSec 6
        $a = @($j.Answer | Where-Object { $_.type -eq 1 })
        if ($a.Count -gt 0) { $t.ip = $a[0].data }
    } catch { }
    Write-Host ("  {0,-22} {1}" -f $t.name, $t.ip)
}

$report = @()
$proc = $null
try {
    Say 'Temel durum (motor kapali) - hepsinin engelli cikmasi beklenir'
    $r = RunProbes; $s = Summarize $r
    Write-Host ("  gecen: {0}/{1}   kontrol: {2}/{3}" -f $s.ok, $s.n, $s.controlsOk, $s.controlsN)
    Write-Host ("  " + $s.text)
    if ($s.ok -eq $s.n) { Write-Host '  Not: bu hatta site adina gore engel gorunmuyor (yalnizca DNS engeli olabilir).' -ForegroundColor Yellow }
    if ($s.controlsOk -lt $s.controlsN) { Write-Host '  Uyari: motor kapaliyken kontrol adresleri de acilmiyor; internet baglantisini kontrol et.' -ForegroundColor Yellow }
    $report += [pscustomobject]@{ name = 'baseline_off'; args = ''; started = $true; ok = $s.ok; n = $s.n; controlsOk = $s.controlsOk; controlsN = $s.controlsN; detail = $r }

    foreach ($c in $candidates) {
        Say ("{0}   {1}" -f $c.name, $c.args)
        $argLine = "--wf-tcp=443 --filter-tcp=443 $testListe $($c.args)"
        $out = Join-Path $logDir "$($c.name).out.txt"; $err = Join-Path $logDir "$($c.name).err.txt"
        $proc = Start-Process -FilePath $winws -ArgumentList $argLine -WorkingDirectory $bin -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        Start-Sleep -Milliseconds 2500
        if ($proc.HasExited) {
            Write-Host "  motor baslamadi (cikis kodu $($proc.ExitCode)); ayrinti: $out" -ForegroundColor Yellow
            $report += [pscustomobject]@{ name = $c.name; args = $c.args; started = $false; exitCode = $proc.ExitCode; ok = 0; n = 0; controlsOk = 0; controlsN = 0; detail = $null }
            $proc = $null
            continue
        }
        $r = RunProbes; $s = Summarize $r
        $color = 'Gray'; if ($s.ok -eq $s.n -and $s.controlsOk -eq $s.controlsN) { $color = 'Green' } elseif ($s.ok -gt 0) { $color = 'Yellow' }
        Write-Host ("  gecen: {0}/{1}   kontrol: {2}/{3}" -f $s.ok, $s.n, $s.controlsOk, $s.controlsN) -ForegroundColor $color
        Write-Host ("  " + $s.text)
        $report += [pscustomobject]@{ name = $c.name; args = $c.args; started = $true; ok = $s.ok; n = $s.n; controlsOk = $s.controlsOk; controlsN = $s.controlsN; detail = $r }
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        $proc.WaitForExit(3000) | Out-Null
        $proc = $null
        Start-Sleep -Milliseconds 700
    }
}
finally {
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    Get-Process winws -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    # WinDivert surucusunu bellekten kaldir (upstream windivert_delete.cmd ile ayni iki komut)
    sc.exe stop windivert   | Out-Null
    sc.exe delete windivert | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $yerel 'strateji-test.json') -Encoding UTF8
}

Say 'OZET'
foreach ($x in $report) {
    $mark = ''; if ($x.started -and $x.n -gt 0 -and $x.ok -eq $x.n -and $x.controlsOk -eq $x.controlsN) { $mark = 'TAM' } elseif ($x.ok -gt 0) { $mark = 'KISMI' }
    Write-Host ("{0,-6} {1,-20} engelli: {2}/{3}   kontrol: {4}/{5}" -f $mark, $x.name, $x.ok, $x.n, $x.controlsOk, $x.controlsN)
}

$adaylar = @($report | Where-Object { $_.name -ne 'baseline_off' })
$secim = Sec-Strateji $adaylar
if ($secim) {
    $secim['secildi'] = (Get-Date).ToString('s')
    $secim['kaynak']  = 'strateji-test'
    [pscustomobject]$secim | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $yerel 'strateji.json') -Encoding UTF8
    Write-Host ("`nSecilen strateji: {0}   ({1})" -f $secim.ad, $secim.tcp) -ForegroundColor Green
    if ($secim.ttl -gt 0) { Write-Host ("Gecen TTL degerleri: {0}. Denetim kutusu yaklasik {1}. atlamada." -f ($secim.gecenTtl -join ', '), $secim.gecenTtl[0]) }
} else {
    Write-Host "`nBu hatta denenen ayarlarin hicbiri butun adresleri acmadi. Onceki secim (varsa) degistirilmedi." -ForegroundColor Yellow
}

if ($servisCalisiyordu) {
    Start-Service -Name $ServisAdi -ErrorAction SilentlyContinue
    Write-Host 'dpi-lite servisi eski ayariyla geri baslatildi. Yeni secimi uygulamak icin kur.ps1 calistir.'
}
if (-not $Icerden) {
    $net = Test-Connection 1.1.1.1 -Count 2 -Quiet
    Write-Host ("Test bitti. Internet: " + $(if ($net) { 'calisiyor' } else { 'YOK (yeniden baslat)' }))
    Stop-Transcript | Out-Null
}
