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

Saat wifi'a ve uçak moduna **hiç dokunmuyor**; Kindle'ı yeniden başlattığında wifi, saati başlattığında nasılsa öyle. (Eski sürümler wifi'ı uçak moduyla kapatıyordu ve zorla yeniden başlatma script'e onu geri açma fırsatı vermediği için Kindle uçak modunda kalıyordu. `install.sh` bu durumu hâlâ düzeltiyor: bağlı değilse wifi'ı açıp bağlanmayı bekliyor.)

## Günlük (log)

Script her dakika ne yaptığını `/mnt/us/clock.log` dosyasına yazıyor: çizilen saat, pil, Kindle'ın güç durumu (`powerd`), wifi denemeleri, hava durumu. Günde ~85 KB büyüyor, 256 KB'ı geçince son ~2000 satır tutuluyor. Bir sorun olursa ilk bakılacak yer burası; kTerm'de `tail -50 /mnt/us/clock.log`.

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

- **Script wifi'a dokunmuyor.** Uçak modu, yeniden bağlanma, `wpa_cli` yok. Wifi Kindle'ın kendi işi; bağlıysa kullanılıyor, değilse bir sonraki dakika tekrar bakılıyor.
- **İnternet işleri arka planda.** `ntpdate` ve hava durumu ayrı bir süreçte çalışıyor ve sonucu bir dosyaya bırakıyor; çizim döngüsü sadece o dosyayı okuyor. DNS asılı kalsa, ağ ölü olsa, istek dakikalarca sürse de ekran bir saniye bile beklemiyor. 5 dakikadan uzun süren bir istek öldürülüyor.
- **Uyanınca ilk iş çizim.** Pil okuma dışında hiçbir şey çizimden önce çalışmıyor.
- Hava durumu saat başı ve açılışta "vadesi gelmiş" sayılıyor; wifi bağlıysa en fazla 5 dakikada bir deneniyor, alınana kadar. Wifi yoksa köşede `No Wifi!` çıkıyor ve `Updated N h ago` büyüyor — ama saat hiç etkilenmiyor.

Upstream'de wifi ile saat iki yerden bağlıydı: açılışta wifi yoksa script çıkıyordu, saat başında da çizim wifi beklemesinden sonra yapılıyordu (wifi yoksa ~31 sn donuyordu). İkisi de gitti.

`ntpdate` duruyor (`USE_NTP=1`): sistem saatini düzeltir, ekran da her zaman sistem saatini gösterir. Sistem saatine hiç dokunulmasın istersen `USE_NTP=0`.

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

## Hava durumu ikonu ve "Updated" satırı

Sıcaklığın solunda hava durumuna göre bir ikon, altında küçük bir `Updated 12 min ago` satırı var.

- **İkon:** Kindle fontları emoji basamıyor, o yüzden [Weather Icons](https://github.com/erikflowers/weather-icons) fontu (`weathericons.ttf`, SIL OFL 1.1) script'in yanında geliyor. Hava tipi wttr.in'in dil bağımsız `%x` kodundan okunuyor (`o` güneşli, `m` parçalı bulutlu, `///` yoğun yağmur, `*` kar...), metinden değil. Font yoksa ya da kod tanınmazsa sadece sıcaklık yazılır.
- **Gece/gündüz:** wttr.in'den şehrin gün doğumu/batımı da çekiliyor (`%S`, `%s`). Gece güneş yerine ay, bulut yerine gece bulutu gösteriliyor. Bu saatler gelmezse 07:00–19:00 varsayılıyor.
- **Updated:** son başarılı hava durumu çekiminden beri geçen süre; bir saatin altında dakika, üstünde saat. Wifi çekmediğinde saat başları atlanır ve bu sayı büyür — gösterilen havanın ne kadar eski olduğunu buradan anlarsın.
- wttr.in bazen hata durumunda düz bir cümleyle cevap veriyor; yanıt beklenen biçimde değilse yok sayılıp eski veri korunuyor.

İkon, fbink'in `format` modunda "bold" font olarak veriliyor: `**<ikon>**  21°C`. Böylece ikon ve sıcaklık tek satır olarak ortalanıyor.

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
| wifi yönetimi | her saat uçak modunu açıp kapatır | hiç dokunmaz, ağ işleri arka planda |
| dakikalar arası | `rtcwake` + suspend, PW4'te donuyor | `SLEEP_MODE=awake`, suspend opsiyonel |
| log | `/dev/null` | `/mnt/us/clock.log`, boyutu sınırlı |
| hava ikonu | yok | Weather Icons, gece/gündüz |
| veri yaşı | gösterilmez | `Updated N min/h ago` |

## Dosyalar

* `kindle-clock.sh` — ana döngü: saati basar, RAM'e suspend eder, uyanır
* `install.sh` — Kindle'da tek satırlık kurulum + donanım probe
* `config.xml`, `menu.json` — KUAL menü tanımı
* `weathericons.ttf`, `LICENSE-weathericons.txt` — hava durumu ikon fontu ve lisansı

## Gereksinimler

* jailbreak'li Kindle
* KUAL
* `fbink` (KOReader ya da MRInstaller ile gelir)
