#!/bin/sh

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
CITY="Istanbul"
USE_NTP=1

### How to wait between minutes.
###   awake    stay awake and sleep. Keeps exact time; costs battery, which
###            does not matter while the kindle is on its charger.
###   suspend  suspend to RAM with an rtc alarm. Battery friendly, but on a
###            kindle the rtc alarm belongs to the system's powerd, and on a
###            PW4 the clock has been seen to stop waking up. Experimental.
SLEEP_MODE="awake"
COND="---"
TEMP="---"
WX_SYM=""
WX_AT=""
SUNRISE=""
SUNSET=""

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


### Updates weather info. One request fetches everything:
###   %x  condition as a plain ascii symbol -- language independent, picks the icon
###   %S  sunrise, %s sunset -- to choose day or night icons
###   %C  condition text, %t temperature
WX_FORMAT="%x+%S+%s+%C,+%t"
update_weather() {
    WEATHER=$(curl -s -f -m 5 "https://wttr.in/$CITY?format=$WX_FORMAT")
    RC=$?
    ### old kindle CA bundles can fail TLS; plain http still works on wttr.in
    if [ -z "$WEATHER" ]; then
        WEATHER=$(curl -s -f -m 5 "http://wttr.in/$CITY?format=$WX_FORMAT")
        RC=$?
    fi
    log "Got weather data. ($WEATHER, RC=$RC)"

    ### Split with parameter expansion only: %x can be "*" or "**", which an
    ### unquoted word split would glob against the current directory.
    W_REST="$WEATHER"
    W_SYM="${W_REST%% *}";  W_REST="${W_REST#* }"
    W_RISE="${W_REST%% *}"; W_REST="${W_REST#* }"
    W_SET="${W_REST%% *}";  W_REST="${W_REST#* }"

    ### wttr.in answers some failures with a 200 and a sentence of text.
    ### Only take the data if the sunrise field looks like a time.
    case "$W_RISE" in
        [0-9?][0-9?]:[0-9?][0-9?]*) ;;
        *)
            log "Ignoring weather response."
            return 1
            ;;
    esac

    WX_SYM="$W_SYM"
    SUNRISE="$W_RISE"
    SUNSET="$W_SET"
    COND="${W_REST%,*}"
    TEMP=$(echo "${W_REST##*,}" | sed 's/^ *//; s/+//')
    WX_AT=$(date +%s)
    log "Processed weather data. ($WX_SYM // $TEMP // $COND // $SUNRISE-$SUNSET)"
}

### Minutes since midnight for an HH:MM[:SS] string; fails if it isn't one.
to_minutes() {
    case "$1" in
        [0-2][0-9]:[0-5][0-9]*) ;;
        *) return 1 ;;
    esac
    TM_H=${1%%:*}; TM_M=${1#*:}; TM_M=${TM_M%%:*}
    ### strip one leading zero so $(( )) does not read "08" as octal
    TM_H=${TM_H#0}; TM_M=${TM_M#0}
    echo $(( ${TM_H:-0} * 60 + ${TM_M:-0} ))
}

### True between sunset and sunrise, using wttr.in's times for the city and
### 07:00 / 19:00 if it did not give any.
is_night() {
    NOW_M=$(to_minutes "$(date '+%H:%M')") || return 1
    RISE_M=$(to_minutes "$SUNRISE") || RISE_M=420
    SET_M=$(to_minutes "$SUNSET") || SET_M=1140
    [ "$NOW_M" -lt "$RISE_M" ] || [ "$NOW_M" -ge "$SET_M" ]
}

### Prints the Weather Icons glyph for the current %x symbol. Codepoints are
### from erikflowers/weather-icons (values/weathericons.xml), written as the
### utf-8 octal bytes printf understands.
weather_icon() {
    if is_night; then N=1; else N=0; fi
    case "$WX_SYM" in
        o)        [ $N = 1 ] && G='\357\200\256' || G='\357\200\215' ;; # night-clear / day-sunny
        m)        [ $N = 1 ] && G='\357\202\206' || G='\357\200\202' ;; # night-alt-cloudy / day-cloudy
        mm|mmm)   G='\357\200\223' ;;                                   # cloudy
        =)        G='\357\200\224' ;;                                   # fog
        .)        [ $N = 1 ] && G='\357\200\251' || G='\357\200\211' ;; # night-alt-showers / day-showers
        /)        G='\357\200\234' ;;                                   # sprinkle
        //)       G='\357\200\232' ;;                                   # showers
        ///)      G='\357\200\231' ;;                                   # rain
        x|x/)     G='\357\202\265' ;;                                   # sleet
        \*|\*\*)  G='\357\200\233' ;;                                   # snow
        \*/|\*/\*) [ $N = 1 ] && G='\357\200\252' || G='\357\200\212' ;; # night-alt-snow / day-snow
        !/)       [ $N = 1 ] && G='\357\200\254' || G='\357\200\216' ;; # night-alt-storm-showers / day-storm-showers
        /!/)      G='\357\200\236' ;;                                   # thunderstorm
        \*!\*)    [ $N = 1 ] && G='\357\201\255' || G='\357\201\253' ;; # night-alt-/day-snow-thunderstorm
        *)        return 1 ;;
    esac
    printf "$G"
}

