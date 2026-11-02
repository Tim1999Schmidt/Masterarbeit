/**
 ******************************************************************************
 * @file    mm_config.h
 * @brief   Board list of the MM: which BMs and PMs are on the I2C bus, plus
 *          the temperature source of each PM. Kept in the last flash page.
 *
 * The number of boards is variable (1..MM_MAX_BM BMs, 0..MM_MAX_PM PMs). The
 * list is set from the GUI (commands CFGBM / CFGPM / PMSRC, host_comm.h) and
 * written to flash with SAVE. The order of the list is the board number used
 * everywhere else: BM 1 = first BM address in the list, and so on.
 *
 * Flash: last 2 KB page of the 512 KB flash of the STM32F303RE
 * (0x0807F800..0x0807FFFF), excluded from the program in the linker script
 * (STM32F303RETX_FLASH.ld: FLASH LENGTH = 510K).
 ******************************************************************************
 */
#ifndef MM_CONFIG_H
#define MM_CONFIG_H

#include "main.h"
#include <stdint.h>

#define MM_MAX_BM             8u
#define MM_MAX_PM             8u

#define MM_I2C_ADDR_MIN       0x08u    /* 7-bit addresses 0x00..0x07 and 0x78..0x7F are reserved */
#define MM_I2C_ADDR_MAX       0x77u

/* Address of a BM / PM whose address was never set: the firmware default of
 * the boards. It is not a valid board address - such a board must first get
 * its own address over its debug console ("addr"). The MM watches these two
 * addresses and reports a board found there (WARN;NOADDR, host_comm.h). */
#define MM_UNASSIGNED_BM_ADDR 0x10u    /* BM_DEFAULT_I2C_ADDR of the BM firmware */
#define MM_UNASSIGNED_PM_ADDR 0x20u    /* PM_DEFAULT_I2C_ADDR of the PM firmware */

/* defaults for an unprogrammed MM: the current setup with 2 BMs and 2 PMs */
#define MM_DEFAULT_NUM_BM     2u
#define MM_DEFAULT_NUM_PM     2u
#define MM_DEFAULT_BM_ADDR_FIRST  (MM_UNASSIGNED_BM_ADDR + 1u)   /* BM 1 = 0x11, BM 2 = 0x12, ... */
#define MM_DEFAULT_PM_ADDR_FIRST  (MM_UNASSIGNED_PM_ADDR + 1u)   /* PM 1 = 0x21, PM 2 = 0x22, ... */

/* temperature source of a PM: the onboard PT1000, or the tab sensor of BM k
 * (1..numBm) whose temperature the MM forwards to the PM (T_EXT) */
#define MM_PM_SOURCE_PT1000   0u

typedef struct
{
    uint8_t numBm;
    uint8_t numPm;
    uint8_t bmAddr[MM_MAX_BM];
    uint8_t pmAddr[MM_MAX_PM];
    uint8_t pmSource[MM_MAX_PM];   /* MM_PM_SOURCE_PT1000 or BM number 1..numBm */
} MmConfig_t;

/* Loads the board list from flash (defaults if the page is empty / invalid). */
void MmConfig_Load(void);

/* Current board list (RAM copy). */
MmConfig_t *MmConfig_Get(void);

/* Checks a list: counts in range, addresses valid, all different and none of
 * the unassigned addresses, PM sources pointing at existing BMs. Returns 1 if valid. */
uint8_t MmConfig_IsValid(const MmConfig_t *cfg);

/* Writes the RAM copy to flash (skipped if unchanged). Returns 1 on success. */
uint8_t MmConfig_Save(void);

#endif /* MM_CONFIG_H */
