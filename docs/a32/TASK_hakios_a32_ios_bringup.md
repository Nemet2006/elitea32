# TASK: Boot iOS 16.5 (HakiOS / Apple XNU) on a Samsung Galaxy A32 4G (SM-A325F)

> Audience: an autonomous AI coding agent with shell access to a build host and (via `adb`) to the phone.
> Owner: the phone's owner. Language of conversation with the owner: Azerbaijani or English.
> Status of the facts below: derived by reading the four repository snapshots the owner supplied
> (`hakios-a32`, `hakios-mt6768`, `hakios-uefi`, `hakios-xnu-kernel` `main`) and the `mtk` branch snapshot of
> `hakios-xnu-kernel` (dated 2026-11-10). Anything marked **UNVERIFIED** has not been run or read in a file
> and must be checked before it is relied on.

---

## 0. Objective and definition of done

Get **one XNU run of iOS 16.5 user space** (launchd → backboardd → SpringBoard) on the A32 with working
screen, touch, buttons, CPU clocks and battery gauge, repeatably, from a clean clone.

This is a **research bring-up, not a ROM**: Android stays on the phone, `mtkloader` sits in the `boot`
partition in front of Android's kernel, starts XNU only when Android asks for it, and the watchdog returns the
phone to Android after every run. Wi-Fi, Bluetooth, audio, camera, cellular are **out of scope** for the
first deliverable (see §10 for stretch goals).

Done levels (each one is a gate; do not skip ahead):

| Level | Meaning | Evidence |
|---|---|---|
| L0 | Baseline toolchain works | unmodified `mtk` branch kernel builds (`mach.development.bcm2837` exists) |
| L1 | Phone prepared | `xnusys` partition (4 GiB) exists, stock `boot` + GPT saved, rollback path tested |
| L2 | Loader runs, Android returns | one triggered run ends with `starting Android` and a log in pstore |
| L3 | Kernel reaches launchd | log has `Darwin Kernel Version 22.5.0` … `load_init_program: attempting to load /sbin/launchd` |
| L4 | SpringBoard draws | periodic `MiniIOMobileFramebuffer: N frames in …` lines, frame "not black" |
| L5 | Input and power | touch events, power/vol keys, `mtk_cpufreq=3` clocks, battery % in log |
| L6 | Stability | a 10-minute run, no panic, SpringBoard keeps one pid (reference: A32 `docs/stability-a32.md`, test41) |

---

## 1. Rules for the agent

### 1.1 Safety invariants (never violate)

1. **Only ever write these partitions on the phone:** `boot` and the new `xnusys`; plus the GPT (first 34 and
   last 33 sectors of the eMMC) exactly once, in step P3. Never write preloader (`mmcblk0boot0/1`), `lk`,
   `vbmeta`, `nvram`, `nvdata`, `nvcfg`, `proinfo`, `persist`, `protect*`, `efs`/`sec_efs`, `tee`, `scp`, `sspm`
   or anything else.
2. **Read-only eMMC driver stays read-only.** Do not change `redwood_emmc.c` to write.
3. **Do not raise CPU or GPU voltages/frequencies** above what the A32 docs list (A75 1999 MHz, A55 1699 MHz).
4. One XNU run at a time. Runs are 120–600 s. Never reboot by hand during a run (log is lost).
5. Always pass the device serial (`adb -s "$HAKIOS_SERIAL"`). Another phone may be attached.
6. Keep a bit-exact copy of the stock `boot` image and the GPT before the first write. Verify with `sha256sum`.

### 1.2 Stop-and-ask conditions

Stop and report to the owner (do not improvise) if any of these is true:

- `getprop ro.boot.slot_suffix` is non-empty (the phone is A/B; the A32 docs assume it is not).
- The stock boot image header version is not **2** (`chainboot.py` asserts `hver == 2`).
- The GPT does not look like the one `gpt-carve.py` expects (it refuses on its own; do not patch it to force it).
- `userdata` is not the last partition on the disk, or its size is under ~12 GiB.
- No way to write `boot` or to unmount `userdata` exists (no usable recovery and no root `dd` path), see §P2.
- The phone does not come back to Android after a run and a power cycle does not fix it.

### 1.3 Repository hygiene (from the projects' own `AGENTS.md`)

- Nothing of Apple's in git: no iOS binary/image/dyld cache/metallib/font/screenshot, no header derived from
  IPSW firmware (`xnuloader/identity.h` is generated locally and git-ignored).
- Nothing of the vendor's: no firmware, no partition or boot images, no device tree taken from a phone.
- No personal data: no serials, no home-directory paths, no logs with device data.
- Licenses: files that become part of XNU (`xnu/files/**`, `xnu/redwood.patch`) are **APSL 2.0**; everything else
  MIT. Do not relabel XNU-derived code as MIT.
- Keep build outputs (`*.o`, `*.bin`, `*.img`, `identity.h`, `touchfw.h`) out of commits.

---

## 2. What the owner has told us (context for risk decisions)

- The phone's **bootloader is already unlocked**.
- The phone holds **nothing of value**: wiping `userdata`, re-flashing, and a factory reset are acceptable.
  Therefore: **skip userdata backup**; do not spend time on it.
- Still do (cheap, protects against the only unrecoverable-looking failures): save stock `boot`, the full GPT
  (both copies), and read-only dumps of the small identity partitions (§P1.4). A wrong GPT write is the one
  mistake that can make the phone hard to recover.

---

## 3. Which repositories to use

