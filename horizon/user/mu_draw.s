; mu_draw.s - Music: drawing. The texts at the top (drawn with their paper: no blank moment),
; the level meters (one sheet_draw of fills a frame, only the bars whose height changed), the
; position bar, the buttons (drawn here: their pictures), the volume and stereo bars, the
; tabs, the status line, the lists' rows. Included by music.s.

        .segment "CODE"

; everything (at the start)
draw_all:
        jsr     draw_info
        jsr     draw_mbox
        jsr     barpx
        lda     #$FFFF
        sta     bar_px                  ; (drawn whatever it was)
        jsr     draw_bar
        jsr     draw_btns
        lda     win
        sta     z:ui_win
        stz     z:ui_font
        lda     #VLX                    ; the labels of the two bars
        sta     z:ui_x
        lda     #VBY
        sta     z:ui_y
        lda     #C_BLACK | (C_BODY << 8)
        ldx     #.loword(s_volume)
        jsr     ui_text
        lda     #SLX
        sta     z:ui_x
        lda     #C_BLACK | (C_BODY << 8)
        ldx     #.loword(s_stereo)
        jsr     ui_text
        jsr     draw_vol
        jsr     draw_sep
        jsr     draw_tabs
        jsr     ctls
        jsr     ui_drawall
        jmp     draw_status

; ---------------------------------------------------------------- texts
; the string X in the box ui_x, ui_y, ui_w (one line), ink | paper << 8 in A, cut with "..."
; to fit; the rest of the box in the paper. tright: right-aligned
tbox:   sta     z:t6
        ldy     #.loword(tbuf)
        jsr     ui_strcpy
        lda     z:ui_w
        ldx     #.loword(tbuf)
        jsr     ui_fit
        ldx     #.loword(tbuf)
        lda     #0
        jsr     ui_twidth
        sta     z:t4                    ; the text's width
        lda     win
        sta     z:ui_win
        stz     z:ui_font
        lda     #UI_LINE - 1
        sta     z:ui_h
        lda     z:ui_w
        sec
        sbc     z:t4
        sta     z:t3                    ; the paper's width
        lda     tright
        beq     @left
        stz     tright
        lda     z:t3                    ; right: the paper, then the text
        beq     :+
        bmi     :+
        sta     z:ui_w
        jsr     @fill
:       lda     z:ui_x
        clc
        adc     z:t3
        sta     z:ui_x
        lda     z:t6
        ldx     #.loword(tbuf)
        jmp     ui_text
@left:  lda     z:t6                    ; left: the text, then the paper
        ldx     #.loword(tbuf)
        jsr     ui_text
        lda     z:t3
        beq     :+
        bmi     :+
        sta     z:ui_w
        lda     z:ui_x
        clc
        adc     z:t4
        sta     z:ui_x
        jmp     @fill
:       rts
@fill:  lda     z:t6
        and     #$FF00
        ora     #WD_FILL
        jmp     ui_rect

draw_info:
        jsr     draw_title
        jsr     draw_fmt
        lda     #1
        sta     posforce
        jmp     draw_pos
draw_title:
        lda     #M
        sta     z:ui_x
        lda     #TY1
        sta     z:ui_y
        lda     #TXW
        sta     z:ui_w
        lda     tink
        ldx     #.loword(tstr)
        jmp     tbox
draw_fmt:
        lda     #M
        sta     z:ui_x
        lda     #TY2
        sta     z:ui_y
        lda     #TXW
        sta     z:ui_w
        lda     fink
        ora     #C_BODY << 8
        ldx     #.loword(fstr)
        jmp     tbox
; the position and the time: drawn when they changed (posforce: anyway)
draw_pos:
        lda     posforce
        bne     :+
        ldx     #.loword(pstr)
        ldy     #.loword(pstr_o)
        jsr     strsame
        bne     :+
        ldx     #.loword(tmstr)
        ldy     #.loword(tmstr_o)
        jsr     strsame
        beq     @out
