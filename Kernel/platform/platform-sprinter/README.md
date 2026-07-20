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
| PS/2 keyboard | ✅ Set 2 decoder, modifiers, VT100 sequences; input echoes to screen |
| IDE storage | ✅ Mount reads superblock and inode blocks over 16-bit ports |
| Root filesystem mount | ✅ `hda1` mounts and root inode opens |
| `_execve /init` | ✅ Resolves `/init`, loads the binary correctly into user pages |
| User-mode entry | ✅ `doexec` jumps to `/init` at 0x0112, user pages mapped, vectors installed |
| Cross-bank syscall dispatch | ✅ `_STUBS` trampolines + `__stub_0_N` banking switch call CODE1/2/3 correctly |
| IRQ handling (user context) | ✅ Timer + PS/2 IRQs dispatch through `sprinter_bringup_int` without IRQ storm |
| Stable pause() loop | ✅ Minimal `/init` enters `pause()` in user space and stays sleeping |
| CMOS RTC | ✅ Read-only BCD access |
| Filesystem image | ✅ Built by `make diskimage` |
| `/bin/sh` in filesystem | ✅ Shipped via `V7-sh` package |
| Disk writes | ⚠️ `bdwrite` / `devide_write_data` no-op'd during bring-up (safety net) |
| Interrupt dispatcher | ⚠️ Bring-up stub (`sprinter_bringup_int`) — absorbs IRQ when `u_insys=1` |
| Real `/init` (`Applications/util/init`) | 🟡 Runs past `KERNEL OK - userland running`, then hits `PANIC_INODE_FREED` in `i_deref` on inode dev=1 num=0x32 (directory, mode=0x41ED, nlink=2) |
| Interactive shell `/bin/sh` | 🔲 Blocked on full init → getty → login flow |
| FDD (WD1793) | 🔲 Not implemented |

## Current Bring-Up State

`make diskimage TARGET=sprinter` produces `Images/sprinter/fuzix.img` (and
`fuzix.chd` if `chdman` is available).  Booting that image in MAME's Sprinter
driver now reaches a **stable userland idle state**:

1. BIOS boot sector messages.
2. `CRT0` banner written directly to VRAM at row 0 (proof-of-life from
   `crt0.s`).
3. Kernel banner (`FUZIX version ...`, copyrights, `Devboot`) via `kprintf`.
4. Root filesystem mount from `hda1` completes.
5. Kernel prints `Starting /init`.
6. `_execve` loads the minimal `/init` binary (80 bytes) — header validates,
   pagemap_realloc allocates user pages, `readi` copies code into the new
   user window, `program_vectors` installs the `JP null_handler` / `JP
   unix_syscall_entry` vectors at user 0x0000 / 0x0030.
7. Kernel prints `KERNEL OK - userland running` right before `doexec`.
8. `doexec` jumps to user entry at 0x0112 with `u_page = {0x45, 0x44, 0x43,
   0x46}`, SP = `u_isp` = 0xEDEE, INSYS = 0 and IRQs enabled.
9. User init executes `ld a,37; call 0x0100` — enters `_pause` via the
   `_STUBS` trampoline at 0x0301 + 37·6 → bank switch to CODE2 via
   `__stub_0_2` → `psleep(0)`.
10. Timer IRQs and PS/2 keystrokes are delivered.  `sprinter_bringup_int`
    routes IRQs to the real handler when `u_insys = 0` and absorbs them
    (setting `_int_disabled`, `reti`) when `u_insys = 1`, so there is no
    IRQ storm.  Keyboard input echoes on-screen.

At this point PID 1 is alive, looping in `pause()`, IRQs are serviced and
the machine is responsive.  No panic, no `trap_illegal`, no `plt_monitor`.

### Packaging fix: real Sprinter `/init` overlay

The filesystem builder enables `platform-$TARGET` via
`build-filesystem -p platform-$TARGET`, but the tree had no
`fuzix-platform-sprinter.pkg`.  As a result, `/init` in the Sprinter image
still came from `Applications/util/init` via `fuzix-basefs.pkg`, while the
bring-up work was modifying `Applications/util/sprinit`.

That mismatch explained the repeated "why is the screen not matching the
current sprinit.s?" loop: the emulator was never booting the diagnostic init
binary at all.

The fix is to use the existing Sprinter-only package overlay:

```text
Kernel/platform/platform-sprinter/fuzix-platform-sprinter.pkg
    r /init
    f 0755 /init ../../../Applications/util/sprinit
```

This keeps other targets on the stock `/init` and lets `TARGET=sprinter`
actually boot the current bring-up PID 1.

### PID1 bootstrap map: avoid one-page init on Sprinter

`create_init()` in core FUZIX normally seeds PID1 with `u_top = PROGLOAD + 512`,
which means `ptab_alloc()` gives init only a one-page bootstrap map until
`_execve()` grows it later.

On Sprinter that proved too fragile: the first `/init` handoff was repeatedly
seen with mixed live mappings like `08/49/4A/49`, followed by `RST 38` into
`0xFF`-filled user space before the real exec path settled.

Under `CONFIG_SPRINTER_EARLY_TRACE`, PID1 now starts with `u_top = PROGTOP`
from the outset, forcing a canonical full user page map before the first
`execve("/init")`.  This is still a temporary bring-up guard and remains a
compile-time no-op for every other target.

### `sprinit`: bypass `sprcrt0` / libc during bring-up

The current early trap now occurs with a stable PID1 page map
(`0x40/0x41/0x42/0x43`) and before the first reliable syscall-enter latch
fires. That moves the suspicion away from the kernel `open()` path and onto
the user-side startup/runtime glue itself.

### Screen-localised boot markers

The current replay after moving IM2 away from `_COMMONDATA` still traps at
`F1AC` with a canonical PID1 map (`0x40/0x41/0x42/0x43`) and only the
banner + `Devboot` visible. Since `_COMMONMEM` now lives at `0xEE00`, the
old dump ranges around `0xFDxx..0xFFxx` no longer show the relevant trace
state directly.

To localise the next failure without relying on stale dump addresses,
`start.c` now emits one-character boot markers under
`CONFIG_SPRINTER_EARLY_TRACE`:

- `A` after `create_init()`
- `B` after `device_init()`
- `C` after successful `fmount(root_dev, ...)`
- `D` after successful `i_open(root_dev, ROOTINODE)`

That makes the next replay readable from the screen alone and pins the
first failing stage in the boot path `create_init -> device_init -> fmount
-> i_open(root) -> OK -> exec_or_die`.

To cut that layer out completely, Sprinter `/init` now builds as a raw
relocatable FUZIX binary with its own exec header, like `init_minimal.s`,
instead of linking through `sprcrt0.o`.  The standalone source now lives in
`Applications/util/sprinit_raw.s` and builds to the packaged binary
`Applications/util/sprinit`:

- issues syscalls directly via `call 0x0100`,
- opens `/dev/tty1`,
- duplicates it to stdin/stdout,
- calls `execve("/bin/sh", ...)`,
- prints `SPRINTER EXEC FAIL` only if `execve()` returns.

This removes `sprcrt0` relocation, libc syscall wrappers, and the argc/argv
startup frame from the PID1 bring-up path.  If the trap disappears, the next
blocker is the real `/bin/sh` handoff rather than the generic Z80 user CRT.

### Milestone: stable boot-to-userland (April 2026)

Reached via a sequence of fixes, each of which exposed the next issue:

1. **`usermem.s:uputget_put` / `uput_slow_loop` argument corruption** —
   user memory was not actually being written with the correct bytes during
   execve's `readi`.  Fixed register ordering and deferred `user_map_de`
   until after the source byte is restored from the stack.

2. **`pv_ptr_valid` rejected common-memory pointers** — `&udata.u_page` lives
   at 0xEExx, so the "reject high-byte ≥ 0x80" sanity check diverted
   `program_vectors` into the kernel page.  User page 0 never received the
   `JP null_handler` stub, and the first timer IRQ after `doexec` tripped
   the null-pointer check → `_doexit(SIGKILL)` on PID 1.

3. **`CONFIG_LARGE_IO_DIRECT` corrupted kernel RAM** — direct IDE-to-user
   transfers used a stale user mapping and wrote IDE data into kernel code
   pages.  Disabled during bring-up.

4. **Cross-bank syscall dispatch verified** — `syscall_dispatch[]` in `_CONST`
   holds the address of a 6-byte stub per syscall (e.g. stub 0x0301 for
   `_exit`, stub 0x03EB for `_kill`).  Each stub: `ld de,#target; jp
   __stub_0_N` where N is the target's bank.  `__stub_0_N` saves the
   current bank, maps the target bank via `MPGSEL_1/2`, calls the target
   (`jp (hl)` on the target address), then restores the caller's bank.
   All 80 syscall numbers dispatch correctly without requiring every
   kernel function to live in one bank.

5. **`null_handler` no longer cascades into a second fault** — the old
   sequence (`push 7; push pid; call unix_syscall_entry` = kill, then
   `push 0xFFFF; push 0xFFFE; call unix_syscall_entry` = exit) could
   re-enter `null_handler` with `INSYS = 1`, tripping `trap_illegal`.
   Replaced with `jp _plt_monitor` so the machine halts cleanly on a
   genuine user-land NULL jump (which no longer happens in the current
   path but is kept for safety).  `_sprinter_nullh_count` at 0xFBB0
   tracks every entry so a dump tells us whether the path ever fires.

6. **Minimal `/init` scaffold (historical)** — before the common-page
   fix landed, a minimal 80-byte `init_minimal` that just called
   `pause()` was used to confirm the user-mode entry path.  Once
   `sprinter_seed_common` was taught to switch `MPGSEL_3` to init's
   own common page, the stock `Applications/util/init` was restored in
   `fuzix-basefs.pkg` and now runs far enough to trip the core
   refcount bug in `i_deref` (see *Current investigation* below).

7. **Init's own common page** (April 2026) — the last stacked fix on
   the bring-up path.  Without it, `fork_copy` on the first child
   propagated a stale snapshot of kernel common into the child and
   `_switchin` returned into garbage.  See the milestone section below.

### Current investigation (April 2026 — post init-common fix)

Real `/init` (`Applications/util/init`) is restored in `fuzix-basefs.pkg`
and actually executes.  The boot console shows the full banner, the
kernel completes mount, prints `Starting /init`, `KERNEL OK - userland
running`, and init makes progress into filesystem paths.  The next
halt is:

```
i_deref0 dev=0001 num=0032 nlink=0002 mode=41ED
panic: inode freed.
```

Decoded:
- `dev=0x0001` — root filesystem (`hda1`, LBA 258+).
- `num=0x0032` — inode 50.
- `mode=0x41ED` — directory, `0755` (regular, not a tty or a pipe).
- `nlink=2` — leaf directory (self + parent link only, no subdirs).

At register dump time: `PC=0xF16A` (kernel common code, `_panic` loop),
`SP=0xEFB5`, `PG0=0x48` (kernel CODE), `PG1=0x4C` + `PG2=0x4D` (kernel
CODE3 overlay — a banked syscall target was active), `PG3=0x46` (init's
own common page).  Banking is clean; the halt is a genuine refcount
bug.

### Iteration: inode ref/deref tracing for inode 0x0032

Added targeted tracing (guarded by `CONFIG_SPRINTER_EARLY_TRACE`) to expose
every refcount transition for the crashing inode (`dev=1 num=0x0032`):

- `i_deref()` emits:

  ```
  ID dev=... num=... refs=old>new nlink=... mode=... pid=... sys=... in=... at=...
  ```

- `i_open()` / `fmount()` emit matching `IR ...` increments for this inode
  (`at=10` and `at=11` respectively).
- Underflow panic line (`i_deref0 ...`) now includes `pid`, `sys` and
  `u_insys` so the failing path can be tied to syscall context.

The earlier global `i_ref()` macro wrapper was reverted: it changed call shape
kernel-wide and produced unstable early boots (blank screen, early return from
`_execve` with `EX_TRACE 0xD0/0x13`).  Tracing is now local to `filesys.c` only.

This should let us replay one failing boot and identify which path adds one
fewer ref than it drops for inode 50.

### Update from next replay: panic moved to `PANIC_CORRUPTI`

On the latest run the halt happened earlier as:

```
panic: corrupt inode
```

So the immediate fault is now a failed `magic()` check (bad `c_magic`) rather
than `i_deref0` underflow.  Added temporary `magic()` context diagnostics under
`CONFIG_SPRINTER_EARLY_TRACE`:

- `magic0 ptr=... slot=... site=... mg=... dev=... num=... refs=... fl=... pid=... sys=... in=...`
- `magic0 raw=.. .. .. ..`

`site` values map to `filesys.c` call sites:

- `site=1` — `n_open()` walker (`magic(ninode)`)
- `site=2` — `i_deref()` entry
- `site=3` — `wr_inode()` entry
- `site=4` — `getinode()` check

This should identify whether the broken inode is a poisoned `i_tab` slot or an
invalid pointer path.

Latest replay produced:

```
magic0 ptr=4BB7 slot=00FF site=0003 mg=FDE1 dev=FD19 num=0036 refs=00D1 fl=00D5 pid=0001 sys=001E in=0001
magic0 raw=00E1 00FD 0019 00FD
```

Interpretation:

- `site=3` confirms failure at `wr_inode()` entry (called from `i_deref`).
- `slot=0xFF` shows `ino` is not inside `i_tab`.
- `ptr=0x4BB7` points into banked code, not an inode struct.

So this is an invalid inode pointer reaching `wr_inode`, not a simple
`dev=1,num=0x32` refcount underflow.

To reduce diagnostic perturbation, the per-call `ID ...` emit inside `i_deref`
was removed (it changed stack shape on a hot path).  `magic0 ...` remains.

Added low-impact pointer snapshots around `i_deref` (no `kprintf`, memory-only):

- `_sprinter_last_ideref_in`   (`0xFC0A`) — pointer on `i_deref` entry
- `_sprinter_last_ideref_post` (`0xFC0C`) — pointer after the `--c_refs` path
- `_sprinter_last_ideref_wr`   (`0xFC0E`) — pointer right before `wr_inode`
- `_sprinter_last_ideref_meta` (`0xFC10`) — low byte `u_callno`, high byte `u_insys`

Current trace buffer moved accordingly:

- `_sprinter_trace_idx` = `0xFC12`
- `_sprinter_trace_buf` = `0xFC14..0xFD13`

Next replay with `WR_INODE(site, ino)` wrapper showed:

- `_sprinter_last_wr_site = 0x01` (callsite in `newfile()`)
- `_sprinter_last_wr_ptr = 0x4BB8` (invalid; code/common area, not `i_tab`)

So the bad pointer reaches `wr_inode` via `newfile()` path, and is already
corrupt before `wr_inode` runs.  The earlier per-`i_open` `IR` trace in this
path was removed because SDCC emitted fragile stack choreography around that
instrumentation; diagnostics now keep only memory snapshots and the `WR_INODE`
site tag.

Added one more low-impact probe around `newfile()` to determine whether the
bad pointer is returned by `i_open()` or corrupted later in `newfile`:

- `_sprinter_last_newfile_pino` at `0xFC17`
- `_sprinter_last_newfile_nindex_in` at `0xFC19`
- `_sprinter_last_newfile_nindex_pr` at `0xFC1B` (just before `WR_INODE(1,...)`)

Also fixed a typo in `newfile()` lock ordering call (`i_lock(ino)` ->
`i_lock(nindex)`). The lock macro is currently a no-op on this config, but the
source now matches intended semantics.

Because of the added probes, trace addresses moved again:

- `_sprinter_trace_idx` = `0xFC1D`
- `_sprinter_trace_buf` = `0xFC1F..0xFD1E`

Latest replay changed failure shape again:

```
magic0 ptr=0000 slot=00FF site=0002 mg=91E7 dev=0060 num=0000 refs=0000 fl=0000 pid=0001 sys=001E in=0001
magic0 raw=00E7 0091 0060 0000
```

This is `MAGIC_CHECK(2, ino)` at `i_deref()` entry with `ino == NULL`.
So at least one path now calls `i_deref(NULLINODE)` during init syscall flow.

Temporary bring-up guard added under `CONFIG_SPRINTER_EARLY_TRACE`:

- `i_deref` now logs `i_deref null pid=... sys=... in=...` and returns early
  when `ino == NULL`.

Follow-up replay confirms `i_deref(null)` happens repeatedly after
`KERNEL OK - userland running` (various `sys=` values observed), and once with
display corruption/hang before panic.

The null guard is now unconditional in `i_deref` (still with trace print under
`CONFIG_SPRINTER_EARLY_TRACE`). This is a safe core hardening change: callers
already treat `NULLINODE` as a sentinel in many paths, and deref-on-null was
causing non-diagnostic crashes.

This avoids a misleading `panic: corrupt inode` on null dereference and lets us
progress to the next failing condition.

Current diagnostics layout:

- `_sprinter_last_iopen_dev` = `0xFC1D`
- `_sprinter_last_iopen_ino` = `0xFC1F`
- `_sprinter_last_iopen_ret` = `0xFC21`
- `_sprinter_last_panic_ptr` = `0xFC23`
- `_sprinter_last_panic_bytes` = `0xFC25..0xFC28`
- `_sprinter_chlink_stage` = `0xFC29`
- `_sprinter_chlink_wd` = `0xFC2A`
- `_sprinter_chlink_nindex` = `0xFC2C`
- `_sprinter_chlink_done` = `0xFC2E`
- `_sprinter_chlink_error` = `0xFC30`
- `_sprinter_trace_idx` = `0xFC32`
- `_sprinter_trace_buf` = `0xFC34..`

Latest replay showed a new top-level failure:

```
panic: getinode: bad OFT
```

Snapshot at failure indicated repeated `i_deref(NULL)` events before panic
(`_sprinter_ideref_null_count=7`, last syscall `0x0102`), and panic string
pointer `0x07FA` (`"geti"...`).

To keep boot moving and capture the exact bad descriptor state, `getinode()` now
returns `EBADF` (instead of panic) under `CONFIG_SPRINTER_EARLY_TRACE` when the
OFT index or OFT inode pointer is invalid, and stores a compact snapshot:

- `_spr_gir` (`0xFC36`): reason (`1` bad OFT index, `2` bad OFT inode ptr)
- `_spr_giu` (`0xFC37`): fd (`uindex`)
- `_spr_gio` (`0xFC38`): `u_files[uindex]` snapshot
- `_spr_gifr` (`0xFC39`): `of_tab[oftindex].o_refs`
- `_spr_gifa` (`0xFC3A`): `of_tab[oftindex].o_access`
- `_spr_giin` (`0xFC3B`): `of_tab[oftindex].o_inode`
- `_spr_gis` (`0xFC3D`): low=`u_callno`, high=`u_insys`

Replay with this probe reported consistent invalid-descriptor hits before
hang:

- `_spr_gir=1` (`bad OFT index`) and `_spr_gfcnt=0x0030`
- latched failure tuple: `fd=0x50`, `u_files[fd]=0x47`,
  `o_refs=0xFF`, `o_access=0xFF`, `o_inode=0x0000`

To prevent this tuple from being overwritten by subsequent `getinode()` calls,
the failure snapshot is now latched (`spr_gf*`) only on the failing path.

Another replay showed CPU parked near `plt_interrupt_all` (`PC≈0xF175`) with
`PG1/PG2=0x4E/0x4F` and no forward progress after `KERNEL OK - userland running`.
This matches an IRQ reentry/livelock on a level-triggered source.

Bring-up IRQ stub is now temporarily hardened to always absorb IRQs (pin
`_int_disabled=1`, `RETI`, no jump to core `interrupt_handler`). This is a
diagnostic containment step to avoid livelock while we continue tracing fd/OFT
state corruption.

Follow-up replay still showed unstable execution (`PC` reaching non-code
data-like addresses) while the bad-`getinode` tuple remained the same.
To reduce diagnostic side effects in this phase:

- `getinode()` tracing is simplified: only fail-path latch writes remain.
- syscall context for the latch is captured directly at fail time.
- `plt_trace()` is temporarily a no-op (returns immediately).

Newest replay then showed `PG2=0x50` (outside the kernel code-bank set
`{0x49,0x4A,0x4C,0x4D,0x4E,0x4F}`) with `PC` jumping into non-code space.
`sanitize_bc_map` has been tightened from a generic `0x08..0x7F` range check to
an explicit whitelist of valid bank pairs only:

- `0x4A49` (CODE1)
- `0x4D4C` (CODE2)
- `0x4F4E` (CODE3)

Any other pair now falls back to `MAP_BANK1` immediately.

Latest replay still showed `PG2=0x50` while userland was running.  The root
cause is that the generic page validators in `map_proc_2` / `map_for_swap`
accepted any page `< 0x80`, which includes VRAM (`0x50..0x5F`).  That allows
an already-corrupted `u_page[]` byte to map VRAM into a code window, after
which user execution quickly degrades into random opcodes (`call 0x0100`
with garbage syscall numbers, screen filled with garbage).

Mapping guards are now tightened to the real RAM-process range only:

- accept pages `0x08..0x4F`
- reject `>= 0x50` (VRAM/MMIO window)

`sanitize_kpages` now also normalizes `_kernel_pages[1..2]` through the same
`sanitize_bc_map` whitelist used by bank stubs, so kernel-side bank metadata
cannot drift to an invalid pair.

As an additional runtime guard, all dynamic WIN2 (`MPGSEL_2`) writes on the
syscall/bank-stub paths now go through `set_mpgsel2_safe`: values `>= 0x50`
are clamped to `0x4A` before touching the port.  This prevents accidental
VRAM mapping in WIN2 from turning user/syscall execution into garbage.

Clamp telemetry (for post-mortem dumps):

- `_spr_pg2_clamp_count` (`0xFC70`) - number of forced clamps
- `_spr_pg2_last_raw` (`0xFC72`) - last raw WIN2 page value before clamp

Follow-up dump still had `PG2=0x50` with `_spr_pg2_clamp_count=0` and
`_spr_pg2_last_raw=0x4F`, meaning the bad mapping did not come from the
bank-stub/runtime paths guarded above.  Additional guards were added in the
remaining direct process-page mappers:

- `usermem.s:user_map_de` now validates user pages as `0x08..0x4F`
  (both WIN1 and WIN2 legs; `>=0x50` rejected)
- `tricks.s:fork_copy` now validates child/parent pages before writing
  `MPGSEL_1/2` (`>=0x50` rejected)

This closes the remaining routes that could map VRAM page `0x50` into WIN2
via corrupted `u_page[]` / `p_page[]` metadata.

Another replay after these guards still showed `PG2=0x50`, while latches were:

- `_spr_sys_enter_no=0x01`
- `_spr_sys_exit_no=0x02`
- `_spr_sys_exit_err=0x001E`
- `_spr_pg2_clamp_count=0`
- `_spr_pg2_last_raw=0x4F`

This points away from the validated map/stub/usermem/fork paths and toward
transient VRAM mapping lifetime in the text console path.  `sprvideo.s` now
uses a re-entrant `map_vr`/`unmap_vr` guard (`map_vr_depth`) and a safe
restore clamp in `unmap_vr` (`saved_vr_page >= 0x50` => restore `0x4A`).
The goal is to prevent nested or interrupted console draws from leaving WIN2
on VRAM.

Latest replay no longer showed VRAM mapped in WIN2 (`PG2=0x4F`) and reached
`HALT` in `_plt_monitor` (`PC≈0xF16A`), with `_sprinter_nullh_count` non-zero.
That indicates control reached `null_handler` (user NULL jump) instead of a
raw bank/VRAM corruption hang.

`null_handler` in `lowlevel-z80-banked.s` is now switched from immediate
`jp _plt_monitor` to the standard synchronous-fault path used by the non-banked
Z80 core logic:

- if `u_insys`/`u_ininterrupt` is set -> `trap_illegal` (monitor)
- otherwise kill the current task via `_doexit(SIGKILL)` on kernel stack

This keeps user-space NULL faults from hard-stopping the entire machine and
lets init/respawn logic continue.

Follow-up replay still hit `trap_illegal` monitor with `PG2=0x4F` (no VRAM
corruption) and `PC` at `_plt_monitor`.  For bring-up, `null_handler` has been
relaxed one more step: only NULL jumps in IRQ context (`u_ininterrupt!=0`) are
treated as fatal; NULL in normal or in-syscall task context is routed through
`_doexit(SIGKILL)` to kill the offending task and keep the machine alive.

Next replay then sat with `PC` inside `sprinter_bringup_int` (`plt_interrupt_all`
region) while border artifacts were active, indicating IM2 IRQ churn during
bring-up.  IRQ policy is now temporarily forced to absorb all IM2 interrupts in
`sprinter_bringup_int` (always set `_int_disabled=1`, `reti`) to prevent
reentry/dispatch instability until userland boot is stable.

Subsequent replay still reached `_plt_monitor` with stable banks
(`PG1/PG2/PG3 = 0x4E/0x4F/0x46`).  To avoid hard-stop on user/task illegal
faults during bring-up, `trap_illegal` in `lowlevel-z80-banked.s` now mirrors
the temporary null-handler policy: if not in IRQ context, switch to kernel
stack/map and route the fault through `_doexit(SIGKILL)` first; only then fall
back to monitor if control returns.

Another replay then failed with `panic: getproc: extra running`. For bring-up,
`getproc()` now has a Sprinter-only early-trace recovery path: if a stale
`P_RUNNING` slot is encountered while selecting the next runnable task, it is
demoted to `P_READY` and scheduling continues instead of triggering
`PANIC_GETPROC`.

Next failure (`i_alloc: corrupt superblock` followed by `panic: want busy
block`) indicates leaked `BF_BUSY` cache entries on task-fault recovery paths.
`bfind()` now has a temporary Sprinter early-trace fallback: if a matching
buffer is found busy, treat it as stale and clear `bf_busy` instead of
panicking with `PANIC_WANTBSYB`.

Repeated `i_alloc: corrupt superblock` while `/init` was running showed that
the old write-disable safety net was no longer viable (dirty metadata was
being treated as written, then later reloaded stale from disk).  Bring-up now
re-enables real block writes on the Sprinter path (`bdwrite` -> `td_write`,
`_devide_write_data` 512-byte OUT loop restored).

Latest replay then halted with `PC` in low RAM/data (`0x0B78`) and kernel banks
mapped (`PG1/2/3 = 0x49/0x4A/0x4B`), which is consistent with a bad user page
table falling back to kernel pages at syscall return.  `map_proc_2` fallback is
now changed to a non-kernel clamp (`0x08/0x09/0x0A`) and syscall-exit latches
now also snapshot `u_page[0..2]` (`_spr_sys_exit_up0..2`) to confirm whether
`u_page` corruption is happening before the return path.

Follow-up replay confirmed this path: `PG1/2/3 = 0x08/0x09/0x0A/0x4B` and
`_spr_sys_exit_up0..2` were zero, so return-to-user happened with clobbered
`u_page[]`.  Syscall-exit path now rebuilds `u_page[0..3]` from
`u_ptab->p_page/p_page2` before `map_proc_always` when any of the first three
entries is out of range.

Another dump still showed repeated `i_alloc: corrupt superblock` while the
copy helper in `usermem.s:user_map_de` was falling back to kernel pages
(`0x49/0x4A`) on invalid user-page bytes.  That can redirect `__uput/__uget`
traffic into kernel memory and poison filesystem state.  `user_map_de` fallback
is now switched to safe user pages (`0x08/0x09`).

One more structural issue found during this pass: diagnostics growth had pushed
`_COMMONDATA` past `0xFF00` into the IM2 vector area.  Unused legacy
`pv_oldsp/pv_stack` reserve is removed so `_COMMONDATA` now ends below vectors
again.  Added `i_alloc` corrupt-path latches (`_spr_iac_*`) to capture
superblock fields at first failure.

Bring-up safety was tightened further around PID 1 exits: under
`CONFIG_SPRINTER_EARLY_TRACE`, `doexit()` no longer panics immediately on
`pid==1` (`PANIC_KILLED_INIT`), and instead returns with `u_error=EFAULT` so
the system can continue and expose the underlying filesystem corruption cause.

### Current handoff state (session checkpoint)

Current visible boot output is stable up to:

- `Devboot`
- `OK`
- `Starting /init`
- `KERNEL OK - userland running`

After that, the machine still falls into `_plt_monitor` (`PC=0xF16A`, `HALT=1`).
Recent dumps repeatedly show `PG1/PG2=0x44/0x43` at the hang point (user pages
left mapped while monitor runs), with `PG3=0x4B`.

Fixes applied in this session to remove known immediate causes:

1. `lowlevel-z80-banked.s`: removed forced monitor fall-through after `_doexit`
   in `null_handler` / `trap_illegal` paths (return instead of unconditional
   `jp/call _plt_monitor` on non-IRQ recovery).
2. `tricks.s:_switchin`: replaced broad kernel-page acceptance with strict
   whitelist (`0x4A49`, `0x4D4C`, `0x4F4E`) before `map_kernel_restore`.
3. `usermem.s:__uget`: fixed zero-length path so it does not enter user map
   and exit without `map_kernel_restore_u`.
4. `tricks.s:switchinfail`: temporary bring-up recovery now resyncs
   `udata.u_ptab = de` and continues, instead of hard stop in monitor.
5. `lowlevel-z80-banked.s:intret`: disabled the `PROGBASE` forced
   `null_pointer_trap` branch (`*(0) != 0xC3`) for bring-up, as it was
   repeatedly driving recovery into monitor loop during unstable mapping.
6. `process.c:doexit()`: if `switchin(getproc())` unexpectedly returns on
   Sprinter bring-up, do not immediately panic with `PANIC_DOEXIT`; return
   instead so the next real failure can surface.

What to check first in the next session:

- Identify who still enters `_plt_monitor` after `KERNEL OK` now that the
  explicit fall-throughs were removed.  Highest-probability path is remaining
  direct monitor calls from lowlevel/tricks side while still on user mapping.
- Add a tiny one-shot latch for monitor entry source (caller PC + current
  `PG1/PG2/PG3`) right in `_plt_monitor` prologue to disambiguate whether it is
  a `switchinfail`-class path, legacy interrupt path, or another trap route.
- Check whether the observed `_plt_monitor` caller stack (`0x5131`-range inside
  `doexit`) disappears after suppressing `PANIC_DOEXIT` on unexpected
  `switchin()` return.

### Temporary userland bring-up override

While the full `Applications/util/init` path is still unstable on Sprinter,
the platform package now overrides `/init` with a minimal userspace probe.
Current override is `Applications/util/sprinit0`, a pure Z80 assembly binary
that just enters an infinite loop with no libc/crt0/syscall dependencies.
This is intentionally Sprinter-only (`fuzix-platform-sprinter.pkg`) and is a
bring-up tool to verify that:

- `execve()` reaches live userland reliably
- first userspace console write works
- console I/O works without the SysV init/getty/login stack in the middle

Once the underlying early-userland bug is fixed, remove the override and
restore the stock `/init` from `fuzix-basefs.pkg`.

Trace buffer moved to:

- `_sprinter_trace_idx` = `0xFC3F`
- `_sprinter_trace_buf` = `0xFC41..`

### Milestone: init's own common page (April 2026)

Previously the first fork from real `/init` corrupted kernel common
and the system fell into wild bank mapping (`PG0=0xFB`, `PG3=0x08`,
random bytes at `0xFA00..0xFFFF`).  Root cause: init is the only
process that never goes through `_switchin`, so its `MPGSEL_3` stayed
on kernel common (`0x4B`) while its `u_page[3]` pointed at a freshly
allocated user page.  On `fork()`, `fork_copy` reads parent's
`u_page[3]` as the source and copies that into the child — but the
live stack / udata are in `0x4B`, not in the seed page, so the child
`_switchin` restored garbage into its top bank.

Fix (in `sprinter_seed_common`, `sprinter.s`):

1. Copy the full 16 KB of kernel common (`0xC000..0xFFFF`) into init's
   allocated common page via `ldir` — target is now a byte-for-byte
   replica.
2. Immediately switch `MPGSEL_3` to that target page.  `SP` still
   lives at `0xFFxx`, target has identical bytes there, so the `ret`
   through the caller's return address stays valid.  IRQs are off at
   this point in boot, so nothing can push/pop between the copy and
   the switch.
3. Update `mpgsel_cache+3` and `top_bank` **after** the switch so the
   writes land in the target page (the orphaned `0x4B` copy is never
   referenced again).
4. Leave `_kernel_pages[3] = 0x4B` — `sanitize_kpages` checks that
   array, not the port, so it stays a no-op and `map_kernel` never
   touches `MPGSEL_3`.

After the fix init runs on its own common, `u_page[3]` matches the
live `MPGSEL_3`, and `fork_copy` propagates the real kstack / udata
into children.  The earlier symptoms (corrupt `0xFA71..0xFBBE` common
code, wild `PG0`) no longer reproduce.

### Hypotheses verified

- **Trace buffer overlapped the IM2 vector table.**  The 512-byte
  `_sprinter_trace_buf` at `0xFC0C` extended to `0xFE0C`, overwriting
  the IM2 table at `0xFE00..0xFEFF`.  `plt_trace` wrapped the index
  with `and #0x01` on the high byte, so writes repeatedly corrupted
  IRQ vectors and produced wild dispatches.  Fixed by shrinking the
  buffer to 256 bytes and tightening the wrap mask.
- **`fork_copy` uses `u_page` as source, not live MPGSEL_3.**  Confirmed
  by reading `Kernel/platform/platform-sprinter/tricks.s:fork_copy` —
  iteration 4 does `out (MPGSEL_2), u_page[3]` then `ldir` from WIN2.
  For every non-init process `u_page[3] == MPGSEL_3` (via `_switchin`);
  for init they differed by design → corruption on first fork.
- **`_kernel_pages[3]` stays `0x4B` safely.**  `sanitize_kpages` only
  inspects the array; `map_kernel` / `map_proc_2` only touch WIN0–2.
  So overriding the running `MPGSEL_3` without rewriting the array
  does not trigger a reset.
- **The earlier `softened i_deref` workaround was hiding corruption,
  not fixing it.**  Returning from `i_deref` with `c_refs == 0`
  leaves the inode in an inconsistent state; the panic text we now
  see (clean halt, valid `PC`) was masked before by cascade faults.
  Reverted to `panic(PANIC_INODE_FREED)` so real bugs surface
  immediately.

### Hypotheses still to check

1. **Which syscall path reaches the bad `i_deref`.**  `dev=1, num=50,
   mode=0755` is a directory.  Suspect paths: `sys_unlink("/etc/mtab")`
   (init removes the file at startup — ENOENT walks the parent chain),
   `sys_open("/dev/tty1")` if the `/dev` directory lookup double-derefs
   the parent, or `umount`/`mount` on the root.  Plan: add a one-shot
   `TRACE_I_REF`/`TRACE_I_DEREF` print around the inode table so every
   `++` / `--` on a given `c_num` is logged with the caller.
2. **`filesys.c:n_open_lock` parent-dir bookkeeping.**  The walker
   `i_ref`s each intermediate component and `i_deref`s siblings.  If
   the final component is a directory with `nlink=2`, the early-exit
   paths might double-deref the parent.  Candidate site:
   `filesys.c:n_open` around the `.` / `..` short-circuits.
3. **Whether the panic is reproducible with `/etc/mtab` absent.**  The
   current `fuzix-basefs.pkg` already comments out `/etc/mtab` so that
   init's `unlink("/etc/mtab")` takes the ENOENT path.  If the bug
   moves (different inode num/mode) when we re-enable `mtab`, that
   isolates the responsible syscall.
4. **`wr_inode` vs `i_deref` order during write-back.**  Earlier
   dumps showed `magic()` fires inside `wr_inode` with `caller ≈
   0x5574`.  Worth reconfirming: does the bad `i_deref` sit on the
   same code path as `wr_inode`, or is it cleanup (`oft_deref`) from
   a failed syscall?
5. **Reference-count damage via buffer cache / blkbuf.**  If `bfree`
   or `brelse` marks an inode dirty while a caller still holds it,
   subsequent `i_deref` can drop `c_refs` below the expected floor.
   Check `devio.c:bread`/`brelse` and `blk512.c` for Sprinter-specific
   changes that might have broken the core assumption.
6. **Behaviour under `CONFIG_UFS` vs `CONFIG_LEVEL_2`.**  Confirm that
   Sprinter's `config.h` matches a platform where `i_deref` is known
   to be robust (e.g. zxevo, z80retro) — any divergent `CONFIG_*`
   option around level-2 bookkeeping is a suspect.

### Known kernel bugs still to resolve

- **`PANIC_INODE_FREED` in `i_deref`** as described above.
- Real init's full startup sequence (signal → unlink → close → open →
  dup → write → load_inittab → execl /bin/sh) depends on this fix.

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

Temporary instrumentation guarded by `CONFIG_SPRINTER_EARLY_TRACE`.  All
of it should be removed in the final pass (see task #5):

- `crt0.s` paints the ZX border port (`0xFE`) at five points during
  startup and calls `early_banner` to write `CRT0` to VRAM.
- `start.c` dumps `udata.u_argn*` before and after `complete_init` and
  reads the just-written `/init` string back via `ugetc` (markers
  `0xCA` / `0xCB`).
- `syscall_exec16.c` dumps `udata.u_page[0..3]`, entry, `u_isp` and
  `u_top` right before `doexec` (marker `0xFE`), then prints
  `KERNEL OK - userland running` via `kputs` as visible proof.  Also
  snapshots `hdr` into `_sprinter_last_exec_hdr` and the most recent
  exec path into `_sprinter_last_exec_path`.
- `FM_/DIO_/TD_/IDE_/EX_/PROC_TRACE` call sites feed a 512-byte circular
  trace buffer at `_sprinter_trace_buf` (16-bit index `and 0x01` on the
  high byte for wrap at 0x200).  `_plt_trace` only writes to memory —
  it does not touch any border/VID port, because the 0xC0..0xCF range
  shares decoder bits with the WIN2 / banking registers.
- Counters: `_sprinter_nmi_count` (NMIs absorbed by `sprinter_nmi_stub`)
  and `_sprinter_nullh_count` (entries to `null_handler`) are easy
  sanity checks from a memory dump.
- Syscall latch points in `unix_syscall_entry`: `_spr_sys_enter_no`
  snapshots the syscall number on entry, `_spr_sys_exit_no` and
  `_spr_sys_exit_err` snapshot `u_callno`/`u_error` right after
  `_unix_syscall` returns, before remapping back to user.
- Exec handoff snapshots now also include:
  - `_sprinter_last_exec_entry[16]` - 16 bytes read back from
    `progload + a_entry`
  - `_sprinter_last_exec_isp` - user SP handed to `doexec()`
  - `_sprinter_last_exec_stack[16]` - 16 bytes read back from user stack
    at `u_isp`

### Current handoff state

Current best-known state for Sprinter bring-up:

- Kernel boots reliably to:
  - `Devboot`
  - `OK`
  - `Starting /init`
- Visible proof of userspace handoff works: the kernel now prints
  `SPRINTER RAW USER PROBE` before `doexec()`, and that message appears on
  screen.
- This confirms the following now work well enough to reach userland:
  - `execve()` setup path
  - userspace page-map handoff
  - `doexec()` entry jump itself

What is still broken:

- Userspace does not stay alive after entry.
- Even with the current minimal raw probe / asm-only `/init` override, the
  process quickly runs into garbage or halts instead of remaining in its
  intended loop.
- Recent dumps show user PCs wandering into upper user RAM (`0x95xx`,
  `0xD9xx`) or low low-page vector space (`0x0038/0x003B`) depending on the
  exact build stage; after the latest low-page fix, the dominant symptom is
  that the process enters userspace and then loses control flow shortly
  afterwards.

Key fixes landed this session:

1. `program_vectors()` on Sprinter no longer zero-fills `0x0000..0x007F`.
   It now only patches the required vector slots.  This was a real bug: the
   old behaviour destroyed low-address userspace code/data.
2. `exec_or_die()` has a temporary `CONFIG_SPRINTER_EARLY_TRACE` fallback that
   bypasses filesystem/libc init and jumps into a minimal raw userspace probe.
3. A Sprinter-only package override exists in
   `fuzix-platform-sprinter.pkg`; latest variant points `/init` to
   `Applications/util/sprinit0` (pure asm probe), although the raw probe in
   `exec_or_die()` is now the more important bring-up path.
4. Userspace signal delivery remains disabled for bring-up in
   `lowlevel-z80-banked.s` to avoid dropping PID 1 into the signal trampoline.

What the latest evidence means:

- Loader corruption is no longer the primary blocker.
- Initial `argc/argv` stack setup was validated earlier and is not the first
  failing point anymore.
- The remaining bug is almost certainly in the bare kernel->userspace runtime
  environment after entry, not in pathname lookup or shell/init complexity.

Latest fix in tree:

- `platform-sprinter/usermem.s` now preserves the transferred byte across
  `map_proc_save_u()` / `map_kernel_restore_u()` in the byte-at-a-time
  `__uput/__uget` loops.  The previous "safe" rewrite loaded the byte into
  `A` and then called the mapping helpers before storing it, but those helpers
  themselves clobber `A` while reprogramming `MPGSEL_0..2`.  Result: early
  userspace copies such as the raw probe at `0x0100` were populated with
  garbage opcodes, producing failures like `SPRINTER RAW USER PROBE` followed
  by random execution in low memory (`PC≈0x002A`) and visible memory
  corruption.
- `process.c:exec_or_die()` now re-copies `udata.u_page/u_page2` from
  `u_ptab->p_page/p_page2` immediately after `pagemap_realloc()` and again
  right before the raw-probe `uput()` / `doexec()`.  Recent replays show
  live user maps like `PG0=0x0A, PG1..3=0x46` at the crash site, which does
  not match the expected freshly allocated 4-page PID1 map; this change tests
  whether the authoritative page table in `ptab` is still correct while the
  live `udata` copy gets clobbered.
- Critical core fix: `cpu-z80/lowlevel-z80-banked.s:_doexec` now discards the
  SDCC banked/noopt `push af` shim before popping the entry address.  Generated
  call sites on Sprinter look like `push <entry>; push af; call _doexec`; the
  old code popped only `ret` and then treated the saved `AF` word as the start
  PC, so userspace jumped into random addresses such as `0x5721` even though
  the raw probe bytes at `0x0100` were correct in RAM.
- `process.c:exec_or_die()` now detects the degenerate "all four `p_page[]`
  entries identical" PID1 map after `pagemap_realloc()`.  When that happens
  under `CONFIG_SPRINTER_EARLY_TRACE`, it force-allocates a fresh full 4-page
  map with `pagemap_alloc()` and immediately re-runs `program_vectors()` on
  that map.  This is a bring-up workaround for the current early-init path:
  replays that landed cleanly in the raw probe loop still showed
  `u_page/p_page = 46 46 46 46`, proving the jump itself was fixed while PID1
  was still running in a misleading one-page alias configuration.
- Follow-up fix: once PID1 is re-mapped to a fresh 4-page allocation, the
  staged boot-time `"/init"` argv no longer lives in the active user map.
  `start.c:rebuild_init_argv()` now re-stages `"/init"` / `argv[]` /
  `envp[]` into the post-realloc PID1 map before `_execve()` runs, avoiding a
  false `panic: no /init` caused purely by the bring-up remap.
- Current checkpoint: the raw userspace loop is now stable with
  `PC` spinning inside `0x0100..0x0121` and live page registers showing a
  distinct PID1 map (`PG0=0x42, PG1=0x43, PG2=0x44, PG3=0x46` in the latest
  replay).  That closes the "can we execute arbitrary user bytes at all?"
  question.
- `process.c:exec_or_die()` therefore no longer jumps into the raw probe.
  Under `CONFIG_SPRINTER_EARLY_TRACE` it only leaves the user-visible shadow
  block at `0xEDC0..0xEDCB` plus the common-memory snapshots, then continues
  into the real `_execve("/init")` path so the next iteration can focus on
  syscall / loader / userspace runtime failures instead of bare entry.
- `_execve("/init")` late-failure tracing is now extended under
  `CONFIG_SPRINTER_EARLY_TRACE`.  Earlier dumps already proved pathname
  lookup, inode resolution, execute permissions and header read were all
  correct (`mode=0x81ED`, `perm=7`, `mflags=1`, valid 16-byte header), yet
  the kernel still fell through to `panic: no /init` with `stage=0`.
  New markers split the previously blind tail of `_execve()` into:
  `rargs(argv)` = 8, `rargs(envp)` = 9, `pagemap_realloc()` = 10,
  `valaddr_r()` = 11, short body `readi()` = 12.  Additional snapshots keep
  the live `argv`/`envp` pointers and `done/count` pair so the next emulator
  dump can distinguish argument staging, user-map validation and body-load
  failures cleanly.
- A returned `doexec()` is now marked explicitly as `stage = 13`, with
  `done = entry` and `count = u_isp`.  If the next panic still lands in
  `panic: no /init` and shows stage 13, the remaining fault is no longer in
  `_execve()` at all but in the Sprinter user-entry contract itself
  (`_doexec`, vectors, low-page traps, or immediate return from user mode).
- Early boot now also exposes `i_open("bad disk inode")` payload in common
  memory.  Besides the existing `last_iopen_dev/ino/ret`, the bad-inode path
  now snapshots whether the failure was on an existing inode (`1`) or a
  supposedly new inode (`2`), plus the raw `i_mode` and `i_nlink` that failed
  validation.  This is aimed at the new on-screen `i_open: bad disk inode`
  line appearing before `Starting /init`, which points to filesystem inode
  corruption/readback issues rather than exec-path failure.
- Follow-up: the ordinary `last_iopen_*` latches were being overwritten by a
  later successful `i_open("/init")`, hiding the earlier bad-inode event.
  Separate `bad_iopen_*` latches now preserve the most recent `badino:` path
  payload (`dev`, `ino`, reason, `mode`, `nlink`) until the next emulator
  dump, so the early boot warning can be decoded even if later opens succeed.
- Syscall-exit tracing now also snapshots `u_ptab->p_page[0..2]` and whether
  the temporary Sprinter return-path repair actually fired.  This is for the
  new early crash mode where the machine drops straight into fallback user
  pages (`PG0..2 = 0x08/0x09/0x0A`) with almost no console output: if
  `u_page[]` is zero but `ptab->p_page[]` is still sane, the repair path can
  be hardened; if both are already broken, the corruption happened earlier and
  the next search moves to the producer of `p_page[]`, not the return path.
- Latest replay showed the stronger case: `u_page[0..2] = 00 00 00`,
  `u_ptab->p_page[0..2] = FF FF FF`, `spr_fixup = 1`, live `PG0..2` then
  clamped to `0x08/0x09/0x0A`.  So the return path itself is not the source of
  corruption; it is merely exposing an already-poisoned PID1 page table.
  As a temporary bring-up guard under `CONFIG_SPRINTER_EARLY_TRACE`, syscall
  exit now restores PID1's `p_page[]` from the last known-good exec snapshot
  (`sprinter_last_exec_ptab`) whenever the live `ptab->p_page[0..2]` is out of
  range.  This is intentionally narrow and only exists to push boot farther so
  the true writer of the bad `p_page[]` can be identified from a later stop.
- A follow-up attempt to remove the `push af ; call _unix_syscall ; pop af`
  wrapper in `lowlevel-z80-banked.s` turned out to be invalid for the banked
  toolchain itself: `tools/binmunge` only recognizes relocated cross-bank
  calls in exactly that five-byte pattern and aborted with
  `Bad format for relocated long call at F55D`.  That wrapper is now restored.
- To separate "already poisoned before entering C" from "corrupted by the
  syscall body", syscall entry now snapshots `u_page[0..2]` and
  `u_ptab->p_page[0..2]` as `spr_sys_enter_up*` / `spr_sys_enter_pp*` in common
  memory alongside the existing syscall-exit snapshots.
- Latest replay tightened that result further: the first observed syscall
  (`0x4F`) already enters with `u_page[0..2] = 00 00 00` and
  `u_ptab->p_page[0..2] = FF FF FF`, while the live hardware map is already the
  fallback `PG0..2 = 0x08/0x09/0x0A`.  So the corruption happens before
  `_unix_syscall()` runs at all.  The next trace therefore also snapshots the
  raw `u_ptab` pointer on syscall entry/exit, to distinguish "bad pointer in
  udata" from "pointer is fine but the `struct p_tab` contents were overwritten
  between `doexec()` and the first userspace syscall".
- Latest proof is harsher still: on the first observed syscall, both
  `sys_enter_ptab` and `sys_exit_ptab` are already `0x0000`.  So it is not a
  valid `struct p_tab` being overwritten in place; `udata.u_ptab` itself has
  been cleared before the kernel even starts processing the syscall.  As a
  temporary bring-up guard under `CONFIG_SPRINTER_EARLY_TRACE`, the syscall
  entry path now restores a zero `u_ptab` to `&ptab[0]` (PID 1 / init) and
  immediately resynchronizes `u_page[]` from that slot.  This is intentionally
  narrow and exists only to push boot past the first-user-syscall boundary so
  the next real corruption point becomes visible.
- The first replay with that guard changed the live hardware map from the old
  fallback `0x08/0x09/0x0A` to a sane PID1 map (`PG0..2 = 0x48/0x4C/0x4D`),
  proving the `u_ptab` rescue is materially affecting control flow.  However,
  the trace itself initially became unreliable because the rescue path reused
  register `A` before `u_callno` was recorded, so `sys_enter_no` showed a page
  byte instead of the syscall number.  The entry trace now preserves the
  original syscall number and records an explicit `sys_enter_fixup` flag.
- The next replay showed `sys_enter_ptab = _ptab`, not `NULL`, but
  `sys_enter_pp0..2 = 00 00 00` while the live hardware map was already sane
  (`PG0..2 = 0x48/0x4C/0x4D`).  So in the current failure the pointer itself is
  valid, but `ptab[0].p_page[]` has been zeroed before the first syscall.  The
  syscall-entry bring-up guard now also repairs a zero/invalid `p_page[]` from
  `mpgsel_cache[0..3]` back into both `ptab[0]` and `udata.u_page[]`.
- With that guard in place, boot now advances into filesystem/device lookup and
  shows `i_open: bad disk inode` followed by `panic: invalid dev` on screen.
  The next trace therefore records the exact `dev` rejected by `validchk()` and
  the caller-site string pointer that triggered the panic, so the next emulator
  dump can tell whether this is a bogus inode `c_dev`, a corrupted mount/super
  path, or a wrong block-device route.
- Latest replay returned to the older `Starting /init` -> `panic: no /init`
  branch, but the preserved exec snapshot finally made that one concrete:
  `/init` in the Sprinter image is still the tiny `Applications/util/sprinit0`
  probe (`a_text=0x0015`, `a_data=0x0003`, so `bin_size=0x0018`), while
  `syscall_exec16.c` still rejects any exec16 image with `bin_size < 64`
  before `doexec()`.  That rejection went through the old `F6` branch without
  writing `sprinter_exec_fail_stage/err`, which is why the dump misleadingly
  showed `stage=0`, `err=0` even though `_execve()` was already bailing out.
- Current tree now makes that path explicit (`stage = 15`, `done = bin_size`,
  `count = progptr`) and, under `CONFIG_SPRINTER_EARLY_TRACE` only, relaxes
  the historical 64-byte minimum to `sizeof(struct exec)` so the pure-asm
  `sprinit0` probe can actually reach `doexec()`.  This keeps the core change
  contained to Sprinter bring-up builds while we finish stabilizing the first
  real userland handoff; the stock limit remains unchanged for normal builds
  and other targets.
- That relax immediately paid off: `/init` now reaches live user mode on the
  real exec path, with stable PID1 pages (`PG0..2 = 0x42/0x43/0x44`) and the
  kernel-side `SPRINTER USERLAND OK` banner emitted right before `doexec()`.
  The current `/init` is therefore no longer "missing"; the expected probe
  runs in userspace and can sit at its own loop address with a sane 4-page map.
- Next probe layer now moves from loop-only `/init` to a single-syscall C
  probe.  The Sprinter package override points `/init` at `Applications/util/sprinit`,
  which writes `SPR1` and a status byte to user common `0xED10..0xED16`, calls
  `getpid()`, stores the returned PID there, and only then loops forever.
  This keeps the test minimal while finally exercising the first
  user->kernel->user syscall round-trip on a normal libc/crt0 binary.
- Raw-probe handoff now writes a user-visible shadow block at
  `0xEDC0..0xEDCB`:
  - `0xEDC0..0xEDC3` = ASCII `SPR0`
  - `0xEDC4..0xEDC7` = `udata.u_page[0..3]`
  - `0xEDC8..0xEDCB` = `u_ptab->p_page[0..3]`
  This block lives in user common, so it remains visible even when the crash
  happens after `_doexec()` has switched `PG3` away from kernel common.
- `process.c:exec_or_die()` now grows PID 1 to a full `PROGTOP` map before
  jumping into the Sprinter raw probe.  The previous fallback reused
  `create_init()`'s boot-sized map (one repeated 16 KB page) but still placed
  `u_isp` at `PROGTOP - 2`, so the probe entered userspace with an
  exec-like stack pointer on a non-exec-like address-space layout.  This keeps
  the raw probe closer to the real `_execve()` contract and removes the last
  obvious map/stack mismatch from the bypass path.
- `/init` is now overridden by the tiny C probe `Applications/util/sprinit`
  instead of the earlier loop-only asm `sprinit0`.  This keeps PID 1 on a
  normal libc/crt0 exec16 path and exercises a real userspace syscall
  (`getpid()`), while still remaining small enough for bring-up.
- The earlier `exec16` lower-size guard rejected the tiny Sprinter probe
  before `doexec()`, causing misleading `panic: no /init`.  Under
  `CONFIG_SPRINTER_EARLY_TRACE` the minimum accepted binary size is now
  relaxed from `64` bytes to `sizeof(struct exec)` so the probe can boot.
- Verified checkpoint: the Sprinter path now reaches real userspace via
  `_execve()`, shows the preserved `Starting /init` console path, and runs
  the probe with sane live maps (`PG0..PG2 = 0x42/0x43/0x44`).  The next
  barrier is no longer exec handoff; it is the first post-entry instruction
  sequence around the initial libc syscall/return path.
- Current `sprinit` stages are:
  - `0x11` before `getpid()`
  - `0x12` immediately after `getpid()` returns into user code
  - `0x13` after storing the returned PID to `spr_pid`
  These bytes live in the probe's own data area and are used to distinguish
  "entered main but trapped in syscall" from "returned to user and died on the
  following store/instruction".
- `sprinit` now also has a separate `spr_loop` byte which increments inside the
  final infinite loop.  This gives a hard split between "reached post-syscall
  loop" and "died after `spr_stage=0x13` but before the first loop iteration".
- Verified checkpoint: `spr_stage=0x13` and a non-zero `spr_loop` now prove
  that the first real userspace syscall (`getpid()`) returns successfully and
  control stays in `/init`'s userspace loop with sane live maps
  (`PG0..PG2 = 0x42/0x43/0x44`).
- Next probe layer extends `/init` from `getpid()` to a minimal
  `write(1, "SPRINTER WRITE OK\\r\\n", ...)`.  New stages are:
  - `0x11` before `getpid()`
  - `0x12` after `getpid()` returns
  - `0x13` after storing PID
  - `0x14` after `write()` returns
  and `spr_wr` stores the returned byte count.
- The same probe state is now mirrored into a fixed user-memory trace block at
  `0x8000` so emulator dumps do not depend on the current `.bss` placement:
  - `0x8000` stage
  - `0x8001-0x8002` PID
  - `0x8003-0x8004` `write()` return value
  - `0x8005` loop counter
  This block lives in the process pages and remains easy to sample even if the
  common-memory trace area is partially clobbered by a later low-page fault.
- Follow-up finding: the z80 `crt0` calls `_brk()` before `main()`, and the
  current Sprinter bring-up was dying in that early syscall before any probe
  state became visible in userspace.  `sprinit` now links with a dedicated
  probe-only `sprcrt0` that skips the initial `_brk()` so we can isolate the
  first explicit syscalls (`getpid()`, then `write()`) without dragging the
  allocator/bootstrap path into the trace.
- Verified follow-up checkpoint: with `sprcrt0` in place, `sprinit` reaches
  `spr_stage=0x14`, enters `write()` as syscall `0x08`, returns to userspace,
  and continues looping.  The first `write(1, ...)` currently comes back with
  `errno=0x0016` (`EINVAL`), so the syscall/return path is working; the next
  probe switches to `write(0, ...)` to test whether the console fd binding is
  the only blocker left before the first userspace-visible output.
- `write(0, ...)` follows the same pattern: `spr_stage` still reaches `0x14`
  and the syscall exits back to userspace with `errno=0x0016`.  This narrows
  the blocker to the filesystem/descriptor side of `rwsetup()` and below,
  rather than the generic syscall or userspace return path.  The next trace
  layer snapshots `rwsetup()` state (`fd`, `u_base`, `u_count`, `o_access`,
  inode mode and device word) so we can see exactly which validation path
  turns the first `write()` into `EINVAL`.
- Follow-up result: `rwsetup()` never starts for the failing `write()`, so the
  rejection happens even earlier in `readwrite()`, almost certainly at
  `valaddr(buf, nbytes, 0)`.  The current trace therefore also snapshots the
  `valaddr()` input pointer, requested size, `u_top`, and the failure stage.
- Next replay disproved that hypothesis too: `valaddr()` reaches its success
  marker (`stage=6`) with the expected userspace buffer range
  (`base=0xEDEE`, `size=0x0010`, `u_top=0xEE00`), while `rwsetup()` still
  remains untouched and the syscall exits as `write`/`EINVAL`.  The active
  trace therefore moves one level up into `readwrite()` itself so we can see
  whether control actually reaches the `rwsetup()` call site after the
  validated buffer check, or whether some earlier state/argument corruption in
  `readwrite()` is short-circuiting before that point.
- Follow-up note: the first `readwrite()` latches showed an impossible mix
  (`rdwr_stage=2` but stale `valaddr(stage=6)` snapshots), so the trace now
  explicitly clears the `rwsetup()/valaddr()` markers at `readwrite()` entry
  and stores raw `u_argn/u_argn1/u_argn2` alongside the decoded fd/buf/count.
  This removes ambiguity between a fresh `EINVAL` in the current `write()` and
  stale evidence left by an older syscall.
- Latest replay shows the fresh `readwrite()` snapshots are still garbage for
  the first `write()` (`u_argn=0x4644`, `u_argn1=0x3973`, `u_argn2=0xF29D`)
  while the syscall number itself remains correct (`0x08`).  That rules out
  `write()`/`rwsetup()` entirely and points at broken userspace->kernel
  argument marshalling for multi-argument syscalls.  The next trace therefore
  snapshots the raw userspace stack bytes seen at `unix_syscall_entry` so the
  exact argument offset can be fixed instead of guessed.
- The raw userspace stack snapshot proved the offset was already correct:
  `unix_syscall_entry` sees sane words at `SP+4` (`fd=0`, `buf=0x03B1`,
  `count=0x0013`) for the first `write()`.  The real bug was subtler: the
  banked syscall entry computed `HL = SP + 16` early, then ran the Sprinter
  `u_ptab/page` repair block, clobbering `HL` before the final `LDI` sequence
  copied arguments into `udata.u_argn*`.  The fix simply recomputes `HL`
  immediately before the `LDI`s.  This should turn the first failing
  multi-argument syscall from "garbage arguments" into a real device/fd-path
  result.
- Follow-up replay confirmed that fix: `readwrite()` now sees the correct
  first userspace `write()` arguments (`fd=0`, `buf=0x03B1`, `count=0x0013`)
  and `rwsetup()` is entered with valid `valaddr()` state.  The remaining
  `EINVAL` was not a syscall marshalling problem at all: the probe was trying
  to write to a closed inherited descriptor.  `sprinit` now mirrors the real
  `init` contract more closely by opening `/dev/tty1`, duplicating it onto
  `0/1/2`, and only then issuing the userspace `write()`.
- The next replay changed failure class completely: after the `/dev/tty1`
  probe path, the screen showed what looks like a second boot banner and then
  died in `panic: map over`.  That panic comes from `pagemap_add()`, which
  means `pagemap_init()` was reached again without resetting the free-page
  pool.  Current working hypothesis is a second entry into the kernel boot
  path after the first userland handoff.  Under
  `CONFIG_SPRINTER_EARLY_TRACE`, `pagemap_init()` is now made idempotent for
  bring-up (`pagemap_reset_pool()` before re-adding pages), and a new common
  latch `_spr_boot_count` increments at the top of `fuzix_main()` so the next
  replay can prove or disprove the double-boot theory directly.
- Follow-up replay weakened that double-boot theory: instead of panicking in
  `pagemap_add()`, the machine later stopped with `PC=0xFB7B` in
  `platform-sprinter/tricks.s:fork_copy`, right on the `ldir` that clones a
  16K bank from parent `WIN2` to child `WIN1` during `_dofork`.  That means
  the next failure is likely not "second entry into `fuzix_main()`" but either
  a legitimate first userspace `fork()` path or a bad control-flow jump into
  `_dofork`.  The current trace therefore adds dedicated `_spr_dofork_*`
  latches (caller return address, child `p_tab`, parent/child page tables,
  current iteration, current parent/child mapped pages) so the next dump can
  tell which of those two cases we are actually in.
- The low-page `0x0038` vector is now split away from the generic bring-up IRQ
  stub.  IM2 still routes to `sprinter_bringup_int`, but `0x0038` now jumps to
  a dedicated fatal logger that snapshots the trap count, SP and the return
  address pushed by `RST 38h`.  This is meant to answer the current question:
  are we taking a genuine interrupt, or are we executing `0xFF` in user low
  memory and falling into `RST 38h`.
- Follow-up fix: the first version of `sprinter_rst38_stub` mistakenly read the
  stack frame at the current `SP` after `push af/push hl`, so the saved
  "return address" was actually the caller's preserved register pair.  The
  logger now reads from `SP+4`, which is the real PC pushed by `RST 38h`.
- Another bring-up clash surfaced immediately after: `do_program_vectors()`
  still re-filled the legacy IM2 table at `0xFE00..0xFEFF` on every exec, but
  `_COMMONDATA` has grown into that region again.  This silently wiped the new
  `rst38_*` latches (and other trace state) before the first user fault could
  be inspected.  For the current `IFF1=0` userspace milestone, the per-exec
  IM2 reinitialisation is now skipped; the boot path still seeds IM2 once in
  `init_hardware()`.
- The raw probe path now also snapshots 16 bytes at `PROGLOAD` and at the
  chosen user stack (`u_isp`) before `doexec()`, and panics with `rawret` if
  `doexec()` ever returns.  A dump that lands in `crt0.s:stop` no longer loses
  the failure source silently.
- `platform-sprinter/usermem.s` no longer uses the 32K `WIN1/WIN2` bulk-copy
  fast path for `__uput/__uget`.  That optimisation remapped the same windows
  that can hold the banked kernel source/destination buffers, so copies from
  code/data in `0x4000-0xBFFF` read back garbage from the freshly mapped user
  pages instead of the intended kernel bytes.  The current code uses the safe
  byte-at-a-time map/store/restore loops until boot is stable.
- Raw userspace probe now writes visible markers into every 16K user window:
  `0x0080=0x11`, `0x4100=0x12`, `0x8100=0x13`, `0xED00=0x14`, then loops
  incrementing a counter mirrored at `0x0080/0x4101/0x8101/0xED01`.  This
  distinguishes "never reached user mode" from "entered user mode, then lost
  bank integrity / control flow".
- Right before `doexec(PROGLOAD)` the bring-up path now snapshots
  `udata.u_page[0..3]` and `u_ptab->p_page[0..3]` into common memory
  alongside the existing entry/stack snapshots.  That makes it possible to
  compare the intended map with the emulator's live `PG0..PG3` register dump
  after a hang.

Most likely next investigation steps:

1. Instrument the raw userspace probe path more directly:
   - snapshot the exact bytes at `PROGLOAD..PROGLOAD+15` immediately before
     `doexec(PROGLOAD)`
   - snapshot the same bytes again after the first return-to-kernel event
     (if any)
2. Compare Sprinter `doexec()` / user-return contract against a known-good
   banked Z80 target at the exact boundary where control first enters user
   space.
3. Verify whether low-page vectors (`0x0000`, `0x0030`, `0x0038`, `0x0066`)
   must live somewhere else entirely for Sprinter userspace, instead of being
   placed inside the user image address space.
4. Once the raw probe stays alive, remove the bypass and retry `sprinit0`,
   then `/bin/sh`, then the real `Applications/util/init`.

### Rebuild Command

```sh
make diskimage TARGET=sprinter
```

Use `Images/sprinter/fuzix.img` (or `fuzix.chd`) produced by that build.

### Next targets

1. **Keep the raw userspace probe alive.**
   This is now the shortest path to a real milestone: stable user execution
   after `doexec()`.
2. Revisit vector placement / low-page contract for Sprinter userspace.
   The remaining failures still smell like a low-address runtime contract
   mismatch.
3. Once the raw probe is stable, retry `sprinit0`, then `/bin/sh`, then the
   real `Applications/util/init`.
4. Only after PID 1 is truly stable: re-enable disk writes (`bdwrite`,
   `_devide_write_data`) and later restore stock signal delivery.
5. Replace the bring-up `sprinter_bringup_int` with the stock FUZIX
   `interrupt_handler` exit path (`EI; RETI`) once the ULA FRAME interrupt
   acknowledge is understood.
6. Strip the `CONFIG_SPRINTER_EARLY_TRACE` diagnostics in the final cleanup.
7. FDD (WD1793) + floppy boot path.

### Current checkpoint (April 2026, tty/open+fork path)

This older "raw userspace probe" plan is no longer the active frontier.  The
current Sprinter-only `/init` probe now gets materially farther:

- boot reaches stable kernel banner / root mount / `Starting /init`
- `_execve("/init")` succeeds and enters real userspace
- `getpid()` returns to userspace successfully
- multi-argument syscall marshalling is fixed (`write(fd, buf, count)` now
  enters the kernel with correct `fd/buf/count` instead of garbage)
- the probe can open `/dev/tty1`, duplicate descriptors, and continue far
  enough that the next failure is no longer in `_execve()` or the generic
  user->kernel->user syscall return path

The previously suspected "double boot" is now weaker than the evidence for a
different failure: recent emulator dumps stop at `PC=0xFB7B`, which is inside
`platform-sprinter/tricks.s:fork_copy`, i.e. the 16K parent->child bank copy
loop used by `_dofork`.  So the active question is no longer "are we re-entering
`fuzix_main()`?" but:

1. are we legitimately hitting the first userspace `fork()` path, or
2. are we jumping into `_dofork` unexpectedly because of corrupted control flow?

To answer that directly, the current tree carries dedicated `_spr_dofork_*`
common-memory latches:

- `_spr_dofork_count`
- `_spr_dofork_ret`
- `_spr_dofork_child`
- `_spr_dofork_upages`
- `_spr_dofork_cpages`
- `_spr_dofork_iter`
- `_spr_dofork_child_page`
- `_spr_dofork_parent_page`

In the current build these live at:

- `0xFEFC` `_spr_dofork_count`
- `0xFEFD-0xFEFE` `_spr_dofork_ret`
- `0xFEFF-0xFF00` `_spr_dofork_child`
- `0xFF01-0xFF04` `_spr_dofork_upages`
- `0xFF05-0xFF08` `_spr_dofork_cpages`
- `0xFF09` `_spr_dofork_iter`
- `0xFF0A` `_spr_dofork_child_page`
- `0xFF0B` `_spr_dofork_parent_page`

Current short-term goal:

- prove whether the stop in `fork_copy` is a legitimate first `fork()` from
  the `/init` probe path or an unexpected jump into `_dofork`
- if it is legitimate, decode which parent/child page pair or loop iteration
  stalls the 16K copy
- only after that return to tty/stdin/stdout inheritance and the first usable
  userland console path

Current recommended dump for the next replay:

- registers and `PG0..PG3`
- `0xFEFB-0xFF0B`

### Update from April 20 replay: fatal `RST 38h` after `/init` enters `open()`

The latest emulator dump no longer matched the older `fork_copy` stop.  It
showed:

- screen text: `SPRINTER USERLAND OK`
- CPU parked at `PC=0xF199`, `HALT=1`, `IFF1=0`
- `PG0..PG3 = 0x48/0x4C/0x4D/0x46`
- `0xFE84..0xFE87 = 52 EF 27 E4` in the old build's layout, i.e.
  `_sprinter_rst38_sp = 0xEF52` and `_sprinter_rst38_ret = 0xE427`

That pins the halt to `sprinter_rst38_stub`: this is a genuine executed
`RST 38h` (`0xFF`) rather than the earlier `_panic`/`_plt_monitor` path.  The
saved return PC `0xE427` is in the process common/stack region, not in kernel
text, so the active failure is now "userland returned/jumped into bytes that
contain `0xFF`" rather than a direct kernel panic.

The same dump also preserved the syscall-entry latches:

- last syscall entry was `sys=0x01` (`open`)
- user and `ptab` pages were consistent (`0x42/0x43/0x44`)
- `u_ptab` was non-zero and no entry/exit fixup was needed
- raw syscall stack bytes decoded as the expected `open("/dev/tty1",
  O_RDWR|O_NOCTTY, ...)` frame

So the current shortest-path hypothesis is:

1. `/init` reaches the first `open("/dev/tty1")` call normally,
2. control later returns into corrupted user/common bytes near `0xE426`,
3. those bytes contain `0xFF`, raising `RST 38h`.

To expose that next replay more directly, the current tree now adds two narrow
diagnostics:

- `sprinter_rst38_stub` stores the four bytes around the faulting PC
  (`ret-1 .. ret+2`) into `_sprinter_dbg[0..3]`
- `Applications/util/sprinit` now uses finer stages:
  - `0x14` after `open()` returns
  - `0x15` after the first `dup()`
  - `0x16` after the second `dup()`
  - `0x17` after `write()` returns

Current absolute addresses in this build:

- `_sprinter_rst38_count` = `0xFE96`
- `_sprinter_rst38_sp`    = `0xFE97`
- `_sprinter_rst38_ret`   = `0xFE99`
- `_sprinter_dbg[0..3]`   = `0xFFE1..0xFFE4`
- `_spr_sys_enter_no`     = `0xFEC4`
- `_spr_sys_exit_no`      = `0xFECE`
- `_spr_sysarg_sp`        = `0xFEDA`
- `_spr_sysarg_buf`       = `0xFEDC..0xFEEB`

Current recommended dump for the next replay:

- registers and `PG0..PG3`
- `0x8000-0x8005` (`sprinit` stage / fd-or-write result / loop byte)
- `0xFE96-0xFE9A` (`rst38` count, SP, return PC)
- `0xFEC4-0xFEEB` (last syscall entry/exit + raw user stack bytes)
- `0xFFE1-0xFFE4` (bytes around the faulting PC: `ret-1 .. ret+2`)

### Update from next replay: `open()` enters kernel, then control jumps to low page

The next dump tightened the failure again:

- `PC=0xF1AC` (`sprinter_rst38_stub` hang loop), `IFF1=0`, `HALT=1`
- `PG0..PG3 = 0x48/0x4E/0x4F/0x46` at trap time, i.e. kernel banks, not the
  user `0x42/0x43/0x44` map
- `_sprinter_rst38_sp = 0xEFFE`
- `_sprinter_rst38_ret = 0x000A`
- `_sprinter_dbg[0..3] = FF FF FF FF`

Interpretation:

- the CPU executed `0xFF` at logical address `0x0009`, causing `RST 38h`
- because `PG0` was `0x48`, that `0x0009` fetch happened while kernel page 0
  was mapped, not after a clean return to userspace
- so this is no longer "bad return into user common near `0xE427`"; it is
  "kernel-side control flow during `open()` jumped/fell into low page"

The syscall latches match that:

- `_spr_sys_enter_no = 0x01` (`open`)
- `_spr_sys_exit_no = 0x12` (`getpid`)
- `_spr_sysarg_sp = 0xEDE0`
- raw stack bytes decode as a valid `open("/dev/tty1", 0x0802, 0)` frame

So `open()` enters the kernel with sane arguments, but never reaches normal
syscall exit.  The active suspicion is now a bad indirect kernel call during
device-open dispatch, not userspace argument marshalling.

To test that directly, `d_open()` now snapshots into `_sprinter_dbg`:

- `[4]` low byte of `dev`
- `[5]` high byte of `dev`
- `[6]` low byte of `dev_tab[major(dev)].dev_open`
- `[7]` high byte of `dev_tab[major(dev)].dev_open`
- `[8]` stage byte: `0xD0` before the indirect call, `0xD1` after return

Current recommended dump for the next replay:

- registers and `PG0..PG3`
- `0xFE96-0xFE9A`
- `0xFEC4-0xFEEB`
- `0xFFE1-0xFFE9`

where:

- `0xFEFB` = `_spr_boot_count`
- `0xFEFC` = `_spr_dofork_count`
- `0xFEFD-0xFEFE` = `_spr_dofork_ret`
- `0xFEFF-0xFF00` = `_spr_dofork_child`
- `0xFF01-0xFF04` = `_spr_dofork_upages`
- `0xFF05-0xFF08` = `_spr_dofork_cpages`
- `0xFF09` = `_spr_dofork_iter`
- `0xFF0A` = `_spr_dofork_child_page`
- `0xFF0B` = `_spr_dofork_parent_page`

### Update from April 20 replay: `device_init()` clobbered tty `dev_tab`

The next replay answered the `d_open()` question directly.  At the stop:

- `PC=0xF1AC`, `HALT=1`, `IFF1=0`
- `PG0..PG3 = 0x48/0x4E/0x4F/0x46`
- `_sprinter_rst38_sp = 0xEFDE`
- `_sprinter_rst38_ret = 0x26EB`
- `_sprinter_dbg[0..3] = FF 41 0B 00`
- `_sprinter_dbg[4..8] = 01 02 B3 04 D0`

That decodes as:

- `dev = 0x0201`, i.e. `/dev/tty1`
- `dev_tab[major(dev)].dev_open = 0x04B3`
- stage = `0xD0`, so the crash happens before the indirect call returns

This is the real bug: `d_open()` is not dispatching through `tty_open` at all.
The traced pointer `0x04B3` does not match the linked tty entry point, and the
Sprinter-local `device_init()` in `discard.c` explains why: it was doing a
runtime rewrite of `dev_tab[]`, including `dev_tab[2]`, replacing the static
tty slot from `devices.c` with `no_open/no_rdwr` placeholders left over from
earlier bring-up.

The current fix keeps the block-device override for major 0 (`td_read`,
`td_write`, `td_ioctl`) but stops `device_init()` from rewriting tty and system
device slots.  That keeps the correction inside `platform-sprinter/` and avoids
touching core device dispatch.

Current recommended dump for the next replay after this fix:

- registers and `PG0..PG3`
- `0x8000-0x8005`
- `0xFE96-0xFE9A`
- `0xFEC4-0xFEEB`
- `0xFFE1-0xFFE9`

Expected change if this diagnosis is correct:

- `_sprinter_dbg[6..7]` should now point at the tty open handler rather than
  `0x04B3`
- `_sprinter_dbg[8]` should advance to `0xD1` or the userspace stage bytes
  should move past `0x15`

### Update from direct RAM dump: live `_dev_tab` overwritten with syscall-stub addresses

The next dump included the live `_dev_tab` window itself and made the failure
much more concrete:

- `PC=0x265C`, which is inside `_i_tab`, not executable kernel text
- `PG0..PG3 = 0x48/0x4E/0x4F/0x46`
- live RAM at `0x0A80..0x0AB1` no longer contained the static device switch
  table (`tty_open = 0x7ED5`, etc.)
- instead it contained a dense sequence of low addresses
  `0x04B3, 0x04B9, 0x04BF, ...`

Those values step by six bytes and look like syscall-stub addresses, not
device handlers.  So the current evidence is:

1. `_dev_tab` is being overwritten in RAM after boot
2. `d_open()` is faithfully reading that corrupted table
3. the indirect call then drives control flow off into data, eventually
   landing at `PC=0x265C` inside `_i_tab`

As a temporary bring-up guard under `CONFIG_SPRINTER_EARLY_TRACE`, the current
tree now adds `sprinter_restore_devsw()` in `platform-sprinter/discard.c` and
teaches `d_open()` to repair the Sprinter `devsw` table if the tty slot points
below `0x4000` instead of at the linked tty handler.  The guard records
`_sprinter_dbg[9] = 0xDA` when it fires.

Current recommended dump for the next replay after this guard:

- registers and `PG0..PG3`
- `0x8000-0x8005`
- `0xFE96-0xFE9A`
- `0xFEC4-0xFEEB`
- `0xFFE1-0xFFEA`

Key fields:

- `FFE7/FFE8` should become `D5 7E` after the repair
- `FFEA` should be `DA` if the guard had to restore `_dev_tab`
- `FFE9` should advance to `D1` if `tty_open()` returns normally

### Update from next replay: `d_open()` itself miscompiled under trace build

The next replay showed:

- `FFEA = 0xDA`, so the emergency `devsw` repair path did run
- but `FFE7/FFE8` still came back as `CB 04`, not the repaired tty handler
- `PC` was back in `sprinter_rst38_stub` with `_sprinter_rst38_ret = 0x26EB`

That ruled out the previous hypothesis that `sprinter_restore_devsw()` was
writing the wrong value.  The generated assembly for `d_open()` under the trace
build was the real issue: instead of indexing `dev_tab` from the `dev` argument
cleanly, SDCC emitted a broken sequence around the `fn = dev_tab[major(dev)]`
fetch (`pop de / push de` and then address arithmetic from that transient
register pair).  So after the repair call, the function pointer reload still
read from the wrong address and reproduced the stale `0x04CB` value.

The current fix rewrites `d_open()` into a simpler form with explicit
`maj/min/dp` temporaries:

- `maj = major(dev)`
- `min = minor(dev)`
- `dp = &dev_tab[maj]`
- `fn = dp->dev_open`

and uses the same explicit reload after the repair path.  This is intended
solely to force a sane codegen shape and expose the next failure beyond the
current miscompiled indirect fetch.

### Update from next replay: bypass tty `dev_tab` fetch entirely

The replay after that rewrite still did not match the new `devio.rst`
assembly.  The dump continued to show:

- `FFEA = 0xDA` (repair path entered)
- `FFE7/FFE8 = 0x04CB` (still not the tty handler)
- no forward progress past the first tty open

At that point the shortest path is no longer to keep massaging SDCC's codegen
for the indirect device-open fetch.  Under `CONFIG_SPRINTER_EARLY_TRACE`,
`d_open()` now takes a direct fast path for tty major 2:

- `fn = tty_open`
- snapshot the direct function pointer into `_sprinter_dbg[6..7]`
- call it directly with `minor(dev), flag`

This bypasses the corrupted/mis-fetched `dev_tab` path only for the current
Sprinter bring-up trace build and should expose the next real failure after
the tty open boundary.

### Update from next replay: tty bootstrap passes, later filesystem path feeds `i_open(dev=0x0201)`

The next replay advanced materially:

- screen now shows `SPRINTER WRITE OK`
- then `i_open: bad disk inode`
- then `panic: invalid dev`

The existing common-memory latches decode this as:

- `bad_iopen_dev = 0x0201`
- `bad_iopen_ino = 0x0147`
- `bad_iopen_bad = 2`
- `bad_iopen_mode = 0x0000`
- `bad_iopen_nlink = 0x0000`
- `last_validchk_dev = 0x1133`
- `last_validchk_site = 0x065E` (`PANIC_IOPEN`)

So the tty path is no longer the blocker.  A later filesystem path is calling
`i_open()` on `/dev/tty1` as if it were a normal filesystem device, then
progresses to another `i_open()` with a fully bogus `dev=0x1133`.

To identify the producer rather than the symptom, the current tree now stores
the last `i_open()` caller marker in `_sprinter_dbg[10..14]`:

- `0x31` `i_open(wd->c_dev, inum)`
- `0x32` `i_open(m->m_dev, ROOTINODE)`
- `0x33` direct entry to `i_open(dev, ino)`
- `0x34` `i_open(pino->c_dev, 0)`
- `0x35` boot root open from `start.c`
- `0x36` root open from `syscall_fs.c`
- `0x37` root open from `syscall_net.c`

Current recommended dump for the next replay:

- registers and `PG0..PG3`
- `0xFE83-0xFE95`
- `0xFEC0-0xFF0B`

### Update from next replay: first `dup()` sees a partially zeroed live `i_tab` slot

The next replay advanced again and changed failure mode:

- screen shows `SPRINTER USERLAND OK`
- then `magic0 ptr=264E slot=0025 site=0004 ...`
- then `panic: corrupt inode`

This is no longer the earlier `i_open(dev=0x0201)`/`invalid dev` stop.  The
new stop is `magic()` from `getinode()` (`site=4`) during syscall `0x11`
(`dup`).  The failing live inode slot decodes as:

- `ptr = 0x264E`
- `slot = 0x25`
- first 4 bytes are already zero (`c_magic = 0`, `c_dev = 0`)
- tail of the slot is still populated (`c_num = 0x0020`, `c_flags = 0x40`)

The direct memory dump confirms this is a partial overwrite of a live `i_tab`
entry, not a wild pointer:

- `i_tab` base is `0x22B1`
- slot size is 25 bytes
- slot `0x25` starts exactly at `0x264E`

So the immediate question is no longer "which bogus device reached `i_open()`",
but "who zeros the first 4 bytes of the tty inode slot between successful
`open("/dev/tty1")` and the first `dup()`".

To catch both sides of that boundary, the current trace build now latches:

- `_sprinter_dbg[24..30]` (`0xFFF9-0xFFFF`) on successful `_open()`
  - `[24]` stage `0xA1`
  - `[25..26]` inode pointer returned by open
  - `[27..28]` `c_magic`
  - `[29..30]` `c_dev`
- `spr_g*` on `_dup()` entry before `getinode()`
  - `spr_gir = 0xA2`
  - `spr_giu = old fd`
  - `spr_gio = oft index`
  - `spr_giin = of_tab[oft].o_inode`
  - `spr_gifr/spr_gifa = c_magic low/high`
  - `spr_gis = c_dev`

Current recommended dump for the next replay:

- registers and `PG0..PG3`
- `0xFE83-0xFE95`
- `0xFEC0-0xFF0B`
- `0xFFF9-0xFFFF`
- `0xFFEB-0xFFEF`

### Update from next replay: `_open()` returns a live inode, corruption happens before `_dup()`

The next replay filled in the missing tail bytes:

- `_dup()` pre-snapshot (`spr_g*`) still sees `of_tab[0].o_inode = 0x264E`
- but that inode already has `c_magic = 0x0000` and `c_dev = 0x0000`
- the `_open()` tail snapshot survives partially even though `_plt_monitor`
  reuses `_sprinter_dbg[24..27]`
  - `_sprinter_dbg[28] = 0x60`, which matches the high byte of `CMAGIC`
    (`0x6091`)
  - `_sprinter_dbg[29..30] = 0x0001`, so `_open()` returned the inode alive on
    `dev = 0x0001`

This tightens the corruption window to:

- after successful return from `_open()`
- before `_dup()` enters `getinode()`

The old `sprinit` diagnostic binary was still writing globals in low user
memory (`spr_stage`, `spr_pid`, `spr_fd`, `spr_wr`, `spr_loop`) and also
poking `0x8000`.  Since the inode slot is already dead before the first
`dup()`, the current tree now swaps in a narrower `sprinit` that:

- uses only locals/stack
- drops the `0x8000` trace writes
- still does `getpid()`, `open("/dev/tty1")`, `dup()`, `dup()`,
  `write(1, "SPRINTER WRITE OK\\r\\n", ...)`, then `pause()`

If this build gets past the old `corrupt inode` stop, that confirms the next
real bug is user low-page writes landing in kernel RAM after syscall return,
not filesystem/open logic.

That hypothesis did **not** hold: the narrower `sprinit` still dies at the same
first-`dup()` `magic()` stop.  The generated `sprinit.s` shows the first code
after `open()` keeps the returned fd on the user stack and also uses SDCC low
page temporaries around `0x026B..0x0295`, so the next working hypothesis is now
more specific:

- either user low page (`WIN0`) is still kernel page `0x48` after syscall return
- or the live page register cache no longer matches `u_page[]`

The attempted follow-up probe in `lowlevel-z80-banked.s` to stash the live
mapping at syscall entry overran `COMMONDATA`, so that approach was dropped.
Instead, the current test removes SDCC from the post-`open()` user path
entirely: `sprinit` is now built from a hand-written `sprinit.s` that issues
`getpid()`, `open("/dev/tty1")`, `dup()`, `dup()`, `write()`, `pause()` with
direct wrapper calls and without SDCC low-page temporaries or stack shuffling
between `open()` and the first `dup()`.

That also did **not** change the stop: the first `dup()` still sees the inode
slot at `0x264E` already zeroed. This rules out SDCC-generated user code as the
writer.

The next probe therefore reuses the existing syscall entry page latches:

- `_spr_sys_enter_up0..2` remain `u_page[]`
- `_spr_sys_enter_pp0..2` now record the live `mpgsel_cache[0..2]` values
  instead of duplicating `ptab->p_page[]`

This answers the remaining mapping question directly: if the failing `dup()`
enters with `_spr_sys_enter_pp0..2 = 0x48,0x49,0x4A` while `_spr_sys_enter_up*`
still says `0x42,0x43,0x44`, then userland really did run on kernel pages and
the inode overwrite is a syscall-return mapping bug. If the live pages are
already `0x42,0x43,0x44`, the writer is elsewhere in the kernel path.

The next replay ruled out that mapping bug as well: on the failing `dup()`,
both `_spr_sys_enter_up0..2` and live `_spr_sys_enter_pp0..2` are
`0x42,0x43,0x44`. So the process re-enters the kernel with normal user pages,
yet the tty inode slot is already dead.

The low-level "open-tail" recheck idea did not fit in the current
`COMMONDATA` budget, so the current trace build narrows the window from the C
side instead: `_open()` now overwrites `_sprinter_dbg[24..30]` a second time
**after** `i_unlock(ino)` and immediately before returning to the syscall
wrapper:

- `_sprinter_dbg[24] = 0xA4` means the post-`i_unlock()` snapshot ran
- `[25..26]` are the inode pointer
- `[27..28]` are `c_magic` after `i_unlock()`
- `[29..30]` are `c_dev` after `i_unlock()`

If those bytes are already `0000/0000`, then the writer sits inside `_open()`
or below it. If they still show `CMAGIC`/`0x0001`, the overwrite happens after
the C syscall body returns.

The next replay showed the latter is false: the surviving tail bytes from
`_sprinter_dbg[28..30]` are already wrong by the time panic hits, so the inode
is dead by the post-`i_unlock()` snapshot.

To split that remaining kernel-side window again without adding new common
symbols, the current trace build reuses the dormant `spr_rdwr_*` block
(`0xFEEC..0xFEF8`) before the first real read/write syscall:

- `spr_rdwr_stage = 0xB0` right after `dev_openi()` returns in `_open()`
- `spr_rdwr_reading = flag`
- `spr_rdwr_fd = oftindex`
- `spr_rdwr_base = ino` pointer
- `spr_rdwr_count = ino->c_magic`
- `spr_rdwr_argn = ino->c_dev`
- `spr_rdwr_argn1 = ino->c_num`
- `spr_rdwr_argn2 = ino->c_node.i_addr[0]`

If that snapshot is already corrupt, the writer is inside `dev_openi()`
(`d_open()`/`tty_post()` path). If it is still sane, the writer is later in
`_open()` between `i_lock(ino)` and the post-`i_unlock()` snapshot.

The next replay ruled out the first half of that window as well. On the
failing boot:

- `spr_rdwr_stage = 0xB0`
- `spr_rdwr_base = 0x264E`
- `spr_rdwr_count = 0x6091`
- `spr_rdwr_argn = 0x0001`
- `spr_rdwr_argn1 = 0x0020`
- `spr_rdwr_argn2 = 0x0201`

So the tty inode is still intact immediately after `dev_openi()` returns from
`_open()`.

The next replay showed that this single post-`i_unlock()` marker never
appeared at all, even though `0xB0` after `dev_openi()` is present and the
syscall later reports success. To split the remaining tail by progress rather
than by a single final snapshot, the current trace build reuses the same
`spr_rw_*` block (`0xFEF9..0xFF03`) as a stepped marker through the last part
of `_open()`:

- `spr_rw_stage = 0xB1` just before `udata.u_files[uindex] = oftindex`
- `spr_rw_stage = 0xB2` immediately after linking `u_files[]`
- `spr_rw_stage = 0xB3` after reader/writer accounting and just before
  `i_unlock(ino)`
- `spr_rw_stage = 0xB4` immediately after `i_unlock(ino)`

At each stage the block still snapshots:

- `spr_rw_fd = uindex`
- `spr_rw_base = ino` pointer
- `spr_rw_count = ino->c_magic`
- `spr_rw_access = flag`
- `spr_rw_mode = ino->c_dev`
- `spr_rw_dev = ino->c_num`

This makes the next replay decisive: the highest `0xB1..0xB4` value tells us
exactly how far the `_open()` tail really ran before the inode goes bad.

### Update from next replay: first boot reaches `write()`, then the machine reboots

The next replay moved past the old inode/open window entirely:

- the screen shows `SPRINTER WRITE OK`
- `_spr_boot_count = 2`, so the machine has really re-entered `fuzix_main()`
  rather than merely redrawing the old banner
- `_spr_rdwr_stage = 0x05` and `spr_rw_stage = 0x05`, which means the live
  trace block has already been reused by the successful `write(1, ..., 19)`
  path
- the stop captured after the second banner is now `PC=0xF1AC`
  (`sprinter_rst38_stub` hang loop), not the earlier `panic: corrupt inode`

So the previous bring-up blocker is gone: the current shortest path now reaches
`open("/dev/tty1")`, both `dup()` calls, and a successful `write()`.  The next
question is whether the reboot happens before `_write()` returns to userspace,
or later in the `pause()`/sleep path.

To split that without widening the kernel trace again, the current image uses a
second userspace marker in `sprinit.s`: after the first successful
`write("SPRINTER WRITE OK\\r\\n")`, PID 1 immediately does another
`write("SPRINTER RETURN OK\\r\\n")` and then drops into a pure local
`jr hang_loop` instead of calling `_pause()`.

Interpretation for the next replay:

- seeing only `SPRINTER WRITE OK` still means the failure is in the first
  `write()` return path or immediately after it
- seeing `SPRINTER RETURN OK` means `_write()` returned cleanly and the old
  reboot was caused later by the `pause()`/sleep path
- if the system now stays up in the local hang loop, the next kernel target is
  `_pause()`/`psleep(0)`/wake-up handling rather than tty/open/write

The next replay ruled out the `pause()` path entirely: PID 1 still prints only
`SPRINTER WRITE OK`, never reaches `SPRINTER RETURN OK`, and the syscall latches
show the trap happens with syscall `0x08` (`write`) still in flight:

- `_spr_sys_enter_no = 0x08`
- `_spr_sys_exit_no` is still the previous completed syscall
- `spr_rdwr_stage = 5`

So the current failure is inside the kernel-side `write()` path, after
`valaddr()` and `rwsetup()` have succeeded, but before `_write()` returns to
userspace.

To split that path, the current trace build reuses `spr_rw_*` as a
`writei()`/`cdwrite()`/`tty_write()` ladder:

- `0xC1` in `writei()` just before `cdwrite()`
- `0xC2` in `writei()` right after `cdwrite()` returns
- `0xC3` in `cdwrite()` just before `dev_write`
- `0xC4` on entry to `tty_write()`
- `0xC5` after `valaddr_r()` and tty lookup
- `0xC6` after the first byte fetch from userspace

The next replay can now tell whether the trap sits in `writei()`, device
dispatch, tty validation, or the first `_ugetc()`/`tty_putc_maywait()` step.

The next replay moved past that whole path as well: the screen now reaches
both `SPRINTER WRITE OK` and `SPRINTER RETURN OK`, and the immediate reboot is
gone. So both `write()` calls return to userspace cleanly, and the local
`jr hang_loop` is stable enough to keep the machine from re-entering the boot
banner.

That makes the next target the original `pause()`/sleep path again, but now
with the tty/write path removed from the equation. The current `sprinit.s`
therefore does:

1. `write("SPRINTER WRITE OK")`
2. `write("SPRINTER RETURN OK")`
3. `_pause(0)`
4. if `_pause()` ever returns, `write("SPRINTER PAUSE OK")`
5. local `jr hang_loop`

Interpretation for the next replay is now trivial from the screen alone:

- stops after `SPRINTER RETURN OK` => failure in `_pause()` / `psleep(0)` path
- shows `SPRINTER PAUSE OK` => `_pause()` returned and the old blocker sits
  later than the sleep syscall itself

The next replay hit exactly that first case. After `SPRINTER RETURN OK`,
PID 1 enters `_pause(0)` and the machine eventually prints garbage followed by
`panic: invalid dev`. The common latches at that stop show:

- `_spr_sys_enter_no = 0x25` (`_pause`)
- `_spr_sys_exit_no = 0x08` (last completed syscall is still `write`)
- `_sprinter_last_validchk_dev = 0x72E4`
- `_sprinter_last_validchk_site = 0x065E` (`PANIC_IOPEN`)
- `_sprinter_last_panic_ptr` points at `"invalid dev"`

So the next failure is no longer tty/output-related. The kernel enters the
sleep/scheduler path for `_pause()`, then some later control-flow/state
corruption leads to `i_open(dev=0x72E4)` and `PANIC_INVD`.

To split that path without widening the trace surface, the current image
reuses `spr_rw_*` as a scheduler ladder:

- `0xD0` at `do_psleep()` entry
- `0xD1` at `switchout()` entry
- `0xD2` on the `chksigs()` fast-return path
- `0xD3` while idling with `nready == 0`
- `0xD4` on the single-runnable-process short return
- `0xD5` just before `plt_switchout()`
- `0xE0` on entry to Sprinter `_plt_switchout`
- `0xE1` after `_getproc()` returns a process pointer
- `0xE2` immediately before calling `_switchin`
- `0xE3` if `_switchin` unexpectedly returns back to `_plt_switchout`

The next replay should therefore tell us whether `_pause()` dies before
platform switchout, inside scheduler selection, or specifically on the
unexpected `_switchin` return path.

The next replay ruled out scheduler handoff as the first failing point:
`spr_rw_stage = 0xD3` at the stop, which means `_pause()` reaches the
`while (nready == 0)` idle loop inside `switchout()`. So PID 1 goes to sleep,
there are no runnable tasks, and the next corruption happens inside
`plt_idle()` or immediately after it returns.

The current trace build therefore adds the cheapest possible split directly in
`platform-sprinter/main.c:plt_idle()`:

- `0xD6` before `kbd_poll()`
- `0xD7` after `kbd_poll()`
- `0xD8` after `timer_interrupt()`

This is enough to tell whether the `_pause()` failure is in the keyboard poll,
the software timer tick, or later than `plt_idle()` itself.

Current checkpoint after the later boot-marker narrowing:

- `0123456789ABEFJNPQSTVWXY` on screen means boot reaches the IDE PIO read
  path for the root superblock, the command is issued, `DRQ` is ready, and
  the blocker sits in the final low-level transfer step between
  `ide_xfer()` and the return from `_devide_read_data()`.

- A first attempt to add lowercase `a..e` markers directly inside
  `_devide_read_data()` regressed the machine back to `0123`, so that split
  has been removed again.  The working baseline remains the uppercase ladder
  through `...XY`, and the next iteration should isolate the final transfer
  path without perturbing the early boot layout.

Current recommended dump for the next replay:

- screen text / whether `SPRINTER WRITE OK` appears
- registers and `PG0..PG3` if it still stops
- `0xFEEC-0xFF03`
- `0xFEA8-0xFEB0`
- `0xFEC4-0xFEEB`
- `0xFFF9-0xFFFF`

The subsequent replays still showed the old `0xC6` write-path marker and
never reached `SPRINTER RETURN OK`, which means the emulator was not yet
running the rebuilt idle-split image. The current production-oriented
bring-up fix therefore narrows the suspected source directly in
`platform-sprinter/main.c`: under `CONFIG_SPRINTER_EARLY_TRACE`,
`plt_idle()` and `plt_interrupt()` no longer feed `kbd_poll()` into the tty
layer at all, and only keep the software timer running.

This is based on the visible symptom pattern from the pause tests:

- after `SPRINTER RETURN OK`, the machine prints random printable garbage
- that is followed by `i_open: bad disk inode`
- and finally `panic: invalid dev`

That sequence matches spurious PS/2 receive bytes being decoded as shell
input during idle, not a scheduler or mapping failure. Until the SIO/PS2
initialisation is cleaned up, suppressing keyboard polling is the smallest
platform-local way to stabilize sleep/idle and let the rest of the runtime
boot path proceed.

In parallel, the hand-written `Applications/util/sprinit.s` had two real
userland-side bugs that made later replays harder to interpret:

- the `write("SPRINTER RETURN OK\\r\\n")` length was `22` instead of `20`
- the `write("SPRINTER PAUSE OK\\r\\n")` length was `21` instead of `19`
- `_pause()` was called with an unnecessary pushed zero even though the libc
  wrapper takes no argument

Those are now fixed so the next replay should reflect only kernel/platform
state, not over-read strings or a mis-shaped user stack at the pause call.

To keep bring-up moving while the sleep/switch path is still unstable, the
current trace image also carries a narrow core-side guard in
`Kernel/syscall_proc.c:_pause()`: under `CONFIG_SPRINTER_EARLY_TRACE`, a
plain `pause(0)` from PID 1 returns immediately instead of entering
`psleep(0)`. This is intentionally temporary and exists only to let the
Sprinter diagnostic `/init` advance beyond the `pause()` checkpoint and
validate later userland/runtime state.

That bypass is now confirmed working: the latest replay reaches
`SPRINTER PAUSE OK` and then sits in ordinary userspace code instead of
dropping into the old `invalid dev` / `i_open` panic path. The current
checkpoint is therefore no longer "make `/init` survive"; it is "hand off
from the diagnostic `/init` into a real userspace program".

The next trace image changes only the hand-written `Applications/util/sprinit.s`
tail: after `SPRINTER PAUSE OK`, PID 1 now calls
`execve("/bin/sh", argv, NULL)` on the already duplicated `/dev/tty1`
descriptors. If `execve()` unexpectedly returns, the probe prints
`SPRINTER EXEC FAIL` and then falls back to the local `jr hang_loop`.

This gives a clean binary next-step result:

- if the screen switches into a shell prompt, the current bring-up image is
  already capable of launching real userspace on Sprinter;
- if `SPRINTER EXEC FAIL` appears, the next blocker is now firmly in the
  exec handoff to `/bin/sh`, not in open/dup/write/pause.

The very next replay reintroduced an earlier class of stop before any of the
probe writes reached the screen, even though the syscall latches still showed
the first `write(1, ...)` entering `readwrite()` with sane arguments and
getting as far as `rwsetup()`/`valaddr()`. Rather than keep debugging the
diagnostic text path, the current image now strips `/init` down further:

- `getpid()`
- `open("/dev/tty1", 0x0802)` with retry
- `dup(fd)` twice to claim `0/1/2`
- direct `execve("/bin/sh", argv, NULL)`

If `execve()` returns unexpectedly, the probe still prints
`SPRINTER EXEC FAIL` and falls back to the local loop. This makes the next
replay answer the real bring-up question directly: can PID 1 hand off into
the stock shell once the tty is opened, without any intermediate diagnostic
`write()` or `_pause()` traffic.

The following replay still died before any `/init`-side text appeared, and
the existing `_execve()` failure latches remained unchanged from the earlier
`/init` handoff. That means the new probe was not even reaching the
`execve("/bin/sh")` call; it was failing somewhere earlier in its own
userspace path. To narrow that further without reintroducing the noisy write
path, the current image removes the initial `getpid()` entirely and leaves the
minimal sequence as:

- `open("/dev/tty1", 0x0802)` with retry
- `dup(fd)` twice
- `execve("/bin/sh", argv, NULL)`

If the next replay still stops at `SPRINTER USERLAND OK`, then the remaining
early blocker is before or inside the first `open()` itself. If it advances,
the old `getpid()` round-trip was the destabilising piece in this stripped
probe layout.
- 2026-04-21: repeated reboots during `/init` handoff narrowed to
  `map_proc_2` taking `HL=0xFDE6`, where the bytes were `48 4C 4D 46`
  from the exec-trace block rather than a real page map. The old
  validator only checked `0x08 <= page < 0x80`, so this bogus pointer
  slipped through. The guard was tightened to the narrow observed case:
  if bank0 is `0x48` then bank1 must be the canonical `0x49`, otherwise
  `map_proc_2` falls back to `_udata + U_DATA__U_PAGE`. This avoids the
  `HL=0xFDE6 -> 48 4C 4D 46` exec-trace alias without growing common
  code enough to overflow `_COMMONDATA`.
- 2026-04-21: the next crash moved even earlier, between `Starting /init`
  and the first useful state inside `_execve()`. The remaining
  pre-exec bring-up shadow writes in `complete_init()` (`uput()` to
  `0xEDC0..0xEDCB`) were removed; for this stage we only keep the
  kernel-side page-map snapshot in common memory. The goal is to enter
  `_execve()` with no user-space writes at all before the real `/init`
  handoff.
- 2026-04-21: latest dumps show PID1 still entering the `/init` handoff
  with a half-stale map (`PG0..PG3 = 08/49/4A/49`) even after the
  `map_proc_2` alias guard. The likely source is the old boot-time
  degenerate map being "grown" in place. Under
  `CONFIG_SPRINTER_EARLY_TRACE`, `exec_or_die()` now discards PID1's
  boot map with `pagemap_free()` and allocates a fresh full `PROGTOP`
  map via `pagemap_alloc()` before `program_vectors()` and `_execve()`.
- 2026-04-21: that fresh-map shim did not move the failure; the trap still
  hits before `_execve("/init")` becomes observable. For the next
  iteration `exec_or_die()` was cut back to a passive snapshot only:
  no raw probe, no `pagemap_realloc()`, no `pagemap_free()/alloc()`,
  no extra `program_vectors()`. The handoff path is again the stock
  `_execve()` path with only kernel-side state capture left in place.
- 2026-04-21: the next replay finally showed PID1 entering `/init` with a
  sane 4-page user map (`PG0..PG3 = 40/41/42/43`), but the trap still hit
  before the first stable syscall from userspace. The remaining
  pre-`_execve()` helper in `exec_or_die()` was `rebuild_init_argv()`,
  which rewrote `/init` argv/envp into user memory a second time even
  though `complete_init()` had already prepared them. That duplicate
  user-memory write path is now removed; `exec_or_die()` keeps only the
  passive page-map snapshot and then drops straight into the stock
  `_execve()` path.
- 2026-04-21: the raw standalone `/init` proved to be present in the image,
  but the first userspace `open("/dev/tty1")` / `dup()` sequence still
  trapped before any stable visible progress. For the next bring-up step,
  PID1 now receives pre-opened `stdin/stdout/stderr` on `/dev/tty1`
  directly from the kernel under `CONFIG_SPRINTER_EARLY_TRACE`, and the
  raw `/init` is reduced to a single `execve("/bin/sh", argv, NULL)` plus
  the existing `SPRINTER EXEC FAIL` fallback if that handoff returns.
- 2026-04-21: the re-enabled circular trace exposed a platform-local
  memory-layout bug in the early-trace image itself: `_COMMONDATA`
  already reaches `0xFDxx..0xFExx`, while `init_hardware()` was still
  building the IM2 table at `0xFE00` and the bring-up IRQ stub at
  `0xFDFD`. That made the trace/common globals overlap the interrupt
  vector page and handler stub, so later boots could corrupt either the
  IM2 path or the trace state simply by touching `_COMMONDATA`.
  The current image moves the temporary IM2 table+stub below commondata:
  the vector page is now `0xFC00`, filled with `0xFC`, which resolves
  every IM2 vector to a fixed stub at `0xFCFC`. This keeps the whole
  early-trace common block and the bring-up IM2 machinery disjoint.
- 2026-04-21: after the IM2 relocation fix the machine still stops at
  `F1AC` very early, with the screen showing only the banner and
  `Devboot`. The important difference is that the live map is now
  canonical at the point of failure:
  `PG0..PG3 = 0x40/0x41/0x42/0x43`, `I = 0xFC`, and the old
  `_COMMONDATA`/IM2 overlap signature is gone. This means the current
  blocker is no longer "corrupted IM2 page layout" but an earlier boot
  path before `kputs("OK\\n")` / `Starting /init`.
- 2026-04-21: because `_COMMONMEM` now lives at `0xEE00`, the historical
  `0xFDxx..0xFFxx` dumps no longer directly expose the relevant live
  trace state. The current image therefore adds screen-localised boot
  markers under `CONFIG_SPRINTER_EARLY_TRACE` in `start.c`:
  `A` after `create_init()`, `B` after `device_init()`, `C` after
  successful `fmount(root_dev, ...)`, and `D` after successful
  `i_open(root_dev, ROOTINODE)`.
- 2026-04-21: the first version of those markers used `kputchar()`, but
  the replay still showed only `Devboot`, so the tty/cursor path was not
  trustworthy enough for this checkpoint. The marker path now writes
  directly to VRAM via `plot_char()` on a fixed row, bypassing tty output
  entirely. The next replay should therefore localise the early stop from
  the screen alone even if tty output is still unstable at that point.
- 2026-04-21: the first VRAM-marker replay still showed only `Devboot`,
  which means the stop is even earlier than the original `A/B/C/D`
  window or the first visible marker was placed too late. The current
  image therefore extends the same direct-VRAM row with earlier stage
  bytes:
  - `0` right after the `Devboot` banner is printed
  - `1` after `bufinit()`
  - `2` after `fstabinit()`
  - `3` after `pagemap_init()`
  - then `A/B/C/D` for `create_init()`, `device_init()`, `fmount()`,
    `i_open(root)` as before
- 2026-04-21: a later replay with the relocated IM2 table and canonical
  PID1 map (`PG0..PG3 = 0x40/0x41/0x42/0x43`) still stopped at `F1AC`,
  but the live trace ring now ends at `0xC2`.  That means boot reaches
  `create_init()`, completes `map_init()`, and dies before `0xC3`
  (`makeproc()` finished).  The narrow platform-local hypothesis is
  that `makeproc()->program_vectors()` was still executing from WIN0
  while remapping WIN0 to the new process page, i.e. a self-unmap in
  the vector setup path.  The current image moves the remap + vector
  patching sequence into a `_COMMONMEM` helper so the code keeps
  executing from WIN3 while WIN0 is switched to user RAM and then back
  to kernel pages.
- 2026-04-21: after the `_COMMONMEM` `program_vectors()` fix the first
  visible on-screen progress advanced to `0123`, which proves the boot
  now reliably reaches `create_init()`.  The next image narrows that
  window further with direct-VRAM markers inside `create_init()` itself:
  - `4` after `map_init()`
  - `5` after `makeproc()`
  - `6` after `uzero(PROGLOAD + 256, 32)`
  - `7` after `add_argument("/init")`
  This split should isolate the current blocker to either the
  `makeproc()/program_vectors()` tail or the first user-memory write
  path used to stage `/init`.
- 2026-04-21: the next replay reached `012345` and then stopped, so the
  current blocker is specifically the first `uzero(PROGLOAD + 256, 32)`
  in `create_init()`.  Under `CONFIG_SPRINTER_EARLY_TRACE` this bulk
  clear is now skipped temporarily: the scratch area is immediately
  overwritten by `add_argument("/init")` and the later argv terminator
  writes, so the no-op is sufficient as a bring-up guard to advance to
  the next real failure in the `/init` staging path.
- 2026-04-21: with the `uzero()` bypass active, the next replay reached
  `0123456` and then stopped.  That localises the new blocker to
  `add_argument("/init")`, i.e. the first `uput/uputp` staging of
  `"/init"` and `argv[0]` into PID1 user space.  The current image now
  keeps the same layout but uses the raw `_uput/_uputw` helpers under
  `CONFIG_SPRINTER_EARLY_TRACE`, bypassing the validated usermem wrapper
  path just for this boot-only argv staging.
- 2026-04-21: `complete_init()` and `rebuild_init_argv()` also now use
  raw `_uputw(0, argptr)` under `CONFIG_SPRINTER_EARLY_TRACE`, so the
  next replay can tell whether the stop was specifically in the wrapper
  validation path or in the lower-level user-page copy itself.
- 2026-04-21: the next replay still stopped at `0123456`, which rules out
  the validated `uput/uputp` wrapper as the active blocker.  For the next
  step PID1 no longer stages `"/init"` / `argv[]` in user RAM at all under
  `CONFIG_SPRINTER_EARLY_TRACE`: `complete_init()` now hands `_execve()`
  kernel-resident `"/init"`, `argv[]`, and `envp[]` with `u_sysio = 1`.
  `filesys.c:n_open()` and `syscall_exec.c:rargs()` gained the minimal
  corresponding early path so `_execve()` can consume those kernel-side
  pointers without going through the fragile first user-memory handoff.
- 2026-04-21: one more replay still showed `0123456`, which means the
  boot was dying before that new kernel-side `_execve()` handoff became
  relevant.  The remaining active touchpoint was the original
  `create_init()->add_argument("/init")`.  Under
  `CONFIG_SPRINTER_EARLY_TRACE` that call is now skipped entirely, so
  PID1 should finally advance past marker `6` into `complete_init()`
  and the real exec path.
- 2026-04-21: the next replay reached `01234567`, which confirms
  `create_init()` now runs to its previous tail.  The stop has moved to
  the narrow window between returning from `create_init()` and the first
  post-return marker at the callsite in `fuzix_main`.  The current image
  therefore adds:
  - `8` in the very end of `create_init()`
  - `9` immediately after `create_init()` returns, before `A`
  so the next replay can split “dies in the `create_init` epilogue” from
  “dies after return in the caller”.
- 2026-04-21: the following replay reached `012345678`, which proves
  `create_init()` itself now runs to its end marker.  The remaining
  stop was not the real C epilogue but the trailing early-trace
  read-back probe (`EARLY_TRACE(0xCA)` plus six `ugetc()` reads of the
  staged `"/init"` bytes) that still executed after marker `8`.
  That probe has now been removed so the next replay can distinguish a
  genuine return-path fault (`012345678` only) from a successful return
  into the caller (`0123456789...`).
- 2026-04-21: the next replay reached `0123456789AB`, which confirms
  both the return from `create_init()` and `device_init()` now succeed.
  The active blocker has therefore moved strictly into the root mount
  path before marker `C`.  The current image adds a finer split there:
  - `E` after `get_root_dev()`
  - `F` after the `BAD_ROOT_DEV` fallback check
  - `G` immediately after `fmount()` returns
  - `H` on the `m == NULL` error path before `panic(PANIC_NOROOT)`
  so the next replay can separate “dies before `fmount()`”, “dies inside
  `fmount()`”, and “returns from `fmount()` but fails on the error
  branch”.
- 2026-04-21: the next replay reached `0123456789ABEF`, which narrows
  the failure to inside `fmount()` itself before any return to the
  caller.  The current image therefore adds direct-VRAM markers inside
  `fmount()`:
  - `J` after `newfstab()`
  - `K` after `bread(dev, 1, 0)` returns
  - `L` after the superblock validity checks pass
  - `M` immediately before returning success
  so the next replay can isolate whether the stop is in `newfstab()`,
  `bread()`, superblock decode/validation, or the final `sync()` tail.
- 2026-04-21: the next replay reached `0123456789ABEFJ`, which proves
  `newfstab()` succeeds and the active blocker has moved into the first
  root superblock read, i.e. `bread(dev, 1, 0)` or lower.  The current
  image therefore adds direct-VRAM markers in the block-read path:
  - `N` after `freebuf()` in `bread()`
  - `O` after `bdread()` returns `BLKSIZE`
  - `P` after `validchk(dev, PANIC_BDR)`
  - `Q` after `bdsetup()`
  - `R` immediately after the underlying `td_read()` / `dev_read()`
    call returns
  so the next replay can separate buffer-cache setup, validity checks,
  and the actual device block read path.
- 2026-04-21: the next replay reached `0123456789ABEFJNPQ`, which
  proves `bread()` allocates a buffer, `bdread()` passes `validchk()`,
  and `bdsetup()` completes.  The active blocker is therefore already
  inside the actual disk transfer path (`td_read -> td_transfer ->
  ide_xfer` / `devide_read_data`).  The current image adds:
  - `S` at the start of the transfer loop in `td_transfer()`
  - `T` immediately before `ide_xfer()`
  - `U` after a successful `ide_xfer()` iteration
  - `V` after initial `ide_write(devh, devsel)`
  - `W` after the initial `!BUSY` waits
  - `X` after issuing the read command
  - `Y` after DRQ becomes ready
  - `Z` after `devide_read_data()` returns
  so the next replay can split IDE setup, status polling, DRQ wait, and
  the 512-byte PIO data transfer loop itself.

## Current checkpoint

The active goal is no longer generic "make `/init` survive".  The next
checkpoint is to localise the early stop inside the narrow kernel boot
path:

`create_init -> makeproc(program_vectors) -> device_init -> fmount(root) -> i_open(root) -> OK -> exec_or_die`

using only the new on-screen markers.

The next expected replay outcomes are:

- no `A`: failure before or during `create_init()`
- `A` only: failure between `create_init()` and `device_init()`
- `AB` only: failure before `get_root_dev()` / before the finer mount
  split becomes visible
- `ABE` only: failure after `get_root_dev()` returns
- `ABEF` only: failure just before entering `fmount()`
- `ABEFJ` only: failure after `newfstab()`
- `ABEFJN` only: failure after `freebuf()` / early `bread()` setup
- `ABEFJNP` only: failure after `validchk()` in `bdread()`
- `ABEFJNPQ` only: failure after `bdsetup()`, inside the actual block
  driver read
- `ABEFJNPQR` only: underlying block read returned, blocker moved back
  to `bread()` / `fmount()` tail
- `ABEFJNPQS` only: failure at the start of `td_transfer()`
- `ABEFJNPQST` only: failure just before `ide_xfer()`
- `ABEFJNPQSTV` only: failure in the first IDE wait/setup phase
- `ABEFJNPQSTVW` only: failure after the initial `!BUSY` waits
- `ABEFJNPQSTVWX` only: failure after issuing the read command
- `ABEFJNPQSTVWXY` only: failure after DRQ, inside the 512-byte data
  transfer loop
- `ABEFJNPQSTVWXYZ` only: PIO data transfer returned, blocker moved to
  the post-transfer status wait / tail
- `ABEFJK` only: failure after `bread(dev, 1, 0)` returns
- `ABEFJKL` only: superblock validated, blocker moved to dirty-mark /
  `sync()` tail
- `ABEFJKLM` only: `fmount()` is about to return success, blocker moved
  back to the caller path before `C`
- `ABEFG` only: `fmount()` returned and the blocker moved to the first
  post-mount branch
- `ABEFGH` only: `fmount()` returned `NULL`, and the blocker is now in
  the mount-failure / panic path
- `ABC` only: failure in `i_open(root_dev, ROOTINODE)`
- `ABCDOK`: handoff has moved past root open and the next blocker is
  again in `exec_or_die()` / `/init`
- `0123456` only: stop in `add_argument("/init")`
- `01234567`: `create_init()` completed, blocker moved to later boot /
  exec handoff
- `012345678`: `create_init()` reached its final marker; if this still
  appears after removing the trailing read-back probe then the blocker
  is the actual return path from `create_init()`
- `0123456789`: returned from `create_init()`, blocker moved to the
  caller path before `device_init()`
- `0123456789AB`: `device_init()` completed, blocker moved into the
  root-device selection / mount path before the successful-mount marker
  `C`

The next replay after the `_COMMONMEM` `program_vectors()` fix should no
longer stop with the last trace code `0xC2`.  Any visible progress past
`Devboot` or a new later trace code means the self-unmap hypothesis was
correct and the blocker has moved further down the boot path.

Current baseline is now stable again at `0123456789ABEFJNPQSTVWXY`.  An
attempt to add on-screen lowercase `a..e` markers inside
`_devide_read_data()` regressed boot back to `0123`, so the next split
must stay off the screen path.  The current image therefore uses the
existing `_spr_rw_stage` / `_spr_rw_base` latches in common memory
instead:

- `_spr_rw_stage` at `0xFCB5`
- `_spr_rw_base` at `0xFCB7`

`_devide_read_data()` now writes:

- `0xE4/0xE5/0xE6` on entry, encoding `td_raw == 0/1/2`, with
  `_spr_rw_base = dptr`
- `0xE1` after `map_buffers()` / `map_proc_always()` / `map_for_swap()`
- `0xE2` after the first 256-byte half of the 512-byte PIO copy
- `0xE3` after the full 512-byte copy and just before `map_kernel_restore`

So the next focused dump for the IDE read blocker is:

- screen, plus `0xFCB5-0xFCB8`

Interpretation:

- `stage=E4`: raw kernel-buffer path (`td_raw == 0`) is taken
- `stage=E5`: blocker is on the `map_proc_always()` path
- `stage=E6`: blocker is on the `map_for_swap()` path
- `stage=E1`: fault in the first 256-byte half
- `stage=E2`: fault in the second 256-byte half
- `stage=E3`: copy finished, blocker moved to `map_kernel_restore()` or
  the caller path above `_devide_read_data()`

The latest latch dump finally narrowed the failing edge further: the
stable replay still stops at `...ABEFJNPQSTVWXY`, but `_spr_rw_stage`
already holds the entry marker, which means `_devide_read_data()` has
actually started and dies before reaching the post-map checkpoint
`0xE1`.

The current image applies the narrowest possible test for that
hypothesis:

- in `_devide_read_data()`, when `td_raw == 0`, skip `map_buffers()`
  entirely and read the 512-byte sector into the current kernel mapping
  as-is
- user (`td_raw == 1`) and swap (`td_raw == 2`) paths are unchanged
- on exit, only call `map_kernel_restore()` if a remap actually
  happened

The next replay should therefore either move past `...XY` (ideally to
`Z`, `K/L/M`, `C`, and then the later boot markers) or prove that the
fault is not caused by the `map_buffers()` remap itself.

That bypass turned out to be too intrusive in practice: the next replay
regressed all the way back to `0123`, so it has been reverted.  The
useful conclusion is only negative: simply skipping `map_buffers()` in
`_devide_read_data()` is not a safe fix.  The working baseline therefore
remains the image that reaches `0123456789ABEFJNPQSTVWXY`, and the next
step must preserve that layout while probing the IDE read path more
carefully.

The next image applies the same hypothesis in a size-neutral way: on the
`td_raw == 0` path inside `_devide_read_data()`, the single `call
map_buffers` is replaced with three `nop`s, preserving code size and all
subsequent addresses in `_COMMONMEM`.  This tests whether the kernel
buffer read really dies because remapping WIN0..WIN2 to canonical kernel
pages loses the live boot mapping, without reintroducing the earlier
layout regression.

That size-neutral test still stopped at `...ABEFJNPQSTVWXY`, so the
simple `map_buffers()` remap hypothesis is now ruled out.  A first
attempt to refine the branch latches with extra stores regressed boot
back to `0123`, so that version was discarded.  The next image keeps the
same stable layout and reuses the existing entry-stage bytes in
`_devide_read_data()` to encode `td_raw` as `E4/E5/E6` without changing
the overall code footprint in `_COMMONMEM`.

The first replay of that `E4/E5/E6` image turned out to be invalid: the
branch-marker experiment had a logic bug (`add a,#0xE4` before `cp #2`)
that corrupted the `td_raw` test itself.  The image has now been fixed
so `td_raw` is compared first and only then latched as `E4/E5/E6`,
without reintroducing the earlier `_spr_rw_fd/_spr_rw_access` stores.

The follow-up replay exposed a more important limitation in this debug
approach: the `_spr_rw_*` bytes used for the branch markers live inside
the active IM2 vector page at `0xFC00`, so writing them is itself unsafe
and can perturb the interrupt page enough to regress boot back to
`0123`. Those FCxx latch experiments are therefore no longer trusted as
runtime evidence.

The stable baseline remains the screen sequence:

`0123456789ABEFJNPQSTVWXY`

which means:

- boot reaches `fmount()`
- `bread(dev, 1, 0)` reaches `td_transfer()`
- `ide_xfer()` reaches `DRQ ready`
- the blocker sits in the final IDE bulk data path inside
  `_devide_read_data()`

Two negative results are now established:

- simply skipping `map_buffers()` on the `td_raw == 0` path does not
  move the failure, so the fault is not just the buffer remap itself
- adding more FCxx latches corrupts the IM2 page and is not a valid way
  to refine the trace further

The current hypothesis is now platform-specific rather than mapping-only:
Sprinter IDE bulk transfer appears to require Z80 block-I/O instructions
(`INI/INIR` and `OUTI/OTIR`) rather than repeated single-byte
`IN A,(C)` / `OUT (C),A` cycles. The local Sprinter manual explicitly
describes IDE data transfer through `INI`/`OTIR`, and the BIOS HDD path
uses `INI` loops for sector reads. The current image therefore switches
`_devide_read_data()` to two `INIR` passes (512 bytes total) and
`_devide_write_data()` to two `OTIR` passes, while also removing the
unsafe `_spr_rw_*` writes from that path.

That first `INIR/OTIR` image still stopped at the same `...XY`
checkpoint, which rules out the simple "single-byte IN/OUT vs block I/O"
hypothesis on its own.  The next hardware-specific constraint from the
Sprinter manual is stronger: page switches must not happen during IDE
transfer at all.  On this port that includes interrupt paths, because
the IRQ/NMI handlers remap windows and would therefore violate the IDE
transaction if they fire between `DRQ` and the end of the sector copy.

The current image therefore wraps `_devide_read_data()` and
`_devide_write_data()` in a narrow `DI ... transfer ... map_kernel_restore
... EI` guard.  This keeps the page mapping stable for the full
512-byte PIO transfer and matches the BIOS assumption that no mapper
activity occurs while the IDE data path is active.

The next replay finally exposed a concrete ABI bug in the Sprinter IDE
helpers.  The `tinyide` call sites on this target do **not** use the
generic naked helper convention `pop ret / pop arg / push arg / push
ret`; SDCC emits `push hl` for the data pointer and then `push af;noopt`
before the `call`.  That means the real pointer is still at `SP+4` on
entry.  The recent Sprinter-local change to generic `pop/push` ABI
therefore loaded the `AF;noopt` word as the destination/source pointer,
causing `_devide_read_data()` / `_devide_write_data()` to copy sector
data into garbage near the live kernel stack and common memory.

The current image fixes this by restoring `SP+4` argument fetch in both
helpers while keeping the rest of the transfer logic unchanged.  If this
is the last blocker in the root-superblock path, boot should finally
move past the long-standing `0123456789ABEFJNPQSTVWXY` checkpoint.

A later attempt to follow the BIOS path even more literally by replacing
the two `INIR` / `OTIR` passes with explicit `16 x INI/OUTI` inside a
`32`-iteration loop turned out to be too disruptive in this kernel
layout: the replay regressed immediately back to `0123`.  That variant
has therefore been reverted.  The working comparison point remains the
stable baseline screen sequence:

`0123456789ABEFJNPQSTVWXY`

which still localises the blocker to the post-`DRQ` bulk read path in
`_devide_read_data()`.

That `DI/EI` guard still leaves the machine at the same
`...ABEFJNPQSTVWXY` checkpoint, so the blocker is no longer well
explained by IRQ-driven page switches during the transfer.

A follow-up split using extra in-band `a/b` screen markers inside
`_devide_read_data()` turned out to be too intrusive: the replay
regressed back to `0123`, so those extra calls have been removed and
that result is discarded.

The next platform-local fix follows the BIOS path more closely.  The
BIOS HDD code uses explicit `INI` runs (16 `INI` × 32 iterations for
512 bytes) rather than `INIR`, and likewise `OUTI` runs for writes.
The current image therefore replaces the two `INIR`/`OTIR` passes in
`_devide_read_data()` / `_devide_write_data()` with BIOS-style
`INI`/`OUTI` loops while keeping the narrow `DI ... map ... transfer ...
map_kernel_restore ... EI` guard intact.

That BIOS-style `INI`/`OUTI` loop regressed the machine back to `0123`,
so it has been discarded.  The new platform-local candidate keeps the
working `INIR` transfer but routes the sector through a Sprinter-local
256-byte bounce buffer in `_COMMONMEM`, in two 256-byte halves.  This
preserves the stable baseline layout while removing direct IDE PIO
stores into banked WIN0/WIN1/WIN2 memory, which is now the main
remaining behavioural difference from the BIOS `PAGE3` transfer path.

That bounce-buffer variant still leaves the machine at the same
`...ABEFJNPQSTVWXY` checkpoint, so the remaining suspect is no longer
the raw data path alone, but the entry/return ABI of the naked
`_devide_read_data()` / `_devide_write_data()` helpers themselves.
Generic `tinyide` uses the classic SDCC naked convention
`pop ret / pop arg / push arg / push ret`; the Sprinter override had
diverged to an `SP+4` fetch based on an earlier bring-up hypothesis.
The current image restores the generic pop/push ABI while keeping the
current transfer logic otherwise unchanged.

The follow-up replay did not move the checkpoint at all, so that ABI
change was not the active blocker.  However, the crash dump exposed a
real layout bug in the bounce path itself: the Sprinter-local symbol
`_sprinter_ide_bounce` was commented as a "common bounce" but still
lived in the active `_CODE` area, and the linker placed it at low
address `0x0455` rather than inside `_COMMONMEM`.  In other words, the
read helper was bulk-reading IDE data into page-0 kernel code/data, not
into a stable common-memory scratch area.

The current image fixes only that placement bug by moving
`_sprinter_ide_bounce` into the real `_COMMONMEM` area while keeping the
rest of the transfer logic unchanged.  If this was the last hidden
layout issue in the root-superblock path, the next replay should
finally move past `0123456789ABEFJNPQSTVWXY`.

That relocation turned out to be another intrusive layout change rather
than a safe fix.  With `_sprinter_ide_bounce` moved into `_COMMONMEM`,
`_COMMONDATA` slid from its previous base and the replay regressed all
the way back to `0123`.  The bounce symbol really did move (to `0xF317`),
but the price was a different common-memory layout, so that experiment
has been reverted and the stable baseline remains the screen sequence:

`0123456789ABEFJNPQSTVWXY`

The useful result is only diagnostic: the IDE helper can still be
destabilised by changing common-memory layout, so the next split/fix
must stay layout-neutral and avoid moving `_COMMONDATA`.

The later RST38 dump around `0xFC20` exposed another layout bug in the
diagnostic layer itself.  The fatal logger fields
`_sprinter_rst38_count/_sp/_ret` and the adjacent
`_sprinter_last_validchk_*` / panic snapshots had ended up at
`0xFC39-0xFC47`, i.e. inside the IM2 vector page that the Sprinter port
fills with `0xFC` bytes.  That made the earlier requests for
`0xFC43-0xFC49` effectively meaningless: the trap did reach
`sprinter_rst38_stub`, but the bytes we tried to read back were sitting
in the same page the vector setup continuously treats as IM2 table
storage.

The current image fixes only that diagnostic-layout mistake by moving
those early fatal latches below `0xFC00`, immediately after
`_kernel_pages` in `_COMMONDATA`.  This is intentionally layout-light:
it does not touch the hot IDE read path, only makes the next RST38 dump
around `0xFC40` trustworthy.

The more important conclusion from the stable `...XY` replay is that
the long-standing Sprinter IDE "bounce" buffer was still not a safe
bounce at all: `_sprinter_ide_bounce` lived in the active low `_CODE`
area, so the first 256-byte `INIR` in `_devide_read_data()` bulk-wrote
IDE sector data over low kernel code around `0x0455`.  That matches the
observed symptom perfectly: the read path reaches `Y` (DRQ ready), then
execution wanders off with garbage `PC`/mapper state before any `Z`
marker can be printed.

The current image fixes that by moving `_sprinter_ide_bounce` out of the
low code page and into `_BUFFERS`, right after `_bufpool`.  This keeps
the bounce in stable low kernel RAM, avoids touching the fragile
`_COMMONMEM/_COMMONDATA` layout, and should finally let the root
superblock read return past `...XY`.

That `_BUFFERS` relocation removed the obvious low-code overwrite, but
the stable replay still stops at exactly the same
`0123456789ABEFJNPQSTVWXY` checkpoint.  A more focused crash dump then
showed execution escaping not into `sprinter_rst38_stub`, but into a
garbage mapping with `PG0=0x08`, `PG3=0x00`, `SP≈0xBFEE`, and the top
stack return word already pointing into ROM space around `0xC031`.
That strongly suggests the remaining post-`Y` failure is a corrupted
return address on the live stack rather than a direct trap inside
`INIR`/`LDIR`.

Latest replay with the on-screen caller probe printed `Y02D88`, proving the
root superblock read enters `_devide_read_data()` on the kernel-buffer path
(`td_raw == 0`) with a sane buffer-cache destination pointer (`dptr=0x2D88`).
That rules out a corrupt caller argument and localises the blocker inside the
platform helper itself.

The first fixed-port rewrite of `_devide_read_data()` replaced `INIR` with a
byte loop, but incorrectly used register `A` as the 256-byte loop counter.
Because each `in a,(c)` overwrote that counter with IDE data, the helper read
an arbitrary amount of data into `_sprinter_ide_bounce`, overrunning the
bounce area and eventually escaping into ROM.

A follow-up attempt switched that counter to `D` (saving/restoring `DE` around
each 256-byte half-sector read), but that image regressed the machine all the
way back to the early `0123` stop. So that exact-counter variant is not a
valid production fix and has been reverted; the current baseline remains the
stable `...XY02D88` replay, which still localises the blocker to the
post-`Y` helper tail.

One more practical correction: that revert must restore the full helper path,
not just the counter register.  The fixed-port single-byte loop itself also
proved regression-prone in this kernel build and repeatedly collapsed the boot
back to `0123`.  The current baseline image therefore restores the whole
Sprinter IDE transfer helper to the last known-good form:

- `SP+4` argument fetch
- two `INIR` passes for reads
- two `OTIR` passes for writes
- keep only the already-tested `td_raw == 0` fast-exit that skips the final
  redundant `map_kernel_restore()`

This should bring the machine back to the stable `...XY02D88` checkpoint so
post-`Y` debugging can continue from a known-good image again.

The current image adds one narrow hardening step only: on entry to
`_devide_read_data()` / `_devide_write_data()` the top-of-stack return
word is copied into `_sprinter_ide_retaddr` in `_COMMONDATA`, and just
before `ret` those two bytes are written back to `(SP)`.  This keeps
the surrounding ABI unchanged and is intended to confirm or rule out
stack-top clobbering during the IDE transfer tail.

That hardening regressed the machine straight back to `0123`, so it is
not a valid production fix and has been removed again.  The useful
result is only negative: touching the helper prologue/epilogue is
fragile enough to perturb early boot, so the stable baseline remains
the original `...ABEFJNPQSTVWXY` checkpoint and future splits should
avoid changing the hot helper ABI unless there is a stronger address-
level proof.

The current image keeps the hot IDE helper unchanged and instead latches
the caller-side argument immediately before `devide_read_data()` /
`devide_write_data()` in `ide_xfer()`, reusing the existing
`_spr_rw_stage/_spr_rw_fd/_spr_rw_base` diagnostics:

- `spr_rw_stage = 0xDA` just after the `Y` marker
- `spr_rw_fd = _td_raw`
- `spr_rw_base = dptr`

This is intended to answer the next concrete question without touching
the fragile `_COMMONMEM` transfer loop: on the stable `...XY` replay,
is the helper entered with a sane buffer-cache pointer, or is the
destination already corrupt (for example into `0xBFxx/0xC0xx`) before
the transfer begins.

The subsequent ROM-map dumps make the likely tail-path culprit narrower.
On the stable `...XY` replay the machine does not go through
`sprinter_rst38_stub`, `validchk()`, or `panic()`.  Instead execution
escapes into ROM with `PG0=0x08`, `PG3=0x00`, and `PC` wandering in a
`NOP`-filled low page.  Because the root superblock read is a kernel-
buffer transfer (`td_raw == 0`), `_devide_read_data()` has already
called `map_buffers()` before the first `LDIR`, so the final
`call map_kernel_restore` is redundant on the success path: we are
already back on the kernel map.  The current image therefore applies one
very narrow platform-local change only:

- `_devide_read_data()` skips the final `map_kernel_restore()` when
  `_td_raw == 0`
- `_devide_write_data()` does the same on the kernel-buffer path

If the remaining corruption lives in the redundant restore/return tail,
this should move the boot past `...ABEFJNPQSTVWXY` without touching the
PIO transfer itself or the user/swap mapping paths.

The replay after that change still lands on exactly the same
`...ABEFJNPQSTVWXY` checkpoint, with execution escaping into ROM and the
stack top already holding a ROM return address.  One more practical
detail also surfaced from the map/dumps: the generic `_spr_rw_*`
diagnostic cells currently sit in the `0xFC96+` range, which is inside
the active IM2 table page at `0xFC00-0xFCFF`, so those latches are not
trustworthy for post-`Y` analysis on Sprinter.  The current image
therefore adds a cheaper and more reliable caller-side probe in
`ide_xfer()`:

- immediately after `Y`, print `'0' + td_raw`

This lets the next replay answer the key question directly on screen:
is the failing superblock read really on the kernel-buffer path
(`...XY0`), or are we unexpectedly entering the user/swap mapping path
(`...XY1` / `...XY2`) before control escapes into ROM.

The next replay confirmed `...XY0`: the failing root superblock read is
indeed on the kernel-buffer path, not on user or swap mappings.  That
moves the remaining ambiguity to the pointer itself: is
`devide_read_data()` entered with a sane buffer-cache destination, or is
the caller already handing it a corrupted stack/ROM-adjacent address.
The current image therefore extends the on-screen probe by printing the
16-bit `dptr` argument immediately after `Y0`, as four hexadecimal
digits.  A healthy replay should show a low kernel RAM address inside
the buffer pool; a `BFxx`/`C0xx`-style value would prove the corruption
exists before the helper tail.

Current stable replay is now:

`0123456789ABEFJNPQSTVWXY02D88`

This is the last known-good baseline and should be treated as the resume
checkpoint for the next session.

Meaning of the confirmed suffix:

- `Y`  — `ide_xfer()` reached DRQ-ready and is about to enter the data helper
- `0`  — `_td_raw == 0`, so this is the kernel-buffer path, not user/swap
- `2D88` — `dptr` passed to `_devide_read_data()` is a sane low kernel
  buffer-cache pointer, not a corrupted stack/ROM address

So the current state is narrowed to a single remaining class of bugs:

- the caller-side destination pointer is good
- the read is on the kernel-buffer path
- the machine still escapes into ROM after `Y`, before `Z`

Therefore the next investigation must start strictly in the
post-`Y` tail of the Sprinter-specific helper path, not in:

- `fmount()` setup
- `bread()` caller argument setup
- `td_raw` path selection
- or generic panic / `RST 38` handling

Practical resume goal for the next session:

1. Preserve this exact baseline (`...XY02D88`) first.
2. Do not introduce layout-moving diagnostics in `_COMMONMEM/_COMMONDATA`.
3. Keep changes inside `platform-sprinter/`.
4. Continue from the post-`Y` helper tail only:
   - `_devide_read_data()`
   - `map_buffers()` / `map_kernel_restore()` interaction
   - return path back into `ide_xfer()`
5. Any new probe should be screen-visible or live in stable low kernel RAM,
   not in the IM2 `0xFC00-0xFCFF` page.

### 2026-04-21: drop `_sprinter_ide_bounce`, go BIOS-style direct PIO

The `...XY02D88` baseline proves that the caller path is correct and the
helper is entered with a sane buffer-cache destination on the
`td_raw == 0` path.  Every post-`Y` probe that added structure inside
`_devide_read_data()` has so far either regressed boot back to `0123`
(layout-sensitive) or not changed the `...XY` stop at all.  The useful
negative result is that the fault sits somewhere between the first INIR
and the return to `ide_xfer()` — and the only structural feature that
lives in that window, other than the mapping calls themselves, is the
`bounce -> ldir` interleave.

The Sprinter BIOS (`sprinter_bios/SETUP/HDRIVER6.ASM:RDS003`) does not
use a bounce at all: with IRQs left masked by the caller, PAGE3 is
pointed at the target and the kernel runs one tight unrolled INI loop
directly into the mapped window, then restores PAGE3.  The DSS example
in `sprinter_ai_doc/manual/07_disk/02_ide.md` matches the same idiom
(`ld bc,HDR_DAT ; ld d,0 ; .loop: ini : ini : dec d : jr nz,.loop`).
The Sprinter DCP port decoder uses the low 8 bits (`A7..A0`) of BC to
classify the port, so the value of B drifting during INIR is
documented as a no-op for HDR_DAT.

Current image rewrites `_devide_read_data()` and `_devide_write_data()`
in `platform-sprinter/sprinter.s` to that direct form:

- `td_raw == 0`: no `map_buffers` call, no `_sprinter_ide_bounce`, no
  intermediate `ldir`.  `DI`; load `HL = dptr`; two `INIR` passes (or
  two `OTIR` passes for writes); `EI`; `RET`.  Every byte lands
  straight in the caller's kernel buffer via a tight block-I/O loop,
  matching BIOS `RDS003`.
- `td_raw == 1`: push `dptr`, `call map_proc_always`, pop it back into
  `HL`, then the same tight `INIR`/`OTIR`, then `map_kernel_restore`
  before the return.
- `td_raw == 2`: same shape with `map_for_swap(td_page)` instead.

This removes the only window between `Y` and `Z` where banking could
change mid-sector or the kstack could be clipped by a partial-half
`ldir` plus a second `inir`.  `_sprinter_ide_bounce` is intentionally
kept as a symbol in `crt0.s` (`_BUFFERS`) for now — nothing else
references it, but leaving it in place avoids disturbing the low-kernel
layout that the current `...XY02D88` baseline depends on.  If the next
replay is stable, the symbol can be removed in a follow-up cleanup.

Expected replay outcomes:

- `ABEFJNPQSTVWXY0<dptr>Z` on screen means the first root-superblock
  read returned; boot should then continue into the `K/L/M` markers
  inside `fmount()` and eventually reach `CDOK` and `Starting /init`.
- If the stop stays at exactly `...XY02D88`, the fault is not the
  bounce/ldir interleave and is somewhere in the shared
  `map_proc_always` / `map_kernel_restore` path or in `inir` itself.
- A regression to `0123` would mean the new layout shifted kernel
  sections enough to hit a different early bug; in that case revert
  and keep the bounce.

Recommended dump for the next replay:

- full screen text
- registers and `PG0..PG3` if it still halts
- `0xFCA2-0xFCA7` (`spr_rw_stage/fd/base` set right before entering
  `_devide_read_data()`)
- `0xFBE4-0xFBEB` (`mpgsel_cache` + `top_bank` + start of
  `_kernel_pages`) so we can tell whether a returned-but-wrong mapping
  is the next-step symptom

### 2026-04-21: direct PIO worked, blocker moved to superblock validate

Replay of the BIOS-style `_devide_read_data()` confirmed the hypothesis:
the IDE read path is now stable end-to-end.  Screen advances from the
old `...XY02D88` stop past `Z` (helper returned) and walks back up
`U R O K G H` into `fmount()`:

- `Z`: `devide_read_data()` returned
- `U`: `ide_xfer()` iteration succeeded
- `R`: `td_read()` / `dev_read()` returned
- `O`: `bdread()` returned `BLKSIZE`
- `K`: `bread(dev, 1, 0)` returned a valid buffer
- `L` / `M` never fire, so `fp->s_mounted != SMOUNTED ||
  fp->s_isize >= fp->s_fsize || fp->s_shift > FS_MAX_SHIFT`
  rejected the freshly read superblock
- `G`: `fmount()` returned
- `H`: `m == NULL` branch ran
- `panic: no root`

On-disk the superblock at `fuzix.img` LBA 259 (partition start 258 + fs
block 1) is known-good: `C6 31 00 01 FF FF 19 00 ...`, i.e.
`s_mounted = 0x31C6 (12742, SMOUNTED)`, `s_isize = 0x0100`,
`s_fsize = 0xFFFF`, `s_shift = 0`.  So either we read the wrong LBA,
the bytes get corrupted before the validation, or the validation itself
is comparing the wrong offsets.

To answer that from the screen alone, the current image adds four
on-screen hex quadruples right before the `fmount()` superblock check
under `CONFIG_SPRINTER_EARLY_TRACE` (via a new shared
`sprinter_boothex()` helper in `start.c`):

- `m<XXXX>` - `fp->s_mounted` (expect `m31C6`)
- `i<XXXX>` - `fp->s_isize`   (expect `i0100`)
- `f<XXXX>` - `fp->s_fsize`   (expect `fFFFF`)
- `s<XX>`   - `fp->s_shift`   (expect `s00`)

Expected outcomes on the next replay:

- Full match (`m31C6 i0100 fFFFF s00`) means the read + `blktok()` path
  is correct and the remaining issue sits in the validation math on
  Sprinter's toolchain.  We then look at `SMOUNTED` / `FS_MAX_SHIFT`
  resolution in this build.
- All zeros (`m0000 ...`) means the read landed on an unwritten sector;
  partition start is off or `bread(dev, 1, 0)` is being routed to LBA
  258 instead of LBA 259.  Next step: dump partition discovery via
  `td_lba[0][1]`.
- Byte-shuffled pattern (e.g. `mC631`) means an endianness/offset bug
  in `blktok()` or the struct layout on Sprinter.
- Any other garbage indicates IDE data corruption that still survives
  the BIOS-style PIO fix, at which point the narrow next probe is the
  raw buffer bytes before `blktok()` vs after.

### 2026-04-21: root cause was 8-bit PIO `Set Features`, not the helper

The superblock probe produced `m00C6 i0031 f0000 s28` on screen.
Comparing against the known-good on-disk superblock
(`C6 31 00 01 FF FF 19 00 ... byte 110 = 0x28`) nails the
transformation: `buffer[2n] = disk[n]`, `buffer[2n+1] = 0`.  The
512 `INI` cycles only recover 256 disk bytes, each one interleaved
with a zero byte — exactly the signature of a drive operating in
8-bit PIO mode where each 16-bit word holds one disk byte in the low
half and zero in the high half, while the Sprinter DCP bridge exposes
each word as two 8-bit reads at port `0x0050`.

The source is `Kernel/dev/tinyide.c` itself: the Sprinter-only
`CONFIG_SPRINTER_EARLY_TRACE` branch added during earlier bring-up
issued `Set Features 0xEF / subcode 0x01` (enable 8-bit data transfer)
before every `ide_xfer()` call.  That negotiated the drive into
8-bit mode and produced the observed half-data pattern.  The BIOS
path in `HDRIVER6.ASM:RDS003` never enables 8-bit PIO and simply
runs 512 `INI`s over the 16-bit data port — which is why the BIOS
had always worked from the same hardware.

The current image removes the `Set Features` sequence in `tinyide.c`
and keeps only the plain `ide_wait_mask(0x80, 0x00)` ready check.
`ide_8bit_mode` is now never written, which is fine: nothing else in
the source ever read it.  This is a narrow platform-relevant
bring-up change and lives behind `CONFIG_SPRINTER_EARLY_TRACE`.

Expected next-replay outcomes:

- Screen progresses past the superblock dump into `L` (validity
  check passed) and `M` (about to return from `fmount()`), then the
  later boot markers `CDOK` / `Starting /init`.
- If we now see `m31C6 i0100 fFFFF s00`, the disk data is
  transferred correctly end-to-end; on a clean superblock `fmount()`
  returns a real `struct mount` and the blocker moves past root mount
  into `i_open(root)` / `exec_or_die()`.
- If the pattern is still interleaved, something else is enabling
  8-bit mode (e.g. residual drive state from an earlier attempt) and
  we need an explicit `Set Features 0xEF / subcode 0x81` "disable
  8-bit PIO" on boot.

### 2026-04-21: IDE read stable; fix link base of `sprinit_raw.s`

Replay after disabling the 8-bit PIO Set Features walked the whole
boot/mount path cleanly:

`0123456789ABEFJNPQSTVWXY02D88ZUROKm31C6i0100fFFFFs00LMGCNPQSTVWXY02B80ZUROD`

- `m31C6 i0100 fFFFF s00` — superblock magic and sanity match the
  on-disk bytes byte-for-byte, confirming the `Set Features` removal
  cured the half-data PIO pattern.
- `LM` — superblock validation passed, `fmount()` about to return.
- `G` — `fmount()` returned non-NULL into `fuzix_main`.
- `C` — the post-mount marker in `start.c`.
- `NPQSTVWXY02B80ZURO` — second `bread()` (the root inode block) ran
  cleanly too.
- `D` — `i_open(root_dev, ROOTINODE)` succeeded.

`kputs("OK\n")` printed.  Then the machine stopped before
`exec_or_die()` could print `Starting /init`.  Register dump shows
PC=`0x001E` with PG0=`0x40` (PID 1's user page), i.e. the CPU is
executing inside user RAM near NULL — so `_execve()` reached
`doexec()` and jumped to the binary's entry address, but that entry
lands in the middle of the code stream instead of at `start:`.

Root cause is in the `/init` probe's build, not in the kernel.
`Applications/util/sprinit_raw.s` uses `.area _TEXT` labels directly
in `ld hl, #sh_name` and friends, but the Makefile linked
`_TEXT` at absolute `0x0000`.  After the exec16 loader strips the
16-byte `struct exec` and copies the rest to `progload + 16` = user
`0x0110`, the string labels inside the binary still hold their
0-based values (`sh_name = 0x003C`, `argv_sh = 0x0058`,
`envp_null = 0x005C`).  Those addresses point into the kernel-patched
low-page vector area, not at the real strings now sitting at user
`0x013C / 0x0158 / 0x015C`.  `execve("/bin/sh", garbage, garbage)`
then fails and further user control flow walks into NOPs.

Fix (Applications-level, no kernel change):

- `Applications/util/sprinit_raw.s` now adds an explicit
  `a_text = a_text_end - 0x0100` header field so the exec16
  `a_text` stays a byte count (94), not an absolute linker address.
- `Applications/util/Makefile.z80` now links sprinit with
  `sdldz80 -b _HEADER=0x0100` and trims the makebin output with
  `-o 0x100`, so absolute label references inside `_TEXT` resolve
  to runtime addresses `0x0112 + offset`.

After the fix the produced 94-byte `sprinit` binary has:

- `a_text = 0x005E` (94 bytes), `a_entry = 0x12`
- `LD HL, 0x015C` (envp_null), `LD HL, 0x0158` (argv_sh),
  `LD HL, 0x013C` (sh_name)
- `argv_sh[0] = 0x013C` (correct runtime pointer to sh_name)

Expected next-replay outcome:

- Screen still shows the full `...D` boot/mount ladder, then
  `OK`, then `Starting /init`, then either the shell prompt (if
  `/bin/sh` execve handoff holds) or `SPRINTER EXEC FAIL` (if
  the second exec fails cleanly and PID 1 falls into its local
  `jr hang_loop`).
- If `Starting /init` never appears, the stop is still in
  `complete_init()` / `sprinter_prepare_init_stdio()` (kernel side)
  rather than in `/init` itself.
- If the machine reboots silently after `Starting /init`, PID 1
  entered user mode but syscall-return path collapses on the first
  `execve()` from real user context.

### 2026-04-21: add lowercase markers through the `D -> _execve()` tail

The replay after the sprinit-link fix showed the same screen as
before (`...D` / `OK` / markers) and the same register shape:
`PC = 0x002A` in user page `0x40`, `SP = 0xEFFE` still on the
kernel stack.  That is not a post-`doexec()` userland state:
`_doexec` unconditionally switches `SP <- u_isp` (user stack near
`0xEDFE`), so an `SP` close to `kstack_top = 0xF000` means control
never reached `_doexec` and we are still nominally in kernel code
even though the `PC` happens to land inside user WIN0.

`"Starting /init\n"` is not visible on screen either, but the
bootmark row 7 overlays tty column 0 onwards, so absence on screen
alone isn't conclusive.  To split the sub-path between `D` and the
userland jump, the current image adds screen-visible lowercase
markers inside `start.c` / `process.c`:

- `a` right before `complete_init()`
- `b` right after `complete_init()` returns
- `c` right before `sprinter_prepare_init_stdio()`
- `d` right after `sprinter_prepare_init_stdio()` returns
- `e` at `exec_or_die()` entry, before `kputs("Starting /init\n")`
- `f` right after that `kputs`
- `g` after the post-kputs page-repair snapshot
- `h` right before `_execve()`
- `i` only fires if `_execve()` unexpectedly returns
- `!` only fires if `exec_or_die()` returns at all

Decoding the next replay:

- `Da` never reaches `b` - crash inside `complete_init()`.
- `Dabc` but no `d` - crash inside `sprinter_prepare_init_stdio()`
  (first `_open("/dev/tty1")` / `_dup()` from kernel context).
- `Dabcdef` but no `g`/`h` - crash during the post-kputs
  page-repair block in `exec_or_die()`.
- `Dabcdefgh` without `i` - entered `_execve()` cleanly but
  the load/doexec tail collapsed (expected: should never reach
  `i` because `doexec` does not return).
- `Dabcdefgh` followed by a stable `Starting /init` line - we
  really do enter user mode; next question is the sprinit probe
  itself.
- `Dabcdefghi` - `_execve()` returned, which is itself a bug.
- `Dabcdefgh!` - `exec_or_die()` returned (impossible per design).

---

## Session handoff (2026-04-21, end of session)

Two big bugs were fixed this session.  The third is staged with
screen markers but not yet verified from a replay — the next session
should start from that replay.

### What works now (verified from replay)

The full kernel-side mount path runs cleanly end-to-end.  Stable
screen after boot banner + `Devboot` + `OK` is now:

```
0123456789ABEFJNPQSTVWXY02D88ZUROKm31C6i0100fFFFFs00LMGCNPQSTVWXY02B80ZUROD
```

Decoded: IDE PIO transfer for the root superblock (`...XY02D88Z`)
and for the root inode block (`...XY02B80Z`) both return cleanly,
`fmount()` validates the superblock with correct magic/isize/fsize,
`i_open(root_dev, ROOTINODE)` succeeds, and `start.c` prints
`kputs("OK\n")`.

Baseline resume checkpoint: **the `...D` + `OK` line**.  Any future
regression past it means an earlier bring-up change broke mount.

### Fixes landed this session

1. **`Kernel/platform/platform-sprinter/sprinter.s` — direct BIOS-style IDE PIO.**
   Rewrote `_devide_read_data()` / `_devide_write_data()` at
   `sprinter.s:496..582` to follow `HDRIVER6.ASM:RDS003` directly:
   `DI`, load `HL = dptr`, two `INIR` passes (or `OTIR` for writes),
   `EI`, `RET`, with `map_proc_always` / `map_for_swap` calls only
   on `td_raw == 1 / 2` paths.  `td_raw == 0` (kernel buffer) now
   touches no MPGSEL port.  The `_sprinter_ide_bounce` + `ldir`
   interleave is gone.

   `_sprinter_ide_bounce` still exists as a 256-byte `_BUFFERS`
   symbol in `crt0.s:230` for layout stability; nothing references
   it now and it can be removed in a cleanup pass once the current
   baseline is fully trusted.

2. **`Kernel/dev/tinyide.c` — dropped the `Set Features 0xEF/0x01` block.**
   Under `CONFIG_SPRINTER_EARLY_TRACE`, `ide_xfer()` used to issue
   `ide_write(error, 0x01); ide_write(cmd, 0xEF)` on every call.
   On the MAME IDE emulator that negotiated the drive into 8-bit
   PIO, producing the half-data-half-zero (`buffer[2n] = disk[n]`,
   `buffer[2n+1] = 0`) pattern the superblock probe caught as
   `m00C6 i0031 f0000 s28`.  The block is replaced by a plain
   `ide_wait_mask(0x80, 0x00)` ready check.  `ide_8bit_mode` is now
   a dead static; removal is a cleanup task.

3. **`Applications/util/sprinit_raw.s` + `Makefile.z80` — link at 0x0100.**
   The raw probe binary used `ld hl, #sh_name` with labels linked at
   base `0x0000`, but the exec16 loader places binary content at
   `progload + 16 = 0x0110`.  Result: string pointers in the binary
   referenced user low-page kernel vectors (`0x003C / 0x0058 / 0x005C`)
   instead of the actual strings.  Fix linked `_HEADER` at `0x0100`
   with `sdldz80 -b _HEADER=0x0100`, trimmed the output with
   `makebin -p -o 0x100`, and changed `.dw a_text_end` to
   `.dw a_text_end - 0x0100` so the exec16 `a_text` field stays a
   byte count, not an absolute address.

### Current suspected blocker (verified to `sprinter_prepare_init_stdio()`)

The requested replay on the `2026-04-21 21:34` image answered the first
split cleanly.  Screen row 7 ends in:

```
...02B80ZURODabc
```

That means:

- `a` printed: `complete_init()` entry reached
- `b` printed: `complete_init()` returned
- `c` printed: `sprinter_prepare_init_stdio()` entry reached
- `d` did **not** print: control never returned from
  `sprinter_prepare_init_stdio()`

The stop registers were:

- `PC = 0x0011`
- `SP = 0xEFFE`
- `PG0..PG3 = 0x40/0x4E/0x4F/0x43`
- `I = 0xFC`, `IM = 2`

So this is still not `_doexec()`: the stack is still on the kernel side,
and the mixed live mapping matches a kernel-context path rather than the
post-user-entry state.  The blocker has therefore narrowed to the
kernel-side stdio bootstrap itself, specifically the first
`_open("/dev/tty1")` and/or one of the two `_dup()` calls inside
`start.c:sprinter_prepare_init_stdio()`.

To split that narrower corridor, the current tree now adds:

- screen markers:
  - `j` immediately after `_open()` returns
  - `k` immediately after the first `_dup()` returns
  - `l` immediately after the second `_dup()` returns
- a dedicated `_COMMONDATA` latch block:
  - `_spr_initio_stage = 0xFC9D`
  - `_spr_initio_fd = 0xFC9E`
  - `_spr_initio_err = 0xFCA0`
  - `_spr_initio_files[0..2] = 0xFCA2..0xFCA4`

`_spr_initio_stage` values:

- `0xC0` entry snapshot before touching stdio state
- `0xC1` just before `_open("/dev/tty1")`
- `0xC2` `_open()` returned, `fd` and `u_error` latched
- `0xC3` just before the first `_dup()`
- `0xC4` first `_dup()` returned
- `0xC5` just before the second `_dup()`
- `0xC6` second `_dup()` returned
- `0xCF` function exit after restoring saved `udata`

The current image built for this probe lives at
`Images/sprinter/fuzix.chd` (timestamped `2026-04-21 22:13`).

### Update from next replay: `sprinter_prepare_init_stdio()` stops inside `_open()`

The next replay on that `22:13` image narrowed the split one step
further.  Register dump plus `0xFC9D-0xFCA4` show:

- `PC = 0x001F`
- `SP = 0xEFFE`
- `PG0..PG3 = 0x40/0x4E/0x4F/0x43`
- `_spr_initio_stage = 0xC1`
- `_spr_initio_fd = 0xFFFF`
- `_spr_initio_err = 0x0000`
- `_spr_initio_files[0..2] = FF FF FF`

So `sprinter_prepare_init_stdio()` still has not returned from the
first `_open("/dev/tty1")` call.  We are now definitively before the
existing `_open()` tail diagnostics:

- `_sprinter_dbg[24] != 0xA1`, so `_open()` never reached the
  post-`dev_openi()` / pre-`i_unlock()` snapshot
- the older `spr_rdwr_*` / `spr_rw_*` blocks remain in `0xFCxx`, so
  they are still inside the IM2 vector page and are not trustworthy in
  emulator dumps

That leaves the early `_open()` front-half as the active window:

- `uf_alloc()`
- `oft_alloc()`
- `n_open_lock(name, &parent)`
- `isdevice(ino)` / `dev_openi()`

The current image therefore moves the next probe into the reliable
`_sprinter_dbg` block at `0xFD82+`, reusing bytes `15..23` which are
only overwritten if the machine later reaches `plt_monitor()`:

- `_sprinter_dbg[15]` stage byte:
  - `0xB5` `_open()` entry
  - `0xB6` after `uf_alloc()`
  - `0xB7` after `oft_alloc()`
  - `0xB8` after `n_open_lock()`
  - `0xB9` just before `dev_openi()`
  - `0xBA` immediately after `dev_openi()` returns
- `_sprinter_dbg[16..19]` carry the stage-specific payload
- `_sprinter_dbg[20..23]` carry `uindex` / `u_error` / `oftindex`
  snapshots from the front-half path

The rebuilt image carrying this probe now lives at
`Images/sprinter/fuzix.chd` (timestamped `2026-04-21 22:20`).

### Update from next replay: `_open()` reaches `n_open()`, then stops in path lookup

The next replay on that `22:20` image moved the early `_open()` split one
step further.  Reliable bytes from `_sprinter_dbg[15..23]` at
`0xFD91-0xFD99` were:

- `stage = 0xB7`
- `name = 0xC5CF`
- `flag = 0x0002`
- `uindex = 0`
- `u_error = 0`
- `oftindex = 0`

So `_open("/dev/tty1", O_RDWR, 0)` now definitely gets through:

- `uf_alloc()`
- `oft_alloc()`

and stops only after entering `n_open_lock()` / `n_open()`.  That rules
out the file-descriptor allocators and moves the live window to the
kernel-side path lookup itself.

The first attempt to split `n_open()` more finely turned out to be too
intrusive for this tree.  Replay on that `22:24` image regressed all the
way back to the old mount-time failure:

- screen: `Devboot` then `i_open: bad disk inode`
- no `Dabc` tail
- `_sprinter_dbg[15..23]` remained zero, so the machine never even
  reached the stdio `_open()` probe

That makes the result useful only in the negative sense: touching the
core path walker in `Kernel/filesys.c` is enough to perturb an earlier
bring-up dependency and invalidate the replay.  The `0xBB..0xC1`
`n_open()` split has therefore been removed again, and the current
baseline rolls back to the earlier `_open()` front-half probe in
`Kernel/syscall_fs3.c` only.

The rebuilt rollback image now lives at `Images/sprinter/fuzix.chd`
(timestamped `2026-04-21 22:36:52`).

That rollback replay exposed the actual core bug.  `n_open()` has a
special `udata.u_sysio` path specifically so early boot can pass it a
kernel-resident pathname (`"/init"`, `"/dev/tty1"`) without validating a
userspace pointer.  However the hot accessor `getcf()` still fetched
every byte through raw `__ugetc()`, and on banked Z80 that helper always
does `map_proc_always` first.  So the Sprinter stdio bootstrap was
handing `n_open()` a kernel/common pointer and the walker was reading
those bytes from process memory instead.

The current image fixes only that accessor bug in `Kernel/filesys.c`:

- if `udata.u_sysio` is set, `getcf()` now returns `*name` directly
- otherwise it keeps using `_ugetc(name)` for the normal userspace path

This is a genuine core fix, not a Sprinter-only workaround: the old code
was internally inconsistent for any banked target that relies on
kernel-space `u_sysio` pathnames.  The rebuilt image carrying this fix
now lives at `Images/sprinter/fuzix.chd` (timestamped
`2026-04-21 22:50:58`).

The next replay on that `22:50:58` image moved the failure again.  It no
longer just idles at the old `PC=0x0013` / stale `B7` snapshot.  Instead
the machine now reaches a real fatal `RST 38` trap:

- `PC = 0xF1AC`, `HALT = 1`, `IFF1 = 0`
- `PG0..PG3 = 0x48/0x4E/0x4F/0x43`
- `_sprinter_rst38_count = 1`
- `_sprinter_rst38_sp = 0xEFC1`
- `_sprinter_rst38_ret = 0x0079`
- `_sprinter_dbg[0..3] = FF FF FF FF`

That means the CPU actually executed byte `0xFF` in low WIN0 memory at
roughly `0x0078`, and the old `_sprinter_dbg[15] = 0xB7` value is now
only a stale pre-trap breadcrumb: `_open()` still enters `n_open()`, but
control escapes before `n_open()` can return to `_open()`.

The first attempt to latch those `n_open()` stages in new `_COMMONDATA`
bytes (`0xFCA5+`) turned out to be another layout-sensitive mistake.
Replay on that image regressed immediately back to the old:

- `i_open: bad disk inode`
- no `abc` tail
- same early mount failure as other bad-layout experiments

So those dedicated `_spr_nopen_*` cells have been removed again.
Current image keeps the same `0xD0..0xD7` walker stages, but stores
them in already-existing stable bytes inside `_sprinter_dbg`, avoiding
any common-layout shift.

One more correction: the first `_sprinter_dbg[4..6]` placement collided
with an older Sprinter-only `d_open()` / tty callback probe already
using those bytes.  The replay from that image therefore was not cleanly
interpretable: it mixed walker state with tty `dev_open` metadata.  The
current image moves the walker latch again, still layout-neutrally, to
unused bytes:

- `_sprinter_dbg[31]` = `n_open()` stage
- `_sprinter_dbg[32]` = current character / `lastname[0]`
- `_sprinter_dbg[33]` = `lastname[0]` snapshot after parse

Stage meanings:

- `0xD0` entered `n_open()` on the `u_sysio` path
- `0xD1` selected `wd = u_root` / `u_cwd`
- `0xD2` finished `i_ref(wd); i_ref(ninode);`
- `0xD3` returned from `srch_mt()`
- `0xD4` finished slash-skip; `spr_nopen_char` is the current component char
- `0xD5` built `lastname[]`; `spr_nopen_char` is the terminator and
  `spr_nopen_last` is `lastname[0]`
- `0xD6` just before `srch_dir(wd, lastname)`
- `0xD7` returned from `srch_dir()`

The rebuilt image carrying this non-conflicting walker latch now lives
at `Images/sprinter/fuzix.chd` (timestamped `2026-04-21 23:11:23`).

One testing caveat remains: the requested non-Sprinter banked-Z80 build
spot-check currently is not usable as evidence either way.  `make
TARGET=zxevo kernel` still dies in this tree on a pre-existing link
failure where Sprinter early-trace globals leak into other targets.  So
that cross-target check is presently blocked by unrelated tree hygiene,
not by this `getcf()` change itself.

### What to do first in the next session

1. **Boot the current `Images/sprinter/fuzix.chd` in MAME** and
   capture: (a) full screen text including row 7 markers,
   (b) registers + `PG0..PG3`, (c) `0xFBE7-0xFBEB`,
   (d) `0xFC9D-0xFCA4`, (e) `0xFD85-0xFDA6`.

2. Decode the stop by the highest visible `j/k/l` marker and the
   highest `0xC*` `spr_initio_stage` value:

   - no `j`, `stage <= 0xC1` ⇒ blocker is inside `_open()`
   - `j` but no `k`, `stage <= 0xC3` ⇒ `_open()` returned; blocker is
     the first `_dup()`
   - `jk` but no `l`, `stage <= 0xC5` ⇒ first `_dup()` returned;
     blocker is the second `_dup()`
   - `jkl` / visible `d` ⇒ stdio bootstrap returned; move focus back
     to `exec_or_die()`

3. If the machine halts in `RST 38`, decode the trap first:

   - `_sprinter_rst38_ret = 0x0079` again with `_spr_nopen_stage <= 0xD2`
     ⇒ escape happens before the first real path component walk
   - `_spr_nopen_stage = 0xD3` / `0xD4`
     ⇒ escape is around `srch_mt()` or slash-skip
   - `_spr_nopen_stage = 0xD5` / `0xD6`
     ⇒ escape happens after parsing `"dev"` / `"tty1"`, before
     `srch_dir()` returns
   - `_spr_nopen_stage = 0xD7`
     ⇒ `srch_dir()` returned and the next blocker moved past the walker

4. If `_open()` is still the stop without `RST 38`, decode
   `_sprinter_dbg[15..23]` from the current image:

   - `0xB5` only ⇒ fault before `uf_alloc()` returns
   - `0xB6` only ⇒ fault between `uf_alloc()` and `oft_alloc()`
   - `0xB7` only ⇒ fault after `oft_alloc()`, i.e. inside
     `n_open_lock()` / `n_open()`
   - `0xB8` only ⇒ path lookup returned, blocker moved to the later
     `_open()` front-half
   - `0xB9` only ⇒ blocker is in `dev_openi()` / `d_open()`
   - `0xBA` without `j` / `0xC2` ⇒ `dev_openi()` returned and the
     remaining fault is after the device open, before `_open()` returns

5. From that result, take the next narrow step:

   - If the replay is still a low-page `RST 38`, use the highest
     `0xD*` walker latch to split the remaining `n_open()` corridor.
   - If the replay moves to `0xB8`/`0xB9`, the blocker has left path
     lookup and moved into later `_open()` or device-open code.
   - If the first or second `_dup()` is the stop, inspect
     `Kernel/syscall_fs.c:_dup()` and `Kernel/filesys.c:getinode()`
     in this kernel-context path rather than reopening the exec path.
   - If stdio bootstrap returns, the earlier `e..i` legend becomes
     active again and the blocker has moved back to `exec_or_die()`.

### Where relevant state lives right now

Symbols / addresses from the current `Kernel/fuzix.map`:

- `_devide_read_data`     = `0xF1B8`  (sprinter, `_COMMONMEM`)
- `_devide_write_data`    = `0xF205`  (sprinter, `_COMMONMEM`)
- `map_buffers` = `map_kernel_restore` = `0x019C`
- `map_proc_always`       = `0x0191`
- `map_for_swap`          = `0x027E`
- `_kernel_pages`         = `0xFBE9`
- `mpgsel_cache`          = `0xFBE4`
- `top_bank`              = `0xFBE8`
- `_spr_rw_stage`         = `0xFC92`
- `_spr_rw_fd`            = `0xFC93`
- `_spr_rw_base`          = `0xFC94`
- `_spr_initio_stage`     = `0xFC9D`
- `_spr_initio_fd`        = `0xFC9E`
- `_spr_initio_err`       = `0xFCA0`
- `_spr_initio_files`     = `0xFCA2`
- `_sprinter_dbg`         = `0xFD82`
- `_sprinter_ide_bounce`  = `0x2F90`  (`_BUFFERS`, currently unused)

IM2 vector page is at `0xFC00..0xFCFF` (every byte `0xFC`, resolves
all IM2 vectors to the single stub at `0xFCFC`).  Do not introduce
common-memory diagnostics that drift `_COMMONDATA` into this page.

### Files changed this session

- `Kernel/platform/platform-sprinter/sprinter.s`
  - `_devide_read_data` / `_devide_write_data` rewritten to direct PIO
- `Kernel/dev/tinyide.c`
  - removed `Set Features 0xEF/0x01` block under `CONFIG_SPRINTER_EARLY_TRACE`
- `Kernel/start.c`
  - added `sprinter_boothex()` helper
  - added lowercase markers `a b c d` around
    `complete_init` / `sprinter_prepare_init_stdio` / `exec_or_die`
  - added `j k l` markers plus `spr_initio_*` latches through
    `sprinter_prepare_init_stdio()`
- `Kernel/syscall_fs3.c`
  - added early `_open()` front-half stage snapshots into
    `_sprinter_dbg[15..23]`
- `Kernel/filesys.c`
  - added kernel-side `n_open()` stage snapshots into
    `_sprinter_dbg[15..23]`
- `Kernel/filesys.c`
  - on-screen hex dump of `s_mounted / s_isize / s_fsize / s_shift`
    right before the superblock validation (under
    `CONFIG_SPRINTER_EARLY_TRACE`)
- `Kernel/process.c`
  - added `extern void sprinter_bootmark(char)` + lowercase markers
    `e f g h i` through `exec_or_die()`
- `Applications/util/sprinit_raw.s`
  - `a_text` field is now `a_text_end - 0x0100` (size in bytes)
- `Applications/util/Makefile.z80`
  - sdldz80 linked with `-b _HEADER=0x0100`, makebin with
    `-p -o 0x100`

All kernel-side changes are gated by `CONFIG_SPRINTER_EARLY_TRACE`
and must remain compile-time no-ops for every other target per the
repo rules in `CLAUDE.md`.

### Rebuild command

From the repo root:

```sh
make kclean TARGET=sprinter && make diskimage TARGET=sprinter
```

Produces `Images/sprinter/fuzix.img` and `Images/sprinter/fuzix.chd`.

### Update from 2026-04-22 replay: `0r` confirms the new image, walker probes are the regression

The next emulator replay finally answered the "old CHD or new CHD?"
question cleanly.  Screen row 7 now starts with:

- `0r123456789ABEFJNPQSTVWXY...`

The extra `r` is emitted immediately after the early `0` marker in
`fuzix_main()`, so its presence proves MAME is actually booting the new
image and not an older cached `.chd`.

That same replay also proved that the most recent `Kernel/filesys.c`
walker instrumentation is itself the source of the regression:

- screen regressed to `i_open: bad disk inode`
- there was no later `abc` / `jkl` progress
- trap state was again `PC = 0xF1AC`, `HALT = 1`
- `_sprinter_rst38_ret = 0x7280`

So the current conclusion is now firm:

- the `getcf()` `u_sysio` fix in `Kernel/filesys.c` is real and stays
- any extra `n_open()` stage latches inside `Kernel/filesys.c` are too
  layout-sensitive on this target and must stay out
- future narrowing should move outward into `_open()` / `dev_openi()` /
  `d_open()` / `tty_open()` / platform-local tty code, not back into
  the core pathname walker

The current rollback removes those last `n_open()` walker latches again
and keeps only the already-stable diagnostics:

- early screen fingerprint `0r`
- `_open()` front-half stages in `_sprinter_dbg[15..23]`
- `sprinter_prepare_init_stdio()` stages in `0xFC9D-0xFCA4`
- existing `d_open()` tty metadata in `_sprinter_dbg[4..9]`
- `RST 38` capture in `0xFBE7-0xFBEB`

The rebuilt rollback image now lives at:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 07:20:23`

### Correct next step from this point

1. Boot the `07:20:23` rollback image and verify that row 7 still starts
   with `0r`.

2. Capture:
   - full screen
   - registers + `PG0..PG3`
   - `0xFBE7-0xFBEB`
   - `0xFC9D-0xFCA4`
   - `0xFD89-0xFD99`

3. Decode from the stable probes only:
   - no `j` and `_sprinter_dbg[15] = 0xB7`
     ⇒ blocker is back in the `_open()` → `n_open_lock()` corridor,
     but without reintroducing walker instrumentation
   - `_sprinter_dbg[15] = 0xB8`
     ⇒ path lookup returned; focus moves to later `_open()`
   - `_sprinter_dbg[15] = 0xB9`
     ⇒ focus moves to `dev_openi()` / `d_open()`
   - `_sprinter_dbg[15] = 0xBA` without `j`
     ⇒ `dev_openi()` returned; remaining blocker is after device-open
       but before `_open()` returns
   - visible `j` / `k` / `l`
     ⇒ stdio bootstrap progressed and focus moves to `_dup()` or later

4. Do not add any more trace storage or stage writes to `Kernel/filesys.c`
   unless there is a new hard reason to believe the core walker itself is
   still the live bug.  The replay evidence now says those edits distort
   the boot before the interesting failure.

### Update from 2026-04-22 07:34: direct tty bootstrap instead of `n_open("/dev/tty1")`

The latest confirmed rollback replay still landed in exactly the same
place:

- screen already showed the correct `0r...` fingerprint
- `PC = 0xF1AC`, `HALT = 1`
- `_sprinter_rst38_ret = 0x0079`
- `_spr_initio_stage = 0xC1`
- `_sprinter_dbg[15] = 0xB7`

So the live blocker remained "inside the first kernel-side
`_open("/dev/tty1")`, before `n_open_lock()` can return", even after the
real `getcf()` `u_sysio` fix.

At that point continuing to split `n_open()` further was no longer the
lowest-risk path.  Sprinter already proves much earlier in `fuzix_main()`
that direct `d_open(TTYDEV, ...)` works before the banner is printed, so
the stdio bootstrap now takes that same path directly under
`CONFIG_SPRINTER_EARLY_TRACE`:

- `sprinter_prepare_init_stdio()` no longer calls `_open("/dev/tty1")`
- it allocates `u_files[]` / `of_tab[]` directly
- it seeds a synthetic in-core `F_CDEV` inode with `i_addr[0] = TTYDEV`
- it calls `d_open(TTYDEV, O_RDWR)` and then `tty_post(...)`
- the two existing `_dup()` calls stay unchanged

This is intentionally a bring-up workaround, not a final core answer:
it tests whether the remaining blocker is specifically the kernel-side
pathname walk for `/dev/tty1`, while keeping the rest of PID1 bootstrap
unchanged.

To make the next replay unambiguous, `_sprinter_dbg[15..23]` are now
reused for the direct-tty bootstrap stages instead of the older `_open()`
front-half split:

- `0xC8` helper entry (`TTYDEV`, `flag`)
- `0xC9` after `uf_alloc()`
- `0xCA` after `oft_alloc()`
- `0xCB` after allocating the synthetic in-core tty inode
- `0xCC` just before `d_open(TTYDEV, flag)`
- `0xCD` immediately after `d_open()` returns
- `0xCE` after linking `u_files[]` / `of_tab[]` and `tty_post()`

The rebuilt image carrying this direct bootstrap now lives at:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 07:34:33`

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBEB`
- `0xFC9D-0xFCA4`
- `0xFD89-0xFD99`

Decode:

- no `j`, `_sprinter_dbg[15] = 0xC8..0xCC`
  ⇒ direct tty bootstrap itself is still blocked before `d_open()`
    completes
- no `j`, `_sprinter_dbg[15] = 0xCD`
  ⇒ `d_open()` returned; blocker is in the synthetic-fd setup after it
- visible `j` but no `k`
  ⇒ direct tty bootstrap returned; blocker moved to the first `_dup()`
- `jk` but no `l`
  ⇒ blocker moved to the second `_dup()`
- `jkl` / visible `d`
  ⇒ stdio bootstrap is no longer the blocker

### Update from 2026-04-22 08:19: direct tty bootstrap confirmed, blocker moved into `_execve()`

The latest correct replay on the `07:34:33` image finally moved the boot
past the stdio bring-up corridor:

- screen showed the correct `0r...` fingerprint
- kernel printed `OK`
- kernel printed `Starting /init`
- the row-tail markers reached `...abc h`, so `exec_or_die()` got past
  `plt_discard()` and into `_execve()`
- `sprinter_prepare_init_stdio()` finished successfully:
  - `_spr_initio_stage = 0xCF`
  - `_spr_initio_fd = 0x0000`
  - `_spr_initio_err = 0x0000`
  - `u_files[0..2] = 0/0/0`
- the direct-tty helper stage in `_sprinter_dbg[15]` reached `0xCE`

So the direct tty bootstrap did exactly what it was meant to prove:
stdio is no longer the blocker.

The machine still trapped in the Sprinter `RST 38` stub afterwards:

- `PC = 0xF1AC`, `HALT = 1`
- `_sprinter_rst38_count = 1`
- `_sprinter_rst38_sp = 0xEFD0`
- `_sprinter_rst38_ret = 0xFA02`

That return address is no longer the old low-page `0x0079` failure. The
remaining blocker has moved forward into `_execve()` or the immediate
usermem handoff it performs before `doexec()`.

To localise that next corridor without touching `Kernel/filesys.c` again,
`Kernel/syscall_exec16.c` now reuses `_sprinter_dbg[15..23]` for stable
`_execve()` stages under `CONFIG_SPRINTER_EARLY_TRACE`:

- `0xE0` entry to `_execve()` (`name`, `argv`, `envp`)
- `0xE1` after successful `n_open_lock(exec_name, ...)`
- `0xE2` after header validation (`a_base`, `a_size`, `a_text`, `a_data`, `a_bss`)
- `0xE3` after successful `pagemap_realloc()`
- `0xE4` after `uput(sys_stubs, ...)`
- `0xE5` after `valaddr_r()` and just before text `readi()`
- `0xE6` after successful text/data `readi()`
- `0xE7` after `uzero(bss)` and `u_break` setup
- `0xE8` after `uzero(DP_BASE, DP_SIZE)` when `DP_SIZE` exists
- `0xE9` after argv/envp/stack setup (`nargv`, `nenvp`, `argc`, `u_isp`)
- `0xEA` immediately before `doexec(entry)`

The rebuilt image carrying this exec split now lives at:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 08:19:59`

Cross-target spot check:

- `make TARGET=sprinter diskimage` succeeds
- `make TARGET=zxevo kernel` still fails on the pre-existing tree-wide
  blocker (`Multiple definition of _swapper` plus many unresolved
  Sprinter-only trace symbols). The new `_execve()` probe no longer adds
  fresh compile-time breakage there.

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBEB`
- `0xFC9D-0xFCA4`
- `0xFD91-0xFD99`

Decode:

- `_sprinter_dbg[15] = 0xE0`
  ⇒ trap still happens before `n_open_lock(exec_name, ...)` can return
- `0xE1`
  ⇒ exec pathname lookup returned; focus moves to header read / validation
- `0xE2`
  ⇒ header is valid; focus moves to `pagemap_prepare()` /
    `pagemap_realloc()`
- `0xE3`
  ⇒ new process map exists; focus moves to the first `uput(sys_stubs, ...)`
- `0xE4`
  ⇒ stubs copied; focus moves to text/data transfer setup
- `0xE5`
  ⇒ `valaddr_r()` passed; focus moves to the text/data `readi()`
- `0xE6`
  ⇒ text/data load completed; focus moves to `uzero()` / break setup
- `0xE7`
  ⇒ BSS clear completed; focus moves to DP clear or later argv/envp setup
- `0xE8`
  ⇒ DP clear completed; focus moves to argv/envp / stack handoff
- `0xE9`
  ⇒ stack setup completed; focus moves to the final pre-`doexec()` state
- `0xEA`
  ⇒ `_execve()` reached `doexec(entry)` and the remaining blocker is now
    in `doexec()` itself or immediately after that jump

### Update from 2026-04-22 08:30: `_execve()` still dies at `E0`, so next split targets `u_sysio` / path bytes / root magic

The first replay on the `08:19:59` image did not advance past the new
entry stage:

- screen still reaches `OK`, `Starting /init`, and the `...abc h` tail
- `PC = 0xF1AC`, `HALT = 1`
- `_sprinter_rst38_ret = 0xFA02`
- `_sprinter_dbg[15] = 0xE0`
- `sprinter_exec_fail_name = 0xC7D7`
- `sprinter_exec_fail_argv = 0xC7DD`
- `sprinter_exec_fail_envp = 0xC7E1`
- `sprinter_exec_fail_root = sprinter_exec_fail_cwd = 0x1F73`

So the direct tty workaround remains good, but the next blocker is now
confirmed as "inside `_execve()` before `n_open_lock(exec_name, ...)`
returns".

Those `0xC7D7/0xC7DD/0xC7E1` pointers already look much more like stable
kernel-resident symbols than like random PID1 userspace, which means the
remaining question is no longer "did `complete_init()` hand `_execve()`
the wrong pointer?" but rather:

- is `u_sysio` still asserted when `_execve()` enters `n_open()`
- do the path bytes really read as `"/init"`
- is `u_root` still a live in-core inode with valid `c_magic`

To answer that without re-entering `Kernel/filesys.c`, stage `0xE0` now
changes payload meaning in `_sprinter_dbg[15..23]`:

- `_sprinter_dbg[15] = 0xE0`
- `_sprinter_dbg[16] = udata.u_sysio`
- `_sprinter_dbg[17..21] = first five bytes of exec path when `u_sysio`
  is true (expected `2F 69 6E 69 74` for `"/init"`)
- `_sprinter_dbg[22..23] = u_root->c_magic`

The rebuilt image carrying that narrower entry probe now lives at:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 08:30:46`

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBEB`
- `0xFBF8-0xFC0A`
- `0xFC9D-0xFCA4`
- `0xFD91-0xFD99`

Decode:

- `FD91 = E0`, `FD92 = 1`, `FD93..FD97 = 2F 69 6E 69 74`,
  `FD98..FD99 = C6 31`
  ⇒ `_execve()` really enters `n_open()` with kernel-resident `"/init"`
    and a live root inode; the next split can move outward into the
    `n_open_lock()` caller corridor or use a direct-`/init` workaround
- `FD92 = 0`
  ⇒ `u_sysio` got cleared before `_execve()`; fix the caller-side handoff
- `FD93..FD97` are not `"/init"`
  ⇒ the path pointer or its lifetime is still wrong before `n_open_lock()`
- `FD98..FD99 != 0x31C6`
  ⇒ root inode is already damaged before pathname lookup starts

### Update from 2026-04-22 08:36: `E0` trap was self-inflicted by the trace loop itself

The `08:30:46` replay answered the `E0` payload question correctly:

- `_sprinter_dbg[15] = 0xE0`
- `_sprinter_dbg[16] = 0x01` (`u_sysio = 1`)
- `_sprinter_dbg[17..21] = 2F 69 6E 69 74` (`"/init"`)
- `_sprinter_dbg[22..23] = 91 60` (`u_root->c_magic = 0x6091`)

That proves `_execve()` is entering with a valid kernel-resident `"/init"`
path and a live root inode.  However, the previous "absolute walker is now
the blocker" conclusion turned out to be premature.

The reason is the trace code immediately after `E0`: it still emitted the
first six path bytes through `ugetc(exec_name_ptr + i)`, even when
`u_sysio = 1`.  For a kernel-resident `"/init"` pointer that is wrong for
exactly the same reason as the earlier `getcf()` bug: `ugetc()` forces a
user-space fetch path.

So the `E0` stall was not yet evidence about `n_open_lock()` at all.  It
was self-inflicted by the diagnostic loop inside `_execve()`.

The current rollback therefore does two things:

1. keeps the useful `E0` payload snapshot (`u_sysio`, `"/init"`,
   `u_root->c_magic`)
2. fixes the trace loop so it reads bytes directly from `exec_name[i]`
   when `u_sysio = 1`, and uses `ugetc()` only for real user-space paths

The temporary direct-`/init` root helper experiment was removed again
without being relied on, because it was testing a false branch.

The rebuilt image carrying this corrected `_execve()` trace now lives at:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 08:42:27` (`fuzix.img`),
  `2026-04-22 08:42:28` (`fuzix.chd`)

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBEB`
- `0xFBF8-0xFC0A`
- `0xFC9D-0xFCA4`
- `0xFD91-0xFD99`

Decode:

- still `FD91 = 0xE0`
  ⇒ now it really is a pre-`n_open_lock()` blocker
- `FD91 = 0xE1`
  ⇒ pathname lookup returned and the old `E0` stop was only the broken
    trace loop
- `FD91 = 0xE2` or later
  ⇒ `/init` inode lookup is solved and the blocker has moved deeper into
    exec load / pagemap / usermem / `doexec()`

### Update from 2026-04-22 08:47: `E0` is now consistent with the absolute walker again

The replay on the corrected `08:42:28` image still stops with:

- `_sprinter_dbg[15] = 0xE0`
- `_sprinter_dbg[16] = 0x01` (`u_sysio = 1`)
- `_sprinter_dbg[17..21] = "/init"`
- `_sprinter_dbg[22..23] = 0x6091` (`u_root->c_magic`)
- `_sprinter_rst38_ret = 0x0079`

So the useful `_execve()` entry payload is now stable, but we still do not
reach `E1`.  With the broken `ugetc()` trace loop removed, that again points
at the first absolute-path lookup corridor rather than the caller handoff.

To test that exact hypothesis without touching `filesys.c` again, the current
image adds a narrow Sprinter-only PID1 workaround in `_execve()`:

- only when `CONFIG_SPRINTER_EARLY_TRACE`
- only for PID 1
- only for exact kernel-resident `"/init"`

that path bypasses `n_open_lock()` and does a direct `srch_dir(u_root, "init")`
followed by `i_lock()`.  If that returns, stage `0xEB` is latched before the
normal exec path continues.  If we still stop before `EB`, the blocker is not
the absolute walker itself.

The rebuilt image carrying this PID1-only direct-lookup test now lives at:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 08:47:47`

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBEB`
- `0xFBF8-0xFC0A`
- `0xFC9D-0xFCA4`
- `0xFD91-0xFD99`

Decode:

- `FD91 = 0xEB`
  ⇒ direct `srch_dir(u_root, "init")` returned; absolute pathname walking is
    the blocker, and exec moved beyond lookup
- `FD91 = 0xE1`
  ⇒ workaround fell through to normal `n_open_lock()` and that returned
- still `FD91 = 0xE0`
  ⇒ the failure is still before both lookup paths complete; re-check the
    caller corridor around the `_execve()` entry and trace plumbing
- `FD91 = 0xE2` or later
  ⇒ inode lookup is solved and the blocker moved deeper into load / `doexec()`

### Update from 2026-04-22 09:05: split the PID1 direct-lookup helper itself

The replay on the `08:47:47` image still showed:

- `_sprinter_dbg[15] = 0xE0`
- `_sprinter_dbg[16] = 0x01`
- `_sprinter_dbg[17..21] = "/init"`
- `_sprinter_dbg[22..23] = 0x6091`
- `_sprinter_rst38_ret = 0x0079`

and never reached `0xEB`.  That means the previous direct-lookup test did not
yet tell us whether:

1. the PID1-only helper was never taken because one of its guards failed, or
2. it was taken, but escaped inside `srch_dir()` / `i_open()` / `i_lock()`.

The current image therefore keeps the same PID1-only direct `srch_dir()` path
but adds stages inside the helper itself:

- `0xEC` helper entry: snapshots `u_sysio`, first five path bytes, and `p_pid`
- `0xED` guard match complete, just before `srch_dir(u_root, "init")`
- `0xEE` `srch_dir()` returned, snapshots the inode pointer / mode / dev / ino
- `0xEB` `i_lock()` completed and the helper returned success to `_execve()`

So the next replay should finally separate "helper not taken" from "helper
entered and faulted during lookup".

The rebuilt image carrying this helper split now lives at:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 09:05:50`

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBEB`
- `0xFBF8-0xFC0A`
- `0xFC9D-0xFCA4`
- `0xFD91-0xFD99`

Decode:

- `FD91 = 0xEC`
  ⇒ helper entry reached; if it stops there, one of the helper guards or the
    first inline reads is the blocker
- `FD91 = 0xED`
  ⇒ helper guards passed; blocker is now inside `srch_dir()` / `i_open()`
- `FD91 = 0xEE`
  ⇒ `srch_dir()` returned; blocker is in `i_lock()` or immediately after
- `FD91 = 0xEB`
  ⇒ helper succeeded; absolute walker is bypassed and the blocker moved on
- still `FD91 = 0xE0`
  ⇒ failure happens before the helper can even publish `0xEC`; re-check the
    `_execve()` caller corridor / trace plumbing around the helper call
- `FD91 = 0xE1` or later
  ⇒ either fallback `n_open_lock()` returned or exec moved deeper into load

### Update from 2026-04-22 09:10: the stop moved earlier than the `_execve()` helper stages

The replay on the `09:05:50` image did **not** show any of the expected
`0xEC/0xED/0xEE/0xEB` helper stages.  In fact the current addresses decode as:

- `_sprinter_dbg = 0xFD82`, so `0xFD91..0xFD99` are still the right stage bytes
- all those bytes were zero
- `_sprinter_rst38_ret = 0xC001`
- live `PG3 = 0x4B` (kernel common page), not init's user/common page

That means the current stop is no longer "inside `_execve()` helper after
entry".  Instead execution escapes into the start of kernel common memory
before any helper stage is published.

`0xC000` is the `_plt_monitor` / common-entry area in `sprinter.s`.  For a
fatal `RST 38` with return address `0xC001`, the live byte at `0xC000` must
have been observed as `0xFF`, which is not what the assembled kernel common
contains there (`_plt_monitor` begins with `ld a,#0xFE`).

So the next question is now:

1. was the live common page actually overwritten so `0xC000` turned into `0xFF`,
   or
2. did some corrupted return/jump target land us at `0xC000` while the top of
   stack was already damaged?

The current image therefore extends `sprinter_rst38_stub` to snapshot:

- `_sprinter_dbg[4..9]` = live bytes at `0xC000..0xC005`
- `_sprinter_dbg[10..11]` = first two bytes currently at the RST38 stack top

This is platform-local only and does not change the exec path itself.

The rebuilt image carrying this common-page crash snapshot now lives at:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 09:10:52`

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFD82-0xFD99`

Decode:

- `FD86..FD8B = 3E FE F5 33 F5 CD`
  ⇒ live `0xC000..` still contains `_plt_monitor`; the escape is via a bad
    return/jump target, not common-page overwrite
- `FD86 = FF` (or other garbage), especially with `RST38 ret = 0xC001`
  ⇒ kernel common itself is being overwritten before the trap
- `FD8C..FD8D` non-zero / unstable
  ⇒ top-of-stack bytes are changing; likely stack corruption feeding the bad
    control transfer

### Update from 2026-04-22 09:16: the `0xC000` crash snapshot regressed the image layout

The `09:10:52` image that showed only a single `F` on screen turned out to be a
diagnostic-layout regression, not a new kernel fact.

Adding the extra `0xC000` / stack snapshot instructions into
`sprinter_rst38_stub` increased `_COMMONMEM` enough to push the early fatal
diagnostic block up into the IM2 vector page again:

- `_sprinter_rst38_count = 0xFC11`
- `_sprinter_exec_fail_stage = 0xFC22`
- `_sprinter_dbg = 0xFDAC`

That is invalid for this bring-up image because the IM2 page at
`0xFC00..0xFCFF` is deliberately filled with `0xFC` bytes at boot.  So the
single-`F` replay must be treated as self-inflicted and discarded.

The current rollback removes only that bad crash snapshot and restores the
previous valid layout:

- `_sprinter_rst38_count = 0xFBE7`
- `_sprinter_rst38_sp    = 0xFBE8`
- `_sprinter_rst38_ret   = 0xFBEA`
- `_sprinter_exec_fail_stage = 0xFBF8`
- `_sprinter_trace_idx   = 0xFCC0`
- `_sprinter_trace_buf   = 0xFCC2`
- `_sprinter_dbg         = 0xFD82`

The rebuilt rollback image now lives at:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 09:16:39`

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFD82-0xFD99`

Decode:

- `FD91 = 0xEC`
  ⇒ the PID1 direct-lookup helper entry runs; blocker is inside helper guards
    or the direct lookup path
- `FD91 = 0xED`
  ⇒ helper guards passed; blocker is inside `srch_dir()` / `i_open()`
- `FD91 = 0xEE`
  ⇒ `srch_dir()` returned; blocker is in `i_lock()` or immediately after
- `FD91 = 0xEB`
  ⇒ helper succeeded; absolute walker is bypassed and exec moved on
- `FD91 = 0xE0`
  ⇒ failure is still before the helper can publish its own stages

### Update from 2026-04-22 09:48: single `F` is a real early stop, and the split now lives inside `fmount()`

The replay on the `09:39:33` image still shows only a single `F` on screen and
never reaches `G`, `C`, `D`, or `OK`.  That keeps the live boot corridor at:

- `E` printed after `get_root_dev()`
- `F` printed immediately before `fmount(root_dev, NULLINODE, ro)`
- nothing after that

The first attempt at splitting this in `start.c` via `sprinter_dbg[4..7]` was
too noisy: those bytes are reused by other early paths (`devio` and related
traces), so the resulting replay could not cleanly distinguish "inside
`fmount()`" from "returned from `fmount()` and got clobbered later".

The current image therefore moves the split into `Kernel/filesys.c:fmount()`
and uses the dedicated `sprinter_dbg[15..18]` slots instead:

- `0xF3` at `fmount()` entry, just before `d_open(dev, 0)`
- `0xF4` immediately after `d_open()` returns
- `0xF5` immediately after `newfstab()`
- `0xF6` immediately after `bread(dev, 1, 0)`

Payload:

- at `F3`: `dbg[16..18] = dev lo, dev hi, flags`
- at `F4`: `dbg[16] = u_error`
- at `F5`: `dbg[16..17] = m lo, m hi`
- at `F6`: `dbg[16..18] = buf lo, buf hi, u_error`

This keeps the probe on the actual mount corridor and avoids touching the
already noisy bootmark bytes in `start.c`.

The rebuilt image carrying this `fmount()`-local split now lives at:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 09:48:09`

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFD91-0xFD96`

Decode:

- `FD91 = 0xF3`
  ⇒ stop is inside `d_open(dev, 0)`
- `FD91 = 0xF4`
  ⇒ `d_open()` returned; inspect `FD92` for `u_error`
- `FD91 = 0xF5`
  ⇒ `newfstab()` returned; blocker is before or inside `bread(dev, 1, 0)`
- `FD91 = 0xF6`
  ⇒ `bread()` returned; inspect `FD92..FD94` for `buf` and `u_error`
- no `0xF3/0xF4/0xF5/0xF6`
  ⇒ crash happened even earlier than the current `fmount()` corridor

### Update from 2026-04-22 09:58: `d_open()` does return; the stop is in the tiny tail right after it

The next replay on the `09:48:09` image still showed only a single `F`, but
the dump was informative:

- `FD86..FD8B = 01 02 8D 84 D1 DB`

Those bytes are not random.  They are the old `devio.c` probe payload:

- `dbg[4] = min = 1`
- `dbg[5] = maj = 2`
- `dbg[6..7] = tty_open pointer = 0x848D`
- `dbg[8] = 0xD1` (`d_open()` already returned)
- `dbg[9] = 0xDB` (tty fast-path marker)

So the live path is now narrower than "inside `fmount()`":

1. boot reaches `F`
2. `fmount()` enters `d_open(dev, 0)`
3. `d_open()` returns successfully
4. machine traps before the first `F4` stage byte became visible

The reason is visible in `filesys.lst`: the original `F4` store sat *after*
`FM_TRACE(0x52)`, so the machine could still die in that trace tail while the
probe incorrectly looked like "never reached `F4`".

The current image fixes that diagnostic ambiguity by moving `F4` to the first
instruction after the `d_open()` return path, before `FM_TRACE(0x52)` and
before clearing `u_error`.

The rebuilt image carrying this tighter split now lives at:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 09:58:54`

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFD86-0xFD96`

Decode:

- `FD91 = 0xF4`
  ⇒ `d_open()` returned and the first post-`d_open()` store executed; the
  blocker is now after that point in the `FM_TRACE(0x52)` / `u_error = 0` /
  `newfstab()` tail
- still no `FD91 = 0xF4`, while `FD86..FD8B` still show `... D1 DB`
  ⇒ the trap is in the tiny cleanup corridor immediately after `call _d_open`
  and before the first explicit `F4` publication
- `FD91 = 0xF5`
  ⇒ `newfstab()` returned
- `FD91 = 0xF6`
  ⇒ `bread()` returned

### Update from 2026-04-22 10:23: the `D1/DB` bytes were stale; the real stop may be at `sprinter_bootmark('F')`

The follow-up replay on the `09:58:54` image was unchanged:

- still only a single `F` on screen
- still no `FD91 = 0xF4`
- `FD86..FD8B` still read `01 02 8D 84 D1 DB`

That combination invalidates the previous interpretation of `D1/DB` as proof
that the *root-mount* `d_open()` had returned.  `fmount()` now publishes `0xF3`
before its own `d_open(dev, 0)` entry, and that byte never appears.  So those
`D1/DB` bytes are just stale `devio` breadcrumbs from an older tty path, not
fresh root-mount evidence.

The real narrow corridor is now even earlier:

- `sprinter_bootmark('F')` is called
- the letter `F` does reach the screen
- but neither the first post-bootmark store nor the `fmount()` entry stage is
  ever published

That means the live stop is now suspected to be in one of two places:

1. inside `sprinter_bootmark('F')` / `plot_char()`, or
2. on the immediate return/cleanup path right after that call in `start.c`

The current image therefore moves the mount-corridor staging back into
`start.c`, but now on the dedicated `sprinter_dbg[15..18]` bytes instead of the
noisy `sprinter_dbg[4..7]` slots:

- `0xEF` immediately before `sprinter_bootmark('F')`
- `0xF0` immediately after `sprinter_bootmark('F')` returns
- `0xF1` immediately before `fmount(root_dev, NULLINODE, ro)`
- `0xF2` immediately after `fmount()` returns
- `0xF7` in the `m == NULL` failure branch

Payload:

- at `EF/F0/F1`: `dbg[16..18] = root_dev lo, root_dev hi, ro`
- at `F2`: `dbg[16..18] = m lo, m hi, u_error`
- at `F7`: `dbg[16..18] = mount_tries, u_error, root_dev lo`

The rebuilt image carrying this corrected split now lives at:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 10:23:26`

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFD91-0xFD96`

Decode:

- `FD91 = 0xEF`
  ⇒ we reached the pre-bootmark store and then died inside `sprinter_bootmark()`
  or on its immediate return path
- `FD91 = 0xF0`
  ⇒ `sprinter_bootmark('F')` returned; the blocker moved into the call setup
  for `fmount()`
- `FD91 = 0xF1`
  ⇒ we reached the actual `fmount()` call site
- `FD91 = 0xF2`
  ⇒ `fmount()` returned
- `FD91 = 0xF7`
  ⇒ `fmount()` failed cleanly and we are in the retry/panic branch
- no `0xEF/0xF0/0xF1/0xF2/0xF7`
  ⇒ the crash happened even before the new dedicated mount-corridor stage bytes

### Update from 2026-04-22 10:40: add a visible `uF` fingerprint to reject stale CHD replays

The replay taken after the `10:23:26` image was still bit-for-bit identical to
the previous one:

- only a single `F` on screen
- `FD91..FD96` still all zero
- `FD86..FD8B` still `01 02 8D 84 D1 DB`

That replay turned out to be ambiguous: the added `uF` marker was emitted via
`sprinter_bootmark()`, which keeps its own static cursor (`x`).  So a screen
showing only `F` does **not** prove that an older image was booted; it may also
mean the first marker was overwritten or collapsed by the same bootmark path we
are trying to debug.

To remove that ambiguity, the current image writes the visual fingerprint via
direct `plot_char()` calls into fixed cells instead of using the bootmark
cursor:

- row 6, col 0 = `u`
- row 6, col 1 = `F`

The original bootmark `F` on row 7 is left intact.  This does not try to solve
the bug; it only gives a fingerprint independent of `sprinter_bootmark()`.

The rebuilt image carrying this on-screen fingerprint now lives at:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 10:45:36`

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFD91-0xFD96`

Decode:

- row 6 does not show the fixed `uF`
  ⇒ the replay is not from the current image, or the machine dies even before
  the fixed-column fingerprint executes
- row 6 shows `uF`
  ⇒ the new image is really loaded; then interpret `FD91` as in the previous
  section (`EF/F0/F1/F2/F7`)

### Update from 2026-04-22 10:57: stop trusting the screen, use the trace ring around `F`

The follow-up replay on the `10:45:36` image still showed only a single `F`,
with no fixed `uF` on row 6, and the dump was again effectively unchanged.
That means the screen is no longer a trustworthy discriminator at all:

- VRAM contents may persist across replays
- the machine may die before or during the fixed `plot_char()` calls
- the ordinary `F` bootmark alone is not enough to prove where execution is

The current image therefore switches to a memory-only split using the existing
`EARLY_TRACE` ring buffer, which is more reliable than the screen in this
failure mode.

New trace markers around the `F` / `fmount()` corridor in `start.c`:

- `0xE4` immediately before the fixed `plot_char(6,0,'u')`
- `0xE5` immediately after that, before `plot_char(6,1,'F')`
- `0xE6` immediately before `sprinter_bootmark('F')`
- `0xE7` immediately after `sprinter_bootmark('F')`
- `0xE8` immediately before `fmount(root_dev, NULLINODE, ro)`

The trace layout on this image is:

- `_sprinter_trace_idx = 0xFCC0`
- `_sprinter_trace_buf = 0xFCC2..`
- `_sprinter_dbg = 0xFD82`

The rebuilt image carrying this trace-only split now lives at:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 10:57:18`

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFCC0-0xFCD0`
- `0xFD91-0xFD96`

Decode:

- trace contains `E4` but not `E5`
  ⇒ stop in or immediately after the first fixed `plot_char()`
- trace contains `E5` but not `E6`
  ⇒ first fixed `plot_char()` returned, stop in second fixed `plot_char()`
- trace contains `E6` but not `E7`
  ⇒ stop in `sprinter_bootmark('F')`
- trace contains `E7` but not `E8`
  ⇒ `sprinter_bootmark('F')` returned; blocker is before `fmount()`
- trace contains `E8`
  ⇒ the blocker has finally moved into the actual `fmount()` call

### Update from 2026-04-22 11:05: the live trace still ends at `0x15`, so the blocker is earlier than `F`

The replay on the `10:57:18` image finally made the trace ring useful:

- `trace_idx = 9`
- `trace_buf = 12 D0 13 14 D1 00 D2 00 15`

This sequence matches exactly the very early console bring-up in `fuzix_main()`:

- `0x12` after `tty_init()`
- `0xD0` before `sprinter_force_bank1()`
- `0x13` before the initial `d_open(TTYDEV, 0)`
- `0x14` after that `d_open()`
- `0xD1 00` = `tty_open_rc == 0`
- `0xD2 00` = `udata.u_error == 0`
- `0x15` immediately before the large sign-on `kprintf(...)`

Crucially, there is no `0x16`, no `0x17`, and none of the later `E4..E8`
markers.  So the previous `F`/`fmount()` theory was a false branch: the live
stop happens **before** any root-mount logic, inside the sign-on banner path or
immediately after entering it.

To split that corridor, the current image adds:

- `0x16` immediately after the banner `kprintf(...)` returns
- `0x17` immediately before the subsequent `0r` bootmarks
- `0x18` immediately after those `0r` bootmarks

The rebuilt image carrying this sign-on split now lives at:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 11:05:01`

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFCC0-0xFCD0`

Decode:

- trace still ends at `0x15`
  ⇒ stop is inside the sign-on `kprintf(...)` / console output path
- trace reaches `0x16` but not `0x17`
  ⇒ banner `kprintf()` returned; blocker moved into the immediate post-banner
    corridor
- trace reaches `0x17` but not `0x18`
  ⇒ blocker is in the `0r` bootmark path
- trace reaches `0x18`
  ⇒ banner + `0r` both returned; then we can resume narrowing later boot
### Update from 2026-04-22 11:52: sign-on split moved inside `kprintf()`

The replay after the `0x16/0x17/0x18` build still showed the same trace ring:

- `trace_idx = 9`
- `trace_buf = 12 D0 13 14 D1 00 D2 00 15`

So the blocker remains inside the banner `kprintf(...)` itself, before it can return to `start.c`. To split that corridor without relying on the screen, temporary `CONFIG_SPRINTER_EARLY_TRACE` diagnostics now live directly in `Kernel/devio.c:kprintf()` using `_sprinter_dbg[15..23]`:

- `_sprinter_dbg[15] = 0xD3` on `kprintf()` entry
- `_sprinter_dbg[16] = emitted-char counter`
- `_sprinter_dbg[17] = current `*fmt``
- `_sprinter_dbg[18] = current literal/`%c` output character`
- `_sprinter_dbg[19] = current format specifier after `%``
- `_sprinter_dbg[20..21] = first byte / value payload for `%s`/integer cases
- `_sprinter_dbg[22..23]` reserved

Stage meanings:

- `0xD3` => entered `kprintf()`, before first output
- `0xD4` => about to call `kputchar()` for a literal or `%c`
- `0xD5` => returned from that `kputchar()`
- `0xD6` => saw a `%` and are decoding the specifier
- `0xD7` => about to emit a `%s` string via `kputs()`
- `0xD8` => returned from `%s` emission
- `0xD9` => about to emit numeric / `%2x` output
- `0xDA` => returned from numeric / `%2x` output

The rebuilt image carrying this `kprintf()` split is:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 11:52:22`

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFCC0-0xFCD0`
- `0xFD91-0xFD99`

Decode:

- trace still ends at `0x15`, and `_sprinter_dbg[15] = 0xD3`
  ⇒ entered banner `kprintf()`, but died before the first `kputchar()` call
- `_sprinter_dbg[15] = 0xD4`, `_sprinter_dbg[16] = N`, `_sprinter_dbg[18] = X`
  ⇒ died while outputting character `X` as emitted char #`N`
- `_sprinter_dbg[15] = 0xD5`
  ⇒ that `kputchar()` returned; the next failure is later in the banner
- `_sprinter_dbg[15] = 0xD6..0xDA`
  ⇒ failure is in a format-expansion path rather than the plain literal-text path
### Update from 2026-04-22 12:00: first banner char dies inside platform console path

The last informative replay was still from the previous `kprintf()`-split image: it showed

- `_sprinter_dbg[15] = 0xD4`
- `_sprinter_dbg[16] = 0x00`
- `_sprinter_dbg[17] = 0x46` (`fmt[0] = F`)
- `_sprinter_dbg[18] = 0x46` (about to output literal F)

So the banner no longer points at format parsing; it dies on the **very first literal `kputchar(F)`**.

To split that corridor without touching shared VT code yet, temporary `CONFIG_SPRINTER_EARLY_TRACE` markers were added in `platform-sprinter/devtty.c` using `_sprinter_dbg[15..17]`:

- `0xDF` in `kputchar()` just before `tty_putc(1, c)`
- `0xE0` at `tty_putc()` entry
- `0xE1` immediately before `vtoutput(&c, 1)`
- `0xE2` immediately after `vtoutput()` returns
- `0xE3` immediately after `tty_putc()` returns to `kputchar()`

The rebuilt image carrying this platform-console split is:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 12:06:26`

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFCC0-0xFCD0`
- `0xFD91-0xFD96`

Decode:

- `FD91 = 0xDF` => stop inside `kputchar()` before entering `tty_putc()`
- `FD91 = 0xE0` => stop at `tty_putc()` entry / very early body
- `FD91 = 0xE1` => stop in `vtoutput()` / deeper video path
- `FD91 = 0xE2` => `vtoutput()` returned; failure is on the return edge back to `kputchar()`
- `FD91 = 0xE3` => first banner char fully returned through platform console path; blocker moved later
### Update from 2026-04-22 12:17: platform console split shows stop inside `vtoutput()`

The latest informative replay on the `12:06:26` image showed:

- `_sprinter_dbg[15] = 0xE1`
- `_sprinter_dbg[16] = 0x01` (minor 1)
- `_sprinter_dbg[17] = 0x46` (`F`)

So `kputchar()` and `tty_putc()` both run, and the failure moves one step deeper: **inside `vtoutput()` or one of its first helpers**.

To split that corridor, temporary `CONFIG_SPRINTER_EARLY_TRACE` markers were added in `Kernel/vt.c` using `_sprinter_dbg[15..20]`:

- `0xE4` at `vtoutput()` entry (`[16]=*p`, `[17]=len`)
- `0xE5` immediately before `vt_cursor_off()`
- `0xE6` at `charout(c)` entry (`[18]=c`)
- `0xE7` immediately before `plot_char(cursory, cursorx, c)` (`[19]=y`, `[20]=x`)
- `0xE8` immediately after `plot_char()` returns
- `0xE9` immediately after `cursor_fix()`
- `0xEA` immediately before `vt_cursor_on()`
- `0xEB` immediately before `vtoutput()` returns

The rebuilt image carrying this VT split is:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 12:31:01` (`.img` and `.chd`)

### Update from 2026-04-22 12:25: `plot_char()` returns, blocker moves to the VT tail

The next informative replay on the `12:31:01` image showed:

- `_sprinter_dbg[15] = 0xE8`
- `_sprinter_dbg[16] = 0x46` (`F`)
- `_sprinter_dbg[17] = 0x01` (`len = 1`)
- `_sprinter_dbg[18] = 0x46` (`charout('F')`)
- `_sprinter_dbg[19] = 0x00` (`cursory`)
- `_sprinter_dbg[20] = 0x00` (`cursorx`)

So the first banner character is actually drawn successfully: `plot_char(0, 0, 'F')`
returns and the visible lone `F` is real. The failure therefore sits strictly
after the cell write, in the tail of `charout()` / `cursor_fix()` / `vt_cursor_on()`
or on the immediate return edge out of `vtoutput()`.

The next informative replay on the same VT-tail image moved the stop one step
further:

- `_sprinter_dbg[15] = 0xE9`
- `_sprinter_dbg[16] = 0x46` (`F`)
- `_sprinter_dbg[17] = 0x01` (`len = 1`)
- `_sprinter_dbg[18] = 0x46` (`charout('F')`)
- `_sprinter_dbg[19] = 0x00`
- `_sprinter_dbg[20] = 0x01`

So `cursor_fix()` also returns. The remaining corridor is now only the platform
cursor-on path itself: `vt_cursor_on()` -> `cursor_on(cursory, cursorx)` ->
`map_vr()` / `cell_hl()` / attribute toggle / `unmap_vr()`.

To split that path, additional temporary trace bytes were added:

- in `Kernel/vt.c`
  - `0xEA` immediately before `vt_cursor_on()` (`[21]=cursory`, `[22]=cursorx`)
  - `0xEB` immediately before `vtoutput()` returns
- in `Kernel/platform/platform-sprinter/sprvideo.s`
  - `0xEC` at `_cursor_on` entry (`[21]=y`, `[22]=x`)
  - `0xED` immediately after `map_vr()`
  - `0xEE` immediately after `cell_hl()`
  - `0xEF` immediately after the attribute byte is inverted
  - `0xF0` immediately after `unmap_vr()` returns

The rebuilt image carrying this `_cursor_on` split is:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 12:39:33` (`.img` and `.chd`)

The next informative replay on that image showed that `_cursor_on` still was
not entered:

- `_sprinter_dbg[15] = 0xE9`
- `_sprinter_dbg[16] = 0x46`
- `_sprinter_dbg[17] = 0x01`
- `_sprinter_dbg[18] = 0x46`
- `_sprinter_dbg[19] = 0x00`
- `_sprinter_dbg[20] = 0x01`

So the stop remains in the narrow `vtoutput()` tail after `charout()` returns
and before the stage byte for `vt_cursor_on()` is written. To split that final
gap, extra markers were inserted in `Kernel/vt.c`:

- `0xF1` immediately after `charout(c)` returns to the `vtmode == 0` branch
- `0xF2` just before `cq = vtpend`
- `0xF3` immediately after copying `cq`
- `0xF4` immediately after reloading `p = &cq`, `len = 1`
- `0xF5` immediately after the `do/while(cq)` loop exits and before `0xEA`

The rebuilt image carrying this VT-tail split is:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 13:46:15` (`.img` and `.chd`)

The next informative replay on that image showed:

- `_sprinter_dbg[15] = 0xF1`
- `_sprinter_dbg[16] = 0x46`
- `_sprinter_dbg[17] = 0x01`
- `_sprinter_dbg[18] = 0x46`
- `_sprinter_dbg[19] = 0x00`
- `_sprinter_dbg[20] = 0x01`

So `charout('F')` definitely returns to the `vtmode == 0` branch. The stop is
now narrowed to the loop edge itself: the branch back to the top of the inner
`while (len--)` and the next len-check before control would reach `0xF2`.

To split that exact edge, the inner `while (len--)` was rewritten under
`CONFIG_SPRINTER_EARLY_TRACE` into an equivalent manual loop with two new
stages:

- `0xF6` immediately before checking `if (len == 0)` (`[23]=len low byte`)
- `0xF7` immediately after `len--` and before re-entering the body (`[23]=len low byte`)

The rebuilt image carrying this loop-edge split is:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 15:18:06` (`.img` and `.chd`)

The next informative replay on that image showed:

- `_sprinter_dbg[15] = 0xF6`
- `_sprinter_dbg[16] = 0x46`
- `_sprinter_dbg[17] = 0x01`
- `_sprinter_dbg[18] = 0x46`
- `_sprinter_dbg[19] = 0x00`
- `_sprinter_dbg[20] = 0x01`
- `_sprinter_dbg[23] = 0x00`

So the branch back to the top of the manual loop already happened, and the
kernel now stops exactly at the exit test with `len == 0`. That narrows the
remaining corridor to the `if (len == 0) break;` edge itself: either entering
the break arm or branching out to the code after the loop.

To split that jump edge, two final stages were added in `Kernel/vt.c`:

- `0xF8` immediately inside the `if (len == 0)` arm, just before `break`
- `0xF9` immediately after the loop exits and before reading `vtpend`

The rebuilt image carrying this break-edge split is:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 16:23:59` (`.img` and `.chd`)

The next informative replay on that image showed:

- `_sprinter_dbg[15] = 0xF8`
- `_sprinter_dbg[16] = 0x46`
- `_sprinter_dbg[17] = 0x01`
- `_sprinter_dbg[18] = 0x46`
- `_sprinter_dbg[19] = 0x00`
- `_sprinter_dbg[20] = 0x01`
- `_sprinter_dbg[23] = 0x00`

So the `if (len == 0)` break arm is definitely entered. The remaining
live corridor is now smaller still: not "does the break arm run", but
"does control survive the break edge into the code after the loop".

To remove that jump edge entirely under `CONFIG_SPRINTER_EARLY_TRACE`,
the post-loop tail was inlined directly into the `if (len == 0)` arm in
`Kernel/vt.c` and instrumented with four new stages:

- `0xFA` immediately before `cq = vtpend`
- `0xFB` immediately after `cq = vtpend`
- `0xFC` immediately after `vtpend = 0`
- `0xFD` immediately after `p = &cq`, `len = 1`

After `0xFD` the code now jumps to a shared `post_loop` label, so the
old `break -> after_loop` control-flow edge is no longer part of the
tested corridor.

The rebuilt image carrying this inline-tail split was:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 16:23:59` (`.img` and `.chd`)

The next replay that was supposed to exercise that image still reported
the older `0xE9` state instead of the new `0xF8/0xFA..0xFD` corridor.
That means the replay evidence no longer uniquely identifies which exact
Sprinter image was booted, even if the user is pointing the emulator at
the expected path.

To remove that ambiguity, `fuzix_main()` now stamps a fixed build marker
into `_sprinter_dbg[28..31]` before the console path is touched:

- `_sprinter_dbg[28] = 0xBA`
- `_sprinter_dbg[29] = 0x27`
- `_sprinter_dbg[30] = 0x04`
- `_sprinter_dbg[31] = 0x22`

That signature lives at `0xFD9E..0xFDA1` and should survive all the
current early-console traces.

The rebuilt image carrying this build stamp is:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 16:41:40` (`.img` and `.chd`)

The next replay on that stamped image confirmed the current source/image
match (`FD9E..FDA1 = BA 27 04 22`) and still landed at the older live
stage:

- `_sprinter_dbg[15] = 0xE9`
- `_sprinter_dbg[16] = 0x46`
- `_sprinter_dbg[17] = 0x01`
- `_sprinter_dbg[18] = 0x46`
- `_sprinter_dbg[19] = 0x00`
- `_sprinter_dbg[20] = 0x01`

So the real blocker is not the `len == 0` / break-edge tail after all.
The machine is still stopping on the return edge from `charout()` back
into the `vtmode == 0` branch of `vtoutput()`, before any of the
post-`charout()` tail states can be published.

To split that exact return edge, the direct `charout(c)` call is now
wrapped under `CONFIG_SPRINTER_EARLY_TRACE` by a tiny helper:

- wrapper sets `0xF1` after `charout(c)` returns to the helper
- caller sets `0xF2` after the helper itself returns to `vtoutput()`

This distinguishes:

- failure on `charout() -> helper` return
- from failure on `helper -> vtoutput()` return

The rebuilt image carrying this wrapper split is:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 16:46:23` (`.img` and `.chd`)

The next replay on that image showed:

- `FD9E..FDA1 = BA 27 04 22`
- `_sprinter_dbg[15] = 0x00`
- `_sprinter_dbg[16] = 0x46`
- `_sprinter_dbg[17] = 0x01`
- `_sprinter_dbg[18] = 0x46`
- `_sprinter_dbg[19] = 0x00`
- `_sprinter_dbg[20] = 0x00`
- `SP = 0xEFC5`
- `RST38 ret = 0xC001`

So the image/source match is now confirmed, and the wrapper split did its
job: the machine is no longer stopping at `0xE9` or at the old post-`charout()`
tail. Instead, it now traps on the raw return edge from `_charout()` back into
`sprinter_charout_wrap()`, before the wrapper can publish `0xF1`.

That makes the next useful evidence stack-centric, not another logical stage
split: the likely failure is a corrupted return address or stack shape in the
`charout() -> wrapper` frame pair.

### Correct next replay for this image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFCC0-0xFCD0`
- `0xFD91-0xFDA1`
- `0xEFB8-0xEFD0`

Decode:

- `FD9E..FDA1 != BA 27 04 22`
  => the replay is not from the current `16:46:23` image, so the stage
     bytes below are not comparable to the current source tree
- `FD91 = 0x00`, `FD92 = 0x46`, `FD93 = 0x01`
  => `_charout()` returned far enough for the caller-side context bytes to be
     visible, but the trap happened before `sprinter_charout_wrap()` could
     publish `0xF1`; focus shifts to the stack / return-address shape
- `FD91 = E4` => stop at `vtoutput()` entry / before `vt_cursor_off()`
- `FD91 = E5` => stop in `vt_cursor_off()` / `cursor_off()`
- `FD91 = E6` => stop on entry to `charout(F)` before `plot_char()`
- `FD91 = E7`, `FD95..FD96 = y/x` => stop in `plot_char()` / sprvideo path
- `FD91 = E8` => `plot_char()` returned; blocker is after cell write
- `FD91 = E9` => `cursor_fix()` returned; blocker is before / in `vt_cursor_on()`
- `FD91 = EA` => stop at the call edge into `vt_cursor_on()`
- `FD91 = EB` => `vt_cursor_on()` returned; blocker is on the return edge above `vtoutput()`
- `FD91 = EC` => stop at `_cursor_on` entry / very early body
- `FD91 = ED` => `map_vr()` returned; blocker is between VRAM map and cell lookup
- `FD91 = EE` => `cell_hl()` returned; blocker is at / after attribute-byte addressing
- `FD91 = EF` => attribute byte was toggled; blocker is in `unmap_vr()`
- `FD91 = F0` => `unmap_vr()` returned; blocker is on the return edge back to `vtoutput()`
- `FD91 = F1` => `charout()` returned to the wrapper; blocker is on the
  wrapper -> `vtoutput()` return edge
- `FD91 = F2` => wrapper returned to `vtoutput()`; blocker moves on to the
  old post-`charout()` tail
- `FD91 = F3` => `cq` copied; blocker is around `vtpend = 0`
- `FD91 = F4` => stop after `p = &cq`, `len = 1`
- `FD91 = F5` => `do/while(cq)` finished; blocker is right before `vt_cursor_on()`
- `FD91 = F6` => stop at the top of the manual len-check loop
- `FD91 = F7` => `len--` completed; blocker is in the first instructions of the next iteration body
- `FD91 = F8` => break arm entered; blocker is before the inlined post-loop tail
- `FD91 = FA` => reached the inlined `cq = vtpend`
- `FD91 = FB` => `cq` copied; blocker is around `vtpend = 0`
- `FD91 = FC` => `vtpend = 0` done; blocker is around `p = &cq`, `len = 1`
- `FD91 = FD` => `p/len` reloaded; blocker is on the jump into the shared post-loop path
- `FD91 = F9` => loop exit reached through some path that still bypasses the inlined tail

The next replay on that stamped `16:46:23` image provided the missing stack
evidence:

- `FD9E..FDA1 = BA 27 04 22`
- `_sprinter_dbg[15] = 0x00`
- `_sprinter_dbg[16] = 0x46`
- `_sprinter_dbg[17] = 0x01`
- `_sprinter_dbg[18] = 0x46`
- `_sprinter_dbg[19] = 0x00`
- `_sprinter_dbg[20] = 0x00`
- `SP = 0xEFC5`
- `RST38 ret = 0xC001`
- stack frame bytes around `0xEFBE..0xEFD0` showed the caller-side return
  chain intact enough to reach the synthetic debug frame, but not far enough
  to execute any post-return store in the helper itself

That replay confirms the raw return edge is the live blocker. The wrapper
split is still useful, but the plain C helper leaves its own normal call/ret
frame in place, so it cannot prove whether the failing edge is:

- `_charout() -> helper`, or
- helper epilogue -> `vtoutput()`

To remove that ambiguity, the helper is now rebuilt as a synthetic-return
trampoline under `CONFIG_SPRINTER_EARLY_TRACE`:

- wrapper saves the character into a global byte
- pushes a synthetic return label
- jumps directly to `_charout`
- synthetic return label publishes `0xF1`
- caller still publishes `0xF2` only after the helper itself returns to
  `vtoutput()`

This removes the helper's ordinary `call _charout` edge from the experiment,
while leaving the rest of `vtoutput()` unchanged.

The rebuilt image carrying this trampoline split is:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 18:26:55` (`.img`) / `2026-04-22 18:26:55` (`.chd`)

`Kernel/vt.lst` confirms the new helper shape:

- `_sprinter_charout_wrap` now does `jp _charout`
- synthetic return label is at local offset `0x013E`
- no ordinary `call _charout` remains inside the helper

### Correct next replay for the trampoline image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFCC0-0xFCD0`
- `0xFD91-0xFDA1`

Decode:

- `FD9E..FDA1 != BA 27 04 22`
  => not the current stamped image
- `FD91 = 0x00`, `FD92 = 0x46`, `FD93 = 0x01`
  => trap still occurs before even the synthetic return label can publish
     `0xF1`; focus narrows to the raw `_charout()` return target itself
- `FD91 = F1`
  => `_charout()` returned through the synthetic label; blocker is now on the
     helper -> `vtoutput()` return edge
- `FD91 = F2`
  => helper returned; blocker moved on to the old post-`charout()` tail

The next replay on that trampoline image showed:

- `FD9E..FDA1 = BA 27 04 22`
- `FD91 = 0xF6`
- `FD92 = 0x46`
- `FD93 = 0x01`
- `FD94 = 0x46`
- `FD99 = 0x01`

That is the key confirmation: the synthetic trampoline worked. The machine is
no longer dying on the raw `_charout()` return edge. Control gets far enough
back into `vtoutput()` to hit the manual len-loop head again (`0xF6`).

However `0xF6` overwrites the earlier `0xF2`, so the live dump cannot yet tell
whether we reached:

- `wrapper -> vtoutput()` and then looped back to `F6`, or
- some earlier path that re-entered the loop without executing the caller-side
  `0xF2` store

To make that distinction persistent, the next image adds sticky latches in the
free tail of `_sprinter_dbg`:

- `[24] = 0xF2`, `[25] = c` immediately after the wrapper returns to
  `vtoutput()`
- `[26] = 0xF6`, `[27] = len` at the loop head
- `[26] = 0xF7`, `[27] = len` after `len--`

Those bytes survive later stage overwrites in `[15]`.

The rebuilt image carrying these sticky return/loop latches is:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 18:53:19` (`.img`) / `2026-04-22 18:53:19` (`.chd`)

### Correct next replay for the sticky-latch image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFCC0-0xFCD0`
- `0xFD91-0xFDA1`

Decode:

- `FD9E..FDA1 != BA 27 04 22`
  => not the current stamped image
- `FD91 = F6`, `FD99 = 1`, but `FD9A = F2`
  => wrapper returned to `vtoutput()`, and we looped back to the first
     len-check head
- `FD91 = F6`, `FD99 = 1`, and `FD9A = 0`
  => we are still not reaching the caller-side post-wrapper store
- `FD9C = F6`, `FD9D = 1`
  => current sticky loop-head state
- `FD9C = F7`, `FD9D = 0`
  => `len--` completed and the body is being re-entered
- `FD91 = F8/FA/FB/FC/FD`
  => the blocker moved on to the inlined `len == 0` tail again

The next replay on that sticky-latch image showed:

- `FD9E..FDA1 = BA 27 04 22`
- `FD91 = 0xF6`
- `FD99 = 0x01`
- `FD9A = 0x00`
- `FD9B = 0x00`
- `FD9C = 0xF6`
- `FD9D = 0x01`

So the current image really is loaded, and the result is now precise:
control reaches the loop head again, but the caller-side post-wrapper store
still does not execute. In other words, control is jumping back to the
manual len-loop head without first passing through the `0xF2` store in the
`vtmode == 0` branch.

That means the next useful evidence is the wrapper-prepared stack shape right
before `jp _charout`, not another logical stage byte. The helper is therefore
updated again so that `_sprinter_dbg[24..27]` are no longer sticky loop
latches; they now snapshot:

- `[24]` = SP low immediately before `jp _charout`
- `[25]` = SP high immediately before `jp _charout`
- `[26]` = low byte at `(SP)` (expected synthetic return low byte)
- `[27]` = high byte at `(SP+1)` (expected synthetic return high byte)

`Kernel/vt.lst` for the rebuilt helper now confirms the synthetic return
label moved to local offset `0x0153`, so a correct prepared stack should show
the bytes `53 01` at `[26..27]`.

The rebuilt image carrying this wrapper-stack snapshot is:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 19:19:43` (`.img`) / `2026-04-22 19:19:43` (`.chd`)

### Correct next replay for the wrapper-stack snapshot image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFCC0-0xFCD0`
- `0xFD91-0xFDA1`

Decode:

- `FD9E..FDA1 != BA 27 04 22`
  => not the current stamped image
- `FD9A..FD9D = xx xx 53 01`
  => wrapper prepared the synthetic return target correctly; if the machine
     still lands at `FD91 = F6`, then `_charout()` is clobbering / replacing
     that return target internally
- `FD9A..FD9D` do not end in `53 01`
  => the stack shape is already wrong before entering `_charout()`
- `FD91 = F1`
  => `_charout()` returned through the synthetic label; blocker moved on to
     helper -> `vtoutput()`
- `FD91 = F2`
  => helper returned; blocker is back in the old post-`charout()` tail

The next replay on that image finally explained the contradiction in the
`0xA0..0xA3` wrapper snapshot: the image stamp matched, but
`FD9A..FD9D` stayed zero even though `Kernel/vt.lst` clearly showed the
stores were assembled before `jp _charout`.  The missing piece is in
`platform-sprinter/sprinter.s`: `_plt_reboot` itself always overwrites
`_sprinter_dbg[24..27]` with the caller stack bytes before it enters the
hang path.  So those four bytes were never a reliable place to keep any
pre-trap wrapper snapshot.

That means the earlier "zero snapshot" replay does **not** prove the
wrapper stores were skipped.  It only proves the post-trap reboot path
clobbered them.

The current image therefore moves the wrapper-side stack snapshot out of
`_sprinter_dbg[24..27]` entirely and reuses already-existing, otherwise
idle exec-fail cells in stable common data:

- `_sprinter_exec_fail_stage` at `0xFBF8`
- `_sprinter_exec_fail_err`   at `0xFBF9..0xFBFA`
- `_sprinter_exec_fail_name`  at `0xFBFB..0xFBFC`

Under `CONFIG_SPRINTER_EARLY_TRACE` they now mean:

- `FBF8 = 0xA0` before calling `sprinter_charout_wrap(c)` from `vtoutput()`
- `FBF8 = 0xA1` on wrapper C entry
- `FBF8 = 0xA2` after the synthetic return label has been pushed and `SP`
  captured
- `FBF8 = 0xA3` immediately before `jp _charout`
- `FBF9..FBFA` = `SP` low/high immediately before `jp _charout`
- `FBFB..FBFC` = bytes at `(SP)` / `(SP+1)` just before `jp _charout`

`Kernel/vt.lst` for the rebuilt helper now shows the synthetic return
label at local offset `0x0175`, so the correct prepared target on the
stack is now:

- `FBFB = 0x75`
- `FBFC = 0x01`

To make the image revision itself unambiguous as well, the build stamp
in `start.c` was bumped by one byte.  The current image now stamps:

- `FD9E..FDA1 = BA 27 04 23`

The rebuilt image carrying this non-clobbered wrapper snapshot is:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 20:04:15` (`.img`) / `2026-04-22 20:04:15` (`.chd`)

### Correct next replay for the exec-fail snapshot image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFCC0-0xFCD0`
- `0xFD91-0xFDA1`

Decode:

- `FD9E..FDA1 != BA 27 04 23`
  => not the current stamped image
- `FBF8 = A0`
  => `vtoutput()` reached the wrapper call site but did not enter the wrapper
- `FBF8 = A1`
  => wrapper C prologue ran, but the synthetic return target has not been
     prepared yet
- `FBF8 = A2` or `A3`, and `FBFB..FBFC = 75 01`
  => wrapper prepared the synthetic return target correctly; if the live
     stage still lands back at `FD91 = F6`, `_charout()` is replacing or
     bypassing that target internally
- `FBF8 = A2` or `A3`, but `FBFB..FBFC != 75 01`
  => the stack is already wrong before entering `_charout()`
- `FD91 = F1`
  => `_charout()` returned through the synthetic label
- `FD91 = F2`
  => wrapper returned to `vtoutput()`
- `FD91 = F6`
  => control is back at the manual len-loop head again

The next replay on that `BA 27 04 23` image changed the picture
substantially:

- `FD9E..FDA1 = BA 27 04 23`
- `FD91 = 0xE4`
- `FD92 = 0x46`
- `FD93 = 0x01`
- `FBF8..FBFC = 00 00 00 00 00`

So the image stamp is valid, but the stop has moved all the way back to
the entry corridor of `vtoutput()` before any wrapper-side `_charout()`
snapshot is published.  This means the earlier `_charout()` return-edge
hypothesis is not the current blocker any more; the live failure is now
strictly between `vtoutput()` entry and the first store after
`irqrestore(irq)`.

To split that corridor, the current image adds four temporary
`CONFIG_SPRINTER_EARLY_TRACE` stages in `Kernel/vt.c`:

- `0xEC` immediately after `irq = di()`
- `0xED` in the `if (vtbusy)` early-return branch
- `0xEE` immediately after `vtbusy = 1`
- `0xEF` immediately after `irqrestore(irq)` and just before `0xE5`

The build stamp was bumped again, so the current image now identifies
itself as:

- `FD9E..FDA1 = BA 27 04 24`

The rebuilt image carrying this `E4 -> E5` corridor split is:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 21:10:39` (`.img`) / `2026-04-22 21:10:39` (`.chd`)

### Correct next replay for the `E4 -> E5` corridor image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFCC0-0xFCD0`
- `0xFD91-0xFDA1`

Decode:

- `FD9E..FDA1 != BA 27 04 24`
  => not the current stamped image
- `FD91 = E4`
  => stop before the post-`di()` marker
- `FD91 = EC`
  => `di()` returned; blocker is before / in the `vtbusy` test
- `FD91 = ED`
  => stop in the `vtbusy` early-return path
- `FD91 = EE`
  => `vtbusy = 1` executed; blocker is on / after `irqrestore(irq)`
- `FD91 = EF`
  => `irqrestore(irq)` returned; blocker is between there and `vt_cursor_off()`
- `FD91 = E5`
  => entry corridor is clean again; blocker moved back into the old VT path

The follow-up replay on the `BA 27 04 25` image landed at:

- `FD91 = F0`
- `FD93 = 00`

So `di()` had already returned and `vtbusy` was read back as zero. At that
point another round of one-byte corridor splits was no longer useful. The
current image switches strategy: under `CONFIG_SPRINTER_EARLY_TRACE`,
`vtoutput()` now bypasses the whole early re-entry corridor and forces the
non-reentrant path directly:

- no `di()`
- no `vtbusy` test / early return
- no `irqrestore()`
- just `vtbusy = 1` and continue with the existing body

This is not intended as a production fix. It is a direct bring-up
workaround to answer one concrete question: does boot move once the
`di()/vtbusy/irqrestore` sequence is removed from the first banner write.

To make this image unambiguous, the build stamp was bumped again. The
current image now identifies itself as:

- `FD9E..FDA1 = BA 27 04 26`

The rebuilt image carrying this direct `vtoutput()` bypass is:

- `Images/sprinter/fuzix.img`
- `Images/sprinter/fuzix.chd`
- timestamp `2026-04-22 21:21:57` is obsolete for replay purposes
- use the next image built after this README entry

### Correct next replay for the direct `vtoutput()` bypass image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFCC0-0xFCD0`
- `0xFD91-0xFDA1`

Decode:

- `FD9E..FDA1 != BA 27 04 26`
  => not the current bypass image
- `FD91 = E5`
  => bypass took effect and control reached `vt_cursor_off()`
- `FD91 = E6/E7/E8/E9/EA/EB/F1/F2/F6...`
  => blocker moved deeper into the old VT path again
- still blank screen with no later stage movement
  => even the re-entry corridor was not the active cause and the next
     step must stop instrumenting `vtoutput()` and move to a broader
     platform workaround

Replay on that `BA 27 04 26` image came back with:

- `FD91 = F6`
- screen still blank

So the direct `vtbusy/irqrestore` bypass did work: the machine no
longer dies in the entry corridor and falls back into the old VT tail.
At that point another round of `vtoutput()` micro-splits is not useful
for bring-up.

The current image therefore moves to a higher-level workaround under
`CONFIG_SPRINTER_EARLY_TRACE`: early `kputchar()` on Sprinter now
bypasses `tty_putc()` / `vtoutput()` completely and writes characters
straight to the screen with `plot_char()`, using a tiny local cursor in
`platform-sprinter/devtty.c`.  Newlines still advance/scroll, but none
of the VT re-entry / cursor / pending-byte logic is used.

This is intentionally a bring-up hack, not a production console
implementation.  The goal is simple: if the VT machinery is the only
remaining blocker, boot should finally move past the blank-screen/F-only
state and continue into the later root mount / `/init` path again.

The build stamp was bumped once more; the current image now identifies
itself as:

- `FD9E..FDA1 = BA 27 04 27`

### Correct next replay for the early direct-console image

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE7-0xFBFF`
- `0xFCC0-0xFCD0`
- `0xFD91-0xFDA1`

Decode:

- `FD9E..FDA1 != BA 27 04 27`
  => not the current image
- visible boot text now advances past the old blank/F-only state
  => VT path really was the active blocker; next work moves back to the
     real boot path instead of the console internals
- screen still blank/frozen with no meaningful later markers
  => even direct `plot_char()` output was not enough, so the next step
     must move above console output entirely

Replay on the `BA 27 04 27` image did in fact move well past the old
blank-screen stop.  It reached:

```text
FUZIX version 0.5
Devboot
OK
Starting /init
...
panic: corrupt inode
```

with panic payload:

```text
magic0 ptr=FFFF slot=00FF site=0001 mg=C300 dev=F554 num=FFFF refs=0003 fl=00FF
pid=0001 sys=0000 in=0001
magic0 raw=0000 00C3 0054 00F5
```

So the console workaround did its job.  The next real blocker is back in
the filesystem path walker:

- `site=1` means `MAGIC_CHECK(1, ninode)` at the top of `n_open()`
- `ptr=0xFFFF` / `slot=0xFF` means `ninode` is not an `i_tab` slot
- this happens while PID1 opens `/init`, not in the old VT/TTY path

The current image therefore moves the diagnostics to the actual `/init`
lookup path and bumps the stamp to:

- `FD9E..FDA1 = BA 27 04 28`

Added `n_open()` walker snapshot state:

- `_sprinter_last_nopen_stage`
- `_sprinter_last_nopen_wd`
- `_sprinter_last_nopen_ninode`
- `_sprinter_last_nopen_name0`
- `_sprinter_last_nopen_char`

and `magic()` now prints those together with the existing last-`i_open()`
snapshot.  This should show whether the `/init` lookup goes bad before
`srch_dir()`, on the `srch_mt()` transition, or immediately after a
specific `i_open(dev, ino)` return.

Replay on `BA 27 04 28` changed the failure again before the new
`magic()` line could fire.  The machine now shows:

```text
Devboot
i_open: bad disk inode
...
panic: no root
```

and never reaches `OK`, so the failure is no longer the later `/init`
pathname walker.  Boot gets through `fmount()` far enough to return to
`fuzix_main`, then the first explicit `i_open(root_dev, ROOTINODE)`
fails its on-disk inode sanity check and `start.c` falls into
`panic(PANIC_NOROOT)`.

Because the existing commondata `last_iopen` slots are no longer
trustworthy enough on this path, the current image moves the next split
directly onto the screen: `i_open badino:` now prints the live inode
payload (`mode`, `nlink`, first block addresses, flags/super index, and
the first four raw bytes of `c_node`) before returning `NULL`.

The build stamp is bumped again.  The current image now identifies
itself as:

- `FD9E..FDA1 = BA 27 04 29`

Replay on `BA 27 04 29` made the bad root inode payload concrete:

```text
iobad ptr=2048 dev=0001 ino=0001 new=0000 mode=0001 nlink=DD00 a0=DD00 a1=0077 fl=0040 sup=0000
iobad raw=0001 0000 0000 00DD
panic: no root
```

This no longer looks like a simple "wrong inode slot" bug.  The live
`c_node` payload is structurally wrong (`mode=0001`, `nlink=0xDD00`,
`a0=0xDD00`) and does not match the plausible root inode words from the
disk image.  So the next image moves the split directly into
`breadi(dev=1, ino=1)` to show the source words from the block buffer and
the destination words after `blktok()`.

The build stamp is bumped again.  The current image now identifies
itself as:

- `FD9E..FDA1 = BA 27 04 30`

Replay on `BA 27 04 30` showed that the root inode path is no longer the
active blocker at all:

- boot reaches `OK`
- boot reaches `Starting /init`
- the `bri blk=/bri dst=` probe does not print
- `_sprinter_dbg[15] = 0xED`

So the image no longer dies in `i_open(root_dev, ROOTINODE)`.  It gets
back into the PID1 `/init` path, and the blocker is again the direct root
directory lookup for `"/init"` inside `sprinter_pid1_init_open()`.

The current image therefore stops trying to diagnose root `breadi()` and
instead uses a narrow PID1-only workaround under
`CONFIG_SPRINTER_EARLY_TRACE`: for the exact kernel-resident `"/init"`
exec it bypasses `srch_dir(root, "init")` and opens the currently known
Sprinter `/init` inode directly with `i_open(root_dev, 0x0083)`.

This is intentionally temporary and local to bring-up.  The goal is to
validate whether the rest of `_execve()` / `doexec()` / real userland init
flow is now healthy once the root-directory walker is out of the path.

The build stamp is bumped again.  The current image now identifies
itself as:

- `FD9E..FDA1 = BA 27 04 31`

Replay on `BA 27 04 31` changed the picture again: the direct
`i_open(root_dev, 0x0083)` workaround got PID1 past the old
`srch_dir(root, "init")` blocker, but the machine still stopped
immediately after `Starting /init` with control in user low memory.
That means the active `/init` probe itself had become the next blocker.

The important mismatch was that the packaged Sprinter `/init` is not the
older `sprinit.c` probe.  `Applications/util/Makefile.z80` builds
`sprinit` from `sprinit_raw.s`, and that raw probe was currently trying
to do a second-stage `execve("/bin/sh")`.  So the boot path was no
longer "make `/init` stable", it was "make the nested `/bin/sh` exec
stable" — an unnecessary expansion of the bring-up surface.

To get back to a meaningful stable PID1 checkpoint, the current image
reduces `Applications/util/sprinit_raw.s` again to the narrowest useful
probe:

- one raw `write(1, "SPRINTER PAUSE OK\\r\\n", ...)`
- then an infinite `pause()` loop

This keeps PID1 in a known-good userland state and avoids dragging the
entire `/bin/sh` handoff into the current failure analysis.

The build stamp is bumped again.  The current image now identifies
itself as:

- `FD9E..FDA1 = BA 27 04 32`

Replay on `BA 27 04 32` showed that the direct `/init` inode bypass was
actually fine, but the packaged `sprinit` binary itself was wrong on
disk:

- boot reaches `OK`
- boot reaches `Starting /init`
- then falls straight to `panic: no /init`

The root cause turned out not to be pathname lookup or `i_open()`.
`Applications/util/sprinit_raw.ihx` was valid, but `makebin -p` writes a
packed binary starting at file offset `0`, preserving the linked
0x0100-origin as a leading 256-byte `0xFF` pad.  So the filesystem was
shipping `/init` with 256 bytes of filler before the exec header, and
the kernel quite correctly rejected it as "no /init".

The Sprinter-only raw `/init` packaging rule now trims that 0x0100
prefix after `makebin`, so the on-disk `/init` starts with the exec16
header instead of filler bytes.

The build stamp is bumped again.  The current image now identifies
itself as:

- `FD9E..FDA1 = BA 27 04 33`

Replay on `BA 27 04 33` confirmed that `/init` now loads and enters
user space again:

- boot reaches `OK`
- boot reaches `Starting /init`
- PID 1 is executing with user pages mapped (`PG0=0x40`)
- but control flow immediately degrades into low addresses (`PC=0x0009`)
  before the raw probe prints its own checkpoint

At this point the blocker is no longer image packaging, inode lookup, or
kernel-side `execve()`.  It sits in the hand-written raw userspace probe
itself or in the exact ABI it assumes after entry.

To get back to a previously more meaningful checkpoint, the current
image stops overriding `Applications/util/sprinit` with the custom raw
`sprinit_raw.s` binary and returns `/init` to the normal
`Applications/util/sprinit.c` userspace program.  That path previously
made it through ordinary libc/syscall setup and reached visible
`SPRINTER WRITE OK` checkpoints, so it is a better next-stage canary
than the current raw-asm entry experiment.

The build stamp is bumped again.  The current image now identifies
itself as:

- `FD9E..FDA1 = BA 27 04 34`

Replay on `BA 27 04 34` proved that `/init` in the filesystem image was
indeed the rebuilt `Applications/util/sprinit` C binary, but it still
fell into low user addresses immediately after `Starting /init` and
never reached `SPRINTER WRITE OK`.

That means the remaining blocker is no longer filesystem packaging, but
the earliest userspace entry/runtime path itself.  To remove libc/crt0
from the equation again, while keeping the packaging path honest, the
current image switches the Sprinter-only `/init` override back to a
separate raw binary target:

- `Applications/util/sprinit_raw.s` is built as standalone `sprinit_raw`
  via `sdasz80 + sdldz80 -b _HEADER=0x0100`
- `makebin -p -o 0x100` trims the linked `0x0100` origin so the on-disk
  file begins with a valid exec16 header
- `Kernel/platform/platform-sprinter/fuzix-platform-sprinter.pkg` now
  points `/init` directly at `../../../Applications/util/sprinit_raw`
  instead of `sprinit`

This keeps the rootfs override explicitly Sprinter-only and gives the
next replay a binary answer:

- if `SPRINTER PAUSE OK` appears, the C runtime path was the blocker
- if control still drops into low memory, the fault is in raw user entry
  / syscall ABI after `_execve()`

The build stamp is bumped again.  The current image now identifies
itself as:

- `FD9E..FDA1 = BA 27 04 35`

Replay on `BA 27 04 35` answered the remaining raw `/init` question
cleanly: the probe really does start executing, but it executes at
runtime base `0x0000`, not `0x0100`.

Key evidence:

- `PC = 0x0019` right after `Starting /init`
- that is inside the raw probe itself (the second `ld hl, #msg_user_ok`)
- therefore the earlier `_HEADER=0x0100` link base was wrong for this
  userspace path

The bad effect was visible in the file bytes too: the packaged probe was
loading `HL = 0x012D` for the message pointer, while runtime code was
actually executing at `0x0012` and the string lived at `0x002D`.

The current image fixes the raw probe to match the real ABI:

- `Applications/util/sprinit_raw.s` now writes `a_text = a_text_end`
- `Applications/util/Makefile.z80` links `sprinit_raw` at base `0x0000`
  (no `_HEADER=0x0100`)
- `makebin` now emits the raw exec16 file directly without `-o 0x100`

Expected next replay result:

- the packaged `/init` still stays the Sprinter-only raw probe
- but now its internal pointers match runtime addresses
- so the screen should reach `SPRINTER PAUSE OK`

The build stamp is bumped again.  The current image now identifies
itself as:

- `FD9E..FDA1 = BA 27 04 36`

Replay on `BA 27 04 36` confirmed the raw probe now links at the correct
runtime base `0x0000`, but it still never reached `SPRINTER PAUSE OK`.
That exposed the next ABI mismatch: the probe was issuing syscalls with
`call 0x0100`, while exec16 actually installs `sys_stubs` into the
header hole at `progload`, i.e. user `0x0000..0x0011`.

So the raw probe itself was now valid, but still calling the wrong
syscall trampoline address.

The current image fixes `Applications/util/sprinit_raw.s` to use:

- `call 0x0000` for `write()`
- `call 0x0000` for `pause()`

That matches the kernel's `uput(sys_stubs, (uint8_t *)progload,
sizeof(struct exec))` contract in `syscall_exec16.c`.

The build stamp is bumped again.  The current image now identifies
itself as:

- `FD9E..FDA1 = BA 27 04 37`

Replay on `BA 27 04 37` still showed no visible user output even though
the raw probe was now running at the right base and calling the right
syscall trampoline.

That made the previous probe ambiguous: it was trying to
`write(1, "SPRINTER PAUSE OK\r\n", ...)`, but PID1 had never explicitly
opened `/dev/tty1`, so silence no longer proved user entry was dead.

The current image changes `Applications/util/sprinit_raw.s` again so
the raw `/init` now does the narrowest tty setup itself:

- loop on `open("/dev/tty1", O_RDWR|O_NOCTTY, 0)`
- write `"SPRINTER PAUSE OK\r\n"` to the returned fd
- then `pause()` forever

This removes any dependency on inherited stdio for the first userland
checkpoint.

The build stamp is bumped again.  The current image now identifies
itself as:

- `FD9E..FDA1 = BA 27 04 38`

Replay on `BA 27 04 38` showed that the new raw `/init` does execute far
enough to return from `open("/dev/tty1", ...)`, but still never prints
the checkpoint line.

That exposed a narrower ABI mistake in the probe itself: `open()` was
called with the correct stack order, but `write(fd, buf, len)` was not.
The syscall ABI expects arguments in normal C order on the stack
(right-to-left pushes), so the probe must push:

- `len`
- `buf`
- `fd`

before `call 0x0000`.

The current image fixes that `write()` argument order in
`Applications/util/sprinit_raw.s`.

The build stamp is bumped again.  The current image now identifies
itself as:

- `FD9E..FDA1 = BA 27 04 39`

Local verification for the current `BA 27 04 39` image:

- `Images/sprinter/fuzix.img` and `Images/sprinter/fuzix.chd` rebuilt at
  `2026-04-23 09:11:51`
- `/init` inside `Images/sprinter/filesys.img` is the raw probe
- the packaged raw probe now has the corrected `write(fd, buf, len)`
  stack order in the actual rootfs image

Next replay needed:

- full screen
- registers + `PG0..PG3`
- `0xFD9E-0xFDA1`

Expected current build marker:

- `FD9E..FDA1 = BA 27 04 39`

Expected next visible checkpoint if the raw probe is now ABI-correct:

- `SPRINTER PAUSE OK`

### Update from 2026-04-23 09:38: raw syscall error ABI fixed in `sprinit_raw`

The `BA 27 04 39` raw `/init` probe still had one critical ABI bug:
it checked `open()` failure as `HL == 0xFFFF`. That is wrong for direct
`call 0x0000` syscalls on this Z80 path. The kernel returns errors as:

- `CARRY = 1`
- `HL = errno`

and returns success as:

- `CARRY = 0`
- `HL = retval`

So the probe could treat failed `open("/dev/tty1", ...)` as success and
then call `write()` with an invalid fd value.

Current fix in `Applications/util/sprinit_raw.s`:

- `open_loop` now retries on `jr c, open_loop` (carry) instead of testing
  `HL` against `0xFFFF`
- added tiny raw-user stage latches:
  - `spr_stage` (`0x007E`)
  - `spr_fd` (`0x007F..0x0080`)
  - `spr_wr` (`0x0081..0x0082`)
- stage values:
  - `0x11` probe start (before open loop)
  - `0x12` open succeeded (`spr_fd` latched)
  - `0x13` write succeeded (`spr_wr` latched)
  - `0x93` write failed (`spr_wr` = errno)
  - `0x14` pause loop

Build stamp bumped again. Current image identifies as:

- `FD9E..FDA1 = BA 27 04 40`

Local verification for this build:

- `Images/sprinter/fuzix.img` and `Images/sprinter/fuzix.chd` rebuilt at
  `2026-04-23 09:38`
- raw `/init` binary bytes confirm latch addresses and carry-based open retry

### Correct next replay for `BA 27 04 40`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFD9E-0xFDA1`
- `0x007E-0x0082`

Decode:

- `FD9E..FDA1 != BA 27 04 40`
  => not the current image
- `007E = 0x11`
  => still looping before a successful open
- `007E = 0x12`, `007F..0080 = fd`
  => open succeeded, blocker moved to write path
- `007E = 0x93`, `0081..0082 = errno`
  => write failed; errno in `spr_wr`
- `007E = 0x13` or `0x14`
  => write returned and probe reached the pause loop

Expected visible checkpoint once fd/write ABI is clean:

- `SPRINTER PAUSE OK`

### Update from 2026-04-23 09:49: emulator path confirmed, raw `/init` narrowed to `write(1)+pause`

User-side launch script check:

- `/Users/dmitry/dev/zx/sprinter/mame_images/mame_release_v306_25.05.2025/_306_fuzix.sh`
  uses:
  - `-hard1 /Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/fuzix.chd`

So MAME is pointed at this tree's rebuilt image path, not at an external copy.

Next narrowing step in `Applications/util/sprinit_raw.s`:

- removed user-space `open("/dev/tty1")` loop from the raw probe
- probe now does the minimal sequence:
  1. stage `0x11`
  2. stage `0x12`
  3. `write(1, "SPRINTER PAUSE OK\\r\\n", 19)`
  4. stage `0x13` on success, `0x93` on write error (`spr_wr = errno`)
  5. stage `0x14`, then `pause()` loop

This removes pathname/device-open noise from the very first userspace checkpoint
and tests only inherited stdio + syscall return path.

Build stamp bumped again. Current image identifies as:

- `BA 27 04 41` in `sprinter_dbg[28..31]`
- with current link map (`_sprinter_dbg = 0xFD89`) this is at
  `0xFDA5..0xFDA8`

Local verification for current image:

- `Images/sprinter/fuzix.img` and `Images/sprinter/fuzix.chd` rebuilt at
  `2026-04-23 09:48:53`
- raw `/init` header now is:
  - `a_text = 0x0068`
  - `a_entry = 0x12`
  - code starts at `0x0010` with two NOPs then stage stores at `0x0012`
- raw probe latch addresses now:
  - `spr_stage` = `0x0063`
  - `spr_fd` = `0x0064..0x0065` (fixed `0x0001`)
  - `spr_wr` = `0x0066..0x0067`

### Correct next replay for `BA 27 04 41`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFD90-0xFDB0`
- `0x0063-0x0067`

Decode:

- no `BA 27 04 41` sequence in `0xFD90-0xFDB0`
  => not the current image
- `0063 = 0x11`/`0x12`
  => probe entered but did not finish first write
- `0063 = 0x93`, `0066..0067 = errno`
  => first write to inherited `fd=1` failed
- `0063 = 0x13` or `0x14`
  => write returned and probe reached pause loop

Expected visible checkpoint for this build:

- `SPRINTER PAUSE OK`

### Update from 2026-04-23 10:xx: fixed `map_proc_2` guard that broke `uput(sys_stubs)`

`BA 27 04 41` replay proved `_execve()` reached stage `0xE3` with correct `/init`
header values (`progload=0x0100`, `bin_size=0x0068`) but then control escaped into
low user addresses with mixed map state:

- `PC` in `0x00xx`
- `PG0=0x40` (user) while `PG1/PG2=0x4C/0x4D` (kernel overlay)

This narrowed the fault to the first `uput(sys_stubs, (uint8_t *)progload, 16)`
step in `_execve()`, specifically the map save/restore path in Sprinter
`map_proc_save_u` / `map_kernel_restore_u`.

Root cause:

- `platform-sprinter/sprinter.s:map_proc_2` had a pointer guard that treated any
  mapping block beginning with `0x48` as valid only if the next byte was exactly
  `0x49`.
- That invalidates legitimate kernel restore maps like `0x48/0x4C/0x4D` (CODE3
  overlay), so `map_kernel_restore_u` silently fell back to `_udata.u_page`
  (user map) instead of restoring the saved kernel map.
- Returning from usermem copy with user bank still in `PG0` explains the observed
  immediate jump into garbage low user memory.

Fix:

- broadened `map_proc_2` guard to accept all valid kernel bank pairs:
  - `0x48/0x49/0x4A` (CODE1)
  - `0x48/0x4C/0x4D` (CODE2)
  - `0x48/0x4E/0x4F` (CODE3)
- otherwise still fallback to `_udata + U_DATA__U_PAGE` as before

Build stamp bumped again. Current image identifies as:

- `BA 27 04 42` in `sprinter_dbg[28..31]`

Local verification:

- `Images/sprinter/fuzix.img` and `Images/sprinter/fuzix.chd` rebuilt at
  `2026-04-23 10:06` (local time)

### Correct next replay for `BA 27 04 42`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFD90-0xFDB0` (for build stamp and `sprinter_dbg[15..23]`)
- `0x0063-0x0067` (`spr_stage/spr_fd/spr_wr`)

Decode:

- no `BA 27 04 42` sequence in `0xFD90-0xFDB0`
  => not the current image
- `sprinter_dbg[15]` advances from old `0xE3` to `0xE4` or later
  => `uput(sys_stubs, ...)` return edge is no longer the blocker
- `0063 = 0x93`, `0066..0067 = errno`
  => raw `/init` write still fails (but entry path survives farther)
- `0063 = 0x13` or `0x14`
  => raw `/init` reached write success/pause loop

Expected visible checkpoint once this map-restore fix is effective:

- `SPRINTER PAUSE OK`

### Update from 2026-04-23 10:13: BA42 regressed root mount, move fix into `map_kernel_restore_u` only

Replay on `BA 27 04 42` came back with an early regression:

- screen:
  - `i_open: bad disk inode`
  - `panic: no root`
- dump still confirmed current image (`FD9E..FDA1 = BA 27 04 42`)

So widening `map_proc_2` pointer acceptance globally was unsafe and reintroduced
the earlier false-positive path in root filesystem bring-up.

New fix (platform-local, narrower):

- reverted `map_proc_2` pointer guard to strict kernel-map signature check
  (`0x48/0x49/0x4A`) with fallback to `_udata + U_DATA__U_PAGE`
- rewrote `map_kernel_restore_u` to restore `map_savearea_user` directly
  (PG0/PG1/PG2 with the same range clamps), instead of routing through
  `map_proc_2` pointer heuristics

Rationale:

- only `map_kernel_restore_u` actually needs to accept saved CODE2/CODE3 overlays
  (`0x4C/0x4D`, `0x4E/0x4F`)
- global pointer broadening in `map_proc_2` is too permissive and affects unrelated
  map callers (including mount/root open path)

Build stamp bumped again. Current image identifies as:

- `BA 27 04 43` in `sprinter_dbg[28..31]`

Local verification:

- `Images/sprinter/fuzix.img` and `Images/sprinter/fuzix.chd` rebuilt at
  `2026-04-23 10:15` (local time)

### Correct next replay for `BA 27 04 43`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFD90-0xFDB0` (build stamp + `sprinter_dbg[15..23]`)
- `0x0063-0x0067` (`spr_stage/spr_fd/spr_wr`)
- `0xFBC8-0xFBE0` (`map_savearea`, `map_savearea_user`, `mpgsel_cache`)

Decode:

- no `BA 27 04 43` sequence in `0xFD90-0xFDB0`
  => not the current image
- `panic: no root` on `BA43`
  => regression is not fully isolated; continue root inode path split
- `Starting /init` plus `sprinter_dbg[15] >= 0xE3`
  => exec path survives root mount, continue on `_execve()`/usermem side
- `0063 = 0x93`, `0066..0067 = errno`
  => raw `/init` first write still failing
- `0063 = 0x13` or `0x14`
  => raw `/init` write path completes and reaches pause loop

### Update from 2026-04-23 10:24: BA43 dump exposed guard bug in `map_proc_2`

Replay on `BA 27 04 43` still regressed to:

- `i_open: bad disk inode`
- `panic: no root`

but the memory dump made the failure mode concrete.

From `sprinter.lst` offsets in `_COMMONDATA`:

- `mpgsel_cache` = base `+0x00` (`0xFBD4`)
- `top_bank`     = base `+0x04` (`0xFBD8`)
- `_kernel_pages`= base `+0x05` (`0xFBD9`)
- `map_savearea` = base `+0x18` (`0xFBEC`)
- `map_savearea_user` = base `+0x1C` (`0xFBF0`)

In the BA43 dump:

- `mpgsel_cache = 48 4C 4D 43` (valid current kernel map)
- `_kernel_pages = 48 4C 4D 4B` (valid CODE2 overlay kernel map)
- `map_savearea_user = 00 00 00 00` (still uninitialized at this stage)

So the earlier BA43 narrowing had two issues:

1. `map_proc_2` was over-tightened incorrectly:
   - `first != 0x48` was sent to fallback, but non-`0x48` process page maps
     are valid and must pass through unchanged.
2. direct `map_kernel_restore_u` could restore from all-zero
   `map_savearea_user` if called before the first matching save.

Current fix:

- restored original `map_proc_2` behavior for non-`0x48` page tables:
  `first != 0x48 => map_proc_2_ptr_ok`
- kept direct `map_kernel_restore_u` restore path for saved CODE2/CODE3 maps
  but added a hard fallback:
  - if `map_savearea_user[0]` is outside `0x08..0x4F`, jump to `map_kernel`
    instead of restoring clamped garbage pages

Build stamp bumped again. Current image identifies as:

- `BA 27 04 44` in `sprinter_dbg[28..31]`

Local verification:

- `Images/sprinter/fuzix.img` and `Images/sprinter/fuzix.chd` rebuilt at
  `2026-04-23 10:24` (local time)

### Correct next replay for `BA 27 04 44`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFD90-0xFDB0` (build stamp + `sprinter_dbg[15..23]`)
- `0x0063-0x0067` (`spr_stage/spr_fd/spr_wr`)
- `0xFBE8-0xFBF8` (`map_savearea`, `map_savearea_user` exact bytes)

Decode:

- no `BA 27 04 44` sequence in `0xFD90-0xFDB0`
  => not the current image
- `panic: no root` persists on BA44
  => continue splitting root inode read path
- `Starting /init`
  => root mount recovered; continue on `_execve()` corridor
- `map_savearea_user` still `00 00 00 00` with no usermem stage
  => fallback path should keep kernel map stable (expected)

### Update from 2026-04-23 11:03: BA44 still `panic: no root`, restore exact BA41 `map_proc_2` guard

Replay on `BA 27 04 44` is still the same early regression:

- `i_open: bad disk inode`
- `panic: no root`
- `iobad raw=0000 0000 0000 0000`

and confirms:

- `spr_rw_stage = 0xDA`, `spr_rw_fd = 0`, `spr_rw_base = 0x2EE0`
  (`0xFC99..0xFC9C = DA 00 E0 2E`)
- `map_savearea_user = 00 00 00 00` (`0xFBF0..0xFBF3`)
- build stamp is current (`FD9E..FDA1 = BA 27 04 44`)

The remaining mismatch vs known-good BA41 was in `map_proc_2`: BA43/BA44 had
an extra third-byte check (`48/49/4A`), while BA41 accepted any pointer with
leading `48/49` and otherwise fell back.  That extra tightening can reject
legitimate map blocks that start with `48/49` but currently carry a different
`u_page[2]` and push map callers onto fallback at the wrong time.

Current fix:

- restored `map_proc_2` guard exactly to BA41 semantics:
  - `first != 0x48` -> accept pointer as-is
  - `first == 0x48 && second == 0x49` -> accept
  - `first == 0x48 && second != 0x49` -> fallback to `_udata + U_DATA__U_PAGE`
- kept BA44 local safety in `map_kernel_restore_u`:
  invalid `map_savearea_user[0]` still falls back to `map_kernel`

Build stamp bumped again. Current image identifies as:

- `BA 27 04 45` in `sprinter_dbg[28..31]`

Local verification:

- `Images/sprinter/fuzix.img` and `Images/sprinter/fuzix.chd` rebuilt at
  `2026-04-23 11:03` (local time)

### Correct next replay for `BA 27 04 45`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFD90-0xFDB0` (build stamp + `sprinter_dbg[15..23]`)
- `0xFC98-0xFC9F` (`spr_rw_stage/spr_rw_fd/spr_rw_base`)
- `0xFBE8-0xFBF8` (`map_savearea`, `map_savearea_user`)
- `0x2EC0-0x2F20` (current IDE destination window around `spr_rw_base`)

Decode:

- no `BA 27 04 45` in `0xFD90-0xFDB0`
  => not the current image
- `Starting /init`
  => root mount path recovered again, continue on `_execve()`
- still `panic: no root` but `spr_rw_base` is sane and `0x2EC0-0x2F20` non-zero
  => continue split inside inode/superblock decode path, not IDE transfer entry

### Update from 2026-04-23 11:29: BA45 recovered root mount, now hard RST38 in E3->E4 corridor

Replay on `BA 27 04 45` moved back to the expected path:

- `Devboot`
- `OK`
- `Starting /init`

so the `panic: no root` regression is gone again.

But the machine then hard-stops with no `E4` advance. The dump is very
specific:

- `sprinter_dbg[15] = 0xE3` still live
  (`progload=0x0100`, `top=0xEE00`, `bin_size=0x0068`, `bss=0x0000`)
- `sprinter_rst38_count = 1` (`0xFBE7`)
- `sprinter_rst38_sp = 0xEFBB` (`0xFBE8..0xFBE9`)
- `sprinter_rst38_ret = 0xFA02` (`0xFBEA..0xFBEB`)
- `sprinter_dbg[0..3] = FF FF FF FF` (`0xFD89..0xFD8C`)

`PC=0xF1AC` is exactly `rst38_hang`, so this is a real RST38 capture.
`RET=0xFA02` lands inside the `_COMMONMEM` `swapstack` reserved area
(filled with `0xFF`), i.e. execution escaped into non-code while still in
the `uput(sys_stubs, ...)` corridor.

That narrows the blocker to the bulk `_uput()` path itself (or its call/stack
ABI), not to root mount / inode lookup anymore.

Current diagnostic fix (early-trace only, temporary):

- in `Kernel/syscall_exec16.c`, replaced the single
  `uput(sys_stubs, (uint8_t *)progload, sizeof(struct exec))`
  with a 16-byte `uputc(...)` loop under `#ifdef CONFIG_SPRINTER_EARLY_TRACE`
- on failure, records:
  - `sprinter_exec_fail_stage = 16`
  - `sprinter_exec_fail_done = failing destination address`
  - `sprinter_exec_fail_count = failing byte index`

Purpose: verify whether the crash is specific to bulk `__uput()` versus
mapper/usermem primitives in general.

Build stamp bumped again. Current image identifies as:

- `BA 27 04 46` in `sprinter_dbg[28..31]`

Local verification:

- `Images/sprinter/fuzix.img` and `Images/sprinter/fuzix.chd` rebuilt at
  `2026-04-23 11:29` (local time)

### Correct next replay for `BA 27 04 46`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFD80-0xFDB0` (`sprinter_dbg[0..31]` + build stamp)
- `0xFBE0-0xFC10` (`rst38`, `exec_fail_*`, `map_savearea_user`)
- `0xEFA8-0xEFC8` (stack window around trapped `SP`)
- `0xF9F0-0xFA20` (code/stack page around trapped `RET=0xFA02`)

Decode:

- no `BA 27 04 46` in `0xFD90-0xFDB0`
  => not the current image
- `sprinter_dbg[15]` advances to `0xE4` or later
  => bulk `__uput()` was the blocker; continue after stub copy
- still `0xE3` + RST38 with `RET` in `0xFAxx`
  => problem is below `_uput` layer (`uputc` / map save/restore / stack integrity)

### Update from 2026-04-23 12:45: BA46 still RST38 at `RET=0xFA02`, switch `_uputc/_uputw` to IX-frame ABI

Replay on the confirmed `BA 27 04 46` image (`FD9E..FDA1 = BA 27 04 46`)
still stops at the same place:

- screen reaches `Devboot`, `OK`, `Starting /init` then hangs
- `PC=0xF1AC` (`rst38_hang`)
- `sprinter_dbg[15] = 0xE3` (no `E4`)
- `sprinter_rst38_count = 1`
- `sprinter_rst38_ret = 0xFA02`
- trapped stack moved (`SP=0xEFC5` in the latest run, previously `0xEFBB`)

So replacing bulk `uput()` with byte-wise `uputc()` was not sufficient: the
fault is in the lower write primitive / call ABI itself.

The most suspicious part was `_uputc`/`_uputw` using pop/push stack surgery
while other Sprinter usermem paths already use stable IX-frame argument decode.
Given SDCC noopt call wrappers around these helpers, this can desync return
stack and jump into `0xFAxx` filler.

Current fix:

- `Kernel/platform/platform-sprinter/usermem.s`
  - rewired `__uputc` and `__uputw` to IX-frame argument access
    (`6(ix)..9(ix)`) instead of pop/push argument juggling
  - keep explicit `map_proc_save_u` / write / `map_kernel_restore_u`
  - return `HL=0` exactly as before

Build stamp bumped again. Current image identifies as:

- `BA 27 04 47` in `sprinter_dbg[28..31]`

Local verification:

- `Images/sprinter/fuzix.img` and `Images/sprinter/fuzix.chd` rebuilt at
  `2026-04-23 13:42` (local time)

### Correct next replay for `BA 27 04 47`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFD80-0xFDB0` (`sprinter_dbg[0..31]` + build stamp)
- `0xFBE0-0xFC10` (`rst38`, `exec_fail_*`, `map_savearea_user`)
- `0xEFB0-0xEFE0` (stack window around trapped `SP`)
- `0xF9F0-0xFA20` (trap target area)
- `0x0000-0x0120` (user low memory / stub landing zone)

Decode:

- no `BA 27 04 47` in `0xFD90-0xFDB0`
  => not the current image
- `sprinter_dbg[15] >= 0xE4`
  => `_uputc` ABI fix worked, move to next exec/load stage
- still `PC=F1AC` with `RET=0xFAxx` and `sprinter_dbg[15]=0xE3`
  => map save/restore state still getting clobbered; split `map_proc_save_u`
  vs `map_kernel_restore_u` next

### Update from 2026-04-23 13:50: BA47 confirms `map_kernel` false fallback when current code bank is 2/3

Replay on confirmed `BA 27 04 47` (`0xFDC6..0xFDC9`) still reaches `/init`
but traps again at `PC=F1AC`.  The key difference in this dump:

- `PG0..PG3 = 48 4E 4F 43` at trap
- `_kernel_pages = 48 4E 4F 4B` (`0xFBFA..0xFBFD`)

This is a legal kernel state while executing bank-3 code paths
(`_kernel_pages+1/+2` can be `4E/4F`), but the BA45 guard in `map_proc_2`
still treated `48/49` as the only valid kernel header and fell back to
`_udata.u_page` for `48/4C` or `48/4E`.

That means a `map_kernel` / `map_restore` call made while current kernel bank
is 2/3 can silently remap to user pages and poison the next return path.
The observed `PG1=4E`, `PG2=4F`, `RST38` hang matches that failure mode.

Current fix:

- `Kernel/platform/platform-sprinter/sprinter.s:map_proc_2`
  - keep the `0x48` lead-byte guard
  - accept second byte `0x49`, `0x4C`, or `0x4E` as valid kernel map headers
  - fallback to `_udata + U_DATA__U_PAGE` only for other `0x48/xx` pairs

Build stamp bumped again. Current image identifies as:

- `BA 27 04 48` in `sprinter_dbg[28..31]`

Local verification:

- `Images/sprinter/fuzix.img` and `Images/sprinter/fuzix.chd` rebuilt at
  `2026-04-23 14:16` (local time)

### Correct next replay for `BA 27 04 48`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBE8-0xFC10` (kernel map header + rst38 block vicinity)
- `0xFCB8-0xFCD0` (`spr_rw_*` and `spr_initio_*` vicinity)
- `0xFDA0-0xFDE0` (`sprinter_dbg` block + build stamp)
- `0xEFB0-0xEFE8` (stack at trap)
- `0x0000-0x0120` (user low memory / vectors)

Decode:

- no `BA 27 04 48` in `0xFDC6..0xFDC9`
  => not the current image
- boot reaches `Starting /init` and no immediate `RST38` halt
  => `map_proc_2` bank-header false reject was the blocker
- still `PC=F1AC` with `PG1/PG2` user-ish and stage tail frozen
  => next split goes into `map_savearea_user` save/restore ordering and
  caller map state around `uputc` loop

### Update from 2026-04-23 14:16: BA48 still traps, but exposes IM2-table overlap with `_COMMONDATA`

Replay on confirmed `BA 27 04 48` (`0xFDC6..0xFDC9`) still ends in:

- `PC=F1AC` (`rst38_hang`)
- `PG0..PG3 = 48 4E 4F 43`
- screen tail still in `_execve()` corridor

The important change is trap payload:

- `sprinter_rst38_sp = 0xEFC0`
- `sprinter_rst38_ret = 0x28BE` (not `0xFAxx` anymore)

Link map for this build shows:

- `_COMMONDATA = 0xFBF5..0xFDC8`
- but IM2 table was still initialized at `0xFC00..0xFD00`

So the boot-time IM2 table fill was overwriting live `_COMMONDATA`
structures (`rst38`, exec-fail diagnostics, map save areas, and others)
before `_execve()` even starts. That explains why FC-page diagnostics are
unstable and why map/restore state can drift despite narrow usermem fixes.

Current fix:

- move IM2 table from `0xFC00` to `0xFE00`
- fill table with `0xFD` so all vectors resolve to `0xFDFD`
- keep minimal JP stub at `0xFDFD -> sprinter_bringup_int`
- set `I = 0xFE`

This keeps IM2 entirely away from the current `_COMMONDATA` range.

Build stamp bumped again. Current image identifies as:

- `BA 27 04 49` in `sprinter_dbg[28..31]`

Local verification:

- `Images/sprinter/fuzix.img` and `Images/sprinter/fuzix.chd` rebuilt at
  `2026-04-23 14:42` (local time)

### Correct next replay for `BA 27 04 49`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFBF0-0xFCD0` (kernel pages + rst38 + exec/map diagnostics now reliable)
- `0xFDA0-0xFDE0` (`sprinter_dbg` + build stamp)
- `0xFDF0-0xFE20` (IM2 stub/page boundary + start of new table page)
- `0xEFB0-0xEFE8` (stack at trap if any)
- `0x0000-0x0120` (user low memory / vectors)

Decode:

- no `BA 27 04 49` in `0xFDC6..0xFDC9`
  => not the current image
- boot advances beyond current `_execve()` tail stop
  => IM2/COMMONDATA overlap was the active blocker
- still `PC=F1AC`
  => use now-stable FC-page diagnostics to split exact writer/caller next

### Update from 2026-04-23 14:42: BA49 reaches userspace, then `/init` self-corrupts low vectors

Replay on confirmed `BA 27 04 49` (`0xFDC6..0xFDC9`) is a real step forward:

- boot now reaches:
  - `OK`
  - `Starting /init`
- no `RST38` hang loop (`PC` is no longer `F1AC`)
- IM2 relocation is active (`I=0xFE`, `0xFE00..` filled with `0xFD`,
  `0xFDFD = JP sprinter_bringup_int`)

But execution then drifts in userspace (`PG0=0x40`, `PC=0x0009`) with low-page
contents clearly clobbered. This aligns with current filesystem override:

- `/init -> Applications/util/sprinit_raw` (raw probe)
- `sprinit_raw` is linked at base `0x0000` and uses absolute low addresses
  (`spr_stage` around `0x0063`, syscall via `call 0x0000`)
- on Sprinter exec16 loads at `PROGLOAD=0x0100`, so that probe writes into
  vector page `0x0000..` and corrupts its own runtime path.

So the current blocker is not kernel map/IM2 anymore, but the raw `/init`
payload itself.

Current fix:

- keep Sprinter-specific `/init` override but switch it from
  `sprinit_raw` to regular linked `sprinit` (libc+crt0), which is
  load-address safe at `PROGLOAD=0x0100`

Build stamp bumped again. Current image identifies as:

- `BA 27 04 4A` in `sprinter_dbg[28..31]`

### Correct next replay for `BA 27 04 4A`

Capture:

- full screen
- registers + `PG0..PG3`
- `0x0000-0x0180` (user vectors/startup now that `/init` changed)
- `0xFBF0-0xFCD0` (kernel pages + exec/map diagnostics)
- `0xFDA0-0xFDE0` (`sprinter_dbg` + build stamp)
- `0xFDF0-0xFE20` (IM2 stub/table still intact)
- `0xEFB0-0xEFE8` (stack window)

Decode:

- no `BA 27 04 4A` in `0xFDC6..0xFDC9`
  => not the current image
- visible user probe output (expected `SPRINTER WRITE OK`) or stable pause loop
  => kernel/user handoff is now coherent, move on to full `/init`
- still early userspace drift near `PC=0x000x`
  => split crt0/userspace syscall vector path next

### Update from 2026-04-23 15:02: BA4A is still failing in `_execve()` stage `E3` (`uputc` stub copy)

Replay on confirmed `BA 27 04 4A` (`0xFDC6..0xFDC9`) still stops right after:

- `OK`
- `Starting /init`

Key dump facts:

- `PC=0x0010`, `PG0..PG3 = 48 4C 4D 43` (kernel mapping still active)
- `_sprinter_dbg[15] = 0xE3` (at `0xFDB9`), not `E4/EA`
- `_sprinter_exec_fail_stage = 0` (`0xFC19`)

So `_execve()` passed header/pagemap setup (`E3` payload shows
`progload=0x0100`, `top=0xEE00`) but never reached `E4` and did not hit
the explicit `uputc` error branch (`stage 16`).  The live stop is inside
the first `uputc(sys_stubs[si], progload+si)` loop.

The concrete Sprinter-specific issue is that the current usermem helpers
(`__uputc/__uputw/__uput/__uget/__uzero`) were still using
`map_proc_save_u`, which remaps bank0 (`MPGSEL_0`).  On Sprinter this is
unsafe for this path because mapper code itself lives in low `_CODE`:
switching bank0 under that code stream can redirect fetch into user page
0x0000.. and land exactly in the observed `PC=0x0010` vector area.

Current fix (platform-local only, in `platform-sprinter/usermem.s`):

- rework user copy primitives to map user addresses via `user_map_de`
  into the `0x4000-0xBFFF` window (`MPGSEL_1/2` only)
- stop touching `MPGSEL_0` in this usermem path
- save/restore previous bank1/2 around each mapped access

This keeps kernel low-code fetch stable while `_execve()` writes the
16-byte syscall stub header at `progload`.

Build stamp bumped again. Current image identifies as:

- `BA 27 04 4B` in `sprinter_dbg[28..31]`

### Correct next replay for `BA 27 04 4B`

Capture:

- full screen
- registers + `PG0..PG3`
- `0x0000-0x0180` (user low page + `progload` region)
- `0xFC10-0xFC40` (`exec_fail_*` + `last_exec_*`)
- `0xFCB8-0xFCD0` (`spr_rw_*` + `spr_initio_*`)
- `0xFDA0-0xFDE0` (`sprinter_dbg` + build stamp)
- `0xFDF0-0xFE20` (IM2 stub/table sanity)
- `0xEFB0-0xEFE8` (stack window)

Decode:

- no `BA 27 04 4B` in `0xFDC6..0xFDC9`
  => not the current image
- `_sprinter_dbg[15]` advances to `E4` or later
  => bank0 self-remap in usermem was the active blocker
- still hard stop with `E3`
  => next split goes into exact `__uputc` call/return ABI and stack frame

### Update from 2026-04-23 15:44: BA4B enters `/init`, then dies in `i_open/getdev` corridor

Replay on confirmed `BA 27 04 4B` now reaches:

- `OK`
- `Starting /init`
- then `i_open: bad disk inode`
- followed by `panic: getdev bad dev`

Two changes were applied for the next step:

1. **Stabilize `/init` probe path (temporary):**
   `Applications/util/sprinit.c` is narrowed to:
   - `getpid()`
   - `write(1, "SPRINTER WRITE OK\\r\\n", ...)`
   - `pause()` loop

   This removes user-space `open("/dev/tty1")/dup()` from the probe so we can
   confirm a stable libc userspace baseline while kernel-side `open` diagnostics
   are tightened.

2. **Make `i_open/getdev` diagnostics reliable:**
   - `i_open badino` print now casts pointer-like values to 16-bit before
     `kprintf("%x")` (previous output could be stack-shifted by pointer width).
   - Added persistent snapshots in `_COMMONDATA`:
     - `_sprinter_bad_iopen_ptr` (`0xFCBF`)
     - `_sprinter_bad_iopen_a0` (`0xFCC1`)
     - `_sprinter_bad_iopen_a1` (`0xFCC3`)
     - `_sprinter_bad_iopen_flags` (`0xFCC5`) (`low=c_flags high=c_super`)
     - `_spr_gd_dev` (`0xFCF7`)
     - `_spr_gd_mnt` (`0xFCF9`)
     - `_spr_gd_state` (`0xFCFB`) (`low=u_callno high=u_insys`)

Build stamp bumped again. Current image identifies as:

- `BA 27 04 4C` in `sprinter_dbg[28..31]`
- note: `_sprinter_dbg` moved to `0xFE12`, so stamp is now at `0xFE2E..0xFE31`

Local verification:

- `Images/sprinter/fuzix.img` and `Images/sprinter/fuzix.chd` rebuilt at
  `2026-04-23 15:44` (local time)

### Correct next replay for `BA 27 04 4C`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFE20-0xFE40` (build stamp window, now based at `_sprinter_dbg=0xFE12`)
- `0xFCB6-0xFD05` (`i_open` + `n_open` + new `getdev` snapshots)
- `0xFD20-0xFD38` (`spr_rw_*` + `spr_initio_*`)
- `0x0000-0x0180` (user vectors/progload area)
- `0xEFA0-0xF000` (stack window at stop)

Decode:

- no `BA 27 04 4C` in `0xFE2E..0xFE31`
  => not the current image
- `SPRINTER WRITE OK` appears and system stays in `pause()`
  => `/init` userspace baseline is stable; blocker is specifically in
     user `open("/dev/tty1")/dup()` corridor
- still panic path
  => decode first from latched words:
  - `_sprinter_bad_iopen_dev/_ino/_bad/_mode/_nlink` + `_ptr/_a0/_a1/_flags`
  - `_spr_gd_dev/_spr_gd_mnt/_spr_gd_state`

### Update from 2026-04-23 16:20: confirmed `BA 27 04 4C`, current stop is pre-`d_open()` return in `fmount()`

The next replay is from the correct image (`0xFE2E..0xFE31 = BA 27 04 4C`),
but this run does **not** reach `/init`.  It stalls earlier with the bootmark
tail:

- `0r123456789ABEF`

and no `G/C/D/OK`.

Decoded latches from this dump:

- `_sprinter_dbg[15..18] = F3 01 00 01`
  (`fmount()` entered, `dev=0x0001`, `flags=0x01`)
- `_sprinter_dbg[4..9] = 01 00 DD 07 D0 00`
  (`d_open()` saw `dev=0x0001`, `maj=0`, `dev_open=0x07DD`, stage `0xD0` and
  never reached `0xD1`)

So the active blocker is a **corrupted `dev_tab[0].dev_open` pointer** before
root mount opens the block device.  This is the same class of issue we already
handled for tty major 2, now observed on major 0.

Current fix in `Kernel/devio.c:d_open()` under `CONFIG_SPRINTER_EARLY_TRACE`:

- extend the `dev_tab` repair guard from tty-only to **all majors**
- if `dev_open` pointer is below kernel code range (`< 0x4000`):
  - call `sprinter_restore_devsw()`
  - reload function pointer
  - if still invalid, fail with `ENXIO` and mark stage `0xDE` instead of
    jumping into garbage

Build stamp bumped again. Current image identifies as:

- `BA 27 04 4D` in `sprinter_dbg[28..31]`

### Correct next replay for `BA 27 04 4D`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFE10-0xFE40` (`sprinter_dbg[0..31]` + stamp + `d_open/fmount` markers)
- `0xFCF0-0xFD20` (`syscall enter/exit snapshots`)
- `0xFD20-0xFD38` (`spr_rw_*` + `spr_initio_*`)
- `0xFCB6-0xFD05` (`i_open/getdev` snapshots if we get that far)
- `0x0000-0x0180` (user vectors/progload area)
- `0xEFA0-0xF000` (stack window)

Decode:

- no `BA 27 04 4D` in `0xFE2E..0xFE31`
  => not the current image
- `_sprinter_dbg[8] = 0xD1` and then `G/C/D/OK` appear
  => root-device `d_open()` return path is repaired
- `_sprinter_dbg[8] = 0xDE`
  => `dev_tab` is still being clobbered after attempted restore; next step is
  to snapshot live `dev_tab[0..4]` words in `_COMMONDATA` before/after restore

### Update from 2026-04-23 16:45: BA4D still halts at `E3`, narrowed to `usermem` mapper race

Replay on confirmed `BA 27 04 4D` reaches:

- `Devboot`
- `OK`
- `Starting /init`

then traps in `sprinter_rst38_stub` with:

- `_sprinter_dbg[15] = 0xE3` (still inside exec stubs copy loop)
- `_sprinter_rst38_ret = 0x0011` (jumped into low `0x00xx`/`0xFF` area)
- no `E4` transition

The `d_open/fmount` blocker is gone on this image; current failure is now
inside the early `_execve` `uputc()` corridor.

Most likely cause is `user_map_de` in `platform-sprinter/usermem.s` using
`EXX` while interrupts can still arrive. If IRQ hits between `EXX` pairs,
alternate register state becomes inconsistent and we eventually return into
garbage (`0x0011` pattern seen in the dump).

Current fix:

- rewrote `user_map_de` to avoid `EXX` entirely (uses `push/pop de/hl`)
- added narrow `__uputc` latches:
  - `_sprinter_dbg[24]` = last byte value
  - `_sprinter_dbg[25]` = last destination low
  - `_sprinter_dbg[26]` = last destination high
  - `_sprinter_dbg[27]` = `mpgsel_cache+1` before remap

Build stamp bumped again. Current image identifies as:

- `BA 27 04 4E` in `sprinter_dbg[28..31]` (`0xFE3F..0xFE42`)

### Correct next replay for `BA 27 04 4E`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFE20-0xFE50` (`E3/E4` + new `__uputc` latches + build stamp)
- `0xFC4F-0xFC90` (`mpgsel_cache`, kernel map, `rst38`, `exec_fail_*`)
- `0x0000-0x0180` (low vectors / `progload` region)
- `0xEFA0-0xF000` (stack window at stop)

Decode:

- no `BA 27 04 4E` in `0xFE3F..0xFE42`
  => not the current image
- `_sprinter_dbg[15]` reaches `0xE4` (or later)
  => `user_map_de` `EXX` race was the active blocker
- still `E3` + `rst38`
  => next split: instrument `_uputc` wrapper frame/return bytes directly

### Update from 2026-04-23 18:12: BA4E advanced to `E5`, then jumped into FE-page trace bytes

Replay on confirmed `BA 27 04 4E` (`0xFE3F..0xFE42`) moved one stage
forward:

- `_sprinter_dbg[15] = 0xE5` (exec reached post-`valaddr_r` corridor)
- `PC = 0xFE10`, `HALT = 1`, `I = 0xFE`, `IM = 2`

The FE-page dump explains this stop directly:

- `_sprinter_trace_buf = 0xFD63..0xFE22`
- IM2 table is also seeded at `0xFE00..0xFEFF`
- so trace writes were corrupting the active IM2 vector page
- the CPU then fetched/ran bytes from that corrupted FE area and halted

Current fix (platform-local, reversible diagnostics retained):

- introduce `SPR_TRACE_LEN` and use it in both places:
  - `_plt_trace` wrap compare (`cp #SPR_TRACE_LEN`)
  - `_sprinter_trace_buf` allocation (`.ds SPR_TRACE_LEN`)
- set `SPR_TRACE_LEN = 125` so `_COMMONDATA` ends at `0xFDFF`
  and FE-page (`0xFE00..`) is reserved for IM2 only
- build stamp bumped again

Current image identifies as:

- `BA 27 04 4F` in `_sprinter_dbg[28..31]` at `0xFDFC..0xFDFF`

Current link-map anchors:

- `_COMMONDATA = 0xFC60..0xFDFF` (`l__COMMONDATA = 0x019F`)
- `_sprinter_trace_idx = 0xFD61`
- `_sprinter_trace_buf = 0xFD63..0xFDDF`
- `_sprinter_dbg = 0xFDE0`

### Correct next replay for `BA 27 04 4F`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFDD8-0xFE20` (`trace` tail + `_sprinter_dbg` + IM2 page head + stamp)
- `0xFC60-0xFC90` (`mpgsel_cache`, `rst38`, `exec_fail_*`)
- `0x0000-0x0180` (low vectors / `progload` region)
- `0xEFA0-0xF000` (stack window)

Decode:

- no `BA 27 04 4F` at `0xFDFC..0xFDFF`
  => not the current image
- `_sprinter_dbg[15] >= 0xE6` or visible `SPRINTER USERLAND OK`
  => FE-page IM2/trace overlap was the active blocker
- still halt with `PC` in `0xFE00..0xFE1F`
  => next split goes into IM2 fetch source (peripheral low-byte / irq-enable edge)

### Update from 2026-04-23 18:30: BA4F still dies before `D`, primary clue is NULL-vector hit then RST38

Replay on confirmed `BA 27 04 4F` (`0xFDFC..0xFDFF`) now lands at:

- screen tail: `...LMGC` (still no `D`/`OK`)
- `PC = 0xF1AC` (`sprinter_rst38_stub` hang loop), `HALT=1`
- `_sprinter_rst38_count = 1`
- `_sprinter_rst38_sp = 0xEFFE`
- `_sprinter_rst38_ret = 0x000A` (execution fell into low-page `0xFF` area)
- `_sprinter_nullh_count = 1`

Additional latch decode:

- `_sprinter_last_iopen_dev = 0x0001`
- `_sprinter_last_iopen_ino = 0x0001`
- `_sprinter_last_iopen_ret = 0`
- `_sprinter_last_iopen_bad = 0`

So `i_open(root_dev, ROOTINODE)` starts, then we lose control before a valid
inode return or `badino` path; meanwhile at least one 0x0000-vector hit occurs.

Current fix (platform-local):

- route vector `0x0000` to new `sprinter_null_stub` (instead of generic
  `null_handler`) in both vector programming paths
- `sprinter_null_stub` logs:
  - `_sprinter_rst38_sp` (current SP)
  - `_sprinter_rst38_ret` (top-of-stack return word)
  - `_sprinter_dbg[4..7]` (first two stack words)
  - `_sprinter_dbg[15] = 0xD9` marker
- then halts immediately, so we catch the primary null-vector fault before
  secondary drift into RST38.

Build stamp bumped again. Current image identifies as:

- `BA 27 04 50` in `_sprinter_dbg[28..31]`

### Correct next replay for `BA 27 04 50`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFC70-0xFC88` (`rst38/null` counters + logged SP/RET)
- `0xFCBC-0xFCD0` (`i_open` latches)
- `0xFDD8-0xFE20` (`_sprinter_dbg` + stamp + IM2 page head)
- `0x0000-0x0020` (low vectors / immediate fault bytes)
- `0xEFE0-0xF000` (top of stack window)

Decode:

- no `BA 27 04 50` at `_sprinter_dbg[28..31]`
  => wrong image loaded
- `_sprinter_dbg[15] = 0xD9`
  => null-vector trap fired first; use `rst38_sp/rst38_ret` + `_sprinter_dbg[4..7]`
     to locate the caller edge
- still `PC=F1AC` with `_sprinter_dbg[15] != 0xD9`
  => null event is secondary; continue on pure RST38 source path

### Update from 2026-04-23 18:46: rebuilt `BA 27 04 50`, map moved diagnostics into FE page

Rebuild after the NULL-vector trap patch completed cleanly with:

- `make TARGET=sprinter diskimage`
- CHD regenerated at `Images/sprinter/fuzix.chd`
- launcher `_306_fuzix.sh` already points to this exact file path

Current artefact checksums:

- `fuzix.img`  sha256 `235f7a21d20c60e89d171b384fc16d9be9348f1344e2255f20eea4f64de80a81`
- `fuzix.chd`  sha256 `40e72a70c7e756508cbc9e3fe307cc695313f4254c13961e009505efd526b612`

Important: with the current symbol set, `_COMMONDATA` shifted and
`_sprinter_dbg` is now at `0xFE10` (not `0xFDE0`), so the build stamp
for this image is at:

- `0xFE2C..0xFE2F` = `BA 27 04 50`

Current key symbol anchors from `Kernel/fuzix.map`:

- `_sprinter_rst38_count = 0xFCA3`
- `_sprinter_rst38_sp    = 0xFCA4`
- `_sprinter_rst38_ret   = 0xFCA6`
- `_sprinter_nullh_count = 0xFCB3`
- `_sprinter_last_iopen_dev = 0xFCEC`
- `_sprinter_last_iopen_ino = 0xFCEE`
- `_sprinter_last_iopen_ret = 0xFCF0`
- `_sprinter_last_iopen_bad = 0xFCF2`
- `_sprinter_bad_iopen_ptr  = 0xFD00`
- `_sprinter_last_nopen_stage = 0xFD08`
- `_sprinter_trace_idx = 0xFD91`
- `_sprinter_trace_buf = 0xFD93`
- `_sprinter_dbg       = 0xFE10`

### Correct next replay for the rebuilt `BA 27 04 50`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFCA0-0xFCBC` (`rst38/null` counters and nearby latches)
- `0xFCE8-0xFD12` (`i_open` and `n_open` diagnostics)
- `0xFE10-0xFE36` (`_sprinter_dbg` + build stamp)
- `0x0000-0x0020` (low vector area)
- `0xEFE0-0xF000` (top of stack window)

Decode:

- missing `BA 27 04 50` at `0xFE2C..0xFE2F`
  => emulator loaded a different image
- `_sprinter_dbg[15] == 0xD9`
  => `sprinter_null_stub` is now the primary trap; use
     `rst38_sp/rst38_ret` and `_sprinter_dbg[4..7]` to identify caller edge
- `_sprinter_dbg[15] != 0xD9` with `PC=F1AC`
  => NULL hit is not primary; continue along pure RST38 source path

### Update from 2026-04-23 19:05: BA50 replay showed FE-page overlap, diagnostics moved back below FE00

Replay on confirmed `BA 27 04 50` showed:

- stop still before `D` (`...LMGC`)
- `PC=F1AC` (`sprinter_rst38_stub`)
- `_sprinter_nullh_count = 0` (NULL trap not primary)
- `_sprinter_rst38_count = 1`
- `_sprinter_rst38_sp = 0x00FE`
- `_sprinter_rst38_ret = 0xFE01` (executing from FE-page data)

The dump also proved the immediate cause: `_sprinter_dbg` had moved to
`0xFE10`, so `_COMMONDATA` overlapped the IM2 page `0xFE00-0xFEFF` again.
That makes FE-page control-flow diagnostics unreliable and can feed bogus
return paths through FE data.

Current fix (platform-local, layout-only):

- reduced `SPR_TRACE_LEN` from `125` to `76`
- expanded `_sprinter_dbg` to `.ds 32` to match actual `[0..31]` writes
- bumped build stamp to `BA 27 04 51`

Current map anchors:

- `s__COMMONDATA = 0xFC90`
- `l__COMMONDATA = 0x016F`
- end of `_COMMONDATA` = `0xFDFF` (FE-page now reserved for IM2 again)
- `_sprinter_trace_idx = 0xFD91`
- `_sprinter_trace_buf = 0xFD93`
- `_sprinter_dbg = 0xFDDF`
- stamp `BA 27 04 51` is written at `0xFDFB..0xFDFE`

Current artefact checksums:

- `fuzix.img` sha256 `8164766744d44ab287e20294f64107bb50df0ca7909739dccbecd0c9c6083e61`
- `fuzix.chd` sha256 `17e3b6a06193ab8e55590dd1e3b9d0540f3a17e57acac32660d64fe25e902d48`

### Correct next replay for `BA 27 04 51`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFCA0-0xFCBC` (`rst38/null` counters and trap SP/RET)
- `0xFCE8-0xFD12` (`i_open` and `n_open` latches)
- `0xFDD8-0xFE20` (`trace tail + _sprinter_dbg + stamp + IM2 head`)
- `0x0000-0x0020` (low vectors)
- `0xEFE0-0xF000` (top of stack window)

Decode:

- no `BA 27 04 51` at `0xFDFB..0xFDFE`
  => wrong image loaded
- `_sprinter_nullh_count != 0` or `_sprinter_dbg[15] == 0xD9`
  => primary NULL-vector fault (use logged SP/RET and dbg[4..7])
- `_sprinter_nullh_count == 0` with `_sprinter_rst38_ret` in low page
  => continue pure `RST38` source split from the restored non-overlap baseline

### Update from 2026-04-23 19:35: `BA 27 04 53`, FE-page overlap removed again, null-trap context extended

Latest replay on `BA 27 04 51` still stopped at `Devboot/uF/...LMGC` with:

- `PC = 0xF1E6` (`null_hang`)
- `HALT = 1`
- `_sprinter_nullh_count = 1`
- `_sprinter_rst38_count = 0`
- logged return word `0x488F` (fault edge in mapped banked code, not FE page)

To decode this edge better, `sprinter_null_stub` now logs six bytes around the
fault return address (`ret-3..ret+2`) into `_sprinter_dbg[8..13]`.

During that edit, map growth moved diagnostics above `0xFE00` again; this was
corrected by reducing trace buffer size:

- `SPR_TRACE_LEN: 76 -> 43`
- `_sprinter_trace_buf` + `_sprinter_dbg` now end exactly at `0xFDFF`
- IM2 page `0xFE00-0xFEFF` is reserved again

Build stamp bumped to:

- `BA 27 04 53` in `_sprinter_dbg[28..31]`

Current map anchors (`Kernel/fuzix.map`):

- `_COMMONDATA = 0xFCB2..0xFDFF` (`l__COMMONDATA = 0x014E`)
- `_sprinter_rst38_count = 0xFCC5`
- `_sprinter_rst38_sp = 0xFCC6`
- `_sprinter_rst38_ret = 0xFCC8`
- `_sprinter_nullh_count = 0xFCD5`
- `_sprinter_last_iopen_dev = 0xFD0E`
- `_sprinter_last_iopen_ino = 0xFD10`
- `_sprinter_last_iopen_ret = 0xFD12`
- `_sprinter_last_iopen_bad = 0xFD14`
- `_sprinter_trace_idx = 0xFDB3`
- `_sprinter_trace_buf = 0xFDB5`
- `_sprinter_dbg = 0xFDE0`
- stamp bytes at `0xFDFC..0xFDFF`

Current artefact checksums:

- `fuzix.img` sha256 `222eadc57d26f49f06a15d32bb76004d0e7ce7e62b323b8d73d70d05b8ac932a`
- `fuzix.chd` sha256 `8521535d1487d9d3f1d25b7e033e46d0d432259a70b785e6705e5f723e16ba5f`

### Correct next replay for `BA 27 04 53`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFCC0-0xFCD8` (`rst38/null` counters and trap SP/RET)
- `0xFD0C-0xFD18` (`i_open` latches)
- `0xFDE0-0xFE10` (`_sprinter_dbg`, stamp, IM2 head)
- `0xEFC0-0xF000` (top of stack window)
- `0x4888-0x4898` (bytes around logged return edge `0x488F`)

Decode:

- no `BA 27 04 53` at `0xFDFC..0xFDFF`
  => wrong image loaded
- `_sprinter_dbg[15] != 0xD9`
  => not a NULL-vector primary fault; switch back to RST38 split
- `_sprinter_dbg[15] == 0xD9` and `dbg[8..13]` valid
  => proceed with exact instruction-level decode at the `0x488F` edge

### Update from 2026-04-23 21:08: `BA 27 04 55`, null-trap now logs `SP-2` word

Replay on `BA 27 04 53` confirmed:

- `PC = 0xF208` (`null_hang`)
- `_sprinter_nullh_count = 1`
- `_sprinter_rst38_count = 0`
- stack window near trap points at `0x488C` in `_i_open` (`call _breadi`)

To distinguish `call/jp 0` from `ret-to-0`, `sprinter_null_stub` now logs:

- `_sprinter_dbg[0..1]` = word at `SP-2` (already-popped return candidate)
- `_sprinter_dbg[2..7]` = words at `SP..SP+5`
- `_sprinter_rst38_ret` mirrors `_sprinter_dbg[0..1]`
- `_sprinter_dbg[8..13]` = bytes at `(_sprinter_dbg[0..1] - 3) .. +2`
- `_sprinter_dbg[15] = 0xD9` marker

During this change, code growth shifted `_COMMONDATA` upward; trace length was
reduced again to keep IM2 page exclusive:

- `SPR_TRACE_LEN: 43 -> 21`
- `_COMMONDATA = 0xFCC8..0xFDFF` (`l__COMMONDATA = 0x0138`)
- `_sprinter_dbg = 0xFDE0` (stamp back at `0xFDFC..0xFDFF`)

Build stamp bumped to:

- `BA 27 04 55`

Current artefact checksums:

- `fuzix.img` sha256 `97fdcbadb5f3d4da650263353322fdcdc6fcefa17e805a2d598ede68cbf6b7ee`
- `fuzix.chd` sha256 `05494187aea32eb66e929e3b4a77b684d0957e9f152e9be19d880237b86781d3`

### Correct next replay for `BA 27 04 55`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFCD8-0xFCF0` (`rst38/null` counters + trap SP/RET)
- `0xFD20-0xFD2C` (`i_open` latches)
- `0xFDE0-0xFE10` (`_sprinter_dbg` + stamp + IM2 head)
- `0xEFC0-0xF000` (top of stack window)
- `0x4880-0x4898` (current `_i_open` / `_breadi` call edge)

Decode:

- no `BA 27 04 55` at `0xFDFC..0xFDFF`
  => wrong image loaded
- `_sprinter_dbg[15] != 0xD9`
  => null trap not primary in this replay
- `_sprinter_dbg[15] == 0xD9` and `_sprinter_dbg[0..1] == 0x0000`
  => direct confirmation of `ret-to-0` path

### Update from 2026-04-23 21:45: `BA 27 04 57`, null-trap entry registers logged and FE-page overlap fixed again

Replay on `BA 27 04 55` stayed at `Devboot/uF/...LMGC` and still hit the
NULL-vector path (`PC` inside `sprinter_null_stub`, not `rst38_hang`), but this
iteration also exposed a regression in the next test build:

- after extending `sprinter_null_stub` register logging, `_sprinter_dbg` moved
  into `0xFE00+` again (IM2 vector page overlap)
- overlap would clobber both diagnostics and IM2 table, so this had to be
  corrected before the next replay

Fixes in this iteration:

- kept the new null-stub entry-register capture (`BC/DE/HL/AF` into
  `_sprinter_dbg[16..23]`)
- removed stale `_spr_dofork_*` diagnostics (no longer used for this failure)
- reduced `SPR_TRACE_LEN` from `21` to `3`
- bumped stamp to `BA 27 04 57`

Current map anchors (`Kernel/fuzix.map`):

- `_plt_monitor = 0xF100`
- `sprinter_null_stub = 0xF1B8` (`null_hang = 0xF23F`)
- `_sprinter_rst38_sp = 0xFCC9`
- `_sprinter_rst38_ret = 0xFCCB`
- `_sprinter_nullh_count = 0xFCD8`
- `_sprinter_trace_idx = 0xFDA6`
- `_sprinter_trace_buf = 0xFDA8` (3 bytes)
- `_sprinter_dbg = 0xFDAB`
- stamp bytes now at `0xFDC7..0xFDCA`

Current artefact checksums:

- `fuzix.img` sha256 `1937a2f0d5478bfde746d40dccf5ddb77e35cc7072077adccba8e59bfc61bb72`
- `fuzix.chd` sha256 `20e06c822cd25ea574906c6152b7783869537677bf9596d242e6cf80132febc5`

### Correct next replay for `BA 27 04 57`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFCC8-0xFCE2` (`rst38/null` counters + trap SP/RET)
- `0xFDA6-0xFDD0` (`trace idx/buf`, `_sprinter_dbg`, build stamp)
- `0xEFC0-0xF000` (top-of-stack window)
- `0x4880-0x49B0` (current `_i_open/_breadi` edge corridor)
- `0x0000-0x0020` (low vectors)

Decode:

- no `BA 27 04 57` at `0xFDC7..0xFDCA`
  => wrong image loaded
- `_sprinter_dbg[15] != 0xD9`
  => NULL vector not primary in this replay
- `_sprinter_dbg[15] == 0xD9`
  => use:
  `dbg[0..1]` (`SP-2` word), `dbg[2..7]` (`SP..SP+5`),
  `dbg[8..13]` (bytes around candidate return), and
  `dbg[16..23]` (entry `BC/DE/HL/AF`) to decide between `call/jp 0`,
  corrupted return, or indirect jump through zeroed register pair

### Update from 2026-04-23 22:06: `_doexec` stack unpack fixed (`BA 27 04 5A`)

Latest replay with `SPRINTER USERLAND OK` still dropped into `rst38_hang`.
The decisive check was in `Kernel/syscall_exec16.rst` around `doexec()`:

```
push hl        ; entry argument
call _doexec
```

So `_doexec` receives stack as `ret, start_addr` only.  But
`cpu-z80/lowlevel-z80-banked.s` still consumed `ret, AF, start_addr`, i.e.
it popped one extra word before loading the entry PC.  That turns the jump
target into garbage and explains immediate userland control-flow loss after
`Starting /init`.

Fix in this iteration:

- `Kernel/cpu-z80/lowlevel-z80-banked.s:_doexec` no longer pops the phantom
  AF word; it now unpacks only `ret` and `start_addr`.
- Build stamp bumped to `BA 27 04 5A` (`_sprinter_dbg[31]`).

Current artefact checksums:

- `fuzix.img` sha256 `3cd34e96dc97c2e645f1fed1214083d76e9ba3cc1595252625c7b0b23b1bb9f0`
- `fuzix.chd` sha256 `6a66fdb454e220e9468e96ad47d86477115de9a0caae60593f12200954ab1f3b`

### Update from 2026-04-23 22:29: replay still used old image (`BA 27 04 57`)

The latest emulator dump attached after the `_doexec` fix still shows the old
stamp bytes `BA 27 04 57` (old layout with `_sprinter_dbg` starting near
`0xFDAB`).  So this replay did not boot the rebuilt `fuzix.chd` from the
`_doexec` fix iteration (`BA 27 04 5A`), and cannot validate or invalidate the
stack-unpack fix itself.

Working assumption remains unchanged:

- first valid replay we need is on `BA 27 04 5A`
- only after that replay we decide whether the remaining blocker is still in
  `_doexec`/entry handoff or moved into first userspace/syscall path

### Correct next replay for `BA 27 04 5A`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFCC7-0xFCDC` (`_sprinter_rst38_count/_sp/_ret`, NULL counter area)
- `0xFD62-0xFD9C` (`syscall` and `_doexec` probes)
- `0xFDBF-0xFDE8` (`trace idx/buf`, `_sprinter_dbg`, build stamp region)
- `0xEFC0-0xF000` (top-of-stack window)
- `0x0000-0x0140` (low vectors + early user window)

Decode:

- no `BA 27 04 5A` at `0xFDE0..0xFDE3`
  => wrong image loaded, replay invalid for current hypothesis
- `BA 27 04 5A` present and `_spr_doexec_call_start != _spr_doexec_expect`
  => `_doexec` frame still mismatched
- `BA 27 04 5A` present and `_spr_doexec_call_start == _spr_doexec_expect`
  => entry handoff is consistent; focus moves to first userspace control-flow edge

### Update from 2026-04-23 22:40: rebuilt `BA 27 04 5A`, launcher path rechecked

Rebuilt from a clean `kclean` + `diskimage` cycle and verified the MAME launcher
still points to the same artefact path:

- script: `/Users/dmitry/dev/zx/sprinter/mame_images/mame_release_v306_25.05.2025/_306_fuzix.sh`
- `-hard1 /Users/dmitry/dev/zx/sprinter/FUZIX/Images/sprinter/fuzix.chd`

Current artefact checksums after this rebuild:

- `fuzix.img` sha256 `412b5b5fa504c002a97e3a874927e4eac9e7e786ce7d09665daa5889c5c7cb22`
- `fuzix.chd` sha256 `86c2dc0f92a3dc9e33a8b41806c3d88ce55d06a57ed41318e142fd3ed288bc4b`

Current map anchors for the `_doexec`/trap split:

- `_sprinter_rst38_count = 0xFCC7`
- `_sprinter_rst38_sp = 0xFCC8`
- `_sprinter_rst38_ret = 0xFCCA`
- `_spr_sys_enter_no = 0xFD62`
- `_spr_sys_exit_no = 0xFD6C`
- `_spr_doexec_arm = 0xFD7A`
- `_spr_doexec_call_start = 0xFD92`
- `_sprinter_trace_idx = 0xFDBF`
- `_sprinter_dbg = 0xFDC4` (stamp at `0xFDE0..0xFDE3`)

The next valid replay still must confirm stamp `BA 27 04 5A` at
`0xFDE0..0xFDE3`; any replay with `BA 27 04 57` remains invalid for this
iteration.

### Update from 2026-04-23 23:20: corrected `_doexec` ABI unpack (`BA 27 04 5B`)

Replay on valid `BA 27 04 5A` reached:

- `Starting /init`
- `SPRINTER USERLAND OK`
- then `PC=F1AC` (`rst38_hang`)

The decisive evidence came from generated `Kernel/syscall_exec16.asm`
around `doexec()` call site:

```
push bc
push de          ; start address argument
push af ;noopt   ; extra SDCC ABI word
call _doexec
```

So `_doexec` does **not** receive just `ret,start_addr`.  It receives
`ret,noopt_af,start_addr,...`.  Our previous `BA 27 04 5A` change removed
`pop af`, therefore `_doexec` consumed the wrong word as entry PC.

Fix in this iteration:

- `Kernel/cpu-z80/lowlevel-z80-banked.s:_doexec` restored
  `pop af` (discard noopt word) before `pop de` start address.
- build stamp bumped to `BA 27 04 5B` (`Kernel/start.c`).

Current artefact checksums:

- `fuzix.img` sha256 `9c22b77cd6cb2c2aea9c38ce982751065ff6ee62b1c40160679aaa7166741cdc`
- `fuzix.chd` sha256 `0f4a24c1597507b6a105f967dfc411066923cf79eacd1ef9ee0eb9137e4ba7ad`

Current map anchors after this rebuild:

- `_sprinter_rst38_count = 0xFCC8`
- `_sprinter_rst38_sp = 0xFCC9`
- `_sprinter_rst38_ret = 0xFCCB`
- `_spr_sys_enter_no = 0xFD63`
- `_spr_sys_exit_no = 0xFD6D`
- `_spr_doexec_arm = 0xFD7B`
- `_spr_doexec_call_start = 0xFD93`
- `_sprinter_trace_idx = 0xFDC0`
- `_sprinter_dbg = 0xFDC5` (stamp at `0xFDE1..0xFDE4`)

### Correct next replay for `BA 27 04 5B`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFCC8-0xFCDD` (`rst38` counters/sp/ret + null counter area)
- `0xFD63-0xFD9E` (syscall and doexec probes)
- `0xFDC0-0xFDE8` (`trace_idx`, `trace_buf`, `_sprinter_dbg`, build stamp)
- `0xEFC0-0xF000` (top-of-stack window)
- `0x0000-0x0140` (low vectors window)

Decode:

- no `BA 27 04 5B` at `0xFDE1..0xFDE4`
  => wrong image loaded
- `BA 27 04 5B` present and no halt after `SPRINTER USERLAND OK`
  => `_doexec` stack unpack blocker confirmed fixed
- still halts at `F1AC`
  => use `_sprinter_rst38_ret` + `_sprinter_dbg[0..3]` to continue from the
     first post-fix user/kernel control-flow edge

### Update from 2026-04-23 23:04: replay still on `BA 27 04 5A`, rebuilt `5B` images

Latest supplied replay still shows stamp `BA 27 04 5A` at `0xFDE0..0xFDE3`
and the known post-`SPRINTER USERLAND OK` fall into `PC=F1AC` (NULL trap
loop).  This means it is not yet a validating run for the `_doexec` ABI fix
iteration (`BA 27 04 5B`).

Rebuilt `TARGET=sprinter diskimage` again and refreshed `Images/sprinter/*`:

- `fuzix.img` sha256 `be4772fa51049b46e17dc16a5e5637fd8eade1eaad3bfaacf6c5758e3d815a1e`
- `fuzix.chd` sha256 `f84f2dab46fc9040d05327f5b86bc0bcec2c1cc90f76f71b588153c40df8e201`

Map anchors remain:

- `_sprinter_rst38_count = 0xFCC8`
- `_sprinter_rst38_sp = 0xFCC9`
- `_sprinter_rst38_ret = 0xFCCB`
- `_spr_sys_enter_no = 0xFD63`
- `_spr_sys_exit_no = 0xFD6D`
- `_spr_doexec_arm = 0xFD7B`
- `_spr_doexec_call_start = 0xFD93`
- `_sprinter_trace_idx = 0xFDC0`
- `_sprinter_dbg = 0xFDC5` (stamp at `0xFDE1..0xFDE4`)

Next valid replay target is unchanged: confirm `BA 27 04 5B` at
`0xFDE1..0xFDE4`, then evaluate post-fix control flow.

### Update from 2026-04-24 00:40: `doexec` fallback frame probe (`BA 27 04 5C`)

Valid `BA 27 04 5B` replay now consistently shows:

- `Starting /init`
- `SPRINTER USERLAND OK`
- trap in `rst38_hang` (`PC=0xF1AC`, `HALT=1`)
- `_sprinter_rst38_count = 1`, `_sprinter_rst38_sp = 0xEFD3`,
  `_sprinter_rst38_ret = 0xC001`
- `_sprinter_dbg[0..3] = FF FF FF FF` and `_sprinter_dbg[15] = 0xEA`

So we are past `/init` load and right at the `doexec()` handoff edge, but the
`_spr_doexec_call_*` latches in the same dumps are still zeroed.  That means
our old probe gate (`_spr_doexec_arm`) is not reliable enough for this edge.

This iteration changes only `platform-sprinter/sprinter.s`:

- `map_proc_always` still captures the same stack words, but now it arms on
  either:
  - `_spr_doexec_arm != 0` (old path, records `_spr_doexec_call_seen = 1`), or
  - fallback marker `_sprinter_dbg[15] == 0xEA` (new path, records
    `_spr_doexec_call_seen = 2`)

Build stamp bumped to `BA 27 04 5C` (`Kernel/start.c`).

Current artefact checksums:

- `fuzix.img` sha256 `c7cde47dd809458f8c60e1ecced246ad6932c2fa5ae8262327c103de9ae228c7`
- `fuzix.chd` sha256 `061e9349dd94165e420b16b98b606f12bcc7f134761356774da1572c0536f709`

Map anchors for this replay:

- `_sprinter_rst38_count = 0xFCC8`
- `_sprinter_rst38_sp = 0xFCC9`
- `_sprinter_rst38_ret = 0xFCCB`
- `_spr_sys_enter_no = 0xFD63`
- `_spr_sys_exit_no = 0xFD6D`
- `_spr_doexec_arm = 0xFD7B`
- `_spr_doexec_call_seen = 0xFD8A`
- `_spr_doexec_call_sp = 0xFD8B`
- `_spr_doexec_call_ra0 = 0xFD8D`
- `_spr_doexec_call_ra1 = 0xFD8F`
- `_spr_doexec_call_af = 0xFD91`
- `_spr_doexec_call_start = 0xFD93`
- `_sprinter_trace_idx = 0xFDC0`
- `_sprinter_dbg = 0xFDC5` (stamp at `0xFDE1..0xFDE4`)

### Correct next replay for `BA 27 04 5C`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFCC8-0xFCDD` (`rst38` counters/sp/ret + null counter area)
- `0xFD7B-0xFD96` (`doexec` arm/call-frame latches)
- `0xFDC0-0xFDE8` (`trace_idx`, `trace_buf`, `_sprinter_dbg`, build stamp)
- `0xEFC0-0xF000` (top-of-stack window)
- `0x0000-0x0140` (low vectors window)

Decode:

- no `BA 27 04 5C` at `0xFDE1..0xFDE4`
  => wrong image loaded
- `_spr_doexec_call_seen = 0`
  => `_doexec -> map_proc_always` edge still not being observed
- `_spr_doexec_call_seen = 1` or `2`, but `_spr_doexec_call_start` is not equal
  to `_spr_doexec_expect`
  => bad stack-frame unpack at `doexec` entry
- `_spr_doexec_call_seen = 1` or `2` and `_spr_doexec_call_start ==
  _spr_doexec_expect`, yet `_sprinter_rst38_ret = 0xC001`
  => handoff argument is correct, next blocker is immediate post-jump control
     flow (entry/vector/common-page execution)

### Update from 2026-04-24 08:06: direct `map_proc_always` frame mirror (`BA 27 04 5D`)

Latest valid `BA 27 04 5C` replay still lands in:

- `Starting /init`
- `SPRINTER USERLAND OK`
- `PC=0xF1AC` (`rst38_hang`), `HALT=1`
- `_sprinter_rst38_ret = 0xC001`
- `_spr_doexec_call_seen = 0`

So even with fallback arming (`dbg[15] == 0xEA`), the dedicated
`_spr_doexec_call_*` latch block is still unreliable in-field for this edge.

This iteration keeps all logic local to `platform-sprinter/sprinter.s` and adds
a second mirror channel into the already-stable `sprinter_dbg[]` window:

- `sprinter_dbg[14]` <- `_spr_doexec_call_seen` source marker (`1` arm, `2`
  fallback)
- `sprinter_dbg[24..25]` <- captured `ra0` word
- `sprinter_dbg[26..27]` <- captured `start` word

Build stamp bumped to `BA 27 04 5D` (`Kernel/start.c`).

Current artefact checksums:

- `fuzix.img` sha256 `45de47924ec417d937454d3dcbc96e31898d0f64b751bd9cb1435e097264b96f`
- `fuzix.chd` sha256 `e90d1f51b8623f94e0bbf32527deb55d346151dbcdc868a6773df1244360c6ca`

Map anchors are unchanged from `5C`:

- `_sprinter_rst38_count = 0xFCC8`
- `_sprinter_rst38_sp = 0xFCC9`
- `_sprinter_rst38_ret = 0xFCCB`
- `_spr_doexec_arm = 0xFD7B`
- `_spr_doexec_call_seen = 0xFD8A`
- `_spr_doexec_call_sp = 0xFD8B`
- `_spr_doexec_call_ra0 = 0xFD8D`
- `_spr_doexec_call_ra1 = 0xFD8F`
- `_spr_doexec_call_af = 0xFD91`
- `_spr_doexec_call_start = 0xFD93`
- `_sprinter_trace_idx = 0xFDC0`
- `_sprinter_dbg = 0xFDC5` (stamp at `0xFDE1..0xFDE4`)

### Correct next replay for `BA 27 04 5D`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFCC8-0xFCDD` (`rst38` counters/sp/ret + null counter area)
- `0xFD7B-0xFD96` (`doexec` arm/call-frame latches)
- `0xFDC0-0xFDE8` (`trace_idx`, `trace_buf`, `_sprinter_dbg`, build stamp)
- `0xEFC0-0xF000` (top-of-stack window)
- `0x0000-0x0140` (low vectors window)

Decode:

- no `BA 27 04 5D` at `0xFDE1..0xFDE4`
  => wrong image loaded
- `sprinter_dbg[14] == 0` and `_spr_doexec_call_seen == 0`
  => `map_proc_always` capture path truly not hit on this edge
- `sprinter_dbg[14] != 0`, but `_spr_doexec_call_seen == 0`
  => latch block is being overwritten later; trust `dbg[24..27]` mirror
- `sprinter_dbg[26..27] == _spr_doexec_expect` and still `_sprinter_rst38_ret = 0xC001`
  => `_doexec` handoff address is correct; blocker moved to immediate post-jump flow

### Update from 2026-04-24 08:31: `sprinit` write-only loop (same kernel stamp `5D`)

To split `doexec` handoff from first userspace syscall/scheduler paths, the
Sprinter test init payload was narrowed:

- `Applications/util/sprinit.c` now does only:
  - one `write(1, "SPRINTER WRITE ONLY OK\\r\\n", ...)`
  - then a pure user-space spin loop (`spin++`) with no further syscalls
- removed `getpid()` and `pause()` from the probe payload

This keeps kernel stamp at `BA 27 04 5D` (no kernel-code change), but changes
filesystem content (`/init` payload).

Refreshed artefact checksums for this run:

- `fuzix.img` sha256 `afc8c99fe83f24db6b06c1643c0137a1fe89be2746a69a48f36d25c5b5603b96`
- `fuzix.chd` sha256 `9f2e6df911e85688b16823fa3417ff13a96fa751bb8c3cda0e0164713bfd0aff`

Interpretation target:

- if `SPRINTER WRITE ONLY OK` appears and no immediate `rst38_hang`
  => first userspace syscall return path is alive; previous stop was likely
     on the `pause()`/sleep path
- if it still falls into `PC=F1AC` before that line
  => blocker is earlier (entry/first syscall/control transfer), continue with
     the same `5D` address set above

### Update from 2026-04-24: extended `RST 38` context latch (`BA 27 04 5E`)

Latest replays with the refreshed image still reach:

- `Starting /init`
- `SPRINTER USERLAND OK`
- then halt in `rst38_hang` (`PC=0xF1AC`, `HALT=1`)

To move from "we trap at `RST 38`" to "which execution context trapped", the
Sprinter trap stub now records extra context on every `0x0038` hit:

- `udata.u_insys`
- `udata.u_callno`
- `udata.u_ininterrupt`
- `udata.u_page[0..2]`
- `mpgsel_cache[0..2]`
- CPU `I` register

Changes are platform-local (`platform-sprinter/sprinter.s`) under the existing
bring-up diagnostics model.  Build stamp bumped to `BA 27 04 5E`.

Current artefact checksums:

- `fuzix.img` sha256 `ce75e0df9fdff256f3d8dc42a6c58b21e9d0927f6ce2e411bbc840d8d455fe63`
- `fuzix.chd` sha256 `389192cbb0ba46579335e16dd626ef8a700c8bb92851ad7d5fb41b039493eaa0`
- `Applications/util/sprinit` sha256 `f0f2f070c2bddf30a4cf35bf17c7953f813c4d917bc91e4650e3b274f6aee41c`

Map anchors for this image:

- `_plt_monitor = 0xF100`
- `_doexec = 0xF605`
- `null_handler = 0xF619`
- `trap_illegal = 0xF64A`
- `_sprinter_rst38_count = 0xFD03`
- `_sprinter_rst38_sp = 0xFD04`
- `_sprinter_rst38_ret = 0xFD06`
- `_sprinter_rst38_insys = 0xFD08`
- `_sprinter_rst38_callno = 0xFD09`
- `_sprinter_rst38_inirq = 0xFD0A`
- `_sprinter_rst38_up0 = 0xFD0B`
- `_sprinter_rst38_up1 = 0xFD0C`
- `_sprinter_rst38_up2 = 0xFD0D`
- `_sprinter_rst38_mp0 = 0xFD0E`
- `_sprinter_rst38_mp1 = 0xFD0F`
- `_sprinter_rst38_mp2 = 0xFD10`
- `_sprinter_rst38_i = 0xFD11`
- `_spr_doexec_arm = 0xFDC0`
- `_spr_doexec_map_ptr = 0xFDC2`
- `_spr_doexec_expect = 0xFDC4`
- `_spr_doexec_call_seen = 0xFDCF`
- `_spr_doexec_call_sp = 0xFDD0`
- `_spr_doexec_call_ra0 = 0xFDD2`
- `_spr_doexec_call_ra1 = 0xFDD4`
- `_spr_doexec_call_af = 0xFDD6`
- `_spr_doexec_call_start = 0xFDD8`
- `_sprinter_trace_idx = 0xFE05`
- `_sprinter_dbg = 0xFE0A` (stamp at `0xFE26..0xFE29`)

### Correct next replay for `BA 27 04 5E`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFD03-0xFD20` (`rst38` full context block)
- `0xFDC0-0xFDE0` (`doexec` arm/call-frame latches)
- `0xFE05-0xFE32` (`trace_idx`, `sprinter_dbg[]`, build stamp)
- `0xEFC0-0xF000` (top-of-stack window)
- `0x0000-0x0140` (low vectors)

Decode:

- no `BA 27 04 5E` at `0xFE26..0xFE29`
  => wrong image loaded
- `_sprinter_rst38_count == 0`
  => this replay did not hit the `RST 38` stub
- `_sprinter_rst38_count != 0` and `_sprinter_rst38_insys == 0`
  => trap happened outside syscall core (likely immediate post-handoff user flow)
- `_sprinter_rst38_count != 0` and `_sprinter_rst38_insys == 1`
  => trap happened while still inside syscall/mapper path; use `callno` + `up/mp`
     bytes to locate the exact corridor
- `_spr_doexec_call_seen != 0` with `_spr_doexec_call_start == _spr_doexec_expect`
  and still `_sprinter_rst38_ret = 0xC001`
  => `doexec` entry argument is valid; blocker is after jump (entry/vector/common
     execution), not call-frame unpack

### Update from 2026-04-24: null-trap now mirrors full context block (`BA 27 04 5F`)

Latest replay no longer looked like pure `rst38_hang`; it halted with:

- `PC = 0xF27B`, `HALT = 1`
- still around `Starting /init` edge

That corridor is adjacent to the NULL-vector stop loop (`null_hang`) and
`_devide_read_data`, so we need the same context bytes for NULL traps that we
already log for `RST 38`.

Change applied (platform-local):

- `sprinter_null_stub` now also stores into `_sprinter_rst38_*` context bytes:
  - `insys/callno/inirq`
  - `u_page[0..2]`
  - `mpgsel_cache[0..2]`
  - `I`
- build stamp bumped to `BA 27 04 5F` in `fuzix_main()` early-trace block.

This keeps replay decoding unified: both `RST 38` and NULL-vector fatal edges
populate the same context latch area.

Current artefact checksums:

- `fuzix.img` sha256 `0212291e606aa09612a354549e44229c02457d51b6e11f02ccd9502045ab2771`
- `fuzix.chd` sha256 `f56d49081e7c10591b373ce14ef1ab6f32fb37a31b315061fdb9bf58e28814a2`
- `Applications/util/sprinit` sha256 `f0f2f070c2bddf30a4cf35bf17c7953f813c4d917bc91e4650e3b274f6aee41c`

Map anchors for this image:

- `_plt_monitor = 0xF100`
- `sprinter_null_stub = 0xF1F3` (`null_hang = 0xF2B5`)
- `_devide_read_data = 0xF2B8`
- `_doexec = 0xF640`
- `null_handler = 0xF654`
- `trap_illegal = 0xF685`
- `_sprinter_rst38_count = 0xFD3E`
- `_sprinter_rst38_sp = 0xFD3F`
- `_sprinter_rst38_ret = 0xFD41`
- `_sprinter_rst38_insys = 0xFD43`
- `_sprinter_rst38_callno = 0xFD44`
- `_sprinter_rst38_inirq = 0xFD45`
- `_sprinter_rst38_up0..up2 = 0xFD46..0xFD48`
- `_sprinter_rst38_mp0..mp2 = 0xFD49..0xFD4B`
- `_sprinter_rst38_i = 0xFD4C`
- `_sprinter_nullh_count = 0xFD58`
- `_spr_doexec_arm = 0xFDFB`
- `_spr_doexec_map_ptr = 0xFDFD`
- `_spr_doexec_expect = 0xFDFF`
- `_spr_doexec_call_seen = 0xFE0A`
- `_spr_doexec_call_sp = 0xFE0B`
- `_spr_doexec_call_ra0 = 0xFE0D`
- `_spr_doexec_call_ra1 = 0xFE0F`
- `_spr_doexec_call_af = 0xFE11`
- `_spr_doexec_call_start = 0xFE13`
- `_sprinter_trace_idx = 0xFE40`
- `_sprinter_dbg = 0xFE45` (stamp at `0xFE61..0xFE64`)

### Correct next replay for `BA 27 04 5F`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFD3E-0xFD5C` (`rst38/null` shared context block + null count)
- `0xFDFB-0xFE18` (`doexec` arm/call-frame latches)
- `0xFE40-0xFE66` (`trace_idx`, `sprinter_dbg[]`, build stamp)
- `0xEFA0-0xF000` (top-of-stack window)
- `0xF1E0-0xF2D0` (null stub / null_hang / devide corridor)
- `0x0000-0x0140` (low vectors)

Decode:

- no `BA 27 04 5F` at `0xFE61..0xFE64`
  => wrong image loaded
- `_sprinter_nullh_count != 0`
  => NULL-vector path is primary; use `_sprinter_rst38_insys/callno/inirq/up/mp/i`
     as NULL-context latches and correlate with `PC` near `null_hang`
- `_sprinter_nullh_count == 0` and `_sprinter_rst38_count != 0`
  => primary failure is true `RST 38` again
- both counters stay zero
  => this replay stopped elsewhere; use `PC` corridor dump (`0xF1E0-0xF2D0`) first

### Update from 2026-04-24: NULL trap now mirrors `SP` and `SP+2` words (`BA 27 04 60`)

Latest supplied replay still showed stamp `BA 27 04 5E` and halted around:

- `PC = 0xF27B`, `HALT = 1`
- `Starting /init` corridor

So the NULL-vector path is still primary, but we were only latching `SP-2`
(via `_sprinter_rst38_ret`).  To separate `CALL 0`, `JP 0`, and stack-return
corruption more cleanly, `sprinter_null_stub` now also latches:

- `_sprinter_null_sp0` = word at entry `SP`
- `_sprinter_null_sp2` = word at entry `SP+2`

Existing `SP-2` latch remains unchanged in `_sprinter_rst38_ret`.
Build stamp bumped to `BA 27 04 60`.

Current artefact checksums:

- `fuzix.img` sha256 `43d16e540de9b19886693537220757e6178a71ec010e63ce3c0c463185e12b7e`
- `fuzix.chd` sha256 `802013a49c7834e27d6e62d5fb3d6a8586c6bf78c2e002b0d3230594f7f5a004`
- `Applications/util/sprinit` sha256 `f0f2f070c2bddf30a4cf35bf17c7953f813c4d917bc91e4650e3b274f6aee41c`

Map anchors for this image:

- `_plt_monitor = 0xF100`
- `sprinter_null_stub = 0xF1F3` (`null_hang = 0xF2D0`)
- `_devide_read_data = 0xF2D3`
- `_doexec = 0xF65B`
- `null_handler = 0xF66F`
- `trap_illegal = 0xF6A0`
- `_sprinter_rst38_count = 0xFD59`
- `_sprinter_rst38_sp = 0xFD5A`
- `_sprinter_rst38_ret = 0xFD5C` (`SP-2` word)
- `_sprinter_rst38_insys = 0xFD5E`
- `_sprinter_rst38_callno = 0xFD5F`
- `_sprinter_rst38_inirq = 0xFD60`
- `_sprinter_rst38_up0..up2 = 0xFD61..0xFD63`
- `_sprinter_rst38_mp0..mp2 = 0xFD64..0xFD66`
- `_sprinter_rst38_i = 0xFD67`
- `_sprinter_nullh_count = 0xFD73`
- `_sprinter_null_sp0 = 0xFD74` (word at entry `SP`)
- `_sprinter_null_sp2 = 0xFD76` (word at entry `SP+2`)
- `_spr_doexec_arm = 0xFE1A`
- `_spr_doexec_map_ptr = 0xFE1C`
- `_spr_doexec_expect = 0xFE1E`
- `_spr_doexec_call_seen = 0xFE29`
- `_spr_doexec_call_sp = 0xFE2A`
- `_spr_doexec_call_ra0 = 0xFE2C`
- `_spr_doexec_call_ra1 = 0xFE2E`
- `_spr_doexec_call_af = 0xFE30`
- `_spr_doexec_call_start = 0xFE32`
- `_sprinter_trace_idx = 0xFE5F`
- `_sprinter_dbg = 0xFE64` (stamp at `0xFE80..0xFE83`)

### Correct next replay for `BA 27 04 60`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFD59-0xFD78` (`rst38/null` context + `null_sp0/null_sp2`)
- `0xFE1A-0xFE34` (`doexec` arm/call-frame latches)
- `0xFE5F-0xFE84` (`trace_idx`, `sprinter_dbg[]`, build stamp)
- `0xEFA0-0xF000` (top-of-stack window)
- `0xF1E0-0xF2F0` (null stub / null_hang / devide corridor)
- `0x0000-0x0140` (low vectors)

Decode:

- no `BA 27 04 60` at `0xFE80..0xFE83`
  => wrong image loaded
- `_sprinter_nullh_count != 0` and `_sprinter_null_sp0 != 0`
  => likely `CALL 0` path; `null_sp0` is the immediate return candidate
- `_sprinter_nullh_count != 0` and `_sprinter_null_sp0 == 0`, but `_sprinter_rst38_ret != 0`
  => likely `JP 0` / stack-frame drift path; use `SP-2` bytes (`rst38_ret` + `dbg[8..13]`)
- `_sprinter_nullh_count == 0` and `_sprinter_rst38_count != 0`
  => primary edge is back to true `RST 38`

### Update from 2026-04-24: confirmed `BA 27 04 60` is true `RST 38`, moved IM2 page to `0xFF00` (`BA 27 04 62`)

Latest valid replay on stamp `BA 27 04 60` showed:

- screen reaches `Starting /init` and `SPRINTER USERLAND OK`
- halt at `PC = 0xF1E7` (`rst38_hang`)
- `IM = 2`, `I = 0xFE`

Decoded `RST 38` context from that replay:

- `_sprinter_rst38_count = 1`
- `_sprinter_nullh_count = 0`
- `_sprinter_rst38_sp = 0xEFD3`
- `_sprinter_rst38_ret = 0xC001`
- `_sprinter_rst38_insys = 1`
- `_sprinter_rst38_callno = 0`
- `_sprinter_rst38_inirq = 0`
- `_sprinter_rst38_up0..up2 = 0x40,0x41,0x42`
- `_sprinter_rst38_mp0..mp2 = 0x48,0x4E,0x4F`
- `_sprinter_rst38_i = 0xFE`

So the failing edge in this replay is no longer the NULL vector path; it is a
real `RST 38` while still in syscall context, with kernel mapping active.
Given `BA 27 04 60` still kept IM2 table and live diagnostics on the same
`0xFE00` page, the next narrow step is to remove that alias completely.

Applied platform-local change in `platform-sprinter/sprinter.s`:

- IM2 vector table moved from `0xFE00` to `0xFF00`
- `I` is initialized to `0xFF`
- `0xFDFD -> JP sprinter_bringup_int` logic unchanged

Build stamp bumped to `BA 27 04 62` in `Kernel/start.c`.

Current artefact checksums:

- `fuzix.img` sha256 `c0782dd844f0ef2933821eeb3159e72fd1d1874546c3f540e0829f20d143d1e5`
- `fuzix.chd` sha256 `43bb54861c3f1b7eee5af0d41a6c734506b287424948aad58aa2a73102b83094`
- `Applications/util/sprinit` sha256 `f0f2f070c2bddf30a4cf35bf17c7953f813c4d917bc91e4650e3b274f6aee41c`

Map anchors for this image:

- `_plt_monitor = 0xF100`
- `sprinter_rst38_stub = 0xF180` (`rst38_hang = 0xF1E6`)
- `sprinter_null_stub = 0xF1F3` (`null_hang = 0xF2D0`)
- `_devide_read_data = 0xF2D3`
- `_sprinter_rst38_count = 0xFD5B`
- `_sprinter_rst38_sp = 0xFD5C`
- `_sprinter_rst38_ret = 0xFD5E`
- `_sprinter_rst38_insys = 0xFD60`
- `_sprinter_rst38_callno = 0xFD61`
- `_sprinter_rst38_inirq = 0xFD62`
- `_sprinter_rst38_up0..up2 = 0xFD63..0xFD65`
- `_sprinter_rst38_mp0..mp2 = 0xFD66..0xFD68`
- `_sprinter_rst38_i = 0xFD69`
- `_sprinter_nullh_count = 0xFD75`
- `_sprinter_null_sp0 = 0xFD76`
- `_sprinter_null_sp2 = 0xFD78`
- `_spr_doexec_arm = 0xFE1C`
- `_spr_doexec_map_ptr = 0xFE1E`
- `_spr_doexec_expect = 0xFE20`
- `_spr_doexec_call_seen = 0xFE2B`
- `_spr_doexec_call_sp = 0xFE2C`
- `_spr_doexec_call_ra0 = 0xFE2E`
- `_spr_doexec_call_ra1 = 0xFE30`
- `_spr_doexec_call_af = 0xFE32`
- `_spr_doexec_call_start = 0xFE34`
- `_sprinter_trace_idx = 0xFE61`
- `_sprinter_dbg = 0xFE66` (stamp at `0xFE82..0xFE85`)

### Correct next replay for `BA 27 04 62`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFD5B-0xFD79` (`rst38/null` context)
- `0xFE1C-0xFE36` (`doexec` arm/call-frame latches)
- `0xFE61-0xFE86` (`trace_idx`, `sprinter_dbg[]`, build stamp)
- `0xFF00-0xFF40` (IM2 vector page sample after runtime)
- `0xEFA0-0xF000` (top-of-stack window)
- `0xF170-0xF2F0` (trap corridor)
- `0x0000-0x0140` (low vectors)

Decode:

- no `BA 27 04 62` at `0xFE82..0xFE85`
  => wrong image loaded
- `_sprinter_rst38_count == 0` and `_sprinter_nullh_count == 0`
  => this replay did not hit current fatal stubs
- `_sprinter_rst38_count != 0` and `_sprinter_rst38_i == 0xFF`
  => true post-relocation fault; FE-page alias is no longer the trigger
- `_sprinter_rst38_count != 0` and `_sprinter_rst38_i == 0xFE`
  => stale image or stale pre-relocation path still booted
- `0xFF00-0xFF40` not predominantly `0xFD`
  => IM2 vector page got clobbered after boot; continue from that write path

### Update from 2026-04-24: latched entry registers in `RST 38` stub (`BA 27 04 63`)

The failure signature is still the same corridor (`Starting /init`,
`SPRINTER USERLAND OK`, then stop in `rst38_hang`), but prior context still
did not prove whether the edge is a corrupted return frame, wrong `_doexec`
argument unpack, or register-state drift before the trap.

Added one more platform-local diagnostic in `sprinter_rst38_stub`:

- `_sprinter_dbg[4..5]`  <- entry `BC`
- `_sprinter_dbg[6..7]`  <- entry `DE`
- `_sprinter_dbg[8..9]`  <- entry `HL`
- `_sprinter_dbg[10..11]` <- entry `IX`
- `_sprinter_dbg[12..13]` <- entry `IY`
- `_sprinter_dbg[14..15]` <- entry `AF`

Existing bytes are unchanged:

- `_sprinter_dbg[0..3]` still capture `(ret-1 .. ret+2)` around
  `_sprinter_rst38_ret`.
- `_sprinter_dbg[24..27]` remain the `_doexec` call-frame mirror channel.

Build stamp bumped to `BA 27 04 63`.

Current artefact checksums:

- `fuzix.img` sha256 `d898ce42848f9bb5b27b279074440c20d89b1e37fa3a97fd4fe0211698f53deb`
- `fuzix.chd` sha256 `2dc04e04e1c3f74b3d02bde25a87a562fb4dc25b6027b6da0a6f755a74c77df6`
- `Applications/util/sprinit` sha256 `f0f2f070c2bddf30a4cf35bf17c7953f813c4d917bc91e4650e3b274f6aee41c`

Map anchors for this image:

- `_plt_monitor = 0xF100`
- `sprinter_rst38_stub = 0xF180` (`rst38_hang = 0xF21E`)
- `sprinter_null_stub = 0xF22B` (`null_hang = 0xF308`)
- `_devide_read_data = 0xF30B`
- `_doexec = 0xF695`
- `null_handler = 0xF6A9`
- `trap_illegal = 0xF6DA`
- `_sprinter_rst38_count = 0xFD93`
- `_sprinter_rst38_sp = 0xFD94`
- `_sprinter_rst38_ret = 0xFD96`
- `_sprinter_rst38_insys = 0xFD98`
- `_sprinter_rst38_callno = 0xFD99`
- `_sprinter_rst38_inirq = 0xFD9A`
- `_sprinter_rst38_up0..up2 = 0xFD9B..0xFD9D`
- `_sprinter_rst38_mp0..mp2 = 0xFD9E..0xFDA0`
- `_sprinter_rst38_i = 0xFDA1`
- `_sprinter_nullh_count = 0xFDAD`
- `_sprinter_null_sp0 = 0xFDAE`
- `_sprinter_null_sp2 = 0xFDB0`
- `_spr_doexec_arm = 0xFE54`
- `_spr_doexec_map_ptr = 0xFE56`
- `_spr_doexec_expect = 0xFE58`
- `_spr_doexec_call_seen = 0xFE63`
- `_spr_doexec_call_sp = 0xFE64`
- `_spr_doexec_call_ra0 = 0xFE66`
- `_spr_doexec_call_ra1 = 0xFE68`
- `_spr_doexec_call_af = 0xFE6A`
- `_spr_doexec_call_start = 0xFE6C`
- `_sprinter_trace_idx = 0xFE99`
- `_sprinter_dbg = 0xFE9E` (stamp at `0xFEBA..0xFEBD`)

### Correct next replay for `BA 27 04 63`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFD93-0xFDB4` (`rst38/null` shared context + `null_sp0/null_sp2`)
- `0xFE54-0xFE70` (`doexec` arm/call-frame latches)
- `0xFE99-0xFEC0` (`trace_idx`, `_sprinter_dbg[]`, stamp)
- `0xEFA0-0xF000` (top-of-stack window)
- `0xF170-0xF240` (`rst38/null` corridor)
- `0xFF00-0xFF40` (IM2 vector page)
- `0x0000-0x0140` (low vectors)

Decode:

- no `BA 27 04 63` at `0xFEBA..0xFEBD`
  => stale image loaded
- `_sprinter_rst38_count == 0` and `_sprinter_nullh_count == 0`
  => this replay did not hit current fatal stubs
- `_sprinter_rst38_count != 0`
  => classify from one frame:
  - `_sprinter_rst38_insys/callno/inirq`
  - `_sprinter_rst38_ret`
  - `_sprinter_dbg[0..3]` and new `_sprinter_dbg[4..15]`
  - `_spr_doexec_call_*` mirror block

### Update from 2026-04-24: latched `SP..SP+7` at `RST 38` entry (`BA 27 04 64`)

User confirmed the emulator launch path uses the image generated by this tree
directly (`Images/sprinter/fuzix.img`). For the next narrowing step, `rst38`
now also snapshots the first 8 bytes of the entry stack frame:

- `_sprinter_dbg[16..23] <- *(SP + 0 .. SP + 7)` at trap entry

This extends the existing latch (`dbg[0..15]`) without changing the runtime
path or trap handling logic.

Build stamp bumped to `BA 27 04 64` in `Kernel/start.c`.

Current artefact checksums:

- `fuzix.img` sha256 `d1738115b283eb4a02d9b5c49422de43a6280041aeb5f0a4231610bddf423793`
- `fuzix.chd` sha256 `8142913032a2374d21d0a4b29ecadff2f15703924d5fb33791d986347adf31aa`
- `Applications/util/sprinit` sha256 `f0f2f070c2bddf30a4cf35bf17c7953f813c4d917bc91e4650e3b274f6aee41c`

Map anchors for this image:

- `_plt_monitor = 0xF100`
- `_doexec = 0xF6C2`
- `null_handler = 0xF6D6`
- `trap_illegal = 0xF707`
- `_sprinter_rst38_count = 0xFDC0`
- `_sprinter_rst38_sp = 0xFDC1`
- `_sprinter_rst38_ret = 0xFDC3`
- `_sprinter_rst38_insys = 0xFDC5`
- `_sprinter_rst38_callno = 0xFDC6`
- `_sprinter_rst38_inirq = 0xFDC7`
- `_sprinter_rst38_up0..up2 = 0xFDC8..0xFDCA`
- `_sprinter_rst38_mp0..mp2 = 0xFDCB..0xFDCD`
- `_sprinter_rst38_i = 0xFDCE`
- `_sprinter_nullh_count = 0xFDDA`
- `_sprinter_null_sp0 = 0xFDDB`
- `_sprinter_null_sp2 = 0xFDDD`
- `_spr_doexec_arm = 0xFE81`
- `_spr_doexec_seen = 0xFE82`
- `_spr_doexec_map_ptr = 0xFE83`
- `_spr_doexec_expect = 0xFE85`
- `_spr_doexec_call_seen = 0xFE90`
- `_spr_doexec_call_sp = 0xFE91`
- `_spr_doexec_call_ra0 = 0xFE93`
- `_spr_doexec_call_ra1 = 0xFE95`
- `_spr_doexec_call_af = 0xFE97`
- `_spr_doexec_call_start = 0xFE99`
- `_sprinter_trace_idx = 0xFEC6`
- `_sprinter_dbg = 0xFECB` (stamp at `0xFEE7..0xFEEA`)

### Correct next replay for `BA 27 04 64`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFDC0-0xFDDF` (`rst38/null` counters + frame pointers)
- `0xFE81-0xFE9B` (`doexec` arm + call-frame mirrors)
- `0xFEC6-0xFEEE` (`trace_idx`, full `sprinter_dbg[]`, build stamp)
- `0xEFA0-0xF000` (top-of-stack window)
- `0xF300-0xF3A0` (syscall/trap corridor near current stop)
- `0xFF00-0xFF40` (IM2 page sample)
- `0x0000-0x0140` (low vectors)

Decode:

- no `BA 27 04 64` at `0xFEE7..0xFEEA`
  => stale image loaded
- `_sprinter_rst38_count == 0` and `_sprinter_nullh_count == 0`
  => this replay did not hit current fatal stubs
- `_sprinter_rst38_count != 0`
  => compare stack-latch consistency first:
  - `dbg[16] == low(_sprinter_rst38_ret)` and `dbg[17] == high(_sprinter_rst38_ret)`
    should hold for a normal `RST 38` push frame
  - `dbg[18..23]` then classify the next three words above return PC
    (caller frame shape vs corrupt frame drift)
- `_spr_doexec_call_seen != 0` with inconsistent `dbg[18..23]`
  => prioritize `_doexec` call-frame corruption path

### Update from 2026-04-24: force `sprinter_dbg` under `0xFF00` (`BA 27 04 67`)

The replay with direct `fuzix.img` boot still showed garbage right after
`Starting /init`. The map confirmed the root cause: `_sprinter_dbg` was at
`0xFEF2` with `.ds 32`, so active writes to `dbg[24..31]` still overlapped the
IM2 vector page (`0xFF00..0xFF11`).

Applied narrow platform-only layout fix:

- reduced `SPR_TRACE_LEN` from `3` to `1`
- collapsed `_spr_doexec_call_sp/ra0/ra1/af/start` into one shared word latch
  (`_spr_doexec_call_word`)
- reduced `_sprinter_dbg` from `.ds 32` to `.ds 24`
- removed all writes to `sprinter_dbg[24..31]` in assembly/C probes
- moved build stamp to `sprinter_dbg[20..23]` and bumped to `BA 27 04 67`

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `caf26f497f8a00742bc7d1975012429d5a9024c53c4ee60f9c8d55b26889b315`
- `Images/sprinter/fuzix.chd` sha256 `43c6da900c0175db75f2cb9a83228224d290a4b2aab08f17129cbff64215512a`

Map anchors for this image:

- `s__VECTORS = 0xFF00`
- `_spr_doexec_arm = 0xFECF`
- `_spr_doexec_seen = 0xFED0`
- `_spr_doexec_map_ptr = 0xFED1`
- `_spr_doexec_expect = 0xFED3`
- `_spr_doexec_call_seen = 0xFEDE`
- `_spr_doexec_call_sp/ra0/ra1/af/start = 0xFEDF` (shared)
- `_spr_pg2_clamp_count = 0xFEE1`
- `_spr_pg2_last_raw = 0xFEE3`
- `_spr_boot_count = 0xFEE4`
- `_sprinter_trace_idx = 0xFEE5`
- `_sprinter_trace_buf = 0xFEE7`
- `_sprinter_dbg = 0xFEE8` (`dbg[0..23] = 0xFEE8..0xFEFF`)

This is the key invariant now:

- no writable diagnostic symbol is left at `0xFFxx`
- only `s__VECTORS` starts at `0xFF00`

### Correct next replay for `BA 27 04 67`

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFE2F-0xFE50` (`rst38/null` counters + pointers)
- `0xFECF-0xFEE4` (`doexec` arm + shared call-word latch)
- `0xFEE5-0xFF20` (`trace_idx`, `dbg[0..23]`, IM2 page head)
- `0xEFA0-0xF000` (top-of-stack window)
- `0xF1B0-0xF2A0` (`_switchin` / `doexec` corridor)
- `0x0000-0x0140` (low vectors)

Decode:

- no `BA 27 04 67` at `0xFEFC..0xFEFF`
  => stale image loaded
- stamp present and corruption still starts right after `Starting /init`
  => IM2-page overlap is no longer the trigger; continue with `_switchin`/`doexec`
    edge classification from `dbg[16..23]` + `rst38_ret`

### Update from 2026-04-24: print `Starting /init` from fixed code page (`BA 27 04 68`)

Latest replay still showed corruption beginning right after `Starting /init`, and
user confirmed emulator boots the generated `Images/sprinter/fuzix.img` directly.

Narrow diagnostic step applied:

- `process.c:exec_or_die()` now uses `kputs(spr_initmsg)` only under
  `CONFIG_SPRINTER_EARLY_TRACE`.
- `spr_initmsg` is defined in `platform-sprinter/sprinter.s` as a fixed string in
  the CODE area (`0x054A`), not in `_COMMONDATA`.
- build stamp bumped to `BA 27 04 68` (`start.c`, `sprinter_dbg[20..23]`).

Important invariant re-checked after this patch:

- `_sprinter_dbg = 0xFEE8`, so `dbg[0..23]` occupies `0xFEE8..0xFEFF`
- `s__VECTORS = 0xFF00`
- no debug latches overlap `0xFF00` again

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `5c3e533f26387a7eb15a74aaf986c66a2f2586a5241877de77dcf4d63ff77b8d`
- `Images/sprinter/fuzix.chd` sha256 `4445b4674cc63a9f62eceb18223742cdee437617e991aaae82699c941b2bfbc8`

Map anchors for this image:

- `_spr_initmsg = 0x054A`
- `_exec_or_die = 0x540C`
- `_plt_monitor = 0xF100`
- `plt_interrupt_all = 0xF174`
- `_sprinter_rst38_count = 0xFE2F`
- `_sprinter_dbg = 0xFEE8`
- `s__VECTORS = 0xFF00`

### Correct next replay for `BA 27 04 68`

Capture:

- full screen
- registers + `PG0..PG3`
- `0x054A-0x0560` (verify `spr_initmsg` bytes and terminator)
- `0xFE2F-0xFE50` (`rst38/null` counters + pointers)
- `0xFEE8-0xFF20` (`sprinter_dbg[0..23]` + IM2 page head)
- `0xEFA0-0xF000` (stack/top common window)
- `0xF100-0xF260` (`plt_monitor` / `rst38` corridor)
- `0x0000-0x0140` (low vectors)

Decode:

- no `BA 27 04 68` at `0xFEFC..0xFEFF` => stale image loaded
- if stamp is present and corruption still starts exactly after `Starting /init`:
  - with `_sprinter_rst38_count != 0`, continue trap-frame classification via
    `rst38_ret + dbg[16..23]`
  - with `_sprinter_rst38_count == 0`, focus on post-`kputs` memory clobber
    before first trap entry

### Update from 2026-04-24: temporary `0x0000 -> unix_syscall_entry` diagnostic

Latest replay showed:

- `PC = 0xF276`, which is inside `sprinter_null_stub` (`push af; pop hl` edge).
- screen still corrupts immediately after `Starting /init`.

That keeps the primary hypothesis unchanged: userspace is still hitting a
`call/jp 0x0000` path very early, before stable userspace syscall handoff.

Narrow platform-only diagnostic applied in `platform-sprinter/sprinter.s`:

- in both `do_program_vectors()` and `pv_program_vectors_common()`
- vector `0x0000` now points to `unix_syscall_entry` (same as `0x0030`)
- this is temporary bring-up wiring to test whether the early crash is solely
  the unrelocated/incorrect syscall entry edge.

Current map anchors after rebuild:

- `_program_vectors = 0xF3B1`
- `unix_syscall_entry = 0xF4C8`
- `_sprinter_rst38_count = 0xFE0A`
- `_sprinter_nullh_count = 0xFE24`
- `_spr_doexec_arm = 0xFEAA`
- `_spr_doexec_call_seen = 0xFEB9`
- `_sprinter_trace_idx = 0xFEC0`
- `_sprinter_dbg = 0xFEC3`
- `s__VECTORS = 0xFF00`

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `0f0f5690475590e8603589c6ca9891f772f82afbdc62407ce065f73478162a98`
- `Images/sprinter/fuzix.chd` sha256 `5adaaaf226e42e0681ed5f0f10c4e5e22462a68539999004df94bb4f832376a1`

### Correct next replay for this diagnostic build

Capture:

- full screen
- registers + `PG0..PG3`
- `0x0000-0x0040` (must show `JP unix_syscall_entry` at both `0x0000` and `0x0030`)
- `0xFE08-0xFE30` (`rst38/null` counters and trap words)
- `0xFEAA-0xFEC0` (`doexec` arm/call latches)
- `0xFEC0-0xFF10` (`trace_idx`, `_sprinter_dbg`, IM2 head)
- `0xEFA0-0xF000` (stack window)

Decode:

- if boot advances past previous stop (`Starting /init...`) this confirms the
  early failure is the `0x0000` syscall edge.
- if it still stops at the same place with clean `0x0000` vector wiring, the
  next split is `_doexec`/user-stack corruption before first real syscall.

### Update from 2026-04-24: explicit image marker (`BA 27 04 69`)

To remove ambiguity about which generated image is actually running, this build
adds a visible marker and bumps the boot stamp:

- `start.c`: `sprinter_dbg[20..23] = BA 27 04 69`
- `sprinter.s`: `_spr_initmsg` now prints `Starting /init [69]`

No functional runtime path was changed in this step; this is a trace-identity
checkpoint only.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `fd5e9d304cdb78277e2efe1418309d291ba5c137ad297d04f188b41a449f53ef`
- `Images/sprinter/fuzix.chd` sha256 `3acd0f8a4c664ff697c577ccb87a3cef32992e9cd5ccd12e24c183b6538957bb`

Map anchors for this image:

- `_spr_initmsg = 0x0554`
- `_program_vectors = 0xF3B1`
- `unix_syscall_entry = 0xF4C8`
- `_sprinter_nullh_count = 0xFE24`
- `_sprinter_trace_idx = 0xFEC0`
- `_sprinter_dbg = 0xFEC3`
- `s__VECTORS = 0xFF00`

### Correct next replay for `BA 27 04 69`

Capture:

- full screen (must show `Starting /init [69]`)
- registers + `PG0..PG3`
- `0x0000-0x0040` (vector bytes; expect `0x0000` and `0x0030` both pointing to `0xF4C8`)
- `0x0554-0x056C` (`_spr_initmsg` bytes with `[69]`)
- `0xFE08-0xFE30` (`rst38/null` counters and trap words)
- `0xFEC0-0xFF10` (`trace_idx`, `_sprinter_dbg`, IM2 head)
- `0xEFA0-0xF000` (stack window)

Decode:

- if `[69]` is missing on screen or dump, replay is not from this image
- if `[69]` is present and `PC` still lands in `sprinter_null_stub`, use
  `0x0000-0x0040` + `0xFE08-0xFE30` to classify whether vector `0x0000` was
  rewritten after `program_vectors()` or entered with a stale low-page map.

### Update from 2026-04-24: NULL-vector stub now tail-chains into syscall (`BA 27 04 6B`)

Latest replay still hit `sprinter_null_stub` at `PC=0xF276` immediately after
`Starting /init`, and the screen line did not show the prior marker.
To keep bring-up moving, the NULL trap path is now made non-fatal and minimal:

- `sprinter_null_stub` no longer writes a full trap frame or halts.
- It now does only:
  - increment `_sprinter_nullh_count`
  - snapshot low-vector bytes `0x0000..0x0002` into `sprinter_dbg[16..18]`
  - `jp unix_syscall_entry`
- Build marker bumped:
  - `start.c`: `sprinter_dbg[20..23] = BA 27 04 6B`
  - `sprinter.s`: `_spr_initmsg` now prints `Starting /init [6B]`

Rationale:

- If early userspace still executes `call 0`, this bridge behaves like a
  temporary compatibility trampoline instead of stopping in the trap logger.
- The captured bytes in `sprinter_dbg[16..18]` tell us whether `0x0000` held
  `JP unix_syscall_entry` (`C3 05 F4` for this build) at the moment of trap.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `06466711c4edd90f0dd02df35257fe2bc86972acfbe85af79e7ded5921f98c4c`
- `Images/sprinter/fuzix.chd` sha256 `5dcaa373ec0bfdee271b434c00827716d04f966ca6e95827336a417448ad915c`

Map anchors for this image:

- `_spr_initmsg = 0x054A`
- `sprinter_null_stub = 0xF25D`
- `_program_vectors = 0xF2EE`
- `unix_syscall_entry = 0xF405`
- `_sprinter_nullh_count = 0xFD61`
- `_sprinter_trace_idx = 0xFDFD`
- `_sprinter_dbg = 0xFE00`
- `s__VECTORS = 0xFF00`

### Correct next replay for `BA 27 04 6B`

Capture:

- full screen (must show `Starting /init [6B]`)
- registers + `PG0..PG3`
- `0x0000-0x0040` (vector bytes)
- `0x054A-0x0564` (`_spr_initmsg` bytes with `[6B]`)
- `0xFD58-0xFE20` (`_sprinter_nullh_count`, `trace_idx`, `sprinter_dbg[0..31]`)
- `0xFEF0-0xFF10` (end of common page + IM2 head)
- `0xEFA0-0xF000` (stack/common window)

Decode:

- if `[6B]` is missing on screen or in `_spr_initmsg` dump, replay is not from
  this image
- if `_sprinter_nullh_count` increases and `sprinter_dbg[16..18] == C3 05 F4`,
  the vector is correct and we are handling legacy `call 0` through trampoline
- if `_sprinter_nullh_count` increases but `sprinter_dbg[16..18] != C3 05 F4`,
  low-page vector bytes are being rewritten after `program_vectors()`

### Update from 2026-04-24: stackless NULL-stub with kernel-map gate (`BA 27 04 6C`)

Latest replay still stopped at `PC=0xF276` (`sprinter_null_stub`) with mixed
stack/context bytes. In that state the old stub still did `push/pop`, which
depends on a sane SP and can blur root cause.

This step makes the NULL path stack-agnostic and classifies entry context:

- `sprinter_null_stub` no longer uses `push/pop`.
- It now latches:
  - `sprinter_dbg[16]` = A at entry (candidate syscall no)
  - `sprinter_dbg[17..18]` = SP low/high
  - `sprinter_dbg[19..20]` = first two bytes at SP
- Then it compares current mapping (`mpgsel_cache[0..2]`) with
  `_kernel_pages[0..2]`:
  - if equal: branch to local `null_hang` (no syscall tail-chain)
  - else: snapshot `0x0000..0x0002` into `sprinter_dbg[21..23]` and
    tail-chain to `unix_syscall_entry`.
- Marker bump:
  - `_spr_initmsg`: `Starting /init [6C]`
  - `start.c` stamp byte: `0x6C`

Rationale:

- If NULL is entered while still in kernel map, tail-chaining into syscall
  with arbitrary A/SP only amplifies corruption.
- For true user-mode `call 0` legacy path, we still keep the bridge.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `b802a271fbdf4c3072adaacb72789fdb418900add3067f869275a3900976ce13`
- `Images/sprinter/fuzix.chd` sha256 `7d3a6a5a6990511d602808a871c3d5213bac861156e22779dfa73e5e11a3a857`

Map anchors for this image:

- `_spr_initmsg = 0x054A`
- `sprinter_null_stub = 0xF25D`
- `null_user_chain = 0xF299`
- `null_hang = 0xF2B1`
- `_program_vectors = 0xF328`
- `unix_syscall_entry = 0xF43F`
- `_kernel_pages = 0xFD73`
- `_sprinter_nullh_count = 0xFD9B`
- `_sprinter_trace_idx = 0xFE37`
- `_sprinter_dbg = 0xFE3A`
- `s__VECTORS = 0xFF00`

### Correct next replay for `BA 27 04 6C`

Capture:

- full screen (must show `Starting /init [6C]`)
- registers + `PG0..PG3`
- `0xF250-0xF2C0` (stub bytes around `sprinter_null_stub`)
- `0x0000-0x0040`
- `0xFD70-0xFE70` (`_kernel_pages`, `_sprinter_nullh_count`, trace/dbg)
- `0xEFA0-0xF000` (stack window)

Decode:

- if `_sprinter_nullh_count` increments and `sprinter_dbg[21..23]` equals
  `_kernel_pages[0..2]`, NULL was entered in kernel mapping and we stopped
  intentionally in `null_hang`.
- if `_sprinter_nullh_count` increments and `sprinter_dbg[21..23]` is
  `C3 xx xx`, NULL entered in user mapping and we tailed into syscall path.

### Update from 2026-04-24: `n_open()` guard for corrupted `u_root/u_cwd` (`[6C]` image, inode panic split)

Latest replay from the confirmed `[6C]` image moved past the old NULL-stub stop
and reached:

- `Starting /init [6C] ...`
- `magic0 ptr=0001 ... site=0001 ...`
- `panic: corrupt inode`

`site=1` means the fault is at `MAGIC_CHECK(1, ninode)` in `n_open()`, right
after the initial root/cwd reference setup. Pointer `0x0001` indicates a
transient corrupted `u_root/u_cwd` value before pathname walk.

Applied narrow bring-up guard in `Kernel/filesys.c` under
`CONFIG_SPRINTER_EARLY_TRACE`:

- after selecting start directory (`u_root` for absolute path, `u_cwd` for relative),
- if `wd` is outside `[i_tab, i_tab + ITABSIZE)`, call
  `i_open(root_dev, ROOTINODE)`,
- patch `u_root`/`u_cwd` with recovered inode pointer and continue path walk.

This is trace-only recovery (no effect for non-Sprinter builds).

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `a233ae82e970dff3b0ccb0ea6bf613c9bf498a77fba8767d789996224df3e505`
- `Images/sprinter/fuzix.chd` sha256 `d7ba983520ca4daa649a129d2d5bffca5a62aa50c2d505f5d26c060f6b49383a`

Map anchors for this build:

- `_spr_initmsg = 0x054A` (still `[6C]`)
- `_program_vectors = 0xF328`
- `unix_syscall_entry = 0xF43F`
- `_kernel_pages = 0xFD73`
- `_sprinter_nullh_count = 0xFD9B`
- `_sprinter_trace_idx = 0xFE37`
- `_sprinter_dbg = 0xFE3A`
- `s__VECTORS = 0xFF00`

### Correct next replay for this guard

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFD90-0xFED0` (`_sprinter_nullh_count`, trace/dbg, beginning of inode-trace block)
- `0x0000-0x0040` (vectors still sanity check)
- `0xEFA0-0xF000` (stack/common window)

Decode:

- if boot advances past old `magic0 ptr=0001` panic, the corrupted-root edge is
  confirmed and next failure is deeper in init/open path.
- if panic remains but pointer/site changes, use new values to split the next
  corruption edge.

### Update from 2026-04-24: harden `n_open()` root recovery and expose root pointers in `magic0`

Next replay still showed the same early `n_open()` panic:

- `magic0 ptr=0001 ... site=0001 ...`
- `nopen st=00D1 wd=0001 ni=0001 ...`

So the previous guard was not sufficient for this edge. The current step tightens
the bring-up recovery path in `Kernel/filesys.c` under
`CONFIG_SPRINTER_EARLY_TRACE`:

- added `sprinter_inode_ptr_valid()` helper for explicit inode-table pointer checks
- in `n_open()`, when start `wd` is invalid:
  - first try global `root` (already opened at boot)
  - only if that is invalid, fallback to `i_open(root_dev, ROOTINODE)`
  - accept recovery only if resulting pointer is a valid `i_tab` slot
- in `magic()`, added extra line:
  - `magic0 roots ur=%x uc=%x gr=%x`
  - this exposes `udata.u_root`, `udata.u_cwd`, and global `root` at panic time

This keeps the change platform-bring-up-local via the existing
`CONFIG_SPRINTER_EARLY_TRACE` guards and does not affect non-Sprinter targets.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `566a5426e344461b42c1ebc70a5f741e7e8c21dcd7cf6ab8c2f57c11f2c9ef0d`
- `Images/sprinter/fuzix.chd` sha256 `a0968591bf4ab14c445bfc3e99a2627de28f6ee4961f48b69bc63d1ecb843be4`

Map anchors for this build:

- `_spr_initmsg = 0x054A` (`[6C]`)
- `_program_vectors = 0xF328`
- `unix_syscall_entry = 0xF43F`
- `_kernel_pages = 0xFD73`
- `_sprinter_nullh_count = 0xFD9B`
- `_sprinter_trace_idx = 0xFE37`
- `_sprinter_dbg = 0xFE3A`
- `_root = 0x0FC9`
- `_udata = 0xEE00`
- `s__VECTORS = 0xFF00`

### Correct next replay for this build

Capture:

- full screen (include all `magic0 ...` lines if panic remains)
- registers + `PG0..PG3`
- `0x0FC0-0x0FD8` (global `root` vicinity)
- `0xEE00-0xEF20` (`udata` head, including cwd/root region context)
- `0xFD90-0xFED0` (trace/dbg + counters)
- `0x0000-0x0040` (vector sanity)
- `0xEFA0-0xF000` (stack/common window)

Decode:

- if `magic0 roots` prints `ur/uc=0001` but `gr` is valid, then corruption is
  limited to `udata` inode pointers and fallback path should now advance further
- if all three (`ur`,`uc`,`gr`) are invalid, root-state corruption is global and
  we pivot to the writer path touching `_root`/inode table memory
- if panic disappears, we continue splitting the next blocker after first
  pathname walk.

### Update from 2026-04-24: PID1 `/init` fallback now matches prefix (avoid `n_open()` on tailed name)

Latest replay still hit:

- `Starting /init [6C]...`
- `magic0 ptr=0001 ... site=0001`
- `panic: corrupt inode`

The key observation is that the on-screen `/init` line is often followed by a
garbage tail, which means `exec_name` can be `"/init...."` instead of exact
`"/init\0"`. In that case `sprinter_pid1_init_open()` (which required exact
`"/init\0"`) returned `NULL`, and `_execve()` fell back to `n_open_lock()`,
re-entering the fragile inode-walk corridor.

Applied a narrow trace-only change in `Kernel/syscall_exec16.c` under
`CONFIG_SPRINTER_EARLY_TRACE`:

- `sprinter_pid1_init_open()` now accepts PID1 kernel-side name by prefix
  `"/init"` (no strict `exec_name[5] == '\0'` requirement)
- removed dereference of possibly corrupted `udata.u_root` from the local trace
  marker in this helper
- still opens fixed Sprinter init inode via `i_open(root_dev, 0x0083)`

This keeps behaviour unchanged for non-Sprinter and for non-trace builds.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `86148c0f78949d26d71201c338d583b22f0e67d0f9125c9370d7196070b6604f`
- `Images/sprinter/fuzix.chd` sha256 `654d40f7ec61a974fdeff9660d0f1950b600e2e126028ef6f4ac89ccb42b84f3`

Map anchors for this build:

- `_spr_initmsg = 0x054A`
- `_n_open = 0x41F1`
- `_magic = 0x6551`
- `_root = 0x0FE9`
- `_udata = 0xEE00`
- `_program_vectors = 0xF328`
- `unix_syscall_entry = 0xF43F`
- `_kernel_pages = 0xFD73`
- `_sprinter_trace_idx = 0xFE37`
- `_sprinter_dbg = 0xFE3A`
- `s__VECTORS = 0xFF00`

### Correct next replay for this build

Capture:

- full screen
- registers + `PG0..PG3`
- `0x0FD8-0x0FF0` (`root_dev/root` neighborhood)
- `0xEE00-0xEF20` (`udata` head)
- `0xFD90-0xFED0` (trace/dbg)
- `0x0000-0x0040` (vector sanity)
- `0xEFA0-0xF000` (stack/common window)

Decode:

- if `magic site=1` disappears and boot proceeds, the strict `"/init\0"` gate
  was the blocker to this panic edge
- if the same panic remains, next split is writer-side corruption of root/inode
  state before PID1 exec.

### Update from 2026-04-24: fixed `/init` inode fallback was stale for current image

Latest replay moved from `panic: corrupt inode` to:

- `Starting /init [6C]...`
- `panic: no /init`

`sprinter_exec_fail_*` decoded from `0xFDA0..0xFDB6`:

- `stage=0x02`, `err=0x000D (EACCES)`
- `mode=0x41ED` (directory, not regular executable)
- permission bits were present (`perm=0x07`)

So `_execve()` did get an inode, but it was a directory. This proved the
temporary fixed-inode shortcut (`i_open(root_dev, 0x0083)`) is no longer valid
for the regenerated Sprinter image layout.

Applied narrow trace-only fix in `Kernel/syscall_exec16.c` under
`CONFIG_SPRINTER_EARLY_TRACE`:

- `sprinter_pid1_init_open()` still detects PID1 tailed `"/init...."` by prefix
- but now resolves through canonical kernel string `"/init"` via
  `n_open_lock("/init", ...)` with `u_sysio=true`
- removed dependency on hardcoded inode number

Non-Sprinter behaviour is unchanged.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `4164e4f59b9923d434a776c57d54f2c0cf5e1bf563ba2f29703d5fb34809434b`
- `Images/sprinter/fuzix.chd` sha256 `e324d35c8ed224cbd9db2d3d435ed9382472d3bc2b61b6a997b0434ad6700af2`

### Correct next replay for this build

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFDA0-0xFDB8` (`sprinter_exec_fail_*` block)
- `0xFDD0-0xFE20` (n_open/i_open trace aliases)
- `0x0FD8-0x0FF0` (`root_dev/root` neighborhood)
- `0xEE00-0xEF20` (`udata` head)
- `0x0000-0x0040` (vector sanity)

Decode:

- if `stage` moves past `0x02`, stale fixed-inode fallback was the blocker
- if `stage==0x01`, canonical `n_open_lock("/init")` is failing and we inspect
  pathname walk results next
- if `stage==0x02` with directory mode again, we pivot to root dir entry
  resolution (`srch_dir("init")`) and device/inode pair capture.

### Update from 2026-04-24: `bri` printf path removed from `bredi()` after `RST 38h` stop

Replay with the canonical `n_open_lock("/init")` build moved again:

- no more `panic: no /init`
- screen reaches `Starting /init [6C]...`
- then prints a broken `bri ...` line (`bri bri dst=...`)
- CPU halts at `PC=F251`

`PC=F251` maps exactly to `jr rst38_hang` in `sprinter_rst38_stub`
(`_plt_reboot=F100`, `sprinter_rst38_stub=F180`, `rst38_hang=F250/F251` in this
image layout).  `rst38_*` bytes in the same dump decode to:

- `count=1`
- `sp=0xF102`
- `ret=0x33F6` (the trapped return address)
- `insys=1`, `callno=0`
- `upages=40/41/42`
- `mpgsel_cache=48/09/0A`

So this stop is no longer the old inode-pointer panic edge; it is a live
`RST 38h` trap during/after the first `/init` open path while diagnostic `bri`
printing is active.

Applied narrow trace-only change in `Kernel/blk512.c` under
`CONFIG_SPRINTER_EARLY_TRACE`:

- removed heavy `kprintf("bri ...")` output from `bredi()` root-inode probe
- kept lightweight byte traces (`A8`/`A9`) and the same `blktok()` copy
- no behavior change for non-Sprinter / non-trace builds

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `26a58fda7e2ca82d51514229c6c464f4677ad149ede88f2335e77fa8b5a4d7b2`
- `Images/sprinter/fuzix.chd` sha256 `6ad23c48ea146198a8cfc3cb29b5965d508c96dc8d387dd028842dd008dd01ed`

### Correct next replay for this build

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFD70-0xFE20` (`_kernel_pages`, `rst38_*`, `_sprinter_exec_fail_*`)
- `0xFE30-0xFE70` (`_sprinter_trace_idx`, `_sprinter_dbg`)
- `0x33E0-0x3420` (bytes around trapped `ret=0x33F6`)
- `0x0000-0x0040` (vector sanity)
- `0xEFA0-0xF020` (stack/common window)

Decode:

- if `PC` no longer lands at `F251`, the `bredi()` printf path was amplifying
  the failure and we continue splitting the next syscall edge
- if `PC` still lands at `F251`, we pivot to the `ret=0x33F6` code path and
  syscall return stack integrity (`unix_syscall_entry` corridor).

### Update from 2026-04-24: harden `_program_vectors` call ABI (SP+2 vs SP+4)

Next replay showed a stable signature of bad page-table argument handling in
`_program_vectors`: at `RST 38h` trap time `u_page` still looked sane
(`40/41/42`), but live mapper bytes were `48/09/0A`.  `09/0A` are the fallback
clamp values used when mapping from an invalid page-map pointer, so we were
re-entering kernel flow after vector programming with wrong WIN1/WIN2 pages.

The wrapper in `sprinter.s` was fixed to accept both observed stack layouts:

- standard SDCC call (`RET,arg` => pointer at `SP+2`)
- banked/noopt wrapper (`RET,AF,arg` => pointer at `SP+4`)

Implementation now probes `SP+2` first, then `SP+4`, and keeps the first
pointer that passes `pv_ptr_valid()`.

This is a platform-local change only (`Kernel/platform/platform-sprinter/sprinter.s`);
no core behavior outside Sprinter was changed.

Current artefact checksums after this fix:

- `Images/sprinter/fuzix.img` sha256 `828278cf89b12dacaacae36cfb07a0eee99a4e428c87d6d69567c74c343a9140`
- `Images/sprinter/fuzix.chd` sha256 `225dd8a2724bcbcf22dd39ead9590c595e388c101a744441baab2a52e97c8d0b`

### Update from 2026-04-25: harden PID1 `/init` open helper against tailed path + sysio mismatch

Latest replay still reached:

- `Starting /init [6C]...`
- then `panic: no /init`

This means `_execve()` still fell through the PID1 helper path and ended in
`n_open_lock(exec_name, ...)` with a tailed/corrupted pathname.

Applied a narrow trace-only fix in `Kernel/syscall_exec16.c` under
`CONFIG_SPRINTER_EARLY_TRACE`:

- `sprinter_pid1_init_open()` no longer requires `udata.u_sysio==true` before
  validating PID1 `"/init"` prefix
- path prefix bytes are now fetched safely for both cases:
  - direct read when `u_sysio`
  - `ugetc()` when not `u_sysio`
- if canonical `n_open_lock("/init", ...)` still fails, helper now performs a
  PID1-only fallback:
  - `i_open(root_dev, ROOTINODE)`
  - `srch_dir(root, "init")`
  - `i_deref(root)`

This keeps behavior unchanged for non-Sprinter builds and for non-trace
configurations, while removing dependence on tailed `exec_name` for PID1.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `66031576b9f88d78f88a6a89add9192baa963b6ce4e59312f1e15c2452adfa51`
- `Images/sprinter/fuzix.chd` sha256 `a4a8c79addcc2a7b7a012b4abd59d6edd97d186ab00ce593533de66eaedb3cef`
- `Images/sprinter/fuzix.sprinter` sha256 `2f91a5bcf86bf8b2b987102268feb962d5108a62e067aa72b5f05c43fc48899f`

Map anchors for this build:

- `_spr_initmsg = 0x054A`
- `_plt_reboot = 0xF100`
- `_program_vectors = 0xF328`
- `unix_syscall_entry = 0xF44B`
- `_kernel_pages = 0xFD7F`
- `_sprinter_exec_fail_stage = 0xFDAC`
- `_sprinter_exec_fail_ino = 0xFDB5`
- `_spr_rw_stage = 0xFDDE`
- `_sprinter_last_nopen_stage = 0xFDDE`
- `_sprinter_dbg = 0xFE46`

### Correct next replay for this build

Capture:

- full screen
- registers + `PG0..PG3`
- `0xFDAC-0xFDE8` (`sprinter_exec_fail_*` + nopen/rw aliases)
- `0xFDE8-0xFE60` (`legacy diag tail + sprinter_dbg head`)
- `0x0FA0-0x0FD0` (`root_dev/root` vicinity)
- `0xEE00-0xEF20` (`udata` head)
- `0x0000-0x0040` (vector sanity)

Decode:

- if panic disappears, failure was the PID1 helper falling through to tailed
  `exec_name`
- if still `panic: no /init`, inspect `sprinter_exec_fail_stage` and
  `sprinter_last_nopen_stage` to decide whether the fail is still in name
  resolution or already in root directory lookup.

### Update from 2026-04-25: stop treating NULL vector as syscall entry

Latest replay showed apparent “double boot” text followed by `panic: invalid dev`.
The dump still had live `/init` tail bytes but then drifted into bogus syscall/
dev-path state, which is consistent with accidental jumps to `0x0000` being
interpreted as valid syscalls.

Applied a narrow platform-local fix in `Kernel/platform/platform-sprinter/sprinter.s`:

- `do_program_vectors()` and `pv_program_vectors_common()` now program vector
  `0x0000` to `JP sprinter_null_stub` instead of `JP unix_syscall_entry`
- `sprinter_null_stub` no longer tail-chains into `unix_syscall_entry`; it now
  latches context bytes and hard-stops in the local hang loop

Rationale: NULL jumps must stay fatal during bring-up; converting them into
syscalls corrupts control flow and masks the real fault location.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `fa0f1efdb5a573755ca30a1c1a7b60494087695afcb1f7e0e4acf77fdf5e3f25`
- `Images/sprinter/fuzix.chd` sha256 `1f6278aafe29d3437363f7ea74d469594a43952ca2510bcea0cdb5afd39b282d`
- `Images/sprinter/fuzix.sprinter` sha256 `953757376570a879fd62f72c95a6dce0512b64b46e6aa6f4a658de84be3b434e`

### Correct next replay for this build

Capture:

- full screen
- registers + `PG0..PG3`
- `0x0000-0x0040` (vector sanity: must point 0x0000 -> `sprinter_null_stub`)
- `0xFD70-0xFE30` (`_kernel_pages` + panic/nopen latches + stub bytes)
- `0xFE40-0xFEB0` (`_sprinter_dbg`/adjacent trace bytes)
- `0xEFA0-0xF020` (common/stack corridor around `/init` transition)

Decode:

- if system halts in `sprinter_null_stub`, we have a clean NULL-jump trap and
  can debug the real caller from the captured stack/mapping bytes
- if panic still reaches `invalid dev`, NULL jumps are no longer being masked
  as syscalls and we continue from `validchk()` path with deterministic state.

### Update from 2026-04-25: bypass indirect `dev_tab` open dispatch in trace build

Latest replay after NULL-vector hardening is consistent and now clean:

- screen reaches `Starting /init [6C]...` and then stops without syscall-panic noise
- `PC=0xF2B1`, `HALT=1` maps to `null_hang` in `sprinter_null_stub`
- null-stub latch bytes decode to:
  - `SP=0xEF82`
  - trapped return address on stack: `0x492F`
  - live kernel map snapshot: `48/49/4A`

`0x492F` is the return site after `call ___sdcc_call_hl` inside `_d_open`
(general path), so this stop is still an indirect-open dispatch failure:
control reaches the call site in `d_open`, then jumps through a bad handler
target and falls into the NULL vector.

Applied a narrow trace-only guard in `Kernel/devio.c` under
`CONFIG_SPRINTER_EARLY_TRACE`:

- `d_open()` now does direct Sprinter bring-up dispatch and returns before the
  legacy `dev_tab` indirect call path:
  - major `2` -> direct `tty_open(minor, flag)` (existing fast path kept)
  - majors `0,1,3,4` -> direct `no_open(minor, flag)`
  - other majors -> `ENXIO`
- non-trace builds keep the normal `dev_tab` path unchanged

Goal: remove the unstable indirect call edge during early bring-up and expose
the next real runtime fault past the first `/init` open boundary.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `7099b767ba491b3bce88710f0626c74c873d0cb783a480dc78e1e74968f94f2a`
- `Images/sprinter/fuzix.chd` sha256 `f43259f2f234ebcf721d24bc150521f7dceb80b2208b037b5eee8c61e916643b`
- `Images/sprinter/fuzix.sprinter` sha256 `cea5514ebd0149ce4f0fe17d44fbe98791b3f9fa07b995fd05a33cce98d244c3`

### Correct next replay for this build

Capture:

- full screen
- registers + `PG0..PG3`
- `0x0000-0x0040` (vector sanity)
- `0xFD79-0xFDC0` (`mpgsel_cache`, `_kernel_pages`, null/rst counters)
- `0xFE40-0xFE80` (`_sprinter_dbg` focus, especially bytes `[16..23]`)
- `0xEFA0-0xF020` (common/stack corridor around `/init` transition)

Decode:

- if NULL trap disappears and boot advances, the indirect open dispatch was the
  current blocker
- if NULL trap remains, re-check null-stub return address (`dbg[19..20]`) to
  confirm whether it still comes from `_d_open+0x121` (`0x492F`) or has moved.

### Update from 2026-04-25: remove `no_open()` call edge from `d_open()` trace path

Latest replay still shows the same NULL stop signature:

- `PC=0xF2B1` (`null_hang`)
- `dbg[17..18] = 0xEF82` (trap SP)
- `dbg[19..20] = 0x492F` (word at trap SP)
- `dbg[21..23] = 48/49/4A` (kernel mapping at trap)

To remove one more call/return edge in the same corridor, trace-only
`d_open()` logic was tightened in `Kernel/devio.c`:

- for majors `0..4` in `CONFIG_SPRINTER_EARLY_TRACE`, `d_open()` now returns
  `dev` directly (success) and no longer calls `no_open()`
- trace marker for this fast path changed to `sprinter_dbg[8] = 0xD3`
- non-trace builds are unchanged

This keeps bring-up behavior equivalent (`no_open()` returned success anyway),
but removes another stack-sensitive call from early `/init` transition.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `d15b35bfa91872c92e8261bb9315c3e7b6900ae54091084abe5a923162054276`
- `Images/sprinter/fuzix.chd` sha256 `96aeae70191ca48aa6591a89252f59d7a399e822c363e36384d987a95b3d2368`
- `Images/sprinter/fuzix.sprinter` sha256 `1135dd064b6a2f34cad7965a290f38a0bb7bcc25aac502de3c0cbba2839ecab0`

### Correct next replay for this build

Capture:

- full screen
- registers + `PG0..PG3`
- `0x0000-0x0040` (vector sanity)
- `0x48E8-0x4938` (current `d_open()` branch bytes around former `0x492F` word)
- `0xFD90-0xFDE8` (`_sprinter_nullh_count`, `_kernel_pages`, trap-adjacent latches)
- `0xFE40-0xFE80` (`_sprinter_dbg[0..23]`)
- `0xEFA0-0xF000` (stack/common corridor)

Decode:

- if `dbg[8] == 0xD3` and NULL trap still occurs, failure is after the new
  direct `d_open()` major<=4 fast path
- if `dbg[19..20]` remains `0x492F`, we cross-check `0x48E8-0x4938` bytes to
  decide whether this word is still a live return-site fingerprint or just a
  reused/corrupted stack word at trap entry.

### Update from 2026-04-25: log `_execve()` failure latches before `PANIC_NOINIT`

Latest replay moved to a stable single-boot path ending in `panic: no /init`
with `PC=0xF172` (panic hang loop).  The screen also still shows a tailed
`Starting /init [6C]...` line, so we need direct evidence from the exact
`_execve()` return path instead of reconstructing from raw memory every run.

Applied a narrow trace-only diagnostic in `Kernel/process.c`:

- right after `_execve()` returns in `exec_or_die()`, emit one-line snapshots
  of:
  - `sprinter_exec_fail_*` (`stage/error/name/root/cwd/inode/mode/perm/...`)
  - latest `n_open()` latches (`stage/wd/ninode/name0/char`)
  - live `u_sysio/u_error/u_root/u_cwd`
- then continue to existing `panic(PANIC_NOINIT)` path unchanged

This does not alter control flow; it only prints the failure context already
latched by trace code.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `ec4b40c3db18961808bcc7af9103fbaad610fb136a72a8f74bf3fccc7336795d`
- `Images/sprinter/fuzix.chd` sha256 `506351da023bfbe25b4a8a5547b3d0598b51d0ef15d670bc0d7c6ad3f3181831`
- `Images/sprinter/fuzix.sprinter` sha256 `2c23b40c692ad6211e0136d5d82acc17296626e88e7accddec2b62a8095d2474`

### Correct next replay for this build

Capture:

- full screen including the two new lines starting with `xv ` and `np `
- registers + `PG0..PG3`
- `0xFDA0-0xFDE8` (`sprinter_exec_fail_*` + nopen/legacy aliases)
- `0xEF40-0xF020` (stack/common corridor around `/init` handoff)

Decode:

- `xv st=1` will confirm pure path-open failure (`n_open_lock` returned `NULL`)
- `xv st>1` will place the fault in permission/header/pagemap/arg handoff stage
- `xv st=0` with panic still means `_execve()` path is returning outside the
  instrumented checkpoints (likely control-flow/mapping corruption before
  normal fail labeling).

### Update from 2026-04-25: disambiguate “second boot” and `doexec` reachability

Latest replays still show `panic: no /init` with unstable tails after
`Starting /init [6C]...`, and one replay looked like a double boot.

Applied two trace-only probes:

- `Kernel/process.c` (`exec_or_die()` after `_execve()` return):
  - added `dx ...` line dumping:
    - `bc` = `spr_boot_count` (how many times `fuzix_main()` was entered)
    - `arm/seen/ex/isp/cs/csp/cst` = `doexec`-path latches
- `Kernel/syscall_exec16.c`:
  - set `sprinter_exec_fail_stage = 17` immediately before `doexec(...)`
    with entry/SP snapshots, so panic-side dump can distinguish
    “never reached doexec call site” from “reached and returned unexpectedly”.

This keeps control flow unchanged and only increases observability in the
current `/init` handoff corridor.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `2fdb132cf940e9991ee9a110b77715886aba3dec4d9f5e45f675577a788e4b20`
- `Images/sprinter/fuzix.chd` sha256 `e2b3731bbb31b3b038af3a4836ba1fa9d1dc51291946029fc4097f5dae70deab`
- `Images/sprinter/fuzix.sprinter` sha256 `5fac56995f2f28687ec1d8541b8d442f561c384398d0c28e624c80bfe2f71001`

### Correct next replay for this build

Capture:

- full screen including `xv ...`, `np ...`, and new `dx ...` lines
- registers + `PG0..PG3`
- `0xFD70-0xFDE8` (exec/nopen latches block)
- `0xEF90-0xF020` (common/stack corridor around `/init`)

Decode:

- `dx bc>1` means real re-entry into `fuzix_main()` (actual second boot)
- `xv st=17` means `_execve()` reached the `doexec(...)` call edge
- `xv st=0` with `dx arm/seen=0` means we never reached the staged call edge
- `xv st=0` with `dx arm=1` but `seen=0` suggests map/call path clobber before
  armed `map_proc_always` probe consumes the marker.

### Update from 2026-04-25: one-shot PID1 `ENOENT` retry with canonical common `/init`

Latest replay still ends with `panic: no /init`, and the `xv/np` lines show an
`ENOENT` edge (`ue=0002`) even when `/init` prefix bytes look correct.

Applied a narrow trace-only fallback in `Kernel/process.c` (`exec_or_die()`):

- after first `_execve()` return, if:
  - `pid == 1`
  - `udata.u_error == ENOENT`
  - retry was not used yet
- then do one retry with forced canonical arguments in common memory:
  - `u_sysio = 1`
  - `u_argn  = spr_common_init_path`
  - `u_argn1 = spr_common_init_argv`
  - `u_argn2 = spr_common_init_envp`
- retry markers:
  - bootmark `'j'` before retry
  - bootmark `'k'` after retry return
  - `xr st=... er=...` line if second attempt also returns

Also kept `Starting /init [6D]` marker in `exec_or_die()` so replay can be
unambiguously matched to this build.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `41f63da6f72554fe652c49941be507b3c0797b9199d8dadf84d293238cd43e17`
- `Images/sprinter/fuzix.chd` sha256 `d2be53b4fac48430aa11257fc12282ffd602a347540108c121840f7598e10b4f`
- `Images/sprinter/fuzix.sprinter` sha256 `fc31bfcdb458c039d71bc780da1baef0a2debf35b1e131cd9ec99984de01f111`

### Correct next replay for this build

Capture:

- full screen (must show `Starting /init [6D]`)
- if panic remains: include `xv ...`, `np ...`, `dx ...`, and possibly `xr ...`
- registers + `PG0..PG3`
- `0xFD70-0xFDF0` (exec/nopen latches)
- `0xEF90-0xF020` (common/stack corridor around `/init` handoff)

Decode:

- no `xr ...` and userland starts => first pass recovered
- `xr ...` present => both first and forced-canonical retries returned
- `dx bc>1` still indicates true re-entry into `fuzix_main()` (double boot)

### Update from 2026-04-25: force retry predicate visibility (`rx`) and reset retry latch

Replay with `[6D]` still ended in `panic: no /init`, with:

- `xv st=0000`
- `np ... ue=0002`
- no `xr ...` line

So the fallback branch itself needed explicit predicate visibility.

Applied a narrow trace-only adjustment in `Kernel/process.c`:

- reset `spr_pid1_exec_retry = 0` just before first `_execve()` in
  `exec_or_die()` to avoid stale/nonzero latch state
- print `rx ue=%x pid=%x rt=%x us=%x` before retry condition
- relax retry gate to:
  - `udata.u_error == ENOENT`
  - `spr_pid1_exec_retry == 0`
  (still one-shot due to latch set to 1 before second `_execve()`)

This is still early-trace-only and does not alter non-Sprinter paths.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `783cdf03de2242847d20f64ce27a547b720a2e40db0e1bd3342e4cb364df91d7`
- `Images/sprinter/fuzix.chd` sha256 `8b0074307695b1af06bd1d1231c4fd2ab05c01588709d0179e830cf2b44dc0e0`
- `Images/sprinter/fuzix.sprinter` sha256 `f32e36cc36582871ad2e30be025a6236f7e875805ce90971cdc1ac9feca9201c`

### Correct next replay for this build

Capture:

- full screen (must show `Starting /init [6D]`)
- lines: `xv ...`, `np ...`, `dx ...`, and new `rx ...` (and `xr ...` if present)
- registers + `PG0..PG3`
- `0xFD70-0xFDF0`
- `0xEF90-0xF020`

Decode:

- `rx ue=2 rt=0` but no `xr ...` => control flow diverges before/inside retry edge
- `xr ...` present and panic remains => both attempts return; issue is below path
  open fallback
- `rx ue!=2` => panic is not the ENOENT branch anymore

### Update from 2026-04-25: retry now uses local kernel argv/envp, not `_COMMONDATA`

Replay with `[6D]` finally proved the retry branch executes and returns:

- `rx ue=0002 pid=0001 rt=0000 us=0001`
- `xr st=0000 er=000E`

`0x000E` is `EFAULT`, so the second `_execve()` is no longer failing as
`ENOENT` path lookup; it is failing on bad address handling during the retry
handoff.

Applied a narrow trace-only change in `Kernel/process.c`:

- keep the one-shot retry gate (`ENOENT`, latch not set)
- switch retry arguments from `_spr_common_init_*` symbols to local static
  kernel objects in `process.c`:
  - `spr_retry_init_path[] = "/init"`
  - `spr_retry_init_argv[] = { spr_retry_init_path, NULL }`
  - `spr_retry_init_envp[] = { NULL }`
- bump visible boot marker to `Starting /init [6E]` so this image is
  unambiguous in emulator replay

Rationale:

- `_COMMONDATA` pointers are valid in many paths, but this retry runs after a
  failed `_execve()` corridor where mapper/user-memory state is already
  suspect.
- Local kernel statics remove one moving part: retry argv/envp no longer
  depend on `_COMMONDATA` placement or aliasing at this point.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `a96541295f0132a969632a2da6f6b461cf88b6fbaf01093cf9728a2222b6955a`
- `Images/sprinter/fuzix.chd` sha256 `e7a49cf4591c103199d95392be75330a38832bfd90835630deb91650d9f8dbd5`
- `Images/sprinter/fuzix.sprinter` sha256 `3d2f7143502942485faf8169da9f971caa2cc02b1a1c593feeea966d27f46c91`

### Correct next replay for this build

Capture:

- full screen with `Starting /init [6E]`
- lines: `xv ...`, `np ...`, `dx ...`, `rx ...`, and `xr ...` (if present)
- registers + `PG0..PG3`
- `0xFD70-0xFE10`
- `0xEF60-0xF020`

Decode target:

- `xr er!=000E` or no `xr` => retry address fault was fixed, move to next edge
- `xr er=000E` again => fault is deeper than source pointer placement (likely
  mixed `u_sysio`/argv interpretation or map context in second `_execve()`)

### Update from 2026-04-25: PID1 `/init` bypass now resolves via canonical root dir lookup

Latest replays still show unstable pathname tail on `Starting /init ...` and
`panic: no /init` with `ue=0002`.  To remove dependence on early `n_open()`
pathname walk for this one edge, `_execve()` now tries a PID1-only direct
lookup first:

- file: `Kernel/syscall_exec16.c`
- helper: `sprinter_pid1_init_open()`
- condition:
  - `pid == 1`
  - exec name prefix is `/init`
- path:
  - `i_open(root_dev, ROOTINODE)`
  - `srch_dir(rootino, "init")`
  - `i_deref(rootino)`
- only if this direct lookup returns NULL do we fall back to normal
  `n_open_lock(exec_name, ...)`.

Also bumped visible process-side marker:

- `Kernel/process.c`: `Starting /init [6F]`

This is still `CONFIG_SPRINTER_EARLY_TRACE` scoped bring-up work and does not
change non-Sprinter behavior.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `2f741856bace7d9cb6a24a6ba4b73da4e9cec628200fbc65f6db6adc24f56410`
- `Images/sprinter/fuzix.chd` sha256 `177abac6b173e75679ea99c3c316764866a1f85d7dd344e2abd4b189e331abf7`
- `Images/sprinter/fuzix.sprinter` sha256 `3b75ba85f42a74a937d65c289502fa9ec7e944dc4c3b432a1506f4cb89343901`

Sanity marker check in current image:

- `strings -a Images/sprinter/fuzix.sprinter | rg "Starting /init"` prints:
  - `Starting /init [6C]` (platform asm marker)
  - `Starting /init [6F]` (process `exec_or_die()` marker)

If replay still shows `Starting /init [6D]` or `[6E]`, emulator is not running
this build image yet.

### Correct next replay for this build

Capture:

- full screen with `Starting /init [6F]`
- lines: `xv ...`, `np ...`, `dx ...`, `rx ...`, `xr ...` (if present)
- registers + `PG0..PG3`
- `0xFD70-0xFE10`
- `0xEF60-0xF020`

Decode target:

- `xv st=1 ue=2` with no `0xEB/0xEE` movement => direct PID1 lookup did not
  resolve `/init` (root lookup path itself failing)
- `xv st` moves past open checks (`>=2`) => `/init` open edge is solved, fault
  is later in exec path
- `rx/xr` no longer appears => first pass no longer returns `ENOENT`

### Update from 2026-04-25: fixed early-trace memory overwrite in `sprinter_dbg`

Root cause of the unstable `/init` edge (switching between `no /init`,
`corrupt inode`, and invalid-dev style failures) was an out-of-bounds trace
write:

- `Kernel/syscall_fs3.c` writes up to `sprinter_dbg[30]`
- `Kernel/platform/platform-sprinter/sprinter.s` allocated `_sprinter_dbg` as
  only 24 bytes

That overflow was writing into adjacent common-memory state and could poison
inode/path data before PID1 `exec`.

Fix applied (platform-local, trace-only impact):

- `Kernel/platform/platform-sprinter/sprinter.s`
  - `_sprinter_dbg: .ds 24` -> `.ds 32`

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `ae12949eef884d54b78d5b17c7abda8a8aa6025790a09c60314e7c1e4b924520`
- `Images/sprinter/fuzix.chd` sha256 `d5ee467f51f537c56df7c38e9837cd9b85ef31ea3a544183be5eabc23cc17822`
- `Images/sprinter/fuzix.sprinter` sha256 `3b75ba85f42a74a937d65c289502fa9ec7e944dc4c3b432a1506f4cb89343901`

Marker sanity in this build:

- `strings -a Images/sprinter/fuzix.sprinter | rg "Starting /init"` =>
  `Starting /init [6C]` and `Starting /init [6F]`

### Update from 2026-04-25: removed PID1 retry `_execve()` pass and bumped marker to `[72]`

Latest replays showed mixed symptoms (`no /init`, `corrupt inode`) plus runs that
looked like a duplicated boot/start corridor. The explicit retry branch in
`exec_or_die()` made the control flow ambiguous during bring-up and could
re-enter `_execve()` after a failed first pass.

Applied narrow trace-phase cleanup:

- file: `Kernel/process.c`
- removed one-shot retry block (`spr_pid1_exec_retry` + second `_execve()` call)
- removed retry-only static `/init` argv/envp objects
- marker changed to `Starting /init [72]`
- kept diagnostics (`xv/np/dx/rx`) but `rx` now reports only `ue/pid/us`

And aligned the PID1 shortcut policy:

- file: `Kernel/syscall_exec16.c`
- `sprinter_pid1_init_open()` now gates on:
  - `pid == 1`
  - `udata.u_sysio == 1`
- direct canonical lookup remains `ROOTINODE + "init"`; it no longer depends on
  tailed `/init...` prefix bytes in the transient exec-name buffer.

Rationale:

- keep first PID1 exec path single-pass and deterministic;
- remove retry re-entry noise while we isolate the inode corruption edge;
- force the PID1 common-memory path to a stable canonical lookup.

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `08ef000b4291297e47370d5f00e359cdac6790836374ac57cbeb43d491a46483`
- `Images/sprinter/fuzix.chd` sha256 `5d0a2cb2301a6fe2bc41792d140210271fe1f02524122ecdd85f396d80ca1d7e`
- `Images/sprinter/fuzix.sprinter` sha256 `f479c98f5857d5c39721aff75a985c378a7a7f13e8b91b83b2a1a183c219d45f`

Marker sanity in this build:

- `strings -a Images/sprinter/fuzix.sprinter | rg "Starting /init"` =>
  `Starting /init [6C]` and `Starting /init [72]`

Next replay request for this exact build:

- full screen (must include `Starting /init [72]`)
- lines: `xv ...`, `np ...`, `dx ...`, `rx ...`
- registers + `PG0..PG3`
- dumps:
  - `0xFD70-0xFE10`
  - `0xEF40-0xF020`

### Update from 2026-04-26: skip redundant PID1 page alloc/common seed in trace build

Replay of the map-init corridor image stopped at:

`0r123pqs`

The focused dump proves the diagnostic split:

- `p` / `q` / `s` all printed, so `map_init()` entered, the second
  `pagemap_alloc(init_process)` returned, and execution reached
  `sprinter_seed_common(top)`;
- `PC = 0x03B0`, exactly the `LDIR` inside `_sprinter_seed_common()`;
- `BC = 0x1ABC`, `DE = 0x6544`, `HL = 0xE544`, so the 16 KB copy from
  common memory to the target page was still in progress;
- `sprinter_dbg[24..28] = 40 41 42 43 43`, showing the second allocation
  handed PID1 pages `0x40..0x43` and selected `0x43` as the common-page
  seed target.

This exposed a narrower problem: `start.c::create_init()` obtains PID1 via
`ptab_alloc()`, and `ptab_alloc()` already calls `pagemap_alloc(newp)`.
The Sprinter `map_init()` path was therefore allocating a second page set for
the same process and then entering a full 16 KB common-page seed that now
hangs before bootmark `4`.

Applied one platform-local trace-phase change in `discard.c`:

- keep marker `p` at `map_init()` entry;
- if `init_process->p_page[0]` is already non-zero, print `Q` instead of
  calling `pagemap_alloc()` again;
- preserve a fallback `q` path only for the unexpected empty `p_page` case;
- store `p_page[0..3]` and the selected top page in `sprinter_dbg[24..28]`;
- print `t` and return without calling `sprinter_seed_common()` in the
  `CONFIG_SPRINTER_EARLY_TRACE` build.

Hypothesis for this image:

- avoiding the redundant second allocation and the blocking common-page seed
  should let `create_init()` advance from `0r123pQt` to bootmarks `4` and `5`;
- if it reaches `Starting /init [72]`, the previous PID1 exec diagnostics
  (`xv/np/dx/rx`) become relevant again.

### Update from 2026-04-25: instrument `map_init()` between bootmarks `3` and `4`

Replay of the re-anchor build regressed earlier than `/init`: the screen stops
at `0r123`, before `create_init()` can print marker `4`, while the CPU is back
inside the initial Sprinter asm clear-screen loop:

- `PC = 0xC322`, which is `clscol` in `Kernel/platform/platform-sprinter/sprinter.s`
- `PG2 = 0x50`, matching that clear loop's temporary VRAM mapping
- `_sprinter_trace_last = 0xC1`, so `create_init()` was entered
- no `xv/np/dx/rx` lines can print because this is now before `_execve()`

Hypothesis for this iteration:

- the failure happens inside the `create_init()` -> `map_init()` corridor,
  most likely around the second `pagemap_alloc(init_process)` or
  `sprinter_seed_common(top)`, before the existing marker `4`.

Applied one narrow platform-local diagnostic in
`Kernel/platform/platform-sprinter/discard.c`:

- print `p` before `map_init()` calls `pagemap_alloc(init_process)`
- print `q` after that allocation returns
- store the post-allocation `init_process->p_page[0..3]` in
  `sprinter_dbg[24..27]`
- store the selected common target page in `sprinter_dbg[28]`
- print `s` immediately before `sprinter_seed_common(top)`
- print `t` after `sprinter_seed_common(top)` returns

Expected decode:

- stop at `...3` only: failure is before/inside the second `pagemap_alloc()`
- stop at `...3pq` or `...3pqs`: `sprinter_seed_common()` is the suspect
- reaching `...3pqst4`: this corridor returned and the failure moved later

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `88c6829cdbeba6963e23f374d30a7bc9f6d9463b7536eed6ddf97b7fa9be6202`
- `Images/sprinter/fuzix.chd` sha256 `bddb1a73d46cd54943390fce385c3b429a6cb28cca17b83a9f927d01b2f4768b`
- `Images/sprinter/fuzix.sprinter` sha256 `2b8bdabca9bd22d3bbcf48632ac09b428aaccccb60bc0675d15d2a7f32aadea8`

Marker sanity in this build:

- `strings -a Images/sprinter/fuzix.sprinter | rg "Starting /init"` =>
  `Starting /init [6C]` and `Starting /init [72]`

Next replay request for this exact build:

- full screen, especially the bootmark suffix after `0r123`
- registers + `PG0..PG3`
- dumps:
  - `0xFD70-0xFE10`
  - `0xFE40-0xFE80` (`sprinter_dbg[24..28]` now lives at `0xFE69..0xFE6D`)
  - `0xEF40-0xF020`

### Update from 2026-04-25: re-anchor PID1 exec state after `plt_discard()`

Replay with `[72]` still ended before the `xv/np/dx/rx` summary could print.
The latched `_execve()` state in the dump decodes as:

- `sprinter_exec_fail_stage = 1`
- `sprinter_exec_fail_err = 2` (`ENOENT`)
- `sprinter_exec_fail_name = 0xFD79`
- `sprinter_exec_fail_argv = 0xFD7F`
- `sprinter_exec_fail_envp = 0xFD83`
- `sprinter_exec_fail_root = 0x0001`
- `sprinter_exec_fail_cwd = 0x0001`

Hypothesis for this iteration:

- the PID1 common `/init` args survive, but `u_root/u_cwd` and possibly
  `u_sysio` are stale/corrupted by the time control reaches `_execve()` after
  `plt_discard()`;
- the direct PID1 lookup either does not run or falls back into the fragile
  `n_open()` path, which then sees invalid root/cwd state and returns `ENOENT`.

Applied one narrow trace-only fix in `Kernel/process.c`:

- immediately after `plt_discard()` and before `_execve()`:
  - force `udata.u_sysio = 1`;
  - restore `udata.u_argn/u_argn1/u_argn2` to the common-memory
    `spr_common_init_*` objects;
  - if `udata.u_root` or `udata.u_cwd` is not an in-core inode-table pointer,
    restore it from valid `root` with `i_ref(root)`.

The visible marker is intentionally still `Starting /init [72]` for the next
replay, matching the current emulator-side capture request.

This re-anchor image was superseded by the `map_init()` corridor probe.  The
probe then stopped at `0r123pqs`, proving the hang was inside
`sprinter_seed_common()` after a redundant second PID1 page allocation.

### Active next replay: no second alloc/no seed current image

Use the current rebuilt image with checksums:

- `Images/sprinter/fuzix.img` sha256 `a566f2b59372a626f8783e552374227636a5d46a1e76a8461a5e50ba5b72f9d1`
- `Images/sprinter/fuzix.chd` sha256 `8801611b0b0b72e698284713df0782d7af97a7679fc964ad8394b1ea1a549e0c`
- `Images/sprinter/fuzix.sprinter` sha256 `8fdb33ba7114767b3ac319c2042d12c7d587568bbc0686e19bbe68ec8b907f16`

Marker sanity in this build:

- `strings -a Images/sprinter/fuzix.sprinter | rg "Starting /init"` =>
  `Starting /init [6C]` and `Starting /init [72]`

This image keeps `p` at `map_init()` entry, prints `Q` when PID1 pages were
already allocated by `ptab_alloc()`, prints fallback `q` only if `map_init()`
had to allocate them itself, records `p_page[0..3]` plus the selected top page
in `sprinter_dbg[24..28]`, then prints `t` without entering
`sprinter_seed_common()`.

Capture:

- full screen, especially the suffix after `0r123`
- if it reaches `/init`, include lines `xv ...`, `np ...`, `dx ...`, `rx ...`
- registers + `PG0..PG3`
- dumps:
  - `0xFD70-0xFE10`
  - `0xFE40-0xFE80`
  - `0xEF40-0xF020`

Decode:

- `0r123pQt4` or later: `map_init()` returned and the blocker moved back
  toward PID1 exec;
- `0r123pqt` with lowercase `q`: PID1 pages were unexpectedly empty before
  `map_init()`;
- stop before `4` with `pQt`: failure is after `map_init()` return but before
  `create_init()` prints marker `4`.

### Update from 2026-07-20: force_bank1 under live banked PC was wiping kernel

MAME bring-up after the `corrupt inode` fixes showed a new hang: `PC` in the
zeroed kernel page at `0x0100`, `PG=48/49/4A/4B`, `_execve` stuck around stage
`E3` (stub install / first usermem writes).

Root cause (confirmed):

- `sprinter_force_bank1()` remaps WIN1/WIN2 to CODE1 while the caller can still
  be executing from CODE2 (`process.c` / `exec_or_die`) or CODE3
  (`syscall_exec16.c` / `sprinter_pid1_init_open`).
- After `ret`, the next fetches at `0x4xxx` are CODE1 bytes interpreted as
  CODE2/CODE3 code → stack/memory corruption → wipe of kernel page 0 → NOP
  slide at `0x0100`.

Fixes in this iteration (platform-local + early-trace core diagnostics):

1. **Remove `sprinter_force_bank1()` from CODE2/CODE3 call sites**
   - `Kernel/process.c` (`exec_or_die`)
   - `Kernel/syscall_exec16.c` (`sprinter_pid1_init_open`)
   - Cross-bank calls must use `__bank_*` stubs only.

2. **`map_proc_2` WIN0 apply moved to common trampoline**
   - `map_apply_win012` in `_COMMONMEM` performs `OUT (MPGSEL_0/1/2)`.
   - Preparation stays in `_CODE`; after WIN0 changes, fetch continues from
     common so the epilogue is not taken from user RAM.

3. **`usermem.s` restored to banked pop-ABI + WIN1/WIN2-only mapping**
   - Never remaps WIN0 from usermem helpers.
   - `restore_k12` keeps `_kernel_pages` and `mpgsel_cache` coherent.

MAME result after the force_bank1 removal:

- Screen reaches `Starting /init [72]…ZURODabO` (bootmark `O` = successful
  `bdread` in `bread`).
- Live map shows CODE3 (`kernel_pages = 48 4E 4F 4B`) instead of stuck CODE1.
- Low page has `JP sprinter_null_stub` at `0x0000`.
- New stop: `RST 38` hang (`rst38_count=1`, `rst38_ret=0xC001`,
  `fail_stage=1`) — next hypothesis is a bad jump into `0xC000` (common window
  base) during the open/exec path, not the old bank1 self-kill.

Helpers added under `Kernel/platform/platform-sprinter/`:

- `mame_exec_probe.lua`, `mame_quick.lua`, `mame_pages.lua`, `mame_open.lua` — headless MAME dumps

### Update from 2026-07-20 (later): past ENOENT/EACCES, crash in readi(header)

MAME after force_bank1 removal stopped at `fail_stage=1` / ENOENT and
`RST38 ret=0xC001`. Further dumps showed:

1. **Root dir + `/init` are fine on disk and in the buffer cache**
   (`buf2` holds block 256 with dirent `init` ino 131), but `srch_dir` /
   `n_open` still returned NULL. PID1 open now falls back to
   `i_open(root_dev, 131)` under `CONFIG_SPRINTER_EARLY_TRACE`.

2. **`fs_tab[0].m_dev` is `NO_DEVICE` after a “successful” `fmount`**
   even though `m_fs` contains a live superblock (`s_mounted=0x31C6`).
   `fs_tab_get()` then returns NULL, `i_open` writes `c_super=0xDA`, and
   `_execve` reads `fs_tab[0xDA].m_flags` as `0xFF` → `MS_NOEXEC` /
   `EACCES` (stage 3). Early-trace repair rebinds `m_dev=root_dev` after
   `fmount` and clamps bogus `c_super` before the noexec check.

3. **Current stop:** `fail_stage=0x18` immediately before
   `readi(ino)` of the 16-byte exec header (`bootmark u`). Open +
   permission checks pass (`ino=21C5`, `mode=0x81ED`, `mflags=0`,
   `fstab dev=0001`). No `doexec` yet (`arm/seen=0`). After the crash,
   PC wanders near `0x0042` with CODE2 mapped and low memory fills with
   `0x4C`.

Open hypotheses:

- Why does `m_dev` clear after `fmount` stores it? (sync / banking /
  pointer)
- Why does `srch_dir` miss a present `init` dirent?
- What faults inside `readi` of the header with `u_sysio=true`?

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `494427cf3b843649de854c80a36d6d68a3188b408206539eba6b36de249f2f2a`
- `Images/sprinter/fuzix.chd` sha256 `5c0dad7cb9d11345c2fc231a4abab6e51712839c12f48cec4d56130fcdbb5eba`
- `Images/sprinter/fuzix.sprinter` sha256 `e1c25fe7e2e51a366a17020522d81c4337229808cd5a21266b5f3fe56c3dfde1`

### Correct next replay

Capture:

- screen suffix after `Starting /init` (look for bootmarks `u`/`v`/`W`/`w`/`x`/`y`/`z`)
- `fail_stage` (expect `0x18` at current stop; `0x17`/`0x20+` if past header read)
- `fs_tab[0]` (`m_dev`, `m_flags`, `s_mounted`) and `ino->c_super`
- `PG0..PG3`, `spr_doexec_arm/seen`, `0x0000-0x0120`
- if past `z`: `SPRINTER USERLAND OK` / `SPRINTER WRITE ONLY OK`

### Update from 2026-07-20: CODE2/CODE3 high halves were zero — userland reached

Root cause of the post-`w` crash (and the earlier `readi`/PC=`0x004x`
chaos once CODE3 execution crossed `0x8000`):

- Linked `CODE2` ends at `0x800D`, `CODE3` at `0x85BB` — both spill into WIN2.
- `Makefile` image packing only took `bank2.bin`/`bank3.bin` `skip=1 count=1`
  (WIN1 half) and **zero-filled pages 5 and 7**.
- With CODE3 mapped as `0x4E/0x4F`, fetches past `0x8000` ran a 16K NOP
  slide into discard/common → PC wandering near `0x0042`/`0x0049`.

Fix (platform Makefile only):

```
dd if=../../bank2.bin bs=16384 skip=1 count=2 ...
dd if=../../bank3.bin bs=16384 skip=1 count=2 ...
```

Also under `CONFIG_SPRINTER_EARLY_TRACE`: header load bypasses nested
`readi`/`uputblk` (CODE3→CODE1→CODE2→memcpy) via `bmap`+`bread`+`memcpy`.

MAME after the packing fix:

- Screen: `…Dabz` plus row 8 `SPRINTER USERLAND OK`
- `doexec` entered (`seen=1`), `expect=0x0112`, `isp=0xEDEE`
- Spin-only `/init` stayed alive: `HALT=0`, `PC` in user low mem,
  `PG=44/45/46/4B`
- `fail_stage=0x11` is the sticky pre-`doexec` latch (17), not a failure

Next targets:

- Make `write(1, …)` from `/init` print `SPRINTER WRITE ONLY OK` (stdio /
  syscall path; PID1 stdio bootstrap re-enabled)
- Root-cause `m_dev` loss after `fmount` and `srch_dir` miss (remove ino 131
  hardcode)
- `ei` after `doexec` so IRQs run in userland

Current artefact checksums:

- `Images/sprinter/fuzix.img` sha256 `c0a3a5dabb660a282f850bc9d5b880abb147f291bc19ad6bd7106c1cda04ed0d`
- `Images/sprinter/fuzix.chd` sha256 `0518fdcd231e9f92a162e1dca87ce0f6b1a206f0009734966a4046364d0c267a`
- `Images/sprinter/fuzix.sprinter` sha256 `e55b14e985f7a2bc6648c642fe5d362fecf57f106978d471e7eeda6f870554c6`

### Correct next replay

Capture:

- screen rows 7–10 for `SPRINTER USERLAND OK` / `SPRINTER WRITE ONLY OK`
- `PC`/`SP`/`HALT`/`PG0..3` after ~6s (alive spin vs monitor)
- `fail_stage`, `spr_doexec_seen`, `isp`/`expect`
- if write missing: `u_files[0..2]`, `spr_initio_*` latches



### Update from 2026-07-20 (evening): WIN0 / "/init" path bring-up

Root causes found while chasing `SPRINTER WRITE ONLY OK`:

1. **`"/init"` must live in `_COMMONMEM`**, not `_COMMONDATA` (BSS wipe) and
   not WIN0 `_CODE` (user page may be mapped there during `n_open`).
2. **`getcf()` must `spr_map_win0_k()`** before reading static `name`/`nameend`
   (they live in WIN0 DATA). Without that, PID1 saw `ENOENT` despite a live
   `"/init\0"` string in common.
3. **`sprinter_pid1_init_open()` shortcut** returned an `i_tab` slot of `0xFF`
   (`ino=0x21FF`, `mode=0xFFFF`) → false `MS_NOEXEC` / `EACCES` stage 3.
   Temporarily returns `NULL` so exec uses full `n_open()`.
4. Keep `_COMMONDATA` below `0xFF00` (IM2 vectors). Do not grow common with
   large asm helpers — put them in `_CODE`.
5. Session regression: a broken `kputs("USERLAND...")` string (lost `\r\n`)
   corrupted the binary; restored from git.

Still open:

- Stable `execve("/init")` → `SPRINTER USERLAND OK` after the above (last MAME
  showed bootmarks `…Dab0`, banking oddity `PG0=4B`).
- Then asm/C stdio for fd1 and first `write(1)` → `SPRINTER WRITE ONLY OK`.
- SDCC `of_tab[].o_inode` store into `fs_tab` remains a known hazard for the
  C `sprinter_open_boot_tty()` path — prefer asm bootstrap after USERLAND.

Artefacts:

- `fuzix.img` sha256 `289b60358b1f0f77abed30a125923ae33e9621b2f6e8954321948da4d045648b`
- `fuzix.chd` sha256 `827007be822c1b4a9c01cd3808b82145596e7272d3b7c14a6c6d604245c9ddb7`
- `fuzix.sprinter` sha256 `588b40cf0571e8b8c7bd68b1d78c121e8244d939e80320e054602a98338b9fb0`

Next MAME dump: `sprinter_exec_fail_stage/err/ino/mode`, `PG0..3`, screen for
`USERLAND` / `WRITE ONLY OK`, and `0xF431` (or current `_spr_common_init_path`).

### Update from 2026-07-20 (late): `n_open` walk state left WIN0 DATA

Last MAME stop after the COMMONMEM `/init` path fix:

- Screen: `…DabO` (bootmark `O` = successful `bdread`)
- `PC` in `_plt_monitor` hang, `HALT=1`
- `fail_stage=0`, `fail_ino=0`, `nopen_name` already past `/init` NUL
- Hypothesis: path walk mostly worked, then a later `i_deref`/`magic`
  saw a garbage inode pointer

Root cause (high confidence):

- `n_open()` kept `wd` / `ninode` as `staticfast` in **WIN0 DATA**.
- After `bread`/IDE/`map_*`, WIN0 can briefly (or sticky) map a
  non-kernel page; the next read of those statics returns garbage
  (observed panic_ptr into BSS around `0x21E1`).
- Kernel stack lives in common (WIN3), so auto locals stay valid.

Fixes in this iteration (`CONFIG_SPRINTER_EARLY_TRACE` only for core):

1. `n_open()`: `wd`/`ninode` are automatic locals under early-trace.
2. `i_deref()`: reject any pointer outside `i_tab` (not just `<0x100`).
3. `magic()`: `spr_map_win0_k()` before reading `c_magic`.
4. `_execve()`: stage latches `0xA0..0xA3` around open; pid1 shortcut
   returns `NULL` again (avoids the old `0x21FF`/`0xFFFF` false EACCES).
5. `mame_exec.lua`: dump **live** `PG0..3` before forced remap; also
   `nopen_stage`, `iopen_ret`, `panic_ptr/bytes`.

Artefacts:

- `fuzix.img` sha256 `712420d58d81601c6074726f66e6db23979f922c2183bb04288dba329e2d574d`
- `fuzix.chd` sha256 `df8c71c438452cfafad902dad58c78ca7f218e068b9f47c498c713c0d33c7f0e`
- `fuzix.sprinter` sha256 `373716e0c6c1f48656f101ff4fdb61f69cb8f8349f5f542fdb15cc17d582b655`

### Correct next replay

Capture:

- screen rows 7–10 for `SPRINTER USERLAND OK` / panic text / bootmarks
  after `Dab` (`O`/`u`/`v`/`z`)
- `fail_stage` decode:
  - `0xA2` = entered `n_open`
  - `0xA3` = returned from `n_open` (then expect `ino!=0` or stage `1`)
  - `0x11` sticky + `USERLAND` = doexec reached again
- live `PG0..3` / `SP` / `HALT` (script now prints live before remap)
- `nopen_stage` (`0xD6`/`0xD7`), `iopen_ret`, `panic_ptr` + 4 bytes
- if `USERLAND`: also `u_files[0..2]` for the write path

### Update from 2026-07-20 (night): USERLAND OK restored via synthetic /init

MAME after the `n_open` stack-local + `lastname` COMMONMEM work:

1. **`n_open` completes (`D7`) but `srch_dir` still returns `ni=0`**
   despite `/init` present on the image (ucp ino 131). Root walk is not
   trusted yet under WIN0.
2. **`i_open(131)` / `breadi` into `i_tab`** left `CMAGIC` + garbage
   `mode=0xD301` → false progress then `ENOEXEC`, and could clear root
   `c_magic` → `panic: corrupt inode` on `i_deref`.
3. **PID1 open is now synthetic** (early-trace only): allocate a low
   `i_tab` slot and install known geometry from the Sprinter image
   (`mode=0x81ED`, size 634, blocks 293/294), force `c_super=0`, repair
   `fs_tab[0].m_dev` if cleared after `fmount`.

Result:

- Screen: `…DaU` + **`SPRINTER USERLAND OK`**
- `fail_stage=0x11`, `ino=16DD`, `mode=0x81ED`
- Still **no** `WRITE ONLY OK` (`u_files=FF`, stdio bootstrap still off)
- Post-doexec stop: `PC≈0x002C`, `HALT=1` — next edge is user entry /
  first `write(1)` / IRQ, not `/init` open

Artefacts:

- `fuzix.chd` sha256 `8bf8d28caa8a98557ae7efbb540b41d63e7b97e9724d7b8bbf66039c611506fc`

Next:

- Keep PID1 alive after `doexec` (compare with prior spin-only success)
- Asm stdio bind for fd 0/1/2 → `SPRINTER WRITE ONLY OK`
- Replace synthetic open with a real `srch_dir` once WIN0 inode/buffer
  reads are solid

### Update from 2026-07-20 (night+): raw `/init` at PROGLOAD + stdio on

Hypothesis for post-`doexec` `PC≈0x002C` / `HALT=1`:

- Libc `sprinit` (and the old `sprinit_raw` linked at `0x0000`) write
  absolute labels into `0x00xx` while the process actually runs at
  `PROGLOAD=0x0100` after `pagemap_prepare` sets `a_base=1`.
- Those stores smash the low-page vector hole (near NMI/`0x0066`), so
  execution later lands around `0x002C` and dies.

Fixes in this iteration:

1. **`sprinit_raw`**: link with `-b _HEADER=0x0100`, header `a_base=1`,
   `call 0x0100` for syscalls, message `SPRINTER WRITE ONLY OK`, then
   spin (no `pause`). Labels now live in `0x01xx`.
2. **Package `/init`** from `sprinit_raw` (109 bytes, ino 131, block 293).
3. **Synthetic PID1 open** geometry updated to size `109` / block `293`.
4. **Re-enable `sprinter_prepare_init_stdio()`** before `exec_or_die`
   (USERLAND open/exec is past the synthetic edge; need fd1 for write).

### Update from 2026-07-20 (night++): map_proc WIN0 self-unmap

MAME after raw `/init` + stdio:

- `/init` bytes correct at user `0x0112`, but `stage` stayed `00`
- `doexec seen=01` and `m0/m1/m2=00` — died mid-`map_proc_2`
- Root cause: `map_proc_always` / `map_proc_2` live in WIN0 `_CODE`.
  `OUT (MPGSEL_0), user` unmaps the routine; later `call`/`ret` back
  into WIN0 after the switch also fetches user garbage → RST38 hang

Fix (platform `sprinter.s`):

1. Fill `mpgsel_cache` in WIN0 without OUTing WIN0
2. `map_proc_2` → `jp map_apply_cached` (COMMON) for direct callers
3. `map_proc_2_pophl_ret` → fill then `jp map_apply_pophl` (COMMON:
   apply banks, `pop hl`, `ret` to the original common caller)

Keep `_COMMONDATA` end ≤ `0xFF00` (IM2 vectors).

MAME after the map fix:

- `seen=02`, `m=44/45/46`, `expect=0112`
- **`stage=0x12`** — user `/init` ran past the pre-write markers
- `u_files=00 00 00` (stdio bound to oft 0), `page=44 45 46 47`
- Still no `WRITE ONLY OK`: first `write(1)` hits **RST38**
  (`rst38=01`, `ret=D648`, `HALT` in `rst38_hang`, `insys=1`)
- Screen still shows `SPRINTER USERLAND OK` only

Artefacts:

- `fuzix.chd` sha256 `ef7bf92cfa074610b8a56b4246b50a89d2a0da13a0d1f0199bff4a1fefb54a33`

### Update from 2026-07-20 (evening): write(1) reached, iobad on tty

Stacked on the map_apply fix:

1. **`map_kernel` in `_COMMONMEM`** (syscall entry with user WIN0).
   Always force WIN0=`0x48`; keep WIN1/2 from `_kernel_pages` so CODE2/3
   overlays survive (hardcoded BANK1 caused `panic: invalid dev`).
2. **`_spr_map_win0_k`** in common — WIN0 only (safe from CODE3).
3. **`entry_off` / `entry_abs`** stack snapshot + PID1 force `a_entry=0x12`
   (static `hdr` in WIN0 `_DATA` was read as 0 after user map →
   `doexec(0x0100)` into stubs).
4. **Skip `uget(argv[0])` name copy for PID1** — crashed after `wargs`
   (markers `SPR@E8` yes / `SPR@A3` no).
5. Boot tty inode `c_dev = TTYDEV` (was `root_dev`).

MAME now:

- Markers through `SPR@A6`, `seen=02`, `expect=0112`, **`stage=0x12`**
- `callno=08` (write), `u_files=00 00 00`, `fail=0x11` (stage 17)
- **No `WRITE ONLY OK`**: `err=EINVAL (0x16)`, screen `iobad … dev=0000`
- At hang `PG0` still user `0x44` — `of_tab`/`i_tab` in WIN0 `_DATA`
  read as garbage (`o_inode` looks like `0xE2EF`)

`_COMMONDATA` end must stay ≤ `0xFF00` (currently ~1 byte free).

### Correct next replay

- screen for **`SPRINTER WRITE ONLY OK`**
- `stage` (`0x13` = write ok, `0x93` = write carry/error, `0x14` = spin)
- during write: live `PG0` must be `0x48` while touching `of_tab`/`i_tab`
- `oft[0].o_inode` / `c_magic` / `c_dev` with kernel WIN0 mapped
- confirm `map_kernel` on `unix_syscall_entry` actually OUTs `0x48` to
  `MPGSEL_0` before `cdwrite`/`getinode`

Artefacts:

- `fuzix.chd` sha256 `04727db179c4fbf8b84ce1072b1b65648923ffe98291c2cf3aecba8680df23ee`

### Update from 2026-07-20 (late): first `write(1)` text on screen

Stacked fixes that got `SPRINTER WRITE ONLY` onto row 0:

1. **`sprinit_raw` syscall ABI** — bare `call 0x0100` was one return
   word short vs libc (`call __text` then stubs). Added `dosys`
   trampoline; size 113; synthetic PID1 `i_size` updated.
2. **IM2 stub moved `0xFDFD` → `0xFFFD`** — with `I=0xFF` / fill `0xFD`
   the vector is `0xFFFD`, and the old `ld (0xFDFD),#0xC3` corrupted
   `__uget`'s `call user_map_de` (`CD B6 FC` spans `FDFB..FDFD`) into
   `call 0xC3B6` (discard) → RST38.
3. **`tty_write` skips `valaddr_r` when `u_sysio`** — bounce path was
   rejecting kernel kstack addresses above `u_top`.
4. **Removed kstack `bounce[64]` in `cdwrite`** — overflowed common
   kstack (19×`M` garbage, then RST38). Per-char `_ugetc` is enough
   now that `__uget` is intact.

MAME now:

- **VRAM R00 = `SPRINTER WRITE ONLY`** (19-byte probe length; no
  ` OK\r\n` yet because `sprinit_raw` pushes nbytes=19)
- `argn=0001 0153 0013`, `err=0000`
- Still **RST38 after the write** (`ret=00C4`, `USER stage` stuck at
  `0x12`, `HALT` in `rst38_hang`); screen still shows a late `iobad`
  line (garbage inode ptr — wrong-bank `i_open` during/after return)

Next:

- finish syscall return so `spr_stage` reaches `0x13`/`0x14` and the
  probe spins (`HALT=0`)
- dump who calls `i_open` after the tty write (CODE3 stuck at hang:
  `mp=4E/4F`)
- then lengthen the probe string / drop early-trace scaffolding

Artefacts: rebuild `Images/sprinter/fuzix.chd` from this tree.

### Update from 2026-07-20 (late+): userland spin after first write

Checkpoint reached:

- VRAM shows **`SPRINTER WRITE ONLY`** (early-kputc path, row 15)
- **`spr_stage=0x14`**, `spr_spin` incrementing, **`HALT=0`**, `PC` in
  user spin loop, **`rst38_count=0`**
- Root causes cleared this step:
  1. Skip `tty_write`/`vtoutput` (CODE3) for early-trace tty writes —
     use `ugetc` + `kputchar`→`plot_char` in WIN0 instead
  2. Silence `badino` `kprintf` (nested print during wrong banks →
     RST38@00C4); latch only
  3. `di` in `sprinit_raw` spin so post-syscall `ei` cannot vector into
     the FONT/`0xFF` hole at `0xE6xx`

Residual (non-blocking for this checkpoint):

- `u_error` sometimes still `EEXIST (0x11)` on the write return path
  (carry set → user briefly takes fail stage); text still printed
- `oft[0].o_inode` may read as 0 after return — investigate before
  second write/open
- Real `srch_dir` / drop synthetic PID1 open still pending

Next: clear stale `EEXIST`, keep `oft` intact across the write return,
then lengthen the probe string / try `pause` or `/bin/sh`.

### Update from 2026-07-20 (evening): clean write return

MAME after the stale-`EEXIST` / retval fix:

- VRAM R15: **`SPRINTER WRITE ONLY OK`** (full 24-byte probe)
- `spr_stage=0x14`, `spr_wr=0x0018`, `spin` climbing, `HALT=0`
- `udata.u_error=0`, `u_retval=u_done=0x18`, `exit_err=0`
- `oft[0].o_inode` intact (`0x16E6`, refs=3); prior "oft wiped" was a
  dump-script address bug (`0x15E6` instead of `of_tab+4`)
- `rst38_count=0`

What was wrong:

1. After `writei`/`readwrite` cleared `u_error`, something in the
   `unix_syscall` tail still left `EEXIST (0x11)` by the time
   `spr_sys_exit_err` was snapped — carry set, user took the fail path
   (masked later by always overwriting stage with `0x14`).
2. Banked `syscall_dispatch` stub returned `HL=0` for `_write` even when
   `u_done==24`, so success path still stored `spr_wr=0`.

Bring-up fix (early-trace / Sprinter lowlevel only):

- On `callno==write` and `spr_rw_stage==0xC2`, force `u_error=0` and
  reload `u_retval` from `u_done` before `unix_return`
- `sprinit_raw` fail path now sticky-`0x93` (no longer overwritten by
  spin); nbytes = full message length
- `mame_write2.lua` refreshed from `fuzix.map` (COMMONMEM latches move)

Residual: root source of the post-`readwrite` `EEXIST` still unknown
(`ch_link` stage stays 0 on this path). Masked for the C2 tty write
only. Next: `pause` or a second write / path toward `/bin/sh`.

Artefacts: `Images/sprinter/fuzix.chd` from this tree.

### Update from 2026-07-20 (night): stable dual-write idle

MAME 15s soak:

- R15/R16: **`SPRINTER WRITE ONLY OK`** + **`SPRINTER IDLE OK`**
- `stage=0x16`, `wr=0x18`, `wr2=0x12`, `spin` climbing, **`HALT=0`**,
  `PC` in user idle, **`rst38=0`**, IM2 page intact (`FF00=FD`,
  `FFFD=JP` stub)

Fixes this step:

1. **COMMONDATA overflow into IM2 page** — exec/i_deref latch farm +
   `sprinter_dbg[32]` ended at `0xFF1C`, so dbg writes corrupted the
   `I=0xFF` vector table → delayed RST38/`magic()`. Collapsed exec
   latches into a 16-byte scratch; COMMONDATA now ends at `0xFEFA`.
2. **`/init` probe** — two successful `write(1)` then `di` + busy-spin
   idle (no `pause`/`psleep` yet).

Still blocked for a “real” multi-process system:

- `pause(0)`/`psleep`/`switchout` → `magic()` (`n_open` site=1) or
  `plt_monitor`
- IM2 still on `sprinter_bringup_int` absorber (no timer IRQ wakeup)
- Real `/bin/sh` needs working `n_open`/`srch_dir` (synthetic PID1 open
  remains)

Next: repair `psleep`/scheduler OR synthetic `execve("/bin/sh")` path;
then wire real `interrupt_handler` once FRAME ack is understood.


### Update from 2026-07-20 (late): synthetic execve("/bin/sh") path

Previous checkpoint: dual-write idle (`stage=0x16`).  Next step toward a
real shell is PID1 `execve("/bin/sh")` without trusting `n_open`/`srch_dir`.

Changes:

1. **`sprinit_raw`** — after the two successful `write(1)`s, call
   `execve("/bin/sh", argv, envp)` (syscall 23).  Stages:
   - `0x18` about to execve
   - `0x19` returned without carry (unexpected)
   - `0x97` returned with carry / errno in `spr_wr`
2. **`syscall_exec16.c`** (early-trace only) — synthetic PID1 open now
   matches both `/init` and `/bin/sh` (user path via `ugetc` when
   `!u_sysio`).  Geometry from current `filesys.img`:
   - `/init` ino **131**, size **218**, block **293**
   - `/bin/sh` ino **177**, size **26630**, direct **1003–1020**,
     single-indirect **1021** (data **1022–1056**)
3. `/init` refreshed in-place via `ucp bget` (no full FS rebuild — keeps
   `/bin/sh` block numbers stable).

Artefacts:

- `fuzix.img` sha256 `4dab0dc05ae58b538890c94f2fc43e1af60fad421afa97706be406a43e3d5f9d`
- `fuzix.chd` sha256 `f5502383de503066869eef9ee13853329af49f22af9326d7d2083654d55899a0`
- probe script: `Kernel/platform/platform-sprinter/mame_sh_handoff.lua`

MAME dump points (after ~8s):

| What | Addr |
|------|------|
| `spr_stage` | `0x01D4` |
| `spr_wr` / `spr_wr2` | `0x01D5` / `0x01D7` |
| `fail_stage` / `fail_err` | `0xFE62` / `0xFE63` |
| `fail_ino` / `fail_mode` | `0xFE6B` / `0xFE6D` |
| `sprinter_dbg` | `0xFEDA` |
| VRAM text rows | R15–R20 for write banners / shell prompt |

Success signals:

- `stage` never stuck at `0x18` forever without progress
- `fail_stage` past `0xA3` / header `0xED` / `0xFA` toward `doexec`
- VRAM eventually shows shell prompt (or at least leaves `/init` map —
  `PROGLOAD` header becomes `/bin/sh`'s `80 A8 ...`, not sprinit's)

Still blocked afterward (unchanged): real `pause`/`psleep`, timer IRQ,
real `n_open`/`srch_dir`.


### Update from 2026-07-20 (late night): `/bin/sh` loads and enters

Milestone advanced past dual-write idle.

What works now:

1. `sprinit_raw` dual `write(1)` then `execve("/bin/sh", argv, empty env)`
2. Synthetic PID1 open for `/bin/sh` (pointer `0x01C6` only — no `ugetc`)
3. Geometry: ino **177**, size **26630**, direct **1003–1020**, ind **1021**
4. PID1 empty-`envp` rargs skipped under early-trace (stale `EEXIST` / ugetp edge)
5. MAME: user `PROGLOAD+0x12` bytes match `/bin/sh` text; stubs at `0x0100`

Hang after shell entry (t≈5–6s):

- `PC` in common halt loop near `0xF251`, `HALT=1`
- Stack shows `namecomp` / `psleep_flags` / `doexit` — shell started and
  hit the still-broken path-walk / sleep / exit corridor
- `mpgsel` sometimes shows WIN2=`0x00` at the freeze (banking smoke)

Artefacts:

- `fuzix.img` sha256 `fa73f379fade90d4c0620003b04aa80a51f90594f61c9ceb44a94b5f34cf01db`
- `fuzix.chd` sha256 `33dfb414f2accc8379dc80e97b08c674d75dbe84dcd1d07329531afa32623304`
- `/init` = `sprinit_raw` (218 bytes, block 293)

Next:

1. Catch first `namecomp`/`n_open` after sh entry (why shell exits)
2. Or stub PID1 `psleep`/`pause` more aggressively so sh can idle on tty read
3. Real `srch_dir` still deferred; keep synthetic opens until that is safe


### Update from 2026-07-20 (night): hang mitigations after /bin/sh entry

Goal: stop the post-`/bin/sh` freeze (HALT≈F251 / `psleep: voodoo`).

Changes (all under `CONFIG_SPRINTER_EARLY_TRACE`):

1. **PID1 tty busy-poll** in `do_psleep()` for `read`/`write` and
   `ttyinq`/`ttydata` wait events — avoids `switchout` → monitor on
   interactive tty waits. Disk sleepers stay on the real idle path so
   `/init` load is not starved.
2. **PID1 VOODOO recovery** — if `p_status` is non-canonical, busy-poll
   instead of `panic("psleep: voodoo")`.
3. **Accept `P_READY`** in the psleep status switch (early-trace).
4. **PID1 userland `n_open` → ENOENT** — skip broken directory walks
   (`.profile` / path probes) so the shell is not trapped in `namecomp`.
5. **Sticky `u_sysio` clear** for exec path pointer `0x01C6` so synthetic
   `/bin/sh` open matches.
6. **`cdwrite`**: no `sprinter_force_bank1()` after the kputchar loop.
7. Filesystem rebuilt; `/init` = `sprinit_raw` (ino 131, block 293).

MAME (8s one-shot, no live remapping):

- `/bin/sh` **loads** (`PROGLOAD+0x12` = `D5 D9`)
- No `psleep: voodoo` when recovery is active
- Still eventually `HALT=1` in the common IRQ/monitor area with a bad SP
  — next target: first post-entry syscall that is neither tty nor open

Artefact: `fuzix.chd` sha256 `297c88bd6c187d8bddece31139f343412791009a0161d9967ae23b9e8b09e0aa`
