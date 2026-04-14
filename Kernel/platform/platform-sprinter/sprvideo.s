;
;	Sprinter native 80x32 text mode video driver
;
;	Hardware text mode: 2 bytes per cell (char code + color attribute).
;	Font (знакогенератор) loaded by BIOS into VRAM at power-on.
;
;	VRAM addressing (VIDEO2.TDF, VCM=3, CT5=0 for char data):
;	  VRAM page  = #50 + (col >> 3)
;	  offset     = ((col & 7) << 11) | 0x0300 | (row << 2)
;	  Char code at offset+0, attribute at offset+1
;
;	We map the needed VRAM page into WIN2 (0x8000-0xBFFF) temporarily.
;

        .module sprvideo

        .globl _plot_char
        .globl _scroll_down
        .globl _scroll_up
        .globl _cursor_on
        .globl _cursor_off
        .globl _cursor_disable
        .globl _clear_lines
        .globl _clear_across
        .globl _do_beep
	.globl _vtattr_notify
	.globl _vtattr_cap

        .include "kernel.def"

        .area _VIDEO

_vtattr_cap:
	.db 0

;----------------------------------------------------------------------
; Default text attribute: white ink (0xF) on black paper (0x0)
;----------------------------------------------------------------------
DATTR	.equ	0x0F

;----------------------------------------------------------------------
; videopos: compute VRAM page + address for cell (D=col, E=row)
;
; Returns: C = VRAM page number
;          HL = address within WIN2 (0x8000 + offset)
; Destroys: A
;----------------------------------------------------------------------
videopos:
	; page = #50 + (col >> 3)
	ld a, d
	srl a
	srl a
	srl a
	add a, #0x50		; VRAM_PAGE_SCR base
	ld c, a

	; offset high byte: ((col & 7) << 3) | 0x03
	ld a, d
	and #0x07
	rlca
	rlca
	rlca			; (col&7) << 3  — becomes bits 13:11
	or #0x03		; set bits 9:8 = constant 11
	add a, #0x80		; add WIN2 base 0x8000
	ld h, a

	; offset low byte: (row << 2)
	ld a, e
	rlca
	rlca
	and #0xFC
	ld l, a
	ret

;----------------------------------------------------------------------
; Helpers: map / unmap VRAM page in WIN2
; map_vr: maps page C into WIN2, pushes old page
; unmap_vr: pops and restores old WIN2 page
;----------------------------------------------------------------------
map_vr:
	in a, (MPGSEL_2)
	push af			; save current WIN2 page
	ld a, c
	out (MPGSEL_2), a
	ret

unmap_vr:
	pop af			; saved page from map_vr
	out (MPGSEL_2), a
	ret

;----------------------------------------------------------------------
; _plot_char(uint8_t y, uint8_t x, uint16_t c)
;----------------------------------------------------------------------
_plot_char:
	pop iy
        pop hl
        pop de              ; D = x (col), E = y (row)
        pop bc              ; C = character code
        push bc
        push de
        push hl
	push iy

	call videopos		; C=page, HL=addr
	call map_vr

        ld (hl), c          ; character
	inc hl
	ld (hl), #DATTR     ; attribute

	jp unmap_vr		; restore and return


;----------------------------------------------------------------------
; _clear_lines(uint8_t row, uint8_t count)
;----------------------------------------------------------------------
_clear_lines:
	pop bc
        pop hl
        pop de              ; E = start row, D = count
        push de
        push hl
	push bc

cl_next:
	push de
	ld d, #0
	ld b, d
	ld c, #80
	push bc
	push de
	push af
	call _clear_across
	pop af
	pop hl
	pop hl
	pop de
	inc e
	dec d
	jr nz, cl_next
	ret


;----------------------------------------------------------------------
; _clear_across(uint8_t y, uint8_t x, uint16_t count)
;
; Clear 'count' cells starting at (x, y)
;----------------------------------------------------------------------
_clear_across:
	pop iy
        pop hl
        pop de              ; D = x (col), E = y (row)
        pop bc              ; C = count
        push bc
        push de
        push hl
	push iy

	; We process one character at a time because cells
	; span across different VRAM pages (8 cols per page).
	; For a fast path, we could batch within a page,
	; but simplicity first.
