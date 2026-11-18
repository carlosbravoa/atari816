; SAVER - (0.24) the screen saver (/SYSTEM/SAVER.PRG). The Desktop starts it when nobody has
; touched the keyboard, the mouse or a joystick for the time set in Settings (kernel setting 5,
; "Screen saver"; setting 6 counts the seconds without input); Settings' "Test" starts it at
; once. One instance only (SYS_SINGLE).
;
; It opens a small plain window and puts it in full-screen mode (320 x 180, 8 bpp: one bank,
; black), so the desktop itself is left untouched and comes back exactly as it was when the
; program ends (exit closes the window: the kernel's way out of full-screen mode). On it,
; Marga's sprites drift and bounce off the edges, once a frame (vsync): the word "Atari816" in
; colours that slowly move (two 32 x 16 sprites), the About box's rainbow stripes, six desktop
; icons and seven twinkling stars, all at different speeds (tools/mksaver.py makes the art).
; 16 sprites, none wider than 32 pixels: never more than 512 sprite pixels on a line, so none
; is ever left out. The CPU's work a frame: the objects moved, one spr_move for the sprites
; that moved by a pixel (A = $8000 | count), now and then a pal_set of 9 or 10 colours, and
; every fourth frame a look at the input.
;
; Without sprites (REV below $0B, or spr_alloc fails: another program holds them) the stripes
; block alone is drawn by the CPU into the black framebuffer, at a new place once a second.
;
; It ends at: a key pressed, a mouse button pressed, the wheel, the pointer moved more than THR
; pixels, a joystick change, or the loss of the keyboard focus (Alt+Tab; F12: the classic Atari
; is shown at once; another program's new window). A key or button that wakes it is
; swallowed: the program waits (at most half a second, still showing) for its release, so
; neither the press nor the release reaches the desktop (an Alt alone would otherwise open the
; menu bar).
        .include "horizon.inc"

NOBJ    = 15                            ; the word, the stripes, 6 icons, 7 stars
NSPR    = 16
THR     = 6                             ; pointer movement that wakes it (screen pixels)
IMG     = $1000                         ; the images, in the window bank (16-byte aligned)
IMG_ICON = IMG
IMG_STR = IMG_ICON + 6 * 512
IMG_WORD = IMG_STR + 256
IMG_STAR = IMG_WORD + 512
ART_LEN = 6 * 512 + 256 + 512 + 3 * 128
C4      = SPR_EN | SPR_BPP4

        .segment "CODE"
        .a16
        .i16
start:  sys     SYS_SINGLE              ; one runs already
        bcc     :+
        exit    0
:       sys     SYS_WSSTART
        bcs     @no
        cmp     #0
        beq     :+
        sys     SYS_WSSTOP              ; no desktop: nothing to protect
@no:    exit    1
:       sys     SYS_TGET                ; the clock's seconds: a new start each time
        ora     #1
        sta     z:seed
        ldx     #8                      ; (stirred)
:       jsr     rnd
        dex
        bne     :-
        sys     SYS_BALLOC              ; the framebuffer: one bank, black
        bcs     @no
        sta     z:fb+2
        stz     z:fb
        sep     #$20
        .a8
        sta     fsb+8
        rep     #$20
        .a16
        lda     #0
        tay
:       sta     [fb],y
        iny
        iny
        cpy     #320 * 180
        bcc     :-
        ldx     #0                      ; the images into the window bank
:       lda     sv_icons,x
        sta     f:IMG,x
        inx
        inx
        cpx     #ART_LEN
        bcc     :-
        lda     #1
        sys     SYS_WSHOLD
        ptr     wblk
        sys     SYS_WOPEN
        bcs     @fail
        sta     z:win
        ptr     fsb
        sys     SYS_FSENTER             ; (EAGAIN: another program is in full-screen mode)
@fail:  php
        lda     #0
        sys     SYS_WSHOLD
        plp
        bcc     :+
        exit    1
:       lda     #$FF                    ; where the pointer and the joysticks are now
        ptr     msb
        sys     SYS_WMOUSE
        lda     msb
        sta     z:x0
        lda     msb+2
        sta     z:y0
        jsr     joyst
        sta     z:j0
        jsr     objinit
        lda     #NSPR
        ldx     z:win
        sys     SYS_SPRALLOC
        jcs     fallback
        sta     z:s0
        lda     #32 | (112 << 8)        ; the palette banks 2-8: stripes, icons
        ptr     sv_pal
        sys     SYS_PALSET
        jsr     hue
        jsr     twinkle
        ldx     #0                      ; the sprites: every field (sprite X, entry Y)
        ldy     #0
@s:     phx
        lda     sp_obj,x
        and     #$00FF
        asl     a
        sta     z:t
        txa
        clc
        adc     z:s0
        sep     #$20
        .a8
        sta     sbuf,y
        lda     sp_ctl,x
        sta     sbuf+1,y
        lda     sp_pal,x
        sta     sbuf+9,y
        lda     #0
        sta     sbuf+8,y
        rep     #$20
        .a16
        txa
        asl     a
        tax
        lda     sp_img,x
        sta     sbuf+6,y
        lda     sp_xo,x
        ldx     z:t
        clc
        adc     olx,x
        sta     sbuf+2,y
        lda     oly,x
        sta     sbuf+4,y
        tya
        clc
        adc     #10
        tay
        plx
        inx
        cpx     #NSPR
        bcc     @s
        lda     #NSPR
        ptr     sbuf
        sys     SYS_SPRSET

frame:  sys     SYS_VSYNC
        inc     z:fc
        jsr     move
        lda     z:fc                    ; every fourth frame: the input (1), the stars (2);
        and     #3                      ; every eighth: the word's colours (0)
        cmp     #1
        bne     :+
        jsr     input
        bra     frame
:       cmp     #2
        bne     :+
        jsr     twinkle
        bra     frame
:       cmp     #0
        bne     frame
        lda     z:fc
        and     #4
        bne     frame
        jsr     hue
        bra     frame

; ---------------------------------------------------------------- input
; every fourth frame: returns, or ends the program (woken)
input:  lda     #1                      ; the events queued
        ptr     ev
        sys     SYS_WEVENT
        jcs     @poll
        lda     ev
        and     #$00FF
        ldx     z:wk
        bne     @waking
        cmp     #WE_KEY
        bne     :+
        lda     ev+4                    ; a press (a release of a key held before: nothing)
        cmp     #$0100
        bcc     input
        lda     ev+2
        sta     z:wkey
        lda     #1                      ; woken by a key: its release is waited for
        sta     z:wk
        bra     input
:       cmp     #WE_BUTTON
        bne     :+
        lda     ev+6
        and     #7
        beq     input
        lda     #2                      ; by a button: the same
        sta     z:wk
        bra     input
:       cmp     #WE_WHEEL
        beq     bye
        cmp     #WE_UNFOCUS             ; (Alt+Tab, F12, another window came up)
        beq     bye
        cmp     #WE_CLOSE
        beq     bye
        bra     input
@waking: cpx    #1
        bne     @wbtn
        cmp     #WE_KEY                 ; the waking key's release
        bne     @wun
        lda     ev+4
        cmp     #$0100
        bcs     input
        lda     ev+2
        cmp     z:wkey
        beq     bye
        bra     input
@wbtn:  cmp     #WE_BUTTON              ; every button released
        bne     @wun
        lda     ev+6
        and     #7
        beq     bye
        jmp     input
@wun:   cmp     #WE_UNFOCUS
        beq     bye
        jmp     input
@poll:  lda     z:wk                    ; woken: half a second at most
        beq     :+
        inc     z:wcnt
        lda     z:wcnt
        cmp     #8
        bcs     bye
        rts
:       lda     #$FF                    ; the pointer moved?
        ptr     msb
        sys     SYS_WMOUSE
        lda     msb
        sec
        sbc     z:x0
        jsr     abs
        cmp     #THR + 1
        bcs     bye
        lda     msb+2
        sec
        sbc     z:y0
        jsr     abs
        cmp     #THR + 1
        bcs     bye
        jsr     joyst                   ; a joystick changed?
        cmp     z:j0
        bne     bye
        rts
bye:    exit    0

abs:    bpl     :+
        eor     #$FFFF
        inc     a
:       rts

; both joysticks -> A (directions | triggers << 8)
joyst:  lda     #0
        sys     SYS_JOY
        sta     z:t
        txa
        xba
        ora     z:t
        rts

; ---------------------------------------------------------------- the sprites
; the objects: a random place, their speed with a random direction
objinit:
        ldx     #0
@o:     lda     #320                    ; the largest x and y, in 1/16 pixel
        sec
        sbc     ob_w,x
        sta     z:t
        jsr     rndmod
        sta     olx,x
        jsr     x16
        sta     ox,x
        lda     z:t
        jsr     x16
        sta     oxmax,x
        lda     #180
        sec
        sbc     ob_h,x
        sta     z:t
        jsr     rndmod
        sta     oly,x
        jsr     x16
        sta     oy,x
        lda     z:t
        jsr     x16
        sta     oymax,x
        jsr     rnd
        sta     z:t
        lda     ob_dx,x
        lsr     z:t
        bcc     :+
        eor     #$FFFF
        inc     a
:       sta     odx,x
        lda     ob_dy,x
        lsr     z:t
        bcc     :+
        eor     #$FFFF
        inc     a
:       sta     ody,x
        inx
        inx
        cpx     #NOBJ * 2
        bcc     @o
        rts
x16:    asl     a
        asl     a
        asl     a
        asl     a
        rts

; once a frame: every object one step on, bouncing at the edges; the sprites of those that
; moved by a pixel (most frames a few of them) in one spr_move
move:   stz     z:nm
        stz     z:nc
        ldx     #0
@o:     lda     ox,x
        clc
        adc     odx,x
        bpl     :+
        lda     #0
        jsr     flipx
:       cmp     oxmax,x
        bcc     :+
        lda     oxmax,x
        jsr     flipx
:       sta     ox,x
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     z:t2
        lda     oy,x
        clc
        adc     ody,x
        bpl     :+
        lda     #0
        jsr     flipy
:       cmp     oymax,x
        bcc     :+
        lda     oymax,x
        jsr     flipy
:       sta     oy,x
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     z:t
        cmp     oly,x
        bne     @ch
        lda     z:t2
        cmp     olx,x
        beq     @nx
@ch:    lda     z:t2
        sta     olx,x
        lda     z:t
        sta     oly,x
        ldy     z:nm                    ; its entry {sprite, x, y}
        lda     ob_sp,x
        clc
        adc     z:s0
        sta     mbuf,y
        lda     z:t2
        sta     mbuf+2,y
        lda     z:t
        sta     mbuf+4,y
        inc     z:nc
        cpx     #0                      ; the word: its second half too
        bne     :+
        lda     mbuf,y
        inc     a
        sta     mbuf+6,y
        lda     z:t2
        clc
        adc     #32
        sta     mbuf+8,y
        lda     z:t
        sta     mbuf+10,y
        inc     z:nc
        lda     z:nm
        clc
        adc     #6
        sta     z:nm
:       lda     z:nm
        clc
        adc     #6
        sta     z:nm
@nx:    inx
        inx
        cpx     #NOBJ * 2
        jcc     @o
        lda     z:nc
        beq     :+
        ora     #$8000
        ptr     mbuf
        sys     SYS_SPRMOVE
:       rts
flipx:  pha
        lda     #0
        sec
        sbc     odx,x
        sta     odx,x
        pla
        rts
flipy:  pha
        lda     #0
        sec
        sbc     ody,x
        sta     ody,x
        pla
        rts

; the word's colours (entries 17-26: one a row), a step further round the wheel
hue:    inc     z:hph
        ldy     #0                      ; pbuf + 3 k
        stz     z:t2                    ; 3 k
@k:     lda     z:t2                    ; colour (hph + 3 k) & 63, 3 bytes each
        clc
        adc     z:hph
        and     #63
        sta     z:t
        asl     a
        adc     z:t
        tax
        sep     #$20
        .a8
        lda     sv_hue,x
        sta     pbuf,y
        lda     sv_hue+1,x
        sta     pbuf+1,y
        lda     sv_hue+2,x
        sta     pbuf+2,y
        rep     #$20
        .a16
        iny
        iny
        iny
        lda     z:t2
        clc
        adc     #3
        sta     z:t2
        cpy     #30
        bcc     @k
        lda     #17 | (10 << 8)
        ptr     pbuf
        sys     SYS_PALSET
        rts

; the stars' bank 9: its colours 1-3, 4-6, 7-9 (entries 145-153: the three star images), each
; at its own phase
twinkle:
        ldx     #0                      ; phase j: tw_ph + 2 j, tbuf + 9 j
        stz     z:i
@b:     lda     z:fc
        lsr     a
        clc
        adc     tw_ph,x
        and     #63
        cmp     #32
        bcc     :+
        eor     #63
:       sta     z:t                     ; level 0-31: 9 bytes each
        asl     a
        asl     a
        asl     a
        clc
        adc     z:t
        tay
        phx
        ldx     z:i
        lda     #8
        sta     z:t
:       sep     #$20
        .a8
        lda     sv_twk,y
        sta     tbuf,x
        rep     #$20
        .a16
        iny
        inx
        dec     z:t
        bpl     :-
        plx
        lda     z:i
        clc
        adc     #9
        sta     z:i
        inx
        inx
        cpx     #6
        bcc     @b
        lda     #145 | (9 << 8)
        ptr     tbuf
        sys     SYS_PALSET
        rts

; ---------------------------------------------------------------- without sprites
; the stripes block, drawn by the CPU, at a new place once a second
fallback:
        lda     #32 | (16 << 8)         ; its colours (bank 2: entries 33-40)
        ptr     sv_pal
        sys     SYS_PALSET
        lda     #59
        sta     z:fc
@f:     sys     SYS_VSYNC
        lda     z:fc
        and     #3
        bne     :+
        jsr     input
:       inc     z:fc
        lda     z:fc
        cmp     #60
        bcc     @f
        stz     z:fc
        lda     #1                      ; the old place black
        sta     z:er
        jsr     block
        lda     #320 - 16
        jsr     rndmod
        sta     z:bx
        lda     #180 - 32
        jsr     rndmod
        sta     z:by
        stz     z:er
        jsr     block
        bra     @f

; the 16 x 32 block at bx, by: sv_fb (er = 0) or black (er = 1)
block:  lda     z:by                    ; by * 320 + bx
        xba
        sta     z:pos
        lda     z:by
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     z:pos
        adc     z:bx
        sta     z:pos
        ldx     #0
        lda     #32
        sta     z:cnt
@r:     lda     #8
        sta     z:t
@c:     lda     #0
        ldy     z:er
        bne     :+
        lda     sv_fb,x
:       ldy     z:pos
        sta     [fb],y
        inx
        inx
        iny
        iny
        sty     z:pos
        dec     z:t
        bne     @c
        lda     z:pos
        clc
        adc     #320 - 16
        sta     z:pos
        dec     z:cnt
        bne     @r
        rts

; ---------------------------------------------------------------- random numbers
; xorshift (16 bits: 7, 9, 8) -> A (keeps X)
rnd:    lda     z:seed
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        eor     z:seed
        sta     z:seed
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        eor     z:seed
        sta     z:seed
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        eor     z:seed
        sta     z:seed
        rts
; a random number 0 .. A - 1 (A 1-511) -> A (keeps X)
rndmod: sta     z:t2
        jsr     rnd
        and     #$01FF
:       cmp     z:t2
        bcc     :+
        sbc     z:t2
        bra     :-
:       rts

        .segment "RODATA"
        .include "saver_art.inc"
t_name: .byte   "Screen saver", 0
; the objects: width, height (pixels of 320 x 180), speed (1/16 pixel a frame), first sprite
ob_w:   .word   64, 16, 32, 32, 32, 32, 32, 32, 16, 16, 16, 16, 16, 16, 16
ob_h:   .word   16, 32, 32, 32, 32, 32, 32, 32, 16, 16, 16, 16, 16, 16, 16
ob_dx:  .word   10, 14, 8, 6, 11, 5, 9, 7, 2, 1, 3, 2, 1, 3, 2
ob_dy:  .word   6, 9, 5, 9, 4, 7, 10, 6, 1, 3, 2, 2, 1, 1, 3
ob_sp:  .word   0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
; the sprites (front first): object, ctrl, palette bank, image, x offset in the object
sp_obj: .byte   0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14
sp_ctl: .byte   C4 | SPR_WIDE, C4 | SPR_WIDE, C4 | SPR_TALL
        .byte   C4 | SPR_WIDE | SPR_TALL, C4 | SPR_WIDE | SPR_TALL, C4 | SPR_WIDE | SPR_TALL
        .byte   C4 | SPR_WIDE | SPR_TALL, C4 | SPR_WIDE | SPR_TALL, C4 | SPR_WIDE | SPR_TALL
        .byte   C4, C4, C4, C4, C4, C4, C4
sp_pal: .byte   1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 9, 9, 9, 9, 9, 9
sp_img: .word   IMG_WORD, IMG_WORD + 256, IMG_STR
        .word   IMG_ICON, IMG_ICON + 512, IMG_ICON + 1024, IMG_ICON + 1536, IMG_ICON + 2048, IMG_ICON + 2560
        .word   IMG_STAR, IMG_STAR + 128, IMG_STAR + 256, IMG_STAR, IMG_STAR + 128, IMG_STAR + 256
        .word   IMG_STAR
sp_xo:  .word   0, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
tw_ph:  .word   0, 21, 42

        .segment "DATA"
wblk:   .word   0, 16, 16, 16           ; a small plain window (full screen at once)
        .faraddr t_name
        .byte   WF_PLAIN
fsb:    .byte   FS_320X8, 0             ; 320 x 180, 8 bpp, the bank at fsb + 8
        .word   320, 180, 0
        .byte   0, 0

        .segment "BSS"
ox:     .res    NOBJ * 2                ; position (1/16 pixel)
oy:     .res    NOBJ * 2
olx:    .res    NOBJ * 2                ; the pixel the sprites show
oly:    .res    NOBJ * 2
odx:    .res    NOBJ * 2                ; speed
ody:    .res    NOBJ * 2
oxmax:  .res    NOBJ * 2
oymax:  .res    NOBJ * 2
sbuf:   .res    NSPR * 10               ; spr_set's table
mbuf:   .res    NSPR * 6                ; spr_move's table: {sprite, x, y}
pbuf:   .res    30                      ; the word's 10 colours
tbuf:   .res    27                      ; entries 145-153 (the stars' colours)
ev:     .res    8
msb:    .res    10

        .segment "ZEROPAGE"
seed:   .res    2
fb:     .res    4
win:    .res    2
s0:     .res    2                       ; the first sprite
fc:     .res    2                       ; frames
hph:    .res    2                       ; the word's colour phase
x0:     .res    2                       ; the pointer and the joysticks at the start
y0:     .res    2
j0:     .res    2
wk:     .res    2                       ; woken: 1 by a key (wkey), 2 by a button
wkey:   .res    2
wcnt:   .res    2
t:      .res    2
t2:     .res    2
i:      .res    2
nm:     .res    2                       ; mbuf: its length, its entries
nc:     .res    2
cnt:    .res    2
pos:    .res    2
er:     .res    2
bx:     .res    2
by:     .res    2
