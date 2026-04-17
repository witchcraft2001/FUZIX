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
	/*
	 * Allocate the first batch of user pages for PID1 (init) BEFORE
	 * start.c::create_init() runs add_argument("/init") which calls
	 * uputc into the init process's user space at PROGLOAD+256.
	 *
	 * Without this, init_process->p_page is zero, makeproc copies that
	 * zero into udata.u_page, and map_proc_2 sanitises the zero by
	 * substituting kernel page 0x48 for WIN0 -- so the "/init" string
	 * ends up written inside the kernel code bank instead of user RAM.
	 * Later _execve reads the corrupted bytes via ugetc, fails to
	 * resolve the path and panics with PANIC_NOINIT.
	 *
	 * pagemap_alloc uses init_process->p_top (set to PROGLOAD+512 by
	 * create_init) to compute how many 16 KB pages the process needs
	 * and fills p_page from the free pool (populated by pagemap_init
	 * above).  After this map_proc_2 will map real user pages into
	 * WIN0..WIN2 and early writes land in actual user RAM.
	 */
	if (init_process && pagemap_alloc(init_process) != 0)
		panic("map_init: no pages");
}