:       stz     posforce
        ldx     #.loword(pstr)
        ldy     #.loword(pstr_o)
        jsr     ui_strcpy
        ldx     #.loword(tmstr)
        ldy     #.loword(tmstr_o)
        jsr     ui_strcpy
        lda     #M
        sta     z:ui_x
        lda     #TY3
        sta     z:ui_y
        lda     #TXW - TIMEW
        sta     z:ui_w
        lda     #C_BLACK | (C_BODY << 8)
        ldx     #.loword(pstr)
        jsr     tbox
        lda     #M + TXW - TIMEW
        sta     z:ui_x
        lda     #TY3
        sta     z:ui_y
        lda     #TIMEW
        sta     z:ui_w
        inc     tright
        lda     #C_BLACK | (C_BODY << 8)
        ldx     #.loword(tmstr)
        jmp     tbox
@out:   rts

; X, Y = strings -> Z set: the same
strsame:
        sep     #$20
        .a8
:       lda     a:0,x
        cmp     a:0,y
        bne     :+
        inx
        iny
        cmp     #0
        bne     :-
:       rep     #$20
        .a16
        rts

; nothing loaded: the title and a hint
idletext:
        lda     phase
        cmp     #PH_NONE
        bne     @out
        ldx     #.loword(m_idle)
        ldy     #.loword(tstr)
        jsr     ui_strcpy
        lda     #C_DARK | (C_BODY << 8)
        sta     tink
        ldx     #.loword(m_hint0)
        lda     pl_n
        beq     :+
        ldx     #.loword(m_hint1)
:       ldy     #.loword(fstr)
        jsr     ui_strcpy
        lda     #C_DARK
        sta     fink
        stz     pstr
        stz     tmstr
        lda     winok                   ; (before the window: drawn by draw_all)
        beq     @out
        jmp     draw_info
@out:   rts

; the format line by the phase: loading, an error, the module's or the WAV's format
mkfmt:  stz     sl
        lda     #C_BLACK | (C_BODY << 8)
        sta     tink
        lda     #C_DARK
        sta     fink
        lda     phase
        cmp     #PH_FAIL
        bne     :+
        lda     #C_RED
        sta     fink
        lda     lerr
        jsr     errtext                 ; -> X
        jsr     sapp
        jmp     @done
:       cmp     #PH_READY
        beq     @ready
        ldx     #.loword(m_loading)     ; "Loading..." (and the percent)
        jsr     sapp
        lda     pct
        beq     :+
        lda     #' '
        jsr     sapc
        lda     pct
        jsr     sappn
        lda     #'%'
        jsr     sapc
:       jmp     @done
@ready: lda     info+MI_KIND
        and     #$00FF
        cmp     #1
        beq     @mod
        cmp     #3
        jeq     @mid
        cmp     #2
        jne     @done
        ldx     #.loword(s_wav)         ; "WAV, 44100 Hz, 16-bit stereo, 3:12"
        jsr     sapp
        lda     info+MI_RATE
        jsr     sappn
        ldx     #.loword(s_hz)
        jsr     sapp
        lda     info+MI_BITS
        and     #$00FF
        jsr     sappn
        ldx     #.loword(s_bit)
        jsr     sapp
        ldx     #.loword(s_mono)
        lda     info+MI_NCHAN
        and     #$00FF
        cmp     #2
        bcc     :+
        ldx     #.loword(s_stereo2)
:       jsr     sapp
        ldx     #.loword(s_comma)
        jsr     sapp
        lda     info+MI_TENTHS
        jsr     sappt10
        bra     @done
@mid:   ldx     #.loword(s_mid)         ; "MIDI (OPL2), 12 tracks, 120 BPM, 3:12"
        jsr     sapp
        lda     info+MI_NPAT
        and     #$00FF
        jsr     sappn
        ldx     #.loword(s_trks)
        jsr     sapp
        lda     info+MI_BPM
        and     #$00FF
        jsr     sappn
        ldx     #.loword(s_bpm)
        jsr     sapp
        lda     info+MI_TENTHS
        jsr     sappt10
        bra     @done
