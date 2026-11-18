; SLIDER - the 4 x 4 sliding-tile puzzle ("15 puzzle") for Horizon (Atari816).
;
; Fifteen numbered tiles and one gap in a 4 x 4 frame. Slide tiles into the gap until they
; read 1 to 15, row by row, with the gap at the bottom right.
;
;   - Click a tile in the gap's row or column: it and every tile between it and the gap
;     slide over by one place (that is one move).
;   - Arrow keys: the tile next to the gap moves in the arrow's direction into the gap
;     (Left moves the tile right of the gap to the left, and so on).
;   - Game menu: New game (Ctrl+N), Quit (Ctrl+Q). Esc or the close box also quit.
;
; "slider -e" (easy) shuffles with two known moves instead of 200 random ones, so a test
; script can solve it: Up, then Left. In every mode a solved puzzle prints
; "slider: solved in N moves" on the console.
;
; What the program shows, part by part (search for the "----" headings):
;   start     - the arguments (ulib's args_init / next_arg), the window system, a window
;               with a menu.
;   loop      - the event loop: wait for one event (SYS_WEVENT), look at its type, act.
;   moves     - the board in memory (16 words, 0 = the gap), one tile sliding into the
;               gap (swap), a click turned into a direction (several tiles, one move).
;   shuffle   - 200 random legal moves from the solved board: every position reached this
;               way can be solved (a random arrangement of the tiles could not, half the
;               time). Random numbers: xorshift16 seeded with SYS_UPTIME.
;   drawing   - only what changed is drawn: a move redraws the cells it touched and the
;               status line. Text is drawn with its paper colour, so new text covers old
;               text in one call (no clearing first, no flicker).
;   sound     - a short tick per move (SYS_BEEP); a rising fanfare when solved, one note
;               per WE_TICK of the window timer (the program never sleeps: the window
;               keeps answering while the fanfare plays). Silence on exit.
;
; Registers: A, X, Y are 16-bit everywhere (".a16 / .i16"); the few 8-bit stores switch
; with "sep #$20 / .a8" and back with "rep #$20 / .a16" (ca65 does not follow REP/SEP by
; itself: horizon.inc turns that off).

        .include "horizon.inc"

; ---------------------------------------------------------------- constants
; The layout, in pixels of the window's content (everything on a 4-pixel grid).
TILE    = 44                            ; a tile is 44 x 44
PITCH   = 48                            ; tile + the 4-pixel gutter between tiles
WELLX   = 8                             ; the dark well the tiles sit in
WELLY   = 8
WELLW   = 4 + 4 * PITCH                 ; 4 + 192 = 196 (4 pixels round the tiles)
BX      = WELLX + 4                     ; the top left of tile (0, 0)
BY      = WELLY + 4
W       = WELLX + WELLW + 8             ; content 212 x 232
STATY   = WELLY + WELLW + 8             ; the status line (fixed font, 12 lines high)
H       = STATY + 12 + 8
SOLVX   = WELLX + WELLW - 7 * 8         ; "Solved!" ends at the well's right edge

; Colours. 0-15 are the system's (C_BODY is the window's beige); 16-231 are the 6 x 6 x 6
; colour cube, 16 + 36 r + 6 g + b with r, g, b 0-5; 232-255 greys.
C_WELL  = 234                           ; dark grey: the well and the gap
C_SOLVED = 16 + 36 * 0 + 6 * 2 + 0      ; dark green "Solved!"

; The four directions, seen from the gap: where the tile that moves is.
D_UP    = 0                             ; the tile above the gap (it moves down)
D_DOWN  = 1                             ; below (it moves up)
D_LEFT  = 2                             ; left of it (it moves right)
D_RIGHT = 3                             ; right of it (it moves left)

SHUFFLE = 200                           ; random moves for a new game

; HID key codes (ev+2 of WE_KEY)
K_N     = $11
K_Q     = $14
K_ESC   = $29
K_RIGHT = $4F
K_LEFT  = $50
K_DOWN  = $51
K_UP    = $52

        .segment "CODE"
        .a16
        .i16

