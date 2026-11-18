; bas_con.s - the console window: scrollback, drawing, the line editor.
;
; The text lives in the scrollback bank CB: 512 rows of 128 characters, a ring indexed by
; absolute row numbers (16-bit, wrapping): row a is at CB:(a & 511) * 128. Rows cbase ..
; lrow are kept (at most 512); the output position is crow, ccol (crow <= lrow: the line
; editor puts it inside a wrapped input line). The window shows vis rows from vtop, ccols
; columns (the content width; a row keeps 128). follow = 1: the view keeps the last row in
; sight (it is 0 after the user scrolled back with the scroll bar, the wheel or PgUp).
; Drawing is deferred: changed rows are marked in dirt[] and con_flush draws the marked
; rows in view (or all of them when the view moved): one text call (the fixed 8x12 font,
; black on white like Edit) and one fill per row. The immediate loop flushes before it
; waits; a running program flushes from `periodic` every FLUSHMS.
; The cursor (a 1-pixel bar like Edit's) is shown only while the line editor waits.

        .segment "CODE"
        .a16
        .i16
CROWS   = 512
CMAXC   = 128
LH      = 12                            ; row height
TOPM    = 2                             ; margins of the text area
LEFTM   = 4
IMAX    = 240                           ; the longest input line
NHIST   = 8

con_open:
        ptr     wopen
        sys     SYS_WOPEN
        bcc     :+
        rts
:       sta     win
        a8
        sta     es_sb+CT_WIN
        a16
        lda     win
        ptr     menus
        sys     SYS_WMENU
        lda     wopen+4
        sta     cw
        lda     wopen+6
        sta     chh
        jsr     con_geom
        stz     cbase
        stz     crow
        stz     lrow
        stz     ccol
        stz     vtop
        lda     #1
        sta     follow
        sta     cfull
        lda     #$FFFF
        sta     dcrow
        sta     vdrawn
        sta     sbl_page
        lda     #0
        jsr     con_clrrow
        jsr     con_flush
        clc
        rts

; the content size cw x chh -> text area, columns, rows, scroll bar
con_geom:
        lda     cw
        sec
        sbc     #UI_SBW
        sta     tw
        sec
        sbc     #LEFTM + 2
        lsr     a
        lsr     a
        lsr     a
        cmp     #8
        bcs     :+
        lda     #8
:       cmp     #CMAXC
        bcc     :+
        lda     #CMAXC
:       sta     ccols
        lda     chh
        sec
        sbc     #TOPM
        ldx     #0
:       cmp     #LH
        bcc     :+
        sbc     #LH
        inx
        bra     :-
:       txa
        bne     :+
        inc     a
:       sta     vis
        lda     tw
        sta     es_sb+CT_X
        stz     es_sb+CT_Y
        lda     #UI_SBW
        sta     es_sb+CT_W
        lda     chh
        sta     es_sb+CT_H
        lda     #$FFFF
        sta     sbl_page
        rts

; A = absolute row -> cp = its characters
con_rowaddr:
        and     #CROWS - 1
        xba
        lsr     a
        sta     z:cp
        lda     cbank
        sta     z:cp+2
        rts

; A = row: spaces, marked
con_clrrow:
        pha
        jsr     con_rowaddr
        lda     #$2020
        ldy     #CMAXC - 2
:       sta     [cp],y
        dey
        dey
        bpl     :-
        pla
        ; fall through
; A = row: draw it at the next flush (keeps A, X? no: X clobbered, keeps Y)
con_dirty:
        and     #CROWS - 1
        tax
        a8
        lda     #1
        sta     dirt,x
        a16
        rts

; X = string in our bank
con_puts:
        stx     z:t7
:       lda     (t7)
        and     #$00FF
        beq     :+
        jsr     con_putc
        inc     z:t7
        bra     :-
:       rts

; a new line
con_nl: lda     #10
        ; fall through
; character A: LF new line, CR column 0, BS back, FF clear, 32-126 printed (others '?')
con_putc:
        and     #$00FF
        ldx     mirror
        beq     :+
        pha
        jsr     out_char
        pla
:       cmp     #32
        bcs     con_rawc
        cmp     #10
        beq     con_nl0
        cmp     #13
        bne     :+
        stz     ccol
        rts
:       cmp     #12
        jeq     con_cls
        cmp     #8
        bne     :+
        lda     ccol
        beq     :+
        dec     ccol
:       rts
; character A at the output position (wraps at the width)
con_rawc:
        cmp     #127
        bcc     :+
        lda     #'?'
:       pha
        lda     ccol
        cmp     ccols
        bcc     :+
        jsr     con_nl0
:       lda     crow
        jsr     con_rowaddr
        pla
        ldy     ccol
        a8
        sta     [cp],y
        a16
        inc     ccol
        lda     crow
        jmp     con_dirty

; to the next row (a new one after the last); the view follows
con_nl0:
        stz     ccol
        lda     crow
        cmp     lrow
        bne     @old
        inc     a
        sta     crow
        sta     lrow
        jsr     con_clrrow
        lda     lrow                    ; more than 512 rows: the oldest goes
        sec
        sbc     cbase
        cmp     #CROWS
        bcc     :+
        inc     cbase
        lda     vtop
        sec
        sbc     cbase
        bpl     :+
        lda     cbase
        sta     vtop
:       lda     follow
        beq     :+
        jmp     con_follow
:       rts
@old:   inc     a
        sta     crow
        rts

; to the start of a line (a new line unless at column 0)
con_bol:
        lda     ccol
        beq     :+
        jmp     con_nl
:       rts

; FF / CLS: the scrollback is cleared, the output at the top
con_cls:
        lda     lrow
        sta     crow
        jsr     con_nl0
        lda     crow
        sta     cbase
        sta     vtop
        lda     #1
        sta     follow
        sta     cfull
        rts

; the view shows the last row
con_follow:
        lda     lrow
        sec
        sbc     cbase
        inc     a
        sec
        sbc     vis
        bcs     :+
        lda     #0
:       clc
        adc     cbase
        sta     vtop
        rts

; the scroll bar moved (ui_event UA_CHANGE)
con_sbmoved:
        lda     es_sb+SB_POS            ; (the bar shows it already)
        sta     sbl_pos
        clc
        adc     cbase
        sta     vtop
        stz     follow
        lda     es_sb+SB_POS
        cmp     es_sb+SB_MAX
        bcc     :+
        lda     #1
        sta     follow
:       jmp     con_flush

; draw what changed (keeps t0-t7: it also runs from event polling inside a statement)
con_flush:
        pei     (t2)
        pei     (t3)
        pei     (t4)
        lda     #1                      ; (the screen shows the whole change at once)
        sys     SYS_WSHOLD
        jsr     @go
        lda     #0
        sys     SYS_WSHOLD
        pla
        sta     z:t4
        pla
        sta     z:t3
        pla
        sta     z:t2
        rts
@go:    lda     win
        sta     z:ui_win
        lda     curshow                 ; the cursor: its old and new rows
        beq     @nocur
        lda     crow
        cmp     dcrow
        bne     @mv
        lda     ccol
        cmp     dccol
        beq     @cdone
@mv:    lda     dcrow
        cmp     #$FFFF
        beq     :+
        jsr     con_dirty
:       lda     crow
        sta     dcrow
        jsr     con_dirty
        lda     ccol
        sta     dccol
        bra     @cdone
@nocur: lda     dcrow
        cmp     #$FFFF
        beq     @cdone
        jsr     con_dirty
        lda     #$FFFF
        sta     dcrow
@cdone: lda     cfull
        bne     @full
        lda     vtop
        sec
        sbc     vdrawn
        beq     @part
        jsr     con_scroll              ; moved by less than a page: copy, mark the new rows
        bcs     @full
@part:  stz     z:t2                    ; the marked rows in view
@l:     lda     z:t2
        cmp     vis
        jcs     @sb
        clc
        adc     vtop
        and     #CROWS - 1
        tax
        lda     dirt,x
        and     #$00FF
        beq     :+
        a8
        stz     dirt,x
        a16
        jsr     con_drawrow
:       inc     z:t2
        bra     @l
@full:  stz     cfull
        lda     vtop
        sta     vdrawn
        stz     z:ui_x                  ; the top margin
        stz     z:ui_y
        lda     tw
        sta     z:ui_w
        lda     #TOPM
        sta     z:ui_h
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     ui_rect
        stz     z:t2
:       lda     z:t2
        clc
        adc     vtop
        and     #CROWS - 1
        tax
        a8
        stz     dirt,x
        a16
        jsr     con_drawrow
        inc     z:t2
        lda     z:t2
        cmp     vis
        bcc     :-
        lda     vis                     ; below the last row
        asl     a
        adc     vis
        asl     a
        asl     a
        adc     #TOPM
        sta     z:ui_y
        lda     chh
        sec
        sbc     z:ui_y
        beq     @sb
        bmi     @sb
        sta     z:ui_h
        stz     z:ui_x
        lda     tw
        sta     z:ui_w
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     ui_rect
@sb:    ; fall through
; the scroll bar, if anything changed for it
con_sbupdate:
        lda     vtop
        sec
        sbc     cbase
        sta     es_sb+SB_POS
        lda     lrow
        sec
        sbc     cbase
        inc     a
        sec
        sbc     vis
        bcs     :+
        lda     #0
:       sta     es_sb+SB_MAX
        lda     vis
        sta     es_sb+SB_PAGE
        lda     #1
        sta     es_sb+SB_STEP
        lda     es_sb+SB_MAX
        cmp     sbl_max
        bne     :+
        lda     es_sb+SB_PAGE
        cmp     sbl_page
        bne     :+
        lda     es_sb+SB_POS            ; only the position: the thumb moves
        cmp     sbl_pos
        beq     :++
        ldx     sbl_pos
        stx     es_sb+SB_POS
        sta     sbl_pos
        ldx     #.loword(es_sb)
        jmp     ui_sbpos
:       lda     es_sb+SB_POS
        sta     sbl_pos
        lda     es_sb+SB_MAX
        sta     sbl_max
        lda     es_sb+SB_PAGE
        sta     sbl_page
        ldx     #.loword(es_sb)
        jsr     ui_draw
:       rts

; the view moved by A rows (vtop - vdrawn, signed, not 0). Less than a page: the rows
; that stay move with one copy (WD_COPY) and the rows that come into view are marked for
; drawing, C clear. C set: too far (draw everything).
con_scroll:
        cmp     #$8000
        bcs     @down
        cmp     vis
        bcs     @far
        sta     z:t3                    ; up: rows t3.. -> 0..
        jsr     @mul12
        adc     #TOPM
        sta     z:ui_y
        ldy     #TOPM
        lda     vtop                    ; new: the last t3 rows
        clc
        adc     vis
        sec
        sbc     z:t3
        bra     @copy
@far:   sec
        rts
@down:  eor     #$FFFF
        inc     a
        cmp     vis
        bcs     @far
        sta     z:t3                    ; down: rows 0.. -> t3..
        jsr     @mul12
        adc     #TOPM
        tay
        lda     #TOPM
        sta     z:ui_y
        lda     vtop                    ; new: the first t3 rows
@copy:  sta     z:t4
        stz     z:ui_x
        lda     tw
        sta     z:ui_w
        lda     vis
        sec
        sbc     z:t3
        jsr     @mul12
        sta     z:ui_h
        ldx     #0
        jsr     ui_copy
:       lda     z:t4
        jsr     con_dirty
        inc     z:t4
        dec     z:t3
        bne     :-
        lda     vtop
        sta     vdrawn
        clc
        rts
@mul12: sta     z:t2                    ; A * 12 (C clear after)
        asl     a
        adc     z:t2
        asl     a
        asl     a
        rts

; screen row t2 (row vtop + t2): its text, the rest white, the cursor
con_drawrow:
        lda     z:t2
        asl     a
        adc     z:t2
        asl     a
        asl     a
        adc     #TOPM
        sta     ry
        lda     z:t2
        clc
        adc     vtop
        sta     z:t3                    ; the absolute row
        sec
        sbc     cbase
        sta     z:t4
        lda     lrow
        sec
        sbc     cbase
        cmp     z:t4
        bcs     :+
        stz     z:t4                    ; past the last row: blank
        bra     @fill
:       lda     z:t3
        jsr     con_rowaddr
        ldy     #0                      ; the characters, without trailing spaces
        ldx     #0
:       cpy     ccols
        bcs     :++
        lda     [cp],y
        and     #$00FF
        sta     rbuf,y
        cmp     #' '
        beq     :+
        tyx
        inx
:       iny
        bra     :--
:       stx     z:t4                    ; t4 = characters drawn
        stz     rbuf,x
        cpx     #0
        beq     @fill
        lda     #LEFTM
        sta     z:ui_x
        lda     ry
        sta     z:ui_y
        lda     #1
        sta     z:ui_font
        ldx     #.loword(rbuf)
        lda     #C_BLACK | (C_WHITE << 8)
        jsr     ui_text
@fill:  stz     z:ui_x                  ; the left margin
        lda     ry
        sta     z:ui_y
        lda     #LEFTM
        sta     z:ui_w
        lda     #LH
        sta     z:ui_h
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     ui_rect
        lda     z:t4                    ; right of the text
        asl     a
        asl     a
        asl     a
        adc     #LEFTM
        sta     z:ui_x
        lda     tw
        sec
        sbc     z:ui_x
        beq     :+
        bmi     :+
        sta     z:ui_w
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     ui_rect
:       lda     curshow                 ; the cursor
        beq     @out
        lda     z:t3
        cmp     crow
        bne     @out
        lda     ccol
        asl     a
        asl     a
        asl     a
        adc     #LEFTM - 1
        sta     z:ui_x
        lda     #1
        sta     z:ui_w
        lda     #WD_FILL | (C_BLACK << 8)
        jmp     ui_rect
@out:   rts

; ---------------------------------------------------------------- numbers on the console
; flo, fhi: signed decimal
con_putnum:
        jsr     fmt_int
        jmp     con_puts
; A: unsigned decimal (16-bit)
con_putu16:
        sta     flo
        stz     fhi
        bra     con_putnum
; A: two hex digits
con_puthex8:
        pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     @nib
        pla
@nib:   and     #$000F
        cmp     #10
        bcc     :+
        adc     #6
:       adc     #'0'
        jmp     con_putc

; ---------------------------------------------------------------- the line editor
; A = 0: a command line, 1: INPUT. Edits a line at the output position: characters
; insert, Backspace / Delete, Left / Right, Home / End, Up / Down the last 8 lines, PgUp /
; PgDn scroll the console, Esc or ctrl-C clear the line (INPUT: they break). Enter ends.
; -> C clear: ibuf holds the line (zero-terminated), A = its length; the output position
; is on the next line. C set: A = an action (ACT_BREAK, ACT_MENU, ACT_CLOSE).
con_input:
        ldx     script
        beq     :+
        jmp     script_input
:       sta     imode
        stz     ilen
        stz     ipos
        stz     iold
        lda     crow
        sta     srow
        lda     ccol
        sta     scol
        lda     #1
        sta     curshow
        lda     hcnt
        sta     hsel
        lda     follow
        bne     @loop
        lda     #1
        sta     follow
        jsr     con_follow
@loop:  jsr     con_render
@show:  jsr     con_flush
        jsr     gfx_flush
@key:   jsr     getkey
        bcc     :+
        pha
        jsr     @fin
        pla
        sec
        rts
:       sta     ikey
        cmp     #KEY_PGUP
        jeq     @pgup
        cmp     #KEY_PGDN
        jeq     @pgdn
        lda     follow                  ; any other key: back to the line
        bne     :+
        lda     #1
        sta     follow
        jsr     con_follow
:       lda     ikey
        cmp     #13
        jeq     @enter
        cmp     #8
        jeq     @bs
        cmp     #KEY_DEL
        jeq     @del
        cmp     #KEY_LEFT
        jeq     @left
        cmp     #KEY_RIGHT
        jeq     @right
        cmp     #KEY_HOME
        jeq     @home
        cmp     #KEY_END
        jeq     @end
        cmp     #KEY_UP
        jeq     @up
        cmp     #KEY_DOWN
        jeq     @down
        cmp     #27
        jeq     @esc
        cmp     #3
        jeq     @esc
        cmp     #' '
        jcc     @show
        cmp     #127
        jcs     @show
        ldx     ilen                    ; insert at ipos
        cpx     #IMAX
        bcc     :+
        jsr     ui_beep
        jmp     @show
:       cpx     ipos
        beq     :+
        dex
        lda     ibuf,x
        inx
        a8
        sta     ibuf,x
        a16
        dex
        bra     :-
:       lda     ikey
        a8
        sta     ibuf,x
        a16
        inc     ilen
        inc     ipos
        jmp     @loop
@bs:    lda     ipos
        jeq     @show
        dec     ipos
@del:   ldx     ipos
        cpx     ilen
        jcs     @show
:       inx
        cpx     ilen
        bcs     :+
        lda     ibuf,x
        dex
        a8
        sta     ibuf,x
        a16
        inx
        bra     :-
:       dec     ilen
        jmp     @loop
@left:  lda     ipos
        jeq     @show
        dec     ipos
        jmp     @loop
@right: lda     ipos
        cmp     ilen
        jcs     @show
        inc     ipos
        jmp     @loop
@home:  stz     ipos
        jmp     @loop
@end:   lda     ilen
        sta     ipos
        jmp     @loop
@esc:   lda     imode
        beq     :+
        lda     #ACT_BREAK              ; (INPUT gets Esc as a break from pump; this is
        jsr     @fin                    ; ctrl-C typed ahead)
        lda     #ACT_BREAK
        sec
        rts
:       stz     ilen
        stz     ipos
        lda     hcnt
        sta     hsel
        jmp     @loop
@up:    lda     hsel
        jeq     @show
        dec     a
        bra     @recall
@down:  lda     hsel
        cmp     hcnt
        jcs     @show
        inc     a
@recall:
        sta     hsel
        stz     ilen
        cmp     hcnt
        bcs     @rdone
        xba                             ; entry * 256
        tax
        ldy     #0
:       lda     f:WIN_HIST,x
        and     #$00FF
        beq     :+
        a8
        sta     ibuf,y
        a16
        inx
        iny
        bra     :-
:       sty     ilen
@rdone: lda     ilen
        sta     ipos
        jmp     @loop
@pgup:  lda     vtop
        sec
        sbc     cbase
        sec
        sbc     vis
        bcs     :+
        lda     #0
:       clc
        adc     cbase
        sta     vtop
        stz     follow
        jmp     @show
@pgdn:  lda     vtop
        clc
        adc     vis
        sta     vtop
        sec
        sbc     cbase
        clc
        adc     vis
        sta     z:t0
        lda     lrow
        sec
        sbc     cbase
        inc     a
        cmp     z:t0
        bcs     :+
        lda     #1
        sta     follow
        jsr     con_follow
:       jmp     @show
@enter: jsr     @fin
        lda     ilen                    ; zero-terminated
        tax
        a8
        stz     ibuf,x
        a16
        lda     mirror                  ; (test mode: the line in the log)
        beq     @hist
        ldx     #0
:       cpx     ilen
        bcs     :+
        lda     ibuf,x
        and     #$00FF
        phx
        jsr     out_char
        plx
        inx
        bra     :-
:       lda     #10
        jsr     out_char
@hist:  lda     imode                   ; into the history (command lines, not empty)
        bne     @hdone
        lda     ilen
        beq     @hdone
        lda     hcnt
        cmp     #NHIST
        bcc     @hput
        ldx     #0                      ; drop the oldest
@hsh:   lda     f:WIN_HIST+256,x
        sta     f:WIN_HIST,x
        inx
        inx
        cpx     #(NHIST - 1) * 256
        bcc     @hsh
        dec     hcnt
        lda     hcnt
@hput:  xba
        tax
        ldy     #0
@hcp:   lda     ibuf,y
        a8
        sta     f:WIN_HIST,x
        a16
        inx
        iny
        and     #$00FF
        bne     @hcp
        inc     hcnt
@hdone: jsr     con_nl0
        lda     ilen
        clc
        rts
; the end of the editing: cursor after the line and hidden
@fin:   lda     ilen
        sta     ipos
        jsr     con_render
        stz     curshow
        rts

; the input line at srow, scol (blanks after it where it was longer); the output position
; at ipos
con_render:
        lda     srow
        sta     crow
        lda     scol
        sta     ccol
        ldx     #0
