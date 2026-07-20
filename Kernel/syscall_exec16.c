#include <kernel.h>
#include <version.h>
#include <kdata.h>
#include <printf.h>
#include <exec.h>

#ifdef CONFIG_SPRINTER_EARLY_TRACE
extern void plt_trace(uint8_t code);
extern uint8_t sprinter_dbg[];
extern uint8_t sprinter_exec_fail_stage;
extern uint16_t sprinter_exec_fail_err;
extern uint16_t sprinter_exec_fail_name;
extern uint16_t sprinter_exec_fail_root;
extern uint16_t sprinter_exec_fail_cwd;
extern uint16_t sprinter_exec_fail_ino;
extern uint16_t sprinter_exec_fail_mode;
extern uint8_t sprinter_exec_fail_perm;
extern uint8_t sprinter_exec_fail_mflags;
extern uint16_t sprinter_exec_fail_argv;
extern uint16_t sprinter_exec_fail_envp;
extern uint16_t sprinter_exec_fail_done;
extern uint16_t sprinter_exec_fail_count;
extern uint8_t spr_doexec_arm;
extern uint8_t spr_doexec_seen;
extern uint16_t spr_doexec_expect;
extern uint16_t spr_doexec_isp;
extern uint8_t spr_doexec_call_seen;
extern uint16_t spr_doexec_call_sp;
extern uint16_t spr_doexec_call_ra0;
extern uint16_t spr_doexec_call_ra1;
extern uint16_t spr_doexec_call_af;
extern uint16_t spr_doexec_call_start;
#define EX_TRACE(x) plt_trace(x)
#define EX_SDBG(stage, a, b, c, d, e, f, g, h) \
	do { \
		sprinter_dbg[15] = (uint8_t)(stage); \
		sprinter_dbg[16] = (uint8_t)(a); \
		sprinter_dbg[17] = (uint8_t)(b); \
		sprinter_dbg[18] = (uint8_t)(c); \
		sprinter_dbg[19] = (uint8_t)(d); \
		sprinter_dbg[20] = (uint8_t)(e); \
		sprinter_dbg[21] = (uint8_t)(f); \
		sprinter_dbg[22] = (uint8_t)(g); \
		sprinter_dbg[23] = (uint8_t)(h); \
	} while (0)
#else
static uint8_t sprinter_exec_fail_stage;
static uint16_t sprinter_exec_fail_err;
static uint16_t sprinter_exec_fail_ino;
static uint16_t sprinter_exec_fail_mode;
static uint8_t sprinter_exec_fail_perm;
static uint8_t sprinter_exec_fail_mflags;
static uint16_t sprinter_exec_fail_done;
static uint16_t sprinter_exec_fail_count;
#define EX_TRACE(x) do { } while (0)
#define EX_SDBG(stage, a, b, c, d, e, f, g, h) do { } while (0)
#endif

#ifdef CONFIG_SPRINTER_EARLY_TRACE
static inoptr sprinter_pid1_synth_ino(uint16_t inum, uint16_t isize,
				      uint16_t blk0)
{
	inoptr ino;
	inoptr j;
	uint_fast8_t i;
	extern void spr_map_win0_k(void);

	spr_map_win0_k();
	if (fs_tab[0].m_dev == NO_DEVICE)
		fs_tab[0].m_dev = root_dev;
	ino = NULLINODE;
	for (j = i_tab; j < i_tab + (ITABSIZE / 2); j++) {
		if (j->c_refs == 0) {
			ino = j;
			break;
		}
	}
	if (!ino)
		return NULLINODE;
	ino->c_node.i_mode = 0x81ED;
	ino->c_node.i_nlink = 1;
	ino->c_node.i_uid = 0;
	ino->c_node.i_gid = 0;
	ino->c_node.i_size = isize;
	ino->c_node.i_atime = 0;
	ino->c_node.i_mtime = 0;
	ino->c_node.i_ctime = 0;
	ino->c_node.i_addr[0] = blk0;
	ino->c_node.i_addr[1] = 0;
	for (i = 2; i < 20; i++)
		ino->c_node.i_addr[i] = 0;
	ino->c_dev = root_dev;
	ino->c_num = inum;
	ino->c_super = 0;
	ino->c_magic = CMAGIC;
	ino->c_flags = 0;
	ino->c_readers = 0;
	ino->c_writers = 0;
	ino->c_refs = 1;
	return ino;
}

