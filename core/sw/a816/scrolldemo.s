; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816: fine scrolling demo for the eye (Marga REV $0B). 640x360x8 window on a 1024 x 512
; virtual bitmap (NV_STRIDE 1024, NV_VHEIGHT 512, HWRAP): 16 x 8 checkered tiles of 64 x 64,
; one hue per column, a black grid, and each tile labelled with its number in hex (row, column:
; "00" to "7F"), all drawn with the blitter (FILL, EXPAND_KEY from a 16x16 font made from 8x8).
; The playfield scrolls for 1200 frames (20 s) on a looping path: the velocity turns in a
; circle once every 256 frames on top of a steady drift (x about 1.25, y about 0.75 pixels a
; frame, up to about 2.7), so it wraps through x 1023 -> 0 and y 511 -> 0 several times; the
; seams should be invisible (labels go 0F -> 00, 7x -> 0x).
; Lines 320 to 359 are a fixed status panel (SPLIT at NV_LINE_CMP 320, second set NV_SCROLLX2 0,
; NV_SCROLLY2 512: the panel lives in rows 512 to 551, below VHEIGHT, so it never wraps). The
; panel shows the frame number and the scroll offsets in use, a block sliding to and fro and a
; progress bar, redrawn by the blitter each frame. Five sprites (a 64x64 and a 32x32 4 bpp
; arrow, three 8 bpp balls, two of them magnified) fly Lissajous paths over playfield and panel.
; Once a second the log gets a status line (frame, offsets, NV_LATE, NV_SPR_STATUS), at the end
; a summary and DONE; the program stops with STP, leaving the last picture on screen.
; Run (from core/): python3 tools/atari.py run816 sw/a816/SCROLLDEMO.BIN --seconds 25
        .p816
        .smart  -

NV_CTRL     = $00D900
NV_BASE     = $00D901
NV_STRIDE   = $00D904
NV_LINE     = $00D906
NV_LINE_CMP = $00D908
NV_LATE     = $00D90B
NV_FRAME    = $00D90C
PAL_IDX     = $00D910
PAL_R       = $00D911
PAL_G       = $00D912
PAL_B       = $00D913
NV_SCROLLX  = $00D930
NV_SCROLLY  = $00D932
NV_SCROLLX2 = $00D934
NV_SCROLLY2 = $00D936
NV_VHEIGHT  = $00D938
NV_SCTL     = $00D93A
NV_SPR_CTRL = $00D940
NV_COMMIT   = $00D941
NV_SPR_STAT = $00D942
NV_SPR      = $00D980
BL_SRC      = $00DA00
BL_SRC_STR  = $00DA03
BL_DST      = $00DA05
BL_DST_STR  = $00DA08
BL_WIDTH    = $00DA0A
BL_HEIGHT   = $00DA0C
BL_FG       = $00DA0E
BL_BG       = $00DA0F
BL_OP       = $00DA11
BL_FLAGS    = $00DA12
BL_CTRL     = $00DA13
SV_CTRL     = $00DC00
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1

FB          = $080000           ; 1024 x 552: rows 0-511 playfield, 512-551 panel
FONT2       = $030000           ; 24 glyphs, 16x16 1 bpp (32 bytes each)
IMG_BALLR   = $030400           ; 8 bpp 16x16
IMG_BALLG   = $030500
IMG_BALLB   = $030600
IMG_ARROW   = $030800           ; 4 bpp 32x32
NFRAMES     = 1200
PANEL       = 512               ; first panel row
SPLITL      = 320               ; first panel line
PANBG       = $82               ; panel background
G_SP        = 23                ; glyph: space

EN = $01
HF = $02
VF = $04
MG = $08
BIG4 = $01 | $10 | $20 | $40    ; 4 bpp 32x32

