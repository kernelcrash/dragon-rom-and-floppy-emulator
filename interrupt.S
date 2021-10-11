#include "defines.h"
/*
   interrupt.S
   kernel@kernelcrash.com 2021

   - 6809 E interrupt processing
     - simple ROM emulation
     - Emulation of WD2793 Floppy controller (based on WD1793.c in fmsx by Marat Fayzullin)
     - Emulation of the 6 bit latch (for NMI masking mainly)




*/
// Reminders (to me)
//   - Dont put instructions that change status inside an IT block!!
//   - Dont use the 1f, 2b etc style local labels. Use the 1$:, 2$: ones as they have scope between
//     regular labels, whereas 1:, 2: are actually scoped to the whole file
//   - Do the PR bit clear early. Is hard to guarantee it works later. And I don't think a dsb in the
//     IRQ exit does anything 100% useful
//   - Be careful of the optimiser (in the C code, not the assembler code). Best idea is to get things
//     working with -O0, then turn the optimiser on when its all working.
//   - It is obvious to me that this code is super duper time critical. Adding features to the code
//     will eventually make it stop working because 'your code takes to long'. A 'read' from the Z80 side
//     is more time critical as you need to get data on the bus by a certain point and leave it there. Things
//     that I try to remember;
//       - avoid accessing RAM. No push/pop, subroutine calls
//       - try not to stuff up the pipeline


/* *********************************** */
	.syntax unified
	.cpu cortex-m4
//	.fpu softvfp
    	.fpu fpv4-sp-d16
	.thumb


	// expose init_fpu_regs so we can call it from main()
	.global	init_fpu_regs
	.global	init_fdc
	.global	e_follower
	.global copy_from_fdc_track_registers
	.global	update_fdc_track_registers
	.global	force
	.global	deactivate_fdc

	.global EXTI0_IRQHandler
	.global EXTI2_IRQHandler
	.global rom_base
	.global low_64k_base
	.global high_64k_base
	.global track_buffer
        .global main_thread_command
        .global main_thread_data
        .global main_thread_actual_track
	.global fdc_write_flush_count
	.global menu_ctrl_file_count
	.global	menu_ctrl_address_register
	.global disk_header


	.extern (rowcache)

/* *********************************** */

/* MACROS */

.macro mov32, reg, val
    movw \reg, #:lower16:\val
    movt \reg, #:upper16:\val
.endm

// manage what happens when E falls and we exit EXTI0
.macro unrolled_exit_EXTI0
	dsb
#if defined(DEBUG_EXTI0_END)
        vstr     reg_bit8_high,[r11,ODR]
#endif
// work out whether to fire NMI
	vmov	r1,reg_next_fdc_irq_drq
	vmov	r0,reg_fdc_status
	mov	r12,r1
	tst	reg_main_thread_command,#MAIN_COMMAND_SEEK_COMPLETE
	beq	2f
	//ITTT	NE
	mov	reg_main_thread_command,#0	// end the command
	lsl	r1,#2
	bfi	r1,r12,#0,#8	// reinsert the lowest 8 bits again (so that signals are repeated until changed)
	//ITTT	NE
	vmov	r3,reg_fdc_drq_all_off_mask
	orr	r1,r3			// queue up an INTRQ immediately
	and	r0,#~(F_BUSY)
2:
	vmov	reg_fdc_status,r0
	vmov	reg_next_fdc_irq_drq,r1

	// reg_next_fdc_irq_drq is effectively a queue of pairs of bits. One for INTRQ, the other for DRQ.
	// Ideally we just shift it every E clock and have an 'up to 12 cycle delay when needing to assert
	// these signals, but that appears to be too quick in some cases, hence the E counter means we 
	// only shift the queue every 2nd E clock, and get an up to 24 cycle delay
	vmov	r12,reg_e_counter
	adds	r12,#1
	vmov	reg_e_counter,r12
	ands	r12,#0x0003	// Most stuff works with 0x0001 here, but a a few things like the Infocom stuff requires 0x0003
	bne	1f
	mov	r3,r1
	lsls	r1,#2
	bfi	r1,r3,#0,#8	// reinsert the lowest 8 bits again (so that signals are repeated until changed)
	vmov	reg_next_fdc_irq_drq,r1

	lsrs	r1,#24	// bit 31 -> 7, bit 30 -> 6
	ands	r1,#0xc0

	// assign 'current' reg_fdc_irq_drq to what was shifted to bits 31 and 30 of reg_next_fdc_irq_drq
	vmov	reg_fdc_irq_drq,r1	// 
	vmov	r12,reg_fdc_system	//get NMI enable of latch
	tst	r12,#S_NMI
	ITE	NE
	eorne	r1,#NMI_HIGH		// if the NMI flag in the latch is high, flip the IRQ bit
	orreq	r1,#NMI_HIGH		// if the NMI flah in the latch is low, NMI must stay high
	str	r1,[r2,ODR]		// assume GPIOC is r2

#ifdef ENABLE_FDC_INTERRUPT_CCM_LOGGING
	movs	r0,#0x99		// special int logging
	log_r0_r1_to_ccm_uses_r12
#endif
1:	vmov 	r11,reg_fake_stack		// pop r11
	bx	lr
.endm




.macro clear_EXTI0_FTSR
	vstr	reg_zero,[r3,FTSR]
.endm

.macro set_EXTI0_FTSR
	vstr	reg_bit0_high,[r3,FTSR]
.endm



.macro databus_read_extra_delay
	.rept 0
        	nop
	.endr
.endm


// Use the 64K CCM ram as a sort of circular buffer for debugging
.macro log_r0_r1_to_ccm_uses_r12
        vmov    r12,reg_ccmram_log
	//tst	r12,#0x00010000		// effectively make it stop logging when it fills the 64K CCM
	//ITTT	EQ
        strb  r0,[r12],#1     // store the address 08 to 0F (ie 7ff8 to 7fff)
        strb  r1,[r12],#1     // store the byte written
        bfc     r12,#16,#8      // Really only need to clear bit 16
        vmov  reg_ccmram_log,r12
.endm

.section .rodata

