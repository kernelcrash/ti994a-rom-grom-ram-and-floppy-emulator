#include "defines.h"
/*
   interrupt.S
   kernel@kernelcrash.com 2023


*/
// Reminders (to me)
//   - Dont put instructions that change status inside an IT block!!
//   - Dont use the 1f, 2b etc style local labels. Use the 1$:, 2$: ones as they have scope between
//     regular labels, whereas 1:, 2: are actually scoped to the whole file (except in a macro
//     where you have to use 1f, 2b etc
//   - Do the PR bit clear early. Is hard to guarantee it works later. And I don't think a dsb in the
//     IRQ exit does anything 100% useful
//   - Be careful of the optimiser (in the C code, not the assembler code). Best idea is to get things
//     working with -O0, then turn the optimiser on when its all working.
//   - It is obvious to me that this code is super duper time critical. Adding features to the code
//     will eventually make it stop working because 'your code takes to long'. 
//   - Also
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
	.global copy_from_fdc_track_registers
	.global	update_fdc_track_registers
	.global	update_fdc_track_registers_from_data
	.global	update_fdc_track_from_intended_track_register
	.global reset_rom_base_offset
	.global	force
	.global	deactivate_fdc

	.global EXTI0_IRQHandler
	.global EXTI3_IRQHandler
	.global rom_base
	.global grom_base
	.global dsr_base
	.global track_buffer
        .global main_thread_command
        .global main_thread_data
        .global main_thread_actual_track
	.global fdc_write_flush_count
	.global fdc_write_dirty_bits
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

// Manage end of _MEMEN
.macro unrolled_exit_EXTI0
        //dsb
#if defined(DEBUG_EXTI0_END)
        vstr     reg_bit8_high,[r11,ODR]
#endif
	vmov    r0,reg_fdc_status
        tst     reg_main_thread_command,#MAIN_COMMAND_SEEK_COMPLETE
        beq     2f
        //ITTT  NE
        mov     reg_main_thread_command,#0      // end the command
        movs    r3,#IRQ_ON + WAIT_ZERO_CYCLES_UNTIL_CHANGE
        vmov    reg_fdc_irq_countdown,r3
        and     r0,#~(F_BUSY)

	//vmov	reg_fdc_track,reg_fdc_intended_track

	// work out whether the selected disk is at track 0
	mov32	r3,#main_thread_actual_track
	vmov	r1,reg_fdc_system

	tst	r1,#S_CRU_DISK_DRIVE_2			// DSK2
	IT	NE
	addne	r3,#4
	tst	r1,#S_CRU_DISK_DRIVE_3			// DSK3
	IT	NE
	addne	r3,#8
	ldr	r3,[r3]					// get the actual track for the selected disk

        cmp     r3,#0
        ITE     EQ
        orreq   r0,#F_TRACK0
        andne   r0,#~(F_TRACK0)
2:
	vmov    reg_fdc_status,r0

        vmov    r11,reg_fake_stack              // pop r11
        bx      lr
.endm







.macro databus_read_extra_delay
	.rept 1
        	nop
	.endr
.endm

// Use the 64K CCM ram as a sort of circular buffer for debugging, but use the lower 32K only as we map the top 32K of CCM to the TI's 32K expansion
.macro log_r0_r1_to_ccm_uses_r12
        vmov    r12,reg_ccmram_log
	tst	r12,#0x00008000		// effectively make it stop logging when it fills the 64K CCM
	ITTT	EQ
        strbeq  r0,[r12],#1     // store r0
        strbeq  r1,[r12],#1     // store r1
        bfceq     r12,#15,#9      // Really only need to clear bit 15
        vmov  reg_ccmram_log,r12
.endm

.section .rodata

.section ccmram

.section bss
	.lcomm dsr_base,0x2000
	.lcomm rom_base,0x8000
	.lcomm grom_base,0xA000
	.lcomm track_buffer,6*SIZEOF_ONE_DISK_TRACK		// two tracks for each of the 3 disks
	.align 4
	.lcomm disk_header,0x08			// 6 byte read address header
	

        .equ CCM_BASE ,   0x10000000

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
        .word   0x00000000                      // DSK1 actual track
	.word   0x00000000			// DSK2 actual track
	.word   0x00000000			// DSK3 actual track
fdc_write_flush_count:
        .word   0x00000000
fdc_write_dirty_bits:
        .word   0x00000000			// this must immediately follow fdc_write_flush_count. The lower 3 bits determine which drive(s) have been written too, so when the flush count gets to zero, it determines which drives need to be written to
menu_ctrl_file_count:
        .word   0x00000000
menu_ctrl_address_register:
        .word   0x00000000


.section .text


.type reset_rom_base_offset, %function
.align 4
.thumb_func
reset_rom_base_offset:
	movs	r0,0
	vmov	reg_rom_base_offset,r0
	bx	lr


.type copy_from_fdc_track_registers, %function
.align 4
.thumb_func
copy_from_fdc_track_registers:
        //ldr   r0,=main_thread_command
        mov32   r0,#main_thread_command

        //vmov    r1,reg_fdc_actual_track
        vmov    r1,reg_fdc_track
        str     r1,[r0,MAIN_STRUCT_DATA]

        bx      lr

// TODO come back to this
.type update_fdc_track_registers_from_data, %function
.align 4
.thumb_func
update_fdc_track_registers_from_data:
	//ldr   r0,=main_thread_command
	mov32   r0,#main_thread_command

	ldr     r1,[r0,MAIN_STRUCT_DATA]                        // get actual track that we seeked to
	ands	r1,#0xff
	vmov    reg_fdc_track,r1                // update the track register
	//vmov    reg_fdc_actual_track,r1
	bx      lr



