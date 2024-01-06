;
;	ZX Diagnostics - fixing ZX Spectrums in the 21st Century
;	https://github.com/brendanalford/zx-diagnostics
;
;	Original code by Dylan Smith
;	Modifications and 128K support by Brendan Alford
;
;	This code is free software; you can redistribute it and/or
;	modify it under the terms of the GNU Lesser General Public
;	License as published by the Free Software Foundation;
;	version 2.1 of the License.
;
;	This code is distributed in the hope that it will be useful,
;	but WITHOUT ANY WARRANTY; without even the implied warranty of
;	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;	Lesser General Public License for more details.
;
;	testrom.asm
;

;
;	Spectrum Diagnostics - Spectranet ROM Module Part 2 - 48 and 128 tests
;
;	v0.1 by Dylan 'Winston' Smith
;	v0.2 modifications and 128K testing by Brendan Alford.
;

	include "vars.asm"
	include "../defines.asm"
	include "../version.asm"
	include "spectranet.asm"

	org 0x1000

;	Spectranet ROM Module table

	defb 0xAA			; Code module
	defb 0x00			; No ROM ID
	defw 0xffff			; No init routine
	defw 0xffff			; Mount vector - unused
	defw 0xffff			; Reserved
	defw 0xffff			; Address of NMI Routine
	defw 0xffff			; Address of NMI Menu string
	defw 0xffff			; Reserved
	defw str_identity+0x1000	; Identity string
	; we must add 0x1000 to this because spectranet expects code modules
	; to be assembled to 0x2000. We want to run it from 0x1000 but this
	; vector must point at the location of the string when paged at 0x2000

module_2_entrypoint

;	Module 1 will call us here.
;	Lower tests passed.
;	Page in ROM 0 (if running on 128 hardware) in preparation
;	for ROM test.

	xor a
	ld bc, 0x1ffd
	out (c), a
	ld bc, 0x7ffd
	out (c), a

;	Prepare system variables

	ld (v_fail_ic), a
	ld (v_fail_ic_uncontend), a
	ld (v_fail_ic_contend), a
	ld (v_paging), a

;	Perform some ROM checksum testing to determine what
;	model we're running on

; 	Assume 128K toastrack (so far)

	xor a
	ld (v_128type), a

	ld hl, str_romcrc
    call outputstring

;	Copy the checksum code into RAM

	ld hl, start_romcrc
	ld de, do_romcrc
	ld bc, end_romcrc-start_romcrc
	ldir

;	Checksum the ROM

	ld(v_stacktmp), sp
	ld sp, tempstack
	call do_romcrc
	ld sp, (v_stacktmp)

;	Save it in DE temporarily

	ld de, hl
	ld hl, rom_signature_table

; 	Check for a matching ROM

rom_check_loop

;	Check for 0000 end marker

	ld bc, (hl)
	ld a, b
	or c
	jr z, rom_unknown

;	Check saved ROM CRC in DE against value in table

	ld a, d
	xor b
	jr nz, rom_check_next
	ld a, e
	xor c

	jr z, rom_check_found

rom_check_next

	ld bc, 8
	add hl, bc
	jr rom_check_loop

; Unknown ROM, say so and prompt the user for manual selection

rom_unknown

	push de
	ld hl, str_romunknown
	call outputstring
	pop hl
    ld de, v_hexstr
    call Num2Hex
    xor a
    ld (v_hexstr+4), a
    ld hl, v_hexstr
    call outputstring
	call newline

;	Run 48K tests by default
	ld hl, test_return
	push hl
	jp test_48kgeneric

rom_check_found

;	Print the appropriate ROM type to screen

	push hl
	inc hl
	inc hl
	ld de, (hl)
	ld hl, de

	call outputstring
	ld hl, str_testpass
	call outputstring
	pop hl

;	Call the appropriate testing routine

	ld de, 4
	add hl, de

call_test_routine

	ld de, (hl)

	ld hl, test_return
	push hl

	ld hl, de
	jp hl

