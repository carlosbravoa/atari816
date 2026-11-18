; PAINT - a 256-colour bitmap editor (/BIN/PAINT.PRG): "paint [path]".
;
; The window: a tool column (pencil, line, rectangle, filled rectangle, flood fill,
; eyedropper), the canvas (320 x 200 at 1:1 in a 1-pixel frame), the palette under it (the
; 16 UI colours in a row, then the 6x6x6 cube as 6 rows of 36 - columns 6 r + b, rows g -
; and the 24 greys in 4 more columns), and the foreground / background swatches.
; (0.18: Paint shows the whole system palette and holds no entries; no pal_alloc needed.)
; Left click on the palette: foreground; right click: background; a click on the swatches
; swaps them. Drawing with the left button uses the foreground, with the right button the
; background (the eyedropper: right click picks the background). The pointer is a
; crosshair over the canvas (the window has WF_HOVER: motion events without a button).
; Keys: 1 / P pencil, 2 / L line, 3 / R rectangle, 4 / F filled rectangle, 5 / B flood fill,
;       6 / I eyedropper, X swap the colours; ctrl-Z undo (again: redo), ctrl-S save,
;       ctrl-O open, ctrl-N new.
;
; Memory: the canvas (CB) and the undo copy (UB) are banks of 64,000 bytes, row by row
; (offset 320 y + x, system palette indices). Before each change the canvas is copied to
; UB (MVN); Undo swaps the two banks. A third bank (SB) is the flood fill's seed stack and
; the file buffer. The window shows the bank with WD_SBLIT (stride 320), only the rectangle
; that changed. Line and rectangle previews are drawn in the window only (the bank stays
; as it was), so erasing one is a blit of its rectangle from the bank.
;
; Flood fill: 4-way scan-line fill; seeds {u16 x, u16 y} on a stack in SB (16,383 of them).
; When the stack overflows, the seed is dropped and, once the stack is empty, the canvas is
; scanned for target pixels next to pixels this fill changed (canvas = new colour and UB =
; the target colour) and those are pushed again, until a pass ends without an overflow.
;
; File format .PIC ("Paint picture"):
;   offset 0   8 bytes  "H816PIC1"
;          8   u16      width  (little-endian)
;          10  u16      height
;          12  width * height bytes: system palette indices, row by row, top row first.
; Paint writes 320 x 200 pictures. It reads any width up to 32768 and any height: the part
; that fits the canvas is kept (top left), the rest of the canvas is white.
; File > Save as BMP writes an 8-bit uncompressed Windows BMP (BITMAPINFOHEADER, the system
; palette as its 256-entry colour table, bottom-up rows of 320 bytes): 65,078 bytes.
        .include "horizon.inc"
        .include "ui.inc"

.ifndef STKMAX
STKMAX  = 65532                         ; the seed stack's last entry offset (4 bytes each)
.endif
CX      = 40                            ; the canvas in the content
CY      = 8
CW      = 320
CH      = 200
TBX     = 8                             ; tool buttons: TBS x TBS, TBSTEP apart
TBY     = 8
TBS     = 24
TBSTEP  = 28
NTOOL   = 6
PALX    = 40                            ; the palette: the UI row (20 x 12 cells),
PALY    = 216                           ; then 6 rows of 40 cells of 8 x 8
PALY2   = PALY + 12
SWX     = 8                             ; swatches: fg at (SWX, SWY), bg 8 down right
SWY     = 216
SWS     = 16
WINW    = 368
WINH    = 284
KEY     = 255                           ; the icons' transparent colour
CHUNK   = 8000

T_PENCIL = 0
T_LINE  = 1
T_RECT  = 2
T_FRECT = 3
T_FILL  = 4
T_PICK  = 5

        .segment "CODE"
        .a16
        .i16
start:  sta     argl
        stx     argx
        sys     SYS_WSSTART
        bcc     :+
        print   "paint: no window system\n"
        exit    1
:       sta     wsown
        jsr     ui_init
        sys     SYS_BALLOC
        jcs     nomem
        sta     cbank
        sys     SYS_BALLOC
        jcs     nomem
        sta     ubank
        sys     SYS_BALLOC
        jcs     nomem
        sta     sbank
        jsr     setptrs
        lda     #1                      ; white
        jsr     clearc
        jsr     getarg
        ptr     wopen
        sys     SYS_WOPEN
        bcc     :+
        jsr     stopws
        print   "paint: no window\n"
        exit    1
:       sta     win
        ptr     menus
        sys     SYS_WMENU
        jsr     drawall
        lda     fpath
        and     #$00FF
        beq     :+
        jsr     load
        jsr     showall
:       jsr     settitle
        jmp     loop

nomem:  jsr     stopws
        print   "paint: not enough memory\n"
        exit    1

stopws: lda     wsown
        beq     :+
        sys     SYS_WSSTOP
:       rts

quit:   lda     #0
        jsr     setptr
        lda     win
        sys     SYS_WCLOSE
        jsr     stopws
        exit    0

; the long pointers to the canvas, the undo copy and the stack bank
setptrs:
        stz     z:cp
        lda     cbank
        sta     z:cp+2
        stz     z:up
        lda     ubank
        sta     z:up+2
        stz     z:sp
        lda     sbank
        sta     z:sp+2
        rts

; the argument: a path (quotes, or "\ " for a space) -> fpath, absolute
getarg: stz     fpath
        lda     argl
        beq     @out
        ldx     argx
        jsr     args_init
        jsr     str_skip
        ldx     #0
        cmp     #'"'
        bne     @pl
        inc     z:u_p
@q:     lda     [u_p]
        and     #$00FF
        beq     @end
        cmp     #'"'
        beq     @end
        jsr     @put
        inc     z:u_p
        bra     @q
@pl:    lda     [u_p]
        and     #$00FF
        beq     @trim
        cmp     #$5C                    ; backslash
        bne     :+
        inc     z:u_p
        lda     [u_p]
        and     #$00FF
        beq     @trim
:       jsr     @put
        inc     z:u_p
        bra     @pl
@trim:  cpx     #0
        beq     @end
        lda     abuf-1,x
        and     #$00FF
        cmp     #' '
        bne     @end
        dex
        bra     @trim
@end:   stz     abuf,x
        cpx     #0
        beq     @out
        ldx     #.loword(abuf)
        jsr     mkabs
@out:   rts
@put:   cpx     #120
        bcs     :+
        sep     #$20
        .a8
        sta     abuf,x
        rep     #$20
        .a16
        inx
:       rts

; the name X (in our bank) made absolute -> fpath
mkabs:  stx     z:t0
        lda     (t0)
        and     #$00FF
        cmp     #'/'
        bne     :+
        ldy     #.loword(fpath)
        jmp     ui_strcpy
:       ptr     fpath
        lda     #128
        sys     SYS_GETCWD
        bcc     :+
        lda     #0
:       tax
        beq     :+
        lda     fpath-1,x
        and     #$00FF
        cmp     #'/'
        beq     :++
:       lda     #'/'
        sta     fpath,x
        inx
:       ldy     #0
:       lda     (t0),y
        and     #$00FF
        sep     #$20
        .a8
        sta     fpath,x
        rep     #$20
        .a16
        beq     :+
        inx
        iny
        cpx     #127
        bcc     :-
        stz     fpath,x
:       rts

; ---------------------------------------------------------------- events
loop:   lda     #0
        jsr     ui_getev
        bcs     loop
        ldx     #.loword(noctls)        ; (keeps the library's button state, makes ui_key)
        jsr     ui_event
        lda     ui_ev
        and     #$00FF
        cmp     #WE_MOTION
        jeq     onmotion
        cmp     #WE_BUTTON
        jeq     onbutton
        cmp     #WE_KEY
        jeq     onkey
        cmp     #WE_MENU
        beq     onmenu
        cmp     #WE_CLOSE
        jeq     m_close
        cmp     #WE_LEAVE
        bne     loop
        lda     op                      ; the pointer left the window
        jne     loop
        lda     #0
        jsr     setptr
        jmp     loop

