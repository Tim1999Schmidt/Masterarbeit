/**
 ******************************************************************************
 * @file    i2c_comm.h
 * @brief   I2C1 slave register-map interface to the master board. Replaces
 *          the original driver's BaSyTec ASCII protocol (dropped per
 *          request) with a compact binary register map, since this is a new
 *          requirement rather than a port of existing logic.
 *
 * Protocol
 * --------
 * PM acts as an I2C slave at the 7-bit address stored in flash
 * (pm_settings.h, default 0x28; set per board with the console command
 * "addr", so several PMs can share the bus).
 *
 *   Master write:  [register address][data bytes...]  (P)
 *     - writes the data bytes starting at that register address. A write of
 *       just the address (no data bytes) only sets the read pointer.
 *       The bytes of ONE write transaction take effect together, when the
 *       transaction ends (STOP or repeated START), never half-applied.
 *       Writes to read-only registers / beyond the map are ignored.
 *   Master read:   [register address](Sr)[data bytes...] (P)
 *     - a write of the address, repeated START, then a read: returns the
 *       register map starting at that address. (A plain read without a
 *       preceding address write starts at the last address that was set.)
 *       Read at most (0x1C - address) bytes. The data of one read is a
 *       consistent snapshot taken when the read starts.
 *
 * All multi-byte fields are little-endian, signed unless noted.
 *
 *   Addr  Name        R/W  Type    Scale / meaning
 *   0x00  STATUS       RO  uint8   bit0 running, bit1 error, bit2 direction (0=heating,1=cooling),
 *                                  bit3 temperature valid (see TempSensor_IsReady: calibrated and
 *                                  plausible for the PT1000, refreshed in time for T_EXT)
 *   0x01  CONTROL      RW  uint8   write: bit0=start, bit1=stop, bit2=clear error,
 *                                  bit3=recalibrate temperature front-end (only while not running)
 *                                  (self-clearing, reads back 0)
 *   0x02  ERROR_CODE   RO  uint8   0 none, 1 startup overcurrent, 2 runtime overcurrent, 3 sanity error,
 *                                  4 PT1000 implausible, 5 T_EXT timeout, 6 open load (no Peltier),
 *                                  7 temperature recalibration failed
 *   0x03  TEMP_SOURCE  RW  uint8   temperature the PID regulates on: 1 = onboard PT1000 (default,
 *                                  normal operation), 0 = external value T_EXT written by the master
 *                                  (e.g. the tab sensor of the BM - not intended for normal operation).
 *                                  Only selects the controller's input - NOT the SEL multiplexer
 *                                  (PT1000 / calibration resistors), which the firmware drives itself.
 *   0x04  T_SET        RW  int16   deg C x100, clamped to 0..5000 (0..50 degC; reads back the value in effect).
 *                                  Each new value triggers a recalibration of the PT1000 front-end
 *                                  (~300 ms, PID output held), another one follows when it is reached
 *   0x06  T_EXT        RW  int16   deg C x100 (used while TEMP_SOURCE = 0). Must be rewritten
 *                                  periodically (also if unchanged): not written for
 *                                  EXT_TEMP_TIMEOUT_MS (temperature_sensor.c, 2 s) -> error 5
 *   0x08  T_ACTUAL     RO  int16   deg C x100 (value currently feeding the PID)
 *   0x0A  T_PT1000     RO  int16   deg C x100 (onboard PT1000, always measured, independent of TEMP_SOURCE)
 *   0x0C  CAL_LOW      RO  uint16  raw ADC counts measured on the 1.00 kOhm reference (bring-up diagnostics)
 *   0x0E  CAL_HIGH     RO  uint16  raw ADC counts measured on the 1.20 kOhm reference (bring-up diagnostics)
 *   0x10  KP           RW  uint16  x1000
 *   0x12  KI           RW  uint16  x1000
 *   0x14  KD           RW  uint16  x1000
 *   0x16  I_LIMIT      RW  uint16  mA, clamped to 500..5000; only accepted while not running
 *                                  (reads back the value in effect)
 *   0x18  I_ACTUAL     RO  uint16  mA (always >= 0, see current_sensor.h)
 *   0x1A  DUTY_CYCLE   RO  uint16  x1000 (0..1000 = 0..100.0%)
 *
 * Register map is 0x1C (28) bytes total. (Addresses unchanged from the first
 * draft; 0x0C/0x0E used to be T_CH2/T_CH3, which do not exist any more now
 * that CH2/CH3 are calibration resistors.)
 ******************************************************************************
 */
#ifndef I2C_COMM_H
#define I2C_COMM_H

#include "main.h"

#ifdef __cplusplus
extern "C" {
#endif

/* One-time setup: sets the slave address, enables the I2C1 interrupt and arms
 * address-match listening. Call once from main() before the main loop, after
 * MX_I2C1_Init(). */
void I2cComm_Init(void);

/* Refreshes the read-only telemetry registers from the live control/sensor
 * state and applies any register writes that arrived since the last call.
 * Call once per main loop iteration. Deliberately does the actual work here
 * (main-loop context) rather than inside the I2C ISR callbacks, which only
 * move bytes and set flags. */
void I2cComm_Update(void);

/* Changes the slave address at runtime (debug console "addr"). */
void I2cComm_SetAddress(uint8_t addr7);

#ifdef __cplusplus
}
#endif

#endif /* I2C_COMM_H */
