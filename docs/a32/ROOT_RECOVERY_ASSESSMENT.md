# A32 root/recovery assessment

Status: compatibility remains unconfirmed; no flashing authorized or performed.

## Evidence
- Device reports SM-A325F, Android 13, A325FXXSCDXL2, empty slot suffix, orange verified boot.
- Owner reports stock recovery, KG Checking, FRP off.
- ADB shell has no su; reading the boot block device failed with Permission denied.
- Current mount table shows / on /dev/block/dm-4. This does not establish the boot image ramdisk size or header.
- No DXL2 AP package or relevant stock boot image was found by filename search under Desktop and Downloads. The Ventoy boot.img is unrelated.

## Primary sources
- https://topjohnwu.github.io/Magisk/install.html : Samsung eligibility includes unlocked OEM state and KG Checking. Ramdisk status determines boot versus recovery installation. Samsung instructions patch AP and flash with the original BL/CP/CSC; this exceeds the task partition allowlist. Initial installation requires wiping according to the guide. Do not infer that boot-only flashing is proven from these instructions.
- https://github.com/LumiROM/twrp_device_samsung_a32/releases : maintainer labels recovery stable, based on A325FXXSCDYB2 kernel and blobs. This is not evidence of testing on DXL2.

## Decision
Retain Magisk as the first candidate for analysis, not a confirmed working installation path. Obtain the exact DXL2 stock AP (preferably full matching AP/BL/CP/CSC rollback package), verify archive integrity and provenance, extract boot/recovery/vbmeta locally, inspect boot header and ramdisk, and inspect the specific Magisk release patch behavior before preparing a flash proposal. Do not substitute a prepatched third-party boot image.

TWRP remains a fallback requiring DXL2 compatibility evidence and separate authorization to write recovery. No claim of working dd or userdata unmount capability has been established on this phone. Root alone would not prove P2 userdata-unmount capability.

No partition write, format, reboot or app installation was performed in this assessment.

## Magisk app check
Official Magisk 31.1 APK installed, SHA-256 matched GitHub release digest. Device UI reports Ramdisk: Yes and Magisk: Not Installed (logs/magisk-ui.xml). This supports boot-ramdisk patching as a candidate but does not verify the DXL2 image header or successful boot. Exact firmware still missing locally. No flash performed.

## DXL2 package validation
Downloaded AP ZIP passed CRC test. Extracted AP tar MD5 verified: 7ee1921b55f5f08b9719d34ac6eb1246. Extracted stock boot has ANDROID! magic, header v2 and 1979389-byte ramdisk. Full AP transfer to device started; patch output not yet produced. No flash authorized/performed.

## Post-patch inspection
Magisk completed the on-device AP patch. Extracted patched boot is 33554432 bytes, header v2; magiskboot cpio test returns 1 (patched), versus stock 0. DTB is identical; decompressed kernel and ramdisk differ. Both stock and patched headers report OS 12.0.0 / patch 2025-01, so the header OS value is inherited, not introduced by Magisk.

Extracted vbmeta is changed: AVB flags stock=0, patched=3. Full patched AP contains additional protected partition images. Thus full AP flashing conflicts with the task allowlist. The observed vbmeta change does not prove boot-only flashing fails, but neither does it establish boot-only compatibility.

P2 remains blocked: stock recovery only; userdata-unmount capability unavailable/unverified; no full AP/BL/CP/CSC rollback set or tested restoration path; device GPT and identity backups not obtained. Firmware-extracted stock boot is not a bit-exact verified backup of the currently installed partition. No partition writes performed. Separate explicit flash approval remains required by the owner's instruction.

Hashes and component comparisons: logs/patch-comparison.txt. Full patched TAR pull is still in progress as of this inspection; extracted boot and vbmeta reads completed successfully.
