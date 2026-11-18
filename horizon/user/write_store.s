; write_store.s - Write: the text store (as Edit's: a line table and a heap of line blocks),
; its changes (inst, delsel: they mark what to redraw, keep the word count and the undo
; records), undo / redo, the clipboard. Part of write.s.

; ---------------------------------------------------------------- the text store
; an empty text: one empty line
tx_reset:
        ldx     #0                      ; the heap banks back
:       cpx     hbn
        bcs     :+
        phx
        txa
        asl     a
        tax
        lda     hb,x
        sys     SYS_BFREE
        plx
        inx
        bra     :-
:       stz     hbn
        stz     hcur
        stz     hoff
        stz     nl
        lda     #16
        jsr     halloc
        bcs     :+
        lda     #0
        jsr     tins
        lda     #0
        jsr     lset
        stz     cl
        stz     cc
        stz     al
        stz     ac
        stz     top
        stz     goalx
        stz     toff
        stz     emod
        stz     crlf
        stz     dr_ok
        stz     mt_ok
        stz     rv_l
        stz     dr_rv
        stz     wc_tot
        stz     wc_tot+2
        stz     arm_n
        jsr     markclr
        jsr     lc_flush
        jsr     ub_clear
        clc
:       rts

; A = line -> lp = its block, llen, lcap; lnum = A
lget:   sta     lnum
        asl     a
        tay
        lda     [zlo],y
        sta     z:lp
        lda     [zhi],y
        sta     z:lp+2
        ldy     #2
        lda     [lp],y
        sta     llen
        lda     [lp]
        sta     lcap
        rts

; A = line: its entry = lp
lset:   asl     a
        tay
        lda     z:lp
        sta     [zlo],y
        lda     z:lp+2
        sta     [zhi],y
        rts

; A = capacity -> lp = a new block (length 0); C set: no memory
halloc: stz     hretry
halloc2:
        sta     hcap
        clc
        adc     #4
        sta     hsize
        lda     hcur
        beq     @new
        lda     hoff
        clc
        adc     hsize
        bcs     @new
        cmp     #$FFF0
        bcs     @new
@take:  lda     hoff
        sta     z:lp
        lda     hcur
        sta     z:lp+2
        lda     hcap
        sta     [lp]
        ldy     #2
        lda     #0
        sta     [lp],y
        lda     hoff
        clc
        adc     hsize
        sta     hoff
        clc
        rts
@new:   lda     hbn
        cmp     #MAXHB
        bcc     @alloc
        lda     incomp                  ; compacting: may go further
        beq     :+
        lda     hbn
        cmp     #MAXHB * 2
        bcs     @fail
        bra     @alloc
:       lda     hretry                  ; full: compact once, then try again
        bne     @fail
        inc     hretry
        jsr     compact
        bcs     @fail
        lda     hcap
        jmp     halloc2
@alloc: sys     SYS_BALLOC
        bcs     @fail
        sta     hcur
        stz     hoff
        lda     hbn
        asl     a
        tax
        lda     hcur
        sta     hb,x
        inc     hbn
        bra     @take
@fail:  sec
        rts

; copy the live lines into fresh banks (in line order), free the old ones -> C set: failed
; (then the old banks are kept as well)
compact:
        inc     incomp
        ldx     #0                      ; the old banks aside
:       cpx     hbn
        bcs     :+
        txa
        asl     a
        tay
        lda     hb,y
        sta     ohb,y
        inx
        bra     :-
:       stx     ohbn
        stz     hbn
        stz     hcur
        stz     cpi
@l:     lda     cpi
        cmp     nl
        bcs     @done
        jsr     lget
        lda     z:lp                    ; sp = the old block
        sta     z:sp
        lda     z:lp+2
        sta     z:sp+2
        lda     llen
        sta     cplen
        clc
        adc     #8
        jsr     halloc2
        bcs     @fail
        lda     cplen
        ldy     #2
        sta     [lp],y
        jsr     cpblock
        lda     cpi
        jsr     lset
        inc     cpi
        bra     @l
@done:  ldx     #0
:       cpx     ohbn
        bcs     :+
        phx
        txa
        asl     a
        tax
        lda     ohb,x
        sys     SYS_BFREE
        plx
        inx
        bra     :-
:       dec     incomp
        clc
        rts
@fail:  ldx     #0                      ; keep both
:       cpx     ohbn
        bcs     :+
        txa
        asl     a
        tay
        lda     ohb,y
        phy
        lda     hbn
        asl     a
        tay
        pla
        tax
        lda     ohb,x
        sta     hb,y
        inc     hbn
        txa
        lsr     a
        tax
        inx
        bra     :-
:       dec     incomp
        sec
        rts

; copy cplen bytes of line data: [sp] + 4 -> [lp] + 4
cpblock:
        ldy     #4
        ldx     cplen
        beq     :++
        sep     #$20
        .a8
:       lda     [sp],y
        sta     [lp],y
        iny
        dex
        bne     :-
        rep     #$20
        .a16
:       rts

; line lnum (loaded) must hold A bytes: moved to a larger block if needed -> C set: no memory
lgrow:  cmp     lcap
        bcc     @ok
        beq     @ok
        sta     z:t0
        lsr     a
        lsr     a
        clc
        adc     z:t0
        adc     #16
        cmp     #MAXLEN + 64
        bcc     :+
        lda     #MAXLEN + 64
:       sta     gcap
        lda     lnum
        pha
        lda     gcap
        jsr     halloc
        pla
        bcs     @fail
        sta     lnum
        lda     z:lp                    ; the new block -> dp
        sta     z:dp
        lda     z:lp+2
        sta     z:dp+2
        lda     lnum                    ; the old one (it may have moved) -> sp
        jsr     lget
        lda     z:lp
        sta     z:sp
        lda     z:lp+2
        sta     z:sp+2
        lda     z:dp
        sta     z:lp
        lda     z:dp+2
        sta     z:lp+2
        lda     llen
        sta     cplen
        ldy     #2
        sta     [lp],y
        jsr     cpblock
        lda     gcap
        sta     lcap
        lda     lnum
        jsr     lset
@ok:    clc
        rts
@fail:  sec
        rts

; insert A bytes from [sp] into line lnum (loaded) at column X -> C set: no room
ins_bytes:
        sta     in_n
        stx     in_c
        lda     z:sp                    ; (lgrow uses sp)
        sta     insrc
        lda     z:sp+2
        sta     insrc+2
        lda     in_n
        clc
        adc     llen
        cmp     #MAXLEN + 1
        bcs     @fail
        jsr     lgrow
        bcs     @fail
        lda     insrc
        sta     z:sp
        lda     insrc+2
        sta     z:sp+2
        lda     z:lp                    ; dp = lp + n: the tail moves up
        clc
        adc     in_n
        sta     z:dp
        lda     z:lp+2
        sta     z:dp+2
        lda     in_c
        clc
        adc     #4
        sta     z:t0
        lda     llen
        clc
        adc     #4
        tay
        sep     #$20
        .a8
:       cpy     z:t0
        beq     :+
        dey
        lda     [lp],y
        sta     [dp],y
        bra     :-
:       rep     #$20
        .a16
        lda     z:lp                    ; dp = the gap: the new bytes
        clc
        adc     z:t0
        sta     z:dp
        ldy     #0
        ldx     in_n
        beq     :++
        sep     #$20
        .a8
:       lda     [sp],y
        sta     [dp],y
        iny
        dex
        bne     :-
        rep     #$20
        .a16
:       lda     llen
        clc
        adc     in_n
        sta     llen
        ldy     #2
        sta     [lp],y
        lda     lnum
        ldx     in_c
        jsr     lc_chg
        clc
        rts
@fail:  sec
        rts

; delete A bytes of line lnum (loaded) at column X
del_bytes:
        sta     in_n
        stx     in_c
        txa
        clc
        adc     #4
        tay
        lda     z:lp                    ; dp = lp + n: the tail comes down from there
        clc
        adc     in_n
        sta     z:dp
        lda     z:lp+2
        sta     z:dp+2
        lda     llen
        sec
        sbc     in_n
        sta     llen
        clc
        adc     #4
        sta     z:t0
        sep     #$20
        .a8
:       cpy     z:t0
        bcs     :+
        lda     [dp],y
        sta     [lp],y
        iny
        bra     :-
:       rep     #$20
        .a16
        lda     llen
        ldy     #2
        sta     [lp],y
        lda     lnum
        ldx     in_c
        jmp     lc_chg

; a new entry at line A (the entries from there move up); the caller sets it
tins:   sta     tn_l
        asl     a
        sta     z:t0
        lda     nl
        asl     a
        tay
:       cpy     z:t0
        beq     :+
        dey
        dey
        lda     [zlo],y
        iny
        iny
        sta     [zlo],y
        dey
        dey
        lda     [zhi],y
        iny
        iny
        sta     [zhi],y
        dey
        dey
        bra     :-
:       inc     nl
        lda     tn_l
        jmp     lc_ins

; delete X entries from line A
tdel:   stx     z:t1
        sta     tn_l
        stx     tn_n
        asl     a
        tay
        txa
        asl     a
        clc
        adc     z:zlo
        sta     z:sp
        lda     z:zlo+2
        sta     z:sp+2
        txa
        asl     a
        clc
        adc     z:zhi
        sta     z:dp
        lda     z:zhi+2
        sta     z:dp+2
        lda     nl
        sec
        sbc     z:t1
        sta     nl
        asl     a
        sta     z:t0
:       cpy     z:t0
        bcs     :+
        lda     [sp],y
        sta     [zlo],y
        lda     [dp],y
        sta     [zhi],y
        iny
        iny
        bra     :-
:       lda     tn_l
        ldx     tn_n
        jmp     lc_del


; ---------------------------------------------------------------- changes of the text
; Every change goes through inst and delsel: they mark what to redraw and keep the undo
; record (unless ub_rec = 0: loading, undo, redo).

; insert A bytes from isrc (a long pointer; LF = a line break) at the cursor; the cursor
; ends after them. C set if something did not fit (lines, memory).
inst:   sta     in_len
        lda     cl
        sta     u_l0
        lda     cc
        sta     u_c0
        stz     mt_ok
        jsr     wc_ipre                 ; (the words: those around it, or its lines')
        lda     loadng
        bne     :+
        jsr     setmod
:       lda     in_len
        jsr     inst0
        php
        jsr     wc_ipost
        lda     cl                      ; the lines it touched: the marks
        cmp     u_l0
        bne     @multi
        ldx     u_c0
        jsr     markp
        bra     @m
@multi: lda     u_l0
        ldx     cl
        jsr     markr
@m:     plp
        bcs     @err
        jmp     ub_ins
@err:   jsr     ub_clear                ; (not all of it: the history would not match)
        sec
        rts

; delete the selection (if any); the cursor at its start
delsel: jsr     selord
        bcs     :+
        rts
:       stz     mt_ok
        jsr     wc_dpre                 ; (the words: those around it, or its lines')
        jsr     ub_del
        jsr     delsel0
        jsr     wc_dpost
        lda     s0l
        ldx     s0c
        jmp     markp

; ---------------------------------------------------------------- the word count
; wc_tot: the words of the text, kept up to date by inst and delsel. A word: a run of
; characters that are not spaces with a letter or digit in it (so markup alone, "-" or
; "**", is none), not counting a numbered item's "12." at the line's start.
; An edit inside one line changes only the words of the run of non-spaces it is in (with
; what it inserts): those are counted before and after it, not the whole line (unless the
; run is the line's first: a numbered item's number is no word).
; before inst: one line (no LF inserted) -> the run around the cursor (wc_a .. wc_b) and
; its words (wc_old), wc_loc = 1; else the cursor's line's words go
wc_ipre:
        stz     wc_loc
        lda     isrc
        sta     z:sp
        lda     isrc+2
        sta     z:sp+2
        ldy     #0
:       cpy     in_len
        bcs     :+
        lda     [sp],y
        and     #$00FF
        cmp     #10
        beq     @lines
        iny
        bra     :-
:       lda     cl
        jsr     lget
        lda     cc
        tax
        jsr     wc_run
        bcc     @lines
        jmp     wc_old0
@lines: lda     cl
        tax
        jmp     wc_sub
; after inst: the run's words now (it holds the text inserted), or the lines'
wc_ipost:
        lda     wc_loc
        beq     @lines
        lda     u_l0
        jsr     lget
        lda     cl
        cmp     u_l0
        bne     @lines                  ; (cannot be)
        lda     cc
        sec
        sbc     u_c0
        jmp     wc_new
@lines: lda     u_l0
        ldx     cl
        jmp     wc_add
; before delsel (the selection ordered): on one line, its run (from before s0c to after
; s1c) and its words; else its lines' words go
wc_dpre:
        stz     wc_loc
        lda     s0l
        cmp     s1l
        bne     @lines
        jsr     lget
        lda     s0c
        ldx     s1c
        jsr     wc_run
        bcc     @lines
        jmp     wc_old0
@lines: lda     s0l
        ldx     s1l
        jmp     wc_sub
; after delsel: the run's words now, or the first line's
wc_dpost:
        lda     wc_loc
        beq     @lines
        lda     s0l
        jsr     lget
        lda     s0c
        sec
        sbc     s1c
        jmp     wc_new
@lines: lda     s0l
        tax
        jmp     wc_add
; the run of non-spaces around columns A .. X of line lp -> wc_a, wc_b; C clear: it is the
; line's first (count the line)
wc_run: stx     wc_b
        sta     wc_a
:       lda     wc_a                    ; back over non-spaces
        beq     :+
        clc
        adc     #3
        tay
        lda     [lp],y
        and     #$00FF
        cmp     #' ' + 1
        bcc     :+
        dec     wc_a
        bra     :-
:       ldy     #4                      ; a non-space before it? (else: the first run)
:       tya
        sec
        sbc     #4
        cmp     wc_a
        bcs     @first
        lda     [lp],y
        and     #$00FF
        cmp     #' ' + 1
        bcs     :+
        iny
        bra     :-
:       lda     wc_b                    ; on over non-spaces
        clc
        adc     #4
        tay
        lda     llen
        clc
        adc     #4
        sta     z:t3
:       cpy     z:t3
        bcs     :+
        lda     [lp],y
        and     #$00FF
        cmp     #' ' + 1
        bcc     :+
        iny
        bra     :-
:       tya
        sec
        sbc     #4
        sta     wc_b
        sec
        rts
@first: clc
        rts
; the run's words (wc_old), wc_loc = 1
wc_old0:
        lda     wc_a
        ldx     wc_b
        jsr     wc_range
        sta     wc_old
        lda     #1
        sta     wc_loc
        rts
; the run grew by A columns (line lp): its words now - before -> wc_tot
wc_new: clc
        adc     wc_b
        tax
        lda     wc_a
        jsr     wc_range
        sec
        sbc     wc_old
        tax
        clc
        adc     wc_tot
        sta     wc_tot
        txa
        and     #$8000                  ; (the sign into the high word)
        beq     :+
        lda     #$FFFF
:       adc     wc_tot+2
        sta     wc_tot+2
        rts

; lines A .. X: their words added to / taken from wc_tot
wc_add: jsr     wc_lines
        clc
        adc     wc_tot
        sta     wc_tot
        lda     wc_hi
        adc     wc_tot+2
        sta     wc_tot+2
        rts
wc_sub: jsr     wc_lines
        eor     #$FFFF
        sec
        adc     wc_tot
        sta     wc_tot
        lda     wc_hi
        eor     #$FFFF
        adc     wc_tot+2
        sta     wc_tot+2
        rts
; the words of lines A .. X -> wc_hi:A
wc_lines:
        sta     wc_i
        stx     wc_j
        stz     wc_n
        stz     wc_hi
@l:     lda     wc_i
        cmp     wc_j
        beq     :+
        bcs     @out
:       cmp     nl
        bcs     @out
        jsr     wc_line
        clc
        adc     wc_n
        sta     wc_n
        bcc     :+
        inc     wc_hi
:       inc     wc_i
        bne     @l
@out:   lda     wc_n
        rts
; the words of columns A .. X of line lp (the ends at spaces or the line's ends) -> A
wc_range:
        stz     z:t4
        clc
        adc     #4
        tay
        txa
        clc
        adc     #4
        sta     z:t3
        bra     wc_l
; the words of line A -> A
wc_line:
        jsr     lget
        stz     z:t4                    ; words
        ldy     #4
        lda     llen
        clc
        adc     #4
        sta     z:t3                    ; the end
:       cpy     z:t3                    ; a numbered item's number: not a word
        bcs     wc_l
        lda     [lp],y
        and     #$00FF
        cmp     #' '
        bne     :+
        iny
        bra     :-
:       sty     z:t2
:       cpy     z:t3
        bcs     @nod
        lda     [lp],y
        and     #$00FF
        cmp     #'0'
        bcc     :+
        cmp     #'9' + 1
        bcs     :+
        iny
        bra     :-
:       cpy     z:t2
        beq     @nod
        cmp     #'.'
        beq     :+
        cmp     #')'
        bne     @nod
:       iny
        cpy     z:t3
        bcs     wc_l
        lda     [lp],y
        and     #$00FF
        cmp     #' '
        beq     wc_l
@nod:   ldy     z:t2
wc_l:
@l:     cpy     z:t3                    ; the runs
        bcs     @out
        lda     [lp],y
        and     #$00FF
        cmp     #' ' + 1
        bcs     @run
        iny
        bra     @l
@run:   stz     z:t1                    ; 1: a letter or digit in it
@r:     cpy     z:t3
        bcs     @end
        lda     [lp],y
        and     #$00FF
        cmp     #' ' + 1
        bcc     @end
        cmp     #128
        bcs     @al
        cmp     #'0'
        bcc     @nx
        cmp     #'9' + 1
        bcc     @al
        and     #$DF
        cmp     #'A'
        bcc     @nx
        cmp     #'Z' + 1
        bcs     @nx
@al:    lda     #1
        sta     z:t1
@nx:    iny
        bra     @r
@end:   lda     z:t1
        beq     @l
        inc     z:t4
        bra     @l
@out:   lda     z:t4
        rts

; ---------------------------------------------------------------- undo
; the stack empty (the text as it is counts as saved unless it is modified)
ub_clear:
        stz     ub_top
        stz     ub_end
        lda     emod
        beq     :+
        lda     #NONE
:       sta     ub_save
        rts

; the insert just made (u_l0:u_c0 .. cl:cc, in_len bytes at isrc): recorded, or added to
; the record on top (characters typed in a row, up to a word's end)
ub_ins: lda     ub_rec
        jeq     @out
        lda     isrc                    ; (the text: up)
        sta     z:up
        lda     isrc+2
        sta     z:up+2
        lda     ub_mrg
        cmp     #UF_TYPE
        jne     @new
        lda     ub_grp                  ; (not the first change of this action)
        jne     @new
        jsr     ub_topr
        jcs     @new
        lda     ub_k                    ; an insert typed, ending here?
        and     #$00FF
        cmp     #U_INS
        jne     @new
        lda     ub_k+1
        and     #UF_TYPE
        jeq     @new
        lda     ub_l1
        cmp     u_l0
        jne     @new
        lda     ub_c1
        cmp     u_c0
        jne     @new
        lda     ub_n
        cmp     #250
        jcs     @new
        lda     [up]                  ; a word starts after a space: a new record
        and     #$00FF
        cmp     #' '
        beq     :+
        lda     ub_r
        clc
        adc     #12 - 1
        adc     ub_n
        tay
        lda     [ub],y
        and     #$00FF
        cmp     #' '
        jeq     @new
:       lda     ub_top                  ; room for one more byte?
        cmp     #UBSIZE - 1
        jcs     @new
        lda     ub_r                    ; the byte after its text, the size after that
        clc
        adc     #12
        adc     ub_n
        tay
        lda     [up]
        sep     #$20
        .a8
        sta     [ub],y
        rep     #$20
        .a16
        iny
        lda     ub_n
        clc
        adc     #15
        sta     [ub],y
        inc     ub_top
        lda     ub_top
        sta     ub_end
        ldy     ub_r                    ; n + 1, its end = the cursor
        tya
        clc
        adc     #10
        tay
        lda     ub_n
        inc     a
        sta     [ub],y
        ldy     ub_r
        iny
        iny
        iny
        iny
        iny
        iny
        lda     cl
        sta     [ub],y
        iny
        iny
        lda     cc
        sta     [ub],y
@out:   clc
        rts
@new:   lda     in_len
        sta     u_n
        lda     cl
        sta     u_l1
        lda     cc
        sta     u_c1
        lda     #U_INS
        ldx     ub_mrg
        cpx     #UF_TYPE
        bne     :+
        ora     #UF_TYPE << 8
:       jsr     ub_new
        bcs     @out
        ldy     #0                      ; the text
        ldx     ub_w
:       cpy     u_n
        bcs     :+
        lda     [up],y
        phy
        txy
        sep     #$20
        .a8
        sta     [ub],y
        rep     #$20
        .a16
        ply
        iny
        inx
        bra     :-
:       clc
        rts

; the delete about to be made (the selection s0l:s0c .. s1l:s1c): recorded with its text,
; or added to the record on top (Backspace, Delete in a row)
ub_del: lda     ub_rec
        jeq     @out
        lda     s0l                     ; its size
        cmp     s1l
        bne     :+
        lda     s1c
        sec
        sbc     s0c
        bra     @sz
:       lda     s0l
        sta     cpi
        jsr     lget
        lda     llen
        sec
        sbc     s0c
        sta     u_n
:       inc     cpi                     ; + LF + the next line (the last one: to s1c)
        inc     u_n
        jeq     @big
        lda     cpi
        cmp     s1l
        bcs     :+
        jsr     lget
        lda     u_n
        clc
        adc     llen
        jcs     @big
        sta     u_n
        bra     :-
:       lda     u_n
        clc
        adc     s1c
        jcs     @big
@sz:    sta     u_n
        cmp     #UBSIZE - 14
        jcs     @big
        cmp     #1                      ; one character (or line end) by Backspace / Delete
        jne     @new
        lda     ub_mrg
        cmp     #UF_BS
        beq     :+
        cmp     #UF_DELK
        jne     @new
:       lda     ub_grp
        jne     @new
        jsr     ub_topr
        jcs     @new
        lda     ub_k
        and     #$00FF
        cmp     #U_DEL
        jne     @new
        lda     ub_k+1
        and     ub_mrg
        jeq     @new
        lda     ub_n
        cmp     #250
        jcs     @new
        lda     ub_top
        cmp     #UBSIZE - 1
        jcs     @new
        jsr     @char                   ; z:t0 = the character
        lda     ub_mrg
        cmp     #UF_BS
        bne     @dk
        lda     ub_l0                   ; Backspace: this one ends where the last began
        cmp     s1l
        jne     @new
        lda     ub_c0
        cmp     s1c
        jne     @new
        lda     ub_r                    ; the text moves up one byte (with the size)
        clc
        adc     #12
        sta     z:t1
        adc     ub_n
        inc     a
        tay
:       dey
        cpy     z:t1
        bcc     :+
        lda     [ub],y
        iny
        sep     #$20
        .a8
        sta     [ub],y
        rep     #$20
        .a16
        dey
        bra     :-
:       ldy     z:t1
        lda     z:t0
        sep     #$20
        .a8
        sta     [ub],y
        rep     #$20
        .a16
        ldy     ub_r                    ; starts at s0
        iny
        iny
        lda     s0l
        sta     [ub],y
        iny
        iny
        lda     s0c
        sta     [ub],y
        bra     @grow
@dk:    lda     ub_l0                   ; Delete: at the same place
        cmp     s0l
        jne     @new
        lda     ub_c0
        cmp     s0c
        jne     @new
        lda     ub_r                    ; the character after its text
        clc
        adc     #12
        adc     ub_n
        tay
        lda     z:t0
        sep     #$20
        .a8
        sta     [ub],y
        rep     #$20
        .a16
        ldy     ub_r                    ; its end one character on (in the old text)
        tya
        clc
        adc     #6
        tay
        lda     z:t0
        cmp     #10
        bne     :+
        lda     ub_l1
        inc     a
        sta     [ub],y
        iny
        iny
        lda     #0
        sta     [ub],y
        bra     @grow
:       iny
        iny
        lda     ub_c1
        inc     a
        sta     [ub],y
@grow:  ldy     ub_r                    ; n + 1, the size after the text
        tya
        clc
        adc     #10
        tay
        lda     ub_n
        inc     a
        sta     [ub],y
        lda     ub_r
        clc
        adc     #13
        adc     ub_n
        tay
        lda     ub_n
        clc
        adc     #15
        sta     [ub],y
        inc     ub_top
        lda     ub_top
        sta     ub_end
@out:   rts
@big:   jmp     ub_clear                ; (too large to keep: the history goes)
@new:   lda     s0l
        sta     u_l0
        lda     s0c
        sta     u_c0
        lda     s1l
        sta     u_l1
        lda     s1c
        sta     u_c1
        lda     #U_DEL
        ldx     ub_mrg
        cpx     #UF_BS
        beq     :+
        cpx     #UF_DELK
        bne     :++
:       pha
        txa
        xba
        ora     1,s
        sta     1,s
        pla
:       jsr     ub_new
        bcs     @out
        jmp     ub_cpdoc
; the one character deleted -> z:t0 (an LF for a line end)
@char:  lda     #10
        sta     z:t0
        lda     s0l
        cmp     s1l
        bne     :+
        jsr     lget
        lda     s0c
        clc
        adc     #4
        tay
        lda     [lp],y
        and     #$00FF
        sta     z:t0
:       rts

; the text s0l:s0c .. s1l:s1c -> UB at ub_w (lines joined with LF)
ub_cpdoc:
        lda     ub_w
        sta     cpn
        lda     s0l
        sta     cpi
@l:     lda     cpi
        jsr     lget
        stz     z:t0                    ; from
        lda     cpi
        cmp     s0l
        bne     :+
        lda     s0c
        sta     z:t0
:       lda     llen                    ; to
        sta     z:t1
        lda     cpi
        cmp     s1l
        bne     :+
        lda     s1c
        sta     z:t1
:       lda     z:t0
        clc
        adc     #4
        tay
        ldx     cpn
@c:     tya
        sec
        sbc     #4
        cmp     z:t1
        bcs     @le
        lda     [lp],y
        phy
        txy
        sep     #$20
        .a8
        sta     [ub],y
        rep     #$20
        .a16
        ply
        iny
        inx
        bra     @c
@le:    lda     cpi
        cmp     s1l
        bcs     @out
        lda     #10
        txy
        sep     #$20
        .a8
        sta     [ub],y
        rep     #$20
        .a16
        inx
        stx     cpn
        inc     cpi
        bra     @l
@out:   rts

; the record on top -> ub_r (its offset), ub_k (kind | flags << 8), ub_l0 .. ub_c1, ub_n;
; C set: none, or the text was saved just after it (it stays as it is)
ub_topr:
        lda     ub_top
        beq     ub_no
        cmp     ub_save
        beq     ub_no
        sec
        sbc     #2
        tay
        lda     [ub],y
        eor     #$FFFF
        sec
        adc     ub_top
        sta     ub_r
        ; fall through
; the record at ub_r -> ub_k .. ub_n (C clear)
ub_rd:  ldy     ub_r
        lda     [ub],y
        sta     ub_k
        iny
        iny
        lda     [ub],y
        sta     ub_l0
        iny
        iny
        lda     [ub],y
        sta     ub_c0
        iny
        iny
        lda     [ub],y
        sta     ub_l1
        iny
        iny
        lda     [ub],y
        sta     ub_c1
        iny
        iny
        lda     [ub],y
        sta     ub_n
        clc
        rts
ub_no:  sec
        rts

; a new record: A = kind | flags << 8 (UF_JOIN is added after the action's first change),
; u_l0 .. u_c1, u_n bytes of text to come. Room is made (the redo part goes; the oldest
; records if needed) -> C clear, ub_w = where its text goes; C set: too large (the stack
; is emptied)
ub_new: ldx     ub_grp
        beq     :+
        ora     #UF_JOIN << 8
:       sta     ub_k
        lda     #1
        sta     ub_grp
        lda     u_n
        clc
        adc     #14
        jcs     @big
        cmp     #UBSIZE
        jcs     @big
        sta     u_sz
        lda     ub_top                  ; the redo part goes (and a save point in it)
        sta     ub_end
        lda     ub_save
        cmp     #NONE
        beq     :+
        cmp     ub_top
        bcc     :+
        beq     :+
        lda     #NONE
        sta     ub_save
:       lda     ub_top
        clc
        adc     u_sz
        bcs     @drop
        cmp     #UBSIZE
        bcc     @fits
@drop:  jsr     ub_dropold
        jcs     @big
@fits:  ldy     ub_top
        lda     ub_k
        sta     [ub],y
        iny
        iny
        lda     u_l0
        sta     [ub],y
        iny
        iny
        lda     u_c0
        sta     [ub],y
        iny
        iny
        lda     u_l1
        sta     [ub],y
        iny
        iny
        lda     u_c1
        sta     [ub],y
        iny
        iny
        lda     u_n
        sta     [ub],y
        iny
        iny
        sty     ub_w
        tya
        clc
        adc     u_n
        tay
        lda     u_sz
        sta     [ub],y
        lda     ub_top
        clc
        adc     u_sz
        sta     ub_top
        sta     ub_end
        clc
        rts
@big:   jsr     ub_clear
        sec
        rts

; the oldest records go until u_sz bytes fit -> C set: they cannot
ub_dropold:
        lda     ub_top
        clc
        adc     u_sz
        sec
        sbc     #UBSIZE
        sta     z:t0                    ; at least this much
        stz     z:t1                    ; record boundaries from the bottom
@w:     lda     z:t1
        cmp     z:t0
        bcs     @cut
        cmp     ub_top
        bcs     @no
        clc
        adc     #10
        tay
        lda     [ub],y
        clc
        adc     #14
        adc     z:t1
        sta     z:t1
        bra     @w
@cut:   cmp     ub_top
        beq     :+
        bcs     @no
:       sta     z:t0                    ; [t0, top) -> [0, top - t0)
        lda     z:ub
        clc
        adc     z:t0
        sta     z:ubs
        lda     z:ub+2
        sta     z:ubs+2
        lda     ub_top
        sec
        sbc     z:t0
        sta     ub_top
        sta     ub_end
        ldy     #0
:       cpy     ub_top
        bcs     :+
        lda     [ubs],y
        sta     [ub],y
        iny
        iny
        bra     :-
:       lda     ub_save
        cmp     #NONE
        beq     :++
        sec
        sbc     z:t0
        bcs     :+
        lda     #NONE
:       sta     ub_save
:       lda     ub_top                  ; the first record left starts a group
        beq     :+
        lda     [ub]
        and     #$FFFF ^ (UF_JOIN << 8)
        sta     [ub]
:       clc
        rts
@no:    sec
        rts

; Edit > Undo: the last group of changes taken back (the text they removed comes back
; selected)
undo:   lda     ub_top
        bne     :+
        jmp     ui_beep
:       stz     ub_rec
@l:     lda     ub_top
        sec
        sbc     #2
        tay
        lda     [ub],y
        eor     #$FFFF
        sec
        adc     ub_top
        sta     ub_r
        jsr     ub_rd
        lda     ub_k
        and     #$00FF
        cmp     #U_INS
        bne     @del
        lda     ub_l0                   ; an insert: its text goes
        sta     al
        lda     ub_c0
        sta     ac
        lda     ub_l1
        sta     cl
        lda     ub_c1
        sta     cc
        jsr     delsel
        bra     @n
@del:   lda     ub_l0                   ; a delete: its text comes back, selected
        sta     cl
        lda     ub_c0
        sta     cc
        jsr     ub_text
        lda     ub_n
        jsr     inst
        lda     ub_l0
        sta     al
        lda     ub_c0
        sta     ac
@n:     lda     ub_r
        sta     ub_top
        beq     :+
        lda     ub_k+1
        and     #UF_JOIN
        bne     @l
:       bra     ub_done

; Edit > Redo: the next group of changes made again
redo:   lda     ub_top
        cmp     ub_end
        bcc     :+
        jmp     ui_beep
:       stz     ub_rec
@l:     lda     ub_top
        sta     ub_r
        jsr     ub_rd
        lda     ub_k
        and     #$00FF
        cmp     #U_INS
        bne     @del
        lda     ub_l0                   ; an insert: again
        sta     cl
        sta     al
        lda     ub_c0
        sta     cc
        sta     ac
        jsr     ub_text
        lda     ub_n
        jsr     inst
        jsr     anchor0                 ; (the cursor after it)
        bra     @n
@del:   lda     ub_l0                   ; a delete: again
        sta     al
        lda     ub_c0
        sta     ac
        lda     ub_l1
        sta     cl
        lda     ub_c1
        sta     cc
        jsr     delsel
@n:     lda     ub_n
        clc
        adc     #14
        adc     ub_top
        sta     ub_top
        cmp     ub_end
        bcs     ub_done
        tay
        lda     [ub],y
        xba
        and     #UF_JOIN
        bne     @l
        ; fall through
; after undo / redo: recording again; modified unless back at the saved state
ub_done:
        lda     #1
        sta     ub_rec
        lda     ub_top
        cmp     ub_save
        bne     :+
        lda     emod
        beq     :+
        stz     emod
        jmp     settitle
:       rts

; isrc = the text of record ub_r
ub_text:
        lda     ub_r
        clc
        adc     #12
        sta     isrc
        lda     z:ub+2
        sta     isrc+2
        rts

; (inst) insert A bytes from isrc (a long pointer; LF = a line break) at the cursor; the
; cursor ends after them. Returns C set if something did not fit (lines, memory).
inst0:   sta     itn
        stz     ierr
        lda     isrc                    ; one line? straight in
        sta     z:sp
        lda     isrc+2
        sta     z:sp+2
        ldy     #0
:       cpy     itn
        bcs     @one
        lda     [sp],y
        and     #$00FF
        cmp     #10
        beq     @multi
        iny
        bra     :-
@one:   lda     cl
        jsr     lget
        lda     itn
        ldx     cc
        jsr     ins_bytes
        bcs     @err
        lda     cc
        clc
        adc     itn
        sta     cc
        clc
        rts
@err:   jsr     ui_beep
        sec
        rts
@multi: lda     cl                      ; the tail of the line -> TB
        jsr     lget
        lda     llen
        sec
        sbc     cc
        sta     itail
        lda     z:lp
        clc
        adc     cc
        sta     z:sp
        lda     z:lp+2
        sta     z:sp+2
        stz     z:dp
        lda     tbank
        sta     z:dp+2
        ldy     #4
        ldx     itail
        beq     :++
        sep     #$20
        .a8
:       lda     [sp],y
        phy
        dey
        dey
        dey
        dey
        sta     [dp],y
        ply
        iny
        dex
        bne     :-
        rep     #$20
        .a16
:       lda     cc
        sta     llen
        ldy     #2
        sta     [lp],y
        lda     cl                      ; (cut there: changed)
        ldx     cc
        jsr     lc_chg
        stz     ipos
@run:   jsr     runlen                  ; the run up to the next LF
        sta     irun
        stz     iforce
        lda     cl
        jsr     lget
        lda     #MAXLEN                 ; room in this line?
        sec
        sbc     llen
        cmp     irun
        bcs     :+
        sta     irun
        inc     iforce
:       lda     irun
        beq     :+
        ldx     llen
        jsr     ins_bytes
        bcs     @nomem
        lda     ipos
        clc
        adc     irun
        sta     ipos
:       lda     iforce                  ; a line break: LF, or a full line
        bne     @brk
        lda     ipos
        cmp     itn
        bcs     @tail
        inc     ipos                    ; (the LF)
@brk:   lda     nl
        cmp     #MAXLINES
        bcs     @nomem
        jsr     runlen                  ; a block for the next run
        cmp     #MAXLEN
        bcc     :+
        lda     #MAXLEN
:       clc
        adc     #8
        jsr     halloc
        bcs     @nomem
        lda     cl
        inc     a
        sta     cl
        jsr     tins
        lda     cl
        jsr     lset
        lda     ipos
        cmp     itn
        jcc     @run
        lda     iforce                  ; (a forced break at the very end: done)
        jeq     @run
        bra     @tail
@nomem: inc     ierr
@tail:  lda     cl                      ; the old tail back, after the cursor
        jsr     lget
        lda     llen
        sta     cc
        stz     z:sp
        lda     tbank
        sta     z:sp+2
        lda     itail
        beq     :+
        ldx     llen
        jsr     ins_bytes
        bcc     :+
        inc     ierr
:       lda     ierr
        beq     :+
        jsr     ui_beep
        sec
        rts
:       clc
        rts

; the length of the run at isrc + ipos up to the next LF (or itn) -> A; sp = its start
runlen: lda     isrc
        clc
        adc     ipos
        sta     z:sp
        lda     isrc+2
        sta     z:sp+2
        ldy     #0
:       tya
        clc
        adc     ipos
        cmp     itn
        bcs     :+
        lda     [sp],y
        and     #$00FF
        cmp     #10
        beq     :+
        iny
        bra     :-
:       tya
        rts

; the selection, ordered -> s0l:s0c .. s1l:s1c; C set if there is one
selord: lda     cl
        cmp     al
        bcc     @cfirst
        bne     @afirst
        lda     cc
        cmp     ac
        beq     @none
        bcc     @cfirst
@afirst:
        lda     al
        sta     s0l
        lda     ac
        sta     s0c
        lda     cl
        sta     s1l
        lda     cc
        sta     s1c
        sec
        rts
@cfirst:
        lda     cl
        sta     s0l
        lda     cc
        sta     s0c
        lda     al
        sta     s1l
        lda     ac
        sta     s1c
        sec
        rts
@none:  clc
        rts

; (delsel) delete the selection (if any); the cursor at its start
delsel0:
        jsr     selord
        bcs     :+
        rts
:       jsr     setmod
        lda     s0l
        cmp     s1l
        bne     @multi
        jsr     lget
        lda     s1c
        sec
        sbc     s0c
        ldx     s0c
        jsr     del_bytes
        bra     @cur
@multi: lda     s1l                     ; the tail of the last line -> TB
        jsr     lget
        lda     llen
        sec
        sbc     s1c
        sta     itail
        lda     z:lp
        clc
        adc     s1c
        sta     z:sp
        lda     z:lp+2
        sta     z:sp+2
        stz     z:dp
        lda     tbank
        sta     z:dp+2
        ldy     #4
        ldx     itail
        beq     :++
        sep     #$20
        .a8
:       lda     [sp],y
        phy
        dey
        dey
        dey
        dey
        sta     [dp],y
        ply
        iny
        dex
        bne     :-
        rep     #$20
        .a16
:       lda     s0l                     ; the first line cut, the tail appended
        jsr     lget
        lda     s0c
        sta     llen
        ldy     #2
        sta     [lp],y
        stz     z:sp
        lda     tbank
        sta     z:sp+2
        lda     itail
        ldx     llen
        jsr     ins_bytes
        lda     s1l                     ; the lines between and the last one go
        sec
        sbc     s0l
        tax
        lda     s0l
        inc     a
        jsr     tdel
@cur:   lda     s0l
        sta     cl
        sta     al
        lda     s0c
        sta     cc
        sta     ac
        rts


; ---------------------------------------------------------------- clipboard
; the selection -> the system clipboard (lines joined with LF; at most 65535 bytes)
copysel:
        jsr     selord
        bcs     :+
        rts
:       stz     z:dp
        lda     sbank
        sta     z:dp+2
        stz     cpn
        lda     s0l
        sta     cpi
@l:     lda     cpi
        jsr     lget
        stz     z:t0                    ; from
        lda     cpi
        cmp     s0l
        bne     :+
        lda     s0c
        sta     z:t0
:       lda     llen                    ; to
        sta     z:t1
        lda     cpi
        cmp     s1l
        bne     :+
        lda     s1c
        sta     z:t1
:       lda     z:t0
        clc
        adc     #4
        tay
        ldx     cpn
@c:     tya
        sec
        sbc     #4
        cmp     z:t1
        bcs     @le
        cpx     #$FFFF
        bcs     @full
        lda     [lp],y
        phy
        txy
        sep     #$20
        .a8
        sta     [dp],y
        rep     #$20
        .a16
        ply
        iny
        inx
        bra     @c
@le:    lda     cpi
        cmp     s1l
        bcs     @put
        cpx     #$FFFF
        bcs     @full
        lda     #10
        txy
        sep     #$20
        .a8
        sta     [dp],y
        rep     #$20
        .a16
        inx
        stx     cpn
        inc     cpi
        bra     @l
@full:  phx
        jsr     ui_beep                 ; (too much: the first 65535 bytes)
        plx
@put:   stx     cpn
        stz     cblk
        lda     sbank
        sta     cblk+2
        lda     cpn
        sta     cblk+3
        ptr     cblk
        sys     SYS_CLPUT
        rts

; the clipboard -> inserted at the cursor (replacing the selection)
paste:  stz     cblk
        lda     sbank
        sta     cblk+2
        lda     #$FFFF
        sta     cblk+3
        ptr     cblk
        sys     SYS_CLGET
        bcs     @out
        cmp     #0
        beq     @out
        stz     crhold
        jsr     crfilter
        sta     z:t5
        jsr     delsel
        jsr     setmod
        stz     isrc
        lda     sbank
        sta     isrc+2
        lda     z:t5
        jsr     inst
        jsr     anchor0
        jsr     setgoal
@out:   rts
anchor0:
        lda     cl
        sta     al
        lda     cc
        sta     ac
        rts

; A bytes at SB:0 with each CR before an LF removed -> A = the new count (crfin: a CR
; held at the end when more follows)
crfilter:
        sta     crn
        stz     z:sp
        lda     sbank
        sta     z:sp+2
        ldy     #0                      ; Y reads, X writes
        ldx     #0
@l:     cpy     crn
        bcs     @out
        lda     [sp],y
        and     #$00FF
        cmp     #13
        bne     @keep
        iny                             ; CR: an LF next?
        cpy     crn
        bcs     @last
        lda     [sp],y
        and     #$00FF
        cmp     #10
        bne     @cr
        lda     #1
        sta     crlf
        bra     @l
@last:  lda     crhold                  ; the last byte: hold it if more follows
        beq     @cr
        lda     #2
        sta     crhold
        bra     @out
@cr:    dey
        lda     #13
@keep:  phy
        txy
        sep     #$20
        .a8
        sta     [sp],y
        rep     #$20
        .a16
        ply
        inx
        iny
        bra     @l
@out:   txa
        rts


        .segment "BSS"
lnum:   .res    2
llen:   .res    2
lcap:   .res    2
hbn:    .res    2
hcur:   .res    2
hoff:   .res    2
hcap:   .res    2
hsize:  .res    2
hretry: .res    2
incomp: .res    2
hb:     .res    MAXHB * 4 + 4
ohb:    .res    MAXHB * 4 + 4
ohbn:   .res    2
cpi:    .res    2
cpn:    .res    2
cplen:  .res    2
gcap:   .res    2
in_n:   .res    2
in_c:   .res    2
in_len: .res    2
itn:    .res    2
itail:  .res    2
ipos:   .res    2
irun:   .res    2
iforce: .res    2
ierr:   .res    2
isrc:   .res    4
insrc:  .res    4
rblk:   .res    6
cblk:   .res    6
tn_l:   .res    2
tn_n:   .res    2
s0l:    .res    2
s0c:    .res    2
s1l:    .res    2
s1c:    .res    2
ub_top: .res    2                       ; undo: the stack's end, the redo part's end
ub_end: .res    2
ub_save: .res   2                       ; ub_top when the text was saved (NONE: lost)
ub_grp: .res    2                       ; 1: this action made a change already
ub_mrg: .res    2                       ; typing / Backspace / Delete (UF_*): may add to the top
ub_w:   .res    2
ub_r:   .res    2
ub_k:   .res    2
ub_l0:  .res    2
ub_c0:  .res    2
ub_l1:  .res    2
ub_c1:  .res    2
ub_n:   .res    2
u_l0:   .res    2
u_c0:   .res    2
u_l1:   .res    2
u_c1:   .res    2
u_n:    .res    2
u_sz:   .res    2
wc_tot: .res    4                       ; the words of the text
wc_i:   .res    2
wc_j:   .res    2
wc_n:   .res    2
wc_hi:  .res    2
wc_loc: .res    2                       ; one line: the run wc_a .. wc_b, its words wc_old
wc_a:   .res    2
wc_b:   .res    2
wc_old: .res    2
