; sht_calc.s - Sheet: recalculation (part of sheet.s).
;
; After every change the whole sheet is recalculated, each formula once, in dependency
; order: a depth-first walk with an explicit stack (a bank of its own, 6-byte entries
; {ci, the code position reached, the range cell reached}). A formula whose references
; include a formula not yet computed in this pass (its epoch is old) pushes that one first
; and resumes where it stopped. A reference to a formula that is still on the stack is a
; cycle: the cell that found it gets #CYCLE, and the error flows on to the cells using it.
; Chains longer than WSMAX formulas are treated as cycles too.
; A formula is evaluated only if something it uses changed in this pass (or was typed
; since the last one, or it is new); after a cell was emptied or rows / columns moved
; (fullcalc) every formula is. Cells whose value changed are passed to mark_dirty (the
; window redraws those rows).
WSMAX   = 65400 / 6 * 6

        .segment "CODE"

; the whole sheet
recalc: inc     epoch
        bne     :+
        jsr     ep_reset
:       stz     rc_ci
@c:     lda     rc_ci                   ; an empty column: skipped
        xba
        lsr     a
        and     #$003F * 2
        tax
        lda     colcnt,x
        beq     @col
@l:     lda     rc_ci
        and     #CPC - 1
        cmp     maxrow
        bcs     @col
        lda     rc_ci
        tay
        lda     [ixb],y
        and     #$00FF
        beq     @n
        tya
        jsr     cell_get
        ldy     #R_TYPE
        lda     [gp],y
        and     #$00FF
        cmp     #T_FORM
        bne     @n
        ldy     #R_EPO
        lda     [gp],y
        cmp     epoch
        beq     @n
        lda     rc_ci
        jsr     calc
@n:     inc     rc_ci
        bra     @l
@col:   lda     rc_ci                   ; the next column
        and     #$FFFF ^ (CPC - 1)
        clc
        adc     #CPC
        sta     rc_ci
        cmp     #NCOL * CPC
        bcc     @c
        stz     fullcalc
        rts

; the epoch wrapped: every stamp 0, epoch 1
ep_reset:
        lda     #1
        sta     epoch
        sta     fullcalc
        stz     rc_ci
@l:     lda     rc_ci
        jsr     cell_get
        bcs     :+
        ldy     #R_EPO
        lda     #0
        sta     [gp],y
        ldy     #R_CHG
        sta     [gp],y
:       inc     rc_ci
        lda     rc_ci
        cmp     #NCOL * CPC
        bcc     @l
        rts

; formula A and, first, everything it needs
calc:   stz     wtop
        jsr     cpush
@top:   lda     wtop
        bne     :+
        rts
:       sec                             ; the entry on top: e_ci, e_pos, e_rc
        sbc     #6
        sta     we
        tay
        lda     [ws],y
        sta     e_ci
        iny
        iny
        lda     [ws],y
        sta     e_pos
        iny
        iny
        lda     [ws],y
        sta     e_rc
        lda     e_ci
        jsr     cell_get
        lda     z:gp
        sta     z:rp
        lda     z:gp+2
        sta     z:rp+2
        ldy     #R_TLEN                 ; its code: at cb, cl bytes
        lda     [rp],y
        clc
        adc     #R_TEXT
        sta     cb
        ldy     #R_CLEN
        lda     [rp],y
        sta     cl
@scan:  lda     e_pos
        cmp     cl
        jcs     @eval
        clc
        adc     cb
        tay
        lda     [rp],y
        and     #$00FF
        cmp     #OP_REF
        beq     @ref
        cmp     #OP_RNG
        beq     @rng
        cmp     #OP_FN + 1
        bcc     :+
        lda     #0
:       tax
        lda     oplen,x
        and     #$00FF
        clc
        adc     e_pos
        sta     e_pos
        bra     @scan
@ref:   iny
        lda     [rp],y
        jsr     dep
        bcs     @push
        lda     e_pos
        clc
        adc     #3
        sta     e_pos
        bra     @scan
@rng:   iny
        lda     [rp],y
        sta     r_c1
        and     #CPC - 1
        sta     r_r1
        iny
        iny
        lda     [rp],y
        pha
        and     #CPC - 1
        sta     r_r2
        pla
        and     #$FFFF ^ (CPC - 1)
        sta     r_c2
        lda     e_rc
        cmp     #$FFFF
        bne     @rl
        lda     r_c1
@rl:    sta     e_rc
        jsr     dep
        bcs     @push
        lda     e_rc                    ; the next cell of the range
        and     #CPC - 1
        cmp     r_r2
        bcs     :+
        lda     e_rc
        inc     a
        bra     @rl
:       lda     e_rc
        and     #$FFFF ^ (CPC - 1)
        cmp     r_c2
        bcs     :+
        clc
        adc     #CPC
        ora     r_r1
        bra     @rl
