; sol_test.s - Solitaire's self test (included by solitair.s): "solitair -t", no window.
;
; 1. Scripts (tscript, made by tests/solitair_gen.py from a model of the same rules): known
;    deals played move by move; each move must be accepted or refused as the model says, the
;    score and a checksum of all piles must match at check points, undo must restore, and
;    the winning lines must end with all cards home.
; 2. Random play: thousands of random attempts (moves from any pile and position to any
;    pile, draws, undos, new deals); after each, every card must be on the table exactly
;    once, face down only in the stock or the tableau, the foundations in order, free cells
;    single; at the end of each game every move is undone and the deal must be back exactly.
; Output: PASS / FAIL lines on the console (DBG_OUT).

        .segment "CODE"

test_run:
        print   "SOLITAIRE TEST START\n"
        stz     tfail
        stz     tsec
        lda     #.loword(tscript)
        sta     tptr
@cmd:   ldx     tptr
        lda     a:0,x
        and     #$00FF
        inx
        stx     tptr
        cmp     #0
        jeq     @end
        sta     tcmd
        ldx     #0
:       lda     tcmds,x
        and     #$00FF
        jeq     @bad
        cmp     tcmd
        beq     :+
        inx
        inx
        inx
        bra     :-
:       lda     tcmds+1,x
        sta     z:jv
        jsr     @go
        bcc     @cmd
        jsr     tfailed                 ; a step failed: report, skip to the next section
@skip:  ldx     tptr
        lda     a:0,x
        and     #$00FF
        jeq     @end
        cmp     #'T'
        jeq     @cmd
        jsr     tlen
        clc
        adc     tptr
        sta     tptr
        bra     @skip
@go:    jmp     (jv)
@bad:   print   "FAIL bad script\n"
        inc     tfail
@end:   jsr     tsecend
        jsr     trandom
        print   "SOLITAIRE TEST END: "
        lda     tfail
        jsr     put_dec
        print   " failed\n"
        exit    0

; X = a command in the script -> A = its length (the command byte included)
tlen:   lda     a:0,x
        and     #$00FF
        ldy     #0
:       cmp     tlens,y
        beq     :+
        iny
        iny
        bra     :-
:       lda     tlens+1,y
        and     #$00FF
        bne     :+
        inx                             ; T: the name, to its end
        jsr     skipstr
        txa
        sec
        sbc     tptr
:       rts

; the bytes after the command
targ:   ldx     tptr
        lda     a:0,x
        inc     tptr
        and     #$00FF
        rts

tfailed:
        inc     tfail
        lda     #1
        sta     tsecbad
        print   "FAIL "
        ldx     tname
        ldy     #^tscript
        jsr     out_str
        print   ": step "
        lda     tstep
        jsr     put_dec
        print   " ("
        lda     tcmd
        jsr     out_char
        print   ")\n"
        rts

; T name: a new section
t_name: jsr     tsecend
        lda     tptr
        sta     tname
        ldx     tptr
        jsr     skipstr
        stx     tptr
        stz     tstep
        stz     tsecbad
        stz     tnmov
        stz     tnbad
        stz     tnundo
        lda     #1
        sta     tsec
        clc
        rts
; the end of a section: its PASS line
tsecend:
        lda     tsec
        jeq     @out
        stz     tsec
        lda     tsecbad
        bne     @out
        print   "PASS "
        ldx     tname
        ldy     #^tscript
        jsr     out_str
        print   ": "
        lda     tnmov
        jsr     put_dec
        print   " moves, "
        lda     tnbad
        jsr     put_dec
        print   " refused, "
        lda     tnundo
        jsr     put_dec
        print   " undone\n"
@out:   rts

; N game draw3 deal(2): deal
t_new:  inc     tstep
        jsr     targ
        sta     game
        jsr     targ
        sta     draw3
        jsr     targ
        sta     deal_no
        jsr     targ
        xba
        ora     deal_no
        sta     deal_no
        jsr     deal
        clc
        rts

; M src index dst expected(1 legal / 0 refused)
t_move: inc     tstep
        jsr     targ
        sta     z:ms
        jsr     targ
        sta     z:mi
        jsr     targ
        sta     z:md
        jsr     targ
        sta     z:t0
        jsr     can_move
        lda     #0
        rol     a
        cmp     z:t0
        bne     @f
        cmp     #0
        beq     @no
        jsr     do_move
        inc     tnmov
        clc
        rts
