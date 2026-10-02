;
;	Sprinter (Peters MC 2008) hardware support
;

        .module sprinter

        ; exported symbols
        .globl init_hardware
	.globl _program_vectors
	.globl map_kernel
	.globl _map_kernel
	.globl _spr_map_win0_k
	.globl map_kernel_restore
	.globl map_proc
	.globl map_proc_save
	.globl map_proc_save_u
	.globl map_buffers
	.globl map_kernel_di
	.globl map_proc_di
	.globl map_proc_always
	.globl map_proc_always_di
	.globl map_save_kernel
	.globl map_restore
	.globl map_kernel_restore_u
	.globl map_for_swap
	.globl plt_interrupt_all
	.globl _copy_common
	.globl _sprinter_seed_common
	.globl mpgsel_cache
	.globl _mpgsel_cache
	.globl top_bank
	.globl _kernel_pages
	.globl _plt_reboot
	.globl _plt_monitor
	.globl _plt_trace
	.globl _sprinter_force_bank1
	.globl _dev_tab
	.globl _int_disabled
	.globl _sprinter_bringup_noei
	.globl _spr_doexec_count
	.globl _sprinter_psleep_tty_ei
	.globl _sprinter_psleep_maybe_ei
	.globl _sprinter_trace_last
		.globl _sprinter_nullh_count
		.globl _sprinter_null_sp0
		.globl _sprinter_null_sp2
		.globl _sprinter_trace_idx
		.globl _sprinter_trace_buf
		.globl _sprinter_dbg
		.globl _spr_initmsg
	.globl _spr_common_init_path
	.globl _spr_common_init_argv
	.globl _spr_common_init_envp
	.globl _spr_nopen_name
	.globl _spr_nopen_nameend
		.globl _sprinter_ide_bounce
	.globl _sprinter_exec_fail_stage
	.globl _sprinter_exec_fail_err
	.globl _sprinter_exec_fail_name
	.globl _sprinter_exec_fail_root
	.globl _sprinter_exec_fail_cwd
	.globl _sprinter_exec_fail_ino
	.globl _sprinter_exec_fail_mode
	.globl _sprinter_exec_fail_perm
	.globl _sprinter_exec_fail_mflags
	.globl _sprinter_exec_fail_argv
	.globl _sprinter_exec_fail_envp
	.globl _sprinter_exec_fail_done
	.globl _sprinter_exec_fail_count
	.globl _sprinter_last_exec_base
	.globl _sprinter_last_exec_count
	.globl _sprinter_last_exec_top
	.globl _sprinter_last_exec_upage
	.globl _sprinter_last_exec_ptab
	.globl _sprinter_last_ideref_in
	.globl _sprinter_last_ideref_post
	.globl _sprinter_last_ideref_wr
	.globl _sprinter_last_ideref_meta
	.globl _sprinter_last_wr_ptr
	.globl _sprinter_last_wr_meta
	.globl _sprinter_last_wr_site
	.globl _sprinter_last_newfile_pino
	.globl _sprinter_last_newfile_nindex_in
	.globl _sprinter_last_newfile_nindex_prewr
	.globl _sprinter_last_iopen_dev
	.globl _sprinter_last_iopen_ino
	.globl _sprinter_last_iopen_ret
	.globl _sprinter_last_iopen_bad
	.globl _sprinter_last_iopen_mode
	.globl _sprinter_last_iopen_nlink
	.globl _sprinter_bad_iopen_dev
	.globl _sprinter_bad_iopen_ino
	.globl _sprinter_bad_iopen_bad
	.globl _sprinter_bad_iopen_mode
	.globl _sprinter_bad_iopen_nlink
	.globl _sprinter_bad_iopen_ptr
	.globl _sprinter_bad_iopen_a0
	.globl _sprinter_bad_iopen_a1
	.globl _sprinter_bad_iopen_flags
	.globl _sprinter_last_nopen_stage
	.globl _sprinter_last_nopen_wd
	.globl _sprinter_last_nopen_ninode
	.globl _sprinter_last_nopen_name0
	.globl _sprinter_last_nopen_char
	.globl _sprinter_last_validchk_dev
	.globl _sprinter_last_validchk_site
	.globl _sprinter_last_panic_ptr
		.globl _sprinter_last_panic_bytes
		.globl _sprinter_rst38_count
		.globl _sprinter_rst38_sp
		.globl _sprinter_rst38_ret
		.globl _sprinter_rst38_insys
		.globl _sprinter_rst38_callno
		.globl _sprinter_rst38_inirq
		.globl _sprinter_rst38_up0
		.globl _sprinter_rst38_up1
		.globl _sprinter_rst38_up2
		.globl _sprinter_rst38_mp0
		.globl _sprinter_rst38_mp1
		.globl _sprinter_rst38_mp2
		.globl _sprinter_rst38_i
		.globl _sprinter_chlink_stage
		.globl _sprinter_chlink_wd
		.globl _sprinter_chlink_nindex
	.globl _sprinter_chlink_done
	.globl _sprinter_chlink_error
	.globl _sprinter_ideref_null_count
	.globl _sprinter_ideref_null_sys
	.globl _spr_gir
	.globl _spr_giu
	.globl _spr_gio
	.globl _spr_gifr
	.globl _spr_gifa
	.globl _spr_giin
	.globl _spr_gis
	.globl _spr_gfcnt
	.globl _spr_gfr
	.globl _spr_gfu
	.globl _spr_gfo
	.globl _spr_gffr
	.globl _spr_gffa
	.globl _spr_gfin
	.globl _spr_gfs
	.globl _spr_iac_devptr
	.globl _spr_iac_ninode
	.globl _spr_iac_tinode
	.globl _spr_iac_isize
	.globl _spr_iac_mounted
	.globl _spr_gd_dev
	.globl _spr_gd_mnt
	.globl _spr_gd_state
	.globl _spr_sys_enter_no
	.globl _spr_sys_enter_up0
	.globl _spr_sys_enter_up1
	.globl _spr_sys_enter_up2
	.globl _spr_sys_enter_pp0
	.globl _spr_sys_enter_pp1
	.globl _spr_sys_enter_pp2
	.globl _spr_sys_enter_ptab
	.globl _spr_sys_enter_fixup
	.globl _spr_sys_exit_no
	.globl _spr_sys_exit_err
	.globl _spr_sys_exit_up0
	.globl _spr_sys_exit_up1
	.globl _spr_sys_exit_up2
	.globl _spr_sys_exit_pp0
	.globl _spr_sys_exit_pp1
	.globl _spr_sys_exit_pp2
		.globl _spr_sys_exit_ptab
		.globl _spr_sys_fixup
		.globl _spr_sysarg_sp
		.globl _spr_doexec_arm
		.globl _spr_doexec_seen
		.globl _spr_doexec_map_ptr
		.globl _spr_doexec_expect
		.globl _spr_doexec_isp
		.globl _spr_doexec_u0
		.globl _spr_doexec_u1
		.globl _spr_doexec_u2
		.globl _spr_doexec_u3
		.globl _spr_doexec_m0
		.globl _spr_doexec_m1
		.globl _spr_doexec_m2
		.globl _spr_doexec_call_seen
		.globl _spr_doexec_call_sp
		.globl _spr_doexec_call_ra0
		.globl _spr_doexec_call_ra1
		.globl _spr_doexec_call_af
		.globl _spr_doexec_call_start
		.globl _spr_rdwr_stage
		.globl _spr_rdwr_reading
		.globl _spr_rdwr_fd
		.globl _spr_rdwr_base
		.globl _spr_rdwr_count
		.globl _spr_rdwr_argn
		.globl _spr_rdwr_argn1
		.globl _spr_rdwr_argn2
		.globl _spr_rw_stage
		.globl _spr_rw_fd
		.globl _spr_rw_base
		.globl _spr_rw_count
		.globl _spr_rw_access
		.globl _spr_rw_mode
		.globl _spr_rw_dev
		.globl _spr_initio_stage
		.globl _spr_initio_fd
		.globl _spr_initio_err
		.globl _spr_initio_files
		.globl _spr_va_stage
		.globl _spr_va_base
		.globl _spr_va_size
		.globl _spr_va_top
		.globl _spr_switchin_stage
		.globl _spr_switchin_sp
		.globl _spr_switchin_ret
		.globl _spr_switchin_next
		.globl _spr_pg2_clamp_count
	.globl _spr_pg2_last_raw
	.globl _spr_boot_count
	.globl _td_op
	.globl _devide_read_data
	.globl _devide_write_data
	.globl _td_raw
	.globl _td_page

        ; imported symbols
        .globl _ramsize
        .globl _procmem
	.globl interrupt_handler
	.globl unix_syscall_entry
	.globl nmi_handler
	.globl null_handler
	.globl _udata
	.globl _vtoutput
	.globl _plt_interrupt

	; exported debugging tools
	.globl outchar

        .include "kernel.def"
        .include "../../cpu-z80/kernel-z80.def"


;=========================================================================
; Initialization code
;=========================================================================
        .area _DISCARD