; ---------------------------------------------------------------- start
; The program starts here (the first byte of CODE) with A = the length of its arguments
; and X = their address (in bank 0, our private window).
start:  sta     z:alen
        jsr     args_init               ; ulib: X = the arguments -> u_p points at them
        lda     z:alen
        beq     @noarg
        ptr     argbuf                  ; the first word into argbuf (8 bytes)
        lda     #8
        jsr     next_arg                ; -> A = its length, C set if there is none
        bcs     @noarg
        cmp     #2
        bne     @noarg
        lda     argbuf                  ; a 16-bit load reads both characters at once:
        cmp     #'-' | ('e' << 8)       ;   "-" in the low byte, "e" in the high byte
        bne     @noarg
        lda     #1
        sta     z:easy                  ; -e: the easy (test) shuffle
@noarg:
        sys     SYS_WSSTART             ; the window system: A = 1 if we started it (from
        bcc     :+                      ;   the text shell), 0 if it was running (Desktop)
        print   "slider: no window system\n"
        exit    1
:       sta     z:wsown                 ; remember: only its starter may stop it
        ptr     wopen
        sys     SYS_WOPEN               ; -> A = our window (its content is C_BODY)
        bcc     :+
        print   "slider: cannot open the window\n"
        jmp     quit
:       sta     z:win
        ptr     menus                   ; the menu bar shows these while we have the focus
        lda     z:win
        sys     SYS_WMENU
        sys     SYS_UPTIME              ; seed the random numbers with the time since boot
        ora     #1                      ;   (in ms; xorshift must not start at 0)
        sta     z:rnd
        jsr     newgame                 ; shuffle and draw everything

; ---------------------------------------------------------------- the event loop
; SYS_WEVENT with A = 0 sleeps until something happens to one of our windows and fills
; the 8-byte ev: u8 type, u8 window, u16 a, b, c. The program uses no CPU while waiting.
loop:   lda     #0
        ldx     #.loword(ev)
        ldy     #^ev
        sys     SYS_WEVENT
        bcs     loop
        lda     ev                      ; the type is the low byte
        and     #$00FF
        cmp     #WE_KEY
        bne     :+
        jsr     onkey
        bra     loop
:       cmp     #WE_BUTTON
        bne     :+
        jsr     onclick
        bra     loop
:       cmp     #WE_TICK
        bne     :+
        jsr     fanfare                 ; the window timer: the next note
        bra     loop
:       cmp     #WE_MENU
        bne     :+
        jsr     onmenu
        bra     loop
:       cmp     #WE_CLOSE               ; the close box, ctrl+W, the Desktop's Shut down
        jeq     quit
        bra     loop

; WE_KEY: a = HID usage, b = modifiers | down << 8 (we act on presses only)
onkey:  lda     ev+4
        bit     #$0100                  ; down?
        beq     @out
        and     #$0011                  ; left or right ctrl held?
        beq     @plain
        lda     ev+2
        cmp     #K_N
        jeq     newgame                 ; ctrl+N (newgame returns to the loop for us)
        cmp     #K_Q
        jeq     quit
@out:   rts
@plain: lda     ev+2
        cmp     #K_ESC
        jeq     quit
        cmp     #K_UP                   ; Up: the tile below the gap moves up
        bne     :+
        lda     #D_DOWN
        bra     keymove
:       cmp     #K_DOWN
        bne     :+
        lda     #D_UP
        bra     keymove
:       cmp     #K_LEFT
        bne     :+
        lda     #D_RIGHT
        bra     keymove
:       cmp     #K_RIGHT
        bne     @out
        lda     #D_LEFT
; A = direction: the tile on that side of the gap slides into it (if there is one)
keymove:
        ldx     z:solved                ; a solved board waits for New game
        bne     @out
        jsr     neighbour               ; -> A = that tile's cell, C set: off the board
        bcs     @out
        jsr     step1
        jmp     moved
@out:   rts

; WE_MENU: a = menu (0 = Game), b = item: New game (0), - (1), Quit (2)
onmenu: lda     ev+4
        jeq     newgame
        cmp     #2
        jeq     quit
        rts

