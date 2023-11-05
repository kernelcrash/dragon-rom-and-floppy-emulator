/*
 * dragon-rom-and-floppy-emulator
 * kernel@kernelcrash.com
 *
 *
 */
#include <stdio.h>
#include <string.h>
#include "main.h"
#include "defines.h"
#include "stm32f4xx.h"
#include "util.h"
#include "timer.h"

#include "stm32f4_discovery.h"
#include "stm32f4_discovery_sdio_sd.h"
#include "ff.h"
#include "diskio.h"



extern volatile uint8_t *rom_base;
extern volatile uint8_t *low_64k_base;
extern volatile uint8_t *high_64k_base;

extern volatile uint32_t main_thread_command;
extern volatile uint32_t main_thread_data;
extern volatile uint32_t main_thread_actual_track;

extern volatile uint8_t *track_buffer;
extern volatile uint32_t fdc_write_flush_count;
extern volatile uint32_t menu_ctrl_file_count;

extern volatile uint8_t *disk_header;

#ifdef ENABLE_SEMIHOSTING
extern void initialise_monitor_handles(void);   /*rtt*/
#endif

GPIO_InitTypeDef  GPIO_InitStructure;

uint32_t global_track_size;
uint32_t global_header_length;

// FATFS stuff
FRESULT res;
FILINFO fno;
DIR dir;
FATFS fs32;
char* path;
UINT BytesRead;

#if _USE_LFN
    static char lfn[_MAX_LFN + 1];
        fno.lfname = lfn;
            fno.lfsize = sizeof lfn;
#endif


// Enable the FPU (Cortex-M4 - STM32F4xx and higher)
// http://infocenter.arm.com/help/topic/com.arm.doc.dui0553a/BEHBJHIG.html
// Also make sure lazy stacking is disabled
void enable_fpu_and_disable_lazy_stacking() {
  __asm volatile
  (
    "  ldr.w r0, =0xE000ED88    \n"  /* The FPU enable bits are in the CPACR. */
    "  ldr r1, [r0]             \n"  /* read CAPCR */
    "  orr r1, r1, #( 0xf << 20 )\n" /* Set bits 20-23 to enable CP10 and CP11 coprocessors */
    "  str r1, [r0]              \n" /* Write back the modified value to the CPACR */
    "  dsb                       \n" /* wait for store to complete */
    "  isb                       \n" /* reset pipeline now the FPU is enabled */
    // Disable lazy stacking (the default) and effectively have no stacking since we're not really using the FPU for anything other than a fast register store
    "  ldr.w r0, =0xE000EF34    \n"  /* The FPU FPCCR. */
    "  ldr r1, [r0]             \n"  /* read FPCCR */
    "  bfc r1, #30,#2\n" /* Clear bits 30-31. ASPEN and LSPEN. This disables lazy stacking */
    "  str r1, [r0]              \n" /* Write back the modified value to the FPCCR */
    "  dsb                       \n" /* wait for store to complete */
    "  isb"                          /* reset pipeline  */
    :::"r0","r1"
    );
}

enum sysclk_freq {
    SYSCLK_42_MHZ=0,
    SYSCLK_84_MHZ,
    SYSCLK_168_MHZ,
    SYSCLK_200_MHZ,
    SYSCLK_240_MHZ,
    SYSCLK_250_MHZ,
};
 
