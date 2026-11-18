; sht_edit.s - Sheet: operations on ranges (part of sheet.s): copy, paste, fill, clear,
; insert and delete rows and columns, with the references in formulas adjusted.
;
; The range is s_c0 .. s_c1 (columns), s_r0 .. s_r1 (rows), ordered.
; The program's own clipboard: a bank (CBK) holding {u16 width, height, the source's
; column, row}, then the cells row by row as {u16 length, the text as typed}. Paste puts
; them back with the relative references moved by the distance from the source.

        .segment "CODE"

; the range -> the clipboard. C set: too large (64 KB of text)
cp_copy:
        lda     s_c1
        sec
        sbc     s_c0
        inc     a
        sta     [cbk]
        ldy     #2
        lda     s_r1
        sec
        sbc     s_r0
        inc     a
        sta     [cbk],y
        ldy     #4
        lda     s_c0
        sta     [cbk],y
        ldy     #6
        lda     s_r0
        sta     [cbk],y
        lda     #8
        sta     cp_off
        stz     cp_have
        lda     s_r0
        sta     cp_r
@row:   lda     s_c0
        sta     cp_c
@cell:  jsr     cp_ci
        jsr     cell_src
        sta     cp_n
        clc
        adc     cp_off
        bcs     @big
        cmp     #$FF00
        bcs     @big
        ldy     cp_off
        lda     cp_n
        sta     [cbk],y
        iny
        iny
        ldx     #0
        sep     #$20
        .a8
:       cpx     cp_n
        bcs     :+
        lda     tbuf,x
        sta     [cbk],y
        inx
        iny
        bra     :-
:       rep     #$20
        .a16
        sty     cp_off
        inc     cp_c
        lda     cp_c
        cmp     s_c1
        bcc     @cell
        beq     @cell
        inc     cp_r
        lda     cp_r
        cmp     s_r1
        bcc     @row
        beq     @row
        lda     #1
        sta     cp_have
        clc
        rts
@big:   sec
        rts

; cp_c, cp_r -> A = the cell index
cp_ci:  lda     cp_c
        xba
        asl     a
        asl     a
        ora     cp_r
        rts

; the clipboard into the sheet at s_c0, s_r0 (a single cell copied fills the whole range)
; -> C set: out of memory
cp_paste:
        lda     cp_have
        bne     :+
        clc
        rts
:       lda     #1
        sta     dirty
        lda     [cbk]                   ; one cell: every cell of the range
        cmp     #1
        bne     @block
        ldy     #2
        lda     [cbk],y
        cmp     #1
        bne     @block
        lda     s_r0
        sta     cp_r
@frow:  lda     s_c0
        sta     cp_c
@fcell: lda     #8
        sta     cp_off
        jsr     cp_one
        bcs     @mem
        inc     cp_c
        lda     cp_c
        cmp     s_c1
        bcc     @fcell
        beq     @fcell
        inc     cp_r
        lda     cp_r
        cmp     s_r1
        bcc     @frow
        beq     @frow
        clc
        rts
@block: lda     #8                      ; the block at s_c0, s_r0
        sta     cp_off
        stz     cp_j
@brow:  stz     cp_i
@bcell: lda     s_c0
        clc
        adc     cp_i
        sta     cp_c
        lda     s_r0
        clc
        adc     cp_j
        sta     cp_r
        lda     cp_c                    ; off the sheet: skipped
        cmp     #NCOL
        bcs     @skip
        lda     cp_r
        cmp     #NROW
        bcs     @skip
        jsr     cp_one
        bcs     @mem
        bra     @nx
@skip:  ldy     cp_off
        lda     [cbk],y
        clc
        adc     #2
        adc     cp_off
        sta     cp_off
@nx:    inc     cp_i
        lda     cp_i
        cmp     [cbk]
        bcc     @bcell
        inc     cp_j
        ldy     #2
        lda     cp_j
        cmp     [cbk],y
        bcc     @brow
        clc
        rts
@mem:   sec
        rts

