; SPDX-License-Identifier: GPL-3.0-or-later
; hz_bbs.s - plat_bb_sprite (plat.h) for a picture already in the atlas: its
; sheet record, clipped as horizon/hz_bb.c hzb_sprite_c clips it (the C is the
; reference and does every other case: a picture not kept yet, /S, a
; destination above the buffer). In C the record path took about 60 % of a
; full redraw's own time (the hash's 32-bit keys, 14-byte entries, the
; clipping in signed and long arithmetic through far pointers).
;
; int plat_bb_sprite(const unsigned char far *spr, int kind, unsigned dest,
;                    unsigned top, unsigned bottom, unsigned lx, unsigned rx)
;   1: drawn (queued), 0: not ready (the C draws)
;
; hz_bb.c's Pic, 16 bytes: +0 lo, +2 bank, +3 used, +4 sheet, +5 key, +6 ax,
; +8 ay, +10 x0, +11 first, +12 w, +14 rows, +15 kind; HASH_N 2048 of them at
; offset 0 of bank hzb_picbank; the hash ((lo >> 4) ^ (lo >> 13) ^ (bank << 3))
; & 2047, probed upwards (hz_bb.c find).
        .p816
        .a16
        .i16
        .include "model.inc"
        .importzp __rg
        .import _hzb_ready, _hzb_picbank, _hzb_q, _hzb_qn, _hzb_qpx, _hzb_yof
        .import _g_bb_draws, _g_bb_wait
        .import _hzb_send, _hzb_sprite_c
        .export _plat_bb_sprite

SPR     = ARGS                  ; the arguments (offsets from S; nothing is pushed)
SPRB    = ARGS+2
DEST    = ARGS+6
TOP     = ARGS+8
BOT     = ARGS+10
LX      = ARGS+12
RX      = ARGS+14

pp      = __rg+0                ; long: the Pic table (+ Y: the slot)
lo      = __rg+4                ; the picture's offset
bku     = __rg+6                ; its bank | 1 << 8 (bank and used)
shk     = __rg+8                ; sheet | key << 8
pax     = __rg+10
pay     = __rg+12
x0      = __rg+14
first   = __rg+16
r0      = __rg+18
r1      = __rg+20
c0      = __rg+22
c1      = __rg+24
bx      = __rg+26               ; the destination's column and row
by      = __rg+28
esx     = __rg+30               ; a record: source x, y, w, h, x, y
esy     = __rg+32
ew      = __rg+34
eh      = __rg+36
ex      = __rg+38
ey      = __rg+40
mw      = __rg+42               ; the pixel count's multiply
mh      = __rg+44
prod    = __rg+46

BB_W    = 320
BB_ROWS = 144
BB_ROW0 = 205
SH_KEY  = 2

        .segment "CODE"

_plat_bb_sprite:
        lda     _hzb_ready
        bne     @on
        lda     #0
        RET
@on:    lda     _g_bb_wait
        bne     @slow
        lda     DEST,s                  ; the row's offset (dest << 2) above the
        cmp     #$3000                  ; buffer (>= C000): the C
        bcs     @slow
        ; room for two records first (the C sends when one would not fit)
        lda     _hzb_qn
        cmp     #127
        bcs     @send
        lda     _hzb_qpx+2
        cmp     #.hiword(460800 - 2 * 65536)
        bcc     @hash
@send:  CALL    _hzb_send
@hash:  lda     SPR,s
        sta     lo
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     mw                      ; lo >> 4
        lda     lo
        rol     a
        rol     a
        rol     a
        rol     a
        and     #7                      ; lo >> 13
        eor     mw
        sta     mw
        lda     SPRB,s
        and     #$00FF
        ora     #$0100
        sta     bku
        asl     a
        asl     a
        asl     a                       ; (bank << 3) | (1 << 11): gone below
        eor     mw
        and     #$07FF
        asl     a
        asl     a
        asl     a
        asl     a
        tay                             ; the slot's offset
        stz     pp
        lda     _hzb_picbank
        sta     pp+2
@probe: lda     [pp],y
        cmp     lo
        bne     @other
        iny
        iny
        lda     [pp],y                  ; bank | used << 8
        dey
        dey
        cmp     bku
        beq     @hit
        bra     @free
@other: iny
        iny
        lda     [pp],y
        dey
        dey
