/**
 ******************************************************************************
 * @file    pm_settings.h
 * @brief   Per-board settings of the PM, kept in the last flash page.
 *
 * Every PM runs the same firmware. With several PMs on the I2C bus of the
 * master board (MM) each one needs its own slave address. It is stored in
 * flash and set once over the debug console (uart_comm.h, command "addr"),
 * same principle as on the BM (bm_config.h).
 *
 * The page used is the last 2 KB page of the 32 KB flash (page 15,
 * 0x08007800..0x08007FFF). It is excluded from the program in the linker
 * script (STM32C051K6TX_FLASH.ld: FLASH LENGTH = 30K), so the code can never
 * grow into it.
 ******************************************************************************
 */
#ifndef PM_SETTINGS_H
#define PM_SETTINGS_H

#include "main.h"
#include <stdint.h>

#define PM_I2C_ADDR_MIN       0x08u    /* 7-bit addresses 0x00..0x07 and 0x78..0x7F are reserved by the I2C standard */
#define PM_I2C_ADDR_MAX       0x77u
#define PM_DEFAULT_I2C_ADDR   0x28u    /* unprogrammed board; further PMs: 0x29, 0x2A, ... (BMs use 0x30 ...) */

typedef struct
{
    uint8_t i2cAddr;      /* PM_I2C_ADDR_MIN..PM_I2C_ADDR_MAX */
} PmSettings_t;

/* Loads the settings from flash (defaults if the page is empty / invalid).
 * Called by I2cComm_Init(); calling it again is harmless. */
void PmSettings_Load(void);

/* Current settings (RAM copy). Change fields, then call PmSettings_Save(). */
PmSettings_t *PmSettings_Get(void);

/* Writes the RAM copy to flash (erase + program, ~25 ms, CPU stalls meanwhile).
 * Does nothing if the flash already holds exactly these values (flash
 * endurance). Only the console command "addr" calls it. Returns 1 on success. */
uint8_t PmSettings_Save(void);

#endif /* PM_SETTINGS_H */
