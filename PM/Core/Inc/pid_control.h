/**
 ******************************************************************************
 * @file    pid_control.h
 * @brief   PID temperature control loop plus its actuation stage (bistable
 *          relay direction switching, PWM duty cycle, startup short-circuit
 *          check, continuous overcurrent protection with duty-cycle
 *          recalibration).
 *
 * The actuation/driver logic is kept together with the PID loop rather than
 * split into its own file: it is the direct, tightly-coupled consumer of the
 * PID output (turns pidOut [A] into a relay direction + PWM duty cycle), so
 * this matches the requested split into current measurement / temperature
 * measurement / PID control.
 *
 * Ported from temperature_driver_sw's pidStateMachine()/driverStateMachine().
 * The Ziegler-Nichols autotuning routine (tuningStateMachine()) was dropped
 * entirely per request. All timing that used to run off dedicated hardware
 * timers (htim1 for the PID cycle, htim3 as a free-running 0.1ms driver
 * timebase) now uses HAL_GetTick() instead, since the PM board's only timer
 * (TIM3) is committed to the PWM output. The one-time startup calibration
 * sequence still runs as a short (~100-150 ms) blocking sequence, exactly
 * like the original - this is fine because I2C slave handling runs on
 * interrupts (see i2c_comm.c) and keeps responding even while this runs.
 *
 * Uses float (not double): the STM32C051 (Cortex-M0+) has no FPU
 * (-mfloat-abi=soft), so every floating-point op is software-emulated, and
 * the 64-bit routines for double are considerably larger than the 32-bit
 * ones for float.
 ******************************************************************************
 */
#ifndef PID_CONTROL_H
#define PID_CONTROL_H

#include "main.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum
{
    PID_ERROR_NONE = 0,
    PID_ERROR_STARTUP_OVERCURRENT = 1, /* short-circuit-like current already at the initial test duty cycle */
    PID_ERROR_RUNTIME_OVERCURRENT = 2, /* current exceeded the configured limit during normal operation */
    PID_ERROR_SANITY = 3,              /* temperature error grew implausibly (reversed polarity / instability) */
    PID_ERROR_TEMP_SENSOR = 4,         /* PT1000 reading implausible (outside ~-5..54 degC, broken/shorted lead) */
    PID_ERROR_EXT_TEMP_TIMEOUT = 5,    /* external temperature source: T_EXT not refreshed by the master in time */
    PID_ERROR_OPEN_LOAD = 6,           /* startup: (almost) no current at the test duty cycle - Peltier not connected */
    PID_ERROR_TEMP_CALIBRATION = 7     /* recalibration of the temperature front-end failed (references implausible / saturated) */
} PidControl_Error_t;

/* Allowed ranges of the settable values (out-of-range values are clamped). */
#define PID_TSET_MIN_DEGC     0.0f   /* inside the measuring range of the PT1000 front-end (~-5..54 degC) */
#define PID_TSET_MAX_DEGC    50.0f
#define PID_I_LIMIT_MIN_A     0.5f
#define PID_I_LIMIT_MAX_A     3.0f   /* permissible for the Peltier element even at the full 24 V output;
                                      * measuring range ~8.25 A (2 mOhm x 200), limit + 0.5 A trip margin stays well below it */

typedef enum
{
    PID_DIRECTION_HEATING = 0,
    PID_DIRECTION_COOLING = 1
} PidControl_Direction_t;

/* One-time setup. Call once from main() before the main loop. */
/* Starts TIM3 with an inverted output at 0 % (PA6 permanently high = output
 * stage off, see pid_control.c). Call in USER CODE "TIM3_Init 2" of main.c,
 * i.e. before HAL_TIM_MspPostInit() switches PA6 to the timer. */
void PidControl_PwmOutputInit(void);

void PidControl_Init(void);

/* Cooperative, non-blocking step (aside from the one-time startup
 * calibration triggered by PidControl_Start(), see above). Call once per
 * main loop iteration; internally drives both the PID loop and the
 * actuation stage, same as the original's pidStateMachine() +
 * driverStateMachine() pair. */
void PidControl_Process(void);

/* Requests the controller to start / stop regulating. Start triggers the
 * short blocking startup calibration described above. A start request is
 * held back until TempSensor_IsReady() (the temperature front-end calibrates
 * itself for ~300 ms after boot) and is cancelled by Stop. */
void PidControl_Start(void);
void PidControl_Stop(void);
uint8_t PidControl_IsRunning(void);

/* Bring-up test (debug console "duty"): fixed duty cycle in percent without
 * regulation, max. 95 %. The sign selects the direction: positive = heating,
 * negative = cooling (a direction change switches the PWM off and flips the
 * relay first). 0 switches the PWM off again.
 * Only accepted while the regulation is off and no error is latched; the
 * current is still supervised (above I_LIMIT + 0.5 A or ADC at full scale ->
 * PWM off, error 2). Returns 1 if accepted. Start is ignored while active. */
uint8_t PidControl_SetManualDuty(float percent);
uint8_t PidControl_IsManual(void);

/* Clears a latched error and returns to the idle (off) state - the I2C
 * equivalent of the original board's ERR_CONFIRM button, which does not
 * exist on the PM board. */
void PidControl_ClearError(void);
uint8_t PidControl_IsError(void);
PidControl_Error_t PidControl_GetErrorCode(void);

/* Setpoint (clamped to PID_TSET_MIN/MAX_DEGC) and gains. A new setpoint also
 * triggers a recalibration of the temperature front-end (internal PT1000 source
 * only); a second one follows once the setpoint is reached (see pid_control.c). */
void PidControl_SetSetpoint(float tSetDegC);
float PidControl_GetSetpoint(void);
void PidControl_SetGains(float kp, float ki, float kd);
void PidControl_GetGains(float *kp, float *ki, float *kd);

/* Symmetric current limit magnitude, in amperes (replaces the original's
 * separate +/- currentLimitP/N now that current is single-ended). Clamped to
 * PID_I_LIMIT_MIN/MAX_A. Only accepted while the driver is not running;
 * returns 1 if applied, 0 if rejected. */
uint8_t PidControl_SetCurrentLimit(float limitA);
float PidControl_GetCurrentLimit(void);

/* Live telemetry. */
float PidControl_GetControllerOutput(void);   /* pidOut, in amperes */
float PidControl_GetMeasuredCurrent(void);    /* most recent current reading, in amperes */
float PidControl_GetDutyCycle(void);          /* 0.0 .. 1.0 */
PidControl_Direction_t PidControl_GetDirection(void);

#ifdef __cplusplus
}
#endif

#endif /* PID_CONTROL_H */
