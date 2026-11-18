; fc_test.s - FreeCell's self test (included by freecell.s): "freecell -t", no window. The
; output is compared with tests/freecell-t.txt by make test.
;   1. the deals of games 1 and 65535 (every card once; the columns printed)
;   2. the run limit: (free cells + 1) * 2 ^ empty columns, one column less for an empty
;      destination
;   3. the rules on a made position: columns, cells, foundations, runs
;   4. the safe rule (what goes home by itself)
;   5. the test position (-w): one move, then everything home by the safe rule
;   6. random play: legal moves on ten deals, every card once after each, then all undone
;      back to the deal

test_run:
        stz     tfail
        print   "FREECELL TEST START\n"
        ; 1. deals
        lda     #1
        jsr     t_deal
        lda     #65535
        jsr     t_deal
        ; 2. the run limit
        print   "run limit (free cells, empty columns: to a column, to an empty one):\n"
        stz     z:g4                    ; free cells
@lf:    stz     z:g5                    ; empty columns
@le:    jsr     clearpiles
        lda     #4
        sec
        sbc     z:g4
        asl     a
        tax
:       dex
        dex
        bmi     :+
        lda     #1
        sta     pcnt,x
        bra     :-
:       lda     #8
        sec
        sbc     z:g5
        asl     a
        tax
:       dex
        dex
        bmi     :+
        lda     #1
        sta     pcnt+2*P_CASC,x
        bra     :-
:       print   "  "
        lda     z:g4
        jsr     put_dec
        print   ", "
        lda     z:g5
        jsr     put_dec
        print   ": "
        lda     #0
        jsr     maxmove
        jsr     put_dec
        lda     z:g5
        beq     :+
        print   ", "
        lda     #1
        jsr     maxmove
        jsr     put_dec
:       jsr     put_nl
        inc     z:g5
        lda     z:g5
        cmp     #4
        jcc     @le
        inc     z:g4
        lda     z:g4
        cmp     #5
        jcc     @lf
        ; 3. the rules
        jsr     t_rules
        ; 4. the safe rule
        jsr     t_safe
        ; 5. the test position
        jsr     testpos
        lda     #P_CASC + 5             ; the queen of spades onto the king of diamonds
        sta     z:ms
        stz     z:mi
        lda     #P_CASC + 1
        sta     z:md
        jsr     can_move
        bcs     :+
        jsr     t_fail
:       stz     z:mf
        jsr     do_move
        stz     tcnt
:       jsr     auto_pick
        bcc     :+
        lda     #MF_AUTO
        sta     z:mf
        jsr     do_move
        inc     tcnt
        bra     :-
:       jsr     all_home
        bcs     :+
        jsr     t_fail
        print   "FAIL test position: not won\n"
        bra     :++
:       print   "PASS test position: one move, then "
        lda     tcnt
        jsr     put_dec
        print   " cards home by themselves: won\n"
:       ; 6. random play
        jsr     t_random
        print   "FREECELL TEST END: "
        lda     tfail
        jsr     put_dec
        print   " failed\n"
        exit    0

t_fail: inc     tfail
        rts

; A = game: dealt, checked (every card once), printed
t_deal: sta     game_no
        jsr     deal
        print   "game "
        lda     game_no
        jsr     put_dec
        print   ":\n"
        jsr     t_check
        bcs     :+
        print   "FAIL the deal: not every card once\n"
        jsr     t_fail
:       lda     #P_CASC
        sta     z:g0
@c:     print   " "
        lda     z:g0
        asl     a
        tax
        lda     pcnt,x
        sta     z:g2
        lda     z:g0
        jsr     pofs
        stx     z:g1
:       print   " "
        ldx     z:g1
        lda     pcards,x
        jsr     t_cname
        inc     z:g1
        dec     z:g2
        bne     :-
        jsr     put_nl
        inc     z:g0
        lda     z:g0
        cmp     #NP
        bcc     @c
        rts

; A = card: printed ("AC", "TD", "QH", "KS")
t_cname: and     #$00FF
        tax
        lda     crank,x
        and     #$00FF
        tay
        lda     csuit,x
        and     #$00FF
        pha
        lda     t_rch,y
        and     #$00FF
        jsr     put_char
        ply
        lda     t_sch,y
        and     #$00FF
        jmp     put_char

; every card in the piles exactly once, no pile over PMAX -> C set
t_check:
        ldx     #50                     ; tseen: 52 bytes of 0
:       stz     deck,x
        dex
        dex
        bpl     :-
        stz     z:t0                    ; cards counted
        stz     z:g2
