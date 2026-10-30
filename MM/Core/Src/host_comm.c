/**
 ******************************************************************************
 * @file    host_comm.c
 * @brief   See host_comm.h. USART2 is driven through its registers with ring
 *          buffers in an own interrupt handler (USART2 global interrupt must
 *          stay disabled in CubeMX, otherwise a second handler is generated).
 ******************************************************************************
 */
#include "host_comm.h"
#include "mm_config.h"
#include "boards.h"
#include "bm_regs.h"
#include "pm_regs.h"
#include "eis_sequencer.h"
#include "i2c_bus.h"
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

extern UART_HandleTypeDef huart2;   /* initialised by MX_USART2_UART_Init() in main.c */

#define MM_FIRMWARE_VERSION   "1.0"

#define UART_IRQ_PRIORITY     2u
#define RX_BUF_SIZE         256u      /* power of two */
#define TX_BUF_SIZE        4096u      /* power of two: holds a whole result table */
#define LINE_MAX            120u
#define MAX_FIELDS           12u      /* command + arguments */
#define FIELD_SEPARATOR      ';'
#define LINE_END             "\r\n"
#define LINE_END_LEN         2u
#define FORMAT_BUF_SIZE     160u
#define DEC_BASE             10
#define HEX_BASE             16
#define HEX_LETTER_OFFSET    10       /* 'a' = 10 */
#define ALL_BOARDS            0       /* board number 0 in PM / BM commands = all boards */

/* number of ';'-separated fields of the commands with a fixed format
 * (command name included) and how many of them are numbers */
#define VALUE_CMD_FIELDS      3u      /* PMSET;<pm>;<v>  PMILIM;<pm>;<v>  PMSRC;<pm>;<src> */
#define PMSRC_NUMBERS         2u      /* <pm>;<src> */
#define PMGAIN_FIELDS         5u      /* PMGAIN;<pm>;<kp>;<ki>;<kd> */
#define PMGAIN_NUMBERS        3u
#define EIS_CMD_FIELDS_MIN    7u      /* EIS;<target>;<fstart>;<fstop>;<amp>;<wave>;<avg> */
#define EIS_CMD_FIELDS_MAX    8u      /* ...;<time> (optional, default BM_MEAS_TIME_DEFAULT) */
#define EIS_CMD_NUMBERS_MAX   (EIS_CMD_FIELDS_MAX - SECOND_ARG)
#define EIS_NUM_MEAS_TIME     5u      /* index of <time> among the numbers */
#define FIRST_ARG             1u      /* field index of the first argument */
#define SECOND_ARG            2u
#define CELL_TARGET_PREFIX    'C'

typedef char rx_size_power_of_two[((RX_BUF_SIZE & (RX_BUF_SIZE - 1u)) == 0u) ? 1 : -1];
typedef char tx_size_power_of_two[((TX_BUF_SIZE & (TX_BUF_SIZE - 1u)) == 0u) ? 1 : -1];

static volatile uint8_t  rxBuf[RX_BUF_SIZE];
static volatile uint16_t rxHead, rxTail;     /* head: ISR, tail: main loop */
static volatile uint8_t  txBuf[TX_BUF_SIZE];
static volatile uint16_t txHead, txTail;     /* head: main loop, tail: ISR */

static char    line[LINE_MAX + 1u];
static uint8_t lineLen, lineOverflow;

/* ---- output ------------------------------------------------------------------- */
uint32_t HostComm_TxFree(void)
{
    return (uint32_t)((txTail - txHead - 1u) & (TX_BUF_SIZE - 1u));
}