:       cpx     ilen
        bcs     :+
        lda     ibuf,x
        and     #$00FF
        phx
        jsr     con_rawc
        plx
        inx
        bra     :-
:       cpx     iold
        bcs     :+
        phx
        lda     #' '
        jsr     con_rawc
        plx
        inx
        bra     :-
:       lda     ilen
        sta     iold
        lda     srow                    ; the position of ipos
        sta     crow
        lda     scol
        clc
        adc     ipos
:       cmp     ccols
        bcc     :+
        sbc     ccols
        inc     crow
        bra     :-
:       sta     ccol
        lda     crow                    ; a row that does not exist yet (the cursor
        sec                             ; after a full last row)
        sbc     cbase
        sta     z:t0
        lda     lrow
        sec
        sbc     cbase
        cmp     z:t0
        bcs     :+
        lda     lrow
        sta     crow
        jsr     con_nl0
:       rts

; the next key (key ring, else events) -> C clear, A = key; C set, A = an action
getkey: jsr     kr_get
        bcc     @out
        lda     brkf
        beq     :+
        stz     brkf
        lda     #ACT_BREAK
        sec
        rts
:       lda     pend_close
        beq     :+
        lda     running                 ; (while running the break comes first)
        bne     :+
        stz     pend_close
        lda     #ACT_CLOSE
        sec
        rts
:       lda     pend_menu
        cmp     #$FFFF
        beq     :+
        lda     #ACT_MENU
        sec
        rts
:       lda     #0
        jsr     pump
        bra     getkey
@out:   rts

        .segment "DATA"
wopen:  .word   12, 22, 534, 268
        .faraddr t_basic
        .byte   WF_RESIZE

        .segment "BSS"
win:    .res    2
cbank:  .res    2
cw:     .res    2
chh:    .res    2
tw:     .res    2
ccols:  .res    2
vis:    .res    2
cbase:  .res    2
crow:   .res    2
ccol:   .res    2
lrow:   .res    2
vtop:   .res    2
vdrawn: .res    2
follow: .res    2
cfull:  .res    2
curshow: .res   2
dcrow:  .res    2
dccol:  .res    2
ry:     .res    2
sbl_pos: .res   2
sbl_max: .res   2
sbl_page: .res  2
imode:  .res    2
ilen:   .res    2
ipos:   .res    2
iold:   .res    2
ikey:   .res    2
srow:   .res    2
scol:   .res    2
hcnt:   .res    2
hsel:   .res    2
dirt:   .res    CROWS
rbuf:   .res    CMAXC + 2
ibuf:   .res    IMAX + 16
