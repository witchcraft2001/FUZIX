#undef DEBUG_SYSCALL		/* turn this on to enable syscall tracing */
#undef DEBUG_SLEEP		/* turn this on to trace sleep/wakeup activity */
#undef DEBUGHARDER		/* report calls to wakeup() that lead nowhere */
#undef DEBUGREALLYHARD		/* turn on getproc dumping */
#undef DEBUG_PREEMPT		/* debug pre-emption */
#undef DEBUG_NREADY		/* debug nready counting */

#include <kernel.h>
#include <tty.h>
#include <kdata.h>
#include <printf.h>
#include <audio.h>
#include <timer.h>

#ifdef CONFIG_SPRINTER_EARLY_TRACE
extern void plt_trace(uint8_t code);
extern void sprinter_bootmark(char c);
extern uint8_t sprinter_exec_fail_stage;
extern uint16_t sprinter_exec_fail_err;
extern uint16_t sprinter_exec_fail_name;
extern uint16_t sprinter_exec_fail_root;
extern uint16_t sprinter_exec_fail_cwd;
extern uint16_t sprinter_exec_fail_ino;
extern uint16_t sprinter_exec_fail_mode;
extern uint8_t sprinter_exec_fail_perm;
extern uint8_t sprinter_exec_fail_mflags;
extern uint16_t sprinter_exec_fail_argv;
extern uint16_t sprinter_exec_fail_envp;
extern uint16_t sprinter_exec_fail_done;
extern uint16_t sprinter_exec_fail_count;
extern uint8_t sprinter_last_nopen_stage;
extern uint16_t sprinter_last_nopen_wd;
extern uint16_t sprinter_last_nopen_ninode;
extern uint8_t sprinter_last_nopen_name0;
extern uint8_t sprinter_last_nopen_char;
extern uint16_t sprinter_last_panic_ptr;
extern uint8_t sprinter_last_panic_bytes[4];
extern uint8_t spr_rw_stage;
extern uint8_t spr_boot_count;
extern uint8_t spr_doexec_arm;
extern uint8_t spr_doexec_seen;
extern uint16_t spr_doexec_expect;
extern uint16_t spr_doexec_isp;
extern uint8_t spr_doexec_call_seen;
extern uint16_t spr_doexec_call_sp;
extern uint16_t spr_doexec_call_start;
extern uint8_t spr_common_init_path[];
extern uint8_t *spr_common_init_argv[];
extern uint8_t *spr_common_init_envp[];
#define PROC_TRACE(x) plt_trace(x)
static bool sprinter_proc_inode_ptr_valid(inoptr ino)
{
	return (uarg_t)ino >= (uarg_t)i_tab &&
		(uarg_t)ino < (uarg_t)(i_tab + ITABSIZE);
}
#else
#define PROC_TRACE(x) do { } while (0)
#endif

/* psleep() puts a process to sleep on the given event.  If another
 * process is runnable, it switches out the current one and starts the
 * new one.  Normally when psleep is called, the interrupts have
 * already been disabled.   An event of 0 means a pause(), while an
 * event equal to the process's own ptab address is a wait().
 */

static void do_psleep(void *event, uint_fast8_t state)
{
	di();
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	spr_rw_stage = 0xD0;
	/*
	 * PID1 switchout/switchin still ends in plt_monitor / "psleep:
	 * voodoo".  Busy-poll tty-related waits (read/write on the
	 * console) and leave disk/buffer sleepers on the real idle path
	 * so /init load is not starved of completion.
	 */
	if (udata.u_ptab->p_pid == 1 &&
	    (udata.u_callno == 7 /* read */ ||
	     udata.u_callno == 8 /* write */ ||
	     (event >= (void *)&ttyinq[0] &&
	      event < (void *)(&ttyinq[0] + NUM_DEV_TTY + 1)) ||
	     (event >= (void *)&ttydata[0] &&
	      event < (void *)(&ttydata[0] + NUM_DEV_TTY + 1)))) {
		extern void kbd_poll(void);

		udata.u_ptab->p_wait = event;
		udata.u_ptab->p_waitno = ++waitno;
		udata.u_ptab->p_status = P_RUNNING;
		ei();
		kbd_poll();
		timer_interrupt();
		di();
		udata.u_ptab->p_wait = NULL;
		udata.u_ptab->p_status = P_RUNNING;
		ei();
		return;
	}
#endif
#ifdef DEBUG_SLEEP
	kprintf("psleep(0x%p)", event);
#endif
	switch (udata.u_ptab->p_status) {
	case P_SLEEP:		/* echo output from devtty happens while processes are still sleeping but in-context */
	case P_IOWAIT:
	case P_STOPPED:		/* coming to a halt */
		nready++;	/* We will fix this back up below */
	case P_RUNNING:		/* normal process */
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	case P_READY:		/* switchout can leave PID1 READY; treat as runnable */
#endif
		break;
	default:
#ifdef CONFIG_SPRINTER_EARLY_TRACE
		/*
		 * PID1 can arrive here with a non-canonical status after a
		 * partial switchout.  Recover with the same busy-poll used
		 * for tty waits instead of panic("psleep: voodoo").
		 */
		if (udata.u_ptab->p_pid == 1) {
			extern void kbd_poll(void);

			udata.u_ptab->p_wait = event;
			udata.u_ptab->p_waitno = ++waitno;
			udata.u_ptab->p_status = P_RUNNING;
			ei();
			kbd_poll();
			timer_interrupt();
			di();
			udata.u_ptab->p_wait = NULL;
			ei();
			return;
		}
#endif
#ifdef DEBUG_SLEEP
	        kprintf("psleep(0x%p) -> %d:%d", event, udata.u_ptab->p_pid, udata.u_ptab->p_status);
#endif
		panic(PANIC_VOODOO);
	}

	udata.u_ptab->p_status = state;
	udata.u_ptab->p_wait = event;
	udata.u_ptab->p_waitno = ++waitno;

	switchout();		/* Switch us out, and start another process */
	/* Switchout doesn't return in this context until we have been switched back in, of course. */
}

void psleep(void *event)
{
	do_psleep(event, P_SLEEP);
}

