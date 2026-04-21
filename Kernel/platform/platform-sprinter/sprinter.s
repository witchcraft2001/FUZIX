;
;	Sprinter (Peters MC 2008) hardware support
;

        .module sprinter

        ; exported symbols
        .globl init_hardware
	.globl _program_vectors
	.globl map_kernel
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
	.globl top_bank
	.globl _kernel_pages
	.globl _plt_reboot
	.globl _plt_monitor
	.globl _plt_trace
	.globl _sprinter_force_bank1
	.globl _dev_tab
	.globl _int_disabled
	.globl _sprinter_trace_last
	.globl _sprinter_nullh_count
	.globl _sprinter_trace_idx
	.globl _sprinter_trace_buf
	.globl _sprinter_dbg
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
	.globl _sprinter_last_validchk_dev
	.globl _sprinter_last_validchk_site
	.globl _sprinter_last_panic_ptr
		.globl _sprinter_last_panic_bytes
		.globl _sprinter_rst38_count
		.globl _sprinter_rst38_sp
		.globl _sprinter_rst38_ret
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
	.globl _spr_va_stage
	.globl _spr_va_base
	.globl _spr_va_size
	.globl _spr_va_top
	.globl _spr_pg2_clamp_count
	.globl _spr_pg2_last_raw
	.globl _spr_boot_count
	.globl _spr_dofork_count
	.globl _spr_dofork_ret
	.globl _spr_dofork_child
	.globl _spr_dofork_upages
	.globl _spr_dofork_cpages
	.globl _spr_dofork_iter
	.globl _spr_dofork_child_page
	.globl _spr_dofork_parent_page
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
	; We use pages 0x04-0x4F for user space = 76 pages * 16K = 1216K
        ld hl, #4096
        ld (_ramsize), hl
        ld hl, #1152		; 72 * 16K user pages
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
	; Under CONFIG_SPRINTER_EARLY_TRACE the _COMMONDATA block now grows
	; up into 0xFDxx..0xFExx, so the old FE00/FDFD table+stub placement
	; overlaps the trace/common globals and both sides corrupt each other.
	; Keep the bring-up IM2 page entirely below _COMMONDATA.
	;
	; Fill 257-byte table at 0xFC00 with 0xFC so every IM2 vector
	; resolves to 0xFCFC regardless of the peripheral-supplied low byte.
	ld hl, #0xFC00
	ld de, #0xFC01
	ld bc, #256
	ld (hl), #0xFC
	ldir

	; Install a MINIMAL bring-up IRQ stub at 0xFDFD instead of the
	; FUZIX `interrupt_handler`.  The FUZIX handler's exit path
	; unconditionally clears _int_disabled and `ei`s, which latches
	; the kernel in an interrupt loop as soon as any IM2 vector
	; fires (CTC, SIO, ULA FRAME / VSync, ISA slot, etc).  Our stub
	; just does `reti` with IFF1 left at 0 so interrupts stay off.
	ld a, #0xC3			; JP instruction
	ld (0xFCFC), a
	ld hl, #sprinter_bringup_int
	ld (0xFCFD), hl

	ld a, #0xFC
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
	; Capture caller return address from stack (who entered reboot/monitor).
	ld hl, #0
	add hl, sp
	ld a, (hl)
	ld (_sprinter_dbg + 24), a
	inc hl
	ld a, (hl)
	ld (_sprinter_dbg + 25), a
	inc hl
	ld a, (hl)
	ld (_sprinter_dbg + 26), a
	inc hl
	ld a, (hl)
	ld (_sprinter_dbg + 27), a
	ld hl, (_sprinter_last_panic_ptr)
	ld a, h
	or l
	jr nz, plt_monitor_capture
	; Bring-up: if monitor was not entered from panic(), do not hard
	; stop here. Return so the next failure can surface.
	ret

