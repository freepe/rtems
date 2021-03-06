/*
 * Copyright (c) 2011, 2016 embedded brains GmbH.  All rights reserved.
 *
 *  embedded brains GmbH
 *  Dornierstr. 4
 *  82178 Puchheim
 *  Germany
 *  <rtems@embedded-brains.de>
 *
 * The license and distribution terms for this file may be
 * found in the file LICENSE in this distribution or at
 * http://www.rtems.org/license/LICENSE.
 */

#include <bspopts.h>
#include <rtems/score/percpu.h>
#include <bsp/vectors.h>

#define VECTOR_REGISTER r4
#define SELF_CPU_REGISTER r5
#define ISR_NEST_REGISTER r6
#define DISPATCH_LEVEL_REGISTER r7
#define HANDLER_REGISTER r8
#define SCRATCH_0_REGISTER r0
#define SCRATCH_1_REGISTER r3
#define SCRATCH_2_REGISTER r9
#define SCRATCH_3_REGISTER r10
#define SCRATCH_4_REGISTER r11
#define SCRATCH_5_REGISTER r12
#define FRAME_REGISTER r14

#define VECTOR_OFFSET GPR4_OFFSET
#define SELF_CPU_OFFSET GPR5_OFFSET
#define ISR_NEST_OFFSET GPR6_OFFSET
#define DISPATCH_LEVEL_OFFSET GPR7_OFFSET
#define HANDLER_OFFSET GPR8_OFFSET
#define SCRATCH_0_OFFSET GPR0_OFFSET
#define SCRATCH_1_OFFSET GPR3_OFFSET
#define SCRATCH_2_OFFSET GPR9_OFFSET
#define SCRATCH_3_OFFSET GPR10_OFFSET
#define SCRATCH_4_OFFSET GPR11_OFFSET
#define SCRATCH_5_OFFSET GPR12_OFFSET

/*
 * The register 2 slot is free, since this is the read-only small data anchor.
 */
#define FRAME_OFFSET GPR2_OFFSET

#ifdef RTEMS_PROFILING
/*
 * The CPU_INTERRUPT_FRAME_SIZE is enough to store this additional register.
 */
#define ENTRY_INSTANT_REGISTER r15
#define ENTRY_INSTANT_OFFSET GPR13_OFFSET

.macro GET_TIME_BASE REG
#if defined(__PPC_CPU_E6500__)
	mfspr \REG, FSL_EIS_ATBL
#elif defined(ppc8540)
	mfspr	\REG, TBRL
#else /* ppc8540 */
	mftb	\REG
#endif /* ppc8540 */
.endm
#endif /* RTEMS_PROFILING */

#ifdef PPC_EXC_CONFIG_USE_FIXED_HANDLER
	.global	bsp_interrupt_dispatch
#endif /* PPC_EXC_CONFIG_USE_FIXED_HANDLER */

	.global	ppc_exc_min_prolog_async_tmpl_normal
	.global ppc_exc_wrap_async_normal

ppc_exc_min_prolog_async_tmpl_normal:

	stwu	r1, -CPU_INTERRUPT_FRAME_SIZE(r1)

#ifndef PPC_EXC_CONFIG_USE_FIXED_HANDLER
	stw	VECTOR_REGISTER, PPC_EXC_VECTOR_PROLOGUE_OFFSET(r1)
	li	VECTOR_REGISTER, 0xffff8000
#endif /* PPC_EXC_CONFIG_USE_FIXED_HANDLER */

	/*
	 * We store the absolute branch target address here.  It will be used
	 * to generate the branch operation in ppc_exc_make_prologue().
	 */
	.int	ppc_exc_wrap_async_normal

ppc_exc_wrap_async_normal:

#ifdef RTEMS_PROFILING
	/* Save non-volatile ENTRY_INSTANT_REGISTER */
	stw	ENTRY_INSTANT_REGISTER, ENTRY_INSTANT_OFFSET(r1)

	/* Get entry instant */
	GET_TIME_BASE	ENTRY_INSTANT_REGISTER
#endif /* RTEMS_PROFILING */

	/* Save non-volatile FRAME_REGISTER */
	stw	FRAME_REGISTER, FRAME_OFFSET(r1)

