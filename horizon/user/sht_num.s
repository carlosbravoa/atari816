; sht_num.s - Sheet: decimal fixed-point numbers (part of sheet.s, one assembly unit).
;
; A number is a 64-bit signed integer scaled by 10,000: four decimals, exactly. The
; magnitude is at most 2^63 - 1 (about 9.2e14 in real units); -2^63 is never produced.
; Every routine works on the zero-page accumulators na and nb (8 bytes, little-endian) and
; returns C clear when it worked, C set with A = an error code (E_OVER, E_DIV0, E_VALUE)
; otherwise. Products and quotients are computed exactly in 128 bits and rounded half away
; from zero, so 1/3 = 0.3333, 2/3 = 0.6667, -2/3 = -0.6667, 0.0001 * 0.5 = 0.0001.
;
;   n_add n_sub     na = na +- nb
;   n_neg           na = -na
;   n_mul           na = na * nb
;   n_div           na = na / nb                  (E_DIV0)
;   n_cmp           A = -1 / 0 / 1 for na <, =, > nb (signed)
;   n_int           na = floor(na)
;   n_round         na rounded to A decimals (-14 .. 4)
;   n_sqrt          na = sqrt(na)                 (E_VALUE below 0)
;   n_pow           na = na ^ nb, nb an integer   (E_VALUE otherwise; E_DIV0 for 0 ^ -n)
;   n_mod           na = na - nb * floor(na / nb) (the sign of nb, as spreadsheets do)
;   n_parse         [sp],y -> na (see there)
;   n_fmt           na -> fbuf, in a cell format (see there)

E_DIV0  = 1
E_REF   = 2
E_VALUE = 3
E_CYCLE = 4
E_OVER  = 5

        .segment "CODE"

; ---------------------------------------------------------------- small helpers
n_zero: stz     z:na
        stz     z:na+2
        stz     z:na+4
        stz     z:na+6
        rts

; na = A (an integer in real units, 0 .. 65535): A * 10000
n_seti: sta     z:m1
        lda     #10000
        jsr     mul16
        lda     z:mp
        sta     z:na
        lda     z:mp+2
        sta     z:na+2
        stz     z:na+4
        stz     z:na+6
        rts

n_nega: sec
        lda     #0
        sbc     z:na
        sta     z:na
        lda     #0
        sbc     z:na+2
        sta     z:na+2
        lda     #0
        sbc     z:na+4
        sta     z:na+4
        lda     #0
        sbc     z:na+6
        sta     z:na+6
        rts
n_negb: sec
        lda     #0
        sbc     z:nb
        sta     z:nb
        lda     #0
        sbc     z:nb+2
        sta     z:nb+2
        lda     #0
        sbc     z:nb+4
        sta     z:nb+4
        lda     #0
        sbc     z:nb+6
        sta     z:nb+6
        rts

; nb = na / na = nb
n_a2b:  lda     z:na
        sta     z:nb
        lda     z:na+2
        sta     z:nb+2
        lda     z:na+4
        sta     z:nb+4
        lda     z:na+6
        sta     z:nb+6
        rts
n_b2a:  lda     z:nb
        sta     z:na
        lda     z:nb+2
        sta     z:na+2
        lda     z:nb+4
        sta     z:na+4
        lda     z:nb+6
        sta     z:na+6
        rts

; Z set if na = 0
n_isz:  lda     z:na
        ora     z:na+2
        ora     z:na+4
        ora     z:na+6
        rts

; nsg = sign(na) xor sign(nb); both made magnitudes
n_signs:
        stz     z:nsg
        lda     z:na+6
        bpl     :+
        jsr     n_nega
        inc     z:nsg
:       lda     z:nb+6
        bpl     :+
        jsr     n_negb
        lda     z:nsg
        eor     #1
        sta     z:nsg
:       rts

; ---------------------------------------------------------------- add, subtract, negate
n_add:  clc
        lda     z:na
        adc     z:nb
        sta     z:na
        lda     z:na+2
        adc     z:nb+2
        sta     z:na+2
        lda     z:na+4
        adc     z:nb+4
        sta     z:na+4
        lda     z:na+6
        adc     z:nb+6
        sta     z:na+6
        bvs     n_ovf
        clc
        rts
n_ovf:  lda     #E_OVER
        sec
        rts

n_sub:  sec
        lda     z:na
        sbc     z:nb
        sta     z:na
        lda     z:na+2
        sbc     z:nb+2
        sta     z:na+2
        lda     z:na+4
        sbc     z:nb+4
        sta     z:na+4
        lda     z:na+6
        sbc     z:nb+6
        sta     z:na+6
        bvs     n_ovf
        clc
        rts

n_neg:  jsr     n_nega
        clc
        rts

; ---------------------------------------------------------------- compare
; A = $FFFF if na < nb, 0 if equal, 1 if na > nb (signed). Keeps na, nb.
n_cmp:  lda     z:na+6
        eor     #$8000
        sta     z:nt
        lda     z:nb+6
        eor     #$8000
        cmp     z:nt
        bne     @d
        lda     z:nb+4
        cmp     z:na+4
        bne     @d
        lda     z:nb+2
        cmp     z:na+2
        bne     @d
        lda     z:nb
        cmp     z:na
        bne     @d
        lda     #0
        rts
@d:     bcs     @lt                     ; nb > na
        lda     #1
        rts
@lt:    lda     #$FFFF
        rts

; ---------------------------------------------------------------- 16 x 16 -> 32
; the quarter squares: qsq[n] = n * n / 4 (n = 0 .. 510), for 8 x 8 products
n_init: ldx     #0
        stz     z:mp                    ; n * n, incrementally: + 2n + 1
        stz     z:mp+2
