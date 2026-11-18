; ws15.s - window system additions of 0.15: pop-up menus (win_popup), focus events
; (WE_FOCUS / WE_UNFOCUS) and the keys a window holds (released when it loses the focus).
        .a16
        .i16

MB_POP   = 12                           ; the pop-up menu's bar entry (mn_open; never drawn)
MB_POPS  = $8C00                        ; its items in the menu bank: "", items, "" (1 KB)
POP_MAX  = 24                           ; items at most (24 * 14 + 4 lines: below the bar)
HK_N     = 8                            ; keys tracked as held by a window
HK_GONE  = $FFFE                        ; (hk_w) released for the window: drop its key events
HK_EAT   = $FFFD                        ;   taken by the window manager: drop its release

; ---- $90 win_popup(A = own window, X, Y = {u24 items, i16 x, i16 y, u8 flags}) -> A ----
; A pop-up menu at x, y of the window's content (x = $8000: at the pointer), its top left
; corner just beside that point (to the left or above it where the screen ends). The items
; are menu items (state bytes, '-' separators, a TAB before a shortcut), "" ends them. The
; caller blocks until an item is chosen (A = its index, counting separators) or the menu is
; dismissed (A = $FFFF: Esc, a click elsewhere, another menu opening). Flags bit 0: the
; first item is highlighted (opened from the keyboard).
sys_wpopup:
        ldx     cur
        lda     t_a,x
        jsr     win_arg
        bcc     :+
        jmp     err_inval
:       stx     pop_w
        lda     #8
        jsr     get_block
        bcc     :+
@flt:   jmp     err_fault
:       lda     mn_open                 ; a menu open: closed first (a pop-up: dismissed)
        bmi     :+
        jsr     mn_close
:       lda     kblk                    ; the items: read to the end of their bank (or
        sta     kt0                     ; of the window)
        lda     kblk+2
        and     #$00FF
        sta     kt1
        lda     #1
        sta     kt2
        stz     kt3
        jsr     uaccess
        bcs     @flt
        lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        ldx     cur
        lda     #0
        ldy     kblk+2
        bne     :+
        lda     #$8000
:       sec
        sbc     kblk
        beq     :+                      ; (0: the whole bank)
        cmp     #1000
        bcc     :++
:       lda     #1000
:       sta     kt5
        lda     #MB_POPS                ; "" (the title), then the items
        sta     kg_ln
        lda     ws_mbank
        sta     kg_ln+2
        a8
        lda     #0
        sta     [kg_ln]
        a16
        inc     kg_ln
        stz     kt6                     ; items
        ldy     #0
@str:   cpy     kt5
        bcs     @cut
        a8
        lda     [kp1],y
        a16
        and     #$00FF
        beq     @end                    ; "": the end
@ch:    a8
        lda     [kp1],y
        sta     [kg_ln],y
        a16
        iny
        and     #$00FF
        beq     @one
        cpy     kt5
        bcc     @ch
        bra     @cut
@one:   inc     kt6
        lda     kt6
        cmp     #POP_MAX
        bcc     @str
        bra     @end
@cut:   inc     kt6
        a8
        lda     #0
        sta     [kg_ln],y
        iny
@end:   a8
        lda     #0
        sta     [kg_ln],y
        a16
        lda     kt6
        bne     :+
        lda     #NONE                   ; no items: nothing chosen
        jmp     set_ok
:       lda     pop_w                   ; the bar entry MB_POP
        sta     mb_win + MB_POP * 2
        stz     mb_idx + MB_POP * 2
        lda     #MB_POPS
        sta     mb_off + MB_POP * 2
        lda     kblk+3                  ; the place: the pointer, or in the content
        cmp     #$8000
        bne     :+
        lda     ms_x
        sta     pop_x
        lda     ms_y
        sta     pop_y
        bra     @pl
:       ldx     pop_w
        clc
        adc     w_x,x
        clc
        adc     w_cx,x
        sta     pop_x
        lda     kblk+5
        clc
        adc     w_y,x
        clc
        adc     w_cy,x
        sta     pop_y
@pl:    lda     kblk+7
        sta     kt7                     ; (flags; kept until the menu is open)
        lda     #NONE
        sta     pop_res
        sta     cap_w                   ; (a press held by a window: the menu takes it)
        lda     cur
        sta     pop_task
        ldx     cur                     ; (dismissed unless something is chosen)
        lda     #NONE
        sta     t_a,x
        lda     t_p,x
        and     #$FFFE
        sta     t_p,x
        inc     mn_noev                 ; (no WE_MENUOPEN for it)
        lda     kt7
        pha
        lda     #MB_POP
        jsr     mn_show
        stz     mn_noev
        pla
        sta     kt7
        lda     dd_w
        bpl     :+
        jsr     mn_close                ; (no window for it: dismissed)
        bra     @wait
:       lda     #1                      ; open until a click (as after a click on a title)
        sta     mn_sticky
        lda     ms_x
        sta     mn_lx
        lda     ms_y
        sta     mn_ly
        lda     kt7
        and     #1
        beq     @wait
        jsr     mn_home                 ; (from the keyboard: the first item highlighted)
@wait:  lda     pop_task                ; until pop_end answers
        cmp     cur
        bne     @done
        ldx     cur
        lda     t_killed,x
        beq     :+
        jsr     mn_close                ; (killed: the menu goes)
        bra     @wait
:       lda     #W_POP
        ldy     #0
        jsr     k_block
        bra     @wait
@done:  rts                             ; (t_a and the carry were set by pop_end)

; (mn_drop) the pop-up menu closes: its caller gets pop_res and goes on
pop_end:
        ldx     pop_task
        bmi     @out
        lda     #NONE
        sta     pop_task
        lda     pop_res
        sta     t_a,x
        lda     kt6
        pha
        lda     kt7
        pha
        lda     #W_POP
        ldy     #0
        jsr     k_wake_all
        pla
        sta     kt7
        pla
        sta     kt6
@out:   rts

; (mn_show) the pop-up's place: kg_x, kg_y for its size kg_w, kg_h - right of and below
; the point, else left of it, above it
pop_place:
        lda     pop_x
        inc     a
        sta     kg_x
        clc
        adc     kg_w
        cmp     #SCR_W + 1
        bcc     :++
        lda     pop_x
        sec
        sbc     kg_w
        bpl     :+
        lda     #0
:       sta     kg_x
:       lda     pop_y
        inc     a
        sta     kg_y
        clc
        adc     kg_h
        cmp     #SCR_H + 1
        bcc     :+
        lda     pop_y
        sec
        sbc     kg_h
        sta     kg_y
:       lda     kg_y
        cmp     #MENU_H
        bpl     :+
        lda     #MENU_H
        sta     kg_y
:       rts

; (mn_button) a button change while the pop-up menu is open: a press on an item highlights
; it, a press outside the menu dismisses it; a release (of any button) on an item chooses it
pop_button:
        lda     wm_btn                  ; pressed now: new & ~old
        eor     #$FFFF
        and     wm_nbtn
        beq     @rel
        jsr     pop_hit
        bcc     :+
        jmp     mn_close                ; outside: dismissed (the click is used up)
:       cmp     #NONE
        beq     @out
        sta     mn_sel
        lda     #2
        sta     mn_sticky
        jmp     dd_draw
@rel:   lda     wm_nbtn                 ; released: old & ~new
        eor     #$FFFF
        and     wm_btn
        beq     @out
        jsr     pop_hit
        bcs     @out
        cmp     #NONE
        beq     @out
        tax
        jmp     mn_pick
@out:   rts

; C set: (wm_x, wm_y) is outside the open drop-down; else A = the item there (NONE: none)
pop_hit:
        ldx     dd_w
        bmi     @no
        lda     wm_x
        sec
        sbc     w_x,x
        cmp     w_w,x
        bcs     @no
        lda     wm_y
        sec
        sbc     w_y,x
        cmp     w_h,x
        bcs     @no
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
        txa
        clc
        rts