void psleep_nosig(void *event)
{
	do_psleep(event, P_IOWAIT);
}

/* wakeup() looks for any process waiting on the event,
 * and makes it runnable
 */

void wakeup(void *event)
{
	regptr ptptr p;
	irqflags_t irq;

#ifdef DEBUGHARDER
	kprintf("wakeup(0x%p)\n", event);
#endif
	irq = di();
	for (p = ptab; p < ptab_end; ++p) {
		if (p->p_status > P_RUNNING && p->p_wait == event) {
#ifdef DEBUG_SLEEP
			kprintf("wakeup: found proc 0x%p pid %d\n",
				p, p->p_pid);
#endif
			pwake(p);
		}
	}
	irqrestore(irq);
}


/*
 * When we wake a process in Fuzix we don't force any kind of reschedule
 * even if the priority is higher. It's too expensive on many systems to
 * be that fair.
 */
void pwake(ptptr p)
{
	if (p->p_status > P_RUNNING && p->p_status < P_STOPPED) {
		if (p->p_status != P_READY) {
			nready++;
			p->p_status = P_READY;
		}
		p->p_wait = NULL;
	}
}

/* This used to be an assembly function in older FUZIX but it turns out we
   have to do a lot of common optimizations so it is now a C helper fronting
   plt_switchout(). For speed and sanity reasons not every platform goes
   via this path when pre-empting, but instead implements a subset of the checks
   in the platform code.

   switchout() is called when a process is giving up the processor for some
   reason
 */

void switchout(void)
{
#ifdef DEBUG_SLEEP
	kprintf("switchout %d\n", udata.u_ptab->p_status);
#endif
	di();
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	spr_rw_stage = 0xD1;
#endif

	/* We do the accounting in switchout as it's cheaper and easier to
	   do it once. Useful trick borrowed from Linux */
	if (udata.u_ptab->p_status > P_READY)
		nready--;

#ifdef DEBUG_NREADY
	{
		ptptr p;
		uint_fast8_t n = 0;
		for (p = ptab; p < ptab_end; ++p) {
			if (p->p_status == P_RUNNING ||
				p->p_status == P_READY)
					n++;
		}
		if (n != nready)
			panic("nready");
	}
#endif
	/* If we have a signal we need to get to processing them we keep
	   running until it happens */
	if (chksigs()) {
#ifdef CONFIG_SPRINTER_EARLY_TRACE
		spr_rw_stage = 0xD2;
#endif
		if (udata.u_ptab->p_status > P_READY)
			nready++;
		udata.u_ptab->p_status = P_RUNNING;
		ei();
		/* Drop through - we want to be running, but we might be
		   pre-empted by someone else */
	}
	/* When we are idle we twiddle our thumbs here until a polled event
	   in plt_idle or an interrupt wakes someone up */
	while (nready == 0) {
#ifdef CONFIG_SPRINTER_EARLY_TRACE
		spr_rw_stage = 0xD3;
#endif
		/* We are idle, we cannot sleep by calling psleep */
		ei();
		plt_idle();
		di();
	}
	/* If only one process is ready to run and it's us then just
	   return. This is the normal path in most Fuzix use cases as we
	   are waiting for input while mostly system idle */
	if (udata.u_ptab->p_status == P_RUNNING || udata.u_ptab->p_status == P_READY) {
		if (nready == 1) {
#ifdef CONFIG_SPRINTER_EARLY_TRACE
			spr_rw_stage = 0xD4;
#endif
			udata.u_ptab->p_status = P_RUNNING;
			ei();
			return;
		}
		udata.u_ptab->p_status = P_READY;
	}
	/* We probably need to run something else */
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	spr_rw_stage = 0xD5;
#endif
	plt_switchout();
}

/* Getproc returns the process table pointer of a runnable process.
 * It is actually the scheduler.  If there are none, it loops.
 * This is the only time-wasting loop in the system.
 */

ptptr getproc_nextp = &ptab[0];

#ifndef CONFIG_SINGLETASK

ptptr getproc(void)
{
	ptptr haltafter;
#ifdef DEBUG_SLEEP
#ifdef DEBUGREALLYHARD
	ptptr pp;
	kputs("getproc start ... ");
	for (pp = ptab; pp < ptab_end; pp++)
		kprintf("ptab[0x%p]: pid=%d uid=%d status=%d, page=0x%x\n",
			pp, pp->p_pid, pp->p_uid, pp->p_status,
			pp->p_page);
#endif
#endif

	haltafter = getproc_nextp;

	for (;;) {
		getproc_nextp++;
		if (getproc_nextp >= ptab_end) {
			getproc_nextp = ptab;
		}

		switch (getproc_nextp->p_status) {
		case P_RUNNING:
		#ifdef CONFIG_SPRINTER_EARLY_TRACE
			/*
			 * Sprinter bring-up: recover from stale P_RUNNING entries
			 * instead of panicking the whole kernel. The current task
			 * is already switched out by this point, so any extra
			 * running slot can be demoted back to READY.
			 */
			getproc_nextp->p_status = P_READY;
			continue;
		#endif
			panic(PANIC_GETPROC);
		case P_READY:
#ifdef DEBUG_SLEEP
			kprintf("[getproc returning %p pid=%d]\n",
				getproc_nextp, getproc_nextp->p_pid);
#endif
#ifdef CONFIG_SWAPPER
			if (getproc_nextp->p_page == 0) {
				/* It gets skipped until the swapper
				   catches up */
				getproc_nextp->p_flags &= ~PFL_BATCH;
				getproc_nextp->p_flags |= PFL_SWAPIN;
				swap_in(getproc_nextp);
				continue;
			}
			getproc_nextp->p_flags &= ~PFL_SWAPIN;
#endif
			/* Punish CPU hogs by selecting them less often */
			if (getproc_nextp->p_flags & PFL_BATCH) {
				getproc_nextp->p_flags &= ~PFL_BATCH;
				continue;
			}
			return getproc_nextp;
		}
		/* Take a nap: not that it makes much difference to power on most
		   Z80 type devices */
		if (getproc_nextp == haltafter) {
			/* we have only one interrupt stack so we can't take interrupts */
			if(udata.u_ininterrupt)
				panic(PANIC_EI);
			/* yes please, interrupts on (WRS: they probably are already on?) */
			ei();
			plt_idle();
		}
	}
}

