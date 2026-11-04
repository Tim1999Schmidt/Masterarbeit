/**
 ******************************************************************************
 * @file    eis_sequencer.c
 * @brief   See eis_sequencer.h.
 ******************************************************************************
 */
#include "eis_sequencer.h"
#include "boards.h"
#include "bm_regs.h"
#include "host_comm.h"
#include "mm_config.h"
#include <stdio.h>

#define CONNECT_SETTLE_MS        100u     /* CONNECT_Z switched -> check its state */
#define START_CHECK_DELAY_MS     100u     /* START sent -> BM must report "busy" */
#define EIS_POLL_PERIOD_MS       250u     /* STATUS / PROGRESS polling during a sweep */
#define EIS_STALL_TIMEOUT_MS   60000u     /* longest step: 9 averages x (4.5 s + 0.2 s) = 42 s
                                           * (3200 ms measuring time: BM waits 4.0 s < 4.5 s) */
#define POLL_FAIL_LIMIT            8u     /* failed polls in a row -> BM counts as lost */
#define READ_RETRIES               3u     /* per result index */
#define TARGET_NAME_LEN            4u     /* "C8" / "S" + terminator */
#define STACK_TARGET              0xFFu   /* target list entry: the stack */
#define NO_BM                     0xFFu
#define RES_LINE_TX_RESERVE       64u     /* free TX bytes needed before the next RES line */
#define RAIL_CHECK_PERIOD_MS    1000u     /* no job: how often the rail connection is checked */
#define RAIL_MIN_CELLS             2u     /* fewer cells: nothing to equalise */
#define END_LINE_LEN              64u     /* "EISEND;C8;ERR;CONNECTZ;BM8;BM_ERR9" */

typedef char target_name_has_one_digit[(MM_MAX_BM <= 9u) ? 1 : -1];

typedef enum
{
    ST_IDLE,
    ST_NEXT_TARGET,
    ST_CONNECT_SETTLE,
    ST_START,
    ST_START_CHECK,
    ST_RUNNING,
    ST_READOUT,
    ST_FINISH
} SeqState_t;

static SeqState_t state = ST_IDLE;
static EisJob_t   job;
static uint8_t    targets[MM_MAX_BM + 1u];   /* BM index of a cell, or STACK_TARGET */
static uint8_t    numTargets, targetPos, targetsOk;
static uint8_t    measBm;                    /* BM doing the current sweep */
static uint8_t    isStack;
static char       name[TARGET_NAME_LEN];
static uint32_t   tick, lastProgressTick;
static uint8_t    lastProgress, pollFails, readIndex, readRetries;
static uint8_t    abortRequest;
static uint8_t    railAuto = 1u;             /* no job: cells in parallel on the rail */
static uint8_t    railUdiffReported;
static uint32_t   railTick;

/* ---- helpers --------------------------------------------------------------- */
static uint8_t NumBm(void) { return MmConfig_Get()->numBm; }

static uint8_t FindStackBm(void)
{
    uint8_t i;
    for (i = 0u; i < NumBm(); i++)
    {
        const BmData_t *b = Boards_GetBm(i);
        if (b->online && b->numEis >= BM_NUM_EIS_WITH_STACK)
            return i;
    }
    return NO_BM;
}

static void SetName(uint8_t target)
{
    if (target == STACK_TARGET)
    {
        name[0] = 'S';
        name[1] = '\0';
    }
    else
    {
        /* MM_MAX_BM <= 9: one digit */
        name[0] = 'C';
        name[1] = (char)('1' + target);
        name[2] = '\0';
    }
}

/* CONNECT_Z of all BMs on/off; returns NO_BM if every write was acknowledged,
 * otherwise the index of the first BM that did not answer */
static uint8_t ConnectAll(uint8_t on)
{
    uint8_t i, failed = NO_BM;
    for (i = 0u; i < NumBm(); i++)
        if (!Boards_BmSetConnectZ(i, on) && failed == NO_BM)
            failed = i;
    return failed;
}

/* reads BM i and checks that CONNECT_Z is in the wanted state */
static uint8_t CheckConnect(uint8_t i, uint8_t on)
{
    if (!Boards_RefreshBm(i))
        return 0u;
    return (((Boards_GetBm(i)->status & BM_ST_CONNECT_Z) != 0u) == (on != 0u)) ? 1u : 0u;
}

/* checks all BMs; returns NO_BM if CONNECT_Z is in the wanted state everywhere,
 * otherwise the index of the first BM that is offline or in the wrong state */