#ifdef __SPE__
	/* Enable SPE */
	mfmsr	FRAME_REGISTER
	oris	FRAME_REGISTER, FRAME_REGISTER, MSR_SPE >> 16
	mtmsr	FRAME_REGISTER
	isync
#endif

#if defined(PPC_MULTILIB_FPU) || defined(PPC_MULTILIB_ALTIVEC)
	/* Enable FPU and/or AltiVec */
	mfmsr	FRAME_REGISTER
#ifdef PPC_MULTILIB_FPU
	ori	FRAME_REGISTER, FRAME_REGISTER, MSR_FP
#endif
#ifdef PPC_MULTILIB_ALTIVEC
	oris	FRAME_REGISTER, FRAME_REGISTER, MSR_VE >> 16
#endif
	mtmsr	FRAME_REGISTER
	isync
#endif

	/* Move frame pointer to non-volatile FRAME_REGISTER */
	mr	FRAME_REGISTER, r1

	/* Load ISR nest level and thread dispatch disable level */
	PPC_GPR_STORE	SELF_CPU_REGISTER, SELF_CPU_OFFSET(r1)
	GET_SELF_CPU_CONTROL	SELF_CPU_REGISTER
	PPC_GPR_STORE	ISR_NEST_REGISTER, ISR_NEST_OFFSET(r1)
	lwz	ISR_NEST_REGISTER, PER_CPU_ISR_NEST_LEVEL(SELF_CPU_REGISTER)
	PPC_GPR_STORE	DISPATCH_LEVEL_REGISTER, DISPATCH_LEVEL_OFFSET(r1)
	lwz	DISPATCH_LEVEL_REGISTER, PER_CPU_THREAD_DISPATCH_DISABLE_LEVEL(SELF_CPU_REGISTER)

	PPC_GPR_STORE	SCRATCH_0_REGISTER, SCRATCH_0_OFFSET(r1)

#ifndef PPC_EXC_CONFIG_USE_FIXED_HANDLER
#ifdef __SPE__
	/*
	 * Save high order part of VECTOR_REGISTER here.  The low order part
	 * was saved in the minimal prologue.
	 */
	evmergehi	SCRATCH_0_REGISTER, SCRATCH_0_REGISTER, VECTOR_REGISTER
	stw	SCRATCH_0_REGISTER, VECTOR_OFFSET(r1)
#endif
#else /* PPC_EXC_CONFIG_USE_FIXED_HANDLER */
	/* The vector register has no special purpose in this case */
	PPC_GPR_STORE	VECTOR_REGISTER, VECTOR_OFFSET(r1)
#endif /* PPC_EXC_CONFIG_USE_FIXED_HANDLER */

	PPC_GPR_STORE	HANDLER_REGISTER, HANDLER_OFFSET(r1)

#ifndef PPC_EXC_CONFIG_USE_FIXED_HANDLER
	/*
	 * Load the handler address.  Get the handler table index from the
	 * vector number.  We have to discard the exception type.  Take only
	 * the least significant five bits (= LAST_VALID_EXC + 1) from the
	 * vector register.  Multiply by four (= size of function pointer).
	 */
	rlwinm	SCRATCH_0_REGISTER, VECTOR_REGISTER, 2, 25, 29
	lis	HANDLER_REGISTER, ppc_exc_handler_table@h
	ori	HANDLER_REGISTER, HANDLER_REGISTER, ppc_exc_handler_table@l
	lwzx	HANDLER_REGISTER, HANDLER_REGISTER, SCRATCH_0_REGISTER
