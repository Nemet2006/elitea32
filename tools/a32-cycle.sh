#!/usr/bin/env bash
# a32-cycle.sh: One XNU run on Samsung Galaxy A32 (SM-A325F)
set -euo pipefail

S="${HAKIOS_SERIAL:-RF8R41H9P3A}"
ROOT="/home/admin_test/Desktop/elitea32"
HAKIOS_ROOT="${ROOT}/hakios"
BOOT_IMG="${HAKIOS_ROOT}/build/boot-a32.img"
LOGS_DIR="${ROOT}/logs"
mkdir -p "$LOGS_DIR"

# Find next run number
RUN_NUM=1
while [ -f "${LOGS_DIR}/run${RUN_NUM}.log" ]; do
    RUN_NUM=$((RUN_NUM + 1))
done
OUT="${LOGS_DIR}/run${RUN_NUM}.log"

echo "=== HakiOS A32 Run #${RUN_NUM} ==="

if [ ! -f "$BOOT_IMG" ]; then
    echo "ERROR: Missing $BOOT_IMG. Building chainboot image..."
    python3 "${HAKIOS_ROOT}/tools/chainboot.py" \
        "${ROOT}/firmware/boot-magisk-DXL2.img" \
        "${HAKIOS_ROOT}/mtkloader/mtkloader.bin" \
        "$BOOT_IMG" \
        "${HAKIOS_ROOT}/build/payload-a32.bin"
fi

# Verify header
echo "Verifying boot image size and header..."
python3 - <<PY
import struct
d = open('$BOOT_IMG', 'rb').read()
assert d[:8] == b'ANDROID!', 'not an Android boot image'
ksize, _, rsize, _, ssize, _, _, page, hver = struct.unpack_from('<9I', d, 8)
assert hver == 2, f'Header version {hver}, expected 2'
assert len(d) == 33554432, f'Image size {len(d)}, expected 33554432'
print(f"Verified: header v{hver}, size {len(d)} bytes, kernel={ksize}, ramdisk={rsize}")
PY

echo "Checking ADB connection..."
adb -s "$S" get-state >/dev/null

echo "=== Flashing HakiOS boot image to /dev/block/by-name/boot ==="
adb -s "$S" push "$BOOT_IMG" /sdcard/boot-a32.img
adb -s "$S" shell "su -c 'dd if=/sdcard/boot-a32.img of=/dev/block/by-name/boot bs=1M conv=fsync ; rm -f /sdcard/boot-a32.img'"
echo "Boot partition flashed successfully."

echo "=== Arming XNU trigger in /dev/pmsg0 ==="
adb -s "$S" shell 'su -c "printf DARWIN-REDWOOD:BOOT-XNU > /dev/pmsg0"'
echo "Trigger armed: DARWIN-REDWOOD:BOOT-XNU written to /dev/pmsg0."

echo "=== Triggering reboot into HakiOS XNU ==="
adb -s "$S" reboot
echo "Phone is rebooting into XNU (watcher is active; Android returns automatically after run)..."

echo "Waiting for Android return (timeout 800s)..."
for i in $(seq 1 270); do
    if [ "$(adb -s "$S" get-state 2>/dev/null)" = "device" ]; then
        echo "Android returned after $((i * 3)) seconds!"
        break
    fi
    sleep 3
done

sleep 4

echo "=== Pulling kernel logs from pstore ==="
FOUND_LOG=0
for node in console-ramoops-2 console-ramoops console-ramoops-0 console-ramoops-1; do
    if adb -s "$S" shell "su -c '[ -f /sys/fs/pstore/$node ]'" 2>/dev/null; then
        echo "Found log at /sys/fs/pstore/$node"
        adb -s "$S" shell "su -c 'cat /sys/fs/pstore/$node'" > "$OUT" 2>/dev/null || true
        if [ -s "$OUT" ]; then
            FOUND_LOG=1
            break
        fi
    fi
done

for pmsg_node in pmsg-ramoops-2 pmsg-ramoops-0; do
    if adb -s "$S" shell "su -c '[ -f /sys/fs/pstore/$pmsg_node ]'" 2>/dev/null; then
        adb -s "$S" shell "su -c 'cat /sys/fs/pstore/$pmsg_node'" > "${OUT}.keep" 2>/dev/null || true
        if head -c 64 "${OUT}.keep" | grep -q 'kept for the host by the kernel'; then
            echo "Found keep log at /sys/fs/pstore/$pmsg_node"
            cat "${OUT}.keep" >> "$OUT"
        fi
        rm -f "${OUT}.keep"
    fi
done

if [ "$FOUND_LOG" -eq 1 ]; then
    echo "Log successfully saved to $OUT ($(wc -c < "$OUT") bytes)"
    echo ""
    echo "=== Checklist verification for run #${RUN_NUM} ==="
    grep -i -E "boot-args:|Darwin Kernel Version|fts|mali:|launchd|36 checks|MiniIOMobileFramebuffer|mtk_cpufreq|battery|starting Android|panic" "$OUT" | head -40 || true
else
    echo "WARNING: No ramoops log found in /sys/fs/pstore/. Checking listing:"
    adb -s "$S" shell "su -c 'ls -la /sys/fs/pstore/'" || true
fi
