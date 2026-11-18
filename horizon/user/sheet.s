; SHEET - the spreadsheet (/BIN/SHEET.PRG): a resizable window, "sheet [FILE]"; a .CSV
; file is imported. "sheet -t FILE" runs a test script without a window (sht_test.s).
;
; The sheet: 26 columns (A-Z) x 999 rows. A cell holds a number, a text or a formula
; ("=" first). Numbers are decimal fixed point (64 bits, four decimals: sht_num.s);
; formulas (sht_fx.s) are recalculated after every change in dependency order
; (sht_calc.s). Files: the program's own text format .SHT and CSV (sht_file.s). (0.23)
; File > Print (ctrl-P): the used area as text columns, a print job "/PRN:Sheet" (sht_file.s,
; prt_save); an alert if it fails (no message when it works: the Desktop tells). See
; SHEET.md for the user's side.
;
; One assembly unit:
;   sheet.s      start, the window: layout, drawing, keys, mouse, menus, dialogs
;   sht_num.s    numbers: arithmetic, parsing, formatting
;   sht_cell.s   the cell store: an index of 26 x 1024 entries, records in a heap of banks
;   sht_fx.s     formulas: compiler, reference adjuster, evaluator, functions
;   sht_calc.s   recalculation
;   sht_file.s   text forms of a cell, .SHT, CSV, reading and writing files
;   sht_edit.s   copy, paste, fill, clear, insert and delete rows and columns
;   sht_test.s   the self test
;
; Memory: the code bank holds the program and small buffers; banks of their own: the
; index (2), the heap (up to 16), the recalculation's work stack, file data (SB), the
; program's clipboard (CBK), and the test script (-t only).
;
; The window (content coordinates): the entry line (EH lines: the cell's name, a text
; field with its content), the column headers (HH), the rows (RH each) with their numbers
; (RW wide) at the left, a vertical scroll bar at the right, a horizontal one at the
; bottom. Drawing: the rows whose contents or selection changed are redrawn, each cell
; as its background, then its text.
        .include "horizon.inc"
        .include "ui.inc"

TXTMAX  = 250                           ; characters in a cell
DEFW    = 64                            ; column widths (pixels)
MINW    = 16
MAXW    = 400
RW      = 34                            ; the row numbers' column
EH      = 26                            ; the entry line
HH      = 14                            ; the column headers
RH      = 14                            ; a row
CY      = EH + HH                       ; the first row's top
MAXVR   = 48                            ; rows on the screen at most
MAXVC   = 30
NBX     = 4                             ; the name box
NBW     = 64
C_SELBG = 16 + 36 * 4 + 6 * 4 + 5       ; a selected cell's background (light blue)
C_HDRSEL = 16 + 36 * 4 + 6 * 4 + 4      ; a selected row's / column's header
N_ALL   = 1                             ; refresh: everything
N_GRID  = 2                             ;   headers and rows
N_ROWS  = 4                             ;   the rows marked in rdirty
N_HDR   = 8                             ;   the column headers
N_NAME  = 16                            ;   the name box
N_FLD   = 32                            ;   the field shows the cursor's cell
N_SB    = 64                            ;   the scroll bars
N_PART  = 128                           ;   the partial row below the whole ones

        .segment "CODE"
        .a16
        .i16
start:  sta     argl
        stx     argx
        jsr     mem_init
        bcc     :+
        print   "sheet: not enough memory\n"
        exit    1
:       jsr     getarg
        lda     tmode
        beq     :+
        jmp     test_run
:       sys     SYS_WSSTART
        bcc     :+
        print   "sheet: no window system\n"
        exit    1
:       sta     wsown
        jsr     ui_init
        lda     #'#'
        ldx     #0
        jsr     ui_cwidth
        sta     wid_hash
        lda     #'1' << 8 | 'A'         ; (the name box's first contents)
        sta     nmbuf
        ptr     wopen
        sys     SYS_WOPEN
        bcc     :+
        jsr     stopws
        print   "sheet: no window\n"
        exit    1
:       sta     win
        sep     #$20
        .a8
        sta     fld+CT_WIN
        sta     vsb+CT_WIN
        sta     hsb+CT_WIN
        rep     #$20
        .a16
        lda     win
        ptr     menus
        sys     SYS_WMENU
        lda     wopen+4
        sta     cw
        lda     wopen+6
        sta     chh
        jsr     geom
        lda     fpath
        and     #$00FF
        beq     :+
        jsr     do_load
:       jsr     settitle
        stz     dirty
        jsr     recalc
        lda     #N_ALL
        sta     need
        jsr     refresh
        jmp     loop

; banks: the index, the work stack, file data, the clipboard -> C set: no memory
mem_init:
        jsr     n_init
        jsr     cell_init
        bcs     @out
        sys     SYS_BALLOC
        bcs     @out
        sta     z:ws+2
        stz     z:ws
        sys     SYS_BALLOC
        bcs     @out
        sta     sbank
        sta     z:sb+2
        stz     z:sb
        sys     SYS_BALLOC
        bcs     @out
        sta     z:cbk+2
        stz     z:cbk
        jsr     sheet_new
        clc
@out:   rts

; an empty sheet: no cells, default widths and formats
sheet_new:
        jsr     cell_wipe
        ldx     #0
:       lda     #DEFW
        sta     colw,x
        inx
        inx
        cpx     #NCOL * 2
        bcc     :-
        ldx     #0
:       stz     colfmt,x
        inx
        inx
        cpx     #NCOL + 2
        bcc     :-
        stz     ccol
        stz     crow
        stz     acol
        stz     arow
        stz     lcol
        stz     trow
        stz     emod
        lda     #1
        sta     dirty
        rts

stopws: lda     wsown
        beq     :+
        sys     SYS_WSSTOP
:       rts

quit:   lda     win
        sys     SYS_WCLOSE
        jsr     stopws
        exit    0

; the arguments: [-t] [FILE] -> tmode, fpath (absolute)
getarg: stz     fpath
        stz     tmode
        lda     argl
        beq     @out
        ldx     argx
        jsr     args_init
        lda     #120
        ptr     abuf
        jsr     next_arg
        beq     @out
        lda     abuf
        cmp     #'-' | ('t' << 8)
        bne     @path
        lda     abuf+2
        and     #$00FF
        bne     @path
        inc     tmode
        lda     #120
        ptr     abuf
        jsr     next_arg
        beq     @out
@path:  ldx     #.loword(abuf)
        jsr     mkabs
@out:   rts

; the name X (in our bank) made absolute -> fpath
mkabs:  stx     z:t0
        lda     (t0)
        and     #$00FF
        cmp     #'/'
        bne     :+
        ldy     #.loword(fpath)
        jmp     ui_strcpy
:       ptr     fpath
        lda     #128
        sys     SYS_GETCWD
        bcc     :+
        lda     #0
:       tax
        beq     :+
        lda     fpath-1,x
        and     #$00FF
        cmp     #'/'
        beq     :++
:       lda     #'/'
        sta     fpath,x
        inx
:       ldy     #0
:       lda     (t0),y
        and     #$00FF
        sep     #$20
        .a8
        sta     fpath,x
        rep     #$20
        .a16
        beq     :+
        inx
        iny
        cpx     #127
        bcc     :-
        stz     fpath,x
:       rts

; ---------------------------------------------------------------- layout
; the content size cw x chh -> the grid's area, rows shown, the controls' places
geom:   lda     cw
        sec
        sbc     #UI_SBW
        cmp     #RW + 20
        bcs     :+
        lda     #RW + 20
:       sta     gx1
        lda     chh
        sec
        sbc     #UI_SBW
        cmp     #CY + RH
        bcs     :+
        lda     #CY + RH
:       sta     gy1
        sec                             ; full rows; a partial one below them
        sbc     #CY
        ldx     #0
:       cmp     #RH
        bcc     :+
        sbc     #RH
        inx
        bra     :-
:       sta     gpart                   ; the partial row's height
        cpx     #MAXVR
        bcc     :+
        ldx     #MAXVR
        stz     gpart
:       stx     vrows
        lda     #4                      ; the entry line: name box, field
        sta     fld+CT_Y
        lda     #NBX + NBW + 4
        sta     fld+CT_X
        lda     cw
        sec
        sbc     #NBX + NBW + 4 + 4
        sta     fld+CT_W
        lda     gx1                     ; the scroll bars
        sta     vsb+CT_X
        lda     #EH
        sta     vsb+CT_Y
        lda     gy1
        sec
        sbc     #EH
        sta     vsb+CT_H
        stz     hsb+CT_X
        lda     gy1
        sta     hsb+CT_Y
        lda     gx1
        sta     hsb+CT_W
        jsr     hlimit
        lda     #N_ALL
        tsb     need
        rts

; hmax: the largest first column that still fills the grid (Z at the right edge)
hlimit: lda     gx1
        sec
        sbc     #RW
        sta     z:t0
        ldx     #(NCOL - 1) * 2
@l:     lda     z:t0
        sec
        sbc     colw,x
        bcc     @e
        sta     z:t0
        dex
        dex
        bpl     @l
        ldx     #0
        bra     :+
@e:     inx
        inx
        cpx     #NCOL * 2
        bcc     :+
        ldx     #(NCOL - 1) * 2
:       txa
        lsr     a
        sta     hmax
        rts

