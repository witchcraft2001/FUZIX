        .module tricks

        .include "kernel.def"
        .include "../../cpu-z80/kernel-z80.def"

TOP_PORT	.equ	MPGSEL_3
MAP_BANK1	.equ	0x4A49

        .globl _ptab_alloc
        .globl _makeproc
        .globl _chksigs
        .globl _getproc
        .globl _plt_monitor
        .globl _plt_switchout
        .globl _switchin
        .globl _doexec
        .globl _dofork
        .globl _runticks
        .globl unix_syscall_entry
        .globl interrupt_handler
	.globl map_kernel
	.globl _spr_seed_top
	.globl _need_resched
	.globl top_bank
	.globl _int_disabled
	.globl _udata
		.globl _kernel_pages
		.globl mpgsel_cache
		.globl map_kernel_restore
		.globl _get_common
		.globl _swap_finish
		.globl _spr_switchin_stage
		.globl _spr_switchin_sp
		.globl _spr_switchin_ret
		.globl _spr_switchin_next
		.globl _spr_switchin_rc
		.globl _spr_switchin_ptab
	        ; imported debug symbols
	        .globl outstring, outde, outhl, outbc, outnewline, outchar, outcharhex

        .area _COMMONMEM

; ramtop must be in common
_need_resched:
	.db 0

_spr_switchin_stage:
	.db 0

_spr_switchin_sp:
	.dw 0

_spr_switchin_ret:
	.dw 0

_spr_switchin_next:
	.dw 0

_spr_switchin_rc:
	.dw 0

_spr_switchin_ptab:
	.dw 0

_plt_switchout:
        ; save machine state
        ld hl, #0		; return code
        push hl
	ld hl, (_kernel_pages + 1)	; Save the kernel banks
	push hl
        push ix
        push iy
        ld (_udata + U_DATA__U_SP), sp

        ; find another process to run
	push af
        call _getproc
	pop af

	push hl
	push hl
        call _switchin

	; Sprinter bring-up: if _switchin unexpectedly returns, do not
	; hard-stop in _plt_monitor. Return to the C scheduler path so we
	; can keep booting and expose the next real failure.
	ret

badswitchmsg: .ascii "_switchin: FAIL"
        .db 13, 10, 0

_switchin:
        di
	pop hl		; bank
	ld a, l
	cp #0x49
	jr nz, sw_chk_2
	ld a, h
	cp #0x4A
	jr z, sw_have_bank
sw_chk_2:
	ld a, l
	cp #0x4C
	jr nz, sw_chk_3
	ld a, h
	cp #0x4D
	jr z, sw_have_bank
sw_chk_3:
	ld a, l
	cp #0x4E
	jr nz, sw_no_bank
	ld a, h
	cp #0x4F
	jr z, sw_have_bank
sw_no_bank:
	ld b, h		; HL was actually the return address from a direct C call
	ld c, l
	pop af		; SDCC noopt slot precedes the process argument
	pop de		; new process pointer
	ld hl, (_kernel_pages + 1)
	jr sw_stack_ready
sw_have_bank:
	pop bc		; return address
	pop de		; new process pointer
sw_stack_ready:

        push de		; restore stack
        push bc
	push hl

        ld hl, #P_TAB__P_PAGE_OFFSET
	add hl, de
	ld a, (hl)
	or a
	jr nz, notswapped

	;
	;	Swap us in
	;
	push de
	push hl

	push af
	call _get_common
	pop af

	ld a, l
	pop hl
	pop de

	out (TOP_PORT), a
	ld (top_bank), a
	ld sp, #swapstack

	push hl
	push de

	push de			; process
	push af			; page for common
	inc sp
	push af
	call _swap_finish
	pop af
	pop af
	inc sp

	pop de
	pop hl
notswapped:
	inc hl
	inc hl
	inc hl			; common page
	ld a, (hl)
	out (TOP_PORT), a	; *CAUTION* our stack just left the building
	ld (top_bank), a
	ld (mpgsel_cache + 3), a

	; ------- No stack -------
        ; check u_data->u_ptab matches what we wanted
	ld hl, (_udata + U_DATA__U_PTAB)
	or a
	sbc hl, de
	jr nz, switchinfail
switchin_resume:
	ld (_spr_switchin_ptab), de

	ld hl, #P_TAB__P_STATUS_OFFSET
	add hl, de
	ld (hl), #P_RUNNING

        ; runticks = 0
        ld hl, #0
        ld (_runticks), hl

        ; restore machine state
        ld sp, (_udata + U_DATA__U_SP)

	; ---- New task stack ----

	pop iy
	pop ix
	pop hl
	ld a, l
	cp #0x49
	jr nz, kpages_chk_2
	ld a, h
	cp #0x4A
	jr z, kpages_ok
kpages_chk_2:
	ld a, l
	cp #0x4C
	jr nz, kpages_chk_3
	ld a, h
	cp #0x4D
	jr z, kpages_ok
kpages_chk_3:
	ld a, l
	cp #0x4E
	jr nz, bad_kpages
	ld a, h
	cp #0x4F
	jr z, kpages_ok
bad_kpages:
	ld hl, #MAP_BANK1