static uint8_t CheckConnectAll(uint8_t on)
{
    uint8_t i;
    for (i = 0u; i < NumBm(); i++)
        if (!CheckConnect(i, on))
            return i;
    return NO_BM;
}

/* reason for a failed CONNECT_Z check of BM i */
static const char *ConnectFailReason(uint8_t i)
{
    return Boards_GetBm(i)->online ? "CONNECTZ" : "OFFLINE";
}

/* BM takes part in the rail equalisation: answers, no overcurrent, no sweep */
static uint8_t RailCandidate(const BmData_t *b)
{
    return (b->online && b->errorCode != BM_ERR_OVERCURRENT && (b->status & BM_ST_EIS_BUSY) == 0u) ? 1u : 0u;
}

/* No EIS job: all cells in parallel on the rail, so that small voltage
 * differences equalise. Only BMs that are online and report no overcurrent
 * take part, and only if their cell voltages are within
 * STACK_MAX_VOLTAGE_DIFF_MV of each other - connecting cells with a larger
 * difference would drive a high equalising current (each BM also switches
 * its CONNECT_Z off by itself at >= 2 A, see BM bm_app.c). */
static void RailIdle(void)
{
    uint16_t uMin = UINT16_MAX, uMax = 0u;
    uint8_t i, n = 0u;

    if (!railAuto || (HAL_GetTick() - railTick) < RAIL_CHECK_PERIOD_MS)
        return;
    railTick = HAL_GetTick();

    for (i = 0u; i < NumBm(); i++)
    {
        const BmData_t *b = Boards_GetBm(i);
        if (!RailCandidate(b))
            continue;
        if (b->uCellMv < uMin) uMin = b->uCellMv;
        if (b->uCellMv > uMax) uMax = b->uCellMv;
        n++;
    }
    if (n < RAIL_MIN_CELLS)
        return;
    if ((int32_t)(uMax - uMin) > STACK_MAX_VOLTAGE_DIFF_MV)
    {
        if (!railUdiffReported)
            (void)HostComm_SendLine("WARN;UDIFF;%u", (unsigned)(uMax - uMin));
        railUdiffReported = 1u;
        return;                                    /* do not connect: equalising current too high */
    }
    railUdiffReported = 0u;
    for (i = 0u; i < NumBm(); i++)
    {
        const BmData_t *b = Boards_GetBm(i);
        if (RailCandidate(b) && (b->status & BM_ST_CONNECT_Z) == 0u)
            (void)Boards_BmSetConnectZ(i, BM_CONNECT_Z_ON);
    }
}

static void ReportCell(uint8_t bmIndex)
{
    const BmData_t *b = Boards_GetBm(bmIndex);
    (void)HostComm_SendLine("EISCELL;%s;%u;%u;%d", name, (unsigned)(bmIndex + 1u),
                            (unsigned)b->uCellMv, (int)b->tTabCenti);
}

/* errorReason 0 = success; bm = BM index the error refers to (NO_BM: none);
 * errorDetail = error code reported by that BM (0: none) */
static void EndTarget(const char *errorReason, uint8_t bm, int errorDetail)
{
    if (isStack && !railAuto)
        (void)ConnectAll(BM_CONNECT_Z_OFF);           /* rail equalisation off: do not leave the cells in parallel */

    if (errorReason == 0)
    {
        targetsOk++;
        (void)HostComm_SendLine("EISEND;%s;OK", name);
    }
    else
    {
        char line[END_LINE_LEN];
        int n = snprintf(line, sizeof(line), "EISEND;%s;ERR;%s", name, errorReason);
        if (bm != NO_BM && n > 0 && n < (int)sizeof(line))
            n += snprintf(&line[n], sizeof(line) - (uint32_t)n, ";BM%u", (unsigned)(bm + 1u));
        if (errorDetail != 0 && n > 0 && n < (int)sizeof(line))
            (void)snprintf(&line[n], sizeof(line) - (uint32_t)n, ";BM_ERR%d", errorDetail);
        (void)HostComm_SendLine("%s", line);
    }

    targetPos++;
    state = ST_NEXT_TARGET;
}

static void FailTarget(const char *reason)
{
    if (measBm != NO_BM)
        (void)Boards_BmControl(measBm, BM_CTRL_ABORT);
    EndTarget(reason, measBm, 0);
}

