#include <kernel.h>
#include <version.h>
#include <kdata.h>
#include <printf.h>
#include <tty.h>
#include <vt.h>

#ifdef CONFIG_SPRINTER_EARLY_TRACE
extern void plt_trace(uint8_t code);
#define EARLY_TRACE(x) plt_trace(x)
extern void sprinter_force_bank1(void);
extern uint8_t spr_boot_count;
extern uint8_t sprinter_dbg[];
extern uint8_t spr_initio_stage;
extern uint16_t spr_initio_fd;
extern uint16_t spr_initio_err;
extern uint8_t spr_initio_files[3];
extern arg_t _open(void);
extern arg_t _dup(void);

static arg_t sprinter_open_boot_tty(uint16_t flag)
{
	int_fast8_t uindex;
	int_fast8_t oftindex;
	inoptr ino;

#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_dbg[15] = 0xC8;
	sprinter_dbg[16] = (uint8_t)TTYDEV;
	sprinter_dbg[17] = (uint8_t)(TTYDEV >> 8);
	sprinter_dbg[18] = (uint8_t)flag;
	sprinter_dbg[19] = (uint8_t)(flag >> 8);
	sprinter_dbg[20] = 0xFF;
	sprinter_dbg[21] = 0xFF;
	sprinter_dbg[22] = 0xFF;
	sprinter_dbg[23] = 0xFF;
#endif
	if ((uindex = uf_alloc()) == -1)
		return -1;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_dbg[15] = 0xC9;
	sprinter_dbg[20] = (uint8_t)uindex;
#endif
	if ((oftindex = oft_alloc()) == -1) {
		udata.u_files[uindex] = NO_FILE;
		return -1;
	}
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_dbg[15] = 0xCA;
	sprinter_dbg[21] = (uint8_t)oftindex;
#endif
	for (ino = i_tab; ino < i_tab + ITABSIZE; ++ino) {
		if (ino->c_refs == 0)
			break;
	}
	if (ino == i_tab + ITABSIZE) {
		of_tab[oftindex].o_refs = 0;
		udata.u_files[uindex] = NO_FILE;
		udata.u_error = ENFILE;
		return -1;
	}
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_dbg[15] = 0xCB;
	sprinter_dbg[22] = (uint8_t)(uarg_t)ino;
	sprinter_dbg[23] = (uint8_t)(((uarg_t)ino) >> 8);
#endif
	memset(ino, 0, sizeof(*ino));
	ino->c_magic = CMAGIC;
	/* Char-device inodes must carry the device number in c_dev.
	 * Using root_dev left c_dev=0 after mount churn and made write(1)
	 * hit iobad / EINVAL (MAME: iobad ptr=… dev=0000). */
	ino->c_dev = TTYDEV;
	ino->c_node.i_mode = F_CDEV | 0666;
	ino->c_node.i_nlink = 1;
	ino->c_node.i_addr[0] = TTYDEV;
	ino->c_refs = 1;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_dbg[15] = 0xCC;
#endif
	if (d_open(TTYDEV, flag) != 0) {
		ino->c_refs = 0;
		of_tab[oftindex].o_refs = 0;
		udata.u_files[uindex] = NO_FILE;
		return -1;
	}
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_dbg[15] = 0xCD;
	sprinter_dbg[20] = (uint8_t)udata.u_error;
#endif
	of_tab[oftindex].o_inode = ino;
	of_tab[oftindex].o_ptr = 0;
	of_tab[oftindex].o_access = flag;
	udata.u_files[uindex] = oftindex;
	if (O_ACCMODE(flag) != O_RDONLY)
		ino->c_writers++;
	if (O_ACCMODE(flag) != O_WRONLY)
		ino->c_readers++;
	tty_post(ino, minor(TTYDEV), flag);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_dbg[15] = 0xCE;
#endif
	return uindex;
}

void sprinter_bootmark(char c)
{
	static uint8_t x;

	plot_char(7, x, (uint16_t)c);
	if (x < 79)
		x++;
}

