/**
 ******************************************************************************
 * @file    pm_config.h
 * @brief   Build-time selection of the communication interfaces.
 *
 * The STM32C051 has only 32 KB flash. If both interfaces together do not fit,
 * build two firmware variants by switching one of them off:
 *
 *   PM_ENABLE_I2C  1 / 0   I2C slave interface to the master board (i2c_comm.c)
 *   PM_ENABLE_UART 1 / 0   debug command line on USART1 (uart_comm.c)
 *
 * Either change the defaults below, or (more convenient) leave them and create
 * a second build configuration in the IDE: Project -> Properties -> C/C++ Build
 * -> Settings -> MCU GCC Compiler -> Preprocessor -> Define symbols, e.g.
 * "PM_ENABLE_I2C=0" for a UART debug build. A value given there overrides the
 * default here.
 *
 * Switching an interface off removes its application code and the HAL
 * interrupt-mode driver code it pulls in (the CubeMX init of the peripheral
 * itself stays and is harmless).
 ******************************************************************************
 */
#ifndef PM_CONFIG_H
#define PM_CONFIG_H

#ifndef PM_ENABLE_I2C
#define PM_ENABLE_I2C   1
#endif

#ifndef PM_ENABLE_UART
#define PM_ENABLE_UART  1
#endif

#endif /* PM_CONFIG_H */
