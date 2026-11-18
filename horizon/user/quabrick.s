; QUABRICKS - a falling-block puzzle game (/BIN/QUABRICK.PRG), after the owner's SDL2 game of
; the same name: two modes (Marathon: levels and a score to chase; Time Attack: 60 s, clears
; earn seconds), a next queue of five, hold, a ghost outline, soft and hard drop, turns both
; ways with wall kicks, a bag of seven, a lock delay, spins, back-to-back and combos, high
; scores per mode with name entry, pastel beveled blocks, samples on Lau (POKEY 2 without).
;   quabrick            the game
;   quabrick -t         the self test of the rules (no window): text, compared by make test
;   quabrick -s N       the pieces from seed N (pictures that can be repeated)
;   quabrick -q LIST    the first pieces in this order (letters O I J L S Z T), then the bag
;   quabrick -m         measures: at each game's end the frames, the CPU time per frame and
;                       the syscalls per frame are printed on the console
; Files: /BIN/QUABRICK.SFX (the samples, made by tools/mkqbsfx.py; without it, or without
; Lau, the effects play on POKEY 2), /BIN/QUABRICK.DAT (high scores and settings; written when
; they change; the game runs without it and on a card it cannot write).
;
; The frame: in play the program waits for the vertical blank (SYS_VSYNC), takes the events
; queued meanwhile (polling, no waiting), runs one step of the rules and draws only what
; changed: the cells whose picture differs from what the screen shows (shown[]), one blit of a
; pre-made tile each, a line clear as copies inside the window (the rows above move down),
; the panels' numbers when they change. Menus and screens wait for events (no frames).
; (1.1) With Ali's command lists (REV $09+) all of a frame's drawing is one draw list that
; starts in the next vertical blank (qb_draw.s, "the frame's draw list"); the colours are
; palette entries taken with pal_alloc ("the palette" below); the speed rises to instant drops
; and a shrinking lock delay (qb_game.s); the blocks have rounded corners (mkqbart.py).
; Sprites for the falling piece and its ghost were measured and left out (qb_draw.s).
;
; One assembly unit:
;   quabrick.s   start, the window, the palette, events, states, menus, measuring
;   qb_game.s    the rules
;   qb_draw.s    the screens and the well
;   qb_snd.s     the sound effects: Lau samples or POKEY 2
;   qb_file.s    high scores, settings, name entry
;   qb_test.s    the self test
;   qb_data.s    tables, texts, variables; build/qb_art.inc (tools/mkqbart.py) the art
        .include "horizon.inc"
        .include "ui.inc"

; count every syscall of the game (the measurement)
.macro  qsys    n
        inc     nsys
        cop     n
.endmacro

ST_TITLE = 0
ST_SETUP = 1
ST_PLAY  = 2
ST_PAUSE = 3
ST_SWEEP = 4
ST_NAME  = 5
ST_OVER  = 6
ST_SCORES = 7
ST_HELP  = 8

GF_STAGE = 1                            ; gflags: what the rules changed since the last frame
GF_CLEAR = 2
GF_NEXT  = 4
GF_HOLD  = 8
GF_SCORE = 16
GF_STATS = 32
GF_SHAKE = 64
GF_TIMEWON = 128
GF_OVER  = 256
GF_TIME  = 512
BF_B2B   = 1                            ; bonusf: back-to-back, combo
BF_COMBO = 2

        .segment "CODE"
        .a16
        .i16
start:  sta     argl
        stx     argx
        sep     #$20                    ; the program's bank (the blits' pointers)
        .a8
        phb
        pla
        sta     db+14
        rep     #$20
        .a16
        and     #$00FF
        sta     pbank
        jsr     getargs
        jsr     mkcells
        lda     tmode
        beq     :+
        jmp     test_run
:       sys     SYS_WSSTART
        bcc     :+
        print   "quabrick: no window system\n"
        exit    1
:       sta     wsown
        jsr     ui_init
        jsr     loaddat                 ; scores, sound on / off, last mode and level
        jsr     snd_init                ; Lau and the samples, or POKEY 2
        jsr     pal_take                ; its palette entries, the art translated
        bcc     :+
        jsr     stopws
        print   "quabrick: no free palette entries\n"
        exit    1