void rcc_set_frequency(enum sysclk_freq freq)
{
    int freqs[]   = {42, 84, 168, 200, 240, 250};
 
    /* USB freqs: 42MHz, 42Mhz, 48MHz, 50MHz, 48MHz */
    int pll_div[] = {2, 4, 7, 10, 10, 10}; 
 
    /* PLL_VCO = (HSE_VALUE / PLL_M) * PLL_N */
    /* SYSCLK = PLL_VCO / PLL_P */
    /* USB OTG FS, SDIO and RNG Clock =  PLL_VCO / PLLQ */
    uint32_t PLL_P = 2;
    uint32_t PLL_N = freqs[freq] * 2;
    uint32_t PLL_M = (HSE_VALUE/1000000);
    uint32_t PLL_Q = pll_div[freq];
 
    RCC_DeInit();
 
    /* Enable HSE osscilator */
    RCC_HSEConfig(RCC_HSE_ON);
 
    if (RCC_WaitForHSEStartUp() == ERROR) {
        return;
    }
 
    /* Configure PLL clock M, N, P, and Q dividers */
    RCC_PLLConfig(RCC_PLLSource_HSE, PLL_M, PLL_N, PLL_P, PLL_Q);
 
    /* Enable PLL clock */
    RCC_PLLCmd(ENABLE);
 
    /* Wait until PLL clock is stable */
    while ((RCC->CR & RCC_CR_PLLRDY) == 0);
 
    /* Set PLL_CLK as system clock source SYSCLK */
    RCC_SYSCLKConfig(RCC_SYSCLKSource_PLLCLK);
 
    /* Set AHB clock divider */
    RCC_HCLKConfig(RCC_SYSCLK_Div1);
 
    //FLASH->ACR = FLASH_ACR_PRFTEN | FLASH_ACR_ICEN |FLASH_ACR_DCEN |FLASH_ACR_LATENCY_5WS;
    FLASH->ACR =  FLASH_ACR_ICEN |FLASH_ACR_DCEN |FLASH_ACR_LATENCY_5WS;

    /* Set APBx clock dividers */
    switch (freq) {
        /* Max freq APB1: 42MHz APB2: 84MHz */
        case SYSCLK_42_MHZ:
            RCC_PCLK1Config(RCC_HCLK_Div1); /* 42MHz */
            RCC_PCLK2Config(RCC_HCLK_Div1); /* 42MHz */
            break;
        case SYSCLK_84_MHZ:
            RCC_PCLK1Config(RCC_HCLK_Div2); /* 42MHz */
            RCC_PCLK2Config(RCC_HCLK_Div1); /* 84MHz */
            break;
        case SYSCLK_168_MHZ:
            RCC_PCLK1Config(RCC_HCLK_Div4); /* 42MHz */
            RCC_PCLK2Config(RCC_HCLK_Div2); /* 84MHz */
            break;
        case SYSCLK_200_MHZ:
            RCC_PCLK1Config(RCC_HCLK_Div4); /* 50MHz */
            RCC_PCLK2Config(RCC_HCLK_Div2); /* 100MHz */
            break;
        case SYSCLK_240_MHZ:
            RCC_PCLK1Config(RCC_HCLK_Div4); /* 60MHz */
            RCC_PCLK2Config(RCC_HCLK_Div2); /* 120MHz */
            break;
        case SYSCLK_250_MHZ:
            RCC_PCLK1Config(RCC_HCLK_Div4); 
            RCC_PCLK2Config(RCC_HCLK_Div2);
            break;
    }
 
    /* Update SystemCoreClock variable */
    SystemCoreClockUpdate();
}


void config_backup_sram() {
  RCC_AHB1PeriphClockCmd(RCC_AHB1Periph_BKPSRAM, ENABLE);
  /* disable backup domain write protection */
  RCC_APB1PeriphClockCmd(RCC_APB1Periph_PWR, ENABLE);   // set RCC->APB1ENR.pwren
  PWR_BackupAccessCmd(ENABLE);                          // set PWR->CR.dbp = 1;
  /** enable the backup regulator (used to maintain the backup SRAM content in
    * standby and Vbat modes).  NOTE : this bit is not reset when the device
    * wakes up from standby, system reset or power reset. You can check that
    * the backup regulator is ready on PWR->CSR.brr, see rm p144 */
  PWR_BackupRegulatorCmd(ENABLE);     // set PWR->CSR.bre = 1;
}


// For some weird reason the optimizer likes to delete this whole function, hence set to O0
void __attribute__((optimize("O0")))  SD_NVIC_Configuration(void)
{
        NVIC_InitTypeDef NVIC_InitStructure;


        NVIC_InitStructure.NVIC_IRQChannel = SDIO_IRQn;
        NVIC_InitStructure.NVIC_IRQChannelPreemptionPriority = SDIO_IRQ_PREEMPTION_PRIORITY;    // This must be a lower priority (ie. higher number) than the _MREQ and _IORQ interrupts
        NVIC_InitStructure.NVIC_IRQChannelSubPriority = 0;
        NVIC_InitStructure.NVIC_IRQChannelCmd = ENABLE;
        NVIC_Init(&NVIC_InitStructure);

	// DMA2 STREAMx Interrupt ENABLE
	NVIC_InitStructure.NVIC_IRQChannel = SD_SDIO_DMA_IRQn;
	NVIC_InitStructure.NVIC_IRQChannelPreemptionPriority = SDIO_DMA_PREEMPTION_PRIORITY;
	NVIC_Init(&NVIC_InitStructure);

}

void SDIO_IRQHandler(void)
{
	/* Process All SDIO Interrupt Sources */
	SD_ProcessIRQSrc();
}

void SD_SDIO_DMA_IRQHANDLER(void)
{
	SD_ProcessDMAIRQ();
}

