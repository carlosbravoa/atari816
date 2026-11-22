; fp_pack.s - cc816's floating point: rounding and packing, shared by the arithmetic.
;
; cc816's float, double and long double are all IEEE 754 single precision (32 bits: sign,
; 8-bit exponent biased by 127, 23-bit fraction). The helpers (fp_add.s, fp_mul.s,
; fp_div.s, fp_cmp.s, fp_conv.s) follow the arithmetic helpers' contract (rt_mul32.s):
; JSR, A, X, Y 16-bit; operands in __h0 (and __h1), the result in __h0 (__fcmp: in A);
; they may change A, X, Y, __h0-__h3 and __rv, and keep everything else.
;
; What they implement: round to nearest, ties to even, on every operation; gradual
; underflow (denormal operands and results, rounded once); overflow to infinity; the
; infinities and NaN as IEEE 754 says, with x86's NaN choices (an operation with a NaN
; operand returns that NaN made quiet, the first one when both are NaN; an invalid
; operation, 0/0, inf - inf, 0 * inf, inf / inf, returns the default NaN $FFC00000).
; No exception flags, no other rounding modes.
;
; __fpack: the result from a sign, an exponent and a significand with guard bits.
;   __h2 (32 bits)  the significand m, not 0; the value is m * 2^(E - 157), so with m's
;                   leading 1 at bit 30, E is the biased exponent. The bits below the 24
;                   kept are guard bits; any bit lost before (sticky) must be ORed into
;                   bit 0. m may have its leading 1 anywhere: __fpack normalises it.
;   __rv            the sign: $8000 or 0
;   __rv+2          E, a signed 16-bit number (any value: below 1 gives a denormal or 0,
;                   255 and above infinity)
;   -> __h0         the float, rounded to nearest even
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __h0, __h1, __h2, __h3, __rv
	.export	__fpack, __fp_rshift

	.segment "CODE"

__fpack:
	; leading 1 at bit 31: one step right (the lost bit is sticky)
	lda	__h2+2
	bpl	@left
	lsr	__h2+2
	ror	__h2
	bcc	:+
	lda	__h2
	ora	#1
	sta	__h2
:	inc	__rv+2
	bra	@norm
	; leading 1 below bit 30: shift left (exact), bytes first
@left:	and	#$FF80
	bne	@lbit
	lda	__h2+2
	ora	__h2
	beq	@zero
@l8:	lda	__h2+1		; m <<= 8 (bits 31..23 are 0)
	sta	__h2+2
	lda	__h2
	xba
	and	#$FF00
	sta	__h2
	lda	__rv+2
	sec
	sbc	#8
	sta	__rv+2
	lda	__h2+2
	and	#$FF80
	beq	@l8
@lbit:	lda	__h2+2
@l1:	bit	#$4000
	bne	@norm
	asl	__h2
	rol	__h2+2
	dec	__rv+2
	lda	__h2+2
	bra	@l1
@zero:	lda	__rv		; (not reached by the helpers: they handle 0 first)
	sta	__h0+2
	stz	__h0
	RET

	; now 2^30 <= m < 2^31. E < 1: a denormal (or 0): shift right by 1 - E, sticky
@norm:	lda	__rv+2
	bmi	@den
	bne	@round
@den:	lda	#1
	sec
	sbc	__rv+2		; 1 - E >= 1
	cmp	#32
	bcc	@dsh
	lda	#1		; everything shifted out: only the sticky bit is left
	sta	__h2
	stz	__h2+2
	bra	@done
@dsh:	tax
	jsr	__fp_rshift
@done:	lda	#1
	sta	__rv+2

	; round at bit 7: the 7 bits below the 24 kept
@round:	lda	__h2
	and	#$007F
	sta	__h3
	asl	__h2		; m >>= 7: << 1, then >> 8
	rol	__h2+2
	lda	__h2+1
	sta	__h2
	lda	__h2+3
	and	#$00FF
	sta	__h2+2
	lda	__h3
	cmp	#$40
	bcc	@pack		; below half: down
	bne	@up		; above half: up
	lda	__h2		; a tie: to even
	lsr	a
	bcc	@pack
@up:	inc	__h2
	bne	:+
	inc	__h2+2
:	lda	__h2+2
	cmp	#$0100		; 2^24: the significand overflowed into the next binade
	bcc	@pack
	lda	#$0080
	sta	__h2+2		; (the low word is 0)
	inc	__rv+2
	; pack: the exponent field is E - 1 plus the leading 1 (bit 23): a denormal (E = 1,
	; no leading 1) gets field 0, and one that rounded up to 2^23 field 1
@pack:	lda	__rv+2
	cmp	#255
	bcs	@inf
	dec	a
	xba			; (E - 1) << 7
	lsr	a
	clc
	adc	__h2+2
	ora	__rv
	sta	__h0+2
	lda	__h2
	sta	__h0
	RET
@inf:	lda	__rv
	ora	#$7F80
	sta	__h0+2
	stz	__h0
	RET

; __fp_rshift: __h2 (32 bits) >>= X (1-31), every bit shifted out ORed into bit 0
; (sticky). Changes A, X, __h3.
__fp_rshift:
	stz	__h3
	cpx	#16
	bcc	@b8
	lda	__h2		; a word out
	sta	__h3
	lda	__h2+2
	sta	__h2
	stz	__h2+2
	txa
	sec
	sbc	#16
	tax
	beq	@st
@b8:	cpx	#8
	bcc	@bits
	lda	__h2		; a byte out
	and	#$00FF
	tsb	__h3
	lda	__h2+1
	sta	__h2
	lda	__h2+3
	and	#$00FF
	sta	__h2+2
	txa
	sec
	sbc	#8
	tax
	beq	@st
@bits:	lsr	__h2+2
	ror	__h2
	bcc	:+
	inc	__h3
:	dex
	bne	@bits
@st:	lda	__h3
	beq	:+
	lda	__h2
	ora	#1
	sta	__h2
:	rts
