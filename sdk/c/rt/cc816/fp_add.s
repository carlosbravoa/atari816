; fp_add.s - cc816's floating point: __fadd (__h0 + __h1 -> __h0), __fsub (__h0 - __h1).
; The contract and the rules: fp_pack.s.
;
; The larger magnitude goes first; both significands get 8 guard bits (the leading 1 at
; bit 31); the smaller is shifted right by the exponents' difference, its lost bits kept
; as a sticky bit; then the add or subtract, and __fpack rounds once. x + (-x) is +0;
; -0 + -0 is -0.
	.p816
	.smart	-
	.a16
	.i16
	.importzp __h0, __h1, __h2, __h3, __rv
	.import	__fpack, __fp_rshift, __fp_ld2, __fp_st, __fp_ldx
	.export	__fadd, __fsub, __faddr, __fsubr, __faddi, __fsubi, __faddx, __faddrx, __fsubx, __fsubrx

	.segment "CODE"

__faddi:	pha			; X = &a, Y = &b, A = &result (fp_ind.s)
	jsr	__fp_ld2
	jsr	__fadd
	pla
	jmp	__fp_st
__fsubi:	pha			; X = &a, Y = &b, A = &result (fp_ind.s)
	jsr	__fp_ld2
	jsr	__fsub
	pla
	jmp	__fp_st
__faddx:	jsr	__fp_ldx		; a in __h0, X = &b (fp_ind.s)
	jmp	__fadd
__faddrx:	jsr	__fp_ldx		; b in __h0, X = &a
	jmp	__faddr
__fsubx:	jsr	__fp_ldx		; a in __h0, X = &b (fp_ind.s)
	jmp	__fsub
__fsubrx:	jsr	__fp_ldx		; b in __h0, X = &a
	jmp	__fsubr
__faddr:	jsr	__fp_swap		; (__h0, __h1) = (b, a)
	jmp	__fadd
__fsubr:	jsr	__fp_swap		; (__h0, __h1) = (b, a)
	jmp	__fsub
__fsub:	lda	__h1+2		; a - b = a + (-b), but a NaN b keeps its sign
	and	#$7FFF
	cmp	#$7F80
	bcc	@flip
	bne	__fadd
	lda	__h1
	bne	__fadd
@flip:	lda	__h1+2
	eor	#$8000
	sta	__h1+2
__fadd:	lda	__h0+2
	and	#$7F80
	cmp	#$7F80
	bne	:+
	jmp	@aspec
:	lda	__h1+2
	and	#$7F80
	cmp	#$7F80
	bne	:+
	jmp	@bspec
	; zeros
:	lda	__h1+2
	asl	a
	ora	__h1
	bne	@bnz
	lda	__h0+2		; b = +-0: the result is a, unless a is 0 too
	asl	a
	ora	__h0
	bne	@reta
	lda	__h0+2		; +-0 + +-0: -0 only when both are -0
	and	__h1+2
	sta	__h0+2
@reta:	rts
@bnz:	lda	__h0+2
	asl	a
	ora	__h0
	bne	@work
@retb:	lda	__h1		; a = +-0, b not: b
	sta	__h0
	lda	__h1+2
	sta	__h0+2
	rts

	; |a| >= |b|: swap if not
@work:	lda	__h0+2
	and	#$7FFF
	sta	__h2
	lda	__h1+2
	and	#$7FFF
	cmp	__h2
	bcc	@ord
	bne	@swap
	lda	__h1
	cmp	__h0
	bcc	@ord
@swap:	ldx	__h0
	lda	__h1
	sta	__h0
	stx	__h1
	ldx	__h0+2
	lda	__h1+2
	sta	__h0+2
	stx	__h1+2
@ord:	lda	__h0+2
	and	#$8000
	sta	__rv		; the result's sign: the larger's
	lda	__h0+2
	eor	__h1+2
	sta	__h3+2		; bit 15: the signs differ (a subtraction)
	; unpack a: exponent -> __rv+2, significand << 8 -> __h2
	lda	__h0+2
	asl	a
	xba
	and	#$00FF
	bne	:+
	inc	a		; a denormal: exponent 1, no leading 1
	sta	__rv+2
	lda	__h0+2
	and	#$007F
	bra	@sa
