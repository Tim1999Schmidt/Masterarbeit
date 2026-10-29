/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    i2c.h
  * @brief   This file contains all the function prototypes for
  *          the i2c.c file
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2025 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */
/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __I2C_H__
#define __I2C_H__

#ifdef __cplusplus
extern "C" {
#endif

/* Includes ------------------------------------------------------------------*/
#include "main.h"

/* USER CODE BEGIN Includes */

// ADS1115 Konfiguration
#define ADS1115_SPG_ADDRESS     (0x49 << 1)  // 7-Bit-Adresse << 1 für Spg 0100 1001 = 49
#define ADS1115_STROM_ADDRESS		(0x48 << 1) // 7-Bit-Adresse << 1 für HAL 0100 1000 = 48
#define ADS1115_REG_CONVERSION 0x00
#define ADS1115_REG_CONFIG     0x01


// Funktionsprototypen (die du selbst implementierst)
int16_t ADS1115_ReadSingleEnded_AIN0(void);
void ADS1115_WriteConfig(uint16_t config);
int16_t ADS1115_ReadConversion(void);


// TCA9555 Konfiguration
#define TCA9555_ADDR (0x20 << 1) // I2C-Adresse in 8-Bit-Form

// PCF8574T Konfiguration
#define PCF8574T_Write_ADDR (0x21 << 1) // I2C-Adresse in 8-Bit-Form, 0x21 wird um 1 verschoben zu 0x42

/* USER CODE END Includes */

extern I2C_HandleTypeDef hi2c1;

/* USER CODE BEGIN Private defines */

/* USER CODE END Private defines */

void MX_I2C1_Init(void);

/* USER CODE BEGIN Prototypes */

/* USER CODE END Prototypes */

#ifdef __cplusplus
}
#endif

#endif /* __I2C_H__ */

