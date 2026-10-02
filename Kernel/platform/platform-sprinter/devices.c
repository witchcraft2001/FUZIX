#include <kernel.h>
#include <version.h>
#include <kdata.h>
#include <tty.h>
#include <devsys.h>
#include <devtty.h>
#include <tinydisk.h>

#ifdef CONFIG_SPRINTER_EARLY_TRACE
extern int spr_tty_ioctl(uint_fast8_t minor, uarg_t request, char *data);
extern int spr_tty_read(uint_fast8_t minor, uint_fast8_t rawflag, uint_fast8_t flag);
extern int spr_tty_write(uint_fast8_t minor, uint_fast8_t rawflag, uint_fast8_t flag);
#define TTY_IOCTL spr_tty_ioctl
#define TTY_READ  spr_tty_read
#define TTY_WRITE spr_tty_write
#else
#define TTY_IOCTL tty_ioctl
#define TTY_READ  tty_read
#define TTY_WRITE tty_write
#endif

struct devsw dev_tab[] =  /* The device driver switch table */
{
/*   open	    close	read		write		ioctl */
  /* 0: /dev/hd - block device interface */
  {  no_open,       no_close,   no_rdwr,        no_rdwr,	no_ioctl},
  /* 1: unused */
  {  no_open,	    no_close,	no_rdwr,	no_rdwr,	no_ioctl},
  /* 2: /dev/tty -- serial/console ports */
  {  tty_open,       tty_close,	TTY_READ,	TTY_WRITE,	TTY_IOCTL},
  /* 3: unused */
  {  no_open,	    no_close,	no_rdwr,	no_rdwr,	no_ioctl},
  /* 4: /dev/mem etc      System devices (one offs) */
  {  no_open,	    no_close,	sys_read,	sys_write,	sys_ioctl},
};

bool validdev(uint16_t dev)
{
	if(dev > ((sizeof(dev_tab)/sizeof(struct devsw)) << 8) + 255)
		return false;
	else
		return true;
}
