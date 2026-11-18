; uialert.s - controls library: the alert box (a small modal window). See ui.inc.
        .include "horizon.inc"
        .include "ui.inc"
        .import ui_list, ui_cap, ui_lbtn
        .export ui_modal_begin, ui_modal_end, ui_modal_get

        .segment "CODE"
        .a16
        .i16

; X = alert block -> A = the button chosen (0 = AL_B1)
ui_alert:
        stx     al_blk
        jsr     ui_modal_begin
        lda     al_blk
        sta     z:ui_t5
        ldy     #AL_TEXT                ; the message, split into lines
        lda     (ui_t5),y
        sta     z:ui_t0
        ldy     #0
        ldx     #0
        stz     al_n
@line:  lda     al_n
        asl     a
        tax
        tya
        clc
        adc     #.loword(al_txt)
        sta     al_lp,x
        inc     al_n
@ch:    lda     (ui_t0)
        and     #$00FF
        beq     @lend
        inc     z:ui_t0
        cmp     #10
        beq     @nl
        cpy     #3 * 90 - 2
        bcs     @ch
        sep     #$20
        .a8
        sta     al_txt,y
        rep     #$20
        .a16
        iny
        bra     @ch
@nl:    lda     #0
        sep     #$20
        .a8
        sta     al_txt,y
        rep     #$20
        .a16
        iny
        lda     al_n
        cmp     #3
        bcc     @line
@lend:  lda     #0
        sep     #$20
        .a8
        sta     al_txt,y
        rep     #$20
        .a16
        stz     al_tw                   ; the widest line
        ldx     #0
:       phx
        lda     al_lp,x
        tax
        lda     #0
        jsr     ui_twidth
        plx
        cmp     al_tw
        bcc     :+
        sta     al_tw
:       inx
        inx
        txa
        lsr     a
        cmp     al_n
        bcc     :--
        stz     al_nb                   ; the buttons: widths, total
        stz     al_bt
        ldx     #0
@b:     txa
        clc
        adc     #AL_B1
        tay
        lda     (ui_t5),y
        beq     @bend
        sta     al_lab,x
        phx
        tax
        jsr     ui_btnw
        plx
        sta     al_bw,x
        clc
        adc     al_bt
        adc     #8
        sta     al_bt
        inc     al_nb
        inx
        inx
        cpx     #6
        bcc     @b
@bend:  lda     al_bt                   ; width = max(56 + text + 16, buttons + 32, 220)
        clc
        adc     #32 - 8
        sta     z:ui_t0
        lda     al_tw
        clc
        adc     #72
        cmp     z:ui_t0
        bcs     :+
        lda     z:ui_t0
:       cmp     #220
        bcs     :+
        lda     #220
:       sta     al_w
        lda     al_n                    ; text height = max(lines * 12, 24)
        asl     a
        adc     al_n
        asl     a
        asl     a
        cmp     #24
        bcs     :+
        lda     #24
:       sta     al_th
        clc
        adc     #16 + 16 + UI_BTNH + 12
        sta     al_h
        lda     al_w                    ; centred
        sta     al_wo+4
        clc
        adc     #2
        eor     #$FFFF
        sec
        adc     #640
        lsr     a
        sta     al_wo
        lda     al_h
        sta     al_wo+6
        clc
        adc     #17
        eor     #$FFFF
        sec
        adc     #360
        lsr     a
        sta     al_wo+2
        ldy     #AL_TITLE
        lda     (ui_t5),y
        sta     al_wo+8
        lda     #^al_wo                 ; (bank)
        sta     al_wo+10
        sep     #$20
        .a8
        lda     #WF_MODAL               ; (flags: a dialog)
        sta     al_wo+11
        rep     #$20
        .a16
        ptr     al_wo
        sys     SYS_WOPEN
        bcc     :+
        jsr     ui_modal_end            ; no window: the default answer
        lda     #0
        rts
:       sta     al_win
        sta     z:ui_win
        jsr     al_icon
        stz     z:ui_font               ; the lines
        lda     al_n
        asl     a
        adc     al_n
        asl     a
        asl     a
        eor     #$FFFF
        sec
        adc     al_th
        lsr     a
        clc
        adc     #16
        sta     z:ui_y
        ldx     #0