:       jsr     mkrows
        ptr     wopen
        sys     SYS_WOPEN
        bcc     :+
        jsr     stopws
        print   "quabrick: no window\n"
        exit    1
:       sta     win
        lda     #0
        ptr     s_tname
        sys     SYS_TNAME
        jsr     setmenus
        lda     win                     ; (1.1) Ali's command lists (REV $09+, where WE_VBL
        ldx     #0                      ; exists too: asked by turning it off): frames are
        sys     SYS_WINVBL              ; drawn with one draw list each. Before REV $09 the
        lda     #0                      ; kernel would unroll the list (REV $08: started
        bcs     :+                      ; one by one; REV $07: the CPU) for more CPU time
        inc     a                       ; than the win_draw calls of 1.0 (measured: 765 vs
:       sta     lhw                     ; 685 us a frame on REV $08, 4305 vs 2985 on $07)
        jsr     pal_set
        jsr     to_title
        jmp     loop

stopws: lda     wsown
        beq     :+
        sys     SYS_WSSTOP
:       rts

quit:   jsr     snd_stop
        jsr     pal_restore
        lda     win
        sys     SYS_WCLOSE
        jsr     stopws
        exit    0

; ---------------------------------------------------------------- arguments
getargs:
        stz     tmode
        stz     mflag
        stz     qforce
        sys     SYS_UPTIME
        sta     seed
        stx     seed+2
        lda     argl
        jeq     @out
        ldx     argx
@sp:    lda     f:0,x
        and     #$00FF
        jeq     @out
        cmp     #' '
        bne     :+
        inx
        bra     @sp
:       cmp     #'-'
        jne     @out
        lda     f:1,x
        and     #$00FF
        ora     #$20
        inx
        inx
        cmp     #'t'
        bne     :+
        inc     tmode
        bra     @sp
:       cmp     #'m'
        bne     :+
        inc     mflag
        bra     @sp
:       cmp     #'q'
        bne     @s
:       lda     f:0,x                   ; -q LIST: copied into qlist
        and     #$00FF
        cmp     #' '
        bne     :+
        inx
        bra     :-
:       ldy     #0
:       lda     f:0,x
        and     #$00FF
        beq     :+
        cmp     #' '
        beq     :+
        and     #$DF                    ; (upper case)
        sep     #$20
        .a8
        sta     qlist,y
        rep     #$20
        .a16
        inx
        iny
        cpy     #63
        bcc     :-
:       lda     #0
        sep     #$20
        .a8
        sta     qlist,y
        rep     #$20
        .a16
        lda     #.loword(qlist)
        sta     qfirst
        jmp     @sp
@s:     cmp     #'s'
        bne     @out
        stz     z:g0
:       lda     f:0,x
        and     #$00FF
        cmp     #' '
        bne     :+
        inx
        bra     :-
:       lda     f:0,x
        and     #$00FF
        sec
        sbc     #'0'
        cmp     #10
        bcs     :+
        sta     z:g1
        lda     z:g0
        asl     a
        asl     a
        adc     z:g0
        asl     a
        adc     z:g1
        sta     z:g0
        inx
        bra     :-
:       lda     z:g0
        sta     seed
        lda     #$5EED
        sta     seed+2
        inc     sfixed
        jmp     @sp
@out:   rts

; the generator for a new game: from the seed (-s: the same pieces every game of the session
; follow from it), the forced list (-q) for the first game
seedgame:
        lda     seed
        sta     rng
        lda     seed+2
        sta     rng+2
        ora     rng
        bne     :+
        inc     rng
:       ldx     #8                      ; (stir)
:       phx
        jsr     rand16
        plx
        dex
        bne     :-
        lda     rng                     ; the next game's seed
        sta     seed
        lda     rng+2
        sta     seed+2
        lda     qfirst
        sta     qforce
        stz     qfirst
        rts

