# SlipDPI : functions shared by the scripts.
# Not meant to be run on its own; the other scripts dot-source this file:  . "$PSScriptRoot\common.ps1"

$ServiceName = 'SlipDPI'
$Label    = 'SlipDPI'
$InstallDir     = Join-Path $env:ProgramFiles 'SlipDPI'
$AutoList = Join-Path $InstallDir 'auto.txt'
$AutoLog = Join-Path $InstallDir 'auto-list.log'
$StatePath = Join-Path $InstallDir 'state.json'

# ---- language --------------------------------------------------------------------------------------
# English is the source language of every message in the code. Other languages live in lang\<code>.psd1
# as a table keyed by the English text; a message without a translation falls back to English.
# Order of preference: the SLIPDPI_LANG environment variable (testing), the user's choice (HKCU, set from the control window), the installer's choice
# (lang.txt next to the scripts), then the Windows display language.
$LangKey = 'HKCU:\Software\SlipDPI'
$Languages = [ordered]@{ en = 'English'; tr = 'Türkçe' }
function Get-Language {
    if ($env:SLIPDPI_LANG -and $Languages.Contains("$env:SLIPDPI_LANG")) { return "$env:SLIPDPI_LANG" }    # for testing
    try {
        $v = (Get-ItemProperty -Path $LangKey -Name Language -ErrorAction Stop).Language
        if ($Languages.Contains("$v")) { return "$v" }
    } catch { }
    try {
        $f = Join-Path $PSScriptRoot 'lang.txt'
        if (Test-Path $f) { $v = "$(Get-Content $f -TotalCount 1)".Trim().ToLowerInvariant(); if ($Languages.Contains($v)) { return $v } }
    } catch { }
    if ((Get-UICulture).TwoLetterISOLanguageName -eq 'tr') { 'tr' } else { 'en' }
}
$Lang = Get-Language
$Strings = @{}
if ($Lang -ne 'en') {
    $langFile = Join-Path $PSScriptRoot "lang\$Lang.psd1"
    if (Test-Path $langFile) { try { $Strings = Import-PowerShellDataFile -Path $langFile } catch { $Strings = @{} } }
}
# T 'English text with {0}' arg0 arg1 ...  ->  the text in the current language, with the arguments filled in.
function T {
    param([string]$Text)
    $v = $Strings[$Text]
    if (-not $v) { $v = $Text }
    if ($args.Count -gt 0) { $v -f $args } else { $v }
}

