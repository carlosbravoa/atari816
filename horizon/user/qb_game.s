; qb_game.s - Quabricks' rules (included by quabrick.s): the well, the pieces and their
; turns with wall kicks, the bag, gravity, the lock delay, holding, clearing lines, the score
; with spins, back-to-back and combos, levels, the Time Attack clock. Nothing here draws or
; plays: it sets flags (gf_*) and sound requests (sfx_req) that the frame acts on, so the self
; test (qb_test.s) runs the same code without a window.
;
; Scoring (times the level; the SDL2 Quabricks' table, extended):
;   lines           1: 100   2: 300   3: 500   4 (a Quad): 800
;   spin (T)        0: 400   1: 800   2: 1200  3: 1600     (the last action a turn, three of
;                                                           the four corners round the T taken)
;   mini spin (T)   0: 100   1: 200                         (a turn into a place it cannot
;                                                           leave: no 3 corners, but stuck)
;   back-to-back    a Quad or a spin with lines right after another one (only pieces that
;                   clear nothing between): the clear's points x 1.5
;   combo           every further piece in a row that clears lines: + 50 x combo x level
;   soft drop 1 a row, hard drop 2 a row (not times the level)
; Levels: every 10 lines. (1.1) Gravity (sp_f, sp_r, sp_l in qb_data.s): a row every 60
; frames at level 1, about 0.8 times that each level up to a row every frame at level 16,
; then 2, 3, 5, 10 rows a frame (levels 17-20) and at once to the floor from level 21; the
; lock delay is 30 frames up to level 20, then 2 frames shorter each level down to 10 frames
; from level 30 on. (1.0 had 60 - 4 (level - 1) frames a row, at least 4, reached at level 15:
; nothing got harder after that.) Time Attack: 60 s at the start, a clear of 1 / 2 / 3 / 4
; lines adds 2 / 4 / 6 / 10 s (the SDL2 version's).

SW      = 10                            ; the well
SH      = 20
NLV     = 30                            ; levels in the speed tables (above: the last one's)
MAXSTART = 20                           ; the highest starting level
LRESMAX = 15                            ; moves or turns on the ground that restart the lock delay
SOFTSPD = 4                             ; soft drop: a row every 4 frames (or faster gravity)
DAS     = 10                            ; auto shift: first repeat after 10 frames, then every 2
ARR     = 2
T_PIECE = 6                             ; piece types: O I J L S Z T (0-6)
I_PIECE = 1

; ---------------------------------------------------------------- set up
; the piece table: pcells (t * 4 + r) * 8: 4 x {dx, dy}; pbox t * 4: min x, max x, min y,
; max y of turn 0 (the previews)
mkcells:
        stz     z:g0                    ; (t * 4 + r)
@tr:    lda     z:g0
        asl     a
        tax
        lda     piecedb,x
        sta     z:g1                    ; the 4 x 4 mask, bit 15 = (0, 0)
        lda     z:g0
        asl     a
        asl     a
        asl     a
        tay
        stz     z:g2                    ; cell 0-15
@c:     asl     z:g1
        bcc     @n
        lda     z:g2
        and     #3
        sep     #$20
        .a8
        sta     pcells,y
        rep     #$20
        .a16
        lda     z:g2
        lsr     a
        lsr     a
        sep     #$20
        .a8
        sta     pcells+1,y
        rep     #$20
        .a16
        iny
        iny
@n:     inc     z:g2
        lda     z:g2
        cmp     #16
        bcc     @c
        inc     z:g0
        lda     z:g0
        cmp     #28
        bcc     @tr
        ldx     #0                      ; the boxes of turn 0
@b:     txa
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        tay                             ; (t * 4 * 8)
        lda     #$FF
        sta     z:g3                    ; min x
        sta     z:g5                    ; min y
        stz     z:g4
        stz     z:g6
        lda     #4
        sta     z:g2
:       lda     pcells,y
        and     #$00FF
        cmp     z:g3
        bcs     :+
        sta     z:g3
:       cmp     z:g4
        bcc     :+
        sta     z:g4
:       lda     pcells+1,y
        and     #$00FF
        cmp     z:g5
        bcs     :+
        sta     z:g5
:       cmp     z:g6
        bcc     :+
        sta     z:g6
:       iny
        iny
        dec     z:g2
        bne     :-----
        txa
        asl     a
        asl     a
        tay
        sep     #$20
        .a8
        lda     z:g3
        sta     pbox,y
        lda     z:g4
        sta     pbox+1,y
        lda     z:g5
        sta     pbox+2,y
        lda     z:g6
        sta     pbox+3,y
        rep     #$20
        .a16
        inx
        cpx     #7
        bcc     @b
        rts

; ---------------------------------------------------------------- the random bag
; xorshift32 in rng -> A = 16 random bits
rand16: lda     rng+2                   ; x ^= x << 13
        sta     z:rq
        lda     rng
        ldx     #13
:       asl     a
        rol     z:rq
        dex
        bne     :-
        eor     rng
        sta     rng
        lda     z:rq
        eor     rng+2
        sta     rng+2
        lda     rng                     ; x ^= x >> 17: low ^= high >> 1
        sta     z:rq
        lda     rng+2
        lsr     a
        eor     rng
        sta     rng
        lda     rng+2                   ; x ^= x << 5
        sta     z:rq
        lda     rng
        ldx     #5
:       asl     a
        rol     z:rq
        dex
        bne     :-
        eor     rng
        sta     rng
        lda     z:rq
        eor     rng+2
        sta     rng+2
        lda     rng
        eor     rng+2
        rts

; a new bag: the seven pieces in a random order (the SDL2 version's way: pick from a pool)
fillbag:
        ldx     #0
:       sep     #$20
        .a8
        txa
        sta     pool,x
        rep     #$20
        .a16
        inx
        cpx     #7
        bcc     :-
        stz     z:g0                    ; i
@i:     lda     #7                      ; j = random * (7 - i) / 65536
        sec
        sbc     z:g0
        sta     z:g1
        jsr     rand16
        ldx     z:g1
        jsr     mul16                   ; (g2 .. g4)
        lda     r32+2
        tax
        lda     pool,x
        ldy     z:g0
        sep     #$20
        .a8
        sta     bag,y
:       lda     pool+1,x                ; the pool closes up
        sta     pool,x
        inx
        cpx     #6
        bcc     :-
        rep     #$20
        .a16
        inc     z:g0
        lda     z:g0
        cmp     #7
        bcc     @i
        stz     bagn
        rts

; -> A = the next piece type (the forced list of -q first, then the bag)
nextbag:
        ldx     qforce
        beq     @bag
        lda     a:0,x
        and     #$00FF
        beq     @off
        inc     qforce
        ldy     #6
        sep     #$20
        .a8
:       cmp     pnames,y
        beq     :+
        dey
        bpl     :-
        ldy     #0
:       rep     #$20
        .a16
        tya
        rts
@off:   stz     qforce
@bag:   ldx     bagn
        lda     bag,x
        and     #$00FF
        pha
        inx
        stx     bagn
        cpx     #7
        bcc     :+
        jsr     fillbag
:       pla
        rts

; ---------------------------------------------------------------- a new game
; mode (0 Marathon, 1 Time Attack), startlv -> everything reset, the first piece out
newgame:
        ldx     #SW * SH - 2
:       stz     stage,x
        dex
        dex
        bpl     :-
        jsr     fillbag
        ldx     #0
:       phx
        jsr     nextbag
        plx
        sep     #$20
        .a8
        sta     queue,x
        rep     #$20
        .a16
        inx
        cpx     #5
        bcc     :-
        lda     #$FFFF
        sta     hold
        stz     holdused
        stz     score
        stz     score+2
        stz     lines
        lda     startlv
        sta     level
        lda     #10
        sta     nextlv
        lda     #$FFFF
        sta     combo
        stz     b2b
        stz     over
        stz     timeup
        stz     dasd
        stz     npieces
        lda     #60
        sta     tsec
        sta     tfr
        jsr     setspeed
        jmp     newpiece

; the level's gravity (speed: frames a row; srows: rows a frame) and lock delay (lockd)
setspeed:
        lda     level
        cmp     #NLV + 1
        bcc     :+
        lda     #NLV
:       tax
        lda     sp_f-1,x
        and     #$00FF
        sta     speed
        lda     sp_r-1,x
        and     #$00FF
        sta     srows
        lda     sp_l-1,x
        and     #$00FF
        sta     lockd
        rts

; the next piece from the queue at the top; over if it does not fit
newpiece:  lda     queue
        and     #$00FF
        sta     z:pt
        ldx     #0
:       lda     queue+1,x
        sep     #$20
        .a8
        sta     queue,x
        rep     #$20
        .a16
        inx
        cpx     #4
        bcc     :-
        jsr     nextbag
        sep     #$20
        .a8
        sta     queue+4
        rep     #$20
        .a16
        lda     #GF_NEXT                ; (hold: drawn again only if it was dimmed)
        ldx     holdused
        beq     :+
        ora     #GF_HOLD
:       tsb     gflags
        stz     holdused
        inc     npieces
put_top:
        lda     #3
        sta     z:px
        lda     #$FFFF
        sta     z:py
        sta     lowest
        stz     z:pr
        stz     lastrot
        stz     lockt
        stz     lres
        stz     grav
        jsr     cur2t
        jsr     valid
        bcs     :+
        jmp     gameover
:       rts

; ---------------------------------------------------------------- the well
; tx, ty, tr with type pt: does it fit? -> C set yes
valid:  lda     z:pt
        asl     a
        asl     a
        ora     z:tr
        asl     a
        asl     a
        asl     a
        tax
        lda     #4
        sta     z:vn
@c:     lda     pcells,x
        and     #$00FF
        clc
        adc     z:tx
        cmp     #SW                     ; (left of the wall: negative, so >= 10 too)
        bcs     @no
        sta     z:vx
        lda     pcells+1,x
        and     #$00FF
        clc
        adc     z:ty
        bmi     @nx                     ; above the top: free
        cmp     #SH
        bcs     @no
        asl     a
        tay
        lda     rowofs,y
        clc
        adc     z:vx
        tay
        lda     stage,y
        and     #$00FF
        bne     @no
@nx:    inx
        inx
        dec     z:vn
        bne     @c
        sec
        rts
@no:    clc
        rts

cur2t:  lda     z:px
        sta     z:tx
        lda     z:py
        sta     z:ty
        lda     z:pr
        sta     z:tr
        rts

; is the piece on something? -> C set yes
grounded:
        jsr     cur2t
        inc     z:ty
        jsr     valid
        bcc     :+
        clc
        rts
:       sec
        rts

; a move or turn on the ground restarts the lock delay (LRESMAX times)
onground:
        jsr     grounded
        bcc     @out
        lda     lres
        cmp     #LRESMAX
        bcs     @out
        inc     lres
        stz     lockt
@out:   rts

; move by A (-1 / +1) -> C set if it moved
move:   clc
        adc     z:px
        sta     z:tx
        lda     z:py
        sta     z:ty
        lda     z:pr
        sta     z:tr
        jsr     valid
        bcc     @no
        lda     z:tx
        sta     z:px
        stz     lastrot
        lda     #SFX_MOVE
        jsr     sfx
        jsr     onground
        sec
        rts
@no:    clc
        rts

; turn by A (+1 clockwise, -1 the other way), with the kicks: left, right, up (and for the
; long piece two left, two right) -> C set if it turned
rotate: clc
        adc     z:pr
        and     #3
        sta     z:tr
        lda     z:px
        sta     z:tx
        lda     z:py
        sta     z:ty
        jsr     valid
        bcs     @ok
        ldy     #0
@k:     lda     kicks,y
        cmp     #$7F
        beq     @no
        clc
        adc     z:px
        sta     z:tx
        lda     kicks+2,y
        clc
        adc     z:py
        sta     z:ty
        phy
        jsr     valid
        ply
        bcs     @ok
        iny
        iny
        iny
        iny
        cpy     #3 * 4                  ; (the last two for the long piece only)
        bne     @k
        lda     z:pt
        cmp     #I_PIECE
        beq     @k
@no:    clc
        rts
@ok:    lda     z:tx
        sta     z:px
        lda     z:ty
        sta     z:py
        lda     z:tr
        sta     z:pr
        lda     #1
        sta     lastrot
        lda     #SFX_ROTATE
        jsr     sfx
        jsr     onground
        sec
        rts

; the lowest place the piece falls to -> A = its y (the ghost, the hard drop)
dropy:  jsr     cur2t
:       inc     z:ty
        jsr     valid
        bcs     :-
        lda     z:ty
        dec     a
        rts

harddrop:
        jsr     dropy
        pha
        sec
        sbc     z:py
        asl     a                       ; 2 points a row
        jsr     addscore
        pla
        sta     z:py
        lda     #SFX_HARD
        jsr     sfx
        lda     #GF_SHAKE
        tsb     gflags
        jmp     lock

; hold: the piece goes aside (once per piece); the one held before comes in at the top
dohold: lda     holdused
        bne     @out
        lda     hold
        bmi     @first
        tax
        lda     z:pt
        sta     hold
        stx     z:pt
        jsr     put_top
        bra     @done
@first: lda     z:pt
        sta     hold
        jsr     newpiece
@done:  lda     #1
        sta     holdused
        lda     #GF_HOLD
        tsb     gflags
        lda     #SFX_HOLD
        jsr     sfx
@out:   rts

; ---------------------------------------------------------------- one frame of play
; the keys pressed since the last frame (kpress) and held (kheld), K_* bits
K_LEFT  = 1
K_RIGHT = 2
K_DOWN  = 4
K_HARD  = 8
K_CCW   = 16
K_CW    = 32
K_HOLD  = 64
step:   lda     mode                    ; Time Attack: the clock (tsec: seconds shown, rounded up;
        beq     :+                      ; tfr: frames 60 .. 1 of the current one)
        dec     tfr
        bne     :+
        lda     #60
        sta     tfr
        lda     #GF_TIME
        tsb     gflags
        dec     tsec
        bne     :+
        lda     #1
        sta     timeup
        jmp     gameover
:       lda     kpress
        bit     #K_HOLD
        beq     :+
        jsr     dohold
        lda     over
        beq     :+
        rts
:       lda     kpress
        bit     #K_CCW
        beq     :+
        lda     #$FFFF
        jsr     rotate
:       lda     kpress
        bit     #K_CW
        beq     :+
        lda     #1
        jsr     rotate
:       lda     kpress                  ; sideways, with the auto shift
        bit     #K_LEFT
        beq     :+
        lda     #$FFFF
        bra     @first
:       bit     #K_RIGHT
        beq     @held
        lda     #1
@first: sta     dasd
        jsr     move
        lda     #DAS
        sta     dast
        bra     @hard
@held:  lda     dasd
        beq     @hard
        bmi     :+
        lda     kheld
        and     #K_RIGHT
        bra     :++
:       lda     kheld
        and     #K_LEFT
:       bne     :+
        stz     dasd                    ; let go
        bra     @hard
:       dec     dast
        bne     @hard
        lda     #ARR
        sta     dast
        lda     dasd
        jsr     move
@hard:  lda     kpress
        bit     #K_HARD
        beq     :+
        jmp     harddrop
:       bit     #K_DOWN                 ; soft drop pressed: a row at once (or lock)
        beq     @grav
        lda     #SFX_SOFT
        jsr     sfx
        stz     grav
        jsr     grounded
        bcc     :+
        jmp     lock
:       jsr     fall
@grav:  jsr     grounded
        bcs     @ground
        inc     grav
        lda     kheld
        and     #K_DOWN
        beq     @nos
        lda     speed
        cmp     #SOFTSPD
        bcc     @cmp
        lda     #SOFTSPD
        bra     @cmp
@nos:   lda     speed
@cmp:   cmp     grav                    ; (speed <= frames waited: a row down)
        beq     @f
        bcs     @out
@f:     stz     grav
        lda     srows                   ; (faster than a row a frame: several)
        cmp     #2
        bcs     gfall
        jmp     fall
@ground:
        inc     lockt
        lda     lockt
        cmp     lockd
        bcs     @lock
        cmp     #SOFTSPD
        bcc     @out
        lda     kheld
        and     #K_DOWN
        bne     @lock
@out:   rts
@lock:  jmp     lock

; (1.1) gravity of A rows in one frame (fewer when the piece lands): no soft-drop points
gfall:  sta     gfn
        lda     kheld
        pha
        lda     #K_DOWN
        trb     kheld
:       jsr     grounded
        bcs     :+
        jsr     fall
        dec     gfn
        bne     :-
:       pla
        sta     kheld
        rts

; a row down (soft drop: a point); a new lowest row gives the lock delay its moves back
fall:   inc     z:py
        stz     lastrot
        lda     kheld
        and     #K_DOWN
        beq     :+
        lda     #1
        jsr     addscore
:       lda     z:py
        cmp     lowest
        beq     :+
        bmi     :+
        sta     lowest
        stz     lres
        stz     lockt
:       rts

; ---------------------------------------------------------------- locking
; the piece into the well, the lines, the points, the next piece
lock:   lda     #SFX_LOCK
        jsr     sfx
        jsr     spincheck               ; (before the cells go in)
        sta     spin
        stz     lockout
        lda     z:pt
        asl     a
        asl     a
        ora     z:pr
        asl     a
        asl     a
        asl     a
        tax
        lda     #4
        sta     z:vn
@c:     lda     pcells+1,x
        and     #$00FF
        clc
        adc     z:py
        bpl     :+
        inc     lockout                 ; above the top: the game ends after this
        bra     @n
:       asl     a
        tay
        lda     pcells,x
        and     #$00FF
        clc
        adc     z:px
        clc
        adc     rowofs,y
        tay
        lda     z:pt
        inc     a
        sep     #$20
        .a8
        sta     stage,y
        rep     #$20
        .a16
@n:     inx
        inx
        dec     z:vn
        bne     @c
        ; the full rows (only the piece's rows can be), top first, into clr[]
        stz     nclr
        lda     z:py
        sta     z:g0
        lda     #4
        sta     z:g1
@r:     lda     z:g0
        bmi     @nr
        cmp     #SH
        bcs     @nr
        asl     a
        tay
        ldx     rowofs,y
        ldy     #SW
:       lda     stage,x
        and     #$00FF
        beq     @nr
        inx
        dey
        bne     :-
        ldx     nclr
        lda     z:g0
        sta     clr,x
        inx
        inx
        stx     nclr
@nr:    inc     z:g0
        dec     z:g1
        bne     @r
        lsr     nclr                    ; (count)
        lda     #GF_STAGE
        tsb     gflags
        jsr     award
        lda     nclr
        beq     @nocl
        ldx     #SW * SH - 2            ; the well as it was, for the screen's copies
:       lda     stage,x
        sta     stage0,x
        dex
        dex
        bpl     :-
        lda     #GF_CLEAR
        tsb     gflags
        jsr     clearrows
@nocl:  lda     lockout
        beq     :+
        jmp     gameover
:       jmp     newpiece

; the rows in clr[] out of the well (the screen copies them itself: qb_draw)
clearrows:
        ldx     #0
@r:     cpx     nclr
        bcs     @out
        phx
        txa
        asl     a
        tax
        lda     clr,x                   ; row r: everything above moves down a row
        asl     a
        tay
        lda     rowofs,y
        clc
        adc     #SW - 1
        tax                             ; the row's last cell
:       cpx     #SW
        bcc     :+
        lda     stage-SW,x
        sep     #$20
        .a8
        sta     stage,x
        rep     #$20
        .a16
        dex
        bra     :-
:       sep     #$20                    ; the top row empties
        .a8
        stz     stage,x
        rep     #$20
        .a16
        dex
        bpl     :-
        plx
        inx
        bra     @r
@out:   rts

; T, the last action a turn: 2 a spin (3 corners of its box taken), 1 a mini spin (stuck:
; it can go neither left, right nor up), 0 none -> A
spincheck:
        lda     z:pt
        cmp     #T_PIECE
        bne     @none
        lda     lastrot
        beq     @none
        stz     z:g0
        lda     z:px
        ldx     z:py
        jsr     corner
        lda     z:px
        inc     a
        inc     a
        ldx     z:py
        jsr     corner
        lda     z:px
        ldx     z:py
        inx
        inx
        jsr     corner
        lda     z:px
        inc     a
        inc     a
        ldx     z:py
        inx
        inx
        jsr     corner
        lda     z:g0
        cmp     #3
        bcc     @mini
        lda     #2
        rts
@mini:  jsr     cur2t
        dec     z:tx
        jsr     valid
        bcs     @none
        inc     z:tx
        inc     z:tx
        jsr     valid
        bcs     @none
        dec     z:tx
        dec     z:ty
        jsr     valid
        bcs     @none
        lda     #1
        rts
@none:  lda     #0
        rts
; cell A, X taken (walls and floor count; above the top does not) -> g0 + 1
corner: cmp     #SW
        bcs     @yes
        sta     z:g1
        txa
        bmi     @no
        cmp     #SH
        bcs     @yes
        asl     a
        tay
        lda     rowofs,y
        clc
        adc     z:g1
        tay
        lda     stage,y
        and     #$00FF
        beq     @no
@yes:   inc     z:g0
@no:    rts

; the points for this lock: spin, nclr -> score, lines, level, combo, back-to-back, the clock
award: stz     lastpts
        stz     lastpts+2
        stz     bonusf
        lda     nclr
        asl     a
        tax
        lda     spin
        cmp     #2
        bne     :+
        lda     pts_spin,x
        bra     @base
:       cmp     #1
        bne     @plain
        cpx     #2 * 2
        bcs     @plain
        lda     pts_mini,x
        bra     @base
@plain: stz     spin
        lda     pts_line,x
@base:  ldx     level
        jsr     mul16                   ; -> r32
        lda     nclr
        bne     @lines
        lda     #$FFFF                  ; nothing cleared: the combo ends
        sta     combo
        bra     @add
@lines: lda     nclr                    ; difficult: a Quad, or a spin with lines
        cmp     #4
        beq     @hard
        lda     spin
        bne     @hard
        stz     b2b
        bra     @combo
@hard:  lda     b2b
        beq     :+
        lda     r32+2                   ; back-to-back: x 1.5
        lsr     a
        sta     z:g2
        lda     r32
        ror     a
        clc
        adc     r32
        sta     r32
        lda     z:g2
        adc     r32+2
        sta     r32+2
        lda     #BF_B2B
        tsb     bonusf
:       lda     #1
        sta     b2b
@combo: inc     combo
        lda     combo
        beq     @add
        lda     #BF_COMBO
        tsb     bonusf
        lda     r32
        sta     z:g5
        lda     r32+2
        sta     z:g6
        lda     combo                   ; + 50 x combo x level
        ldx     #50
        jsr     mul16
        lda     r32
        ldx     level
        jsr     mul16
        lda     r32
        clc
        adc     z:g5
        sta     r32
        lda     r32+2
        adc     z:g6
        sta     r32+2
@add:   lda     r32
        sta     lastpts
        lda     r32+2
        sta     lastpts+2
        lda     r32
        clc
        adc     score
        sta     score
        lda     r32+2
        adc     score+2
        sta     score+2
        lda     #GF_SCORE
        tsb     gflags
        lda     nclr
        beq     @out
        clc                             ; lines, level
        adc     lines
        sta     lines
        lda     nextlv
        sec
        sbc     nclr
        sta     nextlv
        beq     @lvup
        bpl     @noup
@lvup:  clc
        adc     #10
        sta     nextlv
        inc     level
        jsr     setspeed
        lda     #SFX_LEVEL
        jsr     sfx
@noup:  lda     mode                    ; Time Attack: seconds won
        beq     @snd
        lda     nclr
        asl     a
        tax
        lda     ta_bonus,x
        clc
        adc     tsec
        sta     tsec
        lda     #GF_TIMEWON
        tsb     gflags
@snd:   lda     nclr
        clc
        adc     #SFX_CLEAR1 - 1
        jsr     sfx
        lda     #GF_STATS
        tsb     gflags
@out:   rts

; A points added to the score (drops)
addscore:
        clc
        adc     score
        sta     score
        bcc     :+
        inc     score+2
:       lda     #GF_SCORE
        tsb     gflags
        rts

; r32 = A * X (16 x 16 bits)
mul16:  sta     z:g2
        stx     z:g3
        stz     r32
        stz     r32+2
        stz     z:g4                    ; (the multiplicand's high word as it shifts)
        ldy     #16
@b:     lsr     z:g3
        bcc     :+
        lda     r32
        clc
        adc     z:g2
        sta     r32
        lda     r32+2
        adc     z:g4
        sta     r32+2
:       asl     z:g2
        rol     z:g4
        dey
        bne     @b
        rts

gameover:
        lda     #1
        sta     over
        lda     #SFX_OVER
        jsr     sfx
        lda     #GF_OVER
        tsb     gflags
        rts
