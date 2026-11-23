; rt_div64.s - cc816's 64-bit division (long long): see rt_shift64.s for the contract.
;
;   __udiv64 __sdiv64   __h0..__h1 / __h2..__h3 -> __h0..__h1 (__udiv64 leaves the
;                       remainder in __h2..__h3)
;   __umod64 __smod64   __h0..__h1 % __h2..__h3 -> __h0..__h1
;
; C's rules: a quotient truncates toward 0, a remainder has the sign of the dividend.
; Division by 0 does not trap: the quotient is all ones, the remainder the dividend (as
; the 32-bit helpers).
;
; A divisor below $10000 (printf's 10, 8, 16): four 16-bit long-division steps with the
; remainder in A, a step whose remainder is 0 and whose dividend word is below the
; divisor skipped. Both below 2^32: __udiv32. Any other: 64 rounds of shift and subtract
; (less 16 for each word of zeros at the top of the dividend) in a direct page made on
; the hardware stack (D points at it during the loop, then back at 0).
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __h0, __h1, __h2, __h3, __rv
	.import	__udiv32
	.export	__udiv64, __umod64, __sdiv64, __smod64

	.segment "CODE"

; one 16-bit step: (A : word) / __h2 -> word, the remainder in A
.macro	DSTEP	w
	.local	dfull, dzero, dloop, dbit, dbig, ddone
	cmp	#0
	bne	dfull
	lda	w
	cmp	__h2
	bcs	dzero
	stz	w			; remainder 0, dividend word < divisor: quotient word 0
	bra	ddone
dzero:	lda	#0
dfull:	ldx	#16
	asl	w
dloop:	rol	a
	bcs	dbig			; 17 bits: certainly >= the divisor
	cmp	__h2
	bcc	dbit
	sbc	__h2
dbit:	rol	w
	dex
	bne	dloop
	bra	ddone
dbig:	sbc	__h2			; (C set: the 17-bit value less the divisor)
	sec
	bra	dbit
ddone:
.endmacro

__udiv64:
	lda	__h2+2
	ora	__h3
	ora	__h3+2
	beq	@w
	jmp	full
@w:	lda	__h2
	bne	@nz
	jmp	byzero
@nz:	lda	#0
	DSTEP	__h1+2
	DSTEP	__h1
	DSTEP	__h0+2
	DSTEP	__h0
	sta	__h2
	stz	__h2+2
	stz	__h3
	stz	__h3+2
	RET

byzero:	ldx	#6
@c:	lda	__h0,x
	sta	__h2,x
	lda	#$FFFF
	sta	__h0,x
	dex
	dex
	bpl	@c
	RET

; the frame (direct page offsets while D points at it)
R0 = 0				; the remainder, 4 words
Q0 = 8				; the dividend, becoming the quotient
V0 = 16				; the divisor
T0 = 24				; the trial difference's low 3 words
FRAME = 30

full:	lda	__h1			; both below 2^32: the 32-bit division
	ora	__h1+2
	ora	__h3
	ora	__h3+2
	bne	@big64
	lda	__h2
	sta	__h1
	lda	__h2+2
	sta	__h1+2
	CALL	__udiv32		; (quotient __h0, remainder __h2)
	stz	__h1
	stz	__h1+2
	stz	__h3
	stz	__h3+2
	RET
@big64:	pea	0			; T2, T1, T0
	pea	0
	pea	0
	pei	(__h3+2)		; V3 .. V0
	pei	(__h3)
	pei	(__h2+2)
	pei	(__h2)
	pei	(__h1+2)		; Q3 .. Q0
	pei	(__h1)
	pei	(__h0+2)
	pei	(__h0)
	pea	0			; R3 .. R0
	pea	0
	pea	0
	pea	0
	tsc
	inc	a
	tcd
	ldy	#64
@sk:	lda	Q0+6			; a dividend word of zeros at the top: 16 rounds that
	bne	@l			; only shift zeros, done as one word move
	lda	Q0+4
	sta	Q0+6
	lda	Q0+2
	sta	Q0+4
	lda	Q0
	sta	Q0+2
	stz	Q0
	tya
	sec
	sbc	#16
	tay
	bne	@sk
	bra	@end			; (the dividend was 0)
@l:	asl	Q0
	rol	Q0+2
	rol	Q0+4
	rol	Q0+6
	rol	R0
	rol	R0+2
	rol	R0+4
	rol	R0+6
	bcs	@big			; a 65th bit: the remainder is certainly >= the divisor
	lda	R0
	sec
	sbc	V0
	sta	T0
	lda	R0+2
	sbc	V0+2
	sta	T0+2
	lda	R0+4
	sbc	V0+4
	sta	T0+4
	lda	R0+6
	sbc	V0+6
	bcc	@nx
@set:	sta	R0+6
	lda	T0+4
	sta	R0+4
	lda	T0+2
	sta	R0+2
	lda	T0
	sta	R0
	inc	Q0			; the quotient's bit (bit 0 was shifted in as 0)
@nx:	dey
	bne	@l
@end:	lda	#0
	tcd
	lda	Q0+1,s
	sta	__h0
	lda	Q0+3,s
	sta	__h0+2
	lda	Q0+5,s
	sta	__h1
	lda	Q0+7,s
	sta	__h1+2
	lda	R0+1,s
	sta	__h2
	lda	R0+3,s
	sta	__h2+2
	lda	R0+5,s
	sta	__h3
	lda	R0+7,s
	sta	__h3+2
	tsc
	clc
	adc	#FRAME
	tcs
	RET
@big:	lda	R0			; (the difference modulo 2^64 is the true one)
	sec
	sbc	V0
	sta	T0
	lda	R0+2
	sbc	V0+2
	sta	T0+2
	lda	R0+4
	sbc	V0+4
	sta	T0+4
	lda	R0+6
	sbc	V0+6
	bra	@set

__umod64:
	CALL	__udiv64
	ldx	#6
@c:	lda	__h2,x
	sta	__h0,x
	dex
	dex
	bpl	@c
	RET

neg_h0:	sec
	.repeat	4, k
	lda	#0
	sbc	__h0+2*k
	sta	__h0+2*k
	.endrep
	rts

neg_h2:	sec
	.repeat	4, k
	lda	#0
	sbc	__h2+2*k
	sta	__h2+2*k
	.endrep
	rts

__sdiv64:
	lda	__h1+2
	eor	__h3+2
	sta	__rv+2		; the quotient's sign
	lda	__h1+2
	bpl	@a
	jsr	neg_h0
@a:	lda	__h3+2
	bpl	@b
	jsr	neg_h2
@b:	CALL	__udiv64
	lda	__rv+2
	bpl	@r
	jsr	neg_h0
@r:	RET

__smod64:
	lda	__h1+2
	sta	__rv+2		; the remainder's sign: the dividend's
	bpl	@a
	jsr	neg_h0
@a:	lda	__h3+2
	bpl	@b
	jsr	neg_h2
@b:	CALL	__umod64
	lda	__rv+2
	bpl	@r
	jsr	neg_h0
@r:	RET