ca_loop:
	ld a, c
	or a
	ret z
	push bc
	push de
	call videopos		; C=page, HL=addr
	call map_vr
	ld (hl), #0x20		; space
	inc hl
	ld (hl), #DATTR
	call unmap_vr
	pop de
	pop bc
	inc d			; next column
	dec c
	jr ca_loop


;----------------------------------------------------------------------
; _scroll_up: scroll entire screen up by one line
;----------------------------------------------------------------------
_scroll_up:
	; Copy rows 1..31 to 0..30, then clear row 31
	ld b, #31		; 31 rows to copy

	ld e, #0		; dest row
su_row:
	push bc
	push de
	ld d, #0		; start col
	ld b, #80
su_col:
	push bc
	push de
	; Read (col=D, row=E+1)
	inc e
	call videopos
	call map_vr
	ld a, (hl)		; char
	inc hl
	ld c, (hl)		; attr in C
	call unmap_vr
	; A=char, C=attr
	pop de
	push de
	; Write (col=D, row=E)
	push af
	push bc			; save attr
	call videopos
	call map_vr
	pop bc			; C=attr
	pop af			; A=char
	ld (hl), a
	inc hl
	ld (hl), c
	call unmap_vr
	pop de
	pop bc
	inc d
	djnz su_col

	pop de
	pop bc
	inc e
	djnz su_row

	; Clear bottom line
	ld d, #0
	ld e, #31
	ld b, #0
	ld c, #80
	push bc
	push de
	ld hl, #0
	push hl
	push iy
	call _clear_across
	pop iy
	pop hl
	pop hl
	pop hl
	ret


;----------------------------------------------------------------------
; _scroll_down: scroll entire screen down by one line
;----------------------------------------------------------------------
_scroll_down:
	ld b, #31
	ld e, #31		; dest row
sd_row:
	push bc
	push de
	ld d, #0
	ld b, #80
sd_col:
	push bc
	push de
	; Read (col=D, row=E-1)
	dec e
	call videopos
	call map_vr
	ld a, (hl)
	inc hl
	ld c, (hl)
	call unmap_vr
	pop de
	push de
	; Write (col=D, row=E)
	push af
	push bc
	call videopos
	call map_vr
	pop bc
	pop af
	ld (hl), a
	inc hl
	ld (hl), c
	call unmap_vr
	pop de
	pop bc
	inc d
	djnz sd_col

	pop de
	pop bc
	dec e
	djnz sd_row

	; Clear top line
	ld d, #0
	ld e, #0
	ld b, #0
	ld c, #80
	push bc
	push de
	ld hl, #0
	push hl
	push iy
	call _clear_across
	pop iy
	pop hl
	pop hl
	pop hl
	ret


;----------------------------------------------------------------------
; _cursor_on(uint8_t y, uint8_t x)
;----------------------------------------------------------------------
_cursor_on:
	pop bc
        pop hl
        pop de
        push de
        push hl
	push bc
        ld (cursorpos), de

	call videopos
	call map_vr
	inc hl			; point to attribute
	ld a, (hl)
	xor #0xFF		; invert
	ld (hl), a
	jp unmap_vr

;----------------------------------------------------------------------
; _cursor_off / _cursor_disable
;----------------------------------------------------------------------
_cursor_disable:
_cursor_off:
        ld de, (cursorpos)
	call videopos
	call map_vr
	inc hl
	ld (hl), #DATTR		; restore default attr
	jp unmap_vr

_vtattr_notify:
        ret

;----------------------------------------------------------------------
; _do_beep: simple beep via ZX beeper port
;----------------------------------------------------------------------
_do_beep:
        ld e, #0xFF
        ld c, #0xFE
        ld l, #0x10
beep_loop:
        ld a, l
        out (c), a
        xor a
        out (c), a
        dec bc
        ld a, b
        or c
        jr nz, beep_loop
        ret

        .area _DATA
cursorpos:
        .dw 0
