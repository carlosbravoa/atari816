; rt_shift32.s - part of cc816's arithmetic helpers (ld65 links a module only when a
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
	.export	__shl32, __shr32, __sar32

	.segment "CODE"

; ---- 32-bit shifts by X (C: the count is 0-31): 16 or more moves a word, then 8 or
; more a byte (an unaligned word access), then the 0-7 bits left a bit at a time with one
; word in A (about 14 cycles a bit; 1UL << 13 about 130 cycles in all)
__shl32:
	txa
	and	#31
	beq	@r
	cmp	#16
	bcs	@w
	cmp	#8
	bcc	@b
	sbc	#8		; (C set) 0-7 bits left
	tax
	lda	__h0+1		; bytes 1-2: the high word
	sta	__h0+2
	lda	__h0
	xba
	and	#$FF00		; byte 0: the low word's high byte
	sta	__h0
	txa
	beq	@r
@b:	tax			; 1-7 bits
	lda	__h0+2
@l:	asl	__h0
	rol	a
	dex
	bne	@l
	sta	__h0+2
@r:	RET
@w:	sbc	#16		; (C set) 0-15: the low word, shifted, becomes the high one
	tax
	lda	__h0
	stz	__h0
	cpx	#8
	bcc	@w2
	xba
	and	#$FF00
	tay
	txa
	sbc	#8		; (C set by cpx)
	tax
	tya
@w2:	cpx	#0
	beq	@w4
@w3:	asl	a
	dex
	bne	@w3
@w4:	sta	__h0+2
	RET

__shr32:
	txa
	and	#31
	beq	@r
	cmp	#16
	bcs	@w
	cmp	#8
	bcc	@b
	sbc	#8
	tax
	lda	__h0+1		; bytes 1-2: the low word
	sta	__h0
	lda	__h0+3		; byte 3: the high word
	and	#$00FF
	sta	__h0+2
	txa
	beq	@r
@b:	tax
	lda	__h0+2
@l:	lsr	a
	ror	__h0
	dex
	bne	@l
	sta	__h0+2
@r:	RET
@w:	sbc	#16
	tax
	lda	__h0+2
	stz	__h0+2
	cpx	#8
	bcc	@w2
	xba
	and	#$00FF
	tay
	txa
	sbc	#8
	tax
	tya
@w2:	cpx	#0
	beq	@w4
@w3:	lsr	a
	dex
	bne	@w3
@w4:	sta	__h0
	RET

__sar32:
	txa
	and	#31
	beq	@r
	cmp	#16
	bcs	@w
	cmp	#8
	bcc	@b
	sbc	#8
	tax
	lda	__h0+1
	sta	__h0
	lda	__h0+3		; byte 3, sign-extended: the high word
	and	#$00FF
	eor	#$0080
	sec
	sbc	#$0080
	sta	__h0+2
	txa
	beq	@r
@b:	tax
	lda	__h0+2
@l:	cmp	#$8000
	ror	a
	ror	__h0
	dex
	bne	@l
	sta	__h0+2
@r:	RET
@w:	sbc	#16
	tax
	lda	__h0+2
	tay
	asl	a		; the sign into C
	lda	#0
	adc	#$FFFF
	eor	#$FFFF		; $FFFF when negative, else 0
	sta	__h0+2
	tya
	cpx	#8
	bcc	@w2
	xba
	and	#$00FF
	eor	#$0080
	sec
	sbc	#$0080
	tay
	txa
	sec
	sbc	#8
	tax
	tya
@w2:	cpx	#0
	beq	@w4
@w3:	cmp	#$8000
	ror	a
	dex
	bne	@w3
@w4:	sta	__h0
	RET
