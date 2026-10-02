#undef DEBUG
#include <kernel.h>
#include <kdata.h>
#include <printf.h>

#ifdef CONFIG_SPRINTER_EARLY_TRACE
extern void plt_trace(uint8_t code);
#define FM_TRACE(x) plt_trace(x)
extern void sprinter_bootmark(char c);
extern void sprinter_boothex(uint8_t v);
extern uint8_t sprinter_dbg[];
extern uint16_t sprinter_last_ideref_in;
extern uint16_t sprinter_last_ideref_post;
extern uint16_t sprinter_last_ideref_wr;
extern uint16_t sprinter_last_ideref_meta;
extern uint16_t sprinter_last_wr_ptr;
extern uint16_t sprinter_last_wr_meta;
extern uint8_t sprinter_last_wr_site;
extern uint16_t sprinter_last_newfile_pino;
extern uint16_t sprinter_last_newfile_nindex_in;
extern uint16_t sprinter_last_newfile_nindex_prewr;
extern uint16_t sprinter_last_iopen_dev;
extern uint16_t sprinter_last_iopen_ino;
extern uint16_t sprinter_last_iopen_ret;
extern uint8_t sprinter_last_iopen_bad;
extern uint16_t sprinter_last_iopen_mode;
extern uint16_t sprinter_last_iopen_nlink;
extern uint16_t sprinter_bad_iopen_dev;
extern uint16_t sprinter_bad_iopen_ino;
extern uint8_t sprinter_bad_iopen_bad;
extern uint16_t sprinter_bad_iopen_mode;
extern uint16_t sprinter_bad_iopen_nlink;
extern uint16_t sprinter_bad_iopen_ptr;
extern uint16_t sprinter_bad_iopen_a0;
extern uint16_t sprinter_bad_iopen_a1;
extern uint16_t sprinter_bad_iopen_flags;
extern uint8_t sprinter_last_nopen_stage;
extern uint16_t sprinter_last_nopen_wd;
extern uint16_t sprinter_last_nopen_ninode;
extern uint8_t sprinter_last_nopen_name0;
extern uint8_t sprinter_last_nopen_char;
extern uint8_t sprinter_chlink_stage;
extern uint16_t sprinter_chlink_wd;
extern uint16_t sprinter_chlink_nindex;
extern uint16_t sprinter_chlink_done;
extern uint16_t sprinter_chlink_error;
extern uint16_t sprinter_ideref_null_count;
extern uint16_t sprinter_ideref_null_sys;
extern uint16_t spr_gfcnt;
extern uint8_t spr_gfr;
extern uint8_t spr_gfu;
extern uint8_t spr_gfo;
extern uint8_t spr_gffr;
extern uint8_t spr_gffa;
extern uint16_t spr_gfin;
extern uint16_t spr_gfs;
extern uint16_t spr_iac_devptr;
extern uint16_t spr_iac_tinode;
extern uint16_t spr_iac_isize;
extern uint8_t spr_iac_ninode;
extern uint8_t spr_iac_mounted;
extern uint16_t spr_gd_dev;
extern uint16_t spr_gd_mnt;
extern uint16_t spr_gd_state;

#define SPRINTER_TRACE_INODE_DEV 0x0001
#define SPRINTER_TRACE_INODE_NUM 0x0032

static uint16_t sprinter_magic_site;

#define MAGIC_CHECK(site, ino) do { \
    sprinter_magic_site = (site); \
    magic(ino); \
} while (0)

static bool sprinter_trace_inode_match(inoptr ino)
{
    return ino && ino->c_dev == SPRINTER_TRACE_INODE_DEV &&
        ino->c_num == SPRINTER_TRACE_INODE_NUM;
}

static void sprinter_trace_inode_ref(char op, inoptr ino, uint_fast8_t before,
    uint16_t site)
{
    uint16_t pid = 0;

    if (!sprinter_trace_inode_match(ino))
        return;
    if (udata.u_ptab)
        pid = udata.u_ptab->p_pid;
    kprintf("I%c dev=%x num=%x refs=%x>%x nlink=%x mode=%x pid=%x sys=%x in=%x at=%x\n",
        op, ino->c_dev, ino->c_num, before, ino->c_refs,
        ino->c_node.i_nlink, ino->c_node.i_mode,
        pid, udata.u_callno, udata.u_insys, site);
}

#else
#define FM_TRACE(x) do { } while (0)
#define MAGIC_CHECK(site, ino) magic(ino)
#endif

#ifdef CONFIG_SPRINTER_EARLY_TRACE
void sprinter_wr_inode(inoptr ino, uint8_t site)
{
    sprinter_last_wr_ptr = (uint16_t)(uarg_t)ino;
    sprinter_last_wr_site = site;
    sprinter_last_wr_meta = (uint16_t)udata.u_callno |
        ((uint16_t)udata.u_insys << 8);
    wr_inode(ino);
}
#endif

/*
 * There are only two places in the core kernel that know about buffer
 * data and manipulate it directly. This is one of them, and  mm.c is the
 * other. Please keep it that way if at all possible because at some point
 * we will begin supporting out of memory map buffers.
 */

/* N_open is given a string containing a path name in user space,
 * and returns an inode table pointer.  If it returns NULL, the file
 * did not exist.  If the parent existed, and parent is not null,
 * parent will be filled in with the parents inoptr. Otherwise, parent
 * will be set to NULL.
 * The last node parsed is saved in lastname and is useful to some system
 * calls as they want a parent and to create the new node.
 */

#ifdef CONFIG_SPRINTER_EARLY_TRACE
/* lastname lives in platform COMMONMEM (sprinter.s) — WIN0 DATA is unsafe. */
#else
uint8_t lastname[31];
#endif

static uint_fast8_t n_open_fault;
static uint_fast8_t n_fault_type;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
/* Prefer common-resident walk pointers: WIN0 DATA vanishes under user map. */
extern uint8_t *spr_nopen_name;
extern uint8_t *spr_nopen_nameend;
#define name spr_nopen_name
#define nameend spr_nopen_nameend
#else
static uint8_t *name, *nameend;
#endif

#ifdef CONFIG_SPRINTER_EARLY_TRACE
static bool sprinter_inode_ptr_valid(inoptr ino)
{
	return (uarg_t)ino >= (uarg_t)i_tab &&
		(uarg_t)ino < (uarg_t)(i_tab + ITABSIZE);
}

static void sprinter_nopen_snap(uint8_t stage, inoptr wd, inoptr ninode,
	uint8_t c)
{
	sprinter_last_nopen_stage = stage;
	sprinter_last_nopen_wd = (uint16_t)(uarg_t)wd;
	sprinter_last_nopen_ninode = (uint16_t)(uarg_t)ninode;
	sprinter_last_nopen_name0 = lastname[0];
	sprinter_last_nopen_char = c;
}
#endif

static uint8_t getcf(void)
{
    if (name == nameend) {
        udata.u_error = n_fault_type;
        n_open_fault = 1;
        return 0;
    }
    /* n_open() is also used for kernel-resident paths under u_sysio
       (/init, early stdio bootstrap). Those bytes live in kernel/common
       space and must not be fetched through __ugetc(), which forcibly
       remaps process memory. */
    if (udata.u_sysio)
        return *name;
    return (uint8_t)_ugetc(name);
}

