; qb_test.s - "quabrick -t": the self test of the rules (no window, text on the console), run
; by make test and compared with tests/quabrick-t.txt: turns and wall kicks, the bag, every
; kind of score (lines, a Quad, the level, spins, a mini spin, back-to-back, combos), the lock
; delay and its cap, the Time Attack clock, levels and gravity, the end above the top, and a
; game played by a simple robot to its end (a checksum of the rules: the same every run).

test_run:
        stz     sndok
        print   "QUABRICKS TEST START\n"
        stz     tfail
        ; ---- turns and kicks
        print   "turns: "
        jsr     tclear
        lda     #T_PIECE
        sta     z:pt
        lda     #4
        sta     z:px
        lda     #8
        sta     z:py
        stz     z:pr
        ldx     #4
:       phx
        lda     #1
        jsr     rotate
        plx
        dex
        bne     :-
        ldx     #4
:       phx
        lda     #$FFFF
        jsr     rotate
        plx
        dex
        bne     :-
        jsr     tpos                    ; 4 8 0
        print   "kicks: I at the left wall "
        jsr     tclear
        lda     #I_PIECE
        sta     z:pt
        lda     #$FFFF
        sta     z:px
        lda     #5
        sta     z:py
        stz     z:pr
        lda     #1
        jsr     rotate
        jsr     tpos                    ; 0 5 1
        print   "  T at the right wall "
        lda     #T_PIECE
        sta     z:pt
        lda     #8
        sta     z:px
        lda     #3
        sta     z:pr
        lda     #1
        jsr     rotate
        jsr     tpos                    ; 7 5 0
        print   "  T on the floor "
        lda     #3
        sta     z:px
        lda     #18
        sta     z:py
        stz     z:pr
        lda     #1
        jsr     rotate
        jsr     tpos                    ; 3 17 1
        print   "  boxed in "
        lda     #$03FF                  ; rows 10 and 12 full: no room to turn the long piece
        ldx     #10
        jsr     trow
        lda     #$03FF
        ldx     #12
        jsr     trow
        lda     #I_PIECE
        sta     z:pt
        lda     #3
        sta     z:px
        lda     #10                     ; (row 11, flat: turn 1 at y 10)
        sta     z:py
        lda     #1
        sta     z:pr
        lda     #1
        jsr     rotate
        jsr     tpos                    ; 3 10 1 (refused)

        ; ---- the bag
        print   "bag: "
        lda     #1
        sta     rng
        stz     rng+2
        stz     qforce
        jsr     fillbag
        stz     z:g8                    ; 70 pieces, each 7 one of each
        stz     z:g6                    ; (bags that were not)
@bag:   stz     z:g7
        ldx     #7
:       phx
        jsr     nextbag
        tax
        lda     pbits,x
        and     #$00FF
        tsb     z:g7
        lda     z:g8
        cmp     #14
        bcs     :+
        lda     pnames,x
        and     #$00FF
        jsr     put_char
:       inc     z:g8
        plx
        dex
        bne     :--
        lda     z:g7
        cmp     #$7F
        beq     :+
        inc     z:g6
