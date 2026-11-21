; div16.s - a 65816-tuned 16-bit division for vbcc (replaces the C library's div.o,
; which defines all four entry points). Both models (vasm oldstyle).
;
; The library's contract (read from its code): dividend r0, divisor r1.
;   ___divuint16  A = r0 = quotient, r2 = remainder
;   ___moduint16  A = remainder
;   ___divint16   A = quotient (truncated toward 0)
;   ___modint16   A = remainder (the sign of the dividend)
; They destroy A, X, Y, r0, r1 (the signed ones make both operands positive), r2.
; Division by 0 gives the library's answer: quotient $FFFF, remainder the dividend.
; The library's: 16 rounds of a shift-and-subtract with the remainder in memory. This one
; keeps the remainder in A, shifts the quotient bits in as the dividend bits go out
; (one ROL), answers 0 at once when the dividend is below the divisor and takes 8 rounds
; when the dividend is below 256.

	zpage	r0,r1,r2
	global	___divuint16
	global	___moduint16
	global	___divint16
	global	___modint16

	section	"DONTMERGE_text.far.fastdiv16","acrx"
	a16
	x16
___moduint16:
	jsr	udiv
	lda	r2
	rtl

___divuint16:
	jsr	udiv
	rtl

___divint16:
	ldy	#0		; Y bit 0: negate the quotient
	lda	r0
	bpl	.p0
	eor	#$FFFF
	inc	a
	sta	r0
	iny
.p0:	lda	r1
	bpl	.p1
	eor	#$FFFF
	inc	a
	sta	r1
	tya
	eor	#1
	tay
.p1:	tya
	pha
	jsr	udiv
	plx
	beq	.pos
	eor	#$FFFF
	inc	a
.pos:	rtl

___modint16:
	ldy	#0		; Y: the dividend was negative
	lda	r0
	bpl	.m0
	eor	#$FFFF
	inc	a
	sta	r0
	iny
.m0:	lda	r1
	bpl	.m1
	eor	#$FFFF
	inc	a
	sta	r1
.m1:	phy
	jsr	udiv
	lda	r2
	ply
	beq	.mpos
	eor	#$FFFF
	inc	a
.mpos:	rtl

; r0 / r1 -> r0 = A = quotient, r2 = remainder (unsigned)
udiv:	lda	r0
	cmp	r1
	bcc	.small		; dividend < divisor: quotient 0
	ldx	#16
	ldy	r1
	beq	.full		; / 0: 16 rounds, the library's answer
	cmp	#$0100
	bcs	.full
	xba			; dividend < 256: its 8 bits to the top, 8 rounds
	sta	r0
	ldx	#8
.full:	lda	#0
	asl	r0		; the first dividend bit into C
.loop:	rol	a		; remainder * 2 + the bit
	bcs	.big		; 17 bits: certainly >= the divisor
	cmp	r1
	bcc	.zero
	sbc	r1		; (C is set and stays set: no borrow)
.zero:	rol	r0		; the quotient bit in, the next dividend bit out
	dex
	bne	.loop
	sta	r2
	lda	r0
	rts
.big:	sbc	r1		; C was set: the 17-bit value minus the divisor
	sec			; the quotient bit
	bra	.zero
.small:	sta	r2		; quotient 0, remainder the dividend
	stz	r0
	lda	#0
	rts