; direct page
p0          = $20               ; 3
src         = $24
ctp         = $26
fx          = $28
fy          = $2A
fw          = $2C
fh          = $2E
fc          = $30               ; 1: FG
bgc         = $31               ; 1: BG
op          = $32               ; 1: blitter op
addr        = $34               ; 4
srca        = $38               ; 3: blitter source
seed        = $3C
frame       = $3E
tmp         = $40
i           = $42
k           = $44
w           = $46
val         = $48
secs        = $4A
sxa         = $4C               ; scroll x, pixels x 64 (wraps at 1024 pixels)
sya         = $4E               ; scroll y, pixels x 128 (wraps at 512 pixels)
scx         = $50               ; offsets written this frame
scy         = $52
fr0         = $54
sst         = $56               ; 1
tx          = $58
ty          = $5A

.macro print msg
        ldx     #.loword(msg)
        jsr     puts
.endmacro

.macro REC xs, ys, img, pal, ctl
        .word   xs, ys
        .byte   (img & $F0) | pal
        .word   (img >> 8) & $FFFF
        .byte   ctl
.endmacro

        .segment "CODE"
        .a8
        .i16
start:  clc
        xce
        rep     #$10
        sep     #$20
        ldx     #$BFFF
        txs
        pea     $0000
        pld
        phk
        plb
        print   m_hello
        lda     #$04
        sta     f:SV_CTRL               ; classic machine frozen
        lda     #0
        sta     f:NV_CTRL
        sta     f:NV_SPR_CTRL
        ; palette bank 13 for the arrows
        lda     #$D1
        sta     f:PAL_IDX
        ldx     #0
:       lda     pal_fire,x
        sta     f:PAL_R
        lda     pal_fire+1,x
        sta     f:PAL_G
        lda     pal_fire+2,x
        sta     f:PAL_B
        inx
        inx
        inx
        cpx     #45
        bne     :-
        jsr     mkfont
        jsr     mkimages
        jsr     draw
        jsr     panel
        ; display: 1024-byte rows, 512-row ring, split panel at line 320
        rep     #$20
        .a16
        lda     #.loword(FB)
        sta     f:NV_BASE
        lda     #1024
        sta     f:NV_STRIDE
        lda     #512
        sta     f:NV_VHEIGHT
        sta     f:NV_SCROLLY2
        lda     #0
        sta     f:NV_SCROLLX2
        sta     f:NV_SCROLLX
        sta     f:NV_SCROLLY
        lda     #SPLITL
        sta     f:NV_LINE_CMP
        stz     sxa
        stz     sya
        stz     scx
        stz     scy
        sep     #$20
        .a8
        lda     #^FB
        sta     f:NV_BASE+2
        lda     #$03                    ; HWRAP, SPLIT
        sta     f:NV_SCTL
        ; sprite records (positions are set every frame)
        ldx     #0
:       lda     rinit,x
        sta     f:NV_SPR,x
        inx
        cpx     #40
        bne     :-
        lda     #0
:       sta     f:NV_SPR,x              ; 5 to 15 off
        inx
        cpx     #128
        bne     :-
        jsr     waitvbl
        lda     #0
        sta     f:NV_LATE
        lda     #$03
        sta     f:NV_SPR_STAT
        lda     #$01
        sta     f:NV_SPR_CTRL
        sta     f:NV_COMMIT
        sta     f:NV_CTRL               ; ENABLE, 640x360x8, no pointer
        rep     #$20
        .a16
        stz     frame
        stz     secs
        lda     f:NV_FRAME
        sta     fr0
        sep     #$20
        .a8
        stz     sst

; ---- frame loop ----
loop:   jsr     waitvbl
        ; scroll offsets for the next frame (taken at the fetch of line 0)
        rep     #$20
        .a16
        lda     sxa                     ; / 64: 0 to 1023
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        sta     scx
        sta     f:NV_SCROLLX
        lda     sya                     ; / 128: 0 to 511
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        sta     scy
        sta     f:NV_SCROLLY
        sep     #$20
        .a8
:       lda     f:NV_COMMIT             ; PENDING
        and     #$01
        bne     :-
        rep     #$20
        .a16
        ldx     #0