@free:  and     #$FF00                  ; a free slot: not kept, the C
        beq     @slow
        tya
        clc
        adc     #16
        and     #$7FF0
        tay
        bra     @probe
@slow:  TAILJ   _hzb_sprite_c

@hit:   inc     _g_bb_draws
        bne     @d1
        inc     _g_bb_draws+2
@d1:    iny
        iny
        iny
        iny
        lda     [pp],y                  ; +4 sheet, key
        sta     shk
        iny
        iny
        lda     [pp],y                  ; +6 ax
        sta     pax
        iny
        iny
        lda     [pp],y                  ; +8 ay
        sta     pay
        iny
        iny
        lda     [pp],y                  ; +10 x0, first
        tax
        and     #$00FF
        sta     x0
        txa
        xba
        and     #$00FF
        sta     first
        iny
        iny
        lda     [pp],y                  ; +12 w
        bne     @w
@done1: lda     #1
        RET
@w:     clc
        adc     x0
        sta     c1                      ; c1 = x0 + w
        iny
        iny
        lda     [pp],y                  ; +14 rows
        and     #$00FF
        clc
        adc     first
        sta     r1                      ; r1 = first + rows
        ; the rows and columns drawn (unsigned, as the C)
        lda     first
        cmp     TOP,s
        bcs     @t
        lda     TOP,s
@t:     sta     r0
        lda     BOT,s
        cmp     r1
        bcs     @b
        sta     r1
@b:     lda     x0
        cmp     LX,s
        bcs     @l
        lda     LX,s
@l:     sta     c0
        lda     RX,s
        cmp     c1
        bcs     @r
        sta     c1
@r:     lda     r0
        cmp     r1
        bcs     @done1
        lda     c0
        cmp     c1
        bcs     @done1
        ; the destination (dest << 2): row offset / 320 by the table, column
        lda     DEST,s
        asl     a
        asl     a
        sta     bx
        lda     DEST,s
        lsr     a
        lsr     a
        lsr     a
        lsr     a                       ; (dest << 2) >> 6 (dest < 3000h: < 768)
        tax
        lda     _hzb_yof,x
        and     #$00FF
        sta     by
        xba                             ; by * 256
        sta     mw
        lda     by
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a                       ; by * 64
        clc
        adc     mw
        eor     #$FFFF
        sec
        adc     bx
        sta     bx                      ; offset - by * 320
        ; the record(s): rows r0..r1, columns c0..c1 at (bx + c0, by + r0)
        lda     c1
        sec
        sbc     c0
        sta     ew
        lda     r1
        sec
        sbc     r0
        sta     eh
        lda     c0
        sec
        sbc     x0
        clc
        adc     pax
        sta     esx
        lda     r0
        sec
        sbc     first
        clc
        adc     pay
        sta     esy
        lda     bx
        clc
        adc     c0
        sta     ex
        lda     by
        clc
        adc     r0
        sta     ey
        ; (put_linear) past column 320: the next row
@wrap:  lda     ex
        cmp     #BB_W
        bcc     @inrow
        sbc     #BB_W
        sta     ex
        inc     ey
        bra     @wrap
@inrow: clc
        adc     ew
        cmp     #BB_W+1
        bcc     @one
        ; a part past the row's end goes on the next row, from column 0
        lda     #BB_W
        sec
        sbc     ex
        sta     mh                      ; cut
        lda     ew
        pha
        lda     esx
        pha
        lda     ex
        pha
        lda     ey
        pha
        lda     ew
        sec
        sbc     mh
        sta     ew
        lda     esx
        clc
        adc     mh
        sta     esx
        stz     ex
        inc     ey
        lda     mh
        pha
        jsr     emit
        pla
        sta     ew                      ; the left part: cut columns
        pla
        sta     ey
        pla
        sta     ex
        pla
        sta     esx
        pla                             ; (the whole width)
@one:   jsr     emit
        lda     #1
        RET

; one keyed record of the atlas' (esx, esy) ew x eh to the buffer's (ex, ey),
; the buffer's rows only (ey >= 0 here)
emit:   lda     ey
        cmp     #BB_ROWS
        bcc     @y
@x0:    rts
@y:
        clc
        adc     eh
        cmp     #BB_ROWS+1
        bcc     @h
        lda     #BB_ROWS
        sec
        sbc     ey
        sta     eh