uint8_t HostComm_SendLine(const char *format, ...)
{
    char buf[FORMAT_BUF_SIZE];
    va_list ap;
    int n;
    uint32_t i;

    va_start(ap, format);
    n = vsnprintf(buf, sizeof(buf) - LINE_END_LEN, format, ap);
    va_end(ap);
    if (n < 0)
        return 0u;
    if ((uint32_t)n > sizeof(buf) - LINE_END_LEN - 1u)
        n = (int)(sizeof(buf) - LINE_END_LEN - 1u);           /* vsnprintf truncated */
    memcpy(&buf[n], LINE_END, LINE_END_LEN);
    n += (int)LINE_END_LEN;

    if (HostComm_TxFree() < (uint32_t)n)
        return 0u;                                          /* whole line or nothing */
    for (i = 0u; i < (uint32_t)n; i++)
    {
        txBuf[txHead] = (uint8_t)buf[i];
        txHead = (uint16_t)((txHead + 1u) & (TX_BUF_SIZE - 1u));
    }
    USART2->CR1 |= USART_CR1_TXEIE;                          /* ISR sends it */
    return 1u;
}

static void Ok(const char *cmd)                      { (void)HostComm_SendLine("OK;%s", cmd); }
static void Err(const char *cmd, const char *reason) { (void)HostComm_SendLine("ERR;%s;%s", cmd, reason); }

/* ---- parsing ------------------------------------------------------------------ */
/* Decimal (optional '-') or 0x hex integer; the whole field must be a number. */
static uint8_t ParseInt(const char *s, int32_t *out)
{
    int32_t v = 0, base = DEC_BASE;
    uint8_t neg = 0u, digits = 0u;

    if (*s == '-') { neg = 1u; s++; }
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) { base = HEX_BASE; s += 2; }
    for (; *s; s++)
    {
        int32_t d;
        if (*s >= '0' && *s <= '9')                          d = *s - '0';
        else if (base == HEX_BASE && *s >= 'a' && *s <= 'f') d = *s - 'a' + HEX_LETTER_OFFSET;
        else if (base == HEX_BASE && *s >= 'A' && *s <= 'F') d = *s - 'A' + HEX_LETTER_OFFSET;
        else return 0u;
        v = v * base + d;
        digits++;
    }
    if (digits == 0u)
        return 0u;
    *out = neg ? -v : v;
    return 1u;
}

/* Parses fields[first..first+count-1] into out[]. Returns 1 if all are numbers. */
static uint8_t ParseInts(char **fields, uint8_t first, uint8_t count, int32_t *out)
{
    uint8_t k;
    for (k = 0u; k < count; k++)
        if (!ParseInt(fields[first + k], &out[k]))
            return 0u;
    return 1u;
}

static uint8_t Split(char *s, char **fields)
{
    uint8_t n = 0u;
    fields[n++] = s;
    for (; *s; s++)
    {
        if (*s == FIELD_SEPARATOR)
        {
            *s = '\0';
            if (n >= MAX_FIELDS)
                break;
            fields[n++] = s + 1;
        }
    }
    return n;
}

static void ToUpper(char *s)
{
    for (; *s; s++)
        if (*s >= 'a' && *s <= 'z')
            *s = (char)(*s - 'a' + 'A');
}

/* ---- command handlers ----------------------------------------------------------- */
static void CmdCfgQuery(const char *cmd)
{
    const MmConfig_t *c = MmConfig_Get();
    char buf[FORMAT_BUF_SIZE];
    uint8_t i;
    int n;

    n = snprintf(buf, sizeof(buf), "CFG;BM;%u", c->numBm);
    for (i = 0u; i < c->numBm; i++)
        n += snprintf(&buf[n], sizeof(buf) - (uint32_t)n, ";0x%02X", c->bmAddr[i]);
    (void)HostComm_SendLine("%s", buf);

    n = snprintf(buf, sizeof(buf), "CFG;PM;%u", c->numPm);
    for (i = 0u; i < c->numPm; i++)
        n += snprintf(&buf[n], sizeof(buf) - (uint32_t)n, ";0x%02X", c->pmAddr[i]);
    (void)HostComm_SendLine("%s", buf);

    n = snprintf(buf, sizeof(buf), "CFG;SRC");
    for (i = 0u; i < c->numPm; i++)
        n += snprintf(&buf[n], sizeof(buf) - (uint32_t)n, ";%u", c->pmSource[i]);
    (void)HostComm_SendLine("%s", buf);
    Ok(cmd);
}