@p:     lda     z:g2
        asl     a
        tax
        lda     pcnt,x
        cmp     #PMAX + 1
        bcs     @no
        sta     z:t1
        cmp     #0
        beq     @n
        lda     z:g2
        jsr     pofs
@c:     lda     pcards,x
        and     #$00FF
        cmp     #52
        bcs     @no
        tay
        lda     deck,y
        and     #$00FF
        bne     @no
        sep     #$20
        .a8
        lda     #1
        sta     deck,y
        rep     #$20
        .a16
        inc     z:t0
        inx
        dec     z:t1
        bne     @c
@n:     inc     z:g2
        lda     z:g2
        cmp     #NP
        bcc     @p
        lda     z:t0
        cmp     #52
        bne     @no
        sec
        rts
@no:    clc
        rts

; a checksum of the piles (their counts and cards) -> A
t_sum:  stz     z:t5
        stz     z:g2
@p:     lda     z:g2
        asl     a
        tax
        lda     pcnt,x
        sta     z:t1
        jsr     @add
        lda     z:t1
        beq     @n
        lda     z:g2
        jsr     pofs
:       lda     pcards,x
        and     #$00FF
        jsr     @add
        inx
        dec     z:t1
        bne     :-
@n:     inc     z:g2
        lda     z:g2
        cmp     #NP
        bcc     @p
        lda     z:t5
        rts
@add:   inc     a                       ; t5 = t5 * 3 + A + 1
        clc
        adc     z:t5
        adc     z:t5
        adc     z:t5
        sta     z:t5
        rts

; 3. made positions: each case {piles..., then the move and the answer}
t_rules:
        ldx     #0
@case:  lda     trules,x
        and     #$00FF
        cmp     #$FF
        jeq     @out
        phx
        jsr     clearpiles
        plx
@put:   lda     trules,x                ; {pile, card} until pile $FE
        and     #$00FF
        cmp     #$FE
        beq     @mv
        phx
        pha
        lda     trules+1,x
        and     #$00FF
        tay
        pla
        jsr     pushcard
        plx
        inx
        inx
        bra     @put
@mv:    lda     trules+1,x              ; $FE, ms, mi, md, answer, the name (zero-ended)
        and     #$00FF
        sta     z:ms
        lda     trules+2,x
        and     #$00FF
        sta     z:mi
        lda     trules+3,x
        and     #$00FF
        sta     z:md
        lda     trules+4,x
        and     #$00FF
        sta     z:g4
        txa
        clc
        adc     #5
        sta     z:g5                    ; the name
        jsr     can_move
        lda     #0
        rol     a
        cmp     z:g4
        beq     :+
        jsr     t_fail
        print   "FAIL "
        bra     :++
:       print   "PASS "
:       lda     z:g5
        clc
        adc     #.loword(trules)
        tax
        ldy     pbank
        jsr     put_str
        jsr     put_nl
        ldx     z:g5                    ; past the name
:       lda     trules,x
        inx
        and     #$00FF
        bne     :-
        jmp     @case
@out:   rts

; 4. the safe rule: foundations set, a card, the answer
t_safe: ldx     #0
@c:     lda     tsafe,x
        and     #$00FF
        cmp     #$FF
        jeq     @out
        phx
        jsr     clearpiles
        plx
        ldy     #0
:       lda     tsafe,x
        and     #$00FF
        sta     pcnt+2*P_FOUND,y
        inx
        iny
        iny
        cpy     #8
        bcc     :-
        lda     tsafe+1,x
        and     #$00FF
        sta     z:g4
        lda     tsafe,x
        and     #$00FF
        sta     z:g3
        inx
        inx
        phx
        lda     z:g3
        jsr     safe
        lda     #0
        rol     a
        cmp     z:g4
        beq     :+
        jsr     t_fail
        print   "FAIL"
        bra     :++
:       print   "PASS"
:       print   " safe rule: "
        lda     z:g3
        jsr     t_cname
        print   " with foundations C"
        lda     pcnt+2*P_FOUND
        jsr     put_dec
        print   " D"
        lda     pcnt+2*P_FOUND+2
        jsr     put_dec
        print   " H"
        lda     pcnt+2*P_FOUND+4
        jsr     put_dec
        print   " S"
        lda     pcnt+2*P_FOUND+6
        jsr     put_dec
        lda     z:g4
        beq     :+
        print   ": goes home\n"
        bra     :++
:       print   ": stays\n"
:       plx
        jmp     @c
@out:   rts

; 6. random play: games 1-10, 300 tries of a random move each (taken when allowed), the
; piles checked after each move, then everything undone and compared with the deal
t_random:
        stz     z:g4                    ; moves made
        stz     z:g5                    ; refused tries
        stz     tcnt                    ; bad
        lda     #1
        sta     game_no