# Registry roots for the browser DNS policy (Chromium-based browsers use the same value names)
$PolicyRoots = @{
    chrome = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
    edge   = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    brave  = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
}
$BrowserExe = @{ chrome = 'chrome.exe'; edge = 'msedge.exe'; brave = 'brave.exe' }

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Restarts the script as administrator (opens a UAC prompt). $extraArgs: extra argument text for the script.
function Invoke-Elevated($scriptFile, $extraArgs) {
    Write-Host (T 'Asking for administrator rights; approve the UAC prompt that opens...')
    Start-Process powershell.exe -Verb RunAs -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$scriptFile`" $extraArgs").Trim()
}

function Write-Step($t) { Write-Host "`n== $t ==" -ForegroundColor Cyan }

# $true if the package was installed by the setup program straight into C:\Program Files\SlipDPI.
# When run from the repository the package is in another folder and the engine files are copied there.
function Test-InstalledLayout($root) {
    [string]::Equals([IO.Path]::GetFullPath($root).TrimEnd('\'), [IO.Path]::GetFullPath($InstallDir).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
}

# If we are running inside 32-bit PowerShell (e.g. started by a 32-bit setup program), restarts the script
# in 64-bit PowerShell. In a 32-bit process Program Files and the registry are redirected elsewhere.
function Ensure-64Bit($scriptFile, $extraArgs) {
    if ([Environment]::Is64BitProcess -or -not [Environment]::Is64BitOperatingSystem) { return }
    $ps = Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $p = Start-Process -FilePath $ps -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$scriptFile`" $extraArgs").Trim() -Wait -PassThru -NoNewWindow
    exit $p.ExitCode
}

# Clicking inside a classic console window puts Windows into "selection" mode (the title shows "Select" /
# "Sec") and the script freezes the moment it tries to write to the screen, until Enter or Esc is pressed.
# Long-running scripts call this first: it turns QuickEdit mode off for this window.
function Disable-QuickEdit {
    try {
        if (-not ('SlipDPI.ConsoleApi' -as [type])) {
            Add-Type -Namespace SlipDPI -Name ConsoleApi -MemberDefinition '[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n); [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint mode); [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint mode);'
        }
        $h = [SlipDPI.ConsoleApi]::GetStdHandle(-10)                       # STD_INPUT_HANDLE
        [uint32]$mode = 0
        if ([SlipDPI.ConsoleApi]::GetConsoleMode($h, [ref]$mode)) {
            # ENABLE_QUICK_EDIT_MODE (0x40) off, ENABLE_EXTENDED_FLAGS (0x80) on
            [uint32]$newMode = ($mode -band [uint32]4294967231) -bor [uint32]128
            [void][SlipDPI.ConsoleApi]::SetConsoleMode($h, $newMode)
        }
    } catch { }
}

# When the script is opened from File Explorer ("Run with PowerShell") the window closes as soon as it ends.
# Only in that case it waits for Enter so the output can be read. It does not wait when run from a terminal
# or from another script, when output is redirected, or when started with -NoExit.
function Wait-BeforeClose {
    try {
        if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) { return }
        $cmd = [Environment]::GetCommandLineArgs() -join ' '
        if ($cmd -match '(?i)-noexit' -or $cmd -notmatch '(?i)\.ps1') { return }
        $parentPid = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId
        if ((Get-Process -Id $parentPid -ErrorAction Stop).ProcessName -ne 'explorer') { return }
        Write-Host ''
        Read-Host (T 'Press Enter to close') | Out-Null
    } catch { }
}

# Machine-specific files (chosen strategy, logs, measurements) live here; they are not tracked by git.
function Get-LocalDir($root) {
    $y = Join-Path $root 'local'
    New-Item -ItemType Directory -Force $y | Out-Null
    $y
}

# Reads a list file: blank lines and comments (# ; /) are dropped, everything is lowercased.
function Get-Lines($path) {
    if (-not (Test-Path $path)) { return @() }
    @(Get-Content $path | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ -and $_ -notmatch '^[#;/]' })
}

function Read-State {
    if (-not (Test-Path $StatePath)) { return $null }
    try { Get-Content $StatePath -Raw | ConvertFrom-Json } catch { $null }
}

function Test-BrowserInstalled($key) {
    $exe = $BrowserExe[$key]
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths') {
        if (Test-Path (Join-Path $k $exe)) { return $true }
    }
    $false
}

# Writes values under a policy root. Does not touch a value that another source has already set.
# $values : [ordered]@{ name = value }    $previous : the previous install's record for this root (or $null)
# Returns   : @{ record = <record to be written to state.json>; notes = <warning texts> }
function Apply-Policy($rootKey, $values, $previous) {
    $created = @(); $ours = @()
    if ($previous) { $created = @($previous.created | Where-Object { $_ }); $ours = @($previous.values | Where-Object { $_ }) }
    foreach ($k in @((Split-Path $rootKey -Parent), $rootKey)) {
        if (-not (Test-Path $k)) {
            New-Item -Path $k -Force | Out-Null
            if ($created -notcontains $k) { $created += $k }
        }
    }
    $notes = @()
    foreach ($key in $values.Keys) {
        $wanted = $values[$key]
        $cur = $null
        $p = Get-ItemProperty -Path $rootKey -Name $key -ErrorAction SilentlyContinue
        if ($p) { $cur = $p.$key }
        if (($ours -notcontains $key) -and ($null -ne $cur)) {
            if ($cur -ne $wanted) { $notes += (T "{0} is already set to '{1}' (by another source); left untouched." $key $cur) }
            continue
        }
        Set-ItemProperty -Path $rootKey -Name $key -Value $wanted -Type String
        if ($ours -notcontains $key) { $ours += $key }
    }
    [pscustomobject]@{ record = [pscustomobject]@{ root = $rootKey; created = @($created); values = @($ours) }; notes = @($notes) }
}

# Undoes what Apply-Policy wrote: deletes only the values we set and
# the keys we created that are now empty.
function Remove-Policy($previous) {
    if (-not $previous -or -not $previous.root) { return }
    foreach ($key in @($previous.values | Where-Object { $_ })) {
        Remove-ItemProperty -Path $previous.root -Name $key -ErrorAction SilentlyContinue
    }
    foreach ($k in @($previous.created | Where-Object { $_ } | Sort-Object { $_.Length } -Descending)) {
        if (Test-Path $k) {
            $item = Get-Item $k
            if ($item.ValueCount -eq 0 -and $item.SubKeyCount -eq 0) { Remove-Item $k -Force }
        }
    }
}
