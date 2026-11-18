; bas_fn.s - the functions of floating point: SQR, SIN, COS, TAN, ATN, EXP, LOG, LOG10,
; INT, FIX, ROUND, PI, the power x ^ y of real numbers; DEG and RAD.
;
; Each works on FA (bas_fp.s) with 12-digit operations (fm_*: FA = FA op a packed number in
; memory, rounded), the intermediate values in the fx_ cells:
;   SIN, COS, TAN: k = round(x * 2 / pi); r = x - k * pi / 2 (pi / 2 in two parts, the first
;     of 7 digits: k * it and x - k * it are exact in 16 digits, so r has about 11 correct
;     digits up to |x| = 1E6, 10 to 1E8, 9 to 1E9); then
;     sin(r) = r * S(r^2) or cos(r) = C(r^2) by the quadrant k mod 4. In DEG mode the
;     reduction is exact: r = (x - 90 k) * pi / 180, so SIN(180) is 0.
;   ATN: |x| > 1: pi / 2 - atn(1 / x); t > 2 - sqrt(3): pi / 6 + atn((t sqrt(3) - 1) /
;     (t + sqrt(3))); then t * A(t^2).
;   EXP: k = round(x / ln 10), r = x - k ln 10 (ln 10 in two parts); j = round(10 r),
;     t = r - j / 10 (exact); e^x = 10^k * e^(j / 10) (table) * E(t), |t| <= 0.05.
;   LOG: x = y * 10^n, 0.3162 <= y < 3.162; c = y's first two digits (0.31 .. 0.99,
;     1.0 .. 3.1); ln y = ln c (table) + 2 s L(s^2), s = (y - c) / (y + c) <= 0.05;
;     + n ln 10 (ln 10 in two parts, the exact one added last: no cancellation).
;     LOG10 = n + ln y / ln 10 (powers of ten exact).
;   x ^ y: y a whole number (|y| < 2^31): repeated squaring (1 / x first for y < 0);
;     else e^(y ln x) (x > 0).
; S, C, A, E, L are Chebyshev fits (tests/basic_fp.py consts) of 6, 7, 7, 7, 4 terms, all
; within 2E-13 of the function before the rounding of the operations.

        .segment "CODE"
        .a16
        .i16

; "(" a number ")" -> acc (an integer or a float)
arg1n:  lda     #'('
        jsr     expect
        jsr     eval_num
        lda     #')'
        jmp     expect

; ---------------------------------------------------------------- the functions
f_sqr:  jsr     arg1n
        ldx     #FAX
        jsr     fp_unp
        jsr     fp_sqrt
        jmp     fp_pack

f_sin:  lda     #0
        bra     fsc_go
f_cos:  lda     #1
        bra     fsc_go
f_tan:  lda     #2
fsc_go: pha
        jsr     arg1n
        ldx     #FAX
        jsr     fp_unp
        pla
        jsr     fn_sc
        jmp     fp_pack

f_atn:  jsr     arg1n
        ldx     #FAX
        jsr     fp_unp
        jsr     fn_atn
        jmp     fp_pack

f_exp:  jsr     arg1n
        ldx     #FAX
        jsr     fp_unp
        jsr     fn_exp
        jmp     fp_pack

f_log:  lda     #0
        bra     :+
f_log10:
        lda     #1
:       pha
        jsr     arg1n
        ldx     #FAX
        jsr     fp_unp
        pla
        jsr     fn_log
        jmp     fp_pack

f_pi:   jsr     noargs
        ldy     #.loword(c_pi)
        jmp     ld_acc

; the packed number at Y -> acc
ld_acc: lda     a:0,y
        sta     ft
        lda     a:2,y
        sta     flo
        lda     a:4,y
        sta     fhi
        lda     a:6,y
        sta     flen
        rts

; INT(x) the largest whole number <= x, FIX(x) without the fraction
f_int:  lda     #2
        bra     :+
f_fix:  lda     #0
:       pha
        jsr     arg1n
        pla
        ldx     ft
        bne     :+
        rts                             ; an integer: itself
:       sta     fi_md
        ldx     #FAX
        jsr     fp_unp
        lda     fi_md
        jsr     fp_toint
        bcs     :+
        lda     z:fw
        sta     flo
        lda     z:fw+2
        sta     fhi
        stz     ft
        rts
:       lda     fa_e                    ; beyond 32 bits: a float
        ldx     fi_md
        jsr     fp_rdig
        jmp     fp_pack

