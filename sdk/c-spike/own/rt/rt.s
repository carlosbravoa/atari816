; rt.s - cc816 runtime helpers (16-bit registers throughout).
;   __mul16              A * X -> A                     (uses __h2, __h3)
;   __udiv16 __umod16    A / X -> A (quotient or remainder; __udiv16 leaves the remainder in X)
;   __sdiv16 __smod16    signed (C99: the quotient truncates, the remainder has the sign
;                        of the dividend)
;   __mul32 __udiv32 __umod32 __sdiv32 __smod32    __h0 op __h1 -> __h0
;   __shl32 __shr32 __sar32                        __h0 shifted by X -> __h0
; Helpers keep the __rg registers; they may change __h0-__h3, __rv, A, X, Y.
	.p816
	.smart	+
	.a16
	.i16
	.importzp __h0, __h1, __h2, __h3, __rv
	.export	__mul16, __udiv16, __umod16, __sdiv16, __smod16
	.export	__mul32, __udiv32, __umod32, __sdiv32, __smod32
	.export	__shl32, __shr32, __sar32, __umul1632, __smul1632

	.segment "CODE"
__mul16:
	sta	__h3
	stx	__h2
	lda	#0
	bra	@test
@loop:	lsr	__h2
	bcc	@skip
	clc
	adc	__h3
@skip:	asl	__h3
@test:	ldx	__h2
	bne	@loop
	rts

__udiv16:			; A / X -> A, remainder X
	sta	__h2
	stx	__h3
	lda	#0
	ldx	#16
@loop:	asl	__h2
	rol	a
	cmp	__h3
	bcc	@skip
	sbc	__h3
	inc	__h2
@skip:	dex
	bne	@loop
	tax
	lda	__h2
	rts

__umod16:
	jsr	__udiv16
	txa
	rts

; signed: |a| / |b|, the signs put back
__sdiv16:
	stx	__rv
	eor	__rv		; sign of the quotient in bit 15
	sta	__rv+2
	eor	__rv		; A again
	bpl	@a
	eor	#$FFFF
	inc	a
@a:	pha
	txa
	bpl	@b
	eor	#$FFFF
	inc	a
@b:	tax
	pla
	jsr	__udiv16
	bit	__rv+2
	bpl	@r
	eor	#$FFFF
	inc	a
@r:	rts

__smod16:
	sta	__rv+2		; the dividend's sign
	cmp	#0
	bpl	@a
	eor	#$FFFF
	inc	a
@a:	pha
	txa
	bpl	@b
	eor	#$FFFF
	inc	a
@b:	tax
	pla
	jsr	__udiv16
	txa
	bit	__rv+2
	bpl	@r
	eor	#$FFFF
	inc	a
@r:	rts

; 32 x 32 -> 32: lo*lo (32 bits) + (lo0*hi1 + hi0*lo1) << 16
__mul32:
	lda	__h0+2
	ldx	__h1
	jsr	__mul16
	sta	__rv
	lda	__h0
	ldx	__h1+2
	jsr	__mul16
	clc
	adc	__rv
	sta	__rv
	lda	__h1		; 16 x 16 -> 32: multiplier in __h2 becomes the low word
	sta	__h2
	lda	#0
	ldx	#16
	lsr	__h2
@loop:	bcc	@noadd
	clc
	adc	__h0
@noadd:	ror	a
	ror	__h2
	dex
	bne	@loop
	clc
	adc	__rv
	sta	__h0+2
	lda	__h2
	sta	__h0
	rts

; unsigned 32 / 32: quotient in __h0, remainder in __h2
__udiv32:
	lda	__h1+2
	bne	@long
	; divisor < 65536: a 16-bit remainder (its 17th bit in carry), one word at a time
	lda	#0
	ldx	#16
@hi:	asl	__h0+2
	rol	a
	bcs	@sh
	cmp	__h1
	bcc	@nh
@sh:	sbc	__h1
	inc	__h0+2
@nh:	dex
	bne	@hi
	ldx	#16
@lo:	asl	__h0
	rol	a
	bcs	@sl
	cmp	__h1
	bcc	@nl
@sl:	sbc	__h1
	inc	__h0
@nl:	dex
	bne	@lo
	sta	__h2
	stz	__h2+2
	rts
@long:	stz	__h2
	stz	__h2+2
	ldx	#32
@loop:	asl	__h0
	rol	__h0+2
	rol	__h2
	rol	__h2+2
	lda	__h2
	sec
	sbc	__h1
	tay
	lda	__h2+2
	sbc	__h1+2
	bcc	@skip
	sta	__h2+2
	sty	__h2
	inc	__h0
@skip:	dex
	bne	@loop
	rts

__umod32:
	jsr	__udiv32
	lda	__h2
	sta	__h0
	lda	__h2+2
	sta	__h0+2
	rts

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
	sta	__rv+2		; quotient sign
	lda	__h0+2
	bpl	@a
	jsr	neg_h0
@a:	lda	__h1+2
	bpl	@b
	jsr	neg_h1
@b:	jsr	__udiv32
	lda	__rv+2
	bpl	@r
	jsr	neg_h0
@r:	rts

__smod32:
	lda	__h0+2
	sta	__rv+2		; remainder sign = dividend sign
	bpl	@a
	jsr	neg_h0
@a:	lda	__h1+2
	bpl	@b
	jsr	neg_h1
@b:	jsr	__umod32
	lda	__rv+2
	bpl	@r
	jsr	neg_h0
@r:	rts

__shl32:
	txa
	and	#31
	beq	@r
	tax
@l:	asl	__h0
	rol	__h0+2
	dex
	bne	@l
@r:	rts

__shr32:
	txa
	and	#31
	beq	@r
	tax
@l:	lsr	__h0+2
	ror	__h0
	dex
	bne	@l
@r:	rts

__sar32:
	txa
	and	#31
	beq	@r
	tax
@l:	lda	__h0+2
	cmp	#$8000
	ror	__h0+2
	ror	__h0
	dex
	bne	@l
@r:	rts

; 16 x 16 -> 32: __h0 (16) * __h1 (16) -> __h0 (32)
__umul1632:
	lda	__h1		; the multiplier becomes the product's low word
	sta	__h2
	lda	#0
	ldx	#16
	lsr	__h2
@loop:	bcc	@noadd
	clc
	adc	__h0
@noadd:	ror	a
	ror	__h2
	dex
	bne	@loop
	sta	__h0+2
	lda	__h2
	sta	__h0
	rts

; signed: the unsigned product, minus b << 16 if a < 0, minus a << 16 if b < 0
__smul1632:
	lda	__h0
	sta	__h3
	lda	__h1
	sta	__h3+2
	jsr	__umul1632
	lda	__h3
	bpl	@a
	lda	__h0+2
	sec
	sbc	__h3+2
	sta	__h0+2
@a:	lda	__h3+2
	bpl	@b
	lda	__h0+2
	sec
	sbc	__h3
	sta	__h0+2
@b:	rts
