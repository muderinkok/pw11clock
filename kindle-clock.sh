#!/bin/sh

### Shown in the log and by diag.sh, so it is clear which version runs.
VERSION="2026-10-09"

### Where this script lives; the weather icon font ships alongside it.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ICON_FONT="$SCRIPT_DIR/weathericons.ttf"
### Log to a file so that when something goes wrong on the device there is a
### record of it. It grows ~85 KB a day and is trimmed to the last ~2000
### lines (a day or so) once it passes 256 KB. Set to /dev/null to disable.
LOG="/mnt/us/clock.log"
FBINK_BIN="/mnt/us/koreader/fbink"
FONT="regular=/usr/java/lib/fonts/Helvetica_LT_65_Medium.ttf"
#FONT="regular=/usr/java/lib/fonts/Caecilia_LT_75_Bold.ttf"
USE_NTP=1

### Daily forecast from open-meteo.com (free, no API key). This is Istanbul.
LAT="41.01"
LON="28.98"
### The forecast is fetched once a day, at this hour or as soon after it as
### the network allows. It covers today and tomorrow, so at midnight the
### screen moves on to the right day without needing the network.
FORECAST_HOUR=5

### What to do with wifi.
###   daily  switch wifi on for the morning fetch and off again straight
###          after, instead of leaving it on all day. Airplane mode is never
###          touched (see wifi_on).
###   leave  never touch wifi; fetch whenever the kindle happens to be online.
WIFI_MODE="daily"

### How to wait between minutes.
###   awake    stay awake and sleep. Keeps exact time; costs battery, which
###            does not matter while the kindle is on its charger.
###   suspend  suspend to RAM with an rtc alarm. Battery friendly, but on a
###            kindle the rtc alarm belongs to the system's powerd, and on a
###            PW4 the clock has been seen to stop waking up. Experimental.
SLEEP_MODE="awake"
COND="---"
TEMP="---"
FC_ICON=""
FC_LABEL=""

### The clock runs in landscape, which is what writing to the fb rotate
### node achieves. 0 is confirmed to give landscape on a PW4; if some other
### device comes up portrait, try 1, 2 or 3 here.
ROTATE_VALUE=0

### uncomment/adjust according to your hardware
#K4NT
#FBROTATE_PATH="" # uses /proc/eink_fb/update_display, see below
#BACKLIGHT="/dev/null"
#BATTERY="/sys/devices/system/yoshi_battery/yoshi_battery0/battery_capacity"

#PW2
#FBROTATE_PATH="/sys/devices/platform/mxc_epdc_fb/graphics/fb0/rotate"
#BACKLIGHT="/sys/devices/system/fl_tps6116x/fl_tps6116x0/fl_intensity"
#BATTERY="/sys/devices/system/yoshi_battery/yoshi_battery0/battery_capacity"

#PW3
#FBROTATE_PATH="/sys/devices/platform/imx_epdc_fb/graphics/fb0/rotate"
#BACKLIGHT="/sys/devices/platform/imx-i2c.0/i2c-0/0-003c/max77696-bl.0/backlight/max77696-bl/brightness"
#BATTERY="/sys/devices/system/wario_battery/wario_battery0/battery_capacity"

#PW4 (Rex / Moonshine, 1072x1448 @ 300dpi)
### Paths taken from koreader's KindlePaperWhite4:init(). Note that the
### battery node is "capacity", not the "battery_capacity" older kindles use.
FBROTATE_PATH="/sys/class/graphics/fb0/rotate"
BACKLIGHT="/sys/class/backlight/bl/brightness"
BATTERY="/sys/class/power_supply/bd71827_bat/capacity"

### Layout below is tuned against this canvas, in landscape. Everything is
### scaled to whatever fbink actually reports, so it survives a PW2 or a PW5.
REF_W=1448
REF_H=1072

log() {
    echo "$(date '+%Y-%m-%d_%H:%M:%S'): $*" >> $LOG
}

