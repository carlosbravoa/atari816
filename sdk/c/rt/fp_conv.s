; fp_conv.s - cc816's floating point: conversions between float and the integers. The
; contract: fp_pack.s (__h0 -> __h0).
;
;   __ltof   long -> float              rounded to nearest even (above 2^24 not every
;   __ultof  unsigned long -> float     integer is a float)
;   __ftol   float -> long              truncated toward zero
;   __ftoul  float -> unsigned long     truncated toward zero
;
; The compiler converts the 8- and 16-bit types through these (an int is extended to a
; long first; a float to int or unsigned is __ftol's low word). Out of range (C leaves it
; undefined): __ftol gives $80000000 (as x86) for |x| >= 2^31 and NaN; __ftoul gives
; $FFFFFFFF for x >= 2^32 and NaN, and a negative x is converted as __ftol does.
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __h0, __h2, __h3, __rv
	.import	__fpack
	.export	__ltof, __ultof, __ftol, __ftoul

	.segment "CODE"

__ltof:	lda	__h0+2
	and	#$8000
	sta	__rv
	beq	ltof_go
	sec			; |x|
	lda	#0
	sbc	__h0
	sta	__h0
	lda	#0
	sbc	__h0+2
	sta	__h0+2
	bra	ltof_go
__ultof:
	stz	__rv
ltof_go:
	lda	__h0
	ora	__h0+2
	beq	@z		; 0 -> +0 (already in __h0)
	lda	__h0
	sta	__h2
	lda	__h0+2
	sta	__h2+2
	lda	#157		; the leading 1 at bit 30 would be 2^30: E = 127 + 30
	sta	__rv+2
	jmp	__fpack
@z:	RET

__ftoul:
	lda	__h0+2
	bmi	__ftol		; negative: as __ftol
	asl	a
	xba
	and	#$00FF
	cmp	#127
	bcc	zero
	cmp	#127 + 32
	bcc	conv
	lda	#$FFFF		; 2^32 and above, NaN
	sta	__h0
	sta	__h0+2
	RET

__ftol:	lda	__h0+2
	asl	a
	xba
	and	#$00FF		; the biased exponent
	cmp	#127
	bcc	zero		; |x| < 1
	cmp	#127 + 31
	bcc	conv
	stz	__h0		; |x| >= 2^31, NaN
	lda	#$8000
	sta	__h0+2
	RET
zero:	stz	__h0
	stz	__h0+2
	RET

	; A = the exponent (127..158): the significand (24 bits) shifted by E - 150
conv:	tax
	lda	__h0+2
	sta	__rv		; the sign
	and	#$007F
	ora	#$0080
	sta	__h0+2
	txa
	sec
	sbc	#150
	bcc	@right
	beq	@sign
	tax			; left 1..8
@l:	asl	__h0
	rol	__h0+2
	dex
	bne	@l
	bra	@sign
@right:	eor	#$FFFF		; right 1..23 (truncating)
	inc	a
	tax
	cpx	#16
	bcc	@r8
	lda	__h0+2
	sta	__h0
	stz	__h0+2
	txa
	sec
	sbc	#16
	tax
	beq	@sign
@r8:	cpx	#8
	bcc	@r1
	lda	__h0+1
	sta	__h0
	lda	__h0+3
	and	#$00FF
	sta	__h0+2
	txa
	sec
	sbc	#8
	tax
	beq	@sign
@r1:	lsr	__h0+2
	ror	__h0
	dex
	bne	@r1
@sign:	bit	__rv
	bpl	:+
	sec			; negative: 0 - x
	lda	#0
	sbc	__h0
	sta	__h0
	lda	#0
	sbc	__h0+2
	sta	__h0+2
:	RET