init_hardware:
        ; program vectors for the kernel
        call do_program_vectors

        ; set system RAM size
	; Sprinter has 4MB RAM = 4096KB
	; The user pool excludes firmware and kernel pages (56 * 16K).
        ld hl, #4096
        ld (_ramsize), hl
        ld hl, #896		; 56 * 16K user pages
        ld (_procmem), hl

	; Text mode 80x32 is initialized by BIOS at power-on.
	; The BIOS loads the font (character generator) into VRAM
	; and sets up the hardware text mode (VCM=3, port #C3).
	;
	; We select text mode explicitly in case BIOS left us
	; in a different mode:
	ld a, #0x03		; text 80x32 mode via port #C3
	out (VID_MODE), a

	; Leave RGMOD (port #C9) untouched: BIOS has already fully
	; initialised the currently displayed screen (including Mode0
	; bytes, font, geometry).  Switching the RGMOD page bit would
	; point the video controller at a different VRAM area whose
	; Mode0 cells are uninitialised garbage (most notably rendering
	; as BORDER because MODE0[7:4]==#F on un-programmed cells).
	; Instead we write to whichever screen BIOS left active, using
	; the PORT_Y bit 7 marker in sprvideo.s to target it.

	; Clear the displayed screen so kernel output starts on a clean
	; background rather than mixed with BIOS boot-loader text.
	; Directly write space + default attr to every cell (screen B
	; layout: PORT_Y = (col+1) | 0x80, HL = 0x8301 + row*4).  WIN2
	; is temporarily remapped to VRAM page #50 for the fill.
	ld a, #0x50
	out (MPGSEL_2), a
	ld e, #0			; row = 0
clsrow:
	ld d, #0			; col = 0
clscol:
	ld a, d
	inc a
	or #0x80			; screen B
	out (VID_PAGE), a
	ld a, e
	rlca
	rlca				; row * 4
	ld l, a
	ld h, #0x83			; HL = 0x8300 + row*4 (Mode0)
	inc l				; HL = 0x8301 + row*4 (Mode1)
	ld (hl), #0x20			; space
	inc hl
	ld (hl), #0x0F			; white on black
	inc d
	ld a, d
	cp #80
	jr nz, clscol
	inc e
	ld a, e
	cp #32
	jr nz, clsrow
	; Restore WIN2 to kernel bank1 high page.
	ld a, #0x4A
	out (MPGSEL_2), a

	; Hard-disable every Z84C15 on-chip CTC channel.  BIOS may have
	; left CTC CH0..CH3 generating periodic IM2 vectors.  The kernel
	; interrupt_handler exit path unconditionally clears _int_disabled
	; and `ei`s, so a single pre-enabled CTC interrupt latches the CPU
	; into a loop we can't exit.  Issue reset+no-trigger for every
	; channel so none can raise TINT until the kernel is stable.
	ld a, #0x03		; SW reset | CW
	out (CTC_CH0), a
	out (CTC_CH1), a
	out (CTC_CH2), a
	out (CTC_CH3), a

	; Set up IM2 interrupt vectors.
	;
	; WIN3 is always mapped. Keep vectors above PROGTOP=E000 and
	; below common at EE00: E000..E100 table, E1E1..E1E3 jump.
	; External IRQ supplies FF, so an FF00 table would wrap into WIN0.
	; Repeated E1 bytes resolve to E1E1 for both odd and even vectors.
	ld hl, #0xE000
	ld de, #0xE001
	ld bc, #256
	ld (hl), #0xE1
	ldir

	; Minimal bring-up IRQ stub (reti, leave IFF1 clear) — not the
	; FUZIX interrupt_handler, whose exit clears _int_disabled and
	; ei's into an IRQ storm on Sprinter FRAME/CTC.
	ld a, #0xC3			; JP instruction
	ld (0xE1E1), a
	ld hl, #sprinter_bringup_int
	ld (0xE1E2), hl

	ld a, #0xE0
	ld i, a
	im 2

	; Force _int_disabled=1 irrespective of boot state so the first
	; `irqrestore(di())` pair does not accidentally enable interrupts
	; while the kernel is still in bring-up.
	ld a, #1
	ld (_int_disabled), a

        ret

;=========================================================================
; Common memory (always mapped, lives in bank 3)
;=========================================================================
        .area _COMMONMEM

_plt_monitor:
_plt_reboot:
	; Call _plt_trace using SDCC's sdcccall(0) stack convention
	; (arg at SP+4 on callee entry): push the byte, inc sp to strip
	; the F padding, then push A for noopt-preserve, then call.
	ld a, #0xFE
	push af
	inc sp
	push af
	call _plt_trace
	pop af
	inc sp
	di
	; Death frame in dbg[0..15] (must not be wiped by later capture):
	;  0..1  caller RA
	;  2..3  panic_ptr
	;  4     callno
	;  5     insys
	;  6..8  u_page[0..2]
	;  9..11 mpgsel[0..2]
	;  12..13 u_error
	;  14..15 SP
	ld hl, #0
	add hl, sp
	ld a, (hl)
	ld (_sprinter_dbg + 0), a
	inc hl
	ld a, (hl)
	ld (_sprinter_dbg + 1), a
	ld hl, (_sprinter_last_panic_ptr)
	ld a, l
	ld (_sprinter_dbg + 2), a
	ld a, h
	ld (_sprinter_dbg + 3), a
	ld a, (_udata + U_DATA__U_CALLNO)
	ld (_sprinter_dbg + 4), a
	ld a, (_udata + U_DATA__U_INSYS)
	ld (_sprinter_dbg + 5), a
	ld a, (_udata + U_DATA__U_PAGE)
	ld (_sprinter_dbg + 6), a
	ld a, (_udata + U_DATA__U_PAGE + 1)
	ld (_sprinter_dbg + 7), a
	ld a, (_udata + U_DATA__U_PAGE + 2)
	ld (_sprinter_dbg + 8), a
	ld a, (mpgsel_cache)
	ld (_sprinter_dbg + 9), a
	ld a, (mpgsel_cache + 1)
	ld (_sprinter_dbg + 10), a
	ld a, (mpgsel_cache + 2)
	ld (_sprinter_dbg + 11), a
	ld hl, (_udata + U_DATA__U_ERROR)
	ld a, l
	ld (_sprinter_dbg + 12), a
	ld a, h
	ld (_sprinter_dbg + 13), a
	ld hl, #0
	add hl, sp
	ld a, l
	ld (_sprinter_dbg + 14), a
	ld a, h
	ld (_sprinter_dbg + 15), a
	ld hl, (_sprinter_last_panic_ptr)
	ld a, h
	or l
	jr nz, plt_monitor_hang
	; Non-panic monitor entry (e.g. unexpected switchin return path
	; used to call here): keep the death frame and return so bring-up
	; can continue to the next real failure.
	ret
plt_monitor_hang:
	halt
	jr plt_monitor_hang

plt_interrupt_all:
        ret

;=========================================================================
; sprinter_bringup_int - minimal IRQ stub used during platform bring-up.
;
; Any IM2 vector (CTC, SIO, ULA FRAME, ISA, etc) is routed here via the
; table at E000..E100 (I=E0, fill E1 → stub at E1E1).  We acknowledge
; the interrupt with `reti` but leave IFF1 cleared so the kernel stays
; in its post-`di` state.  This is a workaround for FUZIX's core
; interrupt_handler exit which always clears _int_disabled and `ei`s --
; once that runs a single stray IRQ latches the CPU in an interrupt
; loop and main-flow progress stalls.  Once the kernel is stable we'll
; swap this out for the real dispatcher.
;=========================================================================
sprinter_bringup_int:
	; Bring-up safety mode: absorb all IM2 IRQs unconditionally.
	; We still mark interrupts as disabled in common state so any code
	; sampling _int_disabled stays consistent with the hardware IFF1=0.
	; Note: on IRQ accept the CPU clears IFF1+IFF2, so RETI leaves
	; IFF1 clear — but only if nothing re-EI'd afterward.  tty waits
	; must not EI while _sprinter_bringup_noei is set (see below).
	push af
	push hl
	ld hl, #_int_disabled
	ld (hl), #1
	pop hl
	pop af
	reti

;=========================================================================
; sprinter_psleep_tty_ei / sprinter_psleep_maybe_ei
;
; EI gates for core do_psleep (EARLY_TRACE) PID1 tty busy-poll.
; Live in COMMONMEM so banked C never samples _sprinter_bringup_noei
; (that previously regressed /init).  kbd_poll / timer_interrupt stay
; as C calls from process.c — they are banked (CODE3 / CODE1) and need
; SDCC bank stubs; a raw CALL from here would hit the wrong overlay.
;
;   tty_ei:   EI only when !bringup_noei (before poll)
;   maybe_ei: same, after clearing p_wait (matches unix_pop skip)
;
; zxevo can HALT under a real interrupt_handler; Sprinter still uses
; the absorber above, so EI during sh console read walks into FONT.
;=========================================================================
_sprinter_psleep_tty_ei:
_sprinter_psleep_maybe_ei:
	ld a, (_sprinter_bringup_noei)
	or a
	ret nz
	ei
	ret

;=========================================================================
; sprinter_rst38_stub - fatal RST 38 / IM1 trap logger.
;
; User bring-up should not be reaching 0x0038 at all while IFF1 is clear.
; If it does, record the trap and freeze so the emulator dump shows where
; execution came from.  For a real RST 38 the CPU has already pushed the
; return PC; we snapshot that from the current SP.
;=========================================================================
sprinter_rst38_stub:
		ld a, b
		ld (_sprinter_dbg + 4), a
		ld a, c
		ld (_sprinter_dbg + 5), a
		ld a, d
		ld (_sprinter_dbg + 6), a
		ld a, e
		ld (_sprinter_dbg + 7), a
		ld a, h
		ld (_sprinter_dbg + 8), a
		ld a, l
		ld (_sprinter_dbg + 9), a
		push ix
		pop hl
		ld a, l
		ld (_sprinter_dbg + 10), a
		ld a, h
		ld (_sprinter_dbg + 11), a
		push iy
		pop hl
		ld a, l
		ld (_sprinter_dbg + 12), a
		ld a, h
		ld (_sprinter_dbg + 13), a
		push af
		pop hl
		ld a, l
		ld (_sprinter_dbg + 14), a
		ld a, h
		ld (_sprinter_dbg + 15), a
		ld hl, #_sprinter_rst38_count
		ld a, (hl)
		or a
		jp nz, rst38_hang
		inc (hl)
		ld hl, #0
		add hl, sp
		ld (_sprinter_rst38_sp), hl
		ld e, (hl)
		ld a, e
		ld (_sprinter_rst38_ret), a
		inc hl
		ld d, (hl)
		ld a, d
		ld (_sprinter_rst38_ret + 1), a
		; Keep the rest of the frame in dedicated rst38_* latches only —
		; dbg[] is capped at 16 bytes for the IM2 COMMONDATA ceiling.
		ld a, (_udata + U_DATA__U_INSYS)
		ld (_sprinter_rst38_insys), a
		ld a, (_udata + U_DATA__U_CALLNO)
		ld (_sprinter_rst38_callno), a
		ld a, (_udata + U_DATA__U_ININTERRUPT)
		ld (_sprinter_rst38_inirq), a
		ld a, (_udata + U_DATA__U_PAGE)
		ld (_sprinter_rst38_up0), a
		ld a, (_udata + U_DATA__U_PAGE + 1)
		ld (_sprinter_rst38_up1), a
		ld a, (_udata + U_DATA__U_PAGE + 2)
		ld (_sprinter_rst38_up2), a
		ld a, (mpgsel_cache)
		ld (_sprinter_rst38_mp0), a
		ld a, (mpgsel_cache + 1)
		ld (_sprinter_rst38_mp1), a
		ld a, (mpgsel_cache + 2)
		ld (_sprinter_rst38_mp2), a
		ld a, i
		ld (_sprinter_rst38_i), a
		ex de, hl
		dec hl
		ld a, (hl)
		ld (_sprinter_dbg), a
		inc hl
		ld a, (hl)
		ld (_sprinter_dbg + 1), a
		inc hl
		ld a, (hl)
		ld (_sprinter_dbg + 2), a
		inc hl
		ld a, (hl)
		ld (_sprinter_dbg + 3), a
rst38_hang:
		halt
		jr rst38_hang

;=========================================================================
; sprinter_nmi_stub - absorb NMI without printing / panicking.
;
; Z80 NMI pushes PC and jumps to 0x0066.  do_program_vectors writes
; `JP sprinter_nmi_stub` there.  We increment a counter so the trace
; of how often it fires is visible, then RETN to return control to the
; interrupted code.  RETN restores IFF1 from IFF2 (which is the saved
; pre-NMI interrupt-enable state), so we don't change the kernel's
; IRQ state.
;=========================================================================
sprinter_nmi_stub:
        push af
        push hl
        ld hl, #_sprinter_nmi_count
        inc (hl)
        pop hl
        pop af
        retn

        .globl _sprinter_nmi_count

;=========================================================================
; sprinter_null_stub - NULL-vector trap / libc __syscall bring-up fix.
;
; Stock Z80 libc does `call __text` from __syscall.  relocbin is supposed
; to turn that into `call PROGLOAD` (sys_stubs).  Some user binaries
; (notably /bin/sh) ship a reloc stream that never patches this site, so
; the call remains `CD 00 00` and the first brk() lands here.
;
; Detect that pattern (return address points at `ret nc` / 0xD0, call
; site is still `CD xx 00`) and tail into unix_syscall_entry with A still
; holding the syscall number.  Real NULL jumps still hang.
;=========================================================================
sprinter_null_stub:
	; Kernel 0x0000 and user 0x002C land here.  User 0x0000 is retargeted
	; to unix_syscall_entry on doexec map-apply for libc `call 0`.
	ld hl, #_sprinter_nullh_count
	inc (hl)
	ld a, l
	ld (_sprinter_dbg + 12), a
	ld a, h
	ld (_sprinter_dbg + 13), a
	ld hl, #0
	add hl, sp
	ld a, (hl)
	ld (_sprinter_dbg + 14), a
	inc hl
	ld a, (hl)
	ld (_sprinter_dbg + 15), a
null_hang:
	halt
	jr null_hang

;=========================================================================
; devide_read_data / devide_write_data - IDE bulk data transfer
;
; These must live in _COMMONMEM (WIN3) rather than the bank 1 code page
; they were originally compiled into: the body installs a user or
; buffer-cache mapping over WIN0..WIN2 via map_proc_always / map_buffers
; / map_for_swap before the actual IN/OUT loop.  If the transfer code
; itself lived in WIN1 or WIN2 the mapping change would unmap the
; instructions currently being fetched and the CPU would start
; executing whatever bytes were on the new page.
;
; void devide_read_data(uint8_t *dptr)
; void devide_write_data(uint8_t *dptr)
;
; td_raw selects the destination view:
;   0 -> map_buffers      (kernel buffer pool)
;   1 -> map_proc_always  (current process user pages)
;   2 -> map_for_swap(td_page) (swap slot, when SWAPDEV)
;
; map_kernel_restore on exit returns the kernel mapping so the caller
; continues with WIN0..WIN2 set to the kernel banks they expected.
;=========================================================================
; Sprinter IDE bulk transfer follows the BIOS HDRIVER6 pattern:
;   - for td_raw == 0 (kernel buffer) explicitly map buffer pages with
;     map_buffers, transfer, then restore kernel mapping.
;   - for td_raw == 1 (user) / 2 (swap) map target view first, read/write
;     directly via (HL), then restore kernel mapping.
; Removing the _sprinter_ide_bounce / ldir dance eliminates the window
; between the two 256-byte halves where banking and kstack could drift;
; this mirrors HDRIVER6's "DI, map target into WIN3, tight INI loop, EI"
; idiom without moving MPGSEL_3.
_devide_read_data:
        di
	ld hl, #4
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)
	ex de, hl			; HL = dptr

	ld a, (_td_raw)
	cp #2
	jr z, ide_rd_swap
	or a
	jr z, ide_rd_buf
	jr ide_rd_user
ide_rd_buf:
	push hl
	call map_buffers
	pop hl
	jr ide_rd_xfer
ide_rd_swap:
	push hl
	ld a, (_td_page)
	call map_for_swap
	pop hl
	jr ide_rd_xfer
ide_rd_user:
	push hl
	call map_proc_always
	pop hl
ide_rd_xfer:
	ld bc, #0x0050		; Sprinter IDE read data port, B=0 => 256 INIs
	inir
	ld bc, #0x0050
	inir
	call map_kernel_restore
ide_rd_done:
	ei
	ret

_devide_write_data:
	di
	ld hl, #4
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)
	ex de, hl			; HL = dptr

	ld a, (_td_raw)
	cp #2
	jr z, ide_wr_swap
	or a
	jr z, ide_wr_buf
	jr ide_wr_user
ide_wr_buf:
	push hl
	call map_buffers
	pop hl
	jr ide_wr_xfer
ide_wr_swap:
	push hl
	ld a, (_td_page)
	call map_for_swap
	pop hl
	jr ide_wr_xfer
ide_wr_user:
	push hl
	call map_proc_always
	pop hl
ide_wr_xfer:
	ld bc, #0x0150		; Sprinter IDE write data port
	otir
	ld bc, #0x0150
	otir
	call map_kernel_restore
ide_wr_done:
	ei
	ret

;=========================================================================
; program_vectors - set exception vectors for a new process
;=========================================================================
_program_vectors:
	di
	; Different call sites currently reach this helper with two stack
	; layouts:
	;   1) standard sdcc call:       RET, arg          (arg at SP+2)
	;   2) banked/noopt wrapper:     RET, AF, arg      (arg at SP+4)
	; Probe SP+2 first, then SP+4, and keep the first pointer that
	; passes pv_ptr_valid() to avoid silently mapping 0x08/0x09/0x0A.
	ld hl, #2
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)
	call pv_ptr_valid
	jr c, pv_arg_ok

	ld hl, #4
	add hl, sp
	ld e, (hl)
	inc hl
	ld d, (hl)
	call pv_ptr_valid
	jr c, pv_arg_ok
	xor a
	ld d, a
	ld e, a
