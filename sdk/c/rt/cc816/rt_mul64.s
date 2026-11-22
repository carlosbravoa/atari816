; rt_mul64.s - cc816's 64-bit multiply (long long): see rt_shift64.s for the contract.
;
;   __mul64     __h0..__h1 * __h2..__h3 -> __h0..__h1 (the low 64 bits; signed and
;               unsigned alike)
;
; Schoolbook on 16-bit words: the low 64 bits of the product are the sums of a[i] * b[j]
; with i + j <= 3, each a 16 x 16 -> 32 shift-add (a word that is 0 is skipped: small
; values cost little). The sum is kept on the hardware stack.
	.p816
	.smart	-
	.a16
	.i16
	.importzp __h0, __h1, __h2, __h3, __rv
	.export	__mul64

	.segment "CODE"

; the product's word k is at (2k + 1),s

; a[i] * b[j] added at word k = i + j of the sum
.macro	MULADD	ia, jb
	.local	skip
	lda	__h0 + 2 * ia
	beq	skip
	ldx	__h2 + 2 * jb
	beq	skip
	jsr	m16			; A = the high word, __rv the low word
	tax
	lda	__rv
	clc
	adc	2 * (ia + jb) + 1, s
	sta	2 * (ia + jb) + 1, s
	.if	ia + jb < 3
	txa
	adc	2 * (ia + jb) + 3, s
	sta	2 * (ia + jb) + 3, s
	.if	ia + jb < 2
	lda	#0
	adc	2 * (ia + jb) + 5, s
	sta	2 * (ia + jb) + 5, s
	.if	ia + jb < 1
	lda	#0
	adc	2 * (ia + jb) + 7, s
	sta	2 * (ia + jb) + 7, s
	.endif
	.endif
	.endif
skip:
.endmacro

__mul64:
	pea	0			; the sum: 8 bytes, word 0 at 1,s
	pea	0
	pea	0
	pea	0
	MULADD	0, 0
	MULADD	0, 1
	MULADD	1, 0
	MULADD	0, 2
	MULADD	1, 1
	MULADD	2, 0
	MULADD	0, 3
	MULADD	1, 2
	MULADD	2, 1
	MULADD	3, 0
	pla
	sta	__h0
	pla
	sta	__h0+2
	pla
	sta	__h1
	pla
	sta	__h1+2
	rts

; A (16 bits) * X (16 bits) -> A (the high word), __rv (the low word): 16 rounds of
; shift-add, the multiplier shifted out of __rv as the product's low word comes in
m16:	sta	__rv+2
	stx	__rv
	lda	#0
	lsr	__rv
	.repeat	16
	bcc	:+
	clc
	adc	__rv+2
:	ror	a
	ror	__rv
	.endrep
	rts
