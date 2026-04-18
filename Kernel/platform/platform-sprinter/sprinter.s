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
	.globl _sprinter_last_exec_path
	.globl _sprinter_last_exec_hdr
	.globl _sprinter_last_exec_base
	.globl _sprinter_last_exec_count
	.globl _sprinter_last_exec_top
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

	; Set up IM2 interrupt vectors
	; Fill 257-byte table at 0xFE00 with 0xFD
	; This puts interrupt handler at address 0xFDFD
	ld hl, #0xFE00
	ld de, #0xFE01
	ld bc, #256
	ld (hl), #0xFD
	ldir

	; Install a MINIMAL bring-up IRQ stub at 0xFDFD instead of the
	; FUZIX `interrupt_handler`.  The FUZIX handler's exit path
	; unconditionally clears _int_disabled and `ei`s, which latches
	; the kernel in an interrupt loop as soon as any IM2 vector
	; fires (CTC, SIO, ULA FRAME / VSync, ISA slot, etc).  Our stub
	; just does `reti` with IFF1 left at 0 so interrupts stay off.
	ld a, #0xC3			; JP instruction
	ld (0xFDFD), a
	ld hl, #sprinter_bringup_int
	ld (0xFDFE), hl

	ld a, #0xFE
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
        ; Decide whether to absorb or dispatch the IRQ based on the
        ; FUZIX u_insys flag:
        ;   u_insys == 0  -> user code was running, hand off to the
        ;                    real dispatcher so the scheduler, signal
        ;                    delivery and kbd/timer polling all work.
        ;   u_insys != 0  -> kernel bring-up / syscall in progress;
        ;                    the core dispatcher's exit path would
        ;                    `ei` unconditionally and latch us in a
        ;                    reentry loop on a level-triggered source
        ;                    (Sprinter ULA FRAME).  Absorb the IRQ,
        ;                    pin _int_disabled at 1 and RETI with IFF
        ;                    still cleared.
        push af
        ld a, (_udata + U_DATA__U_INSYS)
        or a
        jr z, sprinter_bringup_to_kernel
        push hl
        ld hl, #_int_disabled
        ld (hl), #1
        pop hl
        pop af
        reti
sprinter_bringup_to_kernel:
        pop af
        jp interrupt_handler

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
        ; arg dptr lives at SP+4 under SDCC sdcccall(0) + push af;noopt
        ld hl, #4
        add hl, sp
        ld e, (hl)
        inc hl
        ld d, (hl)
        ex de, hl		; HL = destination address

        push hl
        ld a, (_td_raw)
        cp #2
        jr nz, ide_rd_not_swap
        ld a, (_td_page)
        call map_for_swap
        jr ide_rd_go
ide_rd_not_swap:
        or a
        jr nz, ide_rd_user
        call map_buffers
        jr ide_rd_go
ide_rd_user:
        call map_proc_always
ide_rd_go:
        pop hl

        ld bc, #0x0050		; IDE data port (low byte is what DCP decodes)
        ld de, #0x0200		; 512 bytes per sector
ide_rd_loop:
        in a, (c)
        ld (hl), a
        inc hl
        dec de
        ld a, d
        or e
        jr nz, ide_rd_loop
        jp map_kernel_restore

_devide_write_data:
        ; Bring-up safety: no-op IDE write path.  Even if a higher-level
        ; caller (bdwrite, cdwrite, tinydisk direct) somehow reaches
        ; ide_xfer with is_read=false, we refuse to send the 512 OUT
        ; instructions that would scribble a sector to disk.  Returns
        ; cleanly so the caller sees a "successful" transfer and the
        ; buffer is marked clean; nothing ever leaves RAM.
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
	; Run the vector setup on the caller's (kernel) stack.  An earlier
	; implementation swapped SP to a private pv_stack buffer in
	; _COMMONDATA, but that buffer grew past the IM2 vector table at
	; 0xFE00 and the first `call` push inside program_vectors then
	; clobbered table entries.  Kernel stack is already safely rooted
	; at kstack_top (0xF000) and has plenty of headroom for the three
	; calls below.
	call map_proc
	call do_program_vectors
	jp map_kernel_restore

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
	; write zeroes across all vectors
	ld hl, #0
	ld de, #1
	ld bc, #0x007f
	ld (hl), #0x00
	ldir

	; Install the permanent exception vectors.  The IM2 / IM1 slots
	; intentionally stay on sprinter_bringup_int during kernel
	; bring-up: enabling FUZIX's interrupt_handler while the kernel
	; is still mapping memory for PID1 causes a runaway dispatch loop
	; (the handler's exit path clears _int_disabled and `ei`s, and
	; the Sprinter ULA FRAME pin is asserted continuously during
	; boot).  The first _doexec call re-arms these vectors to the
	; real handler (see sprinter_arm_irq).
	ld a, #0xC3			; JP instruction
	ld (0x0038), a
	ld hl, #sprinter_bringup_int
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

	; IM2 vector table and handler at 0xFDFD.
	ld hl, #0xFE00
	ld de, #0xFE01
	ld bc, #256
	ld (hl), #0xFD
	ldir

	ld a, #0xC3
	ld (0xFDFD), a
	ld hl, #sprinter_bringup_int
	ld (0xFDFE), hl

	ret

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
	out (MPGSEL_2), a
	ret