//
void config_PC0_event(void) {
        EXTI_InitTypeDef EXTI_InitStruct;

        /* Enable clock for SYSCFG */
        RCC_APB2PeriphClockCmd(RCC_APB2Periph_SYSCFG, ENABLE);

        SYSCFG_EXTILineConfig(EXTI_PortSourceGPIOC, EXTI_PinSource0);

        EXTI_InitStruct.EXTI_Line = EXTI_Line0;
        /* Enable interrupt */
        EXTI_InitStruct.EXTI_LineCmd = ENABLE;
        /* Interrupt mode */
        EXTI_InitStruct.EXTI_Mode = EXTI_Mode_Event;
        /* Triggers on rising and falling edge */
        EXTI_InitStruct.EXTI_Trigger = EXTI_Trigger_Falling;
        /* Add to EXTI */
        EXTI_Init(&EXTI_InitStruct);
}

void config_PC0_int(void) {
        EXTI_InitTypeDef EXTI_InitStruct;
        NVIC_InitTypeDef NVIC_InitStruct;

        /* Enable clock for SYSCFG */
        RCC_APB2PeriphClockCmd(RCC_APB2Periph_SYSCFG, ENABLE);

        SYSCFG_EXTILineConfig(EXTI_PortSourceGPIOC, EXTI_PinSource0);

        EXTI_InitStruct.EXTI_Line = EXTI_Line0;
        /* Enable interrupt */
        EXTI_InitStruct.EXTI_LineCmd = ENABLE;
        /* Interrupt mode */
        EXTI_InitStruct.EXTI_Mode = EXTI_Mode_Interrupt;
        /* Triggers on rising and falling edge */
        EXTI_InitStruct.EXTI_Trigger = EXTI_Trigger_Rising;
        /* Add to EXTI */
        EXTI_Init(&EXTI_InitStruct);

        /* Add IRQ vector to NVIC */
        /* PC0 is connected to EXTI_Line0, which has EXTI0_IRQn vector */
        NVIC_InitStruct.NVIC_IRQChannel = EXTI0_IRQn;
        /* Set priority */
        NVIC_InitStruct.NVIC_IRQChannelPreemptionPriority = E_PREEMPTION_PRIORITY;
        /* Set sub priority */
        NVIC_InitStruct.NVIC_IRQChannelSubPriority = 0x00;
        /* Enable interrupt */
        NVIC_InitStruct.NVIC_IRQChannelCmd = ENABLE;
        /* Add to NVIC */
        NVIC_Init(&NVIC_InitStruct);
}

void config_PC4_int(void) {
        EXTI_InitTypeDef EXTI_InitStruct;
        NVIC_InitTypeDef NVIC_InitStruct;

        /* Enable clock for SYSCFG */
        RCC_APB2PeriphClockCmd(RCC_APB2Periph_SYSCFG, ENABLE);

        SYSCFG_EXTILineConfig(EXTI_PortSourceGPIOC, EXTI_PinSource4);

        EXTI_InitStruct.EXTI_Line = EXTI_Line4;
        /* Enable interrupt */
        EXTI_InitStruct.EXTI_LineCmd = ENABLE;
        /* Interrupt mode */
        EXTI_InitStruct.EXTI_Mode = EXTI_Mode_Interrupt;
        /* Triggers on rising and falling edge */
        EXTI_InitStruct.EXTI_Trigger = EXTI_Trigger_Rising;
        /* Add to EXTI */
        EXTI_Init(&EXTI_InitStruct);

        /* Add IRQ vector to NVIC */
        /* PC0 is connected to EXTI_Line0, which has EXTI0_IRQn vector */
        NVIC_InitStruct.NVIC_IRQChannel = EXTI4_IRQn;
        /* Set priority */
        NVIC_InitStruct.NVIC_IRQChannelPreemptionPriority = E_PREEMPTION_PRIORITY;
        /* Set sub priority */
        NVIC_InitStruct.NVIC_IRQChannelSubPriority = 0x00;
        /* Enable interrupt */
        NVIC_InitStruct.NVIC_IRQChannelCmd = ENABLE;
        /* Add to NVIC */
        NVIC_Init(&NVIC_InitStruct);
}

