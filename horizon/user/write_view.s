; write_view.s - Write: the view (part of write.s).
;
; Rows: a row is (line, start column, end column); its height comes from its line's
; block (rh0: a line's first row, with the space above a heading; rh1: the others). The
; view starts at row (top, toff); layout lists the rows that are in view (ly_*), from
; TOPM down to the status line (the last one may be cut).
;
; Drawing (refresh): the rows wanted against the rows drawn (dr_*). A row drawn before
; at another place, the same (line, start, end, height) and not marked, moves there with
; one WD_COPY (the longest run of them that moves by the same amount); the rows not on
; the screen as wanted are drawn. A row is drawn whole into the row buffer (bank RB,
; stride RBS): its paper, a code span's tint, the selection, the block's mark (bullet,
; number, quote bar, rule), the glyphs (wfont.inc: bold, italic by shearing each glyph
; row, headings in their larger faces), the cursor; then one WD_SBLIT puts it in the
; window. The compositor waits for all of it (ws_hold).
;
; Only what changed is drawn: each row drawn leaves a record (a slot of bank VB: its
; characters and their styles, the selection, the cursor, its left and right ends). A row
; to draw at the place of a row drawn before (same y, same height, same block) is compared
; with that one's record: the columns from the first that differs to the last (to the
; row's end when the lengths differ) are drawn (with 4 pixels of margin either side, for
; italic and the cursor), the rest stays on the screen. Typing in a paragraph so draws the
; end of one row, and nothing of the rows after it unless they wrap otherwise; a cursor
; move draws the few pixels around both places. (The glyphs are plotted into the row
; buffer by plotg, one byte of 8 pixels at a time; see plotg for a 1-bpp expanding blit.)

        .segment "CODE"

; ---------------------------------------------------------------- rows and the view
; row pr_l:pr_s -> A = its height (lrows: its line laid out)
prh:    lda     pr_l
        jsr     lrows
        lda     pr_s
        ; fall through
; the height of the row starting at column A of the line laid out last -> A
rowh:   ldx     lcx
        ldy     lc_blk,x
        tax
        tya
        asl     a
        tay
        txa
        bne     :+
        lda     rh0,y
        rts
:       lda     rh1,y
        rts

; the row before / after row pr_l:pr_s -> pr_l:pr_s; C set: none (it stays)
prevrow:
        lda     pr_s
        beq     @pl
        lda     pr_l
        jsr     lrows
        lda     pr_s
        dec     a
        jsr     rowof
        lda     rw_s
        sta     pr_s
        clc
        rts
@pl:    lda     pr_l
        beq     @none
        dec     a
        sta     pr_l
        jsr     lrows
        lda     llen
        jsr     rowof
        lda     rw_s
        sta     pr_s
        clc
        rts
@none:  sec
        rts
nextrow:
        lda     pr_l
        jsr     lrows
        lda     pr_s
        jsr     rowend
        cmp     llen
        bcs     @nl
        sta     pr_s
        clc
        rts
@nl:    lda     pr_l
        inc     a
        cmp     nl
        bcs     @none
        sta     pr_l
        stz     pr_s
        clc
        rts
@none:  sec
        rts

; the rows in view from top:toff -> ly_l, ly_s, ly_e, ly_y, ly_h (nly2 = rows * 2),
; ly_bot (below the last), vis (rows wholly in view, at least 1), pr_l:pr_s (the row
; after them). Kept while the text, the view, the cursor's line and the top are the same.
layout: lda     ed_cnt
        cmp     ly_ec
        bne     @do
        lda     top
        cmp     ly_top
        bne     @do
        lda     toff
        cmp     ly_toff
        bne     @do
        lda     rv_l
        cmp     ly_rv
        bne     @do
        lda     ly_pl
        sta     pr_l
        lda     ly_ps
        sta     pr_s
        rts
@do:    lda     top
        sta     pr_l
        lda     toff
        sta     pr_s
        stz     lyi
        stz     vis
        lda     #TOPM
        sta     ly_bot
@r:     lda     lyi
        cmp     #MAXROWS * 2
        bcs     @out
        lda     ly_bot
        cmp     th
        bcs     @out
        lda     pr_l
        cmp     nl
        bcs     @out
        ldx     lyi
        sta     ly_l,x
        lda     pr_s
        sta     ly_s,x
        lda     ly_bot
        sta     ly_y,x
        jsr     prh
        ldx     lyi
        sta     ly_h,x
        clc
        adc     ly_bot
        sta     ly_bot
        cmp     th
        beq     :+
        bcs     :++
:       inc     vis
:       lda     pr_s
        jsr     rowend
        ldx     lyi
        sta     ly_e,x
        inx
        inx
        stx     lyi
        cmp     llen
        bcc     :+
        inc     pr_l
        stz     pr_s
        bra     @r
:       sta     pr_s
        bra     @r
@out:   lda     lyi
        sta     nly2
        lda     vis
        bne     :+
        inc     vis
:       lda     ed_cnt                  ; (kept)
        sta     ly_ec
        lda     top
        sta     ly_top
        lda     toff
        sta     ly_toff
        lda     rv_l
        sta     ly_rv
        lda     pr_l
        sta     ly_pl
        lda     pr_s
        sta     ly_ps
        rts

; top:toff made a row start again (after the width or the view changed)
normtop:
        lda     top
        cmp     nl
        bcc     :+
        lda     nl
        dec     a
        sta     top
:       lda     top
        jsr     lrows
        lda     toff
        cmp     llen
        bcc     :+
        lda     llen
:       jsr     rowof
        lda     rw_s
        sta     toff
        rts

; keep the cursor's row wholly in view (top, toff)
ensure: jsr     currow                  ; before the view?
        lda     cl
        cmp     top
        jcc     @settop
        bne     @fwd
        lda     rw_s
        cmp     toff
        jcc     @settop
@fwd:   lda     rw_s                    ; among the rows laid out, wholly in view?
        sta     en_s
        jsr     layout
        ldx     #0
:       cpx     nly2
        bcs     @slow
        lda     ly_l,x
        cmp     cl
        bne     :+
        lda     ly_s,x
        cmp     en_s
        bne     :+
        lda     ly_y,x
        clc
        adc     ly_h,x
        cmp     th
        jeq     @vis
        jcc     @vis
        bra     @slow
:       inx
        inx
        bra     :--
@slow:  jsr     currow
        lda     top                     ; the rows from the top down to it
        sta     pr_l
        lda     toff
        sta     pr_s
        lda     #TOPM
        sta     en_y
        lda     #MAXROWS
        sta     en_n
@f:     lda     pr_l
        cmp     cl
        bne     :+
        lda     pr_s
        cmp     rw_s
        beq     @at
:       jsr     prh
        clc
        adc     en_y
        sta     en_y
        cmp     th
        bcs     @below
        dec     en_n
        beq     @below
        jsr     nextrow
        bcc     @f
        bra     @vis
@at:    jsr     prh                     ; its bottom in view?
        clc
        adc     en_y
        cmp     th
        beq     @vis
        bcc     @vis
@below: jsr     currow                  ; below: it becomes the last row in view
        lda     cl
        sta     pr_l
        lda     rw_s
        sta     pr_s
        jsr     prh
        eor     #$FFFF
        sec
        adc     th
        sec
        sbc     #TOPM
        sta     en_y                    ; the room above it
:       lda     pr_l
        sta     en_l
        lda     pr_s
        sta     en_s
        jsr     prevrow
        bcs     @set
        jsr     prh
        cmp     en_y
        beq     :+
        bcs     @set
:       eor     #$FFFF
        sec
        adc     en_y
        sta     en_y
        bra     :--
@set:   lda     en_l
        sta     top
        lda     en_s
        sta     toff
        bra     @vis
@settop:
        lda     cl
        sta     top
        lda     rw_s
        sta     toff
