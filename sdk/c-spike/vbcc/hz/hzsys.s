; hzsys.s - the Horizon syscall gate for vbcc 65816 C (vasm oldstyle syntax).
;
;   unsigned      hz_sys (unsigned n, unsigned a, unsigned x, unsigned y);
;   unsigned long hz_sysl(unsigned n, unsigned a, unsigned x, unsigned y);  A | X << 16
;
; vbcc (large code model): called with JSL, the first argument in A, the others on the
; stack above the 3-byte return address (4,s 6,s 8,s), popped by the caller. Returns A
; (a long in A/X). The gate patches the COP signature byte (the code bank is the task's
; own, writable, addressed through DBR), loads A/X/Y, executes COP #n. Carry set =
; error: hz_err = the error code, else 0. hz_x / hz_y keep X and Y as the call left them.

	global	_hz_sys
	global	_hz_sysl
	global	_hz_err
	global	_hz_x
	global	_hz_y

	section	"DONTMERGE_text.far.hzsys","acrx"
	a16
	x16
_hz_sys:
_hz_sysl:
	sep	#32
	a8
	sta	>hzop+1			; COP #n (long: DBR is 0 in the tiny model)
	rep	#32
	a16
	lda	6,s
	tax
	lda	8,s
	tay
	lda	4,s
hzop:	cop	#0
	stx	!_hz_x
	sty	!_hz_y
	bcs	hzerr
	stz	!_hz_err
	rtl
hzerr:	sta	!_hz_err
	rtl

	section	"DONTMERGE_bss.near.hzsys","aurw"
_hz_err:	reserve	2
_hz_x:		reserve	2
_hz_y:		reserve	2
