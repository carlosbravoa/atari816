; DEEPDIVE - a full-screen scrolling game skeleton for Horizon 0.18 (Atari816).
;
; A small submarine explores an underwater cave: collect the ten pearls and keep away from
; the jellyfish (three touches and you start again at the entrance). Arrow keys, W A S D or
; joystick 1 move; Esc ends (so do Alt+F4 and the window's close box).
;
; What it shows (sdk/docs/reference/games.md explains each part):
;   - full-screen mode (fs_enter): 320 x 180 x 8 bpp from a framebuffer in the program's own
;     memory, two consecutive banks from bank_alloc (69,888 bytes);
;   - the framebuffer as a ring of 21 x 12 tile slots (stride 336, vheight 192) under
;     Marga's scroll registers (fs_scroll) with horizontal and vertical wrap: the camera
;     moves pixel by pixel and only the column or row of tiles coming into view is drawn;
;   - a fixed status panel above the playfield: framebuffer rows 192-207, shown by the first
;     set of scroll registers; the playfield is the second set, from the split line on;
;   - one draw list a frame (draw_list): the new tiles and the panel's changes, with LS_VBL
;     on the first record, so that Ali starts in the vertical blank in which the new scroll
;     values and sprite positions are taken too: no tearing;
;   - (Horizon 0.19) the tiles as a sheet (sheet_new): a frame that only draws tiles sends them
;     as sheet_draw records, which the kernel checks and makes far cheaper; a frame that also
;     changes the panel (1 bpp letters: draw_list's LS_EXPAND) sends one draw_list as before;
;   - the frame loop on vsync (missed frames counted from its result);
;   - Marga's sprites: the submarine, four jellyfish and ten pearls, all set with one
;     spr_set a frame; SPR_BEHIND, so that they pass behind rock, weed and the panel;
;   - its own palette (pal_set: in full-screen mode all 256 entries are the program's) and a
;     raster table (fs_raster) that shades the water by depth;
;   - sound effects on Lau (sample_play), made at the start; silence without Lau;
;   - WE_UNFOCUS (Alt+Tab, Alt+Esc or F12 took the screen away) pauses until WE_FOCUS;
;     Esc and WE_CLOSE leave the full screen (fs_leave) and exit.
;
; The art is text in art/*.txt (made into art/*.inc by sdk/tools/img2inc.py and font2inc.py).

        .include "horizon.inc"

; ---------------------------------------------------------------- constants
TS      = 16                            ; tile size
MAPW    = 64                            ; the cave: 64 x 24 tiles, 1024 x 384 pixels
MAPH    = 24
WORLDW  = MAPW * TS
WORLDH  = MAPH * TS
SCRW    = 320                           ; the screen in FS_320X8
SCRH    = 180
PANH    = 16                            ; the panel: screen rows 0-15
SPLIT   = PANH * 2                      ; the split line (Marga counts 360 lines in every mode)
VIEWH   = SCRH - PANH                   ; 164 rows of playfield
RCOLS   = 21                            ; the ring of tile slots: 21 x 12
RROWS   = 12
STRIDE  = RCOLS * TS                    ; 336 bytes a row (a multiple of 16)
RINGH   = RROWS * TS                    ; 192 rows: the vertical wrap (vheight)
PANY    = RINGH                         ; the panel's rows in the framebuffer: 192-207
FBROWS  = RINGH + PANH                  ; 208 rows: 69,888 bytes, two banks
CAMXMAX = WORLDW - SCRW
CAMYMAX = WORLDH - VIEWH
T_WATER = 0                             ; tiles (frames of art/tiles.inc)
T_ROCK  = 1
T_TOP   = 2                             ; rock with sand on top
T_WEED  = 3
NJELLY  = 4
NPEARL  = 10
NSPR    = 1 + NJELLY + NPEARL           ; sprites: the submarine, jellyfish, pearls
IMG     = $1000                         ; the sprite images, copied into the window (bank 0):
IMG_SUB = IMG                           ;   16-byte aligned, the program's own memory
IMG_JELLY = IMG + 2 * 256
IMG_PEARL = IMG + 4 * 256
NIMG    = 5                             ; images of 256 bytes (8 bpp, 16 x 16)
SPEED   = 2                             ; pixels a frame
HULL    = 3
INVUL   = 120                           ; frames without harm after a touch
J_UP    = 1                             ; joy bits (port 1 of SYS_JOY)
J_DOWN  = 2
J_LEFT  = 4
J_RIGHT = 8
C_PANEL = 1                             ; palette entries (pal below)
C_TEXT  = 2
C_HEART = 3
C_DIM   = 4
HULLX   = 230                           ; the panel's layout (x)
NUMX    = 8 + 7 * 6
BLINGN  = 2400                          ; the samples: 0.15 s and 0.2 s at 16 kHz
THUDN   = 3200

        .segment "CODE"
        .a16
        .i16

start:  sys     SYS_WSSTART
        bcc     :+
        print   "deepdive: no window system\n"
        exit    1
:       sta     z:wsown
        ptr     wopen                   ; the window: full screen belongs to a window, and the
        sys     SYS_WOPEN               ; desktop shows it when another window takes the focus
                                        ; (Alt+Tab, Alt+Esc and F12 minimize it)
        jcs     quit
        sta     z:win
        lda     z:win
        ptr     wd_t1
        sys     SYS_WDRAW
        lda     z:win
        ptr     wd_t2
        sys     SYS_WDRAW
        jsr     makemap                 ; the map's characters -> tiles and objects
        ptr     tsblk                   ; (0.19) the tiles as a sheet: 16 wide, a tile under the
        sys     SYS_SHEETNEW            ; one before (frame t is rows 16 t); 0 if refused (an
        bcc     :+                      ; older Horizon): then every tile is a draw_list record
        lda     #0
:       sta     z:tsheet
        jsr     makesound               ; the samples (if there is Lau)
        jsr     getfb                   ; two consecutive banks for the framebuffer
        jcs     quit
        lda     #NSPR                   ; the sprites, for this window
        ldx     z:win
        sys     SYS_SPRALLOC
        bcc     :+
        print   "deepdive: no sprites (Marga REV $0B is needed)\n"
        jmp     quit
:       sta     z:spr0
        jsr     copyimg
        lda     z:fbb                   ; the framebuffer: row 0 at fbb:0000
        sep     #$20
        .a8
        sta     fsblk+8
        rep     #$20
        .a16
        lda     z:win
        ptr     fsblk
        sys     SYS_FSENTER
        bcc     :+
        jsr     error
        jmp     quit
:       lda     #0                      ; all 256 entries black while the screen is drawn
        ptr     black                   ; (the banks hold whatever was there before)
        sys     SYS_PALSET
        jsr     newgame
        jsr     drawall                 ; every tile slot and the panel: three draw lists
        lda     #0
        sys     SYS_LISTWAIT
        jsr     setscroll
        jsr     setsprites
        lda     #NRASTER                ; the water's shades (ENODEV before REV $09: one shade)
        ptr     raster
        sys     SYS_FSRASTER
        sys     SYS_VSYNC               ; the new screen is up: now its colours
        sta     z:lastf
        lda     #0 | (NPAL << 8)
        ptr     pal
        sys     SYS_PALSET
        print   "deepdive: diving\n"

; ---------------------------------------------------------------- the frame loop
frame:  sys     SYS_VSYNC               ; the next frame begins; our last list is done
        tax
        sec
        sbc     z:lastf                 ; frames since the last time: more than 1 = missed
        stx     z:lastf
        cmp     #2
        bcc     :+
        dec     a
        clc
        adc     z:missed
        sta     z:missed
:       sys     SYS_UPTIME
        sta     z:tstart
        jsr     events                  ; keys, focus, close (may pause, or quit)
        jsr     readjoy
        jsr     moveplayer
        jsr     movejellies
        jsr     touch                   ; pearls, jellyfish
        jsr     camera
        lda     #1                      ; this frame's list starts in the vertical blank
        sta     z:vblreq
        jsr     scrolltiles             ; the tiles coming into view
        jsr     panel                   ; the panel's changes
        jsr     flush                   ; one draw_list (if anything changed)
        jsr     setscroll               ; fs_scroll: taken in the same vertical blank
        jsr     setsprites              ; spr_set: all sprites, also from that blank on
        inc     z:fcount
        sys     SYS_UPTIME              ; the CPU time of this frame (from vsync to here)
        sec
        sbc     z:tstart
        clc
        adc     z:cpu
        sta     z:cpu
        jmp     frame

; ---------------------------------------------------------------- events
events: lda     #1                      ; poll: never wait in the frame loop
        ptr     ev
        sys     SYS_WEVENT
        bcs     @out
        jsr     onevent
        bra     events
@out:   rts

onevent:
        lda     ev
        and     #$00FF
        cmp     #WE_KEY
        beq     onkey
        cmp     #WE_CLOSE               ; Alt+F4, the close box
        jeq     quit
        cmp     #WE_UNFOCUS             ; Alt+Tab, Alt+Esc, F12: the desktop is back
        jeq     pause
        rts

; WE_KEY: a = HID usage (ev+2), b = modifiers | down << 8 (the down flag: byte ev+5)
onkey:  lda     ev+2
        cmp     #$29                    ; Esc pressed: the end
        bne     :+
        lda     ev+5
        and     #$00FF
        jne     quit
        rts
:       ldx     #0
@find:  cmp     keytab,x                ; usage -> joy bit
        beq     @bit
        inx
        inx
        inx
        inx
        cpx     #KEYTABN * 4
        bcc     @find
        rts
@bit:   lda     ev+5
        and     #$00FF
        beq     @up
        lda     keytab+2,x
        tsb     z:keys
        rts
@up:    lda     keytab+2,x
        trb     z:keys
        rts

; Not in front any more: the screen is the desktop's. Silence, then wait (blocking: no CPU
; used) until the window has the focus again; the kernel then shows our screen as it was.
pause:  stz     z:keys
        print   "deepdive: paused\n"
        lda     z:lau
        beq     @wait
        lda     #$FFFF
        sys     SYS_SSTOP
@wait:  lda     #0
        ptr     ev
        sys     SYS_WEVENT
        lda     ev
        and     #$00FF
        cmp     #WE_CLOSE
        jeq     quit
        cmp     #WE_FOCUS
        bne     @wait
        print   "deepdive: resumed\n"
        sys     SYS_FRAME               ; the frames meanwhile are not missed ones
        sta     z:lastf
        sys     SYS_UPTIME
        sta     z:tstart
        rts

readjoy:
        lda     #0
        sys     SYS_JOY
        bcc     :+
        lda     #0
:       and     #$000F                  ; port 1: up, down, left, right (the keys' bits)
        ora     z:keys
        sta     z:joy
        rts

; ---------------------------------------------------------------- the game
newgame:
        lda     z:startx
        sta     z:px
        lda     z:starty
        sta     z:py
        lda     #HULL
        sta     z:hull
        stz     z:inv
        stz     z:face
        rts

moveplayer:
        stz     z:moving
        lda     z:joy
        and     #J_LEFT
        beq     :+
        lda     #SPR_HFLIP              ; the art looks right: mirrored, it looks left
        sta     z:face
        lda     #.loword(-SPEED)
        jsr     movex
:       lda     z:joy
        and     #J_RIGHT
        beq     :+
        stz     z:face
        lda     #SPEED
        jsr     movex
:       lda     z:joy
        and     #J_UP
        beq     :+
        lda     #.loword(-SPEED)
        jsr     movey
:       lda     z:joy
        and     #J_DOWN
        beq     :+
        lda     #SPEED
        jsr     movey
:       rts

; px += A, py += A: each axis alone, so the submarine slides along walls
movex:  inc     z:moving
        clc
        adc     z:px
        sta     z:t0
        lda     z:py
        sta     z:t1
        jsr     blocked
        bcs     :+
        lda     z:t0
        sta     z:px
:       rts
movey:  inc     z:moving
        clc
        adc     z:py
        sta     z:t1
        lda     z:px
        sta     z:t0
        jsr     blocked
        bcs     :+
        lda     z:t1
        sta     z:py
:       rts

; the jellyfish drift up and down, one pixel every second frame, and turn at rock
movejellies:
        lda     z:fcount
        and     #1
        bne     @out
        ldx     #0
@j:     phx
        lda     jx,x
        sta     z:t0
        lda     jy,x
        clc
        adc     jdy,x
        sta     z:t1
        jsr     blocked
        plx
        bcs     @turn
        lda     z:t1
        sta     jy,x
        bra     @next
@turn:  lda     #0
        sec
        sbc     jdy,x
        sta     jdy,x
@next:  inx
        inx
        cpx     #NJELLY * 2
        bcc     @j
@out:   rts

; pearls picked up, jellyfish touched
touch:  lda     z:inv
        beq     :+
        dec     z:inv
:       ldx     #0
@p:     lda     egot,x
        bne     @pn
        lda     ex,x
        sta     z:t0
        lda     ey,x
        sta     z:t1
        jsr     near
        bcc     @pn
        inc     egot,x
        inc     z:pearls
        inc     z:pandirty
        phx
        lda     #.loword(sp_bling)
        jsr     play
        print   "deepdive: pearl "
        lda     z:pearls
        jsr     put_dec
        jsr     put_nl
        plx
@pn:    inx
        inx
        cpx     #NPEARL * 2
        bcc     @p
        lda     z:inv                   ; jellyfish
        bne     @out
        ldx     #0
@j:     lda     jx,x
        sta     z:t0
        lda     jy,x
        sta     z:t1
        jsr     near
        bcs     @hit
        inx
        inx
        cpx     #NJELLY * 2
        bcc     @j
@out:   rts
@hit:   lda     #INVUL
        sta     z:inv
        inc     z:pandirty
        lda     #.loword(sp_thud)
        jsr     play
        print   "deepdive: touched a jellyfish\n"
        dec     z:hull
        bne     @out
        print   "deepdive: back to the entrance\n"
        jsr     newgame
        inc     z:redraw                ; the camera jumps: every tile slot again
        rts

; C set if the 16 x 16 box at (t0, t1) is within 12 pixels of the submarine on both axes
near:   lda     z:t0
        sec
        sbc     z:px
        bpl     :+
        eor     #$FFFF
        inc     a
:       cmp     #12
        bcs     @no
        lda     z:t1
        sec
        sbc     z:py
        bpl     :+
        eor     #$FFFF
        inc     a
:       cmp     #12
        bcs     @no
        sec
        rts
@no:    clc
        rts

; C set if the 16 x 16 box at (t0, t1) touches rock (its corners, 2-3 pixels in)
blocked:
        lda     z:t0
        clc
        adc     #2
        sta     z:bl
        clc
        adc     #11
        sta     z:br
        lda     z:t1
        clc
        adc     #3
        sta     z:bt
        clc
        adc     #9
        sta     z:bb
        ldy     z:bt
        lda     z:bl
        jsr     solid
        bcs     @out
        ldy     z:bt
        lda     z:br
        jsr     solid
        bcs     @out
        ldy     z:bb
        lda     z:bl
        jsr     solid
        bcs     @out
        ldy     z:bb
        lda     z:br
        jmp     solid
@out:   rts

; A = x, Y = y in pixels -> C set if that pixel is rock (outside the map is rock)
solid:  lsr     a
        lsr     a
        lsr     a
        lsr     a
        pha
        tya
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        tay
        pla
        jsr     tileat
        cmp     #T_ROCK
        beq     @yes
        cmp     #T_TOP
        beq     @yes
        clc
        rts
@yes:   sec
        rts

; A = column, Y = row -> A = the tile there (rock outside the map). Uses X.
tileat: cmp     #MAPW
        bcs     @rock
        cpy     #MAPH
        bcs     @rock
        sta     z:t5
        tya
        asl     a                       ; row * 64
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     z:t5
        tax
        lda     map,x
        and     #$00FF
        rts
@rock:  lda     #T_ROCK
        rts

; the camera follows the submarine, inside the cave
camera: lda     z:px
        sec
        sbc     #SCRW / 2 - TS / 2
        bpl     :+
        lda     #0
:       cmp     #CAMXMAX
        bcc     :+
        lda     #CAMXMAX
:       sta     z:camx
        lda     z:py
        sec
        sbc     #VIEWH / 2 - TS / 2
        bpl     :+
        lda     #0
:       cmp     #CAMYMAX
        bcc     :+
        lda     #CAMYMAX
:       sta     z:camy
        rts

; ---------------------------------------------------------------- the ring of tile slots
; World tile (c, r) lives in slot (c mod 21, r mod 12) of the framebuffer. The ring holds
; the columns ltx .. ltx + 20 and the rows lty .. lty + 11, which cover every tile the
; camera (camx, camy) shows; Marga's x2 = camx mod 336 and y2 = camy mod 192 show them in
; place, wrapping around the ring's edges.
scrolltiles:
        lda     z:redraw
        beq     :+
        stz     z:redraw
        jmp     drawring
:       lda     z:camx
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     z:ntx                   ; the first column the camera shows
        lda     z:camy
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     z:nty
@right: lda     z:ltx                   ; moved right: the column after the ring's last
        cmp     z:ntx
        bcs     @left
        clc
        adc     #RCOLS
        jsr     loadcol
        inc     z:ltx
        bra     @right
@left:  lda     z:ltx                   ; moved left: the column before the first
        cmp     z:ntx
        beq     @down
        dec     z:ltx
        lda     z:ltx
        jsr     loadcol
        bra     @left
@down:  lda     z:lty
        cmp     z:nty
        bcs     @up
        clc
        adc     #RROWS
        jsr     loadrow
        inc     z:lty
        bra     @down
@up:    lda     z:lty
        cmp     z:nty
        beq     @out
        dec     z:lty
        lda     z:lty
        jsr     loadrow
        bra     @up
@out:   rts

; every slot (the start, a jump of the camera)
drawring:
        lda     z:camx
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     z:ltx
        lda     z:camy
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     z:lty
        sta     z:row
        lda     #RROWS
        sta     z:rcnt
:       lda     z:row
        jsr     loadrow
        inc     z:row
        dec     z:rcnt
        bne     :-
        rts

; column A of the map, rows lty .. lty + 11, into its slots
loadcol:
        sta     z:lc
        jsr     mod21
        asl     a
        asl     a
        asl     a
        asl     a
        sta     z:sx
        lda     z:lty
        sta     z:lr
        lda     #RROWS
        sta     z:lcnt
@r:     lda     z:lr
        jsr     mod12
        asl     a
        asl     a
        asl     a
        asl     a
        sta     z:sy
        ldy     z:lr
        lda     z:lc
        jsr     tileat
        jsr     rec_tile
        inc     z:lr
        dec     z:lcnt
        bne     @r
        rts

; row A of the map, columns ltx .. ltx + 20, into its slots
loadrow:
        sta     z:lr
        jsr     mod12
        asl     a
        asl     a
        asl     a
        asl     a
        sta     z:sy
        lda     z:ltx
        sta     z:lc
        lda     #RCOLS
        sta     z:lcnt
@c:     lda     z:lc
        jsr     mod21
        asl     a
        asl     a
        asl     a
        asl     a
        sta     z:sx
        ldy     z:lr
        lda     z:lc
        jsr     tileat
        jsr     rec_tile
        inc     z:lc
        dec     z:lcnt
        bne     @c
        rts

mod21:  cmp     #RCOLS
        bcc     :+
        sbc     #RCOLS
        bra     mod21
:       rts
mod12:  cmp     #RROWS
        bcc     :+
        sbc     #RROWS
        bra     mod12
:       rts

; Marga's scroll registers: the panel (first set) and the playfield (second set, wrapping)
setscroll:
        lda     z:camx
:       cmp     #STRIDE
        bcc     :+
        sbc     #STRIDE
        bra     :-
:       sta     scroll+4                ; x2 = camx mod 336
        lda     z:camy
:       cmp     #RINGH
        bcc     :+
        sbc     #RINGH
        bra     :-
:       sta     scroll+6                ; y2 = camy mod 192
        ptr     scroll
        sys     SYS_FSSCROLL
        bcc     :+
        jsr     error
:       rts

; ---------------------------------------------------------------- the draw list
; Records are added with rec_new; flush hands them to Ali with one draw_list. A full list
; (128 records) is flushed on the way. (0.19) Tiles go to a second list, slst, of sheet_draw
; records (rec_snew); flush sends it with sheet_draw when lst is empty (the usual frame), else
; turns its records into lst's first, so a frame is always one call.
; A tile copy: tile A into the slot at (sx, sy)
rec_tile:
        ldx     z:tsheet                ; (0.19) as a sheet record
        beq     rec_tdl
        xba                             ; frame A: rows 16 A of the sheet
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     z:src
        jsr     rec_snew
        lda     z:tsheet                ; the sheet, SH_COPY
        ora     #SH_COPY << 8
        sta     slst+SD_SHEET,x
        stz     slst+SD_C,x
        stz     slst+SD_SX,x
        lda     z:src
        sta     slst+SD_SY,x
        lda     #TS
        sta     slst+SD_W,x
        sta     slst+SD_H,x
        lda     z:sx
        sta     slst+SD_X,x
        lda     z:sy
        sta     slst+SD_Y,x
        rts
rec_tdl:
        xba                             ; * 256: a tile is 256 bytes
        clc
        adc     #.loword(tiles)
        sta     z:src
        jsr     rec_new
        lda     #LS_COPY                ; op, flags
        sta     lst+LR_OP,x
        stz     lst+LR_C1,x
        lda     z:sx
        sta     lst+LR_X,x
        lda     z:sy
        sta     lst+LR_Y,x
        lda     #TS
        sta     lst+LR_W,x
        sta     lst+LR_H,x
        lda     z:src
        sta     lst+LR_SRC,x
        lda     #^tiles                 ; the source's bank, then the byte 0
        sta     lst+LR_SRC+2,x
        stz     lst+LR_STRIDE,x         ; 0: rows of w bytes
        stz     lst+LR_STRIDE+2,x
        rts

; a letter A of the panel at (tx, PANY + 5), colours ink | paper << 8
rec_glyph:
        .assert font_GSIZE = 7, error, "rec_glyph multiplies by 7"
        sec
        sbc     #font_FIRST
        sta     z:t7
        asl     a                       ; * 7
        asl     a
        asl     a
        sec
        sbc     z:t7
        clc
        adc     #.loword(font)
        sta     z:src
        jsr     rec_new
        lda     #LS_EXPAND              ; 1 bpp: set bits c1, clear bits c2; from bit 7
        sta     lst+LR_OP,x
        lda     z:ink
        sta     lst+LR_C1,x             ; c1, c2
        lda     z:tx
        sta     lst+LR_X,x
        lda     #PANY + 5
        sta     lst+LR_Y,x
        lda     #font_W
        sta     lst+LR_W,x
        lda     #font_H
        sta     lst+LR_H,x
        lda     z:src
        sta     lst+LR_SRC,x
        lda     #^font
        sta     lst+LR_SRC+2,x
        lda     #font_BPR               ; expand: the bytes a row takes
        sta     lst+LR_STRIDE,x
        stz     lst+LR_STRIDE+2,x
        rts

; -> X = the offset of a new record in lst
rec_new:
        lda     z:nrec
        clc
        adc     z:nsrec
        cmp     #128
        bcc     :+
        jsr     flush
:       lda     z:nrec
        asl     a                       ; * 20
        asl     a
        sta     z:t7
        asl     a
        asl     a
        clc
        adc     z:t7
        tax
        inc     z:nrec
        rts

; (0.19) -> X = the offset of a new record in slst
rec_snew:
        lda     z:nrec
        clc
        adc     z:nsrec
        cmp     #128
        bcc     :+
        jsr     flush
:       lda     z:nsrec
        asl     a                       ; * 16
        asl     a
        asl     a
        asl     a
        tax
        inc     z:nsrec
        rts

; the records so far, as one draw_list; the first one waits for the vertical blank if asked.
; (0.19) Only sheet records: one sheet_draw instead; both kinds: the sheet records become
; draw_list records (copies from the tiles) after lst's
flush:  lda     z:nrec
        bne     :+
        lda     z:nsrec
        jne     sflush
        rts
:       lda     z:nsrec
        beq     :+
        jsr     s2l
:       lda     z:nrec
        beq     @out
        lda     z:vblreq
        beq     :+
        stz     z:vblreq
        sep     #$20
        .a8
        lda     #LS_VBL
        sta     lst+LR_FLAGS
        rep     #$20
        .a16
:       lda     z:nrec
        xba
        ora     z:win                   ; A = window | count << 8
        ptr     lst
        sys     SYS_DRAWLIST            ; returns at once: Ali works on
        bcc     :+
        jsr     error
:       stz     z:nrec
@out:   rts

; (0.19) slst as one sheet_draw (its first record waiting for the vertical blank if asked)
sflush: lda     z:vblreq
        beq     :+
        stz     z:vblreq
        sep     #$20
        .a8
        lda     slst+SD_OP
        ora     #SH_VBL
        sta     slst+SD_OP
        rep     #$20
        .a16
:       lda     z:nsrec
        xba
        ora     z:win
        ptr     slst
        sys     SYS_SHEETDRAW           ; returns at once, as draw_list
        bcc     :+
        jsr     error
:       stz     z:nsrec
        rts

; (0.19) slst's records appended to lst as copies from the tiles (there is room: rec_new and
; rec_snew keep both together at 128 at most); z:src, sx, sy kept
s2l:    lda     z:src                   ; (kept: the record being made when a full list is
        pha                             ; sent by rec_new)
        lda     z:sx
        pha
        lda     z:sy
        pha
        stz     z:soff                  ; slst's offset
@r:     dec     z:nsrec                 ; (first: rec_new must not flush)
        ldx     z:soff
        lda     slst+SD_SY,x            ; the tile: tiles + 16 * its row
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #.loword(tiles)
        sta     z:src
        lda     slst+SD_X,x
        sta     z:sx
        lda     slst+SD_Y,x
        sta     z:sy
        jsr     rec_new                 ; (keeps z:src, sx, sy)
        lda     #LS_COPY
        sta     lst+LR_OP,x
        stz     lst+LR_C1,x
        lda     z:sx
        sta     lst+LR_X,x
        lda     z:sy
        sta     lst+LR_Y,x
        lda     #TS
        sta     lst+LR_W,x
        sta     lst+LR_H,x
        lda     z:src
        sta     lst+LR_SRC,x
        lda     #^tiles
        sta     lst+LR_SRC+2,x
        stz     lst+LR_STRIDE,x
        stz     lst+LR_STRIDE+2,x
        lda     z:soff
        clc
        adc     #16
        sta     z:soff
        lda     z:nsrec
        bne     @r
        pla
        sta     z:sy
        pla
        sta     z:sx
        pla
        sta     z:src
        rts

; the start: every tile slot and the whole panel
drawall:
        jsr     camera
        jsr     drawring
        jsr     rec_new                 ; the panel's paper
        lda     #LS_FILL
        sta     lst+LR_OP,x
        lda     #C_PANEL
        sta     lst+LR_C1,x
        stz     lst+LR_X,x
        lda     #PANY
        sta     lst+LR_Y,x
        lda     #SCRW
        sta     lst+LR_W,x
        lda     #PANH
        sta     lst+LR_H,x
        lda     #C_TEXT | (C_PANEL << 8)
        sta     z:ink
        ldx     #.loword(t_pearls)
        lda     #8
        jsr     text
        ldx     #.loword(t_hull)
        lda     #HULLX
        jsr     text
        inc     z:pandirty
        jsr     panel
        stz     z:vblreq                ; (the palette is black: no need to wait)
        jmp     flush

; the panel's changes: the pearls found, the hull
panel:  lda     z:pandirty
        beq     @out
        stz     z:pandirty
        lda     z:pearls
        jsr     twodig
        lda     #C_TEXT | (C_PANEL << 8)
        sta     z:ink
        ldx     #.loword(numbuf)
        lda     #NUMX
        jsr     text
        lda     #HULLX + 5 * 6          ; a heart for each hit the hull still takes
        sta     z:tx
        stz     z:t6
@h:     lda     #C_HEART | (C_PANEL << 8)
        ldx     z:t6
        cpx     z:hull
        bcc     :+
        lda     #C_DIM | (C_PANEL << 8)
:       sta     z:ink
        lda     #'*'
        jsr     rec_glyph
        lda     z:tx
        clc
        adc     #font_W + 2
        sta     z:tx
        inc     z:t6
        lda     z:t6
        cmp     #HULL
        bcc     @h
        lda     z:pearls
        cmp     #NPEARL
        bne     @out
        lda     #C_TEXT | (C_PANEL << 8)
        sta     z:ink
        ldx     #.loword(t_all)
        lda     #NUMX + 8 * 6
        jsr     text
        print   "deepdive: all pearls found\n"
@out:   rts

; the string at X (code bank) at x = A, colours ink
text:   sta     z:tx
        stx     z:sp
@c:     ldy     #0
        lda     (sp),y
        and     #$00FF
        beq     @out
        jsr     rec_glyph
        lda     z:tx
        clc
        adc     #font_W
        sta     z:tx
        inc     z:sp
        bra     @c
@out:   rts

; A (0-99) -> two digits at numbuf
twodig: ldx     #'0'
:       cmp     #10
        bcc     :+
        sbc     #10
        inx
        bra     :-
:       clc
        adc     #'0'
        xba                             ; the units in the high byte
        stx     z:t7
        ora     z:t7                    ; the tens in the low byte
        sta     numbuf
        rts

; ---------------------------------------------------------------- sprites
; One spr_set for all of them: a table of NSPR entries of 10 bytes, positions on the screen
; (320 x 180), hidden (no SPR_EN) when off the screen.
setsprites:
        lda     z:spr0
        sta     z:sn
        stz     z:sxe
        lda     z:px                    ; the submarine
        sta     z:t0
        lda     z:py
        sta     z:t1
        lda     z:fcount                ; while it moves, the propeller's frame changes
        and     #4                      ; every 4 frames
        beq     :+
        lda     z:moving
        beq     :+
        lda     #256
:       clc
        adc     #IMG_SUB
        sta     z:t3
        lda     #SPR_EN | SPR_BEHIND
        ora     z:face
        sta     z:t2
        lda     z:inv                   ; blinking after a touch
        beq     :+
        and     #4
        beq     :+
        lda     #SPR_EN
        trb     z:t2
:
        jsr     sprent
        ldy     #0                      ; the jellyfish
@j:     lda     jx,y
        sta     z:t0
        lda     jy,y
        sta     z:t1
        tya                             ; each sways in its own time
        asl     a
        asl     a
        asl     a
        clc
        adc     z:fcount
        and     #16
        beq     :+
        lda     #256
:       clc
        adc     #IMG_JELLY
        sta     z:t3
        lda     #SPR_EN | SPR_BEHIND
        sta     z:t2
        jsr     sprent
        iny
        iny
        cpy     #NJELLY * 2
        bcc     @j
        ldy     #0                      ; the pearls not found yet
@p:     lda     ex,y
        sta     z:t0
        lda     ey,y
        sta     z:t1
        lda     #IMG_PEARL
        sta     z:t3
        lda     #SPR_EN | SPR_BEHIND
        ldx     egot,y
        beq     :+
        lda     #0
:       sta     z:t2
        jsr     sprent
        iny
        iny
        cpy     #NPEARL * 2
        bcc     @p
        lda     #NSPR
        ptr     sprtab
        sys     SYS_SPRSET
        bcc     :+
        jsr     error
:       rts

; the entry for sprite sn at sprtab + sxe: world position t0, t1, ctrl t2, image t3 (an
; offset in the window). Keeps Y.
sprent: ldx     z:sxe
        lda     z:t0
        sec
        sbc     z:camx
        sta     sprtab+SE_X,x
        clc
        adc     #TS                     ; -16 < x < 320?
        cmp     #SCRW + TS
        bcs     @hide
        lda     z:t1
        sec
        sbc     z:camy
        clc
        adc     #PANH
        sta     sprtab+SE_Y,x
        clc
        adc     #TS                     ; -16 < y < 180?
        cmp     #SCRH + TS
        bcc     :+
@hide:  lda     z:t2
        and     #.loword(~SPR_EN)
        sta     z:t2
:       lda     z:t2
        xba
        ora     z:sn                    ; u8 sprite, u8 ctrl
        sta     sprtab+SE_SPRITE,x
        lda     z:t3
        sta     sprtab+SE_IMAGE,x
        stz     sprtab+SE_IMAGE+2,x     ; bank 0 (the window), palette bank 0
        inc     z:sn
        txa
        clc
        adc     #10
        sta     z:sxe
        rts

; the sprite images into the window (Marga needs them 16-byte aligned)
copyimg:
        ldx     #0
:       lda     images,x
        sta     f:IMG,x
        inx
        inx
        cpx     #NIMG * 256
        bcc     :-
        rts

; ---------------------------------------------------------------- set-up
; Two consecutive banks: bank_alloc gives the lowest free bank, so usually the first two
; are; a bank that is not next to the one before is kept aside and given back at the end.
getfb:  sys     SYS_BALLOC
        bcs     @no
        sta     z:fbb
        stz     z:nspare
@more:  sys     SYS_BALLOC
        bcs     @no
        sta     z:t0
        dec     a
        cmp     z:fbb
        beq     @pair
        ldx     z:nspare
        lda     z:fbb
        sta     spare,x
        inx
        inx
        stx     z:nspare
        lda     z:t0
        sta     z:fbb
        cpx     #8 * 2
        bcc     @more
        bra     @no
@pair:  ldx     z:nspare
@free:  cpx     #0
        beq     @ok
        dex
        dex
        lda     spare,x
        sys     SYS_BFREE
        bra     @free
@ok:    clc
        rts
@no:    print   "deepdive: not enough memory\n"
        sec
        rts

; the map's characters (mapsrc) -> tiles (map), the objects' places
makemap:
        ldx     #0
        stz     z:col
        stz     z:row
@c:     lda     mapsrc,x
        and     #$00FF
        ldy     #T_ROCK
        cmp     #'#'
        beq     @put
        ldy     #T_WEED
        cmp     #'w'
        beq     @put
        ldy     #T_WATER
        cmp     #'o'
        bne     :+
        jsr     addpearl
        bra     @put
:       cmp     #'J'
        bne     :+
        jsr     addjelly
        bra     @put
:       cmp     #'S'
        bne     @put
        jsr     cellxy
        lda     z:t0
        sta     z:startx
        lda     z:t1
        sta     z:starty
@put:   tya
        sep     #$20
        .a8
        sta     map,x
        rep     #$20
        .a16
        inc     z:col
        lda     z:col
        cmp     #MAPW
        bcc     :+
        stz     z:col
        inc     z:row
:       inx
        cpx     #MAPW * MAPH
        bcc     @c
        ldx     #MAPW                   ; rock under water or weed: sand on top
@t:     lda     map,x
        and     #$00FF
        cmp     #T_ROCK
        bne     @n
        lda     map - MAPW,x
        and     #$00FF
        cmp     #T_ROCK
        beq     @n
        cmp     #T_TOP
        beq     @n
        sep     #$20
        .a8
        lda     #T_TOP
        sta     map,x
        rep     #$20
        .a16
@n:     inx
        cpx     #MAPW * MAPH
        bcc     @t
        rts

; (col, row) -> t0, t1 in pixels
cellxy: lda     z:col
        asl     a
        asl     a
        asl     a
        asl     a
        sta     z:t0
        lda     z:row
        asl     a
        asl     a
        asl     a
        asl     a
        sta     z:t1
        rts
; a pearl / a jellyfish at (col, row); keep X and Y
addpearl:
        phx
        jsr     cellxy
        ldx     z:np
        lda     z:t0
        sta     ex,x
        lda     z:t1
        sta     ey,x
        inx
        inx
        stx     z:np
        plx
        rts
addjelly:
        phx
        jsr     cellxy
        ldx     z:nj
        lda     z:t0
        sta     jx,x
        lda     z:t1
        sta     jy,x
        lda     #1                      ; drifting down first
        sta     jdy,x
        inx
        inx
        stx     z:nj
        plx
        rts

; ---------------------------------------------------------------- sound
; Two samples, made here (signed 8-bit, 16 kHz): a pearl's "bling" (a square wave, two notes
; up, fading out) and a touch's "thud" (noise held four samples, fading in steps).
makesound:
        sys     SYS_SSTAT               ; the cheapest test for Lau
        bcc     :+
        print   "deepdive: no Lau, no sound\n"
        rts
:       lda     #1
        sta     z:lau
        lda     #$ACE1                  ; the noise's seed
        sta     z:seed
        lda     #20                     ; 800 Hz
        sta     z:wper
        stz     z:ph
        ldx     #0
@b:     cpx     #BLINGN / 2
        bne     :+
        lda     #15                     ; then 1067 Hz
        sta     z:wper
:       stx     z:t0
        lda     #BLINGN
        sec
        sbc     z:t0
        lsr     a                       ; the amplitude: 75 .. 0
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     z:t1
        inc     z:ph
        lda     z:ph
        cmp     z:wper
        bcc     :+
        stz     z:ph
:       lda     z:ph
        asl     a
        cmp     z:wper                   ; the first half of the period: +, then -
        lda     z:t1
        bcc     :+
        eor     #$FFFF
        inc     a
:       sep     #$20
        .a8
        sta     bling,x
        rep     #$20
        .a16
        inx
        cpx     #BLINGN
        bcc     @b
        ldx     #0
@n:     txa
        and     #3
        bne     :+
        jsr     random
:       txa                             ; the loudness falls every 512 samples
        xba
        and     #$00FF
        lsr     a
        tay
        lda     thudmask,y
        and     #$00FF
        sta     z:t1
        lsr     a
        sta     z:t2
        lda     z:seed
        and     z:t1
        sec
        sbc     z:t2                    ; centred on 0
        sep     #$20
        .a8
        sta     thud,x
        rep     #$20
        .a16
        inx
        cpx     #THUDN
        bcc     @n
        rts

; a sample (A = its block's address in the code bank) on any free voice of Lau
play:   tax
        lda     z:lau
        beq     @out
        ldy     #^sp_bling
        sys     SYS_SPLAY
        bcs     @out
        lda     z:heard
        bne     @out
        inc     z:heard
        print   "deepdive: sound on Lau\n"
@out:   rts

; a 16-bit xorshift (seed)
random: lda     z:seed
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        eor     z:seed
        sta     z:seed
        xba
        and     #$00FF
        lsr     a
        eor     z:seed
        sta     z:seed
        xba
        and     #$FF00
        eor     z:seed
        sta     z:seed
        rts

; ---------------------------------------------------------------- the end
quit:   lda     z:win
        sys     SYS_FSLEAVE             ; back to the desktop (exit would do it too)
        lda     #$FFFF
        sys     SYS_SPRFREE
        lda     z:lau
        beq     :+
        lda     #$FFFF
        sys     SYS_SSTOP
:       print   "deepdive: bye after "
        lda     z:fcount
        jsr     put_dec
        print   " frames, "
        lda     z:missed
        jsr     put_dec
        print   " missed, CPU "
        lda     z:cpu
        jsr     put_dec
        print   " ms in all\n"
        lda     z:wsown
        beq     :+
        sys     SYS_WSSTOP
:       exit    0

error:  pha
        print   "deepdive: error "
        pla
        jsr     put_hex8
        jmp     put_nl

; ---------------------------------------------------------------- data
        .segment "RODATA"
t_title: .byte  "Deep Dive", 0
t_w1:   .byte   "Deep Dive is paused.", 0
t_w2:   .byte   "A click here, or Alt+Tab: dive again.", 0
wopen:  .word   180, 150, 280, 44       ; x, y, content width, height
        .faraddr t_title
        .byte   0
wd_t1:  .byte   WD_TEXT, C_BLACK, C_BODY, 0
        .word   10, 8, 0, 0
        .faraddr t_w1
        .byte   0
wd_t2:  .byte   WD_TEXT, C_BLACK, C_BODY, 0
        .word   10, 24, 0, 0
        .faraddr t_w2
        .byte   0
t_pearls: .byte "PEARLS", 0
t_hull: .byte   "HULL", 0
t_all:  .byte   "ALL FOUND!", 0
keytab: .word   $52, J_UP, $51, J_DOWN, $50, J_LEFT, $4F, J_RIGHT       ; arrows
        .word   $1A, J_UP, $16, J_DOWN, $04, J_LEFT, $07, J_RIGHT       ; W S A D
KEYTABN = (* - keytab) / 4

; the game's own palette (pal_set at the start: in full-screen mode all 256 entries are ours)
pal:    .byte   $2A, $86, $A8           ;  0 water (the raster table shades it below)
        .byte   $10, $18, $2C           ;  1 the panel
        .byte   $F0, $E6, $A0           ;  2 the panel's letters
        .byte   $E0, $40, $48           ;  3 a heart
        .byte   $48, $50, $60           ;  4 a lost heart
        .byte   $3A, $2E, $2A           ;  5 rock: dark, mid, light
        .byte   $6A, $54, $46
        .byte   $9C, $82, $68
        .byte   $D8, $C0, $84           ;  8 sand
        .byte   $1E, $6A, $30           ;  9 weed: dark, light
        .byte   $4C, $A8, $48
        .byte   $F0, $C0, $30           ; 11 the hull: yellow, shade
        .byte   $B0, $70, $18
        .byte   $A0, $E8, $F0           ; 13 glass
        .byte   $10, $10, $14           ; 14 outline
        .byte   $FF, $FF, $FF           ; 15 white
        .byte   $E0, $70, $B0           ; 16 jellyfish: body, light
        .byte   $F8, $B8, $DC
        .byte   $F4, $F0, $E8           ; 18 pearl, shade
        .byte   $B8, $A8, $D0
        .byte   $88, $90, $A0           ; 20 propeller
        .byte   $A0, $84, $50           ; 21 dark sand
        .byte   $A0, $40, $80           ; 22 jellyfish rim
NPAL = (* - pal) / 3

; the water darker with depth: entry 0 changed at these lines (from the split line on)
raster: .word   SPLIT
        .byte   0, $2A, $86, $A8
        .word   80
        .byte   0, $23, $78, $9A
        .word   128
        .byte   0, $1D, $6A, $8C
        .word   176
        .byte   0, $17, $5C, $7E
        .word   224
        .byte   0, $12, $4E, $70
        .word   272
        .byte   0, $0D, $41, $62
        .word   320
        .byte   0, $09, $35, $54
NRASTER = (* - raster) / 6

; the samples' blocks for sample_play
sp_bling: .faraddr bling
        .faraddr BLINGN
        .faraddr 0
        .word   $1555                   ; 16 kHz
        .byte   160, 160, 0, SP_ANY, 0
sp_thud: .faraddr thud
        .faraddr THUDN
        .faraddr 0
        .word   $1555
        .byte   220, 220, 0, SP_ANY, 0
thudmask: .byte $7F, $7F, $3F, $3F, $1F, $0F, $07, $07

; the art: tiles (copied by Ali from here), sprite images (copied to IMG first), the font
        .include "art/tiles.inc"
images:
        .include "art/sub.inc"
        .include "art/jelly.inc"
        .include "art/pearl.inc"
        .include "art/font.inc"

; The cave, 64 x 24: # rock, . water, w weed, o a pearl, J a jellyfish, S the start
mapsrc: .byte   "################################################################"
        .byte   "###.......########.................######..............#########"
        .byte   "##.........######...................####................########"
        .byte   "#..S.....o..........o.........o..........o.............#########"
        .byte   "#........................................................#######"
        .byte   "##....######.....J.....####...........#####...............######"
        .byte   "###..########..........######....J.....######.....####......####"
        .byte   "####.#########.........#######........#######....######......###"
        .byte   "####..########.........#######........######.....#######.....###"
        .byte   "###....######..........######..........####.......######......##"
        .byte   "##......####...........#####.....o.......................o.....#"
        .byte   "##..o..................................#####...................#"
        .byte   "##.....................................#######.........J.......#"
        .byte   "###......####...........####..........########.................#"
        .byte   "####....######.........######..........######......#####.......#"
        .byte   "####....######.........#######.....................######...o..#"
        .byte   "###......####...........#####.....######...........#####.......#"
        .byte   "##.......................###.....########......................#"
        .byte   "##..w.....o.....w..w............##########...w.................#"
        .byte   "##.www....#....www.ww...w......############.www................#"
        .byte   "###########################.....##########################.....#"
        .byte   "###########################..J...########################......#"
        .byte   "#############################......o.............w.....ww......#"
        .byte   "################################################################"

        .segment "DATA"
fsblk:  .byte   FS_320X8, 0             ; mode, flags (no pointer)
        .word   STRIDE, FBROWS          ; 336 bytes a row, 208 rows
        .faraddr 0                      ; row 0: fbb:0000 (the bank is set at the start)
        .byte   0
scroll: .word   0, PANY                 ; first set (lines 0-31): the panel, rows 192-207
        .word   0, 0                    ; second set: x2, y2 (the camera, set every frame)
        .word   RINGH                   ; vheight: rows 0-191 wrap
        .word   SPLIT                   ; the split line
        .byte   FSC_HWRAP | FSC_SPLIT, 0
numbuf: .byte   "00/10", 0
tsblk:  .faraddr tiles                  ; (0.19) sheet_new: the tiles, 16 wide, tiles_N of 16 rows
        .byte   0
        .word   TS, TS, TS * tiles_N

        .segment "BSS"
ev:     .res    8
map:    .res    MAPW * MAPH + 1         ; tiles, a byte each
lst:    .res    128 * 20                ; the draw list's records
slst:   .res    128 * 16                ; (0.19) sheet_draw's records (the tiles)
sprtab: .res    NSPR * 10               ; the spr_set table
black:  .res    256 * 3                 ; a black palette
spare:  .res    16
jx:     .res    NJELLY * 2
jy:     .res    NJELLY * 2
jdy:    .res    NJELLY * 2
ex:     .res    NPEARL * 2
ey:     .res    NPEARL * 2
egot:   .res    NPEARL * 2
bling:  .res    BLINGN
thud:   .res    THUDN

        .segment "ZEROPAGE"
wsown:  .res    2
win:    .res    2
fbb:    .res    2                       ; the framebuffer's first bank
nspare: .res    2
spr0:   .res    2                       ; our first sprite
lau:    .res    2
heard:  .res    2
keys:   .res    2
joy:    .res    2
px:     .res    2                       ; the submarine (world pixels)
py:     .res    2
startx: .res    2
starty: .res    2
face:   .res    2                       ; 0 or SPR_HFLIP
moving: .res    2
hull:   .res    2
inv:    .res    2
pearls: .res    2
camx:   .res    2
camy:   .res    2
ltx:    .res    2                       ; the ring's first column and row
lty:    .res    2
ntx:    .res    2
nty:    .res    2
redraw: .res    2
nrec:   .res    2
nsrec:  .res    2                       ; (0.19) records in slst
tsheet: .res    2                       ; (0.19) the tiles' sheet (0: none)
soff:   .res    2                       ; (0.19) s2l: the record in slst
vblreq: .res    2
pandirty: .res  2
fcount: .res    2
lastf:  .res    2
missed: .res    2
cpu:    .res    2
tstart: .res    2
col:    .res    2
row:    .res    2
rcnt:   .res    2
lc:     .res    2
lr:     .res    2
lcnt:   .res    2
sx:     .res    2
sy:     .res    2
src:    .res    2
tx:     .res    2
ink:    .res    2
sp:     .res    2
sn:     .res    2
sxe:    .res    2
np:     .res    2
nj:     .res    2
bl:     .res    2
br:     .res    2
bt:     .res    2
bb:     .res    2
wper:   .res    2
ph:     .res    2
seed:   .res    2
t0:     .res    2
t1:     .res    2
t2:     .res    2
t3:     .res    2
t5:     .res    2
t6:     .res    2
t7:     .res    2