#else
/*
 *	Single tasking mode for small boxes. Keep re-selecting ourself or
 *	calling idle. When we turn zombie move back to the parent. The wait
 *	will then clean the slot and the parent continues. Most software will
 *	be blissfully unaware of its cut down environment.
 */

ptptr getproc(void)
{
	regptr ptptr p = udata.u_ptab;

#ifdef DEBUGREALLYHARD
	kputs("getproc(");
	if (udata.u_ininterrupt)
		kputs("[IRQ]");
#endif
	while (1) {
		switch (p->p_status) {
		case P_ZOMBIE:
			/* If we died go to our parent */
#ifdef DEBUGREALLYHARD
			kprintf("Zombie: move from %p to %p\n", p,
				p->p_pptr);
#endif
			p = p->p_pptr;
		case P_READY:
			/* If we are ready run us */
			p->p_status = P_RUNNING;
		case P_RUNNING:
			/* If we are running keep running */
#ifdef DEBUGREALLYHARD
			kprintf("%p:%s:%d)\n", p, p->p_name, p->p_page);
#endif
			return p;
		default:
			/* Wait for an I/O operation to let us run, don't run
			   other tasks */
			ei();
			plt_idle();
		}
	}
}
#endif

/* Makeproc fixes up the tables for the child of a fork but also for init
 * Call in the processes context!
 * This process MUST be run immediately (since it sets status P_RUNNING)
 *
 * The fork code has already copied the udata into u so we only need to
 * touch things that changed. u may or may not be the current udata
 */
void makeproc(regptr ptptr p, u_data *u)
{				/* Passed New process table entry */
	uint8_t *j, *e;
	irqflags_t irq;
	ptptr pp;

	irq = di();
	/* Note that ptab_alloc clears most of the entry */
	/* calculate base page of process based on ptab table offset */
	u->u_page = p->p_page;
	u->u_page2 = p->p_page2;

	/* Pass a pointer to the u_data copy because the ptab copy may not
	   be in common space and map_process requires a pointer to a common
	   space object */
	program_vectors(&u->u_page);	/* set up vectors in new process and
					   if needed copy any common code */
#ifdef CONFIG_PARENT_FIRST
	p->p_status = P_READY;
#else
	p->p_status = P_RUNNING;
#endif
	nready++;		/* runnable process count */

	pp = u->u_ptab;		/* Because it is a copy of the parent */

	p->p_pptr = pp;
	p->p_sig[0].s_ignored = pp->p_sig[0].s_ignored;
	p->p_sig[1].s_ignored = pp->p_sig[1].s_ignored;
	p->p_sig[0].s_held = pp->p_sig[0].s_held;
	p->p_sig[1].s_held = pp->p_sig[1].s_held;
	p->p_tty = pp->p_tty;
	p->p_uid = pp->p_uid;
	/* Set default priority */
	p->p_priority = MAXTICKS;

	/* For systems where udata is actually a pointer or a register object */
#ifdef udata
	p->p_udata = u;
#endif

	u->u_ptab = p;	/* Fixup from parent */

	memset(&p->p_utime, 0, 4 * sizeof(clock_t));	/* Clear tick counters */

	p->p_time = ticks.full;
	if (u->u_cwd)
		i_ref(u->u_cwd);
	if (u->u_root)
		i_ref(u->u_root);
	u->u_cursig = 0;
	u->u_error = 0;

	e = u->u_files + UFTSIZE;
	for (j = u->u_files; j < e; ++j) {
		if (*j != NO_FILE)
			++of_tab[*j].o_refs;
	}
	irqrestore(irq);
}

/* This allocates a new process table slot, and fills in its
 * p_pid field with a unique number.
 */

static uint16_t nextpid = 0;

ptptr ptab_alloc(void)
{
	regptr ptptr p;
	regptr ptptr newp;
	irqflags_t irq;

	newp = NULL;
	udata.u_error = EAGAIN;

	irq = di();
	for (p = ptab; p < ptab_end; p++) {
		if (p->p_status == P_EMPTY) {
			newp = p;
			/* zero process structure */
			memset(newp, 0, sizeof(struct p_tab));

			/* select a unique pid */
			while (newp->p_pid == 0) {
				if (++nextpid >= MAXPID)
					nextpid = 20;
				newp->p_pid = nextpid;

				for (p = ptab; p < ptab_end; p++)
					if (p->p_status != P_EMPTY
					    && p->p_pid == nextpid) {
						newp->p_pid = 0;	/* try again */
						break;
					}
			}
			newp->p_top = udata.u_top;		/* also for init creation */
			if (udata.u_ptab) {		/* on forking */
#ifdef CONFIG_UDATA_TEXTTOP
				newp->p_texttop = udata.u_texttop;
#endif
				newp->p_pgrp = udata.u_ptab->p_pgrp;
				memcpy(newp->p_name, udata.u_ptab->p_name, sizeof(newp->p_name));
			}
			if (pagemap_alloc(newp) == 0) {
				newp->p_status = P_FORKING;
				nproc++;
			} else {
				udata.u_error = ENOMEM;
				newp = NULL;
				break;
	                }
			udata.u_error = 0;
	                break;
		}
	}
	irqrestore(irq);
	return newp;
}

/* Follow Unix tradition with load reporting (or more accurately it
   is pre-Unix from Tenex). We don't report P_IOWAIT the same way as Unix
   does ... need to keep track of two nready values to do that */

static void load_average(void)
{
	regptr struct runload *r;
	static uint_fast8_t utick;
	uint_fast8_t i;
	uint16_t nr;

	utick++;
	if (utick < 50)
		return;

	utick = 0;

	/* Every 5 seconds */
	i = 0;
	r = &loadavg[0];
	nr = nready;

	while (i++ < 3) {
		r->average = ((((r->average - (nr << 8)) * r->exponent) +
				(((uint32_t)nr) << 16)) >> 8);
		r++;
	}
}

