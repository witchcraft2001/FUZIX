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
