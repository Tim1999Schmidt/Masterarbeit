/*
 * tle9015.h
 *
 *  Created on: May 22, 2025
 *      Author: stieberger
 */

#ifndef INC_TLE9015_H_
#define INC_TLE9015_H_

#include "main.h"

#define TLE9015_FRAME_LENGTH 6

typedef struct {
    uint8_t sync;
    uint8_t id;
    uint8_t addr;
    uint8_t data_1;
    uint8_t data_0;
    uint8_t crc;
} TLE9015_Frame;

void TLE9015_SendWakeup(UART_HandleTypeDef *huart);
void TLE9015_SendFrame(UART_HandleTypeDef *huart, TLE9015_Frame *frame);
uint8_t TLE9015_CalcCRC(uint8_t *data, uint8_t len);

#endif /* INC_TLE9015_H_ */
