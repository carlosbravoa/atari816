; ui.s - controls library, core: start, events, routing, drawing helpers, buttons, labels.
; See ui.inc for the API. The scroll bar is in uisb.s, the text field in uifld.s, the list
; in uilist.s, the alert in uialert.s, the file dialog in uifile.s.
        .include "horizon.inc"
        .include "ui.inc"

        .segment "CODE"
        .a16
        .i16

; ---------------------------------------------------------------- start
; the UI font's advances, one SYS_WTWIDTH per character
ui_init:
        ldx     #0
@c:     txa
        clc
        adc     #32
        sta     ui_tbuf                 ; (character, 0)
        phx
        ptr     ui_tbuf
        lda     #0
        sys     SYS_WTWIDTH
        plx
        sep     #$20
        .a8
        sta     ui_cw,x
        rep     #$20
        .a16
        inx
        cpx     #95
        bcc     @c
        stz     ui_cap
        stz     ui_lbtn
        stz     ui_dfr
        rts

; A = 0 wait / 1 poll -> ui_ev; C set: nothing (poll)
ui_getev:
        ldx     ui_dfr                  ; an event put aside by a dialog first
        beq     @get
        stz     ui_dfr
        ldx     #6
:       lda     ui_dfrev,x
        sta     ui_ev,x
        dex
        dex
        bpl     :-
        clc
        rts
@get:   ptr     ui_ev
        sys     SYS_WEVENT
        rts

; (dialogs) the event in ui_ev belongs to another window: keep a WE_RESIZE / WE_CLOSE
ui_defer_put:
        lda     ui_ev
        and     #$00FF
        cmp     #WE_RESIZE
        beq     :+
        cmp     #WE_CLOSE
        bne     @out
:       ldx     #6
:       lda     ui_ev,x
        sta     ui_dfrev,x
        dex
        dex
        bpl     :-
        lda     #1
        sta     ui_dfr
@out:   rts

; ---------------------------------------------------------------- drawing helpers
; A = op | colour << 8: the rectangle ui_x, ui_y, ui_w, ui_h
ui_rect:
        sta     ui_blk
        lda     z:ui_c2
        and     #$00FF
        sta     ui_blk+2
        lda     z:ui_x
        sta     ui_blk+4
        lda     z:ui_y
        sta     ui_blk+6
        lda     z:ui_w
        sta     ui_blk+8
        lda     z:ui_h
        sta     ui_blk+10
ui_wdraw:
        lda     z:ui_win
        ptr     ui_blk
        sys     SYS_WDRAW
        rts

; X = string, A = ink | paper << 8, at ui_x, ui_y, font ui_font
ui_text:
        stx     ui_blk+12
        pha
        xba
        and     #$00FF
        sta     ui_blk+2
        lda     z:ui_font
        xba
        and     #$FF00
        ora     ui_blk+2
        sta     ui_blk+2                ; c2 | font << 8
        pla
        xba
        and     #$FF00
        ora     #WD_TEXT
        sta     ui_blk
        lda     #^ui_blk
        sta     ui_blk+14
        lda     z:ui_x
        sta     ui_blk+4
        lda     z:ui_y
        sta     ui_blk+6
        bra     ui_wdraw

; X, Y = destination: the rectangle ui_x, ui_y, ui_w, ui_h moves there (WD_COPY)
ui_copy:
        lda     #WD_COPY
        sta     ui_blk
        stx     ui_blk+1                ; c1 | c2 << 8 = destination x
        sty     ui_blk+12               ; the pointer's low word = destination y
        lda     z:ui_x
        sta     ui_blk+4
        lda     z:ui_y
        sta     ui_blk+6
        lda     z:ui_w
        sta     ui_blk+8
        lda     z:ui_h
        sta     ui_blk+10
        jmp     ui_wdraw

; A = 0 raised / 1 sunken: a 1-pixel bevel inside ui_x, ui_y, ui_w, ui_h (kept)
ui_bevel:
        ldx     #C_WHITE | (C_DARK << 8)
        cmp     #0
        beq     :+
        ldx     #C_DARK | (C_WHITE << 8)