pv_arg_ok:
	ex de, hl
	call pv_program_vectors_common
	ret

; Validate pointer to process page map (4 bytes: page0..page3).
; IN: DE = pointer
; OUT: C=1 if valid (or NULL), C=0 if the 4 bytes at DE don't look like
;      a user page map.  The pointer itself may live anywhere in the
;      kernel address space (0x0000..0xFFFF) -- on this platform
;      `_udata + U_DATA__U_PAGE` is in common memory at 0xEExx, so an
;      earlier version that rejected pointers with D >= 0x80 was wrong
;      and caused program_vectors to silently fall back to mapping the
;      kernel, leaving user page #0 without the `JP null_handler` stub
;      and tripping null_pointer_trap on the first IRQ after exec.
pv_ptr_valid:
	ld a, d
	or e
	jr z, pv_ptr_ok			; NULL means kernel mapping
	push hl
	push bc
	ld h, d
	ld l, e
	ld b, #4
pv_ptr_loop:
	ld a, (hl)
	cp #0x08
	jr c, pv_ptr_bad_pop
	cp #0x80
	jr nc, pv_ptr_bad_pop
	inc hl
	djnz pv_ptr_loop
	pop bc
	pop hl
pv_ptr_ok:
	scf
	ret
pv_ptr_bad_pop:
	pop bc
	pop hl
	or a
	ret


do_program_vectors:
	; Sprinter bring-up: do not blank the whole low 0x80 bytes.
	; Current user binaries make real use of low addresses, and wiping
	; 0x0000..0x007F destroys startup code/data before first userspace
	; instructions run. Only patch the required vector slots.

		; Install the permanent exception vectors.  IM2 intentionally stays
		; on sprinter_bringup_int during kernel
		; bring-up: enabling FUZIX's interrupt_handler while the kernel
		; is still mapping memory for PID1 causes a runaway dispatch loop
		; (the handler's exit path clears _int_disabled and `ei`s, and
		; the Sprinter ULA FRAME pin is asserted continuously during
		; boot).  The first _doexec call re-arms the IM1/IM2 vectors to
		; the real handler (see sprinter_arm_irq).
		;
		; Keep 0x0038 on a dedicated fatal stub instead of the generic IRQ
		; absorber.  If execution falls through user low-page garbage and
		; fetches 0xFF, the CPU executes RST 38h and pushes the real return
		; address.  Recording that address tells bring-up whether we took a
		; genuine interrupt or simply jumped into an 0xFF-filled hole.
		ld a, #0xC3			; JP instruction
		ld (0x0038), a
		ld hl, #sprinter_rst38_stub
		ld (0x0039), hl

	; set restart vector for FUZIX system calls (RST 30h)
	ld (0x0030), a
	ld hl, #unix_syscall_entry
	ld (0x0031), hl

	; null trap at 0x0000 (kernel pages).  User doexec map-apply
	; retargets this to unix_syscall_entry for libc `call 0`.
	ld (0x0000), a
	ld hl, #sprinter_null_stub
	ld (0x0001), hl

	; NMI vector at 0x0066.  During bring-up we do NOT want the
	; FUZIX default nmi_handler (which prints "[NMI]" and drops into
	; plt_monitor) -- on Sprinter some edge fires NMI after /init
	; enters user space and we need the system to stay alive long
	; enough to figure out why.  Point the vector at a local stub
	; that simply RETNs so NMIs are absorbed silently.
	ld (0x0066), a
	ld hl, #sprinter_nmi_stub
	ld (0x0067), hl

	; Do not rewrite the IM2 vector page here.  During bring-up the
	; user/common trace state now lives in 0xFE00.., and re-filling the
	; old 257-byte table on every exec silently wipes the very latches
	; we need to debug the first user->kernel->user boundary.  The boot
	; path already seeded the IM2 table once in init_hardware(), and
	; current userland runs with IFF1=0, so preserving common-data wins.

	ret

	.area _COMMONMEM

; Apply mpgsel_cache[0..2] from always-mapped common.  After OUTing a
; user page into MPGSEL_0, WIN0 _CODE is gone — so callers that still have
; a saved HL / return path must jp to map_apply_pophl (below), not return
; into WIN0.
map_apply_cached:
	ld a, (mpgsel_cache)
	out (MPGSEL_0), a
	ld a, (mpgsel_cache + 1)
	out (MPGSEL_1), a
	ld a, (mpgsel_cache + 2)
	out (MPGSEL_2), a
	ld a, (_spr_doexec_seen)
	cp #1
	jr z, map_apply_vecs_oneshot
	; After /bin/sh, re-install low vectors on every user map.
	; User code / failed opens have been seen to leave 0x0000 as
	; BA BA and 0x0038 as FF (RST38 stack-eat loop).
	ld a, (_sprinter_bringup_noei)
	or a
	jr z, map_apply_cached_done
	jr map_apply_install_vecs
map_apply_vecs_oneshot:
	ld a, #2
	ld (_spr_doexec_seen), a
	ld a, (mpgsel_cache)
	ld (_spr_doexec_m0), a
	ld a, (mpgsel_cache + 1)
	ld (_spr_doexec_m1), a
	ld a, (mpgsel_cache + 2)
	ld (_spr_doexec_m2), a
map_apply_install_vecs:
	; User WIN0 is live: re-install vectors.  Syscall site rewrite is
	; done from C (sprinter_patch_syscalls) before doexec — a full
	; [PROGLOAD..u_break) walk here hung V7 (~30KB) before _doexec.
	; libc `call 0` must reach unix_syscall_entry (null_stub here
	; hung /bin/sh at null_hang after ioctl/read once C000 was fixed).
	; /bin/sh refreshes unix@0 again from _doexec when noei is set
	; (program_vectors may have put null_stub back after this shot).
	ld a, #0xC3
	ld (0x0000), a
	ld hl, #unix_syscall_entry
	ld (0x0001), hl
	ld (0x002C), a
	ld hl, #sprinter_null_stub
	ld (0x002D), hl
	ld (0x0030), a
	ld hl, #unix_syscall_entry
	ld (0x0031), hl
	ld (0x0038), a
	ld hl, #sprinter_rst38_stub
	ld (0x0039), hl
map_apply_cached_done:
	ret

; Stack: [saved_hl][ret].  Apply banks then restore HL and return.
map_apply_pophl:
	call map_apply_cached
	pop hl
	ret

; Syscall entry runs with user WIN0 mapped.  map_kernel must live in
; always-visible common — a WIN0 implementation is unmapped and the
; call fetches user garbage (RST38 at first write).
;
; Apply _kernel_pages (not hardcoded BANK1): banked CODE2/3 overlays
; keep their pages here, and forcing 0x49/0x4A unmapped the caller
; (panic: invalid dev during early boot).
	.globl _map_kernel
	.globl map_kernel
	.globl map_kernel_di
	.globl map_kernel_restore
	.globl map_buffers
; COMMONMEM / live WIN3 stack. Syscall entry has already set u_insys;
; reset write progress before readwrite's zero-length/error early returns.
; The bring-up return guard must not reuse the preceding write's u_done.
; Preserve AF and IRQ state, then map WIN0/1/2 through map_kernel below.
map_kernel_di:
	push af
	ld a, (_udata + U_DATA__U_INSYS)
	or a
	jr z, mkdi_done
	ld a, (_udata + U_DATA__U_ININTERRUPT)
	or a
	jr nz, mkdi_done
	ld a, (_udata + U_DATA__U_CALLNO)
	cp #8
	jr nz, mkdi_done
	ld a, (mpgsel_cache)
	cp #0x40
	jr nc, mkdi_done
	xor a
	ld (_udata + 0x9F), a
	ld (_udata + 0xA0), a
mkdi_done:
	pop af
_map_kernel:
map_kernel:
map_buffers:
map_kernel_restore:
	push af
	; WIN0 must always be kernel CODE (0x48).  _kernel_pages[0] can hold
	; a user page after map_proc; remapping that hides i_tab → iobad.
	ld a, #0x48
	ld (_kernel_pages), a
	ld (mpgsel_cache), a
	out (MPGSEL_0), a
	ld a, (_kernel_pages + 1)
	ld (mpgsel_cache + 1), a
	out (MPGSEL_1), a
	ld a, (_kernel_pages + 2)
	ld (mpgsel_cache + 2), a
	out (MPGSEL_2), a
	pop af
	ret

; Remap WIN0 to kernel CODE only.  Must live in common: callers invoke this
; while WIN0 still holds the user page after readi/uput.  Do NOT touch WIN1/2
; — CODE2/CODE3 overlays would be unmapped under the caller.
	.globl _spr_map_win0_k
_spr_map_win0_k:
	push af
	ld a, #0x48
	ld (_kernel_pages), a
	ld (mpgsel_cache), a
	out (MPGSEL_0), a
	pop af
	ret

pv_program_vectors_common:
	ld a, h
	or l
	jr nz, pv_map_ptr_ok
	ld hl, #_kernel_pages
pv_map_ptr_ok:
	push de
	ld a, (hl)
	cp #0x08
	jr c, pv_b0_bad
	cp #0x50
	jr c, pv_b0_ok
pv_b0_bad:
	ld a, #0x08
pv_b0_ok:
	ld e, a
	inc hl
	ld a, (hl)
	cp #0x08
	jr c, pv_b1_bad
	cp #0x50
	jr c, pv_b1_ok
pv_b1_bad:
	ld a, #0x09
pv_b1_ok:
	ld (mpgsel_cache + 1), a
	out (MPGSEL_1), a
	inc hl
	ld a, (hl)
	cp #0x08
	jr c, pv_b2_bad
	cp #0x50
	jr c, pv_b2_ok
pv_b2_bad:
	ld a, #0x0A
pv_b2_ok:
	ld (mpgsel_cache + 2), a
	out (MPGSEL_2), a
	ld a, e
	ld (mpgsel_cache), a
	out (MPGSEL_0), a

	ld a, #0xC3
	ld (0x0038), a
	ld hl, #sprinter_rst38_stub
	ld (0x0039), hl

	ld (0x0030), a
	ld hl, #unix_syscall_entry
	ld (0x0031), hl

	; Trap true NULL jumps while user page 0 is mapped.  libc `call 0`
	; is retargeted to unix_syscall_entry in map_apply_cached (once
	; per doexec).  Installing the syscall entry here too raced with
	; early /init dup/IDE and hung in null_stub under kernel map.
	ld (0x0000), a
	ld hl, #sprinter_null_stub
	ld (0x0001), hl

	ld (0x0066), a
	ld hl, #sprinter_nmi_stub
	ld (0x0067), hl

	ld hl, #_kernel_pages
	inc hl
	ld a, (hl)
	cp #0x49
	jr nc, pv_kb1_ok
	ld a, #0x49
pv_kb1_ok:
	ld (mpgsel_cache + 1), a
	out (MPGSEL_1), a
	inc hl
	ld a, (hl)
	cp #0x4A
	jr nc, pv_kb2_ok
	ld a, #0x4A
pv_kb2_ok:
	ld (mpgsel_cache + 2), a
	out (MPGSEL_2), a
	dec hl
	dec hl
	ld a, (hl)
	cp #0x48
	jr nc, pv_kb0_ok
	ld a, #0x48
pv_kb0_ok:
	ld (mpgsel_cache), a
	out (MPGSEL_0), a
	pop de
	ret

	.area _CODE

;=========================================================================
; Memory management
; - kernel pages:     0 - 2
; - common page:      3
; - user space pages: 4 - 79 (0x04 - 0x4F)
;=========================================================================

;=========================================================================
; map_proc_always - map process pages
; Inputs: page table address in #U_DATA__U_PAGE
; Outputs: none; all registers preserved
;=========================================================================
map_proc_always:
map_proc_save:
map_proc_always_di:
	push hl
	push af
	push de
	ld a, (_spr_doexec_call_seen)
	or a
	jr nz, map_proc_always_probe_done
	ld a, (_spr_doexec_arm)
	or a
	jr nz, map_proc_always_probe_arm
	; Fallback for the current bring-up edge: if C reached the
	; "about to call doexec()" marker (sprinter_dbg[15]=0xEA),
	; capture the stack frame even when _spr_doexec_arm got lost.
	ld a, (_sprinter_dbg + 15)
	cp #0xEA
	jr nz, map_proc_always_probe_done
	ld a, #2
	jr map_proc_always_probe_mark
