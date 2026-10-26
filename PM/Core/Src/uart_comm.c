/**
 ******************************************************************************
 * @file    uart_comm.c
 * @brief   See uart_comm.h.
 *
 * Kept small on purpose (32 KB flash):
 *  - no printf/scanf (newlib float formatting would cost several KB),
 *  - no HAL UART interrupt driver: the USART1 registers are used directly by
 *    a few lines of ISR (receive ring buffer, transmit ring buffer),
 *  - all values are printed from one table, shared by "status" and "log".
 ******************************************************************************
 */
#include "uart_comm.h"
#include "pm_config.h"

#if PM_ENABLE_UART

#include "pid_control.h"
#include "temperature_sensor.h"
#include "pm_settings.h"
#include "i2c_comm.h"
#include <string.h>

#define UART_IRQ_PRIORITY     2u      /* below I2C1 (1): the I2C slave must never be delayed */
#define RX_BUF_SIZE          32u      /* power of two */
#define TX_BUF_SIZE         256u      /* power of two; a "status" reply is ~170 bytes */
#define LINE_MAX             24u
#define LOG_MIN_PERIOD_MS   100u      /* = temperature measurement interval */
#define GAIN_MAX         65.535f      /* same range as the I2C registers (uint16 x 1000) */
#define NUM_GAINS             3u      /* kp, ki, kd */
#define PERCENT_PER_UNIT    100.0f    /* duty cycle printed in % */
#define UINT32_DEC_DIGITS    10u      /* "4294967295" */
#define PUT_FIXED_MAX     2.0e9f      /* PutFixed() clips larger values (fits uint32 after scaling) */
#define ASCII_DEL          0x7F       /* backspace key of many terminals */
#define HEX_BASE             16u
#define DEC_BASE             10u
#define HEX_LETTER_OFFSET    10u      /* 'a' = 10 */
#define ADDR_CMD             "addr"
#define I_GAIN_DECIMALS       4u      /* igain shown as 1.0000 */
#define ADDR_CMD_LEN         4u

static volatile uint8_t  rxBuf[RX_BUF_SIZE];
static volatile uint8_t  rxHead, rxTail;     /* head: ISR, tail: main loop */
static volatile uint8_t  txBuf[TX_BUF_SIZE];
static volatile uint16_t txHead, txTail;     /* head: main loop, tail: ISR */

static char     line[LINE_MAX + 1u];
static uint8_t  lineLen;
static uint32_t logPeriodMs, logLastTick;

/* ---- value table: printed by "status" (all) and "log" (first LOG_FIELDS) ---- */
enum { F_TSET, F_TACT, F_TPT, F_I, F_DUTY, F_OUT, F_ILIM, F_KP, F_KI, F_KD, F_COUNT };
#define LOG_FIELDS  6u

static const char *const fieldName[F_COUNT] = { "tset", "t_act", "t_pt", "i", "duty", "out", "ilim", "kp", "ki", "kd" };
static const uint8_t     fieldDec[F_COUNT]  = { 2, 2, 2, 3, 1, 3, 3, 3, 3, 3 };

static float FieldValue(uint8_t f)
{
    float g[NUM_GAINS];
    switch (f)
    {
    case F_TSET: return PidControl_GetSetpoint();
    case F_TACT: return TempSensor_GetControlTemperature();
    case F_TPT:  return TempSensor_GetTemperature();
    case F_I:    return PidControl_GetMeasuredCurrent();
    case F_DUTY: return PidControl_GetDutyCycle() * PERCENT_PER_UNIT;
    case F_OUT:  return PidControl_GetControllerOutput();
    case F_ILIM: return PidControl_GetCurrentLimit();
    default:
        PidControl_GetGains(&g[0], &g[1], &g[2]);
        return g[f - F_KP];
    }
}

/* ---- output ------------------------------------------------------------------- */
static void PutChar(char c)
{
    const uint16_t next = (uint16_t)((txHead + 1u) & (TX_BUF_SIZE - 1u));
    if (next == txTail)
        return;                                  /* buffer full: drop (debug output only) */
    txBuf[txHead] = (uint8_t)c;
    txHead = next;
    USART1->CR1 |= USART_CR1_TXEIE_TXFNFIE;      /* ISR sends it */
}

static void Put(const char *s)
{
    while (*s)
        PutChar(*s++);
}

static void PutUInt(uint32_t v)
{
    char buf[UINT32_DEC_DIGITS];
    uint8_t n = 0u;
    do { buf[n++] = (char)('0' + (v % 10u)); v /= 10u; } while (v != 0u);
    while (n > 0u)
        PutChar(buf[--n]);
}

