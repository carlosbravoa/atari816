; fp_cmp.s - cc816's floating point: __fcmp, the comparison of __h0 (a) and __h1 (b).
; The contract: fp_pack.s. The result in A:
;   -1  a < b      0  a == b (also +0 and -0)      1  a > b      2  unordered (a NaN)
; The compiler tests it: a < b is A < 0 (signed), a <= b A < 1, a > b A == 1, a >= b
; A < 2 (unsigned), a == b A == 0, a != b A != 0: with a NaN only != is true.
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __h0, __h1
	.import	__fp_ld2, __fp_ldx
	.export	__fcmp, __fcmpr, __fcmpi, __fcmpx, __fcmprx

	.segment "CODE"

__fcmpi:	jsr	__fp_ld2		; X = &a, Y = &b (fp_ind.s): the result in A
	jmp	__fcmp
__fcmpx:	jsr	__fp_ldx		; a in __h0, X = &b (fp_ind.s)
	jmp	__fcmp
__fcmprx:	jsr	__fp_ldx		; b in __h0, X = &a
	jmp	__fcmpr
__fcmpr:	jsr	__fp_swap		; (__h0, __h1) = (b, a)
	jmp	__fcmp
__fcmp:	lda	__h0+2
	and	#$7FFF
	cmp	#$7F80
	bcc	@an
	bne	@un
	lda	__h0
	bne	@un
@an:	lda	__h1+2
	and	#$7FFF
	cmp	#$7F80
	bcc	@bn
	bne	@un
	lda	__h1
	bne	@un
@bn:	lda	__h0+2		; +-0 and +-0: equal
	ora	__h1+2
	asl	a
	ora	__h0
	ora	__h1
	beq	@eq
	lda	__h0+2
	eor	__h1+2
	bmi	@ds
	lda	__h0+2		; the same sign: compare the magnitudes
	cmp	__h1+2
	bne	@ne
	lda	__h0
	cmp	__h1
	beq	@eq
@ne:	lda	#0		; C: |a| > |b| -> 1, else -1
	rol	a
	asl	a
	dec	a
	bit	__h0+2
	bpl	:+
	eor	#$FFFF		; both negative: the other way round
	inc	a
:	RET
@ds:	lda	__h0+2		; the signs differ: the negative one is the smaller
	bmi	@lt
	lda	#1
	RET
@lt:	lda	#$FFFF
	RET
@eq:	lda	#0
	RET
@un:	lda	#2
	RET

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