plt_monitor_capture:
	ld hl, #0x0155
	ld de, #_sprinter_dbg
	ld bc, #0x000E
	ldir
	ld hl, #_dev_tab + 0x0014
	ld a, (hl)
	ld (_sprinter_dbg + 14), a
	inc hl
	ld a, (hl)
	ld (_sprinter_dbg + 15), a
	ld hl, #_dev_tab
	ld a, (hl)
	ld (_sprinter_dbg + 16), a
	inc hl
	ld a, (hl)
	ld (_sprinter_dbg + 17), a
	ld hl, #_dev_tab + 0x0004
	ld a, (hl)
	ld (_sprinter_dbg + 18), a
	inc hl
	ld a, (hl)
	ld (_sprinter_dbg + 19), a
	ld hl, #_dev_tab + 0x0008
	ld a, (hl)
	ld (_sprinter_dbg + 20), a
	inc hl
	ld a, (hl)
	ld (_sprinter_dbg + 21), a
	ld hl, #_td_op
	ld a, (hl)
	ld (_sprinter_dbg + 22), a
	inc hl
	ld a, (hl)
	ld (_sprinter_dbg + 23), a
plt_monitor_hang:
	halt
	jr plt_monitor_hang

plt_interrupt_all:
        ret

;=========================================================================
; sprinter_bringup_int - minimal IRQ stub used during platform bring-up.
;
; Any IM2 vector (CTC, SIO, ULA FRAME, ISA, etc) is routed here via the
; table at 0xFE00.  We acknowledge the interrupt with `reti` but leave
; IFF1 cleared so the kernel stays in its post-`di` state.  This is a
; workaround for FUZIX's core `interrupt_handler` exit which always
; clears _int_disabled and `ei`s -- once that runs a single stray IRQ
; latches the CPU in an interrupt loop and main-flow progress stalls.
; Once the kernel is stable we'll swap this out for the real dispatcher.
;=========================================================================
sprinter_bringup_int:
	; Bring-up safety mode: absorb all IM2 IRQs unconditionally.
	; We still mark interrupts as disabled in common state so any code
	; sampling _int_disabled stays consistent with the hardware IFF1=0.
	push af
	push hl
	ld hl, #_int_disabled
	ld (hl), #1
	pop hl
	pop af
	reti

;=========================================================================
; sprinter_rst38_stub - fatal RST 38 / IM1 trap logger.
;
; User bring-up should not be reaching 0x0038 at all while IFF1 is clear.
; If it does, record the trap and freeze so the emulator dump shows where
; execution came from.  For a real RST 38 the CPU has already pushed the
; return PC; we snapshot that from the current SP.
;=========================================================================
sprinter_rst38_stub:
		ld hl, #_sprinter_rst38_count
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
_devide_read_data:
        di
	pop bc				; return address
	pop de				; destination pointer
	push de
	push bc

	ld hl, #_sprinter_ide_bounce
	ld bc, #0x0050		; Sprinter IDE read data port
	inir				; first 256 bytes -> common bounce

	push de
	ld a, (_td_raw)
	cp #2
	jr nz, ide_rd_not_swap
	ld a, (_td_page)
	call map_for_swap
	jr ide_rd_copy1
ide_rd_not_swap:
	or a
	jr nz, ide_rd_user
	call map_buffers
	jr ide_rd_copy1
ide_rd_user:
	call map_proc_always
ide_rd_copy1:
	pop de
	ld hl, #_sprinter_ide_bounce
	ld bc, #0x0100
	ldir				; copy first half into mapped target

	ld hl, #_sprinter_ide_bounce
	ld bc, #0x0050
	inir				; second 256 bytes -> common bounce
	ld hl, #_sprinter_ide_bounce
	ld bc, #0x0100
	ldir				; copy second half into mapped target
	call map_kernel_restore
        ei
        ret

_devide_write_data:
	di
	pop bc				; return address
	pop hl				; source pointer
	push hl
	push bc

	ld a, (_td_raw)
	cp #2
	jr nz, ide_wr_not_swap
	ld a, (_td_page)
	call map_for_swap
	jr ide_wr_go