rom_base:
// early versions of the code allowed you to embed a rom file here at compile time. I am now pulling roms from SD card
// and copying to ram
// be careful if you add roms and later delete them. The old ones might be still in the STM32 flash
//.incbin "roms/ghost-attack.rom"
//.incbin "roms/cave-hunter.rom"
//.incbin "roms/starship-chameleon.rom"
//.incbin "roms/dragondos-1-0.rom"

.section ccmram
low_64k_base:
	//.lcomm low_64k_base,0x10000

.section bss
	.lcomm high_64k_base,0x10000
	.lcomm track_buffer,2*18*256		// one track , both sides
	.lcomm disk_header,0x0c			// 12 byte VDK header
	


        .equ BACKUP_SRAM ,   0x40024000

        .equ PERIPH_BB_BASE     ,   0x42000000                                                                

        .equ PERIPH_BASE     ,   0x40000000                                                                
        .equ PERIPH_BASE_APB1,   (PERIPH_BASE + 0x00000)
        .equ PERIPH_BASE_APB2,   (PERIPH_BASE + 0x10000)
        .equ PERIPH_BASE_AHB1,   (PERIPH_BASE + 0x20000)
        .equ PERIPH_BASE_AHB2,   0x50000000
        .equ PERIPH_BASE_AHB3,   0x60000000

        .equ GPIOA_BASE,   (PERIPH_BASE_AHB1 + 0x0000)                                           
        .equ GPIOB_BASE,   (PERIPH_BASE_AHB1 + 0x0400)
        .equ GPIOC_BASE,   (PERIPH_BASE_AHB1 + 0x0800)
        .equ GPIOD_BASE,   (PERIPH_BASE_AHB1 + 0x0C00)
        .equ GPIOE_BASE,   (PERIPH_BASE_AHB1 + 0x1000)
        .equ GPIOF_BASE,   (PERIPH_BASE_AHB1 + 0x1400)
        .equ GPIOG_BASE,   (PERIPH_BASE_AHB1 + 0x1800)
        .equ GPIOH_BASE,   (PERIPH_BASE_AHB1 + 0x1C00)
        .equ GPIOI_BASE,   (PERIPH_BASE_AHB1 + 0x2000)

	.equ A_TO_B_OFFSET,     (GPIOB_BASE - GPIOA_BASE)

	.equ C_TO_D_OFFSET,     (GPIOD_BASE - GPIOC_BASE)
	.equ C_TO_E_OFFSET,     (GPIOE_BASE - GPIOC_BASE)

        .equ GPIOA_MODER     ,   GPIOA_BASE + 0x00
        .equ GPIOA_OTYPER    ,   GPIOA_BASE + 0x04
        .equ GPIOA_OSPEEDR   ,   GPIOA_BASE + 0x08
        .equ GPIOA_PUPDR     ,   GPIOA_BASE + 0x0C
        .equ GPIOA_IDR       ,   GPIOA_BASE + 0x10
        .equ GPIOA_ODR       ,   GPIOA_BASE + 0x14
        .equ GPIOA_BSRR      ,   GPIOA_BASE + 0x18
        .equ GPIOA_LCKR      ,   GPIOA_BASE + 0x1C
        .equ GPIOA_AFRL      ,   GPIOA_BASE + 0x20
        .equ GPIOA_AFRH      ,   GPIOA_BASE + 0x24

        .equ GPIOB_MODER     ,   GPIOB_BASE + 0x00
        .equ GPIOB_OTYPER    ,   GPIOB_BASE + 0x04
        .equ GPIOB_OSPEEDR   ,   GPIOB_BASE + 0x08
        .equ GPIOB_PUPDR     ,   GPIOB_BASE + 0x0C
        .equ GPIOB_IDR       ,   GPIOB_BASE + 0x10
        .equ GPIOB_ODR       ,   GPIOB_BASE + 0x14
        .equ GPIOB_BSRR      ,   GPIOB_BASE + 0x18
        .equ GPIOB_LCKR      ,   GPIOB_BASE + 0x1C
        .equ GPIOB_AFRL      ,   GPIOB_BASE + 0x20
        .equ GPIOB_AFRH      ,   GPIOB_BASE + 0x24

        .equ GPIOC_MODER     ,   GPIOC_BASE + 0x00
        .equ GPIOC_OTYPER    ,   GPIOC_BASE + 0x04
        .equ GPIOC_OSPEEDR   ,   GPIOC_BASE + 0x08
        .equ GPIOC_PUPDR     ,   GPIOC_BASE + 0x0C
        .equ GPIOC_IDR       ,   GPIOC_BASE + 0x10
        .equ GPIOC_ODR       ,   GPIOC_BASE + 0x14
        .equ GPIOC_BSRR      ,   GPIOC_BASE + 0x18
        .equ GPIOC_LCKR      ,   GPIOC_BASE + 0x1C
        .equ GPIOC_AFRL      ,   GPIOC_BASE + 0x20
        .equ GPIOC_AFRH      ,   GPIOC_BASE + 0x24

        .equ GPIOD_MODER     ,   GPIOD_BASE + 0x00
        .equ GPIOD_OTYPER    ,   GPIOD_BASE + 0x04
        .equ GPIOD_OSPEEDR   ,   GPIOD_BASE + 0x08
        .equ GPIOD_PUPDR     ,   GPIOD_BASE + 0x0C
        .equ GPIOD_IDR       ,   GPIOD_BASE + 0x10
        .equ GPIOD_ODR       ,   GPIOD_BASE + 0x14
        .equ GPIOD_BSRR      ,   GPIOD_BASE + 0x18
        .equ GPIOD_LCKR      ,   GPIOD_BASE + 0x1C
        .equ GPIOD_AFRL      ,   GPIOD_BASE + 0x20
        .equ GPIOD_AFRH      ,   GPIOD_BASE + 0x24

        .equ GPIOE_MODER     ,   GPIOE_BASE + 0x00
        .equ GPIOE_OTYPER    ,   GPIOE_BASE + 0x04
        .equ GPIOE_OSPEEDR   ,   GPIOE_BASE + 0x08
        .equ GPIOE_PUPDR     ,   GPIOE_BASE + 0x0C
        .equ GPIOE_IDR       ,   GPIOE_BASE + 0x10
        .equ GPIOE_ODR       ,   GPIOE_BASE + 0x14
        .equ GPIOE_BSRR      ,   GPIOE_BASE + 0x18
        .equ GPIOE_LCKR      ,   GPIOE_BASE + 0x1C
        .equ GPIOE_AFRL      ,   GPIOE_BASE + 0x20
        .equ GPIOE_AFRH      ,   GPIOE_BASE + 0x24

        .equ MODER           ,   0x00
        .equ OTYPER          ,   0x04
        .equ OSPEEDR         ,   0x08
        .equ IDR             ,   0x10
        .equ ODR             ,   0x14

        .equ SCB_AIRCR       , 0xE000ED0C


        .equ    EXTI_Line0      ,       0x00001
        .equ    EXTI_Line1      ,       0x00002
        .equ    EXTI_Line2      ,       0x00004
        .equ    EXTI_Line4      ,       0x00010
        .equ    EXTI            ,       0x40013c00
        .equ    EXTI_IMR        ,       EXTI + 0x00
        .equ    EXTI_PR         ,       EXTI + 0x14

	.equ	IMR		,	0x00
	.equ	EMR		,	0x04
	.equ	RTSR		,	0x08
	.equ	FTSR		,	0x0c
	.equ	PR		,	0x14


    .equ        SYSCFG_BASE,    0x40013800
    .equ        SYSCFG_EXTICR1, SYSCFG_BASE + 0x08