@g:     jsr     deal
        jsr     t_sum
        sta     tsum
        lda     #300
        sta     z:g3
@t:     lda     #NP                     ; ms: not a foundation, not empty
        jsr     rand_below
        cmp     #P_FOUND
        bcc     :+
        cmp     #P_CASC
        bcc     @t
:       sta     z:ms
        asl     a
        tax
        lda     pcnt,x
        beq     @t
        jsr     rand_below
        sta     z:mi
        lda     #NP                     ; the first destination from a random one that
        jsr     rand_below              ; takes them
        sta     z:md
        lda     #NP
        sta     z:g2
:       jsr     can_move
        bcs     :+
        inc     z:md
        lda     z:md
        and     #NP - 1
        sta     z:md
        dec     z:g2
        bne     :-
        inc     z:g5
        bra     @n
:       stz     z:mf
        jsr     do_move
        inc     z:g4
        jsr     t_check
        bcs     @n
        inc     tcnt
@n:     dec     z:g3
        bne     @t
:       jsr     undo1                   ; all undone
        bcs     :-
        jsr     t_sum
        cmp     tsum
        beq     :+
        inc     tcnt
:       lda     moves
        beq     :+
        inc     tcnt
:       inc     game_no
        lda     game_no
        cmp     #11
        jcc     @g
        lda     tcnt
        beq     :+
        jsr     t_fail
        print   "FAIL"
        bra     :++
:       print   "PASS"
:       print   " random play: 10 games, "
        lda     z:g4
        jsr     put_dec
        print   " moves, "
        lda     z:g5
        jsr     put_dec
        print   " refused, all undone back to the deal\n"
        rts

        .segment "RODATA"
t_rch:  .byte   "A23456789TJQK"
t_sch:  .byte   "CDHS"
; (cards by suit and rank: suit * 13 + rank - 1)
.define CARD(su, rk) (su * 13 + rk - 1)
CC = 0
CD = 1
CH_ = 2
CS = 3
; {pile, card} ..., $FE, ms, mi, md, answer (1 allowed), the name
trules:
        .byte   P_CASC, CARD(CS, 8), $FE, P_CASC + 1, 0, P_CASC, 0
        .byte   "nothing to move from an empty column", 0
        .byte   P_CASC, CARD(CS, 8), P_CASC + 1, CARD(CH_, 7), $FE, P_CASC + 1, 0, P_CASC, 1
        .byte   "a red 7 onto a black 8", 0
        .byte   P_CASC, CARD(CS, 8), P_CASC + 1, CARD(CC, 7), $FE, P_CASC + 1, 0, P_CASC, 0
        .byte   "a black 7 onto a black 8: refused", 0
        .byte   P_CASC, CARD(CS, 8), P_CASC + 1, CARD(CD, 6), $FE, P_CASC + 1, 0, P_CASC, 0
        .byte   "a red 6 onto a black 8: refused", 0
        .byte   P_CASC, CARD(CS, 8), P_CASC + 1, CARD(CH_, 9), $FE, P_CASC + 1, 0, P_CASC, 0
        .byte   "a red 9 onto a black 8: refused", 0
        .byte   P_CASC + 1, CARD(CH_, 7), $FE, P_CASC + 1, 0, 2, 1
        .byte   "a card into an empty free cell", 0
        .byte   P_CASC + 1, CARD(CH_, 7), 2, CARD(CC, 3), $FE, P_CASC + 1, 0, 2, 0
        .byte   "a card into a full free cell: refused", 0
        .byte   P_CASC + 1, CARD(CH_, 1), $FE, P_CASC + 1, 0, P_FOUND + CH_, 1
        .byte   "an ace onto its foundation", 0
        .byte   P_CASC + 1, CARD(CH_, 1), $FE, P_CASC + 1, 0, P_FOUND + CS, 0
        .byte   "an ace onto another suit's foundation: refused", 0
        .byte   P_CASC + 1, CARD(CH_, 2), $FE, P_CASC + 1, 0, P_FOUND + CH_, 0
        .byte   "a two onto an empty foundation: refused", 0
        .byte   P_FOUND + CH_, CARD(CH_, 1), P_CASC + 1, CARD(CH_, 2), $FE, P_CASC + 1, 0, P_FOUND + CH_, 1
        .byte   "a two onto its ace", 0
        .byte   P_FOUND + CH_, CARD(CH_, 1), $FE, P_FOUND + CH_, 0, P_CASC, 0
        .byte   "a card back from a foundation: refused", 0
        .byte   P_CASC, CARD(CS, 9), P_CASC, CARD(CH_, 8), P_CASC, CARD(CC, 7), $FE, P_CASC, 0, P_CASC + 1, 1
        .byte   "a run of 3 into an empty column (4 cells, 6 columns free)", 0
        .byte   P_CASC, CARD(CS, 9), P_CASC, CARD(CC, 8), P_CASC, CARD(CH_, 7), $FE, P_CASC, 0, P_CASC + 1, 0
        .byte   "not a run (two black cards): refused", 0
        .byte   P_CASC, CARD(CS, 9), P_CASC, CARD(CH_, 8), P_CASC, CARD(CC, 7), $FE, P_CASC, 1, P_CASC + 1, 1
        .byte   "the top two cards of a run", 0
        .byte   P_CASC, CARD(CS, 9), P_CASC, CARD(CH_, 8), P_CASC, CARD(CC, 7), P_CASC + 1, CARD(CD, 10), $FE, P_CASC, 0, P_CASC + 1, 1
        .byte   "a run of 3 onto a red 10", 0
        .byte   0, CARD(CC, 1), 1, CARD(CC, 2), 2, CARD(CC, 3), 3, CARD(CC, 4)
        .byte   P_CASC + 2, CARD(CC, 5), P_CASC + 3, CARD(CC, 5), P_CASC + 4, CARD(CC, 5), P_CASC + 5, CARD(CC, 5)
        .byte   P_CASC + 6, CARD(CC, 5), P_CASC + 7, CARD(CC, 5)
        .byte   P_CASC, CARD(CS, 9), P_CASC, CARD(CH_, 8), $FE, P_CASC, 0, P_CASC + 1, 0
        .byte   "no free cell, no other empty column: a run of 2 into the empty one refused", 0
        .byte   0, CARD(CC, 1), 1, CARD(CC, 2), 2, CARD(CC, 3), 3, CARD(CC, 4)
        .byte   P_CASC + 2, CARD(CC, 5), P_CASC + 3, CARD(CC, 5), P_CASC + 4, CARD(CC, 5), P_CASC + 5, CARD(CC, 5)
        .byte   P_CASC + 6, CARD(CC, 5), P_CASC + 7, CARD(CD, 10)
        .byte   P_CASC, CARD(CS, 9), P_CASC, CARD(CH_, 8), $FE, P_CASC, 1, P_CASC + 1, 1
        .byte   "no free cell: a single card into an empty column", 0
        .byte   1, CARD(CC, 2), 2, CARD(CC, 3), 3, CARD(CC, 4), P_CASC + 1, CARD(CC, 5)
        .byte   P_CASC + 2, CARD(CC, 5), P_CASC + 3, CARD(CC, 5), P_CASC + 4, CARD(CC, 5), P_CASC + 5, CARD(CC, 5)
        .byte   P_CASC + 6, CARD(CC, 5), P_CASC + 7, CARD(CD, 10)
        .byte   P_CASC, CARD(CS, 9), P_CASC, CARD(CH_, 8), P_CASC, CARD(CC, 7), $FE, P_CASC, 0, P_CASC + 7, 0
        .byte   "one free cell, no empty column: a run of 3 refused", 0
        .byte   1, CARD(CC, 2), 2, CARD(CC, 3), 3, CARD(CC, 4), P_CASC + 1, CARD(CC, 5)
        .byte   P_CASC + 2, CARD(CC, 5), P_CASC + 3, CARD(CC, 5), P_CASC + 4, CARD(CC, 5), P_CASC + 5, CARD(CC, 5)
        .byte   P_CASC + 6, CARD(CC, 5), P_CASC + 7, CARD(CC, 9)
        .byte   P_CASC, CARD(CS, 9), P_CASC, CARD(CH_, 8), P_CASC, CARD(CC, 7), $FE, P_CASC, 1, P_CASC + 7, 1
        .byte   "one free cell, no empty column: a run of 2 allowed", 0
        .byte   $FF
; foundations C D H S, card, answer
tsafe:  .byte   0, 0, 0, 0, CARD(CH_, 1), 1
        .byte   1, 0, 0, 0, CARD(CC, 2), 1
        .byte   2, 0, 0, 0, CARD(CC, 3), 0
        .byte   2, 2, 1, 0, CARD(CC, 3), 0
        .byte   2, 2, 2, 2, CARD(CC, 3), 1
        .byte   5, 4, 4, 5, CARD(CD, 5), 1
        .byte   5, 4, 3, 5, CARD(CD, 5), 1
        .byte   5, 4, 4, 3, CARD(CD, 5), 0
        .byte   11, 11, 11, 11, CARD(CS, 12), 1
        .byte   11, 11, 11, 12, CARD(CD, 13), 0
        .byte   12, 12, 12, 12, CARD(CD, 13), 1
        .byte   $FF
        .segment "CODE"
