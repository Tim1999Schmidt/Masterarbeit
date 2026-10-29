/*
 * tle9015.c
 *
 *  Created on: May 22, 2025
 *      Author: stieberger
 */

#include "tle9015.h"
#include <stdio.h>
#include <stdint.h>
#include <math.h>
#include <complex.h>
#include <stdlib.h>   // für rand()
#include <time.h>     // für srand()
#include <string.h>   // für strcpy
#include <stdbool.h>
#include "usart.h"
#include "main.h"

char buffer1[128];
extern msg[50];

const double SENSE_RESISTOR_VALUE = 0.1;

uint8_t read_id		= 0xFF;
uint8_t read_addr	= 0xFF;
uint8_t read_data1	= 0xFF;
uint8_t read_data0	= 0xFF;
uint8_t read_crc	= 0xFF;

uint8_t magnitude_data1 = 0xFF;
uint8_t magnitude_data0 = 0xFF;
uint8_t phase_data1 = 0xFF;
uint8_t phase_data0 = 0xFF;

//Übergabewerte aus main
uint8_t EIS_Chip = 0;
uint8_t Start_Frequenz = 0;
uint8_t Stopp_Frequenz = 0;
uint8_t Amplitude = 0;
uint8_t SinRec = 0;
uint8_t Mittelung = 0;

uint8_t aktuelle_Frequenz; // mit diesem Wert die gewünschte Frequenz wählen

uint8_t TLE9015_CalcCRC(uint8_t *data, uint8_t len) {
	    const uint8_t POLY   = 0x1D;
	    const uint8_t INIT   = 0x00;
	    const uint8_t XOROUT = 0x10;

	    uint8_t crc = INIT;
	    for (uint16_t i = 0; i < len; i++) {
	        crc ^= data[i];
	        for (uint8_t b = 0; b < 8; b++) {
	            if (crc & 0x80)
	                crc = (uint8_t)((crc << 1) ^ POLY);
	            else
	                crc <<= 1;
	        }
	    }
	    return (uint8_t)(crc ^ XOROUT);
	}

uint8_t TLE9015_CalcCRC_for_read(uint8_t *data, uint16_t len){ // das hier nur für Read_Anfragen mit 3 Frames + CRC benutzen
    const uint8_t POLY   = 0x1D;
    const uint8_t INIT   = 0x00;
    const uint8_t XOROUT = 0xF1;

    uint8_t crc = INIT;
    for (uint16_t i = 0; i < len; ++i) {
        crc ^= data[i];
        for (uint8_t b = 0; b < 8; ++b) {
            if (crc & 0x80) {
                crc = (uint8_t)((crc << 1) ^ POLY);
            } else {
                crc <<= 1;
            }
        }
    }
    return (uint8_t)(crc ^ XOROUT);
}

void TLE9015_SendFrame(UART_HandleTypeDef *huart, TLE9015_Frame *frame) {
    uint8_t data[6];
    data[0] = frame->sync;
    data[1] = frame->id;
    data[2] = frame->addr;
    data[3] = frame->data_1;
    data[4] = frame->data_0;
    data[5] = TLE9015_CalcCRC(data, 5); //Berechnung
    HAL_UART_Transmit(huart, data, 6, HAL_MAX_DELAY);
}

void TLE9015_SendFrame_for_read(UART_HandleTypeDef *huart, TLE9015_Frame *frame) { // das hier nur für Read_Anfragen mit 3 Frames + CRC benutzen
    uint8_t data[4];
    data[0] = frame->sync;
    data[1] = frame->id;
    data[2] = frame->addr;
    data[3] = TLE9015_CalcCRC_for_read(data, 3); //Berechnung
    HAL_UART_Transmit(huart, data, 4, HAL_MAX_DELAY);
}

void TLE9015_SendWakeup(UART_HandleTypeDef *huart){ // es werden 6 Einzelimpulse gesendet
	uint8_t data[6];
	data[0] = 0x0F; //sendet 1 impulse
	data[1] = 0x0F; //sendet 1 impulse
	data[2] = 0x0F; //sendet 1 impulse
	data[3] = 0x0F; //sendet 1 impulse
	data[4] = 0x0F; //sendet 1 impulse
	data[5] = 0x0F; //sendet 1 impulse
	HAL_UART_Transmit(huart, data, 6, HAL_MAX_DELAY); //mit dem jeweil ersten und letzten Bit sind es insgesamt 6 Pulse
}

