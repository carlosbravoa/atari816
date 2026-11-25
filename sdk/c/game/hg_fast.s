; hg_fast.s - hgame's hot paths in assembly for cc816 (ca65): the draw record (clip, count,
; append: hg__rec), hg_fill, the text strip, hg__umul. hg_draw, hg_draw_part, hg__blitmem
; and hg__fillmem are in hg_fimg.s (only games that draw images link them, and they pull
; hg_image.c in).
;
; Why assembly: in C one hg_fill or hg_draw took 190-270 us (runtime multiplies, a
; pointer computed for every field), about as much as the kernel's own work for a sheet
; record (21 us). Here they take a few dozen.
;
; cc816's convention: JSR/RTS, A X Y 16-bit, D = 0, DBR = PBR = the code bank (where the
; library's globals are: absolute addresses); every argument on the stack from 3,s (2
; bytes, a long or __far pointer 4); data pointers are 16-bit offsets in the code bank;
; the result in A (32 bits: A low, X high). __rg+0..+47, __h0-__h3, __rv may be changed.
;
; The names r0-r15 and r28-r31 below are scratch words: __rg+0..+30 and __rg+32..+38; rq
; (__rg+40, its bank at +42) points at the record being written: the queues (hg__dq,
; hg__sq) are in far memory, written with [rq],y.
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __rg
.if FARDATA
	.importzp __cbank
.endif
	.import	_hg__offx, _hg__offy, _hg__cly0, _hg__cly1, _hg__clx1
	.import	_hg__qn, _hg__qpix, _hg__nruns, _hg__runs, _hg__runkind, _hg__four
	.import	_hg__dq, _hg__sq, _hg__kind, _hg__cutx, _hg__cuty, _hg__font
	.import	_hg__submit, _hg__fail
	.export	_hg__rec, _hg_fill, _hg__strip, _hg__umul
	.export	hgf_reccore, hgf_sheetrec

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
.define rq  __rg+40

LS_FILL	= 0
QMAX	= 128		; HG__Q

	.segment "CODE"

; ------------------------------------------------------------------ the record core
; In: r8 op, r9 x, r10 y, r11 w, r12 h (screen coordinates), r3 the kind of record (0 a
; draw_list record, 1 a sheet record). The origin and the page are added, the rectangle is
; cut to the target (r13 cut at the left, r14 at the top), the pixels are counted (a call
; is limited to 460,800: records smaller than 60 x 60 count as 3,481, larger ones
; exactly), the queue sent first if full, a new run started if the kind changes.
; Out: carry clear: Y = the record's index (r9-r12 the clipped rectangle; 640 x 360 x 4:
; r9 and r11 in bytes); carry set: wholly outside. Uses A X Y r0 r1 r6 r7 r8-r14 (and,
; when the queue is sent, whatever hg__submit changes except the registers it keeps here).
rc_out:	sec				; (here: in reach of the branches)
	rts
hgf_reccore:
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
	bpl	@xok
	eor	#$FFFF
	inc	a			; -x
	cmp	r11
	bcs	rc_out			; -x >= w: nothing left
	sta	r13
	lda	r11
	sec
	sbc	r13
	sta	r11
	stz	r9
@xok:	lda	r10			; top: y < cy0 (signed)
	sec
	sbc	_hg__cly0
	bvc	@v1
	eor	#$8000
@v1:	bpl	@yok
	lda	_hg__cly0
	sec
	sbc	r10			; cy0 - y
	cmp	r12
	bcs	rc_out
	sta	r14
	lda	r12
	sec
	sbc	r14
	sta	r12
	lda	_hg__cly0
	sta	r10
@yok:	lda	r9			; (x, y >= 0 now: unsigned compares)
	cmp	_hg__clx1
	bcs	rc_out
	lda	r10
	cmp	_hg__cly1
	bcs	rc_out
	lda	r11
	beq	rc_out
	lda	r12
	beq	rc_out
	lda	_hg__clx1		; w = min(w, cx1 - x)
	sec
	sbc	r9
	cmp	r11
	bcs	@w
	sta	r11
@w:	lda	_hg__cly1		; h = min(h, cy1 - y)
	sec
	sbc	r10
	cmp	r12
	bcs	@h
	sta	r12
@h:	lda	r11			; the pixels
	cmp	#60
	bcs	@big
	lda	r12
	cmp	#60
	bcs	@big
	lda	#3481
	sta	r6
	stz	r7
	bra	@count
@big:	jsr	mul32
@count:	lda	_hg__qn
	cmp	#QMAX
	beq	@send
	clc
	lda	_hg__qpix
	adc	r6
	tay
	lda	_hg__qpix+2
	adc	r7
	cmp	#$0007			; 460,800 = $00070800
	bcc	@room
	bne	@send
	cpy	#$0801
	bcc	@room
