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
;	  4. Load 8 FUZIX kernel pages via WIN1 to high RAM pages:
;	       Image page N -> physical page (KERN_PAGE_BASE + N)
;	       Page N -> disk LBA = 2 + N*32 (32 sectors = 16 KB per page)
;	       Buffer = 0x4000 (WIN1 base), MPGSEL_1 set each iteration
;	       WIN2 remains page 10 throughout -- no aliasing with kernel pages
;	  5. Map kernel image page 0 (physical KERN_PAGE_BASE) to WIN0
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
;	  Sectors 2-33:   kernel image page 0 (16 KB, from fuzix.sprinter offset 0)
;	  Sectors 34-65:  kernel image page 1 (16 KB)
;	  Sectors 66-97:  kernel image page 2 (16 KB)
;	  Sectors 98-129: kernel image page 3 (16 KB, common)
;	  Sectors 130-161: kernel image page 4 (16 KB)
;	  Sectors 162-193: kernel image page 5 (16 KB)
;	  Sectors 194-225: kernel image page 6 (16 KB)
;	  Sectors 226-257: kernel image page 7 (16 KB)
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
DRV_READ	.equ	0x55	; Read sectors (uses current WIN3 page)

; ---- Disk / kernel layout ---------------------------------------------------
KERN_LBA_START	.equ	2	; First kernel sector (0=MBR, 1=boot sector)
SECTS_PER_PAGE	.equ	32	; 32 * 512 = 16 384 bytes = one kernel page
KERN_PAGES	.equ	8	; Number of kernel image pages
KERN_PAGE_BASE	.equ	0x48	; Physical RAM page for kernel image page 0

; ---- FUZIX entry ------------------------------------------------------------
PROGLOAD	.equ	0x0100	; Kernel init entry point (crt0.s: init:)

; ---- Default drive ----------------------------------------------------------
IDE0_DRIVE	.equ	0x80	; IDE 0 master

; =============================================================================
; Sprinter BIOS boot signature (offset 0x00–0x0B, 12 bytes)
;
; DSETUP.ASM OS_LOAD compares the first 12 bytes of sector 1 (LBA 1) with
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
	; Page 10 is never touched by kernel reads (loaded to KERN_PAGE_BASE..+7).
	ld	(drive_num), a		; save boot drive passed by BIOS in A
	xor	a
	out	(SYS_PORT_ON), a	; keep BIOS system mode without changing CNF bits

	ld	a, (drive_num)
	ld	c, #DRV_RESET
	rst	0x18
	jp	c, boot_error

	; Initialise loop state
	xor	a
	ld	(page_num), a
	ld	(read_mode), a
	ld	hl, #KERN_LBA_START
	ld	(cur_lba), hl

	ld	a, #'F'			; "FUZIX" banner
	call	print_char
	ld	a, #':'
	call	print_char

; =============================================================================
; Load loop: read kernel pages 0..KERN_PAGES-1 using BIOS DRV_READ (#55)
;
; For each page:
;   1) map page N into WIN1 (MPGSEL_1)
;   2) read 32 sectors to 0x4000 (WIN1 base)
;
; This keeps all reads away from the boot sector in WIN2.
; =============================================================================
load_next:
	; Print page digit before loading
	ld	a, (page_num)
	add	a, #'0'
	call	print_char

	; Map target kernel page into WIN1.
	ld	a, (page_num)
	add	a, #KERN_PAGE_BASE
	out	(MPGSEL_1), a

	; Set up READ parameters and call BIOS via RST #18.
	; read_mode = 0: HL=high, IX=low (BIOS sources: DSETUP + HDRIVER6)
	; read_mode = 1: HL=low,  IX=high (fallback for alternate firmware docs)
	ld	a, (read_mode)
	or	a
	jr	nz, read_params_alt
	ld	hl, #0			; HL = LBA high word
	ld	ix, (cur_lba)		; IX = LBA low word
	jr	read_params_ready
read_params_alt:
	ld	hl, (cur_lba)		; HL = LBA low word (fallback mode)
	ld	ix, #0			; IX = LBA high word
read_params_ready:
	ld	de, #0x4000		; DE = buffer in WIN1 (currently mapped to page N)
	ld	b, #SECTS_PER_PAGE	; B  = 32 sectors (16 KB)
	ld	c, #DRV_READ		; C  = #55
	ld	a, (drive_num)		; A  = drive
	rst	0x18			; BIOS internal call (boot-sector vector)
	jp	c, boot_error		; CF=1 -> disk read failed

	; One-time sanity probe on page 0:
	; if data at 0x4000 begins with "Starting...",0 then we loaded the
	; boot sector instead of kernel page 0. Switch register mapping mode
	; and retry page 0 without advancing LBA/page counters.
	ld	a, (page_num)
	or	a
	jr	nz, read_ok
	ld	a, (read_mode)
	or	a
	jr	nz, read_ok
	ld	hl, #0x4000
	ld	de, #0x8000
	ld	b, #12
read_probe:
	ld	a, (de)
	cp	(hl)
	jr	nz, read_ok
	inc	hl
	inc	de
	djnz	read_probe
	ld	a, #1
	ld	(read_mode), a
	ld	a, #'M'
	call	print_char
	jr	load_next

read_ok:

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
; All pages loaded.  Map kernel image page 0 to WIN0 and enter the kernel.
; crt0.s (init:) remaps WIN1..WIN3 to KERN_PAGE_BASE+1..+3.
; =============================================================================
	ld	a, #'>'			; signal: jumping to kernel
	call	print_char
	ld	a, #KERN_PAGE_BASE
	out	(MPGSEL_0), a		; WIN0 -> kernel image page 0 (init at 0x0100)
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
read_mode:
	.db	0			; 0=HL:IX (normal), 1=HL low fallback

	.org	0x81FE
	.db	0x55
	.db	0xAA
