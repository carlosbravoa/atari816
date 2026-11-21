; ulibwrap.s - puts the ulib block (asmlib/blob.s + ulib.o, linked by ld65 at $0100) first
; in a vbcc program's text and names its jump table for C. vasm oldstyle syntax.
; The block's first 3 bytes are a placeholder for a JMP to the C startup: this file puts
; that JMP (16-bit, the same bank) instead, then the rest of the block from byte 3.

	global	_ul_puts
	global	_ul_putdec
	global	_ul_flush
	global	_ul_puthex

	section	"DONTMERGE_text.blob","acrx"
blob:	jmp	!_start
	incbin	"build/blob.bin",3
_ul_puts	equ	blob+3
_ul_putdec	equ	blob+7
_ul_flush	equ	blob+11
_ul_puthex	equ	blob+15