rotate_log() {
    [ -f "$LOG" ] || return 0
    [ "$(wc -c < "$LOG")" -gt 262144 ] || return 0
    tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
}

wifi_connected() {
    [ "$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)" = "CONNECTED" ]
}


### Wifi on/off through wifid only. The airplane-mode switch
### (com.lab126.cmd wirelessEnable) is never touched: it survives a reboot,
### and after it this kindle does not rejoin its network on its own. Turning
### on follows koreader: enable wifid, then ask cmd to connect to the saved
### network by name.
wifi_on() {
    lipc-set-prop -i com.lab126.wifid enable 1
    if [ -n "$WIFI_SSID" ]; then
        lipc-set-prop -s com.lab126.cmd ensureConnection "wifi:$WIFI_SSID"
    fi
}

wifi_off() {
    lipc-set-prop -i com.lab126.wifid enable 0
}

### The network to rejoin is the one the kindle was on the last time we saw
### it connected, kept across restarts.
SSID_FILE="$SCRIPT_DIR/wifi_ssid"
remember_ssid() {
    S=$(wpa_cli -i wlan0 status 2>/dev/null | sed -n 's/^ssid=//p')
    if [ -n "$S" ] && [ "$S" != "$WIFI_SSID" ]; then
        WIFI_SSID="$S"
        printf '%s' "$S" > "$SSID_FILE"
        log "Remembering wifi network '$S'."
    fi
}

### open-meteo daily forecast as csv. The data rows look like
###   time,weather_code (wmo code),temperature_2m_max (°C),temperature_2m_min (°C),precipitation_probability_max (%)
###   2026-10-05,3,22.1,14.3,40
FORECAST_CACHE="$SCRIPT_DIR/forecast.csv"
FORECAST_QUERY="latitude=$LAT&longitude=$LON&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=2&format=csv"

### Tries https, then https without certificate checks -- the kindle's CA
### bundle predates the roots some sites now use, and this is only weather --
### then plain http. Every attempt's curl exit code goes in the log.
fetch_forecast() {
    TRIED=""
    for MODE in https https-k http; do
        case "$MODE" in
            https)   F=$(curl -s -f -m 15 "https://api.open-meteo.com/v1/forecast?$FORECAST_QUERY") ;;
            https-k) F=$(curl -s -f -k -m 15 "https://api.open-meteo.com/v1/forecast?$FORECAST_QUERY") ;;
            http)    F=$(curl -s -f -m 15 "http://api.open-meteo.com/v1/forecast?$FORECAST_QUERY") ;;
        esac
        RC=$?
        TRIED="$TRIED $MODE=$RC"
        [ -n "$F" ] && break
    done
    log "Got forecast ($TRIED): $(printf '%s\n' "$F" | forecast_rows | tr '\n' ' ')"
    printf '%s' "$F"
}

### The data rows of the csv: everything after its "time," header.
forecast_rows() {
    awk -F, 'f && NF > 1 { print } /^time,/ { f = 1 }'
}

### WMO weather code (open-meteo's weather_code) as text.
wmo_text() {
    case "$1" in
        0)        echo "Clear sky" ;;
        1)        echo "Mainly clear" ;;
        2)        echo "Partly cloudy" ;;
        3)        echo "Overcast" ;;
        45|48)    echo "Fog" ;;
        51|53|55) echo "Drizzle" ;;
        56|57)    echo "Freezing drizzle" ;;
        61)       echo "Light rain" ;;
        63)       echo "Rain" ;;
        65)       echo "Heavy rain" ;;
        66|67)    echo "Freezing rain" ;;
        71)       echo "Light snow" ;;
        73)       echo "Snow" ;;
        75)       echo "Heavy snow" ;;
        77)       echo "Snow grains" ;;
        80)       echo "Light showers" ;;
        81)       echo "Showers" ;;
        82)       echo "Heavy showers" ;;
        85|86)    echo "Snow showers" ;;
        95)       echo "Thunderstorm" ;;
        96|99)    echo "Thunderstorm, hail" ;;
        *)        echo "---" ;;
    esac
}

