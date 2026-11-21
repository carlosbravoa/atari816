; hg_fast.s - hgame's hot paths in assembly (vasm oldstyle, large model): the draw record
; (clip, count, append: hg__rec), hg_fill, hg_draw's sheet path, the text strip.
;
; Why: in C (vbcc -O1) one hg_fill or hg_draw took 190-270 us in the emulator (two runtime
; multiplies, a pointer computed for every field, seven saved registers), about as much
; as the kernel's own work for a sheet record (21 us). Here they take a few dozen.
;
; vbcc's convention (sdk/docs/c/reference.md): JSL/RTL, A X Y 16-bit, the first argument
; in A (32-bit: A low, X high), the others on the stack from 4,s; r0-r15 and r28-r31 may
; be changed, r16-r27 kept; DBR = the code bank, where the library's globals are (so
; they are reached with absolute addresses).

	zpage	r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12,r13,r14,r15,r28,r29,r30,r31
	global	_hg__rec
	global	_hg_fill
	global	_hg_draw
	global	_hg_draw_part
	global	_hg__strip
	global	_hg__blitmem
	global	_hg__fillmem
	global	_hg__umul

LS_FILL	equ	0
LS_COPY	equ	1
LS_KEY	equ	2
QMAX	equ	128		; HG__Q


; ------------------------------------------------------------------ the record core
; In: r8 op, r9 x, r10 y, r11 w, r12 h (screen coordinates), r3 the kind of record (0 a
; draw_list record, 1 a sheet record). The origin and the page are added, the rectangle is
; cut to the target (r13 cut at the left, r14 at the top), the pixels are counted (a call
; is limited to 460,800: records smaller than 60 x 60 count as 3,481, larger ones
; exactly), the queue sent first if full, a new run started if the kind changes (the
; frame's records go out as runs of one kind, in order: no conversion).
; Out: carry clear: Y = the record's index (r9-r12 the clipped rectangle; 640 x 360 x 4:
; r9 and r11 in bytes); carry set: wholly outside. Uses A X Y r0 r1 r6 r7 r8-r14.
	section	"DONTMERGE_text.far.hgreccore","acrx"
	a16
	x16
reccore:
	lda	r9
	clc
	adc	_hg__offx
	sta	r9
	lda	r10
	clc
	adc	_hg__offy
	sta	r10
	stz	r13
	stz	r14
	lda	r9			; left: x < 0 (signed)
	bpl	.xok
	eor	#$FFFF
	inc	a			; -x
	cmp	r11
	bcs	.out			; -x >= w: nothing left
	sta	r13
	lda	r11
	sec
	sbc	r13
	sta	r11
	stz	r9
.xok:	lda	r10			; top: y < cy0 (signed)
	sec
	sbc	_hg__cly0
	bvc	.v1
	eor	#$8000
.v1:	bpl	.yok
	lda	_hg__cly0
	sec
	sbc	r10			; cy0 - y
	cmp	r12
	bcs	.out
	sta	r14
	lda	r12
	sec
	sbc	r14
	sta	r12
	lda	_hg__cly0
	sta	r10
.yok:	lda	r9			; (x, y >= 0 now: unsigned compares)
	cmp	_hg__clx1
	bcs	.out
	lda	r10
	cmp	_hg__cly1
	bcs	.out
	lda	r11
	beq	.out
	lda	r12
	beq	.out
	lda	_hg__clx1		; w = min(w, cx1 - x)
	sec
	sbc	r9
	cmp	r11
	bcs	.w
	sta	r11
.w:	lda	_hg__cly1		; h = min(h, cy1 - y)
	sec
	sbc	r10
	cmp	r12
	bcs	.h
	sta	r12
.h:	lda	r11			; the pixels
	cmp	#60
	bcs	.big
	lda	r12
	cmp	#60
	bcs	.big
	lda	#3481
	sta	r6
	stz	r7
	bra	.count
.big:	jsr	mul32
.count:	lda	_hg__qn
	cmp	#QMAX
	beq	.send
	clc
	lda	_hg__qpix
	adc	r6
	tay
	lda	_hg__qpix+2
	adc	r7
	cmp	#$0007			; 460,800 = $00070800
	bcc	.room
	bne	.send
	cpy	#$0801
	bcc	.room
