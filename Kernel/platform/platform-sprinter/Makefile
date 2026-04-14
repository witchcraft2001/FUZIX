ASRCS = crt0.s tricks.s commonmem.s sprinter.s sprvideo.s usermem.s
CSRCS = devices.c main.c ide.c
DISCARD_CSRCS = discard.c
DISCARD_DSRCS = ../../dev/tinyide_discard.c
DSRCS = ../../dev/tinyide.c ../../dev/tinydisk_discard.c ../../dev/tinydisk.c
C3SRCS = devtty.c

AOBJS = $(ASRCS:.s=.rel)
COBJS = $(CSRCS:.c=.rel)
C3OBJS = $(C3SRCS:.c=.rel)
DISCARD_COBJS = $(DISCARD_CSRCS:.c=.rel)
DISCARD_DOBJS = $(patsubst ../../dev/%.c,%.rel, $(DISCARD_DSRCS))
DOBJS = $(patsubst ../../dev/%.c,%.rel, $(DSRCS))

OBJS  = $(AOBJS) $(COBJS) $(C3OBJS) $(DOBJS) $(DISCARD_DOBJS) $(DISCARD_COBJS)

CROSS_CCOPTS += -I../../dev/

JUNK = *.rel *.lst *.asm *.sym *.rst *.map *.ihx *.bin

all:	$(OBJS)

$(AOBJS): %.rel: %.s
	$(CROSS_AS) $(ASOPTS) $<

$(COBJS): %.rel: %.c
	$(CROSS_CC) $(CROSS_CCOPTS) $(CROSS_CC_SEG1) -c $<

$(C3OBJS): %.rel: %.c
	$(CROSS_CC) $(CROSS_CCOPTS) $(CROSS_CC_SEG3) -c $<

$(DOBJS): %.rel: ../../dev/%.c
	$(CROSS_CC) $(CROSS_CCOPTS) $(CROSS_CC_SEG2) -c $<

$(DISCARD_COBJS): %.rel: %.c
	$(CROSS_CC) $(CROSS_CCOPTS) $(CROSS_CC_SEGDISC) -c $<

$(DISCARD_DOBJS): %.rel: ../../dev/%.c
	$(CROSS_CC) $(CROSS_CCOPTS) $(CROSS_CC_SEGDISC) -c $<

clean:
	rm -f $(OBJS) $(JUNK) core *~ fuzix.sprinter

IMAGES = $(FUZIX_ROOT)/Images/$(TARGET)

#
#	Build the 512-byte boot sector binary
#
#	Layout (raw sectors):
#	  Sector 0:        boot.bin     (512 bytes, ORG 0x8000)
#	  Sectors 1-256:   fuzix.sprinter (8 pages x 16KB = 128KB)
#	  Sectors 257+:    FUZIX filesystem
#
boot.bin: boot.s
	sdasz80 -o boot.s
	sdldz80 -i boot.rel
	makebin -s 0x8200 -o 0x8000 boot.ihx > boot.bin

#
#	Build the kernel binary image (8 pages, 128 KB)
#
image: boot.bin
	# Assemble 8 hardware pages (128 KB) in order 0-7.
	# common.bin / bankN.bin are flat 64-KB address-space images:
	#   common.bin  0x0000-0x3FFF = page 0 (CODE/WIN0)
	#               0xC000-0xFFFF = page 3 (COMMONMEM/WIN3)
	#   bank1.bin   0x4000-0x7FFF = page 1, 0x8000-0xBFFF = page 2 (CODE1)
	#   bank2.bin   0x4000-0x7FFF = page 4 (CODE2; page 5 is empty)
	#   bank3.bin   0x4000-0x7FFF = page 6 (CODE3; page 7 is empty)
	# Pages 5 and 7 must be present as zero-filled pages to keep hardware
	# page numbers aligned with disk sector offsets (boot.s maps sector N
	# directly to hardware page N).
	dd if=../../common.bin bs=16384 count=1 conv=sync > fuzix.sprinter
	dd if=../../bank1.bin  bs=16384 skip=1 count=2 conv=sync >> fuzix.sprinter
	dd if=../../common.bin bs=16384 skip=3 count=1 conv=sync >> fuzix.sprinter
	dd if=../../bank2.bin  bs=16384 skip=1 count=1 conv=sync >> fuzix.sprinter
	dd if=/dev/zero        bs=16384        count=1            >> fuzix.sprinter
	dd if=../../bank3.bin  bs=16384 skip=1 count=1 conv=sync >> fuzix.sprinter
	dd if=/dev/zero        bs=16384        count=1            >> fuzix.sprinter

diskimage: image
	mkdir -p $(IMAGES)
	cp fuzix.sprinter $(IMAGES)/
	cp boot.bin $(IMAGES)/
	# Create a 32 MB raw disk image (65792 sectors = 257 kernel + 65535 filesystem)
	dd if=/dev/zero of=$(IMAGES)/fuzix.img bs=512 count=65792
	# Sector 0: boot sector (also contains the MBR partition table at byte 446)
	dd if=boot.bin of=$(IMAGES)/fuzix.img bs=512 count=1 conv=notrunc
	# Sectors 1-256: kernel (128 KB = 256 sectors)
	dd if=fuzix.sprinter of=$(IMAGES)/fuzix.img bs=512 seek=1 conv=notrunc
	# Sectors 257+: FUZIX filesystem (partition 1 per MBR in boot sector)
	dd if=$(IMAGES)/filesys.img of=$(IMAGES)/fuzix.img bs=512 seek=257 conv=notrunc

## Dependencies
commonmem.s: ../../cpu-z80/std-commonmem.s
crt0.s: kernel.def
sprinter.s: kernel.def
tricks.s: kernel.def
usermem.s: kernel.def
kernel.def: ../../cpu-z80/kernel-z80.def

devices.c: ../../include/kernel.h ../../include/kdata.h ../../include/tty.h ../../include/devsys.h devtty.h ../../dev/tinydisk.h
devtty.c: ../../include/kernel.h ../../include/kdata.h ../../include/printf.h ../../include/tty.h ../../include/vt.h devtty.h
discard.c: ../../include/kernel.h ../../include/kdata.h ../../include/printf.h devtty.h ../../dev/tinyide.h ../../dev/tinydisk.h
ide.c: ../../include/kernel.h ../../dev/tinydisk.h ../../dev/tinyide.h ../../include/printf.h plt_ide.h
main.c: ../../include/kernel.h ../../include/kdata.h ../../include/printf.h ../../include/timer.h devtty.h ../../dev/tinydisk.h

../../include/kernel.h: config.h
../../dev/tinyide.h: plt_ide.h