.section .data
// main_thread_command is actually a register now, but I left it here. These 32 bit longs must be in
// sequence. ie main_thread_command, then main_thread_data, then main_thread_actual_track
main_thread_command:
        .word   0x00000000                      // command word
main_thread_data:
        .word   0x00000000                      // command arg
main_thread_actual_track:
        .word   0x00000000                      // command arg
fdc_write_flush_count:
        .word   0x00000000
menu_ctrl_file_count:
        .word   0x00000000
menu_ctrl_address_register:
        .word   0x00000000


.section .text

.type e_follower, %function
.align 4
.thumb_func
e_follower:
	vmov    r11,reg_gpioa_base
	vmov	r2,reg_gpioc_base
1$:	ldr	r0,[r2,IDR]
	lsl	r0,#8
	str	r0,[r11,ODR]
	b	1$

.type copy_from_fdc_track_registers, %function
.align 4
.thumb_func
copy_from_fdc_track_registers:
	//ldr	r0,=main_thread_command
	mov32	r0,#main_thread_command

	vmov	r1,reg_fdc_actual_track
	str	r1,[r0,MAIN_STRUCT_DATA]

	bx	lr

.type update_fdc_track_registers, %function
.align 4
.thumb_func
update_fdc_track_registers:
	//ldr	r0,=main_thread_command
	mov32	r0,#main_thread_command

	ldr	r1,[r0,MAIN_STRUCT_ACTUAL_TRACK]			// get actual track that we seeked to
	vmov	reg_fdc_track,r1	 	// update the track register
	vmov	reg_fdc_actual_track,r1

	bx	lr

.type init_fpu_regs, %function
.align 4
.thumb_func
init_fpu_regs:
	movs	r0,#0
	vmov	reg_zero,r0

	movs	r0,#1
	vmov	reg_bit0_high,r0

	movs	r0,#2
	vmov	reg_bit1_high,r0

	mov32	r0,GPIOC_BASE
	vmov	reg_gpioc_base,r0

	movs	r0,#4
	vmov	reg_bit2_high,r0

	mov32	r0,GPIOA_BASE
	vmov	reg_gpioa_base,r0

	mov32	r0, high_64k_base
	vmov	reg_high_64k_base,r0

	mov32	r0, EXTI
	vmov	reg_exti_base,r0

	mov32	r0,0x55550020
	vmov	reg_moder_dataout,r0

	mov32	r0,0x00000020
	vmov	reg_moder_datain,r0


	//movs	r0,#0x40
	//vmov	reg_bit6_high,r0

	movs	r0,#0
	vmov	reg_e_counter,r0

	movs	r0,#0x100
	vmov	reg_bit8_high,r0

	mov32	r0,0x10000000
	vmov	reg_ccmram_log,r0

	// bit31 of reg_fdc_system is used to work out if the fdc is actually active. Default is off
	movs	r0,#0
	vmov	reg_fdc_system,r0

	bx	lr



.type init_fdc, %function
.align 4
.thumb_func
init_fdc:
	movs	r0,#F_TRACK0
	vmov	reg_fdc_status,r0

	movs	r0,#0
	vmov	reg_fdc_track,r0
	vmov	reg_fdc_actual_track,r0

	movs	r0,#0
	vmov	reg_fdc_sector,r0

	movs	r0,#0
	vmov	reg_fdc_data,r0

	movs	r0,#0
	vmov	reg_fdc_irq_drq,r0
	vmov	reg_next_fdc_irq_drq,r0

	movs	r0,#0
	vmov	reg_fdc_command,r0

	movs	r0,#0
	vmov	reg_fdc_read_length,r0
	vmov	reg_fdc_write_length,r0

	movs	r0,#0
	vmov	reg_track_buffer_ptr,r0

	movs	r0,#0
	orrs	r0,#S_FDC_PRESENT
	vmov	reg_fdc_system,r0

	mov32	r0,#0x55555555		// just leave DRQ bits if masked with this
	vmov	reg_fdc_irq_all_off_mask,r0

	mov32	r0,#0xaaaaaaaa		// just leave IRQ bits if masked with this
	vmov	reg_fdc_drq_all_off_mask,r0
	bx	lr

.type deactivate_fdc, %function
.align 4
.thumb_func
deactivate_fdc:
	movs	r0,#0			// set bit 31 low
	vmov	reg_fdc_system,r0
	bx	lr


// --------------------------------------------------------
// E Handler. Int on +ve edge. High time is roughly 550ns
.type EXTI0_IRQHandler, %function
.align 4
.thumb_func
EXTI0_IRQHandler:
	vmov	reg_fake_stack,r11		// effectively s30 is our 'stack'
	vmov	r11,reg_gpioa_base
