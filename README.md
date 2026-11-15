# dpi-lite

Türkiye'deki site adı (SNI) tabanlı erişim engellerini, VPN ya da tünel kullanmadan aşan küçük bir
Windows kurulumu. Motor olarak [zapret](https://github.com/bol-van/zapret)'in `winws` programını kullanır.
Trafik doğrudan hedefe gider; hız ve ping değişmez, IP adresin aynı kalır.

Yalnızca listedeki alan adlarına dokunur. Listede olmayan hiçbir bağlantıyı değiştirmez.

## Nasıl çalışır

Engel iki katmanda uygulanıyor, kurulum ikisini ayrı ayrı çözer:

1. **Bağlantı:** her HTTPS bağlantısının ilk paketinde site adı açık yazar; ISS'in denetim kutusu bu ada
   bakıp bağlantıyı keser. Motor, listedeki adlar için gerçek paketten hemen önce zararsız bir ad taşıyan
   sahte bir açılış paketi gönderir. Sahte paketin ömrü (TTL) denetim kutusuna yetecek, gerçek sunucuya
   yetmeyecek kadardır.
2. **DNS:** ISS engelli adlara sahte adres döndürür. Kurulum yalnızca listedeki adların sorgularını
   şifreli DNS'e (DoH) yönlendirir; diğer bütün adlar modem DNS'inde kalır.

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
   Dosyaları `C:\Program Files\dpi-lite` altına kurar, Başlat menüsüne "dpi-lite" kontrol penceresini
   ekler ve "Uygulamalar" listesine kaldırma girdisi koyar.
2. **Zip:** `dpi-lite-<sürüm>.zip` dosyasını indir, bir klasöre aç, `kur.cmd` dosyasına çift tıkla.
3. **Depodan:** depoyu klonla, `kur.cmd` dosyasına çift tıkla ya da komut satırından:

       powershell -ExecutionPolicy Bypass -File kur.ps1

Kurulum programı imzasızdır. Windows indirilen dosyayı ilk çalıştırmada "Windows kişisel bilgisayarınızı
korudu" uyarısıyla durdurur; "Ek bilgi" → "Yine de çalıştır" ile devam edilir. İçinde WinDivert sürücüsü
olduğu için bazı antivirüsler de uyarı verebilir. İndirdiğin dosyanın özetini Releases sayfasındaki
`SHA256SUMS.txt` ile karşılaştırabilirsin (`Get-FileHash <dosya>`).

Kurulum şunları yapar ve her adımı ekrana, ayrıca `yerel\kur.log` dosyasına yazar:

1. Motor dosyalarının özetlerini `bin\SHA256SUMS.txt` ile karşılaştırır.
2. Hat için strateji seçilmemişse **strateji testini** çalıştırır (birkaç dakika): 13 ayarı sırayla
   deneyip bu hatta çalışanı `yerel\strateji.json` dosyasına yazar.
3. Dosyaları `C:\Program Files\dpi-lite` altına kopyalar ve açılışta otomatik başlayan `dpi-lite`
   servisini oluşturur.
4. Listedeki adlar için DNS kuralını (NRPT) yazar.
5. Chrome'da Güvenli DNS'i politika ile açar (aşağıya bak).
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
Kaldır", zip ya da depodan kurulduysa `kaldir.cmd`. Değiştirilen ayarların eski değerleri
`C:\Program Files\dpi-lite\durum.json` dosyasında tutulur.

Kurulum programıyla kurulduğunda betikler ve listeler de `C:\Program Files\dpi-lite` altındadır.

## Kontrol penceresi

![dpi-lite kontrol penceresi](docs/panel.png)

Başlat menüsündeki "dpi-lite" kısayolu (zip ya da depodan kurulduysa `panel.cmd`) küçük bir pencere açar:

- Servisin durumunu, seçili ayarı ve DNS'i gösterir; servisi durdurup başlatır.
- Engelli site ekler, elle eklenenleri çıkarır.
- Motorun kendi öğrendiği siteleri gösterir; yanlış gireni çıkarıp hariç tutar.
- Hattı yeniden test eder ("Yeniden test et"), kurulumu onarır, kaydı açar, kaldırır.

Pencere yönetici olarak çalışmaz. Bir düğmeye basınca ilgili betiği yönetici olarak başlatır (Windows onay
sorar) ve iş bitince durumu yeniler. Yalnızca açıkken çalışır; arka planda bir şey bırakmaz.
Aşağıdaki betikler aynı işleri komut satırından yapar.

## Listeler

| Dosya | Kim doldurur | İş |
|---|---|---|
| `lists\discord.txt` | elle | Discord alan adları, her zaman işlenir |
| `lists\siteler.txt` | elle (`site-ekle.ps1`) | Her zaman işlenecek diğer siteler |
| `C:\Program Files\dpi-lite\otomatik.txt` | motor | Motorun kendi öğrendiği siteler |
| `lists\haric.txt` | elle (`otomatik-liste.ps1 -Sil`) | Asla işlenmeyecek ve otomatik eklenmeyecek siteler |

**Otomatik liste:** listede olmayan bir site 60 saniye içinde üç kez açılışta kesilirse motor onu kendi
listesine ekler. Pratikte yeni bir engelli sitede sayfayı iki üç kez yenilemek gerekir, sonrası kalıcıdır.

- Motor tam alan adını ekler; çok alt adı olan bir sitede her alt ad ayrı öğrenilir. Üst alan adını
  `site-ekle.ps1` ile bir kez eklemek hepsini kapsar.
- Öğrenilen site Güvenli DNS'i açık tarayıcıda hemen açılır. Diğer uygulamalar için DNS kuralı bir
  sonraki `kur.ps1` çalıştırmasında güncellenir.
- Hiç cevap vermeyen ya da hata döndüren sunucular listeye girmez. Bağlantıyı tam engel gibi kesen
  arızalı bir sunucu girebilir; `otomatik-liste.ps1 -Sil` ile çıkarılır.
- Otomatik liste ve motorun kaydı (`otomatik-kayit.log`) düz metindir; açılan engelli sitelerin adlarını tutar.

## Komutlar

Yönetici izni gerekenler kendisi UAC penceresi açar.

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

- `$DnsSunucu`: listedeki adlar için DNS. Varsayılan Google, çünkü istemci konumunu ilettiği için yakın
  sunucu döndürür. Bu ölçüm tek bir Türk Telekom hattında yapıldı: Cloudflare DNS indirme ve içerik
  sunucularını 41–82 ms, Google ve modem DNS'i 6–13 ms uzağa yönlendirdi. Aynı nedenle Windows'un genel
  DNS ayarını değiştirmek önerilmez.
- `$TarayiciDns`: Güvenli DNS politikası konacak tarayıcılar (`chrome`, `edge`, `brave`). Boş bırakılırsa
  (`@()`) tarayıcıya dokunulmaz.
- `$OgrenmeTesti`: kurulum sonunda otomatik listeyi sınamak için kullanılan engelli alan adı.

Strateji `yerel\strateji.json` dosyasındadır ve makineye özeldir. Silip `kur.ps1` çalıştırmak ya da
`strateji-test.ps1` çalıştırmak yeniden seçtirir.

### Tarayıcı Güvenli DNS politikası

Otomatik listenin tarayıcıda işe yaraması için tarayıcının DNS'i şifreli olmalı. Kurulum bunu Chrome'un
kurumsal politika anahtarıyla yapar. Yan etkileri:

- Chrome menüsünde "Tarayıcınız kuruluşunuz tarafından yönetiliyor" yazısı görünür.
- Ayarlardaki "Güvenli DNS kullan" seçeneği kilitlenir.
- Mod `automatic`: şifreli DNS'e ulaşılamazsa Chrome sistem DNS'ine düşer, internet kesilmez.

İstemiyorsan `$TarayiciDns = @()` yapıp `kur.ps1` çalıştır; önceki kurulumun koyduğu politika kaldırılır.
Firefox için politika yazılmaz; Ayarlar → Gizlilik → "HTTPS üzerinden DNS" elle açılabilir.

## Sorun giderme

- **Yeni bir engelli site açılmıyor:** sayfayı iki üç kez yenile. Olmuyorsa `site-ekle.ps1` ile elle ekle.
- **Eskiden açılan bir site bozuldu:** `otomatik-liste.ps1` ile listeye yanlışlıkla girip girmediğine bak;
  girdiyse `otomatik-liste.ps1 -Sil siteadi.com`.
- **Engelli siteler yeniden kapandı:** `ac-kapat.ps1 -Durum` ile servise bak, sonra `strateji-test.ps1`
  ve `kur.ps1` çalıştır. ISS denetim kutusunu değiştirmiş olabilir.
- **Discord "Starting..." ekranında kalıyor:** sistem tepsisinden Discord'dan tamamen çıkıp yeniden aç.
- **Bir şey bozuldu ve nedenini bilmiyorsun:** `ac-kapat.ps1` ile kapat. Sorun sürüyorsa bu kurulumdan
  kaynaklanmıyordur.

## Ne kadar test edildi

Kasım 2026'da tek bir makinede, tek bir Türk Telekom hattında denendi: Chrome, Discord uygulaması
(yazı ve ses), otomatik liste, üstüne kurulum. O hatta motor açık ve kapalıyken ping, TLS süresi ve
yükleme hızı aynıydı; kısa indirme ölçümleri dalgalı olduğu için indirmede küçük bir etki olmadığı
kanıtlanamadı.

Başka ISS'lerde (Superonline, Vodafone, TurkNet, Kablonet, mobil hatlar) denenmedi. Strateji testi her
hatta kendi seçimini yapacak şekilde yazıldı, ama orada çalıştığı doğrulanmadı.

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
