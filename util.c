#include "util.h"

// probably have to tweak these if the processor speed changes. Just have to be rough
void delay_us(const uint16_t us)
{
   uint32_t i = us * 60;
   while (i-- > 0) {
      __asm volatile ("nop");
   }
}

void delay_ms(const uint16_t ms)
{
   //uint32_t i = ms * 27778;
   uint32_t i = ms * 30000 *2;
   while (i-- > 0) {
      __asm volatile ("nop");
   }
}

void blink_debug_led(int delay) {
        while(1) {
                GPIOA->ODR |= GPIO_DEBUG_LED;
                delay_ms(delay);
                GPIOA->ODR &= ~(GPIO_DEBUG_LED);
                delay_ms(delay);
        }
}

uint32_t suffix_match(char *name, char *suffix) {
	if (strlen(name)>strlen(suffix)) {
		if (strncasecmp (&name[strlen(name)-strlen(suffix)],suffix,strlen(suffix)) == 0) {
			return TRUE;
		}
	}
	return FALSE;
}

// Load fname rom file. 8K files get repeated up to 16K
FRESULT load_rom(char *fname, char* highbuffer) {
	FRESULT res;
        FIL     fil;
        UINT BytesRead;
	uint32_t *p;
	uint32_t *q;

	memset(&fil, 0, sizeof(FIL));

	res =  f_open(&fil, fname, FA_READ);

	if (res == FR_OK) {
		res = f_read(&fil,highbuffer, 16384, &BytesRead);
		if (res != FR_OK) {
			blink_debug_led(3000);
		} else {
			if (BytesRead == 8192) {
				p = (uint32_t *) highbuffer;
   				q = (uint32_t *) &highbuffer[8192];
   				for (int i=0; i< 0x0800;i++) {
      					*q++ = *p++;
   				}
			}
#ifdef ENABLE_SEMIHOSTING
	                printf("Read %d bytes in to %0x08x\n",BytesRead,highbuffer);
#endif
		}
		
	}
	f_close(&fil);
	return res;
}

// This just lists the files in a directory one by one
// Each filename is written to the buffer 128 bytes apart and are null ended
// return the number of files read
uint32_t load_directory(char *dirname, unsigned char*buffer) {
	FRESULT res;
        DIR dir;
        static FILINFO fno;
	uint32_t file_index,blanks;
	int i;

	memset(&dir, 0, sizeof(DIR));
        res = f_opendir(&dir, (TCHAR *) dirname);
        if (res != FR_OK) {
                blink_debug_led(2000);
        }

	file_index=0;
	while (file_index<126) {
		res = f_readdir(&dir, &fno);
		if (res != FR_OK || fno.fname[0] == 0) {
			//buffer[(file_index*0x80)]=0;
			break;
		}
		i=0;
		do {
			buffer[(file_index*0x80)+i] = fno.fname[i];
			if (i>126) {
				buffer[(file_index*0x80)+i]=0;
				break;
			}
		} while (fno.fname[i++]!=0);
		file_index++;
	}
	// Put lots of 0x00's in for the remaining entries (should roughly fill out the 16KB chunk reserved for filenames)
	for (blanks = file_index; blanks <126; blanks++) {
		buffer[(blanks*0x80)]=0;
	}

	res = f_closedir(&dir);
	return file_index;
}

