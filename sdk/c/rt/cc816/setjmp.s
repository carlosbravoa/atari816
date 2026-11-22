; setjmp.s - setjmp and longjmp for cc816 (cc816/include/setjmp.h).
;
; The jmp_buf (27 words, in the code bank):
;   +0   S at setjmp's entry (the return address is at S+1)
;   +2   the return address
;   +4   __sp (the software stack pointer)
;   +6   __rg+48 .. __rg+95, the callee-saved registers (48 bytes)
; D is always 0 and DBR the code bank, so neither is kept. longjmp puts S, __sp and the
; registers back, writes the return address where it was, and returns from setjmp a
; second time with its value in A (1 if it is 0). The compiler knows that a function
; that calls setjmp sees it return twice (front.py, regalloc.py): a value live across
; the call keeps a location of its own.
	.p816
	.smart	-
	.a16
	.i16
	.importzp __rg, __sp, __rv
	.export	_setjmp, _longjmp

	.segment "CODE"

; int setjmp(jmp_buf env): env at 3,s
_setjmp:
	lda	3,s
	tax
	tsc
	sta	a:0,x
	lda	1,s
	sta	a:2,x
	lda	__sp
	sta	a:4,x
	.repeat	24, k
	lda	__rg+48+2*k
	sta	a:6+2*k,x
	.endrep
	lda	#0
	rts

; void longjmp(jmp_buf env, int val): env at 3,s, val at 5,s
_longjmp:
	lda	5,s
	bne	:+
	inc	a
:	sta	__rv
	lda	3,s
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
	lda	__rv
	rts