### Weather Icons glyph for a WMO code. Codepoints from erikflowers/weather-icons
### (values/weathericons.xml) as the utf-8 octal bytes printf understands. Day
### variants only: this is a forecast for the whole day.
wmo_icon() {
    case "$1" in
        0)              G='\357\200\215' ;; # day-sunny
        1)              G='\357\200\214' ;; # day-sunny-overcast
        2)              G='\357\200\202' ;; # day-cloudy
        3)              G='\357\200\223' ;; # cloudy
        45|48)          G='\357\200\224' ;; # fog
        51|53|55)       G='\357\200\234' ;; # sprinkle
        56|57|66|67)    G='\357\202\265' ;; # sleet
        61|80)          G='\357\200\211' ;; # day-showers
        63|81)          G='\357\200\232' ;; # showers
        65|82)          G='\357\200\231' ;; # rain
        71|73|75|77)    G='\357\200\233' ;; # snow
        85|86)          G='\357\200\212' ;; # day-snow
        95|96|99)       G='\357\200\236' ;; # thunderstorm
        *)              return 1 ;;
    esac
    printf "$G"
}

### Loads forecast csv text: remembers the day it was fetched (its first row)
### and makes the next draw pick the row to show.
load_forecast() {
    FC_CSV="$1"
    FC_FIRST=$(printf '%s\n' "$FC_CSV" | forecast_rows | head -n 1)
    FC_FIRST=${FC_FIRST%%,*}
    FC_SHOWN=""
}

