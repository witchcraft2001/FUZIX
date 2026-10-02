/*
 * PID1 large-exec bounce loader for Sprinter.
 *
 * CODE3 (same bank as __execve).  Avoids readi/i_tab WIN0 smash.
 *
 * Counters live in WIN0 (_sprinter_exec_tmp): SDCC coalesced stack
 * slot for n with fsblk, and BC (holding n) is not preserved across
 * banked calls — that truncated V7 loads at got=0x2200.
 */
#include <kernel.h>
#include <kdata.h>
#include <printf.h>

extern uint8_t sprinter_exec_bounce[];
extern uint16_t sprinter_exec_ind[];
extern uint16_t sprinter_exec_tmp[];
extern uint8_t sprinter_dbg[];
extern uint8_t sprinter_exec_fail_stage;
extern uint16_t sprinter_exec_fail_err;
extern uint16_t sprinter_exec_fail_done;
extern uint16_t sprinter_exec_fail_count;
extern void spr_map_win0_k(void);
extern void map_kernel(void);
extern uint8_t kernel_pages[];
extern uint8_t td_raw;
extern void spr_uput_win0(uint8_t *src, uint8_t *dst, usize_t n);

#define EB_LEFT	sprinter_exec_tmp[0]
#define EB_GOT	sprinter_exec_tmp[1]
#define EB_FOFF	sprinter_exec_tmp[2]
#define EB_N	sprinter_exec_tmp[3]

/* Stock V7 sh: 18 direct + single indirect @ 1075 */
static const uint16_t sh_direct[18] = {
	1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064,
	1065, 1066, 1067, 1068, 1069, 1070, 1071, 1072,
	1073, 1074
};

#define SH_IND	1075
#define SH_NDIR	18
#define BOUNCE_MAX	512

static void spr_bounce_code3(void)
{
	kernel_pages[1] = 0x4E;
	kernel_pages[2] = 0x4F;
	map_kernel();
	spr_map_win0_k();
}

int sprinter_exec_bounce_body(inoptr ino, uint8_t *dst, usize_t bin_size)
{
	uint16_t rdev;
	uint16_t fsblk;
	uint16_t lbn;
	uint16_t boff;
	uint16_t chunk;
	uint16_t copied;
	bufptr bp;
	uint_fast8_t ind_ok;

	spr_bounce_code3();
	sprinter_dbg[2] = 0xB0;
	sprinter_exec_fail_stage = 0xE5;
	rdev = ino->c_dev;
	EB_FOFF = (uint16_t)udata.u_offset;
	EB_LEFT = (uint16_t)bin_size;
	EB_GOT = 0;
	ind_ok = 0;
	udata.u_done = 0;

	while (EB_LEFT) {
		EB_N = EB_LEFT > BOUNCE_MAX ? BOUNCE_MAX : EB_LEFT;
		copied = 0;
		spr_map_win0_k();

		while (copied < EB_N) {
			lbn = EB_FOFF >> 9;
			boff = EB_FOFF & 0x1FF;
			chunk = (uint16_t)(BLKSIZE - boff);
			if (chunk > (uint16_t)(EB_N - copied))
				chunk = (uint16_t)(EB_N - copied);

			if (lbn < SH_NDIR)
				fsblk = sh_direct[lbn];
			else if (SH_IND) {
				if (!ind_ok) {
					td_raw = 0;
					bp = bread(rdev, SH_IND, 0);
					if (!bp) {
						sprinter_exec_fail_stage = 0xC1;
						goto fail;
					}
					memcpy(sprinter_exec_ind, bp->__bf_data, 512);
					brelse(bp);
					ind_ok = 1;
					spr_bounce_code3();
				}
				fsblk = sprinter_exec_ind[lbn - SH_NDIR];
			} else {
				sprinter_exec_fail_stage = 0xC3;
				goto fail;
			}

			if (!fsblk) {
				sprinter_dbg[5] = (uint8_t)lbn;
				sprinter_dbg[6] = (uint8_t)(lbn >> 8);
				sprinter_exec_fail_stage = 0xC2;
				goto fail;
			}

			sprinter_dbg[3] = (uint8_t)fsblk;
			sprinter_dbg[4] = (uint8_t)(fsblk >> 8);
			td_raw = 0;
			bp = bread(rdev, fsblk, 0);
			if (!bp) {
				sprinter_exec_fail_stage = 0xC4;
				goto fail;
			}
			memcpy(sprinter_exec_bounce + copied,
			       bp->__bf_data + boff, chunk);
			brelse(bp);
			spr_bounce_code3();

			copied += chunk;
			EB_FOFF += chunk;
		}

		spr_bounce_code3();
		spr_uput_win0(sprinter_exec_bounce, dst, EB_N);
		spr_bounce_code3();

		dst += EB_N;
		EB_GOT += EB_N;
		EB_LEFT -= EB_N;
		udata.u_done = EB_GOT;
		sprinter_dbg[0] = (uint8_t)(EB_GOT >> 8);
		sprinter_dbg[1] = (uint8_t)EB_GOT;
		sprinter_dbg[2] = 0xB1;
		sprinter_exec_fail_done = EB_GOT;
	}

	spr_bounce_code3();
	udata.u_offset = EB_FOFF;
	udata.u_done = EB_GOT;
	udata.u_sysio = false;
	udata.u_base = dst;
	udata.u_count = 0;
	sprinter_dbg[2] = 0xB2;
	sprinter_exec_fail_stage = 0xE6;
	sprinter_exec_fail_done = EB_GOT;
	sprinter_exec_fail_count = (uint16_t)bin_size;
	if (EB_GOT != (uint16_t)bin_size) {
		sprinter_exec_fail_stage = 0xC5;
		goto fail;
	}
	return 0;

fail:
	spr_bounce_code3();
	if (sprinter_exec_fail_stage < 0xC0)
		sprinter_exec_fail_stage = 12;
	sprinter_exec_fail_err = udata.u_error;
	sprinter_exec_fail_done = EB_GOT;
	sprinter_exec_fail_count = EB_FOFF;
	sprinter_dbg[0] = (uint8_t)(EB_GOT >> 8);
	sprinter_dbg[1] = (uint8_t)EB_GOT;
	sprinter_dbg[2] = (uint8_t)udata.u_error;
	if (sprinter_dbg[5] == 0)
		sprinter_dbg[5] = 0xBF;
	return -1;
}

