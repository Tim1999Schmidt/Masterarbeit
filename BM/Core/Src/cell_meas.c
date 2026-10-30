/**
 ******************************************************************************
 * @file    cell_meas.c
 * @brief   See cell_meas.h.
 ******************************************************************************
 */
#include "cell_meas.h"
#include "adc_reader.h"
#include "bm_config.h"
#include "bm_io.h"
#include "eis.h"
#include "main.h"

#ifdef HAL_IWDG_MODULE_ENABLED
extern IWDG_HandleTypeDef hiwdg;          /* main.c; refreshed during the blocking zero calibration */
#endif

#define MEAS_INTERVAL_MS        100u
#define BOOT_ZERO_DELAY_MS     1000u     /* automatic current zero calibration this long after reset:
                                          * hall sensor, INA332 and VDDA measurement have settled */
#define VDDA_EVERY_N              10u     /* VDDA every 10th cycle = 1 s */
#define OVERSAMPLE                16u     /* conversions per voltage / current reading */
#define CAL_OVERSAMPLE            64u     /* conversions per calibration reading */
#define CAL_READINGS              20u     /* readings averaged for a calibration (current zero, voltage) */
#define CAL_READING_INTERVAL_MS   50u     /* spacing: 20 x 50 ms = 1 s, also averages slow noise */
#define PPM_PER_UNIT          1.0e6f
#define VREFINT_OVERSAMPLE         8u     /* conversions per VDDA measurement */
#define VREFINT_DUMMY_READS        2u     /* VREFINT buffer start-up after the channel switch */
#define VREFINT_MIN_COUNTS      100.0f    /* below: VREFINT reading implausible, keep the old VDDA */
#define VDDA_NOMINAL_MV        3300.0f    /* until the first VDDA measurement */
#define ADC_FULL_SCALE         4095.0f
#define SAT_LOW_COUNTS            5.0f    /* current reading this close to an ADC rail = saturated */
#define SAT_HIGH_COUNTS        4090.0f
#define MA_PER_A               1000.0f

#define R_DIV_TOP_OHM         39000.0f    /* R33 */
#define R_DIV_BOTTOM_OHM      68000.0f    /* R34 */
#define U_DIVIDER     ((R_DIV_TOP_OHM + R_DIV_BOTTOM_OHM) / R_DIV_BOTTOM_OHM)
#define HALL_MV_PER_A         120.0f      /* CZ-3A01 */
#define I_AMP_GAIN              5.0f      /* INA332 */
#define I_MV_PER_A        (HALL_MV_PER_A * I_AMP_GAIN)   /* 600 mV/A at the ADC */

static uint32_t lastTick;
static uint8_t  cycle;
static float    vddaMv = VDDA_NOMINAL_MV;
static int32_t  voltageMv;
static int32_t  currentMa;
static uint8_t  currentSat;
static uint8_t  bootZeroDone;     /* automatic zero calibration after reset done */

/* Mean of n conversions without the highest and lowest one. */
static float ReadCounts(uint32_t channel, uint32_t n)
{
    uint32_t sum = 0u, minV = UINT32_MAX, maxV = 0u, i;
    for (i = 0u; i < n; i++)
    {
        const uint32_t v = AdcReader_ReadBlocking(channel);
        sum += v;
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
    }
    return (float)(sum - minV - maxV) / (float)(n - 2u);
}

static void MeasureVdda(void)
{
    float c;
    uint8_t i;
    for (i = 0u; i < VREFINT_DUMMY_READS; i++)
        (void)AdcReader_ReadBlocking(ADC_READER_CH_VREFINT);
    c = ReadCounts(ADC_READER_CH_VREFINT, VREFINT_OVERSAMPLE);
    if (c > VREFINT_MIN_COUNTS)
        vddaMv = (float)(*VREFINT_CAL_ADDR) * (float)VREFINT_CAL_VREF / c;
}

static float CountsToMv(float counts)
{
    return counts * vddaMv / ADC_FULL_SCALE;
}

/* gain correction of the voltage path (divider tolerance), from bm_config */
static float VoltageGain(void)
{
    return 1.0f + (float)BmConfig_Get()->uCorrPpm / PPM_PER_UNIT;
}

/* Blocking for CAL_READINGS * CAL_READING_INTERVAL_MS (1 s): the readings are
 * spread over time so that low-frequency noise averages out as well, not only
 * the noise within one ADC burst. */
