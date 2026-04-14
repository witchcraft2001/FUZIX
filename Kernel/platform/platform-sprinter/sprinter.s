;
;	Sprinter (Peters MC 2008) hardware support
;

        .module sprinter

        ; exported symbols
        .globl init_hardware
	.globl _program_vectors
	.globl map_kernel
	.globl map_kernel_restore
	.globl map_proc
	.globl map_proc_save
	.globl map_buffers
	.globl map_kernel_di
	.globl map_proc_di
	.globl map_proc_always
	.globl map_proc_always_di
	.globl map_save_kernel
	.globl map_restore
	.globl map_for_swap
	.globl plt_interrupt_all
	.globl _copy_common
	.globl mpgsel_cache
	.globl top_bank
	.globl _kernel_pages
	.globl _plt_reboot
	.globl _plt_monitor
	.globl _int_disabled

        ; imported symbols
        .globl _ramsize
        .globl _procmem
	.globl interrupt_handler
	.globl unix_syscall_entry
	.globl nmi_handler
	.globl null_handler
	.globl _udata
	.globl _vtoutput
	.globl _plt_interrupt

	; exported debugging tools
	.globl outchar

        .include "kernel.def"
        .include "../../cpu-z80/kernel-z80.def"


;=========================================================================
; Initialization code
;=========================================================================
        .area _DISCARD

