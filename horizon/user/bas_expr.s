; bas_expr.s - expressions: precedence climbing over the token stream, the operators, the
; functions, number formatting and parsing.
;
; eval leaves the value in the accumulator (ft, flo, fhi, flen). A binary operator keeps
; its left operand (an integer on the hardware stack, else on the value stack vstk) and
; evaluates its right one with a higher minimum precedence (one table lookup per operator,
; no recursion per level):
;   1 OR XOR   2 AND   3 NOT (unary)   4 = <> < > <= >=   5 + -   6 * / \ MOD
;   7 unary -  8 ^ (right associative)
; Two integers: iopjt, 32-bit signed; a result that does not fit is computed again in
; floating point (iprom), / of integers gives an integer when it divides exactly, \ and MOD
; truncate toward zero. A float on either side: opjt (bas_fp.s); \ MOD AND OR XOR NOT
; round floats to integers. Comparisons give -1 (true) or 0; AND OR XOR NOT work on the
; bits, so they are logical on comparisons too. Strings: + joins, the comparisons compare
; bytes.
; The value stack and the accumulator are roots of the string garbage collector: a routine
; that allocates a string keeps the strings it still needs there (re-reading them after the
; allocation, which may move them).

        .segment "CODE"
        .a16
        .i16
VSMAX   = 48                            ; values on the value stack
STKMIN  = WIN_END + $0100              ; the hardware stack must stay above this (the window
                                        ; tables below it: basic.s, WIN_*)

; an expression -> acc
eval:   lda     #1
; ... of operators of precedence >= A
eval_p: pha
        jsr     unary
@op:    lda     [tp]
        and     #$00FF
        tax
        lda     prec,x
        and     #$00FF
        beq     @done
        cmp     1,s
        bcc     @done
        ldy     ft
        bne     @gen
        pei     (fhi)                   ; an integer on the left: on the hardware stack
        pei     (flo)
        phx
        inc     z:tp
        cmp     #8                      ; the right one: higher precedence (^: same)
        beq     :+
        inc     a
:       jsr     eval_p
        plx
        pla
        sta     z:il
        pla
        sta     z:ih
        lda     ft
        bne     @mix
        lda     opix,x                  ; integer op integer
        and     #$00FF
        asl     a
        tax
        jsr     (iopjt,x)
        bra     @op
@mix:   phx                             ; a float or a string on the right: the integer
        jsr     vpush_il                ; to the value stack
        plx
        bra     @call
@gen:   sta     z:t0                    ; a float or a string on the left: on the value
        phx                             ; stack (a root of the garbage collector)
        jsr     vpush
        inc     z:tp
        lda     z:t0
        cmp     #8
        beq     :+
        inc     a
:       jsr     eval_p
        plx
@call:  lda     opix,x
        and     #$00FF
        asl     a
        tax
        jsr     (opjt,x)
        bra     @op
@done:  pla
        rts

; acc -> the value stack
vpush:  ldx     vsp
        cpx     #VSMAX * 8
        bcc     :+
        err     E_EXPR
:       lda     ft
        sta     vstk,x
        lda     flo
        sta     vstk+2,x
        lda     fhi
        sta     vstk+4,x
        lda     flen
        sta     vstk+6,x
        txa
        clc
        adc     #8
        sta     vsp
        rts
; the integer il / ih -> the value stack
vpush_il:
        ldx     vsp
        cpx     #VSMAX * 8
        bcc     :+
        err     E_EXPR
:       stz     vstk,x
        lda     z:il
        sta     vstk+2,x
        lda     z:ih
        sta     vstk+4,x
        txa
        clc
        adc     #8
        sta     vsp
        rts
; the top of the value stack -> acc (popped)
vpop:   lda     vsp
        sec
        sbc     #8
        sta     vsp
        tax
        lda     vstk,x
        sta     ft
        lda     vstk+2,x
        sta     flo
        lda     vstk+4,x
        sta     fhi
        lda     vstk+6,x
        sta     flen
        rts

; ---------------------------------------------------------------- operands
unary:  tsc                             ; (every nesting comes through here)
        cmp     #STKMIN
        bcs     :+
        err     E_EXPR
:       lda     [tp]
        and     #$00FF
        cmp     #TK_NVAR
        bne     @nv
        ldy     #1                      ; a number variable (the most common case)
        lda     [tp],y
        tay
        lda     [vb],y
        sta     flo
        lda     [vb4],y
        sta     ft
        bne     @fv
        iny
        iny
        lda     [vb],y
        sta     fhi
        lda     z:tp
        clc
        adc     #3
        sta     z:tp
        rts
@fv:    iny                             ; (a float)
        iny
        lda     [vb],y
        sta     fhi
        lda     [vb4],y
        sta     flen
        lda     z:tp
        clc
        adc     #3
        sta     z:tp
        rts
@nv:    cmp     #TK_BYTE
        bne     :+
        ldy     #1
        lda     [tp],y
        and     #$00FF
        sta     flo
        stz     fhi
        stz     ft
        inc     z:tp
        inc     z:tp
        rts
:       cmp     #$80
        bcs     @tok
        inc     z:tp
        cmp     #'('
        bne     :+
        jsr     eval
        lda     #')'
        jmp     expect
:       cmp     #'-'
        bne     :+
        lda     #7
        jsr     eval_p
        jsr     need_num
        jmp     negacc
:       cmp     #'+'
        bne     :+
        lda     #7
        jsr     eval_p
        jmp     need_num
:       err     E_SYNTAX
@tok:   cmp     #TK_ABS
        bcc     @kw
        cmp     #TK_LASTKW + 1
        bcs     @spec
        inc     z:tp
        sec
        sbc     #TK_ABS
        asl     a
        tax
        jmp     (fntab,x)
@kw:    cmp     #TK_NOT
        jne     @syn
        inc     z:tp
        lda     #3
        jsr     eval_p
        jsr     need_num
        jsr     acc_round
        lda     flo
        eor     #$FFFF
        sta     flo
        lda     fhi
        eor     #$FFFF
        sta     fhi
        rts
@spec:  cmp     #TK_SVAR
        bne     :+
        ldy     #1                      ; a string variable
        lda     [tp],y
        tay
        lda     [vb],y
        sta     flo
        iny
        iny
        lda     [vb],y
        sta     fhi
        iny
        iny
        lda     [vb],y
        sta     flen
        lda     #T_STR
        sta     ft
        lda     z:tp
        clc
        adc     #3
        sta     z:tp
        rts
:       cmp     #TK_IVAR
        bne     :+
        ldy     #1                      ; an integer (%) variable
        lda     [tp],y
        tay
        lda     [vb],y
        sta     flo
        iny
        iny
        lda     [vb],y
        sta     fhi
        stz     ft
        lda     z:tp
        clc
        adc     #3
        sta     z:tp
        rts
