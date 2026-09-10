#!/bin/sh
#
# One-line installer for pw11clock.
#
# On the kindle (kTerm / ssh):
#     cd /mnt/us
#     curl -L -o i.sh <url-to-this-file>
#     sh i.sh
#
# Options:
#     sh i.sh -y        install and start without asking
#     sh i.sh -n        install only, do not start
#     sh i.sh --probe   only print the hardware paths this device exposes
#
# Override the source with env vars, e.g.:
#     REF=main sh i.sh
#

REPO="${REPO:-muderinkok/pw11clock}"
REF="${REF:-claude/kindle-clock-setup-d39f1z}"
BASEURL="${BASEURL:-https://raw.githubusercontent.com/$REPO/refs/heads/$REF}"
DEST="${DEST:-/mnt/us/extensions/clock}"
FILES="kindle-clock.sh config.xml menu.json"

AUTORUN="ask"

for ARG in "$@"; do
    case "$ARG" in
        -y|--yes)   AUTORUN="yes" ;;
        -n|--no-run) AUTORUN="no" ;;
        --probe)    AUTORUN="probe" ;;
        *) echo "unknown option: $ARG"; exit 2 ;;
    esac
done

### Print what this device actually exposes. Useful to get the right paths
### for a device the upstream script does not know about.
probe() {
    echo "--- pw11clock hardware probe ---"
    echo "model:      `cat /proc/usid 2>/dev/null` `cat /etc/prettyversion.txt 2>/dev/null`"
    echo "battery:    `find /sys -name battery_capacity 2>/dev/null | tr '\n' ' '`"
    echo "temp:       `find /sys/devices -name '*_temperature' 2>/dev/null | tr '\n' ' '`"
    echo "backlight:  `ls /sys/class/backlight/*/brightness 2>/dev/null | tr '\n' ' '`"
    echo "fb rotate:  `ls /sys/class/graphics/fb0/rotate /sys/devices/platform/*_fb*/graphics/fb0/rotate 2>/dev/null | tr '\n' ' '`"
    echo "rtc:        `ls /dev/rtc* 2>/dev/null | tr '\n' ' '`"
    echo "fbink:      `ls /mnt/us/koreader/fbink /mnt/us/extensions/MRInstaller/bin/K5/fbink /mnt/us/extensions/kterm/bin/fbink /usr/bin/fbink 2>/dev/null | tr '\n' ' '`"
    echo "fonts:      `ls /usr/java/lib/fonts/ 2>/dev/null | tr '\n' ' '`"
    echo "screen:     `cat /sys/class/graphics/fb0/virtual_size 2>/dev/null`"
    echo "--- end of probe ---"
}

if [ "$AUTORUN" = "probe" ]; then
    probe
    exit 0
fi

### Download one file, trying the tools this kindle might have.
fetch() {
    URL="$1"
    OUT="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -L -s -f -o "$OUT" "$URL" && return 0
        ### Kindle firmware ships a stale CA bundle; retry without verification
        ### rather than failing the install outright.
        echo "  warning: TLS verification failed, retrying without it"
        curl -L -s -f -k -o "$OUT" "$URL" && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$OUT" "$URL" && return 0
        wget -q --no-check-certificate -O "$OUT" "$URL" && return 0
    fi
    return 1
}

echo "pw11clock installer"
echo "  source: $BASEURL"
echo "  target: $DEST"

mkdir -p "$DEST" || { echo "cannot create $DEST"; exit 1; }

for FILE in $FILES; do
    echo "  fetching $FILE"
    if ! fetch "$BASEURL/$FILE" "$DEST/$FILE.new"; then
        echo "  FAILED to download $FILE - is wifi on?"
        rm -f "$DEST/$FILE.new"
        exit 1
    fi
    mv "$DEST/$FILE.new" "$DEST/$FILE"
done

chmod +x "$DEST/kindle-clock.sh"

echo ""
probe
echo ""
echo "Installed. It also shows up in KUAL as 'Clock'."

if [ "$AUTORUN" = "no" ]; then
    echo "Not starting. Run it later with: setsid $DEST/kindle-clock.sh &"
    exit 0
fi

if [ "$AUTORUN" = "ask" ]; then
    echo ""
    echo "Starting the clock stops the kindle UI (and this terminal)."
    echo "The only way back is a ~10s power button reboot."
    printf "Start now? [y/N] "
    read ANSWER
    case "$ANSWER" in
        y|Y|yes|YES) ;;
        *) echo "Not starting. Run it later with: setsid $DEST/kindle-clock.sh &"; exit 0 ;;
    esac
fi

echo "Starting clock..."
cd "$DEST" || exit 1
setsid "$DEST/kindle-clock.sh" >/dev/null 2>&1 &