; WE_BUTTON: a, b = x, y in our content; c = buttons | modifiers << 8. A press has bit 0
; of c set, the release clear.
onclick:
        lda     ev+6
        and     #1
        beq     @out
        lda     z:solved
        bne     @out
        lda     ev+2                    ; which cell? (column, row), or none
        jsr     cellof
        bcs     @out
        sta     z:ccol
        lda     ev+4
        jsr     cellof
        bcs     @out
        sta     z:crow
        asl     a                       ; cell = row * 4 + column
        asl     a
        ora     z:ccol
        sta     z:target
        cmp     z:gap
        beq     @out                    ; the gap itself
        lda     z:gap                   ; the gap's row = gap / 4
        lsr     a
        lsr     a
        cmp     z:crow
        bne     @col
        lda     z:gap                   ; same row: the gap's column = gap & 3
        and     #3
        sta     z:t0
        lda     z:ccol
        cmp     z:t0                    ; (lda does not change the carry)
        lda     #D_LEFT                 ; clicked left of the gap
        bcc     @go
        lda     #D_RIGHT
        bra     @go
@col:   lda     z:gap                   ; same column?
        and     #3
        cmp     z:ccol
        bne     @out                    ; neither: not a move
        lda     z:gap
        lsr     a
        lsr     a
        sta     z:t0
        lda     z:crow
        cmp     z:t0
        lda     #D_UP                   ; clicked above the gap
        bcc     @go
        lda     #D_DOWN
@go:    sta     z:dir                   ; move the gap one cell at a time towards the
@step:  lda     z:dir                   ;   clicked tile: each step slides one tile
        jsr     neighbour
        jsr     step1
        lda     z:gap
        cmp     z:target
        bne     @step
        jmp     moved                   ; all of it counts as one move
@out:   rts

; A = a content coordinate (x or y) -> A = column or row 0-3, C clear; C set if it is not
; on a tile (outside the board or in a gutter between tiles). BX = BY, so one routine.
cellof: sec
        sbc     #BX
        bmi     @no
        ldx     #0
:       cmp     #PITCH                  ; divide by 48: count the subtractions
        bcc     @in
        sbc     #PITCH
        inx
        bra     :-
@in:    cmp     #TILE                   ; the rest: 0-43 a tile, 44-47 the gutter
        bcs     @no
        cpx     #4
        bcs     @no
        txa
        clc
        rts
@no:    sec
        rts

; ---------------------------------------------------------------- moves
; The board is 16 words, cell 0 at the top left, cell 15 at the bottom right; each holds a
; tile number 1-15 or 0 for the gap. gap = the gap's cell.

; A = direction -> A = the cell on that side of the gap, C clear; C set if that is off the
; board.
neighbour:
        asl     a
        tax
        jmp     (@tab,x)                ; (jmp (a,x) reads the table in the code bank)
@tab:   .addr   @up, @down, @left, @right
@up:    lda     z:gap
        cmp     #4
        bcc     @none                   ; top row
        sbc     #4                      ; (carry set by the cmp)
        clc
        rts
@down:  lda     z:gap
        cmp     #12
        bcs     @none                   ; bottom row
        adc     #4                      ; (carry clear)
        rts
@left:  lda     z:gap
        bit     #3
        beq     @none                   ; left column
        dec     a
        clc
        rts
@right: lda     z:gap
        and     #3
        cmp     #3
        beq     @none                   ; right column
        lda     z:gap
        inc     a
        clc
        rts
@none:  sec
        rts

; A = a cell next to the gap: its tile moves into the gap, the cell becomes the gap.
; prev = where the gap was. Only memory: nothing is drawn (the shuffle uses this).
swap:   sta     z:t0
        asl     a
        tax
        lda     board,x                 ; the tile
        stz     board,x                 ; its cell is the gap now
        tay
        lda     z:gap
        sta     z:prev
        asl     a
        tax
        tya
        sta     board,x                 ; the tile in the old gap
        lda     z:t0
        sta     z:gap
        rts

; the same, and draw the two cells that changed
step1:  jsr     swap
        lda     z:prev
        jsr     drawcell                ; the tile at its new place
        lda     z:gap
        jmp     drawcell                ; the gap where it was

