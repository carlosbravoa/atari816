; calc_eng.s - the Calculator's engine (included by calc.s): the state, one key at a time
; (calc_key), the display's strings (mkdisp), paste, and the self test (test_run).
;
; Standard: X (nx) is the number shown, or the text being typed (ebuf, while `entering`).
; A binary operation keeps X in the accumulator (nacc) with the operation (pendop); the next
; operation or = applies it once a new number was given (`fresh`: typed, recalled, or made by
; a function key), so 2 + 3 x 4 = gives 20 and 2 + x 4 = gives 8 (the last operation counts).
; = again repeats the last operation with the same second number (lastop, nlast).
; Programmer: the same with 32-bit integers (px, pacc, plast) typed in the base `base`.

        .segment "CODE"

; everything back to the start: Standard, decimal input base, memory empty
reset:  stz     mode
        lda     #10
        sta     base
        ldx     #.loword(nmem)
        jsr     n_zero
        ; fall through
; C: all but the memory and the mode
clrall: ldx     #.loword(nx)
        jsr     n_zero
        ldx     #.loword(nacc)
        jsr     n_zero
        stz     pendop
        stz     lastop
        stz     entering
        stz     fresh
        stz     err
        stz     px
        stz     px+2
        stz     pacc
        stz     pacc+2
        rts

; A = key code
calc_key:
        and     #$00FF
        sta     z:kc
        lda     err                     ; after an error: C, CE, Backspace clear it, a digit
        beq     @ok                     ; starts again, a change of view goes on; nothing else
        lda     z:kc
        cmp     #'C'
        beq     @clr
        cmp     #'E'
        beq     @clr
        cmp     #'B'
        beq     @clr
        cmp     #'V'
        beq     @clr2
        cmp     #'W'
        beq     @clr2
        cmp     #'.'
        beq     @clr2
        jsr     digval
        bcc     @out
        lda     mode                    ; (a digit of the base)
        beq     @clr2
        cmp     base
        bcs     @out
@clr2:  jsr     clrall
        bra     @ok
@clr:   jmp     clrall
@out:   rts
@ok:    lda     mode
        jne     pkey
        lda     z:kc                    ; Standard
        cmp     #'.'
        beq     :+
        cmp     #'0'
        bcc     @tab
        cmp     #'9' + 1
        bcs     @tab
:       jmp     s_digit
@tab:   ldx     #.loword(stab)
; X = table of {u8 code, u16 routine} ending with 0: the routine of z:kc (A = the code)
dispatch:
        lda     a:0,x
        and     #$00FF
        beq     @out
        cmp     z:kc
        beq     :+
        inx
        inx
        inx
        bra     dispatch
:       lda     a:1,x
        sta     z:jv
        lda     z:kc
        jmp     (jv)
@out:   rts

; ---------------------------------------------------------------- Standard
s_digit:
        lda     entering
        bne     :+
        lda     #'0'                    ; a new number: "0"
        sta     ebuf
        lda     #1
        sta     entering
        sta     fresh
:       ldx     #.loword(ebuf)
        jsr     ui_strlen
        sta     z:t0                    ; its length
        lda     z:kc
        cmp     #'.'
        bne     @dig
        ldx     #0
:       lda     ebuf,x
        and     #$00FF
        beq     @app
        cmp     #'.'
        beq     @out                    ; (one point)
        inx
        bra     :-
@dig:   ldx     z:t0                    ; "0" or "-0": the digit replaces the 0
        lda     ebuf-1,x
        and     #$00FF
        cmp     #'0'
        bne     @cnt
        cpx     #1
        beq     @repl
        cpx     #2
        bne     @cnt
        lda     ebuf
        and     #$00FF
        cmp     #'-'
        bne     @cnt
@repl:  dex
        stx     z:t0
        bra     @app
@cnt:   ldx     #0                      ; at most MAXDIG digits
        ldy     #0
:       lda     ebuf,x
        and     #$00FF
        beq     :++
        cmp     #'0'
        bcc     :+
        iny
:       inx
        bra     :--
:       cpy     #MAXDIG
        bcs     @out
@app:   ldx     z:t0
        lda     z:kc
        and     #$00FF                  ; (with the terminator)
        sta     ebuf,x
