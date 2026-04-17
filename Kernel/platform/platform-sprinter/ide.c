/*
 *	Sprinter IDE driver
 *
 *	The Sprinter uses 16-bit port addresses for IDE registers,
 *	accessed via the Z80's BC register pair:
 *
 *	Write: BC = 0x0150 (data), 0x0151 (err), ..., 0x4153 (cmd)
 *	Read:  BC = 0x0050 (data), 0x0051 (err), ..., 0x4053 (status)
 *
 *	Data transfer uses INI loops with the data port at C=0x50.
 */

#include <kernel.h>
#include <tinydisk.h>
#include <tinyide.h>
#include <printf.h>
#include "plt_ide.h"

/*
 *	IDE register read - read from a register using 16-bit port address
 *
 *	Register mapping to Sprinter ports:
 *	reg 0 (data):    BC = 0x0050
 *	reg 1 (error):   BC = 0x0051
 *	reg 2 (count):   BC = 0x0052
 *	reg 3 (sector):  BC = 0x0053
 *	reg 4 (cyl low): BC = 0x0054
 *	reg 5 (cyl hi):  BC = 0x0055
 *	reg 6 (devh):    BC = 0x4052
 *	reg 7 (status):  BC = 0x4053
 */
uint_fast8_t ide_read(uint_fast8_t regaddr) __naked
{
	regaddr;
	__asm
		; SDCC banked calls add a hidden 2-byte noopt push before call,
		; so first user argument is at SP+4 on entry.
		ld hl, #4
		add hl, sp
		ld a, (hl)		; regaddr

		; Calculate port: regs 0-5 use B=0x00, regs 6-7 use B=0x40
		cp #6
		jr c, ide_rd_lo
		; regs 6-7: port = 0x4050 + (reg - 6)
		sub #6
		add a, #0x50 + 2	; offset +2 from base for regs 6-7
		ld c, a
		ld b, #0x40
		jr ide_rd_do
ide_rd_lo:
		; regs 0-5: port = 0x0050 + reg
		add a, #0x50
		ld c, a
		ld b, #0x00
ide_rd_do:
		in a, (c)
		ld l, a
		ret
	__endasm;
}

/*
 *	IDE register write
 *	Write ports use different B values than read ports
 *	reg 0 (data):    BC = 0x0150
 *	reg 1 (feature): BC = 0x0151
 *	reg 2 (count):   BC = 0x0152
 *	reg 3 (sector):  BC = 0x0153
 *	reg 4 (cyl low): BC = 0x0154
 *	reg 5 (cyl hi):  BC = 0x0155
 *	reg 6 (devh):    BC = 0x4152
 *	reg 7 (cmd):     BC = 0x4153
 */
void ide_write(uint_fast8_t regaddr, uint_fast8_t val) __naked
{
	regaddr; val;
	__asm
		; SDCC banked call frame: args start at SP+4.
		ld hl, #4
		add hl, sp
		ld e, (hl)		; regaddr
		inc hl
		ld a, (hl)		; val

		; Calculate port
		ld d, a			; save value in D
		ld a, e			; regaddr

		cp #6
		jr c, ide_wr_lo
		; regs 6-7: port = 0x4150 + (reg - 6)  -> 0x4152, 0x4153
		sub #6
		add a, #0x50 + 2
		ld c, a
		ld b, #0x41
		jr ide_wr_do
ide_wr_lo:
		; regs 0-5: port = 0x0150 + reg
		add a, #0x50
		ld c, a
		ld b, #0x01
ide_wr_do:
		ld a, d			; restore value
		out (c), a
		ret
	__endasm;
}

/*
 *	IDE data read - read 512 bytes from the data port
 *
 *	Uses INI loop with C=0x50.
 *	INI reads from port (C) with B as high address byte, then decrements B.
 *	The Sprinter DCP decodes only the low byte for the data port,
 *	so varying B during the loop is fine.
 */
void devide_read_data(uint8_t *dptr) __naked
{
	dptr;
	__asm
		; SDCC banked call frame: args start at SP+4.
		ld hl, #4
		add hl, sp
		ld e, (hl)
		inc hl
		ld d, (hl)
		ex de, hl		; HL = destination address

		ld bc, #0x0050		; fixed IDE data port
		ld de, #0x0200		; 512 bytes
1$:
		in a, (c)
		ld (hl), a
		inc hl
		dec de
		ld a, d
		or e
		jr nz, 1$
		ret
	__endasm;
}

/*
 *	IDE data write - write 512 bytes to the data port
 */
void devide_write_data(uint8_t *dptr) __naked
{
	dptr;
	__asm
		; SDCC banked call frame: args start at SP+4.
		ld hl, #4
		add hl, sp
		ld e, (hl)
		inc hl
		ld d, (hl)
		ex de, hl		; HL = source address

		ld bc, #0x0050		; fixed IDE data port
		ld de, #0x0200		; 512 bytes
1$:
		ld a, (hl)
		out (c), a
		inc hl
		dec de
		ld a, d
		or e
		jr nz, 1$
		ret
	__endasm;
}
