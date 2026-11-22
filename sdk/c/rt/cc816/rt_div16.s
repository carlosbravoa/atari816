; rt_div16.s - part of cc816's arithmetic helpers (ld65 links a module only when a
; program uses one of its names). The contract, for all of them:
; cc816's arithmetic helpers, tuned for the 65816 as sdk/c/fastrt is for vbcc (the same
; algorithms; tests/rt checks them against host-made tables).
;
; The code generator calls them with JSR; A, X, Y 16-bit. They keep the __rg registers
; and __sp; they may change A, X, Y, __h0-__h3 and __rv.
;
;   __mul16                A * X -> A (the low 16 bits; signed and unsigned alike)
;   __udiv16 __sdiv16      A / X -> A (__udiv16 leaves the remainder in X)
;   __umod16 __smod16      A % X -> A
;   __mul32                __h0 * __h1 -> __h0 (the low 32 bits; its 16 x 16 -> 32 part
;                          unrolled: about 80 cycles less than fastrt's loop)
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
	.importzp __h0, __h1, __h2, __h3, __rv
	.export	__udiv16, __umod16, __sdiv16, __smod16

	.segment "CODE"

; ---- 16-bit division: the remainder in A, the quotient bits shifted in as the dividend
; bits go out (one ROL a round); 0 at once when the dividend is below the divisor, 8
; rounds when the dividend is below 256
__udiv16:
	sta	__h2
	stx	__h3
udiv:	lda	__h2		; __h2 / __h3 -> A = quotient, X = remainder
	cmp	__h3
	bcc	@small		; dividend < divisor: quotient 0
	ldx	#16
	ldy	__h3
	beq	@full		; / 0: 16 rounds, all ones
	cmp	#$0100
	bcs	@full
	xba			; dividend < 256: its 8 bits to the top, 8 rounds
	sta	__h2
	ldx	#8
@full:	lda	__h3
	bmi	@full17
	lda	#0		; divisor < $8000: the remainder never reaches 17 bits
	asl	__h2
@sloop:	rol	a
	cmp	__h3
	bcc	@szero
	sbc	__h3
@szero:	rol	__h2
	dex
	bne	@sloop
	tax
	lda	__h2
	rts
@full17:
	lda	#0
	asl	__h2		; the first dividend bit into C
@loop:	rol	a		; remainder * 2 + the bit
	bcs	@big		; 17 bits: certainly >= the divisor
	cmp	__h3
	bcc	@zero
	sbc	__h3		; (C is set and stays set: no borrow)
@zero:	rol	__h2		; the quotient bit in, the next dividend bit out
	dex
	bne	@loop
	tax			; the remainder
	lda	__h2		; the quotient
	rts
@big:	sbc	__h3		; C was set: the 17-bit value minus the divisor
	sec			; the quotient bit
	bra	@zero
@small:	tax			; quotient 0, remainder the dividend
	lda	#0
	rts

__umod16:
	sta	__h2
	stx	__h3
	jsr	udiv
	txa
	rts

__sdiv16:
	stx	__h3
	ldy	#0		; Y bit 0: negate the quotient
	cmp	#$8000
	bcc	@p0
	eor	#$FFFF
	inc	a
	iny
@p0:	sta	__h2
	lda	__h3
	bpl	@p1
	eor	#$FFFF
	inc	a
	sta	__h3
	tya
	eor	#1
	tay
@p1:	phy
	jsr	udiv
	ply
	beq	@pos
	eor	#$FFFF
	inc	a
@pos:	rts

__smod16:
	stx	__h3
	ldy	#0		; Y: the dividend was negative
	cmp	#$8000
	bcc	@m0
	eor	#$FFFF
	inc	a
	iny
@m0:	sta	__h2
	lda	__h3
	bpl	@m1
	eor	#$FFFF
	inc	a
	sta	__h3
@m1:	phy
	jsr	udiv
	txa
	ply
	beq	@mpos
	eor	#$FFFF
	inc	a
@mpos:	rts