@no:    inc     tnbad
        clc
        rts
@f:     sec
        rts

; D expected: the stock clicked
t_draw: inc     tstep
        jsr     targ
        sta     z:t0
        jsr     draw_stock
        lda     #0
        rol     a
        cmp     z:t0
        bne     :+
        inc     tnmov
        clc
        rts
:       sec
        rts

; U: undo (must succeed)
t_undo: inc     tstep
        jsr     undo
        bcc     :+
        inc     tnundo
        clc
        rts
:       sec
        rts

; A: finish by moving cards home while possible (as the window does when trivial)
t_auto: inc     tstep
:       jsr     auto_pick
        bcc     :+
        jsr     do_move
        inc     tnmov
        bra     :-
:       clc
        rts

; I expected: trivial (1) or not (0)
t_triv: inc     tstep
        jsr     targ
        sta     z:t0
        jsr     trivial
        lda     #0
        rol     a
        cmp     z:t0
        bne     :+
        clc
        rts
:       sec
        rts

; W: all cards home
t_won:  inc     tstep
        jsr     all_home
        bcc     :+
        clc
        rts
:       sec
        rts

; S score(2)
t_score:
        inc     tstep
        jsr     targ
        sta     z:t0
        jsr     targ
        xba
        ora     z:t0
        cmp     score
        bne     :+
        clc
        rts
:       sec
        rts

; K checksum(2)
t_sum:  inc     tstep
        jsr     targ
        sta     z:t0
        jsr     targ
        xba
        ora     z:t0
        sta     z:t0
        jsr     checksum
        cmp     z:t0
        bne     :+
        clc
        rts
:       sec
        rts

; A = a checksum of all piles: h = h * 31 + count, then h = h * 31 + card for each card
checksum:
        stz     z:t1
        stz     z:t2                    ; pile
@p:     lda     z:t2
        cmp     npiles
        bcs     @out
        asl     a
        tax
        lda     pcnt,x
        sta     z:t3
        jsr     @mix
        lda     z:t2
        jsr     pofs
        tax
        ldy     z:t3
        beq     @n
:       lda     pcards,x
        and     #$00FF
        jsr     @mix
        inx
        dey
        bne     :-
@n:     inc     z:t2
        bra     @p
@out:   lda     z:t1
        rts
@mix:   sta     z:t4                    ; t1 = t1 * 31 + A
        lda     z:t1
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:t1
        clc
        adc     z:t4
        sta     z:t1
        rts

; ---------------------------------------------------------------- random play
TRGAMES = 15                            ; games, attempts per game
TRTRIES = 4000
trandom:
        lda     #$1234                  ; the test's own generator
        sta     trng
        lda     #$5678
        sta     trng+2
        stz     trmov
        stz     trund
        stz     trdeal
        stz     trbad
        stz     z:t6                    ; game number
@game:  lda     z:t6                    ; Klondike draw 1, draw 3, FreeCell in turn
:       cmp     #3
        bcc     :+
        sbc     #3
        bra     :-
:       stz     draw3
        stz     game
        cmp     #1
        bne     :+
        inc     draw3
:       cmp     #2
        bne     :+
        inc     game
:       lda     #65535
        jsr     trand
        inc     a
        sta     deal_no
        jsr     deal
        inc     trdeal
        jsr     checksum
        sta     trsum0
        jsr     tinv
        jcs     @inv
        lda     #TRTRIES
        sta     z:t7
@try:   lda     #16                     ; 1 in 16: undo; Klondike 1 in 8: the stock
        jsr     trand
        bne     :+
        jsr     undo
        bcc     @chk
        inc     trund
        bra     @chk
:       cmp     #3
        bcs     :+
        jsr     draw_stock
        bcc     @chk
        inc     trmov
        bra     @chk
:       lda     npiles                  ; a move from anywhere to anywhere
        jsr     trand
        sta     z:ms
        asl     a
        tax
        lda     pcnt,x
        inc     a
        jsr     trand
        sta     z:mi
        lda     npiles
        jsr     trand
        sta     z:md
        jsr     can_move
        bcc     @chk
        jsr     do_move
        inc     trmov
@chk:   jsr     tinv
        jcs     @inv
        dec     z:t7
        bne     @try
:       jsr     undo                    ; all undone: the deal again
        bcc     :+
        inc     trund
        bra     :-
