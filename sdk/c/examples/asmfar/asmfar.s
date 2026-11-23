; asmfar.s - movable assembly for asmfar.c (rt/model.inc: FUNC, CALL, XBANK, FNADDR).
; In the large code model each FUNC is a segment of its own, F_name, which hcc places
; where it places C functions: in the main bank while it has room, else in another bank.
; PBR is then that bank; DBR is the main bank, always.
        .p816
        .a16
        .i16
        .include "model.inc"
        .importzp __rg, __cbank
        .import _scale, _twice, __fpt
.if LARGE
        .import __icall
.endif
        FNADDR _twice                   ; __T_twice: twice's 16-bit address
        FNADDR _asm_op                  ; __T_asm_op

; int asm_sum(const int *v, int n): twice(v[0] * scale + ... + v[n-1] * scale)
        FUNC _asm_sum
        lda     ARGS,s
        sta     __rg+0                  ; v: a near pointer (the main bank, DBR)
        lda     ARGS+2,s
        beq     @none                   ; (a cheap local label after a CALL: still in scope)
        asl     a
        sta     __rg+2                  ; n * 2
        stz     __rg+4                  ; the sum
        ldy     #0
@loop:  cpy     __rg+2
        bcs     @done
        lda     (__rg+0),y
        jsr     times_scale             ; a subroutine in this segment: JSR is fine
        clc
        adc     __rg+4
        sta     __rg+4
        iny
        iny
        bra     @loop
@done:  pha                             ; twice(sum): a C function, wherever it is
        CALL    _twice
        ply
        RET
@none:  lda     #0                      ; twice(0)
        RET
times_scale:                            ; A * scale (0 <= scale), X changed
        sta     __rg+6
        lda     #0
        ldx     _scale                  ; a main-bank global: absolute, DBR
        beq     @z
@m:     clc
        adc     __rg+6
        dex
        bne     @m
@z:     rts

; int asm_op(int op, int a, int b): a jump table in the function's own segment
        FUNC _asm_op
        lda     ARGS,s
        cmp     #3
        bcs     @bad
        asl     a
        tax
        jmp     (@tab,x)                ; (abs,x): read in PBR's bank, this segment's
@tab:   .word   .loword(@add), .loword(@sub), .loword(@max)
@add:   lda     ARGS+2,s
        clc
        adc     ARGS+4,s
        RET
@sub:   lda     ARGS+2,s
        sec
        sbc     ARGS+4,s
        RET
@max:   lda     ARGS+2,s
        cmp     ARGS+4,s
        bpl     @a
        lda     ARGS+4,s
@a:     RET
@bad:   lda     #$FFFF
        RET

; int asm_apply(int (*f)(int), int x): f(x), through the pointer
        FUNC _asm_apply
        lda     ARGS+2,s                ; x
        pha
        lda     ARGS+2,s                ; f (one word pushed)
        sta     __fpt
.if LARGE
        CALL    __icall                 ; (JSL, its bank recorded)
.else
        ldx     #0
        jsr     (__fpt,x)
.endif
        ply
        RET

; int (*asm_twice_ptr(void))(int), int (*asm_op_ptr(void))(int, int, int)
        FUNC _asm_twice_ptr
        lda     #__T_twice
        RET
        FUNC _asm_op_ptr
        lda     #__T_asm_op
        RET

; unsigned asm_where(void): PBR << 8, | 1 when #^scale (patched by hcc's loader: XBANK)
; is the main bank's number (__cbank)
        FUNC _asm_where
        lda     #^_scale
        XBANK   2                       ; (16-bit A: the bank 2 bytes back)
        and     #$00FF
        cmp     __cbank
        php
        phk
        phk
        pla                             ; PBR in both bytes
        and     #$FF00
        plp
        bne     @x
        ora     #1
@x:     RET

; unsigned asm_main_bank(void)
        FUNC _asm_main_bank
        lda     __cbank
        RET