.send:	pei	(r3)			; the queue first (hg__submit(1): C, changes r0-r15
	pei	(r15)			; and r28-r31)
	pei	(r28)
	pei	(r29)
	pei	(r30)
	pei	(r6)
	pei	(r7)
	pei	(r8)
	pei	(r9)
	pei	(r10)
	pei	(r11)
	pei	(r12)
	pei	(r13)
	pei	(r14)
	lda	#1
	jsl	>_hg__submit
	pla
	sta	r14
	pla
	sta	r13
	pla
	sta	r12
	pla
	sta	r11
	pla
	sta	r10
	pla
	sta	r9
	pla
	sta	r8
	pla
	sta	r7
	pla
	sta	r6
	pla
	sta	r30
	pla
	sta	r29
	pla
	sta	r28
	pla
	sta	r15
	pla
	sta	r3
.room:	clc
	lda	_hg__qpix
	adc	r6
	sta	_hg__qpix
	lda	_hg__qpix+2
	adc	r7
	sta	_hg__qpix+2
	ldy	_hg__qn			; a new run when the kind changes
	lda	_hg__nruns
	beq	.newrun
	lda	r3
	cmp	_hg__runkind
	beq	.same
.newrun:
	lda	_hg__nruns
	asl	a
	tax
	tya				; its first record | the kind << 15
	ldx	r3
	beq	.k0
	ora	#$8000
.k0:	pha
	lda	_hg__nruns
	asl	a
	tax
	pla
	sta	_hg__runs,x
	lda	r3
	sta	_hg__runkind
	inc	_hg__nruns
.same:	inc	_hg__qn
	lda	_hg__four		; 640 x 360 x 4: x and w in bytes
	beq	.ok
	lsr	r9
	inc	r11
	lsr	r11
.ok:	clc
	rts
.out:	sec
	rts

; r6/r7 = r11 * r12 (unsigned 16 x 16 -> 32), shift and add. Uses A Y r0 r1.
mul32:	stz	r6
	stz	r7
	lda	r11
	sta	r0			; the multiplicand, shifted left
	stz	r1
	ldy	r12			; the multiplier, shifted right
.loop:	tya
	beq	.done
	lsr	a
	tay
	bcc	.next
	clc
	lda	r6
	adc	r0
	sta	r6
	lda	r7
	adc	r1
	sta	r7
.next:	asl	r0
	rol	r1
	bra	.loop
.done:	rts

; the draw_list record Y (r8 op, r9-r12): X = its offset in _hg__dq, the rest 0. Uses A r0.
listrec:
	tya				; _hg__dq + Y * 20
	asl	a
	asl	a
	sta	r0
	asl	a
	asl	a
	clc
	adc	r0
	tax
	lda	r8
	and	#$00FF			; op, flags 0
	sta	_hg__dq+0,x
	stz	_hg__dq+2,x		; c1, c2
	lda	r9
	sta	_hg__dq+4,x
	lda	r10
	sta	_hg__dq+6,x
	lda	r11
	sta	_hg__dq+8,x
	lda	r12
	sta	_hg__dq+10,x
	stz	_hg__dq+12,x		; source
	stz	_hg__dq+14,x
	stz	_hg__dq+16,x		; stride
	stz	_hg__dq+18,x
	rts

; the sheet record Y: A = op (SH_*), sheet r29 (0: a fill), colour r28, (sx, sy) = (r13,
; r30 + r14), r9-r12. Uses A X.
sheetrec:
	pha
	tya				; _hg__sq + Y * 16
	asl	a
	asl	a
	asl	a
	asl	a
	tax
	pla
	xba				; sheet | op << 8
	and	#$FF00
	ora	r29
	sta	_hg__sq+0,x
	lda	r28			; colour, 0
	and	#$00FF
	sta	_hg__sq+2,x
	lda	r13
	sta	_hg__sq+4,x
	lda	r30
	clc
	adc	r14
	sta	_hg__sq+6,x
	lda	r11
	sta	_hg__sq+8,x
	lda	r12
	sta	_hg__sq+10,x
	lda	r9
	sta	_hg__sq+12,x
	lda	r10
	sta	_hg__sq+14,x
	rts

	section	"DONTMERGE_text.far.hgrec","acrx"
