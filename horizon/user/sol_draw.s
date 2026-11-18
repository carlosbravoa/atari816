; sol_draw.s - Solitaire's drawing (included by solitair.s).
;
; Card images: made once at the start by the CPU from the art (sol_art.s) into two banks:
; 35 x 48 bytes each (CW x CH), 38 to a bank: 0-51 the faces, 52-54 the backs, then the
; empty places (I_SLOT plain, I_SLOTA a foundation, I_RING the empty stock, I_SLOTK an empty
; Klondike column). Pixels of colour KEY are clear (the rounded corners, the inside of the
; empty places).
;
; The table: an off-screen copy of the window's table area (SW x TH, the scene) in two
; banks (rows 0-149, 150-299; rowlo gives each row's offset). A pile is drawn there (its
; area cleared to the table colour, then its cards), then that area is copied to the
; window with WD_SBLIT (`show`). So every change reaches the screen as whole rectangles of
; finished pixels and nothing flickers.
;
; Dragging: the cards carried are drawn once into dimg (in the work bank); at each pointer
; position the program composes dimg over the scene under it into tmp (only the corners
; are clear) and blits that, then puts back from the scene the part of the old position
; the new one does not cover (`showminus`). The same machinery flies cards (a card sent
; home, the auto finish, a drag dropped where it may not go, the win).

