/**
 ******************************************************************************
 * @file    i2c_comm.c
 * @brief   See i2c_comm.h.
 *
 * How the slave receive works (verified against stm32c0xx_hal_i2c.c):
 * a slave does not know how long a master write is. The HAL only calls
 * HAL_I2C_SlaveRxCpltCallback when ALL requested bytes have arrived; a master
 * that stops earlier ends the transfer with HAL_I2C_ERROR_AF through
 * HAL_I2C_ErrorCallback + HAL_I2C_ListenCpltCallback instead. So we receive
 * ONE byte at a time (re-armed from the callback) and treat "transfer ended
 * with AF only" as the normal end of a write.
 ******************************************************************************
 */
#include "i2c_comm.h"
#include "pm_config.h"

#if PM_ENABLE_I2C

#include "pid_control.h"
#include "temperature_sensor.h"
#include "current_sensor.h"
#include "pm_settings.h"
#include <string.h>
#include <stddef.h>

extern I2C_HandleTypeDef hi2c1; /* initialised by MX_I2C1_Init() in main.c */

#define I2C_IRQ_PRIORITY      1u      /* above USART1 (2) */
#define I2C_OAR1_ADDR7_SHIFT  1u      /* OAR1: 7-bit address in bits 7..1 */

/* register scaling */
#define CENTI_PER_DEGC      100.0f    /* temperatures in degC x100 */
#define MILLI_PER_UNIT     1000.0f    /* gains and duty cycle x1000 */
#define MA_PER_A           1000.0f    /* currents in mA */

/* STATUS register bits */
#define ST_RUNNING        0x01u
#define ST_ERROR          0x02u
#define ST_COOLING        0x04u
#define ST_TEMP_VALID     0x08u

typedef struct __attribute__((packed))
{
    uint8_t  status;      /* 0x00 RO */
    uint8_t  control;     /* 0x01 RW, write-triggered */
    uint8_t  errorCode;   /* 0x02 RO */
    uint8_t  tempSource;  /* 0x03 RW: temperature source for the PID: 0 external (T_EXT), 1 onboard PT1000 (default) */
    int16_t  tSet;        /* 0x04 RW, degC x100 */
    int16_t  tExt;        /* 0x06 RW, degC x100 */
    int16_t  tActual;     /* 0x08 RO, degC x100 */
    int16_t  tPt1000;     /* 0x0A RO, degC x100 */
    uint16_t calLow;      /* 0x0C RO, raw counts on the 1.00 kOhm reference */
    uint16_t calHigh;     /* 0x0E RO, raw counts on the 1.20 kOhm reference */
    uint16_t kp;          /* 0x10 RW, x1000 */
    uint16_t ki;          /* 0x12 RW, x1000 */
    uint16_t kd;          /* 0x14 RW, x1000 */
    uint16_t iLimit;      /* 0x16 RW, mA */
    uint16_t iActual;     /* 0x18 RO, mA */
    uint16_t dutyCycle;   /* 0x1A RO, x1000 */
} RegisterMap_t;

#define REG_MAP_SIZE      ((uint8_t)sizeof(RegisterMap_t))
#define OFF(field)        ((uint8_t)offsetof(RegisterMap_t, field))
#define BIT(off)          (1ul << (off))
#define BITS16(field)     (BIT(OFF(field)) | BIT(OFF(field) + 1u))   /* both bytes of a 16-bit register */

/* One bit per register offset that a master may write:
 * CONTROL(1), TEMP_SOURCE(3), T_SET/T_EXT(4..7), KP/KI/KD/I_LIMIT(0x10..0x17). */
#define WRITABLE_MASK     (BIT(OFF(control)) | BIT(OFF(tempSource)) | BITS16(tSet) | BITS16(tExt) | \
                           BITS16(kp) | BITS16(ki) | BITS16(kd) | BITS16(iLimit))

/* Compile-time layout checks: a violated check stops the build with "size of array
 * 'layout_check_<name>' is negative". Written as the classic negative-array typedef
 * instead of C11 _Static_assert because the CubeIDE editor's parser flags
 * _Static_assert as a syntax error, while gcc accepts both. */
