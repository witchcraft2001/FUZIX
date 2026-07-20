#include "kernel.h"
#include "kdata.h"

#ifdef CONFIG_SPRINTER_EARLY_TRACE
extern void plt_trace(uint8_t code);
#define B512_TRACE(x) plt_trace(x)
static uint8_t b512_trace_count;
static uint8_t b512_root_dumped;
#else
#define B512_TRACE(x) do { } while (0)
#endif

#if (BLKSIZE == 512)

/*
 *	File system routines for the usual 512 byte block size
 */

/* Return the number of blocks an inode occupies assuming all blocks present */
blkno_t inode_blocks(inoptr i)
{
    return (i->c_node.i_size + BLKMASK) >> BLKSHIFT;
}

/* Read an inode */
uint_fast8_t breadi(uint16_t dev, uint16_t ino, void *ptr)
{
    struct blkbuf *buf = bread(dev, (ino >> 3) + 2, 0);
    uint16_t off = sizeof(struct dinode) * (ino & 7);
    if (buf == NULL)
        return 1;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    if (dev == root_dev && ino == ROOTINODE && b512_root_dumped == 0) {
        uint8_t *src = buf->__bf_data + off;
        uint8_t *dst = (uint8_t *)ptr;
        B512_TRACE(0xA8);
        B512_TRACE((uint8_t)dev);
        B512_TRACE((uint8_t)(dev >> 8));
        B512_TRACE((uint8_t)ino);
        B512_TRACE((uint8_t)(ino >> 8));
        B512_TRACE(src[0]); B512_TRACE(src[1]); B512_TRACE(src[2]); B512_TRACE(src[3]);
        B512_TRACE(src[4]); B512_TRACE(src[5]); B512_TRACE(src[6]); B512_TRACE(src[7]);
        blktok(ptr, buf, off, sizeof(struct dinode));
        B512_TRACE(0xA9);
        B512_TRACE(dst[0]); B512_TRACE(dst[1]); B512_TRACE(dst[2]); B512_TRACE(dst[3]);
        B512_TRACE(dst[4]); B512_TRACE(dst[5]); B512_TRACE(dst[6]); B512_TRACE(dst[7]);
        b512_root_dumped = 1;
        brelse(buf);
        return 0;
    }
    if (b512_trace_count < 4) {
        uint8_t *src = buf->__bf_data + off;
        uint8_t *dst = (uint8_t *)ptr;
        B512_TRACE(0xA0);
        B512_TRACE((uint8_t)ino);
        B512_TRACE((uint8_t)(ino >> 8));
        B512_TRACE(src[0]); B512_TRACE(src[1]); B512_TRACE(src[2]); B512_TRACE(src[3]);
        B512_TRACE(src[4]); B512_TRACE(src[5]); B512_TRACE(src[6]); B512_TRACE(src[7]);
        blktok(ptr, buf, off, sizeof(struct dinode));
        B512_TRACE(0xA1);
        B512_TRACE(dst[0]); B512_TRACE(dst[1]); B512_TRACE(dst[2]); B512_TRACE(dst[3]);
        B512_TRACE(dst[4]); B512_TRACE(dst[5]); B512_TRACE(dst[6]); B512_TRACE(dst[7]);
        b512_trace_count++;
        brelse(buf);
        return 0;
    }
#endif
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    {
	extern void spr_map_win0_k(void);
	/* Destination dinode may live in WIN0 i_tab. */
	spr_map_win0_k();
    }
#endif
    blktok(ptr, buf, off, sizeof(struct dinode));
    brelse(buf);
    return 0;
}

/* Write an inode */
uint_fast8_t bwritei(inoptr ino)
{
    blkno_t blkno = (ino->c_num >> 3) + 2;
    struct blkbuf *buf = bread(ino->c_dev, blkno, 0);
    if (buf == NULL)
        return 1;
    blkfromk(&ino->c_node, buf, sizeof(struct dinode) * (ino->c_num & 0x07),
            sizeof(struct dinode));
    bfree(buf, 2);
    return 0;
}

/*
 * Bmap defines the structure of file system storage by returning
 * the physical block number on a device given the inode and the
 * logical block number in a file.  The block is zeroed if created.
 */
blkno_t bmap(inoptr ip, blkno_t bn, unsigned int rwflg)
{
    int i;
    bufptr bp;
    int j;
    blkno_t nb;
    int sh;
    uint16_t dev;

    if(getmode(ip) == MODE_R(F_BDEV))
        return(bn);

    dev = ip->c_dev;

    /* blocks 0..17 are direct blocks
    */
    if(bn < 18) {
        nb = ip->c_node.i_addr[bn];
        if(nb == 0) {
            if(rwflg ||(nb = blk_alloc(dev))==0)
                return(NULLBLK);
            ip->c_node.i_addr[bn] = nb;
            ip->c_flags |= CDIRTY;
        }
        return(nb);
    }

    /* addresses 18 and 19 have single and double indirect blocks.
     * the first step is to determine how many levels of indirection.
     */
    bn -= 18;
    sh = 0;
    j = 2;
    if(bn & 0xff00){       /* bn > 255  so double indirect */
        sh = 8;
        bn -= 256;
        j = 1;
    }

    /* fetch the address from the inode
     * Create the first indirect block if needed.
     */
    if(!(nb = ip->c_node.i_addr[20-j]))
    {
        if(rwflg || !(nb = blk_alloc(dev)))
            return(NULLBLK);
        ip->c_node.i_addr[20-j] = nb;
        ip->c_flags |= CDIRTY;
    }

    /* fetch through the indirect blocks
    */
    for(; j<=2; j++) {
        bp = bread(dev, nb, 0);
        if (bp == NULL) {
            corrupt_fs(ip->c_dev);
            return 0;
        }
        i = (bn >> sh) & 0xff;
        nb = *(blkno_t *)blkptr(bp, (sizeof(blkno_t)) * i, sizeof(blkno_t));
        if (nb)
            brelse(bp);
        else
        {
            if(rwflg || !(nb = blk_alloc(dev))) {
                brelse(bp);
                return(NULLBLK);
            }
            blkfromk(&nb, bp, i * sizeof(blkno_t), sizeof(blkno_t));
            bawrite(bp);
        }
        sh -= 8;
    }
    return(nb);
}

#endif
