; bas_gfx.s - the graphics window (SCREEN and the drawing statements) and sound.
;
; SCREEN w, h opens a window of w x h pixels in 256 colours (the system palette: 0-15 the
; UI colours, 16-231 a 6x6x6 cube, 232-255 greys). The program draws into a copy of it in
; memory (GB banks: the "shadow"; stride a power of two >= w, so a bank holds 65536 /
; stride rows), which POINT reads back. PLOT, LINE, CIRCLE and TEXT draw into the shadow
; and grow a dirty rectangle; gfx_flush shows it with one blit per bank (win_draw op 8:
; one blitter COPY on REV $08) at the periodic flush, before waits and at the end. RECT,
; FRECT and GCLS also draw straight into the window with win_draw (one blitter FILL), so
; large fills never wait for a blit; the shadow gets the same pixels, so the two always
; agree. Any drawing statement without a window opens a 320 x 200 one.
; Coordinates are clipped to the window. TEXT uses the 8x12 font (kernel/font.inc).
;
; Sound: POKEY 2 through sound_write ($66): voice v (0-3) = AUDF at register 2 v, AUDC at
; 2 v + 1. SOUND v, f, vol plays f Hz (pure tone, 125-15980 Hz: AUDF = 31960 / f - 1, the
; 64 kHz clock); SOUND v, pitch, distortion, vol is Atari BASIC's form (raw AUDF, AUDC =
; distortion * 16 + vol). SOUND alone, END, Esc and errors silence all four.

        .segment "CODE"
        .a16
        .i16
GMAXW   = 636
GMAXH   = 324
GBANKS  = 32                            ; (full screen: up to 2 MB)

; ---------------------------------------------------------------- SCREEN
; SCREEN w, h: the graphics window; SCREEN 0: closed. (2.0) SCREEN 1 [, w, h] and SCREEN 2
; [, w, h]: full screen, 320 x 180 or 640 x 360, a drawing area of w x h (bas_game.s).
st_screen:
        jsr     eval_u16
        sta     sc_w
        cmp     #3
        bcs     @win
        cmp     #0
        bne     @fs
        jsr     at_end                  ; SCREEN 0: closed
        bne     @win
        jsr     gfx_close
        jmp     stmt_end
@fs:    jsr     fs_screen
        jmp     stmt_end
@win:   lda     #','
        jsr     expect
        jsr     eval_u16
        sta     sc_h
        lda     sc_w
        jsr     gfx_open
        jmp     stmt_end

; a window of sc_w x sc_h (the same size: cleared and brought to the front)
gfx_open:
        lda     sc_w
        cmp     #16
        bcc     @bad
        cmp     #GMAXW + 1
        bcs     @bad
        lda     sc_h
        cmp     #16
        bcc     @bad
        cmp     #GMAXH + 1
        bcs     @bad
        lda     gwin
        bmi     @new
        lda     gmode                   ; (full screen before: a new window)
        beq     :+
        jsr     gfx_close
        bra     @new
:       lda     sc_w
        cmp     gwid
        bne     @move
        lda     sc_h
        cmp     ghgt
        bne     @move
        lda     gwin                    ; (in front, with the focus: its sprites show)
        sys     SYS_WFRONT
        lda     #0
        jmp     gfx_clear
@move:  jsr     gfx_here                ; another size: closed and opened at its place
        jsr     gfx_close
        bra     @open
@bad:   err     E_ARG
@new:   jsr     gfx_corner
@open:  lda     sc_w
        sta     gopen+4
        sta     gwid
        sta     gww
        lda     sc_h
        sta     gopen+6
        sta     ghgt
        sta     gwh
        lda     #16                     ; the stride: a power of two >= w
        ldx     #4
:       cmp     gwid
        bcs     :+
        asl     a
        inx
        bra     :-
:       sta     gstride
        stx     gshift
        jsr     gfx_rpb
        stz     gnb                     ; the banks
        lda     #0
@bk:    cmp     ghgt
        bcs     @rows
        pha
        sys     SYS_BALLOC
        bcc     :+
        pla
        jsr     gfx_free
        err     E_MEM
:       ldx     gnb
        sta     gbk,x
        inx
        inx
        stx     gnb
        pla
        clc
        adc     grpb
        bra     @bk
@rows:  jsr     gfx_rows
        jsr     gfx_wopen
        lda     #0
        ; fall through
