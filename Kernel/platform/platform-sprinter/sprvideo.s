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
        .globl mpgsel_cache
        .globl _sprinter_dbg

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
;
; NOTE: the saved page MUST live in a static variable -- using `push af`
; here would put the saved byte on top of the caller's return address,
; and `ret` would then jump to the saved value instead of returning to
; the caller.  sprvideo is not expected to be called recursively or
; reentrantly while VRAM is mapped, so a single scalar is enough.
;----------------------------------------------------------------------
map_vr:
        ld a, (map_vr_depth)
        or a
        jr nz, map_vr_nested
        ; MPGSEL ports are not reliably readable on Sprinter.
        ; Use software cache maintained by map layer.
        ld a, (mpgsel_cache + 2)
        ld (saved_vr_page), a
        ld a, #VRAM_TEXT
        out (MPGSEL_2), a
        ld (mpgsel_cache + 2), a
map_vr_nested:
        ld hl, #map_vr_depth
        inc (hl)
        ret

;----------------------------------------------------------------------
; unmap_vr: restore WIN2 page saved by map_vr
; Destroys: A
;----------------------------------------------------------------------
unmap_vr:
        ld a, (map_vr_depth)
        or a
        ret z
        dec a
        ld (map_vr_depth), a
        ret nz
        ld a, (saved_vr_page)
        cp #0x50
        jr c, unmap_vr_ok
        ld a, #0x4A
unmap_vr_ok:
        out (MPGSEL_2), a
        ld (mpgsel_cache + 2), a
        ret