@sp:    lda     spath+4,x               ; x = cx + 2 sin((frame ka) / 4 + pa)
        and     #$00FF
        jsr     fphase
        clc
        adc     spath+6,x
        and     #$00FF
        tay
        jsr     sine
        asl
        clc
        adc     spath,x
        sta     f:NV_SPR,x
        lda     spath+5,x               ; y = cy + sin((frame kb) / 4 + pb)
        and     #$00FF
        jsr     fphase
        clc
        adc     spath+7,x
        and     #$00FF
        tay
        jsr     sine
        clc
        adc     spath+2,x
        sta     f:NV_SPR+2,x
        txa
        clc
        adc     #8
        tax
        cpx     #40
        bne     @sp
        sep     #$20
        .a8
        sta     f:NV_COMMIT
        jsr     panupd
        ; status once a second
        rep     #$20
        .a16
        inc     frame
        inc     secs
        lda     secs
        cmp     #60
        bne     :+
        stz     secs
        sep     #$20
        jsr     status
:       ; the path: velocity turns once in 256 frames on top of a drift
        rep     #$20
        .a16
        lda     frame
        clc
        adc     #64                     ; cos
        and     #$00FF
        tay
        jsr     sine
        sta     tmp                     ; vx = 80 + 3/4 cos (in 1/64 pixel)
        asl
        clc
        adc     tmp
        cmp     #$8000
        ror
        cmp     #$8000
        ror
        clc
        adc     #80
        clc
        adc     sxa
        sta     sxa
        lda     frame
        and     #$00FF
        tay
        jsr     sine
        sta     tmp                     ; vy = 96 + 3/2 sin (in 1/128 pixel)
        cmp     #$8000
        ror
        clc
        adc     tmp
        clc
        adc     #96
        clc
        adc     sya
        sta     sya
        lda     frame
        cmp     #NFRAMES
        sep     #$20
        .a8
        beq     :+
        jmp     loop
:       print   m_sum1
        rep     #$20
        .a16
        lda     frame
        jsr     puthw
        .a8
        print   m_sum2
        rep     #$20
        .a16
        lda     f:NV_FRAME
        sec
        sbc     fr0
        jsr     puthw
        .a8
        print   m_late
        lda     f:NV_LATE
        jsr     puthex
        print   m_sst
        lda     f:NV_SPR_STAT
        ora     sst
        jsr     puthex
        jsr     nl
        print   m_done
        stp

; A (16 bit) = (frame * A) / 4
fphase: .a16
        phy
        tay
        lda     #0
        cpy     #0
        beq     :++
:       clc
        adc     frame
        dey
        bne     :-
:       lsr
        lsr
        ply
        rts

; "T 05 FRAME 012C X 0123 Y 0045 NV_LATE 00 SPR_STATUS 00"
status: .a8
        print   m_t
        rep     #$20
        .a16
        lda     frame
        ldy     #0
:       cmp     #60
        bcc     :+
        sbc     #60
        iny
        bra     :-
:       tya
        sep     #$20
        .a8
        jsr     puthex
        print   m_frame
        rep     #$20
        .a16
        lda     frame
        jsr     puthw
        .a8
        print   m_x
        rep     #$20
        .a16
        lda     scx
        jsr     puthw
        .a8
        print   m_y
        rep     #$20
        .a16
        lda     scy
        jsr     puthw
        .a8
        print   m_late
        lda     f:NV_LATE
        jsr     puthex
        print   m_sst
        lda     f:NV_SPR_STAT
        tsb     sst
        jsr     puthex
        jmp     nl

; ---- the panel: rows 512 to 551 ----
panel:  .a8
        rep     #$20
        .a16
        stz     fx
        lda     #PANEL
        sta     fy
        lda     #640
        sta     fw
        lda     #40
        sta     fh
        sep     #$20
        .a8
        lda     #PANBG
        jsr     fillc
        rep     #$20
        .a16
        lda     #2                      ; a bright edge on top
        sta     fh
        sep     #$20
        .a8
        lda     #$0E
        jsr     fillc
        rep     #$20
        .a16
        lda     #20                     ; progress bar track
        sta     fx
        lda     #PANEL + 34
        sta     fy
        lda     #600
        sta     fw
        lda     #4
        sta     fh
        sep     #$20
        .a8
        lda     #$80
        jsr     fillc
        rep     #$20
        .a16
        lda     #PANEL + 4
        sta     fy
        lda     #16
        sta     fx
        ldx     #.loword(m_title)
        jsr     text
        .a16
        lda     #224
        sta     fx
        ldx     #.loword(m_pframe)
        jsr     text
        .a16
        lda     #416
        sta     fx
        ldx     #.loword(m_px)
        jsr     text
        .a16
        lda     #512
        sta     fx
        ldx     #.loword(m_py)
        jsr     text
        sep     #$20
        .a8
        rts