; the whole drawing area in colour A
gfx_clear:
        sta     gc_col
        stz     fr_x
        stz     fr_y
        lda     gwid
        sta     fr_w
        lda     ghgt
        sta     fr_h
        jmp     fill_rect

; rows per bank: 65536 / stride -> grpb
gfx_rpb:
        lda     #16
        sec
        sbc     gshift
        tax
        lda     #1
:       asl     a
        dex
        bne     :-
        sta     grpb
        rts

; the row table (window memory): the bank and offset of each of the ghgt rows, grpb rows
; to each bank of gbk
gfx_rows:
        stz     z:t1
        ldy     #0                      ; (Y: the row in its bank, X: row * 2)
        ldx     #0
@r:     txa
        lsr     a
        cmp     ghgt
        bcs     @out
        phx
        ldx     z:t1
        lda     gbk,x
        plx
        sta     f:WIN_ROWB,x
        tya
        phx
        ldx     gshift
:       asl     a
        dex
        bne     :-
        plx
        sta     f:WIN_ROWO,x
        iny
        cpy     grpb
        bcc     :+
        ldy     #0
        inc     z:t1
        inc     z:t1
:       inx
        inx
        bra     @r
@out:   rts

; the window's place: the bottom right of the screen for a gww x gwh content (sc_w, sc_h)
gfx_corner:
        lda     #640 - 2 - 8
        sec
        sbc     sc_w
        sta     gopen
        lda     #360 - 17 - 6
        sec
        sbc     sc_h
        cmp     #16
        bcs     :+
        lda     #16
:       sta     gopen+2
        rts
; ... or where the window is now
gfx_here:
        lda     gwin
        ptr     ginfo
        sys     SYS_WINFO
        lda     ginfo
        dec     a
        sta     gopen
        lda     ginfo+2
        sec
        sbc     #15
        sta     gopen+2
        rts

; the window opened (gopen; content gww x gwh): it has the focus
gfx_wopen:
        lda     gww
        sta     gopen+4
        lda     gwh
        sta     gopen+6
        lda     codebk
        sta     gopen+10
        ptr     gopen
        sys     SYS_WOPEN
        bcc     :+
        jsr     gfx_free
        err     E_MEM
:       sta     gwin
        ptr     menus
        sys     SYS_WMENU
        lda     #1
        sta     gcolor
        sta     gfocus
        rts

; the window's banks back
gfx_free:
        ldx     #0
:       cpx     gnb
        bcs     :+
        phx
        lda     gbk,x
        sys     SYS_BFREE
        plx
        inx
        inx
        bra     :-
:       stz     gnb
        rts

