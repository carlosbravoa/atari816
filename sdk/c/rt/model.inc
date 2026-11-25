; model.inc - the code model, for the C library's assembly (ca65). hcc builds the library
; twice: for the small code model (JSR/RTS, as always) and for the large one (hcc --code
; large: ca65 -D __CC816_LARGE__; JSL/RTL, sdk/docs/c/reference.md, "Code models").
;
;   ARGS     the first argument's stack offset in a C-callable routine: 3 (JSR's return
;            address is 2 bytes), 4 in the large code model (JSL's is 3)
;   RET      the return of a routine C code calls: rts / rtl
;   CALL x   a call of such a routine (a C function, an arithmetic helper): jsr / jsl
;   TAILJ x  a tail call of a C function (the same arguments, the same return): jmp, or
;            jml in the large code model (the function may be in another bank)
;   LARGE    1 in the large code model, else 0
;   FARDATA  1 in the far data model (hcc --data far: ca65 -D __CC816_FAR_DATA__), else 0
;   PTRSZ    a data pointer argument's bytes on the stack: 2, or 4 with far data (offset,
;            bank, 0)
;
; Only the routines generated code calls change: a routine the library's assembly calls
; by itself (jsr ... rts) stays as it is.
;
; Movable assembly (sdk/docs/c/reference.md, "Movable assembly"): a function hcc may place
; in another bank, as it places a C function.
;   FUNC name      opens the function's own code segment and exports name, which must be
;                  a C name (_name): in the large code model segment F_name (as cc816's
;                  movable functions: hcc places it), in the small one "CODE". The
;                  function ends with RET; C and other assembly call it with CALL
;   XBANK n        the byte n bytes back is a bank byte of the program (a function's, the
;                  main bank's, a far object's): recorded for hcc (segment XREL), which
;                  patches it when the program starts. After lda #^name (16-bit A: n = 2),
;                  lda f:name (n = 1), .faraddr name (n = 1), a jsl or jml of your own
;                  (n = 1). Nothing in the small code model. Not for a fixed bank
;                  (Horizon's, the hardware's: a constant needs no patch)
;   FNADDR name    lets the file use __T<name>, a function's 16-bit address (for a
;                  function pointer, a callback): in the large code model it imports it
;                  (hcc makes it: the function, or a thunk in the main bank when the
;                  function is in another bank); in the small one it is name itself
;                  (import or define name as usual)
; In a FUNC segment of the large model, CALL and TAILJ record the bank byte of their jsl
; / jml (they then take 3 bytes more of XREL, which is not loaded).
__HZ_FAR .set 0
.macro	FUNC name
	.if .strat(.string(name), 0) <> '_'
	.error	"FUNC: a movable function's name is a C name, _name"
	.endif
.ifdef __CC816_LARGE__
	.segment .concat("F", .string(name))
	__HZ_FAR .set 1
.else
	.segment "CODE"
.endif
	.export name
name:
.endmacro
.ifdef __CC816_LARGE__
LARGE	= 1
ARGS	= 4
.macro	RET
	rtl
.endmacro
.macro	CALL target
	jsl	target
	.if __HZ_FAR
	XBANK	1
	.endif
.endmacro
.macro	TAILJ target
	jml	target
	.if __HZ_FAR
	XBANK	1
	.endif
.endmacro
; (its label is a cheap local one, @__hz_xN: a normal label, even .local, would end the
; scope of the code's own @labels)
__HZ_XN .set 0
.macro	XBANK n
.ident(.sprintf("@__hz_x%d", __HZ_XN)):
	.pushseg
	.segment "XREL"
	.faraddr .ident(.sprintf("@__hz_x%d", __HZ_XN)) - (n)
	.popseg
__HZ_XN .set __HZ_XN + 1
.endmacro
.macro	FNADDR name
	.import	.ident(.concat("__T", .string(name)))
.endmacro
.else
LARGE	= 0
ARGS	= 3
.macro	RET
	rts
.endmacro
.macro	CALL target
	jsr	target
.endmacro
.macro	TAILJ target
	jmp	target
.endmacro
.macro	XBANK n
.endmacro
.macro	FNADDR name
	.ident(.concat("__T", .string(name))) = name
.endmacro
.endif
.ifdef __CC816_FAR_DATA__
FARDATA	= 1
PTRSZ	= 4
.else
FARDATA	= 0
PTRSZ	= 2
.endif
