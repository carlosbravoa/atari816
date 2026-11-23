; fp_div.s - cc816's floating point: __fdiv (__h0 / __h1 -> __h0). The contract and the
; rules: fp_pack.s.
;
; Restoring division of the 24-bit significands: 26 quotient bits (the leading 1, 23
; more, two guard bits), the remainder as a sticky bit; __fpack rounds.
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __h0, __h1, __h2, __h3, __rv
	.import	__fpack, __fp_unpk, __fp_nan, __fp_inf, __fp_zero, __fp_qa, __fp_qb, __fp_ld2, __fp_st, __fp_ldx
	.export	__fdiv, __fdivr, __fdivi, __fdivx, __fdivrx

	.segment "CODE"

__fdivi:	pha			; X = &a, Y = &b, A = &result (fp_ind.s)
	jsr	__fp_ld2
	CALL	__fdiv
	pla
	jmp	__fp_st
__fdivx:	jsr	__fp_ldx		; a in __h0, X = &b (fp_ind.s)
	jmp	__fdiv
__fdivrx:	jsr	__fp_ldx		; b in __h0, X = &a
	jmp	__fdivr
__fdivr:	jsr	__fp_swap		; (__h0, __h1) = (b, a)
	jmp	__fdiv
__fdiv:	lda	__h0+2
	eor	__h1+2
	and	#$8000
	sta	__rv		; the sign
	lda	__h0+2
	and	#$7F80
	cmp	#$7F80
	bne	:+
	jmp	@aspec
:
	lda	__h1+2
	and	#$7F80
	cmp	#$7F80
	bne	:+
	jmp	@bspec
:
	lda	__h1+2
	asl	a
	ora	__h1
	beq	@bzero
	lda	__h0+2
	asl	a
	ora	__h0
	bne	:+
	jmp	__fp_zero	; 0 / x
:	ldx	#__h0
	jsr	__fp_unpk
	sta	__rv+2
	ldx	#__h1
	jsr	__fp_unpk
	eor	#$FFFF
	sec
	adc	__rv+2
	clc
	adc	#127
	sta	__rv+2		; E = ea - eb + 127
	; a < b: a doubled (the quotient's leading bit is then 1), E one less
	lda	__h0+2
	cmp	__h1+2
	bne	:+
	lda	__h0
	cmp	__h1
:	bcs	@go
	asl	__h0
	rol	__h0+2
	dec	__rv+2
@go:	stz	__h2
	stz	__h2+2
	ldx	#26
@d:	asl	__h2
	rol	__h2+2
	lda	__h0
	sec
	sbc	__h1
	tay
	lda	__h0+2
	sbc	__h1+2
	bcc	@no
	sta	__h0+2
	sty	__h0
	inc	__h2		; (bit 0 is 0 after the shift)
@no:	asl	__h0
	rol	__h0+2
	dex
	bne	@d
	; the quotient's leading 1 is at bit 25: << 5 to bit 30; a remainder is sticky
	ldx	#5
:	asl	__h2
	rol	__h2+2
	dex
	bne	:-
	lda	__h0
	ora	__h0+2
	beq	:+
	lda	__h2
	ora	#1
	sta	__h2
:	jmp	__fpack

@bzero:	lda	__h0+2		; x / 0: 0 / 0 is NaN, else inf
	asl	a
	ora	__h0
	bne	:+
	jmp	__fp_nan
:	jmp	__fp_inf
@aspec:	lda	__h0+2		; a inf or NaN
	and	#$007F
	ora	__h0
	beq	:+
	jmp	__fp_qa
:	lda	__h1+2		; a = inf: b NaN -> b, b = inf -> NaN, else inf
	and	#$7F80
	cmp	#$7F80
	beq	:+
	jmp	__fp_inf
:	lda	__h1+2
	and	#$007F
	ora	__h1
	beq	:+
	jmp	__fp_qb
:	jmp	__fp_nan
@bspec:	lda	__h1+2		; b inf or NaN, a finite: NaN -> b, inf -> 0
	and	#$007F
	ora	__h1
	beq	:+
	jmp	__fp_qb
:	jmp	__fp_zero

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
