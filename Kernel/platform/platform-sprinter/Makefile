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
	rm -f $(OBJS) $(JUNK) core *~ fuzix.sprinter mbr.bin boot.bin

IMAGES = $(FUZIX_ROOT)/Images/$(TARGET)

#
#	Disk layout (raw sectors):
#	  Sector 0   (LBA 0):     mbr.bin  (512 B) -- MBR: partition table + 0x55AA
#	  Sector 1   (LBA 1):     boot.bin (512 B) -- Sprinter boot sector ("Starting...")
#	  Sectors 2-257 (128 KB): fuzix.sprinter   -- FUZIX kernel (8 pages x 16 KB)
#	  Sectors 258+:           FUZIX filesystem -- hda1, partition 1 per MBR
#
#	The Sprinter BIOS reads LBA 1 to find the OS boot sector.
#	tinydisk_setup() reads LBA 0 for the MBR partition table.
#

mbr.bin:
	python3 -c "import struct,sys;b=bytearray(512);b[446]=0x80;b[450]=0x7E;b[454:458]=struct.pack('<I',258);b[458:462]=struct.pack('<I',65535);b[510]=0x55;b[511]=0xAA;sys.stdout.buffer.write(bytes(b))" > mbr.bin

boot.bin: boot.s
	sdasz80 -o boot.s
	sdldz80 -i boot.rel
	makebin -s 0x8200 -o 0x8000 boot.ihx > boot.bin

#
#	Build the kernel binary image (8 pages, 128 KB)
#
image: mbr.bin boot.bin
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
	cp mbr.bin $(IMAGES)/
	cp boot.bin $(IMAGES)/
	# Create a 32 MB raw disk image (65793 sectors = 1 MBR + 1 boot + 256 kernel + 65535 fs)
	dd if=/dev/zero of=$(IMAGES)/fuzix.img bs=512 count=65793
	# Sector 0 (LBA 0): MBR with partition table
	dd if=mbr.bin of=$(IMAGES)/fuzix.img bs=512 count=1 conv=notrunc
	# Sector 1 (LBA 1): Sprinter boot sector
	dd if=boot.bin of=$(IMAGES)/fuzix.img bs=512 seek=1 conv=notrunc
	# Sectors 2-257 (LBA 2-257): FUZIX kernel (128 KB = 256 sectors)
	dd if=fuzix.sprinter of=$(IMAGES)/fuzix.img bs=512 seek=2 conv=notrunc
	# Sectors 258+ (LBA 258+): FUZIX filesystem (partition 1 per MBR at LBA 0)
	dd if=$(IMAGES)/filesys.img of=$(IMAGES)/fuzix.img bs=512 seek=258 conv=notrunc
	# Convert to MAME CHD format if chdman is available
	-$(if $(shell which chdman 2>/dev/null),chdman createhd \
	    --input $(IMAGES)/fuzix.img \
	    --output $(IMAGES)/fuzix.chd \
	    --compression none --force, \
	    echo "chdman not found -- skipping CHD conversion (install via: make -C mame TOOLS=1 chdman)")

chd:
	chdman createhd --input $(IMAGES)/fuzix.img \
	                --output $(IMAGES)/fuzix.chd \
	                --compression none --force

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