void TLE9015_Send_Enumerating(UART_HandleTypeDef *huart) {
    TLE9015_Frame frame;
    //rücksetzen alter Addressierungswerte
    frame.sync = 0x02;
    frame.id = 0x81;
    frame.addr = 0x25;
    frame.data_1 = 0x00; //rücksetzen alter Addressierungswerte
    frame.data_0 = 0x00; //rücksetzen alter Addressierungswerte
    frame.crc = 0x00;

    TLE9015_SendFrame(huart, &frame);
    DWT_Delay_us(50);
    //rücksetzen alter Addressierungswerte
    frame.sync = 0x02;
    frame.id = 0x82;
    frame.addr = 0x25;
    frame.data_1 = 0x00; //rücksetzen alter Addressierungswerte
    frame.data_0 = 0x00; //rücksetzen alter Addressierungswerte
    frame.crc = 0x00;

    TLE9015_SendFrame(huart, &frame);
    DWT_Delay_us(50);
    //rücksetzen alter Addressierungswerte
    frame.sync = 0x02;
    frame.id = 0x83;
    frame.addr = 0x25;
    frame.data_1 = 0x00; //rücksetzen alter Addressierungswerte
    frame.data_0 = 0x00; //rücksetzen alter Addressierungswerte
    frame.crc = 0x00;

    TLE9015_SendFrame(huart, &frame);
    DWT_Delay_us(50);

    //neue Addressierungswerte
    frame.sync = 0x02;
    frame.id = 0x80; // muss mit 80 beginnen da alle Anfangs id 0000000 haben
    frame.addr = 0x25;
    frame.data_1 = 0x00;
    frame.data_0 = 0x01; //rechter EIS_Chip
    frame.crc = 0x00;

    TLE9015_SendFrame(huart, &frame);
    DWT_Delay_us(50);

    frame.sync = 0x02;
    frame.id = 0x80;
    frame.addr = 0x25;
    frame.data_1 = 0x00;
    frame.data_0 = 0x02; //mittlerer EIS_Chip
    frame.crc = 0x00;

    TLE9015_SendFrame(huart, &frame);
    DWT_Delay_us(50);

    frame.sync = 0x02;
    frame.id = 0x80;
    frame.addr = 0x25;
    frame.data_1 = 0x08; //Final Node setzen
    frame.data_0 = 0x03; //linker EIS_Chip
    frame.crc = 0x00;

    TLE9015_SendFrame(huart, &frame);
    DWT_Delay_us(50);
}

void TLE9015_Send_GOTO_SLEEP_TIMER_reset(UART_HandleTypeDef *huart) { //Watchdog zurücksetzen für jeden EIS-Chip einzeln, da hier Broadcast nicht mehr funktioniert
    TLE9015_Frame frame;
    frame.sync = 0x02;
    frame.id = 0x81;
    frame.addr = 0x02;
    frame.data_1 = 0xFF;
    frame.data_0 = 0xFF;
    frame.crc = 0x00;

    TLE9015_SendFrame(huart, &frame);
    DWT_Delay_us(50);

    frame.sync = 0x02;
    frame.id = 0x82;
    frame.addr = 0x02;
    frame.data_1 = 0xFF;
    frame.data_0 = 0xFF;
    frame.crc = 0x00;

    TLE9015_SendFrame(huart, &frame);
    DWT_Delay_us(50);

    frame.sync = 0x02;
    frame.id = 0x83;
    frame.addr = 0x02;
    frame.data_1 = 0xFF;
    frame.data_0 = 0xFF;
    frame.crc = 0x00;

    TLE9015_SendFrame(huart, &frame);
    DWT_Delay_us(50);
}

void TLE9015_Send_GOTO_SLEEP_TIMER_sleep(UART_HandleTypeDef *huart) { //EIS_Chips auf schlafen schalten
    TLE9015_Frame frame;
    frame.sync = 0x02;
    frame.id = 0x83;
    frame.addr = 0x02;
    frame.data_1 = 0x00;
    frame.data_0 = 0x00;
    frame.crc = 0x00;

    TLE9015_SendFrame(huart, &frame);
    DWT_Delay_us(50);

    frame.sync = 0x02;
    frame.id = 0x82;
    frame.addr = 0x02;
    frame.data_1 = 0x00;
    frame.data_0 = 0x00;
    frame.crc = 0x00;

    TLE9015_SendFrame(huart, &frame);
    DWT_Delay_us(50);

    frame.sync = 0x02;
    frame.id = 0x81;
    frame.addr = 0x02;
    frame.data_1 = 0x0;
    frame.data_0 = 0x00;
    frame.crc = 0x00;

    TLE9015_SendFrame(huart, &frame);
    DWT_Delay_us(50);
}

