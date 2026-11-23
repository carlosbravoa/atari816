; model.inc - the code model, for the C library's assembly (ca65). hcc builds the library
; twice: for the small code model (JSR/RTS, as always) and for the large one (hcc --code
; large: ca65 -D __CC816_LARGE__; JSL/RTL, sdk/docs/c/reference.md, "The two code models").
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
.ifdef __CC816_LARGE__
LARGE	= 1
ARGS	= 4
.macro	RET
	rtl
.endmacro
.macro	CALL target
	jsl	target
.endmacro
.macro	TAILJ target
	jml	target
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
.endif
.ifdef __CC816_FAR_DATA__
FARDATA	= 1
PTRSZ	= 4
.else
FARDATA	= 0
PTRSZ	= 2
.endif