:       lda     z:g8
        cmp     #70
        bcc     @bag
        lda     z:g6
        jsr     tok
        print   " (10 bags of 7)\n"

        ; ---- points
        lda     #1
        sta     startlv
        stz     mode
        print   "points, level 1:\n"
        ldx     #.loword(tc_single)
        jsr     tcase
        ldx     #.loword(tc_double)
        jsr     tcase
        ldx     #.loword(tc_triple)
        jsr     tcase
        ldx     #.loword(tc_quad)
        jsr     tcase
        ldx     #.loword(tc_spin2)
        jsr     tcase
        ldx     #.loword(tc_spin0)
        jsr     tcase
        ldx     #.loword(tc_mini)
        jsr     tcase
        ldx     #.loword(tc_tdrop)
        jsr     tcase
        lda     #3
        sta     startlv
        print   "points, level 3:\n"
        ldx     #.loword(tc_quad3)
        jsr     tcase
        lda     #1
        sta     startlv
        print   "back-to-back and combos (one game):\n"
        jsr     tnew
        ldx     #.loword(tb_q1)
        jsr     tcase2
        ldx     #.loword(tb_q2)
        jsr     tcase2
        ldx     #.loword(tc_none)
        jsr     tcase2
        ldx     #.loword(tb_q3)
        jsr     tcase2
        ldx     #.loword(tb_s1)
        jsr     tcase2
        ldx     #.loword(tb_s2)
        jsr     tcase2
        ldx     #.loword(tb_q4)
        jsr     tcase2
        ldx     #.loword(tb_sp)
        jsr     tcase2
        print   "  score "
        lda     score
        ldx     score+2
        jsr     tnum
        print   ", lines "
        lda     lines
        jsr     put_dec
        jsr     put_nl

        ; ---- the lock delay
        print   "lock delay: still "
        jsr     tnew
        stz     z:g5
        jsr     tlockrun
        print   " frames, moving every frame "
        jsr     tnew
        lda     #1
        sta     z:g5
        jsr     tlockrun
        print   " frames (15 restarts)\n"

        ; ---- Time Attack, levels, gravity
        print   "time attack: "
        lda     #1
        sta     mode
        jsr     tnew
        lda     tsec
        jsr     put_dec
        print   " s\n"
        ldx     #.loword(tc_double)
        jsr     tcase2
        print   "  time attack: "
        lda     tsec
        jsr     put_dec
        print   " s after 2 lines\n"
        ldx     #.loword(tb_ta4)
        jsr     tcase2
        print   "  time attack: "
        lda     tsec
        jsr     put_dec
        print   " s after a Quad\n"
        stz     mode
        print   "levels: gravity "
        jsr     tnew
        lda     speed
        jsr     put_dec
        jsr     put_nl
        ldx     #.loword(tb_q1)         ; 4 + 4 + 2 lines: level 2
        jsr     tcase2
        ldx     #.loword(tb_q2)
        jsr     tcase2
        ldx     #.loword(tb_d3)
        jsr     tcase2
        print   "  after 10 lines level "
        lda     level
        jsr     put_dec
        print   " gravity "
        lda     speed
        jsr     put_dec
        jsr     put_nl
        ; (1.1) every level's speed, played: an O from the top to the floor (18 rows), then
        ; lying still until it locks
        print   "speed by level: frames to fall 18 rows / frames on the floor until it locks\n"
        lda     #1
        sta     tlv
@lv:    lda     tlv
        sta     startlv
        jsr     tnew
        stz     z:pt
        jsr     put_top
        stz     kpress
        stz     kheld
        lda     npieces
        sta     z:g6
        stz     z:g7
:       inc     z:g7                    ; frames until it lies on the floor
        jsr     step
        jsr     grounded
        bcs     :+
        lda     z:g7
        cmp     #3000
        bcc     :-
:       lda     tlv
        cmp     #10
        bcs     :+
        print   " "
:       print   "  level "
        lda     tlv
        jsr     put_dec
        print   ": "
        lda     z:g7
        jsr     put_dec
        print   " / "
        stz     z:g7
:       inc     z:g7                    ; frames until it locks
        jsr     step
        lda     npieces
        cmp     z:g6
        bne     :+
        lda     z:g7
        cmp     #3000
        bcc     :-
:       lda     z:g7
        jsr     put_dec
        jsr     put_nl
        inc     tlv
        lda     tlv
        cmp     #NLV + 2                ; (and one above the table)
        jcc     @lv
        lda     #1
        sta     startlv

        ; ---- the end above the top
        print   "lock above the top: "
        jsr     tnew
        lda     #I_PIECE
        sta     z:pt
        stz     z:pr
        lda     #3
        sta     z:px
        lda     #$FFFE                  ; (rows -2 .. 1)
        sta     z:py
        jsr     lock
        lda     over
        jsr     put_dec
        print   " (over)\n"

        ; ---- a robot plays
        print   "robot: "
        lda     #1234
        sta     seed
        stz     seed+2
        jsr     seedgame
        jsr     newgame
        stz     z:g8                    ; drops
@robot: lda     over
        bne     @end
        lda     z:g8
        cmp     #2000
        bcs     @end
        and     #3
        bne     :+
        lda     #1
        jsr     rotate
:       lda     z:g8                    ; the target column: 3 n mod 10
        asl     a
        clc
        adc     z:g8
        ldx     #10
        jsr     qmod
        sta     z:g7
        ldx     #10
@mv:    phx
        lda     z:px
        cmp     z:g7
        beq     @dr
        bmi     :+
        lda     #$FFFF
        bra     :++
:       lda     #1
:       jsr     move
        plx
        bcc     @dr2
        dex
        bne     @mv
        bra     @dr2
@dr:    plx
@dr2:   jsr     harddrop
        inc     z:g8
        bra     @robot
@end:   lda     z:g8
        jsr     put_dec
        print   " pieces, score "
        lda     score
        ldx     score+2
        jsr     tnum
        print   ", lines "
        lda     lines
        jsr     put_dec
        print   ", level "
        lda     level
        jsr     put_dec
        print   ", over "
        lda     over
        jsr     put_dec
        jsr     put_nl

        print   "QUABRICKS TEST END: "
        lda     tfail
        jsr     put_dec
        print   " failed\n"
        exit    0

