; uisb.s - controls library: the scroll bar (vertical and horizontal). See ui.inc.
; Along the bar: an arrow box (as long as the bar is wide), the track, an arrow box. The
; thumb sits in the track.
        .include "horizon.inc"
        .include "ui.inc"
        .import ui_px, ui_py, ui_rel, ui_setc, ui_ev

        .segment "CODE"
        .a16
        .i16

; the geometry of scroll bar ui_c (SB_POS clamped to SB_MAX)
ui_sb_geom:
        ldx     z:ui_c
        lda     a:CT_TYPE,x
        and     #$00FF
        cmp     #UT_VSCROLL
        bne     @h
        lda     #1
        sta     sb_vert
        lda     a:CT_Y,x
        sta     sb_a0
        lda     a:CT_H,x
        sta     sb_len
        lda     a:CT_X,x
        sta     sb_c0
        lda     a:CT_W,x
        sta     sb_cl
        bra     @tr
@h:     stz     sb_vert
        lda     a:CT_X,x
        sta     sb_a0
        lda     a:CT_W,x
        sta     sb_len
        lda     a:CT_Y,x
        sta     sb_c0
        lda     a:CT_H,x
        sta     sb_cl
@tr:    lda     sb_cl                   ; the track: between the arrow boxes
        asl     a
        eor     #$FFFF
        sec
        adc     sb_len
        bpl     :+
        lda     #0
:       sta     sb_tl
        lda     a:SB_POS,x
        cmp     a:SB_MAX,x
        bcc     :+
        lda     a:SB_MAX,x
        sta     a:SB_POS,x
:       stz     sb_to
        lda     a:SB_MAX,x
        bne     :+
        lda     sb_tl
        sta     sb_th
        rts
:       clc                             ; thumb = track * page / (max + page)
        adc     a:SB_PAGE,x
        bcc     :+
        lda     #$FFFF
:       tay
        lda     a:SB_PAGE,x
        tax
        lda     sb_tl
        jsr     ui_muldiv
        cmp     #10
        bcs     :+
        lda     #10
:       cmp     sb_tl
        bcc     :+
        lda     sb_tl
:       sta     sb_th
        lda     sb_tl                   ; offset = (track - thumb) * pos / max
        sec
        sbc     sb_th
        ldx     z:ui_c
        ldy     a:SB_MAX,x
        pha
        lda     a:SB_POS,x
        tax
        pla
        jsr     ui_muldiv
        sta     sb_to
        rts

; the box at along offset t0 (length t1), cross offset t2 (length t3) -> ui_x .. ui_h
sb_box: lda     sb_vert
        beq     @h
        lda     sb_c0
        clc
        adc     z:ui_t2
        sta     z:ui_x
        lda     z:ui_t3
        sta     z:ui_w
        lda     sb_a0
        clc
        adc     z:ui_t0
        sta     z:ui_y
        lda     z:ui_t1
        sta     z:ui_h
        rts
@h:     lda     sb_c0
        clc
        adc     z:ui_t2
        sta     z:ui_y
        lda     z:ui_t3
        sta     z:ui_h
        lda     sb_a0
        clc
        adc     z:ui_t0
        sta     z:ui_x
        lda     z:ui_t1
        sta     z:ui_w
        rts

; A = op | colour << 8 on the box t0 .. t3
sb_rect:
        pha
        jsr     sb_box
        pla
        jmp     ui_rect

ui_sb_draw:
        jsr     ui_sb_geom
        stz     z:ui_t0                 ; the outline
        lda     sb_len
        sta     z:ui_t1
        stz     z:ui_t2
        lda     sb_cl
        sta     z:ui_t3
        lda     #WD_FRAME | (C_DARK << 8)
        jsr     sb_rect
        lda     sb_tl                   ; the track
        beq     :+
        sta     z:ui_t1
        lda     sb_cl
        sta     z:ui_t0
        lda     #1
        sta     z:ui_t2
        lda     sb_cl
        dec     a
        dec     a
        sta     z:ui_t3
        lda     #WD_FILL | (C_LIGHT << 8)
        jsr     sb_rect