@l:     lda     z:mp+2                  ; (n * n) / 4: the 32-bit square shifted twice
        lsr     a
        sta     z:m3+2
        lda     z:mp
        ror     a
        lsr     z:m3+2
        ror     a
        sta     qsq,x
        txa                             ; n = x / 2: + 2n + 1 = x + 1
        inc     a
        clc
        adc     z:mp
        sta     z:mp
        bcc     :+
        inc     z:mp+2
:       inx
        inx
        cpx     #511 * 2
        bcc     @l
        rts

; A (0-255) * X (0-255) -> A, with qsq: (a + b)^2 / 4 - (a - b)^2 / 4
mul8:   sta     z:q_x
        stx     z:q_y
        clc
        adc     z:q_y
        asl     a
        tay
        lda     qsq,y
        sta     z:q_s
        lda     z:q_x
        sec
        sbc     z:q_y
        bcs     :+
        eor     #$FFFF
        inc     a
:       asl     a
        tay
        lda     z:q_s
        sec
        sbc     qsq,y
        rts

; mp = m1 * A (unsigned); m1 and X kept
mul16:  phx
        sta     z:m2
        lda     z:m1                    ; the four bytes
        and     #$00FF
        sta     z:q_a0
        lda     z:m1+1
        and     #$00FF
        sta     z:q_a1
        lda     z:m2
        and     #$00FF
        sta     z:q_b0
        lda     z:m2+1
        and     #$00FF
        sta     z:q_b1
        stz     z:mp+2
        stz     z:mp
        lda     z:q_a0                  ; a0 b0
        beq     :+
        ldx     z:q_b0
        beq     :+
        jsr     mul8
        sta     z:mp
:
        stz     z:q_t                   ; the middle: a1 b0 + a0 b1 (17 bits)
        stz     z:q_c
        lda     z:q_a1
        beq     :+
        ldx     z:q_b0
        beq     :+
        jsr     mul8
        sta     z:q_t
:       lda     z:q_a0
        beq     :+
        ldx     z:q_b1
        beq     :+
        jsr     mul8
        clc
        adc     z:q_t
        sta     z:q_t
        rol     z:q_c
:       lda     z:q_t                   ; mp += middle << 8
        beq     :+
        xba
        pha
        and     #$FF00
        clc
        adc     z:mp
        sta     z:mp
        pla
        and     #$00FF
        adc     #0
        sta     z:mp+2
:       lda     z:q_c
        beq     :+
        lda     z:mp+2
        clc
        adc     #$0100
        sta     z:mp+2
:       lda     z:q_a1                  ; a1 b1 << 16
        beq     :+
        ldx     z:q_b1
        beq     :+
        jsr     mul8
        clc
        adc     z:mp+2
        sta     z:mp+2
:       plx
        rts

; ---------------------------------------------------------------- 64 x 64 -> 128
; nr = na * nb (unsigned magnitudes)
mul64:  ldx     #14
:       stz     z:nr,x
        dex
        dex
        bpl     :-
        stz     z:ii
@i:     ldx     z:ii
        lda     z:na,x
        beq     @ni
        sta     z:m1
        stz     z:jj
@j:     ldx     z:jj
        lda     z:nb,x
        beq     @nj
        jsr     mul16
        lda     z:ii
        clc
        adc     z:jj
        tax
        clc
        lda     z:mp
        adc     z:nr,x
        sta     z:nr,x
        lda     z:mp+2
        adc     z:nr+2,x
        sta     z:nr+2,x
        bcc     @nj
:       inx
        inx
        inc     z:nr+2,x
        beq     :-
@nj:    lda     z:jj
        inc     a
        inc     a
        sta     z:jj
        cmp     #8
        bcc     @j
@ni:    lda     z:ii
        inc     a
        inc     a
        sta     z:ii
        cmp     #8
        bcc     @i
        rts

; ---------------------------------------------------------------- 128 / 16
; nr = nr / A (unsigned) -> A = the remainder
div16:  sta     z:dv
        ldx     #14                     ; the zero words at the top: quotient 0 there
:       lda     z:nr,x
        bne     :+
        dex
        dex
        bpl     :-
        lda     #0
        rts
:       lda     #0                      ; A = the remainder through the words
@w:     cmp     #0
        bne     @full
        ldy     z:nr,x                  ; remainder 0 and a word below the divisor: the
        cpy     z:dv                    ; word is the remainder, the quotient word 0
        bcs     @full
        stz     z:nr,x
        tya
        bra     @nw
@full:  ldy     z:nr,x
        sty     z:rl
        ldy     #16
@b:     asl     z:rl
        rol     a
        bcs     @sub
        cmp     z:dv
        bcc     @n
@sub:   sbc     z:dv                    ; (C is set on both paths)
        inc     z:rl
@n:     dey
        bne     @b
        ldy     z:rl
        sty     z:nr,x
@nw:    dex
        dex
        bpl     @w
        rts

; nr = nr + 1 (128 bits)
inc128: ldx     #0
:       inc     z:nr,x
        bne     :+
        inx
        inx
        cpx     #16
        bcc     :-
:       rts

; nr = nr * A (A a 16-bit factor; nr below 2^112)
mulnr:  sta     z:m2s
        ldx     #0
        stz     z:rh                    ; the carry word
@l:     lda     z:nr,x
        bne     :+
        lda     z:rh                    ; (a zero word: the carry only)
        sta     z:nr,x
        stz     z:rh
        bra     @nx
:       sta     z:m1
        lda     z:m2s
        phx
        jsr     mul16
        plx
        clc
        lda     z:mp
        adc     z:rh
        sta     z:nr,x
        lda     z:mp+2
        adc     #0
        sta     z:rh
@nx:    inx
        inx
        cpx     #16
        bcc     @l
        rts

; ---------------------------------------------------------------- results
; na = nr (the magnitude) with sign nsg; C set (E_OVER) if it does not fit in 63 bits
n_fin:  lda     z:nr+8
        ora     z:nr+10
        ora     z:nr+12
        ora     z:nr+14
        bne     @ovf
        lda     z:nr+6
        bmi     @ovf
        sta     z:na+6
        lda     z:nr+4
        sta     z:na+4
        lda     z:nr+2
        sta     z:na+2
        lda     z:nr
        sta     z:na
        lda     z:nsg
        beq     :+
        jsr     n_nega
