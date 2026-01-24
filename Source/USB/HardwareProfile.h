/*------------------------------------------------------------------------------
; PICFT245
;
; FTDI FT245 replacement in a POC18F14K50 (C) SPROG DCC 2012
;	web:	http://www.sprog-dcc.co.uk
;	e-mail:	sprog@sprog-dcc.co.uk
;-----------------------------------------------------------------------------*/

#ifndef HARDWARE_PROFILE_H
#define HARDWARE_PROFILE_H

/*
 18F14K50 MERG CAN USB 4 pinout

           |----------------------------|
 Power     |1  Vdd                VSS 20| Power
 Xtal      |2  RA5/OSC1        D+/RA0 19| USB
 Xtal      |3  RA4/OSC2        D-/RA1 18| USB
 MCLR      |4  RA3/MCLR          VUSB 17| USB
 D5        |5  RC5/CCP1       AN4/RC0 16| D0
 D4        |6  RC4/P1B        AN5/RC1 15| D1
 D3        |7  RC3/AN7        AN6/RC2 14| D2
 D6        |8  RC6/AN8       AN10/RB4 13| UDAV
 D7        |9  RC7/AN9    RX/AN11/RB5 12| CREQ
 CDAV      |10 RB7/TX             RB6 11| UREQ
           |----------------------------|
*/

//
// Port C
#define DATA_PORT       PORTC
#define DATA_PORTbits   PORTCbits

// Default to inputs
#define PORTC_DDR       0b11111111
#define PORTC_INIT      0b00000000

//
// Port B
//
#define UDAV            RB4   // 
#define CREQ            RB5   // 
#define UREQ            RB6   // 
#define CDAV            RB7   // 

// 
#define PORTB_DDR       0b11000000
#define PORTB_INIT      0b00000000

//
// Port A
//
// USB D+               RA0   // reserved
// USB D-               RA1   // reserved
// [VUSB]               RA2   // reserved
// MCLR                 RA3   // reserved
// OSC2                 RA4   // reserved
// OSC1                 RA5   // reserved

#define PORTA_DDR	0xFF
#define PORTA_INIT	0x00

//
// From low pin count hardware profile
//
    /*******************************************************************/
    /******** USB stack hardware selection options *********************/
    /*******************************************************************/
    //This section is the set of definitions required by the MCHPFSUSB
    //  framework.  These definitions tell the firmware what mode it is
    //  running in, and where it can find the results to some information
    //  that the stack needs.
    //These definitions are required by every application developed with
    //  this revision of the MCHPFSUSB framework.  Please review each
    //  option carefully and determine which options are desired/required
    //  for your application.

    #define self_power          1

    #define USB_BUS_SENSE       1

    /*******************************************************************/
    /******** Application specific definitions *************************/
    /*******************************************************************/

    /** Board definition ***********************************************/
    //These defintions will tell the main() function which board is
    //  currently selected.  This will allow the application to add
    //  the correct configuration bits as wells use the correct
    //  initialization functions for the board.  These defitions are only
    //  required in the stack provided demos.  They are not required in
    //  final application design.

    #define CLOCK_FREQ 48000000
    #define GetSystemClock() CLOCK_FREQ

    /** LED ************************************************************/
    #define mLED_1              
    #define mLED_2              

    #define mGetLED_1()         
    #define mGetLED_2()         

    #define mLED_1_On()         
    #define mLED_2_On()         

    #define mLED_1_Off()        
    #define mLED_2_Off()        
    
    #define mLED_1_Toggle()     
    #define mLED_2_Toggle()     

#endif  //HARDWARE_PROFILE_H