; a new game for the tests: empty well, no piece forced
tnew:   lda     #77
        sta     seed
        stz     seed+2
        jsr     seedgame
        jmp     newgame
tclear: ldx     #SW * SH - 2
:       stz     stage,x
        dex
        dex
        bpl     :-
        rts
; row X: the columns of bit mask A (bit 0 = column 0) taken
trow:   sta     z:g0
        txa
        asl     a
        tay
        lda     rowofs,y
        tay
        ldx     #SW
:       lsr     z:g0
        lda     #0
        bcc     :+
        lda     #8                      ; (a grey block)
:       sep     #$20
        .a8
        sta     stage,y
        rep     #$20
        .a16
        iny
        dex
        bne     :--
        rts
; "x y turn\n"
tpos:   lda     z:px
        jsr     tsdec
        print   " "
        lda     z:py
        jsr     tsdec
        print   " "
        lda     z:pr
        jsr     put_dec
        jmp     put_nl
tsdec:  bpl     :+
        pha
        print   "-"
        pla
        eor     #$FFFF
        inc     a
:       jmp     put_dec
; "PASS" when A = 0, else "FAIL" (counted)
tok:    cmp     #0
        bne     :+
        print   "PASS"
        rts
:       inc     tfail
        print   "FAIL"
        rts
; the number A (low), X (high)
tnum:   jsr     numstr
        ldx     #.loword(numbuf)
        ldy     pbank
        jmp     out_str

; a case: {name, rows (4 words: masks of rows 16-19), piece, turn, x, y, last action a turn,
; the points expected}; tcase on a new game, tcase2 in the game going on.
; Prints "  name: +points PASS/FAIL"
tcase:  phx
        jsr     tnew
        plx
tcase2: stx     tcp
        lda     score
        sta     tsave
        lda     score+2
        sta     tsave+2
        jsr     tclear
        ldx     tcp
        lda     a:2,x
        ldx     #16
        jsr     trow
        ldx     tcp
        lda     a:4,x
        ldx     #17
        jsr     trow
        ldx     tcp
        lda     a:6,x
        ldx     #18
        jsr     trow
        ldx     tcp
        lda     a:8,x
        ldx     #19
        jsr     trow
        ldx     tcp
        lda     a:18,x                  ; (extra cells: up to 3, column | row << 8, 0 none)
        jsr     tcell
        ldx     tcp
        lda     a:20,x
        jsr     tcell
        ldx     tcp
        lda     a:22,x
        jsr     tcell
        ldx     tcp
        lda     a:10,x
        sta     z:pt
        lda     a:12,x
        sta     z:pr
        lda     a:14,x
        sta     z:px
        lda     #$FFFE
        sta     z:py
        lda     a:16,x
        bpl     :+
        jsr     dropy                   ; ($FFFF: where it falls)
:       sta     z:py
        ldx     tcp
        lda     a:24,x
        sta     lastrot
        jsr     lock
        print   "  "
        ldx     tcp
        lda     a:0,x
        tax
        ldy     pbank
        jsr     out_str
        print   ": +"
        lda     score
        sec
        sbc     tsave
        sta     z:g0
        lda     score+2
        sbc     tsave+2
        sta     z:g1
        lda     z:g0
        pha
        ldx     z:g1
        jsr     tnum
        print   " "
        pla
        ldx     tcp
        cmp     a:26,x
        beq     :+
        lda     #1
        bra     :++
:       lda     #0
:       jsr     tok
        jmp     put_nl
tcell:  cmp     #0
        beq     @out
        sta     z:g0
        xba
        and     #$00FF
        asl     a
        tay
        lda     z:g0
        and     #$00FF
        clc
        adc     rowofs,y
        tay
        sep     #$20
        .a8
        lda     #8
        sta     stage,y
        rep     #$20
        .a16
@out:   rts

; the O piece on the floor: frames until it locks (g5 = 1: moved left / right every frame,
; else still) -> printed
tlockrun:
        lda     #0
        sta     z:pt
        stz     z:pr
        lda     #4
        sta     z:px
        jsr     dropy
        sta     z:py
        sta     lowest
        stz     lockt
        stz     lres
        lda     npieces
        sta     z:g6
        stz     z:g7
        stz     kheld
@f:     inc     z:g7
        stz     kpress
        lda     z:g5
        beq     :+
        lda     z:g7
        and     #1
        inc     a                       ; K_LEFT / K_RIGHT in turn
        sta     kpress
        sta     kheld
:       jsr     step
        stz     dasd
        lda     npieces
        cmp     z:g6
        bne     :+
        lda     z:g7
        cmp     #200
        bcc     @f
:       stz     z:g5
        stz     kheld
        lda     z:g7
        jmp     put_dec