/*
 * PC0(in)         - _E (p6)
   PC1(in)         - _CTS (p32) (the cartridge chip select)
   PC2(in)         - _P2 (p36)  (the $FF40-$FF5F chip select)

   PC3(in)         - R/_W (p18)
   PC4(in)         - OnePulse early interrupt
   PC5(out)        -  _NMI
   PC6(out)        - CART (PIA1 CB1)

   PC13(out)       - _HALT (only used by the Coco
*/
void config_gpio_portc(void) {
	GPIO_InitTypeDef  GPIO_InitStructure;
	/* GPIOC Periph clock enable */
	RCC_AHB1PeriphClockCmd(RCC_AHB1Periph_GPIOC, ENABLE);

	/* Configure GPIO Settings */
	// Make sure to init the PS2 keyboard pins here.
	GPIO_InitStructure.GPIO_Pin = GPIO_DRAGON_E | GPIO_DRAGON_CTS | GPIO_DRAGON_P2 | GPIO_DRAGON_RW | GPIO_ONE_PULSE | GPIO_DRAGON_RESET;
	GPIO_InitStructure.GPIO_Mode = GPIO_Mode_IN;
	GPIO_InitStructure.GPIO_OType = GPIO_OType_PP;
	GPIO_InitStructure.GPIO_Speed = GPIO_Speed_100MHz;
	//GPIO_InitStructure.GPIO_PuPd = GPIO_PuPd_DOWN;
	GPIO_InitStructure.GPIO_PuPd = GPIO_PuPd_NOPULL;
	GPIO_Init(GPIOC, &GPIO_InitStructure);

	GPIOC->PUPDR |= 0x00000002;	// TODO. not sure why I am adding a pullup to _CTS ???
	GPIO_InitStructure.GPIO_Pin =   GPIO_DRAGON_NMI | GPIO_DRAGON_CART | GPIO_TANDY_HALT;
	GPIO_InitStructure.GPIO_Mode = GPIO_Mode_OUT;
	GPIO_InitStructure.GPIO_OType = GPIO_OType_OD;
	//GPIO_InitStructure.GPIO_OType = GPIO_OType_PP;
	GPIO_InitStructure.GPIO_Speed = GPIO_Speed_100MHz;
	GPIO_InitStructure.GPIO_PuPd  = GPIO_PuPd_UP;
	GPIO_Init(GPIOC, &GPIO_InitStructure);
	// NB: Do not set CART high. It should be low.
	GPIOC->ODR = NMI_HIGH  | HALT_HIGH;
}

/* Input/Output data GPIO pins on PD{8..15}. Also PD2 is used fo MOSI on the STM32F407VET6 board I have */
void config_gpio_data(void) {
	GPIO_InitTypeDef  GPIO_InitStructure;
	/* GPIOD Periph clock enable */
	RCC_AHB1PeriphClockCmd(RCC_AHB1Periph_GPIOD, ENABLE);

	/* Configure GPIO Settings */
	GPIO_InitStructure.GPIO_Pin = GPIO_Pin_8 | GPIO_Pin_9 | GPIO_Pin_10 | GPIO_Pin_11 | 
		GPIO_Pin_12 | GPIO_Pin_13 | GPIO_Pin_14 | GPIO_Pin_15;
	GPIO_InitStructure.GPIO_Mode = GPIO_Mode_IN;
	GPIO_InitStructure.GPIO_OType = GPIO_OType_PP;
	GPIO_InitStructure.GPIO_Speed = GPIO_Speed_100MHz;
	GPIO_InitStructure.GPIO_PuPd = GPIO_PuPd_NOPULL;
	//GPIO_InitStructure.GPIO_PuPd = GPIO_PuPd_DOWN;
	GPIO_Init(GPIOD, &GPIO_InitStructure);

}

/* Input Address GPIO pins on PE{0..15} */
void config_gpio_addr(void) {
	GPIO_InitTypeDef  GPIO_InitStructure;
	/* GPIOE Periph clock enable */
	RCC_AHB1PeriphClockCmd(RCC_AHB1Periph_GPIOE, ENABLE);

	/* Configure GPIO Settings */
	GPIO_InitStructure.GPIO_Pin = 
		GPIO_Pin_0 | GPIO_Pin_1 | GPIO_Pin_2 | GPIO_Pin_3 | 
		GPIO_Pin_4 | GPIO_Pin_5 | GPIO_Pin_6 | GPIO_Pin_7 | 
		GPIO_Pin_8 | GPIO_Pin_9 | GPIO_Pin_10 | GPIO_Pin_11 | 
		GPIO_Pin_12 | GPIO_Pin_13 | GPIO_Pin_14 | GPIO_Pin_15;
	GPIO_InitStructure.GPIO_Mode = GPIO_Mode_IN;
	GPIO_InitStructure.GPIO_OType = GPIO_OType_PP;
	GPIO_InitStructure.GPIO_Speed = GPIO_Speed_100MHz;
	GPIO_InitStructure.GPIO_PuPd = GPIO_PuPd_DOWN;
	GPIO_Init(GPIOE, &GPIO_InitStructure);
}


/* Debug GPIO pins on PA6  / PA7 / PA8 */
void config_gpio_dbg(void) {
	GPIO_InitTypeDef  GPIO_InitStructure;
	/* GPIOA Periph clock enable */
	RCC_AHB1PeriphClockCmd(RCC_AHB1Periph_GPIOA, ENABLE);
        RCC_APB1PeriphClockCmd(RCC_APB1Periph_UART4,DISABLE);


	/* Configure GPIO Settings */
	//GPIO_InitStructure.GPIO_Pin = GPIO_Pin_6 | GPIO_Pin_7 | GPIO_Pin_8 ;
	GPIO_InitStructure.GPIO_Pin = GPIO_DEBUG_LED | GPIO_LOGIC_ANALYSER_DEBUG;
	GPIO_InitStructure.GPIO_Mode = GPIO_Mode_OUT;
	GPIO_InitStructure.GPIO_OType = GPIO_OType_PP;
	GPIO_InitStructure.GPIO_Speed = GPIO_Speed_100MHz;
	GPIO_InitStructure.GPIO_PuPd = GPIO_PuPd_NOPULL;
	GPIO_Init(GPIOA, &GPIO_InitStructure);
}

