; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816: sprite demo for the eye (Marga REV $0B). 640x360x8, a picture of black space with
; stars, six shaded pillars, a girder and a striped ground, drawn with the blitter (FILL). Over it
; all 16 sprites fly for 1200 frames (20 s at 60 fps), each on a straight path with a small
; sine wobble, at 0.6 to 1.9 pixels a frame, wrapping from x 704 to -64 and from y 440 to -80,
; so every sprite leaves and re-enters through all four edges:
;   - 8 bpp 16x16: a fish (two colourings) and a flag; flipped ones swim/point the other way,
;     two fish are magnified (32x32);
;   - 4 bpp 32x32: an arrow (up-right, flipped to point along its path) and a sailing boat, in
;     palette banks 12 (fire), 13 (sea), 14 (leaf) and 15 (a rainbow that cycles every 3 frames);
;     two of them magnified to 64x64;
;   - sprites 10 (arrow) and 11 (magnified flag) are BEHIND: they show only over black space and
;     disappear behind the pillars, the girder, the ground and every star.
; The hardware pointer (32x32, 2 bpp) runs a Lissajous path on top of everything. Each frame,
; in vertical blank, the program writes the 16 X/Y pairs and NV_SPR_COMMIT. Once a second it
; prints a status line (frame, NV_LATE, NV_SPR_STATUS), at the end a summary and DONE, and it
; stops with STP, leaving the last picture on screen. NV_LATE and the LATE bit should stay 0;
; OVERFLOW too (the widest line is 480 sprite pixels).
; Run (from core/): python3 tools/atari.py run816 sw/a816/SPRDEMO.BIN --seconds 25
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
PTR_X       = $00D920
PTR_Y       = $00D922
PTR_HOT     = $00D924
PTR_IMG     = $00D925
PTR_C1      = $00D928
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
BL_DST      = $00DA05
BL_DST_STR  = $00DA08
BL_WIDTH    = $00DA0A
BL_HEIGHT   = $00DA0C
BL_FG       = $00DA0E
BL_OP       = $00DA11
BL_FLAGS    = $00DA12
BL_CTRL     = $00DA13
SV_CTRL     = $00DC00
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1

FB          = $080000           ; 640 x 360 bitmap
IMG_FISHA   = $030000           ; 8 bpp 16x16, 256 bytes each
IMG_FISHB   = $030100
IMG_FLAGA   = $030200
IMG_FLAGB   = $030300
IMG_ARROW   = $030400           ; 4 bpp 32x32, 512 bytes each
IMG_BOAT    = $030600
IMG_PTR     = $030800           ; pointer, 2 bpp 32x32, 256 bytes
NFRAMES     = 1200
XSPAN       = 768               ; x runs -64 .. 703
YSPAN       = 520               ; y runs -80 .. 439 (+-8 wobble)

; sprite CTRL bits
EN = $01
HF = $02
VF = $04
MG = $08
WD = $10
TL = $20
B4 = $40
BH = $80
BIG4 = EN | WD | TL | B4        ; 4 bpp 32x32

; direct page
p0          = $20               ; 3: 24-bit pointer
src         = $24               ; 2: art (bank $01)
ctp         = $26               ; 2: colour table (bank $01)
fx          = $28
fy          = $2A
fw          = $2C
fh          = $2E
fc          = $30               ; 1
hue         = $31               ; 1
addr        = $32               ; 4
seed        = $36
frame       = $38
tmp         = $3A
tmp2        = $3C
i           = $3E
k           = $40
px0         = $42
cyc         = $44               ; rainbow offset * 3
secs        = $46
late        = $48               ; 1: NV_LATE at the last check
sst         = $49               ; 1: NV_SPR_STATUS, all bits seen
fr0         = $4A               ; NV_FRAME at the start
waits       = $4C               ; frames that found COMMIT still pending

.macro print msg
        ldx     #.loword(msg)
        jsr     puts
.endmacro

; one sprite record: start position, image, palette bank, CTRL
.macro REC xs, ys, img, pal, ctl
        .word   xs, ys
        .byte   (img & $F0) | pal
        .word   (img >> 8) & $FFFF
        .byte   ctl
.endmacro