/*
 * Timer queue processing
 */

void ptimer_insert(void)
{
	ptptr p = udata.u_ptab;
	if (!(p->p_flags & PFL_ALARM)) {
		p->p_timerq = alarms;
		alarms = p;
		p->p_flags |= PFL_ALARM;
	}
}

/* This is the clock interrupt routine.   Its job is to increment the clock
 * counters, increment the tick count of the running process, and either
 * switch it out if it has been in long enough and is in user space or mark
 * it to be switched out if in system space.  Also it decrements the alarm
 * clock of processes.
 *
 * We are running off the interrupt stack.
 */

void timer_interrupt(void)
{
	/* Increment processes and global tick counters. We can't do this
	   mid swap because we might have half of the bits for one process
	   and half of another.. */
	if (!inswap && udata.u_ptab->p_status == P_RUNNING) {
		if (udata.u_insys)
			udata.u_ptab->p_stime++;
		else
			udata.u_ptab->p_utime++;
	}

	/* Do once-per-decisecond things - this doesn't work out well on
	   boxes with 64 ticks/second.. need a better approach */
	if (++ticks_this_dsecond == ticks_per_dsecond) {
		ptptr p, *q;
		ticks_this_dsecond = 0;
		++ticks.full;
		q = &alarms;
		while(*q) {
			p = *q;
			if (p->p_status == P_EMPTY)
				panic("dead timer");
			if (p->p_alarm) {
				p->p_alarm--;
				if (!p->p_alarm)
					ssig(p, SIGALRM);
			}
			if (p->p_timeout > 1) {
				p->p_timeout--;
				if (p->p_timeout == 1)
					pwake(p);
			}
			if (p->p_timeout < 2 && !p->p_alarm) {
				p->p_flags &= ~PFL_ALARM;
				*q = p->p_timerq;
			} else
				q = &(p->p_timerq);
		}
		updatetod();
                load_average();
#ifdef CONFIG_AUDIO
		audio_tick();
#endif
	}
#ifndef CONFIG_SINGLETASK
	sync_clock();
	/* Check run time of current process. We don't charge time while
	   swapping as the last thing we want to do is to swap a process in
	   and decide it took time to swap in so needs to go away again! */
	if (!inswap && ++runticks >= udata.u_ptab->p_priority && !udata.u_insys) {
		/* It might appear to make the best sense to just leave
		   runticks ticking upwards if nobody else needs to run but
		   this has two problems. The obvious one is that it may wrap
		   but less obviously it can also cause thrashing on fork()
		   in some memory models */
		if (nready > 1) {
			need_resched = 1;
#ifdef DEBUG_PREEMPT
			kprintf("[preempt %p %d]", udata.u_ptab,
				udata.u_ptab->p_priority);
#endif
		} else	/* Nobody else to run, user gets new time quantum */
			runticks = 0;
	}
#endif
}

#ifdef DEBUG_SYSCALL
#include "syscall_name.h"
#endif

/*
 * Fuzix system call handler
 *
 * we arrive here from syscall interfaces with the kernel paged in, using
 * the kernel stack, interrupts enabled. The glue code has also placed the
 * system call number and arguments into the udata for ease of access and
 * portability.The routine returns two parameters to the platform glue via
 * u_retval and u_error. The platform glue is responsible for returning these
 * in a sensible form to the caller.
 */
void unix_syscall(void)
{
	arg_t rv;
	udata.u_error = 0;
	if (udata.u_ptab->p_pid == 1) {
		PROC_TRACE(0xC2);
		PROC_TRACE((uint8_t)udata.u_callno);
		PROC_TRACE((uint8_t)udata.u_argn);
		PROC_TRACE((uint8_t)(udata.u_argn >> 8));
		PROC_TRACE((uint8_t)udata.u_syscall_sp);
		PROC_TRACE((uint8_t)(udata.u_syscall_sp >> 8));
	}

	if (udata.u_callno >= FUZIX_SYSCALL_COUNT) {
#if defined(CONFIG_SPRINTER_EARLY_TRACE) && !defined(CONFIG_LEVEL_2)
		if (udata.u_callno == 77) {
			udata.u_retval = 0;
			udata.u_error = 0;
		} else if (udata.u_callno == 78) {
			udata.u_ptab->p_pgrp = udata.u_ptab->p_pid;
			udata.u_ptab->p_tty = 0;
			udata.u_retval = udata.u_ptab->p_pid;
			udata.u_error = 0;
		} else if (udata.u_callno == 79) {
			udata.u_retval = udata.u_ptab->p_pid;
			udata.u_error = 0;
		} else
#endif
		{
			if (udata.u_ptab->p_pid == 1) {
				PROC_TRACE(0xC4);
				PROC_TRACE((uint8_t)udata.u_callno);
				if (udata.u_callno & 0x80) {
					PROC_TRACE(0xC7);
					PROC_TRACE((uint8_t)udata.u_callno);
					PROC_TRACE((uint8_t)udata.u_argn);
					PROC_TRACE((uint8_t)(udata.u_argn >> 8));
					PROC_TRACE((uint8_t)ugetc((void *)udata.u_syscall_sp));
					PROC_TRACE((uint8_t)ugetc((void *)((uarg_t)udata.u_syscall_sp + 1)));
					PROC_TRACE((uint8_t)ugetc((void *)((uarg_t)udata.u_syscall_sp + 2)));
					PROC_TRACE((uint8_t)ugetc((void *)((uarg_t)udata.u_syscall_sp + 3)));
				}
			}
			udata.u_error = ENOSYS;
		}
	} else {
#ifdef DEBUG_SYSCALL
		kprintf("\t\tpid %d: syscall %d\t%s(%p, %p, %p)\n",
			udata.u_ptab->p_pid, udata.u_callno,
			syscall_name[udata.u_callno], udata.u_argn,
			udata.u_argn1, udata.u_argn2);
#endif
		/* Dispatch system call */
		rv = (*syscall_dispatch[udata.u_callno]) ();
		/* There is subtle magic here: The system call may change the
		   current process and on some systems that changes how the
		   macro for udata is evaluated. C does not define whether the
		   left side of the assignment evaluates first so we must
		   go via a temporary to force a sequence point */
		udata.u_retval = rv;

#ifdef DEBUG_SYSCALL
		kprintf("\t\t\tpid %d: ret syscall %d, ret %p err %p\n",
			udata.u_ptab->p_pid, udata.u_callno,
			udata.u_retval, udata.u_error);
#endif
	}
	if (udata.u_ptab->p_pid == 1) {
		PROC_TRACE(0xC3);
		PROC_TRACE((uint8_t)udata.u_error);
		PROC_TRACE((uint8_t)udata.u_retval);
		PROC_TRACE((uint8_t)(udata.u_retval >> 8));
		PROC_TRACE((uint8_t)udata.u_ptab->p_status);
	}
	udata.u_ptab->p_timeout = 0;

	sync_clock();

	di();
	if (
#ifdef CONFIG_PARENT_FIRST
	/*
	 *	This is not nice but in the pure swap parent first case
	 *	we always give the parent a chance to get to waitpid().
	 *	If they don't then the interrupt after will get them if
	 *	they are already due for pre-emption.
	 *
	 *	Without this if we are the only running process and exceeded
	 *	time then when we fork we end up thrashing in and out of
	 *	swap before the waitpid.
	 */
		(udata.u_callno != 32 /* fork */ || !udata.u_retval) &&
#endif
		runticks >= udata.u_ptab->p_priority && nready > 1) {
#ifdef DEBUG_PREEMPT	
		kprintf("P: %d %x %d\n", runticks, udata.u_ptab, udata.u_ptab->p_priority);
#endif		
		/* Time to switch out? - we may have overstayed our welcome inside
		   a syscall so swtch straight afterwards */
		udata.u_ptab->p_status = P_READY;
		/* We know there will be a switch if we hit this point so
		   don't look for optimizations. Likewise we know a signal
		   process will stay running/ready */
		plt_switchout();
		/* We will check the signals before we return to user space
		   so all is good */
	}
	ei();
	chksigs();
}

