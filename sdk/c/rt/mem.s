; mem.s - memcpy, memmove, memset, strlen, strcpy, memcmp for cc816 (ca65), tuned for the
; 65816: every near pointer is an offset in the code bank (DBR), so MVN/MVP run in place
; on the code bank.
;
; cc816's convention: JSR, the arguments at 3,s 5,s 7,s (above the return address), the
; result in A. They use A, X, Y and __h0-__h3 and keep DBR.
;   memcpy / memmove: MVN (MVP when the move must go downwards), 7 cycles a byte;
;   memset: the first byte stored, then MVN from it to the next byte (the byte repeats
;           along), from 4 bytes on;
;   strlen, strcpy, memcmp: 16-bit reads, two bytes a round; strlen and strcpy first align
;           their reads to an even address, so a 16-bit read never crosses the bank's end
;           past the terminator.
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __h0, __h1, __h2
	.export	_memcpy, _memmove, _memset, _strlen, _strcpy, _memcmp

	.segment "CODE"

.if FARDATA
; The far data model (hcc --data far): every pointer is far (offset, bank, 0: 4 bytes),
; d at ARGS, s at ARGS+4, n (or c) after them; a pointer result in A (offset) and X (bank).
; MVN / MVP take their two banks in the instruction: it is built on the stack (MVN dst,
; src; RTL) and called there (as far.s's hz_far_copy); MVN leaves DBR at the destination's
; bank, so it is saved around. strlen, strcpy, memcmp read through [dp],y.

; void *memcpy(void *d, const void *s, size_t n)
_memcpy:
	lda	ARGS+8,s		; n
	beq	retd
	dec	a
	sta	__h0		; n - 1
	lda	#$0054		; MVN
movefwd:			; A = the opcode, __h0 = n - 1: X = s, Y = d (offsets)
	sta	__h2
	lda	ARGS+6,s		; the source bank, then the RTL
	and	#$00FF
	ora	#$6B00
	pha
	lda	ARGS+4,s		; the destination bank (ARGS+2, + 2 pushed)
	xba
	and	#$FF00
	ora	__h2		; the opcode
	pha
	lda	ARGS+8,s		; s (ARGS+4, + 4 pushed)
	tax
	lda	ARGS+4,s		; d (ARGS, + 4 pushed)
	tay
	lda	__h2
	cmp	#$0044
	bne	@go
	txa			; MVP: from the last bytes
	clc
	adc	__h0
	tax
	tya
	clc
	adc	__h0
	tay
@go:	tsc
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
retd:	lda	ARGS+2,s		; d: X = its bank, A = its offset
	tax
	lda	ARGS,s
	RET

; void *memmove(void *d, const void *s, size_t n)
_memmove:
	lda	ARGS+8,s		; n
	beq	retd
	dec	a
	sta	__h0
	lda	ARGS+6,s		; another bank: no overlap
	cmp	ARGS+2,s
	bne	@fwd
	lda	ARGS+4,s
	cmp	ARGS,s
	bcs	@fwd		; s >= d: upwards is safe
	lda	#$0044		; MVP: downwards
	bra	movefwd
@fwd:	lda	#$0054
	bra	movefwd

; void *memset(void *d, int c, size_t n)
_memset:
	lda	ARGS+6,s		; n
	beq	retd
	lda	ARGS,s
	sta	__h2
	lda	ARGS+2,s
	sta	__h2+2
	sep	#$20
	.a8
	lda	ARGS+4,s		; c
	sta	[__h2]		; the first byte
	rep	#$20
	.a16
	lda	ARGS+6,s
	dec	a
	beq	retd		; n = 1
	dec	a
	sta	__h0		; MVN's count - 1 = n - 2
	lda	ARGS+2,s		; MVN dst bank, dst bank; RTL
	and	#$00FF
	ora	#$6B00
	pha
	lda	ARGS+4,s		; (ARGS+2 + 2)
	xba
	and	#$FF00
	ora	#$0054
	pha
	lda	ARGS+4,s		; from d (ARGS + 4) ...
	tax
	tay
	iny			; ... to d + 1: the byte repeats along
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
	bra	retd

; size_t strlen(const char *s)
_strlen:
	lda	ARGS,s
	sta	__h0
	lda	ARGS+2,s
	sta	__h0+2
	ldy	#0
	lda	__h0
	lsr	a
	bcc	@w
	sep	#$20		; an odd address: one byte first
	.a8
	lda	[__h0]
	rep	#$20
	.a16
	beq	@zero
	iny
@w:	lda	[__h0],y
	bit	#$00FF
	beq	@d
	bit	#$FF00
	beq	@d1
	iny
	iny
	lda	[__h0],y
	bit	#$00FF
	beq	@d
	bit	#$FF00
	beq	@d1
	iny
	iny
	bra	@w
@d1:	iny
@d:	tya
	RET
@zero:	lda	#0
	RET

; char *strcpy(char *d, const char *s)
_strcpy:
	lda	ARGS,s
	sta	__h1
	lda	ARGS+2,s
	sta	__h1+2
	lda	ARGS+4,s
	sta	__h0
	lda	ARGS+6,s
	sta	__h0+2
	ldy	#0
	lda	__h0
	lsr	a
	bcc	@w
	sep	#$20		; an odd source address: one byte first
	.a8
	lda	[__h0]
	sta	[__h1]
	rep	#$20
	.a16
	beq	@ret
	iny
@w:	lda	[__h0],y
	bit	#$00FF
	beq	@z0
	bit	#$FF00
	beq	@z1
	sta	[__h1],y
	iny
	iny
	bra	@w
@z1:	sta	[__h1],y		; the last character and the 0
	bra	@ret
@z0:	sep	#$20
	.a8
	sta	[__h1],y		; the 0
	rep	#$20
	.a16
@ret:	jmp	retd

; int memcmp(const void *a, const void *b, size_t n): -1, 0 or 1 (unsigned bytes)
_memcmp:
	lda	ARGS,s
	sta	__h0
	lda	ARGS+2,s
	sta	__h0+2
	lda	ARGS+4,s
	sta	__h1
	lda	ARGS+6,s
	sta	__h1+2
	ldy	#0
	lda	ARGS+8,s
	beq	@ret0
	and	#$FFFE
	sta	__h2		; where the pairs end
	beq	@tail
@w:	lda	[__h0],y
	cmp	[__h1],y
	bne	@diff
	iny
	iny
	cpy	__h2
	bne	@w
@tail:	lda	ARGS+8,s
	lsr	a
	bcc	@ret0
	sep	#$20
	.a8
	lda	[__h0],y
	cmp	[__h1],y
	rep	#$20
	.a16
	beq	@ret0
	bcc	@lt
	lda	#1
	RET
@diff:	sep	#$20		; the first byte (the low one) decides if it differs
	.a8
	cmp	[__h1],y
	bne	@bd
	iny
	lda	[__h0],y
	cmp	[__h1],y
@bd:	rep	#$20
	.a16
	bcc	@lt
	lda	#1
	RET
@lt:	lda	#$FFFF
	RET
@ret0:	lda	#0
	RET

.else
; void *memcpy(void *d, const void *s, size_t n)
_memcpy:
	lda	ARGS+4,s		; n
	beq	@z
	dec	a
	tay			; (n - 1 for a moment)
	lda	ARGS+2,s		; s
	tax
	tya
	pha
	lda	ARGS+2,s		; d (3,s + 2)
	tay
	pla
	mvn	#^_memcpy, #^_memcpy
@z:	lda	ARGS,s
	RET

; void *memmove(void *d, const void *s, size_t n)
_memmove:
	lda	ARGS+4,s		; n
	beq	@z
	dec	a
	sta	__h0		; n - 1
	lda	ARGS+2,s		; s
	cmp	ARGS,s
	bcs	@fwd		; s >= d: upwards is safe
	clc
	adc	__h0
	tax			; the last source byte
	lda	ARGS,s
	clc
	adc	__h0
	tay			; the last destination byte
	lda	__h0
	mvp	#^_memcpy, #^_memcpy
	bra	@z
@fwd:	tax
	lda	ARGS,s
	tay
	lda	__h0
	mvn	#^_memcpy, #^_memcpy
@z:	lda	ARGS,s
	RET

; void *memset(void *d, int c, size_t n)
_memset:
	lda	ARGS,s
	tax
	lda	ARGS+4,s		; n
	beq	@done
	cmp	#4
	bcs	@mvn
	tay
	sep	#$20
	.a8
	lda	ARGS+2,s		; c
@l:	sta	a:0,x
	inx
	dey
	bne	@l
	rep	#$20
	.a16
@done:	lda	ARGS,s
	RET
@mvn:	sep	#$20
	.a8
	lda	ARGS+2,s
	sta	a:0,x		; the first byte
	rep	#$20
	.a16
	txy
	iny
	lda	ARGS+4,s
	sec
	sbc	#2		; n - 1 more bytes: the count is n - 2
	mvn	#^_memcpy, #^_memcpy
	lda	ARGS,s
	RET

; size_t strlen(const char *s)
_strlen:
	lda	ARGS,s
	sta	__h0
	tax
	lsr	a
	bcc	@w
	sep	#$20		; an odd address: one byte first
	.a8
	lda	a:0,x
	rep	#$20
	.a16
	beq	@zero
	inx
@w:	lda	a:0,x
	bit	#$00FF
	beq	@d
	bit	#$FF00
	beq	@d1
	inx
	inx
	lda	a:0,x
	bit	#$00FF
	beq	@d
	bit	#$FF00
	beq	@d1
	inx
	inx
	bra	@w
@d1:	inx
@d:	txa
	sec
	sbc	__h0
	RET
@zero:	lda	#0
	RET

; char *strcpy(char *d, const char *s)
_strcpy:
	lda	ARGS,s
	tay
	lda	ARGS+2,s
	tax
	lsr	a
	bcc	@w
	sep	#$20		; an odd source address: one byte first
	.a8
	lda	a:0,x
	sta	a:0,y
	rep	#$20
	.a16
	beq	@ret
	inx
	iny
@w:	lda	a:0,x
	bit	#$00FF
	beq	@z0
	bit	#$FF00
	beq	@z1
	sta	a:0,y
	inx
	inx
	iny
	iny
	bra	@w
@z1:	sta	a:0,y		; the last character and the 0
	bra	@ret
@z0:	sep	#$20
	.a8
	sta	a:0,y		; the 0
	rep	#$20
	.a16
@ret:	lda	ARGS,s
	RET

; int memcmp(const void *a, const void *b, size_t n): -1, 0 or 1 (unsigned bytes)
_memcmp:
	lda	ARGS,s
	sta	__h0
	lda	ARGS+2,s
	sta	__h1
	ldy	#0
	lda	ARGS+4,s
	beq	@ret0
	and	#$FFFE
	sta	__h2		; where the pairs end
	beq	@tail
@w:	lda	(__h0),y
	cmp	(__h1),y
	bne	@diff
	iny
	iny
	cpy	__h2
	bne	@w
@tail:	lda	ARGS+4,s
	lsr	a
	bcc	@ret0
	sep	#$20
	.a8
	lda	(__h0),y
	cmp	(__h1),y
	rep	#$20
	.a16
	beq	@ret0
	bcc	@lt
	lda	#1
	RET
@diff:	sep	#$20		; the first byte (the low one) decides if it differs
	.a8
	cmp	(__h1),y
	bne	@bd
	iny
	lda	(__h0),y
	cmp	(__h1),y
@bd:	rep	#$20
	.a16
	bcc	@lt
	lda	#1
	RET
@lt:	lda	#$FFFF
	RET
@ret0:	lda	#0
	RET
.endif
