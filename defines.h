// defines
//
// This needs to be able to be included from C and asm. defines work in .S and .c files

// Stringify functions
#define XSTR(x) STR(x)
#define STR(x) #x

// true/false
#define TRUE 1
#define FALSE 0

// GPIO Mapping Port A
#define GPIO_DEBUG_LED		GPIO_Pin_1
#define GPIO_LOGIC_ANALYSER_DEBUG	GPIO_Pin_8

#define GPIO_NEXT_ITEM		GPIO_Pin_2
#define GPIO_PREV_ITEM		GPIO_Pin_3
#define GPIO_FORCE_MENU_ROM	GPIO_Pin_4

// GPIO Mapping Port C
#define GPIO_TI994A_MEMEN	GPIO_Pin_0
#define GPIO_TI994A_WE		GPIO_Pin_1
#define GPIO_TI994A_DBIN	GPIO_Pin_2
#define GPIO_TI994A_CRUCLK	GPIO_Pin_3

#define GPIO_TI994A_RESET	GPIO_Pin_5
#define GPIO_TI994A_CRUIN	GPIO_Pin_6

#define GPIO_TI994A_READY	GPIO_Pin_13




// registers
#define reg_zero		s0
#define reg_bit0_high		s1
#define reg_grom_address_counter s2
#define reg_gpioc_base		s3
#define reg_rom_base		s4

#define reg_gpioa_base		s5
#define reg_rom_base_offset	s6
#define reg_exti_base		s7
#define reg_moder_dataout	s8
#define reg_moder_datain	s9

// All this IRQ/DRQ stuff is actually not used for the TI code
#define reg_next_fdc_irq_drq	s10
#define reg_fdc_drq_countdown	s11
#define reg_fdc_irq_countdown	s12
#define reg_fdc_irq_drq_state	s13

#define reg_ccmram_log		s14

#define reg_fdc_status		s15
// NOTE: FPU registers d8 and d9 are used somehow, so you cannot use s16,s17,s18 and s19


#define reg_fdc_write_length	s20
#define reg_fdc_system		s21
#define reg_bit8_high		s22
#define reg_track_buffer_ptr	s23
#define reg_fdc_track		s24
#define reg_fdc_intended_track	s25
#define reg_fdc_sector		s26
#define reg_fdc_data		s27

#define reg_fdc_irq_drq		s28
#define reg_fdc_command		s29

#define reg_fake_stack		s30

#define reg_fdc_read_length	s31

// the thread command is a special one. Its hard to use a floating reg from C when we disable the FPU
#define reg_main_thread_command	r10

// ============================
//
#define         MEMEN_MASK	0x0001       // ie PC0
#define         WE_MASK		0x0002       // ie PC1
#define         DBIN_MASK	0x0004       // ie PC2
#define         CRUCLK_MASK	0x0008       // ie PC3

#define         RESET_MASK	0x0020       // ie PC5
#define         CRUIN_MASK	0x0040       // ie PC6

#define         READY_MASK	0x2000       // ie PC13

// =============================
#define		NEXT_ROM_OR_DISK_MASK 0x0004	   // PA2
#define		PREV_ROM_OR_DISK_MASK 0x0008	   // PA3
#define		FORCE_MENU_ROM_MASK 0x0010	   // PA4
						   //
#define		BUTTON_DEBOUNCE		3000000
// =============================
#define		MAGIC_BUTTON_SUM	1025	// you get this if you push + then - , or - then +

#define         MEMEN_PREEMPTION_PRIORITY	0
#define         CRUCLK_PREEMPTION_PRIORITY	1

#define		SDIO_IRQ_PREEMPTION_PRIORITY	3
#define		SDIO_DMA_PREEMPTION_PRIORITY	4


// ============================
// straight from fMSX
//
                           /* Common status bits:               */
#define F_BUSY     0x01    /* Controller is executing a command */
#define F_READONLY 0x40    /* The disk is write-protected       */
#define F_NOTREADY 0x80    /* The drive is not ready            */

                           /* Type-1 command status:            */
#define F_INDEX    0x02    /* Index mark detected               */
#define F_TRACK0   0x04    /* Head positioned at track #0       */
#define F_CRCERR   0x08    /* CRC error in ID field             */
#define F_SEEKERR  0x10    /* Seek error, track not verified    */
#define F_HEADLOAD 0x20    /* Head loaded                       */

                           /* Type-2 and Type-3 command status: */
