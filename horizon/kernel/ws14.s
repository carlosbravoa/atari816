; ws14.s - window system additions of 0.14: minimize and maximize (the title bar's
; buttons, a double click on the title), the Windows menu, win_geom, task_name, and the
; clock (time_get / time_set).
        .a16
        .i16

; ---- the title bar's buttons (win_decor): minimize for every normal window that is not
; a dialog, maximize also when it is resizable. A = w_fl -> C set: it has them (keeps X)
tb_has:
        bit     #WF_PLAIN | WF_BACK | WF_MODAL
        bne     :+
        sec
        rts
:       clc
        rts

; draw window X's buttons at the right of its title bar (surface and clip set; keeps X)
tb_draw:
        lda     w_fl,x
        jsr     tb_has
        bcs     :+
        rts
:       phx
        lda     w_w,x                   ; minimize: a box with a bar at its bottom
        sec
        sbc     #TB_MIN
        jsr     tb_box
        lda     1,s
        tax
        lda     w_w,x
        sec
        sbc     #TB_MIN - 2
        sta     kg_x
        lda     #9
        sta     kg_y
        lda     #6
        sta     kg_w
        lda     #2
        sta     kg_h
        lda     #C_BLACK
        sta     kg_fg
        jsr     gfx_rect
        plx
        lda     w_fl,x
        bit     #WF_RESIZE
        bne     :+
        rts
:       phx
        lda     w_w,x                   ; maximize: a window; maximized: two (restore)
        sec
        sbc     #TB_MAX
        jsr     tb_box
        lda     1,s
        tax
        lda     w_st,x
        and     #WS_MAX
        bne     @two
        lda     w_w,x
        sec
        sbc     #TB_MAX - 2
        sta     kg_x
        lda     #5
        sta     kg_y
        lda     #6
        sta     kg_w
        sta     kg_h
        jsr     tb_win
        plx
        rts
@two:   lda     w_w,x
        sec
        sbc     #TB_MAX - 4
        sta     kg_x
        lda     #5
        sta     kg_y
        lda     #5
        sta     kg_w
        sta     kg_h
        jsr     tb_win
        lda     1,s
        tax
        lda     w_w,x
        sec
        sbc     #TB_MAX - 2
        sta     kg_x
        lda     #7
        sta     kg_y
        lda     #5
        sta     kg_w
        sta     kg_h
        lda     #C_LIGHT
        sta     kg_fg
        jsr     gfx_rect
        lda     1,s
        tax
        lda     w_w,x
        sec
        sbc     #TB_MAX - 2
        sta     kg_x
        lda     #7
        sta     kg_y
        lda     #5
        sta     kg_w
        sta     kg_h
        jsr     tb_win
        plx
        rts

; a button's box at x = A (as the close box: a black frame, light inside)
tb_box: sta     kg_x
        pha
        lda     #3
        sta     kg_y
        lda     #10
        sta     kg_w
        sta     kg_h
        lda     #C_BLACK
        sta     kg_fg
        jsr     gfx_frame
        pla
        inc     a
        sta     kg_x
        lda     #4
        sta     kg_y
        lda     #8
        sta     kg_w
        sta     kg_h
        lda     #C_LIGHT
        sta     kg_fg
        jmp     gfx_rect

; a little window at kg_x, kg_y, kg_w x kg_h: a black frame with a two-line top
tb_win: lda     kg_x
        pha
        lda     kg_y
        pha
        lda     kg_w
        pha
        lda     #C_BLACK
        sta     kg_fg
        jsr     gfx_frame
        pla
        sta     kg_w
        pla
        inc     a
        sta     kg_y
        pla
        sta     kg_x
        lda     #1
        sta     kg_h
        jmp     gfx_rect

; a press on window X's title bar at x A (relative to the window), y kg_t: C set if it
; was on one of the buttons (and that was done)
tb_press:
        sta     kt0
        lda     kg_t
        cmp     #2
        bcc     @no
        cmp     #14
        bcs     @no
        lda     w_fl,x
        jsr     tb_has
        bcc     @no
        lda     w_w,x                   ; the minimize box
        sec
        sbc     #TB_MIN + 1
        cmp     kt0
        beq     :+
        bcs     @max
:       clc
        adc     #12
        cmp     kt0
        bcc     @max
        jsr     win_min
        sec
        rts
