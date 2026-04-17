/*
 *	Sprinter (Peters MC 2008) TTY driver
 *
 *	Console output: ZX-compatible native 80x32 text mode (sprvideo.s)
 *	Console input:  PS/2 keyboard via Z84C15 SIO Channel A (ports 0x18/0x19)
 *
 *	PS/2 protocol (Set 2 scancodes):
 *	  0xE0 prefix  -- extended key (cursor keys, right-side modifiers, etc.)
 *	  0xF0 prefix  -- key release follows
 *	  0xE1 prefix  -- Pause/Break special sequence (ignored)
 *
 *	Decoding pipeline (mirrors Sprinter BIOS KEY.ASM):
 *	  1. Scancode  -> position code via xlat_t[144]
 *	     (E0+0x11 = RAlt/0x39, E0+0x14 = RCtrl/0x3A, rest use table)
 *	  2. Position  -> ASCII via normtab/shiftab based on shift + caps state
 *	  3. Ctrl modifier: ascii & 0x1F for printable characters
 *	  4. Special positions (arrows, Del, etc.) emit VT100 sequences
 *
 *	Sources: sprinter_bios/SETUP/KEY.ASM (XLAT_T, NORMTAB, SHIFTAB, KINIT)
 */

#include <kernel.h>
#include <kdata.h>
#include <printf.h>
#include <tty.h>
#include <vt.h>
#include <devtty.h>

__sfr __at 0x18 sio_data_a;
__sfr __at 0x19 sio_ctrl_a;

static uint8_t tbuf1[TTYSIZ];

struct s_queue ttyinq[NUM_DEV_TTY + 1] = {
	{NULL,  NULL,  NULL,  0,     0, 0         },
	{tbuf1, tbuf1, tbuf1, TTYSIZ, 0, TTYSIZ / 2},
};

tcflag_t termios_mask[NUM_DEV_TTY + 1] = {
	0,
	_CSYS
};

/* Required by the VT / ZX keyboard matrix layer (not used, PS/2 only) */
uint8_t keymap[8];
uint8_t keyboard[8][5];
struct vt_repeat keyrepeat = { 50, 5 };

/* -------------------------------------------------------------------------
 * PS/2 scancode -> position-code table (144 bytes, indexed by Set 2 scancode)
 * From BIOS KEY.ASM: XLAT_T
 * Position code layout (see comment block at end of this file):
 *   0x00=` 0x01=Esc 0x02-0x0D=1-9,0,-,= 0x0E=BS 0x0F=Tab
 *   0x10-0x1B=Q-P,[] 0x1C=CapsLock 0x1D-0x27=A-L,;' 0x28=Enter
 *   0x29=LShift 0x2A-0x34=Z-M,,./ RShift 0x35=\ 0x36=LCtrl 0x37=LAlt
 *   0x38=Space 0x39=RAlt 0x3A=RCtrl 0x3B-0x46=F1-F12
 *   0x47=PrtScr 0x48=ScrlLk 0x49=NumLk 0x4A-0x4E=Kp/,*,-,+,Ent 0x4F=Del
 *   0x50=Ins 0x51=End 0x52=Down 0x53=PgDn 0x54=Left 0x55=Kp5 0x56=Right
 *   0x57=Home 0x58=Up 0x59=PgUp
 * ------------------------------------------------------------------------- */
