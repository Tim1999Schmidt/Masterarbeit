/**
 ******************************************************************************
 * @file    bm_app.c
 * @brief   See bm_app.h.
 ******************************************************************************
 */
#include "bm_app.h"
#include "bm_config.h"
#include "bm_io.h"
#include "cell_meas.h"
#include "temperature_sensor.h"

static App_Error_t latchedError = APP_ERR_NONE;
static uint8_t     wasBusy;
static int32_t     railLimitMa = APP_RAIL_CURRENT_DEFAULT_MA;

void App_Process(void)
{
    const uint8_t busy = EIS_IsBusy();

    /* rail protection in both current directions (see APP_RAIL_CURRENT_DEFAULT_MA) */
    if (BmIo_GetConnectZ())
    {
        const int32_t i = CellMeas_GetCurrentMa();
        if (i >= railLimitMa || i <= -railLimitMa || CellMeas_IsCurrentSaturated())
        {
            BmIo_SetConnectZ(0u);
            EIS_Abort();                       /* a stack sweep cannot go on without the rail */
            latchedError = APP_ERR_OVERCURRENT;
        }
    }

    /* a sweep that ended with a communication or saturation error latches the error */
    if (wasBusy && !busy)
    {
        if (EIS_GetLastResult() == EIS_ERR_COMM)
            latchedError = APP_ERR_EIS_COMM;
        else if (EIS_GetLastResult() == EIS_ERR_ADC_SAT)
            latchedError = APP_ERR_EIS_ADC_SAT;
    }
    wasBusy = busy;
}

App_Error_t App_StartEis(const Eis_Config_t *cfg)
{
    Eis_Result_t r;

    /* cell and stack measurement are allowed with CONNECT_Z = 0 and 1 - the MM
     * decides which cells are on the rail (see bm_app.h) */
    r = EIS_Start(cfg, BmConfig_Get()->numEis);
    if (r == EIS_ERR_BUSY)
        latchedError = APP_ERR_BUSY;
    else if (r != EIS_OK)
        latchedError = APP_ERR_CONFIG;
    else
        return APP_ERR_NONE;
    return latchedError;
}

void App_AbortEis(void)
{
    EIS_Abort();
}

App_Error_t App_SetConnectZ(uint8_t on)
{
    on = on ? 1u : 0u;
    if (on == BmIo_GetConnectZ())
        return APP_ERR_NONE;
    if (on && latchedError == APP_ERR_OVERCURRENT)
        return APP_ERR_OVERCURRENT;            /* stays off until the error is cleared */
    if (EIS_IsBusy())
    {
        latchedError = APP_ERR_BUSY;
        return APP_ERR_BUSY;
    }
    BmIo_SetConnectZ(on);
    return APP_ERR_NONE;
}

void App_ClearError(void)
{
    latchedError = APP_ERR_NONE;
    BmIo_ResetErrq();
}

void App_SetError(App_Error_t e)
{
    latchedError = e;
}

uint8_t App_SetRailCurrentLimit(int32_t ma)
{
    if (ma < APP_RAIL_CURRENT_MIN_MA || ma > APP_RAIL_CURRENT_MAX_MA)
        return 0u;
    railLimitMa = ma;
    return 1u;
}

uint16_t App_GetRailCurrentLimit(void)
{
    return (uint16_t)railLimitMa;
}

App_Error_t App_GetErrorCode(void)
{
    if (latchedError != APP_ERR_NONE)
        return latchedError;
    if (BmIo_IsErrqActive())
        return APP_ERR_ERRQ;
    if (TempSensor_GetFault() != TEMP_FAULT_NONE)
        return APP_ERR_TEMP_SENSOR;
    return APP_ERR_NONE;
}

uint8_t App_GetStatus(void)
{
    return (uint8_t)((EIS_IsBusy()                      ? APP_ST_EIS_BUSY    : 0u) |
                     (EIS_HasResults()                  ? APP_ST_RESULTS     : 0u) |
                     (App_GetErrorCode() != APP_ERR_NONE ? APP_ST_ERROR      : 0u) |
                     (TempSensor_IsReady()              ? APP_ST_TEMP_VALID  : 0u) |
                     (BmIo_GetConnectZ()                ? APP_ST_CONNECT_Z   : 0u) |
                     (BmIo_IsErrqActive()               ? APP_ST_ERRQ        : 0u) |
                     (BmConfig_Get()->numEis >= BM_NUM_EIS_WITH_STACK ? APP_ST_STACK_CHIP : 0u) |
                     (CellMeas_IsCurrentSaturated()     ? APP_ST_I_SATURATED : 0u));
}
