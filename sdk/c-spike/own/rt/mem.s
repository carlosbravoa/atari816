; mem.s - memcpy, memset, memmove (cc816 convention: JSR, arguments at 3,s 5,s 7,s).
;   void *memcpy(void *d, const void *s, size_t n)    MVN, 7 cycles a byte
;   void *memset(void *d, int c, size_t n)
;   void *memmove(void *d, const void *s, size_t n)
	.p816
	.smart	+
	.a16
	.i16
	.export	_memcpy, _memset, _memmove

	.segment "CODE"
_memcpy:
	lda	7,s		; n
	beq	@z
	dec	a
	pha
	lda	7,s		; s (5,s + 2)
	tax
	lda	5,s		; d (3,s + 2)
	tay
	pla
	phb
	mvn	#^_memcpy, #^_memcpy
	plb
@z:	lda	3,s
	rts

_memmove:
	lda	3,s		; d
	cmp	5,s		; s
	bcc	_memcpy		; d < s: forwards
	beq	@z
	lda	7,s		; backwards: MVP from the last byte
	beq	@z
	dec	a
	pha
	clc
	adc	7,s		; s + n - 1
	tax
	lda	1,s
	clc
	adc	5,s		; d + n - 1
	tay
	pla
	phb
	mvp	#^_memcpy, #^_memcpy
	plb
@z:	lda	3,s
	rts

_memset:
	lda	7,s		; n
	beq	@z
	lda	3,s
	tax
	sep	#$20
	lda	5,s		; c
	sta	a:0,x
	rep	#$20
	lda	7,s
	dec	a
	beq	@z
	dec	a		; n - 2 more bytes, copied forwards from d to d+1
	txy
	iny
	phb
	mvn	#^_memcpy, #^_memcpy
	plb
@z:	lda	3,s
	rts