; ROUND(x [, n]): x rounded to n decimals (default 0; n < 0: to tens, hundreds ...),
; halves away from 0
f_round:
        lda     #'('
        jsr     expect
        jsr     eval_num
        stz     fi_n
        jsr     peek
        cmp     #','
        bne     @np
        inc     z:tp
        jsr     vpush
        jsr     eval_int
        lda     flo                     ; -99 .. 99
        clc
        adc     #99
        cmp     #199
        bcs     @bad
        lda     flo
        bpl     :+
        lda     fhi
        inc     a
        bne     @bad
        bra     :++
:       lda     fhi
        bne     @bad
:
        lda     flo
        sta     fi_n
        jsr     vpop
@np:    lda     #')'
        jsr     expect
        lda     ft
        bne     :+
        lda     fi_n                    ; an integer, n >= 0: itself
        bpl     @x
:       ldx     #FAX
        jsr     fp_unp
        lda     fa_e
        clc
        adc     fi_n
        ldx     #1
        jsr     fp_rdig
        jsr     fp_pack
        lda     fi_n
        bmi     :+
        bne     @x
:       jmp     fp_demote
@x:     rts
@bad:   err     E_ARG

; (1.2) VSYNC: waits for the next vertical blank (60 a second): a game's loop draws once a
; frame without tearing
; DEG, RAD: the unit of SIN, COS, TAN and ATN (RUN: radians)
st_deg: lda     #1
        sta     degm
        jmp     stmt_end
st_rad: stz     degm
        jmp     stmt_end

; ---------------------------------------------------------------- SIN COS TAN
; FA = sin / cos / tan (A = 0 / 1 / 2) of FA
fn_sc:  sta     sc_md
        lda     fa_e                    ; |x| < 1E9
        bmi     :+
        cmp     #10
        bcc     :+
        err     E_FUNC
:       ldx     #.loword(fx_x)
        jsr     fp_stm
        stz     sc_30
        lda     degm
        beq     @rad
        ldy     #.loword(c_i90)         ; degrees: k = round(x / 90), r = (x - 90 k) pi / 180
        jsr     fm_mul
        lda     #1
        jsr     fp_toint
        lda     z:fw
        sta     sc_q
        ldx     #FAX
        jsr     fp_i2fw
        ldy     #.loword(c_90)          ; 90 k (exact)
        jsr     fm_mul
        ldx     #.loword(fx_t1)
        jsr     fp_stm
        ldy     #.loword(fx_x)
        jsr     fm_ld
        ldy     #.loword(fx_t1)
        jsr     fm_sub
        lda     fa_e                    ; r = +-30 degrees: sin 0.5 exactly
        cmp     #2
        bne     :+
        lda     fa+6
        cmp     #$3000
        bne     :+
        lda     fa+4
        ora     fa+2
        bne     :+
        lda     fa_s
        inc     a
        sta     sc_30
:       ldy     #.loword(c_d2r)
        jsr     fm_mul
        bra     @red
@rad:   ldy     #.loword(c_2pi)         ; k = round(x * 2 / pi)
        jsr     fm_mul
        lda     #1
        jsr     fp_toint
        lda     z:fw
        sta     sc_q
        ldx     #FAX                    ; r = (x - k C1) - k C2, the products and the
        jsr     fp_i2fw                 ; first difference in 16 digits (exact)
        ldx     #.loword(fx_k)
        jsr     fp_stm
        ldy     #.loword(c_pi2a)
        ldx     #FBX
        jsr     fp_unpm
        jsr     fp_mul
        jsr     fp_cpab
        ldy     #.loword(fx_x)
        jsr     fm_ld
        jsr     fp_sub
        ldx     #10
:       lda     fa,x
        sta     fx_raw,x
        dex
        dex
        bpl     :-
        ldy     #.loword(fx_k)
        jsr     fm_ld
        ldy     #.loword(c_pi2b)
        ldx     #FBX
        jsr     fp_unpm
        jsr     fp_mul
        jsr     fp_cpab
        ldx     #10
:       lda     fx_raw,x
        sta     fa,x
        dex
        dex
        bpl     :-
        jsr     fp_sub
        jsr     fp_rnd
@red:   ldx     #.loword(fx_r)          ; r, r^2
        jsr     fp_stm
        ldy     #.loword(fx_r)
        jsr     fm_mul
        ldx     #.loword(fx_z)
        jsr     fp_stm
        lda     sc_md
        cmp     #2
        beq     @tan
        clc                             ; cos x = sin(x + pi / 2)
        adc     sc_q
        sta     sc_q
        lsr     a
        bcs     :+
        jsr     sin_r
        bra     :++
:       jsr     cos_r
:       lda     sc_q
        and     #2
        beq     :+
        lda     fa_s
        eor     #1
        sta     fa_s
:       rts
@tan:   jsr     cos_r                   ; k even: sin r / cos r; odd: -cos r / sin r
        ldx     #.loword(fx_t1)
        jsr     fp_stm
        jsr     sin_r
        lda     sc_q
        lsr     a
        bcs     :+
        ldy     #.loword(fx_t1)
        jmp     fm_div
:       ldx     #.loword(fx_t2)
        jsr     fp_stm
        ldy     #.loword(fx_t1)
        jsr     fm_ld
        ldy     #.loword(fx_t2)
        jsr     fm_div
        lda     fa_s
        eor     #1
        sta     fa_s
        rts
; FA = sin(r), cos(r) (r at fx_r, r^2 at fx_z; sc_30: r = 30 degrees (1) or -30 (2))
sin_r:  lda     sc_30
        beq     :+
        ldy     #.loword(c_half)
        jsr     fm_ld
        lda     sc_30
        dec     a
        sta     fa_s
        rts
:       ldy     #.loword(sin_c)
        lda     #6
        jsr     fpoly
        ldy     #.loword(fx_r)
        jmp     fm_mul
cos_r:  lda     sc_30
        beq     :+
        ldy     #.loword(c_c30)
        jmp     fm_ld
:       ldy     #.loword(cos_c)
        lda     #7
        jmp     fpoly

; ---------------------------------------------------------------- ATN
fn_atn: lda     fa_s
        sta     at_sg
        stz     fa_s
        stz     at_inv
        stz     at_six
        ldy     #.loword(c_one)         ; |x| > 1: 1 / |x|
        ldx     #FBX
        jsr     fp_unpm
        jsr     fp_cmp
        cmp     #4
        bne     :+
        jsr     fp_cpab
        ldy     #.loword(c_one)
        jsr     fm_ld
        jsr     fp_div
        jsr     fp_rnd
        inc     at_inv
:       ldy     #.loword(c_tp12)        ; t > 2 - sqrt(3): (t sqrt(3) - 1) / (t + sqrt(3))
        ldx     #FBX
        jsr     fp_unpm
        jsr     fp_cmp
        cmp     #4
        bne     @s
        ldx     #.loword(fx_x)
        jsr     fp_stm
        ldy     #.loword(c_sq3)
        jsr     fm_add
        ldx     #.loword(fx_t1)
        jsr     fp_stm
        ldy     #.loword(fx_x)
        jsr     fm_ld
        ldy     #.loword(c_sq3)
        jsr     fm_mul
        ldy     #.loword(c_one)
        jsr     fm_sub
        ldy     #.loword(fx_t1)
        jsr     fm_div
        inc     at_six
@s:     ldx     #.loword(fx_r)
        jsr     fp_stm
        ldy     #.loword(fx_r)
        jsr     fm_mul
        ldx     #.loword(fx_z)
        jsr     fp_stm
        ldy     #.loword(atn_c)
        lda     #7
        jsr     fpoly
        ldy     #.loword(fx_r)
        jsr     fm_mul
        lda     at_six
        beq     :+
        ldy     #.loword(c_pi6)
        jsr     fm_add
:       lda     at_inv
        beq     :+
        lda     fa_s
        eor     #1
        sta     fa_s
        ldy     #.loword(c_pi2)
        jsr     fm_add
:       lda     at_sg
        beq     :+
        lda     fa_s
        eor     #1
        sta     fa_s
:       lda     degm
        beq     :+
        ldy     #.loword(c_r2d)
        jmp     fm_mul
:       rts

; ---------------------------------------------------------------- EXP
fn_exp: lda     fa+6
        bne     :+
        ldy     #.loword(c_one)         ; e^0 = 1
        jmp     fm_ld
:       lda     fa_e                    ; |x| >= 1000: Overflow, or 0
        bmi     @ok
        cmp     #4
        bcc     @ok
        lda     fa_s
        bne     :+
        err     E_OVF
:       jmp     fp_zero
@ok:    ldx     #10                     ; x (all 16 digits: x ^ y passes a product)
:       lda     fa,x
        sta     fx_raw,x
        dex
        dex
        bpl     :-
        ldy     #.loword(c_l10e)        ; k = round(x / ln 10)
        jsr     fm_mul
        lda     #1
        jsr     fp_toint
        lda     z:fw
        sta     ex_k
        ldx     #FAX
        jsr     fp_i2fw
        ldx     #.loword(fx_k)
        jsr     fp_stm
        ldy     #.loword(c_ln10b)
        jsr     fm_mul
        ldx     #.loword(fx_t1)
        jsr     fp_stm
        ldy     #.loword(fx_k)
        jsr     fm_ld
        ldy     #.loword(c_ln10a)
        jsr     fm_mul
        ldx     #.loword(fx_t2)
        jsr     fp_stm
        ldx     #10                     ; r = x - k ln 10
:       lda     fx_raw,x
        sta     fa,x
        dex
        dex
        bpl     :-
        ldy     #.loword(fx_t2)
        ldx     #FBX
        jsr     fp_unpm
        jsr     fp_sub
        ldy     #.loword(fx_t1)
        jsr     fm_sub
        ldx     #.loword(fx_r)
        jsr     fp_stm
        inc     fa_e                    ; j = round(10 r)
        lda     #1
        jsr     fp_toint
        lda     z:fw
        sta     ex_j
        ldx     #FAX
        jsr     fp_i2fw
        dec     fa_e                    ; j / 10
        ldx     #.loword(fx_t1)
        jsr     fp_stm
        ldy     #.loword(fx_r)          ; t = r - j / 10
        jsr     fm_ld
        ldy     #.loword(fx_t1)
        jsr     fm_sub
        ldx     #.loword(fx_z)
        jsr     fp_stm
        ldy     #.loword(exp_c)
        lda     #7
        jsr     fpoly
        lda     ex_j                    ; * e^(j / 10)
        clc
        adc     #12
        asl     a
        asl     a
        asl     a
        adc     #.loword(exp_t)
        tay
        jsr     fm_mul
        lda     fa_e                    ; * 10^k
        clc
        adc     ex_k
        sta     fa_e
        jmp     fp_rnd

; ---------------------------------------------------------------- LOG
; FA = ln(FA) (A = 0; 2: 16 digits, not rounded) or log10(FA) (A = 1); Illegal function
; call for x <= 0
fn_log: sta     lg_md
        lda     fa+6
        jeq     @bad
        lda     fa_s
        jne     @bad
        lda     fa+6                    ; x = y * 10^n, y in 0.3162 .. 3.162
        cmp     #$3162
        bcc     :+
        lda     fa_e                    ; y = 0.d1d2.., c = 0.d1d2
        sta     lg_n
        stz     fa_e
        lda     #$8004
        sta     fx_c
        lda     #$10000 - 31
        bra     :++
:       lda     fa_e                    ; y = d1.d2.., c = d1.d2
        dec     a
        sta     lg_n
        lda     #1
        sta     fa_e
        lda     #$8104
        sta     fx_c
        lda     #69 - 10
:       sta     lg_i
        stz     fx_c+2
        stz     fx_c+4
        lda     fa+6
        and     #$FF00
        sta     fx_c+6
        xba
        jsr     bcd8
        clc
        adc     lg_i
        asl     a
        asl     a
        asl     a
        sta     lg_i
        ldx     #.loword(fx_x)
        jsr     fp_stm
        ldy     #.loword(fx_c)          ; s = (y - c) / (y + c)
        jsr     fm_sub
        ldx     #.loword(fx_t1)
        jsr     fp_stm
        ldy     #.loword(fx_x)
        jsr     fm_ld
        ldy     #.loword(fx_c)
        jsr     fm_add
        ldx     #.loword(fx_t2)
        jsr     fp_stm
        ldy     #.loword(fx_t1)
        jsr     fm_ld
        ldy     #.loword(fx_t2)
        jsr     fm_div
        ldx     #.loword(fx_r)
        jsr     fp_stm
        ldy     #.loword(fx_r)
        jsr     fm_mul
        ldx     #.loword(fx_z)
        jsr     fp_stm
        ldy     #.loword(log_c)
        lda     #4
        jsr     fpoly
        ldy     #.loword(fx_r)          ; 2 s L(s^2)
        jsr     fm_mul
        ldx     #.loword(fx_t1)
        jsr     fp_stm
        ldy     #.loword(fx_t1)
        jsr     fm_add
        lda     lg_i                    ; + ln c = ln y
        clc
        adc     #.loword(ln_t)
        tay
        jsr     @add
        lda     lg_md
        cmp     #1
        beq     @l10
        lda     lg_n                    ; + n ln 10: n * its 7 digits (exact) last
        beq     @x
        ldx     #.loword(fx_t1)
        jsr     fp_stm
        lda     lg_n
        jsr     fp_i16
        ldx     #.loword(fx_k)
        jsr     fp_stm
        ldy     #.loword(c_ln10b)
        jsr     fm_mul
        ldy     #.loword(fx_t1)
        jsr     fm_add
        ldx     #.loword(fx_t1)
        jsr     fp_stm
        ldy     #.loword(fx_k)
        jsr     fm_ld
        ldy     #.loword(c_ln10a)
        jsr     fm_mul
        ldy     #.loword(fx_t1)
@add:   ldx     #FBX                    ; (A = 2: the last sums not rounded, for x ^ y)
        jsr     fp_unpm
        jsr     fp_add
        lda     lg_md
        cmp     #2
        beq     @x
        jmp     fp_rnd
@l10:   ldy     #.loword(c_l10e)        ; ln y / ln 10 + n
        jsr     fm_mul
        ldx     #.loword(fx_t1)
        jsr     fp_stm
        lda     lg_n
        jsr     fp_i16
        ldy     #.loword(fx_t1)
        jmp     fm_add
@x:     rts
@bad:   err     E_FUNC

; ---------------------------------------------------------------- x ^ y
; FA = FA ^ FB
fp_pow: ldx     #.loword(fx_px)
        jsr     fp_stm
        jsr     fp_cpba
        ldx     #.loword(fx_py)
        jsr     fp_stm
        lda     #0                      ; a whole number?
        jsr     fp_toint
        bcs     @real
        lda     fb
        ora     z:fstk
        bne     @real
        lda     z:fw                    ; (|y| < 100: squarings, exact for 10 ^ n;
        sta     pw_n                    ; beyond, their rounding errors would add up)
        clc
        adc     #99
        cmp     #199
        bcs     @real
        lda     z:fw
        asl     a                       ; (the high word: the low one's sign)
        lda     #0
        sbc     #0
        eor     #$FFFF
        cmp     z:fw+2
        bne     @real
        sta     pw_n+2
        ldy     #.loword(fx_px)
        jsr     fm_ld
        jmp     fp_powi
@real:  ldy     #.loword(fx_px)
        jsr     fm_ld
        lda     fa+6
        bne     :+
        lda     fx_py                   ; 0 ^ y: 0, or Division by zero for y < 0
        lsr     a
        bcc     @x
        err     E_DIV0
:       lda     fa_s
        beq     :+
        err     E_FUNC
:       lda     #2
        jsr     fn_log
        jsr     fp_cpab                 ; (ln x, y ln x unrounded: 16 digits into e^)
        ldy     #.loword(fx_py)
        jsr     fm_ld
        jsr     fp_mul
        jmp     fn_exp
@x:     rts

; FA = FA ^ pw_n (a 32-bit integer): squarings
fp_powi:
        lda     pw_n+2
        bpl     :+
        lda     #0                      ; x ^ -n = (1 / x) ^ n
        sec
        sbc     pw_n
        sta     pw_n
        lda     #0
        sbc     pw_n+2
        sta     pw_n+2
        jsr     fp_cpab
        ldy     #.loword(c_one)
        jsr     fm_ld
        jsr     fp_div
        jsr     fp_rnd
:       ldx     #.loword(fx_pb)
        jsr     fp_stm
        ldy     #.loword(c_one)
        ldx     #.loword(fx_pr)
        jsr     cp8
@l:     lda     pw_n
        ora     pw_n+2
        beq     @done
        lsr     pw_n+2
        ror     pw_n
        bcc     @sq
        ldy     #.loword(fx_pr)         ; r = r * b
        jsr     fm_ld
        ldy     #.loword(fx_pb)
        jsr     fm_mul
        ldx     #.loword(fx_pr)
        jsr     fp_stm
@sq:    lda     pw_n
        ora     pw_n+2
        beq     @done
        ldy     #.loword(fx_pb)         ; b = b * b
        jsr     fm_ld
        ldy     #.loword(fx_pb)
        jsr     fm_mul
        ldx     #.loword(fx_pb)
        jsr     fp_stm
        bra     @l
@done:  ldy     #.loword(fx_pr)
        jmp     fm_ld

; the 8 bytes at Y -> X (our bank)
cp8:    lda     a:0,y
        sta     a:0,x
        lda     a:2,y
        sta     a:2,x
        lda     a:4,y
        sta     a:4,x
        lda     a:6,y
        sta     a:6,x
        rts

; ---------------------------------------------------------------- constants (packed)
        .segment "RODATA"
c_90:   .word   0, 90, 0, 0             ; 90
c_2p31: .word   $8A04, $4800, $4836, $2147   ; 2147483648
c_one:
        .word   $8104, $0000, $0000, $1000   ; 1
c_half:
        .word   $8004, $0000, $0000, $5000   ; 0.5
c_c30:
        .word   $8004, $3784, $2540, $8660   ; cos(30 degrees)
c_pi:
        .word   $8104, $5359, $5926, $3141   ; pi
c_pi2:
        .word   $8104, $2679, $7963, $1570   ; pi / 2
c_pi6:
        .word   $8004, $5598, $9877, $5235   ; pi / 6
c_2pi:
        .word   $8004, $2368, $1977, $6366   ; 2 / pi
c_pi2a:
        .word   $8104, $0000, $7960, $1570   ; pi / 2, its first 7 digits (k * it is exact in 16 digits)
c_pi2b:
        .word   $7A04, $6619, $9489, $3267   ; pi / 2 - c_pi2a
c_d2r:
        .word   $7F04, $5199, $3292, $1745   ; pi / 180
c_r2d:
        .word   $8204, $5131, $5779, $5729   ; 180 / pi
c_i90:
        .word   $7F04, $1111, $1111, $1111   ; 1 / 90
c_sq3:
        .word   $8104, $0757, $0508, $1732   ; sqrt(3)
c_tp12:
        .word   $8004, $2431, $4919, $2679   ; tan(pi / 12) = 2 - sqrt(3)
c_ln10:
        .word   $8104, $9299, $5850, $2302   ; ln(10)
c_ln10a:
        .word   $8104, $0000, $5850, $2302   ; ln(10), its first 7 digits
c_ln10b:
        .word   $7904, $6840, $4045, $9299   ; ln(10) - c_ln10a
c_l10e:
        .word   $8004, $1903, $9448, $4342   ; 1 / ln(10) = log10(e)
sin_c:                          ; sin(r) = r * S(r^2), |r| <= pi / 4, 6 terms
        .word   $7905, $7720, $6558, $2475   ; x^5
        .word   $7B04, $8934, $5271, $2755   ; x^4
        .word   $7D05, $2984, $1263, $1984   ; x^3
        .word   $7E04, $2388, $3333, $8333   ; x^2
        .word   $8005, $6666, $6666, $1666   ; x^1
        .word   $8104, $0000, $0000, $1000   ; x^0
cos_c:                          ; cos(r) = C(r^2), 7 terms
        .word   $7804, $3797, $0454, $2063   ; x^6
        .word   $7A05, $8848, $5233, $2755   ; x^5
        .word   $7C04, $5386, $1578, $2480   ; x^4
        .word   $7E05, $8700, $8888, $1388   ; x^3
        .word   $7F04, $6665, $6666, $4166   ; x^2
        .word   $8005, $0000, $0000, $5000   ; x^1
        .word   $8104, $0000, $0000, $1000   ; x^0
atn_c:                          ; atn(t) = t * A(t^2), |t| <= 2 - sqrt(3), 7 terms
        .word   $7F04, $5024, $3989, $6220   ; x^6
        .word   $7F05, $5659, $8208, $8951   ; x^5
        .word   $8004, $9075, $4443, $1110   ; x^4
        .word   $8005, $6759, $5548, $1428   ; x^3
        .word   $8004, $0313, $9998, $1999   ; x^2
        .word   $8005, $3245, $3333, $3333   ; x^1
        .word   $8104, $0000, $0000, $1000   ; x^0
exp_c:                          ; exp(t), |t| <= 0.05, 7 terms
        .word   $7E04, $9960, $9973, $1388   ; x^6
        .word   $7E04, $2657, $2014, $8334   ; x^5
        .word   $7F04, $5310, $6666, $4166   ; x^4
        .word   $8004, $5582, $6666, $1666   ; x^3
        .word   $8004, $0000, $0000, $5000   ; x^2
        .word   $8104, $0000, $0000, $1000   ; x^1
        .word   $8104, $0000, $0000, $1000   ; x^0
log_c:                          ; ln((1 + s) / (1 - s)) = 2 s L(s^2), |s| <= 0.05, 4 terms
        .word   $8004, $4828, $1426, $1434   ; x^3
        .word   $8004, $8740, $9912, $1999   ; x^2
        .word   $8004, $3769, $3333, $3333   ; x^1
        .word   $8104, $0000, $0000, $1000   ; x^0
exp_t:                          ; e^(j / 10), j = -12 .. 12
        .word   $8004, $1912, $9421, $3011   ; e^-1.2
        .word   $8004, $3698, $7108, $3328   ; e^-1.1
        .word   $8004, $1171, $7944, $3678   ; e^-1.0
        .word   $8004, $9741, $6965, $4065   ; e^-0.9
        .word   $8004, $4117, $2896, $4493   ; e^-0.8
        .word   $8004, $3791, $8530, $4965   ; e^-0.7
        .word   $8004, $6094, $1163, $5488   ; e^-0.6
        .word   $8004, $9713, $3065, $6065   ; e^-0.5
        .word   $8004, $6036, $2004, $6703   ; e^-0.4
        .word   $8004, $0682, $1822, $7408   ; e^-0.3
        .word   $8004, $3078, $3075, $8187   ; e^-0.2
        .word   $8004, $8036, $3741, $9048   ; e^-0.1
        .word   $8104, $0000, $0000, $1000   ; e^0.0
        .word   $8104, $1808, $1709, $1105   ; e^0.1
        .word   $8104, $5816, $4027, $1221   ; e^0.2
        .word   $8104, $0758, $8588, $1349   ; e^0.3
        .word   $8104, $9764, $8246, $1491   ; e^0.4
        .word   $8104, $7070, $7212, $1648   ; e^0.5
        .word   $8104, $0039, $1188, $1822   ; e^0.6
        .word   $8104, $0747, $7527, $2013   ; e^0.7
        .word   $8104, $2849, $5409, $2225   ; e^0.8
        .word   $8104, $1116, $6031, $2459   ; e^0.9
        .word   $8104, $2846, $2818, $2718   ; e^1.0
        .word   $8104, $2395, $1660, $3004   ; e^1.1
        .word   $8104, $2274, $1169, $3320   ; e^1.2
ln_t:                           ; ln(c), c = 0.31, 0.32 .. 0.99, then 1.0, 1.1 .. 3.1
        .word   $8105, $8150, $1829, $1171   ; ln 0.31
        .word   $8105, $8319, $4342, $1139   ; ln 0.32
        .word   $8105, $2452, $6626, $1108   ; ln 0.33
        .word   $8105, $6137, $8096, $1078   ; ln 0.34
        .word   $8105, $2450, $8221, $1049   ; ln 0.35
        .word   $8105, $4753, $6512, $1021   ; ln 0.36
        .word   $8005, $3344, $5227, $9942   ; ln 0.37
        .word   $8005, $6262, $8402, $9675   ; ln 0.38
        .word   $8005, $9858, $0853, $9416   ; ln 0.39
        .word   $8005, $1874, $9073, $9162   ; ln 0.40
        .word   $8005, $9284, $9811, $8915   ; ln 0.41
        .word   $8005, $7705, $0056, $8675   ; ln 0.42
        .word   $8005, $0295, $7007, $8439   ; ln 0.43
        .word   $8005, $2070, $8055, $8209   ; ln 0.44
        .word   $8005, $6218, $0769, $7985   ; ln 0.45
        .word   $8005, $9499, $2878, $7765   ; ln 0.46
        .word   $8005, $4278, $2258, $7550   ; ln 0.47
        .word   $8005, $5080, $6917, $7339   ; ln 0.48
        .word   $8005, $7877, $4988, $7133   ; ln 0.49
        .word   $8005, $0560, $4718, $6931   ; ln 0.50
        .word   $8005, $3264, $4455, $6733   ; ln 0.51
        .word   $8005, $7407, $2646, $6539   ; ln 0.52
        .word   $8005, $2436, $7827, $6348   ; ln 0.53
        .word   $8005, $9424, $8613, $6161   ; ln 0.54
        .word   $8005, $0756, $3700, $5978   ; ln 0.55
        .word   $8005, $5253, $1849, $5798   ; ln 0.56
        .word   $8005, $8154, $1891, $5621   ; ln 0.57
        .word   $8005, $5442, $2717, $5447   ; ln 0.58
        .word   $8005, $2082, $3274, $5276   ; ln 0.59
        .word   $8005, $3766, $2562, $5108   ; ln 0.60
        .word   $8005, $1815, $9632, $4942   ; ln 0.61
        .word   $8005, $0943, $3580, $4780   ; ln 0.62
        .word   $8005, $9597, $3545, $4620   ; ln 0.63
        .word   $8005, $2628, $8710, $4462   ; ln 0.64
        .word   $8005, $6092, $8291, $4307   ; ln 0.65
        .word   $8005, $3962, $1544, $4155   ; ln 0.66
        .word   $8005, $6597, $7756, $4004   ; ln 0.67
        .word   $8005, $0812, $6248, $3856   ; ln 0.68
        .word   $8005, $1391, $6368, $3710   ; ln 0.69
        .word   $8005, $3939, $7494, $3566   ; ln 0.70
        .word   $8005, $8947, $9030, $3424   ; ln 0.71
        .word   $8005, $6972, $0406, $3285   ; ln 0.72
        .word   $8005, $4840, $1074, $3147   ; ln 0.73
        .word   $8005, $2784, $0509, $3011   ; ln 0.74
        .word   $8005, $2452, $8207, $2876   ; ln 0.75
        .word   $8005, $5702, $3684, $2744   ; ln 0.76
        .word   $8005, $4134, $6476, $2613   ; ln 0.77
        .word   $8005, $9298, $6135, $2484   ; ln 0.78
        .word   $8005, $3521, $2233, $2357   ; ln 0.79
        .word   $8005, $1314, $4355, $2231   ; ln 0.80
        .word   $8005, $1316, $2103, $2107   ; ln 0.81
        .word   $8005, $8724, $5093, $1984   ; ln 0.82
        .word   $8005, $8191, $2957, $1863   ; ln 0.83
        .word   $8005, $7145, $5338, $1743   ; ln 0.84
        .word   $8005, $9498, $1892, $1625   ; ln 0.85
        .word   $8005, $9735, $2288, $1508   ; ln 0.86
        .word   $8005, $7334, $6206, $1392   ; ln 0.87
        .word   $8005, $1510, $3337, $1278   ; ln 0.88
        .word   $8005, $6256, $3381, $1165   ; ln 0.89
        .word   $8005, $5658, $6051, $1053   ; ln 0.90
        .word   $7F05, $4712, $0679, $9431   ; ln 0.91
        .word   $7F05, $9391, $1608, $8338   ; ln 0.92
        .word   $7F05, $8348, $0692, $7257   ; ln 0.93
        .word   $7F05, $7181, $5403, $6187   ; ln 0.94
        .word   $7F05, $3876, $3294, $5129   ; ln 0.95
        .word   $7F05, $5203, $1994, $4082   ; ln 0.96
        .word   $7F05, $4847, $9207, $3045   ; ln 0.97
        .word   $7F05, $3175, $2707, $2020   ; ln 0.98
        .word   $7F05, $8535, $0335, $1005   ; ln 0.99
        .word   $0000, $0000, $0000, $0000   ; ln 1.0
        .word   $7F04, $8043, $0179, $9531   ; ln 1.1
        .word   $8004, $6794, $2155, $1823   ; ln 1.2
        .word   $8004, $4467, $6426, $2623   ; ln 1.3
        .word   $8004, $6621, $7223, $3364   ; ln 1.4
        .word   $8004, $8108, $6510, $4054   ; ln 1.5
        .word   $8004, $9246, $0362, $4700   ; ln 1.6
        .word   $8004, $1062, $2825, $5306   ; ln 1.7
        .word   $8004, $4902, $8666, $5877   ; ln 1.8
        .word   $8004, $6172, $5388, $6418   ; ln 1.9
        .word   $8004, $0560, $4718, $6931   ; ln 2.0
        .word   $8004, $4729, $3734, $7419   ; ln 2.1
        .word   $8004, $0364, $5736, $7884   ; ln 2.2
        .word   $8004, $2935, $0912, $8329   ; ln 2.3
        .word   $8004, $7354, $6873, $8754   ; ln 2.4
        .word   $8004, $1874, $9073, $9162   ; ln 2.5
        .word   $8004, $5027, $1144, $9555   ; ln 2.6
        .word   $8004, $3010, $5177, $9932   ; ln 2.7
        .word   $8104, $1718, $6194, $1029   ; ln 2.8
        .word   $8104, $3699, $7107, $1064   ; ln 2.9
        .word   $8104, $8867, $6122, $1098   ; ln 3.0
        .word   $8104, $1149, $4021, $1131   ; ln 3.1

        .segment "BSS"
degm:   .res    2               ; 1: DEG
fi_md:  .res    2
fi_n:   .res    2
sc_md:  .res    2
sc_q:   .res    2
sc_30:  .res    2
at_sg:  .res    2
at_inv: .res    2
at_six: .res    2
ex_k:   .res    2
ex_j:   .res    2
lg_md:  .res    2
lg_n:   .res    2
lg_i:   .res    2
pw_n:   .res    4
fx_x:   .res    8
fx_k:   .res    8
fx_r:   .res    8
fx_c:   .res    8
fx_t1:  .res    8
fx_t2:  .res    8
fx_px:  .res    8
fx_py:  .res    8
fx_pb:  .res    8
fx_pr:  .res    8
fx_raw: .res    12
