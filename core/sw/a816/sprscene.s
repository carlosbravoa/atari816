; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816: one fixed random scene of Marga (REV $0B) for comparing the RTL's picture with the
; emulator's, pixel for pixel. ca65 -D SEED=n: the scene (mode, scrolling, split, pointer, 16
; sprite records) follows from n; the bitmap, the pointer and the sprite images are made by the
; program, so both see the same memory. It draws, waits three frames, prints DONE and stops.
; SEED 9 and up put all sprites on lines 100-227, where the line limit leaves some out.
        .p816
        .smart  -

NV_CTRL     = $00D900
NV_BASE     = $00D901
NV_STRIDE   = $00D904
NV_LINE     = $00D906
NV_LINE_CMP = $00D908
PTR_X       = $00D920
PTR_Y       = $00D922
PTR_HOT     = $00D924
PTR_IMG     = $00D925
NV_SCROLLX  = $00D930
NV_SCROLLY  = $00D932
NV_SCROLLX2 = $00D934
NV_SCROLLY2 = $00D936
NV_VHEIGHT  = $00D938
NV_SCTL     = $00D93A
NV_SPR_CTRL = $00D940
NV_COMMIT   = $00D941
NV_SPR      = $00D980
SV_CTRL     = $00DC00
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1

PIMG        = $030000
SIMG        = $040000
FB          = $080000           ; 432 rows of the stride
.ifndef SEED
SEED = 1
.endif

p0          = $20
tmp         = $30
seed        = $34
k           = $36
rows        = $38
nvctl       = $3A
rec         = $40
xmask       = $48
xoff        = $4A
ymask       = $4C
yoff        = $4E

.macro print msg
        ldx     #.loword(msg)
        jsr     puts
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
        sta     f:SV_CTRL
        rep     #$20
        .a16
        lda     #.loword(SEED * 7919 + 1)
        sta     seed
        sep     #$20
        .a8
        ; mode
        jsr     rnd
        lda     seed
        and     #$03
        cmp     #$03
        bne     :+
        lda     #SEED .mod 3
:       sta     tmp
        stz     tmp+1
        asl
        ora     #$09
        sta     nvctl                   ; NV_CTRL value
        ; bitmap: stride 1024 (8 bpp) or 512, 432 rows, a word pattern
        rep     #$20
        .a16
        lda     #1024
        ldx     tmp
        beq     :+
        lda     #512
:       sta     f:NV_STRIDE
        lsr
        sta     rows                    ; words per row
        lda     #.loword(FB)
        sta     p0
        sep     #$20
        .a8
        lda     #^FB
        sta     p0+2
        rep     #$20
        .a16
        ldx     #432
        lda     #SEED
@row:   ldy     #0
        phx
        pha
        txa
        and     #$0007                  ; one row in 8 is colour 0 (for BEHIND)
        bne     :+
        pla
        pha
        ldx     rows
        lda     #0
@z:     sta     [p0],y
        iny
        iny
        dex
        bne     @z
        pla
        bra     @nx
:       pla
        ldx     rows
:       sta     [p0],y
        clc
        adc     #$1D3B
        iny
        iny
        dex
        bne     :-
@nx:    plx
        adc     #$0101
        pha
        lda     p0                      ; next row
        clc
        adc     f:NV_STRIDE
        sta     p0
        bcc     :+
        inc     p0+2
:       pla
        dex
        bne     @row
        sep     #$20
        .a8
        ; pointer image and the sprite images
        rep     #$20
        .a16
        lda     #.loword(PIMG)
        sta     p0
        sep     #$20
        .a8
        lda     #^PIMG
        sta     p0+2
        ldy     #0
:       jsr     rnd
        sta     [p0],y
        iny
        cpy     #256
        bne     :-
        lda     #^SIMG
        sta     p0+2
        ldy     #0
:       jsr     rnd
        lda     seed+1
        and     #$03
        bne     :+
        lda     #$00
        bra     :++
