# pw11clock

[mattzzw/kindle-clock](https://github.com/mattzzw/kindle-clock) fork'u — jailbreak'li bir Kindle'ı saat + hava durumu ekranına çeviriyor. **Paperwhite 4 (10. nesil, Rex/Moonshine)** için ayarlandı.

Her dakika ekranı tazeler. Günde bir kez (sabah 05:00) wifi'ı kısa süreliğine açıp `ntpdate` ile saati düzeltir ve [Open-Meteo](https://open-meteo.com)'dan günün tahminini çeker; geri kalan zamanda wifi kapalıdır.

Ekran **yatay** kullanılıyor (upstream'deki gibi) — tuval PW4'te 1448x1072.

## Kurulum (Kindle'da)

kTerm açıkken tek satır:

```sh
cd /mnt/us && curl -fL -o i.sh https://github.com/muderinkok/pw11clock/raw/HEAD/install.sh && sh i.sh
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

Saat wifi'a ve uçak moduna **hiç dokunmuyor**; Kindle'ı yeniden başlattığında wifi, saati başlattığında nasılsa öyle. (Eski sürümler wifi'ı uçak moduyla kapatıyordu ve zorla yeniden başlatma script'e onu geri açma fırsatı vermediği için Kindle uçak modunda kalıyordu. `install.sh` bu durumu hâlâ düzeltiyor: bağlı değilse wifi'ı açıp bağlanmayı bekliyor.)

## Günlük (log)

Script `/mnt/us/clock.log` dosyasına yazıyor: saatte bir çizilen saat, pil ve Kindle'ın güç durumu (`powerd`); ayrıca wifi denemeleri ve tahmin çekimleri. Flash belleği boşta tutmak için her dakika yazılmıyor. 256 KB'ı geçince son ~2000 satır tutuluyor. Bir sorun olursa ilk bakılacak yer burası; kTerm'de `tail -50 /mnt/us/clock.log`.

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

**Ekrandaki saat her zaman Kindle'ın sistem saati** (`date`), ve bunun wifi ile hiçbir bağı yok:

- **İnternet işleri arka planda.** Wifi'ı açma, bağlanmayı bekleme, `ntpdate` ve tahmin isteği ayrı bir süreçte çalışıyor ve sonucu bir dosyaya bırakıyor; çizim döngüsü sadece o dosyayı okuyor. Ağ ne yaparsa yapsın ekran bir saniye bile beklemiyor. 5 dakikadan uzun süren bir iş öldürülüyor.
- **Uyanınca ilk iş çizim.**

### Wifi: günde bir kez (`WIFI_MODE`)

```sh
WIFI_MODE="daily"
```

- **`daily`** (varsayılan): wifi sadece sabahki çekim için açılıp hemen kapanıyor. Bütün gün açık kalan wifi pilin bir kısmını yiyordu.
- **`leave`**: wifi'a hiç dokunma; Kindle zaten bağlıysa çek.

Açma/kapama **uçak moduyla yapılmıyor** (`com.lab126.cmd wirelessEnable` hiç değişmiyor), çünkü uçak modu yeniden başlatmada kalıcı ve bu Kindle ondan sonra ağına kendiliğinden dönmüyordu. Onun yerine KOReader'ın yöntemi: `com.lab126.wifid enable 0/1` ile wifi servisi kapatılıp açılıyor, açarken de kayıtlı ağa adıyla bağlanması isteniyor (`com.lab126.cmd ensureConnection "wifi:<ağ>"`). Ağ adı, saatin Kindle'ı bağlı gördüğü son ağ; `wifi_ssid` dosyasında saklanıyor.

Bağlantı 2 dakika içinde gelmezse wifi tekrar kapatılıp 15 dakika sonra yeniden deneniyor ve köşede `No Wifi!` çıkıyor. Saat hiç etkilenmiyor.

`ntpdate` de günde bir, bu çekimle birlikte çalışıyor (`USE_NTP=1`). Sistem saatine hiç dokunulmasın istersen `USE_NTP=0`.

## Uyku modu: neden artık suspend yok

Upstream her dakikayı çizdikten sonra `rtcwake` ile bir saat çipi alarmı kurup cihazı RAM'e suspend ediyordu. PW4'te bu güvenilir değil: saat bir süre geç uyanıp sonra tamamen durdu (22:31'de donup sabaha kadar öyle kaldı).

Sebebi: Kindle'da uyandırma alarmının sahibi sistemin kendi güç servisi `powerd`. KOReader'ın kaynağında da açıkça yazıyor — *"Kindle only allows setting the RTC via lipc during the ReadyToSuspend state"* — KOReader bu yüzden alarmı kendisi kurmuyor, `powerd`'a `rtcWakeup` ile söylüyor. Bizim script `powerd`'ı atlayıp alarmı doğrudan kuruyordu; ikisi çakışınca alarm kayboluyor ve cihaz uyanmıyor.

Artık `kindle-clock.sh` başında bir ayar var:

```sh
SLEEP_MODE="awake"
```

- **`awake`** (varsayılan): cihaz uyanık kalıyor, dakikalar arası düz `sleep`. Saat hiç şaşmıyor. Karşılığı pil: şarja takılıyken önemi yok, pille çalışırken suspend moduna göre çok daha hızlı biter. Log'da her dakika pil yüzdesi var; tüketimi görmek için: `grep Drew /mnt/us/clock.log | sed -n '1p;$p'`
- **`suspend`**: eski pil dostu davranış, deneysel. Güvenlik önlemleri eklendi: alarm her saat çipine kuruluyor ve kurulduğu doğrulanmadan ya da 10 saniyeden az süre kaldıysa suspend edilmiyor (geçmişte kalan bir alarm hiç çalmaz). Erken uyanma ya da başarısız suspend düz `sleep` ile tamamlanıyor. Ama `powerd` çakışması hâlâ olabilir.

Ayrıca her iki modda:

- Çizim ve planlama **tek bir `date` çağrısından** okunuyor; çizilen dakikayla uyku hesabı hep aynı ana dayanıyor.
- Yapılan iş bir sonraki dakikaya taşarsa uyumadan hemen o dakika çiziliyor. Upstream'in "5 saniyeden az kaldıysa 60 saniye ekle" kuralı o dakikayı atlıyordu.
- `preventScreenSaver` her dakika yeniden ayarlanıyor, çünkü `powerd` bunu wifi/güç değişimlerinde düşürebiliyor.

## Hava durumu: günlük tahmin

Ekranda o anki hava değil, **günün tahmini** var: hava durumu, yağmur olasılığı, en yüksek / en düşük sıcaklık ve bir ikon.

```
        Partly cloudy, 40% rain
        ☁  22° / 15°
        Today's forecast
```

- **Kaynak:** [Open-Meteo](https://open-meteo.com) — ücretsiz, anahtar istemiyor. Kindle'da `jq` olmadığı için JSON yerine CSV çekiliyor (`format=csv`) ve `awk` ile okunuyor. Konum `kindle-clock.sh` başında `LAT`/`LON` (İstanbul).
- **Ne zaman:** her gün `FORECAST_HOUR` (05) ve sonrasında, o gün henüz çekilmediyse. Açılışta hiç tahmin yoksa hemen.
- **Bugün ve yarın birlikte çekiliyor**, böylece gece yarısı ekran ağa ihtiyaç duymadan doğru güne geçiyor.
- **Önbellek:** son başarılı tahmin `forecast.csv` dosyasına yazılıyor; yeniden başlatmadan sonra hemen görünüyor.
- **Eskiyse belli oluyor:** bugüne ait satır yoksa (çekim günlerce başarısız olduysa) en son gün gösteriliyor ve alt satır `Today's forecast` yerine `Forecast for Mon 5 Oct` oluyor.
- **Yağmur olasılığı:** yağışlı bir günde `Rain (80%)`, kuru ama %30 ve üstü ihtimalli bir günde `Partly cloudy, 40% rain`.
- **İkon:** [Weather Icons](https://github.com/erikflowers/weather-icons) fontu (`weathericons.ttf`, SIL OFL 1.1). Open-Meteo'nun WMO hava kodundan seçiliyor; günün tamamı için olduğundan hep gündüz ikonları.

İkon, fbink'in `format` modunda "bold" font olarak veriliyor: `**<ikon>**  22° / 15°`. Böylece ikon ve sıcaklıklar tek satır olarak ortalanıyor.

## Pil

Şarja takılı değilken ~3 gün gidiyordu (uyanık mod, wifi bütün gün açık, her dakika log). Yapılanlar:

- wifi günde ~2 dakika açık (`WIFI_MODE=daily`)
- tahmin, ikon ve metinler günde bir hesaplanıyor; her dakika sadece çizim
- log her dakika yerine saatte bir
- tüm işlemci çekirdekleri `powersave`

Tüketimi ölçmek için: `grep Drew /mnt/us/clock.log | sed -n '1p;$p'` — ilk ve son satırdaki pil yüzdesi ile saat farkı.

## Pil göstergesi

Sağ üstte, doluluğuyla orantılı bir pil ikonu ve solunda yüzde (`96%`). İkon fbink'le dolu dikdörtgenlerden çiziliyor (`-k` bölgeyi `-B` rengine boyuyor), ek font gerekmiyor. Yüzdenin genişliği fbink'in `compute` moduyla ölçülüyor — sadece değer değiştiğinde — böylece `9%` da `100%` da ikona aynı mesafede bitiyor. Pil okunamazsa hiçbir şey çizilmiyor.

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
| hava | `de.wttr.in`, saatte bir, o anki hava | Open-Meteo, günde bir, günün tahmini |
| ntp | `de.pool.ntp.org` | `pool.ntp.org` |
| donanım | sabit PW2 yolları | PW4 yolları + otomatik fallback |
| yerleşim | sabit PW2 pikselleri | PW4 referansı, çözünürlüğe göre ölçekli |
| iç sıcaklık | dış sıcaklığın yanında gösterilir | kaldırıldı, sadece dış sıcaklık |
| wifi yoksa | açılışta çıkar, saat başı 31 sn donar | saat etkilenmez |
| wifi yönetimi | her saat uçak modunu açıp kapatır | günde bir wifid ile açıp kapatır, uçak moduna dokunmaz; ağ işleri arka planda |
| dakikalar arası | `rtcwake` + suspend, PW4'te donuyor | `SLEEP_MODE=awake`, suspend opsiyonel |
| log | `/dev/null` | `/mnt/us/clock.log`, boyutu sınırlı |
| pil göstergesi | `Bat: 96` yazısı | sağ üstte dolulukla orantılı pil ikonu + `96%` |
| hava ikonu | yok | Weather Icons, gece/gündüz |
| veri yaşı | gösterilmez | `Today's forecast` / `Forecast for <gün>` |

## Yapılacaklar

- [x] **Hava durumu güncelleme sıklığını düşür.** Günde bire indi (05:00, günlük tahmin).
- [ ] **Suspend'i `powerd` üzerinden yap.** Pil için en büyük kazanç; KOReader gibi alarmı `lipc-set-prop com.lab126.powerd rtcWakeup` ile kurmak. Cihazda deneme gerektiriyor.
- [ ] **Her dakika sadece saat bölgesini tazele.** Tüm ekran yerine saat alanı; tarih ve tahmin sadece değiştiğinde.

## Dosyalar

* `kindle-clock.sh` — ana döngü: saati basar, RAM'e suspend eder, uyanır
* `install.sh` — Kindle'da tek satırlık kurulum + donanım probe
* `config.xml`, `menu.json` — KUAL menü tanımı
* `weathericons.ttf`, `LICENSE-weathericons.txt` — hava durumu ikon fontu ve lisansı
* `forecast.csv`, `wifi_ssid` — cihazda oluşur: son tahmin ve bağlanılacak ağın adı

## Gereksinimler

* jailbreak'li Kindle
* KUAL
* `fbink` (KOReader ya da MRInstaller ile gelir)
