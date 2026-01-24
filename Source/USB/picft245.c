/*------------------------------------------------------------------------------
; PICFT245
;
; FTDI FT245 replacement for CAN_USB in a PIC18F14K50 (C) SPROG DCC 2012
;	web:	http://www.sprog-dcc.co.uk
;	e-mail:	sprog@sprog-dcc.co.uk
;
; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, version 3 of the License, as set out
; at <http://www.gnu.org/licenses/>.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
; See the GNU General Public License for more details.
;
; As set out in the GNU General Public License, you must retain and acknowledge
; the statements above relating to copyright and licensing. You must also
; state clearly any modifications made.  Please therefore retain this header
; and add documentation of any changes you make. If you distribute a changed
; version, you must make those changes publicly available.
;
; The GNU license requires that if you distribute this software, changed or
; unchanged, or software which includes code from this software, including
; the supply of hardware that incorporates this software, you MUST either
; include the source code or a link to a location where you make the source
; publicly available.
;
------------------------------------------------------------------------------*/

/*------------------------------------------------------------------------------
;
; Revision History
; 21/03/15     1.4 Revert to buffering complete messages rather than send short
;				   packets. Improve handling of USB->CAN and CAN->USB contention.
; 20/09/14     1.3 Fixed deadlock in state USB->CAN state machine
; 25/08/14     1.2 Fixed inconsistent endpoint buffer sizes
; 30/12/12     1.1 Replace CAN->USB state machine with tight loop
;				   Change to Interrupt mode for USB tasks
;				   Pass incoming CBUS chars direct to USBUSART instead of
;				   buffering complete Gridconnect messages
; 20/06/12     1.0 Created
;
;-----------------------------------------------------------------------------*/

#include <p18f14k50.h>

        //14K50
        #pragma config CPUDIV = NOCLKDIV
        #pragma config USBDIV = OFF
        #pragma config FOSC   = HS
        #pragma config PLLEN  = ON
        #pragma config FCMEN  = OFF
        #pragma config IESO   = OFF
        #pragma config PWRTEN = OFF
        #pragma config BOREN  = OFF
        #pragma config BORV   = 30
//        #pragma config VREGEN = ON
        #pragma config WDTEN  = OFF
        #pragma config WDTPS  = 32768
        #pragma config MCLRE  = OFF
        #pragma config HFOFST = OFF
        #pragma config STVREN = ON
        #pragma config LVP    = OFF
        #pragma config XINST  = OFF
        #pragma config BBSIZ  = OFF
        #pragma config CP0    = OFF
        #pragma config CP1    = OFF
        #pragma config CPB    = OFF
        #pragma config WRT0   = OFF
        #pragma config WRT1   = OFF
        #pragma config WRTB   = OFF
        #pragma config WRTC   = OFF
        #pragma config EBTR0  = OFF
        #pragma config EBTR1  = OFF
        #pragma config EBTRB  = OFF

#include <p18f14k50.h>
#include "GenericTypeDefs.h"
#include "Compiler.h"
#include "./USB/usb.h"
#include "./USB/usb_function_cdc.h"
#include "USB/usb_device.h"
#include "USB/usb.h"
#include "usb_config.h"

#include "HardwareProfile.h"
#include "io.h"

#pragma udata
char USB_Out_Buffer[CDC_DATA_OUT_EP_SIZE];
char USB_In_Buffer[CDC_DATA_IN_EP_SIZE];

unsigned char NextUSBOut;
unsigned char NextUSBOut;
unsigned char LastUSBIn;  // Number of characters in the buffer
unsigned char USBcp;       // current position within the buffer
unsigned char USB_In_Data_Rdy;
unsigned char USB_Out_Data_Rdy;
USB_HANDLE  lastTransmission;

unsigned char usb_in;
unsigned char usb_in_state;
#define U_IDLE 0
#define U_IDLE2 1
#define U_RDY 2
#define U_OUT 3

unsigned char can_in;