//###### ab hier EIS ######

// 0 = EIS_Chip1; 1 = EIS_Chip2; 2 = EIS_Chip3; Achtung Reihenfolge Beschriftung der Mechanischen Anordnung ist umgekehrt zur Softwarereihenfolge
uint8_t EIS_Chip_Tab_write [3] = {0x83, 0x82, 0x81}; // 0x83 = EIS_Chip1(Z1); 0x82 = EIS_Chip2(Z2); 0x81 = EIS_Chip3(Z3)
uint8_t EIS_Chip_Tab_read [3] = {0x03, 0x02, 0x01}; // 0x03 = EIS_Chip1(Z1); 0x02 = EIS_Chip2(Z2); 0x01 = EIS_Chip3(Z3)

uint8_t Amplitude_data_1 [6] = {0x05, 0x0B, 0x17, 0x22, 0x2E, 0x3A}; //0x05 für 50mA; 0x0B für 100mA; 0x17 für 200mA; 0x22 für 300mA; 0x2E für 400mA; 0x3A für 500mA
uint8_t Amplitude_data_0 [6] = {0xD4, 0xA9, 0x51, 0xFA, 0xA2, 0x4B}; //0xD4 für 50mA; 0xA9 für 100mA; 0x51 für 200mA; 0xFA für 300mA; 0xA2 für 400mA; 0x4B für 500mA

uint8_t sin_or_rect [2] = {0b0, 0b1}; //{Sin, Rec}

typedef struct{
	int FIS;				// Nummerierung
	float Freq;				// Frequenzwert
    uint8_t fund_reg;        // 2-Bit-Wert (0–3)
    uint8_t freq_div;        // 4-Bit-Wert (0–15)
	double Re_Ergebnis;		// Ergebnis_Realteil
	double Im_Ergebnis;		// Ergebnis_Imaginärteil
}Ergebnis_Tab_Inhalt;