@out:   rts

; the number being typed -> nx
s_commit:
        lda     entering
        beq     @out
        stz     entering
        ldx     #.loword(ebuf)
        jsr     n_parse
        bcs     @out
        ldx     #.loword(n_r)
        ldy     #.loword(nx)
        jmp     n_cpy
@out:   rts

; n_a op n_b -> n_r for the operation A (+ - * /); C set: error (n_err)
s_apply:
        cmp     #'+'
        bne     :+
        jmp     n_add
:       cmp     #'-'
        bne     :+
        jmp     n_sub
:       cmp     #'*'
        bne     :+
        jmp     n_mul
:       jmp     n_div

; nacc pendop nx -> n_r (C set: error)
s_pend: ldx     #.loword(nacc)
        ldy     #.loword(n_a)
        jsr     n_cpy
        ldx     #.loword(nx)
        ldy     #.loword(n_b)
        jsr     n_cpy
        lda     pendop
        jmp     s_apply

; an error: shown until cleared
s_error:
        lda     n_err
        sta     err
        stz     pendop
        stz     lastop
        stz     entering
        rts

; n_r -> nx
s_setx: ldx     #.loword(n_r)
        ldy     #.loword(nx)
        jmp     n_cpy

s_binop:
        jsr     s_commit
        lda     pendop
        beq     @first
        lda     fresh
        beq     @set
        jsr     s_pend
        bcs     s_error
        jsr     s_setx
@first: ldx     #.loword(nx)
        ldy     #.loword(nacc)
        jsr     n_cpy
@set:   lda     z:kc
        sta     pendop
        stz     fresh
        rts

s_equal:
        jsr     s_commit
        lda     pendop
        beq     @rep
        ldx     #.loword(nx)            ; (for = again)
        ldy     #.loword(nlast)
        jsr     n_cpy
        lda     pendop
        sta     lastop
        jsr     s_pend
        bcs     s_error
        stz     pendop
        stz     fresh
        jmp     s_setx
@rep:   lda     lastop
        beq     @out
        ldx     #.loword(nx)
        ldy     #.loword(n_a)
        jsr     n_cpy
        ldx     #.loword(nlast)
        ldy     #.loword(n_b)
        jsr     n_cpy
        lda     lastop
        jsr     s_apply
        jcs     s_error
        jmp     s_setx
@out:   rts

; %: with + or - pending, that percentage of the accumulator; else X / 100
s_pct:  jsr     s_commit
        lda     pendop
        cmp     #'+'
        beq     :+
        cmp     #'-'
        bne     @div
:       ldx     #.loword(nacc)
        ldy     #.loword(n_a)
        jsr     n_cpy
        ldx     #.loword(nx)
        ldy     #.loword(n_b)
        jsr     n_cpy
        jsr     n_mul
        jcs     s_error
        jsr     s_setx
@div:   lda     nx+N_D                  ; / 100: the exponent - 2
        and     #$00FF
        beq     @out
        lda     nx+N_EXP
        sec
        sbc     #2
        sta     nx+N_EXP
        clc
        adc     #99
        bpl     @out
        ldx     #.loword(nx)
        jsr     n_zero
@out:   lda     #1
        sta     fresh
        rts

s_clear:
        jmp     clrall

s_ce:   ldx     #.loword(nx)
        jsr     n_zero
        stz     entering
        lda     #1
        sta     fresh
        rts

s_back: lda     entering
        beq     @out
        ldx     #.loword(ebuf)
        jsr     ui_strlen
        tax
        dex
        sep     #$20
        .a8
        stz     ebuf,x
        rep     #$20
        .a16
        cpx     #0                      ; "" or "-": "0"
        beq     :+
        cpx     #1
        bne     @out
        lda     ebuf
        and     #$00FF
        cmp     #'-'
        bne     @out
:       lda     #'0'
        sta     ebuf
@out:   rts

s_neg:  lda     entering
        beq     @num
        lda     ebuf
        and     #$00FF
        cmp     #'-'
        bne     @add
        ldx     #0                      ; "-..." -> "..."