inoptr n_open(uint8_t *namep, inoptr *parent)
{
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    /*
     * Sprinter: do NOT keep walk state in WIN0 DATA (staticfast).  bread()
     * / IDE / map_proc can leave WIN0 on a non-kernel page; the next
     * read of wd/ninode then returns garbage and i_deref panics.
     * Stack lives in common (WIN3), so auto locals stay valid.
     */
    inoptr wd;
    inoptr ninode;
#else
    staticfast inoptr wd;     /* the directory we are currently searching. */
    staticfast inoptr ninode;
#endif
    regptr uint8_t *fp;
    regptr inoptr temp;
    uint8_t c;
    usize_t len;

    if (parent)
        *parent = NULLINODE;

#ifdef CONFIG_SPRINTER_EARLY_TRACE
    {
	extern void spr_map_win0_k(void);
	spr_map_win0_k();
    }
#endif

    /*
     * Sprinter early bring-up can hand _execve() a kernel-resident
     * "/init" path via u_sysio to bypass the fragile initial argv/user
     * staging. In that case stay in a bounded 512-byte direct read path
     * instead of validating a userspace pointer.
     */
    if (udata.u_sysio) {
        len = 512;
        name = namep;
        nameend = namep + len;
        n_open_fault = 0;
        n_fault_type = ENAMETOOLONG;
    } else {
        /* Check the user address and length. If it's shorter than 512 bytes this
           is fine, but set nameeend accordingly. This allows us to use _ugetc
           in the hot path which saves us a ton of cycles */
        len = valaddr_r(namep, 512);
        if (len == 0)
            return NULLINODE;

        name = namep;
        nameend = namep + len;
        n_open_fault = 0;

        /* What error do we return if we hit nameend - are we overlong, or out
           of memory space */
        if (len == 512)
            n_fault_type = ENAMETOOLONG;
        else
            n_fault_type = EACCES;
    }

    c = getcf();
    if(c == '/')
        wd = udata.u_root;
    else
        wd = udata.u_cwd;

#ifdef CONFIG_SPRINTER_EARLY_TRACE
    /*
     * Sprinter bring-up: we still see occasional pre-exec corruption where
     * u_root/u_cwd turns into a tiny non-inode value (eg 0x0001) before the
     * first n_open("/init"). Recover from that transient state by reopening
     * ROOTINODE and continue from a validated in-core pointer.
     */
    if (!sprinter_inode_ptr_valid(wd)) {
        inoptr fix = root;

        if (!sprinter_inode_ptr_valid(fix))
            fix = i_open(root_dev, ROOTINODE);

        sprinter_nopen_snap(0xCF, wd, fix, c);
        if (!sprinter_inode_ptr_valid(fix))
            return NULLINODE;
        if (c == '/')
            udata.u_root = fix;
        else
            udata.u_cwd = fix;
        wd = fix;
    }
#endif

#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_nopen_snap(0xD0, wd, wd, 0);
#endif
    ninode = i_ref(wd);
    i_ref(ninode);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_nopen_snap(0xD1, wd, ninode, 0);
#endif

    for(;;)
    {
        /* ninode is the inode we are walking from at this point and wd
           the parent. They may be the same. We hold one reference to each */
        if(ninode)
            MAGIC_CHECK(1, ninode);

        /* cheap way to spot rename inside yourself */
        if (udata.u_rename == ninode)
            udata.u_rename = NULLINODE;

        /* See if we are at a mount point.
           If we are a mount point then we swap the parent inode for
           the child inode and swap the reference to the child
           Q: could we set an incore inode flag for mountpoint to speed
              this up ? */
        if(ninode)
            ninode = srch_mt(ninode);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
        sprinter_nopen_snap(0xD2, wd, ninode, 0);
#endif

        /* Skip any slashes between nodes. The standards say there can be
           multiple slashes */
        while((c = getcf()) == '/')
            ++name;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
        sprinter_nopen_snap(0xD3, wd, ninode, c);
#endif
        /* It is acceptable to end a file path with / */
        if(!c || n_open_fault)           /* No more components of path? */
            break;

        /* If we failed to find our node we are done */
        if(!ninode){
            udata.u_error = ENOENT;
            goto nodir;
        }
        /* Drop the reference to the old parent */
        i_deref(wd);
        /* Make the parent our own node. We now hold a single reference to
           wd/ninode */
        wd = ninode;
        /* If we are still searching and the parent node is not a directory
           we are done and we failed */
        if(getmode(wd) != MODE_R(F_DIR)){
            udata.u_error = ENOTDIR;
            goto nodir;
        }
        /* If we are now allowed to access the directory then we are done */
        if(!(getperm(wd) & OTH_EX)){
            udata.u_error = EACCES;
            goto nodir;
        }

        /* Walk the filename until / or end. Store the filename of up to
           30 characters in lastname which is also used by our callers. It
           is permissible to give longer name that matches the first 30 */
        fp = lastname;
        while((c = getcf()) != '\0') {
            if (c == '/')
                break;
            if (fp != lastname + 30)
                *fp++ = c;
            ++name;
        }
        /* Terminate the lastname buffer with \0 */
        *fp = 0;
        /* We are going up through a mount point if
           either:
           - We are accessing the root inode
           - We are accessing the root inode number of a device
           and:
           - Our path is ..

           FIXME: re-order tests for speed */
        if((wd == udata.u_root || (wd->c_num == ROOTINODE && wd->c_dev != root_dev)) &&
                lastname[0] == '.' && lastname[1] == '.' && lastname[2] == '\0') {
            /* We are doing /../ */
            if (wd == udata.u_root) {
                i_ref(wd);
                continue;
            }
            /* Find the mount point inode, which is hidden by the mount */
            temp = fs_tab[wd->c_super].m_mntpt;
            /* Take a reference to it */
            i_ref(temp);
            /* Drop the old directory */
            i_deref(wd);
            /* Fall through so we walk the mount point directory .. entry */
            wd = temp;
        }
        /* Find the entry in the directory. ninode will be NULL if we failed or
           valid and referenced if it existed */
#ifdef CONFIG_SPRINTER_EARLY_TRACE
        sprinter_nopen_snap(0xD5, wd, ninode, lastname[0]);
	{
		extern void spr_map_win0_k(void);
		spr_map_win0_k();
	}
#endif
        ninode = srch_dir(wd, lastname);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
        sprinter_nopen_snap(0xD6, wd, ninode, lastname[0]);
#endif
    }
    /* If we faulted then treat it as invalid */
    if (n_open_fault) {
        udata.u_error = n_fault_type;
        goto nodir;
    }

#ifdef CONFIG_SPRINTER_EARLY_TRACE
    {
	extern void spr_map_win0_k(void);
	/* Parent/target inodes live in WIN0 DATA. */
	spr_map_win0_k();
	sprinter_nopen_snap(0xD7, wd, ninode, 0);
    }
#endif

    /* Return the parent node if requested. This is needed by callers that
       do directory manipulation */
    if(parent)
        *parent = wd;
    else
        i_deref(wd);
    /* Check if we failed */
    if(!(parent || ninode))
        udata.u_error = ENOENT;
    /* Return the target node if found. NULL with a valid parent is quite
       possible and indicates the directory exists but the filename is new */
    return ninode;

nodir:
    if(parent)
        *parent = NULLINODE;
    i_deref(wd);
    return NULLINODE;
}

/* Srch_dir is given an inode pointer of an open directory and a string
 * containing a filename, and searches the directory for the file.  If
 * it exists, it opens it and returns the inode pointer, otherwise NULL.
 * This depends on the fact that ba_read will return unallocated blocks
 * as zero-filled, and a partially allocated block will be padded with
 * zeroes.
 */

inoptr srch_dir(register inoptr wd, uint8_t *compname)
{
    register struct direct *d;
    register blkno_t curblock;
    register struct blkbuf *buf;
    uint_fast8_t curentry;
    int nblocks;
    uint16_t inum;

#ifdef CONFIG_SPRINTER_EARLY_TRACE
    {
	extern void spr_map_win0_k(void);
	/* wd->c_node / i_tab live in WIN0 DATA. */
	spr_map_win0_k();
    }
#endif

    i_lock(wd);

    nblocks = inode_blocks(wd);

    for(curblock=0; curblock < nblocks; ++curblock) {
        buf = bread(wd->c_dev, bmap(wd, curblock, 1), 0);
        if (buf == NULL)
            break;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	{
		extern void spr_map_win0_k(void);
		spr_map_win0_k();
	}
#endif
        for(curentry = 0; curentry < (BLKSIZE / DIR_LEN); ++curentry) {
            d = blkptr(buf, curentry * DIR_LEN, DIR_LEN);
            if(namecomp(compname, d->d_name)) {
                inum = d->d_ino;
                brelse(buf);
                i_unlock(wd);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
                sprinter_dbg[10] = 0x31;
                sprinter_dbg[11] = (uint8_t)wd->c_dev;
                sprinter_dbg[12] = (uint8_t)(wd->c_dev >> 8);
                sprinter_dbg[13] = (uint8_t)inum;
                sprinter_dbg[14] = (uint8_t)(inum >> 8);
#endif
                return i_open(wd->c_dev, inum);
            }
        }
        brelse(buf);
    }
    i_unlock(wd);
    return NULLINODE;
}