;=========================================================================
; map_proc_2 - map process or kernel pages
; Inputs: page table address in HL
; Outputs: none, HL destroyed
;=========================================================================
map_proc_2:
	push de
	push af
	ld a, (hl)			; page for bank #0
	cp #0x08
	jr c, map_proc_2_b0_bad
	cp #0x80
	jr c, map_proc_2_b0_ok
map_proc_2_b0_bad:
	ld a, #0x48
map_proc_2_b0_ok:
	ld (mpgsel_cache), a
	out (MPGSEL_0), a		; set bank #0
	inc hl
	ld a, (hl)			; page for bank #1
	cp #0x08
	jr c, map_proc_2_b1_bad
	cp #0x80
	jr c, map_proc_2_b1_ok
map_proc_2_b1_bad:
	ld a, #0x49
map_proc_2_b1_ok:
	ld (mpgsel_cache + 1), a
	out (MPGSEL_1), a		; set bank #1
	inc hl
	ld a, (hl)			; page for bank #2
	cp #0x08
	jr c, map_proc_2_b2_bad
	cp #0x80
	jr c, map_proc_2_b2_ok
map_proc_2_b2_bad:
	ld a, #0x4A
map_proc_2_b2_ok:
	ld (mpgsel_cache + 2), a
	out (MPGSEL_2), a		; set bank #2
	pop af
	pop de
	ret

sanitize_kpages:
	ld a, (_kernel_pages)
	cp #0x48
	jr nz, sanitize_kpages_bad
	ld a, (_kernel_pages + 1)
	cp #0x08
	jr c, sanitize_kpages_bad
	cp #0x80
	jr nc, sanitize_kpages_bad
	ld a, (_kernel_pages + 2)
	cp #0x08
	jr c, sanitize_kpages_bad
	cp #0x80
	jr nc, sanitize_kpages_bad
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
	cp #0x80
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
	; void plt_trace(uint8_t code)
	;
	; 1024-byte circular trace buffer with a 16-bit index.  The index
	; wraps via `and 0x3FF` so the storage range is [0..0x3FF].  This
	; gives us ~4x as much history as the previous 256-byte buffer,
	; which matters when /init makes many syscalls (each one writes
	; 40+ bytes through the bread/td_read/ide_xfer path) and pushes
	; earlier diagnostic markers out of view.
	ld hl, #4
	add hl, sp
	ld a, (hl)			; A = argument byte from stack
	ld e, a
	ld hl, (_sprinter_trace_idx)
	ld b, h
	ld c, l
	inc hl
	ld a, h
	and #0x01			; wrap to 512 (0x200) bytes
	ld h, a
	ld (_sprinter_trace_idx), hl
	ld hl, #_sprinter_trace_buf
	add hl, bc
	ld a, e
	ld (hl), a
	ld (_sprinter_trace_last), a
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
	out (MPGSEL_2), a
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
	out (MPGSEL_2), a
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
	out (MPGSEL_2), a
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
	out (MPGSEL_2), a
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
	cp #0x08
	jr c, sanitize_bc_default
	cp #0x80
	jr nc, sanitize_bc_default
	ld a, b
	cp #0x08
	jr c, sanitize_bc_default
	cp #0x80
	jr nc, sanitize_bc_default
	ret
sanitize_bc_default:
	ld bc, #MAP_BANK1
	ret

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

_sprinter_last_exec_path:
	.ds 32			; zero-terminated copy of most recent _execve arg

_sprinter_last_exec_hdr:
	.ds 16			; raw bytes of most recent exec header read by _execve

_sprinter_last_exec_base:
	.dw 0			; snapshot of udata.u_base before valaddr_r check

_sprinter_last_exec_count:
	.dw 0			; snapshot of udata.u_count before valaddr_r check

_sprinter_last_exec_top:
	.dw 0			; snapshot of udata.u_top before valaddr_r check

_sprinter_trace_idx:
	.dw 0			; 16-bit index to address a larger buffer

_sprinter_trace_buf:
	.ds 512

_sprinter_dbg:
	.ds 32

pv_oldsp:
	.dw 0

pv_stack:
	.ds 256
pv_stack_top:
