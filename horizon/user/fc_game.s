; fc_game.s - FreeCell's rules (included by freecell.s).
; A card c: suit c / 13 (clubs 0, diamonds 1, hearts 2, spades 3), rank c mod 13 (ace 0 ..
; king 12); diamonds and hearts are red. Piles: free cells 0-3, foundations 4-7 (pile 4 + s
; holds suit s, ace first), columns 8-15; pcnt (words) their counts, pcards PMAX bytes each.
; The deal: this game's own generator (xorshift32, seeded from the game number and stirred),
; a Fisher-Yates shuffle, then the 52 cards one by one across the eight columns (7, 7, 7, 7,
; 6, 6, 6, 6). The history: 4 bytes a move in the places' bank from HBASE {source,
; destination, count, flags}; MF_AUTO marks a move the program made after the one before it,
; so one undo takes back a move with the cards that went home after it.

; A = pile -> X = the offset of its cards in pcards (pile * PMAX; keeps Y)
pofs:   asl     a
        sta     z:t7
        asl     a
        asl     a
        clc
        adc     z:t7
        asl     a
        tax
        rts

; A = pile -> A = its top card, $FFFF when empty (keeps Y)
ptop:   pha
        asl     a
        tax
        lda     pcnt,x
        beq     @e
        dec     a
        sta     z:t6
        pla
        jsr     pofs
        txa
        clc
        adc     z:t6
        tax
        lda     pcards,x
        and     #$00FF
        rts
@e:     pla
        lda     #$FFFF
        rts

; ---------------------------------------------------------------- the deal
deal:   lda     game_no
        eor     #$5A3C
        sta     rng
        lda     game_no
        eor     #$C3A5
        sta     rng+2
        ldx     #10                     ; (stirred)
:       phx
        jsr     rand16
        plx
        dex
        bne     :-
        ldx     #0                      ; the deck in order
        sep     #$20
        .a8
:       txa
        sta     deck,x
        inx
        cpx     #52
        bcc     :-
        rep     #$20
        .a16
        lda     #51                     ; shuffled: i = 51 .. 1 changes place with 0 .. i
        sta     z:g0
@sh:    lda     z:g0
        inc     a
        jsr     rand_below
        tax
        ldy     z:g0
        sep     #$20
        .a8
        lda     deck,x
        pha
        lda     deck,y
        sta     deck,x
        pla
        sta     deck,y
        rep     #$20
        .a16
        dec     z:g0
        bne     @sh
        jsr     clearpiles
        stz     z:g0                    ; card j to column j mod 8
@d:     lda     z:g0
        and     #7
        clc
        adc     #P_CASC
        jsr     pushcard_deck
        inc     z:g0
        lda     z:g0
        cmp     #52
        bcc     @d
        rts

; every pile empty, a new game's counters
clearpiles:
        ldx     #2 * NP - 2
:       stz     pcnt,x
        dex
        dex
        bpl     :-
        stz     moves
        stz     hcount
        stz     won
        rts

; A = pile: deck[g0] put on it
pushcard_deck:
        ldx     z:g0
        pha
        lda     deck,x
        and     #$00FF
        tay
        pla
; A = pile, Y = card: put on it
pushcard:
        sta     z:t5
        sty     z:t4
        asl     a
        tax
        lda     pcnt,x
        pha
        inc     a
        sta     pcnt,x
        lda     z:t5
        jsr     pofs
        txa
        clc
        adc     1,s
        tax
        pla
        lda     z:t4
        sep     #$20
        .a8
        sta     pcards,x
        rep     #$20
        .a16
        rts

; the test position (-w): the jacks home, a queen on each king in four columns but one,
; the fourth queen alone: one move of it onto the red king, and the rest goes home
testpos:
        stz     game_no
        jsr     clearpiles
        ldx     #6                      ; the foundations: ace .. jack of each suit
:       lda     #11
        sta     pcnt+2*P_FOUND,x
        dex
        dex
        bpl     :-
        ldx     #0
@f:     txa                             ; (their cards: pile 4 + s, card s * 13 + k)
        pha
        lda     #0
        sta     z:g1
@k:     pla
        pha
        sta     z:t0
        asl     a
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:t0
        sbc     z:t0
        sbc     z:t0                    ; s * 13
        clc
        adc     z:g1
        sta     z:t1
        pla
        pha
        clc
        adc     #P_FOUND
        jsr     pofs
        txa
        clc
        adc     z:g1
        tax
        lda     z:t1
        sep     #$20
        .a8
        sta     pcards,x
        rep     #$20
        .a16
        inc     z:g1
        lda     z:g1
        cmp     #11
        bcc     @k
        plx
        inx
        cpx     #4
        bcc     @f
        ldx     #0                      ; the columns: pairs from tpos
:       phx
        lda     tpos+1,x
        and     #$00FF
        tay
        lda     tpos,x
        and     #$00FF
        jsr     pushcard
        plx
        inx
        inx
        cpx     #TPOSN
        bcc     :-
        rts
        .segment "RODATA"
; {pile, card}: K hearts, Q clubs | K diamonds | K clubs, Q hearts | K spades, Q diamonds |
; Q spades (to go onto the king of diamonds)
tpos:   .byte   P_CASC, 2 * 13 + 12, P_CASC, 0 * 13 + 11
        .byte   P_CASC + 1, 1 * 13 + 12
        .byte   P_CASC + 2, 0 * 13 + 12, P_CASC + 2, 2 * 13 + 11
        .byte   P_CASC + 3, 3 * 13 + 12, P_CASC + 3, 1 * 13 + 11
        .byte   P_CASC + 5, 3 * 13 + 11
TPOSN = * - tpos
        .segment "CODE"

; xorshift32 (rng): x ^= x << 13, x ^= x >> 17, x ^= x << 5 -> A = its two halves mixed
rand16: lda     rng
        sta     z:t0
        lda     rng+2
        sta     z:t1
        ldx     #13
:       asl     z:t0
        rol     z:t1
        dex
        bne     :-
        lda     rng
        eor     z:t0
        sta     rng
        lda     rng+2
        eor     z:t1
        sta     rng+2
        lsr     a                       ; >> 17: the high half >> 1 into the low half
        eor     rng
        sta     rng
        sta     z:t0
        lda     rng+2
        sta     z:t1
        ldx     #5
:       asl     z:t0
        rol     z:t1
        dex
        bne     :-
        lda     rng
        eor     z:t0
        sta     rng
        lda     rng+2
        eor     z:t1
        sta     rng+2
        eor     rng
        rts

; A = n (1-65535) -> A = 0 .. n - 1: (a random 16-bit number * n) >> 16
rand_below:
        sta     z:t2
        jsr     rand16
        sta     z:t3
        stz     z:t4
        stz     z:t5
        ldx     #16
:       asl     z:t5
        rol     z:t4
        asl     z:t3
        bcc     :+
        lda     z:t5
        clc
        adc     z:t2
        sta     z:t5
        lda     z:t4
        adc     #0
        sta     z:t4
:       dex
        bne     :--
        lda     z:t4
        rts

; ---------------------------------------------------------------- moves
; A = 1 when the destination is an empty column -> A = the cards a run may have:
; (empty free cells + 1) * 2 ^ (empty columns, not counting the destination)
maxmove:
        sta     z:t3
        lda     #1
        sta     z:t4
        ldx     #0
@c:     lda     pcnt,x
        bne     :+
        inc     z:t4
:       inx
        inx
        cpx     #8
        bcc     @c
        stz     z:t5
        ldx     #2 * P_CASC
@e:     lda     pcnt,x
        bne     :+
        inc     z:t5
:       inx
        inx
        cpx     #2 * NP
        bcc     @e
        lda     z:t5
        sec
        sbc     z:t3
        bpl     :+
        lda     #0
:       tax
        lda     z:t4
@s:     cpx     #0
        beq     @out
        asl     a
        dex
        bra     @s
@out:   rts

; ms, mi: the cards from mi up are a run (each one lower than the one under it, the other
; colour) -> C
runok:  lda     z:ms
        asl     a
        tax
        lda     pcnt,x
        sec
        sbc     z:mi
        beq     @nop2
        bmi     @nop2
        tay
        lda     z:ms
        jsr     pofs
        txa
        clc
        adc     z:mi
        tax
@n:     dey
        beq     @yes
        lda     pcards+1,x
        and     #$00FF
        sta     z:t0
        lda     pcards,x
        and     #$00FF
        sta     z:t1
        phx
        ldx     z:t0
        lda     cred,x
        ldx     z:t1
        eor     cred,x
        and     #$00FF
        beq     @nop
        ldx     z:t0
        lda     crank,x
        and     #$00FF
        inc     a
        ldx     z:t1
        eor     crank,x
        and     #$00FF
        bne     @nop
        plx
        inx
        bra     @n
@yes:   sec
        rts
@nop:   plx
@nop2:  clc
        rts

; ms, mi, md: may the cards from mi of pile ms go to pile md? -> C set; mn = the count, mc
; = the first card moved
can_move:
        lda     z:ms
        cmp     z:md
        jeq     @no
        cmp     #NP
        jcs     @no
        cmp     #P_FOUND                ; never from a foundation
        bcc     :+
        cmp     #P_CASC
        jcc     @no
:       lda     z:md
        cmp     #NP
        jcs     @no
        lda     z:ms
        asl     a
        tax
        lda     pcnt,x
        sec
        sbc     z:mi
        jeq     @no
        jmi     @no
        sta     z:mn
        jsr     runok
        jcc     @no
        lda     z:ms
        jsr     pofs
        txa
        clc
        adc     z:mi
        tax
        lda     pcards,x
        and     #$00FF
        sta     z:mc
        lda     z:md
        cmp     #P_FOUND
        bcs     @nc
        lda     z:mn                    ; a free cell: one card, empty
        cmp     #1
        bne     @no
        lda     z:md
        asl     a
        tax
        lda     pcnt,x
        bne     @no
        sec
        rts
@nc:    cmp     #P_CASC
        bcs     @cas
        lda     z:mn                    ; a foundation: one card of its suit, the next rank
        cmp     #1
        bne     @no
        ldx     z:mc
        lda     csuit,x
        and     #$00FF
        clc
        adc     #P_FOUND
        cmp     z:md
        bne     @no
        lda     z:md
        asl     a
        tax
        lda     pcnt,x
        ldx     z:mc
        sep     #$20
        .a8
        cmp     crank,x
        rep     #$20
        .a16
        bne     @no
        sec
        rts
@cas:   lda     z:md                    ; a column
        jsr     ptop
        cmp     #$FFFF
        bne     @onto
        lda     #1                      ; empty
        jsr     maxmove
        cmp     z:mn
        bcc     @no
        sec
        rts
@onto:  tax                             ; on card t: one rank lower, the other colour
        lda     crank,x
        and     #$00FF
        sta     z:t6
        lda     cred,x
        ldx     z:mc
        eor     cred,x
        and     #$00FF
        beq     @no
        lda     crank,x
        and     #$00FF
        inc     a
        cmp     z:t6
        bne     @no
        lda     #0
        jsr     maxmove
        cmp     z:mn
        bcc     @no
        sec
        rts
@no:    clc
        rts

; the move checked by can_move (ms, mi, md, mn), flags mf: done and recorded
do_move:
        lda     z:md
        asl     a
        tax
        lda     pcnt,x
        sta     z:t2                    ; where they go in md
        clc
        adc     z:mn
        sta     pcnt,x
        lda     z:ms
        asl     a
        tax
        lda     z:mi
        sta     pcnt,x
        lda     z:ms
        ldy     z:mi
        jsr     mvcards
        jsr     hpush
        inc     moves
        rts

; mn cards from index Y of pile A to index t2 of pile md
mvcards:
        jsr     pofs
        txa
        clc
        adc     z:mi
        sta     z:t0
        tya
        sec
        sbc     z:mi                    ; (Y may differ from mi: undo)
        clc
        adc     z:t0
        sta     z:t0
        lda     z:md
        jsr     pofs
        txa
        clc
        adc     z:t2
        tay
        ldx     z:t0
        lda     z:mn
        sta     z:t1
        sep     #$20
        .a8
:       lda     pcards,x
        sta     pcards,y
        inx
        iny
        dec     z:t1
        bne     :-
        rep     #$20
        .a16
        rts

; the move ms, md, mn, mf into the history
hpush:  lda     hcount
        cmp     #HMAX
        bcs     @out
        jsr     hrec
        sep     #$20
        .a8
        lda     z:ms
        sta     [hp]
        ldy     #1
        lda     z:md
        sta     [hp],y
        iny
        lda     z:mn
        sta     [hp],y
        iny
        lda     z:mf
        sta     [hp],y
        rep     #$20
        .a16
        inc     hcount
@out:   rts
; A = record -> hp
hrec:   asl     a
        asl     a
        clc
        adc     #HBASE
        sta     z:hp
        lda     xbank
        sta     z:hp+2
        rts

; the last move taken back -> C set (ms, md, mn, mf: that move), C clear: none
undo1:  lda     hcount
        bne     :+
        clc
        rts
:       dec     a
        sta     hcount
        jsr     hrec
        lda     [hp]
        tax
        and     #$00FF
        sta     z:ms
        txa
        xba
        and     #$00FF
        sta     z:md
        ldy     #2
        lda     [hp],y
        tax
        and     #$00FF
        sta     z:mn
        txa
        xba
        and     #$00FF
        sta     z:mf
        lda     z:md                    ; the top mn cards of md back onto ms
        asl     a
        tax
        lda     pcnt,x
        sec
        sbc     z:mn
        sta     pcnt,x
        sta     z:g1                    ; (their index in md)
        lda     z:ms
        asl     a
        tax
        lda     pcnt,x
        sta     z:t2
        clc
        adc     z:mn
        sta     pcnt,x
        lda     z:ms                    ; (mvcards copies from A to md: swapped here)
        pha
        lda     z:md
        sta     z:ms
        pla
        sta     z:md
        lda     z:g1
        sta     z:mi
        lda     z:ms
        ldy     z:mi
        jsr     mvcards
        lda     z:ms                    ; (back as recorded)
        pha
        lda     z:md
        sta     z:ms
        pla
        sta     z:md
        dec     moves
        sec
        rts

; ---------------------------------------------------------------- going home by itself
; card A: may it go home without harm? An ace or a two always; else when both foundations
; of the other colour hold its rank - 1 (nothing could want to go onto it any more)
safe:   tax
        lda     crank,x
        and     #$00FF
        cmp     #2
        bcc     @yes
        sta     z:t0
        lda     csuit,x
        and     #$00FF
        tay
        lda     opp1,y
        and     #$00FF
        asl     a
        tax
        lda     pcnt+2*P_FOUND,x
        cmp     z:t0
        bcc     @no
        lda     opp2,y
        and     #$00FF
        asl     a
        tax
        lda     pcnt+2*P_FOUND,x
        cmp     z:t0
        bcc     @no
@yes:   sec
        rts
@no:    clc
        rts

; a card that may and should go home now -> C set, ms, mi, md, mn (cells first, then the
; columns from the left)
auto_pick:
        stz     z:g0
@p:     lda     z:g0
        cmp     #P_FOUND
        bne     :+
        lda     #P_CASC
        sta     z:g0
:       lda     z:g0
        jsr     ptop
        cmp     #$FFFF
        beq     @n
        sta     z:g1
        tax
        lda     csuit,x
        and     #$00FF
        asl     a
        tay
        lda     pcnt+2*P_FOUND,y        ; its rank is the next one there?
        sep     #$20
        .a8
        cmp     crank,x
        rep     #$20
        .a16
        bne     @n
        lda     z:g1
        jsr     safe
        bcc     @n
        lda     z:g0
        sta     z:ms
        asl     a
        tax
        lda     pcnt,x
        dec     a
        sta     z:mi
        ldx     z:g1
        lda     csuit,x
        and     #$00FF
        clc
        adc     #P_FOUND
        sta     z:md
        jmp     can_move
@n:     inc     z:g0
        lda     z:g0
        cmp     #NP
        bcc     @p
        clc
        rts

; -> C set when every card is home
all_home:
        ldx     #6
:       lda     pcnt+2*P_FOUND,x
        cmp     #13
        bne     @no
        dex
        dex
        bpl     :-
        sec
        rts
@no:    clc
        rts

; -> A = 1 when no move is left: no empty cell or column, and no top card may go home or
; onto another column (then only single cards could move)
isstuck:
        ldx     #0
:       lda     pcnt,x
        beq     @no
        inx
        inx
        cpx     #8
        bcc     :-
        ldx     #2 * P_CASC
:       lda     pcnt,x
        beq     @no
        inx
        inx
        cpx     #2 * NP
        bcc     :-
        stz     z:g2                    ; every top card to every foundation and column
@s:     lda     z:g2
        cmp     #P_FOUND
        bne     :+
        lda     #P_CASC
        sta     z:g2
:       lda     #P_FOUND
        sta     z:g3
@d:     lda     z:g2
        sta     z:ms
        asl     a
        tax
        lda     pcnt,x
        dec     a
        sta     z:mi
        lda     z:g3
        sta     z:md
        jsr     can_move
        bcs     @no
        inc     z:g3
        lda     z:g3
        cmp     #NP
        bcc     @d
        inc     z:g2
        lda     z:g2
        cmp     #NP
        bcc     @s
        lda     #1
        rts
@no:    lda     #0
        rts
