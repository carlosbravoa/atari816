; uifld.s - controls library: the one-line text field. See ui.inc.
        .include "horizon.inc"
        .include "ui.inc"
        .import ui_px, ui_py, ui_rel, ui_setc, ui_box

        .segment "CODE"
        .a16
        .i16

; the field ui_c's state -> fb (buffer), fmax, flen, fcur, fanc, fscr, fw (text width)
fd_load:
        ldx     z:ui_c
        lda     a:FD_BUF,x
        sta     z:ui_q
        lda     a:FD_MAX,x
        sta     fmax
        lda     a:FD_LEN,x
        sta     flen
        lda     a:FD_CUR,x
        sta     fcur
        lda     a:FD_ANC,x
        sta     fanc
        lda     a:FD_SCR,x
        sta     fscr
        lda     a:CT_W,x
        sec
        sbc     #8
        sta     fw
        rts
fd_store:
        ldx     z:ui_c
        lda     flen
        sta     a:FD_LEN,x
        lda     fcur
        sta     a:FD_CUR,x
        lda     fanc
        sta     a:FD_ANC,x
        lda     fscr
        sta     a:FD_SCR,x
        rts

; X = from, Y = to -> A = width of the text between them (UI font)
fd_wid: sty     fto
        txy
        stz     fac
:       cpy     fto
        bcs     :+
        lda     (ui_q),y
        ldx     #0
        jsr     ui_cwidth
        clc
        adc     fac
        sta     fac
        iny
        bra     :-
:       lda     fac
        rts

; scroll so that the cursor shows, and no room is wasted at the right
fd_scroll:
        lda     fcur
        cmp     fscr
        bcs     :+
        sta     fscr
:       ldx     fscr                    ; the cursor past the right edge?
        ldy     fcur
        jsr     fd_wid
        inc     a
        cmp     fw
        bcc     :+
        beq     :+
        inc     fscr
        bra     :-
:       lda     fscr                    ; room at the right: show more on the left
        beq     :+
        dec     a
        tax
        ldy     flen
        jsr     fd_wid
        inc     a
        cmp     fw
        beq     :+
        bcs     :+
        dec     fscr
        bra     :-
:       rts

; drawn without a blank moment: the text in pieces with their paper (before, in, after the
; selection), then the white around it
ui_fd_draw:
        jsr     fd_load
        jsr     ui_box
        lda     #1
        jsr     ui_bevel
        jsr     @in
        ldx     z:ui_c
        lda     a:CT_FLAGS,x
        and     #UF_FOCUS
        sta     ffoc
        beq     :+
        lda     #WD_FRAME | (C_SELECT << 8)
        jsr     ui_rect
        jsr     @in
:       lda     z:ui_x                  ; the inside: fix, fiy, fiw, fih
        sta     fix
        lda     z:ui_y
        sta     fiy
        lda     z:ui_w
        sta     fiw
        lda     z:ui_h
        sta     fih
        jsr     ui_box
        lda     z:ui_x                  ; text origin
        clc
        adc     #4
        sta     ftx
        lda     z:ui_h
        sec
        sbc     #8
        lsr     a
        clc
        adc     z:ui_y
        dec     a                       ; (the paper starts a line above the ink)
        sta     fty
        ldy     fscr                    ; the part that fits: fscr .. fend
        stz     fac
@v:     cpy     flen
        bcs     @ve
        lda     (ui_q),y
        ldx     #0
        jsr     ui_cwidth
        clc
        adc     fac
        cmp     fw
        beq     :+
        bcs     @ve
:       sta     fac
        iny
        bra     @v
@ve:    sty     fend
        lda     fend                    ; the selection shown: fs0 .. fs1 (none: at the end)
        sta     fs0
        sta     fs1
        lda     ffoc
        beq     @txt
        lda     fanc
        cmp     fcur
        beq     @txt
        ldx     fcur
        ldy     fanc
        bcs     :+
        ldx     fanc
        ldy     fcur
:       cpx     fscr
        bcs     :+
        ldx     fscr
:       cpy     fend
        bcc     :+
        ldy     fend
:       stx     fs0
        sty     fs1
        cpx     fs1
        bcc     @txt
        lda     fend
        sta     fs0
        sta     fs1
@txt:   stz     z:ui_font
        lda     fty
        sta     z:ui_y
        ldx     fscr
        ldy     fs0
        lda     #C_BLACK | (C_WHITE << 8)
        jsr     @piece
        ldx     fs0
        ldy     fs1
        lda     #C_WHITE | (C_SELECT << 8)
        jsr     @piece
        ldx     fs1
        ldy     fend
        lda     #C_BLACK | (C_WHITE << 8)
        jsr     @piece
        ldx     fscr                    ; the white around: right of the text
        ldy     fend
        jsr     fd_wid
        clc
        adc     ftx
        sta     z:ui_x
        lda     fix
        clc
        adc     fiw
        sec
        sbc     z:ui_x
        sta     z:ui_w
        lda     fty
        sta     z:ui_y
        lda     #11
        sta     z:ui_h
        jsr     @white
        lda     fix                     ; left of it
        sta     z:ui_x
        lda     ftx
        sec
        sbc     fix
        sta     z:ui_w
        jsr     @white
        lda     fiw                     ; above
        sta     z:ui_w
        lda     fiy
        sta     z:ui_y
        lda     fty
        sec
        sbc     fiy
        sta     z:ui_h
        jsr     @white
        lda     fty                     ; below
        clc
        adc     #11
        sta     z:ui_y
        lda     fiy
        clc
        adc     fih
        sec
        sbc     z:ui_y
        sta     z:ui_h
        jsr     @white
        lda     ffoc                    ; the cursor
        beq     @out
        lda     fcur
        cmp     fend
        beq     :+
        bcs     @out
:       ldx     fscr
        ldy     fcur
        jsr     fd_wid
        clc
        adc     ftx
        dec     a
        sta     z:ui_x
        lda     #1
        sta     z:ui_w
        lda     fty
        sta     z:ui_y
        lda     #11
        sta     z:ui_h
        lda     #WD_FILL | (C_BLACK << 8)
        jmp     ui_rect
@out:   rts
@white: lda     z:ui_w
        beq     :+
        bmi     :+
        lda     z:ui_h
        beq     :+
        bmi     :+
        lda     #WD_FILL | (C_WHITE << 8)
        jmp     ui_rect
:       rts
@in:    inc     z:ui_x
        inc     z:ui_y
        dec     z:ui_w
        dec     z:ui_w
        dec     z:ui_h
        dec     z:ui_h
        rts
; the text X .. Y in colours A (ink | paper << 8), at its place
@piece: stx     fs2
        sty     fs3
        cpx     fs3
        bcs     :++
        pha
        ldx     fscr
        ldy     fs2
        jsr     fd_wid
        clc
        adc     ftx
        sta     z:ui_x
        ldy     fs2
        ldx     #0
:       lda     (ui_q),y
        sta     ui_tbuf,x
        inx
        iny
        cpy     fs3
        bcc     :-
        stz     ui_tbuf,x
        pla
        ldx     #.loword(ui_tbuf)
        jmp     ui_text
:       rts

; the character under pointer x A (relative to the field) -> A
fd_hit: sec
        sbc     #4
        bpl     :+
        lda     fscr                    ; left of the text: one more to the left
        beq     @r
        dec     a
@r:     rts
:       sta     fpx
        stz     fac
        ldy     fscr
@c:     cpy     flen
        bcs     @end
        lda     (ui_q),y
        ldx     #0
        jsr     ui_cwidth
        sta     fto
        lsr     a
        clc
        adc     fac
        cmp     fpx
        beq     :+
        bcs     @at
:       lda     fac
        clc
        adc     fto
        sta     fac
        iny
        bra     @c
@at:    tya
        rts
@end:   lda     flen
        rts

ui_fd_press:
        jsr     fd_load
        lda     ui_px
        jsr     fd_hit
        sta     fcur
        lda     ui_kmod                 ; Shift: extend the selection
        and     #$22
        bne     :+
        lda     fcur
        sta     fanc
:       bra     fd_done_used

ui_fd_drag:
        lda     ui_rel
        bne     :+
        jsr     fd_load
        lda     ui_px
        jsr     fd_hit
        cmp     fcur
        beq     :+
        sta     fcur
        bra     fd_done_used
:       lda     #UA_USED
        rts

; store, scroll, draw -> UA_USED / UA_CHANGE
fd_done_used:
        lda     #UA_USED
        bra     fd_done
fd_done_chg:
        lda     #UA_CHANGE
fd_done:
        pha
        jsr     fd_scroll
        jsr     fd_store
        ldx     z:ui_c
        jsr     ui_fd_draw
        pla
        rts

; a key (ui_key, ui_kmod) -> UA_*
ui_fd_key:
        jsr     fd_load
        lda     ui_kmod
        and     #$22
        sta     fshift
        lda     ui_kmod
        and     #$11
        beq     @plain
        lda     ui_key                  ; ctrl
        cmp     #1
        bne     :+
        stz     fanc                    ; ctrl-A
        lda     flen
        sta     fcur
        bra     fd_done_used
:       cmp     #3
        bne     :+
        jsr     fd_copy                 ; ctrl-C
        lda     #UA_USED
        rts
:       cmp     #24
        bne     :+
        jsr     fd_copy                 ; ctrl-X
        jsr     fd_delsel
        bra     fd_done_chg
:       cmp     #22
        jeq     fd_paste
        lda     #UA_NONE
        rts
@plain: lda     ui_key
        cmp     #KEY_LEFT
        bne     @r
        jsr     fd_unsel                ; (no Shift, a selection: to its start)
        bcc     @l1
        lda     fs0
        bra     @mv
@l1:    lda     fcur
        beq     @mv
        dec     a
        bra     @mv
@r:     cmp     #KEY_RIGHT
        bne     @h
        jsr     fd_unsel
        bcc     @r1
        lda     fs1
        bra     @mv
@r1:    lda     fcur
        cmp     flen
        bcs     @mv
        inc     a
        bra     @mv
@h:     cmp     #KEY_HOME
        bne     @e
        lda     #0
        bra     @mv
