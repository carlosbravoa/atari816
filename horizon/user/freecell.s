; FREECELL - the FreeCell patience game (/BIN/FREECELL.PRG).
;   freecell            a game chosen at random (its number shows on the status line)
;   freecell -g N       game N (1-65535): the same number is always the same deal
;   freecell -w         a test position: one move wins (the picture session)
;   freecell -m         measures dragging: at each drop the frames and the CPU time a
;                       frame are printed on the console
;   freecell -t         the self test of the rules (no window): text, compared by make test
;
; One window: the four free cells and the four foundations on top, the eight columns below,
; a status line (game, moves, time, cards left). The cards (40 x 56) are composed once at the
; start from the art of tools/mkfcart.py into three banks registered as sheets; everything is
; drawn with sheet_draw lists (fc_draw.s), redrawing only the region that changed. Mouse:
; drag a card or a run in order to its place (it slides back when the move is not allowed),
; or click it and then click its place; a double click or a right click sends a card home,
; else into a free cell. Safe cards go home by themselves. Keys: U or ctrl-Z undo (all the
; way back), N new game, R restart, G a game number, Esc lets go of the selection.
; Files: /BIN/FREECELL.DAT (the statistics: games played, won, the streaks, the best time),
; /BIN/FREECELL.SFX (the sounds for Lau, from tools/mkfcsfx.py; without it, or without Lau,
; short POKEY 2 tones).
;
; One assembly unit:
;   freecell.s   start, the window, events, menus, the status line, dialogs, statistics
;   fc_game.s    the rules: the deal, moves, the history, the safe moves home
;   fc_draw.s    card images, sheets, the draw lists, dragging and flying, the win
;   fc_snd.s     the sounds
;   fc_test.s    the self test
;   fc_data.s    tables, texts, variables; user/fc_art.inc (tools/mkfcart.py) the art
        .include "horizon.inc"
        .include "ui.inc"

CARDW   = 40                            ; a card
CARDH   = 56
WW      = 432                           ; the window's content
WH      = 320
COLX0   = 14                            ; the first column, the distance between columns
PITCH   = 52
TOPY    = 10                            ; the free cells and foundations
CY0     = 76                            ; the columns: the first card, the room
CBOT    = 300
DSTEP   = 16                            ; a column's step (smaller when it is long)
MINSTEP = 5
STATY   = 304                           ; the status line
STATH   = 16
NP      = 16                            ; piles: cells 0-3, foundations 4-7, columns 8-15
P_FOUND = 4
P_CASC  = 8
PMAX    = 20                            ; cards a pile holds at most (7 + 12 in a column)
ISTRIDE = 26 * CARDW                    ; the cards' banks: 26 cards side by side
HBASE   = $4000                         ; the history in the places' bank: 4 bytes a move
HMAX    = 12000
MF_AUTO = 1                             ; a move made by the program after the one before
DCLICK  = 450                           ; a double click: ms
KEYC    = C_WHITE                       ; the transparent colour of the images (unused there)

        .segment "RODATA"
        .include "fc_art.inc"

.macro  jmi     dst
        bpl     *+5
        jmp     dst
.endmacro

        .segment "CODE"
        .a16
        .i16
start:  sta     argl
        stx     argx
        sep     #$20                    ; the program's bank
        .a8
        phb
        pla
        rep     #$20
        .a16
        and     #$00FF
        sta     pbank
        jsr     getargs
        ldx     #0                      ; banks: the cards (2), the places and the history
:       phx
        sys     SYS_BALLOC
        plx
        bcc     :+
        print   "freecell: not enough memory\n"
        exit    1
:       sta     ibank0,x
        inx
        inx
        cpx     #6
        bcc     :--
        lda     tmode
        beq     :+
        jmp     test_run
:       sys     SYS_WSSTART
        bcc     :+
        print   "freecell: no window system\n"
        exit    1
:       sta     wsown
        jsr     ui_init
        jsr     pal_take
        jsr     mkimages
        jsr     mksheets
        bcc     :+
        jsr     stopws
        print   "freecell: no sheets left\n"
        exit    1
:       jsr     snd_init
        jsr     loadstats
        ptr     wopen
        sys     SYS_WOPEN
        bcc     :+
        jsr     stopws
        print   "freecell: no window\n"
        exit    1