/* CFGBM / CFGPM: new address list, checked as a whole before it is taken */
static void CmdCfgList(const char *cmd, char **f, uint8_t n, uint8_t isBm)
{
    MmConfig_t c = *MmConfig_Get();
    int32_t a[MAX_FIELDS];
    const uint8_t count = (uint8_t)(n - 1u);
    uint8_t i;

    if (EisSeq_IsBusy())                        { Err(cmd, "BUSY");  return; }
    if (count > (isBm ? MM_MAX_BM : MM_MAX_PM) || !ParseInts(f, 1u, count, a))
                                                { Err(cmd, "PARAM"); return; }
    for (i = 0u; i < count; i++)
    {
        if (a[i] < (int32_t)MM_I2C_ADDR_MIN || a[i] > (int32_t)MM_I2C_ADDR_MAX)
            { Err(cmd, "ADDR"); return; }
        if (isBm) c.bmAddr[i] = (uint8_t)a[i];
        else      { c.pmAddr[i] = (uint8_t)a[i]; c.pmSource[i] = MM_PM_SOURCE_PT1000; }
    }
    if (isBm)
    {
        c.numBm = count;
        for (i = 0u; i < c.numPm; i++)          /* sources pointing at removed BMs */
            if (c.pmSource[i] > c.numBm)
                c.pmSource[i] = MM_PM_SOURCE_PT1000;
    }
    else
        c.numPm = count;
    if (!MmConfig_IsValid(&c))                  { Err(cmd, "INVALID"); return; }
    *MmConfig_Get() = c;
    Boards_Init();                              /* old board states are meaningless now */
    Ok(cmd);
}

static void CmdScan(const char *cmd)
{
    char buf[FORMAT_BUF_SIZE];
    uint8_t a;
    int n = snprintf(buf, sizeof(buf), "SCAN");

    if (EisSeq_IsBusy()) { Err(cmd, "BUSY"); return; }
    for (a = MM_I2C_ADDR_MIN; a <= MM_I2C_ADDR_MAX; a++)
    {
        if (I2cBus_Probe(a) && n < (int)(sizeof(buf) - sizeof(";0x00")))
            n += snprintf(&buf[n], sizeof(buf) - (uint32_t)n, ";0x%02X", a);
    }
    (void)HostComm_SendLine("%s", buf);
    Ok(cmd);
}

static void CmdStat(const char *cmd)
{
    const MmConfig_t *c = MmConfig_Get();
    uint8_t i;

    for (i = 0u; i < c->numBm; i++)
    {
        const BmData_t *b = Boards_GetBm(i);
        (void)HostComm_SendLine("BM;%u;0x%02X;%u;%u;%u;%u;%d;%d;%u;%u;%u",
                                (unsigned)(i + 1u), c->bmAddr[i], b->online, b->status, b->errorCode,
                                b->uCellMv, b->iCellMa, b->tTabCenti, b->numEis, b->progress, b->connectZ);
    }
    for (i = 0u; i < c->numPm; i++)
    {
        const PmData_t *p = Boards_GetPm(i);
        (void)HostComm_SendLine("PM;%u;0x%02X;%u;%u;%u;%d;%d;%d;%u;%u;%u;%u",
                                (unsigned)(i + 1u), c->pmAddr[i], p->online, p->status, p->errorCode,
                                p->tSetCenti, p->tActualCenti, p->tPt1000Centi, p->iActualMa,
                                p->dutyMilli, p->iLimitMa, c->pmSource[i]);
    }
    (void)HostComm_SendLine("MM;%u;%lu", EisSeq_IsBusy(), (unsigned long)I2cBus_GetErrorCount());
    Ok(cmd);
}

/* first argument = board number 1..count, or 0 = all; returns the range */
static uint8_t BoardRange(char **f, uint8_t n, uint8_t count, uint8_t *first, uint8_t *last)
{
    int32_t k;
    if (n <= FIRST_ARG || !ParseInt(f[FIRST_ARG], &k) || k < ALL_BOARDS || k > (int32_t)count || count == 0u)
        return 0u;
    if (k == ALL_BOARDS) { *first = 0u; *last = (uint8_t)(count - 1u); }
    else                 { *first = *last = (uint8_t)(k - 1); }
    return 1u;
}