CW      = 35
CH      = 48
SW      = 392                           ; the table: the window's content width
TH      = 300                           ;   and its height above the status line
STATY   = 300                           ; the status line
STATH   = 14
WH      = STATY + STATH
HALF    = 150                           ; scene rows in the first bank
TY      = 8                             ; the top row of piles
TABY    = 66                            ; the tableau
KX0     = 28                            ; Klondike columns: x KX0 + c * KDX
KDX     = 50
FX0     = 21                            ; FreeCell
FDX     = 45
USTEP   = 13                            ; tableau: a face-up card's step, a face-down one's
DSTEP   = 4
MINSTEP = 6
WFAN    = 12                            ; the waste fan (draw 3)
IPB     = 38                            ; images in a bank
ISZ     = CW * CH
I_BACK  = 52
I_SLOT  = 55
I_SLOTA = 56
I_RING  = 57
I_SLOTK = 58
NIMG    = 59
KEY     = 231                           ; the clear colour of images
C_TABLE = 16 + 6 * 2 + 1                ; (0, 102, 51)
C_SLOTC = 16 + 36 + 6 * 3 + 2           ; (51, 153, 102): the empty places
C_STRIP = 16 + 6 * 1                    ; (0, 51, 0): the status line
C_CREAM = 16 + 36 * 5 + 6 * 5 + 4       ; the court cards' panel
C_EDGE  = C_SHADOW                      ; a card's outline
TMPOFS  = $4000                         ; the work bank: dimg at 0, tmp here
FLYOFS  = $8000                         ;   (the win: a card's image)

        .segment "CODE"

; ---------------------------------------------------------------- images
; A = image -> ip = its first byte (keeps nothing)
imgptr: ldx     ibank0
        cmp     #IPB
        bcc     :+
        sbc     #IPB
        ldx     ibank1
:       stx     z:ip+2
        sta     z:g0                    ; * 1680 = * (1024 + 512 + 128 + 16)
        asl     a
        asl     a
        asl     a
        asl     a
        sta     z:g1                    ; * 16
        asl     a
        asl     a
        asl     a
        clc
        adc     z:g1
        sta     z:g1                    ; * 144
        asl     a                       ; (* 288; we want 1536 more: * 512 + * 1024)
        lda     z:g0
        xba
        and     #$FF00                  ; * 256
        asl     a
        sta     z:g2                    ; * 512
        asl     a
        clc
        adc     z:g2                    ; * 1536
        adc     z:g1                    ; + * 144
        sta     z:ip
        rts

; all the images
mkimages:
        stz     z:g8                    ; the faces
@f:     lda     z:g8
        jsr     mkface
        inc     z:g8
        lda     z:g8
        cmp     #52
        bcc     @f
        lda     #0
        jsr     mkback
        lda     #1
        jsr     mkback
        lda     #2
        jsr     mkback
        lda     #I_SLOT                 ; the empty places
        jsr     mkslot
        lda     #I_SLOTA
        jsr     mkslot
        lda     #.loword(r_a)
        jsr     slotart
        lda     #I_RING
        jsr     mkslot
        lda     #.loword(a_ring)
        jsr     slotart
        lda     #I_SLOTK
        jsr     mkslot
        lda     #.loword(r_k)
        jmp     slotart

; an empty place: A = image: a rounded outline, clear inside
mkslot: jsr     imgptr
        lda     #KEY
        jsr     iclear
        lda     #C_SLOTC
        sta     z:g6
        jmp     ioutline
; the art A in the slot colour, centred
slotart:
        sta     z:ap
        lda     #C_SLOTC
        sta     z:ink
        lda     (ap)
        and     #$00FF
        eor     #$FFFF
        sec
        adc     #CW
        lsr     a
        sta     z:ax
        ldy     #1
        lda     (ap),y
        and     #$00FF
        eor     #$FFFF
        sec
        adc     #CH
        lsr     a
        sta     z:ay
        jmp     ipaint

; A = card: its face
mkface: sta     z:g7
        jsr     imgptr
        lda     #C_WHITE
        jsr     icard
        ldx     z:g7                    ; the ink: red or black
        lda     cred,x
        and     #$00FF
        beq     :+
        lda     #C_RED
        bra     :++
:       lda     #C_BLACK
:       sta     z:ink
        lda     crank,x
        and     #$00FF
        sta     z:g9                    ; rank
        asl     a                       ; the corner: rank, small suit
        tax
        lda     a_rank,x
        sta     z:ap
        lda     #3
        sta     z:ax
        lda     #3
        sta     z:ay
        jsr     ipaint
        jsr     @suit
        lda     a_small,x
        sta     z:ap
        lda     #25
        sta     z:ax
        lda     #4
        sta     z:ay
        jsr     ipaint
        lda     z:g9
        bne     :+
        jsr     @suit                   ; ace: the large suit
        lda     a_big,x
        sta     z:ap
        lda     #11
        sta     z:ax
        lda     #22
        sta     z:ay
        jmp     ipaint
:       cmp     #10
        bcs     @court
        dec     a                       ; 2-10: pips
        asl     a
        tax
        lda     pips,x
        sta     z:g6
        lda     (g6)
        and     #$00FF
        sta     z:g5                    ; count
        inc     z:g6
@pip:   jsr     @suit
        lda     a_small,x
        sta     z:ap
        lda     (g6)
        and     #$00FF
        sec
        sbc     #3
        sta     z:ax
        inc     z:g6
        lda     (g6)
        and     #$00FF
        sec
        sbc     #3
        sta     z:ay
        inc     z:g6
        jsr     ipaint
        dec     z:g5
        bne     @pip
        rts
@court: lda     #4                      ; J Q K: a panel, the headgear, the large suit
        sta     z:ax
        lda     #14
        sta     z:ay
        lda     #27
        sta     z:aw
        lda     #31
        sta     z:ah
        lda     z:ink
        jsr     irect
        inc     z:ax
        inc     z:ay
        dec     z:aw
        dec     z:aw
        dec     z:ah
        dec     z:ah
        lda     #C_CREAM
        jsr     irect
        lda     z:g9
        sec
        sbc     #10
        asl     a
        tax
        lda     a_head,x
        sta     z:ap
        lda     #12
        sta     z:ax
        lda     #17
        sta     z:ay
        jsr     ipaint
        jsr     @suit
        lda     a_big,x
        sta     z:ap
        lda     #11
        sta     z:ax
        lda     #29
        sta     z:ay
        jmp     ipaint
@suit:  ldx     z:g7                    ; X = suit * 2
        lda     csuit,x
        and     #$00FF
        asl     a
        tax
        rts

; A = 0-2: a back
mkback: sta     z:g7
        clc
        adc     #I_BACK
        jsr     imgptr
        lda     #C_WHITE
        jsr     icard
        lda     z:g7
        asl     a
        tax
        lda     backcol,x               ; dark | light << 8
        sta     z:g5
        lda     #2                      ; the pattern in x 3..31, y 3..44
        sta     z:ay
@row:   lda     #2
        sta     z:ax
@pix:   lda     z:g7
        bne     :+
        jsr     @lat
        bra     @put
:       cmp     #1
        bne     :+
        jsr     @dia
        bra     @put
:       jsr     @chk
@put:   tax                             ; 0 dark, 1 light
        lda     z:g5
        cpx     #0
        beq     :+
        xba
:       and     #$00FF
        jsr     ipix
        inc     z:ax
        lda     z:ax
        cmp     #CW - 2
        bcc     @pix
        inc     z:ay
        lda     z:ay
        cmp     #CH - 2
        bcc     @row
        rts
; blue: a lattice of diagonals 6 apart, and a frame
@lat:   jsr     @frame
        bcs     @one
        lda     z:ax
        clc
        adc     z:ay
        jsr     mod6
        beq     @one
        lda     z:ax
        sec
        sbc     z:ay
        clc
        adc     #60
        jsr     mod6
        beq     @one
        lda     #0
        rts
@one:   lda     #1
        rts
; red: diamonds around the middle
@dia:   jsr     @frame
        bcs     @one
        lda     z:ax
        sec
        sbc     #17
        bpl     :+
        eor     #$FFFF
        inc     a
:       sta     z:g4
        lda     z:ay
        sec
        sbc     #23
        bpl     :+
        eor     #$FFFF
        inc     a
:       clc
        adc     z:g4
        jsr     mod6
        cmp     #2
        bcc     @one
        lda     #0
        rts
; green: a weave of 3 x 3 blocks
@chk:   jsr     @frame
        bcs     @one
        lda     z:ax
        jsr     div3
        sta     z:g4
        lda     z:ay
        jsr     div3
        clc
        adc     z:g4
        and     #1
        rts
; C set on the pattern's frame (the outermost ring)
@frame: lda     z:ax
        cmp     #2
        beq     @fy
        cmp     #CW - 3
        beq     @fy
        lda     z:ay
        cmp     #2
        beq     @fy
        cmp     #CH - 3
        beq     @fy
        clc
        rts
@fy:    sec
        rts

; A mod 6, A / 3 (A small)
mod6:   cmp     #6
        bcc     :+
        sbc     #6
        bra     mod6
:       cmp     #0
        rts
div3:   ldx     #0
:       cmp     #3
        bcc     :+
        sbc     #3
        inx
        bra     :-
:       txa
        rts

; the image ip: colour A everywhere
iclear: sep     #$20
        .a8
        ldy     #ISZ - 1
:       sta     [ip],y
        dey
        bpl     :-
        rep     #$20
        .a16
        rts

; the image ip: a card filled with A, its rounded outline, clear corners
icard:  jsr     iclear
        lda     #C_EDGE
        sta     z:g6
        ; fall through
; the rounded outline in g6 (corners clear)
ioutline:
        lda     #2                      ; top and bottom rows: x 2..32
        sta     z:ax
:       stz     z:ay
        lda     z:g6
        jsr     ipix
        lda     #CH - 1
        sta     z:ay
        lda     z:g6
        jsr     ipix
        inc     z:ax
        lda     z:ax
        cmp     #CW - 2
        bcc     :-
        lda     #1                      ; rows 1 and 46: x 1 and 33
        sta     z:ay
        jsr     @side1
        lda     #CH - 2
        sta     z:ay
        jsr     @side1
        lda     #2                      ; rows 2..45: x 0 and 34
        sta     z:ay
:       stz     z:ax
        lda     z:g6
        jsr     ipix
        lda     #CW - 1
        sta     z:ax
        lda     z:g6
        jsr     ipix
        inc     z:ay
        lda     z:ay
        cmp     #CH - 2
        bcc     :-
        lda     #KEY                    ; the corners
        stz     z:ax
        stz     z:ay
        jsr     @c4
        lda     #CH - 1
        sta     z:ay
        jsr     @c4
        lda     #1
        sta     z:ay
        stz     z:ax
        lda     #KEY
        jsr     ipix
        lda     #CW - 1
        sta     z:ax
        lda     #KEY
        jsr     ipix
        lda     #CH - 2
        sta     z:ay
        lda     #KEY
        jsr     ipix
        stz     z:ax
        lda     #KEY
        jmp     ipix
@side1: lda     #1
        sta     z:ax
        lda     z:g6
        jsr     ipix
        lda     #CW - 2
        sta     z:ax
        lda     z:g6
        jmp     ipix
@c4:    stz     z:ax                    ; x 0, 1, 33, 34 of row ay
        lda     #KEY
        jsr     ipix
        inc     z:ax
        lda     #KEY
        jsr     ipix
        lda     #CW - 2
        sta     z:ax
        lda     #KEY
        jsr     ipix
        inc     z:ax
        lda     #KEY
        jmp     ipix

; pixel ax, ay of the image ip = A (keeps X)
ipix:   pha
        lda     z:ay                    ; ay * 35 + ax
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     z:ay
        adc     z:ay
        adc     z:ay
        adc     z:ax
        tay
        pla
        sep     #$20
        .a8
        sta     [ip],y
        rep     #$20
        .a16
        rts

; the rectangle ax, ay, aw x ah of the image ip in colour A
irect:  sta     z:g3
        lda     z:ay
        pha
        lda     z:ah
        sta     z:g2
@r:     lda     z:ax
        pha
        ldx     z:aw
:       lda     z:g3
        jsr     ipix
        inc     z:ax
        dex
        bne     :-
        pla
        sta     z:ax
        inc     z:ay
        dec     z:g2
        bne     @r
        pla
        sta     z:ay
        rts

; the art ap at ax, ay of the image ip ($FF = ink)
ipaint: lda     z:ax
        pha
        lda     z:ay
        pha
        lda     (ap)
        and     #$00FF
        sta     z:g0                    ; width
        ldy     #1
        lda     (ap),y
        and     #$00FF
        sta     z:g1                    ; height
        lda     z:ap
        clc
        adc     #2
        sta     z:g2                    ; the pixels
@r:     lda     z:g0
        sta     z:g3
        lda     z:ax
        pha
@p:     lda     (g2)
        and     #$00FF
        beq     @n
        cmp     #$FF
        bne     :+
        lda     z:ink
:       jsr     ipix
@n:     inc     z:g2
        inc     z:ax
        dec     z:g3
        bne     @p
        pla
        sta     z:ax
        inc     z:ay
        dec     z:g1
        bne     @r
        pla
        sta     z:ay
        pla
        sta     z:ax
        rts

; ---------------------------------------------------------------- the scene
; the row offsets
mkrows: ldx     #0
        lda     #0
:       sta     rowlo,x
        clc
        adc     #SW
        inx
        inx
        cpx     #2 * HALF
        bcc     :-
        lda     #0
:       sta     rowlo,x
        clc
        adc     #SW
        inx
        inx
        cpx     #2 * TH
        bcc     :-
        rts

; A = row -> sp4 = its first byte (keeps X, Y)
srow:   phx
        asl     a
        tax
        lda     rowlo,x
        sta     z:sp4
        lda     sbank0
        cpx     #2 * HALF
        bcc     :+
        lda     sbank1
:       sta     z:sp4+2
        plx
        rts

; the rectangle ax, ay, aw x ah of the scene in colour A (clipped by the caller)
sfill:  sta     z:g3
        lda     z:ay
        sta     z:g4
        lda     z:ah
        sta     z:g2
        beq     @out
@r:     lda     z:g4
        jsr     srow
        lda     z:sp4
        clc
        adc     z:ax
        sta     z:sp4
        ldy     z:aw
        dey
        sep     #$20
        .a8
        lda     z:g3
:       sta     [sp4],y
        dey
        bpl     :-
        rep     #$20
        .a16
        inc     z:g4
        dec     z:g2
        bne     @r
@out:   rts

; the image A into the scene at ax, ay: rows 0 .. ah-1 (at most CH); g5 <> 0: every
; pixel tested for KEY (the empty places), else only the corner rows
simg:   jsr     imgptr
        lda     z:ay
        sta     z:g4
        stz     z:g2                    ; row
@r:     lda     z:g2
        cmp     z:ah
        bcs     @out
        lda     z:g4
        cmp     #TH
        bcs     @out
        jsr     srow
        lda     z:sp4
        clc
        adc     z:ax
        sta     z:sp4
        lda     z:g5
        bne     @key
        lda     z:g2
        cmp     #2
        bcc     @key
        cmp     #CH - 2
        bcs     @key
        ldy     #CW - 3                 ; a whole row: 17 words and a byte
:       lda     [ip],y
        sta     [sp4],y
        dey
        dey
        bpl     :-
        sep     #$20
        .a8
        ldy     #CW - 1
        lda     [ip],y
        sta     [sp4],y
        rep     #$20
        .a16
        bra     @n
@key:   ldy     #CW - 1
        sep     #$20
        .a8
:       lda     [ip],y
        cmp     #KEY
        beq     :+
        sta     [sp4],y
:       dey
        bpl     :--
        rep     #$20
        .a16
@n:     lda     z:ip
        clc
        adc     #CW
        sta     z:ip
        inc     z:g4
        inc     z:g2
        bra     @r
@out:   rts

; the scene's rectangle ax, ay, aw x ah to the window (clipped to the table)
show:   lda     z:ax                    ; clip
        bpl     :+
        clc
        adc     z:aw
        sta     z:aw
        stz     z:ax
:       lda     z:ay
        bpl     :+
        clc
        adc     z:ah
        sta     z:ah
        stz     z:ay
:       lda     z:ax
        clc
        adc     z:aw
        cmp     #SW
        bcc     :+
        beq     :+
        lda     #SW
        sec
        sbc     z:ax
        sta     z:aw
:       lda     z:ay
        clc
        adc     z:ah
        cmp     #TH
        bcc     :+
        beq     :+
        lda     #TH
        sec
        sbc     z:ay
        sta     z:ah
:       lda     z:aw
        beq     @out
        bmi     @out
        lda     z:ah
        beq     @out
        bmi     @out
        lda     z:ay                    ; the part in the first bank
        cmp     #HALF
        bcs     @second
        clc
        adc     z:ah
        cmp     #HALF + 1
        bcc     @one
        lda     z:ah                    ; split at HALF
        pha
        lda     #HALF
        sec
        sbc     z:ay
        sta     z:ah
        jsr     @blit
        pla
        sec
        sbc     z:ah
        sta     z:ah
        lda     #HALF
        sta     z:ay
@second:
@one:   ; fall through
@blit:  lda     #WD_SBLIT | (<SW << 8)
        sta     sblk
        lda     #>SW
        sta     sblk+2
        lda     z:ax
        sta     sblk+4
        lda     z:ay
        sta     sblk+6
        lda     z:aw
        sta     sblk+8
        lda     z:ah
        sta     sblk+10
        lda     z:ay
        jsr     srow
        lda     z:sp4
        clc
        adc     z:ax
        sta     sblk+12
        lda     z:sp4+2
        sta     sblk+14
        lda     win
        ptr     sblk
        sys     SYS_WDRAW
@out:   rts

; A minus B: the parts of rectangle A (ax..ah) outside B (bx, by, bw, bh) to the window
showminus:
        lda     z:ax                    ; no overlap: all of A
        clc
        adc     z:aw
        cmp     z:bx
        bpl     *+5
        jmp     @all
        jeq     @all
        lda     z:bx
        clc
        adc     z:bw
        cmp     z:ax
        bpl     *+5
        jmp     @all
        jeq     @all
        lda     z:ay
        clc
        adc     z:ah
        cmp     z:by
        bpl     *+5
        jmp     @all
        jeq     @all
        lda     z:by
        clc
        adc     z:bh
        cmp     z:ay
        bpl     *+5
        jmp     @all
        jeq     @all
        lda     z:ax                    ; keep A
        sta     z:qx
        lda     z:ay
        sta     z:qy
        lda     z:aw
        sta     z:qw
        lda     z:ah
        sta     z:qh
        lda     z:by                    ; above B
        sec
        sbc     z:qy
        bmi     :+
        beq     :+
        sta     z:ah
        jsr     show
        jsr     @a
:       lda     z:qy                    ; below B
        clc
        adc     z:qh
        sta     z:g8                    ; A's bottom
        lda     z:by
        clc
        adc     z:bh
        sta     z:g9                    ; B's bottom
        lda     z:g8
        sec
        sbc     z:g9
        bmi     :+
        beq     :+
        sta     z:ah
        lda     z:g9
        sta     z:ay
        jsr     show
        jsr     @a
:       lda     z:qy                    ; the rows of both: y0 .. y1
        cmp     z:by
        bpl     :+
        lda     z:by
:       sta     z:g6
        lda     z:g8
        cmp     z:g9
        bmi     :+
        lda     z:g9
:       sec
        sbc     z:g6
        sta     z:g7                    ; their height
        lda     z:bx                    ; left of B
        sec
        sbc     z:qx
        bmi     :+
        beq     :+
        sta     z:aw
        lda     z:g6
        sta     z:ay
        lda     z:g7
        sta     z:ah
        jsr     show
        jsr     @a
:       lda     z:bx                    ; right of B
        clc
        adc     z:bw
        sta     z:g8
        lda     z:qx
        clc
        adc     z:qw
        sec
        sbc     z:g8
        bmi     @out
        beq     @out
        sta     z:aw
        lda     z:g8
        sta     z:ax
        lda     z:g6
        sta     z:ay
        lda     z:g7
        sta     z:ah
        jmp     show
@out:   rts
@all:   jmp     show
@a:     lda     z:qx                    ; A back in ax..ah
        sta     z:ax
        lda     z:qy
        sta     z:ay
        lda     z:qw
        sta     z:aw
        lda     z:qh
        sta     z:ah
        rts

; ---------------------------------------------------------------- piles
; the places of the piles for the game
setlayout:
        ldx     #KDX                    ; (the column step)
        lda     game
        beq     :+
        ldx     #FDX
:       stx     z:g1
        ldx     #0
        lda     game
        bne     @fc
        lda     #KX0                    ; stock, waste
        sta     pxs
        lda     #KX0 + KDX
        sta     pxs+2
        lda     #TY
        sta     pys
        sta     pys+2
        ldx     #2 * K_FOUND
        lda     #KX0 + 3 * KDX
        ldy     #4
        jsr     @row
        ldx     #2 * K_TAB
        lda     #KX0
        ldy     #7
        jmp     @tab
@fc:    ldx     #2 * F_CELL
        lda     #FX0
        ldy     #8
        jsr     @row
        ldx     #2 * F_TAB
        lda     #FX0
        ldy     #8
@tab:   sta     z:g0
:       lda     z:g0
        sta     pxs,x
        lda     #TABY
        sta     pys,x
        jsr     @next
        bne     :-
        rts
@row:   sta     z:g0
:       lda     z:g0
        sta     pxs,x
        lda     #TY
        sta     pys,x
        jsr     @next
        bne     :-
        rts
@next:  lda     z:g0
        clc
        adc     z:g1
        sta     z:g0
        inx
        inx
        dey
        rts

; A = tableau pile: the y of each card (from TABY) in ycache, steps fitted to the table
layout: sta     z:g8
        jsr     pofs
        sta     z:g9                    ; the pile's first card
        lda     z:g8
        asl     a
        tax
        lda     pcnt,x
        sta     z:g7                    ; cards
        stz     z:g5                    ; face down ones
        ldx     z:g9
        ldy     z:g7
        beq     @go
:       lda     pcards,x
        and     #DOWN
        beq     :+
        inc     z:g5
        inx
        dey
        bne     :-
:       lda     z:g7                    ; face up: (room - CH - down * DSTEP) / (up - 1)
        sec
        sbc     z:g5
        dec     a
        sta     z:g6
        lda     #USTEP
        sta     z:g4
        lda     z:g6
        beq     @go
        bmi     @go
        lda     z:g5
        asl     a
        asl     a
        sta     z:g3
        lda     #TH - 4 - TABY - CH
        sec
        sbc     z:g3
        ldx     #0                      ; / up - 1
:       cmp     z:g6
        bcc     :+
        sbc     z:g6
        inx
        bra     :-
:       cpx     #USTEP
        bcs     @go
        stx     z:g4
        cpx     #MINSTEP
        bcs     @go
        lda     #MINSTEP
        sta     z:g4
@go:    ldx     z:g9                    ; the offsets
        ldy     #0
        lda     #0
@c:     cpy     z:g7
        bcs     @out
        sep     #$20
        .a8
        sta     ycache,x
        rep     #$20
        .a16
        pha
        lda     pcards,x
        and     #DOWN
        beq     :+
        pla
        clc
        adc     #DSTEP
        bra     :++
:       pla
        clc
        adc     z:g4
:       and     #$00FF
        inx
        iny
        bra     @c
@out:   rts

; A = pile -> ax, ay, aw, ah = its area
parea:  sta     z:g0
        asl     a
        tax
        lda     pxs,x
        sta     z:ax
        lda     pys,x
        sta     z:ay
        lda     #CW
        sta     z:aw
        lda     #CH
        sta     z:ah
        lda     ptype,x
        cmp     #PT_TAB
        bne     :+
        lda     #TH - TABY
        sta     z:ah
        rts
:       cmp     #PT_WASTE
        bne     :+
        lda     #CW + 2 * WFAN
        sta     z:aw
:       rts

; A = pile, X = the cards to draw (the rest is carried): the pile into the scene
pdraw:  sta     z:pp
        stx     z:plim
        jsr     parea
        lda     #C_TABLE
        jsr     sfill
        lda     z:pp
        asl     a
        tax
        lda     ptype,x
        sta     z:ptyv
        lda     z:plim
        bne     @cards
        lda     noslots                 ; (the win: none)
        jne     @out
        lda     z:ptyv                  ; empty: its mark
        ldx     #I_SLOT
        cmp     #PT_WASTE
        jeq     @out
        cmp     #PT_FOUND
        bne     :+
        ldx     #I_SLOTA
:       cmp     #PT_STOCK
        bne     :+
        ldx     #I_RING
:       cmp     #PT_TAB
        bne     :+
        lda     game
        bne     :+
        ldx     #I_SLOTK
:       txa
        ldx     #1
        stx     z:g5
        ldx     #CH
        stx     z:ah
        jmp     simg
@cards: stz     z:g5
        lda     z:ptyv
        cmp     #PT_TAB
        beq     @tab
        cmp     #PT_WASTE
        beq     @waste
        lda     z:plim                  ; the top one only
        dec     a
        jsr     @img
        lda     #CH
        sta     z:ah
        lda     z:g1
        jmp     simg
@waste: lda     z:plim                  ; the last three fanned (draw 3), else the top
        dec     a
        ldx     draw3
        beq     :+
        dec     a
        dec     a
        bpl     :+
        lda     #0
:       sta     z:pi
@wl:    lda     z:pi
        cmp     z:plim
        bcs     @out
        jsr     @img
        lda     #CH
        sta     z:ah
        lda     z:g1
        jsr     simg
        lda     z:ax
        clc
        adc     #WFAN
        sta     z:ax
        inc     z:pi
        bra     @wl
@tab:   lda     z:pp
        jsr     layout
        stz     z:pi
@tl:    lda     z:pi
        cmp     z:plim
        bcs     @out
        jsr     @img
        lda     z:pp
        jsr     pofs
        clc
        adc     z:pi
        tax
        lda     ycache,x
        and     #$00FF
        sta     z:g0
        clc
        adc     #TABY
        sta     z:ay
        lda     #CH                     ; covered: only the strip to the next card
        sta     z:ah
        lda     z:pi
        inc     a
        cmp     z:plim
        bcs     :+
        lda     ycache+1,x
        and     #$00FF
        sec
        sbc     z:g0
        cmp     #CH
        bcs     :+
        sta     z:ah
:       lda     z:g1
        jsr     simg
        inc     z:pi
        bra     @tl
@out:   rts
; A = index in pile pp -> g1 = its image (face or back); keeps ax
@img:   pha
        lda     z:pp
        jsr     pofs
        sta     z:g1
        pla
        clc
        adc     z:g1
        tax
        lda     pcards,x
        and     #$00FF
        bit     #DOWN
        beq     :+
        lda     back
        clc
        adc     #I_BACK
:       sta     z:g1
        rts

; A = pile: drawn in the scene and shown
pshow:  pha
        asl     a
        tax
        lda     pcnt,x
        tax
        pla
        pha
        jsr     pdraw
        pla
        jsr     parea
        jmp     show

; every pile marked in dirty, drawn and shown
redirty:
        stz     z:g8
:       lda     z:g8
        cmp     npiles
        bcs     :++
        jsr     pbit
        and     dirty
        beq     :+
        lda     z:g8
        jsr     pshow
:       inc     z:g8
        bra     :--
:       stz     dirty
        rts

; the whole table
drawtable:
        stz     z:ax
        stz     z:ay
        lda     #SW
        sta     z:aw
        lda     #TH
        sta     z:ah
        lda     #C_TABLE
        jsr     sfill
        stz     z:g8
:       lda     z:g8
        cmp     npiles
        bcs     :+
        asl     a
        tax
        lda     pcnt,x
        tax
        lda     z:g8
        jsr     pdraw
        inc     z:g8
        bra     :-
:       stz     dirty
        stz     z:ax
        stz     z:ay
        lda     #SW
        sta     z:aw
        lda     #TH
        sta     z:ah
        jmp     show

; A = pile, X = index -> cx, cy: where that card lies
cardpos:
        stx     z:g1
        sta     z:g0
        asl     a
        tax
        lda     pxs,x
        sta     z:cx
        lda     pys,x
        sta     z:cy
        lda     ptype,x
        cmp     #PT_TAB
        bne     :+
        lda     z:g0
        jsr     pofs
        clc
        adc     z:g1
        tax
        lda     ycache,x
        and     #$00FF
        clc
        adc     z:cy
        sta     z:cy
        rts
:       cmp     #PT_WASTE
        bne     @out
        lda     draw3
        beq     @out
        lda     z:g0                    ; the fan: index - first shown
        asl     a
        tax
        lda     pcnt,x
        sec
        sbc     #3
        bpl     :+
        lda     #0
:       sta     z:g2
        lda     z:g1
        sec
        sbc     z:g2
        bmi     @out
        sta     z:g2
        asl     a
        clc
        adc     z:g2
        asl     a
        asl     a                       ; * WFAN (12)
        clc
        adc     z:cx
        sta     z:cx
@out:   rts

; the pointer at ex, ey -> C set: hp_ = pile, hi = card index ($FFFF: an empty pile)
hittest:
        lda     npiles
        dec     a
        sta     z:hpl
@p:     lda     z:hpl
        bmi     @no
        asl     a
        tax
        lda     z:ex
        sec
        sbc     pxs,x
        bmi     @n
        cmp     #CW + 2 * WFAN
        bcs     @n
        lda     pcnt,x
        beq     @empty
        dec     a
        sta     z:hi
@c:     lda     z:hpl                   ; the cards from the top down
        ldx     z:hi
        jsr     cardpos
        lda     z:ex
        sec
        sbc     z:cx
        bmi     @cn
        cmp     #CW
        bcs     @cn
        lda     z:ey
        sec
        sbc     z:cy
        bmi     @cn
        cmp     #CH
        bcs     @cn
        sec
        rts
@cn:    lda     z:hpl                   ; (only the waste's top card counts)
        jsr     ptyp
        cmp     #PT_TAB
        bne     @n
        dec     z:hi
        bpl     @c
        bra     @n
@empty: lda     z:ex
        sec
        sbc     pxs,x
        cmp     #CW
        bcs     @n
        lda     z:ey
        sec
        sbc     pys,x
        bmi     @n
        cmp     #CH
        bcs     @n
        lda     #$FFFF
        sta     z:hi
        sec
        rts
@n:     dec     z:hpl
        bra     @p
@no:    clc
        rts

; ---------------------------------------------------------------- carrying cards
; pile ds, cards from di: dimg (dn cards, dh high), the pile drawn without them
; (not shown), dx, dy = where the first one lies
lift:   lda     z:ds
        asl     a
        tax
        lda     pcnt,x
        sec
        sbc     z:di
        sta     z:dn
        dec     a                       ; dh = CH + (n - 1) * USTEP
        sta     z:g0
        asl     a
        clc
        adc     z:g0
        asl     a
        asl     a
        adc     z:g0                    ; * 13
        clc
        adc     #CH
        sta     z:dh
        lda     wbank                   ; dimg: clear, the cards
        sta     z:wp+2
        stz     z:wp
        lda     z:dh
        sta     z:g0
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     z:g0
        adc     z:g0
        adc     z:g0
        tay
        dey
        sep     #$20
        .a8
        lda     #KEY
:       sta     [wp],y
        dey
        bpl     :-
        rep     #$20
        .a16
        stz     z:g9                    ; card k at y 13 k
        stz     z:g8
@k:     lda     z:ds
        jsr     pofs
        clc
        adc     z:di
        adc     z:g9
        tax
        lda     pcards,x
        and     #$00FF
        bit     #DOWN
        beq     :+
        lda     back
        clc
        adc     #I_BACK
:       jsr     imgptr
        lda     z:g8                    ; wp = row g8
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     z:g8
        adc     z:g8
        adc     z:g8
        sta     z:wp
        stz     z:g2                    ; 48 rows, clear pixels left
@r:     ldy     #CW - 1
        sep     #$20
        .a8
:       lda     [ip],y
        cmp     #KEY
        beq     :+
        sta     [wp],y
:       dey
        bpl     :--
        rep     #$20
        .a16
        lda     z:ip
        clc
        adc     #CW
        sta     z:ip
        lda     z:wp
        clc
        adc     #CW
        sta     z:wp
        inc     z:g2
        lda     z:g2
        cmp     #CH
        bcc     @r
        lda     z:g8
        clc
        adc     #USTEP
        sta     z:g8
        inc     z:g9
        lda     z:g9
        cmp     z:dn
        bcc     @k
        lda     z:ds                    ; where they were
        ldx     z:di
        jsr     cardpos
        lda     z:cx
        sta     z:dx
        lda     z:cy
        sta     z:dy
        lda     z:ds                    ; the pile without them
        ldx     z:di
        jmp     pdraw

; the carried cards at A = x, X = y (kept on the table): composed over the scene, shown;
; what the old place showed and the new does not, back from the scene
carry:  bpl     :+
        lda     #0
:       cmp     #SW - CW + 1
        bcc     :+
        lda     #SW - CW
:       sta     z:nx
        txa
        bpl     :+
        lda     #0
:       sta     z:ny
        lda     #TH
        sec
        sbc     z:dh
        cmp     z:ny
        bcs     :+
        sta     z:ny
:       jsr     compose
        lda     z:dx                    ; old minus new
        sta     z:ax
        lda     z:dy
        sta     z:ay
        lda     #CW
        sta     z:aw
        sta     z:bw
        lda     z:dh
        sta     z:ah
        sta     z:bh
        lda     z:nx
        sta     z:bx
        sta     z:dx
        lda     z:ny
        sta     z:by
        sta     z:dy
        lda     z:ax                    ; (unmoved: nothing to put back)
        cmp     z:bx
        bne     :+
        lda     z:ay
        cmp     z:by
        beq     @out
:       jmp     showminus
@out:   rts

; tmp = dimg over the scene at nx, ny; blitted there
compose:
        lda     wbank
        sta     z:wp+2
        sta     z:wq+2
        stz     z:wp                    ; dimg's row
        lda     #TMPOFS
        sta     z:wq                    ; tmp's row
        stz     z:g2
@r:     lda     z:ny
        clc
        adc     z:g2
        jsr     srow
        lda     z:sp4
        clc
        adc     z:nx
        sta     z:sp4
        lda     z:g2                    ; the corner rows: clear pixels from the scene
        cmp     #2
        bcc     @key
        clc
        adc     #2
        cmp     z:dh
        bcs     @key
        ldy     #CW - 3                 ; others: dimg's row as it is
:       lda     [wp],y
        sta     [wq],y
        dey
        dey
        bpl     :-
        sep     #$20
        .a8
        ldy     #CW - 1
        lda     [wp],y
        sta     [wq],y
        rep     #$20
        .a16
        bra     @n
@key:   ldy     #CW - 1
        sep     #$20
        .a8
:       lda     [wp],y
        cmp     #KEY
        bne     :+
        lda     [sp4],y
:       sta     [wq],y
        dey
        bpl     :--
        rep     #$20
        .a16
@n:     lda     z:wp
        clc
        adc     #CW
        sta     z:wp
        lda     z:wq
        clc
        adc     #CW
        sta     z:wq
        inc     z:g2
        lda     z:g2
        cmp     z:dh
        bcc     @r
        lda     #WD_BLIT                ; one blit
        sta     sblk
        stz     sblk+2
        lda     z:nx
        sta     sblk+4
        lda     z:ny
        sta     sblk+6
        lda     #CW
        sta     sblk+8
        lda     z:dh
        sta     sblk+10
        lda     #TMPOFS
        sta     sblk+12
        lda     wbank
        sta     sblk+14
        lda     win
        ptr     sblk
        sys     SYS_WDRAW
        rts

; the carried cards' last place back from the scene (after a drop)
unshow: lda     z:dx
        sta     z:ax
        lda     z:dy
        sta     z:ay
        lda     #CW
        sta     z:aw
        lda     z:dh
        sta     z:ah
        jmp     show

; fly the carried cards from dx, dy to A = x, X = y in z:frames steps (arc: z:arc pixels
; up in the middle)
fly:    sta     z:fx
        stx     z:fy
        lda     z:dx
        sta     z:fx0
        lda     z:dy
        sta     z:fy0
        lda     #1
        sta     z:ff
@f:     lda     z:fx0                   ; x0 + (x1 - x0) f / F
        ldx     z:fx
        jsr     lerp
        pha
        lda     z:fy0
        ldx     z:fy
        jsr     lerp
        sta     z:g0
        lda     z:arc                   ; - arc * 4 f (F - f) / F^2
        beq     :+
        lda     z:frames
        sec
        sbc     z:ff
        sta     z:g1
        lda     z:ff
        ldx     z:g1
        jsr     umul
        asl     a
        asl     a
        ldx     z:arc
        jsr     umul
        ldx     z:frames
        jsr     udiv
        ldx     z:frames
        jsr     udiv
        eor     #$FFFF
        sec
        adc     z:g0
        sta     z:g0
:       ldx     z:g0
        pla
        jsr     carry
        lda     #10
        sys     SYS_SLEEP
        inc     z:ff
        lda     z:ff
        cmp     z:frames
        bcc     @f
        beq     @f
        rts
; A = a, X = b -> a + (b - a) * ff / frames
lerp:   sta     z:g2
        stx     z:g3
        txa
        sec
        sbc     z:g2
        bpl     :+
        eor     #$FFFF
        inc     a
        ldx     z:ff
        jsr     umul
        ldx     z:frames
        jsr     udiv
        eor     #$FFFF
        sec
        adc     z:g2
        rts
:       ldx     z:ff
        jsr     umul
        ldx     z:frames
        jsr     udiv
        clc
        adc     z:g2
        rts

; A * X -> A (16 bits), A / X -> A (unsigned; keep nothing else)
umul:   sta     z:g4
        stx     z:g5
        lda     #0
:       ldx     z:g5
        beq     :+
        lsr     z:g5
        bcc     @s
        clc
        adc     z:g4
@s:     asl     z:g4
        bra     :-
:       rts
udiv:   stx     z:g5
        ldx     #0
:       cmp     z:g5
        bcc     :+
        sbc     z:g5
        inx
        bra     :-
:       txa
        rts

; ---------------------------------------------------------------- the win
; the cards leave the foundations one by one (the tops in turn) and fly to a ring in the
; middle of the table, each landing on the last
winanim:
        stz     wn                      ; the card number
@c:     lda     wn
        and     #3                      ; foundation (n mod 4)
        clc
        adc     #K_FOUND
        ldx     game
        beq     :+
        clc
        adc     #F_FOUND - K_FOUND
:       sta     z:ds
        asl     a
        tax
        lda     pcnt,x
        beq     @n
        dec     a
        sta     z:di
        jsr     lift                    ; (draws the foundation without it)
        jsr     unshow2
        lda     #12
        sta     z:frames
        lda     #40
        sta     z:arc
        lda     wn
        asl     a
        asl     a
        tax
        lda     ring+2,x
        pha
        lda     ring,x
        plx
        jsr     fly
        lda     z:ds                    ; it lands: off the foundation, into the scene
        asl     a
        tax
        dec     pcnt,x
        lda     z:ds
        jsr     pofs
        clc
        adc     pcnt,x
        tax
        lda     pcards,x
        and     #$00FF
        sta     z:g0
        lda     z:dx
        sta     z:ax
        lda     z:dy
        sta     z:ay
        lda     #CH
        sta     z:ah
        stz     z:g5
        lda     z:g0
        jsr     simg
        jsr     unshow
@n:     inc     wn
        lda     wn
        cmp     #52
        jcc     @c
        rts
; the lifted pile's area shown outside the carried card
unshow2:
        lda     z:ds
        jsr     parea
        lda     z:dx
        sta     z:bx
        lda     z:dy
        sta     z:by
        lda     #CW
        sta     z:bw
        lda     z:dh
        sta     z:bh
        jsr     compose0
        jmp     showminus
; compose at the lifted place (nx, ny = dx, dy)
compose0:
        lda     z:dx
        sta     z:nx
        lda     z:dy
        sta     z:ny
        jmp     compose
