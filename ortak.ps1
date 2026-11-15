# dpi-lite : betiklerin ortak fonksiyonlari.
# Tek basina calistirilmaz; diger betikler bu dosyayi dot-source eder:  . "$PSScriptRoot\ortak.ps1"

$ServisAdi = 'dpi-lite'
$Etiket    = 'dpi-lite'
$Hedef     = Join-Path $env:ProgramFiles 'dpi-lite'
$AutoListe = Join-Path $Hedef 'otomatik.txt'
$AutoKayit = Join-Path $Hedef 'otomatik-kayit.log'
$DurumYolu = Join-Path $Hedef 'durum.json'

# Tarayici DNS politikasi icin kayit defteri kokleri (Chromium tabanli tarayicilar ayni adlari kullanir)
$PolitikaKok = @{
    chrome = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
    edge   = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    brave  = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
}
$TarayiciExe = @{ chrome = 'chrome.exe'; edge = 'msedge.exe'; brave = 'brave.exe' }

function Yonetici-Mi {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Betigi yonetici olarak yeniden baslatir (UAC penceresi acar). $ek: betige iletilecek ek arguman metni.
function Yukselt($betik, $ek) {
    Write-Host 'Yonetici izni isteniyor, acilan UAC penceresini onayla...'
    Start-Process powershell.exe -Verb RunAs -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$betik`" $ek").Trim()
}

function Say($t) { Write-Host "`n== $t ==" -ForegroundColor Cyan }

# Paket kurulum programiyla dogrudan C:\Program Files\dpi-lite altina kurulduysa $true.
# Depodan calistirilirken paket baska bir klasordedir ve motor dosyalari oraya kopyalanir.
function Kurulu-Duzen($root) {
    [string]::Equals([IO.Path]::GetFullPath($root).TrimEnd('\'), [IO.Path]::GetFullPath($Hedef).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
}

# 32 bit PowerShell icinde calisiyorsak (ornegin 32 bit bir kurulum programi baslattiysa) betigi 64 bit
# PowerShell ile yeniden baslatir. 32 bit surecte Program Files ve kayit defteri baska yere gider.
function AltmisDort-Bit($betik, $ek) {
    if ([Environment]::Is64BitProcess -or -not [Environment]::Is64BitOperatingSystem) { return }
    $ps = Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $p = Start-Process -FilePath $ps -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$betik`" $ek").Trim() -Wait -PassThru -NoNewWindow
    exit $p.ExitCode
}

# Klasik konsol penceresinin icine tiklaninca Windows "secim" moduna gecer (baslikta "Select" / "Sec"
# gorunur) ve betik ekrana yazi yazmaya calistigi anda donar; Enter ya da Esc'e basilana kadar bekler.
# Uzun suren betikler basta bunu cagirir: hizli duzenleme (QuickEdit) modunu bu pencere icin kapatir.
function HizliDuzenleme-Kapat {
    try {
        if (-not ('DpiLite.Konsol' -as [type])) {
            Add-Type -Namespace DpiLite -Name Konsol -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n); [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint mode); [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint mode);'
        }
        $h = [DpiLite.Konsol]::GetStdHandle(-10)                       # STD_INPUT_HANDLE
        [uint32]$mod = 0
        if ([DpiLite.Konsol]::GetConsoleMode($h, [ref]$mod)) {
            # ENABLE_QUICK_EDIT_MODE (0x40) kapali, ENABLE_EXTENDED_FLAGS (0x80) acik
            [uint32]$yeni = ($mod -band [uint32]4294967231) -bor [uint32]128
            [void][DpiLite.Konsol]::SetConsoleMode($h, $yeni)
        }
    } catch { }
}

# Betik Dosya Gezgini'nden ("PowerShell ile calistir") acildiysa pencere is bitince hemen kapanir.
# Yalnizca o durumda, cikti okunabilsin diye Enter bekler. Terminalden ya da baska bir betikten
# calistirildiginda, cikti yonlendirildiginde ve -NoExit ile acildiginda beklemez.
function Kapanmadan-Bekle {
    try {
        if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) { return }
        $cmd = [Environment]::GetCommandLineArgs() -join ' '
        if ($cmd -match '(?i)-noexit' -or $cmd -notmatch '(?i)\.ps1') { return }
        $ust = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId
        if ((Get-Process -Id $ust -ErrorAction Stop).ProcessName -ne 'explorer') { return }
        Write-Host ''
        Read-Host 'Kapatmak icin Enter' | Out-Null
    } catch { }
}

# Makineye ozel dosyalar (secilen strateji, kayitlar, olcumler) burada durur; git'e girmez.
function Yerel-Klasor($root) {
    $y = Join-Path $root 'yerel'
    New-Item -ItemType Directory -Force $y | Out-Null
    $y
}

# Liste dosyasini okur: bos satirlar ve yorumlar (# ; /) atilir, hepsi kucuk harfe cevrilir.
function Satirlar($path) {
    if (-not (Test-Path $path)) { return @() }
    @(Get-Content $path | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ -and $_ -notmatch '^[#;/]' })
}

function Durum-Oku {
    if (-not (Test-Path $DurumYolu)) { return $null }
    try { Get-Content $DurumYolu -Raw | ConvertFrom-Json } catch { $null }
}

function Tarayici-Kurulu($ad) {
    $exe = $TarayiciExe[$ad]
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths') {
        if (Test-Path (Join-Path $k $exe)) { return $true }
    }
    $false
}

# Bir politika kokune degerleri yazar. Baska bir kaynagin onceden koydugu degere dokunmaz.
# $degerler : [ordered]@{ ad = deger }      $eski : onceki kurulumun bu kok icin tuttugu kayit (ya da $null)
# Donus     : @{ kayit = <durum.json'a yazilacak kayit>; notlar = <uyari metinleri> }
function Politika-Uygula($kok, $degerler, $eski) {
    $yaratilan = @(); $bizim = @()
    if ($eski) { $yaratilan = @($eski.yaratilan | Where-Object { $_ }); $bizim = @($eski.degerler | Where-Object { $_ }) }
    foreach ($k in @((Split-Path $kok -Parent), $kok)) {
        if (-not (Test-Path $k)) {
            New-Item -Path $k -Force | Out-Null
            if ($yaratilan -notcontains $k) { $yaratilan += $k }
        }
    }
    $notlar = @()
    foreach ($ad in $degerler.Keys) {
        $istenen = $degerler[$ad]
        $cur = $null
        $p = Get-ItemProperty -Path $kok -Name $ad -ErrorAction SilentlyContinue
        if ($p) { $cur = $p.$ad }
        if (($bizim -notcontains $ad) -and ($null -ne $cur)) {
            if ($cur -ne $istenen) { $notlar += "$ad zaten '$cur' olarak ayarli (baska bir kaynak koymus); dokunulmadi." }
            continue
        }
        Set-ItemProperty -Path $kok -Name $ad -Value $istenen -Type String
        if ($bizim -notcontains $ad) { $bizim += $ad }
    }
    [pscustomobject]@{ kayit = [pscustomobject]@{ kok = $kok; yaratilan = @($yaratilan); degerler = @($bizim) }; notlar = @($notlar) }
}

# Politika-Uygula'nin yazdiklarini geri alir: yalnizca bizim koydugumuz degerleri ve
# bizim yaratip bos kalan anahtarlari siler.
function Politika-Kaldir($eski) {
    if (-not $eski -or -not $eski.kok) { return }
    foreach ($ad in @($eski.degerler | Where-Object { $_ })) {
        Remove-ItemProperty -Path $eski.kok -Name $ad -ErrorAction SilentlyContinue
    }
    foreach ($k in @($eski.yaratilan | Where-Object { $_ } | Sort-Object { $_.Length } -Descending)) {
        if (Test-Path $k) {
            $item = Get-Item $k
            if ($item.ValueCount -eq 0 -and $item.SubKeyCount -eq 0) { Remove-Item $k -Force }
        }
    }
}