map_proc_always_probe_arm:
	ld a, #1
map_proc_always_probe_mark:
	ld (_spr_doexec_call_seen), a
	ld (_sprinter_dbg + 14), a
	ld hl, #0
	add hl, sp
	ld de, #6
	add hl, de
	ld (_spr_doexec_call_sp), hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld (_spr_doexec_call_ra0), de
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld (_spr_doexec_call_ra1), de
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld (_spr_doexec_call_af), de
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld (_spr_doexec_call_start), de
	; start word already in _spr_doexec_call_*; keep dbg[] ≤16 for IM2.
map_proc_always_probe_done:
	pop de
	pop af
	ld hl, #_udata + U_DATA__U_PAGE
	jp map_proc_2_pophl_ret

;=========================================================================
; map_proc - map process or kernel pages
; Inputs: page table address in HL, map kernel if HL == 0
; Outputs: none; A and HL destroyed
;=========================================================================
map_proc:
map_proc_di:
	ld a, h
	or l				; HL == 0?
	jp z, map_kernel		; common implementation
	; Historically fell into force_bank1 (not map_proc_2).  Restoring
	; that until map_proc callers are audited — jp map_proc_2 zeroed
	; kernel_pages WIN1/2 during bring-up.
	; fall through

_sprinter_force_bank1:
	ld bc, #MAP_BANK1
	ld (_kernel_pages + 1), bc
	ld (mpgsel_cache + 1), bc
	ld a, c
	out (MPGSEL_1), a
	ld a, b
	call set_mpgsel2_safe
	ret

;=========================================================================
; map_proc_2 - map process or kernel pages
; Inputs: page table address in HL
; Outputs: none, HL destroyed
;=========================================================================
map_proc_2:
		push de
		push af
		ld a, (_spr_doexec_arm)
		or a
		jr z, map_proc_2_probe_skip
		push hl
		ld de, #_udata + U_DATA__U_PAGE
		or a
		sbc hl, de
		pop hl
		jr nz, map_proc_2_probe_skip
		xor a
		ld (_spr_doexec_arm), a
		ld a, #1
		ld (_spr_doexec_seen), a
		ld (_spr_doexec_map_ptr), hl
		ld a, (hl)
		ld (_spr_doexec_u0), a
		inc hl
		ld a, (hl)
		ld (_spr_doexec_u1), a
		inc hl
		ld a, (hl)
		ld (_spr_doexec_u2), a
		inc hl
		ld a, (hl)
		ld (_spr_doexec_u3), a
		dec hl
		dec hl
		dec hl
map_proc_2_probe_skip:
		pop af
		pop de
		ld a, (hl)
		cp #0x48
		jr nz, map_proc_2_ptr_ok
	inc hl
	ld a, (hl)
	dec hl
	cp #0x49
	jr z, map_proc_2_ptr_ok
	cp #0x4C
	jr z, map_proc_2_ptr_ok
	cp #0x4E
	jr z, map_proc_2_ptr_ok
	ld hl, #_udata + U_DATA__U_PAGE
map_proc_2_ptr_ok:
	push de
	push af
	; Fill mpgsel_cache only.  The actual OUT (MPGSEL_*) must run from
	; _COMMONMEM: this routine lives in WIN0 _CODE, and OUTing user page
	; 0 into MPGSEL_0 would unmap the next fetch (doexec died at seen=1
	; with m0/m1/m2 still 00).
	ld a, (hl)			; page for bank #0
	cp #0x08
	jr c, map_proc_2_b0_bad
	cp #0x50
	jr c, map_proc_2_b0_ok
map_proc_2_b0_bad:
	ld a, #0x08
map_proc_2_b0_ok:
	ld (mpgsel_cache), a
	inc hl
	ld a, (hl)			; page for bank #1
	cp #0x08
	jr c, map_proc_2_b1_bad
	cp #0x50
	jr c, map_proc_2_b1_ok
map_proc_2_b1_bad:
	ld a, #0x09
map_proc_2_b1_ok:
	ld (mpgsel_cache + 1), a
	inc hl
	ld a, (hl)			; page for bank #2
	cp #0x08
	jr c, map_proc_2_b2_bad
	cp #0x50
	jr c, map_proc_2_b2_ok
map_proc_2_b2_bad:
	ld a, #0x0A
map_proc_2_b2_ok:
	cp #0x50
	jr c, map_proc_2_b2_cached
	ld a, #0x4A
map_proc_2_b2_cached:
	ld (mpgsel_cache + 2), a
	pop af
	pop de
	; Cache filled; WIN0 still kernel.  Direct callers jp apply; the
	; pophl helper calls us then jp's map_apply_pophl in common.
	jp map_apply_cached

; HL = page table, stack = [saved_hl][ret_to_caller].
; Fill in WIN0 (safe), apply+return from common (WIN0 may become user).
map_proc_2_pophl_ret:
	call map_proc_2_fill
	jp map_apply_pophl

; Same body as map_proc_2 but returns after fill (no apply).
map_proc_2_fill:
	push de
	push af
	ld a, (_spr_doexec_arm)
	or a
	jr z, map_proc_2_fill_skip
	push hl
	ld de, #_udata + U_DATA__U_PAGE
	or a
	sbc hl, de
	pop hl
	jr nz, map_proc_2_fill_skip
	xor a
	ld (_spr_doexec_arm), a
	ld a, #1
	ld (_spr_doexec_seen), a
	ld (_spr_doexec_map_ptr), hl
	ld a, (hl)
	ld (_spr_doexec_u0), a
	inc hl
	ld a, (hl)
	ld (_spr_doexec_u1), a
	inc hl
	ld a, (hl)
	ld (_spr_doexec_u2), a
	inc hl
	ld a, (hl)
	ld (_spr_doexec_u3), a
	dec hl
	dec hl
	dec hl
map_proc_2_fill_skip:
	pop af
	pop de
	ld a, (hl)
	cp #0x48
	jr nz, map_proc_2_fill_ptr
	inc hl
	ld a, (hl)
	dec hl
	cp #0x49
	jr z, map_proc_2_fill_ptr
	cp #0x4C
	jr z, map_proc_2_fill_ptr
	cp #0x4E
	jr z, map_proc_2_fill_ptr
	ld hl, #_udata + U_DATA__U_PAGE
map_proc_2_fill_ptr:
	push de
	push af
	ld a, (hl)
	cp #0x08
	jr c, map_proc_2_fill_b0b
	cp #0x50
	jr c, map_proc_2_fill_b0o
map_proc_2_fill_b0b:
	ld a, #0x08
map_proc_2_fill_b0o:
	ld (mpgsel_cache), a
	inc hl
	ld a, (hl)
	cp #0x08
	jr c, map_proc_2_fill_b1b
	cp #0x50
	jr c, map_proc_2_fill_b1o
map_proc_2_fill_b1b:
	ld a, #0x09
map_proc_2_fill_b1o:
	ld (mpgsel_cache + 1), a
	inc hl
	ld a, (hl)
	cp #0x08
	jr c, map_proc_2_fill_b2b
	cp #0x50
	jr c, map_proc_2_fill_b2o
map_proc_2_fill_b2b:
	ld a, #0x0A
map_proc_2_fill_b2o:
	cp #0x50
	jr c, map_proc_2_fill_b2c
	ld a, #0x4A
map_proc_2_fill_b2c:
	ld (mpgsel_cache + 2), a
	pop af
	pop de
	ret

sanitize_kpages:
	ld a, (_kernel_pages)
	cp #0x48
	jr nz, sanitize_kpages_bad
	ld a, (_kernel_pages + 1)
	ld c, a
	ld a, (_kernel_pages + 2)
	ld b, a
	call sanitize_bc_map
	ld a, c
	ld (_kernel_pages + 1), a
	ld (mpgsel_cache + 1), a
	ld a, b
	ld (_kernel_pages + 2), a
	ld (mpgsel_cache + 2), a
	ld a, (_kernel_pages + 3)
	cp #0x4B
	jr nz, sanitize_kpages_bad
	ret
sanitize_kpages_bad:
	ld a, #0x48
	ld (_kernel_pages), a
	ld (mpgsel_cache), a
	ld a, #0x49
	ld (_kernel_pages + 1), a
	ld (mpgsel_cache + 1), a
	ld a, #0x4A
	ld (_kernel_pages + 2), a
	ld (mpgsel_cache + 2), a
	ld a, #0x4B
	ld (_kernel_pages + 3), a
	ld (mpgsel_cache + 3), a
	ld (top_bank), a
	out (MPGSEL_3), a
	ret

;=========================================================================
; map_restore - restore a saved page mapping
;=========================================================================
map_restore:
	push hl
	ld hl, #map_savearea
	jp map_proc_2_pophl_ret

;=========================================================================
; map_save_kernel - save the current page mapping and switch to kernel
;=========================================================================
map_save_kernel:
	push hl
	ld hl, (mpgsel_cache)
	ld (map_savearea), hl
	ld hl, (mpgsel_cache+2)
	ld (map_savearea+2), hl
	ld hl, #_kernel_pages
	jp map_proc_2_pophl_ret

;=========================================================================
; map_proc_save_u / map_kernel_restore_u - usermem private save/restore
;=========================================================================
map_proc_save_u:
	push hl
	ld hl, (mpgsel_cache)
	ld (map_savearea_user), hl
	ld hl, (mpgsel_cache+2)
	ld (map_savearea_user+2), hl
	ld hl, #_udata + U_DATA__U_PAGE
	jp map_proc_2_pophl_ret

map_kernel_restore_u:
	push hl
	push de
	push af
	ld hl, #map_savearea_user
	ld a, (hl)			; page for bank #0
	cp #0x08
	jr c, map_kernel_restore_u_fallback
	cp #0x50
	jr nc, map_kernel_restore_u_fallback
	jr map_kernel_restore_u_b0_ok
