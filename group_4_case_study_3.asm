 
	list P=16F747          
	title "On-Off Control"
;***********************************************************
;				On- Off Control
;***********************************************************


		#include <P16F747.INC>
	__config _CONFIG1, _FOSC_HS & _CP_OFF & _DEBUG_OFF & _VBOR_2_0 & _BOREN_0 & _MCLR_ON & _PWRTE_ON & _WDT_OFF
	__config _CONFIG2, _BORSEN_0 & _IESO_OFF & _FCMEN_OFF

Temp	equ	21h     ; Holds temporary value
Temp2	equ	22h   
Value	equ 23h		; Holds bit indicating second try of mode 4
Octal	equ 24h     ; Holds a bit at the nth position, where n is the current mode
Timer	equ	25h     ; Holds how many increments of 0.5 seconds we wait for.
Timer0	equ	26h     ; Timer0, 1, 2 contain values so as to set the increment to 0.5 seconds
Timer1	equ	27h
Timer2	equ	28h
Start
	org		00h 
	goto 	SwitchCheck
	org 	04h
	goto 	isrService
	org 	15h

SwitchCheck
	call 	initPort 		; Initialize registers
	goto	waitPress  		; Wait for button press


; ====================== Button Presses ===================== ;


waitPress
	btfss 	PORTC, 7 		; See if green button is pressed
	call 	GreenPress 		
	btfss 	PORTC, 6 	    ; See if red button is pressed	
	call 	RedPress 		
	goto 	waitPress 		

GreenPress
	call 	SwitchDelay 	; Let switch debounce
	btfsc 	PORTC, 7 		; See if green button is still pressed
	return 					
GreenRelease
	btfss 	PORTC, 7 		; See if green button released
	goto 	GreenRelease	
	bcf		PORTD, 7        ; New mode, turn off main transistor
	bcf		PORTD, 6        ; New mode, turn off reduced transistor
	goto	ModeRead		; Read the Octal switch and set the mode

RedPress
	call 	SwitchDelay 	
	btfsc 	PORTC, 6 		
	return					
RedRelease
	btfss 	PORTC, 6 		
	goto 	RedRelease 		
	goto	RedAction       ; Check the mode, and take corresponding action


; ====================== Read octal, and set mode ===================== ;


ModeRead
	clrf	Octal
	comf	PORTE, W        ; Complement output of octal switch
	andlw	H'07'           ; Zero out bits 4-7 included
	bsf		STATUS, C       ; Set status bit - will be rotated to position corresponding to the mode
	movwf	Temp
	incf	Temp            ; Rotate once for mode 0, twice for mode 1, etc...
	call	SetOctal        ; Rotate the bit to mode position 
	call	PrintMode       ; Print mode to LEDs, fault if mode 0, 5-7 included
	return

SetOctal
	rlf		Octal           ; Rotate bit through carry bit
	decfsz	Temp, F         ; Decrement
	goto	SetOctal
	return

PrintMode                   ; Print mode to LEDs, fault if mode 0, 5-7 included
	btfsc	Octal, 0
	goto	Hard_Fault
	btfsc	Octal, 1
	movlw	H'01'
	btfsc	Octal, 2
	movlw	H'02'
	btfsc	Octal, 3
	movlw	H'03'
	btfsc	Octal, 4
	movlw	H'04'
	btfsc	Octal, 5
	goto	Hard_Fault
	btfsc	Octal, 6
	goto	Hard_Fault
	btfsc	Octal, 7
	goto	Hard_Fault
	movwf	PORTB
	return


; ====================== Hard Faults ===================== ;


Hard_Fault                  ; Check current mode, and print to LEDs fault at that mode
	bcf		PORTD, 6
	bcf		PORTD, 7
	btfsc	Octal, 0
	movlw	H'08'
	btfsc	Octal, 1
	movlw	H'09'
	btfsc	Octal, 2
	movlw	H'0A'
	btfsc	Octal, 3
	movlw	H'0B'
	btfsc	Octal, 4
	movlw	H'0C'
	btfsc	Octal, 5
	movlw	H'0D'
	btfsc	Octal, 6
	movlw	H'0E'
	btfsc	Octal, 7
	movlw	H'0F'
	movwf	PORTB	
	goto	Hard_Fault