; the clipboard's cell at cp_off -> cell cp_c, cp_r (references moved from where it was
; copied); cp_off past it. C set: out of memory
cp_one: ldy     cp_off
        lda     [cbk],y
        sta     cp_n
        iny
        iny
        ldx     #0
        sep     #$20
        .a8
:       cpx     cp_n
        bcs     :+
        lda     [cbk],y
        sta     tbuf,x
        inx
        iny
        bra     :-
:       lda     #0
        sta     tbuf,x
        rep     #$20
        .a16
        sty     cp_off
        stx     c_tlen
        lda     cp_c                    ; dc = target - source column of the block origin
        sec                             ;  (a single cell: the same, as the origin moves)
        ldy     #4
        sbc     [cbk],y
        sta     cp_dc
        lda     cp_r
        sec
        ldy     #6
        sbc     [cbk],y
        sta     cp_dr
        lda     [cbk]                   ; in a block the origin is the block's: minus i, j
        cmp     #1
        bne     :+
        ldy     #2
        lda     [cbk],y
        cmp     #1
        beq     :++
:       lda     cp_dc
        sec
        sbc     cp_i
        sta     cp_dc
        lda     cp_dr
        sec
        sbc     cp_j
        sta     cp_dr
:       jsr     cp_ci
        sta     c_ci
        lda     cp_dc
        sta     aj_dc
        lda     cp_dr
        sta     aj_dr
        lda     #AJ_COPY
        sta     aj_mode
; tbuf (c_tlen) into cell c_ci, a formula adjusted by aj_* first -> C set: out of memory
ent_adj:
        lda     tbuf
        and     #$00FF
        cmp     #'='
        bne     :+
        jsr     fx_adj
:       lda     #1
        sta     ce_force
        jsr     cell_enter
        stz     ce_force
        bcc     :+
        cmp     #CE_MEM
        beq     :++
:       clc
        rts
:       sec
        rts

; the range emptied
rng_clear:
        lda     #1
        sta     dirty
        lda     s_r0
        sta     cp_r
@row:   lda     s_c0
        sta     cp_c
@cell:  jsr     cp_ci
        jsr     cell_clear
        inc     cp_c
        lda     cp_c
        cmp     s_c1
        bcc     @cell
        beq     @cell
        inc     cp_r
        lda     cp_r
        cmp     s_r1
        bcc     @row
        beq     @row
        rts

; fill down: the range's top row copied into the rows below it (fill right: the left
; column into the columns right of it) -> C set: out of memory
fill_down:
        lda     #1
        sta     dirty
        lda     s_c0
        sta     fl_c
@col:   lda     s_r0                    ; the source: (fl_c, s_r0)
        sta     fl_r
        jsr     fl_src
        lda     s_r0
        inc     a
        sta     cp_r
@cell:  lda     cp_r
        cmp     s_r1
        beq     :+
        bcs     @ncol
:       lda     fl_c
        sta     cp_c
        stz     aj_dc
        lda     cp_r
        sec
        sbc     s_r0
        sta     aj_dr
        jsr     fl_put
        bcs     @mem
        inc     cp_r
        bra     @cell
@ncol:  inc     fl_c
        lda     fl_c
        cmp     s_c1
        bcc     @col
        beq     @col
        clc
        rts
@mem:   sec
        rts
fill_right:
        lda     #1
        sta     dirty
        lda     s_r0
        sta     fl_r
@row:   lda     s_c0
        sta     fl_c
        jsr     fl_src
        lda     s_c0
        inc     a
        sta     cp_c
@cell:  lda     cp_c
        cmp     s_c1
        beq     :+
        bcs     @nrow
:       lda     fl_r
        sta     cp_r
        stz     aj_dr
        lda     cp_c
        sec
        sbc     s_c0
        sta     aj_dc
        jsr     fl_put
        bcs     @mem
        inc     cp_c
        bra     @cell
@nrow:  inc     fl_r
        lda     fl_r
        cmp     s_r1
        bcc     @row
        beq     @row
        clc
        rts