Ergebnis_Tab_Inhalt Ergebnistabelle[52] = {
	{  0, 7812.50, 0b00, 0b0000, 0.000, 0.000 },{  1, 6250.00, 0b01, 0b0000, 0.000, 0.000 },{  2, 5208.33, 0b10, 0b0000, 0.000, 0.000 },{  3, 4464.29, 0b11, 0b0000, 0.000, 0.000 },
	{  4, 3906.25, 0b00, 0b0001, 0.000, 0.000 },{  5, 3125.00, 0b01, 0b0001, 0.000, 0.000 },{  6, 2604.17, 0b10, 0b0001, 0.000, 0.000 },{  7, 2232.14, 0b11, 0b0001, 0.000, 0.000 },
	{  8, 1953.13, 0b00, 0b0010, 0.000, 0.000 },{  9, 1562.50, 0b01, 0b0010, 0.000, 0.000 },{ 10, 1302.08, 0b10, 0b0010, 0.000, 0.000 },{ 11, 1116.07, 0b11, 0b0010, 0.000, 0.000 },
	{ 12,  976.56, 0b00, 0b0011, 0.000, 0.000 },{ 13,  781.25, 0b01, 0b0011, 0.000, 0.000 },{ 14,  651.04, 0b10, 0b0011, 0.000, 0.000 },{ 15,  558.04, 0b11, 0b0011, 0.000, 0.000 },
	{ 16,  488.28, 0b00, 0b0100, 0.000, 0.000 },{ 17,  390.63, 0b01, 0b0100, 0.000, 0.000 },{ 18,  325.52, 0b10, 0b0100, 0.000, 0.000 },{ 19,  279.02, 0b11, 0b0100, 0.000, 0.000 },
	{ 20,  244.14, 0b00, 0b0101, 0.000, 0.000 },{ 21,  195.31, 0b01, 0b0101, 0.000, 0.000 },{ 22,  162.76, 0b10, 0b0101, 0.000, 0.000 },{ 23,  139.51, 0b11, 0b0101, 0.000, 0.000 },
	{ 24,  122.07, 0b00, 0b0110, 0.000, 0.000 },{ 25,   97.66, 0b01, 0b0110, 0.000, 0.000 },{ 26,   81.38, 0b10, 0b0110, 0.000, 0.000 },{ 27,   69.75, 0b11, 0b0110, 0.000, 0.000 },
	{ 28,   61.04, 0b00, 0b0111, 0.000, 0.000 },{ 29,   48.83, 0b01, 0b0111, 0.000, 0.000 },{ 30,   40.69, 0b10, 0b0111, 0.000, 0.000 },{ 31,   34.88, 0b11, 0b0111, 0.000, 0.000 },
	{ 32,   30.52, 0b00, 0b1000, 0.000, 0.000 },{ 33,   24.41, 0b01, 0b1000, 0.000, 0.000 },{ 34,   20.35, 0b10, 0b1000, 0.000, 0.000 },{ 35,   17.44, 0b11, 0b1000, 0.000, 0.000 },
	{ 36,   15.26, 0b00, 0b1001, 0.000, 0.000 },{ 37,   12.21, 0b01, 0b1001, 0.000, 0.000 },{ 38,   10.17, 0b10, 0b1001, 0.000, 0.000 },{ 39,    8.72, 0b11, 0b1001, 0.000, 0.000 },
	{ 40,    7.63, 0b00, 0b1010, 0.000, 0.000 },{ 41,    6.10, 0b01, 0b1010, 0.000, 0.000 },{ 42,    5.09, 0b10, 0b1010, 0.000, 0.000 },{ 43,    4.36, 0b11, 0b1010, 0.000, 0.000 },
	{ 44,    3.81, 0b00, 0b1011, 0.000, 0.000 },{ 45,    3.05, 0b01, 0b1011, 0.000, 0.000 },{ 46,    2.54, 0b10, 0b1011, 0.000, 0.000 },{ 47,    2.18, 0b11, 0b1011, 0.000, 0.000 },
	{ 48,    1.91, 0b00, 0b1100, 0.000, 0.000 },{ 49,    1.53, 0b01, 0b1100, 0.000, 0.000 },{ 50,    1.27, 0b10, 0b1100, 0.000, 0.000 },{ 51,    1.09, 0b11, 0b1100, 0.000, 0.000 }
};

void Reset_Ergebnistabelle(void)
{
    for (int i = 0; i < 52; i++)
    {
        Ergebnistabelle[i].Re_Ergebnis = 0.000;
        Ergebnistabelle[i].Im_Ergebnis = 0.000;
    }
}

//hier Parameter für Register Cx0C eingeben, DB S. 62
uint8_t mux_sel 			= 0b00;     // 2 Bit
uint8_t measurement_time	= 0b111;    // 3 Bit 000 = 3200ms; 001 = 1600ms; 010 = 800ms; 011 = 400ms; 100 = 200ms; 101 = 100ms; 110 = 50 ms; 111 = 25ms
uint8_t freq_div 			= 0b0000;   // 4 Bit
uint8_t fund_freq 			= 0b00;     // 2 Bit
uint8_t settling_time 		= 0b0000;   // 4 Bit


void Zusammenfügen_fuer_0x0C(uint8_t *data_1_high, uint8_t *data_0_low){
    // 16-Bit-Wert zusammensetzen
	freq_div 			= Ergebnistabelle[aktuelle_Frequenz].freq_div;  // 4 Bit hier Werte aus Tabelle entnehmen
	fund_freq 			= Ergebnistabelle[aktuelle_Frequenz].fund_reg;  // 2 Bit hier Werte aus Tabelle entnehmen
    uint16_t doppelByte_fuer_0x0C = 0;
    doppelByte_fuer_0x0C |= ((uint16_t)mux_sel  << 14);
    doppelByte_fuer_0x0C |= ((uint16_t)sin_or_rect [SinRec]  << 13);
    doppelByte_fuer_0x0C |= ((uint16_t)measurement_time << 10);
    doppelByte_fuer_0x0C |= ((uint16_t)freq_div   << 6);
    doppelByte_fuer_0x0C |= ((uint16_t)fund_freq   << 4);
    doppelByte_fuer_0x0C |= ((uint16_t)settling_time << 0);

    // Aufteilen in zwei Bytes
    *data_1_high = (doppelByte_fuer_0x0C >> 8) & 0xFF;  // obere 8 Bits
    *data_0_low  = doppelByte_fuer_0x0C & 0xFF;         // untere 8 Bits
}