static void InitializeSystem(void);
void ProcessIO(void);
void USBDeviceTasks(void);
void YourHighPriorityISRCode();
void YourLowPriorityISRCode();
void USBCBSendResume(void);
void UserInit(void);
unsigned char usbGetChar(void);
unsigned char usbIsDataRdy(void);

#pragma udata

#pragma interrupt isr_high
void isr_high(void) {
    #if defined(USB_INTERRUPT)
    	USBDeviceTasks();
    #endif
}	

//
// Low priority interrupt. Not used.
//
#pragma interruptlow isr_low
void isr_low(void) {
	Nop();
	Nop();
}
	
/*
 * Interrupt vectors
 */
#pragma code high_vector=0x8
void HIGH_INT_VECT(void)
{
    _asm GOTO isr_high _endasm
}

#pragma code low_vector=0x18
void LOW_INT_VECT(void)
{
    _asm GOTO isr_low _endasm
}

#pragma code

void main(void)
{
    InitializeSystem();

    #if defined(USB_INTERRUPT)
        if(USB_BUS_SENSE && (USBGetDeviceState() == DETACHED_STATE))
        {
            USBDeviceAttach();
        }
    #endif

    while(1)
    {
        // Application-specific tasks.
        // Application related code may be added here, or in the ProcessIO() function.
        ProcessIO();

		// Non-blocking state machine to handle USB -> CAN
		switch (usb_in_state) {
			case U_IDLE:
				// Wait until data is received from host
				if (usbIsDataRdy()) {
					usb_in = usbGetChar();
					PORTBbits.UDAV = 1;
					usb_in_state = U_RDY;
				}
				break;
				
			case U_IDLE2:
				// usb_in already holds a byte received from USB but CAN PIC started a transfer
				// to USB before we could send the byte in usb_in to CAN. Spin around here and
				// U_RDY waiting for UREQ handshake when the transfer to USB has finished.
				usb_in_state = U_RDY;
				break;
				
			case U_RDY:
				if (PORTBbits.UREQ && (PORTBbits.CDAV == 0)) {
					// CAN PIC is ready to receive and has nothing to send to USB.
					Nop();
					// Drive data bits out
					TRISC = 0;
					Nop();
					PORTC = usb_in;
					Nop();
					PORTBbits.UDAV = 0;
					usb_in_state = U_OUT;
				} else if (PORTBbits.CDAV == 1) {
					// CAN PIC has a CAN frame to send to USB so give it priority. 
					// CAN PIC uses a tight loop to send data to USB so this can only happen
					// at the beginning of a frame, not in the maiddle of a frame.
					usb_in_state = U_IDLE2;
				}
				break;
			
			case U_OUT:
				// Wait for CAN interface to acknowledge data
				if (PORTBbits.UREQ == 0) {
					TRISC = 0xFF;
					usb_in_state = U_IDLE;
				}
				break;
		}
		
	    if ((usb_in_state == U_IDLE) || (usb_in_state == U_IDLE2)) {
		    // USB->CAN handshke is idle
			if (PORTBbits.CDAV && (NextUSBOut < CDC_DATA_OUT_EP_SIZE-1)) {
				// CAN PIC has data available and will send it in tight loop to keep
				// the CAN buffers as empty as possible, so we loop here until the whole
				// packet is received.
				PORTBbits.CREQ = 1;
				while (PORTBbits.CDAV == 1) {
					// wait for handshake
					;
				}	
				Nop();
				Nop();
				// put data into buffer and append a zero
				USB_Out_Buffer[NextUSBOut] = PORTC;
				if (PORTC == ';') {
					// Received ';' so send the complete gridconnect packet
					USB_Out_Data_Rdy = 1;
				}
				PORTBbits.CREQ = 0;
				NextUSBOut++;
				USB_Out_Buffer[NextUSBOut] = 0;
			} else if (NextUSBOut >= CDC_DATA_OUT_EP_SIZE-1) {
				// Should never happen, but send the buffer if it fills up
				USB_Out_Data_Rdy = 1;
			}
		}
	}
}


