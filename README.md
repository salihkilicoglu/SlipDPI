# SlipDPI

**Lightweight DPI bypass for Windows** · [English](README.en.md)

Türkiye'deki site adı (SNI) tabanlı erişim engellerini VPN kullanmadan aşan küçük bir Windows programı.
Trafik doğrudan hedefe gider; hız ve ping değişmez, IP adresin aynı kalır. Oyun trafiğine hiç dokunmaz,
oyunlarda ping artmaz.

![SlipDPI kontrol penceresi](docs/panel.png)

*Görüntüdeki siteler örnek veridir.*

## Neden "hafif"

SlipDPI bilerek az şey yapar:

- **Yalnızca gerekene dokunur.** Bütün trafiği değil, listedeki alan adlarına giden bağlantıların
  yalnızca açılışını değiştirir. Geri kalan her şey olduğu gibi geçer.
- **Tünel, VPN, proxy yok.** Trafik başka bir sunucudan ya da bilgisayardaki bir ara programdan
  dolaşmaz; hız ve ping bu yüzden değişmez.
- **Tek ayar.** Onlarca hazır ayar arasından seçtirmez. Kurulumda hattını test eder, çalışan en sade
  ayarı kendisi seçer.
- **Arka planda tek küçük servis.** Sistem tepsisinde bekleyen bir program yoktur; kontrol penceresi
  yalnızca açtığında çalışır. Servis yaklaşık 8 MB bellek kullanır.
- **Küçük kurulum.** Kurulum programı yaklaşık 3 MB'tır; Windows'un genel DNS ayarına dokunmaz ve
  kaldırılınca geride bir şey bırakmaz.

Karşılığında yapmadıkları da var: IP adresini gizlemez, trafiği şifrelemez, IP adresine göre yapılan
engelleri aşmaz. Bunlar için VPN gerekir.

## Neye dokunur, neye dokunmaz

Program uygulamaya göre değil alan adına göre çalışır ve yalnızca listesindeki alan adlarına giden
bağlantıları değiştirir.

| Trafik | Ne olur |
|---|---|
| Oyun sunucusu bağlantıları, oyun içi sesli sohbet, 443 dışındaki bütün portlar | Programa hiç uğramaz |
| Listede olmayan sitelere ve servislere giden HTTPS bağlantıları (tarayıcı, oyun başlatıcıları, güncellemeler) | Bakılır, değiştirilmeden geçer |
| Listedeki alan adlarına giden bağlantılar ve Discord ses bağlantısının ilk paketi | Engeli aşacak şekilde değiştirilir |

Liste üç parçadır: kurulumla gelen Discord alan adları, senin eklediklerin ve programın kendi öğrendiği
engelli siteler. Bir oyun ya da başka bir program listedeki bir alan adına bağlanırsa o bağlantı da
işlenir; hangi programın açtığı fark etmez.

Değişiklik yalnızca bağlantının açılışında yapılır; indirme yönündeki veriye dokunulmaz.

**Oyunlarda ping artmaz.** Oyun trafiği programın içinden geçmez, bir sunucuya ya da tünele de
yönlendirilmez; paketler program yokken gittiği yoldan gider.

## Gereksinimler

- Windows 11, 64 bit. Windows 10'da tarayıcı çalışır, Discord gibi uygulamalar açılmayabilir.
- Yönetici hakkı.
- Çalışan başka bir DPI aracı (GoodbyeDPI, zapret, ByeDPI, SplitWire) olmamalı.
- Bazı antivirüsler (ör. Kaspersky) programın kullandığı WinDivert sürücüsünü engeller.

## Kurulum

1. [Releases](../../releases) sayfasından `SlipDPI-kurulum-<sürüm>.exe` dosyasını indirip çalıştır.
2. Windows "Kişisel bilgisayarınızı korudu" uyarısı verirse "Ek bilgi" → "Yine de çalıştır". Kurulum
   programı imzasızdır; dosyayı aynı sayfadaki `SHA256SUMS.txt` ile karşılaştırabilirsin.
3. Başlat menüsü ve masaüstü kısayolu isteyip istemediğini seç.
4. Açılan siyah pencere kurulumu yapar. İlk kurulumda hattını test edip uygun ayarı seçer; bu 2-3 dakika
   sürer ve o sırada engelli siteler kapalıdır. Sonunda kendini sınar ve sonucu yazar.

Bilgisayarı yeniden başlatmak gerekmez. Program açılışta kendiliğinden başlar.

Kurulum programı yerine `SlipDPI-<sürüm>.zip` dosyasını bir klasöre açıp `kur.cmd` dosyasına çift
tıklayarak da kurabilirsin.

**Sisteme ne kurar:** `SlipDPI` adlı bir servis ve WinDivert sürücüsü, `C:\Program Files\SlipDPI`
klasörü, listedeki alan adları için bir DNS kuralı, Chrome için Güvenli DNS ayarı. Windows'un genel DNS
ayarına dokunmaz.

## Kullanım

"SlipDPI" kısayolu (kısayol seçmediysen `C:\Program Files\SlipDPI\panel.cmd`) kontrol penceresini açar.
Pencere yalnızca açıkken çalışır; kapatınca program arka planda çalışmaya devam eder.