/* Fixed-point output with 1..3 decimals, rounded. */
static void PutFixed(float v, uint8_t decimals)
{
    uint32_t scale = 10u, n;
    while (--decimals)
        scale *= 10u;

    v *= (float)scale;
    if (v < 0.0f)
    {
        v = -v;
        if (v >= 0.5f)
            PutChar('-');
    }
    n = (v < PUT_FIXED_MAX) ? (uint32_t)(v + 0.5f) : (uint32_t)PUT_FIXED_MAX;

    PutUInt(n / scale);
    PutChar('.');
    n %= scale;
    for (scale /= 10u; scale > 0u; scale /= 10u)
    {
        PutChar((char)('0' + (n / scale)));
        n %= scale;
    }
}

static void PutHex2(uint8_t v)
{
    static const char hexDigit[] = "0123456789ABCDEF";
    PutChar(hexDigit[v >> 4]);
    PutChar(hexDigit[v & 0x0Fu]);
}

static void PutField(uint8_t f)
{
    PutFixed(FieldValue(f), fieldDec[f]);
}

static void PrintStatus(void)
{
    uint8_t f;

    Put("OK run=");     PutUInt(PidControl_IsRunning());
    Put(" manual=");    PutUInt(PidControl_IsManual());
    Put(" err=");       PutUInt((uint32_t)PidControl_GetErrorCode());
    Put(" cool=");      PutUInt(PidControl_GetDirection() == PID_DIRECTION_COOLING);
    Put(" valid=");     PutUInt(TempSensor_IsReady());
    Put(" addr=0x");    PutHex2(PmSettings_Get()->i2cAddr);
    Put(" igain=");     PutFixed((float)PmSettings_Get()->iGainScale / (float)PM_I_GAIN_SCALE_ONE, I_GAIN_DECIMALS);
    Put(" cal=");       PutUInt(TempSensor_GetCalCountsLow());
    PutChar('/');       PutUInt(TempSensor_GetCalCountsHigh());
    Put("\r\n");
    for (f = 0u; f < F_COUNT; f++)
    {
        Put(fieldName[f]);
        PutChar('=');
        PutField(f);
        PutChar(' ');
    }
    Put("\r\n");
}

static void PrintLogLine(void)
{
    uint8_t f;

    Put("LOG;");
    PutUInt(HAL_GetTick());
    for (f = 0u; f < LOG_FIELDS; f++)
    {
        PutChar(';');
        PutField(f);
    }
    PutChar(';'); PutUInt(PidControl_GetDirection() == PID_DIRECTION_COOLING);
    PutChar(';'); PutUInt((uint32_t)PidControl_GetErrorCode());
    Put("\r\n");
}

/* ---- input ---------------------------------------------------------------------- */
/* Decimal number with optional '-' and '.'/',' fraction. Returns 1 on success. */
static uint8_t ParseNumber(const char *s, float *out)
{
    float value = 0.0f, fracScale = 1.0f;
    uint8_t negative = 0u, digits = 0u, inFrac = 0u;

    if (*s == '-') { negative = 1u; s++; }
    for (; *s; s++)
    {
        if (*s >= '0' && *s <= '9')
        {
            if (inFrac) { fracScale *= 0.1f; value += (float)(*s - '0') * fracScale; }
            else        { value = value * 10.0f + (float)(*s - '0'); }
            digits++;
        }
        else if ((*s == '.' || *s == ',') && !inFrac)
            inFrac = 1u;
        else
            return 0u;
    }
    if (digits == 0u)
        return 0u;
    *out = negative ? -value : value;
    return 1u;
}

/* Unsigned integer, decimal or with "0x" hex prefix. Returns 1 on success. */
static uint8_t ParseUInt(const char *s, uint32_t *out)
{
    uint32_t value = 0u, base = DEC_BASE;
    uint8_t digits = 0u;

    if (s[0] == '0' && s[1] == 'x') { base = HEX_BASE; s += 2; }
    for (; *s; s++)
    {
        uint32_t d;
        if (*s >= '0' && *s <= '9')                          d = (uint32_t)(*s - '0');
        else if (base == HEX_BASE && *s >= 'a' && *s <= 'f') d = (uint32_t)(*s - 'a') + HEX_LETTER_OFFSET;
        else return 0u;
        value = value * base + d;
        digits++;
    }
    if (digits == 0u)
        return 0u;
    *out = value;
    return 1u;
}