/********************************************************************
 * Function:        static void InitializeSystem(void)
 *
 * PreCondition:    None
 *
 * Input:           None
 *
 * Output:          None
 *
 * Side Effects:    None
 *
 * Overview:        InitializeSystem is a centralize initialization
 *                  routine. All required USB initialization routines
 *                  are called from here.
 *
 *                  User application initialization routine should
 *                  also be called from here.
 *
 * Note:            None
 *******************************************************************/
static void InitializeSystem(void)
{
    unsigned char i;

    PORTC = PORTC_INIT;
    PORTB = PORTB_INIT;
    PORTA = PORTA_INIT;

    // Port pull-ups
    WPUA = 0x38;
    WPUB = 0xF0;

    TRISC = PORTC_DDR;
    TRISB = PORTB_DDR;
    TRISA = PORTA_DDR;

    USB_In_Data_Rdy = 0;
    USB_Out_Data_Rdy = 0;
    ANSEL = 0;                 // Default all pins to digital
    ANSELH = 0;

    INTCON = 0;

    // 	 Initialize the arrays
    for (i=0; i<sizeof(USB_Out_Buffer); i++)
    {
        USB_Out_Buffer[i] = 0;
    }

    NextUSBOut = 0;
    LastUSBIn = 0;
    lastTransmission = 0;
    
    usb_in_state = U_IDLE;

    USBDeviceInit();	//usb_device.c.  Initializes USB module SFRs and firmware
                        //variables to known states.
}



/******************************************************************************
 * Function:        void mySetLineCodingHandler(void)
 *
 * PreCondition:    USB_CDC_SET_LINE_CODING_HANDLER is defined
 *
 * Input:           None
 *
 * Output:          None
 *
 * Side Effects:    None
 *
 * Overview:        This function gets called when a SetLineCoding command
 *                  is sent on the bus.  This function will evaluate the request
 *                  and determine if the application should update the baudrate
 *                  or not.
 *
 * Note:
 *
 *****************************************************************************/
#if defined(USB_CDC_SET_LINE_CODING_HANDLER)
void mySetLineCodingHandler(void)
{

}
#endif

/********************************************************************
 * Function:        void ProcessIO(void)
 *
 * PreCondition:    None
 *
 * Input:           None
 *
 * Output:          None
 *
 * Side Effects:    None
 *
 * Overview:        This function is a place holder for other user
 *                  routines. It is a mixture of both USB and
 *                  non-USB tasks.
 *
 * Note:            None
 *******************************************************************/
void ProcessIO(void)
{
    // User Application USB tasks
    if((USBDeviceState < CONFIGURED_STATE)||(USBSuspendControl==1)) { return; }

    // If the previous USB data has been consumed, check for new data from USB.
    if (USB_In_Data_Rdy == 0) {
        LastUSBIn = getsUSBUSART(USB_In_Buffer, CDC_DATA_IN_EP_SIZE);
        if(LastUSBIn > 0)
        {
            USB_In_Data_Rdy = 1;	// signal buffer full
            USBcp = 0;  			// Reset the current position
        }
    }

    // Send data to USB
    if((USBUSARTIsTxTrfReady()) && USB_Out_Data_Rdy) {
        putUSBUSART(&USB_Out_Buffer[0], NextUSBOut);
        NextUSBOut = 0;
		USB_Out_Data_Rdy = 0;
    }

    CDCTxService();
}		//end ProcessIO

/*
 * usbIsDataRdy()
 *
 * Check if there is any data available
 */
unsigned char usbIsDataRdy(void) {
    if (USB_In_Data_Rdy) {
        return 1;
    } else {
        return 0;
    }
}

/*
 * usbGetChar()
 *
 * Get data from the input buffer
 */
unsigned char usbGetChar(void) {
    unsigned char ret = 0;
    if(USB_In_Data_Rdy) {
        ret = USB_In_Buffer[USBcp];
        ++USBcp;
        if (USBcp == LastUSBIn)
			// All of the data has been consumed
            USB_In_Data_Rdy = 0;
    }
    return ret;
}