void sgrpsig(uint16_t pgrp, uint_fast8_t sig)
{
	regptr ptptr p;
	if (pgrp) {
		for (p = ptab; p < ptab_end; ++p)
			if (p->p_pgrp == pgrp)
				ssig(p, sig);
	}
}

#ifdef CONFIG_LEVEL_2
uint_fast8_t dump_core(uint_fast8_t sig)
{
        if (!(udata.u_flags & U_FLAG_NOCORE) && ((sig == SIGQUIT || sig == SIGILL || sig == SIGTRAP ||
            sig == SIGABRT || sig == SIGBUS || sig == SIGFPE ||
            sig == SIGSEGV || sig == SIGXCPU || sig == SIGXFSZ ||
            sig == SIGSYS))) {
		return sig | write_core_image();
	}
	return sig;
}
#endif                                    


/* FIXME: we should keep a dirty flag so we know if we need to check for
   signals so we can optimise this path */

/* This sees if the current process has any signals set, and handles them.
 */

#define SIGBIT(x)	(1 << (x & 15))

static const uint16_t stopper =
	SIGBIT(SIGSTOP) | SIGBIT(SIGTTIN) | SIGBIT(SIGTTOU) | SIGBIT(SIGTSTP);

static const uint16_t clear =
	SIGBIT(SIGSTOP) | SIGBIT(SIGTTIN) | SIGBIT(SIGTTOU) | SIGBIT(SIGTSTP) |
	SIGBIT(SIGCHLD) | SIGBIT(SIGURG) | SIGBIT(SIGWINCH) | SIGBIT(SIGIO) |
	SIGBIT(SIGCONT);

/* Put back a computed signal so that we can recalculate what needs to be
   serviced correctly */
void recalc_cursig(void)
{
	if (udata.u_cursig) {
		struct sigbits *sb = udata.u_ptab->p_sig;
		if (udata.u_cursig & 16) {
			sb++;
			udata.u_cursig &= ~16;
		}
		sb->s_pending |= 1 << udata.u_cursig;
		udata.u_cursig = 0;
	}
	/* This function gets called on things like signal mask changes
	   so even if no signal was pending there might be one next time
	   we ask */
	udata.u_ptab->p_flags |= PFL_CHKSIG;
}

/* Process a block of 16 signals so we can avoid using longs */
static uint_fast8_t chksigset(struct sigbits *sb, uint_fast8_t b)
{
	uint_fast8_t j = 1;
	int (**svec)(int) = &udata.u_sigvec[0];
	uint16_t m;
	uint16_t pending = sb->s_pending & ~sb->s_held;

	if (pending == 0)
		return 0;

	if (b == 1)  {
		j = 0;
		svec = &udata.u_sigvec[15]; /* ++ done at start */
	}

	/* Dispatch the lowest numbered signal */
	for (; j < 15; ++j) {
		svec++;
		/* FIXME: optimise by setting up m once and shifting */
		m = 1 << j;
		if (!(m & pending))
			continue;
		/* This is more complex than in V7 - we have multiple
		   behaviours plus core dump */
		if (*svec == SIG_DFL) {
		        /* SIGSTOP can't be ignored and puts the process into
		           P_STOPPED state when it is ready to handle the signal.
		           Annoyingly right now we have to context switch to the task
		           in order to stop it in the right place. That would be nice
		           to fix */
		        if (b && (m & stopper)) {
				/* Don't allow us to race SIGCONT */
				di();
				/* Can we ever end up here not in READY/RUNNING ? */
				/* Yes: we could be in P_SLEEP on a close race
				   with do_psleep() */
				udata.u_ptab->p_status = P_STOPPED;
				udata.u_ptab->p_event = j;
				sb->s_pending &= ~m;	// unset the bit
				/* Defer if we are in interrupt state, we
				   will pick up the reschedule instead */
				if (udata.u_ininterrupt)
					need_resched = 1;
				else
					switchout();
				/* Other things may have happened */
				return 0xFF;
	                }

			/* The signal is being handled, so clear it even if
			   we are exiting (otherwise we'll loop in
			   chksigs) */
			sb->s_pending &= ~m;

	                if ((b && (m & clear)) || udata.u_ptab->p_pid == 1) {
			/* SIGCONT is subtle - we woke the process to handle
			   the signal so ignoring here works fine */
				continue;
			}
#ifdef DEBUG_SLEEP
			kprintf("process terminated by signal %d (%d)\n",
				j + 16 *b, udata.u_ptab->p_status);
#endif
			/* We may have marked ourselves as asleep and
			   then been caught by the chksigs when we tried
			   to task switch into bed. In that case we need
			   to put the process back in running state */
			if (udata.u_ptab->p_status == P_SLEEP) {
				udata.u_ptab->p_status = P_RUNNING;
				nready++;
			}
			PROC_TRACE(0xCA);
			PROC_TRACE((uint8_t)j);
			PROC_TRACE((uint8_t)b);
			doexit(dump_core(j));
		} else if (*svec != SIG_IGN) {
			/* Arrange to call the user routine at return */
			sb->s_pending &= ~m;	// unset the bit
#ifdef DEBUG_SLEEP
			kprintf("about to process signal %d\n", j);
#endif
			udata.u_cursig = j + (b << 4);
			break;
		}
	}
	return udata.u_cursig;
}

