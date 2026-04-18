/*
 *	Sprinter (Peters MC 2008) platform main
 */

#include <kernel.h>
#include <kdata.h>
#include <printf.h>
#include <timer.h>
#include <devtty.h>
#include <tinydisk.h>
#include <rtc.h>

__sfr __at 0x1D cmos_adr;
__sfr __at 0x1C cmos_dat_r;

uint16_t swap_dev = 0xFFFF;
uint16_t ramtop = PROGTOP;

void plt_idle(void)
{
	/*
	 * Bring-up idle: poll the keyboard and advance timer ticks in
	 * software rather than blocking on HALT.  The bring-up IRQ
	 * dispatcher in sprinter.s absorbs every interrupt (it RETIs
	 * without EI so IFF1 stays cleared) so a HALT here would never
	 * wake back up.  Mirror the zx128 pattern of polling the
	 * tty/timer directly from the idle loop until the kernel IRQ
	 * path is fully plumbed.
	 */
	kbd_poll();
	timer_interrupt();
}

uint_fast8_t plt_param(unsigned char *p)
{
	p;
	return 0;
}

extern void kbd_poll(void);

void plt_interrupt(void)
{
	/*
	 * 50 Hz timer tick: advance FUZIX scheduler time and poll the
	 * PS/2 keyboard.  The bring-up dispatcher in sprinter.s reaches
	 * here only when u_insys == 0 (user code was running); that is
	 * sufficient to unblock a process that sleep()ed from user
	 * space.  For kernel-side waits (plt_idle), the dispatcher
	 * currently absorbs the IRQ — revisit once the ULA FRAME
	 * acknowledgement is understood.
	 */
	timer_interrupt();
	kbd_poll();
}

/*
 *	Discard area is freed after boot
 */
void plt_discard(void)
{
}

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