@mod:   lda     info+MI_NCHAN           ; "4 channels, 31 samples, M.K."
        and     #$00FF
        jsr     sappn
        ldx     #.loword(s_chans)
        jsr     sapp
        lda     info+MI_NSMP
        and     #$00FF
        jsr     sappn
        ldx     #.loword(s_smps)
        jsr     sapp
        lda     info+MI_TAG             ; the tag, when there is one (printable)
        and     #$00FF
        cmp     #'!'
        bcc     @done
        ldx     #.loword(s_comma)
        jsr     sapp
        ldx     #0
:       lda     info+MI_TAG,x
        and     #$00FF
        cmp     #' '
        bcc     @done
        cmp     #127
        bcs     @done
        phx
        jsr     sapc
        plx
        inx
        cpx     #4
        bcc     :-
@done:  ldx     #.loword(sbuf)
        ldy     #.loword(fstr)
        jmp     ui_strcpy

; the position line and the time from the status (PH_READY)
mkpos:  stz     sl
        stz     sbuf
        lda     info+MI_KIND
        and     #$00FF
        cmp     #2
        jcs     @wav
        cmp     #1
        bne     @time
        ldx     #.loword(s_order)       ; "Order 4 of 12, pattern 5, row 32"
        jsr     sapp
        lda     st+2
        and     #$00FF
        inc     a
        jsr     sappn
        ldx     #.loword(s_of)
        jsr     sapp
        lda     info+MI_SLEN
        and     #$00FF
        jsr     sappn
        ldx     #.loword(s_pat)
        jsr     sapp
        lda     st+4
        and     #$00FF
        jsr     sappn
        ldx     #.loword(s_row)
        jsr     sapp
        lda     st+3
        and     #$00FF
        jsr     sappn
@time:  ldx     #.loword(sbuf)
        ldy     #.loword(pstr)
        jsr     ui_strcpy
        stz     sl                      ; the time played
        lda     st+6
        jsr     sappt10
        lda     info+MI_KIND
        and     #$00FF
        cmp     #2
        bcc     :+
        ldx     #.loword(s_slash)       ; a WAV or MIDI: " / its length"
        jsr     sapp
        lda     info+MI_TENTHS
        jsr     sappt10
:       ldx     #.loword(sbuf)
        ldy     #.loword(tmstr)
        jmp     ui_strcpy
@wav:   lda     estate
        cmp     #MST_PAUSED
        bne     @time
        ldx     #.loword(s_paused1)
        jsr     sapp
        bra     @time

; ---------------------------------------------------------------- the position bar
; -> bar_n: the filled pixels, bar_c: their colour (loading: the percent, grey)
barpx:  lda     #C_SELECT
        sta     bar_c
        lda     phase
        cmp     #PH_LOAD
        bne     :+
        lda     #C_MID
        sta     bar_c
        lda     pct
        ldx     #PBW - 2
        jsr     umul32
        ldx     #100
        jsr     udiv32
        bra     @set
:       cmp     #PH_READY
        bne     @zero
        lda     estate
        cmp     #MST_ENDED
        bne     :+
        lda     #PBW - 2
        bra     @set
:       lda     info+MI_KIND
        and     #$00FF
        cmp     #2
        bcs     @wav
        cmp     #1
        bne     @zero
        lda     info+MI_SLEN            ; (order * 64 + row) * width / (length * 64)
        and     #$00FF
        beq     @zero
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        sta     z:t5
        lda     st+2
        and     #$00FF
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        sta     z:t0
        lda     st+3
        and     #$003F
        ora     z:t0
        ldx     #PBW - 2
        jsr     umul32
        ldx     z:t5
        jsr     udiv32
        bra     @set
@wav:   lda     st+2                    ; 256ths * width / 256
        and     #$00FF
        ldx     #PBW - 2
        jsr     umul32
        lda     z:t0
        xba
        and     #$00FF
        sta     z:t0
        lda     z:t1
        xba
        and     #$FF00
        ora     z:t0
        bra     @set
@zero:  lda     #0
@set:   cmp     #PBW - 1
        bcc     :+
        lda     #PBW - 2
:       sta     bar_n
        rts

; the bar drawn when it changed (bar_px, bar_pc: what it shows)
draw_bar:
        lda     bar_n
        cmp     bar_px
        bne     :+
        lda     bar_c
        cmp     bar_pc
        beq     @out
