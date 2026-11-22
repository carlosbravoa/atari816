; hg_fast.s - hgame's hot paths in assembly for cc816 (ca65): the draw record (clip, count,
; append: hg__rec), hg_fill, the text strip, hg__umul. hg_draw, hg_draw_part, hg__blitmem
; and hg__fillmem are in hg_fimg.s (only games that draw images link them, and they pull
; hg_image.c in). The same routines as ../hg_fast.s (vbcc), ported: see its comments for
; why they are in assembly.
;
; cc816's convention: JSR/RTS, A X Y 16-bit, D = 0, DBR = PBR = the code bank (where the
; library's globals are: absolute addresses); every argument on the stack from 3,s (2
; bytes, a long or __far pointer 4); data pointers are 16-bit offsets in the code bank;
; the result in A (32 bits: A low, X high). __rg+0..+47, __h0-__h3, __rv may be changed.
;
; vbcc's registers here: r0-r15 -> __rg+0..+30, r28-r31 -> __rg+32..+38 (all scratch).
	.p816
	.smart	-
	.a16
	.i16
	.importzp __rg
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
	jsr	_hg__submit
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
hgf_sheetrec:
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

; ------------------------------------------------------------------ hz_drawrec *hg__rec
; (unsigned op, int x, int y, unsigned w, unsigned h): 3,s op, 5,s x, 7,s y, 9,s w, 11,s h
_hg__rec:
	lda	3,s
	sta	r8
	lda	5,s
	sta	r9
	lda	7,s
	sta	r10
	lda	9,s
	sta	r11
	lda	11,s
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
	txa				; &hg__dq[Y] (a near pointer)
	clc
	adc	#_hg__dq
	rts
@none:	pea	s_msg
	pea	s_fn
	jsr	_hg__fail
	pla
	pla
@null:	lda	#0
	rts

; ------------------------------------------------------------------ void hg_fill
; (int x, int y, unsigned w, unsigned h, unsigned c): 3,s x, 5,s y, 7,s w, 9,s h, 11,s c
_hg_fill:
	lda	3,s
	sta	r9
	lda	5,s
	sta	r10
	lda	7,s
	sta	r11
	lda	9,s
	sta	r12
	lda	11,s
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
@out:	rts
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
	sep	#$20
	.a8
	sta	_hg__dq+2,x		; c1
	rep	#$20
	.a16
	rts
@none:	pea	0
	pea	0
	pea	0
	pea	0
	pea	0
	jsr	_hg__rec		; (says what is wrong)
	pla
	pla
	pla
	pla
	pla
	rts

; ------------------------------------------------------------------ void hg__strip
; (unsigned char *dst, const char *s, unsigned n): 3,s dst, 5,s s, 7,s n (near pointers:
; the code bank, DBR). The 1 bpp picture of n characters of s, n bytes a row, 10 rows, from
; the built-in font (95 glyphs of 10 bytes from ' '). The row offsets (0, n, .. 9n) are
; made first, so a character is ten 8-bit loads and stores.
_hg__strip:
	lda	3,s			; (r6): dst + i
	sta	r6
	lda	5,s			; (r2): s
	sta	r2
	lda	7,s
	sta	r4			; n
	bne	@go
	rts
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
	lda	(r2),y
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
	sta	(r6),y
	lda	a:1,x
	ldy	r9
	sta	(r6),y
	lda	a:2,x
	ldy	r10
	sta	(r6),y
	lda	a:3,x
	ldy	r11
	sta	(r6),y
	lda	a:4,x
	ldy	r12
	sta	(r6),y
	lda	a:5,x
	ldy	r13
	sta	(r6),y
	lda	a:6,x
	ldy	r14
	sta	(r6),y
	lda	a:7,x
	ldy	r15
	sta	(r6),y
	lda	a:8,x
	ldy	r28
	sta	(r6),y
	lda	a:9,x
	ldy	r29
	sta	(r6),y
	rep	#$20
	.a16
	inc	r6
	inc	r5
	lda	r5
	cmp	r4
	bcs	@done
	jmp	@char
@done:	rts

; ------------------------------------------------------------------ unsigned long hg__umul
; (unsigned a, unsigned b): a * b, 32 bits (3,s a, 5,s b).
_hg__umul:
	lda	3,s
	sta	r11
	lda	5,s
	sta	r12
	jsr	mul32
	lda	r6
	ldx	r7
	rts

	.segment "RODATA"
s_fn:	.byte	"draw",0
s_msg:	.byte	"no screen (hg_screen or hg_window first)",0
