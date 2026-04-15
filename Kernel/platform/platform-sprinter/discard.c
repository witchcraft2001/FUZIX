/*
 *	Sprinter platform discard code - runs once at boot then freed
 */

#include <kernel.h>
#include <kdata.h>
#include <printf.h>
#include <devtty.h>
#include <tinyide.h>
#include <tinydisk.h>

void init_hardware_c(void)
{
}

void device_init(void)
{
#ifdef CONFIG_TD_IDE
	ide_probe();
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