void TLE9015_Send_ZMEAS_CFG_0x0C(UART_HandleTypeDef *huart) { //
	uint8_t data_1_Eingabe, data_0_Eingabe;
	Zusammenfügen_fuer_0x0C(&data_1_Eingabe, &data_0_Eingabe);
    TLE9015_Frame frame;
    frame.sync = 0x02;
    frame.id = EIS_Chip_Tab_write [EIS_Chip];//81
    frame.addr = 0x0C;
    frame.data_1 = data_1_Eingabe; //0x02; //00101100
    frame.data_0 = data_0_Eingabe; //0xA0; //11000000
    frame.crc = 0x00;

    TLE9015_SendFrame(huart, &frame);
}

void TLE9015_Send_ZMEAS_AMPLITUDE_0x0A(UART_HandleTypeDef *huart) { //
    TLE9015_Frame frame;
    frame.sync = 0x02;
    frame.id = EIS_Chip_Tab_write [EIS_Chip];//81
    frame.addr = 0x0A;
    frame.data_1 = Amplitude_data_1 [Amplitude]; //0x05 für 50mA; 0x0B für 100mA; 0x17 für 200mA; 0x22 für 300mA; 0x2E für 400mA; 0x3A für 500mA
    frame.data_0 = Amplitude_data_0 [Amplitude]; //0xD4 für 50mA; 0xA9 für 100mA; 0x51 für 200mA; 0xFA für 300mA; 0xA2 für 400mA; 0x4B für 500mA
    frame.crc = 0x00;

    TLE9015_SendFrame(huart, &frame);
}

void TLE9015_Send_ZMEAS_CTRL_0x0D(UART_HandleTypeDef *huart) { // Startet die EIS-Messung
    TLE9015_Frame frame;
    frame.sync = 0x02;
    frame.id = EIS_Chip_Tab_write [EIS_Chip];//81
    frame.addr = 0x0D;
    frame.data_1 = 0x00; //00000000
    frame.data_0 = 0x01; //00000001
    frame.crc = 0x00;

    TLE9015_SendFrame(huart, &frame);
}

void TLE9015_Send_ZMEAS_CTRL_0x0D_reset(UART_HandleTypeDef *huart) { // Reset für EIS-Messung bzw. Stop der EIS-Messung
    TLE9015_Frame frame;
    frame.sync = 0x02;
    frame.id = EIS_Chip_Tab_write [EIS_Chip];//81
    frame.addr = 0x0D;
    frame.data_1 = 0x00; //00000000
    frame.data_0 = 0x00; //00000000
    frame.crc = 0x00;

    TLE9015_SendFrame(huart, &frame);
}

void TLE9015_Send_ZMEAS_MAGNITUDE_0x0E(UART_HandleTypeDef *huart) { // Read-Anfrage
    TLE9015_Frame frame;
    frame.sync = 0x02;
    frame.id = EIS_Chip_Tab_read [EIS_Chip]; //1 //read-comand für EIS 1
    frame.addr = 0x0E;
    frame.crc = 0x00;

    TLE9015_SendFrame_for_read(huart, &frame); //hier müssen nur 4 Frames gesendet werden

    ReadFrame_Blocking();

    magnitude_data1 = read_data1;
    magnitude_data0 = read_data0;
}

void TLE9015_Send_ZMEAS_PHASE_0x0F(UART_HandleTypeDef *huart) { // Read-Anfrage
    TLE9015_Frame frame;
    frame.sync = 0x02;
    frame.id = EIS_Chip_Tab_read [EIS_Chip]; //1 //read-comand für EIS 1
    frame.addr = 0x0F;
    frame.crc = 0x00;

    TLE9015_SendFrame_for_read(huart, &frame); //hier müssen nur 4 Frames gesendet werden

    ReadFrame_Blocking();

    phase_data1 = read_data1;
    phase_data0 = read_data0;
}