void sprinter_boothex(uint8_t v)
{
	uint8_t n;

	n = v >> 4;
	sprinter_bootmark(n < 10 ? '0' + n : 'A' + (n - 10));
	n = v & 0x0F;
	sprinter_bootmark(n < 10 ? '0' + n : 'A' + (n - 10));
}
#else
#define EARLY_TRACE(x) do { } while (0)
#endif

#define BAD_ROOT_DEV 0xFFFF

static uint8_t ro = 1;

/*
 *	Put nothing here that cannot be discarded. We make the entirety
 *	of this disappear after the initial _execve.
 */

#ifndef TTY_INIT_BAUD
#define TTY_INIT_BAUD B9600
#endif

static const struct termios ttydflt = {
	BRKINT | ICRNL,
	OPOST | ONLCR,
	CS8 | TTY_INIT_BAUD | CREAD | CLOCAL,
	ISIG | ICANON | ECHO | ECHOE | ECHOK | IEXTEN,
	{CTRL('D'), 0, CTRL('H'), CTRL('C'),
	 CTRL('U'), CTRL('\\'), CTRL('Q'), CTRL('S'),
	 CTRL('Z'), CTRL('Y'), CTRL('V'), CTRL('O')
	 }
};

void tty_init(void) {
        register struct tty *t = &ttydata[1];
        register uint_fast8_t i;
        for(i = 1; i <= NUM_DEV_TTY; i++) {
		memcpy(&t->termios, &ttydflt, sizeof(struct termios));
		t++;
        }
}

void bufinit(void)
{
	register bufptr bp;

	for (bp = bufpool; bp < bufpool_end; ++bp) {
		bp->bf_dev = NO_DEVICE;
		bp->bf_busy = BF_FREE;
		bp->bf_dirty = 0;
		bp->bf_time = 0;
	}
}

void fstabinit(void)
{
	register struct mount *mp;

	for (mp = fs_tab; mp < fs_tab + NMOUNTS; ++mp) {
		mp->m_dev = NO_DEVICE;
	}
}

/* Remember two things when modifying this code
   1. Some processors need 2 byte alignment or better of arguments. We
      lay it out for 4
   2. We are going to end up with cases where user and kernel pointer
      size differ due to memory models etc. We use uputp and we allow
      room for the pointers to be bigger than kernel */

static uaddr_t progptr, old_progptr;
static uaddr_t argptr, old_argptr;

#ifdef CONFIG_SPRINTER_EARLY_TRACE
extern uint8_t spr_common_init_path[];
extern uint8_t *spr_common_init_argv[];
extern uint8_t *spr_common_init_envp[];

static void sprinter_prepare_init_stdio(void)
{
	uint8_t old_sysio = udata.u_sysio;
	uint8_t *old_base = udata.u_base;
	arg_t old_argn = udata.u_argn;
	arg_t old_argn1 = udata.u_argn1;
	arg_t old_argn2 = udata.u_argn2;
	arg_t fd;

	spr_initio_stage = 0xC0;
	spr_initio_fd = 0xFFFF;
	spr_initio_err = 0;
	spr_initio_files[0] = udata.u_files[0];
	spr_initio_files[1] = udata.u_files[1];
	spr_initio_files[2] = udata.u_files[2];

	udata.u_sysio = 1;
	spr_initio_stage = 0xC1;
	fd = sprinter_open_boot_tty(O_RDWR);
	spr_initio_stage = 0xC2;
	spr_initio_fd = (uint16_t)fd;
	spr_initio_err = udata.u_error;
	spr_initio_files[0] = udata.u_files[0];
	spr_initio_files[1] = udata.u_files[1];
	spr_initio_files[2] = udata.u_files[2];
	sprinter_bootmark('j');
	if ((int16_t)fd >= 0) {
		udata.u_argn = fd;
		spr_initio_stage = 0xC3;
		_dup();
		spr_initio_stage = 0xC4;
		spr_initio_err = udata.u_error;
		spr_initio_files[0] = udata.u_files[0];
		spr_initio_files[1] = udata.u_files[1];
		spr_initio_files[2] = udata.u_files[2];
		sprinter_bootmark('k');
		udata.u_argn = fd;
		spr_initio_stage = 0xC5;
		_dup();
		spr_initio_stage = 0xC6;
		spr_initio_err = udata.u_error;
		spr_initio_files[0] = udata.u_files[0];
		spr_initio_files[1] = udata.u_files[1];
		spr_initio_files[2] = udata.u_files[2];
		sprinter_bootmark('l');
	}
	udata.u_sysio = old_sysio;
	udata.u_base = old_base;
	udata.u_argn = old_argn;
	udata.u_argn1 = old_argn1;
	udata.u_argn2 = old_argn2;
	spr_initio_stage = 0xCF;
}
#endif

