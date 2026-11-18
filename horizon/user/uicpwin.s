; uicpwin.s - controls library (0.21): the progress window of a long copy or move. A modal
; window "Copying" / "Moving": the file's name, "123 of 1,500 KB (8%)", a bar and a Cancel
; button (Esc and the close box = Cancel). It opens only when the copy still runs about
; 0.5 s after ui_cpwin, so a small copy shows nothing. See ui.inc.
        .include "horizon.inc"
        .include "ui.inc"
        .import ui_modal_begin, ui_modal_end

CW_W    = 320                           ; the window's content
CW_H    = 104
CW_X    = 12                            ; the left of the labels and the bar
CW_TW   = CW_W - 2 * CW_X               ; their width
CW_BY   = 48                            ; the bar
CW_BH   = 14
CW_IN   = CW_TW - 2                     ; the bar's inside (its bevel is 1 pixel)
CW_DELAY = 500                          ; ms before the window opens
CW_EVMAX = 32                           ; events looked at between two pieces, at most

        .segment "CODE"
        .a16
        .i16

; A = 0 copy, 1 move: the progress window for the next ui_cptree / ui_mvtree (ui_cpcb set
; to cw_cb; the 0.5 s count starts now)
ui_cpwin:
        and     #1
        sta     cw_mode
        stz     cw_open
        stz     cw_cancel
        sys     SYS_UPTIME
        sta     cw_t0
        stx     cw_t0+2
        lda     #.loword(cw_cb)
        sta     ui_cpcb
        rts

; after the copy: the window closed (if it opened), ui_cpcb = 0. Keeps A and the carry.
ui_cpdone:
        php
        pha
        stz     ui_cpcb
        lda     cw_open
        cmp     #1
        bne     :+
        ldx     #.loword(cw_dlg)
        jsr     ui_dlgclose
:       stz     cw_open
        pla
        plp
        rts

; ui_cpcb: called when a file starts and after every piece. C set: cancel
cw_cb:  lda     cw_cancel
        bne     @yes
        lda     cw_open
        bne     @isopen
        sys     SYS_UPTIME              ; not yet open: 0.5 s since ui_cpwin?
        sec
        sbc     cw_t0
        sta     cw_tmp
        txa
        sbc     cw_t0+2
        bne     :+
        lda     cw_tmp
        cmp     #CW_DELAY
        bcc     @no
:       jsr     cw_openwin
        lda     cw_open
@isopen:
        cmp     #1                      ; (2: it could not open: copy on without it)
        bne     @no
        lda     ui_cpk                  ; a file starts: everything again
        bne     :+
        stz     cw_shown
:       jsr     cw_show
        jsr     cw_events
        bcc     @no
        lda     #1
        sta     cw_cancel
@yes:   sec
        rts
@no:    clc
        rts

; the window opened and drawn (cw_open = 1; 2 when it could not open)
cw_openwin:
        lda     #2
        sta     cw_open
        ldx     #.loword(t_copying)
        lda     cw_mode
        beq     :+
        ldx     #.loword(t_moving)
:       stx     cw_dlg + DG_TITLE
        ldx     #.loword(s_cancel)
        jsr     ui_btnw
        sta     cw_btn + CT_W
        eor     #$FFFF
        sec
        adc     #CW_W - CW_X
        sta     cw_btn + CT_X
        lda     #.loword(s_empty)
        sta     cw_lname + LB_TEXT
        lda     #.loword(cw_ptxt)
        sta     cw_lprog + LB_TEXT
        stz     cw_ptxt
        ldx     #.loword(cw_dlg)
        jsr     ui_dlgopen
        bcs     :+
        lda     #1
        sta     cw_open
        stz     cw_shown
:       rts

