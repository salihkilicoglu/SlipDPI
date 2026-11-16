# SlipDPI : control window
#
# Shows the status, the selected setting and the lists; has buttons for start/stop, add/remove site,
# retest, repair and uninstall. It does not run as administrator itself: when a button is pressed it
# launches the relevant script as administrator (UAC prompts) and refreshes the status when it ends.
# It runs only while open; it leaves nothing in the background.
#
# This file contains Turkish characters, so it must be saved as UTF-8 (with BOM).
# -EkranGoruntusu <file.png>: for the developer. Draws the window with SAMPLE lists, saves a screenshot
#                              and closes (the real list contents do not end up in the image).
param([string]$EkranGoruntusu, [int]$Sekme = 0)

. (Join-Path $PSScriptRoot 'common.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$root       = $PSScriptRoot
$ElleYol    = Join-Path $root 'lists\sites.txt'
$HaricYol   = Join-Path $root 'lists\exclude.txt'
$DiscordYol = Join-Path $root 'lists\discord.txt'
$AlanDeseni = '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$'
$script:Surec   = $null      # the running elevated process
$script:SonImza = ''

$Yesil  = [Drawing.Color]::FromArgb(22, 163, 74)
$Turunc = [Drawing.Color]::FromArgb(217, 119, 6)
$Gri    = [Drawing.Color]::FromArgb(107, 114, 128)

function Durum-Topla {
    $svc = Get-Service -Name $ServisAdi -ErrorAction SilentlyContinue
    $st  = Durum-Oku
    $d = [ordered]@{
        Kurulu    = [bool]$svc
        Calisiyor = [bool]($svc -and $svc.Status -eq 'Running')
        Otomatik  = [bool]($svc -and "$($svc.StartType)" -eq 'Automatic')
        Strateji  = ''; Ttl = 0; DnsSeviye = 0; DnsSunucu = ''; Kurulum = ''
        Elle      = @(Satirlar $ElleYol)
        Oto       = @(Satirlar $AutoListe)
        Haric     = @(Satirlar $HaricYol)
        Discord   = @(Satirlar $DiscordYol)
    }
    if ($st) {
        $d.Strateji = "$($st.strateji)"; if ($st.ttl) { $d.Ttl = [int]$st.ttl }
        if ($st.dnsSeviye) { $d.DnsSeviye = [int]$st.dnsSeviye }
        $d.DnsSunucu = (@($st.dnsSunucu) -join ', ')
        try { $d.Kurulum = ([datetime]$st.kurulum).ToString('dd.MM.yyyy HH:mm') } catch { $d.Kurulum = "$($st.kurulum)" }
    }
    if ($EkranGoruntusu) {      # no real list contents in the image; status is sample too (drawn even when not installed)
        $d.Kurulu = $true; $d.Calisiyor = $true; $d.Otomatik = $true
        $d.Strateji = 'fake_ttl4'; $d.Ttl = 4; $d.DnsSeviye = 2; $d.DnsSunucu = '8.8.8.8, 8.8.4.4'
        $d.Kurulum = (Get-Date).ToString('dd.MM.yyyy HH:mm')
        $d.Elle = @('ornek-site.com'); $d.Oto = @('ornek-video.com', 'cdn.ornek-video.com', 'ornek-forum.net'); $d.Haric = @('ornek-banka.com.tr')
    }
    [pscustomobject]$d
}

function Yeni($tip, $metin, $x, $y, $w, $h) {
    $c = New-Object "System.Windows.Forms.$tip"
    $c.Text = $metin
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
$ikon = Join-Path $root 'SlipDPI.ico'
if (Test-Path $ikon) { try { $form.Icon = New-Object Drawing.Icon($ikon) } catch { } }

$lblBaslik = Yeni 'Label' 'SlipDPI' 16 12 96 30
$lblBaslik.Font = New-Object Drawing.Font('Segoe UI Semibold', 15)
$lblAlt = Yeni 'Label' 'lightweight DPI bypass for Windows' 112 21 300 18
$lblAlt.ForeColor = $Gri

$lblNokta = Yeni 'Label' ([string][char]0x25CF) 17 46 20 22
$lblNokta.Font = New-Object Drawing.Font('Segoe UI Symbol', 11)
$lblDurum = Yeni 'Label' '' 38 48 370 20
$lblDurum.Font = New-Object Drawing.Font('Segoe UI Semibold', 9.5)
$lblBilgi = Yeni 'Label' '' 18 72 400 36
$lblBilgi.ForeColor = $Gri

$btnAcKapat = Yeni 'Button' 'Durdur' 430 40 114 32

$grpEkle = Yeni 'GroupBox' 'Engelli site ekle  (örnek: ornek.com)' 16 116 528 62
$txtSite = Yeni 'TextBox' '' 12 25 380 23
$btnEkle = Yeni 'Button' 'Ekle' 402 23 112 27
$grpEkle.Controls.AddRange(@($txtSite, $btnEkle))

$tabs = Yeni 'TabControl' '' 16 190 528 312
function Sekme($baslik, $dugmeMetni, $aciklama) {
    $tp = New-Object Windows.Forms.TabPage
    $tp.Text = $baslik
    $tp.BackColor = [Drawing.Color]::White
    $lb = Yeni 'ListBox' '' 8 8 392 230
    $lb.IntegralHeight = $false
    $bt = Yeni 'Button' $dugmeMetni 408 8 104 44
    if (-not $dugmeMetni) { $bt.Visible = $false; $lb.Width = 504 }      # read-only tab
    $lbl = Yeni 'Label' $aciklama 8 244 504 34
    $lbl.ForeColor = $Gri
    $tp.Controls.AddRange(@($lb, $bt, $lbl))
    $tabs.TabPages.Add($tp)
    [pscustomobject]@{ Sayfa = $tp; Liste = $lb; Dugme = $bt; Aciklama = $lbl; Baslik = $baslik }
}
$sDiscord = Sekme 'Discord'           ''                   'Discord''un alan adları kurulumla birlikte gelir ve her zaman işlenir; alt adları da kapsanır. Bu liste buradan değiştirilmez.'
$sElle  = Sekme 'Elle eklenenler'     'Çıkar'              'Kendi eklediğin siteler. Üst alan adını eklemek bütün alt adlarını da kapsar (ornek.com, www.ornek.com, cdn.ornek.com).'
$sOto   = Sekme 'Otomatik eklenenler' "Çıkar ve`nhariç tut" 'Bir site 60 saniye içinde üç kez açılışta kesilirse motor onu buraya kendisi ekler. Yanlış girdiyse çıkarıp hariç tutabilirsin.'
$sHaric = Sekme 'Hariç tutulanlar'    'Geri al'            'Buradaki sitelere hiç dokunulmaz ve otomatik eklenmezler.'

$btnTest   = Yeni 'Button' 'Yeniden test et' 16 514 126 30
$btnOnar   = Yeni 'Button' 'Onar'            150 514 86 30
$btnKayit  = Yeni 'Button' 'Kurulum kaydı'   244 514 112 30
$btnKilavuz = Yeni 'Button' 'Kılavuz'        364 514 86 30
$btnKaldir = Yeni 'Button' 'Kaldır'          458 514 86 30
$lblIs = Yeni 'Label' 'Hazır.' 18 556 526 20
$lblIs.ForeColor = $Gri

$form.Controls.AddRange(@($lblBaslik, $lblAlt, $lblNokta, $lblDurum, $lblBilgi, $btnAcKapat, $grpEkle, $tabs, $btnTest, $btnOnar, $btnKayit, $btnKilavuz, $btnKaldir, $lblIs))
$form.AcceptButton = $btnEkle

# Tooltips that say what a button does when the mouse hovers over it
$ipucu = New-Object Windows.Forms.ToolTip
$ipucu.AutoPopDelay = 15000; $ipucu.InitialDelay = 350; $ipucu.ReshowDelay = 100
$ipucu.SetToolTip($btnAcKapat, "Servisi durdurur ya da başlatır.`nDurdurulunca engelli siteler açılmaz ve servis açılışta da başlamaz.")
$ipucu.SetToolTip($btnEkle,    "Siteyi listeye ekler ve kurulumu yeniler (birkaç saniye).")
$ipucu.SetToolTip($btnTest,    "Hattı baştan test edip ayarı yeniden seçer (2-3 dakika).`nEngelli siteler yeniden kapanmaya başladıysa kullan.")
$ipucu.SetToolTip($btnOnar,    "Kurulum adımlarını yeniden çalıştırır: servis, DNS kuralı, tarayıcı ayarı, doğrulama.`nSeçili ayarı değiştirmez.")
$ipucu.SetToolTip($btnKayit,   "Son kurulumun kaydını Not Defteri'nde açar: hangi ayar seçildi, doğrulama geçti mi.`nBir şey çalışmadığında nedenine buradan bakılır.")
$ipucu.SetToolTip($btnKilavuz, "Kullanım kılavuzunu Not Defteri'nde açar.")
$ipucu.SetToolTip($btnKaldir, "SlipDPI'ı kaldırır ve yaptığı bütün değişiklikleri geri alır.")

$islemDugmeleri = @($btnAcKapat, $btnEkle, $sElle.Dugme, $sOto.Dugme, $sHaric.Dugme, $btnTest, $btnOnar, $btnKaldir)

# ---- status display ----------------------------------------------------------------------------
function Liste-Doldur($sekme, $ogeler) {
    $secili = $sekme.Liste.SelectedItem
    $sekme.Liste.BeginUpdate()
    $sekme.Liste.Items.Clear()
    foreach ($o in $ogeler) { [void]$sekme.Liste.Items.Add($o) }
    if ($secili -and $sekme.Liste.Items.Contains($secili)) { $sekme.Liste.SelectedItem = $secili }
    $sekme.Liste.EndUpdate()
    $sekme.Sayfa.Text = "{0} ({1})" -f $sekme.Baslik, @($ogeler).Count
}

function Yenile {
    $d = Durum-Topla
    $imza = ($d | ConvertTo-Json -Compress -Depth 3)
    if ($imza -eq $script:SonImza) { return }
    $script:SonImza = $imza

    if (-not $d.Kurulu) {
        $lblNokta.ForeColor = $Gri; $lblDurum.Text = 'Kurulu değil'; $btnAcKapat.Text = 'Kur'
    } elseif ($d.Calisiyor) {
        $lblNokta.ForeColor = $Yesil; $btnAcKapat.Text = 'Durdur'
        $lblDurum.Text = 'Çalışıyor' + $(if ($d.Otomatik) { '  ·  açılışta kendiliğinden başlar' } else { '' })
    } else {
        $lblNokta.ForeColor = $Turunc; $lblDurum.Text = 'Durduruldu  ·  engelli siteler açılmaz'; $btnAcKapat.Text = 'Başlat'
    }

    $ayar = 'Ayar: henüz seçilmedi'
    if ($d.Ttl -gt 0) { $ayar = "Ayar: sahte açılış paketi, ömür (TTL) $($d.Ttl)" }
    elseif ($d.Strateji) { $ayar = 'Ayar: ' + ($d.Strateji -replace '--dpi-desync(-[a-z-]+)?=', '') }
    $dns = ''
    if ($d.DnsSunucu) { $dns = "DNS: $($d.DnsSunucu)" + $(if ($d.DnsSeviye -eq 2) { ' (şifreli)' } elseif ($d.DnsSeviye -eq 0) { ' (çalışmıyor)' } else { '' }) }
    $ikinci = @($dns, $(if ($d.Kurulum) { "Son kurulum: $($d.Kurulum)" } else { '' })) | Where-Object { $_ }
    $lblBilgi.Text = $ayar + "`n" + ($ikinci -join '   ·   ')

    Liste-Doldur $sDiscord $d.Discord
    Liste-Doldur $sElle  $d.Elle
    Liste-Doldur $sOto   $d.Oto
    Liste-Doldur $sHaric $d.Haric
}

# ---- actions -----------------------------------------------------------------------------------
# Launches a script as administrator. $gizli: no window is shown, for short jobs.
# $acikKalsin: the window stays open when the job ends (so the result can be read).
function Baslat($betik, $arg, $etiket, [switch]$Gizli, [switch]$AcikKalsin) {
    if ($script:Surec) { return }
    $yol = Join-Path $root $betik
    $a = '-NoProfile -ExecutionPolicy Bypass ' + $(if ($Gizli) { '-WindowStyle Hidden ' } else { '' }) + $(if ($AcikKalsin) { '-NoExit ' } else { '' }) + "-File `"$yol`" $arg"
    try { $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $a.Trim() -PassThru -ErrorAction Stop }
    catch { $lblIs.Text = 'Yönetici izni verilmedi; işlem yapılmadı.'; return }
    $script:Surec = $p
    foreach ($b in $islemDugmeleri) { $b.Enabled = $false }
    $lblIs.Text = "$etiket..." + $(if (-not $Gizli) { '  Açılan pencere iş bitince kapanır.' } else { '' })
}

function Alan-Temizle($ham) {
    $d = "$ham".Trim().ToLowerInvariant() -replace '^https?://', '' -replace '/.*$', '' -replace '^www\.', ''
    if ($d -match $AlanDeseni) { return $d }
    return $null
}

$btnAcKapat.Add_Click({
    $d = Durum-Topla
    if (-not $d.Kurulu)   { Baslat 'install.ps1' '-Kurulumdan' 'Kuruluyor'; return }
    if ($d.Calisiyor)     { Baslat 'toggle.ps1' '' 'Durduruluyor' -Gizli }
    else                  { Baslat 'toggle.ps1' '' 'Başlatılıyor' -Gizli }
})

$btnEkle.Add_Click({
    $d = Alan-Temizle $txtSite.Text
    if (-not $d) { [void][Windows.Forms.MessageBox]::Show($form, 'Geçerli bir site adı yaz. Örnek: ornek.com', 'SlipDPI', 'OK', 'Information'); return }
    $txtSite.Text = ''
    Baslat 'add-site.ps1' "-Alan $d -Panel" "$d ekleniyor"
})

$sElle.Dugme.Add_Click({
    $s = $sElle.Liste.SelectedItem; if (-not $s) { return }
    Baslat 'add-site.ps1' "-Alan $s -Cikar -Panel" "$s çıkarılıyor"
})
$sOto.Dugme.Add_Click({
    $s = $sOto.Liste.SelectedItem; if (-not $s) { return }
    Baslat 'auto-list.ps1' "-Sil $s -Panel" "$s çıkarılıyor"
})
$sHaric.Dugme.Add_Click({
    $s = $sHaric.Liste.SelectedItem; if (-not $s) { return }
    Baslat 'auto-list.ps1' "-HaricSil $s -Panel" "$s hariç listesinden çıkarılıyor"
})

$btnTest.Add_Click({
    $c = [Windows.Forms.MessageBox]::Show($form, "Hat baştan test edilip ayar yeniden seçilecek.`n`n2-3 dakika sürer; bu sırada engelli siteler ve Discord kapanır.`n`nDevam edilsin mi?", 'SlipDPI', 'YesNo', 'Question')
    if ($c -eq 'Yes') { Baslat 'install.ps1' '-Kurulumdan -YenidenTest' 'Hat test ediliyor' }
})
$btnOnar.Add_Click({ Baslat 'install.ps1' '-Kurulumdan' 'Yeniden kuruluyor' })

$btnKayit.Add_Click({
    $log = Join-Path $root 'local\install.log'
    if (Test-Path $log) { Start-Process notepad.exe -ArgumentList "`"$log`"" }
    else { [void][Windows.Forms.MessageBox]::Show($form, 'Henüz bir kurulum kaydı yok.', 'SlipDPI', 'OK', 'Information') }
})

$btnKilavuz.Add_Click({
    $kilavuz = Join-Path $root 'README.md'
    if (Test-Path $kilavuz) { Start-Process notepad.exe -ArgumentList "`"$kilavuz`"" }
    else { [void][Windows.Forms.MessageBox]::Show($form, 'Kılavuz dosyası (README.md) bulunamadı.', 'SlipDPI', 'OK', 'Information') }
})

$btnKaldir.Add_Click({
    $c = [Windows.Forms.MessageBox]::Show($form, "SlipDPI kaldırılacak: servis, DNS kuralı ve tarayıcı ayarı geri alınır, otomatik liste silinir.`n`nEngelli siteler yeniden kapanır. Devam edilsin mi?", 'SlipDPI', 'YesNo', 'Warning')
    if ($c -ne 'Yes') { return }
    $unins = Join-Path $Hedef 'unins000.exe'
    if ((Kurulu-Duzen $root) -and (Test-Path $unins)) { Start-Process $unins; $form.Close() }
    else { Baslat 'uninstall.ps1' '' 'Kaldırılıyor' -AcikKalsin }
})

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({
    if ($script:Surec) {
        # WaitForExit(0): works on an elevated process too (needs only the right to wait on it)
        $bitti = $true
        try { $bitti = $script:Surec.WaitForExit(0) } catch { $bitti = $true }
        if (-not $bitti) { return }
        $script:Surec = $null
        foreach ($b in $islemDugmeleri) { $b.Enabled = $true }
        $lblIs.Text = 'Bitti.'
    }
    Yenile
})

if ($EkranGoruntusu) {
    $form.Add_Shown({
        Yenile
        if ($Sekme -gt 0 -and $Sekme -lt $tabs.TabPages.Count) { $tabs.SelectedIndex = $Sekme }
        $form.Refresh(); [Windows.Forms.Application]::DoEvents()
        $bmp = New-Object Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $bmp.Save($EkranGoruntusu, [Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $form.Close()
    })
} else {
    $form.Add_Shown({ Yenile; $timer.Start(); $form.Activate() })
}
[void]$form.ShowDialog()
$timer.Dispose(); $form.Dispose()