:	sta	__rv+2
	lda	__h0+2
	and	#$007F
	ora	#$0080
@sa:	sta	__h0+2		; a's 24-bit significand in __h0; << 8 into __h2:
	lda	__h0+1		; bits 23-8 (the word at __h0+1)
	sta	__h2+2
	lda	__h0
	xba
	and	#$FF00
	sta	__h2
	; unpack b the same way into __h0 (a is no longer needed there)
	lda	__h1+2
	asl	a
	xba
	and	#$00FF
	bne	:+
	inc	a
	tay			; Y: b's exponent
	lda	__h1+2
	and	#$007F
	bra	@sb
:	tay
	lda	__h1+2
	and	#$007F
	ora	#$0080
@sb:	sta	__h1+2
	lda	__h1+1
	sta	__h0+2
	lda	__h1
	xba
	and	#$FF00
	sta	__h0
	; align b: shift right by ea - eb (0..253), sticky
	tya
	eor	#$FFFF
	sec
	adc	__rv+2		; ea - eb
	beq	@aligned
	cmp	#32
	bcc	@sh
	stz	__h0+2		; all of b is below the guard bits: sticky only
	lda	#1
	sta	__h0
	bra	@aligned
@sh:	tax			; __fp_rshift works on __h2: swap a and b around it
	ldy	__h2
	lda	__h0
	sta	__h2
	sty	__h0
	ldy	__h2+2
	lda	__h0+2
	sta	__h2+2
	sty	__h0+2
	jsr	__fp_rshift
	ldy	__h2		; back: a in __h2, b in __h0
	lda	__h0
	sta	__h2
	sty	__h0
	ldy	__h2+2
	lda	__h0+2
	sta	__h2+2
	sty	__h0+2
@aligned:
	bit	__h3+2
	bmi	@diff
	; same signs: a + b
	clc
	lda	__h2
	adc	__h0
	sta	__h2
	lda	__h2+2
	adc	__h0+2
	sta	__h2+2
	bcc	@sum
	ror	__h2+2		; a carry out of bit 31: back in, one bit right
	ror	__h2
	bcc	:+
	lda	__h2
	ora	#1
	sta	__h2
:	jmp	__fpack		; (the sum is 2^32 + m: halved, the leading 1 at bit 31, E = ea)
@sum:	dec	__rv+2		; the leading 1 at bit 31: E is one less (fp_pack.s)
	jmp	__fpack
	; different signs: a - b (>= 0)
@diff:	sec
	lda	__h2
	sbc	__h0
	sta	__h2
	lda	__h2+2
	sbc	__h0+2
	sta	__h2+2
	ora	__h2
	bne	@sum
	stz	__h0		; exactly 0: +0
	stz	__h0+2
	rts

	; a is infinite or NaN
@aspec:	lda	__h0+2
	and	#$007F
	ora	__h0
	bne	@anan
	lda	__h1+2		; a = inf: b NaN -> b; b = inf of the other sign -> NaN
	and	#$7F80
	cmp	#$7F80
	bne	@reta2
	lda	__h1+2
	and	#$007F
	ora	__h1
	bne	@bnan
	lda	__h0+2
	eor	__h1+2
	bpl	@reta2
	lda	#$FFC0		; inf - inf: the default NaN
	sta	__h0+2
	stz	__h0
@reta2:	rts
@anan:	lda	__h0+2		; a NaN: quiet
	ora	#$0040
	sta	__h0+2
	rts
	; b is infinite or NaN, a finite: b (quiet)
@bspec:	lda	__h1+2
	and	#$007F
	ora	__h1
	bne	@bnan
	jmp	@retb
@bnan:	lda	__h1
	sta	__h0
	lda	__h1+2
	ora	#$0040
	sta	__h0+2
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
