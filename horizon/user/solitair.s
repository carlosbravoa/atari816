; SOLITAIRE - patience games (/BIN/SOLITAIR.PRG): Klondike (draw one or three) and FreeCell.
;   solitair            a Klondike game, a deal chosen at random
;   solitair -d N       Klondike deal N (1-65535); -f N: FreeCell deal N
;   solitair -t         the self test (no window): scripted games and random play
;   solitair -s         shows a FreeCell game won move by move (the picture session)
;
; One window: the table (piles of 35 x 48 cards drawn by the program, sol_art.s) and a
; status line (game, deal number, score, moves, time). Mouse: drag a card or a run of cards
; to another pile (it flies back if the move is not allowed); a double click sends a card to
; its foundation; a click on the stock draws (or turns the waste over). When the rest is
; only cards going home (no stock, waste or face-down card; every column in order), the
; program finishes the game itself. Keys: ctrl-Z undo (any number of moves), F2 new game.
; Menus: Game (new game, restart the deal, choose a deal, Klondike / FreeCell, close), Edit
; (undo), Options (draw one / three, three card backs).
;
; One assembly unit:
;   solitair.s   start, the window, events, menus, the status line, dialogs
;   sol_game.s   the rules: piles, deals, moves, history, score, the end
;   sol_draw.s   card images, the off-screen table, dragging and flying cards, the win
;   sol_art.s    the pixel art
;   sol_test.s   the self test (sol_tscript.inc: its scripts, from tests/solitair_gen.py)
        .include "horizon.inc"
        .include "ui.inc"

K_STOCK = 0                             ; Klondike piles
K_WASTE = 1
K_FOUND = 2
K_TAB   = 6
F_CELL  = 0                             ; FreeCell piles
F_FOUND = 4
F_TAB   = 8
NPMAX   = 16
HMAX    = 10000                         ; moves kept for undo (then the oldest half goes)
DCLICK  = 500                           ; a double click: ms

        .segment "CODE"
        .a16
        .i16
start:  sta     argl
        stx     argx
        jsr     getargs
        ldx     #0                      ; banks: history, table (2), images (2), work
:       phx
        sys     SYS_BALLOC
        plx
        bcc     :+
        print   "solitair: not enough memory\n"
        exit    1
:       sta     hbank,x
        inx
        inx
        cpx     #12
        bcc     :--
        lda     hbank
        sta     z:hp+2
        sta     z:hbase+2
        stz     z:hbase
        lda     tmode
        beq     :+
        jmp     test_run
:       sys     SYS_WSSTART
        bcc     :+
        print   "solitair: no window system\n"
        exit    1
:       sta     wsown
        jsr     ui_init
        jsr     palclaim
        jsr     mkrows
        jsr     mkimages
        ptr     wopen
        sys     SYS_WOPEN
        bcc     :+
        jsr     stopws
        print   "solitair: no window\n"
        exit    1
:       sta     win
        jsr     setmenus
        lda     win
        ldx     #100                    ; a tick a second (the clock)
        sys     SYS_WTIMER
        jsr     newdeal
        lda     smode
        jeq     loop
        jsr     showplay
        jmp     loop

stopws: lda     wsown
        beq     :+
        sys     SYS_WSSTOP
:       rts

; (0.18) the six system cube entries of the card backs (backcol) become ours, at their
; place and with their system colours (nothing visible changes), so the kernel never gives
; them to another program, whose own colours would then show in our backs while it is in
; front (Quabricks did). One call per entry; EAGAIN (another program holds it) ignored.
palclaim:
        ldy     #0
:       phy
        lda     backcol,y
        and     #$00FF
        tax
        lda     #1
        sys     SYS_PALALLOC
        ply
        iny
        cpy     #6
        bcc     :-
        rts

quit:   lda     win
        sys     SYS_WCLOSE
        jsr     stopws
        exit    0

; the arguments: -t, -s, -d N, -f N (in bank 0)
getargs:
        stz     tmode
        stz     smode
        stz     game
        stz     draw3
        sys     SYS_UPTIME              ; the deals' own generator: from the time, or -d / -f
        sta     nrng
        stx     nrng+2
        ora     nrng+2
        bne     :+
        inc     nrng
:       stz     deal_no
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
        bne     @out
        lda     f:1,x
        and     #$00FF
        ora     #$20
        inx
        inx
        cmp     #'t'
        bne     :+
        inc     tmode
        rts
:       cmp     #'s'
        bne     :+
        inc     smode
        lda     #1
        sta     game
        lda     #TSHOWDEAL
        sta     deal_no
        rts
:       cmp     #'f'
        bne     :+
        inc     game
        bra     @num
:       cmp     #'d'
        bne     @out
@num:   stz     z:t0                    ; the number
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
        sta     deal_no
        sta     nrng                    ; (the next deals follow from it)
        stz     nrng+2
        inc     nrng
@out:   rts

; ---------------------------------------------------------------- games
; a new deal: deal_no if set, else the next from nrng
newdeal:
        lda     deal_no
        bne     :+
        lda     nrng
        ldx     nrng+2
        sta     rng
        stx     rng+2
        lda     #65535
        jsr     rand_n
        inc     a
        sta     deal_no
        lda     rng
        ldx     rng+2
        sta     nrng
        stx     nrng+2
:       ; fall through
; the game deal_no from the start
restart:
        jsr     deal
        stz     secs
        stz     timing
        stz     z:pressed
        stz     z:dragging
        stz     lcpile
        dec     lcpile
        jsr     setlayout
        jsr     drawtable
        jmp     status

; after a move: the status, the end of the game, the finish by itself
postmove:
        lda     timing                  ; the clock starts with the first move
        bne     :+
        lda     smode                   ; (not in the replay)
        bne     :+
        inc     timing
        sys     SYS_UPTIME
        sta     tstart
        stx     tstart+2
:       jsr     status
        lda     won
        bne     @out
        jsr     all_home
        bcs     @win
        jsr     trivial
        bcc     @out
@auto:  jsr     auto_pick               ; the rest goes home
        bcc     @chk
        lda     #8
        sta     z:frames
        lda     #12
        sta     z:arc
        jsr     animove
        jsr     status
        bra     @auto
@chk:   jsr     all_home
        bcc     @out
@win:   lda     timing                  ; the clock stops
        beq     :+
        jsr     clock
:       lda     #1
        sta     won
        stz     timing
        jsr     status
        lda     #1                      ; the table without the empty places
        sta     noslots
        jsr     drawtable
        jsr     winanim
        stz     noslots
        jsr     banner
@out:   rts

; the move checked by can_move (ms, mi, md), flown: lift, do it, fly to its place, draw
animove:
        lda     z:ms
        sta     z:ds
        lda     z:mi
        sta     z:di
        lda     z:md
        pha
        jsr     lift
        jsr     unshow2
        jsr     can_move                ; (mn again)
        jsr     do_move
        pla
        sta     z:g8                    ; the place of the first card moved
        jsr     ptyp
        cmp     #PT_TAB
        bne     :+
        lda     z:g8
        jsr     layout
:       lda     z:g8
        asl     a
        tax
        lda     pcnt,x
        sec
        sbc     z:dn
        tax
        lda     z:g8
        jsr     cardpos
        ldx     z:cy
        lda     z:cx
        jsr     fly
        jsr     redirty
        jmp     unshow

; -s: the FreeCell game of the self test, move by move
showplay:
        lda     #100
        sys     SYS_SLEEP
        ldx     #0
@m:     lda     tshow,x
        and     #$00FF
        cmp     #$FF
        beq     @out
        sta     z:ms
        lda     tshow+1,x
        and     #$00FF
        sta     z:mi
        lda     tshow+2,x
        and     #$00FF
        sta     z:md
        inx
        inx
        inx
        stx     shx
        lda     won
        bne     @out
        jsr     can_move
        bcc     @out
        lda     #6
        sta     z:frames
        lda     #8
        sta     z:arc
        jsr     animove
        jsr     postmove
        ldx     shx
        bra     @m
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
        cmp     #WE_CLOSE
        jeq     quit
        bra     loop

ontick: lda     timing
        jeq     loop
        jsr     clock
        jsr     status
        jmp     loop

; secs = the seconds since tstart
clock:  sys     SYS_UPTIME
        sec
        sbc     tstart
        sta     z:t0
        txa
        sbc     tstart+2
        sta     z:t1
        ldx     #32                     ; t1:t0 / 1000 (shift and subtract)
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
        lda     z:t1                    ; (over 18 hours: kept at 65535)
        beq     :+
        lda     #$FFFF
        sta     z:t0
:       lda     z:t0
        sta     secs
        rts

onkey:  lda     ui_ev+4
        cmp     #$0100
        jcc     loop
        lda     z:dragging
        jne     loop
        lda     ui_ev+2
        cmp     #$3B                    ; F2
        jeq     m_new
        lda     ui_ev+4
        and     #$0011
        jeq     loop
        lda     ui_key
        cmp     #26                     ; ctrl-Z
        jeq     m_undo
        jmp     loop

onbutton:
        lda     ui_ev+2
        sta     z:ex
        lda     ui_ev+4
        sta     z:ey
        lda     ui_ev+6
        and     #1
        jeq     @rel
        lda     won                     ; a press
        jne     loop
        lda     z:ey
        cmp     #TH
        jcs     loop
        jsr     hittest
        jcc     loop
        lda     z:hpl
        jsr     ptyp
        cmp     #PT_STOCK
        bne     :+
        jsr     draw_stock              ; the stock: draw
        jcc     loop
        jsr     redirty
        jsr     postmove
        jmp     loop
:       lda     z:hi
        bmi     @none
        jsr     pickable
        bcc     @none
        lda     #1
        sta     z:pressed
        lda     z:hpl
        sta     ppile
        lda     z:hi
        sta     pidx
        lda     z:ex
        sta     px0
        lda     z:ey
        sta     py0
@none:  jmp     loop
@rel:   lda     z:dragging
        jne     drop
        lda     z:pressed
        jeq     loop
        stz     z:pressed               ; a click: the second of a double click?
        sys     SYS_UPTIME
        sta     z:t0
        lda     ppile
        cmp     lcpile
        bne     @first
        lda     pidx
        cmp     lcidx
        bne     @first
        lda     z:t0
        sec
        sbc     lctime
        cmp     #DCLICK
        bcs     @first
        lda     #$FFFF                  ; yes: home if it can go
        sta     lcpile
        lda     ppile
        sta     z:ms
        lda     pidx
        sta     z:mi
        jsr     found_for
        jcc     loop
        lda     #8
        sta     z:frames
        lda     #16
        sta     z:arc
        jsr     animove
        jsr     postmove
        jmp     loop
@first: lda     ppile
        sta     lcpile
        lda     pidx
        sta     lcidx
        lda     z:t0
        sta     lctime
        jmp     loop

onmotion:
        lda     ui_ev+2
        sta     z:ex
        lda     ui_ev+4
        sta     z:ey
        lda     z:dragging
        bne     @move
        lda     z:pressed
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
        lda     ppile
        sta     z:ds
        lda     pidx
        sta     z:di
        jsr     lift
        jsr     unshow2
        lda     px0                   ; the grip inside the cards
        sec
        sbc     z:dx
        sta     grx
        lda     py0
        sec
        sbc     z:dy
        sta     gry
        lda     #1
        sta     z:dragging
@move:  lda     z:ey
        sec
        sbc     gry
        tax
        lda     z:ex
        sec
        sbc     grx
        jsr     carry
        jmp     loop

; the carried cards let go: the pile under them that takes them (the largest overlap)
drop:   stz     z:dragging
        stz     z:pressed
        stz     bestp
        dec     bestp
        stz     besta
        stz     z:g8
@p:     lda     z:g8
        cmp     npiles
        bcs     @done
        cmp     z:ds
        beq     @n
        jsr     droprect                ; bx .. bh: where it would go
        jsr     overlap
        cmp     #0
        beq     @n
        cmp     besta
        bcc     @n
        sta     z:t0
        lda     z:ds
        sta     z:ms
        lda     z:di
        sta     z:mi
        lda     z:g8
        sta     z:md
        jsr     can_move
        bcc     @n
        lda     z:t0
        sta     besta
        lda     z:g8
        sta     bestp
@n:     inc     z:g8
        bra     @p
@done:  lda     bestp
        bmi     @back
        sta     z:md                    ; move: draw both piles, the carried place back
        lda     z:ds
        sta     z:ms
        lda     z:di
        sta     z:mi
        jsr     can_move
        jsr     do_move
        jsr     redirty
        jsr     unshow
        jsr     postmove
        jmp     loop
@back:  lda     z:ds                    ; not allowed: they fly back
        ldx     z:di
        jsr     cardpos
        lda     #6
        sta     z:frames
        stz     z:arc
        ldx     z:cy
        lda     z:cx
        jsr     fly
        lda     z:ds
        jsr     pshow
        jsr     unshow
        jmp     loop

; pile g8 -> bx, by, bw, bh: the place a card dropped there would take
droprect:
        lda     z:g8
        asl     a
        tax
        lda     pxs,x
        sta     z:bx
        lda     pys,x
        sta     z:by
        lda     #CW
        sta     z:bw
        lda     #CH
        sta     z:bh
        lda     ptype,x
        cmp     #PT_TAB
        bne     @out
        lda     pcnt,x
        beq     @out
        dec     a
        tax
        lda     z:g8
        jsr     cardpos
        lda     z:cy
        sta     z:by
@out:   rts

; the carried top card (dx, dy, CW x CH) over bx .. bh -> A = the area in common (Z: none)
overlap:
        lda     z:dx                    ; x: min(right) - max(left)
        clc
        adc     #CW
        sta     z:t1
        lda     z:bx
        clc
        adc     z:bw
        cmp     z:t1
        bpl     :+
        sta     z:t1
:       lda     z:dx
        cmp     z:bx
        bpl     :+
        lda     z:bx
:       eor     #$FFFF
        sec
        adc     z:t1
        bmi     @no
        beq     @no
        sta     z:t2
        lda     z:dy                    ; y
        clc
        adc     #CH
        sta     z:t1
        lda     z:by
        clc
        adc     z:bh
        cmp     z:t1
        bpl     :+
        sta     z:t1
:       lda     z:dy
        cmp     z:by
        bpl     :+
        lda     z:by
:       eor     #$FFFF
        sec
        adc     z:t1
        bmi     @no
        beq     @no
        ldx     z:t2
        jmp     umul
@no:    lda     #0
        rts

; hpl, hi: may the cards from there be taken? -> C set
pickable:
        lda     z:hpl
        asl     a
        tax
        lda     pcnt,x
        sec
        sbc     z:hi
        sta     z:t3                    ; cards
        lda     z:hpl
        jsr     pofs
        clc
        adc     z:hi
        tax
        lda     pcards,x
        and     #$00FF
        bit     #DOWN
        bne     @no
        lda     z:hpl
        jsr     ptyp
        cmp     #PT_TAB
        beq     @run
        cmp     #PT_FOUND
        bne     :+
        lda     game
        bne     @no
:       lda     z:t3
        cmp     #1
        bne     @no
        sec
        rts
@run:   lda     z:hpl                   ; a run in order
        sta     z:ms
        lda     z:hi
        sta     z:mi
        lda     #$FF                    ; (a destination that refuses: only the run checked)
        sta     z:md
        jsr     runok
        rts
