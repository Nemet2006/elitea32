#!/usr/bin/env bash
set -e
IMG="/home/admin_test/Desktop/elitea32/hakios/build/boot-a32.img"
echo "Waiting for Samsung Download Mode (04e8:685d)..."
while true; do
    if heimdall detect >/dev/null 2>&1; then
        echo "Device detected in Download Mode! Flashing boot image..."
        heimdall flash --boot "$IMG"
        echo "SUCCESS: Boot flashed! Device will reboot."
        break
    fi
    sleep 1
done
