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
| `_execve /init` | ✅ Resolves `/init`, loads the binary correctly into user pages |
| User-mode entry | ✅ `doexec` jumps to `/init` at 0x0112, `u_page = {user, user, user}`, vectors installed |
| CMOS RTC | ✅ Read-only BCD access |
| Filesystem image | ✅ Built by `make diskimage` |
| Interrupt dispatcher | ⚠️ Bring-up stub (`sprinter_bringup_int`) — `reti` without `ei`, IRQs stay masked |
| Disk writes | ⚠️ `bdwrite` / `devide_write_data` no-op'd during bring-up (safety net) |
| Init post-exec | 🔲 `/init` enters user space, then NMI fires — `[NMI]` prints, kernel halts |
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
6. `/init` is exec'd — `_execve` loads 18 KB of binary, ugetc read-back at
   0x0110 / 0x35FE / 0x47FE matches `Applications/util/init` byte-for-byte.
7. `doexec` jumps to user entry at 0x0112 with `u_page = {0x45, 0x44, 0x43}`
   mapped and `SP = 0xEDEE`.
8. Shortly after, `[NMI]` appears on the console and the kernel drops into
   `plt_monitor`.  Source of the NMI is the next target (Z84C15 WDT? ULA
   NMI line? spurious bus fault?).

### Key fixes that got PID 1 into user space

Four stacked bugs were silently corrupting the user-memory copy path.
Each fix is required for the next to matter:

1. **`usermem.s:uputget_put` arg order**.  `BC` was loaded from offset 8
   (dst) and `DE` from offset 10 (count).  The fast path then used the
   user pointer as an `ldir` count, and the slow path wrote every
   source byte to one remapped address derived from `count`.  Fixed
   to match `uputget`: `BC = count`, `DE = dst`.

2. **`uput_slow_loop` clobbered source byte**.  The loop did `pop af`
   (restore source byte into `A`) and then `call user_map_de`, which
   overwrites `A` with `(dst_hi & 0x3F) | 0x40`.  The subsequent
   `ld (hl), a` then wrote that value instead of the real byte — user
   RAM filled with a monotonic pattern that parsed as `HALT` near
   0x3600 and as `NOP`s elsewhere.  Reordered so `user_map_de` runs
   first, `pop af` happens just before the write.

3. **`pv_ptr_valid` rejected common-memory pointers**.  The bring-up
   sanity check dropped any pointer with high byte ≥ 0x80.  Since
   `&udata.u_page` is at 0xEExx on this platform, every call to
   `program_vectors(&u_page)` fell back to mapping the kernel and
   wrote the JP null_handler stubs into kernel page 0x48 instead of
   the new user page.  The first timer IRQ after `doexec` then tripped
   the null-pointer check (user 0x0000 was all zeros, not `0xC3`) and
   forced `_doexit(9)` = SIGKILL on PID 1.  High-byte test removed.

4. **Direct-IO path via `CONFIG_LARGE_IO_DIRECT`** fed IDE data
   straight into user memory through `map_proc_always`.  With the
   bugs above live, the transfer landed in kernel code in RAM and
   occasionally triggered wild IDE write bursts that corrupted the
   on-disk image across reboots.  Disabled for now — every block goes
   through the buffer cache and `uputblk`.

### Interrupt handling during bring-up

Interrupts are held masked.  `sprinter_bringup_int` replaces FUZIX's core
`interrupt_handler` in both the IM2 vector table at `0xFDFD` and the IM1
vector at `0x0038`.  The stub:

- Checks `udata.u_insys`.  If zero (user code was running) it jumps to
  the real `interrupt_handler` so the scheduler, signals and keyboard
  polling work.
- If non-zero (kernel/syscall in progress) it pins `_int_disabled = 1`
  and `reti` without re-enabling IFF1, to break the IRQ storm that
  FUZIX's normal dispatcher exit path (`xor a; ld (_int_disabled),a;
  ei`) causes against a level-sensitive ULA FRAME pin on Sprinter.

`plt_interrupt` advances `timer_interrupt()` and polls the PS/2 keyboard
on each accepted IRQ.  `plt_idle` polls `kbd_poll + timer_interrupt`
rather than `HALT`ing — with the bring-up dispatcher RETIing without EI,
a HALT here would wait for an IRQ that never dispatches.

CTC channels are reset at init so they cannot raise TINT.

### Safety net: disk writes disabled

`bdwrite` (in `devio.c`) and `_devide_write_data` (in `sprinter.s`) are
both no-op'd while `CONFIG_SPRINTER_EARLY_TRACE` is set.  Kernel code
cannot issue the IDE `0x30` write-sector command.  This kept the on-disk
image intact while the user-copy bugs above were being hunted; needs to
be restored once PID 1 is stable.

### Diagnostics still in place

Temporary instrumentation that should be removed once the kernel
stabilises:

- `crt0.s` paints the ZX border port (`0xFE`) at five points during
  startup and calls `early_banner` to write `CRT0` to VRAM.
- `start.c` dumps `udata.u_argn*` before and after `complete_init` and
  reads the just-written `/init` string back via `ugetc` (markers
  `0xCA` / `0xCB`).
- `syscall_exec16.c` dumps `udata.u_page[0..3]` at `_execve` entry
  (marker `0xED`), runs a `uputc 0xA5 + ugetc` sentinel probe (markers
  `0xDE` / `0xDF`), re-stages `/init\0` into user space before
  `n_open_lock` and verifies the loaded binary via ugetc at a few
  addresses (markers `0xB3 / 0xB0 / 0xB1 / 0xB2`).
- `FM_/DIO_/TD_/IDE_/EX_/PROC_TRACE` call sites feed a 512-byte circular
  trace buffer at `_sprinter_trace_buf` (16-bit index).  `_plt_trace`
  only writes to memory — it does not touch any border/VID port,
  because the 0xC0..0xCF range shares decoder bits with the WIN2 /
  banking registers.

### Rebuild Command

```sh
make diskimage TARGET=sprinter
```

Use `Images/sprinter/fuzix.img` (or `fuzix.chd`) produced by that build.

### Next targets

1. Silence / investigate the NMI that fires after `doexec` (Z84C15 WDT,
   ULA NMI, bus fault).
2. Re-enable the standard `interrupt_handler` exit path once the IRQ
   source is understood — ack ULA FRAME, restore `EI; RETI` so the
   scheduler can actually preempt.
3. Wire `/dev/console` through `devtty.c` so getty can open a terminal.
4. Remove the bring-up no-ops and trace markers once PID 1 reaches a
   login prompt.
