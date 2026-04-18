#include <kernel.h>
#include <version.h>
#include <kdata.h>
#include <tty.h>
#include <devsys.h>
#include <devtty.h>
#include <tinydisk.h>

struct devsw dev_tab[] =  /* The device driver switch table */
{
/*   open	    close	read		write		ioctl */
  /* 0: /dev/hd - block device interface */
  {  no_open,       no_close,   no_rdwr,        no_rdwr,	no_ioctl},
  /* 1: unused */
  {  no_open,	    no_close,	no_rdwr,	no_rdwr,	no_ioctl},
  /* 2: /dev/tty -- serial/console ports */
  {  tty_open,       tty_close,	tty_read,	tty_write,	tty_ioctl},
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