#define F_DRQ      0x02    /* Data request pending              */
#define F_LOSTDATA 0x04    /* Data has been lost (missed DRQ)   */
#define F_ERRCODE  0x18    /* Error code bits:                  */
#define F_BADDATA  0x08    /* 1 = bad data CRC                  */
#define F_NOTFOUND 0x10    /* 2 = sector not found              */
#define F_BADID    0x18    /* 3 = bad ID field CRC              */
#define F_DELETED  0x20    /* Deleted data mark (when reading)  */
#define F_WRFAULT  0x20    /* Write fault (when writing)        */

#define C_DELMARK  0x01
#define C_UPDATE_SSO 0x02
#define C_STEPRATE 0x03
#define C_VERIFY   0x04
#define C_WAIT15MS 0x04
#define C_LOADHEAD 0x08
#define C_SIDE     0x08
#define C_IRQ      0x08
#define C_SETTRACK 0x10
#define C_MULTIREC 0x10

// CRU 0x11xx bits
#define S_CRU_DSR_ROM	   0x01
#define S_CRU_DISK_MOTOR   0x02
#define S_CRU_DISK_HOLD    0x04
#define S_CRU_DISK_HEADS   0x08
#define S_CRU_DISK_DRIVE_1 0x10
#define S_CRU_DISK_DRIVE_2 0x20
#define S_CRU_DISK_DRIVE_3 0x40
#define S_CRU_DISK_SIDE    0x80

#define S_LASTSTEPDIR	0x0100
#define S_SIDE          0x0200
#define S_FDC_PRESENT	0x80000000

#define WD1793_IRQ     0x80
#define WD1793_DRQ     0x40



// -------------
#define MAIN_THREAD_SEEK_COMMAND 1
#define MAIN_THREAD_CHANGE_DISK_COMMAND 2
#define MAIN_THREAD_COMMAND_LOAD_DIRECTORY 3
#define MAIN_THREAD_COMMAND_LOAD_ROM 4
#define MAIN_THREAD_BUTTON_COMMAND 5

#define LOAD_DIRECTORY_COMMAND_MASK 0x80
#define LOAD_ROM_COMMAND_MASK 0x40

#define MENU_CTRL_COMMAND_REG		0x00
#define MENU_CTRL_FILE_COUNT_LSB	0x02
#define MENU_CTRL_FILE_COUNT_MSB	0x03
#define MENU_CTRL_ADDRESS_REGISTER_LSB	0x04
#define MENU_CTRL_ADDRESS_REGISTER_MSB	0x05
#define MENU_CTRL_DATA_REGISTER		0x06

#define RAM_EXPANSION_OFFSET		0x8000		// 0x8000 is effectively hard coded for the 32K expansion base, but this define is here to help calculate how many filenames we can potentially load in
// storage for the directory and filename (for writing)
#define MENU_DIRCACHE_OFFSET		0x1000		// You need enough room to load a lot of files less than 0x8000 where the emulated 32K ram starts
#define MENU_LISTING_BASE		0x100		// So the TI needs to write this address register to the menu address register to access the listings
#define MENU_LOAD_FILE_BASE		0x0 		// The TI needs to write this to the address register before writing the filename you want to load
#define MENU_SIZEOF_FILENAME_ENTRY	0x80
#define MAX_MENU_FILENAMES		(RAM_EXPANSION_OFFSET-MENU_DIRCACHE_OFFSET)/MENU_SIZEOF_FILENAME_ENTRY

//
// ---------------

#define CCMRAM_BASE	0x10000000

//------------
// This has to be large enough to prevent accidental flushing while a sector is being written to the buffer
#define FDC_WRITE_FLUSH_DEFAULT	200000

//----------
#define MAIN_COMMAND_IN_PROGRESS		0x80000000
#define MAIN_COMMAND_SEEK_COMPLETE		0x40000000
#define MAIN_COMMAND_LOAD_DIRECTORY_COMPLETE	0x20000000
#define MAIN_COMMAND_LOAD_ROM_COMPLETE		0x10000000

#define MAIN_STRUCT_DATA		0x04
#define MAIN_STRUCT_ACTUAL_TRACK	0x08

//--------------

#define SIZEOF_ONE_DISK_TRACK           9*256

// IRQ DRQ countdown delay stuff
#define DRQ_OFF				0x00
#define DRQ_ON				0x80

#define IRQ_OFF				0x00
#define IRQ_ON				0x80

#define WAIT_ZERO_CYCLES_UNTIL_CHANGE	0x01
#define WAIT_3_CYCLES_UNTIL_CHANGE	0x04	// 3 may work (ie. 2 cycles)
#define WAIT_8_CYCLES_UNTIL_CHANGE	0x09
#define WAIT_15_CYCLES_UNTIL_CHANGE	0x11


#define MAX_DRIVES			3
