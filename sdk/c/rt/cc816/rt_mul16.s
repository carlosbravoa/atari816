; rt_mul16.s - part of cc816's arithmetic helpers (ld65 links a module only when a
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
	.export	__mul16

	.segment "CODE"

; ---- 16 x 16 -> 16: the smaller operand is the multiplier, the loop stops when it has
; no bits left (a multiplier below 256: at most 8 rounds)
__mul16:
	stx	__h2
	cmp	__h2
	bcc	@asmall
	sta	__h3		; the multiplicand: A; the multiplier: X (in __h2)
	bra	@go
@asmall:
	sta	__h2		; the multiplier: A; the multiplicand: X
	stx	__h3
@go:	lda	#0
@loop:	lsr	__h2		; the multiplier's next bit
	bcs	@add
	beq	@done		; no bits left
	asl	__h3
	bra	@loop
@add:	clc
	adc	__h3
	ldx	__h2
	beq	@done
	asl	__h3
	bra	@loop
@done:	rts