; per frame: the numbers, the sliding block, the progress bar
panupd: .a8
        rep     #$20
        .a16
        lda     #PANEL + 4
        sta     fy
        lda     #320 + 48
        sta     fx
        lda     frame
        ldy     #4
        jsr     hexd
        lda     #448 + 32
        sta     fx
        lda     scx
        ldy     #3
        jsr     hexd
        lda     #544 + 32
        sta     fx
        lda     scy
        ldy     #3
        jsr     hexd
        stz     fx                      ; the block's track
        lda     #PANEL + 24
        sta     fy
        lda     #640
        sta     fw
        lda     #8
        sta     fh
        sep     #$20
        .a8
        lda     #$84
        jsr     fillc
        rep     #$20
        .a16
        lda     frame                   ; block at 288 + 9/4 sin(2 frame)
        asl
        and     #$00FF
        tay
        jsr     sine
        sta     tmp
        asl
        asl
        asl
        asl
        clc
        adc     tmp
        cmp     #$8000                  ; (s * 17) / 8: -270 to 270
        ror
        cmp     #$8000
        ror
        cmp     #$8000
        ror
        clc
        adc     #288
        sta     fx
        lda     #64
        sta     fw
        sep     #$20
        .a8
        lda     #$1E
        jsr     fillc
        rep     #$20
        .a16
        lda     frame                   ; progress: frame / 2 pixels
        lsr
        inc
        sta     fw
        lda     #20
        sta     fx
        lda     #PANEL + 34
        sta     fy
        lda     #4
        sta     fh
        sep     #$20
        .a8
        lda     #$C8
        jmp     fillc

; draw the Y low hex digits of A (16 bit) right to left ending in the cell at fx; .a16
hexd:   .a16
        sta     val
@d:     lda     val
        and     #$000F
        jsr     glyph
        .a16
        lsr     val
        lsr     val
        lsr     val
        lsr     val
        lda     fx
        sec
        sbc     #16
        sta     fx
        dey
        bne     @d
        rts

; text at (fx, fy), white on the panel colour; X = string. .a16 in and out
text:   .a16
        sep     #$20
        .a8
        lda     a:0,x
        beq     @e
        jsr     gidx
        rep     #$20
        .a16
        and     #$00FF
        phx
        jsr     glyph
        .a16
        plx
        inx
        lda     fx
        clc
        adc     #16
        sta     fx
        bra     text
@e:     rep     #$20
        .a16
        rts

; A = ASCII -> glyph number (8 bit)
gidx:   .a8
        cmp     #' '
        beq     @sp
        cmp     #'A'
        bcs     @l
        sec
        sbc     #'0'
        rts
@l:     cmp     #'G'
        bcs     @x
        sbc     #'A' - 10 - 1           ; carry clear here
        rts
@x:     phx
        ldx     #0
:       cmp     gextra,x
        beq     :+
        inx
        cpx     #7
        bne     :-
:       txa
        clc
        adc     #16
        plx
        rts
@sp:    lda     #G_SP
        rts

; glyph A (16 bit) at (fx, fy): EXPAND, white on the panel colour. Returns .a16
glyph:  .a16
        asl
        asl
        asl
        asl
        asl
        clc
        adc     #.loword(FONT2)
        sta     srca
        lda     #16
        sta     fw
        sta     fh
        sep     #$20
        .a8
        lda     #^FONT2
        sta     srca+2
        lda     #$0F
        sta     fc
        lda     #PANBG
        sta     bgc
        lda     #3                      ; EXPAND
        sta     op
        jsr     blit
        rep     #$20
        .a16
        rts

; FILL fw x fh at (fx, fy) with colour A
fillc:  .a8
        sta     fc
        stz     op
