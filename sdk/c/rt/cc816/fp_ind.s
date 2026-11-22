; fp_ind.s - cc816's floating point: the operand moves of the ...i entries (shorter code
; at each call: the compiler passes the direct-page addresses of its registers instead of
; copying them itself). The contract: fp_pack.s.
;
;   __fpNNNi   X = the address of a (on the direct page), Y = that of b, A = the address
;              for the result (__h0: none; the result is in __h0 as always)
;   __fpNNNx   a in __h0 already (a chain), X = the address of b
;   __fpNNNrx  b in __h0 already, X = the address of a
;
; __fp_ld2 copies a and b into __h0 and __h1, __fp_ldx (X) into __h1; __fp_st stores __h0
; at A. Each operation's
; module has its own ...i entry (pha, jsr __fp_ld2, jsr __fNNN, pla, jmp __fp_st), so only
; the operations a program uses are linked.
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __h0, __h1
	.export	__fp_ld2, __fp_st, __fp_ldx

	.segment "CODE"

__fp_ld2:
	lda	0,x
	sta	__h0
	lda	2,x
	sta	__h0+2
	tyx
	lda	0,x
	sta	__h1
	lda	2,x
	sta	__h1+2
	rts

__fp_ldx:
	lda	0,x
	sta	__h1
	lda	2,x
	sta	__h1+2
	rts

__fp_st:
	tax			; (A = __h0 when there is no destination: a store onto itself;
	lda	__h0		; not 0, which is __rg+0's address)
	sta	0,x
	lda	__h0+2
	sta	2,x
	RET
