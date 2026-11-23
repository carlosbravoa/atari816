; fp_mul.s - cc816's floating point: __fmul (__h0 * __h1 -> __h0), and __fp_unpk (shared
; with fp_div.s). The contract and the rules: fp_pack.s.
;
; The 24 x 24-bit product (48 bits) by shift and add, 24 rounds; its top 32 bits, with the
; low 16 as a sticky bit, go to __fpack.
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __h0, __h1, __h2, __h3, __rv
	.import	__fpack, __fp_ld2, __fp_st, __fp_ldx
	.export	__fmul, __fp_unpk, __fp_nan, __fp_inf, __fp_zero, __fp_qa, __fp_qb, __fmulr, __fmuli, __fmulx, __fmulrx

	.segment "CODE"

__fmuli:	pha			; X = &a, Y = &b, A = &result (fp_ind.s)
	jsr	__fp_ld2
	CALL	__fmul
	pla
	jmp	__fp_st
__fmulx:	jsr	__fp_ldx		; a in __h0, X = &b (fp_ind.s)
	jmp	__fmul
__fmulrx:	jsr	__fp_ldx		; b in __h0, X = &a
	jmp	__fmulr
__fmulr:	jsr	__fp_swap		; (__h0, __h1) = (b, a)
	jmp	__fmul
__fmul:	lda	__h0+2
	eor	__h1+2
	and	#$8000
	sta	__rv		; the sign
	lda	__h0+2
	and	#$7F80
	cmp	#$7F80
	beq	@aspec
	lda	__h1+2
	and	#$7F80
	cmp	#$7F80
	bne	:+
	jmp	@bspec
:
	lda	__h0+2
	asl	a
	ora	__h0
	bne	:+
	jmp	__fp_zero
:
	lda	__h1+2
	asl	a
	ora	__h1
	bne	:+
	jmp	__fp_zero
:
	ldx	#__h0
	jsr	__fp_unpk
	sta	__rv+2
	ldx	#__h1
	jsr	__fp_unpk
	clc
	adc	__rv+2
	sec
	sbc	#127
	sta	__rv+2		; E = ea + eb - 127
	; the product P (48 bits) in __h2+2 (bits 47-32), __h2 (31-16), __h3 (15-0): starts as
	; the multiplier b; the multiplicand a, shifted 24 left, is added to the top 24 bits
	lda	__h1
	sta	__h3
	lda	__h1+2
	sta	__h2
	stz	__h2+2
	lda	__h0+1		; a >> 8: the add to bits 47-32
	sta	__h1+2
	lda	__h0
	xba
	and	#$FF00		; (a & $FF) << 8: the add to bits 31-16 (24-31 only)
	sta	__h1
	lsr	__h2+2		; b's bit 0 -> carry
	ror	__h2
	ror	__h3
	ldx	#24
@m:	bcc	@s
	clc
	lda	__h2
	adc	__h1
	sta	__h2
	lda	__h2+2
	adc	__h1+2
	sta	__h2+2
@s:	ror	__h2+2
	ror	__h2
	ror	__h3
	dex
	bne	@m
	lda	__h3		; the low 16 bits: sticky
	beq	:+
	lda	__h2
	ora	#1
	sta	__h2
:	jmp	__fpack

@aspec:	lda	__h0+2		; a inf or NaN
	and	#$007F
	ora	__h0
	bne	__fp_qa
	lda	__h1+2		; a = inf: b NaN -> b, b = 0 -> NaN, else inf
	and	#$7F80
	cmp	#$7F80
	bne	:+
	lda	__h1+2
	and	#$007F
	ora	__h1
	bne	__fp_qb
	bra	__fp_inf
:	lda	__h1+2
	asl	a
	ora	__h1
	beq	__fp_nan
	bra	__fp_inf
@bspec:	lda	__h1+2		; b inf or NaN, a finite
	and	#$007F
	ora	__h1
	bne	__fp_qb
	lda	__h0+2		; b = inf: a = 0 -> NaN, else inf
	asl	a
	ora	__h0
	beq	__fp_nan
	bra	__fp_inf

; the special results (shared with fp_div.s); __rv: the sign
__fp_zero:
	lda	__rv
	sta	__h0+2
	stz	__h0
	RET
__fp_inf:
	lda	__rv
	ora	#$7F80
	sta	__h0+2
	stz	__h0
	RET
__fp_nan:			; the default NaN
	lda	#$FFC0
	sta	__h0+2
	stz	__h0
	RET
__fp_qa:			; a (a NaN), quiet
	lda	__h0+2
	ora	#$0040
	sta	__h0+2
	RET
__fp_qb:			; b (a NaN), quiet
	lda	__h1
	sta	__h0
	lda	__h1+2
	ora	#$0040
	sta	__h0+2
	RET

; __fp_unpk: X = the direct-page address of a float (finite, not 0) -> its 24-bit
; significand there, the leading 1 at bit 23 (a denormal shifted up), and A = its biased
; exponent (below 1 for a denormal). Changes Y.
__fp_unpk:
	lda	2,x
	asl	a
	xba
	and	#$00FF
	beq	@den
	tay
	lda	2,x
	and	#$007F
	ora	#$0080
	sta	2,x
	tya
	rts
@den:	ldy	#1
	lda	2,x
	and	#$007F
	sta	2,x
@n:	lda	2,x
	bit	#$0080
	bne	@d
	asl	0,x
	rol	2,x
	dey
	bra	@n
@d:	tya
	rts

; __h0 <-> __h1: the ...r entries (the compiler's operands the other way round)
__fp_swap:
	ldx	__h0
	lda	__h1
	sta	__h0
	stx	__h1
	ldx	__h0+2
	lda	__h1+2
	sta	__h0+2
	stx	__h1+2
	rts
