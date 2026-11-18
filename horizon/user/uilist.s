; uilist.s - controls library: the list (rows from a callback, a vertical scroll bar).
; See ui.inc.
        .include "horizon.inc"
        .include "ui.inc"
        .import ui_px, ui_py, ui_rel, ui_setc, ui_ev

        .segment "CODE"
        .a16
        .i16

; the geometry of list ui_c; its scroll bar's fields set from it
ls_layout:
        ldx     z:ui_c
        lda     a:CT_X,x
        inc     a
        sta     lrx
        lda     a:CT_Y,x
        inc     a
        sta     lry
        lda     a:CT_W,x
        sec
        sbc     #2 + UI_SBW
        sta     lrw
        lda     a:CT_H,x
        sec
        sbc     #2
        ldy     #0                      ; rows that fit
:       cmp     #UI_ROWH
        bcc     :+
        sbc     #UI_ROWH
        iny
        bra     :-
:       tya
        bne     :+
        inc     a
:       sta     lvis
        lda     #UT_VSCROLL             ; the scroll bar (type, window)
        sep     #$20
        .a8
        sta     a:LS_SB+CT_TYPE,x
        lda     a:CT_WIN,x
        sta     a:LS_SB+CT_WIN,x
        rep     #$20
        .a16
        lda     lrx
        clc
        adc     lrw
        sta     a:LS_SB+CT_X,x
        lda     lry
        sta     a:LS_SB+CT_Y,x
        lda     #UI_SBW
        sta     a:LS_SB+CT_W,x
        lda     a:CT_H,x
        dec     a
        dec     a
        sta     a:LS_SB+CT_H,x
        lda     a:LS_COUNT,x            ; max top = count - visible
        sec
        sbc     lvis
        bcs     :+
        lda     #0
:       sta     lmax
        sta     a:LS_SB+SB_MAX,x
        lda     a:LS_TOP,x
        cmp     lmax
        bcc     :+
        lda     lmax
        sta     a:LS_TOP,x
:       sta     a:LS_SB+SB_POS,x
        lda     lvis
        sta     a:LS_SB+SB_PAGE,x
        lda     #1
        sta     a:LS_SB+SB_STEP,x
        rts

ui_ls_draw:
        jsr     ls_layout
        ldx     z:ui_c
        lda     a:CT_X,x
        sta     z:ui_x
        lda     a:CT_Y,x
        sta     z:ui_y
        lda     a:CT_W,x
        sta     z:ui_w
        lda     a:CT_H,x
        sta     z:ui_h
        lda     #1
        jsr     ui_bevel
        jsr     ls_rows
        ; fall through
; its scroll bar
ls_sbdraw:
        lda     z:ui_c
        pha
        clc
        adc     #LS_SB
        tax
        jsr     ui_draw
        pla
        sta     z:ui_c
        tax
        jmp     ui_setc

; all the rows (and the white below the last one)
ls_rows:
        stz     lslot
@s:     ldx     z:ui_c
        lda     a:LS_TOP,x
        clc
        adc     lslot
        jsr     ls_drow
        inc     lslot
        lda     lslot
        cmp     lvis
        bcc     @s
        jsr     ls_sloty                ; below: white down to the bevel
        sta     z:ui_y
        ldx     z:ui_c
        lda     a:CT_Y,x
        clc
        adc     a:CT_H,x
        dec     a
        sec
        sbc     z:ui_y
        beq     :+
        bmi     :+
        sta     z:ui_h
        lda     lrx
        sta     z:ui_x
        lda     lrw
        sta     z:ui_w
        lda     #WD_FILL | (C_WHITE << 8)
        jmp     ui_rect
:       rts

; the rows after LS_TOP changed from A (the page shown). By less than a page: the rows
; that stay move with one copy (WD_COPY), the new ones are drawn; else all the rows.
ls_scroll:
        sta     lotop
        ldx     z:ui_c
        lda     a:LS_TOP,x
        sec
        sbc     lotop
        beq     @out
        bmi     @down
        cmp     lvis
        bcs     @all
        sta     ldelta                  ; up: slots ldelta.. -> 0..
        sta     lslot
        jsr     ls_sloty
        sta     z:ui_y
        ldy     lry
        lda     lvis                    ; new: the last ldelta slots
        sec
        sbc     ldelta
        bra     @copy
@all:   jmp     ls_rows
@down:  eor     #$FFFF
        inc     a
        cmp     lvis
        bcs     @all
        sta     ldelta                  ; down: slots 0.. -> ldelta..
        sta     lslot
        jsr     ls_sloty
        tay
        lda     lry
        sta     z:ui_y
        lda     #0                      ; new: the first ldelta slots