/* Srch_mt sees if the given inode is a mount point. If so it
 * dereferences it, and references and returns a pointer to the
 * root of the mounted filesystem.
 */

inoptr srch_mt(register inoptr ino)
{
    register uint_fast8_t j;
    register struct mount *m = &fs_tab[0];

    for(j=0; j < NMOUNTS; ++j){
        if(m->m_dev != NO_DEVICE &&  m->m_mntpt == ino) {
            i_deref(ino);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
            sprinter_dbg[10] = 0x32;
            sprinter_dbg[11] = (uint8_t)m->m_dev;
            sprinter_dbg[12] = (uint8_t)(m->m_dev >> 8);
            sprinter_dbg[13] = ROOTINODE;
            sprinter_dbg[14] = 0;
#endif
            return i_open(m->m_dev, ROOTINODE);
        }
        m++;
    };
    return ino;
}


/* I_open is given an inode number and a device number,
 * and makes an entry in the inode table for them, or
 * increases it reference count if it is already there.
 * An inode # of zero means a newly allocated inode.
 *
 * Once we support sleeping on bigger boxes during I/O we will need
 * a lock (superblock lock perhaps) to cover allocation of blocks and
 * inodes.
 */

inoptr i_open(register uint16_t dev, uint16_t ino)
{
    register inoptr nindex;
    register inoptr j;
    struct mount *m;
    bool isnew = false;

#ifdef CONFIG_SPRINTER_EARLY_TRACE
    {
	extern void spr_map_win0_k(void);
	spr_map_win0_k();
    }
    sprinter_dbg[10] = 0x33;
    sprinter_dbg[11] = (uint8_t)dev;
    sprinter_dbg[12] = (uint8_t)(dev >> 8);
    sprinter_dbg[13] = (uint8_t)ino;
    sprinter_dbg[14] = (uint8_t)(ino >> 8);
    sprinter_last_iopen_dev = dev;
    sprinter_last_iopen_ino = ino;
    sprinter_last_iopen_ret = 0;
    sprinter_last_iopen_bad = 0;
    sprinter_last_iopen_mode = 0;
    sprinter_last_iopen_nlink = 0;
#endif

    validchk(dev, PANIC_IOPEN);

    if(!ino){        /* ino==0 means we want a new one */
        isnew = true;
        ino = i_alloc(dev);
        if(!ino) {
            udata.u_error = ENOSPC;
            return NULLINODE;
        }
    }

    m = fs_tab_get(dev);

    /* Maybe make this DEBUG only eventually - the fs_tab_get cost
       is higher than ideal */
    if(ino < ROOTINODE || ino >= (m->m_fs.s_isize - 2) * INO_PER_BLOCK) {
        kputs("i_open: bad inode number\n");
        return NULLINODE;
    }

    nindex = NULLINODE;
    for(j = i_tab; j<i_tab + ITABSIZE; j++){
        if(!j->c_refs) // free slot?
            nindex = j;

        if(j->c_dev == dev && j->c_num == ino) {
            nindex = j;
            goto found;
        }
    }
    /* Not already in the table. */

    if(!nindex){      /* No unrefed slots in inode table */
        udata.u_error = ENFILE;
        return(NULLINODE);
    }

#ifdef CONFIG_SPRINTER_EARLY_TRACE
    {
	extern void spr_map_win0_k(void);
	spr_map_win0_k();
    }
#endif
    if (breadi(dev, ino, &nindex->c_node))
        return NULLINODE;

#ifdef CONFIG_SPRINTER_EARLY_TRACE
    {
	extern void spr_map_win0_k(void);
	/* breadi may have left WIN0 on a buffer/user page. */
	spr_map_win0_k();
    }
#endif

    nindex->c_dev = dev;
    nindex->c_num = ino;
    nindex->c_super = m - fs_tab;
    nindex->c_magic = CMAGIC;
    nindex->c_flags = (m->m_flags & MS_RDONLY) ? CRDONLY : 0;
found:
    if(isnew) {
        if(nindex->c_node.i_nlink || nindex->c_node.i_mode & F_MASK)
            goto badino;
    } else {
        if(!(nindex->c_node.i_nlink && nindex->c_node.i_mode & F_MASK))
            goto badino;
    }
    nindex->c_refs++;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_last_iopen_ret = (uint16_t)(uarg_t)nindex;
#endif
    return nindex;

badino:
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    /*
     * Do not kputs/kprintf here during bring-up: a badino hit right after
     * the first user write() nested another kputchar path while banks were
     * wrong, then RST38@00C4.  Latch only.
     */
    sprinter_last_iopen_bad = isnew ? 2 : 1;
    sprinter_last_iopen_mode = nindex->c_node.i_mode;
    sprinter_last_iopen_nlink = nindex->c_node.i_nlink;
    sprinter_bad_iopen_ptr = (uint16_t)(uarg_t)nindex;
    sprinter_bad_iopen_dev = dev;
    sprinter_bad_iopen_ino = ino;
    sprinter_bad_iopen_a0 = nindex->c_node.i_addr[0];
    sprinter_bad_iopen_a1 = nindex->c_node.i_addr[1];
    sprinter_dbg[8] = 0xBD;
    sprinter_dbg[9] = (uint8_t)dev;
    sprinter_dbg[10] = (uint8_t)ino;
    sprinter_dbg[11] = (uint8_t)(ino >> 8);
#else
    kputs("i_open: bad disk inode\n");
#endif
    return NULLINODE;
}

bool emptydir(register inoptr wd)
{
    struct direct curentry;

    i_islocked(wd);

    udata.u_offset =  2 * DIR_LEN;	/* . .. ignored */

    do
    {
        udata.u_count = DIR_LEN;
        udata.u_base  = (uint8_t *)&curentry;
        udata.u_sysio = true;
        readi(wd, 0);

        /* Read until EOF or name is found.  readi() advances udata.u_offset */
        if (*curentry.d_name)
            return false;
    } while(udata.u_done == DIR_LEN);

    return true;
}


/* Ch_link modifies or makes a new entry in the directory for the name
 * and inode pointer given. The directory is searched for oldname.  When
 * found, it is changed to newname, and it inode # is that of *nindex.
 * A oldname of "" matches a unused slot, and a nindex of NULLINODE
 * means an inode # of 0.  A return status of 0 means there was no
 * space left in the filesystem, or a non-empty oldname was not found,
 * or the user did not have write permission.
 */