#endif /* PPC_EXC_CONFIG_USE_FIXED_HANDLER */

	PPC_GPR_STORE	SCRATCH_1_REGISTER, SCRATCH_1_OFFSET(r1)
	PPC_GPR_STORE	SCRATCH_2_REGISTER, SCRATCH_2_OFFSET(r1)
	PPC_GPR_STORE	SCRATCH_3_REGISTER, SCRATCH_3_OFFSET(r1)
	PPC_GPR_STORE	SCRATCH_4_REGISTER, SCRATCH_4_OFFSET(r1)
	PPC_GPR_STORE	SCRATCH_5_REGISTER, SCRATCH_5_OFFSET(r1)

	/* Save SRR0, SRR1, CR, CTR, XER, and LR */
	mfsrr0	SCRATCH_0_REGISTER
	mfsrr1	SCRATCH_1_REGISTER
	mfcr	SCRATCH_2_REGISTER
	mfctr	SCRATCH_3_REGISTER
	mfxer	SCRATCH_4_REGISTER
	mflr	SCRATCH_5_REGISTER
	stw	SCRATCH_0_REGISTER, SRR0_FRAME_OFFSET(r1)
	stw	SCRATCH_1_REGISTER, SRR1_FRAME_OFFSET(r1)
	stw	SCRATCH_2_REGISTER, EXC_CR_OFFSET(r1)
	stw	SCRATCH_3_REGISTER, EXC_CTR_OFFSET(r1)
	stw	SCRATCH_4_REGISTER, EXC_XER_OFFSET(r1)
	stw	SCRATCH_5_REGISTER, EXC_LR_OFFSET(r1)

#ifdef __SPE__
	/* Save SPEFSCR and ACC */
	mfspr	SCRATCH_0_REGISTER, FSL_EIS_SPEFSCR
	evxor	SCRATCH_1_REGISTER, SCRATCH_1_REGISTER, SCRATCH_1_REGISTER
	evmwumiaa	SCRATCH_1_REGISTER, SCRATCH_1_REGISTER, SCRATCH_1_REGISTER
	stw	SCRATCH_0_REGISTER, PPC_EXC_SPEFSCR_OFFSET(r1)
	evstdd	SCRATCH_1_REGISTER, PPC_EXC_ACC_OFFSET(r1)
#endif

#ifdef PPC_MULTILIB_ALTIVEC
	/* Save volatile AltiVec context */
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(0)
	stvx	v0, r1, SCRATCH_0_REGISTER
	mfvscr	v0
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(1)
	stvx	v1, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(2)
	stvx	v2, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(3)
	stvx	v3, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(4)
	stvx	v4, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(5)
	stvx	v5, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(6)
	stvx	v6, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(7)
	stvx	v7, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(8)
	stvx	v8, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(9)
	stvx	v9, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(10)
	stvx	v10, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(11)
	stvx	v11, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(12)
	stvx	v12, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(13)
	stvx	v13, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(14)
	stvx	v14, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(15)
	stvx	v15, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(16)
	stvx	v16, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(17)
	stvx	v17, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(18)
	stvx	v18, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(19)
	stvx	v19, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VSCR_OFFSET
	stvewx	v0, r1, SCRATCH_0_REGISTER
#endif

#ifdef PPC_MULTILIB_FPU
	/* Save volatile FPU context */
	stfd	f0, PPC_EXC_MIN_FR_OFFSET(0)(r1)
	mffs	f0
	stfd	f1, PPC_EXC_MIN_FR_OFFSET(1)(r1)
	stfd	f2, PPC_EXC_MIN_FR_OFFSET(2)(r1)
	stfd	f3, PPC_EXC_MIN_FR_OFFSET(3)(r1)
	stfd	f4, PPC_EXC_MIN_FR_OFFSET(4)(r1)
	stfd	f5, PPC_EXC_MIN_FR_OFFSET(5)(r1)
	stfd	f6, PPC_EXC_MIN_FR_OFFSET(6)(r1)
	stfd	f7, PPC_EXC_MIN_FR_OFFSET(7)(r1)
	stfd	f8, PPC_EXC_MIN_FR_OFFSET(8)(r1)
	stfd	f9, PPC_EXC_MIN_FR_OFFSET(9)(r1)
	stfd	f10, PPC_EXC_MIN_FR_OFFSET(10)(r1)
	stfd	f11, PPC_EXC_MIN_FR_OFFSET(11)(r1)
	stfd	f12, PPC_EXC_MIN_FR_OFFSET(12)(r1)
	stfd	f13, PPC_EXC_MIN_FR_OFFSET(13)(r1)
	stfd	f0, PPC_EXC_MIN_FPSCR_OFFSET(r1)
#endif

	/* Increment ISR nest level and thread dispatch disable level */
	cmpwi	ISR_NEST_REGISTER, 0
#ifdef RTEMS_PROFILING
	cmpwi	cr2, ISR_NEST_REGISTER, 0
