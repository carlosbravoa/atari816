; crt0.s - the C startup and exit for Horizon (vasm oldstyle syntax), both memory models.
; Assembled twice by the library build: plain for the large model, -DTINY=1 for tiny.
;
; Horizon starts a task native, A/X/Y 16-bit, PBR = DBR = code bank, D = 0, S just below
; the argument string in the window (bank 0), X = the string's window offset, A = its
; length (ABI.md, "Task start conditions").
;
; _start:  (tiny: copy the data image to the window, clear bss, DBR = 0), clear the direct
;          page, remember the argument string, fill the stack's lowest 256 bytes with a
;          guard pattern (and, linked with hcc --debug, paint the whole stack first),
;          call __main.
; __main:  the constructors, then main(argc, argv) (lib/args.c builds them), then exit.
; exit:    the atexit functions, the destructors (lib/stdio.c's flushes and closes every
;          FILE), then __exit: lib/exitchk.c checks the guard zone (and reports the stack
;          used with --debug), then SYS_EXIT.
; This replaces the C library's _main.o, whose main() gets no arguments and whose exit()
; loses its argument.

; vbcc's direct-page registers at fixed direct-page addresses: Horizon's D is 0 and the
; direct page is always window $0000, so they need no relocation. r0..r31 = $00..$3F,
; btmp0..btmp3 = $40..$4F. $50..$FF stay free for assembly code.
r0	ezp	$00
r1	ezp	$02
r2	ezp	$04
r3	ezp	$06
r4	ezp	$08
r5	ezp	$0A
r6	ezp	$0C
r7	ezp	$0E
r8	ezp	$10
r9	ezp	$12
r10	ezp	$14
r11	ezp	$16
r12	ezp	$18
r13	ezp	$1A
r14	ezp	$1C
r15	ezp	$1E
r16	ezp	$20
r17	ezp	$22
r18	ezp	$24
r19	ezp	$26
r20	ezp	$28
r21	ezp	$2A
r22	ezp	$2C
r23	ezp	$2E
r24	ezp	$30
r25	ezp	$32
r26	ezp	$34
r27	ezp	$36
r28	ezp	$38
r29	ezp	$3A
r30	ezp	$3C
r31	ezp	$3E
btmp0	ezp	$40
btmp1	ezp	$44
btmp2	ezp	$48
btmp3	ezp	$4C
	global	r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12,r13,r14,r15
	global	r16,r17,r18,r19,r20,r21,r22,r23,r24,r25,r26,r27,r28,r29,r30,r31
	global	btmp0,btmp1,btmp2,btmp3

	global	_start
	global	___main
	global	_exit
	global	__Exit
	global	___exit
	global	___firstexit
	global	___hz_argoff
	global	___hz_arglen
	global	___hz_stktop

HZ_GUARD	equ	$C35A		; the stack guard pattern (lib/exitchk.c knows it)
HZ_PAINTW	equ	$A5A5		; the paint pattern of --debug

	section	"DONTMERGE_text.startup","acrx"
	a16
	x16
_start:
	if	TINY
	pha				; the argument string's length
	phx				; and window offset
	lda	#___WDL			; copy the data image: code bank -> window
	beq	nodata
	dec	a
	ldx	#<___WDC
	ldy	#___WDS
	mvn	___WDC,___WDS		; (sets DBR = 0, the destination bank)
nodata:
	pea	#0
	plb
	plb				; DBR = 0 also without data
	sep	#32
	a8
	ldx	#___WBS			; clear bss (the loader clears only its own)
	bra	clrtst
clr:	stz	0,x
	inx
clrtst:	cpx	#___WBE
	bcc	clr
	rep	#32
	a16
	plx
	pla
	endif
	stx	!___hz_argoff		; the argument string: window offset
	sta	!___hz_arglen		; and length
	ldx	#254			; clear the direct page (the loader clears only an o65
clrdp:	stz	0,x			; zp segment, and there is none)
	dex
	dex
	bpl	clrdp
	tsc
	sta	>___hz_stktop		; the stack's top (for --debug's report)
	lda	#___hz_paint		; hcc --debug: paint the stack, ___hz_stklo .. S - 32
	beq	nopaint
	ldx	#___hz_stklo
	tsc
	sec
	sbc	#32
	sta	r0
	lda	#HZ_PAINTW
paint:	sta	>0,x
	inx
	inx
	cpx	r0
	bcc	paint
nopaint:
	ldx	#___hz_stklo		; the guard zone: the stack's lowest 256 bytes
	lda	#HZ_GUARD
guard:	sta	>0,x
	inx
	inx
	cpx	#___hz_stklo+256
	bcc	guard
	lda	#0
	jsl	>___main		; never returns
___exit:				; A = exit code
	rep	#48
	pha
	jsl	>___hz_exitchk		; lib/exitchk.c: the stack guard (and --debug report)
	pla
	cop	#0			; SYS_EXIT, never returns
	bra	___exit

	section	"DONTMERGE_text.far.hzmain","acrx"
	a16
	x16
indir:	jml	[r0]

; __main: the constructors (vlink's list: a 3-byte count, then 3-byte addresses), then
; main. (The C library's own __main reads the count as the first address: a program with
; a constructor, as the float library has, jumped to address 1.)
___main:
	lda	>___CTOR_LIST__
	beq	ctordone
	sta	r16+2			; the count
	ldx	#3
ctor:	lda	>___CTOR_LIST__,x
	sta	r0
	lda	>___CTOR_LIST__+2,x
	and	#255
	sta	r1
	stx	r16
	jsl	>indir
	ldx	r16
	inx
	inx
	inx
	dec	r16+2
	bne	ctor
ctordone:
	jsl	>___hz_mkargs		; lib/args.c -> A = argc, ___hz_argv = argv
	if	TINY
	lda	>___hz_argv
	pha
	else
	lda	>___hz_argv+2
	pha
	lda	>___hz_argv
	pha
	endif
	lda	>___hz_argc
	jsl	>_main			; main(argc, argv) (or main(void): the same call)
	; fall into exit with main's result

; exit(code): A = code. The atexit functions (newest first), then the destructors.
_exit:
	tay
	lda	>inexit			; exit() from an atexit function: ignored
	beq	doexit
	rtl
doexit:	phy				; the code
	lda	#1
	sta	>inexit
	lda	>___firstexit
	sta	r16
	lda	>___firstexit+2
	sta	r17
	bra	atest
anext:	ldy	#4			; {far next, function}
	lda	[r16],y
	sta	r0
	iny
	iny
	lda	[r16],y
	sta	r1
	jsl	>indir
	ldy	#0
	lda	[r16],y
	tax
	iny
	iny
	lda	[r16],y
	sta	r17
	stx	r16
atest:	lda	r16
	ora	r17
	bne	anext
	bra	dtors

; _Exit(code): no atexit functions, but the destructors (the files are flushed)
__Exit:	pha
dtors:	lda	>___DTOR_LIST__		; vlink's list: a count, then 3-byte addresses
	beq	dtordone
	sta	r0
	clc
	adc	r0
	adc	r0
	tax
dtor:	lda	>___DTOR_LIST__,x
	sta	r0
	lda	>___DTOR_LIST__+2,x
	sta	r1
	stx	r16
	jsl	>indir
	ldx	r16
	dex
	dex
	dex
	bne	dtor
dtordone:
	pla
	jml	>___exit

	section	"DONTMERGE_bss.near.hzstart","aurw"
___hz_argoff:	reserve	2
___hz_arglen:	reserve	2
___hz_stktop:	reserve	2
inexit:		reserve	2
___firstexit:	reserve	4

