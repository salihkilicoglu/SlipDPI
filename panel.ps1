# SlipDPI : control window
#
# Shows the status, the selected setting and the lists; has buttons for start/stop, add/remove site,
# retest, repair and uninstall. It does not run as administrator itself: when a button is pressed it
# launches the relevant script as administrator (UAC prompts) and refreshes the status when it ends.
# It runs only while open; it leaves nothing in the background.
#
# This file contains Turkish characters, so it must be saved as UTF-8 (with BOM).
# -Screenshot <file.png>: for the developer. Draws the window with SAMPLE lists, saves a screenshot
#                              and closes (the real list contents do not end up in the image).
param([string]$Screenshot, [int]$Tab = 0)

. (Join-Path $PSScriptRoot 'common.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$root       = $PSScriptRoot
$ManualPath    = Join-Path $root 'lists\sites.txt'
$ExcludePath   = Join-Path $root 'lists\exclude.txt'
$DiscordPath = Join-Path $root 'lists\discord.txt'
$DomainPattern = '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$'
$script:RunningProcess   = $null      # the running elevated process
$script:LastSignature = ''

$Green  = [Drawing.Color]::FromArgb(22, 163, 74)
$Orange = [Drawing.Color]::FromArgb(217, 119, 6)
$Gray    = [Drawing.Color]::FromArgb(107, 114, 128)

function Get-Status {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    $st  = Read-State
    $d = [ordered]@{
        Installed    = [bool]$svc
        Running = [bool]($svc -and $svc.Status -eq 'Running')
        AutoStart  = [bool]($svc -and "$($svc.StartType)" -eq 'Automatic')
        Strategy  = ''; Ttl = 0; DnsLevel = 0; DnsServers = ''; InstalledAt = ''
        Manual      = @(Get-Lines $ManualPath)
        Auto       = @(Get-Lines $AutoList)
        Excluded     = @(Get-Lines $ExcludePath)
        Discord   = @(Get-Lines $DiscordPath)
    }
    if ($st) {
        $d.Strategy = "$($st.strategy)"; if ($st.ttl) { $d.Ttl = [int]$st.ttl }
        if ($st.dnsLevel) { $d.DnsLevel = [int]$st.dnsLevel }
        $d.DnsServers = (@($st.dnsServers) -join ', ')
        try { $d.InstalledAt = ([datetime]$st.installedAt).ToString('dd.MM.yyyy HH:mm') } catch { $d.InstalledAt = "$($st.installedAt)" }
    }
    if ($Screenshot) {      # no real list contents in the image; status is sample too (drawn even when not installed)
        $d.Installed = $true; $d.Running = $true; $d.AutoStart = $true
        $d.Strategy = 'fake_ttl4'; $d.Ttl = 4; $d.DnsLevel = 2; $d.DnsServers = '8.8.8.8, 8.8.4.4'
        $d.InstalledAt = (Get-Date).ToString('dd.MM.yyyy HH:mm')
        $d.Manual = @('ornek-site.com'); $d.Auto = @('ornek-video.com', 'cdn.ornek-video.com', 'ornek-forum.net'); $d.Excluded = @('ornek-banka.com.tr')
    }
    [pscustomobject]$d
}

function New-Control($typeName, $text, $x, $y, $w, $h) {
    $c = New-Object "System.Windows.Forms.$typeName"
    $c.Text = $text
    $c.Location = New-Object Drawing.Point($x, $y)
    $c.Size = New-Object Drawing.Size($w, $h)
    $c
}

# ---- window ------------------------------------------------------------------------------------
$form = New-Object Windows.Forms.Form
$form.Text = 'SlipDPI'
$form.ClientSize = New-Object Drawing.Size(560, 588)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 9)
$form.BackColor = [Drawing.Color]::White
$iconPath = Join-Path $root 'SlipDPI.ico'
if (Test-Path $iconPath) { try { $form.Icon = New-Object Drawing.Icon($iconPath) } catch { } }

$lblTitle = New-Control 'Label' 'SlipDPI' 16 12 96 30
$lblTitle.Font = New-Object Drawing.Font('Segoe UI Semibold', 15)
$lblSubtitle = New-Control 'Label' 'lightweight DPI bypass for Windows' 112 21 300 18
$lblSubtitle.ForeColor = $Gray

