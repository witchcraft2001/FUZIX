;
;	User memory copiers for Sprinter (CONFIG_BANK16)
;
;	Banked SDCC ABI (same as usermem_std-z80-banked / RC2014):
;	  (SP)   return
;	  (SP+2) noopt AF / bank token
;	  (SP+4) first argument
;
;	Never remap WIN0 from here: map helpers that OUT MPGSEL_0 must run
;	from common.  These copiers only window user RAM through WIN1/WIN2.
;

	.module sprinterusermem

	.include "kernel.def"
        .include "../../cpu-z80/kernel-z80.def"

	.globl __uget
	.globl __ugetc
	.globl __ugetw
	.globl __uput
	.globl __uputc
	.globl __uputw
	.globl __uzero
	.globl _uputw
	.globl _spr_uput_win0

	.globl _udata
	.globl mpgsel_cache
	.globl _kernel_pages

        .area _COMMONMEM

; BC packing matches MAP_BANKn: C=WIN1, B=WIN2.
; Do NOT write _kernel_pages here: that is the bank-stub home map.
; Clobbering it from a temporary user WIN1/WIN2 window left the next
; banked bread/ioctl path executing the wrong CODE page (RST38 at
; 0x6480 / mid-_swapread while callno still said ioctl).
;
; Save/restore MUST use _kernel_pages, not mpgsel_cache.  Cache can
; still hold CODE3 after bounce / nested bank_1_3 while PC is in CODE1
; (stub home).  Restoring that stale cache after uputw(TIOCGPGRP→EDE4)
; remapped WIN1/2 to CODE3 and the ioctl epilogue at 0x6480 hit RST38.
; Restore WIN1/WIN2 from C/B via A; preserve IRQ state, clobber A.
restore_k12:
	ld (mpgsel_cache + 1), bc
	ld a, c
	out (MPGSEL_1), a
	ld a, b
	ld (mpgsel_cache + 2), a
	out (MPGSEL_2), a
	ret

; Load stub-home WIN1/2 into BC (clobbers A).
save_k12:
	ld a, (_kernel_pages + 1)
	ld c, a
	ld a, (_kernel_pages + 2)
	ld b, a
	ret

; Map user pages for DE into WIN1/WIN2; return DE in 0x4000-0xBFFF.
; Preserves BC (saved kernel WIN1/WIN2) and IRQ state.
;
; WIN3 holds live kernel common, initially 4B rather than PID1's owned
; u_page[3] until the first fork. Kernel addresses there must stay as-is.
; User addresses below C000 are windowed; C000..DFFF uses live common.
user_map_de:
	ld a, d
	cp #0xC0
	ret nc
	push bc
	push hl
	rlca
	rlca
	and #3
	ld c, a
	ld b, #0
	ld hl, #_udata + U_DATA__U_PAGE
	add hl, bc
	ld a, (hl)
	cp #0x08
	jr c, um_b1_bad
	cp #0x50
	jr c, um_b1_ok
um_b1_bad:
	ld a, #0x08
um_b1_ok:
	ld (mpgsel_cache + 1), a
	out (MPGSEL_1), a
	inc hl
	; WIN2's successor is live WIN3, not PID1's unseeded owned page.
	ld a, c
	cp #2
	jr nz, um_next_page
	ld a, (mpgsel_cache + 3)
	jr um_next_live
um_next_page:
	ld a, (hl)
um_next_live:
	cp #0x08
	jr c, um_b2_bad
	cp #0x50
	jr c, um_b2_ok
um_b2_bad:
	ld a, #0x09
um_b2_ok:
	ld (mpgsel_cache + 2), a
	out (MPGSEL_2), a
	pop hl
	pop bc
	ld a, d
	and #0x3F
	add #0x40
	ld d, a
	ret


__uzero:
	pop iy
	pop de
	pop hl
	pop bc
	push bc
	push hl
	push de
	push iy
	ld a, b
	or c
	ret z
	di
uzero_l:
	push bc
	push hl
	ld e, l
	ld d, h
	call save_k12
	call user_map_de
	xor a
	ld (de), a
	call restore_k12
	pop hl
	pop bc
	inc hl
	dec bc
	ld a, b
	or c
	jr nz, uzero_l
	ld hl, #0
	ret

__uputc:
	pop iy
	pop bc
	pop de			; E = value
	pop hl			; dest
	push hl
	push de
	push bc
	push iy
	di
	ld a, h
	cp #0xC0
	jr nc, uputc_common
	call save_k12
	ex de, hl		; DE=dest, L=value
	push bc
	call user_map_de
	pop bc
	ld a, l
	ld (de), a
	call restore_k12
	ld hl, #0
	ret
; Live common / user stack under PROGTOP: never touch WIN1/2.
; tty_read→uputc (CODE2) after ioctl left BANK2 mapped; a later
; restore from stale kp then landed PC in the C000..EDFF FF hole.
uputc_common:
	ld a, e
	ld (hl), a
	ld hl, #0
	ret

