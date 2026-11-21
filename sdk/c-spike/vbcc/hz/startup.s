; startup.s - vbcc 65816 C startup for a Horizon program (Atari816), vasm oldstyle syntax.
;
; Horizon starts the task native, A/X/Y 16-bit, PBR = DBR = code bank, D = 0, S in the
; task's window (bank 0), X = window offset of the argument string, A = its length.
; vbcc's large (default) data model fits that as is: data pointers are 32-bit (offset,
; bank), locals live on the hardware stack and &local is a bank-0 pointer; near data
; (vbcc's automatic near placement of small statics) is addressed through DBR = the
; code bank (__DBR_init is placed in the code bank by the linker script).

	global	___exit
	global	_start
	global	___hz_argoff
	global	___hz_args
	global	___hz_arglen

	section	"DONTMERGE_text.startup","acrx"
	a16
	x16
_start:
	stx	!___hz_argoff		; the argument string: window (bank 0) offset
	stx	!___hz_args		; and as a C pointer (32-bit: offset, bank 0, 0)
	stz	!___hz_args+2
	sta	!___hz_arglen		; and length
	ldx	#254			; clear the direct page (the loader clears only an
clrdp:	stz	0,x			; o65 zp segment, and there is none): assembly
	dex				; libraries' variables above $50 start at 0
	dex
	bpl	clrdp
	lda	#0
	jsl	>___main		; constructors, main(), exit(main's result)
___exit:				; A = exit code (16-bit regs: __main is C)
	rep	#48
	cop	#0			; SYS_EXIT, never returns
	bra	___exit

	section	"DONTMERGE_bss.near.hzstart","aurw"
___hz_argoff:	reserve	2
___hz_arglen:	reserve	2
___hz_args:	reserve	4

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
