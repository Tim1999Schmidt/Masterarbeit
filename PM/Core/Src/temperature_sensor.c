/**
 ******************************************************************************
 * @file    temperature_sensor.c
 * @brief   See temperature_sensor.h.
 *
 * Note on the measuring range: the front-end maps ~ -5 degC -> 0 V and ~54 degC
 * -> 3.3 V. Outside that the output saturates (and a broken PT1000 lead makes
 * the constant-current source drive the output to the top rail, i.e. it looks
 * like "54 degC"). Such readings are flagged by a
 * plausibility check on the raw counts (TEMP_FAULT_LOW/HIGH_COUNTS), reported
 * through TempSensor_GetFault(), and make the PID controller stop with an error.
 ******************************************************************************
 */
#include "temperature_sensor.h"
#include "adc_reader.h"
#include <stddef.h>

/* ---- Front-end description (PM board) ---------------------------------- */
#define ADC_MAX_COUNTS            4095.0f
#define R_CAL_LOW_OHM             1000.0f   /* CH3 / SEL3: bottom-of-range reference resistor */
#define R_CAL_HIGH_OHM            1200.0f   /* CH2 / SEL2: top-of-range reference resistor    */
#define R_PT1000_AT_0C            1000.0f

/* Nominal analog front-end (see temperature_sensor.h). Only used for the
 * counts -> resistance mapping until the first calibration has succeeded;
 * afterwards the 2-point calibration replaces all of these values. */
#define FE_I_SOURCE_A             100.0e-6f   /* constant-current source (tolerance ~ +-1 %) */
#define FE_VREF_V                   0.098f    /* reference potential of the bridge (tolerance ~ +-0.3 mV) */
#define FE_GAIN                   142.2f      /* op-amp gain (nominal) */
#define FE_VDDA_V                   3.3f      /* ADC reference (full scale) */
#define FE_NOMINAL_COUNTS(r)      ((((r) * FE_I_SOURCE_A) - FE_VREF_V) * FE_GAIN / FE_VDDA_V * ADC_MAX_COUNTS)

/* ---- Tunables ----------------------------------------------------------- */
#define TEMP_SAMPLE_INTERVAL_MS   100u     /* fixed measurement interval (same as the PID cycle) */
/* Moving average of the PT1000 readings (one per TEMP_SAMPLE_INTERVAL_MS):
 * 10 readings = 1 s. Averages the measurement noise; the delay (~0.5 s) is
 * small against the ~15-20 s lag of the thermal path. The averaged value is
 * kept in ADC counts, so a new calibration applies to it at once. */
#define TEMP_AVG_SAMPLES             10u

#define TEMP_RELAY_HOLDOFF_MS     150u     /* no ADC reading this long after a relay pulse: the coil pulse
                                            * (50 ms) loads +5VA, which also supplies the front-end */
#define TEMP_OVERSAMPLE            16u     /* ADC conversions averaged per reading (one short burst) */
#define CAL_OVERSAMPLE             64u     /* ADC conversions averaged per calibration resistor      */
#define CAL_MIN_SPAN_COUNTS      1000.0f   /* plausibility: counts(1.2k) - counts(1k) must be at least this (nominal ~3530) */

/* PT1000 plausibility: a reading this close to either ADC rail means the
 * front-end is saturated (temperature outside ~-5..54 degC) or the sensor lead is
 * broken / shorted. Must be seen on TEMP_FAULT_DEBOUNCE consecutive readings
 * (= 300 ms) before it counts as a fault, so a single noisy reading does not stop the controller. */
#define TEMP_FAULT_LOW_COUNTS       5.0f
#define TEMP_FAULT_HIGH_COUNTS   4090.0f
#define TEMP_FAULT_DEBOUNCE         3u

/* External temperature (T_EXT via I2C): the value is only trusted if the master
 * has written it within this time. Adjust to the master's actual update rate
 * (with some margin). */
#define EXT_TEMP_TIMEOUT_MS      2000u

/* ReadAveragedCounts() drops the highest and the lowest sample, so it needs at least 3.
 * (Preprocessor check instead of C11 _Static_assert: the CubeIDE editor's parser flags
 * _Static_assert as a syntax error, while gcc accepts both.) */