:       stx     z:ui_t0
        lda     z:ui_h                  ; top: (x, y, w, 1); left: (x, y, 1, h)
        pha
        lda     #1
        sta     z:ui_h
        lda     z:ui_t0
        jsr     @fill
        pla
        sta     z:ui_h
        lda     z:ui_w
        pha
        lda     #1
        sta     z:ui_w
        lda     z:ui_t0
        jsr     @fill
        pla
        sta     z:ui_w
        lda     z:ui_x                  ; right: (x + w - 1, y, 1, h)
        pha
        clc
        adc     z:ui_w
        dec     a
        sta     z:ui_x
        lda     z:ui_w
        pha
        lda     #1
        sta     z:ui_w
        lda     z:ui_t0+1
        jsr     @fill
        pla
        sta     z:ui_w
        pla
        sta     z:ui_x
        lda     z:ui_y                  ; bottom: (x, y + h - 1, w, 1)
        pha
        clc
        adc     z:ui_h
        dec     a
        sta     z:ui_y
        lda     z:ui_h
        pha
        lda     #1
        sta     z:ui_h
        lda     z:ui_t0+1
        jsr     @fill
        pla
        sta     z:ui_h
        pla
        sta     z:ui_y
        rts
@fill:  xba
        and     #$FF00
        ora     #WD_FILL
        jmp     ui_rect

; A = character, X = font -> A = its advance (keeps X, Y)
ui_cwidth:
        cpx     #0
        bne     @fx
        and     #$00FF
        cmp     #' '
        bcc     @q
        cmp     #$7F
        bcc     :+
@q:     lda     #'?'
:       phx
        sec
        sbc     #' '
        tax
        lda     ui_cw,x
        and     #$00FF
        plx
        rts
@fx:    lda     #8
        rts

; X = string, A = font -> A = width
ui_twidth:
        stx     z:ui_t1
        tax
        stz     z:ui_t0
        ldy     #0
:       lda     (ui_t1),y
        and     #$00FF
        beq     :+
        jsr     ui_cwidth
        clc
        adc     z:ui_t0
        sta     z:ui_t0
        iny
        bra     :-
:       lda     z:ui_t0
        rts

; X = string (writable), A = width: cut with "..." until it fits (UI font)
ui_fit:
        cmp     #$8000
        bcc     :+
        lda     #0
:       sta     z:ui_t2
        stx     z:ui_t3
        jsr     ui_strlen
        sta     z:ui_t4
@try:   ldx     z:ui_t3
        lda     #0
        jsr     ui_twidth
        cmp     z:ui_t2
        bcc     @out
        beq     @out
        lda     z:ui_t4
        beq     @out
        dec     z:ui_t4
        lda     z:ui_t3
        clc
        adc     z:ui_t4
        tax
        lda     #'.' | ('.' << 8)
        sta     a:0,x
        sta     a:1,x
        stz     a:3,x                   ; ('.', 0 at +2, +3)
        bra     @try
@out:   rts

; X = string -> A = length (keeps X)
ui_strlen:
        phx
        ldy     #0
:       lda     a:0,x
        and     #$00FF
        beq     :+
        inx
        iny
        bra     :-
:       tya
        plx
        rts

; X = source, Y = destination -> A = length
ui_strcpy:
        stx     z:ui_t0
        sty     z:ui_t1
        ldy     #0
        sep     #$20
        .a8
:       lda     (ui_t0),y
        sta     (ui_t1),y
        beq     :+
        iny
        bra     :-
:       rep     #$20
        .a16
        tya
        rts

; X = label -> A = button width: text + 24, at least 64
ui_btnw:
        lda     #0
        jsr     ui_twidth
        clc
        adc     #24
        cmp     #64
        bcs     :+
        lda     #64
:       rts


; A * X / Y -> A (32-bit product; the quotient is clamped to 16 bits; Y = 0 gives 0)
ui_muldiv:
        sta     z:ui_t0
        stx     z:ui_t1
        sty     z:ui_t2
        stz     z:ui_t3                 ; product t4:t3 (hi:lo)
        stz     z:ui_t4
        ldx     #16
@m:     asl     z:ui_t3
        rol     z:ui_t4
        asl     z:ui_t1
        bcc     :+
        lda     z:ui_t3
        clc
        adc     z:ui_t0
        sta     z:ui_t3
        bcc     :+
        inc     z:ui_t4
:       dex
        bne     @m
        lda     z:ui_t2
        beq     @zero
        lda     z:ui_t4                 ; quotient too large?
        cmp     z:ui_t2
        bcs     @big
        ldx     #16                     ; t4:t3 / t2: quotient in t3, remainder in A
