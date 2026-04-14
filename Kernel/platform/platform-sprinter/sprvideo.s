;
;	Sprinter native 80x32 text mode video driver
;
;	Hardware text mode (ALL_MODE port #C3, value #03):
;	  2 bytes per cell: char code + colour attribute.
;	  Font loaded by BIOS into VRAM at power-on.
;
;	VRAM access per cell (col 0..79, row 0..31):
;	  1. Map VRAM page #50 into WIN2 (0x8000-0xBFFF) via port MPGSEL_2
;	  2. Set RGADR (VID_PAGE, port #89) = col + 1
;	  3. char byte at 0x8300 + row*4
;	  4. attr byte at 0x8301 + row*4
;
;	SDCC Z80 calling convention (old style, sdcccall(0)):
;	  Two int8_t args packed into one 16-bit word: first arg in E, second in D.
;	  Additional args pushed separately (low-byte in C).
;	  Return address popped into HL at function entry.
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

        .area _CODE

_vtattr_cap:
        .db 0

;----------------------------------------------------------------------
; Default text attribute: white ink (0xF) on black paper (0x0)
;----------------------------------------------------------------------
DATTR		.equ	0x0F

;----------------------------------------------------------------------
; VRAM page for text mode
;----------------------------------------------------------------------
VRAM_TEXT	.equ	0x50

;----------------------------------------------------------------------
; map_vr: save current WIN2 page, map VRAM page #50 into WIN2
; Destroys: A
;----------------------------------------------------------------------
map_vr:
        in a, (MPGSEL_2)
        push af
        ld a, #VRAM_TEXT
        out (MPGSEL_2), a
        ret

;----------------------------------------------------------------------
; unmap_vr: restore WIN2 page saved by map_vr
; Destroys: A (flags)
;----------------------------------------------------------------------
unmap_vr:
        pop af
        out (MPGSEL_2), a
        ret

;----------------------------------------------------------------------
; cell_hl: set RGADR and compute char address for cell (D=col, E=row)
; On entry:  D = col (0..79), E = row (0..31)
; On exit:   HL = 0x8300 + row*4  (char byte address in WIN2)
;            RGADR (VID_PAGE) set to col+1
; Destroys:  A
; WIN2 must already be mapped to VRAM page #50 (via map_vr)
;----------------------------------------------------------------------
cell_hl:
        ld a, d
        inc a
        out (VID_PAGE), a	; RGADR = col + 1
        ld a, e
        rlca
        rlca			; A = row * 4
        ld l, a
        ld h, #0x83		; HL = 0x8300 + row*4
        ret

;----------------------------------------------------------------------
; _plot_char(int8_t y, int8_t x, uint16_t c)
;----------------------------------------------------------------------
_plot_char:
        pop hl
        pop de			; D = x (col), E = y (row)
        pop bc			; C = character code
        push bc
        push de
        push hl

        call map_vr
        call cell_hl
        ld (hl), c		; write character
        inc hl
        ld (hl), #DATTR		; write attribute
        jp unmap_vr

;----------------------------------------------------------------------
; _clear_across(int8_t y, int8_t x, int16_t count)
;
; Clears 'count' cells starting at (x, y) with space + DATTR.
; count is expected to fit in C (max 80).
;----------------------------------------------------------------------
_clear_across:
        pop hl
        pop de			; D = x (col), E = y (row)
        pop bc			; C = count
        push bc
        push de
        push hl

        call map_vr
        ld b, e			; B = row (constant for this call)
ca_loop:
        ld a, c
        or a
        jr z, ca_done
        ld a, d
        inc a
        out (VID_PAGE), a	; RGADR = col + 1
        ld a, b			; row
        rlca
        rlca			; A = row * 4
        ld l, a
        ld h, #0x83		; HL = 0x8300 + row*4
        ld (hl), #0x20		; space
        inc hl
        ld (hl), #DATTR		; attribute
        inc d			; next col
        dec c
        jr ca_loop
ca_done:
        jp unmap_vr

;----------------------------------------------------------------------
; _clear_lines(int8_t y, int8_t count)
;
; Clears 'count' full rows starting at row y.
;----------------------------------------------------------------------
_clear_lines:
        pop hl
        pop de			; D = count, E = start row
        push de
        push hl

cl_loop:
        ld a, d
        or a
        ret z
        push de			; save (D=remaining count, E=current row)
        ld d, #0		; x = 0
        ld bc, #80		; count = 80
        push bc			; push count
        push de			; push (D=0=x, E=row=y)
        call _clear_across
        pop bc			; cleanup
        pop de			; cleanup
        pop de			; restore (D=remaining, E=row)
        inc e			; next row
        dec d			; decrement count
        jr cl_loop

;----------------------------------------------------------------------
; _scroll_up: scroll entire screen up by one row
;
; Copies rows 1..31 to rows 0..30, then clears row 31.
;----------------------------------------------------------------------
_scroll_up:
        call map_vr

        ld b, #31		; 31 rows to copy
        ld e, #0		; dest row = 0
su_row:
        push bc
        push de
        ld d, #0		; col = 0
su_col:
        ; Set RGADR for current col (same for src and dst)
        ld a, d
        inc a
        out (VID_PAGE), a

        ; Read char + attr from src row (e+1)
        push de			; save (D=col, E=dst_row)
        inc e			; src_row = dst_row + 1
        ld a, e
        rlca
        rlca			; A = src_row * 4
        ld l, a
        ld h, #0x83		; HL = 0x8300 + src_row*4
        ld a, (hl)		; char
        inc hl
        ld c, (hl)		; attr -> C
        pop de			; restore (D=col, E=dst_row)

        ; Write char + attr to dst row (e)
        push bc			; save attr in C
        push af			; save char in A
        ld a, e
        rlca
        rlca			; A = dst_row * 4
        ld l, a
        ld h, #0x83		; HL = 0x8300 + dst_row*4
        pop af			; restore char
        ld (hl), a		; write char
        inc hl
        pop bc			; restore attr
        ld (hl), c		; write attr

        inc d
        ld a, d
        cp #80
        jr nz, su_col

        pop de
        pop bc
        inc e			; next dst row
        djnz su_row

        call unmap_vr

        ; Clear bottom row 31
        ld e, #31		; y = 31
        ld d, #0		; x = 0
        ld bc, #80
        push bc
        push de
        call _clear_across
        pop bc
        pop de
        ret

;----------------------------------------------------------------------
; _scroll_down: scroll entire screen down by one row
;
; Copies rows 30..0 to rows 31..1, then clears row 0.
;----------------------------------------------------------------------
_scroll_down:
        call map_vr

        ld b, #31
        ld e, #31		; dest row = 31
sd_row:
        push bc
        push de
        ld d, #0
sd_col:
        ; Set RGADR for current col
        ld a, d
        inc a
        out (VID_PAGE), a

        ; Read char + attr from src row (e-1)
        push de			; save (D=col, E=dst_row)
        dec e			; src_row = dst_row - 1
        ld a, e
        rlca
        rlca			; A = src_row * 4
        ld l, a
        ld h, #0x83		; HL = 0x8300 + src_row*4
        ld a, (hl)		; char
        inc hl
        ld c, (hl)		; attr -> C
        pop de			; restore (D=col, E=dst_row)

        ; Write char + attr to dst row (e)
        push bc
        push af
        ld a, e
        rlca
        rlca			; A = dst_row * 4
        ld l, a
        ld h, #0x83		; HL = 0x8300 + dst_row*4
        pop af
        ld (hl), a		; write char
        inc hl
        pop bc
        ld (hl), c		; write attr

        inc d
        ld a, d
        cp #80
        jr nz, sd_col

        pop de
        pop bc
        dec e			; next dst row (working upward)
        djnz sd_row

        call unmap_vr

        ; Clear top row 0
        ld e, #0		; y = 0
        ld d, #0		; x = 0
        ld bc, #80
        push bc
        push de
        call _clear_across
        pop bc
        pop de
        ret

;----------------------------------------------------------------------
; _cursor_on(int8_t y, int8_t x)
;
; Saves cursor position and inverts the attribute at (x, y).
;----------------------------------------------------------------------
_cursor_on:
        pop hl
        pop de			; D = x (col), E = y (row)
        push de
        push hl
        ; Save cursor position (H=x, L=y -> stored as 16-bit HL)
        ld h, d
        ld l, e
        ld (cursorpos), hl

        call map_vr
        ; Reload D=x, E=y for cell_hl (HL was overwritten by ld (cursorpos),hl)
        ld hl, (cursorpos)
        ld d, h
        ld e, l
        call cell_hl
        inc hl			; point to attribute byte
        ld a, (hl)
        xor #0xFF		; invert attribute
        ld (hl), a
        jp unmap_vr

;----------------------------------------------------------------------
; _cursor_off / _cursor_disable
;
; Restores the default attribute at the saved cursor position.
;----------------------------------------------------------------------
_cursor_disable:
_cursor_off:
        ld hl, (cursorpos)
        ld d, h
        ld e, l
        call map_vr
        call cell_hl
        inc hl
        ld (hl), #DATTR		; restore default attribute
        jp unmap_vr

_vtattr_notify:
        ret

;----------------------------------------------------------------------
; _do_beep: tone via ZX beeper port (#FE)
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