@copy:  pha
        lda     lvis                    ; height: (lvis - ldelta) slots
        sec
        sbc     ldelta
        sta     lslot
        jsr     ls_sloty
        sec
        sbc     lry
        sta     z:ui_h
        lda     lrx
        sta     z:ui_x
        lda     lrw
        sta     z:ui_w
        ldx     lrx
        jsr     ui_copy
        pla
        sta     lslot
:       ldx     z:ui_c
        lda     a:LS_TOP,x
        clc
        adc     lslot
        jsr     ls_drow
        inc     lslot
        dec     ldelta
        bne     :-
@out:   rts

; A = y of slot lslot
ls_sloty:
        lda     lslot
        asl     a                       ; * 14 = * 16 - * 2
        sta     z:ui_t0
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:ui_t0
        clc
        adc     lry
        rts

; row A in slot lslot
ls_drow:
        sta     lrow
        jsr     ls_sloty
        sta     z:ui_y
        lda     lrx
        sta     z:ui_x
        lda     lrw
        sta     z:ui_w
        lda     #UI_ROWH
        sta     z:ui_h
        stz     lsel                    ; 1 selected, 2 selected and focused
        ldx     z:ui_c
        lda     lrow
        cmp     a:LS_COUNT,x
        bcs     @col
        cmp     a:LS_SEL,x
        bne     @col
        inc     lsel
        lda     a:CT_FLAGS,x
        and     #UF_FOCUS
        beq     @col
        inc     lsel
@col:   lda     #C_WHITE                ; the paper
        ldx     lsel
        beq     :+
        lda     #C_LIGHT
        cpx     #2
        bne     :+
        lda     #C_SELECT
:       sta     lbg
        ldx     z:ui_c
        lda     lrow
        cmp     a:LS_COUNT,x
        bcc     :+
        jmp     @fill                   ; no row: all paper
:       lda     a:LS_INDENT,x           ; (drawn without a blank moment:) the icon's place
        clc
        adc     #2
        sta     z:ui_w
        jsr     @fill
        ldx     z:ui_c
        lda     a:LS_ROW,x              ; the callback: icon, text
        sta     lcb
        lda     lsel
        beq     :+
        lda     #1
:       sta     z:ui_rsel
        lda     lrx
        inc     a
        inc     a
        sta     z:ui_x
        lda     z:ui_c
        pha
        lda     lrow
        ldx     #0
        jsr     (lcb,x)
        pla
        sta     z:ui_c
        ldy     #.loword(ui_tbuf)
        jsr     ui_strcpy
        ldx     z:ui_c
        lda     lrw
        sec
        sbc     #6
        sec
        sbc     a:LS_INDENT,x
        ldx     #.loword(ui_tbuf)
        jsr     ui_fit
        ldx     z:ui_c                  ; the text on its paper
        lda     lrx
        clc
        adc     #2
        adc     a:LS_INDENT,x
        sta     z:ui_x
        sta     ltx
        jsr     ls_sloty
        clc
        adc     #3
        sta     z:ui_y
        stz     z:ui_font
        lda     lbg
        xba
        ora     #C_BLACK
        ldx     lsel
        cpx     #2
        bne     :+
        ora     #C_WHITE
:       ldx     #.loword(ui_tbuf)
        jsr     ui_text
        lda     ltx                     ; the paper above it
        sta     z:ui_x
        jsr     ls_sloty
        sta     z:ui_y
        lda     #3
        sta     z:ui_h
        lda     lrx
        clc
        adc     lrw
        sec
        sbc     ltx
        sta     z:ui_w
        jsr     @fill
        ldx     #.loword(ui_tbuf)       ; and right of it
        lda     #0
        jsr     ui_twidth
        clc
        adc     ltx
        sta     z:ui_x
        lda     lrx
        clc
        adc     lrw
        sec
        sbc     z:ui_x
        sta     z:ui_w
        jsr     ls_sloty
        clc
        adc     #3
        sta     z:ui_y
        lda     #UI_ROWH - 3
        sta     z:ui_h
@fill:  lda     z:ui_w
        beq     :+
        bmi     :+
        lda     lbg
        xba
        ora     #WD_FILL
        jmp     ui_rect
:       rts

