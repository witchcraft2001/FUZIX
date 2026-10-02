/*
 *	Sprinter platform discard code - runs once at boot then freed
 */

#include <kernel.h>
#include <kdata.h>
#include <printf.h>
#include <devsys.h>
#include <tty.h>
#include <devtty.h>
#include <tinyide.h>
#define _TINYDISK_PRIVATE
#include <tinydisk.h>

extern void plt_trace(uint8_t code);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
extern void sprinter_bootmark(char c);
extern void pagemap_reset_pool(void);
extern uint8_t sprinter_dbg[];
#endif

void sprinter_restore_devsw(void)
{
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

	dev_tab[2].dev_open = tty_open;
	dev_tab[2].dev_close = tty_close;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	{
		extern int spr_tty_ioctl(uint_fast8_t minor, uarg_t request, char *data);
		extern int spr_tty_read(uint_fast8_t minor, uint_fast8_t rawflag, uint_fast8_t flag);
		extern int spr_tty_write(uint_fast8_t minor, uint_fast8_t rawflag, uint_fast8_t flag);

		dev_tab[2].dev_read = spr_tty_read;
		dev_tab[2].dev_write = spr_tty_write;
		dev_tab[2].dev_ioctl = spr_tty_ioctl;
	}
#else
	dev_tab[2].dev_read = tty_read;
	dev_tab[2].dev_write = tty_write;
	dev_tab[2].dev_ioctl = tty_ioctl;
#endif

	dev_tab[3].dev_open = no_open;
	dev_tab[3].dev_close = no_close;
	dev_tab[3].dev_read = no_rdwr;
	dev_tab[3].dev_write = no_rdwr;
	dev_tab[3].dev_ioctl = no_ioctl;

	dev_tab[4].dev_open = no_open;
	dev_tab[4].dev_close = no_close;
	dev_tab[4].dev_read = sys_read;
	dev_tab[4].dev_write = sys_write;
	dev_tab[4].dev_ioctl = sys_ioctl;
}

void init_hardware_c(void)
{
}

void device_init(void)
{
	/*
	 * Keep the static devices.c table for tty and system devices intact.
	 * Sprinter only needs to wire the block layer hooks here.
	 */
	sprinter_restore_devsw();

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
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	pagemap_reset_pool();
#endif
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
	 * start.c::create_init() now gets init_process via ptab_alloc(),
	 * which has already called pagemap_alloc().  Keep this hook as a
	 * guarded fallback for trace bring-up, but do not allocate or seed a
	 * second page set when p_page is already populated.
	 */
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('p');
	if (init_process) {
		uint8_t *pp = (uint8_t *)&init_process->p_page;
		if (pp[0] == 0) {
			if (pagemap_alloc(init_process) != 0)
				panic("map_init: no pages");
			sprinter_bootmark('q');
		} else {
			sprinter_bootmark('Q');
		}
		sprinter_dbg[8] = pp[0];
		sprinter_dbg[9] = pp[1];
		sprinter_dbg[10] = pp[2];
		sprinter_dbg[11] = pp[3];
		sprinter_dbg[12] = pp[3];
		sprinter_bootmark('t');
	}
#else
	if (init_process && pagemap_alloc(init_process) != 0)
		panic("map_init: no pages");
	/*
	 * Seed init's "common" page (p_page[3]) with a full copy of the
	 * running kernel common page.  init is the first process: it
	 * never goes through switchin() and nothing else populates the
	 * page it was handed.  When init forks, fork_copy reads parent's
	 * page[3] (== uninitialised p_page[3]) and copies garbage into
	 * the child's top bank, making MPGSEL_3 point at junk after the
	 * switchin.  Copy the whole 16 KB so udata, kstack and the top
	 * of common code all survive the propagation through fork.
	 */
	if (init_process) {
		extern void sprinter_seed_common(uint8_t target_page);
		/* p_page is a uint16_t/uint16_t pair holding 4 page bytes */
		uint8_t top = ((uint8_t *)&init_process->p_page)[3];
		sprinter_seed_common(top);
	}
#endif
}