map_kernel_restore_u_b0_bad:
	ld a, #0x08
map_kernel_restore_u_b0_ok:
	ld (mpgsel_cache), a
	out (MPGSEL_0), a
	inc hl
	ld a, (hl)			; page for bank #1
	cp #0x08
	jr c, map_kernel_restore_u_b1_bad
	cp #0x50
	jr c, map_kernel_restore_u_b1_ok
map_kernel_restore_u_b1_bad:
	ld a, #0x09
map_kernel_restore_u_b1_ok:
	ld (mpgsel_cache + 1), a
	out (MPGSEL_1), a
	inc hl
	ld a, (hl)			; page for bank #2
	cp #0x08
	jr c, map_kernel_restore_u_b2_bad
	cp #0x50
	jr c, map_kernel_restore_u_b2_ok
map_kernel_restore_u_b2_bad:
	ld a, #0x0A
map_kernel_restore_u_b2_ok:
	call set_mpgsel2_safe
	pop af
	pop de
	pop hl
	ret

map_kernel_restore_u_fallback:
	pop af
	pop de
	pop hl
	jp map_kernel

;=========================================================================
; map_for_swap - map a page into bank 1 for swap I/O
; Inputs: A = page
; Outputs: none
;=========================================================================
map_for_swap:
	cp #0x08
	jr c, map_for_swap_bad
	cp #0x50
	jr c, map_for_swap_ok
map_for_swap_bad:
	ld a, #0x49
map_for_swap_ok:
	ld (mpgsel_cache + 1), a
	out (MPGSEL_1), a
	ret

;=========================================================================
; _copy_common - copy the common page to a new physical page
;=========================================================================
_copy_common:
	pop bc			; return
	pop hl			; (unused)
	pop de			; target page number
	push de
	push hl
	push bc
	ld a, e
	call map_for_swap	; map target page to bank 1 (0x4000)
	ld hl, #0xF200
	ld de, #0x7200		; 0x4000 + 0x3200 (offset within bank)
	ld bc, #0x0E00		; copy 3.5K of common area
	ldir
	jp map_kernel

;=========================================================================
; _sprinter_seed_common - full 16K copy of the running kernel common page
; (WIN3) into the target page. Used at boot or before PID1's first fork
; to initialise its owned common page with the live stack and kernel code.
;
; Unlike _copy_common, which only ships 3.5K of high kernel code from
; 0xF200, this routine copies the entire 0xC000-0xFFFF range so udata,
; the kernel stack and the common-mem code all survive being ported
; into the child bank by fork_copy.
;
; C prototype: void sprinter_seed_common(uint8_t target_page);
;=========================================================================
_sprinter_seed_common:
	pop bc			; return address
	pop hl			; (unused)
	pop de			; target page number (E = page, D = padding)
	push de
	push hl
	push bc
	; Called from create_init()/map_init() during boot, IRQs are
	; already off here.  We do NOT ei inside this routine.
	ld a, e
	.globl _spr_seed_top
; Register entry: A = allocated common page, WIN0 must hold kernel CODE.
; Map WIN1 via A, copy the live WIN3 stack/code, then switch WIN3 via A.
; Return with IRQs disabled.
_spr_seed_top:
	di
	call map_for_swap	; map target page at WIN1 (0x4000-0x7FFF)
				; A now holds the actual page (target,
				; or 0x49 if caller passed an invalid
				; value -- map_for_swap substitutes)
	push af			; save target across ldir (E is clobbered)
	; Copy 0xC000-0xFFFF (WIN3, kernel common page 0x4B) into the
	; target page mapped at WIN1 (0x4000-0x7FFF).  Single 16 KB
	; ldir - target ends up as an exact byte-for-byte copy of the
	; live kernel common, including udata, kstack and common-code.
	ld hl, #0xC000
	ld de, #0x4000
	ld bc, #0x4000
	ldir
	pop af			; A = target page again
	; Switch MPGSEL_3 to the target page.  Because target is an
	; exact copy of what was just at WIN3, SP (which lives in the
	; 0xFFxx range) still finds identical bytes after the switch:
	; our return address on stack survives, ret works, caller keeps
	; going uninterrupted.  IRQs are off (di above), so nothing can
	; push/pop between the ldir and the switch.
	;
	; Why this matters: init is the first process and never goes
	; through _switchin, which is what otherwise installs a process's
	; own common page.  Without this switch, MPGSEL_3 stays on the
	; kernel common (0x4B) while init's u_page[3] records the
	; just-seeded target page.  When init forks, fork_copy reads
	; parent's u_page[3] as the source and copies that (stale seed)
	; into the child -- but the live stack/udata are in 0x4B, not in
	; the seed page, so the child switches in on corrupt common.
	; Switching here makes init's u_page[3] and the running
	; MPGSEL_3 agree, and fork_copy then propagates the live common.
	;
	; top_bank aliases _kernel_pages[3]; both it and the cache must
	; describe the new live common after the copied stack is installed.
	out (MPGSEL_3), a	; switch first; SP still finds identical bytes
	; We are now running on the target common page.  Both mpgsel_cache
	; and top_bank live IN common, so writing them here updates the
	; target page's copy (which is what subsequent code reads once we
	; are on target).  The old kernel-common copy at 0x4B becomes
	; orphaned and is never referenced again -- init is the only
	; process and it now lives on target.
	ld (mpgsel_cache + 3), a
	ld (top_bank), a
	jp map_kernel

;=========================================================================
; outchar - output a character for kernel debug messages
; Input: A = character
;=========================================================================
outchar:
	; Save registers and output via VT
	ld (_tmpout), a
	push bc
	push de
	push hl
	push ix
	ld hl, #1
	push hl
	ld hl, #_tmpout
	push hl
	push af
	call _vtoutput
	pop af
	pop af
	pop af
	pop ix
	pop hl
	pop de
	pop bc
        ret

_plt_trace:
	push af
	push bc
	push de
	push hl

	; sdcccall(0): 8-bit argument is at SP+4 on callee entry.
	; We saved 8 more bytes above, so fetch it from SP+12 now.
	ld hl, #12
	add hl, sp
	ld a, (hl)
	ld (_sprinter_trace_last), a

	ld hl, (_sprinter_trace_idx)
	ld e, l
	ld d, #0
	push af
	ld hl, #_sprinter_trace_buf
	add hl, de
	pop af
	ld (hl), a

	ld hl, (_sprinter_trace_idx)
	inc l
	ld a, l
	cp #SPR_TRACE_LEN
	jr c, plt_trace_store_idx
	ld hl, #0
plt_trace_store_idx:
	ld (_sprinter_trace_idx), hl

	pop hl
	pop de
	pop bc
	pop af
	ret

_tmpout:
	.db 1

SPR_TRACE_LEN	.equ	1

;=========================================================================
; Data in common memory
;=========================================================================
;=========================================================================
; Banking stubs for inter-bank calls
;
; Kernel code banks:
;   Bank 1 (CODE1): pages 0x49,0x4A in WIN1,WIN2
;   Bank 2 (CODE2): pages 0x4C,0x4D in WIN1,WIN2
;   Bank 3 (CODE3): pages 0x4E,0x4F in WIN1,WIN2
;
; MAP_BANKn stores as BC: B=page_for_WIN2, C=page_for_WIN1
;=========================================================================

MAP_BANK1	.equ	0x4A49	; pages 0x49,0x4A
BANK1		.equ	0x49
MAP_BANK2	.equ	0x4D4C	; pages 0x4C,0x4D
BANK2		.equ	0x4C
MAP_BANK3	.equ	0x4F4E	; pages 0x4E,0x4F
BANK3		.equ	0x4E

	.globl __bank_0_1
	.globl __bank_0_2
	.globl __bank_0_3
	.globl __bank_1_2
	.globl __bank_1_3
	.globl __bank_2_1
	.globl __bank_2_3
	.globl __bank_3_1
	.globl __bank_3_2

	.globl __stub_0_1
	.globl __stub_0_2
	.globl __stub_0_3
	.globl __stub_1_2
	.globl __stub_1_3
	.globl __stub_2_1
	.globl __stub_2_3

__bank_0_1:
	ld bc, #MAP_BANK1
bank0:
	pop hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	push hl
	ld a, (_kernel_pages + 1)
	ld (_kernel_pages + 1), bc
	ld (mpgsel_cache + 1), bc
	ld b, a
	ld a, c
	out (MPGSEL_1), a
	inc a
	call set_mpgsel2_safe
	ex de, hl
	ld a, b
	cp #BANK1
	jr z, retbank1
	cp #BANK2
	jr z, retbank2
	call callhl
	; BANK3 and unknown: restore CODE3 (bounce/execve home).
	ld bc, #MAP_BANK3
banksetbc:
	call sanitize_bc_map
	ld (_kernel_pages + 1), bc
	ld (mpgsel_cache + 1), bc
	ld a, c
	out (MPGSEL_1), a
	ld a, b
	call set_mpgsel2_safe
	ret
retbank1:
	call callhl
	ld bc, #MAP_BANK1
	jr banksetbc
retbank2:
	call callhl
	ld bc, #MAP_BANK2
	jr banksetbc
__bank_0_2:
	ld bc, #MAP_BANK2
	jr bank0
__bank_0_3:
	ld bc, #MAP_BANK3
	jr bank0

__bank_1_2:
	ld bc, #MAP_BANK2
bank_1_x:
	pop hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	push hl
	call banksetbc
	ex de, hl
	call callhl
	ld bc, #MAP_BANK1
	jr banksetbc
__bank_1_3:
	ld bc, #MAP_BANK3
	jr bank_1_x

__bank_2_1:
	ld bc, #MAP_BANK1
bank_2_x:
	pop hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	push hl
	call banksetbc
	ex de, hl
	call callhl
	ld bc, #MAP_BANK2
	jr banksetbc