### Turns today's row into what is drawn. With no row for today (the daily
### fetch has been failing for a while) the latest day there is gets shown,
### labelled with its date so it is obviously stale.
select_forecast() {
    ROWS=$(printf '%s\n' "$FC_CSV" | forecast_rows)
    ROW=$(printf '%s\n' "$ROWS" | awk -F, -v d="$TODAY" '$1 == d { print; exit }')
    [ -n "$ROW" ] || ROW=$(printf '%s\n' "$ROWS" | tail -n 1)
    [ -n "$ROW" ] || return 1

    FC_DATE=${ROW%%,*}; R=${ROW#*,}
    FC_CODE=${R%%,*};   R=${R#*,}
    F_MAX=${R%%,*};     R=${R#*,}
    F_MIN=${R%%,*};     F_RAIN=${R#*,}

    COND=$(wmo_text "$FC_CODE")
    ### Chance of rain: on its own for a wet day ("Rain (80%)"), spelled out
    ### for a dry one that might still turn ("Partly cloudy, 40% rain").
    case "$F_RAIN" in
        [0-9]|[0-9][0-9]|100)
            if [ "$FC_CODE" -ge 51 ] 2>/dev/null; then
                COND="$COND ($F_RAIN%)"
            elif [ "$F_RAIN" -ge 30 ]; then
                COND="$COND, $F_RAIN% rain"
            fi
            ;;
    esac
    TEMP=$(awk -v a="$F_MAX" -v b="$F_MIN" 'BEGIN {
        if (a !~ /^-?[0-9.]+$/ || b !~ /^-?[0-9.]+$/) exit 1
        printf "%d° / %d°", sprintf("%.0f", a), sprintf("%.0f", b) }') || TEMP="---"
    FC_ICON=""
    [ -r "$ICON_FONT" ] && FC_ICON=$(wmo_icon "$FC_CODE")
    if [ "$FC_DATE" = "$TODAY" ]; then
        FC_LABEL="Today's forecast"
    else
        FC_LABEL="Forecast for $(date -d "$FC_DATE" '+%a %-d %b' 2>/dev/null || echo "$FC_DATE")"
    fi
    log "Showing forecast for $FC_DATE: $COND, $TEMP"
}

### Due once a day: when the forecast we have was not fetched today and it
### is FORECAST_HOUR or later -- or straight away if we have none at all.
forecast_due() {
    [ -z "$FC_FIRST" ] && return 0
    [ "$FC_FIRST" != "$TODAY" ] && [ "${HOUR#0}" -ge "$FORECAST_HOUR" ]
}

### The screen always shows the kindle's own clock. This only nudges that
### clock back into line when the network is there anyway; the display never
### waits on it. Set USE_NTP=0 to leave the system clock completely alone.
sync_time() {
    [ "$USE_NTP" = "1" ] || return 0
    ntpdate -s pool.ntp.org
    log "Time synced. ($?)"
}

clear_screen(){
    $FBINK -f -c
    $FBINK -f -c
}

### Fall back to whatever this device exposes if a path above is wrong.
if [ ! -x "$FBINK_BIN" ]; then
    for CANDIDATE in /mnt/us/koreader/fbink /mnt/us/extensions/MRInstaller/bin/K5/fbink /mnt/us/extensions/kterm/bin/fbink /usr/bin/fbink; do
        if [ -x "$CANDIDATE" ]; then
            FBINK_BIN="$CANDIDATE"
            break
        fi
    done
fi
FBINK="$FBINK_BIN -q"

if [ ! -r "$BATTERY" ]; then
    BATTERY=$(ls /sys/class/power_supply/*/capacity 2>/dev/null | head -n 1)
fi
if [ ! -r "$BATTERY" ]; then
    BATTERY=$(find /sys -name battery_capacity 2>/dev/null | head -n 1)
fi

if [ ! -w "$BACKLIGHT" ]; then
    BACKLIGHT=$(ls /sys/class/backlight/*/brightness 2>/dev/null | head -n 1)
fi
if [ -z "$BACKLIGHT" ]; then
    BACKLIGHT="/dev/null"
fi

if [ ! -w "$FBROTATE_PATH" ]; then
    FBROTATE_PATH="/sys/class/graphics/fb0/rotate"
fi
if [ -w "$FBROTATE_PATH" ]; then
    FBROTATE="echo -n $ROTATE_VALUE > $FBROTATE_PATH"
else
    FBROTATE="true"
fi

if [ ! -r "${FONT#regular=}" ]; then
    for CANDIDATE in /usr/java/lib/fonts/Helvetica_LT_65_Medium.ttf /usr/java/lib/fonts/Palatino-Regular.ttf /usr/java/lib/fonts/Caecilia_LT_75_Bold.ttf; do
        if [ -r "$CANDIDATE" ]; then
            FONT="regular=$CANDIDATE"
            break
        fi
    done
fi

### Prep Kindle...
log "------------- Startup $VERSION ------------"
log "fbink=$FBINK_BIN battery=$BATTERY backlight=$BACKLIGHT sleep=$SLEEP_MODE"

$FBINK -w -c -f -m -M -t $FONT,size=20 "Starting Clock..." > /dev/null 2>&1


### stop processes that we don't need
#K4
#/etc/init.d/framework stop
#/etc/init.d/pmond stop
#/etc/init.d/phd stop
#/etc/init.d/cmd stop
#/etc/initd./tmd stop
#/etc/init.d/browserd stop
#/etc/init.d/webreaderd stop
#/etc/init.d/lipc-daemon stop
#/etc/init.d/powerd stop

#PW2/3/4
stop lab126_gui
stop otaupd
stop phd
stop tmd
stop x
stop todo
stop mcsd

sleep 2

### turn off 270 degree rotation of framebuffer device
eval $FBROTATE

### Ask fbink what we ended up with and scale the layout to it.
FBSTATE=$($FBINK_BIN -e 2>/dev/null)
SCREEN_W=$(echo "$FBSTATE" | sed -n 's/.*viewWidth=\([0-9][0-9]*\).*/\1/p')
SCREEN_H=$(echo "$FBSTATE" | sed -n 's/.*viewHeight=\([0-9][0-9]*\).*/\1/p')
[ -n "$SCREEN_W" ] || SCREEN_W=$REF_W
[ -n "$SCREEN_H" ] || SCREEN_H=$REF_H
log "screen ${SCREEN_W}x${SCREEN_H} ($FBSTATE)"

### Font sizes stay in points: fbink scales pt by the panel's dpi, so they
### already track the device. Only the pixel margins need scaling.
TIME_TOP=$((14 * SCREEN_H / REF_H))
DATE_TOP=$((580 * SCREEN_H / REF_H))
COND_TOP=$((721 * SCREEN_H / REF_H))
TEMP_TOP=$((849 * SCREEN_H / REF_H))
AGE_TOP=$((1000 * SCREEN_H / REF_H))
### Battery icon in the top right corner, the percentage to its left.
BAT_W=$((66 * SCREEN_W / REF_W))
BAT_H=$((30 * SCREEN_H / REF_H))
BAT_T=$((3 * SCREEN_W / REF_W)); [ "$BAT_T" -ge 2 ] || BAT_T=2
NUB_W=$((6 * SCREEN_W / REF_W))
NUB_H=$((13 * SCREEN_H / REF_H))
BAT_TOP=$((22 * SCREEN_H / REF_H))
BAT_X=$((SCREEN_W - 40 * SCREEN_W / REF_W - BAT_W))
BAT_GAP=$((14 * SCREEN_W / REF_W))
BAT_TEXT_TOP=$((12 * SCREEN_H / REF_H))
### wide enough for "100%" should fbink not tell us the real width
BAT_TEXT_W_FALLBACK=$((115 * SCREEN_W / REF_W))
BAT_MEASURED=""
WARN_LEFT=$((70 * SCREEN_W / REF_W))

### Set lowest cpu clock
for GOVERNOR in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo powersave > "$GOVERNOR" 2>/dev/null
done
### Disable Screensaver
lipc-set-prop com.lab126.powerd preventScreenSaver 1

clear_screen

### Battery: a small icon filled to the charge level, with the percentage
### right-aligned against it. fbink draws the shapes as filled rectangles
### (-k paints a region in the -B colour) and measures the text in its
### compute mode whenever the number changes, so "9%" and "100%" both end
### the same distance from the icon.
draw_battery() {
    case "$BAT" in
        ''|*[!0-9]*) return 0 ;;
    esac
    [ "$BAT" -le 100 ] || BAT=100

    if [ "$BAT" != "$BAT_MEASURED" ]; then
        BAT_MEASURED=$BAT
        BAT_TEXT_W=$($FBINK -l -t $FONT,size=10,top=0,bottom=0,left=0,right=0,compute "$BAT%" 2>/dev/null \
            | sed -n 's/.*bbox_width=\([0-9][0-9]*\).*/\1/p')
        [ -n "$BAT_TEXT_W" ] || BAT_TEXT_W=$BAT_TEXT_W_FALLBACK
    fi

    ### outline, hollow it out, charge level, terminal nub
    $FBINK -b -B BLACK -k top=$BAT_TOP,left=$BAT_X,width=$BAT_W,height=$BAT_H
    $FBINK -b -k top=$((BAT_TOP + BAT_T)),left=$((BAT_X + BAT_T)),width=$((BAT_W - 2 * BAT_T)),height=$((BAT_H - 2 * BAT_T))
    FILL=$(( (BAT_W - 4 * BAT_T) * BAT / 100 ))
    if [ "$FILL" -gt 0 ]; then
        $FBINK -b -B BLACK -k top=$((BAT_TOP + 2 * BAT_T)),left=$((BAT_X + 2 * BAT_T)),width=$FILL,height=$((BAT_H - 4 * BAT_T))
    fi
    $FBINK -b -B BLACK -k top=$((BAT_TOP + (BAT_H - NUB_H) / 2)),left=$((BAT_X + BAT_W)),width=$NUB_W,height=$NUB_H

    $FBINK -b -t $FONT,size=10,top=$BAT_TEXT_TOP,bottom=0,left=$((BAT_X - BAT_GAP - BAT_TEXT_W)),right=0 "$BAT%"
}

### The network runs in the background. The drawing loop only ever reads the
### file this leaves behind, so a slow connection, a hung DNS lookup or a
### dead network cannot delay the time on screen.
STATE_DIR="/tmp/pw11clock"
FETCH_PID=""
FETCH_STARTED=0

fetch_running() {
    [ -n "$FETCH_PID" ] && kill -0 "$FETCH_PID" 2>/dev/null
}

start_fetch() {
    FETCH_STARTED=$(date +%s)
    (
        if [ "$WIFI_MODE" = "daily" ]; then
            wifi_on
            WAITED=0
            while ! wifi_connected && [ "$WAITED" -lt 120 ]; do
                sleep 2
                WAITED=$((WAITED + 2))
            done
        fi
        if wifi_connected; then
            remember_ssid
            sync_time
            F=$(fetch_forecast)
            if [ -n "$F" ]; then
                printf '%s' "$F" > "$STATE_DIR/forecast.tmp" && mv "$STATE_DIR/forecast.tmp" "$STATE_DIR/forecast"
            fi
        else
            log "Wifi did not connect."
            : > "$STATE_DIR/nowifi"
        fi
        if [ "$WIFI_MODE" = "daily" ]; then
            wifi_off
        fi
    ) > /dev/null 2>&1 &
    FETCH_PID=$!
}

### Called after every draw; normally does nothing at all.
network_tick() {
    ### Pick up whatever a finished fetch left behind.
    if [ -f "$STATE_DIR/forecast" ]; then
        F=$(cat "$STATE_DIR/forecast")
        rm -f "$STATE_DIR/forecast"
        case "$(printf '%s\n' "$F" | forecast_rows | head -n 1)" in
            [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9],*)
                printf '%s' "$F" > "$FORECAST_CACHE"
                load_forecast "$F"
                NOWIFI=0
                log "Forecast updated."
                ;;
            *)
                log "Ignoring forecast response: $(printf '%s' "$F" | head -c 80 | tr '\n' ' ')"
                ;;
        esac
    fi
    if [ -f "$STATE_DIR/nowifi" ]; then
        rm -f "$STATE_DIR/nowifi"
        NOWIFI=1
    fi

    if fetch_running; then
        ### A fetch that has been going for 5 minutes is not coming back.
        if [ $(( $(date +%s) - FETCH_STARTED )) -gt 300 ]; then
            log "Fetch hung, killing it."
            kill "$FETCH_PID" 2>/dev/null
            [ "$WIFI_MODE" = "daily" ] && wifi_off
        fi
        return 0
    fi

    forecast_due || return 0
    ### while it is due, one attempt every 15 minutes
    [ $(( $(date +%s) - FETCH_STARTED )) -ge 900 ] || return 0
    if [ "$WIFI_MODE" = "leave" ] && ! wifi_connected; then
        NOWIFI=1
        return 0
    fi
    [ -r "$SSID_FILE" ] && WIFI_SSID=$(cat "$SSID_FILE")
    log "Fetching forecast in the background."
    start_fetch
}