void add_argument(const char *s)
{
	int l = strlen(s) + 1;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	/*
	 * Sprinter bring-up: PID1 still trips in the validated uput/uputp
	 * wrapper path while staging the initial "/init" argv.  Use the
	 * raw usermem helpers here so we exercise only the banked copy path
	 * itself and move the next failure edge forward.
	 */
	_uput((const uint8_t *)s, (uint8_t *)progptr, l);
	_uputw((uint16_t)progptr, (uint16_t *)argptr);
#else
	uput(s, (void *)progptr, l);
	uputp(progptr, (void *)argptr);
#endif
	progptr += ((l + 3) & ~3);
	argptr += sizeof(uptr_t);
}

void create_init(void)
{
	register uint8_t *j, *e;
	EARLY_TRACE(0xC1);

	/*
	 * Sprinter bring-up: the historical one-page bootstrap map
	 * (PROGLOAD + 512) leaves PID1 with a degenerate page table until
	 * _execve() grows it, and on Sprinter the handoff already trips
	 * over mixed 0x08/0x49/0x4A mappings before that path stabilises.
	 * Start init with a full user map so the first exec/open path
	 * always sees a canonical 4-page process layout.
	 */
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	udata.u_top = PROGTOP;
#else
	udata.u_top = PROGLOAD + 512;	/* Plenty for the boot */
#endif
	init_process = ptab_alloc();
	udata.u_ptab = init_process;
	init_process->p_top = udata.u_top;
	map_init();
	EARLY_TRACE(0xC2);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('4');
#endif

	/* wipe file table */
	e = udata.u_files + UFTSIZE;
	for (j = udata.u_files; j < e; ++j)
		*j = NO_FILE;

	makeproc(init_process, &udata);
	EARLY_TRACE(0xC3);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('5');
#endif

	udata.u_insys = 1;
	init_process->p_status = P_RUNNING;

	/* Poke the execve arguments into user data space so _execve() can read them back */
	/* Some systems only have a tiny window we can use at boot as most of
	   this space is loaded with common memory */
	argptr = PROGLOAD;
	progptr = PROGLOAD + 256;

	/*
	 * Sprinter bring-up: the first PID1 user-space bulk zero still
	 * traps before the argv handoff.  This scratch area is immediately
	 * overwritten by add_argument("/init") and later argv terminators,
	 * so skipping the pre-clear under early trace lets boot advance to
	 * the next real handoff edge without affecting other targets.
	 */
#ifdef CONFIG_SPRINTER_EARLY_TRACE
#else
	uzero((void *)progptr, 32);
#endif
	EARLY_TRACE(0xC4);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('6');
#else
	add_argument("/init");
#endif
	EARLY_TRACE(0xC5);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('7');
	EARLY_TRACE(0xC6);
	sprinter_bootmark('8');
#endif
}

#ifdef CONFIG_SPRINTER_EARLY_TRACE
void rebuild_init_argv(void)
{
	argptr = PROGLOAD;
	progptr = PROGLOAD + 256;
	uzero((void *)progptr, 32);
	add_argument("/init");
	_uputw(0, (uint16_t *)argptr);
	udata.u_argn2 = (arg_t)argptr;
	udata.u_argn = (arg_t)PROGLOAD + 256;
	udata.u_argn1 = (arg_t)PROGLOAD;
}
#endif

