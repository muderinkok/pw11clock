#!/bin/sh

PWD=$(pwd)
#LOG="/mnt/us/clock.log"
LOG="/dev/null"
FBINK="/mnt/us/koreader/fbink -q"
FONT="regular=/usr/java/lib/fonts/Helvetica_LT_65_Medium.ttf"
#FONT="regular=/usr/java/lib/fonts/Caecilia_LT_75_Bold.ttf"
CITY="Istanbul"
COND="---"
TEMP="---"

### uncomment/adjust according to your hardware
#K4NT
#FBROTATE=" echo 14 2 > /proc/eink_fb/update_display"
#BACKLIGHT="/dev/null"
#BATTERY="/sys/devices/system/yoshi_battery/yoshi_battery0/battery_capacity"
#TEMP_SENSOR="/sys/devices/virtual/i2c-adapter/i2c-1/1-0048/papyrus_temperature"

#PW3
#FBROTATE="echo 0 > /sys/devices/platform/imx_epdc_fb/graphics/fb0/rotate"
#BACKLIGHT="/sys/devices/platform/imx-i2c.0/i2c-0/0-003c/max77696-bl.0/backlight/max77696-bl/brightness"
#BATTERY="/sys/devices/system/wario_battery/wario_battery0/battery_capacity"
#TEMP_SENSOR="/sys/devices/virtual/i2c-adapter/i2c-1/1-0068/papyrus_temperature"

#PW2
FBROTATE="echo -n 0 > /sys/devices/platform/mxc_epdc_fb/graphics/fb0/rotate"
BACKLIGHT="/sys/devices/system/fl_tps6116x/fl_tps6116x0/fl_intensity"
BATTERY="/sys/devices/system/yoshi_battery/yoshi_battery0/battery_capacity"
TEMP_SENSOR="/sys/devices/virtual/i2c-adapter/i2c-1/1-0068/papyrus_temperature"

### PW4/PW5 (and anything else): the hardcoded paths above only exist on a PW2.
### Rather than guessing, fall back to whatever this device actually exposes.
if [ ! -r "$BATTERY" ]; then
    BATTERY=$(find /sys -name battery_capacity 2>/dev/null | head -n 1)
fi
if [ ! -r "$TEMP_SENSOR" ]; then
    TEMP_SENSOR=$(find /sys/devices -name 'papyrus_temperature' 2>/dev/null | head -n 1)
fi
if [ ! -r "$TEMP_SENSOR" ]; then
    TEMP_SENSOR=$(find /sys/devices -name '*_temperature' 2>/dev/null | head -n 1)
