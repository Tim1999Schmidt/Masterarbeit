/**
 ******************************************************************************
 * @file    i2c_bus.h
 * @brief   I2C master access to the register maps of the BMs and PMs
 *          (I2C1, PB8 = SCL, PB9 = SDA, through the PCA9615 bus buffer).
 *
 * Both slave types use the same protocol:
 *   write: [register][data ...]                -> I2cBus_Write()
 *   read : [register] (repeated START) [data]  -> I2cBus_Read()
 * which is exactly the HAL "memory" access with 8-bit memory address.
 *
 * All functions block for at most I2C_BUS_TIMEOUT_MS. After a failed transfer
 * the bus is re-initialised (a slave that was reset in the middle of a
 * transfer can otherwise leave the HAL in the BUSY state).
 ******************************************************************************
 */
#ifndef I2C_BUS_H
#define I2C_BUS_H

#include "main.h"
#include <stdint.h>

#define I2C_BUS_TIMEOUT_MS   20u

/* Writes len bytes starting at register reg. Returns 1 on success (ACK). */
uint8_t I2cBus_Write(uint8_t addr7, uint8_t reg, const uint8_t *data, uint16_t len);

/* Writes one byte. Returns 1 on success. */
uint8_t I2cBus_WriteByte(uint8_t addr7, uint8_t reg, uint8_t value);

/* Writes a little-endian 16-bit value. Returns 1 on success. */
uint8_t I2cBus_WriteU16(uint8_t addr7, uint8_t reg, uint16_t value);

/* Reads len bytes starting at register reg. Returns 1 on success. */
uint8_t I2cBus_Read(uint8_t addr7, uint8_t reg, uint8_t *data, uint16_t len);

/* Returns 1 if a slave acknowledges its address. */
uint8_t I2cBus_Probe(uint8_t addr7);

/* Number of failed transfers since start (diagnostics). */
uint32_t I2cBus_GetErrorCount(void);

/* Little-endian helpers for register contents */
uint16_t I2cBus_GetU16(const uint8_t *p);
int16_t  I2cBus_GetI16(const uint8_t *p);
uint32_t I2cBus_GetU32(const uint8_t *p);
int32_t  I2cBus_GetI32(const uint8_t *p);

#endif /* I2C_BUS_H */