; ====================== Actions on Red ===================== ;


RedAction                   ; Read current mode, and send PC to start of the corresponding action
	btfsc	Octal, 1
	goto	Mode_1_On_Red
	btfsc	Octal, 2
	goto	Mode_2_On_Red
	btfsc	Octal, 3
	goto	Mode_3_On_Red
	btfsc	Octal, 4
	goto	Mode_4_On_Red
	return


; ====================== Mode 1 Action ===================== ;


Mode_1_On_Red
	movlw	B'10000000'
	xorwf	PORTD, 1
	return


; ====================== Mode 2 Action ===================== ;


Mode_2_On_Red
	call	A_to_D          ; Read pot value, store in Timer variable
	bsf		PORTD, 7		; Turn on main transistor
Loop_Once
	call	timeLoop		; Keep it on for given Time
	btfss 	PORTC,6 		; see if red button pressed
	goto 	Mode_2_RedPress ; Start sequence to potentially reset timer
Discard_RedPress
	decfsz	Timer, 1
	goto	Loop_Once
	bcf		PORTD, 7		; Turn Off Main transistor
	return                  ; Return to red/green presses loop

A_to_D
	call 	initAD 				; call to initialize A/D
	call 	SwitchDelay 		; delay for Tad (see data sheet) prior to A/D start
	bsf 	ADCON0,GO 			; start A/D conversion
A_to_D_Wait
	btfsc 	ADCON0,GO 			; check if A/D is finished
	goto 	A_to_D_Wait 		; loop right here until A/D finished
	btfsc 	ADCON0,GO 			; make sure A/D finished
	goto 	A_to_D_Wait 		; A/D not finished, continue to loop
	movf 	ADRESH, W  			; get A/D value
	movwf	Timer				; Get A/D in Timer register.
	btfsc	STATUS, Z           ; Hard fault if pot value is zero
	goto	Hard_Fault
	bcf		STATUS, C           ; Clear the carry bit
	rrf		Timer, F            ; Divide timer value by two
	return

initAD
	bsf 	STATUS,RP0 	; select register bank 1
	movlw 	B'00001110' ; RA0 analog input, all other digital
	movwf 	ADCON1 		; move to special function A/D register
	bcf 	STATUS,RP0 	; select register bank 0
	movlw 	B'01000001' ; select 8 * oscillator, analog input 0, turn on
	movwf 	ADCON0 		; move to special function A/D register
	return

SwitchDelay
	movlw 	D'02' 		; load Temp with decimal 20 <= change delay time
	movwf 	Temp
delay
	decfsz 	Temp, F 	; 60 usec delay loop
	goto 	delay 		; loop until count equals zero
	return

timeLoop                ; Initialize timers for half a second increment
	movlw	03h
	movwf	Timer2
	movlw	8Bh
	movwf	Timer1
	movlw	0Ah
	movwf	Timer0
delay2                  ; Delay for half a second
	decfsz	Timer0, F
	goto	delay2
	decfsz	Timer1, F
	goto	delay2
	decfsz	Timer2, F
	goto	delay2
	return

Mode_2_RedPress
	call 	SwitchDelay 	; let switch debounce
	btfsc 	PORTC,6 		; see if red button still pressed
	goto	Discard_RedPress; Ignore red press
Mode_2_RedRelease
	btfss 	PORTC,6 		; Check if red button is released
	goto 	RedRelease
	goto	Mode_2_On_Red	; Restart the full mode 2 sequence


; ====================== Mode 3 Action ===================== ;