| Repo | Use it? | Role |
|---|---|---|
| `https://github.com/oosexgang/hakios-xnu-kernel`, **branch `mtk`** | **YES – this is the base tree** | Self-contained, flat layout with `redwood_*` names: `xnu/` (`apply.sh`, `redwood.patch`, `files/`), `xnu-deps/`, `xnu-build.sh`, `mtkloader/`, `userland/`, `ios165/`, `tools/` (`chainboot.py`, `gpt-carve.py`, `system-flash.sh`, `xnu-cycle.sh`, `boot-xnu.sh`, `get-zig.sh`, `mk-mesa.sh`, …), `xl`, `xl_x6826b`, `docs/from-a-clone.md`, `docs/mtk-porting.md`. Its `from-a-clone.md` was run clean from clone to home screen on the Infinix Hot 20 on 2026-11-10. |
| `https://github.com/Luminous418/hakios-a32` (owner's A32 repo; zip snapshot `hakios-a32-main_1_.zip`) | **YES – overlay source** | Everything A32-specific: `mtkloader/` (A32 loader), `kernel/` drivers, `docs/*-a32.md`, `INSTALL.md`, `device.conf`. Names are `hakios.*` and must be converted (§6). |
| `https://github.com/oosexgang/hakios-xnu-kernel`, branch `main` | **NO** | Qualcomm/QEMU tree with `hakios_*` names; has no MediaTek code, no `emmc_root`, no panfrost. Do not mix it in. (Only possible donor for `xnuloader/mkpayload.py` if missing from `mtk`, check first.) |
| `https://github.com/oosexgang/hakios-mt6768` | **NO (reference only)** | Infinix Hot 20 device repo; everything A32 needs from it is already inside the `mtk` branch. |
| `https://github.com/oosexgang/hakios-uefi` | **NO** | Mu-Silicium/EDK2 for Qualcomm phones. The A32 is MediaTek with Samsung LK; no UEFI is used. Also ignore `uefi/` inside the `mtk` branch. |
| `https://github.com/Nemet2006/hackios-a32-personal` | **Optional, unreviewed** | Owner's personal repo (not analysed). Diff its A32 files against `hakios-a32` before merging; use whichever is newer and tested. |
| `prebuilt/mach.development.bcm2837` in `mtk` | **NO** | Infinix build; lacks the A32 touch/battery/cpufreq drivers. Always build the kernel yourself. |

```sh
mkdir -p ~/work && cd ~/work                     # path must contain NO SPACES
git clone -b mtk https://github.com/oosexgang/hakios-xnu-kernel.git hakios
git clone https://github.com/Luminous418/hakios-a32.git hakios-a32-src
# If either clone fails, use the zip snapshots the owner supplied and unzip them to the same names.
```

**First sanity action (5 min):** record `git rev-parse HEAD` of both; diff the cloned `hakios-a32-src` against the
owner's zip snapshot. If GitHub is newer, use GitHub, but re-read `README.md` "What works" for changes.

---

## 4. Verified hardware facts (A32 4G, SM-A325F)

| Item | Fact | Source |
|---|---|---|
| SoC / GPU | MediaTek Helio G80 **MT6769T**, Mali-G52 MC2 (r1p0, `GPU_ID 0x74021000`), eMMC | `hakios-a32/README.md` |
| Partition scheme | **Legacy non-A/B**: partition is `boot` (no `boot_a`, no slot B) | `AGENTS.md`, `INSTALL.md` |
| Firmware baseline | Stock ROM, stock kernel, **Android 13 / One UI 5**, rooted with Magisk; custom ROM/kernel or GKI/vendor_boot layouts are not expected to work | `INSTALL.md` |
| Boot image | Header **v2**; kernel gzip or raw arm64 `Image`; loader blob must be ≤ `0x40000` bytes (256 KiB); partition is 32 MiB (`BOOT_PARTITION = 32<<20`) | `tools/chainboot.py` |
| Load address | Samsung LK decompresses the kernel where it likes; the loader relocates itself and XNU to `0x40080000` | `mtkloader/start.S`, README |
| Display | 1080×2400 **command-mode DSI**; DSI busy = reg `0x1401400c` bit 31; mutex mask `0x90380`; iOS at `fbscale=3` | `docs/display-a32.md` |
| Touch | STM **FTS5CU56A**, I²C6 @ `0x49`, bit-banged on GPIO89/90; rails GPIO4 (1.8 V) and PMIC VCAMA2 (3.0 V) both required; **no firmware needed** | `docs/touch-a32.md` |
| Buttons | Power: MT6358 `TOPSTATUS` bit 1; Vol-up: keypad `KP_MEM1` bit 1; Vol-down: `TOPSTATUS` bit 3 (homekey) | `kernel/README.md` |
| CPU | A75 cluster 1999 MHz, A55 cluster 1699 MHz via ARMPLL2/ARMPLL1 + MT6358 Vproc11/Vproc12 (`mtk_cpufreq=3`); **`cpus=4`** (six cores ended in fastboot) | `kernel/README.md`, `docs/cpu-a32.md` |
| Battery | MT6358 AUXADC ch0 (3:1 divider) for voltage, `TOPSTATUS` bit 2 = charger (`battery=2`); temperature/current are placeholders | `docs/battery-a32.md` |
| Storage | iOS system image in a 4 GiB partition `xnusys` cut from the end of `userdata`; kernel reads it read-only on demand (`emmc_root=1`, MSDC0 @ `0x11230000`) | `INSTALL.md`, `redwood_emmc.c` |
| Logs | Kernel log returns via ramoops: `/sys/fs/pstore/console-ramoops-2` on the A32 (the Infinix docs say `-0`: use whichever exists) | `README.md` |
| Run trigger | `printf DARWIN-REDWOOD:BOOT-XNU > /dev/pmsg0; adb reboot` (needs root) | README |
| Escape | five fingers held on the screen 1.5 s returns to the loader | README |
| Proven stable config | boot args `cpus=4 fbscale=3 touchscreen=3 buttons=2 mtk_cpufreq=3 battery=2 mali=1`, 600 s watcher, no panic, no respring | `docs/stability-a32.md` |

### Known inconsistencies in A32 `INSTALL.md` (do NOT copy its flags blindly)

| Topic | `INSTALL.md` says | README / kernel README / stability doc say | Decision |
|---|---|---|---|
| cores | `cpus=6`, `-DXNU_CORES=6` | `cpus=4`; "six ended in fastboot" | use **4** |
| display kick | `-DWATCHER_NO_KICK=1` + `mtk_kick=1 te_sync=1` (XNU kicks) | `mtk_kick` default 0, **loader's watcher kicks** with DSI-busy check; `te_sync` measured slower (19 vs 26 fps) | start with **watcher kicks** (do not define `WATCHER_NO_KICK`; leave `mtk_kick` unset). Try the other mode only as an experiment after L5. |
| framebuffer size | `fbwidth=810 fbheight=1800 fbscale=3` | `fbscale=3` only (stability test) | start with **`fbscale=3` only** |
| watcher length | 180 s | 300 s (README), 600 s (stability test) | 300 s for bring-up |
| GPU | `mali=1 gl=1 wallpaper=1` | baseline test used `mali=1` only (CPU-drawn CoreAnimation, 1–24 fps) | **no `gl=1`/`metal=1` until L6 is green** |

---

## 5. The fast workflow (critical path and parallel tracks)

The long pole is the IPSW download (~7.4 GB, ~30 min at 4 MB/s) and the 2.3 GB `system.apfs` flash. Everything
else should happen while they run.

```
TIME ─────────────────────────────────────────────────────────────────────────────►
Track H (host)    H1 clone+toolchain ─► H2 baseline kernel build ─► H3 merge A32 ─► H4 build kernel+loader ─► H6 payload+boot image
Track D (download)        └─► D1 ios165/fetch.sh (30 min) ─► D2 userland/build.sh (root.apfs + system.apfs)
Track P (phone)   P0 probe ─► P1 backups ─► P2 recovery check ─► P3 GPT carve (xnusys) ─► P4 flash system.apfs ──────┐
                                                                                                                      ▼
                                                                          P5 flash boot ─► P6 first run ─► iterate (boot-only loop)
```

Parallelism rules:

- Start **D1 immediately** after the clone (needs only network and `7z`).
- While D1 runs: do P0–P3 on the phone **and** H2–H4 on the host.
- The merge (H3) is the only step that needs thinking; the phone steps are mechanical. Do H3 while P-steps wait
  on the owner (e.g., for the owner to download stock firmware).
- After the first successful flash of `xnusys`, **never touch it again** unless the iOS image changes. The inner
  loop is: edit → build kernel (~3 min) → pack payload (1 s) → flash `boot` → run (5 min) → read log.

---

## 6. Phases, commands and gates

### Phase H1: host toolchain (target: 20 min)

Requirements (from `mtk/docs/from-a-clone.md` and `xnu/README.md`):

- macOS (Command Line Tools; verified path) **or** Linux (stock clang, lld, python3, perl, xz, git, curl; the
  Linux path is documented but was **not re-run** after the last changes: expect small fixes). On Windows use
  WSL2 and run `adb` on the Windows side or via `usbipd`.
- iOS 16.5 SDK at `~/theos/sdks/iPhoneOS16.5.sdk` (from `github.com/theos/sdks`); on Linux also `theos` for cctools.
- `7z`/`7zz` ≥ 23 (reads APFS images), `python3` ≥ 3.9, `adb`, ~20 GB free disk.
- zig 0.13.0 (the loader links with `zig ld.lld`): `tools/get-zig.sh` installs it into `xnu-deps/host/zig`.
- `swift` is only needed to rasterize `font8x16.h`; **the `mtk` branch already contains `mtkloader/font8x16.h`**: copy
  it next to the A32 loader instead of installing Swift.

```sh
cd ~/work/hakios
export HAKIOS_SERIAL=<adb serial>          # environment only, never in a file
xnu/apply.sh                               # ~8 s: Apple xnu-8796.121.2 (from apple-oss-distributions/xnu) + redwood.patch + files -> xnu-src/
xnu-deps/setup.sh                          # ~1 min
tools/get-zig.sh                           # ~1 min
(cd ios165 && ./fetch.sh) &                # background: ~30 min, resumes broken downloads  [Track D]
```

### Phase H2: baseline build (Gate L0)

```sh
./xnu-build.sh -j8 -k
ls -l xnu-src/xnu-8796.121.2/BUILD/obj/DEVELOPMENT_ARM64_BCM2837/mach.development.bcm2837
```

- `-k` is mandatory: the build always ends with a harmless error (`check_all_exports`/lldbmacros) **after** the
  kernel is linked. Judge by the file's timestamp, not by make's exit code.
- **Gate L0:** the kernel file exists and is newer than the build start. If not, fix the toolchain before
  proceeding. This isolates toolchain problems from merge problems.

### Phase P0: probe the phone (10 min, read-only)

Run and save outputs to `logs/probe-*.txt` (git-ignored; they contain device data):

```sh
S="adb -s $HAKIOS_SERIAL"
$S shell getprop ro.product.model                 # expect SM-A325F
$S shell getprop ro.build.version.release         # expect 13
$S shell getprop ro.boot.slot_suffix              # expect EMPTY (non-A/B)
$S shell getprop ro.boot.verifiedbootstate        # expect orange (unlocked)
$S shell su -c id                                  # expect uid=0
$S shell su -c 'ls -l /dev/block/by-name/'
$S shell su -c 'cat /sys/block/mmcblk0/size'       # TOTAL sectors (512 B)
$S shell su -c 'ls -l /dev/block/by-name/userdata' # which disk node it points at
$S shell 'ls /sys/fs/pstore/'                      # ramoops must exist after a reboot
$S shell su -c 'cat /proc/cmdline'
```

Boot image header version (must be 2). Pull the currently installed boot and check byte offset 40:

```sh
$S shell su -c 'dd if=/dev/block/by-name/boot of=/sdcard/boot-stock.img bs=1M'
$S pull /sdcard/boot-stock.img backup/boot-stock.img
python3 - <<'PY'
import struct; d=open('backup/boot-stock.img','rb').read()
assert d[:8]==b'ANDROID!', 'not an Android boot image'
ksize,_,rsize,_,ssize,_,_,page,hver = struct.unpack_from('<9I', d, 8)
print('header version =', hver, ' page =', page, ' kernel =', ksize)
PY
```

**UNVERIFIED unknowns to resolve here (write the answers in `logs/PROBE_SUMMARY.md`):**

1. Is the device's `boot` image a Magisk-patched header-v2 image? If the header is v3/v4, stop (§1.2).
2. Which disk node holds the GPT (`mmcblk0` assumed) and is `userdata` the last partition?
3. Is a working **recovery with `dd` and the ability to unmount `userdata`** available (TWRP for SM-A325F is what `INSTALL.md`
   assumes; its availability is **UNVERIFIED**)? See P2.
4. Which pstore node appears after a reboot (`console-ramoops-0` or `-2`)?

### Phase P1: backups (10 min)

The owner says nothing on the phone is valuable, so **skip userdata**. Do keep:

```sh
mkdir -p backup && cd backup
# 1. stock boot (already pulled above) + checksum
sha256sum boot-stock.img > SHA256SUMS
# 2. both GPT copies (read-only)
$S shell su -c 'dd if=/dev/block/mmcblk0 of=/sdcard/gpt-pri.bin bs=512 count=34'
TOTAL=$($S shell su -c 'cat /sys/block/mmcblk0/size' | tr -d '\r')
$S shell su -c "dd if=/dev/block/mmcblk0 of=/sdcard/gpt-sec.bin bs=512 skip=$((TOTAL-33)) count=33"
$S pull /sdcard/gpt-pri.bin; $S pull /sdcard/gpt-sec.bin
# 3. small identity partitions, READ-ONLY, only if they exist (names vary):
for p in nvram nvdata nvcfg proinfo persist protect1 protect2 efs sec_efs; do
  $S shell su -c "[ -e /dev/block/by-name/$p ] && dd if=/dev/block/by-name/$p of=/sdcard/part-$p.img bs=1M" ; done
$S pull /sdcard/ -a 2>/dev/null || true     # pull part-*.img; keep them out of git
```

Also ask the owner to **download the exact stock firmware package (AP/BL/CP/CSC) for this model and current
build** and keep it on the host. This is the Odin rollback path (general Samsung knowledge, **UNVERIFIED** against
this specific phone); the agent cannot do this itself.

### Phase P2: decide how to write `boot` and edit the GPT (Gate before any write)

Two independent capabilities are needed:

| Need | Preferred | Fallback |
|---|---|---|
| Edit GPT (needs `userdata` unmounted) | TWRP (`adb reboot recovery`) as in `INSTALL.md` §0 | **No known fallback** (UNVERIFIED). If there is no recovery, stop and ask the owner. Do not edit GPT with `userdata` mounted. |
| Write `boot` | root `dd` from running Android (`su -c 'dd if=… of=/dev/block/by-name/boot'`) or from TWRP | Odin with a tar containing `boot.img` (owner-assisted) |

Confirm **both** work harmlessly now: re-flash the stock `boot` over itself and reboot to Android. Only then
continue. This proves the rollback path before anything risky happens.

### Phase P3: carve `xnusys` (destructive, once)  ·  Gate L1

`userdata` loses its last 4 GiB; `xnusys` takes them; `userdata` must then be **formatted** (acceptable here).
Use the `mtk` branch's `tools/gpt-carve.py` (it checks every entry and refuses if something is in the way).

```sh
# from TWRP, userdata UNMOUNTED
adb -s $HAKIOS_SERIAL shell 'dd if=/dev/block/mmcblk0 of=/tmp/gpt-pri.bin bs=512 count=34'
adb -s $HAKIOS_SERIAL shell "dd if=/dev/block/mmcblk0 of=/tmp/gpt-sec.bin bs=512 skip=\$((TOTAL-33)) count=33"
adb pull /tmp/gpt-pri.bin; adb pull /tmp/gpt-sec.bin       # compare with the backups from P1 (must be identical)
python3 ~/work/hakios/tools/gpt-carve.py gpt-pri.bin gpt-sec.bin $TOTAL
#   -> gpt-pri.bin.new, gpt-sec.bin.new ; inspect the printed table: userdata shrinks 4 GiB, "xnusys" appears
adb push gpt-pri.bin.new /tmp/gpt-pri.bin; adb push gpt-sec.bin.new /tmp/gpt-sec.bin
adb shell 'dd if=/tmp/gpt-pri.bin of=/dev/block/mmcblk0 bs=512 seek=0 count=34 conv=fsync'
adb shell "dd if=/tmp/gpt-sec.bin of=/dev/block/mmcblk0 bs=512 seek=\$((TOTAL-33)) count=33 conv=fsync"
adb shell sync
# then in TWRP: Wipe > Format Data (type yes). Reboot to Android.
adb shell su -c 'ls -l /dev/block/by-name/xnusys'    # Gate L1 part 1
```

- Rollback if Android no longer boots: from recovery write back `backup/gpt-pri.bin` (seek 0) and
  `backup/gpt-sec.bin` (seek TOTAL-33), format data again.
- The partition **name must be exactly `xnusys`** (the kernel's eMMC driver looks it up in the GPT).
- Verify `userdata` is formatted and Android completes first-boot setup (skip accounts).

### Phase H3: merge the A32 layer onto the `mtk` base (the only hard engineering task)

Principle: **`mtk` is the base tree (its names, its `redwood.patch`). `hakios-a32` provides hardware-specific
files, renamed `hakios` → `redwood`.** Where a file exists on both sides, the A32 version wins for A32 hardware
*except* the framebuffer (§H3.3). Measured similarity after renaming (`hakios`→`redwood`), as differing lines:
`mali.c` 146, `scp.c` 37, `input.c` 36, `mali.cpp` 486 (A32 added Mesa/Metal syncobj support),
`MiniIOMobileFramebuffer.cpp` 766 (needs manual port), loader `mtkloader.c` 311 (A32 is a fork; use it whole).

Work on a branch: `git checkout -b a32-bringup` in `~/work/hakios`, and work **inside `xnu-src/…`** (a git tree on
branch `redwood`) or directly in `xnu/files/` then re-apply; the project's flow is: edit tree → `xnu/export.sh`
regenerates `redwood.patch` + `files/`. Do not hand-edit `redwood.patch`.

#### H3.1 File mapping (A32 repo → `mtk` tree)

| A32 source (`hakios-a32-src/kernel/…`) | `mtk` destination (`xnu/files/…`) | Action |
|---|---|---|
| `bsd/dev/hakios.fts.c` | `bsd/dev/redwood_fts.c` | **new**; add to `bsd/conf/files` (below) |
| `bsd/dev/hakios.mtkcpufreq.c` | `bsd/dev/redwood_mtkcpufreq.c` | **new** (note: `mtk` keeps `mtk_cpufreq` inside `redwood_mtkkeys.c`; see H3.2) |
| `bsd/dev/hakios.mtkbattery.c` | `bsd/dev/redwood_mtkbattery.c` | **new**; coexists with `mtk`'s `redwood_mtkbatt.c` (boot-arg `battery=2` vs `mtkbatt=1`) |
| `bsd/dev/hakios.mtkkeys.c` (168 lines) | `bsd/dev/redwood_mtkkeys.c` (385 lines) | **conflict**: see H3.2 |
| `bsd/dev/hakios.mali.c` | `bsd/dev/redwood_mali.c` | A32 wins (after rename) |
| `bsd/dev/hakios.scp.c` | `bsd/dev/redwood_scp.c` | A32 wins |
| `bsd/dev/hakios.input.c` | `bsd/dev/redwood_input.c` | **merge** init lists (union), keep `mtk`'s `redwood_pwrap_lock` if present |
| `bsd/dev/hakios.goodix.c` | `bsd/dev/redwood_goodix.c` | A32 wins (only `touchscreen=1` starts Goodix) |
| `bsd/dev/hakios.battery.c` | `bsd/dev/redwood_battery.c` | A32 wins (only `battery=1` uses the Qualcomm UEFI cache) |
| `bsd/dev/hakios.buttons.c` | `bsd/dev/redwood_buttons.c` | A32 wins (only `buttons=1` starts the Qualcomm SPMI buttons) |
| `bsd/sys/hakios.input.h` | `bsd/sys/redwood_input.h` | merge prototypes (add `fts`, `mtkcpufreq`, `mtkbattery`) |
| `iokit/Kernel/hakios.mali.cpp` | `iokit/Kernel/RedwoodMali.cpp` | A32 wins **together with** the two files below (they were changed as a unit for Mesa 25.0.7 / Metal) |
| `iokit/Kernel/MiniIOSurface.h` | `iokit/Kernel/MiniIOSurface.h` | A32 wins (adds `maliSeq`, `MiniIOSurfaceDrawn`) |
| `iokit/Kernel/hakios.gpu.cpp` | `iokit/Kernel/RedwoodGPU.cpp` | **verify** this pairing by diffing; A32 wins if equivalent |
| `iokit/Kernel/MiniIOMobileFramebuffer.cpp` | same path | **port hunks, not replace** (H3.3) |
| `bsd/conf/files`, `iokit/conf/files` | (patched through `redwood.patch`) | **DO NOT COPY.** These are full-file copies from the `main`-style base and would overwrite the `mtk` ones. Add only the new lines (H3.4). |
| `mtkloader/*` | `mtkloader/*` | A32's loader **replaces** `mtk`'s wholesale (it is a fork: Samsung LK relocation, A32 memory map, command-mode DSI kick, `darwin-board=a32`, no SPI touch). Keep `mtk`'s `font8x16.h`; A32 lacks `mtkcam.h` (not needed). Never use `mtk`'s loader on the A32: it has the Infinix memory map. |
| `tools/chainboot.py` | `tools/chainboot.py` | diff both; keep the one that asserts header v2 and `CHAIN_OFFSET 0x40000`; A32's is the tested one |
| `tools/mesa/*`, `tools/rc.jobs.*`, `tools/say_run.c`, `tools/mali_job_test.c` | – | **defer** to GPU stretch (§10) |
| `diag/` | – | optional; useful as a framebuffer/chainboot self-test (`diag/a32diag.c`) |

#### H3.2 Rename procedure

1. Copy A32 files into `xnu/files/...` under their new names (table above).
2. Mechanical rename inside copied files (review the diff; do not trust `sed` blindly):
   - identifiers/functions: `hakios_` → `redwood_`; file-name strings `hakios.` → `redwood_`
   - sysctls: `kern.hakios.` → `kern.redwood.`; devices: `/dev/hakios-touch` → `/dev/redwood-touch` (the `mtk`
     user space opens `redwood-*`)
   - macros/enums: `HAKIOS_BUTTON_*` etc. → check what `mtk`'s `redwood_input.h` actually names them
   - A32 sources **already mix** names (`RedwoodMaliStart`, `redwood_mali_done`): after the rename run
     `grep -rn 'hakios' xnu/files/bsd/dev/redwood_{fts,mtk*,mali,scp,input}*.c` and expect **zero** hits.
3. **`redwood_mtkkeys.c` conflict:** `mtk`'s file implements keys **and** big-cluster clocking (`mtk_cpufreq`);
   A32 split clocking into `redwood_mtkcpufreq.c` and keeps keys alone (power/vol-down from PMIC, vol-up from
   keypad). Resolution: **use the A32 keys + A32 cpufreq pair** (they ran on this hardware, test41) and delete
   the `mtk_cpufreq` code path from the replaced file, so the boot-arg is parsed in exactly one place.
4. Boot-arg collisions to check: `touchscreen=2` (TD4160, Infinix) vs `touchscreen=3` (FTS, A32); `battery=2`
   (A32) vs `mtkbatt=1` (Infinix). They are distinct values, but make sure no init function runs unconditionally.

#### H3.3 Framebuffer (`MiniIOMobileFramebuffer.cpp`), highest-risk hunk

Start from the **`mtk`** version. Diff against A32's and port only A32-specific behaviour:

- `gMTKKick` (`mtk_kick`, **default 0**) and the kick path that writes the display mutex, sets mmsys bit
  (`0x140000f0 |= 1`), sends DSI command `0x2C` (`DSI_CMDQ0 = 0x002c3909`, `DSI_CMDQ_SIZE = 1`, `DSI_START`),
- DSI-busy wait (`0x1401400c` bit 31) before drawing and kick after (presenter),
- `te_sync` (opt-in, default 0) with GPIO44 TE edge detection,
- `IOAcceleratorES::setProperties` gated on `metal=1` (only needed for the Metal stretch).

Compile gate: the `mtk` Infinix path (720×1640, `fbscale=2 fbfit=3`) must still compile and its boot-args remain.
Do not delete Infinix code; gate A32 behaviour on `mtk_kick`/board checks so one tree builds for both.

#### H3.4 Config wiring

In the tree (`xnu-src/…/bsd/conf/files`) add, next to the existing `redwood_tcm.c`/`redwood_mali.c`/`redwood_emmc.c`
lines (they appear around lines 75–82 of `redwood.patch`):

```
bsd/dev/redwood_fts.c           standard
bsd/dev/redwood_mtkcpufreq.c    standard
bsd/dev/redwood_mtkbattery.c    standard
```

and in `redwood_input_init()` add `redwood_fts_init();`, `redwood_mtkcpufreq_init();`, `redwood_mtkbattery_init();`
(order as in A32's `hakios_input_init`: …goodix, **fts**, buttons, mtkkeys, **mtkcpufreq**, scp, battery,
**mtkbattery**, …, mali). Declare them in `redwood_input.h`. Then `xnu/export.sh` to regenerate the patch.

**Gate:** `./xnu-build.sh -j8 -k` produces a kernel again. Fix compile errors by reading the A32 file's original
includes: A32 `goodix` needs `redwood_focaltech_fw.h` (present in `mtk` `xnu/files/bsd/dev/`); `MiniDrivers.h` is in
`mtk` `xnu/files/iokit/Kernel/`.

### Phase H4: build the A32 loader

```sh
cd ~/work/hakios/mtkloader     # now the A32 loader
# baseline flags; do NOT copy INSTALL.md's flags (see §4 table). Read mtkloader.c for the real defaults first:
grep -n 'XNU_CORES\|XNU_WATCH_SECONDS\|XNU_WDT_SECONDS\|XNU_EXTRA_ARGS\|XNU_RETURN_AFTER\|WATCHER_NO_KICK\|XNU_ROOT_ARG' mtkloader.c | head -40
LLD="$PWD/../xnu-deps/host/zig/zig ld.lld" ./build.sh \
   -DXNU_WATCH_SECONDS=300 \
   -DXNU_EXTRA_ARGS='"cpus=4 fbscale=3 touchscreen=3 buttons=2 mtk_cpufreq=3 battery=2 mali=1"'
ls -l mtkloader.bin           # MUST be <= 0x40000 (262144) bytes
```

- `build.sh` writes a placeholder `touchfw.h` (A32 needs no touch firmware) and rasterizes `font8x16.h` only if
  missing (copy the `mtk` one to avoid Swift).
- The loader includes `../xnuloader/identity.h`: generate it from **your own IPSW** (below).
- The loader sets `rd=md0 emmc_root=1` as root arguments by itself (`XNU_ROOT_ARG`); do not duplicate.

### Phase D1/D2: iOS user space (Gate: images exist)

```sh
cd ~/work/hakios
# D1 (started in H1): ios165/fetch.sh  -> pulls iPhone X iOS 16.5 (20F66) disk images from Apple's CDN (~7.4 GB)
# D2:
./userland/build.sh                 # baseline: no GL, no METAL. ~4 min -> userland/root.apfs (~4 MB) and userland/system.apfs (~2.3 GB)
xnuloader/mkidentity.sh <path to the iPhone10,3/6 16.5 20F66 IPSW or its DeviceTree.d22ap.im4p>   # makes xnuloader/identity.h (git-ignored)
```

Verify `xnuloader/mkpayload.py` exists in the `mtk` tree (**UNVERIFIED**; the `main` branch has it, and the A32
`INSTALL.md` uses it). If absent, take it from `main`, or use the `xl`/`xl_x6826b` script's logic. Order matters: the
loader needs `identity.h` **before** it is built, so run `mkidentity.sh` before H4 if the IPSW is already local
(`ios165/fetch.sh` leaves `DeviceTree.d22ap.im4p` in place).

### Phase H6: payload and boot image

```sh
# payload = kernel + small root (root.apfs). Create an A32 copy of xl_x6826b / mkpayload invocation:
python3 xnuloader/mkpayload.py -o /tmp/payload.bin \
   kernel=xnu-src/xnu-8796.121.2/BUILD/obj/DEVELOPMENT_ARM64_BCM2837/mach.development.bcm2837 \
   ramdisk=userland/root.apfs
python3 tools/chainboot.py backup/boot-stock.img mtkloader/mtkloader.bin build/boot-a32.img /tmp/payload.bin
ls -l build/boot-a32.img      # MUST fit the 32 MiB boot partition
```

Wrap steps H2→H6 plus flash/run/log into one script **`tools/a32-cycle.sh`** (derive it from `tools/xnu-cycle.sh`
and `tools/boot-xnu.sh`; those target `boot_a` + `fastboot`, which the A32 does not have). Requirements for the
script: partition `boot`; write via root `dd` (or recovery); trigger with `printf DARWIN-REDWOOD:BOOT-XNU > /dev/pmsg0`
then `adb reboot`; wait for Android; pull whichever `/sys/fs/pstore/console-ramoops-*` exists; save as
`logs/runN.log`; print the checklist in §8.

### Phase P4: flash the iOS system image into `xnusys` (once)

Use `tools/system-flash.sh` (adapt the partition lookup to `/dev/block/by-name/xnusys`; Android must be up with
root; needs ~2.3 GB free on `/data`, which exists after the format in P3):

```sh
tools/system-flash.sh            # ~3 min; system.apfs -> xnusys. Verify with a checksum readback if the script supports it.
```

### Phase P5/P6: first run (Gate L2 → L3 → L4)

```sh
tools/a32-cycle.sh   # flashes boot, triggers ONE run, reads the log
```

First run uses **minimal args** to isolate faults: `cpus=4 fbscale=3` (+ `mali=1`). Add one subsystem per run:
`touchscreen=3` → `buttons=2` → `mtk_cpufreq=3` → `battery=2` → `scp_step=6` (optional). Do not enable everything on run 1.

---

## 7. Triage table (symptom → likely cause → action)

| Symptom | Likely cause | Action |
|---|---|---|
| Phone boots straight to Android, **no** log | loader never started: trigger string wrong, `boot` not flashed, or chain image broken | confirm `boot` hash on device equals `build/boot-a32.img`; re-check `/dev/pmsg0` write; boot image must be header v2 |
| Phone hangs / black screen, no return | loader or kernel hang | power-cycle; the image boots Android unless asked, once. Reproduce with `diag/` framebuffer test; add `fbshot=N` |
| Log ends before `Darwin Kernel Version` | loader/handoff fault | check memory map in A32 loader; watch `mtkdbg.h` ramoops zone addresses |
| `panic: IOFindBSDRoot: emmc_root=1, but the eMMC's xnusys partition could not be read` | partition name/GPT wrong, MSDC0 init, or `xnusys` empty | check `ls /dev/block/by-name/xnusys`; re-run `system-flash.sh`; check `emmc` lines in the log |
| Reaches launchd, then reboots/respring loops | user space mismatch or missing resource | check which daemon aborts; compare against `mtk` docs (`docs/README.md` journals) |
| Screen black but kernel log shows frames | DSI not being kicked | confirm watcher kick active (no `WATCHER_NO_KICK`), `mtk_kick` unset; check DSI_BUSY handling |
| Image/tearing | two kickers | exactly one of {watcher, `mtk_kick`} may kick |
| Touch silent | only GPIO4 on, VCAMA2 off | need both rails (A32 `docs/touch-a32.md`); try `touch_swap=1 touch_flip_x=1 touch_flip_y=1` if axes wrong |
| Six cores → fastboot | known | stay at `cpus=4` |
| `pstore` empty after run | do not reboot manually; ramoops may be cleared | rerun; read immediately after Android is up |

---

## 8. Success checklist for each run (grep these in `logs/runN.log`)

In order (from `mtk/docs/from-a-clone.md`, adjusted for the A32):

1. `boot-args:` line shows `emmc_root=1` and your A32 args
2. A32 touch bring-up line (text from `redwood_fts.c`; `grep -i fts`)
3. `Darwin Kernel Version 22.5.0: …`
4. `mali: came up to step 6 of 6` (when `mali=1`)
5. `load_init_program: attempting to load /sbin/launchd`
6. `=== 36 checks, 0 failed ===` (the project's init self-test)
7. Every 5 s once SpringBoard draws: `MiniIOMobileFramebuffer: N frames in M ms` and a "% not black" line
8. CPU line shows ~1999/1699 MHz when `mtk_cpufreq=3`; battery line with mV and charger state when `battery=2`
9. `=== end of XNU log ===` then `starting Android`
10. L6: summary says `(no panic string)`, SpringBoard pid unchanged for the whole run

Known harmless noise: `lsd … denied attempt to escape CPU monitor` (20 lines/s) and a one-off
`activityawardsd` abort.

---

## 9. Inner iteration loop (after the first successful run)

- Kernel/driver change: `xnu/export.sh` (if edited in-tree) → `./xnu-build.sh -j8 -k` (~3 min) → payload (1 s) →
  `tools/a32-cycle.sh` (flash `boot`, run, log). **Never** re-flash `xnusys`.
- Loader change: rebuild `mtkloader.bin`, re-pack, same cycle.
- Touch/buttons/display tuning: use boot-args first (`touch_poll_us`, `keylog=1`, `keyraw=1`, `fbshot=20` and
  `python3 tools/fbshot.py logs/runN.log shot.png` to see the screen without looking at the phone).
- One change per run; commit after each green run with the run's key log lines in the message.

---

## 10. Stretch goals (only after L6)

Order by value/risk. Each starts with a **discovery step** because the A32's silicon may differ from the Infinix's.

1. **GPU-accelerated CoreAnimation (`GL=1 gl=1`)**: needs `tools/mk-mesa.sh` with panfrost (`panfrost-darwin.patch`,
   `air-panfrost.patch`, `hakios-drm`/`redwood-drm`), then A32's `hakios.mali.cpp` panfrost IOKit service. A32 docs
   report 21,729 job chains, 0 failed, 21–31 fps with retain/lazy-heap patches. Needs meson+ninja.
2. **Metal (`METAL=1`, `metal=1 metal_plugin=1`)**: `userland/build.sh` supports `METAL`; the A32 repo references
   the `y2sios` runtime and a **private** `hakios-a32-metal` tree for extra flags (`CHRONO`, `METAL_QUARTZCORE`,
   `METAL_RENDERBOX`, `WALLPAPER_FILE` appear in **neither** public `userland/build.sh`). Requires the two
   `default.metallib` files extracted from the owner's own IPSW (`QuartzCore.framework`, `RenderBox.framework`).
3. **Wi-Fi/Bluetooth**: the `mtk` branch has working CONNSYS code for the Infinix (MT6631 combo, `connsys_step=1..17`).
   **Do not assume the A32 uses the same chip/firmware.** Discovery: from Android (`adb shell su`) read
   `ls /vendor/firmware /vendor/lib/modules`, `lsmod`, `dmesg | grep -i -E 'wlan|consys|conn|mt66'`; compare to
   `mtk/docs/wifi-x6826b.md` and `bluetooth-mtk-porting.md`; pull firmware with a copy of `pull-firmware.sh`
   (vendor files stay local, never committed).
4. **Rotation (SCP accelerometer)**: kernel streams samples (`scp_step=6`); user-space feed to backboardd is missing.
5. Audio, camera, haptics, cellular: no A32 groundwork exists. Out of scope.

Not goals of the project (from its README): Apple ID, iCloud, App Store, activation (no Secure Enclave on this hardware).

---

## 11. Risk register (owner's context: unlocked bootloader, no valuable data)

| # | Risk | Likelihood | Impact | Mitigation / why acceptable |
|---|---|---|---|---|
| R1 | Android loses data when `userdata` is cut and formatted | certain | none (owner: nothing valuable) | accepted; skip userdata backup |
| R2 | Bootloader-unlock consequences (data wipe, Knox flag) | already incurred | none | already done by the owner |
| R3 | Wrong GPT write makes the phone unbootable | low if `gpt-carve.py` is used unmodified and backups exist | **high** (the only serious one) | verify pulled GPT = backup GPT; never force `gpt-carve.py`; keep `gpt-*.bin` backups; stop-and-ask on any mismatch; have Odin stock firmware ready |
| R4 | A bad `boot` image causes a boot loop | medium during development | low | the image boots Android unless asked; keep `boot-stock.img`; rollback = `dd` stock `boot` (recovery or Odin); **test the rollback path in P2** |
| R5 | No recovery (TWRP) for SM-A325F available, so GPT/`userdata` cannot be handled safely | **UNKNOWN** | blocks P3 | resolve in P0/P2 before anything else; ask the owner |
| R6 | Samsung AVB/vbmeta or other protection rejects the modified `boot` | low (bootloader is unlocked, `orange` state expected) | medium | check `ro.boot.verifiedbootstate`; if boot refuses, report; do **not** flash vbmeta without owner approval |
| R7 | IMEI/radio calibration partitions damaged | very low (we never write them) | high | only write `boot`, `xnusys`, GPT; read-only dumps of identity partitions taken in P1 |
| R8 | Thermal/battery stress | low | low | do not raise voltages; runs ≤ 600 s; charger present on long runs |
| R9 | Merge produces a kernel that compiles but misbehaves (framebuffer, touch) | **high** | time | isolate by adding one boot-arg per run (§P5/P6), keep Infinix code paths intact, log-driven fixes |
| R10 | Docs disagree with each other (see §4 table) | certain | time | follow the stability-test configuration; treat `INSTALL.md` as a draft |
| R11 | Legal/provenance mistakes (committing Apple or vendor files) | low | medium | §1.3; `tools/provenance-check.py` exists in the `main` branch and is a useful pattern |
| R12 | MediaTek BROM recovery (`mtkclient`) on this Samsung model | **UNVERIFIED** whether reachable | – | do not rely on it; plan on Odin |

---

## 12. Deliverables

1. Branch `a32-bringup` of the base tree with: the A32 layer merged (H3), `tools/a32-cycle.sh`, adapted
   `system-flash.sh`, updated `docs/` page `docs/a32-from-a-clone.md` (every command in order, with timings from
   your run, and what stopped you).
2. `logs/` excerpts for L2–L6 (device identifiers redacted), kept **out of git** or sanitized.
3. A short `RESULTS.md`: which levels were reached, exact boot args and loader flags that worked, open bugs.
4. A list of every place you deviated from this document and why.

Report progress to the owner at each gate (L0, L1, L2, …) in one or two sentences with the evidence line.