#if (TEMP_OVERSAMPLE < 3u) || (CAL_OVERSAMPLE < 3u)
#error "TEMP_OVERSAMPLE and CAL_OVERSAMPLE must be at least 3 (ReadAveragedCounts drops min and max)"
#endif

/* Piecewise-linear resistance/temperature table, carried over verbatim from
 * temperature_driver_sw (values calculated from the datasheet formula for
 * NB-PTCO-164 PTFC102A1A0; these are samples of the standard PT1000 curve,
 * IEC 60751). Against that formula the table stays within ~0.007 K over
 * the measuring range (checked) - far below one ADC step (~0.015 K). */
#define PWL_SIZE 10u
static const float pwlResistanceOhm[PWL_SIZE] = { 900.0f, 950.0f, 1000.0f, 1050.0f, 1100.0f, 1150.0f, 1200.0f, 1250.0f, 1300.0f, 1350.0f };
static const float pwlTemperatureC[PWL_SIZE]  = { -25.488f, -12.7685f, 0.0f, 12.818f, 25.6845f, 38.6005f, 51.5665f, 64.583f, 77.651f, 90.7705f };
static float pwlSlope[PWL_SIZE - 1u];   /* degC per Ohm of each table segment */
static const float linpolSlopeFallback = 0.2593035671f; /* used only outside the table (-25..91 degC), where the front-end cannot measure anyway */

/* ---- SEL multiplexer ---------------------------------------------------- */
typedef enum
{
    MUX_PT1000 = 0,   /* CH1 / SEL1 */
    MUX_CAL_HIGH,     /* CH2 / SEL2, 1.20 kOhm */
    MUX_CAL_LOW       /* CH3 / SEL3, 1.00 kOhm */
} MuxChannel_t;