_hg__rec:
	sta	r8
	lda	4,s
	sta	r9
	lda	6,s
	sta	r10
	lda	8,s
	sta	r11
	lda	10,s
	sta	r12
	sep	#$20
	a8
	lda	_hg__kind
	rep	#$20
	a16
	beq	.none
	stz	r3			; a draw_list record
	jsr	reccore
	bcs	.null
	jsr	listrec
	lda	r13
	sta	_hg__cutx
	lda	r14
	sta	_hg__cuty
	txa
	clc
	adc	#<_hg__dq
	ldx	#^_hg__dq
	rtl
.none:	pea	#^.msg
	pea	#<.msg
	ldx	#^.fn
	lda	#<.fn
	jsl	>_hg__fail
	pla
	pla
.null:	lda	#0
	tax
	rtl
.fn:	db	"draw",0
.msg:	db	"no screen (hg_screen or hg_window first)",0

; ------------------------------------------------------------------ void hg_fill
; (int x, int y, unsigned w, unsigned h, unsigned c)
	section	"DONTMERGE_text.far.hgfill","acrx"
_hg_fill:
	sta	r9
	lda	4,s
	sta	r10
	lda	6,s
	sta	r11
	lda	8,s
	sta	r12
	lda	10,s
	sta	r28			; the colour
	stz	r8			; LS_FILL
	sep	#$20
	a8
	lda	_hg__kind
	rep	#$20
	a16
	beq	.none
	lda	_hg__four
	bne	.four
	lda	#1			; a sheet record (SH_FILL, sheet 0)
	sta	r3
	jsr	reccore
	bcs	.out
	stz	r29
	stz	r30
	stz	r13
	stz	r14
	lda	#0			; SH_FILL
	jsr	sheetrec
.out:	rtl
.four:	stz	r3			; 16 colours: a draw_list fill, both nibbles
	jsr	reccore
	bcs	.out
	jsr	listrec
	lda	r28
	and	#15
	sta	r28
	asl	a
	asl	a
	asl	a
	asl	a
	ora	r28
	sep	#$20
	a8
	sta	_hg__dq+2,x		; c1
	rep	#$20
	a16
	rtl
.none:	lda	#0
	pha
	pha
	pha
	pha
	pha
	jsl	>_hg__rec		; (says what is wrong)
	pla
	pla
	pla
	pla
	pla
	rtl

; ------------------------------------------------------------------ void hg_draw
; (const hg_image *img, unsigned frame, int x, int y): the sheet path here; anything
; else (no sheet, 16 colours, a bad argument) goes on in C (hg__draw_c, same arguments).
; hg_image: w 0, h 2, n 4, stride 6, addr 8, key 12, sheet 14, bpp 15
	section	"DONTMERGE_text.far.hgdraw","acrx"
_hg_draw:
	sta	r4			; [r4]: the image
	stx	r5
	ora	r5
	beq	.slow
	sep	#$20
	a8
	lda	_hg__kind
	rep	#$20
	a16
	beq	.slow
	lda	_hg__four
	bne	.slow
	ldy	#14			; sheet | bpp << 8
	lda	[r4],y
	cmp	#$0801			; bpp 8 and a sheet (1-32)
	bcc	.slow
	cmp	#$0821
	bcs	.slow
	and	#$00FF
	sta	r29			; the sheet
	lda	4,s			; frame < n?
	sta	r15
	ldy	#4
	cmp	[r4],y
	bcs	.slow
	lda	6,s
	sta	r9
	lda	8,s
	sta	r10
	lda	[r4]			; w
	sta	r11
	ldy	#2
	lda	[r4],y			; h
	sta	r12
	sta	r30			; sy = frame * h
	jsr	fmul
	ldy	#12
	lda	[r4],y			; key: SH_KEY, or HG_NONE: SH_COPY
	sta	r28
	ldx	#1			; SH_COPY
	cmp	#$FFFF
	beq	.op
	ldx	#2			; SH_KEY
.op:	stx	r8
	lda	#1
	sta	r3
	jsr	reccore
	bcs	.out
	lda	r8
	jsr	sheetrec
.out:	rtl
.slow:	lda	r4
	ldx	r5
	jml	>_hg__draw_c		; (the same arguments on the stack)

