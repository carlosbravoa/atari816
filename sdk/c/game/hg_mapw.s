; hg_mapw.s - hgame: hg_map16's tiles coming into view, a run of cells at a time (a column
; or a row of the ring, inside the map, not across the ring's edge): each cell's tile number
; read from the map (far), kept in the slots' table (far) and queued as a sheet record, as
; hg_draw_part would queue it but without its checks (a slot always lies inside the
; framebuffer). In C this was about 2,100 cycles a tile (cc816's code, the calls); here
; about a quarter of that. The convention is in hg_fast.s's header.
;
; void hg__mapwalk(void): the run is described by hg__mw (hg_map.c):
;   +0  u16 p, +2 its bank     the first cell's map word
;   +4  pstep                  bytes to the next cell's word (2 along a row, mw * 2 down)
;   +6  u16 sh, +8 its bank    the first slot's word in the slots' table
;   +10 shstep                 bytes to the next slot's word
;   +12 n                      cells (1 or more)
;   +14 x, +16 y               the first slot's top left in the framebuffer
;   +18 dx, +20 dy             to the next slot's
;   +22 ntiles                 numbers from it on draw tile 0
;   +24 tmask                  tiles a row of the sheet - 1 (a power of two)
;   +26 tsh, +28 wsh, +30 hsh  log2 of the tiles a row, the tile's width and height
;   +32 w, +34 h               the tile's size
;   +36 op (SH_COPY / SH_KEY), +38 sheet, +40 key colour
;   +42 u32 px                 what a record counts toward a call's 460,800 pixels
;   +46 diff                   1: only the cells whose tile differs from the slot's
;                              (hg_map_refresh)
;   +48 drawn                  + 1 a tile queued
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __rg
	.import	_hg__mw, _hg__qn, _hg__qpix, _hg__nruns, _hg__runs, _hg__runkind
	.import	_hg__offx, _hg__offy, _hg__submit
	.import	hgf_sheetrec
	.export	_hg__mapwalk

.define r0  __rg+0
.define r1  __rg+2
.define r2  __rg+4
.define r3  __rg+6
.define r4  __rg+8
.define r5  __rg+10
.define r6  __rg+12
.define r7  __rg+14
.define r9  __rg+18
.define r10 __rg+20
.define r11 __rg+22
.define r12 __rg+24
.define r13 __rg+26
.define r14 __rg+28
.define r28 __rg+32
.define r29 __rg+34
.define r30 __rg+36

MW	= _hg__mw
QMAX	= 128		; HG__Q

	.segment "CODE"

; r0/r1 [the map word], r2/r3 [the slot's word], r4 cells left, r5 x, r6 y, r7 the tile
_hg__mapwalk:
	lda	MW+0
	sta	r0
	lda	MW+2
	sta	r1
	lda	MW+6
	sta	r2
	lda	MW+8
	sta	r3
	lda	MW+14
	sta	r5
	lda	MW+16
	sta	r6
	lda	MW+12
	sta	r4
	bne	@loop
	RET
@loop:	lda	[r0]			; the tile
	cmp	MW+22
	bcc	@tok
	lda	#0
@tok:	sta	r7
	ldx	MW+46			; only the changed ones: the slot holds it already?
	beq	@q
	cmp	[r2]
	bne	@q
	jmp	@next
@q:	lda	_hg__qn			; room in the queue for one more record?
	cmp	#QMAX
	beq	@send
	clc
	lda	_hg__qpix
	adc	MW+42
	tay
	lda	_hg__qpix+2
	adc	MW+44
	cmp	#$0007			; 460,800 = $00070800
	bcc	@room
	bne	@send
	cpy	#$0801
	bcc	@room
@send:	pei	(r0)			; the queue sent first (hg__submit(1): C, changes __rg)
	pei	(r1)
	pei	(r2)
	pei	(r3)
	pei	(r4)
	pei	(r5)
	pei	(r6)
	pei	(r7)
	pea	1
	CALL	_hg__submit
	pla
	pla
	sta	r7
	pla
	sta	r6
	pla
	sta	r5
	pla
	sta	r4
	pla
	sta	r3
	pla
	sta	r2
	pla
	sta	r1
	pla
	sta	r0
@room:	lda	r7
@put:	sta	[r2]
	inc	MW+48
	and	MW+24			; sx = (t & tmask) << wsh
	ldx	MW+28
	beq	@sx1
@sx:	asl	a
	dex
	bne	@sx
@sx1:	sta	r13
	lda	r7			; sy = (t >> tsh) << hsh
	ldx	MW+26
	beq	@sy1
@sy:	lsr	a
	dex
	bne	@sy
@sy1:	ldx	MW+30
	beq	@sy3
@sy2:	asl	a
	dex
	bne	@sy2
@sy3:	sta	r30
	stz	r14
	lda	r5			; the slot (the origin added, as hg__rec does)
	clc
	adc	_hg__offx
	sta	r9
	lda	r6
	clc
	adc	_hg__offy
	sta	r10
	lda	MW+32
	sta	r11
	lda	MW+34
	sta	r12
	lda	MW+40
	sta	r28
	lda	MW+38
	sta	r29
	clc				; the count of pixels
	lda	_hg__qpix
	adc	MW+42
	sta	_hg__qpix
	lda	_hg__qpix+2
	adc	MW+44
	sta	_hg__qpix+2
	ldy	_hg__qn			; a new run of sheet records unless the last one is
	lda	_hg__nruns
	beq	@newrun
	lda	_hg__runkind
	cmp	#1
	beq	@same
@newrun:
	lda	_hg__nruns
	asl	a
	tax
	tya
	ora	#$8000
	sta	_hg__runs,x
	lda	#1
	sta	_hg__runkind
	inc	_hg__nruns
@same:	inc	_hg__qn
	lda	MW+36
	jsr	hgf_sheetrec		; record Y
@next:	lda	r0			; the next cell (the map's run lies in one bank)
	clc
	adc	MW+4
	sta	r0
	lda	r2
	clc
	adc	MW+10
	sta	r2
	lda	r5
	clc
	adc	MW+18
	sta	r5
	lda	r6
	clc
	adc	MW+20
	sta	r6
	dec	r4
	beq	@done
	jmp	@loop
@done:	RET
