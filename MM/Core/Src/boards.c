/**
 ******************************************************************************
 * @file    boards.c
 * @brief   See boards.h.
 ******************************************************************************
 */
#include "boards.h"
#include "bm_regs.h"
#include "pm_regs.h"
#include "i2c_bus.h"
#include <string.h>

#define PM_GAINS_FIRST   PM_REG_KP
#define PM_GAINS_COUNT   3u          /* KP, KI, KD */
#define BITS_PER_BYTE    8u

static BmData_t bm[MM_MAX_BM];
static PmData_t pm[MM_MAX_PM];
static uint32_t lastPollTick;

/* ---- helpers --------------------------------------------------------------- */
static uint8_t BmAddr(uint8_t i) { return MmConfig_Get()->bmAddr[i]; }
static uint8_t PmAddr(uint8_t i) { return MmConfig_Get()->pmAddr[i]; }

static void MarkFailed(uint8_t *online, uint8_t *failCount)
{
    if (*failCount < BOARDS_OFFLINE_AFTER_FAILS)
        (*failCount)++;
    if (*failCount >= BOARDS_OFFLINE_AFTER_FAILS)
        *online = 0u;
}

static void MarkOk(uint8_t *online, uint8_t *failCount)
{
    *failCount = 0u;
    *online = 1u;
}

static uint8_t ReadPm(uint8_t i)
{
    uint8_t r[PM_TELEMETRY_LEN];
    PmData_t *d = &pm[i];

    if (!I2cBus_Read(PmAddr(i), PM_TELEMETRY_FIRST, r, sizeof(r)))
    {
        MarkFailed(&d->online, &d->failCount);
        return 0u;
    }
    d->status       = r[PM_REG_STATUS];
    d->errorCode    = r[PM_REG_ERROR_CODE];
    d->tempSource   = r[PM_REG_TEMP_SOURCE];
    d->tSetCenti    = I2cBus_GetI16(&r[PM_REG_T_SET]);
    d->tActualCenti = I2cBus_GetI16(&r[PM_REG_T_ACTUAL]);
    d->tPt1000Centi = I2cBus_GetI16(&r[PM_REG_T_PT1000]);
    d->kpMilli      = I2cBus_GetU16(&r[PM_REG_KP]);
    d->kiMilli      = I2cBus_GetU16(&r[PM_REG_KI]);
    d->kdMilli      = I2cBus_GetU16(&r[PM_REG_KD]);
    d->iLimitMa     = I2cBus_GetU16(&r[PM_REG_I_LIMIT]);
    d->iActualMa    = I2cBus_GetU16(&r[PM_REG_I_ACTUAL]);
    d->dutyMilli    = I2cBus_GetU16(&r[PM_REG_DUTY_CYCLE]);
    MarkOk(&d->online, &d->failCount);
    return 1u;
}

/* Forwards the tab temperature of the assigned BM (if any) and keeps the PM's
 * TEMP_SOURCE register in line with the board list. */
static uint8_t ForwardSource(uint8_t i)
{
    const uint8_t source = MmConfig_Get()->pmSource[i];

    if (source == MM_PM_SOURCE_PT1000)
    {
        if (pm[i].online && pm[i].tempSource != PM_SOURCE_PT1000)
            return I2cBus_WriteByte(PmAddr(i), PM_REG_TEMP_SOURCE, PM_SOURCE_PT1000);
        return 1u;
    }
    else
    {
        const BmData_t *b = &bm[source - 1u];            /* source = BM number 1..numBm */
        if (!b->online || (b->status & BM_ST_TEMP_VALID) == 0u)
            return 1u;                                   /* nothing valid to forward */
        /* T_EXT first: the PM only accepts the external source once a value exists */
        if (!I2cBus_WriteU16(PmAddr(i), PM_REG_T_EXT, (uint16_t)b->tTabCenti))
            return 0u;
        if (pm[i].tempSource != PM_SOURCE_EXTERNAL)
            return I2cBus_WriteByte(PmAddr(i), PM_REG_TEMP_SOURCE, PM_SOURCE_EXTERNAL);
        return 1u;
    }
}

/* ---- public ------------------------------------------------------------------- */
void Boards_Init(void)
{
    memset(bm, 0, sizeof(bm));
    memset(pm, 0, sizeof(pm));
    lastPollTick = HAL_GetTick() - BOARDS_POLL_PERIOD_MS;   /* first poll right away */
}

void Boards_Process(void)
{
    const MmConfig_t *c = MmConfig_Get();
    uint8_t i;

    if ((HAL_GetTick() - lastPollTick) < BOARDS_POLL_PERIOD_MS)
        return;
    lastPollTick = HAL_GetTick();

    for (i = 0u; i < c->numBm; i++)
        (void)Boards_RefreshBm(i);
    for (i = 0u; i < c->numPm; i++)
    {
        if (ReadPm(i))
            (void)ForwardSource(i);
    }
}