; after a move (one or several tiles): count it, tick, maybe solved, the status line
moved:  inc     z:moves
        lda     #20                     ; a short, high tick: pitch (AUDF) 20 ~ 1.5 kHz,
        ldx     #2                      ;   2 ticks of 10 ms, volume 6
        ldy     #6
        sys     SYS_BEEP
        jsr     issolved
        bcc     @show
        lda     #1
        sta     z:solved
        print   "slider: solved in "    ; to the console (under the Desktop: the log)
        lda     z:moves                 ; (print clobbers A, X, Y: load after it)
        jsr     put_dec
        print   " moves\n"              ; ulib sends a line when it ends
        jsr     fanfare_start
@show:  jmp     status

; -> C set if the board reads 1 ... 15 (then the gap is in the last cell)
issolved:
        ldx     #0
        lda     #1
:       cmp     board,x
        bne     @no
        inc     a
        inx
        inx
        cpx     #15 * 2
        bcc     :-
        sec
        rts
@no:    clc
        rts

; ---------------------------------------------------------------- shuffle
; New game: the solved board, shuffled, all drawn. Also stops a fanfare still playing.
newgame:
        jsr     fanfare_stop
        ldx     #0                      ; board = 1, 2, ... 15, 0
        lda     #1
:       sta     board,x
        inc     a
        inx
        inx
        cpx     #15 * 2
        bcc     :-
        stz     board + 15 * 2
        lda     #15
        sta     z:gap
        stz     z:moves
        stz     z:solved
        lda     z:easy
        bne     @easy
        jsr     shuffle
        bra     @draw
@easy:  lda     #D_LEFT                 ; two known moves: the gap goes left, then up.
        jsr     neighbour               ;   (Solve: Up, then Left.)
        jsr     swap
        lda     #D_UP
        jsr     neighbour
        jsr     swap
@draw:  jmp     drawall

; SHUFFLE random legal moves. A move that would undo the one before is skipped (it would
; waste the move). If the result happens to be solved, shuffle again.
shuffle:
        lda     #$FFFF
        sta     z:prev                  ; no move before the first
        lda     #SHUFFLE
        sta     z:count
@next:  jsr     random
        and     #3                      ; a direction 0-3
        jsr     neighbour
        bcs     @next                   ; off the board: pick again
        cmp     z:prev
        beq     @next                   ; back where the gap just was: pick again
        jsr     swap
        dec     z:count
        bne     @next
        jsr     issolved
        bcs     shuffle
        rts

; xorshift16 (shifts 7, 9, 8) -> A, a new pseudo-random number (never 0)
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
        xba                             ; << 8 (xba swaps the bytes; clear the low one)
        and     #$FF00
        eor     z:rnd
        sta     z:rnd
        rts

; ---------------------------------------------------------------- drawing
; Every drawing is one SYS_WDRAW with the 16-byte block blk:
;   +0 op, +1 c1 (ink), +2 c2 (paper), +3 font, +4 x, +6 y, +8 w, +10 h, +12 u24 ptr
; Each call costs ~0.2 ms (0.4 ms on the board), so a tile is 5 rectangles and a text:
; a move of 3 tiles is about 25 calls, a few ms.

; the whole window: the well (with a sunken edge), the 16 cells, the status line
drawall:
        lda     #WELLX - 1              ; the sunken edge: dark top and left, white bottom
        sta     z:rx                    ;   and right, one pixel outside the well
        lda     #WELLY - 1
        sta     z:ry
        lda     #WELLW + 2
        sta     z:rw
        lda     #1
        sta     z:rh
        lda     #C_DARK
        jsr     frect                   ; top
        lda     #1
        sta     z:rw
        lda     #WELLW + 2
        sta     z:rh
        lda     #C_DARK
        jsr     frect                   ; left
        lda     #WELLX + WELLW
        sta     z:rx
        lda     #C_WHITE
        jsr     frect                   ; right
        lda     #WELLX - 1
        sta     z:rx
        lda     #WELLY + WELLW
        sta     z:ry
        lda     #WELLW + 2
        sta     z:rw
        lda     #1
        sta     z:rh
        lda     #C_WHITE
        jsr     frect                   ; bottom
        lda     #WELLX                  ; the well
        sta     z:rx
        lda     #WELLY
        sta     z:ry
        lda     #WELLW
        sta     z:rw
        sta     z:rh
        lda     #C_WELL
        jsr     frect
        lda     #0                      ; every cell
