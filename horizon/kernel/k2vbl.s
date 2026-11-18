; k2vbl.s - (0.18) the vertical blank: the frame counter, what is applied there (sprites, the
; full screen's registers and raster table), WE_VBL.

        .segment "BSS"
vbl_due:    .res    2           ; WE_VBL to send (the window-system thread)
vbl_n:      .res    2           ; windows that asked for WE_VBL
w_vbl:      .res    32          ; per window: 1 = WE_VBL wanted

        .segment "K2CODE"

; ---- $9E frame() -> A = the frame counter: NV_FRAME (REV $09+: +1 at every vertical blank
; since the start, wraps at 65536); before REV $09 the vertical blanks waited for (vsync) ----
k2_frame:
        jsr     k2_nvframe
        jsl     f_set_ok
        rtl

; A = NV_FRAME (REV $09+; reading the low byte latches the high one), else vs_frame
k2_nvframe:
        lda     k_rev
        cmp     #$09
        bcc     @old
        a8
        lda     f:NV_FRAME
        xba
        lda     f:NV_FRAME+1
        xba
        a16
        rts
@old:   lda     vs_frame
        rts

; (vsync's result) A = the frame counter, as frame() gives it
        .export k2_frameval: far
k2_frameval:
        jsr     k2_nvframe
        rtl

; the next vertical blank is wanted (REV $09+: its interrupt on); before REV $09 there is no
; interrupt for this, so what it would do is done now
vbl_arm:
        lda     k_rev
        cmp     #$09
        bcc     @now
        a8
        lda     f:IRQ_EN
        bit     #IRQ_VBLANK
        bne     :+
        ora     #IRQ_VBLANK
        sta     f:IRQ_EN
        lda     #IRQ_VBLANK
        sta     f:IRQ_STATUS            ; (a stale latch)
:       a16
        rts
@now:   jsr     fs_vbl
        rts

; (vs_irq, REV $09+, the VBLANK interrupt) -> A non-zero: keep the VBLANK interrupt on
        .export k2_vbl: far
k2_vbl: jsr     spr_vbl
        jsr     fs_vbl
        sta     ki7
        lda     vbl_n                   ; WE_VBL: the window-system thread sends them
        beq     :+
        sta     vbl_due
        jsl     f_ws_paint_req
:       lda     ki7
        ora     vbl_n
        ora     spr_dirty
        ora     fs_dirty
        rtl

; (the window-system thread) WE_VBL to every window that asked, if its queue is empty
ev_vbl: ldx     #30
@w:     lda     w_vbl,x
        beq     @n
        lda     w_used,x
        beq     @n
        lda     w_qn,x
        bne     @n
        stz     kg_t
        stz     kg_u
        lda     #WE_VBL
        sta     kg_v
        phx
        lda     #0
        jsl     f_wev_push
        plx
@n:     dex
        dex
        bpl     @w
        rts

; ---- $9F win_vbl(A = window, X = 1 on, 0 off) ----
; WE_VBL (16) at every vertical blank while the window's event queue is empty (so they never
; pile up): an event-loop program can draw once a frame without vsync. REV $09+ (ENODEV).
k2_winvbl:
        lda     k_rev
        cmp     #$09
        bcs     :+
        lda     #ENODEV
        jmp     k2_err
:       ldx     cur
        lda     t_x,x
        tay
        lda     t_a,x
        jsl     f_win_arg
        bcc     :+
        jmp     k2_inval
:       tya
        beq     @off
        lda     w_vbl,x
        bne     @ok
        inc     w_vbl,x
        inc     vbl_n
        jsr     vbl_arm
@ok:    jmp     k2_ok0
@off:   lda     w_vbl,x
        beq     @ok
        stz     w_vbl,x
        dec     vbl_n
        bra     @ok