bool ch_link(register inoptr wd, uint8_t *oldname, uint8_t *newname, inoptr nindex)
{
    struct direct curentry;
    register int i;

#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_chlink_stage = 1;
    sprinter_chlink_wd = (uint16_t)(uarg_t)wd;
    sprinter_chlink_nindex = (uint16_t)(uarg_t)nindex;
    sprinter_chlink_done = 0;
    sprinter_chlink_error = 0;
#endif

    i_islocked(wd);

    if (wd->c_flags & CRDONLY) {
        udata.u_error = EROFS;
        return false;
    }
    /* FIXME: for modern style permissions we should also check whether
       wd has the sticky bit set and if so require ownership or root */
    if(!(getperm(wd) & OTH_WR))
    {
        udata.u_error = EACCES;
        return false;
    }
    /* Inserting a new blank entry ? */
    if (!*newname && nindex != NULLINODE) {
        udata.u_error = EEXIST;
        return false;
    }

    /* Search the directory for the desired slot. */

    udata.u_offset = 0;

    for(;;)
    {
        udata.u_count = DIR_LEN;
        udata.u_base  =(uint8_t *)&curentry;
        udata.u_sysio = true;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
        sprinter_chlink_stage = 2;
#endif
        readi(wd, 0);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
        sprinter_chlink_stage = 3;
        sprinter_chlink_done = (uint16_t)udata.u_done;
        sprinter_chlink_error = (uint16_t)udata.u_error;
#endif

        /* Read until EOF or name is found.  readi() advances udata.u_offset */
        if(udata.u_done == 0 || namecomp(oldname, curentry.d_name))
            break;
    }

#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_chlink_stage = 4;
#endif

    if(udata.u_done == 0 && *oldname) {
        udata.u_error = ENOENT;
        return false;                  /* Entry not found */
    }

    memcpy(curentry.d_name, newname, FILENAME_LEN);
    /* FIXME: add strncpy and use for this */
    for(i = 0; i < FILENAME_LEN; ++i)
        if(curentry.d_name[i] == '\0')
            break;
    for(; i < FILENAME_LEN; ++i)
        curentry.d_name[i] = '\0';

    if(nindex)
        curentry.d_ino = nindex->c_num;
    else
        curentry.d_ino = 0;

    /* If an existing slot is being used, we must back up the file offset */
    if(udata.u_done){
        udata.u_offset -= DIR_LEN;
    }

    udata.u_count = DIR_LEN;
    udata.u_base  = (unsigned char*)&curentry;
    udata.u_sysio = true;
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_chlink_stage = 5;
#endif
    writei(wd, 0);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_chlink_stage = 6;
    sprinter_chlink_done = (uint16_t)udata.u_done;
    sprinter_chlink_error = (uint16_t)udata.u_error;
#endif

    if(udata.u_error) {
#ifdef CONFIG_SPRINTER_EARLY_TRACE
        sprinter_chlink_stage = 8;
#endif
        return false;
    }

    setftime(wd, A_TIME|M_TIME|C_TIME);     /* Sets CDIRTY */

    /* Update file length to next block */
    if(BLKOFF(wd->c_node.i_size))
        wd->c_node.i_size += BLKSIZE - BLKOFF(wd->c_node.i_size);

#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_chlink_stage = 7;
#endif
    return true; // success
}

/* Namecomp compares two strings to see if they are the same file name.
 * It stops at FILENAME_LEN chars or a null or a slash. It returns 0 for difference.
 *
 * TODO: This generates crap code on most compilers so we probably ought to
 * turn it into platform asm code.
 */
bool namecomp(uint8_t *n1, uint8_t *n2) // return true if n1 == n2
{
    uint_fast8_t n; // do we have enough variables called n?

    n = FILENAME_LEN;
    while(*n1 && *n1 != '/')
    {
        if(*n1++ != *n2++)
            return false; // mismatch
        n--;
        if(n==0)
            return true; // match
    }

    return (*n2 == '\0' || *n2 == '/');
}


/* Newfile is given a pointer to a directory and a name, and creates
 * an entry in the directory for the name, dereferences the parent,
 * and returns a pointer to the new inode.  It allocates an inode
 * number, and creates a new entry in the inode table for the new
 * file, and initializes the inode table entry for the new file.
 * The new file will have one reference, and 0 links to it.
 * Better make sure there isn't already an entry with the same name.
 *
 * Returns the new inode locked so nobody can access it before ready. We need
 * to think hard about newfile taking a callback to fix up the ino struct so
 * it's cleaner ???
 */

inoptr newfile(register inoptr pino, uint8_t *name)
{
    register inoptr nindex;
    register uint_fast8_t j;

    /* No parent? */
    if (!pino) {
        udata.u_error = ENXIO;
        goto nogood;
    }

    /* We check getperm before CRDONLY because if you reverse these two
       it breaks gcc 68hc11 3.4 */
    if (!(getperm(pino) & OTH_WR)) {
        udata.u_error = EPERM;
        goto nogood;
    }

    /* First see if parent is writeable */
    if (pino->c_flags & CRDONLY) {
        udata.u_error = EROFS;
        goto nogood;
    }

 #ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_dbg[10] = 0x34;
    sprinter_dbg[11] = (uint8_t)pino->c_dev;
    sprinter_dbg[12] = (uint8_t)(pino->c_dev >> 8);
    sprinter_dbg[13] = 0;
    sprinter_dbg[14] = 0;
#endif
    if (!(nindex = i_open(pino->c_dev, 0))) {
        udata.u_error = ENFILE;
        goto nogood;
    }

#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_last_newfile_pino = (uint16_t)(uarg_t)pino;
    sprinter_last_newfile_nindex_in = (uint16_t)(uarg_t)nindex;
#endif

    i_lock(pino);	/* Lock in tree order */
    i_lock(nindex);
    /* This does not implement BSD style "sticky" groups */
    nindex->c_node.i_uid = udata.u_euid;
    nindex->c_node.i_gid = udata.u_egid;

    nindex->c_node.i_mode = F_REG;   /* For the time being */
    nindex->c_node.i_nlink = 1;
    nindex->c_node.i_size = 0;
    for (j = 0; j < 20; j++) {
        nindex->c_node.i_addr[j] = 0;
    }
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_last_newfile_nindex_prewr = (uint16_t)(uarg_t)nindex;
#endif
    WR_INODE(1, nindex);
    if (!ch_link(pino, (uint8_t *)"", name, nindex)) {
        i_deref(nindex);
	/* ch_link sets udata.u_error */
        goto nogood;
    }
    i_unlock_deref(pino);
    return nindex;

nogood:
    i_unlock_deref(pino);
    return NULLINODE;
}


/* Check the given device number, and return its address in the mount
 * table.  Also time-stamp the superblock of dev, and mark it modified.
 * Used when freeing and allocating blocks and inodes.
 */

fsptr getdev(uint16_t dev)
{
    register struct mount *mnt;
    time_t t;

    mnt = fs_tab_get(dev);

    if (!mnt || mnt->m_fs.s_mounted == 0) {
#ifdef CONFIG_SPRINTER_EARLY_TRACE
        spr_gd_dev = dev;
        spr_gd_mnt = (uint16_t)(uarg_t)mnt;
        spr_gd_state = (uint16_t)udata.u_callno |
            ((uint16_t)udata.u_insys << 8);
#endif
        panic(PANIC_GD_BAD);
        /* Return needed to persuade SDCC all is ok */
        return NULL;
    }
    if (!(mnt->m_flags & MS_RDONLY)) {
        rdtime(&t);
        mnt->m_fs.s_time = t.low;
        mnt->m_fs.s_timeh = t.high;
        mnt->m_fs.s_fmod = FMOD_DIRTY;
    }
    return &mnt->m_fs;
}


/* Returns true if the magic number of a superblock is corrupt. */

bool inline baddev(fsptr dev)
{
    return(dev->s_mounted != SMOUNTED);
}


/* I_alloc finds an unused inode number, and returns it, or 0
 * if there are no more inodes available.
 *
 * This will need to happen under the superblock lock once we do sleeping
 */

