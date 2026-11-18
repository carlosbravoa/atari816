; bas_fp.s - floating point: decimal numbers of 12 significant digits (BCD).
;
; A float (type T_FLT) in the accumulator, on the value stack, in a variable or a tagged
; array element: ft = (e + 128) << 8 | T_FLT | sign (bit 0); flen = the digits d1 d2 d3 d4,
; fhi = d5..d8, flo = d9..d12 (BCD), d1 <> 0. The value is 0.d1d2...d12 x 10^e, e -98..100
; (1E-99 <= |x| < 1E+100). A float is never 0: a zero result is the integer 0, and so is a
; result below 1E-99. Above the range: Overflow.
;
; The arithmetic works on two unpacked registers in the direct page, FA and FB: 16 digits
; m0..m3 (fa+6 = m3 = d1..d4, fa+0 = m0: four guard digits), the exponent fa_e, the sign
; fa_s (0 / 1); fstk is the sticky flag (non-zero: digits were lost below m0). fp_add,
; fp_mul, fp_div and fp_sqrt leave the exact result's first 16 digits and the sticky flag,
; and fp_rnd rounds that to 12 digits, half to even: every operation is correctly rounded.
; The digit arithmetic runs in decimal mode (SED: ADC / SBC add 4 BCD digits at a time); it
; is switched off (CLD) before anything that can raise an error or call the kernel.
;
; Registers are addressed as fa+k,x with X = FAX (0) or FBX. Routines are a16 i16 and
; clobber A, X, Y.

        .segment "CODE"
        .a16
        .i16
FAX     = 0
FBX     = fb - fa

; ---------------------------------------------------------------- unpacking, packing
; acc (a number) -> register X
fp_unp: lda     ft
        bne     @f
        lda     flo
        sta     z:fw
        lda     fhi
        sta     z:fw+2
        bra     fp_i2fw
@f:     stz     fa,x
        lda     flo
        sta     fa+2,x
        lda     fhi
        sta     fa+4,x
        lda     flen
        sta     fa+6,x
        lda     ft
        and     #1
        sta     fa_s,x
        lda     ft
        xba
        and     #$00FF
        sec
        sbc     #128
        sta     fa_e,x
        rts

; the packed number at Y (our bank) -> register X
fp_unpm:
        lda     a:0,y
        bne     @f
        lda     a:2,y
        sta     z:fw
        lda     a:4,y
        sta     z:fw+2
        bra     fp_i2fw
@f:     stz     fa,x
        lda     a:2,y
        sta     fa+2,x
        lda     a:4,y
        sta     fa+4,x
        lda     a:6,y
        sta     fa+6,x
        lda     a:0,y
        and     #1
        sta     fa_s,x
        lda     a:0,y
        xba
        and     #$00FF
        sec
        sbc     #128
        sta     fa_e,x
        rts

; the signed 32-bit fw -> register X: the BCD of 2^k added for each bit k that is set
fp_i2fw:
        stz     fa_s,x
        stz     fa,x
        stz     fa+2,x
        stz     fa+4,x
        stz     fa+6,x
        lda     z:fw+2
        bpl     :+
        inc     fa_s,x
        lda     #0
        sec
        sbc     z:fw
        sta     z:fw
        lda     #0
        sbc     z:fw+2
        sta     z:fw+2
:       ora     z:fw
        beq     @x                      ; zero
        lda     #12                     ; value = the 12-digit integer m3 m2 m1
        sta     fa_e,x
        ldy     #0                      ; (Y: the power's offset in p2bcd)
@l:     lsr     z:fw+2
        ror     z:fw
        bcc     @n
        sed
        clc
        lda     fa+2,x
        adc     p2bcd,y
        sta     fa+2,x
        lda     fa+4,x
        adc     p2bcd+2,y
        sta     fa+4,x
        lda     fa+6,x
        adc     p2bcd+4,y
        sta     fa+6,x
        cld
@n:     iny
        iny
        iny
        iny
        iny
        iny
        lda     z:fw
        ora     z:fw+2
        bne     @l
        jmp     fp_normx
@x:     rts

; register X normalized: d1 <> 0 (zero stays zero)
fp_normx:
@w:     lda     fa+6,x
        bne     @b
        lda     fa+4,x                  ; a word of zeros
        ora     fa+2,x
        ora     fa,x
        beq     @x
        lda     fa+4,x
        sta     fa+6,x
        lda     fa+2,x
        sta     fa+4,x
        lda     fa,x
        sta     fa+2,x
        stz     fa,x
        lda     fa_e,x
        sec
        sbc     #4
        sta     fa_e,x
        bra     @w
@b:     cmp     #$0100                  ; a byte of zeros
        bcs     @n
        lda     fa+5,x
        sta     fa+6,x
        lda     fa+3,x
        sta     fa+4,x
        lda     fa+1,x
        sta     fa+2,x
        lda     fa,x
        xba
        and     #$FF00
        sta     fa,x
        dec     fa_e,x
        dec     fa_e,x
        lda     fa+6,x
@n:     cmp     #$1000                  ; a digit
        bcs     @x
        ldy     #4
:       asl     fa,x
        rol     fa+2,x
        rol     fa+4,x
        rol     fa+6,x
        dey
        bne     :-
        dec     fa_e,x
@x:     rts

; FA rounded to 12 digits (half to even, by m0 and fstk); m0 and fstk cleared. Overflow
; above 1E+100; below 1E-99: zero.
fp_rnd: lda     fa+6
        beq     @zero
        lda     fa
        cmp     #$5000
        bcc     @dn
        bne     @up
        lda     z:fstk
        bne     @up
        lda     fa+2                    ; a tie: to the even digit
        lsr     a
        bcc     @dn
