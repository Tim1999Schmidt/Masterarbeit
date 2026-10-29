/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Main program body
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
#include "main.h"
#include "i2c.h"
#include "usart.h"
#include "gpio.h"
#include "tle9015.h"
#include "core_cm4.h"  // Für STM32F3/F4 etc. (wichtig für DWT) für us_Delay
#include <stdbool.h>

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */
/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */
/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */
/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/
/* USER CODE BEGIN PV */
/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
/* USER CODE BEGIN PFP */
void SystemClock_Config(void);
/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

#define RX_BUFFER_SIZE 40  // Maximale Eingabelänge
char rxBuffer[RX_BUFFER_SIZE]; // Puffer für Eingabe

void sendMessage(char *message) {
    HAL_UART_Transmit(&huart2, (uint8_t*)message, strlen(message), HAL_MAX_DELAY);
}

void receiveInput(void) //Programm wartet und wird nach Eingang eines Datenstrings fortgesetzt
{
    uint8_t index = 0;
    uint8_t receivedChar;

    while (1)
    {
        if (HAL_UART_Receive(&huart2, &receivedChar, 1, 20) == HAL_OK) // 20 = UART_TIMEOUT_MS
        {
            if (receivedChar == '\r' || receivedChar == '\n')
            {
                rxBuffer[index] = '\0';
                break;
            }
            if (index < RX_BUFFER_SIZE - 1)
            {
                rxBuffer[index++] = receivedChar;
            }
        }
    }
}

// SS: dieser Teil ist dafür, dass printf über USB-COM ausgibt
int _write(int file, char *ptr, int len) {
    HAL_UART_Transmit(&huart2, (uint8_t*) ptr, len, HAL_MAX_DELAY);
    return len;
}

char msg[50];

int16_t Spannungswerte[4] = {0,0,0,0};

int16_t Stromwerte[4] = {0,0,0,0};

uint8_t Eingang_Sens_Pos [8] = {1,1,1,1,1,1,1,1};

uint8_t Eingang_Verschaltung [9] = {0,0,0,0,0,0,0,0,0};

//us_Delay_Start, Funktion zum Initialisieren des DWT (einmalig beim Start)
void DWT_Init(void) {
    CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk; // DWT-Timer aktivieren
    DWT->CYCCNT = 0;                                // Zähler auf 0 setzen
    DWT->CTRL |= DWT_CTRL_CYCCNTENA_Msk;            // Zähler aktivieren
}
// Mikrosekunden-Delay
void DWT_Delay_us(uint32_t us) {
    uint32_t clk_cycle_start = DWT->CYCCNT;
    uint32_t ticks = us * (SystemCoreClock / 1000000);

    while ((DWT->CYCCNT - clk_cycle_start) < ticks);
}
//us_Delay_Ende