:       lda     #56
        sta     z:ui_x
        phx
        lda     al_lp,x
        tax
        lda     #C_BLACK | ($FF << 8)
        jsr     ui_text
        plx
        lda     z:ui_y
        clc
        adc     #UI_LINE
        sta     z:ui_y
        inx
        inx
        txa
        lsr     a
        cmp     al_n
        bcc     :-
        lda     al_w                    ; the buttons, from the right
        sec
        sbc     #16
        sta     z:ui_t0
        ldx     #0
        ldy     #.loword(al_btn)
@bb:    lda     #UT_BUTTON
        sta     a:CT_TYPE,y
        sep     #$20
        .a8
        lda     al_win
        sta     a:CT_WIN,y
        rep     #$20
        .a16
        lda     z:ui_t0
        sec
        sbc     al_bw,x
        sta     a:CT_X,y
        sec
        sbc     #8
        sta     z:ui_t0
        lda     al_h
        sec
        sbc     #12 + UI_BTNH
        sta     a:CT_Y,y
        lda     al_bw,x
        sta     a:CT_W,y
        lda     #UI_BTNH
        sta     a:CT_H,y
        lda     al_lab,x
        sta     a:BT_LABEL,y
        lda     #0
        cpx     #0
        bne     :+
        lda     #UF_DEFAULT
:       pha
        txa
        lsr     a
        inc     a
        cmp     al_nb
        bne     :+
        pla
        ora     #UF_CANCEL
        pha
:       pla
        sta     a:CT_FLAGS,y
        tya
        sta     al_list,x
        clc
        adc     #BT_SIZE
        tay
        inx
        inx
        txa
        lsr     a
        cmp     al_nb
        bcc     @bb
        stz     al_list,x
        ldx     #.loword(al_list)
        jsr     ui_drawall
        ldx     al_blk                  ; (0.15) the chime of its kind
        lda     a:AL_KIND,x
        and     #3
        jsr     ui_chime
@loop:  lda     al_win
        jsr     ui_modal_get
        cmp     #WE_CLOSE
        bne     :+
        lda     al_nb                   ; the close box: cancel
        dec     a
        bra     @done
:       ldx     #.loword(al_list)
        jsr     ui_event
        cmp     #UA_CLICK
        bne     @loop
        txa                             ; which one
        sec
        sbc     #.loword(al_btn)
        ldy     #0
:       cmp     #BT_SIZE
        bcc     :+
        sbc     #BT_SIZE
        iny
        bra     :-
:       tya
@done:  pha
        lda     al_win
        sys     SYS_WCLOSE
        jsr     ui_modal_end
        pla
        rts

; the icon at (16, 16), 24 x 24: a warning triangle, else a rounded square (blue: an
; "i" or a "?"; red: an "!")
al_icon:
        ldx     al_blk
        lda     a:AL_KIND,x
        and     #3
        sta     al_kind
        cmp     #AL_WARN
        bne     @note
        ldx     #0                      ; rows of 2 lines: dark outline, yellow inside
@t:     phx
        txa
        eor     #$FFFF
        sec
        adc     #27
        sta     z:ui_x
        txa
        asl     a
        adc     #16
        sta     z:ui_y
        txa
        asl     a
        inc     a
        inc     a
        sta     z:ui_w
        lda     #2
        sta     z:ui_h
        lda     #WD_FILL | (C_DARK << 8)
        jsr     ui_rect
        plx
        phx
        cpx     #1
        bcc     :+
        cpx     #11
        bcs     :+
        inc     z:ui_x
        inc     z:ui_y
        dec     z:ui_w
        dec     z:ui_w
        lda     #WD_FILL | (C_YELLOW << 8)
        jsr     ui_rect
:       plx
        inx
        cpx     #12
        bcc     @t
        lda     #C_BLACK
        jsr     @mark
        rts
@note:  ldy     #C_SELECT               ; a rounded square
        cmp     #AL_ERROR
        bne     :+
        ldy     #C_RED
:       sty     al_sqc
        lda     #18
        ldx     #16
        ldy     #20
        jsr     @blue
        lda     #16
        ldx     #18
        ldy     #24
        jsr     @blue
        lda     #C_WHITE
        ; fall through