@no:    clc
        rts

; ms, mi: the cards from mi up are a run (each one lower, the other colour) -> C
runok:  lda     z:ms
        asl     a
        tax
        lda     pcnt,x
        sec
        sbc     z:mi
        tay
        lda     z:ms
        jsr     pofs
        clc
        adc     z:mi
        tax
:       dey
        beq     @yes
        lda     pcards+1,x
        and     #$00FF
        sta     z:g0
        lda     pcards,x
        and     #$00FF
        sta     z:g1
        phx
        ldx     z:g0
        lda     cred,x
        ldx     z:g1
        eor     cred,x
        and     #$00FF
        beq     @nop
        ldx     z:g0
        lda     crank,x
        and     #$00FF
        inc     a
        ldx     z:g1
        eor     crank,x
        and     #$00FF
        bne     @nop
        plx
        inx
        bra     :-
@yes:   sec
        rts
@nop:   plx
        clc
        rts

; ---------------------------------------------------------------- menus
onmenu: lda     z:dragging
        jne     loop
        lda     ui_ev+2                 ; Game 0, Edit 1, Options 2
        asl     a
        tax
        lda     ui_ev+4
        asl     a
        tay
        jmp     (mtab,x)
m_game: tyx
        cpx     #16
        jcs     loop
        jmp     (gtab,x)
m_edit: tyx
        jeq     m_undo
        jmp     loop
m_opt:  tyx
        cpx     #12
        jcs     loop
        jmp     (otab,x)

m_new:  stz     deal_no
        jsr     newdeal
        jmp     loop
m_restart:
        jsr     restart
        jmp     loop
m_kl:   lda     #0
        bra     :+
m_fc:   lda     #1
:       sta     game
        jsr     setmenus
        jmp     m_new
m_d1:   lda     #0
        bra     :+
m_d3:   lda     #1
:       sta     draw3
        jsr     setmenus
        lda     game                    ; Klondike: the deal again with it
        jne     loop
        jmp     m_restart
m_b0:   lda     #0
        bra     :+
m_b1:   lda     #1
        bra     :+
m_b2:   lda     #2
:       sta     back
        jsr     setmenus
        jsr     drawtable
        lda     won
        jeq     loop
        jsr     banner
        jmp     loop
m_undo: lda     won
        jne     loop
        jsr     undo
        jcc     loop
        jsr     redirty
        jsr     status
        jmp     loop
m_close:
        jmp     quit

; Game > Choose deal...: the number in a dialog
m_deal: ldx     deal_no                 ; the field holds the current one
        stx     pv16
        jsr     dec16
        ldx     #.loword(numbuf)
        ldy     #.loword(dbuf)
        jsr     ui_strcpy
        sta     fd_deal+FD_LEN
        sta     fd_deal+FD_CUR
        stz     fd_deal+FD_ANC
        stz     fd_deal+FD_SCR
        lda     #UF_FOCUS
        sta     fd_deal+CT_FLAGS
        ldx     #.loword(dg_deal)
        jsr     ui_dlgopen
        jcs     loop
        ldx     #.loword(dg_deal)
        jsr     ui_dlgrun
        phx
        ldx     #.loword(dg_deal)
        jsr     ui_dlgclose
        plx
        cpx     #.loword(bt_dok)
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
        sta     deal_no
        jsr     restart
        jmp     loop
@bad:   jsr     ui_beep
        jmp     loop

; the menus, the current choices marked
setmenus:
        ldx     #0
        ldy     #0
@c:     lda     mtmpl,x
        and     #$00FF
        cmp     #8
        bcs     @put
        cmp     #0
        beq     @zero
        phx                             ; a choice: its state byte, checked or not
        phy
        asl     a
        tax
        jsr     (mchk-2,x)
        ply
        plx
        lda     #MS_STATE
        bcc     :+
        ora     #MS_CHECK