; ------------------------------------------------------------------ void hg_draw_part
; (const hg_image *img, unsigned sx, unsigned sy, unsigned w, unsigned h, int x, int y):
; the sheet path here, the rest in C (hg__draw_part_c, same arguments).
	section	"DONTMERGE_text.far.hgdrawpart","acrx"
_hg_draw_part:
	sta	r4
	stx	r5
	ora	r5
	beq	.slow
	sep	#$20
	a8
	lda	_hg__kind
	rep	#$20
	a16
	beq	.slow
	lda	_hg__four
	bne	.slow
	ldy	#14
	lda	[r4],y
	cmp	#$0801
	bcc	.slow
	cmp	#$0821
	bcs	.slow
	and	#$00FF
	sta	r29
	ldy	#4			; rows of the whole image: h * n
	lda	[r4],y
	sta	r15
	ldy	#2
	lda	[r4],y
	sta	r30
	jsr	fmul
	lda	r30
	sta	r2			; r2: rows
	lda	4,s			; sx < w?
	sta	r1
	cmp	[r4]
	bcs	.out
	lda	6,s			; sy < rows?
	sta	r30
	cmp	r2
	bcs	.out
	lda	[r4]			; w = min(w, img.w - sx)
	sec
	sbc	r1
	cmp	8,s
	bcc	.w
	lda	8,s
.w:	sta	r11
	lda	r2			; h = min(h, rows - sy)
	sec
	sbc	r30
	cmp	10,s
	bcc	.h
	lda	10,s
.h:	sta	r12
	lda	12,s
	sta	r9
	lda	14,s
	sta	r10
	ldy	#12
	lda	[r4],y
	sta	r28
	ldx	#1			; SH_COPY
	cmp	#$FFFF
	beq	.op
	ldx	#2			; SH_KEY
.op:	stx	r8
	pei	(r1)			; (sx: reccore uses r1)
	lda	#1
	sta	r3
	jsr	reccore
	pla
	bcs	.out
	clc
	adc	r13
	sta	r13			; the source x: sx + the cut
	lda	r8
	jsr	sheetrec
.out:	rtl
.slow:	lda	r4
	ldx	r5
	jml	>_hg__draw_part_c

; r30 = r15 * r30 (16 bits; frame * h). Uses A Y r31.
fmul:	lda	r30
	sta	r31
	stz	r30
	ldy	r15
.loop:	tya
	beq	.done
	lsr	a
	tay
	bcc	.next
	lda	r30
	clc
	adc	r31
	sta	r30
.next:	asl	r31
	bra	.loop
.done:	rts

; ------------------------------------------------------------------ void hg__strip
; (unsigned char *dst, const char *s, unsigned n): the 1 bpp picture of n characters of s,
; n bytes a row, 10 rows, from the built-in font (95 glyphs of 10 bytes from ' '). The
; row offsets (0, n, .. 9n) are made first, so a character is ten 8-bit loads and stores.
	section	"DONTMERGE_text.far.hgstrip","acrx"
_hg__strip:
	sta	r6			; [r6]: dst + i
	stx	r7
	lda	4,s			; [r2]: s
	sta	r2
	lda	6,s
	sta	r3
	lda	8,s
	sta	r4			; n
	beq	.done
	stz	r8			; the rows' offsets
	sta	r9
	clc
	adc	r4
	sta	r10
	adc	r4
	sta	r11
	adc	r4
	sta	r12
	adc	r4
	sta	r13
	adc	r4
	sta	r14
	adc	r4
	sta	r15
	adc	r4
	sta	r28
	adc	r4
	sta	r29
	stz	r5			; i
.char:	ldy	r5
	lda	[r2],y
	and	#$00FF
	sec
	sbc	#32
	cmp	#95
	bcc	.ok
	lda	#0			; outside 32-126: blank
