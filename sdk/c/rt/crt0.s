; crt0.s - the C startup and exit for programs built with cc816 (ca65). Linked first: Horizon
; enters a program at code bank:$0100, the start of its text (hzprog.cfg: STARTUP first).
;
; Horizon starts a task native, A/X/Y 16-bit, PBR = DBR = code bank, D = 0, S just below
; the argument string in the window (bank 0), X = the string's window offset, A = its
; length (ABI.md, "Task start conditions").
;
; cc816's memory model (sdk/docs/c/reference.md):
;   code bank  $0100..        code, constants, data, bss (every near pointer is an offset
;                             in this bank: DBR), then the heap (malloc, upwards)
;              __hz_sslo..    the software stack's guard zone (256 bytes)
;              ..$FFF0        the software stack (__sp, downwards): arrays, structures and
;                             locals whose address is taken; __HZ_SSTACK__ bytes (hcc
;                             --stack N, default 8192)
;   bank 0     $0000-$00FF    the direct page: cc816's registers (ZEROPAGE below), the
;                             controls library's when it is linked
;              $0100-$01FF    the hardware stack's guard zone
;              ..S            the hardware stack: return addresses, arguments, spilled
;                             registers (about 32 KB, up to the argument string)
;
; __start: the argument string copied into the code bank, both stacks' guard zones filled
;          (hcc --debug: both stacks painted first), the constructors, main(argc, argv),
;          exit.
; exit:    the atexit functions (newest first), the destructors (the C library's: every
;          FILE flushed and closed), the stack checks (lib/exitchk.c), SYS_EXIT.
;
; The large code model (hcc --code large, ca65 -D __CC816_LARGE__): C functions are called
; with JSL and return with RTL (model.inc), wherever they are. Before the constructors,
; __hz_xload (lib/cc816/xload.c) loads the program's other code banks from its own file;
; then the constructors, main and the exit functions are called as JSL calls. __icall is
; the call through a function pointer: JSL __icall with the pointer in __fpt (a 16-bit
; address in this bank: the function, or its thunk JML in the main bank).

	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"

	.exportzp __rg, __sp, __rv, __h0, __h1, __h2, __h3, __cbank, __hz_zpend
	.export	__start, __fpt, __abs0
	.export	___hz_argbuf, ___hz_arglen, ___hz_argoff, ___hz_stktop, ___hz_sslo
	.export	_exit, __Exit, _atexit, _abort
	.export	_hz_stack_free, _hz_sstack_free
	.export	___hz_heapstart, ___hz_heapend, ___hz_paintflag
	.export	___hz_heapuse, ___hz_heappeak
	.import	_main, ___hz_mkargs, ___hz_argv, ___hz_exitchk
	.import	__HZ_SSTACK__, __HZ_PAINT__
	.import	__CONSTRUCTOR_TABLE__, __CONSTRUCTOR_COUNT__
	.import	__DESTRUCTOR_TABLE__, __DESTRUCTOR_COUNT__
.if LARGE
	.export	__icall, __cc816_large
	.import	___hz_xload
__cc816_large = 1		; (every object cc816 makes for the large model imports it)
.else
	.export	__cc816_small
__cc816_small = 1
.endif

__abs0	= 0			; *(T *)constant: an absolute address in the code bank
SSTOP	= $FFF0			; the software stack's top (it grows down from here)
HSLO	= $0100			; the hardware stack's lowest address (window)
GUARD	= $C35A			; the guard zones' pattern (lib/exitchk.c knows it)
PAINTW	= $A5A5			; hcc --debug's paint
ZONE	= 256			; the guard zones' size
MAXEXIT	= 32			; atexit functions

	.segment "ZEROPAGE"
__rg:	.res	96		; registers: 48 bytes scratch, 48 callee-saved
__sp:	.res	2		; the software stack pointer (code bank)
__rv:	.res	4		; the return value across an epilogue, helper scratch
__h0:	.res	4		; the runtime helpers' operands and scratch
__h1:	.res	4
__h2:	.res	4
__h3:	.res	4
__cbank: .res	2		; the code bank's number (far pointers to near data)
__hz_zpend:			; (the end of cc816's direct page: the controls library's
				; zero page follows, ui/lib816/hui816.inc)

	.segment "STARTUP"
__start:
	sta	___hz_arglen
	stx	___hz_argoff
	sep	#$20
	.a8
	phk
	pla
	sta	__cbank
	stz	__cbank+1
	; the argument string (bank 0) into the code bank, at most 255 characters
	ldy	#0
@cp:	lda	f:$000000,x
	sta	___hz_argbuf,y
	beq	@cpd
	inx
	iny
	cpy	#255
	bcc	@cp
	lda	#0
	sta	___hz_argbuf,y
@cpd:	rep	#$20
	.a16
	; the hardware stack (window): paint it (--debug), then its guard zone
	tsc
	sta	___hz_stktop
	lda	#__HZ_PAINT__
	beq	@nohp
	tsc
	sec
	sbc	#32
	sta	__h0
	ldx	#HSLO
	lda	#PAINTW
@hp:	sta	f:$000000,x
	inx
	inx
	cpx	__h0
	bcc	@hp
@nohp:	ldx	#HSLO
	lda	#GUARD
