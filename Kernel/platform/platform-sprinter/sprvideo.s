;
;	Sprinter video driver for ZX-compatible mode
;
;	Text rendering into VRAM page mapped at 0x8000
;	32x24 character grid using 8x8 font
;

        .module sprvideo

        ; exported symbols
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

	; imported
	.globl _fontdata_8x8

        .include "kernel.def"

        .area _VIDEO

; VT attribute capabilities (bit mask)
; 0 = no attributes supported
_vtattr_cap:
	.db 0

;
;	Map VRAM page into WIN2 (0x8000), preserving current mapping
;	Returns previous WIN2 page in B
;
map_screen:
	in a, (MPGSEL_2)	; Sprinter ports are readable
	ld b, a			; save old page
	ld a, #VRAM_PAGE_SCR
	out (MPGSEL_2), a	; map screen to 0x8000
	ret

;
;	Restore WIN2 mapping from B
;
unmap_screen:
	ld a, b
	out (MPGSEL_2), a
	ret

;
;	Compute video position for character at (D=x, E=y)
;	Returns address in DE (within 0x8000 base)
;
;	ZX screen layout: non-linear pixel addressing
;	Address = 0x8000 + (Y7 Y6 Y2 Y1 Y0 Y5 Y4 Y3 X4 X3 X2 X1 X0)
;
videopos:
        ld a, e
        and #7
        rrca
        rrca
        rrca
        add a, d
        ld d, e
        ld e, a
        ld a, d
        and #0x18
        or #0x80	    ; base at 0x8000 (not 0x40 as in original ZX)
        ld d, a
        ret

_plot_char:
	pop iy
        pop hl
        pop de              ; D = x E = y
        pop bc              ; C = character
        push bc
        push de
        push hl
	push iy

	call map_screen
	push bc		    ; save old page

        call videopos

	; Calculate font address
        ld b, #0
        ld a, c
	cp #0x60
	jr nz, nofiddle
	ld a, #0x27
nofiddle:
	or a
        rla
        rl b
        rla
        rl b
        rla
        rl b
        ld c, a

        ld hl, #_fontdata_8x8
        add hl, bc          ; hl points to first byte of char data

        ; Print 8 pixel lines
        ld c, #8
plot_char_loop:
        ld a, (hl)
        ld (de), a
        inc hl
        inc d               ; next screen line
        dec c
        jr nz, plot_char_loop

	pop bc
	jp unmap_screen


_clear_lines:
	pop bc
        pop hl
        pop de              ; E = line, D = count
        push de
        push hl
	push bc

clear_next_line:
        push de
        ld d, #0
        ld b, d
        ld c, #32
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
        jr nz, clear_next_line

        ret


_clear_across:
	pop iy
        pop hl
        pop de              ; DE = coords
        pop bc              ; C = count
        push bc
        push de
        push hl
	push iy

	call map_screen
	push bc			; save old page (in B)

        call videopos
        push de
        pop hl
        xor a

clear_line:
        ld b, #8
clear_char:
        ld (de), a
        inc d
        dec b
        jr nz, clear_char

        ex de, hl
        inc de
        push de
        pop hl

        dec c
        jr nz, clear_line

	pop bc
	jp unmap_screen

copy_line:
        ; HL - source line, DE - destination line
        push de
        ex de, hl
        call videopos
        ex de, hl
        pop de
        call videopos

        ld c, #8

copy_line_nextchar:
        push hl
        push de

        ld b, #32

copy_pixel_line:
        ld a, (hl)
        ld (de), a
        inc e
        inc l
        dec b
        jr nz, copy_pixel_line

        pop de
        pop hl
        inc d
        inc h
        dec c
        jr nz, copy_line_nextchar
        ret


_scroll_down:
	call map_screen
	push bc

        xor a
        ld d, a
        ld h, a
        ld l, #22
        ld e, #23
        ld c, #23

loop_scroll_down:
        push hl
        push de
        push bc
        call copy_line
        pop bc
        pop de
        pop hl
        dec l
        dec e
        dec c
        jr nz, loop_scroll_down

	pop bc
	jp unmap_screen


_scroll_up:
	call map_screen
	push bc

        xor a
        ld d, a
        ld e, a
        ld h, a
        ld l, #1
        ld c, #23

loop_scroll_up:
        push hl
        push de
        push bc
        call copy_line
        pop bc
        pop de
        pop hl
        inc l
        inc e
        dec c
        jr nz, loop_scroll_up

	pop bc
	jp unmap_screen

_cursor_on:
	pop bc
        pop hl
        pop de
        push de
        push hl
	push bc
        ld (cursorpos), de

	call map_screen
	push bc

        call videopos
        ld a, #7
        add a, d
        ld d, a
        ld a, #0xFF
        ld (de), a

	pop bc
	jp unmap_screen

_cursor_disable:
_cursor_off:
        ld de, (cursorpos)

	call map_screen
	push bc

        call videopos
        ld a, #7
        add a, d
        ld d, a
        xor a
        ld (de), a

	pop bc
	jp unmap_screen

_vtattr_notify:
        ret

_do_beep:
        ld e, #0xFF
        ld c, #0xFE
        ld l, #0x10
loop_beep:
        ld a, l
        out (c), a
        xor a
        out (c), a
        dec bc
        ld a, b
        or c
        jr nz, loop_beep
        ret

        .area _DATA

cursorpos:
        .dw 0
