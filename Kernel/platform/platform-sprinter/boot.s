;
;	Sprinter (Peters MC 2008) FUZIX boot sector
;
;	Loaded by Sprinter BIOS from sector 0 of the boot device.
;	BIOS loads this 512-byte sector to 0x8000 (WIN2 = RAM page 10)
;	and jumps to 0x8000 with the boot drive number in register A.
;
;	Initial memory windows (after reset, per Sprinter boot sequence docs):
;	  WIN0 (0x0000-0x3FFF): ROM page 0 (BIOS) -- RST #08 dispatcher here
;	  WIN1 (0x4000-0x7FFF): RAM page 2
;	  WIN2 (0x8000-0xBFFF): RAM page 10 (0x0A) -- THIS boot sector
;	  WIN3 (0xC000-0xFFFF): RAM page 0
;
;	Strategy:
;	  1. Save drive number from A register (passed by BIOS)
;	  2. Enable Sprinter native mode (SYS_PORT_ON)
;	  3. Reset boot drive via BIOS DRV_RESET (#51)
;	  4. Load 8 FUZIX kernel pages (pages 0-7) via WIN1:
;	       Page N -> disk LBA = 1 + N*32 (32 sectors = 16 KB per page)
;	       Buffer = 0x4000 (WIN1 base), MPGSEL_1 set to page N each time
;	       WIN2 remains page 10 throughout -- no aliasing with pages 0-7
;	  5. Map kernel page 0 to WIN0 (so 0x0100 has FUZIX crt0 init code)
;	  6. Jump to 0x0100 (PROGLOAD)
;	     crt0.s then sets WIN1=p1, WIN2=p2, WIN3=p3 and calls fuzix_main
;
;	BIOS DRV_READ (#55) call via RST #08:
;	  A  = drive number (#80 = IDE 0 master)
;	  HL = LBA low word
;	  DE = LBA high word (0 for disks < 32 MB)
;	  IX = destination buffer (must lie within one 16 KB window)
;	  B  = sector count
;	  C  = #55 (DRV_READ)
;	  Returns: CF=0 success, CF=1 error (A = error code)
;
;	Disk layout (raw, sector-addressed):
;	  Sector 0:       this boot sector (512 bytes)
;	  Sectors 1-32:   kernel page 0 (16 KB, from fuzix.sprinter offset 0)
;	  Sectors 33-64:  kernel page 1 (16 KB)
;	  Sectors 65-96:  kernel page 2 (16 KB)
;	  Sectors 97-128: kernel page 3 (16 KB, common)
;	  Sectors 129-160: kernel page 4 (16 KB)
;	  Sectors 161-192: kernel page 5 (16 KB)
;	  Sectors 193-224: kernel page 6 (16 KB)
;	  Sectors 225-256: kernel page 7 (16 KB)
;	  Sectors 257+:   FUZIX filesystem (mkfs.fuzix)
;

	.area BOOT(ABS)
	.org 0x8000

; ---- Port constants (must match kernel.def) ---------------------------------
MPGSEL_0	.equ	0x82	; WIN0 page select (0x0000-0x3FFF)
MPGSEL_1	.equ	0xA2	; WIN1 page select (0x4000-0x7FFF)
SYS_PORT_ON	.equ	0x7C	; Enable Sprinter native mode

; ---- BIOS API ---------------------------------------------------------------
DRV_RESET	.equ	0x51	; Reset drive
DRV_READ	.equ	0x55	; Read sectors from drive

; ---- Disk / kernel layout ---------------------------------------------------
KERN_LBA_START	.equ	1	; First kernel sector (0 = boot sector)
SECTS_PER_PAGE	.equ	32	; 32 * 512 = 16 384 bytes = one kernel page
KERN_PAGES	.equ	8	; Kernel pages 0-7

; ---- FUZIX entry ------------------------------------------------------------
PROGLOAD	.equ	0x0100	; Kernel init entry point (crt0.s: init:)

; ---- Default drive ----------------------------------------------------------
IDE0_DRIVE	.equ	0x80	; IDE 0 master

; =============================================================================
; Entry point -- BIOS jumps here with drive number in A
; =============================================================================
boot_start:
	di
	ld	(drive_num), a		; save boot drive

	; Activate Sprinter native mode so banking ports respond
	ld	a, #0x1D
	out	(SYS_PORT_ON), a

	; Reset boot drive (ignore result -- proceed even on soft errors)
	ld	a, (drive_num)
	ld	c, #DRV_RESET
	rst	0x08			; BIOS dispatcher

	; Initialise loop state
	xor	a
	ld	(page_num), a
	ld	hl, #KERN_LBA_START
	ld	(cur_lba), hl

; =============================================================================
; Load loop: read kernel pages 0..KERN_PAGES-1 into RAM via WIN1
; =============================================================================
load_next:
	; Point WIN1 at the RAM page we are about to fill
	ld	a, (page_num)
	out	(MPGSEL_1), a

	; Set up DRV_READ parameters and call BIOS
	ld	hl, (cur_lba)		; HL = LBA low word
	ld	de, #0			; DE = LBA high word (disk < 32 MB)
	ld	ix, #0x4000		; IX = buffer at WIN1 base
	ld	b, #SECTS_PER_PAGE	; B  = 32 sectors (16 KB)
	ld	c, #DRV_READ		; C  = function code
	ld	a, (drive_num)		; A  = drive
	rst	0x08			; BIOS: read sectors
	jr	c, boot_error		; CF=1 -> disk read failed

	; Advance LBA for the next page
	ld	hl, (cur_lba)
	ld	de, #SECTS_PER_PAGE
	add	hl, de
	ld	(cur_lba), hl

	; Increment page counter and loop
	ld	a, (page_num)
	inc	a
	ld	(page_num), a
	cp	#KERN_PAGES
	jr	nz, load_next

; =============================================================================
; All pages loaded.  Map kernel page 0 to WIN0 and enter the kernel.
; crt0.s (init:) will remap WIN1=1, WIN2=2, WIN3=3 before calling fuzix_main.
; =============================================================================
	xor	a
	out	(MPGSEL_0), a		; WIN0 -> page 0 (kernel init at 0x0100)
	jp	PROGLOAD

; =============================================================================
; Disk read error: hang (no reliable console at this stage)
; =============================================================================
boot_error:
	jr	boot_error

; =============================================================================
; Variables -- packed into the boot sector itself (well within 510 bytes)
; =============================================================================
drive_num:
	.db	IDE0_DRIVE		; overwritten with BIOS-supplied drive
page_num:
	.db	0			; current page index (0..KERN_PAGES-1)
cur_lba:
	.dw	KERN_LBA_START		; current disk LBA (low 16 bits)

; =============================================================================
; PC-compatible boot signature at bytes 510-511
; =============================================================================
	.org	0x81FE
	.db	0x55
	.db	0xAA
