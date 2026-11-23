; rt_div32.s - part of cc816's arithmetic helpers (ld65 links a module only when a
; program uses one of its names). The contract, for all of them:
; cc816's arithmetic helpers, tuned for the 65816 (tests/rt checks them against
; host-made tables).
;
; The code generator calls them with JSR; A, X, Y 16-bit. They keep the __rg registers
; and __sp; they may change A, X, Y, __h0-__h3 and __rv.
;
;   __mul16                A * X -> A (the low 16 bits; signed and unsigned alike)
;   __udiv16 __sdiv16      A / X -> A (__udiv16 leaves the remainder in X)
;   __umod16 __smod16      A % X -> A
;   __mul32                __h0 * __h1 -> __h0 (the low 32 bits; its 16 x 16 -> 32 part
;                          unrolled: about 80 cycles less than a shift-and-add loop)
;   __udiv32 __sdiv32      __h0 / __h1 -> __h0 (__udiv32 leaves the remainder in __h2)
;   __umod32 __smod32      __h0 % __h1 -> __h0
;   __shl32 __shr32 __sar32   __h0 shifted by X (0-31 used) -> __h0
;   __umul1632 __smul1632  __h0 (16 bits) * __h1 (16 bits) -> __h0 (32 bits)
;
; C's rules: a quotient truncates toward 0, a remainder has the sign of the dividend.
; Division by 0 does not trap: the quotient is all ones, the remainder the dividend.
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __h0, __h1, __h2, __h3, __rv
	.export	__udiv32, __umod32, __sdiv32, __smod32

	.segment "CODE"

; ---- 32-bit unsigned division: quotient in __h0, remainder in __h2.
;  divisor < $10000: two 16-bit long-division steps with the remainder in A (the high
;  word's step skipped when it is below the divisor: 16 rounds in all);
;  divisor >= $10000: the quotient has 16 bits: 16 rounds from the high word.
__udiv32:
	lda	__h1+2
	beq	@w
	jmp	@full
@w:	lda	__h1
	bne	@nz
	jmp	@byzero
@nz:	bmi	@w16		; divisor < $8000: no 17th remainder bit, a shorter round
	lda	__h0+2
	cmp	__h1
	bcc	@shlow
	ldx	#16
	lda	#0
	asl	__h0+2
@s1:	rol	a
	cmp	__h1
	bcc	@sz1
	sbc	__h1
@sz1:	rol	__h0+2
	dex
	bne	@s1
	bra	@slow
@shlow:	stz	__h0+2
@slow:	ldx	#16
	asl	__h0
@s2:	rol	a
	cmp	__h1
	bcc	@sz2
	sbc	__h1
@sz2:	rol	__h0
	dex
	bne	@s2
	sta	__h2
	stz	__h2+2
	RET
@w16:	lda	__h0+2		; divisor < $10000: the high word first
	cmp	__h1
	bcc	@hlow
	ldx	#16
	lda	#0
	asl	__h0+2
@l1:	rol	a
	bcs	@b1
	cmp	__h1
	bcc	@z1
	sbc	__h1
@z1:	rol	__h0+2
	dex
	bne	@l1
	bra	@low
@b1:	sbc	__h1
	sec
	bra	@z1
@hlow:	stz	__h0+2		; quotient high 0, the remainder is the high word (in A)
@low:	ldx	#16		; then (remainder : low word) / divisor
	asl	__h0
@l2:	rol	a
	bcs	@b2
	cmp	__h1
	bcc	@z2
	sbc	__h1
@z2:	rol	__h0
	dex
	bne	@l2
	sta	__h2
	stz	__h2+2
	RET
@b2:	sbc	__h1
	sec
	bra	@z2
@byzero:
	lda	__h0
	sta	__h2
	lda	__h0+2
	sta	__h2+2
	lda	#$FFFF
	sta	__h0
	sta	__h0+2
	RET
@full:	lda	__h0+2		; divisor >= $10000: the remainder starts as the high word
	sta	__h2
	stz	__h2+2
	ldx	#16
	asl	__h0
@l3:	rol	__h2
	rol	__h2+2
	bcs	@b3		; 33 bits: certainly >= the divisor
	lda	__h2
	sec
	sbc	__h1
	tay
	lda	__h2+2
	sbc	__h1+2
	bcc	@z3
	sta	__h2+2
	sty	__h2
@z3:	rol	__h0
	dex
	bne	@l3
	stz	__h0+2
	RET
@b3:	lda	__h2
	sec
	sbc	__h1
	sta	__h2
	lda	__h2+2
	sbc	__h1+2
	sta	__h2+2
	sec
	bra	@z3

__umod32:
	CALL	__udiv32
	lda	__h2
	sta	__h0
	lda	__h2+2
	sta	__h0+2
	RET

neg_h0:	lda	#0
	sec
	sbc	__h0
	sta	__h0
	lda	#0
	sbc	__h0+2
	sta	__h0+2
	rts
neg_h1:	lda	#0
	sec
	sbc	__h1
	sta	__h1
	lda	#0
	sbc	__h1+2
	sta	__h1+2
	rts

__sdiv32:
	lda	__h0+2
	eor	__h1+2
	sta	__rv+2		; the quotient's sign
	lda	__h0+2
	bpl	@a
	jsr	neg_h0
@a:	lda	__h1+2
	bpl	@b
	jsr	neg_h1
@b:	CALL	__udiv32
	lda	__rv+2
	bpl	@r
	jsr	neg_h0
@r:	RET

__smod32:
	lda	__h0+2
	sta	__rv+2		; the remainder's sign: the dividend's
	bpl	@a
	jsr	neg_h0
@a:	lda	__h1+2
	bpl	@b
	jsr	neg_h1
@b:	CALL	__umod32
	lda	__rv+2
	bpl	@r
	jsr	neg_h0
@r:	RET