:       lda     bar_px                  ; (not drawn yet: its frame first)
        cmp     #$FFFF
        bne     :+
        lda     win
        sta     z:ui_win
        lda     #PBX
        sta     z:ui_x
        lda     #PBY
        sta     z:ui_y
        lda     #PBW
        sta     z:ui_w
        lda     #PBH
        sta     z:ui_h
        lda     #1
        jsr     ui_bevel
:       lda     bar_n
        sta     bar_px
        lda     bar_c
        sta     bar_pc
        lda     win
        sta     z:ui_win
        lda     #PBX + 1
        sta     z:ui_x
        lda     #PBY + 1
        sta     z:ui_y
        lda     #PBH - 2
        sta     z:ui_h
        lda     bar_n
        beq     :+
        sta     z:ui_w
        lda     bar_c
        xba
        and     #$FF00
        ora     #WD_FILL
        jsr     ui_rect
:       lda     #PBW - 2
        sec
        sbc     bar_n
        beq     @out
        sta     z:ui_w
        lda     #PBX + 1
        clc
        adc     bar_n
        sta     z:ui_x
        lda     #WD_FILL | (C_WHITE << 8)
        jmp     ui_rect
@out:   rts

; ---------------------------------------------------------------- the meters
; the box: sunken, black inside
draw_mbox:
        lda     win
        sta     z:ui_win
        lda     #MTX
        sta     z:ui_x
        lda     #MTY
        sta     z:ui_y
        lda     #MTW
        sta     z:ui_w
        lda     #MTH
        sta     z:ui_h
        lda     #1
        jsr     ui_bevel
        inc     z:ui_x
        inc     z:ui_y
        lda     #MTW - 2
        sta     z:ui_w
        lda     #MTH - 2
        sta     z:ui_h
        lda     #WD_FILL | (C_BLACK << 8)
        jsr     ui_rect
        ldx     #14                     ; every bar drawn again at the next frame
:       lda     #$FFFF
        sta     lv_s,x
        dex
        dex
        bpl     :-
        rts

; A = the channels (1-8): the bars' places; the box cleared when the number changed
setnch: cmp     #1
        bcs     :+
        lda     #1
:       cmp     #9
        bcc     :+
        lda     #8
:       cmp     nch
        beq     @out
        sta     nch
        dec     a                       ; the width of a bar: (104 - (n - 1) * 3) / n
        sta     z:t0
        asl     a
        adc     z:t0
        eor     #$FFFF
        sec
        adc     #MTW - 8
        ldx     nch
        jsr     udiv16
        sta     mbw
        ldx     nch                     ; centred: (104 - (n * w + (n - 1) * 3)) / 2
        jsr     umul16
        clc
        adc     z:t0
        adc     z:t0
        adc     z:t0
        eor     #$FFFF
        sec
        adc     #MTW - 8
        lsr     a
        clc
        adc     #MTX + 4
        ldx     #0
:       sta     mbx,x
        clc
        adc     mbw
        adc     #3
        inx
        inx
        cpx     #16
        bcc     :-
        ldx     #14
:       stz     lv_d,x
        dex
        dex
        bpl     :-
        lda     winok
        beq     @out
        jsr     draw_mbox
@out:   rts

; a frame: each bar falls slowly to its level (or jumps up to it); the bars whose height
; changed drawn with one sheet_draw of fills; the frames off when nothing plays and all fell
meters: dec     vischk                  ; every 8 frames: is the meters' box seen? (another
        bpl     :+                      ; window over it: not drawn, which keeps the CPU for
        lda     #7                      ; the program in front)
        sta     vischk
        jsr     mvisible
:       stz     mn                      ; records
        stz     z:t7                    ; any bar up
        ldx     #0
@ch:    txa
        lsr     a
        cmp     nch
        jcs     @draw
        lda     lv_t,x
        cmp     lv_d,x
        bcs     @set                    ; up: at once
        lda     lv_d,x                  ; down: 3 a frame
        sec
        sbc     #3
        bcc     :+
        cmp     lv_t,x
        bcs     @set
