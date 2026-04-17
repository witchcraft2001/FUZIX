# FUZIX for Sprinter (Peters MC 2008)

Port of FUZIX OS to the Sprinter — a Russian ZX Spectrum-compatible home computer
with a full Z80 CPU upgrade, 4 MB RAM and IDE storage.

## Hardware

| Component | Details |
|-----------|---------|
| CPU | Z84C15 (CMOS Z80) at 7 MHz (normal) / 21 MHz (turbo) |
| RAM | 4 MB — 256 pages × 16 KB, pages #00–#FF |
| VRAM | 512 KB — pages #50–#5F |
| Banking | 4 independent 16 KB windows (WIN0–WIN3) via ports #82/#A2/#C2/#E2 |
| Video | ZX-compatible + native 320×256 / 640×256; text 80×32 for console |
| Keyboard | PS/2 via Z84C15 SIO Channel A (data port #18, control port #19) |
| Storage | IDE (16-bit ports: read #0050, write #0150) |
| FDD | WD1793 via MAX7000 (not yet supported) |
| Timer | CTC channels #10–#13; channel 0 generates 50 Hz system tick |
| RTC | CMOS via ports #1C (data read) / #1D (data write) / #1E (address) |

## Kernel Memory Layout

FUZIX uses `CONFIG_BANK16` — four 16 KB windows mapped to physical RAM pages.

```
Address range    Window  Kernel page  Contents
0x0000–0x3FFF   WIN0     page 0       CODE (kernel init, low-level routines)
0x4000–0xBFFF   WIN1/2   pages 1–2    CODE1 (banked; overlaid CODE2/3 for syscalls)
0xC000–0xFFFF   WIN3     page 3       COMMONMEM (always visible)

Pages 4–5  →  CODE2 bank (overlaid at 0x4000 for syscall groups)
Pages 6–7  →  CODE3 bank (overlaid at 0x4000 for remaining syscalls)
Pages 8–79 →  user processes (72 pages × 16 KB = 1152 KB user space)
Pages 0x50–0x5F  VRAM (not used for processes)
```

## Disk Layout

```
Sector 0          Boot sector (512 bytes, ORG 0x8000)
                  ├─ Bytes 0–81:      Z80 boot code (load kernel via BIOS DRV_READ)
                  ├─ Bytes 446–461:   MBR partition entry (type 0x7E, LBA 257, 65535 blocks)
                  └─ Bytes 510–511:   Boot signature 0x55 0xAA

Sectors 1–32      Kernel page 0  (16 KB)
Sectors 33–64     Kernel page 1  (16 KB)
Sectors 65–96     Kernel page 2  (16 KB)
Sectors 97–128    Kernel page 3  (16 KB, common memory)
Sectors 129–160   Kernel page 4  (16 KB, CODE2)
Sectors 161–192   Kernel page 5  (16 KB, empty — required for page alignment)
Sectors 193–224   Kernel page 6  (16 KB, CODE3)
Sectors 225–256   Kernel page 7  (16 KB, empty — required for page alignment)

Sector 257+       FUZIX filesystem (hda1 — 65535 × 512-byte blocks ≈ 32 MB)
```

The boot sector doubles as a PC-style MBR so that `tinydisk_setup()` can discover
partition 1 at LBA 257 without a separate MBR sector.

## Boot Sequence

1. Sprinter BIOS reads sector 0 → loads 512 bytes at **0x8000** (WIN2 = RAM page 10) → jumps to 0x8000 with drive number in register A.
2. Boot sector enables Sprinter native mode (`OUT (0x7C), 0x1D`), resets the IDE drive, then loads 8 kernel pages (pages 0–7) into RAM via WIN1 using BIOS **DRV_READ** (`RST #08`, C=#55).
3. Remaps WIN0 → page 0, jumps to **0x0100** (PROGLOAD).
4. `crt0.s` remaps WIN1=1, WIN2=2, WIN3=3 and calls `fuzix_main`.
5. Kernel mounts root filesystem from **hda1** (IDE 0 master, partition 1 at LBA 257).

## Building

### Prerequisites

- SDCC cross-compiler (provides `sdcc`, `sdasz80`, `sdldz80`, `makebin`)
- `byacc` (for library builds)
- `/opt/fcc/bin` on PATH (Fuzix Compiler Kit, for applications)
- Perl (for `build-filesystem-ng`)

### Commands

```sh
# Build everything: tools, libraries, applications, kernel, disk image
make diskimage TARGET=sprinter

# Build only the kernel (no filesystem)
make TARGET=sprinter

# Rebuild only the kernel after a source change
make kclean TARGET=sprinter && make TARGET=sprinter

# Build only the platform Makefile targets (from Kernel/)
make -C Kernel/platform/platform-sprinter image \
     IMAGES=$(pwd)/Images/sprinter

# Build the filesystem image separately
cd Standalone/filesystem-src
TARGET=sprinter ./build-filesystem \
    ../../Images/sprinter/filesys.img 256 65535

# Clean kernel build artifacts
make kclean TARGET=sprinter

# Full clean (tools, libs, apps, kernel, images)
make clean TARGET=sprinter
```

### Output Files

| File | Location | Description |
|------|----------|-------------|
| `boot.bin` | `Kernel/platform/platform-sprinter/` | 512-byte boot sector binary |
| `fuzix.sprinter` | `Kernel/platform/platform-sprinter/` | Raw kernel image (128 KB, 8 pages) |
| `filesys.img` | `Images/sprinter/` | FUZIX filesystem (32 MB, 256 inodes) |
| `fuzix.img` | `Images/sprinter/` | **Complete bootable disk image (32 MB)** |

### Writing to IDE Disk

```sh
# Write to a physical IDE disk device (replace /dev/sdX with the correct device)
dd if=Images/sprinter/fuzix.img of=/dev/sdX bs=512 conv=fsync
```

> **Warning:** this overwrites the entire disk. Double-check the target device.

## Source Files

| File | Description |
|------|-------------|
| `boot.s` | Boot sector: loads kernel pages via Sprinter BIOS DRV_READ API |
| `crt0.s` | Kernel entry: sets up banking windows, calls `fuzix_main` |
| `sprinter.s` | Platform assembly: bank switching, interrupt vectors |
| `sprvideo.s` | Video driver: 80×32 text mode via native Sprinter VRAM |
| `commonmem.s` | Common memory trampolines |
| `tricks.s` | Z80 banked call/return stubs |
| `usermem.s` | User-space memory copy routines |
| `devtty.c` | PS/2 keyboard driver (Set 2 scancodes, SIO polling, VT100 output) |
| `devices.c` | Device switch table |
| `ide.c` | IDE driver (16-bit Sprinter port addresses via BC register pair) |
| `main.c` | Platform init, CMOS RTC, 50 Hz interrupt handler |
| `discard.c` | One-shot init code: IDE probe, page map init |
| `config.h` | Platform configuration (memory, devices, banking) |
| `target.mk` | Make variables for this target (CPU, toolchain flags) |
| `rules.mk` | Optional Makefile overrides |
| `plt_ide.h` | IDE port definitions for `tinyide` |
| `fuzix-platform-sprinter.pkg` | Filesystem package descriptor (activated by `build-filesystem -p platform-sprinter`) |

## Status

| Component | Status |
|-----------|--------|
| Kernel build | ✅ Compiles and links cleanly |
| Boot sector | ✅ Loads 8 kernel pages, MBR partition table embedded |
| Video (80×32) | ✅ Native text mode via sprvideo.s |
| PS/2 keyboard | ✅ Full Set 2 decoder, modifiers, VT100 sequences |
| IDE storage | ✅ Driver written; untested on hardware |
| CMOS RTC | ✅ Read-only BCD access |
| Filesystem image | ✅ Built by `make diskimage` |
| Emulator test (MAME) | 🔲 Not yet tested |
| FDD (WD1793) | 🔲 Not implemented |

## Bring-Up Recovery Point (2026-04-17)

This section tracks the current stabilization point for `/init` bring-up on Sprinter,
so a new session can continue from the same state.

### Goal

- Boot reaches mounted root FS and runs `/init` reliably.
- Avoid memory-corrupting recovery hacks.
- Eliminate `panic: killed init` by fixing the real cause of PID1 `_exit(-1)`.

### Current Safe State

- System is in deterministic panic mode again (no disk image corruption, no full-trace `0xFF` flood).
- Main reproducible failure currently ends in `plt_monitor` (`PC=0xEE65`) with panic text `no /init`.
- Current `_execve` bring-up instrumentation shows `u_argn == 0` at entry (`E8 00 00`), but fallback write path (`EC`) still does not execute in failing runs.

### Last Known-Useful Fixes Kept

- `Kernel/platform/platform-sprinter/usermem.s`: `__uput`/slow-path fixes (required for valid `/init` string path writes).
- `Kernel/cpu-z80/lowlevel-z80-banked.s`: `null_handler` now sets syscall number in `A` before `unix_syscall_entry` calls:
  - `A=39` for `signal(getpid(), SIGBUS)`
  - `A=0` for `_exit`

### Recovery Hooks Disabled Again

- Automatic PID1 restart from `doexit()` removed.
- Automatic `exec_or_die()` on bogus syscall (`u_callno & 0x80`) removed.
- Forced marker-based restart path in `_execve()` removed.

These hooks were useful for diagnosis but caused unstable behavior in some runs.

### Latest Trace Signature (authoritative)

Current observed signatures (latest runs):

- `... C2 4F 01 00 ... C3 00 01 00 08 ...`
  - PID1 syscall `0x4F` (`getsid`) returns success.
- **Signature A (`PANIC_NOINIT`)**
  - `... F1 D2 08 D1 08 D0 08 ... DB F2 F2 DC 6E 6F 20 2F ...`
  - `_execve` enters with null/garbage exec name (`E7 00 00`, `EB 00 00`, `EF 00...`) and panics `no /init`.
- **Signature A2 (`PANIC_NOINIT` with fallback diagnostics)**
  - `... E8 00 00 01 ... E7 00 00 EA 00 00 EB 00 00 EF 00...`
  - PID1 (`01`) enters `_execve` with null exec pointer, but expected fallback marker `EC` is absent before panic.
- **Signature B (`PANIC_WANTBSYB`)**
  - `... DB C7 C7 DC 77 61 6E 74 ...`
  - panic string starts with `want` (`PANIC_WANTBSYB`, "want busy block").
- **Signature C (guard hit + unstable flow)**
  - `... E6 ... EB 40 40 EF 2F 69 6E 69 74 00 ...`
  - PID1 exec-name guard rewrites to `/init`, then run may still jump to low-memory garbage (`PC ~ 0x004F`).

Latest snapshot details (2026-04-17, cycles 297/217):

- `PC=0xEE65`, `SP=0xFBE8`, `PG0=0x0148`, `PG1=0x014C`, `PG2=0x01FE`, `PG3=0x014B`
- Trace around failure:
  - `... E8 00 00 01 E0 E7 00 00 EA 00 00 EB 00 00 EF 00 00 00 00 00 00 ...`
  - `... F1 D2 08 D1 08 D0 08 DA 08 ... DB F2 F2 DC 6E 6F 20 2F ...`

### Next Debug Target

- Explain why `_execve` fallback path is skipped despite `u_argn==0` (`E8 00 00`) and PID1 (`01`).
- Keep changes minimal and deterministic (no aggressive restart guards).
- Once `EC`/valid `exec_name` path is stable, continue toward previous target: reproduce and fix `killed init` (`_exit(-1)` from PID1).

### Rebuild Command

```sh
make diskimage TARGET=sprinter
```

Use `Images/sprinter/fuzix.img` (or `fuzix.chd`) produced by that build.
