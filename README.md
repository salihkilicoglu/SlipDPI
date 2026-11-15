# dpi-lite

Türkiye'deki site adı (SNI) tabanlı erişim engellerini, VPN ya da tünel kullanmadan aşan küçük bir
Windows kurulumu. Motor olarak [zapret](https://github.com/bol-van/zapret)'in `winws` programını kullanır.
Trafik doğrudan hedefe gider; hız ve ping değişmez, IP adresin aynı kalır.

Yalnızca listedeki alan adlarına dokunur. Listede olmayan hiçbir bağlantıyı değiştirmez.

![dpi-lite kontrol penceresi](docs/panel.png)

*Görüntüdeki siteler örnek veridir.*

## Nasıl çalışır

Engel iki katmanda uygulanıyor, kurulum ikisini ayrı ayrı çözer:

1. **Bağlantı:** her HTTPS bağlantısının ilk paketinde site adı açık yazar; ISS'in denetim kutusu bu ada
   bakıp bağlantıyı keser. Motor, listedeki adlar için gerçek paketten hemen önce zararsız bir ad taşıyan
   sahte bir açılış paketi gönderir. Sahte paketin ömrü (TTL) denetim kutusuna yetecek, gerçek sunucuya
   yetmeyecek kadardır.
2. **DNS:** ISS engelli adlara sahte adres döndürür. Kurulum yalnızca listedeki adların sorgularını
   şifreli DNS'e (DoH) yönlendirir; diğer bütün adlar modem DNS'inde kalır. Tarayıcı için ayrıca
   [Güvenli DNS](#chromeda-güvenli-dns-doh) açılır.

Uygulamaya göre değil alan adına göre çalışır: tarayıcı, Discord ya da başka bir program fark etmez.

## Gereksinimler

- Windows 11, 64 bit (x64). Windows 10'da motor çalışır ama sistem düzeyinde şifreli DNS olmadığı için
  tarayıcı dışındaki uygulamalarda (Discord) DNS engeli aşılamayabilir.
- Yönetici hakkı (servis ve sürücü kurulumu için).
- Bazı antivirüsler (ör. Kaspersky) motorun kullandığı WinDivert sürücüsünü engeller.
- Çalışan başka bir DPI aracı (GoodbyeDPI, zapret, ByeDPI) olmamalı.

## Kurulum

Üç yol var; üçü de aynı kurulum betiğini (`kur.ps1`) çalıştırır.

1. **Kurulum programı:** Releases sayfasından `dpi-lite-kurulum-<sürüm>.exe` dosyasını indirip çalıştır.
   Dosyaları `C:\Program Files\dpi-lite` altına kurar, Başlat menüsü ve masaüstü kısayolu isteyip
   istemediğini sorar ve "Uygulamalar" listesine kaldırma girdisi koyar. Soru sormadan kurmak için
   `/SILENT` (yalnızca Başlat menüsü kısayolu), ikisini de istemek için
   `/SILENT /TASKS="baslatmenusu,masaustu"`.
2. **Zip:** `dpi-lite-<sürüm>.zip` dosyasını indir, bir klasöre aç, `kur.cmd` dosyasına çift tıkla.
3. **Depodan:** depoyu klonla, `kur.cmd` dosyasına çift tıkla ya da komut satırından:

       powershell -ExecutionPolicy Bypass -File kur.ps1

Kurulum programı imzasızdır. Windows indirilen dosyayı ilk çalıştırmada "Windows kişisel bilgisayarınızı
korudu" uyarısıyla durdurur; "Ek bilgi" → "Yine de çalıştır" ile devam edilir. İçinde WinDivert sürücüsü
olduğu için bazı antivirüsler de uyarı verebilir. İndirdiğin dosyanın özetini Releases sayfasındaki
`SHA256SUMS.txt` ile karşılaştırabilirsin (`Get-FileHash <dosya>`).

Kurulum şunları yapar ve her adımı ekrana, ayrıca `yerel\kur.log` dosyasına yazar:

1. Motor dosyalarının özetlerini `bin\SHA256SUMS.txt` ile karşılaştırır.
2. Hat için strateji seçilmemişse **strateji testini** çalıştırır (2-3 dakika): 13 ayarı sırayla deneyip
   bu hatta çalışanı `yerel\strateji.json` dosyasına yazar. Bu sırada engelli siteler kapalıdır.
3. Açılışta otomatik başlayan `dpi-lite` servisini oluşturur.
4. Listedeki adlar için DNS kuralını (NRPT) yazar.
5. Chrome kuruluysa [Güvenli DNS](#chromeda-güvenli-dns-doh)'i politika ile açar.
6. Engelli ve engelsiz adreslere bağlanarak kendini doğrular; otomatik listenin öğrendiğini sınar.

Aynı betik üstüne kurulum için de kullanılır; ayar ya da liste değiştiğinde yeniden çalıştırmak yeterlidir.

### Sistemde değişenler

| Ne | Nerede |
|---|---|
| Servis | `dpi-lite` (otomatik başlar), WinDivert sürücüsü |
| Dosyalar | `C:\Program Files\dpi-lite` |
| DNS kuralı | NRPT, yalnızca listedeki alan adları → 8.8.8.8 / 8.8.4.4 |
| Şifreli DNS | Düz sorgu kesiliyorsa bu iki sunucu için DoH zorunlu kılınır (Windows 11) |
| Tarayıcı politikası | `HKLM\SOFTWARE\Policies\Google\Chrome`: `DnsOverHttpsMode`, `DnsOverHttpsTemplates` |

Kaldırma bunların hepsini geri alır: kurulum programıyla kurulduysa "Ayarlar → Uygulamalar → dpi-lite →
Kaldır" (ya da kontrol penceresindeki "Kaldır"), zip ya da depodan kurulduysa `kaldir.cmd`. Değiştirilen
ayarların eski değerleri `C:\Program Files\dpi-lite\durum.json` dosyasında tutulur.

Kurulum programıyla kurulduğunda betikler ve listeler de `C:\Program Files\dpi-lite` altındadır.

## Kontrol penceresi

Başlat menüsündeki ya da masaüstündeki "dpi-lite" kısayolu (kısayol seçmediysen ya da zip/depodan
kurduysan `panel.cmd`) yukarıdaki pencereyi açar:

- Servisin durumunu, seçili ayarı ve DNS'i gösterir; servisi durdurup başlatır.
- Listeleri dört sekmede gösterir: Discord (kurulumla gelen, her zaman işlenen alan adları), elle
  eklenenler, otomatik eklenenler, hariç tutulanlar.
- Engelli site ekler, elle eklenenleri çıkarır.
- Motorun kendi öğrendiği siteleri gösterir; yanlış gireni çıkarıp hariç tutar.
- "Yeniden test et" hattı baştan test edip ayarı yeniden seçer; "Onar" kurulum adımlarını yeniden
  çalıştırır; "Kurulum kaydı" son kurulumun kaydını Not Defteri'nde açar; "Kaldır" her şeyi geri alır.
  Düğmelerin üzerine gelince ne yaptıkları yazar.
- "Durdur" servisi kapatır ve açılışta başlamasını da engeller; "Başlat" ikisini geri açar.

Pencere yönetici olarak çalışmaz. Bir düğmeye basınca ilgili betiği yönetici olarak başlatır (Windows onay
sorar) ve iş bitince durumu yeniler. Yalnızca açıkken çalışır; arka planda bir şey bırakmaz.
[Komutlar](#komutlar) bölümündeki betikler aynı işleri komut satırından yapar.

## Chrome'da Güvenli DNS (DoH)

**Neden gerekli:** ISS engelli adlara sahte adres döndürdüğü için tarayıcının gerçek adresi başka yoldan
öğrenmesi gerekir. Kurulumun Windows'a yazdığı DNS kuralı yalnızca o an listede olan adları kapsar. Motor
yeni bir siteyi kendiliğinden öğrendiğinde o site kuralda henüz yoktur; tarayıcının kendi DNS'i şifreli
değilse site yine açılmaz. Güvenli DNS (DNS over HTTPS) açıkken Chrome bütün adları şifreli sorar ve ISS
araya giremez. Ayar yalnızca Chrome'u etkiler; diğer uygulamalar modem DNS'inde kalır.

**Kurulum ne yapar:** Chrome kuruluysa bu ayarı Chrome'un kurumsal politika anahtarıyla kendisi açar
(`DnsOverHttpsMode = automatic`, sağlayıcı Google). Elle bir şey yapman gerekmez. Yan etkileri:

- Chrome menüsünde "Tarayıcınız kuruluşunuz tarafından yönetiliyor" yazısı görünür.
- Ayarlardaki "Güvenli DNS kullan" seçeneği açık ve kilitli görünür.
- Şifreli DNS'e ulaşılamazsa Chrome sistem DNS'ine düşer; internet kesilmez.

Uygulandığını `chrome://policy` sayfasında `DnsOverHttpsMode` ve `DnsOverHttpsTemplates` satırlarından
görebilirsin. Kaldırma politikayı siler ve Chrome eski haline döner.

**Politikayı istemiyorsan:** `kur.ps1` başındaki `$TarayiciDns = @('chrome')` satırını `@()` yapıp
`kur.ps1` çalıştır; önceki kurulumun koyduğu politika kaldırılır. Sonra ayarı elle aç:

Chrome → Ayarlar → Gizlilik ve güvenlik → Güvenlik → Gelişmiş → **Güvenli DNS kullan** → "DNS sağlayıcı
seç" → **Google (Public DNS)**

![Chrome'da Güvenli DNS ayarı](docs/chrome-guvenli-dns.png)

**Neden Google:** Cloudflare DNS, istemcinin konumunu iletmediği için indirme ve içerik sunucularını uzağa
yönlendirebiliyor. Tek bir Türk Telekom hattında yapılan ölçümde aynı adlar Cloudflare DNS ile 41–82 ms,
Google DNS ve modem DNS'i ile 6–13 ms uzaktaki sunuculara gitti. Aynı nedenle Windows'un genel DNS ayarını
değiştirmek gerekmez ve önerilmez.

**Diğer tarayıcılar:** Edge ve Brave aynı politikayı kullanır; `$TarayiciDns = @('chrome', 'edge', 'brave')`
yazıp `kur.ps1` çalıştırmak yeterlidir. Firefox için politika yazılmaz; Ayarlar → Gizlilik ve Güvenlik →
"HTTPS üzerinden DNS" bölümünden elle açılır.

**Not:** DNS'i sistem genelinde süzen bir araç kullanıyorsan (ör. bir reklam engelleyicinin "DNS koruması"),
tarayıcının şifreli DNS sorguları o süzgeçten geçmez.

## Listeler

| Dosya | Kim doldurur | İş |
|---|---|---|
| `lists\discord.txt` | elle | Discord alan adları, her zaman işlenir |
| `lists\siteler.txt` | kontrol penceresi ya da `site-ekle.ps1` | Her zaman işlenecek diğer siteler |
| `C:\Program Files\dpi-lite\otomatik.txt` | motor | Motorun kendi öğrendiği siteler |
| `lists\haric.txt` | kontrol penceresi ya da `otomatik-liste.ps1 -Sil` | Asla işlenmeyecek ve otomatik eklenmeyecek siteler |

**Otomatik liste:** listede olmayan bir site 60 saniye içinde üç kez açılışta kesilirse motor onu kendi
listesine ekler. Pratikte yeni bir engelli sitede sayfayı iki üç kez yenilemek gerekir, sonrası kalıcıdır.

- Motor tam alan adını ekler; çok alt adı olan bir sitede her alt ad ayrı öğrenilir. Üst alan adını elle
  bir kez eklemek hepsini kapsar.
- Öğrenilen site Güvenli DNS'i açık tarayıcıda hemen açılır. Diğer uygulamalar için DNS kuralı bir
  sonraki kurulum çalıştırmasında ("Onar" ya da `kur.ps1`) güncellenir.
- Hiç cevap vermeyen ya da hata döndüren sunucular listeye girmez. Bağlantıyı tam engel gibi kesen
  arızalı bir sunucu girebilir; kontrol penceresinden çıkarılıp hariç tutulur.
- Otomatik liste ve motorun kaydı (`otomatik-kayit.log`) düz metindir; açılan engelli sitelerin adlarını tutar.

## Komutlar

Kontrol penceresinin yaptığı her şey betiklerle de yapılır. Yönetici izni gerekenler kendisi UAC penceresi açar.

| Betik | İş |
|---|---|
| `panel.ps1` | Kontrol penceresini açar |
| `kur.ps1` | Kurar ya da yeniden kurar, sonunda kendini doğrular; `-YenidenTest` ile hattı baştan test eder |
| `kaldir.ps1` | Her şeyi geri alır |
| `ac-kapat.ps1` | Servisi durdurur ya da başlatır; `-Durum` ile yalnızca durumu gösterir |
| `site-ekle.ps1 ornek.com` | Listeye site ekler ve kurulumu yeniler; `-Cikar` ile listeden çıkarır |
| `otomatik-liste.ps1` | Motorun eklediklerini gösterir; `-Sil ornek.com` ile çıkarıp hariç tutar, `-HaricSil ornek.com` ile hariç listesinden geri alır |
| `strateji-test.ps1` | Stratejiyi yeniden test edip seçer; uygulamak için ardından `kur.ps1` |
| `olc.ps1 -Etiket once` | Ping, TLS süresi, indirme ve yükleme hızını ölçer |

Çalıştırma: `powershell -ExecutionPolicy Bypass -File <betik>`

Çift tıklamayla: `panel.cmd`, `kur.cmd`, `kaldir.cmd`, `otomatik-liste.cmd`. Bir `.ps1` dosyasına sağ tıklayıp
"PowerShell ile çalıştır" demek de olur; bilgi gösteren betikler pencereyi kapatmadan önce Enter bekler.
Otomatik liste düz bir metin dosyasıdır, Not Defteri'yle de açılır:
`C:\Program Files\dpi-lite\otomatik.txt`

## Ayarlar

`kur.ps1` dosyasının başındaki `AYAR` bölümünde:

- `$DnsSunucu`: listedeki adlar için DNS. Varsayılan Google (nedeni [yukarıda](#chromeda-güvenli-dns-doh)).
- `$TarayiciDns`: Güvenli DNS politikası konacak tarayıcılar (`chrome`, `edge`, `brave`). Boş bırakılırsa
  (`@()`) tarayıcıya dokunulmaz.
- `$OgrenmeTesti`: kurulum sonunda otomatik listeyi sınamak için kullanılan engelli alan adı.

Strateji `yerel\strateji.json` dosyasındadır ve makineye özeldir. Kontrol penceresindeki "Yeniden test et"
(ya da `kur.ps1 -YenidenTest`) hattı baştan test edip yeniden seçer. Seçim kuralı: sahte paketin geçtiği en
düşük ömür (TTL) denetim kutusunun uzaklığıdır; bir fazlası da geçiyorsa o kullanılır.

## Sorun giderme

- **Yeni bir engelli site açılmıyor:** sayfayı iki üç kez yenile. Olmuyorsa kontrol penceresinden elle ekle.
  Chrome dışında bir tarayıcı kullanıyorsan [Güvenli DNS](#chromeda-güvenli-dns-doh)'in açık olduğuna bak.
- **Eskiden açılan bir site bozuldu:** kontrol penceresindeki "Otomatik eklenenler" sekmesine yanlışlıkla
  girip girmediğine bak; girdiyse "Çıkar ve hariç tut".
- **Engelli siteler yeniden kapandı:** pencerede servisin çalıştığına bak, sonra "Yeniden test et". ISS
  denetim kutusunu değiştirmiş olabilir.
- **Kurulum doğrulamayı geçemedi:** pencerede "Kurulum kaydı" kaydı açar; "Onar" kurulumu yeniden dener.
  Servis başlamıyorsa antivirüs WinDivert sürücüsünü engelliyor olabilir.
- **Discord "Starting..." ekranında kalıyor:** sistem tepsisinden Discord'dan tamamen çıkıp yeniden aç.
- **Bir şey bozuldu ve nedenini bilmiyorsun:** pencereden servisi durdur. Sorun sürüyorsa bu kurulumdan
  kaynaklanmıyordur.

## Ne kadar test edildi

Kasım 2026'da tek bir makinede, tek bir Türk Telekom hattında denendi:

- Chrome, Discord uygulaması (yazı ve ses), HTTP/3, otomatik liste, depodan kurulum ve üstüne kurulum.
- Kurulum programı sessiz modda (`/SILENT`) kuruldu ve kaldırıldı: kurulum kendi doğrulamasını geçti,
  kaldırma servis, sürücü, dosyalar, DNS kuralı, şifreli DNS ayarı, Chrome politikası ve kısayolların
  hepsini geri aldı.
- Motor açık ve kapalıyken ping, TLS süresi ve yükleme hızı aynıydı. 500 MB'lık sürekli indirme motor
  açıkken 607–613 Mbps ölçüldü; motor kapalıyken görülen tavan 610–615 Mbps'ti. İkisi aynı dosyayla
  yapılmış birebir karşılaştırma değildir.

Henüz denenmeyenler:

- Kurulum sihirbazının sayfaları (yalnızca sessiz mod denendi) ve kontrol penceresinin düğmeleri.
  Pencerenin görünümü ve durumu doğru okuduğu doğrulandı.
- Başka ISS'ler (Superonline, Vodafone, TurkNet, Kablonet, mobil hatlar). Strateji testi her hatta kendi
  seçimini yapacak şekilde yazıldı, ama orada çalıştığı doğrulanmadı.
- Edge ve Brave için Güvenli DNS politikası.

## Dağıtım dosyalarını üretmek

`paketle.ps1 -Surum x.y.z`, son commit'ten `cikti\` klasörüne zip'i, kurulum programını ve özetlerini
üretir. Inno Setup 6 gerekir (`winget install JRSoftware.InnoSetup`). Kurulum programının tanımı
`kurulum\dpi-lite.iss` dosyasındadır.

## Lisans ve üçüncü taraf bileşenler

Bu deponun kendi betikleri ve belgeleri [MIT lisansı](LICENSE) altındadır.

`bin\` ve `filters\` altındaki dosyalar bu deponun yazarına ait değildir ve kendi lisanslarına tabidir
(zapret: MIT, WinDivert: LGPLv3 ya da GPLv2, Cygwin: LGPLv3+). Kaynakları, sürümleri, özetleri
[UCUNCU-TARAF.md](UCUNCU-TARAF.md) dosyasında, lisans metinleri `licenses\` klasöründedir.

Bu aracı kullanmanın sorumluluğu kullanana aittir; yasal durum ülkeye ve kullanım amacına göre değişir.