; row A redrawn if it is on the page
ls_one: ldx     z:ui_c
        sec
        sbc     a:LS_TOP,x
        bcc     :+
        cmp     lvis
        bcs     :+
        sta     lslot
        clc
        adc     a:LS_TOP,x
        jmp     ls_drow
:       rts

; scroll so that LS_SEL shows -> C set if LS_TOP changed
ui_ls_show:
        ldx     z:ui_c
        lda     a:LS_TOP,x
        sta     z:ui_t0
        lda     a:LS_SEL,x
        cmp     #$FFFF
        beq     @cmp
        cmp     a:LS_TOP,x
        bcs     :+
        sta     a:LS_TOP,x
:       sec                             ; below the page: at the bottom
        sbc     lvis
        bcc     @cmp
        inc     a
        cmp     a:LS_TOP,x
        bcc     @cmp
        sta     a:LS_TOP,x
@cmp:   lda     a:LS_TOP,x
        cmp     lmax
        bcc     :+
        lda     lmax
        sta     a:LS_TOP,x
:       cmp     z:ui_t0
        beq     :+
        sec
        rts
:       clc
        rts

; select row A (clamped; $FFFF none), scrolled into view, redrawn -> A = UA_CHANGE / USED
ls_select:
        ldx     z:ui_c
        cmp     #$FFFF
        beq     :+
        cmp     a:LS_COUNT,x
        bcc     :+
        lda     a:LS_COUNT,x
        dec     a
        bpl     :+
        lda     #$FFFF
:       ldy     a:LS_SEL,x
        sty     lold
        cmp     lold
        bne     :+
        jsr     ls_layout               ; the same: just keep it in view
        jsr     ui_ls_show
        bcc     @same
        lda     z:ui_t0
        jsr     ls_scroll
        jsr     ls_sbdraw
@same:  lda     #UA_USED
        rts
:       sta     a:LS_SEL,x
        jsr     ls_layout
        jsr     ui_ls_show
        bcc     :+
        lda     z:ui_t0
        jsr     ls_scroll               ; (then the two rows whose selection changed)
        jsr     ls_sbdraw
:       lda     lold
        jsr     ls_one
        ldx     z:ui_c
        lda     a:LS_SEL,x
        jsr     ls_one
        lda     #UA_CHANGE
        rts

; is the pointer on the scroll bar? (C set); ls_sbrel: its coordinates made relative to it
ls_onsb:
        jsr     ls_sboff
        lda     ui_px
        cmp     z:ui_t0
        bcc     :+
        jsr     ls_sbrel
        sec
:       rts
ls_sbrel:
        jsr     ls_sboff
        lda     ui_px
        sec
        sbc     z:ui_t0
        sta     ui_px
        dec     ui_py
        rts
ls_sboff:
        lda     lrx
        clc
        adc     lrw
        ldx     z:ui_c
        sec
        sbc     a:CT_X,x
        sta     z:ui_t0
        rts

; the scroll bar's routine X (press / drag) with ui_c = the bar; a change scrolls the rows
ls_sbcall:
        stx     lcb
        lda     z:ui_c
        pha
        clc
        adc     #LS_SB
        tax
        jsr     ui_setc
        ldx     #0
        jsr     (lcb,x)
        tay
        pla
        tax
        jsr     ui_setc
        cpy     #UA_CHANGE
        bne     :+
        lda     a:LS_TOP,x
        pha
        lda     a:LS_SB+SB_POS,x
        sta     a:LS_TOP,x
        jsr     ls_layout
        pla
        jsr     ls_scroll
:       lda     #UA_USED
        rts

ui_ls_press:
        jsr     ls_layout
        stz     ui_lsb
        jsr     ls_onsb
        bcc     :+
        inc     ui_lsb
        ldx     #.loword(ui_sb_press)
        jmp     ls_sbcall
:       lda     ui_py                   ; the row
        jsr     ls_rowat
        bcs     @no
        sta     z:ui_t1
        sys     SYS_UPTIME
        sta     z:ui_t2
        ldx     z:ui_c
        lda     z:ui_t1
        cmp     a:LS_SEL,x              ; a second press on the selected row, soon enough
        bne     :+
        lda     z:ui_t2
        sec
        sbc     a:LS_CLICK,x
        cmp     #500
        bcs     :+
        stz     a:LS_CLICK,x
        lda     #UA_OPEN
        rts
:       lda     z:ui_t2
        sta     a:LS_CLICK,x
        lda     z:ui_t1
        jmp     ls_select
@no:    lda     #UA_USED
        rts