:       sta     win
        lda     #0
        ptr     t_title
        sys     SYS_TNAME
        lda     win
        ptr     menus
        sys     SYS_WMENU
        lda     win
        ldx     #100                    ; a tick a second (the clock)
        sys     SYS_WTIMER
        lda     win                     ; REV $09+ (WE_VBL there: asked by turning it off):
        ldx     #0                      ; the frames start in the vertical blank
        sys     SYS_WINVBL
        lda     #0
        bcs     :+
        ldx     mflag                   ; (-m: no wait for the vertical blank, so the time
        bne     :+                      ; measured is the CPU's, not the wait for the frame)
        lda     #SH_VBL
:       sta     vblok
        lda     #1
        sta     focused
        lda     wmode
        beq     :+
        jsr     testpos
        jsr     shownew
        jmp     loop
:       lda     game_no
        bne     :+
        jsr     nextno
:       jsr     newgame
        jmp     loop

stopws: lda     wsown
        beq     :+
        sys     SYS_WSSTOP
:       rts

quit:   jsr     abandon
        jsr     snd_stop
        lda     #0
        sys     SYS_PALALLOC
        lda     win
        sys     SYS_WCLOSE
        jsr     stopws
        exit    0

; the arguments: -t, -w, -m, -g N (in bank 0)
getargs:
        stz     tmode
        stz     wmode
        stz     mflag
        stz     game_no
        sys     SYS_UPTIME              ; new game numbers: from the time
        sta     nrng
        stx     nrng+2
        ora     nrng+2
        bne     :+
        inc     nrng
:       lda     argl
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
:       cmp     #'w'
        bne     :+
        inc     wmode
        bra     @sp
:       cmp     #'m'
        bne     :+
        inc     mflag
        bra     @sp
:       cmp     #'g'
        bne     @out
        stz     z:t0                    ; the number
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
        sta     z:t1
        lda     z:t0
        asl     a
        asl     a
        adc     z:t0
        asl     a
        adc     z:t1
        sta     z:t0
        inx
        bra     :-
:       lda     z:t0
        sta     game_no
        jmp     @sp
@out:   rts

; the next game number from nrng (1-65535)
nextno: lda     rng                     ; (the deal's generator, borrowed)
        pha
        lda     rng+2
        pha
        lda     nrng
        sta     rng
        lda     nrng+2
        sta     rng+2
:       jsr     rand16
        cmp     #0
        beq     :-
        sta     game_no
        lda     rng
        sta     nrng
        lda     rng+2
        sta     nrng+2
        pla
        sta     rng+2
        pla
        sta     rng
        rts

; ---------------------------------------------------------------- games
; game_no dealt and shown
newgame:
        jsr     deal
shownew:
        stz     started
        stz     running
        stz     tacc
        stz     secs
        stz     stuck
        stz     celeb
        stz     dn
        stz     pressed
        stz     dragging
        stz     fl_on
        lda     #$FFFF
        sta     hid_p
        sta     sel_p
        sta     lcpile
        jsr     draw_all
        jsr     status
        lda     #SFX_DEAL
        jmp     sfx

; the game in play is left (a new one, a restart, the end): it counts as lost
abandon:
        lda     started
        beq     @out
        lda     won
        bne     @out
        stz     started
        stz     st_streak
        jsr     savestats
@out:   rts

; after a move by the player: the cards that are safe go home, then the end or the hint
postmove:
@auto:  jsr     auto_pick
        bcc     @end
        lda     #MF_AUTO
        sta     z:mf
        jsr     animove
        jsr     status
        bra     @auto
@end:   lda     stsave
        beq     :+
        stz     stsave
        jsr     savestats
:       jsr     all_home
        bcs     @win
        jsr     isstuck
        sta     stuck
        jmp     status
@win:   lda     secs0                   ; (the time when the last move was made)
        sta     secs
        stz     running
        lda     #1
        sta     won
        inc     st_won
        inc     st_streak
        lda     st_streak
        cmp     st_best
        bcc     :+
        sta     st_best
        lda     secs                    ; the best time ($FFFF: none yet)
        cmp     st_btime
        bcs     :+
        sta     st_btime
:       jsr     savestats
        stz     stuck
        jsr     status
        lda     #SFX_WIN
        jsr     sfx
        jsr     winanim
        jmp     banner

; a move is made (animove calls it first): the game's first counts, the clock starts
firstmove:
        lda     started
        bne     @out
        inc     started
        inc     st_played
        sys     SYS_UPTIME
        sta     tstart
        stx     tstart+2
        stz     tacc
        lda     focused
        sta     running
        inc     stsave                  ; (saved after the move: postmove)
        lda     win                     ; the ticks from now on: whole seconds of play
        ldx     #100
        sys     SYS_WTIMER
@out:   rts

; the clock: secs = tacc + the running span
clock:  lda     running
        beq     @out
        sys     SYS_UPTIME
        sec
        sbc     tstart
        sta     z:t0
        txa
        sbc     tstart+2
        sta     z:t1
        lda     z:t0                    ; (+ 0.5 s: a tick a second after the start is
        clc                             ; never read as a second too few)
        adc     #500
        sta     z:t0
        bcc     :+
        inc     z:t1
:       ldx     #32                     ; t1:t0 / 1000
        lda     #0
:       asl     z:t0
        rol     z:t1
        rol     a
        cmp     #1000
        bcc     :+
        sbc     #1000
        inc     z:t0
:       dex
        bne     :--
        lda     z:t0
        clc
        adc     tacc
        bcc     :+
        lda     #$FFFF
:       sta     secs
@out:   rts

; ---------------------------------------------------------------- events
loop:   lda     #0
        jsr     ui_getev
        bcs     loop
        ldx     #.loword(noctls)
        jsr     ui_event                ; (makes ui_key)
        lda     ui_ev
        and     #$00FF
        cmp     #WE_BUTTON
        jeq     onbutton
        cmp     #WE_MOTION
        jeq     onmotion
        cmp     #WE_KEY
        jeq     onkey
        cmp     #WE_MENU
        jeq     onmenu
        cmp     #WE_TICK
        jeq     ontick
        cmp     #WE_FOCUS
        jeq     onfocus
        cmp     #WE_UNFOCUS
        jeq     onunfocus
        cmp     #WE_CLOSE
        jeq     quit
        bra     loop

ontick: lda     running
        jeq     loop
        jsr     clock
        jsr     status
        jmp     loop

; the clock stops while the window is not in front
onfocus:
        lda     #1
        sta     focused
        lda     started
        jeq     loop
        lda     won
        jne     loop
        lda     running
        jne     loop
        sys     SYS_UPTIME
        sta     tstart
        stx     tstart+2
        lda     #1
        sta     running
        jmp     loop
onunfocus:
        stz     focused
        lda     dragging                ; a drag cut short: the cards go back
        beq     :+
        jsr     dragback
:       lda     running
        jeq     loop
        jsr     clock
        lda     secs
        sta     tacc
        stz     running
        jmp     loop

onkey:  lda     ui_ev+4
        cmp     #$0100                  ; presses only
        jcc     loop
        lda     dragging
        jne     loop
        lda     ui_ev+2
        cmp     #$29                    ; Esc: the selection let go
        bne     :+
        jsr     unselect
        jmp     loop
:       cmp     #$3B                    ; F2: a new game
        jeq     m_new
        lda     ui_ev+4
        and     #$0011
        beq     @plain
        lda     ui_key
        cmp     #26                     ; ctrl-Z
        jeq     m_undo
        jmp     loop
@plain: lda     ui_ev+4
        and     #$00CC                  ; (no Alt, GUI)
        jne     loop
        lda     ui_key
        ora     #$20
        cmp     #'u'
        jeq     m_undo
        cmp     #'n'
        jeq     m_new
        cmp     #'r'
        jeq     m_restart
        cmp     #'g'
        jeq     m_select
        jmp     loop

; ---------------------------------------------------------------- the mouse
onbutton:
        lda     ui_ev+2
        sta     z:ex
        lda     ui_ev+4
        sta     z:ey
        lda     ui_ev+6
        and     #3
        tax
        eor     btns                    ; what changed
        stx     btns
        sta     z:t0
        and     #1
        beq     @right
        txa
        and     #1
        jne     onpress
        jmp     onrelease
@right: lda     z:t0
        and     #2
        jeq     loop
        txa
        and     #2
        jeq     loop
        lda     dragging                ; a right press: the card home or to a cell
        ora     pressed
        jne     loop
        lda     won
        jne     loop
        jsr     hittest
        jcc     loop
        lda     z:hix
        jmi     loop
        jsr     unselect
        lda     z:hpl
        jsr     sendcard
        jmp     loop

onpress:
        stz     pressed
        lda     won
        jne     loop
        jsr     hittest
        bcc     @none
        lda     z:hix
        bmi     @none
        jsr     pickable
        bcc     @none
        lda     #1
        sta     pressed
        lda     z:hpl
        sta     pp
        lda     z:hix
        sta     pix
        lda     z:ex
        sta     px0
        lda     z:ey
        sta     py0
        jmp     loop
@none:  lda     #$FFFF                  ; a press on a place or the table
        sta     pp
        jmp     loop

onrelease:
        lda     dragging
        jne     drop
        lda     won
        jne     loop
        lda     pressed
        bne     @card
        lda     sel_p                   ; on a place: the selection goes there
        jmi     loop
        jsr     hittest
        bcc     @off
        lda     z:hpl
        jsr     clickmove
        jmp     loop
@off:   jsr     unselect
        jmp     loop
@card:  stz     pressed                 ; a click on a card: the second of a double click?
        sys     SYS_UPTIME
        sta     z:t0
        lda     pp
        cmp     lcpile
        bne     @first
        lda     pix
        cmp     lcidx
        bne     @first
        lda     z:t0
        sec
        sbc     lctime
        cmp     #DCLICK
        bcs     @first
        lda     #$FFFF                  ; yes: home, or a free cell
        sta     lcpile
        jsr     unselect
        lda     pp
        jsr     sendcard
        jmp     loop
@first: lda     pp
        sta     lcpile
        lda     pix
        sta     lcidx
        lda     z:t0
        sta     lctime
        lda     sel_p
        bmi     @sel
        cmp     pp                      ; the same pile: let go
        bne     :+
        jsr     unselect
        jmp     loop
:       lda     pp                      ; another: the selection goes there
        jsr     clickmove
        jmp     loop
@sel:   lda     pp                      ; select it
        sta     sel_p
        lda     pix
        sta     sel_i
        lda     #SFX_PICK
        jsr     sfx
        lda     sel_p
        jsr     redraw_pile
        jsr     flush
        jmp     loop

onmotion:
        lda     ui_ev+2
        sta     z:ex
        lda     ui_ev+4
        sta     z:ey
        lda     dragging
        bne     @move
        lda     pressed
        jeq     loop
        lda     z:ex                    ; a drag starts after 3 pixels
        sec
        sbc     px0
        bpl     :+
        eor     #$FFFF
        inc     a
:       sta     z:t0
        lda     z:ey
        sec
        sbc     py0
        bpl     :+
        eor     #$FFFF
        inc     a
:       clc
        adc     z:t0
        cmp     #3
        jcc     loop
        jsr     unselect
        lda     pp
        ldx     pix
        jsr     lift
        lda     px0                     ; the grip inside the cards
        sec
        sbc     fl_x
        sta     grx
        lda     py0
        sec
        sbc     fl_y
        sta     gry
        lda     #1
        sta     dragging
        lda     #SFX_PICK
        jsr     sfx
        stz     mt_t
        stz     mt_ms
@move:  lda     mflag
        beq     :+
        sys     SYS_UPTIME
        sta     mt_t0
:       lda     z:ey
        sec
        sbc     gry
        tax
        lda     z:ex
        sec
        sbc     grx
        jsr     float_to
        lda     mflag
        jeq     loop
        sys     SYS_UPTIME
        sec
        sbc     mt_t0
        clc
        adc     mt_ms
        sta     mt_ms
        inc     mt_t
        jmp     loop

; the carried cards let go: the pile under them that takes them (the largest overlap)
drop:   stz     dragging
        stz     pressed
        jsr     measure
        lda     #$FFFF
        sta     z:g3                    ; the best pile, its overlap
        stz     z:g4
        stz     z:g2
@p:     lda     z:g2
        cmp     pp
        beq     @n
        jsr     droprect                ; ax .. ah: where a card dropped there would lie
        jsr     overlap
        beq     @n
        cmp     z:g4
        bcc     @n
        sta     z:g5
        lda     pp
        sta     z:ms
        lda     pix
        sta     z:mi
        lda     z:g2
        sta     z:md
        jsr     can_move
        bcc     @n
        lda     z:g5
        sta     z:g4
        lda     z:g2
        sta     z:g3
@n:     inc     z:g2
        lda     z:g2
        cmp     #NP
        bcc     @p
        lda     z:g3
        bmi     @back
        sta     z:md                    ; the move
        lda     pp
        sta     z:ms
        lda     pix
        sta     z:mi
        jsr     can_move
        stz     z:mf
        jsr     animove                 ; (the cards fly from where they were let go)
        jsr     postmove
        jmp     loop
@back:  jsr     dragback
        jmp     loop

; the dragged cards slide back to their place
dragback:
        stz     dragging
        stz     pressed
        lda     #SFX_BAD
        jsr     sfx
        lda     hid_p
        ldx     hid_i
        jsr     cardpos
        lda     z:ax
        ldx     z:ay
        jsr     fly
        jsr     float_end
        jmp     flush

; -m: the frames of the drag and their CPU time
measure:
        lda     mflag
        jeq     @out
        lda     mt_t
        jeq     @out
        print   "freecell: drag "
        lda     mt_t
        jsr     put_dec
        print   " frames, "
        lda     mt_ms
        jsr     put_dec
        print   " ms of CPU: "
        lda     mt_ms                   ; us a frame = ms * 1000 / frames
        ldx     #1000
        jsr     umul32
        ldx     mt_t
        jsr     udiv32
        jsr     put_dec
        print   " us a frame\n"
        jsr     out_flush
@out:   rts

; pile g2 -> ax, ay, aw, ah: the place a card dropped there would take
droprect:
        lda     z:g2
        jsr     pilexy
        lda     #CARDW
        sta     z:aw
        lda     #CARDH
        sta     z:ah
        lda     z:g2
        cmp     #P_CASC
        bcc     @out
        asl     a
        tax
        lda     pcnt,x
        beq     @out
        dec     a
        tax
        lda     z:g2
        jsr     cardpos
@out:   rts

; the carried top card (fl_x, fl_y, CARDW x CARDH) over ax .. ah -> A = the area in common
; (Z: none)
overlap:
        lda     fl_x                    ; x: min(right) - max(left)
        clc
        adc     #CARDW
        sta     z:t1
        lda     z:ax
        clc
        adc     z:aw
        cmp     z:t1
        bpl     :+
        sta     z:t1
:       lda     fl_x
        cmp     z:ax
        bpl     :+
        lda     z:ax
:       eor     #$FFFF
        sec
        adc     z:t1
        bmi     @no
        beq     @no
        sta     z:t2
        lda     fl_y                    ; y
        clc
        adc     #CARDH
        sta     z:t1
        lda     z:ay
        clc
        adc     z:ah
        cmp     z:t1
        bpl     :+
        sta     z:t1
:       lda     fl_y
        cmp     z:ay
        bpl     :+
        lda     z:ay
:       eor     #$FFFF
        sec
        adc     z:t1
        bmi     @no
        beq     @no
        ldx     z:t2
        jsr     umul16
        cmp     #0
        rts
@no:    lda     #0
        rts

; hpl, hix: may the cards from there be taken? -> C set
pickable:
        lda     z:hpl
        cmp     #P_FOUND                ; not from a foundation
        bcc     :+
        cmp     #P_CASC
        bcc     @no
:       lda     z:hpl
        sta     z:ms
        lda     z:hix
        sta     z:mi
        jmp     runok
@no:    clc
        rts

; A = pile: the selection (sel_p, sel_i) goes there if it may: a click on a place
clickmove:
        sta     z:md
        lda     sel_p
        sta     z:ms
        lda     sel_i
        sta     z:mi
        jsr     unselect
        lda     z:md                    ; a foundation: the top card to its own
        cmp     #P_CASC
        bcs     @cas
        jsr     topone
        lda     z:md
        cmp     #P_FOUND
        bcc     @cell
        ldx     z:mc
        lda     csuit,x
        and     #$00FF
        clc
        adc     #P_FOUND
        sta     z:md
        bra     @try
@cell:  lda     z:md                    ; a cell: the first empty one
        asl     a
        tax
        lda     pcnt,x
        beq     @try
        jsr     freecell_no
        bcc     @bad
        sta     z:md
        bra     @try
@cas:   asl     a                       ; an empty column: as many as may go
        tax
        lda     pcnt,x
        bne     @try
        lda     #1
        jsr     maxmove
        sta     z:t0
        lda     z:ms
        asl     a
        tax
        lda     pcnt,x
        sec
        sbc     z:mi
        cmp     z:t0
        bcc     @try
        lda     pcnt,x
        sec
        sbc     z:t0
        sta     z:mi
@try:   jsr     can_move
        bcc     @bad
        stz     z:mf
        jsr     animove
        jsr     postmove
        rts
@bad:   lda     #SFX_BAD
        jmp     sfx

; ms, mi: only the top card of the pile (mi, mc set)
topone: lda     z:ms
        jsr     ptop
        sta     z:mc
        lda     z:ms
        asl     a
        tax
        lda     pcnt,x
        dec     a
        sta     z:mi
        rts

; A = pile: its top card home if it may go, else into a free cell (from a column)
sendcard:
        sta     z:ms
        asl     a
        tax
        lda     pcnt,x
        beq     @bad
        jsr     topone
        ldx     z:mc
        lda     csuit,x
        and     #$00FF
        clc
        adc     #P_FOUND
        sta     z:md
        jsr     can_move
        bcs     @go
        lda     z:ms
        cmp     #P_CASC
        bcc     @bad
        jsr     freecell_no
        bcc     @bad
        sta     z:md
        jsr     can_move
        bcc     @bad
@go:    stz     z:mf
        jsr     animove
        jmp     postmove
@bad:   lda     #SFX_BAD
        jmp     sfx

; -> C set, A = the first empty free cell
freecell_no:
        ldx     #0
:       lda     pcnt,x
        beq     :+
        inx
        inx
        cpx     #8
        bcc     :-
        clc
        rts
:       txa
        lsr     a
        sec
        rts

; the selection let go (redrawn)
unselect:
        lda     sel_p
        bmi     @out
        pha
        lda     #$FFFF
        sta     sel_p
        pla
        jsr     redraw_pile
        jsr     flush
@out:   rts

; the sound of a card put down: home or elsewhere (md)
placesnd:
        lda     z:md
        cmp     #P_FOUND
        bcc     :+
        cmp     #P_CASC
        bcs     :+
        lda     #SFX_HOME
        jmp     sfx
:       lda     #SFX_PLACE
        jmp     sfx

; ---------------------------------------------------------------- menus
onmenu: lda     dragging
        jne     loop
        lda     ui_ev+4
        asl     a
        tax
        lda     ui_ev+2                 ; Game 0, Help 1
        bne     @help
        cpx     #18
        jcs     loop
        jmp     (gtab,x)
@help:  cpx     #4
        jcs     loop
        jmp     (htab,x)

m_new:  jsr     abandon
        jsr     nextno
        jsr     newgame
        jmp     loop
m_restart:
        jsr     abandon
        lda     wmode                   ; (the test position again)
        beq     :+
        lda     game_no
        bne     :+
        jsr     testpos
        jsr     shownew
        jmp     loop
:       jsr     newgame
        jmp     loop
m_undo: lda     won
        jne     loop
        jsr     unselect
        stz     umask                   ; the piles changed (bits)
        stz     z:g4                    ; any undone
@u:     jsr     undo1
        bcc     @done
        inc     z:g4
        lda     z:ms
        jsr     pbit
        lda     z:md
        jsr     pbit
        lda     z:mf
        and     #MF_AUTO
        bne     @u
@done:  lda     z:g4
        bne     :+
        lda     #SFX_BAD
        jsr     sfx
        jmp     loop
:       stz     uidx
@d:     lda     uidx
        asl     a
        tax
        lda     bitn,x
        and     umask
        beq     :+
        lda     uidx
        jsr     redraw_pile
:       inc     uidx
        lda     uidx
        cmp     #NP
        bcc     @d
        jsr     flush
        lda     #SFX_PLACE
        jsr     sfx
        jsr     isstuck
        sta     stuck
        jsr     status
        jmp     loop
pbit:   asl     a
        tax
        lda     bitn,x
        tsb     umask
        rts

; Game > Select game...: the number in a dialog
m_select:
        ldx     game_no
        bne     :+
        ldx     #1
:       stx     pv16
        jsr     dec16
        ldx     #.loword(numbuf)
        ldy     #.loword(dbuf)
        jsr     ui_strcpy
        sta     fd_sel+FD_LEN
        sta     fd_sel+FD_CUR
        stz     fd_sel+FD_ANC
        stz     fd_sel+FD_SCR
        lda     #UF_FOCUS
        sta     fd_sel+CT_FLAGS
        jsr     dlgpause
        ldx     #.loword(dg_sel)
        jsr     ui_dlgopen
        jcs     dlgdone
        ldx     #.loword(dg_sel)
        jsr     ui_dlgrun
        phx
        ldx     #.loword(dg_sel)
        jsr     ui_dlgclose
        jsr     dlgresume
        plx
        cpx     #.loword(bt_sok)
        jne     loop
        ldx     #0                      ; 1-65535
        stz     z:t0
@d:     lda     dbuf,x
        and     #$00FF
        beq     @e
        cmp     #' '
        beq     @sk
        sec
        sbc     #'0'
        cmp     #10
        bcs     @bad
        sta     z:t1
        lda     z:t0
        cmp     #6554
        bcs     @bad
        asl     a
        asl     a
        adc     z:t0
        asl     a
        adc     z:t1
        bcs     @bad
        sta     z:t0
@sk:    inx
        bra     @d
@e:     lda     z:t0
        beq     @bad
        pha
        jsr     abandon
        pla
        sta     game_no
        jsr     newgame
        jmp     loop
@bad:   jsr     ui_beep
        jmp     loop

; Game > Statistics...
m_stats:
        jsr     dlgpause
        jsr     stattext
        ldx     #.loword(dg_stats)
        jsr     ui_dlgopen
        jcs     dlgdone
@run:   ldx     #.loword(dg_stats)
        jsr     ui_dlgrun
        cpx     #.loword(bt_streset)
        bne     @close
        ldx     #.loword(al_reset)
        jsr     ui_alert
        cmp     #0
        bne     @run
        stz     st_played
        stz     st_won
        stz     st_streak
        stz     st_best
        lda     #$FFFF
        sta     st_btime
        lda     started                 ; (a game in play counts from now on, as played)
        beq     :+
        lda     won
        bne     :+
        inc     st_played
:       jsr     savestats
        jsr     stattext
        ldx     #.loword(lb_st1)
        jsr     ui_draw
        ldx     #.loword(lb_st2)
        jsr     ui_draw
        ldx     #.loword(lb_st3)
        jsr     ui_draw
        ldx     #.loword(lb_st4)
        jsr     ui_draw
        ldx     #.loword(lb_st5)
        jsr     ui_draw
        bra     @run
@close: ldx     #.loword(dg_stats)
        jsr     ui_dlgclose
        jmp     dlgdone

; the statistics' lines (stl1 .. stl5)
stattext:
        ldx     #.loword(s_st1)
        lda     st_played
        ldy     #.loword(stl1)
        jsr     @line
        stz     sl
        ldx     #.loword(s_st2)
        jsr     sapp
        lda     st_won
        jsr     sappn
        lda     st_played
        beq     :+
        ldx     #.loword(s_op)
        jsr     sapp
        lda     st_won                  ; percent = won * 100 / played
        ldx     #100
        jsr     umul32
        ldx     st_played
        jsr     udiv32
        jsr     sappn
        ldx     #.loword(s_pc)
        jsr     sapp
:       ldx     #.loword(sbuf)
        ldy     #.loword(stl2)
        jsr     ui_strcpy
        ldx     #.loword(s_st3)
        lda     st_streak
        ldy     #.loword(stl3)
        jsr     @line
        ldx     #.loword(s_st4)
        lda     st_best
        ldy     #.loword(stl4)
        jsr     @line
        stz     sl
        ldx     #.loword(s_st5)
        jsr     sapp
        lda     st_btime
        cmp     #$FFFF
        bne     :+
        ldx     #.loword(s_none)
        jsr     sapp
        bra     :++
:       jsr     sappt
:       ldx     #.loword(sbuf)
        ldy     #.loword(stl5)
        jmp     ui_strcpy
@line:  phy
        pha
        stz     sl
        jsr     sapp
        pla
        jsr     sappn
        ply
        ldx     #.loword(sbuf)
        jmp     ui_strcpy

m_help: jsr     dlgpause
        ldx     #.loword(dg_help)
        jsr     ui_dlgopen
        jcs     dlgdone
        ldx     #.loword(dg_help)
        jsr     ui_dlgrun
        ldx     #.loword(dg_help)
        jsr     ui_dlgclose
        jmp     dlgdone
m_about:
        jsr     dlgpause
        ldx     #.loword(al_about)
        jsr     ui_alert
dlgdone:
        jsr     dlgresume
        jmp     loop

; the clock stops while one of the program's dialogs is open (dlgpause .. dlgresume)
dlgpause:
        lda     running
        sta     wasrun
        beq     :+
        jsr     clock
        lda     secs
        sta     tacc
        stz     running
:       jmp     status
dlgresume:
        lda     wasrun
        beq     :+
        stz     wasrun
        sys     SYS_UPTIME
        sta     tstart
        stx     tstart+2
        lda     #1
        sta     running
        lda     win
        ldx     #100
        sys     SYS_WTIMER
:       jmp     status

; ---------------------------------------------------------------- statistics
; /BIN/FREECELL.DAT, 14 bytes: "FCS1", u16 played, won, the current streak, the best streak,
; the best time in seconds ($FFFF: none). Read at the start (missing or not ours: zeros), written
; whenever it changes; a card that cannot be written is fine.
DATLEN  = 14
loadstats:
        stz     st_played
        stz     st_won
        stz     st_streak
        stz     st_best
        lda     #$FFFF
        sta     st_btime
        lda     #O_READ
        ptr     p_dat
        sys     SYS_OPEN
        bcs     @out
        sta     z:g0
        jsr     iofile
        sys     SYS_READ
        php
        pha
        lda     z:g0
        sys     SYS_CLOSE
        pla
        plp
        bcs     @out
        cmp     #DATLEN
        bne     @out
        lda     fbuf
        cmp     #$4346                  ; "FC"
        bne     @out
        lda     fbuf+2
        cmp     #$3153                  ; "S1"
        bne     @out
        ldx     #8
:       lda     fbuf+4,x
        sta     st_played,x
        dex
        dex
        bpl     :-
@out:   rts

savestats:
        lda     #$4346
        sta     fbuf
        lda     #$3153
        sta     fbuf+2
        ldx     #8
:       lda     st_played,x
        sta     fbuf+4,x
        dex
        dex
        bpl     :-
        lda     #O_CREATE
        ptr     p_dat
        sys     SYS_OPEN
        bcs     @out
        sta     z:g0
        jsr     iofile
        sys     SYS_WRITE
        lda     z:g0
        sys     SYS_CLOSE
@out:   rts
; the read / write block: handle g0, fbuf, DATLEN -> X, Y
iofile: lda     z:g0
        sep     #$20
        .a8
        sta     iob
        rep     #$20
        .a16
        lda     #.loword(fbuf)
        sta     iob+1
        lda     pbank
        sep     #$20
        .a8
        sta     iob+3
        rep     #$20
        .a16
        lda     #DATLEN
        sta     iob+4
        ptr     iob
        rts

; ---------------------------------------------------------------- the status line
; "Game 1234" left (then the hint), "Moves 12    Time 1:23    Cards left 40" right
status: lda     win
        sta     z:ui_win
        stz     z:ui_font
        stz     z:ui_x                  ; the rows above and below the text
        lda     #WW
        sta     z:ui_w
        lda     #STATY
        sta     z:ui_y
        lda     #3
        sta     z:ui_h
        jsr     @fill
        lda     #STATY + 14
        sta     z:ui_y
        lda     #2
        sta     z:ui_h
        jsr     @fill
        lda     #STATY + 3
        sta     z:ui_y
        lda     #11
        sta     z:ui_h
        stz     sl                      ; left: the game
        lda     game_no
        bne     :+
        ldx     #.loword(s_test)
        jsr     sapp
        bra     :++
:       ldx     #.loword(s_game)
        jsr     sapp
        lda     game_no
        jsr     sappn
:       stz     z:ui_x
        lda     #8
        sta     z:ui_w
        jsr     @fill
        lda     #8
        sta     z:ui_x
        lda     cmapw+2*FC_STXT
        jsr     @text                   ; ui_x = after it
        lda     stuck
        beq     :+
        lda     z:ui_x                  ; the hint
        sta     z:t5
        lda     #16
        sta     z:ui_w
        jsr     @fill
        lda     z:t5
        clc
        adc     #16
        sta     z:ui_x
        stz     sl
        ldx     #.loword(s_stuck)
        jsr     sapp
        lda     cmapw+2*FC_HINT
        jsr     @text
:       lda     z:ui_x
        sta     z:t5                    ; the gap starts here
        stz     sl                      ; right: moves, time, cards left
        ldx     #.loword(s_moves)
        jsr     sapp
        lda     moves
        jsr     sappn
        ldx     #.loword(s_gap)
        jsr     sapp
        ldx     #.loword(s_time)
        jsr     sapp
        jsr     clock
        lda     secs
        jsr     sappt
        ldx     #.loword(s_gap)
        jsr     sapp
        ldx     #.loword(s_left)
        jsr     sapp
        jsr     cardsleft
        jsr     sappn
        ldx     #.loword(sbuf)
        lda     #0
        jsr     ui_twidth
        sta     z:t6
        lda     #WW - 8
        sec
        sbc     z:t6
        sta     z:t7                    ; its x
        sec
        sbc     z:t5
        beq     :+
        bmi     :+
        sta     z:ui_w
        lda     z:t5
        sta     z:ui_x
        jsr     @fill
:       lda     z:t7
        sta     z:ui_x
        lda     cmapw+2*FC_STXT
        jsr     @text
        lda     #8
        sta     z:ui_w
        jmp     @fill
; sbuf at ui_x in colour A on the strip -> ui_x after it
@text:  and     #$00FF
        sta     z:t4
        lda     cmapw+2*FC_STRIP
        xba
        and     #$FF00
        ora     z:t4
        ldx     #.loword(sbuf)
        jsr     ui_text
        ldx     #.loword(sbuf)
        lda     #0
        jsr     ui_twidth
        clc
        adc     z:ui_x
        sta     z:ui_x
        rts
@fill:  lda     cmapw+2*FC_STRIP
        xba
        and     #$FF00
        ora     #WD_FILL
        jmp     ui_rect

; -> A = the cards not home
cardsleft:
        lda     #0                      ; (the win: all home, on display)
        ldx     celeb
        bne     :+
        lda     #52
        sec
        sbc     pcnt+2*P_FOUND
        sec
        sbc     pcnt+2*P_FOUND+2
        sec
        sbc     pcnt+2*P_FOUND+4
        sec
        sbc     pcnt+2*P_FOUND+6
:       rts

; append the string X / the number A / the time A (m:ss) / the character A to sbuf
sapp:   ldy     sl
:       lda     a:0,x
        and     #$00FF
        sep     #$20
        .a8
        sta     sbuf,y
        rep     #$20
        .a16
        beq     :+
        inx
        iny
        bra     :-
:       sty     sl
        rts
sappn:  sta     pv16
        jsr     dec16
        ldx     #.loword(numbuf)
        bra     sapp
sappt:  pha
        ldx     #60
        jsr     udiv16
        jsr     sappn
        lda     #':'
        jsr     sapc
        pla
        ldx     #60
        jsr     umod16
        cmp     #10
        bcs     :+
        pha
        lda     #'0'
        jsr     sapc
        pla
:       bra     sappn
sapc:   ldy     sl
        and     #$00FF
        sta     sbuf,y
        iny
        sty     sl
        rts

; pv16 -> numbuf (decimal, unsigned)
dec16:  ldx     #0                      ; digits, last first
:       lda     pv16
        jsr     div10r                  ; A = quotient, t2 = remainder
        sta     pv16
        lda     z:t2
        ora     #'0'
        pha
        inx
        lda     pv16
        bne     :-
        ldy     #0
:       pla
        sep     #$20
        .a8
        sta     numbuf,y
        rep     #$20
        .a16
        iny
        dex
        bne     :-
        lda     #0
        sta     numbuf,y
        rts
; A / 10 -> A, t2 = the remainder (keeps X)
div10r: ldy     #0
        cmp     #10000
        bcc     @s
        ldy     #0                      ; (large: by 1000s first)
:       cmp     #1000
        bcc     :+
        sbc     #1000
        iny
        bra     :-
:       sta     z:t2
        tya                             ; A = thousands: the quotient so far * 100
        sta     z:t3
        asl     a
        asl     a
        adc     z:t3                    ; * 5
        asl     a                       ; * 10
        sta     z:t3
        asl     a
        asl     a
        asl     a                       ; * 80
        clc
        adc     z:t3
        adc     z:t3                    ; * 100
        tay
        lda     z:t2
@s:     cmp     #10
        bcc     :+
        sbc     #10
        iny
        bra     @s
:       sta     z:t2
        tya
        rts

; A / X -> A (unsigned 16), A mod X
udiv16: stx     z:t3
        ldy     #0
:       cmp     z:t3
        bcc     :+
        sbc     z:t3
        iny
        bra     :-
:       tya
        rts
umod16: stx     z:t3
:       cmp     z:t3
        bcc     :+
        sbc     z:t3
        bra     :-
:       rts
; A * X -> A (low 16 bits)
umul16: stx     z:t3
        sta     z:t4
        lda     #0
        ldx     #16
:       asl     a
        asl     z:t4
        bcc     :+
        clc
        adc     z:t3
:       dex
        bne     :--
        rts
; A * X -> t1:t0 (32 bits)
umul32: stx     z:t3
        sta     z:t4
        stz     z:t0
        stz     z:t1
        ldx     #16
:       asl     z:t0
        rol     z:t1
        asl     z:t4
        bcc     :+
        lda     z:t0
        clc
        adc     z:t3
        sta     z:t0
        lda     z:t1
        adc     #0
        sta     z:t1
:       dex
        bne     :--
        rts
; t1:t0 / X -> A (the quotient's low 16 bits)
udiv32: stx     z:t3
        lda     #0
        ldx     #32
:       asl     z:t0
        rol     z:t1
        rol     a
        cmp     z:t3
        bcc     :+
        sbc     z:t3
        inc     z:t0
:       dex
        bne     :--
        lda     z:t0
        rts

; the end: a panel over the empty top row
banner: lda     win
        sta     z:ui_win
        lda     #COLX0 - 4
        sta     z:ui_x
        lda     #TOPY - 2
        sta     z:ui_y
        lda     #WW - 2 * (COLX0 - 4)
        sta     z:ui_w
        lda     #CARDH + 4
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        lda     #WD_FRAME | (C_BLACK << 8)
        jsr     ui_rect
        inc     z:ui_x
        inc     z:ui_y
        dec     z:ui_w
        dec     z:ui_w
        dec     z:ui_h
        dec     z:ui_h
        lda     #0
        jsr     ui_bevel
        stz     sl
        ldx     #.loword(s_won1)
        jsr     sapp
        lda     #14
        jsr     @line
        stz     sl
        lda     game_no
        beq     :+
        ldx     #.loword(s_game)
        jsr     sapp
        lda     game_no
        jsr     sappn
        ldx     #.loword(s_in)
        jsr     sapp
        bra     :++
:       ldx     #.loword(s_test)
        jsr     sapp
        ldx     #.loword(s_in)
        jsr     sapp
:       lda     moves
        jsr     sappn
        ldx     #.loword(s_mvs)
        jsr     sapp
        lda     secs
        jsr     sappt
        lda     #31
        jsr     @line
        stz     sl
        ldx     #.loword(s_won3)
        jsr     sapp
        lda     #48
@line:  sta     z:ui_y                  ; sbuf centred at row A
        ldx     #.loword(sbuf)
        lda     #0
        jsr     ui_twidth
        eor     #$FFFF
        sec
        adc     #WW
        lsr     a
        sta     z:ui_x
        stz     z:ui_font
        lda     #C_BLACK | (C_BODY << 8)
        ldx     #.loword(sbuf)
        jmp     ui_text

; bit n of a word
        .segment "RODATA"
bitn:   .repeat 16, I
        .word   1 << I
        .endrepeat
        .segment "CODE"

        .include "fc_game.s"
        .include "fc_draw.s"
        .include "fc_snd.s"
        .include "fc_test.s"
        .include "fc_data.s"