:       cmp     #TK_NARR
        beq     @arr
        cmp     #TK_SARR
        beq     @arr
        cmp     #TK_IARR
        beq     @arr
        cmp     #TK_INT
        beq     @i32
        cmp     #TK_HEX
        beq     @i32
        cmp     #TK_FLT
        beq     @flt
        cmp     #TK_STRL
        bne     @syn
        ldy     #1                      ; a string literal: its bytes in the line
        lda     [tp],y
        and     #$00FF
        sta     flen
        lda     z:tp
        clc
        adc     #2
        sta     flo
        clc
        adc     flen
        sta     z:tp
        lda     z:tp+2
        sta     fhi
        lda     #T_STR
        sta     ft
        rts
@i32:   ldy     #1
        lda     [tp],y
        sta     flo
        ldy     #3
        lda     [tp],y
        sta     fhi
        stz     ft
        lda     z:tp
        clc
        adc     #5
        sta     z:tp
        rts
@flt:   ldy     #1                      ; a float literal {ft, flo, fhi, flen}
        lda     [tp],y
        sta     ft
        ldy     #3
        lda     [tp],y
        sta     flo
        ldy     #5
        lda     [tp],y
        sta     fhi
        ldy     #7
        lda     [tp],y
        sta     flen
        lda     z:tp
        clc
        adc     #9
        sta     z:tp
        rts
@arr:   jsr     lvalue                  ; an element: its address, then the value
        jmp     load_ap
@syn:   err     E_SYNTAX

; the value at ap of kind A (K_NUM, K_STR, K_INT, K_NA4) -> acc
load_ap:
        cmp     #K_NUM
        beq     @n
        cmp     #K_STR
        beq     @s
        lda     [ap]                    ; {lo, hi}
        sta     flo
        ldy     #2
        lda     [ap],y
        sta     fhi
        stz     ft
        rts
@n:     lda     [ap]                    ; {lo, hi, type, len}
        sta     flo
        ldy     #2
        lda     [ap],y
        sta     fhi
        ldy     #4
        lda     [ap],y
        sta     ft
        beq     :+
        ldy     #6
        lda     [ap],y
        sta     flen
:       rts
@s:     sta     ft
        lda     [ap]
        sta     flo
        ldy     #2
        lda     [ap],y
        sta     fhi
        ldy     #4
        lda     [ap],y
        sta     flen
        rts

; acc must be a number (Type mismatch)
need_num:
        lda     ft
        cmp     #T_STR
        beq     :+
        rts
:       err     E_TYPE

; acc = -acc
negacc: lda     ft
        beq     negate
        eor     #1                      ; a float: the sign bit
        sta     ft
        rts
; the integer acc negated (-2147483648: the float 2147483648)
negate: lda     flo
        eor     #$FFFF
        clc
        adc     #1
        sta     flo
        lda     fhi
        eor     #$FFFF
        adc     #0
        cmp     fhi
        bne     :+
        cmp     #$8000
        bne     :+
        ldx     flo
        bne     :+
        ldy     #.loword(c_2p31)
        jmp     ld_acc
:       sta     fhi
        rts

; ---------------------------------------------------------------- the lvalue
; the variable or element at tp -> ap = its place, A = its kind; tp past it:
;   K_NUM  a number variable, an element of a tagged number array: {lo, hi, type, len}
;   K_STR  a string {offset, bank, length}
;   K_INT  a % variable or element: an integer {lo, hi} (a float is rounded)
;   K_NA4  an element of a number array of integers {lo, hi}: a float stored in it makes
;          the array tagged first (arr_promote)
lvalue: lda     [tp]
        and     #$00FF
        cmp     #TK_NVAR
        jcc     @syn
        cmp     #TK_SARR + 1
        bcc     :+
        cmp     #TK_IVAR
        jcc     @syn
        cmp     #TK_IARR + 1
        jcs     @syn
:       sta     lv_tok
        ldy     #1
        lda     [tp],y
        sta     lv_off
        lda     z:tp
        clc
        adc     #3
        sta     z:tp
        lda     lv_tok
        cmp     #TK_NARR
        beq     @narr
        cmp     #TK_SARR
        beq     @sarr
        cmp     #TK_IARR
        beq     @iarr
        lda     lv_off                  ; a variable: its slot
        sta     z:ap
        lda     z:vb+2
        sta     z:ap+2
        lda     lv_tok
        cmp     #TK_SVAR
        beq     @s
        cmp     #TK_IVAR
        beq     @i
        lda     #K_NUM
        rts
@s:     lda     #K_STR
        rts
@i:     lda     #K_INT
        rts
@narr:  lda     lv_off
        ldx     #0
        jsr     arr_elem
        cmp     #8
        beq     :+
        lda     #K_NA4
        rts
:       lda     #K_NUM
        rts
@iarr:  lda     lv_off
        ldx     #0
        jsr     arr_elem
        lda     #K_INT
        rts
@sarr:  lda     lv_off
        ldx     #1
        jsr     arr_elem
        lda     #K_STR
        rts
@syn:   err     E_SYNTAX