// ******************************************************************************************************
// ************** USB Callback Functions ****************************************************************
// ******************************************************************************************************
// The USB firmware stack will call the callback functions USBCBxxx() in response to certain USB related
// events.  For example, if the host PC is powering down, it will stop sending out Start of Frame (SOF)
// packets to your device.  In response to this, all USB devices are supposed to decrease their power
// consumption from the USB Vbus to <2.5mA each.  The USB module detects this condition (which according
// to the USB specifications is 3+ms of no bus activity/SOF packets) and then calls the USBCBSuspend()
// function.  You should modify these callback functions to take appropriate actions for each of these
// conditions.  For example, in the USBCBSuspend(), you may wish to add code that will decrease power
// consumption from Vbus to <2.5mA (such as by clock switching, turning off LEDs, putting the
// microcontroller to sleep, etc.).  Then, in the USBCBWakeFromSuspend() function, you may then wish to
// add code that undoes the power saving things done in the USBCBSuspend() function.

// The USBCBSendResume() function is special, in that the USB stack will not automatically call this
// function.  This function is meant to be called from the application firmware instead.  See the
// additional comments near the function.

/******************************************************************************
 * Function:        void USBCBSuspend(void)
 *
 * PreCondition:    None
 *
 * Input:           None
 *
 * Output:          None
 *
 * Side Effects:    None
 *
 * Overview:        Call back that is invoked when a USB suspend is detected
 *
 * Note:            None
 *****************************************************************************/
void USBCBSuspend(void)
{
    //Example power saving code.  Insert appropriate code here for the desired
    //application behavior.  If the microcontroller will be put to sleep, a
    //process similar to that shown below may be used:

    //ConfigureIOPinsForLowPower();
    //SaveStateOfAllInterruptEnableBits();
    //DisableAllInterruptEnableBits();
    //EnableOnlyTheInterruptsWhichWillBeUsedToWakeTheMicro();	//should enable at least USBActivityIF as a wake source
    //Sleep();
    //RestoreStateOfAllPreviouslySavedInterruptEnableBits();	//Preferrably, this should be done in the USBCBWakeFromSuspend() function instead.
    //RestoreIOPinsToNormal();									//Preferrably, this should be done in the USBCBWakeFromSuspend() function instead.

    //IMPORTANT NOTE: Do not clear the USBActivityIF (ACTVIF) bit here.  This bit is
    //cleared inside the usb_device.c file.  Clearing USBActivityIF here will cause
    //things to not work as intended.


 
}



/******************************************************************************
 * Function:        void USBCBWakeFromSuspend(void)
 *
 * PreCondition:    None
 *
 * Input:           None
 *
 * Output:          None
 *
 * Side Effects:    None
 *
 * Overview:        The host may put USB peripheral devices in low power
 *					suspend mode (by "sending" 3+ms of idle).  Once in suspend
 *					mode, the host may wake the device back up by sending non-
 *					idle state signalling.
 *
 *					This call back is invoked when a wakeup from USB suspend
 *					is detected.
 *
 * Note:            None
 *****************************************************************************/
void USBCBWakeFromSuspend(void)
{
    // If clock switching or other power savings measures were taken when
    // executing the USBCBSuspend() function, now would be a good time to
    // switch back to normal full power run mode conditions.  The host allows
    // a few milliseconds of wakeup time, after which the device must be
    // fully back to normal, and capable of receiving and processing USB
    // packets.  In order to do this, the USB module must receive proper
    // clocking (IE: 48MHz clock must be available to SIE for full speed USB
    // operation).
}

/********************************************************************
 * Function:        void USBCB_SOF_Handler(void)
 *
 * PreCondition:    None
 *
 * Input:           None
 *
 * Output:          None
 *
 * Side Effects:    None
 *
 * Overview:        The USB host sends out a SOF packet to full-speed
 *                  devices every 1 ms. This interrupt may be useful
 *                  for isochronous pipes. End designers should
 *                  implement callback routine as necessary.
 *
 * Note:            None
 *******************************************************************/
void USBCB_SOF_Handler(void)
{
    // No need to clear UIRbits.SOFIF to 0 here.
    // Callback caller is already doing that.
}

