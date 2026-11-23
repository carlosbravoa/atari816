; setjmp.s - setjmp and longjmp for cc816 (cc816/include/setjmp.h).
;
; The jmp_buf (27 words, in the code bank):
;   +0   S at setjmp's entry (the return address is at S+1)
;   +2   the return address
;   +4   __sp (the software stack pointer)
;   +6   __rg+48 .. __rg+95, the callee-saved registers (48 bytes)
; In the large code model (hcc --code large) the return address has 3 bytes: its bank is
; kept too, at +54 (the jmp_buf has 28 words there, setjmp.h).
; D is always 0 and DBR the code bank, so neither is kept. longjmp puts S, __sp and the
; registers back, writes the return address where it was, and returns from setjmp a
; second time with its value in A (1 if it is 0). The compiler knows that a function
; that calls setjmp sees it return twice (front.py, regalloc.py): a value live across
; the call keeps a location of its own.
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.importzp __rg, __sp, __rv, __h0
	.export	_setjmp, _longjmp

	.segment "CODE"

.if FARDATA
; The far data model (hcc --data far): env is a far pointer (a jmp_buf in any bank), the
; same layout through [__h0],y; val at ARGS+4.
_setjmp:
	lda	ARGS,s
	sta	__h0
	lda	ARGS+2,s
	sta	__h0+2
	tsc
	sta	[__h0]
	ldy	#2
	lda	1,s
	sta	[__h0],y
	ldy	#54
	lda	3,s			; the return address's bank
	sta	[__h0],y
	ldy	#4
	lda	__sp
	sta	[__h0],y
	.repeat	24, k
	iny
	iny
	lda	__rg+48+2*k
	sta	[__h0],y
	.endrep
	lda	#0
	RET

_longjmp:
	lda	ARGS+4,s
	bne	:+
	inc	a
:	sta	__rv
	lda	ARGS,s
	sta	__h0
	lda	ARGS+2,s
	sta	__h0+2
	ldy	#4
	.repeat	24, k
	iny
	iny
	lda	[__h0],y
	sta	__rg+48+2*k
	.endrep
	ldy	#4
	lda	[__h0],y
	sta	__sp
	lda	[__h0]
	tcs
	ldy	#2
	lda	[__h0],y
	sta	1,s
	ldy	#54
	sep	#$20
	.a8
	lda	[__h0],y
	sta	3,s
	rep	#$20
	.a16
	lda	__rv
	RET
.else

; int setjmp(jmp_buf env): env at 3,s (large: 4,s)
_setjmp:
	lda	ARGS,s
	tax
	tsc
	sta	a:0,x
	lda	1,s
	sta	a:2,x
.if LARGE
	lda	3,s			; the return address's bank (and env's low byte: unused)
	sta	a:54,x
.endif
	lda	__sp
	sta	a:4,x
	.repeat	24, k
	lda	__rg+48+2*k
	sta	a:6+2*k,x
	.endrep
	lda	#0
	RET

; void longjmp(jmp_buf env, int val): env at 3,s, val at 5,s (large: 4,s and 6,s)
_longjmp:
	lda	ARGS+2,s
	bne	:+
	inc	a
:	sta	__rv
	lda	ARGS,s
	tax
	.repeat	24, k
	lda	a:6+2*k,x
	sta	__rg+48+2*k
	.endrep
	lda	a:4,x
	sta	__sp
	lda	a:0,x
	tcs
	lda	a:2,x
	sta	1,s
.if LARGE
	sep	#$20
	.a8
	lda	a:54,x
	sta	3,s
	rep	#$20
	.a16
.endif
	lda	__rv
	RET
.endif