onmenu: lda     op                      ; (not in the middle of a drag)
        jne     loop
        lda     ui_ev+2                 ; menu: File 0, Edit 1
        asl     a
        tax
        lda     ui_ev+4                 ; item (counting separators)
        asl     a
        tay
        jmp     (mtab,x)
m_file: tyx
        cpx     #14
        jcs     loop
        jmp     (ftab,x)
m_edit: tyx
        cpx     #4
        jcs     loop
        jmp     (etab,x)

m_new:  jsr     confirm
        jcs     loop
        stz     fpath
        lda     #1
        jsr     clearc
        stz     emod
        stz     canundo
        jsr     settitle
        jsr     showall
        jmp     loop
m_open: jsr     confirm
        jcs     loop
        stz     dlgbuf
        lda     #0
        ldx     #.loword(dlgbuf)
        ldy     #.loword(t_open)
        jsr     ui_filedlg
        jcs     loop
        ldx     #.loword(dlgbuf)
        ldy     #.loword(fpath)
        jsr     ui_strcpy
        jsr     load
        jsr     settitle
        jsr     showall
        jmp     loop
m_save: jsr     do_save
        jmp     loop
m_saveas:
        jsr     do_saveas
        jmp     loop
m_bmp:  jsr     do_bmp
        jmp     loop
m_close:
        lda     op
        jne     loop
        jsr     confirm
        jcs     loop
        jmp     quit
m_undo: lda     canundo
        jeq     loop
        lda     cbank                   ; swap the canvas and its copy
        ldx     ubank
        sta     ubank
        stx     cbank
        jsr     setptrs
        jsr     setmod
        jsr     showall
        jmp     loop
m_clear:
        jsr     snap
        lda     bg
        jsr     clearc
        jsr     setmod
        jsr     showall
        jmp     loop

; a key
onkey:  lda     ui_ev+4
        cmp     #$0100
        jcc     loop
        lda     op
        jne     loop
        lda     ui_key
        jeq     loop
        sta     key
        lda     ui_ev+4
        and     #$0011
        beq     @plain
        lda     key                     ; ctrl
        cmp     #26
        jeq     m_undo
        cmp     #19
        jeq     m_save
        cmp     #15
        jeq     m_open
        cmp     #14
        jeq     m_new
        jmp     loop
@plain: lda     key
        cmp     #'1'
        bcc     :+
        cmp     #'1' + NTOOL
        bcs     :+
        sec
        sbc     #'1'
        jmp     settool
:       ora     #$20                    ; letters in lower case
        sta     key
        ldx     #NTOOL - 1
:       lda     toolkeys,x
        and     #$00FF
        cmp     key
        beq     @tool
        dex
        bpl     :-
        lda     key
        cmp     #'x'
        jne     loop
        jsr     swapc
        jmp     loop
@tool:  txa
        jmp     settool

; A = tool: pressed in the tool column
settool:
        and     #$00FF
        cmp     tool
        jeq     loop
        pha
        lda     tool
        sta     z:t6
        pla
        sta     tool
        lda     z:t6
        jsr     drawtool
        lda     tool
        jsr     drawtool
        jmp     loop

; swap the foreground and background colours
swapc:  lda     bg
        pha
        lda     fg
        sta     bg
        pla
        jmp     setfg

; the mouse
onbutton:
        lda     op
        beq     @press
        lda     ui_ev+6                 ; a drag ends when its button is up
        and     opbtn
        jne     loop
        jsr     evpos
        jsr     opmove
        jsr     opend
        jmp     loop
@press: lda     ui_ev+6
        and     #3
        jeq     loop
        lda     ui_ev+2
        sta     z:ex
        lda     ui_ev+4
        sta     z:ey
        lda     z:ex                    ; the canvas?
        sec
        sbc     #CX
        cmp     #CW
        bcs     @ncv
        lda     z:ey
        sec
        sbc     #CY
        cmp     #CH
        bcs     @ncv
        jsr     evpos
        lda     ui_ev+6
        and     #1
        beq     :+
        sta     opbtn                   ; left: drawn in the foreground
        lda     fg
        sta     dcol
        jmp     opstart
:       lda     ui_ev+6                 ; right (alone)
        and     #2
        jeq     loop
        lda     tool                    ; the eyedropper picks the background
        cmp     #T_PICK
        bne     :+
        jsr     pixat
        sta     bg
        jsr     drawsw
        jmp     loop
:       lda     #2                      ; the other tools draw in the background colour
        sta     opbtn
        lda     bg
        sta     dcol
        jmp     opstart
@ncv:   lda     z:ex                    ; the palette?
        sec
        sbc     #PALX
        cmp     #CW
        bcs     @npal
        lda     z:ey
        sec
        sbc     #PALY
        cmp     #60
        bcs     @npal
        jsr     palhit
        tax
        lda     ui_ev+6
        and     #1
        beq     :+
        txa
        jsr     setfg
        jmp     loop
:       stx     bg
        jsr     drawsw
        jmp     loop
@npal:  lda     ui_ev+6                 ; (the rest: left button only)
        and     #1
        jeq     loop
        lda     z:ex                    ; the tool column?
        sec
        sbc     #TBX
        cmp     #TBS
        bcs     @ntool
        lda     z:ey
        sec
        sbc     #TBY
        cmp     #NTOOL * TBSTEP
        bcs     @ntool
        ldx     #0
:       cmp     #TBSTEP
        bcc     :+
        sbc     #TBSTEP
        inx
        bra     :-
:       cmp     #TBS
        jcs     loop
        txa
        jmp     settool
@ntool: lda     z:ex                    ; the swatches?
        sec
        sbc     #SWX
        cmp     #SWS + 8
        jcs     loop
        lda     z:ey
        sec
        sbc     #SWY
        cmp     #SWS + 8
        jcs     loop
        jsr     swapc
        jmp     loop

onmotion:
        jsr     evpos
        lda     op
        beq     :+
        jsr     opmove
        jmp     loop
:       jsr     hoverptr                ; (WF_HOVER) the crosshair over the canvas
        jmp     loop

; the pointer at z:px, z:py: the crosshair over the canvas, else the arrow
hoverptr:
        lda     #2
        ldx     z:px
        cpx     #CW
        bcs     :+
        ldx     z:py
        cpx     #CH
        bcc     setptr
:       lda     #0
; the pointer shape A (a syscall only when it changes)
setptr: cmp     pshape
        beq     :+
        sta     pshape
        sys     SYS_WPTR
:       rts

; the event's position in canvas coordinates -> z:px, z:py (signed, may be outside)
evpos:  lda     ui_ev+2
        sec
        sbc     #CX
        sta     z:px
        lda     ui_ev+4
        sec
        sbc     #CY
        sta     z:py
        rts

; z:px, z:py clamped to the canvas -> z:cx1, z:cy1
clampp: lda     z:px
        bpl     :+
        lda     #0
:       cmp     #CW
        bcc     :+
        lda     #CW - 1
:       sta     z:cx1
        lda     z:py
        bpl     :+
        lda     #0
:       cmp     #CH
        bcc     :+
        lda     #CH - 1
:       sta     z:cy1
        rts

; the colour at z:px, z:py (inside) -> A
pixat:  lda     z:py
        jsr     mul320
        clc
        adc     z:px
        tay
        lda     [cp],y
        and     #$00FF
        rts

; ---------------------------------------------------------------- operations
; a left press on the canvas at z:px, z:py
opstart:
        lda     tool
        cmp     #T_FILL
        bne     @drag
        jsr     snap                    ; flood fill: at once
        lda     z:px
        sta     z:fx
        lda     z:py
        sta     z:fy
        lda     dcol
        sta     z:col
        jsr     flood
        bcs     :+
        jsr     setmod
        jsr     showall