static float ReadCalibrationCounts(uint32_t channel)
{
    float sum = 0.0f;
    uint8_t i;
    for (i = 0u; i < CAL_READINGS; i++)
    {
        sum += ReadCounts(channel, CAL_OVERSAMPLE);
        HAL_Delay(CAL_READING_INTERVAL_MS);
#ifdef HAL_IWDG_MODULE_ENABLED
        (void)HAL_IWDG_Refresh(&hiwdg);
#endif
    }
    return sum / (float)CAL_READINGS;
}

static float ZeroMv(void)
{
    return (float)BmConfig_Get()->iZeroMv;      /* 1650 mV until a zero calibration is stored */
}

void CellMeas_Init(void)
{
    MeasureVdda();
    lastTick = HAL_GetTick();
    cycle = 0u;
}

void CellMeas_Process(void)
{
    float cU, cI, mv;

    if ((HAL_GetTick() - lastTick) < MEAS_INTERVAL_MS)
        return;
    lastTick = HAL_GetTick();

    /* Automatic current zero calibration once after reset (RAM only, like the
     * I2C control bit): CONNECT_Z is off after reset and no sweep runs, so no
     * current can flow through the hall sensor. An implausible reading keeps
     * the stored value (see CellMeas_ZeroCurrent()). */
    if (!bootZeroDone && HAL_GetTick() >= BOOT_ZERO_DELAY_MS)
    {
        bootZeroDone = 1u;
        if (!BmIo_GetConnectZ() && !EIS_IsBusy())
            (void)CellMeas_ZeroCurrent();
    }

    if (++cycle >= VDDA_EVERY_N)
    {
        cycle = 0u;
        MeasureVdda();
    }

    cU = ReadCounts(ADC_READER_CH_VOLTAGE, OVERSAMPLE);
    mv = CountsToMv(cU) * U_DIVIDER * VoltageGain();
    voltageMv = (int32_t)(mv + 0.5f);

    cI = ReadCounts(ADC_READER_CH_CURRENT, OVERSAMPLE);
    mv = (CountsToMv(cI) - ZeroMv()) * MA_PER_A / I_MV_PER_A;
    currentMa = (int32_t)((mv >= 0.0f) ? (mv + 0.5f) : (mv - 0.5f));
    currentSat = (cI < SAT_LOW_COUNTS || cI > SAT_HIGH_COUNTS) ? 1u : 0u;
}

int32_t  CellMeas_GetVoltageMv(void)       { return voltageMv; }
int32_t  CellMeas_GetCurrentMa(void)       { return currentMa; }
uint32_t CellMeas_GetVddaMv(void)          { return (uint32_t)(vddaMv + 0.5f); }
uint8_t  CellMeas_IsCurrentSaturated(void) { return currentSat; }

/* Blocking for 1 s (see ReadCalibrationCounts()). */
int32_t CellMeas_ZeroCurrent(void)
{
    const int32_t z = (int32_t)(CountsToMv(ReadCalibrationCounts(ADC_READER_CH_CURRENT)) + 0.5f);
    if (z >= BM_I_ZERO_MIN_MV && z <= BM_I_ZERO_MAX_MV)   /* implausible (current flowing?): keep the old value */
        BmConfig_Get()->iZeroMv = (int16_t)z;
    return z;
}
/* Blocking for 1 s (see ReadCalibrationCounts()). */
uint8_t CellMeas_CalibrateVoltage(int32_t refMv)
{
    const float rawMv = CountsToMv(ReadCalibrationCounts(ADC_READER_CH_VOLTAGE)) * U_DIVIDER;
    float corr;

    if (refMv < BM_U_CAL_MIN_MV || refMv > BM_U_CAL_MAX_MV || rawMv <= 0.0f)
        return 0u;
    corr = ((float)refMv / rawMv - 1.0f) * PPM_PER_UNIT;
    if (corr > (float)BM_U_CORR_MAX_PPM || corr < -(float)BM_U_CORR_MAX_PPM)
        return 0u;                                  /* too large for a divider tolerance: keep the old value */
    BmConfig_Get()->uCorrPpm = (int16_t)((corr >= 0.0f) ? (corr + 0.5f) : (corr - 0.5f));
    return 1u;
}
