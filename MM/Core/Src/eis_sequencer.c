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

#define CONNECT_SETTLE_MS        100u     /* CONNECT_Z switched -> check its state */
#define START_CHECK_DELAY_MS     100u     /* START sent -> BM must report "busy" */
#define EIS_POLL_PERIOD_MS       250u     /* STATUS / PROGRESS polling during a sweep */
#define EIS_STALL_TIMEOUT_MS   60000u     /* longest step: 9 averages x (4.5 s + 0.2 s) = 42 s */
#define POLL_FAIL_LIMIT            8u     /* failed polls in a row -> BM counts as lost */
#define READ_RETRIES               3u     /* per result index */
#define TARGET_NAME_LEN            4u     /* "C8" / "S" + terminator */
#define STACK_TARGET              0xFFu   /* target list entry: the stack */
#define NO_BM                     0xFFu
#define RES_LINE_TX_RESERVE       64u     /* free TX bytes needed before the next RES line */

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

/* CONNECT_Z of all BMs on/off; returns 1 if every write was acknowledged */
static uint8_t ConnectAll(uint8_t on)
{
    uint8_t i, ok = 1u;
    for (i = 0u; i < NumBm(); i++)
        if (!Boards_BmSetConnectZ(i, on))
            ok = 0u;
    return ok;
}

/* reads all BMs and checks that CONNECT_Z is in the wanted state everywhere */
static uint8_t CheckConnectAll(uint8_t on)
{
    uint8_t i;
    for (i = 0u; i < NumBm(); i++)
    {
        if (!Boards_RefreshBm(i))
            return 0u;
        if (((Boards_GetBm(i)->status & BM_ST_CONNECT_Z) != 0u) != (on != 0u))
            return 0u;
    }
    return 1u;
}

static void ReportCell(uint8_t bmIndex)
{
    const BmData_t *b = Boards_GetBm(bmIndex);
    (void)HostComm_SendLine("EISCELL;%s;%u;%u;%d", name, (unsigned)(bmIndex + 1u),
                            (unsigned)b->uCellMv, (int)b->tTabCenti);
}

static void EndTarget(const char *errorReason, int errorDetail)
{
    if (isStack)
        (void)ConnectAll(BM_CONNECT_Z_OFF);           /* never leave the cells in parallel */

    if (errorReason == 0)
    {
        targetsOk++;
        (void)HostComm_SendLine("EISEND;%s;OK", name);
    }
    else if (errorDetail != 0)
        (void)HostComm_SendLine("EISEND;%s;ERR;%s;BM_ERR%d", name, errorReason, errorDetail);
    else
        (void)HostComm_SendLine("EISEND;%s;ERR;%s", name, errorReason);

    targetPos++;
    state = ST_NEXT_TARGET;
}

static void FailTarget(const char *reason)
{
    if (measBm != NO_BM)
        (void)Boards_BmControl(measBm, BM_CTRL_ABORT);
    EndTarget(reason, 0);
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
    (void)HostComm_SendLine("EISBEGIN;%s;%u;%u;%u;%u;%u", name, job.fStart, job.fStop,
                            job.amplitude, job.waveform, job.averages);

    if (!isStack)
    {
        const uint8_t k = targets[targetPos];
        /* a cell is measured alone: no BM may connect its cell to the rail */
        (void)ConnectAll(BM_CONNECT_Z_OFF);
        if (!CheckConnectAll(BM_CONNECT_Z_OFF))
        {
            EndTarget(Boards_GetBm(k)->online ? "CONNECTZ" : "OFFLINE", 0);
            return 1u;
        }
        ReportCell(k);
        measBm = k;
        state  = ST_START;
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
                EndTarget("OFFLINE", 0);
                return 1u;
            }
            b = Boards_GetBm(i);
            if (b->uCellMv < uMin) uMin = b->uCellMv;
            if (b->uCellMv > uMax) uMax = b->uCellMv;
            ReportCell(i);
        }
        if ((int32_t)(uMax - uMin) > STACK_MAX_VOLTAGE_DIFF_MV)
        {
            EndTarget("UDIFF", 0);
            return 1u;
        }
    }
    measBm = FindStackBm();
    if (measBm == NO_BM)
    {
        EndTarget("NOSTACK", 0);
        return 1u;
    }
    if (!ConnectAll(BM_CONNECT_Z_ON))
    {
        EndTarget("CONNECTZ", 0);
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

void EisSeq_Process(void)
{
    if (state == ST_IDLE)
        return;

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
            (void)ConnectAll(BM_CONNECT_Z_OFF);
            (void)HostComm_SendLine("EISDONE;%u;%u", targetsOk, numTargets);
            state = ST_IDLE;
        }
        break;

    case ST_CONNECT_SETTLE:
        if ((HAL_GetTick() - tick) < CONNECT_SETTLE_MS)
            break;
        if (!CheckConnectAll(BM_CONNECT_Z_ON))
        {
            EndTarget("CONNECTZ", 0);
            break;
        }
        state = ST_START;
        break;

    case ST_START:
    {
        const uint8_t params[BM_EIS_PARAM_LEN] =
        {
            isStack ? BM_EIS_CHIP_STACK : BM_EIS_CHIP_CELL,
            job.fStart, job.fStop, job.amplitude, job.waveform, job.averages
        };
        if (!Boards_BmControl(measBm, BM_CTRL_CLEAR_ERROR) ||
            !Boards_BmWriteEisParams(measBm, params) ||
            !Boards_BmControl(measBm, BM_CTRL_START))
        {
            EndTarget("OFFLINE", 0);
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
            EndTarget("START", Boards_GetBm(measBm)->errorCode);
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
            EndTarget("SWEEP", b->errorCode);
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
            EndTarget("READ", 0);
        break;
    }

    case ST_FINISH:
        EndTarget(0, 0);
        break;

    default:
        state = ST_IDLE;
        break;
    }
}
