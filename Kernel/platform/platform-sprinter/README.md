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
| Kernel startup (crt0) | ✅ Banking, stack at `kstack_top`, BSS/DATA zeroing, early banner |
| Console text output | ✅ Direct VRAM writes to screen B via `sprvideo.s`, screen cleared by `init_hardware` |
| PS/2 keyboard | ✅ Set 2 decoder, modifiers, VT100 sequences (polled — interrupts currently masked) |
| IDE storage | ✅ Mount reads the superblock and inode blocks over 16-bit ports |
| Root filesystem mount | ✅ `hda1` mounts and root inode opens |
| `_execve /init` | ✅ Resolves `/init`, loads the binary, PID 1 starts running in user space |
| CMOS RTC | ✅ Read-only BCD access |
| Filesystem image | ✅ Built by `make diskimage` |
| Interrupt dispatcher | ⚠️ Bring-up stub (`sprinter_bringup_int`) — `reti` without `ei`, IRQs stay masked |
| Init hang | 🔲 `/init` runs but stalls shortly after "Starting /init" — syscall path from user space to be investigated |
| FDD (WD1793) | 🔲 Not implemented |

## Current Bring-Up State

`make diskimage TARGET=sprinter` produces `Images/sprinter/fuzix.img` (and
`fuzix.chd` if `chdman` is available).  Booting that image in MAME's Sprinter
driver reaches the following milestones:

1. BIOS boot sector messages.
2. `CRT0` banner written directly to VRAM at row 0 (proof-of-life from
   `crt0.s`).
3. Kernel banner (`FUZIX version ...`, copyrights, `Devboot`) via `kprintf`.
4. Root filesystem mount from `hda1` completes.
5. Kernel prints `Starting /init`.
6. `/init` is exec'd — `PC` moves into user space (WIN0 mapped to a user
   page), syscalls fire, `trace_idx` climbs past 200.
7. Execution stalls with no further on-screen output; the next target is to
   find which syscall / resource init is waiting on.

Interrupts are held masked during bring-up.  `sprinter_bringup_int` replaces
FUZIX's core `interrupt_handler` in both the IM2 vector table at `0xFDFD`
and the IM1 vector at `0x0038`; it simply RETIs without re-enabling IFF1,
and forces `_int_disabled = 1` so a subsequent `irqrestore(saved)` where
`saved == 0` does not turn IRQs back on.  CTC channels are reset at init
time to guarantee they don't raise TINT.

### Diagnostics still in place

The following temporary instrumentation is carried while init is being
brought up and should be removed once the kernel stabilises:

- `crt0.s` paints the ZX border port (`0xFE`) at five points during startup
  and calls `early_banner` to write `CRT0` to VRAM.
- `start.c` dumps `udata.u_argn*` before and after `complete_init` and reads
  the just-written `/init` string back via `ugetc` (markers `0xCA` / `0xCB`).
- `syscall_exec16.c` dumps `udata.u_page[0..3]` at `_execve` entry (marker
  `0xED`), runs a `uputc 0xA5 + ugetc` sentinel probe (markers `0xDE` /
  `0xDF`) and re-stages `/init\0` into user space immediately before
  `n_open_lock` to work around a page-reuse bug (see below).
- Many `FM_/DIO_/TD_/IDE_/EX_/PROC_TRACE` call sites throughout the core
  kernel; they feed the circular trace buffer at `_sprinter_trace_buf`
  (256 bytes in `_COMMONDATA`).  `_plt_trace` only writes to memory — it
  does NOT touch any border / VID port, because the I/O ports in the
  `0xC0..0xCF` range share decoder bits with the WIN2 / banking registers
  on Sprinter.

### Known bug kept under workaround

Between `create_init` (where `add_argument("/init")` writes the path into
init's user pages) and `_execve` (where `n_open_lock` reads it), the
user page holding `PROGLOAD + 256` gets reused by some other kernel code
path and the "/init" bytes disappear.  The workaround is the re-stage step
in `_execve` listed above.  Tracking the real culprit is open — see the
task list in the session notes.

### Rebuild Command

```sh
make diskimage TARGET=sprinter
```

Use `Images/sprinter/fuzix.img` (or `fuzix.chd`) produced by that build.
