; Build with
; lwasm -f raw --list -o menu menu.s

	PRAGMA 6809

GETKEY				EQU	$8006
TANDY_INDIRECT_GETKEY		EQU	$A000
TXT_SCREEN			EQU	$0400

MENU_CTRL_COMMAND		EQU	$FF50
MENU_CTRL_FILE_COUNT		EQU	$FF52
MENU_CTRL_ADDRESS_REGISTER	EQU	$FF54
MENU_CTRL_DATA_REGISTER		EQU	$FF56

ENTRIES_PER_PAGE		EQU	12

; Note, the stack will down around $7f30 when we start
SCRATCH_FILE_COUNT		EQU	$7800
SCRATCH_PAGE_NUMBER		EQU	$7801
SCRATCH_PAGE_BASE_ADDRESS	EQU	$7802
SCRATCH_PROGRAM_END		EQU	$7804
SCRATCH_FILE_NAME		EQU	$7806
SCRATCH_MODE			EQU	$7807

SCRATCH_START			EQU	$7880


	ORG $C000

	FCC	/DK/

START
	; relocate the whole program to RAM and run from there. This means we can get select ROMs without worrying about the stm32f4 pulling the carpet out
	LBSR	COPY_WHOLE_PROGRAM_TO_SCRATCH
	JMP	SCRATCH_START

MAIN
	LDA	#$1
	STA	SCRATCH_PAGE_NUMBER

	LBSR	GET_TANDY_DRAGON_MODE
	LEAX	HEADING_LINE+2,PCR
	CMPA	#$00
	BNE	L1@
	LDA	#'C'		// Change title to KCCFS for Coco mode
	STA	,X
L1@	
	LBSR	TRIGGER_DIR_LIST
	LBSR	GET_FILE_COUNT

REDRAW
	LBSR	CLEAR_SCREEN
	LEAX	HEADING_LINE,PCR
	LDB	#$00
	LBSR	PRINT_INVERSE_LINE

	LDA	SCRATCH_PAGE_NUMBER
	ADDA	#'0'
	STA	(TXT_SCREEN+30)

	LEAX	HELP_LINE,PCR
	LDB	#$0f
	LBSR	PRINT_INVERSE_LINE


	LDB	#$00
	LDX	#$0100
	LDA	SCRATCH_PAGE_NUMBER
L9@	DECA
	BEQ	L1@
	LEAX	$0600,X
	BRA	L9@
L1@	STX	SCRATCH_PAGE_BASE_ADDRESS
L2@	LBSR	PRINT_MENU_LINE
	TSTA
	BEQ	KEYWAIT
	LEAX	$80,X
	INCB
	CMPB	#ENTRIES_PER_PAGE
	BNE	L2@

KEYWAIT	LDA	SCRATCH_MODE
	TSTA			// = 0 for Tandy mode, = 1 for Dragon
	BEQ	TANDY_KEYBOARD_MODE
; Must be Dragon
	JSR	GETKEY
	BRA	KEYWAIT2
TANDY_KEYBOARD_MODE
	JSR	[TANDY_INDIRECT_GETKEY]
KEYWAIT2 TSTA
	BEQ	KEYWAIT
	STA	(TXT_SCREEN)

	CMPA	#'A'
	BLT	NO_LETTER
	CMPA	#'M'
	BGT	NO_LETTER
	SUBA	#$41
	LDX	SCRATCH_PAGE_BASE_ADDRESS
	TSTA
	BEQ	L8@
L2@	LEAX	$80,X
	DECA
	BNE	L2@
; write address register again
L8@	TFR	X,D
	STB	MENU_CTRL_ADDRESS_REGISTER
	STA	(MENU_CTRL_ADDRESS_REGISTER+1)
	LDY	#SCRATCH_FILE_NAME
L3@	LDA	MENU_CTRL_DATA_REGISTER
	STA	,Y+
	TSTA
	BNE	L3@
; Now write it to the stm32f4
; set address register to 0000
	LDA	#$00
	STA	MENU_CTRL_ADDRESS_REGISTER
	STA	(MENU_CTRL_ADDRESS_REGISTER+1)

	LDY	#SCRATCH_FILE_NAME
L4@	LDA	,Y+
	STA MENU_CTRL_DATA_REGISTER
	TSTA
	BNE	L4@
; trigger  the stm32f4 to swap in the dragondos ROM and load the disk image, then cold start teh Dragon
	ORCC	#$50		; disable ints
	;LDX	[$FFFE]
	LDX	$FFFE
	PSHS	X
	
	LDA	#$00
	STA	$0071		; trigger a cold start
	LDA	#$40
	STA	MENU_CTRL_COMMAND
	LDB	#$FF
; kill some time
L10@	NOP
	DECB
	BNE	L10@
; reboot Dragon
	LDA	SCRATCH_MODE
	TSTA
	BEQ	L11@
; Dragon reboot. Pop the reset vector we pushed earlier
	RTS
; Tandy reboot (should be fine for coco1 and coco2)
L11@	JMP	$A027
NO_LETTER
	CMPA	#'1'
	BLT	NO_NUMBER
	CMPA	#'9'
	BGT	NO_NUMBER
	SUBA	#'0'
	STA	SCRATCH_PAGE_NUMBER
	LBRA	REDRAW

NO_NUMBER
	LBSR	CLEAR_SCREEN
	LEAX	HEADING_LINE,PCR
	LDB	#$00
	LBSR	PRINT_INVERSE_LINE

	LEAX	HELP_PART_1,PCR
	LDB	#$03
	BSR	PRINT_LINE

	LEAX	HELP_PART_2,PCR
	LDB	#$06
	BSR	PRINT_LINE