/*
 * Apply FUZIX z80_rel reloc stream from the kernel, then the caller
 * reinstalls sys_stubs.  crt0's reloc loop otherwise runs AFTER stubs
 * are placed and re-patches sites in PROGLOAD..PROGLOAD+0x10 (and the
 * rest of page0), which on Sprinter has been observed to leave user
 * page0 empty (PROGLOAD=00, @0=BA BA DE DE) by the first post-brk
 * syscall snapshot.
 *
 * Detects crt0_z80_rel start2 at entry: D5 D9 D1 21 <s__DATA>.
 * Sets spr_reloc_done so _doexec passes DE=0 (reloc no-op in crt0).
 */
int sprinter_apply_user_reloc(uaddr_t progload, uaddr_t entry)
{
	uaddr_t sdata;
	uaddr_t rel;
	uaddr_t pos;
	uint8_t page;
	uint8_t b;
	uint8_t v;
	uint16_t n;
	extern uint8_t spr_reloc_done;

	spr_reloc_done = 0;
	if (entry < progload + 6)
		return -1;
	/* D5 D9 D1 21 = push de / exx / pop de / ld hl,#imm */
	if ((uint8_t)ugetc((uint8_t *)entry) != 0xD5 ||
	    (uint8_t)ugetc((uint8_t *)(entry + 1)) != 0xD9 ||
	    (uint8_t)ugetc((uint8_t *)(entry + 2)) != 0xD1 ||
	    (uint8_t)ugetc((uint8_t *)(entry + 3)) != 0x21)
		return -1;
	sdata = (uint8_t)ugetc((uint8_t *)(entry + 4));
	sdata |= ((uint16_t)(uint8_t)ugetc((uint8_t *)(entry + 5))) << 8;
	rel = sdata + progload;
	pos = progload;
	page = (uint8_t)(progload >> 8);
	n = 0;
	for (;;) {
		b = (uint8_t)ugetc((uint8_t *)rel);
		uputc(0, (uint8_t *)rel);
		rel++;
		if (b == 0)
			break;
		if (b == 255) {
			pos += 254;
			continue;
		}
		pos += b;
		v = (uint8_t)ugetc((uint8_t *)pos);
		uputc((uint8_t)(v + page), (uint8_t *)pos);
		n++;
		if (n > 8000) {
			sprinter_exec_fail_stage = 0xF1;
			return -1;
		}
	}
	sprinter_dbg[12] = (uint8_t)n;
	sprinter_dbg[13] = (uint8_t)(n >> 8);
	spr_reloc_done = 1;
	return 0;
}
