; mul16.s - a 65816-tuned ___mulint16 / ___muluint16 for vbcc (replaces the C library's
; mul.o). Both models (vasm oldstyle).
;
; The library's contract (read from its code): A = r0 * r1 (the low 16 bits; signed and
; unsigned are the same); it destroys A, X, r0, r2 and keeps r1 and Y. This one keeps the
; same set.
; The library's: 16 rounds of shift-and-add, always. This one takes the smaller operand as
; the multiplier and stops when it has no bits left: a multiplier below 256 takes at most
; 8 rounds, 0 or 1 a few cycles.

	zpage	r0,r1,r2
	global	___mulint16
	global	___muluint16

	section	"DONTMERGE_text.far.fastmul16","acrx"
	a16
	x16
___mulint16:
___muluint16:
	lda	r0
	cmp	r1
	bcc	.r0small
	sta	r2		; multiplicand = r0, multiplier = r1 (the smaller)
	lda	r1
	sta	r0
	bra	.go
.r0small:
	lda	r1		; multiplicand = r1, multiplier = r0
	sta	r2
.go:	lda	#0
.loop:	lsr	r0		; the multiplier's next bit
	bcs	.add
	beq	.done		; no bits left
	asl	r2
	bra	.loop
.add:	clc
	adc	r2
	ldx	r0
	beq	.done
	asl	r2
	bra	.loop
.done:	rtl
