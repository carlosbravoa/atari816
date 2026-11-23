; far.s - copies between any banks with MVN, for cc816 (ca65).
;
;   void hz_far_copy(void __far *dst, const void __far *src, unsigned n);
;   void hz_far_set(void __far *dst, int c, unsigned n);
;   void __far *hz_farptr(unsigned bank, unsigned off);
;
; MVN takes its two banks in the instruction, so the instruction is built on the stack
; (MVN dst,src; RTL) and called there: no code is modified. n = 0 does nothing; the
; ranges must not cross a bank boundary; hz_far_copy's ranges must not overlap (MVN copies
; upwards). cc816's convention: JSR, the arguments from 3,s (a far pointer is 4 bytes:
; offset, bank, 0), the result in A (32 bits: A low, X high).
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __h0, __h1, __h2
	.export	_hz_far_copy, _hz_far_set, _hz_farptr

	.segment "CODE"

_hz_far_copy:			; 3,s dst, 7,s src, 11,s n
	lda	ARGS+8,s
	beq	@done
	dec	a
	sta	__h0		; n - 1
	lda	ARGS+6,s		; MVN's source bank and the RTL (bytes 3 and 4)
	and	#$00FF
	ora	#$6B00
	pha
	lda	ARGS+4,s		; MVN (byte 1) and its destination bank (byte 2): 5,s + 2
	xba
	and	#$FF00
	ora	#$0054
	pha
	lda	ARGS+8,s		; the source offset: 7,s + 4
	tax
	lda	ARGS+4,s		; the destination offset: 3,s + 4
	tay
	tsc
	inc	a
	sta	__h1		; the instruction's address: bank 0 (the stack)
	stz	__h1+2
	lda	__h0
	phb
	phk			; a JSL's return address, for its RTL
	per	@back - 1
	jml	[__h1]
@back:	plb
	pla
	pla
@done:	RET

_hz_far_set:			; 3,s dst, 7,s c, 9,s n
	lda	ARGS+6,s
	beq	@done
	lda	ARGS,s
	sta	__h2
	lda	ARGS+2,s
	sta	__h2+2
	sep	#$20
	.a8
	lda	ARGS+4,s
	sta	[__h2]		; the first byte
	rep	#$20
	.a16
	lda	ARGS+6,s
	dec	a
	beq	@done		; n = 1
	dec	a
	sta	__h0		; MVN's count - 1 = n - 2
	lda	ARGS+2,s		; MVN dst bank, dst bank; RTL
	and	#$00FF
	ora	#$6B00
	pha
	lda	ARGS+4,s		; (5,s + 2)
	xba
	and	#$FF00
	ora	#$0054
	pha
	lda	ARGS+4,s		; from dst (3,s + 4) ...
	tax
	tay
	iny			; ... to dst + 1: the byte repeats along
	tsc
	inc	a
	sta	__h1
	stz	__h1+2
	lda	__h0
	phb
	phk
	per	@back - 1
	jml	[__h1]
@back:	plb
	pla
	pla
@done:	RET

; a far pointer from a bank and an offset
_hz_farptr:			; 3,s bank, 5,s offset
	lda	ARGS,s
	and	#$00FF
	tax
	lda	ARGS+2,s
	RET