#endif
	addi	ISR_NEST_REGISTER, ISR_NEST_REGISTER, 1
	addi	DISPATCH_LEVEL_REGISTER, DISPATCH_LEVEL_REGISTER, 1
	stw	ISR_NEST_REGISTER, PER_CPU_ISR_NEST_LEVEL(SELF_CPU_REGISTER)
	stw	DISPATCH_LEVEL_REGISTER, PER_CPU_THREAD_DISPATCH_DISABLE_LEVEL(SELF_CPU_REGISTER)

	/* Switch stack if necessary */
	mfspr	SCRATCH_0_REGISTER, SPRG1
	iselgt	r1, r1, SCRATCH_0_REGISTER

#ifndef PPC_EXC_CONFIG_USE_FIXED_HANDLER
	/*
	 * Call high level exception handler.
	 *
	 * First parameter = exception frame pointer + FRAME_LINK_SPACE
	 * Second parameter = vector number (r4 is the VECTOR_REGISTER)
	 */
	addi	r3, FRAME_REGISTER, FRAME_LINK_SPACE
	rlwinm	VECTOR_REGISTER, VECTOR_REGISTER, 0, 27, 31
	mtctr	HANDLER_REGISTER
	bctrl
#else /* PPC_EXC_CONFIG_USE_FIXED_HANDLER */
	/* Call fixed high level handler */
	bl	bsp_interrupt_dispatch
#endif /* PPC_EXC_CONFIG_USE_FIXED_HANDLER */

#ifdef RTEMS_PROFILING
	/* Update profiling data if necessary */
	bne	cr2, .Lprofiling_done
	GET_SELF_CPU_CONTROL	r3
	mr	r4, ENTRY_INSTANT_REGISTER
	GET_TIME_BASE	r5
	bl	_Profiling_Outer_most_interrupt_entry_and_exit
.Lprofiling_done:
#endif /* RTEMS_PROFILING */

	/* Load some per-CPU variables */
	GET_SELF_CPU_CONTROL	SELF_CPU_REGISTER
	lbz	SCRATCH_0_REGISTER, PER_CPU_DISPATCH_NEEDED(SELF_CPU_REGISTER)
	lwz	SCRATCH_1_REGISTER, PER_CPU_ISR_DISPATCH_DISABLE(SELF_CPU_REGISTER)
	lwz	SCRATCH_2_REGISTER, PER_CPU_THREAD_DISPATCH_DISABLE_LEVEL(SELF_CPU_REGISTER)
	lwz	ISR_NEST_REGISTER, PER_CPU_ISR_NEST_LEVEL(SELF_CPU_REGISTER)

	/*
	 * Switch back to original stack (FRAME_REGISTER == r1 if we are still
	 * on the IRQ stack) and restore FRAME_REGISTER.
	 */
	mr	r1, FRAME_REGISTER
	lwz	FRAME_REGISTER, FRAME_OFFSET(r1)

	/* Decrement levels and determine thread dispatch state */
	xori	SCRATCH_0_REGISTER, SCRATCH_0_REGISTER, 1
	or	SCRATCH_0_REGISTER, SCRATCH_0_REGISTER, SCRATCH_1_REGISTER
	subi	DISPATCH_LEVEL_REGISTER, SCRATCH_2_REGISTER, 1
	or.	SCRATCH_0_REGISTER, SCRATCH_0_REGISTER, DISPATCH_LEVEL_REGISTER
	subi	ISR_NEST_REGISTER, ISR_NEST_REGISTER, 1

	/* Store thread dispatch disable and ISR nest levels */
	stw	DISPATCH_LEVEL_REGISTER, PER_CPU_THREAD_DISPATCH_DISABLE_LEVEL(SELF_CPU_REGISTER)
	stw	ISR_NEST_REGISTER, PER_CPU_ISR_NEST_LEVEL(SELF_CPU_REGISTER)

	/*
	 * Check thread dispatch necessary, ISR dispatch disable and thread
	 * dispatch disable level.
	 */
	bne	.Lthread_dispatch_done

	/* Thread dispatch */