@no:    sec
        rts

; ---- focus events (wm_retop): ws_top changed -> WE_UNFOCUS to the window that had the
; focus (after key releases for the keys it holds), WE_FOCUS to the new one. Keeps kg_t,
; kg_u, kg_v.
ws_focus:
        lda     ws_top
        cmp     fo_w
        bne     :+
        rts
:       lda     kg_t
        pha
        lda     kg_u
        pha
        lda     kg_v
        pha
        ldx     fo_w
        bmi     @new
        jsr     hk_release
        ldx     fo_w
        lda     w_used,x
        beq     @new
        lda     #WE_UNFOCUS
        jsr     wev_push0
@new:   ldx     ws_top
        stx     fo_w
        bmi     @out
        lda     #WE_FOCUS
        jsr     wev_push0
@out:   jsl     k2_focus                ; (0.18) palette entries, full screen, sprites
        pla
        sta     kg_v
        pla
        sta     kg_u
        pla
        sta     kg_t
        rts

; window X loses the focus: every key it holds gets a release now (b = 0); their real
; releases (and repeats) later are dropped
hk_release:
        stx     hk_x
        ldy     #0
@k:     lda     hk_w,y
        cmp     hk_x
        bne     @n
        lda     #HK_GONE
        sta     hk_w,y
        ldx     hk_x
        lda     w_used,x
        beq     @n
        lda     hk_u,y
        sta     kg_t
        stz     kg_u
        lda     #WE_KEY
        sta     kg_v
        phy
        lda     #0
        jsr     wev_push
        ply
@n:     iny
        iny
        cpy     #HK_N * 2
        bne     @k
        rts

; (wm_key, first) the key kg_t (kg_u = modifiers | down << 8) and the held keys: a release
; ends its entry; a key released for a window that lost the focus has its own release and
; its repeats dropped. C set: drop the key.
hk_pre: lda     kg_t
        cmp     #$FF                    ; (F12)
        beq     @ok
        ldy     #0
@f:     lda     hk_w,y                  ; held?
        cmp     #NONE
        beq     @fn
        lda     hk_u,y
        cmp     kg_t
        beq     @have
@fn:    iny
        iny
        cpy     #HK_N * 2
        bne     @f
@ok:    clc
        rts
@have:  lda     kg_u
        cmp     #$0100
        bcs     @down
        lda     hk_w,y                  ; a release: the entry ends
        pha
        lda     #NONE
        sta     hk_w,y
        pla
        cmp     #HK_EAT                 ; (released for its window already, or its press
        bcs     @drop                   ; was the window manager's: dropped)
        clc
        rts
@down:  lda     hk_w,y                  ; a repeat: dropped if released for its window
        cmp     #HK_GONE
        bne     @ok
@drop:  sec
        rts

; (wm_key) a press the window manager took (a menu's keys, F10, Alt+Tab ...): its release
; will be dropped too
hk_eat: ldx     #HK_EAT
        ; fall through
; (wm_key, a WE_KEY for window X) a press not held yet takes a free entry; keeps X
hk_add: lda     kg_u
        cmp     #$0100
        bcc     @out
        lda     kg_t
        cmp     #$FF
        beq     @out
        ldy     #0
@f:     lda     hk_w,y
        cmp     #NONE
        beq     @n
        lda     hk_u,y
        cmp     kg_t
        beq     @out                    ; (a repeat: held already)
@n:     iny
        iny
        cpy     #HK_N * 2
        bne     @f
        ldy     #0
@g:     lda     hk_w,y
        cmp     #NONE
        beq     @add
        iny
        iny
        cpy     #HK_N * 2
        bne     @g
@out:   rts                             ; (full: not tracked)
@add:   lda     kg_t
        sta     hk_u,y
        txa
        sta     hk_w,y
        rts
