/*
 *	Peters Plus Sprinter (Peters MC 2008) platform configuration
 *
 *	Z84C15 (CMOS Z80) @ 7 MHz / 21 MHz (turbo)
 *	4 MB RAM, 512 KB ROM/Flash, 512 KB VRAM
 *	4 independent 16K memory windows
 *	IDE HDD, WD1793 FDD, PS/2 keyboard, CMOS RTC
 */

/* Process table sizing */
#define OFTSIZE		48
#define ITABSIZE	40
#define PTABSIZE	16

/* Enable to make ^A drop back into the monitor */
#undef CONFIG_MONITOR
/* Profil syscall support */
#undef CONFIG_PROFIL
/* Multiple processes in memory at once */
#define CONFIG_MULTI
/* Flexible 4x16K banking */
#define CONFIG_BANK16
/* Permit large I/O requests to bypass cache and go direct to userspace */
/* Disabled during bring-up: the direct path invokes map_proc_always with
 * the raw udata.u_page mapping.  If PID1's page map is not fully
 * populated the transfer writes into kernel pages and corrupts the
 * running kernel.  Force everything through the buffer cache until the
 * user mapping is trusted. */
#define CONFIG_LARGE_IO_DIRECT(x)	0
/*
 * 256 total 16K pages in 4MB RAM.
 * Reserve high RAM pages 0x48-0x4F for kernel (CODE, 3 code banks, common):
 *   0x48 = WIN0 (CODE), 0x49-0x4A = bank1, 0x4B = common,
 *   0x4C-0x4D = bank2, 0x4E-0x4F = bank3
 * Skip VRAM pages 0x50-0x5F.
 * Reserve 0x40-0x47 for firmware: 0x40 contains the live DCP table,
 * 0x41 the BIOS RAM workspace. Never let a fork overwrite port decoding.
 * User pages: 0x08-0x3F = 56 user pages.
 */
#define MAX_MAPS	56
/* Banked kernel */
#define CONFIG_BANKED
/* Banks as reported to user space */
#define CONFIG_BANKS	4

#define CONFIG_SPRINTER_EARLY_TRACE

#define TICKSPERSEC 50	    /* 50 Hz CTC interrupt */
#define PROGBASE    0x0000  /* also data base */
#define PROGLOAD    0x0100  /* also data base */
/* Keep the upper 8K of WIN3 for IM2, udata and kernel common. */
#define PROGTOP     0xE000

#define SWAPDEV     (swap_dev)
extern uint16_t swap_dev;
#define SWAP_SIZE   0x78	/* 60K in blocks (prog + udata) */
#define SWAPBASE    0x0000	/* start at the base of user mem */
#define SWAPTOP	    0xF000	/* Swap out udata and program */
#define MAX_SWAPS   16
#define CONFIG_DYNAMIC_SWAP

/*
 *	When the kernel swaps something it needs to map the right page into
 *	memory using map_for_swap and then turn the user address into a
 *	physical address. We use the second 16K window.
 */
#define swap_map(x)	((uint8_t *)((((x) & 0x3FFF)) + 0x4000))

#define CMDLINE	NULL
#define BOOTDEVICENAMES "hd#"

#define NBUFS    5        /* Number of block buffers - must match kernel.def */
#define CONFIG_DYNAMIC_BUFPOOL
#define NMOUNTS	 4	  /* Number of mounts at a time */

#define MAX_BLKDEV 2	    /* IDE only for now */

/* Tiny disk / IDE support */
#define CONFIG_TINYDISK
#define CONFIG_TD_NUM	2
#define CONFIG_TD_IDE
#define TD_IDE_NUM	2
#define CONFIG_TINYIDE_INDIRECT
/* Sprinter IDE is 16-bit but we access in 8-bit mode via custom routines */

/* RTC support via CMOS */
#define CONFIG_RTC
#define CONFIG_RTC_FULL
#define CONFIG_RTC_INTERVAL	50

/* Video terminal - Sprinter native 80x32 text mode */
#define CONFIG_VT
/* Vt definitions - 80x32 native text mode, font in VRAM (loaded by BIOS) */
#define VT_WIDTH	80
#define VT_HEIGHT	32
#define VT_RIGHT	79
#define VT_BOTTOM	31

#define NUM_DEV_TTY 1

/* TTY as the console */
#define BOOT_TTY (512 + 1)
#define TTY_INIT_BAUD B9600

#define TTYDEV   BOOT_TTY /* Device used by kernel for messages, panics */

/*
 * Root device: hda1 = IDE 0 master, partition 1 (LBA 257..65791)
 * The partition entry is embedded in the boot sector at byte 446.
 */
#define BOOTDEVICE	0x0001		/* major 0 (hd), minor 1 (hda1) */
#define BOOTDEVICENAMES	"hd#"

#define plt_copyright()		/* for now */
