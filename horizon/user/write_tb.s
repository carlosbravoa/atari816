; write_tb.s - Write: the toolbar under the title bar (part of write.s), and the Format
; menu's check marks.
;
; Buttons, in groups: Undo, Redo | Bold, Italic, Code | Heading 1, 2, 3, Normal text |
; Bullet list, Numbered list, Quote, Rule. Each shows an icon (wfont.inc: tbi_bm, 16 x 14
; pixels in two inks, made by tools/mkwfont.py) on the window's body: flat; raised under
; the pointer (the window has WF_HOVER: the status line names the button and its key
; then); pressed in, on a pale blue, when its style holds at the cursor; darker while the
; mouse holds it; greyed when it cannot act (Undo, Redo with nothing to take back). A click
; runs the command as the menu does: the cursor and the selection stay (the toolbar takes
; no keyboard focus, and a press there does not touch the text).
;
; The state (tb_calc): the block of the cursor's line (of the selection's first line); the
; inline styles of the character before the cursor (the one after it when the one before
; is a marker), or those all the shown characters of the selection's first line share, or
; the styles armed (write_fmt.s: Bold with no word at the cursor puts "****" in, the
; cursor in the middle: typing there is bold). The Format menu's check marks and Edit's
; Undo / Redo (dimmed) follow the same state.
;
; Drawing: into the row buffer, then one WD_SBLIT: all of it after a full redraw, later
; only the buttons whose look changed (tb_dl: the look drawn).

TBN     = 13                            ; buttons
TBW     = 22                            ; a button's size, its top
TBBH    = 20
TBY     = 2
C_TBON  = 189                           ; a pressed button's face (pale blue: 204, 204, 255)
C_TBDN  = 153                           ;   while the mouse holds it (153, 204, 255)
C_TBGREY = C_TITLE_OFF                  ; the icons' second ink (132, 138, 148)
TL_HOV  = 1                             ; looks: under the pointer, on, held, dimmed
TL_ON   = 2
TL_DOWN = 4
TL_DIM  = 8

        .segment "CODE"

; ---------------------------------------------------------------- the state
; -> tb_st (bit i: button i pressed in), tb_dis (bit i: dimmed)
tb_calc:
        stz     tb_st
        stz     tb_dis
        lda     ub_top                  ; undo, redo
        bne     :+
        lda     #1
        tsb     tb_dis
:       lda     ub_top
        cmp     ub_end
        bcc     :+
        lda     #2
        tsb     tb_dis
:       jsr     selord
        bcs     @sel
        lda     cl                      ; the cursor's line, the cursor
        jsr     tb_blk
        lda     arm_n                   ; armed: those styles
        beq     :+
        lda     arm_bits
        tsb     tb_st
        rts
:       lda     cl
        jsr     lmodel
        lda     cc                      ; the one before (not a marker)
        beq     @at
        clc
        adc     #3
        tay
        lda     [mb],y
        bit     #S_M | S_P
        beq     @bits
@at:    lda     cc                      ; the one after
        cmp     llen
        bcs     @out
        adc     #4
        tay
        lda     [mb],y
        bit     #S_M | S_P
        bne     @out
@bits:  jsr     tb_sbits
        tsb     tb_st
@out:   rts
@sel:   lda     s0l                     ; the selection's first line
        jsr     tb_blk
        lda     s0l
        jsr     lmodel
        lda     #S_B | S_I | S_C        ; the styles all its shown characters have
        sta     z:t0
        stz     z:t1
        lda     llen
        ldx     s0l
        cpx     s1l
        bne     :+
        lda     s1c
:       clc
        adc     #4
        sta     z:t2
        lda     s0c
        clc
        adc     #4
        tay
@c:     cpy     z:t2
        bcs     @e
        lda     [lp],y
        and     #$00FF
        cmp     #' ' + 1
        bcc     @n
        lda     [mb],y
        bit     #S_M | S_P
        bne     @n
        and     z:t0
        sta     z:t0
        inc     z:t1
@n:     iny
        bra     @c
@e:     lda     z:t1
        beq     @out
        lda     z:t0
        bra     @bits

; style byte A -> the bits of its buttons (Bold, Italic, Code)
tb_sbits:
        and     #S_B | S_I | S_C
        sta     z:t3
        lda     #0
        lsr     z:t3
        bcc     :+
        ora     #1 << 2
:       lsr     z:t3
        bcc     :+
        ora     #1 << 3
:       lsr     z:t3
        bcc     :+
        ora     #1 << 4
:       rts

; line A's block -> its button's bit in tb_st
tb_blk: jsr     lget
        jsr     md_block
        ldx     m_blk
        lda     blkbtn,x
        and     #$00FF
        asl     a
        tax
        lda     tbbit,x
        tsb     tb_st
        rts

; ---------------------------------------------------------------- drawing
; the toolbar as the state is now: the buttons whose look changed (all after a full
; redraw); the menus' marks too
tb_update:
        lda     nodraw
        bne     @out
        jsr     tb_calc
        jsr     mn_checks
        lda     tb_ok
        beq     tb_drawall
        ldx     #0
@l:     jsr     tb_look
        cmp     tb_dl,x
        beq     :+
        sta     tb_dl,x
        stx     tb_i
        jsr     tb_btn
        ldx     tb_i
:       inx
        inx
        cpx     #TBN * 2
        bcc     @l
@out:   rts

; button X (* 2) -> A = its look (TL_*)
tb_look:
        lda     tbbit,x
        and     tb_dis
        beq     :+
        lda     #TL_DIM
        rts
:       stz     z:t0
        lda     tbbit,x
        and     tb_st
        beq     :+
        lda     #TL_ON
        sta     z:t0
:       txa
        lsr     a
        cmp     tb_hov
        bne     :+
        lda     #TL_HOV
        tsb     z:t0
        txa
        lsr     a
        cmp     tb_prs
        bne     :+
        lda     #TL_DOWN
        tsb     z:t0
:       lda     z:t0
        rts

; the whole toolbar
tb_drawall:
        lda     #1
        sta     tb_ok
        stz     z:qx                    ; its body, a light line at the top, a line under it
        stz     z:qy
        lda     cw
        sta     z:qw
        lda     #TBH - 1
        sta     z:qh
        lda     #C_BODY
        jsr     bfill
        lda     #1
        sta     z:qh
        lda     #C_WHITE
        jsr     bfill
        lda     #TBH - 1
        sta     z:qy
        lda     #C_MID
        jsr     bfill
        ldx     #0                      ; the lines between the groups
@s:     lda     tbsep,x
        beq     :+
        phx
        sta     z:qx
        lda     #TBY + 3
        sta     z:qy
        lda     #TBBH - 6
        sta     z:qh
        lda     #1
        sta     z:qw
        lda     #C_MID
        jsr     bfill
        inc     z:qx
        lda     #C_WHITE
        jsr     bfill
        plx
        inx
        inx
        bra     @s
:       ldx     #0                      ; the buttons
@b:     jsr     tb_look
        sta     tb_dl,x
        stx     tb_i
        jsr     tb_render
        ldx     tb_i
        inx
        inx
        cpx     #TBN * 2
        bcc     @b
        stz     z:qx
        stz     z:qy
        lda     cw
        sta     z:qw
        lda     #TBH
        sta     z:qh
        jmp     tb_blit

; button tb_i drawn and blitted
tb_btn: ldx     tb_i
        jsr     tb_render
        ldx     tb_i
        lda     tbx,x
        sta     z:qx
        lda     #TBY
        sta     z:qy
        lda     #TBW
        sta     z:qw
        lda     #TBBH
        sta     z:qh
        ; fall through
; the row buffer's qx, qy, qw x qh -> the window at the same place
tb_blit:
        lda     z:qx
        sta     bl_x
        lda     z:qy
        sta     bl_y
        xba
        and     #$FF00
        asl     a
        asl     a
        clc
        adc     z:qx
        adc     #RBOFF
        sta     bl_p
        lda     z:qw
        sta     bl_w
        lda     z:qh
        sta     bl_h
        sep     #$20
        .a8
        lda     rbank
        sta     bl_p+2
        rep     #$20
        .a16
        lda     win
        ptr     bl_blk
        sys     SYS_WDRAW
        rts

; button X (* 2) into the row buffer, as its look tb_dl
tb_render:
        lda     tbx,x
        sta     tb_x
        sta     z:qx
        lda     tb_dl,x
        sta     tb_lk
        txa                             ; its icon
        lsr     a
        sta     z:t0
        asl     a                       ; * 56
        asl     a
        asl     a
        sta     z:t1
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:t1
        clc
        adc     #.loword(tbi_bm)
        sta     tb_ic
        lda     #TBY                    ; the face
        sta     z:qy
        lda     #TBW
        sta     z:qw
        lda     #TBBH
        sta     z:qh
        ldy     #C_BODY
        lda     tb_lk
        bit     #TL_DOWN
        beq     :+
        ldy     #C_TBDN
        bra     :++
:       bit     #TL_ON
        beq     :+
        ldy     #C_TBON
:       tya
        jsr     bfill
        lda     tb_lk                   ; the edges: pressed in, raised, none
        bit     #TL_ON | TL_DOWN
        beq     :+
        lda     #C_MID
        ldx     #C_WHITE
        bra     @edge
:       bit     #TL_HOV
        beq     @icon
        lda     #C_WHITE
        ldx     #C_MID
@edge:  sta     tb_c1
        stx     tb_c2
        lda     #1                      ; top, left
        sta     z:qh
        lda     tb_c1
        jsr     bfill
        lda     #TBBH
        sta     z:qh
        lda     #1
        sta     z:qw
        lda     tb_c1
        jsr     bfill
        lda     tb_x                    ; right, bottom
        clc
        adc     #TBW - 1
        sta     z:qx
        lda     tb_c2
        jsr     bfill
        lda     tb_x
        sta     z:qx
        lda     #TBY + TBBH - 1
        sta     z:qy
        lda     #TBW
        sta     z:qw
        lda     #1
        sta     z:qh
        lda     tb_c2
        jsr     bfill
@icon:  lda     tb_x                    ; the icon (held: a pixel right and down)
        clc
        adc     #3
        sta     tb_ix
        lda     #TBY + 3
        sta     pg_y
        lda     tb_lk
        and     #TL_DOWN
        beq     :+
        inc     tb_ix
        inc     pg_y
:       lda     tb_lk                   ; its inks
        and     #TL_DIM
        beq     :+
        lda     #C_MID
        sta     tb_k1
        lda     #C_LIGHT
        sta     tb_k2
        bra     :++
:       lda     #C_BLACK
        sta     tb_k1
        lda     #C_TBGREY
        sta     tb_k2
:       stz     pg_it
        lda     #TBI_ROWS
        sta     tb_n
@r:     lda     tb_k1                   ; a row: the ink's two bytes, the grey's
        sta     pg_ink
        ldy     #0
        jsr     @two
        lda     tb_k2
        sta     pg_ink
        ldy     #2
        jsr     @two
        lda     tb_ic
        clc
        adc     #4
        sta     tb_ic
        inc     pg_y
        dec     tb_n
        bne     @r
        rts
@two:   lda     tb_ix                   ; bytes Y, Y + 1 of the row
        sta     pg_x
        jsr     @one
        lda     tb_ix
        clc
        adc     #8
        sta     pg_x
        iny
@one:   phy
        tya
        clc
        adc     tb_ic
        tax
        lda     a:0,x
        and     #$00FF
        sta     z:t1
        jsr     plotb
        ply
        rts

; ---------------------------------------------------------------- the mouse
; button under the pointer (ui_ev a, b) -> A (NONE: none)
tb_hit: lda     ui_ev+4
        cmp     #TBY
        bmi     @no
        cmp     #TBY + TBBH
        bpl     @no
        ldx     #0
:       lda     ui_ev+2
        sec
        sbc     tbx,x
        bmi     @nx
        cmp     #TBW
        bcc     @yes
@nx:    inx
        inx
        cpx     #TBN * 2
        bcc     :-
@no:    lda     #NONE
        rts
@yes:   txa
        lsr     a
        rts

; the pointer moved (no button held, or one held after a press on the toolbar)
tb_hover:
        jsr     tb_hit
; A = the button under the pointer now: drawn raised, named on the status line
tb_sethov:
        cmp     tb_hov
        beq     @out
        sta     tb_hov
        lda     nodraw
        bne     @out
        jsr     tb_update
        jsr     stupdate
@out:   rts

; a press on the toolbar: the button held (not one dimmed)
tb_press:
        jsr     tb_hit
        cmp     #NONE
        jeq     loop
        sta     tb_hov
        asl     a
        tax
        lda     tbbit,x
        and     tb_dis
        jne     loop
        txa
        lsr     a
        sta     tb_prs
        jsr     tb_update
        jmp     loop

