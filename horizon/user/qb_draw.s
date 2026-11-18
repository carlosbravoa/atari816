; qb_draw.s - Quabricks' screens (included by quabrick.s). Everything is drawn with win_draw
; into the window (directly on the screen while nothing covers it): pre-made tiles blitted,
; fills, the UI font, and two big bold fonts expanded from 1 bpp (one WD_EXPAND per string,
; composed here). The well keeps shown[]: what each cell shows now (0 empty, 1-7 a block,
; 8-14 a ghost, 15 the sweep's grey, $FF unknown); a frame blits only the cells whose wanted
; picture differs.
;
; (1.1) No hardware sprites for the falling piece and its ghost (REV $0B), measured: a frame
; that only moves the piece is one draw list already and would be one spr_set (no syscall
; saved; a lock still needs its list), and all the drawing calls cost 0.10 ms of CPU a frame on
; average (emulated, 290 us a frame with them, 187 us without). They would look worse: a
; window's sprites hide whenever anything covers it (the piece would vanish under the game's
; own right-click menu and the menu bar's menus) and stand in front of the pause box; they
; need 14 aligned 16 x 16 images (3.5 KB; the code bank has 1.9 KB left) and this path
; stays anyway for REV < $0B.

CW      = 384                           ; the window's content
CH      = 304
CELL    = 14
WX      = 136                           ; the well's first cell
WY      = 12
FRX     = WX - 4                        ; its frame
FRY     = WY - 4
FRW     = SW * CELL + 8
FRH     = SH * CELL + 8
LX      = 8                             ; left column: hold, score, the numbers
LW      = 116
NX      = 288                           ; right column: next
NW      = 88
STATY     = 146                           ; the numbers' panel
MSGY    = 236                           ; the bonus messages in it
BAND    = 38                            ; the background: 8 bands

; ---------------------------------------------------------------- set up
; the empty row and the sweep's row (10 tiles side by side), the cells' places, the bank of
; the blits' pointers
mkrows: sep     #$20
        .a8
        phb
        pla
        sta     db+14
        rep     #$20
        .a16
        and     #$00FF
        sta     pbank
        stz     z:g2                    ; tile row y
        stz     z:g1                    ; y * 14 (in a tile)
        stz     z:g3                    ; y * 140 (in a row)
@r:     ldx     z:g3
        lda     #SW
        sta     z:g4
@t:     ldy     z:g1
        lda     #CELL
        sta     z:g5
:       sep     #$20
        .a8
        lda     t_e14,y
        sta     erow,x
        lda     t_s14,y
        sta     srow,x
        rep     #$20
        .a16
        inx
        iny
        dec     z:g5
        bne     :-
        dec     z:g4
        bne     @t
        lda     z:g1
        clc
        adc     #CELL
        sta     z:g1
        lda     z:g3
        clc
        adc     #SW * CELL
        sta     z:g3
        inc     z:g2
        lda     z:g2
        cmp     #CELL
        bcc     @r
        ldx     #0                      ; the cells' places in the window
        stz     z:g0
        lda     #WX
        sta     z:g2
        lda     #WY
        sta     z:g1
:       lda     z:g2
        sta     cposx,x
        lda     z:g1
        sta     cposy,x
        inx
        inx
        lda     z:g2
        clc
        adc     #CELL
        sta     z:g2
        inc     z:g0
        lda     z:g0
        cmp     #SW
        bcc     :-
        stz     z:g0
        lda     #WX
        sta     z:g2
        lda     z:g1
        clc
        adc     #CELL
        sta     z:g1
        cpx     #SW * SH * 2
        bcc     :-
        rts

; ---------------------------------------------------------------- primitives
; win_draw with the block db; (1.1) in a frame (lon): a record of the frame's draw list
wd:     lda     lon
        bne     :+
        stz     lshn                    ; (1.2: a sheet's record only in a list)
        bra     wdnow
:       jmp     ladd
wdnow:  lda     win
        ldx     #.loword(db)
        ldy     pbank
        qsys    SYS_WDRAW
        rts
; (1.1) the local colours in A (xc2: both bytes, xc1: the low one) as palette entries (cmap;
; 0 and $FF stay)
xc2:    pha
        and     #$00FF
        tax
        lda     cmap,x
        and     #$00FF
        sta     z:xct
        pla
        xba
        and     #$00FF
        tax
        lda     cmap,x
        xba
        and     #$FF00
        ora     z:xct
        rts
xc1:    and     #$00FF
        tax
        lda     cmap,x
        and     #$00FF
        rts
setr:   lda     z:rx
        sta     db+4
        lda     z:ry
        sta     db+6
        lda     z:rw
        sta     db+8
        lda     z:rh
        sta     db+10
        rts
; the rectangle rx .. rh in colour A
fill:   jsr     xc1
        xba
        ora     #WD_FILL
        sta     db
        jsr     setr
        jmp     wd
; a 1-pixel line from rx, ry to rw, rh in colour A
line:   jsr     xc1
        xba
        ora     #WD_LINE
        sta     db
        jsr     setr
        jmp     wd
; the image at X (rw x rh) at rx, ry
blit:   stx     db+12
        lda     #WD_BLIT
        sta     db
        jsr     setr
        jmp     wd
; the same, colour 0 left out
kblit:  stx     db+12
        lda     #WD_KBLIT
        sta     db
        stz     db+2
        jsr     setr
        jmp     wd
; the rectangle rx .. rh moves to A, X (inside the window)
copy:   sta     db+1
        stx     db+12
        sep     #$20
        .a8
        lda     #WD_COPY
        sta     db
        rep     #$20
        .a16
        jsr     setr
        jmp     wd
; a checker of A (low) and A (high)
dither: jsr     xc2
        sta     db+1
        sep     #$20
        .a8
        lda     #WD_DITHER
        sta     db
        rep     #$20
        .a16
        jsr     setr
        jmp     wd
; the string X at rx, ry in the UI font: A = ink | paper << 8 ($FF: none)
text:   stx     db+12
        jsr     xc2
        sta     db+1
        sep     #$20
        .a8
        lda     #WD_TEXT
        sta     db
        rep     #$20
        .a16
        stz     db+3
        lda     z:rx
        sta     db+4
        lda     z:ry
        sta     db+6
        jmp     wd
; the string X: its width in the UI font -> A
twidth: lda     #0
        ldy     pbank
        qsys    SYS_WTWIDTH
        rts
; the string X centred on cx / right-aligned at cx, at ry, A = ink | paper << 8
textc:  pha
        phx
        jsr     twidth
        lsr     a
        eor     #$FFFF
        sec
        adc     z:cx
        sta     z:rx
        plx
        pla
        bra     text
textr:  pha
        phx
        jsr     twidth
        eor     #$FFFF
        sec
        adc     z:cx
        sta     z:rx
        plx
        pla
        bra     text

; ---------------------------------------------------------------- the big fonts
; the string X in the big font of scale bk (2 or 3) at rx, ry: A = ink | paper << 8; composed
; into bigbuf (one 1 bpp row of characters) and drawn with one WD_EXPAND. -> A = its width
big:    stx     z:bs
        jsr     xc2
        sta     z:bink
        ldx     z:bs
        jsr     bigw                    ; -> n, width
        lda     z:bn
        jeq     @out
        lda     #.loword(bigbuf)        ; (1.1) where it is composed: in a frame, the arena
        ldx     lon                     ; (left alone until the list has run)
        beq     :+
        jsr     lbig
:       sta     z:bbase
        ldy     #0                      ; character i
@ch:    phy
        lda     (bs),y
        and     #$00FF
        cmp     #'a'
        bcc     :+
        and     #$DF
:       ldx     #BIGCH - 1
        sep     #$20
        .a8
:       cmp     big_chars,x
        beq     :+
        dex
        bpl     :-
        ldx     #0                      ; (unknown: a space)
:       rep     #$20
        .a16
        txa                             ; the glyph: big2 + 28 g / big3 + 63 g
        ldx     z:bk
        cpx     #3
        beq     :+
        asl     a
        asl     a
        sta     z:g0
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:g0                    ; 28 g
        clc
        adc     #.loword(big2)
        bra     :++
:       sta     z:g0
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:g0                    ; 63 g
        clc
        adc     #.loword(big3)
:       sta     z:g1                    ; source
        lda     1,s                     ; destination: bigbuf + i * k
        ldx     z:bk
        cpx     #3
        bne     :+
        asl     a
        clc
        adc     1,s
        bra     :++
:       asl     a
:       clc
        adc     z:bbase
        sta     z:g2
        lda     z:bk                    ; rows: 7 k
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:bk
        sta     z:g3
@row:   sep     #$20
        .a8
        lda     (g1)
        sta     (g2)
        ldy     #1
        lda     (g1),y
        sta     (g2),y
        lda     z:bk
        cmp     #3
        bne     :+
        iny
        lda     (g1),y
        sta     (g2),y
:       rep     #$20
        .a16
        lda     z:g1
        clc
        adc     z:bk
        sta     z:g1
        lda     z:g2
        clc
        adc     z:bstr
        sta     z:g2
        dec     z:g3
        bne     @row
        ply
        iny
        cpy     z:bn
        jcc     @ch
        lda     z:bbase                 ; one expand
        sta     db+12
        lda     z:bink
        sta     db+1
        sep     #$20
        .a8
        lda     #WD_EXPAND
        sta     db
        rep     #$20
        .a16
        stz     db+3
        lda     z:rx
        sta     db+4
        lda     z:ry
        sta     db+6
        lda     z:bwid
        sta     db+8
        lda     z:bk
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:bk
        sta     db+10
        lda     z:bstr
        sta     db+15
        jsr     wd
@out:   lda     z:bwid
        rts
; the string X in font bk: bn characters, bstr = bytes a row, bwid = pixels -> A = bwid
bigw:   stx     z:bs
        ldy     #0
:       lda     (bs),y
        and     #$00FF
        beq     :+
        iny
        bra     :-
:       sty     z:bn
        tya
        ldx     z:bk
        cpx     #3
        bne     :+
        asl     a
        clc
        adc     z:bn
        bra     :++
:       asl     a
:       sta     z:bstr
        asl     a                       ; n * 8 k - k
        asl     a
        asl     a
        sec
        sbc     z:bk
        bpl     :+
        lda     #0
:       sta     z:bwid
        rts
; centred on cx / right-aligned at cx
bigc:   pha
        phx
        jsr     bigw
        lsr     a
        eor     #$FFFF
        sec
        adc     z:cx
        sta     z:rx
        plx
        pla
        jmp     big
bigr:   pha
        phx
        jsr     bigw
        eor     #$FFFF
        sec
        adc     z:cx
        sta     z:rx
        plx
        pla
        jmp     big
; centred, with a drop shadow (2 pixels down and right; over the background)
bigcs:  pha
        phx
        lda     z:cx
        pha
        inc     z:cx
        inc     z:cx
        inc     z:ry
        inc     z:ry
        lda     #Q_SHADOW | $FF00
        jsr     bigc
        dec     z:ry
        dec     z:ry
        pla
        sta     z:cx
        plx
        pla
        jmp     bigc

; A (low word), X (high word) in decimal -> numbuf (zero-terminated)
numstr: sta     z:n0
        stx     z:n1
        ldy     #0
@d:     ldx     #32                     ; (n1:n0) / 10, the remainder in A
        lda     #0
:       asl     z:n0
        rol     z:n1
        rol     a
        cmp     #10
        bcc     :+
        sbc     #10
        inc     z:n0
:       dex
        bne     :--
        ora     #'0'
        pha
        iny
        lda     z:n0
        ora     z:n1
        bne     @d
        ldx     #0
:       pla
        sep     #$20
        .a8
        sta     numbuf,x
        rep     #$20
        .a16
        inx
        dey
        bne     :-
        sep     #$20
        .a8
        stz     numbuf,x
        rep     #$20
        .a16
        rts

; ---------------------------------------------------------------- shapes
; the background: 8 bands from the top colour down, 4 rows of checker between them
draw_bg:
        jsr     lend
        stz     z:rx
        lda     #CW
        sta     z:rw
        lda     #BAND
        sta     z:rh
        stz     z:g8                    ; band
:       lda     z:g8
        jsr     bandy
        sta     z:ry
        lda     #Q_GRAD0 + 7
        sec
        sbc     z:g8
        jsr     fill
        inc     z:g8
        lda     z:g8
        cmp     #8
        bcc     :-
        lda     #4
        sta     z:rh
        lda     #1
        sta     z:g8
:       lda     z:g8
        jsr     bandy
        dec     a
        dec     a
        sta     z:ry
        lda     #Q_GRAD0 + 7            ; above: 8 - band, below: 7 - band
        sec
        sbc     z:g8
        sta     z:g0
        inc     a
        xba
        ora     z:g0
        jsr     dither
        inc     z:g8
        lda     z:g8
        cmp     #8
        bcc     :-
        rts
bandy:  sta     z:g9                    ; A * 38
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     z:g9
        adc     z:g9
        adc     z:g9
        adc     z:g9
        adc     z:g9
        adc     z:g9
        rts
; the background colour at row A (for the text that changes over it)
bgat:   ldx     #0
:       sec
        sbc     #BAND
        bmi     :+
        inx
        bra     :-
:       txa
        eor     #$FFFF
        sec
        adc     #Q_GRAD0 + 7
        rts

; a panel: rx .. rh, rounded, PANEL inside a PANELB line
panel:  jsr     rrect                   ; (keeps rx .. rh)
        lda     z:rx                    ; the outline
        sta     z:g4
        clc
        adc     z:rw
        dec     a
        sta     z:g5                    ; right
        lda     z:ry
        sta     z:g6
        clc
        adc     z:rh
        dec     a
        sta     z:g7                    ; bottom
        jsr     savr
        lda     z:g4                    ; top: x + 2 .. right - 2
        inc     a
        inc     a
        sta     z:rx
        lda     z:g6
        sta     z:ry
        lda     z:g5
        dec     a
        dec     a
        sta     z:rw
        lda     z:g6
        sta     z:rh
        lda     #Q_PANELB
        jsr     line
        lda     z:g7
        sta     z:ry
        sta     z:rh
        lda     #Q_PANELB
        jsr     line
        lda     z:g4                    ; left: y + 2 .. bottom - 2
        sta     z:rx
        sta     z:rw
        lda     z:g6
        inc     a
        inc     a
        sta     z:ry
        lda     z:g7
        dec     a
        dec     a
        sta     z:rh
        lda     #Q_PANELB
        jsr     line
        lda     z:g5
        sta     z:rx
        sta     z:rw
        lda     #Q_PANELB
        jsr     line
        lda     #1                      ; the four corners' pixels
        sta     z:rw
        sta     z:rh
        lda     z:g4
        inc     a
        sta     z:rx
        lda     z:g6
        inc     a
        sta     z:ry
        lda     #Q_PANELB
        jsr     fill
        lda     z:g7
        dec     a
        sta     z:ry
        lda     #Q_PANELB
        jsr     fill
        lda     z:g5
        dec     a
        sta     z:rx
        lda     #Q_PANELB
        jsr     fill
        lda     z:g6
        inc     a
        sta     z:ry
        lda     #Q_PANELB
        jsr     fill
        jmp     restr
; a rounded rectangle rx .. rh in PANEL (or A with rrectc): three fills
rrect:  lda     #Q_PANEL
rrectc: sta     z:g3
        jsr     savr
        inc     z:rx                    ; x + 1 .. w - 2, y + 1 .. h - 2
        dec     z:rw
        dec     z:rw
        inc     z:ry
        dec     z:rh
        dec     z:rh
        lda     z:g3
        jsr     fill
        jsr     restr
        inc     z:rx
        inc     z:rx
        lda     z:rw
        sec
        sbc     #4
        sta     z:rw
        lda     z:g3
        jsr     fill                    ; (the full height, narrower)
        jsr     restr
        inc     z:ry
        inc     z:ry
        lda     z:rh
        sec
        sbc     #4
        sta     z:rh
        lda     z:g3
        jsr     fill                    ; (the full width, lower)
        jmp     restr
savr:   lda     z:rx
        sta     z:svx
        lda     z:ry
        sta     z:svy
        lda     z:rw
        sta     z:svw
        lda     z:rh
        sta     z:svh
        rts
restr:  lda     z:svx
        sta     z:rx
        lda     z:svy
        sta     z:ry
        lda     z:svw
        sta     z:rw
        lda     z:svh
        sta     z:rh
        rts
; rx, ry, rw, rh = the four words at X
rect:   lda     a:0,x
        sta     z:rx
        lda     a:2,x
        sta     z:ry
        lda     a:4,x
        sta     z:rw
        lda     a:6,x
        sta     z:rh
        rts

; ---------------------------------------------------------------- the play screen
draw_playscreen:
        jsr     draw_bg
        ldx     #.loword(r_hold)
        jsr     rect
        jsr     panel
        ldx     #.loword(r_score)
        jsr     rect
        jsr     panel
        ldx     #.loword(r_stats)
        jsr     rect
        jsr     panel
        ldx     #.loword(r_next)
        jsr     rect
        jsr     panel
        lda     #LX + 8
        sta     z:rx
        lda     #13
        sta     z:ry
        ldx     #.loword(s_hold)
        lda     #Q_MUTED | (Q_PANEL << 8)
        jsr     text
        lda     #93
        sta     z:ry
        ldx     #.loword(s_score)
        lda     #Q_MUTED | (Q_PANEL << 8)
        jsr     text
        lda     #NX + 8
        sta     z:rx
        lda     #13
        sta     z:ry
        ldx     #.loword(s_next)
        lda     #Q_MUTED | (Q_PANEL << 8)
        jsr     text
        ldx     #.loword(r_frame)       ; the well's frame
        jsr     rect
        lda     #Q_GLOW
        jsr     rrectc
        jsr     draw_stlabels
        lda     #LX + LW / 2            ; "Enter: pause"
        sta     z:cx
        lda     #279
        sta     z:ry
        ldx     #.loword(s_epause)
        lda     #Q_MUTED | (Q_PANEL << 8)
        jsr     textc
        jsr     well_full
        jsr     draw_hold
        jsr     draw_nextall
        jsr     draw_score
        jsr     draw_stats
        stz     gflags
        rts

; the well from nothing: an empty row, doubled by copies; then every cell that is not empty
well_full:
        lda     #WX
        sta     z:rx
        lda     #WY
        sta     z:ry
        lda     #SW * CELL
        sta     z:rw
        lda     #CELL
        sta     z:rh
        lda     #2                      ; (1.2) the rows' sheet, row 0
        sta     lshn
        ldx     #.loword(erow)
        jsr     blit
        lda     #CELL                   ; 1 -> 2 -> 4 -> 8 -> 16 rows, then 4 more
        sta     z:g8
:       lda     z:g8
        sta     z:rh
        clc
        adc     #WY
        tax
        lda     #WX
        jsr     copy
        lda     z:g8
        asl     a
        sta     z:g8
        cmp     #16 * CELL
        bcc     :-
        lda     #4 * CELL
        sta     z:rh
        ldx     #WY + 16 * CELL
        lda     #WX
        jsr     copy
        ldx     #SW * SH - 2
:       stz     shown,x
        stz     ov,x
        dex
        dex
        bpl     :-
        stz     noc
        lda     #$FFFF
        sta     dpt                     ; (the piece: drawn afresh)
        jsr     overlay
        jmp     diffall

; the piece and its ghost into ov[] (the cells they cover, listed in oc[]); the old ones out
overlay:
        ldx     noc
        beq     @new
:       dex
        dex
        ldy     oc,x
        sep     #$20
        .a8
        lda     #0
        sta     ov,y
        rep     #$20
        .a16
        txa
        bne     :-
        stz     noc
@new:   lda     state
        cmp     #ST_PLAY
        bne     @out
        lda     over
        bne     @out
        jsr     dropy                   ; the ghost
        sta     z:g9
        lda     z:pt
        clc
        adc     #8
        ldx     z:g9
        jsr     @cells
        lda     z:pt
        inc     a
        ldx     z:py
        jsr     @cells
@out:   lda     z:px                    ; drawn as
        sta     dpx
        lda     z:py
        sta     dpy
        lda     z:pr
        sta     dpr
        lda     z:pt
        sta     dpt
        rts
; the piece's cells at row X in ov[] as A
@cells: sta     z:g6
        stx     z:g7
        lda     z:pt
        asl     a
        asl     a
        ora     z:pr
        asl     a
        asl     a
        asl     a
        tax
        lda     #4
        sta     z:g5
@c:     lda     pcells+1,x
        and     #$00FF
        clc
        adc     z:g7
        bmi     @n
        asl     a
        tay
        lda     pcells,x
        and     #$00FF
        clc
        adc     z:px
        clc
        adc     rowofs,y
        tay
        lda     z:g6
        sep     #$20
        .a8
        sta     ov,y
        rep     #$20
        .a16
        phx
        ldx     noc
        tya
        sta     oc,x
        inx
        inx
        stx     noc
        plx
@n:     inx
        inx
        dec     z:g5
        bne     @c
        rts

; cell Y: what it should show (the well, or the piece / ghost over it) -> blitted if it differs
diffcell:
        lda     (dsrc),y
        and     #$00FF
        bne     :+
        lda     ov,y
        and     #$00FF
:       sta     z:g0
        lda     shown,y
        and     #$00FF
        cmp     z:g0
        beq     dcout
        lda     z:g0
        sep     #$20
        .a8
        sta     shown,y
        rep     #$20
        .a16
        ; fall through
; tile A at cell Y
blitcell:
        tax                             ; (1.2) the tiles' sheet, its row
        pha
        lda     tilesy,x
        and     #$00FF
        xba
        ora     #1
        sta     lshn
        pla
        asl     a
        tax
        lda     tilep,x
        sta     db+12
        tya
        asl     a
        tay
        lda     cposx,y
        sta     db+4
        lda     cposy,y
        sta     db+6
        lda     #CELL
        sta     db+8
        sta     db+10
        lda     #WD_BLIT
        sta     db
        jmp     wd
dcout:  rts

; every cell against the well (diffall) / the well before its lines went (diffall0)
diffall:
        lda     #.loword(stage)
        bra     :+
diffall0:
        lda     #.loword(stage0)
:       sta     z:dsrc
        ldy     #0
@row:   sty     z:g9                    ; a row that should be empty but is not: one blit
        ldx     #SW
        lda     #0
        sta     z:g8
:       lda     (dsrc),y
        ora     ov,y
        and     #$00FF
        bne     @cells
        lda     shown,y
        and     #$00FF
        tsb     z:g8
        iny
        dex
        bne     :-
        lda     z:g8
        beq     @nextr
        ldy     z:g9                    ; the empty row
        lda     #0
        sep     #$20
        .a8
        ldx     #SW
:       sta     shown,y
        iny
        dex
        bne     :-
        rep     #$20
        .a16
        lda     z:g9
        ldx     #SW
        jsr     qdiv
        asl     a
        tax
        lda     rowy,x
        sta     z:ry
        lda     #WX
        sta     z:rx
        lda     #SW * CELL
        sta     z:rw
        lda     #CELL
        sta     z:rh
        lda     #2                      ; (1.2) the rows' sheet, row 0
        sta     lshn
        ldx     #.loword(erow)
        jsr     blit
        bra     @nextr
@cells: ldy     z:g9                    ; else cell by cell
        ldx     #SW
:       phx
        phy
        jsr     diffcell
        ply
        plx
        iny
        dex
        bne     :-
@nextr: lda     z:g9
        clc
        adc     #SW
        tay
        cpy     #SW * SH
        bcc     @row
        rts
; the cells of the old and the new piece and ghost
diffpiece:
        lda     #.loword(stage)
        sta     z:dsrc
        ldx     #0
:       cpx     z:nold
        bcs     :+
        ldy     oldc,x
        phx
        jsr     diffcell
        plx
        inx
        inx
        bra     :-
:       ldx     #0
:       cpx     noc
        bcs     :+
        ldy     oc,x
        phx
        jsr     diffcell
        plx
        inx
        inx
        bra     :-
:       rts

; one frame of play: what the rules changed
draw_play:
        jsr     draw_anims              ; (a shake back first)
        lda     gflags
        bit     #GF_CLEAR
        beq     @noclr
        jsr     overlay0                ; the locked piece, the full rows
        jsr     diffall0
        jsr     clearcopies
        lda     #16
        sta     flashn
        bra     @stage
@noclr: bit     #GF_STAGE
        beq     @piece
@stage: jsr     overlay
        jsr     diffall
        bra     @panels
@piece: lda     z:px                    ; moved?
        cmp     dpx
        bne     :+
        lda     z:py
        cmp     dpy
        bne     :+
        lda     z:pr
        cmp     dpr
        bne     :+
        lda     z:pt
        cmp     dpt
        beq     @panels
:       ldx     noc                     ; the old cells, then the new
        stx     z:nold
:       dex
        dex
        bmi     :+
        lda     oc,x
        sta     oldc,x
        bra     :-
:       jsr     overlay
        jsr     diffpiece
@panels:
        lda     gflags
        bit     #GF_NEXT
        beq     :+
        jsr     draw_nextshift
        lda     gflags
:       bit     #GF_HOLD
        beq     :+
        jsr     draw_hold
        lda     gflags
:       bit     #GF_SCORE
        beq     :+
        jsr     draw_score
        lda     gflags
:       bit     #GF_STATS | GF_TIME | GF_TIMEWON
        beq     :+
        jsr     draw_stats
:       lda     gflags                  ; a message for a bonus
        bit     #GF_STAGE
        beq     :+
        jsr     draw_msg
:       lda     msgt                    ; the message goes after 2 s
        beq     :+
        dec     msgt
        bne     :+
        jsr     clear_msg
:       lda     gflags
        bit     #GF_SHAKE
        beq     :+
        lda     over
        bne     :+
        jsr     shake
:       stz     gflags
        rts

; the overlay without the piece (it is in stage0 now)
overlay0:
        lda     state
        pha
        lda     #ST_SWEEP               ; (overlay draws no piece outside play)
        sta     state
        jsr     overlay
        pla
        sta     state
        rts

; the rows in clr[] (top first): the rows above each move down a row on the screen
clearcopies:
        ldx     #0
@r:     cpx     nclr
        bcc     :+
        rts
:       phx
        txa
        asl     a
        tax
        lda     clr,x
        sta     z:g8                    ; r
        ldy     #0                      ; the first row the screen shows something in
@t:     cpy     z:g8
        bcs     @next
        tya
        asl     a
        tax
        lda     rowofs,x
        tax
        lda     #SW
        sta     z:g7
:       lda     shown,x
        and     #$00FF
        bne     @top
        inx
        dec     z:g7
        bne     :-
        iny
        bra     @t
@top:   sty     z:g9
        lda     #WX                     ; rows top .. r - 1 down by a row
        sta     z:rx
        sta     z:g6
        tya
        asl     a
        tax
        lda     rowy,x
        sta     z:ry
        clc
        adc     #CELL
        tax
        lda     #SW * CELL
        sta     z:rw
        lda     z:g8
        sec
        sbc     z:g9
        asl     a
        tay
        lda     rowh,y
        sta     z:rh
        lda     z:g6
        jsr     copy
        lda     z:g8                    ; shown[] the same: rows r - 1 .. top into r .. top + 1
        asl     a
        tax
        lda     rowofs,x
        clc
        adc     #SW - 1
        tax                             ; the last cell of row r
        lda     z:g9
        asl     a
        tay
        lda     rowofs,y
        clc
        adc     #SW
        sta     z:g7                    ; the first cell of row top + 1
        sep     #$20
        .a8
:       lda     shown-SW,x
        sta     shown,x
        dex
        cpx     z:g7
        bcs     :-
        rep     #$20
        .a16
@next:  plx
        inx
        jmp     @r

; the hard drop's jolt: the rows with blocks 2 pixels up for a frame (draw_anims puts them
; back): one copy of the stack, not of the whole well
shake:  ldy     #0                      ; the first row with blocks of the well
        ldx     #0
:       lda     stage,y
        and     #$00FF
        bne     :+
        iny
        cpy     #SW * SH
        bcc     :-
        rts
:       tya
        ldx     #SW
        jsr     qdiv
        sta     shtop
        asl     a
        tax
        lda     rowy,x
        sta     z:ry
        lda     #WY + SH * CELL
        sec
        sbc     z:ry
        sta     z:rh
        lda     #WX
        sta     z:rx
        lda     #SW * CELL
        sta     z:rw
        lda     z:ry
        dec     a
        dec     a
        tax
        lda     #WX
        jsr     copy
        lda     #1
        sta     shaken
        rts

; the shake back, the flash's next step (any state)
draw_anims:
        lda     shaken
        jeq     @fl
        stz     shaken
        lda     shtop
        asl     a
        tax
        lda     rowy,x
        dec     a
        dec     a
        sta     z:ry
        lda     #WY + SH * CELL - 2     ; (the same height: down to the floor)
        sec
        sbc     z:ry
        sta     z:rh
        lda     #WX
        sta     z:rx
        lda     #SW * CELL
        sta     z:rw
        lda     z:ry
        inc     a
        inc     a
        tax
        lda     #WX
        jsr     copy
        lda     #2                      ; the 2 rows above it: the frame, or an empty row's last two
        sta     z:rh
        lda     shtop
        bne     :+
        lda     #Q_GLOW
        jsr     fill
        bra     @fl
:       jsr     @strip
        lda     shtop                   ; the cells of the row above that are not empty: again
        dec     a
        ldx     #SW
        jsr     mulx
        tay
        ldx     #SW
:       lda     shown,y
        and     #$00FF
        beq     :+
        lda     #$FF
        sep     #$20
        .a8
        sta     shown,y
        rep     #$20
        .a16
        phx
        phy
        lda     #.loword(stage)
        sta     z:dsrc
        jsr     diffcell
        ply
        plx
:       iny
        dex
        bne     :--
        rts
@strip: lda     #SW * CELL              ; (the source stride)
        sta     db+1
        lda     #2 | (12 << 8)          ; (1.2) the rows' sheet, row 12
        sta     lshn
        lda     #.loword(erow + 12 * SW * CELL)
        sta     db+12
        sep     #$20
        .a8
        lda     #WD_SBLIT
        sta     db
        rep     #$20
        .a16
        jsr     setr
        jmp     wd
@fl:    rts
; A * X (small) -> A
mulx:   sta     z:g1
        lda     #0
        cpx     #0
        beq     :++
:       clc
        adc     z:g1
        dex
        bne     :-
:       rts

; the line-clear flash: its next step (right after the vertical blank: no change of colours
; while the picture is drawn)
flashstep:
        lda     flashn
        beq     @out
        dec     flashn
        lda     state
        cmp     #ST_PAUSE
        beq     @out
        lda     flashn                  ; white x 3/8 of what is left
        asl     a
        clc
        adc     flashn
        lsr     a
        lsr     a
        lsr     a
        pha
        tax
        lda     #Q_BOARD
        jsr     pal_flash
        plx
        lda     #Q_GRID
        jsr     pal_flash
@out:   rts

; hold: its piece (dimmed while it cannot be used)
draw_hold:
        ldx     #.loword(r_holdin)
        jsr     rect
        lda     #Q_PANEL
        jsr     fill
        lda     hold
        bmi     @out
        sta     z:g8
        ldx     #.loword(tt_b12)
        lda     holdused
        beq     :+
        ldx     #.loword(tt_d12)
:       stx     z:tt
        lda     #12
        sta     z:csz
        lda     #LX + LW / 2
        sta     z:cx
        lda     #50
        sta     z:cy
        lda     z:g8
        jmp     preview
@out:   rts

; the next queue: all five (draw_nextall), or after a piece came out: slots 2-4 copied up,
; 0 and 4 drawn (draw_nextshift)
draw_nextall:
        lda     #0
        sta     z:g8
:       jsr     nextslot
        inc     z:g8
        lda     z:g8
        cmp     #5
        bcc     :-
        rts
draw_nextshift:
        lda     #NX + 4
        sta     z:rx
        lda     #130
        sta     z:ry
        lda     #NW - 8
        sta     z:rw
        lda     #3 * 48 - 4
        sta     z:rh
        ldx     #82
        lda     #NX + 4
        jsr     copy
        stz     z:g8
        jsr     nextslot
        lda     #4
        sta     z:g8
; slot g8: its area cleared, queue[g8] in it
nextslot:
        lda     z:g8
        asl     a
        tax
        lda     slot_y,x
        sta     z:cy
        lda     #NX + 4
        sta     z:rx
        lda     #NW - 8
        sta     z:rw
        lda     #44
        ldy     #10
        ldx     #.loword(tt_b10)
        lda     z:g8
        bne     :+
        ldy     #12
        ldx     #.loword(tt_b12)
:       sty     z:csz
        stx     z:tt
        lda     #44
        ldy     z:g8
        bne     :+
        lda     #52
:       sta     z:rh
        lsr     a
        eor     #$FFFF
        sec
        adc     z:cy
        sta     z:ry
        lda     #Q_PANEL
        jsr     fill
        lda     #NX + NW / 2
        sta     z:cx
        ldx     z:g8
        lda     queue,x
        and     #$00FF
        ; fall through
; piece A (turn 0) centred on cx, cy in tiles of csz from the table tt
preview:
        sta     z:g9
        asl     a
        asl     a
        tax
        lda     pbox+1,x                ; width: (max x - min x + 1) * csz
        sec
        sbc     pbox,x
        and     #$00FF
        inc     a
        jsr     @mul
        lsr     a
        sta     z:g0
        lda     pbox,x
        and     #$00FF
        jsr     @mul
        clc
        adc     z:g0
        eor     #$FFFF
        sec
        adc     z:cx
        sta     z:g6                    ; ox
        lda     pbox+3,x
        sec
        sbc     pbox+2,x
        and     #$00FF
        inc     a
        jsr     @mul
        lsr     a
        sta     z:g0
        lda     pbox+2,x
        and     #$00FF
        jsr     @mul
        clc
        adc     z:g0
        eor     #$FFFF
        sec
        adc     z:cy
        sta     z:g7                    ; oy
        lda     z:g9
        asl     a
        tay
        lda     (tt),y
        sta     db+12
        lda     z:csz
        sta     db+8
        sta     db+10
        lda     #WD_BLIT
        sta     db
        lda     z:g9                    ; turn 0's cells
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        tax
        lda     #4
        sta     z:g5
:       lda     pcells,x
        and     #$00FF
        jsr     @mul
        clc
        adc     z:g6
        sta     db+4
        lda     pcells+1,x
        and     #$00FF
        jsr     @mul
        clc
        adc     z:g7
        sta     db+6
        phx
        jsr     wd
        plx
        inx
        inx
        dec     z:g5
        bne     :-
        rts
@mul:   ldy     z:csz                   ; A * csz (small)
        sta     z:g1
        lda     #0
        cpy     #0
        beq     :++
:       clc
        adc     z:g1
        dey
        bne     :-
:       rts

; the score, right-aligned in its panel (2x font)
draw_score:
        lda     score
        ldx     score+2
        jsr     numstr
        lda     #LX + LW - 8
        sta     z:cx
        lda     #111
        sta     z:ry
        lda     #2
        sta     z:bk
        ldx     #.loword(numbuf)
        lda     #Q_TEXT | (Q_PANEL << 8)
        jsr     bigr
        eor     #$FFFF                  ; the space left of it
        sec
        adc     #LW - 16
        beq     @out
        bmi     @out
        sta     z:rw
        lda     #LX + 8
        sta     z:rx
        lda     #111
        sta     z:ry
        lda     #14
        sta     z:rh
        lda     #Q_PANEL
        jmp     fill
@out:   rts

; the numbers' labels (Marathon: level, lines, next level in; Time Attack: time, lines, level)
draw_stlabels:
        lda     #LX + 8
        sta     z:rx
        ldy     #0
:       phy
        tya
        asl     a
        tax
        lda     stat_y,x
        clc
        adc     #3
        sta     z:ry
        lda     mode
        beq     :+
        txa
        clc
        adc     #6
        tax
:       lda     stat_lab,x
        tax
        lda     #Q_MUTED | (Q_PANEL << 8)
        jsr     text
        ply
        iny
        cpy     #3
        bcc     :--
        rts
; their values
draw_stats:
        lda     #2
        sta     z:bk
        lda     mode
        jeq     @mar
        lda     tsec                    ; m:ss
        ldx     #60
        jsr     qdiv
        ldx     #0
        jsr     numstr
        ldx     #0
:       lda     numbuf,x
        and     #$00FF
        beq     :+
        inx
        bra     :-
:       lda     #':'
        sta     numbuf,x                ; (and a 0 after it)
        inx
        phx
        lda     tsec
        ldx     #60
        jsr     qmod
        ldx     #10
        jsr     qdiv
        ora     #'0'
        plx
        sta     numbuf,x
        inx
        phx
        lda     tsec
        ldx     #60
        jsr     qmod
        ldx     #10
        jsr     qmod
        ora     #'0'
        plx
        sta     numbuf,x
        lda     gflags                  ; green when seconds came, red in the last 10 s
        and     #GF_TIMEWON
        beq     @nw
        lda     #Q_P0FACE
        bra     @col
@nw:    lda     #Q_TEXT
        ldx     tsec
        cpx     #11
        bcs     @col
        lda     #Q_RED
@col:   ora     #Q_PANEL << 8
        ldy     #0
        jsr     statval
        lda     lines
        ldy     #1
        jsr     statnum
        lda     level
        ldy     #2
        jmp     statnum
@mar:   lda     level
        ldy     #0
        jsr     statnum
        lda     lines
        ldy     #1
        jsr     statnum
        lda     nextlv
        ldy     #2
; the number A in row Y (level: the accent; others white)
statnum:
        phy
        ldx     #0
        jsr     numstr
        ply
        lda     #Q_TEXT | (Q_PANEL << 8)
        cpy     #0
        bne     :+
        ldx     mode
        bne     :+
        lda     #Q_ACCENT | (Q_PANEL << 8)
:       cpy     #2
        bne     statval
        ldx     mode
        beq     statval
        lda     #Q_ACCENT | (Q_PANEL << 8)
; numbuf in row Y, right-aligned, colours A; the space left of it cleared
statval:
        pha
        tya
        asl     a
        tax
        lda     stat_y,x
        sta     z:ry
        sta     z:g8
        lda     #LX + LW - 8
        sta     z:cx
        pla
        ldx     #.loword(numbuf)
        jsr     bigr
        eor     #$FFFF
        sec
        adc     #LW - 16 - 60           ; (the label takes the left 60 pixels)
        beq     @out
        bmi     @out
        sta     z:rw
        lda     #LX + 8 + 60
        sta     z:rx
        lda     z:g8
        sta     z:ry
        lda     #14
        sta     z:rh
        lda     #Q_PANEL
        jmp     fill
@out:   rts

; the bonus of the last lock (a Quad, a spin, back-to-back, a combo) under the numbers
draw_msg:
        lda     nclr
        cmp     #4
        beq     :+
        lda     spin
        bne     :+
        lda     bonusf
        bne     :+
        rts
:       jsr     clear_msg
        ldx     #.loword(s_quad)        ; the first line: what it was
        lda     spin
        beq     @l1
        asl     a
        asl     a
        clc
        adc     nclr
        asl     a
        tax
        lda     spinmsg-8,x
        tax
@l1:    lda     nclr
        cmp     #4
        beq     :+
        lda     spin
        beq     @l2
:       lda     #LX + LW / 2
        sta     z:cx
        lda     #MSGY
        sta     z:ry
        lda     #Q_ACCENT | (Q_PANEL << 8)
        jsr     textc
@l2:    lda     bonusf                  ; the second: back-to-back, or the combo
        bit     #BF_B2B
        beq     :+
        ldx     #.loword(s_b2b)
        bra     @show
:       bit     #BF_COMBO
        beq     @pts
        lda     combo
        ldx     #0
        jsr     numstr
        ldx     #.loword(s_combo)
        ldy     #.loword(msgbuf)
        jsr     strcpy
        ldx     #.loword(numbuf)
        jsr     strcat
        ldx     #.loword(msgbuf)
        bra     @show
@pts:   lda     #'+'                    ; else the points
        sta     msgbuf
        lda     lastpts
        ldx     lastpts+2
        jsr     numstr
        ldx     #.loword(numbuf)
        ldy     #.loword(msgbuf + 1)
        jsr     strcpy
        ldx     #.loword(msgbuf)
@show:  lda     #LX + LW / 2
        sta     z:cx
        lda     #MSGY + 14
        sta     z:ry
        lda     #Q_TEXT | (Q_PANEL << 8)
        jsr     textc
        lda     #120
        sta     msgt
        rts
clear_msg:
        lda     #LX + 4
        sta     z:rx
        lda     #MSGY
        sta     z:ry
        lda     #LW - 8
        sta     z:rw
        lda     #28
        sta     z:rh
        lda     #Q_PANEL
        jmp     fill
; X -> Y (zero-terminated; Y: where its end is, for strcat)
strcpy: sty     z:g0
strcat0:
        ldy     #0
:       lda     a:0,x
        and     #$00FF
        sep     #$20
        .a8
        sta     (g0),y
        rep     #$20
        .a16
        beq     :+
        inx
        iny
        bra     :-
:       tya
        clc
        adc     z:g0
        sta     z:g0
        rts
strcat: bra     strcat0

; ---------------------------------------------------------------- pause and the end
draw_pause:
        lda     #0                      ; (no flash over the dimmed colours)
        sta     flashn
        ldx     #.loword(r_pause)
        jsr     rect
        lda     #Q_BOARD
        jsr     rrectc
        lda     #WX + SW * CELL / 2
        sta     z:cx
        lda     #WY + 108
        sta     z:ry
        lda     #2
        sta     z:bk
        ldx     #.loword(s_paused)
        lda     #Q_OTEXT | (Q_BOARD << 8)
        jsr     bigc
        lda     #WY + 130
        sta     z:ry
        ldx     #.loword(s_resume2)
        lda     #Q_OMUTED | (Q_BOARD << 8)
        jsr     textc
        lda     #WY + 144
        sta     z:ry
        ldx     #.loword(s_tomenu)
        lda     #Q_OMUTED | (Q_BOARD << 8)
        jsr     textc
        rts
; the cells under the pause box drawn again
undraw_pause:
        ldx     #7 * SW
        sep     #$20
        .a8
        lda     #$FF
:       sta     shown,x
        inx
        cpx     #13 * SW
        bcc     :-
        rep     #$20
        .a16
        lda     #.loword(stage)
        sta     z:dsrc
        ldy     #7 * SW
:       phy
        jsr     diffcell
        ply
        iny
        cpy     #13 * SW
        bcc     :-
        rts

; the end: the well fills with grey blocks from the bottom, a row a frame
draw_sweep:
        lda     sweepn
        inc     sweepn
        cmp     #SH
        bcs     @out
        eor     #$FFFF
        clc
        adc     #SH                     ; row 19 - n
        asl     a
        tax
        lda     rowy,x
        sta     z:ry
        lda     #WX
        sta     z:rx
        lda     #SW * CELL
        sta     z:rw
        lda     #CELL
        sta     z:rh
        lda     #2 | (CELL << 8)        ; (1.2) the rows' sheet, row 14
        sta     lshn
        ldx     #.loword(srow)
        jmp     blit
@out:   rts

; ---------------------------------------------------------------- the other screens
draw_title:
        jsr     draw_bg
        ldx     #0                      ; a few faint blocks
:       phx
        lda     deco,x
        sta     z:rx
        lda     deco+2,x
        sta     z:ry
        lda     #10
        sta     z:rw
        sta     z:rh
        ldx     #.loword(t_t10)
        jsr     kblit                   ; (its rounded corners: the background)
        plx
        inx
        inx
        inx
        inx
        cpx     #NDECO * 4
        bcc     :-
        lda     #64
        jsr     logo
        lda     #CW / 2
        sta     z:cx
        lda     #108
        sta     z:ry
        ldx     #.loword(s_edition)
        lda     #Q_ACCENT | $FF00
        jsr     textc
        lda     #148
        sta     z:ry
        lda     #2
        sta     z:bk
        ldx     #.loword(s_press)
        lda     #Q_OTEXT | $FF00
        jsr     bigc
        lda     #182
        sta     z:ry
        ldx     #.loword(s_keys1)
        lda     #Q_MUTED | $FF00
        jsr     textc
        lda     #196
        sta     z:ry
        ldx     #.loword(s_keys2)
        lda     #Q_MUTED | $FF00
        jsr     textc
        lda     hs_tab + HS_SCORE       ; the best Marathon score
        ora     hs_tab + HS_SCORE + 2
        beq     :+
        jsr     bestline
        lda     #CW / 2
        sta     z:cx
        lda     #226
        sta     z:ry
        ldx     #.loword(msgbuf)
        lda     #Q_ACCENT | $FF00
        jsr     textc
:       lda     #CW / 2
        sta     z:cx
        lda     #282
        sta     z:ry
        ldx     #.loword(s_esc)
        lda     #Q_MUTED | $FF00
        jmp     textc
; the logo at row A, centred
logo:   sta     z:ry
        lda     #(CW - LOGO_W) / 2
        sta     z:rx
        lda     #LOGO_W
        sta     z:rw
        lda     #LOGO_H
        sta     z:rh
        ldx     #.loword(t_logo)
        jmp     kblit
; "BEST  12480  NAME" -> msgbuf
bestline:
        ldx     #.loword(s_best)
        ldy     #.loword(msgbuf)
        jsr     strcpy
        lda     hs_tab + HS_SCORE
        ldx     hs_tab + HS_SCORE + 2
        jsr     numstr
        ldx     #.loword(numbuf)
        ldy     z:g0
        jsr     strcpy
        ldx     #.loword(s_gap)
        ldy     z:g0
        jsr     strcpy
        ldx     #.loword(hs_tab)
        ldy     z:g0
        jmp     strcpy

draw_setup:
        jsr     draw_bg
        lda     #12
        jsr     logo
        lda     #CW / 2
        sta     z:cx
        lda     #56
        sta     z:ry
        lda     #2
        sta     z:bk
        ldx     #.loword(s_setup)
        lda     #Q_TEXT | $FF00
        jsr     bigcs
        lda     #84
        sta     z:ry
        ldx     #.loword(s_mode)
        lda     #Q_MUTED | $FF00
        jsr     textc
        lda     #142
        sta     z:ry
        ldx     #.loword(s_stlv)
        lda     #Q_MUTED | $FF00
        jsr     textc
        lda     #232
        sta     z:ry
        ldx     #.loword(s_setkeys)
        lda     #Q_MUTED | $FF00
        jsr     textc
draw_setupvals:
        stz     z:g8                    ; the two mode buttons
@b:     lda     z:g8
        asl     a
        tax
        lda     btn_x,x
        sta     z:rx
        clc
        adc     #75
        sta     z:cx
        lda     #98
        sta     z:ry
        lda     #150
        sta     z:rw
        lda     #28
        sta     z:rh
        lda     z:g8
        cmp     mode
        bne     @off
        lda     #Q_BTN
        jsr     rrectc
        lda     #Q_GRAD0 | (Q_BTN << 8)
        bra     @t
@off:   jsr     panel
        lda     #Q_MUTED | (Q_PANEL << 8)
@t:     pha
        lda     #107
        sta     z:ry
        lda     z:g8
        asl     a
        tax
        lda     mode_names,x
        tax
        pla
        jsr     textc
        inc     z:g8
        lda     z:g8
        cmp     #2
        bcc     @b
        ldx     #.loword(r_lvbox)       ; the level
        jsr     rect
        jsr     panel
        lda     startlv
        ldx     #0
        jsr     numstr
        lda     #CW / 2
        sta     z:cx
        lda     #170
        sta     z:ry
        lda     #3
        sta     z:bk
        ldx     #.loword(numbuf)
        lda     #Q_ACCENT | (Q_PANEL << 8)
        jsr     bigc
        lda     #CW / 2 - 64            ; the arrows (dim at the ends)
        sta     z:rx
        lda     #170
        sta     z:ry
        ldx     #.loword(arr_l)
        lda     #Q_TEXT
        ldy     startlv
        cpy     #2
        bcs     :+
        lda     #Q_PANELB
:       jsr     arrow
        lda     #CW / 2 + 56
        sta     z:rx
        ldx     #.loword(arr_r)
        lda     #Q_TEXT
        ldy     startlv
        cpy     #MAXSTART
        bcc     :+
        lda     #Q_PANELB
:       jsr     arrow
        stz     z:g8                    ; the pips (1.1: 20, 9 pixels apart)
        lda     #CW / 2 - 88
        sta     z:rx
        lda     #214
        sta     z:ry
        lda     #6
        sta     z:rw
        lda     #4
        sta     z:rh
:       lda     #Q_ACCENT
        ldx     z:g8
        cpx     startlv
        bcc     :+
        lda     #Q_PANELB
:       jsr     fill
        lda     z:rx
        clc
        adc     #9
        sta     z:rx
        inc     z:g8
        lda     z:g8
        cmp     #MAXSTART
        bcc     :--
        lda     #20                     ; the description, over its band
        sta     z:rx
        lda     #252
        sta     z:ry
        lda     #CW - 40
        sta     z:rw
        lda     #12
        sta     z:rh
        lda     #252
        jsr     bgat
        jsr     fill
        lda     #CW / 2
        sta     z:cx
        ldx     #.loword(s_dmar)
        lda     mode
        beq     :+
        ldx     #.loword(s_dta)
:       lda     #Q_MUTED | $FF00
        jmp     textc
; an arrow (8 x 16, 1 bpp at X) at rx, ry in colour A over the background
arrow:  stx     db+12
        ora     #$FF00
        phx
        jsr     xc2
        plx
        sta     db+1
        sep     #$20
        .a8
        lda     #WD_EXPAND
        sta     db
        rep     #$20
        .a16
        stz     db+3
        lda     #1
        sta     db+15
        lda     #8
        sta     z:rw
        lda     #16
        sta     z:rh
        jsr     setr
        jmp     wd

; the new record: the score, the name being typed
draw_namescreen:
        jsr     draw_bg
        lda     #CW / 2
        sta     z:cx
        lda     #36
        sta     z:ry
        lda     #3
        sta     z:bk
        ldx     #.loword(s_record)
        lda     #Q_ACCENT | $FF00
        jsr     bigcs
        lda     #88
        sta     z:ry
        ldx     #.loword(s_final)
        lda     #Q_MUTED | $FF00
        jsr     textc
        lda     score
        ldx     score+2
        jsr     numstr
        lda     #104
        sta     z:ry
        lda     #3
        sta     z:bk
        ldx     #.loword(numbuf)
        lda     #Q_TEXT | $FF00
        jsr     bigcs
        lda     #152
        sta     z:ry
        ldx     #.loword(s_yname)
        lda     #Q_MUTED | $FF00
        jsr     textc
        ldx     #.loword(r_name)
        jsr     rect
        jsr     panel
        lda     #CW / 2
        sta     z:cx
        lda     #222
        sta     z:ry
        ldx     #.loword(s_save)
        lda     #Q_ACCENT | $FF00
        jsr     textc
draw_name:
        lda     #CW / 2 - 96
        sta     z:rx
        lda     #176
        sta     z:ry
        lda     #192
        sta     z:rw
        lda     #18
        sta     z:rh
        lda     #Q_PANEL
        jsr     fill
        lda     #CW / 2
        sta     z:cx
        lda     #178
        sta     z:ry
        lda     #2
        sta     z:bk
        ldx     #.loword(nbuf)
        jsr     bigw
        lsr     a
        eor     #$FFFF
        sec
        adc     #CW / 2
        sta     z:rx
        clc
        adc     z:bwid
        inc     a
        inc     a
        sta     caretx
        ldx     #.loword(nbuf)
        lda     #Q_TEXT | (Q_PANEL << 8)
        jsr     big
        stz     blink
draw_caret:
        lda     caretx
        sta     z:rx
        lda     #177
        sta     z:ry
        lda     #2
        sta     z:rw
        lda     #16
        sta     z:rh
        lda     #Q_ACCENT
        ldx     blink
        beq     :+
        lda     #Q_PANEL
:       jmp     fill

; the summary: the headline, the score, the table of this mode
draw_over:
        jsr     draw_bg
        lda     #CW / 2
        sta     z:cx
        lda     #16
        sta     z:ry
        lda     #3
        sta     z:bk
        ldx     #.loword(s_gover)
        lda     #Q_RED | $FF00
        ldy     timeup
        beq     :+
        ldx     #.loword(s_tup)
        lda     #Q_P6FACE | $FF00
:       jsr     bigcs
        lda     #52
        sta     z:ry
        ldx     #.loword(s_final)
        lda     #Q_MUTED | $FF00
        jsr     textc
        lda     score
        ldx     score+2
        jsr     numstr
        lda     #66
        sta     z:ry
        lda     #2
        sta     z:bk
        ldx     #.loword(numbuf)
        lda     #Q_TEXT | $FF00
        jsr     bigcs
        jsr     lvline
        lda     #88
        sta     z:ry
        ldx     #.loword(msgbuf)
        lda     #Q_MUTED | $FF00
        jsr     textc
        lda     mode
        sta     vmode
        lda     #112
        jsr     table
        lda     #CW / 2
        sta     z:cx
        lda     #282
        sta     z:ry
        ldx     #.loword(s_overkeys)
        lda     #Q_ACCENT | $FF00
        jmp     textc
; "Level 5  -  42 lines" -> msgbuf
lvline: ldx     #.loword(s_level2)
        ldy     #.loword(msgbuf)
        jsr     strcpy
        lda     level
        ldx     #0
        jsr     numstr
        ldx     #.loword(numbuf)
        ldy     z:g0
        jsr     strcpy
        ldx     #.loword(s_dot)
        ldy     z:g0
        jsr     strcpy
        lda     lines
        ldx     #0
        jsr     numstr
        ldx     #.loword(numbuf)
        ldy     z:g0
        jsr     strcpy
        ldx     #.loword(s_lines2)
        ldy     z:g0
        jmp     strcpy

; the high-score table of vmode in a panel from row A: rank, name, level, lines, score
table:  sta     z:g8
        lda     #48
        sta     z:rx
        lda     z:g8
        sta     z:ry
        lda     #CW - 96
        sta     z:rw
        lda     #5 * 18 + 30
        sta     z:rh
        jsr     panel
        lda     #CW / 2
        sta     z:cx
        lda     z:g8
        clc
        adc     #6
        sta     z:ry
        ldx     #.loword(s_hsm)
        lda     vmode
        beq     :+
        ldx     #.loword(s_hst)
:       lda     #Q_ACCENT | (Q_PANEL << 8)
        jsr     textc
        lda     z:g8
        clc
        adc     #26
        sta     z:g8                    ; the first row
        stz     z:g7                    ; (none yet: say so)
        jsr     hs_entry
        lda     a:HS_SCORE,x
        ora     a:HS_SCORE+2,x
        bne     @some
        lda     z:g8
        clc
        adc     #30
        sta     z:ry
        ldx     #.loword(s_noscore)
        lda     #Q_MUTED | (Q_PANEL << 8)
        jmp     textc
@some:  stz     z:g7                    ; rank
@r:     jsr     hs_entry                ; X = entry g7 of vmode
        stx     z:g6
        lda     a:HS_SCORE,x
        ora     a:HS_SCORE+2,x
        jeq     @next
        lda     z:g8
        sta     z:ry
        lda     z:g7                    ; "1."
        inc     a
        ldx     #0
        jsr     numstr
        ldx     #.loword(numbuf)
        ldy     #.loword(msgbuf)
        jsr     strcpy
        ldx     #.loword(s_pt)
        ldy     z:g0
        jsr     strcpy
        lda     #78
        sta     z:cx
        ldx     #.loword(msgbuf)
        lda     #Q_MUTED | (Q_PANEL << 8)
        jsr     textr
        lda     #Q_TEXT | (Q_PANEL << 8)  ; the new one in the accent
        ldx     z:g7
        cpx     hrank
        bne     :+
        ldx     vmode
        cpx     mode
        bne     :+
        lda     #Q_ACCENT | (Q_PANEL << 8)
:       sta     z:g5
        lda     #86
        sta     z:rx
        ldx     z:g6
        lda     z:g5
        jsr     text                    ; (the name is the entry's start)
        ldx     z:g6
        lda     a:HS_LEVEL,x
        and     #$00FF
        ldx     #0
        jsr     numstr
        lda     #196
        sta     z:cx
        ldx     #.loword(numbuf)
        lda     #Q_MUTED | (Q_PANEL << 8)
        jsr     textr
        ldx     z:g6
        lda     a:HS_LINES,x
        ldx     #0
        jsr     numstr
        lda     #240
        sta     z:cx
        ldx     #.loword(numbuf)
        lda     #Q_MUTED | (Q_PANEL << 8)
        jsr     textr
        ldx     z:g6
        lda     a:HS_SCORE+2,x
        tay
        lda     a:HS_SCORE,x
        tyx
        jsr     numstr
        lda     #CW - 60
        sta     z:cx
        ldx     #.loword(numbuf)
        lda     z:g5
        jsr     textr
@next:  lda     z:g8
        clc
        adc     #18
        sta     z:g8
        inc     z:g7
        lda     z:g7
        cmp     #HSN
        jcc     @r
        rts

; the tables (Game > High scores...)
draw_scores:
        jsr     draw_bg
        lda     #CW / 2
        sta     z:cx
        lda     #20
        sta     z:ry
        lda     #3
        sta     z:bk
        ldx     #.loword(s_hscores)
        lda     #Q_TEXT | $FF00
        jsr     bigcs
        lda     #62
        sta     z:ry
        ldx     #.loword(s_hshead)
        lda     #Q_MUTED | $FF00
        jsr     textc
        lda     #84
        jsr     table
        lda     #CW / 2
        sta     z:cx
        lda     #282
        sta     z:ry
        ldx     #.loword(s_hskeys)
        lda     #Q_ACCENT | $FF00
        jmp     textc

; how to play
draw_help:
        jsr     draw_bg
        lda     #CW / 2
        sta     z:cx
        lda     #10
        sta     z:ry
        lda     #2
        sta     z:bk
        ldx     #.loword(s_howto)
        lda     #Q_TEXT | $FF00
        jsr     bigcs
        ldx     #0
        lda     #36
        sta     z:ry
@l:     phx
        lda     help,x
        beq     @done
        tax
        lda     a:0,x
        and     #$00FF
        cmp     #'*'                    ; '*': a heading line (the accent)
        bne     :+
        inx
        lda     #Q_ACCENT | $FF00
        bra     :++
:       lda     #Q_TEXT | $FF00
:       sta     z:g6                    ; the colours
        ldy     #0                      ; up to a TAB into msgbuf
:       lda     a:0,x
        and     #$00FF
        cmp     #9
        beq     :+
        sep     #$20
        .a8
        sta     msgbuf,y
        rep     #$20
        .a16
        cmp     #0
        beq     :+
        inx
        iny
        bra     :-
:       stx     z:g7
        lda     #0
        sep     #$20
        .a8
        sta     msgbuf,y
        rep     #$20
        .a16
        lda     #20
        sta     z:rx
        ldx     #.loword(msgbuf)
        lda     z:g6
        jsr     text
        ldx     z:g7                    ; the second column
        lda     a:0,x
        and     #$00FF
        beq     :+
        inx
        lda     #196
        sta     z:rx
        lda     z:g6
        jsr     text
:       lda     z:ry
        clc
        adc     #13
        sta     z:ry
        plx
        inx
        inx
        bra     @l
@done:  plx
        rts

; ---------------------------------------------------------------- the frame's draw list (1.1)
; In play (and the sweep, the flash, the jolt) everything a frame draws goes into one draw list
; (SYS_DRAWLIST: Ali runs it as one command list), its first record waiting for the vertical
; blank (LS_VBL): a lock with its line clear (the cells, the rows moving down, whole empty rows,
; the panels' numbers) is one syscall and changes between two frames. wd turns each win_draw
; block into a record (fill, line: a fill; blit: copy; keyed blit; stride blit: copy with a
; stride; copy inside the window: move; expand). The list's sources are constant art (tiles,
; the logo, erow / srow) or the arena the big font is composed into for the list; the records
; and the arena are written again only after the list has run (lwait, or the next vsync, which
; waits for it). Text (win_draw's UI font, not a list op) waits in ltq and is drawn right after
; the next vsync (or before the program waits for events), over what the list drew. A whole
; screen (draw_bg) ends the list first and is drawn at once. Outside frames wd draws at once,
; and in frames too before REV $09 (lhw = 0: no command lists; see start).
LMAX    = 128                           ; records a list
LARENA  = 2048                          ; the big font's arena
LTQN    = 4                             ; texts waiting
LTQSZ   = 54                            ; x, y, colours, 48 characters
lbegin: lda     lhw                     ; (with Ali's command lists only)
        sta     lon
        lda     #LS_VBL
        sta     lvbl
        stz     lcnt
        stz     lpend
        stz     laren
        lda     #1
        sta     lall
        rts
; the frame's end: its list sent (not waited for: the next vsync does)
lfin:   jsr     lsend
        stz     lon
        rts
; the list ends now (a whole screen follows: drawn at once), the waiting texts drawn
lend:   lda     lon
        beq     :+
        jsr     lsend
        stz     lon
        jsr     ltexts
:       rts
; the records made so far sent: (1.2) as sheet records (sheet_draw) when every one is a fill
; or comes from the tiles or erow / srow, else as they are (draw_list)
lsend:  lda     lcnt
        beq     @out
        lda     lall
        beq     @dl
        lda     lsh
        beq     @dl
        jsr     lconv
        lda     lcnt
        xba
        ora     win
        ldx     #.loword(lbuf)
        ldy     pbank
        qsys    SYS_SHEETDRAW
        bra     @sent
@dl:    lda     lcnt
        xba
        ora     win
        ldx     #.loword(lbuf)
        ldy     pbank
        qsys    SYS_DRAWLIST
@sent:  stz     lcnt
        stz     laren
        lda     #1
        sta     lpend
        sta     lall
@out:   rts
; (1.2) lbuf's records as sheet_draw's (16 bytes, in place: record i is read whole before it is
; written at 16 i, and 16 i + 16 <= 20 (i + 1))
lconv:  stz     lc_i
        ldx     #0                      ; X: record i (20 bytes), Y: its sheet record (16)
        ldy     #0
@r:     lda     lbuf+LR_X,x
        sta     lc_x
        lda     lbuf+LR_Y,x
        sta     lc_y
        lda     lbuf+LR_W,x
        sta     lc_w
        lda     lbuf+LR_H,x
        sta     lc_h
        lda     lbuf+LR_C1,x            ; c1 | c2 << 8
        sta     lc_c
        lda     lbuf+LR_OP,x            ; op | flags << 8
        sta     lc_op
        phx
        lda     lc_i
        asl     a
        tax
        lda     lsv,x                   ; sheet | sy << 8, $FF a fill
        plx
        sta     lc_sv
        lda     lc_op
        and     #$00FF
        beq     @fill
        lda     lc_sv                   ; copy, keyed copy: 1 the tiles, 2 the rows; the key c2
        and     #$00FF
        cmp     #2
        lda     lsh
        bcc     :+
        lda     lsh2
:       sta     lc_sh
        lda     lc_c
        xba
        bra     @w
@fill:  stz     lc_sh                   ; a fill: no sheet, the colour c1
        stz     lc_sv
        lda     lc_c
@w:     and     #$00FF
        sta     lbuf+SD_C,y
        lda     lc_op                   ; the op (the same numbers), LS_VBL -> SH_VBL
        bit     #LS_VBL << 8
        beq     :+
        ora     #SH_VBL
:       xba
        and     #$FF00
        ora     lc_sh
        sta     lbuf+SD_SHEET,y
        lda     #0
        sta     lbuf+SD_SX,y
        lda     lc_sv
        xba
        and     #$00FF
        sta     lbuf+SD_SY,y
        lda     lc_w
        sta     lbuf+SD_W,y
        lda     lc_h
        sta     lbuf+SD_H,y
        lda     lc_x
        sta     lbuf+SD_X,y
        lda     lc_y
        sta     lbuf+SD_Y,y
        txa
        clc
        adc     #20
        tax
        tya
        clc
        adc     #16
        tay
        inc     lc_i
        lda     lc_i
        cmp     lcnt
        bcs     :+
        jmp     @r
:       rts
; (1.2) with command lists: the tiles (14 x 14 each, one after the other: 14 wide, 224 rows)
; and erow / srow (140 wide, 28 rows) as sheets, for lsend (none if either is refused)
lsheets:
        stz     lsh
        stz     lsh2
        lda     lhw
        beq     @out
        lda     #.loword(t_b14_0)
        ldx     #CELL
        ldy     #16 * CELL
        jsr     @new
        bcs     @out
        sta     lsh2                    ; (for the moment)
        lda     #.loword(erow)
        ldx     #SW * CELL
        ldy     #2 * CELL
        jsr     @new
        bcc     :+
        lda     lsh2
        sys     SYS_SHEETFREE
        stz     lsh2
        rts
:       ldx     lsh2
        stx     lsh
        sta     lsh2
@out:   rts
@new:   sta     lshb                    ; {address, stride, width, height}: X, X, Y
        lda     pbank
        sta     lshb+2
        stx     lshb+4
        stx     lshb+6
        sty     lshb+8
        ldx     #.loword(lshb)
        ldy     pbank
        sys     SYS_SHEETNEW
        rts
; (the list sent in this frame has run: its records and arena may be written again)
lwait:  lda     #0
        qsys    SYS_LISTWAIT
        stz     lpend
        rts
; room for a big string (bstr x 7 bk bytes) in the arena, and for its record -> A = where
lbig:   lda     z:bk
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:bk
        tax
        lda     z:bstr
        jsr     mulx
        sta     z:g0                    ; its bytes
        clc
        adc     laren
        cmp     #LARENA + 1
        bcs     @full
        lda     lcnt
        cmp     #LMAX
        bcc     @ok
@full:  jsr     lsend
@ok:    lda     lpend
        beq     :+
        jsr     lwait
:       lda     laren
        pha
        clc
        adc     z:g0
        sta     laren
        pla
        clc
        adc     #.loword(larena)
        rts

; db as a record of the list
ladd:   lda     lshn                    ; (1.2) the sheet it comes from, if any
        sta     lsvt
        stz     lshn
        lda     db
        and     #$00FF
        cmp     #WD_TEXT
        bne     :+
        jmp     ltext
:       cmp     #WD_DITHER              ; (not list ops: drawn at once after the list)
        beq     @now
        cmp     #WD_FRAME
        beq     @now
        cmp     #WD_KSBLIT
        bne     :+
@now:   jsr     lend
        jmp     wdnow
:       sta     z:lop
        lda     lcnt
        cmp     #LMAX
        bcc     :+
        jsr     lsend
:       lda     lpend
        beq     :+
        jsr     lwait
:       lda     lcnt                    ; the record: lbuf + 20 lcnt
        asl     a
        asl     a
        adc     lcnt
        asl     a
        asl     a
        tay
        inc     lcnt
        lda     db+4                    ; the common part
        sta     lbuf+LR_X,y
        lda     db+6
        sta     lbuf+LR_Y,y
        lda     db+8
        sta     lbuf+LR_W,y
        lda     db+10
        sta     lbuf+LR_H,y
        lda     db+12
        sta     lbuf+LR_SRC,y
        lda     pbank
        sta     lbuf+LR_SRC+2,y
        lda     #0
        sta     lbuf+LR_STRIDE,y
        sta     lbuf+LR_STRIDE+2,y
        sta     lbuf+LR_C1,y
        lda     lvbl                    ; flags: the frame's first record waits for the blank
        stz     lvbl
        xba
        sta     z:lfl
        lda     z:lop
        cmp     #WD_FILL
        bne     :+
        lda     db+1                    ; fill: c1
        and     #$00FF
        sta     lbuf+LR_C1,y
        lda     #LS_FILL
        jmp     @op
:       cmp     #WD_BLIT
        bne     :+
        lda     #LS_COPY
        jmp     @op
:       cmp     #WD_KBLIT
        bne     :+
        lda     db+1
        sta     lbuf+LR_C1,y
        lda     #LS_KEY
        jmp     @op
:       cmp     #WD_SBLIT
        bne     :+
        lda     db+1                    ; (its stride in c1, c2)
        sta     lbuf+LR_STRIDE,y
        lda     #LS_COPY
        jmp     @op
:       cmp     #WD_COPY
        bne     :+
        lda     db+1                    ; move: to (c1 | c2 << 8, ptr), from (x, y)
        sta     lbuf+LR_X,y
        lda     db+12
        sta     lbuf+LR_Y,y
        lda     db+4
        sta     lbuf+LR_SRC,y
        lda     db+6
        sta     lbuf+LR_SRC+2,y
        lda     #LS_MOVE
        jmp     @op
:       cmp     #WD_EXPAND
        bne     @line
        lda     db+1                    ; expand: ink, paper ($FF: keyed)
        sta     lbuf+LR_C1,y
        lda     db+15
        sta     lbuf+LR_STRIDE,y
        lda     db+2
        and     #$00FF
        cmp     #$00FF
        lda     #LS_EXPAND
        bcc     @op
        lda     #LS_EXPANDK
        jmp     @op
@line:  lda     db+1                    ; line (across or down): a fill of the rectangle
        and     #$00FF
        sta     lbuf+LR_C1,y
        lda     db+8                    ; x2 < x? swapped
        cmp     db+4
        bpl     :+
        sta     lbuf+LR_X,y
        lda     db+4
:       sec
        sbc     lbuf+LR_X,y
        inc     a
        sta     lbuf+LR_W,y
        lda     db+10
        cmp     db+6
        bpl     :+
        sta     lbuf+LR_Y,y
        lda     db+6
:       sec
        sbc     lbuf+LR_Y,y
        inc     a
        sta     lbuf+LR_H,y
        lda     #LS_FILL
@op:    pha
        ora     z:lfl
        sta     lbuf+LR_OP,y
        pla                             ; (1.2) a sheet record too? a fill; a copy or keyed
        beq     @fill                   ; copy from one of the sheets
        cmp     #LS_KEY + 1
        bcs     @nosh
        lda     lsvt
        bra     @sv
@fill:  lda     #$00FF
        bra     @sv
@nosh:  lda     #0
@sv:    pha
        lda     lcnt
        dec     a
        asl     a
        tax
        pla
        sta     lsv,x
        bne     :+
        stz     lall
:       rts

; a text for after the list: x, y, colours, the string (up to 47 characters) into ltq
ltext:  lda     ltqn
        cmp     #LTQN
        bcc     :+
        jsr     lend                    ; (full: the list now, the text at once)
        jmp     wdnow
:       ldx     #LTQSZ
        jsr     mulx
        tay
        inc     ltqn
        lda     db+4
        sta     ltq,y
        lda     db+6
        sta     ltq+2,y
        lda     db+1
        sta     ltq+4,y
        ldx     db+12
        lda     #47
        sta     z:g0
:       lda     a:0,x
        and     #$00FF
        dec     z:g0
        bne     :+
        lda     #0
:       sep     #$20
        .a8
        sta     ltq+6,y
        rep     #$20
        .a16
        inx
        iny
        cmp     #0
        bne     :--
        rts
; the texts waiting, drawn (after vsync: the list has run; else wait for it first)
ltexts: lda     ltqn
        beq     @out
        lda     lpend
        beq     :+
        jsr     lwait
:       stz     z:g7
@t:     lda     z:g7
        ldx     #LTQSZ
        jsr     mulx
        tax
        sep     #$20
        .a8
        lda     #WD_TEXT
        sta     db
        stz     db+3
        rep     #$20
        .a16
        lda     ltq,x
        sta     db+4
        lda     ltq+2,x
        sta     db+6
        lda     ltq+4,x
        sta     db+1
        txa
        clc
        adc     #.loword(ltq + 6)
        sta     db+12
        jsr     wdnow
        inc     z:g7
        lda     z:g7
        cmp     ltqn
        bcc     @t
        stz     ltqn
@out:   rts
