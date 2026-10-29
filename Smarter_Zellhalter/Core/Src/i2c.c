/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    i2c.c
  * @brief   This file provides code for the configuration
  *          of the I2C instances.
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
/* Includes ------------------------------------------------------------------*/
#include "i2c.h"
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>   // für abs()
/* USER CODE BEGIN 0 */

/* USER CODE END 0 */

I2C_HandleTypeDef hi2c1;

/* I2C1 init function */
void MX_I2C1_Init(void)
{

  /* USER CODE BEGIN I2C1_Init 0 */

  /* USER CODE END I2C1_Init 0 */

  /* USER CODE BEGIN I2C1_Init 1 */

  /* USER CODE END I2C1_Init 1 */
  hi2c1.Instance = I2C1;
  hi2c1.Init.Timing = 0x00201D2B;
  hi2c1.Init.OwnAddress1 = 0;
  hi2c1.Init.AddressingMode = I2C_ADDRESSINGMODE_7BIT;
  hi2c1.Init.DualAddressMode = I2C_DUALADDRESS_DISABLE;
  hi2c1.Init.OwnAddress2 = 0;
  hi2c1.Init.OwnAddress2Masks = I2C_OA2_NOMASK;
  hi2c1.Init.GeneralCallMode = I2C_GENERALCALL_DISABLE;
  hi2c1.Init.NoStretchMode = I2C_NOSTRETCH_DISABLE;
  if (HAL_I2C_Init(&hi2c1) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure Analogue filter
  */
  if (HAL_I2CEx_ConfigAnalogFilter(&hi2c1, I2C_ANALOGFILTER_ENABLE) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure Digital filter
  */
  if (HAL_I2CEx_ConfigDigitalFilter(&hi2c1, 0) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN I2C1_Init 2 */

  /* USER CODE END I2C1_Init 2 */

}

void HAL_I2C_MspInit(I2C_HandleTypeDef* i2cHandle)
{

  GPIO_InitTypeDef GPIO_InitStruct = {0};
  if(i2cHandle->Instance==I2C1)
  {
  /* USER CODE BEGIN I2C1_MspInit 0 */

  /* USER CODE END I2C1_MspInit 0 */

    __HAL_RCC_GPIOB_CLK_ENABLE();
    /**I2C1 GPIO Configuration
    PB8     ------> I2C1_SCL
    PB9     ------> I2C1_SDA
    */
    GPIO_InitStruct.Pin = GPIO_PIN_8|GPIO_PIN_9;
    GPIO_InitStruct.Mode = GPIO_MODE_AF_OD;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_HIGH;
    GPIO_InitStruct.Alternate = GPIO_AF4_I2C1;
    HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);

    /* I2C1 clock enable */
    __HAL_RCC_I2C1_CLK_ENABLE();
  /* USER CODE BEGIN I2C1_MspInit 1 */

  /* USER CODE END I2C1_MspInit 1 */
  }
}

void HAL_I2C_MspDeInit(I2C_HandleTypeDef* i2cHandle)
{

  if(i2cHandle->Instance==I2C1)
  {
  /* USER CODE BEGIN I2C1_MspDeInit 0 */

  /* USER CODE END I2C1_MspDeInit 0 */
    /* Peripheral clock disable */
    __HAL_RCC_I2C1_CLK_DISABLE();

    /**I2C1 GPIO Configuration
    PB8     ------> I2C1_SCL
    PB9     ------> I2C1_SDA
    */
    HAL_GPIO_DeInit(GPIOB, GPIO_PIN_8);

    HAL_GPIO_DeInit(GPIOB, GPIO_PIN_9);

  /* USER CODE BEGIN I2C1_MspDeInit 1 */

  /* USER CODE END I2C1_MspDeInit 1 */
  }
}

/* USER CODE BEGIN 1 */
extern msg[50];

	// Datenblatt S.25 - 26

	// für Spannungsmessung: Beispiel-Konfiguration: Einzelmessung an AINx gegen GND, Gain = ±0.512 V, 128 SPS
	uint16_t spg_ads1115_config_single_ain0 = 0xC983; //1100 1001 1000 0011
	uint16_t spg_ads1115_config_single_ain1 = 0xD983; //1101 1001 1000 0011
	uint16_t spg_ads1115_config_single_ain2 = 0xE983; //1110 1001 1000 0011
	uint16_t spg_ads1115_config_single_ain3 = 0xF983; //1111 1001 1000 0011

	// für Strommessung: Beispiel-Konfiguration: Einzelmessung an AINx gegen GND, Gain = ±4.096 V, 128 SPS
	uint16_t str_ads1115_config_single_ain0 = 0xC383; //1100 0011 1000 0011
	uint16_t str_ads1115_config_single_ain1 = 0xD383; //1101 0011 1000 0011
	uint16_t str_ads1115_config_single_ain2 = 0xE383; //1110 0011 1000 0011
	uint16_t str_ads1115_config_single_ain3 = 0xF383; //1111 0011 1000 0011

	//Spannungsmessung:
	void ADS1115_SPG_WriteConfig(uint16_t config)
	{
	    uint8_t config_data[3];
	    config_data[0] = ADS1115_REG_CONFIG;
	    config_data[1] = (uint8_t)(config >> 8);
	    config_data[2] = (uint8_t)(config & 0xFF);
	    HAL_I2C_Master_Transmit(&hi2c1, ADS1115_SPG_ADDRESS, config_data, 3, HAL_MAX_DELAY);
	}

	int16_t ADS1115_SPG_ReadConversion()
	{
	    uint8_t reg = ADS1115_REG_CONVERSION;
	    uint8_t data[2];

	    HAL_I2C_Master_Transmit(&hi2c1, ADS1115_SPG_ADDRESS, &reg, 1, HAL_MAX_DELAY);
	    HAL_I2C_Master_Receive(&hi2c1, ADS1115_SPG_ADDRESS, data, 2, HAL_MAX_DELAY);

	    return (int16_t)((data[0] << 8) | data[1]);
	}

	int16_t ADS1115_SPG_ReadSingleEnded_AIN0(void)
	{
		ADS1115_SPG_WriteConfig(spg_ads1115_config_single_ain0);
	    HAL_Delay(10); // Warte auf Conversion
	    return ADS1115_SPG_ReadConversion();
	}

	int16_t ADS1115_SPG_ReadSingleEnded_AIN1(void)
	{
		ADS1115_SPG_WriteConfig(spg_ads1115_config_single_ain1);
	    HAL_Delay(10); // Warte auf Conversion
	    return ADS1115_SPG_ReadConversion();
	}

	int16_t ADS1115_SPG_ReadSingleEnded_AIN2(void)
	{
		ADS1115_SPG_WriteConfig(spg_ads1115_config_single_ain2);
	    HAL_Delay(10); // Warte auf Conversion
	    return ADS1115_SPG_ReadConversion();
	}

	int16_t ADS1115_SPG_ReadSingleEnded_AIN3(void)
	{
		ADS1115_SPG_WriteConfig(spg_ads1115_config_single_ain3);
	    HAL_Delay(10); // Warte auf Conversion
	    return ADS1115_SPG_ReadConversion();
	}

	//Strommessung:
	void ADS1115_STROM_WriteConfig(uint16_t config)
	{
	    uint8_t config_data[3];
	    config_data[0] = ADS1115_REG_CONFIG;
	    config_data[1] = (uint8_t)(config >> 8);
	    config_data[2] = (uint8_t)(config & 0xFF);
	    HAL_I2C_Master_Transmit(&hi2c1, ADS1115_STROM_ADDRESS, config_data, 3, HAL_MAX_DELAY);
	}

	int16_t ADS1115_STROM_ReadConversion()
	{
	    uint8_t reg = ADS1115_REG_CONVERSION;
	    uint8_t data[2];

	    HAL_I2C_Master_Transmit(&hi2c1, ADS1115_STROM_ADDRESS, &reg, 1, HAL_MAX_DELAY);
	    HAL_I2C_Master_Receive(&hi2c1, ADS1115_STROM_ADDRESS, data, 2, HAL_MAX_DELAY);

	    return (int16_t)((data[0] << 8) | data[1]);
	}

	int16_t ADS1115_STROM_ReadSingleEnded_AIN0(void)
	{
		ADS1115_STROM_WriteConfig(str_ads1115_config_single_ain0);
	    HAL_Delay(10); // Warte auf Conversion
	    return ADS1115_STROM_ReadConversion();
	}

	int16_t ADS1115_STROM_ReadSingleEnded_AIN1(void)
	{
		ADS1115_STROM_WriteConfig(str_ads1115_config_single_ain1);
	    HAL_Delay(10); // Warte auf Conversion
	    return ADS1115_STROM_ReadConversion();
	}

	int16_t ADS1115_STROM_ReadSingleEnded_AIN2(void)
	{
		ADS1115_STROM_WriteConfig(str_ads1115_config_single_ain2);
	    HAL_Delay(10); // Warte auf Conversion
	    return ADS1115_STROM_ReadConversion();
	}

	int16_t ADS1115_STROM_ReadSingleEnded_AIN3(void)
	{
		ADS1115_STROM_WriteConfig(str_ads1115_config_single_ain3);
	    HAL_Delay(10); // Warte auf Conversion
	    return ADS1115_STROM_ReadConversion();
	}


	void Spannungsmessung_Funktion(int16_t *Spg_Ergebnis){ // Verbaut wurde nachträglich ein Spannungsteiler aus 180k und 20k, daher mal 10
														   // der Dritte Faktor ist zur korrektur der Ungenauigkeit des Spannungsteilers (Empierisch bestimmt)
			  Spg_Ergebnis[0] = (int16_t)(0.015625 * 10 * 0.9986 * ADS1115_SPG_ReadSingleEnded_AIN0() + 1);

			  Spg_Ergebnis[1] = (int16_t)(0.015625 * 10 * 1.0007 * ADS1115_SPG_ReadSingleEnded_AIN1() + 1);

			  Spg_Ergebnis[2] = (int16_t)(0.015625 * 10 * 0.9993 * ADS1115_SPG_ReadSingleEnded_AIN2() + 1);

			  Spg_Ergebnis[3] = 0; //= (int16_t)(0.1875 * 10 * 1.0000 ADS1115_SPG_ReadSingleEnded_AIN3()); // NC

		}


	void Strommessung_Funktion(int16_t *Str_Ergebnis){

			long sum[4] = {0, 0, 0, 0};     // Summenspeicher für Mittelwert
			int i;

			// 10 Durchläufe für Mittelung
			for(i = 0; i < 10; i++)
			{																				// Letzte Summanden sind korrekturfaktoren (Offset) (Empierisch bestimmt)
				sum[0] += (((0.125 * 1.1998 * ADS1115_STROM_ReadSingleEnded_AIN0()) - 2498) / 0.150) - 1;
				sum[1] += (((0.125 * 1.2001 * ADS1115_STROM_ReadSingleEnded_AIN1()) - 2500) / 0.150) - 7;
				sum[2] += (((0.125 * 1.1997 * ADS1115_STROM_ReadSingleEnded_AIN2()) - 2499) / 0.150) - 2;
				sum[3] = 0; //+= ((0.1875 * ADS1115_STROM_ReadSingleEnded_AIN3()) - 2500) / 0.125; // NC
				HAL_Delay(20);
			}

			// Mittelwert bilden
			for(i = 0; i < 4; i++)
			{
				Str_Ergebnis[i] = (int16_t)(sum[i] / 10);
			}

	}

// ab hier IO_Expander für Verschaltung

	// #################################################################################
	// PCF8574T IO-Expander Start
	void PCF8574T_WriteOutputs(uint8_t Registerdaten)
	{
		//uint8_t PCF8574T_out = 0b11111111; //P7, P6, P5, P4, P3, P2, P1, P0, Relais ist bei 0 an und bei 1 aus
		uint8_t PCF8574T_out = Registerdaten;
		HAL_I2C_Master_Transmit(&hi2c1, PCF8574T_Write_ADDR, &PCF8574T_out, 1, HAL_MAX_DELAY);
	}

	void Sensor_Position_setzen_Funktion(uint8_t Eingang_Sens_Pos [8])// Übergabewert: uint8_t Eingang_Sens_Pos [8] = {0,0,0,0,0,0,0,0};
	{
		uint8_t Registerdaten = 0;

		    for (uint8_t i = 0; i < 8; i++)
		    {
		        Registerdaten |= (Eingang_Sens_Pos[i] & 0x01) << i;
		    }

		PCF8574T_WriteOutputs(Registerdaten);
	}

	bool Gueltige_Zeichen_Check_Sensor_Position(uint8_t Eingang_Sens_Pos [8])
	{
	    uint8_t summe = 0;

	    for (int i = 0; i < 8; i++)
	    {

	        if (Eingang_Sens_Pos[i] != 0 && Eingang_Sens_Pos[i] != 1) // Nur 0 oder 1 erlaubt
	        {
	            return false;
	        }
	        summe += Eingang_Sens_Pos[i];
	    }

	    if (summe < 6)// Mindestens 6 Einsen → maximal 2 Nullen -> es dürfen wegen der Stromaufnahme maximal 2 Relais gleichzeitig eingeschaltet sein (Relais bei 0 aktiv)
	    {
	        return false;
	    }

	    return true;
	}

	// #################################################################################
	// TCA9555 IO-Expander Start
	void TCA9555_Config_AllOutputs(void)
	{
	    uint8_t config_data[3] = {0x06, 0x00, 0x00}; // alle Pins Ausgang
	    HAL_I2C_Master_Transmit(&hi2c1, TCA9555_ADDR, config_data, 3, HAL_MAX_DELAY);
	}

	void TCA9555_WriteOutputs(uint8_t port0, uint8_t port1)
	{
	    uint8_t out0[2] = {0x02, port0};
	    uint8_t out1[2] = {0x03, port1};
	    HAL_I2C_Master_Transmit(&hi2c1, TCA9555_ADDR, out0, 2, HAL_MAX_DELAY);
	    HAL_I2C_Master_Transmit(&hi2c1, TCA9555_ADDR, out1, 2, HAL_MAX_DELAY);
	}

	void Zellen_Verschalten_Funktion(uint8_t Eingang_Verschaltung [9])// Übergabewert: uint8_t Eingang_Verschaltung [9] = {0,0,0,0,0,0,0,0,0};
	{
	    TCA9555_Config_AllOutputs();

	    uint16_t wert = 0;

	    for (int i = 0; i < 9; i++)
	       {
	    		wert |= ((uint16_t)(Eingang_Verschaltung[8 - i] & 1u) << i);   // arr[8] wird Bit 0, arr[0] wird Bit 8
	       }

	    // unteres Byte → port0, oberes Byte → port1
	    uint8_t port0 = (uint8_t)(wert & 0x00FF);      // Bits 0–7, 0b00000000; // Z1_R, Z1_GND, Z2_direkt, Z2_mit_R, Z2_GND, Z3_direkt, Z3_mit_R, Z3_GND
	    uint8_t port1 = (uint8_t)((wert >> 8) & 0xFF); // Bits 8–15, 0b00000000; //  nc,     nc,        nc,       nc,     nc,        nc,       nc, Z1_1_direkt

	    TCA9555_WriteOutputs(port0, port1);
	}

	bool Gueltige_Zeichen_Check_Verschaltung(const uint8_t Eingang_Verschaltung[9])
	{
	    for (int i = 0; i < 9; i++)
	    {
	    	if (Eingang_Verschaltung[i] != 0 && Eingang_Verschaltung[i] != 1)   // nur 0 oder 1 erlaubt
	            return false;
	    }
	    return true;
	}

	bool Spannungs_Check_Verschaltung(const uint8_t Eingang_Verschaltung[9], uint16_t max_Spg_dif)
	{
		uint8_t Verschaltung_fuer_Check [9] = {0,0,1,0,0,1,0,0,1};
		Zellen_Verschalten_Funktion(Verschaltung_fuer_Check); //nur GND Verbindung herstellen

		HAL_Delay(200);

		int16_t Spannungswerte[4] = {0,0,0,0};

		Spannungsmessung_Funktion(Spannungswerte);

		HAL_Delay(50);

		uint8_t Verschaltung_reset [9] = {0,0,0,0,0,0,0,0,0};
		Zellen_Verschalten_Funktion(Verschaltung_reset); //alles auf 0

		// wenn Spg unter 1000mV ist kann man davon ausgehen, dass keine Zelle eingelegt ist
		if (((Spannungswerte[0] >= 1000 && Spannungswerte[1] >= 1000 && (abs(Spannungswerte[0] - Spannungswerte[1]) >= max_Spg_dif) && Eingang_Verschaltung[0] == 1 && Eingang_Verschaltung[3] == 1) ||
			 (Spannungswerte[0] >= 1000 && Spannungswerte[2] >= 1000 && (abs(Spannungswerte[0] - Spannungswerte[2]) >= max_Spg_dif) && Eingang_Verschaltung[0] == 1 && Eingang_Verschaltung[6] == 1) ||
			 (Spannungswerte[1] >= 1000 && Spannungswerte[2] >= 1000 && (abs(Spannungswerte[1] - Spannungswerte[2]) >= max_Spg_dif) && Eingang_Verschaltung[3] == 1 && Eingang_Verschaltung[6] == 1)))
			return false;
		else
			return true;

		//		Eingang_Verschaltung[0]  Z1_direkt     Spannungswerte[0] = Z1
		//		Eingang_Verschaltung[1]  Z1_R          Spannungswerte[1] = Z2
		//		Eingang_Verschaltung[2]  Z1_GND        Spannungswerte[2] = Z3
		//		Eingang_Verschaltung[3]  Z2_direkt
		//		Eingang_Verschaltung[4]  Z2_R
		//		Eingang_Verschaltung[5]  Z2_GND
		//		Eingang_Verschaltung[6]  Z3_direkt
		//		Eingang_Verschaltung[7]  Z3_R
		//		Eingang_Verschaltung[8]) Z3_GND

	}

/* USER CODE END 1 */