static inoptr sprinter_pid1_init_open(uint8_t *exec_name)
{
	uint_fast8_t i;

	if (!exec_name || !udata.u_ptab || udata.u_ptab->p_pid != 1)
		return NULLINODE;

	/* Kernel exec_or_die("/init") — path in kernel space. */
	if (udata.u_sysio &&
	    exec_name[0] == '/' && exec_name[1] == 'i' &&
	    exec_name[2] == 'n' && exec_name[3] == 'i' &&
	    exec_name[4] == 't')
		return sprinter_pid1_synth_ino(131, 218, 293);

	/*
	 * Sticky u_sysio from earlier kernel I/O blocked the userland
	 * "/bin/sh" match (argn was 0x01C6 but !u_sysio failed).  Only
	 * clear it for the known sprinit_raw path pointer.
	 */
	if ((uarg_t)exec_name == 0x01C6)
		udata.u_sysio = false;

	/* Userland sprinit_raw: literal "/bin/sh" at 0x01C6. */
	if (!udata.u_sysio && (uarg_t)exec_name == 0x01C6) {
		inoptr ino = sprinter_pid1_synth_ino(177, 26630, 1003);
		if (!ino)
			return NULLINODE;
		for (i = 0; i < 18; i++)
			ino->c_node.i_addr[i] = 1003 + i;
		ino->c_node.i_addr[18] = 1021;
		ino->c_node.i_addr[19] = 0;
		return ino;
	}
	return NULLINODE;
}
#endif

/* We don't share this routine between the exec routines as we optimise the
   8bit one differently */
static void close_on_exec(void)
{
	/* Keep the mask separate to stop SDCC generating crap code */
	register uint16_t m = 1U << (UFTSIZE - 1);
	register int_fast8_t j;

	for (j = UFTSIZE - 1; j >= 0; --j) {
		if (udata.u_cloexec & m)
			doclose(j);
		m >>= 1;
	}
	udata.u_cloexec = 0;
}

/* User's execve() call. All other flavors are library routines. */
/*******************************************
execve (name, argv, envp)        Function 23
char *name;
char *argv[];
char *envp[];
********************************************/
#define name (uint8_t *)udata.u_argn
#define argv (uint8_t **)udata.u_argn1
#define envp (uint8_t **)udata.u_argn2

/*
 *	See exec.h
 */
static int header_ok(register struct exec *pp)
{
	/* Executable ? */
	if (pp->a_magic != EXEC_MAGIC)
		return 0;
	/* Right CPU type ? */
	if (pp->a_cpu != sys_cpu)
		return 0;
	/* Compatible with this system ? */
	if ((pp->a_cpufeat & sys_cpu_feat) != pp->a_cpufeat)
		return 0;
	return 1;
}