test_return
	; set paging back as spectranet needs it
	ld bc, 0x1FFD		; set port 0x1ffd
	ld a, 0x04
	out (c), a
	ld b, 0x7F		; set port 0x7ffd which must be done
	ld a, 0x10		; second due to toastrack 128K machines
	out (c), a		; responding also to 0x1ffd

	ret

	; We can't fit all of the ROM definitions and test code into a single
	; 4K Spectranet module
	
	define SAVEMEM 

	include "output.asm"
	include "../paging.asm"
	include "testroutines.asm"
	include "spectranet48tests.asm"
	include "spectranet128tests.asm"
	include "../romtables.asm"

;
;	Prints a 16-bit hex number to the buffer pointed to by DE.
;	Inputs: HL=number to print.
;

Num2Hex

	ld	a,h
	call	Num1
	ld	a,h
	call	Num2

;	Call here for a single byte conversion to hex

Byte2Hex

	ld	a,l
	call	Num1
	ld	a,l
	jr	Num2

Num1

	rra
	rra
	rra
	rra

Num2

	or	0xF0
	daa
	add	a,#A0
	adc	a,#40

	ld	(de),a
	inc	de
	ret

;
;	Routine to calculate the checksum of the
;	currently installed ROM.
;
start_romcrc

;	Unpage the Spectranet
	call 0x007c

	ld de, 0
	ld hl,0xFFFF

Read

	ld a, (de)
	inc	de
	xor	h
	ld	h,a
	ld	b,8

CrcByte

	add	hl, hl
	jr	nc, Next
	ld	a,h
	xor	10h
	ld	h,a
	ld	a,l
	xor	21h
	ld	l,a

Next

	djnz	CrcByte

;	We only check the ROM from 0000-3FBF to maintain
;	compatibility with the mainstream ROM tables, which
;	need to avoid the top 64 bytes of ROM space to avoid
;	conflicts with the ZXC3/4 cartridge memory mapped paging.

	ld a, d
	cp 0x3f
	jr	nz,Read
	ld a, e
	cp 0xc0
	jr nz, Read

	push hl
	pop bc

;	Restore Spectranet ROM/RAM

	call 0x3ff9
	ret

end_romcrc

;
;	Subroutine to print a list of failing IC's.
;   	Inputs: D=bitmap of failed IC's, IX=start of IC number list
;

print_fail_ic

	ld b, 0

fail_print_ic_loop

	bit 0, d
	jr z, ic_ok

;	Bad IC, print out the correspoding location for a 48K machine

	ld hl, str_ic
	push bc
	push de
	push ix
	call print
	pop ix
	pop de
	pop bc
	ld hl, ix

;	Strings are aligned to nearest 32 bytes, so we can just replace
;	this much the LSB

	ld a, b
	rlca
	rlca
	or l
	ld l, a
	push bc
	push de
	push ix
	call print
	pop ix
	pop de
	pop bc
	ld a, 5

ic_ok

;	Rotate D register right to line up the next IC result
;	for checking in bit 0

	rr d

;	Loop round if we've got more bits to check

	inc b
	ld a, b
	cp 8
	jr nz, fail_print_ic_loop

	ret

;
;	Subroutines to print a list of failing IC's for 4 bit wide
;	memories (+2A/+3).
;   	Inputs: D=bitmap of failed IC's, IX=start of IC number list
;

print_fail_ic_4bit


	ld a, d
	and 0x0f
	jr z, next_4_bits

;	Bad IC, print out the correspoding location

	ld hl, str_ic
	push bc
	push de
	push ix
	call print
	pop ix
	pop de
	pop bc
	ld hl, ix
	call print

next_4_bits

	ld bc, 4
	add ix, bc

	ld a, d
	and 0xf0
	jr z, bit4_check_done

	ld hl, str_ic
	push bc
	push de
	push ix
	call print
	pop ix
	pop de
	pop bc
	ld hl, ix
	call print

bit4_check_done

	ret

;
print

	jp outputstring

newline

	ld a, LF
	call outputchar
	ld a, NL
	call outputchar
	ret