@h:     lda     ew
        beq     @x0
        lda     eh
        beq     @x0
        lda     _hzb_qn
        asl     a
        asl     a
        asl     a
        asl     a
        tax
        lda     shk                     ; sheet, op
        and     #$00FF
        ora     #SH_KEY << 8
        sta     _hzb_q,x
        lda     shk+1                   ; key, 0
        and     #$00FF
        sta     _hzb_q+2,x
        lda     esx
        sta     _hzb_q+4,x
        lda     esy
        sta     _hzb_q+6,x
        lda     ew
        sta     _hzb_q+8,x
        lda     eh
        sta     _hzb_q+10,x
        lda     ex
        sta     _hzb_q+12,x
        lda     ey
        clc
        adc     #BB_ROW0
        sta     _hzb_q+14,x
        inc     _hzb_qn
        ; qpx += max(ew * eh, 256)
        lda     ew
        sta     mw
        lda     eh
        sta     mh
        stz     prod
@ml:    lsr     mh
        bcc     @mn
        lda     prod
        clc
        adc     mw
        sta     prod
@mn:    asl     mw
        lda     mh
        bne     @ml
        lda     prod
        cmp     #256
        bcs     @p
        lda     #256
@p:     clc
        adc     _hzb_qpx
        sta     _hzb_qpx
        bcc     @x
        inc     _hzb_qpx+2
@x:     rts

; unsigned hzb_scan(const unsigned char far *s, int kind)
;   hz_bb.c unpack's first pass over picture s (vgasprite.py's formats: kind 0
;   masked spans, 1 OR rows): hzb_used[c] = 1 for every colour c its spans
;   use, hzb_x0 / hzb_x1 its columns (x0 >= x1: none); -> its length in bytes
;   (In C, a byte at a time through far pointers: 9 ms a picture.)
        .export _hzb_scan, _hzb_used, _hzb_x0, _hzb_x1
        .segment "BSS"
_hzb_used: .res 256
_hzb_x0: .res 2
_hzb_x1: .res 2
srows:  .res 2
skind:  .res 2
sn:     .res 2
sx:     .res 2
slen:   .res 2
        .segment "CODE"
PSC     = __rg+0
_hzb_scan:
        lda     ARGS,s
        sta     PSC
        lda     ARGS+2,s
        sta     PSC+2
        lda     ARGS+4,s
        sta     skind
        ldx     #254
@clr:   stz     _hzb_used,x
        dex
        dex
        bpl     @clr
        lda     #$FFFF
        sta     _hzb_x0
        stz     _hzb_x1
        ldy     #1
        lda     [PSC],y
        and     #$00FF
        sta     srows
        iny                             ; y: the reading position (t)
@row:   lda     srows
        bne     @r1
        tya                             ; done: the length
        RET
@r1:    dec     srows
        lda     skind
        bne     @or
        lda     [PSC],y                 ; masked: the row's spans
        and     #$00FF
        sta     sn
        iny
@span:  lda     sn
        beq     @row
        dec     sn
        lda     [PSC],y                 ; x, len
        iny
        iny
        tax
        and     #$0080
        beq     @nf
        iny                             ; the filler byte
@nf:    txa
        and     #$007F
        sta     sx
        txa
        xba
        and     #$00FF
        sta     slen
        jsr     mark
        bra     @span
@or:    lda     [PSC],y                 ; OR: x, words
        iny
        iny
        tax
        and     #$00FF
        sta     sx
        txa
        xba
        and     #$00FF
        asl     a
        sta     slen
        jsr     mark
        bra     @row

; the span at sx (slen bytes at Y): its bounds, its colours; Y past it
mark:   lda     slen
        beq     @x
        lda     sx
        cmp     _hzb_x0
        bcs     @a
        sta     _hzb_x0
@a:     clc
        adc     slen
        cmp     _hzb_x1
        bcc     @b
        sta     _hzb_x1
@b:     ldx     slen
        lda     #0                      ; (TAX below takes B too)
        sep     #$20
        .a8
@m:     lda     [PSC],y
        phx
        tax
        lda     #1
        sta     _hzb_used,x
        plx
        iny
        dex
        bne     @m
        rep     #$20
        .a16
@x:     rts
