; hg_runs.s - hgame (0.30): runs filled by the CPU, for hg_fill_runs and hg_fill_groups on
; boards where the kernel's fill_runs is not there (before REV $09, the blitter off, Horizon
; before 0.30). The same rules as the kernel's: a run must end inside the page; the first one
; that does not stops it (the runs before it are filled).
;
; unsigned hg__runs_cpu(unsigned long page, unsigned size, const hg_run __far *runs,
;                       unsigned n)
;   page: the address of offset 0; size: its bytes (0 = 65,536); runs: {u16 ofs, u8 colour,
;   u8 width}; -> 0xFFFF, or the index of the run past the page.
; unsigned hg__groups_cpu(unsigned long page, unsigned size, const hg_rungroup __far *g,
;                         unsigned n)
;   the same for groups {u24 elements, u8 colour, u16 count, u8 stride, u8 fields} -> 0xFFFF,
;   or the index of the group with a run past the page.
; A run inside one bank: DBR = its bank, 16-bit stores (abs,X); one that crosses into the
; next bank: byte by byte through a long pointer. cc816's convention (hg_fast.s).
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __rg
	.export	_hg__runs_cpu, _hg__groups_cpu

.macro	jeq	dst
	bne	*+5
	jmp	dst
.endmacro

.define r0  __rg+0		; the page, bits 0-15
.define r1  __rg+2		;   bits 16-23
.define r2  __rg+4		; size - 1
.define r3  __rg+6		; runs (groups) left
.define r4  __rg+8		; -> the next run or group (24 bits: r4, r5)
.define r5  __rg+10
.define r6  __rg+12		; its index
.define r7  __rg+14		; the run's offset
.define r8  __rg+16		; its colour (low byte)
.define r9  __rg+18		; its width
.define r10 __rg+20		; the run's bank
.define r11 __rg+22
.define r12 __rg+24		; -> the run (24 bits: r12, r13), crossing a bank
.define r13 __rg+26
.define r14 __rg+28		; groups: -> the element (24 bits: r14, r15)
.define r15 __rg+30
.define r16 __rg+32		;   elements left
.define r17 __rg+34		;   stride
.define r18 __rg+36		;   the offset's place, the width's place
.define r19 __rg+38

	.segment "CODE"

; the arguments -> r0-r5, r3; DBR kept on the stack by the caller after this
args:	lda	ARGS+2,s		; (one more return address: ARGS + 2)
	sta	r0
	lda	ARGS+4,s
	and	#$00FF
	sta	r1
	lda	ARGS+6,s
	dec	a
	sta	r2
	lda	ARGS+8,s
	sta	r4
	lda	ARGS+10,s
	sta	r5
	lda	ARGS+12,s
	sta	r3
	stz	r6
	rts

_hg__runs_cpu:
	jsr	args
	phb
@run:	lda	r3
	jeq	ok
	lda	[r4]			; the offset
	sta	r7
	ldy	#2
	lda	[r4],y			; colour | width << 8
	sta	r8
	xba
	and	#$00FF
	sta	r9
	jsr	fill1
	bcs	bad
	lda	r4			; the next run
	clc
	adc	#4
	sta	r4
	bcc	:+
	inc	r5
:	inc	r6
	dec	r3
	bra	@run
ok:	plb
	lda	#$FFFF
	RET
bad:	plb
	lda	r6
	RET

_hg__groups_cpu:
	jsr	args
	phb
@grp:	lda	r3
	beq	ok
	lda	[r4]			; the elements
	sta	r14
	ldy	#2
	lda	[r4],y			; bank | colour << 8
	and	#$00FF
	sta	r15
	lda	[r4],y
	xba
	sta	r8
	ldy	#4
	lda	[r4],y			; count
	sta	r16
	ldy	#6
	lda	[r4],y			; stride | fields << 8
	and	#$00FF
	sta	r17
	lda	[r4],y
	xba
	sta	r18
	lda	r16
	beq	@nextg
@el:	lda	r18			; the offset at fields & 15
	and	#$000F
	tay
	lda	[r14],y
	sta	r7
	lda	r18			; the width at fields >> 4
	lsr	a
	lsr	a
	lsr	a
	lsr	a
	and	#$000F
	tay
	lda	[r14],y
	and	#$00FF
	sta	r9
	jsr	fill1
	bcs	bad
	lda	r14
	clc
	adc	r17
	sta	r14
	bcc	:+
	inc	r15
:	dec	r16
	bne	@el
@nextg:	lda	r4			; the next group
	clc
	adc	#8
	sta	r4
	bcc	:+
	inc	r5
:	inc	r6
	dec	r3
	bra	@grp

; one run: r7 offset, r9 width, r8 the colour (low byte). C set: it does not end inside the
; page. Changes DBR (the caller restores it at the end)
fill1:	lda	r9			; offset + width <= size?
	clc
	adc	r7
	bcs	@c
	beq	@in
	dec	a
	cmp	r2
	bcc	@in
	beq	@in
	sec
	rts
@c:	bne	@no			; past 65,536
	lda	r2
	inc	a
	beq	@in			; (only a page of 65,536 bytes reaches it)
@no:	sec
	rts
@in:	lda	r9
	beq	@done
	lda	r0			; the run's address
	clc
	adc	r7
	tax
	lda	r1
	adc	#0
	sta	r10
	txa
	clc
	adc	r9
	bcs	@cross
	sep	#$20			; inside one bank: DBR = it
	.a8
	lda	r10
	pha
	plb
	rep	#$20
	.a16
	lda	r8			; the colour in both bytes
	and	#$00FF
	sta	r11
	xba
	ora	r11
	sta	r11
	lda	r9
	lsr	a
	tay				; Y = pairs, C = an odd byte first
	lda	r11
	bcc	@ev
	sep	#$20
	.a8
	sta	a:0,x
	rep	#$20
	.a16
	inx
@ev:	cpy	#0
	beq	@done
@pair:	sta	a:0,x
	inx
	inx
	dey
	bne	@pair
@done:	clc
	rts
@cross:	stx	r12			; it crosses into the next bank: byte by byte
	lda	r10
	sta	r13
	lda	r8
	ldy	#0
	sep	#$20
	.a8
:	sta	[r12],y
	iny
	cpy	r9
	bne	:-
	rep	#$20
	.a16
	clc
	rts