L1@	JSR	[TANDY_INDIRECT_GETKEY]
	BEQ	L1@

	LBRA	REDRAW
	


GET_FILE_COUNT
	LDA	MENU_CTRL_FILE_COUNT
	STA	SCRATCH_FILE_COUNT
	RTS


; X is the stm32f4 address register pointer . 0x0080 is the first entry, 0x0100 is the 2nd and so on.
PRINT_MENU_LINE
	PSHS	B,X,Y

	PSHS	B
	; set the stm32f4 address regiser
	TFR	X,D
	STB	MENU_CTRL_ADDRESS_REGISTER
	STA	(MENU_CTRL_ADDRESS_REGISTER+1)
	PULS	B

	; work out screen start address
	PSHS	B
	LDA	#$00
	LDX	#TXT_SCREEN+(32*2)	// start a few lines down
	ASLB
	ROLA
	ASLB
	ROLA
	ASLB
	ROLA
	ASLB
	ROLA
	ASLB
	ROLA
	LEAX	D,X
	PULS	B

	TFR	B,A
	ADDA	#$41			// Should put A. for the first entry
	TFR	X,Y
	STA	,X+
	LDA	#$6e
	STA	,X+
	LDB	#30		// max chars per line
	LDA	MENU_CTRL_DATA_REGISTER
	BNE	L5@
	LDA	#' '+$40			// For the last line we would have written a letter and a . . Now write over them with spaces
	STA	,Y+
	STA	,Y+
	LDA	#$00
	PULS	B,X,Y
	RTS
L2@	LDA	MENU_CTRL_DATA_REGISTER
L5@	BEQ	L1@
	DECB
	BEQ	L1@
	CMPA	#$40
	BGE	L3@
	ORA	#$40	
	BRA	L4@
L3@	ANDA	#$1f
	ORA	#$40
L4@	STA	,X+
	BRA	L2@
L1@	PULS	B,X,Y
	LDA	#$01
	RTS




; X points to line to print
; B points to line number (0 is the top line, 15 is the bottom line)

PRINT_LINE
	PSHS	A,B,X,Y
	LDA	#$00
	LDY	#TXT_SCREEN
; multiply by 32
	ASLB
	ROLA
	ASLB
	ROLA
	ASLB
	ROLA
	ASLB
	ROLA
	ASLB
	ROLA

	LEAY	D,Y
	LDB	#$20		// 32 chars per line
L2@	LDA	,X+
	BEQ	L1@
	CMPA	#$40
	BGE	L5@
	ORA	#$40		// This makes ASCII code below $40 appear. eg. a dot $2e will end up being $6e
	BRA	L3@
L5@	ANDA	#$1f		// This is so that upper and lowercase are merged into one
	ORA	#$40		// OR with $40 to make them appear on the light green background
L3@	STA	,Y+
	DECB
	BEQ	L1@
	BRA	L2@
L1@
	PULS	A,B,X,Y
	RTS

; X points to line to print
; B points to line number (0 is the top line, 15 is the bottom line)
; Note: I think this is 'not inverse' in terms of the 6847 doco
PRINT_INVERSE_LINE
	PSHS	A,B,X,Y
	LDA	#$00
	LDY	#TXT_SCREEN
; multiply by 32
	ASLB
	ROLA
	ASLB
	ROLA
	ASLB
	ROLA
	ASLB
	ROLA
	ASLB
	ROLA

	LEAY	D,Y
	LDB	#$20		// 32 chars per line
L2@	LDA	,X+
	BEQ	L1@
	CMPA	#$40
	BLT	L3@
	ANDA	#$1f		// This is so that upper and lowercase are merged into one
L3@	STA	,Y+
	DECB
	BEQ	L1@
	BRA	L2@
L1@
	PULS	A,B,X,Y
	RTS

GET_TANDY_DRAGON_MODE
	LDB	#$01		// 01 means Dragon mode
	LDA	MENU_CTRL_COMMAND
	ASLA
; bit 6 is the tandy/dragon mode bit. 
	ASLA	
	BCS	L1@
	LDB	#$00
L1@	STB	SCRATCH_MODE
	TFR	B,A		// return mode in A
	RTS

TRIGGER_DIR_LIST
	LDA	#$80
	STA	MENU_CTRL_COMMAND
	NOP
	NOP
L1@	LDA	MENU_CTRL_COMMAND
	ASLA	
	BCS	L1@
	RTS

CLEAR_SCREEN
	LDX	#TXT_SCREEN
	LDY	#(32*16)
	LDA	#$60
L1@	STA	,X+
	LEAY	-1,Y
	BNE	L1@
	RTS

COPY_WHOLE_PROGRAM_TO_SCRATCH
	LEAX	MAIN,PCR
	LEAY	END,PCR
	STY	SCRATCH_PROGRAM_END
	LDY	#SCRATCH_START
L1@	LDA	,X+
	STA	,Y+
	CMPX	SCRATCH_PROGRAM_END
	BNE	L1@
	RTS


HEADING_LINE
	FCC	/KCDFS 0.25              PAGE    /
	FCB	$00

HELP_LINE
	FCC	/? - HELP                        /
	FCB	$00

HELP_PART_1
	FCC	/  A-L   SELECT DISK AND RESET/
	FCB	$00

HELP_PART_2
	FCC	/  1-9   SELECT PAGE/
	FCB	$00

END