void complete_init(void)
{
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	/*
	 * Sprinter bring-up: the initial PID1 user-space argv staging still
	 * traps in add_argument()/uput before the real exec loader starts.
	 * Hand _execve() common-memory-resident "/init", argv[] and envp[]
	 * under u_sysio so the next failure edge moves into the actual exec
	 * path without depending on the current code bank mapping.
	 */
	udata.u_sysio = 1;
	udata.u_argn2 = (arg_t)spr_common_init_envp;
	udata.u_argn = (arg_t)spr_common_init_path;
	udata.u_argn1 = (arg_t)spr_common_init_argv;
#else
	/* Terminate argv, also use this as the env ptr */
	uputp(0, (void *)argptr);
	/* Set up things to look like the process is calling _execve() */
	udata.u_argn2 = (arg_t)argptr; /* Environment (none) */
	udata.u_argn =  (arg_t)PROGLOAD + 256; /* "/init" */
	udata.u_argn1 = (arg_t)PROGLOAD; /* Arguments */
#endif
	EARLY_TRACE(0xE8);
	EARLY_TRACE((uint8_t)udata.u_argn);
	EARLY_TRACE((uint8_t)(((uarg_t)udata.u_argn) >> 8));
	EARLY_TRACE((uint8_t)udata.u_argn1);
	EARLY_TRACE((uint8_t)(((uarg_t)udata.u_argn1) >> 8));
	EARLY_TRACE((uint8_t)udata.u_argn2);
	EARLY_TRACE((uint8_t)(((uarg_t)udata.u_argn2) >> 8));

#ifdef CONFIG_LEVEL_2
	init_process->p_session = 1;
#endif
	init_process->p_pgrp = 1;
}

#if !defined(BOOTDEVICE) || defined(BOOTPARAM)

/* Parse boot device name, based on platform defined BOOTDEVICENAMES string.
 *
 * This string is a list of device driver names delimited by commas. Device
 * driver names should be listed in the same order as entries in dev_tab.
 * Unbootable slots should be listed with an empty name. The position in the
 * list of names specifies the top 8 bits of the minor number.
 *
 * Names which end in a # character expect a letter suffix which specifies bits
 * 4--7 of the minor number.
 *
 * All names can be followed by an index number which is added to the minor
 * number. The user can provide only this index number, in which case it
 * specifies the full minor number.
 *
 * Some example BOOTDEVICENAMES:
 * "hd#,fd"
 *    hda   gives 0x0000
 *    hda1  gives 0x0001
 *    hdc   gives 0x0020
 *    hdc3  gives 0x0023
 *    fd0   gives 0x0100
 *    fd15  gives 0x010F
 *    17    gives 0x0011
 *
 * "fd,hd#,,ram"  (slot 2 in dev_tab is the tty device which is unbootable)
 *    fd0   gives 0x0000
 *    fd1   gives 0x0001
 *    hda1  gives 0x0101
 *    hdc3  gives 0x0123
 *    ram7  gives 0x0307
 *    17    gives 0x0011
 */

#ifndef BOOTDEVICENAMES
#define BOOTDEVICENAMES "" /* numeric parsing only */
#endif

static uint8_t system_param(register char *p)
{
	if (*p == 'r' && p[2] == 0) {
		if (p[1] == 'o') {
			ro = MS_RDONLY;
			return 1;
		} else if (p[1] == 'w') {
			ro = 0;
			return 1;
		}
	}
	/* FIXME: Parse init=path ?? */
	return plt_param(p);
}

/* Parse other arguments */
void parse_args(register char *p)
{
	register char *s;
	while(*p) {
		while(*p == ' ' || *p == '\n')
			p++;
		s = p;
		while(*p && *p != ' ' && *p != '\n')
			p++;
		if(*p)
			*p++=0;
		if (!system_param(s))
			add_argument(s);

	}
}
#endif

#if !defined(BOOTDEVICE)