- **Durdur / Başlat:** programı kapatır ya da açar. Durdurulmuşsa açılışta da başlamaz.
- **Ekle / Çıkar:** engelli bir siteyi listeye ekler ya da listeden çıkarır.
- **Çıkar ve hariç tut:** programın kendi öğrendiği bir siteyi çıkarır ve bir daha eklememesini sağlar.
  "Geri al" bunu geri çevirir.
- **Yeniden test et:** hattı baştan test edip ayarı yeniden seçer. Engelli siteler yeniden kapanırsa kullan.
- **Onar:** kurulum adımlarını yeniden çalıştırır.
- **Kurulum kaydı:** son kurulumun kaydını açar.
- **Kılavuz:** bu belgeyi açar.
- **Kaldır:** programı kaldırır.

Düğmelerin üzerine gelince ne yaptıkları yazar. "Yeniden test et" ve "Onar" listeleri silmez.

### Yeni bir engelli site

Çoğu zaman bir şey yapman gerekmez: listede olmayan bir site bir dakika içinde üç kez engellenirse program
onu kendi listesine ekler. Pratikte sayfayı iki üç kez yenilemek yeterlidir, sonrası kalıcıdır. Olmazsa
pencereden "Ekle" ile kendin ekle.

Programın öğrendiği siteler "Otomatik eklenenler" sekmesinde görünür. Bu liste bilgisayarında düz metin
olarak durur ve açtığın engelli sitelerin adlarını içerir.

## Sorun giderme

- **Yeni bir engelli site açılmıyor:** sayfayı iki üç kez yenile; olmuyorsa pencereden elle ekle. Chrome
  dışında bir tarayıcıdaysan Güvenli DNS'in açık olduğuna bak.
- **Engelli siteler yeniden kapandı:** pencerede programın çalıştığına bak, sonra "Yeniden test et".
- **Eskiden açılan bir site bozuldu:** "Otomatik eklenenler" sekmesinde varsa "Çıkar ve hariç tut".
- **Listeden çıkardığın site hâlâ açılıyor:** site engelliyse program onu yeniden öğrenir. Hiç işlenmesin
  istiyorsan "Çıkar ve hariç tut".
- **Kurulum sonunda hata yazdı:** "Onar" ile yeniden dene. Servis başlamıyorsa antivirüs WinDivert
  sürücüsünü engelliyor olabilir.
- **Discord "Starting..." ekranında kalıyor:** sistem tepsisinden Discord'dan tamamen çıkıp yeniden aç.
- **Bir şey bozuldu ve nedenini bilmiyorsun:** pencereden "Durdur". Sorun sürüyorsa bu programdan
  kaynaklanmıyordur.

## Kaldırma

Ayarlar → Uygulamalar → SlipDPI → Kaldır, ya da kontrol penceresindeki "Kaldır". Zip ile kurduysan
`kaldir.cmd`. Servis, sürücü, DNS kuralı, Chrome ayarı, kısayollar ve listeler silinir; sistem kurulumdan
önceki haline döner.

## Chrome'da Güvenli DNS

İnternet sağlayıcı engelli sitelerin adresini de yanlış bildirir. Bunu aşmak için kurulum Chrome'da
"Güvenli DNS kullan" ayarını (sağlayıcı: Google) kendisi açar; elle bir şey yapman gerekmez.

Bunun görünür iki sonucu var: Chrome menüsünde "Tarayıcınız kuruluşunuz tarafından yönetiliyor" yazar ve
ayarlardaki "Güvenli DNS kullan" seçeneği açık ve kilitli görünür. İkisi de program kaldırılınca gider.

![Chrome'da Güvenli DNS ayarı](docs/chrome-guvenli-dns.png)

Başka bir tarayıcı kullanıyorsan aynı ayarı elle aç ve sağlayıcı olarak Google'ı seç:

- **Edge, Brave:** Ayarlar → Gizlilik ve güvenlik → Güvenlik → "Güvenli DNS kullan"
- **Firefox:** Ayarlar → Gizlilik ve Güvenlik → "HTTPS üzerinden DNS"

## Bilmen gerekenler

- Yalnızca Türk Telekom hattında denendi. Kurulumdaki test her hatta kendi ayarını seçecek şekilde
  yazıldı, ama Superonline, Vodafone, TurkNet, Kablonet ve mobil hatlarda çalıştığı doğrulanmadı.
- Denenen hatta program açık ve kapalıyken ping, sayfa açılış süresi, indirme ve yükleme hızı aynı ölçüldü.
- İnternet sağlayıcı engelleme yöntemini değiştirirse seçilen ayar çalışmayabilir; "Yeniden test et"
  yeni ayarı arar.
- VPN değildir: IP adresini gizlemez, trafiği şifrelemez, IP adresine göre yapılan engelleri aşmaz.
- Bu programı kullanmanın sorumluluğu kullanana aittir.

## Lisans

Programın kendi betikleri [MIT lisansı](LICENSE) altındadır. İçindeki [zapret](https://github.com/bol-van/zapret)
motoru, WinDivert ve Cygwin dosyaları kendi lisanslarına tabidir; ayrıntılar
[UCUNCU-TARAF.md](UCUNCU-TARAF.md) dosyasındadır.
