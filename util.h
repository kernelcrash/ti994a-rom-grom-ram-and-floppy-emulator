#ifndef __UTIL_H
#define __UTIL_H

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "stm32f4xx.h"

#include "ff.h"
#include "main.h"

#include "defines.h"

void delay_us(const uint16_t us);
void delay_ms(const uint16_t ms);
void blink_debug_led(int delay);

uint32_t suffix_match(char *name, char *suffix);
FRESULT load_rom(char *fname, unsigned char* buffer, uint32_t max_size, uint32_t blank_remaining) ;
void load_rom_and_grom_and_disk_name(char *app_directory, unsigned char*rom_buffer, unsigned char *grom_buffer, DSK *dsk);

uint32_t load_directory(char *dirname, uint16_t *index_buffer, uint32_t max_files,  uint32_t base_offset);

extern void enable_pcard(void);
extern void disable_pcard(void);


#endif