; the visible columns from lcol: colx (their x), colc (index), coldw (width drawn, cut at
; the grid's edge) -> vcols
colpos: ldx     #0
        lda     lcol
        sta     z:t1
        lda     #RW
        sta     z:t0
@l:     lda     z:t0
        cmp     gx1
        bcs     @e
        lda     z:t1
        cmp     #NCOL
        bcs     @e
        cpx     #MAXVC * 2
        bcs     @e
        lda     z:t0
        sta     colx,x
        lda     z:t1
        sta     colc,x
        asl     a
        tay
        lda     colw,y
        sta     z:t2
        clc
        adc     z:t0
        cmp     gx1                     ; cut at the edge
        bcc     :+
        lda     gx1
        sec
        sbc     z:t0
        sta     z:t2
        lda     gx1
:       sta     z:t0
        lda     z:t2
        sta     coldw,x
        inx
        inx
        inc     z:t1
        bra     @l
@e:     lda     z:t0
        sta     colend                  ; where the last one ends
        txa
        lsr     a
        sta     vcols
        rts

; the cursor shown: rows (ensure_v) and columns (ensure_h) scrolled as needed
ensure: jsr     ensure_v
        jmp     ensure_h
ensure_v:
        lda     crow
        cmp     trow
        bcs     :+
        sta     trow
:       lda     crow
        sec
        sbc     trow
        cmp     vrows
        bcc     :+
        lda     crow
        sec
        sbc     vrows
        inc     a
        sta     trow
:       lda     #NROW                   ; no empty page below row 999
        sec
        sbc     vrows
        bcs     :+
        lda     #0
:       cmp     trow
        bcs     :+
        sta     trow
:       rts
ensure_h:
        lda     ccol
        cmp     lcol
        bcs     :+
        sta     lcol
:       jsr     colpos
@r:     lda     ccol                    ; (the first column shown counts as shown)
        cmp     lcol
        beq     @out
        sec
        sbc     lcol
        cmp     vcols
        bcs     @more
        asl     a
        tax
        lda     ccol
        asl     a
        tay
        lda     colx,x
        clc
        adc     colw,y
        cmp     gx1
        bcc     @out
        beq     @out
@more:  inc     lcol
        jsr     colpos
        bra     @r
@out:   rts

; ---------------------------------------------------------------- drawing
; whatever "need" asks for
refresh:
        lda     win
        sta     z:ui_win
        stz     z:ui_font
        lda     need
        bit     #N_ALL
        beq     :+
        jsr     draw_bar
        lda     #N_GRID | N_SB | N_NAME | N_FLD
        tsb     need
:       lda     need
        bit     #N_FLD
        beq     :+
        jsr     fld_show
:       lda     need
        bit     #N_NAME
        beq     :+
        jsr     draw_name
:       lda     need
        bit     #N_GRID
        beq     @rows
        jsr     colpos
        jsr     draw_hdr
        stz     z:t5
:       lda     z:t5
        cmp     vrows
        bcs     :+
        jsr     draw_row
        inc     z:t5
        bra     :-
:       jsr     draw_part
        bra     @sb
@rows:  lda     need
        bit     #N_HDR
        beq     :+
        jsr     colpos
        jsr     draw_hdr
:       lda     need
        bit     #N_ROWS
        beq     @sb
        jsr     colpos
        stz     z:t5
:       lda     z:t5
        cmp     vrows
        bcs     @sb
        tax
        lda     rdirty,x
        and     #$00FF
        beq     :+
        jsr     draw_row
:       inc     z:t5
        bra     :--
@sb:    lda     need
        bit     #N_PART
        beq     :+
        jsr     draw_part
:       ldx     #0                      ; (the marks are done)
:       stz     rdirty,x
        inx
        inx
        cpx     #MAXVR
        bcc     :-
        lda     need
        bit     #N_SB
        beq     :+
        jsr     draw_sb
:       stz     need
        rts

; the entry line's background and the corner below the scroll bars
draw_bar:
        stz     z:ui_x
        stz     z:ui_y
        lda     cw
        sta     z:ui_w
        lda     #EH - 1
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        lda     #EH - 1
        sta     z:ui_y
        lda     #1
        sta     z:ui_h
        lda     #WD_FILL | (C_MID << 8)
        jsr     ui_rect
        lda     gx1                     ; the corner
        sta     z:ui_x
        lda     gy1
        sta     z:ui_y
        lda     cw
        sec
        sbc     gx1
        sta     z:ui_w
        lda     chh
        sec
        sbc     gy1
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        jmp     ui_rect

; the name box: the cursor's cell, or the range "A1:C5"
draw_name:
        lda     ccol
        xba
        asl     a
        asl     a
        ora     crow
        jsr     ci_name
        lda     ccol                    ; a range: "A1:C5" (the selection's corners)
        cmp     acol
        bne     :+
        lda     crow
        cmp     arow
        beq     @one
:       jsr     selrect
        lda     s_c0
        xba
        asl     a
        asl     a
        ora     s_r0
        jsr     ci_name
        ldx     #.loword(nmbuf)
        ldy     #.loword(nmbuf2)
        jsr     ui_strcpy
        lda     s_c1
        xba
        asl     a
        asl     a
        ora     s_r1
        jsr     ci_name
        ldx     #.loword(nmbuf2)
        jsr     ui_strlen
        tax
        lda     #':'
        sta     nmbuf2,x
        inx
        txa
        clc
        adc     #.loword(nmbuf2)
        tay
        ldx     #.loword(nmbuf)
        jsr     ui_strcpy
        ldx     #.loword(nmbuf2)
        ldy     #.loword(nmbuf)
        jsr     ui_strcpy
@one:   lda     #NBX                    ; a sunken box, the name centred
        sta     z:ui_x
        lda     #4
        sta     z:ui_y
        lda     #NBW
        sta     z:ui_w
        lda     #UI_FLDH
        sta     z:ui_h
        lda     #1
        jsr     ui_bevel
        inc     z:ui_x
        inc     z:ui_y
        dec     z:ui_w
        dec     z:ui_w
        dec     z:ui_h
        dec     z:ui_h
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     ui_rect
        ldx     #.loword(nmbuf)
        lda     #0
        jsr     ui_twidth
        sta     z:t0
        lda     #NBW
        sec
        sbc     z:t0
        lsr     a
        clc
        adc     #NBX
        sta     z:ui_x
        lda     #8
        sta     z:ui_y
        ldx     #.loword(nmbuf)
        lda     #C_BLACK | (C_WHITE << 8)
        jmp     ui_text

; the field shows the cursor's cell as it would be typed (not while editing)
fld_show:
        lda     editing
        bne     :+
        jsr     cur_ci
        jsr     cell_src
        ldx     #.loword(fld)
        ldy     #.loword(tbuf)
        jsr     ui_fdset
        lda     fld+FD_LEN              ; (no selection, the start shown)
        sta     fld+FD_CUR
        sta     fld+FD_ANC
        stz     fld+FD_SCR
        ldx     #.loword(fld)
        jsr     ui_draw
:       rts

; the scroll bars
draw_sb:
        lda     trow
        sta     vsb+SB_POS
        lda     #NROW
        sec
        sbc     vrows
        bpl     :+
        lda     #0
:       sta     vsb+SB_MAX
        lda     vrows
        sta     vsb+SB_PAGE
        lda     #1
        sta     vsb+SB_STEP
        ldx     #.loword(vsb)
        jsr     ui_draw
        lda     lcol
        sta     hsb+SB_POS
        lda     hmax
        sta     hsb+SB_MAX
        jsr     colpos
        lda     vcols
        cmp     #2
        bcc     :+
        dec     a
:       sta     hsb+SB_PAGE
        lda     #1
        sta     hsb+SB_STEP
        ldx     #.loword(hsb)
        jsr     ui_draw
        rts

; the column headers (and the corner box at their left)
draw_hdr:
        jsr     selrect
        stz     z:ui_x                  ; the corner
        lda     #EH
        sta     z:ui_y
        lda     #RW - 1
        sta     z:ui_w
        lda     #HH - 1
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        lda     #RW - 1
        sta     z:ui_x
        lda     #1
        sta     z:ui_w
        lda     #HH
        sta     z:ui_h
        lda     #WD_FILL | (C_MID << 8)
        jsr     ui_rect
        stz     z:ui_x
        lda     #EH + HH - 1
        sta     z:ui_y
        lda     #RW
        sta     z:ui_w
        lda     #1
        sta     z:ui_h
        lda     #WD_FILL | (C_MID << 8)
        jsr     ui_rect
        stz     z:t4
@c:     lda     z:t4
        cmp     vcols
        jcs     @rest
        asl     a
        tax
        lda     colx,x
        sta     z:ui_x
        lda     coldw,x
        sta     z:t2
        lda     colc,x
        sta     z:t3
        lda     #EH
        sta     z:ui_y
        lda     z:t2
        dec     a
        sta     z:ui_w
        lda     #HH - 1
        sta     z:ui_h
        lda     #C_BODY                 ; in the selection: highlighted
        sta     z:t1
        lda     z:t3
        cmp     s_c0
        bcc     :+
        cmp     s_c1
        beq     @hl
        bcs     :+
@hl:    lda     #C_HDRSEL
        sta     z:t1
:       lda     z:t1
        xba
        ora     #WD_FILL
        jsr     ui_rect
        lda     z:t3                    ; the letter, centred
        clc
        adc     #'A'
        sta     hdrs
        ldx     #.loword(hdrs)
        lda     #0
        jsr     ui_twidth
        sta     z:t0
        lda     z:t2
        sec
        sbc     z:t0
        lsr     a
        clc
        adc     z:ui_x
        pha
        lda     z:t1
        xba
        ora     #C_BLACK
        sta     z:t0
        pla
        sta     z:ui_x
        lda     #EH + 2
        sta     z:ui_y
        ldx     #.loword(hdrs)
        lda     z:t0
        jsr     ui_text
        lda     z:t4                    ; its lines: right, bottom
        asl     a
        tax
        lda     colx,x
        clc
        adc     z:t2
        dec     a
        sta     z:ui_x
        lda     #EH
        sta     z:ui_y
        lda     #1
        sta     z:ui_w
        lda     #HH
        sta     z:ui_h
        lda     #WD_FILL | (C_MID << 8)
        jsr     ui_rect
        lda     z:t4
        asl     a
        tax
        lda     colx,x
        sta     z:ui_x
        lda     #EH + HH - 1
        sta     z:ui_y
        lda     z:t2
        sta     z:ui_w
        lda     #1
        sta     z:ui_h
        lda     #WD_FILL | (C_MID << 8)
        jsr     ui_rect
        inc     z:t4
        jmp     @c
@rest:  lda     colend                  ; past Z: plain
        cmp     gx1
        bcs     :+
        sta     z:ui_x
        lda     #EH
        sta     z:ui_y
        lda     gx1
        sec
        sbc     colend
        sta     z:ui_w
        lda     #HH
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
:       rts

; row t5 of the view (row trow + t5): its number, then its cells
draw_row:
        lda     #RH
        sta     dr_h
        stz     dr_part
; (dr_h, dr_part set: the partial row below the last whole one has no texts)
draw_row2:
        jsr     selrect
        lda     z:t5                    ; y = CY + 14 t5 (16 t5 - 2 t5)
        asl     a
        sta     z:t0
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:t0
        clc
        adc     #CY
        sta     dr_y
        lda     z:t5
        clc
        adc     trow
        sta     dr_row
        lda     #C_BODY                 ; the number
        sta     dr_bg
        lda     dr_row
        cmp     s_r0
        bcc     :+
        cmp     s_r1
        beq     @hl
        bcs     :+
@hl:    lda     #C_HDRSEL
        sta     dr_bg
:       stz     z:ui_x
        lda     dr_y
        sta     z:ui_y
        lda     #RW - 1
        sta     z:ui_w
        lda     dr_h
        dec     a
        sta     z:ui_h
        lda     dr_bg
        xba
        ora     #WD_FILL
        jsr     ui_rect
        lda     dr_part
        bne     :+
        lda     dr_row
        inc     a
        ldx     #0
        jsr     put_decx
        ldx     #.loword(nmbuf)
        lda     #0
        jsr     ui_twidth
        eor     #$FFFF
        sec
        adc     #RW - 5
        sta     z:ui_x
        lda     dr_y
        clc
        adc     #2
        sta     z:ui_y
        lda     dr_bg
        xba
        ora     #C_DARK
        ldx     #.loword(nmbuf)
        jsr     ui_text
:       lda     #RW - 1                 ; its lines
        sta     z:ui_x
        lda     dr_y
        sta     z:ui_y
        lda     #1
        sta     z:ui_w
        lda     dr_h
        sta     z:ui_h
        lda     #WD_FILL | (C_MID << 8)
        jsr     ui_rect
        lda     dr_part
        bne     :+
        stz     z:ui_x
        lda     dr_y
        clc
        adc     #RH - 1
        sta     z:ui_y
        lda     #RW - 1
        sta     z:ui_w
        lda     #1
        sta     z:ui_h
        lda     #WD_FILL | (C_MID << 8)
        jsr     ui_rect
:       lda     #RW                     ; the cells: white (past Z: the body colour)
        sta     z:ui_x
        lda     dr_y
        sta     z:ui_y
        lda     colend
        sec
        sbc     #RW
        sta     z:ui_w
        lda     dr_h
        dec     a
        sta     z:ui_h
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     ui_rect
        lda     colend
        cmp     gx1
        bcs     :+
        sta     z:ui_x
        lda     gx1
        sec
        sbc     colend
        sta     z:ui_w
        lda     dr_h
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
:       lda     dr_part                 ; the bottom line
        bne     :+
        lda     #RW
        sta     z:ui_x
        lda     dr_y
        clc
        adc     #RH - 1
        sta     z:ui_y
        lda     colend
        sec
        sbc     #RW
        sta     z:ui_w
        lda     #1
        sta     z:ui_h
        lda     #WD_FILL | (C_LIGHT << 8)
        jsr     ui_rect
:       lda     s_c0                    ; a selection of more than one cell: tinted (but
        cmp     s_c1                    ; not the cursor's cell)
        bne     :+
        lda     s_r0
        cmp     s_r1
        beq     @cells
:       lda     dr_row
        cmp     s_r0
        bcc     @cells
        cmp     s_r1
        beq     :+
        bcs     @cells
:       stz     dr_j
@tint:  lda     dr_j
        cmp     vcols
        bcs     @cells
        asl     a
        tax
        lda     colc,x
        cmp     s_c0
        bcc     @tn
        cmp     s_c1
        beq     :+
        bcs     @tn
:       cmp     ccol
        bne     :+
        lda     dr_row
        cmp     crow
        beq     @tn
:       lda     colx,x
        sta     z:ui_x
        lda     coldw,x
        dec     a
        sta     z:ui_w
        lda     dr_y
        sta     z:ui_y
        lda     dr_h
        dec     a
        sta     z:ui_h
        lda     #WD_FILL | (C_SELBG << 8)
        jsr     ui_rect
@tn:    inc     dr_j
        bra     @tint
@cells: stz     dr_k                    ; the cells, a span at a time
@cell:  lda     dr_k
        cmp     vcols
        jcs     @out
        asl     a
        tax
        lda     colc,x
        sta     dr_c
        lda     dr_part
        bne     @empty
        lda     dr_c
        xba
        asl     a
        asl     a
        ora     dr_row
        sta     dr_ci
        ldx     dr_c
        lda     colfmt,x
        and     #$00FF
        tax
        lda     dr_ci
        jsr     cell_disp
        sta     dr_len
        bra     :+
@empty: stz     dr_len
        stz     dkind
        stz     fbuf
:       lda     dr_k                    ; the span: this cell, and empty ones to the right
        sta     dr_e                    ; for a text too wide for it
        asl     a
        tax
        lda     coldw,x
        sta     dr_sw
        lda     dkind
        cmp     #2
        bne     @span
        ldx     #.loword(fbuf)
        lda     #0
        jsr     ui_twidth
        clc
        adc     #6
        sta     dr_tw
@grow:  lda     dr_sw
        cmp     dr_tw
        bcs     @span
        lda     dr_e
        inc     a
        cmp     vcols
        bcs     @span
        asl     a
        tax
        lda     colc,x
        xba
        asl     a
        asl     a
        ora     dr_row
        tay
        lda     [ixb],y
        and     #$00FF
        bne     @span
        inc     dr_e
        lda     coldw,x
        clc
        adc     dr_sw
        sta     dr_sw
        bra     @grow
@span:  lda     dr_e                    ; the span's last column cut at the edge?
        asl     a
        tax
        stz     dr_cut
        lda     colc,x
        asl     a
        tay
        lda     colw,y
        cmp     coldw,x
        beq     :+
        inc     dr_cut
        sec                             ; (its whole width, in the span)
        sbc     coldw,x
        clc
        adc     dr_sw
        sta     dr_full
:       lda     dr_k                    ; the span's right line
        asl     a
        tax
        lda     colx,x
        sta     dr_x
        clc
        adc     dr_sw
        dec     a
        sta     z:ui_x
        lda     dr_y
        sta     z:ui_y
        lda     #1
        sta     z:ui_w
        lda     dr_h
        sta     z:ui_h
        lda     #WD_FILL | (C_LIGHT << 8)
        jsr     ui_rect
        lda     dr_len                  ; the text
        beq     @frame
        jsr     dr_text
@frame: lda     dr_part                 ; the cursor's frame
        bne     @next
        lda     dr_row
        cmp     crow
        bne     @next
        lda     dr_k
        sta     dr_j
:       lda     dr_j
        asl     a
        tax
        lda     colc,x
        cmp     ccol
        beq     :+
        lda     dr_j
        cmp     dr_e
        beq     @next
        inc     dr_j
        bra     :-
:       lda     colx,x                  ; two pixels inside its lines
        sta     z:ui_x
        lda     coldw,x
        dec     a
        sta     z:ui_w
        lda     dr_y
        sta     z:ui_y
        lda     #RH - 1
        sta     z:ui_h
        lda     #WD_FRAME | (C_SELECT << 8)
        jsr     ui_rect
        inc     z:ui_x
        inc     z:ui_y
        dec     z:ui_w
        dec     z:ui_w
        dec     z:ui_h
        dec     z:ui_h
        lda     #WD_FRAME | (C_SELECT << 8)
        jsr     ui_rect
@next:  lda     dr_e
        inc     a
        sta     dr_k
        jmp     @cell
@out:   rts

; the text fbuf (dr_len) in the span: dr_x, dr_sw; aligned by dalign, ink dink
dr_text:
        lda     dr_sw                   ; the room: span - 6
        sec
        sbc     #6
        bcs     :+
        lda     #0
:       sta     dr_room
        ldx     #.loword(fbuf)
        lda     #0
        jsr     ui_twidth
        sta     dr_tw
        cmp     dr_room
        bcc     @fits
        beq     @fits
        lda     dkind                   ; too wide: a number shows ###, the rest is cut
        cmp     #1
        bne     @cut
        lda     dr_cut                  ; (a column cut at the grid's edge: nothing, if it
        beq     :+                      ;  would fit the whole column)
        lda     dr_full
        sec
        sbc     #6
        cmp     dr_tw
        bcc     :+
        rts
:       ldx     #0
        stz     dr_tw
:       lda     dr_tw
        clc
        adc     wid_hash
        cmp     dr_room
        beq     :+
        bcs     @hashes
:       sta     dr_tw
        lda     #'#'
        sta     fbuf,x
        inx
        cpx     #40
        bcc     :--
@hashes:
        stz     fbuf,x
        bra     @fits
@cut:   ldy     #0                      ; as many characters as fit
        stz     dr_tw
:       lda     fbuf,y
        and     #$00FF
        beq     @fits
        ldx     #0
        jsr     ui_cwidth
        clc
        adc     dr_tw
        cmp     dr_room
        beq     :+
        bcs     @end
:       sta     dr_tw
        iny
        bra     :--
@end:   lda     #0
        sep     #$20
        .a8
        sta     fbuf,y
        rep     #$20
        .a16
@fits:  lda     dalign                  ; x by the alignment
        cmp     #1
        bne     :+
        lda     dr_x                    ; right: 4 pixels from the right line
        clc
        adc     dr_sw
        sec
        sbc     #4
        sec
        sbc     dr_tw
        bra     @x
:       cmp     #2
        bne     :+
        lda     dr_sw                   ; centred
        sec
        sbc     dr_tw
        lsr     a
        clc
        adc     dr_x
        bra     @x
:       lda     dr_x                    ; left
        clc
        adc     #3
@x:     sta     z:ui_x
        lda     dr_y
        clc
        adc     #2
        sta     z:ui_y
        ldx     #.loword(fbuf)
        lda     dink
        ora     #$FF00
        jmp     ui_text

; below the whole rows: a partial row, no texts
draw_part:
        lda     gpart
        beq     :+
        sta     dr_h
        lda     #1
        sta     dr_part
        lda     vrows
        sta     z:t5
        jsr     draw_row2
:       rts

; the selection, ordered -> s_c0 .. s_r1
selrect:
        lda     ccol
        ldx     acol
        cmp     acol
        bcc     :+
        txa
        ldx     ccol
:       sta     s_c0
        stx     s_c1
        lda     crow
        ldx     arow
        cmp     arow
        bcc     :+
        txa
        ldx     crow
:       sta     s_r0
        stx     s_r1
        rts

; the cursor's cell -> A
cur_ci: lda     ccol
        xba
        asl     a
        asl     a
        ora     crow
        rts

; (from the recalculation) cell A's value changed: its row is redrawn if shown
mark_dirty:
        and     #CPC - 1
        sec
        sbc     trow
        bcc     :+
        cmp     vrows
        bcs     :+
        tax
        sep     #$20
        .a8
        lda     #1
        sta     rdirty,x
        rep     #$20
        .a16
        lda     #N_ROWS
        tsb     need
:       rts

; the view went down by A rows (signed, not 0): the rows still shown are copied, the new
; ones marked -> C set: too far (draw everything)
scroll_rows:
        sta     z:t3
        bpl     :+
        eor     #$FFFF
        inc     a
:       cmp     vrows
        bcc     :+
        rts
:       sta     z:t4                    ; |d|
        lda     vrows                   ; the height kept: (vrows - |d|) * RH
        sec
        sbc     z:t4
        jsr     mul14
        sta     z:ui_h
        lda     z:t4
        jsr     mul14
        sta     z:t2                    ; |d| * RH
        lda     win
        sta     z:ui_win
        stz     z:ui_x
        lda     gx1
        sta     z:ui_w
        lda     z:t3
        bmi     @down
        lda     #CY                     ; up: from CY + |d| RH to CY
        clc
        adc     z:t2
        sta     z:ui_y
        ldx     #0
        ldy     #CY
        jsr     ui_copy
        lda     trow                    ; the new rows at the bottom
        clc
        adc     vrows
        sec
        sbc     z:t4
        pha
        lda     trow
        clc
        adc     vrows
        dec     a
        tax
        pla
        bra     @mark
@down:  lda     #CY                     ; down: from CY to CY + |d| RH
        sta     z:ui_y
        lda     #CY
        clc
        adc     z:t2
        tay
        ldx     #0
        jsr     ui_copy
        lda     trow                    ; the new rows at the top
        clc
        adc     z:t4
        dec     a
        tax
        lda     trow
@mark:  jsr     mark_rows
        lda     #N_SB | N_PART
        tsb     need
        clc
        rts
; A * 14 -> A
mul14:  asl     a
        sta     z:t0
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:t0
        rts

; rows A .. X (sheet rows) marked for redrawing (those shown)
mark_rows:
        stx     z:t1
        sta     z:t0
@l:     lda     z:t0
        cmp     z:t1
        beq     :+
        bcs     @out
:       lda     z:t0
        jsr     mark_dirty
        inc     z:t0
        bra     @l
@out:   rts

; ---------------------------------------------------------------- events
loop:   jsr     snap
        lda     #0
        jsr     ui_getev
        bcs     loop
        ldx     #.loword(ctls)
        jsr     ui_event
        cmp     #UA_CHANGE
        bne     @none
        cpx     #.loword(vsb)
        bne     :+
        lda     vsb+SB_POS              ; the scroll bars move the view
        sta     trow
        lda     #3
        sta     nosc
        jmp     post
:       cpx     #.loword(hsb)
        bne     :+
        lda     hsb+SB_POS
        sta     lcol
        lda     #3
        sta     nosc
        jmp     post
:       lda     #1                      ; the field: typing in it is editing
        sta     editing
        jmp     loop
@none:  cmp     #UA_NONE
        beq     :+
        lda     fld+CT_FLAGS            ; (a press in the field focused it: editing)
        and     #UF_FOCUS
        beq     loop
        lda     #1
        sta     editing
        jmp     loop
:       lda     ui_ev
        and     #$00FF
        cmp     #WE_KEY
        jeq     onkey
        cmp     #WE_BUTTON
        jeq     onbutton
        cmp     #WE_MOTION
        jeq     onmotion
        cmp     #WE_CLOSE
        jeq     m_close
        cmp     #WE_RESIZE
        beq     onresize
        cmp     #WE_MENU
        beq     onmenu
        jmp     loop

onresize:
        lda     ui_ev+2
        sta     cw
        lda     ui_ev+4
        sta     chh
        jsr     geom
        jsr     ensure
        jmp     post

onmenu: lda     editing                 ; (a menu while editing: the entry first)
        beq     :+
        jsr     commit
        jcs     loop
:       lda     ui_ev+2                 ; File 0, Edit 1, Format 2
        asl     a
        tax
        lda     ui_ev+4                 ; the item (separators counted)
        asl     a
        tay
        jmp     (mtab,x)
m_file: tyx
        cpx     #18
        jcs     loop
        jmp     (ftab,x)
m_edit: tyx
        cpx     #24
        jcs     loop
        jmp     (etab,x)
m_fmt:  tyx
        cpx     #18
        jcs     loop
        jmp     (otab,x)

; before an event: what is drawn now
snap:   lda     ccol
        sta     o_cc
        lda     crow
        sta     o_cr
        lda     acol
        sta     o_ac
        lda     arow
        sta     o_ar
        lda     lcol
        sta     o_lcol
        lda     trow
        sta     o_trow
        rts

; after it: recalculate if cells changed, scroll to the cursor, redraw what changed
post:   lda     nosc                    ; the view first (the recalculation marks the rows
        and     #1                      ; it changes in the new view)
        bne     :+
        jsr     ensure_v
:       lda     nosc
        and     #2
        bne     :+
        jsr     ensure_h
:       stz     nosc
        lda     dirty
        beq     :+
        stz     dirty
        jsr     recalc
        lda     #N_FLD                  ; (the cursor's cell may have changed too)
        tsb     need
:       lda     lcol                    ; the view moved sideways: all of it
        cmp     o_lcol
        bne     @all
        lda     trow                    ; up or down by less than a page: copied, and the
        sec                             ; rows that come into view drawn
        sbc     o_trow
        beq     @sel
        jsr     scroll_rows
        bcc     @sel
@all:   lda     #N_GRID | N_SB
        tsb     need
        bra     @cur
@sel:   lda     ccol                    ; the selection changed: its rows before and now
        cmp     o_cc
        bne     @ch
        lda     crow
        cmp     o_cr
        bne     @ch
        lda     acol
        cmp     o_ac
        bne     @ch
        lda     arow
        cmp     o_ar
        beq     @cur
@ch:    lda     o_cr
        ldx     o_ar
        jsr     @mk
        lda     crow
        ldx     arow
        jsr     @mk
        lda     ccol                    ; the headers if the columns changed
        cmp     o_cc
        bne     :+
        lda     acol
        cmp     o_ac
        beq     @cur
:       lda     #N_HDR
        tsb     need
@cur:   lda     ccol                    ; the name box, the field
        cmp     o_cc
        bne     :+
        lda     crow
        cmp     o_cr
        bne     :+
        lda     acol
        cmp     o_ac
        bne     :+
        lda     arow
        cmp     o_ar
        beq     :++
:       lda     #N_NAME | N_FLD
        tsb     need
:       jsr     refresh
        jmp     loop
@mk:    cmp     #0                      ; rows A .. X in either order
        stx     z:t2
        cmp     z:t2
        bcc     :+
        pha
        txa
        plx
:       jmp     mark_rows

; a key
onkey:  lda     ui_ev+4
        and     #$00FF
        sta     kmods
        lda     ui_ev+4
        cmp     #$0100
        jcc     loop
        lda     kmods
        and     #$22
        sta     shift
        lda     ui_ev+2                 ; F2 (no character)
        cmp     #$3B
        bne     :+
        lda     editing
        jne     loop
        jmp     ed_f2
:       lda     ui_key
        jeq     loop
        sta     key
        lda     editing
        beq     @grid
        lda     key                     ; editing: the keys the field leaves
        cmp     #27
        jeq     ed_cancel
        cmp     #13
        beq     @cm
        cmp     #9
        beq     @cm
        cmp     #KEY_UP
        beq     @cm
        cmp     #KEY_DOWN
        beq     @cm
        cmp     #KEY_PGUP
        beq     @cm
        cmp     #KEY_PGDN
        beq     @cm
        lda     kmods                   ; ctrl + a key the field does not use
        and     #$11
        jeq     loop
@cm:    jsr     commit
        jcs     loop
@grid:  lda     kmods
        and     #$11
        jne     ctrlkey
        lda     key
        cmp     #KEY_LEFT
        jeq     k_left
        cmp     #KEY_RIGHT
        jeq     k_right
        cmp     #KEY_UP
        jeq     k_up
        cmp     #KEY_DOWN
        jeq     k_down
        cmp     #KEY_PGUP
        jeq     k_pgup
        cmp     #KEY_PGDN
        jeq     k_pgdn
        cmp     #KEY_HOME
        jeq     k_home
        cmp     #KEY_END
        jeq     k_end
        cmp     #13
        jeq     k_enter
        cmp     #9
        jeq     k_tab
        cmp     #KEY_DEL
        jeq     m_clear
        cmp     #27
        jeq     k_esc
        cmp     #8
        jeq     ed_bs
        cmp     #' '
        jcc     loop
        cmp     #$7F
        jcs     loop
        jmp     ed_char

ctrlkey:
        lda     key
        cmp     #KEY_HOME
        bne     :+
        stz     ccol                    ; ctrl-Home: A1
        stz     crow
        jmp     mv
:       cmp     #KEY_END
        bne     @tab
        jsr     used                    ; ctrl-End: the last used cell
        lda     us_c
        beq     :+
        dec     a
:       sta     ccol
        lda     us_r
        beq     :+
        dec     a
:       sta     crow
        jmp     mv
@tab:   ldx     #0
:       lda     ctltab,x
        jeq     loop
        cmp     key
        beq     :+
        inx
        inx
        inx
        inx
        bra     :-
:       jmp     (ctltab+2,x)

k_left: lda     ccol
        jeq     mv
        dec     ccol
        jmp     mv
k_right:
        lda     ccol
        cmp     #NCOL - 1
        bcs     mv
        inc     ccol
        bra     mv
k_up:   lda     crow
        beq     mv
        dec     crow
        bra     mv
k_down: lda     crow
        cmp     #NROW - 1
        bcs     mv
        inc     crow
        bra     mv
k_pgup: lda     crow
        sec
        sbc     vrows
        bcs     :+
        lda     #0
:       sta     crow
        lda     trow
        sec
        sbc     vrows
        bcs     :+
        lda     #0
:       sta     trow
        bra     mv
k_pgdn: lda     crow
        clc
        adc     vrows
        cmp     #NROW
        bcc     :+
        lda     #NROW - 1
:       sta     crow
        lda     trow
        clc
        adc     vrows
        sta     trow
        bra     mv
k_home: stz     ccol
        bra     mv
k_end:  lda     #NCOL - 1               ; the last cell in use in this row (or Z)
        sta     ccol
:       lda     ccol
        beq     mv
        jsr     cur_ci
        tay
        lda     [ixb],y
        and     #$00FF
        bne     mv
        dec     ccol
        bra     :-
; a move: Shift extends the selection, otherwise it follows the cursor
mv:     lda     shift
        bne     :+
        lda     ccol
        sta     acol
        lda     crow
        sta     arow
:       jmp     post
; Enter, Tab: down / right (Shift: up / left), the selection collapses
k_enter:
        stz     z:t0
        lda     shift
        beq     :+
        stz     shift
        jmp     k_up
:       jmp     k_down
k_tab:  lda     shift
        beq     :+
        stz     shift
        jmp     k_left
:       jmp     k_right
k_esc:  lda     ccol
        sta     acol
        lda     crow
        sta     arow
        jmp     post

; ---------------------------------------------------------------- editing
; F2: edit the cell's content, the cursor at its end
ed_f2:  jsr     ed_begin
        jsr     cur_ci
        jsr     cell_src
        ldx     #.loword(fld)
        ldy     #.loword(tbuf)
        jsr     ui_fdset
        lda     fld+FD_LEN
        sta     fld+FD_CUR
        sta     fld+FD_ANC
        ldx     #.loword(fld)
        jsr     ui_draw
        jmp     loop
; Backspace: edit from an empty field
ed_bs:  jsr     ed_begin
        stz     ebuf
        jsr     ed_set
        jmp     loop
; a character: edit, starting with it
ed_char:
        jsr     ed_begin
        lda     key
        and     #$00FF
        sta     ebuf
        jsr     ed_set
        jmp     loop
; the field holds ebuf: the cursor after it, focused
ed_set: ldx     #.loword(ebuf)
        jsr     ui_strlen
        sta     fld+FD_LEN
        sta     fld+FD_CUR
        sta     fld+FD_ANC
        stz     fld+FD_SCR
        ldx     #.loword(fld)
        jmp     ui_draw
ed_begin:
        lda     #1
        sta     editing
        lda     fld+CT_FLAGS
        ora     #UF_FOCUS
        sta     fld+CT_FLAGS
        rts
; leave the field (not focused, the cell's content shown)
ed_end: stz     editing
        lda     fld+CT_FLAGS
        and     #$FFFF ^ UF_FOCUS
        sta     fld+CT_FLAGS
        lda     #N_FLD
        tsb     need
        rts
ed_cancel:
        jsr     ed_end
        jsr     refresh
        jmp     loop
; the field into the cursor's cell -> C set: not taken (a formula error: beep, the
; field stays; out of memory: said so)
commit: ldx     #.loword(ebuf)
        ldy     #.loword(tbuf)
        jsr     ui_strcpy
        jsr     cur_ci
        sta     c_ci
        jsr     cell_enter
        bcc     @ok
        cmp     #CE_MEM
        bne     :+
        jsr     nomem
        bra     @ok
:       jsr     ui_beep
        sec
        rts
@ok:    jsr     setmod
        jsr     ed_end
        lda     crow                    ; its row (texts flow into neighbours)
        jsr     mark_dirty
        clc
        rts

; ---------------------------------------------------------------- the mouse
; drag: 0 none, 1 cells, 2 whole columns, 3 whole rows, 4 a column's width
onbutton:
        lda     ui_ev+6
        and     #1
        bne     :+
        stz     drag                    ; a release
        jmp     loop
:       lda     ui_ev+4                 ; above the grid: nothing (the field is a control)
        cmp     #EH
        jcc     loop
        lda     ui_ev+2
        cmp     gx1
        jcs     loop
        lda     ui_ev+4
        cmp     gy1
        jcs     loop
        lda     ui_ev+4
        cmp     #CY
        jcs     @cells
        lda     ui_ev+2                 ; the column headers
        cmp     #RW
        bcs     :+
        jmp     m_all                   ; the corner: everything
:       jsr     colpos                  ; on a column's right line (+- 3): its width
        ldx     #0
@b:     txa
        lsr     a
        cmp     vcols
        bcs     @hcol
        lda     colx,x
        clc
        adc     coldw,x
        sec
        sbc     ui_ev+2
        clc
        adc     #3
        cmp     #6
        bcc     @wid
        inx
        inx
        bra     @b
@wid:   lda     colc,x
        sta     dg_col
        lda     colx,x
        sta     dg_x0
        lda     #4
        sta     drag
        jmp     loop
@hcol:  jsr     edit_off                ; a column: all of it (Shift: from the anchor)
        jcs     loop
        jsr     hit_col
        sta     ccol
        jsr     shift_now
        bne     :+
        lda     ccol
        sta     acol
:       stz     crow
        lda     #NROW - 1
        sta     arow
        lda     #2
        sta     drag
        lda     #1
        sta     nosc
        jmp     post
@cells: lda     ui_ev+2
        cmp     #RW
        bcs     @cell
        jsr     edit_off                ; the row numbers: whole rows
        jcs     loop
        jsr     hit_row
        sta     crow
        jsr     shift_now
        bne     :+
        lda     crow
        sta     arow
:       stz     ccol
        lda     #NCOL - 1
        sta     acol
        lda     #3
        sta     drag
        lda     #2
        sta     nosc
        jmp     post
@cell:  jsr     colpos
        jsr     hit_col
        sta     z:t2
        jsr     hit_row
        sta     z:t3
        lda     editing                 ; a formula being typed: the cell's name goes in
        beq     @sel
        jsr     ptmode
        bcc     @sel
        lda     z:t3
        sta     z:t1
        lda     z:t2
        xba
        asl     a
        asl     a
        ora     z:t1
        jsr     ci_name
        ldx     #.loword(nmbuf)
        jsr     fld_ins
        jmp     loop
@sel:   jsr     edit_off
        jcs     loop
        lda     z:t2                    ; a double click on the same cell: edit it
        cmp     ccol
        bne     @one
        lda     z:t3
        cmp     crow
        bne     @one
        sys     SYS_UPTIME
        sec
        sbc     lastclick
        cmp     #500
        bcs     @one
        stz     lastclick
        jmp     ed_f2
@one:   sys     SYS_UPTIME
        sta     lastclick
        lda     z:t2
        sta     ccol
        lda     z:t3
        sta     crow
        jsr     shift_now
        bne     :+
        lda     ccol
        sta     acol
        lda     crow
        sta     arow
:       lda     #1
        sta     drag
        jmp     post

; ctrl-A, the corner: everything
m_all:  stz     ccol
        stz     crow
        lda     #NCOL - 1
        sta     acol
        lda     #NROW - 1
        sta     arow
        lda     #3
        sta     nosc
        jmp     post

; Shift held (the event's modifiers are only in key events: ask)
shift_now:
        lda     kmods
        and     #$22
        rts

; editing: commit first -> C set: it was not taken
edit_off:
        lda     editing
        beq     :+
        jmp     commit
:       clc
        rts

; the pointer's column (ui_ev a) -> A (one beyond the view left or right of it)
hit_col:
        lda     ui_ev+2
        bmi     @left
        cmp     #RW
        bcc     @left
        ldx     #0
:       txa
        lsr     a
        cmp     vcols
        bcs     @last
        lda     ui_ev+2
        sec
        sbc     colx,x
        cmp     coldw,x
        bcc     @hit
        inx
        inx
        bra     :-
@hit:   lda     colc,x
        rts
@left:  lda     lcol
        beq     :+
        dec     a
:       rts
@last:  lda     vcols
        dec     a
        asl     a
        tax
        lda     colc,x
        inc     a
        cmp     #NCOL
        bcc     :+
        lda     #NCOL - 1
:       rts
; the pointer's row (ui_ev b) -> A (one beyond the view above or below it)
hit_row:
        lda     ui_ev+4
        sec
        sbc     #CY
        bpl     :+
        lda     trow
        beq     @r
        dec     a
        rts
:       ldx     #0
:       cmp     #RH
        bcc     :+
        sbc     #RH
        inx
        bra     :-
:       txa
        cmp     vrows
        bcc     :+
        lda     vrows
:       clc
        adc     trow
        cmp     #NROW
        bcc     @r
        lda     #NROW - 1
@r:     rts

; motion with the button held: the selection follows, or the column's width
onmotion:
        lda     drag
        jeq     loop
        cmp     #4
        beq     @width
        jsr     colpos
        lda     drag
        cmp     #3
        beq     :+
        jsr     hit_col
        sta     ccol
:       lda     drag
        cmp     #2
        beq     :+
        jsr     hit_row
        sta     crow
:       lda     drag                    ; whole columns: no vertical scrolling, rows: no
        cmp     #2                      ; sideways scrolling
        bne     :+
        lda     #1
        sta     nosc
:       cmp     #3
        bne     :+
        lda     #2
        sta     nosc
:       jmp     post
@width: lda     ui_ev+2                 ; the width follows the pointer (live)
        sec
        sbc     dg_x0
        bmi     :+
        cmp     #MINW
        bcs     :++
:       lda     #MINW
:       cmp     #MAXW + 1
        bcc     :+
        lda     #MAXW
:       pha
        lda     dg_col
        asl     a
        tax
        pla
        cmp     colw,x
        jeq     loop
        sta     colw,x
        jsr     setmod
        jsr     hlimit
        lda     #N_GRID | N_SB
        tsb     need
        jsr     refresh
        jmp     loop

; the field's text ends with an operator, "(", "," or ":" and its cursor is at the end:
; a click puts the cell's name there -> C set
ptmode: lda     ebuf
        and     #$00FF
        cmp     #'='
        bne     @no
        lda     fld+FD_CUR
        cmp     fld+FD_LEN
        bne     @no
        tax
        lda     ebuf-1,x
        ldx     #0
        sep     #$20
        .a8
:       cmp     ptchars,x
        beq     @yes
        inx
        cpx     #PTN
        bcc     :-
        rep     #$20
        .a16
@no:    clc
        rts
@yes:   rep     #$20
        .a16
        sec
        rts
; string X appended to the field (at its end)
fld_ins:
        lda     fld+FD_LEN
        clc
        adc     #.loword(ebuf)
        tay
        jsr     ui_strcpy
        ldx     #.loword(ebuf)
        jsr     ui_strlen
        cmp     #TXTMAX
        bcc     :+
        lda     #TXTMAX
        tax
        stz     ebuf,x
:       sta     fld+FD_LEN
        sta     fld+FD_CUR
        sta     fld+FD_ANC
        ldx     #.loword(fld)
        jsr     ui_draw
        rts

; ---------------------------------------------------------------- menus
m_new:  jsr     confirm
        jcs     loop
        jsr     sheet_new
        stz     fpath
        jsr     settitle
        lda     #N_ALL
        sta     need
        jsr     hlimit
        jmp     post
m_open: jsr     confirm
        jcs     loop
        stz     dlgbuf
        lda     #0
        ldx     #.loword(dlgbuf)
        ldy     #.loword(t_open)
        jsr     ui_filedlg
        jcs     loop
        ldx     #.loword(dlgbuf)
        ldy     #.loword(fpath)
        jsr     ui_strcpy
        jsr     do_load
        jsr     settitle
        lda     #N_ALL
        sta     need
        jmp     post
m_save: jsr     do_save
        jmp     loop
m_saveas:
        jsr     do_saveas
        jmp     loop
m_export:
        jsr     basename                ; the name with .CSV
        ldy     #.loword(dlgbuf)
        jsr     ui_strcpy
        jsr     ext_cut
        ldx     #.loword(e_csv)
        jsr     dlg_app
        lda     #1
        ldx     #.loword(dlgbuf)
        ldy     #.loword(t_export)
        jsr     ui_filedlg
        jcs     loop
        jsr     dlg_ext                 ; (no extension: .CSV)
        lda     #.loword(e_csv)
        jsr     dlg_ext2
        ldx     #.loword(fpath)         ; (fpath kept: the sheet's own name)
        ldy     #.loword(fpath2)
        jsr     ui_strcpy
        ldx     #.loword(dlgbuf)
        ldy     #.loword(fpath)
        jsr     ui_strcpy
        jsr     busy
        jsr     csv_save
        php
        pha
        jsr     unbusy
        pla
        plp
        bcc     :+
        ldx     #.loword(m_cantsave)
        jsr     errbox
:       ldx     #.loword(fpath2)
        ldy     #.loword(fpath)
        jsr     ui_strcpy
        jmp     loop
; (0.23) File > Print (ctrl-P): the used area as text columns (prt_save), a print job
; "/PRN:Sheet"; an alert if it failed (the Desktop tells when it is done)
m_print:
        jsr     busy
        jsr     prt_save
        php
        pha
        jsr     unbusy
        pla
        plp
        bcc     :+
        ldx     #.loword(m_cantprint)
        jsr     errbox
:       jmp     loop
m_close:
        jsr     confirm
        jcs     loop
        jmp     quit

m_cut:  jsr     selrect
        jsr     copysel
        bcs     :+
        jsr     rng_clear
        jsr     setmod
        jsr     sel_rows
:       jmp     post
m_copy: jsr     selrect
        jsr     copysel
        jmp     post
m_paste:
        jsr     selrect
        jsr     busy
        jsr     paste
        jsr     unbusy
        jsr     setmod
        lda     #N_GRID
        tsb     need
        jmp     post
m_clear:
        jsr     selrect
        jsr     rng_clear
        jsr     setmod
        jsr     sel_rows
        lda     #N_FLD
        tsb     need
        jmp     post
m_filld:
        jsr     selrect
        jsr     fill_down
        bra     :+
m_fillr:
        jsr     selrect
        jsr     fill_right
:       bcc     :+
        jsr     nomem
:       jsr     setmod
        jsr     sel_rows
        jmp     post
m_insr: jsr     selrect                 ; as many rows as selected, above them
        jsr     busy
        lda     s_r1
        sec
        sbc     s_r0
        inc     a
        sta     z:t4
:       lda     s_r0
        jsr     ed_insr
        dec     z:t4
        bne     :-
        bra     m_struct
m_insc: jsr     selrect
        jsr     busy
        lda     s_c1
        sec
        sbc     s_c0
        inc     a
        sta     z:t4
:       lda     s_c0
        jsr     ed_insc
        dec     z:t4
        bne     :-
        bra     m_struct
m_delr: jsr     selrect
        jsr     busy
        lda     s_r1
        sec
        sbc     s_r0
        inc     a
        sta     z:t4
:       lda     s_r0
        jsr     ed_delr
        dec     z:t4
        bne     :-
        bra     m_struct
m_delc: jsr     selrect
        jsr     busy
        lda     s_c1
        sec
        sbc     s_c0
        inc     a
        sta     z:t4
:       lda     s_c0
        jsr     ed_delc
        dec     z:t4
        bne     :-
m_struct:
        jsr     unbusy
        jsr     setmod
        jsr     hlimit
        lda     #N_GRID | N_SB | N_FLD
        tsb     need
        jmp     post

; Format: the selected columns
o_gen:  lda     #0
        bra     o_dec
o_d0:   lda     #1
        bra     o_dec
o_d2:   lda     #3
        bra     o_dec
o_d4:   lda     #5
o_dec:  sta     z:t3                    ; the decimals part replaced
        lda     #$FFF0
        sta     z:t4
        bra     o_set
o_thou: lda     #FM_THOU                ; toggled (by the cursor's column)
        bra     o_tog
o_pct:  lda     #FM_PCT
o_tog:  sta     z:t3
        eor     #$FFFF
        sta     z:t4
        ldx     ccol
        lda     colfmt,x
        and     z:t3
        eor     z:t3
        sta     z:t3
o_set:  jsr     selrect
        ldx     s_c0
:       lda     colfmt,x
        and     z:t4
        ora     z:t3
        sep     #$20
        .a8
        sta     colfmt,x
        rep     #$20
        .a16
        inx
        cpx     s_c1
        bcc     :-
        beq     :-
        jsr     setmod
        lda     #N_GRID
        tsb     need
        jmp     post
o_width:
        jsr     askwidth
        jmp     post

; ---------------------------------------------------------------- the clipboard
; the selection to the program's clipboard and, as tab-separated text, to the system's
copysel:
        jsr     cp_copy
        bcc     :+
        ldx     #.loword(m_toobig)
        lda     #0
        jsr     errbox
        sec
        rts
:       jsr     wr_init                 ; the text into SB: values as shown
        lda     s_r0
        sta     sv_r
@row:   lda     s_c0
        sta     sv_c
@cell:  lda     sv_c
        cmp     s_c0
        beq     :+
        lda     #9
        jsr     tsv_byte
:       lda     sv_c
        tax
        lda     colfmt,x
        and     #$00FF
        tax
        lda     sv_c
        xba
        asl     a
        asl     a
        ora     sv_r
        jsr     cell_disp
        ldx     #0
:       lda     fbuf,x
        and     #$00FF
        beq     :+
        phx
        jsr     tsv_byte
        plx
        inx
        bra     :-
:       inc     sv_c
        lda     sv_c
        cmp     s_c1
        bcc     @cell
        beq     @cell
        lda     #10
        jsr     tsv_byte
        inc     sv_r
        lda     sv_r
        cmp     s_r1
        bcc     @row
        beq     @row
        stz     clipblk                 ; to the system clipboard ({u24 data, u16 length});
        lda     sbank                   ; remember what it was
        sta     clipblk+2
        lda     wr_n
        sta     clipblk+3
        sta     tsv_len
        sta     tsv_mlen
        ptr     clipblk
        sys     SYS_CLPUT
        jsr     tsv_sum
        sta     tsv_ck
        clc
        rts
; a byte of the text (stops at 60000)
tsv_byte:
        ldy     wr_n
        cpy     #WFLUSH
        bcs     :+
        sep     #$20
        .a8
        sta     [sb],y
        rep     #$20
        .a16
        iny
        sty     wr_n
:       rts
; a checksum of SB's first tsv_len bytes -> A
tsv_sum:
        lda     #0
        ldy     #0
:       cpy     tsv_len
        bcs     :+
        sta     z:t0
        lda     [sb],y
        and     #$00FF
        clc
        adc     z:t0
        asl     a
        adc     #0
        iny
        bra     :-
:       rts

; paste at the selection: the program's own cells when the system clipboard still holds
; what we put there, else its text (tab-separated rows) from the cursor
paste:  stz     clipblk                 ; the system clipboard into SB
        lda     sbank
        sta     clipblk+2
        lda     #WFLUSH
        sta     clipblk+3
        ptr     clipblk
        sys     SYS_CLGET
        bcs     @own
        cmp     #WFLUSH
        bcc     :+
        lda     #WFLUSH
:       sta     tsv_len
        beq     @own
        cmp     tsv_mlen
        bne     @text
        jsr     tsv_sum
        cmp     tsv_ck
        bne     @text
        lda     cp_have
        beq     @text
@own:   jsr     cp_paste
        bcc     :+
        jsr     nomem
:       rts
@text:  lda     s_c0
        sta     dl_c0
        lda     s_r0
        sta     dl_r0
        lda     #9
        sta     dl_sep
        lda     #1
        sta     dl_clr
        stz     rd_pos
        lda     #.loword(mem_byte)
        sta     dl_get
        jsr     dl_read
        bcc     :+
        jsr     nomem
:       rts
; the next byte of SB (tsv_len of them) -> A, C set at the end
mem_byte:
        ldy     rd_pos
        cpy     tsv_len
        bcs     :+
        lda     [sb],y
        and     #$00FF
        iny
        sty     rd_pos
        clc
:       rts

; the selection's rows marked for redrawing
sel_rows:
        lda     s_r0
        ldx     s_r1
        jmp     mark_rows

; ---------------------------------------------------------------- files
; load fpath (by its extension: .CSV imported, anything else as .SHT)
do_load:
        jsr     busy
        jsr     sheet_new
        jsr     is_csv
        bcc     :+
        jsr     csv_load
        bra     @chk
:       jsr     sht_load
@chk:   bcc     @ok
        cmp     #$44                    ; not there: a new sheet of that name
        beq     @ok
        ldx     #.loword(m_cantopen)
        jsr     errbox
@ok:    stz     emod
        lda     #1
        sta     dirty
        jsr     hlimit
        jsr     unbusy
        rts

; File > Save: to its path (a .CSV or a new sheet: Save as) -> C set: not saved
do_save:
        lda     fpath
        and     #$00FF
        beq     do_saveas
        jsr     is_csv
        bcs     do_saveas
save_now:
        jsr     busy
        jsr     sht_save
        php
        pha
        jsr     unbusy
        pla
        plp
        bcc     :+
        ldx     #.loword(m_cantsave)
        jsr     errbox
        sec
        rts
:       stz     emod
        jsr     settitle
        clc
        rts
do_saveas:
        jsr     basename
        ldy     #.loword(dlgbuf)
        jsr     ui_strcpy
        jsr     is_csv
        bcc     :+
        jsr     ext_cut                 ; (a CSV: suggest the name as .SHT)
        ldx     #.loword(e_sht)
        jsr     dlg_app
:       lda     #1
        ldx     #.loword(dlgbuf)
        ldy     #.loword(t_saveas)
        jsr     ui_filedlg
        bcc     :+
        rts
:       jsr     dlg_ext
        lda     #.loword(e_sht)
        jsr     dlg_ext2
        ldx     #.loword(dlgbuf)
        ldy     #.loword(fpath)
        jsr     ui_strcpy
        jsr     save_now
        php
        jsr     settitle
        plp
        rts

; dlgbuf's name without an extension? -> C set (Y = its end)
dlg_ext:
        ldy     #0
        ldx     #0
:       lda     dlgbuf,y
        and     #$00FF
        beq     :+++
        cmp     #'/'
        bne     :+
        ldx     #0
        bra     :++
:       cmp     #'.'
        bne     :+
        ldx     #1
:       iny
        bra     :---
:       cpx     #0
        bne     :+
        sec
        rts
:       clc
        rts
; (after dlg_ext) C set: the extension A appended
dlg_ext2:
        bcc     :+
        tax
        jmp     dlg_app
:       rts
; string X appended to dlgbuf
dlg_app:
        phx
        ldx     #.loword(dlgbuf)
        jsr     ui_strlen
        clc
        adc     #.loword(dlgbuf)
        tay
        plx
        jmp     ui_strcpy
; dlgbuf's extension (from its last '.') removed
ext_cut:
        ldx     #.loword(dlgbuf)
        jsr     ui_strlen
        tax
:       dex
        bmi     :+
        lda     dlgbuf,x
        and     #$00FF
        cmp     #'.'
        bne     :-
        stz     dlgbuf,x
:       rts
; fpath ends in .CSV? -> C set
is_csv: ldx     #.loword(fpath)
        jsr     ui_strlen
        cmp     #4
        bcc     @no
        tax
        lda     fpath-4,x
        cmp     #'.' | ('C' << 8)
        beq     :+
        cmp     #'.' | ('c' << 8)
        bne     @no
:       lda     fpath-2,x
        and     #$DFDF
        cmp     #'S' | ('V' << 8)
        bne     @no
        sec
        rts
@no:    clc
        rts

; unsaved changes: ask (Save / Discard / Cancel) -> C set: stop
confirm:
        lda     emod
        bne     :+
        clc
        rts
:       ldx     #.loword(m_save1)
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        jsr     basename
        jsr     append
        ldx     #.loword(m_save2)
        jsr     append
        ldx     #.loword(al_save)
        jsr     ui_alert
        cmp     #1
        beq     @go
        cmp     #0
        bne     @stop
        jmp     do_save
@go:    clc
        rts
@stop:  sec
        rts

nomem:  ldx     #.loword(m_nomem)
        lda     #0
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        ldx     #.loword(al_err)
        jmp     ui_alert

; an alert: message X then the file's name, error code A (0: none)
errbox: sta     z:t5
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        jsr     basename
        jsr     append
        lda     z:t5
        beq     @show
        ldx     #.loword(m_code)
        jsr     append
        lda     z:t5
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     @hex
        lda     z:t5
        jsr     @hex
        ldx     #.loword(m_rpar)
        jsr     append
@show:  ldx     #.loword(al_err)
        jmp     ui_alert
@hex:   and     #$000F
        cmp     #10
        bcc     :+
        adc     #6
:       adc     #'0'
        sta     onech
        ldx     #.loword(onech)
; append string X to msgbuf
append: phx
        ldx     #.loword(msgbuf)
        jsr     ui_strlen
        clc
        adc     #.loword(msgbuf)
        tay
        plx
        jmp     ui_strcpy

; X = the file's name (after the last '/'), or "(new)"
basename:
        lda     fpath
        and     #$00FF
        bne     :+
        ldx     #.loword(t_newname)
        rts
:       ldx     #.loword(fpath)
        ldy     #.loword(fpath)
:       lda     a:0,x
        and     #$00FF
        beq     :++
        cmp     #'/'
        bne     :+
        txy
        iny
:       inx
        bra     :--
:       tyx
        rts

; the title: "Sheet: name" (and " *" when changed)
settitle:
        ldx     #.loword(t_sheet)
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        jsr     basename
        ldy     #.loword(msgbuf + 7)
        jsr     ui_strcpy
        cmp     #22
        bcc     :+
        lda     #'.' | ('.' << 8)
        sta     msgbuf + 7 + 19
        stz     msgbuf + 7 + 21
:       lda     emod
        beq     :+
        ldx     #.loword(t_star)
        jsr     append
:       lda     win
        ptr     msgbuf
        sys     SYS_WTITLE
        rts

setmod: lda     emod
        bne     :+
        inc     emod
        jsr     settitle
:       rts

; a long operation: the drag pointer while it runs (shown at once)
busy:   lda     #1
        sys     SYS_WPTR
        rts
unbusy: lda     #0
        sys     SYS_WPTR
        rts

; ---------------------------------------------------------------- the width dialog
DW      = 232
DH      = 84
askwidth:
        lda     ccol                    ; the prompt: "Width of column B (16-400):"
        clc
        adc     #'A'
        sep     #$20
        .a8
        sta     l_wcol
        rep     #$20
        .a16
        lda     ccol                    ; the field: the width now
        asl     a
        tax
        lda     colw,x
        ldx     #0
        jsr     put_decx
        ldx     #.loword(nmbuf)
        ldy     #.loword(wbuf)
        jsr     ui_strcpy
        lda     #DW                     ; centred over the window
        sta     dwo+4
        lda     #DH
        sta     dwo+6
        lda     win
        ptr     winf
        sys     SYS_WINFO
        lda     winf+4
        sec
        sbc     #DW + 2
        cmp     #$8000
        ror     a
        clc
        adc     winf
        dec     a
        sta     dwo
        lda     winf+6
        sec
        sbc     #DH + 17
        cmp     #$8000
        ror     a
        clc
        adc     winf+2
        sec
        sbc     #16
        sta     dwo+2
        lda     #.loword(t_width)
        sta     dwo+8
        sep     #$20
        .a8
        lda     #^t_width
        sta     dwo+10
        lda     #WF_MODAL
        sta     dwo+11
        rep     #$20
        .a16
        ptr     dwo
        sys     SYS_WOPEN
        bcc     :+
        jmp     ui_beep
:       sta     dwin
        sep     #$20
        .a8
        sta     d_lab+CT_WIN
        sta     d_fld+CT_WIN
        sta     d_ok+CT_WIN
        sta     d_cn+CT_WIN
        rep     #$20
        .a16
        lda     #UF_FOCUS
        sta     d_fld+CT_FLAGS
        ldx     #.loword(dlist)
        jsr     ui_drawall
        ldx     #.loword(d_fld)
        ldy     #.loword(wbuf)
        jsr     ui_fdset
@l:     lda     #0
        jsr     ui_getev
        bcs     @l
        lda     ui_ev+1
        and     #$00FF
        cmp     dwin
        beq     @mine
        lda     ui_ev                   ; our window's keys come here too
        and     #$00FF
        cmp     #WE_KEY
        beq     :+
        jsr     ui_defer_put
        bra     @l
:       sep     #$20
        .a8
        lda     dwin
        sta     ui_ev+1
        rep     #$20
        .a16
@mine:  lda     ui_ev
        and     #$00FF
        cmp     #WE_CLOSE
        beq     @no
        ldx     #.loword(dlist)
        jsr     ui_event
        cmp     #UA_CLICK
        bne     @l
        cpx     #.loword(d_ok)
        bne     @no
        ldx     #0                      ; a number in range?
        stz     z:t0
:       lda     wbuf,x
        and     #$00FF
        beq     :+
        jsr     isdigit
        bcc     @bad
        and     #$000F
        pha
        lda     z:t0
        cmp     #1000
        bcs     @bad2
        asl     a
        sta     z:t1
        asl     a
        asl     a
        adc     z:t1
        sta     z:t0
        pla
        clc
        adc     z:t0
        sta     z:t0
        inx
        bra     :-
:       lda     z:t0
        cmp     #MINW
        bcc     @bad
        cmp     #MAXW + 1
        bcs     @bad
        jsr     selrect                 ; every selected column
        ldx     s_c0
:       phx
        txa
        asl     a
        tax
        lda     z:t0
        sta     colw,x
        plx
        inx
        cpx     s_c1
        bcc     :-
        beq     :-
        jsr     setmod
        jsr     hlimit
        lda     #N_GRID | N_SB
        tsb     need
@no:    lda     dwin
        sys     SYS_WCLOSE
        rts
@bad2:  pla
@bad:   jsr     ui_beep
        jmp     @l

        .include "sht_num.s"
        .include "sht_cell.s"
        .include "sht_fx.s"
        .include "sht_calc.s"
        .include "sht_file.s"
        .include "sht_edit.s"
        .include "sht_test.s"

        .segment "RODATA"
menus:  .byte   "File", 0, "New", 0, "Open...", 0, "Save", 0, "Save as...", 0
        .byte   "Export CSV...", 0, "-", 0, "Print", 0, "-", 0, "Close", 0, 0
        .byte   "Edit", 0, "Cut", 0, "Copy", 0, "Paste", 0, "Clear", 0, "-", 0
        .byte   "Fill down", 0, "Fill right", 0, "-", 0, "Insert row", 0, "Insert column", 0
        .byte   "Delete row", 0, "Delete column", 0, 0
        .byte   "Format", 0, "General", 0, "0 decimals", 0, "2 decimals", 0, "4 decimals", 0
        .byte   "-", 0, "Thousands", 0, "Percent", 0, "-", 0, "Column width...", 0, 0, 0
        .res    256 - (* - menus)
mtab:   .addr   m_file, m_edit, m_fmt
ftab:   .addr   m_new, m_open, m_save, m_saveas, m_export, loop, m_print, loop, m_close
etab:   .addr   m_cut, m_copy, m_paste, m_clear, loop, m_filld, m_fillr, loop, m_insr, m_insc
        .addr   m_delr, m_delc
otab:   .addr   o_gen, o_d0, o_d2, o_d4, loop, o_thou, o_pct, loop, o_width
; ctrl + key: {ASCII, routine}
ctltab: .word   14, m_new, 15, m_open, 19, m_save, 24, m_cut, 3, m_copy, 22, m_paste
        .word   4, m_filld, 18, m_fillr, 1, m_all, 16, m_print, 0
ctls:   .addr   vsb, hsb, fld, 0
ptchars: .byte  "=+-*/^(,:<>"
PTN     = * - ptchars
t_sheet: .byte  "Sheet: ", 0
t_prn:  .byte   "/PRN:Sheet", 0
m_cantprint: .byte "Cannot print ", 0
t_star: .byte   " *", 0
t_newname: .byte "(new)", 0
t_open: .byte   "Open", 0
t_saveas: .byte "Save as", 0
t_export: .byte "Export CSV", 0
t_title: .byte  "Sheet", 0
t_width: .byte  "Column width", 0
e_csv:  .byte   ".CSV", 0
e_sht:  .byte   ".SHT", 0
m_save1: .byte  "Save the changes to ", 0
m_save2: .byte  "?", 10, "Changes that are not saved will be lost.", 0
m_cantopen: .byte "Cannot open ", 0
m_cantsave: .byte "Cannot save ", 0
m_toobig: .byte "Too much to copy at once.", 0
m_nomem: .byte  "Not enough memory: the last", 10, "change was not made.", 0
m_code: .byte   10, "(error $", 0
m_rpar: .byte   ")", 0
b_save: .byte   "Save", 0
b_discard: .byte "Discard", 0
b_cancel: .byte "Cancel", 0
b_ok:   .byte   "OK", 0
al_save: .word  2, t_title, msgbuf, b_save, b_discard, b_cancel
al_err: .word   3, t_title, msgbuf, b_ok, 0, 0

        .segment "DATA"
wopen:  .word   15, 22, 608, 304
        .faraddr t_title
        .byte   WF_RESIZE
fld:    .byte   UT_FIELD, 0
        .word   0, 4, 100, UI_FLDH, 0
        .addr   ebuf
        .word   TXTMAX + 1, 0, 0, 0, 0
vsb:    .byte   UT_VSCROLL, 0
        .word   0, 0, UI_SBW, 0, 0
        .word   0, 0, 1, 1, 0, 0
hsb:    .byte   UT_HSCROLL, 0
        .word   0, 0, 0, UI_SBW, 0
        .word   0, 0, 1, 1, 0, 0
dwo:    .word   0, 0, DW, DH, 0, 0
d_lab:  .byte   UT_LABEL, 0
        .word   8, 8, DW - 16, UI_LINE, 0
        .addr   l_width
d_fld:  .byte   UT_FIELD, 0
        .word   8, 24, 64, UI_FLDH, UF_FOCUS
        .addr   wbuf
        .word   6, 0, 0, 0, 0
d_ok:   .byte   UT_BUTTON, 0
        .word   DW - 8 - 64, DH - 8 - UI_BTNH, 64, UI_BTNH, UF_DEFAULT
        .addr   b_ok
d_cn:   .byte   UT_BUTTON, 0
        .word   DW - 16 - 128, DH - 8 - UI_BTNH, 64, UI_BTNH, UF_CANCEL
        .addr   b_cancel
dlist:  .addr   d_lab, d_fld, d_ok, d_cn, 0
l_width: .byte  "Width of column "
l_wcol: .byte   "A in pixels (16-400):", 0

        .segment "BSS"
argl:   .res    2
argx:   .res    2
tmode:  .res    2
wsown:  .res    2
win:    .res    2
dwin:   .res    2
sbank:  .res    2
cw:     .res    2
chh:    .res    2
gx1:    .res    2
gy1:    .res    2
gpart:  .res    2
vrows:  .res    2
vcols:  .res    2
colend: .res    2
hmax:   .res    2
lcol:   .res    2
trow:   .res    2
ccol:   .res    2
crow:   .res    2
acol:   .res    2
arow:   .res    2
o_cc:   .res    2
o_cr:   .res    2
o_ac:   .res    2
o_ar:   .res    2
o_lcol: .res    2
o_trow: .res    2
need:   .res    2
editing: .res   2
emod:   .res    2
kmods:  .res    2
key:    .res    2
shift:  .res    2
drag:   .res    2
dg_col: .res    2
dg_x0:  .res    2
lastclick: .res 2
onech:  .res    2
wid_hash: .res  2
nosc:   .res    2
tsv_mlen: .res  2
dr_h:   .res    2
dr_part: .res   2
dr_y:   .res    2
dr_row: .res    2
dr_bg:  .res    2
dr_k:   .res    2
dr_c:   .res    2
dr_ci:  .res    2
dr_len: .res    2
dr_e:   .res    2
dr_j:   .res    2
dr_sw:  .res    2
dr_tw:  .res    2
dr_x:   .res    2
dr_room: .res   2
dr_cut: .res    2
dr_full: .res   2
tsv_len: .res   2
tsv_ck: .res    2
clipblk: .res   6
winf:   .res    8
colw:   .res    NCOL * 2
colfmt: .res    NCOL + 2
colx:   .res    MAXVC * 2
colc:   .res    MAXVC * 2
coldw:  .res    MAXVC * 2
rdirty: .res    MAXVR + 2
hdrs:   .res    4
nmbuf2: .res    16
wbuf:   .res    8
fpath:  .res    130
fpath2: .res    130
abuf:   .res    130
dlgbuf: .res    130
msgbuf: .res    200
ebuf:   .res    TXTMAX + 8

        .segment "ZEROPAGE"
t0:     .res    2
t1:     .res    2
t2:     .res    2
t3:     .res    2
t4:     .res    2
t5:     .res    2
