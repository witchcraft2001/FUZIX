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

	.include "kernel.def"
	.include "../../cpu-z80/kernel-z80.def"

        ; startup code
        .area _CODE

init:
	di

	; Set up Sprinter native mode
	xor a
	out (SYS_PORT_ON), a

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

        ; switch to stack in common memory
        ld sp, #kstack_top

        ; Zero the data area
        ld hl, #s__DATA
        ld de, #s__DATA + 1
        ld bc, #l__DATA - 1
        ld (hl), #0
        ldir

	; Zero buffers area
	ld hl, #s__BUFFERS
	ld de, #s__BUFFERS + 1
	ld bc, #l__BUFFERS - 1
	ld (hl), #0
	ldir

        ; Hardware setup
        call init_hardware

        ; Call the C main routine
        call _fuzix_main

        ; fuzix_main() shouldn't return, but if it does...
        di
stop:   halt
        jr stop

;
;	Call stubs are filled in here by the linker
;

	.area _STUBS
	.ds 630

	.area _BUFFERS