:       pha
        jsr     drawcell
        pla
        inc     a
        cmp     #16
        bcc     :-
        jmp     status

; A = a cell 0-15: draw it, a raised tile or the gap
drawcell:
        sta     z:t0
        and     #3                      ; x = BX + column * 48 (48 = 32 + 16)
        asl     a
        asl     a
        asl     a
        asl     a
        sta     z:t1
        asl     a
        clc
        adc     z:t1
        adc     #BX
        sta     z:cx
        lda     z:t0                    ; y = BY + row * 48
        and     #$000C                  ; row * 4
        asl     a
        asl     a                       ; row * 16
        sta     z:t1
        asl     a
        clc
        adc     z:t1
        adc     #BY
        sta     z:cy
        lda     z:cx                    ; the whole cell first
        sta     z:rx
        lda     z:cy
        sta     z:ry
        lda     #TILE
        sta     z:rw
        sta     z:rh
        lda     z:t0
        asl     a
        tax
        lda     board,x
        sta     z:cv                    ; the tile's number, 0 = the gap
        bne     @tile
        lda     #C_WELL                 ; the gap: the well's colour
        jmp     frect
; A tile: its colour comes from its home row ((number - 1) / 4), so a solved board shows
; four stripes. Body, then the bevel: light top and left edges, dark bottom and right
; ones (2 pixels each; the dark ones are drawn last and win the two corners).
@tile:  dec     a
        lsr     a
        lsr     a
        tax                             ; X = the home row 0-3: index into the byte tables
        lda     t_light,x
        and     #$00FF
        sta     z:clight
        lda     t_dark,x
        and     #$00FF
        sta     z:cdark
        lda     t_body,x
        and     #$00FF
        sta     z:cbody
        jsr     frect                   ; the body (the 44 x 44 set above)
        lda     #2
        sta     z:rh
        lda     z:clight
        jsr     frect                   ; top edge 44 x 2
        lda     #2
        sta     z:rw
        lda     #TILE
        sta     z:rh
        lda     z:clight
        jsr     frect                   ; left edge 2 x 44
        lda     z:cx
        clc
        adc     #TILE - 2
        sta     z:rx
        lda     z:cdark
        jsr     frect                   ; right edge 2 x 44
        lda     z:cx
        sta     z:rx
        lda     z:cy
        clc
        adc     #TILE - 2
        sta     z:ry
        lda     #TILE
        sta     z:rw
        lda     #2
        sta     z:rh
        lda     z:cdark
        jsr     frect                   ; bottom edge 44 x 2
; The number: one or two digits in the fixed font (8 x 12 cells), centred:
; x = cx + (44 - 8 * digits) / 2, y = cy + (44 - 12) / 2.
        lda     z:cy
        clc
        adc     #(TILE - 12) / 2
        sta     z:ry
        lda     z:cv
        cmp     #10
        bcc     @one
        sbc     #10                     ; 10-15: "1" and a second digit
        clc
        adc     #'0'
        xba                             ; the second digit in the high byte ...
        ora     #'1'                    ; ... "1" in the low: one 16-bit store writes both
        sta     numbuf
        stz     numbuf+2                ; the end of the string
        lda     z:cx
        clc
        adc     #TILE / 2 - 8
        bra     @text
@one:   clc
        adc     #'0'                    ; the digit, and its high byte 0 ends the string
        sta     numbuf
        lda     z:cx
        clc
        adc     #TILE / 2 - 4
@text:  sta     z:rx
        lda     z:cbody                 ; ink white, paper = the tile's body
        xba
        ora     #C_WHITE
        ldx     #.loword(numbuf)
        jmp     text

; the status line: "Moves: N" at the left, "Solved!" (or blanks) at the right. Both are
; drawn with the window's paper colour, so they replace what was there.
status: ldx     #0                      ; "Moves: " into line
:       lda     s_moves,x
        and     #$00FF
        beq     :+
        jsr     putch
        bra     :-