:       lda     ebuf+1,x
        sep     #$20
        .a8
        sta     ebuf,x
        rep     #$20
        .a16
        and     #$00FF
        beq     @out
        inx
        bra     :-
@add:   lda     ebuf                    ; "0" stays
        cmp     #'0'
        beq     @out
        ldx     #.loword(ebuf)          ; "..." -> "-..."
        jsr     ui_strlen
        tax
:       lda     ebuf,x
        sep     #$20
        .a8
        sta     ebuf+1,x
        rep     #$20
        .a16
        dex
        bpl     :-
        lda     ebuf
        and     #$FF00
        ora     #'-'
        sta     ebuf
@out:   rts
@num:   lda     nx+N_D
        and     #$00FF
        beq     :+
        lda     nx+N_SGN
        eor     #1
        sta     nx+N_SGN
:       lda     #1
        sta     fresh
        rts

; the functions of X: n_r -> X, fresh
s_fdone:
        bcc     :+
        jmp     s_error
:       jsr     s_setx
        lda     #1
        sta     fresh
        rts
s_xa:   jsr     s_commit                ; X -> n_a and n_b
        ldx     #.loword(nx)
        ldy     #.loword(n_a)
        jsr     n_cpy
        ldx     #.loword(nx)
        ldy     #.loword(n_b)
        jmp     n_cpy
s_sqrt: jsr     s_xa
        jsr     n_sqrt
        jmp     s_fdone
s_sqr:  jsr     s_xa
        jsr     n_mul
        jmp     s_fdone
s_inv:  jsr     s_xa
        ldx     #.loword(n_one)
        ldy     #.loword(n_a)
        jsr     n_cpy
        jsr     n_div
        jmp     s_fdone

s_mc:   ldx     #.loword(nmem)
        jmp     n_zero
s_mr:   stz     entering
        ldx     #.loword(nmem)
        ldy     #.loword(nx)
        jsr     n_cpy
        lda     #1
        sta     fresh
        rts
s_mplus:
        jsr     s_commit
        ldx     #.loword(nmem)
        ldy     #.loword(n_a)
        jsr     n_cpy
        ldx     #.loword(nx)
        ldy     #.loword(n_b)
        jsr     n_cpy
        lda     z:kc
        cmp     #'p'
        bne     :+
        jsr     n_add
        bra     :++
:       jsr     n_sub
:       bcc     :+
        jmp     s_error
:       ldx     #.loword(n_r)
        ldy     #.loword(nmem)
        jmp     n_cpy

; to the Programmer view: X's integer part, 32 bits
s_toprog:
        jsr     s_commit
        ldx     #.loword(nx)
        jsr     n_toint
        jsr     clrall
        lda     pv
        sta     px
        lda     pv+2
        sta     px+2
        lda     #1
        sta     mode
        rts

; ---------------------------------------------------------------- Programmer
pkey:   lda     z:kc
        jsr     digval
        bcc     @tab
        cmp     base
        bcs     @out
        jmp     p_digit
@tab:   ldx     #.loword(ptab)
        jmp     dispatch
@out:   rts

; A = a digit's value
p_digit:
        sta     z:t0
        lda     entering
        bne     :+
        stz     px
        stz     px+2
        lda     #1
        sta     entering
        sta     fresh
:       lda     base
        cmp     #10
        beq     @dec
        ldx     #4                      ; the bits of a digit
        cmp     #16
        beq     :+
        ldx     #3
        cmp     #8
        beq     :+
        ldx     #1
:       stx     z:t1
        lda     px+2                    ; no room: the digit is not taken
        ldy     z:t1
:       asl     a
        bcs     @out
        dey
        bne     :-
:       asl     px
        rol     px+2
        dex
        bne     :-
        lda     px
        ora     z:t0
        sta     px
@out:   rts
@dec:   lda     z:t0                    ; (i_mul uses t0-t3)
        sta     z:t6
        stz     z:t7                    ; decimal: the magnitude, the sign kept
        lda     px+2
        bpl     :+
        inc     z:t7
        ldx     #.loword(px)
        jsr     neg32
:       lda     px+2                    ; at most 2147483647 (2147483648 negative)
        cmp     #$0CCC
        bcc     @ok
        bne     @back
        lda     px
        cmp     #$CCCC
        bcc     @ok
        bne     @back
        lda     z:t7
        clc
        adc     #7
        cmp     z:t6
        bcc     @back