:       jmp     loop
@drag:  inc     a
        sta     op
        lda     #2                      ; the crosshair while drawing
        jsr     setptr
        stz     pvon
        lda     dcol
        sta     z:col
        lda     tool
        cmp     #T_PICK
        bne     :+
        jsr     pixat
        jsr     setfg
        jmp     loop
:       cmp     #T_PENCIL
        bne     @shape
        jsr     snap
        jsr     setmod
        lda     z:px
        sta     z:lx
        lda     z:py
        sta     z:ly
        jsr     pencil
        jmp     loop
@shape: jsr     clampp
        lda     z:cx1
        sta     z:cx0
        lda     z:cy1
        sta     z:cy0
        jsr     preview
        jmp     loop

; the pointer moved (or the button went up) at z:px, z:py during a drag
opmove: lda     op
        dec     a
        cmp     #T_PICK
        bne     :+
        lda     z:px                    ; eyedropper: inside the canvas only
        cmp     #CW
        bcs     @out
        lda     z:py
        cmp     #CH
        bcs     @out
        jsr     pixat
        jmp     setfg
:       cmp     #T_PENCIL
        bne     :+
        jmp     pencil
:       jsr     clampp
        lda     z:cx1                   ; a shape: the preview follows
        cmp     z:pcx
        bne     :+
        lda     z:cy1
        cmp     z:pcy
        beq     @out
:       jsr     unpreview
        jsr     preview
@out:   rts

; the button went up: commit a shape
opend:  lda     op
        stz     op
        dec     a
        cmp     #T_LINE
        bcc     @done
        cmp     #T_PICK
        bcs     @done
        pha
        jsr     snap
        pla
        cmp     #T_LINE
        bne     :+
        lda     z:cx0
        sta     z:lx
        lda     z:cy0
        sta     z:ly
        lda     z:cx1
        sta     z:px
        lda     z:cy1
        sta     z:py
        jsr     line
        bra     @show
:       pha
        jsr     shapebox
        pla
        cmp     #T_RECT
        bne     @fr
        lda     z:qy0                   ; a frame: four lines
        jsr     @hl
        lda     z:qy1
        jsr     @hl
        lda     z:qx0
        jsr     @vl
        lda     z:qx1
        jsr     @vl
        bra     @show
@fr:    lda     z:qy0                   ; filled: every row
        sta     z:t5
:       lda     z:t5
        jsr     @hl
        lda     z:t5
        cmp     z:qy1
        beq     @show
        inc     z:t5
        bra     :-
@show:  jsr     setmod
        jsr     unpreview               ; (the rectangle of the shape: from the bank)
@done:  jmp     hoverptr                ; (the crosshair stays over the canvas)
@hl:    jsr     mul320                  ; row A from qx0 to qx1
        clc
        adc     z:qx0
        tay
        lda     z:qx1
        sec
        sbc     z:qx0
        tax
        sep     #$20
        .a8
        lda     z:col
:       sta     [cp],y
        iny
        dex
        bpl     :-
        rep     #$20
        .a16
        rts
@vl:    sta     z:t4                    ; column A from qy0 to qy1
        lda     z:qy0
        jsr     mul320
        clc
        adc     z:t4
        tay
        lda     z:qy1
        sec
        sbc     z:qy0
        tax
:       sep     #$20
        .a8
        lda     z:col
        sta     [cp],y
        rep     #$20
        .a16
        tya
        clc
        adc     #CW
        tay
        dex
        bpl     :-
        rts

; the shape cx0, cy0 - cx1, cy1 ordered -> qx0 <= qx1, qy0 <= qy1
shapebox:
        lda     z:cx0
        ldx     z:cx1
        jsr     order
        sta     z:qx0
        stx     z:qx1
        lda     z:cy0
        ldx     z:cy1
        jsr     order
        sta     z:qy0
        stx     z:qy1
        rts
; A, X (signed) -> A = the smaller, X = the larger
order:  stx     z:t7
        sta     z:o1
        sec
        sbc     z:t7
        bvc     :+
        eor     #$8000
:       bmi     :+
        lda     z:t7                    ; A >= X: swapped
        ldx     z:o1
        rts
:       lda     z:o1
        rts

; draw the shape cx0, cy0 - cx1, cy1 in the window only (not in the bank)
preview:
        lda     z:cx1
        sta     z:pcx
        lda     z:cy1
        sta     z:pcy
        jsr     shapebox
        lda     z:qx0
        sta     z:vx0
        lda     z:qy0
        sta     z:vy0
        lda     z:qx1
        sta     z:vx1
        lda     z:qy1
        sta     z:vy1
        lda     #1
        sta     pvon
        lda     fg
        xba
        and     #$FF00
        sta     z:t0
        lda     op
        dec     a
        cmp     #T_LINE
        bne     @box
        lda     z:t0
        ora     #WD_LINE
        sta     blk
        stz     blk+2
        lda     z:cx0
        clc
        adc     #CX
        sta     blk+4
        lda     z:cy0
        clc
        adc     #CY
        sta     blk+6
        lda     z:cx1
        clc
        adc     #CX
        sta     blk+8
        lda     z:cy1
        clc
        adc     #CY
        sta     blk+10
        jmp     wd
@box:   ldx     #WD_FRAME
        cmp     #T_RECT
        beq     :+
        ldx     #WD_FILL
:       txa
        ora     z:t0
        sta     blk
        stz     blk+2
        jsr     qgeom
        jmp     wd

; erase the preview: its rectangle from the bank
unpreview:
        lda     pvon
        beq     @out
        stz     pvon
        lda     z:vx0
        sta     z:qx0
        lda     z:vy0
        sta     z:qy0
        lda     z:vx1
        sta     z:qx1
        lda     z:vy1
        sta     z:qy1
        jmp     blitq
@out:   rts

; pencil: a line from (lx, ly) to (px, py) in the bank, shown; then (lx, ly) = (px, py)
pencil: lda     z:lx
        sta     z:cx0
        lda     z:ly
        sta     z:cy0
        lda     z:px
        sta     z:cx1
        lda     z:py
        sta     z:cy1
        jsr     line
        jsr     shapebox
        jsr     qclip
        bcs     :+
        jsr     blitq
:       lda     z:px
        sta     z:lx
        lda     z:py
        sta     z:ly
        rts

; qx0..qy1 (ordered, signed) clipped to the canvas; C set: nothing left
qclip:  lda     z:qx1
        bmi     @no
        lda     z:qy1
        bmi     @no
        lda     z:qx0
        bpl     :+
        stz     z:qx0
        lda     #0
:       cmp     #CW
        bcs     @no
        lda     z:qy0
        bpl     :+
        stz     z:qy0
        lda     #0
:       cmp     #CH
        bcs     @no
        lda     z:qx1
        cmp     #CW
        bcc     :+
        lda     #CW - 1
        sta     z:qx1
:       lda     z:qy1
        cmp     #CH
        bcc     :+
        lda     #CH - 1
        sta     z:qy1
:       clc
        rts
@no:    sec
        rts

; a line (Bresenham) from (lx, ly) to (px, py) in colour col, in the bank; pixels outside
; the canvas are skipped. Keeps px, py; moves lx, ly.
line:   lda     z:lx
        sta     z:ax
        lda     z:ly
        sta     z:ay
        lda     z:px                    ; dx = |px - x|, sx
        sec
        sbc     z:ax
        bpl     :+
        eor     #$FFFF
        inc     a
        ldx     #$FFFF
        bra     :++
:       ldx     #1
:       sta     z:ddx
        stx     z:lsx
        lda     z:py                    ; dy = -|py - y|, sy
        sec
        sbc     z:ay
        bmi     :+
        eor     #$FFFF
        inc     a
        ldx     #1
        bra     :++