/* "addr [0x08..0x77]": show / set the I2C slave address (stored in flash) */
static void AddrCommand(const char *arg)
{
    uint32_t a;
    while (*arg == ' ')
        arg++;
    if (*arg != '\0')
    {
        if (!ParseUInt(arg, &a) || a < PM_I2C_ADDR_MIN || a > PM_I2C_ADDR_MAX)
        {
            Put("ERR 0x08..0x77\r\n");
            return;
        }
        PmSettings_Get()->i2cAddr = (uint8_t)a;
        I2cComm_SetAddress((uint8_t)a);
        if (!PmSettings_Save())
        {
            Put("ERR flash\r\n");
            return;
        }
    }
    Put("OK addr=0x"); PutHex2(PmSettings_Get()->i2cAddr); Put("\r\n");
}

/* One command line (already lower case, no leading spaces). */
static void ProcessLine(char *cmd)
{
    char *arg = strchr(cmd, ' ');
    float v = 0.0f;
    uint8_t hasValue = 0u, f;

    /* addr takes a hex argument: handled before the decimal number parsing */
    if (strncmp(cmd, ADDR_CMD, ADDR_CMD_LEN) == 0 && (cmd[ADDR_CMD_LEN] == ' ' || cmd[ADDR_CMD_LEN] == '\0'))
    {
        AddrCommand(cmd + ADDR_CMD_LEN);
        return;
    }

    if (arg != NULL)
    {
        *arg++ = '\0';
        while (*arg == ' ')
            arg++;
        if (*arg != '\0')
        {
            if (!ParseNumber(arg, &v))
            {
                Put("ERR number\r\n");
                return;
            }
            hasValue = 1u;
        }
    }

    if (strcmp(cmd, "s") == 0)            { PrintStatus(); return; }
    if (strcmp(cmd, "start") == 0)        { PidControl_Start();      Put("OK\r\n"); return; }
    if (strcmp(cmd, "stop") == 0)         { PidControl_Stop();       Put("OK\r\n"); return; }
    if (strcmp(cmd, "clear") == 0)        { PidControl_ClearError(); Put("OK\r\n"); return; }
    if (strcmp(cmd, "recal") == 0)
    {
        if (PidControl_IsRunning()) { Put("ERR running\r\n"); return; }
        TempSensor_Recalibrate();
        Put("OK\r\n");
        return;
    }
    if (strcmp(cmd, "igain") == 0)
    {
        if (hasValue)
        {
            const float scale = v * (float)PM_I_GAIN_SCALE_ONE + 0.5f;
            if (scale < (float)PM_I_GAIN_SCALE_MIN || scale > (float)PM_I_GAIN_SCALE_MAX + 0.5f)
            {
                Put("ERR 0.8..1.2\r\n");
                return;
            }
            PmSettings_Get()->iGainScale = (uint16_t)scale;
            if (!PmSettings_Save())
            {
                Put("ERR flash\r\n");
                return;
            }
        }
        Put("OK igain=");
        PutFixed((float)PmSettings_Get()->iGainScale / (float)PM_I_GAIN_SCALE_ONE, I_GAIN_DECIMALS);
        Put("\r\n");
        return;
    }
    if (strcmp(cmd, "duty") == 0)
    {
        if (hasValue && !PidControl_SetManualDuty(v))
        {
            Put("ERR running/error\r\n");
            return;
        }
        Put("OK duty="); PutField(F_DUTY); Put(" i="); PutField(F_I);
        Put(" cool="); PutUInt(PidControl_GetDirection() == PID_DIRECTION_COOLING);
        Put(PidControl_IsManual() ? " (manual)\r\n" : "\r\n");
        return;
    }
    if (strcmp(cmd, "log") == 0)
    {
        if (hasValue)
        {
            logPeriodMs = (v <= 0.0f) ? 0u : ((v < (float)LOG_MIN_PERIOD_MS) ? LOG_MIN_PERIOD_MS : (uint32_t)v);
            logLastTick = HAL_GetTick();
        }
        Put("OK log="); PutUInt(logPeriodMs);
        Put("\r\nLOG;ms;tset;t_act;t_pt;i;duty;out;cool;err\r\n");
        return;
    }

    /* settable values: tset, ilim, kp, ki, kd - with a number: set, without: show */
    for (f = 0u; f < F_COUNT; f++)
    {
        if ((f == F_TSET || f >= F_ILIM) && strcmp(cmd, fieldName[f]) == 0)
            break;
    }
    if (f == F_COUNT)
    {
        Put("ERR ? (s start stop clear recal log tset ilim kp ki kd addr duty igain)\r\n");
        return;
    }
    if (hasValue)
    {
        if (f == F_TSET)
        {
            PidControl_SetSetpoint(v);                     /* clamped to 0..50 degC */
        }
        else if (f == F_ILIM)
        {
            if (!PidControl_SetCurrentLimit(v))            /* clamped to 0.5..3.0 A */
            {
                Put("ERR running\r\n");
                return;
            }
        }
        else
        {
            float g[NUM_GAINS];
            if (v < 0.0f || v > GAIN_MAX)
            {
                Put("ERR range\r\n");
                return;
            }
            PidControl_GetGains(&g[0], &g[1], &g[2]);
            g[f - F_KP] = v;
            PidControl_SetGains(g[0], g[1], g[2]);
        }
    }
    Put("OK "); Put(fieldName[f]); PutChar('='); PutField(f); Put("\r\n");
}