@up:    sed
        clc
        lda     fa+2
        adc     #1
        sta     fa+2
        lda     fa+4
        adc     #0
        sta     fa+4
        lda     fa+6
        adc     #0
        sta     fa+6
        cld
        bcc     @dn
        lda     #$1000
        sta     fa+6
        inc     fa_e
@dn:    stz     fa
        stz     z:fstk
        lda     fa_e
        bmi     @neg
        cmp     #101
        bcs     @ovf
        rts
@neg:   cmp     #$10000 - 98
        bcs     @ok
@zero:  stz     fa
        stz     fa+2
        stz     fa+4
        stz     fa+6
        stz     fa_s
        stz     z:fstk
@ok:    rts
@ovf:   err     E_OVF

; FA rounded -> acc (zero: the integer 0)
fp_pack:
        jsr     fp_rnd
        lda     fa+6
        beq     @z
        sta     flen
        lda     fa+4
        sta     fhi
        lda     fa+2
        sta     flo
        lda     fa_e
        clc
        adc     #128
        xba
        ora     fa_s
        ora     #T_FLT
        sta     ft
        rts
@z:     stz     ft
        stz     flo
        stz     fhi
        rts

; FA rounded -> the packed number at X (our bank)
fp_stm: phx
        jsr     fp_rnd
        plx
        lda     fa+6
        beq     @z
        sta     a:6,x
        lda     fa+4
        sta     a:4,x
        lda     fa+2
        sta     a:2,x
        lda     fa_e
        clc
        adc     #128
        xba
        ora     fa_s
        ora     #T_FLT
        sta     a:0,x
        rts
@z:     stz     a:0,x
        stz     a:2,x
        stz     a:4,x
        stz     a:6,x
        rts

; FA = FB, FB = FA, FA = 0
fp_cpba:
        ldx     #10
:       lda     fb,x
        sta     fa,x
        dex
        dex
        bpl     :-
        rts
fp_cpab:
        ldx     #10
:       lda     fa,x
        sta     fb,x
        dex
        dex
        bpl     :-
        rts
fp_zero:
        stz     fa
        stz     fa+2
        stz     fa+4
        stz     fa+6
        stz     fa_s
        rts
fp_swap:
        ldx     #10
:       lda     fa,x
        ldy     fb,x
        sta     fb,x
        sty     fa,x
        dex
        dex
        bpl     :-
        rts

; FB shifted right by A digits; digits shifted out set fstk
fp_shrb:
        cmp     #17
        bcc     @go
        lda     fb
        ora     fb+2
        ora     fb+4
        ora     fb+6
        beq     :+
        sta     z:fstk
:       stz     fb
        stz     fb+2
        stz     fb+4
        stz     fb+6
        rts
@go:    tay
@w:     cpy     #4
        bcc     @b
        lda     fb
        beq     :+
        sta     z:fstk
:       lda     fb+2
        sta     fb
        lda     fb+4
        sta     fb+2
        lda     fb+6
        sta     fb+4
        stz     fb+6
        dey
        dey
        dey
        dey
        bra     @w
@b:     cpy     #2
        bcc     @n
        lda     fb
        and     #$00FF
        beq     :+
        sta     z:fstk
:       lda     fb+1
        sta     fb
        lda     fb+3
        sta     fb+2
        lda     fb+5
        sta     fb+4
        lda     fb+7
        and     #$00FF
        sta     fb+6
        dey
        dey
@n:     cpy     #0
        beq     @x
        lda     fb
        and     #$000F
        beq     :+
        sta     z:fstk
:       ldy     #4
:       lsr     fb+6
        ror     fb+4
        ror     fb+2
        ror     fb
        dey
        bne     :-
@x:     rts

; ---------------------------------------------------------------- + - * /
; FA = FA - FB, FA = FA + FB
fp_sub: lda     fb_s
        eor     #1
        sta     fb_s
fp_add: stz     z:fstk
        lda     fb+6
        bne     :+
        rts
:       lda     fa+6
        bne     :+
        jmp     fp_cpba
:       lda     fa_e                    ; FA has the larger exponent
        sec
        sbc     fb_e
        bpl     :+
        jsr     fp_swap
        lda     fa_e
        sec
        sbc     fb_e
:       jsr     fp_shrb                 ; FB aligned
        lda     fa_s
        cmp     fb_s
        bne     @sub
        sed
        clc
        lda     fa
        adc     fb
        sta     fa
        lda     fa+2
        adc     fb+2
        sta     fa+2
        lda     fa+4
        adc     fb+4
        sta     fa+4
        lda     fa+6
        adc     fb+6
        sta     fa+6
        cld
        bcc     @x
        lda     fa                      ; a carry: one digit to the right
        and     #$000F
        beq     :+
        sta     z:fstk
:       ldy     #4
:       lsr     fa+6
        ror     fa+4
        ror     fa+2
        ror     fa
        dey
        bne     :-
        lda     fa+6
        ora     #$1000
        sta     fa+6
        inc     fa_e
@x:     rts
@sub:   sed                             ; (sticky: a little more is taken away, the
        lda     z:fstk                  ; sticky flag stays: the exact value is just
        beq     :+                      ; above the digits)
        clc
        bra     :++
:       sec
:       lda     fa
        sbc     fb
        sta     fa
        lda     fa+2
        sbc     fb+2
        sta     fa+2
        lda     fa+4
        sbc     fb+4
        sta     fa+4
        lda     fa+6
        sbc     fb+6
        sta     fa+6
        bcs     @pos
        sec                             ; FB was larger (same exponent): negated
        lda     #0
        sbc     fa
        sta     fa
        lda     #0
        sbc     fa+2
        sta     fa+2
        lda     #0
        sbc     fa+4
        sta     fa+4
        lda     #0
        sbc     fa+6
        sta     fa+6
        cld
        lda     fb_s
        sta     fa_s
        bra     :+