void ReadFrame_Blocking()
    {
		HAL_UART_Abort(&huart3);
		//DWT_Delay_us(5); //kann man einfügen aber nicht zwingend
		HAL_UART_Receive(&huart3, &read_id, 1, 1);
		HAL_UART_AbortReceive(&huart3);
		HAL_UART_Receive(&huart3, &read_addr, 1, 1);
		HAL_UART_AbortReceive(&huart3);
		HAL_UART_Receive(&huart3, &read_data1, 1, 1);
		HAL_UART_AbortReceive(&huart3);
		HAL_UART_Receive(&huart3, &read_data0, 1, 1);
		HAL_UART_AbortReceive(&huart3);
		HAL_UART_Receive(&huart3, &read_crc, 1, 1);
		HAL_UART_Abort(&huart3);
    }

void Berechnung_Re_Im(){
    // 1️ 16-Bit-Wert bilden
    uint16_t magnitude_raw = ((uint16_t)magnitude_data1 << 8) | magnitude_data0;

    // 2️ Mantisse und Exponent extrahieren
    uint16_t magnitude_mant = magnitude_raw >> 4;
    uint16_t magnitude_exp  = magnitude_raw & 0x0F;

    // 3️ magnitude berechnen
    double magnitude = magnitude_mant * pow(2.0, -10.0 - (double)magnitude_exp) * SENSE_RESISTOR_VALUE;

    // 4 Phase berechnen
    uint16_t phase_raw = ((uint16_t)phase_data1 << 8) | phase_data0;
    double phase = (phase_raw / 32768.0) * M_PI + M_PI; // Ergebnis in [rad]

    // 5 Komplexer Wert
    //zComplex = magnitude * exp(j*phase)
    double complex zComplex = magnitude * cexp(I * phase); // Ohm

    // 6 Real- und Imaginärteil in mΩ
    double zReal_mOhm      = creal(zComplex) * 1000.0;
    double zImaginary_mOhm = cimag(zComplex) * 1000.0;

    // 7 Ergebnisse in Ergebnisstabelle eintragen
    Ergebnistabelle[aktuelle_Frequenz].Re_Ergebnis = Ergebnistabelle[aktuelle_Frequenz].Re_Ergebnis + zReal_mOhm/Mittelung;
    Ergebnistabelle[aktuelle_Frequenz].Im_Ergebnis = Ergebnistabelle[aktuelle_Frequenz].Im_Ergebnis + zImaginary_mOhm/Mittelung;

}

void Sweep_Messung(){
    //Messungen machen

	Reset_Ergebnistabelle();

	int Wartezeit_nach_Messungsstart = 5000;

	for (uint8_t f = Start_Frequenz; f <= Stopp_Frequenz; f++) {
        aktuelle_Frequenz = f;

        	if (aktuelle_Frequenz <= 23) {Wartezeit_nach_Messungsstart = 50;} //Wartewerte bestimmen wie in Mail von Infineon
        	else if (aktuelle_Frequenz <= 27) {Wartezeit_nach_Messungsstart = 100;}
        	else if (aktuelle_Frequenz <= 31) {Wartezeit_nach_Messungsstart = 200;}
        	else if (aktuelle_Frequenz <= 35) {Wartezeit_nach_Messungsstart = 400;}
        	else if (aktuelle_Frequenz <= 39) {Wartezeit_nach_Messungsstart = 700;}
        	else if (aktuelle_Frequenz <= 43) {Wartezeit_nach_Messungsstart = 1200;}
        	else if (aktuelle_Frequenz <= 47) {Wartezeit_nach_Messungsstart = 2300;}
            else {Wartezeit_nach_Messungsstart = 4500;}

          TLE9015_Send_ZMEAS_CFG_0x0C(&huart3);
          DWT_Delay_us(50); //Pause zwischen Befehlen in us (wichtig)

          TLE9015_Send_ZMEAS_AMPLITUDE_0x0A(&huart3);
          DWT_Delay_us(50); //Pause zwischen Befehlen in us (wichtig)

          for (uint8_t m = 0; m < Mittelung; m++) { // Schleife wie oft die Messung für einen Wert wiederholt wird

          TLE9015_Send_ZMEAS_CTRL_0x0D(&huart3); //Startet EIS-Messung, nur bei eingelegter Zelle aktivieren
          HAL_Delay(Wartezeit_nach_Messungsstart);

          TLE9015_Send_ZMEAS_CTRL_0x0D_reset(&huart3); // resetet bzw. stoppt die EIS-Messung
          DWT_Delay_us(100); //Pause zwischen Befehlen in us (wichtig)

          TLE9015_Send_ZMEAS_MAGNITUDE_0x0E(&huart3); //read_Anfrage, hier längere Pause 100us
          DWT_Delay_us(50); //Pause zwischen Befehlen in us (wichtig)

          TLE9015_Send_ZMEAS_PHASE_0x0F(&huart3); //read_Anfrage
          DWT_Delay_us(50); //Pause zwischen Befehlen in us (wichtig)

          Berechnung_Re_Im();
          DWT_Delay_us(50); //Pause zwischen Befehlen in us (wichtig)

          HAL_Delay(200);

          }
    }

	//Ergebnisse ausgeben
	 sprintf(buffer1,"Anfang Messergebnisse\r\n"); //Signalwort damit Matlab weiß, dass ab hier die Messwerte anfangen
          sendMessage(buffer1);

	for (uint8_t f = Start_Frequenz; f <= Stopp_Frequenz; f++) {

		sprintf(buffer1,
						"%10.2f %12.3f %12.3f\r\n",
						Ergebnistabelle[f].Freq,
						Ergebnistabelle[f].Re_Ergebnis,
						Ergebnistabelle[f].Im_Ergebnis);

		sendMessage(buffer1);
	}

		sprintf(buffer1,"Ende Messergebnisse\r\n"); //Signalwort damit Matlab weiß, dass ab hier die Messwerte enden
	    sendMessage(buffer1);

}

