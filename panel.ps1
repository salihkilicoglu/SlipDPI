# dpi-lite : kontrol penceresi
#
# Durumu, secili ayari ve listeleri gosterir; ac/kapat, site ekle/cikar, yeniden test, onar ve kaldir
# dugmeleri vardir. Kendisi yonetici olarak calismaz: bir dugmeye basilinca ilgili betigi yonetici
# olarak baslatir (UAC sorar) ve bitince durumu yeniler. Yalnizca acikken calisir; arka planda bir
# sey birakmaz.
#
# Bu dosya Turkce karakter icerdigi icin UTF-8 (BOM'lu) kaydedilmelidir.
# -EkranGoruntusu <dosya.png>: gelistirici icin. Pencereyi ORNEK listelerle cizip goruntusunu kaydeder
#                              ve kapanir (gercek liste icerigi goruntuye girmez).
param([string]$EkranGoruntusu, [int]$Sekme = 0)

. (Join-Path $PSScriptRoot 'ortak.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$root       = $PSScriptRoot
$ElleYol    = Join-Path $root 'lists\siteler.txt'
$HaricYol   = Join-Path $root 'lists\haric.txt'
$DiscordYol = Join-Path $root 'lists\discord.txt'
$AlanDeseni = '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$'
$script:Surec   = $null      # calisan yukseltilmis islem
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
    if ($EkranGoruntusu) {      # goruntuye gercek liste icerigi girmesin
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

# ---- pencere -----------------------------------------------------------------------------------
$form = New-Object Windows.Forms.Form
$form.Text = 'dpi-lite'
$form.ClientSize = New-Object Drawing.Size(560, 588)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 9)
$form.BackColor = [Drawing.Color]::White
$ikon = Join-Path $root 'dpi-lite.ico'
if (Test-Path $ikon) { try { $form.Icon = New-Object Drawing.Icon($ikon) } catch { } }

$lblBaslik = Yeni 'Label' 'dpi-lite' 16 12 300 30
$lblBaslik.Font = New-Object Drawing.Font('Segoe UI Semibold', 15)

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
    if (-not $dugmeMetni) { $bt.Visible = $false; $lb.Width = 504 }      # salt okunur sekme
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

$form.Controls.AddRange(@($lblBaslik, $lblNokta, $lblDurum, $lblBilgi, $btnAcKapat, $grpEkle, $tabs, $btnTest, $btnOnar, $btnKayit, $btnKilavuz, $btnKaldir, $lblIs))
$form.AcceptButton = $btnEkle

# Fareyle uzerine gelince dugmenin ne yaptigini soyleyen ipuclari
$ipucu = New-Object Windows.Forms.ToolTip
$ipucu.AutoPopDelay = 15000; $ipucu.InitialDelay = 350; $ipucu.ReshowDelay = 100
$ipucu.SetToolTip($btnAcKapat, "Servisi durdurur ya da başlatır.`nDurdurulunca engelli siteler açılmaz ve servis açılışta da başlamaz.")
$ipucu.SetToolTip($btnEkle,    "Siteyi listeye ekler ve kurulumu yeniler (birkaç saniye).")
$ipucu.SetToolTip($btnTest,    "Hattı baştan test edip ayarı yeniden seçer (2-3 dakika).`nEngelli siteler yeniden kapanmaya başladıysa kullan.")
$ipucu.SetToolTip($btnOnar,    "Kurulum adımlarını yeniden çalıştırır: servis, DNS kuralı, tarayıcı ayarı, doğrulama.`nSeçili ayarı değiştirmez.")
$ipucu.SetToolTip($btnKayit,   "Son kurulumun kaydını Not Defteri'nde açar: hangi ayar seçildi, doğrulama geçti mi.`nBir şey çalışmadığında nedenine buradan bakılır.")
$ipucu.SetToolTip($btnKilavuz, "Kullanım kılavuzunu Not Defteri'nde açar.")
$ipucu.SetToolTip($btnKaldir, "dpi-lite'ı kaldırır ve yaptığı bütün değişiklikleri geri alır.")

$islemDugmeleri = @($btnAcKapat, $btnEkle, $sElle.Dugme, $sOto.Dugme, $sHaric.Dugme, $btnTest, $btnOnar, $btnKaldir)

# ---- durum gosterimi ---------------------------------------------------------------------------
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

# ---- islemler ----------------------------------------------------------------------------------
# Bir betigi yonetici olarak baslatir. $gizli: kisa isler icin pencere gosterilmez.
# $acikKalsin: is bitince pencere kapanmaz (sonucu okumak icin).
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
    if (-not $d.Kurulu)   { Baslat 'kur.ps1' '-Kurulumdan' 'Kuruluyor'; return }
    if ($d.Calisiyor)     { Baslat 'ac-kapat.ps1' '' 'Durduruluyor' -Gizli }
    else                  { Baslat 'ac-kapat.ps1' '' 'Başlatılıyor' -Gizli }
})

