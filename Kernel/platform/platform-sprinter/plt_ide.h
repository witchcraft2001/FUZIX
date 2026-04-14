/*
 *	Sprinter IDE interface definitions
 *
 *	The Sprinter uses 16-bit port addressing for IDE registers.
 *	We use indirect access via custom C functions.
 */

#ifndef __PLT_IDE_H__
#define __PLT_IDE_H__

/* Use indirect register access */
#define CONFIG_TINYIDE_INDIRECT

/*
 *	IDE register "addresses" - these are codes passed to
 *	ide_read/ide_write, not actual Z80 port numbers.
 *	The actual 16-bit port addressing is handled in ide.c
 */
#define data	0
#define error	1
#define count	2
#define sec	3
#define cyll	4
#define cylh	5
#define devh	6
#define cmd	7
#define status	7
#define altstatus 14
#define control 14

extern uint_fast8_t ide_read(uint_fast8_t regaddr);
extern void ide_write(uint_fast8_t regaddr, uint_fast8_t val);
extern void devide_read_data(uint8_t *dptr);
extern void devide_write_data(uint8_t *dptr);

#define ide_select(x)
#define ide_deselect()

#endif /* __PLT_IDE_H__ */
