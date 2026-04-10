   	TITLE		"Source for CAN-USB4 interface for CBUS"
; filename CAN_USB4.asm  15/09/14
;
; Uses 4 MHz resonator and PLL for 16 MHz clock
; This interface does not have a Node Number



; The setup timer is TMR3. This should not be used for anything else
; CAN bit rate of 125 Kbits/sec
; Standard frame only
; Uses 'Gridconnect' protocol for USB
; Works with FTDI 245AM for now.

;

; added RUN LED switch on.
; no full diagnostics yet.


; Doesn't use interrupts - for speed.
; Working at full speed with minimum CAN frames (no data bytes)
; 390 uSec per frame
; PC gets all frames  08/05/08
; Mod so it sends response to RTR  (FLiM compatibility)
; Fixed CAN_ID at 7E to avoid conflict with CAN_RS
; RTR response removed. Avoids possibility of buffer overflow
; Allows true sniffer capability for checking self enum. of other modules.
; FLiM should never have a CAN_ID of 7E

; This version is based on the CAN_USBm code but changed for the 25K80 and
; for use with the 14K50 as an altenative to Andrew's C code vrsion
; Incorporates ECAN overflow and busy mechanism as in the CAN_CAN
; Working with the 14K50 OK. 17/09/14

;
; Assembly options
	LIST	P=18F26K80,r=hex,N=75,C=120,T=ON

	include		"p18f26K80.inc"

	;definitions  Change these to suit hardware.

#DEFINE CDAV	5
#DEFINE	UREQ	4
#DEFINE CREQ	1
#DEFINE UDAV	0

;set config registers

	;config for 18F26K80

	CONFIG	FCMEN = OFF, FOSC = HS1, IESO = OFF, PLLCFG = ON
	CONFIG	PWRTEN = ON, BOREN = SBORDIS, BORV=0, SOSCSEL = DIG
	CONFIG	WDTEN = OFF,  WDTPS = 128 ;watchdog 512 mSec
	CONFIG	MCLRE = ON, CANMX = PORTB
	CONFIG	BBSIZ = BB1K

	CONFIG	XINST = OFF,STVREN = ON,CP0 = OFF
	CONFIG	CP1 = OFF, CPB = OFF, CPD = OFF,WRT0 = OFF,WRT1 = OFF, WRTB = OFF
	CONFIG 	WRTC = OFF,WRTD = OFF, EBTR0 = OFF, EBTR1 = OFF, EBTRB = OFF



;	processor uses  4 MHz. Resonator




;****************************************************************
;	define RAM storage

	CBLOCK	0		;file registers - access bank
					;interrupt stack for low priority
					;hpint uses fast stack
	W_tempL
	St_tempL
	Bsr_tempL
	PCH_tempH		;save PCH in hpint
	PCH_tempL		;save PCH in lpint (if used)
	Fsr_temp0L
	Fsr_temp0H
	Fsr_temp1L
	Fsr_temp1H
	Fsr_temp2L
	Fsr_hold
	Fsr_holx
	TempCANCON
	TempCANSTAT
	CanID_tmp	;temp for CAN Node ID
	IDtemph		;used in ID shuffle
	IDtempl



	Datmode		;flag for data waiting
	Count		;counter for loading
	Count1
	Latcount	;latency counter

	Temp		;temps
	Temp1
					;the above variables must be in access space (00 to 5F)

	Buffer		;temp buffer in access bank for data
	RXbuf		;:0x1C	USB serial receive packet buffer
	RXbuf1
	RXbuf2
	RXbuf3
	RXbuf4
	RXbuf5
	RXbuf6
	RXbuf7
	RXbuf8
	RXbuf9
	RXbufA
	RXbufB
	RXbufC
	RXbufD
	RXbufE
	RxbufF
	RXbuf10
	RXbuf11
	RXbuf12
	RXbuf13
	RXbuf14
	RXbuf15
	RXbuf16
	RXbuf17
	RXbuf18
	RXbuf19



	ENDC			;ends at 5F



	CBLOCK	h'60'	;rest of bank 0

	Rx0con			;start of receive packet 0
	Rx0sidh
	Rx0sidl
	Rx0eidh
	Rx0eidl
	Rx0dlc
	Rx0d0
	Rx0d1
	Rx0d2
	Rx0d3
	Rx0d4
	Rx0d5
	Rx0d6
	Rx0d7



	Tx0con			;start of transmit frame  0
	Tx0sidh
	Tx0sidl
	Tx0eidh
	Tx0eidl
	Tx0dlc
	Tx0d0
	Tx0d1
	Tx0d2
	Tx0d3
	Tx0d4
	Tx0d5
	Tx0d6
	Tx0d7










	;add variables to suit

		;****************************************************************
	;	used in ASCII to HEX and HEX to ASCII and decimal conversions
	Abyte1		;first ascii char of a hex byte for ascii input
	Abyte2		;second ascii char of a hex byte
	Hbyte1		;first ascii char of a hex byte for ascii output
	Hbyte2
	Atemp		;temp store
	Htemp
	Hexcon		;answer to ascii to hex conversion
	;*************************************************************
	;	used in USB transmit and receive
	Srbyte_n		;number of serial bytes received in packet
	Stbyte_n		;number of serial bytes to send
	TXmode		;state during serial send
	RXmode		;state during serial receive
	RXtemp		;temp store for received byte
	RXnum		;number of chars in receive string
	Datnum		;no. of data bytes in a received frame

	;**************************************************************



	ENDC

	CBLOCK	0x100

	TXbuf		;USB transmit packet buffer to PC
	TXbuf1
	TXbuf2
	TXbuf3
	TXbuf4
	TXbuf5
	TXbuf6
	TXbuf7
	TXbuf8
	TXbuf9
	TXbuf10
	TXbuf11
	TXbuf12
	TXbuf13
	TXbuf14
	TXbuf15
	TXbuf16
	TXbuf17
	Txbuf18
	TXbuf19
	TXbuf20
	TXbuf21
	TXbuf22
	TXbuf23
	TXbuf24
	TXbuf25

	ENDC

;****************************************************************
;
;		start of program code

		ORG		0000h
		nop						;for debug
		goto	setup

		ORG		0008h
		goto	hpint			;high priority interrupt

		ORG		0018h
		goto	lpint			;low priority interrupt


;*******************************************************************

		ORG		0840h			;start of program
;
;
;		high priority interrupt.

hpint	nop
		btfsc	PIR5,IRXIF			;a bus error?
		bra		err
		btfsc	PIR5,ERRIF
		bra		err
		bra		no_err
err
		bsf		CANCON,ABAT			;abort transmission
		bcf		PIR5,ERRIF			;clear interrupts
		bcf		PIR5,IRXIF
		bcf		PIE5,ERRIF

		bcf		PIR5,IRXIF



		retfie	1

no_err
		movlb	.15
		btfss	PIR5,FIFOWMIF,0
		bra		no_fifo
		bcf		PIR5,FIFOWMIF,0		;clear FIFO flag
		bcf		PIR5,4,0			;clear busy frame flag
		bsf		TXB1CON,TXREQ		;send busy frame
		bcf		PIE5,FIFOWMIE,0		;disable FIFO interrupt
		movlb	.14
		bsf		TXBIE,TXB1IE		;enable IRQ for busy frame sent
		bsf		PIE5,4,0			;enable IRQ for busy frame sent
		movlb	0
		retfie	1

no_fifo	bcf		PIR5,4,0			;clear busy frame flag
		movlb	.14
		bcf		TXBIE,TXB1IE		;no busy frame IRQ
		movlb	0
		bsf		PIE5,FIFOWMIE		;wait for next FIFO IRQ

		retfie	1











;**************************************************************
;
;
;		low priority interrupt. (if used)
;

lpint	retfie






;*********************************************************************




main	btfsc	COMSTAT,7			;fast loop for CAN detection
		bra		incan
		btfsc	PORTB,UDAV
		bra		inusb
		bra		main

;		move incoming CAN frame to serial output buffer

incan	movf	CANCON,W			;sort out ECAN buffer
		andlw	B'00001111'
		movwf	TempCANCON
		movf	ECANCON,W
		andlw	B'11110000'
		iorwf	TempCANCON,W
		movwf	ECANCON
		movlw	.13
		movwf	Count
		lfsr	FSR0,RXB0SIDH			;		;start of CAN frame in RB0
		lfsr	FSR1,Rx0sidh
incan1	movff	POSTINC0,POSTINC1		;save ECAN buffer
		decfsz	Count
		bra		incan1
		bcf		RXB0CON,RXFUL
		lfsr	FSR0,Rx0sidh
		lfsr	FSR1,TXbuf		;start of serial string for PC
		movlw	":"				;serial start
		movwf	POSTINC1
		btfsc	Rx0sidl,3		;is it extended
		bra		exide
		movlw	"S"				;standard frames only
		movwf	POSTINC1
		bra		serload
exide	movlw	"X"
		movwf	POSTINC1

serload	movf	POSTINC0,W		;get byte
		call	hexasc			;convert to acsii
		movff	Hbyte1,POSTINC1
		movff	Hbyte2,POSTINC1
		movf	POSTINC0,W		;get byte
		call	hexasc			;convert to acsii
		movff	Hbyte1,POSTINC1
		movff	Hbyte2,POSTINC1
		btfsc	Rx0sidl,3	;is it extended
		bra		exload
		incf	FSR0L			;skip the extended ID bytes
		incf	FSR0L
		bra	serlo1
exload	movf	POSTINC0,W		;get byte
		call	hexasc			;convert to acsii
		movff	Hbyte1,POSTINC1
		movff	Hbyte2,POSTINC1
		movf	POSTINC0,W		;get byte
		call	hexasc			;convert to acsii
		movff	Hbyte1,POSTINC1
		movff	Hbyte2,POSTINC1
serlo1		movff	POSTINC0,Datnum		;get dlc byte
		btfsc	Datnum,6			;is it an RTR
		bra		rtrset
		movlw	"N"
		movwf	POSTINC1
		bra		datbyte
rtrset	movlw	"R"
		movwf	POSTINC1
		bcf		Datnum,6		;Datnum now has just the number
datbyte	tstfsz	Datnum
		bra		datload
		bra		back2
datload	movf	POSTINC0,W		;get byte
		call	hexasc			;convert to acsii
		movff	Hbyte1,POSTINC1
		movff	Hbyte2,POSTINC1
		decfsz	Datnum
		bra		datload
back2	movlw	";"
		movwf	POSTINC1
		movf	FSR1L,W			;get last
		movwf	Count1			;number of bytes to send


		lfsr	FSR1,TXbuf


			;set to output


usbwr	movlw	B'00000000'
		movwf	TRISC


notwr1	btfsc	PORTB,CREQ		;CREQ must be lo to write to USB initially
		bra		notwr1


notwr	bsf		PORTB,CDAV
		btfss	PORTB,CREQ		;CREQ must be hi to write to USB
		bra		notwr
		movff	POSTINC1,PORTC	;output byte
		nop						;settling time
		nop

		bcf		PORTB,CDAV		;flag to USB
		nop
		nop

		decfsz	Count1
		bra		notwr1
		movlw	B'11111111'
		movwf	TRISC			;back to inputs



endwr	bra		main

inusb	clrf	RXmode			;clear receive mode flags
		movlw	B'11111111'
		movwf	TRISC			;set to input
		btfss	PORTB,UDAV		;any USB data?
		bra		notin			;loop

		bsf		PORTB,UREQ		;can take
inusb1	btfsc	PORTB,UDAV		;is data
		bra		inusb1
		nop
		bcf		PORTB,UREQ

		movlw	":"
		subwf	PORTC,W
		bnz		notin			;not start of frame

inusb2	btfss	PORTB,UDAV		;is data
		bra		inusb2
		bsf		PORTB,UREQ
inusb3	btfsc	PORTB,UDAV
		bra		inusb3
		nop
		bcf		PORTB,UREQ

		movlw	"S"			;is it S (standard) or X (extended)
		subwf	PORTC,W
		bz		instd
		movlw	"X"
		subwf	PORTC,W
		bz		inext
		bra		notin			;neither so abort
instd	bcf		RXmode,3		;flag standard
		bra		instart
inext	bsf		RXmode,3		;flag extended
instart		clrf	RXnum		;byte counter
		lfsr	FSR2,RXbuf		;set to start


inloop	btfss	PORTB,UDAV		;read all USB till end
		bra		inloop
		bsf		PORTB,UREQ		;can take
inloop1	btfsc	PORTB,UDAV		;data?
		bra		inloop1
		nop
		bcf		PORTB,UREQ


		movlw	";"				;end?
		subwf	PORTC,W
		bz		lastin
		movff	PORTC,POSTINC2  		;bug fix
		bra		inloop

lastin	movff	PORTC,POSTINC2


		lfsr	FSR2,RXbuf		;point to serial receive buffer
		lfsr	FSR1,Tx0sidh		;point to CAN TX buffer 1  - lowest priority
txload	movff	POSTINC2,Abyte1
		movff	POSTINC2,Abyte2
		call	aschex
		movwf	POSTINC1		;put in CAN TX buffer
		movlw	"N"
		subwf	INDF2,W
		bz		txload1
		movlw	"R"
		subwf	INDF2,W
		bz		txload5
		bra		txload
txload5	bsf		RXmode,2		;flag R
txload1	incf	FSR2L			;miss N or R
		incf	FSR1L			;miss dlc
		btfsc	RXmode,3		;is it ext
		bra		txload2
		incf	FSR1L			;miss out EIDH and EIDL if not extended
		incf	FSR1L

txload2		movlw	";"
		subwf	INDF2,W
		bz		txdone



txload4	movff	POSTINC2,Abyte1
		movff	POSTINC2,Abyte2
		call	aschex
		movwf	POSTINC1		;put in CAN TX buffer
		incf	RXnum,F
		bra		txload2
txdone	movf	RXnum,W			;get number of data bytes
		btfsc	RXmode,2		;is it a RTR
		iorlw	B'01000000'		;set RTR bit
		movwf	Tx0dlc
		movlw	B'00001000'
		btfsc	RXmode,3		;extended?
		iorwf	Tx0sidl,F		;add extended bit
		clrf	RXmode			;ready for next
		movlw	.10
		movwf	Latcount		;ten tries at low priority
		call	sendTX0

notin	bcf		PORTB,UREQ		;clear

		goto	main






;***************************************************************************
;		main setup routine
;*************************************************************************

setup	bcf		WDTCON,SWDTEN	;WDT off during reset
		movlb	0
		clrf	INTCON			;no interrupts yet

		movlb	.15

		clrf	ANCON0			;disable A/D
		clrf	ANCON1
		clrf	CM1CON
		clrf	CM2CON
		setf	WPUB			;pullups set
		movlb	0


		;port settings will be hardware dependent. RB2 and RB3 are for CAN.
		;set S_PORT and S_BIT to correspond to port used for setup.
		;rest are hardware options


		movlw	B'00100000'		;Port A outputs except reset pin
		movwf	TRISA			;
		movlw	B'00001011'		;RB0 is UDAV, RB1 is CREQ,  RB2 = CANTX, RB3 = CANRX, RB4 = UREQ, RB5 = CDAV
								;RB6,7 for debug and ICSP and diagnostic LEDs
		movwf	TRISB
		clrf	PORTB
		bsf		PORTB,2			;CAN recessive
		bcf		PORTB,4			;USB write strobe
		bcf		PORTB,5			;USB read strobe
		movlw	B'11111111'		;Port C  USB interface
		movwf	TRISC

;	next segment is essential.

		clrf	BSR				;set to bank 0
		clrf	EECON1			;no accesses to program memory
		bsf		CANCON,7		;CAN to config mode
		movlw	B'10110000'
		movwf	ECANCON			;CAN mode 2
		bsf		ECANCON,5

		movlb	.15

		clrf	RXB0CON
		clrf	RXB1CON
		bsf		TXB0CON,TXABT		;abort any pending messages
		bsf		TXB1CON,TXABT


		movlb	.14

		clrf	BSEL0			;8 frame FIFO
		clrf	B0CON
		clrf	B1CON
		clrf	B2CON
		clrf	B3CON
		clrf	B4CON
		clrf	B5CON
		bcf		TXBIE,TXB1IE	;no interrupt on busy



		movlw	B'00000011'		;set CAN bit rate at 125000 for now. 4 MHz
		movwf	BRGCON1
		movlw	B'10011110'		;set phase 1 etc
		movwf	BRGCON2
		movlw	B'00000011'		;set phase 2 etc
		movwf	BRGCON3
		movlb	0

		movlw	B'00100000'
		movwf	CIOCON			;CAN to high when off


mskload	lfsr	FSR0,RXM0SIDH		;Clear masks, point to start
mskloop	clrf	POSTINC0
		cpfseq	FSR0L
		bra		mskloop

		bcf		COMSTAT,RXB0OVFL	;clear overflow flags if set
		bcf		COMSTAT,RXB1OVFL
		clrf	PIR5			;clear all flags
		clrf	CANCON			;out of CAN setup mode
		clrf	CCP1CON

		clrf	IPR1			;all peripheral interrupts are low priority
		clrf	IPR2
		clrf	PIE2
		clrf	PIR5			;can FLAGS
		clrf	EEADRH			;clear EEPROM Hi byte



		movlw	B'10001000'		;Config TX1 buffer for busy frame
		movwf	CANCON
		movlb	.15				;buffer in bank 15
		movlw	B'00000011'
		movwf	TXB0CON			;no send yet
		movwf	TXB1CON
		clrf	TXB1SIDH
		clrf	TXB1SIDL
		clrf	TXB1DLC
		movlb	0				;back to bank 0
		clrf	CANCON			;out of CAN setup mode

		movlw	3
		movwf	Tx0con			;set transmit priority

		movlw	B'00100011'
		movwf	IPR3			;high priority CAN RX and Tx error interrupts(for now)
		clrf	IPR1			;all peripheral interrupts are low priority
		clrf	IPR2
		clrf	PIE2

		clrf	INTCON2			;
		clrf	INTCON3			;

		clrf	PIR1
		clrf	PIR2

		clrf	PIR5
		movlw	B'10110001'
		movwf	IPR5			;FIFOHWM and TXB are high priority
		movlw	B'10110001'
		movwf	PIE5			;FIFOHWM IRQ, error interrupts and TX complete only

		bcf		PORTB,6
		bsf		PORTB,7			;put run LED on.
		goto	main



;****************************************************************************
;		start of subroutines

;*****************************************************************************
;		send a busy frame - already preloaded in TX0.

sendTX1	movlb	.15				;set to bank 1
		bsf		TXB1CON,TXREQ	;send immediately
		movlb	0				;back to bank 0
		return
;******************************************************************

;		Send contents of Tx1 buffer via CAN TXB1

sendTX0	movlb	.15				;check for buffer access
tx_loop	btfsc	TXB0CON,TXREQ
		bra	tx_loop
		movlb	0

		lfsr	FSR0,Tx0con
		lfsr	FSR1,TXB0CON
ldTX0	movf	POSTINC0,W
		movwf	POSTINC1	;load TXB1
		movlw	Tx0d7+1
		cpfseq	FSR0L
		bra		ldTX0


		movlb	.15				;bank 15
tx0test	btfsc	TXB0CON,TXREQ	;test if clear to send
		bra		tx0test
		bsf		TXB0CON,TXREQ	;OK so send

tx1done	movlb	0				;bank 0
		return					;successful send



;************************************************************************


;		converts one hex byte to two ascii bytes

hexasc	movwf	Htemp			;save hex.  comes in W
		swapf	Htemp,W
		andlw	B'00001111'		;mask
		addlw	30h
		movwf	Hbyte1
		movlw	39h
		cpfsgt	Hbyte1
		bra		nxtnib
		movlw	7
		addwf	Hbyte1,F
nxtnib	movlw	B'00001111'
		andwf	Htemp,W
		addlw	30h
		movwf	Hbyte2
		movlw	39h
		cpfsgt	Hbyte2
		bra		ascend
		movlw	7
		addwf	Hbyte2,F
ascend	return					;Hbyte1 has high nibble, Hbyte2 has low nibble


;****************************************************************************
;		converts two ascii bytes to one hex byte.
;		for consistency, ascii hi byte in Abyte1, ascii low byte in Abyte2
;		answer in Hexcon

aschex	movlw	30h
		subwf	Abyte1,F
		movlw	9
		cpfsgt	Abyte1
		bra		hinib
		movlw	7
		subwf	Abyte1,F
hinib	movf	Abyte1,W
		movwf	Hexcon
		swapf	Hexcon,F
		movlw	30h
		subwf	Abyte2,F
		movlw	9
		cpfsgt	Abyte2
		bra		hexend
		movlw	7
		subwf	Abyte2,F
hexend	movf	Abyte2,W
		iorwf	Hexcon,W
		return

;


;************************************************************************

		end
