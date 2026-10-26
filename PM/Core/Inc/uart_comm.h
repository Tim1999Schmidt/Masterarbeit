/**
 ******************************************************************************
 * @file    uart_comm.h
 * @brief   Debug interface on USART1 (PA9 = TX, PA10 = RX): a plain-text
 *          command line for a terminal program on the PC, so the PM can be
 *          operated and observed without the master board.
 *
 * Offers the same functions as the I2C interface (i2c_comm.h) except T_EXT and
 * TEMP_SOURCE (the controller always uses whatever source is selected via I2C,
 * by default the onboard PT1000). Both interfaces act on the same modules, so a
 * value set over UART is also what the master reads over I2C, and vice versa.
 * The same rules apply: T_SET 0..50 degC, I_LIMIT 0.5..3.0 A and only while
 * stopped, recalibration only while stopped.
 *
 * Terminal settings: 115200 baud, 8N1, no flow control (USART1 in PM.ioc).
 * Lines end with CR and/or LF (max. 24 characters). The PM does not echo -
 * switch on "local echo" in the terminal. Not case sensitive; numbers accept
 * '.' or ',' as decimal separator.
 *
 *   s                   status: run, err (code, see i2c_comm.h), cool, valid,
 *                       addr, igain,
 *                       cal (CAL_LOW/CAL_HIGH) + all values (tset ... kd)
 *   start / stop        start / stop regulating
 *   clear               clear a latched error
 *   recal               recalibrate the temperature front-end (only while stopped)
 *   tset [degC]         set / show setpoint (0..50)
 *   ilim [A]            set / show current limit (0.5..3.0, default 3.0, only while stopped)
 *   kp | ki | kd [val]  set / show PID gain (0..65.535, same range as over I2C)
 *   log [ms]            periodic CSV line every ms (>= 100), 0 = off
 *   duty [percent]      bring-up test: fixed duty cycle without regulation
 *                       (max. 95 %, current still supervised);
 *                       positive = heating, negative = cooling (e.g.
 *                       "duty -30"), "duty 0" switches it off; only while
 *                       stopped
 *   igain [factor]      set / show the calibration factor of the current
 *                       measurement (0.8..1.2, stored in flash): factor =
 *                       true current / displayed current x old factor
 *   addr [0x08..0x77]   set / show the I2C slave address (decimal or 0x hex),
 *                       stored in flash, effective immediately (default 0x28)
 *   (anything else)     ERR + list of commands
 *
 * Replies start with "OK" or "ERR". Log lines (';'-separated, header printed
 * by the log command):
 *   LOG;ms;tset;t_act;t_pt;i;duty;out;cool;err
 *   (degC, degC, degC, A, %, A, 0 heat / 1 cool, error code)
 *
 * Kept small for the 32 KB flash (USART1 registers used directly, no HAL UART
 * interrupt driver). Can be left out entirely with PM_ENABLE_UART = 0, see
 * pm_config.h.
 ******************************************************************************
 */
#ifndef UART_COMM_H
#define UART_COMM_H

#include "main.h"

#ifdef __cplusplus
extern "C" {
#endif

/* One-time setup: enables the USART1 interrupt, starts reception and prints a
 * short banner. Call once from main() before the main loop, after
 * MX_USART1_UART_Init(). */
void UartComm_Init(void);

/* Processes received command lines and sends the periodic log line.
 * Call once per main loop iteration. */
void UartComm_Update(void);

#ifdef __cplusplus
}
#endif

#endif /* UART_COMM_H */