:       clc
        rts
@ovf:   lda     #E_OVER
        sec
        rts

; nr = na (64 bits, unsigned), upper half 0
n_a2r:  lda     z:na
        sta     z:nr
        lda     z:na+2
        sta     z:nr+2
        lda     z:na+4
        sta     z:nr+4
        lda     z:na+6
        sta     z:nr+6
        stz     z:nr+8
        stz     z:nr+10
        stz     z:nr+12
        stz     z:nr+14
        rts

; nr = nr / 10^(4 nk), rounded half up (nr is a magnitude)
n_scdown:
@l:     lda     #10000
        jsr     div16
        dec     z:nk
        bne     @l
        cmp     #5000
        bcc     :+
        jsr     inc128
:       rts

; ---------------------------------------------------------------- multiply
n_mul:  lda     #1
; na = na * nb / 10^(4 A), rounded (A = 1: the plain product of two numbers)
n_mulk: sta     z:nk
        jsr     n_signs
        jsr     mul64
        jsr     n_scdown
        jmp     n_fin

; ---------------------------------------------------------------- divide
n_div:  lda     z:nb
        ora     z:nb+2
        ora     z:nb+4
        ora     z:nb+6
        bne     :+
        lda     #E_DIV0
        sec
        rts
:       jsr     n_signs
        jsr     n_b2d
        lda     #10000                  ; nr = |na| * 10000
        jsr     n_a2r
        lda     #10000
        jsr     mulnr
; nr = round(nr / nd), then the result with sign nsg
n_divr: jsr     div64
        asl     z:rm                    ; 2 * remainder >= divisor: up
        rol     z:rm+2
        rol     z:rm+4
        rol     z:rm+6
        bcs     @up
        lda     z:rm+6
        cmp     z:nd+6
        bne     :+
        lda     z:rm+4
        cmp     z:nd+4
        bne     :+
        lda     z:rm+2
        cmp     z:nd+2
        bne     :+
        lda     z:rm
        cmp     z:nd
:       bcc     @fin
@up:    jsr     inc128
@fin:   jmp     n_fin

n_b2d:  lda     z:nb
        sta     z:nd
        lda     z:nb+2
        sta     z:nd+2
        lda     z:nb+4
        sta     z:nd+4
        lda     z:nb+6
        sta     z:nd+6
        rts

; nr = nr / nd, rm = the remainder (unsigned; nd not 0, below 2^64)
div64:  stz     z:rm
        stz     z:rm+2
        stz     z:rm+4
        stz     z:rm+6
        ldx     #14                     ; the significant words: w
:       lda     z:nr,x
        bne     :+
        dex
        dex
        bpl     :-
        rts                             ; nr = 0: quotient 0, remainder 0
:       txa                             ; x = 2 (w - 1): move the words up by 8 - w
        lsr     a
        inc     a
        sta     z:cnt                   ; w
        txa
        eor     #$FFFF
        sec
        adc     #14                     ; 14 - x = 2 (8 - w)
        beq     @go
        sta     z:nt
        ldx     #14
@mv:    txa
        sec
        sbc     z:nt
        bcc     @mz
        tay
        phx
        tyx
        lda     z:nr,x
        plx
        sta     z:nr,x
        bra     @mn
@mz:    stz     z:nr,x
@mn:    dex
        dex
        bpl     @mv
@go:    lda     z:cnt                   ; w * 16 steps
        asl     a
        asl     a
        asl     a
        asl     a
        sta     z:cnt
@b:     asl     z:nr
        rol     z:nr+2
        rol     z:nr+4
        rol     z:nr+6
        rol     z:nr+8
        rol     z:nr+10
        rol     z:nr+12
        rol     z:nr+14
        rol     z:rm
        rol     z:rm+2
        rol     z:rm+4
        rol     z:rm+6
        lda     z:rm+6
        cmp     z:nd+6
        bcc     @n
        bne     @s
        lda     z:rm+4
        cmp     z:nd+4
        bcc     @n
        bne     @s
        lda     z:rm+2
        cmp     z:nd+2
        bcc     @n
        bne     @s
        lda     z:rm
        cmp     z:nd
        bcc     @n
@s:     sec
        lda     z:rm
        sbc     z:nd
        sta     z:rm
        lda     z:rm+2
        sbc     z:nd+2
        sta     z:rm+2
        lda     z:rm+4
        sbc     z:nd+4
        sta     z:rm+4
        lda     z:rm+6
        sbc     z:nd+6
        sta     z:rm+6
        inc     z:nr
@n:     dec     z:cnt
        bne     @b
        rts

; ---------------------------------------------------------------- INT, ROUND
; na = floor(na)
n_int:  stz     z:nsg
        lda     z:na+6
        bpl     :+
        jsr     n_nega
        inc     z:nsg
:       jsr     n_a2r
        lda     #10000
        jsr     div16                   ; nr = whole units, A = the fraction
        cmp     #0
        beq     :+
        ldx     z:nsg                   ; negative with a fraction: one further down
        beq     :+
        jsr     inc128
:       lda     #10000
        jsr     mulnr
        jmp     n_fin

; na rounded to A decimals (A signed: 4 or more: unchanged; below -14: 0)
n_round:
        cmp     #$8000
        bcs     @neg
        cmp     #4
        bcc     :+
        clc                             ; 4 or more decimals: as it is
        rts
:       eor     #3                      ; 0..3 -> drop 4 - A digits
        inc     a
        bra     @drop
@neg:   eor     #$FFFF                  ; -1 .. -14 -> drop 4 + |A| digits
        inc     a
        clc
        adc     #4
        cmp     #19
        bcc     @drop
        jsr     n_zero
        clc
        rts