@pos:   cld
:       ldx     #FAX
        jmp     fp_normx

; FA = FA * FB: the product of FA's 12 digits and FB's 16 (its guard digits too, when not 0)
; from a table of A * 1..9, the multiplier's digits added at byte offsets: the low digits
; of each byte in mp1, the high ones in mp2 (then shifted one digit).
fp_mul: stz     z:fstk
        lda     fa+6
        bne     :+
        rts
:       lda     fb+6
        bne     :+
        jmp     fp_zero
:       lda     fb                      ; the shorter one multiplies (FB: its zero bytes
        bne     :+                      ; cost nothing; FA's guard digits are not used)
        lda     fb+2
        beq     :+
        lda     fa
        ora     fa+2
        bne     :+
        jsr     fp_swap
:       lda     fa_s
        eor     fb_s
        sta     fa_s
        lda     fa_e
        clc
        adc     fb_e
        sta     fa_e
        lda     fa+2                    ; mt + 8 (k - 1) = A * k, made when first needed
        sta     mt
        lda     fa+4
        sta     mt+2
        lda     fa+6
        sta     mt+4
        stz     mt+6
        stz     mt_n                    ; (the last one made: (k - 1) * 8)
        ldx     #16
:       stz     mp1,x
        stz     mp2,x
        dex
        dex
        bpl     :-
        stz     mp_h
        ldx     #0                      ; the multiplier's bytes, the lowest first
        lda     fb
        bne     @b
        ldx     #2
@b:     lda     fb,x
        and     #$00FF
        jeq     @n
        and     #$000F
        beq     @h
        dec     a
        asl     a
        asl     a
        asl     a
        tay
        cpy     mt_n
        beq     :+
        bcc     :+
        jsr     mt_make
:       sed
        clc
        lda     mp1,x
        adc     mt,y
        sta     mp1,x
        lda     mp1+2,x
        adc     mt+2,y
        sta     mp1+2,x
        lda     mp1+4,x
        adc     mt+4,y
        sta     mp1+4,x
        lda     mp1+6,x
        adc     mt+6,y
        sta     mp1+6,x
        lda     mp1+8,x
        adc     #0
        sta     mp1+8,x
        cld
@h:     lda     fb,x
        and     #$00F0
        beq     @n
        sta     mp_h
        lsr     a
        sec
        sbc     #8
        tay
        cpy     mt_n
        beq     :+
        bcc     :+
        jsr     mt_make
:       sed
        clc
        lda     mp2,x
        adc     mt,y
        sta     mp2,x
        lda     mp2+2,x
        adc     mt+2,y
        sta     mp2+2,x
        lda     mp2+4,x
        adc     mt+4,y
        sta     mp2+4,x
        lda     mp2+6,x
        adc     mt+6,y
        sta     mp2+6,x
        lda     mp2+8,x
        adc     #0
        sta     mp2+8,x
        cld
@n:     inx
        cpx     #8
        jcc     @b
        lda     mp_h                    ; (no high digits: mp1 alone)
        jeq     @one
        ldy     #4                      ; mp2 * 10
:       asl     mp2
        rol     mp2+2
        rol     mp2+4
        rol     mp2+6
        rol     mp2+8
        rol     mp2+10
        rol     mp2+12
        dey
        bne     :-
        sed                             ; the 28 digits: the first 16 -> FA
        clc
        lda     mp1
        adc     mp2
        sta     mp1
        lda     mp1+2
        adc     mp2+2
        sta     mp1+2
        lda     mp1+4
        adc     mp2+4
        sta     mp1+4
        lda     mp1+6
        adc     mp2+6
        sta     fa
        lda     mp1+8
        adc     mp2+8
        sta     fa+2
        lda     mp1+10
        adc     mp2+10
        sta     fa+4
        lda     mp1+12
        adc     mp2+12
        sta     fa+6
        cld
        lda     mp1
        ora     mp1+2
        ora     mp1+4
        sta     z:fstk
        ldx     #FAX
        jmp     fp_normx
@one:   lda     mp1+6
        sta     fa
        lda     mp1+8
        sta     fa+2
        lda     mp1+10
        sta     fa+4
        lda     mp1+12
        sta     fa+6
        lda     mp1
        ora     mp1+2
        ora     mp1+4
        sta     z:fstk
        ldx     #FAX
        jmp     fp_normx
; the multiples A * k up to mt[Y] (k - 1 = Y / 8) made (keeps X, Y)
mt_make:
        phx
        ldx     mt_n
        sed
@l:     clc
        lda     mt,x
        adc     mt
        sta     mt+8,x
        lda     mt+2,x
        adc     mt+2
        sta     mt+10,x
        lda     mt+4,x
        adc     mt+4
        sta     mt+12,x
        lda     mt+6,x
        adc     #0
        sta     mt+14,x
        txa
        cld
        clc
        adc     #8
        sed
        tax
        sty     mt_n
        cmp     mt_n
        bcc     @l
        cld
        plx
        rts

; FA = FA / FB (Division by zero): long division, 15 quotient digits: q0, then pairs (the
; remainder shifted a byte). Each digit: the largest multiple of the divisor (dvt: D * 1..9,
; then D * 10, 20 .. 90) not above the remainder, by a binary search, subtracted.
fp_div: lda     fb+6
        bne     :+
        err     E_DIV0
:       stz     z:fstk
        lda     fa+6
        bne     :+
        rts
:       lda     fa_s
        eor     fb_s
        sta     fa_s
        lda     fa_e
        sec
        sbc     fb_e
        inc     a
        sta     fa_e
        lda     fa+2                    ; R = A
        sta     z:dr
        lda     fa+4
        sta     z:dr+2
        lda     fa+6
        sta     z:dr+4
        stz     z:dr+6
        lda     fb+2                    ; dvt[0] = D, dvt[72] = D * 10
        sta     dvt
        sta     dvt+72
        lda     fb+4
        sta     dvt+2
        sta     dvt+74
        lda     fb+6
        sta     dvt+4
        sta     dvt+76
        stz     dvt+6
        stz     dvt+78
        ldy     #4
:       asl     dvt+72
        rol     dvt+74
        rol     dvt+76
        rol     dvt+78
        dey
        bne     :-
        ldx     #0                      ; the multiples
@t:     sed
        clc
        lda     dvt,x
        adc     dvt
        sta     dvt+8,x
        lda     dvt+2,x
        adc     dvt+2
        sta     dvt+10,x
        lda     dvt+4,x
        adc     dvt+4
        sta     dvt+12,x
        lda     dvt+6,x
        adc     #0
        sta     dvt+14,x
        clc
        lda     dvt+72,x
        adc     dvt+72
        sta     dvt+80,x
        lda     dvt+74,x
        adc     dvt+74
        sta     dvt+82,x
        lda     dvt+76,x
        adc     dvt+76
        sta     dvt+84,x
        lda     dvt+78,x
        adc     dvt+78
        sta     dvt+86,x
        cld
        txa
        clc
        adc     #8
        tax
        cmp     #64
        bcc     @t
        lda     fa_e                    ; (digits 0 q0 q1 .. q14: normalized below)
        inc     a
        sta     fa_e
        lda     #0                      ; q0
        jsr     dv_dig
        xba
        sta     z:fw
        jsr     dv_pair
        ora     z:fw
        sta     fa+6
        jsr     dv_pair
        xba
        sta     z:fw
        jsr     dv_pair
        ora     z:fw
        sta     fa+4
        jsr     dv_pair
        xba
        sta     z:fw
        jsr     dv_pair
        ora     z:fw
        sta     fa+2
        jsr     dv_pair
        xba
        sta     z:fw
        jsr     dv_pair
        ora     z:fw
        sta     fa
        lda     z:dr
        ora     z:dr+2
        ora     z:dr+4
        ora     z:dr+6
        sta     z:fstk
        ldx     #FAX
        jmp     fp_normx
; R * 100, then two digits (against D * 10 k, then D k) -> A = the BCD byte
dv_pair:
        lda     z:dr+5
        sta     z:dr+6
        lda     z:dr+3
        sta     z:dr+4
        lda     z:dr+1
        sta     z:dr+2
        lda     z:dr
        xba
        and     #$FF00
        sta     z:dr
        lda     #72
        jsr     dv_dig
        asl     a
        asl     a
        asl     a
        asl     a
        sta     dv_h
        lda     #0
        jsr     dv_dig
        ora     dv_h
        rts

; a quotient digit: the largest k with dvt[A + 8 (k - 1)] <= R (or 0); R -= it -> A = k.
; A binary search; dv_ge compares the lower words when the first ones are equal.
.macro  dvge
        lda     z:dr+6
        cmp     dvt+6,y
        bne     *+5
        jsr     dv_ge
.endmacro
dv_dig: clc
        adc     #32                     ; 5?
        tay
        dvge
        bcs     @hi
        tya                             ; 3?
        sbc     #16 - 1
        tay
        dvge
        bcs     @k34
        tya                             ; 2?
        sbc     #8 - 1
        tay
        dvge
        bcs     @k2
        tya                             ; 1?
        sbc     #8 - 1
        tay
        dvge
        bcs     @k1
        lda     #0
        rts
@k1:    lda     #1
        brl     @sub
@k2:    lda     #2
        brl     @sub
@k34:   tya                             ; 4?
        adc     #8 - 1
        tay
        dvge
        bcs     @k4
        tya
        sbc     #8 - 1
        tay
        lda     #3
        bra     @sub
@k4:    lda     #4
        bra     @sub
@hi:    tya                             ; 7?
        adc     #16 - 1
        tay
        dvge
        bcs     @k789
        tya                             ; 6?
        sbc     #8 - 1
        tay
        dvge
        bcs     @k6
        tya
        sbc     #8 - 1
        tay
        lda     #5
        bra     @sub
@k6:    lda     #6
        bra     @sub
@k789:  tya                             ; 8?
        adc     #8 - 1
        tay
        dvge
        bcs     :+
        tya
        sbc     #8 - 1
        tay
        lda     #7
        bra     @sub
:       tya                             ; 9?
        adc     #8 - 1
        tay
        dvge
        bcs     :+
        tya
        sbc     #8 - 1
        tay
        lda     #8
        bra     @sub
:       lda     #9
@sub:   pha                             ; R -= dvt[Y]
        sed
        sec
        lda     z:dr
        sbc     dvt,y
        sta     z:dr
        lda     z:dr+2
        sbc     dvt+2,y
        sta     z:dr+2
        lda     z:dr+4
        sbc     dvt+4,y
        sta     z:dr+4
        lda     z:dr+6
        sbc     dvt+6,y
        sta     z:dr+6
        cld
        pla
        rts
; (the first words equal) R >= dvt[Y]? -> C
dv_ge:  lda     z:dr+4
        cmp     dvt+4,y
        bne     :+
        lda     z:dr+2
        cmp     dvt+2,y
        bne     :+
        lda     z:dr
        cmp     dvt,y
:       rts

; the digits qd[X..X+15] -> FA's mantissa
qd_fa:  jsr     qd_w4
        sta     fa+6
        jsr     qd_w4
        sta     fa+4
        jsr     qd_w4
        sta     fa+2
        jsr     qd_w4
        sta     fa
        rts
; 4 digits qd[X..] -> A
qd_w4:  lda     #0
        ldy     #4
:       asl     a
        asl     a
        asl     a
        asl     a
        sta     z:fw
        lda     qd,x
        and     #$000F
        ora     z:fw
        inx
        dey
        bne     :-
        rts

; FA vs FB -> A = 1 (FA < FB), 2 (equal), 4 (greater)
fp_cmp: lda     fa+6
        bne     @a
        lda     fb+6
        bne     :+
        lda     #2
        rts
:       lda     fb_s                    ; 0 vs B
        bne     @gt
@lt:    lda     #1
        rts
@a:     lda     fb+6
        bne     @b
        lda     fa_s                    ; A vs 0
        bne     @lt
@gt:    lda     #4
        rts
@b:     lda     fa_s
        cmp     fb_s
        beq     :+
        lda     fa_s                    ; the signs differ
        bne     @lt
        bra     @gt
:       lda     fa_e                    ; the magnitudes
        cmp     fb_e
        bne     @e
        lda     fa+6
        cmp     fb+6
        bne     @m
        lda     fa+4
        cmp     fb+4
        bne     @m
        lda     fa+2
        cmp     fb+2
        bne     @m
        lda     fa
        cmp     fb
        bne     @m
        lda     #2
        rts
@e:     sec
        sbc     fb_e
        bmi     @sm
        bra     @bg
@m:     bcc     @sm
@bg:    lda     fa_s                    ; |A| > |B|
        bne     @lt
        bra     @gt
@sm:    lda     fa_s
        bne     @gt
        bra     @lt

; ---------------------------------------------------------------- integers
; FA -> fw (signed 32-bit): A = 0 truncated, 1 rounded (halves away from 0), 2 floor. C set:
; out of range. FB = the integer part's digits (fb+2..fb+6) and the first four of the
; fraction (fb), fstk the rest (both 0: FA was an integer).
fp_toint:
        sta     ti_md
        stz     z:fw
        stz     z:fw+2
        lda     fa+6
        bne     :+
        stz     fb
        stz     z:fstk
        clc
        rts
:       lda     fa_e
        bmi     :+
        cmp     #11
        bcc     :+
        sec
        rts
:       jsr     fp_cpab
        stz     z:fstk
        lda     #12
        sec
        sbc     fa_e
        jsr     fp_shrb
        lda     ti_md
        beq     @t
        cmp     #1
        bne     @fl
        lda     fb                      ; round: a fraction >= .5
        cmp     #$5000
        bcc     @t
        bra     @inc
@fl:    lda     fa_s                    ; floor: a negative number with a fraction
        beq     @t
        lda     fb
        ora     z:fstk
        beq     @t
@inc:   sed
        clc
        lda     fb+2
        adc     #1
        sta     fb+2
        lda     fb+4
        adc     #0
        sta     fb+4
        lda     fb+6
        adc     #0
        sta     fb+6
        cld
@t:     lda     fb+6                    ; at most 2147483647 (2147483648 if negative)
        cmp     #$0021
        bcc     @ok
        bne     @ovf
        lda     fb+4
        cmp     #$4748
        bcc     @ok
        bne     @ovf
        lda     fb+2
        cmp     #$3648
        bcc     @ok
        bne     @ovf
        lda     fa_s
        beq     @ovf
@ok:    lda     fb+2                    ; hi * 10^8 + mid * 10^4 + lo
        jsr     bcd2bin
        sta     z:fw
        lda     fb+4
        jsr     bcd2bin
        beq     :+
        ldx     #10000
        jsr     umul16
        clc
        adc     z:fw
        sta     z:fw
        txa
        adc     z:fw+2
        sta     z:fw+2
:       lda     fb+6
        jsr     bcd2bin
        beq     :+
        pha
        ldx     #$E100                  ; 10^8 = $05F5E100
        jsr     umul16
        clc
        adc     z:fw
        sta     z:fw
        txa
        adc     z:fw+2
        sta     z:fw+2
        pla
        ldx     #$05F5
        jsr     umul16
        clc
        adc     z:fw+2
        sta     z:fw+2
:       lda     fa_s
        beq     :+
        lda     #0
        sec
        sbc     z:fw
        sta     z:fw
        lda     #0
        sbc     z:fw+2
        sta     z:fw+2
:       clc
        rts
@ovf:   sec
        rts

; A = 4 BCD digits -> A = their value
bcd2bin:
        sta     bb_w
        xba
        and     #$00FF
        jsr     bcd8
        asl     a                       ; * 100 = * 4 + * 32 + * 64
        asl     a
        sta     bb_t
        asl     a
        asl     a
        asl     a
        sta     bb_u
        asl     a
        clc
        adc     bb_u
        adc     bb_t
        sta     bb_t
        lda     bb_w
        and     #$00FF
        jsr     bcd8
        clc
        adc     bb_t
        rts
; A = a BCD byte -> its value (b - 6 * (b >> 4))
bcd8:   sta     bb_v
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     bb_u
        asl     a
        adc     bb_u
        asl     a
        eor     #$FFFF
        sec
        adc     bb_v
        rts

; acc (a number) -> an integer, rounded (Overflow beyond 32 bits)
acc_round:
        lda     ft
        bne     :+
        rts
:       ldx     #FAX
        jsr     fp_unp
        lda     #1
        jsr     fp_toint
        bcc     :+
        err     E_OVF
:       lda     z:fw
        sta     flo
        lda     z:fw+2
        sta     fhi
        stz     ft
        rts

; acc: a float that is a whole number of 32 bits becomes an integer
fp_demote:
        lda     ft
        cmp     #T_FLT
        bcc     @x
        xba
        and     #$00FF
        cmp     #128 + 11
        bcs     @x
        cmp     #128 + 1
        bcc     @x
        ldx     #FAX
        jsr     fp_unp
        lda     #0
        jsr     fp_toint
        bcs     @x
        lda     fb
        ora     z:fstk
        bne     @x
        lda     z:fw
        sta     flo
        lda     z:fw+2
        sta     fhi
        stz     ft
@x:     rts

; FA rounded to its first p = A digits (A signed): X = 0 truncated, 1 halves away from 0,
; 2 floor. The value: the kept digits as an integer * 10^(e - p).
fp_rdig:
        stx     ti_md
        sta     rd_p
        lda     fa+6
        beq     @x
        lda     rd_p
        bmi     :+
        cmp     #12
        bcs     @x                      ; all 12 digits kept
:       jsr     fp_cpab
        stz     z:fstk
        lda     #12
        sec
        sbc     rd_p
        jsr     fp_shrb
        lda     ti_md
        beq     @t
        cmp     #1
        bne     @fl
        lda     fb
        cmp     #$5000
        bcc     @t
        bra     @inc
@fl:    lda     fa_s
        beq     @t
        lda     fb
        ora     z:fstk
        beq     @t
@inc:   sed
        clc
        lda     fb+2
        adc     #1
        sta     fb+2
        lda     fb+4
        adc     #0
        sta     fb+4
        lda     fb+6
        adc     #0
        sta     fb+6
        cld
@t:     stz     fa
        lda     fb+2
        sta     fa+2
        lda     fb+4
        sta     fa+4
        lda     fb+6
        sta     fa+6
        lda     fa_e
        clc
        adc     #12
        sec
        sbc     rd_p
        sta     fa_e
        stz     z:fstk
        ldx     #FAX
        jmp     fp_normx
@x:     rts

; ---------------------------------------------------------------- text
; the float in acc -> X = its text (numbuf), A = its length; A = significant digits (10:
; PRINT, STR$; 12: LIST, so that the text reads back as the same number). Trailing zeros
; dropped; 0.0001 <= |x| < 1E10 as a plain number, else d.dddE+nn.
fp_fmt: sta     fm_nd
        ldx     #FAX
        jsr     fp_unp
        lda     fm_nd
        cmp     #12
        bcs     @dig
        sed                             ; 10 digits, rounded (halves up)
        clc
        lda     fa+2
        adc     #$0050
        sta     fa+2
        lda     fa+4
        adc     #0
        sta     fa+4
        lda     fa+6
        adc     #0
        sta     fa+6
        cld
        bcc     :+
        lda     #$1000
        sta     fa+6
        inc     fa_e
:       lda     fa+2
        and     #$FF00
        sta     fa+2
@dig:   ldx     #0
        lda     fa+6
        jsr     @w4
        lda     fa+4
        jsr     @w4
        lda     fa+2
        jsr     @w4
        ldx     #12                     ; the digits without trailing zeros
:       lda     fmtd-1,x
        and     #$00FF
        cmp     #'0'
        bne     :+
        dex
        bne     :-
:       stx     fm_nd
        ldy     #0
        lda     fa_s
        beq     :+
        lda     #'-'
        jsr     @pc
:       lda     fa_e
        dec     a
        sta     fm_x                    ; x = d.ddd * 10^fm_x
        bmi     @neg
        cmp     #10
        bcs     @exp
        ldx     #0                      ; ddd.ddd
:       jsr     @dg
        cpx     fm_x
        beq     :+
        inx
        bra     :-
:       inx
        cpx     fm_nd
        jcs     @end
        lda     #'.'
        jsr     @pc
:       jsr     @dg
        inx
        cpx     fm_nd
        bcc     :-
        brl     @end
@neg:   cmp     #$10000 - 4
        bcc     @exp
        lda     #'0'                    ; 0.000ddd
        jsr     @pc
        lda     #'.'
        jsr     @pc
        lda     fm_x
:       inc     a
        beq     :+
        pha
        lda     #'0'
        jsr     @pc
        pla
        bra     :-
:       ldx     #0
:       jsr     @dg
        inx
        cpx     fm_nd
        bcc     :-
        bra     @end
@exp:   ldx     #0                      ; d.dddE+nn
        jsr     @dg
        inx
        cpx     fm_nd
        bcs     @e
        lda     #'.'
        jsr     @pc
:       jsr     @dg
        inx
        cpx     fm_nd
        bcc     :-
@e:     lda     #'E'
        jsr     @pc
        lda     fm_x
        bpl     :+
        eor     #$FFFF
        inc     a
        sta     fm_x
        lda     #'-'
        bra     :++
:       lda     #'+'
:       jsr     @pc
        lda     fm_x
        cmp     #100                    ; (1E+100: rounded up to 10 digits)
        bcc     :+
        lda     #'1'
        jsr     @pc
        lda     fm_x
        sbc     #100
:       ldx     #'0'
:       cmp     #10
        bcc     :+
        sbc     #10
        inx
        bra     :-
:       pha
        txa
        jsr     @pc
        pla
        ora     #'0'
        jsr     @pc
@end:   lda     #0
        sta     numbuf,y
        tya
        ldx     #.loword(numbuf)
        rts
; the digit X (or '0' past the digits)
@dg:    lda     #'0'
        cpx     fm_nd
        bcs     @pc
        lda     fmtd,x
; the character A -> numbuf[Y++]
@pc:    sta     numbuf,y
        iny
        rts
; 4 BCD digits A -> fmtd[X..X+3] (ASCII)
@w4:    sta     fm_w
        ldy     #4
:       lda     #0
        asl     fm_w
        rol     a
        asl     fm_w
        rol     a
        asl     fm_w
        rol     a
        asl     fm_w
        rol     a
        ora     #'0'
        sta     fmtd,x
        inx
        dey
        bne     :-
        rts

; the decimal number at bp + Y (pn_max: the end) with '.' or an exponent, or too large for
; an integer (parse_num: the sign done, pn_neg) -> acc, Y past it; C set: no digits
fp_parse:
        stz     fa
        stz     fa+2
        stz     fa+4
        stz     fa+6
        stz     z:fstk
        stz     pn_nd
        stz     pn_dx
        stz     pn_cnt
@ip:    jsr     pn_ch
        jsr     tk_isdigit
        bcc     @dot
        inc     pn_cnt
        sbc     #'0'
        bne     :+
        ldx     pn_nd                   ; a leading zero
        beq     @in
:       jsr     @put
        inc     pn_dx
@in:    iny
        bra     @ip
@dot:   cmp     #'.'
        bne     @ex
        iny
@fp:    jsr     pn_ch
        jsr     tk_isdigit
        bcc     @ex
        inc     pn_cnt
        sbc     #'0'
        bne     :+
        ldx     pn_nd
        bne     :+
        dec     pn_dx                   ; 0.00ddd
        bra     @fn
:       jsr     @put
@fn:    iny
        bra     @fp
@ex:    lda     pn_cnt
        bne     :+
        sec
        rts
:       stz     pn_ex
        jsr     pn_ch
        and     #$00DF
        cmp     #'E'
        bne     @val
        jsr     pn_isexp
        bcc     @val
        iny
        stz     pn_esg
        jsr     pn_ch
        cmp     #'+'
        beq     :+
        cmp     #'-'
        bne     @ed
        inc     pn_esg
:       iny
@ed:    jsr     pn_ch
        jsr     tk_isdigit
        bcc     :++
        sbc     #'0'
        sta     pn_d
        lda     pn_ex
        cmp     #1000
        bcs     :+
        asl     a
        sta     pn_ex
        asl     a
        asl     a
        adc     pn_ex
        adc     pn_d
        sta     pn_ex
:       iny
        bra     @ed
:       lda     pn_esg
        beq     @val
        lda     #0
        sec
        sbc     pn_ex
        sta     pn_ex
@val:   phy
        lda     pn_nd
        beq     @zero
        lda     pn_dx
        clc
        adc     pn_ex
        sta     fa_e
        lda     pn_neg
        and     #1
        sta     fa_s
        jsr     fp_pack
        jsr     fp_demote
        ply
        clc
        rts
@zero:  stz     ft
        stz     flo
        stz     fhi
        ply
        clc
        rts
; the digit A at mantissa position pn_nd (beyond 16: the sticky flag)
@put:   phy
        ldx     pn_nd
        cpx     #16
        bcc     :+
        tsb     z:fstk
        ply
        rts
:       sta     pn_d
        txa
        lsr     a
        lsr     a
        asl     a
        eor     #6
        tax                             ; the word: 6 - 2 * (nd / 4)
        lda     pn_nd
        and     #3
        eor     #3
        tay                             ; digits to shift: 3 - nd % 4
        lda     pn_d
:       dey
        bmi     :+
        asl     a
        asl     a
        asl     a
        asl     a
        bra     :-
:       ora     fa,x
        sta     fa,x
        inc     pn_nd
        ply
        rts

; the character at bp + Y (0 past pn_max)
pn_ch:  cpy     pn_max
        bcs     :+
        lda     [bp],y
        and     #$00FF
        rts
:       lda     #0
        rts
; an exponent at Y ('E', then a digit or a sign and a digit)? -> C set
pn_isexp:
        phy
        iny
        jsr     pn_ch
        cmp     #'+'
        beq     :+
        cmp     #'-'
        bne     :++
:       iny
        jsr     pn_ch
:       ply
        jmp     tk_isdigit

; ---------------------------------------------------------------- helpers for the functions
; FA = [Y]; FA = FA op [Y], rounded
fm_ld:  ldx     #FAX
        jmp     fp_unpm
fm_add: ldx     #FBX
        jsr     fp_unpm
        jsr     fp_add
        jmp     fp_rnd
fm_sub: ldx     #FBX
        jsr     fp_unpm
        jsr     fp_sub
        jmp     fp_rnd
fm_mul: ldx     #FBX
        jsr     fp_unpm
        jsr     fp_mul
        jmp     fp_rnd
fm_div: ldx     #FBX
        jsr     fp_unpm
        jsr     fp_div
        jmp     fp_rnd
; FA = the signed 16-bit A
fp_i16: sta     z:fw
        ldx     #0
        cmp     #$8000
        bcc     :+
        dex
:       stx     z:fw+2
        ldx     #FAX
        jmp     fp_i2fw

; FA = c[0] + z (c[1] + z (...)): Horner over the table Y of A coefficients (the highest
; power first), z at fx_z
fpoly:  dec     a
        sta     pl_n
        sty     pl_p
        jsr     fm_ld
:       ldy     #.loword(fx_z)
        jsr     fm_mul
        lda     pl_p
        clc
        adc     #8
        sta     pl_p
        tay
        jsr     fm_add
        dec     pl_n
        bne     :-
        rts

; ---------------------------------------------------------------- square root
; FA = sqrt(FA) (Illegal function call below 0), digit by digit: for each pair of digits
; the odd numbers 20 p + 1, 20 p + 3, ... are taken from the remainder (p: the root so far).
; 13 digits and the remainder's sticky flag: correctly rounded.
fp_sqrt:
        lda     fa+6
        bne     :+
        rts
:       lda     fa_s
        beq     :+
        err     E_FUNC
:       lda     fa_e
        lsr     a
        bcc     :++
        ldy     #4                      ; an odd exponent: 0.0ddd x 10^(e + 1)
:       lsr     fa+6
        ror     fa+4
        ror     fa+2
        ror     fa
        dey
        bne     :-
        inc     fa_e
:       lda     fa_e
        cmp     #$8000                  ; e / 2 (signed)
        ror     a
        sta     fa_e
        stz     z:dr                    ; remainder
        stz     z:dr+2
        stz     z:dr+4
        stz     z:dr+6
        stz     z:dt                    ; 20 p
        stz     z:dt+2
        stz     z:dt+4
        stz     z:dt+6
        stz     sq_i
@dig:   lda     z:dr+5                  ; R = R * 100 + the next pair
        sta     z:dr+6
        lda     z:dr+3
        sta     z:dr+4
        lda     z:dr+1
        sta     z:dr+2
        lda     z:dr
        xba
        and     #$FF00
        sta     z:dr
        lda     sq_i
        cmp     #8
        bcs     :+
        eor     #7
        tax
        lda     fa,x
        and     #$00FF
        tsb     z:dr
:       sed                             ; t = 20 p + 1
        clc
        lda     z:dt
        adc     #1
        sta     z:dd
        lda     z:dt+2
        adc     #0
        sta     z:dd+2
        lda     z:dt+4
        adc     #0
        sta     z:dd+4
        lda     z:dt+6
        adc     #0
        sta     z:dd+6
        cld
        ldy     #0
@c:     lda     z:dr+6                  ; R >= t: R -= t, t += 2
        cmp     z:dd+6
        bcc     @e
        bne     @s
        lda     z:dr+4
        cmp     z:dd+4
        bcc     @e
        bne     @s
        lda     z:dr+2
        cmp     z:dd+2
        bcc     @e
        bne     @s
        lda     z:dr
        cmp     z:dd
        bcc     @e
@s:     sed
        sec
        lda     z:dr
        sbc     z:dd
        sta     z:dr
        lda     z:dr+2
        sbc     z:dd+2
        sta     z:dr+2
        lda     z:dr+4
        sbc     z:dd+4
        sta     z:dr+4
        lda     z:dr+6
        sbc     z:dd+6
        sta     z:dr+6
        clc
        lda     z:dd
        adc     #2
        sta     z:dd
        bcc     :+
        lda     z:dd+2
        adc     #0
        sta     z:dd+2
        lda     z:dd+4
        adc     #0
        sta     z:dd+4
        lda     z:dd+6
        adc     #0
        sta     z:dd+6
:       cld
        iny
        bra     @c
@e:     tya                             ; the digit
        ldx     sq_i
        sta     qd,x
        sed                             ; 20 p' = (t - 1) * 10
        sec
        lda     z:dd
        sbc     #1
        sta     z:dt
        lda     z:dd+2
        sbc     #0
        sta     z:dt+2
        lda     z:dd+4
        sbc     #0
        sta     z:dt+4
        lda     z:dd+6
        sbc     #0
        sta     z:dt+6
        cld
        ldy     #4
:       asl     z:dt
        rol     z:dt+2
        rol     z:dt+4
        rol     z:dt+6
        dey
        bne     :-
        inc     sq_i
        lda     sq_i
        cmp     #13
        jcc     @dig
        lda     z:dr
        ora     z:dr+2
        ora     z:dr+4
        ora     z:dr+6
        sta     z:fstk
        stz     qd+13
        stz     qd+15
        ldx     #0
        jmp     qd_fa

        .segment "RODATA"
p2bcd:  .repeat 32, K                   ; 2^k in BCD (12 digits, 3 words)
        .word   ((1 << K) .mod 10) + (((1 << K) / 10) .mod 10) * $10 + (((1 << K) / 100) .mod 10) * $100 + (((1 << K) / 1000) .mod 10) * $1000
        .word   (((1 << K) / 10000) .mod 10) + (((1 << K) / 100000) .mod 10) * $10 + (((1 << K) / 1000000) .mod 10) * $100 + (((1 << K) / 10000000) .mod 10) * $1000
        .word   (((1 << K) / 100000000) .mod 10) + (((1 << K) / 1000000000) .mod 10) * $10
        .endrepeat

        .segment "BSS"
mt:     .res    72              ; fp_mul: A * 1 .. 9
mt_n:   .res    2
mp_h:   .res    2
mp1:    .res    18
mp2:    .res    18
qd:     .res    20              ; fp_div, fp_sqrt: the digits
dvt:    .res    144             ; fp_div: D * 1..9, D * 10 .. 90
dv_h:   .res    2
ti_md:  .res    2
rd_p:   .res    2
bb_t:   .res    2
bb_u:   .res    2
bb_v:   .res    2
bb_w:   .res    2
fm_nd:  .res    2
fm_x:   .res    2
fm_w:   .res    2
fmtd:   .res    14
pn_nd:  .res    2
pn_dx:  .res    2
pn_ex:  .res    2
pn_esg: .res    2
pl_n:   .res    2
pl_p:   .res    2
sq_i:   .res    2
fx_z:   .res    8