#define LAYOUT_CHECK(name, cond)  typedef char layout_check_##name[(cond) ? 1 : -1]
LAYOUT_CHECK(map_size_is_28_bytes,    sizeof(RegisterMap_t)              == 0x1Cu);
LAYOUT_CHECK(t_set_at_0x04,           offsetof(RegisterMap_t, tSet)      == 0x04u);
LAYOUT_CHECK(t_ext_at_0x06,           offsetof(RegisterMap_t, tExt)      == 0x06u);
LAYOUT_CHECK(kp_at_0x10,              offsetof(RegisterMap_t, kp)        == 0x10u);
LAYOUT_CHECK(i_limit_at_0x16,         offsetof(RegisterMap_t, iLimit)    == 0x16u);
LAYOUT_CHECK(duty_cycle_at_0x1A,      offsetof(RegisterMap_t, dutyCycle) == 0x1Au);
LAYOUT_CHECK(map_fits_32bit_mask,     sizeof(RegisterMap_t)              <= 32u);

/* CONTROL register bits */
#define CTRL_START        0x01u
#define CTRL_STOP         0x02u
#define CTRL_CLEAR_ERROR  0x04u
#define CTRL_RECALIBRATE  0x08u

static RegisterMap_t regs;      /* the register map; RO fields written by main loop, RW fields committed by the ISR */
static RegisterMap_t applied;   /* RW field values already applied to the modules (avoids redundant re-applies) */

/* ISR-side transaction state */
static uint8_t  regPointer = 0u;             /* read pointer, set by the first byte of a master write */
static uint8_t  rxByte = 0u;                 /* 1-byte slave receive buffer */
static uint8_t  rxCount = 0u;                /* bytes received in the current master write (first = pointer) */
static uint8_t  wrPointer = 0u;              /* register offset the next data byte belongs to */
static uint8_t  wrData[REG_MAP_SIZE];        /* data bytes of the current write, committed as a group at its end */
static uint32_t wrMask = 0u;                 /* which offsets wrData holds valid bytes for */
static uint8_t  txSnapshot[REG_MAP_SIZE];    /* consistent copy of the map for the current master read */

static volatile uint8_t pendingControlWrite = 0u;
static volatile uint8_t pendingConfigWrite = 0u;
static volatile uint8_t pendingTExtWrite = 0u;   /* T_EXT was written (refreshes the external-source timeout even if unchanged) */

/* ---- helpers ---------------------------------------------------------------- */
/* float -> register value: round to nearest and saturate (a plain cast would
 * truncate, and is undefined for out-of-range values). */
static int16_t ToInt16(float v)
{
    if (v >= (float)INT16_MAX) return INT16_MAX;
    if (v <= (float)INT16_MIN) return INT16_MIN;
    return (int16_t)((v >= 0.0f) ? (v + 0.5f) : (v - 0.5f));
}

static uint16_t ToUint16(float v)
{
    if (v <= 0.0f)       return 0u;
    if (v >= (float)UINT16_MAX) return UINT16_MAX;
    return (uint16_t)(v + 0.5f);
}

/* Commit the bytes of a finished master write into the register map (all
 * together) and flag them for the main loop. Idempotent. */
static void FinishWriteTransaction(void)
{
    uint32_t mask = wrMask;
    uint8_t off;

    if (mask != 0u)
    {
        uint8_t *dst = (uint8_t *)&regs;

        for (off = 0u; off < REG_MAP_SIZE; off++)
        {
            if (mask & BIT(off))
                dst[off] = wrData[off];
        }

        if (mask & BIT(OFF(control)))
            pendingControlWrite = 1u;
        if (mask & ~BIT(OFF(control)))
            pendingConfigWrite = 1u;
        if (mask & BITS16(tExt))
            pendingTExtWrite = 1u;
    }

    wrMask = 0u;
    rxCount = 0u;
}

/* ---- main-loop side --------------------------------------------------------- */
void I2cComm_SetAddress(uint8_t addr7)
{
    /* Same way as HAL_I2C_Init(): OA1 may only be written while OA1EN = 0. */
    hi2c1.Init.OwnAddress1 = (uint32_t)addr7 << I2C_OAR1_ADDR7_SHIFT;
    hi2c1.Instance->OAR1 &= ~I2C_OAR1_OA1EN;
    hi2c1.Instance->OAR1 = I2C_OAR1_OA1EN | hi2c1.Init.OwnAddress1;
}