@ok:    lda     px                      ; px = px * 10 + digit
        sta     ia
        lda     px+2
        sta     ia+2
        lda     #10
        sta     ibv
        stz     ibv+2
        jsr     i_mul
        lda     pv
        clc
        adc     z:t6
        sta     px
        lda     pv+2
        adc     #0
        sta     px+2
@back:  lda     z:t7
        beq     :+
        ldx     #.loword(px)
        jsr     neg32
:       rts

p_commit:
        stz     entering
        rts

; ia op ibv -> pv for the operation A; C set: divide by zero
p_apply:
        cmp     #'+'
        bne     :+
        lda     ia
        clc
        adc     ibv
        sta     pv
        lda     ia+2
        adc     ibv+2
        sta     pv+2
        clc
        rts
:       cmp     #'-'
        bne     :+
        lda     ia
        sec
        sbc     ibv
        sta     pv
        lda     ia+2
        sbc     ibv+2
        sta     pv+2
        clc
        rts
:       cmp     #'*'
        bne     :+
        jsr     i_mul
        clc
        rts
:       cmp     #'/'
        bne     :+
        jmp     i_div
:       cmp     #'%'
        bne     :+
        jsr     i_div
        bcs     @out
        lda     irem
        sta     pv
        lda     irem+2
        sta     pv+2
@out:   rts
:       cmp     #'&'
        bne     :+
        lda     ia
        and     ibv
        sta     pv
        lda     ia+2
        and     ibv+2
        sta     pv+2
        clc
        rts
:       cmp     #'|'
        bne     :+
        lda     ia
        ora     ibv
        sta     pv
        lda     ia+2
        ora     ibv+2
        sta     pv+2
        clc
        rts
:       cmp     #'^'
        bne     :+
        lda     ia
        eor     ibv
        sta     pv
        lda     ia+2
        eor     ibv+2
        sta     pv+2
        clc
        rts
:       sta     z:t0                    ; shifts: by 0-31 (more: all out)
        lda     ia
        sta     pv
        lda     ia+2
        sta     pv+2
        lda     ibv+2
        bne     @far
        lda     ibv
        cmp     #32
        bcs     @far
        tax
        beq     @sdone
        lda     z:t0
        cmp     #'<'
        bne     @sar
:       asl     pv
        rol     pv+2
        dex
        bne     :-
        bra     @sdone
@sar:   lda     pv+2
        cmp     #$8000
        ror     pv+2
        ror     pv
        dex
        bne     @sar
@sdone: clc
        rts
@far:   stz     pv                      ; << : 0; >> : the sign everywhere
        stz     pv+2
        lda     z:t0
        cmp     #'<'
        beq     @sdone
        lda     ia+2
        bpl     @sdone
        dec     pv
        dec     pv+2
        clc
        rts

; pacc pendop px -> pv
p_pend: lda     pacc
        sta     ia
        lda     pacc+2
        sta     ia+2
        lda     px
        sta     ibv
        lda     px+2
        sta     ibv+2
        lda     pendop
        jmp     p_apply

p_error:
        lda     #E_DIV
        sta     n_err
        jmp     s_error

p_setx: lda     pv
        sta     px
        lda     pv+2
        sta     px+2
        rts

p_binop:
        jsr     p_commit
        lda     pendop
        beq     @first
        lda     fresh
        beq     @set
        jsr     p_pend
        bcs     p_error
        jsr     p_setx
@first: lda     px
        sta     pacc
        lda     px+2
        sta     pacc+2
@set:   lda     z:kc
        sta     pendop
        stz     fresh
        rts

p_equal:
        jsr     p_commit
        lda     pendop
        beq     @rep
        lda     px
        sta     plast
        lda     px+2
        sta     plast+2
        lda     pendop
        sta     lastop
        jsr     p_pend
        bcs     p_error
        stz     pendop
        stz     fresh
        jmp     p_setx
