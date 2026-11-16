# SlipDPI : functions shared by the scripts.
# Not meant to be run on its own; the other scripts dot-source this file:  . "$PSScriptRoot\common.ps1"

$ServisAdi = 'SlipDPI'
$Etiket    = 'SlipDPI'
$Hedef     = Join-Path $env:ProgramFiles 'SlipDPI'
$AutoListe = Join-Path $Hedef 'auto.txt'
$AutoKayit = Join-Path $Hedef 'auto-list.log'
$DurumYolu = Join-Path $Hedef 'state.json'

# Registry roots for the browser DNS policy (Chromium-based browsers use the same value names)
$PolitikaKok = @{
    chrome = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
    edge   = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    brave  = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
}
$TarayiciExe = @{ chrome = 'chrome.exe'; edge = 'msedge.exe'; brave = 'brave.exe' }

function Yonetici-Mi {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Restarts the script as administrator (opens a UAC prompt). $ek: extra argument text for the script.
function Yukselt($betik, $ek) {
    Write-Host 'Yonetici izni isteniyor, acilan UAC penceresini onayla...'
    Start-Process powershell.exe -Verb RunAs -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$betik`" $ek").Trim()
}

function Say($t) { Write-Host "`n== $t ==" -ForegroundColor Cyan }

# $true if the package was installed by the setup program straight into C:\Program Files\SlipDPI.
# When run from the repository the package is in another folder and the engine files are copied there.
function Kurulu-Duzen($root) {
    [string]::Equals([IO.Path]::GetFullPath($root).TrimEnd('\'), [IO.Path]::GetFullPath($Hedef).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
}

# If we are running inside 32-bit PowerShell (e.g. started by a 32-bit setup program), restarts the script
# in 64-bit PowerShell. In a 32-bit process Program Files and the registry are redirected elsewhere.
function AltmisDort-Bit($betik, $ek) {
    if ([Environment]::Is64BitProcess -or -not [Environment]::Is64BitOperatingSystem) { return }
    $ps = Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $p = Start-Process -FilePath $ps -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$betik`" $ek").Trim() -Wait -PassThru -NoNewWindow
    exit $p.ExitCode
}

# Clicking inside a classic console window puts Windows into "selection" mode (the title shows "Select" /
# "Sec") and the script freezes the moment it tries to write to the screen, until Enter or Esc is pressed.
# Long-running scripts call this first: it turns QuickEdit mode off for this window.
function HizliDuzenleme-Kapat {
    try {
        if (-not ('DpiLite.Konsol' -as [type])) {
            Add-Type -Namespace DpiLite -Name Konsol -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n); [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint mode); [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint mode);'
        }
        $h = [DpiLite.Konsol]::GetStdHandle(-10)                       # STD_INPUT_HANDLE
        [uint32]$mod = 0
        if ([DpiLite.Konsol]::GetConsoleMode($h, [ref]$mod)) {
            # ENABLE_QUICK_EDIT_MODE (0x40) off, ENABLE_EXTENDED_FLAGS (0x80) on
            [uint32]$yeni = ($mod -band [uint32]4294967231) -bor [uint32]128
            [void][DpiLite.Konsol]::SetConsoleMode($h, $yeni)
        }
    } catch { }
}

# When the script is opened from File Explorer ("Run with PowerShell") the window closes as soon as it ends.
# Only in that case it waits for Enter so the output can be read. It does not wait when run from a terminal
# or from another script, when output is redirected, or when started with -NoExit.
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

# Machine-specific files (chosen strategy, logs, measurements) live here; they are not tracked by git.
function Yerel-Klasor($root) {
    $y = Join-Path $root 'local'
    New-Item -ItemType Directory -Force $y | Out-Null
    $y
}

# Reads a list file: blank lines and comments (# ; /) are dropped, everything is lowercased.
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

# Writes values under a policy root. Does not touch a value that another source has already set.
# $degerler : [ordered]@{ name = value }    $eski : the previous install's record for this root (or $null)
# Returns   : @{ kayit = <record to be written to state.json>; notlar = <warning texts> }
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

# Undoes what Politika-Uygula wrote: deletes only the values we set and
# the keys we created that are now empty.
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