const BmData_t *Boards_GetBm(uint8_t index) { return &bm[index]; }
const PmData_t *Boards_GetPm(uint8_t index) { return &pm[index]; }

uint8_t Boards_RefreshBm(uint8_t i)
{
    uint8_t r[BM_TELEMETRY_LEN];
    BmData_t *d = &bm[i];

    if (!I2cBus_Read(BmAddr(i), BM_TELEMETRY_FIRST, r, sizeof(r)))
    {
        MarkFailed(&d->online, &d->failCount);
        return 0u;
    }
    d->status    = r[BM_REG_STATUS];
    d->errorCode = r[BM_REG_ERROR_CODE];
    d->connectZ  = r[BM_REG_CONNECT_Z];
    d->numEis    = r[BM_REG_NUM_EIS];
    d->progress  = r[BM_REG_PROGRESS];
    d->uCellMv   = I2cBus_GetU16(&r[BM_REG_U_CELL]);
    d->iCellMa   = I2cBus_GetI16(&r[BM_REG_I_CELL]);
    d->tTabCenti = I2cBus_GetI16(&r[BM_REG_T_TAB]);
    MarkOk(&d->online, &d->failCount);
    return 1u;
}

/* ---- BM commands ---- */
uint8_t Boards_BmControl(uint8_t i, uint8_t controlBits)
{
    return I2cBus_WriteByte(BmAddr(i), BM_REG_CONTROL, controlBits);
}

uint8_t Boards_BmSetConnectZ(uint8_t i, uint8_t on)
{
    return I2cBus_WriteByte(BmAddr(i), BM_REG_CONNECT_Z, on ? BM_CONNECT_Z_ON : BM_CONNECT_Z_OFF);
}

uint8_t Boards_BmWriteEisParams(uint8_t i, const uint8_t *params)
{
    return I2cBus_Write(BmAddr(i), BM_EIS_PARAM_FIRST, params, BM_EIS_PARAM_LEN);
}

uint8_t Boards_BmReadResult(uint8_t i, uint8_t freqIndex, uint8_t *valid,
                            uint32_t *freqCentiHz, int32_t *reUOhm, int32_t *imUOhm)
{
    uint8_t r[BM_RESULT_LEN];

    /* select the frequency (separate write, ends with STOP), then read the window */
    if (!I2cBus_WriteByte(BmAddr(i), BM_REG_RES_INDEX, freqIndex))
        return 0u;
    if (!I2cBus_Read(BmAddr(i), BM_RESULT_FIRST, r, sizeof(r)))
        return 0u;
    *valid       = r[BM_REG_RES_VALID - BM_RESULT_FIRST];
    *freqCentiHz = I2cBus_GetU32(&r[BM_REG_RES_FREQ - BM_RESULT_FIRST]);
    *reUOhm      = I2cBus_GetI32(&r[BM_REG_RES_RE - BM_RESULT_FIRST]);
    *imUOhm      = I2cBus_GetI32(&r[BM_REG_RES_IM - BM_RESULT_FIRST]);
    return 1u;
}

/* ---- PM commands ---- */
uint8_t Boards_PmControl(uint8_t i, uint8_t controlBits)
{
    return I2cBus_WriteByte(PmAddr(i), PM_REG_CONTROL, controlBits);
}

uint8_t Boards_PmSetSetpoint(uint8_t i, int16_t tSetCenti)
{
    return I2cBus_WriteU16(PmAddr(i), PM_REG_T_SET, (uint16_t)tSetCenti);
}

uint8_t Boards_PmSetCurrentLimit(uint8_t i, uint16_t limitMa)
{
    return I2cBus_WriteU16(PmAddr(i), PM_REG_I_LIMIT, limitMa);
}

uint8_t Boards_PmSetGains(uint8_t i, uint16_t kpMilli, uint16_t kiMilli, uint16_t kdMilli)
{
    const uint16_t g[PM_GAINS_COUNT] = { kpMilli, kiMilli, kdMilli };
    uint8_t b[PM_GAINS_COUNT * sizeof(uint16_t)];
    uint8_t k;
    for (k = 0u; k < PM_GAINS_COUNT; k++)
    {
        b[sizeof(uint16_t) * k]      = (uint8_t)g[k];
        b[sizeof(uint16_t) * k + 1u] = (uint8_t)(g[k] >> BITS_PER_BYTE);
    }
    return I2cBus_Write(PmAddr(i), PM_GAINS_FIRST, b, sizeof(b));   /* one write: applied together */
}

uint8_t Boards_PmApplySource(uint8_t i)
{
    if (!ReadPm(i))
        return 0u;
    return ForwardSource(i);
}
