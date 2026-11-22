; rt_fcopy.s - cc816's structure copy between far addresses (a structure assigned through
; a __far pointer): __h0 = the destination (offset, bank), __h1 = the source, A = n
; (1-65535). MVN takes its two banks in the instruction, so it is built on the stack
; (MVN dst,src; RTL) and called there: no code is modified. The ranges must not cross a
; bank and must not overlap. Changes A, X, Y, __h2, __h3.
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __h0, __h1, __h2, __h3
	.export	__fcopy

	.segment "CODE"
__fcopy:
	dec	a
	sta	__h3		; n - 1
	lda	__h1+2		; MVN's source bank and the RTL (bytes 3 and 4)
	and	#$00FF
	ora	#$6B00
	pha
	lda	__h0+2		; MVN (byte 1) and its destination bank (byte 2)
	xba
	and	#$FF00
	ora	#$0054
	pha
	ldx	__h1		; the source offset
	ldy	__h0		; the destination offset
	tsc
	inc	a
	sta	__h2		; the instruction's address: bank 0 (the stack)
	stz	__h2+2
	lda	__h3
	phb
	phk			; a JSL's return address, for its RTL
	per	@back - 1
	jml	[__h2]
@back:	plb
	pla
	pla
	RET
