; far.s - copies between any banks with MVN (vasm oldstyle), both memory models.
;
;   void hz_far_copy(void __far *dst, const void __far *src, unsigned n);
;   void hz_far_set(void __far *dst, int c, unsigned n);
;
; MVN takes its two banks in the instruction, so the instruction is built on the stack
; (MVN dst,src; RTL) and called there, as the C library's memcpy does: no code is
; modified. n = 0 does nothing; the ranges must not cross a bank boundary; hz_far_copy's
; ranges must not overlap (MVN copies upwards).

	zpage	r0,r1,r2,r4,r5
	global	_hz_far_copy
	global	_hz_far_set

	section	"DONTMERGE_text.far.hzfarcopy","acrx"
	a16
	x16
_hz_far_copy:			; A/X = dst (offset, bank), 4,s src (offset, bank), 8,s n
	sta	r0
	stx	r1
	lda	8,s
	beq	.done
	dec	a
	sta	r2
	lda	6,s		; MVN's source bank and the RTL (bytes 3 and 4)
	and	#$00FF
	ora	#$6B00
	pha
	lda	r1		; MVN (byte 1) and its destination bank (byte 2)
	xba
	and	#$FF00
	ora	#$0054
	pha
	lda	8,s		; the source offset (4,s before the two pushes)
	tax
	ldy	r0
	tsc
	inc	a
	sta	r4		; the instruction's address: bank 0 (the stack)
	stz	r5
	lda	r2		; n - 1
	phb
	jsl	>.call
	plb
	pla
	pla
.done:	rtl
.call:	jml	[r4]

	section	"DONTMERGE_text.far.hzfarset","acrx"
_hz_far_set:			; A/X = dst, 4,s c, 6,s n
	sta	r0
	stx	r1
	lda	6,s
	beq	.done
	sta	r2
	sep	#$20
	a8
	lda	4,s
	sta	[r0]		; the first byte
	rep	#$20
	a16
	lda	r2
	dec	a
	beq	.done		; n = 1
	dec	a
	sta	r2		; MVN's count - 1 = n - 2
	lda	r1		; MVN dst bank, dst bank; RTL
	and	#$00FF
	ora	#$6B00
	pha
	lda	r1
	xba
	and	#$FF00
	ora	#$0054
	pha
	ldx	r0		; from dst ...
	txy
	iny			; ... to dst + 1: the byte repeats along
	tsc
	inc	a
	sta	r4
	stz	r5
	lda	r2
	phb
	jsl	>.call
	plb
	pla
	pla
.done:	rtl
.call:	jml	[r4]

; void __far *hz_farptr(unsigned bank, unsigned off): a far pointer from a bank and an
; offset (vbcc turns a constant-folded integer into a pointer in the data bank, so
; HZ_FARPTR calls this instead of casting)
	global	_hz_farptr
	section	"DONTMERGE_text.far.hzfarptr","acrx"
_hz_farptr:
	and	#$00FF
	tax
	lda	4,s
	rtl