:       lda     #0                      ; the arrows
        ldx     #1
        jsr     sb_arrow
        lda     sb_len
        sec
        sbc     sb_cl
        ldx     #2
        jsr     sb_arrow
        ldx     z:ui_c                  ; the thumb (when there is something to scroll)
        lda     a:SB_MAX,x
        beq     @out
        lda     sb_tl
        cmp     #10
        bcc     @out
        lda     sb_cl
        clc
        adc     sb_to
        sta     z:ui_t0
        lda     sb_th
        sta     z:ui_t1
        stz     z:ui_t2
        lda     sb_cl
        sta     z:ui_t3
        lda     #WD_FRAME | (C_DARK << 8)
        jsr     sb_rect
        jsr     sb_in
        lda     #WD_FILL | (C_BODY << 8)
        jsr     sb_rect
        lda     #0
        jsr     ui_bevel
        lda     sb_th                   ; three grip lines in its middle
        cmp     #16
        bcc     @out
        lsr     a
        clc
        adc     z:ui_t0
        sec
        sbc     #3
        sta     z:ui_t0
        lda     #4
        sta     z:ui_t2
        lda     sb_cl
        sec
        sbc     #8
        sta     z:ui_t3
        lda     #1
        sta     z:ui_t1
        ldx     #3
:       phx
        lda     #WD_FILL | (C_MID << 8)
        jsr     sb_rect
        inc     z:ui_t0
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     sb_rect
        inc     z:ui_t0
        plx
        dex
        bne     :-
@out:   rts
sb_in:  inc     z:ui_t0                 ; the box t0 .. t3 one pixel smaller
        inc     z:ui_t2
        dec     z:ui_t1
        dec     z:ui_t1
        dec     z:ui_t3
        dec     z:ui_t3
        rts

; the arrow box at along offset A; X = 1 the "-" arrow, 2 the "+" arrow
sb_arrow:
        sta     sb_ao
        stx     sb_dir
        sta     z:ui_t0
        lda     sb_cl
        sta     z:ui_t1
        sta     z:ui_t3
        stz     z:ui_t2
        lda     #WD_FRAME | (C_DARK << 8)
        jsr     sb_rect
        jsr     sb_in
        ldx     z:ui_c
        lda     a:SB_PART,x
        cmp     sb_dir
        bne     :+
        lda     #WD_FILL | (C_LIGHT << 8)
        jsr     sb_rect
        lda     #1
        bra     :++
:       lda     #WD_FILL | (C_BODY << 8)
        jsr     sb_rect
        lda     #0
:       jsr     ui_bevel
        lda     #C_BLACK                ; the triangle: rows of 2, 4, 6, 8 pixels
        ldx     z:ui_c
        ldy     a:SB_MAX,x
        bne     :+
        lda     #C_MID
:       xba
        ora     #WD_FILL
        sta     sb_col
        lda     #1
        sta     z:ui_t1
        ldx     #0
@k:     phx
        txa                             ; along: base + k ("-": the point first) or 3 - k
        ldy     sb_dir
        cpy     #1
        beq     :+
        eor     #$FFFF
        clc
        adc     #4
:       sta     z:ui_t0
        lda     sb_cl
        lsr     a
        dec     a
        dec     a
        clc
        adc     sb_ao
        adc     z:ui_t0
        sta     z:ui_t0
        lda     sb_cl                   ; cross: (cl / 2 - 1 - k), 2k + 2 wide
        lsr     a
        dec     a
        sec
        sbc     1,s
        sta     z:ui_t2
        lda     1,s
        asl     a
        inc     a
        inc     a
        sta     z:ui_t3
        lda     sb_col
        jsr     sb_rect
        plx
        inx
        cpx     #4
        bcc     @k
        rts

; the pointer's along position (relative) -> A
sb_along:
        lda     sb_vert
        beq     :+
        lda     ui_py
        rts
:       lda     ui_px
        rts