@rep:   lda     lastop
        beq     @out
        lda     px
        sta     ia
        lda     px+2
        sta     ia+2
        lda     plast
        sta     ibv
        lda     plast+2
        sta     ibv+2
        lda     lastop
        jsr     p_apply
        jcs     p_error
        jmp     p_setx
@out:   rts

p_ce:   stz     px
        stz     px+2
        stz     entering
        lda     #1
        sta     fresh
        rts

p_back: lda     entering
        beq     @out
        lda     base
        cmp     #10
        bne     @sh
        lda     px                      ; decimal: / 10 (towards 0)
        sta     ia
        lda     px+2
        sta     ia+2
        lda     #10
        sta     ibv
        stz     ibv+2
        jsr     i_div
        jmp     p_setx
@sh:    ldx     #4
        cmp     #16
        beq     :+
        ldx     #3
        cmp     #8
        beq     :+
        ldx     #1
:       lsr     px+2
        ror     px
        dex
        bne     :-
@out:   rts

p_neg:  ldx     #.loword(px)
        jsr     neg32
p_fn:   lda     entering                ; (while typing, the number goes on)
        bne     :+
        lda     #1
        sta     fresh
:       rts
p_not:  jsr     p_commit
        lda     px
        eor     #$FFFF
        sta     px
        lda     px+2
        eor     #$FFFF
        sta     px+2
        bra     p_fn
p_rol:  jsr     p_commit
        lda     px+2
        asl     a
        rol     px
        rol     px+2
        bra     p_fn
p_ror:  jsr     p_commit
        lda     px
        lsr     a
        ror     px+2
        ror     px
        bra     p_fn

p_base: jsr     p_commit
        ldx     #0
:       lda     basecode,x
        and     #$00FF
        cmp     z:kc
        beq     :+
        inx
        bra     :-
:       txa
        asl     a
        tax
        lda     bases,x
        sta     base
        rts

; to the Standard view: the integer as a decimal number
p_tostd:
        jsr     p_commit
        lda     px
        sta     pv
        lda     px+2
        sta     pv+2
        jsr     n_fromint
        jsr     clrall
        jsr     s_setx
        stz     mode
        rts