fi
if [ ! -w "$BACKLIGHT" ]; then
    BACKLIGHT=$(ls /sys/class/backlight/*/brightness 2>/dev/null | head -n 1)
fi
if [ -z "$BACKLIGHT" ]; then
    BACKLIGHT="/dev/null"
fi
if [ ! -w "/sys/devices/platform/mxc_epdc_fb/graphics/fb0/rotate" ]; then
    if [ -w "/sys/class/graphics/fb0/rotate" ]; then
        FBROTATE="echo -n 0 > /sys/class/graphics/fb0/rotate"
    else
        FBROTATE="true"
    fi
fi

### fbink lives in different places depending on what is installed
if [ ! -x "${FBINK%% *}" ]; then
    for CANDIDATE in /mnt/us/koreader/fbink /mnt/us/extensions/MRInstaller/bin/K5/fbink /mnt/us/extensions/kterm/bin/fbink /usr/bin/fbink; do
        if [ -x "$CANDIDATE" ]; then
            FBINK="$CANDIDATE -q"
            break
        fi
    done
fi

### fall back to a font that exists if the preferred one is missing
if [ ! -r "${FONT#regular=}" ]; then
    for CANDIDATE in /usr/java/lib/fonts/Helvetica_LT_65_Medium.ttf /usr/java/lib/fonts/Palatino-Regular.ttf /usr/java/lib/fonts/Caecilia_LT_75_Bold.ttf; do
        if [ -r "$CANDIDATE" ]; then
            FONT="regular=$CANDIDATE"
            break
        fi
    done
fi

### rtc device used for the wakeup timer
RTC="/dev/rtc1"
if [ ! -e "$RTC" ]; then
    RTC="/dev/rtc0"
fi

wait_for_wifi() {
  return `lipc-get-prop com.lab126.wifid cmState | grep -e "CONNECTED" | wc -l`
}


### Updates weather info
update_weather() {
    WEATHER=$(curl -s -f -m 5 https://wttr.in/$CITY?format="%C,+%t" )
    ### old kindle CA bundles can fail TLS; plain http still works on wttr.in
    if [ -z "$WEATHER" ]; then
        WEATHER=$(curl -s -f -m 5 http://wttr.in/$CITY?format="%C,+%t" )
    fi
#     WEATHER=$(curl -v -s -f -m 5 https://wttr.in/$CITY?format="%C,+%t" 2>> $LOG)
    RC=$?
    echo "`date '+%Y-%m-%d_%H:%M:%S'`: Got weather data. ($WEATHER, RC=$RC)" >> $LOG
    if [ ! -z "$WEATHER" ]; then
        COND=${WEATHER%,*}
        TEMP=$(echo ${WEATHER##*,} | sed s/+//)
        echo "`date '+%Y-%m-%d_%H:%M:%S'`: Processed weather data. ($TEMP // $COND)" >> $LOG
    fi
}

clear_screen(){
    $FBINK -f -c
    $FBINK -f -c
}

### Prep Kindle...
echo "`date '+%Y-%m-%d_%H:%M:%S'`: ------------- Startup ------------" >> $LOG

### No way of running this if wifi is down.
if [ `lipc-get-prop com.lab126.wifid cmState` != "CONNECTED" ]; then
	exit 1
fi

$FBINK -w -c -f -m -t $FONT,size=20,top=410,bottom=0,left=0,right=0 "Starting Clock..." > /dev/null 2>&1


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

#PW2/3
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

### Set lowest cpu clock
echo powersave > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
### Disable Screensaver
lipc-set-prop com.lab126.powerd preventScreenSaver 1

### set time/weather as we start up
ntpdate -s pool.ntp.org
update_weather
clear_screen

while true; do
    echo "`date '+%Y-%m-%d_%H:%M:%S'`: Top of loop (awake!)." >> $LOG
    ### Backlight off
    echo -n 0 > $BACKLIGHT

    ### Get weather data and set time via ntpdate every hour
    MINUTE=`date "+%M"`
    if [ "$MINUTE" = "00" ]; then
        echo "`date '+%Y-%m-%d_%H:%M:%S'`: Enabling Wifi" >> $LOG
        ### Enable WIFI, disable wifi first in order to have a defined state
    	lipc-set-prop com.lab126.cmd wirelessEnable 1
        TRYCNT=0
        NOWIFI=0
        ### Wait for wifi to come up
    	while wait_for_wifi; do
            if [ ${TRYCNT} -gt 30 ]; then
                ### waited long enough
                echo "`date '+%Y-%m-%d_%H:%M:%S'`: No Wifi... ($TRYCNT)" >> $LOG
                NOWIFI=1
                break
            fi
            WIFISTATE=$(lipc-get-prop com.lab126.wifid cmState)
            echo "`date '+%Y-%m-%d_%H:%M:%S'`: Waiting for Wifi... (try $TRYCNT: $WIFISTATE)" >> $LOG
            ### Are we stuck in READY state?
            if [ "$WIFISTATE" = "READY" ]; then
                ### we have to reconnect
                echo "`date '+%Y-%m-%d_%H:%M:%S'`: Reconnecting to Wifi..." >> $LOG
                /usr/bin/wpa_cli -i wlan0 reconnect

                ### Could also be that kindle forgot the wpa ssid/psk combo
                #if [ wpa_cli status | grep INACTIVE | wc -l ]; then...
            fi
    	    sleep 1
            let TRYCNT=$TRYCNT+1
    	done
        echo "`date '+%Y-%m-%d_%H:%M:%S'`: wifi: `lipc-get-prop com.lab126.wifid cmState`" >> $LOG
        echo "`date '+%Y-%m-%d_%H:%M:%S'`: wifi: `wpa_cli status`" >> $LOG

        if [ `lipc-get-prop com.lab126.wifid cmState` = "CONNECTED" ]; then
            ### Finally, set time
            echo "`date '+%Y-%m-%d_%H:%M:%S'`: Setting time..." >> $LOG
            ntpdate -s pool.ntp.org
            RC=$?
            echo "`date '+%Y-%m-%d_%H:%M:%S'`: Time set. ($RC)" >> $LOG
            update_weather
        fi

        clear_screen
    fi

    ### Disable WIFI
    lipc-set-prop com.lab126.cmd wirelessEnable 0

    #BAT=$(gasgauge-info -s)
    BAT="?"
    if [ -r "$BATTERY" ]; then
        BAT=$(cat $BATTERY)
    fi
    TIME=$(date '+%H:%M')
    DATE=$(date '+%A, %-d. %B %Y')
    INSIDE_TEMP_C=""
    if [ -r "$TEMP_SENSOR" ]; then
        INSIDE_TEMP_C=$(cat $TEMP_SENSOR)
    fi
    # convert to centigrade
    #let INSIDE_TEMP_C="($INSIDE_TEMP_F-32)*5/9"

    ## adjust coordinates according to display resolution. This is for PW2.
    $FBINK -b -c -m -t $FONT,size=150,top=10,bottom=0,left=0,right=0 "$TIME"
    $FBINK -b -m -t $FONT,size=20,top=410,bottom=0,left=0,right=0 "$DATE"
    $FBINK -b    -t $FONT,size=10,top=0,bottom=0,left=900,right=0 "Bat: $BAT"
    $FBINK -b -m -t $FONT,size=20,top=510,bottom=0,left=0,right=0 "$COND"
    if [ -n "$INSIDE_TEMP_C" ]; then
        $FBINK -b -m -t $FONT,size=30,top=600,bottom=0,left=0,right=0 "$TEMP | $INSIDE_TEMP_C°C"
    else
        $FBINK -b -m -t $FONT,size=30,top=600,bottom=0,left=0,right=0 "$TEMP"
    fi
    if [ "$NOWIFI" = "1" ]; then
        $FBINK -b -t $FONT,size=10,top=0,bottom=0,left=50,right=0 "No Wifi!"
    fi
    ### update framebuffer
    $FBINK -w -s

    echo "`date '+%Y-%m-%d_%H:%M:%S'`: Battery: $BAT" >> $LOG

    ### Set Wakeuptimer
	#echo 0 > /sys/class/rtc/rtc1/wakealarm
	#echo ${WAKEUP_TIME} > /sys/class/rtc/rtc1/wakealarm
    NOW=$(date +%s)
    let WAKEUP_TIME="((($NOW + 59)/60)*60)" # Hack to get next minute
    let SLEEP_SECS=$WAKEUP_TIME-$NOW

    ### Prevent SLEEP_SECS from being negative or just too small
    ### if we took too long
    if [ $SLEEP_SECS -lt 5 ]; then
        let SLEEP_SECS=$SLEEP_SECS+60
    fi
    rtcwake -d $RTC -m no -s $SLEEP_SECS
    echo "`date '+%Y-%m-%d_%H:%M:%S'`: Going to sleep for $SLEEP_SECS" >> $LOG
	### Go into Suspend to Memory (STR)
	echo "mem" > /sys/power/state
#    exit
done