static const uint8_t xlat_t[144] = {
/*       0     1     2     3     4     5     6     7     8     9     A     B     C     D     E     F */
/* 00 */ 0x00, 0x43, 0x00, 0x3F, 0x3D, 0x3B, 0x3C, 0x46, 0x00, 0x44, 0x42, 0x40, 0x3E, 0x0F, 0x00, 0x00,
/* 10 */ 0x00, 0x37, 0x29, 0x00, 0x36, 0x10, 0x02, 0x00, 0x00, 0x00, 0x2A, 0x1E, 0x1D, 0x11, 0x03, 0x00,
/* 20 */ 0x00, 0x2C, 0x2B, 0x1F, 0x12, 0x05, 0x04, 0x00, 0x00, 0x38, 0x2D, 0x20, 0x14, 0x13, 0x06, 0x00,
/* 30 */ 0x00, 0x2F, 0x2E, 0x22, 0x21, 0x15, 0x07, 0x00, 0x00, 0x00, 0x30, 0x23, 0x16, 0x08, 0x09, 0x00,
/* 40 */ 0x00, 0x31, 0x24, 0x17, 0x18, 0x0B, 0x0A, 0x00, 0x00, 0x32, 0x33, 0x25, 0x26, 0x19, 0x0C, 0x00,
/* 50 */ 0x00, 0x00, 0x27, 0x00, 0x1A, 0x0D, 0x00, 0x00, 0x1C, 0x34, 0x28, 0x1B, 0x00, 0x35, 0x00, 0x00,
/* 60 */ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0E, 0x00, 0x00, 0x51, 0x00, 0x54, 0x57, 0x00, 0x00, 0x00,
/* 70 */ 0x50, 0x4F, 0x52, 0x55, 0x56, 0x58, 0x01, 0x49, 0x45, 0x4D, 0x53, 0x4C, 0x4B, 0x59, 0x48, 0x00,
/* 80 */ 0x00, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

/* Position code -> ASCII, no modifier (from BIOS NORMTAB) */
static const uint8_t normtab[90] = {
	/* 0x00-0x0E: ` Esc 1-9 0 - = BS */
	'`',  0x1B, '1',  '2',  '3',  '4',  '5',  '6',
	'7',  '8',  '9',  '0',  '-',  '=',  0x08,
	/* 0x0F-0x1B: Tab q w e r t y u i o p [ ] */
	0x09, 'q',  'w',  'e',  'r',  't',  'y',  'u',
	'i',  'o',  'p',  '[',  ']',
	/* 0x1C-0x28: CapsLock a s d f g h j k l ; ' Enter */
	0x00, 'a',  's',  'd',  'f',  'g',  'h',  'j',
	'k',  'l',  ';',  '\'', 0x0D,
	/* 0x29-0x35: LShift z x c v b n m , . / RShift \ */
	0x00, 'z',  'x',  'c',  'v',  'b',  'n',  'm',
	',',  '.',  '/',  0x00, '\\',
	/* 0x36-0x3A: LCtrl LAlt Space RAlt RCtrl */
	0x00, 0x00, ' ',  0x00, 0x00,
	/* 0x3B-0x46: F1-F12 (no ASCII output) */
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	/* 0x47-0x4F: PrtScr ScrlLk NumLk Kp/ Kp* Kp- Kp+ KpEnter Del */
	0x00, 0x00, 0x00, '/',  '*',  '-',  '+',  0x0D, 0x00,
	/* 0x50-0x59: Ins End Down PgDn Left Kp5 Right Home Up PgUp */
	0x00, 0x00, 0x00, 0x00, 0x00, '5',  0x00, 0x00, 0x00, 0x00
};

/* Position code -> ASCII, Shift held (from BIOS SHIFTAB) */
static const uint8_t shiftab[90] = {
	/* 0x00-0x0E */
	'~',  0x1B, '!',  '@',  '#',  '$',  '%',  '^',
	'&',  '*',  '(',  ')',  '_',  '+',  0x08,
	/* 0x0F-0x1B */
	0x09, 'Q',  'W',  'E',  'R',  'T',  'Y',  'U',
	'I',  'O',  'P',  '{',  '}',
	/* 0x1C-0x28 */
	0x00, 'A',  'S',  'D',  'F',  'G',  'H',  'J',
	'K',  'L',  ':',  '"',  0x0D,
	/* 0x29-0x35 */
	0x00, 'Z',  'X',  'C',  'V',  'B',  'N',  'M',
	'<',  '>',  '?',  0x00, '|',
	/* 0x36-0x3A */
	0x00, 0x00, ' ',  0x00, 0x00,
	/* 0x3B-0x46 */
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	/* 0x47-0x4F */
	0x00, 0x00, 0x00, '/',  '*',  '-',  '+',  0x0D, 0x00,
	/* 0x50-0x59 */
	0x00, 0x00, 0x00, 0x00, 0x00, '5',  0x00, 0x00, 0x00, 0x00
};

/* -------------------------------------------------------------------------
 * PS/2 decoder state
 * ------------------------------------------------------------------------- */
#define PS2_E0		0x01		/* E0 extended prefix received */
#define PS2_F0		0x02		/* F0 release prefix received */

/* Modifier bits in mod_state */
#define MOD_LSHIFT	0x01
#define MOD_RSHIFT	0x02
#define MOD_LCTRL	0x04
#define MOD_RCTRL	0x08
#define MOD_LALT	0x10
#define MOD_RALT	0x20

static uint8_t ps2_flags;	/* E0 / F0 prefix state */
static uint8_t mod_state;	/* currently held modifier keys */
static uint8_t caps_lock;	/* CapsLock toggle (0=off, 1=on) */

/* Return MOD_xxx bitmask if position code is a modifier key, else 0 */
static uint8_t pos_modifier(uint8_t pos)
{
	switch (pos) {
	case 0x29: return MOD_LSHIFT;
	case 0x34: return MOD_RSHIFT;
	case 0x36: return MOD_LCTRL;
	case 0x3A: return MOD_RCTRL;
	case 0x37: return MOD_LALT;
	case 0x39: return MOD_RALT;
	default:   return 0;
	}
}

/* Send a VT100 escape sequence: ESC [ suffix */
static void send_vt(uint8_t suffix)
{
	tty_inproc(1, 0x1B);
	tty_inproc(1, '[');
	tty_inproc(1, suffix);
}

/* Send a VT100 function sequence: ESC [ digit ~ */
static void send_vtfn(uint8_t digit)
{
	tty_inproc(1, 0x1B);
	tty_inproc(1, '[');
	tty_inproc(1, digit);
	tty_inproc(1, '~');
}

/* -------------------------------------------------------------------------
 * kbd_poll -- called from plt_interrupt (50 Hz timer tick)
 * Drains the SIO RX FIFO and converts PS/2 scancodes to ASCII.
 * ------------------------------------------------------------------------- */
void kbd_poll(void)
{
	uint8_t sc, pos, ascii, mod;
	uint8_t shifted;

	while (sio_ctrl_a & 0x01) {	/* bit 0 = RxChar available */
		sc = sio_data_a;

		/* Handle protocol prefix bytes */
		if (sc == 0xE0) { ps2_flags |= PS2_E0; continue; }
		if (sc == 0xF0) { ps2_flags |= PS2_F0; continue; }
		if (sc == 0xE1) { ps2_flags = 0; continue; } /* Pause/Break: ignore */

		/* Translate scancode to position code */
		if ((ps2_flags & PS2_E0) && sc == 0x11) {
			pos = 0x39;		/* E0 11 = Right Alt */
		} else if ((ps2_flags & PS2_E0) && sc == 0x14) {
			pos = 0x3A;		/* E0 14 = Right Ctrl */
		} else if ((ps2_flags & PS2_E0) && sc == 0x5A) {
			pos = 0x4E;		/* E0 5A = Numpad Enter */
		} else if ((ps2_flags & PS2_E0) && sc == 0x4A) {
			pos = 0x4A;		/* E0 4A = Numpad / */
		} else if (sc < 144) {
			pos = xlat_t[sc];
		} else {
			pos = 0;
		}
		ps2_flags &= ~PS2_E0;

		if (ps2_flags & PS2_F0) {
			/* Key release: clear modifier if applicable */
			ps2_flags &= ~PS2_F0;
			mod = pos_modifier(pos);
			if (mod)
				mod_state &= ~mod;
			continue;
		}

		/* Key press */
		if (pos == 0)
			continue;

		mod = pos_modifier(pos);
		if (mod) {
			mod_state |= mod;
			continue;
		}

		/* Toggle keys */
		if (pos == 0x1C) { caps_lock ^= 1; continue; } /* CapsLock */
		if (pos == 0x49) continue; /* NumLock: ignore */
		if (pos == 0x48) continue; /* ScrollLock: ignore */

		if (pos > 0x59)
			continue;

		/* Look up ASCII from table */
		shifted = (mod_state & (MOD_LSHIFT | MOD_RSHIFT)) ? 1 : 0;

		/*
		 * CapsLock inverts shift state for letter positions only.
		 * Letters are at positions 0x10-0x19 (Q-P), 0x1D-0x25 (A-L),
		 * 0x2A-0x30 (Z-M).
		 */
		if (caps_lock) {
			if ((pos >= 0x10 && pos <= 0x19) ||
			    (pos >= 0x1D && pos <= 0x25) ||
			    (pos >= 0x2A && pos <= 0x30))
				shifted ^= 1;
		}

		ascii = shifted ? shiftab[pos] : normtab[pos];

		if (ascii == 0) {
			/* Special keys: emit VT100 sequences */
			switch (pos) {
			case 0x58: send_vt('A');  break; /* Up    ESC[A */
			case 0x52: send_vt('B');  break; /* Down  ESC[B */
			case 0x56: send_vt('C');  break; /* Right ESC[C */
			case 0x54: send_vt('D');  break; /* Left  ESC[D */
			case 0x57: send_vt('H');  break; /* Home  ESC[H */
			case 0x51: send_vt('F');  break; /* End   ESC[F */
			case 0x50: send_vtfn('2'); break; /* Ins   ESC[2~ */
			case 0x4F: tty_inproc(1, 0x7F); break; /* Del  */
			case 0x59: send_vtfn('5'); break; /* PgUp  ESC[5~ */
			case 0x53: send_vtfn('6'); break; /* PgDn  ESC[6~ */
			/* F1-F12, PrtScr, etc.: ignore */
			}
			continue;
		}

		/* Apply Ctrl: map printable chars >= '@' to control codes */
		if ((mod_state & (MOD_LCTRL | MOD_RCTRL)) && ascii >= '@')
			ascii &= 0x1F;

		tty_inproc(1, ascii);
	}
}

/* -------------------------------------------------------------------------
 * TTY driver interface
 * ------------------------------------------------------------------------- */

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

/*
 * tty_setup: called at init and on stty changes.
 * Re-initialise SIO Channel A for PS/2 polling (no interrupts).
 * Sequence from BIOS KEY.ASM: KINIT
 */
void tty_setup(uint_fast8_t minor, uint_fast8_t flags)
{
	minor; flags;
	/* Select WR1, disable Rx interrupt (we poll) */
	sio_ctrl_a = 0x01;
	sio_ctrl_a = 0x00;
	/* Select WR3: Rx enable, 8-bit word length */
	sio_ctrl_a = 0x03;
	sio_ctrl_a = 0xC1;
	/* Select WR4: async, x1 clock (PS/2 provides its own clock) */
	sio_ctrl_a = 0x04;
	sio_ctrl_a = 0x07;
	/* Select WR5: Tx enable, DTR, 8-bit word */
	sio_ctrl_a = 0x05;
	sio_ctrl_a = 0x62;
}

int tty_carrier(uint_fast8_t minor)
{
	minor;
	return 1;
}

int sprinter_tty_open(uint_fast8_t minor, uint16_t flag)
{
	register struct tty *t;

	flag;

	if (minor > NUM_DEV_TTY) {
		udata.u_error = ENODEV;
		return -1;
	}

	t = &ttydata[minor];

	if (t->users) {
		t->flag &= ~TTYF_DEAD;
		t->users++;
		return 0;
	}

	t->flag &= ~TTYF_DEAD;
	tty_setup(minor, 0);
	t->users++;
	return 0;
}

void tty_sleeping(uint_fast8_t minor)
{
	minor;
}

void tty_data_consumed(uint_fast8_t minor)
{
	minor;
}

void kputchar(uint_fast8_t c)
{
	if (c == '\n')
		tty_putc(1, '\r');
	tty_putc(1, c);
}

/*
 * Position code layout reference (from BIOS KEY.ASM comments):
 *
 *  Pos  Key          Pos  Key          Pos  Key
 *  0x00 ` ~          0x20 f F          0x40 F10
 *  0x01 Esc          0x21 g G          0x41 F11
 *  0x02 1 !          0x22 h H          0x42 F12
 *  0x03 2 @          0x23 j J          0x43 F1
 *  0x04 3 #          0x24 k K          0x44 F2
 *  0x05 4 $          0x25 l L          0x45 F9
 *  0x06 5 %          0x26 ; :          0x46 F12(dup)
 *  0x07 6 ^          0x27 ' "          0x47 PrtScr
 *  0x08 7 &          0x28 Enter        0x48 ScrlLk
 *  0x09 8 *          0x29 LShift       0x49 NumLk
 *  0x0A 9 (          0x2A z Z          0x4A Kp/
 *  0x0B 0 )          0x2B x X          0x4B Kp*
 *  0x0C - _          0x2C c C          0x4C Kp-
 *  0x0D = +          0x2D v V          0x4D Kp+
 *  0x0E Backspace    0x2E b B          0x4E KpEnter
 *  0x0F Tab          0x2F n N          0x4F Delete
 *  0x10 q Q          0x30 m M          0x50 Insert
 *  0x11 w W          0x31 , <          0x51 End
 *  0x12 e E          0x32 . >          0x52 Down
 *  0x13 r R          0x33 / ?          0x53 PgDn
 *  0x14 t T          0x34 RShift       0x54 Left
 *  0x15 y Y          0x35 \ |          0x55 Kp5
 *  0x16 u U          0x36 LCtrl        0x56 Right
 *  0x17 i I          0x37 LAlt         0x57 Home
 *  0x18 o O          0x38 Space        0x58 Up
 *  0x19 p P          0x39 RAlt         0x59 PgUp
 *  0x1A [ {          0x3A RCtrl
 *  0x1B ] }          0x3B F1
 *  0x1C CapsLock     0x3C F2
 *  0x1D a A          0x3D F3
 *  0x1E s S          0x3E F4
 *  0x1F d D          0x3F F5
 */
