; GEMRUN - game skeleton for Horizon (Atari816): a small but complete game to grow from.
;
; Collect every gem in the maze; the blob bounces around and costs a life when it touches
; you. Arrow keys (or W A S D) move; a click sends the player towards the pointer; Space or
; a click starts; Esc goes back to the title (and from the title quits).
;
; What it shows (sdk/docs/reference/game-patterns.md explains each):
;   - a window of its own, 320 x 208: a 16-line status strip and a 320 x 192 playfield.
;     (Programs cannot change the video mode: a game is a window. For "full screen" open
;     a WF_PLAIN window of 640 x 344 at (0, 16), under the menu bar.)
;   - a timer-driven loop: win_timer gives WE_TICK every 20 ms (50 Hz); every tick is
;     one logic step, the screen is drawn once when the event queue is empty, so a slow
;     frame skips drawing, never logic.
;   - a tile map (20 x 12 tiles of 16 x 16) drawn by the CPU into a background picture in a
;     bank of its own (SYS_BALLOC), shown with one WD_SBLIT.
;   - sprites with keyed blits (WD_KBLIT, colour 231 transparent) and dirty rectangles:
;     each frame, a sprite's old place is put back from the background (WD_SBLIT, one
;     blitter copy) and the sprite is drawn at its new place right after.
;   - input: key down / up events kept as a joystick-like bit mask (keys), ORed with
;     joystick 1 (SYS_JOY, Horizon 0.15: the DB9 port's directions and trigger) in
;     read_joy; the mouse (WE_BUTTON). When the window loses the focus (WE_UNFOCUS) the
;     held keys are forgotten (Horizon also sends their releases first).
;   - sound effects on POKEY 2 (SYS_SNDW): an envelope per voice, run by the tick.
;   - states: title, play, game over.
;
; The art is text in art/*.txt, turned into art/*.inc by sdk/tools/img2inc.py (make).

        .include "horizon.inc"

; ---------------------------------------------------------------- constants
TS      = 16                            ; tile size
MW      = 20                            ; map size in tiles
MH      = 12
PW      = MW * TS                       ; playfield 320 x 192
PH      = MH * TS
HUDH    = 16                            ; the status strip above it
CW      = PW                            ; window content
CH      = PH + HUDH
KEY     = 231                           ; the transparent colour of sprites
T_FLOOR = 0                             ; tiles (frames of tiles.inc)
T_WALL  = 1
T_GEM   = 2
ST_TITLE = 0
ST_PLAY = 1
ST_OVER = 2
J_UP    = 1                             ; joy bits (the layout of a stick on the DB9 port)
J_DOWN  = 2
J_LEFT  = 4
J_RIGHT = 8
J_FIRE  = 16
C_HUD   = 16 + 36 * 0 + 6 * 0 + 1       ; status strip paper (cube 0 0 1: dark blue)
C_PANEL = 16 + 36 * 0 + 6 * 1 + 2       ; title / game over panel
LIVES   = 3

        .segment "CODE"
        .a16
        .i16

start:  sys     SYS_WSSTART
        bcc     :+
        print   "gemrun: no window system\n"
        exit    1
:       sta     z:wsown
        sys     SYS_BALLOC              ; a 64 KB bank for the background picture
        bcc     :+
        print   "gemrun: not enough memory\n"
        jmp     quit
:       sta     z:bg+2                  ; bg = long pointer bank:0000
        stz     z:bg
        ptr     wopen
        sys     SYS_WOPEN
        jcs     quit
        sta     z:win
        ptr     menus
        lda     z:win
        sys     SYS_WMENU
        lda     z:win                   ; WE_TICK every 2 x 10 ms
        ldx     #2
        sys     SYS_WTIMER
        sys     SYS_UPTIME              ; seed the random numbers
        ora     #1
        sta     z:rnd
        jsr     title

; ---------------------------------------------------------------- the main loop
loop:   lda     #0                      ; wait for an event
        jsr     getev
        jsr     handle
@more:  lda     #1                      ; then take every queued one (poll)
        jsr     getev
        bcs     @step
        jsr     handle
        bra     @more
@step:  lda     z:state                 ; (not playing: the joystick's trigger starts)
        cmp     #ST_PLAY
        beq     :+
        jsr     joystart
:       lda     z:pending               ; the ticks that came: one logic step each
        beq     loop
        cmp     #5                      ; (at most 4: after a long stall, skip ahead)
        bcc     :+
        lda     #4
:       sta     z:pending
@one:   jsr     sfx_tick
        lda     z:state
        cmp     #ST_PLAY
        bne     :+
        jsr     step
:       dec     z:pending
        bne     @one
        lda     z:state                 ; then draw once
        cmp     #ST_PLAY
        bne     loop
        jsr     draw
        bra     loop

; A = 0 wait / 1 poll -> the event in ev; C set: none
getev:  ldx     #.loword(ev)
        ldy     #^ev
        sys     SYS_WEVENT
        rts

; one event (ev: u8 type, u8 window, u16 a, b, c)
handle: lda     ev
        and     #$00FF
        cmp     #WE_TICK
        bne     :+
        inc     z:pending
        rts
:       cmp     #WE_KEY
        beq     onkey
        cmp     #WE_UNFOCUS             ; (another window took the keyboard: no key is
        bne     :+                      ; held for us any more)
        stz     z:keys
        rts
:       cmp     #WE_KEY
        beq     onkey
        cmp     #WE_BUTTON
        jeq     onbutton
        cmp     #WE_MENU
        jeq     onmenu
        cmp     #WE_CLOSE
        jeq     quit
        rts

; WE_KEY: a = HID usage, b = modifiers | down << 8. The bits of held keys are kept in keys.
onkey:  lda     ev+2
        ldx     #0
:       cmp     keytab,x                ; usage -> joy bit
        beq     @bit
        inx
        inx
        inx
        inx
        cpx     #KEYTABN * 4
        bcc     :-
        lda     ev+5                    ; other keys: only presses count
        and     #$00FF
        beq     @out
        lda     ev+2
        cmp     #$29                    ; Esc
        bne     @out
        lda     z:state
        cmp     #ST_TITLE
        jeq     quit                    ; Esc on the title: quit
        jmp     title                   ; else back to the title
@bit:   lda     ev+5                    ; down?
        and     #$00FF
        beq     @up
        lda     keytab+2,x
        tsb     z:keys
        cmp     #J_FIRE                 ; Space / fire starts a game
        bne     @out
        lda     z:state
        cmp     #ST_PLAY
        jne     newgame
@out:   rts
@up:    lda     keytab+2,x
        trb     z:keys
        rts

; WE_BUTTON: a, b = content x, y; c = buttons | modifiers << 8
onbutton:
        lda     ev+6
        and     #1                      ; a left press (c bit 0 set; a release has it clear)
        beq     @out
        lda     z:state
        cmp     #ST_PLAY
        jne     newgame
        lda     ev+2                    ; the target: the pointer, centred on the sprite
        sec
        sbc     #TS / 2
        sta     z:tx
        lda     ev+4
        sec
        sbc     #HUDH + TS / 2
        sta     z:ty
        lda     #1
        sta     z:tgt
@out:   rts

; WE_MENU: a = menu, b = item. Game: New game (0), - (1), Quit (2)
onmenu: lda     ev+4
        jeq     newgame
        cmp     #2
        jeq     quit
        rts

; joy = the keys held | joystick 1 (SYS_JOY: A = the directions, port 1 in bits 0-3 in
; this very layout; X = the triggers, bit 0 port 1)
read_joy:
        lda     z:keys
        sta     z:joy
        lda     #0
        sys     SYS_JOY
        bcs     @out                    ; (a Horizon without it: ENOSYS, the keys only)
        and     #J_UP | J_DOWN | J_LEFT | J_RIGHT
        tsb     z:joy
        txa
        and     #1
        beq     @out
        lda     #J_FIRE
        tsb     z:joy
@out:   rts

; not playing: a new press of joystick 1's trigger starts a game (as Space does)
joystart:
        lda     #0
        sys     SYS_JOY
        bcs     @out
        txa
        and     #1
        cmp     z:jfire
        sta     z:jfire
        bcc     @out                    ; (pressed now, not before: 1 >= 0 and different)
        beq     @out
        jmp     newgame
@out:   rts

; ---------------------------------------------------------------- states
title:  lda     #ST_TITLE
        sta     z:state
        jsr     sfx_off
        jsr     loadmap                 ; the maze behind the panel
        jsr     showall
        jsr     panel
        lda     #8
        ldx     #.loword(s_title)
        jsr     ptext
        lda     #40
        ldx     #.loword(s_help1)
        jsr     ptext
        lda     #56
        ldx     #.loword(s_help2)
        jsr     ptext
        lda     #72
        ldx     #.loword(s_help3)
        jsr     ptext
        stz     z:score
        lda     #LIVES
        sta     z:lives
        lda     #1
        sta     z:level
        jmp     hud

newgame:
        stz     z:score
        lda     #LIVES
        sta     z:lives
        lda     #1
        sta     z:level
        stz     z:keys
newlevel:
        jsr     loadmap
        jsr     showall
        lda     #ST_PLAY
        sta     z:state
        stz     z:tgt
        stz     z:pending
        lda     z:startx                ; the actors at their places
        sta     z:px
        lda     z:starty
        sta     z:py
        lda     z:estx
        sta     z:ex
        lda     z:esty
        sta     z:ey
        jsr     newdir
        stz     z:pfr
        stz     z:efr
        stz     z:invul
        jsr     sync_old
        jsr     drawsprites
        jmp     hud

gameover:
        lda     #ST_OVER
        sta     z:state
        jsr     panel
        lda     #8
        ldx     #.loword(s_over)
        jsr     ptext
        lda     #40
        ldx     #.loword(s_again)
        jsr     ptext
        jmp     sfx_over                ; a falling tone

; ---------------------------------------------------------------- one logic step
step:   inc     z:tick
        jsr     read_joy
        lda     z:invul
        beq     :+
        dec     z:invul
:
; ---- the player: 2 pixels a step, each axis on its own (so it slides along walls)
        stz     z:dx
        stz     z:dy
        lda     z:joy
        bit     #J_LEFT
        beq     :+
        dec     z:dx
:       bit     #J_RIGHT
        beq     :+
        inc     z:dx
:       bit     #J_UP
        beq     :+
        dec     z:dy
:       bit     #J_DOWN
        beq     :+
        inc     z:dy
:       and     #J_UP | J_DOWN | J_LEFT | J_RIGHT
        beq     @mouse
        stz     z:tgt                   ; a key cancels the mouse target
        bra     @move
@mouse: lda     z:tgt                   ; walk towards the clicked point
        beq     @move
        lda     z:tx
        ldx     z:px
        jsr     @sgn
        sta     z:dx
        lda     z:ty
        ldx     z:py
        jsr     @sgn
        sta     z:dy
        ora     z:dx
        bne     @move
        stz     z:tgt                   ; arrived
@move:  lda     z:dx
        beq     @y
        asl     a                       ; 2 pixels
        clc
        adc     z:px
        tax
        ldy     z:py
        jsr     blocked
        bcc     @okx
        lda     z:dy                    ; blocked sideways: near a corridor, slide into it
        bne     @y
        lda     z:py
        jsr     nudge
        tay
        ldx     z:px
        jsr     blocked
        bcs     @y
@okx:   stx     z:px
        sty     z:py
@y:     lda     z:dy
        beq     @anim
        asl     a
        clc
        adc     z:py
        tay
        ldx     z:px
        jsr     blocked
        bcc     @oky
        lda     z:dx                    ; the same, up and down
        bne     @anim
        lda     z:px
        jsr     nudge
        tax
        ldy     z:py
        jsr     blocked
        bcs     @anim
@oky:   stx     z:px
        sty     z:py
@anim:  lda     z:dx                    ; walking: the next frame every 8 steps
        ora     z:dy
        beq     @gem
        lda     z:tick
        and     #7
        bne     @gem
        lda     z:pfr
        eor     #1
        sta     z:pfr
; ---- a gem under the player's centre
@gem:   lda     z:px
        clc
        adc     #TS / 2
        tax
        lda     z:py
        clc
        adc     #TS / 2
        tay
        jsr     mapidx                  ; -> X = index
        lda     map,x
        and     #$00FF
        cmp     #T_GEM
        bne     @enemy
        sep     #$20
        .a8
        lda     #T_FLOOR
        sta     map,x
        rep     #$20
        .a16
        phx
        txa
        jsr     drawtile                ; into the background ...
        pla
        jsr     showtile                ; ... and onto the screen
        lda     z:score
        clc
        adc     #10
        sta     z:score
        jsr     sfx_gem
        jsr     hud
        dec     z:gems
        bne     @enemy
        inc     z:level                 ; every gem: the next level
        jsr     sfx_level
        jmp     newlevel
; ---- the enemy: straight on, a new random direction at a wall
@enemy: lda     z:edx
        clc
        adc     z:ex
        tax
        lda     z:edy
        clc
        adc     z:ey
        tay
        jsr     blocked
        bcc     :+
        jsr     newdir
        bra     @eanim
:       stx     z:ex
        sty     z:ey
@eanim: lda     z:tick
        and     #15
        bne     @hit
        lda     z:efr
        eor     #1
        sta     z:efr
; ---- touching it
@hit:   lda     z:invul
        bne     @out
        lda     z:px
        sec
        sbc     z:ex
        jsr     @abs
        cmp     #12
        bcs     @out
        lda     z:py
        sec
        sbc     z:ey
        jsr     @abs
        cmp     #12
        bcs     @out
        jsr     sfx_hit
        dec     z:lives
        jsr     hud
        lda     z:lives
        jeq     gameover
        lda     z:startx                ; back to the start, safe for 2 s
        sta     z:px
        lda     z:starty
        sta     z:py
        stz     z:tgt
        lda     #100
        sta     z:invul
@out:   rts
; A = target, X = position -> A = -1, 0 or 1 (0 within 1 pixel)
@sgn:   stx     z:t0
        sec
        sbc     z:t0
        beq     @s0
        bmi     @sm
        cmp     #2
        bcc     @s0
        lda     #1
        rts
@sm:    cmp     #$FFFF
        beq     @s0
        lda     #$FFFF
        rts
@s0:    lda     #0
        rts
@abs:   bpl     :+
        eor     #$FFFF
        inc     a
:       rts

; A = a position: moved 2 pixels (1 at the end) towards the nearest multiple of 16 if it
; is at most 6 away, else unchanged. Helps the player turn into corridors.
nudge:  sta     z:t3
        and     #TS - 1
        beq     @same
        cmp     #7
        bcc     @down
        cmp     #10
        bcs     @up
@same:  lda     z:t3
        rts
@down:  cmp     #2
        lda     z:t3
        bcc     :+
        dec     a
:       dec     a
        rts
@up:    cmp     #TS - 1
        lda     z:t3
        bcs     :+
        inc     a
:       inc     a
        rts

; a new direction for the enemy: one of four, at its speed (1 + level / 2, at most 3)
newdir: jsr     random
        and     #3
        asl     a
        tax
        lda     z:level
        lsr     a
        inc     a
        cmp     #4
        bcc     :+
        lda     #3
:       sta     z:t0
        stz     z:edx
        stz     z:edy
        lda     z:t0
        jmp     (@tab,x)
@tab:   .addr   @r, @l, @d, @u
@r:     sta     z:edx
        rts
@l:     eor     #$FFFF
        inc     a
        sta     z:edx
        rts
@d:     sta     z:edy
        rts
@u:     eor     #$FFFF
        inc     a
        sta     z:edy
        rts

; X, Y = a sprite's top left in the playfield -> C set if its box (inset by 2) touches a
; wall or leaves the playfield. Keeps X, Y.
blocked:
        phx
        phy
        cpx     #PW - TS + 1            ; (unsigned: negative values are large)
        bcs     @yes
        cpy     #PH - TS + 1
        bcs     @yes
        stx     z:t1
        sty     z:t2
        lda     #2                      ; the four corners
        ldy     #2
        jsr     @pt
        bcs     @yes
        lda     #TS - 3
        ldy     #2
        jsr     @pt
        bcs     @yes
        lda     #2
        ldy     #TS - 3
        jsr     @pt
        bcs     @yes
        lda     #TS - 3
        ldy     #TS - 3
        jsr     @pt
@yes:   ply
        plx
        rts
@pt:    clc                             ; (t1 + A, t2 + Y) a wall?
        adc     z:t1
        tax
        tya
        clc
        adc     z:t2
        tay
        jsr     mapidx
        lda     map,x
        and     #$00FF
        cmp     #T_WALL
        beq     :+
        clc
        rts
:       sec
        rts

; X, Y = playfield pixel -> X = map index (y / 16 * 20 + x / 16)
mapidx: tya
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     z:t0                    ; row
        asl     a
        asl     a
        clc
        adc     z:t0                    ; * 5
        asl     a
        asl     a                       ; * 20
        sta     z:t0
        txa
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     z:t0
        tax
        rts

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
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        eor     z:rnd
        sta     z:rnd
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        eor     z:rnd
        sta     z:rnd
        rts

; ---------------------------------------------------------------- the map
; map0 holds the level as text: # wall, . floor, * gem, P the player's start, E the
; enemy's. loadmap makes the working copy (tile numbers), counts the gems, finds P and E,
; and draws every tile into the background picture.
loadmap:
        stz     z:gems
        ldx     #0
@l:     lda     map0,x
        and     #$00FF
        ldy     #T_WALL
        cmp     #'#'
        beq     @put
        ldy     #T_GEM
        cmp     #'*'
        bne     :+
        inc     z:gems
        bra     @put
:       ldy     #T_FLOOR
        cmp     #'P'
        bne     :+
        jsr     @pos
        sta     z:starty
        lda     z:t1
        sta     z:startx
        bra     @put
:       cmp     #'E'
        bne     @put
        jsr     @pos
        sta     z:esty
        lda     z:t1
        sta     z:estx
@put:   tya
        sep     #$20
        .a8
        sta     map,x
        rep     #$20
        .a16
        phx
        txa
        jsr     drawtile
        plx
        inx
        cpx     #MW * MH
        bcc     @l
        rts
@pos:   phx                             ; X = index -> t1 = x pixel, A = y pixel
        phy
        stz     z:t0
        txa
:       cmp     #MW
        bcc     :+
        sbc     #MW
        inc     z:t0
        bra     :-
:       asl     a
        asl     a
        asl     a
        asl     a
        sta     z:t1
        lda     z:t0
        asl     a
        asl     a
        asl     a
        asl     a
        ply
        plx
        rts

; A = map index: draw that tile into the background picture (the CPU: 16 rows of 16 bytes
; from tiles.inc to bg). The picture is 320 x 192, 320 bytes a line, at bg (a bank).
drawtile:
        jsr     tilexy                  ; -> t1 = x, t2 = y (pixels)
        lda     map,x                   ; (X = index, from tilexy)
        and     #$00FF
        xba                             ; * 256: the tile's frame in tiles.inc
        clc
        adc     #.loword(tiles)
        sta     z:src
        lda     #^tiles
        sta     z:src+2
        lda     z:t2                    ; dst = bg + y * 320 + x
        jsr     mul320
        clc
        adc     z:t1
        sta     z:dst
        lda     z:bg+2
        sta     z:dst+2
        ldx     #TS                     ; 16 rows
@row:   ldy     #0
:       lda     [src],y                 ; two pixels at a time
        sta     [dst],y
        iny
        iny
        cpy     #TS
        bcc     :-
        lda     z:src
        clc
        adc     #TS
        sta     z:src
        lda     z:dst
        clc
        adc     #PW
        sta     z:dst
        dex
        bne     @row
        rts

; A = map index -> t1 = x, t2 = y of the tile (pixels), X = index
tilexy: tax
        stz     z:t2
:       cmp     #MW
        bcc     :+
        sbc     #MW
        pha
        lda     z:t2
        clc
        adc     #TS
        sta     z:t2
        pla
        bra     :-
:       asl     a
        asl     a
        asl     a
        asl     a
        sta     z:t1
        rts

; A = y -> A = y * 320 (y * 256 + y * 64)
mul320: sta     z:t0
        xba
        and     #$FF00
        sta     z:t3
        lda     z:t0
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     z:t3
        rts

; ---------------------------------------------------------------- drawing
; WD_SBLIT a rectangle of the background picture onto the window, at the same place:
; t1, t2 = x, y in the playfield; t4, t5 = w, h
bgblit: lda     #WD_SBLIT
        sta     blk                     ; op (and c1 = 0, rewritten next)
        lda     #PW
        sta     blk+1                   ; c1 | c2 << 8 = the source stride
        sep     #$20
        .a8
        stz     blk+3                   ; font (unused)
        rep     #$20
        .a16
        lda     z:t1
        sta     blk+4
        lda     z:t2
        clc
        adc     #HUDH
        sta     blk+6
        lda     z:t4
        sta     blk+8
        lda     z:t5
        sta     blk+10
        lda     z:t2                    ; source: bg + y * 320 + x
        jsr     mul320
        clc
        adc     z:t1
        sta     blk+12
        lda     z:bg+2
        sta     blk+14                  ; (writes blk+15 too: blk has 16 bytes)
        jmp     wdraw

; A = map index: that tile from the background onto the window
showtile:
        jsr     tilexy
        lda     #TS
        sta     z:t4
        sta     z:t5
        bra     bgblit

; the whole playfield
showall:
        stz     z:t1
        stz     z:t2
        lda     #PW
        sta     z:t4
        lda     #PH
        sta     z:t5
        bra     bgblit

; X, Y = playfield x, y; A = the frame's address (in this bank): a keyed blit, 16 x 16
kblit:  sta     blk+12
        lda     #WD_KBLIT
        sta     blk
        lda     #KEY << 8               ; c1 = 0, c2 = KEY (skipped)
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
        lda     #TS
        sta     blk+8
        sta     blk+10
        lda     #^player                ; (the art is in this program's bank)
        sta     blk+14
        jmp     wdraw

wdraw:  lda     z:win
        ldx     #.loword(blk)
        ldy     #^blk
        sys     SYS_WDRAW
        rts

; dirty rectangles: put back the background where the sprites were, then draw them
; where they are now. Only when something changed.
draw:   lda     z:px
        cmp     z:opx
        bne     @go
        lda     z:py
        cmp     z:opy
        bne     @go
        lda     z:ex
        cmp     z:oex
        bne     @go
        lda     z:ey
        cmp     z:oey
        bne     @go
        lda     z:pfr
        cmp     z:opfr
        bne     @go
        lda     z:efr
        cmp     z:oefr
        bne     @go
        lda     z:invul                 ; (blinking while invulnerable)
        bne     @go
        rts
; Every win_draw shows on the screen at once, so a sprite must not stay erased for long
; (a video frame could show it missing: flicker): erase and redraw each one in
; consecutive calls. The enemy first, the player over it; if the player's old place
; overlaps the enemy's new one, its erase cut into the enemy: draw the enemy again.
@go:    lda     #TS
        sta     z:t4
        sta     z:t5
        lda     z:oex                   ; the enemy: erase, draw
        sta     z:t1
        lda     z:oey
        sta     z:t2
        jsr     bgblit
        jsr     drawenemy
        lda     z:opx                   ; the player: erase
        sta     z:t1
        lda     z:opy
        sta     z:t2
        jsr     bgblit
        lda     z:opx                   ; overlapping the enemy (|dx| < 16, |dy| < 16)?
        sec
        sbc     z:ex
        jsr     absval
        cmp     #TS
        bcs     :+
        lda     z:opy
        sec
        sbc     z:ey
        jsr     absval
        cmp     #TS
        bcs     :+
        jsr     drawenemy
:       jsr     sync_old
        bra     drawplayer
drawsprites:
        jsr     drawenemy
drawplayer:
        lda     z:invul                 ; invulnerable: shown every other 4 steps
        and     #4
        bne     @out
        lda     z:pfr
        xba
        clc
        adc     #.loword(player)
        ldx     z:px
        ldy     z:py
        jsr     kblit
@out:   rts
drawenemy:
        lda     z:efr
        xba                             ; frame * 256
        clc
        adc     #.loword(enemy)
        ldx     z:ex
        ldy     z:ey
        jmp     kblit
absval: bpl     :+
        eor     #$FFFF
        inc     a
:       rts

sync_old:
        lda     z:px
        sta     z:opx
        lda     z:py
        sta     z:opy
        lda     z:ex
        sta     z:oex
        lda     z:ey
        sta     z:oey
        lda     z:pfr
        sta     z:opfr
        lda     z:efr
        sta     z:oefr
        rts

; the status strip: "SCORE 00120  LIVES 3  LEVEL 1" in the fixed font, white on blue
hud:    ldx     #0
        jsr     @copy
        .addr   s_score
        lda     z:score
        jsr     dec5
        jsr     @copy
        .addr   s_lives
        lda     z:lives
        jsr     dec1
        jsr     @copy
        .addr   s_level
        lda     z:level
        ldy     #10
        jsr     digit
        jsr     dec1
        stz     line,x
        lda     #WD_FILL | (C_HUD << 8) ; the strip
        sta     blk
        stz     blk+4
        stz     blk+6
        lda     #CW
        sta     blk+8
        lda     #HUDH
        sta     blk+10
        jsr     wdraw
        lda     #WD_TEXT | (C_WHITE << 8)
        sta     blk
        lda     #C_HUD | (1 << 8)       ; paper, font 1 (fixed 8x12)
        sta     blk+2
        lda     #8
        sta     blk+4
        lda     #2
        sta     blk+6
        lda     #.loword(line)
        sta     blk+12
        lda     #^line
        sta     blk+14
        jmp     wdraw
; append the string whose address follows the JSR to line (X = position)
@copy:  ply                             ; (the return address - 1 points before the .addr)
        iny
        lda     a:0,y                   ; the string's address
        iny
        phy                             ; return past the .addr
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

; A = 0-65535 -> 5 digits at line,X (dec1: A = 0-9, one digit)
dec5:   ldy     #10000
        jsr     digit
        ldy     #1000
        jsr     digit
        ldy     #100
        jsr     digit
        ldy     #10
        jsr     digit
dec1:   clc                             ; the last digit
        adc     #'0'
        sep     #$20
        .a8
        sta     line,x
        rep     #$20
        .a16
        inx
        rts
; A = value, Y = power of ten: its digit at line,X -> A = the rest
digit:  sty     z:t0                    ; count the subtractions
        ldy     #'0'
:       cmp     z:t0
        bcc     :+
        sbc     z:t0
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

; the title / game over panel: a framed box in the middle of the playfield
panel:  lda     #WD_FILL | (C_PANEL << 8)
        sta     blk
        lda     #40
        sta     blk+4
        lda     #HUDH + 48
        sta     blk+6
        lda     #PW - 80
        sta     blk+8
        lda     #96
        sta     blk+10
        jsr     wdraw
        lda     #WD_FRAME | (C_YELLOW << 8)
        sta     blk
        jmp     wdraw
; A = y in the panel, X = string: centred, fixed font
ptext:  clc
        adc     #HUDH + 48 + 6
        sta     blk+6
        stx     blk+12
        lda     #^s_title
        sta     blk+14
        lda     #1                      ; win_twidth: A = font, X, Y = string
        ldy     #^s_title
        sys     SYS_WTWIDTH             ; -> A = width in pixels
        eor     #$FFFF
        sec
        adc     #PW                     ; x = (PW - width) / 2
        lsr     a
        sta     blk+4
        lda     #WD_TEXT | (C_WHITE << 8)
        sta     blk
        lda     #$FF | (1 << 8)         ; no paper (transparent), font 1
        sta     blk+2
        jmp     wdraw

; ---------------------------------------------------------------- sound (POKEY 2)
; Two voices with an envelope each, stepped by the tick (50 Hz). Voice v uses POKEY
; channel v + 1: AUDF at register 2 v, AUDC at 2 v + 1 (SYS_SNDW: A = register, X = value).
; AUDF: the pitch (f = 63921 / (2 (AUDF + 1)) Hz on the 64 kHz clock); AUDC: distortion
; << 4 | volume ($A0 = a pure tone, $80 = noise). The emulator makes no sound: check with
; run816.py --log-sound (every write is in emu.err).
; v_f: pitch, v_df: added per tick (signed), v_v: volume, v_dv: subtracted per tick,
; v_c: distortion bits, v_n: ticks left
sfx_gem:                                ; a rising blip, voice 0
        ldx     #0
        lda     #60
        ldy     #$FFFC                  ; pitch falls = tone rises
        bra     sfx_set
sfx_level:
        ldx     #0
        lda     #120
        ldy     #$FFFD
        jsr     sfx_set
        lda     #40
        sta     v_n
        rts
sfx_hit:                                ; a noise burst, voice 1
        ldx     #2
        lda     #40
        ldy     #3
        jsr     sfx_set
        lda     #$80
        sta     v_c,x
        rts
sfx_over:                               ; a long falling tone, voice 0
        ldx     #0
        lda     #80
        ldy     #4
        jsr     sfx_set
        lda     #60
        sta     v_n
        lda     #1                      ; slow decay
        sta     v_dv
        rts
; X = voice * 2, A = pitch, Y = pitch step: a pure tone at volume 12 for 12 ticks
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
        stx     z:t0                    ; AUDF of voice v is register 2 v = X
        phx
        lda     v_f,x
        and     #$00FF
        tax
        lda     z:t0
        sys     SYS_SNDW
        plx
        phx                             ; AUDC = distortion | volume
        lda     v_v,x
        ora     v_c,x
        tax
        lda     z:t0
        inc     a
        sys     SYS_SNDW
        plx
        lda     v_f,x                   ; the envelope
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
        sys     SYS_SNDW                ; AUDC = 0: silent
        plx
@next:  inx
        inx
        cpx     #4
        bcc     @v
        rts

sfx_off:
        stz     v_n
        stz     v_n+2
        lda     #1                      ; AUDC1-4 = 0
:       pha
        ldx     #0
        sys     SYS_SNDW
        pla
        inc     a
        inc     a
        cmp     #9
        bcc     :-
        rts

; ---------------------------------------------------------------- the end
quit:   jsr     sfx_off                 ; the sound keeps playing after exit: silence it
        lda     z:win
        sys     SYS_WCLOSE
        lda     z:bg+2                  ; (exit frees banks and windows anyway)
        beq     :+
        sys     SYS_BFREE
:       lda     z:wsown
        beq     :+
        sys     SYS_WSSTOP
:       exit    0

; ---------------------------------------------------------------- data
        .segment "RODATA"
wopen:  .word   (640 - CW - 2) / 2, 60, CW, CH
        .faraddr t_win
        .byte   0
t_win:  .byte   "Gem Run", 0
menus:  .byte   "Game", 0, "New game", 9, "Space", 0, "-", 0, "Quit", 9, "Esc", 0, 0, 0
s_title: .byte  "G E M   R U N", 0
s_help1: .byte  "Collect every gem.", 0
s_help2: .byte  "Arrows / WASD / mouse: move", 0
s_help3: .byte  "Space or click: start", 0
s_over: .byte   "GAME OVER", 0
s_again: .byte  "Space or click: again", 0
s_score: .byte  "SCORE ", 0
s_lives: .byte  "   LIVES ", 0
s_level: .byte  "   LEVEL ", 0
; key -> joy bit: {u16 HID usage, u16 bit}
keytab: .word   $52, J_UP, $51, J_DOWN, $50, J_LEFT, $4F, J_RIGHT
        .word   $1A, J_UP, $16, J_DOWN, $04, J_LEFT, $07, J_RIGHT      ; W S A D
        .word   $2C, J_FIRE
KEYTABN = (* - keytab) / 4
; the level: 20 x 12
map0:   .byte   "####################"
        .byte   "#P.....*....*.....*#"
        .byte   "#.###.####.####.##.#"
        .byte   "#.#*...........*.#.#"
        .byte   "#.#.###.####.###.#.#"
        .byte   "#*....#..E...#....*#"
        .byte   "#.###.#.####.#.###.#"
        .byte   "#...#..........#...#"
        .byte   "###.#.###..###.#.###"
        .byte   "#*....*........*...#"
        .byte   "#....####*.####...*#"
        .byte   "####################"
; the art, made from art/*.txt by sdk/tools/img2inc.py (frames of 256 bytes)
        .include "art/tiles.inc"
        .include "art/player.inc"
        .include "art/enemy.inc"

        .segment "BSS"
ev:     .res    8
blk:    .res    16                      ; win_draw block (15 bytes used)
map:    .res    MW * MH                 ; the level's tiles now
line:   .res    40
v_f:    .res    4                       ; the two voices (2 bytes each)
v_df:   .res    4
v_v:    .res    4
v_dv:   .res    4
v_c:    .res    4
v_n:    .res    4

        .segment "ZEROPAGE"
wsown:  .res    2
win:    .res    2
bg:     .res    4                       ; long pointer: the background picture
src:    .res    4
dst:    .res    4
state:  .res    2
pending: .res   2
tick:   .res    2
keys:   .res    2
joy:    .res    2
jfire:  .res    2                       ; the trigger was down already (not a new press)
rnd:    .res    2
px:     .res    2                       ; the player (playfield pixels)
py:     .res    2
opx:    .res    2                       ; where it was drawn
opy:    .res    2
pfr:    .res    2                       ; its frame
opfr:   .res    2
dx:     .res    2
dy:     .res    2
tx:     .res    2                       ; the mouse target
ty:     .res    2
tgt:    .res    2
ex:     .res    2                       ; the enemy
ey:     .res    2
oex:    .res    2
oey:    .res    2
edx:    .res    2
edy:    .res    2
efr:    .res    2
oefr:   .res    2
startx: .res    2
starty: .res    2
estx:   .res    2
esty:   .res    2
score:  .res    2
lives:  .res    2
level:  .res    2
gems:   .res    2
invul:  .res    2
t0:     .res    2
t1:     .res    2
t2:     .res    2
t3:     .res    2
t4:     .res    2
t5:     .res    2