uint16_t bootdevice(char *devname)
{
	bool match = true;
	unsigned int b = 0, n = 0;
	register char *p;
	const uint8_t *bdn = (const uint8_t *)BOOTDEVICENAMES;
	uint8_t c, pc;

	/* skip spaces at start of string */
	while(*devname == ' '){
		devname++;
	}

	p = devname;

	/* first we try to the match device name */
	while(true){
		pc = *p;
		if(pc >= 'A' && pc <= 'Z')
			pc |= 0x20; /* lower case */
		c = *bdn;

		if(!c){
			/* end of device names string */
			break;
		}else if(c == ','){
			/* next device driver */
			if(match == true && p != devname)
				break;
			p = devname;
			b += 0x100;
			match = true;
			bdn++;
			continue;
		}else if(match && c == '#'){
			/* parse device drive letter */
			if(pc < 'a' || pc > 'p')
				return BAD_ROOT_DEV;
			b += ((pc-'a') << 4);
			p++;
			break;
		}else if(match && pc != c){
			match = false;
		}
		p++;
		bdn++;
	}

	/* if we didn't match a device name, start over */
	if(!match){
		b = 0;
		p = devname;
	}

	/* then we read an index number */
	while(*p >= '0' && *p <= '9'){
		n = (n*10) + (*p - '0');
		p++;
		match = true;
	}

	/* string ends in junk? */
	switch(*p) {
		case 0:
		case '\n':
		case '\r':
			break;
		case ' ':
			parse_args(p);
			break;
		default:
			return BAD_ROOT_DEV;
	}

	if(match)
		return (b + n);
	else
		return BAD_ROOT_DEV;
}

/* So its in discard and thrown not on stack */
static char bootline[64];

uint16_t get_root_dev(void)
{
	uint16_t rd = BAD_ROOT_DEV;

	if (cmdline && *cmdline){
		rd = bootdevice(cmdline);
        }
        cmdline = NULL;                   /* ignore cmdline if get_root_dev() is called again */

	while(rd == BAD_ROOT_DEV){
		kputs("bootdev: ");
		udata.u_base = (uint8_t *)bootline;
		udata.u_sysio = 1;
		udata.u_count = sizeof(bootline)-1;
		udata.u_euid = 0;		/* Always begin as superuser */
		udata.u_done = 0;

		cdread(TTYDEV, O_RDONLY);	/* read root filesystem name from tty */
		bootline[udata.u_done] = 0;
		rd = bootdevice(bootline);
	}

	return rd;
}

void set_boot_line(const char *p)
{
	/* This is a little bit ugly but we want it in discard. Override any
	   command line if the user already hit a key */
	/* Give the user bit of time by calling pause(10) */
	udata.u_argn = 10;
	_pause();
	if (!tty_pending(TTYDEV)) {
		memcpy(bootline, p, 63);
		cmdline = bootline;
	}
}

#else

static inline uint16_t get_root_dev(void)
{
#ifdef BOOTPARAM
	parse_args(BOOTPARAM);
#endif
	return BOOTDEVICE;
}
#endif