#ifdef DEBUG_EXTI0_START
	vstr     reg_zero,[r11,ODR]		
#endif
	
	vmov	r2,reg_gpioc_base
clear_pending_e_int:
	vmov	r3,reg_exti_base		// s7 = EXTI
	vstr	reg_bit0_high,[r3,PR]	// clear interrupt

e_high:
	ldr	r0,[r2,C_TO_E_OFFSET+IDR]     // portE address bus
	ldr     r1,[r2,IDR]     // portC. 

1$:
        lsls    r3,r1,#30      // b2 (_P2)-> Carry, b1 (_CTS)-> pl/mi
	bcc	handle_fdc	// _P2 is low
	bmi	exit_EXTI0_not_a_cart_or_p2

// Handle cart
	tst	r1,#RW_MASK
	beq	exit_EXTI0	// no writing to cartridge

	vmov    r3,reg_high_64k_base
	bfc	r0,#14,#18	// ands    r0,#0x00003FFF.

	ldrb	r3,[r3,r0]	// get byte from rom in lower 8 bits
	lsls	r1,r3,#8

#ifdef DEBUG_EXTI0_ROM_ACCESS
	vstr     reg_zero,[r11,ODR]		
#endif
	vmov	r0,reg_moder_dataout
        str     r1,[r2, C_TO_D_OFFSET + ODR] // GPIOD ODR
        str     r0,[r2, C_TO_D_OFFSET + MODER]  // MODER set to outputs

	vmov	r3,reg_exti_base
	set_EXTI0_FTSR

        vstr     reg_bit0_high,[r3,EMR]   // EXTI_EMR - wait for an event rather than an interrupt on PC0

        vmov	r1,reg_moder_datain
	
	dsb
        sev     // set the event register
        wfe     // clear the event register
// So the 2nd wfe is meant to wait for the +ve edge, but if you get a spurious edge at exactly the time these instructions execute, it can slip through without waiting
        wfe     // wait for +ve edge of _MREQ

	databus_read_extra_delay

        str     r1,[r2, C_TO_D_OFFSET + MODER]  // MODER set to inputs

#ifdef DEBUG_EXTI0_ROM_ACCESS
        vstr     reg_bit8_high,[r11,ODR]
#endif
	clear_EXTI0_FTSR

exit_EXTI0:
	unrolled_exit_EXTI0

exit_EXTI0_not_a_cart_or_p2:
	vmov	r0,reg_fdc_system
	tst	r0,#S_FDC_PRESENT
	bne	1$
	// bit 31 of reg_fdc_system is low so, must be in ROM mode. 
	// toggle the CART pin. This triggers the BASIC rom to think a cartridge is plugged in. Not required for Dragon DOS ROM
	ldr	r0,[r2,ODR]
	eor	r0,#0x0040	// PC6
	str	r0,[r2,ODR]
1$:	unrolled_exit_EXTI0

// Emulation of the WD279x
handle_fdc:
#ifdef DEBUG_FDC
        vstr     reg_bit8_high,[r11,ODR]
	nop
	nop
        vstr     reg_zero,[r11,ODR]
#endif
	ands	r0,#0x001F	// drop address to bottom 5 bits
	tst	r1,#RW_MASK
	IT	NE
	orrne	r0,#0x20	// set bit 5 if a read