/* sets up the next target; returns 0 when the list is done */
static uint8_t BeginTarget(void)
{
    uint8_t i;

    if (targetPos >= numTargets)
        return 0u;

    isStack = (targets[targetPos] == STACK_TARGET) ? 1u : 0u;
    measBm  = NO_BM;
    SetName(targets[targetPos]);
    (void)HostComm_SendLine("EISBEGIN;%s;%u;%u;%u;%u;%u;%u", name, job.fStart, job.fStop,
                            job.amplitude, job.waveform, job.averages, job.measTime);

    if (!isStack)
    {
        /* a cell is measured alone: CONNECT_Z off on all BMs (BMs that do not
         * answer are skipped); only the measured BM must confirm it (checked
         * in ST_CONNECT_SETTLE) */
        measBm = targets[targetPos];
        (void)ConnectAll(BM_CONNECT_Z_OFF);
        ReportCell(measBm);
        tick  = HAL_GetTick();
        state = ST_CONNECT_SETTLE;
        return 1u;
    }

    /* stack: all cells online and at (almost) the same voltage */
    {
        uint16_t uMin = UINT16_MAX, uMax = 0u;
        for (i = 0u; i < NumBm(); i++)
        {
            const BmData_t *b;
            if (!Boards_RefreshBm(i))
            {
                EndTarget("OFFLINE", i, 0);
                return 1u;
            }
            b = Boards_GetBm(i);
            if (b->uCellMv < uMin) uMin = b->uCellMv;
            if (b->uCellMv > uMax) uMax = b->uCellMv;
            ReportCell(i);
        }
        if ((int32_t)(uMax - uMin) > STACK_MAX_VOLTAGE_DIFF_MV)
        {
            EndTarget("UDIFF", NO_BM, 0);
            return 1u;
        }
    }
    measBm = FindStackBm();
    if (measBm == NO_BM)
    {
        EndTarget("NOSTACK", NO_BM, 0);
        return 1u;
    }
    i = ConnectAll(BM_CONNECT_Z_ON);
    if (i != NO_BM)
    {
        EndTarget("OFFLINE", i, 0);
        return 1u;
    }
    tick  = HAL_GetTick();
    state = ST_CONNECT_SETTLE;
    return 1u;
}

/* ---- public ----------------------------------------------------------------- */
void EisSeq_Init(void)
{
    state = ST_IDLE;
}

uint8_t EisSeq_IsBusy(void)
{
    return (state != ST_IDLE) ? 1u : 0u;
}

EisSeqResult_t EisSeq_Start(const EisJob_t *j)
{
    uint8_t i;

    if (state != ST_IDLE)
        return EIS_SEQ_ERR_BUSY;
    if (j->fStart > BM_FREQ_INDEX_MAX || j->fStop > BM_FREQ_INDEX_MAX || j->fStop < j->fStart ||
        j->amplitude >= BM_AMPLITUDE_COUNT || j->waveform > BM_WAVE_RECTANGLE ||
        j->averages < BM_AVERAGES_MIN || j->averages > BM_AVERAGES_MAX ||
        j->measTime >= BM_MEAS_TIME_COUNT ||
        (j->type == EIS_JOB_CELL && j->cellBm >= NumBm()))
        return EIS_SEQ_ERR_PARAM;
    if ((j->type == EIS_JOB_STACK || j->type == EIS_JOB_ALL_CELLS_STACK) && FindStackBm() == NO_BM)
        return EIS_SEQ_ERR_NO_STACK;

    job = *j;
    numTargets = 0u;
    if (job.type == EIS_JOB_CELL)
        targets[numTargets++] = job.cellBm;
    if (job.type == EIS_JOB_ALL_CELLS || job.type == EIS_JOB_ALL_CELLS_STACK)
        for (i = 0u; i < NumBm(); i++)
            targets[numTargets++] = i;
    if (job.type == EIS_JOB_STACK || job.type == EIS_JOB_ALL_CELLS_STACK)
        targets[numTargets++] = STACK_TARGET;

    targetPos = 0u;
    targetsOk = 0u;
    abortRequest = 0u;
    state = ST_NEXT_TARGET;
    return EIS_SEQ_OK;
}

void EisSeq_Abort(void)
{
    if (state != ST_IDLE)
        abortRequest = 1u;
}

void EisSeq_SetRailAuto(uint8_t on)
{
    railAuto = on ? 1u : 0u;
    railTick = HAL_GetTick() - RAIL_CHECK_PERIOD_MS;   /* check at once */
    if (!railAuto && state == ST_IDLE)
        (void)ConnectAll(BM_CONNECT_Z_OFF);
}

uint8_t EisSeq_GetRailAuto(void) { return railAuto; }