; ---------------------------------------------------------------- the palette
; (1.1) The game's NCOLS colours go into palette entries the kernel gives it: pal_alloc(1,
; $FFFF) NCOLS times takes the first free entry each time, in the kernel's order (the spare
; ranges 76-113 and 136-175 that no desktop icon or UI colour uses, then from 16 up), so the
; game works whatever another program (Solitaire, say) already holds. Entries that follow each
; other form runs (one pal_set each: usually two). cmap translates the art's and the drawing
; calls' local colours (1 .. NCOLS, 0 transparent, $FF no paper) into entries: the art once,
; in place, here; the colours of fills, text and the big font in the drawing primitives. The
; entries show the game's colours while its window has the focus (else the system's), and go
; back at its end (pal_restore, and the kernel at exit or kill). C set: none free.
pal_take:
        stz     cmap                    ; (0 stays 0, $FF stays $FF)
        lda     #$00FF
        sta     cmap+$FF
        stz     nruns
        lda     #1
        sta     z:g0                    ; the local colour
@e:     lda     #1
        ldx     #$FFFF
        qsys    SYS_PALALLOC
        bcc     :+
        rts
:       sta     z:g1                    ; its entry
        ldx     z:g0
        sep     #$20
        .a8
        sta     cmap,x
        rep     #$20
        .a16
        lda     nruns                   ; right after the last run: it grows
        beq     @new
        asl     a
        tax
        lda     runend-2,x
        cmp     z:g1
        bne     @new
        inc     a
        sta     runend-2,x
        inc     runcnt-2,x
        bra     @n
@new:   lda     nruns
        asl     a
        tax
        lda     z:g1
        sta     runfirst,x
        inc     a
        sta     runend,x
        lda     z:g0
        sta     runloc,x
        lda     #1
        sta     runcnt,x
        inc     nruns
@n:     inc     z:g0
        lda     z:g0
        cmp     #NCOLS + 1
        bcc     @e
        ldx     #0                      ; the art: local colours -> entries
@a:     lda     qb_art0,x
        and     #$00FF
        tay
        lda     cmap,y
        sep     #$20
        .a8
        sta     qb_art0,x
        rep     #$20
        .a16
        inx
        cpx     #qb_art1 - qb_art0
        bcc     @a
        clc
        rts

; the game's colours into its entries (pal_runs: from the table X, NCOLS x red, green, blue in
; local order: one pal_set per run)
pal_set:
        ldx     #.loword(qb_rgb)
pal_runs:
        stx     z:g2
        stz     z:g3                    ; run * 2
@r:     ldx     z:g3
        lda     runloc,x                ; the table at (local - 1) * 3
        dec     a
        sta     z:g0
        asl     a
        adc     z:g0
        adc     z:g2
        pha
        lda     runcnt,x
        xba
        ora     runfirst,x
        plx
        ldy     pbank
        qsys    SYS_PALSET
        inc     z:g3
        inc     z:g3
        lda     z:g3
        lsr     a
        cmp     nruns
        bcc     @r
        rts

; the pause: every entry that dims at 3/8 (the text over it keeps its own)
pal_dim:
        ldx     #0                      ; local - 1
        ldy     #0                      ; its colour's offset
@e:     lda     qb_dims,x
        and     #$00FF
        sta     z:g4
        jsr     @c
        jsr     @c
        jsr     @c
        inx
        cpx     #NCOLS
        bcc     @e
        ldx     #.loword(palbuf)
        jmp     pal_runs
@c:     lda     qb_rgb,y
        and     #$00FF
        sta     z:g1
        lda     z:g4
        beq     :+
        lda     z:g1                    ; A * 3 / 8
        asl     a
        adc     z:g1
        lsr     a
        lsr     a
        lsr     a
        sta     z:g1
:       lda     z:g1
        sep     #$20
        .a8
        sta     palbuf,y
        rep     #$20
        .a16
        iny
        rts