/*******************************************************************
 * Function:        void USBCBErrorHandler(void)
 *
 * PreCondition:    None
 *
 * Input:           None
 *
 * Output:          None
 *
 * Side Effects:    None
 *
 * Overview:        The purpose of this callback is mainly for
 *                  debugging during development. Check UEIR to see
 *                  which error causes the interrupt.
 *
 * Note:            None
 *******************************************************************/
void USBCBErrorHandler(void)
{
    // No need to clear UEIR to 0 here.
    // Callback caller is already doing that.

    // Typically, user firmware does not need to do anything special
    // if a USB error occurs.  For example, if the host sends an OUT
    // packet to your device, but the packet gets corrupted (ex:
    // because of a bad connection, or the user unplugs the
    // USB cable during the transmission) this will typically set
    // one or more USB error interrupt flags.  Nothing specific
    // needs to be done however, since the SIE will automatically
    // send a "NAK" packet to the host.  In response to this, the
    // host will normally retry to send the packet again, and no
    // data loss occurs.  The system will typically recover
    // automatically, without the need for application firmware
    // intervention.

    // Nevertheless, this callback function is provided, such as
    // for debugging purposes.
}


/*******************************************************************
 * Function:        void USBCBCheckOtherReq(void)
 *
 * PreCondition:    None
 *
 * Input:           None
 *
 * Output:          None
 *
 * Side Effects:    None
 *
 * Overview:        When SETUP packets arrive from the host, some
 * 					firmware must process the request and respond
 *					appropriately to fulfill the request.  Some of
 *					the SETUP packets will be for standard
 *					USB "chapter 9" (as in, fulfilling chapter 9 of
 *					the official USB specifications) requests, while
 *					others may be specific to the USB device class
 *					that is being implemented.  For example, a HID
 *					class device needs to be able to respond to
 *					"GET REPORT" type of requests.  This
 *					is not a standard USB chapter 9 request, and
 *					therefore not handled by usb_device.c.  Instead
 *					this request should be handled by class specific
 *					firmware, such as that contained in usb_function_hid.c.
 *
 * Note:            None
 *******************************************************************/
void USBCBCheckOtherReq(void)
{
    USBCheckCDCRequest();
}//end


/*******************************************************************
 * Function:        void USBCBStdSetDscHandler(void)
 *
 * PreCondition:    None
 *
 * Input:           None
 *
 * Output:          None
 *
 * Side Effects:    None
 *
 * Overview:        The USBCBStdSetDscHandler() callback function is
 *					called when a SETUP, bRequest: SET_DESCRIPTOR request
 *					arrives.  Typically SET_DESCRIPTOR requests are
 *					not used in most applications, and it is
 *					optional to support this type of request.
 *
 * Note:            None
 *******************************************************************/
void USBCBStdSetDscHandler(void)
{
    // Must claim session ownership if supporting this request
}//end


/*******************************************************************
 * Function:        void USBCBInitEP(void)
 *
 * PreCondition:    None
 *
 * Input:           None
 *
 * Output:          None
 *
 * Side Effects:    None
 *
 * Overview:        This function is called when the device becomes
 *                  initialized, which occurs after the host sends a
 * 					SET_CONFIGURATION (wValue not = 0) request.  This
 *					callback function should initialize the endpoints
 *					for the device's usage according to the current
 *					configuration.
 *
 * Note:            None
 *******************************************************************/
void USBCBInitEP(void)
{
    CDCInitEP();
}