static void CmdPm(const char *cmd, char **f, uint8_t n)
{
    uint8_t first, last, i, ok = 1u;
    int32_t v[PMGAIN_NUMBERS];

    if (strcmp(cmd, "PMSTART") != 0 && strcmp(cmd, "PMSTOP") != 0 && strcmp(cmd, "PMCLR") != 0 &&
        strcmp(cmd, "PMRECAL") != 0 && strcmp(cmd, "PMSET") != 0 && strcmp(cmd, "PMILIM") != 0 &&
        strcmp(cmd, "PMGAIN") != 0)
        { Err(cmd, "UNKNOWN"); return; }
    if (!BoardRange(f, n, MmConfig_Get()->numPm, &first, &last)) { Err(cmd, "BOARD"); return; }

    for (i = first; i <= last; i++)
    {
        if (strcmp(cmd, "PMSTART") == 0)      ok &= Boards_PmControl(i, PM_CTRL_START);
        else if (strcmp(cmd, "PMSTOP") == 0)  ok &= Boards_PmControl(i, PM_CTRL_STOP);
        else if (strcmp(cmd, "PMCLR") == 0)   ok &= Boards_PmControl(i, PM_CTRL_CLEAR_ERROR);
        else if (strcmp(cmd, "PMRECAL") == 0) ok &= Boards_PmControl(i, PM_CTRL_RECALIBRATE);
        else if (strcmp(cmd, "PMSET") == 0)
        {
            if (n != VALUE_CMD_FIELDS || !ParseInts(f, SECOND_ARG, 1u, v) ||
                v[0] < PM_T_SET_MIN_CENTI || v[0] > PM_T_SET_MAX_CENTI)
                { Err(cmd, "PARAM"); return; }
            ok &= Boards_PmSetSetpoint(i, (int16_t)v[0]);
        }
        else if (strcmp(cmd, "PMILIM") == 0)
        {
            if (n != VALUE_CMD_FIELDS || !ParseInts(f, SECOND_ARG, 1u, v) ||
                v[0] < (int32_t)PM_I_LIMIT_MIN_MA || v[0] > (int32_t)PM_I_LIMIT_MAX_MA)
                { Err(cmd, "PARAM"); return; }
            if (Boards_GetPm(i)->status & PM_ST_RUNNING)
                { Err(cmd, "RUNNING"); return; }
            ok &= Boards_PmSetCurrentLimit(i, (uint16_t)v[0]);
        }
        else if (strcmp(cmd, "PMGAIN") == 0)
        {
            if (n != PMGAIN_FIELDS || !ParseInts(f, SECOND_ARG, PMGAIN_NUMBERS, v) ||
                v[0] < 0 || v[0] > (int32_t)UINT16_MAX || v[1] < 0 || v[1] > (int32_t)UINT16_MAX || v[2] < 0 || v[2] > (int32_t)UINT16_MAX)
                { Err(cmd, "PARAM"); return; }
            ok &= Boards_PmSetGains(i, (uint16_t)v[0], (uint16_t)v[1], (uint16_t)v[2]);
        }
    }
    if (ok) Ok(cmd); else Err(cmd, "I2C");
}

static void CmdPmSource(const char *cmd, char **f, uint8_t n)
{
    MmConfig_t *c = MmConfig_Get();
    int32_t v[PMSRC_NUMBERS];

    if (n != VALUE_CMD_FIELDS || !ParseInts(f, FIRST_ARG, PMSRC_NUMBERS, v) || v[0] < 1 || v[0] > (int32_t)c->numPm ||
        v[1] < (int32_t)MM_PM_SOURCE_PT1000 || v[1] > (int32_t)c->numBm)
        { Err(cmd, "PARAM"); return; }
    c->pmSource[v[0] - 1] = (uint8_t)v[1];
    if (Boards_PmApplySource((uint8_t)(v[0] - 1))) Ok(cmd); else Err(cmd, "I2C");
}

