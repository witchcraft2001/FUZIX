;
;	User memory copiers for Sprinter (CONFIG_BANK16)
;
;	Based on the RC2014 optimized version.
;	We can use 0x4000-0xBFFF as a 32K window since those banks
;	contain only code from the kernel's perspective and are never
;	eligible locations to copy to/from.
;

	.module sprinterusermem

	.include "kernel.def"
        .include "../../cpu-z80/kernel-z80.def"

        ; exported symbols
        .globl __uget
        .globl __ugetc
        .globl __ugetw

        .globl __uput
        .globl __uputc
        .globl __uputw
        .globl __uzero

	.globl _udata

	.globl map_kernel
	.globl  map_proc_save_u
	.globl  map_kernel_restore_u

	.globl mpgsel_cache

;
;	We need these in common as they bank switch
;
        .area _COMMONMEM

;
;	Zero a chunk of memory.
;
__uzero:
	pop iy
	pop de	; return
	pop hl	; address
	pop bc	; size
	push bc
	push hl
	push de
	push iy
	ld a, b	; check for 0 copy
	or c
	ret z
	call map_proc_save_u
	ld (hl), #0
	dec bc
	ld a, b
	or c
	jp z, uputc_out
	ld e, l
	ld d, h
	inc de
	ldir
	jr uputc_out

__uputc:
	pop iy
	pop bc
	pop de	; char
	pop hl	; dest
	push hl
	push de
	push bc
	push iy
	call map_proc_save_u
	ld (hl), e
uputc_out:
	ld hl, #0
	jp map_kernel_restore_u

__uputw:
	pop iy
	pop bc
	pop de	; word
	pop hl	; dest
	push hl
	push de
	push bc
	push iy
	call map_proc_save_u
	ld (hl), e
	inc hl
	ld (hl), d
	jr uputc_out

__ugetc:
	call map_proc_save_u
        ld l, (hl)
	ld h, #0
	jp map_kernel_restore_u

__ugetw:
	call map_proc_save_u
        ld a, (hl)
	inc hl
	ld h, (hl)
	ld l, a
	jp map_kernel_restore_u

;
;	General helper to get the C arguments off the stack.
;
uputget:
        ; load BC with the byte count
        ld c, 10(ix) ; byte count
        ld b, 11(ix)
        ; load HL with the source address
        ld l, 6(ix) ; src address
        ld h, 7(ix)
        ; load DE with destination address
        ld e, 8(ix)
        ld d, 9(ix)
	ld a, b
	or c
	ret

;
;	_uput() C signature is _uput(source, user, count), so after
;	`push ix; ld ix, #0; add ix, sp` (and the SDCC noopt AF save
;	before the call) the stack layout is:
;	 6(ix)  source
;	 8(ix)  destination (user)
;	10(ix)  byte count
;
;	The previous version loaded BC from 8(ix) and DE from 10(ix)
;	-- i.e. BC=dst, DE=count -- which swapped the two, so the
;	fast path's `ldir` treated the destination pointer as a
;	count and the slow path wrote every source byte to the same
;	remapped address derived from `count`.  Result: the binary
;	never actually landed in user RAM.
;
uputget_put:
	; load BC with the byte count (arg 2)
	ld c, 10(ix)
	ld b, 11(ix)
	; load HL with source address (arg 0)
	ld l, 6(ix)
	ld h, 7(ix)
	; load DE with destination user address (arg 1)
	ld e, 8(ix)
	ld d, 9(ix)
	ld a, b
	or c
	ret

;
;	Make the user pages holding DE upwards appear at 0x4000-0xBFFF
;	Return an updated DE with the mapped address.
;
user_map_de:
	ld a, d
	exx
	rlca
	rlca
	and #3
	ld e, a
	ld d, #0
	ld hl, #_udata + U_DATA__U_PAGE
	add hl, de
	ld a, (hl)
	cp #0x08
	jr c, user_map_de_b1_bad
	cp #0x50
	jr c, user_map_de_b1_ok
user_map_de_b1_bad:
	ld a, #0x08
user_map_de_b1_ok:
	ld (mpgsel_cache + 1), a
	out (MPGSEL_1), a
	inc hl
	ld a, (hl)
	cp #0x08
	jr c, user_map_de_b2_bad
	cp #0x50
	jr c, user_map_de_b2_ok
user_map_de_b2_bad:
	ld a, #0x09
user_map_de_b2_ok:
	ld (mpgsel_cache + 2), a
	out (MPGSEL_2), a
	exx

	ld a, d
	and #0x3F
	add #0x40
	ld d, a
	ret

;
;	Copy data to user space
;
__uput:
	push ix
	ld ix, #0
	add ix, sp
	call uputget_put		; source in HL, dest in DE, count in BC
	jr z, uput_out

uput_l:
	ld a, (hl)
	inc hl
	push bc
	push hl
	push af
	ex de, hl
	call map_proc_save_u
	pop af
	ld (hl), a
	call map_kernel_restore_u
	ex de, hl
	pop hl
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

;
;	Copy data from user space
;
__uget:
	push ix
	ld ix, #0
	add ix, sp
	call uputget			; source in HL, dest in DE, count in BC
	jr z, uput_out

uget_l:
	push bc
	push de
	call map_proc_save_u
	ld a, (hl)
	inc hl
	push af
	call map_kernel_restore_u
	pop af
	pop de
	pop bc
	ld (de), a
	inc de
	dec bc
	ld a, b
	or c
	jr nz, uget_l
	jr uput_out