@hg:	sta	f:$000000,x
	inx
	inx
	cpx	#HSLO + ZONE
	bcc	@hg
	; the software stack (code bank): the same
	lda	#SSTOP
	sta	__sp
	sec
	sbc	#__HZ_SSTACK__
	sta	___hz_sslo
	lda	#__HZ_PAINT__
	beq	@nosp
	lda	___hz_sslo
	tax
	lda	#PAINTW
@sp:	sta	a:0,x
	inx
	inx
	cpx	#SSTOP
	bcc	@sp
@nosp:	ldx	___hz_sslo
	lda	___hz_sslo
	clc
	adc	#ZONE
	sta	__h0
	lda	#GUARD
@sg:	sta	a:0,x
	inx
	inx
	cpx	__h0
	bcc	@sg
	; the constructors (functions named _INIT_n_...: cc816 lists them for ld65)
.if LARGE
	jsl	___hz_xload	; the other code banks (lib/cc816/xload.c)
.endif
	ldx	#0
@ct:	cpx	#__CONSTRUCTOR_COUNT__ * 2
	bcs	@ctd
	phx
.if LARGE
	phk			; a JSL's return address (constructors are in this bank)
	pea	@ctr - 1
	jmp	(__CONSTRUCTOR_TABLE__,x)
@ctr:
.else
	jsr	(__CONSTRUCTOR_TABLE__,x)
.endif
	plx
	inx
	inx
	bra	@ct
@ctd:	CALL	___hz_mkargs	; lib/args.c: A = argc, ___hz_argv = argv
	tax
	lda	___hz_argv	; main(int argc, char **argv) (or main(void): the same call)
	pha
	phx
	CALL	_main
	ply
	ply
	jmp	exitA

; void exit(int code)
_exit:	lda	ARGS,s
exitA:	ldx	inexit		; exit() inside an atexit function or a destructor: ignored
	beq	@go
	RET			; (after main: main's return was the program's end, exitA)
@go:	sta	exitcode
	inc	inexit
@at:	ldx	nexit		; the atexit functions, newest first
	beq	dtors
	dex
	dex
	stx	nexit
.if LARGE
	lda	exittab,x
	sta	__fpt
	jsl	__icall
.else
	jsr	(exittab,x)
.endif
	bra	@at

; void _Exit(int code): no atexit functions, but the destructors (the files are flushed)
__Exit:	lda	ARGS,s
	sta	exitcode
	inc	inexit
dtors:	ldx	#__DESTRUCTOR_COUNT__ * 2
@dt:	cpx	#2
	bcc	@dtd
	dex
	dex
	phx
.if LARGE
	phk
	pea	@dtr - 1
	jmp	(__DESTRUCTOR_TABLE__,x)
@dtr:
.else
	jsr	(__DESTRUCTOR_TABLE__,x)
.endif
	plx
	bra	@dt
@dtd:	CALL	___hz_exitchk	; lib/exitchk.c: the guard zones (and --debug's report)
	lda	exitcode
@end:	cop	#0		; SYS_EXIT, never returns
	bra	@end

; void abort(void): exit code 3, no atexit functions, no flushing
_abort:	lda	#3
	cop	#0
	bra	_abort

; int atexit(void (*f)(void)): 0, or -1 when MAXEXIT functions are registered
_atexit:
	lda	nexit
	cmp	#MAXEXIT * 2
	bcs	@full
	tax
	lda	ARGS,s
	sta	exittab,x
	inx
	inx
	stx	nexit
	lda	#0
	RET
@full:	lda	#$FFFF
	RET

; unsigned hz_stack_free(void): bytes of the hardware stack below S now
_hz_stack_free:
	tsc
	clc
	adc	#ARGS - 1	; (S before the call)
	sec
	sbc	#HSLO
	RET

; unsigned hz_sstack_free(void): bytes of the software stack below __sp now
_hz_sstack_free:
	lda	__sp
	sec
	sbc	___hz_sslo
	RET

.if LARGE
; a call through a function pointer (the large code model): JSL __icall with the pointer
; (an address in this bank) in __fpt; the function returns to the caller with its RTL
__icall:
	ldx	#0
	jmp	(__fpt,x)
.endif

	.segment "RODATA"
; the heap: from the end of bss to the software stack's guard zone (lib/cc816/malloc.c)
___hz_heapstart:
	.addr	heap0
___hz_paintflag:		; nonzero with hcc --debug (lib/exitchk.c's report)
	.word	__HZ_PAINT__

	.segment "BSS"
___hz_argbuf:	.res	256	; the argument string (lib/args.c splits it into argv)
___hz_arglen:	.res	2
___hz_argoff:	.res	2
___hz_stktop:	.res	2	; S at the start (--debug's report)
___hz_sslo:	.res	2	; the software stack's lowest address (its guard zone)
___hz_heapend	= ___hz_sslo
__fpt:	.res	2		; indirect calls: JSR (__fpt,X)
inexit:	.res	2
exitcode: .res	2
nexit:	.res	2
exittab: .res	MAXEXIT * 2
___hz_heapuse:	.res	2	; the heap's bytes in use (lib/cc816/malloc.c), and the most
___hz_heappeak:	.res	2	; since the start (hz_heap_peak, --debug's report)

	.segment "HEAPSTART"		; (hzprog.cfg: after every module's bss)
heap0:	.res	2
