        .module commonmem

        ; std-commonmem.s has no `.area` directive: it continues in
        ; whichever area was active after crt0.rel was linked (which
        ; is `_CODE`).  That placed _ub/_udata/kstack/istack at ~0x0191
        ; in WIN0 = kernel code page 0x48.  Any process with u_page[0]
        ; still zero (e.g. PID1 during early bring-up before _execve
        ; runs pagemap_prepare) gets WIN0 substituted back to 0x48 by
        ; map_proc_2, so writes to "user" addresses 0x01xx-0x02xx end
        ; up inside _udata and corrupt the u_block -- including the
        ; `/init` string add_argument tries to stage for exec.
        ; Place the common block in _COMMONMEM (WIN3, page 0x4B) so it
        ; lives in always-mapped common memory and never overlaps the
        ; user-window physical pages.
        .area _COMMONMEM

        .include "../../cpu-z80/std-commonmem.s"