static void CmdBm(const char *cmd, char **f, uint8_t n)
{
    uint8_t first, last, i, ok = 1u, bits;

    if (!BoardRange(f, n, MmConfig_Get()->numBm, &first, &last)) { Err(cmd, "BOARD"); return; }
    if (EisSeq_IsBusy())                                        { Err(cmd, "BUSY");  return; }

    if (strcmp(cmd, "BMCLR") == 0)        bits = BM_CTRL_CLEAR_ERROR;
    else if (strcmp(cmd, "BMRECAL") == 0) bits = BM_CTRL_RECAL_TEMP;
    else                                  bits = BM_CTRL_ZERO_CURRENT;   /* BMIZERO */

    for (i = first; i <= last; i++)
        ok &= Boards_BmControl(i, bits);
    if (ok) Ok(cmd); else Err(cmd, "I2C");
}

static void CmdEis(const char *cmd, char **f, uint8_t n)
{
    EisJob_t job;
    int32_t v[EIS_CMD_NUMBERS_MAX];
    const char *t;
    uint8_t k, numbers;

    if (n < EIS_CMD_FIELDS_MIN || n > EIS_CMD_FIELDS_MAX) { Err(cmd, "PARAM"); return; }
    numbers = (uint8_t)(n - SECOND_ARG);
    if (!ParseInts(f, SECOND_ARG, numbers, v)) { Err(cmd, "PARAM"); return; }
    t = f[FIRST_ARG];
    if (strcmp(t, "S") == 0)          job.type = EIS_JOB_STACK;
    else if (strcmp(t, "ALL") == 0)   job.type = EIS_JOB_ALL_CELLS;
    else if (strcmp(t, "ALLS") == 0)  job.type = EIS_JOB_ALL_CELLS_STACK;
    else if (t[0] == CELL_TARGET_PREFIX)
    {
        int32_t bmNumber;
        if (!ParseInt(&t[1], &bmNumber) || bmNumber < 1 || bmNumber > (int32_t)MmConfig_Get()->numBm)
            { Err(cmd, "TARGET"); return; }
        job.type   = EIS_JOB_CELL;
        job.cellBm = (uint8_t)(bmNumber - 1);
    }
    else { Err(cmd, "TARGET"); return; }

    for (k = 0u; k < numbers; k++)
        if (v[k] < 0 || v[k] > (int32_t)UINT8_MAX)
            { Err(cmd, "PARAM"); return; }
    job.fStart    = (uint8_t)v[0];
    job.fStop     = (uint8_t)v[1];
    job.amplitude = (uint8_t)v[2];
    job.waveform  = (uint8_t)v[3];
    job.averages  = (uint8_t)v[4];
    job.measTime  = (n == EIS_CMD_FIELDS_MAX) ? (uint8_t)v[EIS_NUM_MEAS_TIME] : BM_MEAS_TIME_DEFAULT;

    switch (EisSeq_Start(&job))
    {
    case EIS_SEQ_OK:           Ok(cmd);              break;
    case EIS_SEQ_ERR_BUSY:     Err(cmd, "BUSY");     break;
    case EIS_SEQ_ERR_NO_STACK: Err(cmd, "NOSTACK");  break;
    default:                   Err(cmd, "PARAM");    break;
    }
}