void I2cComm_Init(void)
{
    float kp, ki, kd;

    /* Start from the values the modules really use, so the master reads the
     * true defaults instead of zeros. */
    memset(&regs, 0, sizeof(regs));
    PidControl_GetGains(&kp, &ki, &kd);
    regs.tSet       = ToInt16(PidControl_GetSetpoint() * CENTI_PER_DEGC);
    regs.tExt       = 0;
    regs.tempSource = (uint8_t)TempSensor_GetSource();
    regs.kp         = ToUint16(kp * MILLI_PER_UNIT);
    regs.ki         = ToUint16(ki * MILLI_PER_UNIT);
    regs.kd         = ToUint16(kd * MILLI_PER_UNIT);
    regs.iLimit     = ToUint16(PidControl_GetCurrentLimit() * MA_PER_A);
    applied = regs;

    regPointer = 0u;
    rxCount = 0u;
    wrMask = 0u;
    pendingControlWrite = 0u;
    pendingConfigWrite = 0u;
    pendingTExtWrite = 0u;

    /* MX_I2C1_Init() (CubeMX-generated) leaves OwnAddress1 at 0: set the
     * address stored in flash (pm_settings.h, default 0x28). */
    PmSettings_Load();
    I2cComm_SetAddress(PmSettings_Get()->i2cAddr);

    /* The CubeMX project does not enable the I2C1 interrupt: do it here
     * (the matching handler is I2C1_IRQHandler() at the end of this file). */
    HAL_NVIC_SetPriority(I2C1_IRQn, I2C_IRQ_PRIORITY, 0u);
    HAL_NVIC_EnableIRQ(I2C1_IRQn);

    (void)HAL_I2C_EnableListen_IT(&hi2c1);
}