### Arms a wake alarm $1 seconds out on every rtc that takes one. Fails if
### none could be armed, in which case we must not suspend at all.
arm_wakeup() {
    ARMED=1
    for W in /sys/class/rtc/rtc*/wakealarm; do
        [ -w "$W" ] || continue
        WAKE_ENABLE="${W%/wakealarm}/device/power/wakeup"
        [ -w "$WAKE_ENABLE" ] && echo enabled > "$WAKE_ENABLE" 2>/dev/null
        echo 0 > "$W" 2>/dev/null
        echo "+$1" > "$W" 2>/dev/null || continue
        [ -n "$(cat "$W" 2>/dev/null)" ] && ARMED=0
    done
    return $ARMED
}

### Waits until epoch $1.
sleep_until() {
    LEFT=$(($1 - $(date +%s)))
    ### Suspend only with a confirmed alarm and enough time for it: an alarm
    ### that is already in the past by the time we are asleep never fires.
    if [ "$SLEEP_MODE" = "suspend" ] && [ "$LEFT" -ge 10 ] && arm_wakeup "$LEFT"; then
        log "Suspending for ${LEFT}s"
        echo mem > /sys/power/state
    fi
    ### Whatever happened above -- awake mode, a suspend that failed straight
    ### away, or an early wake -- make up the rest with a plain sleep.
    LEFT=$(($1 - $(date +%s)))
    if [ "$LEFT" -gt 0 ]; then
        sleep "$LEFT"
    fi
    ### A sleep only overruns like this if the whole system was suspended
    ### underneath it; record when, by how much, and what powerd says.
    LATE=$(($(date +%s) - $1))
    if [ "$LATE" -ge 5 ]; then
        log "Woke ${LATE}s late (powerd $(lipc-get-prop com.lab126.powerd state 2>/dev/null))"
    fi
}