; velocity of one sprite, padded to the 8-byte stride of the records
.macro VEL vx, vy
        .word   (vx) & $FFFF, (vy) & $FFFF, 0, 0
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
        sta     f:NV_CTRL               ; display off while drawing
        sta     f:NV_SPR_CTRL
        rep     #$20
        .a16
        lda     #$ACE1
        sta     seed
        stz     waits
        sep     #$20
        .a8
        jsr     setpal
        jsr     mkimages
        jsr     draw
        ; display: 640x360x8 at FB, no scrolling
        rep     #$20
        .a16
        lda     #.loword(FB)
        sta     f:NV_BASE
        lda     #640
        sta     f:NV_STRIDE
        lda     #0
        sta     f:NV_SCROLLX
        sta     f:NV_SCROLLY
        sta     f:NV_SCROLLX2
        sta     f:NV_SCROLLY2
        sta     f:NV_VHEIGHT
        lda     #511
        sta     f:NV_LINE_CMP
        lda     #320
        sta     f:PTR_X
        lda     #180
        sta     f:PTR_Y
        lda     #.loword(IMG_PTR)
        sta     f:PTR_IMG
        sep     #$20
        .a8
        lda     #^FB
        sta     f:NV_BASE+2
        lda     #0
        sta     f:NV_SCTL
        sta     f:PTR_HOT               ; hot spot at the tip
        lda     #^IMG_PTR
        sta     f:PTR_IMG+2
        lda     #$00                    ; outline black, body white, 3 unused
        sta     f:PTR_C1
        lda     #$0F
        sta     f:PTR_C1+1
        lda     #$46
        sta     f:PTR_C1+2
        ; records and the motion state
        rep     #$20
        .a16
        ldx     #0
@ri:    lda     rinit,x
        sta     f:NV_SPR,x
        clc
        adc     #64
        asl
        asl
        asl
        asl
        sta     state,x                 ; (x + 64) * 16
        lda     rinit+2,x
        sta     f:NV_SPR+2,x
        clc
        adc     #80
        asl
        asl
        asl
        asl
        sta     state+2,x               ; (y + 80) * 16
        lda     rinit+4,x
        sta     f:NV_SPR+4,x
        lda     rinit+6,x
        sta     f:NV_SPR+6,x
        lda     vinit,x
        sta     state+4,x
        lda     vinit+2,x
        sta     state+6,x
        txa
        clc
        adc     #8
        tax
        cpx     #128
        bne     @ri
        sep     #$20
        .a8
        jsr     waitvbl
        lda     #0
        sta     f:NV_LATE               ; any write clears
        lda     #$03
        sta     f:NV_SPR_STAT           ; W1C
        lda     #$01
        sta     f:NV_SPR_CTRL
        sta     f:NV_COMMIT
        lda     #$09                    ; ENABLE, 640x360x8, POINTER_EN
        sta     f:NV_CTRL
        rep     #$20
        .a16
        stz     frame
        stz     cyc
        stz     secs
        lda     f:NV_FRAME
        sta     fr0
        sep     #$20
        .a8
        stz     late
        stz     sst

; ---- the frame loop: in vertical blank write records, COMMIT, pointer, palette; then move ----
loop:   jsr     waitvbl
        lda     f:NV_COMMIT             ; PENDING (never expected here)
        and     #$01
        beq     :+
        rep     #$20
        inc     waits
        sep     #$20
:       lda     f:NV_COMMIT
        and     #$01
        bne     :-
        rep     #$20
        .a16
        ldx     #0
@wr:    lda     state,x                 ; x = state / 16 - 64
        lsr
        lsr
        lsr
        lsr
        sec
        sbc     #64
        sta     f:NV_SPR,x
        lda     state+2,x               ; y = state / 16 - 80 + wobble
        lsr
        lsr
        lsr
        lsr
        sec
        sbc     #80
        sta     tmp
        txa
        asl
        clc
        adc     frame
        adc     frame
        and     #$00FF
        tay
        jsr     sine                    ; -127..127
        cmp     #$8000                  ; / 16: -8..7
        ror
        cmp     #$8000
        ror
        cmp     #$8000
        ror
        cmp     #$8000
        ror
        clc
        adc     tmp
        sta     f:NV_SPR+2,x
        txa
        clc
        adc     #8
        tax
        cpx     #128
        bne     @wr
        sep     #$20
        .a8
        sta     f:NV_COMMIT
        ; pointer: Lissajous 2:3
        rep     #$20
        .a16
        lda     frame
        and     #$00FF
        tay
        jsr     sine
        asl
        clc
        adc     #320
        sta     f:PTR_X
        lda     frame
        asl
        clc
        adc     frame
        lsr
        and     #$00FF
        tay
        jsr     sine
        clc
        adc     #176
        sta     f:PTR_Y
        sep     #$20
        .a8
        ; bank 15 rainbow: rotate one step every 3 frames
        rep     #$20
        .a16
        lda     frame