:       lda     lv_t,x
@set:   sta     lv_d,x
        beq     :+
        inc     z:t7
:       sta     z:t0                    ; the height: level * MBH / 64, rounded
        asl     a
        asl     a
        clc
        adc     z:t0
        asl     a                       ; * 10 ...
        sta     z:t1
        lda     z:t0
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     z:t1                    ; * 42
        sec
        sbc     z:t0
        sbc     z:t0
        sbc     z:t0
        sbc     z:t0                    ; * 38 (MBH)
        clc
        adc     #32
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        cmp     lv_s,x
        beq     @next
        sta     lv_s,x
        sta     z:mh
        stx     z:mc
        lda     mbx,x
        sta     z:mx
        lda     #0                      ; green zone [0, ZG)
        ldx     #ZG
        ldy     #C_GREEN | (C_DIMG << 8)
        jsr     zone
        lda     #ZG                     ; yellow [ZG, ZY)
        ldx     #ZY
        ldy     #C_YELLOW | (C_DIMY << 8)
        jsr     zone
        lda     #ZY                     ; red [ZY, MBH)
        ldx     #MBH
        ldy     #C_RED | (C_DIMR << 8)
        jsr     zone
        ldx     z:mc
@next:  inx
        inx
        cpx     #16
        jcc     @ch
@draw:  lda     mn
        beq     :+
        ldx     mvis
        beq     :+
        xba
        and     #$FF00
        ora     win
        ldx     #.loword(mrec)
        ldy     pbank
        sys     SYS_SHEETDRAW
:       lda     z:t7                    ; all down and nothing plays: no more frames
        bne     :+
        lda     estate
        cmp     #MST_PLAYING
        beq     :+
        lda     #0
        jmp     setvbl
:       rts
ZG      = 23
ZY      = 32

; mvis: the middle of the meters' box is ours on the screen (no window over it); when it
; comes back every bar is drawn again
mvisible:
        lda     win
        ptr     wibuf
        sys     SYS_WINFO
        bcs     @no
        lda     wibuf
        clc
        adc     #MTX + MTW / 2
        tax
        lda     wibuf+2
        clc
        adc     #MTY + MTH / 2
        tay
        sys     SYS_WINAT
        and     #$00FF
        cmp     win
        bne     @no
        lda     mvis
        bne     :+
        inc     mvis
        ldx     #14                     ; (seen again: all drawn)
        lda     #$FFFF
@f:     sta     lv_s,x
        dex
        dex
        bpl     @f
:       rts
@no:    stz     mvis
        rts

; the zone [A, X) of the bar at mx (height mh): lit in Y's low byte up to mh, dim above
zone:   sta     z:za
        stx     z:zb
        sty     z:zc
        lda     z:mh                    ; lit: [a, min(h, b))
        cmp     z:za
        beq     @dim
        bcc     @dim
        cmp     z:zb
        bcc     :+
        lda     z:zb
:       sta     z:t2                    ; the top
        sec
        sbc     z:za
        tay                             ; the height
        lda     #MBY
        sec
        sbc     z:t2
        tax                             ; y
        lda     z:zc
        jsr     mfill
@dim:   lda     z:mh                    ; dim: [max(h, a), b)
        cmp     z:zb
        bcs     @out
        cmp     z:za
        bcs     :+
        lda     z:za
:       sta     z:t2
        lda     z:zb
        sec
        sbc     z:t2
        tay
        lda     #MBY
        sec
        sbc     z:zb
        tax
        lda     z:zc
        xba
        jsr     mfill
@out:   rts

; a fill record: colour A (low byte), y X, height Y, at mx, mbw wide
mfill:  pha
        phx
        lda     mn
        asl     a
        asl     a
        asl     a
        asl     a
        tax
        stz     mrec,x                  ; sheet 0, SH_FILL
        pla
        sta     mrec+SD_Y,x
        pla
        and     #$00FF
        sta     mrec+SD_C,x
        stz     mrec+SD_SX,x
        stz     mrec+SD_SY,x
        lda     mbw
        sta     mrec+SD_W,x
        tya
        sta     mrec+SD_H,x
        lda     z:mx
        sta     mrec+SD_X,x
        inc     mn
        rts

; ---------------------------------------------------------------- buttons
draw_btns:
        lda     #0
:       pha
        jsr     draw_btn
        pla
        inc     a
        cmp     #NBTN
        bcc     :-
        rts

; button A: up, down (pressed with the pointer on it, or the state it stands for: Play
; while playing, Pause while paused, Stop while stopped), dimmed (Previous and Next with
; fewer than two songs); its picture
draw_btn:
        sta     z:bi
        lda     win
        sta     z:ui_win
        lda     z:bi                    ; x = M + i * (BTW + BTG)
        ldx     #BTW + BTG
        jsr     umul16
        clc
        adc     #M
        sta     z:bx
        stz     z:bdn
        lda     btnp                    ; held
        cmp     z:bi
        bne     :+
        lda     btnin
        sta     z:bdn
        bra     @face
:       lda     phase                   ; latched by the state
        cmp     #PH_READY
        bne     @face
        lda     estate
        ldx     z:bi
        cpx     #B_PLAY
        bne     :+
        cmp     #MST_PLAYING
        bne     @face
        inc     z:bdn
        bra     @face
:       cpx     #B_PAUSE
        bne     :+
        cmp     #MST_PAUSED
        bne     @face
        inc     z:bdn
        bra     @face
:       cpx     #B_STOP
        bne     @face
        cmp     #MST_STOPPED
        beq     :+
        cmp     #MST_ENDED
        bne     @face
:       inc     z:bdn
@face:  lda     z:bx                    ; the outline, the face, the bevel
        sta     z:ui_x
        lda     #BTY
        sta     z:ui_y
        lda     #BTW
        sta     z:ui_w
        lda     #BTH
        sta     z:ui_h
        lda     #WD_FRAME | (C_DARK << 8)
        jsr     ui_rect
        inc     z:ui_x
        inc     z:ui_y
        lda     #BTW - 2
        sta     z:ui_w
        lda     #BTH - 2
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        ldx     z:bdn
        beq     :+
        lda     #WD_FILL | (C_LIGHT << 8)
:       jsr     ui_rect
        lda     z:bdn
        jsr     ui_bevel
        lda     #C_BLACK                ; the picture
        sta     z:bink
        lda     z:bi
        cmp     #B_PREV
        beq     :+
        cmp     #B_NEXT
        bne     :++
:       lda     pl_n
        cmp     #2
        bcs     :+
        lda     #C_MID
        sta     z:bink
:       lda     z:bi
        asl     a
        tax
        ldy     glyphs,x
@r:     lda     a:0,y                   ; {dx, dy, w, h}, $FFFF
        cmp     #$FFFF
        beq     @out
        clc
        adc     z:bx
        adc     z:bdn
        sta     z:ui_x
        lda     a:2,y
        clc
        adc     #BTY
        adc     z:bdn
        sta     z:ui_y
        lda     a:4,y
        sta     z:ui_w
        lda     a:6,y
        sta     z:ui_h
        phy
        lda     z:bink
        xba
        and     #$FF00
        ora     #WD_FILL
        jsr     ui_rect
        ply
        tya
        clc
        adc     #8
        tay
        bra     @r
@out:   rts

; ---------------------------------------------------------------- volume, separation
draw_vol:
        lda     #VBX
        ldx     #VBW
        ldy     vol
        bra     vbar
draw_sep:
        lda     #SBX
        ldx     #SBW
        ldy     msep
; a bar at x A, X wide, value Y (0-64): sunken, filled to the value
vbar:   sta     z:ui_x
        stx     z:ui_w
        sty     z:t5
        lda     win
        sta     z:ui_win
        lda     #VBY
        sta     z:ui_y
        lda     #VBH
        sta     z:ui_h
        lda     #1
        jsr     ui_bevel
        inc     z:ui_x
        inc     z:ui_y
        dec     z:ui_h
        dec     z:ui_h
        lda     z:ui_w
        dec     a
        dec     a
        sta     z:t6                    ; the inside's width (umul16 uses t3, t4)
        ldx     z:t5                    ; filled: value * width / 64
        jsr     umul16
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     z:t3
        beq     :+
        sta     z:ui_w
        lda     #WD_FILL | (C_SELECT << 8)
        jsr     ui_rect
:       lda     z:t6                    ; the rest: white
        sec
        sbc     z:t3
        beq     :+
        sta     z:ui_w
        lda     z:ui_x
        clc
        adc     z:t3
        sta     z:ui_x
        lda     #WD_FILL | (C_WHITE << 8)
        jmp     ui_rect
:       rts

; ---------------------------------------------------------------- the tabs
; "Playlist" and "Samples" (the one shown: black, underlined), the count at the right
draw_tabs:
        lda     win
        sta     z:ui_win
        stz     z:ui_font
        ldx     #.loword(s_tpl)
        lda     #0
        jsr     ui_twidth
        clc
        adc     #M + 12
        sta     tabx1
        ldx     #.loword(s_tsm)
        lda     #0
        jsr     ui_twidth
        clc
        adc     tabx1
        adc     #12
        sta     tabx2
        lda     #M                      ; Playlist
        ldx     tabx1
        ldy     #.loword(s_tpl)
        lda     view
        eor     #1
        sta     z:t5
        lda     #M
        jsr     tab
        lda     view                    ; Samples
        sta     z:t5
        lda     tabx1
        ldx     tabx2
        ldy     #.loword(s_tsm)
        jsr     tab
        stz     sl                      ; the count
        lda     view
        bne     @sm
        lda     pl_n
        beq     @put
        jsr     sappn
        ldx     #.loword(s_songs)
        lda     pl_n
        cmp     #1
        bne     :+
        ldx     #.loword(s_song1)
:       jsr     sapp
        bra     @put
@sm:    lda     nsmp
        beq     @put
        jsr     sappn
        ldx     #.loword(s_smps2)
        jsr     sapp
@put:   lda     tabx2
        sta     z:ui_x
        lda     #TABY + 3
        sta     z:ui_y
        lda     #WW - M
        sec
        sbc     tabx2
        sta     z:ui_w
        inc     tright
        lda     #C_DARK | (C_BODY << 8)
        ldx     #.loword(sbuf)
        jmp     tbox

; a tab from x A to X, label Y, t5 = 1: the one shown
tab:    sta     z:ui_x
        stx     z:t4
        sty     z:t3
        lda     #TABY + 3
        sta     z:ui_y
        lda     z:ui_x
        clc
        adc     #4
        sta     z:ui_x
        lda     #C_DARK | (C_BODY << 8)
        ldx     z:t5
        beq     :+
        lda     #C_BLACK | (C_BODY << 8)
:       ldx     z:t3
        jsr     ui_text
        lda     z:ui_x                  ; the line under it
        sec
        sbc     #4
        sta     z:ui_x
        lda     z:t4
        sec
        sbc     z:ui_x
        sec
        sbc     #4
        sta     z:ui_w
        lda     #TABY + TABH - 4
        sta     z:ui_y
        lda     #2
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        ldx     z:t5
        beq     :+
        lda     #WD_FILL | (C_SELECT << 8)
:       jmp     ui_rect

; ---------------------------------------------------------------- the status line
; left: "Song 2 of 5" (or the count); right: the modes, or that the sound is off in Settings
draw_status:
        stz     sl
        lda     cur
        cmp     pl_n
        bcs     :+
        ldx     #.loword(s_songn)
        jsr     sapp
        lda     cur
        inc     a
        jsr     sappn
        ldx     #.loword(s_of)
        jsr     sapp
        lda     pl_n
        jsr     sappn
        bra     @l
:       ldx     #.loword(s_plempty)
        lda     pl_n
        beq     :+
        ldx     #.loword(s_plnone)
:       jsr     sapp
@l:     lda     #M
        sta     z:ui_x
        lda     #STATY
        sta     z:ui_y
        lda     #160
        sta     z:ui_w
        lda     #C_DARK | (C_BODY << 8)
        ldx     #.loword(sbuf)
        jsr     tbox
        stz     sl
        lda     sysv
        bne     :+
        ldx     #.loword(s_soundoff)
        jsr     sapp
        lda     #C_RED | (C_BODY << 8)
        bra     @r
