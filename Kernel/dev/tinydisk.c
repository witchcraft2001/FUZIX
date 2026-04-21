/*
 *	A minimal SD implementation for tiny machines
 *	Assumes
 *	- Firmware initialized the device
 *	- Only supports primary partitions
 */

#include <kernel.h>
#include <kdata.h>
#include <printf.h>
#include <timer.h>
#define _TINYDISK_PRIVATE
#include <tinydisk.h>

#ifdef CONFIG_TD_IDE
extern int ide_xfer(uint_fast8_t unit, bool is_read, uint32_t lba, uint8_t *dptr);
#endif

#ifdef CONFIG_SPRINTER_EARLY_TRACE
extern void plt_trace(uint8_t code);
#define TD_TRACE(x) plt_trace(x)
extern void sprinter_bootmark(char c);
#else
#define TD_TRACE(x) do { } while (0)
#endif

/* Used by the asm helpers */
uint8_t td_page;
uint8_t td_raw;
uint32_t td_lba[CONFIG_TD_NUM][CONFIG_TD_MAX_PART + 1];
uint8_t td_unit[CONFIG_TD_NUM];
td_xfer td_op[CONFIG_TD_NUM];
td_ioc td_iop[CONFIG_TD_NUM];

static int td_transfer(uint8_t minor, bool is_read, uint8_t rawflag)
{
	TD_TRACE(0x77);
	TD_TRACE(0x78);
	TD_TRACE(rawflag);
	uint8_t dev = minor >> 4;
	register uint16_t ct = 0;
	register uint8_t *dptr;
	uint16_t nblock;
	uint32_t lba;

	minor &= 0x0F;
	TD_TRACE(0x7B);
	if (dev >= CONFIG_TD_NUM || td_op[dev] == NULL) {
		TD_TRACE(0x79);
		goto fail;
	}

	td_page = 0;
	td_raw = rawflag;
	if (rawflag == 1) {
		if (d_blkoff(BLKSHIFT))
			return -1;
		td_page = udata.u_page;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
		/* Dump u_page[0..3] so we can tell whether map_proc_always
		 * is going to set up a real user mapping or fall back to a
		 * kernel page because u_page is unpopulated. */
		TD_TRACE(0x40);
		TD_TRACE(((uint8_t *)&udata.u_page)[0]);
		TD_TRACE(((uint8_t *)&udata.u_page)[1]);
		TD_TRACE(((uint8_t *)&udata.u_page)[2]);
		TD_TRACE(((uint8_t *)&udata.u_page)[3]);
#endif
	}
#if defined(SWAPDEV) || defined(PAGEDEV)
	else if (rawflag == 2)
		td_page = swappage;
#else
	else if (rawflag == 2)
		goto error;
#endif

	lba = udata.u_block;
	if (minor) {
		if (minor <= CONFIG_TD_MAX_PART && td_lba[dev][minor])
			lba += td_lba[dev][minor];
		else {
			TD_TRACE(0x79);
			goto fail;
		}
	}

	dptr = udata.u_dptr;
	nblock = udata.u_nblock;
	TD_TRACE(0x7E);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('S');
#endif
	while (ct < nblock) {
		TD_TRACE(0x72);
		if (dev == 0) {
			TD_TRACE(0x7A);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
			sprinter_bootmark('T');
#endif
			if (ide_xfer(td_unit[dev], is_read, lba, dptr) == 0)
				goto error;
		} else if (td_op[dev] (td_unit[dev], is_read, lba, dptr) == 0)
			goto error;
		TD_TRACE(0x73);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
		sprinter_bootmark('U');
#endif
		ct++;
		dptr += 512;
		lba++;
	}
	return ct << 9;
error:
	TD_TRACE(0x74);
fail:
	TD_TRACE(0x7F);
	udata.u_error = EIO;
	return -1;
}

int td_open(uint_fast8_t minor, uint16_t flag)
{
	uint8_t dev = minor >> 4;
	minor &= 0x0F;
	if (dev >= CONFIG_TD_NUM || minor > CONFIG_TD_MAX_PART || td_op[dev] == NULL) {
		udata.u_error = ENODEV;
		return -1;
	}
	return 0;
}

int td_read(uint_fast8_t minor, uint_fast8_t rawflag, uint_fast8_t flag)
{
	int r;
	TD_TRACE(0x70);
	TD_TRACE((uint8_t)minor);
	TD_TRACE(0x71);
	TD_TRACE((uint8_t)rawflag);
	TD_TRACE(0x75);
	r = td_transfer(minor, true, rawflag);
	TD_TRACE(0x76);
	TD_TRACE((uint8_t)r);
	return r;
}

int td_write(uint_fast8_t minor, uint_fast8_t rawflag, uint_fast8_t flag)
{
	return td_transfer(minor, false, rawflag);

}

int td_ioctl_none(uint_fast8_t dev, uarg_t request, char *data)
{
	udata.u_error = ENOTTY;
	return -1;
}

int td_ioctl(uint_fast8_t minor, uarg_t request, char *data)
{
	uint8_t dev = minor >> 4;
	return td_iop[dev](td_unit[dev], request, data);
}
