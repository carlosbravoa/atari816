; hg_fimg.s - hgame's image hot paths for cc816 (ca65): hg_draw's and hg_draw_part's sheet
; path, hg__blitmem, hg__fillmem. Apart from hg_fast.s because only games that draw
; images need them (hg_draw's C part pulls hg_image.c in). The same routines as
; ../hg_fast.s (vbcc); the convention is in hg_fast.s's header.
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __rg
	.import	_hg__kind, _hg__four, _hg__draw_c, _hg__draw_part_c
	.import	hgf_reccore, hgf_sheetrec
	.export	_hg_draw, _hg_draw_part, _hg__blitmem, _hg__fillmem

.define r0  __rg+0
.define r1  __rg+2
.define r2  __rg+4
.define r3  __rg+6
.define r4  __rg+8
.define r5  __rg+10
.define r6  __rg+12
.define r7  __rg+14
.define r8  __rg+16
.define r9  __rg+18
.define r10 __rg+20
.define r11 __rg+22
.define r12 __rg+24
.define r13 __rg+26
.define r14 __rg+28
.define r15 __rg+30
.define r28 __rg+32
.define r29 __rg+34
.define r30 __rg+36
.define r31 __rg+38

	.segment "CODE"

; ------------------------------------------------------------------ void hg_draw
; (const hg_image *img, unsigned frame, int x, int y): 3,s img (near), 5,s frame, 7,s x,
; 9,s y. The sheet path here; anything else (no sheet, 16 colours, a bad argument) goes
; on in C (hg__draw_c, the same arguments, still on the stack).
; hg_image: w 0, h 2, n 4, stride 6, addr 8, key 12, sheet 14, bpp 15
_hg_draw:
	lda	ARGS,s			; (r4): the image
	beq	@slow
	sta	r4
	sep	#$20
	.a8
	lda	_hg__kind
	rep	#$20
	.a16
	beq	@slow
	lda	_hg__four
	bne	@slow
	ldy	#14			; sheet | bpp << 8
	lda	(r4),y
	cmp	#$0801			; bpp 8 and a sheet (1-32)
	bcc	@slow
	cmp	#$0821
	bcs	@slow
	and	#$00FF
	sta	r29			; the sheet
	lda	ARGS+2,s			; frame < n?
	sta	r15
	ldy	#4
	cmp	(r4),y
	bcs	@slow
	lda	ARGS+4,s
	sta	r9
	lda	ARGS+6,s
	sta	r10
	lda	(r4)			; w
	sta	r11
	ldy	#2
	lda	(r4),y			; h
	sta	r12
	sta	r30			; sy = frame * h
	jsr	fmul
	ldy	#12
	lda	(r4),y			; key: SH_KEY, or HG_NONE: SH_COPY
	sta	r28
	ldx	#1			; SH_COPY
	cmp	#$FFFF
	beq	@op
	ldx	#2			; SH_KEY
@op:	stx	r8
	lda	#1
	sta	r3
	jsr	hgf_reccore
	bcs	@out
	lda	r8
	jsr	hgf_sheetrec
@out:	RET
@slow:	TAILJ	_hg__draw_c		; (the same arguments on the stack)

; ------------------------------------------------------------------ void hg_draw_part
; (const hg_image *img, unsigned sx, unsigned sy, unsigned w, unsigned h, int x, int y):
; 3,s img, 5,s sx, 7,s sy, 9,s w, 11,s h, 13,s x, 15,s y. The sheet path here, the rest
; in C (hg__draw_part_c, the same arguments).
dp_slow:	TAILJ	_hg__draw_part_c	; (here: in reach of the branches)
_hg_draw_part:
	lda	ARGS,s
	beq	dp_slow
	sta	r4
	sep	#$20
	.a8
	lda	_hg__kind
	rep	#$20
	.a16
	beq	dp_slow
	lda	_hg__four
	bne	dp_slow
	ldy	#14
	lda	(r4),y
	cmp	#$0801
	bcc	dp_slow
	cmp	#$0821
	bcs	dp_slow
	and	#$00FF
	sta	r29
	ldy	#4			; rows of the whole image: h * n
	lda	(r4),y
	sta	r15
	ldy	#2
	lda	(r4),y
	sta	r30
	jsr	fmul
	lda	r30
	sta	r2			; r2: rows
	lda	ARGS+2,s			; sx < w?
	sta	r1
	cmp	(r4)
	bcs	@out
	lda	ARGS+4,s			; sy < rows?
	sta	r30
	cmp	r2
	bcs	@out
	lda	(r4)			; w = min(w, img.w - sx)
	sec
	sbc	r1
	cmp	ARGS+6,s
	bcc	@w
	lda	ARGS+6,s
@w:	sta	r11
	lda	r2			; h = min(h, rows - sy)
	sec
	sbc	r30
	cmp	ARGS+8,s
	bcc	@h
	lda	ARGS+8,s
@h:	sta	r12
	lda	ARGS+10,s
	sta	r9
	lda	ARGS+12,s
	sta	r10
	ldy	#12
	lda	(r4),y
	sta	r28
	ldx	#1			; SH_COPY
	cmp	#$FFFF
	beq	@op
	ldx	#2			; SH_KEY
@op:	stx	r8
	pei	(r1)			; (sx: hgf_reccore uses r1)
	lda	#1
	sta	r3
	jsr	hgf_reccore
	pla
	bcs	@out
	clc
	adc	r13
	sta	r13			; the source x: sx + the cut
	lda	r8
	jsr	hgf_sheetrec
@out:	RET

; r30 = r15 * r30 (16 bits; frame * h). Uses A Y r31.
fmul:	lda	r30
	sta	r31
	stz	r30
	ldy	r15
@loop:	tya
	beq	@done
	lsr	a
	tay
	bcc	@next
	lda	r30
	clc
	adc	r31
	sta	r30
@next:	asl	r31
	bra	@loop
@done:	rts

; ------------------------------------------------------------------ void hg__blitmem
; (unsigned long dst, unsigned dstride, unsigned long src, unsigned sstride, unsigned w,
;  unsigned h, unsigned key): 3,s dst, 7,s dstride, 9,s src, 13,s sstride, 15,s w, 17,s h,
; 19,s key. The CPU, memory to memory: h rows of w bytes; key $FFFF a plain copy (two
; bytes at a time), else bytes equal to key are skipped. Rows may cross banks ([dp],y
; carries into the bank).
_hg__blitmem:
	lda	ARGS,s			; [r0]: dst
	sta	r0
	lda	ARGS+2,s
	sta	r1
	lda	ARGS+4,s
	sta	r4			; dstride
	lda	ARGS+6,s			; [r2]: src
	sta	r2
	lda	ARGS+8,s
	sta	r3
	lda	ARGS+10,s
	sta	r5			; sstride
	lda	ARGS+12,s
	sta	r6			; w
	beq	@done
	lsr	a
	sta	r9			; w / 2
	lda	ARGS+14,s
	sta	r7			; h
	beq	@done
	lda	ARGS+16,s
	sta	r8			; key
@row:	ldy	#0
	lda	r8
	cmp	#$FFFF
	bne	@keyed
	lda	r6			; a plain row inside one bank on both sides: MVN
	dec	a			; (7 cycles a byte; its banks written into it: the
	clc				; code bank is writable)
	adc	r2
	bcs	@loop
	lda	r6
	dec	a
	clc
	adc	r0
	bcs	@loop
	jsr	mvrow
	bra	@next
@loop:	ldx	r9
	beq	@odd
@pair:	lda	[r2],y
	sta	[r0],y
	iny
	iny
	dex
	bne	@pair
@odd:	lda	r6
	lsr	a
	bcc	@next
	sep	#$20
	.a8
	lda	[r2],y
	sta	[r0],y
	rep	#$20
	.a16
	bra	@next
@keyed:	sep	#$20
	.a8
@k:	lda	[r2],y
	cmp	r8
	beq	@skip
	sta	[r0],y
@skip:	iny
	cpy	r6
	bne	@k
	rep	#$20
	.a16
@next:	clc				; the next rows (24-bit adds)
	lda	r0
	adc	r4
	sta	r0
	bcc	@n1
	inc	r1
@n1:	clc
	lda	r2
	adc	r5
	sta	r2
	bcc	@n2
	inc	r3
@n2:	dec	r7
	bne	@row
@done:	RET

; hg__blitmem's row by MVN: r6 bytes from r3:r2 to r1:r0 (neither crosses a bank). A label
; of its own (the MVN's, patched) would end the routine's @ labels: a subroutine
mvrow:	sep	#$20
	.a8
	lda	r1
	sta	bmv+1			; MVN dst, src: the destination's bank first
	lda	r3
	sta	bmv+2
	rep	#$20
	.a16
	ldx	r2
	ldy	r0
	lda	r6
	dec	a
	phb
bmv:	mvn	#0, #0
	plb
	rts

; ------------------------------------------------------------------ void hg__fillmem
; (unsigned long dst, unsigned dstride, unsigned w, unsigned h, unsigned c): 3,s dst,
; 7,s dstride, 9,s w, 11,s h, 13,s c. h rows of w bytes of colour c.
_hg__fillmem:
	lda	ARGS,s
	sta	r0
	lda	ARGS+2,s
	sta	r1
	lda	ARGS+4,s
	sta	r4			; dstride
	lda	ARGS+6,s
	sta	r6			; w
	beq	@done
	lsr	a
	sta	r9
	lda	ARGS+8,s
	sta	r7			; h
	beq	@done
	lda	ARGS+10,s			; c | c << 8
	and	#$00FF
	sta	r8
	xba
	ora	r8
	sta	r8
@row:	ldy	#0
	ldx	r9
	beq	@odd
	lda	r8
@pair:	sta	[r0],y
	iny
	iny
	dex
	bne	@pair
@odd:	lda	r6
	lsr	a
	bcc	@next
	sep	#$20
	.a8
	lda	r8
	sta	[r0],y
	rep	#$20
	.a16
@next:	clc
	lda	r0
	adc	r4
	sta	r0
	bcc	@n1
	inc	r1
@n1:	dec	r7
	bne	@row
@done:	RET
