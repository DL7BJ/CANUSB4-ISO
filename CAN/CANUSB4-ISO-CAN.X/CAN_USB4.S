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

processor   18F26K80
radix	    hex
	
; #include "pic18f26k80.inc" no need for pic-as, xc.inc does it
#include <xc.inc>	

; definitions  Change these to suit hardware.

#define CDAV	0 // Orgigina RB5
#define	UREQ	1 // Original RB4
#define CREQ	4 // Original RB1
#define UDAV	5 // Original RB0
	
#define ABAT	4
#define TXREQ	3
#define REQOP2	7
#define RXFUL	7
#define EXIDE	3
#define TXB1IE	3
#define TXABT	6
    
#define LED_GREEN   7
#define LED_YELLOW  6
	
;=========================================================
; Configuration Registers
; Target: PIC18F26K80
;=========================================================
; processor uses 4 MHz. Resonator
;---------------------------------------------------------
; Oscillator & Clock Configuration
;---------------------------------------------------------
CONFIG  FOSC    = HS1        ; High-Speed Crystal / External Clock  / 4MHz Quartz
CONFIG  PLLCFG  = ON         ; 4x PLL enabled (for higher CPU clock)/ 16MHz
CONFIG  IESO    = OFF        ; No internal/external oscillator switchover
CONFIG  FCMEN   = OFF        ; Fail-Safe Clock Monitor disabled
;---------------------------------------------------------
; Power & Reset Behavior
;---------------------------------------------------------
CONFIG  PWRTEN  = ON         ; Power-up Timer enabled
CONFIG  BOREN   = SBORDIS    ; Brown-out Reset enabled, controlled by software
CONFIG  BORV    = 0          ; Brown-out Reset voltage (lowest threshold)
CONFIG  SOSCSEL = DIG        ; Secondary oscillator pins used as digital I/O
;---------------------------------------------------------
; Watchdog Timer
;---------------------------------------------------------
CONFIG  WDTEN   = OFF        ; Watchdog Timer disabled
CONFIG  WDTPS   = 128        ; Prescaler (only relevant if WDT enabled)
                             ; ? 512 ms typical
;---------------------------------------------------------
; Pin & Peripheral Configuration
;---------------------------------------------------------
CONFIG  MCLRE   = ON        ; MCLR pin enabled (external reset)
CONFIG  CANMX   = PORTB     ; CAN RX/TX on RB2/RB3
CONFIG  BBSIZ   = BB1K      ; Boot Block size = 1 Kword
;---------------------------------------------------------
; CPU Core Options
;---------------------------------------------------------
CONFIG  XINST   = OFF        ; Extended instruction set disabled
CONFIG  STVREN  = ON         ; Stack overflow/underflow causes reset
;---------------------------------------------------------
; Code Protection
;---------------------------------------------------------
CONFIG  CP0     = OFF
CONFIG  CP1     = OFF
CONFIG  CPB     = OFF
CONFIG  CPD     = OFF
;---------------------------------------------------------
; Write Protection
;---------------------------------------------------------
CONFIG  WRT0    = OFF
CONFIG  WRT1    = OFF
CONFIG  WRTB    = OFF
CONFIG  WRTC    = OFF
CONFIG  WRTD    = OFF
;---------------------------------------------------------
; Table Read Protection
;---------------------------------------------------------
CONFIG  EBTR0   = OFF
CONFIG  EBTR1   = OFF
CONFIG  EBTRB   = OFF
;****************************************************************
; Define RAM storage
;			     
; Access-Bank, low RAM	    0x00 ? 0x5F	    direct ,a
; Bank 0 RAM (Rx0/Tx0)	    0x60 ? 0x7F	    Bank 0 movlb 0 or BANKMASK
; Bank 1 RAM (ASCII/HEX)    0x7C ? 0x82	    Bank 0 0x60?0xBF 
; Banked RAM, TXbuf	    0x100 ? 0x119   Bank 1 movlb 1 or BANKMASK
; file registers - access bank
; interrupt stack for low priorit
; hpint uses fast stack

; Access Bank 0 0x00 - 0x5F
     
			     
PSECT udata_acs, global, class=COMRAM, space=1, delta=1
    W_templ: DS 1
    St_tempL: DS 1
    Bsr_tempL: DS 1
    PCH_tempH: DS 1
    PCH_tempL: DS 1
    Fsr_temp0L: DS 1
    Fsr_temp0H: DS 1
    Fsr_temp1L: DS 1
    Fsr_temp1H: DS 1
    Fsr_hold: DS 1
    Fsr_holx: DS 1
    TempCANCON: DS 1
    TempCANSTAT: DS 1
    CanID_tmp: DS 1
    IDtemph: DS 1
    IDtempl: DS 1
    Datmode: DS 1
    Count: DS 1
    Count1: DS 1
    Latcount: DS 1
    Temp: DS 1
    Temp1: DS 1
    Buffer: DS 1
    ; RX Buffer 20 Bytes
    RXbuf:
    RXbuf1: 
    RXbuf2:
    RXbuf3:
    RXbuf4:
    RXbuf5:
    RXbuf6:
    RXbuf7:
    RXbuf8:
    RXbuf9:
    RXbufA:
    RXbufB:
    RXbufC:
    RXbufD:
    RXbufE:
    RXbufF:
    RXbuf10:
    RXBuf11:
    RXBuf12:
    RXBuf13:
    RXBuf14:
    RXBuf15:
    RXBuf16:
    RXBuf17:
    RXBuf18:
    RXBuf19:
    	DS 20

; Bank 0 0x60
PSECT udata_bank0, global, class=BANK0, space=1, delta=1
    Rx0con: DS 1
    Rx0sidh: DS 1
    Rx0sidl: DS 1
    Rx0eidh: DS 1
    Rx0eidl: DS 1
    Rx0dlc: DS 1
    Rx0d0: 
    Rx0d1: 
    Rx0d2: 
    Rx0d3: 
    Rx0d4:
    Rx0d5:
    Rx0d6:
    Rx0d7:
	DS 8
    Tx0con: DS 1           ; start of transmit frame 0
    Tx0sidh: DS 1
    Tx0sidl: DS 1
    Tx0eidh: DS 1
    Tx0eidl: DS 1
    Tx0dlc: DS 1
    Tx0d0:
    Tx0d1:
    Tx0d2:
    Tx0d3:
    Tx0d4:
    Tx0d5:
    Tx0d6:
    Tx0d7:
	DS 8
    ; ASCII / HEX conversion
    Abyte1: DS 1	    ; first ascii char of a hex byte for ascii input
    Abyte2: DS 1
    Hbyte1: DS 1	    ; first ascii char of a hex byte for ascii output
    Hbyte2: DS 1
    Atemp: DS 1		    ; temp store
    Htemp: DS 1		
    Hexcon: DS 1	    ; answer to ascii to hex conversion

    ; USB transmit/receive state variables
    Srbyte_n: DS 1	        ; number of serial bytes received in packet
    Stbyte_n: DS 1		; number of serial bytes to send
    TXmode: DS 1		; state during serial send
    RXmode: DS 1		; state during serial receive
    RXtemp: DS 1		; temp store for received byte
    RXnum: DS 1			; number of chars in receive string
    Datnum: DS 1		; number of data bytes in received frame

    ; ****************************************************************
    ; TX Buffer start 0x100, banked RAM 0x100 - 0x119 Bank 1
    PSECT udata_bank1, global, class=BANK1, space=1, delta=1
    TXbuf:			; USB transmit packet buffer to PC
    TXbuf1:
    TXbuf2:
    TXbuf3:
    TXbuf4:
    TXbuf5:
    TXbuf6:
    TXbuf7:
    TXbuf8:
    TXbuf9:
    TXbuf10:
    TXbuf11:
    TXbuf12:
    TXbuf13:
    TXbuf14:
    TXbuf15:
    TXbuf16:
    TXbuf17:
    TXbuf18:
    TXbuf19:
    TXbuf20:
    TXbuf21:
    TXbuf22:
    TXbuf23:
    TXbuf24:
    TXbuf25:
	DS 26

PSECT code
;*******************************************************************
; Start of Program
;*******************************************************************
        ORG     0x0000		    ; Reset Vector
        nop                     ; optional für Debug
        goto    setup           ; springe zur Setup-Routine

        ORG     0x0008		    ; High-Priority Interrupt Vector
        goto    hpint           ; High-Priority Interrupt

        ORG     0x0018		    ; Low-Priority Interrupt Vector
        goto    lpint           ; Low-Priority Interrupt
;*******************************************************************
; Program Start
;*******************************************************************
	ORG	0840h		    ; start of program
;---------------------------------------------
; High-Priority Interrupt
;---------------------------------------------
hpint:
    nop                         ; optional, kleine Verzögerung
    ; --- Prüfe Bus- und CAN-Fehler ---
    btfsc   IRXIF               ; wenn IRXIF=0, überspringe nächsten Befehl
    bra     err                 ; Fehler aufgetreten, springe zu err
    btfsc   ERRIF               ; wenn ERRIF=0, überspringe nächsten Befehl
    bra     err                 ; Fehler aufgetreten, springe zu err
    ; --- Kein Fehler ---
    bra     no_err
;---------------------------------------------
; Fehlerbehandlung
;---------------------------------------------
err:    
    bsf     BANKMASK(CANCON), ABAT, a 
                                    ; Transmission abbrechen
    bcf     ERRIF                   ; Interrupt-Flag ERRIF löschen
    bcf     IRXIF                   ; Interrupt-Flag IRXIF löschen
    retfie  1                       ; Rückkehr aus High-Priority Interrupt	
no_err:
    ; --- Bank 15 aktivieren ---
    movlb   15                      ; Access Latch auf Bank 15                             
    ; --- FIFO-Flag prüfen ---
    btfss   FIFOWMIF                ; Prüfe FIFO Watermark Interrupt Flag
    bra     no_fifo                 ; wenn nicht gesetzt, springe zu no_fifo
    ; --- FIFO-Flag löschen ---
    bcf     FIFOWMIF                ; FIFO-Interrupt-Flag zurücksetzen
    bcf     PIR5,4,0                ; busy frame Flag löschen (PIR5 Bit4)
    ; --- Frame zum Senden markieren ---
    bsf     BANKMASK(TXB1CON), TXREQ, a  
                                    ; TXREQ-Bit setzen -> CAN-Frame senden
    ; --- FIFO-Interrupt deaktivieren ---
    bcf     FIFOWMIE                ; temporär FIFO Interrupt deaktivieren
    bsf     BANKMASK(TXBIE), TXB1IE,a  
                                    ; TXB1 Interrupt Enable setzen
    bsf     PIE5,4,a                ; globalen Interrupt aktivieren für busy frame
    ; --- Bank zurücksetzen auf Bank 0 ---
    movlb   0
    ; --- Interrupt-Rückkehr ---
    retfie  1                       ; Return from High-Priority Interrupt
no_fifo:	
    bcf     PIR5,4,a                ; busy frame Flag löschen (PIR5 Bit4)   
    movlb   0                       ; zurück auf Bank 0
    bsf     FIFOWMIE                ; FIFO Watermark Interrupt wieder aktivieren    
    retfie  1                       ; Rückkehr aus High-Priority-Interrupt
    
; **************************************************************
; Low Priority Interrupt (currently not used)
; **************************************************************
lpint:
        retfie                   ; return from low priority interrupt

;*****************************************************************************
; Main Loop
; Purpose:  Poll CAN and USB interfaces, transfer frames to serial output
;****************************************************************************
main:
    
    ; btg PORTB, UREQ     ; Toggle RB1
    ; btg PORTB, CDAV     ; Toggle RB0
    bcf     PORTB, LED_YELLOW, a        ; turn off LED_YELLOW
    bcf     PORTB, LED_GREEN, a         ; turn off LED_GREEN
    ; -----------------------------
    ; Check for incoming CAN frame
    ; -----------------------------
    btfsc   BANKMASK(COMSTAT), 7, b     ; RXFUL? (CAN receive buffer full)
    bra     incan                       ; handle incoming CAN frame
    ; -----------------------------
    ; Check for incoming USB data
    ; -----------------------------
    btfsc   PORTB, UDAV, a              ; USB data available?
    bra     inusb                       ; handle USB input
    ; -----------------------------
    ; Stay in polling loop if nothing to do
    ; -----------------------------
    bra     main
;*****************************************************************************
; Copy incoming CAN frame to serial output buffer
;*****************************************************************************
incan:
    ; -----------------------------
    ; Prepare CAN control bytes
    ; -----------------------------
    bsf     PORTB, LED_GREEN, a             ; turn on LED_GREEN
    bsf     BANKMASK(CANCON), REQOP2, a     ; Set REQOP2 bit (access bank)
    movf    BANKMASK(CANCON), W, a          ; Read CANCON
    andlw   0b00001111                      ; Keep lower 4 bits only
    movwf   TempCANCON, a                   ; Store temporarily
    movf    BANKMASK(ECANCON), W, a
    andlw   0b11110000                      ; Keep upper 4 bits only
    iorwf   TempCANCON, W, a                ; Combine with TempCANCON
    movwf   BANKMASK(ECANCON), a            ; Write back to ECANCON
    ; -----------------------------
    ; Setup loop counter and frame pointers
    ; -----------------------------
    movlw   13
    movwf   Count, a                        ; Loop counter
    movlw   BANKMASK(RXB0SIDH)
    movwf   FSR0, a                         ; FSR0 -> CAN RX buffer (source)
    movlw   BANKMASK(Rx0sidh)
    movwf   FSR1, a                         ; FSR1 -> Temp buffer (destination)
; -----------------------------
; Copy CAN frame byte-by-byte
; -----------------------------
incan1:
    movff   POSTINC0, POSTINC1              ; move byte from FSR0 to FSR1
    decfsz  Count, f, a
    bra     incan1
    ; -----------------------------
    ; Clear RX buffer full flag
    ; -----------------------------
    bcf     BANKMASK(RXB0CON), RXFUL, a
    ; -----------------------------
    ; Setup pointers for serial output
    ; -----------------------------
    lfsr    0, Rx0sidh                      ; FSR0 -> start of CAN RX frame
    lfsr    1, TXbuf                        ; FSR1 -> USB output buffer
    ; Start-of-frame marker
    movlw   ":"
    movwf   POSTINC1, a
    ; -----------------------------
    ; Check frame type: extended or standard
    ; -----------------------------
    btfsc   BANKMASK(Rx0sidl), EXIDE, b   ; Extended frame?
    bra     exide
    ; Standard frame
    movlw   "S"
    movwf   POSTINC1, a
    bra     serload
exide:
    movlw   "X"
    movwf   POSTINC1, a
serload:
    ; -----------------------------
    ; Convert frame bytes to ASCII
    ; -----------------------------
    movf    POSTINC0, W, a
    call    hexasc
    movff   Hbyte1, POSTINC1
    movff   Hbyte2, POSTINC1
    movf    POSTINC0, W, a
    call    hexasc
    movff   Hbyte1, POSTINC1
    movff   Hbyte2, POSTINC1
    ; Skip extended ID bytes if necessary
    btfsc   Rx0sidl, 3, b
    bra     exload
    incf    FSR0L, a
    incf    FSR0L, a
    bra     serlo1
exload:
    movf    POSTINC0, W, a
    call    hexasc
    movff   Hbyte1, POSTINC1
    movff   Hbyte2, POSTINC1
    movf    POSTINC0, W, a
    call    hexasc
    movff   Hbyte1, POSTINC1
    movff   Hbyte2, POSTINC1
serlo1:
    movff   POSTINC0, Datnum           ; DLC byte
    btfsc   Datnum, 6, a               ; is it an RTR frame?
    bra     rtrset
    movlw   "N"
    movwf   POSTINC1, a
    bra     datbyte
rtrset:
    movlw   "R"
    movwf   POSTINC1, a
    bcf     Datnum, 6, a               ; clear RTR bit in Datnum
datbyte:
    tstfsz  Datnum, a
    bra     datload
    bra     back2
datload:
    movf    POSTINC0, W, a
    call    hexasc
    movff   Hbyte1, POSTINC1
    movff   Hbyte2, POSTINC1
    decfsz  Datnum, a
    bra     datload
back2:
    movlw   ";"
    movwf   POSTINC1, a

    movf    FSR1L, W, a
    movwf   Count1, a                  ; number of bytes to send
    lfsr    1, TXbuf                   ; reset FSR1 to start of output
; -----------------------------
; Send serial data to USB
; -----------------------------
usbwr:
    movlw   0b00000000
    movwf   TRISC, a                    ; configure PORTC as output
notwr1:
    btfsc   PORTB, CREQ, a              ; CREQ must be low initially
    bra     notwr1
notwr:
    bsf     PORTB, CDAV, a
    btfss   PORTB, CREQ, a              ; wait for CREQ high
    bra     notwr
    movff   POSTINC1, PORTC             ; output byte
    nop
    nop
    bcf     PORTB, CDAV, a
    nop
    nop
    decfsz  Count1, a
    bra     notwr1
    movlw   0b11111111
    movwf   TRISC, a                    ; restore PORTC as input
endwr:
    bra     main
;*****************************************************************************
; Handle incoming USB data
;*****************************************************************************
inusb:
    bsf     PORTB, LED_YELLOW, a        ; turn on LED_YELLOW   
    clrf    RXmode, a                   ; clear receive flags
    movlw   0b11111111
    movwf   TRISC, a                    ; all PORTC pins input
    btfss   PORTB, UDAV, a              ; wait for data
    bra     notin
    bsf     PORTB, UREQ, a              ; request USB access
inusb1:
    btfsc   PORTB, UDAV, a
    bra     inusb1
    nop
    bcf     PORTB, UREQ, a
    movlw   ":"
    subwf   PORTC, W, a
    bnz     notin                      ; not start of frame
; -----------------------------
; Check frame type from USB: S (standard) or X (extended)
; -----------------------------
inusb2:
    btfss   PORTB, UDAV, a
    bra     inusb2
    bsf     PORTB, UREQ, a
inusb3:
    btfsc   PORTB, UDAV, a
    bra     inusb3
    nop
    bcf     PORTB, UREQ, a
    movlw   "S"
    subwf   PORTC, W, a
    bz      instd
    movlw   "X"
    subwf   PORTC, W, a
    bz      inext
    bra     notin
instd:
    bcf     RXmode, 3, a               ; standard frame
    bra     instart
inext:
    bsf     RXmode, 3, a               ; extended frame
instart:
    clrf    RXnum, a                   ; byte counter
    lfsr    2, RXbuf                   ; FSR2 -> start of serial receive buffer
; -----------------------------
; Read USB bytes into RX buffer
; -----------------------------
inloop:
    btfss   PORTB, UDAV, a
    bra     inloop
    bsf     PORTB, UREQ, a
inloop1:
    btfsc   PORTB, UDAV, a
    bra     inloop1
    nop
    bcf     PORTB, UREQ, a
    movlw   ";"
    subwf   PORTC, W, a
    bz      lastin
    movff   PORTC, POSTINC2
    bra     inloop
lastin:
    movff   PORTC, POSTINC2
; -----------------------------
; Convert USB input to CAN TX buffer
; -----------------------------
    lfsr    2, RXbuf                   ; reset FSR2 to serial input buffer
    lfsr    1, Tx0sidh                 ; FSR1 -> CAN TX buffer (lowest priority)
txload:
    movff   POSTINC2, Abyte1
    movff   POSTINC2, Abyte2
    call    aschex
    movwf   POSTINC1, a                 ; put byte in CAN TX buffer
    movlw   "N"
    subwf   INDF2, W, a
    bz      txload1
    movlw   "R"
    subwf   INDF2, W, a
    bz      txload5
    bra     txload
txload5:
    bsf     RXmode, 2, a               ; set RTR flag
txload1:
    incf    FSR2L, a                   ; skip 'N' or 'R'
    incf    FSR1L, a                   ; skip DLC byte
    btfsc   RXmode, 3, a               ; extended frame?
    bra     txload2
    incf    FSR1L, a                   ; skip EIDH/EIDL for standard
    incf    FSR1L, a
txload2:
    movlw   ";"
    subwf   INDF2, W, a
    bz      txdone
txload4:
    movff   POSTINC2, Abyte1
    movff   POSTINC2, Abyte2
    call    aschex
    movwf   POSTINC1, a
    incf    RXnum, F, a
    bra     txload2
txdone:
    movf    RXnum, W, a
    btfsc   RXmode, 2, a               ; is RTR?
    iorlw   0b01000000
    movwf   Tx0dlc, a

    movlw   0b00001000
    btfsc   RXmode, 3, a               ; extended frame?
    iorwf   Tx0sidl, F, a

    clrf    RXmode, a                   ; reset flags
    movlw   10
    movwf   Latcount, a                 ; ten tries at low priority
    call    sendTX0
notin:
    bcf     PORTB, UREQ, a
    bcf     PORTB, LED_YELLOW, a        ; turn off LED_GREEN
    goto    main
;*****************************************************************************
; Routine: setup
; Purpose:  Main setup routine for PIC18 CBUS node
;           - Disable watchdog
;           - Configure ports and CAN module
;           - Clear flags and interrupts
;****************************************************************************
setup:
    ; -----------------------------
    ; Disable watchdog and interrupts
    ; -----------------------------
    bcf     WDTCON, 0, a        ; WDT off during reset
    movlb   0
    clrf    INTCON, a           ; disable all interrupts for now
    ; -----------------------------
    ; Disable analog and comparators
    ; -----------------------------
    movlb   15
    clrf    ANCON0, a           ; disable ADC on AN pins
    clrf    ANCON1, a
    clrf    CM1CON, a           ; disable comparators
    clrf    CM2CON, a
    ; -----------------------------
    ; Enable weak pull-ups
    ; -----------------------------
    setf    WPUB, a             ; enable pull-ups on PORTB
    movlb   0
    ; Port configuration depends on hardware
    ; RB2 = CANTX, RB3 = CANRX
    ; Other pins used for USB, debug LEDs, etc.
    movlw   0b00100000          ; Port A outputs except reset pin
    movwf   TRISA, a
    movlw   0b00111000          ; Configure PORTB directions
    ; RB5 = UDAV input
    ; RB4 = CREQ input
    ; RB2 = CANTX output
    ; RB3 = CANRX input
    ; RB1 = UREQ output
    ; RB0 = CDAV output
    ; RB6, RB7 = debug, ICSP, diagnostic LEDs
    movwf   TRISB, a
    clrf    PORTB, a            ; clear PORTB
    bsf     PORTB, 2, a         ; CAN recessive
    bcf     PORTB, UREQ, a      ; USB write strobe inactive
    bcf     PORTB, CDAV, a      ; USB read strobe inactive
    movlw   0b11111111          ; Port C for USB interface
    movwf   TRISC, a  
    ; -----------------------------
    ; Initialize CAN module and buffers
    ; -----------------------------
    clrf    BSR, a              ; select bank 0
    clrf    EECON1, a           ; no program memory access
    bsf     CANCON, 7, a        ; put CAN in configuration mode
    movlw   0b10110000          ; CAN mode 2
    movwf   ECANCON, a
    bsf     ECANCON, 5, a
    movlb   15
    clrf    RXB0CON, a          ; reset CAN RX buffers
    clrf    RXB1CON, a
    bsf     TXB0CON, TXABT, a   ; abort any pending TX
    bsf     TXB1CON, TXABT, a
    movlb   14
    clrf    BSEL0, b            ; 8-frame FIFO selection
    clrf    B0CON, b
    clrf    B1CON, b
    clrf    B2CON, b
    clrf    B3CON, b
    clrf    B4CON, b
    clrf    B5CON, b
    bcf     TXBIE, TXB1IE, b    ; disable interrupt on busy TX buffer
    ; -----------------------------
    ; Set CAN bit rate (125 kbit/s @ 4 MHz)
    ; -----------------------------
    movlw   0b00000011
    movwf   BRGCON1, b
    movlw   0b10011110
    movwf   BRGCON2, b
    movlw   0b00000011
    movwf   BRGCON3, b

    movlb   0
    movlw   0b00100000
    movwf   CIOCON, a            ; CAN idle high when off
    ; -----------------------------
    ; Clear RX masks
    ; -----------------------------
mskload:
    lfsr    0, RXM0SIDH          ; FSR0 -> start of RX mask
mskloop:
    clrf    POSTINC0, a
    cpfseq  FSR0L, a
    bra     mskloop
    ; -----------------------------
    ; Clear flags and peripheral settings
    ; -----------------------------
    movlb   15
    bcf     COMSTAT, 7, a        ; clear overflow flags
    bcf     COMSTAT, 7, a
    clrf    PIR5, a               ; clear CAN flags
    clrf    CANCON, a             ; exit CAN setup
    clrf    CCP1CON, a
    clrf    IPR1, a               ; peripheral interrupts low priority
    clrf    IPR2, a
    clrf    PIE2, a
    clrf    PIR5, a
    clrf    EEADRH, a             ; clear EEPROM high byte
    ; -----------------------------
    ; Configure TX1 buffer for busy frame
    ; -----------------------------
    movlw   0b10001000
    movwf   CANCON, a
    movlb   15
    movlw   0b00000011
    movwf   TXB0CON, b           ; no send yet
    movwf   TXB1CON, b
    clrf    TXB1SIDH, b
    clrf    TXB1SIDL, b
    clrf    TXB1DLC, b
    movlb   0
    ; clrf    CANCON, a            ; exit CAN setup mode
    movlw   3
    movwf   Tx0con, a            ; set TX0 priority
    movlw   0b00100011
    movwf   IPR3, a              ; high-priority CAN RX & TX error
    clrf    IPR1, a
    clrf    IPR2, a
    clrf    PIE2, a
    clrf    INTCON2, a
    clrf    INTCON3, a
    clrf    PIR1, a
    clrf    PIR2, a
    clrf    PIR5, a
    movlw   0b10110001
    movwf   IPR5, a              ; FIFOHWM & TXB high priority
    movlw   0b10110001
    movwf   PIE5, a              ; FIFOHWM IRQ, errors, TX complete only
    
    bsf     INTCON, 7; PEIE
    bsf     INTCON, 6; GIEH

    bsf     PORTB, LED_YELLOW, a ; turn on  LED_YELLOW   
    bsf     PORTB, LED_GREEN, a  ; turn on  LED_GREEN
    goto    main                 ; jump to main loop
;****************************************************************************
;			    Start of subroutines		
;*****************************************************************************
; Routine: sendTX1
; Purpose:  Send a preloaded CAN busy frame in TXB1
; Input:    TXB1 buffer already contains frame data
;****************************************************************************
sendTX1:
    movlb   15			; Select Bank 15 (CAN SFRs)
    bsf     TXB1CON, TXREQ, b	; Set TXREQ to send immediately
    movlb   0			; Return to Bank 0
    return
;*****************************************************************************
; Routine: sendTX0
; Purpose:  Send contents of Tx0 buffer via CAN TXB0
; Input:    Tx0con..Tx0d7 in Bank 0
;****************************************************************************
sendTX0:
    movlb   15			; Select Bank 15 for CAN SFR access
tx_loop:
    btfsc   TXB0CON, TXREQ, b	; Wait until TXB0 buffer is free
    bra     tx_loop
    movlb   0			; Switch back to Bank 0 for RAM access
    lfsr    0, Tx0con		; FSR0 -> source buffer start
    lfsr    1, TXB0CON		; FSR1 -> target CAN TXB0
ldTX0:
    movf    POSTINC0, W, a      ; Load byte from source (FSR0)
    movwf   POSTINC1, a         ; Store byte into target (FSR1)
    movlw   Tx0d7+1             ; Loop limit for Tx0d0..Tx0d7
    cpfseq  FSR0L, a
    bra     ldTX0
    movlb   15			; Switch to Bank 15 for CAN SFRs
tx0test:
    btfsc   TXB0CON, TXREQ, b	; Wait until TXB0 is ready
    bra     tx0test
    bsf     TXB0CON, TXREQ, b	; Set TXREQ to start transmission
tx1done:
    movlb   0			; Return to Bank 0
    return			; Transmission done successfully
;****************************************************************************
; Routine: hexasc
; Purpose: Converts one hex byte into two ASCII characters
; Input:   W = 8-bit hex value
; Output:  Hbyte1 = ASCII high nibble
;          Hbyte2 = ASCII low nibble
;****************************************************************************
hexasc:
    ; -----------------------------
    ; Save input
    ; -----------------------------
    movwf   Htemp, a           ; Save hex value

    ; -----------------------------
    ; Convert high nibble
    ; -----------------------------
    swapf   Htemp, W, a        ; Move high nibble to low position
    andlw   0b00001111         ; Mask only the nibble
    addlw   30h                ; ASCII '0' base
    movwf   Hbyte1, a          ; Tentative ASCII
    movlw   39h
    cpfsgt  Hbyte1, a          ; > '9' ?
    bra     nxtnib             ; If yes, already a letter
    movlw   7
    addwf   Hbyte1, F, a       ; Adjust for letters ('A'-'F')
nxtnib:
    ; -----------------------------
    ; Convert low nibble
    ; -----------------------------
    movlw   0b00001111
    andwf   Htemp, W, a        ; Mask low nibble
    addlw   30h                ; ASCII '0' base
    movwf   Hbyte2, a          ; Tentative ASCII
    movlw   39h
    cpfsgt  Hbyte2, a          ; > '9' ?
    bra     ascend             ; If yes, already a letter
    movlw   7
    addwf   Hbyte2, F, a       ; Adjust for letters ('A'-'F')
ascend:
    return                      ; Hbyte1 = high nibble ASCII, Hbyte2 = low nibble ASCII
;****************************************************************************
; Routine: aschex
; Purpose: Converts two ASCII characters representing a hex byte into one byte
; Input:   Abyte1 = ASCII high nibble ('0'-'9','A'-'F','a'-'f')
;          Abyte2 = ASCII low nibble
; Output:  Hexcon = 8-bit hex value
;****************************************************************************
aschex:
    ; -----------------------------
    ; Convert high nibble
    ; -----------------------------
    movlw   30h               ; ASCII '0'
    subwf   Abyte1, F, a      ; Abyte1 - '0' 
    movlw   9
    cpfsgt  Abyte1, a         ; Compare: > 9 ?
    bra     hinib              ; If yes, already a letter, skip adjustment    
    ; Adjust for letters ('A'-'F')
    movlw   7
    subwf   Abyte1, a
hinib:
    movf    Abyte1, W, a      ; Load high nibble into W
    movwf   Hexcon, a         ; Store in result
    swapf   Hexcon, F, a      ; Shift high nibble to upper half
    ; -----------------------------
    ; Convert low nibble
    ; -----------------------------
    movlw   30h
    subwf   Abyte2, F, a      ; ASCII '0' subtraction
    movlw   9
    cpfsgt  Abyte2, a         ; Compare: > 9 ?
    bra     hexend             ; If yes, already a letter    
    ; Adjust for letters ('A'-'F')
    movlw   7
    subwf   Abyte2, F, a
hexend:
    movf    Abyte2, W, a
    iorwf   Hexcon, W, a      ; Combine low nibble into result
    return   
;************************************************************************
    end