/* ---- public API -------------------------------------------------------------------- */
void UartComm_Init(void)
{
    /* USART1 itself is configured by MX_USART1_UART_Init() (115200 8N1, FIFO off). */
    USART1->ICR = USART_ICR_ORECF | USART_ICR_FECF | USART_ICR_NECF | USART_ICR_PECF;
    USART1->CR1 |= USART_CR1_RXNEIE_RXFNEIE;
    HAL_NVIC_SetPriority(USART1_IRQn, UART_IRQ_PRIORITY, 0u);
    HAL_NVIC_EnableIRQ(USART1_IRQn);

    Put("\r\nPM debug UART\r\n");
}

void UartComm_Update(void)
{
    while (rxTail != rxHead)
    {
        char c = (char)rxBuf[rxTail];
        rxTail = (uint8_t)((rxTail + 1u) & (RX_BUF_SIZE - 1u));

        if (c == '\r' || c == '\n')
        {
            line[lineLen] = '\0';
            if (lineLen > 0u)
                ProcessLine(line);
            lineLen = 0u;
        }
        else if (c == '\b' || c == ASCII_DEL)
        {
            if (lineLen > 0u)
                lineLen--;
        }
        else if (lineLen < LINE_MAX && !(lineLen == 0u && c == ' '))
        {
            if (c >= 'A' && c <= 'Z')
                c = (char)(c - 'A' + 'a');           /* not case sensitive */
            line[lineLen++] = c;                      /* characters beyond LINE_MAX are dropped */
        }
    }

    if (logPeriodMs != 0u && (HAL_GetTick() - logLastTick) >= logPeriodMs)
    {
        logLastTick = HAL_GetTick();
        PrintLogLine();
    }
}

/* NOTE: if you later enable "USART1 global interrupt" in CubeMX, it generates
 * its own USART1_IRQHandler in stm32c0xx_it.c - then delete that one again
 * (this module does not use the HAL UART interrupt driver). */
void USART1_IRQHandler(void)
{
    const uint32_t isr = USART1->ISR;

    /* RXNEIE also fires on overrun: clear the error flags, otherwise the interrupt would repeat */
    if (isr & (USART_ISR_ORE | USART_ISR_FE | USART_ISR_NE | USART_ISR_PE))
        USART1->ICR = USART_ICR_ORECF | USART_ICR_FECF | USART_ICR_NECF | USART_ICR_PECF;

    if (isr & USART_ISR_RXNE_RXFNE)
    {
        const uint8_t b = (uint8_t)USART1->RDR;     /* reading clears RXNE */
        const uint8_t next = (uint8_t)((rxHead + 1u) & (RX_BUF_SIZE - 1u));
        if (next != rxTail)
        {
            rxBuf[rxHead] = b;
            rxHead = next;
        }
    }

    if ((USART1->CR1 & USART_CR1_TXEIE_TXFNFIE) && (isr & USART_ISR_TXE_TXFNF))
    {
        if (txTail != txHead)
        {
            USART1->TDR = txBuf[txTail];
            txTail = (uint16_t)((txTail + 1u) & (TX_BUF_SIZE - 1u));
        }
        else
        {
            USART1->CR1 &= ~USART_CR1_TXEIE_TXFNFIE;  /* nothing left to send */
        }
    }
}

#else  /* !PM_ENABLE_UART */

void UartComm_Init(void)   { }
void UartComm_Update(void) { }

#endif /* PM_ENABLE_UART */