;----------------------------------------------------------------------
; cell_hl: set RGADR and compute char address for cell (D=col, E=row)
; On entry:  D = col (0..79), E = row (0..31)
; On exit:   HL = 0x8301 + row*4  (Mode1 / char byte in WIN2)
;            RGADR (VID_PAGE) set to (col+1) | 0x80 -- screen B selector
; Destroys:  A
; WIN2 must already be mapped to VRAM page #50 (via map_vr)
;
; Sprinter text mode has two independent VRAM screens:
;   Screen A: PORT_Y = col + 1         (pages #50-#54)
;   Screen B: PORT_Y = (col + 1) | #80 (pages #55-#59)
;
; BIOS initialises the Mode0 display-mode bytes only for whichever
; screen it is currently using (RGMOD bit 0).  On observed boot state
; RGMOD = 1 -> screen B is live, and screen A's Mode0 bytes are still
; un-programmed, so they render as BORDER and any writes to screen A
; are invisible.  We therefore target screen B (bit 7 in PORT_Y) and
; let BIOS' cell initialisation stand.
;
; VRAM cell layout (from manual 05_graphics/08_text_mode.md):
;   LA + 0  Mode0  display-mode byte, set by BIOS -- DO NOT OVERWRITE
;   LA + 1  Mode1  character code
;   LA + 2  Mode2  attribute (INK/PAPER)
;   LA + 3  Mode3  reserved
; where LA = 0x8300 + row*4 when WIN2 holds VRAM page 0x50.
;----------------------------------------------------------------------
cell_hl:
        ld a, d
        inc a
        or #0x80		; screen B select (bit 7)
        out (VID_PAGE), a	; RGADR = (col + 1) | 0x80
        ld a, e
        rlca
        rlca			; A = row * 4
        ld l, a
        ld h, #0x83		; HL = 0x8300 + row*4  (Mode0 base)
        inc l			; HL = 0x8301 + row*4  (Mode1, char byte)
        ret

;----------------------------------------------------------------------
; _plot_char(int8_t y, int8_t x, uint16_t c)
;
; Caller layout (SDCC sdcccall(0) with `push af;noopt` optimisation):
;   SP+0..1 = return address
;   SP+2..3 = noopt AF frame (pushed by the `push af;noopt` before call)
;   SP+4    = y (int8_t)
;   SP+5    = x (int8_t)
;   SP+6..7 = c (uint16_t, char code in low byte)
;
; We follow the zx128/zxuno convention: pop the two extra frames (ret +
; noopt) into IY/HL, pop args into DE/BC, then restore symmetrically so
; a trailing `jp unmap_vr` / `ret` returns to the original caller.
;----------------------------------------------------------------------
_plot_char:
        pop iy			; return address
        pop hl			; noopt AF placeholder
        pop de			; D = x (col), E = y (row)
        pop bc			; C = character code
        push bc
        push de
        push hl
        push iy

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
        pop iy			; return address
        pop hl			; noopt AF placeholder
        pop de			; D = x (col), E = y (row)
        pop bc			; C = count
        push bc
        push de
        push hl
        push iy

        call map_vr
        ld b, e			; B = row (constant for this call)
ca_loop:
        ld a, c
        or a
        jr z, ca_done
        ld a, d
        inc a
        or #0x80		; screen B selector (bit 7)
        out (VID_PAGE), a	; RGADR = (col + 1) | 0x80
        ld a, b			; row
        rlca
        rlca			; A = row * 4
        ld l, a
        ld h, #0x83		; HL = 0x8300 + row*4  (Mode0)
        inc l			; HL = 0x8301 + row*4  (Mode1, char)
        ld (hl), #0x20		; space
        inc hl			; -> Mode2 (attr)
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
        pop iy			; return address
        pop hl			; noopt AF placeholder
        pop de			; D = count, E = start row
        push de
        push hl
        push iy

cl_loop:
        ld a, d
        or a
        ret z
        push de			; save (D=remaining count, E=current row)
        ld d, #0		; x = 0
        ld bc, #80		; count = 80
        push bc			; count word
        push de			; (D=0=x, E=row=y)
        push af			; noopt AF placeholder so callee sees the
				; same frame layout as an SDCC-generated call
        call _clear_across
        pop af			; noopt cleanup
        pop de			; args cleanup
        pop bc
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
        ; Set RGADR for current col (same for src and dst); screen B
        ld a, d
        inc a
        or #0x80
        out (VID_PAGE), a

        ; Read char + attr from src row (e+1)
        push de			; save (D=col, E=dst_row)
        inc e			; src_row = dst_row + 1
        ld a, e
        rlca
        rlca			; A = src_row * 4
        ld l, a
        ld h, #0x83		; HL = 0x8300 + src_row*4 (Mode0)
        inc l			; HL = 0x8301 + src_row*4 (Mode1, char)
        ld a, (hl)		; char
        inc hl			; -> Mode2 (attr)
        ld c, (hl)		; attr -> C
        pop de			; restore (D=col, E=dst_row)

        ; Write char + attr to dst row (e)
        push bc			; save attr in C
        push af			; save char in A
        ld a, e
        rlca
        rlca			; A = dst_row * 4
        ld l, a
        ld h, #0x83		; HL = 0x8300 + dst_row*4 (Mode0)
        inc l			; HL = 0x8301 + dst_row*4 (Mode1, char)
        pop af			; restore char
        ld (hl), a		; write char
        inc hl			; -> Mode2 (attr)
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
        push af			; noopt AF placeholder
        call _clear_across
        pop af
        pop de
        pop bc
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
        ; Set RGADR for current col; screen B selector
        ld a, d
        inc a
        or #0x80
        out (VID_PAGE), a

        ; Read char + attr from src row (e-1)
        push de			; save (D=col, E=dst_row)
        dec e			; src_row = dst_row - 1
        ld a, e
        rlca
        rlca			; A = src_row * 4
        ld l, a
        ld h, #0x83		; HL = 0x8300 + src_row*4 (Mode0)
        inc l			; HL = 0x8301 + src_row*4 (Mode1, char)
        ld a, (hl)		; char
        inc hl			; -> Mode2 (attr)
        ld c, (hl)		; attr -> C
        pop de			; restore (D=col, E=dst_row)

        ; Write char + attr to dst row (e)
        push bc
        push af
        ld a, e
        rlca
        rlca			; A = dst_row * 4
        ld l, a
        ld h, #0x83		; HL = 0x8300 + dst_row*4 (Mode0)
        inc l			; HL = 0x8301 + dst_row*4 (Mode1, char)
        pop af
        ld (hl), a		; write char
        inc hl			; -> Mode2 (attr)
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
        push af			; noopt AF placeholder
        call _clear_across
        pop af
        pop de
        pop bc
        ret

;----------------------------------------------------------------------
; _cursor_on(int8_t y, int8_t x)
;
; Saves cursor position and inverts the attribute at (x, y).
;----------------------------------------------------------------------
_cursor_on:
        pop iy			; return address
        pop hl			; noopt AF placeholder
        pop de			; D = x (col), E = y (row)
        push de
        push hl
        push iy
        ld a, #0xEC
        ld (_sprinter_dbg + 15), a
        ld a, e
        ld (_sprinter_dbg + 21), a
        ld a, d
        ld (_sprinter_dbg + 22), a
        ; Save cursor position (H=x, L=y -> stored as 16-bit HL)
        ld h, d
        ld l, e
        ld (cursorpos), hl

        call map_vr
        ld a, #0xED
        ld (_sprinter_dbg + 15), a
        ; Reload D=x, E=y for cell_hl (HL was overwritten by ld (cursorpos),hl)
        ld hl, (cursorpos)
        ld d, h
        ld e, l
        call cell_hl
        ld a, #0xEE
        ld (_sprinter_dbg + 15), a
        inc hl			; point to attribute byte
        ld a, (hl)
        xor #0xFF		; invert attribute
        ld (hl), a
        ld a, #0xEF
        ld (_sprinter_dbg + 15), a
        call unmap_vr
        ld a, #0xF0
        ld (_sprinter_dbg + 15), a
        ret

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

;
; On Sprinter _DATA lives in WIN0 (s__DATA ~0x0FEA), which map_vr never
; remaps.  Do not put these in _COMMONDATA (overcrowded / aliased) or in
; the middle of _CODE (shifts the CODE layout and broke /init open).
;
        .area _DATA
cursorpos:
        .dw 0
saved_vr_page:
        .db 0
map_vr_depth:
        .db 0