__bank_2_3:
	ld bc, #MAP_BANK3
	jr bank_2_x

__bank_3_1:
	ld bc, #MAP_BANK1
bank_3_x:
	pop hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	push hl
	call banksetbc
	ex de, hl
	call callhl
	ld bc, #MAP_BANK3
	jr banksetbc
__bank_3_2:
	ld bc, #MAP_BANK2
	jr bank_3_x

__stub_2_1:
__stub_3_1:
__stub_0_1:
	ld bc, #MAP_BANK1
	jr stub_call
__stub_0_2:
__stub_1_2:
__stub_3_2:
	ld bc, #MAP_BANK2
	jr stub_call
__stub_0_3:
__stub_1_3:
__stub_2_3:
	ld bc, #MAP_BANK3
stub_call:
	pop hl
	ex (sp), hl
	call sanitize_bc_map
	; COMMONMEM, stack in WIN3: switch WIN1/2 with BC, preserving
	; IRQ state.  Classify the caller before the callee clobbers BC;
	; sanitize_bc_map also destroys A, so read the caller bank after it.
	ld a, (_kernel_pages+1)
	ld (_kernel_pages+1), bc
	ld (mpgsel_cache + 1), bc
	ld b, a
	ld a, c
	out (MPGSEL_1), a
	inc a
	call set_mpgsel2_safe
	ex de, hl
	ld a, b
	cp #BANK1
	jr z, stub_ret_1
	cp #BANK2
	jr z, stub_ret_2
	call callhl
	ld bc, #MAP_BANK3
	jr stub_ret
stub_ret_2:
	call callhl
	ld bc, #MAP_BANK2
stub_ret:
	call sanitize_bc_map
	ld (_kernel_pages+1), bc
	ld (mpgsel_cache + 1), bc
	ld a, c
	out (MPGSEL_1), a
	ld a, b
	call set_mpgsel2_safe
	pop bc
	push bc
	push bc
	ret
stub_ret_1:
	call callhl
	ld bc, #MAP_BANK1
	jr stub_ret

callhl:	jp (hl)

sanitize_bc_map:
	ld a, c
	cp #BANK1
	jr z, sanitize_bc_b1
	cp #BANK2
	jr z, sanitize_bc_b2
	cp #BANK3
	jr z, sanitize_bc_b3
	jr sanitize_bc_default
sanitize_bc_b1:
	ld a, b
	cp #0x4A
	jr z, sanitize_bc_ok
	jr sanitize_bc_default
sanitize_bc_b2:
	ld a, b
	cp #0x4D
	jr z, sanitize_bc_ok
	jr sanitize_bc_default
sanitize_bc_b3:
	ld a, b
	cp #0x4F
	jr z, sanitize_bc_ok
sanitize_bc_default:
	ld bc, #MAP_BANK1
	ret
sanitize_bc_ok:
	ret

set_mpgsel2_safe:
	ld (_spr_pg2_last_raw), a
	cp #0x50
	jr c, set_mpgsel2_ok
	push hl
	ld hl, #_spr_pg2_clamp_count
	inc (hl)
	jr nz, set_mpgsel2_sat
	inc hl
	inc (hl)
set_mpgsel2_sat:
	pop hl
	ld a, #0x4A
set_mpgsel2_ok:
	ld (mpgsel_cache + 2), a
	out (MPGSEL_2), a
	ret

;
; Keep this banner line outside _COMMONDATA to leave room for debug latches.
;
; PID1 "/init" path must live in always-mapped common (WIN3), not CODE/WIN0
; (user page may be mapped there during n_open) and not COMMONDATA (BSS wipe).
;
	.area _COMMONMEM

_spr_initmsg:
		.db 'i','n','i','t',0x0A,0

_spr_common_init_path:
		.db '/','i','n','i','t',0

_spr_common_init_argv:
		.dw _spr_common_init_path
		.dw 0

_spr_common_init_envp:
		.dw 0

; Kernel pathname must survive the CODE1 -> CODE3 filesystem call.
	.globl _spr_tty_path
_spr_tty_path:
		.ascii "/dev/tty1"
		.db 0

; Set by sprinter_apply_user_reloc() after kernel-side reloc of a
; FUZIX z80_rel binary.  _doexec then passes DE=0 so crt0's reloc loop
; is a no-op (stream already consumed) and cannot re-patch sys_stubs.
	.globl _spr_reloc_done
_spr_reloc_done:
		.db 0

; n_open walk pointers — must stay in common (WIN3), not WIN0 DATA.
_spr_nopen_name:
		.dw 0
_spr_nopen_nameend:
		.dw 0

; Component buffer for n_open — same WIN0 hazard as the walk pointers.
	.globl _lastname
_lastname:
		.ds 31

	.area _COMMONDATA

_mpgsel_cache:
mpgsel_cache:
	.db 0, 0, 0, 0		; cached page numbers for all 4 windows

_kernel_pages:
	.db 0x48, 0x49, 0x4A, 0x4B	; kernel page assignments

; top_bank tracks MPGSEL_3 — share kernel_pages[3] (saves 1B for IM2 ceiling).
top_bank		.equ _kernel_pages + 3

;
; Keep early fatal diagnostics below 0xFC00 so replay dumps around trap
; stubs and the top common page stay easy to compare across iterations.
;
_sprinter_rst38_count:
	.db 0			; count of fatal hits to the 0x0038 vector

_sprinter_rst38_ret:
	.dw 0			; return address fetched from the RST 38 stack frame

map_savearea:
	.db 0, 0, 0, 0		; saved mapping

map_savearea_user:
	.db 0, 0, 0, 0		; usermem private saved mapping

_int_disabled:
	.db 1

; 0 at boot so sprinit write returns use stock ei.
; _doexec sets this on the second+ exec (/bin/sh); unix_pop skips ei.
_sprinter_bringup_noei:
	.db 0

_spr_doexec_count:
	.db 0

; Real bytes (not aliased onto sys exit probes or dbg[]): map_apply
; one-shot and doexec arming depend on these surviving other syscalls.
_spr_doexec_arm:
	.db 0
_spr_doexec_seen:
	.db 0

; nullh aliases exec_diag tail (saves 1B).
_sprinter_nullh_count	.equ _spr_exec_diag + 15

;
; Exec / i_deref bring-up latches collapsed into one scratch block.
; Full separate .dw/.db storage overlapped the former IM2 vector
; page at 0xFF00 (I=0xFF); dbg[] writes then corrupted the vector table
; and userland died with RST38 after a few syscalls.
;
_spr_exec_diag:
	.ds 16

; up*/mp*/I / nmi / panic_bytes / null_sp snapshots alias exec_diag —
; saves common storage after sys_diag grew to 16 and arm/seen regained bytes.
_sprinter_rst38_up0	.equ _spr_exec_diag + 0
_sprinter_rst38_up1	.equ _spr_exec_diag + 1
_sprinter_rst38_up2	.equ _spr_exec_diag + 2
_sprinter_rst38_mp0	.equ _spr_exec_diag + 3
_sprinter_rst38_mp1	.equ _spr_exec_diag + 4
_sprinter_rst38_mp2	.equ _spr_exec_diag + 5
_sprinter_rst38_i	.equ _spr_exec_diag + 6
_sprinter_nmi_count	.equ _spr_exec_diag + 7
_sprinter_last_panic_bytes	.equ _spr_exec_diag + 8
_sprinter_last_validchk_dev	.equ _spr_exec_diag + 8
_sprinter_last_validchk_site	.equ _spr_exec_diag + 8
_sprinter_last_panic_ptr	.equ _spr_exec_diag + 10
_sprinter_null_sp0		.equ _spr_exec_diag + 10
_sprinter_rst38_sp		.equ _spr_exec_diag + 10
_sprinter_rst38_insys		.equ _spr_exec_diag + 12
_sprinter_rst38_callno		.equ _spr_exec_diag + 13
_sprinter_null_sp2		.equ _spr_exec_diag + 12
_sprinter_trace_last		.equ _spr_exec_diag + 14
_sprinter_rst38_inirq		.equ _spr_exec_diag + 15

; Layout matches C externs (stage u8, err/done/count u16).  Keep
; last_exec_* inside this 16-byte block so they do not smash _spr_misc_diag.
_sprinter_exec_fail_stage	.equ _spr_exec_diag + 0
_sprinter_exec_fail_err	.equ _spr_exec_diag + 1
_sprinter_exec_fail_done	.equ _spr_exec_diag + 4
_sprinter_exec_fail_count	.equ _spr_exec_diag + 6
_sprinter_exec_fail_argv	.equ _spr_exec_diag + 8
_sprinter_exec_fail_envp	.equ _spr_exec_diag + 10
_sprinter_last_exec_base	.equ _spr_exec_diag + 12
_sprinter_last_exec_count	.equ _spr_exec_diag + 14
; Legacy aliases (bring-up probes; may overlap — prefer dbg[] for progress).
_sprinter_exec_fail_name	.equ _spr_exec_diag + 3
_sprinter_exec_fail_root	.equ _spr_exec_diag + 8
_sprinter_exec_fail_cwd	.equ _spr_exec_diag + 10
_sprinter_exec_fail_ino	.equ _spr_exec_diag + 12
_sprinter_exec_fail_mode	.equ _spr_exec_diag + 14
_sprinter_exec_fail_perm	.equ _spr_exec_diag + 3
_sprinter_exec_fail_mflags	.equ _spr_exec_diag + 0
_sprinter_last_exec_top	.equ _spr_exec_diag + 8
_sprinter_last_exec_upage	.equ _spr_exec_diag + 10
_sprinter_last_exec_ptab	.equ _spr_exec_diag + 12
_sprinter_last_ideref_in	.equ _spr_exec_diag + 8
_sprinter_last_ideref_post	.equ _spr_exec_diag + 10
_sprinter_last_ideref_wr	.equ _spr_exec_diag + 12
_sprinter_last_ideref_meta	.equ _spr_exec_diag + 14
_sprinter_last_wr_ptr	.equ _spr_exec_diag + 8
_sprinter_last_wr_meta	.equ _spr_exec_diag + 10
_sprinter_last_wr_site	.equ _spr_exec_diag + 12