### "Updated 12 min ago", so a stale forecast is obvious at a glance.
weather_age() {
    [ -n "$WX_AT" ] || return 1
    AGE=$(( ($(date +%s) - WX_AT) / 60 ))
    [ "$AGE" -ge 0 ] || AGE=0
    if [ "$AGE" -lt 1 ]; then
        echo "Updated just now"
    elif [ "$AGE" -lt 60 ]; then
        echo "Updated $AGE min ago"
    else
        echo "Updated $((AGE / 60)) h ago"
    fi
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
log "------------- Startup ------------"
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
BAT_LEFT=$((1248 * SCREEN_W / REF_W))
WARN_LEFT=$((70 * SCREEN_W / REF_W))

### Set lowest cpu clock
echo powersave > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
### Disable Screensaver
lipc-set-prop com.lab126.powerd preventScreenSaver 1

clear_screen

### Brings wifi up and, once connected, syncs time and weather. Never waits
### past second 50 of the current minute, so the next minute is always drawn
### on time: if wifi is not there yet it is left enabled and tried again the
### next minute, up to NET_MAX_TRIES times, before giving up until the hour.
NET_MAX_TRIES=5
network_step() {
    ### only when off: re-sending it could restart a connection in progress
    if [ "$(lipc-get-prop com.lab126.cmd wirelessEnable 2>/dev/null)" != "1" ]; then
        lipc-set-prop com.lab126.cmd wirelessEnable 1
    fi
    while ! wifi_connected; do
        SEC=$(date +%S); SEC=${SEC#0}
        [ "${SEC:-0}" -lt 50 ] || break
        WIFISTATE=$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)
        log "Waiting for wifi ($WIFISTATE)"
        ### stuck in READY means we have to reconnect ourselves
        if [ "$WIFISTATE" = "READY" ]; then
            /usr/bin/wpa_cli -i wlan0 reconnect > /dev/null 2>&1
        fi
        sleep 1
    done

    SEC=$(date +%S); SEC=${SEC#0}
    if wifi_connected && [ "${SEC:-0}" -ge 30 ]; then
        ### ntpdate and curl can take a while; starting them this late would
        ### run into the next minute. Stay connected and do it then instead.
        log "Wifi up late in the minute, fetching next minute."
    elif wifi_connected; then
        NOWIFI=0
        NET_DUE=0
        sync_time
        update_weather
    else
        NET_TRIES=$((NET_TRIES + 1))
        log "No wifi yet (attempt $NET_TRIES of $NET_MAX_TRIES)"
        if [ "$NET_TRIES" -ge "$NET_MAX_TRIES" ]; then
            NOWIFI=1
            NET_DUE=0
        fi
    fi

    ### wifi off again once we are done with it for this hour
    if [ "$NET_DUE" = "0" ]; then
        lipc-set-prop com.lab126.cmd wirelessEnable 0
    fi
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
}

NOWIFI=0
NET_DUE=1
NET_TRIES=0
NET_HOUR=""

while true; do
    rotate_log
    ### powerd can drop this across wifi and power state changes; keep it set
    lipc-set-prop com.lab126.powerd preventScreenSaver 1
    ### Backlight off
    echo -n 0 > $BACKLIGHT

    ### One date call, so the time drawn and the time we plan from agree.
    NOWSTR=$(date '+%s|%M|%Y%m%d%H|%H:%M|%A, %-d. %B %Y')
    DRAWN_AT=${NOWSTR%%|*};  NOWSTR=${NOWSTR#*|}
    MINUTE=${NOWSTR%%|*};    NOWSTR=${NOWSTR#*|}
    HOUR_KEY=${NOWSTR%%|*};  NOWSTR=${NOWSTR#*|}
    TIME=${NOWSTR%%|*}
    DATE=${NOWSTR#*|}

    ### Once an hour: clear out e-ink ghosting and schedule a network update.
    if [ "$MINUTE" = "00" ] && [ "$HOUR_KEY" != "$NET_HOUR" ]; then
        NET_HOUR=$HOUR_KEY
        NET_DUE=1
        NET_TRIES=0
        clear_screen
    fi

    ### Draw FIRST. Nothing below this point may delay what is on screen.
    #BAT=$(gasgauge-info -s)
    BAT="?"
    if [ -r "$BATTERY" ]; then
        BAT=$(cat $BATTERY)
    fi

    ## coordinates are scaled from a PW4 landscape canvas (1448x1072)
    $FBINK -b -c -m -t $FONT,size=150,top=$TIME_TOP,bottom=0,left=0,right=0 "$TIME"
    $FBINK -b -m -t $FONT,size=20,top=$DATE_TOP,bottom=0,left=0,right=0 "$DATE"
    $FBINK -b    -t $FONT,size=10,top=0,bottom=0,left=$BAT_LEFT,right=0 "Bat: $BAT"
    $FBINK -b -m -t $FONT,size=20,top=$COND_TOP,bottom=0,left=0,right=0 "$COND"
    ICON=""
    if [ -r "$ICON_FONT" ]; then
        ICON=$(weather_icon)
    fi
    if [ -n "$ICON" ]; then
        ### The icon font goes in as the "bold" face, so **...** switches to it
        ### mid-line and fbink still centres icon + temperature as one line.
        $FBINK -b -m -t $FONT,bold=$ICON_FONT,size=30,top=$TEMP_TOP,bottom=0,left=0,right=0,format "**$ICON**  $TEMP"
    else
        $FBINK -b -m -t $FONT,size=30,top=$TEMP_TOP,bottom=0,left=0,right=0 "$TEMP"
    fi
    if AGE_TEXT=$(weather_age); then
        $FBINK -b -m -t $FONT,size=10,top=$AGE_TOP,bottom=0,left=0,right=0 "$AGE_TEXT"
    fi
    if [ "$NOWIFI" = "1" ]; then
        $FBINK -b -t $FONT,size=10,top=0,bottom=0,left=$WARN_LEFT,right=0 "No Wifi!"
    fi
    ### update framebuffer
    $FBINK -w -s

    log "Drew $TIME (bat $BAT, powerd $(lipc-get-prop com.lab126.powerd state 2>/dev/null))"

    ### Screen is current now, so the network can take its time.
    if [ "$NET_DUE" = "1" ]; then
        network_step
    fi

    ### If the work above ran into the next minute, draw that minute now
    ### rather than sleeping through it.
    NOW=$(date +%s)
    if [ $((NOW / 60)) -ne $((DRAWN_AT / 60)) ]; then
        log "Ran past the minute, redrawing now."
        continue
    fi
    sleep_until $(( (NOW / 60 + 1) * 60 ))
done