@mem:   sec
        rts
; the source cell (fl_c, fl_r) as typed -> obuf2
fl_src: lda     fl_c
        xba
        asl     a
        asl     a
        ora     fl_r
        jsr     cell_src
        ldx     #.loword(tbuf)
        ldy     #.loword(fl_buf)
        jmp     ui_strcpy
; the source into (cp_c, cp_r), moved by aj_dc, aj_dr
fl_put: ldx     #.loword(fl_buf)
        ldy     #.loword(tbuf)
        jsr     ui_strcpy
        sta     c_tlen
        jsr     cp_ci
        sta     c_ci
        lda     #AJ_COPY
        sta     aj_mode
        jmp     ent_adj

; insert / delete row A, column A: the cells move, then every formula is adjusted
ed_insr:
        sta     aj_at
        jsr     row_ins
        lda     #AJ_INSR
        jmp     adj_all
ed_delr:
        sta     aj_at
        jsr     row_del
        lda     #AJ_DELR
        bra     adj_all
ed_insc:
        sta     aj_at
        jsr     col_ins
        ldx     #(NCOL - 1) * 2         ; widths and formats move with the columns
:       txa
        lsr     a
        cmp     aj_at
        beq     :+
        lda     colw-2,x
        sta     colw,x
        phx
        txa
        lsr     a
        tax
        lda     colfmt-1,x
        sep     #$20
        .a8
        sta     colfmt,x
        rep     #$20
        .a16
        plx
        dex
        dex
        bra     :-
:       lda     #DEFW
        sta     colw,x
        txa
        lsr     a
        tax
        sep     #$20
        .a8
        stz     colfmt,x
        rep     #$20
        .a16
        lda     #AJ_INSC
        bra     adj_all
ed_delc:
        sta     aj_at
        jsr     col_del
        lda     aj_at
        asl     a
        tax
:       cpx     #(NCOL - 1) * 2
        bcs     :+
        lda     colw+2,x
        sta     colw,x
        phx
        txa
        lsr     a
        tax
        lda     colfmt+1,x
        sep     #$20
        .a8
        sta     colfmt,x
        rep     #$20
        .a16
        plx
        inx
        inx
        bra     :-
:       lda     #DEFW
        sta     colw,x
        sep     #$20
        .a8
        stz     colfmt + NCOL - 1
        rep     #$20
        .a16
        lda     #AJ_DELC
; every formula's references adjusted (aj_mode A, aj_at set)
adj_all:
        sta     aj_mode
        lda     #1
        sta     dirty
        sta     fullcalc
        stz     aa_ci
@l:     lda     aa_ci
        and     #CPC - 1
        cmp     maxrow
        bcs     @col
        lda     aa_ci
        jsr     cell_get
        bcs     @n
        ldy     #R_TYPE
        lda     [gp],y
        and     #$00FF
        cmp     #T_FORM
        bne     @n
        lda     aa_ci
        jsr     cell_src
        sta     c_tlen
        lda     aa_ci
        sta     c_ci
        jsr     ent_adj
@n:     inc     aa_ci
        bra     @l
@col:   lda     aa_ci
        and     #$FFFF ^ (CPC - 1)
        clc
        adc     #CPC
        sta     aa_ci
        cmp     #NCOL * CPC
        bcc     @l
        rts

        .segment "BSS"
s_c0:   .res    2                       ; the range (ordered)
s_r0:   .res    2
s_c1:   .res    2
s_r1:   .res    2
cp_have: .res   2
cp_off: .res    2
cp_c:   .res    2
cp_r:   .res    2
cp_n:   .res    2
cp_i:   .res    2
cp_j:   .res    2
cp_dc:  .res    2
cp_dr:  .res    2
fl_c:   .res    2
fl_r:   .res    2
fl_buf: .res    TXTMAX + 8
aa_ci:  .res    2

        .segment "ZEROPAGE"
cbk:    .res    4                       ; the clipboard bank

        .segment "CODE"
