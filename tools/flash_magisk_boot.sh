#!/usr/bin/env bash
set -euo pipefail

SERIAL="RF8R41H9P3A"
FW_DIR="/home/admin_test/Desktop/elitea32/firmware"
MAGISK_BOOT="${FW_DIR}/boot-magisk-DXL2.img"
STOCK_BOOT="${FW_DIR}/boot-stock.img"
LOG_FILE="/home/admin_test/Desktop/elitea32/logs/heimdall_flash_magisk.log"

echo "=== Step 1: Pre-flight checks ==="
test -f "$MAGISK_BOOT" || { echo "Missing $MAGISK_BOOT"; exit 1; }
test -f "$STOCK_BOOT" || { echo "Missing $STOCK_BOOT"; exit 1; }

echo "Verifying Magisk boot header..."
python3 - <<'PY'
import struct
d = open('/home/admin_test/Desktop/elitea32/firmware/boot-magisk-DXL2.img','rb').read()
assert d[:8] == b'ANDROID!', 'not an Android boot image'
ksize,_,rsize,_,ssize,_,_,page,hver = struct.unpack_from('<9I', d, 8)
assert hver == 2, f'Invalid header version: {hver}'
print(f"Header v2 verified: page={page}, kernel={ksize}, ramdisk={rsize}")
PY

echo "Checking ADB device..."
adb -s "$SERIAL" get-state

echo "=== Step 2: Rebooting to Download Mode ==="
adb -s "$SERIAL" reboot download

echo "Waiting for device in Download Mode..."
for i in {1..30}; do
    if heimdall detect 2>/dev/null | grep -q "Device detected"; then
        echo "Device detected by Heimdall after ${i} seconds!"
        break
    fi
    sleep 1
done

sleep 2

echo "=== Step 3: Flashing Magisk Boot via Heimdall ==="
# Partition name in PIT is lowercase "boot"
heimdall flash --boot "$MAGISK_BOOT" --verbose 2>&1 | tee "$LOG_FILE"
FLASH_EXIT=${PIPESTATUS[0]}

echo "Flash exited with status: $FLASH_EXIT"
if [ "$FLASH_EXIT" -ne 0 ]; then
    echo "Heimdall flash failed! See $LOG_FILE"
    exit "$FLASH_EXIT"
fi

echo "=== Step 4: Waiting for phone to boot back into Android ==="
adb -s "$SERIAL" wait-for-device
echo "Device reconnected to ADB!"

echo "=== Step 5: Verifying Root Access ==="
sleep 5
for attempt in {1..10}; do
    if adb -s "$SERIAL" shell "su -c id" 2>/dev/null | grep -q "uid=0"; then
        echo "SUCCESS: Root access (uid=0) confirmed!"
        adb -s "$SERIAL" shell "su -c id"
        exit 0
    fi
    echo "Waiting for Magisk daemon (attempt $attempt)..."
    sleep 3
done

echo "Root check completed."
