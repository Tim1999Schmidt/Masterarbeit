/**
 ******************************************************************************
 * @file    boards.h
 * @brief   State of all BMs and PMs on the bus and the commands to them.
 *
 * Boards_Process() reads the telemetry of every board in the list
 * (mm_config.h) every BOARDS_POLL_PERIOD_MS. A board counts as offline after
 * BOARDS_OFFLINE_AFTER_FAILS failed reads in a row and online again after the
 * first good read.
 *
 * Temperature source of a PM: if the board list assigns the tab sensor of a
 * BM to a PM (MmConfig_t.pmSource), the MM forwards that BM's T_TAB to the
 * PM's T_EXT on every poll (the PM expects a new value at least every 2 s)
 * and keeps the PM's TEMP_SOURCE register set to "external". This is also
 * re-applied after a PM was reset. If the BM's temperature is not valid,
 * nothing is forwarded, the PM runs into its T_EXT timeout and stops with
 * error 5 (intended: no regulation on a stale temperature).
 *
 * Board numbers in this API are 0-based indices into the board list.
 ******************************************************************************
 */
#ifndef BOARDS_H
#define BOARDS_H

#include "main.h"
#include "mm_config.h"
#include <stdint.h>

#define BOARDS_POLL_PERIOD_MS        500u
#define BOARDS_OFFLINE_AFTER_FAILS   3u

typedef struct
{
    uint8_t  online;
    uint8_t  status;        /* BM_ST_* */
    uint8_t  errorCode;     /* BM_ERR_* */
    uint8_t  connectZ;
    uint8_t  numEis;
    uint8_t  progress;      /* BM_PROGRESS_IDLE when idle */
    uint16_t uCellMv;
    int16_t  iCellMa;
    int16_t  tTabCenti;     /* degC x100 */
    uint8_t  failCount;
} BmData_t;

typedef struct
{
    uint8_t  online;
    uint8_t  status;        /* PM_ST_* */
    uint8_t  errorCode;     /* PM_ERR_* */
    uint8_t  tempSource;    /* PM_SOURCE_* as reported by the PM */
    int16_t  tSetCenti;
    int16_t  tActualCenti;
    int16_t  tPt1000Centi;
    uint16_t kpMilli, kiMilli, kdMilli;
    uint16_t iLimitMa;
    uint16_t iActualMa;
    uint16_t dutyMilli;     /* x1000 */
    uint8_t  failCount;
} PmData_t;

void Boards_Init(void);
void Boards_Process(void);

const BmData_t *Boards_GetBm(uint8_t index);
const PmData_t *Boards_GetPm(uint8_t index);

/* Reads the telemetry of one BM immediately (used by the EIS sequencer).
 * Returns 1 on success. */
uint8_t Boards_RefreshBm(uint8_t index);

/* ---- BM commands (return 1 if the I2C transfer succeeded) ---- */
uint8_t Boards_BmControl(uint8_t index, uint8_t controlBits);           /* BM_CTRL_* */
uint8_t Boards_BmSetConnectZ(uint8_t index, uint8_t on);
uint8_t Boards_BmWriteEisParams(uint8_t index, const uint8_t *params);  /* BM_EIS_PARAM_LEN bytes from EIS_CHIP */
/* Result of one frequency index of the last completed sweep. */
uint8_t Boards_BmReadResult(uint8_t index, uint8_t freqIndex, uint8_t *valid,
                            uint32_t *freqCentiHz, int32_t *reUOhm, int32_t *imUOhm);

/* ---- PM commands ---- */
uint8_t Boards_PmControl(uint8_t index, uint8_t controlBits);           /* PM_CTRL_* */
uint8_t Boards_PmSetSetpoint(uint8_t index, int16_t tSetCenti);
uint8_t Boards_PmSetCurrentLimit(uint8_t index, uint16_t limitMa);
uint8_t Boards_PmSetGains(uint8_t index, uint16_t kpMilli, uint16_t kiMilli, uint16_t kdMilli);
/* Applies the source of the board list to the PM right away (also done on
 * every poll). */
uint8_t Boards_PmApplySource(uint8_t index);

#endif /* BOARDS_H */
