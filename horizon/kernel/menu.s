; menu.s - the menu bar and its drop-down menus (window system, stage 2).
;
; The bar is a kernel overlay window across the top of the screen. It shows the menus of
; the backdrop window (the Desktop's system menu) and then those of the focused window,
; and a status text at the right (ws_status: the Desktop's clock). Menus are given with
; win_menu as strings: a title, its items, "" - and "" after the last menu. An item that
; starts with '-' is a separator. A press on a title opens the menu; releasing on an item
; picks it (WE_MENU to the menu's window: a = menu, b = item); releasing on the title
; keeps the menu open until the next click.
;
; 0.13: an item may start with a state byte MS_STATE | bits ($10-$13: MS_CHECK a check
; mark in the left margin, MS_DIM greyed and not selectable; set with win_mstate) and may
; hold a TAB: the text after it (a shortcut, "Ctrl+S") is drawn right-aligned. Keyboard
; menus (F10, Alt alone, Alt+letter; the keys while a menu is open): mn_key.

MB_MAX  = 12                            ; menus shown at most
MS_STATE = $10                          ; an item's state byte: MS_STATE | MS_CHECK | MS_DIM
MS_CHECK = 1
MS_DIM   = 2
ITEM_H  = 14

; ---- the bar window, at ws_start ----
bar_make:
        jsr     win_find
        bcs     @out
        stx     kg_e
        lda     #WF_OVER | WF_PLAIN
        sta     w_fl,x
        stz     kg_x
        stz     kg_y
        lda     #SCR_W
        sta     kg_w
        lda     #MENU_H
        sta     kg_h
        jsr     win_geom
        jsr     win_make
        bcs     @out
        ldx     kg_e
        lda     #NONE
        sta     w_owner,x
        stx     mb_w
        jmp     bar_draw
@out:   rts

; X = window*2 -> kg_ln = its menu strings (the menu bank + window * MENU_SZ)
menu_ptr:
        txa
        xba
        asl     a
        asl     a                       ; window*2 * 1024 = window * MENU_SZ
        sta     kg_ln
mb_bank:
        lda     ws_mbank
        sta     kg_ln+2
        rts

; kg_ln: skip one zero-terminated string
str_skip:
        ldy     #0
:       lda     [kg_ln],y
        iny
        and     #$00FF
        bne     :-
        tya
        clc
        adc     kg_ln
        sta     kg_ln
        rts

; ---- redraw the bar: the menu titles (the open one highlighted) and the status ----
bar_draw:
        ldx     mb_w
        bpl     :+
        rts
:       jsr     win_surf
        jsr     win_clip_all
        stz     kg_x                    ; background and the line under it
        stz     kg_y
        lda     #SCR_W
        sta     kg_w
        lda     #MENU_H - 1
        sta     kg_h
        lda     #C_BODY
        sta     kg_fg
        jsr     gfx_rect
        stz     kg_x
        lda     #MENU_H - 1
        sta     kg_y
        lda     #SCR_W
        sta     kg_w
        lda     #1
        sta     kg_h
        lda     #C_BLACK
        sta     kg_fg
        jsr     gfx_rect
        stz     mb_n
        lda     #8
        sta     mb_x
        ldx     #NONE                   ; the backdrop's menus, then the focus's
        lda     z_n
        beq     :+
        ldx     z_list
        lda     w_fl,x
        bit     #WF_BACK
        bne     :+
        ldx     #NONE
:       stx     mb_back
        stz     mb_nx
        stz     mb_sys
        cpx     #NONE
        beq     @prog
        jsr     bar_menus               ; the system menus: the backdrop's, then Windows
        lda     mb_n                    ; (none: no Windows menu, no name either)
        beq     @prog
        sta     mb_sys
        lda     #MB_WMENU
        sta     kg_ln
        jsr     mb_bank
        lda     #WMENU_W
        jsr     bar_list
@prog:  ldx     ws_top                  ; the focused program: (after the system menus a
        cpx     #NONE                   ; divider and its name in bold) its menus
        beq     @stat
        cpx     mb_back
        beq     @stat
        lda     mb_sys
        beq     :+
        jsr     bar_name
:       ldx     ws_top
        jsr     bar_menus
@stat:  lda     #.loword(ws_stat)       ; the status text, right-aligned
        sta     kg_ln
        lda     #KBANK
        sta     kg_ln+2
        lda     #0
        jsr     text_width
        eor     #$FFFF
        sec
        adc     #SCR_W - 8
        sta     kg_x
        sta     mb_sx
        lda     #2
        sta     kg_y
        stz     kg_i
        lda     #C_BLACK
        sta     kg_fg
        lda     #$FF
        sta     kg_bg
        ldx     mb_w
        jsr     win_surf
        jsr     win_clip_all
        jsr     gfx_text
        ldx     mb_w
        jmp     win_damage

; (0.14) after the system menus: a thin divider, then the name of window X's program in
; bold (drawn twice, one pixel apart); mb_x moves past it
bar_name:
        jsr     app_name                ; -> mb_name
        ldx     mb_w
        jsr     win_surf
        jsr     win_clip_all
        lda     mb_x                    ; the divider
        clc
        adc     #4
        sta     kg_x
        lda     #3
        sta     kg_y
        lda     #1
        sta     kg_w
        lda     #MENU_H - 6
        sta     kg_h
        lda     #C_MID
        sta     kg_fg
        jsr     gfx_rect
        lda     mb_x
        clc
        adc     #16
        sta     mb_nx
        lda     #.loword(mb_name)
        sta     kg_ln
        lda     #KBANK
        sta     kg_ln+2
        lda     #2
        sta     kg_y
        stz     kg_i
        lda     #C_BLACK
        sta     kg_fg
        lda     #$FF
        sta     kg_bg
        lda     mb_nx
        sta     kg_x
        jsr     gfx_text
        lda     mb_nx
        inc     a
        sta     kg_x
        jsr     gfx_text
        lda     mb_nx                   ; (gfx_text left the width in kg_dx)
        clc
        adc     kg_dx
        inc     a
        sta     mb_nx1
        clc
        adc     #8
        sta     mb_x
        rts

; window X's program name -> mb_name (bank 1): its task_name, else the program's file
; name with only its first letter capital ("EDIT" -> "Edit")
app_name:
        lda     w_owner,x
; (0.15) the same for the task in slot A (slot*2)
app_nslot:
        cmp     #NSLOT * 2
        bcc     :+
        stz     mb_name
        rts
:       pha
        asl     a
        asl     a
        asl     a
        tax                             ; slot * 16
        ldy     #0
        lda     t_dname,x
        and     #$00FF
        beq     @file
        a8
:       lda     t_dname,x
        sta     mb_name,y
        beq     :+
        inx
        iny
        cpy     #15
        bne     :-
        lda     #0
        sta     mb_name,y
:       a16
        pla
        rts
@file:  pla                             ; slot * 8: t_name
        asl     a
        asl     a
        tax
        a8
:       lda     t_name,x
        cmp     #' '
        beq     :++
        cpy     #0
        beq     :+
        cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        ora     #$20
:       sta     mb_name,y
        inx
        iny
        cpy     #8
        bne     :--
:       lda     #0
        sta     mb_name,y
        a16
        rts

; the menus of window X into the bar
bar_menus:
        stx     mb_src
        jsr     menu_ptr
        txa
; the menus at kg_ln (window A's: the bar entries' mb_win) into the bar
bar_list:
        sta     mb_src
        stz     mb_m
@menu:  lda     [kg_ln]
        and     #$00FF
        bne     :+
        rts
:       lda     mb_n
        cmp     #MB_MAX
        bcc     :+
        rts
:       asl     a
        tax
        lda     mb_src
        sta     mb_win,x
        lda     mb_m
        sta     mb_idx,x
        lda     kg_ln
        sta     mb_off,x
        lda     mb_x
        sta     mb_x0,x
        lda     #0                      ; width + 16
        jsr     text_width
        clc
        adc     #16
        clc
        adc     mb_x
        ldx     mb_n
        txa
        asl     a
        tax
        lda     mb_x
        clc
        adc     kg_t                    ; (text_width left the width in kg_t)
        adc     #16
        sta     mb_x1,x
        sta     mb_x
        lda     mb_x0,x                 ; draw the title (highlighted when open)
        sta     kg_x
        lda     kg_ln
        pha
        lda     #C_BLACK
        sta     kg_fg
        lda     #$FF
        sta     kg_bg
        lda     mb_n
        cmp     mn_open
        bne     :+
        lda     #C_WHITE
        sta     kg_fg
        lda     #C_TITLE
        sta     kg_bg
:       ldx     mb_w
        jsr     win_surf
        jsr     win_clip_all
        lda     kg_bg                   ; an open title: the whole box
        and     #$00FF
        cmp     #$FF
        beq     :+
        lda     kg_fg
        pha
        lda     kg_bg
        sta     kg_fg
        ldx     mb_n
        txa
        asl     a
        tax
        lda     mb_x1,x
        sec
        sbc     mb_x0,x
        sta     kg_w
        stz     kg_y
        lda     #MENU_H - 1
        sta     kg_h
        jsr     gfx_rect
        pla
        sta     kg_fg
        ldx     mb_n
        txa
        asl     a
        tax
        lda     mb_x0,x
        sta     kg_x
        lda     #$FF
        sta     kg_bg
:       lda     kg_x
        clc
        adc     #8
        sta     kg_x
        lda     #2
        sta     kg_y
        stz     kg_i
        pla
        sta     kg_ln
        pha
        jsr     gfx_text
        pla
        sta     kg_ln
        jsr     str_skip                ; past the title and the items
:       lda     [kg_ln]
        and     #$00FF
        beq     :+
        jsr     str_skip
        bra     :-
:       inc     kg_ln                   ; past the ""
        inc     mb_n
        inc     mb_m
        jmp     @menu

; ---- a press on the bar (wm_x): open the menu there ----
mn_press:
        jsr     mn_at
        bcs     :+
        stz     mn_sticky
        jmp     mn_show
:       lda     wm_x                    ; (0.14) the status text: WE_STATUS to the backdrop
        cmp     mb_sx
        bcc     :+
        ldx     mb_back
        bmi     :+
        lda     #WE_STATUS
        jmp     wev_push0
:       rts

; C clear: A = the bar entry at (wm_x, wm_y)
mn_at:  lda     wm_y
        cmp     #MENU_H
        bcs     @no
        ldx     #0
:       txa
        lsr     a
        cmp     mb_n
        bcs     @no
        lda     wm_x
        cmp     mb_x0,x
        bcc     @nx
        cmp     mb_x1,x
        bcs     @nx
        txa
        lsr     a
        clc
        rts
@nx:    inx
        inx
        bra     :-
@no:    sec
        rts

; open bar entry A's drop-down (closing another one)
mn_show:
        pha
        jsr     mn_drop
        pla
        sta     mn_open
        lda     #NONE
        sta     mn_sel
        jsr     bar_draw
        lda     mn_open                 ; its items: count and widest
        asl     a
        tax
        lda     mb_win,x                ; (the Windows menu: made now)
        cmp     #WMENU_W
        bne     :+
        phx
        jsr     wl_build
        plx
        bra     @items
:       phx                             ; (0.14) a backdrop's menu: WE_MENUOPEN to it
        lda     mn_noev
        bne     :+
        lda     mb_idx,x
        sta     kg_t
        lda     mb_win,x
        tax
        lda     w_fl,x
        bit     #WF_BACK
        beq     :+
        stz     kg_u
        lda     #WE_MENUOPEN
        sta     kg_v
        lda     #0
        jsr     wev_push
:       plx
@items: lda     mb_off,x
        sta     kg_ln
        jsr     mb_bank
        jsr     str_skip
        lda     kg_ln
        sta     mn_items
        stz     mn_n
        lda     #40
        sta     mn_wd
:       lda     [kg_ln]
        and     #$00FF
        beq     :+++
        lda     kg_ln
        pha
        jsr     item_split              ; label (+ 16 + shortcut)
        lda     #0
        jsr     text_width
        ldx     it_tab
        beq     :+
        pha
        inx
        stx     kg_ln
        lda     #0
        jsr     text_width
        clc
        adc     #16
        adc     1,s
        sta     1,s
        pla
:       cmp     mn_wd
        bcc     :+
        sta     mn_wd
:       jsr     item_join
        pla
        sta     kg_ln
        inc     mn_n
        jsr     str_skip
        bra     :---
:       lda     mn_n
        bne     :+
        rts                             ; (a menu without items: only the title)
:       jsr     win_find
        bcs     @out
        stx     kg_e
        stx     dd_w
        lda     #WF_OVER | WF_PLAIN
        sta     w_fl,x
        lda     mn_open
        asl     a
        tax
        lda     mb_x0,x
        sta     kg_x
        lda     #MENU_H - 1
        sta     kg_y
        lda     mn_wd
        clc
        adc     #24
        sta     kg_w
        lda     mn_n                    ; items * 14 + 4
        asl     a
        sta     kg_t
        asl     a
        asl     a
        asl     a
        sec
        sbc     kg_t
        clc
        adc     #4
        sta     kg_h
        lda     mn_open                 ; (0.15) a pop-up menu: beside its point
        cmp     #MB_POP
        bne     :+
        jsr     pop_place
:       ldx     kg_e
        jsr     win_geom
        jsr     win_make
        bcc     :+
        lda     #NONE
        sta     dd_w
        rts
:       ldx     dd_w
        lda     #NONE
        sta     w_owner,x
        jmp     dd_draw
@out:   rts

; draw the open drop-down: frame, items, the selected one highlighted
dd_draw:
        ldx     dd_w
        bpl     :+
        rts
:       jsr     win_surf
        jsr     win_clip_all
        ldx     dd_w
        stz     kg_x
        stz     kg_y
        lda     w_w,x
        sta     kg_w
        lda     w_h,x
        sta     kg_h
        lda     #C_BLACK
        sta     kg_fg
        jsr     gfx_frame
        lda     mn_items
        sta     kg_ln
        jsr     mb_bank
        stz     mn_i
@it:    lda     mn_i
        cmp     mn_n
        jcs     @done
        asl     a                       ; y = 2 + 14 i
        sta     kg_t
        asl     a
        asl     a
        asl     a
        sec
        sbc     kg_t
        clc
        adc     #2
        sta     mn_y
        ldx     dd_w                    ; the item's background
        lda     #1
        sta     kg_x
        lda     mn_y
        sta     kg_y
        lda     w_w,x
        dec     a
        dec     a
        sta     kg_w
        lda     #ITEM_H
        sta     kg_h
        lda     #C_BODY
        ldx     mn_i
        cpx     mn_sel
        bne     :+
        lda     #C_TITLE
:       sta     kg_fg
        jsr     gfx_rect
        lda     [kg_ln]
        and     #$00FF
        cmp     #'-'
        bne     @txt
        ldx     dd_w                    ; a separator
        lda     #4
        sta     kg_x
        lda     mn_y
        clc
        adc     #ITEM_H / 2
        sta     kg_y
        lda     w_w,x
        sec
        sbc     #8
        sta     kg_w
        lda     #1
        sta     kg_h
        lda     #C_MID
        sta     kg_fg
        jsr     gfx_rect
        bra     @nx
@txt:   lda     kg_ln
        pha
        jsr     item_split
        lda     #C_BLACK
        ldx     mn_i
        cpx     mn_sel
        bne     :+
        lda     #C_WHITE
:       ldx     it_st                   ; dimmed: grey
        cpx     #MS_STATE | MS_DIM
        bcc     :+
        lda     #C_MID
:       sta     kg_fg
        lda     #12                     ; the label
        jsr     dd_text
        ldx     it_tab                  ; the shortcut, right-aligned
        beq     :+
        inx
        stx     kg_ln
        lda     #0
        jsr     text_width
        eor     #$FFFF
        sec
        ldx     dd_w
        adc     w_w,x
        sec
        sbc     #12
        jsr     dd_text
:       lda     it_st                   ; the check mark
        and     #MS_CHECK
        beq     :+
        jsr     dd_check
:       jsr     item_join
        pla
        sta     kg_ln
@nx:    jsr     str_skip
        inc     mn_i
        jmp     @it
@done:  ldx     dd_w
        jmp     win_damage

; the item text at [kg_ln] at x = A on the row mn_y, ink kg_fg
dd_text:
        sta     kg_x
        lda     mn_y
        clc
        adc     #2
        sta     kg_y
        stz     kg_i
        lda     #$FF
        sta     kg_bg
        jmp     gfx_text

; a check mark in the left margin of the row mn_y, in kg_fg: lines x0, y0, x1, y1
dd_check:
        ldy     #0
:       lda     ck_tab,y
        and     #$00FF
        sta     kg_x
        lda     ck_tab+2,y
        and     #$00FF
        sta     kg_w
        lda     ck_tab+1,y
        jsr     @y
        sta     kg_y
        lda     ck_tab+3,y
        jsr     @y
        sta     kg_h
        phy
        jsr     gfx_line
        ply
        iny
        iny
        iny
        iny
        cpy     #16
        bne     :-
        rts
@y:     and     #$00FF
        clc
        adc     mn_y
        rts
ck_tab: .byte   1, 7, 3, 9,  1, 8, 3, 10,  3, 9, 8, 4,  3, 10, 8, 5

; kg_ln = an item: it_st = its state byte (0: none), kg_ln past it; a TAB in it becomes
; the end of the label (it_tab = its address, 0: none) until item_join puts it back
item_split:
        stz     it_st
        stz     it_tab
        lda     [kg_ln]
        and     #$00FC
        cmp     #MS_STATE
        bne     :+
        lda     [kg_ln]
        and     #$00FF
        sta     it_st
        inc     kg_ln
:       ldy     #0
@c:     lda     [kg_ln],y
        and     #$00FF
        beq     @out
        iny
        cmp     #9
        bne     @c
        tya
        clc
        adc     kg_ln
        dec     a
        sta     it_tab
        sta     km_p
        lda     kg_ln+2
        sta     km_p+2
        a8
        lda     #0
        sta     [km_p]
        a16
@out:   rts

item_join:
        lda     it_tab
        beq     :+
        sta     km_p
        a8
        lda     #9
        sta     [km_p]
        a16
:       rts

; A = item index -> kg_ln = the item
it_at:  tay
        lda     mn_items
        sta     kg_ln
        jsr     mb_bank
:       dey
        bmi     :+
        phy
        jsr     str_skip
        ply
        bra     :-
:       rts

; kg_ln = an item: C set if it cannot be chosen (a separator, dimmed)
it_bad: lda     [kg_ln]
        and     #$00FF
        cmp     #'-'
        beq     :+
        eor     #MS_STATE | MS_DIM
        cmp     #2
        bcs     :++
:       sec
        rts
:       clc
        rts

; close the drop-down window (if any); mn_open stays
mn_drop:
        ldx     dd_w
        bmi     :+
        lda     #NONE
        sta     dd_w
        jsr     win_close
        stz     mn_kill                 ; (mn_closed took it for a menu's window)
:       lda     mn_open                 ; (0.15) a pop-up menu: its caller goes on
        cmp     #MB_POP
        bne     :+
        jmp     pop_end
:       rts

; close the open menu
mn_close:
        jsr     mn_drop
        lda     #NONE
        sta     mn_open
        stz     mn_kill
        jmp     bar_draw

; (win_close) window kg_e closes: if its menu is open, close it soon (in the thread)
mn_closed:
        lda     mn_open
        bmi     :+
        lda     kg_e
        cmp     dd_w
        beq     :+
        lda     #1
        sta     mn_kill
:       rts

; the item under the pointer (ms_x, ms_y) -> A (NONE: none, a separator, dimmed)
mn_item:
        ldx     dd_w
        bmi     @no
        lda     ms_x
        sec
        sbc     w_x,x
        bcc     @no
        cmp     w_w,x
        bcs     @no
        lda     ms_y
        sec
        sbc     w_y,x
        sec
        sbc     #2
        bcc     @no
        ldy     #0                      ; / 14
:       cmp     #ITEM_H
        bcc     :+
        sbc     #ITEM_H
        iny
        bra     :-
:       cpy     mn_n
        bcs     @no
        sty     mn_i                    ; a separator, dimmed?
        tya
        jsr     it_at
        jsr     it_bad
        bcs     @no
        lda     mn_i
        rts
@no:    lda     #NONE
        rts

; the pointer moved while a menu is open: follow it
mn_track:
        lda     ms_x
        sta     mn_lx
        lda     ms_y
        sta     mn_ly
        sta     wm_y
        lda     ms_x
        sta     wm_x
        lda     mn_open                 ; (0.15: not from a pop-up menu)
        cmp     #MB_POP
        beq     :+
        jsr     mn_at                   ; over another title: that menu
        bcs     :+
        cmp     mn_open
        beq     :+
        jmp     mn_show
:       jsr     mn_item
        cmp     mn_sel
        beq     :+
        sta     mn_sel
        jmp     dd_draw
:       rts

; a button change while a menu is open (kg_e = buttons, wm_x, wm_y)
mn_button:
        lda     mn_open                 ; (0.15) a pop-up menu: any button (ws15.s)
        cmp     #MB_POP
        bne     :+
        jmp     pop_button
:       lda     kg_e
        and     #1
        beq     @up
        lda     wm_btn                  ; a press (the menu stayed open): on an item it
        and     #1                      ; is picked at the release
        bne     @out
        jsr     mn_at
        bcs     :+
        cmp     mn_open                 ; the open title again: close
        jeq     mn_close
        stz     mn_sticky
        jmp     mn_show
:       lda     ms_x
        pha
        lda     ms_y
        pha
        lda     wm_x
        sta     ms_x
        lda     wm_y
        sta     ms_y
        jsr     mn_item
        tax
        pla
        sta     ms_y
        pla
        sta     ms_x
        cpx     #NONE
        jeq     mn_close                ; elsewhere: close (the click is used up)
        stx     mn_sel
        lda     #2                      ; picking
        sta     mn_sticky
@out:   rts
@up:    lda     wm_btn                  ; a release
        and     #1
        beq     @out
        lda     ms_x
        pha
        lda     ms_y
        pha
        lda     wm_x
        sta     ms_x
        lda     wm_y
        sta     ms_y
        jsr     mn_item
        tax
        pla
        sta     ms_y
        pla
        sta     ms_x
        cpx     #NONE
        bne     mn_pick
        lda     mn_sticky               ; released on the title after the opening
        bne     :+                      ; press: stay open
        jsr     mn_at
        bcs     :+
        cmp     mn_open
        bne     :+
        lda     #1
        sta     mn_sticky
        rts
:       jmp     mn_close
; X = item of the open menu: chosen (WE_MENU: a = menu, b = item)
mn_pick:
        lda     mn_open                 ; (0.15) a pop-up menu: the answer to its caller
        cmp     #MB_POP
        bne     :+
        stx     pop_res
        jmp     mn_close
:       phx
        lda     mn_open
        asl     a
        tax
        lda     mb_idx,x
        pha
        lda     mb_win,x
        pha
        jsr     mn_close                ; (redraws the bar: kg_* change)
        plx
        pla
        sta     kg_t
        pla
        sta     kg_u
        cpx     #WMENU_W                ; the Windows menu: that window comes up
        bne     :+
        jmp     wl_pick
:       lda     w_used,x
        beq     :+
        lda     #WE_MENU
        sta     kg_v
        lda     #0
        jmp     wev_push
:       rts

;---- keyboard menus
; a key down while a menu is open (A = usage): Esc closes, Left / Right the previous /
; next menu, Up / Down / Home / End move, Enter chooses, a letter: the next item with it
mn_krts:
        rts
mn_key: cmp     #$29
        bne     :+
        jmp     mn_close
:       ldx     mn_open                 ; (0.15: a pop-up menu has no neighbours)
        cpx     #MB_POP
        bne     :+
        cmp     #$4F
        beq     mn_krts
        cmp     #$50
        beq     mn_krts
:       cmp     #$4F
        bne     :++
        lda     mn_open
        inc     a
        cmp     mb_n
        bcc     :+
        lda     #0
:       bra     mn_kopen
:       cmp     #$50
        bne     :++
        lda     mn_open
        dec     a
        bpl     :+
        lda     mb_n
        dec     a
:       bra     mn_kopen
:       cmp     #$4A
        beq     mn_home
        cmp     #$51
        bne     :+
        lda     mn_sel
        bra     mn_down
:       cmp     #$4D
        bne     :+
        lda     mn_n
        bra     mn_up
:       cmp     #$52
        bne     :+
        lda     mn_sel
mn_up:  ldy     #$FFFF
        bra     mn_sel0
:       cmp     #$28                    ; Enter (and the keypad's)
        beq     :+
        cmp     #$58
        bne     :++
:       ldx     mn_sel
        bmi     @out
        jmp     mn_pick
:       sec                             ; a letter
        sbc     #4
        cmp     #26
        bcs     @out
        adc     #'A'
        sta     kt3
        lda     mn_sel
        ldy     #1
        bra     mn_step
@out:   rts

; open bar entry A from the keyboard: its first selectable item highlighted; it stays
; open (as after a click on its title)
mn_kopen:
        ldx     mb_n
        beq     mn_rts
        jsr     mn_show
        lda     #1
        sta     mn_sticky
        lda     ms_x                    ; (the pointer has not moved since)
        sta     mn_lx
        lda     ms_y
        sta     mn_ly
mn_home:
        lda     #NONE
mn_down:
        ldy     #1
mn_sel0:
        stz     kt3
        ; fall through
; the next selectable item after A in direction Y (+1, -1; wrapping) whose label starts
; with letter kt3 (0: any) gets the highlight
mn_step:
        ldx     mn_n
        beq     mn_rts
        stx     kt2
        sta     kt0
        sty     kt1
@l:     lda     kt0
        clc
        adc     kt1
        bpl     :+
        lda     mn_n
        dec     a
:       cmp     mn_n
        bcc     :+
        lda     #0
:       sta     kt0
        jsr     it_at
        jsr     it_bad
        bcs     @nx
        lda     kt3
        beq     @got
        lda     [kg_ln]                 ; (past a state byte)
        and     #$00FF
        cmp     #MS_STATE + 4
        bcs     :+
        inc     kg_ln
:       lda     [kg_ln]
        and     #$00DF
        cmp     kt3
        beq     @got
@nx:    dec     kt2
        bne     @l
        rts
@got:   lda     kt0
        sta     mn_sel
        jmp     dd_draw
mn_rts: rts

; A = letter ('A'-'Z') -> A = the bar entry whose title starts with it (the focused
; window's menus first, then the backdrop's); C set: none
mn_title:
        sta     kt0
        lda     #1                      ; pass 1: not the backdrop's, pass 0: its
        sta     kt1
@p:     ldx     #0
@e:     txa
        lsr     a
        cmp     mb_n
        bcs     @np
        ldy     #0
        lda     mb_win,x
        cmp     mb_back
        beq     :+
        cmp     #WMENU_W
        beq     :+
        iny
:       cpy     kt1
        bne     @nx
        lda     mb_off,x
        sta     kg_ln
        jsr     mb_bank
        lda     [kg_ln]
        and     #$00DF
        cmp     kt0
        bne     @nx
        txa
        lsr     a
        clc
        rts
@nx:    inx
        inx
        bra     @e
@np:    dec     kt1
        bpl     @p
        sec
        rts

; ---- $7D win_menu(A = window, X, Y = menus: title, items, "", ..., "") ----
; (0.14) read up to the end of the list, at most MENU_SZ - 3 bytes (and not past the end of
; the pointer's bank, or of the window in bank 0); a longer list is cut (whole menus kept
; well-formed: the cut string ends, then the menu and the list)
sys_wmenu:
        ldx     cur
        lda     t_a,x
        jsr     win_arg
        bcc     :+
        jmp     err_inval
:       stx     kg_e
        lda     #NONE                   ; (a menu open: close it first; one of this
        sta     mn_re                   ; window's: opened again afterwards)
        lda     mn_open
        bmi     :++
        asl     a
        tax
        lda     mb_win,x
        cmp     kg_e
        bne     :+
        lda     mn_open
        sta     mn_re
        lda     mn_sticky
        sta     mn_rs
:       jsr     mn_close
        ldx     cur                     ; (0.29) mn_close's win_close of the drop-down took
        lda     t_a,x                   ; kg_e: the window again (before, the new menus went
        asl     a                       ; to the drop-down's place and were lost: a menu
        sta     kg_e                    ; refreshed while open kept its old items)
:       ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #1
        sta     kt2
        stz     kt3
        jsr     uaccess
        bcc     :+
        jmp     err_fault
:       lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        ldx     cur                     ; readable: to the end of the bank (or the window)
        lda     #0
        ldy     t_y,x
        bne     :+
        lda     #$8000
:       sec
        sbc     t_x,x
        beq     :+                      ; (0: the whole bank)
        cmp     #MENU_SZ - 3
        bcc     :++
:       lda     #MENU_SZ - 3
:       sta     kt5
        ldx     kg_e
        jsr     menu_ptr
        ldy     #0
        lda     #1                      ; kt6: a title comes (a menu starts)
        sta     kt6
@str:   cpy     kt5
        bcs     @cut
        a8
        lda     [kp1],y
        a16
        and     #$00FF
        bne     @full
        lda     kt6                     ; "" where a title comes: the end
        bne     @end
        a8                              ; "": the end of a menu
        sta     [kg_ln],y
        a16
        iny
        inc     kt6
        bra     @str
@full:  stz     kt6
@ch:    a8
        lda     [kp1],y
        sta     [kg_ln],y
        a16
        iny
        and     #$00FF
        beq     @str
        cpy     kt5
        bcc     @ch
@cut:   a8
        lda     #0
        sta     [kg_ln],y
        iny
        sta     [kg_ln],y
        iny
@end:   a8
        lda     #0
        sta     [kg_ln],y
        a16
        jsr     bar_draw
        lda     mn_re
        bmi     :+
        cmp     mb_n
        bcs     :+
        inc     mn_noev
        jsr     mn_show
        stz     mn_noev
        lda     mn_rs
        sta     mn_sticky
:       lda     #0
        jmp     set_ok

; ---- $7E ws_status(X, Y = string): the text at the right of the menu bar ----
sys_wstat:
        lda     ws_on
        bne     :+
        jmp     err_inval
:       ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #1
        sta     kt2
        stz     kt3
        jsr     uaccess
        bcc     :+
        jmp     err_fault
:       lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        ldy     #0
        a8
:       lda     [kp1],y
        sta     ws_stat,y
        beq     :+
        iny
        cpy     #31
        bne     :-
        lda     #0
        sta     ws_stat,y
:       a16
        jsr     bar_draw
        lda     #0
        jmp     set_ok