:       jsr     @p
@next:  inx
        bra     @c
@zero:  jsr     @p                      ; "" ends a menu, two the list
        lda     mtmpl+1,x
        and     #$00FF
        bne     @next
        lda     mtmpl+2,x
        and     #$00FF
        bne     @next
        lda     #0
        jsr     @p
        jsr     @p
        lda     win
        ptr     mbuf
        sys     SYS_WMENU
        rts
@put:   jsr     @p
        bra     @next
@p:     sep     #$20
        .a8
        sta     mbuf,y
        rep     #$20
        .a16
        iny
        rts
c_kl:   lda     game
        bra     c_z
c_fc:   lda     game
        bra     c_nz
c_d1:   lda     draw3
        bra     c_z
c_d3:   lda     draw3
        bra     c_nz
c_b0:   lda     back
        bra     c_z
c_b1:   lda     back
        cmp     #1
        bra     c_eq
c_b2:   lda     back
        cmp     #2
        bra     c_eq
c_z:    cmp     #0
c_eq:   beq     c_yes
        clc
        rts
c_nz:   cmp     #0
        bne     c_yes
        clc
        rts
c_yes:  sec
        rts

; ---------------------------------------------------------------- the status line
; "Klondike, draw 3 - deal 1234" left, "Score 120   Moves 37   2:35" right
status: stz     sl
        ldx     #.loword(s_kl)
        lda     game
        beq     :+
        ldx     #.loword(s_fc)
:       jsr     sapp
        lda     game
        bne     :+
        ldx     #.loword(s_dr1)
        lda     draw3
        beq     :++
        ldx     #.loword(s_dr3)
        bra     :++
:       ldx     #.loword(s_none)
:       jsr     sapp
        ldx     #.loword(s_deal)
        jsr     sapp
        lda     deal_no
        jsr     sappn
        lda     #6                      ; left, then the rest of the strip up to the middle
        sta     z:t5
        lda     #SW / 2
        sta     z:t6
        jsr     stext
        stz     sl
        lda     game
        bne     :+
        ldx     #.loword(s_score)
        jsr     sapp
        lda     score
        jsr     sappn
        ldx     #.loword(s_gap)
        jsr     sapp
:       ldx     #.loword(s_moves)
        jsr     sapp
        lda     moves
        jsr     sappn
        ldx     #.loword(s_gap)
        jsr     sapp
        lda     smode                   ; (the replay has no clock)
        beq     :+
        ldx     #.loword(s_replay)
        jsr     sapp
        jmp     @right
:       lda     secs                    ; m:ss
        ldx     #60
        jsr     udiv
        sta     z:t3
        lda     secs
        ldx     #60
        jsr     umod
        sta     z:t4
        lda     z:t3
        jsr     sappn
        lda     #':'
        jsr     sapc
        lda     z:t4
        cmp     #10
        bcs     :+
        pha
        lda     #'0'
        jsr     sapc
        pla
:       jsr     sappn
@right: ldx     #.loword(sbuf)          ; right-aligned
        lda     #0
        jsr     ui_twidth
        eor     #$FFFF
        sec
        adc     #SW - 6
        sta     z:t5
        lda     #SW / 2
        sta     z:t6
        ; fall through
; sbuf at x t5 on the strip, its paper; the strip from t6 to it (or from its end to t6)
stext:  lda     win
        sta     z:ui_win
        lda     #STATY
        sta     z:ui_y
        lda     #STATH
        sta     z:ui_h
        ldx     #.loword(sbuf)
        lda     #0
        jsr     ui_twidth
        sta     z:t7
        lda     z:t5
        cmp     z:t6
        bcc     @left
        lda     z:t6                    ; right part: fill t6 .. t5
        sta     z:ui_x
        lda     z:t5
        sec
        sbc     z:t6
        jsr     @fill
        lda     z:t5                    ; and after the text to the right edge
        clc
        adc     z:t7
        sta     z:ui_x
        lda     #SW
        sec
        sbc     z:ui_x
        jsr     @fill
        bra     @text