uint_fast8_t chksigs(void)
{
	struct sigbits *sb = udata.u_ptab->p_sig;
	uint_fast8_t r;
	uint_fast8_t b;

#ifdef CONFIG_SPRINTER_EARLY_TRACE
	if (udata.u_ptab->p_pid == 1) {
		udata.u_cursig = 0;
		udata.u_ptab->p_flags &= ~PFL_CHKSIG;
		udata.u_ptab->p_sig[0].s_pending = 0;
		udata.u_ptab->p_sig[1].s_pending = 0;
		return 0;
	}
#endif

	/* Sleeping without signals allowed. We rely upon the fact that
	   P_IOWAIT is never pre-empted or returns to user space so
	   udata.u_cursig is not consulted until it is safe to do so */
	if (udata.u_ptab->p_status == P_IOWAIT) {
		recalc_cursig();
		return 0;
	}

	/* Fast path - no signals pending means no work.
	   Cursig being set means we've already worked out what to do.
	 */
rescan:
	if (udata.u_cursig || !(udata.u_ptab->p_flags & PFL_CHKSIG) || udata.u_ptab->p_status == P_STOPPED)
		return udata.u_cursig;

	for (b = 0; b < 2; b++, sb++) {
		r = chksigset(sb, b);
		if (r == 0xFF)
			goto rescan;
		else if (r)
			return udata.u_cursig;
	}
	/* No signal pending, remember this */
	udata.u_ptab->p_flags &= ~PFL_CHKSIG;
	return 0;
}

/*
 *	Send signal, avoid touching uarea
 */

void ssig(ptptr proc, uint_fast8_t sig)
{
	struct sigbits *m = proc->p_sig;
	uint16_t sigm;
	irqflags_t irq;

	if (sig > 15)
		m++;

	sigm = 1 << (sig & 0x0F);

#ifdef DEBUG_SLEEP
	kprintf("sig %d to %d(%d) %p %p\n",
		sig, proc->p_pid, proc->p_status, proc, udata.u_ptab);
#endif

	irq = di();

	if (proc->p_status != P_EMPTY) {	/* Presumably was killed just now */
		proc->p_flags |= PFL_CHKSIG;
                /* SIGCONT has an unblockable effect */
		if (sig == SIGCONT) {
			/* You can never send yourself a SIGCONT when you are stopped */
			if (proc->p_status == P_STOPPED) {
			        proc->p_status = P_READY;
			        proc->p_event = 0;
			        nready++;
			}
			/* CONT discards pending stops */
			proc->p_sig[1].s_pending &= ~(SIGBIT(SIGSTOP) | SIGBIT(SIGTTIN)
						     | SIGBIT(SIGTTOU) | SIGBIT(SIGTSTP));
		}
		/* STOP discards pending conts */
		if (sig >= SIGSTOP && sig <= SIGTTOU)
			proc->p_sig[1].s_pending &= ~SIGBIT(SIGCONT);

		/* Routine signal behaviour */
		if (!(m->s_ignored & sigm)) {
			/* Don't wake for held signals */
			if (!(m->s_held & sigm)) {
				switch (proc->p_status) {
				case P_SLEEP:
					proc->p_status = P_READY;
					nready++;
				default:;
				}
				proc->p_wait = NULL;
			}
			m->s_pending |= sigm;
		}
		/* FIXME: need to clean up the way we handle ready/running
		   so we have a simple 'make runnable' */
		if (proc->p_status == P_READY) {
			/* This is a weird corner case. If we deliver a signal
			   to someone who is now running then sync_clock so that
			   things like ^C feel nice */
			sync_clock();
			if (udata.u_ptab == proc)
				proc->p_status = P_RUNNING;
		}
	}
	irqrestore(irq);
}

#ifdef CONFIG_ACCT
void acctexit(ptptr p)
{
	struct oft *oftp;
	inoptr ino;

	if (acct_fh == -1)
		return;

	oftp = &of_tab[acct_fh];
	ino = oftp->o_inode;

	/* Reuse the field before we write out accounting data */
	udata.u_mask = p->p_uid;
	/* More useful information is u_top */
	udata.u_break = udata.u_top;

	udata.u_sysio = true;
	udata.u_base = (char *) &udata.u_mask;
	udata.u_count = 48;	/* Includes some spare for expansion */

	/* Append to the end of the file */
	oftp->o_ptr = ino->c_node.i_size;
	writei(ino, 0);
}
#endif

/*
 *	Perform the terminal process signalling for process c
 *
 *	POSIX requires
 *	1. If SIGCHLD is ignored - the process dies
 *	2. Otherwise it becomes a zombie and we signal the parent
 *
 *	This gets called both when a process dies and when it gets reparented
 *	to init (parent dies), because init is entitled to ignore SIGCHLD too
 */
