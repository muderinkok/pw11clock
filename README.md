# pw11clock

[mattzzw/kindle-clock](https://github.com/mattzzw/kindle-clock) fork'u — jailbreak'li bir Kindle'ı saat + hava durumu ekranına çeviriyor. **Paperwhite 4 (10. nesil, Rex/Moonshine)** için ayarlandı.

Her dakika ekranı tazeler, dakikanın kalanında cihazı RAM'e suspend eder. Saat başı wifi'yi açıp `ntpdate` ile saati, `wttr.in`'den hava durumunu günceller.

Ekran **yatay** kullanılıyor (upstream'deki gibi) — tuval PW4'te 1448x1072.

## Kurulum (Kindle'da)

kTerm açıkken:

```sh
cd /mnt/us
curl -L -o i.sh https://raw.githubusercontent.com/muderinkok/pw11clock/refs/heads/claude/kindle-clock-setup-d39f1z/install.sh
sh i.sh
```

Link uzunsa is.gd / tinyurl gibi bir kısaltıcıdan geçirip Kindle'a onu yaz.

`install.sh` şunları yapar: `/mnt/us/extensions/clock` klasörünü açar, `kindle-clock.sh` + `config.xml` + `menu.json` dosyalarını indirir, `chmod +x` yapar, donanım yollarını ekrana basar ve onay isteyip saati başlatır.

```sh
sh i.sh -y        # sormadan kur ve başlat
sh i.sh -n        # sadece kur, başlatma
sh i.sh --probe   # hiçbir şey kurma, sadece bu cihazın donanım yollarını yazdır
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

**İç sıcaklık belirsiz.** PW4 panel sıcaklığını sysfs yerine bir ioctl üzerinden veriyor, bilinen sağlam bir dosya yok. Script önce `bd71827_bat/temp`, sonra `thermal_zone0/temp`, sonra `papyrus_temperature` deniyor; hiçbiri okunmazsa iç sıcaklığı hiç göstermiyor (dış sıcaklık yine görünür). Okunan değerin birimi de otomatik normalize ediliyor (milli/desi/tam santigrat).

Diğer modellerin blokları dosyanın başında yorum satırı olarak duruyor. Ayrıca yollardan biri tutmazsa script çakılmak yerine cihazdan doğrusunu arıyor, `fbink` ve font için de alternatifler deniyor, `rtcwake` için `rtc1` yoksa `rtc0` kullanıyor.

## Ekran yerleşimi

Koordinatlar PW4 yatay tuvaline (1448x1072) göre yazıldı, ama açılışta `fbink -e` ile gerçek çözünürlük okunup ölçekleniyor — PW2'de de PW5'te de bozulmuyor.

Punto değerleri (`size=150` vb.) hiç değişmiyor: fbink puntoyu panelin DPI'ıyla piksele çeviriyor (`px = dpi/72 * pt`), yani PW2'nin 212 DPI'ından PW4'ün 300 DPI'ına zaten kendiliğinden ölçekleniyor. Sadece piksel cinsinden olan `top=` / `left=` kenar boşlukları ölçekleniyor.

Ekran dikey açılırsa `kindle-clock.sh` başındaki `ROTATE_VALUE` değerini 1, 2 veya 3 yap.

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
| iç sıcaklık | `cat` (yoksa patlar) | opsiyonel, birim normalize |

## Dosyalar

* `kindle-clock.sh` — ana döngü: saati basar, RAM'e suspend eder, uyanır
* `install.sh` — Kindle'da tek satırlık kurulum + donanım probe
* `config.xml`, `menu.json` — KUAL menü tanımı

## Gereksinimler

* jailbreak'li Kindle
* KUAL
* `fbink` (KOReader ya da MRInstaller ile gelir)
