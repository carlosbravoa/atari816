; mouse.s - the mouse. The I/O processor sends MOUSE events ($E1: dx, dy, wheel signed,
; buttons) while the keyboard is routed to Horizon. Each one moves the pointer position
; (clamped to 0-639, 0-359), updates Marga's hardware pointer at once (this runs from the
; interrupt service, so the pointer stays smooth while tasks compute) and queues an event
; for the input holder in the key queue:
;   motion        usage $0100 | buttons, X = x, Y = y. Consecutive motion events with the
;                 same buttons are coalesced: the queued one takes the latest position.
;   button change usage $0100 | buttons, X = x, Y = y, never coalesced (internal flag
;                 $8000 in the queue, removed by input_read).
;   wheel         usage $0200, X = summed wheel delta (signed). Consecutive ones add up.
; The pointer appears with the first mouse event and is hidden with the desktop while the
; classic machine is shown.

        .a16
        .i16

PTR_X      = $00D920
PTR_Y      = $00D922
PTR_HOT    = $00D924
PTR_IMG    = $00D925
PTR_C1     = $00D928
PTR_IMG_AT = $7FF000                    ; in the framebuffer banks, past the 90 text rows

mouse_init:
        lda     #.loword(ptr_img)       ; image -> $7F:F000 (8-byte aligned, kernel bank)
        sta     kt0
        lda     #KBANK
        sta     kt1
        lda     #.loword(PTR_IMG_AT)
        sta     kt2
        lda     #^PTR_IMG_AT
        sta     kt3
        lda     #3 * 256                ; (the arrow, the drag pointer, the crosshair)
        jsr     kmemcpy
        ldx     #0                      ; the resize pointers after them: 21 rows of 6
        txy                             ; bytes each, the rest transparent
        a8
@rs:    txa
        and     #7
        cmp     #6
        bcs     @z
        txa
        and     #$F8
        cmp     #21 * 8
        bcs     @z
        lda     ptr_rs,y
        iny
        bra     @s
@z:     lda     #0
@s:     sta     f:PTR_IMG_AT + 3 * 256,x
        inx
        cpx     #2 * 256
        bne     @rs
        a16
        lda     #.loword(PTR_IMG_AT)
        sta     f:PTR_IMG
        sta     vs_img
        a8
        lda     #^PTR_IMG_AT
        sta     f:PTR_IMG+2
        sta     vs_img+2
        lda     #0
        sta     f:PTR_HOT
        sta     vs_hot
        sta     vs_shape
        lda     #4                      ; colours: 1 dark outline, 2 white fill, 3 amber
        sta     f:PTR_C1
        sta     vs_pc
        lda     #5
        sta     f:PTR_C1+1
        sta     vs_pc+1
        lda     #2
        sta     f:PTR_C1+2
        sta     vs_pc+2
        a16
        lda     #320
        sta     ms_x
        lda     #180
        sta     ms_y
        stz     ms_btn
        jmp     ptr_update

; write the position to the hardware pointer
ptr_update:
        lda     ms_x
        sta     f:PTR_X
        sta     vs_px
        lda     ms_y
        sta     f:PTR_Y
        sta     vs_py
        rts

; A (signed) * ms_speed (setting 0, 1-4; keeps X, Y)
ms_scale:
        pha
        lda     ms_speed
        cmp     #2
        bcc     @one
        cmp     #5
        bcc     :+
        lda     #4
:       sta     kt7
        pla
        sta     kt5
:       dec     kt7
        beq     :+
        clc
        adc     kt5
        bra     :-
:       rts
@one:   pla
        rts

; one mouse event: ms_dx, ms_dy, ms_dw (signed bytes), ms_nb (buttons). Interrupt service
; or kernel context; may wake the holder, never switches.
mouse_event:
        lda     ms_dx
        jsr     sext8
        jsr     ms_scale
        clc
        adc     ms_x
        bpl     :+
        lda     #0
:       cmp     #640
        bcc     :+
        lda     #639
:       sta     ms_x
        lda     ms_dy
        jsr     sext8
        jsr     ms_scale
        clc
        adc     ms_y
        bpl     :+
        lda     #0
:       cmp     #360
        bcc     :+
        lda     #359
:       sta     ms_y
        jsr     ptr_update
        lda     ms_nb
        and     #$0007
        sta     vs_btn
        lda     fs_act                  ; (0.18: a full screen decides itself)
        bne     :+
        lda     scr_ctrl                ; first event: show the pointer
        bit     #$08
        bne     :+
        ora     #$08
        sta     scr_ctrl
        lda     cls_on
        bne     :+
        lda     scr_ctrl
        jsr     nv_ctrl
:       lda     ws_on                   ; the window system takes the mouse
        beq     :+
        lda     ms_nb
        and     #$0007
        sta     ms_btn
        jmp     ws_mouse
:       lda     ms_nb                   ; buttons changed: an event of its own
        and     #$0007
        cmp     ms_btn
        beq     @motion
        sta     ms_btn
        ora     #$8100
        jsr     ms_push
        bra     @wheel