:       cmp     #3
        bcc     :+
        sbc     #3
        bra     :-
:       sep     #$20
        .a8
        cmp     #0
        bne     @nocyc
        lda     #$F1
        sta     f:PAL_IDX
        ldx     cyc
        ldy     #15
:       lda     pal_rainbow,x
        sta     f:PAL_R
        lda     pal_rainbow+1,x
        sta     f:PAL_G
        lda     pal_rainbow+2,x
        sta     f:PAL_B
        inx
        inx
        inx
        cpx     #45
        bne     :+
        ldx     #0
:       dey
        bne     :--
        rep     #$20
        .a16
        lda     cyc
        clc
        adc     #3
        cmp     #45
        bne     :+
        lda     #0
:       sta     cyc
        sep     #$20
        .a8
@nocyc:
        ; move every sprite for the next frame, wrapping at the spans
        rep     #$20
        .a16
        ldx     #0
@mv:    lda     state,x
        clc
        adc     state+4,x
        bpl     :+
        clc
        adc     #XSPAN * 16
        bra     :++
:       cmp     #XSPAN * 16
        bcc     :+
        sbc     #XSPAN * 16
:       sta     state,x
        lda     state+2,x
        clc
        adc     state+6,x
        bpl     :+
        clc
        adc     #YSPAN * 16
        bra     :++
:       cmp     #YSPAN * 16
        bcc     :+
        sbc     #YSPAN * 16
:       sta     state+2,x
        txa
        clc
        adc     #8
        tax
        cpx     #128
        bne     @mv
        inc     frame
        inc     secs
        lda     secs
        cmp     #60
        sep     #$20
        .a8
        bne     :+
        rep     #$20
        stz     secs
        sep     #$20
        jsr     status
:       rep     #$20
        .a16
        lda     frame
        cmp     #NFRAMES
        sep     #$20
        .a8
        beq     :+
        jmp     loop
        ; summary
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
        print   m_waits
        rep     #$20
        .a16
        lda     waits
        jsr     puthw
        .a8
        jsr     nl
        print   m_done
        stp

; "T 05 FRAME 012C NV_LATE 00 SPR_STATUS 00"
status: print   m_t
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
        print   m_late
        lda     f:NV_LATE
        sta     late
        jsr     puthex
        print   m_sst
        lda     f:NV_SPR_STAT
        tsb     sst
        jsr     puthex
        jmp     nl

; A (16 bit) = sine256[Y], sign-extended to 16 bits
sine:   .a16
        lda     sine256,y
        and     #$00FF
        eor     #$0080
        sec
        sbc     #$0080
        rts
        .a8

; ---- palette banks 12 to 15 (entries $C1-$CF, $D1-$DF, $E1-$EF, $F1-$FF) ----
setpal: lda     #$C1
        ldx     #.loword(pal_fire)
        jsr     bank15
        lda     #$D1
        ldx     #.loword(pal_sea)
        jsr     bank15
        lda     #$E1
        ldx     #.loword(pal_leaf)
        jsr     bank15
        lda     #$F1
        ldx     #.loword(pal_rainbow)
bank15: sta     f:PAL_IDX
        ldy     #15
:       lda     a:0,x
        sta     f:PAL_R
        lda     a:1,x
        sta     f:PAL_G
        lda     a:2,x
        sta     f:PAL_B
        inx
        inx
        inx
        dey
        bne     :-
        rts

