; hg_rmp.s - hgame's colour remap helpers for cc816 (ca65), linked only by games that remap
; (hg_remap.c). The convention is in hg_fast.s's header.
;
; void hg__sheetq(unsigned op, unsigned sheet, unsigned c, unsigned sx, unsigned sy,
;                 unsigned w, unsigned h, int x, int y)
;   a sheet record of op (SH_*) from (sx, sy) of the sheet, w x h to (x, y) (screen
;   coordinates), through hg_fast.s's record core: clipped (the source moves with the cut),
;   counted, the queue sent first if full; nothing if wholly outside.
; void hg__remapmem(unsigned long dst, unsigned dstride, unsigned long src, unsigned sstride,
;                   unsigned w, unsigned h, unsigned key, unsigned long tab)
;   the CPU: h rows of w bytes, each written as tab[its source byte]; key $FFFF none, else
;   source bytes equal to key are skipped (before the table). Rows may cross banks; the
;   table is read with DBR = its bank (abs,X: the loop's operand is patched with its offset).
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __rg
	.import	hgf_reccore, hgf_sheetrec
	.export	_hg__sheetq, _hg__remapmem

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

; ------------------------------------------------------------------ hg__sheetq
; 3,s op, 5,s sheet, 7,s c, 9,s sx, 11,s sy, 13,s w, 15,s h, 17,s x, 19,s y
_hg__sheetq:
	lda	ARGS,s
	sta	r8
	lda	ARGS+14,s
	sta	r9
	lda	ARGS+16,s
	sta	r10
	lda	ARGS+10,s
	sta	r11
	lda	ARGS+12,s
	sta	r12
	lda	#1			; a sheet record
	sta	r3
	jsr	hgf_reccore
	bcs	@out
	lda	ARGS+6,s		; sx + the cut at the left
	clc
	adc	r13
	sta	r13
	lda	ARGS+8,s		; sy (hgf_sheetrec adds the cut at the top)
	sta	r30
	lda	ARGS+2,s
	sta	r29
	lda	ARGS+4,s
	sta	r28
	lda	r8
	jsr	hgf_sheetrec
@out:	RET

; ------------------------------------------------------------------ hg__remapmem
; 3,s dst, 7,s dstride, 9,s src, 13,s sstride, 15,s w, 17,s h, 19,s key, 21,s tab
_hg__remapmem:
	lda	ARGS,s			; [r0]: dst
	sta	r0
	lda	ARGS+2,s
	sta	r1
	lda	ARGS+4,s
	sta	r4			; dstride
	lda	ARGS+6,s		; [r2]: src
	sta	r2
	lda	ARGS+8,s
	sta	r3
	lda	ARGS+10,s
	sta	r5			; sstride
	lda	ARGS+12,s
	sta	r6			; w
	beq	rm_done
	lda	ARGS+14,s
	sta	r7			; h
	beq	rm_done
	lda	ARGS+16,s
	sta	r8			; key
	lda	ARGS+18,s		; the table's offset into both loops (DBR = the code bank)
	sta	rm_tk+1
	sta	rm_tp+1
	lda	ARGS+20,s
	sta	r9			; its bank
	phb
	ldx	r8
	lda	#0			; (B = 0: TAX takes B:A)
	sep	#$20
	.a8
	lda	r9
	pha
	plb				; DBR = the table's bank
	cpx	#$FFFF
	beq	rm_prow
rm_krow:
	ldy	#0
rm_k:	lda	[r2],y
	cmp	r8
	beq	rm_ks
	tax
rm_tk:	lda	a:$0000,x
	sta	[r0],y
rm_ks:	iny
	cpy	r6
	bne	rm_k
	jsr	rm_next
	bne	rm_krow
	bra	rm_end
rm_prow:
	ldy	#0
rm_p:	lda	[r2],y
	tax
rm_tp:	lda	a:$0000,x
	sta	[r0],y
	iny
	cpy	r6
	bne	rm_p
	jsr	rm_next
	bne	rm_prow
rm_end:	rep	#$20
	.a16
	plb
rm_done:
	RET

; the next rows (24-bit adds); Z set when none is left. Called and returns with a8 (B = 0)
	.a8
rm_next:
	rep	#$20
	.a16
	clc
	lda	r0
	adc	r4
	sta	r0
	bcc	:+
	inc	r1
:	clc
	lda	r2
	adc	r5
	sta	r2
	bcc	:+
	inc	r3
:	dec	r7
	php				; (Z)
	lda	#0
	plp
	sep	#$20			; (Z kept)
	.a8
	rts
