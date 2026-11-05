/**
 ******************************************************************************
 * @file    host_comm.h
 * @brief   Text protocol between the MATLAB GUI (PC) and the MM over USART2
 *          (ST-LINK virtual COM port of the Nucleo, 115200 baud, 8N1).
 *
 * Every line ends with CR, LF or CR/LF (terminal programs often send only CR);
 * backspace deletes the last character, other control characters are ignored. Fields are separated by ';'.
 * Commands are not case sensitive. Numbers are decimal, addresses may also be
 * written as 0x.. hex. Board numbers start at 1 (order of the board list).
 *
 * Every command is answered by exactly one final line:
 *   OK;<COMMAND>[;...]          success
 *   ERR;<COMMAND>;<REASON>      failure (REASON: short upper-case token)
 * Commands that return data send their data lines first, then the OK line.
 * Lines of a running EIS job (EISBEGIN, PROG, RES, ...) can come at any time
 * in between (they are never split).
 *
 * ---- connection / board list --------------------------------------------
 *   HELLO                         -> OK;HELLO;MM;<firmware version>
 *   CFG?                          -> CFG;BM;<n>;<addr1>;...    (addresses hex)
 *                                    CFG;PM;<n>;<addr1>;...
 *                                    CFG;SRC;<src PM1>;...     (0 = PT1000, k = tab sensor of BM k)
 *                                    OK;CFG?
 *   CFGBM;<addr1>;<addr2>;...     set the BM list (1..8 addresses; 0x10 / 0x20 are the
 *                                 unassigned default addresses -> ERR;CFGBM;UNASSIGNED)
 *   CFGPM;<addr1>;...             set the PM list (0..8 addresses; sources reset to PT1000)
 *   PMSRC;<pm>;<0|bm>             temperature source of a PM
 *   SAVE                          write the board list to flash
 *   SCAN                          -> SCAN;<addr>;<addr>;...  all addresses that answer
 *                                    OK;SCAN
 * ---- status --------------------------------------------------------------
 *   STAT  -> one line per board, then OK;STAT
 *     BM;<k>;<addr>;<online>;<status>;<err>;<u_mV>;<i_mA>;<t_tab_cdegC>;<numEis>;<progress>;<connectZ>
 *     PM;<k>;<addr>;<online>;<status>;<err>;<tset_cdegC>;<tact_cdegC>;<tpt_cdegC>;<i_mA>;<duty_permille>;<ilim_mA>;<src>
 *     MM;<eis busy>;<i2c error count>;<BM on 0x10>;<PM on 0x20>;<rail>
 *       (BM/PM on 0x10/0x20: 1 = a board without an assigned address answers
 *        there; rail: 1 = rail equalisation on, see RAIL)
 * ---- warnings (sent by the MM on its own) ------------------------------------
 *   WARN;UDIFF;<mV>
 *       rail equalisation: the cell voltages differ by more than 50 mV, the
 *       cells are not connected in parallel (sent once until the difference is ok)
 *   WARN;NOADDR;BM;0x10 / WARN;NOADDR;PM;0x20
 *       a BM / PM answers on its unassigned default address: give it its own
 *       address over its debug console ("addr") before it can be used.
 *       Sent once when such a board appears.
 *     (status / err: register values of the board, see bm_regs.h / pm_regs.h;
 *      progress 255 = idle; cdegC = degC x100)
 * ---- PM (temperature control) --------------------------------------------
 *   PMSET;<pm>;<tset_cdegC>       setpoint 0..5000 (0..50 degC)
 *   PMSTART;<pm>   PMSTOP;<pm>   PMCLR;<pm>   PMRECAL;<pm>
 *   PMILIM;<pm>;<mA>              current limit 500..3000 (only while stopped)
 *   PMGAIN;<pm>;<kp>;<ki>;<kd>    gains x1000
 *   (<pm> = 0 means all PMs)
 * ---- BM -------------------------------------------------------------------
 *   BMCLR;<bm>   BMRECAL;<bm>   BMIZERO;<bm>  (clear error / recalibrate tab
 *                                 temperature / current zero, RAM only)
 *   (<bm> = 0 means all BMs; not while an EIS job runs)
 * ---- EIS --------------------------------------------------------------------
 *   EIS;<target>;<fstart>;<fstop>;<amp>;<wave>;<avg>[;<time>[;<stack>]]
 *       target: C<k> = cell of BM k, S = stack, ALL = all cells one after
 *       another, ALLS = all cells and then the stack
 *       fstart/fstop 0..51, amp 0..5, wave 0/1, avg 1..9, time 0..7 = measuring
 *       time 25, 50, 100 .. 3200 ms (optional, default 1 = 50 ms) (as on the BM),
 *       stack = cells on the rail for the stack measurement (S / ALLS) as bit mask,
 *       bit 0 = BM 1 ... (decimal or 0x hex, optional, default all; e.g. 0x5 = BM 1 + 3);
 *       the other BMs get CONNECT_Z = 0 during the stack sweep
 *   ABORT
 *   RAIL[;0|1]                    rail equalisation while no EIS job runs (default 1):
 *                                 all cells in parallel (CONNECT_Z = 1) if their voltages
 *                                 differ by <= 50 mV; 0 = all CONNECT_Z = 0. -> OK;RAIL;<state>
 *   Lines of a running job (see eis_sequencer.h):
 *     EISBEGIN;<target>;<fstart>;<fstop>;<amp>;<wave>;<avg>;<time>;<stack mask>
 *     EISCELL;<target>;<bm>;<u_mV>;<t_tab_cdegC>      cell(s) involved
 *     PROG;<target>;<frequency index>
 *     RES;<target>;<index>;<f_cHz>;<re_uOhm>;<im_uOhm>
 *     EISEND;<target>;OK  |  EISEND;<target>;ERR;<REASON>[;BM<k>][;BM_ERR<n>]
 *     EISDONE;<targets ok>;<targets total>
 ******************************************************************************
 */
#ifndef HOST_COMM_H
#define HOST_COMM_H

#include "main.h"
#include <stdint.h>

#define HOST_BAUD_RATE   115200u

/* Sets the baud rate, enables the USART2 interrupt and prints a banner.
 * Call once after MX_USART2_UART_Init(). */
void HostComm_Init(void);

/* Executes received command lines. Call once per main loop iteration. */
void HostComm_Process(void);

/* Sends one line (printf format, the line end is added). Lines that do not
 * fit into the transmit buffer completely are dropped as a whole, never
 * truncated. Returns 1 if the line was queued. */
uint8_t HostComm_SendLine(const char *format, ...) __attribute__((format(printf, 1, 2)));

/* Free space in the transmit buffer in bytes. */
uint32_t HostComm_TxFree(void);

#endif /* HOST_COMM_H */
