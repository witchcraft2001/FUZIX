#ifndef __DEVTTY_DOT_H__
#define __DEVTTY_DOT_H__

extern void kbd_poll(void);
extern int sprinter_tty_open(unsigned char minor, unsigned short flag);

#endif