:       ldx     #$FFFF
:       sta     z:ddy
        stx     z:lsy
        clc
        adc     z:ddx
        sta     z:lerr
@l:     lda     z:ax                    ; plot
        cmp     #CW
        bcs     :+
        lda     z:ay
        cmp     #CH
        bcs     :+
        jsr     mul320
        clc
        adc     z:ax
        tay
        sep     #$20
        .a8
        lda     z:col
        sta     [cp],y
        rep     #$20
        .a16
:       lda     z:ax
        cmp     z:px
        bne     :+
        lda     z:ay
        cmp     z:py
        beq     @out
:       lda     z:lerr
        asl     a
        sta     z:le2
        sec                             ; e2 >= dy: x step
        sbc     z:ddy
        bmi     :+
        lda     z:lerr
        clc
        adc     z:ddy
        sta     z:lerr
        lda     z:ax
        clc
        adc     z:lsx
        sta     z:ax
:       lda     z:ddx                   ; e2 <= dx: y step
        sec
        sbc     z:le2
        bmi     @l
        lda     z:lerr
        clc
        adc     z:ddx
        sta     z:lerr
        lda     z:ay
        clc
        adc     z:lsy
        sta     z:ay
        bra     @l
@out:   rts

; A = row (0-199) -> A = 320 A (clobbers only A)
mul320: sta     z:mt
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        sta     z:mt2
        lda     z:mt
        xba
        clc
        adc     z:mt2
        rts

; ---------------------------------------------------------------- flood fill
; at (fx, fy) with col -> C set: nothing changed (the same colour)
flood:  lda     z:fy
        jsr     mul320
        clc
        adc     z:fx
        tay
        lda     [cp],y
        and     #$00FF
        sta     z:ftgt
        cmp     z:col
        bne     :+
        sec
        rts
:       stz     z:stk
        stz     z:fovf
        lda     z:fx
        ldx     z:fy
        jsr     fpush
@next:  ldy     z:stk
        bne     @pop
        lda     z:fovf                  ; seeds were dropped: find them again
        bne     :+
        clc
        rts
:       stz     z:fovf
        jsr     rescan
        bra     @next
@pop:   dey
        dey
        lda     [sp],y
        sta     z:fy
        dey
        dey
        lda     [sp],y
        sta     z:fx
        sty     z:stk
        lda     z:fy
        jsr     mul320
        sta     z:frow
        clc
        adc     #CW - 1
        sta     z:frend
        lda     z:frow
        clc
        adc     z:fx
        sta     z:fs
        tay
        sep     #$20
        .a8
        lda     z:ftgt
        cmp     [cp],y
        bne     @nx8
@lft:   cpy     z:frow                  ; extend left
        beq     :+
        dey
        cmp     [cp],y
        beq     @lft
        iny
:       sty     z:fl
        ldy     z:fs
@rgt:   cpy     z:frend                 ; extend right
        beq     :+
        iny
        cmp     [cp],y
        beq     @rgt
        dey
:       sty     z:fr
        lda     z:col                   ; fill the span
        ldy     z:fl
:       sta     [cp],y
        cpy     z:fr
        beq     :+
        iny
        bra     :-
:       rep     #$20
        .a16
        lda     z:fy                    ; the row above
        beq     :+
        dec     a
        sta     z:sy
        lda     z:frow
        sec
        sbc     #CW
        jsr     fscan
:       lda     z:fy                    ; the row below
        cmp     #CH - 1
        jcs     @next
        inc     a
        sta     z:sy
        lda     z:frow
        clc
        adc     #CW
        jsr     fscan
        jmp     @next
@nx8:   rep     #$20
        .a16
        jmp     @next

; push one seed per run of target pixels in row sy (starting at offset A) under fl..fr
fscan:  sta     z:srow
        lda     z:fl
        sec
        sbc     z:frow
        clc
        adc     z:srow
        tay
        lda     z:fr
        sec
        sbc     z:frow
        clc
        adc     z:srow
        sta     z:se
        sep     #$20
        .a8
        stz     z:frun
@s:     lda     [cp],y
        cmp     z:ftgt
        bne     @no
        lda     z:frun
        bne     @adv
        inc     z:frun
        rep     #$20
        .a16
        tya
        sec
        sbc     z:srow
        ldx     z:sy
        jsr     fpush
        sep     #$20
        .a8
        bra     @adv
@no:    stz     z:frun
@adv:   cpy     z:se
        beq     :+
        iny
        bra     @s
:       rep     #$20
        .a16
        rts

; push the seed (A = x, X = y); keeps Y. A full stack drops it (fovf = 1).
fpush:  phy
        ldy     z:stk
        cpy     #STKMAX + 1
        bcs     @ovf
        sta     [sp],y
        iny
        iny
        txa
        sta     [sp],y
        iny
        iny
        sty     z:stk
        ply
        rts
@ovf:   lda     #1
        sta     z:fovf
        ply
        rts

; push every target pixel next to a pixel this fill changed (canvas = col, copy = ftgt)
rescan: stz     z:fy
        ldy     #0
@row:   stz     z:fx
@px:    lda     [cp],y
        and     #$00FF
        cmp     z:ftgt
        bne     @nx
        lda     z:fx                    ; left
        beq     :+
        dey
        jsr     @filled
        iny
        bcs     @push
:       lda     z:fx                    ; right
        cmp     #CW - 1
        beq     :+
        iny
        jsr     @filled
        dey
        bcs     @push
:       lda     z:fy                    ; above
        beq     :+
        tya
        sec
        sbc     #CW
        tay
        jsr     @filled
        php
        tya
        clc
        adc     #CW
        tay
        plp
        bcs     @push
:       lda     z:fy                    ; below
        cmp     #CH - 1
        beq     @nx
        tya
        clc
        adc     #CW
        tay
        jsr     @filled
        php
        tya
        sec
        sbc     #CW
        tay
        plp
        bcc     @nx
@push:  lda     z:fx
        ldx     z:fy
        jsr     fpush
@nx:    iny
        inc     z:fx
        lda     z:fx
        cmp     #CW
        bne     @px
        inc     z:fy
        lda     z:fy
        cmp     #CH
        bne     @row
        rts
@filled:
        lda     [cp],y
        and     #$00FF
        cmp     z:col
        bne     :+
        lda     [up],y
        and     #$00FF
        cmp     z:ftgt
        bne     :+
        sec
        rts
:       clc
        rts

; ---------------------------------------------------------------- the canvas
; the canvas before a change -> the undo copy
snap:   lda     cbank
        sta     z:mvs
        lda     ubank
        sta     z:mvd
        ldx     #0
        ldy     #0
        lda     #CW * CH - 1
        jsr     bcopy
        lda     #1
        sta     canundo
        rts

; the whole canvas in colour A
clearc: sep     #$20
        .a8
        sta     [cp]
        rep     #$20
        .a16
        lda     cbank
        sta     z:mvs
        sta     z:mvd
        ldx     #0
        ldy     #1
        lda     #CW * CH - 2
        ; fall through
; copy A + 1 bytes from bank mvs offset X to bank mvd offset Y (MVN, upwards)
bcopy:  pha
        sep     #$20
        .a8
        lda     z:mvs
        sta     mvsrc
        lda     z:mvd
        sta     mvdst
        rep     #$20
        .a16
        pla
        jmp     mvstub

; show the whole canvas
showall:
        stz     z:qx0
        stz     z:qy0
        lda     #CW - 1
        sta     z:qx1
        lda     #CH - 1
        sta     z:qy1
        ; fall through
; show the canvas rectangle qx0, qy0 - qx1, qy1 (inside) from the bank
blitq:  lda     #WD_SBLIT | (<CW << 8)
        sta     blk
        lda     #>CW                    ; stride high byte, font 0
        sta     blk+2
        jsr     qgeom
        lda     z:qy0
        jsr     mul320
        clc
        adc     z:qx0
        sta     blk+12
        lda     cbank
        sta     blk+14
        jmp     wd

; blk's x, y, w, h = the canvas rectangle qx0 .. qy1 in the window
qgeom:  lda     z:qx0
        clc
        adc     #CX
        sta     blk+4
        lda     z:qy0
        clc
        adc     #CY
        sta     blk+6
        lda     z:qx1
        sec
        sbc     z:qx0
        inc     a
        sta     blk+8
        lda     z:qy1
        sec
        sbc     z:qy0
        inc     a
        sta     blk+10
        rts

wd:     lda     win
        ptr     blk
        sys     SYS_WDRAW
        rts

; ---------------------------------------------------------------- the window
drawall:
        jsr     uwin
        lda     #CX - 1                 ; the frames of the canvas and the palette
        sta     z:ui_x
        lda     #CY - 1
        sta     z:ui_y
        lda     #CW + 2
        sta     z:ui_w
        lda     #CH + 2
        sta     z:ui_h
        lda     #WD_FRAME | (C_DARK << 8)
        jsr     ui_rect
        lda     #PALY - 1
        sta     z:ui_y
        lda     #60 + 2
        sta     z:ui_h
        lda     #WD_FRAME | (C_DARK << 8)
        jsr     ui_rect
        stz     z:t6                    ; the palette
:       lda     z:t6
        jsr     cellrect
        lda     z:t6
        xba
        ora     #WD_FILL
        jsr     ui_rect
        inc     z:t6
        lda     z:t6
        cmp     #256
        bcc     :-
        jsr     markfg
        jsr     drawsw
        stz     z:t6                    ; the tools
:       lda     z:t6
        jsr     drawtool
        inc     z:t6
        lda     z:t6
        cmp     #NTOOL
        bcc     :-
        jmp     showall

uwin:   lda     win
        sta     z:ui_win
        rts

; tool button A (pressed if it is the current tool)
drawtool:
        sta     z:t5
        jsr     uwin
        lda     #TBX
        sta     z:ui_x
        lda     z:t5
        ldx     #TBSTEP
        jsr     mulax
        clc
        adc     #TBY
        sta     z:ui_y
        lda     #TBS
        sta     z:ui_w
        sta     z:ui_h
        lda     #WD_FRAME | (C_DARK << 8)
        jsr     ui_rect
        inc     z:ui_x
        inc     z:ui_y
        lda     #TBS - 2
        sta     z:ui_w
        sta     z:ui_h
        ldx     #0                      ; 0 raised, 1 sunken
        lda     z:t5
        cmp     tool
        bne     :+
        inx
:       stx     z:t4
        lda     #WD_FILL | (C_BODY << 8)
        cpx     #0
        beq     :+
        lda     #WD_FILL | (C_LIGHT << 8)
:       jsr     ui_rect
        lda     z:t4
        jsr     ui_bevel
        lda     #WD_KBLIT | (KEY << 8)  ; the icon (pressed: one pixel down right)
        sta     blk
        lda     #KEY
        sta     blk+2
        lda     z:ui_x
        clc
        adc     #3
        adc     z:t4
        sta     blk+4
        lda     z:ui_y
        clc
        adc     #3
        adc     z:t4
        sta     blk+6
        lda     #16
        sta     blk+8
        sta     blk+10
        lda     z:t5
        xba                             ; 256 bytes an icon
        clc
        adc     #.loword(icons)
        sta     blk+12
        lda     #^icons
        sta     blk+14
        jmp     wd

; A * X (small) -> A
mulax:  sta     z:t7
        lda     #0
        cpx     #0
        beq     :++
:       clc
        adc     z:t7
        dex
        bne     :-
:       rts

; the foreground / background swatches
drawsw: jsr     uwin
        lda     #SWX + 8
        sta     z:ui_x
        lda     #SWY + 8
        sta     z:ui_y
        lda     bg
        jsr     @one
        lda     #SWX
        sta     z:ui_x
        lda     #SWY
        sta     z:ui_y
        lda     fg
@one:   sta     z:t5
        lda     #SWS
        sta     z:ui_w
        sta     z:ui_h
        lda     #WD_FRAME | (C_BLACK << 8)
        jsr     ui_rect
        jsr     shrink
        lda     #WD_FRAME | (C_WHITE << 8)
        jsr     ui_rect
        jsr     shrink
        lda     z:t5
        xba
        ora     #WD_FILL
        jmp     ui_rect

shrink: inc     z:ui_x
        inc     z:ui_y
        dec     z:ui_w
        dec     z:ui_w
        dec     z:ui_h
        dec     z:ui_h
        rts

; the palette cell of colour A -> ui_x, ui_y, ui_w, ui_h
cellrect:
        and     #$00FF
        cmp     #16
        bcs     :+
        ldx     #20                     ; UI colours: 20 x 12
        jsr     mulax
        clc
        adc     #PALX
        sta     z:ui_x
        lda     #PALY
        sta     z:ui_y
        lda     #20
        sta     z:ui_w
        lda     #12
        sta     z:ui_h
        rts
:       ldx     #8
        stx     z:ui_w
        stx     z:ui_h
        cmp     #232
        bcc     :+
        sec                             ; greys: columns 36-39, 4 a row
        sbc     #232
        pha
        and     #3
        clc
        adc     #36
        sta     z:t7
        pla
        lsr     a
        lsr     a
        bra     @xy
:       sec                             ; the cube: column 6 r + b, row g
        sbc     #16
        ldx     #0
:       cmp     #36
        bcc     :+
        sbc     #36
        inx
        bra     :-
:       stx     z:t3                    ; r
        ldx     #0
:       cmp     #6
        bcc     :+
        sbc     #6
        inx
        bra     :-
:       sta     z:t7                    ; b
        lda     z:t3
        asl     a
        adc     z:t3
        asl     a
        adc     z:t7
        sta     z:t7                    ; column
        txa                             ; row g
@xy:    asl     a
        asl     a
        asl     a
        clc
        adc     #PALY2
        sta     z:ui_y
        lda     z:t7
        asl     a
        asl     a
        asl     a
        adc     #PALX
        sta     z:ui_x
        rts

; the palette at (ex, ey) (inside) -> A = colour
palhit: lda     z:ex
        sec
        sbc     #PALX
        sta     z:t3
        lda     z:ey
        sec
        sbc     #PALY
        cmp     #12
        bcs     @rows
        lda     z:t3                    ; the UI row: 20 pixels a colour
        ldx     #20
        jsr     divax
        txa
        rts
@rows:  sbc     #12                     ; (C set) row 0-5
        lsr     a
        lsr     a
        lsr     a
        sta     z:t4
        lda     z:t3
        lsr     a
        lsr     a
        lsr     a                       ; column 0-39
        cmp     #36
        bcc     @cube
        sbc     #36                     ; greys: 4 a row
        sta     z:t3
        lda     z:t4
        asl     a
        asl     a
        adc     z:t3
        adc     #232
        rts
@cube:  ldx     #6                      ; r = column / 6, b = column mod 6
        jsr     divax
        sta     z:t3                    ; b
        txa
        ldx     #36
        jsr     mulax
        clc
        adc     z:t3
        sta     z:t3
        lda     z:t4                    ; + 6 g
        asl     a
        adc     z:t4
        asl     a
        adc     z:t3
        adc     #16
        rts

; A / X (A small, X > 0) -> X = quotient, A = remainder
divax:  stx     z:t7
        ldx     #0
:       cmp     z:t7
        bcc     :+
        sbc     z:t7
        inx
        bra     :-
:       rts

; mark the foreground in the palette
markfg: jsr     uwin
        lda     fg
        jsr     cellrect
        lda     #WD_FRAME | (C_BLACK << 8)
        jsr     ui_rect
        jsr     shrink
        lda     #WD_FRAME | (C_WHITE << 8)
        jmp     ui_rect