str_identity

	defb "ZX Diagnostics Module 2 ", VERSION, 0

str_testpass

	defb "PASS", 0

str_testfail

	defb "FAIL", 0

str_romcrc

	defb	CRLF, "Checking ROM version...", CRLF, 0

str_romunknown

	defb	"Unknown or corrupt ROM: 0x", 0

str_test4

	defb	CRLF, "Upper RAM Walk test...      ", 0

str_test5

	defb	"Upper RAM Inversion test... ", 0

str_test6

	defb	"Upper RAM March test...     ", 0

str_test7

	defb	"Upper RAM Random test...    ", 0

str_48ktestspass

	defb	CRLF, "48K RAM Tests Passed", CRLF, NL, 0

str_48ktestsfail

	defb	CRLF, "48K tests FAILED", CRLF, NL, 0

str_isthis16k

	defb	"This appears to be a 16K Spectrum", CRLF
	defb    "If 48K, check IC23-IC26 (74LS157, 32, 00)", CRLF, NL, 0

str_check_ic

	defb	"Check the following IC's:", CRLF, 0

str_ic

	defb "IC", 0

str_testingbank

	defb	CRLF, CRLF, "Testing RAM bank  ", 0

str_testingpaging

	defb	"Testing paging    ", 0

str_bankm

	defb	"x ", 0


str_128ktestspass

	defb	CRLF, "128K RAM Tests Passed", CRLF, NL, 0

str_128ktestsfail

	defb	CRLF, "128K tests FAILED", CRLF, NL, 0

str_128kpagingfail

	defb	CRLF, "128K Paging tests FAILED", CRLF, 0

str_check_128_hal

	defb	"Check IC29 (PAL10H8CN) and IC31 (74LS174N)", CRLF, NL, 0

str_check_plus2_hal

	defb	"Check IC7 (HAL10H8ACN) and IC6 (74LS174N)", CRLF, NL, 0

str_check_js128_hal

	defb	"Check HAL (GAL16V8) and U6 (74LS174N)", CRLF, NL, 0

str_check_plus3_ula

	defb	"Check IC1 (ULA 40077)", CRLF, NL, 0

;	Page align the IC strings to make calcs easier
;	Each string block needs to be aligned to 32 bytes

	BLOCK #1ee0-$, #FF

str_bit_ref

	defb "0 ", 0, 0,  "1 ", 0, 0, "2 ", 0, 0, "3 ", 0, 0, "4 ", 0, 0, "5 ", 0, 0, "6 ", 0, 0, "7 ", 0, 0

str_48_ic

	defb "15 ",0, "16 ",0, "17 ",0, "18 ",0, "19 ",0, "20 ",0, "21 ",0, "22 ", 0

str_128k_ic_contend

	defb "6  ",0, "7  ",0, "8  ",0, "9  ",0, "10 ",0, "11 ",0, "12 ",0, "13 ", 0

str_128k_ic_uncontend

	defb "15 ",0, "16 ",0, "17 ",0, "18 ",0, "19 ",0, "20 ",0, "21 ",0, "22 ", 0

str_plus2_ic_contend

	defb "32 ",0, "31 ",0, "30 ",0, "29 ",0, "28 ",0, "27 ",0, "26 ",0, "25 ", 0

str_plus2_ic_uncontend

	defb "17 ",0, "18 ",0, "19 ",0, "20 ",0, "21 ",0, "22 ",0, "23 ",0, "24 ", 0

str_plus3_ic_contend

	defb "3  ", 0, "4  ", 0

str_plus3_ic_uncontend

	defb "5  ", 0, "6  ", 0

str_js128_ic_contend

	defb "20 ",0, "21 ",0, "22 ",0, "23 ",0, "24 ",0, "25 ",0, "26 ",0, "27 ", 0

str_js128_ic_uncontend

	defb "29 ",0, "28 ",0, "10 ",0, "9  ",0, "30 ",0, "31 ",0, "32 ",0, "33 ", 0

	BLOCK 0x1fff-$, 0xff