; pointer y A (relative) -> A = row, C set: none (outside the rows)
ls_rowat:
        dec     a
        bmi     @no
        ldy     #0
:       cmp     #UI_ROWH
        bcc     :+
        sbc     #UI_ROWH
        iny
        bra     :-
:       cpy     lvis
        bcs     @no
        tya
        ldx     z:ui_c
        clc
        adc     a:LS_TOP,x
        cmp     a:LS_COUNT,x
        bcs     @no
        clc
        rts
@no:    sec
        rts

ui_ls_drag:
        jsr     ls_layout
        lda     ui_lsb
        beq     @sel
        lda     ui_rel
        beq     :+
        stz     ui_lsb
:       jsr     ls_onsb                 ; (just the coordinates)
        lda     z:ui_t0
        ldx     z:ui_c
        lda     ui_px                   ; relative to the bar even when outside it
        ldx     #.loword(ui_sb_drag)
        jmp     ls_sbcall
@sel:   lda     ui_rel                  ; dragging the selection
        bne     @used
        lda     ui_py
        dec     a
        bpl     :+
        ldx     z:ui_c                  ; above: the row before the page
        lda     a:LS_TOP,x
        beq     @used
        dec     a
        bra     @go
:       ldy     #0
:       cmp     #UI_ROWH
        bcc     :+
        sbc     #UI_ROWH
        iny
        bra     :-
:       tya
        ldx     z:ui_c
        clc
        adc     a:LS_TOP,x
        cmp     a:LS_COUNT,x
        bcc     @go
        lda     a:LS_COUNT,x
        beq     @used
        dec     a
@go:    jmp     ls_select
@used:  lda     #UA_USED
        rts

ui_ls_key:
        jsr     ls_layout
        ldx     z:ui_c
        lda     a:LS_SEL,x
        sta     z:ui_t0
        lda     ui_key
        cmp     #KEY_UP
        bne     :+
        lda     z:ui_t0
        cmp     #$FFFF
        beq     @first
        dec     a
        bpl     @go
@first: lda     #0
        bra     @go
:       cmp     #KEY_DOWN
        bne     :+
        lda     z:ui_t0
        inc     a                       ; ($FFFF -> 0)
        bra     @go
:       cmp     #KEY_PGUP
        bne     :+
        lda     z:ui_t0
        cmp     #$FFFF
        beq     @first
        sec
        sbc     lvis
        bcc     @first
        bra     @go
:       cmp     #KEY_PGDN
        bne     :+
        lda     z:ui_t0
        cmp     #$FFFF
        beq     @first
        clc
        adc     lvis
        bra     @go
:       cmp     #KEY_HOME
        beq     @first
        cmp     #KEY_END
        bne     @none
        lda     a:LS_COUNT,x
        beq     @first
        dec     a
@go:    ldx     z:ui_c
        ldy     a:LS_COUNT,x
        beq     @used
        jmp     ls_select
@used:  lda     #UA_USED
        rts
@none:  lda     #UA_NONE
        rts

; the wheel: 3 rows a notch
ui_ls_wheel:
        jsr     ls_layout
        lda     ui_ev+2
        asl     a
        clc
        adc     ui_ev+2
        eor     #$FFFF
        inc     a
        ldx     z:ui_c
        clc
        adc     a:LS_TOP,x
        bpl     :+
        lda     #0
:       cmp     lmax
        bcc     :+
        lda     lmax
:       cmp     a:LS_TOP,x
        beq     :+
        ldy     a:LS_TOP,x
        phy
        sta     a:LS_TOP,x
        jsr     ls_layout
        pla
        jsr     ls_scroll
        jsr     ls_sbdraw
:       lda     #UA_USED
        rts

; X = list, A = rows: nothing selected, at the top, redrawn
ui_lsset:
        sta     a:LS_COUNT,x
        lda     #$FFFF
        sta     a:LS_SEL,x
        stz     a:LS_TOP,x
        jmp     ui_draw

; X = list, A = row: selected and shown
ui_lssel:
        pha
        jsr     ui_setc
        jsr     ls_layout
        pla
        jmp     ls_select

        .segment "BSS"
lrx:    .res    2
lotop:  .res    2                       ; ls_scroll: the old top, rows moved
ldelta: .res    2
lry:    .res    2
lrw:    .res    2
lvis:   .res    2
lmax:   .res    2
lslot:  .res    2
lrow:   .res    2
lsel:   .res    2
lold:   .res    2
lcb:    .res    2
lbg:    .res    2
ltx:    .res    2
ui_lsb: .res    2
