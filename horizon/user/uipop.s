; uipop.s - controls library (0.15): pop-up menus (ui_popup, ui_popat), the menu key
; (ui_menukey), the chime (ui_chime, ui_beep), and the text field's pop-up menu (Cut, Copy,
; Paste, Select all). See ui.inc.
        .include "horizon.inc"
        .include "ui.inc"
        .import ui_lbtn, ui_setc, ui_rbtn

        .segment "RODATA"
; the text field's menu: a state byte before each item (MS_DIM set as needed)
fm_items:
fm_cut: .byte   MS_STATE, "Cut", 9, "Ctrl+X", 0
fm_copy: .byte  MS_STATE, "Copy", 9, "Ctrl+C", 0
fm_paste: .byte MS_STATE, "Paste", 9, "Ctrl+V", 0
        .byte   "-", 0
        .byte   MS_STATE, "Select all", 9, "Ctrl+A", 0
        .byte   0, 0
fm_end:
fm_keys: .byte  24, 3, 22, 0, 1         ; ctrl-X, C, V, -, A

        .segment "CODE"
        .a16
        .i16

; A = window, X = items ("item", ..., ""; state bytes, separators and shortcuts as in a
; menu) -> A = the item chosen (counting separators), $FFFF: none. At the pointer.
ui_popup:
        ldy     #POP_HERE
        sty     pp_x
        ldy     #0
        bra     pp_go
; the same at ui_x, ui_y of the window's content, the first item highlighted (opened from
; the keyboard)
ui_popat:
        ldy     z:ui_x
        sty     pp_x
        ldy     z:ui_y
        sty     pp_blk+5
        ldy     #POP_KEY
pp_go:  sty     pp_blk+7
        stx     pp_blk
        ldy     #^pp_blk                ; (the items: in the program's bank)
        sty     pp_blk+2
        ldy     pp_x
        sty     pp_blk+3
        ptr     pp_blk
        sys     SYS_WPOPUP
        bcc     :+
        lda     #$FFFF
:       stz     ui_lbtn                 ; (the menu took the button's release)
        stz     ui_rbtn
        rts

; the event in ui_ev: C set if it is the menu key (or Shift+F10) pressed
ui_menukey:
        lda     ui_ev
        and     #$00FF
        cmp     #WE_KEY
        bne     @no
        lda     ui_ev+4
        cmp     #$0100
        bcc     @no
        lda     ui_ev+2
        cmp     #$65                    ; the menu (application) key
        beq     @yes
        cmp     #$43                    ; Shift+F10
        bne     @no
        lda     ui_ev+4
        and     #$22
        beq     @no
@yes:   sec
        rts
@no:    clc
        rts

; the error beep (a soft chime; the beep volume setting)
ui_beep:
        lda     #CH_ERROR
        ; fall through
; A = CH_* kind: the chime of that kind at the beep volume setting
ui_chime:
        ldx     #$FFFF
        sys     SYS_CHIME
        rts

; X = text field (it has the focus), A = 0 at the pointer / 1 from the keyboard: its pop-up
; menu; the item chosen is done as its ctrl key -> A = UA_* (as ui_fd_key)
ui_fd_menu:
        sta     pp_key
        jsr     ui_setc
        ldy     #0                      ; the items, Cut and Copy dimmed without a selection,
:       lda     fm_items,y              ; Paste with an empty clipboard
        sta     pp_items,y
        iny
        iny
        cpy     #fm_end - fm_items
        bcc     :-
        ldx     z:ui_c
        lda     a:FD_CUR,x
        cmp     a:FD_ANC,x
        bne     :+
        sep     #$20
        .a8
        lda     #MS_STATE | MS_DIM
        sta     pp_items
        sta     pp_items + 12       ; (fm_copy)
        rep     #$20
        .a16
:       lda     #.loword(pp_cl)         ; the clipboard's length
        sta     pp_cl
        lda     #^pp_cl
        sta     pp_cl+2
        stz     pp_cl+3
        ptr     pp_cl
        sys     SYS_CLGET
        bcs     :+
        cmp     #0
        bne     :++
:       sep     #$20
        .a8
        lda     #MS_STATE | MS_DIM
        sta     pp_items + 25       ; (fm_paste)
        rep     #$20
        .a16
:       ldx     z:ui_c
        lda     a:CT_WIN,x
        and     #$00FF
        pha
        lda     pp_key
        beq     :+
        lda     a:CT_X,x                ; (from the keyboard: below the field's left end)
        sta     z:ui_x
        lda     a:CT_Y,x
        clc
        adc     a:CT_H,x
        sta     z:ui_y
        pla
        ldx     #.loword(pp_items)
        jsr     ui_popat
        bra     @do
:       pla
        ldx     #.loword(pp_items)
        jsr     ui_popup
@do:    cmp     #5
        bcs     @none
        tax
        lda     fm_keys,x
        and     #$00FF
        beq     @none
        sta     ui_key
        lda     #$01                    ; (left ctrl)
        sta     ui_kmod
        ldx     z:ui_c
        jsr     ui_setc
        jmp     ui_fd_key
@none:  lda     #UA_USED
        rts

        .segment "BSS"
pp_blk:  .res   8                       ; win_popup's block
pp_key:  .res   2
pp_cl:   .res   6                       ; clip_get: {u24 buffer, u16 size 0}
pp_x:    .res   2
pp_items: .res  fm_end - fm_items + 1

        .export ui_fd_menu
