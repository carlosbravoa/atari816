; sol_game.s - Solitaire's rules (included by solitair.s): the piles, dealing, legal moves,
; the move history (undo), scoring, the end of a game. No drawing here: every routine that
; changes piles sets their bits in `dirty` for the window side to redraw.
;
; A card is a byte: 0-51 = suit * 13 + rank (suits clubs, diamonds, hearts, spades; ranks
; ace 0 .. king 12), bit 7 set = face down. Piles (at most 16) hold up to PMAX cards each,
; the first one at the bottom.
;   Klondike: 0 stock, 1 waste, 2-5 foundations, 6-12 tableau.
;   FreeCell: 0-3 free cells, 4-7 foundations, 8-15 tableau.
;
; Deals: the deal number (1-65535) seeds a xorshift32 generator; the deck 0..51 is
; shuffled (Fisher-Yates from the top, j = rand(i + 1)) and dealt: Klondike row by row
; across the columns (column c gets c + 1 cards, the last face up), the other 24 to the
; stock; FreeCell card i to column i mod 8, all face up. tests/solitair_gen.py does the same.
;
; History: one 6-byte record per move in a bank of its own {u8 kind, src, dst, count, flags
; (bit 0: a tableau card was turned up), i8 score change}; kinds: 1 move, 2 draw (stock to
; waste), 3 the waste turned over to the stock. Undo replays a record backwards.
; Score (Klondike): + 10 a card to a foundation, - 10 one taken back, + 5 waste to tableau,
; + 5 a tableau card turned up, - 20 the waste turned over; never below 0.

PMAX    = 64                            ; cards a pile can hold (bytes in pcards)
DOWN    = $80                           ; a card face down
PT_STOCK = 1
PT_WASTE = 2
PT_FOUND = 3
PT_TAB  = 4
PT_CELL = 5
H_MOVE  = 1
H_DRAW  = 2
H_TURN  = 3
HSZ     = 6

        .segment "CODE"

; ---------------------------------------------------------------- piles
; A = pile -> A = its offset in pcards (keeps X, Y)
pofs:   and     #$00FF
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        rts

; A = pile -> A = its top card (with DOWN), C set if empty (keeps Y)
ptop:   and     #$00FF
        pha
        asl     a
        tax
        lda     pcnt,x
        beq     @e
        sta     z:g0
        pla
        jsr     pofs
        clc
        adc     z:g0
        tax
        lda     pcards-1,x
        and     #$00FF
        clc
        rts
@e:     pla
        sec
        rts

; A = pile, X = card: put it on top (keeps nothing)
ppush:  and     #$00FF
        stx     z:g1
        pha
        asl     a
        tax
        lda     pcnt,x
        inc     pcnt,x
        sta     z:g0
        pla
        jsr     pofs
        clc
        adc     z:g0
        tax
        lda     z:g1
        sep     #$20
        .a8
        sta     pcards,x
        rep     #$20
        .a16
        rts

; A = pile -> A = its top card, taken off
ppop:   and     #$00FF
        pha
        asl     a
        tax
        dec     pcnt,x
        lda     pcnt,x
        sta     z:g0
        pla
        jsr     pofs
        clc
        adc     z:g0
        tax
        lda     pcards,x
        and     #$00FF
        rts

; A = pile -> A = its type
ptyp:   and     #$00FF
        asl     a
        tax
        lda     ptype,x
        rts

; A = pile -> A = 1 << pile (the bit of dirty)
pbit:   and     #$00FF
        tax
        lda     #1
:       dex
        bmi     :+
        asl     a
        bra     :-
:       rts

; ---------------------------------------------------------------- the deal
; a new game: game, draw3, deal set -> the piles dealt, history, score, moves, time cleared
deal:   jsr     setpiles
        lda     deal_no                 ; the generator: deal * $9E3779B1 + $6D2B79F5
        sta     ia32
        stz     ia32+2
        lda     #$79B1
        sta     ib32
        lda     #$9E37
        sta     ib32+2
        jsr     mul32
        lda     r32
        clc
        adc     #$79F5
        sta     rng
        lda     r32+2
        adc     #$6D2B
        sta     rng+2
        ora     rng
        bne     :+
        inc     rng
:       ldx     #8
:       phx
        jsr     xorshift
        plx
        dex
        bne     :-
        ldx     #0                      ; the deck, shuffled
        sep     #$20
        .a8
:       txa
        sta     deck,x
        inx
        cpx     #52
        bcc     :-
        rep     #$20
        .a16
        lda     #51
        sta     z:g4
@sh:    lda     z:g4
        inc     a
        jsr     rand_n
        tay                             ; swap deck[i], deck[j]
        ldx     z:g4
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
        dec     z:g4
        bne     @sh
        stz     z:g4                    ; the next card
        lda     game
        bne     @fc
        stz     z:g5                    ; Klondike: row r, columns r .. 6
@row:   lda     z:g5
        sta     z:g6
@col:   ldx     z:g4
        lda     deck,x
        and     #$00FF
        ldy     z:g6
        cpy     z:g5
        beq     :+
        ora     #DOWN
:       tax
        lda     z:g6
        clc
        adc     #K_TAB
        jsr     ppush
        inc     z:g4
        inc     z:g6
        lda     z:g6
        cmp     #7
        bcc     @col
        inc     z:g5
        lda     z:g5
        cmp     #7
        bcc     @row
:       ldx     z:g4                    ; the stock: the rest, face down
        lda     deck,x
        and     #$00FF
        ora     #DOWN
        tax
        lda     #K_STOCK
        jsr     ppush
        inc     z:g4
        lda     z:g4
        cmp     #52
        bcc     :-
        bra     @done
@fc:    lda     z:g4                    ; FreeCell: card i to column i mod 8
        and     #7
        clc
        adc     #F_TAB
        pha
        ldx     z:g4
        lda     deck,x
        and     #$00FF
        tax
        pla
        jsr     ppush
        inc     z:g4
        lda     z:g4
        cmp     #52
        bcc     @fc
@done:  stz     hcount
        stz     score
        stz     moves
        stz     won
        lda     #$FFFF
        sta     dirty
        rts

; the piles of the game: types, none holding cards
setpiles:
        ldx     #2 * NPMAX - 2
:       stz     pcnt,x
        stz     ptype,x
        dex
        dex
        bpl     :-
        lda     game
        bne     @fc
        lda     #13
        sta     npiles
        lda     #PT_STOCK
        sta     ptype + 2 * K_STOCK
        lda     #PT_WASTE
        sta     ptype + 2 * K_WASTE
        ldx     #2 * K_FOUND
        ldy     #4
        lda     #PT_FOUND
        jsr     @set
        ldx     #2 * K_TAB
        ldy     #7
        lda     #PT_TAB
        jmp     @set
@fc:    lda     #16
        sta     npiles
        ldx     #2 * F_CELL
        ldy     #4
        lda     #PT_CELL
        jsr     @set
        ldx     #2 * F_FOUND
        ldy     #4
        lda     #PT_FOUND
        jsr     @set
        ldx     #2 * F_TAB
        ldy     #8
        lda     #PT_TAB
@set:   sta     ptype,x
        inx
        inx
        dey
        bne     @set
        rts

; rng = xorshift32(rng)
xorshift:
        lda     rng                     ; x ^= x << 13
        sta     z:g0
        lda     rng+2
        sta     z:g1
        ldx     #13
        jsr     @shl
        jsr     @xor
        lda     rng+2                   ; x ^= x >> 17: the high word >> 1 into the low
        lsr     a
        eor     rng
        sta     rng
        lda     rng                     ; x ^= x << 5
        sta     z:g0
        lda     rng+2
        sta     z:g1
        ldx     #5
        jsr     @shl
@xor:   lda     z:g0
        eor     rng
        sta     rng
        lda     z:g1
        eor     rng+2
        sta     rng+2
        rts
@shl:   asl     z:g0
        rol     z:g1
        dex
        bne     @shl
        rts