@motion:
        lda     ms_dx
        ora     ms_dy
        and     #$00FF
        beq     @wheel
        lda     kq_count                ; the last queued event is motion with the same
        beq     @new                    ; buttons: give it the new position
        jsr     kq_last
        lda     kq_usage,y
        and     #$FFF8
        cmp     #$0100
        bne     @new
        lda     kq_usage,y
        and     #$0007
        cmp     ms_btn
        bne     @new
        lda     ms_x
        sta     kq_mods,y
        lda     ms_y
        sta     kq_y,y
        bra     @wheel
@new:   lda     ms_btn
        ora     #$0100
        jsr     ms_push
@wheel: lda     ms_dw
        and     #$00FF
        beq     @out
        jsr     sext8
        sta     kt6
        lda     kq_count
        beq     :+
        jsr     kq_last
        lda     kq_usage,y
        cmp     #$0200
        bne     :+
        lda     kq_mods,y
        clc
        adc     kt6
        sta     kq_mods,y
        rts
:       lda     kt6
        tax
        lda     #$0200
        ldy     #0
        jmp     kq_push
@out:   rts

; queue A with X = x, Y = y
ms_push:
        ldx     ms_x
        ldy     ms_y
        jmp     kq_push

; Y = offset of the last queued entry
kq_last:
        lda     kq_head
        clc
        adc     kq_count
        dec     a
        and     #KQLEN - 1
        asl     a
        tay
        rts

; A = signed byte -> 16 bits
sext8:  and     #$00FF
        cmp     #$0080
        bcc     :+
        ora     #$FF00
:       rts

; ---- $5F mouse_inject(A = dx | dy << 8, X = wheel | buttons << 8): test aid. Feeds an
; event through the same path as one from the I/O processor. ----
sys_minject:
        ldx     cur
        lda     t_a,x
        and     #$00FF
        sta     ms_dx
        lda     t_a,x
        xba
        and     #$00FF
        sta     ms_dy
        lda     t_x,x
        and     #$00FF
        sta     ms_dw
        lda     t_x,x
        xba
        and     #$00FF
        sta     ms_nb
        jsr     mouse_event
        lda     #0
        jmp     set_ok

ptr_img:
        .include "pointer.inc"
        .include "pointer_drag.inc"
        .include "pointer_cross.inc"
ptr_rs:                                 ; (21 rows of 6 bytes each: the Makefile cuts them)
        .include "pointer_hsize.inc"
        .include "pointer_vsize.inc"

; the arrow again (window system end, a task's exit)
ptr_arrow:
        lda     #.loword(PTR_IMG_AT)
        sta     f:PTR_IMG
        sta     vs_img
        a8
        lda     #0
        sta     f:PTR_HOT
        sta     vs_hot
        sta     vs_shape
        a16
        inc     vs_seq
        rts

; ---- $89 ws_pointer(A = 0 arrow, 1 drag (a document), 2 crosshair, 3 column resize,
; 4 row resize) ----
sys_wptr:
        ldx     cur
        lda     t_a,x
        cmp     #5
        bcc     :+
        jmp     err_inval
:       pha
        xba                             ; image: PTR_IMG_AT + shape * 256
        clc
        adc     #.loword(PTR_IMG_AT)
        sta     f:PTR_IMG
        sta     vs_img
        pla
        tax
        a8
        txa
        sta     vs_shape
        lda     ptr_hots,x
        sta     f:PTR_HOT
        sta     vs_hot
        a16
        inc     vs_seq
        lda     #0
        jmp     set_ok
ptr_hots: .byte $00, $00, $44, $55, $55 ; hot spots (2-pixel steps: x | y << 4)

; ---- $8A ws_mouse(A = window or $FF, X, Y = 10-byte buffer) -> A = buttons, X = the
; window under the pointer ($FF: none, the menu bar, or no window system). The buffer:
; {i16 x, i16 y on the screen, i16 x, i16 y in the content of window A (any program's;
; $FF: the screen again), u16 buttons (bit 0 left, 1 right, 2 middle)} ----
sys_wmouse:
        ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #10
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
        stz     kt4                     ; the content origin (0, 0: the screen)
        stz     kt5
        ldx     cur
        lda     t_a,x
        and     #$00FF
        cmp     #$FF
        beq     @put
        ldy     ws_on
        bne     :+
@bad:   jmp     err_inval
:       jsr     win_any
        bcs     @bad
        lda     w_x,x
        clc
        adc     w_cx,x
        sta     kt4
        lda     w_y,x
        clc
        adc     w_cy,x
        sta     kt5
@put:   lda     ms_x
        sta     [kp1]
        sec
        sbc     kt4
        ldy     #4
        sta     [kp1],y
        lda     ms_y
        ldy     #2
        sta     [kp1],y
        sec
        sbc     kt5
        ldy     #6
        sta     [kp1],y
        lda     vs_btn
        ldy     #8
        sta     [kp1],y
        lda     #$FF                    ; the window under the pointer
        ldy     ws_on
        beq     :+
        lda     ms_x
        sta     wm_x
        lda     ms_y
        sta     wm_y
        jsr     wm_hit
        lda     #$FF
        cpx     #NONE
        beq     :+
        lda     w_fl,x
        bit     #WF_OVER
        bne     :+
        txa
        lsr     a
        bra     :++
:       lda     #$FF
:       ldx     cur
        sta     t_x,x
        lda     vs_btn
        jmp     set_ok
