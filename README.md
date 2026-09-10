# pw11clock

[mattzzw/kindle-clock](https://github.com/mattzzw/kindle-clock) fork'u — jailbreak'li bir Kindle'ı saat + hava durumu ekranına çeviriyor.

Her dakika ekranı tazeler, dakikanın kalanında cihazı RAM'e suspend eder. Saat başı wifi'yi açıp `ntpdate` ile saati, `wttr.in`'den hava durumunu günceller.

## Upstream'e göre farklar

| | upstream | burada |
|---|---|---|
| `FBINK` | MRInstaller içindeki fbink | `/mnt/us/koreader/fbink -q` |
| `FONT` | Palatino-Regular | Helvetica_LT_65_Medium |
| `CITY` | Hamburg | Istanbul |
| hava | `de.wttr.in` | `wttr.in` (https başarısızsa http'ye düşer) |
| ntp | `de.pool.ntp.org` | `pool.ntp.org` |
| donanım yolları | sabit PW2 yolları | PW2 yolları duruyor, **okunamazsa** cihazdan otomatik bulunuyor |

Donanım blokları (`FBROTATE`, `BACKLIGHT`, `BATTERY`, `TEMP_SENSOR`) elle değiştirilmedi. Sadece o yollar cihazda yoksa script çakılmak yerine `/sys` altından doğrusunu arıyor: pil için `battery_capacity`, sıcaklık için `*_temperature`, backlight için `/sys/class/backlight/*/brightness`, rotate için `/sys/class/graphics/fb0/rotate`. Aynı şekilde `fbink` ve font da bulunamazsa alternatifler deneniyor, `rtcwake` için `rtc1` yoksa `rtc0` kullanılıyor.

## Kurulum (Kindle'da)

> **Önce repo'yu public yap.** Şu an private; `raw.githubusercontent.com` private repo'ya token'sız 404 döner, yani Kindle indiremez.
> GitHub → repo → Settings → General → en altta Danger Zone → Change visibility → Public.
> Public yapmak istemiyorsan alternatif: dosyaları bir gist'e koy, ya da USB ile `/mnt/us/extensions/clock` altına elle kopyala.

kTerm açıkken:

```sh
cd /mnt/us
curl -L -o i.sh https://raw.githubusercontent.com/muderinkok/pw11clock/refs/heads/claude/kindle-clock-setup-d39f1z/install.sh
sh i.sh
```

Link uzunsa is.gd / tinyurl gibi bir kısaltıcıdan geçirip Kindle'a onu yaz.

`install.sh` şunları yapar: `/mnt/us/extensions/clock` klasörünü açar, `kindle-clock.sh` + `config.xml` + `menu.json` dosyalarını indirir, `chmod +x` yapar, donanım yollarını ekrana basar ve onay isteyip saati başlatır.

Seçenekler:

```sh
sh i.sh -y        # sormadan kur ve başlat
sh i.sh -n        # sadece kur, başlatma
sh i.sh --probe   # hiçbir şey kurma, sadece bu cihazın donanım yollarını yazdır
```

`--probe` çıktısı, `find /sys -name battery_capacity` dahil merak ettiğin her şeyi tek seferde veriyor.

Kurulum bittikten sonra saat KUAL'de **Clock** olarak da görünür.

## Durdurma

Saat çalışırken Kindle arayüzü kapalıdır (`stop lab126_gui`). Çıkmanın tek yolu güç düğmesini ~10 saniye basılı tutup yeniden başlatmak.

## Bilinen eksik: ekran koordinatları

`kindle-clock.sh` içindeki `top=` / `left=` / `size=` değerleri PW2 için (758x1024). Daha büyük ekranlı bir cihazda yazılar yukarıya toplanmış görünür. Doğru değerleri ayarlamak için `sh i.sh --probe` çıktısındaki `screen:` satırına bak, sonra script'in sonundaki `$FBINK -b ...` satırlarını ona göre büyüt.

## Dosyalar

* `kindle-clock.sh` — ana döngü: saati basar, RAM'e suspend eder, uyanır
* `install.sh` — Kindle'da tek satırlık kurulum + donanım probe
* `config.xml`, `menu.json` — KUAL menü tanımı

## Gereksinimler

* jailbreak'li Kindle
* KUAL
* `fbink` (KOReader ya da MRInstaller ile gelir)