; ---- sprite and pointer images from the ASCII art below ----
mkimages:
        lda     #^IMG_FISHA
        sta     p0+2
        rep     #$20
        .a16
        lda     #.loword(art_fish)
        sta     src
        lda     #.loword(ct_fisha)
        sta     ctp
        lda     #.loword(IMG_FISHA)
        sta     p0
        jsr     mk8
        .a16
        lda     #.loword(ct_fishb)
        sta     ctp
        lda     #.loword(IMG_FISHB)
        sta     p0
        jsr     mk8
        .a16
        lda     #.loword(art_flag)
        sta     src
        lda     #.loword(ct_flaga)
        sta     ctp
        lda     #.loword(IMG_FLAGA)
        sta     p0
        jsr     mk8
        .a16
        lda     #.loword(ct_flagb)
        sta     ctp
        lda     #.loword(IMG_FLAGB)
        sta     p0
        jsr     mk8
        .a16
        lda     #.loword(art_arrow)
        sta     src
        lda     #.loword(IMG_ARROW)
        sta     p0
        jsr     mk4
        .a16
        lda     #.loword(art_boat)
        sta     src
        lda     #.loword(IMG_BOAT)
        sta     p0
        jsr     mk4
        .a16
        lda     #.loword(art_ptr)
        sta     src
        lda     #.loword(IMG_PTR)
        sta     p0
        jsr     mk2
        sep     #$20
        .a8
        rts

; 16x16 chars at (src) -> 8 bpp at [p0] through the colour table at (ctp). Called and returns .a16
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

; 32x32 chars at (src) -> 4 bpp at [p0] (512 bytes). Called and returns .a16
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

; 32x32 chars at (src) -> 2 bpp at [p0] (256 bytes, leftmost pixel in bits 7-6). .a16
mk2:    .a16
        sep     #$20
        .a8
        ldy     #0
@b:     stz     tmp
        ldx     #4
@p:     lda     tmp
        asl
        asl
        sta     tmp
        lda     (src),y
        jsr     cval
        ora     tmp
        sta     tmp
        iny
        dex
        bne     @p
        lda     tmp
        sta     [p0]
        rep     #$20
        .a16
        inc     p0
        sep     #$20
        .a8
        cpy     #1024
        bne     @b
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

; ---- the picture ----
draw:   .a8
        rep     #$20
        .a16
        stz     fx                      ; clear to colour 0
        stz     fy
        lda     #640
        sta     fw
        lda     #360
        sta     fh
        sep     #$20
        .a8
        stz     fc
        jsr     fill
        jsr     bwait
        ; stars: 500 pixels at random offsets of the 230,400-byte bitmap
        rep     #$20
        .a16
        lda     #500
        sta     i
@st:    jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed
        sta     p0
        jsr     rnd
        .a8
        lda     seed
        and     #$03
        clc
        adc     #^FB
        sta     p0+2
        cmp     #^FB + 3
        bne     :+
        lda     p0+1
        cmp     #$84                    ; past $0B:8400: outside
        bcs     @ns
:       rep     #$20
        .a16
        lda     seed
        xba
        and     #$0003
        tax
        sep     #$20
        .a8
        lda     starc,x
        sta     [p0]
@ns:    rep     #$20
        .a16
        dec     i
        bne     @st
        ; girder across the picture, behind the pillars
        stz     fx
        lda     #170
        sta     fy
        lda     #640
        sta     fw
        lda     #10
        sta     fh
        sep     #$20
        .a8
        lda     #$24
        sta     fc
        jsr     fill
        rep     #$20
        .a16
        lda     #2
        sta     fh
        sep     #$20
        .a8
        lda     #$2A
        sta     fc
        jsr     fill
        ; ground: 15 bands of 2 lines, gold getting brighter
        rep     #$20
        .a16
        lda     #330
        sta     fy
        stz     i
@gr:    lda     i
        sep     #$20
        .a8
        lsr
        clc
        adc     #$12                    ; $12 to $19
        sta     fc
        jsr     fill
        rep     #$20
        .a16
        inc     fy
        inc     fy
        inc     i
        lda     i
        cmp     #15
        bne     @gr
        ; six pillars of ten 4-pixel strips, with a cap and a base
        stz     i
@pi:    lda     i
        asl
        tax
        lda     pillx,x
        sta     px0
        ldx     i
        sep     #$20
        .a8
        lda     pillh,x
        sta     hue
        rep     #$20
        .a16
        lda     #60
        sta     fy
        lda     #4
        sta     fw
        lda     #270
        sta     fh
        stz     k