// Jump table for FDC command. Note for future. tbh is not that fast. It is pretty linear time wise though.
        tbh.w   [pc,r0,lsl #1]
.include "dragon_fdc_readwrite_branchtable.S"

menu_ctrl_unused_read:
fdc_unused_read:
        unrolled_exit_EXTI0

fdc_status_read:
#ifdef DEBUG_FDC_STATUS_READ2
	vstr	reg_bit8_high,[r11,ODR]
#endif

	vmov	r1,reg_fdc_status

// Make sure 2nd drive reports not ready
	vmov	r0,reg_fdc_system
	//tst	r0,#S_DRIVE
	tst	r0,#0x01		
	IT	NE
	orrne	r1,#F_NOTREADY		// set drive 1 to not ready

	vmov	r0,reg_fdc_command	// check what the last command was
	tst	r0,#0x80
	ITE	NE
	andne    r1,#(F_BUSY|F_NOTREADY|F_READONLY|F_DRQ)	//CMD >= 0x80
	eoreq	r1,#F_INDEX					//CMD < 0x80

2$:	vmov	reg_fdc_status,r1

#ifdef DEBUG_FDC_STATUS_READ
	vstr	reg_bit8_high,[r11,ODR]
#endif
	lsls	r1,#8
	vmov	r0,reg_moder_dataout
        str     r1,[r2, C_TO_D_OFFSET + ODR] // GPIOD ODR
        str     r0,[r2, C_TO_D_OFFSET + MODER]  // MODER set to outputs

	// reset IRQ
	vmov	r12,reg_fdc_irq_all_off_mask
	vmov	r3,reg_next_fdc_irq_drq
	and	r3,r12
	vmov	reg_next_fdc_irq_drq,r3

	vmov	r3,reg_exti_base
	set_EXTI0_FTSR
        vstr     reg_bit0_high,[r3,EMR]   // EXTI_EMR - wait for an event rather than an interrupt on PC0

#ifdef ENABLE_FDC_CCM_LOGGING
	movs	r0,#0x18
	lsrs	r1,#8
	log_r0_r1_to_ccm_uses_r12
#endif

        vmov	r1,reg_moder_datain
	
	dsb
        sev     // set the event register
        wfe     // clear the event register
// So the 2nd wfe is meant to wait for the +ve edge, but if you get a spurious edge at exactly the time these instructions execute, it can slip through without waiting
        wfe     // wait for +ve edge of _MREQ

	databus_read_extra_delay

        str     r1,[r2, C_TO_D_OFFSET + MODER]  // MODER set to inputs

	clear_EXTI0_FTSR

#ifdef DEBUG_FDC_STATUS_READ
	vstr	reg_zero,[r11,ODR]
#endif

        unrolled_exit_EXTI0

fdc_track_read:
	vmov	r1,reg_fdc_track

// get it out on the bus early

	lsls	r1,#8
	vmov	r0,reg_moder_dataout
        str     r1,[r2, C_TO_D_OFFSET + ODR] // GPIOD ODR
        str     r0,[r2, C_TO_D_OFFSET + MODER]  // MODER set to outputs

#ifdef ENABLE_FDC_CCM_LOGGING
	movs	r0,#0x19
	lsrs	r1,#8
	log_r0_r1_to_ccm_uses_r12
#endif

	vmov	r3,reg_exti_base
	set_EXTI0_FTSR

        vstr     reg_bit0_high,[r3,EMR]   // EXTI_EMR - wait for an event rather than an interrupt on PC0

        vmov	r1,reg_moder_datain
	
	dsb
        sev     // set the event register
        wfe     // clear the event register
// So the 2nd wfe is meant to wait for the +ve edge, but if you get a spurious edge at exactly the time these instructions execute, it can slip through without waiting
        wfe     // wait for +ve edge of _MREQ

	databus_read_extra_delay

        str     r1,[r2, C_TO_D_OFFSET + MODER]  // MODER set to inputs

	clear_EXTI0_FTSR
        unrolled_exit_EXTI0

fdc_sector_read:
	vmov	r1,reg_fdc_sector

	lsls	r1,#8
	vmov	r0,reg_moder_dataout
        str     r1,[r2, C_TO_D_OFFSET + ODR] // GPIOD ODR
        str     r0,[r2, C_TO_D_OFFSET + MODER]  // MODER set to outputs

#ifdef ENABLE_FDC_CCM_LOGGING
	movs	r0,#0x1a
	lsrs	r1,#8
	log_r0_r1_to_ccm_uses_r12
#endif

	vmov	r3,reg_exti_base
	set_EXTI0_FTSR

        vstr     reg_bit0_high,[r3,EMR]   // EXTI_EMR - wait for an event rather than an interrupt on PC0

        vmov	r1,reg_moder_datain
	
	dsb
        sev     // set the event register
        wfe     // clear the event register
// So the 2nd wfe is meant to wait for the +ve edge, but if you get a spurious edge at exactly the time these instructions execute, it can slip through without waiting
        wfe     // wait for +ve edge of _MREQ

	databus_read_extra_delay

        str     r1,[r2, C_TO_D_OFFSET + MODER]  // MODER set to inputs

	clear_EXTI0_FTSR
        unrolled_exit_EXTI0

fdc_data_read:
#ifdef DEBUG_FDC_DATA_READ_START
	vstr     reg_zero,[r11,ODR]		
#endif
	mov32	r0,#track_buffer
	vmov	r3,reg_track_buffer_ptr
	movs	r1,#0

	vmov	r12,reg_fdc_read_length
	cmp	r12,#0
	ITE	NE
	ldrbne	r1,[r0,r3]		// get byte from the track buffer
	vmoveq	r1,reg_fdc_data		// or get the data register
	vmov	reg_fdc_data,r1		// update the data register

	lsls	r1,#8
	vmov	r0,reg_moder_dataout
        str     r1,[r2, C_TO_D_OFFSET + ODR] // GPIOD ODR
        str     r0,[r2, C_TO_D_OFFSET + MODER]  // MODER set to outputs

	// reset DRQ
	vmov	r12,reg_fdc_drq_all_off_mask
	vmov	r3,reg_next_fdc_irq_drq
	and	r3,r12
	vmov	reg_next_fdc_irq_drq,r3

	vmov	r12,reg_fdc_command	// check what the last command was
	tst	r12,#0x80
	beq	10$
	// previous command was >=0x80 (eg. read or write sector)
	cmp	r12,#0xd0
	beq	10$	
	vmov	r12,reg_next_fdc_irq_drq
	orr	r12,#(WD1793_DRQ)
	vmov	reg_next_fdc_irq_drq,r12
10$:
	vmov	r12,reg_fdc_read_length
	cmp	r12,#0
	beq	2$

#ifdef DEBUG_FDC_DATA_READ
        vstr    reg_zero,[r11,ODR]
#endif
	vmov	r3,reg_track_buffer_ptr
	vmov	r12,reg_fdc_read_length
	adds	r3,#1			// incr the track_buffer_ptr
	subs	r12,#1			// decr the read length
	vmov	reg_track_buffer_ptr,r3	// update the track_buffer_ptr
	vmov	r3,reg_fdc_sector	// get current sector num
	vmov	reg_fdc_read_length,r12
	mov	r0,#0x0ff		// 256 byte sectors
	tst	r12,r0		// see if bottom 8 bits are clear
	IT	EQ
// must have crossed a sector boundary. Everything seems to just read one sector at a time, so leaving off
	addseq	r3,#1		// incr the sector number
	vmov	reg_fdc_sector,r3
	cmp	r12,#0
	bne	2$
// All data read
	vmov	r12,reg_fdc_status
	ands	r12,#~(F_DRQ|F_BUSY)
	vmov	reg_fdc_status,r12
	
	vmov	r12,reg_next_fdc_irq_drq
	and	r12,#~(WD1793_DRQ)		// we might have set DRQ earlier. Turn it off
	orr	r12,#WD1793_IRQ
	vmov	reg_next_fdc_irq_drq,r12

// Put some data on the databus
2$:


#ifdef ENABLE_FDC_CCM_LOGGING
	movs	r0,#0x1b
	lsrs	r1,#8
	log_r0_r1_to_ccm_uses_r12

#endif

	vmov	r3,reg_exti_base
	set_EXTI0_FTSR

        vstr     reg_bit0_high,[r3,EMR]   // EXTI_EMR - wait for an event rather than an interrupt on PC0

        vmov	r1,reg_moder_datain
	
	dsb
        sev     // set the event register
        wfe     // clear the event register
// So the 2nd wfe is meant to wait for the +ve edge, but if you get a spurious edge at exactly the time these instructions execute, it can slip through without waiting
        wfe     // wait for +ve edge of _MREQ

	databus_read_extra_delay

        str     r1,[r2, C_TO_D_OFFSET + MODER]  // MODER set to inputs

	clear_EXTI0_FTSR

        unrolled_exit_EXTI0


menu_ctrl_unused_write:
fdc_unused_write:
        unrolled_exit_EXTI0

fdc_command_write:
	// D->IRQ=0
	// This stuff kills the queue of interrupts

	ldr	r1,[r2,C_TO_D_OFFSET+IDR]	// read databus again
	lsrs	r1,r1,#8

#ifdef ENABLE_FDC_CCM_LOGGING
	orrs	r0,#0x80
        log_r0_r1_to_ccm_uses_r12
#endif

	mov	r0,r1

	ands	r0,#0xf0
	cmp	r0,#0xD0	// Force interrupt command
	bne	1$
// D0 Force interrupt
	//D->RDLength = 0
	movs	r12,#0
	vmov	reg_fdc_read_length,r12

	// D->Cmd=0xD0;
	vmov 	reg_fdc_command,r0

	vmov	r0,reg_fdc_status
	tst	r0,#F_BUSY
	beq	5$
// busy was set, so clear it
	ands	r0,#~F_BUSY		// clear busy bit
	vmov 	reg_fdc_status,r0
	b	6$
// busy was clear
5$:
	//clear all bits. D->R[0]=D->Track[D->Drive]? 0:F_TRACK0
	movs	r0,#0
	vmov	r1,reg_fdc_actual_track
	cmp	r1, #0
	IT	EQ
	moveq	r0,#F_TRACK0
	vmov	reg_fdc_status,r0

// if(V&C_IRQ) D->IRQ=WD1793_IRQ;
6$:	vmov	r0,reg_next_fdc_irq_drq
	tst	r3,#C_IRQ
	ITT	NE
	orrne	r0,#WD1793_IRQ
	vmovne	reg_next_fdc_irq_drq,r0

        unrolled_exit_EXTI0

// all commands except D0
1$:
	// pretty much all of them will generally reset NMI and set DRQ off
	movs	r3,#0
	vmov	reg_next_fdc_irq_drq,r3


	vmov	r12,reg_fdc_status
	tst	r12, #F_BUSY
	beq	2$
	// exit if busy
        unrolled_exit_EXTI0
2$:
	movs	r12,#0
	vmov	reg_fdc_status,r12	// reset status
	vmov	reg_fdc_command,r1	// save the full command
	// r0 bits 7 to 4 should be the command
	lsrs	r0,#4
        tbh.w   [pc,r0,lsl #1]
.include "dragon_fdc_command_branchtable.S"

fdc_command_unused:
	unrolled_exit_EXTI0

fdc_command_restore:
	ldr	r3,=main_thread_command
	mov	r1,#MAIN_THREAD_SEEK_COMMAND
        vstr    reg_zero,[r3, MAIN_STRUCT_DATA]           // write cylinder to seek to 
	mov	reg_main_thread_command,r1
	vmov	r12,reg_fdc_status
	orrs	r12,#F_BUSY
	vmov	reg_fdc_status,r12
	unrolled_exit_EXTI0


fdc_command_seek:
	vmov	reg_fdc_read_length,reg_zero
	vmov	r0,reg_fdc_data		// The track num would have been loaded into 'data'
	ldr	r3,=main_thread_command
	mov	r1,#MAIN_THREAD_SEEK_COMMAND
        str     r0,[r3, MAIN_STRUCT_DATA]           // write cylinder to seek to 
	mov	reg_main_thread_command,r1
	vmov	r12,reg_fdc_status
	orrs	r12,#F_BUSY
	vmov	reg_fdc_status,r12
	unrolled_exit_EXTI0


fdc_command_step:
fdc_command_step_and_update:
fdc_command_step_in:
fdc_command_step_in_and_update:
fdc_command_step_out:
fdc_command_step_out_and_update:
	tst	r1,#0x40
	bne	1$
// step . V=(V&~0x20)|D->LastS;
	ands	r1, #~0x20	// clear bit 5
	// 
	vmov	r12,reg_fdc_system
	tst	r12,#S_LASTSTEPDIR
	IT	NE
	orrne	r1,#0x20	// set bit 5 based on the last step
	b	2$

// step in or out . D->LastS=V&0x20
1$:
	vmov	r12,reg_fdc_system
	tst	r3,#0x20	// get the step direction
	ITE	NE
	orrne	r12,#S_LASTSTEPDIR
	andeq	r12,#~S_LASTSTEPDIR
	vmov	reg_fdc_system,r12
2$:
	vmov	r0,reg_fdc_actual_track
	//tst	r12,#S_DRIVE	// check if drive 0 or 1
	tst	r12,#0x01	// check if drive 0 or 1
	bne	3$
	tst	r1,#0x20
	ITE	NE
	subne	r0,#1		// decr track num
	addeq	r0,#1		// incr track num
	tst	r0,#0x80000000		//check if we just went negative
	IT	NE
	movne	r0,#0			// reset to track0

	vmov	reg_fdc_actual_track,r0
3$:
	tst	r1,#C_SETTRACK
	IT	NE
	vmovne	reg_fdc_track,r0

// zero most of fdc_status
	movs	r1,#F_INDEX
	//tst	r12,#S_DRIVE		// r12 still has the system register
	vmov	reg_fdc_status,r1

	ldr	r3,=main_thread_command
	movs	r1,#MAIN_THREAD_SEEK_COMMAND
        str     r0,[r3, MAIN_STRUCT_DATA]           // write cylinder to seek to 
        mov	reg_main_thread_command,r1

	vmov	r12,reg_fdc_status
	orrs	r12,#F_BUSY
	vmov	reg_fdc_status,r12

	unrolled_exit_EXTI0



fdc_command_read_sector:
	// reset DRQ
	vmov	r12,reg_fdc_drq_all_off_mask
	vmov	r3,reg_next_fdc_irq_drq
	and	r3,r12
	orr	r3,#WD1793_DRQ
	vmov	reg_next_fdc_irq_drq,r3
	// assume 256 byte sector
	movs	r0,#0		// set to beginning of track

	vmov	r12,reg_fdc_system
	tst	r1,#C_UPDATE_SSO
	ITTE	NE
	addne	r0,#(18*256)
	orrne 	r12,#S_SIDE
	andeq 	r12,#~(S_SIDE)
	vmov	reg_fdc_system,r12

3$:	vmov	r12,reg_fdc_sector
	subs	r12, #1		// sectors are 1 to 18. We need 0 to 17
	IT	MI
	movmi	r12,#0		// adjust it back to zero if it went negative

	lsls	r12,#8		// * 256
	adds	r0,r12
	vmov	reg_track_buffer_ptr,r0

	movs	r0,#256		// one sector
	tst	r1,#0x10	// Are we reading multiple sectors which I think is 'all sectors until end of track on one side
	beq	1$
	movs	r0,#8
	vmov	r3,reg_fdc_sector
	subs	r0,r3
	adds	r0,#1
	lsls	r0,#8		// * 256
1$:	vmov	reg_fdc_read_length,r0

// flags
	vmov	r0,reg_fdc_status
	orrs	r0,#(F_BUSY|F_DRQ)
	vmov	reg_fdc_status,r0

	unrolled_exit_EXTI0

fdc_command_write_sector:
	// reset DRQ
	vmov	r12,reg_fdc_drq_all_off_mask
	vmov	r3,reg_next_fdc_irq_drq
	and	r3,r12
	orr	r3,#WD1793_DRQ
	vmov	reg_next_fdc_irq_drq,r3

	// assume 256 byte sector
	movs	r0,#0		// set to beginning of track

	vmov	r12,reg_fdc_system
	tst	r1,#C_UPDATE_SSO
	ITTE	NE
	addne	r0,#(18*256)
	orrne 	r12,#S_SIDE
	andeq 	r12,#~(S_SIDE)
	vmov	reg_fdc_system,r12

3$:	vmov	r12,reg_fdc_sector
	subs	r12, #1		// sectors are 1 to 18. We need 0 to 17
	IT	MI
	movmi	r12,#0		// adjust it back to zero if it went negative

	lsls	r12,#8		// * 256
	adds	r0,r12
	vmov	reg_track_buffer_ptr,r0

	movs	r0,#256		// one sector
	tst	r1,#0x10	// Are we writing multiple sectors which I think is 'all sectors until end of track on one side
	beq	1$
	movs	r0,#8
	vmov	r3,reg_fdc_sector
	subs	r0,r3
	adds	r0,#1
	lsls	r0,#8		// * 256
1$:	vmov	reg_fdc_write_length,r0

// flags
	vmov	r0,reg_fdc_status
	orrs	r0,#(F_BUSY|F_DRQ)
	vmov	reg_fdc_status,r0

        unrolled_exit_EXTI0

fdc_command_read_address:
	
        unrolled_exit_EXTI0


// ---------------------

fdc_track_write:
	ldr	r1,[r2,C_TO_D_OFFSET+IDR]	// read databus again
	lsrs	r1,r1,#8

#ifdef ENABLE_FDC_CCM_LOGGING
	log_r0_r1_to_ccm_uses_r12
#endif

	vmov	r0,reg_fdc_status
	tst	r0,#F_BUSY
	IT	EQ
	vmoveq	reg_fdc_track,r1		// upate track if not busy

        unrolled_exit_EXTI0

fdc_sector_write:
	ldr	r1,[r2,C_TO_D_OFFSET+IDR]	// read databus again
	lsrs	r1,r1,#8

#ifdef ENABLE_FDC_CCM_LOGGING
	log_r0_r1_to_ccm_uses_r12
#endif

	vmov	r0,reg_fdc_status
	tst	r0,#F_BUSY
	IT	EQ
	vmoveq	reg_fdc_sector,r1

        unrolled_exit_EXTI0

fdc_data_write:
	ldr	r1,[r2,C_TO_D_OFFSET+IDR]	// read databus again
	lsrs	r1,r1,#8

	// reset DRQ
	vmov	r12,reg_fdc_drq_all_off_mask
	vmov	r3,reg_next_fdc_irq_drq
	and	r3,r12
	vmov	reg_next_fdc_irq_drq,r3

// make sure we only queue up a DRQ if we are writing sectors
	vmov	r12,reg_fdc_command
	tst	r12,#0x80
	beq	10$
	cmp	r12,#0xd0
	beq	10$	
        vmov    r12, reg_next_fdc_irq_drq
        orr     r12,#(WD1793_DRQ)
        vmov    reg_next_fdc_irq_drq,r12
10$:
#ifdef ENABLE_FDC_CCM_LOGGING
	log_r0_r1_to_ccm_uses_r12
#endif

	vmov	reg_fdc_data,r1
	vmov	r12,reg_fdc_write_length
	cmp	r12,#0
	bne	1$
	unrolled_exit_EXTI0

// WRITE DATA TO SECTOR. non zero write length
1$:
	mov32	r0,#track_buffer
	vmov	r3,reg_track_buffer_ptr
	strb	r1,[r0,r3]		// store byte in track buffer

	adds	r3,#1			// incr the track_buffer_ptr
	subs	r12,#1			// decr the write length
	vmov	reg_track_buffer_ptr,r3	// update the track_buffer_ptr
	vmov	r3,reg_fdc_sector	// get current sector num
	vmov	reg_fdc_write_length,r12
	mov	r0,#0x0ff
	tst	r12,r0		// see if bottom 8 bits are clear
	IT	EQ
// must have crossed a sector boundary
	addseq	r3,#1		// incr the sector number
	vmov	reg_fdc_sector,r3
	cmp	r12,#0
	bne	2$
// All data written
        vmov    r12,reg_fdc_status
        ands    r12,#~(F_DRQ|F_BUSY)
        vmov    reg_fdc_status,r12

        vmov    r12,reg_next_fdc_irq_drq
	and	r12,#~(WD1793_DRQ)
        orr     r12,#WD1793_IRQ
        vmov    reg_next_fdc_irq_drq,r12

	mov32	r0,#FDC_WRITE_FLUSH_DEFAULT
	ldr	r1,=fdc_write_flush_count
	str	r0,[r1]				// trigger write after some delay
2$:
        unrolled_exit_EXTI0

// -----------------

// Update the latch.
fdc_system_write:
	ldr	r1,[r2,C_TO_D_OFFSET+IDR]	// read databus again
	lsrs	r1,r1,#8
#ifdef ENABLE_FDC_CCM_LOGGING
	log_r0_r1_to_ccm_uses_r12
#endif

	vmov	r12,reg_fdc_system
	and	r12,#~(S_NMI|S_PRECOMP|S_DENSITY|S_MOTOR|S_DRIVE)
	and	r1,#(S_NMI|S_PRECOMP|S_DENSITY|S_MOTOR|S_DRIVE)
	orr	r12,r1
	vmov	reg_fdc_system,r12

#ifdef ENABLE_FDC_CCM_LOGGING
	//log_r0_r1_to_ccm_uses_r12
#endif

        unrolled_exit_EXTI0

//---------------------

menu_ctrl_command_write:
	ldr	r1,[r2,C_TO_D_OFFSET+IDR]	// read databus again
	lsrs	r1,r1,#8

	tst	r1,#LOAD_DIRECTORY_COMMAND_MASK
	beq	1$
	mov	reg_main_thread_command,#MAIN_THREAD_COMMAND_LOAD_DIRECTORY
	b	2$
1$:     tst     r1,#LOAD_ROM_COMMAND_MASK
        beq     2$
        mov     reg_main_thread_command,#MAIN_THREAD_COMMAND_LOAD_ROM
2$:	unrolled_exit_EXTI0


menu_ctrl_address_register_lsb_write:
menu_ctrl_address_register_msb_write:
	ldr	r1,[r2,C_TO_D_OFFSET+IDR]	// read databus again
	lsrs	r1,r1,#8
	mov32	r3,#menu_ctrl_address_register
	ands	r0,#1
	strb	r1,[r3,r0]
	unrolled_exit_EXTI0

menu_ctrl_data_register_write:
	ldr	r1,[r2,C_TO_D_OFFSET+IDR]	// read databus again
	lsrs	r1,r1,#8

	movs	r0,#0x0
	mov32	r3,#menu_ctrl_address_register
	ldr	r0,[r3]		// grab it as a word

	mov32	r12,#CCMRAM_BASE+0x4000
	strb	r1,[r12,r0]
	adds	r0,#1
	bfc     r0,#14,#18	// same as and 0x3fff
	str	r0,[r3]
	unrolled_exit_EXTI0

menu_ctrl_command_read:
	movs	r1,#0x80
	tst	reg_main_thread_command,#MAIN_COMMAND_LOAD_DIRECTORY_COMPLETE
	beq	1$
	movs	r1,#0	// send bit 7 low
	movs	reg_main_thread_command,#0
1$:	
// get it out on the bus early

	lsls	r1,#8
	vmov	r0,reg_moder_dataout
        str     r1,[r2, C_TO_D_OFFSET + ODR] // GPIOD ODR
        str     r0,[r2, C_TO_D_OFFSET + MODER]  // MODER set to outputs

	vmov	r3,reg_exti_base
	set_EXTI0_FTSR

        vstr     reg_bit0_high,[r3,EMR]   // EXTI_EMR - wait for an event rather than an interrupt on PC0

        vmov	r1,reg_moder_datain
	
	dsb
        sev     // set the event register
        wfe     // clear the event register
// So the 2nd wfe is meant to wait for the +ve edge, but if you get a spurious edge at exactly the time these instructions execute, it can slip through without waiting
        wfe     // wait for +ve edge of _MREQ

	databus_read_extra_delay

        str     r1,[r2, C_TO_D_OFFSET + MODER]  // MODER set to inputs

	clear_EXTI0_FTSR
        unrolled_exit_EXTI0

menu_ctrl_file_count_lsb_read:
menu_ctrl_file_count_msb_read:
	mov32	r3,#menu_ctrl_file_count
	ands	r0,#0x01
	ldrb	r1,[r3,r0]

// get it out on the bus early

	lsls	r1,#8
	vmov	r0,reg_moder_dataout
        str     r1,[r2, C_TO_D_OFFSET + ODR] // GPIOD ODR
        str     r0,[r2, C_TO_D_OFFSET + MODER]  // MODER set to outputs

	vmov	r3,reg_exti_base
	set_EXTI0_FTSR

        vstr     reg_bit0_high,[r3,EMR]   // EXTI_EMR - wait for an event rather than an interrupt on PC0

        vmov	r1,reg_moder_datain
	
	dsb
        sev     // set the event register
        wfe     // clear the event register
// So the 2nd wfe is meant to wait for the +ve edge, but if you get a spurious edge at exactly the time these instructions execute, it can slip through without waiting
        wfe     // wait for +ve edge of _MREQ

	databus_read_extra_delay

        str     r1,[r2, C_TO_D_OFFSET + MODER]  // MODER set to inputs

	clear_EXTI0_FTSR
        unrolled_exit_EXTI0

menu_ctrl_data_register_read:
	movs	r0,#0x0
	mov32	r3,#menu_ctrl_address_register
	ldr	r0,[r3]		// grab it as a word

	mov32	r12,#CCMRAM_BASE+0x4000
	movs	r1,#0x0
	ldrb	r1,[r12,r0]
	adds	r0,#1
	bfc     r0,#14,#18	// same as and 0x3fff
	str	r0,[r3]
	

// get it out on the bus early

	lsls	r1,#8
	vmov	r0,reg_moder_dataout
        str     r1,[r2, C_TO_D_OFFSET + ODR] // GPIOD ODR
        str     r0,[r2, C_TO_D_OFFSET + MODER]  // MODER set to outputs

	vmov	r3,reg_exti_base
	set_EXTI0_FTSR

        vstr     reg_bit0_high,[r3,EMR]   // EXTI_EMR - wait for an event rather than an interrupt on PC0

        vmov	r1,reg_moder_datain
	
	dsb
        sev     // set the event register
        wfe     // clear the event register
// So the 2nd wfe is meant to wait for the +ve edge, but if you get a spurious edge at exactly the time these instructions execute, it can slip through without waiting
        wfe     // wait for +ve edge of _MREQ

	databus_read_extra_delay

        str     r1,[r2, C_TO_D_OFFSET + MODER]  // MODER set to inputs

	clear_EXTI0_FTSR
        unrolled_exit_EXTI0
