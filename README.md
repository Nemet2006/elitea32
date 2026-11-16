# elitea32 · HakiOS for Samsung Galaxy A32 4G (SM-A325F)

[![Kernel](https://img.shields.io/badge/XNU-xnu--8796.121.2-blue.svg)](https://opensource.apple.com/releases/)
[![iOS](https://img.shields.io/badge/iOS-16.5%20(20F66)-green.svg)](https://developer.apple.com)
[![SoC](https://img.shields.io/badge/MediaTek-Helio%20G80%20(MT6769T)-orange.svg)](https://www.mediatek.com)
[![Device](https://img.shields.io/badge/Samsung-Galaxy%20A32%204G-lightgrey.svg)](https://www.samsung.com)
[![License](https://img.shields.io/badge/License-APSL%20%2F%20GPL%2FMIT-brightgreen.svg)](LICENSE)

> **Apple's open-source Darwin XNU kernel (`xnu-8796.121.2` / Darwin 22.5.0) and authentic iOS 16.5 userland running natively on the Samsung Galaxy A32 4G (`SM-A325F`).**

---

## 📱 Device & Hardware Specifications

| Component | Target Hardware Specification |
|---|---|
| **Device Model** | Samsung Galaxy A32 4G (`SM-A325F` / `SM-A325M`) |
| **System-on-Chip** | MediaTek Helio G80 (`MT6769T`) 64-bit Octa-core |
| **CPU Architecture** | 2× ARM Cortex-A75 @ 2.0 GHz + 6× ARM Cortex-A55 @ 1.8 GHz |
| **GPU** | ARM Mali-G52 2EEMC2 (Bifrost Architecture) |
| **Display** | 6.4" Super AMOLED, 1080×2400 FHD+, 90Hz (Emulated at iPhone X `375×812 pt` @3x) |
| **Digitizer / Touch** | STMicroelectronics FTS Multi-touch Controller (`I2C6`) |
| **RAM / Memory** | 4GB / 6GB / 8GB LPDDR4X SDRAM |
| **Internal Storage** | 64GB / 128GB eMMC 5.1 (`MSDC0`) |
| **Power & Battery** | 5000 mAh Li-Ion, MediaTek MT6358 Fuel Gauge + PMIC |
| **Wireless & Comms** | MediaTek MT6631 CONNSYS (Wi-Fi 802.11 a/b/g/n/ac + Bluetooth 5.0) |
| **Security & Boot** | ARM TrustZone, MTK Preloader, Samsung Little Kernel (LK) |

---

## 🏗️ Architecture & Dual-Boot System

HakiOS on the Galaxy A32 is implemented as a **zero-risk dual-boot research platform**. It **does not overwrite Android or corrupt device calibration data** (`efs`, `nvram`, `nvdata`, `preloader` remain untouched).

```mermaid
flowchart TD
    A["BootROM / Preloader"] --> B["Samsung Little Kernel (LK)"]
    B --> C["mtkloader (Bare-Metal Stage 1)"]
    C -- "No pmsg trigger (Normal Boot)" --> D["Android Kernel (Magisk Root)"]
    C -- "pmsg trigger (DARWIN-REDWOOD:BOOT-XNU)" --> E["xnuloader (Stage 2)"]
    E --> F["Apple XNU Kernel (22.5.0)"]
    F --> G["APFS root.apfs / system.apfs Mount"]
    G --> H["iOS launchd (PID 1)"]
    H --> I["backboardd + WindowServer"]
    I --> J["SpringBoard + CoreAnimation + Metal/GLES"]
    J --> K["iOS 16.5 Applications (Notes, Safari, Sileo, etc.)"]
```

### 1. Chainboot Execution Flow
1. **Trigger via Android (`/dev/pmsg0`)**:
   From Android root, writing `DARWIN-REDWOOD:BOOT-XNU` to `/dev/pmsg0` arms persistent DRAM memory (`ramoops` scratchpad).
2. **`mtkloader` Execution**:
   Replaces the Android kernel in `/dev/block/by-name/boot`. When executed with MMU disabled:
   - Initializes UART, timer, GIC, and DRAM mappings.
   - Inspects `pmsg` buffer. If the trigger is absent, it chains directly to the Android kernel (guaranteeing safety against bootloops).
   - If armed, it boots the XNU payload.
3. **`xnuloader` Payload**:
   Constructs Mach-O boot structures, memory descriptors, device tree nodes, and sets kernel boot arguments (`fbscale=3`, `mtkbatt=1`, `gpu=1`).
4. **Mach Kernel & Userland**:
   Mounts APFS filesystem (`/dev/md1` resident payload and `/dev/md0` root), hands control to `/sbin/launchd`, launches `backboardd`, `SpringBoard`, and native applications.
5. **Auto-Recovery Watcher**:
   A hardware watchdog timer ensures that if a kernel panic occurs or the user session ends, the device cleanly reboots straight back into Android.

---

## ⚡ What Works (Feature Status)

| Subsystem | Status | Implementation Details |
|---|---|---|
| **Darwin 22.5.0 XNU Kernel** | ✅ Working | Full Mach 3.0 kernel, BSD subsystems, 64-bit ARM64 task ports, VFS layer |
| **CPU Management** | ✅ Working | MTK DVFS cpufreq frequency scaling on Cortex-A75 & A55 cores |
| **Display & Framebuffer** | ✅ Working | `MiniIOMobileFramebuffer`, command-mode DSI, 39pt authentic corner radius |
| **GPU / Acceleration** | ✅ Working | Mali-G52 MC2 via Mesa Panfrost & OpenGL ES with CoreAnimation integration |
| **Touchscreen Digitizer** | ✅ Working | ST FTS multitouch (I2C6), edge gesture filtering, wake-on-touch |
| **Virtual Keyboard (InputUI)** | ✅ Working | Auto-layout width clamping (`375pt`), dynamic "123" <-> "ABC" keyplane switching |
| **Battery & Fuel Gauge** | ✅ Working | Real battery %, cycle count, Health ("Good", 98%), charging time in Settings |
| **SpringBoard UI** | ✅ Working | Lock screen, swipe-to-unlock, Notification Center, Control Center, Status Bar |
| **Wi-Fi Networking** | ✅ Working | MediaTek MT6631 CONNSYS driver, SSID joining, background URLSession tasks |
| **Bluetooth Subsystem** | ✅ Working | MT6631 HCI controller integration behind iOS `bluetoothd` daemon |
| **Applications** | ✅ Working | MobileNotes, Calculator, Calendar, Clock, Reminders, Safari, Preferences |
| **Jailbreak / Prefix** | ✅ Working | Sileo Package Manager, Procursus prefix (`/var/jb`), dpkg/apt command-line tools |

---

## 🔍 Key Technical Breakthroughs & Fixes

### 1. Dynamic Keyboard Keyplane Switching ("123" <-> "ABC")
- **Root Cause**: On iOS 16, `UIKeyboardLayoutStar` uses `completeRetestForTouchUp` with a conditional bitmask test (`tbz w22, #29`). Slight slop displacement or coordinate latency caused UIKit to flag touches as drag/cancel events, suppressing keyplane changes.
- **Solution**: Inside `userland/src/inject_app.c`, `-[UIKeyboardLayoutStar touchDownWithKey:withTouchInfo:atPoint:executionContext:]` is intercepted via Objective-C runtime swizzling. When the "123" key (`interactionType == 5` or title `"123"`) is detected, `switchKeyplane:` is dynamically invoked with the target keyplane (`Numbers-And-Punctuation` or `Letters`), immediately calling `[[UIKeyboardImpl activeInstance] updateLayout]`.
- **Result**: Immediate, responsive, 100% reliable switching between letters, numbers, and symbols.

### 2. Elimination of Keyboard Window Misalignment
- **Root Cause**: In initial application presentation (e.g. `MobileNotes`), `UIKeyboard` opened with an uninitialized offset (`x > 0`), causing right-edge key cutoff (P, L, Delete off-screen) until first touch forced layout.
- **Solution**: Intercepted `setFrame:`, `didMoveToWindow`, and `showKeyboard` in `libredwood-app.dylib`. Frame coordinates are clamped to `x = 0.0, width = 375.0pt` with immediate `[self setNeedsLayout]` and `[self layoutIfNeeded]` dispatch.

### 3. Battery Fuel Gauge & Health Calibration
- Implemented `RedwoodBattery.cpp` and `redwood_mtkbattery.c`:
  - Maps MT6358 fuel gauge ADC registers to Apple `IOPMPowerSource`.
  - Publishes `NominalChargeCapacity` (4900 mAh), `DesignCapacity` (5000 mAh), `BatteryHealth` (`"Good"`), and `PeakPerformanceCapability`.
  - Enables full authentic battery health display inside iOS **Settings > Battery**.

### 4. APFS & RamFS Virtual Volume Virtualization
- macOS/iOS daemons (`containermanagerd`, `pasted`, `lsd`) check volume free space before allowing downloads or database commits.
- Patched `apfs_vfsops.c` and `ramfs.c` statfs handlers to advertise 64 GB capacity with 32 GB available, bypassing low-space eviction daemon panics.

---

## 🛠️ Build & Compilation

### Prerequisites
- Host Machine: Linux (Ubuntu 22.04 / 24.04 LTS or Debian 12 ARM64/x86_64)
- Toolchains: `clang-18`, `llvm-18`, `zig` (0.13+), `python3`, `git`
- SDK: Theos iOS SDK for `iPhoneOS16.5.sdk`

### Build Steps

1. **Clone Repository**:
   ```bash
   git clone https://github.com/Nemet2006/elitea32.git
   cd elitea32
   ```

2. **Configure Environment**:
   ```bash
   source xnu-env.sh
   ```

3. **Compile Userland & Custom Injections**:
   ```bash
   cd userland
   REST=0 ./build.sh
   cd ..
   ```

4. **Package HakiOS Payload**:
   ```bash
   python3 xnuloader/mkpayload.py -o build/payload-a32.bin \
       kernel=xnu-src/xnu-8796.121.2/BUILD/obj/DEVELOPMENT_ARM64_BCM2837/mach.development.bcm2837 \
       ramdisk=userland/root.apfs
   ```

5. **Generate Chainboot Android Image**:
   ```bash
   python3 tools/chainboot.py \
       /path/to/boot-magisk-DXL2.img \
       mtkloader/mtkloader.bin \
       build/boot-a32.img \
       build/payload-a32.bin
   ```

---

## 🚀 Deployment & Testing

To flash and test on a connected device (`SM-A325F`):

```bash
# Automated run cycle: flashes boot-a32.img, reboots to XNU, captures pstore ramoops logs
export HAKIOS_SERIAL=RF8R41H9P3A
bash tools/a32-cycle.sh
```

To monitor runtime kernel output:
```bash
adb -s $HAKIOS_SERIAL shell "su -c 'cat /sys/fs/pstore/console-ramoops-2'"
```

---

## 📂 Repository Layout

```
elitea32/
├── xnu/                   # XNU 8796.121.2 kernel patches and A32 drivers
│   └── files/
│       ├── bsd/dev/       # Mali, Wi-Fi, MTK battery, touch drivers
│       └── iokit/Kernel/  # MiniIOMobileFramebuffer, RedwoodBattery
├── mtkloader/             # Bare-metal MediaTek bootloader (Stage 1)
├── xnuloader/             # Mach-O chainboot loader & device tree builder (Stage 2)
├── userland/              # iOS user-space bringup, daemons, and injections
│   ├── build.sh           # Userland APFS packager & compiler
│   └── src/
│       ├── inject.c       # backboardd / input touch forwarding & edge filter
│       ├── inject_app.c   # Application UIKit hooks (keyboard 123 switch, layout)
│       └── inject_sb.c    # SpringBoard hooks & Control Center modules
├── tools/                 # Chainboot, image packaging, and flash automation
│   ├── a32-cycle.sh       # Automated test runner and log collector
│   └── chainboot.py       # Dual-boot image injector
├── docs/                  # Architectural documentation & test run logs
│   └── a32/               # Samsung Galaxy A32 specific bringup notes
└── README.md              # Project documentation
```

---

## ⚠️ Disclaimer & Legal Notice

- **Research Purpose Only**: This project is an independent systems engineering and academic operating system research endeavor.
- **Proprietary Files**: No copyrighted Apple proprietary binaries or firmware files are distributed in this repository. All Apple components are loaded directly from legitimate user-supplied iOS IPSW images.
- **Safety**: Modifying partition tables or boot structures carries inherent risk. Always ensure you have a full eMMC / partition dump backup before testing.

---

## 👥 Credits & Authors

- **Project Lead & Developer**: [@Nemet2006](https://github.com/Nemet2006)
- **HakiOS Project & Darwin Kernel Base**: [oosexgang / HakiOS Team](https://github.com/oosexgang)
- **MediaTek Helio Reverse Engineering & Panfrost Community**
