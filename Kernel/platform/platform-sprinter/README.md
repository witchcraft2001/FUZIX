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