uint16_t i_alloc(uint16_t devno)
{
    staticfast fsptr dev;
    staticfast blkno_t blk;
    register struct dinode *di;
    staticfast uint16_t j;
    register struct blkbuf *buf;
    uint16_t k;
    unsigned ino;

    if(baddev(dev = getdev(devno)))
        goto corrupt;

tryagain:
    if(dev->s_ninode) {
#ifdef CONFIG_SPRINTER_EARLY_TRACE
        if(!(dev->s_tinode)) {
            dev->s_ninode = 0;
            goto tryagain;
        }
#else
        if(!(dev->s_tinode))
            goto corrupt;
#endif
        ino = dev->s_inode[--dev->s_ninode];
        if(ino < 2 || ino >=(dev->s_isize-2)*8)
            goto corrupt;
        --dev->s_tinode;
        return(ino);
    }
    /* We must scan the inodes, and fill up the table */

    sync();           /* Make on-disk inodes consistent */
    k = 0;
    for(blk = 2; blk < dev->s_isize; blk++) {
        buf = bread(devno, blk, 0);
        if (buf == NULL)
            goto corrupt;
        for(j=0; j < INO_PER_BLOCK; j++) {
            /* Optimisation: add offsetof and use that to reduce blkptr range */
            di = blkptr(buf, sizeof(struct dinode) * j, sizeof(struct dinode));
            if(!(di->i_mode || di->i_nlink))
                dev->s_inode[k++] = INO_PER_BLOCK * (blk - 2) + j;
            if(k == FILESYS_TABSIZE) {
                brelse(buf);
                goto done;
            }
        }
        brelse(buf);
    }

done:
    if(!k) {
#ifndef CONFIG_SPRINTER_EARLY_TRACE
        if(dev->s_tinode)
            goto corrupt;
#endif
        udata.u_error = ENOSPC;
        return(0);
    }
    dev->s_ninode = k;
    goto tryagain;

corrupt:
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    spr_iac_devptr = (uint16_t)(uarg_t)dev;
    spr_iac_ninode = dev->s_ninode;
    spr_iac_tinode = dev->s_tinode;
    spr_iac_isize = dev->s_isize;
    spr_iac_mounted = dev->s_mounted;
    if (dev->s_isize > 2 && dev->s_isize < 4096) {
        dev->s_ninode = 0;
        if (dev->s_tinode == 0)
            dev->s_tinode = 1;
        goto tryagain;
    }
#endif
    kputs("i_alloc: corrupt superblock\n");
    dev->s_mounted = 1;
    udata.u_error = ENOSPC;
    return(0);
}


/* I_free is given a device and inode number, and frees the inode.
 * It is assumed that there are no references to the inode in the
 * inode table or in the filesystem.
 *
 * This will need to happen under the superblock lock once we do sleeping
 */

void i_free(uint16_t devno, uint16_t ino)
{
    register fsptr dev;

    if(baddev(dev = getdev(devno)))
        return;

    if(ino < 2 || ino >=(dev->s_isize-2)*8)
        panic(PANIC_IFREE_BADI);

    ++dev->s_tinode;
    if(dev->s_ninode < FILESYS_TABSIZE)
        dev->s_inode[dev->s_ninode++] = ino;
}


/* Blk_alloc is given a device number, and allocates an unused block
 * from it. A returned block number of zero means no more blocks.
 *
 * This will need to happen under the superblock lock once we do sleeping
 */

blkno_t blk_alloc(uint16_t devno)
{
    register fsptr dev;
    register struct blkbuf *buf;
    blkno_t newno;

    if(baddev(dev = getdev(devno)))
        goto corrupt2;

    if(dev->s_nfree <= 0 || dev->s_nfree > FILESYS_TABSIZE)
        goto corrupt;

    newno = dev->s_free[--dev->s_nfree];
    if(!newno)
    {
        if(dev->s_tfree != 0)
            goto corrupt;
        udata.u_error = ENOSPC;
        ++dev->s_nfree;
        return(0);
    }

    /* See if we must refill the s_free array */

    if(!dev->s_nfree)
    {
        buf = bread(devno, newno, 0);
        if (buf == NULL)
            goto corrupt;
        blktok(&dev->s_nfree, buf, 0,
            sizeof(int) + FILESYS_TABSIZE * sizeof(blkno_t));
        /* This assumes no padding: this is an UZI era assumption */
        brelse(buf);
    }

    validblk(devno, newno);

    if(!dev->s_tfree)
        goto corrupt;
    --dev->s_tfree;

   /*
    * FIXME: When we implement the rest of the bigger block size fs support
    * this routine is responsible for zeroing the entire extent not just the
    * BLKSIZE byte block
    */
    /* Zero out the new block */
    buf = bread(devno, newno, 2);
    if (buf == NULL)
        goto corrupt;
    blkzero(buf);
    bawrite(buf);
    return newno;

corrupt:
    kputs("blk_alloc: corrupt\n");
    dev->s_mounted = 1;
corrupt2:
    udata.u_error = ENOSPC;
    return 0;
}


/* Blk_free is given a device number and a block number,
 * and frees the block.
 *
 * This will need to happen under the superblock lock once we do sleeping
 */

void blk_free(uint16_t devno, blkno_t blk)
{
    fsptr dev;
    struct blkbuf *buf;

    if(!blk)
        return;

    if(baddev(dev = getdev(devno)))
        return;

    validblk(devno, blk);

    if(dev->s_nfree == FILESYS_TABSIZE) {
        buf = bread(devno, blk, 1);
        if (buf) {
            /* nfree must directly preceed the blocks and without padding. That's
               the assumption UZI always had */
            blkfromk(&dev->s_nfree, buf, 0, sizeof(int) + 50 * sizeof(blkno_t));
            bawrite(buf);
            dev->s_nfree = 0;
        } else
            dev->s_mounted = 1;
    }

    ++dev->s_tfree;
    dev->s_free[(dev->s_nfree)++] = blk;
}


/* Oft_alloc and oft_deref allocate and dereference(and possibly free)
 * entries in the open file table.
 */

int_fast8_t oft_alloc(void)
{
    register uint_fast8_t j;

    for(j=0; j < OFTSIZE ; ++j) {
        if(of_tab[j].o_refs == 0) {
            of_tab[j].o_refs = 1;
            of_tab[j].o_inode = NULLINODE;
            return j;
        }
    }
    udata.u_error = ENFILE;
    return -1;
}

/*
 *	To minimise storage we don't track exclusive locks explicitly. We know
 *	that if we are dropping an exclusive lock then we must be the owner,
 *	and if we are dropping a lock that is not exclusive we must own one of
 *	the non exclusive locks.
 */
void deflock(register struct oft *ofptr)
{
    register inoptr i = ofptr->o_inode;
    register uint_fast8_t c = i->c_flags & CFLOCK;

    if (ofptr->o_access & O_FLOCK) {
        if (c == CFLEX)
            c = 0;
        else
            c--;
        i->c_flags = (i->c_flags & ~CFLOCK) | c;
        wakeup(&i->c_flags);
    }
}

/*
 *	Drop a reference in the open file table. If this is the last reference
 *	from a user file table then drop any file locks, dereference the inode
 *	and mark empty
 */
void oft_deref(uint_fast8_t of)
{
    register struct oft *ofptr;

    ofptr = of_tab + of;
    if(!(--ofptr->o_refs) && ofptr->o_inode) {
        deflock(ofptr);
        i_deref(ofptr->o_inode);
        ofptr->o_inode = NULLINODE;
    }
}


/* Uf_alloc finds an unused slot in the user file table.*/

int_fast8_t uf_alloc_n(uint_fast8_t base)
{
    register uint_fast8_t j;

    for(j=base; j < UFTSIZE ; ++j) {
        if(udata.u_files[j] == NO_FILE) {
            return j;
        }
    }
    udata.u_error = EMFILE;
    return -1;
}


int_fast8_t uf_alloc(void)
{
    return uf_alloc_n(0);
}


/* I_deref decreases the reference count of an inode, and frees it from
 * the table if there are no more references to it.  If it also has no
 * links, the inode itself and its blocks(if not a device) is freed.
 */

