; SPDX-License-Identifier: GPL-3.0-or-later
; hz_vga.s - two of plat/vga.c's pixel loops on the Atari816 (the C there is
; the reference, the host's): the geoscape's zoomed rows and the interface's
; glyphs (vga_uk_glyph: 8 % of the geoscape's time with the clock running).
;
; void hz_zoom_row(unsigned char far *d, const unsigned char far *s, unsigned n,
;                  unsigned zoom)
;   n bytes of s, each 2 (zoom 1) or 4 (zoom 2) times, to d
; void hz_glyph(unsigned char far *d, const unsigned char far *g, int h, int bpr,
;               int c, int right)
;   h rows of a 1-bit glyph (bpr 1 or 2 bytes a row, bit 7 of the first the
;   left), colour c where a bit is set, at most right pixels a row; d steps 320
        .p816
        .a16
        .i16
        .include "model.inc"
        .importzp __rg
        .export _hz_zoom_row, _hz_glyph

PD       = __rg+0
PS       = __rg+4
cnt     = __rg+8
bits    = __rg+10
col     = __rg+12
right   = __rg+14
bpr     = __rg+16


        FUNC    _hz_zoom_row
        lda     ARGS,s
        sta     PD
        lda     ARGS+2,s
        sta     PD+2
        lda     ARGS+4,s
        sta     PS
        lda     ARGS+6,s
        sta     PS+2
        lda     ARGS+8,s
        beq     @x
        sta     cnt
        ldy     #0
        lda     ARGS+10,s
        cmp     #2
        beq     @z2
@z1:    lda     [PS],y                   ; zoom 1: a byte -> a word
        and     #$00FF
        sta     bits
        xba
        ora     bits
        sta     [PD]
        inc     PD
        inc     PD
        iny
        dec     cnt
        bne     @z1
@x:     RET
@z2:    lda     [PS],y                   ; zoom 2: a byte -> two words
        and     #$00FF
        sta     bits
        xba
        ora     bits
        sta     [PD]
        ldx     #2
        phy
        txy
        sta     [PD],y
        ply
        lda     PD
        clc
        adc     #4
        sta     PD
        iny
        dec     cnt
        bne     @z2
        RET

        FUNC    _hz_glyph
        lda     ARGS,s
        sta     PD
        lda     ARGS+2,s
        sta     PD+2
        lda     ARGS+4,s
        sta     PS
        lda     ARGS+6,s
        sta     PS+2
        lda     ARGS+8,s                ; h
        beq     @x
        bmi     @x
        sta     cnt
        lda     ARGS+10,s
        sta     bpr
        lda     ARGS+12,s
        sta     col
        lda     ARGS+14,s
        sta     right
@row:   lda     [PS]                     ; g[0] << 8 | g[1]
        xba
        ldx     bpr
        cpx     #2
        beq     @two
        and     #$FF00
@two:   sta     bits
        ldx     right
        ldy     #0
@px:    lda     bits
        beq     @rd
        cpx     #0
        beq     @rd
        asl     bits
        bcc     @n
        sep     #$20
        .a8
        lda     col
        sta     [PD],y
        rep     #$20
        .a16
@n:     iny
        dex
        bra     @px
@rd:    lda     PS
        clc
        adc     bpr
        sta     PS
        lda     PD
        clc
        adc     #320
        sta     PD
        dec     cnt
        bne     @row
@x:     RET

; void hz_shade_rect(unsigned char far *d, const unsigned char far *s, unsigned w,
;                    unsigned rows, const unsigned char far *tab)
;   rows of w bytes (stride 320) from s to d through the 256-byte table tab
;   (the night's present: plat/vgabat.c bufc_present_rect)
        .export _hz_shade_rect
PT      = __rg+18
        .segment "BSS"
stab:   .res 256
        FUNC    _hz_shade_rect
        lda     ARGS,s
        sta     PD
        lda     ARGS+2,s
        sta     PD+2
        lda     ARGS+4,s
        sta     PS
        lda     ARGS+6,s
        sta     PS+2
        lda     ARGS+8,s
        beq     @x
        sta     right                   ; w
        lda     ARGS+10,s
        beq     @x
        sta     cnt                     ; rows
        lda     ARGS+12,s
        sta     PT
        lda     ARGS+14,s
        sta     PT+2
        ldy     #254                    ; the table into the main bank (abs,X)
@cp:    lda     [PT],y
        sta     stab,y
        dey
        dey
        bpl     @cp
        lda     #0                      ; (B: TAX takes it)
        sep     #$20
        .a8
@row:   ldy     #0
@px:    lda     [PS],y
        tax
        lda     stab,x
        sta     [PD],y
        iny
        cpy     right
        bne     @px
        rep     #$20
        .a16
        lda     PS
        clc
        adc     #320
        sta     PS
        lda     PD
        clc
        adc     #320
        sta     PD
        lda     #0
        sep     #$20
        .a8
        dec     cnt
        bne     @row
        rep     #$20
        .a16
@x:     RET
