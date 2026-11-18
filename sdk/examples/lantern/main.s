; LANTERN - an arcade game for Horizon (Atari816): paddle, ball and a moth.
;
; Thirty-six lanterns hang on three wires in the night sky. Bounce the ball into them to
; light them; light them all to finish the night. A moth flutters along the wires and
; puts out every lit lantern it touches: hit it with the ball (+50) to chase it away
; for a while; a moth that put out a lantern flies off too. Three balls; each night the
; ball and the moth are faster.
;
; Started with any argument ("lantern demo" in the shell) it plays itself: the paddle
; follows the ball, most lanterns are lit already and the moth stays away; after the
; dawn it lets the ball fall. The test uses this (the console says what happened).
;
;   Left / Right (or A / D), or the mouse: move the paddle
;   Space or a click: launch the ball / start; Esc: back to the title (there: quit)
;
; Built from sdk/templates/game (read that first: the loop, the background picture and
; the dirty rectangles are the same); new here:
;   - fixed-point motion: the ball's position and speed are in quarter pixels;
;   - the paddle's bounce angle depends on where the ball hits it;
;   - WF_HOVER: motion events whenever the pointer moves over the window (the paddle
;     follows the mouse without a button held);
;   - a second module, bigtext.s, for the big title letters (a 1 bpp font made by
;     sdk/tools/font2inc.py, expanded by the CPU, one WD_KBLIT);
;   - lantern tiles drawn into the background picture with a keyed CPU copy (the sky
;     shows through the transparent pixels), and redrawn when lit or put out.

        .include "horizon.inc"
        .import bigtext, bt_buf, bt_buf2
        .importzp bt_w, bt_dst