void i_deref(register inoptr ino)
{
    uint_fast8_t mode;

    if (!ino) {
#ifdef CONFIG_SPRINTER_EARLY_TRACE
        sprinter_ideref_null_count++;
        sprinter_ideref_null_sys = (uint16_t)udata.u_callno |
            ((uint16_t)udata.u_insys << 8);
#endif
        return;
    }

#ifdef CONFIG_SPRINTER_EARLY_TRACE
    {
	extern void spr_map_win0_k(void);
	/*
	 * Observed: i_deref((inoptr)1) and other non-i_tab pointers during
	 * PID1 n_open → corrupt inode.  Reject anything outside i_tab so a
	 * stale WIN0 walk pointer cannot hard-stop bring-up.
	 */
	spr_map_win0_k();
	if (!sprinter_inode_ptr_valid(ino)) {
		sprinter_ideref_null_count++;
		sprinter_ideref_null_sys = (uint16_t)udata.u_callno |
			((uint16_t)udata.u_insys << 8);
		sprinter_last_ideref_in = (uint16_t)(uarg_t)ino;
		return;
	}
    }
#endif

#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_last_ideref_in = (uint16_t)(uarg_t)ino;
    sprinter_last_ideref_meta = (uint16_t)udata.u_callno |
        ((uint16_t)udata.u_insys << 8);
#endif

    mode = getmode(ino);
    MAGIC_CHECK(2, ino);

    if(!ino->c_refs) {
#ifdef CONFIG_SPRINTER_EARLY_TRACE
        uint16_t pid = 0;

        if (udata.u_ptab)
            pid = udata.u_ptab->p_pid;
        kprintf("i_deref0 dev=%x num=%x nlink=%x mode=%x pid=%x sys=%x in=%x\n",
            ino->c_dev, ino->c_num,
            ino->c_node.i_nlink, ino->c_node.i_mode,
            pid, udata.u_callno, udata.u_insys);
#endif
        panic(PANIC_INODE_FREED);
    }

    if (mode == MODE_R(F_PIPE))
        wakeup((uint8_t *)ino);

    /* If the inode has no links and no refs, it must have
       its blocks freed. */

    {
        if(!(--ino->c_refs || ino->c_node.i_nlink))
        /*
           SN (mcy)
           */
            if (mode == MODE_R(F_REG) || mode == MODE_R(F_DIR) || mode == MODE_R(F_PIPE))
                f_trunc(ino);
    }

#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_last_ideref_post = (uint16_t)(uarg_t)ino;
#endif

    /* If the inode was modified, we must write it to disk. */
    if(!(ino->c_refs) && (ino->c_flags & CDIRTY))
    {
#ifdef CONFIG_SPRINTER_EARLY_TRACE
        sprinter_last_ideref_wr = (uint16_t)(uarg_t)ino;
#endif
        if(!(ino->c_node.i_nlink))
        {
            ino->c_node.i_mode = 0;
            i_free(ino->c_dev, ino->c_num);
        }
        WR_INODE(2, ino);
    }
}

void corrupt_fs(uint16_t devno)
{
    struct mount *mnt = fs_tab_get(devno);
    mnt->m_fs.s_mounted = 1;
    kputs("filesystem corrupt.\n");
}
/* Wr_inode writes out the given inode in the inode table out to disk,
 * and resets its dirty bit.
 */

void wr_inode(register inoptr ino)
{
/*    struct blkbuf *buf;
    blkno_t blkno;
*/
    MAGIC_CHECK(3, ino);

    if (bwritei(ino))
        corrupt_fs(ino->c_dev);
    else
        ino->c_flags &= ~CDIRTY;
}


/* isdevice(ino) returns true if ino points to a device */
bool isdevice(inoptr ino)
{
    return !!(ino->c_node.i_mode & F_CDEV);
}


/* This returns the device number of an inode representing a device */
uint16_t devnum(inoptr ino)
{
    return (uint16_t)ino->c_node.i_addr[0];
}


/*
 *	f_trunc_blocks frees all the blocks associated with the file, if it
 *	is a disk file. The blocks are freed in reverse order. This is
 *	very important so that they end up on the freelist in the
 *	order we want to allocate them.
 */
int f_trunc_blocks(register inoptr ino, uint16_t nblock)
{
    register uint16_t dev;
    register int_fast8_t j;
    uint16_t map1 = 0;
    uint16_t map2 = 0;

    if (ino->c_flags & CRDONLY) {
        udata.u_error = EROFS;
        return -1;
    }

    /* Block offsets are
        0-17 direct
        18 256 blocks (18-273)
        19 256 * 256 blocks (274-65810)

        (We only allow 65535 block offset in order to keep a lot of stuff
         uint16_t - FIXME to fix u writei())

        We don't support triple indirect blocks.

        When we are called nblock is the number of blocks that will
        remain in the file when we truncate it

        We set map1 to the number of blocks we must purge for single
        indirect. We set map2 for the number of blocks we must purge
        of double indirect.

        freeblk frees full subblocks above the block passed, and then frees
        blocks >> 8 on the last iteration to partially clear the last set
    */

    if (nblock > 17 && nblock < 274)
        map1 = (nblock - 18) << 8;
    else if (nblock > 273)
        map2 = nblock - 273;
    dev = ino->c_dev;

    /* FIXME: ideally zero the indirect pointers before we write the
       free lists */

    /* First deallocate the double indirect blocks */
    freeblk(dev, ino->c_node.i_addr[19], 2, map2);
    if (map2)
        ino->c_node.i_addr[19] = 0;

    /* Also deallocate the indirect blocks */
    freeblk(dev, ino->c_node.i_addr[18], 1, map1);
    if (map1 == 0 && map2 == 0)	/* ???? should this just be if map1 */
        ino->c_node.i_addr[18] = 0;

    /* Finally, free the direct blocks */
    /* FIXME: use pointers for efficiency ? */
    /* At this point nblock is definitely < 0x8000 so forcing a signed
       compare does what we want */
    for(j = 17; j >= (int)nblock; --j) {
        freeblk(dev, ino->c_node.i_addr[j], 0, 0);
        ino->c_node.i_addr[j] = 0;
    }

    ino->c_flags |= CDIRTY;
    return 0;
}


/* Truncate a file back to nothing using f_trunc_blocks and then write
   the inode size as 0 */
int f_trunc(regptr inoptr ino)
{
    /* Is it worth checking size already 0 ? */
    if (f_trunc_blocks(ino, 0))
        return -1;
     ino->c_node.i_size = 0;
     return 0;
}

/* Companion function to f_trunc().

   This is the one case where we can't hide the difference between an internal
   and external buffer cache cleanly. The external one has a somewhat higher
   overhead (we could mitigate it by batching perhaps) and also size.

   This is annoying and it would be nice one day to find a clean solution */

#ifdef CONFIG_BLKBUF_EXTERNAL
void freeblk(uint16_t dev, blkno_t blk, uint_fast8_t level, uint16_t nblock)
{
    struct blkbuf *buf;
    regptr blkno_t *bn;
    int16_t j;
    int_fast8_t nblock1 = nblock >> 8;

    if(!blk)
        return;

    if(level){
        buf = bread(dev, blk, 0);
        if (buf == NULL) {
            corrupt_fs(dev);
            return;
        }
        for(j = BLKSIZE / 2 - 1; j >= nblock1; --j) {
            uint8_t b = 0;
            if (j == nblock1)
                b = nblock & 0xFF;
            blktok(&bn, buf, j * sizeof(blkno_t), sizeof(blkno_t));
            freeblk(dev, bn[j], level - 1, b);
        }
        brelse(buf);
    }
#ifdef CONFIG_TRIM
    d_ioctl(dev, HDIO_TRIM, (void*)&blk);
#endif
    blk_free(dev, blk);
}

#else

void freeblk(uint16_t dev, blkno_t blk, uint_fast8_t level, uint16_t nblock)
{
    struct blkbuf *buf;
    regptr blkno_t *bn;
    int16_t j;
    int_fast8_t nblock1 = nblock >> 8;

    if(!blk)
        return;

    if(level){
        buf = bread(dev, blk, 0);
        if (buf == NULL) {
            corrupt_fs(dev);
            return;
        }
        bn = blkptr(buf, 0, BLKSIZE);
        for(j = BLKSIZE / 2 - 1; j >= 0; --j) {
            /* When we hit nblock1 we are doing the final partial clear, so
               only tell the child freeblk to do a partial clear */
            uint_fast8_t b = 0;
            if (j == nblock1)
                b = nblock & 0xFF;
            freeblk(dev, bn[j], level-1, b);
        }
        brelse(buf);
    }
#ifdef CONFIG_TRIM
    d_ioctl(dev, HDIO_TRIM, (void*)&blk);
#endif
    blk_free(dev, blk);
}
#endif