@vis:   ; fall through
; no room left empty at the end while the text could fill it
endclamp:
        jsr     layout
        lda     pr_l                    ; (layout stopped at the text's end?)
        cmp     nl
        bcc     @out
        lda     th
        sec
        sbc     ly_bot
        beq     @out
        bmi     @out
        sta     en_y
        lda     top
        sta     pr_l
        lda     toff
        sta     pr_s
:       jsr     prevrow
        bcs     @out
        jsr     prh
        cmp     en_y
        beq     :+
        bcs     @out
:       eor     #$FFFF
        sec
        adc     en_y
        sta     en_y
        lda     pr_l
        sta     top
        lda     pr_s
        sta     toff
        bra     :--
@out:   rts

; the line of the top row when the text's last row is the last one in view (the scroll
; bar's maximum; kept until the text or the view changes)
maxtop: lda     mt_ok
        bne     @c
        lda     nl
        dec     a
        sta     pr_l
        jsr     lrows
        lda     llen
        jsr     rowof
        lda     rw_s
        sta     pr_s
        jsr     prh
        eor     #$FFFF
        sec
        adc     th
        sec
        sbc     #TOPM
        sta     en_y
        bmi     @d
        lda     #MAXROWS
        sta     en_n
:       jsr     prevrow
        bcs     @d
        jsr     prh
        cmp     en_y
        beq     :+
        bcs     @d1
:       eor     #$FFFF
        sec
        adc     en_y
        sta     en_y
        dec     en_n
        bne     :--
        bra     @d
@d1:    jsr     nextrow
@d:     lda     pr_l
        sta     mt_line
        lda     #1
        sta     mt_ok
@c:     lda     mt_line
        rts

; the scroll bar (lines): only its thumb when only the position changed
sbupdate:
        lda     top
        sta     es_sb+SB_POS
        jsr     maxtop
        sta     es_sb+SB_MAX
        lda     nly2                    ; the page: the lines in view
        beq     :+
        dec     a
        dec     a
        tax
        lda     ly_l,x
        sec
        sbc     top
:       inc     a
        sta     es_sb+SB_PAGE
        lda     #1
        sta     es_sb+SB_STEP
        lda     es_sb+SB_POS
        cmp     es_sb+SB_MAX
        bcc     :+
        lda     es_sb+SB_MAX
        sta     es_sb+SB_POS
:       lda     es_sb+SB_MAX
        cmp     sbl_max
        bne     @all
        lda     es_sb+SB_PAGE
        cmp     sbl_page
        bne     @all
        lda     es_sb+SB_POS
        cmp     sbl_pos
        beq     @out
        ldx     sbl_pos
        stx     es_sb+SB_POS
        sta     sbl_pos
        ldx     #.loword(es_sb)
        jmp     ui_sbpos
@all:   lda     es_sb+SB_POS
        sta     sbl_pos
        lda     es_sb+SB_MAX
        sta     sbl_max
        lda     es_sb+SB_PAGE
        sta     sbl_page
        ldx     #.loword(es_sb)
        jmp     ui_draw
@out:   rts

; ---------------------------------------------------------------- drawing
redraw_all:
        lda     #$FFFF                  ; (the scroll bar and the status line for sure)
        sta     sbl_page
        stz     st_ok
        stz     dr_ok
        ; fall through
; draw what changed (see the top of this file)
refresh:
        stz     pend
        lda     nodraw                  ; (the self test)
        beq     :+
        jmp     markclr
:       lda     #1
        sys     SYS_WSHOLD
        jsr     layout
        jsr     selord
        lda     #0
        rol     a
        sta     selon
        lda     win
        sta     z:ui_win
        lda     dr_ok
        bne     @diff
        stz     z:t4                    ; the top margin
        lda     #TOPM
        sta     z:t5
        jsr     bgrect
        lda     #NONE
        ldx     #0
:       sta     dr_l,x
        inx
        inx
        cpx     #MAXROWS * 2
        bcc     :-
        stz     dr_n2
@diff:  jsr     slbusy                  ; the records of the rows drawn are kept
        jsr     rowmatch                ; the rows that stay, or move
        jsr     movebest
        ldx     #0                      ; the others drawn
@d:     cpx     nly2
        bcs     @below
        lda     rm_j,x
        cmp     #NONE
        beq     :+
        lda     rm_dy,x
        bne     :+
        lda     rm_j,x                  ; (it stays: its record too)
        tay
        lda     dr_slot,y
        sta     ly_slot,x
        bra     @n
:       stx     rf_i
        jsr     drawrow
        ldx     rf_i
@n:     inx
        inx
        bra     @d
@below: lda     ly_bot                  ; below the last row
        cmp     th
        bcs     :+
        sta     z:t4
        eor     #$FFFF
        sec
        adc     th
        sta     z:t5
        jsr     bgrect
:       ldx     #0                      ; what is drawn now
:       cpx     nly2
        bcs     :+
        lda     ly_l,x
        sta     dr_l,x
        lda     ly_s,x
        sta     dr_s,x
        lda     ly_e,x
        sta     dr_e,x
        lda     ly_y,x
        sta     dr_y,x
        lda     ly_h,x
        sta     dr_h,x
        lda     ly_slot,x
        sta     dr_slot,x
        inx
        inx
        bra     :-
:       stx     dr_n2
        lda     #NONE
:       cpx     #MAXROWS * 2
        bcs     :+
        sta     dr_l,x
        inx
        inx
        bra     :-
:       lda     #1
        sta     dr_ok
        lda     rv_l
        sta     dr_rv
        jsr     markclr
        jsr     sbupdate
        jsr     tb_update
        jsr     stupdate
        lda     #0
        sys     SYS_WSHOLD
        rts

; the slots of the rows drawn: busy, the others free (sl_busy)
slbusy: ldx     #SLN - 2
        lda     #0
:       sta     sl_busy,x
        dex
        dex
        bpl     :-
        lda     dr_ok
        beq     @out
        ldx     #0
:       cpx     dr_n2
        bcs     @out
        lda     dr_slot,x
        tay
        sep     #$20
        .a8
        lda     #1
        sta     sl_busy,y
        rep     #$20
        .a16
        inx
        inx
        bra     :-
@out:   rts

; a free slot -> A (busy now)
slalloc:
        ldy     #0
        sep     #$20
        .a8
:       lda     sl_busy,y
        beq     :+
        iny
        cpy     #SLN - 1
        bcc     :-
:       lda     #1
        sta     sl_busy,y
        rep     #$20
        .a16
        tya
        rts

; each row wanted: the row drawn that is the same (rm_j: its index * 2, NONE) and how far
; it moves (rm_dy). Rows marked, and rows not wholly in view, are drawn again.
rowmatch:
        ldx     #0
@i:     cpx     nly2
        bcc     :+
        rts
:       lda     #NONE
        sta     rm_j,x
        jsr     rowdirty
        bcs     @n
        ldy     #0
@j:     cpy     dr_n2
        bcs     @n
        lda     dr_l,y
        cmp     ly_l,x
        bne     @jn
        lda     dr_s,y
        cmp     ly_s,x
        bne     @jn
        lda     dr_e,y
        cmp     ly_e,x
        bne     @jn
        lda     dr_h,y
        cmp     ly_h,x
        bne     @jn
        lda     dr_y,y                  ; in place (even cut by the status line), or moved
        cmp     ly_y,x                  ; and wholly in view before and after
        beq     @ok
        clc
        adc     dr_h,y
        cmp     th
        beq     :+
        bcs     @jn
:       lda     ly_y,x
        clc
        adc     ly_h,x
        cmp     th
        beq     @ok
        bcs     @jn
@ok:    tya
        sta     rm_j,x
        lda     ly_y,x
        sec
        sbc     dr_y,y
        sta     rm_dy,x
        bra     @n
@jn:    iny
        iny
        bra     @j
@n:     inx
        inx
        bra     @i

; row X (ly_*) marked? -> C set
rowdirty:
        ldy     #0
@l:     cpy     mk_n
        bcs     @no
        lda     ly_l,x
        cmp     mk_l0,y
        bcc     @nx
        lda     mk_l1,y
        cmp     ly_l,x
        bcc     @nx
        lda     mk_c0,y                 ; the columns: c0 <= e and c1 >= s
        cmp     ly_e,x
        beq     :+
        bcs     @nx
:       lda     mk_c1,y
        cmp     ly_s,x
        bcs     @yes
@nx:    iny
        iny
        bra     @l
@yes:   sec
        rts
@no:    clc
        rts

; the longest run of rows that move by the same amount (and lie together on the screen):
; moved with one copy; the others that move are drawn (rm_j = NONE)
movebest:
        stz     mb_h                    ; the best: its height, first row, rows
        ldx     #0
@i:     cpx     nly2
        bcs     @go
        lda     rm_j,x
        cmp     #NONE
        beq     @nx
        lda     rm_dy,x
        beq     @nx
        stx     mb_f                    ; a run from here
        lda     ly_h,x
        sta     z:t0
        txy
@r:     iny
        iny
        cpy     nly2
        bcs     @end
        lda     rm_j,y
        cmp     #NONE
        beq     @end
        lda     rm_dy,y
        cmp     rm_dy,x
        bne     @end
        lda     rm_j,y
        dec     a
        dec     a
        cmp     rm_j-2,y
        bne     @end
        lda     ly_h,y
        clc
        adc     z:t0
        sta     z:t0
        bra     @r
@end:   lda     z:t0
        cmp     mb_h
        bcc     :+
        beq     :+
        sta     mb_h
        stx     mb_bf
        sty     mb_bl
:       tyx
        bra     @i
@nx:    inx
        inx
        bra     @i
@go:    lda     mb_h                    ; the copy
        beq     @drop
        ldx     mb_bf
        lda     rm_j,x
        tay
        lda     dr_y,y
        clc
        adc     #TBH
        sta     z:ui_y
        stz     z:ui_x
        lda     tw
        sta     z:ui_w
        lda     mb_h
        sta     z:ui_h
        lda     win
        sta     z:ui_win
        lda     ly_y,x
        clc
        adc     #TBH
        tay
        ldx     #0
        jsr     ui_copy
@drop:  ldx     #0                      ; the other moves: drawn
@d:     cpx     nly2
        bcs     @out
        lda     rm_dy,x
        beq     @dn
        lda     mb_h
        beq     :+
        cpx     mb_bf
        bcc     :+
        cpx     mb_bl
        bcc     @dz
:       lda     #NONE
        sta     rm_j,x
        bra     @dn
@dz:    stz     rm_dy,x                 ; (moved: in place now)
@dn:    inx
        inx
        bra     @d
@out:   rts

; the text area's paper from y = t4, t5 lines high (the page and its surround)
bgrect: lda     z:t5
        beq     @out
        bmi     @out
        lda     win
        sta     z:ui_win
        lda     z:t4
        clc
        adc     #TBH
        sta     z:ui_y
        lda     z:t5
        sta     z:ui_h
        lda     pagew
        bne     @page
        stz     z:ui_x
        lda     tw
        sta     z:ui_w
        lda     #WD_FILL | (C_WHITE << 8)
        jmp     ui_rect
@page:  stz     z:ui_x
        lda     tl
        sec
        sbc     #PAGEP
        sta     z:ui_w
        lda     #WD_FILL | (C_PAGEBG << 8)
        jsr     ui_rect
        lda     z:ui_w
        sta     z:ui_x
        lda     colw
        clc
        adc     #2 * PAGEP
        sta     z:ui_w
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     ui_rect
        lda     z:ui_x
        clc
        adc     z:ui_w
        sta     z:ui_x
        eor     #$FFFF
        sec
        adc     tw
        sta     z:ui_w
        lda     #WD_FILL | (C_PAGEBG << 8)
        jmp     ui_rect
@out:   rts

; ---------------------------------------------------------------- one row
; row X (ly_*) drawn into the row buffer and blitted: what differs from the row drawn at
; its place before (rowrec), or all of it
drawrow:
        lda     ly_l,x
        sta     dw_l
        lda     ly_s,x
        sta     dw_s
        sta     rw_s
        lda     ly_e,x
        sta     dw_e
        sta     rw_e
        lda     ly_y,x
        sta     dw_y
        lda     ly_h,x
        sta     dw_h
        lda     #NONE                   ; the row drawn at this place before (its record)
        sta     dw_os
        lda     dr_ok
        beq     @new
        ldy     #0
@o:     cpy     dr_n2
        bcs     @new
        lda     dr_y,y
        cmp     dw_y
        bne     :+
        lda     dr_h,y
        cmp     dw_h
        bne     @new
        lda     dr_slot,y
        sta     dw_os
        bra     @new
:       iny
        iny
        bra     @o
@new:   phx                             ; a record of its own
        jsr     slalloc
        plx
        sta     dw_ns
        sta     ly_slot,x
        lda     dw_l
        jsr     lrows
        lda     dw_l
        jsr     lmodel
        ldx     m_blk                   ; the baseline
        txa
        asl     a
        tax
        lda     dw_s
        bne     :+
        lda     rb0,x
        bra     :++
:       lda     rb1,x
:       sta     dw_by
        lda     cut,x
        sta     dw_cut
        lda     cuh,x
        sta     dw_cuh
        lda     m_hx                    ; the text's left
        ldx     dw_s
        bne     :+
        lda     m_cx
:       clc
        adc     tl
        sta     dw_x0
        ; how far right it draws (the rest of the row: one WD_FILL after the blit)
        lda     tw
        sta     dw_xr
        lda     ml_f
        and     #RVP
        bne     :+
        lda     m_blk
        cmp     #B_RULE
        beq     @sel
:       lda     dw_e
        jsr     wstopat
        lda     wx
        clc
        adc     tl
        adc     #8                      ; (the line end selected, italic, the cursor)
        and     #$FFFE
        cmp     tw
        bcs     @sel
        sta     dw_xr
@sel:   ; the selection: columns dw_sa .. dw_sb of this row; dw_le 4: the line end too
        stz     dw_sa
        stz     dw_sb
        stz     dw_le
        stz     dw_sr
        lda     selon
        jeq     @cc
        lda     dw_l
        cmp     s0l
        jcc     @cc
        cmp     s1l
        beq     :+
        jcs     @cc
:       stz     dw_a
        cmp     s0l
        bne     :+
        lda     s0c
        sta     dw_a
:       lda     llen
        sta     dw_b
        lda     dw_l
        cmp     s1l
        bne     :+
        lda     s1c
        sta     dw_b
        bra     :++
:       lda     dw_e
        cmp     llen
        bcc     :+
        lda     #4
        sta     dw_le
:       lda     dw_a
        cmp     dw_s
        bcs     :+
        lda     dw_s
        sta     dw_a
:       lda     dw_b
        cmp     dw_e
        bcc     :+
        lda     dw_e
        sta     dw_b
:       lda     dw_a
        cmp     dw_b
        bcc     :+
        lda     dw_le
        beq     @cc
        lda     dw_b
        sta     dw_a
:       lda     dw_a
        sta     dw_sa
        lda     dw_b
        sta     dw_sb
        inc     dw_sr
@cc:    lda     #NONE                   ; the cursor's column in the row (no selection)
        sta     dw_cc
        lda     dw_l
        cmp     cl
        bne     @rec
        lda     selon
        bne     @rec
        lda     cc
        cmp     dw_s
        bcc     @rec
        cmp     dw_e
        bcc     :+
        bne     @rec
        lda     dw_e
        cmp     llen
        bcc     @rec
:       lda     cc
        sec
        sbc     dw_s
        sta     dw_cc
@rec:   jsr     rowrec                  ; what to draw
        bcc     :+
        rts                             ; (nothing: it is on the screen)
:       lda     th                      ; (cut at the status line)
        sec
        sbc     dw_y
        cmp     dw_h
        bcc     :+
        lda     dw_h
:       sta     bl_h
        lda     dw_cpw                  ; the end moved: copied on the screen first
        beq     :+
        sta     z:ui_w
        lda     dw_cpx
        sta     z:ui_x
        lda     bl_h
        sta     z:ui_h
        lda     dw_y
        clc
        adc     #TBH
        sta     z:ui_y
        tay
        lda     win
        sta     z:ui_win
        ldx     dw_p1
        jsr     ui_copy
:       lda     dw_p0                   ; the part that changed, the end too
        ldx     dw_p1
        jsr     dpart
        lda     dw_p2
        cmp     dw_p3
        bcs     :+
        ldx     dw_p3
        jsr     dpart
:       lda     dw_y
        clc
        adc     #TBH
        sta     bl_y
@rest:  lda     dw_xr                   ; the rest of the row, as far as the row before
        cmp     dw_rest                 ; reached: its paper
        bcc     :+
        rts
:       sta     z:ui_x
        lda     bl_y
        sta     z:ui_y
        lda     bl_h
        sta     z:ui_h
        lda     win
        sta     z:ui_win
        lda     pagew
        bne     :+
        lda     dw_rest
        sec
        sbc     z:ui_x
        sta     z:ui_w
        lda     #WD_FILL | (C_WHITE << 8)
        jmp     ui_rect
:       lda     tl                      ; page: white to the page's edge, then grey
        clc
        adc     colw
        adc     #PAGEP
        cmp     dw_rest
        bcc     :+
        lda     dw_rest
:       sec
        sbc     z:ui_x
        beq     :+
        bmi     :+
        sta     z:ui_w
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     ui_rect
        lda     z:ui_x
        clc
        adc     z:ui_w
        sta     z:ui_x
:       lda     dw_rest
        sec
        sbc     z:ui_x
        beq     :+
        bmi     :+
        sta     z:ui_w
        lda     #WD_FILL | (C_PAGEBG << 8)
        jmp     ui_rect
:       rts

; the row being drawn (drawrow), its pixels A .. X: into the row buffer, blitted
dpart:  sta     clx0
        stx     clx1
        lda     dw_s                    ; the first column that can reach them
        clc
        adc     #4
        tay
        lda     dw_e
        clc
        adc     #4
        sta     z:mq
        lda     clx0
        sec
        sbc     #24
        sta     z:t0
        lda     dw_x0
        bit     z:t0
        bmi     @j0
:       cpy     z:mq
        bcs     @j0
        sta     z:t1
        lda     [ma],y
        and     #$00FF
        clc
        adc     z:t1
        cmp     z:t0
        bcs     :+
        iny
        bra     :-
:       lda     z:t1
@j0:    sty     dw_j0
        sta     dw_jx
        ; the paper
        stz     z:qy
        lda     dw_h
        sta     z:qh
        stz     z:qx
        lda     pagew
        bne     :+
        lda     dw_xr
        sta     z:qw
        lda     #C_WHITE
        jsr     bfill
        bra     @tint
:       lda     tl
        sec
        sbc     #PAGEP
        sta     z:qw
        lda     #C_PAGEBG
        jsr     bfill
        lda     tl
        sec
        sbc     #PAGEP
        sta     z:qx
        lda     dw_xr
        sec
        sbc     z:qx
        sta     z:qw
        lda     #C_WHITE
        jsr     bfill
        lda     tl                      ; (the page's right edge in it?)
        clc
        adc     colw
        adc     #PAGEP
        sta     z:qx
        eor     #$FFFF
        sec
        adc     dw_xr
        sta     z:qw
        lda     #C_PAGEBG
        jsr     bfill
@tint:  ; code spans' tint (runs of shown code characters)
        lda     dw_by
        sec
        sbc     #8
        sta     z:qy
        lda     #12
        sta     z:qh
        lda     dw_jx
        sta     dw_cx
        lda     #NONE
        sta     dw_t0
        ldy     dw_j0
@t:     tya
        sec
        sbc     #4
        cmp     dw_e
        bcs     @tend
        lda     [mb],y
        and     #S_C | S_H
        cmp     #S_C
        bne     @tno
        lda     dw_t0                   ; in a run
        cmp     #NONE
        bne     @tadv
        lda     dw_cx
        sta     dw_t0
        bra     @tadv
@tno:   jsr     @tflush
@tadv:  lda     [ma],y
        and     #$00FF
        clc
        adc     dw_cx
        sta     dw_cx
        iny
        cmp     clx1                    ; (past what is drawn: done)
        bcc     @t
@tend:  jsr     @tflush
        lda     dw_sr                   ; the selection
        beq     @mark
        lda     dw_sa
        jsr     wstopat
        lda     wx
        clc
        adc     tl
        sta     z:qx
        lda     dw_sb
        jsr     wstopat
        lda     wx
        clc
        adc     tl
        adc     dw_le
        sec
        sbc     z:qx
        sta     z:qw
        stz     z:qy
        lda     dw_h
        sta     z:qh
        lda     #C_SELECT
        jsr     bfill
@mark:  jsr     blkmark                 ; the bullet, the number, the bar, the rule
        ; the glyphs (those that can reach clx0 .. clx1: 24 pixels wide at most, an
        ; italic one a pixel more to the left)
        lda     dw_jx
        sta     dw_cx
        ldy     dw_j0
@g:     tya
        sec
        sbc     #4
        cmp     dw_e
        jcs     @cur
        sty     dw_i
        lda     [mb],y
        and     #$00FF
        sta     dw_st
        bit     #S_H
        jne     @gn
        lda     dw_cx
        sec
        sbc     #2
        cmp     clx1
        jcs     @cur                    ; (right of what is drawn: done)
        lda     dw_cx
        clc
        adc     #24
        cmp     clx0
        jcc     @gadv                   ; (left of it)
        lda     [lp],y
        and     #$00FF
        cmp     #' ' + 1
        jcc     @gadv                   ; (space, tab: no ink)
        jsr     glyphc
        sta     dw_gc
        lda     dw_st                   ; the ink
        and     #S_M | S_P
        beq     :+
        lda     #C_MARK
        bra     :++
:       lda     #C_BLACK
        ldx     m_blk
        cpx     #B_QUO
        bne     :+
        lda     #C_QUOTE
:       sta     pg_ink
        ldy     dw_i                    ; selected: white
        tya
        sec
        sbc     #4
        cmp     dw_sa
        bcc     :+
        cmp     dw_sb
        bcs     :+
        lda     #C_WHITE
        sta     pg_ink
:       lda     dw_st
        and     #S_I
        sta     pg_it
        lda     dw_st
        jsr     faceof
        tax
        lda     dw_cx
        sta     pg_x
        lda     dw_by
        sec
        sbc     fd_base,x
        sta     pg_y
        lda     dw_gc
        jsr     plotg
        ldy     dw_i
@gadv:  lda     [ma],y
        and     #$00FF
        clc
        adc     dw_cx
        sta     dw_cx
@gn:    iny
        jmp     @g
@cur:   lda     dw_cc                   ; the cursor
        cmp     #NONE
        beq     @blit
        clc
        adc     dw_s
        jsr     wstopat
        lda     wx
        clc
        adc     tl
        dec     a
        sta     z:qx
        lda     #1
        sta     z:qw
        lda     dw_by
        sec
        sbc     dw_cut
        sta     z:qy
        lda     dw_cuh
        sta     z:qh
        lda     #C_BLACK
        jsr     bfill
@blit:  lda     dw_y
        clc
        adc     #TBH
        sta     bl_y
        lda     clx0
        sta     bl_x
        clc
        adc     #RBOFF
        sta     bl_p
        lda     clx1
        sec
        sbc     clx0
        beq     @nob
        bmi     @nob
        sta     bl_w
        sep     #$20
        .a8
        lda     rbank
        sta     bl_p+2
        rep     #$20
        .a16
        lda     win
        ptr     bl_blk
        sys     SYS_WDRAW
@nob:   lda     #0                      ; (no clip)
        sta     clx0
        lda     #$7FFF
        sta     clx1
        rts

; a code tint run ends here
@tflush:
        lda     dw_t0
        cmp     #NONE
        beq     :+
        sta     z:qx
        lda     dw_cx
        sec
        sbc     z:qx
        inc     a                       ; (a pixel of tint after the last glyph)
        sta     z:qw
        phy
        lda     #C_CODEBG
        jsr     bfill
        ply
        lda     #NONE
        sta     dw_t0
:       rts

; the block's mark in the row buffer (when its marker is hidden)
blkmark:
        lda     ml_f
        and     #RVP
        bne     @out
        lda     m_blk
        cmp     #B_QUO
        beq     @bar
        cmp     #B_RULE
        beq     @rule
        ldx     dw_s                    ; (bullets and numbers: the first row)
        bne     @out
        cmp     #B_BUL
        beq     @bul
        cmp     #B_NUM
        jeq     @num
@out:   rts
@bar:   lda     tl                      ; a quote: a bar left of every row
        clc
        adc     #2
        sta     z:qx
        lda     #3
        sta     z:qw
        stz     z:qy
        lda     dw_h
        sta     z:qh
        lda     #C_MID
        jmp     bfill
@rule:  lda     tl                      ; a rule: a line across the column
        sta     z:qx
        lda     colw
        sta     z:qw
        lda     dw_h
        lsr     a
        sta     z:qy
        lda     #1
        sta     z:qh
        lda     #C_MID
        jsr     bfill
        inc     z:qy
        lda     #C_LIGHT
        jmp     bfill
@bul:   lda     m_lvl                   ; a bullet: a dot, a ring, a square by level
        cmp     #2
        bcc     :+
        lda     #2
:       asl     a
        tax
        lda     bulimg,x
        sta     z:t0
        lda     dw_x0
        sec
        sbc     #GUT - 4
        sta     pg_x
        lda     dw_by
        sec
        sbc     #5
        sta     pg_y
        lda     #C_BLACK
        sta     pg_ink
        stz     pg_it
        ldy     #0                      ; 5 rows of 8 pixels
:       lda     (t0),y
        and     #$00FF
        sta     z:t1
        phy
        jsr     plotb
        ply
        inc     pg_y
        iny
        cpy     #5
        bcc     :-
        rts
@num:   ldy     m_ind                   ; a number: its digits and . or ), right-aligned
        tya                             ; before the text
        clc
        adc     #4
        tay
        lda     m_pfx                   ; (without the space)
        clc
        adc     #3
        sta     z:t3
        sty     z:t2
        lda     #0                      ; its width
:       cpy     z:t3
        bcs     :+
        sta     z:t1
        lda     [lp],y
        jsr     glyphc
        phy
        tay
        lda     FB_adv,y
        and     #$00FF
        clc
        adc     z:t1
        ply
        iny
        bra     :-
:       eor     #$FFFF
        sec
        adc     dw_x0
        sec
        sbc     #4
        sta     pg_x
        lda     dw_by
        sec
        sbc     #FB_BASE
        sta     pg_y
        lda     #C_BLACK
        sta     pg_ink
        stz     pg_it
        ldy     z:t2
:       cpy     z:t3
        bcs     :+
        lda     [lp],y
        jsr     glyphc
        sta     z:t1
        phy
        tay
        lda     FB_adv,y
        and     #$00FF
        pha
        lda     z:t1
        ldx     #F_B
        jsr     plotg
        pla
        clc
        adc     pg_x
        sta     pg_x
        ply
        iny
        bra     :-
:       rts

; ---------------------------------------------------------------- row records
; A record (a slot of 512 bytes in bank VB): n (the row's columns; NONE: not kept, longer than
; RCMAX), x0, the key (block, level, first row, block marker shown), the cursor's column
; in the row (NONE), the right end xr, le (the line end selected), the line's length,
; the row's first column; from 16 on the
; characters, from 256 on their styles (bit 7: selected).
; The record of the row being drawn (slot dw_ns), compared with the one drawn at its
; place before (dw_os) -> dw_p0 .. dw_p1, the pixels to draw, then the paper from dw_xr to
; dw_rest; C set: nothing to draw (the row on the screen is the same)
rowrec: stz     dw_cpw
        stz     dw_p2
        stz     dw_p3
        lda     dw_ns
        jsr     slptr
        lda     z:vh                    ; (the new record: vh, vp, vs)
        sta     z:vg
        lda     z:vh+2
        sta     z:vg+2
        lda     z:vp
        sta     z:vq
        lda     z:vp+2
        sta     z:vq+2
        lda     z:vs
        sta     z:vr
        lda     z:vs+2
        sta     z:vr+2
        lda     dw_e                    ; the header
        sec
        sbc     dw_s
        cmp     #RCMAX + 1
        bcc     :+
        lda     #NONE
:       sta     dw_n
        ldy     #0
        sta     [vg],y
        lda     dw_x0
        ldy     #2
        sta     [vg],y
        lda     ml_f                    ; (the key)
        and     #RVP
        xba
        ldx     dw_s
        bne     :+
        ora     #$0100
:       sta     dw_key
        lda     m_lvl
        asl     a
        asl     a
        asl     a
        asl     a
        ora     m_blk
        ora     dw_key
        sta     dw_key
        ldy     #4
        sta     [vg],y
        lda     dw_cc
        ldy     #6
        sta     [vg],y
        lda     dw_xr
        ldy     #8
        sta     [vg],y
        lda     dw_le
        ldy     #10
        sta     [vg],y
        lda     llen
        ldy     #12
        sta     [vg],y
        lda     dw_s
        ldy     #14
        sta     [vg],y
        lda     dw_n                    ; the characters, the styles
        cmp     #NONE
        beq     @cmp
        lda     dw_e
        clc
        adc     #4
        sta     z:mq
        lda     dw_s
        clc
        adc     #4
        tay
        sep     #$20
        .a8
:       cpy     z:mq
        bcs     :+
        lda     [lp],y
        sta     [vq],y
        lda     [mb],y
        sta     [vr],y
        iny
        bra     :-
:       rep     #$20
        .a16
        lda     dw_sb                   ; (the selected ones)
        clc
        adc     #4
        sta     z:mq
        lda     dw_sa
        clc
        adc     #4
        tay
        sep     #$20
        .a8
:       cpy     z:mq
        bcs     :+
        lda     [vr],y
        ora     #$80
        sta     [vr],y
        iny
        bra     :-
:       rep     #$20
        .a16
@cmp:   lda     dw_os                   ; the record before
        cmp     #NONE
        jeq     @all
        jsr     slptr                   ; (vh, vp, vs: the old one)
        ldy     #8
        lda     [vh],y
        sta     dw_rest
        ldy     #0
        lda     [vh],y
        sta     dw_on
        cmp     #NONE
        jeq     @all0
        lda     dw_n
        cmp     #NONE
        jeq     @all0
        ldy     #2
        lda     [vh],y
        cmp     dw_x0
        jne     @all0
        ldy     #4
        lda     [vh],y
        cmp     dw_key
        jne     @all0
        lda     dw_on                   ; the first column that differs -> dw_k
        cmp     dw_n
        bcc     :+
        lda     dw_n
:       clc
        adc     dw_s
        adc     #4
        sta     z:mq
        lda     dw_s
        clc
        adc     #4
        tay
        sep     #$20
        .a8
:       cpy     z:mq
        bcs     :+
        lda     [vp],y
        cmp     [vq],y
        bne     :+
        lda     [vs],y
        cmp     [vr],y
        bne     :+
        iny
        bra     :-
:       rep     #$20
        .a16
        tya
        sec
        sbc     #4
        sec
        sbc     dw_s
        sta     dw_k
        ldy     #6                      ; the cursors (NONE is never the smaller)
        lda     [vh],y
        sta     dw_oc
        cmp     dw_cc
        beq     :++
        cmp     dw_k
        bcs     :+
        sta     dw_k
:       lda     dw_cc
        cmp     dw_k
        bcs     :+
        sta     dw_k
:       lda     dw_on                   ; the same length, line end and right end: to the
        cmp     dw_n                    ; last column that differs
        jne     @toend
        ldy     #10
        lda     [vh],y
        cmp     dw_le
        jne     @toend
        lda     dw_rest
        cmp     dw_xr
        jne     @toend
        lda     dw_k
        cmp     dw_n
        bcc     @last
        lda     dw_oc
        cmp     dw_cc
        bne     @last
        sec                             ; (nothing differs)
        rts
@last:  lda     dw_k
        clc
        adc     dw_s
        adc     #4
        sta     z:mq
        lda     dw_n
        clc
        adc     dw_s
        adc     #4
        tay
        sep     #$20
        .a8
:       dey
        cpy     z:mq
        bcc     :+
        lda     [vp],y
        cmp     [vq],y
        bne     :+
        lda     [vs],y
        cmp     [vr],y
        beq     :-
:       rep     #$20
        .a16
        tya                             ; -> dw_m: after the last that differs
        sec
        sbc     #3
        sec
        sbc     dw_s
        sta     dw_m
        lda     dw_oc                   ; (and the cursors)
        cmp     dw_cc
        beq     @m
        lda     dw_oc
        jsr     @max
        lda     dw_cc
        jsr     @max
@m:     lda     dw_m
        jsr     rcx
        clc
        adc     #4
        cmp     dw_xr
        bcc     :+
        lda     dw_xr
:       sta     dw_p1
        stz     dw_rest
        bra     @p0
@toend: jsr     rshift                  ; (the end moved: copied on the screen?)
        bcc     @p0
        lda     dw_xr
        sta     dw_p1
@p0:    lda     dw_k                    ; from the first (a block marker: from the left)
        cmp     dw_n
        bcs     :+
        clc
        adc     dw_s
        adc     #4
        tay
        lda     [vr],y
        and     #S_P
        bne     @left
:       lda     dw_k
        jsr     rcx
        sec
        sbc     #4
        bpl     :+
@left:  lda     #0
:       sta     dw_p0
        clc
        rts
@all:   lda     tw                      ; (no row there before: the paper to the end)
        sta     dw_rest
@all0:  stz     dw_p0
        lda     dw_xr
        sta     dw_p1
        clc
        rts
@max:   cmp     #NONE
        beq     :+
        cmp     dw_m
        bcc     :+
        sta     dw_m
:       rts

; (rowrec) columns of the old row are in the new one, moved right or left (a character
; typed or deleted, a word wrapped to another row): a run of them, new columns dw_js ..
; dw_je, old ones + dw_d, moved by dw_dx pixels. Tried: the run that ends both rows; the one
; that starts at both cursors; the one that starts where the old row's first column is now
; (the line's columns moved by the change of its length). The columns before the run are
; drawn (to dw_p1, a few pixels into it: what leans over from the left), the run is copied
; on the screen (dw_cpx, dw_cpw pixels, to dw_p1), what follows it is drawn (dw_p2 ..
; dw_p3) -> C clear: so; C set: not (drawn to the end)
rshift: ldy     #10                     ; (the line end selected or not as before)
        lda     [vh],y
        cmp     dw_le
        jne     rs_no
        lda     dw_on                   ; 1. the ends aligned: back from the end
        sec
        sbc     dw_n
        sta     dw_d1
        jsr     rs_ptr
        lda     dw_k                    ; (down to max(k, k - d))
        sec
        sbc     dw_d
        bmi     :+
        cmp     dw_k
        bcs     :++
:       lda     dw_k
:       clc
        adc     dw_s
        adc     #4
        sta     z:mq
        lda     dw_n
        clc
        adc     dw_s
        adc     #4
        tay
        sep     #$20
        .a8
:       dey
        cpy     z:mq
        bcc     :+
        lda     [vt],y
        cmp     [vq],y
        bne     :+
        lda     [vu],y
        cmp     [vr],y
        beq     :-
:       rep     #$20
        .a16
        iny
        tya
        sec
        sbc     #4
        sec
        sbc     dw_s
        sta     dw_js
        lda     dw_n
        sta     dw_je
        jsr     rs_go
        bcs     :+
        rts
:       lda     #NONE                   ; 2. aligned at the cursors: on from them
        sta     dw_d2
        lda     dw_oc
        cmp     #NONE
        beq     @m3
        lda     dw_cc
        cmp     #NONE
        beq     @m3
        lda     dw_oc
        sec
        sbc     dw_cc
        sta     dw_d2
        cmp     dw_d1
        beq     @m3
        lda     dw_cc
        jsr     rs_fwd
        bcs     @m3
        rts
@m3:    ldy     #14                     ; 3. the old first column where it is now: the
        lda     [vh],y                  ; line's columns moved by its change of length
        sec                             ; (d = new s - old s - (new length - old length))
        sbc     dw_s
        eor     #$FFFF
        inc     a
        sta     dw_d
        ldy     #12
        lda     [vh],y
        clc
        adc     dw_d
        sec
        sbc     llen
        cmp     dw_d1
        beq     rs_no
        cmp     dw_d2
        beq     rs_no
        pha
        eor     #$FFFF                  ; (from max(k, -d))
        inc     a
        bmi     :+
        cmp     dw_k
        bcs     :++
:       lda     dw_k
:       sta     z:t2
        pla
        sta     dw_d
        lda     z:t2
        jmp     rs_fwd0
rs_no:  stz     dw_p2
        stz     dw_p3
        stz     dw_cpw
        sec
        rts

; alignment dw_d (A: rs_fwd0, A = dw_d), the run on from new column A while the columns are
; equal -> rs_go
rs_fwd: pha
        lda     dw_d2
        sta     dw_d
        pla
rs_fwd0:
        sta     dw_js
        lda     dw_d
        jsr     rs_ptr
        lda     dw_on                   ; (up to min(n, old n - d))
        sec
        sbc     dw_d
        cmp     dw_n
        bcc     :+
        lda     dw_n
:       clc
        adc     dw_s
        adc     #4
        sta     z:mq
        lda     dw_js
        clc
        adc     dw_s
        adc     #4
        tay
        sep     #$20
        .a8
:       cpy     z:mq
        bcs     :+
        lda     [vt],y
        cmp     [vq],y
        bne     :+
        lda     [vu],y
        cmp     [vr],y
        bne     :+
        iny
        bra     :-
:       rep     #$20
        .a16
        tya
        sec
        sbc     #4
        sec
        sbc     dw_s
        sta     dw_je
        ; fall through
; the run dw_js .. dw_je (alignment dw_d): the cursors in it at the same place, wide
; enough -> the copy, the parts to draw; C set: not usable
rs_go:  lda     dw_je
        cmp     dw_js
        beq     rs_no
        bcc     rs_no
        lda     dw_je                   ; (the run ends both rows: a cursor after its last
        cmp     dw_n                    ; column is in it too)
        bne     :+
        clc
        adc     dw_d
        cmp     dw_on
        bne     :+
        lda     #1
        bra     :++
:       lda     #0
:       sta     dw_ee
        lda     dw_cc
        jsr     @inrun
        sta     z:t2
        lda     dw_oc
        cmp     #NONE
        beq     :+
        sec
        sbc     dw_d
:       jsr     @inrun
        cmp     z:t2
        jne     rs_no
        lda     dw_k                    ; the old run's x: x(k) + the old columns k .. js + d
        jsr     rcx
        sta     z:t3
        lda     dw_js
        clc
        adc     dw_d
        cmp     dw_k
        jcc     rs_no
        clc
        adc     dw_s
        adc     #4
        sta     z:mq
        lda     dw_k
        clc
        adc     dw_s
        adc     #4
        tay
:       cpy     z:mq
        bcs     :+
        lda     [vs],y
        and     #$007F
        sta     z:t1
        lda     [vp],y
        jsr     advof
        clc
        adc     z:t3
        sta     z:t3
        iny
        bra     :-
:       lda     dw_js                   ; the new run's x, the move
        jsr     rcx
        sta     z:t4
        sec
        sbc     z:t3
        sta     dw_dx
        lda     z:t4                    ; drawn to 6 pixels into it (whole columns)
        clc
        adc     #6
        sta     z:t5
        lda     dw_je
        clc
        adc     dw_s
        adc     #4
        sta     z:mq
        lda     dw_js
        clc
        adc     dw_s
        adc     #4
        tay
        lda     z:t4
:       cmp     z:t5
        bcs     :+
        cpy     z:mq
        jcs     rs_no
        sta     z:t4
        lda     [ma],y
        and     #$00FF
        clc
        adc     z:t4
        iny
        bra     :-
:       sta     dw_p1
        lda     dw_xr                   ; the copy: to the new right end, or (the run
        sta     z:t4                    ; ending before the row) to 2 pixels before its end
        stz     dw_p2
        stz     dw_p3
        lda     dw_ee
        bne     :+
        lda     dw_je
        jsr     rcx
        sec
        sbc     #2
        sta     z:t4
        sta     dw_p2
        lda     dw_xr
        sta     dw_p3
:       lda     z:t4
        sec
        sbc     dw_p1
        beq     :+
        bpl     :++
:       jmp     rs_no
:       sta     dw_cpw
        lda     dw_p1
        sec
        sbc     dw_dx
        sta     dw_cpx
        bpl     :+
        jmp     rs_no
:       clc
        adc     dw_cpw
        cmp     tw
        beq     :+
        jcs     rs_no
:       lda     dw_dx                   ; (not moved: nothing to copy)
        bne     :+
        stz     dw_cpw
:       clc
        rts
; a cursor's column A (new columns): its place in the run (NONE: not in it)
@inrun: cmp     #NONE
        beq     @nr
        cmp     dw_js
        bcc     @nr
        cmp     dw_je
        bcc     :+
        bne     @nr
        ldx     dw_ee
        beq     @nr
:       sec
        sbc     dw_js
        rts
@nr:    lda     #NONE
        rts

; alignment d = A (old column = new column + d): vt, vu = the old record's columns at the
; new ones' indexes
rs_ptr: sta     dw_d
        clc
        adc     z:vp
        sta     z:vt
        lda     dw_d
        and     #$8000
        beq     :+
        lda     #$FFFF
:       sta     z:t0
        adc     z:vp+2
        sta     z:vt+2
        lda     dw_d
        clc
        adc     z:vs
        sta     z:vu
        lda     z:t0
        adc     z:vs+2
        sta     z:vu+2
        rts

; the advance of character A (low byte) with style z:t1 in the line modelled -> A
advof:  and     #$00FF
        sta     z:t2
        lda     z:t1
        bit     #S_H
        bne     @z
        lda     z:t2
        cmp     #9
        bne     :+
        lda     #TABW
        rts
:       phx
        phy
        lda     z:t1
        jsr     faceof
        tax
        lda     z:t2
        jsr     glyphc
        tay
        lda     fd_adv,x
        sta     z:mc
        lda     (mc),y
        and     #$00FF
        ply
        plx
        rts
@z:     lda     #0
        rts

; the x of the row's column dw_s + A (in the window) -> A
rcx:    clc
        adc     dw_s
        adc     #4
        sta     z:mq
        lda     dw_s
        clc
        adc     #4
        tay
        lda     dw_x0
:       cpy     z:mq
        bcs     :+
        sta     z:mc
        lda     [ma],y
        and     #$00FF
        clc
        adc     z:mc
        iny
        bra     :-
:       rts

; slot A -> vh (its header), vp, vs (its characters, its styles: [vp],y and [vs],y with
; Y = a column + 4, from column dw_s on)
slptr:  xba
        and     #$FF00
        asl     a
        sta     z:vh
        lda     vbank
        sta     z:vh+2
        lda     dw_s
        clc
        adc     #4
        sta     z:t0
        lda     z:vh
        clc
        adc     #16
        sec
        sbc     z:t0
        sta     z:vp
        lda     vbank
        sbc     #0
        sta     z:vp+2
        lda     z:vh
        clc
        adc     #256
        sec
        sbc     z:t0
        sta     z:vs
        lda     vbank
        sbc     #0
        sta     z:vs+2
        rts

; ---------------------------------------------------------------- the row buffer
; fill qx, qy, qw x qh of the row buffer with colour A, cut to clx0 .. clx1 (stores of 16
; bits, DBR = the buffer's bank; qx .. qh are kept)
bfill:  and     #$00FF
        sta     z:qc
        xba
        ora     z:qc
        sta     z:qc
        lda     z:qw
        beq     @out0
        bmi     @out0
        lda     z:qh
        beq     @out0
        bpl     @go
@out0:  rts
@go:    lda     z:qx                    ; the columns cut: qa .. qa + qv
        sta     z:qa
        clc
        adc     z:qw
        cmp     clx1
        bcc     :+
        lda     clx1
:       sta     z:qv
        lda     z:qa
        cmp     clx0
        bcs     :+
        lda     clx0
        sta     z:qa
:       lda     z:qv
        sec
        sbc     z:qa
        beq     @out0
        bmi     @out0
        sta     z:qv
        lda     z:qh
        sta     z:qn
        lda     z:qy
        xba
        and     #$FF00
        asl     a
        asl     a
        clc
        adc     z:qa
        adc     #RBOFF
        sta     z:qo
        phb
        sep     #$20
        .a8
        lda     rbank
        pha
        plb
        rep     #$20
        .a16
@row:   ldx     z:qo
        ldy     z:qv
        txa
        lsr     a
        bcc     :+
        sep     #$20                    ; (an odd start: one byte)
        .a8
        lda     z:qc
        sta     a:0,x
        rep     #$20
        .a16
        inx
        dey
        jeq     @next
:       tya
        lsr     a
        tay                             ; words
        php
        lda     z:qc
@w8:    cpy     #32
        bcc     @w1
        .repeat 32, I
        sta     a:2 * I,x
        .endrepeat
        txa
        clc
        adc     #64
        tax
        tya
        sec
        sbc     #32
        tay
        lda     z:qc
        bra     @w8
@w1:    cpy     #0
        beq     :+
        sta     a:0,x
        inx
        inx
        dey
        bra     @w1
:       plp
        bcc     @next
        sep     #$20                    ; (an odd end)
        .a8
        sta     a:0,x
        rep     #$20
        .a16
@next:  lda     z:qo
        clc
        adc     #RBS
        sta     z:qo
        dec     z:qn
        beq     :+
        jmp     @row
:
        plb
@out:   rts

; glyph A of face X at pg_x, pg_y (its top row) in colour pg_ink; pg_it: sheared
; (italic). Each glyph row: one or two bytes, bit 7 leftmost; a set bit stores the ink.
; (For a 1-bpp expanding blit, when the kernel has one: dpart would gather the glyphs of a
; run of one ink, face and slant into a 1-bpp row (each glyph row byte shifted to its x and
; OR-ed in; italic rows at their shear) and expand it over the paper already in the row
; buffer (the 0 bits transparent) in one op a run, instead of these per-byte stores; the
; paper, tint, selection and cursor fills and the one blit of the part stay as they are.)
; (A 8 bits inside, B = the ink; Y = the glyph's byte, X = where its row goes)
plotg:  asl     a
        tay
        lda     fd_off,x
        sta     z:t0
        lda     (t0),y
        sta     z:gb
        lda     fd_ish,x
        sta     z:gi
        lda     fd_rows,x
        sta     pg_n
        lda     fd_bpr,x
        sta     pg_bpr
        lda     pg_y
        xba
        and     #$FF00
        asl     a
        asl     a
        clc
        adc     pg_x
        adc     #RBOFF
        sta     z:go
        ldy     #0
        sep     #$20
        .a8
        lda     pg_ink
        xba
        lda     pg_it
        bne     @it
        lda     pg_bpr
        cmp     #2
        beq     @two
@one:   lda     [gb],y                  ; one byte a row
        beq     :+
        ldx     z:go
        jsr     pbits
:       iny
        lda     z:go+1                  ; (the next row: + RBS)
        clc
        adc     #>RBS
        sta     z:go+1
        dec     pg_n
        bne     @one
        rep     #$20
        .a16
        rts
        .a8
@two:   lda     [gb],y                  ; two bytes a row
        beq     :+
        ldx     z:go
        jsr     pbits
:       iny
        lda     [gb],y
        beq     :+
        ldx     z:go
        jsr     pbits8
:       iny
        lda     z:go+1
        clc
        adc     #>RBS
        sta     z:go+1
        dec     pg_n
        bne     @two
        rep     #$20
        .a16
        rts
        .a8
@it:    lda     [gb],y                  ; italic: each row moved by its shear
        beq     :+
        jsr     @sx
        jsr     pbits
:       lda     pg_bpr
        cmp     #2
        bne     :++
        iny
        lda     [gb],y
        beq     :+
        jsr     @sx
        jsr     pbits8
:
:       iny
        rep     #$20
        .a16
        inc     z:gi
        sep     #$20
        .a8
        lda     z:go+1
        clc
        adc     #>RBS
        sta     z:go+1
        dec     pg_n
        bne     @it
        rep     #$20
        .a16
        rts
        .a8
; X = this row's place + its shear (A kept)
@sx:    pha
        ldx     z:go
        lda     (gi)
        beq     @sxo
        bmi     @sxm
:       inx
        dec     a
        bne     :-
        bra     @sxo
@sxm:   dex
@sxo:   pla
        rts

; one byte of a glyph row in the row buffer: A (8 bits) = the bits, B = the ink, X = where
; the leftmost goes (pbits8: 8 pixels further right). The stores' bank is the row buffer's
; (set at start: pb_bank).
pbits8: inx
        inx
        inx
        inx
        inx
        inx
        inx
        inx
pbits:
.macro  PBIT    n
        asl     a
        bcc     :+
        xba
        .ident(.sprintf("pb%d", n)):
        sta     f:$010000,x
        xba
:       beq     pb_out
        inx
.endmacro
        PBIT    0
        PBIT    1
        PBIT    2
        PBIT    3
        PBIT    4
        PBIT    5
        PBIT    6
        asl     a
        bcc     pb_out
        xba
pb7:    sta     f:$010000,x
        xba
pb_out:   rts
        .a16

; the row buffer's bank into pbits' stores
pb_bank:
        sep     #$20
        .a8
        lda     rbank
        sta     pb0+3
        sta     pb1+3
        sta     pb2+3
        sta     pb3+3
        sta     pb4+3
        sta     pb5+3
        sta     pb6+3
        sta     pb7+3
        rep     #$20
        .a16
        rts

; one row of 8 pixels (z:t1, bit 7 leftmost) at pg_x, pg_y in pg_ink
plotb:  lda     pg_y
        xba
        and     #$FF00
        asl     a
        asl     a
        clc
        adc     pg_x
        adc     #RBOFF
        tax
        sep     #$20
        .a8
        lda     pg_ink
        xba
        lda     z:t1
        beq     :+
        jsr     pbits
:       rep     #$20
        .a16
        rts

        .segment "RODATA"
; rows: heights (a line's first row, the others), baselines, the cursor (from the
; baseline up, its height), by block
rh0:    .word   14, 32, 26, 20, 14, 14, 14, 14, 14
rh1:    .word   14, 24, 20, 14, 14, 14, 14, 14, 14
rb0:    .word   9, 23, 18, 15, 9, 9, 9, 9, 9
rb1:    .word   9, 15, 12, 9, 9, 9, 9, 9, 9
cut:    .word   8, 15, 11, 8, 8, 8, 8, 8, 8
cuh:    .word   12, 21, 16, 12, 12, 12, 12, 12, 12
; bullets: 5 rows of 8 pixels
bulimg: .addr   bul0, bul1, bul2
bul0:   .byte   $70, $F8, $F8, $F8, $70
bul1:   .byte   $70, $88, $88, $88, $70
bul2:   .byte   $00, $78, $78, $78, $78

        .segment "DATA"
bl_blk: .byte   WD_SBLIT, <RBS, >RBS, 0
bl_x:   .word   0
bl_y:   .word   0
bl_w:   .word   0
bl_h:   .word   0
bl_p:   .word   RBOFF
        .byte   0

        .segment "BSS"
nly2:   .res    2                       ; the rows wanted * 2
rf_i:   .res    2
lyi:    .res    2
ly_bot: .res    2
ly_ec:  .res    2                       ; the layout's key (ed_cnt, top, toff, rv_l)
ly_top: .res    2
ly_toff: .res   2
ly_rv:  .res    2
ly_pl:  .res    2
ly_ps:  .res    2
ly_l:   .res    MAXROWS * 2             ; the rows wanted, the rows drawn
ly_s:   .res    MAXROWS * 2
ly_e:   .res    MAXROWS * 2
ly_y:   .res    MAXROWS * 2
ly_h:   .res    MAXROWS * 2
dr_n2:  .res    2
dr_l:   .res    MAXROWS * 2
dr_s:   .res    MAXROWS * 2
dr_e:   .res    MAXROWS * 2
dr_y:   .res    MAXROWS * 2
dr_h:   .res    MAXROWS * 2
rm_j:   .res    MAXROWS * 2
rm_dy:  .res    MAXROWS * 2
dr_ok:  .res    2
mt_ok:  .res    2                       ; maxtop known
mt_line: .res   2
mb_h:   .res    2
mb_f:   .res    2
mb_bf:  .res    2
mb_bl:  .res    2
pr_l:   .res    2                       ; prevrow / nextrow
pr_s:   .res    2
en_y:   .res    2
en_n:   .res    2
en_l:   .res    2
en_s:   .res    2
selon:  .res    2
sbl_pos: .res   2
sbl_max: .res   2
sbl_page: .res  2
dw_l:   .res    2                       ; the row being drawn
dw_s:   .res    2
dw_e:   .res    2
dw_y:   .res    2
dw_h:   .res    2
dw_by:  .res    2
dw_cut: .res    2
dw_cuh: .res    2
dw_x0:  .res    2
dw_xr:  .res    2
dw_cx:  .res    2
dw_t0:  .res    2
dw_a:   .res    2
dw_b:   .res    2
dw_sa:  .res    2
dw_sb:  .res    2
dw_i:   .res    2
dw_st:  .res    2
dw_gc:  .res    2
dw_le:  .res    2
dw_sr:  .res    2
dw_cc:  .res    2
dw_os:  .res    2
dw_ns:  .res    2
dw_n:   .res    2
dw_on:  .res    2
dw_oc:  .res    2
dw_k:   .res    2
dw_m:   .res    2
dw_key: .res    2
dw_p0:  .res    2
dw_p1:  .res    2
dw_rest: .res   2
dw_p2:  .res    2                       ; (a second part: the end)
dw_p3:  .res    2
dw_j0:  .res    2                       ; dpart: its first column, its x
dw_jx:  .res    2
dw_je:  .res    2
dw_ee:  .res    2
dw_d1:  .res    2
dw_d2:  .res    2
dw_cpx: .res    2                       ; rshift: the copy, the move
dw_cpw: .res    2
dw_dx:  .res    2
dw_d:   .res    2
dw_js:  .res    2
dw_jo:  .res    2
clx0:   .res    2                       ; bfill's clip
clx1:   .res    2
sl_busy: .res   SLN                     ; the records' slots in use
ly_slot: .res   MAXROWS * 2
dr_slot: .res   MAXROWS * 2
pg_x:   .res    2
pg_y:   .res    2
pg_ink: .res    2
pg_it:  .res    2
pg_n:   .res    2
pg_bpr: .res    2

        .segment "ZEROPAGE"
qx:     .res    2                       ; bfill
qy:     .res    2
qw:     .res    2
qh:     .res    2
qn:     .res    2
qc:     .res    2
qo:     .res    2
qa:     .res    2
qv:     .res    2
vh:     .res    4                       ; row records (rowrec)
vp:     .res    4
vs:     .res    4
vg:     .res    4
vq:     .res    4
vr:     .res    4
vt:     .res    4
vu:     .res    4
gb:     .res    4                       ; plotg (the glyph, in VB)
gi:     .res    2
go:     .res    2
gy:     .res    2
gw:     .res    2
