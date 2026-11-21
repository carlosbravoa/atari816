; ldiv.s - a 65816-tuned 32-bit unsigned division for vbcc (replaces the library's ldiv.o
; when linked before it; the signed routines in the library's ldivs.o call these).
; The library's contract (read from its code): dividend r0/r1, divisor r2/r3; quotient
; in r0/r1 and in A (low) / X (high), remainder in r4/r5. ___moduint32 and ___modcopy
; return the remainder in A/X.
; The library's: 32 rounds of a 32-bit shift-and-subtract. This one does the same for a
; divisor >= $10000, and keeps the remainder in A (16-bit) when the divisor is smaller.

	global	___intdiv32
	global	___divuint32
	global	___moduint32
	global	___modcopy
	zpage	r0,r1,r2,r3,r4,r5	; external, but direct page (see mulint32.s)

	section	"DONTMERGE_text.far.fastldiv","acrx"
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
	bne	full
	ldx	r2
	beq	full			; / 0: as the library (quotient $FFFFFFFF)
	ldx	#32			; divisor < $10000: remainder in A
l16:	asl	r0
	rol	r1
	rol	a
	bcs	s16			; 17 bits: certainly >= the divisor
	cmp	r2
	bcc	n16
s16:	sbc	r2			; (carry is set)
	inc	r0
n16:	dex
	bne	l16
	sta	r4
	stz	r5
	lda	r0
	ldx	r1
	rtl

full:	stz	r4
	stz	r5
	ldx	#32
lf:	asl	r0
	rol	r1
	rol	r4
	rol	r5
	lda	r4
	sec
	sbc	r2
	tay
	lda	r5
	sbc	r3
	bcc	nf
	sta	r5
	sty	r4
	inc	r0
nf:	dex
	bne	lf
	lda	r0
	ldx	r1
	rtl
