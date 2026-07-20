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

	.globl _udata
	.globl mpgsel_cache
	.globl _kernel_pages

        .area _COMMONMEM

; BC packing matches MAP_BANKn: C=WIN1, B=WIN2
restore_k12:
	ld (_kernel_pages + 1), bc
	ld (mpgsel_cache + 1), bc
	ld a, c
	out (MPGSEL_1), a
	ld a, b
	ld (mpgsel_cache + 2), a
	out (MPGSEL_2), a
	ret

; Map user pages for DE into WIN1/WIN2; return DE in 0x4000-0xBFFF.
; Preserves BC (saved kernel WIN1/WIN2).
user_map_de:
	push bc
	push hl
	ld a, d
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
	ld a, (hl)
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
	ld a, (mpgsel_cache + 1)
	ld c, a
	ld a, (mpgsel_cache + 2)
	ld b, a
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
	ld a, (mpgsel_cache + 1)
	ld c, a
	ld a, (mpgsel_cache + 2)
	ld b, a
	ex de, hl		; DE=dest, L=value
	push bc
	call user_map_de
	pop bc
	ld a, l
	ld (de), a
	call restore_k12
	ld hl, #0
	ret

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
	ld a, (mpgsel_cache + 1)
	ld c, a
	ld a, (mpgsel_cache + 2)
	ld b, a
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

__ugetc:
	push bc
	push de
	di
	ld e, l
	ld d, h
	ld a, (mpgsel_cache + 1)
	ld c, a
	ld a, (mpgsel_cache + 2)
	ld b, a
	call user_map_de
	ld a, (de)
	ld l, a
	ld h, #0
	call restore_k12
	pop de
	pop bc
	ret

__ugetw:
	push bc
	push de
	di
	ld e, l
	ld d, h
	ld a, (mpgsel_cache + 1)
	ld c, a
	ld a, (mpgsel_cache + 2)
	ld b, a
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
	ld a, (mpgsel_cache + 1)
	ld c, a
	ld a, (mpgsel_cache + 2)
	ld b, a
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
	ld a, (mpgsel_cache + 1)
	ld c, a
	ld a, (mpgsel_cache + 2)
	ld b, a
	call user_map_de
	ld a, (de)
	call restore_k12
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