@send:	pei	(r3)			; the queue first (hg__submit(1): C, changes __rg+0..47)
	pei	(r15)
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
	pea	1
	CALL	_hg__submit
	pla
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
@room:	clc
	lda	_hg__qpix
	adc	r6
	sta	_hg__qpix
	lda	_hg__qpix+2
	adc	r7
	sta	_hg__qpix+2
	ldy	_hg__qn			; a new run when the kind changes
	lda	_hg__nruns
	beq	@newrun
	lda	r3
	cmp	_hg__runkind
	beq	@same
@newrun:
	tya				; its first record | the kind << 15
	ldx	r3
	beq	@k0
	ora	#$8000
@k0:	pha
	lda	_hg__nruns
	asl	a
	tax
	pla
	sta	_hg__runs,x
	lda	r3
	sta	_hg__runkind
	inc	_hg__nruns
@same:	inc	_hg__qn
	lda	_hg__four		; 640 x 360 x 4: x and w in bytes
	beq	@ok
	lsr	r9
	inc	r11
	lsr	r11
@ok:	clc
	rts

; r6/r7 = r11 * r12 (unsigned 16 x 16 -> 32), shift and add. Uses A Y r0 r1.
mul32:	stz	r6
	stz	r7
	lda	r11
	sta	r0			; the multiplicand, shifted left
	stz	r1
	ldy	r12			; the multiplier, shifted right
@loop:	tya
	beq	@done
	lsr	a
	tay
	bcc	@next
	clc
	lda	r6
	adc	r0
	sta	r6
	lda	r7
	adc	r1
	sta	r7
@next:	asl	r0
	rol	r1
	bra	@loop
@done:	rts

; the draw_list record Y (r8 op, r9-r12): rq = its address (hg__dq + Y * 20), the rest 0.
; Uses A Y r0.
listrec:
	tya				; hg__dq + Y * 20
	asl	a
	asl	a
	sta	r0
	asl	a
	asl	a
	clc
	adc	r0
	adc	_hg__dq			; (the queue lies in one bank: no carry)
	sta	rq
	lda	_hg__dq+2
	sta	rq+2
	lda	r8
	and	#$00FF			; op, flags 0
	sta	[rq]
	ldy	#2
	lda	#0
	sta	[rq],y			; c1, c2
	ldy	#12
	sta	[rq],y			; source
	ldy	#14
	sta	[rq],y
	ldy	#16
	sta	[rq],y			; stride
	ldy	#18
	sta	[rq],y
	lda	r9
	ldy	#4
	sta	[rq],y
	lda	r10
	ldy	#6
	sta	[rq],y
	lda	r11
	ldy	#8
	sta	[rq],y
	lda	r12
	ldy	#10
	sta	[rq],y
	rts

; the sheet record Y: A = op (SH_*), sheet r29 (0: a fill), colour r28, (sx, sy) = (r13,
; r30 + r14), r9-r12. rq = its address (hg__sq + Y * 16). Uses A X Y.
hgf_sheetrec:
	tax
	tya				; hg__sq + Y * 16
	asl	a
	asl	a
	asl	a
	asl	a
	clc
	adc	_hg__sq			; (the queue lies in one bank: no carry)
	sta	rq
	lda	_hg__sq+2
	sta	rq+2
	txa
	xba				; sheet | op << 8
	and	#$FF00
	ora	r29
	sta	[rq]
	lda	r28			; colour, 0
	and	#$00FF
	ldy	#2
	sta	[rq],y
	lda	r13
	ldy	#4
	sta	[rq],y
	lda	r30
	clc
	adc	r14
	ldy	#6
	sta	[rq],y
	lda	r11
	ldy	#8
	sta	[rq],y
	lda	r12
	ldy	#10
	sta	[rq],y
	lda	r9
	ldy	#12
	sta	[rq],y
	lda	r10
	ldy	#14
	sta	[rq],y
	rts

; ------------------------------------------------------------------ hz_drawrec __far *hg__rec
; (unsigned op, int x, int y, unsigned w, unsigned h): 3,s op, 5,s x, 7,s y, 9,s w, 11,s h
_hg__rec:
	lda	ARGS,s
	sta	r8
	lda	ARGS+2,s
	sta	r9
	lda	ARGS+4,s
	sta	r10
	lda	ARGS+6,s
	sta	r11
	lda	ARGS+8,s
	sta	r12
	sep	#$20
	.a8
	lda	_hg__kind
	rep	#$20
	.a16
	beq	@none
	stz	r3			; a draw_list record
	jsr	hgf_reccore
	bcs	@null
	jsr	listrec
	lda	r13
	sta	_hg__cutx
	lda	r14
	sta	_hg__cuty
	lda	rq			; the record: a far pointer (A, X its bank)
	ldx	rq+2
	RET
.if FARDATA
@none:	pei	(__cbank)		; (far pointers: the main bank)
	pea	s_msg
	pei	(__cbank)
	pea	s_fn
	CALL	_hg__fail
	pla
	pla
	pla
	pla
@null:	lda	#0
	tax
	RET
.else
@none:	pea	s_msg
	pea	s_fn
	CALL	_hg__fail
	pla
	pla
