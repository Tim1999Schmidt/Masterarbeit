/**
 ******************************************************************************
 * @file    pm_settings.h
 * @brief   Per-board settings of the PM, kept in the last flash page.
 *
 * Every PM runs the same firmware. What differs between the boards is stored
 * in flash and set once over the debug console (uart_comm.h), same principle
 * as on the BM (bm_config.h):
 *   i2cAddr     I2C slave address (command "addr"): several PMs share the bus
 *   iGainScale  calibration factor of the current measurement (command
 *               "igain"): tolerance of shunt, amplifier gain and VDDA
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
#define PM_DEFAULT_I2C_ADDR   0x20u    /* unprogrammed board; further PMs: 0x21, 0x22, ... (BMs use 0x10 ...) */

/* current calibration factor in 1/10000: measured current x iGainScale / 10000 */
#define PM_I_GAIN_SCALE_ONE   10000u   /* factor 1.0000 = nominal (default) */
#define PM_I_GAIN_SCALE_MIN    8000u   /* 0.8 .. 1.2: larger corrections point to a hardware fault */
#define PM_I_GAIN_SCALE_MAX   12000u

typedef struct
{
    uint8_t  i2cAddr;     /* PM_I2C_ADDR_MIN..PM_I2C_ADDR_MAX */
    uint16_t iGainScale;  /* PM_I_GAIN_SCALE_MIN..PM_I_GAIN_SCALE_MAX */
} PmSettings_t;

/* Loads the settings from flash (defaults if the page is empty / invalid).
 * Called by CurrentSensor_Init() and I2cComm_Init(); calling it again is harmless. */
void PmSettings_Load(void);

/* Current settings (RAM copy). Change fields, then call PmSettings_Save(). */
PmSettings_t *PmSettings_Get(void);

/* Writes the RAM copy to flash (erase + program, ~25 ms, CPU stalls meanwhile).
 * Does nothing if the flash already holds exactly these values (flash
 * endurance). Only the console commands "addr" and "igain" call it. Returns 1 on success. */
uint8_t PmSettings_Save(void);

#endif /* PM_SETTINGS_H */