; SB_POS -= A (at least 0); SB_POS += A (at most SB_MAX) -> C set: changed
sb_dec: sta     z:ui_t0
        ldx     z:ui_c
        lda     a:SB_POS,x
        sec
        sbc     z:ui_t0
        bcs     sb_set
        lda     #0
        bra     sb_set
sb_inc: sta     z:ui_t0
        ldx     z:ui_c
        lda     a:SB_POS,x
        clc
        adc     z:ui_t0
        bcs     :+
        cmp     a:SB_MAX,x
        bcc     sb_set
:       lda     a:SB_MAX,x
sb_set: cmp     a:SB_POS,x
        beq     :+
        sta     a:SB_POS,x
        sec
        rts
:       clc
        rts

; a press (ui_px, ui_py relative to the bar)
ui_sb_press:
        jsr     ui_sb_geom
        lda     sb_to                   ; (the thumb as drawn)
        sta     sb_oto
        jsr     sb_along
        sta     z:ui_t5
        ldx     z:ui_c
        cmp     sb_cl
        bcs     :+
        lda     #1                      ; the "-" arrow
        sta     a:SB_PART,x
        lda     a:SB_STEP,x
        jsr     sb_dec
        bra     @drawn
:       lda     sb_len
        sec
        sbc     sb_cl
        cmp     z:ui_t5
        beq     :+
        bcs     @track
:       lda     #2                      ; the "+" arrow
        sta     a:SB_PART,x
        lda     a:SB_STEP,x
        jsr     sb_inc
        bra     @drawn
@track: lda     a:SB_MAX,x
        beq     @used
        lda     z:ui_t5
        sec
        sbc     sb_cl
        sec
        sbc     sb_to
        bcs     :+
        lda     a:SB_PAGE,x             ; above the thumb
        jsr     sb_dec
        bra     @drawn
:       cmp     sb_th
        bcc     :+
        lda     a:SB_PAGE,x             ; below it
        jsr     sb_inc
        bra     @drawn
:       sta     a:SB_GRAB,x             ; on it: a drag
        lda     #3
        sta     a:SB_PART,x
@used:  lda     #UA_USED
        rts
@drawn: php                             ; the arrow pressed, the thumb moved
        ldx     z:ui_c
        lda     a:SB_PART,x
        beq     :+
        jsr     sb_arrowp
:       jsr     sb_thumbmv
        plp
        bcc     @used
        lda     #UA_CHANGE
        rts

; motion / release
ui_sb_drag:
        jsr     ui_sb_geom
        lda     sb_to                   ; (the thumb as drawn)
        sta     sb_oto
        ldx     z:ui_c
        lda     ui_rel
        beq     @mot
        lda     a:SB_PART,x
        stz     a:SB_PART,x
        cmp     #3
        bcs     :+
        cmp     #0
        beq     :+
        jsr     sb_arrowp               ; an arrow comes up
:       lda     #UA_USED
        rts
@mot:   lda     a:SB_PART,x
        cmp     #3
        bne     :-
        jsr     sb_along
        sec
        sbc     sb_cl
        sec
        sbc     a:SB_GRAB,x
        bpl     :+
        lda     #0
:       sta     z:ui_t5
        lda     sb_tl
        sec
        sbc     sb_th
        sta     z:ui_t4                 ; the thumb's range
        cmp     z:ui_t5
        bcs     :+
        sta     z:ui_t5
:       ldy     z:ui_t4                 ; pos = offset * max / range (rounded)
        lda     a:SB_MAX,x
        tax
        lda     z:ui_t5
        jsr     ui_muldiv
        ldx     z:ui_c
        jsr     sb_set
        bcc     :---
        jsr     sb_thumbmv
        lda     #UA_CHANGE
        rts

; a wheel event (ui_ev+2 = signed steps, > 0 up): 3 steps a notch
ui_sb_wheel:
        jsr     ui_sb_geom
        lda     sb_to                   ; (the thumb as drawn)
        sta     sb_oto
        ldx     z:ui_c
        lda     a:SB_STEP,x
        sta     z:ui_t0
        asl     a
        adc     z:ui_t0
        sta     z:ui_t1                 ; 3 steps
        lda     ui_ev+2
        bpl     :+
        eor     #$FFFF
        inc     a
