; div32.s - a 65816-tuned 32-bit unsigned division for vbcc (replaces the C library's
; ldiv.o; the signed ___divint32 / ___modint32 of the library's ldivs.o call it). Both
; models (vasm oldstyle).
;
; The library's contract (read from its code): dividend r0/r1, divisor r2/r3 (low word
; first); quotient in r0/r1 and in A (low) / X (high), remainder in r4/r5.
; ___moduint32 and ___modcopy return the remainder in A/X. It destroys A, X, Y, r0, r1,
; r4, r5 and keeps r2, r3 (and r28, r30, which ldivs.o keeps its signs in).
; Division by 0: the library's answer, quotient $FFFFFFFF, remainder the dividend.
;
; The library's: 32 rounds of a 32-bit shift-and-subtract. This one:
;  - divisor < $10000: two 16-bit long-division steps with the remainder in A (the high
;    word's step is skipped when it is below the divisor: then 16 rounds in all);
;  - divisor >= $10000: the quotient has 16 bits, so 16 rounds starting from the high
;    word as the remainder.

	zpage	r0,r1,r2,r3,r4,r5
	global	___intdiv32
	global	___divuint32
	global	___moduint32
	global	___modcopy

	section	"DONTMERGE_text.far.fastdiv32","acrx"
	a16
	x16
___moduint32:
	jsl	>___intdiv32
___modcopy:
	lda	r4
	ldx	r5
	rtl

___divuint32:
___intdiv32:
	lda	r3
	bne	.full
	lda	r2
	beq	.byzero
	lda	r1		; divisor < $10000: first the high word
	cmp	r2
	bcc	.hlow
	ldx	#16
	lda	#0
	asl	r1
.l1:	rol	a
	bcs	.b1
	cmp	r2
	bcc	.z1
	sbc	r2
.z1:	rol	r1
	dex
	bne	.l1
	bra	.low
.b1:	sbc	r2
	sec
	bra	.z1
.hlow:	stz	r1		; quotient high 0, the remainder is the high word (in A)
.low:	ldx	#16		; then (remainder : low word) / divisor
	asl	r0
.l2:	rol	a
	bcs	.b2
	cmp	r2
	bcc	.z2
	sbc	r2
.z2:	rol	r0
	dex
	bne	.l2
	sta	r4
	stz	r5
	lda	r0
	ldx	r1
	rtl
.b2:	sbc	r2
	sec
	bra	.z2

.byzero:
	lda	r0
	sta	r4
	lda	r1
	sta	r5
	lda	#$FFFF
	sta	r0
	sta	r1
	tax
	rtl

.full:	lda	r1		; divisor >= $10000: the remainder starts as the high word
	sta	r4
	stz	r5
	ldx	#16
	asl	r0
.l3:	rol	r4
	rol	r5
	bcs	.b3		; 33 bits: certainly >= the divisor
	lda	r4
	sec
	sbc	r2
	tay
	lda	r5
	sbc	r3
	bcc	.z3
	sta	r5
	sty	r4
.z3:	rol	r0
	dex
	bne	.l3
	stz	r1
	lda	r0
	ldx	#0
	rtl
.b3:	lda	r4
	sec
	sbc	r2
	sta	r4
	lda	r5
	sbc	r3
	sta	r5
	sec
	bra	.z3