:       jsr     checksum
        cmp     trsum0
        jne     @back
        lda     score
        ora     moves
        jne     @back
        inc     z:t6
        lda     z:t6
        cmp     #TRGAMES
        jcc     @game
        print   "PASS random play: "
        lda     trdeal
        jsr     put_dec
        print   " deals, "
        lda     trmov
        jsr     put_dec
        print   " moves, "
        lda     trund
        jsr     put_dec
        print   " undone, every card once, rules kept\n"
        rts
@inv:   print   "FAIL random play: the table is wrong after "
        bra     :+
@back:  print   "FAIL random play: undo did not restore the deal after "
:       inc     tfail
        lda     trmov
        jsr     put_dec
        print   " moves (deal "
        lda     deal_no
        jsr     put_dec
        print   ")\n"
        rts

; A = n -> A = 0 .. n-1 from the test's generator (the game's own is kept)
trand:  pha
        lda     rng
        ldx     trng
        sta     trng
        stx     rng
        lda     rng+2
        ldx     trng+2
        sta     trng+2
        stx     rng+2
        pla
        jsr     rand_n
        pha
        lda     rng
        ldx     trng
        sta     trng
        stx     rng
        lda     rng+2
        ldx     trng+2
        sta     trng+2
        stx     rng+2
        pla
        rts

; the table's invariants -> C set if broken
tinv:   ldx     #64 - 2                 ; seen[card]
:       stz     tseen,x
        dex
        dex
        bpl     :-
        stz     z:t2                    ; pile
@p:     lda     z:t2
        cmp     npiles
        jcs     @all
        jsr     ptyp
        sta     z:t5
        lda     z:t2
        asl     a
        tax
        lda     pcnt,x
        sta     z:t3
        cmp     #53
        jcs     @bad
        lda     z:t5                    ; a free cell: one card at most
        cmp     #PT_CELL
        bne     :+
        lda     z:t3
        cmp     #2
        jcs     @bad
:       lda     z:t2
        jsr     pofs
        tax
        stz     z:t4                    ; index
@c:     lda     z:t4
        cmp     z:t3
        bcs     @n
        lda     pcards,x
        and     #$00FF
        bit     #DOWN                   ; face down: only stock and tableau
        beq     :+
        pha
        lda     z:t5
        cmp     #PT_STOCK
        beq     :++
        cmp     #PT_TAB
        beq     :++
        pla
        jmp     @bad
:       pha
:       pla
        and     #$007F
        cmp     #52
        jcs     @bad
        tay                             ; once only
        lda     tseen,y
        and     #$00FF
        jne     @bad
        lda     #1
        sep     #$20
        .a8
        sta     tseen,y
        rep     #$20
        .a16
        lda     z:t5                    ; a foundation: suit and rank in order
        cmp     #PT_FOUND
        bne     :+
        lda     z:t4
        cmp     #13
        bcs     @bad
        lda     crank,y
        and     #$00FF
        cmp     z:t4
        bne     @bad
        lda     z:t4                    ; (the same suit as the one under it)
        beq     :+
        lda     csuit,y
        and     #$00FF
        sta     z:t1
        lda     pcards-1,x
        and     #$007F
        tay
        lda     csuit,y
        and     #$00FF
        cmp     z:t1
        bne     @bad
:       inx
        inc     z:t4
        bra     @c
@n:     inc     z:t2
        jmp     @p
@all:   ldx     #0                      ; all 52 seen
:       lda     tseen,x
        and     #$00FF
        beq     @bad
        inx
        cpx     #52
        bcc     :-
        clc
        rts
@bad:   sec
        rts

; X = string -> X past its terminator
skipstr:
        lda     a:0,x
        inx
        and     #$00FF
        bne     skipstr
        rts

        .segment "RODATA"
tcmds:  .byte   'T'
        .addr   t_name
        .byte   'N'
        .addr   t_new
        .byte   'M'
        .addr   t_move
        .byte   'D'
        .addr   t_draw
        .byte   'U'
        .addr   t_undo
        .byte   'A'
        .addr   t_auto
        .byte   'I'
        .addr   t_triv
        .byte   'W'
        .addr   t_won
        .byte   'S'
        .addr   t_score
        .byte   'K'
        .addr   t_sum
        .byte   0
tlens:  .byte   'T', 0, 'N', 5, 'M', 5, 'D', 2, 'U', 1, 'A', 1, 'I', 2, 'W', 1, 'S', 3, 'K', 3
        .include "sol_tscript.inc"