@sp:    lda     k
        asl
        asl
        clc
        adc     px0
        sta     fx
        ldx     k
        sep     #$20
        .a8
        lda     lumtab,x
        ora     hue
        sta     fc
        jsr     fill
        rep     #$20
        .a16
        inc     k
        lda     k
        cmp     #10
        bne     @sp
        lda     px0                     ; cap
        sec
        sbc     #8
        sta     fx
        lda     #48
        sta     fy
        lda     #56
        sta     fw
        lda     #12
        sta     fh
        sep     #$20
        .a8
        lda     hue
        ora     #$0C
        sta     fc
        jsr     fill
        rep     #$20
        .a16
        lda     #50                     ; cap highlight
        sta     fy
        lda     #2
        sta     fh
        sep     #$20
        .a8
        lda     hue
        ora     #$0E
        sta     fc
        jsr     fill
        rep     #$20
        .a16
        lda     px0                     ; base
        sec
        sbc     #6
        sta     fx
        lda     #318
        sta     fy
        lda     #52
        sta     fw
        lda     #12
        sta     fh
        sep     #$20
        .a8
        lda     hue
        ora     #$06
        sta     fc
        jsr     fill
        rep     #$20
        .a16
        inc     i
        lda     i
        cmp     #6
        beq     :+
        jmp     @pi
:       sep     #$20
        .a8
        jmp     bwait

; blitter FILL of fw x fh at (fx, fy) with colour fc, stride 640
fill:   .a8
        rep     #$20
        .a16
        lda     fx
        sta     addr
        stz     addr+2
        ldx     fy
        beq     @d
@m:     lda     addr
        clc
        adc     #640
        sta     addr
        bcc     :+
        inc     addr+2
:       dex
        bne     @m
@d:     lda     addr+2
        clc
        adc     #^FB
        sta     addr+2
        sep     #$20
        .a8
        jsr     bwait
        rep     #$20
        .a16
        lda     addr
        sta     f:BL_DST
        lda     #640
        sta     f:BL_DST_STR
        lda     fw
        sta     f:BL_WIDTH
        lda     fh
        sta     f:BL_HEIGHT
        sep     #$20
        .a8
        lda     addr+2
        sta     f:BL_DST+2
        lda     fc
        sta     f:BL_FG
        lda     #0                      ; FILL
        sta     f:BL_OP
        sta     f:BL_FLAGS
        lda     #$01
        sta     f:BL_CTRL               ; START
        rts
bwait:  lda     f:BL_CTRL
        and     #$01
        bne     bwait
        rts

waitvbl:
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
rnd:    rep     #$20
        .a16
        lda     seed
        asl
        asl
        asl
        asl
        asl
        asl
        asl
        eor     seed
        sta     seed
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        eor     seed
        sta     seed
        xba
        and     #$FF00
        eor     seed
        sta     seed
        sep     #$20
        .a8
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

m_hello: .byte "SPRDEMO: 16 SPRITES AND POINTER OVER A PICTURE, 640X360X8, 1200 FRAMES", 10, 0
m_t:     .byte "T ", 0
m_frame: .byte " FRAME ", 0
m_late:  .byte " NV_LATE ", 0
m_sst:   .byte " SPR_STATUS ", 0
m_sum1:  .byte "SUMMARY FRAMES ", 0
m_sum2:  .byte " VBLANKS ", 0
m_waits: .byte " PENDING_WAITS ", 0
m_done:  .byte "DONE", 10, 0

; ---- sprites: 0 is in front. Arrows point along their path, flipped fish swim left ----
rinit:  REC     100,  60, IMG_ARROW, 12, BIG4 | MG              ; 0  64x64 fire arrow
        REC     300, 100, IMG_FISHA,  0, EN                     ; 1
        REC     500, 200, IMG_FISHA,  0, EN | HF                ; 2  swims left
        REC      50, 300, IMG_FLAGA,  0, EN | VF                ; 3  upside down
        REC     600,  30, IMG_FLAGB,  0, EN | HF | VF           ; 4
        REC     200, 250, IMG_BOAT,  13, BIG4                   ; 5  sea
        REC     450,  80, IMG_BOAT,  14, BIG4 | HF              ; 6  leaf, mirrored
        REC     350, 320, IMG_ARROW, 15, BIG4 | VF              ; 7  rainbow, down-right
        REC     150, 180, IMG_FISHB,  0, EN | MG                ; 8  32x32
        REC     550, 300, IMG_FISHB,  0, EN | MG | HF           ; 9  32x32, swims left
        REC      30, 150, IMG_ARROW, 13, BIG4 | HF | BH         ; 10 behind, up-left
        REC     400,  10, IMG_FLAGA,  0, EN | MG | BH           ; 11 behind, 32x32
        REC     250, 340, IMG_BOAT,  12, BIG4 | MG              ; 12 64x64 fire boat
        REC     620, 330, IMG_FISHA,  0, EN | VF                ; 13 belly up
        REC      10,  10, IMG_FLAGB,  0, EN                     ; 14
        REC     480, 140, IMG_ARROW, 14, BIG4 | HF | VF         ; 15 down-left