; any blit at (fx, fy) of the 1024-byte-row bitmap, fw x fh, from srca (stride 2), fc, bgc, op
blit:   .a8
        rep     #$20
        .a16
        lda     fy
        sta     addr
        stz     addr+2
        phx
        ldx     #10
:       asl     addr
        rol     addr+2
        dex
        bne     :-
        plx
        lda     addr
        clc
        adc     fx
        sta     addr
        lda     addr+2
        clc
        adc     #^FB
        sta     addr+2
        sep     #$20
        .a8
        jsr     bwait
        rep     #$20
        .a16
        lda     srca
        sta     f:BL_SRC
        lda     #2
        sta     f:BL_SRC_STR
        lda     addr
        sta     f:BL_DST
        lda     #1024
        sta     f:BL_DST_STR
        lda     fw
        sta     f:BL_WIDTH
        lda     fh
        sta     f:BL_HEIGHT
        sep     #$20
        .a8
        lda     srca+2
        sta     f:BL_SRC+2
        lda     addr+2
        sta     f:BL_DST+2
        lda     fc
        sta     f:BL_FG
        lda     bgc
        sta     f:BL_BG
        lda     op
        sta     f:BL_OP
        lda     #$70                    ; SRC_BIT 7 (leftmost)
        sta     f:BL_FLAGS
        lda     #$01
        sta     f:BL_CTRL
        rts
bwait:  .a8
        lda     f:BL_CTRL
        and     #$01
        bne     bwait
        rts

; ---- the playfield: tiles, grid, labels ----
draw:   .a8
        rep     #$20
        .a16
        lda     #64
        sta     fw
        sta     fh
        stz     ty
@ty:    stz     tx
@tx:    lda     tx
        xba
        lsr
        lsr
        sta     fx                      ; tx * 64
        lda     ty
        xba
        lsr
        lsr
        sta     fy
        ldx     tx
        sep     #$20
        .a8
        lda     tx                      ; hue of the column, luminance 4 or 8 (checker)
        eor     ty
        and     #$01
        asl
        asl
        ora     #$04
        ora     huetab,x
        jsr     fillc
        rep     #$20
        .a16
        inc     tx
        lda     tx
        cmp     #16
        bne     @tx
        inc     ty
        lda     ty
        cmp     #8
        bne     @ty
        ; grid: black lines 2 pixels wide every 64
        stz     fx
        lda     #1024
        sta     fw
        lda     #2
        sta     fh
        stz     fy
:       sep     #$20
        .a8
        lda     #0
        jsr     fillc
        rep     #$20
        .a16
        lda     fy
        clc
        adc     #64
        sta     fy
        cmp     #512
        bne     :-
        stz     fy
        lda     #2
        sta     fw
        lda     #512
        sta     fh
        stz     fx
:       sep     #$20
        .a8
        lda     #0
        jsr     fillc
        rep     #$20
        .a16
        lda     fx
        clc
        adc     #64
        sta     fx
        cmp     #1024
        bne     :-
        ; labels: row and column in hex, shadow then white, EXPAND_KEY
        stz     ty
@ly:    stz     tx
@lx:    lda     #$00                    ; shadow
        jsr     label
        lda     #$0F
        jsr     label
        inc     tx
        lda     tx
        cmp     #16
        bne     @lx
        inc     ty
        lda     ty
        cmp     #8
        bne     @ly
        sep     #$20
        .a8
        jmp     bwait

; label of tile (tx, ty) in colour A (0: shadow, 2 pixels down-right); .a16
label:  .a16
        sta     tmp
        lda     tx
        xba
        lsr
        lsr
        clc
        adc     #16
        sta     fx
        lda     ty
        xba
        lsr
        lsr
        clc
        adc     #24
        sta     fy
        lda     tmp
        bne     :+
        inc     fx
        inc     fx
        inc     fy
        inc     fy
:       lda     ty
        jsr     lglyph
        lda     fx
        clc
        adc     #16
        sta     fx
        lda     tx
        jmp     lglyph