@e:     cmp     #KEY_END
        bne     @bs
        lda     flen
@mv:    sta     fcur
        lda     fshift
        bne     :+
        lda     fcur
        sta     fanc
:       jmp     fd_done_used
@bs:    cmp     #8
        bne     @del
        lda     fanc
        cmp     fcur
        bne     @ds
        lda     fcur
        beq     @nothing
        dec     a
        sta     fanc
        bra     @ds
@del:   cmp     #KEY_DEL
        bne     @chr
        lda     fanc
        cmp     fcur
        bne     @ds
        lda     fcur
        cmp     flen
        bcs     @nothing
        inc     a
        sta     fanc
@ds:    jsr     fd_delsel
        jmp     fd_done_chg
@chr:   cmp     #' '
        bcc     @none
        cmp     #$7F
        bcs     @none
        pha
        jsr     fd_delsel
        pla
        jsr     fd_ins
        jmp     fd_done_chg
@nothing:
        lda     #UA_USED
        rts
@none:  lda     #UA_NONE
        rts

; C set if there is a selection (fs0 .. fs1 = its ends, ordered)
fd_sel: lda     fcur
        ldx     fanc
        cmp     fanc
        beq     @no
        bcc     :+
        stx     fs0
        sta     fs1
        sec
        rts
:       sta     fs0
        stx     fs1
        sec
        rts
@no:    clc
        rts
; the same, but only without Shift (left / right then collapse it)
fd_unsel:
        lda     fshift
        bne     :+
        jmp     fd_sel
:       clc
        rts

; delete the selection (if any)
fd_delsel:
        jsr     fd_sel
        bcc     @out
        ldx     fs0                     ; buf[fs0..] = buf[fs1..] with the terminator
        ldy     fs1
        sep     #$20
        .a8
:       lda     (ui_q),y
        phy
        txy
        sta     (ui_q),y
        ply
        inx
        iny
        cmp     #0
        bne     :-
        rep     #$20
        .a16
        lda     fs1
        sec
        sbc     fs0
        eor     #$FFFF
        sec
        adc     flen
        sta     flen
        lda     fs0
        sta     fcur
        sta     fanc
@out:   rts

; insert character A at the cursor (if there is room)
fd_ins: sta     fac
        lda     flen
        inc     a
        cmp     fmax
        bcs     @out
        ldy     flen                    ; move buf[cur..len] (and the 0) one up
        iny
        sep     #$20
        .a8
:       dey
        lda     (ui_q),y
        iny
        sta     (ui_q),y
        dey
        cpy     fcur
        bne     :-
        lda     fac
        sta     (ui_q),y
        rep     #$20
        .a16
        inc     flen
        inc     fcur
        lda     fcur
        sta     fanc
@out:   rts

; the selection to the clipboard
fd_copy:
        jsr     fd_sel
        bcc     @out
        lda     z:ui_q
        clc
        adc     fs0
        sta     fcb
        lda     #^fcb
        sta     fcb+2
        lda     fs1
        sec
        sbc     fs0
        sta     fcb+3
        ptr     fcb
        sys     SYS_CLPUT
@out:   rts

; ctrl-V: the clipboard's first line, inserted
fd_paste:
        jsr     fd_delsel
        lda     #.loword(ui_tbuf)
        sta     fcb
        lda     #^ui_tbuf
        sta     fcb+2
        lda     #255
        sta     fcb+3
        ptr     fcb
        sys     SYS_CLGET
        bcs     @done
        cmp     #256
        bcc     :+
        lda     #255
:       sta     fpx
        ldx     #0
@c:     cpx     fpx
        bcs     @done
        lda     ui_tbuf,x
        and     #$00FF
        cmp     #10
        beq     @done
        cmp     #13
        beq     @done
        phx
        cmp     #' '
        bcc     :+
        cmp     #$7F
        bcs     :+
        jsr     fd_ins
:       plx
        inx
        bra     @c
@done:  jmp     fd_done_chg

; X = field, Y = string: its new text, all selected
ui_fdset:
        jsr     ui_setc
        jsr     fd_load
        sty     z:ui_t0
        ldy     #0
        sep     #$20
        .a8
:       lda     (ui_t0),y
        beq     :+
        sta     (ui_q),y
        iny
        cpy     fmax
        bcc     :-
        dey
:       lda     #0
        sta     (ui_q),y
        rep     #$20
        .a16
        sty     flen
        sty     fcur
        stz     fanc
        stz     fscr
        jmp     fd_done_used

        .segment "BSS"
fmax:   .res    2
flen:   .res    2
fcur:   .res    2
fanc:   .res    2
fscr:   .res    2
fw:     .res    2
fto:    .res    2
fac:    .res    2
ftx:    .res    2
fty:    .res    2
fend:   .res    2
ffoc:   .res    2
fs0:    .res    2
fs1:    .res    2
fsx:    .res    2
fs2:    .res    2
fs3:    .res    2
fix:    .res    2
fiy:    .res    2
fiw:    .res    2
fih:    .res    2
fpx:    .res    2
fshift: .res    2
fcb:    .res    6
