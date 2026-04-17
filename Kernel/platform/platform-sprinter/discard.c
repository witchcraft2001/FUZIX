/*
 *	Sprinter platform discard code - runs once at boot then freed
 */

#include <kernel.h>
#include <kdata.h>
#include <printf.h>
#include <devsys.h>
#include <devtty.h>
#include <tinyide.h>
#define _TINYDISK_PRIVATE
#include <tinydisk.h>

extern void plt_trace(uint8_t code);

void init_hardware_c(void)
{
}

void device_init(void)
{
	/* Runtime re-init of dev_tab for bring-up diagnostics. */
	dev_tab[0].dev_open = no_open;
	dev_tab[0].dev_close = no_close;
	dev_tab[0].dev_read = td_read;
	dev_tab[0].dev_write = td_write;
	dev_tab[0].dev_ioctl = td_ioctl;

	dev_tab[1].dev_open = no_open;
	dev_tab[1].dev_close = no_close;
	dev_tab[1].dev_read = no_rdwr;
	dev_tab[1].dev_write = no_rdwr;
	dev_tab[1].dev_ioctl = no_ioctl;

	dev_tab[2].dev_open = no_open;
	dev_tab[2].dev_close = no_close;
	dev_tab[2].dev_read = no_rdwr;
	dev_tab[2].dev_write = no_rdwr;
	dev_tab[2].dev_ioctl = no_ioctl;

	dev_tab[3].dev_open = no_open;
	dev_tab[3].dev_close = no_close;
	dev_tab[3].dev_read = no_rdwr;
	dev_tab[3].dev_write = no_rdwr;
	dev_tab[3].dev_ioctl = no_ioctl;

	plt_trace(0x42);

#ifdef CONFIG_TD_IDE
	plt_trace(0x40);
	/* ide_probe currently crashes on Sprinter bring-up; force a minimal
	   registration for hd0 so td paths can be exercised safely. */
	td_op[0] = ide_xfer;
	td_iop[0] = ide_ioctl;
	td_unit[0] = 0;
	td_lba[0][1] = 258;
	plt_trace(0x43);
	plt_trace(0x41);
#endif
}

void pagemap_init(void)
{
	uint8_t i;
	/*
	 *	Add user pages to the free pool.
	 *	Kernel uses high pages 0x48-0x4F.
	 *	User pages are 0x08-0x47; 0x50-0x5F are VRAM.
	 */
	for (i = 8; i < 0x48; i++)
		pagemap_add(i);
}

void map_init(void)
{
}