void I2cComm_Update(void)
{
    RegisterMap_t snap;
    uint8_t doControl, doConfig, doTExt;

    /* 1) Build the telemetry outside the critical section ... */
    const uint8_t status = (uint8_t)((PidControl_IsRunning() ? ST_RUNNING : 0u) |
                                     (PidControl_IsError() ? ST_ERROR : 0u) |
                                     ((PidControl_GetDirection() == PID_DIRECTION_COOLING) ? ST_COOLING : 0u) |
                                     (TempSensor_IsReady() ? ST_TEMP_VALID : 0u));
    const uint8_t  errorCode = (uint8_t)PidControl_GetErrorCode();
    const int16_t  tActual   = ToInt16(TempSensor_GetControlTemperature() * CENTI_PER_DEGC);
    const int16_t  tPt1000   = ToInt16(TempSensor_GetTemperature() * CENTI_PER_DEGC);
    const uint16_t calLow    = TempSensor_GetCalCountsLow();
    const uint16_t calHigh   = TempSensor_GetCalCountsHigh();
    const uint16_t iActual   = ToUint16(PidControl_GetMeasuredCurrent() * MA_PER_A);
    const uint16_t duty      = ToUint16(PidControl_GetDutyCycle() * MILLI_PER_UNIT);

    /* 2) ... then store it, and take a consistent copy of the writable fields,
     * with the I2C interrupt masked for these few instructions. This keeps
     * the ISR from ever seeing a half-updated telemetry value and the main
     * loop from ever seeing a half-committed write. */
    __disable_irq();
    regs.status    = status;
    regs.errorCode = errorCode;
    regs.tActual   = tActual;
    regs.tPt1000   = tPt1000;
    regs.calLow    = calLow;
    regs.calHigh   = calHigh;
    regs.iActual   = iActual;
    regs.dutyCycle = duty;

    doControl = pendingControlWrite;
    doConfig  = pendingConfigWrite;
    doTExt    = pendingTExtWrite;
    pendingControlWrite = 0u;
    pendingConfigWrite  = 0u;
    pendingTExtWrite    = 0u;
    snap = regs;
    if (doControl)
        regs.control = 0u; /* command bits are self-clearing */
    __enable_irq();

    /* 3) Act on what the master wrote. */
    if (doControl)
    {
        if (snap.control & CTRL_START)        PidControl_Start();
        if (snap.control & CTRL_STOP)         PidControl_Stop();
        if (snap.control & CTRL_CLEAR_ERROR)  PidControl_ClearError();
        if ((snap.control & CTRL_RECALIBRATE) && !PidControl_IsRunning())
            TempSensor_Recalibrate();
    }

    if (doConfig)
    {
        /* Apply only what actually changed: PidControl_SetSetpoint() also
         * resets the integrator, which must not happen just because the master
         * wrote, say, the current limit. */
        if (snap.tSet != applied.tSet)
        {
            PidControl_SetSetpoint((float)snap.tSet / CENTI_PER_DEGC);
            applied.tSet = snap.tSet;
        }
        if (snap.tempSource != applied.tempSource)
        {
            if (snap.tempSource <= (uint8_t)TEMP_SOURCE_INTERNAL)
                TempSensor_SetSource((TempSensor_Source_t)snap.tempSource);
            applied.tempSource = snap.tempSource;
        }
        if ((snap.kp != applied.kp) || (snap.ki != applied.ki) || (snap.kd != applied.kd))
        {
            PidControl_SetGains((float)snap.kp / MILLI_PER_UNIT, (float)snap.ki / MILLI_PER_UNIT, (float)snap.kd / MILLI_PER_UNIT);
            applied.kp = snap.kp;
            applied.ki = snap.ki;
            applied.kd = snap.kd;
        }
        if (snap.iLimit != applied.iLimit)
        {
            (void)PidControl_SetCurrentLimit((float)snap.iLimit / MA_PER_A); /* rejected while running */
            applied.iLimit = snap.iLimit;
        }
    }

    /* 4) Mirror the settings that are really in effect back into the register
     * map, so the master always reads them: T_SET / I_LIMIT may have been
     * clamped (T_SET 0..50 degC, I_LIMIT 0.5..5 A) or rejected (I_LIMIT while
     * running), and all of them may also have been changed over the debug UART
     * (uart_comm.c). A field is only overwritten if the master has not written
     * a newer value in the meantime (that one is applied on the next call). */
    {
        float kpNow, kiNow, kdNow;
        int16_t  effTSet;
        uint16_t effILimit, effKp, effKi, effKd;
        uint8_t  effSource;

        PidControl_GetGains(&kpNow, &kiNow, &kdNow);
        effTSet   = ToInt16(PidControl_GetSetpoint() * CENTI_PER_DEGC);
        effILimit = ToUint16(PidControl_GetCurrentLimit() * MA_PER_A);
        effKp     = ToUint16(kpNow * MILLI_PER_UNIT);
        effKi     = ToUint16(kiNow * MILLI_PER_UNIT);
        effKd     = ToUint16(kdNow * MILLI_PER_UNIT);
        effSource = (uint8_t)TempSensor_GetSource();

        __disable_irq();
        if (regs.tSet == snap.tSet)             regs.tSet = effTSet;
        if (regs.iLimit == snap.iLimit)         regs.iLimit = effILimit;
        if (regs.kp == snap.kp)                 regs.kp = effKp;
        if (regs.ki == snap.ki)                 regs.ki = effKi;
        if (regs.kd == snap.kd)                 regs.kd = effKd;
        if (regs.tempSource == snap.tempSource) regs.tempSource = effSource;
        __enable_irq();
        applied.tSet       = effTSet;
        applied.iLimit     = effILimit;
        applied.kp         = effKp;
        applied.ki         = effKi;
        applied.kd         = effKd;
        applied.tempSource = effSource;
    }

    /* T_EXT: applied on EVERY write, even with an unchanged value - each write
     * refreshes the timeout of the external temperature source. */
    if (doTExt)
    {
        TempSensor_SetExternalTemperature((float)snap.tExt / CENTI_PER_DEGC);
        applied.tExt = snap.tExt;
    }
}

/* ---- ISR side --------------------------------------------------------------
 * Kept minimal on purpose: move bytes and set flags; all application logic
 * runs from I2cComm_Update() above. */

void HAL_I2C_AddrCallback(I2C_HandleTypeDef *hi2c, uint8_t TransferDirection, uint16_t AddrMatchCode)
{
    (void)AddrMatchCode;
    if (hi2c != &hi2c1)
        return;

    /* A new address phase ends whatever write came before it (write, then
     * repeated START, then read is the normal register-read sequence). */
    FinishWriteTransaction();

    if (TransferDirection == I2C_DIRECTION_TRANSMIT)
    {
        /* Master writes: first byte = register pointer, the rest = data.
         * Receive one byte at a time (see file header). */
        (void)HAL_I2C_Slave_Seq_Receive_IT(hi2c, &rxByte, 1u, I2C_FIRST_FRAME);
    }
    else
    {
        /* Master reads: send the register map from the pointer on, from a
         * snapshot taken now (consistent, even if telemetry updates meanwhile). */
        memcpy(txSnapshot, &regs, REG_MAP_SIZE);
        (void)HAL_I2C_Slave_Seq_Transmit_IT(hi2c, &txSnapshot[regPointer],
                                            (uint16_t)(REG_MAP_SIZE - regPointer), I2C_LAST_FRAME);
    }
}

void HAL_I2C_SlaveRxCpltCallback(I2C_HandleTypeDef *hi2c)
{
    if (hi2c != &hi2c1)
        return;

    if (rxCount == 0u)
    {
        /* first byte of a write = register pointer */
        wrPointer = rxByte;
        regPointer = (rxByte < REG_MAP_SIZE) ? rxByte : 0u;
    }
    else if (wrPointer < REG_MAP_SIZE)
    {
        if (WRITABLE_MASK & BIT(wrPointer))
        {
            wrData[wrPointer] = rxByte;
            wrMask |= BIT(wrPointer);
        }
        wrPointer++;
    }
    else
    {
        /* beyond the end of the map: ACK and ignore */
    }

    if (rxCount < UINT8_MAX)
        rxCount++;

    /* arm the next byte (keeps the transfer open until the master's STOP) */
    (void)HAL_I2C_Slave_Seq_Receive_IT(hi2c, &rxByte, 1u, I2C_NEXT_FRAME);
}

/* The HAL reports "master ended the transfer earlier than the length we armed"
 * as HAL_I2C_ERROR_AF. For a slave that is the NORMAL end of every write (an
 * armed 1-byte receive is always still open at the STOP) and of every read
 * that is shorter than the rest of the map - not an error. */
void HAL_I2C_ErrorCallback(I2C_HandleTypeDef *hi2c)
{
    if (hi2c != &hi2c1)
        return;

    if ((HAL_I2C_GetError(hi2c) & ~HAL_I2C_ERROR_AF) == 0u)
    {
        FinishWriteTransaction();       /* normal end of a transfer */
    }
    else
    {
        wrMask = 0u;                    /* real bus error: drop the partial write */
        rxCount = 0u;
    }

    (void)HAL_I2C_EnableListen_IT(hi2c); /* returns HAL_BUSY (no-op) while the HAL is still listening */
}

void HAL_I2C_ListenCpltCallback(I2C_HandleTypeDef *hi2c)
{
    if (hi2c != &hi2c1)
        return;

    FinishWriteTransaction();
    (void)HAL_I2C_EnableListen_IT(hi2c);
}

/* I2C1 has ONE combined interrupt vector on the STM32C0: error flags go to the
 * HAL error handler, everything else to the event handler.
 * NOTE: if you later enable "I2C1 global interrupt" in CubeMX, it generates
 * its own I2C1_IRQHandler in stm32c0xx_it.c - then delete this one (the
 * HAL_NVIC_* lines in I2cComm_Init() are harmless to keep). */
void I2C1_IRQHandler(void)
{
    if (hi2c1.Instance->ISR & (I2C_ISR_BERR | I2C_ISR_ARLO | I2C_ISR_OVR))
        HAL_I2C_ER_IRQHandler(&hi2c1);
    else
        HAL_I2C_EV_IRQHandler(&hi2c1);
}

#else  /* !PM_ENABLE_I2C: interface switched off in pm_config.h */

void I2cComm_Init(void)   { }
void I2cComm_Update(void) { }
void I2cComm_SetAddress(uint8_t addr7) { (void)addr7; }

#endif /* PM_ENABLE_I2C */