@max:   lda     w_fl,x
        bit     #WF_RESIZE
        beq     @no
        lda     w_w,x                   ; the maximize box
        sec
        sbc     #TB_MAX + 1
        cmp     kt0
        beq     :+
        bcs     @no
:       clc
        adc     #12
        cmp     kt0
        bcc     @no
        jsr     win_maxtog
        sec
        rts
@no:    clc
        rts

; ---- minimize / restore
; window X minimized: out of the z list (its bitmap is kept and still drawn into)
win_min:
        lda     w_st,x
        and     #WS_MIN
        beq     :+
        rts
:       stx     kg_e
        jsr     win_unstale
        lda     w_st,x
        ora     #WS_MIN
        sta     w_st,x
        jsr     win_damage
        jsr     z_remove
        jsr     win_forget
        lda     #NONE                   ; (the old top is gone: no redraw for it)
        sta     ws_top
        jmp     wm_retop

; window kg_e no longer takes part in a drag, a resize, a press, the hover, an open menu
win_forget:
        lda     #NONE
        ldx     kg_e
        cpx     rs_w
        bne     :+
        sta     rs_w
:       cpx     cap_w
        bne     :+
        sta     cap_w
:       cpx     hov_w
        bne     :+
        sta     hov_w
:       cpx     drag_w
        bne     :+
        sta     drag_w
:       jmp     mn_closed

; window X back from minimized (into the z list on top of its class; drawn); keeps X
win_unmin:
        lda     w_st,x
        and     #WS_MIN
        bne     :+
        rts
:       lda     w_st,x
        and     #$FFFF ^ WS_MIN
        sta     w_st,x
        stx     kg_e
        jsr     z_insert
        ldx     kg_e
        jsr     win_damage
        ldx     kg_e
        rts

; ---- $A0 win_front(A = own window): (BASIC 2.0) back if minimized, raised to the top of
; its class, the focus (a full-screen window: the full screen shown again) ----
sys_wfront:
        ldx     cur
        lda     t_a,x
        jsr     win_arg
        bcc     :+
        jmp     err_inval
:       jsr     win_front
        lda     #0
        jmp     set_ok

; window X restored if minimized, raised, and a dialog of its program over it
win_front:
        jsr     win_unmin
        phx
        jsr     wm_raise
        plx
        jsr     wm_modal0
        bcc     :+
        jmp     wm_raise
:       rts

; ---- maximize: the whole screen below the menu bar; again: the geometry before. The
; program gets WE_RESIZE.
win_maxtog:
        stx     kg_e
        lda     w_st,x
        bit     #WS_MAX
        bne     @back
        ora     #WS_MAX
        sta     w_st,x
        lda     w_x,x
        sta     w_rx,x
        lda     w_y,x
        sta     w_ry,x
        lda     w_w,x
        sta     w_rw,x
        lda     w_h,x
        sta     w_rh,x
        stz     kg_t
        lda     #MENU_H
        sta     kg_u
        lda     #SCR_W
        sta     kg_w
        lda     #SCR_H - MENU_H
        sta     kg_h
        bra     @set
@back:  and     #$FFFF ^ WS_MAX
        sta     w_st,x
        lda     w_rx,x
        sta     kg_t
        lda     w_ry,x
        sta     kg_u
        lda     w_rw,x
        sta     kg_w
        lda     w_rh,x
        sta     kg_h
@set:   lda     kg_e
        pha
        jsr     win_place
        plx
        ; fall through
; WE_RESIZE to window X: its content size
win_tellsize:
        lda     #WE_RESIZE
        sta     kg_v
        lda     w_w,x
        sec
        sbc     w_cx,x
        sec
        sbc     w_cx,x
        sta     kg_t
        lda     w_h,x
        sec
        sbc     w_cy,x
        sec
        sbc     w_cb,x
        sta     kg_u
        lda     #0
        jmp     wev_push

; window kg_e to x kg_t, y kg_u, outer size kg_w x kg_h (kept on the screen, below the bar)
win_place:
        lda     kg_w                    ; the size: 96 .. 640 x 40 .. 344 (8 for a plain one)
        cmp     #SCR_W + 1
        bcc     :+
        lda     #SCR_W
:       sta     kg_w
        lda     kg_h
        cmp     #SCR_H - MENU_H + 1
        bcc     :+
        lda     #SCR_H - MENU_H
:       sta     kg_h
        lda     kg_t                    ; x: 0 .. 640 - w
        bpl     :+
        lda     #0
:       sta     kg_t
        lda     #SCR_W
        sec
        sbc     kg_w
        cmp     kg_t
        bcs     :+
        sta     kg_t
:       lda     kg_u                    ; y: 16 .. 360 - h
        bmi     :+
        cmp     #MENU_H
        bcs     :++
:       lda     #MENU_H
:       sta     kg_u
        lda     #SCR_H
        sec
        sbc     kg_h
        cmp     kg_u
        bcs     :+
        sta     kg_u
:       lda     kg_w
        pha
        lda     kg_h
        pha
        lda     kg_t
        pha
        lda     kg_u
        pha
        ldx     kg_e
        jsr     win_unstale
        jsr     win_damage              ; the old place
        ldx     kg_e
        pla
        sta     w_y,x
        pla
        sta     w_x,x
        pla
        sta     kg_h
        pla
        sta     kg_w
        cmp     w_w,x
        bne     :+
        lda     kg_h
        cmp     w_h,x
        bne     :+
        jsr     win_decor               ; (the same size: only moved)
        ldx     kg_e
        jmp     win_damage
:       jmp     win_resize

; ---- $8E win_geom(A = own window, X, Y = {i16 x, i16 y, u16 width, u16 height}): moves
; and resizes it (content size, as win_open; x = $8000: where it is). No WE_RESIZE. ----
sys_wgeom:
        ldx     cur
        lda     t_a,x
        jsr     win_arg
        bcc     :+
        jmp     err_inval
:       stx     kg_e
        lda     #8
        jsr     get_block
        bcc     :+
        jmp     err_fault
:       ldx     kg_e
        lda     w_st,x
        and     #$FFFF ^ WS_MAX
        sta     w_st,x
        lda     kblk
        cmp     #$8000
        bne     :+
        lda     w_x,x
        sta     kblk
        lda     w_y,x
        sta     kblk+2
:       lda     kblk
        sta     kg_t
        lda     kblk+2
        sta     kg_u
        lda     kblk+4                  ; outer size = content + the margins
        clc
        adc     w_cx,x
        adc     w_cx,x
        cmp     #8
        bcs     :+
        lda     #8
:       sta     kg_w
        lda     kblk+6
        clc
        adc     w_cy,x
        adc     w_cb,x
        cmp     #8
        bcs     :+
        lda     #8
:       sta     kg_h
        jsr     win_place
        lda     #0
        jmp     set_ok

; ---- the Windows menu (the kernel's, after the Desktop's system menus): every window,
; the front one checked, minimized ones in brackets; choosing one restores and raises it
wl_title: .byte "Windows", 0, 0, 0
wl_title_end:
wl_none: .byte  MS_STATE | MS_DIM, "No windows", 0
wl_none_end:

; its items into the menu bank after "Windows" (wl_ids: their windows)
wl_build:
        lda     #MB_WMENU + 8
        sta     km_p
        lda     ws_mbank
        sta     km_p+2
        stz     wl_n
        ldy     z_n                     ; the windows in view, front first
@z:     dey
        bmi     @min
        phy
        tya
        asl     a
        tax
        lda     z_list,x
        tax
        lda     w_fl,x
        bit     #WF_BACK | WF_OVER
        bne     :+
        jsr     wl_item
:       ply
        bra     @z
@min:   ldx     #0                      ; then the minimized ones
@m:     lda     w_used,x
        beq     :+
        lda     w_st,x
        and     #WS_MIN
        beq     :+
        phx
        jsr     wl_item
        plx
:       inx
        inx
        cpx     #NWIN * 2
        bne     @m
        lda     wl_n
        bne     @end
        ldx     #0
:       lda     wl_none,x
        jsr     wl_put
        inx
        cpx     #wl_none_end - wl_none
        bne     :-
@end:   lda     #0                      ; the end of the menu and of the list
        jsr     wl_put
        lda     #0
        jmp     wl_put

; window X as an item
wl_item:
        lda     wl_n
        cmp     #16
        bcc     :+
        rts