; velocities in 1/16 pixel per frame (x, y), same 8-byte stride as the records
vinit:  VEL     20, -12
        VEL     28, 10
        VEL     -26, 14
        VEL     18, -16
        VEL     -22, -20
        VEL     16, -12
        VEL     -18, 16
        VEL     24, 14
        VEL     14, 18
        VEL     -16, -14
        VEL     -20, -22
        VEL     12, 20
        VEL     -14, -12
        VEL     30, -18
        VEL     -30, 24
        VEL     -20, 16
; x, y (16 x fixed point, biased by 64 and 80), vx, vy per sprite
state:  .res    128

pillx:  .word   40, 144, 248, 352, 456, 560
pillh:  .byte   $20, $40, $50, $70, $90, $A0
lumtab: .byte   4, 6, 8, 10, 12, 14, 12, 10, 8, 6
starc:  .byte   $0E, $0A, $06, $0F

; colour tables of the 8 bpp art: char value -> GTIA colour (0 stays transparent)
;                0    1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
ct_fisha: .byte $00, $26, $00, $00, $00, $2A, $1C, $28, $1E, $36, $00, $00, $00, $00, $34, $0F
ct_fishb: .byte $00, $86, $00, $00, $00, $8A, $98, $88, $9C, $0E, $00, $00, $00, $00, $46, $0F
ct_flaga: .byte $00, $00, $00, $08, $24, $00, $00, $00, $00, $00, $0E, $44, $1E, $00, $00, $00
ct_flagb: .byte $00, $00, $00, $0A, $24, $00, $00, $00, $00, $00, $0E, $74, $0E, $00, $00, $00

; palette banks: 15 RGB entries each (entries 1 to 15 of the bank)
pal_fire:
        .byte   $3C, $00, $00, $49, $11, $05, $57, $22, $0B, $65, $33, $11, $73, $44, $16
        .byte   $81, $55, $1C, $8F, $66, $22, $9D, $78, $28, $AB, $89, $2D, $B9, $9A, $33
        .byte   $C7, $AB, $39, $D5, $BC, $3E, $E3, $CD, $44, $F1, $DE, $4A, $FF, $F0, $50
pal_sea:
        .byte   $00, $14, $5A, $08, $24, $65, $11, $35, $71, $19, $46, $7D, $22, $57, $89
        .byte   $2A, $67, $94, $33, $78, $A0, $3C, $89, $AC, $44, $9A, $B8, $4D, $AB, $C4
        .byte   $55, $BB, $CF, $5E, $CC, $DB, $66, $DD, $E7, $6F, $EE, $F3, $78, $FF, $FF
pal_leaf:
        .byte   $00, $3C, $0A, $10, $49, $17, $20, $57, $25, $31, $65, $32, $41, $73, $40
        .byte   $52, $81, $4D, $62, $8F, $5B, $73, $9D, $69, $83, $AB, $76, $93, $B9, $84
        .byte   $A4, $C7, $91, $B4, $D5, $9F, $C5, $E3, $AC, $D5, $F1, $BA, $E6, $FF, $C8
pal_rainbow:
        .byte   $FF, $26, $26, $FF, $7C, $26, $FF, $D3, $26, $D3, $FF, $26, $7C, $FF, $26
        .byte   $26, $FF, $26, $26, $FF, $7C, $26, $FF, $D3, $26, $D3, $FF, $26, $7C, $FF
        .byte   $26, $26, $FF, $7C, $26, $FF, $D3, $26, $FF, $FF, $26, $D3, $FF, $26, $7C

        .include "sine256.inc"

