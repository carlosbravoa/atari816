; hz_blit.s - Digger's drawing primitives for the Atari816 port: rectangles of whole bytes
; between the framebuffer (4 bits a pixel, 512 bytes a row, 128 rows a bank: hz_plat.h),
; near buffers (the game's save-unders, in the main bank) and far memory (DIGGER.DAT).
; cc816, both code models (model.inc: ARGS, RET). Every width is even: 16-bit moves; a
; buffer or a source never crosses a bank.
        .p816
        .a16
        .i16
        .smart  +
        .include "model.inc"
        .importzp __rg
        .export _hzb_put, _hzb_get, _hzb_putm, _hzb_copy, _hzb_fill, _hzb_fbbank
        .export _hzb_show, _hzb_showbank

fbp     = __rg+0                ; long pointer: the row in the framebuffer (+ x)
src     = __rg+4                ; long pointer (or a near offset): the source / buffer
msk     = __rg+8                ; long pointer: the mask
bw      = __rg+12               ; bytes a row
rows    = __rg+14               ; rows left
row     = __rg+16               ; the framebuffer row
xb      = __rg+18               ; the byte in the row

        .segment "BSS"
_hzb_fbbank: .res 2

        .segment "CODE"

; fbp = the framebuffer's row `row`, byte xb
setrow: lda     row
        and     #$007F
        xba
        asl     a               ; (row % 128) * 512
        clc
        adc     xb
        sta     fbp
        lda     row
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a               ; row / 128
        clc
        adc     _hzb_fbbank
        sta     fbp+2
        rts

; the common arguments: x, row, (buffer), then bw and rows at ARGS+k
.macro  args3 k
        lda     ARGS,s
        sta     xb
        lda     ARGS+2,s
        sta     row
        lda     ARGS+k,s
        sta     bw
        lda     ARGS+k+2,s
        sta     rows
.endmacro

; void hzb_put(unsigned x, unsigned row, const uint8_t __far *buf, unsigned bw,
;              unsigned rows): a buffer (rows of bw bytes) to the screen
_hzb_put:
        jmp     _hzb_copy

; void hzb_get(unsigned x, unsigned row, uint8_t __far *buf, unsigned bw, unsigned rows)
_hzb_get:
        args3   8
        lda     ARGS+4,s
        sta     src
        lda     ARGS+6,s
        sta     src+2
        lda     rows
        beq     @done
@r:     jsr     setrow
        ldy     #0
@c:     lda     [fbp],y
        sta     [src],y
        iny
        iny
        cpy     bw
        bcc     @c
        lda     src
        clc
        adc     bw
        sta     src
        inc     row
        dec     rows
        bne     @r
@done:  RET

; void hzb_putm(unsigned x, unsigned row, unsigned long src, unsigned bw, unsigned rows):
; screen = (screen & M) | S; M follows S (bw * rows bytes on, in the same bank)
_hzb_putm:
        args3   8
        lda     ARGS+4,s
        sta     src
        lda     ARGS+6,s
        sta     src+2
        sta     msk+2
        ldx     rows
        beq     @done
        lda     src
@m:     clc
        adc     bw
        dex
        bne     @m
        sta     msk
@r:     jsr     setrow
        ldy     #0
@c:     lda     [fbp],y
        and     [msk],y
        ora     [src],y
        sta     [fbp],y
        iny
        iny
        cpy     bw
        bcc     @c
        lda     src
        clc
        adc     bw
        sta     src
        lda     msk
        clc
        adc     bw
        sta     msk
        inc     row
        dec     rows
        bne     @r
@done:  RET

; void hzb_copy(unsigned x, unsigned row, unsigned long src, unsigned bw, unsigned rows)
_hzb_copy:
        args3   8
        lda     ARGS+4,s
        sta     src
        lda     ARGS+6,s
        sta     src+2
        lda     rows
        beq     @done
@r:     jsr     setrow
        ldy     #0
@c:     lda     [src],y
        sta     [fbp],y
        iny
        iny
        cpy     bw
        bcc     @c
        lda     src
        clc
        adc     bw
        sta     src
        inc     row
        dec     rows
        bne     @r
@done:  RET

; void hzb_fill(unsigned x, unsigned row, unsigned bw, unsigned rows, unsigned word)
_hzb_fill:
        args3   4
        lda     ARGS+8,s
        sta     src
        lda     rows
        beq     @done
@r:     jsr     setrow
        ldy     #0
        lda     src
@c:     sta     [fbp],y
        iny
        iny
        cpy     bw
        bcc     @c
        inc     row
        dec     rows
        bne     @r
@done:  RET

; void hzb_show(unsigned x, unsigned row, unsigned bw, unsigned rows): the rectangle from
; the drawing buffer (hzb_fbbank) to the shown one (hzb_showbank), same place
_hzb_show:
        args3   4
        lda     rows
        beq     @done
@r:     jsr     setrow
        lda     fbp
        sta     msk
        lda     fbp+2
        sec
        sbc     _hzb_fbbank
        clc
        adc     _hzb_showbank
        sta     msk+2
        ldy     #0
@c:     lda     [fbp],y
        sta     [msk],y
        iny
        iny
        cpy     bw
        bcc     @c
        inc     row
        dec     rows
        bne     @r
@done:  RET

        .segment "BSS"
_hzb_showbank: .res 2
