/**
 ******************************************************************************
 * @file    pm_settings.c
 * @brief   See pm_settings.h. Same flash procedure as bm_config.c of the BM.
 ******************************************************************************
 */
#include "pm_settings.h"
#include <string.h>

#define CFG_PAGE          15u
#define CFG_ADDR          (FLASH_BASE + CFG_PAGE * FLASH_PAGE_SIZE)   /* 0x08007800 */

/* Format version of the stored record. Load() only accepts a record with exactly
 * this version; an erased page reads 0xFFFF and is therefore never taken as valid.
 * Increase it whenever the layout of CfgRecord_t changes. */
#define CFG_RECORD_VERSION  1u
#define CFG_RESERVED_FILL   0xFFu     /* unused bytes of the record */

/* Interim version 2 (16 bytes, separate factors for heating and cooling) is
 * still read once, so boards keep their I2C address: the two factors are
 * averaged. The next save writes version 1 again. */
#define CFG_RECORD_VERSION_V2   2u
#define CFG_V2_RESERVED_HALFWORDS 3u
#define CFG_V2_GAIN_COUNT       2u    /* heating + cooling, averaged */

/* Stored record: exactly one 64-bit double word (the flash programming unit).
 * iGainScale uses two bytes that were reserved in the first layout: a record
 * written before still has 0xFFFF there, which is out of range and therefore
 * replaced by the default 1.0000 (same version number, the check covers it). */
typedef struct
{
    uint16_t version;    /* CFG_RECORD_VERSION */
    uint8_t  i2cAddr;
    uint8_t  reserved;
    uint16_t iGainScale;
    uint16_t check;      /* ~(sum of the 3 halfwords above) */
} CfgRecord_t;

typedef char cfg_record_is_8_bytes[(sizeof(CfgRecord_t) == 8u) ? 1 : -1];

typedef struct
{
    uint16_t version;    /* CFG_RECORD_VERSION_V2 */
    uint8_t  i2cAddr;
    uint8_t  reserved;
    uint16_t iGainHeat;
    uint16_t iGainCool;
    uint16_t reserved2[CFG_V2_RESERVED_HALFWORDS];
    uint16_t check;      /* ~(sum of all halfwords above) */
} CfgRecordV2_t;

#define CFG_V2_HALFWORDS  (sizeof(CfgRecordV2_t) / sizeof(uint16_t))

typedef char cfg_record_v2_is_16_bytes[(sizeof(CfgRecordV2_t) == 16u) ? 1 : -1];

/* timeout of WaitReady() in polling loops: a page erase takes ~22 ms, the loop
 * runs at least ~1 M times per 100 ms at 48 MHz -> generous margin */
#define FLASH_WAIT_LOOPS  2000000u

#define FLASH_SR_ERRORS  (FLASH_SR_OPERR | FLASH_SR_PROGERR | FLASH_SR_WRPERR | FLASH_SR_PGAERR | \
                          FLASH_SR_SIZERR | FLASH_SR_PGSERR | FLASH_SR_MISERR | FLASH_SR_FASTERR | \
                          FLASH_SR_RDERR | FLASH_SR_OPTVERR)

static PmSettings_t settings;

static uint16_t Check(const CfgRecord_t *r)
{
    const uint16_t *h = (const uint16_t *)r;
    return (uint16_t)~(uint16_t)(h[0] + h[1] + h[2]);
}

static uint16_t CheckV2(const CfgRecordV2_t *r)
{
    const uint16_t *h = (const uint16_t *)r;
    uint16_t sum = 0u;
    uint32_t i;
    for (i = 0u; i < CFG_V2_HALFWORDS - 1u; i++)
        sum = (uint16_t)(sum + h[i]);
    return (uint16_t)~sum;
}

void PmSettings_Load(void)
{
    CfgRecord_t r;
    CfgRecordV2_t r2;
    memcpy(&r, (const void *)CFG_ADDR, sizeof(r));
    memcpy(&r2, (const void *)CFG_ADDR, sizeof(r2));
    if (r2.version == CFG_RECORD_VERSION_V2 && r2.check == CheckV2(&r2))
    {
        r.version    = CFG_RECORD_VERSION;   /* convert, then validate as usual */
        r.i2cAddr    = r2.i2cAddr;
        r.iGainScale = (uint16_t)(((uint32_t)r2.iGainHeat + r2.iGainCool) / CFG_V2_GAIN_COUNT);
        r.check      = Check(&r);
    }

    settings.i2cAddr    = PM_DEFAULT_I2C_ADDR;
    settings.iGainScale = PM_I_GAIN_SCALE_ONE;
    if (r.version == CFG_RECORD_VERSION && r.check == Check(&r))
    {
        if (r.i2cAddr >= PM_I2C_ADDR_MIN && r.i2cAddr <= PM_I2C_ADDR_MAX)
            settings.i2cAddr = r.i2cAddr;
        if (r.iGainScale >= PM_I_GAIN_SCALE_MIN && r.iGainScale <= PM_I_GAIN_SCALE_MAX)
            settings.iGainScale = r.iGainScale;
    }
}

PmSettings_t *PmSettings_Get(void)
{
    return &settings;
}

/* ---- flash access directly via the registers (no HAL RAM function) ---- */
static uint8_t WaitReady(void)
{
    uint32_t guard = FLASH_WAIT_LOOPS;
    while ((FLASH->SR & (FLASH_SR_BSY1 | FLASH_SR_CFGBSY)) != 0u)
    {
        if (--guard == 0u)
            return 0u;
    }
    return ((FLASH->SR & FLASH_SR_ERRORS) == 0u) ? 1u : 0u;
}

static uint8_t ErasePageAndProgram(const uint32_t w[2])
{
    uint8_t ok;

    FLASH->KEYR = FLASH_KEY1;                    /* unlock sequence (RM0490, FLASH_KEYR) */
    FLASH->KEYR = FLASH_KEY2;
    FLASH->SR = FLASH_SR_ERRORS | FLASH_SR_EOP;   /* clear old flags */

    ok = WaitReady();
    if (ok)
    {
        FLASH->CR = FLASH_CR_PER | (CFG_PAGE << FLASH_CR_PNB_Pos);
        FLASH->CR |= FLASH_CR_STRT;
        ok = WaitReady();
        FLASH->CR &= ~FLASH_CR_PER;
    }
    if (ok)
    {
        FLASH->CR |= FLASH_CR_PG;
        *(volatile uint32_t *)CFG_ADDR        = w[0];   /* a double word: two word writes */
        *(volatile uint32_t *)(CFG_ADDR + 4u) = w[1];
        ok = WaitReady();
        FLASH->CR &= ~FLASH_CR_PG;
    }
    FLASH->SR = FLASH_SR_ERRORS | FLASH_SR_EOP;
    FLASH->CR |= FLASH_CR_LOCK;
    return ok;
}

uint8_t PmSettings_Save(void)
{
    CfgRecord_t r;
    uint32_t w[2];

    r.version = CFG_RECORD_VERSION;
    r.i2cAddr    = settings.i2cAddr;
    r.reserved   = CFG_RESERVED_FILL;
    r.iGainScale = settings.iGainScale;
    r.check   = Check(&r);

    if (memcmp((const void *)CFG_ADDR, &r, sizeof(r)) == 0)
        return 1u;                               /* unchanged: no erase/program */

    memcpy(w, &r, sizeof(w));
    if (!ErasePageAndProgram(w))
        return 0u;
    return (memcmp((const void *)CFG_ADDR, &r, sizeof(r)) == 0) ? 1u : 0u;
}
