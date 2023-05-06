*  KCTFS menuing system
*
* Assemble with xdt99 (endlos99.github.io/xdt99)
*   export PATH=/u/ti994a/xdt99:$PATH
*   xas99.py -L ti-kctfs.lst -R -b ti-kctfs.asm
*   Copy ti-kctfs.bin to the root of the SD card



       idt 'kctfs'

       def sload, sfirst, slast, start
       ref kscan


       AORG >6000

       DATA >AA01
       DATA 0,0
       DATA MENU
       DATA 0,0,0,0
MENU   DATA 0
       DATA start
       BYTE 5
       TEXT 'KCTFS'

       jmp  start

workspace:
       equ  >8300
keymode:
       equ  >8374
keycode:
       equ  >8375
gpl_status:
       equ  >837c

SCRATCH_RAM		equ	>F000
RAM_ROUTINE		equ	>F100

FDC_CRU_BASE		equ	>1100

MENU_STATUS		equ	>5fe0
MENU_COUNT_LSB		equ	>5fe2
MENU_DATA_READ		equ	>5fe6

MENU_COMMAND		equ	>5fe8
MENU_ADDRESS_LSB	equ	>5fea
MENU_ADDRESS_MSB	equ	>5fec
MENU_DATA_WRITE		equ	>5fee

MENU_FNAME_BASE_ADDRESS	equ	>0100
MENU_LOAD_DIRECTORY_COMMAND	equ	>8000
MENU_LOAD_ROM_COMMAND		equ	>4000

MENU_END_COMMAND		equ	>3300

MENU_ITEMS_PER_PAGE		equ 20
CHARACTERS_TO_SKIP_PER_LINE	equ 32

top_line_message:
	;     12345678901234567890123456789012
	text 'KCTFS 0.16              PAGE x  '
	byte 0

bottom_line_message:
	text '/ - HELP'
	byte 0

help_page:
	text 'A - T  - SELECT AND RESET'
	byte 0
	text '1 - 9  - CHANGE PAGE'
	byte 0
	text '/      - HELP'
	byte 0
	text ' '
	byte 0
	text 'PRESS X TO EXIT HELP'
	byte 0,0


	even
start:
       limi 0
       lwpi workspace

       li	r12,FDC_CRU_BASE		Disk controller CRU
       sbo	0				Must be on to talk to the FDC

	clr	r10				R10 is used to work out if the help screen is showing

* Once done, don't forget to turn the card off:
       ;SBZ  0

	bl	@clear_screen
	bl	@load_font

	bl	@display_top_line
	bl	@display_bottom_line


	; write a 'W' (for wait) on the top line to saw we are waiting for the stm32f4 to produce the whole directory listing
	li	r0,12
	li	r1,'W '
	bl	@vsbw
; poke the load directory command
	li	r1,MENU_LOAD_DIRECTORY_COMMAND
	movb	r1,@MENU_COMMAND
wait_for_dir_load:
	movb	@MENU_STATUS,r1
	sla	r1,1
	joc	wait_for_dir_load
dir_load_is_finished:
	li	r1,MENU_END_COMMAND	; Reading the status register used to auto-end things , but you often get spurious reads. So now you send this magic command
	movb	r1,@MENU_COMMAND

	; get rid of the 'W'
	li	r0,12
	li	r1,'  '
	bl	@vsbw

	; R9 - number of menu entries
	; R8 - page number
	; R7 - last key pressed



	movb	@MENU_COUNT_LSB,r9
	srl	r9,8
	li	r8,1			; start at page 1
	clr	r7			; prime for the first key press


main_loop:
	bl	@display_page

wait_for_key:
	bl	@KCHECK
	jne	key_down
	jmp	wait_for_key
key_down:
	movb	@keycode,r1
	cb	r1,r7
	jeq	wait_for_key
	mov	r1,r7			; update last key pressed
; key is pressed, and its different to the last one
	srl	r1,8
	ci	r1,'/'
	jne	!not_help
	li	r2,>8000		; highest order bit of the page number indicates whether the help page is display
	xor	r10,r2
	czc	r2,r10
	jne	main_loop		; if top bit is zero after the xor then it means that we need to return to the normal menu list display
	bl	@show_help
	jmp	wait_for_key

!not_help:
	ci	r1,'0'
	jle	main_loop
	ci	r1,'9'
	jgt	try_letters
; should be a number selected
	ai	r1,-'0'
	mov	r1,r8
	; TODO
	;bl	@update_page_number
	jmp	main_loop
try_letters:
	ci	r1,('A'-1)
	jle	main_loop
	ci 	r1,'A' + MENU_ITEMS_PER_PAGE
	jgt	main_loop
; Should be a key from 'A' to 'something'
	ai	r1,-'A'				; subtract 'A'
	mov	r8,r0
!	dec	r0				; adjust so that page num is from 0
	jeq	adjust_page_offset_done
	ai	r1,MENU_ITEMS_PER_PAGE
	jmp	-!
