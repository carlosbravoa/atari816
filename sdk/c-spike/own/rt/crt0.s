; crt0.s - cc816 C startup for a Horizon program (Atari816). Linked first: Horizon enters
; the program at code bank:$0100, the start of the text.
;
; Horizon starts the task native, A/X/Y 16-bit, PBR = DBR = code bank, D = 0, S in the
; task's window (bank 0) just below the argument string, X = its window offset, A = its
; length. cc816's memory model:
;   code bank  $0100..      code, rodata, data, bss (all C data: pointers are 16-bit
;                           offsets in this bank, DBR), then the heap (malloc, upwards)
;              ..$FFEF      the software stack (__sp, downwards): arrays, structures and
;                           locals whose address is taken
;   bank 0     $0000-$00FF  direct page: __rg registers and the runtime's scratch
;              ...          the hardware stack: return addresses, arguments, spilled
;                           registers (stack-relative addressing), up to the arguments
	.p816
	.smart	+
	.a16
	.i16
	.exportzp __rg, __sp, __rv, __h0, __h1, __h2, __h3, __cbank
	.export	__hz_argbuf, __hz_arglen, ___hz_arglen, __fpt, __abs0, __start
	.export	_hz_args
	.import	_main, _exit

__abs0	= 0
SOFTTOP	= $FFF0

	.segment "ZEROPAGE"
__rg:	.res	96		; registers: 48 bytes scratch, 48 callee-saved
__sp:	.res	2		; software stack pointer (code bank)
__rv:	.res	4		; return value across the epilogue, helper scratch
__h0:	.res	4		; runtime helper arguments / scratch
__h1:	.res	4
__h2:	.res	4
__h3:	.res	4
__cbank: .res	2		; the code bank number (for far pointers)

	.segment "CODE"
__start:
	sta	__hz_arglen
	stx	__hz_argoff
	sep	#$20
	phk
	pla
	sta	__cbank
	stz	__cbank+1
	; copy the argument string (bank 0) into the code bank: hz_args
	ldy	#0
@cp:	lda	f:$000000,x
	sta	__hz_argbuf,y
	beq	@cpd
	inx
	iny
	cpy	#127
	bcc	@cp
	lda	#0
	sta	__hz_argbuf,y
@cpd:	rep	#$20
	lda	#SOFTTOP
	sta	__sp
	pea	argv0		; main(int argc, char **argv): argc 1, argv { "", NULL }
	pea	1
	jsr	_main
	ply
	ply
	pha
	jsr	_exit		; never returns
@hang:	bra	@hang

	.segment "RODATA"
argv0:	.addr	argv0+4, 0
	.byte	0

	.segment "BSS"
__hz_argbuf:
_hz_args: .res	128
__hz_arglen:
___hz_arglen: .res 2
__hz_argoff: .res 2
__fpt:	.res	2		; indirect calls: JSR (__fpt,X)
