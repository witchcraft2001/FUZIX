/*
 *	Sprinter (Peters MC 2008) platform main
 */

#include <kernel.h>
#include <kdata.h>
#include <printf.h>
#include <timer.h>
#include <tty.h>
#include <devtty.h>
#include <tinydisk.h>
#include <rtc.h>

#ifdef CONFIG_SPRINTER_EARLY_TRACE
extern uint8_t spr_rw_stage;
#endif

__sfr __at 0x1D cmos_adr;
__sfr __at 0x1C cmos_dat_r;

uint16_t swap_dev = 0xFFFF;
uint16_t ramtop = PROGTOP;
struct blkbuf *bufpool_end = bufpool + NBUFS;

void plt_idle(void)
{
	extern void spr_idle_wait(void);

#ifdef CONFIG_SPRINTER_EARLY_TRACE
	spr_rw_stage = 0xD6;
#endif
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	spr_rw_stage = 0xD7;
#endif
	spr_idle_wait();
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	spr_rw_stage = 0xD8;
#endif
}

uint_fast8_t plt_param(unsigned char *p)
{
	p;
	return 0;
}

extern void kbd_poll(void);

void plt_interrupt(void)
{
	extern uint8_t spr_idle_irq;

	timer_interrupt();
	/* Kernel console output is not reentrant with keyboard echo. */
	if (!udata.u_insys || spr_idle_irq)
		kbd_poll();
}

/*
 *	Discard area is freed after boot
 */
void plt_discard(void)
{
}

#ifdef CONFIG_SPRINTER_EARLY_TRACE
arg_t spr_boot_open(void)
{
	extern arg_t _open(void);
	extern uint8_t spr_tty_path[];

	udata.u_error = 0;
	udata.u_argn = (uarg_t)spr_tty_path;
	udata.u_argn1 = O_RDWR;
	udata.u_argn2 = 0;
	return _open();
}

/*
 * Rewrite unrelocatable libc `CD 00 00 D0` (call 0; ret nc) to
 * `CD 00 01 D0` (call PROGLOAD/sys_stubs).  Run before doexec via uget
 * into the WIN0 bounce buffer — map_apply must not walk large images.
 */
void sprinter_patch_syscalls(void)
{
	uaddr_t a;
	uaddr_t end = udata.u_break;
	usize_t n;
	usize_t i;
	uint8_t *tmp;
	extern uint8_t sprinter_exec_bounce[];
	extern uint8_t sprinter_dbg[];

	if (end < PROGLOAD + 4)
		return;

	tmp = sprinter_exec_bounce;
	a = PROGLOAD;
	while (a + 3 < end) {
		n = end - a;
		if (n > 2048)
			n = 2048;
		if (uget((uint8_t *)a, tmp, n))
			break;
		for (i = 0; i + 3 < n; i++) {
			if (tmp[i] == 0xCD && tmp[i + 1] == 0x00 &&
			    tmp[i + 2] == 0x00 && tmp[i + 3] == 0xD0) {
				uputc(0x01, (uint8_t *)(a + i + 2));
				sprinter_dbg[14] = 0xDE;
			}
		}
		if (n <= 3)
			break;
		a += n - 3;
	}
}
#endif

#ifdef CONFIG_SPRINTER_EARLY_TRACE
/*
 * Device-table entries for tty.  Force CODE1 around tty_* :
 * bounce / bank_1_3 can leave WIN1/2 on CODE2/3 while CODE1 still
 * thinks it is running — the next fetch then hits FONT (RST38).
 * Safe: these wrappers and tty_* both live in CODE1.
 */
extern void sprinter_force_bank1(void);

int spr_tty_ioctl(uint_fast8_t minor, uarg_t request, char *data)
{
	int r;

	sprinter_force_bank1();
	r = tty_ioctl(minor, request, data);
	sprinter_force_bank1();
	return r;
}

int spr_tty_read(uint_fast8_t minor, uint_fast8_t rawflag, uint_fast8_t flag)
{
	int r;

	sprinter_force_bank1();
	r = tty_read(minor, rawflag, flag);
	sprinter_force_bank1();
	return r;
}

int spr_tty_write(uint_fast8_t minor, uint_fast8_t rawflag, uint_fast8_t flag)
{
	int r;

	sprinter_force_bank1();
	r = tty_write(minor, rawflag, flag);
	sprinter_force_bank1();
	return r;
}
#endif

/*
 *	CMOS RTC access
 */
uint_fast8_t plt_rtc_secs(void)
{
	cmos_adr = 0x00;	/* RTC seconds register */
	return cmos_dat_r;
}

/* Read BCD value from CMOS register */
static uint8_t cmos_read(uint8_t reg)
{
	cmos_adr = reg;
	return cmos_dat_r;
}

int plt_rtc_read(void)
{
	uint16_t len = sizeof(struct cmos_rtc);
	struct cmos_rtc cmos;
	uint8_t *p;

	if (udata.u_count < len)
		len = udata.u_count;

	p = cmos.data.bytes;
	p[6] = cmos_read(0x09);	/* year */
	p[5] = cmos_read(0x08);	/* month */
	p[4] = cmos_read(0x07);	/* day */
	p[3] = cmos_read(0x04);	/* hour */
	p[2] = cmos_read(0x02);	/* minute */
	p[1] = cmos_read(0x00);	/* second */
	p[0] = 0;			/* sub-second */
	cmos.type = CMOS_RTC_BCD;
	if (uput(&cmos, udata.u_base, len) == -1)
		return -1;
	return len;
}

int plt_rtc_write(void)
{
	udata.u_error = EOPNOTSUPP;
	return -1;
}