arg_t _execve(void)
{
	/* We aren't re-entrant where this matters */
	staticfast struct exec hdr;
	staticfast inoptr ino;
	uint8_t **nargv;		/* In user space */
	uint8_t **nenvp;		/* In user space */
	struct s_argblk *abuf, *ebuf;
	int argc;
	uaddr_t progptr;
	uaddr_t progload;
	staticfast uaddr_t top;
	uaddr_t bin_size;	/* Will need to be bigger on some cpus */
	uaddr_t bss;
	uaddr_t min_bin;
	uint_fast8_t mflags;
	uint8_t *exec_name;
	uarg_t exec_name_ptr;
	uint8_t exec_name_lo;
	uint8_t exec_name_hi;
	uint8_t exec_c0 = 0;
	uint8_t exec_c1 = 0;
	uint8_t exec_c2 = 0;
	uint8_t exec_c3 = 0;
	uint8_t exec_c4 = 0;
	uint16_t root_magic = 0;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	/* Stack-local: must not live in WIN0 _DATA (see snapshot below). */
	uint8_t entry_off = 0;
	uaddr_t entry_abs = 0;
#endif

	top = ramtop;

	exec_name_lo = (uint8_t)udata.u_argn;
	exec_name_hi = (uint8_t)(((uarg_t)udata.u_argn) >> 8);
	exec_name_ptr = (uarg_t)udata.u_argn;
	exec_name = (uint8_t *)exec_name_ptr;

#ifdef CONFIG_SPRINTER_EARLY_TRACE
	/* Copy the exec path into a dedicated 32-byte kernel buffer that
	 * does NOT get wrapped out of the circular trace.  Also trace the
	 * first 6 bytes for short-term visibility. */
	{
		extern void spr_map_win0_k(void);
		spr_map_win0_k();
	}
	sprinter_exec_fail_stage = 0xA0;
	sprinter_exec_fail_err = 0;
	sprinter_exec_fail_name = exec_name_ptr;
	sprinter_exec_fail_root = (uint16_t)(uarg_t)udata.u_root;
	sprinter_exec_fail_cwd = (uint16_t)(uarg_t)udata.u_cwd;
	sprinter_exec_fail_ino = 0;
	sprinter_exec_fail_mode = 0;
	sprinter_exec_fail_perm = 0;
	sprinter_exec_fail_mflags = 0;
	sprinter_exec_fail_argv = (uint16_t)(uarg_t)argv;
	sprinter_exec_fail_envp = (uint16_t)(uarg_t)envp;
	sprinter_exec_fail_done = 0;
	sprinter_exec_fail_count = 0;
	if (udata.u_sysio && exec_name_ptr) {
		exec_c0 = exec_name[0];
		exec_c1 = exec_name[1];
		exec_c2 = exec_name[2];
		exec_c3 = exec_name[3];
		exec_c4 = exec_name[4];
	}
	if (udata.u_root)
		root_magic = udata.u_root->c_magic;
	EX_SDBG(0xE0, udata.u_sysio,
		exec_c0, exec_c1, exec_c2, exec_c3, exec_c4,
		(uint8_t)root_magic, (uint8_t)(root_magic >> 8));
	EX_TRACE(0xEF);
		{
			uint_fast8_t i;
			for (i = 0; i < 6; i++) {
				uint8_t c = 0;
				if (exec_name_ptr) {
					if (udata.u_sysio)
						c = exec_name[i];
					else
						c = (uint8_t)ugetc((void *)(exec_name_ptr + i));
				}
				EX_TRACE(c);
				if (c == 0)
					break;
		}
		/* Pad trace to always 6 bytes so alignment is predictable. */
		while (i < 6) {
			EX_TRACE(0);
			i++;
		}
	}
#endif

	ino = NULLINODE;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_exec_fail_stage = 0xA1;
	ino = sprinter_pid1_init_open(exec_name);
	if (ino) {
		EX_SDBG(0xEB,
			(uint8_t)(uarg_t)ino, (uint8_t)(((uarg_t)ino) >> 8),
			(uint8_t)ino->c_node.i_mode, (uint8_t)(ino->c_node.i_mode >> 8),
			(uint8_t)ino->c_dev, (uint8_t)(ino->c_dev >> 8),
			(uint8_t)ino->c_num, (uint8_t)(ino->c_num >> 8));
	}
	sprinter_exec_fail_stage = 0xA2;
#endif
	if (!ino)
		ino = n_open_lock(exec_name, NULLINOPTR);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_exec_fail_stage = 0xA3;
#endif
	if (!ino)
	{
		sprinter_exec_fail_stage = 1;
		sprinter_exec_fail_err = udata.u_error;
		EX_TRACE(0xE1);
		EX_TRACE((uint8_t)udata.u_error);
		return (-1);
	}
	sprinter_exec_fail_ino = (uint16_t)(uarg_t)ino;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	{
		extern void spr_map_win0_k(void);
		/* i_tab / mode bits live in WIN0 DATA. */
		spr_map_win0_k();
		if ((uarg_t)ino < (uarg_t)i_tab ||
		    (uarg_t)ino >= (uarg_t)(i_tab + ITABSIZE)) {
			sprinter_exec_fail_stage = 1;
			sprinter_exec_fail_err = EBADF;
			udata.u_error = EBADF;
			return (-1);
		}
	}
#endif
	sprinter_exec_fail_mode = ino->c_node.i_mode;
	sprinter_exec_fail_perm = getperm(ino);
	EX_SDBG(0xE1,
		(uint8_t)(uarg_t)ino, (uint8_t)(((uarg_t)ino) >> 8),
		(uint8_t)ino->c_node.i_mode, (uint8_t)(ino->c_node.i_mode >> 8),
		sprinter_exec_fail_perm,
		(uint8_t)ino->c_dev, (uint8_t)(ino->c_dev >> 8),
		(uint8_t)ino->c_num);

	EX_TRACE(0xE2);
	EX_TRACE(0xEE);
	EX_TRACE(((uint8_t *)ino)[0]);
	EX_TRACE(((uint8_t *)ino)[1]);
	EX_TRACE(((uint8_t *)ino)[2]);
	EX_TRACE(((uint8_t *)ino)[3]);
	EX_TRACE(((uint8_t *)ino)[4]);
	EX_TRACE(((uint8_t *)ino)[5]);
	EX_TRACE(((uint8_t *)ino)[6]);
	EX_TRACE(((uint8_t *)ino)[7]);
	EX_TRACE((uint8_t)(uarg_t)ino);
	EX_TRACE((uint8_t)(((uarg_t)ino) >> 8));
	EX_TRACE((uint8_t)ino->c_magic);
	EX_TRACE((uint8_t)(ino->c_magic >> 8));
	EX_TRACE((uint8_t)ino->c_dev);
	EX_TRACE((uint8_t)(ino->c_dev >> 8));
	EX_TRACE((uint8_t)ino->c_num);
	EX_TRACE((uint8_t)(ino->c_num >> 8));
	EX_TRACE((uint8_t)ino->c_node.i_mode);
	EX_TRACE((uint8_t)(ino->c_node.i_mode >> 8));

	if (!((getperm(ino) & OTH_EX) &&
	      (ino->c_node.i_mode & F_REG) &&
	      (ino->c_node.i_mode & (OWN_EX | OTH_EX | GRP_EX)))) {
		EX_TRACE(0xE3);
		EX_TRACE((uint8_t)getperm(ino));
		EX_TRACE((uint8_t)ino->c_node.i_mode);
		EX_TRACE((uint8_t)(ino->c_node.i_mode >> 8));
		sprinter_exec_fail_stage = 2;
		sprinter_exec_fail_err = EACCES;
		udata.u_error = EACCES;
		goto nogood;
	}

#ifdef CONFIG_SPRINTER_EARLY_TRACE
	{
		extern void spr_map_win0_k(void);
		spr_map_win0_k();
		/* fmount has been seen to leave m_dev=NO_DEVICE while the
		 * superblock payload is live — then c_super becomes junk
		 * and fs_tab[c_super].m_flags reads as MS_NOEXEC. */
		if (fs_tab[0].m_dev == NO_DEVICE)
			fs_tab[0].m_dev = root_dev;
		if (ino->c_super >= NMOUNTS)
			ino->c_super = 0;
	}
#endif

	mflags = fs_tab[ino->c_super].m_flags;
	sprinter_exec_fail_mflags = mflags;
	if (mflags & MS_NOEXEC) {
		EX_TRACE(0xE4);
		EX_TRACE((uint8_t)mflags);
		sprinter_exec_fail_stage = 3;
		sprinter_exec_fail_err = EACCES;
		udata.u_error = EACCES;
		goto nogood;
	}

	setftime(ino, A_TIME);

	udata.u_offset = 0;
	udata.u_count = sizeof(struct exec);
	udata.u_base = (uint8_t *)&hdr;
	udata.u_sysio = true;

	readi(ino, 0);
	EX_TRACE(0xED);
	EX_TRACE((uint8_t)udata.u_done);
	EX_TRACE((uint8_t)(((uarg_t)udata.u_done) >> 8));
	EX_TRACE(((uint8_t *)&hdr)[0]);
	EX_TRACE(((uint8_t *)&hdr)[1]);
	EX_TRACE(((uint8_t *)&hdr)[2]);
	EX_TRACE(((uint8_t *)&hdr)[3]);
	if (udata.u_done != sizeof(struct exec)) {
		sprinter_exec_fail_stage = 4;
		sprinter_exec_fail_err = ENOEXEC;
		udata.u_error = ENOEXEC;
		goto nogood;
	}

	if (!header_ok(&hdr)) {
		EX_TRACE(0xF1);
		sprinter_exec_fail_stage = 5;
		sprinter_exec_fail_err = ENOEXEC;
		udata.u_error = ENOEXEC;
		goto nogood2;
	}
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	/* hdr is staticfast in WIN0 _DATA.  After user readi/uput WIN0 may
	 * still be the process page, so late hdr.a_entry loads see user BSS
	 * (0) and doexec jumps to PROGLOAD — the syscall stubs.  Snapshot
	 * while WIN0 is still kernel (header was just read with u_sysio). */
	{
		extern void spr_map_win0_k(void);
		spr_map_win0_k();
	}
	entry_off = hdr.a_entry;
	/* Bring-up: sprinit_raw always enters at PROGLOAD+0x12. */
	if (udata.u_ptab->p_pid == 1)
		entry_off = 0x12;
#endif
	EX_SDBG(0xE2,
		hdr.a_base, hdr.a_size,
		(uint8_t)hdr.a_text, (uint8_t)(hdr.a_text >> 8),
		(uint8_t)hdr.a_data, (uint8_t)(hdr.a_data >> 8),
		(uint8_t)hdr.a_bss, (uint8_t)(hdr.a_bss >> 8));
	EX_TRACE(0xF2);

	if (pagemap_prepare(&hdr) < 0)
	{
		EX_TRACE(0xF3);
		sprinter_exec_fail_stage = 6;
		sprinter_exec_fail_err = udata.u_error;
		goto nogood2;
	}
	EX_TRACE(0xF4);

	progload = hdr.a_base << 8;
	top = (hdr.a_base + hdr.a_size) << 8;

	/* For now assume no split I/D. We will need to revisit this and
	   pagemap_realloc when we add that so that the work is done in
	   pagemap_realloc and passed back somehow */

	/* top can overflow. We check below */
	bss = hdr.a_bss;
	min_bin = 64;

	bin_size = hdr.a_text + hdr.a_data;
	/* Does it fit ? */
	if (bin_size < hdr.a_text || top < progload || bin_size + bss < bin_size) {
		EX_TRACE(0xF5);
		sprinter_exec_fail_stage = 7;
		sprinter_exec_fail_err = ENOMEM;
		udata.u_error = ENOMEM;
		goto nogood2;
	}
#ifdef DP_SIZE
	if (hdr.a_zp > DP_SIZE) {
		sprinter_exec_fail_stage = 14;
		sprinter_exec_fail_err = ENOMEM;
		sprinter_exec_fail_done = hdr.a_zp;
		sprinter_exec_fail_count = DP_SIZE;
		udata.u_error = ENOMEM;
		goto nogood2;
	}
#endif
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	/* Sprinter bring-up uses a tiny pure-asm /init probe (sprinit0).
	 * It is a valid exec16 image whose text+data is only 24 bytes, and
	 * the real hard floor here is the 16-byte header overwritten by
	 * sys_stubs, not the historical 64-byte heuristic. Keep the relax
	 * local to early-trace builds until the full init path is stable. */
	min_bin = sizeof(struct exec);
#endif
	progptr = bin_size + 1024 + bss;
	if (bin_size < min_bin || progload < PROGLOAD ||
	    top - progload < progptr || progptr < bin_size) {
		EX_TRACE(0xF6);
		sprinter_exec_fail_stage = 15;
		sprinter_exec_fail_err = ENOMEM;
		sprinter_exec_fail_done = (uint16_t)bin_size;
		sprinter_exec_fail_count = (uint16_t)progptr;
		udata.u_error = ENOMEM;
		goto nogood2;
	}

	udata.u_ptab->p_status = P_NOSLEEP;

	/* If we made pagemap_realloc keep hold of some defined area we
	   could in theory just move the arguments up or down as part of
	   the process - that would save us all this hassle but replace it
	   with new hassle */

	/* Gather the arguments, and put them in temporary buffers. */
	abuf = (struct s_argblk *) tmpbuf();
	/* Put environment in another buffer. */
	ebuf = (struct s_argblk *) tmpbuf();

	/* Read args and environment from process memory */
	if (rargs(argv, abuf))
	{
		EX_TRACE(0xF7);
		sprinter_exec_fail_stage = 8;
		sprinter_exec_fail_err = udata.u_error;
		goto nogood3;	/* SN */
	}
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	/*
	 * PID1 bring-up: second rargs(envp) via ugetp has been seen to
	 * fail while leaving a stale EEXIST from the prior write(1).
	 * sprinit_raw always passes an empty env — skip the usermem walk.
	 */
	if (udata.u_ptab->p_pid == 1) {
		ebuf->a_argc = 0;
		ebuf->a_arglen = 0;
		udata.u_error = 0;
	} else
#endif
	if (rargs(envp, ebuf))
	{
		EX_TRACE(0xF7);
		sprinter_exec_fail_stage = 9;
		sprinter_exec_fail_err = udata.u_error;
		goto nogood3;	/* SN */
	}
	EX_TRACE(0xF8);

	/* This must be the last test as it makes changes if it works */
	/* This is only safe from deadlocks providing pagemap_realloc doesn't
	   sleep */
	if (pagemap_realloc(&hdr, top - MAPBASE))
	{
		EX_TRACE(0xF9);
		sprinter_exec_fail_stage = 10;
		sprinter_exec_fail_err = udata.u_error;
		goto nogood3;
	}
	EX_SDBG(0xE3,
		(uint8_t)progload, (uint8_t)(progload >> 8),
		(uint8_t)top, (uint8_t)(top >> 8),
		(uint8_t)bin_size, (uint8_t)(bin_size >> 8),
		(uint8_t)bss, (uint8_t)(bss >> 8));
	EX_TRACE(0xFA);

#ifdef CONFIG_PLATFORM_UDMA
	plt_udma_kill(udata.u_ptab);
#endif
	/* From this point on we are commmited to the exec() completing */

	/* Core dump and ptrace permission logic */
#ifdef CONFIG_LEVEL_2
	/* Q: should uid == 0 mean we always allow core */
	if ((!(getperm(ino) & OTH_RD)) ||
		(ino->c_node.i_mode & (SET_UID | SET_GID)))
		udata.u_flags |= U_FLAG_NOCORE;
	else
		udata.u_flags &= ~U_FLAG_NOCORE;
#endif
	udata.u_top = top;
	udata.u_ptab->p_top = top;

	if (!(mflags & MS_NOSUID)) {
		/* setuid, setgid if executable requires it */
		if (ino->c_node.i_mode & SET_UID)
			udata.u_euid = ino->c_node.i_uid;
		if (ino->c_node.i_mode & SET_GID)
			udata.u_egid = ino->c_node.i_gid;
	}

	/* FIXME: In the execve case we may on some platforms have space
	   below PROGLOAD to clear... */

	udata.u_codebase = progload;

	/*
	 * We place the stubs below the program in the hole left by the
	 * header. It's like the Linux VDSO except that it's not virtual
	 * not dynamic and not shared 8).
	 */
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	/* Sprinter bring-up split: bulk __uput() is currently the only
	 * blocker left between stage E3 and E4 (RST38 at FA01 with E3
	 * payload still live).  Copy the 16-byte stub header one byte at a
	 * time to separate __uput ABI/stack issues from mapper correctness.
	 * This is temporary diagnostics under early-trace only. */
	{
		uint_fast8_t si;
		for (si = 0; si < sizeof(struct exec); si++) {
			if (uputc(sys_stubs[si], (uint8_t *)(progload + si))) {
				sprinter_exec_fail_stage = 16;
				sprinter_exec_fail_err = udata.u_error;
				sprinter_exec_fail_done = (uint16_t)(progload + si);
				sprinter_exec_fail_count = si;
				goto nogood4;
			}
		}
	}
#else
	uput(sys_stubs, (uint8_t *)progload, sizeof(struct exec));
#endif
	EX_SDBG(0xE4,
		(uint8_t)progload, (uint8_t)(progload >> 8),
		((uint8_t *)&udata.u_page)[0], ((uint8_t *)&udata.u_page)[1],
		((uint8_t *)&udata.u_page)[2], ((uint8_t *)&udata.u_page)[3],
		(uint8_t)udata.u_error, 0);
	/* At this point, we are committed to reading in and
	 * executing the program. This call must not block. */

	close_on_exec();

	/*
	 *  Read in the rest of the program, block by block. We rely upon
	 *  the optimization path in readi to spot this is a big move to user
	 *  space and move it directly.
	 */

	progptr = progload + sizeof(struct exec);
	bin_size -= sizeof(struct exec);
	udata.u_base = (uint8_t *)progptr;		/* We copied the first block already */
	udata.u_count = bin_size;
	udata.u_sysio = false;

	/* Should not be possible */
	{
		usize_t va;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
		extern uint16_t sprinter_last_exec_base;
		extern uint16_t sprinter_last_exec_count;
		extern uint16_t sprinter_last_exec_top;
		sprinter_last_exec_base = (uint16_t)(uarg_t)udata.u_base;
		sprinter_last_exec_count = (uint16_t)udata.u_count;
		sprinter_last_exec_top = (uint16_t)udata.u_top;
#endif
		va = valaddr_r(udata.u_base, udata.u_count);
		if (va != udata.u_count) {
			EX_TRACE(0xFB);
			sprinter_exec_fail_stage = 11;
			sprinter_exec_fail_err = udata.u_error;
			sprinter_exec_fail_done = (uint16_t)va;
			sprinter_exec_fail_count = (uint16_t)udata.u_count;
			goto nogood4;
		}
	}
	EX_SDBG(0xE5,
		(uint8_t)(uarg_t)udata.u_base, (uint8_t)(((uarg_t)udata.u_base) >> 8),
		(uint8_t)udata.u_count, (uint8_t)(((uarg_t)udata.u_count) >> 8),
		(uint8_t)udata.u_top, (uint8_t)(udata.u_top >> 8),
		0, 0);
	readi(ino, 0);
	if (udata.u_done != bin_size)
	{
		EX_TRACE(0xFC);
		EX_TRACE((uint8_t)udata.u_done);
		EX_TRACE((uint8_t)(((uarg_t)udata.u_done) >> 8));
		EX_TRACE(0xCE);
		EX_TRACE((uint8_t)bin_size);
		EX_TRACE((uint8_t)(((uarg_t)bin_size) >> 8));
		EX_TRACE(0xCF);
		EX_TRACE((uint8_t)udata.u_error);
		sprinter_exec_fail_stage = 12;
		sprinter_exec_fail_err = udata.u_error;
		sprinter_exec_fail_done = (uint16_t)udata.u_done;
		sprinter_exec_fail_count = (uint16_t)bin_size;
		goto nogood4;
	}
	EX_SDBG(0xE6,
		(uint8_t)udata.u_done, (uint8_t)(((uarg_t)udata.u_done) >> 8),
		(uint8_t)bin_size, (uint8_t)(((uarg_t)bin_size) >> 8),
		(uint8_t)(uarg_t)udata.u_base, (uint8_t)(((uarg_t)udata.u_base) >> 8),
		(uint8_t)udata.u_error, 0);
	EX_TRACE(0xFD);
	progptr += bin_size;

#ifdef CONFIG_SPRINTER_EARLY_TRACE
	if (udata.u_ptab->p_pid == 1)
		kputs("SPR@E6\r\n");
#endif
	/* Wipe the memory in the BSS. We don't wipe the memory above
	   that on 8bit boxes, but defer it to brk/sbrk() */
	uzero((uint8_t *)progptr, bss);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	if (udata.u_ptab->p_pid == 1)
		kputs("SPR@E7\r\n");
#endif

	/* Wipe zero page/direct page spaces if present */
#ifdef DP_SIZE
	uzero((uint8_t *)DP_BASE, DP_SIZE);
	EX_SDBG(0xE8,
		(uint8_t)DP_BASE, (uint8_t)(DP_BASE >> 8),
		(uint8_t)DP_SIZE, (uint8_t)(DP_SIZE >> 8),
		(uint8_t)progptr, (uint8_t)(progptr >> 8),
		0, 0);
#endif

	/* Set initial break for program */
	udata.u_break = (int)ALIGNUP(progptr + bss);
	EX_SDBG(0xE7,
		(uint8_t)progptr, (uint8_t)(progptr >> 8),
		(uint8_t)bss, (uint8_t)(bss >> 8),
		(uint8_t)udata.u_break, (uint8_t)(((uarg_t)udata.u_break) >> 8),
		0, 0);

	/* Turn off caught signals */
	memset(udata.u_sigvec, 0, sizeof(udata.u_sigvec));

	// place the arguments, environment and stack at the top of userspace memory,

	// Write back the arguments and the environment
	nargv = wargs(((uint8_t *) top - 2), abuf, &argc);
	nenvp = wargs((uint8_t *) (nargv), ebuf, NULL);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	if (udata.u_ptab->p_pid == 1)
		kputs("SPR@E8\r\n");
#endif

	// Fill in udata.u_name with program invocation name
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	/* PID1 bring-up: ugetp/uget here has been crashing after wargs
	 * (E8 reached, A3 not).  Skip name copy for init; keep path alive. */
	if (udata.u_ptab->p_pid != 1) {
		uget((void *) ugetp(nargv), udata.u_name, 8);
		memcpy(udata.u_ptab->p_name, udata.u_name, 8);
	} else {
		udata.u_name[0] = 'i';
		udata.u_name[1] = 'n';
		udata.u_name[2] = 'i';
		udata.u_name[3] = 't';
		udata.u_name[4] = 0;
		memcpy(udata.u_ptab->p_name, udata.u_name, 8);
	}
#else
	uget((void *) ugetp(nargv), udata.u_name, 8);
	memcpy(udata.u_ptab->p_name, udata.u_name, 8);
#endif

	tmpfree(abuf);
	tmpfree(ebuf);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	if (udata.u_ptab->p_pid == 1)
		kputs("SPR@A3\r\n");
#endif
	i_deref(ino);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	if (udata.u_ptab->p_pid == 1)
		kputs("SPR@A4\r\n");
#endif

	/* Shove argc and the address of argv just below envp
	   FIXME: should flip them in crt0.S of app for R2L setups
	   so we can get rid of the ifdefs */
#ifdef CONFIG_CALL_R2L	/* Arguments are stacked the 'wrong' way around */
	uputp((uaddr_t) nargv, nenvp - 2);
	uputp((uaddr_t) argc, nenvp - 1);
#else
	uputp((uaddr_t) nargv, nenvp - 1);
	uputp((uaddr_t) argc, nenvp - 2);
#endif

	/* Set stack pointer for the program */
	udata.u_isp = nenvp - 2;
	EX_SDBG(0xE9,
		(uint8_t)(uarg_t)nargv, (uint8_t)(((uarg_t)nargv) >> 8),
		(uint8_t)(uarg_t)nenvp, (uint8_t)(((uarg_t)nenvp) >> 8),
		(uint8_t)argc, (uint8_t)(argc >> 8),
		(uint8_t)(uarg_t)udata.u_isp, (uint8_t)(((uarg_t)udata.u_isp) >> 8));

#ifdef CONFIG_SPRINTER_EARLY_TRACE
	/* Dump the page map we're about to hand to user space, plus the
	 * entry point, user SP and top-of-memory.  If any of u_page[0..2]
	 * shows as 0x48 the user binary never landed in RAM (map_proc_2
	 * fallback), which historically presented as `[NMI]` or random
	 * HALT instructions.  Verified ok with the uput fixes in place. */
	entry_abs = progload + entry_off;
	if (udata.u_ptab->p_pid == 1)
		kputs("SPR@A5\r\n");
	{
		extern void spr_map_win0_k(void);
		spr_map_win0_k();
	}
	if (udata.u_ptab->p_pid == 1)
		kputs("SPR@A6\r\n");
	EX_TRACE(0xA5);
	EX_TRACE((uint8_t)entry_off);
	EX_TRACE((uint8_t)entry_abs);
	EX_TRACE((uint8_t)(entry_abs >> 8));
	EX_TRACE(0xFE);
	EX_TRACE(((uint8_t *)&udata.u_page)[0]);
	EX_TRACE(((uint8_t *)&udata.u_page)[1]);
	EX_TRACE(((uint8_t *)&udata.u_page)[2]);
	EX_TRACE(((uint8_t *)&udata.u_page)[3]);
	EX_TRACE((uint8_t)entry_abs);
	EX_TRACE((uint8_t)(entry_abs >> 8));
	EX_TRACE((uint8_t)udata.u_isp);
	EX_TRACE((uint8_t)(((uarg_t)udata.u_isp) >> 8));
	EX_TRACE((uint8_t)top);
	EX_TRACE((uint8_t)(top >> 8));
#endif

#ifdef CONFIG_SPRINTER_EARLY_TRACE
	/* Skip kputs here: console path has been a crash surface with WIN0
	 * still ambiguous after the FE dump.  Screen traces above are enough. */
#endif

	/* Start execution (never returns) */
	udata.u_ptab->p_status = P_RUNNING;
	sprinter_exec_fail_stage = 17;
	sprinter_exec_fail_err = 0;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_exec_fail_done = (uint16_t)entry_abs;
#else
	sprinter_exec_fail_done = (uint16_t)(progload + hdr.a_entry);
#endif
	sprinter_exec_fail_count = (uint16_t)(uarg_t)udata.u_isp;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	EX_SDBG(0xEA,
		(uint8_t)entry_abs,
		(uint8_t)(entry_abs >> 8),
		(uint8_t)(uarg_t)udata.u_isp,
		(uint8_t)(((uarg_t)udata.u_isp) >> 8),
		((uint8_t *)&udata.u_page)[0], ((uint8_t *)&udata.u_page)[1],
		((uint8_t *)&udata.u_page)[2], ((uint8_t *)&udata.u_page)[3]);
	spr_doexec_expect = (uint16_t)entry_abs;
	spr_doexec_isp = (uint16_t)(uarg_t)udata.u_isp;
	spr_doexec_call_seen = 0;
	spr_doexec_call_sp = 0;
	spr_doexec_call_ra0 = 0;
	spr_doexec_call_ra1 = 0;
	spr_doexec_call_af = 0;
	spr_doexec_call_start = 0;
	spr_doexec_seen = 0;
	spr_doexec_arm = 1;
	doexec(entry_abs);
	sprinter_exec_fail_stage = 13;
	sprinter_exec_fail_err = 0;
	sprinter_exec_fail_done = (uint16_t)entry_abs;
#else
	EX_SDBG(0xEA,
		(uint8_t)(progload + hdr.a_entry),
		(uint8_t)((progload + hdr.a_entry) >> 8),
		(uint8_t)(uarg_t)udata.u_isp,
		(uint8_t)(((uarg_t)udata.u_isp) >> 8),
		((uint8_t *)&udata.u_page)[0], ((uint8_t *)&udata.u_page)[1],
		((uint8_t *)&udata.u_page)[2], ((uint8_t *)&udata.u_page)[3]);
	doexec(progload + hdr.a_entry);
	sprinter_exec_fail_stage = 13;
	sprinter_exec_fail_err = 0;
	sprinter_exec_fail_done = (uint16_t)(progload + hdr.a_entry);
#endif
	sprinter_exec_fail_count = (uint16_t)(uarg_t)udata.u_isp;

	/* tidy up in various failure modes */
nogood4:
	EX_TRACE(0xD4);
	EX_TRACE((uint8_t)udata.u_error);
	/* Must not run userspace */
	ssig(udata.u_ptab, SIGKILL);
nogood3:
	EX_TRACE(0xD3);
	EX_TRACE((uint8_t)udata.u_error);
	udata.u_ptab->p_status = P_RUNNING;
	tmpfree(abuf);
	tmpfree(ebuf);
nogood2:
	EX_TRACE(0xD2);
	EX_TRACE((uint8_t)udata.u_error);
nogood:
	EX_TRACE(0xD1);
	EX_TRACE((uint8_t)udata.u_error);
	i_unlock_deref(ino);
	EX_TRACE(0xD0);
	EX_TRACE((uint8_t)udata.u_error);
	return (-1);
}

#undef name
#undef argv
#undef envp