/********************************************************************
 * Function:        void USBCBSendResume(void)
 *
 * PreCondition:    None
 *
 * Input:           None
 *
 * Output:          None
 *
 * Side Effects:    None
 *
 * Overview:        The USB specifications allow some types of USB
 * 					peripheral devices to wake up a host PC (such
 *					as if it is in a low power suspend to RAM state).
 *					This can be a very useful feature in some
 *					USB applications, such as an Infrared remote
 *					control	receiver.  If a user presses the "power"
 *					button on a remote control, it is nice that the
 *					IR receiver can detect this signalling, and then
 *					send a USB "command" to the PC to wake up.
 *
 *					The USBCBSendResume() "callback" function is used
 *					to send this special USB signalling which wakes
 *					up the PC.  This function may be called by
 *					application firmware to wake up the PC.  This
 *					function will only be able to wake up the host if
 *                  all of the below are true:
 *					
 *					1.  The USB driver used on the host PC supports
 *						the remote wakeup capability.
 *					2.  The USB configuration descriptor indicates
 *						the device is remote wakeup capable in the
 *						bmAttributes field.
 *					3.  The USB host PC is currently sleeping,
 *						and has previously sent your device a SET 
 *						FEATURE setup packet which "armed" the
 *						remote wakeup capability.   
 *
 *                  If the host has not armed the device to perform remote wakeup,
 *                  then this function will return without actually performing a
 *                  remote wakeup sequence.  This is the required behavior, 
 *                  as a USB device that has not been armed to perform remote 
 *                  wakeup must not drive remote wakeup signalling onto the bus;
 *                  doing so will cause USB compliance testing failure.
 *                  
 *					This callback should send a RESUME signal that
 *                  has the period of 1-15ms.
 *
 * Note:            This function does nothing and returns quickly, if the USB
 *                  bus and host are not in a suspended condition, or are 
 *                  otherwise not in a remote wakeup ready state.  Therefore, it
 *                  is safe to optionally call this function regularly, ex: 
 *                  anytime application stimulus occurs, as the function will
 *                  have no effect, until the bus really is in a state ready
 *                  to accept remote wakeup. 
 *
 *                  When this function executes, it may perform clock switching,
 *                  depending upon the application specific code in 
 *                  USBCBWakeFromSuspend().  This is needed, since the USB
 *                  bus will no longer be suspended by the time this function
 *                  returns.  Therefore, the USB module will need to be ready
 *                  to receive traffic from the host.
 *
 *                  The modifiable section in this routine may be changed
 *                  to meet the application needs. Current implementation
 *                  temporary blocks other functions from executing for a
 *                  period of ~3-15 ms depending on the core frequency.
 *
 *                  According to USB 2.0 specification section 7.1.7.7,
 *                  "The remote wakeup device must hold the resume signaling
 *                  for at least 1 ms but for no more than 15 ms."
 *                  The idea here is to use a delay counter loop, using a
 *                  common value that would work over a wide range of core
 *                  frequencies.
 *                  That value selected is 1800. See table below:
 *                  ==========================================================
 *                  Core Freq(MHz)      MIP         RESUME Signal Period (ms)
 *                  ==========================================================
 *                      48              12          1.05
 *                       4              1           12.6
 *                  ==========================================================
 *                  * These timing could be incorrect when using code
 *                    optimization or extended instruction mode,
 *                    or when having other interrupts enabled.
 *                    Make sure to verify using the MPLAB SIM's Stopwatch
 *                    and verify the actual signal on an oscilloscope.
 *******************************************************************/
void USBCBSendResume(void)
{
    static WORD delay_count;
    
    //First verify that the host has armed us to perform remote wakeup.
    //It does this by sending a SET_FEATURE request to enable remote wakeup,
    //usually just before the host goes to standby mode (note: it will only
    //send this SET_FEATURE request if the configuration descriptor declares
    //the device as remote wakeup capable, AND, if the feature is enabled
    //on the host (ex: on Windows based hosts, in the device manager 
    //properties page for the USB device, power management tab, the 
    //"Allow this device to bring the computer out of standby." checkbox 
    //should be checked).
    if(USBGetRemoteWakeupStatus() == TRUE) 
    {
        //Verify that the USB bus is in fact suspended, before we send
        //remote wakeup signalling.
        if(USBIsBusSuspended() == TRUE)
        {
            USBMaskInterrupts();
            
            //Clock switch to settings consistent with normal USB operation.
            USBCBWakeFromSuspend();
            USBSuspendControl = 0; 
            USBBusIsSuspended = FALSE;  //So we don't execute this code again, 
                                        //until a new suspend condition is detected.

            //Section 7.1.7.7 of the USB 2.0 specifications indicates a USB
            //device must continuously see 5ms+ of idle on the bus, before it sends
            //remote wakeup signalling.  One way to be certain that this parameter
            //gets met, is to add a 2ms+ blocking delay here (2ms plus at 
            //least 3ms from bus idle to USBIsBusSuspended() == TRUE, yeilds
            //5ms+ total delay since start of idle).
            delay_count = 3600U;        
            do
            {
                delay_count--;
            }while(delay_count);
            
            //Now drive the resume K-state signalling onto the USB bus.
            USBResumeControl = 1;       // Start RESUME signaling
            delay_count = 1800U;        // Set RESUME line for 1-13 ms
            do
            {
                delay_count--;
            }while(delay_count);
            USBResumeControl = 0;       //Finished driving resume signalling

            USBUnmaskInterrupts();
        }
    }
}