;
; Common _uputw: same body as __uputw (fall through).  CODE1 tty_ioctl
; calls this without a CODE2 bank bounce.
;
; Dest in 0xC000-0xFFFF (live common / user stack under PROGTOP): do
; not touch WIN1/2 at all.  save+restore from _kernel_pages was still
; fatal when kp had been left at CODE3 (bounce / bank_1_3) while PC
; was in CODE1 ioctl — restore then switched hardware to CODE3 and
; the epilogue at 0x6480 executed RST38.
;
_uputw:
__uputw:
	pop iy
	pop bc
	pop de
	pop hl
	push hl
	push de
	push bc
	push iy
	di
	ld a, h
	cp #0xC0
	jr nc, uputw_common
	call save_k12
	push de
	ex de, hl
	call user_map_de
	pop hl
	ld a, l
	ld (de), a
	inc de
	ld a, h
	ld (de), a
	call restore_k12
	ld hl, #0
	ret
uputw_common:
	ex de, hl			; DE = dest in common, HL = value
	ld a, l
	ld (de), a
	inc de
	ld a, h
	ld (de), a
	; If this is ioctl, re-home CODE1 before returning to tty_ioctl.
	ld a, (_udata + U_DATA__U_INSYS)
	or a
	jr z, uputw_ok
	ld a, (_udata + U_DATA__U_CALLNO)
	cp #0x1D
	jr nz, uputw_ok
	ld bc, #0x4A49			; MAP_BANK1
	ld (_kernel_pages + 1), bc
	ld (mpgsel_cache + 1), bc
	ld a, c
	out (MPGSEL_1), a
	ld a, b
	ld (mpgsel_cache + 2), a
	out (MPGSEL_2), a
uputw_ok:
	ld hl, #0
	ret

__ugetc:
	push bc
	push de
	di
	ld e, l
	ld d, h
	ld a, d
	cp #0xC0
	jr nc, ugetc_common
	call save_k12
	call user_map_de
	ld a, (de)
	ld l, a
	ld h, #0
	call restore_k12
	pop de
	pop bc
	ret
ugetc_common:
	ld a, (de)
	ld l, a
	ld h, #0
	pop de
	pop bc
	ret

__ugetw:
	push bc
	push de
	di
	ld e, l
	ld d, h
	ld a, d
	cp #0xC0
	jr nc, ugetw_common
	call save_k12
	call user_map_de
	ld a, (de)
	ld l, a
	inc de
	ld a, (de)
	ld h, a
	call restore_k12
	pop de
	pop bc
	ret
ugetw_common:
	ld a, (de)
	ld l, a
	inc de
	ld a, (de)
	ld h, a
	pop de
	pop bc
	ret

uputget:
	ld c, 10(ix)
	ld b, 11(ix)
	ld l, 6(ix)
	ld h, 7(ix)
	ld e, 8(ix)
	ld d, 9(ix)
	ld a, b
	or c
	ret

;
; Bulk kernel→user copy for exec bounce.  Src must live in WIN0 (always
; mapped); dest is windowed through WIN1/WIN2 once, then one LDIR.
; Banked ABI: args at IX+6/+8/+10 (same as __uput). Crossing BFFF/C000
; uses live WIN3 through the successor window; the kernel stack stays put.
;
_spr_uput_win0:
	push ix
	ld ix, #0
	add ix, sp
	ld l, 6(ix)
	ld h, 7(ix)
	ld e, 8(ix)
	ld d, 9(ix)
	ld c, 10(ix)
	ld b, 11(ix)
	ld a, b
	or c
	jr z, suw_out
	di
	push hl
	call save_k12
	push bc
	call user_map_de
	pop bc
	pop hl
	push bc
	ld c, 10(ix)
	ld b, 11(ix)
	ldir
	pop bc
	call restore_k12
suw_out:
	pop ix
	ld hl, #0
	ret

__uput:
	push ix
	ld ix, #0
	add ix, sp
	call uputget
	jr z, uput_out
	di
uput_l:
	ld a, (hl)
	inc hl
	push bc
	push de
	push hl
	ld l, a
	call save_k12
	call user_map_de
	ld a, l
	ld (de), a
	call restore_k12
	pop hl
	pop de
	pop bc
	inc de
	dec bc
	ld a, b
	or c
	jr nz, uput_l
uput_out:
	pop ix
	ld hl, #0
	ret

__uget:
	push ix
	ld ix, #0
	add ix, sp
	call uputget
	jr z, uget_out
	di
uget_l:
	push bc
	push de
	push hl
	ld e, l
	ld d, h
	call save_k12
	call user_map_de
	ld a, (de)
	; restore_k12 uses A for MPGSEL writes; keep the copied byte.
	push af
	call restore_k12
	pop af
	pop hl
	pop de
	pop bc
	ld (de), a
	inc hl
	inc de
	dec bc
	ld a, b
	or c
	jr nz, uget_l
uget_out:
	pop ix
	ld hl, #0
	ret