adjust_page_offset_done:
	sla	r1,7				; multiple by 128
	ai	r1,MENU_FNAME_BASE_ADDRESS
	mov	r1,r6
	movb	r6,@MENU_ADDRESS_MSB	; MSB
	mov	r6,r0
	sla	r0,8
	movb	r0,@MENU_ADDRESS_LSB	; LSB
	li	r5,SCRATCH_RAM		; scratch ram
select_fname1:
	movb	@MENU_DATA_READ,r1
	andi	r1,>ff00
	jeq	end_of_select_fname
	movb	r1,*r5+
	jmp	select_fname1
end_of_select_fname:
	movb	r1,*r5+			; final null
	li	r6,>0
	movb	r6,@MENU_ADDRESS_MSB	; MSB
	mov	r6,r0
	sla	r0,8
	movb	r0,@MENU_ADDRESS_LSB	; LSB
	li	r5,SCRATCH_RAM
select_fname2:
	movb	*r5+,r1
	movb	r1,@MENU_DATA_WRITE
	andi	r1,>ff00
	jne	select_fname2
copy_low_mem_routine:
	li	r0,low_mem_reset
	li	r1,RAM_ROUTINE
	li	r2,(low_mem_reset_end-low_mem_reset)
	srl	r2,1
	inc	r2		; add some padding
!	mov	*r0+,*r1+
	dec	r2
	jne	-!
	b	@RAM_ROUTINE

low_mem_reset:
	limi	0

	clr	r12
	sbz	2

	clr	r0
	mov	r0,@>83C4	; see https://forums.atariage.com/topic/245161-blwp-0/
	; pull carpet out
	li	r0,MENU_LOAD_ROM_COMMAND
	movb	r0,@MENU_COMMAND
; NB: this reboot process is very sensitive with respect to disk based games. It took a long time to
; figure out. If you trigger the ROM swap above and don't wait long enough before calling blwp @>0000
; then the 994a can get very confused and while it will load roms and groms OK it seems to have
; trouble loading disk images. Originally I had a simple delay loop but that was very unreliable.
wait_for_rom_load_complete:
	movb	@MENU_STATUS,r1
	sla	r1,2
	joc	wait_for_rom_load_complete
	li	r1,MENU_END_COMMAND	; Reading the status register used to auto-end things , but you often get spurious reads. So now you send this magic command
	movb	r1,@MENU_COMMAND
	
	li	r12,FDC_CRU_BASE		Disk controller CRU
	SBZ	0		; turn off the DSR rom
	blwp	@>0000
low_mem_reset_end:
	nop


show_help:
	li	r6,help_page
	li	r5,MENU_ITEMS_PER_PAGE					; number of lines that we may have to blot out
	li	r4,(2*32+1)				; r4 is screen location. 3rd line indented by 1

; set the VDP address
next_help_line:
	mov	r4,r0
	ori	r0, >4000
	swpb r0
	movb r0, @vdpwa
	swpb r0
	movb r0, @vdpwa

	li	r3,29					; max of 29 chars of visible filename
!	movb	*r6+,r0
	;andi	r0,>ff00
	jeq	!end_of_line
	movb	r0,@vdpwd
	dec	r3
	jne	-!
	jmp	!end_of_line2
!end_of_line:
	li	r0,'  '
!	movb	r0,@vdpwd
	dec	r3
	jne	-!
!end_of_line2:
	ai	r4,CHARACTERS_TO_SKIP_PER_LINE
	dec	r5					; lines left
	movb	*r6,r0
	;andi	r0,>ff00
	jne	next_help_line
; fill lines with blanks
next_blank_help_line:
	mov	r4,r0
	ori	r0, >4000
	swpb r0
	movb r0, @vdpwa
	swpb r0
	movb r0, @vdpwa

	li	r0,'  '
	li	r3,29
!	movb	r0,@vdpwd
	dec	r3
	jne	-!
	ai	r4,CHARACTERS_TO_SKIP_PER_LINE
	dec	r5
	jne	next_blank_help_line
	rt

; R8 is the page number (1 is the first page)
display_page:
	; First update the page number
	li	r0,30					; top line to the far right
	ori	r0, >4000
	swpb r0
	movb r0, @vdpwa
	swpb r0
	movb r0, @vdpwa
	mov	r8,r1
	sla	r1,8
	ai	r1,'0 '
	movb	r1,@vdpwd


	mov	r9,r2					; r2 is how many files we retrieved overall
	li	r6,MENU_FNAME_BASE_ADDRESS		; index into the stm32f4's table of filenames
	mov	r8,r5
!	dec	r5					; make it a page number from 0 to x
	jeq	!pages_done
	ci	r2,10
	jlt	blank_whole_page
	ai	r2,-MENU_ITEMS_PER_PAGE
	ai	r6,(MENU_ITEMS_PER_PAGE*128)
	jmp	-!