; ---- art: '.' transparent, '1'-'F' a colour (8 bpp: through a colour table; 4 bpp: PAL x 16
; + value; pointer: PTR_C1 to PTR_C3) ----
art_fish:                               ; faces right, dorsal fin on top
        .byte   "................"
        .byte   "................"
        .byte   "......555......."
        .byte   ".....55555......"
        .byte   "....5555555....."
        .byte   "1..666666666...."
        .byte   "11666996666666.."
        .byte   "1166699666666F6."
        .byte   "116669966666666E"
        .byte   "118889988888888E"
        .byte   "11888998888888E."
        .byte   "1..888888888...."
        .byte   ".....777........"
        .byte   "......77........"
        .byte   "................"
        .byte   "................"
art_flag:                               ; pole on the left, flag at the top
        .byte   ".3.............."
        .byte   "333............."
        .byte   ".3AAAAAAAAA....."
        .byte   ".3ABBBBBBBBAA..."
        .byte   ".3ABBBBBBBBBBA.."
        .byte   ".3ABBCCCCBBBBBA."
        .byte   ".3ABBCCCCBBBBBA."
        .byte   ".3ABBBBBBBBBBA.."
        .byte   ".3ABBBBBBBBAA..."
        .byte   ".3AAAAAAAAA....."
        .byte   ".3.............."
        .byte   ".3.............."
        .byte   ".3.............."
        .byte   ".3.............."
        .byte   ".3.............."
        .byte   "444............."
art_arrow:                              ; points up-right, dark tail to bright head
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
art_boat:                               ; big sail right of the mast, pennant flying right
        .byte   "................CCCCC..........."
        .byte   "................CCCCCC.........."
        .byte   "..............22CCCCC..........."
        .byte   "..............22................"
        .byte   "..............228..............."
        .byte   "..............2288.............."
        .byte   "..............22999............."
        .byte   "..............229999............"
        .byte   "..............22AAAA............"
        .byte   "............6.22AAAAA..........."
        .byte   "...........66.22BBBBBB.........."
        .byte   "..........666.22BBBBBBB........."
        .byte   "..........666.22CCCCCCC........."
        .byte   ".........6666.22CCCCCCCC........"
        .byte   "........66666.22CCCCCCCCC......."
        .byte   ".......666666.22DDDDDDDDDD......"
        .byte   "......6666666.22DDDDDDDDDDD....."
        .byte   "......6666666.22EEEEEEEEEEE....."
        .byte   ".....66666666.22EEEEEEEEEEEE...."
        .byte   "....666666666.22FFFFFFFFFFFFF..."
        .byte   "...6666666666.22FFFFFFFFFFFFFF.."
        .byte   "..............22................"
        .byte   ".555555555555555555555555555555."
        .byte   "..555555555555555555555555555..."
        .byte   "...333333333333333333333333....."
        .byte   "....333333333333333333333......."
        .byte   ".....333333333333333333........."
        .byte   "......333333333333333..........."
        .byte   "................................"
        .byte   "AAAA....AAAA....AAAA....AAAA...."
        .byte   "A....AAAA....AAAA....AAAA....AAA"
        .byte   "..AAAA....AAAA....AAAA....AAAA.."
art_ptr:                                ; 1 outline, 2 body; hot spot at the tip
        .byte   "1..............................."
        .byte   "11.............................."
        .byte   "121............................."
        .byte   "1221............................"
        .byte   "12221..........................."
        .byte   "122221.........................."
        .byte   "1222221........................."
        .byte   "12222221........................"
        .byte   "122222221......................."
        .byte   "1222222221......................"
        .byte   "12222222221....................."
        .byte   "122222222221...................."
        .byte   "1222222222221..................."
        .byte   "12222222222221.................."
        .byte   "122222222222221................."
        .byte   "1222222221111111................"
        .byte   "122221221......................."
        .byte   "12221.1221......................"
        .byte   "1221..1221......................"
        .byte   "121....1221....................."
        .byte   "11.....1221....................."
        .byte   "1......12221...................."
        .byte   "........1221...................."
        .byte   "........12221..................."
        .byte   ".........1211..................."
        .byte   ".........11....................."
        .byte   "................................"
        .byte   "................................"
        .byte   "................................"
        .byte   "................................"
        .byte   "................................"
        .byte   "................................"