; ---------------------------------------------------------------- constants
FW      = 320                           ; the playfield (the background picture: 64,000
FH      = 200                           ;   bytes, one bank)
HUDH    = 16                            ; the status strip above it
CW      = FW                            ; the window's content
CH      = FH + HUDH
KEY     = 231                           ; transparent (sprites, big text)
NROW    = 3                             ; lanterns: 3 rows of 12
NCOL    = 12
NLAN    = NROW * NCOL
LX0     = 20                            ; lantern column c at x = LX0 + 24 c
LY0     = 20                            ; row r at y = LY0 + 24 r
LSTEP   = 24
PY      = 184                           ; the paddle's top
PW      = 32                            ; paddle 32 x 8
BS      = 8                             ; the ball: 8 x 8
GROUND  = 196                           ; grass from this row down
ST_TITLE = 0
ST_PLAY = 1
ST_CLEAR = 2                            ; "NIGHT n" between nights
ST_OVER = 3
J_LEFT  = 4                             ; key bits (a joystick's layout)
J_RIGHT = 8
J_FIRE  = 16
C_HUD   = 16                            ; cube 0 0 0: black
C_WIRE  = 16 + 36 * 2 + 6 * 1           ; cube 2 1 0: brown
C_GRASS = 16 + 6 * 1                    ; cube 0 1 0
C_GOLD  = 16 + 36 * 5 + 6 * 4           ; cube 5 4 0
C_SHADE = 16 + 36 * 1 + 1               ; cube 1 0 1

        .segment "CODE"
        .a16
        .i16

start:  cmp     #0                      ; any argument: the demo (autopilot, for tests)
        beq     :+
        lda     #1
:       sta     z:demo
        sys     SYS_WSSTART
        bcc     :+
        print   "lantern: no window system\n"
        exit    1
:       sta     z:wsown
        sys     SYS_BALLOC              ; the background picture's bank
        bcc     :+
        print   "lantern: not enough memory\n"
        jmp     quit
:       sta     z:bg+2
        stz     z:bg
        ptr     wopen
        sys     SYS_WOPEN
        jcs     quit
        sta     z:win
        ptr     menus
        lda     z:win
        sys     SYS_WMENU
        lda     z:win
        ldx     #2                      ; 50 steps a second
        sys     SYS_WTIMER
        sys     SYS_UPTIME
        ora     #1
        sta     z:rnd
        jsr     makesky                 ; the sky's colour of every row
        jsr     title
        lda     z:demo
        beq     loop
        jsr     newgame                 ; the demo starts playing at once

; ---------------------------------------------------------------- the loop
loop:   lda     #0
        jsr     getev
        jsr     handle
@more:  lda     #1
        jsr     getev
        bcs     @step
        jsr     handle
        bra     @more
@step:  lda     z:pending
        beq     loop
        cmp     #5
        bcc     :+
        lda     #4
:       sta     z:pending
@one:   jsr     sfx_tick
        lda     z:state
        cmp     #ST_PLAY
        bne     :+
        jsr     step
        bra     @dec
:       cmp     #ST_CLEAR
        bne     @dec
        dec     z:cltimer               ; the pause between nights
        bne     @dec
        inc     z:night
        jsr     newnight
@dec:   dec     z:pending
        bne     @one
        lda     z:state
        cmp     #ST_PLAY
        bne     loop
        jsr     draw
        bra     loop

getev:  ldx     #.loword(ev)
        ldy     #^ev
        sys     SYS_WEVENT
        rts

handle: lda     ev
        and     #$00FF
        cmp     #WE_TICK
        bne     :+
        inc     z:pending
        rts
:       cmp     #WE_KEY
        beq     onkey
        cmp     #WE_MOTION
        jeq     onmotion
        cmp     #WE_BUTTON
        jeq     onbutton
        cmp     #WE_MENU
        jeq     onmenu
        cmp     #WE_CLOSE
        jeq     quit
        rts

; keys: held keys as bits in z:keys (see the game template)
onkey:  lda     ev+2
        ldx     #0
:       cmp     keytab,x
        beq     @bit
        inx
        inx
        inx
        inx
        cpx     #KEYTABN * 4
        bcc     :-
        lda     ev+5                    ; other keys: presses only
        and     #$00FF
        beq     @out
        lda     ev+2
        cmp     #$29                    ; Esc
        bne     @out
        lda     z:state
        cmp     #ST_TITLE
        jeq     quit
        jmp     title
@bit:   lda     ev+5
        and     #$00FF
        beq     @up
        lda     keytab+2,x
        tsb     z:keys
        stz     z:mouse                 ; keys take over from the mouse
        cmp     #J_FIRE
        bne     @out
        jmp     fire
@up:    lda     keytab+2,x
        trb     z:keys
@out:   rts

; WE_MOTION (WF_HOVER: also without a button): the paddle follows the pointer
onmotion:
        lda     ev+2                    ; x in the content
        sec
        sbc     #PW / 2
        sta     z:mtarget
        lda     #1
        sta     z:mouse
        rts

onbutton:
        lda     ev+6                    ; a left press
        and     #1
        beq     :+
        jmp     fire
:       rts

; Space or a click: start a game, or launch the held ball
fire:   lda     z:state
        cmp     #ST_PLAY
        beq     :+
        cmp     #ST_CLEAR
        beq     @out
        jmp     newgame
:       lda     z:held
        beq     @out
        stz     z:held                  ; launch: up and a little to one side
        lda     z:speed
        eor     #$FFFF
        inc     a
        sta     z:vy
        lda     #3
        sta     z:vx
        jsr     random
        and     #1
        beq     @out
        lda     #$FFFD                  ; -3
        sta     z:vx
@out:   rts

; Game: New game (0), - (1), Quit (2)
onmenu: lda     ev+4
        jeq     newgame
        cmp     #2
        jeq     quit
        rts

; ---------------------------------------------------------------- states
title:  lda     #ST_TITLE
        sta     z:state
        jsr     sfx_off
        ldx     #NLAN - 1               ; the title picture: every lantern lit
:       lda     #1
        sep     #$20
        .a8
        sta     lit,x
        rep     #$20
        .a16
        dex
        bpl     :-
        jsr     render
        jsr     showall
        lda     #96                     ; "LANTERN", 3 x, gold with a shadow
        ldx     #.loword(s_title)
        ldy     #3
        jsr     bigcentre
        jsr     panelb
        lda     #128
        ldx     #.loword(s_help1)
        jsr     fixcentre
        lda     #142
        ldx     #.loword(s_help2)
        jsr     fixcentre
        lda     #156
        ldx     #.loword(s_help3)
        jsr     fixcentre
        lda     #1
        sta     z:night
        lda     #3
        sta     z:lives
        jmp     hud

newgame:
        stz     z:score
        lda     #3
        sta     z:lives
        lda     #1
        sta     z:night
        stz     z:keys
newnight:
        ldx     #NLAN - 1               ; every lantern dark
:       sep     #$20
        .a8
        stz     lit,x
        rep     #$20
        .a16
        dex
        bpl     :-
        stz     z:nlit
        lda     z:demo                  ; the demo: all but the 6 lanterns of the lowest
        beq     :++                     ;   row's middle lit, to reach the dawn quickly
        ldx     #NLAN - 1 - 9
:       sep     #$20
        .a8
        lda     #1
        sta     lit,x
        rep     #$20
        .a16
        inc     z:nlit
        dex
        bpl     :-
        ldx     #NLAN - 3               ; and the last two of that row
        jsr     @lit1
        ldx     #NLAN - 2
        jsr     @lit1
        ldx     #NLAN - 1
        jsr     @lit1
:       jsr     render
        jsr     showall
        lda     #ST_PLAY
        sta     z:state
        stz     z:pending
        lda     z:night                 ; ball speed: 6 + night quarter pixels a step
        clc
        adc     #6
        cmp     #13
        bcc     :+
        lda     #12
:       sta     z:speed
        lda     #(FW - PW) / 2
        sta     z:px
        sta     z:mtarget
        jsr     holdball
        stz     z:mact                  ; the moth comes after 4 s (in the demo: never,
        lda     #200                    ;   so its run is the same every time)
        ldx     z:demo
        beq     :+
        lda     #$7FFF
:       sta     z:mtimer
        stz     z:mdrawn
        jsr     sync_old
        jsr     drawsprites
        jmp     hud
@lit1:  sep     #$20
        .a8
        lda     #1
        sta     lit,x
        rep     #$20
        .a16
        inc     z:nlit
        rts

; the ball on the paddle, waiting for Space or a click
holdball:
        lda     #1
        sta     z:held
        stz     z:vx
        stz     z:vy
        jmp     ballonpaddle

ballonpaddle:
        lda     z:px                    ; x = paddle centre - 4, y = above it (quarters)
        clc
        adc     #PW / 2 - BS / 2
        asl     a
        asl     a
        sta     z:bx
        lda     #(PY - BS) * 4
        sta     z:by
        rts

gameover:
        lda     #ST_OVER
        sta     z:state
        print   "lantern: game over, score "
        lda     z:score
        jsr     put_dec
        jsr     put_nl
        jsr     sfx_lost
        jsr     panelb
        lda     #100
        ldx     #.loword(s_over)
        ldy     #2
        jsr     bigcentre
        lda     #128
        ldx     #.loword(s_again)
        jmp     fixcentre

nightclear:
        lda     #ST_CLEAR
        sta     z:state
        print   "lantern: night "
        lda     z:night
        jsr     put_dec
        print   " cleared\n"
        lda     z:demo                  ; the demo: then one ball, launched but not
        beq     :+                      ;   followed: game over
        lda     #2
        sta     z:demo
        lda     #1
        sta     z:lives
:
        lda     z:score                 ; 100 a night
        clc
        adc     #100
        sta     z:score
        jsr     hud
        jsr     sfx_level
        lda     #100                    ; 2 s
        sta     z:cltimer
        lda     #104
        ldx     #.loword(s_clear)
        ldy     #2
        jmp     bigcentre

; ---------------------------------------------------------------- one step
step:   inc     z:tick
; ---- the paddle: keys 4 pixels a step, or towards the pointer (at most 8)
        lda     z:keys
        bit     #J_LEFT
        beq     :+
        lda     z:px
        sec
        sbc     #4
        sta     z:px
        lda     z:keys
:       bit     #J_RIGHT
        beq     :+
        lda     z:px
        clc
        adc     #4
        sta     z:px
:       lda     z:mouse
        beq     @clamp
        lda     z:mtarget
        sec
        sbc     z:px                    ; distance, limited to -8 .. 8
        bpl     :+
        cmp     #$FFF8
        bcs     @madd
        lda     #$FFF8
        bra     @madd
:       cmp     #9
        bcc     @madd
        lda     #8
@madd:  clc
        adc     z:px
        sta     z:px
@clamp: lda     z:px                    ; 0 .. FW - PW
        bpl     :+
        stz     z:px
:       lda     z:px
        cmp     #FW - PW + 1
        bcc     :+
        lda     #FW - PW
        sta     z:px
:
; ---- the demo's autopilot: the paddle under the ball (with an offset that changes at
; every bounce, so the ball goes everywhere); launch after half a second
        lda     z:demo
        beq     @ball
        cmp     #1
        bne     @launch                 ; demo 2: launch only
        lda     #1
        sta     z:mouse
        lda     z:bx
        lsr     a
        lsr     a
        clc
        adc     z:dofs
        sec
        sbc     #PW / 2 - BS / 2
        sta     z:mtarget
@launch: lda    z:held
        beq     @ball
        lda     z:tick
        and     #31
        bne     @ball
        jsr     fire
; ---- the ball
@ball:  lda     z:held
        beq     @fly
        jsr     ballonpaddle
        jmp     domoth
@fly:   lda     z:bx                    ; remember where it was (pixels)
        lsr     a
        lsr     a
        sta     z:ox
        lda     z:by
        lsr     a
        lsr     a
        sta     z:oy
        lda     z:bx                    ; move (quarter pixels)
        clc
        adc     z:vx
        sta     z:bx
        lda     z:by
        clc
        adc     z:vy
        sta     z:by
        lda     z:bx                    ; the side walls
        bpl     :+
        eor     #$FFFF                  ; reflect: x = -x
        inc     a
        sta     z:bx
        jsr     negvx
:       lda     z:bx
        cmp     #(FW - BS) * 4 + 1
        bcc     :+
        lda     #(FW - BS) * 8          ; x = 2 * right - x
        sec
        sbc     z:bx
        sta     z:bx
        jsr     negvx
:       lda     z:by                    ; the top
        bpl     :+
        eor     #$FFFF
        inc     a
        sta     z:by
        jsr     negvy
:       lda     z:by                    ; fell past the paddle
        cmp     #FH * 4
        bcc     :+
        jmp     lost
:       jsr     paddlehit
        jsr     lanternhit
; ---- the moth (domoth)
domoth: lda     z:mact
        bne     @fly
        dec     z:mtimer                ; not here: count down to its return
        bne     @out
        lda     #1
        sta     z:mact
        lda     #0                      ; from the left or the right
        sta     z:mx
        lda     z:night                 ; speed 1 + night / 2, at most 3
        lsr     a
        inc     a
        cmp     #4
        bcc     :+
        lda     #3
:       sta     z:mdx
        jsr     random
        and     #1
        beq     @y
        lda     #FW - 16
        sta     z:mx
        lda     z:mdx
        eor     #$FFFF
        inc     a
        sta     z:mdx
@y:     stz     z:mph
@fly:   lda     z:mx                    ; across, turning at the sides
        clc
        adc     z:mdx
        sta     z:mx
        bmi     @turn
        cmp     #FW - 16 + 1
        bcc     @wob
@turn:  lda     z:mdx
        eor     #$FFFF
        inc     a
        sta     z:mdx
        clc
        adc     z:mx
        sta     z:mx
@wob:   inc     z:mph                   ; up and down along the wires (a sine table)
        lda     z:mph
        lsr     a
        and     #31
        tax
        lda     wob,x
        and     #$00FF
        clc
        adc     #LY0
        sta     z:my
        lda     z:tick                  ; flap
        and     #3
        bne     :+
        lda     z:mfr
        eor     #1
        sta     z:mfr
:       jsr     motheats
        jsr     mothhit
@out:   rts

negvx:  lda     z:vx
        eor     #$FFFF
        inc     a
        sta     z:vx
        rts
negvy:  lda     z:vy
        eor     #$FFFF
        inc     a
        sta     z:vy
        rts

; the ball fell: one ball less
lost:   dec     z:lives
        jsr     hud
        lda     z:lives
        jeq     gameover
        jsr     sfx_lost
        jmp     holdball

; the paddle: when the ball comes down onto it, back up at an angle that depends on where
; it hit (8 zones of 4 pixels: far left = steep left ... far right = steep right)
paddlehit:
        lda     z:vy
        bmi     @no                     ; going up
        lda     z:by
        lsr     a
        lsr     a
        clc
        adc     #BS
        cmp     #PY                     ; its bottom reached the paddle's top?
        bcc     @no
        cmp     #PY + 6
        bcs     @no                     ; (already past it)
        lda     z:bx
        lsr     a
        lsr     a
        clc
        adc     #BS / 2                 ; its centre
        sec
        sbc     z:px
        bmi     @no
        cmp     #PW
        bcs     @no
        lsr     a                       ; zone 0-7
        lsr     a
        asl     a
        tax
        lda     zonevx,x
        sta     z:vx
        lda     z:speed
        eor     #$FFFF
        inc     a
        sta     z:vy
        lda     #(PY - BS) * 4          ; on top of the paddle
        sta     z:by
        jsr     random                  ; (the demo's next offset: -8 .. 7)
        and     #15
        sec
        sbc     #8
        sta     z:dofs
        jsr     sfx_paddle
@no:    rts

; the lanterns: if the ball's box touches one, bounce (sideways if it came from the side,
; else up / down), back to where it was, and light it
lanternhit:
        lda     z:by
        lsr     a
        lsr     a
        sta     z:t1                    ; the ball's y (pixels)
        cmp     #LY0 + NROW * LSTEP
        bcs     @out                    ; below the lanterns
        lda     z:bx
        lsr     a
        lsr     a
        sta     z:t0                    ; x
        stz     z:t2                    ; lantern index
        lda     #LY0
        sta     z:t4                    ; the row's y
@row:   lda     z:t1                    ; ball bottom >= row top and ball top <= row bottom?
        clc
        adc     #BS - 1
        cmp     z:t4
        bcc     @nextrow
        lda     z:t4
        clc
        adc     #15
        cmp     z:t1
        bcc     @nextrow
        lda     #LX0
        sta     z:t3                    ; the lantern's x
        ldx     #NCOL
@col:   lda     z:t0
        clc
        adc     #BS - 1
        cmp     z:t3
        bcc     @nextcol
        lda     z:t3
        clc
        adc     #15
        cmp     z:t0
        bcs     @hit
@nextcol:
        inc     z:t2
        lda     z:t3
        clc
        adc     #LSTEP
        sta     z:t3
        dex
        bne     @col
        bra     @out                    ; (only one row can touch the ball)
@nextrow:
        lda     z:t2
        clc
        adc     #NCOL
        sta     z:t2
        lda     z:t4
        clc
        adc     #LSTEP
        sta     z:t4
        cmp     #LY0 + NROW * LSTEP
        bcc     @row
@out:   rts
; bounce away from the lantern (t3, t4 = its x, y) and put the ball just outside it on the
; side it came from (so it can never stick inside)
@hit:   lda     z:ox                    ; was it beside the lantern before (no overlap in x)?
        clc
        adc     #BS - 1
        cmp     z:t3
        bcc     @side
        lda     z:t3
        clc
        adc     #15
        cmp     z:ox
        bcc     @side
        lda     z:t1                    ; came from above or below: compare the centres
        clc
        adc     #BS / 2
        sec
        sbc     #8
        cmp     z:t4
        bmi     @above
        lda     z:t4                    ; below: under the lantern, going down
        clc
        adc     #16
        asl     a
        asl     a
        sta     z:by
        lda     z:vy
        jsr     absa
        sta     z:vy
        bra     @light
@above: lda     z:t4                    ; above: over it, going up
        sec
        sbc     #BS
        asl     a
        asl     a
        sta     z:by
        lda     z:vy
        jsr     absa
        eor     #$FFFF
        inc     a
        sta     z:vy
        bra     @light
@side:  lda     z:t0                    ; from the side
        clc
        adc     #BS / 2
        sec
        sbc     #8
        cmp     z:t3
        bmi     @left
        lda     z:t3                    ; right of it, going right
        clc
        adc     #16
        asl     a
        asl     a
        sta     z:bx
        lda     z:vx
        jsr     absa
        sta     z:vx
        bra     @light
@left:  lda     z:t3
        sec
        sbc     #BS
        asl     a
        asl     a
        sta     z:bx
        lda     z:vx
        jsr     absa
        eor     #$FFFF
        inc     a
        sta     z:vx
@light:
        ldx     z:t2
        lda     lit,x
        and     #$00FF
        jne     @out                    ; lit already
        sep     #$20
        .a8
        lda     #1
        sta     lit,x
        rep     #$20
        .a16
        lda     z:score
        clc
        adc     #10
        sta     z:score
        lda     z:t4                    ; a chime: higher for higher rows
        jsr     sfx_chime
        lda     z:t2
        jsr     redrawlantern           ; (uses t0-t5)
        jsr     hud
        inc     z:nlit
        lda     z:nlit
        cmp     #NLAN
        jne     @out
        jmp     nightclear

; the moth's centre over a lit lantern puts it out
motheats:
        lda     z:mx
        clc
        adc     #8
        sec
        sbc     #LX0
        bmi     @no
        sta     z:t0                    ; x from the first column
        lda     z:my
        clc
        adc     #8
        sec
        sbc     #LY0
        bmi     @no
        sta     z:t1
        ldx     #0                      ; column: x / 24, inside the first 16 pixels
        lda     z:t0
:       cmp     #LSTEP
        bcc     :+
        sbc     #LSTEP
        inx
        bra     :-
:       cmp     #16
        bcs     @no
        cpx     #NCOL
        bcs     @no
        stx     z:t2
        ldx     #0                      ; row the same way
        lda     z:t1
:       cmp     #LSTEP
        bcc     :+
        sbc     #LSTEP
        inx
        bra     :-
:       cmp     #16
        bcs     @no
        cpx     #NROW
        bcs     @no
        txa                             ; index = row * 12 + column
        asl     a
        sta     z:t3
        asl     a
        clc
        adc     z:t3                    ; * 6
        asl     a                       ; * 12
        clc
        adc     z:t2
        tax
        lda     lit,x
        and     #$00FF
        beq     @no
        sep     #$20
        .a8
        stz     lit,x
        rep     #$20
        .a16
        dec     z:nlit
        txa
        jsr     redrawlantern
        jsr     sfx_eat
        stz     z:mact                  ; full: it flies off, back in 5 s
        lda     #250
        sta     z:mtimer
@no:    rts

; the ball hits the moth: +50, the moth goes away for 8 s
mothhit:
        lda     z:held
        bne     @no
        lda     z:bx
        lsr     a
        lsr     a
        sec
        sbc     #8 - BS / 2             ; (centre - 8: a negative immediate is a range error)
        sec
        sbc     z:mx                    ; ball centre - moth centre
        jsr     absa
        cmp     #10
        bcs     @no
        lda     z:by
        lsr     a
        lsr     a
        sec
        sbc     #8 - BS / 2             ; (centre - 8: a negative immediate is a range error)
        sec
        sbc     z:my
        jsr     absa
        cmp     #10
        bcs     @no
        stz     z:mact
        lda     #400
        sta     z:mtimer
        lda     z:score
        clc
        adc     #50
        sta     z:score
        jsr     hud
        jsr     negvy
        jsr     sfx_moth
@no:    rts

absa:   bpl     :+
        eor     #$FFFF
        inc     a
:       rts

; xorshift16 -> A
random: lda     z:rnd
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        eor     z:rnd
        sta     z:rnd
        xba                             ; >> 9 = (>> 8) >> 1
        and     #$00FF
        lsr     a
        eor     z:rnd
        sta     z:rnd
        xba                             ; << 8
        and     #$FF00
        eor     z:rnd
        sta     z:rnd
        rts

; ---------------------------------------------------------------- the background
; skyrow: the colour of each of the 200 rows (bands of night blue, then grass)
makesky:
        ldx     #0
@l:     txa
        ldy     #16 + 1                 ; cube 0 0 1
        cmp     #70
        bcc     @put
        ldy     #16 + 2                 ; cube 0 0 2
        cmp     #130
        bcc     @put
        ldy     #16 + 6 + 2             ; cube 0 1 2
        cmp     #GROUND
        bcc     @put
        ldy     #C_GRASS
@put:   tya
        sep     #$20
        .a8
        sta     skyrow,x
        rep     #$20
        .a16
        inx
        cpx     #FH
        bcc     @l
        rts

; the whole picture: sky, stars, wires, lanterns (CPU, into the bank at bg)
render: lda     z:bg+2
        sta     z:dst+2
        stz     z:dst
        ldx     #0                      ; every row in its colour
@row:   lda     skyrow,x
        and     #$00FF
        sta     z:t0
        xba
        ora     z:t0                    ; the colour in both bytes
        ldy     #0
:       sta     [dst],y
        iny
        iny
        cpy     #FW
        bcc     :-
        lda     z:dst
        clc
        adc     #FW
        sta     z:dst
        inx
        cpx     #FH
        bcc     @row
        lda     #1234                   ; stars: the same sky every time (a fixed seed)
        sta     z:rnd2
        ldx     #70
@star:  phx
        jsr     random2                 ; x 0-319
        and     #$01FF
        cmp     #FW
        bcs     @skip
        sta     z:t0
        jsr     random2                 ; y 2-129
        and     #$007F
        clc
        adc     #2
        jsr     mul320
        clc
        adc     z:t0
        sta     z:dst
        jsr     random2                 ; a grey 244-255
        and     #$000F
        cmp     #12
        bcc     :+
        lda     #11
:       clc
        adc     #244
        sep     #$20
        .a8
        sta     [dst]
        rep     #$20
        .a16
@skip:  plx
        dex
        bne     @star
        lda     #NLAN - 1               ; every lantern (with its wire)
        sta     z:t5
:       lda     z:t5
        jsr     drawlantern
        dec     z:t5
        bpl     :-
        rts

; a second random generator for the stars (so they do not change the game's numbers)
random2:
        lda     z:rnd
        pha
        lda     z:rnd2
        sta     z:rnd
        jsr     random
        sta     z:rnd2
        pla
        sta     z:rnd
        lda     z:rnd2
        rts

; A = lantern index: its 24 x 16 cell into the background: the sky (and the wire across
; the hook's row), then the lantern image over it, key pixels skipped
drawlantern:
        jsr     lanxy                   ; -> t0 = x, t1 = y; X = index
        lda     lit,x
        and     #$00FF
        xba                             ; frame * 256
        clc
        adc     #.loword(lantern)
        sta     z:src
        lda     #^lantern
        sta     z:src+2
        lda     z:bg+2
        sta     z:dst+2
        lda     z:t1
        jsr     mul320
        clc
        adc     z:t0
        sec
        sbc     #4                      ; the cell starts 4 pixels left of the image
        sta     z:dst
        clc
        adc     #4                      ; dst4: where the image goes
        sta     z:dst4
        lda     z:bg+2
        sta     z:dst4+2
        stz     z:t3                    ; row
@row:   lda     z:t1                    ; the sky's colour of this row, or the wire's
        clc
        adc     z:t3
        tax
        lda     skyrow,x
        and     #$00FF
        ldy     z:t3
        cpy     #2                      ; the wire runs through the hook (image row 2)
        bne     :+
        lda     #C_WIRE
:       sta     z:t2
        sep     #$20
        .a8
        ldy     #0                      ; 24 pixels of sky / wire
        lda     z:t2
:       sta     [dst],y
        iny
        cpy     #LSTEP
        bcc     :-
        ldy     #0                      ; the image, 16 pixels at +4, key skipped
@px:    lda     [src],y
        cmp     #KEY
        beq     :+
        sta     [dst4],y
:       iny
        cpy     #16
        bcc     @px
        rep     #$20
        .a16
        lda     z:src
        clc
        adc     #16
        sta     z:src
        lda     z:dst
        clc
        adc     #FW
        sta     z:dst
        clc
        adc     #4
        sta     z:dst4
        inc     z:t3
        lda     z:t3
        cmp     #16
        bcc     @row
        rts

; A = lantern index -> t0 = image x, t1 = y (playfield), X = index
lanxy:  tax
        lda     #LY0
        sta     z:t1
        txa
:       cmp     #NCOL
        bcc     :+
        sbc     #NCOL
        pha
        lda     z:t1
        clc
        adc     #LSTEP
        sta     z:t1
        pla
        bra     :-
:       sta     z:t0                    ; x = LX0 + 24 column
        asl     a
        clc
        adc     z:t0                    ; * 3
        asl     a
        asl     a
        asl     a                       ; * 24
        clc
        adc     #LX0
        sta     z:t0
        rts

; A = lantern index: draw it again in the picture, then that cell onto the window
redrawlantern:
        pha
        jsr     drawlantern
        pla
        jsr     lanxy
        lda     z:t0
        sec
        sbc     #4
        sta     z:t0
        lda     #LSTEP
        sta     z:t4
        lda     #16
        sta     z:t5
        jmp     bgblit

; A = y -> A = y * 320
mul320: sta     z:t6
        xba
        and     #$FF00
        sta     z:t7
        lda     z:t6
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     z:t7
        rts

; ---------------------------------------------------------------- drawing
; WD_SBLIT from the background: t0, t1 = x, y in the playfield, t4, t5 = w, h
bgblit: lda     #WD_SBLIT
        sta     blk
        lda     #FW                     ; source stride
        sta     blk+1
        sep     #$20
        .a8
        stz     blk+3
        rep     #$20
        .a16
        lda     z:t0
        sta     blk+4
        lda     z:t1
        clc
        adc     #HUDH
        sta     blk+6
        lda     z:t4
        sta     blk+8
        lda     z:t5
        sta     blk+10
        lda     z:t1
        jsr     mul320
        clc
        adc     z:t0
        sta     blk+12
        lda     z:bg+2
        sta     blk+14
        jmp     wdraw

showall:
        stz     z:t0
        stz     z:t1
        lda     #FW
        sta     z:t4
        lda     #FH
        sta     z:t5
        bra     bgblit

; WD_KBLIT: A = image address (this bank), X, Y = playfield x, y, t4, t5 = w, h
kblit:  sta     blk+12
        lda     #WD_KBLIT
        sta     blk
        lda     #KEY << 8
        sta     blk+1
        sep     #$20
        .a8
        stz     blk+3
        rep     #$20
        .a16
        stx     blk+4
        tya
        clc
        adc     #HUDH
        sta     blk+6
        lda     z:t4
        sta     blk+8
        lda     z:t5
        sta     blk+10
        lda     #^ball
        sta     blk+14
        jmp     wdraw

wdraw:  lda     z:win
        ldx     #.loword(blk)
        ldy     #^blk
        sys     SYS_WDRAW
        rts

; dirty rectangles (as in the game template): put back the background where the paddle,
; the ball and the moth were, then draw them where they are
draw:   lda     z:px
        cmp     z:opx
        bne     @go
        lda     z:bx
        lsr     a
        lsr     a
        cmp     z:obx
        bne     @go
        lda     z:by
        lsr     a
        lsr     a
        cmp     z:oby
        bne     @go
        lda     z:mact
        ora     z:mdrawn
        bne     @go                     ; (the moth always moves)
        rts
; Each sprite is put back and drawn again in calls that follow each other closely: the
; screen shows every call at once (direct drawing), so a sprite erased early and drawn
; late can be missing from a video frame (seen in the emulator's screenshots: a flicker
; on the monitor). Erase, then draw right away; the ball last, over the paddle.
@go:    lda     z:mdrawn                ; the moth: erase, draw
        beq     :+
        lda     z:omx
        sta     z:t0
        lda     z:omy
        sta     z:t1
        lda     #16
        sta     z:t4
        sta     z:t5
        jsr     bgblit
:       jsr     drawmoth
        lda     z:obx                   ; the ball's old place, then the paddle's
        sta     z:t0
        lda     z:oby
        sta     z:t1
        lda     #BS
        sta     z:t4
        sta     z:t5
        jsr     bgblit
        lda     z:opx
        sta     z:t0
        lda     #PY
        sta     z:t1
        lda     #PW
        sta     z:t4
        lda     #8
        sta     z:t5
        jsr     bgblit
        jsr     sync_old
        bra     drawpb

drawsprites:
        jsr     drawmoth
drawpb: lda     #PW                     ; the paddle
        sta     z:t4
        lda     #8
        sta     z:t5
        lda     #.loword(paddle)
        ldx     z:px
        ldy     #PY
        jsr     kblit
        lda     #BS                     ; the ball
        sta     z:t4
        sta     z:t5
        lda     #.loword(ball)
        ldx     z:obx
        ldy     z:oby
        jmp     kblit

; the moth where it is now (if it is out); remembers that it is on the screen
drawmoth:
        stz     z:mdrawn
        lda     z:mact
        beq     @out
        lda     #16
        sta     z:t4
        sta     z:t5
        lda     z:mfr
        xba
        clc
        adc     #.loword(moth)
        ldx     z:mx
        ldy     z:my
        jsr     kblit
        lda     #1
        sta     z:mdrawn
        lda     z:mx
        sta     z:omx
        lda     z:my
        sta     z:omy
@out:   rts

; what is drawn now = what is on the screen (old positions for the next erase)
sync_old:
        lda     z:px
        sta     z:opx
        lda     z:bx
        lsr     a
        lsr     a
        sta     z:obx
        lda     z:by
        lsr     a
        lsr     a
        sta     z:oby
        lda     z:mx
        sta     z:omx
        lda     z:my
        sta     z:omy
        rts

; the status strip: "SCORE 00120   BALLS 3   NIGHT 1"
hud:    ldx     #0
        jsr     @copy
        .addr   s_score
        lda     z:score
        jsr     dec5
        jsr     @copy
        .addr   s_balls
        lda     z:lives
        jsr     dec1
        jsr     @copy
        .addr   s_night
        lda     z:night
        ldy     #10
        jsr     digit
        jsr     dec1
        stz     line,x
        lda     #WD_TEXT | (C_GOLD << 8)
        sta     blk
        lda     #C_HUD | (1 << 8)       ; paper, the fixed font
        sta     blk+2
        lda     #0
        sta     blk+4
        sta     blk+6
        lda     #.loword(line)
        sta     blk+12
        lda     #^line
        sta     blk+14
        lda     #WD_FILL | (C_HUD << 8) ; first the strip (the text does not fill it)
        sta     blk
        lda     #CW
        sta     blk+8
        lda     #HUDH
        sta     blk+10
        jsr     wdraw
        lda     #WD_TEXT | (C_GOLD << 8)
        sta     blk
        lda     #8
        sta     blk+4
        lda     #2
        sta     blk+6
        jmp     wdraw
@copy:  ply                             ; the string's address follows the JSR
        iny
        lda     a:0,y
        iny
        phy
        tay
:       lda     a:0,y
        and     #$00FF
        beq     :+
        sep     #$20
        .a8
        sta     line,x
        rep     #$20
        .a16
        inx
        iny
        bra     :-
:       rts

dec5:   ldy     #10000
        jsr     digit
        ldy     #1000
        jsr     digit
        ldy     #100
        jsr     digit
        ldy     #10
        jsr     digit
dec1:   clc
        adc     #'0'
        sep     #$20
        .a8
        sta     line,x
        rep     #$20
        .a16
        inx
        rts
; A = value, Y = power of ten: its digit at line,X -> A = the rest
digit:  sty     z:t6
        ldy     #'0'
:       cmp     z:t6
        bcc     :+
        sbc     z:t6
        iny
        bra     :-
:       pha
        tya
        sep     #$20
        .a8
        sta     line,x
        rep     #$20
        .a16
        inx
        pla
        rts

; big text centred: A = y (playfield), X = string, Y = scale. A shadow 1 pixel down-right
; in a dark colour, then the letters in gold.
bigcentre:
        sta     z:bty
        stx     z:bts
        sty     z:btsc
        lda     #.loword(bt_buf2)       ; the shadow into the second buffer
        sta     z:bt_dst
        lda     z:btsc
        ldy     #C_SHADE
        jsr     bigtext                 ; -> A = width
        lda     #1                      ; at +1, +1
        jsr     @blit
        lda     #.loword(bt_buf)        ; the letters into the first (bt_buf2 may still
        sta     z:bt_dst                ;   be read by the blitter)
        lda     z:btsc
        ldx     z:bts
        ldy     #C_GOLD
        jsr     bigtext
        lda     #0
@blit:  sta     z:t6                    ; A = the offset
        lda     #WD_KBLIT
        sta     blk
        lda     #KEY << 8
        sta     blk+1
        lda     #FW                     ; x = (FW - width) / 2 + offset
        sec
        sbc     z:bt_w
        lsr     a
        clc
        adc     z:t6
        sta     blk+4
        lda     z:bty
        clc
        adc     #HUDH
        adc     z:t6
        sta     blk+6
        lda     z:bt_w
        sta     blk+8
        lda     z:btsc                  ; height 7 * scale
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:btsc
        sta     blk+10
        lda     z:bt_dst
        sta     blk+12
        lda     #^bt_buf
        sta     blk+14
        jmp     wdraw

; a dark band behind the title / game over texts
panelb: lda     #WD_FILL | (C_HUD << 8)
        sta     blk
        lda     #12
        sta     blk+4
        lda     #HUDH + 122
        sta     blk+6
        lda     #FW - 24
        sta     blk+8
        lda     #48
        sta     blk+10
        jsr     wdraw
        lda     #WD_FRAME | (C_WIRE << 8)
        sta     blk
        jmp     wdraw

; A = y (playfield), X = string: centred, fixed font, white on the band
fixcentre:
        clc
        adc     #HUDH
        sta     blk+6
        stx     blk+12
        lda     #^s_title
        sta     blk+14
        lda     #1
        ldy     #^s_title
        sys     SYS_WTWIDTH             ; X = the string still
        eor     #$FFFF
        sec
        adc     #FW
        lsr     a
        sta     blk+4
        lda     #WD_TEXT | (C_WHITE << 8)
        sta     blk
        lda     #$FF | (1 << 8)         ; no paper, font 1
        sta     blk+2
        jmp     wdraw

; ---------------------------------------------------------------- sound
; two voices, as in the game template: X = voice * 2; pitch, step, volume 12, 12 ticks
sfx_paddle:
        ldx     #0
        lda     #100
        ldy     #0
        jsr     sfx_set
        lda     #5
        sta     v_n
        rts
sfx_chime:                              ; A = the lantern row's y: higher rows, higher
        lsr     a                       ; pitch 10 + y / 2
        clc
        adc     #10
        ldx     #0
        ldy     #0
        jsr     sfx_set
        lda     #16
        sta     v_n
        rts
sfx_eat:                                ; a light goes out: falling, voice 1
        ldx     #2
        lda     #120
        ldy     #8
        jmp     sfx_set
sfx_moth:                               ; the moth hit: noise
        ldx     #2
        lda     #20
        ldy     #1
        jsr     sfx_set
        lda     #$80
        sta     v_c+2
        rts
sfx_lost:
        ldx     #0
        lda     #60
        ldy     #6
        jsr     sfx_set
        lda     #40
        sta     v_n
        rts
sfx_level:
        ldx     #0
        lda     #110
        ldy     #$FFFC
        jsr     sfx_set
        lda     #26
        sta     v_n
        stz     v_dv
        rts
sfx_set:
        sta     v_f,x
        tya
        sta     v_df,x
        lda     #12
        sta     v_v,x
        lda     #1
        sta     v_dv,x
        lda     #$A0
        sta     v_c,x
        lda     #12
        sta     v_n,x
        rts

sfx_tick:
        ldx     #0
@v:     lda     v_n,x
        beq     @next
        dec     v_n,x
        beq     @off
        stx     z:t6                    ; AUDF of voice v = register 2 v = X
        phx
        lda     v_f,x
        and     #$00FF
        tax
        lda     z:t6
        sys     SYS_SNDW
        plx
        phx
        lda     v_v,x
        ora     v_c,x
        tax
        lda     z:t6
        inc     a
        sys     SYS_SNDW
        plx
        lda     v_f,x
        clc
        adc     v_df,x
        sta     v_f,x
        lda     v_v,x
        sec
        sbc     v_dv,x
        bpl     :+
        lda     #0
:       sta     v_v,x
        bra     @next
@off:   phx
        txa
        inc     a
        ldx     #0
        sys     SYS_SNDW
        plx
@next:  inx
        inx
        cpx     #4
        bcc     @v
        rts

sfx_off:
        stz     v_n
        stz     v_n+2
        lda     #0                      ; beep with duration 0: everything silent
        ldx     #0
        ldy     #0
        sys     SYS_BEEP
        rts

; ---------------------------------------------------------------- the end
quit:   jsr     sfx_off
        lda     z:win
        sys     SYS_WCLOSE
        lda     z:wsown
        beq     :+
        sys     SYS_WSSTOP
:       exit    0

; ---------------------------------------------------------------- data
        .segment "RODATA"
wopen:  .word   (640 - CW - 2) / 2, 56, CW, CH
        .faraddr t_win
        .byte   WF_HOVER                ; motion events without a button: the paddle
t_win:  .byte   "Lantern", 0
menus:  .byte   "Game", 0, "New game", 9, "Space", 0, "-", 0, "Quit", 9, "Esc", 0, 0, 0
s_title: .byte  "LANTERN", 0
s_over: .byte   "GAME OVER", 0
s_clear: .byte  "DAWN!", 0
s_help1: .byte  "Light every lantern. Mind the moth.", 0
s_help2: .byte  "Arrows / A D / mouse: move", 0
s_help3: .byte  "Space or click: start", 0
s_again: .byte  "Space or click: play again", 0
s_score: .byte  "SCORE ", 0
s_balls: .byte  "    BALLS ", 0
s_night: .byte  "    NIGHT ", 0
keytab: .word   $50, J_LEFT, $4F, J_RIGHT, $04, J_LEFT, $07, J_RIGHT, $2C, J_FIRE
KEYTABN = (* - keytab) / 4
; the ball's sideways speed after the paddle, by where it hit (quarter pixels a step)
zonevx: .word   $FFF7, $FFF9, $FFFB, $FFFE, 2, 5, 7, 9
; the moth's height along its path: 25 + 25 sin(2 pi i / 32)
wob:    .byte   25, 30, 35, 39, 43, 46, 48, 50, 50, 50, 48, 46, 43, 39, 35, 30
        .byte   25, 20, 15, 11, 7, 4, 2, 0, 0, 0, 2, 4, 7, 11, 15, 20
; the art (art/*.txt -> art/*.inc, sdk/tools/img2inc.py)
        .include "art/lantern.inc"
        .include "art/ball.inc"
        .include "art/paddle.inc"
        .include "art/moth.inc"

        .segment "BSS"
ev:     .res    8
blk:    .res    16
lit:    .res    NLAN + 1                ; 1 = lit
skyrow: .res    FH + 1
line:   .res    48
v_f:    .res    4
v_df:   .res    4
v_v:    .res    4
v_dv:   .res    4
v_c:    .res    4
v_n:    .res    4

        .segment "ZEROPAGE"
wsown:  .res    2
win:    .res    2
demo:   .res    2                       ; 1: autopilot (started with an argument)
dofs:   .res    2
bg:     .res    4
src:    .res    4
dst:    .res    4
dst4:   .res    4
state:  .res    2
pending: .res   2
tick:   .res    2
keys:   .res    2
mouse:  .res    2                       ; 1: the paddle follows the pointer
mtarget: .res   2
rnd:    .res    2
rnd2:   .res    2
px:     .res    2                       ; paddle x
opx:    .res    2
bx:     .res    2                       ; ball, quarter pixels
by:     .res    2
vx:     .res    2
vy:     .res    2
obx:    .res    2                       ; ball as drawn (pixels)
oby:    .res    2
ox:     .res    2                       ; ball before this step (pixels)
oy:     .res    2
held:   .res    2
speed:  .res    2
mx:     .res    2                       ; moth
my:     .res    2
omx:    .res    2
omy:    .res    2
mdx:    .res    2
mph:    .res    2
mfr:    .res    2
mact:   .res    2
mtimer: .res    2
mdrawn: .res    2
score:  .res    2
lives:  .res    2
night:  .res    2
nlit:   .res    2
cltimer: .res   2
bty:    .res    2
bts:    .res    2
btsc:   .res    2
t0:     .res    2
t1:     .res    2
t2:     .res    2
t3:     .res    2
t4:     .res    2
t5:     .res    2
t6:     .res    2
t7:     .res    2
