#include <kernel.h>
#include <kdata.h>
#include <exec.h>

extern int spr_prep_old(struct exec *hdr);

int pagemap_prepare(struct exec *hdr)
{
	if (spr_prep_old(hdr) < 0)
		return -1;
	/* Explicit chmem sizes must also leave IM2 and kernel common intact. */
	if ((uint16_t)hdr->a_base + hdr->a_size > (PROGTOP >> 8)) {
		udata.u_error = ENOMEM;
		return -1;
	}
	return 0;
}