init_hardware:
        ; program vectors for the kernel
        call do_program_vectors

        ; set system RAM size
	; Sprinter has 4MB RAM = 4096KB
	; We use pages 0x04-0x4F for user space = 76 pages * 16K = 1216K
        ld hl, #4096
        ld (_ramsize), hl
        ld hl, #1152		; 72 * 16K user pages
        ld (_procmem), hl

	; Text mode 80x32 is initialized by BIOS at power-on.
	; The BIOS loads the font (character generator) into VRAM
	; and sets up the hardware text mode (VCM=3, port #C3).
	;
	; We select text mode explicitly in case BIOS left us
	; in a different mode:
	ld a, #0x02		; 640x256 / text mode via port #C3
	out (VID_MODE), a

	; Set up CTC for 50Hz timer interrupt
	; CTC channel 2 + 3 chained for timer
	ld a, #0x57		; timer mode, prescaler=256, INT enable
	out (CTC_CH2), a
	ld a, #112		; time constant for ~50Hz
	out (CTC_CH2), a

	; Set up IM2 interrupt vectors
	; Fill 257-byte table at 0xFE00 with 0xFD
	; This puts interrupt handler at address 0xFDFD
	ld hl, #0xFE00
	ld de, #0xFE01
	ld bc, #256
	ld (hl), #0xFD
	ldir

	; Set up jump at 0xFDFD to our interrupt handler
	ld a, #0xC3		; JP instruction
	ld (0xFDFD), a
	ld hl, #interrupt_handler
	ld (0xFDFE), hl

	ld a, #0xFE
	ld i, a
	im 2

        ret

;=========================================================================
; Common memory (always mapped, lives in bank 3)
;=========================================================================
        .area _COMMONMEM

_plt_monitor:
_plt_reboot:
	di
	; Reset to Sprinter BIOS
	xor a
	out (MPGSEL_0), a
	ld a, #0x80		; ROM page 0
	out (MPGSEL_0), a
	rst 0

plt_interrupt_all:
        ret

;=========================================================================
; program_vectors - set exception vectors for a new process
;=========================================================================
_program_vectors:
	di
	pop bc				; bank
	pop de				; temporarily store return address
	pop hl				; function argument -- base page number
	push hl				; put stack back as it was
	push de
	push bc

	call map_proc

	call do_program_vectors

	jp map_kernel_restore


do_program_vectors:
	; write zeroes across all vectors
	ld hl, #0
	ld de, #1
	ld bc, #0x007f
	ld (hl), #0x00
	ldir

	; install interrupt vector at 0x0038 (IM1 fallback)
	ld a, #0xC3			; JP instruction
	ld (0x0038), a
	ld hl, #interrupt_handler
	ld (0x0039), hl

	; set restart vector for FUZIX system calls (RST 30h)
	ld (0x0030), a
	ld hl, #unix_syscall_entry
	ld (0x0031), hl

	; null trap at 0x0000
	ld (0x0000), a
	ld hl, #null_handler
	ld (0x0001), hl

	; NMI vector at 0x0066
	ld (0x0066), a
	ld hl, #nmi_handler
	ld (0x0067), hl

	; IM2 vector table and handler at 0xFDFD
	; (already set up in init_hardware, but set for each process)
	ld hl, #0xFE00
	ld de, #0xFE01
	ld bc, #256
	ld (hl), #0xFD
	ldir

	ld a, #0xC3
	ld (0xFDFD), a
	ld hl, #interrupt_handler
	ld (0xFDFE), hl

	ret

;=========================================================================
; Memory management
; - kernel pages:     0 - 2
; - common page:      3
; - user space pages: 4 - 79 (0x04 - 0x4F)
;=========================================================================

;=========================================================================
; map_proc_always - map process pages
; Inputs: page table address in #U_DATA__U_PAGE
; Outputs: none; all registers preserved
;=========================================================================
map_proc_always:
map_proc_save:
map_proc_always_di:
	push hl
	ld hl, #_udata + U_DATA__U_PAGE
        jr map_proc_2_pophl_ret

;=========================================================================
; map_proc - map process or kernel pages
; Inputs: page table address in HL, map kernel if HL == 0
; Outputs: none; A and HL destroyed
;=========================================================================
map_proc:
map_proc_di:
	ld a, h
	or l				; HL == 0?
	jr nz, map_proc_2		; HL == 0 - map the kernel

;=========================================================================
; map_kernel - map kernel pages
; Inputs: none
; Outputs: none; all registers preserved
;=========================================================================
map_kernel:
map_buffers:
map_kernel_restore:
map_kernel_di:
	push hl
	ld hl, #_kernel_pages
        jr map_proc_2_pophl_ret

;=========================================================================
; map_proc_2 - map process or kernel pages
; Inputs: page table address in HL
; Outputs: none, HL destroyed
;=========================================================================
map_proc_2:
	push de
	push af
	ld de, #mpgsel_cache		; cache for paging registers
	ld a, (hl)			; page for bank #0
	ld (de), a
	out (MPGSEL_0), a		; set bank #0
	inc hl
	inc de
	ld a, (hl)			; page for bank #1
	ld (de), a
	out (MPGSEL_1), a		; set bank #1
	inc hl
	inc de
	ld a, (hl)			; page for bank #2
	ld (de), a
	out (MPGSEL_2), a		; set bank #2
	pop af
	pop de
	ret

;=========================================================================
; map_restore - restore a saved page mapping
;=========================================================================
map_restore:
	push hl
	ld hl, #map_savearea
map_proc_2_pophl_ret:
	call map_proc_2
	pop hl
	ret

;=========================================================================
; map_save_kernel - save the current page mapping and switch to kernel
;=========================================================================
map_save_kernel:
	push hl
	ld hl, (mpgsel_cache)
	ld (map_savearea), hl
	ld hl, (mpgsel_cache+2)
	ld (map_savearea+2), hl
	ld hl, #_kernel_pages
	jr map_proc_2_pophl_ret

;=========================================================================
; map_for_swap - map a page into bank 1 for swap I/O
; Inputs: A = page
; Outputs: none
;=========================================================================
map_for_swap:
	ld (mpgsel_cache + 1), a
	out (MPGSEL_1), a
	ret

;=========================================================================
; _copy_common - copy the common page to a new physical page
;=========================================================================
_copy_common:
	pop bc			; return
	pop hl			; (unused)
	pop de			; target page number
	push de
	push hl
	push bc
	ld a, e
	call map_for_swap	; map target page to bank 1 (0x4000)
	ld hl, #0xF200
	ld de, #0x7200		; 0x4000 + 0x3200 (offset within bank)
	ld bc, #0x0E00		; copy 3.5K of common area
	ldir
	jp map_kernel

;=========================================================================
; outchar - output a character for kernel debug messages
; Input: A = character
;=========================================================================
outchar:
	; Save registers and output via VT
	ld (_tmpout), a
	push bc
	push de
	push hl
	push ix
	ld hl, #1
	push hl
	ld hl, #_tmpout
	push hl
	push af
	call _vtoutput
	pop af
	pop af
	pop af
	pop ix
	pop hl
	pop de
	pop bc
        ret

_tmpout:
	.db 1

;=========================================================================
; Data in common memory
;=========================================================================
;=========================================================================
; Banking stubs for inter-bank calls
;
; Kernel code banks:
;   Bank 1 (CODE1): pages 1,2 in WIN1,WIN2
;   Bank 2 (CODE2): pages 4,5 in WIN1,WIN2
;   Bank 3 (CODE3): pages 6,7 in WIN1,WIN2
;
; MAP_BANKn stores as BC: B=page_for_WIN2, C=page_for_WIN1
;=========================================================================

MAP_BANK1	.equ	0x0201	; pages 1,2
BANK1		.equ	0x01
MAP_BANK2	.equ	0x0504	; pages 4,5
BANK2		.equ	0x04
MAP_BANK3	.equ	0x0706	; pages 6,7
BANK3		.equ	0x06

	.globl __bank_0_1
	.globl __bank_0_2
	.globl __bank_0_3
	.globl __bank_1_2
	.globl __bank_1_3
	.globl __bank_2_1
	.globl __bank_2_3
	.globl __bank_3_1
	.globl __bank_3_2

	.globl __stub_0_1
	.globl __stub_0_2
	.globl __stub_0_3
	.globl __stub_1_2
	.globl __stub_1_3
	.globl __stub_2_1
	.globl __stub_2_3

__bank_0_1:
	ld bc, #MAP_BANK1
bank0:
	pop hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	push hl
	ld a, (_kernel_pages + 1)
	ld (_kernel_pages + 1), bc
	ld (mpgsel_cache + 1), bc
	ld b, a
	ld a, c
	out (MPGSEL_1), a
	inc a
	out (MPGSEL_2), a
	ex de, hl
	ld a, b
	cp #BANK1
	jr z, retbank1
	cp #BANK2
	jr z, retbank2
	call callhl
	ld bc, #MAP_BANK3
banksetbc:
	ld (_kernel_pages + 1), bc
	ld (mpgsel_cache + 1), bc
	ld a, c
	out (MPGSEL_1), a
	ld a, b
	out (MPGSEL_2), a
	ret
retbank1:
	call callhl
	ld bc, #MAP_BANK1
	jr banksetbc
retbank2:
	call callhl
	ld bc, #MAP_BANK2
	jr banksetbc
__bank_0_2:
	ld bc, #MAP_BANK2
	jr bank0
__bank_0_3:
	ld bc, #MAP_BANK3
	jr bank0

__bank_1_2:
	ld bc, #MAP_BANK2
bank_1_x:
	pop hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	push hl
	call banksetbc
	ex de, hl
	call callhl
	ld bc, #MAP_BANK1
	jr banksetbc
__bank_1_3:
	ld bc, #MAP_BANK3
	jr bank_1_x

__bank_2_1:
	ld bc, #MAP_BANK1
bank_2_x:
	pop hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	push hl
	call banksetbc
	ex de, hl
	call callhl
	ld bc, #MAP_BANK2
	jr banksetbc
__bank_2_3:
	ld bc, #MAP_BANK3
	jr bank_2_x

__bank_3_1:
	ld bc, #MAP_BANK1
bank_3_x:
	pop hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	inc hl
	push hl
	call banksetbc
	ex de, hl
	call callhl
	ld bc, #MAP_BANK3
	jr banksetbc
__bank_3_2:
	ld bc, #MAP_BANK2
	jr bank_3_x

__stub_2_1:
__stub_3_1:
__stub_0_1:
	ld bc, #MAP_BANK1
	jr stub_call
__stub_0_2:
__stub_1_2:
__stub_3_2:
	ld bc, #MAP_BANK2
	jr stub_call
__stub_0_3:
__stub_1_3:
__stub_2_3:
	ld bc, #MAP_BANK3
stub_call:
	pop hl
	ex (sp), hl
	ld a, (_kernel_pages+1)
	ld (_kernel_pages+1), bc
	ld (mpgsel_cache + 1), bc
	ld b, a
	ld a, c
	out (MPGSEL_1), a
	inc a
	out (MPGSEL_2), a
	ex de, hl
	ld a, b
	cp #BANK1
	jr z, stub_ret_1
	call callhl
	ld bc, #MAP_BANK2
stub_ret:
	ld (_kernel_pages+1), bc
	ld (mpgsel_cache + 1), bc
	ld a, c
	out (MPGSEL_1), a
	ld a, b
	out (MPGSEL_2), a
	pop bc
	push bc
	push bc
	ret
stub_ret_1:
	call callhl
	ld bc, #MAP_BANK1
	jr stub_ret

callhl:	jp (hl)

	.area _COMMONDATA

mpgsel_cache:
	.db 0, 0, 0, 0		; cached page numbers for all 4 windows

top_bank:
	.db 3			; current top bank (common) page

_kernel_pages:
	.db 0, 1, 2, 3		; kernel page assignments

map_savearea:
	.db 0, 0, 0, 0		; saved mapping

_int_disabled:
	.db 1
