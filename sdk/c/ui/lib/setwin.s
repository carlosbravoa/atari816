; setwin.s - ui_setwin: every control of a control list in one window.
        .p816
        .smart  off
        .include "horizon.inc"
        .include "ui.inc"
        .include "huidefs.inc"


        .segment "CODE"
        .a16
        .i16

; X = control list (16-bit pointers, 0 at the end), A = window
hui_setwin:
        sta     z:hui_d
:       ldy     a:0,x
        beq     :+
        sep     #$20
        .a8
        lda     z:hui_d
        sta     a:CT_WIN,y
        rep     #$20
        .a16
        inx
        inx
        bra     :-
:       rts
