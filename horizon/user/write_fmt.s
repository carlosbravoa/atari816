; write_fmt.s - Write: formatting (part of write.s). Every command inserts or removes
; Markdown markers through inst and delsel, so it is one undo step and the rest of the
; text is not touched.
;
; Inline (Bold ctrl-B "**", Italic ctrl-I "*", Code ctrl-E "`"): on the selection, line by
; line (each line's part gets its own markers; spaces at its ends stay outside). Already
; marked (markers just around it, or at its ends): the markers go. No selection: the word
; at the cursor; at no word, the two markers with the cursor between them.
; Blocks (Heading 1-3 ctrl-1..3, Normal ctrl-0, Bullets, Numbers, Quote): the block
; marker of each line of the selection (or the cursor's line) is replaced; when all the
; lines already are of that kind, it goes (Normal). Numbers count on from a numbered
; item just above.
; Enter in a list item or a quote starts the next one (the next number; the numbers
; after it are counted on); Enter on an empty item ends the list: the item becomes a blank
; line and the cursor goes to a new one after it (a nested item moves out one level). Tab / Shift-Tab: list items in or out a level (4 spaces). Backspace at
; the start of an item's or a heading's text removes its marker.

        .segment "CODE"

f_bold: ldy     #0
        bra     f_inl
f_ital: ldy     #2
        bra     f_inl
f_code: ldy     #4
f_inl:  tya
        lsr     a
        sta     fm_kind
        lda     fmk_tab,y
        sta     fm_mk
        lda     fmk_len,y
        sta     fm_n
        lda     fmk_sbit,y
        sta     fm_sbit
        ldx     fm_mk
        lda     a:0,x
        and     #$00FF
        sta     fm_ch
        stz     fm_rm
        jsr     fm_save
        jsr     selord
        jcs     @sel
        lda     arm_n                   ; armed at the cursor: this style out, or in too
        jne     @arm
        jsr     fm_exit                 ; at the end of a span of this style: out of it
        jcs     fm_done
        lda     cl                      ; no selection: the word at the cursor
        jsr     lget
        lda     cc
        sta     fm_b
        sta     fm_a
:       lda     fm_a                    ; back over word characters
        beq     :+
        dec     a
        jsr     chclass
        cmp     #1
        bne     :+
        dec     fm_a
        bra     :-
:       lda     fm_b
        cmp     llen
        bcs     :+
        jsr     chclass
        cmp     #1
        bne     :+
        inc     fm_b
        bra     :-
:       lda     fm_a
        cmp     fm_b
        bne     @word
@arm:   jsr     arm_tog                 ; none: armed (two markers, the cursor between)
        jmp     fm_done
@word:  lda     cl
        sta     s0l
        sta     s1l
        lda     fm_a
        sta     s0c
        lda     fm_b
        sta     s1c
@sel:   lda     s0l                     ; add or remove: as the first line's part is
        sta     fm_sl
        lda     s1l
        sta     fm_el
        lda     s0c
        sta     fm_sc
        lda     s1c
        sta     fm_ec
        lda     fm_sl
        jsr     fm_part
        bcs     :+
        jsr     fm_has
        lda     #0
        rol     a
        sta     fm_rm
:       lda     fm_el                   ; each line's part, the last first (the columns
        sta     fm_l                    ; before stay)
@ln:    lda     fm_l
        jsr     fm_part
        jcs     @nx
        lda     fm_rm
        beq     @add
        jsr     fm_has
        jcc     @nx
        lda     fm_where                ; around it: the markers after, then before
        bne     @in
        lda     fm_b
        sta     fm_c
        jsr     fm_del
        lda     fm_a
        sec
        sbc     fm_n
        sta     fm_c
        jsr     fm_del
        lda     fm_l                    ; the ends move
        cmp     fm_sl
        bne     :+
        lda     fm_a
        sec
        sbc     fm_n
        sta     fm_sc
:       lda     fm_l
        cmp     fm_el
        bne     @nx
        lda     fm_b
        sec
        sbc     fm_n
        sta     fm_ec
        bra     @nx
@in:    lda     fm_b                    ; at its ends
        sec
        sbc     fm_n
        sta     fm_c
        jsr     fm_del
        lda     fm_a
        sta     fm_c
        jsr     fm_del
        lda     fm_l
        cmp     fm_el
        bne     @nx
        lda     fm_b
        sec
        sbc     fm_n
        sbc     fm_n
        sta     fm_ec
        bra     @nx
@add:   lda     fm_b
        sta     fm_c
        jsr     fm_ins
        lda     fm_a
        sta     fm_c
        jsr     fm_ins
        lda     fm_l
        cmp     fm_sl
        bne     :+
        lda     fm_a
        clc
        adc     fm_n
        sta     fm_sc
:       lda     fm_l
        cmp     fm_el
        bne     @nx
        lda     fm_b
        clc
        adc     fm_n
        sta     fm_ec
@nx:    lda     fm_l
        cmp     fm_sl
        beq     :+
        dec     fm_l
        brl     @ln
:       lda     fm_sl                   ; the text selected again (over several lines:
        cmp     fm_el                   ; with its markers, so the command undoes it)
        beq     @one
        lda     fm_rm
        bne     @one
        lda     fm_sc
        sec
        sbc     fm_n
        sta     fm_sc
        lda     fm_ec
        clc
        adc     fm_n
        sta     fm_ec
@one:   lda     fm_sl
        sta     al
        lda     fm_sc
        sta     ac
        lda     fm_el
        sta     cl
        lda     fm_ec
        sta     cc
        jmp     fm_done

; line A's part of the selection fm_sl:fm_sc .. fm_el:fm_ec without the spaces at its
; ends (and without a block marker) -> fm_a .. fm_b; C set: nothing there
fm_part:
        sta     fm_l
        jsr     lget
        jsr     md_block
        lda     m_pfx
        sta     fm_a
        lda     m_blk
        cmp     #B_RULE
        bcc     :+
        sec
        rts
:       lda     fm_l
        cmp     fm_sl
        bne     :+
        lda     fm_sc
        cmp     fm_a
        bcc     :+
        sta     fm_a
:       lda     llen
        sta     fm_b
        lda     fm_l
        cmp     fm_el
        bne     :+
        lda     fm_ec
        sta     fm_b
:       lda     fm_a                    ; spaces at the ends
        cmp     fm_b
        bcs     @none
        jsr     chclass
        bne     :+
        inc     fm_a
        bra     :-
:       lda     fm_b
        dec     a
        jsr     chclass
        bne     :+
        dec     fm_b
        bra     :-
:       clc
        rts
@none:  sec
        rts

; is fm_a .. fm_b of line fm_l (loaded) marked with fm_mk? -> C set; fm_where: 0 the
; markers are just around it, 1 at its ends
fm_has: stz     fm_where
        lda     fm_a                    ; around: the runs of the marker's character
        jsr     fm_runl
        sta     z:t2
        lda     fm_b
        jsr     fm_runr
        sta     z:t3
        jsr     fm_ok
        bcs     @yes
        inc     fm_where                ; at its ends (inside)
        lda     fm_b
        sec
        sbc     fm_a
        lsr     a
        cmp     fm_n
        bcc     @no
        lda     fm_a
        jsr     fm_runr
        sta     z:t2
        lda     fm_b
        jsr     fm_runl
        sta     z:t3
        jsr     fm_ok
        bcs     @yes
@no:    clc
        rts
@yes:   sec
        rts
; runs t2, t3 make the marker? (** both >= 2; * both odd; ` both >= 1) -> C set
fm_ok:  lda     fm_n
        cmp     #2
        bne     :+
        lda     z:t2
        cmp     #2
        bcc     @no
        lda     z:t3
        cmp     #2
        rts
:       lda     fm_ch
        cmp     #'*'
        bne     :+
        lda     z:t2
        and     z:t3
        lsr     a
        rts
:       lda     z:t2
        beq     @no
        lda     z:t3
        beq     @no
        sec
        rts
@no:    clc
        rts
; the run of the marker's character ending before column A -> A (at most 3)
fm_runl:
        sta     z:t0
        ldx     #0
:       lda     z:t0
        beq     :+
        dec     a
        sta     z:t0
        jsr     fm_isch
        bne     :+
        inx
        cpx     #3
        bcc     :-
:       txa
        rts
; the run starting at column A -> A (at most 3)
fm_runr:
        sta     z:t0
        ldx     #0
:       lda     z:t0
        cmp     llen
        bcs     :+
        jsr     fm_isch
        bne     :+
        inc     z:t0
        inx
        cpx     #3
        bcc     :-
:       txa
        rts
; column A of line lp the marker's character? -> Z set
fm_isch:
        clc
        adc     #4
        tay
        lda     [lp],y
        eor     fm_ch
        and     #$00FF
        rts

; the marker inserted at fm_l:fm_c (the cursor after it)
fm_ins: lda     fm_l
        sta     cl
        lda     fm_c
        sta     cc
        jsr     anchor0
        lda     fm_mk
        sta     isrc
        lda     #^fmk_b
        sta     isrc+2
        lda     fm_n
        jmp     inst
; the marker's length deleted at fm_l:fm_c
fm_del: lda     fm_l
        sta     cl
        sta     al
        lda     fm_c
        sta     ac
        clc
        adc     fm_n
        sta     cc
        jmp     delsel

; the cursor and the anchor kept (fm_save) and back (fm_rest)
fm_save:
        lda     cl
        sta     fm_cl
        lda     cc
        sta     fm_cc
        lda     al
        sta     fm_al
        lda     ac
        sta     fm_ac
        rts
fm_rest:
        lda     fm_cl
        sta     cl
        lda     fm_cc
        sta     cc
        lda     fm_al
        sta     al
        lda     fm_ac
        sta     ac
        rts

; no selection, the cursor at the end of a span of this style (just before its closing
; marker): the cursor goes past the markers (typing goes on outside it) -> C set
fm_exit:
        lda     cl
        jsr     lmodel
        lda     cc
        beq     @no
        cmp     llen
        bcs     @no
        clc
        adc     #3
        tay
        lda     [mb],y
        and     #$00FF
        bit     #S_M | S_P
        bne     @no
        and     fm_sbit
        beq     @no
        iny
        lda     [mb],y
        bit     #S_M
        beq     @no
        lda     [lp],y
        eor     fm_ch
        and     #$00FF
        bne     @no
:       iny                             ; over the markers
        tya
        sec
        sbc     #4
        cmp     llen
        bcs     :+
        lda     [mb],y
        bit     #S_M
        bne     :-
:       tya
        sec
        sbc     #4
        sta     cc
        jsr     anchor0
        sec
        rts
@no:    clc
        rts

; ---------------------------------------------------------------- styles armed
; Bold (Italic, Code) with no selection and no word at the cursor arms the style: its two
; markers go in with the cursor between them, so what is typed there has that style
; (another style armed there nests inside: "***" "***" for both; that style again takes
; its markers out). The toolbar and the menu show the styles armed. When the cursor leaves
; them empty (a move, a click, Backspace, any other command, a save), the markers go out
; again, and so do their undo records when nothing came after them.
; arm_n styles (arm_k: their kinds, outer first) at line arm_l, the left markers from
; column arm_c (arm_w long), the cursor after them; arm_txt: all the markers.

; fm_kind armed at the cursor (or out again when it is armed)
arm_tog:
        ldx     #0
:       cpx     arm_n
        bcs     @in
        lda     arm_k,x
        and     #$00FF
        cmp     fm_kind
        beq     arm_rm
        inx
        bra     :-
@in:    lda     arm_n
        cmp     #3
        bcs     @out
        tax
        bne     :+
        lda     cl                      ; (the first)
        sta     arm_l
        lda     cc
        sta     arm_c
        stz     arm_w
        lda     ub_top
        sta     arm_ub0
:       lda     cl                      ; the markers, the cursor between
        sta     fm_l
        lda     cc
        sta     fm_c
        jsr     fm_ins
        lda     cl
        sta     fm_l
        lda     cc
        sta     fm_c
        jsr     fm_ins
        lda     fm_c
        sta     cc
        jsr     anchor0
        ldx     arm_n
        lda     fm_kind
        sep     #$20
        .a8
        sta     arm_k,x
        rep     #$20
        .a16
        inc     arm_n
        lda     arm_w
        clc
        adc     fm_n
        sta     arm_w
        jsr     arm_mk
        lda     ub_top
        sta     arm_ubt
@out:   rts

; style X of those armed out (its two markers deleted); none left: as if never armed
arm_rm: stx     arm_i
        stz     z:t4                    ; the markers before it (left), after it (right)
        stz     z:t5
        ldx     #0
:       cpx     arm_n
        bcs     :+++
        jsr     @len
        cpx     arm_i
        beq     :++
        bcs     :+
        clc
        adc     z:t4
        sta     z:t4
        bra     :++
:       clc
        adc     z:t5
        sta     z:t5
:       inx
        bra     :---
:       lda     arm_l                   ; the right one, then the left one
        sta     fm_l
        lda     arm_c
        clc
        adc     arm_w
        adc     z:t5
        sta     fm_c
        jsr     fm_del
        lda     arm_c
        clc
        adc     z:t4
        sta     fm_c
        jsr     fm_del
        lda     arm_w
        sec
        sbc     fm_n
        sta     arm_w
        ldx     arm_i                   ; out of the list
:       inx
        cpx     arm_n
        bcs     :+
        lda     arm_k,x
        sep     #$20
        .a8
        sta     arm_k-1,x
        rep     #$20
        .a16
        bra     :-
:       dec     arm_n
        lda     arm_l
        sta     cl
        lda     arm_c
        clc
        adc     arm_w
        sta     cc
        jsr     anchor0
        jsr     arm_mk
        lda     ub_top
        sta     arm_ubt
        lda     arm_n
        bne     :+
        jsr     arm_pop
:       rts
; the length of style X's marker -> A
@len:   lda     arm_k,x
        and     #$00FF
        asl     a
        tay
        lda     fmk_len,y
        rts

; arm_txt (the markers: the left ones outer first, the right ones inner first), arm_bits
; (their toolbar buttons)
arm_mk: stz     arm_bits
        ldy     #0
        ldx     #0
@l:     cpx     arm_n
        bcs     @r
        jsr     @put
        inx
        bra     @l
@r:     dex
        bmi     @out
        jsr     @put
        bra     @r
@out:   rts
@put:   phx
        lda     arm_k,x
        and     #$00FF
        asl     a
        tax
        lda     fmk_bit,x
        tsb     arm_bits
        lda     fmk_len,x
        sta     z:t3
        lda     fmk_tab,x
        tax
:       lda     a:0,x
        sep     #$20
        .a8
        sta     arm_txt,y
        rep     #$20
        .a16
        inx
        iny
        dec     z:t3
        bne     :-
        plx
        rts

; are the markers armed still there? -> C set
arm_ok: lda     arm_l
        cmp     nl
        bcs     @no
        jsr     lget
        lda     arm_w
        asl     a
        sta     z:t0
        clc
        adc     arm_c
        cmp     llen
        beq     :+
        bcs     @no
:       ldx     #0
        lda     arm_c
        clc
        adc     #4
        tay
:       cpx     z:t0
        bcs     @yes
        lda     [lp],y
        eor     arm_txt,x
        and     #$00FF
        bne     @no
        inx
        iny
        bra     :-
@yes:   sec
        rts
@no:    clc
        rts

; after an action: the styles armed stay armed while the cursor is between their markers
arm_chk:
        lda     arm_n
        beq     @out
        jsr     arm_ok
        bcc     @clr
        jsr     selord
        bcs     arm_drop
        lda     cl
        cmp     arm_l
        bne     arm_drop
        lda     arm_c
        clc
        adc     arm_w
        cmp     cc
        bne     arm_drop
@out:   rts
@clr:   stz     arm_n
        rts

; the styles armed and left empty out: their markers deleted (and their undo records when
; nothing came after them); the cursor and the anchor follow -> C set: there were some
arm_drop:
        lda     arm_n
        beq     @no
        jsr     arm_ok
        bcc     @clr
        jsr     fm_save
        lda     ub_top
        cmp     arm_ubt
        bne     @rec
        stz     ub_rec                  ; (not recorded: the records of the arming go)
        jsr     @del
        lda     #1
        sta     ub_rec
        jsr     arm_pop
        bra     @fix
@rec:   jsr     @del
@fix:   ldx     #.loword(fm_cl)
        jsr     @mv
        ldx     #.loword(fm_al)
        jsr     @mv
        jsr     fm_rest
        stz     arm_n
        sec
        rts
@clr:   stz     arm_n
@no:    clc
        rts
@del:   lda     arm_l
        sta     al
        sta     cl
        lda     arm_c
        sta     ac
        clc
        adc     arm_w
        adc     arm_w
        sta     cc
        jmp     delsel
@mv:    lda     a:0,x                   ; (a place on that line after them: back)
        cmp     arm_l
        bne     @mo
        lda     arm_w
        asl     a
        adc     arm_c
        cmp     a:2,x
        bcs     :+
        lda     a:2,x
        sec
        sbc     arm_w
        sbc     arm_w
        sta     a:2,x
        rts
:       lda     arm_c
        cmp     a:2,x
        bcs     @mo
        sta     a:2,x
@mo:    rts

; the arming's undo records go, when they are the last ones (the text is as before it)
arm_pop:
        lda     ub_top
        cmp     arm_ubt
        bne     @out
        lda     arm_ub0
        cmp     ub_top
        beq     :+
        bcs     @out
:       sta     ub_top
        sta     ub_end
        lda     ub_save                 ; (saved in between: that state is gone)
        cmp     #NONE
        beq     :+
        cmp     ub_top
        beq     :+
        bcc     :+
        lda     #NONE
        sta     ub_save
:       lda     ub_top
        cmp     ub_save
        bne     @out
        lda     emod
        beq     @out
        stz     emod
        jmp     settitle
@out:   rts

; after a format command: the lines it touched are marked (by inst / delsel)
fm_done:
        jsr     clampcur
        jsr     setgoal
        jmp     post

; ---------------------------------------------------------------- blocks
f_h1:   lda     #B_H1
        bra     f_blk
f_h2:   lda     #B_H2
        bra     f_blk
f_h3:   lda     #B_H3
        bra     f_blk
f_norm: lda     #B_PARA
        bra     f_blk
f_bul:  lda     #B_BUL
        bra     f_blk
f_num:  lda     #B_NUM
        bra     f_blk
f_quote:
        lda     #B_QUO
f_blk:  sta     fm_k
        jsr     arm_drop
        jsr     fm_save
        jsr     selord                  ; the lines
        bcs     :+
        lda     cl
        sta     s0l
        sta     s1l
:       lda     s0l
        sta     fm_sl
        lda     s1l
        sta     fm_el
        cmp     fm_sl                   ; (a selection ending at a line's start: not
        beq     :+                      ; that line)
        lda     s1c
        bne     :+
        dec     fm_el
:       lda     fm_sl                   ; all of that kind already? then: normal text
        sta     fm_l
        stz     fm_cnt
@all:   lda     fm_l
        jsr     lget
        jsr     md_block
        lda     m_blk
        cmp     #B_BLANK
        beq     :+
        inc     fm_cnt
        cmp     fm_k
        bne     @diff
:       lda     fm_l
        inc     fm_l
        cmp     fm_el
        bcc     @all
        lda     fm_cnt
        beq     @diff
        stz     fm_k                    ; (B_PARA)
@diff:  lda     #1                      ; numbers: on from a numbered item above (blank
        sta     fm_num                  ; lines between)
        lda     fm_sl
        sta     z:t4
@up:    lda     z:t4
        beq     @upx
        dec     z:t4
        lda     z:t4
        jsr     lget
        jsr     md_block
        lda     m_blk
        cmp     #B_BLANK
        beq     @up
        cmp     #B_NUM
        bne     @upx
        jsr     fm_numval
        inc     a
        sta     fm_num
@upx:   lda     fm_sl
        sta     fm_l
@ln:    lda     fm_l
        jsr     lget
        jsr     md_block
        lda     m_blk
        cmp     #B_BLANK                ; (blank lines stay, unless the only one)
        bne     :+
        lda     fm_sl
        cmp     fm_el
        bne     @nx
:       jsr     fm_mkpfx                ; the new marker -> fm_buf, fm_blen
        jsr     fm_repl                 ; replaces the old one (m_pfx)
@nx:    lda     fm_l
        inc     fm_l
        cmp     fm_el
        bcc     @ln
        jsr     fm_rest
        jmp     fm_done

; the marker for kind fm_k on line lp (md_block read) -> fm_buf, fm_blen
fm_mkpfx:
        ldy     #0
        lda     fm_k
        beq     @out                    ; normal: none
        cmp     #B_H3 + 1
        bcs     @list
        tax                             ; # ## ###
:       lda     #'#'
        jsr     @put
        dex
        bne     :-
        bra     @sp
@list:  cmp     #B_QUO
        bne     :+
        lda     #'>'
        jsr     @put
        bra     @sp
:       pha                             ; a list: the level kept (4 spaces each)
        lda     m_blk
        cmp     #B_BUL
        beq     :+
        cmp     #B_NUM
        beq     :+
        stz     m_lvl
:       lda     m_lvl
        asl     a
        asl     a
        tax
        beq     :++
:       lda     #' '
        jsr     @put
        dex
        bne     :-
:       pla
        cmp     #B_BUL
        bne     :+
        lda     #'-'
        jsr     @put
        bra     @sp
:       lda     fm_num                  ; the number
        inc     fm_num
        phy
        ldy     #.loword(fm_nbuf)
        jsr     snum
        ply
        ldx     #0
:       lda     fm_nbuf,x
        and     #$00FF
        beq     :+
        jsr     @put
        inx
        bra     :-
:       lda     #'.'
        jsr     @put
@sp:    lda     #' '
        jsr     @put
@out:   sty     fm_blen
        rts
@put:   sep     #$20
        .a8
        sta     fm_buf,y
        rep     #$20
        .a16
        iny
        rts

; line fm_l's block marker (m_pfx long) replaced by fm_buf (fm_blen); the saved cursor
; and anchor follow
fm_repl:
        lda     m_pfx
        sta     fm_op
        beq     :+
        lda     fm_l
        sta     cl
        sta     al
        stz     ac
        lda     fm_op
        sta     cc
        jsr     delsel
:       lda     fm_blen
        beq     :+
        lda     fm_l
        sta     cl
        stz     cc
        jsr     anchor0
        lda     #.loword(fm_buf)
        sta     isrc
        lda     #^fm_buf
        sta     isrc+2
        lda     fm_blen
        jsr     inst
:       ldx     #.loword(fm_cl)         ; the columns kept on this line
        jsr     @fix
        ldx     #.loword(fm_al)
@fix:   lda     a:0,x
        cmp     fm_l
        bne     @out
        lda     a:2,x
        sec
        sbc     fm_op
        bcs     :+
        lda     #0
:       clc
        adc     fm_blen
        sta     a:2,x
@out:   rts

; the number of the numbered item lp (md_block read) -> A
fm_numval:
        lda     m_ind
        clc
        adc     #4
        tay
        lda     #0
:       sta     z:t0
        lda     [lp],y
        and     #$00FF
        cmp     #'0'
        bcc     :+
        cmp     #'9' + 1
        bcs     :+
        sbc     #'0' - 1
        sta     z:t1
        lda     z:t0                    ; t0 * 10 + digit
        asl     a
        asl     a
        adc     z:t0
        asl     a
        adc     z:t1
        iny
        bra     :-
:       lda     z:t0
        rts

; ---------------------------------------------------------------- keys in lists
; Enter: in a list item or a quote, the next one; on an empty one, the list ends
k_enter:
        jsr     arm_drop
        jsr     delsel
        lda     cl
        jsr     lget
        jsr     md_block
        lda     m_blk
        cmp     #B_BUL
        jcc     @plain
        cmp     #B_RULE
        jcs     @plain
        lda     cc
        cmp     m_pfx
        jcc     @plain
        lda     llen
        cmp     m_pfx
        bne     @next
        lda     m_blk                   ; an empty item: out one level, or no marker
        cmp     #B_QUO
        beq     :+
        lda     m_ind
        cmp     #4
        bcc     :+
        stz     fm_c
        lda     cl
        sta     fm_l
        lda     #4
        sta     fm_n
        jsr     fm_del
        lda     cl                      ; (the cursor after its marker)
        jsr     lget
        lda     llen
        sta     cc
        jmp     edited
:       lda     cl                      ; (the marker goes; a line end after it, so the
        sta     al                      ; next paragraph is not read as part of the list)
        stz     ac
        lda     m_pfx
        sta     cc
        jsr     delsel
        jmp     @plain
@next:  lda     m_blk                   ; LF and the next marker
        cmp     #B_NUM
        bne     :+
        jsr     fm_numval               ; (the next number)
        inc     a
        sta     fm_num
:       lda     #10
        sta     fm_buf
        ldy     #1
        ldx     #0
        lda     m_blk
        cmp     #B_NUM
        bne     @cp
:       cpx     m_ind
        bcs     :+
        lda     #' '
        jsr     fm_putb
        inx
        bra     :-
:       phy
        lda     fm_num
        ldy     #.loword(fm_nbuf)
        jsr     snum
        ply
        ldx     #0
:       lda     fm_nbuf,x
        and     #$00FF
        beq     :+
        jsr     fm_putb
        inx
        bra     :-
:       lda     m_pfx                   ; (its . or ): before the space)
        clc
        adc     #2
        phy
        tay
        lda     [lp],y
        ply
        jsr     fm_putb
        lda     #' '
        jsr     fm_putb
        bra     @ins
@cp:    cpx     m_pfx                   ; a bullet or a quote: its marker as it is
        bcs     @ins
        phy
        txa
        clc
        adc     #4
        tay
        lda     [lp],y
        ply
        jsr     fm_putb
        inx
        bra     @cp
@ins:   sty     fm_blen
        lda     m_lvl
        sta     fm_lvl
        lda     m_blk
        sta     fm_k
        lda     #.loword(fm_buf)
        sta     isrc
        lda     #^fm_buf
        sta     isrc+2
        lda     fm_blen
        jsr     inst
        lda     fm_k
        cmp     #B_NUM
        bne     :+
        jsr     renum
:       jmp     edited
@plain: lda     #10
        sta     onech
        lda     #.loword(onech)
        sta     isrc
        lda     #^onech
        sta     isrc+2
        lda     #1
        jsr     inst
        jmp     edited
fm_putb:
        sep     #$20
        .a8
        sta     fm_buf,y
        rep     #$20
        .a16
        iny
        rts

; the numbered items after line cl at its level (fm_lvl) counted on from fm_num (deeper
; items are passed over; anything else ends the list)
renum:  lda     cl
        sta     fm_l
        jsr     fm_save
@l:     inc     fm_l
        lda     fm_l
        cmp     nl
        jcs     @out
        jsr     lget
        jsr     md_block
        lda     m_blk
        cmp     #B_BUL
        beq     :+
        cmp     #B_NUM
        bne     @out
:       lda     m_lvl
        cmp     fm_lvl
        beq     :+
        bcs     @l
        bra     @out
:       lda     m_blk
        cmp     #B_NUM
        bne     @out
        inc     fm_num
        jsr     fm_numval
        cmp     fm_num
        beq     @l
        lda     m_ind                   ; its digits replaced
        sta     fm_c
        clc
        adc     #4
        tay
        ldx     #0
:       lda     [lp],y
        and     #$00FF
        cmp     #'0'
        bcc     :+
        cmp     #'9' + 1
        bcs     :+
        inx
        iny
        bra     :-
:       stx     fm_op
        lda     fm_l
        sta     cl
        sta     al
        lda     fm_c
        sta     ac
        clc
        adc     fm_op
        sta     cc
        jsr     delsel
        ldy     #.loword(fm_nbuf)
        lda     fm_num
        jsr     snum
        tya
        sec
        sbc     #.loword(fm_nbuf)
        pha
        lda     #.loword(fm_nbuf)
        sta     isrc
        lda     #^fm_nbuf
        sta     isrc+2
        pla
        jsr     inst
        brl     @l
@out:   jmp     fm_rest

; Tab / Shift-Tab: list items of the selection (or the cursor's line) in / out a level;
; elsewhere Tab is a tab character
k_tab:  lda     tabmenu                 ; (from the menu: lists only)
        sta     fm_tm
        stz     tabmenu
        jsr     arm_drop
        jsr     fm_save
        jsr     selord
        bcs     :+
        lda     cl
        sta     s0l
        sta     s1l
:       lda     s0l
        sta     fm_sl
        lda     s1l
        sta     fm_el
        stz     fm_cnt
        lda     fm_sl
        sta     fm_l
@ln:    lda     fm_l
        jsr     lget
        jsr     md_block
        lda     m_blk
        cmp     #B_BUL
        beq     :+
        cmp     #B_NUM
        bne     @nx
:       inc     fm_cnt
        lda     shift
        bne     @out1
        lda     #4                      ; in: 4 spaces at its start
        sta     fm_op
        lda     #.loword(fm_sp4)
        sta     isrc
        lda     #^fm_sp4
        sta     isrc+2
        lda     fm_l
        sta     cl
        stz     cc
        jsr     anchor0
        lda     #4
        jsr     inst
        lda     #4
        bra     @fix
@out1:  lda     m_ind                   ; out: up to 4 spaces from its start
        cmp     #4
        bcc     :+
        lda     #4
:       sta     fm_op
        beq     @nx
        lda     fm_l
        sta     cl
        sta     al
        stz     ac
        lda     fm_op
        sta     cc
        jsr     delsel
        lda     fm_op
        eor     #$FFFF
        inc     a
@fix:   sta     z:t5                    ; the saved columns on this line move
        ldx     #.loword(fm_cl)
        jsr     @mv
        ldx     #.loword(fm_al)
        jsr     @mv
@nx:    lda     fm_l
        inc     fm_l
        cmp     fm_el
        jcc     @ln
        lda     fm_cnt
        bne     :+
        lda     fm_tm                   ; no list: a tab character (Shift-Tab, the menu:
        ora     shift                   ; nothing)
        jne     loop
        jsr     fm_rest
        lda     #9
        sta     key
        jmp     k_char
:       jsr     fm_rest
        jmp     fm_done
@mv:    lda     a:0,x
        cmp     fm_l
        bne     :+
        lda     a:2,x
        clc
        adc     z:t5
        bpl     :++
        lda     #0
        bra     :++
:       rts
:       sta     a:2,x
        rts

; Format > Indent list / Outdent list: as Tab / Shift-Tab, for list items only
f_indent:
        stz     shift
        bra     :+
f_outdent:
        lda     #1
        sta     shift
:       lda     #1
        sta     tabmenu
        jmp     k_tab

; Format > Rule: a rule (---) on a line of its own, with a blank line before it (so that the
; paragraph above does not become a heading in other Markdown readers), the cursor on a
; new line after it; on a rule: it goes (a blank line stays)
f_rule: jsr     arm_drop
        jsr     selord
        bcc     :+
        lda     s1l                     ; (a selection: after its last line)
        sta     cl
        lda     s1c
        sta     cc
:       lda     cl
        jsr     lget
        jsr     md_block
        lda     m_blk
        cmp     #B_RULE
        bne     @add
        lda     cl                      ; on a rule: the line emptied
        sta     al
        stz     ac
        lda     llen
        sta     cc
        jsr     delsel
        jmp     edited
@add:   cmp     #B_BLANK
        beq     @blank
        lda     llen                    ; after the line's text: a blank line, the rule
        sta     cc
        ldx     #.loword(fm_rule2)
        lda     #6
        bra     @ins
@blank: lda     cl                      ; a blank line: emptied, the rule there (after a
        sta     al                      ; blank line)
        stz     ac
        lda     llen
        sta     cc
        jsr     delsel
        ldx     #.loword(fm_rule1)
        lda     cl
        beq     :+
        dec     a
        jsr     lget
        jsr     md_block
        lda     m_blk
        cmp     #B_BLANK
        beq     :+
        ldx     #.loword(fm_rule2 + 1)
        lda     #5
        bra     @ins
:       lda     #4
@ins:   stx     isrc
        pha
        lda     #^fm_rule1
        sta     isrc+2
        jsr     anchor0
        pla
        jsr     inst
        jmp     edited

; Backspace at the start of a list item's, a quote's or a heading's text (its marker
; hidden): the marker goes -> C clear; else C set
bs_block:
        lda     showmk
        bne     @no
        lda     cl
        jsr     lget
        jsr     md_block
        lda     m_blk
        beq     @no
        cmp     #B_RULE
        bcs     @no
        lda     cc
        cmp     m_pfx
        bne     @no
        lda     cl
        sta     al
        stz     ac
        jsr     delsel
        clc
        rts
@no:    sec
        rts

        .segment "RODATA"
fmk_b:   .byte   "**"
fmk_i:   .byte   "*"
fmk_c:   .byte   "`"
; the inline styles (Bold, Italic, Code): their marker, its length, their style bit, their
; toolbar button
fmk_tab: .addr  fmk_b, fmk_i, fmk_c
fmk_len: .word  2, 1, 1
fmk_sbit: .word S_B, S_I, S_C
fmk_bit: .word  1 << 2, 1 << 3, 1 << 4
fm_rule1: .byte "---", 10
fm_rule2: .byte 10, 10, "---", 10
fm_sp4: .byte   "    "

        .segment "BSS"
fm_mk:  .res    2                       ; the marker (inline), its length
fm_n:   .res    2
fm_ch:  .res    2
fm_k:   .res    2                       ; the block kind
fm_l:   .res    2
fm_c:   .res    2
fm_a:   .res    2
fm_b:   .res    2
fm_sl:  .res    2
fm_sc:  .res    2
fm_el:  .res    2
fm_ec:  .res    2
fm_rm:  .res    2
fm_where: .res  2
fm_cnt: .res    2
fm_num: .res    2
fm_lvl: .res    2
fm_op:  .res    2
fm_blen: .res   2
fm_cl:  .res    2                       ; (fm_cl, fm_cc and fm_al, fm_ac: pairs)
fm_cc:  .res    2
fm_al:  .res    2
fm_ac:  .res    2
fm_kind: .res   2                       ; the inline style (0 bold, 1 italic, 2 code)
fm_sbit: .res   2
fm_tm:  .res    2
tabmenu: .res   2                       ; 1: Tab from the menu
arm_n:  .res    2                       ; the styles armed
arm_l:  .res    2
arm_c:  .res    2
arm_w:  .res    2
arm_i:  .res    2
arm_k:  .res    4
arm_bits: .res  2
arm_ub0: .res   2                       ; ub_top before the arming, after it
arm_ubt: .res   2
arm_txt: .res   8
fm_buf: .res    32
fm_nbuf: .res   8