/* push buttons on PA2, PA3, ROM/DISK control on PA4  */
void config_gpio_buttons(void) {
	GPIO_InitTypeDef  GPIO_InitStructure;
	/* GPIOA Periph clock enable */
	RCC_AHB1PeriphClockCmd(RCC_AHB1Periph_GPIOA, ENABLE);


	/* Configure GPIO Settings */
	GPIO_InitStructure.GPIO_Pin = GPIO_NEXT_ITEM| GPIO_PREV_ITEM | GPIO_DRAGON_TANDY_MODE_CONTROL;
	GPIO_InitStructure.GPIO_Mode = GPIO_Mode_IN;
	GPIO_InitStructure.GPIO_OType = GPIO_OType_PP;
	GPIO_InitStructure.GPIO_Speed = GPIO_Speed_100MHz;
	GPIO_InitStructure.GPIO_PuPd = GPIO_PuPd_UP;
	GPIO_Init(GPIOA, &GPIO_InitStructure);
}


FRESULT load_disk_header(FIL *fil,char *fname, char *buffer) {
        UINT BytesRead;
        FRESULT res;
	FSIZE_t sz;

        res = f_open(fil, fname, FA_READ);
	sz = f_size(fil);

	if (suffix_match(fname, DSK_SUFFIX)) {

		buffer[VDK_HEADER_SIZE_LSB] = 0x00; /// make it so it wont seek at all
		buffer[VDK_HEADER_SIZE_MSB] = 0x00;

		switch (sz) {
			case DISK_40_18_256_SIZE:
				buffer[VDK_TRACKS] = 40;
				buffer[VDK_SIDES] = 1;
				break;
			case DISK_40_18_256_DOUBLE_SIDED_SIZE:
				buffer[VDK_TRACKS] = 40;
				buffer[VDK_SIDES] = 2;
				break;
			case DISK_80_18_256_DOUBLE_SIDED_SIZE:
				buffer[VDK_TRACKS] = 80;
				buffer[VDK_SIDES] = 2;
				break;
			case DISK_35_18_256_SIZE:
				buffer[VDK_TRACKS] = 35;
				buffer[VDK_SIDES] = 1;
				break;
		}

	}
	if (suffix_match(fname, VDK_SUFFIX)) {
        	if (res == FR_OK) {
               		res = f_read(fil, buffer, SIZE_OF_VDK_DISK_HEADER, &BytesRead);
        	} 
	}

        return res;
}


FRESULT __attribute__((optimize("O0")))  load_track(FIL *fil, uint32_t track_number, char *track, uint32_t header_length, uint32_t track_size) {
        UINT BytesRead;
        FRESULT res;
	uint32_t offset;

	offset = header_length + (track_number * track_size);

	res = f_lseek(fil, offset);
	if (res == FR_OK) {
		// load 2 sides regardless of whether the disk is single sided or not
		res = f_read(fil, track, 2 * 18 * 256, &BytesRead);
	} else {
                // it is possible after a weird reset that it will try to seek to some random value. Just return a blank track then.
                for (uint32_t i=0; i< SIZEOF_ONE_DISK_TRACK; i++) {
                        track[i] = 0;
                }
		// fake success
		res = FR_OK;
	}

	return res;
}

FRESULT __attribute__((optimize("O0"))) save_track(FIL *fil, uint32_t track_number, char *track, uint32_t header_length, uint32_t track_size) {
        UINT BytesWritten;
        FRESULT res;
	uint32_t offset;

	offset = header_length + (track_number * track_size);

	res = f_lseek(fil, offset);
	if (res == FR_OK) {
		res = f_write(fil, track, track_size, &BytesWritten);
	} else {
                blink_debug_led(3000);
	}
	return res;

}



void copy_rom_to_ram(uint8_t *from, uint8_t *to) {
   uint32_t *p, *q;
   // copy in 4 byte chunks
   p = (uint32_t *)from;
   q = (uint32_t *)to;

   for (int i=0; i< 0x0800;i++) {
      *q++ = *p++;
   }

}




