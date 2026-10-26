/**
 ******************************************************************************
 * @file    pm_regs.h
 * @brief   I2C register map of the PM (Peltier module) as seen from the MM.
 *
 * Mirror of PM/Core/Inc/i2c_comm.h - if the PM register map changes, change
 * it here as well. All multi-byte fields little-endian.
 ******************************************************************************
 */
#ifndef PM_REGS_H
#define PM_REGS_H

/* ---- register addresses ---- */
#define PM_REG_STATUS        0x00u   /* RO uint8  see PM_ST_* */
#define PM_REG_CONTROL       0x01u   /* W  uint8  see PM_CTRL_* */
#define PM_REG_ERROR_CODE    0x02u   /* RO uint8  see PM_ERR_* */
#define PM_REG_TEMP_SOURCE   0x03u   /* RW uint8  PM_SOURCE_* */
#define PM_REG_T_SET         0x04u   /* RW int16  degC x100 (0..5000) */
#define PM_REG_T_EXT         0x06u   /* RW int16  degC x100 (external source, refresh < 2 s) */
#define PM_REG_T_ACTUAL      0x08u   /* RO int16  degC x100 (value feeding the PID) */
#define PM_REG_T_PT1000      0x0Au   /* RO int16  degC x100 (onboard PT1000) */
#define PM_REG_CAL_LOW       0x0Cu   /* RO uint16 raw counts */
#define PM_REG_CAL_HIGH      0x0Eu   /* RO uint16 raw counts */
#define PM_REG_KP            0x10u   /* RW uint16 x1000 */
#define PM_REG_KI            0x12u   /* RW uint16 x1000 */
#define PM_REG_KD            0x14u   /* RW uint16 x1000 */
#define PM_REG_I_LIMIT       0x16u   /* RW uint16 mA (500..3000, only while stopped) */
#define PM_REG_I_ACTUAL      0x18u   /* RO uint16 mA */
#define PM_REG_DUTY_CYCLE    0x1Au   /* RO uint16 x1000 */
#define PM_REG_MAP_SIZE      0x1Cu

/* telemetry block read in one go: the whole map */
#define PM_TELEMETRY_FIRST   PM_REG_STATUS
#define PM_TELEMETRY_LEN     PM_REG_MAP_SIZE

/* ---- STATUS bits ---- */
#define PM_ST_RUNNING        0x01u
#define PM_ST_ERROR          0x02u
#define PM_ST_COOLING        0x04u
#define PM_ST_TEMP_VALID     0x08u

/* ---- CONTROL bits (write-triggered) ---- */
#define PM_CTRL_START        0x01u
#define PM_CTRL_STOP         0x02u
#define PM_CTRL_CLEAR_ERROR  0x04u
#define PM_CTRL_RECALIBRATE  0x08u

/* ---- ERROR_CODE values ---- */
#define PM_ERR_NONE                 0u
#define PM_ERR_STARTUP_OVERCURRENT  1u
#define PM_ERR_RUNTIME_OVERCURRENT  2u
#define PM_ERR_SANITY               3u
#define PM_ERR_TEMP_SENSOR          4u
#define PM_ERR_EXT_TEMP_TIMEOUT     5u
#define PM_ERR_OPEN_LOAD            6u
#define PM_ERR_TEMP_CALIBRATION     7u

/* ---- TEMP_SOURCE values ---- */
#define PM_SOURCE_EXTERNAL   0u      /* T_EXT written by the MM (tab sensor of a BM) */
#define PM_SOURCE_PT1000     1u      /* onboard PT1000 (default) */

/* ---- value ranges (PM clamps itself as well) ---- */
#define PM_T_SET_MIN_CENTI   0
#define PM_T_SET_MAX_CENTI   5000
#define PM_I_LIMIT_MIN_MA    500u
#define PM_I_LIMIT_MAX_MA    3000u   /* permissible for the Peltier element even at 24 V (PM measuring range ~8.25 A) */

#endif /* PM_REGS_H */