ide_wr_not_swap:
	or a
	jr nz, ide_wr_user
	call map_buffers
	jr ide_wr_go
ide_wr_user:
	call map_proc_always
ide_wr_go:
	pop hl

	ld bc, #0x0150		; Sprinter IDE write data port
	otir
	otir
	call map_kernel_restore
	ei
	ret

;=========================================================================
; program_vectors - set exception vectors for a new process
;=========================================================================
_program_vectors:
	di
	; SDCC banked call sites push AF (noopt) before calling this helper,
	; so argument pointer (&u_page) is at SP+4.
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

	; null trap at 0x0000
	ld (0x0000), a
	ld hl, #null_handler
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

	ld (0x0000), a
	ld hl, #null_handler
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
	jr nz, map_proc_2		; HL == 0 - map the kernel

;=========================================================================
; map_kernel - map kernel pages
; Inputs: none
; Outputs: none; all registers preserved
;=========================================================================
map_kernel:
map_buffers:
map_kernel_restore:
map_kernel_di:
	push hl
	call sanitize_kpages
	ld hl, #_kernel_pages
	jp map_proc_2_pophl_ret

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
	ld a, (hl)
	cp #0x48
	jr nz, map_proc_2_ptr_ok
	inc hl
	ld a, (hl)
	dec hl
	cp #0x49
	jr z, map_proc_2_ptr_ok
	ld hl, #_udata + U_DATA__U_PAGE
map_proc_2_ptr_ok:
	push de
	push af
	ld a, (hl)			; page for bank #0
	cp #0x08
	jr c, map_proc_2_b0_bad
	cp #0x50
	jr c, map_proc_2_b0_ok
map_proc_2_b0_bad:
	ld a, #0x08
map_proc_2_b0_ok:
	ld (mpgsel_cache), a
	out (MPGSEL_0), a		; set bank #0
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
	out (MPGSEL_1), a		; set bank #1
	inc hl
	ld a, (hl)			; page for bank #2
	cp #0x08
	jr c, map_proc_2_b2_bad
	cp #0x50
	jr c, map_proc_2_b2_ok
map_proc_2_b2_bad:
	ld a, #0x0A
map_proc_2_b2_ok:
	call set_mpgsel2_safe		; set bank #2
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
map_proc_2_pophl_ret:
	call map_proc_2
	pop hl
	ret

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
	jr map_proc_2_pophl_ret

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
	jr map_proc_2_pophl_ret

map_kernel_restore_u:
	push hl
	ld hl, #map_savearea_user
	jr map_proc_2_pophl_ret

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
; (WIN3, currently page 0x4B) into the target page.  Used once at boot
; to initialise PID1 (init)'s p_page[3] so that the first fork() does
; not propagate uninitialised bytes as the child's "common" bank.
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
	di			; must stay off through the switch below
	ld a, e
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
	; _kernel_pages[3] is deliberately left at 0x4B: sanitize_kpages
	; only inspects the array, so it stays a no-op, and map_kernel
	; never touches MPGSEL_3.  top_bank tracks the real port value.
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
	cp #192
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
	ld a, (_kernel_pages+1)
	call sanitize_bc_map
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
	call callhl
	ld a, b
	cp #BANK2
	jr z, stub_ret_2
	ld bc, #MAP_BANK3
	jr stub_ret
stub_ret_2:
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

_sprinter_ide_bounce:
	.ds 256			; 256-byte common bounce for IDE PIO

	.area _COMMONDATA

mpgsel_cache:
	.db 0, 0, 0, 0		; cached page numbers for all 4 windows

top_bank:
	.db 0x4B			; current top bank (common) page

_kernel_pages:
	.db 0x48, 0x49, 0x4A, 0x4B	; kernel page assignments

map_savearea:
	.db 0, 0, 0, 0		; saved mapping