; A = the new foreground colour
setfg:  and     #$00FF
        cmp     fg
        bne     :+
        rts
:
        pha
        jsr     uwin                    ; the old one's cell unmarked
        lda     fg
        jsr     cellrect
        lda     fg
        xba
        ora     #WD_FILL
        jsr     ui_rect
        pla
        sta     fg
        jsr     markfg
        jmp     drawsw

; ---------------------------------------------------------------- files
; read fpath into the canvas (a missing file: a new picture of that name)
load:   lda     #1
        jsr     clearc
        stz     emod
        stz     canundo
        ptr     fpath
        lda     #O_READ
        sys     SYS_OPEN
        bcc     :+
        cmp     #$44                    ; not there: a new file of that name
        beq     @new
        ldx     #.loword(m_cantopen)
        jsr     errbox
        stz     fpath
@new:   rts
:       sta     fh
        lda     #12                     ; the header
        ldx     #.loword(hdr)
        ldy     #^hdr
        jsr     fread
        jcs     @err
        cmp     #12
        jne     @bad
        ldx     #6
:       lda     hdr,x
        cmp     pichdr,x
        jne     @bad
        dex
        dex
        bpl     :-
        lda     hdr+8
        jeq     @bad
        cmp     #32769
        jcs     @bad
        sta     z:pw
        lda     hdr+10
        jeq     @bad
        cmp     #CH
        bcc     :+
        lda     #CH
:       sta     z:ph                    ; the rows kept
        lda     #32768                  ; rows per piece: 32768 / width
        ldx     #0
:       cmp     z:pw
        bcc     :+
        sbc     z:pw
        inx
        bra     :-
:       stx     z:pn
        stz     z:prow
@piece: lda     z:ph                    ; k = min(pn, rows left)
        sec
        sbc     z:prow
        beq     @close
        cmp     z:pn
        bcc     :+
        lda     z:pn
:       sta     z:pk
        tax
        lda     z:pw
        jsr     mulax                   ; (k * width <= 32768)
        sta     z:pb
        ldx     #0
        ldy     sbank
        jsr     fread
        jcs     @err
        cmp     z:pb
        beq     :+
        ldx     z:pw                    ; short: the whole rows that came, then stop
        jsr     divax
        stx     z:pk
        jsr     @copy
        bra     @close
:       jsr     @copy
        bra     @piece
@close: lda     fh
        sys     SYS_CLOSE
        rts
@bad:   lda     fh
        sys     SYS_CLOSE
        lda     #1
        jsr     clearc
        ldx     #.loword(m_notpic)
        lda     #0
        jsr     errbox
        stz     fpath
        rts
@err:   pha
        lda     fh
        sys     SYS_CLOSE
        lda     #1
        jsr     clearc
        pla
        ldx     #.loword(m_cantread)
        jsr     errbox
        stz     fpath
        rts
; pk rows from SB to the canvas from row prow on: min(width, 320) bytes each
@copy:  stz     z:poff
@cr:    lda     z:pk
        beq     @cout
        lda     z:prow
        jsr     mul320
        tay
        lda     z:pw
        cmp     #CW
        bcc     :+
        lda     #CW
:       dec     a
        ldx     sbank
        stx     z:mvs
        ldx     cbank
        stx     z:mvd
        ldx     z:poff
        jsr     bcopy
        lda     z:poff
        clc
        adc     z:pw
        sta     z:poff
        inc     z:prow
        dec     z:pk
        bra     @cr
@cout:  rts

; read A bytes from fh into X (offset), Y (bank) -> A = bytes read, C set: error
fread:  jsr     ioblk
        sys     SYS_READ
        rts
; write A bytes ... -> C set: error (a short write: $47, the card is full)
fwrite: sta     z:t6
        jsr     ioblk
        sys     SYS_WRITE
        bcs     @out
        cmp     z:t6
        bne     :+
        clc
        rts
:       lda     #$47
        sec
@out:   rts
ioblk:  stx     z:t7
        sta     rblk+4
        lda     fh
        sta     rblk
        lda     z:t7
        sta     rblk+1
        tya
        sep     #$20
        .a8
        sta     rblk+3
        rep     #$20
        .a16
        ptr     rblk
        rts

; write the canvas to fpath -> C set: failed (said so)
save:   ptr     fpath
        lda     #O_CREATE
        sys     SYS_OPEN
        bcs     @err2
        sta     fh
        lda     #12
        ldx     #.loword(pichdr)
        ldy     #^pichdr
        jsr     fwrite
        bcs     @err
        stz     z:poff
:       lda     #CHUNK
        ldx     z:poff
        ldy     cbank
        jsr     fwrite
        bcs     @err
        lda     z:poff
        clc
        adc     #CHUNK
        sta     z:poff
        cmp     #CW * CH
        bcc     :-
        lda     fh
        sys     SYS_CLOSE
        bcs     @err2
        stz     emod
        jsr     settitle
        clc
        rts
@err:   pha
        lda     fh
        sys     SYS_CLOSE
        pla
@err2:  ldx     #.loword(m_cantsave)
        jsr     errbox
        sec
        rts

; File > Save: to its path, or Save as for a new picture -> C set: not saved
do_save:
        lda     fpath
        and     #$00FF
        beq     do_saveas
        jmp     save
do_saveas:
        jsr     suggest
        lda     #1
        ldx     #.loword(dlgbuf)
        ldy     #.loword(t_saveas)
        jsr     ui_filedlg
        bcc     :+
        rts
:       ldx     #.loword(e_pic)
        jsr     addext
        ldx     #.loword(dlgbuf)
        ldy     #.loword(fpath)
        jsr     ui_strcpy
        jsr     save
        php
        jsr     settitle
        plp
        rts

; File > Save as BMP: the picture with the name's extension .BMP
do_bmp: jsr     suggest
        ldx     #.loword(dlgbuf)        ; (its extension dropped)
        jsr     extpos
        bcs     :+
        lda     #0
        sta     dlgbuf,x
:       ldx     #.loword(e_bmp)
        jsr     addext
        lda     #1
        ldx     #.loword(dlgbuf)
        ldy     #.loword(t_savebmp)
        jsr     ui_filedlg
        bcc     :+
        rts
:       ldx     #.loword(e_bmp)
        jsr     addext
        lda     #^bmphdr                ; the headers
        sta     z:mvs
        lda     sbank
        sta     z:mvd
        ldx     #.loword(bmphdr)
        ldy     #0
        lda     #54 - 1
        jsr     bcopy
        stz     z:fp                    ; the colour table: B, G, R, 0
        lda     sbank
        sta     z:fp+2
        ldy     #54
        ldx     #0
:       lda     uipal,x                 ; the UI colours
        sta     z:t0
        lda     uipal+1,x
        sta     z:t1
        lda     uipal+2,x
        sta     z:t2
        jsr     @put
        inx
        inx
        inx
        cpx     #48
        bcc     :-
        stz     z:t3                    ; the cube
@r:     stz     z:t4
@g:     stz     z:t5
@b:     lda     z:t3
        jsr     @x51
        sta     z:t0
        lda     z:t4
        jsr     @x51
        sta     z:t1
        lda     z:t5
        jsr     @x51
        sta     z:t2
        jsr     @put
        inc     z:t5
        lda     z:t5
        cmp     #6
        bcc     @b
        inc     z:t4
        lda     z:t4
        cmp     #6
        bcc     @g
        inc     z:t3
        lda     z:t3
        cmp     #6
        bcc     @r
        lda     #8                      ; the greys
:       sta     z:t0
        sta     z:t1
        sta     z:t2
        jsr     @put
        lda     z:t0
        clc
        adc     #10
        cmp     #248
        bcc     :-
        lda     cbank                   ; the rows, bottom up
        sta     z:mvs
        lda     sbank
        sta     z:mvd
        stz     z:prow