@d:     asl     z:ui_t3
        rol     a
        bcs     @sub
        cmp     z:ui_t2
        bcc     :+
@sub:   sbc     z:ui_t2
        inc     z:ui_t3
:       dex
        bne     @d
        lda     z:ui_t3
        rts
@zero:  lda     #0
        rts
@big:   lda     #$FFFF
        rts

; ---------------------------------------------------------------- controls
; X = control: draw it
ui_draw:
        stx     z:ui_c
        lda     a:CT_WIN,x
        and     #$00FF
        sta     z:ui_win
        lda     a:CT_TYPE,x
        and     #$00FF
        asl     a
        tax
        jmp     (draw_tab,x)
nop_rts:
        rts

; X = control list: draw all
ui_drawall:
        stx     ui_list
:       lda     a:0,x
        beq     :+
        phx
        tax
        jsr     ui_draw
        plx
        inx
        inx
        bra     :-
:       rts

; X = field or list: give it the focus (the others of its window lose it)
ui_focus:
        stx     z:ui_t5
        lda     a:CT_FLAGS,x
        bit     #UF_FOCUS
        bne     @out
        ldx     ui_list                 ; the others (of the last list routed)
        beq     @me
@l:     lda     a:0,x
        beq     @me
        phx
        tay
        cpy     z:ui_t5
        beq     @n
        lda     a:CT_WIN,y          ; same window?
        ldx     z:ui_t5
        eor     a:CT_WIN,x
        and     #$00FF
        bne     @n
        lda     a:CT_FLAGS,y
        bit     #UF_FOCUS
        beq     @n
        and     #$FFFF ^ UF_FOCUS
        sta     a:CT_FLAGS,y
        tyx
        lda     z:ui_t5
        pha
        jsr     ui_draw
        pla
        sta     z:ui_t5
@n:     plx
        inx
        inx
        bra     @l
@me:    ldx     z:ui_t5
        lda     a:CT_FLAGS,x
        ora     #UF_FOCUS
        sta     a:CT_FLAGS,x
        jsr     ui_draw
@out:   rts

; X = control list, event in ui_ev -> A = UA_*, X = control (0: none)
ui_event:
        stx     ui_list
        stz     z:ui_c
        lda     ui_ev+1
        and     #$00FF
        sta     ui_evwin
        lda     ui_ev
        and     #$00FF
        cmp     #WE_BUTTON
        beq     @button
        cmp     #WE_MOTION
        jeq     @motion
        cmp     #WE_KEY
        jeq     @key
        cmp     #WE_WHEEL
        jeq     @wheel
@none:  lda     #UA_NONE
        ldx     #0
        rts
@button:
        lda     ui_ev+6                 ; (0.15) a right press on a text field: its menu
        and     #2
        tax
        eor     ui_rbtn
        stx     ui_rbtn
        beq     @left
        cpx     #0
        beq     @left
        ldx     ui_list
:       lda     a:0,x
        beq     @left
        inx
        inx
        tay
        jsr     ui_inside
        bcc     :-
        lda     a:CT_TYPE,y
        and     #$00FF
        cmp     #UT_FIELD
        bne     @left
        lda     a:CT_FLAGS,y
        bit     #UF_DIM
        bne     @left
        sty     z:ui_c
        tyx
        jsr     ui_focus
        ldx     z:ui_c
        lda     #0
        jsr     ui_fd_menu
        jmp     @ret
@none2: jmp     @none
@left:  lda     ui_ev+6
        and     #1
        tax
        eor     ui_lbtn                 ; left changed?
        stx     ui_lbtn
        beq     @none2
        cpx     #0
        beq     @release
        ldx     ui_list                 ; a press: the control under the pointer
@hit:   lda     a:0,x
        beq     @none2
        inx
        inx
        tay
        jsr     ui_inside
        bcc     @hit
        sty     z:ui_c
        lda     a:CT_TYPE,y
        and     #$00FF
        cmp     #UT_LABEL
        beq     @none2
        lda     a:CT_FLAGS,y
        bit     #UF_DIM
        bne     @none2
        sty     ui_cap
        lda     a:CT_TYPE,y
        and     #$00FF
        cmp     #UT_FIELD
        beq     :+
        cmp     #UT_LIST
        bne     @press
:       tyx
        jsr     ui_focus
@press: ldx     ui_cap
        jsr     ui_setc
        jsr     ui_relxy
        lda     a:CT_TYPE,x
        and     #$00FF
        asl     a
        tax
        jsr     (press_tab,x)
        bra     @ret
@release:
        lda     #1
        sta     ui_rel
        bra     :+
@motion:
        stz     ui_rel
:       ldx     ui_cap
        jeq     @none
        jsr     ui_setc
        jsr     ui_relxy
        lda     a:CT_TYPE,x
        and     #$00FF
        asl     a
        tax
        jsr     (drag_tab,x)
        ldx     ui_rel
        beq     @ret
        stz     ui_cap
@ret:   ldx     z:ui_c
        rts
@key:   jsr     ui_menukey              ; (0.15) the menu key on a focused text field
        bcc     :+
        ldy     #UT_FIELD
        jsr     @focused
        bcc     :+
        sty     z:ui_c
        tyx
        lda     #1
        jsr     ui_fd_menu
        jmp     @ret
:       lda     ui_ev+4
        and     #$00FF
        sta     ui_kmod
        lda     ui_ev+2
        ldx     ui_ev+4
        jsr     key_ascii
        sta     ui_key
        cmp     #0
        jeq     @none
        lda     ui_kmod
        and     #$11
        bne     @ctl
        lda     ui_key
        cmp     #9
        jeq     @tab
        cmp     #27
        bne     :+
        lda     #UF_CANCEL
        jmp     @btn
:       cmp     #13
        bne     @ctl
        ldy     #UT_BUTTON              ; Enter: a focused button is activated
        jsr     @focused
        bcc     :+
        sty     z:ui_c
        jsr     bt_flash
        jmp     @ret
:       ldy     #UT_LIST                ; a focused list opens
        jsr     @focused
        bcc     :+
        sty     z:ui_c
        lda     a:LS_SEL,y
        cmp     #$FFFF
        jeq     @used
        lda     #UA_OPEN
        jmp     @ret
:       lda     #UF_DEFAULT
        jmp     @btn
@ctl:   ldy     #0                      ; the focused control's keys
        jsr     @focused
        jcc     @none
        sty     z:ui_c
        tyx
        jsr     ui_setc
        lda     a:CT_TYPE,x
        and     #$00FF
        asl     a
        tax
        jsr     (key_tab,x)
        jmp     @ret
@wheel: ldx     ui_list
:       lda     a:0,x
        jeq     @none
        inx
        inx
        tay
        lda     a:CT_WIN,y
        and     #$00FF
        cmp     ui_evwin
        bne     :-
        lda     a:CT_TYPE,y
        and     #$00FF
        cmp     #UT_LIST
        beq     :+
        cmp     #UT_VSCROLL
        bne     :-
        sty     z:ui_c
        tyx
        jsr     ui_setc
        jsr     ui_sb_wheel
        jmp     @ret
:       sty     z:ui_c
        tyx
        jsr     ui_setc
        jsr     ui_ls_wheel
        jmp     @ret
@tab:   ldy     #0                      ; Tab: the next control that takes the focus (a field,
        jsr     @focused                ; a list, a button not dimmed) after the focused one,
        bcs     :+                      ; in list order; Shift + Tab: the one before
        ldy     #0
:       sty     z:ui_t5                 ; (0: none focused)
        stz     tb_first
        stz     tb_last
        stz     tb_prev
        stz     tb_next
        stz     tb_pass
        ldx     ui_list
@tl:    lda     a:0,x
        beq     @tend
        inx
        inx
        tay
        cpy     z:ui_t5
        bne     :+
        lda     #1
        sta     tb_pass
        bra     @tl
:       jsr     ui_canfocus
        bcc     @tl
        lda     tb_first
        bne     :+
        sty     tb_first
:       sty     tb_last
        lda     tb_pass
        bne     :+
        sty     tb_prev                 ; (the last one before the focused one)
        bra     @tl
:       lda     tb_next
        bne     @tl
        sty     tb_next
        bra     @tl
@tend:  lda     ui_kmod
        and     #$22
        bne     @back
        ldy     tb_next
        bne     @tgo
        ldy     tb_first
        bra     @tgo
@back:  ldy     tb_prev
        bne     @tgo
        ldy     tb_last
@tgo:   cpy     #0
        jeq     @none
        cpy     z:ui_t5
        jeq     @none
        tyx
        phy
        jsr     ui_focus
        ply
        sty     z:ui_c
@used:  lda     #UA_USED
        jmp     @ret
; a button of the event's window with flag A: flash it, UA_CLICK
@btn:   sta     z:ui_t5
        ldx     ui_list
:       lda     a:0,x
        jeq     @none
        inx
        inx
        tay
        lda     a:CT_WIN,y
        and     #$00FF
        cmp     ui_evwin
        bne     :-
        lda     a:CT_TYPE,y
        and     #$00FF
        cmp     #UT_BUTTON
        bne     :-
        lda     a:CT_FLAGS,y
        bit     #UF_DIM
        bne     :-
        and     z:ui_t5
        beq     :-
        sty     z:ui_c
        jsr     bt_flash
        jmp     @ret
; the focused control of the event's window (of type Y, 0 = any) -> C set, Y
@focused:
        sty     z:ui_t4
        ldx     ui_list
:       lda     a:0,x
        beq     @nf
        inx
        inx
        tay
        lda     a:CT_WIN,y
        and     #$00FF
        cmp     ui_evwin
        bne     :-
        lda     a:CT_FLAGS,y
        bit     #UF_FOCUS
        beq     :-
        lda     z:ui_t4
        beq     :+
        lda     a:CT_TYPE,y
        and     #$00FF
        cmp     z:ui_t4
        bne     :-
:       sec
        rts
@nf:    clc
        rts

; Y = control: C set if it takes the focus with Tab (in the event's window: a field, a list,
; a button not dimmed). Keeps X, Y.
ui_canfocus:
        lda     a:CT_WIN,y
        and     #$00FF
        cmp     ui_evwin
        bne     @no
        lda     a:CT_TYPE,y
        and     #$00FF
        cmp     #UT_FIELD
        beq     @yes
        cmp     #UT_LIST
        beq     @yes
        cmp     #UT_BUTTON
        bne     @no
        lda     a:CT_FLAGS,y
        bit     #UF_DIM
        bne     @no
@yes:   sec
        rts
@no:    clc
        rts

; Y = control: C set if the event's pointer is inside it (and in its window). Keeps X, Y.
ui_inside:
        lda     a:CT_WIN,y
        and     #$00FF
        cmp     ui_evwin
        bne     @no
        lda     ui_ev+2
        sec
        sbc     a:CT_X,y
        bmi     @no
        cmp     a:CT_W,y
        bcs     @no
        lda     ui_ev+4
        sec
        sbc     a:CT_Y,y
        bmi     @no
        cmp     a:CT_H,y
        bcs     @no
        sec
        rts
@no:    clc
        rts

; X = control: ui_c, ui_win (keeps X)
ui_setc:
        stx     z:ui_c
        lda     a:CT_WIN,x
        and     #$00FF
        sta     z:ui_win
        rts

; X = control: ui_px, ui_py = the event's pointer relative to it (keeps X)
ui_relxy:
        lda     ui_ev+2
        sec
        sbc     a:CT_X,x
        sta     ui_px
        lda     ui_ev+4
        sec
        sbc     a:CT_Y,x
        sta     ui_py
        rts

; ui_x .. ui_h = control ui_c's box
ui_box: ldx     z:ui_c
        lda     a:CT_X,x
        sta     z:ui_x
        lda     a:CT_Y,x
        sta     z:ui_y
        lda     a:CT_W,x
        sta     z:ui_w
        lda     a:CT_H,x
        sta     z:ui_h
        rts

; ---------------------------------------------------------------- button
bt_draw:
        jsr     ui_box
        ldx     z:ui_c
        lda     a:CT_FLAGS,x
        sta     z:ui_t5
        bit     #UF_DEFAULT
        beq     @n
        lda     #WD_FRAME | (C_BLACK << 8)  ; the default button: a 2-pixel black outline
        jsr     ui_rect
        jsr     @in
        lda     #WD_FRAME | (C_BLACK << 8)
        bra     @f
@n:     lda     #WD_FRAME | (C_DARK << 8)
@f:     jsr     ui_rect
        jsr     @in
        lda     z:ui_t5
        and     #UF_PRESSED
        beq     :+
        lda     #WD_FILL | (C_LIGHT << 8)
        bra     :++
:       lda     #WD_FILL | (C_BODY << 8)
:       jsr     ui_rect
        lda     z:ui_t5
        and     #UF_PRESSED
        beq     :+
        lda     #1
:       jsr     ui_bevel
        ldx     z:ui_c                  ; the label, centred (pressed: one pixel down right)
        lda     a:BT_LABEL,x
        tax
        ldy     #.loword(ui_tbuf)
        jsr     ui_strcpy
        lda     z:ui_w
        sec
        sbc     #8
        ldx     #.loword(ui_tbuf)
        jsr     ui_fit
        ldx     #.loword(ui_tbuf)
        lda     #0
        jsr     ui_twidth
        sta     z:ui_t0
        lda     z:ui_w
        sec
        sbc     z:ui_t0
        lsr     a
        clc
        adc     z:ui_x
        sta     z:ui_x
        lda     z:ui_h
        sec
        sbc     #8
        lsr     a
        clc
        adc     z:ui_y
        sta     z:ui_y
        lda     z:ui_t5
        and     #UF_PRESSED
        beq     :+
        inc     z:ui_x
        inc     z:ui_y
:       stz     z:ui_font
        lda     z:ui_t5
        and     #UF_DIM
        beq     :+
        lda     #C_MID | ($FF << 8)
        bra     :++
:       lda     #C_BLACK | ($FF << 8)
:       ldx     #.loword(ui_tbuf)
        jsr     ui_text
        lda     z:ui_t5                 ; focused: a dotted frame 3 pixels inside
        and     #UF_FOCUS
        bne     :+
        rts