/* Validblk panics if the given block number is not a valid
 *  data block for the given device.
 */
void validblk(uint16_t dev, register blkno_t num)
{
    register struct mount *mnt;

    mnt = fs_tab_get(dev);

    if(mnt == NULL || mnt->m_fs.s_mounted == 0) {
        panic(PANIC_VALIDBLK_NM);
        return;
    }

    if(num < mnt->m_fs.s_isize || num >= mnt->m_fs.s_fsize)
        panic(PANIC_VALIDBLK_INV);
}


/* This returns the inode pointer associated with a user's file
 * descriptor, checking for valid data structures.
 */
inoptr getinode(uint_fast8_t uindex)
{
    register uint_fast8_t oftindex;
    register inoptr inoindex;

    if(uindex >= UFTSIZE || udata.u_files[uindex] == NO_FILE) {
        udata.u_error = EBADF;
        return NULLINODE;
    }

    oftindex = udata.u_files[uindex];

    if(oftindex >= OFTSIZE || oftindex == NO_FILE) {
#ifdef CONFIG_SPRINTER_EARLY_TRACE
        spr_gfr = 1;
        spr_gfu = uindex;
        spr_gfo = oftindex;
        spr_gffr = 0xFF;
        spr_gffa = 0xFF;
        spr_gfin = 0;
        spr_gfs = (uint16_t)udata.u_callno |
            ((uint16_t)udata.u_insys << 8);
        udata.u_error = EBADF;
        return NULLINODE;
#else
        panic(PANIC_GETINO_BADT);
#endif
    }

    inoindex = of_tab[oftindex].o_inode;

    if(inoindex < i_tab || inoindex >= i_tab+ITABSIZE) {
#ifdef CONFIG_SPRINTER_EARLY_TRACE
        /*
         * Bounce/patch can smash of_tab[].o_inode while i_tab[0] (tty)
         * remains valid.  For stdio fds, reattach to the console node.
         */
        if (uindex < 3 && i_tab[0].c_magic == CMAGIC) {
            of_tab[oftindex].o_inode = i_tab;
            of_tab[oftindex].o_access = O_RDWR;
            if (!of_tab[oftindex].o_refs)
                of_tab[oftindex].o_refs = 1;
            inoindex = i_tab;
            sprinter_dbg[15] = 0x72;
        } else {
            spr_gfr = 2;
            spr_gfu = uindex;
            spr_gfo = oftindex;
            spr_gffr = of_tab[oftindex].o_refs;
            spr_gffa = of_tab[oftindex].o_access;
            spr_gfin = (uint16_t)(uarg_t)inoindex;
            spr_gfs = (uint16_t)udata.u_callno |
                ((uint16_t)udata.u_insys << 8);
            udata.u_error = EBADF;
            return NULLINODE;
        }
#else
        panic(PANIC_GETINO_OFT);
#endif
    }

    MAGIC_CHECK(4, inoindex);
    return(inoindex);
}


/* Super returns true if we are the superuser */
bool super(void)
{
    return(udata.u_euid == 0);
}

/* Similar but this helper sets the error code */
bool esuper(void)
{
    if (udata.u_euid) {
        udata.u_error = EPERM;
        return -1;
    }
    return 0;
}

/* Getperm looks at the given inode and the effective user/group ids,
 * and returns the effective permissions in the low-order 3 bits.
 */
uint8_t getperm(register inoptr ino)
{
    int mode;

    if(super())
        return(07);

    mode = ino->c_node.i_mode;
    if(ino->c_node.i_uid == udata.u_euid)
        mode >>= 6;
    else if(ino->c_node.i_gid == udata.u_egid)
        mode >>= 3;
#ifdef CONFIG_LEVEL_2
    /* BSD process groups */
    else if (in_group(ino->c_node.i_gid))
        mode >>= 3;
#endif

    return(mode & 07);
}


/* This sets the times of the given inode, according to the flags. */
void setftime(register inoptr ino, register uint_fast8_t flag)
{
    if (ino->c_flags & CRDONLY)
        return;

    /* If only ATIME is due an update then skip it for a noatime fs */
    if (flag == A_TIME && fs_tab[ino->c_super].m_flags & MS_NOATIME)
        return;

    ino->c_flags |= CDIRTY;

    if(flag & A_TIME)
        rdtime32(&(ino->c_node.i_atime));
    if(flag & M_TIME)
        rdtime32(&(ino->c_node.i_mtime));
    if(flag & C_TIME)
        rdtime32(&(ino->c_node.i_ctime));
}

uint8_t getmode(inoptr ino)
{
    /* Shifting by 9 (past permissions) might be more logical but
       8 happens to be cheap */
    return (ino->c_node.i_mode & F_MASK) >> 8;
}

static struct mount *newfstab(void)
{
    register struct mount *m = fs_tab;
    register uint_fast8_t i;
    for (i = 0; i < NMOUNTS; i++) {
        if (m->m_dev == NO_DEVICE)
            return m;
        m++;
    }
    return NULL;
}

struct mount *fs_tab_get(uint16_t dev)
{
    register struct mount *m = fs_tab;
    register uint_fast8_t i;
    for (i = 0; i < NMOUNTS; i++) {
        if (m->m_dev == dev)
            return m;
        m++;
    }
    return NULL;
}

/* Fmount places the given device in the mount table with mount point info. */
struct mount *fmount(uint16_t dev, register inoptr ino, uint16_t flags)
{
    register struct mount *m;
    register struct filesys *fp;
    register bufptr buf;

    FM_TRACE(0x50);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_dbg[15] = 0xF3;
    sprinter_dbg[16] = (uint8_t)dev;
    sprinter_dbg[17] = (uint8_t)(dev >> 8);
    sprinter_dbg[18] = (uint8_t)flags;
#endif

    if(d_open(dev, 0) != 0) {
        FM_TRACE(0x51);
        FM_TRACE((uint8_t)udata.u_error);
        FM_TRACE(0x57);
    }
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_dbg[15] = 0xF4;
    sprinter_dbg[16] = (uint8_t)udata.u_error;
#endif
    FM_TRACE(0x52);
    udata.u_error = 0;

    FM_TRACE(0x5A);
    FM_TRACE((uint8_t)dev);
    FM_TRACE(0x5E);
    FM_TRACE((uint8_t)(dev >> 8));

    m = newfstab();
    FM_TRACE(0x5B);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_dbg[15] = 0xF5;
    sprinter_dbg[16] = (uint8_t)(uarg_t)m;
    sprinter_dbg[17] = (uint8_t)(((uarg_t)m) >> 8);
#endif
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_bootmark('J');
#endif
    if (m == NULL) {
        udata.u_error = EMFILE;
        FM_TRACE(0x53);
        return NULL;	/* Table is full */
    }

    fp = &m->m_fs;

    /* Get the buffer with the superblock (block 1) */
    FM_TRACE(0x5C);
    buf = bread(dev, 1, 0);
    FM_TRACE(0x5D);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_dbg[15] = 0xF6;
    sprinter_dbg[16] = (uint8_t)(uarg_t)buf;
    sprinter_dbg[17] = (uint8_t)(((uarg_t)buf) >> 8);
    sprinter_dbg[18] = (uint8_t)udata.u_error;
#endif
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_bootmark('K');
#endif
    if (buf == NULL) {
        FM_TRACE(0x54);
        FM_TRACE((uint8_t)udata.u_error);
        return NULL;
    }
    FM_TRACE(0x5F);
    FM_TRACE(buf->__bf_data[0]);
    FM_TRACE(buf->__bf_data[1]);
    FM_TRACE(buf->__bf_data[2]);
    FM_TRACE(buf->__bf_data[3]);
    FM_TRACE(buf->__bf_data[4]);
    FM_TRACE(buf->__bf_data[5]);
    FM_TRACE(buf->__bf_data[6]);
    FM_TRACE(buf->__bf_data[7]);
    blktok(fp, buf, 0, sizeof(struct filesys));
    brelse(buf);