void EisSeq_Process(void)
{
    if (state == ST_IDLE)
    {
        RailIdle();
        return;
    }

    if (abortRequest)
    {
        abortRequest = 0u;
        if (state != ST_NEXT_TARGET)
            FailTarget("ABORTED");              /* a target is in progress */
        targetPos = numTargets;                 /* skip the remaining targets */
    }

    switch (state)
    {
    case ST_NEXT_TARGET:
        if (!BeginTarget())
        {
            if (!railAuto)
                (void)ConnectAll(BM_CONNECT_Z_OFF);
            (void)HostComm_SendLine("EISDONE;%u;%u", targetsOk, numTargets);
            railTick = HAL_GetTick() - RAIL_CHECK_PERIOD_MS;   /* reconnect the rail at once */
            state = ST_IDLE;
        }
        break;

    case ST_CONNECT_SETTLE:
    {
        uint8_t failed;
        if ((HAL_GetTick() - tick) < CONNECT_SETTLE_MS)
            break;
        if (isStack)
            failed = CheckConnectAll(BM_CONNECT_Z_ON);     /* stack: every cell on the rail */
        else
            failed = CheckConnect(measBm, BM_CONNECT_Z_OFF) ? NO_BM : measBm;
        if (failed != NO_BM)
        {
            EndTarget(ConnectFailReason(failed), failed, 0);
            break;
        }
        state = ST_START;
        break;
    }

    case ST_START:
    {
        const uint8_t params[BM_EIS_PARAM_LEN] =
        {
            isStack ? BM_EIS_CHIP_STACK : BM_EIS_CHIP_CELL,
            job.fStart, job.fStop, job.amplitude, job.waveform, job.averages, job.measTime
        };
        if (!Boards_BmControl(measBm, BM_CTRL_CLEAR_ERROR) ||
            !Boards_BmWriteEisParams(measBm, params) ||
            !Boards_BmControl(measBm, BM_CTRL_START))
        {
            EndTarget("OFFLINE", measBm, 0);
            break;
        }
        tick  = HAL_GetTick();
        state = ST_START_CHECK;
        break;
    }

    case ST_START_CHECK:
        if ((HAL_GetTick() - tick) < START_CHECK_DELAY_MS)
            break;
        if (!Boards_RefreshBm(measBm))
        {
            FailTarget("OFFLINE");
            break;
        }
        if ((Boards_GetBm(measBm)->status & BM_ST_EIS_BUSY) == 0u)
        {
            EndTarget("START", measBm, Boards_GetBm(measBm)->errorCode);
            break;
        }
        lastProgress     = BM_PROGRESS_IDLE;
        lastProgressTick = HAL_GetTick();
        pollFails        = 0u;
        tick             = HAL_GetTick();
        state            = ST_RUNNING;
        break;

    case ST_RUNNING:
    {
        const BmData_t *b = Boards_GetBm(measBm);
        if ((HAL_GetTick() - tick) < EIS_POLL_PERIOD_MS)
            break;
        tick = HAL_GetTick();

        if (!Boards_RefreshBm(measBm))
        {
            if (++pollFails >= POLL_FAIL_LIMIT)
                FailTarget("OFFLINE");
            break;
        }
        pollFails = 0u;

        if ((b->status & BM_ST_EIS_BUSY) != 0u)
        {
            if (b->progress != lastProgress)
            {
                lastProgress     = b->progress;
                lastProgressTick = HAL_GetTick();
                (void)HostComm_SendLine("PROG;%s;%u", name, b->progress);
            }
            else if ((HAL_GetTick() - lastProgressTick) > EIS_STALL_TIMEOUT_MS)
                FailTarget("STALL");
            break;
        }
        if ((b->status & BM_ST_RESULTS) == 0u)
        {
            EndTarget("SWEEP", measBm, b->errorCode);
            break;
        }
        readIndex   = job.fStart;
        readRetries = 0u;
        state       = ST_READOUT;
        break;
    }

    case ST_READOUT:
    {
        uint8_t valid = 0u;
        uint32_t f;
        int32_t re, im;

        if (HostComm_TxFree() < RES_LINE_TX_RESERVE)
            break;                              /* let the UART catch up first */
        if (Boards_BmReadResult(measBm, readIndex, &valid, &f, &re, &im) && valid)
        {
            (void)HostComm_SendLine("RES;%s;%u;%lu;%ld;%ld", name, readIndex,
                                    (unsigned long)f, (long)re, (long)im);
            readRetries = 0u;
            if (readIndex >= job.fStop)
                state = ST_FINISH;
            else
                readIndex++;
        }
        else if (++readRetries >= READ_RETRIES)
            EndTarget("READ", measBm, 0);
        break;
    }

    case ST_FINISH:
        EndTarget(0, NO_BM, 0);
        break;

    default:
        state = ST_IDLE;
        break;
    }
}