.type update_fdc_track_registers, %function
.align 4
.thumb_func
update_fdc_track_registers:
	//ldr   r0,=main_thread_command
	mov32   r0,#main_thread_command

	ldr     r1,[r0,MAIN_STRUCT_ACTUAL_TRACK]                        // get actual track that we seeked to
	vmov    reg_fdc_track,r1                // update the track register
	//vmov    reg_fdc_actual_track,r1

	bx      lr

.type update_fdc_track_from_intended_track_register, %function
.align 4
.thumb_func
update_fdc_track_from_intended_track_register:
	//ldr   r0,=main_thread_command
	vmov	reg_fdc_track,reg_fdc_intended_track
	bx      lr

.type init_fpu_regs, %function
.align 4
.thumb_func
init_fpu_regs:
	movs	r0,#0
	vmov	reg_zero,r0

	movs	r0,#1
	vmov	reg_bit0_high,r0

	movs	r0,#0
	vmov	reg_grom_address_counter,r0

	mov32	r0,GPIOC_BASE
	vmov	reg_gpioc_base,r0

	mov32	r0,GPIOA_BASE
	vmov	reg_gpioa_base,r0

	movs	r0,#0
	vmov	reg_rom_base_offset,r0

	mov32	r0,rom_base
	vmov	reg_rom_base,r0

	mov32	r0, EXTI
	vmov	reg_exti_base,r0

	mov32	r0,0x55550020
	vmov	reg_moder_dataout,r0

	mov32	r0,0x00000020
	vmov	reg_moder_datain,r0

	movs	r0,#0x100
	vmov	reg_bit8_high,r0

	mov32	r0,#CCM_BASE
	vmov	reg_ccmram_log,r0

	// bit31 of reg_fdc_system is used to work out if the fdc is actually active. Default is off
	movs    r0,#0
	vmov    reg_fdc_system,r0

	bx	lr


.type init_fdc, %function
.align 4
.thumb_func
init_fdc:
	movs	r0,#F_TRACK0
	vmov	reg_fdc_status,r0

	movs	r0,#0
	vmov	reg_fdc_track,r0
	//vmov	reg_fdc_actual_track,r0
	vmov	reg_fdc_intended_track,r0

	movs	r0,#0
	vmov	reg_fdc_sector,r0

	movs	r0,#0
	vmov	reg_fdc_data,r0


	movs	r0,#0
	vmov	reg_fdc_command,r0

	movs	r0,#0
	vmov	reg_fdc_read_length,r0
	vmov	reg_fdc_write_length,r0

	movs	r0,#0
	vmov	reg_track_buffer_ptr,r0

	// reg_fdc_system would have been set to 0 in init_fpu
	vmov	r0,reg_fdc_system
	orrs	r0,#S_FDC_PRESENT
	vmov	reg_fdc_system,r0

	movs	r0,#1
	vmov	reg_fdc_drq_countdown,r0
	vmov	reg_fdc_irq_countdown,r0
	movs	r0,#0
	vmov	reg_fdc_irq_drq_state,r0

	// init the disk header used by read_address
	//mov32	r0,#0xe5e5e5e5
	mov32	r0,#0x00
	mov32	r1,#disk_header
	// only need 6 bytes so 2 extra ones
	str	r0,[r1],#4 
	str	r0,[r1],#4 
	

	bx	lr

.type deactivate_fdc, %function
.align 4
.thumb_func
deactivate_fdc:
	vmov	r0,reg_fdc_system
	bfc	r0,#31,#1			// set bit 31 low
	vmov	reg_fdc_system,r0
	bx	lr


// --------------------------------------------------------
// CRUCLK Handler. Int on -ve edge. 
//  0x1100  - DSR on off
//  0x1102  - DSK motor
//  0x1104  - DSK hold
//  0x1106  - DSK head
//  0x1108  - DSK 1 select
//  0x110a  - DSK 2 select
//  0x110c  - DSK 3 select
//  0x110e  - DSK side select
.type EXTI3_IRQHandler, %function
.align 4
.thumb_func
EXTI3_IRQHandler:
	vmov	r2,reg_gpioc_base
	ldr	r1,[r2,C_TO_E_OFFSET + IDR]

	vmov	r3,reg_exti_base		// s7 = EXTI
	mov32	r0,#CRUCLK_MASK
	str	r0,[r3,PR]

	lsrs	r0,r1,#8
	cmp	r0,#0x11			// ie CRU 0x11xx
	bne	1$

	vmov	r3,reg_fdc_system		// get current state
	ands	r1,#0x000f
	lsr	r0,r1,#1		// keep r1, shift r0 to the right 

	mov	r12,#1			//    0x0000 0001

	lsl	r12,r0

	tst	r1,#0x0001		
	ITTE 	EQ
	mvneq	r12,r12			// NOT r12
	andeq	r3,r12			// set bit to 0
	orrne	r3,r12			// set bit to 1

	vmov	reg_fdc_system,r3

1$:	bx	lr

// --------------------------------------------------------
// MEMEN Handler. Int on -ve edge. 
.type EXTI0_IRQHandler, %function
.align 4
.thumb_func
EXTI0_IRQHandler:
	vmov	reg_fake_stack,r11		// effectively s30 is our 'stack'
	vmov	r11,reg_gpioa_base
#ifdef DEBUG_EXTI0
        //vstr     reg_zero,[r11,ODR]
	//nop
	//nop
        vstr     reg_bit8_high,[r11,ODR]
#endif

	vmov	r2,reg_gpioc_base
	vmov	r3,reg_exti_base		// s7 = EXTI
	vstr    reg_bit0_high,[r3,PR]

	
memen_loop:
	ldr	r1,[r2,IDR]
	tst	r1,#RESET_MASK
	beq	8$
	tst	r1,#MEMEN_MASK
	beq	9$
	// exit out
8$:	databus_read_extra_delay
	vmov	r0,reg_moder_datain
	str	r0,[r2, C_TO_D_OFFSET + MODER] 
#ifdef DEBUG_EXTI0
        vstr     reg_bit8_high,[r11,ODR]
