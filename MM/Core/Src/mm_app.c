/**
 ******************************************************************************
 * @file    mm_app.c
 * @brief   See mm_app.h.
 ******************************************************************************
 */
#include "mm_app.h"
#include "mm_config.h"
#include "boards.h"
#include "eis_sequencer.h"
#include "host_comm.h"

#define LED_HALF_PERIOD_IDLE_MS   500u   /* 1 Hz */
#define LED_HALF_PERIOD_EIS_MS    100u   /* 5 Hz */

static void UpdateLed(void)
{
    const uint32_t half = EisSeq_IsBusy() ? LED_HALF_PERIOD_EIS_MS : LED_HALF_PERIOD_IDLE_MS;
    HAL_GPIO_WritePin(LD2_GPIO_Port, LD2_Pin,
                      (((HAL_GetTick() / half) & 1u) != 0u) ? GPIO_PIN_SET : GPIO_PIN_RESET);
}

void MmApp_Init(void)
{
    MmConfig_Load();
    Boards_Init();
    EisSeq_Init();
    HostComm_Init();
}

void MmApp_Process(void)
{
    HostComm_Process();
    Boards_Process();
    EisSeq_Process();
    UpdateLed();
}
