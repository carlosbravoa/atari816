; bigtext.s - big letters for Lantern: a string in the 1 bpp font of art/bigfont.txt
; (made into art/bigfont.inc by sdk/tools/font2inc.py --prop), drawn 1, 2 or 3 times
; larger into an 8 bpp buffer, ready for one WD_KBLIT.
;
; Horizon's win_draw has two fonts and no 1 bpp blit, so any other lettering is expanded
; by the CPU: for every output row, for every character, the glyph's bits become ink
; pixels; everything else stays the key colour (transparent in a WD_KBLIT).
;
; A separate module: main.s calls it with JSR (the .export / .import below; ld65 links
; both objects into one program, so they share the code bank and DBR).
;
;   bigtext     X = string (zero-terminated, in this program's bank), A = scale 1-3,
;               Y = ink colour, bt_dst = the output buffer (bt_buf or bt_buf2) ->
;               A = width in pixels (at most BT_MAXW); the buffer holds width x 7 * scale
;               pixels, rows of `width` bytes; key colour BT_KEY elsewhere. Keeps nothing.
;   Two buffers, because a blit may still be reading its picture when win_draw returns
;   (the kernel starts the blitter and goes on): never rewrite the picture of the blit
;   you just started before another win_draw call (which waits for the blitter).

        .include "horizon.inc"
        .export bigtext, bt_buf, bt_buf2
        .exportzp bt_w, bt_dst

BT_KEY  = 231                           ; the transparent colour (the same as the sprites')
BT_MAXW = 320
BT_MAXH = 7 * 3

        .segment "CODE"
        .a16
        .i16

bigtext:
        sta     z:bt_sc
        sty     z:bt_ink
        stx     z:bt_s
; ---- the width: the sum of the advances, times the scale
        stz     z:bt_w
@wl:    lda     a:0,x                   ; (absolute,X: the code bank, DBR)
        and     #$00FF
        beq     @wdone
        jsr     glyph                   ; -> Y = glyph index, C set: not in the font
        bcs     :+
        lda     bigfont_ADV,y
        and     #$00FF
        clc
        adc     z:bt_w
        sta     z:bt_w
:       inx
        bra     @wl
@wdone: lda     z:bt_w                  ; * scale (1-3)
        ldy     z:bt_sc
        dey
        beq     :++
:       clc
        adc     z:bt_w
        dey
        bne     :-
:       cmp     #BT_MAXW + 1
        bcc     :+
        lda     #BT_MAXW
:       sta     z:bt_w
; ---- the height and the clear: w * h bytes of the key colour
        lda     z:bt_sc                 ; h = 7 * scale
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:bt_sc
        sta     z:bt_h
        sta     z:bt_n
        lda     #0                      ; count = w * h (h at most 21: by adding)
        ldy     z:bt_h
:       clc
        adc     z:bt_w
        dey
        bne     :-
        lsr     a                       ; in words (+1 for an odd count)
        inc     a
        tay
        lda     z:bt_dst
        sta     z:bt_p
        lda     #BT_KEY | (BT_KEY << 8)
:       sta     (bt_p)                  ; (dp): the address in bt_p, in the data bank
        inc     z:bt_p
        inc     z:bt_p
        dey
        bne     :-
; ---- the rows: output row by output row, every character
        lda     z:bt_dst
        sta     z:bt_row                ; the start of the output row (in bt_buf)
        stz     z:bt_gr                 ; the glyph row (0-6)
        stz     z:bt_sy                 ; the copy of it (0 .. scale - 1)
@row:   lda     z:bt_row
        sta     z:bt_p                  ; where the next pixel goes
        ldx     z:bt_s
@ch:    lda     a:0,x
        and     #$00FF
        beq     @rowdone
        phx
        jsr     glyph
        bcs     @next
        lda     bigfont_ADV,y           ; the columns to do
        and     #$00FF
        sta     z:bt_cols
        tya                             ; the glyph's row byte: bigfont + index * 7 + row
        asl     a
        asl     a
        asl     a
        sta     z:bt_t
        tya
        eor     #$FFFF
        sec
        adc     z:bt_t                  ; index * 8 - index
        clc
        adc     z:bt_gr
        tay
        lda     bigfont,y
        and     #$00FF
        sta     z:bt_bits               ; bit 7 = the leftmost column
@col:   lda     z:bt_p                  ; (stay inside the width)
        sec
        sbc     z:bt_row
        cmp     z:bt_w
        bcs     @next
        lda     z:bt_bits
        bit     #$0080
        beq     @blank
        sep     #$20                    ; scale pixels of ink
        .a8
        lda     z:bt_ink
        ldy     #0
:       sta     (bt_p),y                ; (dp),y: the address in bt_p, in the data bank
        iny
        cpy     z:bt_sc
        bcc     :-
        rep     #$20
        .a16
@blank: lda     z:bt_p
        clc
        adc     z:bt_sc
        sta     z:bt_p
        asl     z:bt_bits
        dec     z:bt_cols
        bne     @col
@next:  plx
        inx
        bra     @ch
@rowdone:
        lda     z:bt_row                ; the next output row
        clc
        adc     z:bt_w
        sta     z:bt_row
        inc     z:bt_sy
        lda     z:bt_sy
        cmp     z:bt_sc
        bcc     :+
        stz     z:bt_sy                 ; every scale rows, the next glyph row
        inc     z:bt_gr
:       dec     z:bt_n
        jne     @row
        lda     z:bt_w
        rts

; A = character -> Y = its index in the font, C clear; C set if it has no glyph
glyph:  sec
        sbc     #bigfont_FIRST
        bcc     @no
        cmp     #bigfont_COUNT
        bcs     @no
        tay
        clc
        rts
@no:    sec
        rts

        .segment "RODATA"
        .include "art/bigfont.inc"

        .segment "BSS"
bt_buf: .res    BT_MAXW * BT_MAXH + 2
bt_buf2: .res   BT_MAXW * BT_MAXH + 2

        .segment "ZEROPAGE"
bt_dst: .res    2                       ; the output buffer (set by the caller)
bt_sc:  .res    2                       ; scale
bt_ink: .res    2
bt_s:   .res    2                       ; the string
bt_w:   .res    2                       ; the width
bt_h:   .res    2
bt_n:   .res    2                       ; output rows left
bt_row: .res    2
bt_p:   .res    2
bt_gr:  .res    2
bt_sy:  .res    2
bt_cols: .res   2
bt_bits: .res   2
bt_t:   .res    2
