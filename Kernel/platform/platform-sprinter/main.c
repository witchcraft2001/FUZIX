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
	__asm
		halt
	__endasm;
}

uint_fast8_t plt_param(unsigned char *p)
{
	p;
	return 0;
}

void plt_interrupt(void)
{
	kbd_poll();
	timer_interrupt();
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
