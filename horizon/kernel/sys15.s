; sys15.s - syscalls of 0.15: joystick, vsync (sound_chime is in sound.s, win_popup in
; ws15.s).
        .a16
        .i16

JOY_PORT    = $00DE21
JOY_TRIG    = $00DE22
NV_LINE     = $00D906
TM1_RELOAD  = $00DE14
TM1_CTRL    = $00DE17
IRQ_VBLANK  = $01
IRQ_TIMER1  = $08

; ---- $55 joystick(A = 0) -> A = directions, X = triggers ----
; A: bits 0-3 port 1 (up, down, left, right), bits 4-7 port 2; X: bit 0 port 1's trigger,
; bit 1 port 2's; 1 = pressed (JOY_PORT, JOY_TRIG). A = 1 (test aid): X = directions and
; Y = triggers are ORed into what the ports give from now on (0, 0: off).
sys_joy:
        ldx     cur
        lda     t_a,x
        beq     @read
        cmp     #1
        beq     :+
        jmp     err_inval
:       lda     t_x,x
        and     #$00FF
        sta     joy_tx
        lda     t_y,x
        and     #$0003
        sta     joy_ty
        lda     #0
        jmp     set_ok
@read:  a8
        lda     f:JOY_TRIG
        a16
        and     #$0003
        ora     joy_ty
        sta     t_x,x
        a8
        lda     f:JOY_PORT
        a16
        and     #$00FF
        ora     joy_tx
        jmp     set_ok

; ---- $0F vsync() -> A = the frame counter (REV $09+: NV_FRAME; before: the vertical blanks
; waited for so far by any task; wraps) ----
; Blocks until the next vertical blank begins (NV_LINE 360). Interruptible by kill.
; (0.18) From REV $09 Marga's VBLANK interrupt ends the wait (it comes at the beam, and the
; same interrupt applies sprites, full-screen scrolling and the raster table: k2vbl.s). Before
; REV $09 the moment is derived from the raster position: TIMER1 is set to go off when NV_LINE
; reaches 360 (lines of 43.86 us, 380 a frame), with the VBLANK interrupt enabled as well, and
; whichever comes first ends the wait (vs_irq).
sys_vsync:
        lda     vs_frame
        pha
        jsr     vs_arm
@w:     ldx     cur
        lda     t_killed,x
        bne     @done
        lda     vs_frame
        cmp     1,s
        bne     @done
        lda     #W_VSYNC
        ldy     #0
        jsr     k_block
        bra     @w
@done:  pla
        jsl     k2_lwait                ; (0.18) the caller's draw list done, seen by the CPU
        jsl     k2_frameval             ; (0.18) NV_FRAME from REV $09
        jmp     set_ok

; the next vertical blank wakes the W_VSYNC waiters: TIMER1 from NV_LINE, and VBLANK
vs_arm: lda     vs_armed
        beq     :+
        rts
:       inc     vs_armed
        lda     k_rev                   ; (0.18) REV $09+: the VBLANK interrupt alone
        cmp     #$09
        bcc     @line
        a8
        lda     #IRQ_VBLANK
        sta     f:IRQ_STATUS            ; (a stale latch)
        lda     f:IRQ_EN
        ora     #IRQ_VBLANK
        sta     f:IRQ_EN
        a16
        rts
@line:  a8                              ; the raster line (read low, then high; again if
        lda     f:NV_LINE               ; torn)
        xba
        lda     f:NV_LINE+1
        xba
        a16
        cmp     #366
        bcs     @line
        cmp     #360                    ; lines to the next 360 (+1: never early)
        bcs     :+
        eor     #$FFFF
        sec
        adc     #361
        bra     :++
:       eor     #$FFFF                  ; (in the blank: 380 - (line - 360) + 1)
        sec
        adc     #741
:       sta     kt0                     ; microseconds: lines * 44 (43.86 a line)
        asl     a
        asl     a
        clc
        adc     kt0                     ; * 5
        asl     a
        clc
        adc     kt0                     ; * 11
        asl     a
        asl     a                       ; * 44
        a8
        sta     f:TM1_RELOAD
        xba
        sta     f:TM1_RELOAD+1
        lda     #0
        sta     f:TM1_RELOAD+2
        sta     f:TM1_CTRL              ; (stopped: RUN reloads the count)
        lda     #IRQ_VBLANK | IRQ_TIMER1
        sta     f:IRQ_STATUS            ; (stale latches)
        lda     #1
        sta     f:TM1_CTRL              ; one shot
        lda     f:IRQ_EN
        ora     #IRQ_VBLANK | IRQ_TIMER1
        sta     f:IRQ_EN
        a16
        rts

; (irq_service, A8) VBLANK or TIMER1 latched while a vertical blank is awaited: the
; waiters go on, both sources are off again
        .a8
vs_irq: lda     k_rev                   ; (0.18) REV $09+: the VBLANK interrupt, at the beam
        cmp     #$09
        bcc     @old
        lda     f:IRQ_STATUS
        and     #IRQ_VBLANK
        beq     @out
        sta     f:IRQ_STATUS
        a16
        jsl     k2_vbl                  ; sprites, full screen, raster table: A <> 0 keeps it on
        pha
        lda     vs_armed
        beq     :+
        stz     vs_armed
        inc     vs_frame
        lda     #W_VSYNC
        ldy     #0
        jsr     k_wake_all
:       pla
        a8
        bne     @out
        lda     f:IRQ_EN
        and     #$FF ^ IRQ_VBLANK
        sta     f:IRQ_EN
        rts
@old:   lda     f:IRQ_STATUS
        and     #IRQ_VBLANK | IRQ_TIMER1
        beq     @out
        a16
        lda     vs_armed
        a8
        beq     @out
        lda     #0
        sta     f:TM1_CTRL
        lda     f:IRQ_EN
        and     #$FF ^ (IRQ_VBLANK | IRQ_TIMER1)
        sta     f:IRQ_EN
        lda     #IRQ_VBLANK | IRQ_TIMER1
        sta     f:IRQ_STATUS
        a16
        stz     vs_armed
        inc     vs_frame
        lda     #W_VSYNC
        ldy     #0
        jsr     k_wake_all
        a8
@out:   rts
        .a16