:       lda     shuf
        beq     :+
        ldx     #.loword(s_shuf)
        jsr     sapp
:       lda     mrep
        asl     a
        tax
        lda     reptxt,x
        tax
        jsr     sapp
        lda     #C_DARK | (C_BODY << 8)
@r:     pha
        lda     #M + 160
        sta     z:ui_x
        lda     #STATY
        sta     z:ui_y
        lda     #WW - 2 * M - 160
        sta     z:ui_w
        inc     tright
        pla
        ldx     #.loword(sbuf)
        jmp     tbox

; the sound volume setting (Lau's master volume): 0 shows a hint on the status line
sysvol: lda     #4
        ldx     #$FFFF
        sys     SYS_SETTING
        bcc     :+
        lda     #8
:       cmp     sysv
        beq     :+
        sta     sysv
        lda     winok
        beq     :+
        jmp     draw_status
:       rts

; ---------------------------------------------------------------- the lists' rows
; the playlist: A = row -> X = its name; the song loaded has a mark in the indent
lsrow_pl:
        sta     z:t5
        jsr     pl_get
        jsr     namepb
        lda     z:t5
        cmp     cur
        bne     @out
        lda     phase
        cmp     #PH_NONE
        beq     @out
        lda     z:ui_x                  ; a small triangle (kept: ui_x .. ui_h)
        pha
        lda     z:ui_y
        pha
        lda     z:ui_w
        pha
        lda     z:ui_h
        pha
        lda     #C_SELECT
        ldx     z:ui_rsel
        beq     :+
        lda     #C_WHITE
:       xba
        ora     #WD_FILL
        sta     z:t4
        lda     #1
        sta     z:ui_w
        lda     z:ui_x
        clc
        adc     #2
        sta     z:ui_x
        lda     z:ui_y
        clc
        adc     #3
        sta     z:ui_y
        lda     #9
        sta     z:ui_h
:       lda     z:t4
        jsr     ui_rect
        inc     z:ui_x
        inc     z:ui_y
        dec     z:ui_h
        dec     z:ui_h
        bpl     :-
        pla
        sta     z:ui_h
        pla
        sta     z:ui_w
        pla
        sta     z:ui_y
        pla
        sta     z:ui_x
@out:   ldx     #.loword(nbuf)
        rts

; the samples: A = row -> X = its name; the number right-aligned in the indent
lsrow_sm:
        sta     z:t5
        ldx     #30                     ; its header: smp + row * 30, the name 22 bytes
        jsr     umul16
        clc
        adc     #.loword(smp)
        tax
        ldy     #0
:       lda     a:0,x
        sep     #$20
        .a8
        sta     rowbuf,y
        rep     #$20
        .a16
        inx
        iny
        cpy     #22
        bcc     :-
        ldx     #.loword(rowbuf)
        ldy     #22
        jsr     clean
        lda     z:ui_x                  ; the number
        pha
        lda     z:ui_y
        pha
        lda     z:ui_w
        pha
        lda     z:ui_h
        pha
        stz     sl
        lda     z:t5
        inc     a
        jsr     sappn
        ldx     #.loword(sbuf)
        lda     #0
        jsr     ui_twidth
        eor     #$FFFF
        sec
        adc     #SNW - 4
        clc
        adc     z:ui_x
        sta     z:ui_x
        lda     z:ui_y
        clc
        adc     #3
        sta     z:ui_y
        stz     z:ui_font
        lda     #C_DARK | (C_WHITE << 8)
        ldx     z:ui_rsel
        beq     :+
        lda     #C_WHITE | (C_SELECT << 8)
:       ldx     #.loword(sbuf)
        jsr     ui_text
        pla
        sta     z:ui_h
        pla
        sta     z:ui_w
        pla
        sta     z:ui_y
        pla
        sta     z:ui_x
        ldx     #.loword(rowbuf)
        rts