@drop:  sta     z:nk                    ; digits dropped (1 .. 18)
        stz     z:nsg
        lda     z:na+6
        bpl     :+
        jsr     n_nega
        inc     z:nsg
:       jsr     n_a2r
        lda     z:nk                    ; drop nk - 1 digits (truncating), then one more:
        dec     a                       ; its value decides the rounding
        sta     z:cnt
@l:     lda     z:cnt
        beq     @last
        cmp     #4
        bcc     :+
        lda     #4
:       pha
        asl     a
        tax
        lda     p10,x
        jsr     div16
        pla
        eor     #$FFFF
        sec
        adc     z:cnt
        sta     z:cnt
        bra     @l
@last:  lda     #10
        jsr     div16
        cmp     #5
        bcc     :+
        jsr     inc128
:       lda     z:nk                    ; and back to the scale
@up:    beq     @fin
        cmp     #4
        bcc     :+
        lda     #4
:       pha
        asl     a
        tax
        lda     p10,x
        jsr     mulnr
        pla
        eor     #$FFFF
        sec
        adc     z:nk
        sta     z:nk
        bra     @up
@fin:   jmp     n_fin

; ---------------------------------------------------------------- SQRT
; na = sqrt(na), rounded: the integer square root of na * 10^4 (as the result is scaled)
n_sqrt: lda     z:na+6
        bpl     :+
        lda     #E_VALUE
        sec
        rts