@null:	lda	#0
	tax
	RET
.endif

; ------------------------------------------------------------------ void hg_fill
; (int x, int y, unsigned w, unsigned h, unsigned c): 3,s x, 5,s y, 7,s w, 9,s h, 11,s c
_hg_fill:
	lda	ARGS,s
	sta	r9
	lda	ARGS+2,s
	sta	r10
	lda	ARGS+4,s
	sta	r11
	lda	ARGS+6,s
	sta	r12
	lda	ARGS+8,s
	sta	r28			; the colour
	stz	r8			; LS_FILL
	sep	#$20
	.a8
	lda	_hg__kind
	rep	#$20
	.a16
	beq	@none
	lda	_hg__four
	bne	@four
	lda	#1			; a sheet record (SH_FILL, sheet 0)
	sta	r3
	jsr	hgf_reccore
	bcs	@out
	stz	r29
	stz	r30
	stz	r13
	stz	r14
	lda	#0			; SH_FILL
	jsr	hgf_sheetrec
@out:	RET
@four:	stz	r3			; 16 colours: a draw_list fill, both nibbles
	jsr	hgf_reccore
	bcs	@out
	jsr	listrec
	lda	r28
	and	#15
	sta	r28
	asl	a
	asl	a
	asl	a
	asl	a
	ora	r28
	ldy	#2
	sep	#$20
	.a8
	sta	[rq],y			; c1
	rep	#$20
	.a16
	RET
@none:	pea	0
	pea	0
	pea	0
	pea	0
	pea	0
	CALL	_hg__rec		; (says what is wrong)
	pla
	pla
	pla
	pla
	pla
	RET

; ------------------------------------------------------------------ void hg__strip
; (unsigned char *dst, const char *s, unsigned n): 3,s dst, 5,s s, 7,s n (near pointers:
; the code bank, DBR). The 1 bpp picture of n characters of s, n bytes a row, 10 rows, from
; the built-in font (95 glyphs of 10 bytes from ' '). The row offsets (0, n, .. 9n) are
; made first, so a character is ten 8-bit loads and stores.
.if FARDATA
; (far data: dst and s are far pointers, [r6],y and [r2],y: dst at ARGS, s at ARGS+4, n at
; ARGS+8; r7 and r3 their banks)
.macro	STRIPIND op, r
	op	[r],y
.endmacro
_hg__strip:
	lda	ARGS,s
	sta	r6
	lda	ARGS+2,s
	sta	r7
	lda	ARGS+4,s
	sta	r2
	lda	ARGS+6,s
	sta	r3
	lda	ARGS+8,s
	sta	r4			; n
	bne	@go
	RET
.else
.macro	STRIPIND op, r
	op	(r),y
.endmacro
_hg__strip:
	lda	ARGS,s			; (r6): dst + i
	sta	r6
	lda	ARGS+2,s			; (r2): s
	sta	r2
	lda	ARGS+4,s
	sta	r4			; n
	bne	@go
	RET
.endif
@go:	stz	r8			; the rows' offsets
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
@char:	ldy	r5
	STRIPIND	lda, r2
	and	#$00FF
	sec
	sbc	#32
	cmp	#95
	bcc	@ok
	lda	#0			; outside 32-126: blank
@ok:	sta	r30			; glyph * 10
	asl	a
	asl	a
	clc
	adc	r30
	asl	a
	clc
	adc	#_hg__font
	tax				; X: the glyph's bytes (absolute, code bank)
	sep	#$20
	.a8
	lda	a:0,x
	ldy	r8
	STRIPIND	sta, r6
	lda	a:1,x
	ldy	r9
	STRIPIND	sta, r6
	lda	a:2,x
	ldy	r10
	STRIPIND	sta, r6
	lda	a:3,x
	ldy	r11
	STRIPIND	sta, r6
	lda	a:4,x
	ldy	r12
	STRIPIND	sta, r6
	lda	a:5,x
	ldy	r13
	STRIPIND	sta, r6
	lda	a:6,x
	ldy	r14
	STRIPIND	sta, r6
	lda	a:7,x
	ldy	r15
	STRIPIND	sta, r6
	lda	a:8,x
	ldy	r28
	STRIPIND	sta, r6
	lda	a:9,x
	ldy	r29
	STRIPIND	sta, r6
	rep	#$20
	.a16
	inc	r6
	inc	r5
	lda	r5
	cmp	r4
	bcs	@done
	jmp	@char
@done:	RET

; ------------------------------------------------------------------ unsigned long hg__umul
; (unsigned a, unsigned b): a * b, 32 bits (3,s a, 5,s b).
_hg__umul:
	lda	ARGS,s
	sta	r11
	lda	ARGS+2,s
	sta	r12
	jsr	mul32
	lda	r6
	ldx	r7
	RET

	.segment "RODATA"
s_fn:	.byte	"draw",0
s_msg:	.byte	"no screen (hg_screen or hg_window first)",0
