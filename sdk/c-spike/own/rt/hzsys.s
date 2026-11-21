; hzsys.s - the Horizon syscall gate for cc816 C.
;
;   unsigned      hz_sys (unsigned n, unsigned a, unsigned x, unsigned y);
;   unsigned long hz_sysl(unsigned n, unsigned a, unsigned x, unsigned y);  A | X << 16
;
; cc816 convention: JSR, arguments on the hardware stack above the return address (3,s
; 5,s 7,s 9,s), popped by the caller; result in A (32 bits: A low, X high). The gate patches
; the COP signature byte (the code bank is the task's own, writable, through DBR), loads
; A/X/Y, executes COP #n. Carry set = error: hz_err = the code, else 0. hz_x / hz_y keep X
; and Y as the call left them.
	.p816
	.smart	+
	.a16
	.i16
	.export	_hz_sys, _hz_sysl, _hz_err, _hz_x, _hz_y

	.segment "CODE"
_hz_sys:
_hz_sysl:
	sep	#$20
	lda	3,s
	sta	hzop+1
	rep	#$20
	lda	7,s
	tax
	lda	9,s
	tay
	lda	5,s
hzop:	cop	#0
	stx	_hz_x
	sty	_hz_y
	bcs	@err
	stz	_hz_err
	rts
@err:	sta	_hz_err
	rts

	.segment "BSS"
_hz_err: .res	2
_hz_x:	.res	2
_hz_y:	.res	2