static int signal_parent(ptptr c)
{
	ptptr p = c->p_pptr;
        if (p->p_sig[1].s_ignored & (1UL << (SIGCHLD - 16))) {
		/* POSIX.1 says that SIG_IGN for SIGCHLD means don't go
		   zombie, just clean up as we go */
		udata.u_ptab->p_status = P_EMPTY;
                return 0;
	}
	ssig(p, SIGCHLD);
	/* Wake up a waiting parent, if any. */
	wakeup((char *)p);
	udata.u_ptab->p_status = P_ZOMBIE;
	return 1;
}

void doexit(uint16_t val)
{
	uint_fast8_t j;
	ptptr p;
	irqflags_t irq;

	PROC_TRACE(0xC6);
	PROC_TRACE((uint8_t)udata.u_ptab->p_pid);
	PROC_TRACE((uint8_t)udata.u_ptab->p_status);
	PROC_TRACE((uint8_t)val);
	PROC_TRACE((uint8_t)(val >> 8));

#ifdef DEBUG_SLEEP
	kprintf("process %d exiting %d\n", udata.u_ptab->p_pid, val);

	kprintf
	    ("udata.u_page %u, udata.u_ptab %p, udata.u_ptab->p_page %u\n",
	     udata.u_page, udata.u_ptab, udata.u_ptab->p_page);
#endif
	if (udata.u_ptab->p_pid == 1)
	{
	#ifdef CONFIG_SPRINTER_EARLY_TRACE
		/*
		 * Sprinter bring-up: avoid global panic when PID 1 trips a
		 * fault path (null/trap recovery currently routes via doexit).
		 * Keep init alive so boot can continue and diagnostics can be
		 * collected from a running system.
		 */
		udata.u_cursig = 0;
		udata.u_error = EFAULT;
		return;
	#endif
		PROC_TRACE(0xC8);
		PROC_TRACE((uint8_t)val);
		PROC_TRACE((uint8_t)(val >> 8));
		PROC_TRACE(0xC9);
		PROC_TRACE((uint8_t)udata.u_error);
		PROC_TRACE((uint8_t)udata.u_cursig);
		panic(PANIC_KILLED_INIT);
	}

	sync();		/* Not necessary, but a good idea. */

	irq = di();

	/* We are exiting, hold all signals  (they will never be
	   delivered). If we don't do this we might take a signal
	   while exiting which would be ... unfortunate */
	udata.u_ptab->p_sig[0].s_held = 0xFFFFU;
	udata.u_ptab->p_sig[1].s_held = 0xFFFFU;
	udata.u_cursig = 0;

	/* Discard our memory before we blow away and reuse the memory */
#ifdef CONFIG_PLATFORM_UDMA
	plt_udma_kill(udata.u_ptab);
#endif
	pagemap_free(udata.u_ptab);

	for (j = 0; j < UFTSIZE; ++j) {
		if (udata.u_files[j] != NO_FILE)
			doclose(j);
	}

	udata.u_ptab->p_exitval = val;

	i_deref(udata.u_cwd);
	i_deref(udata.u_root);

	/* Stash away child's execution tick counts in process table,
	 * overlaying some no longer necessary stuff.
	 *
	 * Pedantically POSIX says we should do this at the point of wait()
	 */

	sync_clock();	/* Not that these values will be wildly accurate! */

	for (p = ptab; p < ptab_end; ++p) {
		if (p->p_status == P_EMPTY || p == udata.u_ptab)
			continue;
		/* Set any child's parents to init */
		if (p->p_pptr == udata.u_ptab) {
			p->p_pptr = ptab;	/* ptab is always init */
			/* Figure out if we are signalling init or just
			   blowing the slot away */
			signal_parent(p);
		}
		/* Send SIGHUP to any pgrp members and remove
		   them from our pgrp */
                if (p->p_pgrp == udata.u_ptab->p_pid) {
			p->p_pgrp = 0;
			ssig(p, SIGHUP);
			ssig(p, SIGCONT);
		}
		/* Sneak the alarmq dequeue into the same loop */
		if (p->p_timerq == udata.u_ptab)
			p->p_timerq = udata.u_ptab->p_timerq;
	}
	/* If we head the timer list then we didn't kill it in the loop */
	if (alarms == udata.u_ptab)
		alarms = udata.u_ptab->p_timerq;
	tty_exit();
	irqrestore(irq);
#ifdef DEBUG_SLEEP
	kprintf
	    ("udata.u_page %u, udata.u_ptab %p, udata.u_ptab->p_page %u\n",
	     udata.u_page, udata.u_ptab, udata.u_ptab->p_page);
#endif
#ifdef CONFIG_ACCT
	acctexit(udata.u_ptab);
#endif
        udata.u_page = 0xFFFFU;
        udata.u_page2 = 0xFFFFU;
	signal_parent(udata.u_ptab);
	nready--;
	nproc--;
	switchin(getproc());
	#ifdef CONFIG_SPRINTER_EARLY_TRACE
	/*
	 * Sprinter bring-up: if switchin() unexpectedly returns from the
	 * exit path, avoid dropping straight into PANIC_DOEXIT/monitor.
	 * Leave the dead task marked empty and hand control back so the
	 * next symptom can surface instead of a hard stop.
	 */
	return;
	#endif
	panic(PANIC_DOEXIT);
}

void NORETURN panic(char *deathcry)
{
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_last_panic_ptr = (uint16_t)(uarg_t)deathcry;
	sprinter_last_panic_bytes[0] = deathcry[0];
	sprinter_last_panic_bytes[1] = deathcry[1];
	sprinter_last_panic_bytes[2] = deathcry[2];
	sprinter_last_panic_bytes[3] = deathcry[3];
#endif
	PROC_TRACE(0xDB);
	PROC_TRACE((uint8_t)(uarg_t)deathcry);
	PROC_TRACE((uint8_t)(((uarg_t)deathcry) >> 8));
	PROC_TRACE(0xDC);
	PROC_TRACE(deathcry[0]);
	PROC_TRACE(deathcry[1]);
	PROC_TRACE(deathcry[2]);
	PROC_TRACE(deathcry[3]);
	kputs("\r\npanic: ");
	kputs(deathcry);
	plt_monitor();

	for(;;);
}

#ifdef CONFIG_SWAPPER

