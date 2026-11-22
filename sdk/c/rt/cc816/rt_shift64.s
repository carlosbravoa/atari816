; rt_shift64.s - cc816's 64-bit shifts (long long), linked only by a program that shifts
; a long long by a variable or by a constant the code generator does not do inline (it
; does multiples of 16, and 1 to 3, itself).
;
; The contract of the 64-bit helpers (rt_mul64.s, rt_div64.s, this file): called with
; JSR, A, X, Y 16-bit. A long long operand is 8 bytes in the direct page, low word first:
; the first in __h0..__h1 (__h0, __h0+2, __h1, __h1+2), the second in __h2..__h3; the
; result in __h0..__h1. They keep the __rg registers and __sp; they may change A, X, Y,
; __h0-__h3 and __rv.
;
;   __shl64 __shr64 __sar64   __h0..__h1 shifted by X (0-63 used) -> __h0..__h1
	.p816
	.smart	-
	.a16
	.i16
	.importzp __h0, __h1
	.export	__shl64, __shr64, __sar64

	.segment "CODE"

; ---- left: whole words first (32, then 16), then a bit at a time
__shl64:
	txa
	and	#63
	beq	@r
	cmp	#32
	bcc	@w16
	sbc	#32		; (C set)
	tax
	lda	__h0+2
	sta	__h1+2
	lda	__h0
	sta	__h1
	stz	__h0+2
	stz	__h0
	txa
@w16:	cmp	#16
	bcc	@bits
	sbc	#16
	tax
	lda	__h1
	sta	__h1+2
	lda	__h0+2
	sta	__h1
	lda	__h0
	sta	__h0+2
	stz	__h0
	txa
@bits:	tax
	beq	@r
@l:	asl	__h0
	rol	__h0+2
	rol	__h1
	rol	__h1+2
	dex
	bne	@l
@r:	rts

; ---- right, unsigned
__shr64:
	txa
	and	#63
	beq	@r
	cmp	#32
	bcc	@w16
	sbc	#32
	tax
	lda	__h1
	sta	__h0
	lda	__h1+2
	sta	__h0+2
	stz	__h1
	stz	__h1+2
	txa
@w16:	cmp	#16
	bcc	@bits
	sbc	#16
	tax
	lda	__h0+2
	sta	__h0
	lda	__h1
	sta	__h0+2
	lda	__h1+2
	sta	__h1
	stz	__h1+2
	txa
@bits:	tax
	beq	@r
@l:	lsr	__h1+2
	ror	__h1
	ror	__h0+2
	ror	__h0
	dex
	bne	@l
@r:	rts

; ---- right, signed: the words that come in are the sign's
__sar64:
	lda	__h1+2
	asl	a
	lda	#0
	adc	#$FFFF
	eor	#$FFFF		; $FFFF when negative, else 0
	tay
	txa
	and	#63
	beq	@r
	cmp	#32
	bcc	@w16
	sbc	#32
	tax
	lda	__h1
	sta	__h0
	lda	__h1+2
	sta	__h0+2
	sty	__h1
	sty	__h1+2
	txa
@w16:	cmp	#16
	bcc	@bits
	sbc	#16
	tax
	lda	__h0+2
	sta	__h0
	lda	__h1
	sta	__h0+2
	lda	__h1+2
	sta	__h1
	sty	__h1+2
	txa
@bits:	tax
	beq	@r
@l:	cpy	#$8000		; C = the sign (Y is 0 or $FFFF)
	ror	__h1+2
	ror	__h1
	ror	__h0+2
	ror	__h0
	dex
	bne	@l
@r:	rts