.Ldo_thread_dispatch:

	/* Set ISR dispatch disable and thread dispatch disable level to one */
	li	SCRATCH_0_REGISTER, 1
	stw	SCRATCH_0_REGISTER, PER_CPU_ISR_DISPATCH_DISABLE(SELF_CPU_REGISTER)
	stw	SCRATCH_0_REGISTER, PER_CPU_THREAD_DISPATCH_DISABLE_LEVEL(SELF_CPU_REGISTER)

	/* Call _Thread_Do_dispatch(), this function will enable interrupts */
	mr	r3, SELF_CPU_REGISTER
	mfmsr	r4
	ori	r4, r4, MSR_EE
	bl	_Thread_Do_dispatch

	/* Disable interrupts */
	wrteei	0

	/* SELF_CPU_REGISTER is volatile, we must set it again */
	GET_SELF_CPU_CONTROL	SELF_CPU_REGISTER

	/* Check if we have to do the thread dispatch again */
	lbz	SCRATCH_0_REGISTER, PER_CPU_DISPATCH_NEEDED(SELF_CPU_REGISTER)
	cmpwi	SCRATCH_0_REGISTER, 0
	bne	.Ldo_thread_dispatch

	/* We are done with thread dispatching */
	li	SCRATCH_0_REGISTER, 0
	stw	SCRATCH_0_REGISTER, PER_CPU_ISR_DISPATCH_DISABLE(SELF_CPU_REGISTER)

.Lthread_dispatch_done:

#ifdef PPC_MULTILIB_ALTIVEC
	/* Restore volatile AltiVec context */
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VSCR_OFFSET
	lvewx	v0, r1, SCRATCH_0_REGISTER
	mtvscr	v0
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(0)
	lvx	v0, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(1)
	lvx	v1, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(2)
	lvx	v2, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(3)
	lvx	v3, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(4)
	lvx	v4, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(5)
	lvx	v5, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(6)
	lvx	v6, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(7)
	lvx	v7, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(8)
	lvx	v8, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(9)
	lvx	v9, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(10)
	lvx	v10, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(11)
	lvx	v11, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(12)
	lvx	v12, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(13)
	lvx	v13, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(14)
	lvx	v14, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(15)
	lvx	v15, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(16)
	lvx	v16, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(17)
	lvx	v17, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(18)
	lvx	v18, r1, SCRATCH_0_REGISTER
	li	SCRATCH_0_REGISTER, PPC_EXC_MIN_VR_OFFSET(19)
	lvx	v19, r1, SCRATCH_0_REGISTER
#endif

#ifdef PPC_MULTILIB_FPU
	/* Restore volatile FPU context */
	lfd	f0, PPC_EXC_MIN_FPSCR_OFFSET(r1)
	mtfsf	0xff, f0
	lfd	f0, PPC_EXC_MIN_FR_OFFSET(0)(r1)
	lfd	f1, PPC_EXC_MIN_FR_OFFSET(1)(r1)
	lfd	f2, PPC_EXC_MIN_FR_OFFSET(2)(r1)
	lfd	f3, PPC_EXC_MIN_FR_OFFSET(3)(r1)
	lfd	f4, PPC_EXC_MIN_FR_OFFSET(4)(r1)
	lfd	f5, PPC_EXC_MIN_FR_OFFSET(5)(r1)
	lfd	f6, PPC_EXC_MIN_FR_OFFSET(6)(r1)
	lfd	f7, PPC_EXC_MIN_FR_OFFSET(7)(r1)
	lfd	f8, PPC_EXC_MIN_FR_OFFSET(8)(r1)
	lfd	f9, PPC_EXC_MIN_FR_OFFSET(9)(r1)
	lfd	f10, PPC_EXC_MIN_FR_OFFSET(10)(r1)
	lfd	f11, PPC_EXC_MIN_FR_OFFSET(11)(r1)
	lfd	f12, PPC_EXC_MIN_FR_OFFSET(12)(r1)
	lfd	f13, PPC_EXC_MIN_FR_OFFSET(13)(r1)
#endif

#ifdef __SPE__
	/* Load SPEFSCR and ACC */
	lwz	DISPATCH_LEVEL_REGISTER, PPC_EXC_SPEFSCR_OFFSET(r1)
	evldd	HANDLER_REGISTER, PPC_EXC_ACC_OFFSET(r1)