:       ldx     z:ui_t1
        ldy     #1
        jsr     ui_muldiv               ; |notches| * 3 steps
        tax
        lda     ui_ev+2
        bmi     :+
        txa
        jsr     sb_dec
        bra     :++
:       txa
        jsr     sb_inc
:       bcs     :+
        lda     #UA_USED
        rts
:       jsr     sb_thumbmv
        lda     #UA_CHANGE
        rts

; X = scroll bar, A = position: set (clamped) and drawn
ui_sbset:
        sta     a:SB_POS,x
        jsr     ui_setc
        jmp     ui_sb_draw

; X = scroll bar, A = position: set (clamped); only the thumb is redrawn (the bar must be
; drawn with its SB_POS, SB_MAX and SB_PAGE before: only the position changes)
ui_sbpos:
        pha
        jsr     ui_setc
        jsr     ui_sb_geom
        lda     sb_to
        sta     sb_oto
        pla
        ldx     z:ui_c
        sta     a:SB_POS,x
        ; fall through
; the thumb of bar ui_c from its drawn place (offset sb_oto) to its place now: one copy of
; it (WD_COPY) and the track filled where it was
sb_thumbmv:
        jsr     ui_sb_geom
        ldx     z:ui_c
        lda     a:SB_MAX,x              ; (no thumb shown)
        jeq     @out
        lda     sb_tl
        cmp     #10
        jcc     @out
        lda     sb_to
        cmp     sb_oto
        jeq     @out
        lda     sb_cl                   ; the old thumb's box
        clc
        adc     sb_oto
        sta     z:ui_t0
        lda     sb_th
        sta     z:ui_t1
        stz     z:ui_t2
        lda     sb_cl
        sta     z:ui_t3
        jsr     sb_box
        lda     sb_a0                   ; the new place (along)
        clc
        adc     sb_cl
        adc     sb_to
        ldy     sb_vert
        beq     :+
        tay
        ldx     z:ui_x
        bra     :++
:       tax
        ldy     z:ui_y
:       jsr     ui_copy
        lda     sb_to                   ; the track where the thumb was and is no more
        cmp     sb_oto
        bcc     @up
        lda     sb_oto                  ; moved on: [old, min(old end, new))
        clc
        adc     sb_th
        cmp     sb_to
        bcc     :+
        lda     sb_to
:       sec
        sbc     sb_oto
        sta     z:ui_t1
        lda     sb_oto
        bra     @fill
@up:    lda     sb_to                   ; moved back: [max(new end, old), old end)
        clc
        adc     sb_th
        cmp     sb_oto
        bcs     :+
        lda     sb_oto
:       sta     z:ui_t0
        lda     sb_oto
        clc
        adc     sb_th
        sec
        sbc     z:ui_t0
        sta     z:ui_t1
        lda     z:ui_t0
@fill:  clc
        adc     sb_cl
        sta     z:ui_t0
        lda     #1
        sta     z:ui_t2
        lda     sb_cl
        dec     a
        dec     a
        sta     z:ui_t3
        lda     #WD_FILL | (C_LIGHT << 8)
        jmp     sb_rect
@out:   rts

; arrow A (1 the "-" arrow, 2 the "+" arrow) redrawn (pressed if it is SB_PART)
sb_arrowp:
        cmp     #1
        bne     :+
        tax
        lda     #0
        jmp     sb_arrow
:       lda     sb_len
        sec
        sbc     sb_cl
        ldx     #2
        jmp     sb_arrow

        .segment "BSS"
sb_vert: .res   2
sb_a0:  .res    2
sb_len: .res    2
sb_c0:  .res    2
sb_cl:  .res    2
sb_tl:  .res    2
sb_th:  .res    2
sb_to:  .res    2
sb_ao:  .res    2
sb_dir: .res    2
sb_col: .res    2
sb_oto: .res    2