:       lda     #$FFFF                  ; the range is done
        sta     e_rc
        lda     e_pos
        clc
        adc     #5
        sta     e_pos
        jmp     @scan
@push:  pha                             ; the dependency A first: E's place saved
        ldy     we
        iny
        iny
        lda     e_pos
        sta     [ws],y
        iny
        iny
        lda     e_rc
        sta     [ws],y
        pla
        jsr     cpush
        jmp     @top
@eval:  lda     fullcalc                ; everything it needs is there: evaluate, if
        bne     @ev                     ; anything changed
        ldy     #R_CHG
        lda     [rp],y
        cmp     epoch
        beq     @ev
        ldy     #R_FL
        lda     [rp],y
        and     #RF_DEP | RF_CYCLE
        bne     @ev
        jmp     @done
@ev:    lda     z:rp
        clc
        adc     cb
        sta     z:ep
        lda     z:rp+2
        sta     z:ep+2
        lda     cl
        sta     ev_len
        jsr     fx_eval
        ldy     #R_FL
        lda     [rp],y
        and     #RF_CYCLE
        beq     :+
        lda     #V_ERR
        sta     ev_tag
        lda     #E_CYCLE
        sta     ev_err
:       lda     ev_tag                  ; the error code as the value
        beq     :+
        lda     ev_err
        sta     z:na
        stz     z:na+2
        stz     z:na+4
        stz     z:na+6
:       ldy     #R_TYPE                 ; changed? (the result type, the 8 bytes)
        lda     [rp],y
        xba
        and     #$00FF
        cmp     ev_tag
        bne     @chg
        ldy     #R_VAL
        lda     [rp],y
        cmp     z:na
        bne     @chg
        iny
        iny
        lda     [rp],y
        cmp     z:na+2
        bne     @chg
        iny
        iny
        lda     [rp],y
        cmp     z:na+4
        bne     @chg
        iny
        iny
        lda     [rp],y
        cmp     z:na+6
        beq     @st
@chg:   ldy     #R_CHG
        lda     epoch
        sta     [rp],y
        lda     e_ci
        jsr     mark_dirty
@st:    ldy     #R_TYPE
        lda     ev_tag
        xba
        ora     #T_FORM
        sta     [rp],y
        ldy     #R_VAL
        lda     z:na
        sta     [rp],y
        iny
        iny
        lda     z:na+2
        sta     [rp],y
        iny
        iny
        lda     z:na+4
        sta     [rp],y
        iny
        iny
        lda     z:na+6
        sta     [rp],y
@done:  ldy     #R_EPO
        lda     epoch
        sta     [rp],y
        ldy     #R_FL
        lda     #0
        sta     [rp],y
        lda     we                      ; popped
        sta     wtop
        jmp     @top

; a reference to cell A from the entry on top (its record: rp) -> C set: A must be computed
; first (it is marked active); C clear: it is ready (or not a formula, or a cycle: marked).
; A cell that changed in this pass marks the entry RF_DEP.
dep:    sta     d_ci
        jsr     cell_get
        bcs     @no
        ldy     #R_TYPE
        lda     [gp],y
        and     #$00FF
        cmp     #T_FORM
        bne     @rdy
        ldy     #R_EPO
        lda     [gp],y
        cmp     epoch
        beq     @rdy
        ldy     #R_FL
        lda     [gp],y
        and     #RF_ACTIVE
        bne     @cyc
        lda     wtop
        cmp     #WSMAX - 6
        bcs     @cyc
        lda     d_ci
        sec
        rts
@rdy:   ldy     #R_CHG
        lda     [gp],y
        cmp     epoch
        bne     @no
        lda     #RF_DEP
        bra     @mark
@cyc:   lda     #RF_CYCLE
@mark:  ldy     #R_FL
        ora     [rp],y
        sta     [rp],y
@no:    clc
        rts

; push cell A (position 0, no range cell), marked active
cpush:  pha
        ldy     wtop
        sta     [ws],y
        iny
        iny
        lda     #0
        sta     [ws],y
        iny
        iny
        lda     #$FFFF
        sta     [ws],y
        iny
        iny
        sty     wtop
        pla
        jsr     cell_get
        ldy     #R_FL
        lda     [gp],y
        ora     #RF_ACTIVE
        sta     [gp],y
        rts

        .segment "BSS"
epoch:  .res    2
rc_ci:  .res    2
wtop:   .res    2
we:     .res    2
e_ci:   .res    2
e_pos:  .res    2
e_rc:   .res    2
cb:     .res    2
cl:     .res    2
r_c1:   .res    2
r_r1:   .res    2
r_c2:   .res    2
r_r2:   .res    2
d_ci:   .res    2

        .segment "ZEROPAGE"
ws:     .res    4                       ; the work stack (bank WSB)
rp:     .res    4                       ; the record of the formula on top

        .segment "CODE"