#endif

	/*
	 * We must clear reservations here, since otherwise compare-and-swap
	 * atomic operations with interrupts enabled may yield wrong results.
	 * A compare-and-swap atomic operation is generated by the compiler
	 * like this:
	 *
	 *   .L1:
	 *     lwarx  r9, r0, r3
	 *     cmpw   r9, r4
	 *     bne-   .L2
	 *     stwcx. r5, r0, r3
	 *     bne-   .L1
	 *   .L2:
	 *
	 * Consider the following scenario.  A thread is interrupted right
	 * before the stwcx.  The interrupt updates the value using a
	 * compare-and-swap sequence.  Everything is fine up to this point.
	 * The interrupt performs now a compare-and-swap sequence which fails
	 * with a branch to .L2.  The current processor has now a reservation.
	 * The interrupt returns without further stwcx.  The thread updates the
	 * value using the unrelated reservation of the interrupt.
	 */
	li	SCRATCH_0_REGISTER, FRAME_OFFSET
	stwcx.	SCRATCH_0_REGISTER, r1, SCRATCH_0_REGISTER

	/* Load SRR0, SRR1, CR, CTR, XER, and LR */
	lwz	SCRATCH_0_REGISTER, SRR0_FRAME_OFFSET(r1)
	lwz	SCRATCH_1_REGISTER, SRR1_FRAME_OFFSET(r1)
	lwz	SCRATCH_2_REGISTER, EXC_CR_OFFSET(r1)
	lwz	SCRATCH_3_REGISTER, EXC_CTR_OFFSET(r1)
	lwz	SCRATCH_4_REGISTER, EXC_XER_OFFSET(r1)
	lwz	SCRATCH_5_REGISTER, EXC_LR_OFFSET(r1)

	PPC_GPR_LOAD	VECTOR_REGISTER, VECTOR_OFFSET(r1)
	PPC_GPR_LOAD	SELF_CPU_REGISTER, SELF_CPU_OFFSET(r1)
	PPC_GPR_LOAD	ISR_NEST_REGISTER, ISR_NEST_OFFSET(r1)

#ifdef __SPE__
	/* Restore SPEFSCR */
	mtspr	FSL_EIS_SPEFSCR, DISPATCH_LEVEL_REGISTER
#endif
	PPC_GPR_LOAD	DISPATCH_LEVEL_REGISTER, DISPATCH_LEVEL_OFFSET(r1)

#ifdef __SPE__
	/* Restore ACC */
	evmra	HANDLER_REGISTER, HANDLER_REGISTER
#endif
	PPC_GPR_LOAD	HANDLER_REGISTER, HANDLER_OFFSET(r1)

	/* Restore SRR0, SRR1, CR, CTR, XER, and LR */
	mtsrr0	SCRATCH_0_REGISTER
	PPC_GPR_LOAD	SCRATCH_0_REGISTER, SCRATCH_0_OFFSET(r1)
	mtsrr1	SCRATCH_1_REGISTER
	PPC_GPR_LOAD	SCRATCH_1_REGISTER, SCRATCH_1_OFFSET(r1)
	mtcr	SCRATCH_2_REGISTER
	PPC_GPR_LOAD	SCRATCH_2_REGISTER, SCRATCH_2_OFFSET(r1)
	mtctr	SCRATCH_3_REGISTER
	PPC_GPR_LOAD	SCRATCH_3_REGISTER, SCRATCH_3_OFFSET(r1)
	mtxer	SCRATCH_4_REGISTER
	PPC_GPR_LOAD	SCRATCH_4_REGISTER, SCRATCH_4_OFFSET(r1)
	mtlr	SCRATCH_5_REGISTER
	PPC_GPR_LOAD	SCRATCH_5_REGISTER, SCRATCH_5_OFFSET(r1)

#ifdef RTEMS_PROFILING
	/* Restore ENTRY_INSTANT_REGISTER */
	lwz	ENTRY_INSTANT_REGISTER, ENTRY_INSTANT_OFFSET(r1)
#endif /* RTEMS_PROFILING */

	/* Pop stack */
	addi	r1, r1, CPU_INTERRUPT_FRAME_SIZE

	/* Return */
	rfi

/* Symbol provided for debugging and tracing */
ppc_exc_wrap_async_normal_end:
