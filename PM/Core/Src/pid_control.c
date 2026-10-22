/**
 ******************************************************************************
 * @file    pid_control.c
 * @brief   See pid_control.h.
 ******************************************************************************
 */
#include "pid_control.h"
#include "temperature_sensor.h"
#include "current_sensor.h"

extern TIM_HandleTypeDef htim3; /* PWM_CTRL / TIM3_CH1, initialised by MX_TIM3_Init() in main.c */

/* ---- Tunables, carried over from the original driver (converted from its
 * 0.1ms-tick units to milliseconds since HAL_GetTick() is now the timebase) */
#define PID_FREQ_HZ                    10.0f  /* PID calculation rate: one calculation per new temperature
                                               * sample, i.e. 1000 / TEMP_SAMPLE_INTERVAL_MS (temperature_sensor.c) */
#define RELAY_ACTUATION_MS             50u    /* time to energise the bistable relay coil */
#define CURRENT_CYCLE_MS               10u    /* actuation stage update rate */
#define CURRENT_UPDATE_COOLDOWN_MS     20u    /* settle time after a new control value before overcurrent checks resume */
#define RECAL_COOLDOWN_MS              20u    /* settle time after a duty-cycle recalibration */
#define FLIP_TIME_MS                 1000u    /* minimum time direction must be requested before the relay actually flips */

/* PWM resolution is taken from the timer itself (ARR + 1 counts per period, set
 * by the TIM3 Counter Period in PM.ioc), so it stays correct if the PWM frequency
 * is changed there. 100 % duty = CCR = ARR + 1 (PWM mode 1, up-counting). */

#define DUTY_CYCLE_START                0.2f  /* initial test duty cycle for the startup short-circuit check */
#define CURRENT_LIMIT_START_A           3.0f  /* fixed startup short-circuit threshold, independent of the user-settable run-time limit */
#define OPEN_LOAD_MIN_CURRENT_A         0.1f  /* startup: less than this at DUTY_CYCLE_START = no Peltier element connected / open circuit */
#define I_SAT_P                         2.5f  /* integrator anti-windup, positive */
#define I_SAT_N                        -2.5f  /* integrator anti-windup, negative */
/* Highest duty cycle ever applied. The high-side gate driver (TPS28225) is
 * supplied from the bootstrap capacitor C25, which only recharges while the
 * low side conducts: at 100 % it is never recharged, the gate voltage of the
 * high-side MOSFET sags and the MOSFET heats up in its linear region. */
#define DUTY_CYCLE_MAX                  0.95f
#define PERCENT_PER_UNIT              100.0f
#define DUTY_OVERLOAD_NONE              1.0f  /* dutyCycleOverload: no overload factor */

/* Waiting times of the (blocking) startup check and of the stop sequence */
#define STARTUP_ZERO_SETTLE_MS         10u    /* after the current zero calibration, before the test duty cycle */
#define STARTUP_TEST_SETTLE_MS          4u    /* current settling at the test duty cycle (per reading) */
#define STARTUP_LIMIT_SETTLE_MS         8u    /* current settling while the duty-cycle limit is determined */
#define STARTUP_END_SETTLE_MS           5u    /* current back to zero at the end of the startup check */
#define STOP_CURRENT_DECAY_MS           4u    /* current back to zero before the relay may switch */

/* Duty-cycle limit: the startup check first aims at this fraction of the
 * current limit, so the second step does not overshoot it */
#define STARTUP_LIMIT_APPROACH          0.9f

/* Overcurrent trip: measured current above currentLimit + this margin */
#define OVERCURRENT_MARGIN_A            0.5f

/* Run-time recalibration of the duty-cycle limit: only above this fraction of
 * the current limit, and only if measured and requested current differ by
 * more than the tolerance */
#define DC_RECAL_MIN_FRACTION           0.5f
#define DC_RECAL_TOLERANCE_A            0.08f

/* Sanity check: the temperature error may grow by at most this much beyond
 * its value at the start (wrong polarity / runaway) */
#define SANITY_ERR_GROWTH_K             3.0f

/* Defaults after reset (all changeable via I2C / console) */
#define PID_TSET_DEFAULT_DEGC          25.0f
#define PID_KP_DEFAULT                  1.0f
#define PID_KI_DEFAULT                  0.1f
#define PID_KD_DEFAULT                  1.0f
#define PID_I_LIMIT_DEFAULT_A           2.0f

/* Recalibration of the temperature front-end "when the setpoint is reached"
 * (in addition to the one on every new setpoint): the setpoint counts as reached
 * once |T_SET - T| stayed within the band for this many PID cycles. Happens once
 * per setpoint / per start. Only with the internal PT1000 as control source. */
#define SETPOINT_REACHED_BAND_K         0.2f   /* K */
#define SETPOINT_REACHED_SAMPLES         50u   /* x 100 ms = 5 s */

/* Derivative filter (structure from the original driver): the derivative of the
 * error is estimated as the mean of 11 difference quotients over 1..11 sample
 * intervals,
 *
 *     de/dt ~= 1/11 * sum_{i=0..10} (err - errHistory[i]) / ((i + 1) * Ts),
 *
 * where errHistory[i] is the error (i + 1) samples ago and Ts = 1 / PID_FREQ_HZ.
 * dWeight[i] = 1 / ((i + 1) * Ts) = PID_FREQ_HZ / (i + 1) [1/s] is calculated in
 * PidControl_Init(), so it is exact and follows PID_FREQ_HZ. (The original used a
 * rounded table for 10 Hz with typos, e.g. 0.99 instead of 0.909 for the oldest slot.) */
#define ERR_HISTORY_LEN              11u              /* number of difference quotients */
#define ERR_FILT_CO                  (1.0f / (float)ERR_HISTORY_LEN)   /* averaging over the 11 estimates */
static float dWeight[ERR_HISTORY_LEN];

/* ---- PID state ----------------------------------------------------------- */
typedef enum { PID_STATE_OFF, PID_STATE_WAIT_FOR_DRIVER, PID_STATE_WAIT, PID_STATE_CALCULATE, PID_STATE_ERROR } PidState_t;

static PidState_t pidState = PID_STATE_OFF;
static uint8_t startRequested = 0;
static uint8_t stopRequested = 0;
static float T_SET = PID_TSET_DEFAULT_DEGC;
static float kp = PID_KP_DEFAULT, ki = PID_KI_DEFAULT, kd = PID_KD_DEFAULT;
static float P_val = 0.0f, I_val = 0.0f, D_val = 0.0f;
static float pidOut = 0.0f;
static float err = 0.0f, errStart = 0.0f;
static float errHistory[ERR_HISTORY_LEN];
static uint8_t tempUpdatedFlag = 0;
static uint8_t reachedCount = 0;      /* consecutive PID cycles within SETPOINT_REACHED_BAND_K */
static uint8_t reachedRecalDone = 0;  /* the "setpoint reached" recalibration has been requested for this setpoint */
static PidControl_Error_t lastError = PID_ERROR_NONE;

/* ---- Driver / actuation state --------------------------------------------- */
typedef enum { DRIVER_STATE_OFF, DRIVER_STATE_ON, DRIVER_STATE_ERROR } DriverState_t;

static DriverState_t driverState = DRIVER_STATE_OFF;
static uint8_t driverStartRequested = 0;
static uint8_t driverStopRequested = 0;
static PidControl_Direction_t driverDirection  = PID_DIRECTION_HEATING; /* HEATING = RELAY_SET, COOLING = RELAY_RESET */
static PidControl_Direction_t controlDirection = PID_DIRECTION_HEATING;
static uint8_t directionFlipCounter = 0;
static uint8_t directionFlipThreshold = 1; /* recomputed in Init */
static float currentLimit = PID_I_LIMIT_DEFAULT_A;  /* symmetric magnitude, I2C-settable */
static float dutyCycle = 0.0f, dutyCyclePrevious = 0.0f;
static float dutyCycleLimit = DUTY_CYCLE_MAX, dutyCycleOverload = DUTY_OVERLOAD_NONE;
static float currentMaxDC = 0.0f;
static float currentControl = 0.0f, currentControlPrevious = 0.0f;
static float measuredCurrent = 0.0f;
static uint8_t currentUpdatedSettlingCycles = 0;
static uint8_t recalibrationCooldownCounter = 0;
static uint8_t relayActuatedCooldownCounter = 0;
static uint32_t driverLastTick = 0;

/* ---- Manual duty-cycle mode (bring-up test, debug console "duty") ---------- */
static uint8_t manualActive = 0;    /* fixed duty cycle without regulation, heating direction */

/* ---- Small helpers --------------------------------------------------------- */
static void BusyWaitMs(uint32_t ms)
{
    uint32_t start = HAL_GetTick();
    while ((HAL_GetTick() - start) < ms) { }
}

static void SetPwmDutyCycle(float dc)
{
    if (dc <= dutyCycleLimit && dc >= 0.0f && dc <= DUTY_CYCLE_MAX)   /* never above DUTY_CYCLE_MAX */
        htim3.Instance->CCR1 = (uint32_t)(dc * (float)(htim3.Instance->ARR + 1u) + 0.5f);
}

static void SetRelayHeating(void)
{
    HAL_GPIO_WritePin(RELAY_RESET_GPIO_Port, RELAY_RESET_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(RELAY_SET_GPIO_Port, RELAY_SET_Pin, GPIO_PIN_SET);
    HAL_GPIO_WritePin(PID_COOLING_GPIO_Port, PID_COOLING_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(PID_HEATING_GPIO_Port, PID_HEATING_Pin, GPIO_PIN_SET);
}

static void SetRelayCooling(void)
{
    HAL_GPIO_WritePin(RELAY_SET_GPIO_Port, RELAY_SET_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(RELAY_RESET_GPIO_Port, RELAY_RESET_Pin, GPIO_PIN_SET);
    HAL_GPIO_WritePin(PID_HEATING_GPIO_Port, PID_HEATING_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(PID_COOLING_GPIO_Port, PID_COOLING_Pin, GPIO_PIN_SET);
}

static void ReleaseRelayCoils(void)
{
    /* Bistable relay: only ever pulsed, never held - drop both coil drives
     * to reduce parasitic current, same as the original driver. */
    HAL_GPIO_WritePin(RELAY_SET_GPIO_Port, RELAY_SET_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(RELAY_RESET_GPIO_Port, RELAY_RESET_Pin, GPIO_PIN_RESET);
}

static void EnterDriverError(PidControl_Error_t reason)
{
    dutyCycle = 0.0f;
    SetPwmDutyCycle(0.0f);
    HAL_GPIO_WritePin(FAN_CTRL_GPIO_Port, FAN_CTRL_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(PID_COOLING_GPIO_Port, PID_COOLING_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(PID_HEATING_GPIO_Port, PID_HEATING_Pin, GPIO_PIN_RESET);
    lastError = reason;
    driverState = DRIVER_STATE_ERROR;
}

/* ---- Driver / actuation stage ---------------------------------------------- */

/* One-time startup sequence: switch to heating direction, ramp to a test
 * duty cycle and measure the resulting current twice (catches short
 * circuits before real power is applied for any length of time), then
 * derive dutyCycleLimit so that currentLimit is not exceeded regardless of
 * supply voltage / Peltier resistance tolerance. Blocking (~100-150 ms) -
 * see the design note in pid_control.h for why that is fine here. */
static uint8_t RunStartupCalibration(void)
{
    driverDirection = PID_DIRECTION_HEATING;
    SetRelayHeating();
    BusyWaitMs(RELAY_ACTUATION_MS);
    ReleaseRelayCoils();

    dutyCycle = 0.0f;
    dutyCycleLimit = DUTY_CYCLE_MAX;
    dutyCycleOverload = DUTY_OVERLOAD_NONE;
    currentMaxDC = 0.0f;
    SetPwmDutyCycle(0.0f);
    HAL_TIM_PWM_Start(&htim3, TIM_CHANNEL_1);

    CurrentSensor_CalibrateZero(); /* PWM is at 0% here: genuine zero-current baseline */

    BusyWaitMs(STARTUP_ZERO_SETTLE_MS);

    dutyCycle = DUTY_CYCLE_START;
    SetPwmDutyCycle(dutyCycle);
    BusyWaitMs(STARTUP_TEST_SETTLE_MS);

    measuredCurrent = CurrentSensor_Read();
    if (measuredCurrent > CURRENT_LIMIT_START_A || CurrentSensor_IsSaturated())
    {
        HAL_TIM_PWM_Stop(&htim3, TIM_CHANNEL_1);
        EnterDriverError(PID_ERROR_STARTUP_OVERCURRENT);
        return 0;
    }

    BusyWaitMs(STARTUP_TEST_SETTLE_MS);
    measuredCurrent = CurrentSensor_Read();
    if (measuredCurrent > CURRENT_LIMIT_START_A || CurrentSensor_IsSaturated())
    {
        HAL_TIM_PWM_Stop(&htim3, TIM_CHANNEL_1);
        EnterDriverError(PID_ERROR_STARTUP_OVERCURRENT);
        return 0;
    }
    if (measuredCurrent < OPEN_LOAD_MIN_CURRENT_A)
    {
        /* (Practically) no current at the test duty cycle: Peltier element not
         * connected or circuit open. Also protects the dutyCycleLimit calculation
         * below from dividing by ~0. */
        HAL_TIM_PWM_Stop(&htim3, TIM_CHANNEL_1);
        EnterDriverError(PID_ERROR_OPEN_LOAD);
        return 0;
    }
    currentMaxDC = measuredCurrent;

    /* Target ~90% of the configured limit at the current/duty-cycle ratio just measured */
    dutyCycle = STARTUP_LIMIT_APPROACH * (currentLimit / currentMaxDC) * DUTY_CYCLE_START;
    if (dutyCycle > DUTY_CYCLE_MAX) dutyCycle = DUTY_CYCLE_MAX;
    SetPwmDutyCycle(dutyCycle);
    BusyWaitMs(STARTUP_LIMIT_SETTLE_MS);
    currentMaxDC = CurrentSensor_Read();

    dutyCycleLimit = (currentLimit / currentMaxDC) * dutyCycle;
    if (dutyCycleLimit > DUTY_CYCLE_MAX) dutyCycleLimit = DUTY_CYCLE_MAX;
    dutyCycle = dutyCycleLimit;
    SetPwmDutyCycle(dutyCycle);
    BusyWaitMs(STARTUP_LIMIT_SETTLE_MS);
    currentMaxDC = CurrentSensor_Read();

    if (currentMaxDC > (currentLimit + OVERCURRENT_MARGIN_A) || CurrentSensor_IsSaturated())
    {
        HAL_TIM_PWM_Stop(&htim3, TIM_CHANNEL_1);
        EnterDriverError(PID_ERROR_STARTUP_OVERCURRENT);
        return 0;
    }

    dutyCycle = 0.0f;
    SetPwmDutyCycle(0.0f);
    currentControl = 0.0f;
    currentControlPrevious = 0.0f;
    dutyCyclePrevious = 0.0f;
    BusyWaitMs(STARTUP_END_SETTLE_MS);

    HAL_GPIO_WritePin(FAN_CTRL_GPIO_Port, FAN_CTRL_Pin, GPIO_PIN_SET);
    driverLastTick = HAL_GetTick();
    return 1;
}

/* Manual mode: only supervision, the duty cycle is set by PidControl_SetManualDuty() */
static void ManualStep(void)
{
    if ((HAL_GetTick() - driverLastTick) < CURRENT_CYCLE_MS)
        return;
    driverLastTick = HAL_GetTick();
    if (measuredCurrent > (currentLimit + OVERCURRENT_MARGIN_A) || CurrentSensor_IsSaturated())
    {
        HAL_TIM_PWM_Stop(&htim3, TIM_CHANNEL_1);
        manualActive = 0;
        EnterDriverError(PID_ERROR_RUNTIME_OVERCURRENT);
    }
}

static void DriverStep(void)
{
    measuredCurrent = CurrentSensor_Read();

    if (manualActive)
    {
        ManualStep();
        return;
    }

    switch (driverState)
    {
    case DRIVER_STATE_OFF:
        if (driverStartRequested)
        {
            driverStartRequested = 0;
            if (RunStartupCalibration())
                driverState = DRIVER_STATE_ON;
        }
        break;

    case DRIVER_STATE_ON:
        if (driverStopRequested)
        {
            driverStopRequested = 0;
            dutyCycle = 0.0f;
            SetPwmDutyCycle(0.0f);
            HAL_TIM_PWM_Stop(&htim3, TIM_CHANNEL_1);
            HAL_GPIO_WritePin(FAN_CTRL_GPIO_Port, FAN_CTRL_Pin, GPIO_PIN_RESET);
            HAL_GPIO_WritePin(PID_COOLING_GPIO_Port, PID_COOLING_Pin, GPIO_PIN_RESET);
            HAL_GPIO_WritePin(PID_HEATING_GPIO_Port, PID_HEATING_Pin, GPIO_PIN_RESET);
            BusyWaitMs(STOP_CURRENT_DECAY_MS);
            SetRelayHeating(); /* leave relay in a defined (heating) position, mirrors original driver */
            driverDirection = PID_DIRECTION_HEATING;
            BusyWaitMs(RELAY_ACTUATION_MS);
            ReleaseRelayCoils();
            driverState = DRIVER_STATE_OFF;
            break;
        }

        if (pidState == PID_STATE_ERROR)
        {
            EnterDriverError(lastError == PID_ERROR_NONE ? PID_ERROR_SANITY : lastError);
            break;
        }

        if ((HAL_GetTick() - driverLastTick) < CURRENT_CYCLE_MS)
            break;
        driverLastTick = HAL_GetTick();

        /* ADC at full scale: the real current is unknown (above the measuring
         * range), so treat it as overcurrent right away, independent of the
         * settling counters below. */
        if (CurrentSensor_IsSaturated())
        {
            EnterDriverError(PID_ERROR_RUNTIME_OVERCURRENT);
            break;
        }

        if (relayActuatedCooldownCounter > 0)
            relayActuatedCooldownCounter--;
        else
            ReleaseRelayCoils();

        /* pidOut == 0 (e.g. right after start) keeps the current relay position */
        if (pidOut > 0.0f)
            controlDirection = PID_DIRECTION_HEATING;
        else if (pidOut < 0.0f)
            controlDirection = PID_DIRECTION_COOLING;
        else
            controlDirection = driverDirection;

        if (driverDirection != controlDirection)
        {
            /* Desired direction differs from the actuated one: hold at zero and
             * only actually flip the relay once the request is stable for
             * FLIP_TIME_MS, so we don't chatter the relay while the PID output
             * hovers around zero. */
            currentControl = 0.0f;
            directionFlipCounter++;
            if (directionFlipCounter > directionFlipThreshold)
            {
                driverDirection = controlDirection;
                if (driverDirection == PID_DIRECTION_COOLING)
                    SetRelayCooling();
                else
                    SetRelayHeating();
                relayActuatedCooldownCounter = (uint8_t)(RELAY_ACTUATION_MS / CURRENT_CYCLE_MS);
                directionFlipCounter = 0;
            }
        }
        else
        {
            float currentControlMag = (currentControl < 0.0f) ? -currentControl : currentControl;

            if (directionFlipCounter > 0)
                directionFlipCounter--;

            if (currentUpdatedSettlingCycles > 1)
            {
                currentUpdatedSettlingCycles--;
                if (recalibrationCooldownCounter > 0)
                    recalibrationCooldownCounter--;
            }
            else
            {
                if (recalibrationCooldownCounter > 0)
                {
                    recalibrationCooldownCounter--;
                }
                else
                {
                    if (currentUpdatedSettlingCycles > 0)
                    {
                        currentUpdatedSettlingCycles--;
                    }
                    else if (measuredCurrent > (currentLimit + OVERCURRENT_MARGIN_A))
                    {
                        /* current is single-ended/unipolar now (see current_sensor.h),
                         * so only one bound needs checking regardless of direction */
                        EnterDriverError(PID_ERROR_RUNTIME_OVERCURRENT);
                        break;
                    }
                }

                if (currentUpdatedSettlingCycles > 0)
                    currentUpdatedSettlingCycles--;

                /* Recalibrate dutyCycleLimit against the actually measured current
                 * whenever we're driving a significant load and the measurement
                 * has drifted from the commanded value - direction-agnostic now
                 * that current is a magnitude, unlike the original's separate
                 * heating/cooling branches. */
                if ((measuredCurrent > (DC_RECAL_MIN_FRACTION * currentLimit) ||
                     currentControlMag > (DC_RECAL_MIN_FRACTION * currentLimit)) &&
                    (measuredCurrent > (currentControlMag + DC_RECAL_TOLERANCE_A) ||
                     measuredCurrent < (currentControlMag - DC_RECAL_TOLERANCE_A)))
                {
                    dutyCycleLimit = (currentLimit / measuredCurrent) * dutyCycle;
                    if (dutyCycleLimit > DUTY_CYCLE_MAX)
                    {
                        dutyCycleOverload = dutyCycleLimit;
                        dutyCycleLimit = DUTY_CYCLE_MAX;
                    }
                    else
                    {
                        dutyCycleOverload = DUTY_OVERLOAD_NONE;
                    }
                    recalibrationCooldownCounter = (uint8_t)(RECAL_COOLDOWN_MS / CURRENT_CYCLE_MS) + 1u;
                }
            }

            currentControl = pidOut;
            if (driverDirection == PID_DIRECTION_HEATING)
            {
                if (currentControl > currentLimit) currentControl = currentLimit;
                if (currentControl < 0.0f) currentControl = 0.0f;
            }
            else
            {
                if (currentControl < -currentLimit) currentControl = -currentLimit;
                if (currentControl > 0.0f) currentControl = 0.0f;
            }
        }

        {
            float currentControlMagNow = (currentControl < 0.0f) ? -currentControl : currentControl;
            dutyCycle = dutyCycleLimit * dutyCycleOverload * (currentControlMagNow / currentLimit);
            if (measuredCurrent > 0.0f)
                dutyCycle -= ((measuredCurrent - ((currentControlPrevious < 0.0f) ? -currentControlPrevious : currentControlPrevious)) / measuredCurrent) * dutyCyclePrevious;
            if (dutyCycle < 0.0f) dutyCycle = 0.0f;
            if (dutyCycle > dutyCycleLimit) dutyCycle = dutyCycleLimit;
            SetPwmDutyCycle(dutyCycle);
        }

        currentControlPrevious = currentControl;
        dutyCyclePrevious = dutyCycle;
        break;

    case DRIVER_STATE_ERROR:
        /* Held until PidControl_ClearError() (I2C CONTROL register) - no local
         * button/LED exist on the PM board, unlike the original driver.
         * Discard any pending start/stop request accumulated while in this
         * state so clearing the error doesn't cause an unrequested auto-start. */
        driverStartRequested = 0;
        driverStopRequested = 0;
        break;
    }
}

/* ---- PID stage -------------------------------------------------------------- */
static void PushErrHistory(void)
{
    uint8_t i;
    for (i = ERR_HISTORY_LEN - 1u; i > 0; i--)
        errHistory[i] = errHistory[i - 1];
    errHistory[0] = err;
}

static float WeightedDerivative(void)
{
    float sum = 0.0f;
    uint8_t i;
    for (i = 0; i < ERR_HISTORY_LEN; i++)
        sum += ERR_FILT_CO * (err - errHistory[i]) * dWeight[i];
    return sum;
}

static void PidStep(void)
{
    /* A recalibration of the temperature front-end moves the measured
     * temperature by a (small) step. Shift the error history by exactly that
     * step, so it looks as if all past samples had been measured with the new
     * calibration already: no derivative kick, no false sanity error. */
    {
        const float shift = TempSensor_ConsumeCalibrationShift(); /* degC, T_new - T_old */
        if (shift != 0.0f)
        {
            uint8_t i;
            for (i = 0; i < ERR_HISTORY_LEN; i++)
                errHistory[i] -= shift;   /* err = T_SET - T */
            err      -= shift;
            errStart -= shift;
        }
    }

    switch (pidState)
    {
    case PID_STATE_OFF:
        /* Keep the error history up to date on the measurement clock, so the
         * derivative filter has correctly spaced samples right from the start. */
        if (TempSensor_ConsumeNewSample())
        {
            PushErrHistory();
            err = T_SET - TempSensor_GetControlTemperature();
        }

        /* A start request waits until the temperature measurement is valid
         * (calibration of the analog front-end right after boot takes ~300 ms),
         * so errStart / the sanity check are never based on a bogus 0 degC. */
        if (startRequested && TempSensor_IsReady())
        {
            startRequested = 0;
            errStart = err;
            tempUpdatedFlag = 0;
            pidOut = 0.0f;          /* no stale output from a previous run */
            P_val = I_val = D_val = 0.0f;
            reachedCount = 0;
            reachedRecalDone = 0;
            driverStartRequested = 1;
            pidState = PID_STATE_WAIT_FOR_DRIVER;
        }
        break;

    case PID_STATE_WAIT_FOR_DRIVER:
        if (driverState == DRIVER_STATE_ON)
        {
            P_val = I_val = D_val = 0.0f;
            pidOut = 0.0f;
            (void)TempSensor_ConsumeNewSample(); /* first calculation on a sample taken after the (blocking) driver start */
            pidState = PID_STATE_WAIT;
        }
        else if (driverState == DRIVER_STATE_ERROR)
        {
            pidState = PID_STATE_OFF;
        }
        break;

    case PID_STATE_WAIT:
        /* One PID calculation per new temperature sample (100 ms measurement clock) */
        if (TempSensor_ConsumeNewSample())
            pidState = PID_STATE_CALCULATE;
        break;

    case PID_STATE_CALCULATE:
        if (driverState == DRIVER_STATE_ERROR)
        {
            pidState = PID_STATE_OFF;
            break;
        }

        /* Temperature not trustworthy (PT1000 at an ADC rail / recalibration
         * failed / T_EXT timed out):
         * stop regulating - the driver follows into its error state. */
        {
            const TempSensor_Fault_t fault = TempSensor_GetFault();
            if (fault != TEMP_FAULT_NONE)
            {
                if (fault == TEMP_FAULT_EXT_TIMEOUT)
                    lastError = PID_ERROR_EXT_TEMP_TIMEOUT;
                else if (fault == TEMP_FAULT_CALIBRATION)
                    lastError = PID_ERROR_TEMP_CALIBRATION;
                else
                    lastError = PID_ERROR_TEMP_SENSOR;
                pidState = PID_STATE_ERROR;
                break;
            }
        }

        PushErrHistory();
        err = T_SET - TempSensor_GetControlTemperature();

        if (tempUpdatedFlag)
        {
            errStart = err;
            I_val = 0.0f;
            tempUpdatedFlag = 0;
        }
        else if ((errStart > 0.0f && err > (errStart + SANITY_ERR_GROWTH_K)) || (errStart <= 0.0f && err < (errStart - SANITY_ERR_GROWTH_K)))
        {
            lastError = PID_ERROR_SANITY;
            pidState = PID_STATE_ERROR;
            break;
        }

        /* Setpoint reached (stable within the band for SETPOINT_REACHED_SAMPLES
         * cycles): recalibrate the front-end once, at the operating point. */
        if (!reachedRecalDone)
        {
            const float errMag = (err < 0.0f) ? -err : err;
            if (errMag <= SETPOINT_REACHED_BAND_K)
            {
                if (++reachedCount >= SETPOINT_REACHED_SAMPLES)
                {
                    reachedRecalDone = 1;
                    if (TempSensor_GetSource() == TEMP_SOURCE_INTERNAL)
                        TempSensor_Recalibrate();
                }
            }
            else
            {
                reachedCount = 0;
            }
        }

        P_val = kp * err;
        I_val += ki * err / PID_FREQ_HZ;
        if (I_val > I_SAT_P) I_val = I_SAT_P;
        if (I_val < I_SAT_N) I_val = I_SAT_N;
        D_val = kd * WeightedDerivative();
        pidOut = P_val + I_val + D_val;

        currentUpdatedSettlingCycles = (uint8_t)(CURRENT_UPDATE_COOLDOWN_MS / CURRENT_CYCLE_MS) + 1u;
        pidState = PID_STATE_WAIT;
        break;

    case PID_STATE_ERROR:
        /* Held until PidControl_ClearError(); driver error (if any) is cleared together with it. */
        break;
    }

    if (stopRequested)
    {
        startRequested = 0; /* also cancels a start that is still waiting for a valid temperature */

        if (pidState != PID_STATE_OFF && pidState != PID_STATE_ERROR)
        {
            driverStopRequested = 1;
            pidState = PID_STATE_OFF;
        }
    }
    stopRequested = 0;
}

/* ---- Public API --------------------------------------------------------------- */
void PidControl_Init(void)
{
    uint8_t i;
    for (i = 0; i < ERR_HISTORY_LEN; i++)
    {
        errHistory[i] = 0.0f;
        dWeight[i] = PID_FREQ_HZ / (float)(i + 1u);   /* 1 / ((i + 1) * Ts), see derivative filter above */
    }

    directionFlipThreshold = (uint8_t)(FLIP_TIME_MS / CURRENT_CYCLE_MS);

    ReleaseRelayCoils();
    HAL_GPIO_WritePin(FAN_CTRL_GPIO_Port, FAN_CTRL_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(PID_HEATING_GPIO_Port, PID_HEATING_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(PID_COOLING_GPIO_Port, PID_COOLING_Pin, GPIO_PIN_RESET);
}

void PidControl_Process(void)
{
    PidStep();
    DriverStep();
}

void PidControl_Start(void)
{
    if (pidState == PID_STATE_OFF && !manualActive)
        startRequested = 1;
}

uint8_t PidControl_SetManualDuty(float percent)
{
    /* only while the regulation is off and no error is latched */
    if (pidState != PID_STATE_OFF || driverState != DRIVER_STATE_OFF || startRequested)
        return 0u;

    if (percent <= 0.0f)
    {
        if (manualActive)
        {
            dutyCycle = 0.0f;
            SetPwmDutyCycle(0.0f);
            HAL_TIM_PWM_Stop(&htim3, TIM_CHANNEL_1);
            HAL_GPIO_WritePin(FAN_CTRL_GPIO_Port, FAN_CTRL_Pin, GPIO_PIN_RESET);
            manualActive = 0;
        }
        return 1u;
    }

    if (!manualActive)
    {
        /* same preparation as the startup check: heating direction, PWM at 0 % */
        driverDirection = PID_DIRECTION_HEATING;
        SetRelayHeating();
        BusyWaitMs(RELAY_ACTUATION_MS);
        ReleaseRelayCoils();
        HAL_GPIO_WritePin(PID_HEATING_GPIO_Port, PID_HEATING_Pin, GPIO_PIN_RESET);
        dutyCycleLimit = DUTY_CYCLE_MAX;
        dutyCycle = 0.0f;
        SetPwmDutyCycle(0.0f);
        HAL_TIM_PWM_Start(&htim3, TIM_CHANNEL_1);
        CurrentSensor_CalibrateZero();             /* PWM at 0 %: zero-current baseline */
        HAL_GPIO_WritePin(FAN_CTRL_GPIO_Port, FAN_CTRL_Pin, GPIO_PIN_SET);
        driverLastTick = HAL_GetTick();
        manualActive = 1;
    }

    dutyCycle = percent / PERCENT_PER_UNIT;
    if (dutyCycle > DUTY_CYCLE_MAX)
        dutyCycle = DUTY_CYCLE_MAX;
    SetPwmDutyCycle(dutyCycle);
    return 1u;
}

uint8_t PidControl_IsManual(void)
{
    return manualActive;
}

void PidControl_Stop(void)
{
    if (manualActive)
        (void)PidControl_SetManualDuty(0.0f);       /* also ends the manual test */
    stopRequested = 1;
}

uint8_t PidControl_IsRunning(void)
{
    return (driverState == DRIVER_STATE_ON) ? 1u : 0u;
}

void PidControl_ClearError(void)
{
    if (driverState == DRIVER_STATE_ERROR)
        driverState = DRIVER_STATE_OFF;
    if (pidState == PID_STATE_ERROR)
        pidState = PID_STATE_OFF;
    lastError = PID_ERROR_NONE;
}

uint8_t PidControl_IsError(void)
{
    return (driverState == DRIVER_STATE_ERROR || pidState == PID_STATE_ERROR) ? 1u : 0u;
}

PidControl_Error_t PidControl_GetErrorCode(void)
{
    return lastError;
}

void PidControl_SetSetpoint(float tSetDegC)
{
    /* Limited to the measuring range of the PT1000 front-end */
    if (tSetDegC < PID_TSET_MIN_DEGC) tSetDegC = PID_TSET_MIN_DEGC;
    if (tSetDegC > PID_TSET_MAX_DEGC) tSetDegC = PID_TSET_MAX_DEGC;
    T_SET = tSetDegC;
    tempUpdatedFlag = 1;

    /* New setpoint: recalibrate the temperature front-end (drift since the last
     * calibration) and arm the "setpoint reached" recalibration again. */
    reachedCount = 0;
    reachedRecalDone = 0;
    if (TempSensor_GetSource() == TEMP_SOURCE_INTERNAL)
        TempSensor_Recalibrate();
}

float PidControl_GetSetpoint(void) { return T_SET; }

void PidControl_SetGains(float newKp, float newKi, float newKd)
{
    kp = newKp;
    ki = newKi;
    kd = newKd;
}

void PidControl_GetGains(float *outKp, float *outKi, float *outKd)
{
    if (outKp) *outKp = kp;
    if (outKi) *outKi = ki;
    if (outKd) *outKd = kd;
}

uint8_t PidControl_SetCurrentLimit(float limitA)
{
    /* Only while the driver is not running: dutyCycleLimit is calibrated for the
     * limit at start (RunStartupCalibration), a change during operation would
     * either trip the overcurrent check or not be reachable. */
    if (driverState == DRIVER_STATE_ON)
        return 0u;

    if (limitA < PID_I_LIMIT_MIN_A) limitA = PID_I_LIMIT_MIN_A;
    if (limitA > PID_I_LIMIT_MAX_A) limitA = PID_I_LIMIT_MAX_A;
    currentLimit = limitA;
    return 1u;
}

float PidControl_GetCurrentLimit(void) { return currentLimit; }

float PidControl_GetControllerOutput(void) { return pidOut; }
float PidControl_GetMeasuredCurrent(void) { return measuredCurrent; }
float PidControl_GetDutyCycle(void) { return dutyCycle; }

PidControl_Direction_t PidControl_GetDirection(void)
{
    return driverDirection;
}