; glyph A at (fx, fy) in colour tmp, EXPAND_KEY; .a16 in and out
lglyph: .a16
        asl
        asl
        asl
        asl
        asl
        clc
        adc     #.loword(FONT2)
        sta     srca
        lda     #16
        sta     fw
        sta     fh
        sep     #$20
        .a8
        lda     #^FONT2
        sta     srca+2
        lda     tmp
        sta     fc
        lda     #4                      ; EXPAND_KEY
        sta     op
        jsr     blit
        rep     #$20
        .a16
        rts

; ---- 16x16 font from the 8x8 one: every bit and every row doubled ----
mkfont: .a8
        rep     #$20
        .a16
        lda     #.loword(FONT2)
        sta     p0
        stz     i
        sep     #$20
        .a8
        lda     #^FONT2
        sta     p0+2
@r:     ldx     i
        lda     font8,x
        sta     tmp
        ldx     #8
:       asl     tmp
        rep     #$20
        .a16
        php
        rol     w
        plp
        rol     w
        sep     #$20
        .a8
        dex
        bne     :-
        ldy     #0
        lda     w+1
        sta     [p0],y
        iny
        lda     w
        sta     [p0],y
        iny
        lda     w+1
        sta     [p0],y
        iny
        lda     w
        sta     [p0],y
        rep     #$20
        .a16
        lda     p0
        clc
        adc     #4
        sta     p0
        inc     i
        lda     i
        cmp     #24 * 8
        sep     #$20
        .a8
        bne     @r
        rts

; ---- sprite images ----
mkimages:
        .a8
        lda     #^IMG_BALLR
        sta     p0+2
        rep     #$20
        .a16
        lda     #.loword(art_ball)
        sta     src
        lda     #.loword(ct_red)
        sta     ctp
        lda     #.loword(IMG_BALLR)
        sta     p0
        jsr     mk8
        lda     #.loword(ct_green)
        sta     ctp
        lda     #.loword(IMG_BALLG)
        sta     p0
        jsr     mk8
        lda     #.loword(ct_blue)
        sta     ctp
        lda     #.loword(IMG_BALLB)
        sta     p0
        jsr     mk8
        lda     #.loword(art_arrow)
        sta     src
        lda     #.loword(IMG_ARROW)
        sta     p0
        jsr     mk4
        sep     #$20
        .a8
        rts

; 16x16 chars at (src) -> 8 bpp at [p0] through the colour table at (ctp); .a16 in and out
mk8:    .a16
        sep     #$20
        .a8
        ldy     #0
@l:     lda     (src),y
        jsr     cval
        beq     @z
        phy
        rep     #$20
        .a16
        and     #$000F
        tay
        sep     #$20
        .a8
        lda     (ctp),y
        ply
@z:     sta     [p0],y
        iny
        cpy     #256
        bne     @l
        rep     #$20
        .a16
        rts

; 32x32 chars at (src) -> 4 bpp at [p0]; .a16 in and out
mk4:    .a16
        sep     #$20
        .a8
        ldy     #0
@l:     lda     (src),y
        jsr     cval
        asl
        asl
        asl
        asl
        sta     tmp
        iny
        lda     (src),y
        jsr     cval
        ora     tmp
        sta     [p0]
        rep     #$20
        .a16
        inc     p0
        sep     #$20
        .a8
        iny
        cpy     #1024
        bne     @l
        rep     #$20
        .a16
        rts

; A = art char ('.', '0'-'9', 'A'-'F') -> 0..15, Z set for 0
cval:   .a8
        cmp     #'.'
        beq     @z
        cmp     #'A'
        bcs     @h
        sec
        sbc     #'0'
        rts
@h:     sbc     #'A' - 10
        rts
@z:     lda     #0
        rts

; A (16 bit) = sine256[Y], sign-extended
sine:   .a16
        lda     sine256,y
        and     #$00FF
        eor     #$0080
        sec
        sbc     #$0080
        rts

waitvbl:
        .a8
:       rep     #$20
        .a16
        lda     f:NV_LINE
        cmp     #360
        sep     #$20
        .a8
        bcs     :-
:       rep     #$20
        .a16
        lda     f:NV_LINE
        cmp     #360
        sep     #$20
        .a8
        bcc     :-
        rts