### Logs powerd and wifid events as they happen: screensaver, suspend and
### resume, charging, wifi state changes. Costs nothing while idle, the
### process just waits on lipc. Wifi signal strength updates are left out.
watch_events() {
    for PUBLISHER in com.lab126.powerd com.lab126.wifid; do
        lipc-wait-event -m -s 0 "$PUBLISHER" '*' 2>/dev/null | while read -r EV; do
            case "$EV" in
                signalStrength*) ;;
                *) log "event ${PUBLISHER#com.lab126.}: $EV" ;;
            esac
        done &
    done
}

### Once an hour: how busy the cpu was since the last report, and the three
### processes with the most cpu time so far. Something spinning in the
### background would eat the battery while the screen looks idle.
cpu_report() {
    STAT=$(awk '/^cpu / { t = 0; for (i = 2; i <= NF; i++) t += $i; print t, $5 + $6 }' /proc/stat)
    TOTAL=${STAT% *}; IDLE=${STAT#* }
    if [ -n "$CPU_TOTAL" ] && [ "$TOTAL" -gt "$CPU_TOTAL" ]; then
        BUSY=$(( (TOTAL - CPU_TOTAL - (IDLE - CPU_IDLE)) * 1000 / (TOTAL - CPU_TOTAL) ))
        TOPP=$(cat /proc/[0-9]*/stat 2>/dev/null | awk '{
                name = $0; sub(/^[0-9]+ \(/, "", name); sub(/\) .*/, "", name)
                rest = $0; sub(/.*\) /, "", rest); split(rest, a, " ")
                print a[12] + a[13], name }' | sort -rn | head -n 3 \
            | awk '{ printf "%s %ds, ", $2, $1 / 100 }')
        log "cpu busy $((BUSY / 10)).$((BUSY % 10))% last hour; most cpu: ${TOPP%, }"
    fi
    CPU_TOTAL=$TOTAL; CPU_IDLE=$IDLE
}