    FM_TRACE(0x6A);
    FM_TRACE(((uint8_t *)fp)[0]);
    FM_TRACE(((uint8_t *)fp)[1]);
    FM_TRACE(((uint8_t *)fp)[2]);
    FM_TRACE(((uint8_t *)fp)[3]);
    FM_TRACE(((uint8_t *)fp)[4]);
    FM_TRACE(((uint8_t *)fp)[5]);
    FM_TRACE(((uint8_t *)fp)[6]);
    FM_TRACE(((uint8_t *)fp)[7]);

    FM_TRACE(0x57);
    FM_TRACE((uint8_t)fp->s_mounted);
    FM_TRACE((uint8_t)(fp->s_mounted >> 8));
    FM_TRACE(0x58);
    FM_TRACE((uint8_t)fp->s_isize);
    FM_TRACE((uint8_t)(fp->s_isize >> 8));
    FM_TRACE(0x59);
    FM_TRACE((uint8_t)fp->s_fsize);
    FM_TRACE((uint8_t)(fp->s_fsize >> 8));
    FM_TRACE(0x5A);
    FM_TRACE((uint8_t)fp->s_shift);

#ifdef DEBUG
    kprintf("fp->s_mounted=0x%x, fp->s_isize=0x%x, fp->s_fsize=0x%x\n",
    fp->s_mounted, fp->s_isize, fp->s_fsize);
#endif

#ifdef CONFIG_SPRINTER_EARLY_TRACE
    /* Show the magic and the sanity window on screen so we can see
     * exactly why the validation below may fail on Sprinter. On a good
     * 512-byte superblock we expect: mnt=31C6 isz=0100 fsz=FFFF shift=00 */
    sprinter_bootmark('m');
    sprinter_boothex((uint8_t)(fp->s_mounted >> 8));
    sprinter_boothex((uint8_t)fp->s_mounted);
    sprinter_bootmark('i');
    sprinter_boothex((uint8_t)(fp->s_isize >> 8));
    sprinter_boothex((uint8_t)fp->s_isize);
    sprinter_bootmark('f');
    sprinter_boothex((uint8_t)(fp->s_fsize >> 8));
    sprinter_boothex((uint8_t)fp->s_fsize);
    sprinter_bootmark('s');
    sprinter_boothex(fp->s_shift);
#endif
    /* See if there really is a filesystem on the device */
    if(fp->s_mounted != SMOUNTED  ||  fp->s_isize >= fp->s_fsize ||
        fp->s_shift > FS_MAX_SHIFT) {
        udata.u_error = EINVAL;
        FM_TRACE(0x55);
        return NULL;
    }
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_bootmark('L');
#endif

    if (fp->s_fmod == FMOD_DIRTY) {
        kputs("warning: mounting dirty file system, forcing r/o.\n");
        flags |= MS_RDONLY;
    }
    if (!(flags & MS_RDONLY))
        /* Dirty - and will write dirty mark back to media */
        fp->s_fmod = FMOD_DIRTY;
    else	/* Clean in memory, don't write it back to media */
        fp->s_fmod = FMOD_CLEAN;
    m->m_mntpt = ino;
    if(ino)
        ++ino->c_refs;
    m->m_flags = flags;
    /* Makes our entry findable */
    m->m_dev = dev;

    /* Mark the filesystem dirty on disk */
    sync();

    FM_TRACE(0x56);
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    sprinter_bootmark('M');
#endif

    return m;
}


void magic(inoptr ino)
{
#ifdef CONFIG_SPRINTER_EARLY_TRACE
    {
	extern void spr_map_win0_k(void);
	spr_map_win0_k();
    }
#endif
    if(ino->c_magic != CMAGIC) {
#ifdef CONFIG_SPRINTER_EARLY_TRACE
        /*
         * V7 sh bounce/patch has been seen to zero i_tab[0] (console
         * tty) while of_tab[0..2] still reference it.  getinode then
         * panics on ioctl(1, TCGETA).  Rebuild a minimal tty1 node so
         * userland can continue; other corruptions still panic.
         * Temporary bring-up only (CONFIG_SPRINTER_EARLY_TRACE).
         */
        if (sprinter_magic_site == 4 && ino == i_tab) {
            ino->c_magic = CMAGIC;
            ino->c_dev = root_dev;
            ino->c_num = 0;
            ino->c_node.i_mode = F_CDEV | 0666;
            ino->c_node.i_nlink = 1;
            ino->c_node.i_uid = 0;
            ino->c_node.i_gid = 0;
            ino->c_node.i_size = 0;
            ino->c_node.i_addr[0] = 0x0201; /* major 2 minor 1 */
            ino->c_flags = 0;
            ino->c_readers = 0;
            ino->c_writers = 0;
            if (!ino->c_refs)
                ino->c_refs = 1;
            sprinter_dbg[15] = 0x71;
            return;
        }
        {
        uint_fast8_t slot = 0xFF;
        uint16_t pid = 0;

        if (sprinter_inode_ptr_valid(ino))
            slot = (uint_fast8_t)(ino - i_tab);
        if (udata.u_ptab)
            pid = udata.u_ptab->p_pid;
        kprintf("magic0 ptr=%x slot=%x site=%x mg=%x dev=%x num=%x refs=%x fl=%x pid=%x sys=%x in=%x\n",
            (uint16_t)(uarg_t)ino, slot, sprinter_magic_site,
            ino->c_magic, ino->c_dev, ino->c_num,
            ino->c_refs, ino->c_flags,
            pid, udata.u_callno, udata.u_insys);
        kprintf("nopen st=%x wd=%x ni=%x n0=%x ch=%x iodev=%x ino=%x ret=%x bad=%x md=%x nl=%x\n",
            sprinter_last_nopen_stage, sprinter_last_nopen_wd,
            sprinter_last_nopen_ninode, sprinter_last_nopen_name0,
            sprinter_last_nopen_char, sprinter_last_iopen_dev,
            sprinter_last_iopen_ino, sprinter_last_iopen_ret,
            sprinter_last_iopen_bad, sprinter_last_iopen_mode,
            sprinter_last_iopen_nlink);
        kprintf("magic0 roots ur=%x uc=%x gr=%x\n",
            (uint16_t)(uarg_t)udata.u_root,
            (uint16_t)(uarg_t)udata.u_cwd,
            (uint16_t)(uarg_t)root);
        kprintf("magic0 raw=%x %x %x %x\n",
            ((uint8_t *)ino)[0], ((uint8_t *)ino)[1],
            ((uint8_t *)ino)[2], ((uint8_t *)ino)[3]);
        }
#endif
        panic(PANIC_CORRUPTI);
    }
}

/* This is a helper function used by _unlink and _rename; it doesn't really
 * belong here, but needs to be in common code as it's used from two different
 * syscall banks.
 *
 * FIXME: this could be more efficient if we remembered which directory offset
 * we found the node at lookup time
 */
arg_t unlinki(inoptr ino, inoptr pino, uint8_t *fname)
{
	if (getmode(ino) == MODE_R(F_DIR)) {
		udata.u_error = EISDIR;
		return -1;
	}

	/* Remove the directory entry (ch_link checks perms) */
	if (!ch_link(pino, fname, (uint8_t *)"", NULLINODE))
		return -1;

	/* Decrease the link count of the inode */
	if (!(ino->c_node.i_nlink--)) {
		ino->c_node.i_nlink += 2;
		kprintf("_unlink: bad nlink\n");
	}
	setftime(ino, C_TIME);
	return (0);
}