# Language switch: a link showing the other language. The choice is stored per user (HKCU) and the
# window restarts itself to apply it; scripts started afterwards use the same language.
$otherLang = if ($Lang -eq 'tr') { 'en' } else { 'tr' }
$panelPath = $PSCommandPath
$lnkLang = New-Control 'LinkLabel' $Languages[$otherLang] 444 18 100 18
$lnkLang.TextAlign = 'MiddleRight'
$lnkLang.Add_LinkClicked({
    try {
        if (-not (Test-Path $LangKey)) { New-Item -Path $LangKey -Force | Out-Null }
        Set-ItemProperty -Path $LangKey -Name Language -Value $otherLang -Type String
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$panelPath`"" -WindowStyle Hidden
        $form.Close()
    } catch { }
})

$lblDot = New-Control 'Label' ([string][char]0x25CF) 17 46 20 22
$lblDot.Font = New-Object Drawing.Font('Segoe UI Symbol', 11)
$lblStatus = New-Control 'Label' '' 38 48 370 20
$lblStatus.Font = New-Object Drawing.Font('Segoe UI Semibold', 9.5)
$lblInfo = New-Control 'Label' '' 18 72 400 36
$lblInfo.ForeColor = $Gray

$btnToggle = New-Control 'Button' (T 'Stop') 430 40 114 32

$grpAdd = New-Control 'GroupBox' (T 'Add a blocked site  (example: example.com)') 16 116 528 62
$txtSite = New-Control 'TextBox' '' 12 25 380 23
$btnAdd = New-Control 'Button' (T 'Add') 402 23 112 27
$grpAdd.Controls.AddRange(@($txtSite, $btnAdd))

$tabs = New-Control 'TabControl' '' 16 190 528 312
function New-ListTab($title, $buttonText, $description) {
    $tp = New-Object Windows.Forms.TabPage
    $tp.Text = $title -f 0      # $title is a format with a {0} for the entry count
    $tp.BackColor = [Drawing.Color]::White
    $lb = New-Control 'ListBox' '' 8 8 392 230
    $lb.IntegralHeight = $false
    $bt = New-Control 'Button' $buttonText 408 8 104 44
    if (-not $buttonText) { $bt.Visible = $false; $lb.Width = 504 }      # read-only tab
    $lbl = New-Control 'Label' $description 8 244 504 34
    $lbl.ForeColor = $Gray
    $tp.Controls.AddRange(@($lb, $bt, $lbl))
    $tabs.TabPages.Add($tp)
    [pscustomobject]@{ Page = $tp; List = $lb; Button = $bt; Description = $lbl; Title = $title }
}
$tabDiscord = New-ListTab 'Discord ({0})'               ''                   (T 'The Discord domains come with the install and are always handled, subdomains included. This list cannot be changed from here.')
$tabManual  = New-ListTab (T 'Added manually ({0})')      (T 'Remove')         (T 'Sites you added yourself. Adding the parent domain covers all its subdomains too (example.com, www.example.com, cdn.example.com).')
$tabAuto   = New-ListTab (T 'Added automatically ({0})') ((T 'Remove and') + "`n" + (T 'exclude')) (T 'If a site is cut off on connect three times within 60 seconds, the engine adds it here itself. Remove and exclude it if that was wrong.')
$tabExcluded = New-ListTab (T 'Excluded ({0})')            (T 'Undo')           (T 'Sites listed here are never touched and are never added automatically.')

$btnTest   = New-Control 'Button' (T 'Test again') 16 514 126 30
$btnRepair   = New-Control 'Button' (T 'Repair')     150 514 86 30
$btnLog  = New-Control 'Button' (T 'Setup log')  244 514 112 30
$btnGuide = New-Control 'Button' (T 'Guide')      364 514 86 30
$btnUninstall = New-Control 'Button' (T 'Uninstall')  458 514 86 30
$lblTask = New-Control 'Label' (T 'Ready.') 18 556 526 20
$lblTask.ForeColor = $Gray

$form.Controls.AddRange(@($lblTitle, $lblSubtitle, $lnkLang, $lblDot, $lblStatus, $lblInfo, $btnToggle, $grpAdd, $tabs, $btnTest, $btnRepair, $btnLog, $btnGuide, $btnUninstall, $lblTask))
$form.AcceptButton = $btnAdd

# Tooltips that say what a button does when the mouse hovers over it
$toolTip = New-Object Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 15000; $toolTip.InitialDelay = 350; $toolTip.ReshowDelay = 100
$toolTip.SetToolTip($btnToggle, ((T 'Stops or starts the service.') + "`n" + (T 'While stopped, blocked sites do not open and the service does not start at boot either.')))
$toolTip.SetToolTip($btnAdd,    (T 'Adds the site to the list and refreshes the install (a few seconds).'))
$toolTip.SetToolTip($btnTest,    ((T 'Tests the line from scratch and selects the setting again (2-3 minutes).') + "`n" + (T 'Use it if blocked sites have started failing again.')))
$toolTip.SetToolTip($btnRepair,    ((T 'Runs the install steps again: service, DNS rule, browser setting, verification.') + "`n" + (T 'Does not change the selected setting.')))
$toolTip.SetToolTip($btnLog,   ((T 'Opens the log of the last install in Notepad: which setting was selected, whether verification passed.') + "`n" + (T 'This is where to look for the reason when something does not work.')))
$toolTip.SetToolTip($btnGuide, (T 'Opens the user guide in Notepad.'))
$toolTip.SetToolTip($btnUninstall, (T 'Uninstalls SlipDPI and reverts every change it made.'))

$actionButtons = @($btnToggle, $btnAdd, $tabManual.Button, $tabAuto.Button, $tabExcluded.Button, $btnTest, $btnRepair, $btnUninstall)

# ---- status display ----------------------------------------------------------------------------
function Fill-List($tab, $items) {
    $selected = $tab.List.SelectedItem
    $tab.List.BeginUpdate()
    $tab.List.Items.Clear()
    foreach ($o in $items) { [void]$tab.List.Items.Add($o) }
    if ($selected -and $tab.List.Items.Contains($selected)) { $tab.List.SelectedItem = $selected }
    $tab.List.EndUpdate()
    $tab.Page.Text = $tab.Title -f @($items).Count
}

function Update-View {
    $d = Get-Status
    $signature = ($d | ConvertTo-Json -Compress -Depth 3)
    if ($signature -eq $script:LastSignature) { return }
    $script:LastSignature = $signature

    if (-not $d.Installed) {
        $lblDot.ForeColor = $Gray; $lblStatus.Text = (T 'Not installed'); $btnToggle.Text = (T 'Install')
    } elseif ($d.Running) {
        $lblDot.ForeColor = $Green; $btnToggle.Text = (T 'Stop')
        $lblStatus.Text = (T 'Running') + $(if ($d.AutoStart) { '  ·  ' + (T 'starts automatically at boot') } else { '' })
    } else {
        $lblDot.ForeColor = $Orange; $lblStatus.Text = (T 'Stopped') + '  ·  ' + (T 'blocked sites will not open'); $btnToggle.Text = (T 'Start')
    }

    $settingText = (T 'Setting: not selected yet')
    if ($d.Ttl -gt 0) { $settingText = (T 'Setting: fake opening packet, lifetime (TTL) {0}' $d.Ttl) }
    elseif ($d.Strategy) { $settingText = (T 'Setting: {0}' ($d.Strategy -replace '--dpi-desync(-[a-z-]+)?=', '')) }
    $dns = ''
    if ($d.DnsServers) { $dns = "DNS: $($d.DnsServers)" + $(if ($d.DnsLevel -eq 2) { (T ' (encrypted)') } elseif ($d.DnsLevel -eq 0) { (T ' (not working)') } else { '' }) }
    $secondLine = @($dns, $(if ($d.InstalledAt) { (T 'Last install: {0}' $d.InstalledAt) } else { '' })) | Where-Object { $_ }
    $lblInfo.Text = $settingText + "`n" + ($secondLine -join '   ·   ')

    Fill-List $tabDiscord $d.Discord
    Fill-List $tabManual  $d.Manual
    Fill-List $tabAuto   $d.Auto
    Fill-List $tabExcluded $d.Excluded
}

# ---- actions -----------------------------------------------------------------------------------
# Launches a script as administrator. $hidden: no window is shown, for short jobs.
# $keepOpen: the window stays open when the job ends (so the result can be read).
function Start-Task($scriptFile, $arg, $label, [switch]$Hidden, [switch]$KeepOpen) {
    if ($script:RunningProcess) { return }
    $filePath = Join-Path $root $scriptFile
    $a = '-NoProfile -ExecutionPolicy Bypass ' + $(if ($Hidden) { '-WindowStyle Hidden ' } else { '' }) + $(if ($KeepOpen) { '-NoExit ' } else { '' }) + "-File `"$filePath`" $arg"
    try { $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $a.Trim() -PassThru -ErrorAction Stop }
    catch { $lblTask.Text = (T 'Administrator permission was not granted; nothing was done.'); return }
    $script:RunningProcess = $p
    foreach ($b in $actionButtons) { $b.Enabled = $false }
    $lblTask.Text = "$label..." + $(if (-not $Hidden) { (T '  The window that opens closes when the job is done.') } else { '' })
}

function Normalize-Domain($raw) {
    $d = "$raw".Trim().ToLowerInvariant() -replace '^https?://', '' -replace '/.*$', '' -replace '^www\.', ''
    if ($d -match $DomainPattern) { return $d }
    return $null
}

$btnToggle.Add_Click({
    $d = Get-Status
    if (-not $d.Installed)   { Start-Task 'install.ps1' '-FromSetup' (T 'Installing'); return }
    if ($d.Running)     { Start-Task 'toggle.ps1' '' (T 'Stopping') -Hidden }
    else                  { Start-Task 'toggle.ps1' '' (T 'Starting') -Hidden }
})

$btnAdd.Add_Click({
    $d = Normalize-Domain $txtSite.Text
    if (-not $d) { [void][Windows.Forms.MessageBox]::Show($form, (T 'Enter a valid site name. Example: example.com'), 'SlipDPI', 'OK', 'Information'); return }
    $txtSite.Text = ''
    Start-Task 'add-site.ps1' "-Domain $d -Panel" (T 'Adding {0}' $d)
})

$tabManual.Button.Add_Click({
    $s = $tabManual.List.SelectedItem; if (-not $s) { return }
    Start-Task 'add-site.ps1' "-Domain $s -Remove -Panel" (T 'Removing {0}' $s)
})
$tabAuto.Button.Add_Click({
    $s = $tabAuto.List.SelectedItem; if (-not $s) { return }
    Start-Task 'auto-list.ps1' "-Delete $s -Panel" (T 'Removing {0}' $s)
})
$tabExcluded.Button.Add_Click({
    $s = $tabExcluded.List.SelectedItem; if (-not $s) { return }
    Start-Task 'auto-list.ps1' "-Unexclude $s -Panel" (T 'Removing {0} from the exclude list' $s)
})

$btnTest.Add_Click({
    $c = [Windows.Forms.MessageBox]::Show($form, ((T 'The line will be tested from scratch and the setting selected again.') + "`n`n" + (T 'It takes 2-3 minutes; blocked sites and Discord stop working meanwhile.') + "`n`n" + (T 'Continue?')), 'SlipDPI', 'YesNo', 'Question')
    if ($c -eq 'Yes') { Start-Task 'install.ps1' '-FromSetup -Retest' (T 'Testing the line') }
})
$btnRepair.Add_Click({ Start-Task 'install.ps1' '-FromSetup' (T 'Reinstalling') })

$btnLog.Add_Click({
    $log = Join-Path $root 'local\install.log'
    if (Test-Path $log) { Start-Process notepad.exe -ArgumentList "`"$log`"" }
    else { [void][Windows.Forms.MessageBox]::Show($form, (T 'There is no install log yet.'), 'SlipDPI', 'OK', 'Information') }
})

$btnGuide.Add_Click({
    $guidePath = Join-Path $root 'README.md'
    if ($Lang -eq 'en' -and (Test-Path (Join-Path $root 'README.en.md'))) { $guidePath = Join-Path $root 'README.en.md' }
    if (Test-Path $guidePath) { Start-Process notepad.exe -ArgumentList "`"$guidePath`"" }
    else { [void][Windows.Forms.MessageBox]::Show($form, (T 'The guide file (README.md) was not found.'), 'SlipDPI', 'OK', 'Information') }
})

$btnUninstall.Add_Click({
    $c = [Windows.Forms.MessageBox]::Show($form, ((T 'SlipDPI will be uninstalled: the service, DNS rule and browser setting are reverted, the automatic list is deleted.') + "`n`n" + (T 'Blocked sites will stop opening again. Continue?')), 'SlipDPI', 'YesNo', 'Warning')
    if ($c -ne 'Yes') { return }
    $unins = Join-Path $InstallDir 'unins000.exe'
    if ((Test-InstalledLayout $root) -and (Test-Path $unins)) { Start-Process $unins; $form.Close() }
    else { Start-Task 'uninstall.ps1' '' (T 'Uninstalling') -KeepOpen }
})

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({
    if ($script:RunningProcess) {
        # WaitForExit(0): works on an elevated process too (needs only the right to wait on it)
        $finished = $true
        try { $finished = $script:RunningProcess.WaitForExit(0) } catch { $finished = $true }
        if (-not $finished) { return }
        $script:RunningProcess = $null
        foreach ($b in $actionButtons) { $b.Enabled = $true }
        $lblTask.Text = (T 'Done.')
    }
    Update-View
})

if ($Screenshot) {
    $form.Add_Shown({
        Update-View
        if ($Tab -gt 0 -and $Tab -lt $tabs.TabPages.Count) { $tabs.SelectedIndex = $Tab }
        $form.Refresh(); [Windows.Forms.Application]::DoEvents()
        $bmp = New-Object Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $bmp.Save($Screenshot, [Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $form.Close()
    })
} else {
    $form.Add_Shown({ Update-View; $timer.Start(); $form.Activate() })
}
[void]$form.ShowDialog()
$timer.Dispose(); $form.Dispose()
