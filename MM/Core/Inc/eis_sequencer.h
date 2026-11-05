/**
 ******************************************************************************
 * @file    eis_sequencer.h
 * @brief   Runs EIS measurements on the BMs: a single cell, the stack, or all
 *          cells one after another (optionally followed by the stack).
 *
 * Non-blocking state machine, advanced by EisSeq_Process() from the main
 * loop, so status requests from the GUI are still answered during a job.
 *
 * No job running: all cells are connected in parallel on the rail (CONNECT_Z
 * = 1 on every BM that is online, reports no overcurrent and whose cell
 * voltage is within STACK_MAX_VOLTAGE_DIFF_MV of the others), so that small
 * voltage differences equalise. A larger difference is reported once as
 * WARN;UDIFF;<mV> and nothing is connected. Each BM also switches its own
 * CONNECT_Z off at a cell current >= 2 A (BM error 9). Can be switched off
 * with EisSeq_SetRailAuto(0) (host command RAIL;0): then all CONNECT_Z = 0.
 *
 * Per target:
 *   cell k : CONNECT_Z = 0 on all BMs (BMs that do not answer are skipped;
 *            only BM k must confirm CONNECT_Z = 0) -> clear error on BM k ->
 *            write the parameters (EIS_CHIP = cell) -> START -> poll STATUS /
 *            PROGRESS until the sweep is done -> read all results -> next.
 *   stack  : read all BMs, all must be online; the cells selected in stackMask
 *            must be within STACK_MAX_VOLTAGE_DIFF_MV of each other (they are
 *            connected in parallel!) -> CONNECT_Z = 1 on the selected BMs,
 *            CONNECT_Z = 0 on the others (both checked) -> sweep with the stack
 *            TLE9010 of the BM that has one (NUM_EIS = 2; its own cell may be
 *            deselected, the chip is supplied from the rail) ->
 *            results (the cells stay on the rail if the rail equalisation is on,
 *            otherwise CONNECT_Z = 0 on all BMs, also after an error / abort).
 *
 * A failed target is reported (EISEND;<target>;ERR;<REASON>[;BM<k>][;BM_ERR<n>],
 * BM<k> = the BM the error refers to, BM_ERR<n> = its error code) and the job
 * continues with the next target. Reasons:
 *   OFFLINE    BM does not answer                 UDIFF     voltage difference too high (stack)
 *   NOSTACK    no BM with a stack chip            CONNECTZ  CONNECT_Z did not switch
 *   START      sweep did not start (BM_ERR_<n> follows if the BM reports one)
 *   SWEEP      sweep ended without results        STALL     no progress for EIS_STALL_TIMEOUT_MS
 *   (START and SWEEP are followed by ;BM_ERR<n> if the BM reports an error code n)
 *   READ       results could not be read          ABORTED   ABORT command
 * Output lines: see host_comm.h.
 ******************************************************************************
 */
#ifndef EIS_SEQUENCER_H
#define EIS_SEQUENCER_H

#include "main.h"
#include <stdint.h>

#define STACK_MAX_VOLTAGE_DIFF_MV   50      /* same limit as the Zellhalter firmware */

typedef enum
{
    EIS_JOB_CELL = 0,          /* one cell (cellBm) */
    EIS_JOB_STACK,             /* the stack */
    EIS_JOB_ALL_CELLS,         /* every cell in the board list */
    EIS_JOB_ALL_CELLS_STACK    /* every cell, then the stack */
} EisJobType_t;

typedef struct
{
    EisJobType_t type;
    uint8_t cellBm;            /* 0-based BM index for EIS_JOB_CELL */
    uint8_t fStart;
    uint8_t fStop;
    uint8_t amplitude;
    uint8_t waveform;
    uint8_t averages;
    uint8_t measTime;          /* 0..BM_MEAS_TIME_COUNT-1 = 25 .. 3200 ms */
    uint8_t stackMask;         /* stack: cells on the rail, bit k-1 = BM k (EIS_STACK_ALL = all) */
} EisJob_t;

#define EIS_STACK_ALL   0xFFu  /* stackMask: every BM of the board list */

typedef enum
{
    EIS_SEQ_OK = 0,
    EIS_SEQ_ERR_BUSY,          /* a job is already running */
    EIS_SEQ_ERR_PARAM,         /* parameter out of range / BM number invalid */
    EIS_SEQ_ERR_NO_STACK       /* stack requested, but no BM with a stack chip is known */
} EisSeqResult_t;

void EisSeq_Init(void);
void EisSeq_Process(void);

EisSeqResult_t EisSeq_Start(const EisJob_t *job);
void           EisSeq_Abort(void);
uint8_t        EisSeq_IsBusy(void);

/* Rail equalisation while no job runs (default on). Off: CONNECT_Z = 0 on all BMs. */
void           EisSeq_SetRailAuto(uint8_t on);
uint8_t        EisSeq_GetRailAuto(void);

#endif /* EIS_SEQUENCER_H */