$btnEkle.Add_Click({
    $d = Alan-Temizle $txtSite.Text
    if (-not $d) { [void][Windows.Forms.MessageBox]::Show($form, 'Geçerli bir site adı yaz. Örnek: ornek.com', 'dpi-lite', 'OK', 'Information'); return }
    $txtSite.Text = ''
    Baslat 'site-ekle.ps1' "-Alan $d -Panel" "$d ekleniyor"
})

$sElle.Dugme.Add_Click({
    $s = $sElle.Liste.SelectedItem; if (-not $s) { return }
    Baslat 'site-ekle.ps1' "-Alan $s -Cikar -Panel" "$s çıkarılıyor"
})
$sOto.Dugme.Add_Click({
    $s = $sOto.Liste.SelectedItem; if (-not $s) { return }
    Baslat 'otomatik-liste.ps1' "-Sil $s -Panel" "$s çıkarılıyor"
})
$sHaric.Dugme.Add_Click({
    $s = $sHaric.Liste.SelectedItem; if (-not $s) { return }
    Baslat 'otomatik-liste.ps1' "-HaricSil $s -Panel" "$s hariç listesinden çıkarılıyor"
})

$btnTest.Add_Click({
    $c = [Windows.Forms.MessageBox]::Show($form, "Hat baştan test edilip ayar yeniden seçilecek.`n`n2-3 dakika sürer; bu sırada engelli siteler ve Discord kapanır.`n`nDevam edilsin mi?", 'dpi-lite', 'YesNo', 'Question')
    if ($c -eq 'Yes') { Baslat 'kur.ps1' '-Kurulumdan -YenidenTest' 'Hat test ediliyor' }
})
$btnOnar.Add_Click({ Baslat 'kur.ps1' '-Kurulumdan' 'Yeniden kuruluyor' })

$btnKayit.Add_Click({
    $log = Join-Path $root 'yerel\kur.log'
    if (Test-Path $log) { Start-Process notepad.exe -ArgumentList "`"$log`"" }
    else { [void][Windows.Forms.MessageBox]::Show($form, 'Henüz bir kurulum kaydı yok.', 'dpi-lite', 'OK', 'Information') }
})

$btnKilavuz.Add_Click({
    $kilavuz = Join-Path $root 'README.md'
    if (Test-Path $kilavuz) { Start-Process notepad.exe -ArgumentList "`"$kilavuz`"" }
    else { [void][Windows.Forms.MessageBox]::Show($form, 'Kılavuz dosyası (README.md) bulunamadı.', 'dpi-lite', 'OK', 'Information') }
})

$btnKaldir.Add_Click({
    $c = [Windows.Forms.MessageBox]::Show($form, "dpi-lite kaldırılacak: servis, DNS kuralı ve tarayıcı ayarı geri alınır, otomatik liste silinir.`n`nEngelli siteler yeniden kapanır. Devam edilsin mi?", 'dpi-lite', 'YesNo', 'Warning')
    if ($c -ne 'Yes') { return }
    $unins = Join-Path $Hedef 'unins000.exe'
    if ((Kurulu-Duzen $root) -and (Test-Path $unins)) { Start-Process $unins; $form.Close() }
    else { Baslat 'kaldir.ps1' '' 'Kaldırılıyor' -AcikKalsin }
})

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({
    if ($script:Surec) {
        # WaitForExit(0): yukseltilmis surecte de calisir (yalnizca bekleme hakki ister)
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
