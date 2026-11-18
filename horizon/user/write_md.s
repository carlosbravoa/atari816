; write_md.s - Write: Markdown and the rows (part of write.s).
;
; md_block: the block a line starts (B_*, its marker's length m_pfx, its list level).
; lmodel:   the line model of one line (the last one asked for is kept): for each
;           character a style byte (S_*: bold, italic, code, an inline marker, the block
;           marker, hidden) and its advance in pixels, in bank MB at 4 + column ($4004 +
;           column), so the line's bytes ([lp], 4 + column) and these share an index.
; lrows:    where a line wraps: the line cache (LCN lines, LCK row starts each) holds the
;           row starts of the lines laid out lately; a change of a line drops its entry,
;           lines inserted and deleted renumber the entries (and the rows drawn, the
;           marks). rowend, rowof: rows of the line asked for last.
; wstopat, whitat: x of a column in a row, the column at an x.

B_PARA  = 0                             ; blocks
B_H1    = 1
B_H2    = 2
B_H3    = 3
B_BUL   = 4
B_NUM   = 5
B_QUO   = 6
B_RULE  = 7
B_BLANK = 8
S_B     = 1                             ; style bits
S_I     = 2
S_C     = 4
S_M     = 8                             ; an inline marker (** * ` \)
S_P     = 16                            ; the block's marker
S_H     = 32                            ; not shown (no width)
RVI     = 1                             ; laid out with the inline markers shown
RVP     = 2                             ;   with the block marker shown
F_B     = 0                             ; type faces (wfont.inc)
F_BB    = 2
F_F     = 4
F_H1    = 6
F_H2    = 8
LIND    = 18                            ; a list level's indent
GUT     = 16                            ; a list item's gutter (the bullet, the number)
QIND    = 16                            ; a quote's indent
TABW    = 16                            ; a tab's advance
LCN     = 64                            ; the line cache: lines
LCK     = 16                            ;   row starts each
MAXD    = 48                            ; delimiter runs in a line (more: literal)

        .segment "CODE"

; ---------------------------------------------------------------- blocks
; line lp (llen) -> m_blk, m_pfx (the marker's length, with its spaces), m_lvl (list
; level, 4 spaces a level), m_ind (leading spaces)
md_block:
        stz     m_lvl
        stz     m_pfx
        lda     llen
        clc
        adc     #4
        sta     z:mq
        ldy     #4
:       cpy     z:mq                    ; leading spaces
        jcs     @blank
        lda     [lp],y
        and     #$00FF
        cmp     #' '
        bne     :+
        iny
        bra     :-
:       sta     z:mc
        tya
        sec
        sbc     #4
        sta     m_ind
        cmp     #4
        jcs     @list                   ; (indented: only a list item)
        lda     z:mc
        cmp     #'-'
        beq     @rule
        cmp     #'_'
        beq     @rule
        cmp     #'*'
        bne     @hd
@rule:  phy                             ; - * _: three or more, only spaces between
        ldx     #0
@r:     cpy     z:mq
        bcs     @re
        lda     [lp],y
        and     #$00FF
        cmp     #' '
        beq     :+
        cmp     z:mc
        bne     @rno
        inx
:       iny
        bra     @r
@re:    ply
        cpx     #3
        bcc     @list
        lda     #B_RULE
        sta     m_blk
        lda     llen
        sta     m_pfx
        rts
@rno:   ply
        bra     @list
@hd:    cmp     #'#'
        bne     @quo
        ldx     #0                      ; # ## ###, then a space or the end
:       cpy     z:mq
        bcs     :+
        lda     [lp],y
        and     #$00FF
        cmp     #'#'
        bne     :+
        inx
        iny
        bra     :-
:       cpx     #4
        jcs     @para
        cpy     z:mq
        bcs     :+
        cmp     #' '
        jne     @para
        iny
:       stx     m_blk                   ; (B_H1 .. B_H3 = 1 .. 3)
        brl     @pfx
@quo:   cmp     #'>'
        bne     @list
        iny
        lda     #B_QUO
        sta     m_blk
        cpy     z:mq
        jcs     @pfx
        lda     [lp],y
        and     #$00FF
        cmp     #' '
        jne     @pfx
        iny
        bra     @pfx
@list:  lda     z:mc                    ; - * + and a space
        cmp     #'-'
        beq     :+
        cmp     #'*'
        beq     :+
        cmp     #'+'
        bne     @num
:       iny
        cpy     z:mq
        bcs     @para
        lda     [lp],y
        and     #$00FF
        cmp     #' '
        bne     @para
        iny
        lda     #B_BUL
        bra     @lvl
@num:   ldx     #0                      ; 1-9 digits, . or ), a space
:       cpy     z:mq
        bcs     @para
        lda     [lp],y
        and     #$00FF
        cmp     #'0'
        bcc     :+
        cmp     #'9' + 1
        bcs     :+
        inx
        iny
        bra     :-
:       cpx     #0
        beq     @para
        cpx     #10
        bcs     @para
        cmp     #'.'
        beq     :+
        cmp     #')'
        bne     @para
:       iny
        cpy     z:mq
        bcs     @para
        lda     [lp],y
        and     #$00FF
        cmp     #' '
        bne     @para
        iny
        lda     #B_NUM
@lvl:   sta     m_blk
        lda     m_ind                   ; level: (indent + 2) / 4, at most 3
        clc
        adc     #2
        lsr     a
        lsr     a
        cmp     #4
        bcc     :+
        lda     #3
:       sta     m_lvl
@pfx:   tya
        sec
        sbc     #4
        sta     m_pfx
        rts
@para:  stz     m_blk                   ; (B_PARA)
        stz     m_pfx
        rts
@blank: lda     #B_BLANK
        sta     m_blk
        rts

; line A: its block marker's length if it is hidden (the cursor cannot go there), else 0
hidpfx: jsr     lget
        lda     showmk
        bne     @no
        jsr     md_block
        lda     m_blk
        beq     @no
        cmp     #B_RULE
        bcs     @no
        lda     m_pfx
        rts
@no:    lda     #0
        rts

; line A: how it is laid out: RVI (the cursor's line), RVI | RVP (Show markup), or 0
rvflags:
        ldx     showmk
        beq     :+
        lda     #RVI | RVP
        rts
:       cmp     rv_l
        bne     :+
        lda     #RVI
        rts
:       lda     #0
        rts

; ---------------------------------------------------------------- the line model
; A = line -> lp, llen; the model of that line (kept until the line or the view changes)
lmodel: sta     ml_want
        jsr     lget
        lda     ml_want
        jsr     rvflags
        sta     ml_f
        lda     ml_want
        cmp     ml_line
        bne     :+
        lda     ml_f
        cmp     ml_rvf
        bne     :+
        rts
:       lda     ml_want
        sta     ml_line
        lda     ml_f
        sta     ml_rvf
        jsr     md_block
        lda     m_blk                   ; the shown parts: a rule shows itself on the
        cmp     #B_RULE                 ; cursor's line
        bne     :+
        lda     ml_f
        beq     :+
        lda     #RVI | RVP
        sta     ml_f
:       jsr     md_inline
        jsr     md_adv
        ; fall through
; the rows' start x (m_cx: the first, m_hx: the others) and the base face (m_face)
md_geom:
        stz     m_cx
        stz     m_hx
        ldx     m_blk
        lda     blkface,x
        and     #$00FF
        sta     m_face
        txa
        cmp     #B_BUL
        bcc     @out
        cmp     #B_RULE
        bcs     @out
        lda     ml_f                    ; a list or a quote: the marker in the flow, the
        and     #RVP                    ; other rows under the text
        beq     @hid
        lda     m_pfx
        jsr     advsum
        sta     m_hx
@out:   rts
@hid:   lda     m_blk
        cmp     #B_QUO
        bne     :+
        lda     #QIND
        bra     :++
:       lda     m_lvl                   ; lvl * LIND + GUT
        asl     a
        sta     z:t0
        asl     a
        asl     a
        asl     a
        clc
        adc     z:t0
        adc     #GUT
:       sta     m_cx
        sta     m_hx
        rts

; the advances of columns 0 .. A - 1 summed -> A
advsum: clc
        adc     #4
        sta     z:mq
        lda     #0
        ldy     #4
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

; the styles: st (MB at 4 + column) for line lp
md_inline:
        lda     llen
        clc
        adc     #4
        sta     z:mq                    ; the end (as an index)
        lda     m_pfx
        clc
        adc     #4
        sta     z:mp                    ; the text after the block marker
        ldy     #4
        sep     #$20
        .a8
:       cpy     z:mq                    ; the block marker S_P, the rest 0
        bcs     :++
        lda     #S_P
        cpy     z:mp
        bcc     :+
        lda     #0
:       sta     [mb],y
        iny
        bra     :--
:       rep     #$20
        .a16
        lda     m_blk
        cmp     #B_RULE
        bcc     :+
        rts
:       stz     dn
        ldy     z:mp
@scan:  sep     #$20                    ; (on over the characters that mean nothing)
        .a8
:       cpy     z:mq
        bcs     :+
        lda     [lp],y
        cmp     #'*'
        beq     :+
        cmp     #'`'
        beq     :+
        cmp     #$5C
        beq     :+
        iny
        bra     :-
:       rep     #$20
        .a16
        cpy     z:mq
        jcs     @emph
        lda     [lp],y
        and     #$00FF
        cmp     #$5C                    ; \ before punctuation: hidden, the next is literal
        bne     @nesc
        iny
        cpy     z:mq
        bcs     @scan
        lda     [lp],y
        jsr     chkind
        cmp     #1
        bne     @scan
        dey
        lda     #S_M
        jsr     @set
        iny
        iny
        bra     @scan
@nesc:  cmp     #'`'
        jne     @nbt
        jsr     @run                    ; a code span: a run of n `, to the next run of n
        sty     md_a
        stx     md_n
        tya
        clc
        adc     md_n
        tay
@bs:    cpy     z:mq                    ; (Y: after the opening run)
        bcs     @bnot
        lda     [lp],y
        and     #$00FF
        cmp     #'`'
        beq     :+
        iny
        bra     @bs
:       sty     md_b
        jsr     @run
        cpx     md_n
        beq     @bok
        tya                             ; another length: on after it
        clc
        adc     z:t0
        tay
        bra     @bs
@bnot:  lda     md_a                    ; no end: literal
        clc
        adc     md_n
        tay
        jmp     @scan
@bok:   ldy     md_a                    ; markers, code, markers
        ldx     md_n
:       lda     #S_M
        jsr     @set
        iny
        dex
        bne     :-
:       cpy     md_b
        bcs     :+
        lda     #S_C
        jsr     @set
        iny
        bra     :-
:       ldx     md_n
:       lda     #S_M
        jsr     @set
        iny
        dex
        bne     :-
        jmp     @scan
@nbt:   cmp     #'*'
        beq     :+
        iny
        jmp     @scan
:       jsr     @run                    ; a run of * : a delimiter
        lda     dn
        cmp     #MAXD * 2
        bcs     @skip
        tax
        tya
        sta     d_pos,x
        lda     z:t0
        sta     d_len,x
        sta     d_cnt,x
        stz     d_fl,x
        lda     #' '                    ; the characters around it
        cpy     z:mp
        beq     :+
        dey
        lda     [lp],y
        iny
:       jsr     chkind
        sta     md_pk                   ; 0 space, 1 punctuation, 2 other
        tya
        clc
        adc     z:t0
        tay
        lda     #' '
        cpy     z:mq
        bcs     :+
        lda     [lp],y
:       jsr     chkind
        sta     md_nk
        ldx     dn
        lda     md_nk                   ; left-flanking: can open
        beq     @rf
        cmp     #1
        bne     :+
        lda     md_pk
        cmp     #2
        beq     @rf
:       lda     #1
        sta     d_fl,x
@rf:    lda     md_pk                   ; right-flanking: can close
        beq     :++
        cmp     #1
        bne     :+
        lda     md_nk
        cmp     #2
        beq     :++
:       lda     d_fl,x
        ora     #2
        sta     d_fl,x
:       inx
        inx
        stx     dn
        jmp     @scan
@skip:  tya
        clc
        adc     z:t0
        tay
        jmp     @scan
; the run of the character at Y -> X = z:t0 = its length (Y kept)
@run:   sta     z:t1
        phy
        ldx     #0
:       cpy     z:mq
        bcs     :+
        lda     [lp],y
        and     #$00FF
        cmp     z:t1
        bne     :+
        inx
        iny
        bra     :-
:       ply
        stx     z:t0
        rts
; style bits A set at Y (A, X, Y kept)
@set:   sep     #$20
        .a8
        ora     [mb],y
        sta     [mb],y
        rep     #$20
        .a16
        rts
; emphasis: CommonMark's delimiter matching (no "_"), each closer with the nearest
; opener before it
@emph:  ldx     #0
@k:     cpx     dn
        bcc     :+
        rts
:       lda     d_fl,x
        and     #2
        jeq     @kn
@kc:    lda     d_cnt,x
        jeq     @kn
        stx     md_k                    ; an opener for it?
        txy
@o:     dey
        dey
        bpl     @o1
        jmp     @kn
@o1:    lda     d_fl,y
        and     #1
        beq     @o
        lda     d_cnt,y
        beq     @o
        lda     d_fl,y                  ; the rule of 3
        and     #2
        bne     :+
        lda     d_fl,x
        and     #1
        beq     @ok
:       lda     d_len,y
        clc
        adc     d_len,x
        jsr     mod3
        bne     @ok
        lda     d_len,y
        jsr     mod3
        bne     @o
        lda     d_len,x
        jsr     mod3
        bne     @o
@ok:    sty     md_o
        lda     #1                      ; strong (2) or emphasis (1)
        sta     md_use
        lda     d_cnt,y
        cmp     #2
        bcc     :+
        lda     d_cnt,x
        cmp     #2
        bcc     :+
        inc     md_use
:       lda     d_pos,y                 ; the text: opener's end .. closer's start
        clc
        adc     d_cnt,y
        sta     md_a
        sec
        sbc     md_use
        sta     md_c                    ; (the opener's markers from here)
        lda     d_len,x
        sec
        sbc     d_cnt,x
        clc
        adc     d_pos,x
        sta     md_b
        lda     #S_I
        ldy     md_use
        cpy     #2
        bne     :+
        lda     #S_B
:       sta     md_bit
        ldy     md_a
:       cpy     md_b
        bcs     :+
        lda     md_bit
        jsr     @set
        iny
        bra     :-
:       ldy     md_c                    ; the markers: the opener's last, the closer's first
        ldx     md_use
:       lda     #S_M
        jsr     @set
        iny
        dex
        bne     :-
        ldy     md_b
        ldx     md_use
:       lda     #S_M
        jsr     @set
        iny
        dex
        bne     :-
        ldx     md_k                    ; the counts; the openers between are spent
        ldy     md_o
        lda     d_cnt,y
        sec
        sbc     md_use
        sta     d_cnt,y
        lda     d_cnt,x
        sec
        sbc     md_use
        sta     d_cnt,x
:       iny
        iny
        sty     z:t0
        cpx     z:t0
        beq     :+
        lda     #0
        sta     d_cnt,y
        bra     :-
:       jmp     @kc
@kn:    inx
        inx
        jmp     @k

; A mod 3 -> A (Z set: 0)
mod3:   cmp     #3
        bcc     :+
        sbc     #3
        bra     mod3
:       cmp     #0
        rts

; character A (low byte): 0 space or tab (or none), 1 ASCII punctuation, 2 other
chkind: and     #$00FF
        cmp     #' ' + 1
        bcc     @sp
        cmp     #'0'
        bcc     @p
        cmp     #'9' + 1
        bcc     @o
        cmp     #'A'
        bcc     @p
        cmp     #'Z' + 1
        bcc     @o
        cmp     #'a'
        bcc     @p
        cmp     #'z' + 1
        bcc     @o
        cmp     #127
        bcc     @p
@o:     lda     #2
        rts
@p:     lda     #1
        rts
@sp:    lda     #0
        rts

; the advances (MB at $4004 + column) and S_H for what is not shown (ml_f), from ta_all
; (each face's advance by character, wf_init); 8-bit A with B = the base face's table
md_adv: ldx     m_blk
        lda     blkface,x
        and     #$00FF
        sta     m_face
        lsr     a                       ; (its table: B; bold's)
        sta     z:mf
        lda     m_face
        bne     :+
        lda     #F_BB
:       lsr     a
        sta     z:mf+1
        lda     #S_M | S_P              ; the markers hidden
        sta     z:mh
        lda     ml_f
        lsr     a
        bcc     :+
        lda     #S_M
        trb     z:mh
:       lda     ml_f
        and     #RVP
        beq     :+
        lda     #S_P
        trb     z:mh
:       lda     llen
        clc
        adc     #4
        sta     z:mq
        ldy     #4
        lda     z:mf
        xba
        and     #$FF00
        sep     #$20
        .a8
@l:     cpy     z:mq
        bcs     @out
        lda     [mb],y
        bit     z:mh
        bne     @hide
        bit     #S_C | S_B
        bne     @sty
        lda     [lp],y
        tax
        lda     ta_all,x
@w:     sta     [ma],y
        iny
        bra     @l
@sty:   bit     #S_C
        bne     :+
        lda     z:mf+1                  ; (B: bold's table, then the base face's again)
        bra     :++
:       lda     #F_F / 2
:       xba
        lda     [lp],y
        tax
        lda     z:mf
        xba
        lda     ta_all,x
        bra     @w
@hide:  ora     #S_H
        sta     [mb],y
        lda     #0
        bra     @w
@out:   rep     #$20
        .a16
        rts

; style byte A (low byte) -> A = the face (F_*) of the line now modelled
faceof: bit     #S_C
        beq     :+
        lda     #F_F
        rts
:       and     #S_B
        beq     :+
        lda     m_face
        bne     :++
        lda     #F_BB
        rts
:       lda     m_face
:       rts

; character A (low byte) -> A = its glyph index (0 .. 94; others '?')
glyphc: and     #$00FF
        cmp     #' '
        bcc     :+
        cmp     #127
        bcs     :+
        sec
        sbc     #' '
        rts
:       lda     #'?' - ' '
        rts

; ---------------------------------------------------------------- the type faces
; their bitmaps unpacked into VB at WFO (wf_lz: LZSS, see tools/mkwfont.py), each glyph's
; place there (fd_off's tables), gb's bank (plotg)
wf_init:
        stz     z:lzd
        lda     vbank
        sta     z:lzd+2
        sta     z:gb+2
        ldx     #.loword(wf_lz)
        ldy     #WFO
@grp:   cpy     #WFO + WF_SIZE
        bcs     @offs
        lda     a:0,x                   ; 8 flags (bit 0 first: 1 a byte, 0 a match)
        inx
        and     #$00FF
        sta     z:lzf
        lda     #8
        sta     z:lzn
@item:  cpy     #WFO + WF_SIZE
        bcs     @offs
        lsr     z:lzf
        bcc     @match
        lda     a:0,x
        inx
        sep     #$20
        .a8
        sta     [lzd],y
        rep     #$20
        .a16
        iny
        bra     @next
@match: lda     a:0,x                   ; the distance back, the length - 3
        inx
        inx
        pha
        and     #$0FFF
        sta     z:lzo
        pla
        xba
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        and     #$000F
        clc
        adc     #3
        sta     z:lzl
        lda     #0                      ; (lzs + Y = what was unpacked lzo bytes before)
        sec
        sbc     z:lzo
        sta     z:lzs
        lda     vbank
        sbc     #0
        sta     z:lzs+2
        sep     #$20
        .a8
:       lda     [lzs],y
        sta     [lzd],y
        iny
        dec     z:lzl
        bne     :-
        rep     #$20
        .a16
@next:  dec     z:lzn
        bne     @item
        bra     @grp
@offs:  ldx     #0                      ; each face's advances by character (ta_all)
        stz     z:t2
@af:    lda     fd_adv,x
        sta     z:t0
        ldy     #0
:       tya
        cmp     #9
        bne     :+
        lda     #TABW
        bra     @as
:       jsr     glyphc
        phy
        tay
        lda     (t0),y
        ply
@as:    phx
        tyx
        pha
        txa
        clc
        adc     z:t2
        tax
        pla
        sep     #$20
        .a8
        sta     ta_all,x
        rep     #$20
        .a16
        plx
        iny
        cpy     #256
        bcc     :--
        lda     z:t2
        clc
        adc     #256
        sta     z:t2
        inx
        inx
        cpx     #5 * 2
        bcc     @af
        ldx     #0                      ; the glyphs' places
@f:     lda     fd_off,x
        sta     z:t0
        lda     fd_rows,x               ; (a glyph's bytes: rows * bytes a row)
        ldy     fd_bpr,x
        cpy     #2
        bne     :+
        asl     a
:       sta     z:t1
        lda     fd_bmo,x
        clc
        adc     #WFO
        ldy     #0
:       sta     (t0),y
        clc
        adc     z:t1
        iny
        iny
        cpy     #95 * 2
        bcc     :-
        inx
        inx
        cpx     #5 * 2
        bcc     @f
        rts

; ---------------------------------------------------------------- the line cache
; empty (the view changed)
lc_flush:
        inc     ed_cnt
        ldx     #0
        lda     #NONE
:       sta     lc_line,x
        inx
        inx
        cpx     #LCN * 2
        bcc     :-
        sta     ml_line
        stz     mt_ok
        rts

; line A changed from column X on: its rows are laid out again from the one before the
; row of that column (those before it stay)
lc_chg: stx     lc_cc
        ldx     #NONE
        stx     ml_line
        inc     ed_cnt
        cmp     mt_line
        bcc     :+
        stz     mt_ok
:
        ldx     #0
:       cmp     lc_line,x
        bne     :++
        pha
        lda     lc_cc
        cmp     lc_vc,x
        bcs     :+
        sta     lc_vc,x
:       pla
:       inx
        inx
        cpx     #LCN * 2
        bcc     :---
        rts

; a line was inserted at A: the lines from A on are one further (cache, rows drawn, marks)
lc_ins: ldx     #NONE
        stx     ml_line
        inc     ed_cnt
        ldx     loadng
        bne     @out
        sta     z:t0
        ldx     #0
:       lda     lc_line,x
        cmp     #NONE
        beq     :+
        cmp     z:t0
        bcc     :+
        inc     lc_line,x
:       inx
        inx
        cpx     #LCN * 2
        bcc     :--
        ldx     #0
:       lda     dr_l,x
        cmp     #$FFFE
        bcs     :+
        cmp     z:t0
        bcc     :+
        inc     dr_l,x
:       inx
        inx
        cpx     #MAXROWS * 2
        bcc     :--
        ldx     #0
:       cpx     mk_n
        bcs     :+++
        lda     mk_l0,x
        cmp     z:t0
        bcc     :+
        inc     mk_l0,x
:       lda     mk_l1,x
        cmp     z:t0
        bcc     :+
        inc     mk_l1,x
:       inx
        inx
        bra     :---
:       lda     dr_rv
        cmp     z:t0
        bcc     @out
        inc     dr_rv
@out:   rts

; X lines deleted at A
lc_del: ldy     #NONE
        sty     ml_line
        inc     ed_cnt
        sta     z:t0                    ; [t0, t1) go, from t1 on: - X
        stx     z:t2
        clc
        adc     z:t2
        sta     z:t1
        ldx     #0
@c:     lda     lc_line,x
        jsr     @map
        sta     lc_line,x
        inx
        inx
        cpx     #LCN * 2
        bcc     @c
        ldx     #0
@d:     lda     dr_l,x
        cmp     #$FFFE
        bcs     :+
        jsr     @map
        cmp     #NONE
        bne     :+
        lda     #$FFFE
:       sta     dr_l,x
        inx
        inx
        cpx     #MAXROWS * 2
        bcc     @d
        ldx     #0
@m:     cpx     mk_n
        bcs     :+
        lda     mk_l0,x
        jsr     @mapk
        sta     mk_l0,x
        lda     mk_l1,x
        jsr     @mapk
        sta     mk_l1,x
        inx
        inx
        bra     @m
:       lda     dr_rv
        jsr     @mapk
        sta     dr_rv
        rts
; line A -> its number now (NONE: gone)
@map:   cmp     #NONE
        beq     :+
        cmp     z:t0
        bcc     :+
        cmp     z:t1
        bcc     @gone
        sec
        sbc     z:t2
:       rts
@gone:  lda     #NONE
        rts
; (marks: a line gone becomes the first one after)
@mapk:  cmp     z:t0
        bcc     :+
        cmp     z:t1
        bcc     @k0
        sec
        sbc     z:t2
:       rts
@k0:    lda     z:t0
        rts

; A = line -> lp, llen, lcx (its cache entry * 2), lc_blk..: its rows are known
lrows:  sta     lr_l
        jsr     lget
        lda     lr_l
        jsr     rvflags
        sta     lr_f
        lda     lr_l                    ; (the entry this line had last)
        and     #LCN - 1
        asl     a
        tay
        ldx     lc_hint,y
        cpx     #LCN * 2
        bcs     :+
        lda     lc_line,x
        cmp     lr_l
        beq     @fnd
:       ldx     #0
@f:     lda     lc_line,x
        cmp     lr_l
        bne     :+
@fnd:   lda     lc_rvf,x
        cmp     lr_f
        bne     @fill
        lda     lc_vc,x
        cmp     #NONE
        jeq     @hit
        jmp     @part
:       inx
        inx
        cpx     #LCN * 2
        bcc     @f
        ldx     lc_next                 ; a new entry (in turn)
        inx
        inx
        cpx     #LCN * 2
        bcc     :+
        ldx     #0
:       stx     lc_next
@fill:  stx     lcx
        lda     #NONE
        sta     lc_line,x
        jsr     @hint
        lda     lr_l
        jsr     lmodel
@fill2: ldx     lcx
        lda     m_blk
        sta     lc_blk,x
        jsr     lc_rowp                 ; its row starts
        stx     lr_p
        stz     lr_n
        lda     #0
@r:     sta     lr_s
        ldx     lr_n
        cpx     #LCK
        bcs     :+
        txa
        asl     a
        clc
        adc     lr_p
        tay
        lda     lr_s
        sta     a:0,y
:       inc     lr_n
        lda     lr_s
        jsr     rowend_m
        cmp     llen
        bcc     @r
        ldx     lcx
        lda     lr_n
        sta     lc_n,x
        lda     lr_l
        sta     lc_line,x
        lda     lr_f
        sta     lc_rvf,x
        lda     #NONE
        sta     lc_vc,x
        rts
@part:  stx     lcx                     ; changed from column lc_vc on: the row starts up
        jsr     @hint                   ; to the row before its row stay
        lda     lr_l
        jsr     lmodel
        ldx     lcx
        lda     m_blk
        cmp     lc_blk,x
        bne     @fill2
        lda     lc_n,x
        cmp     #LCK + 1
        bcc     :+
        lda     #LCK
:       sta     z:t2                    ; (the starts known)
        lda     lc_vc,x
        sta     z:t3
        jsr     lc_rowp
        stx     lr_p
        stx     z:t1
        ldy     #2                      ; the last start <= the column, then one back
        ldx     #1
:       cpx     z:t2
        bcs     :++
        lda     (t1),y
        cmp     z:t3
        beq     :+
        bcs     :++
:       iny
        iny
        inx
        cpx     z:t2
        bcc     :--
:       dex                             ; (X: the row after it -> its row)
        stx     lr_n
        txa                             ; a space in it before the column: the row
        asl     a                       ; before stays too (its first word did not
        tay                             ; change: nothing comes up from it)
        lda     (t1),y
        clc
        adc     #4
        tay
        lda     z:t3
        clc
        adc     #4
        sta     z:t3
:       cpy     z:t3
        bcs     :+
        lda     [lp],y
        and     #$00FF
        cmp     #' ' + 1
        bcc     :++
        iny
        bra     :-
:       dex                             ; (else the row before it, at least 0)
        bpl     :+
        ldx     #0
:       stx     lr_n
        txa
        asl     a
        tay
        lda     (t1),y
        jmp     @r
@hit:   stx     lcx
        lda     lc_blk,x
        sta     m_blk
@hint:  lda     lr_l                    ; (its entry, to find it at once next time)
        and     #LCN - 1
        asl     a
        tay
        txa
        sta     lc_hint,y
        rts

; the row starts of entry lcx -> X = their address (in our bank)
lc_rowp:
        lda     lcx                     ; (lcx * LCK)
        .assert LCK = 16, error, "lc_rowp"
        asl     a
        asl     a
        asl     a
        asl     a
        adc     #.loword(lc_st)
        tax
        rts

; ---------------------------------------------------------------- rows
; (lrows first) the end of the row of line lnum starting at column A -> A
rowend: sta     re_s
        jsr     lc_rowp
        stx     z:t1
        ldx     lcx
        lda     lc_n,x
        cmp     #LCK + 1
        bcc     :+
        lda     #LCK                    ; (only LCK known)
        sta     z:t2
        bra     :++
:       sta     z:t2
:       ldy     #0                      ; find the start
@f:     tya
        lsr     a
        cmp     z:t2
        bcs     @model
        lda     (t1),y
        cmp     re_s
        beq     @got
        iny
        iny
        bra     @f
@got:   iny
        iny
        tya
        lsr     a
        cmp     z:t2
        bcs     :+
        lda     (t1),y
        rts
:       ldx     lcx                     ; the last row: the line's end
        lda     lc_n,x
        cmp     #LCK + 1
        bcs     @model
        lda     llen
        rts
@model: lda     lnum                    ; (a row the cache does not hold)
        jsr     lmodel
        lda     re_s
        ; fall through
; the end of the row starting at column A, from the model: after the last space that
; fits the width (a space past the edge hangs there), else before the character that
; does not fit (at least one character a row)
rowend_m:
        sta     re_i
        sta     re_s
        lda     colw
        sec
        sbc     m_hx
        ldx     re_s
        bne     :+
        lda     colw
        sec
        sbc     m_cx
:       sta     re_w
        stz     re_x
        lda     #NONE
        sta     re_sp
        lda     re_i
        clc
        adc     #4
        tay
        lda     llen
        clc
        adc     #4
        sta     z:mq
@l:     cpy     z:mq
        bcc     :+
        lda     llen
        rts
:       lda     [ma],y
        and     #$00FF
        clc
        adc     re_x
        cmp     re_w
        beq     @fit
        bcc     @fit
        lda     [lp],y                  ; it does not fit
        and     #$00FF
        cmp     #' '
        beq     @hang
        cmp     #9
        beq     @hang
        lda     re_sp
        cmp     #NONE
        beq     :+
        inc     a
        rts
:       tya
        sec
        sbc     #4
        cmp     re_s
        bne     :+
        inc     a
:       rts
@hang:  tya
        sec
        sbc     #3
        rts
@fit:   sta     re_x
        lda     [lp],y
        and     #$00FF
        cmp     #' '
        beq     :+
        cmp     #9
        bne     :++
:       tya
        sec
        sbc     #4
        sta     re_sp
:       iny
        bra     @l

; (lrows first) column A -> its row rw_s .. rw_e (a column at a wrapped row's end belongs
; to the next row)
rowof:  sta     ro_c
        jsr     lc_rowp
        stx     z:t1
        ldx     lcx
        lda     lc_n,x
        sta     z:t2
        cmp     #LCK + 1
        bcc     :+
        lda     #LCK
:       sta     z:t3                    ; known
        ldy     #0
@l:     iny                             ; the next start <= c: on
        iny
        tya
        lsr     a
        cmp     z:t3
        bcs     @last
        lda     (t1),y
        cmp     ro_c
        beq     @l
        bcc     @l
        dey                             ; this row
        dey
        lda     (t1),y
        sta     rw_s
        iny
        iny
        lda     (t1),y
        sta     rw_e
        rts
@last:  dey
        dey
        lda     (t1),y
        sta     rw_s
        lda     z:t2                    ; all known: the last row
        cmp     #LCK + 1
        bcs     @walk
        lda     llen
        sta     rw_e
        rts
@walk:  lda     lnum                    ; past what the cache holds: walk on
        jsr     lmodel
@w:     lda     rw_s
        jsr     rowend_m
        sta     rw_e
        cmp     llen
        bcs     @out
        cmp     ro_c
        beq     :+
        bcs     @out
:       lda     rw_e
        sta     rw_s
        bra     @w
@out:   rts

; the x of column A in row rw_s .. rw_e of line lnum (from the text column's left) -> wx
wstopat:
        sta     ws_c
        lda     lnum
        jsr     lmodel
        lda     m_hx
        ldx     rw_s
        bne     :+
        lda     m_cx
:       sta     wx
        lda     ws_c
        cmp     rw_e
        bcc     :+
        lda     rw_e
:       clc
        adc     #4
        sta     z:mq
        lda     rw_s
        clc
        adc     #4
        tay
        lda     wx
:       cpy     z:mq
        bcs     :+
        sta     z:mc
        lda     [ma],y
        and     #$00FF
        clc
        adc     z:mc
        iny
        bra     :-
:       sta     wx
        rts

; the column of row rw_s .. rw_e of line lnum nearest pixel A (from the text column's
; left, signed) -> A
whitat: sta     wpx
        lda     lnum
        jsr     lmodel
        lda     m_hx
        ldx     rw_s
        bne     :+
        lda     m_cx
:       sta     wx
        lda     rw_e
        clc
        adc     #4
        sta     z:mq
        lda     rw_s
        clc
        adc     #4
        tay
@l:     cpy     z:mq
        bcs     @end
        lda     [ma],y
        and     #$00FF
        sta     z:mc
        lsr     a
        clc
        adc     wx
        sta     z:t0
        lda     wpx
        bmi     @hit
        cmp     z:t0
        bcc     @hit
        lda     wx
        clc
        adc     z:mc
        sta     wx
        iny
        bra     @l
@hit:   tya
        sec
        sbc     #4
        rts
@end:   lda     rw_e
        rts

        .segment "RODATA"
; the base face of each block
blkface: .byte  F_B, F_H1, F_H2, F_BB, F_B, F_B, F_B, F_B, F_B
; the type faces
fd_rows: .word  FB_ROWS, FBB_ROWS, FF_ROWS, FH1_ROWS, FH2_ROWS
fd_bpr: .word   FB_BPR, FBB_BPR, FF_BPR, FH1_BPR, FH2_BPR
fd_base: .word  FB_BASE, FBB_BASE, FF_BASE, FH1_BASE, FH2_BASE
fd_adv: .addr   FB_adv, FBB_adv, FF_adv, FH1_adv, FH2_adv
fd_off: .addr   fo_b, fo_bb, fo_f, fo_h1, fo_h2
fd_ish: .addr   FB_ish, FBB_ish, FF_ish, FH1_ish, FH2_ish
fd_bmo: .word   FB_BMO, FBB_BMO, FF_BMO, FH1_BMO, FH2_BMO
        .include "wfont.inc"

        .segment "BSS"
ta_all: .res    5 * 256                 ; each face's advance by character (wf_init)
fo_b:   .res    95 * 2                  ; each glyph's bitmap in VB (wf_init)
fo_bb:  .res    95 * 2
fo_f:   .res    95 * 2
fo_h1:  .res    95 * 2
fo_h2:  .res    95 * 2
m_blk:  .res    2                       ; the block of the line md_block read last
m_pfx:  .res    2
m_lvl:  .res    2
m_ind:  .res    2
m_cx:   .res    2                       ; the model: the rows' start x, the base face
m_hx:   .res    2
m_face: .res    2
ml_line: .res   2                       ; the line modelled (NONE: none)
ml_rvf: .res    2
ml_want: .res   2
ml_f:   .res    2
dn:     .res    2                       ; delimiter runs * 2
d_pos:  .res    MAXD * 2
d_len:  .res    MAXD * 2
d_cnt:  .res    MAXD * 2
d_fl:   .res    MAXD * 2                ; bit 0 can open, bit 1 can close
md_a:   .res    2
md_b:   .res    2
md_c:   .res    2
md_n:   .res    2
md_k:   .res    2
md_o:   .res    2
md_use: .res    2
md_bit: .res    2
md_pk:  .res    2
md_nk:  .res    2
lc_line: .res   LCN * 2                 ; the line cache
lc_rvf: .res    LCN * 2
lc_blk: .res    LCN * 2
lc_n:   .res    LCN * 2
lc_st:  .res    LCN * LCK * 2
lc_next: .res   2
lc_hint: .res   LCN * 2
lc_vc:  .res    LCN * 2                 ; changed from this column on (NONE: not)
lc_cc:  .res    2
ed_cnt: .res    2                       ; + 1 at every change of the text or the view
lcx:    .res    2
lr_l:   .res    2
lr_f:   .res    2
lr_p:   .res    2
lr_n:   .res    2
lr_s:   .res    2
re_i:   .res    2
re_s:   .res    2
re_x:   .res    2
re_w:   .res    2
re_sp:  .res    2
ro_c:   .res    2
rw_s:   .res    2
rw_e:   .res    2
ws_c:   .res    2
wx:     .res    2
wpx:    .res    2

        .segment "ZEROPAGE"
ma:     .res    4                       ; the advances (mb + $4000)
mf:     .res    2                       ; md_adv: the faces' tables, the markers hidden
mh:     .res    2
lzd:    .res    4                       ; wf_init
lzs:    .res    4
lzf:    .res    2
lzn:    .res    2
lzo:    .res    2
lzl:    .res    2
mq:     .res    2
mp:     .res    2
mc:     .res    2