kpages_ok:
	ld (_kernel_pages + 1), hl
	call map_kernel_restore

	pop hl ; return code
	ld (_spr_switchin_rc), hl

	; Capture the immediate return frame before leaving _switchin.
	; If the target is 0xC000, stop here to preserve the pre-RST frame.
	push hl
	push de
	push bc
	ld hl, #6
	add hl, sp
	ld (_spr_switchin_sp), hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	ld (_spr_switchin_ret), de
	inc hl
	ld c, (hl)
	inc hl
	ld b, (hl)
	ld (_spr_switchin_next), bc
	ld a, #0xE1
	ld (_spr_switchin_stage), a
	ld a, d
	cp #0xC0
	jr nz, sw_ret_ok
	ld a, e
	or a
	jr nz, sw_ret_ok
	ld a, #0xE0
	ld (_spr_switchin_stage), a
sw_ret_c000_hang:
	halt
	jr sw_ret_c000_hang
sw_ret_ok:
	pop bc
	pop de
	pop hl

	; Sprinter bring-up: keep IRQs disabled on return to task context.
	; Current IM2 sources still storm continuously and trap execution in
	; sprinter_bringup_int before userspace can make progress.
	ld a, #1
	ld (_int_disabled), a
	ret

switchinfail:
	; Bring-up recovery: if u_ptab desyncs during switch-in,
	; resync it to the process being switched in and continue
	; instead of halting in monitor with user pages still mapped.
	ld (_udata + U_DATA__U_PTAB), de
	jp switchin_resume

fork_proc_ptr: .dw 0

;
;	Called from _fork. We are in a syscall, the uarea is live as the
;	parent uarea. The kernel is the mapped object.
;
_dofork:
        di

	pop bc
        pop de		; return address
        pop hl		; new process p_tab*
        push hl
        push de
	push bc

	        ld (fork_proc_ptr), hl

	        ; prepare return value in parent process -- HL = p->p_pid;
	        ld de, #P_TAB__P_PID_OFFSET
        add hl, de
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a

        ; Save the stack pointer and critical registers.
        push hl
	ld hl, (_kernel_pages + 1)
	push hl
        push ix
        push iy

        ld (_udata + U_DATA__U_SP), sp

	; PID1 bring-up leaves its allocated common page unseeded while
	; running on 4B. Move the live stack/code onto that owned page so
	; both fork_copy and a later parent switch-in use the saved frame.
	ld a, (mpgsel_cache + 3)
	ld c, a
	ld a, (_udata + U_DATA__U_PAGE + 3)
	cp c
	jr z, fork_top_ready
	call _spr_seed_top
fork_top_ready:
	; --------- we switch stack copies in this call -----------
	call fork_copy

        ; now the copy operation is complete we can get rid of the stuff
        ; _switchin will be expecting from our copy of the stack.
	pop bc
        pop bc
        pop bc
        pop bc

        ; The child makes its own new process table entry
	ld hl, #_udata
	push hl
        ld hl, (fork_proc_ptr)
        push hl
	push af
        call _makeproc
	pop af
        pop bc
	pop bc

        ; runticks = 0;
        ld hl, #0
        ld (_runticks), hl
        ; in the child process, fork() returns zero.
        ret


        .area _COMMONMEM

	.globl mpgsel_cache

; WIN1=A child, WIN2=A parent; WIN3=A child common after the last LDIR.
; Runs from common with a common stack; caller has disabled IRQs.
fork_copy:
	ld hl, (_udata + U_DATA__U_TOP)
	; Match bank16k maps_needed: PROGTOP=E000 reserves an 8K common tail.
	ld de, #0x1fff
	add hl, de
	ld a, h
	rlca
	rlca
	and #3
	inc a
	ld b, a
	; we need to copy the relevant chunks
	ld hl, (fork_proc_ptr)
	ld de, #P_TAB__P_PAGE_OFFSET
	add hl, de
	; hl now points into the child pages
	ld de, #_udata + U_DATA__U_PAGE
	; and de is the parent
fork_next:
		ld a, b
		ld a, (hl)
		cp #0x08
		jr c, fork_next_child_bad
	cp #0x50
	jr c, fork_next_child_ok
fork_next_child_bad:
		ld a, #0x49
fork_next_child_ok:
		out (MPGSEL_1), a	; 0x4000 map the child
		ld c, a
		inc hl
	ld a, (de)
	cp #0x08
	jr c, fork_next_parent_bad
	cp #0x50
	jr c, fork_next_parent_ok
fork_next_parent_bad:
		ld a, #0x4A
fork_next_parent_ok:
		out (MPGSEL_2), a	; 0x8000 maps the parent
	inc de
	exx
	ld hl, #0x8000		; copy the bank
	ld de, #0x4000
	ld bc, #0x4000		; 16K
	ldir
	exx
	call map_kernel		; put the maps back
	djnz fork_next
	ld a, c
	out (MPGSEL_3), a	; our last bank repeats up to common
	; --- we are now on the stack copy ---
	ld (mpgsel_cache+3), a
	ld (top_bank), a
	ret

	.ds 256
swapstack:
