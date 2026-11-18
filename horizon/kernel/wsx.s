; wsx.s - window system extras (stage 3): the clipboard, window info and hit test, drops
; between windows (drag and drop), palette entries, user settings, window titles.

; ---- $80 clip_put(X, Y = {u24 data, u16 length}): the system clipboard (64 KB at most;
; length 0 empties it; the data must not cross a bank) ----
sys_clput:
        lda     #5
        jsr     get_block
        bcc     :+
        jmp     err_fault
:       lda     kblk+3
        bne     :+
        stz     clip_len
        jmp     @ok
:       lda     clip_bank               ; its bank, on first use
        bne     :+
        lda     #1
        jsr     bank_run
        bcc     :+
        jmp     err_nomem
:       sta     clip_bank
        lda     kblk
        sta     kt0
        lda     kblk+2
        and     #$00FF
        sta     kt1
        lda     kblk+3
        sta     kt2
        stz     kt3
        jsr     uaccess
        bcc     :+
        jmp     err_fault
:       lda     kphys
        sta     kt0
        lda     kphys+2
        sta     kt1
        stz     kt2
        lda     clip_bank
        sta     kt3
        lda     kblk+3
        sta     clip_len
        jsr     kmemcpy
@ok:    lda     #0
        jmp     set_ok

; ---- $81 clip_get(X, Y = {u24 buffer, u16 size}) -> A = the clipboard's length; copies
; min(length, size) bytes (size 0: the length only) ----
sys_clget:
        lda     #5
        jsr     get_block
        bcc     :+
        jmp     err_fault
:       lda     kblk+3
        cmp     clip_len
        bcc     :+
        lda     clip_len
:       sta     kt2
        beq     @out
        lda     kblk
        sta     kt0
        lda     kblk+2
        and     #$00FF
        sta     kt1
        lda     #1
        sta     kt3
        jsr     uaccess
        bcc     :+
        jmp     err_fault
:       lda     kt2
        pha
        stz     kt0
        lda     clip_bank
        sta     kt1
        lda     kphys
        sta     kt2
        lda     kphys+2
        sta     kt3
        pla
        jsr     kmemcpy
@out:   lda     clip_len
        jmp     set_ok

err_nomem:
        lda     #ENOMEM
        jmp     set_err

; X = window A (any owner, not an overlay) -> C set: no such window
win_any:
        cmp     #NWIN
        bcs     @bad
        asl     a
        tax
        lda     w_used,x
        beq     @bad
        lda     w_fl,x
        bit     #WF_OVER
        bne     @bad
        clc
        rts
@bad:   sec
        rts

; ---- $82 win_info(A = window, X, Y = 8-byte buffer): {i16 content x, i16 content y on
; the screen, u16 content width, u16 content height}; any window ----
sys_winfo:
        ldx     cur
        lda     t_a,x
        jsr     win_any
        bcc     :+
        jmp     err_inval
:       stx     kg_e
        ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #8
        sta     kt2
        lda     #1
        sta     kt3
        jsr     uaccess
        bcc     :+
        jmp     err_fault
:       lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        ldx     kg_e
        lda     w_x,x
        clc
        adc     w_cx,x
        sta     [kp1]
        ldy     #2
        lda     w_y,x
        clc
        adc     w_cy,x
        sta     [kp1],y
        ldy     #4
        lda     w_w,x
        sec
        sbc     w_cx,x
        sec
        sbc     w_cx,x
        sta     [kp1],y
        ldy     #6
        lda     w_h,x
        sec
        sbc     w_cy,x
        sec
        sbc     w_cb,x
        sta     [kp1],y
        lda     #0
        jmp     set_ok

; ---- $83 win_at(X = screen x, Y = screen y) -> A = the window there (a backdrop too),
; $FF = none (or the menu bar) ----
sys_winat:
        ldx     cur
        lda     t_x,x
        sta     wm_x
        lda     t_y,x
        sta     wm_y
        jsr     wm_hit
        cpx     #NONE
        beq     @none
        lda     w_fl,x
        bit     #WF_OVER
        bne     @none
        txa
        lsr     a
        jmp     set_ok
@none:  lda     #$FF
        jmp     set_ok

; ---- $84 win_drop(A = window, X, Y = string, 127 characters): drag and drop. The target
; window (any program's) gets WE_DROP: a, b = the pointer in its content, c = the
; sender's task id | the modifier keys << 8; it reads the string with win_dropget ----
sys_wdrop:
        ldx     cur
        lda     t_a,x
        jsr     win_any
        bcc     :+
        jmp     err_inval
:       stx     kg_e
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
        jmp     err_fault
:       lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        jsr     drop_ptr                ; the menu bank: MB_DROP + window * 128
        ldy     #0
        a8
:       lda     [kp1],y
        sta     [km_p],y
        beq     :+
        iny
        cpy     #127
        bne     :-
        lda     #0
        sta     [km_p],y
:       a16
        ldx     kg_e
        lda     ms_x
        sec
        sbc     w_x,x
        sec
        sbc     w_cx,x
        sta     kg_t
        lda     ms_y
        sec
        sbc     w_y,x
        sec
        sbc     w_cy,x
        sta     kg_u
        lda     #WE_DROP
        sta     kg_v
        ldy     cur                     ; c = the sender | the modifiers << 8 (0.14)
        lda     t_id,y
        and     #$00FF
        ora     ws_mods
        jsr     wev_push
        lda     #0
        jmp     set_ok

; window kg_e -> km_p = its dropped string (the menu bank: MB_DROP + window * 128)
drop_ptr:
        lda     kg_e
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #MB_DROP
        sta     km_p
        lda     ws_mbank
        sta     km_p+2
        rts

; ---- $85 win_dropget(A = window, X, Y = 128-byte buffer): the last string dropped on it ----
sys_wdropget:
        ldx     cur
        lda     t_a,x
        jsr     win_arg
        bcc     :+
        jmp     err_inval
:       stx     kg_e
        ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #128
        sta     kt2
        lda     #1
        sta     kt3
        jsr     uaccess
        bcc     :+
        jmp     err_fault
:       lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        jsr     drop_ptr
        ldy     #0
        a8
:       lda     [km_p],y
        sta     [kp1],y
        iny
        cpy     #128
        bne     :-
        a16
        lda     #0
        jmp     set_ok

; ---- $86 ws_palette(A = index, X = red | green << 8, Y = blue): one entry of the system
; palette (the desktop colours are 2 and 3) ----
sys_wspal:
        jsl     k2_wspal                ; (0.18) entries 16-255 are the setter's (k2pal.s)
        rts

; ---- $87 setting(A = id, X = value, $FFFF = only read) -> A = the old value.
; 0 mouse speed 1-4, 1 beep volume 0-15, 2 key repeat delay (10 ms ticks, 0 = off),
; 3 key repeat interval (ticks), (0.18) 4 the sound volume 0-15 (Lau's master volume) ----
sys_setting:
        ldx     cur
        lda     t_a,x
        cmp     #5
        bcc     :+
        jmp     err_inval
:       asl     a
        tay
        lda     set_tab,y
        tay                             ; Y = the variable's address
        lda     a:0,y
        pha
        lda     t_x,x
        cmp     #$FFFF
        beq     :+
        sta     a:0,y
        jsr     au_master               ; (0.18) Lau's master volume follows setting 4
:       pla
        jmp     set_ok
set_tab: .addr  ms_speed, snd_vol, rep_delay, rep_rate, smp_vol

; ---- $88 win_title(A = window, X, Y = string): a new title (31 characters) ----
sys_wtitle:
        ldx     cur
        lda     t_a,x
        jsr     win_arg
        bcc     :+
        jmp     err_inval
:       stx     kg_e
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
        jmp     err_fault
:       lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        lda     kg_e
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #.loword(w_title)
        tax
        ldy     #0
        a8
:       lda     [kp1],y
        sta     a:0,x
        beq     :+
        inx
        iny
        cpy     #31
        bne     :-
        lda     #0
        sta     a:0,x
:       a16
        ldx     kg_e
        jsr     win_decor
        ldx     kg_e
        jsr     win_damage
        lda     #0
        jmp     set_ok