:       asl     a
        tay
        txa
        sta     wl_ids,y
        inc     wl_n
        lda     #MS_STATE               ; the state byte: the front one checked
        cpx     ws_top
        bne     :+
        ora     #MS_CHECK
:       jsr     wl_put
        lda     w_st,x
        and     #WS_MIN
        sta     kt7
        beq     :+
        lda     #'['
        jsr     wl_put
:       txa                             ; the title (w_title + window * 32), else the
        asl     a                       ; program's name
        asl     a
        asl     a
        asl     a
        tay
        lda     w_title,y
        and     #$00FF
        bne     @t
        jsr     app_name
        ldy     #.loword(mb_name) - .loword(w_title)
@t:     ldx     #31
:       lda     w_title,y
        and     #$00FF
        beq     :+
        jsr     wl_put
        iny
        dex
        bne     :-
:       lda     kt7
        beq     :+
        lda     #']'
        jsr     wl_put
:       lda     #0
        ; fall through
; one byte A to [km_p]++ (keeps X, Y)
wl_put: a8
        sta     [km_p]
        a16
        inc     km_p
        rts

; item kg_u of the Windows menu was chosen
wl_pick:
        lda     kg_u
        cmp     wl_n
        bcs     :+
        asl     a
        tax
        lda     wl_ids,x
        tax
        lda     w_used,x
        beq     :+
        jmp     win_front
:       rts

; ---- $8F task_name(A = task id, 0 = the caller; X, Y = string): the name the menu bar
; shows for its windows (15 characters; "" = from its file name) ----
sys_tname:
        ldx     cur
        lda     t_a,x
        bmi     tname_get
        bne     :+
        lda     t_id,x
:       jsr     find_id                 ; -> X = its slot*2
        bcc     :+
        jmp     err_inval
:       phx                             ; (uaccess uses kt4)
        ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #1
        sta     kt2
        stz     kt3
        jsr     uaccess
        bcc     :+
        plx
        jmp     err_fault
:       lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        pla                             ; slot * 16
        asl     a
        asl     a
        asl     a
        tax
        ldy     #0
        a8
:       lda     [kp1],y
        sta     t_dname,x
        beq     :+
        inx
        iny
        cpy     #15
        bne     :-
        lda     #0
        sta     t_dname,x
:       a16
        lda     ws_on
        beq     :+
        jsr     bar_draw
:       lda     #0
        jmp     set_ok

; (0.15) task_name(A = id | $8000 (0: the caller), X, Y = 16-byte buffer): the name the bar
; shows for its windows (its task_name, else its file name with only the first letter
; capital), zero-terminated
tname_get:
        and     #$7FFF
        bne     :+
        lda     t_id,x
:       jsr     find_id
        bcc     :+
        jmp     err_inval
:       phx
        ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #16
        sta     kt2
        lda     #1
        sta     kt3
        jsr     uaccess
        pla
        bcc     :+
        jmp     err_fault
:       jsr     app_nslot               ; -> mb_name
        lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        ldy     #0
        a8
:       lda     mb_name,y
        sta     [kp1],y
        beq     :+
        iny
        cpy     #15
        bne     :-
        lda     #0
        sta     [kp1],y
:       a16
        lda     #0
        jmp     set_ok

; ---- $0D time_get -> A = seconds low, X = seconds high (since 2000-01-01 00:00), Y = 0 not
; set, 1 a provisional value (the last one saved), 2 set ----
sys_tget:
        ldx     cur
        lda     clk_sec+2
        sta     t_x,x
        lda     clk_st
        sta     t_y,x
        lda     clk_sec
        jmp     set_ok

; ---- $0E time_set(A = seconds low, X = high, Y = 1 provisional, 2 set): the clock counts
; from there (10 ms ticks) ----
sys_tset:
        ldx     cur
        lda     t_y,x
        beq     :+
        cmp     #3
        bcc     :++
:       jmp     err_inval
:       sta     clk_st
        lda     t_a,x
        sta     clk_sec
        lda     t_x,x
        sta     clk_sec+2
        stz     clk_sub
        lda     #0
        jmp     set_ok

; (the 10 ms tick, interrupt service) the clock
clk_tick:
        inc     clk_sub
        lda     clk_sub
        cmp     #100
        bcc     :+
        stz     clk_sub
        inc     clk_sec
        bne     :+
        inc     clk_sec+2
:       rts
