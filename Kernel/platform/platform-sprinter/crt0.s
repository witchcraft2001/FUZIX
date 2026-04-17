;
;	Sprinter (Peters MC 2008) startup code
;

        .module crt0

        ; Ordering of segments for the linker.
	.area _CODE
        .area _HOME
	.area _STUBS
        .area _CONST
        .area _INITIALIZED
        .area _DATA
        .area _BSEG
        .area _BSS
        .area _HEAP
        .area _GSINIT
        .area _GSFINAL
	.area _BUFFERS
        .area _DISCARD
	.area _FONT
	.area _CODE1
	.area _DISCARD1
        .area _CODE2
	.area _DISCARD2
	.area _VECTORS
        .area _COMMONMEM
	.area _COMMONDATA
        .area _INITIALIZER

        ; exported symbols
        .globl init

        ; imported symbols
	.globl _fuzix_main
	.globl init_hardware
	.globl s__INITIALIZER
	.globl s__COMMONMEM
	.globl l__COMMONMEM
        .globl s__DISCARD
        .globl l__DISCARD
        .globl s__BUFFERS
        .globl l__BUFFERS
        .globl s__DATA
        .globl l__DATA
        .globl kstack_top
	.globl mpgsel_cache

	.include "kernel.def"
	.include "../../cpu-z80/kernel-z80.def"

        ; startup code
        .area _CODE

init:
	di

	; ---- Diagnostic marker #1 (border = blue): reached crt0 entry ----
	; Use ZX-compatible port #FE for border tint: writing to Sprinter
	; #C2/#CA port range can clobber the WIN2 page selector.
	ld a, #0x01
	out (0xFE), a

	; Do not touch SYS_PORT_ON/SYS_PORT_OFF here.
	; Switching mode at 0x0102 can remap WIN0 to ROM immediately
	; (observed: PG0 becomes 0x0008), which destroys crt0 execution.
	; Keep mode exactly as bootloader left it.

	; Setup the memory paging for kernel
	; Kernel base pages: 0x48 = WIN0 (CODE), 0x49/0x4A = bank1,
	;                    0x4B = WIN3 (common)
	; WIN0 already points at 0x48 (set by boot loader)
        ld a, #0x49
        out (MPGSEL_1), a       ; map page 1 at 0x4000 (bank1 low)
        ld a, #0x4A
        out (MPGSEL_2), a       ; map page 2 at 0x8000 (bank1 high)
	ld a, #0x4B
        out (MPGSEL_3), a       ; map page 3 at 0xC000 (common)

	; ---- Diagnostic marker #2 (border = red): banking set up ----
	ld a, #0x02
	out (0xFE), a

	; Initialize paging cache used by map_save_kernel/map_restore.
	; If left zeroed, first IRQ would restore WIN0..WIN2 to page 0.
	ld hl, #mpgsel_cache
	ld (hl), #0x48
	inc hl
	ld (hl), #0x49
	inc hl
	ld (hl), #0x4A
	inc hl
	ld (hl), #0x4B

	; switch to a high stack in fixed common window (0xC000-0xFFFF).
	; keep it well above kernel globals/debug buffers around 0xF800.
	ld sp, #0xFC00

	; ---- Diagnostic marker #3 (border = magenta): stack valid ----
	ld a, #0x03
	out (0xFE), a

	; ---- Direct-VRAM banner: write "CRT0" at row 0, col 0..3 ----
	; This bypasses all C/VT infrastructure and proves raw text output
	; works: VRAM page #50 mapped to WIN2, PORT_Y = col+1, writes go
	; to Mode1/Mode2 bytes at 0x8301/0x8302 + row*4.
	call early_banner

	; Zero the data area
	ld bc, #l__DATA
	ld a, b
	or c
	jr z, zero_buffers
	ld hl, #s__DATA
	ld de, #s__DATA + 1
	dec bc
	ld (hl), #0
	ldir

	; Zero buffers area

zero_buffers:
	ld bc, #l__BUFFERS
	ld a, b
	or c
	jr z, zero_done
	ld hl, #s__BUFFERS
	ld de, #s__BUFFERS + 1
	dec bc
	ld (hl), #0
	ldir

zero_done:

	; ---- Diagnostic marker #4 (border = green): BSS/DATA zeroed ----
	ld a, #0x04
	out (0xFE), a

        ; Hardware setup
        call init_hardware

	; ---- Diagnostic marker #5 (border = yellow): init_hardware done ----
	ld a, #0x06
	out (0xFE), a

        ; Call the C main routine
        call _fuzix_main

	; ---- Diagnostic marker (border = white): fuzix_main returned ----
	ld a, #0x07
	out (0xFE), a

        ; fuzix_main() shouldn't return, but if it does...
        di
stop:   halt
        jr stop

;-----------------------------------------------------------------------
; early_banner -- write "CRT0" at VRAM row 0, cols 0..3 and restore WIN2
;
; Uses WIN2 for VRAM access.  Saves/restores MPGSEL_2 via stack so this
; is callable even after banking cache is initialised.  Attr = 0x0F
; (white ink on black paper).
;-----------------------------------------------------------------------
early_banner:
	; Save current WIN2 page selector (we assume it's 0x4A, set above)
	ld a, #0x50			; VRAM page
	out (MPGSEL_2), a

	; Loop over 4 chars at row 0
	ld hl, #banner_text
	ld d, #0			; col counter
eb_loop:
	ld a, (hl)
	or a
	jr z, eb_done
	; PORT_Y = (col + 1) | 0x80  (screen B)
	ld a, d
	inc a
	or #0x80
	out (0x89), a
	; Write char to 0x8301 (row 0: 0x8301 + 0*4)
	ld a, (hl)
	ld (0x8301), a
	ld a, #0x0F			; white on black
	ld (0x8302), a
	inc hl
	inc d
	jr eb_loop
eb_done:
	; Restore WIN2 to kernel bank1 high page 0x4A
	ld a, #0x4A
	out (MPGSEL_2), a
	ret

banner_text:
	.ascii	"CRT0"
	.db	0

;
;	Call stubs are filled in here by the linker
;

	.area _STUBS
	.ds 630

	.area _BUFFERS
