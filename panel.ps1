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
        Strategy  = ''; Ttl = 0; DnsLevel = 0; DnsServers = ''; İnstalledAt = ''
        Manual      = @(Get-Lines $ManualPath)
        Auto       = @(Get-Lines $AutoList)
        Excluded     = @(Get-Lines $ExcludePath)
        Discord   = @(Get-Lines $DiscordPath)
    }
    if ($st) {
        $d.Strategy = "$($st.strategy)"; if ($st.ttl) { $d.Ttl = [int]$st.ttl }
        if ($st.dnsLevel) { $d.DnsLevel = [int]$st.dnsLevel }
        $d.DnsServers = (@($st.dnsServers) -join ', ')
        try { $d.İnstalledAt = ([datetime]$st.installedAt).ToString('dd.MM.yyyy HH:mm') } catch { $d.İnstalledAt = "$($st.installedAt)" }
    }
    if ($Screenshot) {      # no real list contents in the image; status is sample too (drawn even when not installed)
        $d.Installed = $true; $d.Running = $true; $d.AutoStart = $true
        $d.Strategy = 'fake_ttl4'; $d.Ttl = 4; $d.DnsLevel = 2; $d.DnsServers = '8.8.8.8, 8.8.4.4'
        $d.İnstalledAt = (Get-Date).ToString('dd.MM.yyyy HH:mm')
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

$lblDot = New-Control 'Label' ([string][char]0x25CF) 17 46 20 22
$lblDot.Font = New-Object Drawing.Font('Segoe UI Symbol', 11)
$lblStatus = New-Control 'Label' '' 38 48 370 20
$lblStatus.Font = New-Object Drawing.Font('Segoe UI Semibold', 9.5)
$lblInfo = New-Control 'Label' '' 18 72 400 36
$lblInfo.ForeColor = $Gray

$btnToggle = New-Control 'Button' 'Durdur' 430 40 114 32

$grpAdd = New-Control 'GroupBox' 'Engelli site ekle  (örnek: ornek.com)' 16 116 528 62
$txtSite = New-Control 'TextBox' '' 12 25 380 23
$btnAdd = New-Control 'Button' 'Ekle' 402 23 112 27
$grpAdd.Controls.AddRange(@($txtSite, $btnAdd))

$tabs = New-Control 'TabControl' '' 16 190 528 312
function New-ListTab($title, $buttonText, $description) {
    $tp = New-Object Windows.Forms.TabPage
    $tp.Text = $title
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
$tabDiscord = New-ListTab 'Discord'           ''                   'Discord''un alan adları kurulumla birlikte gelir ve her zaman işlenir; alt adları da kapsanır. Bu liste buradan değiştirilmez.'
$tabManual  = New-ListTab 'Elle eklenenler'     'Çıkar'              'Kendi eklediğin siteler. Üst alan adını eklemek bütün alt adlarını da kapsar (ornek.com, www.ornek.com, cdn.ornek.com).'
$tabAuto   = New-ListTab 'Otomatik eklenenler' "Çıkar ve`nhariç tut" 'Bir site 60 saniye içinde üç kez açılışta kesilirse motor onu buraya kendisi ekler. Yanlış girdiyse çıkarıp hariç tutabilirsin.'
$tabExcluded = New-ListTab 'Hariç tutulanlar'    'Geri al'            'Buradaki sitelere hiç dokunulmaz ve otomatik eklenmezler.'

$btnTest   = New-Control 'Button' 'Yeniden test et' 16 514 126 30
$btnRepair   = New-Control 'Button' 'Onar'            150 514 86 30
$btnLog  = New-Control 'Button' 'Kurulum kaydı'   244 514 112 30
$btnGuide = New-Control 'Button' 'Kılavuz'        364 514 86 30
$btnUninstall = New-Control 'Button' 'Kaldır'          458 514 86 30
$lblTask = New-Control 'Label' 'Hazır.' 18 556 526 20
$lblTask.ForeColor = $Gray

$form.Controls.AddRange(@($lblTitle, $lblSubtitle, $lblDot, $lblStatus, $lblInfo, $btnToggle, $grpAdd, $tabs, $btnTest, $btnRepair, $btnLog, $btnGuide, $btnUninstall, $lblTask))
$form.AcceptButton = $btnAdd

# Tooltips that say what a button does when the mouse hovers over it
$toolTip = New-Object Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 15000; $toolTip.InitialDelay = 350; $toolTip.ReshowDelay = 100
$toolTip.SetToolTip($btnToggle, "Servisi durdurur ya da başlatır.`nDurdurulunca engelli siteler açılmaz ve servis açılışta da başlamaz.")
$toolTip.SetToolTip($btnAdd,    "Siteyi listeye ekler ve kurulumu yeniler (birkaç saniye).")
$toolTip.SetToolTip($btnTest,    "Hattı baştan test edip ayarı yeniden seçer (2-3 dakika).`nEngelli siteler yeniden kapanmaya başladıysa kullan.")
$toolTip.SetToolTip($btnRepair,    "Kurulum adımlarını yeniden çalıştırır: servis, DNS kuralı, tarayıcı ayarı, doğrulama.`nSeçili ayarı değiştirmez.")
$toolTip.SetToolTip($btnLog,   "Son kurulumun kaydını Not Defteri'nde açar: hangi ayar seçildi, doğrulama geçti mi.`nBir şey çalışmadığında nedenine buradan bakılır.")
$toolTip.SetToolTip($btnGuide, "Kullanım kılavuzunu Not Defteri'nde açar.")
$toolTip.SetToolTip($btnUninstall, "SlipDPI'ı kaldırır ve yaptığı bütün değişiklikleri geri alır.")

$actionButtons = @($btnToggle, $btnAdd, $tabManual.Button, $tabAuto.Button, $tabExcluded.Button, $btnTest, $btnRepair, $btnUninstall)

# ---- status display ----------------------------------------------------------------------------
function Fill-List($tab, $items) {
    $selected = $tab.List.SelectedItem
    $tab.List.BeginUpdate()
    $tab.List.Items.Clear()
    foreach ($o in $items) { [void]$tab.List.Items.Add($o) }
    if ($selected -and $tab.List.Items.Contains($selected)) { $tab.List.SelectedItem = $selected }
    $tab.List.EndUpdate()
    $tab.Page.Text = "{0} ({1})" -f $tab.Title, @($items).Count
}

function Update-View {
    $d = Get-Status
    $signature = ($d | ConvertTo-Json -Compress -Depth 3)
    if ($signature -eq $script:LastSignature) { return }
    $script:LastSignature = $signature

    if (-not $d.Installed) {
        $lblDot.ForeColor = $Gray; $lblStatus.Text = 'Kurulu değil'; $btnToggle.Text = 'Kur'
    } elseif ($d.Running) {
        $lblDot.ForeColor = $Green; $btnToggle.Text = 'Durdur'
        $lblStatus.Text = 'Çalışıyor' + $(if ($d.AutoStart) { '  ·  açılışta kendiliğinden başlar' } else { '' })
    } else {
        $lblDot.ForeColor = $Orange; $lblStatus.Text = 'Durduruldu  ·  engelli siteler açılmaz'; $btnToggle.Text = 'Başlat'
    }

    $settingText = 'Ayar: henüz seçilmedi'
    if ($d.Ttl -gt 0) { $settingText = "Ayar: sahte açılış paketi, ömür (TTL) $($d.Ttl)" }
    elseif ($d.Strategy) { $settingText = 'Ayar: ' + ($d.Strategy -replace '--dpi-desync(-[a-z-]+)?=', '') }
    $dns = ''
    if ($d.DnsServers) { $dns = "DNS: $($d.DnsServers)" + $(if ($d.DnsLevel -eq 2) { ' (şifreli)' } elseif ($d.DnsLevel -eq 0) { ' (çalışmıyor)' } else { '' }) }
    $secondLine = @($dns, $(if ($d.İnstalledAt) { "Son kurulum: $($d.İnstalledAt)" } else { '' })) | Where-Object { $_ }
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
    catch { $lblTask.Text = 'Yönetici izni verilmedi; işlem yapılmadı.'; return }
    $script:RunningProcess = $p
    foreach ($b in $actionButtons) { $b.Enabled = $false }
    $lblTask.Text = "$label..." + $(if (-not $Hidden) { '  Açılan pencere iş bitince kapanır.' } else { '' })
}

function Normalize-Domain($raw) {
    $d = "$raw".Trim().ToLowerInvariant() -replace '^https?://', '' -replace '/.*$', '' -replace '^www\.', ''
    if ($d -match $DomainPattern) { return $d }
    return $null
}

$btnToggle.Add_Click({
    $d = Get-Status
    if (-not $d.Installed)   { Start-Task 'install.ps1' '-FromSetup' 'Kuruluyor'; return }
    if ($d.Running)     { Start-Task 'toggle.ps1' '' 'Durduruluyor' -Hidden }
    else                  { Start-Task 'toggle.ps1' '' 'Başlatılıyor' -Hidden }
})

$btnAdd.Add_Click({
    $d = Normalize-Domain $txtSite.Text
    if (-not $d) { [void][Windows.Forms.MessageBox]::Show($form, 'Geçerli bir site adı yaz. Örnek: ornek.com', 'SlipDPI', 'OK', 'Information'); return }
    $txtSite.Text = ''
    Start-Task 'add-site.ps1' "-Domain $d -Panel" "$d ekleniyor"
})

$tabManual.Button.Add_Click({
    $s = $tabManual.List.SelectedItem; if (-not $s) { return }
    Start-Task 'add-site.ps1' "-Domain $s -Remove -Panel" "$s çıkarılıyor"
})
$tabAuto.Button.Add_Click({
    $s = $tabAuto.List.SelectedItem; if (-not $s) { return }
    Start-Task 'auto-list.ps1' "-Delete $s -Panel" "$s çıkarılıyor"
})
$tabExcluded.Button.Add_Click({
    $s = $tabExcluded.List.SelectedItem; if (-not $s) { return }
    Start-Task 'auto-list.ps1' "-Unexclude $s -Panel" "$s hariç listesinden çıkarılıyor"
})

$btnTest.Add_Click({
    $c = [Windows.Forms.MessageBox]::Show($form, "Hat baştan test edilip ayar yeniden seçilecek.`n`n2-3 dakika sürer; bu sırada engelli siteler ve Discord kapanır.`n`nDevam edilsin mi?", 'SlipDPI', 'YesNo', 'Question')
    if ($c -eq 'Yes') { Start-Task 'install.ps1' '-FromSetup -Retest' 'Hat test ediliyor' }
})
$btnRepair.Add_Click({ Start-Task 'install.ps1' '-FromSetup' 'Yeniden kuruluyor' })

$btnLog.Add_Click({
    $log = Join-Path $root 'local\install.log'
    if (Test-Path $log) { Start-Process notepad.exe -ArgumentList "`"$log`"" }
    else { [void][Windows.Forms.MessageBox]::Show($form, 'Henüz bir kurulum kaydı yok.', 'SlipDPI', 'OK', 'Information') }
})

$btnGuide.Add_Click({
    $guidePath = Join-Path $root 'README.md'
    if (Test-Path $guidePath) { Start-Process notepad.exe -ArgumentList "`"$guidePath`"" }
    else { [void][Windows.Forms.MessageBox]::Show($form, 'Kılavuz dosyası (README.md) bulunamadı.', 'SlipDPI', 'OK', 'Information') }
})

$btnUninstall.Add_Click({
    $c = [Windows.Forms.MessageBox]::Show($form, "SlipDPI kaldırılacak: servis, DNS kuralı ve tarayıcı ayarı geri alınır, otomatik liste silinir.`n`nEngelli siteler yeniden kapanır. Devam edilsin mi?", 'SlipDPI', 'YesNo', 'Warning')
    if ($c -ne 'Yes') { return }
    $unins = Join-Path $InstallDir 'unins000.exe'
    if ((Test-InstalledLayout $root) -and (Test-Path $unins)) { Start-Process $unins; $form.Close() }
    else { Start-Task 'uninstall.ps1' '' 'Kaldırılıyor' -KeepOpen }
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
        $lblTask.Text = 'Bitti.'
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