:       lda     z:moves
        jsr     putdec
:       cpx     #12                     ; pad with spaces to 12 characters: covers the
        bcs     :+                      ;   longer number of a game before
        lda     #' '
        jsr     putch
        bra     :-
:       stz     line,x                  ; the end (a 16-bit store: line has room)
        lda     #WELLX
        sta     z:rx
        lda     #STATY
        sta     z:ry
        lda     #C_BLACK | (C_BODY << 8)
        ldx     #.loword(line)
        jsr     text
        lda     #SOLVX
        sta     z:rx
        ldx     #.loword(s_blank)
        lda     z:solved
        beq     :+
        ldx     #.loword(s_solved)
:       lda     #C_SOLVED | (C_BODY << 8)
        jmp     text

; A = 0-65535: its decimal digits at line,X (no leading zeros); X moves past them
putdec: sta     z:t0                    ; what is left of the number
        stz     z:t2                    ; 0 until the first digit is written
        ldy     #0                      ; index into pow10
@pow:   lda     #'0'
        sta     z:t1                    ; this digit, counted up
        lda     z:t0
:       cmp     pow10,y                 ; subtract the power of ten while we can
        bcc     @dig
        sbc     pow10,y                 ; (carry set by the cmp)
        inc     z:t1
        bra     :-
@dig:   sta     z:t0
        lda     z:t2
        bne     @put
        lda     z:t1
        cmp     #'0'
        beq     @skip                   ; a leading zero: leave it out
@put:   lda     z:t1
        jsr     putch
        sta     z:t2                    ; (non-zero: digits have started)
@skip:  iny
        iny
        cpy     #4 * 2
        bcc     @pow
        lda     z:t0                    ; the units, always
        clc
        adc     #'0'
; A = a character: one byte at line,X; X + 1. A byte store needs 8-bit A.
putch:  sep     #$20
        .a8
        sta     line,x
        rep     #$20
        .a16
        inx
        rts

; A = colour: fill the rectangle rx, ry, rw, rh
frect:  xba                             ; colour << 8 = c1
        and     #$FF00
        ora     #WD_FILL                ; op in the low byte
        sta     blk                     ; op and c1 in one store
        lda     z:rx
        sta     blk+4
        lda     z:ry
        sta     blk+6
        lda     z:rw
        sta     blk+8
        lda     z:rh
        sta     blk+10
        bra     wdraw

; A = ink | paper << 8, X = a string (in this bank): fixed-font text at rx, ry
text:   stx     blk+12                  ; ptr: the offset ...
        pha
        and     #$00FF                  ; ink -> c1
        xba
        ora     #WD_TEXT
        sta     blk
        pla
        xba                             ; paper -> c2 (low byte), font 1 (fixed) -> +3
        and     #$00FF
        ora     #1 << 8
        sta     blk+2
        lda     z:rx
        sta     blk+4
        lda     z:ry
        sta     blk+6
        lda     #^line                  ; ... and the bank (writes blk+15 too: blk has 16)
        sta     blk+14
wdraw:  lda     z:win
        ldx     #.loword(blk)
        ldy     #^blk
        sys     SYS_WDRAW
        rts

; ---------------------------------------------------------------- sound
; SYS_BEEP: A = pitch (POKEY AUDF: 31960 / Hz - 1), X = length in 10 ms ticks, Y = volume
; 0-15; a new beep replaces the one playing. The fanfare plays one note per WE_TICK of
; the window timer (SYS_WTIMER), so the event loop keeps running between notes.
fanfare_start:
        stz     z:note
        lda     z:win
        ldx     #12                     ; a WE_TICK every 120 ms
        sys     SYS_WTIMER
        ; (fall through: the first note now)
; WE_TICK: the next note, or after the last one the timer off
fanfare:
        lda     z:note
        cmp     #NOTES
        bcs     @stop
        asl     a                       ; {pitch, length} words: note * 4
        asl     a
        tax
        lda     notes+2,x
        pha                             ; the length (it goes to X)
        lda     notes,x
        plx
        ldy     #10
        sys     SYS_BEEP
        inc     z:note
        rts