; A = n -> A = a random number 0 .. n-1: (the generator's high word * n) >> 16
rand_n: sta     z:g2
        jsr     xorshift
        lda     rng+2
        sta     z:g0
        stz     z:g1                    ; g1:g3 = g0 * g2 (32 bits; the high word wanted)
        stz     z:g3
        ldx     #16
:       asl     z:g1
        rol     z:g3
        asl     z:g0
        bcc     :+
        lda     z:g1
        clc
        adc     z:g2
        sta     z:g1
        bcc     :+
        inc     z:g3
:       dex
        bne     :--
        lda     z:g3
        rts

; r32 = ia32 * ib32 (low 32 bits)
mul32:  stz     r32
        stz     r32+2
        lda     ia32
        sta     z:g0
        lda     ia32+2
        sta     z:g1
        lda     ib32
        sta     z:g2
        lda     ib32+2
        sta     z:g3
        ldx     #32
@l:     lsr     z:g3
        ror     z:g2
        bcc     :+
        lda     r32
        clc
        adc     z:g0
        sta     r32
        lda     r32+2
        adc     z:g1
        sta     r32+2
:       asl     z:g0
        rol     z:g1
        dex
        bne     @l
        rts

; ---------------------------------------------------------------- moves
; ms (source pile), mi (index of the first card moved), md (destination) -> C set if the
; move is legal; mn = the number of cards, mc = the first card
can_move:
        lda     z:ms
        cmp     z:md
        jeq     @no
        asl     a
        tax
        lda     pcnt,x
        sec
        sbc     z:mi
        jcc     @no
        jeq     @no
        sta     z:mn
        lda     z:ms
        jsr     pofs
        clc
        adc     z:mi
        sta     z:g7                    ; the first card's offset
        tax
        lda     pcards,x
        and     #$00FF
        sta     z:mc
        bit     #DOWN
        jne     @no
        lda     z:ms                    ; what may leave the source
        jsr     ptyp
        cmp     #PT_TAB
        beq     @run
        cmp     #PT_STOCK
        jeq     @no
        cmp     #PT_FOUND
        bne     @one
        lda     game                    ; (FreeCell: never back from a foundation)
        jne     @no
@one:   lda     z:mn
        cmp     #1
        jne     @no
        bra     @dst
@run:   ldx     z:g7                    ; a tableau run: each card one lower, other colour
        ldy     z:mn
@rl:    dey
        beq     @dst
        lda     pcards+1,x
        and     #$00FF
        bit     #DOWN
        jne     @no
        sta     z:g0
        lda     pcards,x
        and     #$00FF
        sta     z:g1
        jsr     @pair                   ; g1 on top of... g0 on g1
        jcc     @no
        inx
        bra     @rl
@dst:   lda     z:md
        jsr     ptyp
        cmp     #PT_FOUND
        jeq     @found
        cmp     #PT_CELL
        beq     @cell
        cmp     #PT_TAB
        jne     @no
        lda     z:md                    ; tableau
        jsr     ptop
        bcs     @empty
        bit     #DOWN
        jne     @no
        sta     z:g1
        lda     z:mc
        sta     z:g0
        jsr     @pair
        jcc     @no
        bra     @cap
@empty: lda     game
        bne     @cap
        ldx     z:mc                    ; Klondike: a king
        lda     crank,x
        and     #$00FF
        cmp     #12
        jne     @no
        sec
        rts
@cap:   lda     game                    ; FreeCell: (free cells + 1) << empty columns
        bne     :+
        sec
        rts
:       stz     z:g2
        ldx     #2 * F_CELL
:       lda     pcnt,x
        bne     :+
        inc     z:g2
:       inx
        inx
        cpx     #2 * (F_CELL + 4)
        bcc     :--
        inc     z:g2
        ldx     #2 * F_TAB
        ldy     #F_TAB
:       lda     pcnt,x
        bne     :+
        cpy     z:md                    ; (the destination does not count)
        beq     :+
        asl     z:g2
:       inx
        inx
        iny
        cpy     #F_TAB + 8
        bcc     :--
        lda     z:g2
        cmp     z:mn
        bcc     @no
        sec
        rts
@cell:  lda     z:mn
        cmp     #1
        bne     @no
        lda     z:md
        asl     a
        tax
        lda     pcnt,x
        bne     @no
        sec
        rts
@found: lda     z:mn
        cmp     #1
        bne     @no
        lda     z:md
        jsr     ptop
        bcc     :+
        ldx     z:mc                    ; empty: an ace
        lda     crank,x
        and     #$00FF
        bne     @no
        sec
        rts
:       sta     z:g0                    ; the same suit, one higher
        tax
        lda     csuit,x
        ldx     z:mc
        eor     csuit,x
        and     #$00FF
        bne     @no
        ldx     z:g0
        lda     crank,x
        and     #$00FF
        inc     a
        ldx     z:mc
        eor     crank,x
        and     #$00FF
        bne     @no
        sec
        rts
@no:    clc
        rts
; card g0 may lie on card g1 in the tableau (one lower, the other colour) -> C (keeps X, Y)
@pair:  phx
        ldx     z:g0
        lda     cred,x
        ldx     z:g1
        eor     cred,x
        and     #$00FF
        beq     @pn
        ldx     z:g0
        lda     crank,x
        and     #$00FF
        inc     a
        ldx     z:g1
        eor     crank,x
        and     #$00FF
        bne     @pn
        plx
        sec
        rts
@pn:    plx
        clc
        rts

; do the move checked by can_move (ms, mi, md, mn): history, score, moves, dirty
do_move:
        lda     z:mi                    ; the cards, in order
        sta     z:g4
:       lda     z:ms
        jsr     pofs
        clc
        adc     z:g4
        tax
        lda     pcards,x
        and     #$00FF
        tax
        lda     z:md
        jsr     ppush
        inc     z:g4
        dec     z:mn
        bne     :-
        lda     z:ms                    ; the source keeps those under them
        asl     a
        tax
        lda     pcnt,x
        sec
        sbc     z:mi
        sta     z:mn
        lda     z:mi
        sta     pcnt,x
        stz     z:mf                    ; Klondike: a face-down card left on top turns up
        lda     game
        bne     :+
        lda     z:ms
        jsr     ptyp
        cmp     #PT_TAB
        bne     :+
        lda     z:ms
        jsr     ptop
        bcs     :+
        bit     #DOWN
        beq     :+
        txa                             ; (ptop leaves X = the offset + 1)
        dec     a
        tax
        lda     pcards,x
        and     #$007F
        sep     #$20
        .a8
        sta     pcards,x
        rep     #$20
        .a16
        inc     z:mf
:       stz     z:g5                    ; the score
        lda     game
        bne     @sc
        lda     z:md
        jsr     ptyp
        cmp     #PT_FOUND
        bne     :+
        lda     z:ms
        jsr     ptyp
        cmp     #PT_FOUND
        beq     :+
        lda     #10
        sta     z:g5
:       lda     z:ms
        jsr     ptyp
        cmp     #PT_FOUND
        bne     :+
        lda     z:g5
        sec
        sbc     #10
        sta     z:g5
:       cmp     #PT_WASTE
        bne     :+
        lda     z:md
        jsr     ptyp
        cmp     #PT_TAB
        bne     :+
        lda     z:g5
        clc
        adc     #5
        sta     z:g5
:       lda     z:mf
        beq     @sc
        lda     z:g5
        clc
        adc     #5
        sta     z:g5
@sc:    jsr     addscore
        lda     #H_MOVE
        jsr     hpush
        lda     z:ms
        jsr     pbit
        tsb     dirty
        lda     z:md
        jsr     pbit
        tsb     dirty
        rts

; score += g5, kept >= 0; g5 = the change made
addscore:
        lda     z:g5
        clc
        adc     score
        bpl     :+
        lda     score                   ; (to 0)
        eor     #$FFFF
        inc     a
        sta     z:g5
        lda     #0
:       sta     score
        rts

; A = kind, ms, md, mn, mf, g5 (score change): a history record; moves + 1
hpush:  sta     z:g0
        lda     hcount
        cmp     #HMAX
        bcc     :+
        jsr     hdrop
:       lda     hcount
        asl     a
        adc     hcount
        asl     a
        sta     z:hp
        ldy     #0
        lda     z:g0
        jsr     @b
        lda     z:ms
        jsr     @b
        lda     z:md
        jsr     @b
        lda     z:mn
        jsr     @b
        lda     z:mf
        jsr     @b
        lda     z:g5
        jsr     @b
        inc     hcount
        inc     moves
        rts
@b:     sep     #$20
        .a8
        sta     [hp],y
        rep     #$20
        .a16
        iny
        rts
; the history is full: the oldest half goes
hdrop:  lda     #HMAX / 2
        sta     z:g1
        ldy     #0
:       tya                             ; record y + HMAX / 2 -> y (byte by byte)
        clc
        adc     #HSZ * (HMAX / 2)
        tax
        phy
        txy
        lda     [hbase],y
        ply
        sta     [hbase],y
        iny
        cpy     #HSZ * (HMAX / 2)
        bcc     :-
        lda     #HMAX / 2
        sta     hcount
        rts

; Klondike: the stock clicked: draw 1 or 3 to the waste, or (empty) the waste turned over.
; C set if anything happened.
draw_stock:
        lda     game
        bne     @no
        lda     pcnt + 2 * K_STOCK
        bne     @draw
        lda     pcnt + 2 * K_WASTE
        beq     @no
        sta     z:mn                    ; turn the waste over: its top becomes the bottom
        sta     z:g4
:       lda     #K_WASTE
        jsr     ppop
        ora     #DOWN
        tax
        lda     #K_STOCK
        jsr     ppush
        dec     z:g4
        bne     :-
        lda     #$FFFF - 19             ; - 20
        sta     z:g5
        jsr     addscore
        lda     #H_TURN
        bra     @rec
@draw:  ldx     #1
        lda     draw3
        beq     :+
        ldx     #3
:       txa
        cmp     pcnt + 2 * K_STOCK
        bcc     :+
        lda     pcnt + 2 * K_STOCK
:       sta     z:mn
        sta     z:g4
:       lda     #K_STOCK
        jsr     ppop
        and     #$007F
        tax
        lda     #K_WASTE
        jsr     ppush
        dec     z:g4
        bne     :-
        stz     z:g5
        lda     #H_DRAW
@rec:   pha
        lda     #K_STOCK
        sta     z:ms
        lda     #K_WASTE
        sta     z:md
        stz     z:mf
        pla
        jsr     hpush
        lda     #(1 << K_STOCK) | (1 << K_WASTE)
        tsb     dirty
        sec
        rts
@no:    clc
        rts

; the last move undone; C set if there was one
undo:   lda     hcount
        bne     :+
        clc
        rts
:       dec     hcount
        dec     moves
        lda     hcount
        asl     a
        adc     hcount
        asl     a
        sta     z:hp
        ldy     #0
        jsr     @b
        sta     z:g0
        jsr     @b
        sta     z:ms
        jsr     @b
        sta     z:md
        jsr     @b
        sta     z:mn
        jsr     @b
        sta     z:mf
        jsr     @b
        cmp     #$80                    ; (signed)
        bcc     :+
        ora     #$FF00
:       eor     #$FFFF                  ; the score back
        inc     a
        clc
        adc     score
        sta     score
        lda     z:ms
        jsr     pbit
        tsb     dirty
        lda     z:md
        jsr     pbit
        tsb     dirty
        lda     z:g0
        cmp     #H_MOVE
        beq     @move
        cmp     #H_DRAW
        beq     @draw
        lda     z:mn                    ; the turn-over: stock back to the waste
        sta     z:g4
:       lda     #K_STOCK
        jsr     ppop
        and     #$007F
        tax
        lda     #K_WASTE
        jsr     ppush
        dec     z:g4
        bne     :-
        sec
        rts
@draw:  lda     #K_WASTE
        jsr     ppop
        ora     #DOWN
        tax
        lda     #K_STOCK
        jsr     ppush
        dec     z:mn
        bne     @draw
        sec
        rts
@move:  lda     z:mf                    ; turn the card back down
        beq     :+
        lda     z:ms
        jsr     ptop
        txa
        dec     a
        tax
        lda     pcards,x
        ora     #DOWN
        sep     #$20
        .a8
        sta     pcards,x
        rep     #$20
        .a16
:       lda     z:md                    ; the cards back, in order
        asl     a
        tax
        lda     pcnt,x
        sec
        sbc     z:mn
        sta     z:g4                    ; the first one's index
        sta     pcnt,x
:       lda     z:md
        jsr     pofs
        clc
        adc     z:g4
        tax
        lda     pcards,x
        and     #$00FF
        tax
        lda     z:ms
        jsr     ppush
        inc     z:g4
        dec     z:mn
        bne     :-
        sec
        rts
@b:     lda     [hp],y
        iny
        and     #$00FF
        rts

; ---------------------------------------------------------------- the end
; C set if all 52 cards are on the foundations
all_home:
        ldx     #2 * K_FOUND
        lda     game
        beq     :+
        ldx     #2 * F_FOUND
:       lda     pcnt,x
        clc
        adc     pcnt+2,x
        adc     pcnt+4,x
        adc     pcnt+6,x
        cmp     #52
        bne     :+
        sec
        rts
:       clc
        rts

; C set if the game can be finished by moving cards to the foundations alone: no stock,
; waste or face-down card (Klondike), and every tableau column in descending order
trivial:
        lda     game
        bne     :+
        lda     pcnt + 2 * K_STOCK
        ora     pcnt + 2 * K_WASTE
        bne     @no
:       ldy     #0                      ; each pile
@p:     cpy     npiles
        bcs     @yes
        tya
        jsr     ptyp
        cmp     #PT_TAB
        bne     @n
        tya
        asl     a
        tax
        lda     pcnt,x
        beq     @n
        sta     z:g1
        tya
        jsr     pofs
        tax
        lda     pcards,x
        and     #$00FF
        bit     #DOWN
        bne     @no
@c:     dec     z:g1                    ; the next card no higher, face up
        beq     @n
        stx     z:g2
        tax
        lda     crank,x
        and     #$00FF
        sta     z:g3
        ldx     z:g2
        lda     pcards+1,x
        and     #$00FF
        bit     #DOWN
        bne     @no
        phx
        tax
        lda     crank,x
        and     #$00FF
        plx
        cmp     z:g3
        beq     :+
        bcs     @no
:       inx
        lda     pcards,x
        and     #$00FF
        bra     @c
@n:     iny
        bra     @p
@yes:   sec
        rts
@no:    clc
        rts

; the lowest card that can go to a foundation (a top card of the tableau, a free cell,
; the waste) -> C set, ms, mi, md (checked with can_move)
auto_pick:
        lda     #99
        sta     z:g6                    ; the best rank so far
        stz     z:g8
:       lda     z:g8                    ; each pile not a foundation or the stock
        cmp     npiles
        bcs     @end
        jsr     ptyp
        cmp     #PT_FOUND
        beq     @n
        cmp     #PT_STOCK
        beq     @n
        lda     z:g8
        jsr     ptop
        bcs     @n
        bit     #DOWN
        bne     @n
        tax
        lda     crank,x
        and     #$00FF
        cmp     z:g6
        bcs     @n
        sta     z:g9
        lda     z:g8                    ; to any foundation?
        sta     z:ms
        asl     a
        tax
        lda     pcnt,x
        dec     a
        sta     z:mi
        jsr     found_for
        bcc     @n
        lda     z:g9
        sta     z:g6
        lda     z:md
        sta     z:bd
        lda     z:ms
        sta     z:bs
        lda     z:mi
        sta     z:bi
@n:     inc     z:g8
        bra     :-
@end:   lda     z:g6
        cmp     #99
        bcs     :+
        lda     z:bs
        sta     z:ms
        lda     z:bi
        sta     z:mi
        lda     z:bd
        sta     z:md
        jsr     can_move                ; (sets mn, mc)
        sec
        rts
:       clc
        rts

; ms, mi: a foundation that takes the card -> C set, md
found_for:
        ldx     #K_FOUND
        lda     game
        beq     :+
        ldx     #F_FOUND
:       stx     z:md
        txa
        clc
        adc     #4
        sta     z:fe
:       jsr     can_move
        bcs     @yes
        inc     z:md
        lda     z:md
        cmp     z:fe
        bcc     :-
        clc
@yes:   rts