:       lda     seed
        ora     #$11
:       sta     [p0],y
        iny
        cpy     #8192
        bne     :---
        ; pointer
        lda     #<PIMG
        sta     f:PTR_IMG
        lda     #>PIMG
        sta     f:PTR_IMG+1
        lda     #^PIMG
        sta     f:PTR_IMG+2
        jsr     rnd
        sta     f:PTR_HOT
        rep     #$20
        .a16
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed
        and     #$01FF
        sta     f:PTR_X
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed
        and     #$00FF
        clc
        adc     #20
        sta     f:PTR_Y
        lda     #.loword(FB)
        sta     f:NV_BASE
        sep     #$20
        .a8
        lda     #^FB
        sta     f:NV_BASE+2
        ; scrolling
        rep     #$20
        .a16
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed
        and     #$03FF
        sta     f:NV_SCROLLX
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed
        and     #$03FF
        sta     f:NV_SCROLLX2
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed
        and     #$003F
        sta     f:NV_SCROLLY
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed
        and     #$007F
        sta     f:NV_SCROLLY2
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed                    ; VHEIGHT 0 (half the time) or 128-255
        and     #$01FF
        cmp     #$0100
        bcs     :+
        lda     #0
        bra     :++
:       and     #$00FF
        ora     #$0080
:       sta     f:NV_VHEIGHT
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed
        and     #$00FF
        clc
        adc     #40
        sta     f:NV_LINE_CMP
        sep     #$20
        .a8
        lda     seed+1
        and     #$03
        sta     f:NV_SCTL
        ; sprite positions over every edge: x -96..927, y -80..431 (320x180: half)
        rep     #$20
        .a16
        lda     #$03FF
        sta     xmask
        lda     #96
        sta     xoff
        lda     #$01FF
        sta     ymask
        lda     #80
        sta     yoff
        lda     tmp
        cmp     #2
        bne     :+
        lsr     xmask
        lsr     xoff
        lsr     ymask
        lsr     yoff
:
.if SEED >= 9
        lda     #$003F                  ; SEED 9 and up: crowded, y 100..163 (the line limit)
        sta     ymask
        lda     #$FF9C
        sta     yoff
.endif
        sep     #$20
        .a8
        ; 16 records
        ldx     #0
@rec:   phx
        jsr     rnd
        rep     #$20
        .a16
        lda     seed
        and     xmask
        sec
        sbc     xoff
        sta     rec
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed
        and     ymask
        sec
        sbc     yoff
        sta     rec+2
        pla
        pha
        asl
        asl
        asl
        asl
        asl
        asl
        and     #$1E00
        clc
        adc     #.loword(SIMG)
        sta     rec+4
        jsr     rnd
        .a8
        lda     seed
        and     #$0F
        ora     rec+4
        sta     rec+4
        lda     #^SIMG
        sta     rec+6
        lda     seed+1
.if SEED >= 9
        ora     #$08                    ; crowded scenes: all magnified
.endif
        sta     rec+7
        and     #$0E
        bne     :+
        lda     rec+7
        and     #$FE
        bra     :++
:       lda     rec+7
        ora     #$01
:       sta     rec+7
        plx
        stx     k
        ldx     #0
:       lda     rec,x                   ; (direct page; rec,y would be absolute, bank $01)
        phx
        ldx     k
        sta     f:NV_SPR,x
        inx
        stx     k
        plx
        inx
        cpx     #8
        bne     :-
        ldx     k
        cpx     #128
        bne     @rec
        lda     #$01
        sta     f:NV_SPR_CTRL
        sta     f:NV_COMMIT
        lda     nvctl
        sta     f:NV_CTRL
        ldx     #4
:       phx
        jsr     waitvbl
        plx
        dex
        bne     :-
        print   m_done
        stp

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

m_hello: .byte "SPRITE SCENE", 10, 0
m_done:  .byte "DONE", 10, 0
