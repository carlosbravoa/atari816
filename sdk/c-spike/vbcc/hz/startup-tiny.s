; startup-tiny.s - vbcc 65816 C startup for Horizon, tiny data model (-mtiny): code in the
; code bank, all data, the stack and the direct page in the task's window (bank 0),
; DBR = 0 (see hz/horizon-tiny.cmd). vasm oldstyle syntax.

	global	___exit
	global	_start
	global	___hz_argoff
	global	___hz_args
	global	___hz_arglen

	section	"DONTMERGE_text.startup","acrx"
	a16
	x16
_start:
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
	ldx	#___WBS			; clear bss (the loader clears only its own bss)
	bra	clrtst
clr:	stz	0,x
	inx
clrtst:	cpx	#___WBE
	bcc	clr
	rep	#32
	a16
	ldx	#254			; clear the direct page (see startup.s)
clrdp:	stz	0,x
	dex
	dex
	bpl	clrdp
	plx
	stx	!___hz_argoff
	stx	!___hz_args		; as a C pointer (16-bit: the window is the data bank)
	pla
	sta	!___hz_arglen
	lda	#0
	jsl	>___main
___exit:
	rep	#48
	cop	#0			; SYS_EXIT, never returns
	bra	___exit

	section	"DONTMERGE_bss.near.hzstart","aurw"
___hz_argoff:	reserve	2
___hz_arglen:	reserve	2
___hz_args:	reserve	2

; vbcc's direct-page registers at fixed direct-page addresses: Horizon's D is 0 and the
; direct page is always window $0000, so they need no relocation (vlink's o65 writer
; would not relocate a zp section anyway). r0..r31 = $00..$3F, btmp0..btmp3 = $40..$4F.
; $50..$FF stay free for assembly code (ulib-style variables).
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
