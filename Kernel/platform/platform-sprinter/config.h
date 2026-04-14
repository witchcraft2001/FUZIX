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
#define CONFIG_LARGE_IO_DIRECT(x)	1
/*
 * 256 total 16K pages in 4MB RAM.
 * Reserve pages 0-7 for kernel (CODE, 3 code banks, common):
 *   0 = WIN0 (CODE), 1-2 = bank1, 3 = common,
 *   4-5 = bank2, 6-7 = bank3
 * Skip VRAM pages 0x50-0x5F.
 * User pages: 8-79 (0x08-0x4F) = 72 user pages.
 */
#define MAX_MAPS	72
/* Banked kernel */
#define CONFIG_BANKED
/* Banks as reported to user space */
#define CONFIG_BANKS	4

#define TICKSPERSEC 50	    /* 50 Hz CTC interrupt */
#define PROGBASE    0x0000  /* also data base */
#define PROGLOAD    0x0100  /* also data base */
#define PROGTOP     0xEE00  /* Top of program, base of U_DATA copy */

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

/* Video terminal */
#define CONFIG_VT
/* Font for text console */
#define CONFIG_FONT8X8
/* Vt definitions - 32x24 ZX-compatible text */
#define VT_WIDTH	32
#define VT_HEIGHT	24
#define VT_RIGHT	31
#define VT_BOTTOM	23

#define NUM_DEV_TTY 1

/* TTY as the console */
#define BOOT_TTY (512 + 1)
#define TTY_INIT_BAUD B9600

#define TTYDEV   BOOT_TTY /* Device used by kernel for messages, panics */

#define plt_copyright()		/* for now */