void fuzix_main(void)
{
	struct mount *m;
	uint16_t tty_open_rc;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	spr_boot_count++;
	sprinter_dbg[20] = 0xBA;
	sprinter_dbg[21] = 0x27;
	sprinter_dbg[22] = 0x04;
	sprinter_dbg[23] = 0x6C;
	#endif
	/* setup state */
	udata.u_ininterrupt = 0;
	udata.u_insys = true;

#ifdef PROGTOP		/* FIXME */
	ramtop = (uaddr_t)PROGTOP;
#endif

	EARLY_TRACE(0x11);
	tty_init();
	EARLY_TRACE(0x12);

	EARLY_TRACE(0xD0);
	#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_force_bank1();
	#endif

	EARLY_TRACE(0x13);
	tty_open_rc = d_open(TTYDEV, 0);
	EARLY_TRACE(0x14);
	EARLY_TRACE(0xD1);
	EARLY_TRACE((uint8_t)tty_open_rc);
	EARLY_TRACE(0xD2);
	EARLY_TRACE((uint8_t)udata.u_error);
	if (tty_open_rc != 0) {
		EARLY_TRACE(0xE1);
		tty_open_rc = 0;
		udata.u_error = 0;
		EARLY_TRACE(0xE2);
	}

	/* Sign on messages */
	EARLY_TRACE(0x15);
	kprintf(
			"FUZIX version %s\n"
			"Copyright (c) 1988-2002 by H.F.Bower, D.Braun, S.Nitschke, H.Peraza\n"
			"Copyright (c) 1997-2001 by Arcady Schekochikhin, Adriano C. R. da Cunha\n"
			"Copyright (c) 2013-2015 Will Sowerbutts <will@sowerbutts.com>\n"
			"Copyright (c) 2014-2025 Alan Cox <alan@etchedpixels.co.uk>\nDevboot\n",
			sysinfo.uname);
	EARLY_TRACE(0x16);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	EARLY_TRACE(0x17);
	sprinter_bootmark('0');
	sprinter_bootmark('r');
	EARLY_TRACE(0x18);
#endif

	set_cpu_type();
	sysinfo.cpu[0] = sys_cpu_feat;
	sysinfo.cputype = sys_cpu;
	plt_copyright();
#ifndef SWAPDEV
#ifdef PROC_SIZE
	maxproc = procmem / PROC_SIZE;
	/* Check we don't exceed the process table size limit */
	if (maxproc > PTABSIZE) {
		kprintf("WARNING: Increase PTABSIZE to %d to use available RAM\n",
				maxproc);
		maxproc = PTABSIZE;
	}
#else
	maxproc = PTABSIZE;
#endif
#else
	maxproc = PTABSIZE;
#endif
	/* Used as a stop marker to make compares fast on process
	   scheduling and the like */
	ptab_end = &ptab[maxproc];

	bufinit();
	EARLY_TRACE(0x21);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('1');
#endif
	fstabinit();
	EARLY_TRACE(0x22);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('2');
#endif
	pagemap_init();
	EARLY_TRACE(0x23);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('3');
#endif
	create_init();
	EARLY_TRACE(0x24);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('9');
	sprinter_bootmark('A');
#endif

	/* Parameters message (temporarily suppressed during sprinter bring-up) */
	EARLY_TRACE(0x25);

	/* runtime configurable, defaults to build time setting */
	ticks_per_dsecond = TICKSPERSEC / 10;

	/* There are some setups we delay the EI until after we've dumped the
	   discard */
#ifndef CONFIG_PLATFORM_LATE_EI
	/* Temporarily keep IRQs disabled during Sprinter bring-up. */
	EARLY_TRACE(0x27);
#endif
	EARLY_TRACE(0x26);

	/* initialise hardware devices */
	device_init();
	EARLY_TRACE(0x30);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('B');
#endif

	do {
		static uint8_t mount_tries;
		EARLY_TRACE(0x31);
            old_progptr = progptr;
            old_argptr = argptr;
            /* Get a root device to try */
	            root_dev = (uint8_t)get_root_dev();
            EARLY_TRACE(0x32);
            EARLY_TRACE((uint8_t)root_dev);
		EARLY_TRACE(0x3E);
		EARLY_TRACE((uint8_t)(root_dev >> 8));
#ifdef CONFIG_SPRINTER_EARLY_TRACE
		sprinter_bootmark('E');
#endif
            if (root_dev == BAD_ROOT_DEV) {
			EARLY_TRACE(0x33);
			root_dev = 1;
			EARLY_TRACE(0x3B);
            }
#ifdef CONFIG_SPRINTER_EARLY_TRACE
		EARLY_TRACE(0xE4);
		sprinter_dbg[15] = 0xEF;
		plot_char(6, 0, (uint16_t)'u');
		EARLY_TRACE(0xE5);
		plot_char(6, 1, (uint16_t)'F');
		EARLY_TRACE(0xE6);
		sprinter_bootmark('F');
		EARLY_TRACE(0xE7);
		sprinter_dbg[15] = 0xF0;
		sprinter_dbg[16] = (uint8_t)root_dev;
		sprinter_dbg[17] = (uint8_t)(root_dev >> 8);
		sprinter_dbg[18] = ro;
#endif
            /* Mount the root device */
		EARLY_TRACE(0x34);
		/* Console output disabled while early tty bring-up is unstable. */
#ifdef CONFIG_SPRINTER_EARLY_TRACE
		EARLY_TRACE(0xE8);
		sprinter_dbg[15] = 0xF1;
#endif
            m = fmount(root_dev, NULLINODE, ro);
		EARLY_TRACE(0x35);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
		sprinter_dbg[15] = 0xF2;
		sprinter_dbg[16] = (uint8_t)(uarg_t)m;
		sprinter_dbg[17] = (uint8_t)(((uarg_t)m) >> 8);
		sprinter_dbg[18] = (uint8_t)udata.u_error;
		sprinter_bootmark('G');
		/* Observed: m_fs live but m_dev cleared after fmount/sync. */
		if (m && m->m_dev == NO_DEVICE)
			m->m_dev = root_dev;
#endif
            if (m == NULL) {
			EARLY_TRACE(0x36);
			EARLY_TRACE(0x3C);
			EARLY_TRACE((uint8_t)udata.u_error);
			EARLY_TRACE(0x3F);
			EARLY_TRACE(mount_tries);
			mount_tries++;
			EARLY_TRACE(0x3A);
			EARLY_TRACE(mount_tries);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
			sprinter_dbg[15] = 0xF7;
			sprinter_dbg[16] = mount_tries;
			sprinter_dbg[17] = (uint8_t)udata.u_error;
			sprinter_dbg[18] = (uint8_t)root_dev;
			sprinter_bootmark('H');
#endif
			if (mount_tries >= 1) {
				EARLY_TRACE(0x3D);
				panic(PANIC_NOROOT);
			}
		    /* reset potentially altered state before prompting the user for command line again */
	            progptr = old_progptr;
		    argptr = old_argptr;
	            ro = MS_RDONLY;
	    } else
			EARLY_TRACE(0x37);
        } while(m == NULL);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('C');
#endif

        /* Set the system time from the superblock. In turn user space will
           set it from the user or rtc when prompted. Setting it here
           however means the date is often right and that time goes forward */
        tod.low = m->m_fs.s_time;
        tod.high = m->m_fs.s_timeh;

	EARLY_TRACE(0x38);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_dbg[10] = 0x35;
	sprinter_dbg[11] = (uint8_t)root_dev;
	sprinter_dbg[12] = (uint8_t)(root_dev >> 8);
	sprinter_dbg[13] = ROOTINODE;
	sprinter_dbg[14] = 0;
#endif
	root = i_open(root_dev, ROOTINODE);
	if (!root) {
		EARLY_TRACE(0x39);
		panic(PANIC_NOROOT);
	}
	EARLY_TRACE(0x3A);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('D');
#endif

	kputs("OK\n");

	/* finish building argv */
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('a');
#endif
	complete_init();
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('b');
#endif
	EARLY_TRACE(0xE9);
	EARLY_TRACE((uint8_t)udata.u_argn);
	EARLY_TRACE((uint8_t)(((uarg_t)udata.u_argn) >> 8));
	EARLY_TRACE((uint8_t)udata.u_argn1);
	EARLY_TRACE((uint8_t)(((uarg_t)udata.u_argn1) >> 8));
	EARLY_TRACE((uint8_t)udata.u_argn2);
	EARLY_TRACE((uint8_t)(((uarg_t)udata.u_argn2) >> 8));

	udata.u_cwd = i_ref(root);
	udata.u_root = i_ref(root);
	udata.u_ptab->p_time = ticks.full;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('c');
	/*
	 * USERLAND open/exec is past the synthetic-/init edge. Re-enable PID1
	 * stdio so write(1) from /init can reach the tty. Prefer keeping this
	 * path until an asm of_tab binder replaces the SDCC store hazard.
	 */
	sprinter_prepare_init_stdio();
	sprinter_bootmark('d');
#endif
	exec_or_die();
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('!');
#endif
}