; the mark (an "!" or an "i"): a bar and a dot, colour A
@mark:  xba
        ora     #WD_FILL
        pha
        lda     #27
        sta     z:ui_x
        lda     #2
        sta     z:ui_w
        sta     z:ui_h
        lda     al_kind
        cmp     #AL_QUESTION
        beq     @quest
        cmp     #AL_INFO
        beq     :+
        lda     #24                     ; "!": bar 24..32, dot 34
        sta     z:ui_y
        lda     #9
        sta     z:ui_h
        lda     1,s
        jsr     ui_rect
        lda     #34
        sta     z:ui_y
        lda     #2
        sta     z:ui_h
        pla
        jmp     ui_rect
:       lda     #20                     ; "i": dot 20, bar 24..34
        sta     z:ui_y
        lda     1,s
        jsr     ui_rect
        lda     #24
        sta     z:ui_y
        lda     #11
        sta     z:ui_h
        pla
        jmp     ui_rect
@blue:  sta     z:ui_x                  ; A = x, X = y, Y = w (h = 40 - 2 y + 16)
        stx     z:ui_y
        sty     z:ui_w
        txa
        asl     a
        eor     #$FFFF
        sec
        adc     #16 * 2 + 24
        sta     z:ui_h
        lda     al_sqc
        xba
        ora     #WD_FILL
        jmp     ui_rect
@quest: ldx     #0                      ; "?": its strokes (x, y, w, h)
:       lda     q_tab,x
        and     #$00FF
        sta     z:ui_x
        lda     q_tab+1,x
        and     #$00FF
        sta     z:ui_y
        lda     q_tab+2,x
        and     #$00FF
        sta     z:ui_w
        lda     q_tab+3,x
        and     #$00FF
        sta     z:ui_h
        phx
        lda     3,s
        jsr     ui_rect
        plx
        inx
        inx
        inx
        inx
        cpx     #6 * 4
        bcc     :-
        pla
        rts

; ---------------------------------------------------------------- modal helpers
; begin: the caller's routing state put aside
ui_modal_begin:
        lda     mo_depth                ; (nested: a stack of 4)
        asl     a
        adc     mo_depth
        asl     a
        tax
        lda     ui_list
        sta     mo_save,x
        lda     ui_cap
        sta     mo_save+2,x
        lda     ui_lbtn
        sta     mo_save+4,x
        stz     ui_cap
        stz     ui_lbtn
        inc     mo_depth
        rts
ui_modal_end:
        dec     mo_depth
        lda     mo_depth
        asl     a
        adc     mo_depth
        asl     a
        tax
        lda     mo_save,x
        sta     ui_list
        lda     mo_save+2,x
        sta     ui_cap
        lda     mo_save+4,x
        sta     ui_lbtn
        rts

; the next event for dialog window A -> A = its type (other windows' keys come as its own;
; their WE_RESIZE / WE_CLOSE are put aside for the program, the rest is dropped)
ui_modal_get:
        sta     mo_win
@get:   lda     #0
        jsr     ui_getev
        bcs     @get
        lda     ui_ev+1
        and     #$00FF
        cmp     mo_win
        beq     @mine
        lda     ui_ev
        and     #$00FF
        cmp     #WE_KEY
        beq     :+
        jsr     ui_defer_put
        bra     @get
:       sep     #$20
        .a8
        lda     mo_win
        sta     ui_ev+1
        rep     #$20
        .a16
@mine:  lda     ui_ev
        and     #$00FF
        rts

        .segment "RODATA"
q_tab:  .byte   24, 22, 2, 2,  25, 20, 6, 2,  30, 22, 2, 4,  27, 26, 3, 2,  27, 28, 2, 3
        .byte   27, 33, 2, 2

        .segment "BSS"
al_kind: .res   2
al_sqc: .res    2
al_blk: .res    2
al_n:   .res    2
al_lp:  .res    6
al_txt: .res    3 * 90
al_tw:  .res    2
al_nb:  .res    2
al_bt:  .res    2
al_lab: .res    6
al_bw:  .res    6
al_w:   .res    2
al_h:   .res    2
al_th:  .res    2
al_wo:  .res    12
al_win: .res    2
al_btn: .res    3 * BT_SIZE
al_list: .res   8
mo_save: .res   24
mo_depth: .res  2
mo_win: .res    2