mkdir -p "$STATE_DIR"
rm -f "$STATE_DIR/forecast" "$STATE_DIR/forecast.tmp" "$STATE_DIR/nowifi"
watch_events
CPU_TOTAL=""
cpu_report
NOWIFI=0
FLASHED=""
FC_CSV=""
FC_FIRST=""
FC_SHOWN=""
[ -r "$FORECAST_CACHE" ] && load_forecast "$(cat "$FORECAST_CACHE")"
WIFI_SSID=""
[ -r "$SSID_FILE" ] && WIFI_SSID=$(cat "$SSID_FILE")
wifi_connected && remember_ssid
log "wifi=$WIFI_MODE ssid='$WIFI_SSID' forecast from ${FC_FIRST:-none}"
### In daily mode wifi has no business being on until the next fetch.
TODAY=$(date +%Y-%m-%d)
HOUR=$(date +%H)
if [ "$WIFI_MODE" = "daily" ] && ! forecast_due; then
    wifi_off
fi

while true; do
    ### Draw FIRST, straight after waking. Nothing may run before this.
    ### One date call, so the time drawn and the time we plan from agree.
    NOWSTR=$(date '+%s|%M|%H|%Y-%m-%d|%H:%M|%A, %-d. %B %Y')
    DRAWN_AT=${NOWSTR%%|*}; NOWSTR=${NOWSTR#*|}
    MINUTE=${NOWSTR%%|*};   NOWSTR=${NOWSTR#*|}
    HOUR=${NOWSTR%%|*};     NOWSTR=${NOWSTR#*|}
    TODAY=${NOWSTR%%|*};    NOWSTR=${NOWSTR#*|}
    TIME=${NOWSTR%%|*}
    DATE=${NOWSTR#*|}

    ### Once a day, or right after new data: choose what to show. Local work
    ### only, a few milliseconds.
    if [ "$FC_SHOWN" != "$TODAY" ] && [ -n "$FC_CSV" ]; then
        select_forecast
        FC_SHOWN=$TODAY
    fi

    ### Once an hour, flash the refresh to clear e-ink ghosting.
    FLASH=""
    if [ "$MINUTE" = "00" ] && [ "$FLASHED" != "$TODAY$HOUR" ]; then
        FLASHED=$TODAY$HOUR
        FLASH="-f"
    fi

    #BAT=$(gasgauge-info -s)
    BAT="?"
    if [ -r "$BATTERY" ]; then
        BAT=$(cat $BATTERY)
    fi

    ## coordinates are scaled from a PW4 landscape canvas (1448x1072)
    $FBINK -b -c -m -t $FONT,size=150,top=$TIME_TOP,bottom=0,left=0,right=0 "$TIME"
    $FBINK -b -m -t $FONT,size=20,top=$DATE_TOP,bottom=0,left=0,right=0 "$DATE"
    draw_battery
    $FBINK -b -m -t $FONT,size=20,top=$COND_TOP,bottom=0,left=0,right=0 "$COND"
    if [ -n "$FC_ICON" ]; then
        ### The icon font goes in as the "bold" face, so **...** switches to it
        ### mid-line and fbink still centres icon + temperatures as one line.
        $FBINK -b -m -t $FONT,bold=$ICON_FONT,size=30,top=$TEMP_TOP,bottom=0,left=0,right=0,format "**$FC_ICON**  $TEMP"
    else
        $FBINK -b -m -t $FONT,size=30,top=$TEMP_TOP,bottom=0,left=0,right=0 "$TEMP"
    fi
    if [ -n "$FC_LABEL" ]; then
        $FBINK -b -m -t $FONT,size=10,top=$AGE_TOP,bottom=0,left=0,right=0 "$FC_LABEL"
    fi
    if [ "$NOWIFI" = "1" ]; then
        $FBINK -b -t $FONT,size=10,top=0,bottom=0,left=$WARN_LEFT,right=0 "No Wifi!"
    fi
    ### update framebuffer
    $FBINK -w -s $FLASH

    ### Everything below happens with the right time already on screen.
    echo -n 0 > $BACKLIGHT
    ### powerd can drop this across power state changes; keep it set
    lipc-set-prop com.lab126.powerd preventScreenSaver 1
    ### Once an hour is plenty to follow the battery and to see that the
    ### clock is alive; wifi and forecast events are logged as they happen.
    if [ "$MINUTE" = "00" ]; then
        log "Drew $TIME (bat $BAT, powerd $(lipc-get-prop com.lab126.powerd state 2>/dev/null))"
        cpu_report
        rotate_log
    fi
    network_tick

    ### If any of that ran into the next minute, draw that minute now
    ### rather than sleeping through it.
    NOW=$(date +%s)
    if [ $((NOW / 60)) -ne $((DRAWN_AT / 60)) ]; then
        log "Ran past the minute, redrawing now."
        continue
    fi
    sleep_until $(( (NOW / 60 + 1) * 60 ))
done
