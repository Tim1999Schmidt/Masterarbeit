/**
 ******************************************************************************
 * @file    mm_app.h
 * @brief   Top level of the MM firmware: starts the modules and runs them
 *          from the main loop.
 *
 * Module overview:
 *   mm_config      board list (BM / PM addresses, PM temperature sources), flash
 *   i2c_bus        I2C master access to the register maps of the boards
 *   boards         cyclic telemetry of all boards, commands to BMs and PMs,
 *                  forwarding of the BM tab temperature to the PMs
 *   eis_sequencer  EIS jobs: single cell, stack, all cells (+ stack)
 *   host_comm      text protocol to the MATLAB GUI on USART2 (ST-LINK VCP)
 *
 * LED LD2: 1 Hz idle, 5 Hz while an EIS job runs.
 ******************************************************************************
 */
#ifndef MM_APP_H
#define MM_APP_H

#include "main.h"

/* Call once in USER CODE 2 of main.c (after the MX_..._Init() calls). */
void MmApp_Init(void);

/* Call in USER CODE 3 of main.c (inside the while (1) loop). */
void MmApp_Process(void);

#endif /* MM_APP_H */
