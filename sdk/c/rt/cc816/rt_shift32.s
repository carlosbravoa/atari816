; rt_shift32.s - part of cc816's arithmetic helpers (ld65 links a module only when a
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
	.export	__shl32, __shr32, __sar32

	.segment "CODE"

; ---- 32-bit shifts by X (C: the count is 0-31); 16 or more moves a word first
__shl32:
	txa
	and	#31
	beq	@r
	cmp	#16
	bcc	@go
	sbc	#16		; (C set)
	tax
	lda	__h0
	sta	__h0+2
	stz	__h0
	txa
	beq	@r
@go:	tax
@l:	asl	__h0
	rol	__h0+2
	dex
	bne	@l
@r:	rts

__shr32:
	txa
	and	#31
	beq	@r
	cmp	#16
	bcc	@go
	sbc	#16
	tax
	lda	__h0+2
	sta	__h0
	stz	__h0+2
	txa
	beq	@r
@go:	tax
@l:	lsr	__h0+2
	ror	__h0
	dex
	bne	@l
@r:	rts

__sar32:
	txa
	and	#31
	beq	@r
	cmp	#16
	bcc	@go
	sbc	#16
	tax
	lda	__h0+2
	sta	__h0
	asl	a		; the sign into C
	lda	#0
	adc	#$FFFF
	eor	#$FFFF		; $FFFF when negative, else 0
	sta	__h0+2
	txa
	beq	@r
@go:	tax
@l:	lda	__h0+2
	cmp	#$8000
	ror	__h0+2
	ror	__h0
	dex
	bne	@l
@r:	rts
