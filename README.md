# pw11clock

[mattzzw/kindle-clock](https://github.com/mattzzw/kindle-clock) fork'u — jailbreak'li bir Kindle'ı saat + hava durumu ekranına çeviriyor. **Paperwhite 4 (10. nesil, Rex/Moonshine)** için ayarlandı.

Her dakika ekranı tazeler, dakikanın kalanında cihazı RAM'e suspend eder. Saat başı wifi'yi açıp `ntpdate` ile saati, `wttr.in`'den hava durumunu günceller.

Ekran **yatay** kullanılıyor (upstream'deki gibi) — tuval PW4'te 1448x1072.

## Kurulum (Kindle'da)

kTerm açıkken tek satır:

```sh
cd /mnt/us && curl -L -o i.sh https://github.com/muderinkok/pw11clock/raw/HEAD/install.sh && sh i.sh
```

`HEAD` repo'nun default branch'ine çözülüyor, o yüzden link kısa ve branch adı değişse bile ölmüyor.

`install.sh` şunları yapar: `/mnt/us/extensions/clock` klasörünü açar, `kindle-clock.sh` + `config.xml` + `menu.json` dosyalarını indirir, `chmod +x` yapar, donanım yollarını ekrana basar ve onay isteyip saati başlatır.

```sh
sh i.sh -y        # sormadan kur ve başlat
sh i.sh -n        # sadece kur, başlatma
sh i.sh --probe   # hiçbir şey kurma, sadece bu cihazın donanım yollarını yazdır
REF=main sh i.sh  # başka bir branch/tag'den kur
```

Kurulumdan sonra saat KUAL'de **Clock** olarak da görünür.

## Durdurma

Saat çalışırken Kindle arayüzü kapalıdır (`stop lab126_gui`). Çıkmanın tek yolu güç düğmesini ~10 saniye basılı tutup yeniden başlatmak.

## PW4 donanım yolları

koreader'ın `KindlePaperWhite4:init()` tanımından alındı:

| | PW4 |
|---|---|
| `BATTERY` | `/sys/class/power_supply/bd71827_bat/capacity` |
| `BACKLIGHT` | `/sys/class/backlight/bl/brightness` |
| `FBROTATE_PATH` | `/sys/class/graphics/fb0/rotate` |
| DPI | 300 |
| çözünürlük | 1072x1448 (dikey), yatayda 1448x1072 |

**Dikkat:** PW4'te pil dosyasının adı `capacity`; eski Kindle'lardaki `battery_capacity` **yok**. Yani `find /sys -name battery_capacity` PW4'te boş döner — doğru komut `ls /sys/class/power_supply/*/capacity`. `sh i.sh --probe` ikisine de bakıyor.

**Cihaz sıcaklığı yok.** Upstream alt satırda dış sıcaklığın yanında bir de cihazın kendi sensörünü gösteriyordu. PW4'te bu ancak pil sensöründen okunabiliyor (panel sensörü sysfs'te yok) ve odayı değil cihazın gövdesini ölçtüğü için kaldırıldı. Alt satırda artık sadece dış sıcaklık var.

Diğer modellerin blokları dosyanın başında yorum satırı olarak duruyor. Ayrıca yollardan biri tutmazsa script çakılmak yerine cihazdan doğrusunu arıyor, `fbink` ve font için de alternatifler deniyor, `rtcwake` için `rtc1` yoksa `rtc0` kullanıyor.

## Saat ve wifi

Ekranda gösterilen saat **her zaman Kindle'ın kendi saati** (`date`). Wifi sadece hava durumu için, saat için değil.

Upstream'de wifi ile saat gösterimi iki yerden birbirine bağlıydı ve wifi çekmediğinde saat geri kalıyordu:

1. **Açılışta** wifi bağlı değilse script `exit 1` ile çıkıyordu — yani saat hiç başlamıyordu.
2. **Saat başında** çizim, wifi denemesinden *sonra* yapılıyordu. Wifi yoksa yeniden deneme döngüsü ~31 saniye (+ ntpdate ve curl zaman aşımları) sürüyor, ekran o süre boyunca bir önceki dakikada takılı kalıyordu.

İkisi de düzeltildi: açılışta wifi aranmıyor, ve döngüde **önce çizim yapılıp ekran tazeleniyor**, ağ işleri ondan sonra geliyor. Wifi'ın kopuk olduğu bir saat başında ölçüm:

| | çizim gecikmesi |
|---|---|
| upstream sıralaması | 31.4 sn |
| şimdiki sıralama | 0.1 sn |

Saat başı çekilen hava durumu bir sonraki dakikanın çiziminde görünür; saat hiç beklemez.

`ntpdate` hâlâ var ama artık sadece wifi zaten bağlıyken ve çizimden sonra çalışıyor — ekranı hiçbir şekilde geciktiremez. Tek işi Kindle'ın RTC'sinin zamanla kaymasını toparlamak (upstream'in notuna göre bu RTC epey kayıyor). Sistem saatine hiç dokunulmasını istemezsen `kindle-clock.sh` başındaki `USE_NTP=1` değerini `0` yap.

## Ekran yerleşimi

Koordinatlar PW4 yatay tuvaline (1448x1072) göre yazıldı, ama açılışta `fbink -e` ile gerçek çözünürlük okunup ölçekleniyor — PW2'de de PW5'te de bozulmuyor.

Punto değerleri (`size=150` vb.) hiç değişmiyor: fbink puntoyu panelin DPI'ıyla piksele çeviriyor (`px = dpi/72 * pt`), yani PW2'nin 212 DPI'ından PW4'ün 300 DPI'ına zaten kendiliğinden ölçekleniyor. Sadece piksel cinsinden olan `top=` / `left=` kenar boşlukları ölçekleniyor.

`ROTATE_VALUE=0`'ın PW4'te yatay verdiği gerçek cihazda doğrulandı. Başka bir modelde ekran dikey açılırsa `kindle-clock.sh` başındaki bu değeri 1, 2 veya 3 yap.

## Upstream'e göre farklar

| | upstream | burada |
|---|---|---|
| `FBINK` | MRInstaller içindeki fbink | `/mnt/us/koreader/fbink` |
| `FONT` | Palatino-Regular | Helvetica_LT_65_Medium |
| `CITY` | Hamburg | Istanbul |
| hava | `de.wttr.in` | `wttr.in` (https başarısızsa http'ye düşer) |
| ntp | `de.pool.ntp.org` | `pool.ntp.org` |
| donanım | sabit PW2 yolları | PW4 yolları + otomatik fallback |
| yerleşim | sabit PW2 pikselleri | PW4 referansı, çözünürlüğe göre ölçekli |
| iç sıcaklık | dış sıcaklığın yanında gösterilir | kaldırıldı, sadece dış sıcaklık |
| wifi yoksa | açılışta çıkar, saat başı 31 sn donar | saat etkilenmez |

## Dosyalar

* `kindle-clock.sh` — ana döngü: saati basar, RAM'e suspend eder, uyanır
* `install.sh` — Kindle'da tek satırlık kurulum + donanım probe
* `config.xml`, `menu.json` — KUAL menü tanımı

## Gereksinimler

* jailbreak'li Kindle
* KUAL
* `fbink` (KOReader ya da MRInstaller ile gelir)
