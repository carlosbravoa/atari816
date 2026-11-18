; sht_fx.s - Sheet: formulas (part of sheet.s): the compiler, the reference adjuster used
; by copy / insert / delete, the evaluator and the functions.
;
; Grammar (lowest precedence first; spaces anywhere between tokens):
;   comparison  sum { (= | <> | < | > | <= | >=) sum }        1 if true, 0 if false
;   sum         product { (+ | -) product }
;   product     unary { (* | /) unary }
;   unary       - unary | + unary | power                     (-2^2 = -4)
;   power       primary [ ^ unary ]                           (right associative)
;   primary     number | reference | range | error | function ( args ) | ( comparison )
;   reference   [$]letter[$]row   (A1, $B$2; rows 1-999)      range: reference:reference
;   error       #DIV/0 #REF #VALUE #CYCLE #OVER (a trailing ! allowed)
; Code (reverse Polish, in the cell's record after its text):
;   OP_NUM v8, OP_REF ci16, OP_RNG ci16 ci16 (top left, bottom right), OP_ERR code8,
;   the operators, OP_FN id8 argc8
; Values on the evaluation stack: 10-byte slots {u16 tag, 8 bytes}: V_NUM (a number),
; V_ERR (an error, its code in the low byte), V_RNG (a range: two cell indexes), V_TXT (a
; text cell), V_EMP (an empty cell). An operator turns empty into 0, text and ranges into
; #VALUE; functions over lists (SUM ...) skip text and empty cells.
OP_NUM  = 1
OP_REF  = 2
OP_RNG  = 3
OP_ERR  = 4
OP_ADD  = 5
OP_SUB  = 6
OP_MUL  = 7
OP_DIV  = 8
OP_POW  = 9
OP_NEG  = 10
OP_EQ   = 11
OP_NE   = 12
OP_LT   = 13
OP_GT   = 14
OP_LE   = 15
OP_GE   = 16
OP_FN   = 17
V_NUM   = 0
V_ERR   = 1
V_RNG   = 2
V_TXT   = 3
V_EMP   = 4
CMAX    = 1400                          ; code bytes in a formula
MAXV    = 48                            ; evaluation stack slots
MAXDEP  = 40                            ; nesting of parentheses and functions
F_SUM   = 0
F_AVG   = 1
F_MIN   = 2
F_MAX   = 3
F_COUNT = 4
F_AND   = 5
F_OR    = 6
F_ABS   = 7
F_INT   = 8
F_SQRT  = 9
F_NOT   = 10
F_ROUND = 11
F_MOD   = 12
F_IF    = 13
F_PMT   = 14

        .segment "CODE"

; ---------------------------------------------------------------- characters
; A = tbuf[Y] (one byte)
fx_ch:  lda     tbuf,y
        and     #$00FF
        rts
; skip spaces at tbuf[Y]
fx_ws:  lda     tbuf,y
        and     #$00FF
        cmp     #' '
        bne     :+
        iny
        bra     fx_ws
:       rts
; C set if A is a letter
isletter:
        pha
        and     #$00DF
        cmp     #'A'
        bcc     @no
        cmp     #'Z' + 1
        bcs     @no
        pla
        sec
        rts
@no:    pla
        clc
        rts
; C set if A is a digit
isdigit:
        cmp     #'0'
        bcc     @no
        cmp     #'9' + 1
        bcs     @no
        sec
        rts
@no:    clc
        rts

; a reference at tbuf[Y] -> C clear: rf_col, rf_row (0-based), rf_ac, rf_ar (the $ marks),
; Y past it; C set: none (Y unchanged)
rd_ref: sty     rf_y0
        stz     rf_ac
        stz     rf_ar
        jsr     fx_ch
        cmp     #'$'
        bne     :+
        inc     rf_ac
        iny
        jsr     fx_ch
:       jsr     isletter
        bcc     @no
        and     #$00DF
        sec
        sbc     #'A'
        sta     rf_col
        iny
        jsr     fx_ch
        cmp     #'$'
        bne     :+
        inc     rf_ar
        iny
        jsr     fx_ch
:       stz     rf_row
        ldx     #0                      ; digits
@d:     jsr     isdigit
        bcc     @e
        and     #$000F
        pha
        lda     rf_row                  ; row * 10 + digit (capped)
        cmp     #2000
        bcc     :+
        lda     #2000
:       asl     a
        sta     rf_t
        asl     a
        asl     a
        adc     rf_t
        sta     rf_row
        pla
        clc
        adc     rf_row
        sta     rf_row
        inx
        iny
        jsr     fx_ch
        bra     @d
@e:     cpx     #0
        beq     @no
        jsr     isletter                ; (A1B, A1_ are no references)
        bcs     @no
        cmp     #'_'
        beq     @no
        lda     rf_row
        beq     @no
        cmp     #NROW + 1
        bcs     @no
        dec     rf_row
        clc
        rts
@no:    ldy     rf_y0
        sec
        rts

; rf_col, rf_row -> A = the cell index
rf_ci:  lda     rf_col
        xba
        asl     a
        asl     a
        ora     rf_row
        rts

; ---------------------------------------------------------------- the compiler
; tbuf (a formula, "=" first, zero-terminated) -> cbuf, c_clen; C set: not a formula
fx_comp:
        tsx
        stx     fx_sp
        stz     c_clen
        stz     fx_dep
        stz     fx_sd
        stz     fx_smax
        ldy     #1
        jsr     p_cmp
        jsr     fx_ws
        jsr     fx_ch
        bne     fx_bad
        lda     fx_smax
        cmp     #MAXV
        bcs     fx_bad
        clc
        rts
fx_bad: ldx     fx_sp                   ; (from any depth)
        txs
        sec
        rts

; emit byte A
emit:   ldx     c_clen
        cpx     #CMAX
        bcs     fx_bad
        sep     #$20
        .a8
        sta     cbuf,x
        rep     #$20
        .a16
        inx
        stx     c_clen
        rts
; emit word A
emitw:  pha
        jsr     emit
        pla
        xba
        jmp     emit
; the stack depth: + 1 (an operand) / - 1 (a binary operator)
sd_inc: inc     fx_sd
        lda     fx_sd
        cmp     fx_smax
        bcc     :+
        sta     fx_smax
:       rts
sd_dec: dec     fx_sd
        rts

p_cmp:  jsr     p_add
@l:     jsr     fx_ws
        jsr     fx_ch
        cmp     #'='
        bne     :+
        iny
        lda     #OP_EQ
        bra     @op
:       cmp     #'<'
        bne     @gt
        iny
        jsr     fx_ch
        cmp     #'>'
        bne     :+
        iny
        lda     #OP_NE
        bra     @op
:       cmp     #'='
        bne     :+
        iny
        lda     #OP_LE
        bra     @op
:       lda     #OP_LT
        bra     @op
@gt:    cmp     #'>'
        bne     @x
        iny
        jsr     fx_ch
        cmp     #'='
        bne     :+
        iny
        lda     #OP_GE
        bra     @op
:       lda     #OP_GT
@op:    pha
        jsr     p_add
        pla
        jsr     emit
        jsr     sd_dec
        bra     @l
@x:     rts

p_add:  jsr     p_mul
@l:     jsr     fx_ws
        jsr     fx_ch
        cmp     #'+'
        bne     :+
        lda     #OP_ADD
        bra     @op
:       cmp     #'-'
        bne     @x
        lda     #OP_SUB
@op:    iny
        pha
        jsr     p_mul
        pla
        jsr     emit
        jsr     sd_dec
        bra     @l
@x:     rts

p_mul:  jsr     p_un
@l:     jsr     fx_ws
        jsr     fx_ch
        cmp     #'*'
        bne     :+
        lda     #OP_MUL
        bra     @op
:       cmp     #'/'
        bne     @x
        lda     #OP_DIV
@op:    iny
        pha
        jsr     p_un
        pla
        jsr     emit
        jsr     sd_dec
        bra     @l
@x:     rts

p_un:   jsr     fx_ws
        jsr     fx_ch
        cmp     #'-'
        bne     :+
        iny
        jsr     p_deep
        jsr     p_un
        dec     fx_dep
        lda     #OP_NEG
        jmp     emit
:       cmp     #'+'
        bne     p_pow
        iny
        jsr     p_deep
        jsr     p_un
        dec     fx_dep
        rts

p_pow:  jsr     p_prim
        jsr     fx_ws
        jsr     fx_ch
        cmp     #'^'
        bne     @x
        iny
        jsr     p_deep
        jsr     p_un
        dec     fx_dep
        lda     #OP_POW
        jsr     emit
        jsr     sd_dec
@x:     rts

; one level deeper (parentheses, functions, unary signs): at most MAXDEP
p_deep: inc     fx_dep
        lda     fx_dep
        cmp     #MAXDEP
        bcc     :+
        jmp     fx_bad
:       rts

p_prim: jsr     fx_ws
        jsr     fx_ch
        cmp     #'('
        bne     @num
        iny
        jsr     p_deep
        jsr     p_cmp
        dec     fx_dep
        jsr     fx_ws
        jsr     fx_ch
        cmp     #')'
        jne     fx_bad
        iny
        rts
@num:   jsr     isdigit
        bcs     :+
        cmp     #'.'
        bne     @err
:       lda     #.loword(tbuf)          ; the number: n_parse at [sp], Y
        sta     z:sp
        lda     #^tbuf
        sta     z:sp+2
        stz     n_pflags
        jsr     n_parse
        jcs     fx_bad
        lda     #OP_NUM
        jsr     emit
        lda     z:na
        jsr     emitw
        lda     z:na+2
        jsr     emitw
        lda     z:na+4
        jsr     emitw
        lda     z:na+6
        jsr     emitw
        jmp     sd_inc
@err:   cmp     #'#'
        bne     @id
        jsr     rd_errnm
        jcs     fx_bad
        pha
        lda     #OP_ERR
        jsr     emit
        pla
        jsr     emit
        jmp     sd_inc
@id:    cmp     #'$'
        beq     :+
        jsr     isletter
        jcc     fx_bad
:       jsr     rd_ref
        bcs     @fn
        jsr     rf_ci
        sta     fx_c1
        lda     rf_col
        sta     fx_col
        lda     rf_row
        sta     fx_row
        jsr     fx_ch
        cmp     #':'
        bne     @ref
        iny
        jsr     rd_ref
        jcs     fx_bad
        lda     rf_col                  ; top left, bottom right
        cmp     fx_col
        bcs     :+
        ldx     fx_col
        sta     fx_col
        stx     rf_col
:       lda     rf_row
        cmp     fx_row
        bcs     :+
        ldx     fx_row
        sta     fx_row
        stx     rf_row
:       lda     #OP_RNG
        jsr     emit
        lda     fx_col
        xba
        asl     a
        asl     a
        ora     fx_row
        jsr     emitw
        jsr     rf_ci
        jsr     emitw
        jmp     sd_inc
@ref:   lda     #OP_REF
        jsr     emit
        lda     fx_c1
        jsr     emitw
        jmp     sd_inc
@fn:    ldx     #0                      ; a name: letters, upper case, into fx_name
:       jsr     fx_ch
        jsr     isletter
        bcc     :+
        and     #$00DF
        cpx     #8
        jcs     fx_bad
        sep     #$20
        .a8
        sta     fx_name,x
        rep     #$20
        .a16
        inx
        iny
        bra     :-
:       stx     fx_nl
        cmp     #'('
        jne     fx_bad
        iny
        ldx     #0                      ; look it up: {len, name, id, min, max}
@look:  lda     fntable,x
        and     #$00FF
        jeq     fx_bad
        cmp     fx_nl
        bne     @skip
        stx     fx_e
        phy
        ldy     #0
:       lda     fntable+1,x
        eor     fx_name,y
        and     #$00FF
        bne     @ne
        inx
        iny
        cpy     fx_nl
        bcc     :-
        ply
        ldx     fx_e
        txa                             ; X = the entry + its name length
        clc
        adc     fx_nl
        tax
        bra     @found
@ne:    ply
        ldx     fx_e
@skip:  lda     fntable,x
        and     #$00FF
        clc
        adc     #4
        sta     fx_t
        txa
        clc
        adc     fx_t
        tax
        bra     @look
@found: lda     fntable+1,x                ; id, min, max (X = entry + len)
        and     #$00FF
        pha
        lda     fntable+2,x
        and     #$00FF
        pha
        lda     fntable+3,x
        and     #$00FF
        pha
        jsr     p_deep
        stz     fx_t                    ; the arguments
        jsr     fx_ws
        jsr     fx_ch
        cmp     #')'
        beq     @close
@arg:   lda     fx_t
        pha
        jsr     p_cmp
        pla
        inc     a
        sta     fx_t
        jsr     fx_ws
        jsr     fx_ch
        cmp     #','
        bne     :+
        iny
        bra     @arg
:       cmp     #')'
        jne     fx_bad
@close: iny
        dec     fx_dep
        pla                             ; max
        cmp     fx_t
        jcc     fx_bad
        pla                             ; min
        cmp     fx_t
        beq     :+
        jcs     fx_bad
:       lda     #OP_FN
        jsr     emit
        pla                             ; id
        jsr     emit
        lda     fx_t
        jsr     emit
        lda     fx_t                    ; the stack: argc values -> 1 (argc >= 1)
@sd:    dec     a
        beq     @sdx
        pha
        jsr     sd_dec
        pla
        bra     @sd
@sdx:   rts

; an error name at tbuf[Y] ('#') -> C clear: A = its code, Y past it (and a '!')
rd_errnm: sty     rf_y0
        ldx     #0                      ; the names: {len, name, code}
@e:     lda     errtab,x
        and     #$00FF
        beq     @no
        sta     fx_nl
        stx     fx_e
        ldy     rf_y0
        iny
        inx
@c:     jsr     fx_ch
        cmp     #'a'
        bcc     :+
        cmp     #'z' + 1
        bcs     :+
        and     #$00DF
:       sta     fx_t
        lda     errtab,x
        and     #$00FF
        cmp     fx_t
        bne     @miss
        inx
        iny
        dec     fx_nl
        bne     @c
        lda     errtab,x                  ; matched: the code
        and     #$00FF
        sta     fx_t
        jsr     fx_ch                   ; not followed by a letter or digit
        jsr     isletter
        bcs     @no
        jsr     isdigit
        bcs     @no
        cmp     #'!'
        bne     :+
        iny
:       lda     fx_t
        clc
        rts
@miss:  ldx     fx_e
        lda     errtab,x
        and     #$00FF
        clc
        adc     #2
        adc     fx_e
        tax
        bra     @e
@no:    ldy     rf_y0
        sec
        rts

; ---------------------------------------------------------------- the adjuster
; The formula in tbuf (c_tlen) rewritten with its references moved -> tbuf, c_tlen; C set:
; the result would be too long (tbuf unchanged).
;   aj_mode AJ_COPY: relative parts move by aj_dc columns, aj_dr rows ($ parts stay); a
;                    reference moved off the sheet becomes #REF
;   AJ_INSR / AJ_DELR: a row inserted / deleted at aj_at: every reference below moves (a
;                    reference to the deleted row becomes #REF; a range shrinks)
;   AJ_INSC / AJ_DELC: the same for a column
AJ_COPY = 0
AJ_INSR = 1
AJ_DELR = 2
AJ_INSC = 3
AJ_DELC = 4
fx_adj: ldy     #0
        stz     aj_ox
@l:     jsr     fx_ch
        jeq     @end
        cmp     #'$'
        beq     @id
        jsr     isletter
        bcs     @id
        jsr     isdigit
        bcs     @run
        cmp     #'.'
        beq     @run
        cmp     #'#'
        beq     @err
        jsr     aj_put
        iny
        bra     @l
@run:   jsr     aj_put                  ; a number: copied
        iny
        jsr     fx_ch
        jsr     isdigit
        bcs     @run
        cmp     #'.'
        beq     @run
        bra     @l
@err:   jsr     aj_put                  ; an error name: copied
        iny
        jsr     fx_ch
        jsr     isletter
        bcs     @err
        jsr     isdigit
        bcs     @err
        cmp     #'/'
        beq     @err
        cmp     #'!'
        beq     @err
        bra     @l
@id:    jsr     rd_ref
        bcc     @ref
@cp:    jsr     fx_ch                   ; a name: copied
        cmp     #'$'
        beq     :+
        cmp     #'_'
        beq     :+
        jsr     isdigit
        bcs     :+
        jsr     isletter
        bcc     @l
:       jsr     aj_put
        iny
        bra     @cp
@ref:   jsr     fx_ch
        cmp     #':'
        beq     @rng
        jsr     aj_one                  ; a single reference
        bcs     @bad
        jsr     aj_wref
        jmp     @l
@bad:   jsr     aj_wbad
        jmp     @l
@rng:   lda     rf_col                  ; a range: the first end aside
        sta     aj_c1
        lda     rf_row
        sta     aj_r1
        lda     rf_ac
        sta     aj_ac1
        lda     rf_ar
        sta     aj_ar1
        iny
        jsr     rd_ref
        bcc     :+
        dey                             ; (not a range after all: the first one alone)
        lda     aj_c1
        sta     rf_col
        lda     aj_r1
        sta     rf_row
        lda     aj_ac1
        sta     rf_ac
        lda     aj_ar1
        sta     rf_ar
        bra     @ref1
:       jsr     aj_two
        bcs     @bad
        jsr     aj_xchg                 ; the first end, ':', the second
        jsr     aj_wref
        lda     #':'
        jsr     aj_put
        jsr     aj_xchg
        jsr     aj_wref
        jmp     @l
@ref1:  jsr     aj_one
        bcs     @bad
        jsr     aj_wref
        lda     #':'                    ; the ':' that followed, as it was
        jsr     aj_put
        iny
        jmp     @l
@end:   lda     aj_ox
        cmp     #TXTMAX + 1
        bcs     @long
        tax
        stz     obuf,x
        ldx     #.loword(obuf)
        ldy     #.loword(tbuf)
        jsr     ui_strcpy
        sta     c_tlen
        clc
        rts
@long:  sec
        rts

; character A to obuf
aj_put: ldx     aj_ox
        cpx     #TXTMAX + 2
        bcs     :+
        sep     #$20
        .a8
        sta     obuf,x
        rep     #$20
        .a16
        inx
        stx     aj_ox
:       rts
aj_wbad:
        phy
        ldx     #0
:       lda     s_ref,x
        and     #$00FF
        beq     :+
        phx
        jsr     aj_put
        plx
        inx
        bra     :-
:       ply
        rts

; the reference rf_* written
aj_wref:
        phy
        lda     rf_ac
        beq     :+
        lda     #'$'
        jsr     aj_put
:       lda     rf_col
        clc
        adc     #'A'
        jsr     aj_put
        lda     rf_ar
        beq     :+
        lda     #'$'
        jsr     aj_put
:       lda     rf_row
        inc     a
        jsr     aj_num
        ply
        rts
; A (1-999) in decimal
aj_num: ldx     #0
:       cmp     #100
        bcc     :+
        sbc     #100
        inx
        bra     :-
:       sta     aj_t
        txa
        beq     :+
        ora     #'0'
        jsr     aj_put
        lda     #1
        sta     aj_t2
        bra     @tens
:       stz     aj_t2
@tens:  lda     aj_t
        ldx     #0
:       cmp     #10
        bcc     :+
        sbc     #10
        inx
        bra     :-
:       sta     aj_t
        txa
        ora     aj_t2
        beq     :+
        txa
        ora     #'0'
        jsr     aj_put
:       lda     aj_t
        ora     #'0'
        jmp     aj_put

; one reference rf_* adjusted -> C set: it is gone (#REF)
aj_one: lda     aj_mode
        bne     @ins
        lda     rf_ac                   ; copy
        bne     :+
        lda     rf_col
        clc
        adc     aj_dc
        sta     rf_col
:       lda     rf_ar
        bne     :+
        lda     rf_row
        clc
        adc     aj_dr
        sta     rf_row
:       lda     rf_col
        cmp     #NCOL
        bcs     @gone
        lda     rf_row
        cmp     #NROW
        bcs     @gone
        clc
        rts
@gone:  sec
        rts
@ins:   cmp     #AJ_INSR
        bne     @delr
        lda     rf_row
        cmp     aj_at
        bcc     @ok
        inc     a
        sta     rf_row
        cmp     #NROW
        bcs     @gone
@ok:    clc
        rts
@delr:  cmp     #AJ_DELR
        bne     @insc
        lda     rf_row
        cmp     aj_at
        bcc     @ok
        beq     @gone
        dec     rf_row
        clc
        rts
@insc:  cmp     #AJ_INSC
        bne     @delc
        lda     rf_col
        cmp     aj_at
        bcc     @ok
        inc     a
        sta     rf_col
        cmp     #NCOL
        bcs     @gone
        clc
        rts
@delc:  lda     rf_col
        cmp     aj_at
        bcc     @ok
        beq     @gone
        dec     rf_col
        clc
        rts

; a range (first end aj_c1 .. aj_ar1, second rf_*) adjusted, in order (top left first)
; -> C set: it is gone
aj_two: lda     aj_c1                   ; order the columns, then the rows (with their $)
        cmp     rf_col
        bcc     :+
        beq     :+
        ldx     rf_col
        sta     rf_col
        stx     aj_c1
        lda     aj_ac1
        ldx     rf_ac
        sta     rf_ac
        stx     aj_ac1
:       lda     aj_r1
        cmp     rf_row
        bcc     :+
        beq     :+
        ldx     rf_row
        sta     rf_row
        stx     aj_r1
        lda     aj_ar1
        ldx     rf_ar
        sta     rf_ar
        stx     aj_ar1
:       lda     aj_mode
        bne     @struct
        jsr     aj_one                  ; copy: both ends move
        bcs     @gone
        jsr     aj_xchg
        jsr     aj_one
        php
        jsr     aj_xchg
        plp
        bcs     @gone
        clc
        rts
@gone:  sec
        rts
@struct:
        cmp     #AJ_INSR
        bne     @dr
        lda     aj_r1                   ; insert a row
        cmp     aj_at
        bcc     :+
        inc     aj_r1
:       lda     rf_row
        cmp     aj_at
        bcc     :+
        inc     rf_row
:       lda     aj_r1
        cmp     #NROW
        bcs     @gone
        lda     rf_row
        cmp     #NROW
        bcc     @ok
        lda     #NROW - 1
        sta     rf_row
@ok:    clc
        rts
@dr:    cmp     #AJ_DELR
        bne     @ic
        lda     aj_at                   ; delete a row
        cmp     aj_r1
        bne     :+
        cmp     rf_row
        beq     @gone
:       lda     aj_at
        cmp     aj_r1
        bcs     :+
        dec     aj_r1
        dec     rf_row
        bra     @ok
:       lda     rf_row
        cmp     aj_at
        bcc     @ok
        dec     rf_row
        bra     @ok
@ic:    cmp     #AJ_INSC
        bne     @dc
        lda     aj_c1
        cmp     aj_at
        bcc     :+
        inc     aj_c1
:       lda     rf_col
        cmp     aj_at
        bcc     :+
        inc     rf_col
:       lda     aj_c1
        cmp     #NCOL
        jcs     @gone
        lda     rf_col
        cmp     #NCOL
        bcc     @ok
        lda     #NCOL - 1
        sta     rf_col
        bra     @ok
@dc:    lda     aj_at
        cmp     aj_c1
        bne     :+
        cmp     rf_col
        jeq     @gone
:       lda     aj_at
        cmp     aj_c1
        bcs     :+
        dec     aj_c1
        dec     rf_col
        jmp     @ok
:       lda     rf_col
        cmp     aj_at
        jcc     @ok
        dec     rf_col
        jmp     @ok
; swap rf_* and aj_*1
aj_xchg:
        lda     rf_col
        ldx     aj_c1
        sta     aj_c1
        stx     rf_col
        lda     rf_row
        ldx     aj_r1
        sta     aj_r1
        stx     rf_row
        lda     rf_ac
        ldx     aj_ac1
        sta     aj_ac1
        stx     rf_ac
        lda     rf_ar
        ldx     aj_ar1
        sta     aj_ar1
        stx     rf_ar
        rts

; ---------------------------------------------------------------- the evaluator
; The code at ep (ev_len bytes) -> ev_tag V_NUM with na, or V_ERR with ev_err
fx_eval:
        stz     vsp
        stz     ev_pc
@l:     ldy     ev_pc
        cpy     ev_len
        bcs     @done
        lda     [ep],y
        iny
        sty     ev_pc
        and     #$00FF
        cmp     #OP_FN + 1
        bcc     :+
        lda     #0
:       asl     a
        tax
        jsr     (optab,x)
        bra     @l
@done:  lda     vsp                     ; the last value
        beq     @bad
        sec
        sbc     #10
        tax
        jsr     scal
        lda     vstk,x
        sta     ev_tag
        beq     :+
        lda     vstk+2,x
        sta     ev_err
        rts
:       jmp     ld_a
@bad:   lda     #V_ERR
        sta     ev_tag
        lda     #E_VALUE
        sta     ev_err
        rts

; slot X -> na / nb
ld_a:   lda     vstk+2,x
        sta     z:na
        lda     vstk+4,x
        sta     z:na+2
        lda     vstk+6,x
        sta     z:na+4
        lda     vstk+8,x
        sta     z:na+6
        rts
ld_b:   lda     vstk+2,x
        sta     z:nb
        lda     vstk+4,x
        sta     z:nb+2
        lda     vstk+6,x
        sta     z:nb+4
        lda     vstk+8,x
        sta     z:nb+6
        rts
; slot X = the number na / the error A
st_num: lda     #V_NUM
        sta     vstk,x
        lda     z:na
        sta     vstk+2,x
        lda     z:na+2
        sta     vstk+4,x
        lda     z:na+4
        sta     vstk+6,x
        lda     z:na+6
        sta     vstk+8,x
        rts
st_err: sta     vstk+2,x
        lda     #V_ERR
        sta     vstk,x
        rts
; slot X made a scalar: empty -> 0, text and ranges -> #VALUE (keeps X)
scal:   lda     vstk,x
        cmp     #V_EMP
        bne     :+
        stz     vstk,x
        stz     vstk+2,x
        stz     vstk+4,x
        stz     vstk+6,x
        stz     vstk+8,x
        rts
:       cmp     #V_TXT
        beq     :+
        cmp     #V_RNG
        bne     :++
:       lda     #E_VALUE
        jmp     st_err
:       rts

; the operations: Y = ev_pc (after the opcode)
op_bad: lda     #E_VALUE                ; (an unknown code: an error value)
        sta     ev_t
        bra     op_push_err
op_num: ldx     vsp
        lda     #V_NUM
        sta     vstk,x
        lda     [ep],y
        sta     vstk+2,x
        iny
        iny
        lda     [ep],y
        sta     vstk+4,x
        iny
        iny
        lda     [ep],y
        sta     vstk+6,x
        iny
        iny
        lda     [ep],y
        sta     vstk+8,x
        iny
        iny
        sty     ev_pc
        bra     vpush
op_err: lda     [ep],y
        and     #$00FF
        sta     ev_t
        iny
        sty     ev_pc
op_push_err:
        ldx     vsp
        lda     ev_t
        jsr     st_err
vpush:  lda     vsp
        clc
        adc     #10
        sta     vsp
        rts
op_rng: ldx     vsp
        lda     #V_RNG
        sta     vstk,x
        lda     [ep],y
        sta     vstk+2,x
        iny
        iny
        lda     [ep],y
        sta     vstk+4,x
        iny
        iny
        sty     ev_pc
        bra     vpush
op_ref: lda     [ep],y
        iny
        iny
        sty     ev_pc
        ldx     vsp
        jsr     cellval
        bra     vpush

; slot X = the value of cell A
cellval:
        jsr     cell_get
        bcc     :+
        lda     #V_EMP
        sta     vstk,x
        rts
:       ldy     #R_TYPE
        lda     [gp],y
        and     #$00FF
        cmp     #T_TEXT
        bne     :+
        lda     #V_TXT
        sta     vstk,x
        rts
:       cmp     #T_FORM
        bne     @num
        lda     [gp],y                  ; a formula: its result
        xba
        and     #$00FF
        beq     @num
        ldy     #R_VAL
        lda     [gp],y
        and     #$00FF
        jmp     st_err
@num:   stz     vstk,x
        ldy     #R_VAL
        lda     [gp],y
        sta     vstk+2,x
        iny
        iny
        lda     [gp],y
        sta     vstk+4,x
        iny
        iny
        lda     [gp],y
        sta     vstk+6,x
        iny
        iny
        lda     [gp],y
        sta     vstk+8,x
        rts

; unary minus
op_neg: lda     vsp
        sec
        sbc     #10
        tax
        jsr     scal
        lda     vstk,x
        bne     :+
        jsr     ld_a
        jsr     n_nega
        jsr     st_num
:       rts

; binary operators: the two slots on top -> one
op_bin: dey                             ; the opcode
        lda     [ep],y
        and     #$00FF
        sta     ev_op
        lda     vsp
        sec
        sbc     #10
        sta     vsp
        tax
        jsr     scal                    ; b
        txa
        sec
        sbc     #10
        tax
        jsr     scal                    ; a
        lda     vstk,x
        bne     @out                    ; a is an error: the result
        lda     vstk+10,x
        beq     :+
        lda     vstk+12,x               ; b is an error
        jmp     st_err
:       jsr     ld_a
        phx
        txa
        clc
        adc     #10
        tax
        jsr     ld_b
        plx
        phx
        lda     ev_op
        sec
        sbc     #OP_ADD
        asl     a
        tax
        jsr     (bintab,x)
        plx
        bcc     :+
        jmp     st_err
:       jmp     st_num
@out:   rts

b_cmp:  jsr     n_cmp                   ; A = -1 / 0 / 1 -> a truth by the operator
        tax
        lda     ev_op
        cmp     #OP_EQ
        bne     :+
        cpx     #0
        beq     @t
        bra     @f
:       cmp     #OP_NE
        bne     :+
        cpx     #0
        bne     @t
        bra     @f
:       cmp     #OP_LT
        bne     :+
        cpx     #$FFFF
        beq     @t
        bra     @f
:       cmp     #OP_GT
        bne     :+
        cpx     #1
        beq     @t
        bra     @f
:       cmp     #OP_LE
        bne     :+
        cpx     #1
        bne     @t
        bra     @f
:       cpx     #$FFFF                  ; GE
        bne     @t
@f:     jsr     n_zero
        clc
        rts
@t:     lda     #1
        jsr     n_seti
        clc
        rts

; ---------------------------------------------------------------- functions
op_fn:  lda     [ep],y                  ; id, argc
        iny
        iny
        sty     ev_pc
        pha
        and     #$00FF
        sta     fn_id
        pla
        xba
        and     #$00FF
        sta     fn_argc
        asl     a                       ; base = vsp - 10 argc
        asl     a
        adc     fn_argc
        asl     a
        sta     fx_t
        lda     vsp
        sec
        sbc     fx_t
        sta     fn_base
        clc                             ; the result goes to the base slot
        adc     #10
        sta     vsp
        lda     fn_id
        asl     a
        tax
        jmp     (fntab,x)

; SUM AVERAGE MIN MAX COUNT AND OR: every argument, ranges cell by cell
fn_agg: stz     ag_n
        stz     ag_err
        stz     ag_acc
        stz     ag_acc+2
        stz     ag_acc+4
        stz     ag_acc+6
        lda     #1
        sta     ag_bool
        lda     fn_id
        cmp     #F_OR
        bne     :+
        stz     ag_bool
:       stz     ag_i
@arg:   lda     ag_i
        cmp     fn_argc
        jcs     @fin
        asl     a
        asl     a
        adc     ag_i
        asl     a
        adc     fn_base
        tax
        lda     vstk,x
        cmp     #V_NUM
        bne     :+
        jsr     ld_a
        jsr     ag_val
        jmp     @next
:       cmp     #V_ERR
        bne     :+
        lda     vstk+2,x
        jsr     ag_e
        jmp     @next
:       cmp     #V_RNG
        jne     @next
        lda     vstk+2,x                ; the range: columns c .. ag_c2, rows ag_r1 .. ag_r2
        pha
        and     #CPC - 1
        sta     ag_r1
        pla
        sta     ag_ci
        lda     vstk+4,x
        pha
        and     #CPC - 1
        sta     ag_r2
        pla
        and     #$FFFF ^ (CPC - 1)
        sta     ag_c2
@cell:  lda     ag_ci
        jsr     cell_get
        bcs     @cn
        ldy     #R_TYPE
        lda     [gp],y
        and     #$00FF
        cmp     #T_TEXT
        beq     @cn
        cmp     #T_FORM
        bne     @cv
        lda     [gp],y
        xba
        and     #$00FF
        beq     @cv
        ldy     #R_VAL
        lda     [gp],y
        and     #$00FF
        jsr     ag_e
        bra     @cn
@cv:    ldy     #R_VAL
        lda     [gp],y
        sta     z:na
        iny
        iny
        lda     [gp],y
        sta     z:na+2
        iny
        iny
        lda     [gp],y
        sta     z:na+4
        iny
        iny
        lda     [gp],y
        sta     z:na+6
        jsr     ag_val
@cn:    lda     ag_ci                   ; the next cell: down, then the next column
        and     #CPC - 1
        cmp     ag_r2
        bcs     :+
        inc     ag_ci
        bra     @cell
:       lda     ag_ci
        and     #$FFFF ^ (CPC - 1)
        cmp     ag_c2
        bcs     @next
        clc
        adc     #CPC
        ora     ag_r1
        sta     ag_ci
        bra     @cell
@next:  inc     ag_i
        jmp     @arg
@fin:   ldx     fn_base
        lda     fn_id
        cmp     #F_COUNT
        bne     :+
        lda     ag_n
        jsr     n_seti
        jmp     st_num
:       lda     ag_err
        beq     :+
        jmp     st_err
:       lda     fn_id
        cmp     #F_AVG
        bne     @mm
        lda     ag_n
        bne     :+
        lda     #E_DIV0
        jmp     st_err
:       jsr     n_seti
        jsr     n_a2b
        jsr     ag_ld
        jsr     n_div
        ldx     fn_base
        bcc     :+
        jmp     st_err
:       jmp     st_num
@mm:    cmp     #F_AND
        bcc     @val
        lda     ag_n
        bne     :+
        lda     #E_VALUE
        jmp     st_err
:       lda     ag_bool
        jsr     n_seti
        jmp     st_num
@val:   jsr     ag_ld                   ; SUM, MIN, MAX (0 without values)
        jmp     st_num

ag_ld:  lda     ag_acc
        sta     z:na
        lda     ag_acc+2
        sta     z:na+2
        lda     ag_acc+4
        sta     z:na+4
        lda     ag_acc+6
        sta     z:na+6
        rts
; an error A met (the first one counts)
ag_e:   ldx     ag_err
        bne     :+
        sta     ag_err
:       rts
; a value na met (keeps nothing but ag_*)
ag_val: lda     fn_id
        asl     a
        tax
        inc     ag_n
        jmp     (agtab,x)
ag_sum: lda     ag_acc                  ; (nb = acc)
        sta     z:nb
        lda     ag_acc+2
        sta     z:nb+2
        lda     ag_acc+4
        sta     z:nb+4
        lda     ag_acc+6
        sta     z:nb+6
        jsr     n_add
        bcc     ag_st
        jmp     ag_e
ag_st:  lda     z:na
        sta     ag_acc
        lda     z:na+2
        sta     ag_acc+2
        lda     z:na+4
        sta     ag_acc+4
        lda     z:na+6
        sta     ag_acc+6
ag_none:
        rts
ag_min: lda     ag_n
        cmp     #1
        beq     ag_st
        jsr     ag_accb
        jsr     n_cmp
        cmp     #$FFFF
        beq     ag_st
        rts
ag_max: lda     ag_n
        cmp     #1
        beq     ag_st
        jsr     ag_accb
        jsr     n_cmp
        cmp     #1
        beq     ag_st
        rts
ag_and: jsr     n_isz
        bne     :+
        stz     ag_bool
:       rts
ag_or:  jsr     n_isz
        beq     :+
        lda     #1
        sta     ag_bool
:       rts
ag_accb:
        lda     ag_acc
        sta     z:nb
        lda     ag_acc+2
        sta     z:nb+2
        lda     ag_acc+4
        sta     z:nb+4
        lda     ag_acc+6
        sta     z:nb+6
        rts

; the first argument as a scalar in na -> C set: it is an error (already the result)
fn_a1:  ldx     fn_base
        jsr     scal
        lda     vstk,x
        bne     :+
        jsr     ld_a
        clc
        rts
:       sec
        rts
; the second as nb (X = the base) -> C set: an error (made the result)
fn_a2:  ldx     fn_base
        txa
        clc
        adc     #10
        tax
        jsr     scal
        lda     vstk,x
        bne     :+
        jsr     ld_b
        ldx     fn_base
        clc
        rts
:       lda     vstk+2,x
        ldx     fn_base
        jsr     st_err
        sec
        rts
; the result: C set -> error A, else na
fn_res: ldx     fn_base
        bcc     :+
        jmp     st_err
:       jmp     st_num

fn_abs: jsr     fn_a1
        bcs     :+
        lda     z:na+6
        bpl     :+
        jsr     n_nega
        clc
        jsr     fn_res
:       rts
fn_int: jsr     fn_a1
        bcs     :+
        jsr     n_int
        jsr     fn_res
:       rts
fn_sqrt:
        jsr     fn_a1
        bcs     :+
        jsr     n_sqrt
        jsr     fn_res
:       rts
fn_not: jsr     fn_a1
        bcs     :+
        jsr     n_isz
        php
        jsr     n_zero
        plp
        bne     @z
        lda     #1
        jsr     n_seti
@z:     clc
        jsr     fn_res
:       rts
fn_round:
        jsr     fn_a1
        bcs     :+
        jsr     fn_a2
        bcs     :+
        jsr     n_toint                 ; the digits: nb's whole part
        jsr     n_round
        jsr     fn_res
:       rts
fn_mod: jsr     fn_a1
        bcs     :+
        jsr     fn_a2
        bcs     :+
        jsr     n_mod
        jsr     fn_res
:       rts
fn_if:  ldx     fn_base                 ; the condition
        jsr     scal
        lda     vstk,x
        bne     @out                    ; an error: that
        jsr     ld_a
        jsr     n_isz
        bne     @then
        lda     fn_argc                 ; false: the third, or 0
        cmp     #3
        bcs     :+
        jsr     n_zero
        ldx     fn_base
        jmp     st_num
:       lda     #20
        bra     @take
@then:  lda     #10
@take:  clc                             ; that slot into the base, as a scalar
        adc     fn_base
        tax
        jsr     scal
        ldy     fn_base
        lda     vstk,x
        sta     vstk,y
        lda     vstk+2,x
        sta     vstk+2,y
        lda     vstk+4,x
        sta     vstk+4,y
        lda     vstk+6,x
        sta     vstk+6,y
        lda     vstk+8,x
        sta     vstk+8,y
@out:   rts

; PMT(rate, periods, amount): the payment per period (sht_num.s, n_pmt)
fn_pmt: jsr     fn_a1                   ; the rate
        bcs     @out
        ldx     #6
:       lda     z:na,x
        sta     pm_r,x
        dex
        dex
        bpl     :-
        jsr     fn_a2                   ; the periods: a whole number 1 .. 30000
        bcs     @out
        jsr     n_toint
        cmp     #1
        bmi     @bad
        sta     n_pn
        lda     fn_base                 ; the amount
        clc
        adc     #20
        tax
        jsr     scal
        lda     vstk,x
        beq     :+
        lda     vstk+2,x
        ldx     fn_base
        jmp     st_err
:       jsr     ld_b
        jsr     n_pmt
        jmp     fn_res
@bad:   ldx     fn_base
        lda     #E_VALUE
        jmp     st_err
@out:   rts

; nb (a number) -> A = its whole part, signed, clamped to -30000 .. 30000
n_toint:
        lda     z:na                    ; (na kept)
        pha
        lda     z:na+2
        pha
        lda     z:na+4
        pha
        lda     z:na+6
        pha
        jsr     n_b2a
        stz     z:nsg
        lda     z:na+6
        bpl     :+
        jsr     n_nega
        inc     z:nsg
:       jsr     n_a2r
        lda     #10000
        jsr     div16
        lda     z:nr+2
        ora     z:nr+4
        ora     z:nr+6
        bne     @big
        lda     z:nr
        cmp     #30000
        bcc     :+
@big:   lda     #30000
:       ldx     z:nsg
        beq     :+
        eor     #$FFFF
        inc     a
:       sta     fx_t
        pla
        sta     z:na+6
        pla
        sta     z:na+4
        pla
        sta     z:na+2
        pla
        sta     z:na
        lda     fx_t
        rts

        .segment "RODATA"
optab:  .addr   op_bad, op_num, op_ref, op_rng, op_err, op_bin, op_bin, op_bin, op_bin, op_bin
        .addr   op_neg, op_bin, op_bin, op_bin, op_bin, op_bin, op_bin, op_fn
; the length of each operation in the code (the scanner of the recalculation)
oplen:  .byte   1, 9, 3, 5, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3
bintab: .addr   n_add, n_sub, n_mul, n_div, n_pow, n_neg, b_cmp, b_cmp, b_cmp, b_cmp, b_cmp, b_cmp
fntab:  .addr   fn_agg, fn_agg, fn_agg, fn_agg, fn_agg, fn_agg, fn_agg
        .addr   fn_abs, fn_int, fn_sqrt, fn_not, fn_round, fn_mod, fn_if, fn_pmt
agtab:  .addr   ag_sum, ag_sum, ag_min, ag_max, ag_none, ag_and, ag_or
; functions: {name length, name, id, least arguments, most}
fntable:   .byte   3, "SUM", F_SUM, 1, 30
        .byte   7, "AVERAGE", F_AVG, 1, 30
        .byte   3, "MIN", F_MIN, 1, 30
        .byte   3, "MAX", F_MAX, 1, 30
        .byte   5, "COUNT", F_COUNT, 1, 30
        .byte   3, "AND", F_AND, 1, 30
        .byte   2, "OR", F_OR, 1, 30
        .byte   3, "ABS", F_ABS, 1, 1
        .byte   3, "INT", F_INT, 1, 1
        .byte   4, "SQRT", F_SQRT, 1, 1
        .byte   3, "NOT", F_NOT, 1, 1
        .byte   5, "ROUND", F_ROUND, 2, 2
        .byte   3, "MOD", F_MOD, 2, 2
        .byte   2, "IF", F_IF, 2, 3
        .byte   3, "PMT", F_PMT, 3, 3
        .byte   0
; errors: {length, name, code}; their names for display: errnames
errtab:   .byte   5, "DIV/0", E_DIV0
        .byte   3, "REF", E_REF
        .byte   5, "VALUE", E_VALUE
        .byte   5, "CYCLE", E_CYCLE
        .byte   4, "OVER", E_OVER
        .byte   0
s_ref:  .byte   "#REF", 0
errnames:
        .addr   s_e0, s_e1, s_ref, s_e3, s_e4, s_e5
s_e0:   .byte   "#ERR", 0
s_e1:   .byte   "#DIV/0", 0
s_e3:   .byte   "#VALUE", 0
s_e4:   .byte   "#CYCLE", 0
s_e5:   .byte   "#OVER", 0

        .segment "BSS"
fx_sp:  .res    2
fx_dep: .res    2
fx_sd:  .res    2
fx_smax: .res   2
fx_c1:  .res    2
fx_col: .res    2
fx_row: .res    2
fx_name: .res   10
fx_nl:  .res    2
fx_t:   .res    2
fx_e:   .res    2
rf_y0:  .res    2
rf_col: .res    2
rf_row: .res    2
rf_ac:  .res    2
rf_ar:  .res    2
rf_t:   .res    2
aj_mode: .res   2
aj_dc:  .res    2
aj_dr:  .res    2
aj_at:  .res    2
aj_ox:  .res    2
aj_c1:  .res    2
aj_r1:  .res    2
aj_ac1: .res    2
aj_ar1: .res    2
aj_t:   .res    2
aj_t2:  .res    2
vsp:    .res    2
vstk:   .res    MAXV * 10 + 20
ev_pc:  .res    2
ev_len: .res    2
ev_tag: .res    2
ev_err: .res    2
ev_op:  .res    2
ev_t:   .res    2
fn_id:  .res    2
fn_argc: .res   2
fn_base: .res   2
ag_n:   .res    2
ag_err: .res    2
ag_acc: .res    8
ag_bool: .res   2
ag_i:   .res    2
ag_ci:  .res    2
ag_r1:  .res    2
ag_r2:  .res    2
ag_c2:  .res    2
tbuf:   .res    TXTMAX + 8              ; a cell's text (zero-terminated)
obuf:   .res    TXTMAX + 8
cbuf:   .res    CMAX + 16               ; a formula's code

        .segment "ZEROPAGE"
ep:     .res    4                       ; the code being evaluated
sp:     .res    4                       ; n_parse's string

        .segment "CODE"