@left:  stz     z:ui_x                  ; left part: 0 .. t5, after the text .. t6
        lda     z:t5
        jsr     @fill
        lda     z:t5
        clc
        adc     z:t7
        sta     z:ui_x
        lda     z:t6
        sec
        sbc     z:ui_x
        jsr     @fill
@text:  lda     z:t5                    ; (the two rows above the text)
        sta     z:ui_x
        lda     #2
        sta     z:ui_h
        lda     z:t7
        jsr     @fill
        lda     #STATY + 2
        sta     z:ui_y
        stz     z:ui_font
        lda     #C_LIGHT | (C_STRIP << 8)
        ldx     #.loword(sbuf)
        jmp     ui_text
@fill:  beq     :+
        bmi     :+
        sta     z:ui_w
        lda     #WD_FILL | (C_STRIP << 8)
        jmp     ui_rect
:       rts

; append the string X / the number A / the character A to sbuf
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
sapc:   ldy     sl
        and     #$00FF
        sta     sbuf,y
        iny
        sty     sl
        rts
; A mod X
umod:   stx     z:g5
:       cmp     z:g5
        bcc     :+
        sbc     z:g5
        bra     :-
:       rts

; pv16 -> numbuf (decimal, signed)
dec16:  ldy     #0
        lda     pv16
        bpl     :+
        eor     #$FFFF
        inc     a
        sta     pv16
        lda     #'-'
        sta     numbuf
        iny
:       sty     z:t1
        ldx     #0                      ; digits, last first
:       lda     pv16
        jsr     div10r                  ; A = quotient, t2 = remainder
        sta     pv16
        lda     z:t2
        ora     #'0'
        pha
        inx
        lda     pv16
        bne     :-
        ldy     z:t1
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
:       cmp     #10
        bcc     :+
        sbc     #10
        iny
        bra     :-
:       sta     z:t2
        tya
        rts

; the end: a panel over the ring
banner: lda     win
        sta     z:ui_win
        lda     #(SW - 240) / 2
        sta     z:ui_x
        lda     #142
        sta     z:ui_y
        lda     #240
        sta     z:ui_w
        lda     #76
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        lda     #WD_FRAME | (C_SHADOW << 8)
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
        ldx     #.loword(s_won)
        jsr     sapp
        lda     #152
        jsr     @line
        stz     sl
        lda     game
        bne     :+
        ldx     #.loword(s_score)
        jsr     sapp
        lda     score
        jsr     sappn
        ldx     #.loword(s_gap)
        jsr     sapp
:       ldx     #.loword(s_moves)
        jsr     sapp
        lda     moves
        jsr     sappn
        lda     smode
        bne     @nt
        ldx     #.loword(s_gap)
        jsr     sapp
        ldx     #.loword(s_time)
        jsr     sapp
        lda     secs
        ldx     #60
        jsr     udiv
        jsr     sappn
        lda     #':'
        jsr     sapc
        lda     secs
        ldx     #60
        jsr     umod
        cmp     #10
        bcs     :+
        pha
        lda     #'0'
        jsr     sapc
        pla
:       jsr     sappn
@nt:    lda     #174
        jsr     @line
        stz     sl
        ldx     #.loword(s_again)
        jsr     sapp
        lda     #196
@line:  sta     z:ui_y                  ; sbuf centred at row A
        ldx     #.loword(sbuf)
        lda     #0
        jsr     ui_twidth
        eor     #$FFFF
        sec
        adc     #SW
        lsr     a
        sta     z:ui_x
        stz     z:ui_font
        lda     #C_BLACK | (C_BODY << 8)
        ldx     #.loword(sbuf)
        jmp     ui_text

        .include "sol_game.s"
        .include "sol_draw.s"
        .include "sol_test.s"
        .include "sol_art.s"
        .include "sol_data.s"