@stop:  lda     z:win
        ldx     #0                      ; period 0: the timer off
        sys     SYS_WTIMER
        rts

; timer off and silence (X = 0: every voice off)
fanfare_stop:
        lda     #NOTES
        sta     z:note
        lda     z:win
        ldx     #0
        sys     SYS_WTIMER
        lda     #0
        ldx     #0
        ldy     #0
        sys     SYS_BEEP
        rts

; ---------------------------------------------------------------- the end
quit:   jsr     fanfare_stop            ; sound keeps playing after exit: silence it
        lda     z:win                   ; (exit would close our window anyway)
        sys     SYS_WCLOSE
        lda     z:wsown
        beq     :+
        sys     SYS_WSSTOP              ; we started the window system: stop it
:       exit    0

; ---------------------------------------------------------------- data
        .segment "RODATA"
wopen:  .word   (640 - (W + 2)) / 2 / 4 * 4, 56, W, H   ; outer x, y; content w, h
        .faraddr t_win
        .byte   0                       ; flags: a normal framed window with a close box
t_win:  .byte   "Slider", 0
; the menu bar: "Title", items ("text", TAB, "shortcut text"), "-" = a separator, an
; empty string ends a menu, another one ends the bar
menus:  .byte   "Game", 0
        .byte   "New game", 9, "Ctrl+N", 0
        .byte   "-", 0
        .byte   "Quit", 9, "Ctrl+Q", 0
        .byte   0
        .byte   0
s_moves: .byte  "Moves: ", 0
s_solved: .byte "Solved!", 0
s_blank: .byte  "       ", 0             ; as wide as "Solved!"
pow10:  .word   10000, 1000, 100, 10
; tile colours by home row: red, orange, green, blue (cube 16 + 36 r + 6 g + b)
t_body: .byte   16 + 36*4 + 6*1 + 1, 16 + 36*4 + 6*2 + 0, 16 + 36*1 + 6*3 + 1, 16 + 36*1 + 6*1 + 4
t_light: .byte  16 + 36*5 + 6*2 + 2, 16 + 36*5 + 6*3 + 1, 16 + 36*2 + 6*4 + 2, 16 + 36*2 + 6*2 + 5
t_dark: .byte   16 + 36*2 + 6*0 + 0, 16 + 36*2 + 6*1 + 0, 16 + 36*0 + 6*1 + 0, 16 + 36*0 + 6*0 + 2
        .byte   0                       ; (a 16-bit load of the last entry reads one more)
; the fanfare: {AUDF pitch, length in 10 ms} - C5 E5 G5 C6, the last one held
notes:  .word   60, 10, 47, 10, 40, 10, 29, 40
NOTES   = (* - notes) / 4

        .segment "BSS"
ev:     .res    8                       ; the event: u8 type, u8 window, u16 a, b, c
blk:    .res    16                      ; the win_draw block (15 bytes used)
board:  .res    16 * 2                  ; 16 cells, a word each: 1-15, 0 = the gap
line:   .res    32                      ; the status text
numbuf: .res    4                       ; a tile's number
argbuf: .res    8                       ; the first argument

        .segment "ZEROPAGE"             ; (last in the file: always written z:var above)
alen:   .res    2
wsown:  .res    2                       ; 1: we started the window system
win:    .res    2
easy:   .res    2                       ; 1: -e
rnd:    .res    2
gap:    .res    2                       ; the gap's cell 0-15
prev:   .res    2                       ; where the gap was before the last swap
moves:  .res    2
solved: .res    2
count:  .res    2
note:   .res    2                       ; the fanfare's next note
dir:    .res    2
target: .res    2
ccol:   .res    2
crow:   .res    2
cx:     .res    2                       ; drawcell: the cell's top left, its number
cy:     .res    2
cv:     .res    2
cbody:  .res    2
clight: .res    2
cdark:  .res    2
rx:     .res    2                       ; frect / text: the rectangle or the text place
ry:     .res    2
rw:     .res    2
rh:     .res    2
t0:     .res    2
t1:     .res    2
t2:     .res    2
