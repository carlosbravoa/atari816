; hz_blit.s - Xargon's drawing by the CPU for the Atari816 port: what the blitter cannot do
; (hz_vga.c draws the rest with it): a shape through a colour table (upstream's fonts: four
; values to the colours fontcolor chose, 255 transparent), and a fill, into the framebuffer
; (hz_plat.h: 512-byte rows, 128 rows a bank, its first bank in _hzb_bank). The callers have
; cut the rectangles at the screen's edges and at the ring's wrap, so a row never wraps; a
; source row never crosses a bank (the atlas's rows are 512 bytes).
; cc816, both code models (model.inc: ARGS, RET).
        .p816
        .a16
        .i16
        .smart  +
        .include "model.inc"
        .importzp __rg
        .export _hzb_map, _hzb_fill, _hzb_bank, _hzb_maptab

; long conditional branches (jXX: the opposite branch over a JMP)
.macro  jcs     t
        bcc     :+
        jmp     t
:
.endmacro
.macro  jcc     t
        bcs     :+
        jmp     t
:
.endmacro
.macro  jeq     t
        bne     :+
        jmp     t
:
.endmacro
.macro  jne     t
        beq     :+
        jmp     t
:
.endmacro
.macro  jmi     t
        bpl     :+
        jmp     t
:
.endmacro
.macro  jpl     t
        bmi     :+
        jmp     t
:
.endmacro

src     = __rg+0                ; long pointer: the source row
dst     = __rg+4                ; long pointer: the framebuffer row (+ x)
wm1     = __rg+8                ; the width - 1 (the last byte's index)
rows    = __rg+10               ; rows left
row     = __rg+12               ; the framebuffer row
xb      = __rg+14               ; the byte in the row
sstr    = __rg+16               ; the source's stride
wm2     = __rg+18               ; the width - 2 (16-bit loop)
col     = __rg+20               ; hzb_fill's colour, twice

        .segment "BSS"
_hzb_bank:   .res 2
_hzb_maptab: .res 256

        .segment "CODE"

; dst = row `row`, byte xb of the page
setrow: lda     row
        and     #$007F
        xba
        asl     a               ; (row % 128) * 512
        clc
        adc     xb
        sta     dst
        lda     row
        asl     a
        xba
        and     #$00FF          ; row / 128
        clc
        adc     _hzb_bank
        sta     dst+2
        rts

; the arguments of the source routines: src, sstride, w, h, row, x
.macro  sargs
        lda     ARGS,s
        sta     src
        lda     ARGS+2,s
        sta     src+2
        lda     ARGS+4,s
        sta     sstr
        lda     ARGS+6,s
        dec     a
        sta     wm1
        dec     a
        sta     wm2
        lda     ARGS+8,s
        sta     rows
        lda     ARGS+10,s
        sta     row
        lda     ARGS+12,s
        sta     xb
.endmacro

; the next source row and framebuffer row; Z set when the rows are done
.macro  next
        lda     src
        clc
        adc     sstr
        sta     src
        inc     row
        dec     rows
.endmacro

; void hzb_map(...): each source byte through _hzb_maptab, 255 = transparent (upstream's
;              colour tables 1 and 2: the fonts' colours, erasing)
_hzb_map:
        sargs
        lda     rows
        beq     @done
        lda     wm1
        bmi     @done
@row:   jsr     setrow
        lda     #0              ; (B = 0: TAX takes 00:A)
        sep     #$20
        .a8
        ldy     wm1
@px:    lda     [src],y
        tax
        lda     _hzb_maptab,x
        cmp     #$FF
        beq     @skip
        sta     [dst],y
@skip:  dey
        bpl     @px
        rep     #$20
        .a16
        next
        bne     @row
@done:  RET

; void hzb_fill(unsigned w, unsigned h, unsigned row, unsigned x, unsigned colour)
_hzb_fill:
        lda     ARGS,s
        dec     a
        sta     wm1
        lda     ARGS+2,s
        sta     rows
        lda     ARGS+4,s
        sta     row
        lda     ARGS+6,s
        sta     xb
        lda     ARGS+8,s
        and     #$00FF
        sta     col
        xba
        ora     col
        sta     col             ; the colour in both bytes
        lda     rows
        beq     @done
        lda     wm1
        bmi     @done
@row:   jsr     setrow
        ldy     wm1
        sep     #$20
        .a8
        lda     col
@b:     sta     [dst],y
        dey
        bpl     @b
        rep     #$20
        .a16
        inc     row
        dec     rows
        bne     @row
@done:  RET

; ---------------------------------------------------------------- drawshape's fast path
;
; void drawshape(vptype *vp, int n, int x, int y): upstream's (graphics.c) for the common
; case, a cell or a sprite of a loaded table, wholly inside the viewport and the
; playfield's rows, not across the ring's wrap: one sheet_draw record queued
; (hz_vga.c's queue). Shapes wholly outside the viewport return at once. Everything else
; (a table to load, a font, a shape to cut, the status bar's rows) goes to hz_vga.c's
; drawshape_c with the same arguments.
        .import _shm_flags, _hzshm_ok, _hzshm_count, _hzshm_first, _hzshm_row0, _hzshm_dir
        .import _drawofs, _hzv_ox, _hzv_oy, _hzv_q, _hzv_qn, _hzv_sheet_a, _hzv_sheet_b
        .import _drawshape_c, _hzv_flush
        .export _drawshape, _hzv_fast

        .segment "BSS"
_hzv_fast: .res 4               ; (statistics: shapes queued here)
        .segment "CODE"

d_vp    = __rg+24
d_ns    = __rg+26
d_ct    = __rg+28
d_w     = __rg+30
d_h     = __rg+32
d_x     = __rg+34
d_y     = __rg+36
d_sx    = __rg+38
d_sy    = __rg+40
d_e     = __rg+42               ; (4 bytes: the shapes' directory)
d_p     = __rg+20               ; the page drawn, x 2
d_c0    = __rg+22

_drawshape:
        lda     _hzv_qn
        cmp     #64
        bcc     ds_room
        CALL    _hzv_flush      ; (the queue full: sent first; it may use __rg)
ds_room:
        lda     ARGS,s
        sta     d_vp
        lda     ARGS+2,s
        and     #$00FF
        sta     d_ns
        lda     ARGS+2,s
        xba
        and     #$00FF          ; nt (0x80 and up: n < 0)
        cmp     #$0080
        jcs     ds_ret
        bit     #$0040
        beq     ds_tab
        eor     #$0040          ; (0x40: opaque, colour table 3)
        tax
        lda     #3
        sta     d_ct
        txa
        bra     ds_chk
ds_tab: cmp     #64
        jcs     ds_ret
        asl     a
        tax
        lda     _shm_flags,x
        and     #1
        sta     d_ct
        jne     ds_slow         ; (a font: drawshape_c, by the CPU)
        txa
        lsr     a
ds_chk: cmp     #64
        jcs     ds_ret
        tax
        jeq     ds_ret          ; (table 0: none)
        lda     _hzshm_ok,x
        and     #$00FF
        jeq     ds_slow         ; (not loaded: drawshape_c loads it)
        txa
        asl     a
        tax
        lda     d_ns
        cmp     _hzshm_count,x
        jcs     ds_ret
        clc
        adc     _hzshm_first,x
        asl     a
        asl     a
        asl     a
        tay                     ; the shape's entry
        lda     _hzshm_row0,x
        sta     d_sy
        lda     _hzshm_dir
        sta     d_e
        lda     _hzshm_dir+2
        sta     d_e+2
        lda     [d_e],y         ; x in the atlas
        sta     d_sx
        iny
        iny
        lda     [d_e],y         ; y in the table's rows
        clc
        adc     d_sy
        sta     d_sy
        iny
        iny
        lda     [d_e],y         ; w | h << 8
        tax
        and     #$00FF
        sta     d_w
        txa
        xba
        and     #$00FF
        sta     d_h
        ldy     #8              ; x -= vp->vpox, y -= vp->vpoy
        lda     ARGS+4,s
        sec
        sbc     (d_vp),y
        sta     d_x
        ldy     #10
        lda     ARGS+6,s
        sec
        sbc     (d_vp),y
        sta     d_y
        ; wholly outside: y >= vpyl, y + h <= 0, x >= vpxl, x + w <= 0
        ldy     #6
        sec
        sbc     (d_vp),y
        jpl     ds_ret
        lda     d_y
        clc
        adc     d_h
        jeq     ds_ret
        jmi     ds_ret
        ldy     #4
        lda     d_x
        sec
        sbc     (d_vp),y
        jpl     ds_ret
        lda     d_x
        clc
        adc     d_w
        jeq     ds_ret
        jmi     ds_ret
        ; wholly inside the viewport?
        lda     d_x
        jmi     ds_slow
        lda     d_y
        jmi     ds_slow
        lda     d_x
        clc
        adc     d_w
        dec     a
        ldy     #4
        sec
        sbc     (d_vp),y
        jpl     ds_slow
        lda     d_y
        clc
        adc     d_h
        dec     a
        ldy     #6
        sec
        sbc     (d_vp),y
        jpl     ds_slow
        ; screen coordinates: inside columns 0-319 and rows 0-159?
        ldy     #0
        lda     d_x
        clc
        adc     (d_vp),y
        jmi     ds_slow
        sta     d_x
        clc
        adc     d_w
        cmp     #321
        jcs     ds_slow
        ldy     #2
        lda     d_y
        clc
        adc     (d_vp),y
        jmi     ds_slow
        sta     d_y
        clc
        adc     d_h
        cmp     #161
        jcs     ds_slow
        ; the page and the ring's column
        lda     _drawofs
        and     #$4000
        beq     ds_p0
        lda     #2
ds_p0:  sta     d_p
        tax
        lda     _hzv_ox,x
        clc
        adc     d_x
        and     #511
        sta     d_c0
        clc
        adc     d_w
        cmp     #513
        jcs     ds_slow         ; (across the wrap)
        ; the record
        lda     _hzv_qn
        inc     _hzv_qn
        asl     a
        asl     a
        asl     a
        asl     a
        tax                     ; its offset in the queue
        lda     d_sx
        sta     _hzv_q+4,x
        lda     d_w
        sta     _hzv_q+8,x
        lda     d_h
        sta     _hzv_q+10,x
        lda     d_c0
        sta     _hzv_q+12,x
        ldy     d_p
        lda     _hzv_oy,y
        clc
        adc     d_y
        cpy     #0
        beq     ds_y0
        clc
        adc     #440            ; (page 1: HZ_PAGE rows down)
ds_y0:  sta     _hzv_q+14,x
        lda     d_ct
        cmp     #3
        beq     ds_cp
        lda     #$0002          ; SH_KEY, key 0 (c = 0 in the high byte)
        bra     ds_op
ds_cp:  lda     #$0001          ; SH_COPY
ds_op:  xba                     ; (op in the record's byte 1)
        sta     _hzv_q+0,x      ; (byte 0, the sheet: below)
        stz     _hzv_q+2,x      ; c, zero
        lda     d_sy
        cmp     #1024
        bcs     ds_b
        sta     _hzv_q+6,x
        sep     #$20
        .a8
        lda     _hzv_sheet_a
        sta     _hzv_q+0,x
        rep     #$20
        .a16
        bra     ds_done
ds_b:   sec
        sbc     #1024
        sta     _hzv_q+6,x
        sep     #$20
        .a8
        lda     _hzv_sheet_b
        sta     _hzv_q+0,x
        rep     #$20
        .a16
ds_done:
        inc     _hzv_fast
        jne     ds_ret
        inc     _hzv_fast+2
ds_ret: RET
ds_slow:
        TAILJ   _drawshape_c