:       lda     #CH - 1
        sec
        sbc     z:prow
        jsr     mul320
        clc
        adc     #1078
        tay
        lda     z:prow
        jsr     mul320
        tax
        lda     #CW - 1
        jsr     bcopy
        inc     z:prow
        lda     z:prow
        cmp     #CH
        bcc     :-
        ptr     dlgbuf                  ; write
        lda     #O_CREATE
        sys     SYS_OPEN
        bcs     @err2
        sta     fh
        stz     z:poff
@w:     lda     #1078 + CW * CH         ; 8 KB pieces
        sec
        sbc     z:poff
        beq     @end
        cmp     #8192
        bcc     :+
        lda     #8192
:       sta     z:pb
        ldx     z:poff
        ldy     sbank
        jsr     fwrite
        bcs     @err
        lda     z:poff
        clc
        adc     z:pb
        sta     z:poff
        bra     @w
@end:   lda     fh
        sys     SYS_CLOSE
        bcs     @err2
        rts
@err:   pha
        lda     fh
        sys     SYS_CLOSE
        pla
@err2:  ldx     #.loword(m_cantsave)
        ldy     #.loword(dlgbuf)
        jmp     errbox2
@x51:   sta     z:t7                    ; A * 51
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     z:t7
        sta     z:t7
        asl     a
        adc     z:t7
        rts
@put:   sep     #$20                    ; t2 (blue), t1, t0 (red), 0 at [fp], y
        .a8
        lda     z:t2
        sta     [fp],y
        iny
        lda     z:t1
        sta     [fp],y
        iny
        lda     z:t0
        sta     [fp],y
        iny
        lda     #0
        sta     [fp],y
        iny
        rep     #$20
        .a16
        rts

; the picture's name (or PICTURE.PIC) -> dlgbuf, the dialog's suggestion
suggest:
        ldx     #.loword(t_defname)
        lda     fpath
        and     #$00FF
        beq     :+
        ldx     #.loword(fpath)
        jsr     basename
:       ldy     #.loword(dlgbuf)
        jmp     ui_strcpy

; X = path: the offset of its name's '.' -> X; C set: none
extpos: jsr     basename
:       lda     a:0,x
        and     #$00FF
        beq     :+
        cmp     #'.'
        beq     @yes
        inx
        bra     :-
:       sec
        rts
@yes:   txa
        sec
        sbc     #.loword(dlgbuf)
        tax
        clc
        rts

; dlgbuf without an extension: append the one at X
addext: phx
        ldx     #.loword(dlgbuf)
        jsr     extpos
        plx
        bcc     @out
        phx
        ldx     #.loword(dlgbuf)
        jsr     ui_strlen
        plx
        cmp     #122
        bcs     @out
        clc
        adc     #.loword(dlgbuf)
        tay
        jmp     ui_strcpy
@out:   rts

; unsaved changes: ask (Save / Discard / Cancel) -> C set: stop (cancelled, or not saved)
confirm:
        lda     emod
        bne     :+
        clc
        rts
:       ldx     #.loword(m_save1)
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        ldx     #.loword(fpath)
        jsr     basename
        jsr     append
        ldx     #.loword(m_save2)
        jsr     append
        ldx     #.loword(al_save)
        jsr     ui_alert
        cmp     #1
        beq     @go
        cmp     #0
        bne     @stop
        jmp     do_save
@go:    clc
        rts
@stop:  sec
        rts

; an alert: message X, then the name of fpath (errbox2: of path Y), error code A (0: none)
errbox: ldy     #.loword(fpath)
errbox2:
        sta     z:t5
        sty     z:t6
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        ldx     z:t6
        jsr     basename
        jsr     append
        lda     z:t5
        beq     @show
        ldx     #.loword(m_code)
        jsr     append
        lda     z:t5                    ; the code in hex
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     @hex
        lda     z:t5
        jsr     @hex
        ldx     #.loword(m_rpar)
        jsr     append
@show:  ldx     #.loword(al_err)
        jsr     ui_alert
        rts
@hex:   and     #$000F
        cmp     #10
        bcc     :+
        adc     #6
:       adc     #'0'
        sta     onech
        ldx     #.loword(onech)
        ; fall through
; append string X to the string at msgbuf
append: phx
        ldx     #.loword(msgbuf)
        jsr     ui_strlen
        clc
        adc     #.loword(msgbuf)
        tay
        plx
        jmp     ui_strcpy

; X = path -> X = its name (after the last '/'), "(new)" for an empty path
basename:
        lda     a:0,x
        and     #$00FF
        bne     :+
        ldx     #.loword(t_newname)
        rts
:       txy
:       lda     a:0,x
        and     #$00FF
        beq     :++
        cmp     #'/'
        bne     :+
        txy
        iny
:       inx
        bra     :--
:       tyx
        rts

; the window title: "Paint: name" (and " *" when changed)
settitle:
        ldx     #.loword(t_paint)
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        ldx     #.loword(fpath)
        jsr     basename
        ldy     #.loword(msgbuf+7)
        jsr     ui_strcpy
        cmp     #23                     ; cut long names
        bcc     :+
        lda     #'.' | ('.' << 8)
        sta     msgbuf+7+20
        stz     msgbuf+7+22
:       lda     emod
        beq     :+
        ldx     #.loword(t_star)
        jsr     append
:       lda     win
        ptr     msgbuf
        sys     SYS_WTITLE
        rts

setmod: lda     emod
        bne     :+
        inc     emod
        jsr     settitle
:       rts

; ---------------------------------------------------------------- data
; a 16-pixel icon row: # black, + dark, m mid, l light, w white, y yellow, o orange,
; r red, b blue, . transparent
.macro  irow    pix
        .repeat .strlen(pix), I
        .if .strat(pix, I) = '#'
        .byte   C_BLACK
        .elseif .strat(pix, I) = '+'
        .byte   C_DARK
        .elseif .strat(pix, I) = 'm'
        .byte   C_MID
        .elseif .strat(pix, I) = 'l'
        .byte   C_LIGHT
        .elseif .strat(pix, I) = 'w'
        .byte   C_WHITE
        .elseif .strat(pix, I) = 'y'
        .byte   C_YELLOW
        .elseif .strat(pix, I) = 'o'
        .byte   C_ORANGE
        .elseif .strat(pix, I) = 'r'
        .byte   C_RED
        .elseif .strat(pix, I) = 'b'
        .byte   C_SELECT
        .else
        .byte   KEY
        .endif
        .endrepeat
.endmacro

        .segment "RODATA"