bool Gueltige_Zeichen_Check_EIS(const uint8_t Einstellungen_Parameter[6]) // Überprüft ob Eingehende Parameter im Wertebereich sind
	{
		if (Einstellungen_Parameter[0] < 0 || Einstellungen_Parameter[0] > 2)  return false;   // Bereich 0–2	EIS_Chip
		if (Einstellungen_Parameter[1] < 0 || Einstellungen_Parameter[1] > 51) return false;   // Bereich 0–51	Start_Frequenz
		if (Einstellungen_Parameter[2] < 0 || Einstellungen_Parameter[2] > 51) return false;   // Bereich 0–10	Stopp_Frequenz
		if (Einstellungen_Parameter[3] < 0 || Einstellungen_Parameter[3] > 5)  return false;   // Bereich 0–5	Amplitude
		if (Einstellungen_Parameter[4] < 0 || Einstellungen_Parameter[4] > 1)  return false;   // Bereich 0–1	SinRec
		if (Einstellungen_Parameter[5] < 0 || Einstellungen_Parameter[5] > 9)  return false;   // Bereich 0–9	Mittelung

		if (Einstellungen_Parameter[2] < Einstellungen_Parameter[1])           return false;   // Überprüfen ob Stopp_Frequenz größergleich der Start_Frequenz ist

	    return true;
	}

void EIS_Messung(uint8_t Einstellungen_Parameter[]){

	HAL_Delay(500); // Wartezeit damit der EIS-Chip "hochfahren" kann nachdem durch Verschaltung erstmalig Versorgungsspannung angelegt wurde

	EIS_Chip = Einstellungen_Parameter[0]; // 0 = EIS_Chip1; 1 = EIS_Chip2; 2 = EIS_Chip3
	Start_Frequenz = Einstellungen_Parameter[1];
	Stopp_Frequenz = Einstellungen_Parameter[2];
	Amplitude = Einstellungen_Parameter[3];
	SinRec = Einstellungen_Parameter[4];
	Mittelung = Einstellungen_Parameter[5];

	TLE9015_SendWakeup(&huart3);
	DWT_Delay_us(500); //Pause zwischen Befehlen in us (wichtig)

	TLE9015_Send_Enumerating(&huart3); // hier werden den EIS-Chips die Adressen zugewiesen
	DWT_Delay_us(50); //Pause zwischen Befehlen in us (wichtig)

	TLE9015_Send_GOTO_SLEEP_TIMER_reset(&huart3); // EIS-Chips bleiben 15h wach
	DWT_Delay_us(50); //Pause zwischen Befehlen in us (wichtig)

	Sweep_Messung(); //führt alle Messungen von f_start bis f_stopp aus

	TLE9015_Send_GOTO_SLEEP_TIMER_sleep(&huart3); //EIS_Chips wieder in Schlafmodus versetzen

}