.ok:	sta	r30			; glyph * 10
	asl	a
	asl	a
	clc
	adc	r30
	asl	a
	clc
	adc	#<_hg__font
	tax				; X: the glyph's bytes (absolute, code bank)
	sep	#$20
	a8
	lda	!0,x
	ldy	r8
	sta	[r6],y
	lda	!1,x
	ldy	r9
	sta	[r6],y
	lda	!2,x
	ldy	r10
	sta	[r6],y
	lda	!3,x
	ldy	r11
	sta	[r6],y
	lda	!4,x
	ldy	r12
	sta	[r6],y
	lda	!5,x
	ldy	r13
	sta	[r6],y
	lda	!6,x
	ldy	r14
	sta	[r6],y
	lda	!7,x
	ldy	r15
	sta	[r6],y
	lda	!8,x
	ldy	r28
	sta	[r6],y
	lda	!9,x
	ldy	r29
	sta	[r6],y
	rep	#$20
	a16
	inc	r6
	inc	r5
	lda	r5
	cmp	r4
	bcc	.char
.done:	rtl

; ------------------------------------------------------------------ void hg__blitmem
; (unsigned long dst, unsigned dstride, unsigned long src, unsigned sstride, unsigned w,
;  unsigned h, unsigned key): the CPU, memory to memory: h rows of w bytes; key $FFFF a
; plain copy (two bytes at a time), else bytes equal to key are skipped. Rows may cross
; banks ([dp],y carries into the bank).
	section	"DONTMERGE_text.far.hgblitmem","acrx"
_hg__blitmem:
	sta	r0			; [r0]: dst
	stx	r1
	lda	4,s
	sta	r4			; dstride
	lda	6,s			; [r2]: src
	sta	r2
	lda	8,s
	sta	r3
	lda	10,s
	sta	r5			; sstride
	lda	12,s
	sta	r6			; w
	beq	.done
	lsr	a
	sta	r9			; w / 2
	lda	14,s
	sta	r7			; h
	beq	.done
	lda	16,s
	sta	r8			; key
.row:	ldy	#0
	lda	r8
	cmp	#$FFFF
	bne	.keyed
	ldx	r9
	beq	.odd
.pair:	lda	[r2],y
	sta	[r0],y
	iny
	iny
	dex
	bne	.pair
.odd:	lda	r6
	lsr	a
	bcc	.next
	sep	#$20
	a8
	lda	[r2],y
	sta	[r0],y
	rep	#$20
	a16
	bra	.next
.keyed:	sep	#$20
	a8
.k:	lda	[r2],y
	cmp	r8
	beq	.skip
	sta	[r0],y
.skip:	iny
	cpy	r6
	bne	.k
	rep	#$20
	a16
.next:	clc				; the next rows (24-bit adds)
	lda	r0
	adc	r4
	sta	r0
	bcc	.n1
	inc	r1
.n1:	clc
	lda	r2
	adc	r5
	sta	r2
	bcc	.n2
	inc	r3
.n2:	dec	r7
	bne	.row
.done:	rtl

; ------------------------------------------------------------------ void hg__fillmem
; (unsigned long dst, unsigned dstride, unsigned w, unsigned h, unsigned c): h rows of w
; bytes of colour c.
	section	"DONTMERGE_text.far.hgfillmem","acrx"
_hg__fillmem:
	sta	r0
	stx	r1
	lda	4,s
	sta	r4			; dstride
	lda	6,s
	sta	r6			; w
	beq	.done
	lsr	a
	sta	r9
	lda	8,s
	sta	r7			; h
	beq	.done
	lda	10,s			; c | c << 8
	and	#$00FF
	sta	r8
	xba
	ora	r8
	sta	r8
.row:	ldy	#0
	ldx	r9
	beq	.odd
	lda	r8
.pair:	sta	[r0],y
	iny
	iny
	dex
	bne	.pair
.odd:	lda	r6
	lsr	a
	bcc	.next
	sep	#$20
	a8
	lda	r8
	sta	[r0],y
	rep	#$20
	a16
.next:	clc
	lda	r0
	adc	r4
	sta	r0
	bcc	.n1
	inc	r1
.n1:	dec	r7
	bne	.row
.done:	rtl

; ------------------------------------------------------------------ unsigned long hg__umul
; (unsigned a, unsigned b): a * b, 32 bits (the C runtime's 32 x 32 multiply costs about
; 100 us; this one a quarter of that).
	section	"DONTMERGE_text.far.hgumul","acrx"
_hg__umul:
	sta	r11
	lda	4,s
	sta	r12
	jsr	mul32
	lda	r6
	ldx	r7
	rtl
