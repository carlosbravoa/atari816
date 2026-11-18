; ws13.s - window system additions of 0.13: the window manager's keys (keyboard menus,
; Alt+Tab, Alt+F4 and ctrl+W), win_mstate, ws_closeall, and the task helpers used by
; sys13.s (ws_task_info, ws_task_raise).
        .a16
        .i16

KM_ALT  = $44                           ; HID modifiers: left / right Alt
KM_CTRL = $11                           ;   left / right ctrl

; ---- the window manager's keys (wm_key: kg_t = usage, kg_u = modifiers | down << 8).
; C set: taken (not passed on). F10, or Alt pressed and released alone, opens the bar's
; first menu (or closes the open one); Alt+letter the menu whose title starts with it.
; While a menu is open every key goes to it (mn_key), except the Alt keys themselves,
; which always go on. Alt+Tab raises the bottom-most normal window; Alt+F4 and ctrl+W
; send WE_CLOSE to the focused window.
wm_kbd: jsl     k2_fskey                ; (0.18) the full screen: only its way out
        cmp     #1
        bne     :+
        sec
        rts
:       cmp     #2
        bne     :+
        clc
        rts
:       lda     kg_t
        cmp     #$FF                    ; F12: as before
        beq     @pass
        ldx     kg_u
        cpx     #$0100
        bcs     @down
        cmp     #$43                    ; a release: F10's is taken
        jeq     @take
        jsr     @alt
        bne     @rel
        lda     km_alt                  ; Alt released alone: the menus
        beq     @pass
        stz     km_alt
        jsr     @tog
@pass:  clc
        rts
@rel:   lda     mn_open                 ; (while a menu is open: taken)
        jpl     @take
        clc
        rts
@down:  stz     km_alt
        jsr     @alt
        bne     :+
        inc     km_alt                  ; Alt down: pending
        clc
        rts
:       cmp     #$43                    ; F10
        bne     :+
        lda     kg_u                    ; (0.15: Shift+F10 goes to the program: its
        and     #$22                    ; pop-up menu)
        bne     @pass
        jsr     @tog
        bra     @take
:       lda     kg_u
        and     #KM_ALT
        beq     @noalt
        lda     kg_t                    ; Alt+letter: that menu
        sec
        sbc     #4
        cmp     #26
        bcs     :+
        adc     #'A'
        jsr     mn_title
        bcs     :+
        jsr     mn_kopen
        bra     @take
:       lda     mn_open
        bpl     @menu
        lda     kg_t
        cmp     #$2B                    ; Alt+Tab
        bne     :+
        jsr     wm_atab
        bra     @take
:       cmp     #$3D                    ; Alt+F4
        beq     @close
        bra     @pass
@noalt: lda     mn_open
        bpl     @menu
        lda     kg_u                    ; ctrl+W
        and     #KM_CTRL
        beq     @pass
        lda     kg_t
        cmp     #$1A
        bne     @pass
@close: ldx     ws_top                  ; WE_CLOSE to the focused window (as its close box)
        bmi     @take
        lda     w_fl,x
        bit     #WF_BACK
        bne     @take
        lda     #WE_CLOSE
        jsr     wev_push0
        bra     @take
@menu:  lda     kg_t
        jsr     mn_key
@take:  sec
        rts
@tog:   lda     mn_open                 ; open the first menu, or close the open one
        bmi     :+
        jmp     mn_close
:       lda     #0
        jmp     mn_kopen
@alt:   lda     kg_t                    ; Z set: an Alt key
        cmp     #$E2
        beq     :+
        cmp     #$E6
:       rts

; Alt+Tab: the bottom-most normal window comes to the top (so repeated presses go
; through all of them); a dialog of its program comes up with it. (0.14) A minimized
; window comes first: it is restored on top.
wm_atab:
        ldx     #0
:       lda     w_used,x
        beq     :+
        lda     w_st,x
        and     #WS_MIN
        beq     :+
        jmp     win_front
:       inx
        inx
        cpx     #NWIN * 2
        bne     :--
        ldy     #0
@z:     cpy     z_n
        bcs     @out
        tya
        asl     a
        tax
        lda     z_list,x
        tax
        iny
        lda     w_fl,x
        bit     #WF_BACK | WF_OVER
        bne     @z
        cpx     ws_top
        beq     @out
        phx
        jsr     wm_raise
        plx
        jsr     wm_modal0
        bcc     @out
        jmp     wm_raise
@out:   rts

; ---- $8C win_mstate(A = own window, X = menu | item << 8, Y = state): the item's state
; byte (MS_STATE | Y & 3); EINVAL: no such window, menu or item, or no state byte ----
sys_wmstate:
        ldx     cur
        lda     t_a,x
        jsr     win_arg
        jcs     @bad
        stx     kg_e
        jsr     menu_ptr
        ldx     cur
        lda     t_x,x
        and     #$00FF
        sta     kt0                     ; menu
        sta     kt2
        lda     t_x+1,x
        and     #$00FF
        sta     kt1                     ; item
        sta     kt3
@m:     lda     [kg_ln]                 ; the menu
        and     #$00FF
        beq     @bad
        jsr     str_skip
        dec     kt0
        bmi     @i
:       lda     [kg_ln]
        and     #$00FF
        beq     :+
        jsr     str_skip
        bra     :-
:       inc     kg_ln
        bra     @m
@i:     lda     [kg_ln]                 ; the item
        and     #$00FF
        beq     @bad
        dec     kt1
        bmi     :+
        jsr     str_skip
        bra     @i
:       and     #$00FC
        cmp     #MS_STATE
        bne     @bad
        ldx     cur
        lda     t_y,x
        and     #MS_CHECK | MS_DIM
        ora     #MS_STATE
        a8
        sta     [kg_ln]
        a16
        and     #MS_DIM
        sta     kt0
        lda     dd_w                    ; its drop-down is open: drawn again
        bmi     @ok
        lda     mn_open
        asl     a
        tax
        lda     mb_win,x
        cmp     kg_e
        bne     @ok
        lda     mb_idx,x
        cmp     kt2
        bne     @ok
        lda     kt0                     ; (dimmed: no longer highlighted)
        beq     :+
        lda     mn_sel
        cmp     kt3
        bne     :+
        lda     #NONE
        sta     mn_sel
:       jsr     dd_draw
@ok:    lda     #0
        jmp     set_ok
@bad:   jmp     err_inval

; ---- $8D ws_closeall: WE_CLOSE to every window of every other task (backdrops too; not
; the menu bar or a drop-down) ----
sys_wscloseall:
        lda     ws_on
        beq     @bad
        ldx     #0
@w:     lda     w_used,x
        beq     @n
        lda     w_fl,x
        bit     #WF_OVER
        bne     @n
        lda     w_owner,x
        cmp     cur
        beq     @n
        phx
        lda     #WE_CLOSE
        jsr     wev_push0
        plx
@n:     inx
        inx
        cpx     #NWIN * 2
        bne     @w
        lda     #0
        jmp     set_ok
@bad:   jmp     err_inval

; ---- for sys13.s (kernel conventions; never block; safe without the window system) ----
; X = slot*2 -> A = TI_WINDOWS 1 (it has a window) | TI_MODAL 2 (a WF_MODAL one) |
; TI_IDLE 4 (blocked in win_event, every window's queue empty), Y = its windows.
; Clobbers X, kt0, kt1.
ws_task_info:
        stx     kt0
        stz     kt1
        ldy     #0
        lda     ws_on
        beq     @out
        lda     t_state,x
        cmp     #TS_BLOCKED
        bne     :+
        lda     t_wreason,x
        cmp     #W_WEVENT
        bne     :+
        lda     #4
        sta     kt1
:       ldx     #0
@w:     lda     w_used,x
        beq     @n
        lda     w_owner,x
        cmp     kt0
        bne     @n
        iny
        lda     #1
        tsb     kt1
        lda     w_fl,x
        and     #WF_MODAL
        beq     :+
        lda     #2
        tsb     kt1
:       lda     w_qn,x
        beq     @n
        lda     #4
        trb     kt1
@n:     inx
        inx
        cpx     #NWIN * 2
        bne     @w
@out:   lda     kt1
        bit     #1                      ; (no window: not idle either)
        bne     :+
        lda     #0
:       rts

; X = slot*2: its normal windows come to the top, in their order (the top one gets the
; focus), damaged and the bar redrawn as for a click. Clobbers A, X, Y, kt0, kt1, kg_*.
ws_task_raise:
        lda     ws_on
        beq     @out
        stx     kt0
        ldx     #0                      ; (0.14) its minimized windows come back first
:       lda     w_used,x
        beq     :+
        lda     w_owner,x
        cmp     kt0
        bne     :+
        jsr     win_unmin
:       inx
        inx
        cpx     #NWIN * 2
        bne     :--
        stz     kt1                     ; how many
        ldy     z_n
@c:     dey
        bmi     @go
        jsr     @own
        bcc     @c
        inc     kt1
        bra     @c
@go:    ldy     #0                      ; the lowest one not moved yet goes up, until all
@r:     lda     kt1                     ; are (the moved ones lie above the rest)
        beq     @done
        jsr     @own
        bcs     :+
        iny
        bra     @r
:       phy
        stx     kg_e
        jsr     z_remove
        jsr     z_insert
        ldx     kg_e
        jsr     win_damage
        ply
        dec     kt1
        bra     @r
@done:  jmp     wm_retop
@out:   rts
; Y = z position -> X = window*2 there; C set: a normal window of task kt0
@own:   tya
        asl     a
        tax
        lda     z_list,x
        tax
        lda     w_fl,x
        bit     #WF_BACK | WF_OVER
        bne     :+
        lda     w_owner,x
        cmp     kt0
        beq     :++
:       clc
:       rts