int __attribute__((optimize("O0")))  main(void) {

        FIL fil;
	uint32_t track_size;
	uint32_t header_length;
	TCHAR full_filename[128];
	int next_button_debounce;
	int first_time;
	int special_reset_mode;
	uint32_t	button_state;
	int32_t	file_counter;
	uint32_t reset_counter;

        char *disk_header_ptr = (char *) &disk_header;

	char dosrom[15];

        TCHAR root_directory[15];
        DIR dir;
        static FILINFO fno;


	// You have to disable lazy stacking BEFORE initialising the scratch fpu registers
	enable_fpu_and_disable_lazy_stacking();
	init_fpu_regs();

	register uint32_t main_thread_command_reg asm("r10") __attribute__((unused)) = 0;

	rcc_set_frequency(SYSCLK_240_MHZ);

	RCC_AHB1PeriphClockCmd(RCC_AHB1Periph_CCMDATARAMEN, ENABLE);

	/* PD{8..15}  and PD2 for SD card MOSI*/
	config_gpio_data();
	/* PE{0..15} */
	config_gpio_addr();
	
	config_gpio_portc();

	config_gpio_dbg();

	config_gpio_buttons();

	config_backup_sram();


	// Make sure _RESET is high and stable before enabling interrupts
	reset_counter=0;
	while (reset_counter < 20) {
		reset_counter = (GPIOC->IDR & RESET_HIGH)? reset_counter+1 : 0;
		delay_us(2);
	}

	setupOnePulse();

	// Determine Tandy or Dargon mode via jumper. Do this before we turn interrupts on
	if (GPIOA->IDR & TANDY_DRAGON_MODE_MASK) {
		// Dragon 32 mode
		strcpy(root_directory,"dragon");
		strcpy(dosrom,"dragondos.rom");
		// bit 30 of reg_fdc_system is the tandy/dragon mode bit. 1 means Dragon mode
		__asm volatile("vmov r0,"XSTR(reg_fdc_system)"\n"
                      "orr r0,#"XSTR(S_DRAGON_TANDY_MODE)"\n"
		       "vmov "XSTR(reg_fdc_system)",r0\n"
                       :::);
	} else {
		// Tandy Coco mode
		strcpy(root_directory,"tandy");
		strcpy(dosrom,"tandydos.rom");
		// bit 30 of reg_fdc_system is the tandy/dragon mode bit. 0 means Tandy mode
		__asm volatile("vmov r0,"XSTR(reg_fdc_system)"\n"
                      "and r0,#~"XSTR(S_DRAGON_TANDY_MODE)"\n"
		       "vmov "XSTR(reg_fdc_system)",r0\n"
                       :::);
	}

	update_exti_exit_vector();

	//copy_rom_to_ram((uint8_t*) &rom_base, (uint8_t*) &high_64k_base);

	  // switch on compensation cell
	RCC->APB2ENR |= 0 |  RCC_APB2ENR_SYSCFGEN ;
	SYSCFG->CMPCR |= SYSCFG_CMPCR_CMP_PD; // enable compensation cell
	while ((SYSCFG->CMPCR & SYSCFG_CMPCR_READY) == 0);  // wait until ready

	NVIC_PriorityGroupConfig(NVIC_PriorityGroup_4); 
	SysTick->CTRL  = 0;

	SD_NVIC_Configuration();




	config_PC0_event();
	config_PC4_int();

        memset(&fs32, 0, sizeof(FATFS));
        res = f_mount(&fs32, "",0);
        if (res != FR_OK) {
                blink_debug_led(250);
        }


	init_fdc();
	// This next call just 'primes' the main_thread_data so that when the first disk image is loaded it loads track 0 rather than some unknown track
	copy_from_fdc_track_registers();



        res = f_opendir(&dir, root_directory);
        if (res != FR_OK) {
                blink_debug_led(100);
        }


	first_time=TRUE;
	next_button_debounce=0;
	file_counter=-1;

	// attempt to load the special menu rom. See kcdfs. Note kcdfs will talk to the stm32f4 and ask it whether its in Tandy or Dragon mode
	res = load_rom("menu.rom",(char *)&high_64k_base);
	if (res == FR_OK) {
		first_time=FALSE;
	}
	// This memset is actually really important
	memset(&fil, 0, sizeof(FIL));


	special_reset_mode = 0;

	while(1) {
		button_state = GPIOA->IDR;
		
		 /* doesnt work
		  if (!(GPIOC->IDR & RESET_HIGH)) {
			// _RESET is low
			if (!(button_state & NEXT_ROM_OR_DISK_MASK) || !(button_state & PREV_ROM_OR_DISK_MASK) ) {
				res = load_rom("menu.rom",(char *)&high_64k_base);
				if (res == FR_OK) {
					first_time=FALSE;
				}
				// This memset is actually really important
				memset(&fil, 0, sizeof(FIL));
				next_button_debounce=30000000;
			}
		}
		*/
		if (GPIOC->IDR & RESET_HIGH) {
			special_reset_mode=0;
		}
	
		if (!(button_state & NEXT_ROM_OR_DISK_MASK) || !(button_state & PREV_ROM_OR_DISK_MASK) || first_time) {
			first_time = FALSE;
			if (next_button_debounce == 0 ) {
				if (!(button_state & PREV_ROM_OR_DISK_MASK)) {
					// if we hit the prev button do the worlds worst way of finding the previous file
					if (file_counter >0) {
						res = f_closedir(&dir);
        					res = f_opendir(&dir, root_directory);
						for (uint32_t i=0;i< file_counter; i++) {
							res = f_readdir(&dir, &fno);                 
						}
						file_counter--;
					} else {
						// file_counter is 0 (ie. first file) and we hit PREV. Just keep it to the 
						// first file. Do not wrap round.
						//res = f_readdir(&dir, &fno);                 
						//
						// redo getting the first file
						f_closedir(&dir);
						res = f_opendir(&dir, root_directory);
						res = f_readdir(&dir, &fno);
						file_counter=0;
					}
				} else {
					// if we hit the next button or this is the first time through
					file_counter++;
					res = f_readdir(&dir, &fno);                 
					if (res != FR_OK || fno.fname[0] == 0) {
						// allow buttonpushes to 'wrap round'
						f_closedir(&dir);
						res = f_opendir(&dir, root_directory);
						res = f_readdir(&dir, &fno);
						file_counter=0;
					}
				}
				strcpy(full_filename,root_directory);
				strcat(full_filename,"/");
				strcat(full_filename,fno.fname);

				if (!(GPIOC->IDR & RESET_HIGH)) {
					// The logic here is that if you hold down reset then press + then -, then special_reset_mode == 1025. If you press + twice you get 2048. If you press - twice you get 2
					if (!(button_state & PREV_ROM_OR_DISK_MASK)) {
						special_reset_mode++;
					} else {
						special_reset_mode+=1024;
					}
				}
				if ( (special_reset_mode==0) && ((suffix_match(fno.fname, DSK_SUFFIX)) || (suffix_match(fno.fname, VDK_SUFFIX))) ) {
					// try to close any previous dsk
					if (fil.obj.id) {
						f_close(&fil);
						memset(&fil, 0, sizeof(FIL));
					}
					load_rom(dosrom,(char *)&high_64k_base);
					load_disk_header(&fil, full_filename, disk_header_ptr); 
					track_size = ( (uint32_t) disk_header_ptr[VDK_SIDES] * 18 * 256);
					global_track_size = track_size;
					header_length = ((uint32_t) disk_header_ptr[VDK_HEADER_SIZE_LSB]) + ((uint32_t) disk_header_ptr[VDK_HEADER_SIZE_MSB]<<8) ; 
					global_header_length = header_length;

					// take whatever the fdc_actual_track is and shove in to the track param for the SEEK
					//copy_from_fdc_track_registers();
					// trigger a seek in the next block of code.
					//main_thread_command_reg = MAIN_THREAD_SEEK_COMMAND;
					main_thread_command_reg = MAIN_THREAD_BUTTON_COMMAND;
					__asm volatile("vmov r0,"XSTR(reg_fdc_system)"\n"
                                               "orr r0,#"XSTR(S_FDC_PRESENT)"\n"
					       "vmov "XSTR(reg_fdc_system)",r0\n"
                                               :::);
				} else {
					// assume ROM
					if (special_reset_mode==MAGIC_BUTTON_SUM) {
						load_rom("menu.rom",(char *)&high_64k_base);
						special_reset_mode=0;
					} else {
						load_rom(full_filename,(char *)&high_64k_base);
					}
					__asm volatile("vmov r0,"XSTR(reg_fdc_system)"\n"
                                               "and r0,#~"XSTR(S_FDC_PRESENT)"\n"
					       "vmov "XSTR(reg_fdc_system)",r0\n"
                                               :::);
				}
				//next_button_debounce=5850000;
				next_button_debounce=3000000;
			} 
		}
		next_button_debounce = (next_button_debounce>0)?next_button_debounce-1:0;

		if (!(main_thread_command_reg & 0xf0000000) && (main_thread_command_reg & 0xff)) {
			switch(main_thread_command_reg & 0xff) {
				case (MAIN_THREAD_BUTTON_COMMAND): 
				case (MAIN_THREAD_SEEK_COMMAND): {
					main_thread_command_reg |= MAIN_COMMAND_IN_PROGRESS;
					// Check if there is any pending write
					if (fdc_write_flush_count) {
						fdc_write_flush_count=0;
						if (fil.obj.id) {
							f_close(&fil);
							memset(&fil, 0, sizeof(FIL));
						}
						res = f_open(&fil, full_filename, FA_WRITE);
						save_track(&fil, main_thread_actual_track, (char *) &track_buffer, header_length, track_size);
						f_close(&fil);
						memset(&fil, 0, sizeof(FIL));
						res = f_open(&fil, full_filename, FA_READ);

					}
					// main_thread_data contains the track number
					load_track(&fil, main_thread_data, (char *) &track_buffer, header_length, track_size);
					delay_ms(1);
					main_thread_actual_track = main_thread_data;
					update_fdc_track_registers();
					if ((main_thread_command_reg & 0xff) == MAIN_THREAD_SEEK_COMMAND) {
						main_thread_command_reg |= MAIN_COMMAND_SEEK_COMPLETE;
					} else {
						// must be a next/prev button push so make sure we don't feed an INTRQ in
					   	main_thread_command_reg = 0;
					}
					break;
				}
				case (MAIN_THREAD_COMMAND_LOAD_DIRECTORY): {
					main_thread_command_reg |= MAIN_COMMAND_IN_PROGRESS;
					menu_ctrl_file_count = load_directory(root_directory,(unsigned char *)(CCMRAM_BASE+0x4100));
					//unsigned char * p = (unsigned char *) (CCMRAM_BASE+0x4080);
					//*p = 0x00;
					main_thread_command_reg |= MAIN_COMMAND_LOAD_DIRECTORY_COMPLETE;
					break;
				}
				case (MAIN_THREAD_COMMAND_LOAD_ROM): {
					main_thread_command_reg |= MAIN_COMMAND_IN_PROGRESS;
					// The filename to load will be in CCMRAM+0x4000+0x00
					//
					char *fname = (char *) (CCMRAM_BASE+0x4000+0x00);
					file_counter=0;
					res = f_closedir(&dir);
        				res = f_opendir(&dir, root_directory);
					// Search for the file that the user selected. This is really just a cheap way
					// to have the directory pointer at the right spot, such that hitting NEXT
					// will advance you to the rom/disk the user expects to be next
					while (1) {
						res = f_readdir(&dir, &fno);                 
						if (res != FR_OK || fno.fname[0] == 0) {
							f_closedir(&dir);
							res = f_opendir(&dir, root_directory);
							res = f_readdir(&dir, &fno);
							file_counter=0;
							break;
						}
						if (strcmp(fno.fname,fname)==0) {
							break;
						}
						file_counter++;
					}
					strcpy(full_filename,root_directory);
					strcat(full_filename,"/");
					strcat(full_filename,fno.fname);
					if ( (suffix_match(fno.fname, DSK_SUFFIX)) || (suffix_match(fno.fname, VDK_SUFFIX)) ) {
						// try to close any previous dsk
						if (fil.obj.id) {
							f_close(&fil);
							memset(&fil, 0, sizeof(FIL));
						}
						load_rom(dosrom,(char *)&high_64k_base);
						load_disk_header(&fil, full_filename, disk_header_ptr); 
						track_size = ( (uint32_t) disk_header_ptr[VDK_SIDES] * 18 * 256);
						global_track_size = track_size;
						header_length = ((uint32_t) disk_header_ptr[VDK_HEADER_SIZE_LSB]) + ((uint32_t) disk_header_ptr[VDK_HEADER_SIZE_MSB]<<8) ; 
						global_header_length = header_length;

						main_thread_command_reg = MAIN_THREAD_BUTTON_COMMAND;
						__asm volatile("vmov r0,"XSTR(reg_fdc_system)"\n"
                                                       "orr r0,#"XSTR(S_FDC_PRESENT)"\n"
						       "vmov "XSTR(reg_fdc_system)",r0\n"
                                                       :::);
					} else {
						// assume ROM
						load_rom(full_filename,(char *)&high_64k_base);
						__asm volatile("vmov r0,"XSTR(reg_fdc_system)"\n"
                                                       "and r0,#~"XSTR(S_FDC_PRESENT)"\n"
						       "vmov "XSTR(reg_fdc_system)",r0\n"
                                                       :::);
					}
					main_thread_command_reg |= MAIN_COMMAND_LOAD_ROM_COMPLETE;
					break;
				}
			}
		}

		if (fdc_write_flush_count) {
			fdc_write_flush_count--;
			if (fdc_write_flush_count == 0) {
				if (fil.obj.id) {
					f_close(&fil);
					memset(&fil, 0, sizeof(FIL));
				}
				res = f_open(&fil, full_filename, FA_WRITE);
				save_track(&fil, main_thread_actual_track, (char *) &track_buffer, header_length, track_size);
				f_close(&fil);
				memset(&fil, 0, sizeof(FIL));
				res = f_open(&fil, full_filename, FA_READ);
			}
		}
	}
}

