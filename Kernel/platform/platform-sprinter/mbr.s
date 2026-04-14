;
;	Sprinter FUZIX MBR (sector 0 / LBA 0)
;
;	The Sprinter BIOS reads LBA 1 (sector 1) for the OS boot sector.
;	LBA 0 carries only the PC-compatible MBR partition table so that
;	tinydisk_setup() can discover the FUZIX filesystem partition.
;
;	Disk layout:
;	  LBA 0   (512 B)     : this MBR  (partition table + 0x55AA)
;	  LBA 1   (512 B)     : Sprinter boot sector (boot.s, "Starting...")
;	  LBA 2-257 (128 KB)  : FUZIX kernel (8 pages x 16 KB = 256 sectors)
;	  LBA 258+            : FUZIX filesystem (hda1, 65535 x 512 B)
;

	.area MBR(ABS)
	.org 0x0000

; 446 bytes of zeros (no executable boot code -- BIOS never executes LBA 0)
	.ds	446

; =============================================================================
; MBR partition table at byte offset 446 (standard PC MBR layout)
;
; tinydisk_setup() reads sector 0 (LBA 0), checks 0x55AA at bytes 510-511,
; then parses the four 16-byte partition entries at bytes 446-509.
;
; Entry format (16 bytes):
;   offset  0:    status (0x80 = bootable)
;   offset  1-3:  CHS start (ignored for LBA, set 0)
;   offset  4:    partition type
;   offset  5-7:  CHS end   (ignored for LBA, set 0)
;   offset  8-11: LBA first (little-endian uint32)
;   offset 12-15: LBA count (little-endian uint32)
; =============================================================================
	.org	0x01BE
	; Partition 1: FUZIX FS at LBA 258 (after MBR + boot + 256 kernel sectors)
	.db	0x80			; status: bootable
	.db	0x00, 0x00, 0x00	; CHS start (ignored)
	.db	0x7E			; type: FUZIX filesystem
	.db	0x00, 0x00, 0x00	; CHS end   (ignored)
	.db	0x02, 0x01, 0x00, 0x00	; LBA first = 258 = 0x00000102 (little-endian)
	.db	0xFF, 0xFF, 0x00, 0x00	; LBA count = 65535 (little-endian)
	; Partitions 2-4: empty
	.db	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
	.db	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
	.db	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
	.db	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
	.db	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
	.db	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00

; Boot signature at bytes 510-511
	.org	0x01FE
	.db	0x55
	.db	0xAA
