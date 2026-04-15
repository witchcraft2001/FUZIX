;
;	Sprinter (Peters MC 2008) FUZIX boot sector
;
;	Loaded by Sprinter BIOS from sector 0 of the boot device.
;	BIOS (DSETUP.ASM OS_LOAD) reads sector to 0x7E00, checks first 12 bytes
;	for "Starting.",0, then copies 512 bytes to 0x8000 (WIN2 = RAM page 10)
;	and jumps to 0x800C (offset +12) with the boot drive number in register A.
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
;	BIOS DRV_READ (#55) call via RST #18 (boot-sector vector):
;	  A  = drive number (#80 = IDE 0 master)
;	  HL = LBA high word (0 for disks < 32 MB)
;	  IX = LBA low word  (sector number)
;	  DE = destination buffer address
;	  B  = sector count
;	  C  = #55 (DRV_READ)
;	  Returns: CF=0 success, CF=1 error
;	  (HDRIVER6.ASM LREADH; same convention as DOSBOOT4.asm RST #18)
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
DRV_LREAD	.equ	0x52	; Long read: A=drive, A'=phys page, HL:IX=LBA, DE=buf, B=count
DRV_READ	.equ	0x55	; Read sectors (uses current WIN3 page)

; ---- Disk / kernel layout ---------------------------------------------------
KERN_LBA_START	.equ	2	; First kernel sector (0=MBR, 1=boot sector)
SECTS_PER_PAGE	.equ	32	; 32 * 512 = 16 384 bytes = one kernel page
KERN_PAGES	.equ	8	; Kernel pages 0-7

; ---- FUZIX entry ------------------------------------------------------------
PROGLOAD	.equ	0x0100	; Kernel init entry point (crt0.s: init:)

; ---- Default drive ----------------------------------------------------------
IDE0_DRIVE	.equ	0x80	; IDE 0 master

; =============================================================================
; Sprinter BIOS boot signature (offset 0x00–0x0B, 12 bytes)
;
; DSETUP.ASM OS_LOAD compares the first 12 bytes of sector 0 with
; the string "Starting." followed by a NUL byte (SIDLEN=12).
; On success it copies the full 512-byte sector to 0x8000 and jumps
; to 0x800C (offset +12).  Register A = drive number on entry.
; =============================================================================
	.ascii	"Starting..."		; 11 bytes: S t a r t i n g . . .
	.db	0x00			; NUL terminator -- total 12 bytes (0x00-0x0B)

; =============================================================================
; Entry point at 0x800C -- BIOS jumps here with drive number in A
;
; BIOS DRV_READ (#55) call via RST #18 (boot-sector BIOS vector):
;   A  = drive number
;   HL = LBA address high 16 bits (0 for disks up to 64K sectors)
;   IX = LBA address low  16 bits (sector number)
;   DE = destination buffer address
;   B  = sector count
;   C  = #55 (DRV_READ)
;   Returns: CF=0 success, CF=1 error
; (Source: HDRIVER6.ASM LREADH/READH; DOSBOOT4.asm uses same convention)
; =============================================================================
; ---- BIOS console print (boot-sector context) --------------------------------
; LP_PRINT_SYM via RST #18: A = char, B = 1, C = #82
LP_PRINT_SYM	.equ	0x82

boot_start:
	di
	ld	sp, #0xBFF0		; stack in WIN2 (page 10, our boot sector page)
	; Page 10 is never overwritten by DRV_LREAD (loads pages 0-7 only).
	; If SP were in WIN3 (page 0) and BIOS remapped WIN3 during LREAD,
	; the stack would be corrupted -> hang/reboot.
	ld	(drive_num), a		; save boot drive passed by BIOS in A
	; NOTE: do NOT touch port 0x7C (SYS_PORT_ON) here -- BIOS already set up
	; native mode and memory windows.  Writing 0x1D would remap WIN0 away from
	; ROM, breaking RST 0x18 calls.

	; Initialise loop state
	xor	a
	ld	(page_num), a
	ld	hl, #KERN_LBA_START
	ld	(cur_lba), hl

	ld	a, #'F'			; "FUZIX" banner
	call	print_char
	ld	a, #':'
	call	print_char

; =============================================================================
; Load loop: read kernel pages 0..KERN_PAGES-1 using BIOS DRV_LREAD (#52)
;
; BIOS C=#52 (CLREAD -> LREADH in HDRIVER6.ASM):
;   A  = drive number (#80)
;   A' = physical page number to load into (set via EX AF,AF' before call)
;   HL = LBA high word (0)
;   IX = LBA low word (sector number)
;   DE = buffer address in WIN3 range (#C000)
;   B  = sector count (32)
;   C  = #52
;
; BIOS internally remaps WIN3 to the physical page in A' and reads via INI.
; Our stack is in WIN2 (page 10) -- not affected by WIN3 remapping.
; =============================================================================
load_next:
	; Print page digit before loading
	ld	a, (page_num)
	add	a, #'0'
	call	print_char

	; A' = physical page number (consumed by LREADH via RDS000/PRESET)
	ld	a, (page_num)
	ex	af, af'

	; Set up LREAD parameters and call BIOS via RST #18
	ld	hl, #0			; HL = LBA high word (0 for disk < 64K sectors)
	ld	ix, (cur_lba)		; IX = LBA low word (sector number)
	ld	de, #0xC000		; DE = buffer at WIN3 base (BIOS maps WIN3 to page A')
	ld	b, #SECTS_PER_PAGE	; B  = 32 sectors (16 KB)
	ld	c, #DRV_LREAD		; C  = #52 (Long Read with explicit page in A')
	ld	a, (drive_num)		; A  = drive
	rst	0x18			; BIOS internal call (boot-sector vector)
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
	ld	a, #'>'			; signal: jumping to kernel
	call	print_char
	xor	a
	out	(MPGSEL_0), a		; WIN0 -> page 0 (kernel init at 0x0100)
	jp	PROGLOAD

; =============================================================================
; Disk read error: print 'E' + page digit and hang
; =============================================================================
boot_error:
	ld	a, #'E'
	call	print_char
	ld	a, (page_num)
	add	a, #'0'
	call	print_char
boot_hang:
	jr	boot_hang

; =============================================================================
; print_char: print character in A via BIOS LP_PRINT_SYM (RST #18)
; Clobbers: BC
; =============================================================================
print_char:
	ld	bc, #0x0100 | LP_PRINT_SYM	; B=1 (count), C=#82 (LP_PRINT_SYM)
	rst	0x18
	ret

; =============================================================================
; Variables -- packed into the boot sector itself (well within 510 bytes)
; =============================================================================
drive_num:
	.db	IDE0_DRIVE		; overwritten with BIOS-supplied drive
page_num:
	.db	0			; current page index (0..KERN_PAGES-1)
cur_lba:
	.dw	KERN_LBA_START		; current disk LBA (low 16 bits)
