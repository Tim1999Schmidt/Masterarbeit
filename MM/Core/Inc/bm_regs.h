/**
 ******************************************************************************
 * @file    bm_regs.h
 * @brief   I2C register map of the BM (battery module) as seen from the MM.
 *
 * Mirror of BM/Core/Inc/i2c_comm.h - if the BM register map changes, change
 * it here as well. All multi-byte fields little-endian.
 ******************************************************************************
 */
#ifndef BM_REGS_H
#define BM_REGS_H

/* ---- register addresses ---- */
#define BM_REG_STATUS        0x00u   /* RO uint8  see BM_ST_* */
#define BM_REG_CONTROL       0x01u   /* W  uint8  see BM_CTRL_* */
#define BM_REG_ERROR_CODE    0x02u   /* RO uint8  see BM_ERR_* */
#define BM_REG_CONNECT_Z     0x03u   /* RW uint8  0 single cell, 1 cell on the parallel rail */
#define BM_REG_EIS_CHIP      0x04u   /* RW uint8  0 cell TLE9010, 1 stack TLE9010 */
#define BM_REG_F_START       0x05u   /* RW uint8  frequency index 0..51 */
#define BM_REG_F_STOP        0x06u   /* RW uint8  frequency index F_START..51 */
#define BM_REG_AMPLITUDE     0x07u   /* RW uint8  0..5 = 50..500 mA */
#define BM_REG_WAVEFORM      0x08u   /* RW uint8  0 sine, 1 rectangle */
#define BM_REG_AVERAGES      0x09u   /* RW uint8  1..9 */
#define BM_REG_MEAS_TIME     0x0Au   /* RW uint8  0..7 = 25, 50, 100 .. 3200 ms */
#define BM_REG_PROGRESS      0x0Bu   /* RO uint8  frequency index being measured, 0xFF idle */
#define BM_REG_NUM_EIS       0x0Cu   /* RO uint8  1 or 2 TLE9010 on this board */
#define BM_REG_U_CELL        0x0Du   /* RO uint16 mV */
#define BM_REG_I_CELL        0x0Fu   /* RO int16  mA */
#define BM_REG_T_TAB         0x11u   /* RO int16  degC x100 */
#define BM_REG_CAL_LOW       0x13u   /* RO uint16 raw counts */
#define BM_REG_CAL_HIGH      0x15u   /* RO uint16 raw counts */
#define BM_REG_RES_INDEX     0x17u   /* RW uint8  frequency index of the result window */
#define BM_REG_RES_VALID     0x18u   /* RO uint8  1 = RES_INDEX belongs to the last completed sweep */
#define BM_REG_RES_FREQ      0x19u   /* RO uint32 0.01 Hz */
#define BM_REG_RES_RE        0x1Du   /* RO int32  uOhm */
#define BM_REG_RES_IM        0x21u   /* RO int32  uOhm */
#define BM_REG_MAP_SIZE      0x25u

/* telemetry block read in one go: STATUS .. CAL_HIGH */
#define BM_TELEMETRY_FIRST   BM_REG_STATUS
#define BM_TELEMETRY_LEN     (BM_REG_CAL_HIGH + 2u - BM_REG_STATUS)
/* EIS parameter block written in one go: EIS_CHIP .. MEAS_TIME */
#define BM_EIS_PARAM_FIRST   BM_REG_EIS_CHIP
#define BM_EIS_PARAM_LEN     (BM_REG_MEAS_TIME + 1u - BM_REG_EIS_CHIP)
/* result window read in one go: RES_VALID .. RES_IM */
#define BM_RESULT_FIRST      BM_REG_RES_VALID
#define BM_RESULT_LEN        (BM_REG_RES_IM + 4u - BM_REG_RES_VALID)

/* ---- STATUS bits ---- */
#define BM_ST_EIS_BUSY       0x01u
#define BM_ST_RESULTS        0x02u
#define BM_ST_ERROR          0x04u
#define BM_ST_TEMP_VALID     0x08u
#define BM_ST_CONNECT_Z      0x10u
#define BM_ST_ERRQ           0x20u
#define BM_ST_STACK_CHIP     0x40u
#define BM_ST_I_SATURATED    0x80u

/* ---- CONTROL bits (write-triggered) ---- */
#define BM_CTRL_START        0x01u
#define BM_CTRL_ABORT        0x02u
#define BM_CTRL_CLEAR_ERROR  0x04u
#define BM_CTRL_RECAL_TEMP   0x08u
#define BM_CTRL_ZERO_CURRENT 0x10u

/* ---- ERROR_CODE values ---- */
#define BM_ERR_NONE          0u
#define BM_ERR_CONFIG        1u
#define BM_ERR_BUSY          2u
#define BM_ERR_EIS_COMM      3u
#define BM_ERR_CONNECT_STATE 4u
#define BM_ERR_TEMP_SENSOR   5u
#define BM_ERR_ERRQ          6u
#define BM_ERR_FLASH         7u
#define BM_ERR_EIS_ADC_SAT   8u   /* TLE9010 ADC saturated, sweep stopped */

/* ---- value ranges ---- */
#define BM_CONNECT_Z_OFF     0u
#define BM_CONNECT_Z_ON      1u
#define BM_EIS_CHIP_CELL     0u
#define BM_EIS_CHIP_STACK    1u
#define BM_NUM_FREQ          52u      /* frequency index 0..51 */
#define BM_FREQ_INDEX_MAX    (BM_NUM_FREQ - 1u)
#define BM_AMPLITUDE_COUNT   6u       /* 0..5 = 50, 100, 200, 300, 400, 500 mA */
#define BM_WAVE_SINE         0u
#define BM_WAVE_RECTANGLE    1u
#define BM_AVERAGES_MIN      1u
#define BM_AVERAGES_MAX      9u
#define BM_MEAS_TIME_COUNT   8u       /* 0..7 = 25, 50, 100, 200, 400, 800, 1600, 3200 ms */
#define BM_MEAS_TIME_DEFAULT 1u       /* 50 ms */
#define BM_PROGRESS_IDLE     0xFFu
#define BM_NUM_EIS_WITH_STACK 2u

#endif /* BM_REGS_H */