puthw:  .a16                            ; A (16 bit) in hex; returns .a8
        pha
        xba
        sep     #$20
        .a8
        jsr     puthex
        rep     #$20
        .a16
        pla
        sep     #$20
        .a8
puthex: pha
        lsr
        lsr
        lsr
        lsr
        jsr     nib
        pla
        and     #$0F
nib:    cmp     #10
        bcc     :+
        adc     #6
:       adc     #$30
        bra     putc
nl:     lda     #10
putc:   pha
:       lda     f:DBG_STAT
        bmi     :-
        pla
        sta     f:DBG_OUT
        rts
puts:   lda     a:0,x
        beq     :+
        jsr     putc
        inx
        bra     puts
:       rts

m_hello: .byte "SCROLLDEMO: 1024X512 WRAPPING PLAYFIELD, PANEL SPLIT AT LINE 320, 5 SPRITES, 1200 FRAMES", 10, 0
m_t:     .byte "T ", 0
m_frame: .byte " FRAME ", 0
m_x:     .byte " X ", 0
m_y:     .byte " Y ", 0
m_late:  .byte " NV_LATE ", 0
m_sst:   .byte " SPR_STATUS ", 0
m_sum1:  .byte "SUMMARY FRAMES ", 0
m_sum2:  .byte " VBLANKS ", 0
m_done:  .byte "DONE", 10, 0
; panel text (glyphs: 0-9, A-F and the letters of gextra)
m_title: .byte "SCROLL DEMO", 0
m_pframe: .byte "FRAME", 0
m_px:    .byte "X", 0
m_py:    .byte "Y", 0
gextra:  .byte "LMORSXY"

; sprites 0-4: records, then the paths (cx, cy, ka, kb, pa, pb):
; x = cx + 2 sin(frame ka / 4 + pa), y = cy + sin(frame kb / 4 + pb), in 1/256 turns
rinit:  REC     0, 0, IMG_ARROW, 13, BIG4 | MG          ; 0 64x64
        REC     0, 0, IMG_BALLR,  0, EN | MG            ; 1 32x32
        REC     0, 0, IMG_BALLG,  0, EN | MG            ; 2 32x32
        REC     0, 0, IMG_ARROW, 13, BIG4 | HF | VF     ; 3 32x32, points down-left
        REC     0, 0, IMG_BALLB,  0, EN                 ; 4 16x16
spath:  .word   288, 130
        .byte   2, 3,   0,   0
        .word   304, 150
        .byte   3, 4,  64,  32
        .word   304, 250
        .byte   4, 3, 128, 100
        .word   304, 160
        .byte   3, 3, 192,   0
        .word   312, 170
        .byte   5, 5,  64,   0

huetab: .byte   $10, $20, $30, $40, $50, $60, $70, $80, $90, $A0, $B0, $C0, $E0, $F0, $40, $80

;                0    1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
ct_red:   .byte $00, $40, $41, $42, $43, $44, $45, $46, $47, $48, $49, $4A, $4B, $4C, $4D, $0F
ct_green: .byte $00, $C0, $C1, $C2, $C3, $C4, $C5, $C6, $C7, $C8, $C9, $CA, $CB, $CC, $CD, $0F
ct_blue:  .byte $00, $80, $81, $82, $83, $84, $85, $86, $87, $88, $89, $8A, $8B, $8C, $8D, $0F

pal_fire:
        .byte   $3C, $00, $00, $49, $11, $05, $57, $22, $0B, $65, $33, $11, $73, $44, $16
        .byte   $81, $55, $1C, $8F, $66, $22, $9D, $78, $28, $AB, $89, $2D, $B9, $9A, $33
        .byte   $C7, $AB, $39, $D5, $BC, $3E, $E3, $CD, $44, $F1, $DE, $4A, $FF, $F0, $50

