; calc_num.s - the Calculator's numbers (included by calc.s): decimal floating point and the
; programmer view's 32-bit integers.
;
; A number (NUM, NSZ bytes): u16 sign (0 / 1), i16 exponent, 16 decimal digits (one per byte,
; 0-9). The value is d0.d1d2...d15 x 10^exponent, d0 <> 0, or zero: all digits 0, exponent 0,
; sign 0. Exponents -99 .. 99: a larger result is an overflow (n_err = E_OVF), a smaller one 0.
;
; Every operation works on the fixed registers n_a, n_b -> n_r. It builds the exact (or, for
; a quotient or a root, at least 19 digits of the) result in the work array wk (WKN digits,
; wk[0] of weight 10^wexp) and n_norm rounds it to 16 digits, half away from zero. So the
; arithmetic is decimal (0.1 + 0.2 is exactly 0.3) and each result is correctly rounded to 16
; digits; the display shows 15 (n_fmt), so a last-digit error of a chain of operations
; (1 / 3 x 3 = 0.9999999999999999) is not seen.
;
; Routines (a16 i16; A, X, Y clobbered): n_add, n_sub, n_mul, n_div, n_sqrt (C set: error, in
; n_err), n_parse (X = string -> n_r; C set: not a number, or overflow), n_fmt (X = NUM ->
; nstr, the display's form), n_cpy (X -> Y), n_zero (X), n_toint (X = NUM -> pv, low 32 bits of
; its integer part, two's complement), n_fromint (pv, signed -> n_r).
; 32-bit (programmer view): i_mul, i_div (signed; C set: divide by zero), i_fmt (base).

NSZ     = 20
N_SGN   = 0
N_EXP   = 2
N_D     = 4
ND      = 16                            ; digits
WKN     = 64                            ; the work array
E_DIV   = 1                             ; n_err: divide by zero
E_OVF   = 2                             ;   overflow
E_INV   = 3                             ;   invalid input (the root of a negative number)
RL      = 24                            ; the square root's digit strings

        .segment "CODE"

; X = source, Y = destination (NUM)
n_cpy:  stx     z:p1
        sty     z:p2
        ldy     #NSZ - 2
:       lda     (p1),y
        sta     (p2),y
        dey
        dey
        bpl     :-
        rts

; X = NUM: zero
n_zero: ldy     #NSZ / 2
:       stz     a:0,x
        inx
        inx
        dey
        bne     :-
        rts

; X = NUM -> Z set if zero (A = its first digit)
n_isz:  lda     a:N_D,x
        and     #$00FF
        rts

; wk and wk2 cleared
wk_clr: ldx     #WKN - 2
:       stz     wk,x
        stz     wk2,x
        dex
        dex
        bpl     :-
        rts

; ---------------------------------------------------------------- rounding
; wk (wk[0] of weight 10^wexp), wsgn -> n_r, rounded to 16 digits. C set: overflow.
n_norm: ldx     #0
:       lda     wk,x
        and     #$00FF
        bne     @nz
        inx
        cpx     #WKN - ND - 1
        bcc     :-
        ldx     #.loword(n_r)           ; nothing: zero
        jsr     n_zero
        clc
        rts
@nz:    stx     z:t0
        lda     wexp
        sec
        sbc     z:t0
        sta     n_r+N_EXP
        ldy     #0
        sep     #$20
        .a8
:       lda     wk,x
        sta     n_r+N_D,y
        inx
        iny
        cpy     #ND
        bne     :-
        lda     wk,x                    ; the next digit: round half away from zero
        cmp     #5
        bcc     @done
        ldy     #ND - 1
:       lda     n_r+N_D,y
        inc     a
        cmp     #10
        bcc     @st
        lda     #0
        sta     n_r+N_D,y
        dey
        bpl     :-
        lda     #1                      ; 9.99...9 -> 10.0...0
        sta     n_r+N_D
        rep     #$20
        .a16
        inc     n_r+N_EXP
        bra     @done
        .a8
@st:    sta     n_r+N_D,y
@done:  rep     #$20
        .a16
        lda     wsgn
        and     #1
        sta     n_r+N_SGN
        lda     n_r+N_EXP
        bmi     @neg
        cmp     #100
        bcs     @ovf
        clc
        rts
@neg:   clc
        adc     #99
        bpl     :+
        ldx     #.loword(n_r)           ; below 1e-99: zero
        jsr     n_zero
:       clc
        rts
@ovf:   lda     #E_OVF
        sta     n_err
        sec
        rts

; ---------------------------------------------------------------- + -
n_sub:  lda     n_b+N_SGN
        eor     #1
        sta     n_b+N_SGN
        ; fall through
n_add:  ldx     #.loword(n_b)
        jsr     n_isz
        bne     :+
        ldx     #.loword(n_a)
        jmp     @copy
:       ldx     #.loword(n_a)
        jsr     n_isz
        bne     :+
        ldx     #.loword(n_b)
        bra     @copy
:       jsr     n_cmpmag
        bcs     :+
        ldx     #.loword(n_b)           ; L = the larger magnitude, S = the other
        ldy     #.loword(n_a)
        bra     @go
:       ldx     #.loword(n_a)
        ldy     #.loword(n_b)
@go:    stx     z:p1
        sty     z:p2
        jsr     wk_clr
        ldx     #0                      ; wk[1..16] = L
        ldy     #N_D
        sep     #$20
        .a8
:       lda     (p1),y
        sta     wk+1,x
        inx
        iny
        cpx     #ND
        bne     :-
        rep     #$20
        .a16
        ldy     #N_EXP
        lda     (p1),y
        inc     a
        sta     wexp
        dec     a
        sec
        sbc     (p2),y                  ; the exponent difference (>= 0)
        cmp     #WKN - ND - 1
        bcs     @big
        tax                             ; wk2[1 + diff ..] = S
        inx
        ldy     #N_D
        sep     #$20
        .a8
:       lda     (p2),y
        sta     wk2,x
        inx
        iny
        cpy     #N_D + ND
        bne     :-
        rep     #$20
        .a16
        ldy     #N_SGN
        lda     (p1),y
        sta     wsgn
        lda     n_a+N_SGN
        eor     n_b+N_SGN
        and     #1
        bne     :+
        jsr     wk_add
        jmp     n_norm
:       jsr     wk_sub
        jmp     n_norm
@big:   ldx     z:p1                    ; S is below the last digit of L
@copy:  ldy     #.loword(n_r)
        jsr     n_cpy
        clc
        rts

; |n_a| vs |n_b| (both not zero) -> C set if |n_a| >= |n_b|
n_cmpmag:
        lda     n_a+N_EXP
        cmp     n_b+N_EXP
        beq     @dig
        sec
        sbc     n_b+N_EXP
        bvc     :+
        eor     #$8000
:       asl     a                       ; C = the sign: set if a < b
        bcs     :+
        sec
        rts
:       clc
        rts
@dig:   ldx     #0
        sep     #$20
        .a8
:       lda     n_a+N_D,x
        cmp     n_b+N_D,x
        bne     :+
        inx
        cpx     #ND
        bne     :-
        sec
:       rep     #$20
        .a16
        rts

; wk += wk2, wk -= wk2 (WKN digits)
wk_add: ldx     #WKN - 1
        sep     #$20
        .a8
        stz     z:cy
@l:     lda     wk,x
        clc
        adc     wk2,x
        clc
        adc     z:cy
        stz     z:cy
        cmp     #10
        bcc     :+
        sbc     #10
        inc     z:cy
:       sta     wk,x
        dex
        bpl     @l
        rep     #$20
        .a16
        rts
wk_sub: ldx     #WKN - 1
        sep     #$20
        .a8
        stz     z:cy
@l:     lda     wk,x
        sec
        sbc     wk2,x
        sec
        sbc     z:cy
        stz     z:cy
        bpl     :+
        clc
        adc     #10
        inc     z:cy
:       sta     wk,x
        dex
        bpl     @l
        rep     #$20
        .a16
        rts

; ---------------------------------------------------------------- x
n_mul:  ldx     #.loword(n_a)
        jsr     n_isz
        beq     @zero
        ldx     #.loword(n_b)
        jsr     n_isz
        bne     :+
@zero:  ldx     #.loword(n_r)
        jsr     n_zero
        clc
        rts
:       ldx     #2 * (2 * ND + 1) - 2   ; the column sums
:       stz     pw,x
        dex
        dex
        bpl     :-
        ldx     #0
@i:     lda     n_a+N_D,x
        and     #$00FF
        beq     @ni
        asl     a
        sta     z:t0
        asl     a
        asl     a
        clc
        adc     z:t0
        sta     z:t1                    ; a[i] * 10
        stx     z:t2
        ldy     #0
@j:     lda     n_b+N_D,y
        and     #$00FF
        clc
        adc     z:t1
        tax
        lda     mtab,x                  ; a[i] * b[j]
        and     #$00FF
        sta     z:t3
        tya
        sec                             ; column i + j + 1
        adc     z:t2
        asl     a
        tax
        lda     pw,x
        clc
        adc     z:t3
        sta     pw,x
        iny
        cpy     #ND
        bne     @j
        ldx     z:t2
@ni:    inx
        cpx     #ND
        bne     @i
        jsr     wk_clr
        stz     z:dq                    ; the carries, from the last column
        ldx     #2 * ND
@c:     txa
        asl     a
        tay
        lda     pw,y
        clc
        adc     z:dq
        jsr     dv10
        sep     #$20
        .a8
        sta     wk,x
        rep     #$20
        .a16
        dex
        bpl     @c
        lda     n_a+N_EXP
        clc
        adc     n_b+N_EXP
        inc     a
        sta     wexp
        lda     n_a+N_SGN
        eor     n_b+N_SGN
        sta     wsgn
        jmp     n_norm

; A / 10 -> z:dq = the quotient, A = the remainder (keeps X, Y; A < 2000 or so)
dv10:   stz     z:dq
:       cmp     #10
        bcc     :+
        sbc     #10
        inc     z:dq
        bra     :-
:       rts

; ---------------------------------------------------------------- /
n_div:  ldx     #.loword(n_b)
        jsr     n_isz
        bne     :+
        lda     #E_DIV
        sta     n_err
        sec
        rts
:       ldx     #.loword(n_a)
        jsr     n_isz
        bne     :+
        ldx     #.loword(n_r)
        jsr     n_zero
        clc
        rts
:       jsr     wk_clr
        ldx     #ND                     ; ra = 0 a0 .. a15, rb = 0 b0 .. b15
        sep     #$20
        .a8
:       lda     n_a+N_D-1,x
        sta     ra,x
        lda     n_b+N_D-1,x
        sta     rb,x
        dex
        bne     :-
        stz     ra
        stz     rb
        rep     #$20
        .a16
        lda     #ND + 1
        sta     z:bl
        stz     z:t4                    ; the quotient digit's index
@q:     stz     z:t5
:       ldx     #.loword(ra)
        ldy     #.loword(rb)
        stx     z:p1
        sty     z:p2
        jsr     bcmp
        bcc     :+
        jsr     bsub
        inc     z:t5
        bra     :-
:       lda     z:t5
        ldx     z:t4
        sep     #$20
        .a8
        sta     wk,x
        rep     #$20
        .a16
        jsr     bshl
        inc     z:t4
        lda     z:t4
        cmp     #ND + 4
        bcc     @q
        lda     n_a+N_EXP
        sec
        sbc     n_b+N_EXP
        sta     wexp
        lda     n_a+N_SGN
        eor     n_b+N_SGN
        sta     wsgn
        jmp     n_norm

; ---------------------------------------------------------------- square root
; n_a -> n_r, digit by digit (exact digits, then rounded)
n_sqrt: ldx     #.loword(n_a)
        jsr     n_isz
        bne     :+
        ldx     #.loword(n_r)
        jsr     n_zero
        clc
        rts
:       lda     n_a+N_SGN
        beq     :+
        lda     #E_INV
        sta     n_err
        sec
        rts
:       jsr     wk_clr                  ; wk2 = the radicand's digits, in pairs
        lda     n_a+N_EXP
        and     #1
        eor     #1                      ; even exponent: a leading 0 (pairs 0 d0, d1 d2, ...)
        tax
        ldy     #0
        sep     #$20
        .a8
:       lda     n_a+N_D,y
        sta     wk2,x
        inx
        iny
        cpy     #ND
        bne     :-
        rep     #$20
        .a16
        lda     n_a+N_EXP               ; the root's first digit: 10^((e - (e & 1)) / 2)
        and     #$FFFE
        cmp     #$8000
        ror     a
        sta     wexp
        stz     wsgn
        ldx     #RL - 2
:       stz     rr,x
        stz     rp,x
        dex
        dex
        bpl     :-
        lda     #RL
        sta     z:bl
        stz     z:t4                    ; root digit i
@d:     ldx     #.loword(rr)            ; rr = rr * 100 + the next pair
        stx     z:p1
        jsr     bshl
        jsr     bshl
        lda     z:t4
        asl     a
        tax
        lda     wk2,x
        sta     rr+RL-2                 ; (two digits, in order)
        ldx     #.loword(rp)            ; ry = 20 rp + 1
        ldy     #.loword(ry)
        jsr     bcopy
        ldx     #.loword(ry)
        stx     z:p1
        stx     z:p2
        jsr     bshl
        jsr     badd
        lda     #1
        jsr     binc
        stz     z:t5
:       ldx     #.loword(rr)            ; while rr >= ry: rr -= ry, ry += 2
        ldy     #.loword(ry)
        stx     z:p1
        sty     z:p2
        jsr     bcmp
        bcc     :+
        jsr     bsub
        ldx     #.loword(ry)
        stx     z:p1
        lda     #2
        jsr     binc
        inc     z:t5
        bra     :-
:       ldx     #.loword(rp)            ; rp = rp * 10 + d
        stx     z:p1
        jsr     bshl
        lda     z:t5
        sep     #$20
        .a8
        sta     rp+RL-1
        ldx     z:t4
        sta     wk,x
        rep     #$20
        .a16
        inc     z:t4
        lda     z:t4
        cmp     #ND + 2
        bcc     @d
        jmp     n_norm

; ---------------------------------------------------------------- digit strings
; (p1) and (p2) of z:bl digits, the first the most significant.
; C set if (p1) >= (p2)
bcmp:   ldy     #0
        sep     #$20
        .a8
:       lda     (p1),y
        cmp     (p2),y
        bne     :+
        iny
        cpy     z:bl
        bne     :-
        sec
:       rep     #$20
        .a16
        rts
; (p1) -= (p2)
bsub:   ldy     z:bl
        dey
        sep     #$20
        .a8
        stz     z:cy
@l:     lda     (p1),y
        sec
        sbc     (p2),y
        sec
        sbc     z:cy
        stz     z:cy
        bpl     :+
        clc
        adc     #10
        inc     z:cy
:       sta     (p1),y
        dey
        bpl     @l
        rep     #$20
        .a16
        rts
; (p1) += (p2)
badd:   ldy     z:bl
        dey
        sep     #$20
        .a8
        stz     z:cy
@l:     lda     (p1),y
        clc
        adc     (p2),y
        clc
        adc     z:cy
        stz     z:cy
        cmp     #10
        bcc     :+
        sbc     #10
        inc     z:cy
:       sta     (p1),y
        dey
        bpl     @l
        rep     #$20
        .a16
        rts
; (p1) += A (0-9)
binc:   ldy     z:bl
        dey
        sep     #$20
        .a8
@l:     clc
        adc     (p1),y
        cmp     #10
        bcc     :+
        sbc     #10
        sta     (p1),y
        lda     #1
        dey
        bpl     @l
        bra     :++
:       sta     (p1),y
:       rep     #$20
        .a16
        rts
; (p1) = (p1) * 10 (the first digit is lost)
bshl:   ldy     #0
        sep     #$20
        .a8
:       iny
        cpy     z:bl
        beq     :+
        lda     (p1),y
        dey
        sta     (p1),y
        iny
        bra     :-
:       dey
        lda     #0
        sta     (p1),y
        rep     #$20
        .a16
        rts
; X -> Y, z:bl digits
bcopy:  stx     z:p1
        sty     z:p2
        ldy     z:bl
        dey
        sep     #$20
        .a8
:       lda     (p1),y
        sta     (p2),y
        dey
        bpl     :-
        rep     #$20
        .a16
        rts

; ---------------------------------------------------------------- text
; the zero-terminated string X -> n_r. Spaces around it and ',' between the digits are
; ignored; [+|-] digits [. digits] [e [+|-] digits]. C set: not a number (or overflow).
n_parse:
        stx     z:p1
        jsr     wk_clr
        stz     wsgn
        stz     z:t0                    ; digits stored
        stz     z:t1                    ; integer digits after the first non-zero one
        stz     z:t2                    ; leading zeros after the point (before any digit)
        stz     z:t3                    ; seen: bit 0 a digit, bit 1 the point, bit 2 non-zero
        stz     z:t4                    ; the exponent part
        stz     z:t5                    ; its sign
        ldy     #0
        jsr     @sp
        cmp     #'-'
        bne     :+
        inc     wsgn
        bra     @sgn
:       cmp     #'+'
        bne     @m
@sgn:   iny
@m:     jsr     @ch
        cmp     #','
        beq     @next
        cmp     #'.'
        bne     :+
        lda     z:t3
        bit     #2
        jne     @bad
        ora     #2
        sta     z:t3
        bra     @next
:       cmp     #'0'
        bcc     @mend
        cmp     #'9' + 1
        bcs     @mend
        sbc     #'0' - 1                ; (C clear: - '0')
        sta     z:t6
        lda     z:t3
        ora     #1
        sta     z:t3
        bit     #4
        bne     @store
        lda     z:t6                    ; before the first non-zero digit
        bne     :+
        lda     z:t3
        bit     #2
        beq     @next
        inc     z:t2
        bra     @next
:       lda     z:t3
        ora     #4
        sta     z:t3
@store: lda     z:t3
        bit     #2
        bne     :+
        inc     z:t1
:       ldx     z:t0
        cpx     #WKN - ND - 2
        bcs     @next
        lda     z:t6
        sep     #$20
        .a8
        sta     wk,x
        rep     #$20
        .a16
        inc     z:t0
@next:  iny
        bra     @m
@mend:  lda     z:t3
        and     #1
        jeq     @bad
        jsr     @ch
        ora     #$20
        cmp     #'e'
        bne     @end
        iny
        jsr     @ch
        cmp     #'-'
        bne     :+
        inc     z:t5
        bra     :++
:       cmp     #'+'
        bne     :++
:       iny
:       jsr     @ch
        cmp     #'0'
        bcc     @bad
        cmp     #'9' + 1
        bcs     @bad
@ed:    jsr     @ch
        cmp     #'0'
        bcc     @eend
        cmp     #'9' + 1
        bcs     @eend
        sbc     #'0' - 1
        sta     z:t6
        lda     z:t4
        cmp     #1000
        bcs     :+
        asl     a
        sta     z:t7
        asl     a
        asl     a
        adc     z:t7
        adc     z:t6
        sta     z:t4
:       iny
        bra     @ed
@eend:  lda     z:t5
        beq     @end
        lda     z:t4
        eor     #$FFFF
        inc     a
        sta     z:t4
@end:   jsr     @sp
        cmp     #0
        bne     @bad
        lda     z:t3
        and     #4
        bne     :+
        ldx     #.loword(n_r)           ; all zeros
        jsr     n_zero
        clc
        rts
:       lda     z:t1                    ; the first digit's exponent: int digits - 1, or
        beq     :+                      ; -(zeros after the point + 1)
        dec     a
        bra     :++
:       lda     z:t2
        eor     #$FFFF
:       clc
        adc     z:t4
        sta     wexp
        jmp     n_norm
@bad:   sec
        rts
; the character at Y (CR, LF and TAB end the text like 0) -> A
@ch:    lda     (p1),y
        and     #$00FF
        cmp     #13
        beq     :+
        cmp     #10
        beq     :+
        cmp     #9
        bne     :++
:       lda     #0
:       rts
; skip spaces -> A = the character
@sp:    jsr     @ch
        cmp     #' '
        bne     :+
        iny
        bra     @sp
:       rts

; X = NUM -> nstr: up to 15 significant digits, fixed point while it fits (an integer part of
; up to 15 digits; at most 16 places after the point), else d.ddddddddddde-NN (12 digits).
n_fmt:  ldy     #.loword(n_f)
        jsr     n_cpy
        stz     z:t7                    ; output index
        ldx     #.loword(n_f)
        jsr     n_isz
        bne     :+
        lda     #'0'
        sta     nstr
        rts
:       lda     n_f+N_SGN
        beq     :+
        lda     #'-'
        jsr     @put
:       lda     n_f+N_EXP
        bmi     @small
        cmp     #15
        jcs     @sci
        lda     #15
        jsr     @round
        lda     z:t6                    ; (the rounding may reach 1e15)
        cmp     #15
        jcs     @sci
        ldx     #0                      ; integer digits g[0 .. e]
:       lda     g,x
        jsr     @dig
        inx
        cpx     z:t6
        bcc     :-
        beq     :-
        bra     @frac
@small: cmp     #$FFFF - 4              ; e >= -5
        bcc     @sci
        clc
        adc     #17                     ; 16 places after the point
        cmp     #15
        bcc     :+
        lda     #15
:       jsr     @round
        lda     z:t6
        bmi     :+
        ldx     #0                      ; rounded up to 1
        bra     @ints
:       lda     #'0'
        jsr     @put
        lda     #'.'
        jsr     @put
        lda     z:t6                    ; zeros after the point: -e - 1
        eor     #$FFFF
        tax
        beq     :++
:       lda     #'0'
        jsr     @put
        dex
        bne     :-
:       ldx     #0
        jsr     @last
        bra     @fdig
@ints:  lda     g,x                     ; (1 or more with the integer part)
        jsr     @dig
        inx
        cpx     z:t6
        bcc     @ints
        beq     @ints
@frac:  jsr     @last                   ; the digits after e, without trailing zeros
        cpx     z:t5
        bcs     @end
        lda     #'.'
        jsr     @put
@fdig:  cpx     z:t5
        bcs     @end
        lda     g,x
        jsr     @dig
        inx
        bra     @fdig
@end:   ldx     z:t7
        sep     #$20
        .a8
        stz     nstr,x
        rep     #$20
        .a16
        rts
@sci:   lda     #12
        jsr     @round
        lda     g
        jsr     @dig
        ldx     #1
        jsr     @last
        cpx     z:t5
        bcs     :++
        lda     #'.'
        jsr     @put
:       lda     g,x
        jsr     @dig
        inx
        cpx     z:t5
        bcc     :-
:       lda     #'e'
        jsr     @put
        lda     z:t6
        bpl     :+
        eor     #$FFFF
        inc     a
        pha
        lda     #'-'
        bra     :++
:       pha
        lda     #'+'
:       jsr     @put
        pla
        jsr     dv10
        pha
        lda     z:dq
        beq     :+
        jsr     @dig
:       pla
        jsr     @dig
        bra     @end
; t5 = the end of the significant digits (trailing zeros dropped), at least X
@last:  lda     z:t4
        sta     z:t5
:       cpx     z:t5
        bcs     :+
        ldy     z:t5
        lda     g-1,y
        and     #$00FF
        bne     :+
        dec     z:t5
        bra     :-
:       rts
@dig:   and     #$00FF
        ora     #'0'
@put:   phx
        ldx     z:t7
        sep     #$20
        .a8
        sta     nstr,x
        rep     #$20
        .a16
        inx
        stx     z:t7
        plx
        rts
; A digits of n_f, rounded -> g[0 .. A-1] (t4 = A), t6 = the exponent
@round: sta     z:t4
        ldx     #ND - 1
:       lda     n_f+N_D,x
        sta     g,x
        dex
        bpl     :-
        lda     n_f+N_EXP
        sta     z:t6
        ldx     z:t4
        lda     g,x
        and     #$00FF
        cmp     #5
        bcc     @rz
        sep     #$20
        .a8
:       dex
        bmi     @r1
        lda     g,x
        inc     a
        sta     g,x
        cmp     #10
        bcc     @rz8
        lda     #0
        sta     g,x
        bra     :-
@r1:    lda     #1
        sta     g
        rep     #$20
        .a16
        inc     z:t6
        bra     @rz
        .a8
@rz8:   rep     #$20
        .a16
@rz:    ldx     z:t4                    ; zeros after them
        sep     #$20
        .a8
:       cpx     #ND
        bcs     :+
        stz     g,x
        inx
        bra     :-
:       rep     #$20
        .a16
        rts

; ---------------------------------------------------------------- 32-bit integers
; X = NUM -> pv (u32): the integer part's low 32 bits, negated for a negative number
n_toint:
        stx     z:p1
        stz     pv
        stz     pv+2
        ldy     #N_D
        lda     (p1),y
        and     #$00FF
        beq     @out
        ldy     #N_EXP
        lda     (p1),y
        bmi     @out
        inc     a
        sta     z:t0                    ; integer digits
        ldy     #N_D
@d:     lda     pv                      ; pv = pv * 10 + digit
        sta     z:t1
        lda     pv+2
        sta     z:t2
        asl     pv
        rol     pv+2
        asl     pv
        rol     pv+2
        lda     pv
        clc
        adc     z:t1
        sta     pv
        lda     pv+2
        adc     z:t2
        sta     pv+2
        asl     pv
        rol     pv+2
        cpy     #N_D + ND
        bcs     :+
        lda     (p1),y
        and     #$00FF
        clc
        adc     pv
        sta     pv
        bcc     :+
        inc     pv+2
:       iny
        dec     z:t0
        bne     @d
        ldy     #N_SGN
        lda     (p1),y
        beq     @out
        jsr     i_neg
@out:   rts

; pv = -pv
i_neg:  lda     pv
        eor     #$FFFF
        clc
        adc     #1
        sta     pv
        lda     pv+2
        eor     #$FFFF
        adc     #0
        sta     pv+2
        rts

; pv (signed) -> n_r
n_fromint:
        lda     #10
        jsr     i_fmt
        ldx     #.loword(istr)
        jmp     n_parse

; pv in base A (2, 8, 10 signed, 16) -> istr. Keeps pv.
i_fmt:  sta     z:t0
        lda     pv
        sta     iq
        lda     pv+2
        sta     iq+2
        stz     z:t1                    ; negative (base 10)
        lda     z:t0
        cmp     #10
        bne     :+
        lda     iq+2
        bpl     :+
        inc     z:t1
        lda     iq
        eor     #$FFFF
        clc
        adc     #1
        sta     iq
        lda     iq+2
        eor     #$FFFF
        adc     #0
        sta     iq+2
:       ldx     #0                      ; digits, last first, in ib
@d:     phx
        jsr     iq_div                  ; iq /= base, A = remainder
        plx
        tay
        lda     hexd,y
        sep     #$20
        .a8
        sta     ib,x
        rep     #$20
        .a16
        inx
        lda     iq
        ora     iq+2
        bne     @d
        ldy     #0
        lda     z:t1
        beq     :+
        lda     #'-'
        sta     istr
        iny
:       dex
        lda     ib,x
        sep     #$20
        .a8
        sta     istr,y
        rep     #$20
        .a16
        iny
        cpx     #0
        bne     :-
        lda     #0
        sep     #$20
        .a8
        sta     istr,y
        rep     #$20
        .a16
        rts
; iq (u32) /= z:t0 (2-16) -> A = the remainder
iq_div: lda     #0
        ldx     #32
:       asl     iq
        rol     iq+2
        rol     a
        cmp     z:t0
        bcc     :+
        sbc     z:t0
        inc     iq
:       dex
        bne     :--
        rts

; pv = ia * ib (low 32 bits)
i_mul:  stz     pv
        stz     pv+2
        lda     ia
        sta     z:t0
        lda     ia+2
        sta     z:t1
        lda     ibv
        sta     z:t2
        lda     ibv+2
        sta     z:t3
        ldx     #32
:       lsr     z:t3
        ror     z:t2
        bcc     :+
        lda     pv
        clc
        adc     z:t0
        sta     pv
        lda     pv+2
        adc     z:t1
        sta     pv+2
:       asl     z:t0
        rol     z:t1
        dex
        bne     :--
        rts

; ia / ibv, signed, truncated -> pv = quotient, irem = remainder (the dividend's sign).
; C set: divide by zero.
i_div:  lda     ibv
        ora     ibv+2
        bne     :+
        sec
        rts
:       stz     z:t4                    ; bit 0: quotient negative, bit 1: remainder negative
        lda     ia+2
        bpl     :+
        lda     #3
        sta     z:t4
        ldx     #.loword(ia)
        jsr     neg32
:       lda     ibv+2
        bpl     :+
        lda     z:t4
        eor     #1
        sta     z:t4
        ldx     #.loword(ibv)
        jsr     neg32
:       stz     irem                    ; unsigned shift-subtract
        stz     irem+2
        lda     ia
        sta     pv
        lda     ia+2
        sta     pv+2
        ldx     #32
@l:     asl     pv
        rol     pv+2
        rol     irem
        rol     irem+2
        lda     irem
        sec
        sbc     ibv
        tay
        lda     irem+2
        sbc     ibv+2
        bcc     :+
        sta     irem+2
        sty     irem
        inc     pv
:       dex
        bne     @l
        lda     z:t4
        and     #1
        beq     :+
        jsr     i_neg
:       lda     z:t4
        and     #2
        beq     :+
        ldx     #.loword(irem)
        jsr     neg32
:       clc
        rts
; the u32 at X negated
neg32:  lda     a:0,x
        eor     #$FFFF
        clc
        adc     #1
        sta     a:0,x
        lda     a:2,x
        eor     #$FFFF
        adc     #0
        sta     a:2,x
        rts

        .segment "RODATA"
mtab:                                   ; a * b for a, b = 0-9 (index 10 a + b)
        .repeat 100, I
        .byte   (I / 10) * (I .mod 10)
        .endrepeat
hexd:   .byte   "0123456789ABCDEF"

        .segment "BSS"
n_a:    .res    NSZ
n_b:    .res    NSZ
n_r:    .res    NSZ
n_f:    .res    NSZ
n_err:  .res    2
wexp:   .res    2
wsgn:   .res    2
wk:     .res    WKN
wk2:    .res    WKN
pw:     .res    2 * (2 * ND + 1)
ra:     .res    ND + 2
rb:     .res    ND + 2
rr:     .res    RL
rp:     .res    RL
ry:     .res    RL
g:      .res    ND + 2
nstr:   .res    40
pv:     .res    4
ia:     .res    4
ibv:    .res    4
irem:   .res    4
iq:     .res    4
ib:     .res    34
istr:   .res    36