; acc -> the target ap of kind A (Type mismatch). A string from our own bank (a direct
; command's literal, CHR$, an input line) is copied into the heap first.
assign: cmp     #K_NA4
        bne     :+
        ldx     ft                      ; (an element of an integer array: the common case)
        jne     @na4f
        lda     flo
        sta     [ap]
        ldy     #2
        lda     fhi
        sta     [ap],y
        rts
:       cmp     #K_STR
        beq     @str
        ldx     ft
        cpx     #T_STR
        beq     @mism
        cmp     #K_NUM
        bne     @int
@num:   lda     flo
        sta     [ap]
        ldy     #2
        lda     fhi
        sta     [ap],y
        ldy     #4
        txa
        sta     [ap],y
        beq     :+
        ldy     #6
        lda     flen
        sta     [ap],y
:       rts
@int:   txa
        beq     @st4
        jsr     acc_round
@st4:   lda     flo
        sta     [ap]
        ldy     #2
        lda     fhi
        sta     [ap],y
        rts
@str:   lda     ft
        cmp     #T_STR
        bne     @mism
        lda     flen
        beq     @set
        lda     fhi
        cmp     codebk
        bne     @set
        pei     (ap+2)
        pei     (ap)
        jsr     str_dup
        pla
        sta     z:ap
        pla
        sta     z:ap+2
@set:   lda     flo
        sta     [ap]
        ldy     #2
        lda     fhi
        sta     [ap],y
        ldy     #4
        lda     flen
        sta     [ap],y
        rts
@mism:  err     E_TYPE
@na4f:  cpx     #T_STR
        beq     @mism
        pei     (ap+2)                  ; a float: a whole number is stored as an integer,
        pei     (ap)                    ; else the array becomes tagged (-> ap)
        jsr     fp_demote
        pla
        sta     z:ap
        pla
        sta     z:ap+2
        ldx     ft
        jeq     @st4
        jsr     arr_promote
        ldx     ft
        jmp     @num

; ---------------------------------------------------------------- operators
; (the left operand is the value stack's top, the right one acc; result in acc; at least
; one of them is not an integer)
; X = the top's offset (not popped yet)
optop:  lda     vsp
        sec
        sbc     #8
        tax
        rts
; numbers: the left one (popped) -> FA, the right one -> FB (Type mismatch for a string)
fp_ops: jsr     optop
        stx     vsp
        lda     vstk,x
        cmp     #T_STR
        beq     mism
        lda     ft
        cmp     #T_STR
        beq     mism
        txa
        clc
        adc     #.loword(vstk)
        pha
        ldx     #FBX
        jsr     fp_unp
        ply
        ldx     #FAX
        jmp     fp_unpm
; both rounded to integers: the left one (popped) -> il / ih, the right one -> flo / fhi
int_ops:
        jsr     need_num
        jsr     acc_round
        pei     (flo)
        pei     (fhi)
        jsr     vpop
        jsr     need_num
        jsr     acc_round
        lda     flo
        sta     z:il
        lda     fhi
        sta     z:ih
        pla
        sta     fhi
        pla
        sta     flo
        rts

op_add: jsr     optop
        lda     vstk,x
        cmp     #T_STR
        bne     :+
        cmp     ft
        bne     mism
        jmp     concat
:       jsr     fp_ops
        jsr     fp_add
        jmp     fp_pack
ovf:    err     E_OVF
mism:   err     E_TYPE
op_sub: jsr     fp_ops
        jsr     fp_sub
        jmp     fp_pack
op_mul: jsr     fp_ops
        jsr     fp_mul
        jmp     fp_pack
op_div: jsr     fp_ops
        jsr     fp_div
        jmp     fp_pack
op_pow: jsr     fp_ops
        jsr     fp_pow
        jmp     fp_pack
op_and: jsr     int_ops
        jmp     iop_and
op_or:  jsr     int_ops
        jmp     iop_or
op_xor: jsr     int_ops
        jmp     iop_xor
op_mod: jsr     int_ops
        jmp     iop_mod
op_idiv:
        jsr     int_ops
        jmp     iop_idiv

; ---- integers: the left operand in il / ih, the right one in acc (result in acc). A
; result beyond 32 bits: the operation again in floats.
; FA = il / ih, FB = acc
iprom:  ldx     #FBX
        jsr     fp_unp
        lda     z:il
        sta     z:fw
        lda     z:ih
        sta     z:fw+2
        ldx     #FAX
        jmp     fp_i2fw
iop_add:
        clc
        lda     z:il
        adc     flo
        sta     flo
        lda     z:ih
        adc     fhi
        sta     fhi
        bvs     :+
        rts
:       sec                             ; (the right operand back)
        lda     flo
        sbc     z:il
        sta     flo
        lda     fhi
        sbc     z:ih
        sta     fhi
        jsr     iprom
        jsr     fp_add
        jmp     fp_pack
iop_sub:
        sec
        lda     z:il
        sbc     flo
        sta     flo
        lda     z:ih
        sbc     fhi
        sta     fhi
        bvs     :+
        rts
:       sec
        lda     z:il
        sbc     flo
        sta     flo
        lda     z:ih
        sbc     fhi
        sta     fhi
        jsr     iprom
        jsr     fp_sub
        jmp     fp_pack
iop_and:
        lda     z:il
        and     flo
        sta     flo
        lda     z:ih
        and     fhi
        sta     fhi
        rts
iop_or: lda     z:il
        ora     flo
        sta     flo
        lda     z:ih
        ora     fhi
        sta     fhi
        rts
iop_xor:
        lda     z:il
        eor     flo
        sta     flo
        lda     z:ih
        eor     fhi
        sta     fhi
        rts
iop_mul:
        lda     z:il
        sta     m_a
        lda     z:ih
        sta     m_a+2
        lda     flo
        sta     m_b
        lda     fhi
        sta     m_b+2
        jsr     smul32
        bcs     :+
        lda     m_r
        sta     flo
        lda     m_r+2
        sta     fhi
        rts
:       jsr     iprom
        jsr     fp_mul
        jmp     fp_pack
; a / b: an integer if b divides a, else a float
iop_div:
        lda     flo
        sta     dv_r
        lda     fhi
        sta     dv_r+2
        jsr     idivpre
        bcs     :+
        lda     m_a
        ora     m_a+2
        bne     :+
        jmp     div_q
:       lda     dv_r
        sta     flo
        lda     dv_r+2
        sta     fhi
        jsr     iprom
        jsr     fp_div
        jmp     fp_pack
; a \ b: the quotient truncated toward 0
iop_idiv:
        jsr     idivpre
        bcs     :+
        jmp     div_q
:       ldy     #.loword(c_2p31)        ; (-2147483648 \ -1)
        jmp     ld_acc
iop_mod:
        jsr     idivpre
div_r:  lda     m_a                     ; the remainder: the dividend's sign
        sta     flo
        lda     m_a+2
        sta     fhi
        lda     m_neg
        and     #2
        beq     :+
        jsr     negate
:       rts
div_q:  lda     m_r                     ; the quotient
        sta     flo
        lda     m_r+2
        sta     fhi
        bmi     :+                      ; (-2147483648: already right)
        lda     m_neg                   ; signs differ: negative
        and     #1
        beq     :+
        jsr     negate
:       rts
; |il ih| / |acc| -> m_r quotient, m_a remainder; m_neg bit 0: signs differ, bit 1: the
; dividend is negative. Division by zero; C set: the quotient is 2147483648.
idivpre:
        lda     flo
        ora     fhi
        bne     :+
        err     E_DIV0
:       stz     m_neg
        lda     z:il
        sta     m_a
        lda     z:ih
        sta     m_a+2
        bpl     :+
        lda     #3
        sta     m_neg
        jsr     m_nega
:       lda     flo
        sta     m_b
        lda     fhi
        sta     m_b+2
        bpl     :+
        lda     m_neg
        eor     #1
        sta     m_neg
        jsr     m_negb
:       jsr     udiv32
        lda     m_r+2                   ; (2147483648 as a positive quotient)
        bpl     :+
        lda     m_neg
        and     #1
        bne     :+
        sec
        rts
:       clc
        rts

; A ^ B: B >= 0 by squarings; B < 0: 1 ^ B = 1, -1 ^ B = +-1, else a float
iop_pow:
        lda     z:il
        sta     pw_b
        lda     z:ih
        sta     pw_b+2
        lda     fhi
        bpl     @pos
        lda     pw_b+2                  ; a negative exponent
        bne     @negb
        lda     pw_b
        cmp     #1
        beq     @one
@flt:   jsr     iprom
        jsr     fp_pow
        jmp     fp_pack
@negb:  cmp     #$FFFF
        bne     @flt
        lda     pw_b
        cmp     #$FFFF
        bne     @flt
        lda     flo                     ; -1 ^ odd = -1
        lsr     a
        bcc     @one
        lda     #$FFFF
        sta     flo
        sta     fhi
        rts
@one:   lda     #1
        sta     flo
        stz     fhi
        rts
@pos:   lda     flo
        sta     pw_e
        lda     fhi
        sta     pw_e+2
        lda     #1                      ; r = 1; while e: if e & 1: r *= b; b *= b
        sta     pw_r
        stz     pw_r+2
@l:     lda     pw_e
        ora     pw_e+2
        beq     @done
        lda     pw_e
        lsr     a
        bcc     @sq
        lda     pw_r
        sta     m_a
        lda     pw_r+2
        sta     m_a+2
        lda     pw_b
        sta     m_b
        lda     pw_b+2
        sta     m_b+2
        jsr     smul32
        bcs     @flt
        lda     m_r
        sta     pw_r
        lda     m_r+2
        sta     pw_r+2
@sq:    lsr     pw_e+2
        ror     pw_e
        lda     pw_e
        ora     pw_e+2
        beq     @done
        lda     pw_b
        sta     m_a
        sta     m_b
        lda     pw_b+2
        sta     m_a+2
        sta     m_b+2
        jsr     smul32
        jcs     @flt
        lda     m_r
        sta     pw_b
        lda     m_r+2
        sta     pw_b+2
        bra     @l
@done:  lda     pw_r
        sta     flo
        lda     pw_r+2
        sta     fhi
        rts
iop_eq: lda     #2
        bra     icmp
iop_ne: lda     #5
        bra     icmp
iop_lt: lda     #1
        bra     icmp
iop_gt: lda     #4
        bra     icmp
iop_le: lda     #3
        bra     icmp
iop_ge: lda     #6
icmp:   sta     z:t1
        lda     z:il
        cmp     flo
        bne     @ne
        lda     z:ih
        cmp     fhi
        bne     @ne
        lda     #2
        bra     @res
@ne:    lda     z:il
        cmp     flo
        lda     z:ih
        sbc     fhi
        bvc     :+
        eor     #$8000
:       bmi     :+
        lda     #4
        bra     @res
:       lda     #1
@res:   and     z:t1
        beq     :+
        lda     #$FFFF
:       sta     flo
        sta     fhi
        rts

; comparisons: A = the relation's bits (1 less, 2 equal, 4 greater) that make it true
op_eq:  lda     #2
        bra     cmpop
op_ne:  lda     #5
        bra     cmpop
op_lt:  lda     #1
        bra     cmpop
op_gt:  lda     #4
        bra     cmpop
op_le:  lda     #3
        bra     cmpop
op_ge:  lda     #6
cmpop:  sta     z:t1
        jsr     optop
        lda     vstk,x
        cmp     #T_STR
        bne     @num
        cmp     ft
        jne     mism
        jsr     strcmp                  ; -> A = 1, 2, 4 (pops)
        bra     @res
@num:   jsr     fp_ops
        jsr     fp_cmp
@res:   and     z:t1
        beq     :+
        lda     #$FFFF
:       sta     flo
        sta     fhi
        stz     ft
        rts

; the strings: top (left) and acc (right) -> A = 1 less, 2 equal, 4 greater; popped
strcmp: jsr     optop
        stx     vsp
        lda     vstk+2,x
        sta     z:bp
        lda     vstk+4,x
        sta     z:bp+2
        lda     vstk+6,x
        sta     z:t2                    ; left length
        lda     flo
        sta     z:cp
        lda     fhi
        sta     z:cp+2
        ldy     #0
@l:     cpy     z:t2
        beq     @lend
        cpy     flen
        beq     @gt                     ; right ended first
        lda     [bp],y
        and     #$00FF
        sta     z:t3
        lda     [cp],y
        and     #$00FF
        cmp     z:t3
        bcc     @gt                     ; right < left
        bne     @lt
        iny
        bra     @l
@lend:  cpy     flen
        beq     :+
@lt:    lda     #1
        rts
:       lda     #2
        rts
@gt:    lda     #4
        rts

; left + right (strings): a new string
concat: lda     vstk+6,x
        clc
        adc     flen
        cmp     #256
        bcc     :+
        err     E_STRLEN
:       sta     z:t5
        lda     flen                    ; an empty side: the other one
        bne     :+
        jmp     vpop
:       lda     vstk+6,x
        bne     :+
        stx     vsp
        rts
:       lda     z:t5
        jsr     str_alloc               ; -> ap (may move both)
        jsr     optop
        lda     vstk+2,x
        sta     z:bp
        lda     vstk+4,x
        sta     z:bp+2
        ldy     #0
        lda     vstk+6,x
        sta     z:t6
        a8
:       cpy     z:t6
        bcs     :+
        lda     [bp],y
        sta     [ap],y
        iny
        bra     :-
:       a16
        tya
        clc
        adc     z:ap
        sta     z:cp                    ; (the right part goes after it)
        lda     z:ap+2
        sta     z:cp+2
        lda     flo
        sta     z:bp
        lda     fhi
        sta     z:bp+2
        ldy     #0
        a8
:       cpy     flen
        bcs     :+
        lda     [bp],y
        sta     [cp],y
        iny
        bra     :-
:       a16
        stx     vsp
        jmp     acc_ap

; acc = the new string at ap of length t5
acc_ap: lda     z:ap
        sta     flo
        lda     z:ap+2
        sta     fhi
        lda     z:t5
        sta     flen
        lda     #T_STR
        sta     ft
        rts

; a copy of the string in acc in the heap (acc then points at it)
str_dup:
        lda     flen
        sta     z:t5
        jsr     str_alloc
        lda     flo
        sta     z:bp
        lda     fhi
        sta     z:bp+2
        ldy     #0
        a8
:       cpy     flen
        bcs     :+
        lda     [bp],y
        sta     [ap],y
        iny
        bra     :-
:       a16
        jmp     acc_ap

; ---------------------------------------------------------------- arithmetic
; m_r = m_a * m_b (signed 32-bit) -> C set on overflow
smul32: stz     m_sgn
        lda     m_a+2
        bpl     :+
        inc     m_sgn
        jsr     m_nega
:       lda     m_b+2
        bpl     :+
        lda     m_sgn
        eor     #1
        sta     m_sgn
        jsr     m_negb
:       lda     m_a+2                   ; both above 16 bits: too big
        beq     :+
        ldx     m_b+2
        bne     @ovf
:       lda     m_a                     ; lo * lo
        ldx     m_b
        jsr     umul16
        sta     m_r
        stx     m_r+2
        lda     m_a+2                   ; + (hi * lo) << 16
        beq     :+
        ldx     m_b
        bra     @cross
:       lda     m_b+2
        beq     @sign
        ldx     m_a
@cross: jsr     umul16
        cpx     #0
        bne     @ovf
        clc
        adc     m_r+2
        bcs     @ovf
        sta     m_r+2
@sign:  lda     m_r+2                   ; at most 2147483647 (2147483648 if negative)
        bpl     :+
        cmp     #$8000
        bne     @ovf
        lda     m_r
        bne     @ovf
        lda     m_sgn
        beq     @ovf
:       lda     m_sgn
        beq     :+
        lda     m_r
        eor     #$FFFF
        clc
        adc     #1
        sta     m_r
        lda     m_r+2
        eor     #$FFFF
        adc     #0
        sta     m_r+2
:       clc
        rts
@ovf:   sec
        rts

; A * X (unsigned 16-bit) -> A low, X high. Shift-and-add over the smaller factor's bits
; (a loop per bit up to its highest one: 3 * N takes two).
umul16: stx     mu_b
        cmp     mu_b
        bcs     :+
        sta     mu_b                    ; (the smaller one shifts)
        txa
:       sta     mu_a
        stz     mu_ah
        stz     mu_r
        stz     mu_rh
@l:     lda     mu_b
        beq     @done
        lsr     mu_b
        bcc     :+
        clc
        lda     mu_r
        adc     mu_a
        sta     mu_r
        lda     mu_rh
        adc     mu_ah
        sta     mu_rh
:       asl     mu_a
        rol     mu_ah
        bra     @l
@done:  lda     mu_r
        ldx     mu_rh
        rts

m_nega: lda     m_a
        eor     #$FFFF
        clc
        adc     #1
        sta     m_a
        lda     m_a+2
        eor     #$FFFF
        adc     #0
        sta     m_a+2
        rts
m_negb: lda     m_b
        eor     #$FFFF
        clc
        adc     #1
        sta     m_b
        lda     m_b+2
        eor     #$FFFF
        adc     #0
        sta     m_b+2
        rts

; m_a / m_b (unsigned 32-bit, m_b != 0) -> m_r quotient, m_a remainder
udiv32: lda     m_a+2                   ; both 16-bit: the short way
        ora     m_b+2
        bne     @long
        stz     m_r+2
        lda     m_a
        sta     m_r
        lda     #0
        ldx     #16
@s:     asl     m_r
        rol     a
        bcs     :+
        cmp     m_b
        bcc     :++
:       sbc     m_b
        inc     m_r
:       dex
        bne     @s
        sta     m_a
        stz     m_a+2
        rts
@long:  lda     m_b+2                   ; a 16-bit divisor: two 16-bit steps
        bne     @full
        lda     m_a+2                   ; the high word: below the divisor (the usual
        cmp     m_b                     ; case): no quotient there
        bcs     @hi
        stz     m_r+2
        bra     @lo
@hi:    sta     m_r+2                   ; high / divisor
        lda     #0
        ldx     #16
@h:     asl     m_r+2
        rol     a
        bcs     :+
        cmp     m_b
        bcc     :++
:       sbc     m_b
        inc     m_r+2
:       dex
        bne     @h
@lo:    ldx     m_a                     ; (remainder : low word) / divisor
        stx     m_r
        ldx     #16
@m:     asl     m_r
        rol     a
        bcs     :+
        cmp     m_b
        bcc     :++
:       sbc     m_b
        inc     m_r
:       dex
        bne     @m
        sta     m_a
        stz     m_a+2
        rts
@full:  lda     m_a
        sta     m_r
        lda     m_a+2
        sta     m_r+2
        stz     m_a
        stz     m_a+2
        ldx     #32
@l:     asl     m_r
        rol     m_r+2
        rol     m_a
        rol     m_a+2
        lda     m_a
        sec
        sbc     m_b
        tay
        lda     m_a+2
        sbc     m_b+2
        bcc     :+
        sta     m_a+2
        sty     m_a
        inc     m_r
:       dex
        bne     @l
        rts

; ---------------------------------------------------------------- numbers <-> text
; acc (a number) -> X = its text (numbuf), A = its length
fmt_num:
        lda     ft
        beq     fmt_int
        lda     #10
        jmp     fp_fmt
; flo, fhi (signed) -> X = the decimal text (numbuf), A = its length
fmt_int:
        lda     flo
        sta     m_a
        lda     fhi
        sta     m_a+2
        ldy     #0
        lda     m_a+2
        bpl     :+
        jsr     m_nega
        lda     #'-'
        sta     numbuf
        iny
:       stz     fm_any                  ; a digit written (no leading zeros)
        ldx     #0                      ; powers of ten from 10^9
@p:     lda     #'0'
        sta     fm_d
@sub:   lda     m_a                     ; m_a -= 10^k while it fits
        sec
        sbc     pow10,x
        sta     m_b
        lda     m_a+2
        sbc     pow10+2,x
        bcc     @dig
        sta     m_a+2
        lda     m_b
        sta     m_a
        inc     fm_d
        bra     @sub
@dig:   lda     fm_d
        cmp     #'0'
        bne     :+
        lda     fm_any
        beq     @skip
:       lda     fm_d
        sta     numbuf,y
        iny
        inc     fm_any
@skip:  inx
        inx
        inx
        inx
        cpx     #9 * 4
        bcc     @p
        lda     m_a                     ; the last digit
        clc
        adc     #'0'
        sta     numbuf,y
        iny
        lda     #0
        sta     numbuf,y
        tya
        ldx     #.loword(numbuf)
        rts

; flo, fhi (unsigned) -> X = the hex text (no leading zeros), A = its length
fmt_hex:
        ldy     #0
        stz     fm_any
        ldx     #28                     ; shift of the digit
@l:     lda     flo
        sta     fm_d
        lda     fhi
        sta     fm_h
        txa
        beq     @d
        phx
:       lsr     fm_h
        ror     fm_d
        dex
        bne     :-
        plx
@d:     lda     fm_d
        and     #$000F
        bne     :+
        lda     fm_any
        bne     :+
        cpx     #0
        bne     @n
:       inc     fm_any
        lda     fm_d
        and     #$000F
        cmp     #10
        bcc     :+
        adc     #6
:       adc     #'0'
        sta     numbuf,y
        iny
@n:     txa
        sec
        sbc     #4
        tax
        bpl     @l
        lda     #0
        sta     numbuf,y
        tya
        ldx     #.loword(numbuf)
        rts

; a number at bp (at most A characters): spaces, a sign, then $hex / &Hhex, or decimal
; digits, a fraction, an exponent (E-5) -> acc (an integer if it is a whole number of 32
; bits, else a float; Overflow beyond 1E+100), Y = characters used; C set: no number
parse_num:
        sta     pn_max
        stz     pn_neg
        stz     m_a
        stz     m_a+2
        ldy     #0
:       jsr     @ch
        cmp     #' '
        bne     :+
        iny
        bra     :-
:       cmp     #'-'
        bne     :+
        inc     pn_neg
        iny
        bra     @num
:       cmp     #'+'
        bne     @num
        iny
@num:   sty     pn_st
        jsr     @ch
        cmp     #'$'
        beq     @hex
        cmp     #'&'
        bne     @dec
        iny
        jsr     @ch
        and     #$00DF
        cmp     #'H'
        jne     @no
@hex:   iny
        stz     pn_cnt
:       jsr     @ch
        jsr     tk_ishex
        jcc     @end
        sta     pn_d
        lda     m_a+2
        and     #$F000
        jne     @no
        ldx     #4
@sh:    asl     m_a
        rol     m_a+2
        dex
        bne     @sh
        lda     pn_d
        ora     m_a
        sta     m_a
        inc     pn_cnt
        iny
        bra     :-
@flt:   ldy     pn_st                   ; a fraction, an exponent or a large number
        jmp     fp_parse
@dec:   stz     pn_cnt
:       jsr     @ch
        jsr     tk_isdigit
        bcc     @end
        sbc     #'0'
        sta     pn_d
        lda     m_a                     ; m_a = m_a * 10 + d
        sta     m_b
        lda     m_a+2
        sta     m_b+2
        asl     m_a                     ; * 4 + 1 = * 5
        rol     m_a+2
        bcs     @flt
        asl     m_a
        rol     m_a+2
        bcs     @flt
        lda     m_a
        clc
        adc     m_b
        sta     m_a
        lda     m_a+2
        adc     m_b+2
        sta     m_a+2
        bcs     @flt
        asl     m_a                     ; * 10
        rol     m_a+2
        bcs     @flt
        lda     m_a
        clc
        adc     pn_d
        sta     m_a
        lda     m_a+2
        adc     #0
        sta     m_a+2
        bmi     @flt
        inc     pn_cnt
        iny
        bra     :-
@end:   cmp     #'.'
        beq     @flt
        and     #$00DF
        cmp     #'E'
        bne     :+
        lda     pn_cnt
        beq     :+
        jsr     pn_isexp
        jcs     @flt
:       lda     pn_cnt
        beq     @no
        lda     m_a
        sta     flo
        lda     m_a+2
        sta     fhi
        stz     ft
        lda     pn_neg
        beq     :+
        phy
        jsr     negate
        ply
:       clc
        rts
@no:    sec
        rts
; the character at bp + Y (0 past the end)
@ch:    cpy     pn_max
        bcs     :+
        lda     [bp],y
        and     #$00FF
        rts
:       lda     #0
        rts

; ---------------------------------------------------------------- functions
; (entered with tp after the function's token)
; "(" a number ")" -> flo, fhi
arg1:   lda     #'('
        jsr     expect
        jsr     eval_int
        lda     #')'
        jmp     expect
; "(" a string ")"
arg1s:  lda     #'('
        jsr     expect
        jsr     eval_str
        lda     #')'
        jmp     expect
; an optional "()" after TIME, FRE ...
noargs: jsr     peek
        cmp     #'('
        bne     :+
        jsr     arg1
:       rts
; acc = the int A (low), X (high)
ret_int:
        sta     flo
        stx     fhi
        stz     ft
        rts
; acc = the 16-bit unsigned A
ret_u16:
        ldx     #0
        bra     ret_int

f_abs:  jsr     arg1n
        lda     ft
        beq     :+
        and     #$FFFE                  ; a float: the sign bit off
        sta     ft
        rts
:       lda     fhi
        bpl     :+
        jmp     negate
:       rts
f_sgn:  jsr     arg1n
        lda     ft
        beq     :+
        lsr     a                       ; a float: never 0
        bcs     @neg
        lda     #1
        bra     :++
:       lda     fhi
        bmi     @neg
        ora     flo
        beq     :+
        lda     #1
:       ldx     #0
        jmp     ret_int
@neg:   lda     #$FFFF
        tax
        jmp     ret_int

; RND(n): 0 .. n-1 (xorshift32); RND or RND(1): a float 0 <= x < 1 (12 random digits)
f_rnd:  jsr     peek
        cmp     #'('
        bne     @flt
        jsr     arg1
        lda     fhi
        bmi     @bad
        bne     :+
        lda     flo
        beq     @bad
        cmp     #1
        beq     @flt
:       jsr     rnd32
        lda     rseed                   ; (31 bits) mod n
        sta     m_a
        lda     rseed+2
        and     #$7FFF
        sta     m_a+2
        lda     flo
        sta     m_b
        lda     fhi
        sta     m_b+2
        jsr     udiv32
        lda     m_a
        ldx     m_a+2
        jmp     ret_int
@bad:   err     E_ARG
@flt:   stz     rn_i
:       jsr     rnd32                   ; two digits from each 32 random bits:
        lda     rseed                   ; (16 bits * 10) >> 16
        ldx     #10
        jsr     umul16
        txa
        ldx     rn_i
        sta     qd,x
        inc     rn_i
        lda     rseed+2
        ldx     #10
        jsr     umul16
        txa
        ldx     rn_i
        sta     qd,x
        inc     rn_i
        lda     rn_i
        cmp     #12
        bcc     :-
        stz     qd+12
        stz     qd+14
        ldx     #0
        jsr     qd_fa
        stz     fa_e
        stz     fa_s
        ldx     #FAX
        jsr     fp_normx
        jmp     fp_pack
rnd32:  lda     rseed                   ; x ^= x << 13; x ^= x >> 17; x ^= x << 5
        sta     z:t0
        lda     rseed+2
        sta     z:t1
        ldx     #13
:       asl     z:t0
        rol     z:t1
        dex
        bne     :-
        jsr     @mix
        lda     rseed+2                 ; >> 17: the high word >> 1
        lsr     a
        sta     z:t0
        stz     z:t1
        jsr     @mix
        lda     rseed
        sta     z:t0
        lda     rseed+2
        sta     z:t1
        ldx     #5
:       asl     z:t0
        rol     z:t1
        dex
        bne     :-
@mix:   lda     rseed
        eor     z:t0
        sta     rseed
        lda     rseed+2
        eor     z:t1
        sta     rseed+2
        rts

f_len:  jsr     arg1s
        lda     flen
        jmp     ret_u16

f_asc:  jsr     arg1s
        lda     flen
        bne     :+
        err     E_ARG
:       lda     flo
        sta     z:bp
        lda     fhi
        sta     z:bp+2
        lda     [bp]
        and     #$00FF
        jmp     ret_u16

f_val:  jsr     arg1s
        lda     flo
        sta     z:bp
        lda     fhi
        sta     z:bp+2
        lda     flen
        jsr     parse_num
        bcc     :+
        lda     #0
        tax
        jmp     ret_int
:       rts

f_chr:  jsr     arg1
        lda     fhi
        bne     :+
        lda     flo
        cmp     #256
        bcc     chr_acc
:       err     E_ARG
; acc = the one-character string A (from the table: no allocation)
chr_acc:
        clc
        adc     #.loword(chrtab)
        sta     flo
        lda     codebk
        sta     fhi
        lda     #1
        sta     flen
        lda     #T_STR
        sta     ft
        rts

; the empty string
empty_acc:
        stz     flo
        stz     fhi
        stz     flen
        lda     #T_STR
        sta     ft
        rts

f_str:  jsr     arg1n
        jsr     fmt_num
        bra     numstr
f_hex:  jsr     arg1
        jsr     fmt_hex
; the text X (numbuf), length A -> a heap string in acc
numstr: sta     z:t5
        jsr     str_alloc
        ldy     #0
        a8
:       lda     numbuf,y
        sta     [ap],y
        iny
        cpy     z:t5
        bcc     :-
        a16
        jmp     acc_ap

; LEFT$(s, n), RIGHT$(s, n)
f_left: lda     #0
        bra     :+
f_right:
        lda     #1
:       pha
        lda     #'('
        jsr     expect
        jsr     eval_str
        jsr     vpush
        lda     #','
        jsr     expect
        jsr     eval_int
        lda     #')'
        jsr     expect
        lda     fhi
        bmi     @bad
        bne     @all
        jsr     optop
        lda     flo
        cmp     vstk+6,x
        bcs     @all
        sta     z:t5                    ; the count
        pla
        beq     :+
        lda     vstk+6,x                ; RIGHT$: from len - n
        sec
        sbc     z:t5
:       sta     z:t4                    ; the start
        jmp     substr
@all:   pla
        jmp     vpop
@bad:   err     E_ARG

; MID$(s, start [, n])
f_mid:  lda     #'('
        jsr     expect
        jsr     eval_str
        jsr     vpush
        lda     #','
        jsr     expect
        jsr     eval_int
        lda     fhi
        bne     @bad
        lda     flo
        beq     @bad
        jsr     vpush
        lda     #255                    ; n: all
        sta     flo
        stz     fhi
        jsr     peek
        cmp     #','
        bne     :+
        inc     z:tp
        jsr     eval_int
        lda     fhi
        bmi     @bad
        beq     :+
        lda     #255
        sta     flo
:       lda     #')'
        jsr     expect
        jsr     optop                   ; the start
        stx     vsp
        lda     vstk+2,x
        dec     a
        sta     z:t4
        jsr     optop                   ; the string
        lda     vstk+6,x
        sec
        sbc     z:t4                    ; characters from start
        bcs     :+
        lda     #0
:       cmp     flo
        bcc     :+
        lda     flo
:       sta     z:t5
        cmp     vstk+6,x                ; all of it: the same string
        bne     substr
        jmp     vpop
@bad:   err     E_ARG

; the string on the value stack's top: t5 characters from t4 -> a new string (popped)
substr: lda     z:t5
        bne     :+
        jsr     vpop
        jmp     empty_acc
:       pei     (t4)
        lda     z:t5
        jsr     str_alloc               ; (may move the string)
        pla
        sta     z:t4
        jsr     optop
        stx     vsp
        lda     vstk+2,x
        clc
        adc     z:t4
        sta     z:bp
        lda     vstk+4,x
        sta     z:bp+2
        ldy     #0
        a8
:       lda     [bp],y
        sta     [ap],y
        iny
        cpy     z:t5
        bcc     :-
        a16
        jmp     acc_ap

; INSTR([start,] s, t): the position of t in s from start (1-based), 0 if none
f_instr:
        lda     #'('
        jsr     expect
        lda     #1
        sta     in_start
        jsr     eval
        lda     ft
        cmp     #T_STR
        beq     :+
        jsr     acc_round
        lda     fhi                     ; a start
        jne     @bad
        lda     flo
        jeq     @bad
        sta     in_start
        lda     #','
        jsr     expect
        jsr     eval_str
:       jsr     vpush
        lda     #','
        jsr     expect
        jsr     eval_str
        lda     #')'
        jsr     expect
        jsr     optop
        stx     vsp
        lda     vstk+2,x
        sta     z:bp
        lda     vstk+4,x
        sta     z:bp+2
        lda     vstk+6,x
        sta     z:t2                    ; s length
        lda     flo
        sta     z:cp
        lda     fhi
        sta     z:cp+2
        lda     in_start
        dec     a
        sta     z:t3                    ; the position tried
@try:   lda     z:t3
        clc
        adc     flen
        cmp     z:t2
        beq     :+
        bcs     @none
:       ldy     #0
        lda     z:bp
        clc
        adc     z:t3
        sta     z:dp
        lda     z:bp+2
        sta     z:dp+2
@c:     cpy     flen
        beq     @hit
        lda     [dp],y
        and     #$00FF
        sta     z:t4
        lda     [cp],y
        and     #$00FF
        cmp     z:t4
        bne     @next
        iny
        bra     @c
@next:  inc     z:t3
        bra     @try
@hit:   lda     z:t3
        inc     a
        jmp     ret_u16
@none:  lda     #0
        jmp     ret_u16
@bad:   err     E_ARG

f_peek: jsr     arg1
        lda     fhi
        bne     @bad
        jsr     kb_get
        ldy     flo
        lda     #0
        a8
        lda     [ep],y                  ; (8-bit: PEEK(65535) ends the bank)
        a16
        jmp     ret_u16
@bad:   err     E_ARG

f_time: jsr     noargs
        sys     SYS_UPTIME
        jmp     ret_int

f_inkey:
:       lda     #1
        jsr     pump
        bcc     :-
        lda     brkf
        jne     do_break
        jsr     kr_get
        bcs     :+
        jmp     chr_acc
:       jmp     empty_acc

f_mousex:
        ldx     #0
        bra     :+
f_mousey:
        ldx     #2
        bra     :+
f_mouseb:
        ldx     #4
:       phx
:       lda     #1                      ; (the events queued so far first: keys, Esc)
        jsr     pump
        bcc     :-
        lda     gwin                    ; the pointer now, in the graphics window (else in
        bpl     :+                      ; the console window)
        lda     win
:       ptr     mbuf
        sys     SYS_WMOUSE
        plx
        lda     fsact                   ; (2.0) full screen: the screen's (320 x 180: halved)
        beq     :++
        cpx     #4
        bcs     :++
        lda     mbuf,x
        ldy     fs_m
        cpy     #1
        bne     :+
        lsr     a
:       jmp     ret_s16
:       lda     mbuf+4,x                ; content x, y, buttons
        jmp     ret_s16
; acc = the signed 16-bit A
ret_s16:
        ldx     #0
        cmp     #$8000
        bcc     :+
        dex
:       jmp     ret_int

; (1.2) STICK(n), STRIG(n): joystick port n + 1 (n = 0, 1) as in Atari BASIC: STICK 15
; centred, the direction bits cleared (14 up, 13 down, 11 left, 7 right, and the diagonals:
; 10, 6, 9, 5); STRIG 0 while the trigger is pressed, else 1 (SYS_JOY)
f_stick:
        lda     #0
        bra     :+
f_strig:
        lda     #1
:       pha
        jsr     arg1
        lda     fhi
        bne     @bad
        lda     flo
        cmp     #2
        bcs     @bad
        pha
:       lda     #1                      ; (2.0: the events so far: the keys held)
        jsr     pump
        bcc     :-
        lda     #0
        sys     SYS_JOY                 ; A = directions, X = triggers
        ply                             ; the port
        bne     :+
        pha                             ; port 1: the arrows and Space too
        lda     kheld
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     z:t0
        txa
        ora     z:t0
        tax
        lda     kheld
        and     #$000F
        ora     1,s
        sta     1,s
        pla
:
        sta     z:t0
        lda     1,s                     ; STRIG?
        beq     :+
        txa                             ; the trigger: bit 0 port 1, bit 1 port 2
        cpy     #0
        beq     @tr
        lsr     a
@tr:    and     #1
        eor     #1
        bra     @out
:       lda     z:t0                    ; the directions: port 1 bits 0-3, port 2 4-7
        cpy     #0
        beq     :+
        lsr     a
        lsr     a
        lsr     a
        lsr     a
:       and     #$000F
        eor     #$000F
@out:   ply
        jmp     ret_u16
@bad:   err     E_ARG

f_fre:  jsr     noargs
        sys     SYS_MINFO               ; free banks * 65536
        tax
        lda     #0
        jmp     ret_int

; MIN(a, b), MAX(a, b)
f_min:  lda     #1
        bra     :+
f_max:  lda     #4
:       pha
        lda     #'('
        jsr     expect
        jsr     eval_num
        jsr     vpush
        lda     #','
        jsr     expect
        jsr     eval_num
        lda     #')'
        jsr     expect
        jsr     optop
        lda     vstk,x
        ora     ft
        beq     @int
        ldx     #FBX                    ; floats: left vs right
        jsr     fp_unp
        jsr     optop
        txa
        clc
        adc     #.loword(vstk)
        tay
        ldx     #FAX
        jsr     fp_unpm
        jsr     fp_cmp
        sta     z:t0
        jsr     optop
        lda     z:t0
        cmp     #1
        beq     @less
        pla
        cmp     #4
        beq     @left
        stx     vsp
        rts
@int:   jsr     optop                   ; left < right?
        lda     vstk+2,x
        cmp     flo
        lda     vstk+4,x
        sbc     fhi
        bvc     :+
        eor     #$8000
:       bmi     @less
        pla                             ; left >= right: MAX takes the left
        cmp     #4
        beq     @left
        stx     vsp
        rts
@less:  pla
        cmp     #1
        beq     @left
        stx     vsp
        rts
@left:  jmp     vpop

f_tab:  err     E_SYNTAX

        .segment "RODATA"
fntab:  .addr   f_abs, f_sgn, f_rnd, f_len, f_left, f_right, f_mid, f_chr
        .addr   f_asc, f_str, f_val, f_hex, f_instr, f_peek, f_time, f_inkey
        .addr   f_mousex, f_mousey, f_mouseb, f_point, f_tab, f_tab, f_fre, f_min
        .addr   f_max, f_sqr, f_sin, f_cos, f_tan, f_atn, f_exp, f_log
        .addr   f_log10, f_int, f_fix, f_round, f_pi, f_stick, f_strig, f_hit
        .addr   f_frame, f_note
; precedence of each token as a binary operator (0: not one)
prec:   .repeat 256, I
        .byte   ((I = TK_OR) | (I = TK_XOR)) * 1 + (I = TK_AND) * 2 + ((I = '=') | (I = '<') | (I = '>') | (I = TK_LE) | (I = TK_GE) | (I = TK_NE)) * 4 + ((I = '+') | (I = '-')) * 5 + ((I = '*') | (I = '/') | (I = TK_MOD) | (I = $5C)) * 6 + (I = '^') * 8
        .endrepeat
; the operator routine of each operator token (its index in opjt)
opix:   .repeat 256, I
        .byte   (I = '-') * 1 + (I = '*') * 2 + (I = '/') * 3 + (I = TK_MOD) * 4 + (I = '^') * 5 + (I = TK_AND) * 6 + (I = TK_OR) * 7 + (I = TK_XOR) * 8 + (I = '=') * 9 + (I = TK_NE) * 10 + (I = '<') * 11 + (I = '>') * 12 + (I = TK_LE) * 13 + (I = TK_GE) * 14 + (I = $5C) * 15
        .endrepeat
opjt:   .addr   op_add, op_sub, op_mul, op_div, op_mod, op_pow, op_and, op_or
        .addr   op_xor, op_eq, op_ne, op_lt, op_gt, op_le, op_ge, op_idiv
iopjt:  .addr   iop_add, iop_sub, iop_mul, iop_div, iop_mod, iop_pow, iop_and, iop_or
        .addr   iop_xor, iop_eq, iop_ne, iop_lt, iop_gt, iop_le, iop_ge, iop_idiv
pow10:  .dword  1000000000, 100000000, 10000000, 1000000, 100000, 10000, 1000, 100, 10
chrtab: .repeat 256, I
        .byte   I
        .endrepeat

        .segment "BSS"
vsp:    .res    2
vstk:   .res    VSMAX * 8 + 8
lv_tok: .res    2
lv_off: .res    2
dv_r:   .res    4
rn_i:   .res    2
pn_st:  .res    2
m_a:    .res    4
m_b:    .res    4
m_r:    .res    4
m_sgn:  .res    2
m_neg:  .res    2
mu_a:   .res    2
mu_ah:  .res    2
mu_b:   .res    2
mu_r:   .res    2
mu_rh:  .res    2
pw_b:   .res    4
pw_e:   .res    4
pw_r:   .res    4
pn_max: .res    2
pn_neg: .res    2
pn_cnt: .res    2
pn_d:   .res    2
in_start: .res  2
rseed:  .res    4
numbuf: .res    32
fm_d:   .res    2
fm_h:   .res    2
fm_any: .res    2
codebk: .res    2               ; our bank (code, data, direct commands)
