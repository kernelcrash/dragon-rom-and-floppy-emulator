#ifndef __MAIN_H
#define __MAIN_H
#include <stdint.h>
#include "stm32f4xx.h"

typedef uint8_t boolean;
typedef uint8_t byte;


extern void init_fpu_regs(void);
extern void init_fdc(void);
extern void update_exti_exit_vector(void);
extern void e_follower(void);
extern void copy_from_fdc_track_registers(void);
extern void update_fdc_track_registers(void);

extern void deactivate_fdc(void);


#endif
