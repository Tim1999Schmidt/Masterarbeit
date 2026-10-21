/**
 ******************************************************************************
 * @file    mm_config.c
 * @brief   See mm_config.h.
 ******************************************************************************
 */
#include "mm_config.h"
#include <string.h>

#define FLASH_TOTAL_BYTES   (512u * 1024u)                /* STM32F303RE */
#define CFG_PAGE_ADDR       (FLASH_BASE + FLASH_TOTAL_BYTES - FLASH_PAGE_SIZE)   /* last 2 KB page: 0x0807F800 */
#define CFG_PAGE_COUNT      1u

/* Format version of the stored record. Load() only accepts a record with exactly
 * this version; an erased page reads 0xFFFF and is never taken as valid.
 * Increase it whenever the layout of CfgRecord_t changes. */
#define CFG_RECORD_VERSION  1u
#define CFG_RESERVED_FILL   0xFFu

typedef struct
{
    uint16_t version;               /* CFG_RECORD_VERSION */
    uint8_t  numBm;
    uint8_t  numPm;
    uint8_t  bmAddr[MM_MAX_BM];
    uint8_t  pmAddr[MM_MAX_PM];
    uint8_t  pmSource[MM_MAX_PM];
    uint8_t  reserved[2];           /* pads the record to whole halfwords */
    uint16_t check;                 /* ~(sum of all halfwords before it) */
} CfgRecord_t;

#define CFG_RECORD_HALFWORDS  (sizeof(CfgRecord_t) / sizeof(uint16_t))
typedef char cfg_record_whole_halfwords[(sizeof(CfgRecord_t) % sizeof(uint16_t) == 0u) ? 1 : -1];

static MmConfig_t cfg;

static uint16_t Check(const CfgRecord_t *r)
{
    const uint16_t *h = (const uint16_t *)r;
    uint16_t sum = 0u;
    uint32_t i;
    for (i = 0u; i < CFG_RECORD_HALFWORDS - 1u; i++)      /* all but the check itself */
        sum = (uint16_t)(sum + h[i]);
    return (uint16_t)~sum;
}

static void SetDefaults(MmConfig_t *c)
{
    uint8_t i;
    memset(c, 0, sizeof(*c));
    c->numBm = MM_DEFAULT_NUM_BM;
    c->numPm = MM_DEFAULT_NUM_PM;
    for (i = 0u; i < MM_MAX_BM; i++)
        c->bmAddr[i] = (uint8_t)(MM_DEFAULT_BM_ADDR_FIRST + i);
    for (i = 0u; i < MM_MAX_PM; i++)
    {
        c->pmAddr[i]   = (uint8_t)(MM_DEFAULT_PM_ADDR_FIRST + i);
        c->pmSource[i] = MM_PM_SOURCE_PT1000;
    }
}

uint8_t MmConfig_IsValid(const MmConfig_t *c)
{
    uint8_t all[MM_MAX_BM + MM_MAX_PM];
    uint8_t n = 0u, i, j;

    if (c->numBm < 1u || c->numBm > MM_MAX_BM || c->numPm > MM_MAX_PM)
        return 0u;
    for (i = 0u; i < c->numBm; i++)
        all[n++] = c->bmAddr[i];
    for (i = 0u; i < c->numPm; i++)
    {
        all[n++] = c->pmAddr[i];
        if (c->pmSource[i] > c->numBm)
            return 0u;
    }
    for (i = 0u; i < n; i++)
    {
        if (all[i] < MM_I2C_ADDR_MIN || all[i] > MM_I2C_ADDR_MAX)
            return 0u;
        for (j = (uint8_t)(i + 1u); j < n; j++)
            if (all[i] == all[j])
                return 0u;                        /* two boards on the same address */
    }
    return 1u;
}

void MmConfig_Load(void)
{
    CfgRecord_t r;
    memcpy(&r, (const void *)CFG_PAGE_ADDR, sizeof(r));

    SetDefaults(&cfg);
    if (r.version == CFG_RECORD_VERSION && r.check == Check(&r))
    {
        MmConfig_t c;
        memset(&c, 0, sizeof(c));
        c.numBm = r.numBm;
        c.numPm = r.numPm;
        memcpy(c.bmAddr,   r.bmAddr,   sizeof(c.bmAddr));
        memcpy(c.pmAddr,   r.pmAddr,   sizeof(c.pmAddr));
        memcpy(c.pmSource, r.pmSource, sizeof(c.pmSource));
        if (MmConfig_IsValid(&c))
            cfg = c;
    }
}

MmConfig_t *MmConfig_Get(void)
{
    return &cfg;
}

uint8_t MmConfig_Save(void)
{
    CfgRecord_t r;
    FLASH_EraseInitTypeDef erase;
    uint32_t pageError = 0u, i;
    const uint16_t *h = (const uint16_t *)&r;
    uint8_t ok = 1u;

    memset(&r, CFG_RESERVED_FILL, sizeof(r));
    r.version = CFG_RECORD_VERSION;
    r.numBm   = cfg.numBm;
    r.numPm   = cfg.numPm;
    memcpy(r.bmAddr,   cfg.bmAddr,   sizeof(r.bmAddr));
    memcpy(r.pmAddr,   cfg.pmAddr,   sizeof(r.pmAddr));
    memcpy(r.pmSource, cfg.pmSource, sizeof(r.pmSource));
    r.check = Check(&r);

    if (memcmp((const void *)CFG_PAGE_ADDR, &r, sizeof(r)) == 0)
        return 1u;                                /* unchanged: no erase (flash endurance) */

    erase.TypeErase   = FLASH_TYPEERASE_PAGES;
    erase.PageAddress = CFG_PAGE_ADDR;
    erase.NbPages     = CFG_PAGE_COUNT;

    if (HAL_FLASH_Unlock() != HAL_OK)
        return 0u;
    if (HAL_FLASHEx_Erase(&erase, &pageError) != HAL_OK)
        ok = 0u;
    for (i = 0u; ok && i < CFG_RECORD_HALFWORDS; i++)
    {
        if (HAL_FLASH_Program(FLASH_TYPEPROGRAM_HALFWORD, CFG_PAGE_ADDR + i * sizeof(uint16_t), h[i]) != HAL_OK)
            ok = 0u;
    }
    (void)HAL_FLASH_Lock();

    return (ok && memcmp((const void *)CFG_PAGE_ADDR, &r, sizeof(r)) == 0) ? 1u : 0u;
}