; the window brought up to date: what changed is drawn (everything when cw_shown = 0)
cw_show:
        lda     cw_dlg + DG_WIN
        sta     z:ui_win
        lda     ui_cpsize               ; total K = (size + 1023) / 1024
        clc
        adc     #1023
        sta     cw_tmp
        lda     ui_cpsize+2
        adc     #0
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        sta     cw_tot
        lda     cw_tmp
        xba
        and     #$00FF
        lsr     a
        lsr     a
        ora     cw_tot
        sta     cw_tot
        lda     ui_cpsize               ; (0.22) the size unknown (a URL): 0
        ora     ui_cpsize+2
        sta     cw_unk
        lda     ui_cpk                  ; done K (at most the total)
        ldx     cw_unk
        beq     :+
        cmp     cw_tot
        bcc     :+
        lda     cw_tot
:       sta     cw_k
        lda     cw_shown
        bne     @text
        lda     ui_cpname               ; a new file: its name, the bar empty
        sta     cw_lname + LB_TEXT
        ldx     #.loword(cw_lname)
        jsr     ui_draw
        lda     #CW_X
        sta     z:ui_x
        lda     #CW_BY
        sta     z:ui_y
        lda     #CW_TW
        sta     z:ui_w
        lda     #CW_BH
        sta     z:ui_h
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     ui_rect
        lda     #1
        jsr     ui_bevel
        stz     cw_bar
        lda     #$FFFF                  ; (the text drawn below)
        sta     cw_lastk
@text:  lda     cw_k
        cmp     cw_lastk
        beq     @bar
        sta     cw_lastk
        ldy     #.loword(cw_ptxt)       ; (0.22) the size unknown: "123 KB"
        lda     cw_unk
        bne     :+
        lda     cw_k
        jsr     cw_dec
        ldx     #.loword(s_kbonly)
        jsr     cw_app
        bra     @draw
:       lda     #100
        jsr     cw_part
        sta     cw_pct
        ldy     #.loword(cw_ptxt)       ; "123 of 1,500 KB (8%)"
        lda     cw_k
        jsr     cw_dec
        ldx     #.loword(s_of)
        jsr     cw_app
        lda     cw_tot
        jsr     cw_dec
        ldx     #.loword(s_kb)
        jsr     cw_app
        lda     cw_pct
        jsr     cw_dec
        ldx     #.loword(s_pct)
        jsr     cw_app
@draw:  ldx     #.loword(cw_lprog)
        jsr     ui_draw
@bar:   lda     cw_unk                  ; (0.22) the size unknown: the bar stays empty
        beq     @done
        lda     #CW_IN                  ; the bar: only the part that changed
        jsr     cw_part
        sta     cw_tmp
        cmp     cw_bar
        beq     @done
        ldx     #WD_FILL | (C_SELECT << 8)
        lda     cw_bar                  ; more: C_SELECT from the old end
        bcs     :+
        ldx     #WD_FILL | (C_WHITE << 8)
        lda     cw_tmp                  ; less: white from the new end
:       stx     cw_op
        clc
        adc     #CW_X + 1
        sta     z:ui_x
        lda     cw_tmp                  ; the width: |new - old|
        sec
        sbc     cw_bar
        bcs     :+
        eor     #$FFFF
        inc     a
:       sta     z:ui_w
        lda     #CW_BY + 1
        sta     z:ui_y
        lda     #CW_BH - 2
        sta     z:ui_h
        lda     cw_dlg + DG_WIN
        sta     z:ui_win
        lda     cw_op
        jsr     ui_rect
        lda     cw_tmp
        sta     cw_bar
@done:  lda     #1
        sta     cw_shown
        rts

; A = scale -> A = cw_k * scale / cw_tot (all of it when the total is 0)
cw_part:
        ldy     cw_tot
        bne     :+
        rts
:       ldx     cw_k
        jmp     ui_muldiv

; the events that came meanwhile, none waited for: the window's go to its button (Esc, a
; click on Cancel, the close box: C set); keys of the program's other windows are the
; dialog's; their other events are dropped (a WE_RESIZE or WE_CLOSE kept for ui_getev)
cw_events:
        lda     #CW_EVMAX
        sta     cw_n
@get:   dec     cw_n
        bmi     @none
        lda     #1                      ; (SYS_WEVENT, not ui_getev: an event put aside
        ptr     ui_ev                   ; would come back at once)
        sys     SYS_WEVENT
        bcs     @none
        lda     ui_ev+1
        and     #$00FF
        cmp     cw_dlg + DG_WIN
        beq     @mine
        lda     ui_ev
        and     #$00FF
        cmp     #WE_KEY
        beq     :+
        jsr     ui_defer_put
        bra     @get
:       sep     #$20
        .a8
        lda     cw_dlg + DG_WIN
        sta     ui_ev+1
        rep     #$20
        .a16
@mine:  lda     ui_ev
        and     #$00FF
        cmp     #WE_CLOSE
        beq     @yes
        ldx     #.loword(cw_list)
        jsr     ui_event
        cmp     #UA_CLICK
        bne     @get
@yes:   sec
        rts
@none:  clc
        rts

; A = number (0-65535) appended at Y in decimal, with a ',' before the hundreds when there
; are thousands ("1,500") -> Y at the terminator
cw_dec: sta     cw_tmp
        stz     cw_any                  ; a digit put already
        ldx     #0
@d:     stz     cw_dig                  ; this digit: how many times cw_pow,x goes in
:       lda     cw_tmp
        cmp     cw_pow,x
        bcc     :+
        sbc     cw_pow,x
        sta     cw_tmp
        inc     cw_dig
        bra     :-
:       lda     cw_dig
        ora     cw_any
        bne     @put
        cpx     #8                      ; (a leading 0 is left out, but not the last digit)
        bne     @skip
@put:   lda     #1
        sta     cw_any
        lda     cw_dig
        clc
        adc     #'0'
        jsr     cw_put
        cpx     #2                      ; the thousands digit: then ','
        bne     @skip
        lda     #','
        jsr     cw_put
@skip:  inx
        inx
        cpx     #10
        bcc     @d
        lda     #0
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        rts

; A = character stored at Y, Y + 1
cw_put: sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        iny
        rts

; X = string appended at Y (zero-terminated) -> Y at its end
cw_app: lda     a:0,x
        and     #$00FF
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        beq     :+
        inx
        iny
        bra     cw_app
:       rts

        .segment "RODATA"
t_copying: .byte "Copying", 0
t_moving: .byte "Moving", 0
s_cancel: .byte "Cancel", 0
s_of:   .byte   " of ", 0
s_kb:   .byte   " KB (", 0
s_pct:  .byte   "%)", 0
s_kbonly: .byte " KB", 0
s_empty: .byte  0
cw_pow: .word   10000, 1000, 100, 10, 1

        .segment "DATA"
cw_dlg: .addr   t_copying               ; DG_TITLE (set when it opens)
        .word   CW_W, CW_H
        .addr   cw_list
        .word   0                       ; DG_WIN
cw_list: .addr  cw_lname, cw_lprog, cw_btn, 0
cw_lname: .byte UT_LABEL, 0
        .word   CW_X, 12, CW_TW, UI_LINE, 0
        .addr   s_empty
cw_lprog: .byte UT_LABEL, 0
        .word   CW_X, 30, CW_TW, UI_LINE, 0
        .addr   s_empty
cw_btn: .byte   UT_BUTTON, 0
        .word   CW_W - CW_X - 64, CW_H - 12 - UI_BTNH, 64, UI_BTNH, UF_CANCEL
        .addr   s_cancel

        .segment "BSS"
cw_mode: .res   2                       ; 0 copy, 1 move
cw_open: .res   2                       ; 0 not yet, 1 open, 2 it could not open
cw_cancel: .res 2                       ; Cancel chosen: every later call says so
cw_shown: .res  2                       ; 0: draw everything at the next cw_show
cw_t0:  .res    4                       ; ms at ui_cpwin
cw_tot: .res    2                       ; the file's K
cw_k:   .res    2                       ; K done (at most cw_tot)
cw_lastk: .res  2                       ; the K the text shows
cw_bar: .res    2                       ; pixels of the bar filled
cw_tmp: .res    2
cw_any: .res    2
cw_dig: .res    2
cw_pct: .res    2
cw_unk: .res    2                       ; (0.22) 0: the size is unknown (ui_cpsize = 0)
cw_op:  .res    2
cw_n:   .res    2
cw_ptxt: .res   32
