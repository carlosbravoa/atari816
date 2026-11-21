; mem.s - 65816-tuned memcpy, memmove, memset, strlen, strcpy, memcmp for vbcc (replace
; the C library's members of the same names). vasm oldstyle; assembled with -DTINY=0
; (large model: 32-bit pointers, first argument in A/X, the others on the stack from 4,s)
; and -DTINY=1 (tiny model: 16-bit pointers into the window, DBR = 0, first argument in
; A). size_t is 16 bits in both. The results are the library's: memcpy, memmove, memset
; and strcpy return the destination, memcmp -1, 0 or 1 (unsigned bytes), strlen the
; length. They use A, X, Y and r0..r5 (volatile in vbcc's ABI) and keep DBR.
;
; How:
;  - memcpy / memmove: MVN (or MVP when a move must go downwards) for 5 bytes and more,
;    7 cycles a byte; a byte loop below that. The large model builds the instruction
;    (with the two banks) and an RTL on the stack and calls it there, as the library's
;    memcpy does; the tiny model has both banks 0 and runs MVN in place.
;  - memset: the first byte stored, then MVN from it to the next byte (the byte repeats
;    along), from 10 bytes on (tiny model: 4).
;  - strlen, strcpy, memcmp: 16-bit reads, two bytes a round. strlen and strcpy first
;    align their reads to an even address, so a 16-bit read never crosses a bank (or the
;    window's end at $8000) past the terminator.

	zpage	r0,r1,r2,r3,r4,r5
	global	_memcpy
	global	_memmove
	global	_memset
	global	_strlen
	global	_strcpy
	global	_memcmp

	if	TINY
; ======================================================================== tiny model

	section	"DONTMERGE_text.far.fastmemcpy","acrx"
	a16
	x16
_memcpy:			; A dst, 4,s src, 6,s n
	pha
	tay
	lda	6,s
	tax
	lda	8,s
	beq	.done
	dec	a
	mvn	0,0
.done:	pla
	rtl

	section	"DONTMERGE_text.far.fastmemmove","acrx"
_memmove:			; A dst, 4,s src, 6,s n
	pha
	lda	8,s
	beq	.done
	dec	a
	sta	r0		; n - 1
	lda	6,s
	cmp	1,s
	bcs	.fwd		; src >= dst: upwards is safe
	clc
	adc	r0
	tax			; the last source byte
	lda	1,s
	clc
	adc	r0
	tay			; the last destination byte
	lda	r0
	mvp	0,0
	bra	.done
.fwd:	tax
	lda	1,s
	tay
	lda	r0
	mvn	0,0
.done:	pla
	rtl

	section	"DONTMERGE_text.far.fastmemset","acrx"
_memset:			; A dst, 4,s c, 6,s n
	pha
	tax
	lda	8,s
	beq	.done
	cmp	#4
	bcs	.mvn
	tay
	sep	#$20
	lda	6,s
.l:	sta	!0,x
	inx
	dey
	bne	.l
	rep	#$20
.done:	pla
	rtl
.mvn:	sep	#$20
	lda	6,s
	sta	!0,x
	rep	#$20
	txy
	iny
	lda	8,s
	sec
	sbc	#2
	mvn	0,0
	pla
	rtl

	section	"DONTMERGE_text.far.faststrlen","acrx"
_strlen:			; A s
	sta	r0
	tax
	lsr	a
	bcc	.w
	sep	#$20		; an odd address: one byte first
	lda	!0,x
	rep	#$20
	beq	.z
	inx
.w:	lda	!0,x
	bit	#$00FF
	beq	.d
	bit	#$FF00
	beq	.d1
	inx
	inx
	lda	!0,x
	bit	#$00FF
	beq	.d
	bit	#$FF00
	beq	.d1
	inx
	inx
	bra	.w
.d1:	inx
.d:	txa
	sec
	sbc	r0
	rtl
.z:	lda	#0
	rtl

	section	"DONTMERGE_text.far.faststrcpy","acrx"
_strcpy:			; A dst, 4,s src
	sta	r0
	tay
	lda	4,s
	tax
	lsr	a
	bcc	.w
	sep	#$20		; an odd source address: one byte first
	lda	!0,x
	sta	!0,y
	rep	#$20
	beq	.ret
	inx
	iny
.w:	lda	!0,x
	bit	#$00FF
	beq	.z0
	bit	#$FF00
	beq	.z1
	sta	!0,y
	inx
	inx
	iny
	iny
	bra	.w
.z1:	sta	!0,y		; the last character and the 0
	bra	.ret
.z0:	sep	#$20
	sta	!0,y		; the 0
	rep	#$20
.ret:	lda	r0
	rtl

	section	"DONTMERGE_text.far.fastmemcmp","acrx"
_memcmp:			; A a, 4,s b, 6,s n
	sta	r0
	lda	4,s
	sta	r2
	ldy	#0
	lda	6,s
	beq	.ret0
	and	#$FFFE
	sta	r4		; where the pairs end
	beq	.tail
.w:	lda	(r0),y
	cmp	(r2),y
	bne	.diff
	iny
	iny
	cpy	r4
	bne	.w
.tail:	lda	6,s
	lsr	a
	bcc	.ret0
	sep	#$20
	lda	(r0),y
	cmp	(r2),y
	rep	#$20
	beq	.ret0
	bcc	.lt
	lda	#1
	rtl
.diff:	sep	#$20		; the first byte (the low one) decides if it differs
	cmp	(r2),y
	bne	.bd
	iny
	lda	(r0),y
	cmp	(r2),y
.bd:	rep	#$20
	bcc	.lt
	lda	#1
	rtl
.lt:	lda	#$FFFF
	rtl
.ret0:	lda	#0
	rtl

	else
; ======================================================================== large model

	section	"DONTMERGE_text.far.fastmemcpy","acrx"
	a16
	x16
_memcpy:			; A/X dst, 4,s src, 8,s n
	sta	r0
	stx	r1
	lda	8,s
	beq	.ret
	cmp	#5
	bcs	.mvn
	tax			; a few bytes: a loop
	lda	4,s
	sta	r2
	lda	6,s
	sta	r3
	ldy	#0
	sep	#$20
.l:	lda	[r2],y
	sta	[r0],y
	iny
	dex
	bne	.l
	rep	#$20
.ret:	lda	r0
	ldx	r1
	rtl
.mvn:	dec	a
	sta	r4		; n - 1
	lda	6,s		; byte 3: the source bank, byte 4: RTL
	and	#$00FF
	ora	#$6B00
	pha
	lda	r1		; byte 1: MVN, byte 2: the destination bank
	xba
	and	#$FF00
	ora	#$0054
	pha
	lda	8,s		; the source offset (4,s before the two pushes)
	tax
	ldy	r0
	tsc
	inc	a
	sta	r2		; the instruction: bank 0 (the stack)
	stz	r3
	lda	r4
	phb
	jsl	>.call
	plb
	pla
	pla
	lda	r0
	ldx	r1
	rtl
.call:	jml	[r2]

	section	"DONTMERGE_text.far.fastmemmove","acrx"
_memmove:			; A/X dst, 4,s src, 8,s n
	sta	r0
	stx	r1
	lda	8,s
	beq	.fwd
	lda	6,s
	cmp	r1
	bne	.fwd		; another bank: no overlap
	lda	4,s
	cmp	r0
	bcc	.down		; src < dst in one bank: downwards
.fwd:	lda	r0
	ldx	r1
	jml	>_memcpy
.down:	lda	8,s
	cmp	#5
	bcs	.mvp
	tax			; a few bytes: a loop from the end
	tay
	lda	4,s
	sta	r2
	lda	6,s
	sta	r3
	sep	#$20
.l:	dey
	lda	[r2],y
	sta	[r0],y
	dex
	bne	.l
	rep	#$20
	lda	r0
	ldx	r1
	rtl
.mvp:	dec	a
	sta	r4		; n - 1
	lda	6,s		; MVP $44, dst bank, src bank (the same bank), RTL
	and	#$00FF
	ora	#$6B00
	pha
	lda	r1
	xba
	and	#$FF00
	ora	#$0044
	pha
	lda	8,s		; the source's last byte
	clc
	adc	r4
	tax
	lda	r0		; the destination's last byte
	clc
	adc	r4
	tay
	tsc
	inc	a
	sta	r2
	stz	r3
	lda	r4
	phb
	jsl	>.call
	plb
	pla
	pla
	lda	r0
	ldx	r1
	rtl
.call:	jml	[r2]

	section	"DONTMERGE_text.far.fastmemset","acrx"
_memset:			; A/X dst, 4,s c, 6,s n
	sta	r0
	stx	r1
	lda	6,s
	beq	.ret
	cmp	#10
	bcs	.mvn
	tax
	sep	#$20
	lda	4,s
	ldy	#0
.l:	sta	[r0],y
	iny
	dex
	bne	.l
	rep	#$20
.ret:	lda	r0
	ldx	r1
	rtl
.mvn:	sep	#$20
	lda	4,s
	sta	[r0]		; the first byte
	rep	#$20
	lda	6,s
	sec
	sbc	#2
	sta	r4		; MVN's count - 1 = n - 2
	lda	r1		; MVN dst bank, dst bank; RTL
	and	#$00FF
	ora	#$6B00
	pha
	lda	r1
	xba
	and	#$FF00
	ora	#$0054
	pha
	ldx	r0		; from dst to dst + 1
	txy
	iny
	tsc
	inc	a
	sta	r2
	stz	r3
	lda	r4
	phb
	jsl	>.call
	plb
	pla
	pla
	lda	r0
	ldx	r1
	rtl
.call:	jml	[r2]

	section	"DONTMERGE_text.far.faststrlen","acrx"
_strlen:			; A/X s
	sta	r0
	stx	r1
	ldy	#0
	lsr	a
	bcc	.w
	sep	#$20		; an odd address: one byte first
	lda	[r0]
	rep	#$20
	beq	.d
	iny
.w:	lda	[r0],y
	bit	#$00FF
	beq	.d
	bit	#$FF00
	beq	.d1
	iny
	iny
	lda	[r0],y
	bit	#$00FF
	beq	.d
	bit	#$FF00
	beq	.d1
	iny
	iny
	bra	.w
.d1:	iny
.d:	tya
	rtl

	section	"DONTMERGE_text.far.faststrcpy","acrx"
_strcpy:			; A/X dst, 4,s src
	sta	r0
	stx	r1
	lda	6,s
	sta	r3
	ldy	#0
	lda	4,s
	sta	r2
	lsr	a
	bcc	.w
	sep	#$20		; an odd source address: one byte first
	lda	[r2]
	sta	[r0]
	rep	#$20
	beq	.ret
	iny
.w:	lda	[r2],y
	bit	#$00FF
	beq	.z0
	bit	#$FF00
	beq	.z1
	sta	[r0],y
	iny
	iny
	bra	.w
.z1:	sta	[r0],y		; the last character and the 0
	bra	.ret
.z0:	sep	#$20
	sta	[r0],y		; the 0
	rep	#$20
.ret:	lda	r0
	ldx	r1
	rtl

	section	"DONTMERGE_text.far.fastmemcmp","acrx"
_memcmp:			; A/X a, 4,s b, 8,s n
	sta	r0
	stx	r1
	lda	4,s
	sta	r2
	lda	6,s
	sta	r3
	ldy	#0
	lda	8,s
	beq	.ret0
	lsr	a
	tax			; pairs
	beq	.tail
.w:	lda	[r0],y
	cmp	[r2],y
	bne	.diff
	iny
	iny
	dex
	bne	.w
.tail:	lda	8,s
	lsr	a
	bcc	.ret0
	sep	#$20
	lda	[r0],y
	cmp	[r2],y
	rep	#$20
	beq	.ret0
	bcc	.lt
	lda	#1
	rtl
.diff:	sep	#$20		; the first byte (the low one) decides if it differs
	cmp	[r2],y
	bne	.bd
	iny
	lda	[r0],y
	cmp	[r2],y
.bd:	rep	#$20
	bcc	.lt
	lda	#1
	rtl
.lt:	lda	#$FFFF
	rtl
.ret0:	lda	#0
	rtl

	endif
