; mulint32.s - a 65816-tuned ___mulint32/___muluint32 for vbcc (replaces the library's
; lmul.o when linked before it). The library's contract (read from its code): operands
; in r2/r3 and r4/r5 (32-bit, low word first), result in A (low) / X (high); it
; destroys r0..r3. This one destroys only r0, r1 (and A, X).
; low32(M * N) = Mlo*Nlo + ((Mlo*Nhi + Mhi*Nlo) << 16): one 16x16->32 shift-add multiply
; (16 rounds) and two 16x16->16 ones that stop when the multiplier runs out of bits.
; The library's: 32 rounds of 32-bit shift-and-add.

	global	___mulint32
	global	___muluint32
	zpage	r0,r1,r2,r3,r4,r5	; external, but direct page: without this vasm uses
					; absolute addressing (through DBR: the code bank)

	section	"DONTMERGE_text.far.fastmul32","acrx"
	a16
	x16
___muluint32:
___mulint32:
	lda	r2			; Mlo * Nhi (low 16)
	sta	r0
	lda	r5
	jsr	mul16
	pha
	lda	r4			; + Nlo * Mhi (low 16)
	sta	r0
	lda	r3
	jsr	mul16
	clc
	adc	1,s
	sta	1,s
	lda	r4			; Mlo * Nlo -> A (high) : r1 (low)
	sta	r1
	lda	#0
	ldx	#16
	lsr	r1
ml:	bcc	mn
	clc
	adc	r2
mn:	ror	a
	ror	r1
	dex
	bne	ml
	clc
	adc	1,s			; + the cross terms
	tax				; high word
	pla
	lda	r1			; low word
	rtl

; A = r0 * A (low 16 bits); destroys r0, r1
mul16:	sta	r1
	lda	#0
	bra	m16t
m16l:	lsr	r1
	bcc	m16s
	clc
	adc	r0
m16s:	asl	r0
m16t:	ldx	r1
	bne	m16l
	rts
