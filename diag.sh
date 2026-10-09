#!/bin/sh
#
# One-screen health report for pw11clock. On the kindle, in kTerm:
#     cd /mnt/us && sh d.sh
# and take a photo of the output.
#
# Everything comes from the clock's own log, for its latest run only (the
# battery may have been charged between runs), plus a live check of wifi
# and of the forecast server.

DIR="${DIR:-/mnt/us/extensions/clock}"
LOG="${LOG:-/mnt/us/clock.log}"
RUN="/tmp/pw11clock-diag.log"
URL="api.open-meteo.com/v1/forecast?latitude=41.01&longitude=28.98&daily=weather_code&forecast_days=1&format=csv"

echo "== pw11clock $(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$DIR/kindle-clock.sh" 2>/dev/null)   now $(date '+%d.%m %H:%M')"

if [ -r "$LOG" ]; then
    awk '/-- Startup/ { n = 0 } { l[n++] = $0 } END { for (i = 0; i < n; i++) print l[i] }' "$LOG" > "$RUN"
    echo "run started: $(head -n 1 "$RUN" | cut -c1-16 | tr _ ' ')"

    ### battery: first and last hourly heartbeat of this run
    FIRST=$(grep 'Drew .*(bat [0-9]' "$RUN" | head -n 1)
    LAST=$(grep 'Drew .*(bat [0-9]' "$RUN" | tail -n 1)
    if [ -n "$FIRST" ] && [ "$FIRST" != "$LAST" ]; then
        T1=$(date -d "$(echo "$FIRST" | cut -c1-19 | tr _ ' ')" +%s)
        T2=$(date -d "$(echo "$LAST" | cut -c1-19 | tr _ ' ')" +%s)
        B1=$(echo "$FIRST" | sed -n 's/.*(bat \([0-9]*\).*/\1/p')
        B2=$(echo "$LAST" | sed -n 's/.*(bat \([0-9]*\).*/\1/p')
        awk -v t="$((T2 - T1))" -v b1="$B1" -v b2="$B2" 'BEGIN {
            h = t / 3600; r = (b1 - b2) / h
            printf "battery: %d%% -> %d%% in %.1f h = %.2f %%/h", b1, b2, h, r
            if (r > 0) printf " (full: %.1f days)", 100 / r / 24
            printf "\n" }'
    else
        echo "battery: not enough heartbeats yet (one per hour)"
    fi

    ### missed minutes
    LATE_N=$(grep -c 'Woke .*s late' "$RUN")
    LATE_MAX=$(sed -n 's/.*Woke \([0-9]*\)s late.*/\1/p' "$RUN" | sort -n | tail -n 1)
    echo "late wakes: $LATE_N (worst ${LATE_MAX:-0}s), ran past a minute: $(grep -c 'Ran past' "$RUN")"
    grep 'Woke .*s late' "$RUN" | tail -n 2 | cut -c12-

    ### what powerd did, as event counts
    EV=$(grep 'event powerd:' "$RUN" | sed 's/.*event powerd: //' | awk '{ print $1 }' | sort | uniq -c | awk '{ printf "%s=%s ", $2, $1 }')
    echo "powerd events: ${EV:-none}"
    grep 'cpu busy' "$RUN" | tail -n 1 | cut -c12-

    ### forecast and wifi
    grep -E 'Got forecast|Ignoring forecast|Wifi did not|Forecast updated|Fetch hung' "$RUN" | tail -n 3 | cut -c12-
    grep 'event wifid:' "$RUN" | tail -n 3 | cut -c12-
else
    echo "no log at $LOG"
fi

### live: wifi state, then the forecast server over each way the clock tries
echo "wifi now: $(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)," \
     "wifid enable=$(lipc-get-prop com.lab126.wifid enable 2>/dev/null)," \
     "airplane-off=$(lipc-get-prop com.lab126.cmd wirelessEnable 2>/dev/null)"
if [ "$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)" != "CONNECTED" ]; then
    lipc-set-prop -i com.lab126.wifid enable 1 2>/dev/null
    [ -r "$DIR/wifi_ssid" ] && lipc-set-prop -s com.lab126.cmd ensureConnection "wifi:$(cat "$DIR/wifi_ssid")" 2>/dev/null
    W=0
    while [ "$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)" != "CONNECTED" ] && [ "$W" -lt 60 ]; do
        sleep 2; W=$((W + 2))
    done
    echo "wifi after ${W}s: $(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)"
fi
for MODE in https https-k http; do
    case "$MODE" in
        https)   OUT=$(curl -s -f -m 15 "https://$URL" 2>&1) ;;
        https-k) OUT=$(curl -s -f -k -m 15 "https://$URL" 2>&1) ;;
        http)    OUT=$(curl -s -f -m 15 "http://$URL" 2>&1) ;;
    esac
    RC=$?
    ROW=$(printf '%s\n' "$OUT" | awk -F, 'f && NF > 1 { print; exit } /^time,/ { f = 1 }')
    echo "open-meteo $MODE: rc=$RC ${ROW:-(no data)}"
done
rm -f "$RUN"
