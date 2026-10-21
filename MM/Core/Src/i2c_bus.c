/**
 ******************************************************************************
 * @file    i2c_bus.c
 * @brief   See i2c_bus.h.
 ******************************************************************************
 */
#include "i2c_bus.h"

extern I2C_HandleTypeDef hi2c1;   /* initialised by MX_I2C1_Init() in main.c */

#define I2C_ADDR7_SHIFT        1u      /* HAL expects the 7-bit address shifted left by one */
#define PROBE_TRIALS           2u
#define BITS_PER_BYTE          8u

static uint32_t errorCount;

/* After a failed transfer: count it and bring the peripheral back to a clean
 * state (also clears a stuck BUSY flag in the HAL handle). */
static void Recover(void)
{
    errorCount++;
    (void)HAL_I2C_DeInit(&hi2c1);
    (void)HAL_I2C_Init(&hi2c1);
}

uint8_t I2cBus_Write(uint8_t addr7, uint8_t reg, const uint8_t *data, uint16_t len)
{
    if (HAL_I2C_Mem_Write(&hi2c1, (uint16_t)(addr7 << I2C_ADDR7_SHIFT), reg, I2C_MEMADD_SIZE_8BIT,
                          (uint8_t *)data, len, I2C_BUS_TIMEOUT_MS) == HAL_OK)
        return 1u;
    Recover();
    return 0u;
}

uint8_t I2cBus_WriteByte(uint8_t addr7, uint8_t reg, uint8_t value)
{
    return I2cBus_Write(addr7, reg, &value, sizeof(value));
}

uint8_t I2cBus_WriteU16(uint8_t addr7, uint8_t reg, uint16_t value)
{
    uint8_t b[sizeof(uint16_t)];
    b[0] = (uint8_t)value;
    b[1] = (uint8_t)(value >> BITS_PER_BYTE);
    return I2cBus_Write(addr7, reg, b, sizeof(b));
}

uint8_t I2cBus_Read(uint8_t addr7, uint8_t reg, uint8_t *data, uint16_t len)
{
    if (HAL_I2C_Mem_Read(&hi2c1, (uint16_t)(addr7 << I2C_ADDR7_SHIFT), reg, I2C_MEMADD_SIZE_8BIT,
                         data, len, I2C_BUS_TIMEOUT_MS) == HAL_OK)
        return 1u;
    Recover();
    return 0u;
}

uint8_t I2cBus_Probe(uint8_t addr7)
{
    return (HAL_I2C_IsDeviceReady(&hi2c1, (uint16_t)(addr7 << I2C_ADDR7_SHIFT), PROBE_TRIALS,
                                  I2C_BUS_TIMEOUT_MS) == HAL_OK) ? 1u : 0u;
}

uint32_t I2cBus_GetErrorCount(void)
{
    return errorCount;
}

uint16_t I2cBus_GetU16(const uint8_t *p)
{
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << BITS_PER_BYTE));
}

int16_t I2cBus_GetI16(const uint8_t *p)
{
    return (int16_t)I2cBus_GetU16(p);
}

uint32_t I2cBus_GetU32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << BITS_PER_BYTE) |
           ((uint32_t)p[2] << (2u * BITS_PER_BYTE)) | ((uint32_t)p[3] << (3u * BITS_PER_BYTE));
}

int32_t I2cBus_GetI32(const uint8_t *p)
{
    return (int32_t)I2cBus_GetU32(p);
}