map_savearea_user:
	.db 0, 0, 0, 0		; usermem private saved mapping

_int_disabled:
	.db 1

_sprinter_trace_last:
	.db 0

_sprinter_nmi_count:
	.db 0

_sprinter_nullh_count:
	.db 0

_sprinter_exec_fail_stage:
	.db 0			; _execve failure checkpoint id

_sprinter_exec_fail_err:
	.dw 0			; u_error at failure checkpoint

_sprinter_exec_fail_name:
	.dw 0			; u_argn pointer seen by _execve

_sprinter_exec_fail_root:
	.dw 0			; u_root inode pointer seen by _execve

_sprinter_exec_fail_cwd:
	.dw 0			; u_cwd inode pointer seen by _execve

_sprinter_exec_fail_ino:
	.dw 0			; inode pointer returned by n_open_lock (0 on failure)

_sprinter_exec_fail_mode:
	.dw 0			; ino->c_node.i_mode at permission check

_sprinter_exec_fail_perm:
	.db 0			; getperm(ino) at permission check

_sprinter_exec_fail_mflags:
	.db 0			; fs_tab[ino->c_super].m_flags at permission check

_sprinter_exec_fail_argv:
	.dw 0			; argv pointer seen by _execve late path

_sprinter_exec_fail_envp:
	.dw 0			; envp pointer seen by _execve late path

_sprinter_exec_fail_done:
	.dw 0			; u_done / valaddr_r result at late failure

_sprinter_exec_fail_count:
	.dw 0			; expected count at late failure

_sprinter_last_exec_base:
	.dw 0			; snapshot of udata.u_base before valaddr_r check

_sprinter_last_exec_count:
	.dw 0			; snapshot of udata.u_count before valaddr_r check

_sprinter_last_exec_top:
	.dw 0			; snapshot of udata.u_top before valaddr_r check

_sprinter_last_exec_upage:
	.ds 4			; udata.u_page[0..3] right before doexec()

_sprinter_last_exec_ptab:
	.ds 4			; u_ptab->p_page[0..3] right before doexec()

_sprinter_last_ideref_in:
	.dw 0			; inode pointer on i_deref entry

_sprinter_last_ideref_post:
	.dw 0			; inode pointer after --c_refs path

_sprinter_last_ideref_wr:
	.dw 0			; inode pointer right before wr_inode call

_sprinter_last_ideref_meta:
	.dw 0			; low=u_callno high=u_insys snapshot

_sprinter_last_wr_ptr:
	.dw 0			; pointer passed to WR_INODE wrapper

_sprinter_last_wr_meta:
	.dw 0			; low=u_callno high=u_insys at WR_INODE

_sprinter_last_wr_site:
	.db 0			; WR_INODE call site id

_sprinter_last_newfile_pino:
	.dw 0			; parent inode pointer seen by newfile()

_sprinter_last_newfile_nindex_in:
	.dw 0			; nindex pointer returned by i_open in newfile()

_sprinter_last_newfile_nindex_prewr:
	.dw 0			; nindex pointer just before WR_INODE(1,...)

_sprinter_last_iopen_dev:
	.dw 0			; last i_open(dev, ino) dev argument

_sprinter_last_iopen_ino:
	.dw 0			; last i_open(dev, ino) ino argument

_sprinter_last_iopen_ret:
	.dw 0			; last i_open return pointer

_sprinter_last_iopen_bad:
	.db 0			; 1=existing inode invalid, 2=new inode already populated

_sprinter_last_iopen_mode:
	.dw 0			; i_open badino snapshot of c_node.i_mode

_sprinter_last_iopen_nlink:
	.dw 0			; i_open badino snapshot of c_node.i_nlink

_sprinter_bad_iopen_dev:
	.dw 0			; dev of most recent i_open badino event

_sprinter_bad_iopen_ino:
	.dw 0			; ino of most recent i_open badino event

_sprinter_bad_iopen_bad:
	.db 0			; 1=existing inode invalid, 2=new inode already populated

_sprinter_bad_iopen_mode:
	.dw 0			; badino snapshot of c_node.i_mode

_sprinter_bad_iopen_nlink:
	.dw 0			; badino snapshot of c_node.i_nlink

_sprinter_last_validchk_dev:
	.dw 0			; last dev rejected by validchk()

_sprinter_last_validchk_site:
	.dw 0			; caller string pointer passed to validchk()

_sprinter_last_panic_ptr:
	.dw 0			; last panic() deathcry pointer

_sprinter_last_panic_bytes:
	.ds 4			; first 4 bytes at deathcry pointer

_sprinter_rst38_count:
	.db 0			; count of fatal hits to the 0x0038 vector

_sprinter_rst38_sp:
	.dw 0			; SP seen on entry to sprinter_rst38_stub

_sprinter_rst38_ret:
		.dw 0			; return address fetched from the RST 38 stack frame

_sprinter_chlink_stage:
	.db 0			; ch_link progress marker

_sprinter_chlink_wd:
	.dw 0			; ch_link wd pointer

_sprinter_chlink_nindex:
	.dw 0			; ch_link nindex pointer

_sprinter_chlink_done:
	.dw 0			; last u_done observed in ch_link

_sprinter_chlink_error:
	.dw 0			; last u_error observed in ch_link

_sprinter_ideref_null_count:
	.dw 0			; number of i_deref(NULL) calls

_sprinter_ideref_null_sys:
	.dw 0			; low=u_callno high=u_insys for last NULL deref

_spr_gir:
	.db 0			; 0=ok 1=bad oft index 2=bad of_tab inode ptr

_spr_giu:
	.db 0			; getinode() fd argument

_spr_gio:
	.db 0			; u_files[uindex] snapshot

_spr_gifr:
	.db 0			; of_tab[oftindex].o_refs snapshot

_spr_gifa:
	.db 0			; of_tab[oftindex].o_access snapshot

_spr_giin:
	.dw 0			; of_tab[oftindex].o_inode snapshot

_spr_gis:
	.dw 0			; low=u_callno high=u_insys in getinode

_spr_gfcnt:
	.dw 0			; count of getinode() validation failures

_spr_gfr:
	.db 0			; last failing reason (1 bad oft index, 2 bad inode ptr)

_spr_gfu:
	.db 0			; failing fd/uindex

_spr_gfo:
	.db 0			; failing u_files[uindex]

_spr_gffr:
	.db 0			; failing of_tab[oft].o_refs

_spr_gffa:
	.db 0			; failing of_tab[oft].o_access

_spr_gfin:
	.dw 0			; failing of_tab[oft].o_inode

_spr_gfs:
	.dw 0			; syscall context for failing getinode

_spr_iac_devptr:
	.dw 0			; i_alloc() dev pointer at corrupt path

_spr_iac_ninode:
	.db 0			; i_alloc() s_ninode snapshot

_spr_iac_tinode:
	.dw 0			; i_alloc() s_tinode snapshot

_spr_iac_isize:
	.dw 0			; i_alloc() s_isize snapshot

_spr_iac_mounted:
	.db 0			; i_alloc() s_mounted snapshot

_spr_sys_enter_no:
	.db 0			; last syscall number seen at unix_syscall_entry

_spr_sys_enter_up0:
	.db 0			; u_page[0] seen on syscall entry

_spr_sys_enter_up1:
	.db 0			; u_page[1] seen on syscall entry

_spr_sys_enter_up2:
	.db 0			; u_page[2] seen on syscall entry

_spr_sys_enter_pp0:
	.db 0			; ptab->p_page[0] seen on syscall entry

_spr_sys_enter_pp1:
	.db 0			; ptab->p_page[1] seen on syscall entry

_spr_sys_enter_pp2:
	.db 0			; ptab->p_page[2] seen on syscall entry

_spr_sys_enter_ptab:
	.dw 0			; u_ptab pointer seen on syscall entry

_spr_sys_enter_fixup:
	.db 0			; 1 if syscall entry repaired u_ptab, 2 if it repaired p_page[]

_spr_sys_exit_no:
	.db 0			; last syscall number seen after _unix_syscall

_spr_sys_exit_err:
	.dw 0			; last u_error snapshot after _unix_syscall

_spr_sys_exit_up0:
	.db 0			; u_page[0] seen after _unix_syscall

_spr_sys_exit_up1:
	.db 0			; u_page[1] seen after _unix_syscall

_spr_sys_exit_up2:
	.db 0			; u_page[2] seen after _unix_syscall

_spr_sys_exit_pp0:
	.db 0			; ptab->p_page[0] seen after _unix_syscall

_spr_sys_exit_pp1:
	.db 0			; ptab->p_page[1] seen after _unix_syscall

_spr_sys_exit_pp2:
	.db 0			; ptab->p_page[2] seen after _unix_syscall

_spr_sys_exit_ptab:
	.dw 0			; u_ptab pointer seen after _unix_syscall

_spr_sys_fixup:
	.db 0			; 1 if syscall exit rebuilt u_page[] from ptab

_spr_sysarg_sp:
	.dw 0			; original userspace SP seen on syscall entry

_spr_rdwr_stage:
	.db 0			; readwrite progress marker

_spr_rdwr_reading:
	.db 0			; readwrite direction flag

_spr_rdwr_fd:
	.db 0			; readwrite fd argument

_spr_rdwr_base:
	.dw 0			; readwrite buffer pointer

_spr_rdwr_count:
	.dw 0			; readwrite byte count

_spr_rdwr_argn:
	.dw 0			; raw u_argn snapshot

_spr_rdwr_argn1:
	.dw 0			; raw u_argn1 snapshot

_spr_rdwr_argn2:
	.dw 0			; raw u_argn2 snapshot

_spr_rw_stage:
	.db 0			; rwsetup progress marker

_spr_rw_fd:
	.db 0			; rwsetup fd argument

_spr_rw_base:
	.dw 0			; rwsetup u_base

_spr_rw_count:
	.dw 0			; rwsetup u_count

_spr_rw_access:
	.db 0			; rwsetup of_tab[o].o_access

_spr_rw_mode:
	.dw 0			; rwsetup inode mode snapshot

_spr_rw_dev:
	.dw 0			; rwsetup inode i_addr[0] snapshot

_spr_va_stage:
	.db 0			; valaddr progress marker

_spr_va_base:
	.dw 0			; valaddr base pointer

_spr_va_size:
	.dw 0			; valaddr requested size

_spr_va_top:
	.dw 0			; valaddr u_top snapshot

_spr_pg2_clamp_count:
	.dw 0			; count of forced MPGSEL_2 clamps

_spr_pg2_last_raw:
	.db 0			; raw MPGSEL_2 value before clamp

_spr_boot_count:
	.db 0			; number of entries into fuzix_main()

_spr_dofork_count:
	.db 0			; number of entries into _dofork

_spr_dofork_ret:
	.dw 0			; caller return address seen by _dofork

_spr_dofork_child:
	.dw 0			; child p_tab* argument

_spr_dofork_upages:
	.ds 4			; parent u_page[0..3] snapshot at _dofork entry

_spr_dofork_cpages:
	.ds 4			; child p_page[0..3] snapshot at _dofork entry

_spr_dofork_iter:
	.db 0			; current remaining chunk count in fork_copy

_spr_dofork_child_page:
	.db 0			; current child page mapped at WIN1 in fork_copy

_spr_dofork_parent_page:
	.db 0			; current parent page mapped at WIN2 in fork_copy

_sprinter_trace_idx:
	.dw 0			; 16-bit index to address a larger buffer

_sprinter_trace_buf:
	.ds 192

_sprinter_dbg:
		.ds 31
