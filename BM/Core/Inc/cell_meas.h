/**
 ******************************************************************************
 * @file    cell_meas.h
 * @brief   Cell voltage and cell current from the onboard ADC, plus VDDA.
 *
 * Voltage (U_Z+, PA6): divider 39k / 68k
 *      U_cell = U_ADC * (39k + 68k) / 68k * (1 + uCorrPpm / 1e6)   (0 .. ~5.2 V)
 * uCorrPpm (bm_config) corrects the divider tolerance; it is determined with
 * "ucal <mV>" on the debug console against a reference measurement.
 *
 * Current (HALL_OUT -> INA332 -> PA2): Hall sensor CZ-3A01, 120 mV/A, VDD/2 at
 * 0 A, followed by the INA332 with gain 5 (0R between OUT and RG) and
 * VIN-/REF on REF1 (1.65 V = VDD/2, the Hall output at 0 A):
 *      U_ADC = U_REF1 + 5 * (U_hall - U_REF1)  ->  600 mV/A at the ADC
 *      I     = (U_ADC - U_ADC@0A) / 600 mV/A
 * U_ADC@0A nominally = 1.65 V. The Hall offset and the REF1 tolerance are
 * multiplied by 5, so the real zero is measured once with no current flowing
 * ("izero" on the debug console: stored in flash; CONTROL bit 4 over I2C:
 * RAM only, so the MM may repeat it as often as it likes without wearing the
 * flash). Measuring range ~ +-2.75 A.
 *
 * All ADC voltages are scaled with the real VDDA, measured once a second via
 * the internal reference (VREFINT, factory calibrated), not with a nominal 3.3 V.
 *
 * Cooperative: call CellMeas_Process() every main loop iteration; it measures
 * every 100 ms (~0.5 ms ADC burst).
 ******************************************************************************
 */
#ifndef CELL_MEAS_H
#define CELL_MEAS_H

#include "main.h"
#include <stdint.h>

void CellMeas_Init(void);
void CellMeas_Process(void);

int32_t  CellMeas_GetVoltageMv(void);   /* cell voltage, mV */
int32_t  CellMeas_GetCurrentMa(void);   /* cell current, mA (sign as seen by the Hall sensor) */
uint32_t CellMeas_GetVddaMv(void);      /* measured VDDA, mV */
uint8_t  CellMeas_IsCurrentSaturated(void); /* current path at an ADC rail: outside the measuring range */

/* Takes the present current reading as 0 A (no current may flow!), stores it
 * in the RAM copy of the config (caller saves it with BmConfig_Save()) - only
 * if it lies within BM_I_ZERO_MIN_MV..MAX_MV (1.0..2.3 V), otherwise the old
 * value stays. Returns the measured zero voltage in mV. */
int32_t CellMeas_ZeroCurrent(void);

/* Voltage calibration: compares the present cell voltage (averaged over 1 s,
 * blocking) with the reference refMv (e.g. multimeter at the cell) and sets
 * uCorrPpm in the RAM copy of the config (caller saves it). Returns 0 and keeps
 * the old value if refMv is outside BM_U_CAL_MIN_MV..MAX_MV or the correction
 * would exceed +-BM_U_CORR_MAX_PPM. */
uint8_t CellMeas_CalibrateVoltage(int32_t refMv);

#endif /* CELL_MEAS_H */
