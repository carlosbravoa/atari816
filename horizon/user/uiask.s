; uiask.s - controls library: ask for a value (a modal dialog: a prompt, a text field,
; Cancel and OK), built on ui_dlgopen / ui_dlgrun. See ui.inc.
        .include "horizon.inc"
        .include "ui.inc"

AW      = 248                           ; the smallest content width
AH      = 84

        .segment "CODE"
        .a16
        .i16

; X = block {u16 title, u16 prompt, u16 buffer, u16 buffer size, u16 OK label (0: "OK")}
; -> C clear: the buffer holds the text (Enter / OK); C set: cancelled (Esc, Cancel, close)
ui_ask:
        stx     z:ui_t5
        lda     a:AK_TITLE,x
        sta     ak_dg+DG_TITLE
        lda     a:AK_PROMPT,x
        sta     ak_lab+LB_TEXT
        lda     a:AK_BUF,x
        sta     ak_fld+FD_BUF
        lda     a:AK_SIZE,x
        sta     ak_fld+FD_MAX
        lda     a:AK_OK,x
        bne     :+
        lda     #.loword(s_ok)
:       sta     ak_ok+BT_LABEL
        ldx     ak_lab+LB_TEXT          ; the width: the prompt's, at least AW, at most 600
        lda     #0
        jsr     ui_twidth
        clc
        adc     #16
        cmp     #AW
        bcs     :+
        lda     #AW
:       cmp     #600
        bcc     :+
        lda     #600
:       sta     ak_dg+DG_W
        sec
        sbc     #16
        sta     ak_lab+CT_W
        sta     ak_fld+CT_W
        ldx     ak_ok+BT_LABEL          ; the buttons, from the right: OK, Cancel
        jsr     ui_btnw
        sta     ak_ok+CT_W
        eor     #$FFFF
        sec
        adc     ak_dg+DG_W
        sec
        sbc     #8
        sta     ak_ok+CT_X
        ldx     #.loword(s_cancel)
        jsr     ui_btnw
        sta     ak_cn+CT_W
        eor     #$FFFF
        sec
        adc     ak_ok+CT_X
        sec
        sbc     #8
        sta     ak_cn+CT_X
        ldx     ak_fld+FD_BUF           ; the text (cut to the buffer), all selected
        lda     ak_fld+FD_MAX
        dec     a
        sta     z:ui_t0
        jsr     ui_strlen
        cmp     z:ui_t0
        bcc     :+
        lda     z:ui_t0
        pha
        clc
        adc     ak_fld+FD_BUF
        tax
        sep     #$20
        .a8
        stz     a:0,x
        rep     #$20
        .a16
        pla
:       sta     ak_fld+FD_LEN
        sta     ak_fld+FD_CUR
        stz     ak_fld+FD_ANC
        stz     ak_fld+FD_SCR
        lda     #UF_FOCUS
        sta     ak_fld+CT_FLAGS
        ldx     #.loword(ak_dg)
        jsr     ui_dlgopen
        bcs     @out
        ldx     #.loword(ak_fld)        ; (scrolled to show the end)
        ldy     ak_fld+FD_BUF
        jsr     ui_fdset
        ldx     #.loword(ak_dg)
        jsr     ui_dlgrun
        phx
        ldx     #.loword(ak_dg)
        jsr     ui_dlgclose
        pla
        cmp     #.loword(ak_ok)
        beq     :+
        sec
@out:   rts
:       clc
        rts

        .segment "RODATA"
s_ok:   .byte   "OK", 0
s_cancel: .byte "Cancel", 0

        .segment "DATA"
ak_dg:  .addr   0
        .word   AW, AH
        .addr   ak_list
        .word   0
ak_list: .addr  ak_lab, ak_fld, ak_cn, ak_ok, 0
ak_lab: .byte   UT_LABEL, 0
        .word   8, 8, AW - 16, UI_LINE, 0
        .addr   0
ak_fld: .byte   UT_FIELD, 0
        .word   8, 24, AW - 16, UI_FLDH, UF_FOCUS
        .addr   0
        .word   2, 0, 0, 0, 0
ak_cn:  .byte   UT_BUTTON, 0
        .word   0, AH - 8 - UI_BTNH, 64, UI_BTNH, UF_CANCEL
        .addr   s_cancel
ak_ok:  .byte   UT_BUTTON, 0
        .word   0, AH - 8 - UI_BTNH, 64, UI_BTNH, UF_DEFAULT
        .addr   s_ok