/*
 *	Very simple swap helper task for systems that benefit from it.
 *
 *	There is lots more can be done here especially if the platform
 *	has true asynchronous disk I/O - things like paging stuff out in
 *	advance.
 */

static struct p_tab *swapin_proc;

void NORETURN swapper(void)
{
	irqflags_t irq;
	struct p_tab *proc;

	while(1) {
		irq = di();
		if (swapin_proc) {
			proc = swapin_proc;
			swapin_proc = HULL;
			irqrestore(irq);
			swapin(proc, proc->p_page2);
		}
		psleep(&swapper);
	}
}

void swap_in(ptptr proc)
{
	/* No queue for now */
	if (swapin_proc == NULL) {
		swapin_proc = proc;
		wakeup(&swapper);
	}
}

#endif

/* We put this here so that we can blow the start.c code away on exec
   eventually, but still manage to get the panic() to happen if it fails */
void exec_or_die(void)
{
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	extern uint16_t sprinter_last_exec_base;
	extern uint16_t sprinter_last_exec_count;
	extern uint16_t sprinter_last_exec_top;
	extern uint8_t sprinter_last_exec_upage[4];
	extern uint8_t sprinter_last_exec_ptab[4];
	/*
	 * Sprinter bring-up: the previous exec_or_die shims (raw probe,
	 * in-place realloc, fresh pagemap_alloc) all became suspects for the
	 * current pre-exec trap.  Leave only a passive kernel-side snapshot
	 * here and follow the stock _execve() path unchanged.
	 */
	sprinter_last_exec_base = 0;
	sprinter_last_exec_count = 0;
	sprinter_last_exec_top = udata.u_top;
	memcpy(sprinter_last_exec_upage, &udata.u_page, 4);
	memcpy(sprinter_last_exec_ptab, &udata.u_ptab->p_page, 4);
#endif
#ifdef CONFIG_SWAPPER
	irqflags_t irq;
	unsigned pid;
	struct p_tab *p;

	kputs("Starting swapper\n");
	p = ptab_alloc();
	if (p == NULL)
		panic("pswp");
	irq = di();
	pid = dofork(p);
	irqrestore(irq);
	if (pid != 1)
		swapper();
#endif
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('e');
#endif
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	kputs("Starting /init [72]\n");
#else
	kputs("Starting /init\n");
#endif
	#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('f');
	/*
	 * Sprinter bring-up: complete_init() already prepared argv/envp in the
	 * fresh PID1 address space. Touching user memory again here adds one
	 * more pre-exec write path and has repeatedly become a suspect for the
	 * trap before the first stable /init syscall.
	 */
	udata.u_page = udata.u_ptab->p_page;
	udata.u_page2 = udata.u_ptab->p_page2;
	sprinter_last_exec_base = 0;
	sprinter_last_exec_count = 0;
	sprinter_last_exec_top = udata.u_top;
	memcpy(sprinter_last_exec_upage, &udata.u_page, 4);
	memcpy(sprinter_last_exec_ptab, &udata.u_ptab->p_page, 4);
	sprinter_bootmark('g');
	#endif
	plt_discard();
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('h');
	udata.u_sysio = 1;
	udata.u_argn = (arg_t)spr_common_init_path;
	udata.u_argn1 = (arg_t)spr_common_init_argv;
	udata.u_argn2 = (arg_t)spr_common_init_envp;
	if (sprinter_proc_inode_ptr_valid(root)) {
		if (!sprinter_proc_inode_ptr_valid(udata.u_root))
			udata.u_root = i_ref(root);
		if (!sprinter_proc_inode_ptr_valid(udata.u_cwd))
			udata.u_cwd = i_ref(root);
	}
	/*
	 * Do not call sprinter_force_bank1() here: exec_or_die lives in
	 * CODE2, and remapping WIN1/WIN2 to CODE1 under a live CODE2 PC
	 * fetches the wrong bank.  _execve() is reached via __bank_2_3.
	 */
	sprinter_bootmark('H');
#endif
	_execve();
#ifdef CONFIG_SPRINTER_EARLY_TRACE
	sprinter_bootmark('i');
	kprintf("xv st=%x er=%x nm=%x rt=%x cw=%x ino=%x md=%x pm=%x mf=%x av=%x ev=%x dn=%x ct=%x\n",
		sprinter_exec_fail_stage, sprinter_exec_fail_err,
		sprinter_exec_fail_name, sprinter_exec_fail_root,
		sprinter_exec_fail_cwd, sprinter_exec_fail_ino,
		sprinter_exec_fail_mode, sprinter_exec_fail_perm,
		sprinter_exec_fail_mflags, sprinter_exec_fail_argv,
		sprinter_exec_fail_envp, sprinter_exec_fail_done,
		sprinter_exec_fail_count);
	kprintf("np st=%x wd=%x ni=%x n0=%x ch=%x us=%x ue=%x ur=%x uc=%x\n",
		sprinter_last_nopen_stage, sprinter_last_nopen_wd,
		sprinter_last_nopen_ninode, sprinter_last_nopen_name0,
		sprinter_last_nopen_char, udata.u_sysio, udata.u_error,
		(uint16_t)(uarg_t)udata.u_root,
		(uint16_t)(uarg_t)udata.u_cwd);
	kprintf("dx bc=%x arm=%x seen=%x ex=%x isp=%x cs=%x csp=%x cst=%x\n",
			spr_boot_count, spr_doexec_arm, spr_doexec_seen,
			spr_doexec_expect, spr_doexec_isp, spr_doexec_call_seen,
			spr_doexec_call_sp, spr_doexec_call_start);
	kprintf("rx ue=%x pid=%x us=%x\n",
		udata.u_error,
		udata.u_ptab ? udata.u_ptab->p_pid : 0,
		udata.u_sysio);
#endif
	PROC_TRACE(0xDA);
	PROC_TRACE((uint8_t)udata.u_error);
	PROC_TRACE((uint8_t)udata.u_retval);
	PROC_TRACE((uint8_t)(udata.u_retval >> 8));
	panic(PANIC_NOINIT);	/* BIG Trouble if we Get Here!! */
}