/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{

  /* USER CODE BEGIN 1 */

  /* USER CODE END 1 */

  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */

  DWT_Init(); //us_Delay
  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  MX_USART2_UART_Init();
  MX_I2C1_Init();
  MX_USART3_UART_Init();

  HAL_NVIC_SetPriority(EXTI15_10_IRQn, 2, 0);
  HAL_NVIC_EnableIRQ(EXTI15_10_IRQn);

  /* USER CODE BEGIN 2 */
  Sensor_Position_setzen_Funktion(Eingang_Sens_Pos); // Sicherheitshalber Rücksetzen der Verschaltung vor Schleife
  HAL_Delay(100);
  Zellen_Verschalten_Funktion(Eingang_Verschaltung); // Sicherheitshalber Rücksetzen der Verschaltung vor Schleife
  HAL_Delay(100);
  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */

  while (1)
  {
	  sendMessage("Warten auf Befehl!\r\n"); // dieser Wert soll immer als letzter String der alten Funktion von Matlab eingelesen werden
	  memset(rxBuffer, 0, RX_BUFFER_SIZE); // Buffer wird immer bei Schleifenbeginn geleert und wartet auf eine neue Eingabe um Falsche Eingaben zu verhindern
	  receiveInput(); // Funktion!!! Warte auf Benutzereingabe, Programm wird bei Eingabe durch Text oder blauen Taster (B1) fortgesetzt
	  HAL_Delay(100); // ansonsten werden die ersten paar Zeichen evtl nicht richtig gelesen

	  sendMessage(rxBuffer);
	  sendMessage("\r\n");

	  if (strcmp(rxBuffer, "Befehl_Connect") == 0)
	              	  	  {
		  	  	  	  	  	  sendMessage("Befehl_Connect wurde erkannt\r\n");
		  	  	  	  	  	  sendMessage("Verbindung wurde hergestellt\r\n");
		  	  	  	  	  	  sendMessage("SW: Smarter_Zellhalter_C_29_04_2026_final_Abgabe\r\n");
	              	  	  }

	  else if (strcmp(rxBuffer, "Befehl_Spg_Messung") == 0)
	  	              	  {
		  	  	  	  	  	  sendMessage("Befehl_Spg_Messung wurde erkannt\r\n");
		  	  	  	  	  	  Spannungsmessung_Funktion(Spannungswerte);

		  	  	  	  	  	  sprintf(msg, "Spannungswerte;%d;%d;%d;%d;\r\n", Spannungswerte[0], Spannungswerte[1], Spannungswerte[2], Spannungswerte[3]);
		  	  	  	  	  	  sendMessage(msg);
	  	              	  }

	  else if (strcmp(rxBuffer, "Befehl_Str_Messung") == 0)
	  	  	              {
	  		  	  	  	  	  sendMessage("Befehl_Str_Messung wurde erkannt\r\n");
	  						  Strommessung_Funktion(Stromwerte);

	  						  sprintf(msg, "Stromwerte;%d;%d;%d;%d;\r\n", Stromwerte[0], Stromwerte[1], Stromwerte[2], Stromwerte[3]);
	  						  sendMessage(msg);
	  	  	              }

	  else if (strncmp(rxBuffer, "Befehl_Sens_Pos", strlen("Befehl_Sens_Pos")) == 0) //Vergleicht ob der String mit Befehl_Verschalten beginnt
	  	  	  	              {														 //Aufbau rxBuffer: Befehl_Sens_Pos;1;1;1;1;1;1;1;1;
	  						  	  sendMessage("Befehl_Sens_Pos wurde erkannt\r\n");

	  						  	  // Werte aus rxBuffer in Eingang_Sens_Pos speichern
	  						  	  sscanf(rxBuffer, "Befehl_Sens_Pos;%d;%d;%d;%d;%d;%d;%d;%d;",&Eingang_Sens_Pos[0], // nc
	  																						  &Eingang_Sens_Pos[1], // P1 = Relais K1 = EIS1_Sense_+
																							  &Eingang_Sens_Pos[2], // P2 = Relais K2 = EIS1_Sense_-
																							  &Eingang_Sens_Pos[3], // P3 = Relais K3 = EIS2_Sense_+
																							  &Eingang_Sens_Pos[4], // P4 = Relais K4 = EIS2_Sense_-
																							  &Eingang_Sens_Pos[5], // P5 = Relais K5 = EIS3_Sense_+
																							  &Eingang_Sens_Pos[6], // P6 = Relais K6 = EIS3_Sense_-
																							  &Eingang_Sens_Pos[7]);// nc

	  						  	  if (Gueltige_Zeichen_Check_Sensor_Position(Eingang_Sens_Pos) == false)
	  						  	  	  {
	  						  		  	  sendMessage("Ungueltige Befehlseingabe\r\n");
	  						  	  	  }
	  						  	  else
	  						  	  	  {
	  						  		  	  Sensor_Position_setzen_Funktion(Eingang_Sens_Pos);
	  						  		  	  sendMessage("Befehl_Sens_Pos wurde ausgefuehrt\r\n");
	  						  	  	  }
	  	  	  	              }

	  else if (strncmp(rxBuffer, "Befehl_Verschalten", strlen("Befehl_Verschalten")) == 0) //Vergleicht ob der String mit Befehl_Verschalten beginnt
	  	  	              {																   //Aufbau rxBuffer: Befehl_Verschalten;0;0;0;0;0;0;0;0;0;
						  	  sendMessage("Befehl_Verschalten wurde erkannt\r\n");

						  	  // Werte aus rxBuffer in Eingang_Verschaltung speichern
						  	  sscanf(rxBuffer, "Befehl_Verschalten;%d;%d;%d;%d;%d;%d;%d;%d;%d;",&Eingang_Verschaltung[0], // Z1_direkt
																							  	&Eingang_Verschaltung[1], // Z1_R
																								&Eingang_Verschaltung[2], // Z1_GND
																								&Eingang_Verschaltung[3], // Z2_direkt
																								&Eingang_Verschaltung[4], // Z2_R
																								&Eingang_Verschaltung[5], // Z2_GND
																								&Eingang_Verschaltung[6], // Z3_direkt
																								&Eingang_Verschaltung[7], // Z3_R
																								&Eingang_Verschaltung[8]);// Z3_GND

						  	  if (Gueltige_Zeichen_Check_Verschaltung(Eingang_Verschaltung) == false) // Überprüft auf Gülitge Zeichen und Wertebereich (0 oder 1)
								{
						  		  sendMessage("Ungueltige Befehlseingabe\r\n");
								}
						  	  else
								{
						  		  int16_t max_Spg_dif = 50;

						  		  if (Spannungs_Check_Verschaltung(Eingang_Verschaltung, max_Spg_dif) == false) // Überprüft Spannungsdifferenz
									{																			// hier Check ob die Verschaltung ausführbar ist hinsichtlich des Spannungsunterschieds
						  			  sendMessage("Spannungsdifferenz zu hoch\r\n");							// eine Check-Messung mit nur GND-Kontakten ist aber immer erlaubt
									}																			// Verschaltung mit leerem Zellenplatz ist auch immer erlaubt
						  		  else
									{
									  Zellen_Verschalten_Funktion(Eingang_Verschaltung);
									  sendMessage("Verschaltung wurde ausgefuehrt\r\n");
									}
								}
	  	  	              }

	  else if (strncmp(rxBuffer, "Befehl_EIS", strlen("Befehl_EIS")) == 0) //Vergleicht ob der String mit Befehl_EIS beginnt
				  	  	  {
		  	  	  	  	  	  sendMessage("Befehl_EIS wurde erkannt\r\n");

		  	  	  	  	  	  uint8_t Einstellungen_Parameter[6] = {0,0,0,0,0,0};

		  	  	  	  	  	  // Werte aus rxBuffer in Einstellungen_Parameter speichern
		  	  	  	  	  	  sscanf(rxBuffer, "Befehl_EIS;%d;%d;%d;%d;%d;%d;",&Einstellungen_Parameter[0],
							  	  	  	  	  	  	  	  	   	   	   	   	   &Einstellungen_Parameter[1],
																			   &Einstellungen_Parameter[2],
																			   &Einstellungen_Parameter[3],
																			   &Einstellungen_Parameter[4],
																			   &Einstellungen_Parameter[5]);

		  	  	  	  	  	  if (Gueltige_Zeichen_Check_EIS(Einstellungen_Parameter) == false) // Überprüft auf Gülitgen Zeichen und Wertebereich
								{
								  sendMessage("Ungueltige Befehlseingabe\r\n");
								}
							  else
								{
								  sendMessage("EIS_Messung wurde gestartet\r\n");

								  EIS_Messung(Einstellungen_Parameter);

								  sendMessage("EIS-Messung fertig!!!\r\n");
								}
				  	  	  }

    /* USER CODE END WHILE */
  }
  /* USER CODE BEGIN 3 */

  /* USER CODE END 3 */
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};
  RCC_PeriphCLKInitTypeDef PeriphClkInit = {0};

  /** Initializes the RCC Oscillators according to the specified parameters
  * in the RCC_OscInitTypeDef structure.
  */
  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSI;
  RCC_OscInitStruct.HSIState = RCC_HSI_ON;
  RCC_OscInitStruct.HSICalibrationValue = RCC_HSICALIBRATION_DEFAULT;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSI;
  RCC_OscInitStruct.PLL.PLLMUL = RCC_PLL_MUL9;
  RCC_OscInitStruct.PLL.PREDIV = RCC_PREDIV_DIV1;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }

  /** Initializes the CPU, AHB and APB buses clocks
  */
  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK
                              |RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV2;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV1;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_2) != HAL_OK)
  {
    Error_Handler();
  }
  PeriphClkInit.PeriphClockSelection = RCC_PERIPHCLK_USART2|RCC_PERIPHCLK_USART3
                              |RCC_PERIPHCLK_I2C1;
  PeriphClkInit.Usart2ClockSelection = RCC_USART2CLKSOURCE_PCLK1;
  PeriphClkInit.Usart3ClockSelection = RCC_USART3CLKSOURCE_PCLK1;
  PeriphClkInit.I2c1ClockSelection = RCC_I2C1CLKSOURCE_HSI;
  if (HAL_RCCEx_PeriphCLKConfig(&PeriphClkInit) != HAL_OK)
  {
    Error_Handler();
  }
}

/* USER CODE BEGIN 4 */

/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
  /* User can add his own implementation to report the HAL error return state */
  __disable_irq();
  while (1)
  {
  }
  /* USER CODE END Error_Handler_Debug */
}

#ifdef  USE_FULL_ASSERT
/**
  * @brief  Reports the name of the source file and the source line number
  *         where the assert_param error has occurred.
  * @param  file: pointer to the source file name
  * @param  line: assert_param error line source number
  * @retval None
  */
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */
  /* User can add his own implementation to report the file name and line number,
     ex: printf("Wrong parameters value: file %s on line %d\r\n", file, line) */
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */
