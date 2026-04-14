/*
 *	Sprinter (Peters MC 2008) TTY driver
 *
 *	Console output via ZX-compatible video mode
 *	Input via PS/2 keyboard through Z84C15 SIO Channel A
 */

#include <kernel.h>
#include <kdata.h>
#include <printf.h>
#include <stdbool.h>
#include <tty.h>
#include <vt.h>
#include <devtty.h>

__sfr __at 0x18 sio_data_a;
__sfr __at 0x19 sio_ctrl_a;

static uint8_t tbuf1[TTYSIZ];

struct s_queue ttyinq[NUM_DEV_TTY + 1] = {
	{NULL, NULL, NULL, 0, 0, 0},
	{tbuf1, tbuf1, tbuf1, TTYSIZ, 0, TTYSIZ / 2},
};

tcflag_t termios_mask[NUM_DEV_TTY + 1] = {
	0,
	_CSYS
};

/* Write a character to the console */
void tty_putc(uint_fast8_t minor, uint_fast8_t c)
{
	minor;
	vtoutput(&c, 1);
}

uint_fast8_t tty_writeready(uint_fast8_t minor)
{
	minor;
	return TTY_READY_NOW;
}

/* Called to set baud rate etc */
void tty_setup(uint_fast8_t minor, uint_fast8_t flags)
{
	minor; flags;
}

int tty_carrier(uint_fast8_t minor)
{
	minor;
	return 1;
}

void tty_sleeping(uint_fast8_t minor)
{
	minor;
}

void tty_data_consumed(uint_fast8_t minor)
{
	minor;
}

/*
 *	Keyboard support stubs for VT layer
 *	The VT system expects these to be provided by the keyboard driver.
 *	We use a simple PS/2 approach without the ZX matrix keyboard.
 */
uint8_t keymap[8];
uint8_t keyboard[8][5];
struct vt_repeat keyrepeat = { 50, 5 };

/* Kernel debug output character */
void kputchar(uint_fast8_t c)
{
	if (c == '\n')
		tty_putc(1, '\r');
	tty_putc(1, c);
}

/*
 *	PS/2 keyboard polling via SIO Channel A
 *
 *	The Z84C15 SIO delivers PS/2 scan codes as bytes.
 *	For now we pass raw bytes to the tty layer.
 *	A proper PS/2 scancode decoder will be added later.
 */
void kbd_poll(void)
{
	uint8_t st, ch;

	st = sio_ctrl_a;

	if (!(st & 0x01))	/* bit 0 = RxChar available */
		return;

	ch = sio_data_a;

	if (ch & 0x80)		/* key release - ignore for now */
		return;

	tty_inproc(1, ch);
}