icons:  ; pencil
        irow    "................"
        irow    "............##.."
        irow    "...........#rr#."
        irow    "..........#rrrr#"
        irow    ".........#m#rr#."
        irow    "........#mmm##.."
        irow    ".......#yyy#m#.."
        irow    "......#yyyyo#..."
        irow    ".....#yyyyo#...."
        irow    "....#yyyyo#....."
        irow    "...#lyyyo#......"
        irow    "...#llyo#......."
        irow    "..#llll#........"
        irow    "..##ll#........."
        irow    "..###..........."
        irow    "................"
        ; line
        irow    "................"
        irow    "................"
        irow    "............###."
        irow    "............###."
        irow    "...........##..."
        irow    "..........##...."
        irow    ".........##....."
        irow    "........##......"
        irow    ".......##......."
        irow    "......##........"
        irow    ".....##........."
        irow    "....##.........."
        irow    "..###..........."
        irow    "..###..........."
        irow    "................"
        irow    "................"
        ; rectangle
        irow    "................"
        irow    "................"
        irow    "................"
        irow    "..############.."
        irow    "..#..........#.."
        irow    "..#..........#.."
        irow    "..#..........#.."
        irow    "..#..........#.."
        irow    "..#..........#.."
        irow    "..#..........#.."
        irow    "..#..........#.."
        irow    "..#..........#.."
        irow    "..############.."
        irow    "................"
        irow    "................"
        irow    "................"
        ; filled rectangle
        irow    "................"
        irow    "................"
        irow    "................"
        irow    "..############.."
        irow    "..#bbbbbbbbbb#.."
        irow    "..#bbbbbbbbbb#.."
        irow    "..#bbbbbbbbbb#.."
        irow    "..#bbbbbbbbbb#.."
        irow    "..#bbbbbbbbbb#.."
        irow    "..#bbbbbbbbbb#.."
        irow    "..#bbbbbbbbbb#.."
        irow    "..#bbbbbbbbbb#.."
        irow    "..############.."
        irow    "................"
        irow    "................"
        irow    "................"
        ; flood fill
        irow    "................"
        irow    "......###......."
        irow    ".....#...#......"
        irow    ".....#..###....."
        irow    "....##.#mww#...."
        irow    "...#w#wwwwmw#..."
        irow    "..#wwwwwwwwwm#.."
        irow    ".#wwwwwwwwwwm#b."
        irow    "..#wwwwwwwwm#bb."
        irow    "...#wwwwwwm#.bb."
        irow    "....#wwwwm#..bb."
        irow    ".....#wwm#..bbbb"
        irow    "......#m#...bbbb"
        irow    ".......#.....bb."
        irow    "................"
        irow    "................"
        ; eyedropper
        irow    "................"
        irow    "............##.."
        irow    "...........####."
        irow    "...........####."
        irow    ".........#######"
        irow    "..........####.."
        irow    ".........#.##..."
        irow    "........#w#.#..."
        irow    ".......#w#......"
        irow    "......#w#......."
        irow    ".....#bb#......."
        irow    "....#bb#........"
        irow    "...#bb#........."
        irow    "...##..........."
        irow    "..#............."
        irow    "................"

pichdr: .byte   "H816PIC1"
        .word   CW, CH
bmphdr: .byte   "BM"                    ; BITMAPFILEHEADER
        .dword  1078 + CW * CH, 0, 1078
        .dword  40, CW, CH              ; BITMAPINFOHEADER
        .word   1, 8
        .dword  0, CW * CH, 2835, 2835, 256, 0
uipal:  .byte   0, 0, 0,  255, 255, 255,  36, 92, 112,  46, 104, 124 ; (tools/mkpalette.py)
        .byte   28, 60, 132,  132, 138, 148,  228, 226, 216,  76, 80, 90
        .byte   160, 164, 172,  204, 206, 210,  52, 100, 204,  200, 52, 44
        .byte   240, 200, 64,  60, 156, 80,  232, 128, 40,  36, 40, 48
toolkeys: .byte "plrfbi"
menus:  .byte   "File", 0, "New", 0, "Open...", 0, "Save", 0, "Save as...", 0
        .byte   "Save as BMP...", 0, "-", 0, "Close", 0, 0
        .byte   "Edit", 0, "Undo", 0, "Clear to background", 0, 0, 0
        .res    128 - (* - menus)
mtab:   .addr   m_file, m_edit
ftab:   .addr   m_new, m_open, m_save, m_saveas, m_bmp, loop, m_close
etab:   .addr   m_undo, m_clear
noctls: .addr   0
t_paint: .byte  "Paint: ", 0
t_star: .byte   " *", 0
t_newname: .byte "(new)", 0
t_defname: .byte "PICTURE.PIC", 0
t_open: .byte   "Open", 0
t_saveas: .byte "Save as", 0
t_savebmp: .byte "Save as BMP", 0
t_title: .byte  "Paint", 0
e_pic:  .byte   ".PIC", 0
e_bmp:  .byte   ".BMP", 0
m_save1: .byte  "Save the changes to ", 0
m_save2: .byte  "?", 10, "Changes that are not saved will be lost.", 0
m_cantopen: .byte "Cannot open ", 0
m_cantread: .byte "Cannot read ", 0
m_cantsave: .byte "Cannot save ", 0
m_notpic: .byte "Not a Paint picture: ", 0
m_code: .byte   10, "(error $", 0
m_rpar: .byte   ")", 0
b_save: .byte   "Save", 0
b_discard: .byte "Discard", 0
b_cancel: .byte "Cancel", 0
b_ok:   .byte   "OK", 0
al_save: .word  2, t_title, msgbuf, b_save, b_discard, b_cancel
al_err: .word   3, t_title, msgbuf, b_ok, 0, 0

        .segment "DATA"
wopen:  .word   60, 40, WINW, WINH
        .faraddr t_title
        .byte   WF_HOVER                ; (motion without a button: the crosshair)
tool:   .word   T_PENCIL
opbtn:  .word   1                       ; the button that draws (1 left, 2 right)
dcol:   .word   0                       ; and its colour
pshape: .word   0                       ; the pointer shape set (SYS_WPTR)
fg:     .word   C_BLACK
bg:     .word   C_WHITE
; MVN with its banks patched in (bcopy): A + 1 bytes from X to Y
mvstub: phb
        .byte   $54                     ; MVN dst, src
mvdst:  .byte   0
mvsrc:  .byte   0
        plb
        rts

        .segment "BSS"
argl:   .res    2
argx:   .res    2
wsown:  .res    2
win:    .res    2
cbank:  .res    2
ubank:  .res    2
sbank:  .res    2
op:     .res    2                       ; the drag in progress: tool + 1 (0 none)
pvon:   .res    2                       ; a shape preview is shown
emod:   .res    2
canundo: .res   2
key:    .res    2
fh:     .res    2
onech:  .res    2
blk:    .res    16
rblk:   .res    6
hdr:    .res    12
fpath:  .res    130
abuf:   .res    130
dlgbuf: .res    130
msgbuf: .res    200

        .segment "ZEROPAGE"
cp:     .res    4                       ; the canvas
up:     .res    4                       ; the undo copy
sp:     .res    4                       ; the seed stack / file buffer
fp:     .res    4
t0:     .res    2
t1:     .res    2
t2:     .res    2
t3:     .res    2
t4:     .res    2
t5:     .res    2
t6:     .res    2
t7:     .res    2
o1:     .res    2
mt:     .res    2
mt2:    .res    2
mvs:    .res    2
mvd:    .res    2
col:    .res    2
ex:     .res    2                       ; a press in the content
ey:     .res    2
px:     .res    2                       ; the pointer on the canvas (signed)
py:     .res    2
lx:     .res    2                       ; the pencil's last point
ly:     .res    2
cx0:    .res    2                       ; a shape: from (cx0, cy0) to (cx1, cy1)
cy0:    .res    2
cx1:    .res    2
cy1:    .res    2
pcx:    .res    2                       ; the end point of the preview shown
pcy:    .res    2
qx0:    .res    2                       ; a rectangle of the canvas
qy0:    .res    2
qx1:    .res    2
qy1:    .res    2
vx0:    .res    2                       ; the preview's rectangle
vy0:    .res    2
vx1:    .res    2
vy1:    .res    2
ax:     .res    2                       ; line
ay:     .res    2
ddx:    .res    2
ddy:    .res    2
lsx:    .res    2
lsy:    .res    2
lerr:   .res    2
le2:    .res    2
fx:     .res    2                       ; flood fill
fy:     .res    2
ftgt:   .res    2
stk:    .res    2
fovf:   .res    2
frow:   .res    2
frend:  .res    2
fs:     .res    2
fl:     .res    2
fr:     .res    2
sy:     .res    2
srow:   .res    2
se:     .res    2
frun:   .res    2
pw:     .res    2                       ; loading
ph:     .res    2
pn:     .res    2
pk:     .res    2
pb:     .res    2
prow:   .res    2
poff:   .res    2