#endif
	unrolled_exit_EXTI0
	
9$:	ldr	r1,[r2, C_TO_E_OFFSET + IDR]
	lsrs	r0,r1,#13
	tbh.w	[pc,r0,lsl #1]
.include "ti_eightK_branchtable.S"
block_unused:
	b	memen_loop

// Wait for _WE to go high or the address bus to change
we_loop_wait:
	ldr	r3,[r2,C_TO_E_OFFSET + IDR]
1$:	ldr	r1,[r2,IDR]
	tst	r1,#WE_MASK
	bne	2$
	ldr	r0,[r2,C_TO_E_OFFSET + IDR]
	cmp	r0,r3
	beq	1$
2$:	databus_read_extra_delay
	vmov	r0,reg_moder_datain
	str	r0,[r2, C_TO_D_OFFSET + MODER] 
	b	memen_loop


memen_loop_wait:
1$:	ldr	r1,[r2,IDR]
	tst	r1,#MEMEN_MASK
	beq	1$
	databus_read_extra_delay
	vmov	r0,reg_moder_datain
	str	r0,[r2, C_TO_D_OFFSET + MODER] 
	unrolled_exit_EXTI0

	
rom_cartridge:
// 6000 - 7FFF request
	//databus_read_extra_delay
#ifdef DEBUG_EXTI0_CART
        vstr     reg_zero,[r11,ODR]
	nop
	nop
        vstr     reg_bit8_high,[r11,ODR]
	nop
	nop
        vstr     reg_zero,[r11,ODR]

#endif
	ldr	r1,[r2,IDR]
	vmov	r0,reg_moder_datain
	vmov	r12,reg_moder_dataout
	tst	r1,#WE_MASK
	ITE	EQ
	streq	r0,[r2, C_TO_D_OFFSET + MODER]
	strne	r12,[r2, C_TO_D_OFFSET + MODER]
	beq	1$

	ldr	r1,[r2, C_TO_E_OFFSET + IDR]
	bfc	r1,#13,#19			// keep to an 8K range

	vmov	r3,reg_rom_base
	vmov	r0,reg_rom_base_offset
	add	r3,r0				// change r3 to select one of the 4 8K banks
	ldrb	r0,[r3,r1]
	lsls	r0,r0,#8
	str     r0,[r2, C_TO_D_OFFSET + ODR]
	b	memen_loop

// cartridge write (bank switching)
1$:
	ldr	r1,[r2, C_TO_E_OFFSET + IDR]
	//ands	r1,#0x1e			// mask 4 bits
	ands	r1,#0x06			// mask 2 bits for up to 32K roms
	//eor	r1,#0x06
	lsls	r1,#12
	vmov	reg_rom_base_offset,r1
	vmov	r3,reg_rom_base
	add	r3,r1
	b	memen_loop

// 32K RAM expansion 2000-3FFF and A000-FFFF
ram_expansion:
	cmp	r1,#0xA000		// Check if its the block at 0x2000
	IT	LT
	addlt	r1,#0x6000		// convert 0x2000 to 0x8000 so the entire 32K is grouped together at the top half of the CCM RAM
	databus_read_extra_delay

	// switch the databus direction early based on the state of _WE
	mov32	r0,#GPIOD_BASE
	ldr	r12,[r2,IDR]
	tst	r12,#WE_MASK
	ITE	EQ
	vstreq	reg_moder_datain,[r0,MODER]
	vstrne	reg_moder_dataout,[r0,MODER]
	beq	write_32k

// read 32K expansion
	mov32	r0,#CCM_BASE		// Because r1 will be from 0x8000 to 0xffff, the 32K will exist in the top 32K of CCMRAM
	ldrb	r0,[r0,r1]
	lsls	r0,r0,#8
	str     r0,[r2, C_TO_D_OFFSET + ODR]
	b	memen_loop

// write 32k expansion
write_32k:
	mov32	r12,#CCM_BASE
#ifdef DEBUG_EXTI0_WRITE_32K
        vstr     reg_zero,[r11,ODR]
	nop
	nop
        vstr     reg_bit8_high,[r11,ODR]
	nop
	nop
        vstr     reg_zero,[r11,ODR]

#endif
	ldr	r0,[r2, C_TO_D_OFFSET + IDR]
	lsrs	r0,#8
	strb	r0,[r12,r1]
	b	memen_loop		// Normally I would just to we_loop_wait after a write ... but weirdly it does not work for this case

// 0x8000-0x9FFF
misc_peripherals:
	lsrs	r0,r1,#11
	cmp	r0,#(0x9800 >>11)
	bne	memen_loop
	tst	r1,#0x0001		// A15 must be low
	bne	memen_loop
	// Must be 0x9800 - 0x9fff
	tst	r1,#0x0400		//To determine 9c vs 98 . 
	beq	grom_read
	// 9cxx
	tst	r1,#0x0002		// make sure its 9c02
	beq	memen_loop
	ldr	r0,[r2,IDR]		// check _WE. TODO. Probably should check DBIN instead
	tst	r0,#WE_MASK
	bne	memen_loop

#ifdef DEBUG_EXTI0
        vstr     reg_zero,[r11,ODR]
	nop
	nop
	nop
        vstr     reg_bit8_high,[r11,ODR]
	nop
	nop
	nop
        vstr     reg_zero,[r11,ODR]

#endif
grom_write:
	// 9C02. write to the address counter
	vmov	r0, reg_moder_datain
	str	r0,[r2,C_TO_D_OFFSET + MODER]
	nop
	vmov	r1,reg_grom_address_counter
	// get data bus
	ldr	r0,[r2, C_TO_D_OFFSET + IDR]
	lsrs	r0,#8
	// Shift in the address 8 bits at a time. This seems to be the opposite of the doco I found, but it does work
	lsls	r1,#8
	bfi	r1,r0,#0,#8
	bfc	r1, #16,#16		// and 0xffff
	vmov	reg_grom_address_counter,r1
	b	we_loop_wait


	// 98xx read data
grom_read:
	tst	r1,#0x0002		// make sure its 9800
	bne	grom_read_address
	// 9800 (read data)
	vmov	r0, reg_grom_address_counter
	lsrs	r12,r0,#13
	cmp	r12,#3
	blt	4$
	// bump address counter. Not too sure if we should do this for any read of 0x9800
	vmov	r0, reg_grom_address_counter
	mov	r12,r0			// we'll use r12 further down
	adds	r0,#1
	vmov 	reg_grom_address_counter, r0
	// Only do something with groms 3 to 7
	sub	r12,#0x6000	// align the base of the GROMs
	ldr	r0,[r2,IDR]	// check _WE
	tst	r0,#WE_MASK
	beq	4$		// ignore writes
	// must be a GROM read
	vmov	r0, reg_moder_dataout
	str	r0,[r2,C_TO_D_OFFSET + MODER]
	mov32	r0,#grom_base
	ldrb	r0,[r0,r12]
	lsls	r0,r0,#8
	str	r0,[r2,C_TO_D_OFFSET + ODR]
	ldr	r12,[r2,C_TO_E_OFFSET + IDR]

4$:	ldr	r0,[r2,IDR]	
	tst	r0,#MEMEN_MASK
	bne	5$
	ldr	r1,[r2,C_TO_E_OFFSET + IDR]
	cmp	r1,r12
	beq	4$
5$:	
	vmov	r0, reg_moder_datain
	str	r0,[r2,C_TO_D_OFFSET + MODER]

	b	memen_loop
	
	//9802 read the address+1 (not implemented)
grom_read_address:
	vmov	r0, reg_grom_address_counter
	lsrs	r12,r0,#13
	cmp	r12,#3				// only read the address back if its for GROMS 3 to 7
	// Not implemented
	b	memen_loop




// Emulation of the DSR ROM (4000-5fff) and FDC (sorta 5ffx) and I haev shoved the menu interface in to 5fex
dsr_block:
#ifdef DEBUG_FDC
        vstr     reg_bit8_high,[r11,ODR]
	nop
	nop
        vstr     reg_zero,[r11,ODR]
#endif
2$:
	vmov	r3,reg_fdc_system
	tst	r3,#S_CRU_DSR_ROM
	beq	memen_loop
	mov32	r0,#0x5fe0			// TODO check the extra CRU bit that enables 0x5fe0 to 5fee for the menu interface
	cmp	r1,r0
	bge	fdc_controller
	ldr	r0,[r2,IDR]
	tst	r0,#WE_MASK
	beq	memen_loop
// reading the DSR ROM(s)
	vmov	r0, reg_moder_dataout
	str	r0,[r2,C_TO_D_OFFSET + MODER]
	mov32	r0,#dsr_base
	sub	r1,#0x4000
	ldrb	r0,[r0,r1]
	lsls	r0,r0,#8
	str     r0,[r2, C_TO_D_OFFSET + ODR]
	b	memen_loop


fdc_controller:
	tst	r1,#0x0001		// test the LSB A15. It must be zero
	bne	memen_loop
	
	ldr	r3,[r2,IDR]		// we want to check _WE
	ands	r1,#0x001f		// change 5fe0 to 5ffe to 0 to 1e
	lsrs	r1,#1			// switch to 0 to f
	tst	r1,#0x0004		// bit 3 of the address (now bit 2 after the shift) is low for reads. high for writes
	beq	1$
	// 4 to 7  are 5fe8 to 5fee, c to f are 5ff8 to 5ffe which should be WRITE commands
	tst	r3,#WE_MASK
	bne	memen_loop		// if its a read, then ignore
#ifdef DEBUG_FDC_WRITES
	ldr	r0,[r2,C_TO_D_OFFSET+IDR]
	lsrs	r0,#8
	mvn	r0,r0
	log_r0_r1_to_ccm_uses_r12
#endif
	b	2$
1$:	tst	r3,#WE_MASK
	beq	memen_loop		// if its a write for a read address then ignore
// Jump table for FDC command. Note for future. tbh is not that fast. It is pretty linear time wise though.
// First 4 entries are reads. Next 4 are writes
2$:	tbh.w   [pc,r1,lsl #1]
.include "ti_fdc_readwrite_branchtable.S"

menu_ctrl_unused_read:
fdc_unused_read:
        b	memen_loop

fdc_status_read:
#ifdef DEBUG_FDC_STATUS_READ2
	vstr	reg_bit8_high,[r11,ODR]
#endif
	vmov	r1,reg_fdc_status

// Make sure 2nd, 3rd drive reports not ready
	vmov	r0,reg_fdc_system
	//tst	r0,#(S_CRU_DISK_DRIVE_2|S_CRU_DISK_DRIVE_3)
	//IT	NE
	//orrne	r1,#F_NOTREADY		// set drive 2,3,4 to not ready

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
	mvn	r1,r1			// invert data
        str     r1,[r2, C_TO_D_OFFSET + ODR] // GPIOD ODR
        str     r0,[r2, C_TO_D_OFFSET + MODER]  // MODER set to outputs

	// reset IRQ
	movs	r3,#IRQ_OFF+WAIT_ZERO_CYCLES_UNTIL_CHANGE
	vmov	reg_fdc_irq_countdown,r3

	b	memen_loop_wait

fdc_data_read:
#ifdef DEBUG_FDC_DATA_READ_START
	vstr     reg_zero,[r11,ODR]		
#endif
	mov32	r0,#track_buffer
	// offset the track_buffer by one tracks worth if we are on the other side of the disk
	vmov	r3,reg_fdc_command
	cmp	r3,#0xc0		// if last command was a read_address, we dont change the offset for the side
	beq	1$
	vmov	r3,reg_fdc_system
	tst	r3,#S_CRU_DISK_SIDE
	IT	NE
	addne	r0,#SIZEOF_ONE_DISK_TRACK
	tst	r3,#S_CRU_DISK_DRIVE_2
	IT	NE
	addne	r0,(2*SIZEOF_ONE_DISK_TRACK)
	tst	r3,#S_CRU_DISK_DRIVE_3
	IT	NE
	addne	r0,(4*SIZEOF_ONE_DISK_TRACK)

1$:	vmov	r3,reg_track_buffer_ptr
	movs	r1,#0

	vmov	r12,reg_fdc_read_length
	cmp	r12,#0
	ITTEE	NE
	ldrbne	r1,[r0,r3]		// get byte from the track buffer
	movne	r12,#DRQ_ON+WAIT_15_CYCLES_UNTIL_CHANGE	
	vmoveq	r1,reg_fdc_data		// or get the data register
	moveq	r12,#DRQ_OFF+WAIT_ZERO_CYCLES_UNTIL_CHANGE	// if we are in dummy read mode we need to make sure we dont trigger a DRQ
	vmov	reg_fdc_data,r1		// update the data register

	lsls	r1,#8
	vmov	r0,reg_moder_dataout
	mvn	r1,r1
        str     r1,[r2, C_TO_D_OFFSET + ODR] // GPIOD ODR
        str     r0,[r2, C_TO_D_OFFSET + MODER]  // MODER set to outputs


	// reset DRQ immediately. This weirdness is because we can't queue up two transitions of DRQ
	vmov	r3,reg_fdc_irq_drq_state
	ands	r3,#~0x40
	vmov	reg_fdc_irq_drq_state,r3

	vmov	r0,reg_fdc_command	// check what the last command was
	tst	r0,#0x80
	beq	10$
	// previous command was >=0x80 (eg. read or write sector)
	cmp	r0,#0xd0
	beq	10$	
	// This is queuing up the next DRQ
	mov	r3,r12			// Get the countdown timer setting for DRQ. Its needs to be OFF for a dummy read
	vmov	reg_fdc_drq_countdown,r3
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
	//IT	EQ
// must have crossed a sector boundary. Everything seems to just read one sector at a time, so leaving off
	//addseq	r3,#1		// incr the sector number
	vmov	reg_fdc_sector,r3
	cmp	r12,#0
	bne	2$
// All data read
	vmov	r12,reg_fdc_status
	ands	r12,#~(F_DRQ|F_BUSY)
	vmov	reg_fdc_status,r12
	
	movs	r12,#DRQ_OFF+WAIT_ZERO_CYCLES_UNTIL_CHANGE
	vmov	reg_fdc_drq_countdown,r12
	movs	r12,#IRQ_ON+WAIT_3_CYCLES_UNTIL_CHANGE      // This seems quite important to Nitros-9. 
	vmov	reg_fdc_irq_countdown,r12


// Put some data on the databus
2$:
	b	memen_loop_wait


fdc_track_read:
	vmov	r1,reg_fdc_track

// get it out on the bus early

	lsls	r1,#8
	vmov	r0,reg_moder_dataout
	mvn	r1,r1
        str     r1,[r2, C_TO_D_OFFSET + ODR] // GPIOD ODR
        str     r0,[r2, C_TO_D_OFFSET + MODER]  // MODER set to outputs

#ifdef ENABLE_FDC_CCM_LOGGING
	movs	r0,#0x19
	lsrs	r1,#8
	log_r0_r1_to_ccm_uses_r12
#endif

	b	memen_loop_wait

fdc_sector_read:
	vmov	r1,reg_fdc_sector

	lsls	r1,#8
	vmov	r0,reg_moder_dataout
	mvn	r1,r1
        str     r1,[r2, C_TO_D_OFFSET + ODR] // GPIOD ODR
        str     r0,[r2, C_TO_D_OFFSET + MODER]  // MODER set to outputs

#ifdef ENABLE_FDC_CCM_LOGGING
	movs	r0,#0x1a
	lsrs	r1,#8
	log_r0_r1_to_ccm_uses_r12
#endif

	b	memen_loop_wait


	// TODO. These are not used.
menu_ctrl_unused_write:
fdc_unused_write:
        b	memen_loop

fdc_command_write:
	// D->IRQ=0
	// This stuff kills the queue of interrupts

	ldr	r1,[r2,C_TO_D_OFFSET+IDR]	// read databus again
	lsrs	r1,r1,#8
	eor	r1,#0xff

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
	vmov	r3,reg_fdc_track
	cmp	r3, #0
	IT	EQ
	moveq	r0,#F_TRACK0
	vmov	reg_fdc_status,r0

// if(V&C_IRQ) D->IRQ=WD1793_IRQ;
6$:	tst	r1,#C_IRQ
	ITT	NE
	movne	r0,#IRQ_ON+WAIT_ZERO_CYCLES_UNTIL_CHANGE
	vmovne	reg_fdc_irq_countdown,r0

        b	we_loop_wait

// all commands except D0
1$:
	// pretty much all of them will generally reset NMI and set DRQ off
	movs	r3,#WAIT_ZERO_CYCLES_UNTIL_CHANGE
	vmov	reg_fdc_irq_countdown,r3
	vmov	reg_fdc_drq_countdown,r3


	vmov	r12,reg_fdc_status
	tst	r12, #F_BUSY
	beq	2$
	// exit if busy
        b	we_loop_wait
2$:
	movs	r12,#0
	vmov	reg_fdc_status,r12	// reset status
	vmov	reg_fdc_command,r1	// save the full command
	// r0 bits 7 to 4 should be the command
	lsrs	r0,#4
        tbh.w   [pc,r0,lsl #1]
.include "ti_fdc_command_branchtable.S"

fdc_command_unused:
	b	memen_loop

fdc_command_restore:
	//ldr	r3,=main_thread_command
	movs	r0,#0
	vmov	reg_fdc_intended_track,r0
	mov32   r3,#main_thread_command
	mov	r1,#MAIN_THREAD_SEEK_COMMAND
	vmov	r0,reg_fdc_system
	lsrs	r0,#4					// get disk select bits in bottom 3 bits
	ands	r0,#0x0007				// make sure its just 3 bits
	lsls	r0,#29					// top 3 bits are now drive select bits and rest is 0 for 'track 0'
        str   	r0,[r3, MAIN_STRUCT_DATA]		// write cylinder to seek to combined with drive select bits in top 3 bits
	mov	reg_main_thread_command,r1
	vmov	r12,reg_fdc_status
	orrs	r12,#F_BUSY
	vmov	reg_fdc_status,r12
	b	we_loop_wait


fdc_command_seek:
	vmov	reg_fdc_read_length,reg_zero
	vmov	r0,reg_fdc_data		// The track num would have been loaded into 'data'
	vmov	reg_fdc_intended_track,r0
	//ldr	r3,=main_thread_command

	vmov	r1,reg_fdc_system
	lsrs	r1,#4					// get disk select bits in bottom 3 bits
	ands	r1,#0x0007				// make sure its just 3 bits
	mov32	r3,#main_thread_actual_track
	// assume DSK1, but test for DSK2 or DSK3
	tst	r1,#0x02				// DSK2
	IT	NE
	addne	r3,#4
	tst	r1,#0x04				// DSK3
	IT	NE
	addne	r3,#8
	ldr	r3,[r3]					// get the actual track for the selected disk
	add	r0,r3					// data register + actual track 
	vmov	r3,reg_fdc_track
	subs	r0,r3					// subtract track register
	IT	MI
	movmi	r0,#0					//
	
	lsls	r1,#29					// top 3 bits are now drive select bits and rest is 0 for 'track 0'
	orr	r0,r1
	
	mov32   r3,#main_thread_command
	mov	r1,#MAIN_THREAD_SEEK_COMMAND
        str     r0,[r3, MAIN_STRUCT_DATA]           // write cylinder to seek to 
	mov	reg_main_thread_command,r1
	vmov	r12,reg_fdc_status
	orrs	r12,#F_BUSY
	vmov	reg_fdc_status,r12
	b	we_loop_wait


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
	tst	r1,#0x20	// get the step direction
	ITE	NE
	orrne	r12,#S_LASTSTEPDIR
	andeq	r12,#~S_LASTSTEPDIR
	vmov	reg_fdc_system,r12
2$:
	vmov	r12,reg_fdc_system
	mov32	r3,#main_thread_actual_track
	// assume DSK1, but test for DSK2 or DSK3
	tst	r12,#S_CRU_DISK_DRIVE_2			// DSK2
	IT	NE
	addne	r3,#4
	tst	r12,#S_CRU_DISK_DRIVE_2			// DSK3
	IT	NE
	addne	r3,#8
	ldr	r3,[r3]					// get the actual track for the selected disk

	vmov	r0,reg_fdc_track
	mov	r12,r0					// back up the original track register to r12
	//tst	r12,#S_DRIVE	// check if drive 0 or 1
	//tst	r12,#S_CRU_DISK_DRIVE_1	// check if drive 1
	//bne	3$
	tst	r1,#0x20
	ITE	NE
	subne	r0,#1		// decr track num
	addeq	r0,#1		// incr track num
	tst	r0,#0x80000000		//check if we just went negative
	IT	NE
	movne	r0,#0			// reset to track0
	vmov	reg_fdc_intended_track,r0

	tst	r1,#C_SETTRACK
	IT	NE
	vmovne	reg_fdc_track,r0

	add	r0,r3					// actual track + intended track
	subs	r0,r12					// subtract original track register
	IT	MI
	movmi	r0,#0					//
	// r0 is now the intended actual track to seek to


// zero most of fdc_status
	movs	r1,#F_INDEX
	//tst	r12,#S_DRIVE		// r12 still has the system register
	vmov	reg_fdc_status,r1

	mov32	r3,#main_thread_command

	vmov	r1,reg_fdc_system
	lsrs	r1,#4					// get disk select bits (AGAIN) in bottom 3 bits
	ands	r1,#0x0007				// make sure its just 3 bits
	lsls	r1,#29					// top 3 bits are now drive select bits and rest is 0 for 'track 0'
	orr	r0,r1

	movs	r1,#MAIN_THREAD_SEEK_COMMAND
        str     r0,[r3, MAIN_STRUCT_DATA]           // write cylinder to seek to 
        mov	reg_main_thread_command,r1

	vmov	r12,reg_fdc_status
	orrs	r12,#F_BUSY
	vmov	reg_fdc_status,r12

	b	we_loop_wait



fdc_command_read_sector:
	// reset DRQ immediately
	vmov	r3,reg_fdc_irq_drq_state
	ands	r3,#~0x40
	vmov	reg_fdc_irq_drq_state,r3
	// queue up the first DRQ for the first byte
	movs	r3,#DRQ_ON+WAIT_15_CYCLES_UNTIL_CHANGE
	vmov	reg_fdc_drq_countdown,r3
	// assume 256 byte sector
	movs	r0,#0		// set to beginning of track

	// all the code to check the disk side is removed due to Nitros-9 sending very late writes to the latch
	vmov	r12,reg_fdc_system
	tst	r1,#C_UPDATE_SSO	// The Tandy wont use this bit usually, but the Dragon will
	ITE	NE
	orrne 	r12,#S_SIDE
	andeq 	r12,#~(S_SIDE)
	vmov	reg_fdc_system,r12

3$:	vmov	r12,reg_fdc_sector
	//subs	r12, #1		// sectors are 1 to 18. We need 0 to 17
	//IT	MI
	//movmi	r12,#0		// adjust it back to zero if it went negative

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

	b	we_loop_wait

fdc_command_write_sector:
	// reset DRQ immediately
	vmov	r3,reg_fdc_irq_drq_state
	ands	r3,#~0x40
	vmov	reg_fdc_irq_drq_state,r3
	// queue up the first DRQ for the first byte
	movs	r3,#DRQ_ON+WAIT_15_CYCLES_UNTIL_CHANGE
	vmov	reg_fdc_drq_countdown,r3

	// assume 256 byte sector
	movs	r0,#0		// set to beginning of track

	// all the code to check the disk side is removed due to Nitros-9 sending very late writes to the latch
	vmov	r12,reg_fdc_system
	tst	r1,#C_UPDATE_SSO	// The Tandy wont use this bit usually, but the Dragon will
	ITE	NE
	orrne 	r12,#S_SIDE
	andeq 	r12,#~(S_SIDE)
	vmov	reg_fdc_system,r12

3$:	vmov	r12,reg_fdc_sector
	//subs	r12, #1		// sectors are 1 to 18. We need 0 to 17
	//IT	MI
	//movmi	r12,#0		// adjust it back to zero if it went negative

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

        b	we_loop_wait

// TI  read_address command
fdc_command_read_address:
	// reset DRQ immediately
	vmov	r3,reg_fdc_irq_drq_state
	ands	r3,#~0x40
	vmov	reg_fdc_irq_drq_state,r3
	// queue up the first DRQ for the first byte
	movs	r3,#DRQ_ON+WAIT_15_CYCLES_UNTIL_CHANGE
	vmov	reg_fdc_drq_countdown,r3

	mov32	r0,#(disk_header-track_buffer)
	vmov	reg_track_buffer_ptr,r0

	movs	r0,#6
	vmov	reg_fdc_read_length,r0

	mov32	r3,#disk_header
	vmov	r0,reg_fdc_track
	strb	r0,[r3]
	vmov	r1,reg_fdc_system
	// fudge the side
	movs	r0,#0
	tst	r1,#S_CRU_DISK_SIDE
	IT	NE
	orrne	r0,#1
	strb	r0,[r3,1]
	vmov	r0,reg_fdc_sector
	strb	r0,[r3,2]
	movs	r0,#1
	strb	r0,[r3,3]
	
// flags
	vmov	r0,reg_fdc_status
	orrs	r0,#(F_BUSY|F_DRQ)
	vmov	reg_fdc_status,r0

	b	we_loop_wait
	


// ---------------------

fdc_track_write:
	ldr	r1,[r2,C_TO_D_OFFSET+IDR]	// read databus again
	lsrs	r1,r1,#8
	eor	r1,#0xff


	vmov	r0,reg_fdc_status
	tst	r0,#F_BUSY
	IT	EQ
	vmoveq	reg_fdc_track,r1		// upate track if not busy

	b	we_loop_wait

fdc_sector_write:
	ldr	r1,[r2,C_TO_D_OFFSET+IDR]	// read databus again
	lsrs	r1,r1,#8
	eor	r1,#0xff


	vmov	r0,reg_fdc_status
	tst	r0,#F_BUSY
	IT	EQ
	vmoveq	reg_fdc_sector,r1

	b	we_loop_wait

fdc_data_write:
	ldr	r1,[r2,C_TO_D_OFFSET+IDR]	// read databus again
	lsrs	r1,r1,#8
	eor	r1,#0xff

#ifdef DEBUG_FDC_DATA_WRITE
        vstr     reg_zero,[r11,ODR]
	nop
	nop
        vstr     reg_bit8_high,[r11,ODR]
#endif
	// reset DRQ immediately
	vmov	r3,reg_fdc_irq_drq_state
	ands	r3,#~0x40
	vmov	reg_fdc_irq_drq_state,r3

// make sure we only queue up a DRQ if we are writing sectors
	vmov	r12,reg_fdc_command
	tst	r12,#0x80
	beq	10$
	cmp	r12,#0xd0
	beq	10$	
	movs	r12,#DRQ_ON+WAIT_15_CYCLES_UNTIL_CHANGE
	vmov	reg_fdc_drq_countdown,r12
10$:
#ifdef ENABLE_FDC_CCM_LOGGING
	//log_r0_r1_to_ccm_uses_r12
#endif

	vmov	reg_fdc_data,r1
	vmov	r12,reg_fdc_write_length
	cmp	r12,#0
	bne	1$
	b	we_loop_wait

// WRITE DATA TO SECTOR. non zero write length
1$:
	mov32	r0,#track_buffer
	// offset the track_buffer by one tracks worth if we are on the other side of the disk
	// this has to be done here to make Nitros-9 work
	vmov	r3,reg_fdc_system
	tst	r3,#S_CRU_DISK_SIDE
	IT	NE
	addne	r0,#(9*256)
	tst	r3,#S_CRU_DISK_DRIVE_2
	IT	NE
	addne	r0,(2*SIZEOF_ONE_DISK_TRACK)
	tst	r3,#S_CRU_DISK_DRIVE_3
	IT	NE
	addne	r0,(4*SIZEOF_ONE_DISK_TRACK)

	vmov	r3,reg_track_buffer_ptr
	strb	r1,[r0,r3]		// store byte in track buffer

	adds	r3,#1			// incr the track_buffer_ptr
	subs	r12,#1			// decr the write length
	vmov	reg_track_buffer_ptr,r3	// update the track_buffer_ptr
	vmov	r3,reg_fdc_sector	// get current sector num
	vmov	reg_fdc_write_length,r12
	mov	r0,#0x0ff
	//tst	r12,r0		// see if bottom 8 bits are clear
	//IT	EQ
// must have crossed a sector boundary
	//addseq	r3,#1		// incr the sector number
	//vmov	reg_fdc_sector,r3
	cmp	r12,#0
	bne	2$
// All data written
        vmov    r12,reg_fdc_status
        ands    r12,#~(F_DRQ|F_BUSY)
        vmov    reg_fdc_status,r12

	movs	r12,#DRQ_OFF+WAIT_ZERO_CYCLES_UNTIL_CHANGE
	vmov	reg_fdc_drq_countdown,r12
	// write sector seems to need a larger delay here than read sector. not sure why
	movs	r12,#IRQ_ON+WAIT_15_CYCLES_UNTIL_CHANGE
	vmov	reg_fdc_irq_countdown,r12


	// flush logic. Its very unlikely that we would be writing to two disks at the same time
	vmov	r3,reg_fdc_system
	lsrs	r3,#4					// get disk select bits in bottom 3 bits
	ands	r3,#0x0007				// make sure its just 3 bits

	mov32	r1,#fdc_write_flush_count
	ldr	r0,[r1,4]				// get the current dirty bits
	orr	r0,r3					// add in any additional dirty bits
	str	r0,[r1,4]

	mov32	r0,#FDC_WRITE_FLUSH_DEFAULT
	str	r0,[r1]				// trigger write after some delay

2$:	
        b	we_loop_wait


menu_ctrl_command_write:
	vmov	r0,reg_moder_datain
	str	r0,[r2, C_TO_D_OFFSET + MODER] 
	nop
	nop
	//movs	r1,#0x80
	ldr	r1,[r2,C_TO_D_OFFSET+IDR]	// read databus again
	lsrs	r1,r1,#8

	mov32	r0,#0x10000010
	mvn	r1,r1
	strb	r1,[r0]
	mvn	r1,r1

	tst	r1,#LOAD_DIRECTORY_COMMAND_MASK
	beq	1$
// Initiate 'load directory'

	mov	reg_main_thread_command,#MAIN_THREAD_COMMAND_LOAD_DIRECTORY
	b	2$
1$:     tst     r1,#LOAD_ROM_COMMAND_MASK
        beq     3$
	// Initiate 'load rom'
        mov     reg_main_thread_command,#MAIN_THREAD_COMMAND_LOAD_ROM
	b	2$
3$:	cmp	r1,#0x33		// magic code to clear the reg_main_thread_command
	bne	2$
        movs    reg_main_thread_command,#0
2$:	b	we_loop_wait


menu_ctrl_address_register_lsb_write:
	movs	r0,#0
	b	menu_ctrl_address_register_write_main
menu_ctrl_address_register_msb_write:
	movs	r0,#1
menu_ctrl_address_register_write_main:

	ldr	r1,[r2,C_TO_D_OFFSET+IDR]	// read databus again
	lsrs	r1,r1,#8
	mov32	r3,#menu_ctrl_address_register
	strb	r1,[r3,r0]
	b	we_loop_wait

menu_ctrl_data_register_write:
	ldr	r1,[r2,C_TO_D_OFFSET+IDR]	// read databus again
	lsrs	r1,r1,#8

	movs	r0,#0x0
	mov32	r3,#menu_ctrl_address_register
	ldr	r0,[r3]		// grab it as a word

	mov32	r12,#CCMRAM_BASE+MENU_DIRCACHE_OFFSET
	strb	r1,[r12,r0]
	adds	r0,#1
	cmp	r0,#(0x8000-MENU_DIRCACHE_OFFSET)	// wrap round, which is wrong, but at least it does not interfere with the 32k ram
	IT	EQ
	moveq	r0,#0
	str	r0,[r3]
	b	we_loop_wait

// return bit 7 as 1 if a load directory command is complete
menu_ctrl_command_read:
	mov32	r0,#0x10000004
	ldr	r1,[r0]
	adds	r1,#1
	str	r1,[r0]

	tst	reg_main_thread_command,#MAIN_COMMAND_LOAD_DIRECTORY_COMPLETE
	ITE	NE
	bfcne	r1,#7,#1	// send bit 7 low
	orreq	r1,0x80		// bit 7 high

	tst	reg_main_thread_command,#MAIN_COMMAND_LOAD_ROM_COMPLETE
	ITE	NE
	bfcne	r1,#6,#1	// send bit 6 low
	orreq	r1,0x40		// bit 6 high

	//movs	reg_main_thread_command,#0		// You now have to write an 0x33 to the command register to ack these commands
1$:	
// get it out on the bus early

	lsls	r1,#8
	vmov	r0,reg_moder_dataout
        str     r1,[r2, C_TO_D_OFFSET + ODR] // GPIOD ODR
        str     r0,[r2, C_TO_D_OFFSET + MODER]  // MODER set to outputs

	b	memen_loop_wait

menu_ctrl_file_count_lsb_read:
menu_ctrl_file_count_msb_read:
	mov32	r3,#menu_ctrl_file_count
	//ands	r0,#0x01
	ldrb	r1,[r3]

// get it out on the bus early

	lsls	r1,#8
	vmov	r0,reg_moder_dataout
        str     r1,[r2, C_TO_D_OFFSET + ODR] // GPIOD ODR
        str     r0,[r2, C_TO_D_OFFSET + MODER]  // MODER set to outputs

	b	memen_loop

menu_ctrl_data_register_read:
	movs	r0,#0x0
	mov32	r3,#menu_ctrl_address_register
	ldr	r0,[r3]		// grab it as a word
// TODO check if this CCMRAM offset is going to clash
	mov32	r12,#CCMRAM_BASE+MENU_DIRCACHE_OFFSET
	movs	r1,#0x0
	ldrb	r1,[r12,r0]
	adds	r0,#1
	cmp	r0,#(0x8000-MENU_DIRCACHE_OFFSET)	// wrap round, which is wrong, but at least it does not interfere with the 32k ram
	IT	EQ
	moveq	r0,#0
	str	r0,[r3]
	

// get it out on the bus early

	lsls	r1,#8
	vmov	r0,reg_moder_dataout
        str     r1,[r2, C_TO_D_OFFSET + ODR] // GPIOD ODR
        str     r0,[r2, C_TO_D_OFFSET + MODER]  // MODER set to outputs

	b	memen_loop_wait