; 8x8 font, leftmost pixel in bit 7: 0-9, A-F, L, M, O, R, S, X, Y, space
font8:  .byte   $3C, $66, $6E, $76, $66, $66, $3C, $00
        .byte   $18, $38, $18, $18, $18, $18, $7E, $00
        .byte   $3C, $66, $06, $0C, $18, $30, $7E, $00
        .byte   $3C, $66, $06, $1C, $06, $66, $3C, $00
        .byte   $0C, $1C, $3C, $6C, $7E, $0C, $0C, $00
        .byte   $7E, $60, $7C, $06, $06, $66, $3C, $00
        .byte   $3C, $60, $7C, $66, $66, $66, $3C, $00
        .byte   $7E, $06, $0C, $18, $30, $30, $30, $00
        .byte   $3C, $66, $66, $3C, $66, $66, $3C, $00
        .byte   $3C, $66, $66, $3E, $06, $0C, $38, $00
        .byte   $18, $3C, $66, $66, $7E, $66, $66, $00
        .byte   $7C, $66, $66, $7C, $66, $66, $7C, $00
        .byte   $3C, $66, $60, $60, $60, $66, $3C, $00
        .byte   $78, $6C, $66, $66, $66, $6C, $78, $00
        .byte   $7E, $60, $60, $7C, $60, $60, $7E, $00
        .byte   $7E, $60, $60, $7C, $60, $60, $60, $00
        .byte   $60, $60, $60, $60, $60, $60, $7E, $00
        .byte   $63, $77, $7F, $6B, $63, $63, $63, $00
        .byte   $3C, $66, $66, $66, $66, $66, $3C, $00
        .byte   $7C, $66, $66, $7C, $6C, $66, $66, $00
        .byte   $3C, $66, $60, $3C, $06, $66, $3C, $00
        .byte   $66, $66, $3C, $18, $3C, $66, $66, $00
        .byte   $66, $66, $66, $3C, $18, $18, $18, $00
        .byte   $00, $00, $00, $00, $00, $00, $00, $00

        .include "sine256.inc"

art_ball:                               ; lit from the top left
        .byte   ".......BA......."
        .byte   "....DEEDDBA7...."
        .byte   "...EFFFEDCB96..."
        .byte   "..EFFFFEDCB974.."
        .byte   ".DFFFFFEDCB9751."
        .byte   ".DEFFFEEDCA9752."
        .byte   ".DEEEEEDCBA8641."
        .byte   "9CDDDDDCBA975311"
        .byte   "8BCCCCCBA9864211"
        .byte   ".ABBBBAA9865311."
        .byte   ".89AA9987653211."
        .byte   ".57888766432111."
        .byte   "..456654421111.."
        .byte   "...2333211111..."
        .byte   "....11111111...."
        .byte   ".......11......."
art_arrow:                              ; points up-right
        .byte   "................................"
        .byte   "............................FFF."
        .byte   ".....................FFFFFFFCDF."
        .byte   "..............FFFFFFFBBBBCCCCCF."
        .byte   "...........FFF99AAAAABBBBBCCCF.."
        .byte   "............F9999AAAAABBBBBCCF.."
        .byte   ".............F9999AAAAABBBBBCF.."
        .byte   "..............F9999AAAAABBBBBF.."
        .byte   "...............F9999AAAAABBBBF.."
        .byte   "................F9999AAAAABBBF.."
        .byte   ".................F9999AAAAABBF.."
        .byte   "................F889999AAAAAF..."
        .byte   "...............F88889999AAAAF..."
        .byte   "..............F7888889999AAAF..."
        .byte   ".............F7778888F9999AAF..."
        .byte   "............F7777788F.F9999AF..."
        .byte   "...........F6677777F...F9999F..."
        .byte   "..........F6666777F.....F999F..."
        .byte   ".........F5666667F.......F9F...."
        .byte   "........F5556666F.........FF...."
        .byte   ".......F4555566F...........F...."
        .byte   "......F4445555F................."
        .byte   ".....F4444455F.................."
        .byte   "....F3344444F..................."
        .byte   "...F3333444F...................."
        .byte   "..F2333334F....................."
        .byte   ".F2223333F......................"
        .byte   "F2222233F......................."
        .byte   "F122222F........................"
        .byte   "F11222F........................."
        .byte   "F1112F.........................."
        .byte   ".FFFF..........................."