; a release: on the button pressed, its command (as the menu's)
tb_release:
        lda     tb_prs
        cmp     #NONE
        jeq     loop
        sta     tb_cmd
        lda     #NONE
        sta     tb_prs
        jsr     tb_hit
        sta     tb_hov
        cmp     tb_cmd
        beq     :+
        jsr     tb_update
        jmp     loop
:       jsr     tb_update
        jsr     snap
        lda     tb_cmd
        asl     a
        tax
        jmp     (tbcmd,x)

; the pointer left the window
onleave:
        lda     #NONE
        jsr     tb_sethov
        jmp     loop

; ---------------------------------------------------------------- the menus' marks
; Format's check marks, Edit's Undo / Redo dimmed: the items whose state changed
mn_checks:
        lda     tb_st
        eor     mn_st
        sta     z:t2
        lda     tb_dis
        eor     mn_dis
        tsb     z:t2
        lda     tb_st
        sta     mn_st
        lda     tb_dis
        sta     mn_dis
        lda     z:t2
        beq     @out
        ldx     #0
@l:     lda     tbbit,x
        and     z:t2
        beq     @n
        lda     mn_short
        beq     :+
        lda     tbmenu_s,x
        bra     :++
:       lda     tbmenu,x
:       cmp     #NONE
        beq     @n
        sta     z:t4
        ldy     #0
        lda     tbbit,x
        and     tb_st
        beq     :+
        ldy     #MS_CHECK
:       lda     tbbit,x
        and     tb_dis
        beq     :+
        ldy     #MS_DIM
:       phx
        ldx     z:t4
        lda     win
        sys     SYS_WMSTATE
        plx
@n:     inx
        inx
        cpx     #TBN * 2
        bcc     @l
@out:   rts

        .segment "RODATA"
tbbit:  .word   1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096
tbx:    .word   6, 30, 62, 86, 110, 142, 166, 190, 214, 246, 270, 294, 318
tbsep:  .word   57, 137, 241, 0
tbcmd:  .addr   m_undo, m_redo, f_bold, f_ital, f_code, f_h1, f_h2, f_h3, f_norm
        .addr   f_bul, f_num, f_quote, f_rule
; a block -> its button
blkbtn: .byte   8, 5, 6, 7, 9, 10, 11, 12, 8
; each button's menu item (menu | item << 8; NONE: none): the long menus, the short
tbmenu: .word   1, 1 | (1 << 8), 3, 3 | (1 << 8), 3 | (2 << 8), 3 | (4 << 8), 3 | (5 << 8)
        .word   3 | (6 << 8), 3 | (7 << 8), 3 | (9 << 8), 3 | (10 << 8), 3 | (11 << 8)
        .word   3 | (12 << 8)
tbmenu_s: .word NONE, NONE, NONE, NONE, NONE, NONE, NONE, NONE, NONE, NONE, NONE, NONE, NONE
; the status line's text for each
tbhint: .addr   th_undo, th_redo, th_bold, th_ital, th_code, th_h1, th_h2, th_h3, th_norm
        .addr   th_bul, th_num, th_quo, th_rule
th_undo: .byte  "Undo (Ctrl+Z)", 0
th_redo: .byte  "Redo (Ctrl+Y)", 0
th_bold: .byte  "Bold (Ctrl+B)", 0
th_ital: .byte  "Italic (Ctrl+I)", 0
th_code: .byte  "Code (Ctrl+E)", 0
th_h1:  .byte   "Heading 1 (Ctrl+1)", 0
th_h2:  .byte   "Heading 2 (Ctrl+2)", 0
th_h3:  .byte   "Heading 3 (Ctrl+3)", 0
th_norm: .byte  "Normal text (Ctrl+0)", 0
th_bul: .byte   "Bullet list (Ctrl+8)", 0
th_num: .byte   "Numbered list (Ctrl+7)", 0
th_quo: .byte   "Quote (Ctrl+9)", 0
th_rule: .byte  "Rule, a line across (Ctrl+-)", 0

        .segment "DATA"
tb_hov: .word   NONE                    ; the button under the pointer, held
tb_prs: .word   NONE

        .segment "BSS"
tb_ok:  .res    2                       ; the toolbar is drawn
tb_st:  .res    2                       ; the state (bit i: button i)
tb_dis: .res    2
tb_dl:  .res    TBN * 2                 ; the look drawn
tb_i:   .res    2
tb_cmd: .res    2                       ; the button released on
tb_x:   .res    2
tb_lk:  .res    2
tb_ic:  .res    2
tb_ix:  .res    2
tb_n:   .res    2
tb_c1:  .res    2
tb_c2:  .res    2
tb_k1:  .res    2
tb_k2:  .res    2
mn_st:  .res    2                       ; the menus' marks as set
mn_dis: .res    2
mn_short: .res  2                       ; 1: the short menus (a kernel keeping 254 bytes)