Mode_3_On_Red
	call    A_to_D      ; Read A_to_D converter
	movlw   H'38'	    ; Timer value of A_to_D converter is divided by two
	subwf   Timer, W    ; W = W - Timer
	btfsc   STATUS, C   ; Check if carry bit is set
	bsf     PORTD,7     ; Turn on main transistor
	btfss   STATUS, C   ; Check if carry bit is clear
	bcf		PORTD, 7    ; Turn off main transistor
	btfss   PORTC, 6 	; See if red button is pressed, potentially stop control 
	goto	RedPress_3
	goto	Mode_3_On_Red

RedPress_3
	call 	SwitchDelay 	; let switch debounce
	btfsc 	PORTC, 6 		; see if red button still pressed
	goto	Mode_3_On_Red
RedRelease_3
	btfss 	PORTC, 6 		; See if red button is released
	goto 	RedRelease_3
	bcf		PORTD, 7        ; Turn off main transistor
	return


; ====================== Mode 4 Action ===================== ;


Mode_4_On_Red
	movlw	H'01'   ; Set first bit of value register - indicates possible second try fault
	movwf	Value
	movlw	H'15'   ; Set timer for 10 seconds
	movwf	Temp2
Mode_4_Start_Sequence
	call	A_to_D
Mode_4_Loop
	bsf		PORTD, 7    ; Turn on the main transistor
	call	timeLoop    ; Wait for half a second
	decfsz	Temp2, F    ; Fault if ten seconds have passed
	goto	Mode_4_Continue
	goto	Hard_Fault
Mode_4_Continue	
	btfsc	PORTC, 0		; Check sensor, bit 0 is low when solenoid is retracted
	goto	Mode_4_Loop     ; Sensor indicates solenoid is not retracted, try again
	bsf     PORTD, 6		; Turn on reduced transistor
	call	SwitchDelay     ; Wait a little bit
	bcf		PORTD, 7		; Turn off the main transistor
Mode_4_Loop_2
	btfsc	PORTC, 0            ; Check if solenoid has disengaged
	goto	Mode_4_Second_Try   ; Try again one time on disengage
	call	timeLoop	        ; Wait for half a second
	decfsz	Timer, F            ; Keep solenoid engaged for 1/4 pot value
	goto	Mode_4_Loop_2
	bcf		PORTD, 6            ; Turn off reduced transistor
	movlw	H'15'               ; Set timer for ten seconds
	movwf	Temp2
Mode_4_Loop_3
	call	timeLoop
	decfsz	Temp2, F        ; Fault if solenoid doesn't disengage in ten seconds
	goto	Check_Disengage
	goto	Hard_Fault
Check_Disengage
	btfss	PORTC, 0        ; Check if solenoid has disengaged
	goto	Mode_4_Loop_3
	return                  ; Go back to listening to red/green presses

Mode_4_Second_Try
	btfss	Value, 0        ; Check if this is my second try
	goto	Hard_Fault
	bcf		Value, 0        ; Indicate I've tried once already
	bcf		PORTD, 6        ; Turn off reduced transistor
	goto	Mode_4_Start_Sequence


; ====================== Initialization ===================== ;

initPort
	clrf 	PORTB 		; Clear Port B output latches
	clrf 	PORTC 		; Clear Port C output latches
	clrf	PORTD
	clrf	PORTE		; Clear Port E output Latches
	clrf	Octal
	bsf 	STATUS,RP0 	; Set bit in STATUS register for bank 1
	movlw 	B'11110000' ; move hex value FF into W register
	movwf 	TRISB 		; Configure Port C as all output
	movlw 	H'FF'		; move hex value FF into W register
	movwf 	TRISC 		; Configure Port C as inputs for unassigned pins and outputs for necessary pins
	movlw 	B'00111101' 	
	movwf 	TRISD 		; Configure Port D as inputs for unassigned pins and output for pin1 
	movlw 	B'00000111'
	movwf 	TRISE 		; Configure Port E as inputs for pins 0,1,2 
	movlw 	B'00001110'
	movwf 	ADCON1 		; move to special function A/D register
	bcf 	STATUS,RP0 	; Clear bit in STATUS register for bank 0
	return


; ====================== Interrupt Vector ===================== ;


isrService
	bsf		PORTB,3
	goto 	isrService 	; error - - stay here
	end