static void ProcessLine(char *s)
{
    char *f[MAX_FIELDS];
    const uint8_t n = Split(s, f);
    const char *cmd = f[0];

    ToUpper(f[0]);
    if (n > FIRST_ARG)
        ToUpper(f[FIRST_ARG]);                           /* EIS targets (c1 -> C1) */

    if (strcmp(cmd, "HELLO") == 0)
        (void)HostComm_SendLine("OK;HELLO;MM;%s", MM_FIRMWARE_VERSION);
    else if (strcmp(cmd, "CFG?") == 0)       CmdCfgQuery(cmd);
    else if (strcmp(cmd, "CFGBM") == 0)      CmdCfgList(cmd, f, n, 1u);
    else if (strcmp(cmd, "CFGPM") == 0)      CmdCfgList(cmd, f, n, 0u);
    else if (strcmp(cmd, "PMSRC") == 0)      CmdPmSource(cmd, f, n);
    else if (strcmp(cmd, "SAVE") == 0)
    {
        if (MmConfig_Save()) Ok(cmd); else Err(cmd, "FLASH");
    }
    else if (strcmp(cmd, "SCAN") == 0)       CmdScan(cmd);
    else if (strcmp(cmd, "STAT") == 0)       CmdStat(cmd);
    else if (cmd[0] == 'P' && cmd[1] == 'M') CmdPm(cmd, f, n);    /* PMSTART, PMSET, ... */
    else if (strcmp(cmd, "BMCLR") == 0 || strcmp(cmd, "BMRECAL") == 0 || strcmp(cmd, "BMIZERO") == 0)
        CmdBm(cmd, f, n);
    else if (strcmp(cmd, "EIS") == 0)        CmdEis(cmd, f, n);
    else if (strcmp(cmd, "ABORT") == 0)
    {
        EisSeq_Abort();
        Ok(cmd);
    }
    else
        Err(cmd, "UNKNOWN");
}

/* ---- public API ------------------------------------------------------------------ */
void HostComm_Init(void)
{
    huart2.Init.BaudRate = HOST_BAUD_RATE;          /* CubeMX default of the project: 38400 */
    (void)HAL_UART_Init(&huart2);

    USART2->ICR = USART_ICR_ORECF | USART_ICR_FECF | USART_ICR_NCF | USART_ICR_PECF;
    USART2->CR1 |= USART_CR1_RXNEIE;
    HAL_NVIC_SetPriority(USART2_IRQn, UART_IRQ_PRIORITY, 0u);
    HAL_NVIC_EnableIRQ(USART2_IRQn);

    (void)HostComm_SendLine("MM;READY;%s", MM_FIRMWARE_VERSION);
}

void HostComm_Process(void)
{
    while (rxTail != rxHead)
    {
        const char c = (char)rxBuf[rxTail];
        rxTail = (uint16_t)((rxTail + 1u) & (RX_BUF_SIZE - 1u));

        if (c == '\n')
        {
            line[lineLen] = '\0';
            if (lineOverflow)
                Err("LINE", "TOO_LONG");
            else if (lineLen > 0u)
                ProcessLine(line);
            lineLen = 0u;
            lineOverflow = 0u;
        }
        else if (c == '\r' || c == ' ')
        {
            /* ignored (CR of CR/LF line ends, spaces around fields) */
        }
        else if (lineLen < LINE_MAX)
            line[lineLen++] = c;
        else
            lineOverflow = 1u;
    }
}

/* NOTE: keep "USART2 global interrupt" disabled in CubeMX (see file header). */
void USART2_IRQHandler(void)
{
    const uint32_t isr = USART2->ISR;

    if (isr & (USART_ISR_ORE | USART_ISR_FE | USART_ISR_NE | USART_ISR_PE))
        USART2->ICR = USART_ICR_ORECF | USART_ICR_FECF | USART_ICR_NCF | USART_ICR_PECF;

    if (isr & USART_ISR_RXNE)
    {
        const uint8_t b = (uint8_t)USART2->RDR;
        const uint16_t next = (uint16_t)((rxHead + 1u) & (RX_BUF_SIZE - 1u));
        if (next != rxTail)
        {
            rxBuf[rxHead] = b;
            rxHead = next;
        }
    }

    if ((USART2->CR1 & USART_CR1_TXEIE) && (isr & USART_ISR_TXE))
    {
        if (txTail != txHead)
        {
            USART2->TDR = txBuf[txTail];
            txTail = (uint16_t)((txTail + 1u) & (TX_BUF_SIZE - 1u));
        }
        else
            USART2->CR1 &= ~USART_CR1_TXEIE;
    }
}