; the local colour A set to its colour blended towards white by X / 16 (the line-clear flash)
pal_flash:
        stx     z:g2
        sta     z:g4
        dec     a                       ; its colour at (A - 1) * 3
        sta     z:g0
        asl     a
        adc     z:g0
        tax
        phx
        lda     qb_rgb+1,x
        jsr     @w
        xba
        sta     z:g0
        plx
        phx
        lda     qb_rgb,x
        jsr     @w
        ora     z:g0
        sta     z:g0
        plx
        lda     qb_rgb+2,x
        jsr     @w
        tay
        ldx     z:g4
        lda     cmap,x
        and     #$00FF
        ldx     z:g0
        qsys    SYS_WSPAL
        rts
@w:     and     #$00FF                  ; c + (255 - c) * g2 / 16
        sta     z:g1
        eor     #$00FF
        ldy     z:g2
        sta     z:g3
        lda     #0
        cpy     #0
        beq     :++
:       clc
        adc     z:g3
        dey
        bne     :-
:       lsr     a
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     z:g1
        rts

; the entries back to the system (the kernel does it too when the program ends)
pal_restore:
        lda     #0
        sys     SYS_PALALLOC
        rts

; ---------------------------------------------------------------- the loop
loop:   jsr     needframes
        jcc     @wait
        qsys    SYS_VSYNC               ; (it waits for the last frame's list too)
        sta     z:g0
        stz     lpend
        jsr     ltexts                  ; the texts that waited for it
        jsr     flashstep
        lda     mflag
        beq     @poll
        jsr     mstart
@poll:  lda     #1
        jsr     ui_getev
        bcs     @run
        jsr     onevent
        bra     @poll
@run:   jsr     lbegin                  ; what the frame draws: one draw list
        jsr     frame
        jsr     lfin
        jsr     sfx_frame
        lda     mflag
        beq     loop
        jsr     mframe_end
        jmp     loop
@wait:  stz     mvok
        jsr     ltexts
        lda     #0
        jsr     ui_getev
        jcs     loop
        jsr     onevent
        jmp     loop

; -m: a frame's start (the blank counter in g0: blanks missed), its end (the CPU time)
mstart: lda     mvok                    ; (only between two frames of play: not across a pause)
        beq     :+
        lda     state
        cmp     #ST_PLAY
        bne     :+
        lda     z:g0
        sec
        sbc     mvbl
        dec     a
        beq     :+
        bmi     :+
        cmp     #100
        bcs     :+
        clc
        adc     mdrop
        sta     mdrop
:       lda     z:g0
        sta     mvbl
        stz     mvok
        lda     state
        cmp     #ST_PLAY
        bne     :+
        inc     mvok
:       sys     SYS_UPTIME
        sta     mt0
        lda     nsys
        sta     msys0
        rts
mframe_end:   lda     state
        cmp     #ST_PLAY
        bne     :+
        sys     SYS_UPTIME
        sec
        sbc     mt0
        clc
        adc     mbusy
        sta     mbusy
        bcc     :+
        inc     mbusy+2
:       inc     mframes
        lda     nsys                    ; the most in one frame
        sec
        sbc     msys0
        cmp     msysmax
        bcc     :+
        sta     msysmax
:       rts

; frames are needed while playing, sweeping, flashing, shaking or a POKEY effect sounds
needframes:
        lda     state
        cmp     #ST_PLAY
        beq     @yes
        cmp     #ST_SWEEP
        beq     @yes
        lda     flashn
        ora     shaken
        ora     pk_on
        bne     @yes
        clc
        rts
@yes:   sec
        rts

frame:  lda     state
        cmp     #ST_PLAY
        beq     fr_play
        cmp     #ST_SWEEP
        bne     :+
        jmp     fr_sweep
:       jmp     draw_anims              ; (a flash or a shake ending)

fr_play:
        jsr     readjoy
        jsr     step
        stz     kpress
        jsr     draw_play               ; what changed
        lda     over
        beq     :+
        jmp     to_sweep
:       rts

; joystick 1: directions and the trigger as keys (up: hard drop, trigger: turn clockwise)
readjoy:
        lda     #0
        qsys    SYS_JOY
        bcs     @out
        and     #$000F
        tay
        txa
        and     #1
        beq     :+
        lda     #K_CW
:       sta     z:g0
        lda     joymap,y
        and     #$00FF
        ora     z:g0
        sta     z:g0
        eor     jheld                   ; the edges
        and     z:g0
        tsb     kpress
        lda     z:g0                    ; held: the keys' and the stick's
        sta     jheld
        ora     kheldk
        sta     kheld
@out:   rts

; ---------------------------------------------------------------- events
onevent:
        lda     ui_ev
        and     #$00FF
        cmp     #WE_KEY
        jeq     onkey
        cmp     #WE_MENU
        jeq     onmenu
        cmp     #WE_CLOSE
        jeq     quit
        cmp     #WE_UNFOCUS
        beq     @unf
        cmp     #WE_TICK
        jeq     ontick
        cmp     #WE_BUTTON
        beq     @btn
        rts
@unf:   stz     kheld                   ; (the releases came first anyway)
        stz     kheldk
        stz     kpress
        lda     state
        cmp     #ST_PLAY
        bne     :+
        jmp     to_pause
:       rts
@btn:   lda     ui_ev+6
        and     #2
        beq     :+
        jmp     popup
:       rts

; keys: usage in ui_ev+2, down in ui_ev+5
onkey:  lda     ui_ev+2
        and     #$00FF
        sta     z:ku
        lda     ui_ev+5
        and     #$00FF
        sta     z:kd
        lda     state
        cmp     #ST_PLAY
        beq     @play
        lda     z:kd                    ; elsewhere: every press (and repeat) counts
        bne     :+
        rts
:       lda     state
        asl     a
        tax
        jmp     (keytab,x)
@play:  ldx     #0                      ; the game keys: held and pressed (edges)
:       lda     gkeys,x
        and     #$00FF
        cmp     z:ku
        beq     @bit
        inx
        inx
        cpx     #GKEYN * 2
        bcc     :-
        lda     z:kd                    ; others, pressed: Enter, Esc, F2
        beq     @out
        lda     z:ku
        cmp     #$28
        beq     @pause
        cmp     #$58
        beq     @pause
        cmp     #$29
        beq     @pause
        cmp     #$13                    ; P
        beq     @pause
        cmp     #$3B
        bne     @out
        jmp     m_new
@pause: jmp     to_pause
@bit:   lda     gkeys+1,x
        and     #$00FF
        sta     z:g0
        lda     z:kd
        beq     @up
        lda     kheldk
        and     z:g0
        bne     @out                    ; a repeat: nothing new
        lda     z:g0
        tsb     kpress
        tsb     kheldk
        tsb     kheld
@out:   rts
@up:    lda     z:g0
        trb     kheldk
        lda     jheld                   ; (still held on the stick?)
        and     z:g0
        bne     @out
        lda     z:g0
        trb     kheld
        rts

k_none: rts
; the title: Enter or Space the setup, Esc quits, F2 starts at once
k_title:
        lda     z:ku
        cmp     #$29
        bne     :+
        jmp     quit
:       cmp     #$3B
        bne     :+
        jmp     m_new
:       cmp     #$28
        beq     :+
        cmp     #$58
        beq     :+
        cmp     #$2C
        bne     @out
:       lda     #SFX_MSEL
        jsr     sfx
        jmp     to_setup
@out:   rts
; the setup: Up / Down the mode, Left / Right the level, Enter starts, Esc back
k_setup:
        lda     z:ku
        cmp     #$52
        beq     @mode
        cmp     #$51
        beq     @mode
        cmp     #$50
        beq     @left
        cmp     #$4F
        beq     @right
        cmp     #$28
        beq     @go
        cmp     #$58
        beq     @go
        cmp     #$29
        bne     @out
        lda     #SFX_MMOVE
        jsr     sfx
        jmp     to_title
@go:    lda     #SFX_MSEL
        jsr     sfx
        jmp     to_play
@mode:  lda     mode
        eor     #1
        sta     mode
        bra     @chg
@left:  lda     startlv
        cmp     #2
        bcc     @out
        dec     startlv
        bra     @chg
@right: lda     startlv
        cmp     #MAXSTART
        bcs     @out
        inc     startlv
@chg:   lda     #SFX_MMOVE
        jsr     sfx
        jsr     savedat
        jmp     draw_setupvals
@out:   rts
; the pause: Enter resumes, Esc ends the game (to the title)
k_pause:
        lda     z:ku
        cmp     #$28
        beq     @res
        cmp     #$58
        beq     @res
        cmp     #$13
        beq     @res
        cmp     #$29
        bne     :+
        lda     #SFX_MMOVE
        jsr     sfx
        jsr     pal_set
        jmp     to_title
:       cmp     #$3B
        bne     :+
        jsr     pal_set
        jmp     m_new
:       rts
@res:   jmp     resume
; the name: letters, digits, space, Backspace; Enter (or Esc) saves
k_name: lda     z:ku
        cmp     #$28
        beq     @done
        cmp     #$58
        beq     @done
        cmp     #$29
        beq     @done
        cmp     #$2A                    ; Backspace
        bne     :+
        lda     nlen
        beq     @out
        dec     nlen
        bra     @show
:       lda     ui_ev+2                 ; the character (ulib: US layout)
        ldx     ui_ev+4
        jsr     key_ascii
        cmp     #'a'
        bcc     :+
        cmp     #'z' + 1
        bcs     :+
        and     #$DF
:       cmp     #' '
        beq     @ok
        cmp     #'-'
        beq     @ok
        cmp     #'.'
        beq     @ok
        cmp     #'0'
        bcc     @out
        cmp     #'9' + 1
        bcc     @ok
        cmp     #'A'
        bcc     @out
        cmp     #'Z' + 1
        bcs     @out
@ok:    ldx     nlen
        cpx     #NAMEMAX
        bcs     @out
        sep     #$20
        .a8
        sta     nbuf,x
        rep     #$20
        .a16
        inc     nlen
@show:  ldx     nlen
        sep     #$20
        .a8
        stz     nbuf,x
        rep     #$20
        .a16
        lda     #SFX_MMOVE
        jsr     sfx
        jmp     draw_name
@done:  lda     #SFX_MSEL
        jsr     sfx
        jsr     hs_insert               ; -> hrank
        jsr     savedat
        jmp     to_over
@out:   rts
; the game-over screen: Enter the title, Esc quits, F2 again
k_over: lda     z:ku
        cmp     #$3B
        bne     :+
        jmp     m_new
:       cmp     #$29
        bne     :+
        jmp     to_title
:       cmp     #$28
        beq     :+
        cmp     #$58
        bne     @out
:       lda     #SFX_MSEL
        jsr     sfx
        jmp     to_title
@out:   rts
; the high-score tables: Left / Right the other mode; Enter / Esc back
k_scores:
        lda     z:ku
        cmp     #$50
        beq     @sw
        cmp     #$4F
        beq     @sw
        cmp     #$28
        beq     @back
        cmp     #$58
        beq     @back
        cmp     #$29
        beq     @back
        rts
@sw:    lda     vmode
        eor     #1
        sta     vmode
        lda     #SFX_MMOVE
        jsr     sfx
        jmp     draw_scores
@back:  lda     #SFX_MMOVE
        jsr     sfx
        jmp     goback
; how to play: any key back
k_help: lda     #SFX_MMOVE
        jsr     sfx
        jmp     goback

ontick: lda     state                   ; the title's blinking prompt, the name's caret
        cmp     #ST_TITLE
        bne     @n
        lda     blink
        eor     #1
        sta     blink
        beq     :+
        lda     a:cmap+Q_OTEXT            ; (OTEXT: muted / white)
        and     #$00FF
        ldx     #$A09A
        ldy     #$00C8
        qsys    SYS_WSPAL
        rts
:       lda     a:cmap+Q_OTEXT
        and     #$00FF
        ldx     #$FFFF
        ldy     #$00FF
        qsys    SYS_WSPAL
        rts
@n:     cmp     #ST_NAME
        bne     @o
        lda     blink
        eor     #1
        sta     blink
        jmp     draw_caret
@o:     rts

; ---------------------------------------------------------------- states
to_title:
        lda     #ST_TITLE
        sta     state
        stz     blink
        jsr     pal_set
        lda     win
        ldx     #50                     ; the prompt blinks every half second
        sys     SYS_WTIMER
        jmp     draw_title

to_setup:
        lda     #ST_SETUP
        sta     state
        jsr     timeroff
        jsr     pal_set
        jmp     draw_setup

to_play:
        lda     #ST_PLAY
        sta     state
        jsr     timeroff
        jsr     pal_set
        jsr     seedgame
        stz     kpress
        stz     kheld
        stz     kheldk
        stz     jheld
        stz     msgt
        stz     mframes
        stz     mbusy
        stz     mbusy+2
        stz     mdrop
        stz     msysmax
        stz     nsys
        stz     gflags
        jsr     newgame
        jmp     draw_playscreen

to_pause:
        lda     #ST_PAUSE
        sta     state
        lda     #SFX_PAUSE
        jsr     sfx
        jsr     pal_dim
        jmp     draw_pause

resume: lda     #ST_PLAY
        sta     state
        stz     kpress
        lda     #SFX_PAUSE
        jsr     sfx
        jsr     pal_set
        jmp     undraw_pause

to_sweep:
        lda     mflag
        beq     :+
        jsr     report
:       lda     #ST_SWEEP
        sta     state
        stz     sweepn
        rts
fr_sweep:
        jsr     draw_sweep              ; a row a frame from the bottom
        lda     sweepn
        cmp     #SH + 12                ; (and a moment more)
        bcc     :+
        jsr     hs_qualifies
        bcs     to_name
        lda     #$FFFF
        sta     hrank
        jmp     to_over
:       rts

to_name:
        lda     #ST_NAME
        sta     state
        stz     nlen
        stz     nbuf
        stz     blink
        lda     win
        ldx     #40
        sys     SYS_WTIMER
        jmp     draw_namescreen

to_over:
        lda     #ST_OVER
        sta     state
        jsr     timeroff
        jmp     draw_over

timeroff:
        lda     win
        ldx     #0
        sys     SYS_WTIMER
        rts

; back from the high scores or the help: where the player was (a game: paused)
goback: lda     backst
        cmp     #ST_PAUSE
        bne     :+
        lda     #ST_PAUSE
        sta     state
        jsr     draw_playscreen
        jsr     pal_dim
        jmp     draw_pause
:       cmp     #ST_OVER
        bne     :+
        jmp     to_over
:       cmp     #ST_SETUP
        bne     :+
        jmp     to_setup
:       jmp     to_title

; ---------------------------------------------------------------- menus
onmenu: lda     ui_ev+2
        bne     @help
        lda     ui_ev+4                 ; Game: New game, Pause, High scores..., Sound, -, Quit
        asl     a
        tax
        cpx     #6 * 2
        bcs     @out
        jmp     (gtab,x)
@help:  lda     ui_ev+4
        beq     m_help
        cmp     #1
        beq     m_about
@out:   rts

m_new:  jsr     pal_set
        jmp     to_play
m_pause:
        lda     state
        cmp     #ST_PLAY
        bne     :+
        jmp     to_pause
:       cmp     #ST_PAUSE
        bne     :+
        jmp     resume
:       rts
; the high scores (a game in play pauses first)
m_scores:
        jsr     leave
        lda     mode
        sta     vmode
        lda     #ST_SCORES
        sta     state
        jmp     draw_scores
m_sound:
        lda     sndon
        eor     #1
        sta     sndon
        bne     :+
        jsr     snd_stop
:       jsr     setmenus
        jmp     savedat
m_help: jsr     leave
        lda     #ST_HELP
        sta     state
        jmp     draw_help
m_about:
        lda     state
        cmp     #ST_PLAY
        bne     :+
        jsr     to_pause
:       ldx     #.loword(al_about)
        jsr     ui_alert
        rts
; going to another screen: remember where from (a game in play: paused)
leave:  jsr     timeroff
        lda     state
        cmp     #ST_PLAY
        bne     :+
        lda     #ST_PAUSE
:       cmp     #ST_SCORES
        beq     @keep
        cmp     #ST_HELP
        beq     @keep
        cmp     #ST_SWEEP
        bne     :+
        lda     #ST_TITLE
:       cmp     #ST_NAME
        bne     :+
        lda     #ST_TITLE
:       sta     backst
@keep:  jmp     pal_set

; the right button's menu: Pause / Resume, New game, High scores, Sound, Quit
popup:  ldx     #0
        ldy     #0
        lda     state
        cmp     #ST_PAUSE
        bne     :+
        ldx     #.loword(s_resume)
        bra     :++
:       ldx     #.loword(s_pausei)
        cmp     #ST_PLAY
        beq     :+
        lda     #MS_STATE | MS_DIM
        jsr     @c
:       jsr     @s
        ldx     #.loword(s_newg)
        jsr     @s
        ldx     #.loword(s_hsc)
        jsr     @s
        lda     #MS_STATE
        ldx     sndon
        beq     :+
        ora     #MS_CHECK
:       jsr     @c
        ldx     #.loword(s_sound)
        jsr     @s
        ldx     #.loword(s_quit)
        jsr     @s
        lda     #0
        jsr     @c
        lda     win
        ldx     #.loword(mbuf)
        jsr     ui_popup
        cmp     #5
        bcs     @out
        asl     a
        tax
        jmp     (ptab,x)
@out:   rts
@s:     lda     a:0,x                   ; a string and its terminator
        and     #$00FF
        jsr     @c
        inx
        cmp     #0
        bne     @s
        rts
@c:     sep     #$20
        .a8
        sta     mbuf,y
        rep     #$20
        .a16
        iny
        rts

; the menus, the sound's check mark set
setmenus:
        ldx     #0
:       lda     mtmpl,x
        sta     mbuf,x
        inx
        inx
        cpx     #MTMPLN + 1
        bcc     :-
        lda     #MS_STATE
        ldx     sndon
        beq     :+
        ora     #MS_CHECK
:       ldx     #MSOUND
        sep     #$20
        .a8
        sta     mbuf,x
        rep     #$20
        .a16
        lda     win
        ptr     mbuf
        sys     SYS_WMENU
        rts

; ---------------------------------------------------------------- measuring (-m)
; at a game's end: "quabrick: N frames, X us of CPU a frame, Y syscalls a frame"
report: print   "quabrick: "
        lda     mframes
        jsr     put_dec
        print   " frames of play, CPU "
        lda     mbusy                   ; busy ms * 1000 / frames
        ldx     #1000
        jsr     perframe
        jsr     put_dec
        print   " us a frame, "
        lda     mdrop
        jsr     put_dec
        print   " frames missed, "
        lda     nsys                    ; syscalls * 100 / frames
        ldx     #100
        jsr     perframe
        pha
        ldx     #100
        jsr     qdiv
        jsr     put_dec
        print   "."
        pla
        ldx     #100
        jsr     qmod
        cmp     #10
        bcs     :+
        pha
        print   "0"
        pla
:       jsr     put_dec
        print   " syscalls a frame (at most "
        lda     msysmax
        jsr     put_dec
        print   ")\n"
        jmp     out_flush
; A * X / mframes -> A
perframe:
        jsr     mul16
        lda     mframes
        beq     @z
        lda     r32
        sta     z:g0
        lda     r32+2
        sta     z:g1
        ldx     #32
        lda     #0
:       asl     z:g0
        rol     z:g1
        rol     a
        cmp     mframes
        bcc     :+
        sbc     mframes
        inc     z:g0
:       dex
        bne     :--
        lda     z:g0
@z:     rts

; A / X -> A (unsigned 16 bits)
qdiv:   stx     z:g7
        ldy     #0
:       cmp     z:g7
        bcc     :+
        sbc     z:g7
        iny
        bra     :-
:       tya
        rts
; A mod X
qmod:   stx     z:g7
:       cmp     z:g7
        bcc     :+
        sbc     z:g7
        bra     :-
:       rts

        .include "qb_game.s"
        .include "qb_draw.s"
        .include "qb_snd.s"
        .include "qb_file.s"
        .include "qb_test.s"
        .include "qb_data.s"
