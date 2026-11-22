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

; The copies of whole rows use MVN (7 cycles a byte, against about 12 for a loop of
; [dp],y loads and stores), whose two bank bytes are written into the instruction itself
; (self-modifying code: the code bank is writable, docs/reference/program.md) when the
; routine starts and when the framebuffer's row moves into its next bank (every 128 rows).
; MVN sets DBR to the destination's bank: PHB / PLB around it. The masked put reads the
; sprite with absolute,Y addressing (DBR the sprite's bank), the operands written for each
; row. Each label of a patched instruction ends the routine's @ labels' scope: those
; routines name their labels.
;
; patch label, srcbank, dstbank: the MVN at label moves from bank srcbank to dstbank (A8)
.macro  patch   label, srcbank, dstbank
        sep     #$20
        .a8
        lda     dstbank
        sta     label+1
        lda     srcbank
        sta     label+2
        rep     #$20
        .a16
.endmacro

; the next row of the framebuffer: fbp += 512; carry set when it went into the next bank
.macro  nextrow
        lda     fbp
        clc
        adc     #512
        sta     fbp
.endmacro

bw1     = __rg+20               ; bw - 1: MVN's count

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
        beq     get_done
        lda     bw
        dec     a
        sta     bw1
        jsr     setrow
        patch   getmv, fbp+2, src+2
get_r:  ldx     fbp
        ldy     src
        lda     bw1
        phb
getmv:  mvn     #0, #0
        plb
        sty     src             ; (MVN leaves Y at the next row of the buffer)
        nextrow
        bcc     get_n
        inc     fbp+2
        patch   getmv, fbp+2, src+2
get_n:  dec     rows
        bne     get_r
get_done:
        RET

; void hzb_putm(unsigned x, unsigned row, unsigned long src, unsigned bw, unsigned rows):
; screen = (screen & M) | S; M follows S (bw * rows bytes on, in the same bank)
_hzb_putm:
        args3   8
        lda     ARGS+4,s
        sta     src
        lda     ARGS+6,s
        sta     src+2
        ldx     rows
        beq     putm_done
        lda     src
@m:     clc
        adc     bw
        dex
        bne     @m
        sta     msk
        jsr     setrow
        phb                     ; DBR = the sprite's bank (S and M)
        sep     #$20
        .a8
        lda     src+2
        pha
        plb
        rep     #$20
        .a16
putm_r: lda     msk             ; this row's M and S: the operands below
        sta     f:pm_and+1
        lda     src
        sta     f:pm_ora+1
        ldy     bw              ; the row from its end: Y = bw - 2 ... 0
        dey
        dey
pm_c:   lda     [fbp],y
pm_and: and     a:$0000,y
pm_ora: ora     a:$0000,y
        sta     [fbp],y
        dey
        dey
        bpl     pm_c
        lda     src
        clc
        adc     bw
        sta     src
        lda     msk
        clc
        adc     bw
        sta     msk
        nextrow
        bcc     putm_n
        inc     fbp+2
putm_n: dec     rows
        bne     putm_r
        plb
putm_done:
        RET

; void hzb_copy(unsigned x, unsigned row, unsigned long src, unsigned bw, unsigned rows)
_hzb_copy:
        args3   8
        lda     ARGS+4,s
        sta     src
        lda     ARGS+6,s
        sta     src+2
        lda     rows
        beq     copy_done
        lda     bw
        dec     a
        sta     bw1
        jsr     setrow
        patch   copymv, src+2, fbp+2
copy_r: ldx     src
        ldy     fbp
        lda     bw1
        phb
copymv: mvn     #0, #0
        plb
        stx     src             ; (MVN leaves X at the next row of the source)
        nextrow
        bcc     copy_n
        inc     fbp+2
        patch   copymv, src+2, fbp+2
copy_n: dec     rows
        bne     copy_r
copy_done:
        RET

; void hzb_fill(unsigned x, unsigned row, unsigned bw, unsigned rows, unsigned word)
_hzb_fill:
        args3   4
        lda     ARGS+8,s
        sta     src
        lda     rows
        beq     @done
        jsr     setrow
@r:     ldy     bw
        dey
        dey
        lda     src
@c:     sta     [fbp],y
        dey
        dey
        bpl     @c
        nextrow
        bcc     @n
        inc     fbp+2
@n:     dec     rows
        bne     @r
@done:  RET

; void hzb_show(unsigned x, unsigned row, unsigned bw, unsigned rows): the rectangle from
; the drawing buffer (hzb_fbbank) to the shown one (hzb_showbank), same place
_hzb_show:
        args3   4
        lda     rows
        beq     show_done
        lda     bw
        dec     a
        sta     bw1
        jsr     setrow
        jsr     showbank
show_r: ldx     fbp
        txy
        lda     bw1
        phb
showmv: mvn     #0, #0
        plb
        nextrow
        bcc     show_n
        inc     fbp+2
        jsr     showbank
show_n: dec     rows
        bne     show_r
show_done:
        RET

; the MVN of hzb_show: from the drawing buffer's bank of this row to the shown one's
showbank:
        lda     fbp+2
        sec
        sbc     _hzb_fbbank
        clc
        adc     _hzb_showbank
        sta     msk+2
        patch   showmv, fbp+2, msk+2
        rts

        .segment "BSS"
_hzb_showbank: .res 2