!pages_done:
	inc	r2
	li	r4,(2*32+1)				; r4 is screen location. 3rd line indented by 1
	clr	r5					; first entry on the page is r5=0
next_filename:
	dec	r2
	jeq	blank_rest_of_page
	movb	r6,@MENU_ADDRESS_MSB	; MSB
	mov	r6,r0
	sla	r0,8
	movb	r0,@MENU_ADDRESS_LSB	; LSB

; set the VDP address
	mov	r4,r0
	ori	r0, >4000
	swpb r0
	movb r0, @vdpwa
	swpb r0
	movb r0, @vdpwa

	mov	r5,r1
	sla	r1,8
	ai	r1,>4100
	movb r1, @vdpwd					; write the menu letter .eg 'A', 'B' ...
	li	r1,'. '
	movb r1, @vdpwd					; write a dot after the letter
	li	r3,29					; max of 29 chars of visible filename
next_fname_byte:
	movb	@MENU_DATA_READ,r1
	andi	r1,>ff00
	jeq	pad_rest_of_line
	ci	r1,>6100
	jlt	case1
	; probably lowercase, so make uppercase
	andi	r1,>df00
case1:	movb	r1,@vdpwd
	dec	r3
	jne	next_fname_byte
	jmp	end_of_line
pad_rest_of_line:
	li	r1,'  '
!	movb	r1,@vdpwd
	dec	r3
	jne	-!
end_of_line:
	ai	r6,128
	ai	r4,CHARACTERS_TO_SKIP_PER_LINE
	inc	r5
	ci	r5,MENU_ITEMS_PER_PAGE
	jne	next_filename
	rt
blank_rest_of_page:
	mov	r4,r0
	ori	r0, >4000
	swpb r0
	movb r0, @vdpwa
	swpb r0
	movb r0, @vdpwa

	li	r0,32
	li	r1,'  '
!	movb r1, @vdpwd					; write the menu letter .eg 'A', 'B' ...
	dec	r0
	jne	-!
	ai	r4,CHARACTERS_TO_SKIP_PER_LINE
	inc	r5
	ci	r5,MENU_ITEMS_PER_PAGE
	jne	blank_rest_of_page
	rt


; this actually just blanks the menu lines and leaves the top and bottom lines intact
blank_whole_page:
	li	r0,32
	ori	r0, >4000
	swpb r0
	movb r0, @vdpwa
	swpb r0
	movb r0, @vdpwa

	li   r1, '  '
	li   r2, 22 * 32

!	movb r1, @vdpwd
	dec  r2
	jne  -!
	rt



; Note you cant bl something else without saving r11 first!
clear_screen:
	clr	r0
	ori	r0, >4000
	swpb r0
	movb r0, @vdpwa
	swpb r0
	movb r0, @vdpwa

	li   r1, '  '
	li   r2, 24 * 32

!	movb r1, @vdpwd
	dec  r2
	jne  -!
	rt

display_bottom_line:
	li	r0,23*32
	li	r1,bottom_line_message
	jmp	display_line

display_top_line:
	clr	r0
	li	r1,top_line_message
display_line:
	ori	r0, >4000
	swpb r0
	movb r0, @vdpwa
	swpb r0
	movb r0, @vdpwa
!	movb	*r1+,r0
	jeq	!end
	movb	r0,@vdpwd
	jmp	-!
!end	rt

load_font:
	li	r0,>0900	; start of the 'space' character in the character map
	ori	r0, >4000
	swpb r0
	movb r0, @vdpwa
	swpb r0
	movb r0, @vdpwa

	li	r2, 59 * 8	; load 59 chars
	li	r0,font
!	movb	*r0+,r1
	movb r1, @vdpwd
	dec  r2
	jne  -!
	rt

; keyscan from Thierry's pages
*--------------------------------------------
* Quick-and-dirty check to see if a key is pressed. 
* If not return in a hurry, 
* else call the standard scanning routine.
* Uses R1, R2 and R12.
*--------------------------------------------
KCHECK CLR  R1                 Start with column 0
LP1    LI   R12,>0024          R12-address for column selection
       LDCR R1,3               Select a column
       LI   R12,>0006          R12-address to read rows
       SETO R2                 Make sure all bits are 1
       STCR R2,8               Get 8 row values
       INV  R2                 Since pressed keys read as 0
       JNE  KPR                A key was pressed
       AI   R1,>0100           Next column
       CI   R1,>0600           Are we done
       JNE  LP1                Not yet
       B    *R11               No key pressed: return (with EQ bit set)
 
KPR    BLWP @KSCAN             Call KSCAN routine
*       INCT R11               (either) signal key by skipping a jump
      MOV  R2,R2             (or) signal key by clearing the EQ bit
       B    *R11               Return

	copy "vsbw.asm"
	copy "vmbw.asm"
	copy "vwtr.asm"
	copy "kscan_ea.asm"

	copy "spectrum-font.asm"

	end