static void SelectChannel(MuxChannel_t channel)
{
    /* Break-before-make: switch everything off first, so two resistors are
     * never connected to the current source at the same time. */
    HAL_GPIO_WritePin(SEL1_GPIO_Port, SEL1_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(SEL2_GPIO_Port, SEL2_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(SEL3_GPIO_Port, SEL3_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(SEL4_GPIO_Port, SEL4_Pin, GPIO_PIN_RESET); /* unused on this board revision */

    switch (channel)
    {
    case MUX_PT1000:   HAL_GPIO_WritePin(SEL1_GPIO_Port, SEL1_Pin, GPIO_PIN_SET); break;
    case MUX_CAL_HIGH: HAL_GPIO_WritePin(SEL2_GPIO_Port, SEL2_Pin, GPIO_PIN_SET); break;
    case MUX_CAL_LOW:  HAL_GPIO_WritePin(SEL3_GPIO_Port, SEL3_Pin, GPIO_PIN_SET); break;
    default: break;
    }
}

/* Mean of n consecutive ADC conversions of the TEMP channel. The single
 * highest and lowest value are dropped as outliers (same idea as in
 * current_sensor.c). */
static float ReadAveragedCounts(uint32_t n)
{
    uint32_t sum  = 0u;
    uint32_t minV = UINT32_MAX;
    uint32_t maxV = 0u;
    uint32_t i;

    for (i = 0u; i < n; i++)
    {
        const uint32_t v = AdcReader_ReadBlocking(ADC_READER_CH_TEMP);
        sum += v;
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
    }

    return (float)(sum - minV - maxV) / (float)(n - 2u);
}

/* ---- State ---------------------------------------------------------------- */
typedef enum
{
    TS_CAL_MEASURE_LOW = 0, /* 1.00 kOhm reference is connected: measure it, connect the 1.20 kOhm one */
    TS_CAL_MEASURE_HIGH,    /* 1.20 kOhm reference is connected: measure it, calibrate, connect the PT1000 */
    TS_RUN                  /* normal operation: PT1000 only */
} TempState_t;

static TempState_t state    = TS_CAL_MEASURE_LOW;
static uint32_t    lastTick = 0u;

static uint8_t recalRequested   = 0u;
static uint8_t calibrationOk    = 0u;   /* result of the last COMPLETED calibration (not cleared while a new one runs) */
static uint8_t measurementValid = 0u;   /* a PT1000 value exists (held during a recalibration) */
static float   lastPtCounts     = 0.0f; /* raw counts of the last PT1000 reading */
static float   calShiftC        = 0.0f; /* temperature step caused by recalibrations, not yet consumed by the PID */
static uint8_t newSample        = 0u;   /* set on every PT1000 reading (100 ms clock), consumed by the PID */

static uint8_t pt1000FaultCount = 0u;
static uint8_t pt1000Fault      = 0u;

/* Raw counts measured on the two calibration resistors (diagnostics). */
static float calCountsLow  = 0.0f;
static float calCountsHigh = 0.0f;

/* Moving average of the PT1000 counts */
static float   ptCountsHistory[TEMP_AVG_SAMPLES];
static uint8_t ptHistoryIndex = 0u;
static uint8_t ptHistoryCount = 0u;   /* valid entries (0 after reset) */

/* Relay switch hold-off (see TempSensor_RelaySwitched()). */
static uint8_t  relayHoldoff      = 0u;
static uint32_t relayHoldoffStart = 0u;

/* Active counts -> resistance mapping: two known points on a straight line. */
static float mapCountsLow   = 0.0f;   /* set to the nominal front-end in TempSensor_Init() */
static float mapResLow      = R_CAL_LOW_OHM;
static float mapOhmPerCount = 0.0f;

static float resistanceOhm    = R_PT1000_AT_0C;
static float temperatureRawC  = 0.0f;
static float temperatureC     = 0.0f;
static float trimOffsetC      = 0.0f;
static float trimSlope        = 0.0f;

static TempSensor_Source_t controlSource = TEMP_SOURCE_INTERNAL;
static float externalTemperatureC = 0.0f;
static uint8_t  externalValid     = 0u;   /* 1 once the master has written T_EXT at least once */
static uint32_t externalLastTick  = 0u;   /* HAL_GetTick() of the last T_EXT write */

static void SetMapping(float countsLow, float countsHigh, float resLowOhm, float resHighOhm)
{
    mapCountsLow   = countsLow;
    mapResLow      = resLowOhm;
    mapOhmPerCount = (resHighOhm - resLowOhm) / (countsHigh - countsLow);
}

static float ResistanceToTemperature(float resistanceOhmValue)
{
    uint8_t i = 0;

    while (i < PWL_SIZE && resistanceOhmValue > pwlResistanceOhm[i])
        i++;

    if (i > 0 && i < PWL_SIZE)
    {
        i--;
        /* PWL interpolation: T(R) = Tlower + (R - Rlower) * slope, see AN0970 (Analog Devices) */
        return pwlTemperatureC[i] + (resistanceOhmValue - pwlResistanceOhm[i]) * pwlSlope[i];
    }

    /* Outside the characterised range: fall back to a simple linear approximation around 0 degC */
    return (resistanceOhmValue - R_PT1000_AT_0C) * linpolSlopeFallback;
}

/* counts -> resistance -> temperature (+ trim) with the active mapping */
static float CountsToResistance(float counts)
{
    return mapResLow + (counts - mapCountsLow) * mapOhmPerCount;
}

static float ResistanceToTrimmedTemperature(float resistanceOhmValue, float *rawOut)
{
    const float raw = ResistanceToTemperature(resistanceOhmValue);
    if (rawOut) *rawOut = raw;
    return raw - trimOffsetC - (raw * trimSlope);
}

/* Connects the 1.00 kOhm reference; the state machine takes it from there.
 * The last PT1000 value (and the result of the previous calibration) stay
 * valid meanwhile, so a recalibration during regulation only pauses the
 * measurement for ~300 ms (the PID controller holds its output for that time). */
static void BeginCalibration(void)
{
    pt1000FaultCount = 0u;
    pt1000Fault      = 0u;
    SelectChannel(MUX_CAL_LOW);
    state = TS_CAL_MEASURE_LOW;
}

static void FinishCalibration(void)
{
    /* Both references must lie inside the ADC range (a reading at a rail means the
     * front-end saturates there - the calibration would then be silently wrong)
     * and be far enough apart. */
    if (((calCountsHigh - calCountsLow) >= CAL_MIN_SPAN_COUNTS) &&
        (calCountsLow  > TEMP_FAULT_LOW_COUNTS)  && (calCountsLow  < TEMP_FAULT_HIGH_COUNTS) &&
        (calCountsHigh > TEMP_FAULT_LOW_COUNTS)  && (calCountsHigh < TEMP_FAULT_HIGH_COUNTS))
    {
        /* How much does the new calibration move the temperature? Evaluated on the
         * last PT1000 reading with the old and the new mapping, so it contains
         * only the calibration effect, not a real temperature change. The PID
         * controller uses it to shift its error history (no derivative kick). */
        const float tOld = ResistanceToTrimmedTemperature(CountsToResistance(lastPtCounts), NULL);
        SetMapping(calCountsLow, calCountsHigh, R_CAL_LOW_OHM, R_CAL_HIGH_OHM);
        if (measurementValid && (controlSource == TEMP_SOURCE_INTERNAL))
            calShiftC += ResistanceToTrimmedTemperature(CountsToResistance(lastPtCounts), NULL) - tOld;
        calibrationOk = 1u;
    }
    else
    {
        /* Reference readings implausible (resistors not connected / SEL lines not
         * wired / front-end dead or saturated): keep the previous mapping, but do
         * not report ready - reported as TEMP_FAULT_CALIBRATION, which stops a
         * running controller. */
        calibrationOk = 0u;
    }
}

/* One PT1000 reading: counts -> resistance -> temperature (+ trim). */
static void MeasurePt1000(void)
{
    float sum = 0.0f;
    uint8_t i;
    const float raw = ReadAveragedCounts(TEMP_OVERSAMPLE);

    if (ptHistoryCount == 0u)
    {
        /* first reading: fill the whole window, no ramp from 0 */
        for (i = 0u; i < TEMP_AVG_SAMPLES; i++)
            ptCountsHistory[i] = raw;
        ptHistoryCount = TEMP_AVG_SAMPLES;
    }
    ptCountsHistory[ptHistoryIndex] = raw;
    ptHistoryIndex = (uint8_t)((ptHistoryIndex + 1u) % TEMP_AVG_SAMPLES);
    for (i = 0u; i < TEMP_AVG_SAMPLES; i++)
        sum += ptCountsHistory[i];

    lastPtCounts    = sum / (float)TEMP_AVG_SAMPLES;
    resistanceOhm   = CountsToResistance(lastPtCounts);
    temperatureC    = ResistanceToTrimmedTemperature(resistanceOhm, &temperatureRawC);
    measurementValid = 1u;
    newSample        = 1u;

    /* Plausibility check on the raw counts (see file header) */
    if ((raw < TEMP_FAULT_LOW_COUNTS) || (raw > TEMP_FAULT_HIGH_COUNTS))
    {
        if (pt1000FaultCount < TEMP_FAULT_DEBOUNCE)
            pt1000FaultCount++;
        if (pt1000FaultCount >= TEMP_FAULT_DEBOUNCE)
            pt1000Fault = 1u;
    }
    else
    {
        pt1000FaultCount = 0u;
        pt1000Fault      = 0u;
    }
}

/* ---- Public API ---------------------------------------------------------- */
void TempSensor_Init(void)
{
    uint8_t i;

    /* Precalculate the PWL segment slopes */
    for (i = 0; i < PWL_SIZE - 1u; i++)
        pwlSlope[i] = (pwlTemperatureC[i + 1] - pwlTemperatureC[i]) / (pwlResistanceOhm[i + 1] - pwlResistanceOhm[i]);

    SetMapping(FE_NOMINAL_COUNTS(R_CAL_LOW_OHM), FE_NOMINAL_COUNTS(R_CAL_HIGH_OHM), R_CAL_LOW_OHM, R_CAL_HIGH_OHM);
    recalRequested = 0u;

    BeginCalibration();          /* calibrate first, then measure */
    lastTick = HAL_GetTick();
}

void TempSensor_Process(void)
{
    const uint32_t now = HAL_GetTick();

    if (relayHoldoff)
    {
        if ((now - relayHoldoffStart) < TEMP_RELAY_HOLDOFF_MS)
            return;
        relayHoldoff = 0u;
    }
    if ((now - lastTick) < TEMP_SAMPLE_INTERVAL_MS)
        return;
    lastTick = now;

    switch (state)
    {
    case TS_CAL_MEASURE_LOW:
        calCountsLow = ReadAveragedCounts(CAL_OVERSAMPLE);
        SelectChannel(MUX_CAL_HIGH);
        state = TS_CAL_MEASURE_HIGH;
        break;

    case TS_CAL_MEASURE_HIGH:
        calCountsHigh = ReadAveragedCounts(CAL_OVERSAMPLE);
        FinishCalibration();
        SelectChannel(MUX_PT1000);
        state = TS_RUN;
        break;

    case TS_RUN:
        if (recalRequested)
        {
            recalRequested = 0u;
            BeginCalibration();
        }
        else
        {
            MeasurePt1000();
        }
        break;

    default:
        BeginCalibration();
        break;
    }
}

void TempSensor_Recalibrate(void)
{
    recalRequested = 1u;
}

uint8_t TempSensor_IsCalibrating(void)
{
    return (recalRequested || state != TS_RUN) ? 1u : 0u;
}

void TempSensor_RelaySwitched(void)
{
    relayHoldoff      = 1u;
    relayHoldoffStart = HAL_GetTick();
}

uint8_t TempSensor_IsReady(void)
{
    if (controlSource == TEMP_SOURCE_EXTERNAL)
        return (TempSensor_GetFault() == TEMP_FAULT_NONE) ? 1u : 0u;

    return (calibrationOk && measurementValid && !pt1000Fault) ? 1u : 0u;
}

TempSensor_Fault_t TempSensor_GetFault(void)
{
    if (controlSource == TEMP_SOURCE_EXTERNAL)
    {
        if (!externalValid || ((HAL_GetTick() - externalLastTick) > EXT_TEMP_TIMEOUT_MS))
            return TEMP_FAULT_EXT_TIMEOUT;
        return TEMP_FAULT_NONE;
    }

    if (pt1000Fault)
        return TEMP_FAULT_PT1000_RANGE;

    /* last calibration failed (and no new one is pending / running) */
    if ((state == TS_RUN) && !recalRequested && !calibrationOk)
        return TEMP_FAULT_CALIBRATION;

    return TEMP_FAULT_NONE;
}

float TempSensor_ConsumeCalibrationShift(void)
{
    const float shift = calShiftC;
    calShiftC = 0.0f;
    return shift;
}

uint8_t TempSensor_ConsumeNewSample(void)
{
    const uint8_t flag = newSample;
    newSample = 0u;
    return flag;
}

float TempSensor_GetTemperature(void)
{
    return temperatureC;
}

float TempSensor_GetResistance(void)
{
    return resistanceOhm;
}

float TempSensor_GetControlTemperature(void)
{
    return (controlSource == TEMP_SOURCE_EXTERNAL) ? externalTemperatureC : temperatureC;
}

void TempSensor_SetSource(TempSensor_Source_t source)
{
    controlSource = source;
}

TempSensor_Source_t TempSensor_GetSource(void)
{
    return controlSource;
}

void TempSensor_SetExternalTemperature(float tempDegC)
{
    externalTemperatureC = tempDegC;
    externalLastTick     = HAL_GetTick();
    externalValid        = 1u;
}

void TempSensor_SetTrim(float offsetDegC, float slope)
{
    trimOffsetC = offsetDegC;
    trimSlope   = slope;
}

uint16_t TempSensor_GetCalCountsLow(void)
{
    return (uint16_t)(calCountsLow + 0.5f);
}

uint16_t TempSensor_GetCalCountsHigh(void)
{
    return (uint16_t)(calCountsHigh + 0.5f);
}
