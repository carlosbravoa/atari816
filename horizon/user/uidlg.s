; uidlg.s - controls library: dialogs made of the program's own controls (a modal window
; that stays open while the program acts on its buttons: Find, Replace, ...). See ui.inc.
        .include "horizon.inc"
        .include "ui.inc"
        .import ui_modal_begin, ui_modal_end, ui_modal_get

        .segment "CODE"
        .a16
        .i16

; X = dialog block: its window opened (centred, WF_MODAL), the controls drawn -> C set: no
; window (nothing open)
ui_dlgopen:
        stx     dg_blk
        jsr     ui_modal_begin
        ldx     dg_blk
        lda     a:DG_W,x                ; centred: x = (640 - (w + 2)) / 2, y = (360 - (h + 17)) / 2
        sta     dg_wo+4
        clc
        adc     #2
        eor     #$FFFF
        sec
        adc     #640
        lsr     a
        sta     dg_wo
        lda     a:DG_H,x
        sta     dg_wo+6
        clc
        adc     #17
        eor     #$FFFF
        sec
        adc     #360
        lsr     a
        sta     dg_wo+2
        lda     a:DG_TITLE,x
        sta     dg_wo+8
        lda     #^dg_wo                 ; (the title's bank: ours)
        sta     dg_wo+10
        sep     #$20
        .a8
        lda     #WF_MODAL
        sta     dg_wo+11
        rep     #$20
        .a16
        ptr     dg_wo
        sys     SYS_WOPEN
        bcc     :+
        jsr     ui_modal_end
        sec
        rts
:       ldx     dg_blk
        sta     a:DG_WIN,x
        lda     a:DG_LIST,x             ; the controls are in it
        tax
:       lda     a:0,x
        beq     @drawn
        tay
        lda     dg_blk
        phx
        tax
        lda     a:DG_WIN,x
        plx
        sep     #$20
        .a8
        sta     a:CT_WIN,y
        rep     #$20
        .a16
        lda     a:CT_TYPE,y             ; (a button focused the last time: not now)
        and     #$00FF
        cmp     #UT_BUTTON
        bne     :+
        lda     a:CT_FLAGS,y
        and     #$FFFF ^ (UF_FOCUS | UF_PRESSED)
        sta     a:CT_FLAGS,y
:       inx
        inx
        bra     :--
@drawn: ldx     dg_blk
        lda     a:DG_LIST,x
        tax
        jsr     ui_drawall
        clc
        rts

; X = dialog block -> X = the button activated (Enter: the default one; Esc or the close
; box: the cancel one). The dialog stays open.
ui_dlgrun:
        stx     dg_blk
@loop:  ldx     dg_blk
        lda     a:DG_WIN,x
        jsr     ui_modal_get
        cmp     #WE_CLOSE
        bne     @ev
        ldx     dg_blk                  ; the close box: the cancel button
        lda     a:DG_LIST,x
        tax
:       lda     a:0,x
        beq     @loop
        inx
        inx
        tay
        lda     a:CT_TYPE,y
        and     #$00FF
        cmp     #UT_BUTTON
        bne     :-
        lda     a:CT_FLAGS,y
        and     #UF_CANCEL
        beq     :-
        tyx
        rts
@ev:    ldx     dg_blk
        lda     a:DG_LIST,x
        tax
        jsr     ui_event
        cmp     #UA_CLICK
        bne     @loop
        rts

; X = dialog block: its window closed
ui_dlgclose:
        lda     a:DG_WIN,x
        sys     SYS_WCLOSE
        jmp     ui_modal_end

        .segment "BSS"
dg_blk: .res    2
dg_wo:  .res    12