:       jsr     ui_box
        lda     z:ui_x
        clc
        adc     #3
        sta     z:ui_x
        lda     z:ui_y
        clc
        adc     #3
        sta     z:ui_y
        lda     z:ui_w
        sec
        sbc     #6
        sta     z:ui_w
        lda     z:ui_h
        sec
        sbc     #6
        sta     z:ui_h
        lda     z:ui_t5                 ; (dots of black and the button's face)
        and     #UF_PRESSED
        beq     :+
        lda     #C_LIGHT
        bra     :++
:       lda     #C_BODY
:       sta     z:ui_c2
        lda     z:ui_h                  ; top, bottom: (x, y, w, 1), (x, y + h - 1, w, 1)
        pha
        lda     #1
        sta     z:ui_h
        jsr     @dot
        lda     1,s
        dec     a
        clc
        adc     z:ui_y
        sta     z:ui_y
        jsr     @dot
        pla                             ; left, right: (x, y, 1, h), (x + w - 1, y, 1, h)
        sta     z:ui_h
        dec     a
        eor     #$FFFF
        sec
        adc     z:ui_y
        sta     z:ui_y
        lda     #1
        sta     z:ui_w
        jsr     @dot
        lda     z:ui_x
        pha
        jsr     ui_box
        pla
        clc
        adc     z:ui_w
        sec
        sbc     #7
        sta     z:ui_x
        lda     #1
        sta     z:ui_w
        lda     z:ui_y
        clc
        adc     #3
        sta     z:ui_y
        lda     z:ui_h
        sec
        sbc     #6
        sta     z:ui_h
@dot:   lda     #WD_DITHER | (C_BLACK << 8)
        jmp     ui_rect
@in:    inc     z:ui_x                  ; the box one pixel smaller
        inc     z:ui_y
        dec     z:ui_w
        dec     z:ui_w
        dec     z:ui_h
        dec     z:ui_h
        rts

; Space on the focused button activates it
bt_key: lda     ui_key
        cmp     #' '
        beq     bt_flash
        lda     #UA_NONE
        rts

; ui_c = button: drawn pressed for a moment -> A = UA_CLICK
bt_flash:
        ldx     z:ui_c
        lda     a:CT_FLAGS,x
        ora     #UF_PRESSED
        sta     a:CT_FLAGS,x
        jsr     ui_draw
        sys     SYS_WSSYNC
        lda     #80
        sys     SYS_SLEEP
        ldx     z:ui_c
        lda     a:CT_FLAGS,x
        and     #$FFFF ^ UF_PRESSED
        sta     a:CT_FLAGS,x
        jsr     ui_draw
        lda     #UA_CLICK
        rts

bt_press:
        ldx     z:ui_c
        lda     a:CT_FLAGS,x
        ora     #UF_PRESSED
        sta     a:CT_FLAGS,x
        jsr     ui_draw
        lda     #UA_USED
        rts

; motion / release (ui_rel): pressed while the pointer is inside; a release inside clicks
bt_drag:
        ldy     z:ui_c
        jsr     ui_inside
        lda     #0
        rol     a
        sta     z:ui_t2                 ; inside
        lda     ui_rel
        beq     @mot
        stz     z:ui_t3                 ; released: not pressed; clicked if inside
        bra     @ap
@mot:   lda     z:ui_t2
        beq     :+
        lda     #UF_PRESSED
:       sta     z:ui_t3
        stz     z:ui_t2
@ap:    ldx     z:ui_c
        lda     a:CT_FLAGS,x
        and     #UF_PRESSED
        cmp     z:ui_t3
        beq     :+
        lda     a:CT_FLAGS,x
        eor     #UF_PRESSED
        sta     a:CT_FLAGS,x
        jsr     ui_draw
:       lda     z:ui_t2
        beq     :+
        lda     #UA_CLICK
        rts
:       lda     #UA_USED
        rts

; ---------------------------------------------------------------- label
lb_draw:
        jsr     ui_box
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        ldx     z:ui_c
        lda     a:LB_TEXT,x
        tax
        ldy     #.loword(ui_tbuf)
        jsr     ui_strcpy
        lda     z:ui_w
        ldx     #.loword(ui_tbuf)
        jsr     ui_fit
        ldx     z:ui_c
        lda     a:CT_FLAGS,x
        and     #UF_RIGHT
        beq     :+
        ldx     #.loword(ui_tbuf)
        lda     #0
        jsr     ui_twidth
        eor     #$FFFF
        sec
        adc     z:ui_w
        clc
        adc     z:ui_x
        sta     z:ui_x
:       stz     z:ui_font
        ldx     z:ui_c
        lda     a:CT_FLAGS,x
        and     #UF_DIM
        beq     :+
        lda     #C_MID | ($FF << 8)
        bra     :++
:       lda     #C_BLACK | ($FF << 8)
:       ldx     #.loword(ui_tbuf)
        jmp     ui_text

none_ev:
        lda     #UA_NONE
        rts

        .segment "RODATA"
draw_tab:  .addr nop_rts, bt_draw, ui_sb_draw, ui_sb_draw, ui_fd_draw, ui_ls_draw, lb_draw
press_tab: .addr none_ev, bt_press, ui_sb_press, ui_sb_press, ui_fd_press, ui_ls_press, none_ev
drag_tab:  .addr none_ev, bt_drag, ui_sb_drag, ui_sb_drag, ui_fd_drag, ui_ls_drag, none_ev
key_tab:   .addr none_ev, bt_key, none_ev, none_ev, ui_fd_key, ui_ls_key, none_ev

        .segment "BSS"
ui_blk:  .res   16
ui_ev:   .res   8
ui_dfrev: .res  8
ui_dfr:  .res   2
ui_cw:   .res   96
ui_tbuf: .res   264                     ; scratch text (a label, a field's visible part, ...)
ui_cap:  .res   2                       ; the control holding the press
ui_lbtn: .res   2                       ; the left button's last state
ui_rbtn: .res   2                       ; (0.15) the right button's
ui_list: .res   2                       ; the control list of the last ui_event
ui_evwin: .res  2
ui_rel:  .res   2                       ; 1: the drag routine sees the release
ui_kmod: .res   2
ui_key:  .res   2
ui_px:   .res   2                       ; pointer relative to the control
ui_py:   .res   2
tb_first: .res  2                       ; Tab: the candidates
tb_last: .res   2
tb_prev: .res   2
tb_next: .res   2
tb_pass: .res   2
        .export ui_px, ui_py, ui_rel, ui_cap, ui_lbtn, ui_list, ui_evwin, ui_box, ui_setc
        .export ui_inside, ui_cw, ui_rbtn
        .import ui_fd_menu

        .segment "ZEROPAGE"
ui_win:  .res   2
ui_x:    .res   2
ui_y:    .res   2
ui_w:    .res   2
ui_h:    .res   2
ui_font: .res   2
ui_c2:   .res   2
ui_rsel: .res   2
ui_c:    .res   2
ui_t0:   .res   2
ui_t1:   .res   2
ui_t2:   .res   2
ui_t3:   .res   2
ui_t4:   .res   2
ui_t5:   .res   2
ui_p:    .res   4
ui_q:    .res   4