/*******************************************************************
 * Function:        void USBCBEP0DataReceived(void)
 *
 * PreCondition:    ENABLE_EP0_DATA_RECEIVED_CALLBACK must be
 *                  defined already (in usb_config.h)
 *
 * Input:           None
 *
 * Output:          None
 *
 * Side Effects:    None
 *
 * Overview:        This function is called whenever a EP0 data
 *                  packet is received.  This gives the user (and
 *                  thus the various class examples a way to get
 *                  data that is received via the control endpoint.
 *                  This function needs to be used in conjunction
 *                  with the USBCBCheckOtherReq() function since 
 *                  the USBCBCheckOtherReq() function is the apps
 *                  method for getting the initial control transfer
 *                  before the data arrives.
 *
 * Note:            None
 *******************************************************************/
#if defined(ENABLE_EP0_DATA_RECEIVED_CALLBACK)
void USBCBEP0DataReceived(void)
{
}
#endif

/*******************************************************************
 * Function:        BOOL USER_USB_CALLBACK_EVENT_HANDLER(
 *                        USB_EVENT event, void *pdata, WORD size)
 *
 * PreCondition:    None
 *
 * Input:           USB_EVENT event - the type of event
 *                  void *pdata - pointer to the event data
 *                  WORD size - size of the event data
 *
 * Output:          None
 *
 * Side Effects:    None
 *
 * Overview:        This function is called from the USB stack to
 *                  notify a user application that a USB event
 *                  occured.  This callback is in interrupt context
 *                  when the USB_INTERRUPT option is selected.
 *
 * Note:            None
 *******************************************************************/
BOOL USER_USB_CALLBACK_EVENT_HANDLER(int event, void *pdata, WORD size)
{
    switch(event)
    {
        case EVENT_TRANSFER:
            //Add application specific callback task or callback function here if desired.
            break;
        case EVENT_SOF:
            USBCB_SOF_Handler();
            break;
        case EVENT_SUSPEND:
            USBCBSuspend();
            break;
        case EVENT_RESUME:
            USBCBWakeFromSuspend();
            break;
        case EVENT_CONFIGURED: 
            USBCBInitEP();
            break;
        case EVENT_SET_DESCRIPTOR:
            USBCBStdSetDscHandler();
            break;
        case EVENT_EP0_REQUEST:
            USBCBCheckOtherReq();
            break;
        case EVENT_BUS_ERROR:
            USBCBErrorHandler();
            break;
        case EVENT_TRANSFER_TERMINATED:
            //Add application specific callback task or callback function here if desired.
            //The EVENT_TRANSFER_TERMINATED event occurs when the host performs a CLEAR
            //FEATURE (endpoint halt) request on an application endpoint which was 
            //previously armed (UOWN was = 1).  Here would be a good place to:
            //1.  Determine which endpoint the transaction that just got terminated was 
            //      on, by checking the handle value in the *pdata.
            //2.  Re-arm the endpoint if desired (typically would be the case for OUT 
            //      endpoints).
            break;
        default:
            break;
    }      
    return TRUE; 
}

/** EOF main.c *************************************************/

