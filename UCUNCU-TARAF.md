# Üçüncü taraf bileşenler

Bu depodaki `bin\` ve `filters\` klasörlerindeki dosyalar değiştirilmeden başka projelerden alınmıştır.

## Kaynak

Hepsi [bol-van/zapret-win-bundle](https://github.com/bol-van/zapret-win-bundle) deposunun `zapret-winws`
klasöründen, 9 Kasım 2026 tarihli `6b4375fa04` commit'inden alındı. İndirilen dosyalar GitHub'ın bildirdiği
git blob özetleriyle karşılaştırılarak doğrulandı.

| Dosya | Proje | Sürüm | SHA-256 |
|---|---|---|---|
| `bin\winws.exe` | [zapret](https://github.com/bol-van/zapret) | v72.12 | `2da71e80878dc270ac83f5893ecbb841f9752a57f1da8ff9325636b4346bc632` |
| `bin\WinDivert.dll` | [WinDivert](https://github.com/basil00/WinDivert) | 2.2 | `16abd6a029e65557c6a309bea7b13bf81fff4e193567582e1cddbf6719f323e0` |
| `bin\WinDivert64.sys` | WinDivert | 2.2 | `8da085332782708d8767bcace5327a6ec7283c17cfb85e40b03cd2323a90ddc2` |
| `bin\cygwin1.dll` | [Cygwin](https://cygwin.com) | zapret paketindeki sürüm | `103104a52e5293ce418944725df19e2bf81ad9269b9a120d71d39028e821499b` |
| `filters\windivert_part.*.txt` | zapret | aynı commit | metin dosyaları |

Aynı özetler `bin\SHA256SUMS.txt` dosyasındadır; `kur.ps1` kurulumdan önce dosyaları bu listeyle karşılaştırır.

Git blob özetleri (GitHub'daki dosyayla karşılaştırmak için, `git hash-object <dosya>`):

    winws.exe        ea098a19fc808b11cd95466c3a04f64849580585
    WinDivert.dll    2c55eeb6921351a6cad292a900f4b8d7d41c4bcc
    WinDivert64.sys  218ccaf423ef0a67696226f9ef3a09149e4441d0
    cygwin1.dll      1bb2e05c6d5458ad7987859a17172b635e87b9c5

## Bilinmesi gerekenler

- `WinDivert64.sys` bir çekirdek sürücüsüdür. İmza sahibi olarak "成都密思听科技有限公司" görünür (Windows imzayı
  geçerli sayıyor). Bu depo dosyayı zapret paketindeki haliyle içerir; imzanın kime ait olduğu ayrıca araştırılmadı.
- `winws.exe`, `WinDivert.dll` ve `cygwin1.dll` imzasızdır.
- zapret-win-bundle deposu geçmişini tek commit olarak yeniden yazdığı için yukarıdaki commit ileride
  erişilemez olabilir; özetler bu yüzden burada kayıtlıdır.

## Lisanslar

Aşağıdakiler projelerin kendi beyanlarıdır. Depoyu herkese açık yapmadan ya da dosyaları yeniden
dağıtmadan önce her projenin güncel lisans dosyasını kendi deposundan kontrol et.

- **zapret**: MIT lisansı.
- **WinDivert**: LGPLv3 ya da GPLv2 (çift lisans).
- **Cygwin (`cygwin1.dll`)**: LGPLv3 ve sonrası.