; the window closed (SCREEN 0, its close box, another SCREEN), full screen too; its sprites
; go with it (the kernel frees them; BASIC's table stays, for the next window)
gfx_close:
        lda     gwin
        bmi     @out
        jsr     dl_drop
        lda     fsact
        beq     :+
        lda     gwin
        sys     SYS_FSLEAVE
        stz     fsact
:       lda     gwin
        sys     SYS_WCLOSE
        lda     #$FFFF
        sta     gwin
        sta     sp_first
        sta     sp_dirty
        stz     gdirty
        lda     gmode
        beq     :+
        jsr     fs_forget
:       stz     gmode
        jsr     gfx_free
@out:   rts

; no window: a 320 x 200 one (unless its close box just stopped the program)
gfx_need:
        lda     gwin
        bpl     :+
        lda     brkf
        jne     do_break
        lda     #320
        sta     sc_w
        lda     #200
        sta     sc_h
        jsr     gfx_open
:       rts
; the same for drawing with the CPU: in full screen, Ali's drawing before it done first
gfx_cpu:
        jsr     gfx_need
        jmp     dl_sync

; ---------------------------------------------------------------- the dirty rectangle
; grow it by x0 = t0, y0 = t1, x1 = t2, y1 = t3 (exclusive), already clipped
dirty:  lda     gdirty
        bne     :+
        lda     z:t0
        sta     gdx0
        lda     z:t1
        sta     gdy0
        lda     z:t2
        sta     gdx1
        lda     z:t3
        sta     gdy1
        lda     #1
        sta     gdirty
        rts
:       lda     z:t0
        cmp     gdx0
        bcs     :+
        sta     gdx0
:       lda     z:t1
        cmp     gdy0
        bcs     :+
        sta     gdy0
:       lda     z:t2
        cmp     gdx1
        bcc     :+
        sta     gdx1
:       lda     z:t3
        cmp     gdy1
        bcc     :+
        sta     gdy1
:       rts
; all of the window
dirty_all:
        stz     gdx0
        stz     gdy0
        lda     gww
        sta     gdx1
        lda     gwh
        sta     gdy1
        lda     #1
        sta     gdirty
        rts

; the box of signed x0 = t0, y0 = t1, x1 = t2, y1 = t3 (inclusive) clipped, then dirty
dirty_box:
        lda     z:t0
        bpl     :+
        stz     z:t0
:       lda     z:t1
        bpl     :+
        stz     z:t1
:       lda     z:t2
        bmi     @out
        inc     a
        cmp     gwid
        bcc     :+
        lda     gwid
:       sta     z:t2
        lda     z:t3
        bmi     @out
        inc     a
        cmp     ghgt
        bcc     :+
        lda     ghgt
:       sta     z:t3
        lda     z:t0
        cmp     z:t2
        bcs     @out
        lda     z:t1
        cmp     z:t3
        bcs     @out
        jmp     dirty
@out:   rts

; the window shows the shadow's dirty rectangle: a blit per bank (keeps t0-t7). In full
; screen the window shows the top left of the drawing area, while the full screen is not
; shown (another window in front, or the program stopped).
gfx_flush:
        lda     gwin
        jmi     @out
        lda     gdirty
        jeq     @out
        stz     gdirty
        lda     gmode
        beq     @clip
        lda     fsact
        beq     :+
        lda     gfocus
        jne     @out
:       jsr     dl_sync
@clip:  lda     gdx1
        cmp     gww
        bcc     :+
        lda     gww
        sta     gdx1
:       lda     gdy1
        cmp     gwh
        bcc     :+
        lda     gwh
        sta     gdy1
:       lda     gdx0
        cmp     gdx1
        jcs     @out
        lda     gdy0
        cmp     gdy1
        jcs     @out
        sta     gf_y
        lda     gmode                   ; (full screen: row by row, bas_game.s)
        jne     fs_flush
@band:  lda     gf_y
        cmp     gdy1
        bcs     @out
        asl     a                       ; the rows of this bank from gf_y
        tax
        lda     f:WIN_ROWB,x
        sta     gblk+14
        lda     f:WIN_ROWO,x
        clc
        adc     gdx0
        sta     gblk+12
        lda     gf_y                    ; the bank's end: the next multiple of grpb
        ldx     #0
:       cmp     grpb
        bcc     :+
        sbc     grpb
        inx
        bra     :-
:       sta     gf_t0
        lda     grpb
        sec
        sbc     gf_t0
        clc
        adc     gf_y
        cmp     gdy1
        bcc     :+
        lda     gdy1
:       sta     gf_t1                    ; the band's end
        lda     #WD_SBLIT
        sta     gblk
        lda     gstride
        sta     gblk+1
        lda     gdx0
        sta     gblk+4
        lda     gf_y
        sta     gblk+6
        lda     gdx1
        sec
        sbc     gdx0
        sta     gblk+8
        lda     gf_t1
        sec
        sbc     gf_y
        sta     gblk+10
        lda     gwin
        ptr     gblk
        sys     SYS_WDRAW
        lda     gf_t1
        sta     gf_y
        brl     @band
@out:   rts

; ---------------------------------------------------------------- pixels
; pixel x = A, y = X in colour gc_col (clipped; not marked dirty)
pset:   cmp     gwid
        bcs     @out
        cpx     ghgt
        bcs     @out
        sta     z:t7
        txa
        asl     a
        tax
        lda     f:WIN_ROWO,x
        clc
        adc     z:t7
        sta     z:gq
        lda     f:WIN_ROWB,x
        adc     #0                      ; (full screen: a row may run into the next bank)
        sta     z:gq+2
        lda     gc_col
        a8
        sta     [gq]
        a16
@out:   rts

; the colour after COLOR
st_color:
        jsr     eval_u16
        cmp     #256
        bcc     :+
        err     E_ARG
:       sta     gcolor
        jmp     stmt_end

; two numbers "a, b" -> t0, t1 (signed 16-bit, clamped)
two_args:
        jsr     eval_s16
        pha
        lda     #','
        jsr     expect
        jsr     eval_s16
        sta     z:t1
        pla
        sta     z:t0
        rts
; a coordinate: a number (rounded) clamped to -4000..4000 -> A
eval_s16:
        jsr     eval_clamp
        lda     fhi
        bmi     @neg
        bne     @max
        lda     flo
        cmp     #4001
        bcs     @max
        rts
@max:   lda     #4000
        rts
@neg:   cmp     #$FFFF
        bne     @min
        lda     flo
        cmp     #$10000 - 4000
        bcc     @min
        rts
@min:   lda     #$10000 - 4000
        rts

st_plot:
        jsr     gfx_cpu
        jsr     two_args
        lda     gcolor
        sta     gc_col
        lda     z:t0
        ldx     z:t1
        jsr     pset
        lda     z:t0
        sta     z:t2
        lda     z:t1
        sta     z:t3
        jsr     dirty_box
        jmp     stmt_end

; LINE x1, y1, x2, y2 (Bresenham)
st_line:
        jsr     gfx_cpu
        jsr     two_args
        lda     z:t0
        sta     ln_x
        lda     z:t1
        sta     ln_y
        lda     #','
        jsr     expect
        jsr     two_args
        lda     z:t0
        sta     ln_x2
        lda     z:t1
        sta     ln_y2
        lda     gcolor
        sta     gc_col
        jsr     draw_line
        jmp     stmt_end

; a line ln_x, ln_y -> ln_x2, ln_y2 in gc_col, marked dirty
draw_line:
        lda     ln_x                    ; the box
        ldx     ln_x2
        jsr     minmax
        sta     z:t0
        stx     z:t2
        lda     ln_y
        ldx     ln_y2
        jsr     minmax
        sta     z:t1
        stx     z:t3
        jsr     dirty_box
        lda     ln_x2                   ; dx = |x2 - x1|, sx; dy = -|y2 - y1|, sy
        sec
        sbc     ln_x
        ldx     #1                      ; (LDX sets N: test the difference again)
        cmp     #0
        bvc     :+
        eor     #$8000
:       bpl     :+
        ldx     #$FFFF
:       stx     ln_sx
        lda     ln_x2
        sec
        sbc     ln_x
        cpx     #1
        beq     :+
        eor     #$FFFF
        inc     a
:       sta     ln_dx
        lda     ln_y2
        sec
        sbc     ln_y
        ldx     #1                      ; (LDX sets N: test the difference again)
        cmp     #0
        bvc     :+
        eor     #$8000
:       bpl     :+
        ldx     #$FFFF
:       stx     ln_sy
        lda     ln_y2
        sec
        sbc     ln_y
        cpx     #1
        bne     :+
        eor     #$FFFF
        inc     a
:       sta     ln_dy                   ; (negative)
        clc
        adc     ln_dx
        sta     ln_err
@l:     lda     ln_x
        ldx     ln_y
        jsr     pset
        lda     ln_x
        cmp     ln_x2
        bne     :+
        lda     ln_y
        cmp     ln_y2
        beq     @out
:       lda     ln_err                  ; e2 = 2 err
        asl     a
        sta     z:t7
        sec                             ; e2 >= dy: x step
        sbc     ln_dy
        bvc     :+
        eor     #$8000
:       bmi     :+
        lda     ln_err
        clc
        adc     ln_dy
        sta     ln_err
        lda     ln_x
        clc
        adc     ln_sx
        sta     ln_x
:       lda     ln_dx                   ; e2 <= dx: y step
        sec
        sbc     z:t7
        bvc     :+
        eor     #$8000
:       bmi     @l
        lda     ln_err
        clc
        adc     ln_dx
        sta     ln_err
        lda     ln_y
        clc
        adc     ln_sy
        sta     ln_y
        bra     @l
@out:   rts

; A, X (signed) -> A = the smaller, X = the larger
minmax: sta     z:t7
        stx     z:t6
        sec
        sbc     z:t6
        bvc     :+
        eor     #$8000
:       bmi     :+
        lda     z:t6
        ldx     z:t7
        rts
:       lda     z:t7
        ldx     z:t6
        rts

; RECT x, y, w, h (a frame), FRECT x, y, w, h (filled)
st_rect:
        lda     #WD_FRAME
        pha
        jsr     gfx_cpu
        bra     :+
st_frect:
        lda     #WD_FILL
        pha
        jsr     gfx_need
:
        jsr     two_args
        lda     z:t0
        sta     fr_x
        lda     z:t1
        sta     fr_y
        lda     #','
        jsr     expect
        jsr     two_args
        lda     z:t0
        sta     fr_w
        lda     z:t1
        sta     fr_h
        lda     gcolor
        sta     gc_col
        pla
        cmp     #WD_FILL
        beq     :+
        jsr     frame_rect
        jmp     stmt_end
:       jsr     fill_rect
        jmp     stmt_end

; the box fr_x, fr_y, fr_w, fr_h (signed) clipped -> t0, t1, t2, t3 (x0, y0, x1, y1
; exclusive); C set if nothing is left
clip_box:
        lda     fr_w
        bmi     @none
        beq     @none
        lda     fr_h
        bmi     @none
        beq     @none
        lda     fr_x
        clc
        adc     fr_w
        bvs     @none
        bmi     @none
        beq     @none
        cmp     gwid
        bcc     :+
        lda     gwid
:       sta     z:t2
        lda     fr_y
        clc
        adc     fr_h
        bvs     @none
        bmi     @none
        beq     @none
        cmp     ghgt
        bcc     :+
        lda     ghgt
:       sta     z:t3
        lda     fr_x
        bpl     :+
        lda     #0
:       sta     z:t0
        cmp     z:t2
        bcs     @none
        lda     fr_y
        bpl     :+
        lda     #0
:       sta     z:t1
        cmp     z:t3
        bcs     @none
        clc
        rts
@none:  sec
        rts

; a filled box fr_* in gc_col: the shadow, and the window directly
fill_rect:
        jsr     clip_box
        bcs     @out
        lda     gmode                   ; (full screen: Ali fills, bas_game.s; while the
        beq     @win                    ; desktop is shown, the CPU)
        lda     fsact
        beq     :+
        jmp     fs_fill
:       jsr     dirty
        bra     @cpu
@win:   lda     #WD_FILL
        jsr     win_box
@cpu:
        lda     z:t1
        sta     z:t5
@row:   lda     z:t5                    ; each row: the first pixel, then copied on
        cmp     z:t3
        bcs     @out
        asl     a
        tax
        lda     f:WIN_ROWO,x
        clc
        adc     z:t0
        sta     z:gq
        lda     f:WIN_ROWB,x
        adc     #0                      ; (full screen: a row may run into the next bank)
        sta     z:gq+2
        lda     z:t2
        sec
        sbc     z:t0
        tay                             ; Y = the width
        lda     gc_col
        and     #$00FF
        sta     z:t6
        xba
        ora     z:t6                    ; colour in both bytes
        dey
        beq     @one
@pair:  dey
        sta     [gq],y
        beq     @next
        dey
        bne     @pair
@one:   a8
        sta     [gq]
        a16
@next:  inc     z:t5
        bra     @row
@out:   rts

; a frame fr_* in gc_col: four lines in the shadow, the frame directly
frame_rect:
        jsr     clip_box
        bcs     @out
        lda     gmode                   ; (full screen: the box marked for the window)
        beq     :+
        jsr     dirty
        bra     :++
:       lda     #WD_FRAME
        jsr     win_box
:
        lda     fr_x                    ; the four sides as lines
        sta     ln_x
        sta     ln_x2
        lda     fr_y
        sta     ln_y
        clc
        adc     fr_h
        dec     a
        sta     ln_y2
        jsr     draw_line0
        lda     fr_x
        clc
        adc     fr_w
        dec     a
        sta     ln_x
        sta     ln_x2
        lda     fr_y
        sta     ln_y
        jsr     draw_line0
        lda     fr_x
        sta     ln_x
        clc
        adc     fr_w
        dec     a
        sta     ln_x2
        lda     fr_y
        sta     ln_y
        sta     ln_y2
        jsr     draw_line0
        lda     fr_y
        clc
        adc     fr_h
        dec     a
        sta     ln_y
        sta     ln_y2
        lda     fr_x
        sta     ln_x
        jsr     draw_line0
@out:   rts
; (a line already drawn in the window: the shadow only, not marked dirty)
draw_line0:
        lda     gdirty
        pha
        lda     gdx0
        pha
        lda     gdy0
        pha
        lda     gdx1
        pha
        lda     gdy1
        pha
        jsr     draw_line
        pla
        sta     gdy1
        pla
        sta     gdx1
        pla
        sta     gdy0
        pla
        sta     gdx0
        pla
        sta     gdirty
        rts

; win_draw op A (fill / frame) of fr_* in gc_col on the window (the kernel clips). What
; was drawn into the shadow before is shown first, so the window follows the program's order.
win_box:
        pha
        jsr     gfx_flush
        pla
        sta     gblk
        lda     gc_col
        a8
        sta     gblk+1
        a16
        lda     fr_x
        sta     gblk+4
        lda     fr_y
        sta     gblk+6
        lda     fr_w
        sta     gblk+8
        lda     fr_h
        sta     gblk+10
        lda     gwin
        ptr     gblk
        sys     SYS_WDRAW
        rts

; GCLS [c]: the window in c (default 0)
st_gcls:
        jsr     gfx_need
        lda     #0
        sta     gc_col
        jsr     at_end
        beq     :+
        jsr     eval_u16
        and     #$00FF
        sta     gc_col
:       lda     gc_col
        jsr     gfx_clear
        jmp     stmt_end

; CIRCLE x, y, r (midpoint)
st_circle:
        jsr     gfx_cpu
        jsr     two_args
        lda     z:t0
        sta     ci_x
        lda     z:t1
        sta     ci_y
        lda     #','
        jsr     expect
        jsr     eval_s16
        tax
        bmi     @bad
        sta     ci_r
        lda     gcolor
        sta     gc_col
        lda     ci_x                    ; the box
        sec
        sbc     ci_r
        sta     z:t0
        lda     ci_y
        sec
        sbc     ci_r
        sta     z:t1
        lda     ci_x
        clc
        adc     ci_r
        sta     z:t2
        lda     ci_y
        clc
        adc     ci_r
        sta     z:t3
        jsr     dirty_box
        lda     ci_r                    ; x = r, y = 0, err = 1 - r
        sta     ci_px
        stz     ci_py
        lda     #1
        sec
        sbc     ci_r
        sta     ci_e
@l:     lda     ci_px
        cmp     ci_py
        bmi     @out
        jsr     @eight
        inc     ci_py
        lda     ci_e
        bmi     :+
        dec     ci_px                   ; err += 2 (y - x) + 1
        lda     ci_py
        sec
        sbc     ci_px
        asl     a
        inc     a
        clc
        adc     ci_e
        sta     ci_e
        bra     @l
:       lda     ci_py                   ; err += 2 y + 1
        asl     a
        inc     a
        clc
        adc     ci_e
        sta     ci_e
        bra     @l
@out:   jmp     stmt_end
@bad:   err     E_ARG
@eight: lda     ci_px
        ldx     ci_py
        jsr     @four
        lda     ci_py
        ldx     ci_px
@four:  sta     z:t4                    ; (cx +- a, cy +- b)
        stx     z:t5
        lda     ci_x
        clc
        adc     z:t4
        pha
        lda     ci_y
        clc
        adc     z:t5
        tax
        pla
        jsr     pset
        lda     ci_x
        sec
        sbc     z:t4
        pha
        lda     ci_y
        clc
        adc     z:t5
        tax
        pla
        jsr     pset
        lda     ci_x
        clc
        adc     z:t4
        pha
        lda     ci_y
        sec
        sbc     z:t5
        tax
        pla
        jsr     pset
        lda     ci_x
        sec
        sbc     z:t4
        pha
        lda     ci_y
        sec
        sbc     z:t5
        tax
        pla
        jmp     pset

; TEXT x, y, s$: the 8x12 font in the colour (no paper)
st_text:
        jsr     gfx_cpu
        jsr     two_args
        lda     z:t0
        sta     tx_x
        lda     z:t1
        sta     tx_y
        lda     #','
        jsr     expect
        jsr     eval_str
        lda     gcolor
        sta     gc_col
        lda     tx_x                    ; the box
        sta     z:t0
        lda     tx_y
        sta     z:t1
        clc
        adc     #11
        sta     z:t3
        lda     flen
        jeq     @out
        asl     a
        asl     a
        asl     a
        clc
        adc     tx_x
        dec     a
        sta     z:t2
        jsr     dirty_box
        lda     flo
        sta     z:bp
        lda     fhi
        sta     z:bp+2
        stz     tx_i
@ch:    lda     tx_i
        cmp     flen
        bcs     @out
        tay
        lda     [bp],y
        and     #$00FF
        cmp     #' '
        bcc     :+
        cmp     #127
        bcc     :++
:       lda     #'?'
:       sec
        sbc     #' '
        sta     z:t4                    ; glyph * 12
        asl     a
        clc
        adc     z:t4
        asl     a
        asl     a
        sta     tx_g
        stz     tx_r
@row:   ldx     tx_g
        lda     gfont,x
        and     #$00FF
        sta     tx_bits
        lda     tx_x
        sta     tx_px
@bit:   lda     tx_bits
        beq     @nrow
        asl     a                       ; (bit 8: this pixel)
        sta     tx_bits
        and     #$0100
        beq     :+
        lda     tx_y
        clc
        adc     tx_r
        tax
        lda     tx_px
        jsr     pset
:       lda     tx_bits
        and     #$00FF
        sta     tx_bits
        inc     tx_px
        bra     @bit
@nrow:  inc     tx_g
        inc     tx_r
        lda     tx_r
        cmp     #12
        bcc     @row
        lda     tx_x
        clc
        adc     #8
        sta     tx_x
        inc     tx_i
        brl     @ch
@out:   jmp     stmt_end

; PALETTE i, r, g, b (i 16-255; restored at RUN and at the end). (2.0) In full screen all
; 256 are the program's own; BASIC keeps a copy for CONT (fs_resume)
st_palette:
        jsr     eval_u16
        cmp     #256
        bcs     @bad
        ldx     gmode
        bne     :+
        cmp     #16
        bcc     @bad
:       sta     pl_i
        lda     #','
        jsr     expect
        jsr     byte_arg
        sta     pl_rg
        lda     #','
        jsr     expect
        jsr     byte_arg
        xba
        ora     pl_rg
        sta     pl_rg
        lda     #','
        jsr     expect
        jsr     byte_arg
        sta     pl_b
        tay
        ldx     pl_rg
        lda     pl_i
        sys     SYS_WSPAL
        lda     gmode
        beq     :+
        lda     pl_i                    ; the full-screen palette's copy
        tax
        a8
        lda     #1
        sta     palchg,x
        a16
        txa
        asl     a
        adc     pl_i
        tax
        lda     pl_rg
        sta     f:WIN_FSPAL,x
        a8
        lda     pl_b
        sta     f:WIN_FSPAL+2,x
        a16
:       jmp     stmt_end
@bad:   err     E_ARG
byte_arg:
        jsr     eval_u16
        cmp     #256
        bcs     :+
        rts
:       err     E_ARG

; the palette entries the program holds back to the system's
pal_restore:
        lda     #0
        sys     SYS_PALALLOC
        rts

; POINT(x, y): the colour there, -1 outside or without a window
f_point:
        lda     #'('
        jsr     expect
        jsr     two_args
        lda     #')'
        jsr     expect
        lda     gwin
        bmi     @out
        jsr     dl_sync
        lda     z:t0
        cmp     gwid
        bcs     @out
        lda     z:t1
        cmp     ghgt
        bcs     @out
        asl     a
        tax
        lda     f:WIN_ROWO,x
        clc
        adc     z:t0
        sta     z:gq
        lda     f:WIN_ROWB,x
        adc     #0                      ; (full screen: a row may run into the next bank)
        sta     z:gq+2
        lda     [gq]
        and     #$00FF
        jmp     ret_u16
@out:   lda     #$FFFF
        tax
        jmp     ret_int

; ---------------------------------------------------------------- sound
st_sound:
        jsr     at_end
        bne     :+
        jsr     snd_off
        jmp     stmt_end
:       jsr     eval_u16                ; the voice
        cmp     #4
        jcs     @bad
        asl     a
        sta     so_reg
        lda     #','
        jsr     expect
        jsr     eval_u16
        sta     so_f
        lda     #','
        jsr     expect
        jsr     eval_u16
        sta     so_v
        jsr     peek
        cmp     #','
        beq     @atari
        lda     so_v                    ; Hz: AUDF = 31960 / f - 1
        cmp     #16
        bcs     @bad
        lda     so_f
        beq     @quiet
        lda     so_v
        beq     @quiet
        lda     so_f
        jsr     hz_audf
        sta     so_f
        lda     so_v
        ora     #$A0
        sta     so_v
        bra     @write
@atari: inc     z:tp                    ; voice, pitch, distortion, volume
        jsr     eval_u16
        cmp     #16
        bcs     @bad
        sta     z:t0
        lda     so_f
        cmp     #256
        bcs     @bad
        lda     so_v                    ; (the distortion)
        cmp     #16
        bcs     @bad
        asl     a
        asl     a
        asl     a
        asl     a
        ora     z:t0
        sta     so_v
@write: lda     so_reg
        ldx     so_f
        sys     SYS_SNDW
        lda     so_reg
        inc     a
        ldx     so_v
        sys     SYS_SNDW
        jmp     stmt_end
@quiet: stz     so_v
        bra     @write
@bad:   err     E_ARG

; f Hz (A > 0) -> A = AUDF (0-255)
hz_audf:
        sta     m_b
        stz     m_b+2
        lsr     a                       ; (rounded: + f / 2)
        clc
        adc     #31960
        sta     m_a
        stz     m_a+2
        jsr     udiv32
        lda     m_r
        dec     a
        bpl     :+
        lda     #0
:       cmp     #256
        bcc     :+
        lda     #255
:       rts

; BEEP [f, ms]: a short tone on voice 0 (default 1000 Hz, 100 ms)
st_beep:
        lda     #1000
        sta     so_f
        lda     #100
        sta     so_v
        jsr     at_end
        beq     :+
        jsr     eval_u16
        sta     so_f
        lda     #','
        jsr     expect
        jsr     eval_u16
        sta     so_v
:       lda     so_f
        bne     :+
        jmp     stmt_end
:       jsr     hz_audf
        pha
        lda     so_v                    ; ms -> ticks of 10 ms (at least 1)
        ldx     #0
:       cmp     #10
        bcc     :+
        sbc     #10
        inx
        bra     :-
:       cpx     #0
        bne     :+
        inx
:       pla
        ldy     #8
        sys     SYS_BEEP
        jmp     stmt_end

; all voices silent (2.0: and the samples stopped)
snd_off:
        lda     #$FFFF
        sys     SYS_SSTOP
        ldx     #0
        lda     #1
:       pha
        sys     SYS_SNDW
        pla
        inc     a
        inc     a
        cmp     #9
        bcc     :-
        rts

        .segment "RODATA"
gfont:
        .include "../kernel/font.inc"
t_graphics: .byte "Graphics", 0

        .segment "DATA"
gwin:   .word   $FFFF
gopen:  .word   0, 0, 320, 200
        .word   .loword(t_graphics)
        .byte   0                       ; (the bank, set at run time)
        .byte   0

        .segment "BSS"
gcolor: .res    2
gc_col: .res    2
gwid:   .res    2
ghgt:   .res    2
gstride: .res   2
gshift: .res    2
grpb:   .res    2
gnb:    .res    2
gbk:    .res    GBANKS * 2 + 2
gdirty: .res    2
gdx0:   .res    2
gdy0:   .res    2
gdx1:   .res    2
gdy1:   .res    2
gf_y:   .res    2
gf_t0:  .res    2
gf_t1:  .res    2
gblk:   .res    16
ginfo:  .res    8
sc_w:   .res    2
sc_h:   .res    2
fr_x:   .res    2
fr_y:   .res    2
fr_w:   .res    2
fr_h:   .res    2
ln_x:   .res    2
ln_y:   .res    2
ln_x2:  .res    2
ln_y2:  .res    2
ln_dx:  .res    2
ln_dy:  .res    2
ln_sx:  .res    2
ln_sy:  .res    2
ln_err: .res    2
ci_x:   .res    2
ci_y:   .res    2
ci_r:   .res    2
ci_px:  .res    2
ci_py:  .res    2
ci_e:   .res    2
tx_x:   .res    2
tx_y:   .res    2
tx_i:   .res    2
tx_g:   .res    2
tx_r:   .res    2
tx_px:  .res    2
tx_bits: .res   2
palchg: .res    256             ; (full screen: the palette entries set)
pl_i:   .res    2
pl_rg:  .res    2
pl_b:   .res    2
gmode:  .res    2               ; 0 a window, 1 / 2 full screen (bas_game.s)
gww:    .res    2               ; the window's content (= gwid, ghgt but in full screen)
gwh:    .res    2
gfocus: .res    2               ; the window has the keyboard focus
so_reg: .res    2
so_f:   .res    2
so_v:   .res    2