; ---------------------------------------------------------------- the display's strings
; dstr: the number (or the error's message), xstr: the pending operation ("12 +")
mkdisp: stz     xstr
        lda     err
        beq     :+
        asl     a
        tax
        lda     errmsg-2,x
        tax
        ldy     #.loword(dstr)
        jmp     ui_strcpy
:       lda     mode
        bne     @prog
        lda     entering
        beq     :+
        ldx     #.loword(ebuf)
        ldy     #.loword(dstr)
        jsr     ui_strcpy
        bra     @xs
:       ldx     #.loword(nx)
        jsr     n_fmt
        ldx     #.loword(nstr)
        ldy     #.loword(dstr)
        jsr     ui_strcpy
@xs:    lda     pendop
        beq     @out
        ldx     #.loword(nacc)
        jsr     n_fmt
        ldx     #.loword(nstr)
        bra     @op
@prog:  lda     px
        sta     pv
        lda     px+2
        sta     pv+2
        lda     base
        jsr     i_fmt
        ldx     #.loword(istr)
        ldy     #.loword(dstr)
        jsr     ui_strcpy
        lda     pendop
        beq     @out
        lda     pacc
        sta     pv
        lda     pacc+2
        sta     pv+2
        lda     base
        jsr     i_fmt
        ldx     #.loword(istr)
@op:    ldy     #.loword(xstr)          ; the accumulator, a space, the operation's name
        jsr     ui_strcpy
        tay
        lda     #' '
        sta     xstr,y
        iny
        sty     z:t0
        ldx     #0
:       lda     opnames,x
        and     #$00FF
        cmp     pendop
        beq     :+
        inx
        inx
        bra     :-
:       lda     opnames+1,x
        and     #$00FF
        tax
        ldy     z:t0
        jmp     opcopy
@out:   rts
; the name X (an offset in opstr) -> xstr at Y
opcopy: lda     opstr,x
        and     #$00FF
        sep     #$20
        .a8
        sta     xstr,y
        rep     #$20
        .a16
        beq     :+
        inx
        iny
        bra     opcopy
:       rts

; pbuf (the clipboard's text) -> X; C set: not a number
paste:  lda     mode
        bne     @prog
        ldx     #.loword(pbuf)
        jsr     n_parse
        bcs     @out
        jsr     clrnum
        jsr     s_setx
        clc
@out:   rts
@prog:  jsr     clrnum                  ; digits of the base, spaces between them, a sign
        stz     pflag                    ; (decimal); bit 0 a digit seen, bit 1 minus
        ldx     #0
@c:     lda     pbuf,x
        and     #$00FF
        beq     @end
        cmp     #' '
        beq     @n
        cmp     #'-'
        bne     :+
        lda     base
        cmp     #10
        bne     @bad
        lda     pflag
        bne     @bad
        lda     #2
        sta     pflag
        bra     @n
:       cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        ora     #$20
:       jsr     digval
        bcc     @bad
        cmp     base
        bcs     @bad
        phx
        jsr     p_digit
        plx
        lda     pflag
        ora     #1
        sta     pflag
@n:     inx
        bra     @c
@end:   lda     pflag
        and     #1
        beq     @bad
        lda     pflag
        and     #2
        beq     :+
        ldx     #.loword(px)
        jsr     neg32
:       stz     entering
        lda     #1
        sta     fresh
        clc
        rts
@bad:   sec
        rts
; a pasted number replaces X: no error, no typing, a fresh number
clrnum: lda     err
        beq     :+
        jsr     clrall
:       stz     entering
        lda     #1
        sta     fresh
        stz     px
        stz     px+2
        lda     #1
        sta     entering                ; (p_digit: typing)
        lda     mode
        bne     :+
        stz     entering
:       rts

; ---------------------------------------------------------------- the self test
; calc -t: each case of ttab from the start (Standard, base 10, memory empty), its keys
; typed (K) or its text pasted (P); the display must then be the expected text.
test_run:
        print   "CALC TEST START\n"
        stz     tcount
        stz     tfail
        lda     #.loword(ttab)
        sta     tptr
@case:  ldx     tptr
        lda     a:0,x
        and     #$00FF
        jeq     @end
        sta     ttype
        inx
        stx     tkeys
        jsr     skipstr
        stx     texp
        jsr     skipstr
        stx     tptr
        jsr     reset
        lda     ttype
        cmp     #'K'
        beq     :+
        cmp     #'P'                    ; P: paste (Q: in the Programmer view)
        beq     @paste
        lda     #'V'
        jsr     calc_key
        bra     @paste
:        ldx     tkeys                   ; keys
@k:     lda     a:0,x
        and     #$00FF
        beq     @cmp
        phx
        jsr     calc_key
        plx
        inx
        bra     @k
@paste: ldx     tkeys
        ldy     #.loword(pbuf)
        jsr     ui_strcpy
        jsr     paste
        bcc     @cmp
        jsr     mkdisp
        ldx     #.loword(t_rej)
        ldy     #.loword(dstr)
        jsr     ui_strcpy
        bra     @cmp2
@cmp:   jsr     mkdisp
@cmp2:  inc     tcount
        ldx     texp
        ldy     #0
:       lda     a:0,x
        eor     dstr,y
        and     #$00FF
        bne     @fail
        lda     a:0,x
        and     #$00FF
        beq     @pass
        inx
        iny
        bra     :-
@pass:  print   "PASS "
        jsr     @show
        jsr     put_nl
        jmp     @case
@fail:  inc     tfail
        print   "FAIL "
        jsr     @show
        print   " (expected "
        ldx     texp
        ldy     #^ttab
        jsr     out_str
        print   ")\n"
        jmp     @case
@show:  lda     ttype
        and     #$00FF
        cmp     #'K'
        beq     :+
        print   "paste "
:       ldx     tkeys
        ldy     #^ttab
        jsr     out_str
        print   " -> "
        ldx     #.loword(dstr)
        ldy     #^dstr
        jmp     out_str
@end:   print   "CALC TEST END: "
        lda     tcount
        jsr     put_dec
        print   " cases, "
        lda     tfail
        jsr     put_dec
        print   " failed\n"
        exit    0

; X = string -> X past its terminator
skipstr:
        lda     a:0,x
        inx
        and     #$00FF
        bne     skipstr
        rts