;
; Legacy bring-up latches below are no longer used on the active path.
; Keep symbol ABI for existing probes but collapse storage into one scratch
; block to conserve common memory.
;
_spr_legacy_diag	.equ _spr_misc_diag

_sprinter_last_newfile_pino	.equ _spr_legacy_diag + 0
_sprinter_last_newfile_nindex_in	.equ _spr_legacy_diag + 2
_sprinter_last_newfile_nindex_prewr	.equ _spr_legacy_diag + 4
_sprinter_last_iopen_dev	.equ _spr_legacy_diag + 0
_sprinter_last_iopen_ino	.equ _spr_legacy_diag + 2
_sprinter_last_iopen_ret	.equ _spr_legacy_diag + 4
_sprinter_last_iopen_bad	.equ _spr_legacy_diag + 1
_sprinter_last_iopen_mode	.equ _spr_legacy_diag + 3
_sprinter_last_iopen_nlink	.equ _spr_legacy_diag + 5
_sprinter_bad_iopen_dev	.equ _spr_legacy_diag + 0
_sprinter_bad_iopen_ino	.equ _spr_legacy_diag + 2
_sprinter_bad_iopen_bad	.equ _spr_legacy_diag + 1
_sprinter_bad_iopen_mode	.equ _spr_legacy_diag + 3
_sprinter_bad_iopen_nlink	.equ _spr_legacy_diag + 5
_sprinter_bad_iopen_ptr	.equ _spr_legacy_diag + 0
_sprinter_bad_iopen_a0	.equ _spr_legacy_diag + 2
_sprinter_bad_iopen_a1	.equ _spr_legacy_diag + 4
_sprinter_bad_iopen_flags	.equ _spr_legacy_diag + 6
_sprinter_last_nopen_stage	.equ _spr_legacy_diag + 0
_sprinter_last_nopen_wd	.equ _spr_legacy_diag + 3
_sprinter_last_nopen_ninode	.equ _spr_legacy_diag + 5
_sprinter_last_nopen_name0	.equ _spr_legacy_diag + 1
_sprinter_last_nopen_char	.equ _spr_legacy_diag + 2

_spr_rdwr_stage	.equ _spr_legacy_diag + 0
_spr_rdwr_reading	.equ _spr_legacy_diag + 1
_spr_rdwr_fd	.equ _spr_legacy_diag + 2
_spr_rdwr_base	.equ _spr_legacy_diag + 3
_spr_rdwr_count	.equ _spr_legacy_diag + 5
_spr_rdwr_argn	.equ _spr_legacy_diag + 3
_spr_rdwr_argn1	.equ _spr_legacy_diag + 5
_spr_rdwr_argn2	.equ _spr_legacy_diag + 3
_spr_rw_stage	.equ _spr_legacy_diag + 0
_spr_rw_fd	.equ _spr_legacy_diag + 2
_spr_rw_base	.equ _spr_legacy_diag + 3
_spr_rw_count	.equ _spr_legacy_diag + 5
_spr_rw_access	.equ _spr_legacy_diag + 7
_spr_rw_mode	.equ _spr_legacy_diag + 3
_spr_rw_dev	.equ _spr_legacy_diag + 5
_spr_initio_stage	.equ _spr_legacy_diag + 0
_spr_initio_fd	.equ _spr_legacy_diag + 3
_spr_initio_err	.equ _spr_legacy_diag + 5
_spr_initio_files	.equ _spr_legacy_diag + 2
_spr_va_stage	.equ _spr_legacy_diag + 0
_spr_va_base	.equ _spr_legacy_diag + 3
_spr_va_size	.equ _spr_legacy_diag + 5
_spr_va_top	.equ _spr_legacy_diag + 3

;
; Collapse unused ch_link / getinode / i_alloc / getdev probes into one
; scratch block.  Separate .db/.dw storage pushed COMMONDATA past 0xFF00
; and corrupted the former IM2 page (_sprinter_dbg started at 0xFEFF).
;
_spr_misc_diag:
	.ds 8

_sprinter_chlink_stage	.equ _spr_misc_diag + 0
_sprinter_chlink_wd	.equ _spr_misc_diag + 1
_sprinter_chlink_nindex	.equ _spr_misc_diag + 3
_sprinter_chlink_done	.equ _spr_misc_diag + 5
_sprinter_chlink_error	.equ _spr_misc_diag + 7
_sprinter_ideref_null_count	.equ _spr_misc_diag + 9
_sprinter_ideref_null_sys	.equ _spr_misc_diag + 11
_spr_gir	.equ _spr_misc_diag + 0
_spr_giu	.equ _spr_misc_diag + 1
_spr_gio	.equ _spr_misc_diag + 2
_spr_gifr	.equ _spr_misc_diag + 3
_spr_gifa	.equ _spr_misc_diag + 4
_spr_giin	.equ _spr_misc_diag + 5
_spr_gis	.equ _spr_misc_diag + 7
_spr_gfcnt	.equ _spr_misc_diag + 9
_spr_gfr	.equ _spr_misc_diag + 11
_spr_gfu	.equ _spr_misc_diag + 12
_spr_gfo	.equ _spr_misc_diag + 13
_spr_gffr	.equ _spr_misc_diag + 14
_spr_gffa	.equ _spr_misc_diag + 15
_spr_gfin	.equ _spr_misc_diag + 5
_spr_gfs	.equ _spr_misc_diag + 7
_spr_iac_devptr	.equ _spr_misc_diag + 0
_spr_iac_ninode	.equ _spr_misc_diag + 2
_spr_iac_tinode	.equ _spr_misc_diag + 3
_spr_iac_isize	.equ _spr_misc_diag + 5
_spr_iac_mounted	.equ _spr_misc_diag + 7
_spr_gd_dev	.equ _spr_misc_diag + 8
_spr_gd_mnt	.equ _spr_misc_diag + 10
_spr_gd_state	.equ _spr_misc_diag + 12

;
; Syscall enter/exit probes share one scratch block to conserve common.
; Must be 16 bytes: exit probes write +10..+15 (was backed by arm/seen/dbg).
;
_spr_sys_diag:
	.ds 16

_spr_sys_enter_no	.equ _spr_sys_diag + 0
_spr_sys_enter_up0	.equ _spr_sys_diag + 1
_spr_sys_enter_up1	.equ _spr_sys_diag + 2
_spr_sys_enter_up2	.equ _spr_sys_diag + 3
_spr_sys_enter_pp0	.equ _spr_sys_diag + 4
_spr_sys_enter_pp1	.equ _spr_sys_diag + 5
_spr_sys_enter_pp2	.equ _spr_sys_diag + 6
_spr_sys_enter_ptab	.equ _spr_sys_diag + 7
_spr_sys_enter_fixup	.equ _spr_sys_diag + 9
_spr_sys_exit_no	.equ _spr_sys_diag + 10
_spr_sys_exit_err	.equ _spr_sys_diag + 11
_spr_sys_exit_up0	.equ _spr_sys_diag + 13
_spr_sys_exit_up1	.equ _spr_sys_diag + 14
_spr_sys_exit_up2	.equ _spr_sys_diag + 15
_spr_sys_exit_pp0	.equ _spr_sys_diag + 4
_spr_sys_exit_pp1	.equ _spr_sys_diag + 5
_spr_sys_exit_pp2	.equ _spr_sys_diag + 6
_spr_sys_exit_ptab	.equ _spr_sys_diag + 7
_spr_sys_fixup		.equ _spr_sys_diag + 9
_spr_sysarg_sp		.equ _spr_sys_diag + 11

; expect/isp share sys_diag (idle during doexec arm).  arm/seen are
; real bytes below (must not share sys exit probes or dbg[] aliases).
_spr_doexec_expect	.equ _spr_sys_diag + 0
_spr_doexec_isp		.equ _spr_sys_diag + 2

; doexec map/call probes share misc scratch (not arm/seen/expect/isp).
_spr_doexec_probe	.equ _spr_misc_diag
_spr_doexec_map_ptr	.equ _spr_doexec_probe
_spr_doexec_u0		.equ _spr_doexec_probe + 0
_spr_doexec_u1		.equ _spr_doexec_probe + 1
_spr_doexec_u2		.equ _spr_doexec_probe + 2
_spr_doexec_u3		.equ _spr_doexec_probe + 3
_spr_doexec_m0		.equ _spr_doexec_probe + 0
_spr_doexec_m1		.equ _spr_doexec_probe + 1
_spr_doexec_m2		.equ _spr_doexec_probe + 2
_spr_doexec_call_seen	.equ _spr_misc_diag + 4
_spr_doexec_call_word	.equ _spr_misc_diag + 5
_spr_doexec_call_sp	.equ _spr_doexec_call_word
_spr_doexec_call_ra0	.equ _spr_doexec_call_word
_spr_doexec_call_ra1	.equ _spr_doexec_call_word
_spr_doexec_call_af	.equ _spr_doexec_call_word
_spr_doexec_call_start	.equ _spr_doexec_call_word

; boot/pg2 live in misc — never alias onto doexec arm/seen/isp.
_spr_pg2_clamp_count	.equ _spr_misc_diag + 3
_spr_pg2_last_raw	.equ _spr_misc_diag + 5
_spr_boot_count		.equ _spr_misc_diag + 6

_sprinter_trace_idx	.equ _spr_misc_diag + 0
_sprinter_trace_buf	.equ _spr_misc_diag + 2

; dbg[] aliases exec_diag (16B), saving a second .ds 16.
; Exec-fail latches are idle once /bin/sh is running.
_sprinter_dbg		.equ _spr_exec_diag