:       jsr     n_a2r
        lda     #10000
        jsr     mulnr                   ; N = na * 10^4 < 2^78, in nr
        stz     z:nb                    ; nb = the root, rm = the remainder
        stz     z:nb+2
        stz     z:nb+4
        stz     z:nb+6
        stz     z:rm
        stz     z:rm+2
        stz     z:rm+4
        stz     z:rm+6
        lda     #40                     ; 40 bit pairs: N < 2^80
        sta     z:cnt
        lda     z:nr+8                  ; bring bit 79 to the top: shift left 48 bits
        sta     z:nr+14
        lda     z:nr+6
        sta     z:nr+12
        lda     z:nr+4
        sta     z:nr+10
        lda     z:nr+2
        sta     z:nr+8
        lda     z:nr
        sta     z:nr+6
        stz     z:nr+4
        stz     z:nr+2
        stz     z:nr
        ; (now N << 48; bits 127..48 hold N's bits 79..0)
@b:     ldy     #2                      ; rem = rem << 2 | the next two bits
:       asl     z:nr+6
        rol     z:nr+8
        rol     z:nr+10
        rol     z:nr+12
        rol     z:nr+14
        rol     z:rm
        rol     z:rm+2
        rol     z:rm+4
        rol     z:rm+6
        dey
        bne     :-
        asl     z:nb                    ; root << 1; trial = root << 1 | 1 (= old root * 4 + 1)
        rol     z:nb+2
        rol     z:nb+4
        rol     z:nb+6
        lda     z:nb                    ; nd = trial = 2 root' + 1
        asl     a
        ora     #1
        sta     z:nd
        lda     z:nb+2
        rol     a
        sta     z:nd+2
        lda     z:nb+4
        rol     a
        sta     z:nd+4
        lda     z:nb+6
        rol     a
        sta     z:nd+6
        lda     z:rm+6                  ; rem >= trial?
        cmp     z:nd+6
        bcc     @n
        bne     @s
        lda     z:rm+4
        cmp     z:nd+4
        bcc     @n
        bne     @s
        lda     z:rm+2
        cmp     z:nd+2
        bcc     @n
        bne     @s
        lda     z:rm
        cmp     z:nd
        bcc     @n
@s:     sec
        lda     z:rm
        sbc     z:nd
        sta     z:rm
        lda     z:rm+2
        sbc     z:nd+2
        sta     z:rm+2
        lda     z:rm+4
        sbc     z:nd+4
        sta     z:rm+4
        lda     z:rm+6
        sbc     z:nd+6
        sta     z:rm+6
        inc     z:nb
@n:     dec     z:cnt
        bne     @b
        lda     z:rm+6                  ; round: remainder > root -> root + 1
        cmp     z:nb+6
        bcc     @d
        bne     @u
        lda     z:rm+4
        cmp     z:nb+4
        bcc     @d
        bne     @u
        lda     z:rm+2
        cmp     z:nb+2
        bcc     @d
        bne     @u
        lda     z:rm
        cmp     z:nb
        bcc     @d
        beq     @d
@u:     inc     z:nb
        bne     @d
        inc     z:nb+2
        bne     @d
        inc     z:nb+4
@d:     jsr     n_b2a
        clc
        rts

; ---------------------------------------------------------------- MOD
; na = na - nb * floor(na / nb)
n_mod:  lda     z:nb
        ora     z:nb+2
        ora     z:nb+4
        ora     z:nb+6
        bne     :+
        lda     #E_DIV0
        sec
        rts
:       lda     z:na+6                  ; signs of both: the remainder of the magnitudes
        and     #$8000
        sta     ms_a
        lda     z:nb+6
        and     #$8000
        sta     ms_b
        jsr     n_signs
        jsr     n_b2d
        jsr     n_a2r
        jsr     div64                   ; rm = |a| mod |b|
        lda     z:rm
        sta     z:na
        lda     z:rm+2
        sta     z:na+2
        lda     z:rm+4
        sta     z:na+4
        lda     z:rm+6
        sta     z:na+6
        lda     ms_a                  ; r = sign(a) * rm
        beq     :+
        jsr     n_nega
:       jsr     n_isz
        beq     @out
        lda     ms_a                  ; signs differ and r <> 0: r + b
        eor     ms_b
        beq     @out
        lda     z:nd
        sta     z:nb
        lda     z:nd+2
        sta     z:nb+2
        lda     z:nd+4
        sta     z:nb+4
        lda     z:nd+6
        sta     z:nb+6
        lda     ms_b
        beq     :+
        jsr     n_negb
:       jmp     n_add
@out:   clc
        rts

; ---------------------------------------------------------------- POWER
; na = na ^ nb; nb must be a whole number (|nb| < 65536). Square and multiply from the
; top bit with the running result at scale 10^12 (8 more decimals than a number has, so
; (1 + r) ^ 360 keeps its accuracy); when it grows past that scale's range (about 9.2e6) it
; goes on at the normal scale.
n_pow:  jsr     n_b2d                   ; the exponent: nd
        lda     z:nb+6                  ; |e|, a whole number?
        and     #$8000
        sta     ms_b
        beq     :+
        jsr     n_negb
:       lda     z:na                    ; the base: pw_x (scale 10^4)
        sta     pw_x
        lda     z:na+2
        sta     pw_x+2
        lda     z:na+4
        sta     pw_x+4
        lda     z:na+6
        sta     pw_x+6
        jsr     n_b2a
        jsr     n_a2r
        lda     #10000
        jsr     div16
        cmp     #0
        bne     @bad
        lda     z:nr+2                  ; at most 65535
        ora     z:nr+4
        ora     z:nr+6
        bne     @bad
        lda     z:nr
        sta     pw_e
        bne     :+
        lda     #1                      ; x ^ 0 = 1
        jsr     n_seti
        clc
        rts
:       lda     pw_x                  ; 0 ^ -n
        ora     pw_x+2
        ora     pw_x+4
        ora     pw_x+6
        bne     :+
        lda     ms_b
        beq     @zero
        lda     #E_DIV0
        sec
        rts
@zero:  jsr     n_zero
        clc
        rts
@bad:   lda     #E_VALUE
        sec
        rts
:       jsr     pw_loop
        jcs     @ovf
        lda     ms_b                  ; the result
        bne     @inv
        lda     pw_r                  ; x ^ e: r at its scale -> 10^4
        sta     z:na
        lda     pw_r+2
        sta     z:na+2
        lda     pw_r+4
        sta     z:na+4
        lda     pw_r+6
        sta     z:na+6
        lda     pw_s
        beq     @ok
        stz     z:nsg
        lda     z:na+6
        bpl     :+
        jsr     n_nega
        inc     z:nsg
:       jsr     n_a2r
        lda     #2
        sta     z:nk
        jsr     n_scdown
        jmp     n_fin
@ok:    clc
        rts
@inv:   stz     z:nsg                   ; x ^ -e = 1 / r: 10^16 (or 10^8) / r
        lda     pw_r
        sta     z:nd
        lda     pw_r+2
        sta     z:nd+2
        lda     pw_r+4
        sta     z:nd+4
        lda     pw_r+6
        sta     z:nd+6
        bpl     :+
        inc     z:nsg
        sec
        lda     #0
        sbc     z:nd
        sta     z:nd
        lda     #0
        sbc     z:nd+2
        sta     z:nd+2
        lda     #0
        sbc     z:nd+4
        sta     z:nd+4
        lda     #0
        sbc     z:nd+6
        sta     z:nd+6
:       ldx     #14
:       stz     z:nr,x
        dex
        dex
        bpl     :-
        lda     #1
        sta     z:nr
        lda     #10000
        jsr     mulnr
        lda     #10000
        jsr     mulnr
        lda     pw_s
        beq     :+
        lda     #10000
        jsr     mulnr
        lda     #10000
        jsr     mulnr
:       jmp     n_divr
@ovf:   lda     ms_b                  ; too large: x ^ -e is 0, x ^ e an overflow
        beq     :+
        jmp     @zero
:       lda     #E_OVER
        sec
        rts

; pw_r = pw_x ^ pw_e (pw_e > 0): pw_s 1 at scale 10^12, 0 at 10^4; C set: overflow
pw_loop:
        lda     #1                      ; r = 1 at scale 10^12 (10^12 = $E8_D4A5_1000)
        sta     pw_s
        lda     #$1000
        sta     pw_r
        lda     #$D4A5
        sta     pw_r+2
        lda     #$00E8
        sta     pw_r+4
        stz     pw_r+6
        lda     #$8000                  ; the exponent's bits from the top
        sta     pw_m
:       lda     pw_e
        and     pw_m
        bne     @bit
        lsr     pw_m
        bra     :-
@bit:   jsr     pw_sq                   ; r = r * r (the first one squares 1)
        bcs     @ovf
        lda     pw_e
        and     pw_m
        beq     :+
        jsr     pw_mx                   ; r = r * x
        bcs     @ovf
:       lsr     pw_m
        bne     @bit
        clc
@ovf:   rts

; ---------------------------------------------------------------- PMT
; na = the payment per period that repays nb (an amount) in n_pn periods (1-65535) at
; the rate pm_r per period: amount * r * g / (g - 1), g = (1 + r) ^ n computed at scale
; 10^12, so the payment is exact to its four decimals; rate 0: amount / n
n_pmt:  jsr     n_b2a                   ; amount -> pm_a
        ldx     #6
:       lda     z:na,x
        sta     pm_a,x
        lda     pm_r,x
        sta     z:nb,x
        dex
        dex
        bpl     :-
        lda     pm_r                    ; rate 0
        ora     pm_r+2
        ora     pm_r+4
        ora     pm_r+6
        bne     :+
        lda     n_pn
        jsr     n_seti
        jsr     n_a2b
        jsr     pm_lda
        jmp     n_div
:       jsr     n_mul                   ; amount * r (the numerator's first part)
        bcc     :+
        rts
:       ldx     #6
:       lda     z:na,x
        sta     pm_a,x
        dex
        dex
        bpl     :-
        lda     #1                      ; 1 + r -> pw_x (above 0)
        jsr     n_seti
        ldx     #6
:       lda     pm_r,x
        sta     z:nb,x
        dex
        dex
        bpl     :-
        jsr     n_add
        jcs     pm_bad
        lda     z:na+6
        bpl     :+
        jmp     pm_bad
:       jsr     n_isz
        jeq     pm_bad
        ldx     #6
:       lda     z:na,x
        sta     pw_x,x
        dex
        dex
        bpl     :-
        lda     n_pn
        sta     pw_e
        jsr     pw_loop                 ; g (positive) in pw_r, at scale 10^12 or 10^4
        bcc     :+
        lda     #E_OVER
        rts
:       ldx     #6                      ; d = g - 1 at that scale -> nd (with its sign)
:       lda     pw_r,x
        sta     z:na,x
        dex
        dex
        bpl     :-
        lda     #$1000                  ; 10^12
        sta     z:nb
        lda     #$D4A5
        sta     z:nb+2
        lda     #$00E8
        sta     z:nb+4
        stz     z:nb+6
        lda     pw_s
        bne     :+
        lda     #1                      ; (10^4)
        jsr     n_seti
        jsr     n_a2b
:       ldx     #6
:       lda     pw_r,x
        sta     z:na,x
        dex
        dex
        bpl     :-
        jsr     n_sub
        jsr     n_isz
        bne     :+
        lda     #E_DIV0
        sec
        rts
:       lda     z:na+6                  ; nd = |d|, nsg = sign(d) xor sign(amount r)
        and     #$8000
        sta     ms_a
        bpl     :+
        jsr     n_nega
:       ldx     #6
:       lda     z:na,x
        sta     z:nd,x
        dex
        dex
        bpl     :-
        jsr     pm_lda                  ; nr = |amount r| * g
        lda     z:na+6
        and     #$8000
        eor     ms_a
        sta     ms_a
        lda     z:na+6
        bpl     :+
        jsr     n_nega
:       ldx     #6
:       lda     pw_r,x
        sta     z:nb,x
        dex
        dex
        bpl     :-
        jsr     mul64
        stz     z:nsg
        lda     ms_a
        beq     :+
        inc     z:nsg
:       jmp     n_divr
pm_bad: lda     #E_VALUE
        sec
        rts
pm_lda: ldx     #6
:       lda     pm_a,x
        sta     z:na,x
        dex
        dex
        bpl     :-
        rts

; pw_r = pw_r * pw_r at its scale -> C set: overflow (also at the normal scale)
pw_sq:  lda     pw_r
        sta     z:nb
        lda     pw_r+2
        sta     z:nb+2
        lda     pw_r+4
        sta     z:nb+4
        lda     pw_r+6
        sta     z:nb+6
        lda     #3                      ; scale 10^12: drop 12 digits
        bra     pw_go
; pw_r = pw_r * pw_x
pw_mx:  lda     pw_x
        sta     z:nb
        lda     pw_x+2
        sta     z:nb+2
        lda     pw_x+4
        sta     z:nb+4
        lda     pw_x+6
        sta     z:nb+6
        lda     #1
pw_go:  sta     pw_k
        ldx     #6                      ; the operand, kept for a second try
:       lda     z:nb,x
        sta     pw_o,x
        dex
        dex
        bpl     :-
        lda     pw_s                    ; at the normal scale every product drops 4 digits
        bne     :+
        lda     #1
        sta     pw_k
:       jsr     pw_try
        bcc     @out
        lda     pw_s                    ; overflow at 10^12: go to 10^4 and try again
        beq     @ovf
        stz     pw_s
        jsr     pw_r2a                  ; r = r / 10^8, rounded
        stz     z:nsg
        lda     z:na+6
        bpl     :+
        jsr     n_nega
        inc     z:nsg
:       jsr     n_a2r
        lda     #2
        sta     z:nk
        jsr     n_scdown
        jsr     n_fin
        jsr     pw_a2r
        lda     pw_k                    ; a square: the operand is r itself (converted)
        cmp     #3
        bne     :+
        jsr     pw_r2b
        bra     :+++
:       ldx     #6
:       lda     pw_o,x
        sta     z:nb,x
        dex
        dex
        bpl     :-
:       lda     #1
        sta     pw_k
        jsr     pw_try
        bcs     @ovf
@out:   clc
        rts
@ovf:   sec
        rts
pw_r2b: lda     pw_r
        sta     z:nb
        lda     pw_r+2
        sta     z:nb+2
        lda     pw_r+4
        sta     z:nb+4
        lda     pw_r+6
        sta     z:nb+6
        rts
pw_r2a: lda     pw_r
        sta     z:na
        lda     pw_r+2
        sta     z:na+2
        lda     pw_r+4
        sta     z:na+4
        lda     pw_r+6
        sta     z:na+6
        rts
pw_a2r: lda     z:na
        sta     pw_r
        lda     z:na+2
        sta     pw_r+2
        lda     z:na+4
        sta     pw_r+4
        lda     z:na+6
        sta     pw_r+6
        rts
; r * nb, dropping 4 pw_k digits -> pw_r; C set on overflow (pw_r unchanged)
pw_try: jsr     pw_r2a
        lda     pw_k
        jsr     n_mulk
        bcs     :+
        jsr     pw_a2r
        clc
:       rts

; ---------------------------------------------------------------- parse
; A number at [sp],y -> na, Y past it; C set: not a number (nothing taken), or too large
; (A = E_OVER). n_pflags: bit 0 commas allowed between digits of the whole part (1,234),
; bit 1 a % after it (divides by 100). Digits: 0-9 with one '.', at least one digit; no sign.
n_parse:
        sty     ps_y0
        jsr     n_zero
        stz     ps_nd                 ; digits seen
        lda     #$FFFF
        sta     ps_fd                 ; fraction digits ($FFFF: no point yet)
        stz     ps_ov
@c:     lda     [sp],y
        and     #$00FF
        cmp     #'0'
        bcc     @nd
        cmp     #'9' + 1
        bcs     @nd
        sbc     #'0' - 1                ; (C clear: - '0')
        sta     ps_d
        inc     ps_nd
        lda     ps_fd
        bmi     @dig
        cmp     #7                      ; past 7 decimals: ignored
        bcs     @next
        inc     ps_fd
@dig:   jsr     mul10
        bcs     @big
        lda     z:na
        clc
        adc     ps_d
        sta     z:na
        bcc     @next
        inc     z:na+2
        bne     @next
        inc     z:na+4
        bne     @next
        inc     z:na+6
        bmi     @big
@next:  iny
        bra     @c
@big:   inc     ps_ov
        bra     @next
@nd:    cmp     #'.'
        bne     @comma
        lda     ps_fd
        bpl     @end
        stz     ps_fd
        iny
        bra     @c
@comma: cmp     #','
        bne     @end
        lda     n_pflags
        and     #1
        beq     @end
        lda     ps_fd                 ; (only in the whole part, after a digit, before one)
        bpl     @end
        lda     ps_nd
        beq     @end
        iny
        lda     [sp],y
        dey
        and     #$00FF
        cmp     #'0'
        bcc     @end
        cmp     #'9' + 1
        bcs     @end
        iny
        jmp     @c
@end:   lda     ps_nd
        bne     :+
        ldy     ps_y0
        sec
        rts
:       lda     ps_ov
        beq     :+
        lda     #E_OVER
        sec
        rts
:       lda     ps_fd
        bpl     :+
        lda     #0
:       sta     ps_fd
        lda     n_pflags              ; a percent sign: two more decimals
        and     #2
        beq     @scale
        lda     [sp],y
        and     #$00FF
        cmp     #'%'
        bne     @scale
        iny
        inc     ps_fd
        inc     ps_fd
@scale: sty     ps_y0
        lda     ps_fd
        cmp     #5
        bcs     @down
        eor     #$FFFF                  ; 4 - fd zeros more
        sec
        adc     #4
        beq     @ok
        sta     ps_d
:       jsr     mul10
        bcs     @ovf
        dec     ps_d
        bne     :-
@ok:    ldy     ps_y0
        clc
        rts
@ovf:   ldy     ps_y0
        lda     #E_OVER
        sec
        rts
@down:  sec                             ; fd - 4 digits too many: drop, rounding
        sbc     #4
        sta     ps_d
        stz     z:nsg
        jsr     n_a2r
:       lda     ps_d
        dec     a
        beq     :+
        sta     ps_d
        lda     #10
        jsr     div16
        bra     :-
:       lda     #10
        jsr     div16
        cmp     #5
        bcc     :+
        jsr     inc128
:       jsr     n_fin
        ldy     ps_y0
        clc
        rts

; na = na * 10 (unsigned) -> C set if it no longer fits in 63 bits. Keeps Y.
mul10:  lda     z:na                    ; t = na * 2
        asl     a
        sta     z:m3
        lda     z:na+2
        rol     a
        sta     z:m3+2
        lda     z:na+4
        rol     a
        sta     z:mp
        lda     z:na+6
        rol     a
        sta     z:mp+2
        bcs     @ovf
        bmi     @ovf
        asl     z:na                    ; na * 8
        rol     z:na+2
        rol     z:na+4
        rol     z:na+6
        bcs     @ovf
        asl     z:na
        rol     z:na+2
        rol     z:na+4
        rol     z:na+6
        bcs     @ovf
        asl     z:na
        rol     z:na+2
        rol     z:na+4
        rol     z:na+6
        bcs     @ovf
        bmi     @ovf
        clc
        lda     z:na
        adc     z:m3
        sta     z:na
        lda     z:na+2
        adc     z:m3+2
        sta     z:na+2
        lda     z:na+4
        adc     z:mp
        sta     z:na+4
        lda     z:na+6
        adc     z:mp+2
        sta     z:na+6
        bmi     @ovf
        clc
        rts
@ovf:   sec
        rts

; ---------------------------------------------------------------- format
; na -> fbuf (zero-terminated), A = its length. The format byte A:
;   bits 0-3: 0 general (up to 4 decimals, trailing zeros dropped), 1-5 fixed with
;             0-4 decimals
;   FM_THOU  ($10) thousands separators (1,234,567.5)
;   FM_PCT   ($20) percent: the value times 100 with a '%'
FM_THOU = $10
FM_PCT  = $20
n_fmt:  sta     fm_f
        stz     fm_neg
        lda     z:na+6
        bpl     :+
        inc     fm_neg
:       lda     z:na                    ; |na| -> nr (keeping na)
        sta     z:nr
        lda     z:na+2
        sta     z:nr+2
        lda     z:na+4
        sta     z:nr+4
        lda     z:na+6
        sta     z:nr+6
        stz     z:nr+8
        stz     z:nr+10
        stz     z:nr+12
        stz     z:nr+14
        lda     fm_neg
        beq     :+
        sec
        ldx     #0
        ldy     #4
@ng:    lda     #0
        sbc     z:nr,x
        sta     z:nr,x
        inx
        inx
        dey
        bne     @ng
:       lda     #4                      ; S: the decimals nr carries (percent: 2)
        sta     fm_s
        lda     fm_f
        and     #FM_PCT
        beq     :+
        lda     #2
        sta     fm_s
:       lda     fm_f                  ; D: the decimals wanted
        and     #$0F
        beq     :+
        dec     a
        bra     :++
:       lda     fm_s
:       sta     fm_d
        stz     fm_pad                ; D > S: zeros appended
        cmp     fm_s
        bcc     @less
        sec
        sbc     fm_s
        sta     fm_pad
        lda     fm_s
        sta     fm_d
        bra     @digits
@less:  lda     fm_s                  ; D < S: drop S - D digits, rounding
        sec
        sbc     fm_d
        dec     a
        beq     :+
        asl     a
        tax
        lda     p10,x
        jsr     div16
:       lda     #10
        jsr     div16
        cmp     #5
        bcc     @digits
        jsr     inc128
@digits:                                ; nr -> decimal digits, right to left in dgt
        ldx     #DGTMAX
@grp:   phx
        lda     #10000
        jsr     div16
        plx
        jsr     dig4
        lda     z:nr
        ora     z:nr+2
        ora     z:nr+4
        ora     z:nr+6
        bne     @grp
:       txa                             ; at least fm_d + 1 digits
        eor     #$FFFF
        sec
        adc     #DGTMAX
        dec     a
        cmp     fm_d
        bcs     :+
        dex
        sep     #$20
        .a8
        stz     dgt,x
        rep     #$20
        .a16
        bra     :-
:
        ; leading zeros off, but keep fm_d + 1 digits at least
        stx     fm_i
:       lda     #DGTMAX
        sec
        sbc     fm_i                  ; digits now
        dec     a
        cmp     fm_d
        bcc     :+
        beq     :+
        ldx     fm_i
        lda     dgt,x
        and     #$00FF
        bne     :+
        inc     fm_i
        bra     :-
:       lda     #DGTMAX                 ; the fraction's end: general drops trailing zeros
        sta     fm_e
        lda     fm_f
        and     #$0F
        bne     @build
:       lda     fm_d
        beq     @build
        ldx     fm_e
        lda     dgt-1,x
        and     #$00FF
        bne     @build
        dec     fm_e
        dec     fm_d
        bra     :-
@build: ldy     #0                      ; zero? (no minus sign then)
        ldx     fm_i
:       cpx     fm_e
        bcs     :+
        lda     dgt,x
        and     #$00FF
        bne     @nz
        inx
        bra     :-
:       stz     fm_neg
@nz:    lda     fm_neg
        beq     :+
        lda     #'-'
        jsr     @put
:       lda     fm_e                  ; the whole part: fm_i .. fm_e - fm_d
        sec
        sbc     fm_d
        sta     fm_w
        sec
        sbc     fm_i
        sta     fm_c                  ; its digit count
        ldx     fm_i
@wh:    cpx     fm_w
        bcs     @frac
        lda     dgt,x
        and     #$00FF
        ora     #'0'
        jsr     @put
        inx
        dec     fm_c
        lda     fm_f
        and     #FM_THOU
        beq     @wh
        lda     fm_c
        beq     @wh
:       cmp     #3
        bcc     :+
        sbc     #3
        bra     :-
:       cmp     #0
        bne     @wh
        lda     #','
        jsr     @put
        bra     @wh
@frac:  lda     fm_d
        ora     fm_pad
        beq     @pct
        lda     #'.'
        jsr     @put
:       cpx     fm_e
        bcs     :+
        lda     dgt,x
        and     #$00FF
        ora     #'0'
        jsr     @put
        inx
        bra     :-
:       lda     fm_pad
        beq     @pct
        lda     #'0'
        jsr     @put
        dec     fm_pad
        bra     :-
@pct:   lda     fm_f
        and     #FM_PCT
        beq     :+
        lda     #'%'
        jsr     @put
:       lda     #0
        sta     fbuf,y
        tya
        rts
@put:   sep     #$20
        .a8
        sta     fbuf,y
        rep     #$20
        .a16
        iny
        rts

; A (below 10000) -> four digits (0-9) at dgt + X - 4 .. X - 1; X = X - 4
dig4:   dex
        dex
        dex
        dex
        ldy     #0
:       cmp     #1000
        bcc     :+
        sbc     #1000
        iny
        bra     :-
:       jsr     @put
        ldy     #0
:       cmp     #100
        bcc     :+
        sbc     #100
        iny
        bra     :-
:       inx
        jsr     @put
        ldy     #0
:       cmp     #10
        bcc     :+
        sbc     #10
        iny
        bra     :-
:       inx
        jsr     @put
        tay
        inx
        jsr     @put
        dex
        dex
        dex
        rts
@put:   pha
        tya
        sep     #$20
        .a8
        sta     dgt,x
        rep     #$20
        .a16
        pla
        rts

        .segment "RODATA"
p10:    .word   1, 10, 100, 1000, 10000

        .segment "BSS"
DGTMAX  = 24
dgt:    .res    DGTMAX + 2
qsq:    .res    511 * 2
fbuf:   .res    TXTMAX + 8

        .segment "ZEROPAGE"
na:     .res    8
nb:     .res    8
nr:     .res    16
rm:     .res    8
nd:     .res    8
m1:     .res    2
m2:     .res    2
m2s:    .res    2
m3:     .res    4
mp:     .res    4
dv:     .res    2
rh:     .res    2
rl:     .res    2
nk:     .res    2
nsg:    .res    2
ii:     .res    2
jj:     .res    2
cnt:    .res    2
nt:     .res    2
q_x:    .res    2
q_y:    .res    2
q_s:    .res    2
q_a0:   .res    2
q_a1:   .res    2
q_b0:   .res    2
q_b1:   .res    2
q_t:    .res    2
q_c:    .res    2

        .segment "BSS"
ms_a:   .res    2
ms_b:   .res    2
pw_x:   .res    8
pw_r:   .res    8
pw_o:   .res    8
pm_r:   .res    8
pm_a:   .res    8
n_pn:   .res    2
pw_e:   .res    2
pw_s:   .res    2
pw_m:   .res    2
pw_k:   .res    2
ps_y0:  .res    2
ps_nd:  .res    2
ps_fd:  .res    2
ps_ov:  .res    2
ps_d:   .res    2
n_pflags: .res  2
fm_f:   .res    2
fm_neg: .res    2
fm_s:   .res    2
fm_d:   .res    2
fm_pad: .res    2
fm_g:   .res    2
fm_q:   .res    2
fm_i:   .res    2
fm_e:   .res    2
fm_w:   .res    2
fm_c:   .res    2
        .segment "CODE"
