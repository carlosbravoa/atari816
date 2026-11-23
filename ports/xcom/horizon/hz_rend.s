; SPDX-License-Identifier: GPL-3.0-or-later
; hz_rend.s - the floor pass's columns on the Atari816: plat/rend.c rd_level's
; loop (col_setup, slots, col_late with scatter and roofed, col_floors with
; floor_draw), which is upstream's src/rendasm.asm in C. The C in rend.c is
; the reference (the host runs it); this does the same, step by step, on
; rend.c's block rd_b (its fields by offset, B_* below: rend.c checks them),
; and draws a ground floor's record straight through plat_bb_sprite (the
; blitter's record path, horizon/hz_bbs.s). In C the floor pass took about
; 37 % of a full redraw.
;
; void rd_cols(void)
        .p816
        .a16
        .i16
        .include "model.inc"
        .importzp __rg
        .import _rd_b, _rd_roofoff, _rd_rqx, _rd_rqy
        .import _g_map, _g_seen, _g_unit_at, _g_occ_count
        .import _plat_bb_sprite, _blitc_or, _gfx_sprite, _gfx_sprite_or
        .export _rd_cols

RB      = _rd_b
B_MCD   = 0                     ; far pointers (4 bytes)
B_SPR   = 4
B_LATE  = 8
B_COV   = 12
B_MX    = 24                    ; ints
B_MY    = 26
B_BSEG  = 28
B_CX0   = 30
B_CY0   = 32
B_CX1   = 34
B_CY1   = 36
B_CAMX  = 38
B_UA0   = 42
B_UB    = 44
B_VC    = 46
B_VD    = 48
B_Z     = 50
B_ZBASE = 52
B_CURX  = 54
B_CURY  = 56
B_NLATE = 58
B_X     = 60
B_N     = 62
B_Y     = 64
B_IDX   = 66
B_SX    = 68
B_SY    = 70
B_ZY    = 72
B_YEND  = 74
B_ORSPR = 76
B_OCC   = 78
B_LOOK  = 80
B_COVON = 82
B_UP1   = 84
B_UP2   = 86
B_C     = 88
B_S0    = 90
B_S1    = 92
B_S2    = 94
B_S3    = 96
B_SF    = 98
B_XLO   = 100
B_XHI   = 102

SEEN    = $10
MAXLATE = 400
LATEHID = $40
LATEROOF = $8000
COVCOL  = 68

; long pointers kept across the C calls: callee-saved registers (saved here)
P_MAP   = __rg+48
P_SEEN  = __rg+52
P_UNIT  = __rg+56
P_COV   = __rg+60
P_MCD   = __rg+64
P_LATE  = __rg+68
P_SPR   = __rg+72
NSAVE   = 28
; scratch (lost across the C calls)
TS      = __rg+0                ; long: the floor's picture
m1      = __rg+4
m2      = __rg+6
macc    = __rg+8
tmp     = __rg+10

        .segment "BSS"
hasseen: .res 2                 ; g_seen not NULL
hasunit: .res 2                 ; g_unit_at not NULL
cc:     .res 2                  ; the column
ylo:    .res 2
yhi:    .res 2
li:     .res 2                  ; a column's tile: its number, index, first y
lidx:   .res 2
y0:     .res 2
curleft: .res 2
left:   .res 2
tofs:   .res 2                  ; the tile's offset in g_map (idx << 2)
t123:   .res 2                  ; its walls' and object's records ORed
uat:    .res 2                  ; its unit
hidden: .res 2
dxf:    .res 2                  ; a late entry's flags
cx:     .res 2                  ; scatter
ccl:    .res 2
cch:    .res 2
y3:     .res 2
rec:    .res 2                  ; floor_draw
mofs:   .res 2
open:   .res 2
r0:     .res 2
r1:     .res 2
dst:    .res 2
ft:     .res 2


        FUNC    _rd_cols
        ldx     #0
@sv:    lda     P_MAP,x
        pha
        inx
        inx
        cpx     #NSAVE
        bne     @sv
        lda     _g_map
        sta     P_MAP
        lda     _g_map+2
        sta     P_MAP+2
        lda     _g_seen
        sta     P_SEEN
        ora     _g_seen+2
        sta     hasseen
        lda     _g_seen+2
        sta     P_SEEN+2
        lda     _g_unit_at
        sta     P_UNIT
        ora     _g_unit_at+2
        sta     hasunit
        lda     _g_unit_at+2
        sta     P_UNIT+2
        lda     RB+B_COV
        sta     P_COV
        lda     RB+B_COV+2
        sta     P_COV+2
        lda     RB+B_MCD
        sta     P_MCD
        lda     RB+B_MCD+2
        sta     P_MCD+2
        lda     RB+B_SPR
        sta     P_SPR
        lda     RB+B_SPR+2
        sta     P_SPR+2
        lda     RB+B_LATE
        sta     P_LATE
        lda     RB+B_LATE+2
        sta     P_LATE+2
        ; for (c = xlo; c <= xhi + look; c++)
        lda     RB+B_XLO
        sta     cc
@col:   lda     RB+B_XHI
        clc
        adc     RB+B_LOOK
        sec
        sbc     cc
        bpl     @in
        jmp     @end
@in:    lda     cc
        sta     RB+B_C
        lda     RB+B_XHI                ; c <= xhi && col_setup(c)
        sec
        sbc     cc
        bmi     @nolate
        lda     cc
        jsr     col_setup
        bcc     @nolate
        lda     RB+B_OCC
        beq     @ns
        jsr     slots
@ns:    jsr     col_late
@nolate:
        lda     cc                      ; t = c - look; t >= xlo && col_setup(t)
        sec
        sbc     RB+B_LOOK
        tax
        sec
        sbc     RB+B_XLO
        bmi     @next
        txa
        jsr     col_setup
        bcc     @next
        jsr     col_floors
@next:  inc     cc
        jmp     @col
@end:   ldx     #NSAVE-2
@rs:    pla
        sta     P_MAP,x
        dex
        dex
        bpl     @rs
        RET

; m1 * m2 -> A (16 bits)
mul:    stz     macc
@l:     lsr     m2
        bcc     @n
        lda     macc
        clc
        adc     m1
        sta     macc
@n:     asl     m1
        lda     m2
        bne     @l
        lda     macc
        rts

; col_setup (A = x): the column's tiles in the view: b.x, b.n, b.y, b.yend,
; b.idx; carry clear when none
col_setup:
        sta     RB+B_X
        sec
        sbc     RB+B_UB
        sta     ylo                     ; x - ub
        lda     RB+B_VC
        inc     a
        sec
        sbc     RB+B_X                  ; vc + 1 - x
        tax
        sec
        sbc     ylo
        beq     @a
        bmi     @a
        stx     ylo
@a:     lda     ylo
        bpl     @b
        stz     ylo
@b:     lda     RB+B_X
        clc                             ; x - ua0 - 1
        sbc     RB+B_UA0
        sta     yhi
        lda     RB+B_VD
        sec
        sbc     RB+B_X                  ; vd - x
        tax
        sec
        sbc     yhi
        bpl     @c
        stx     yhi
@c:     lda     RB+B_MY
        dec     a
        tax
        sec
        sbc     yhi
        bpl     @d
        stx     yhi
@d:     lda     yhi
        sec
        sbc     ylo
        bpl     @e
        clc
        rts
@e:     inc     a
        sta     RB+B_N
        lda     ylo
        sta     RB+B_Y
        clc
        adc     RB+B_N
        sta     RB+B_YEND
        lda     ylo
        sta     m1
        lda     RB+B_MX
        sta     m2
        jsr     mul
        clc
        adc     RB+B_X
        clc
        adc     RB+B_ZBASE
        sta     RB+B_IDX
        sec
        rts

; (c & 3) * 68 -> A
slot_of:
        and     #3
        sta     tmp
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     tmp                     ; * 17
        asl     a
        asl     a                       ; * 68
        rts

; slots: the cover map's slots of this column and the three before; this
; column's cleared
slots:  lda     RB+B_C
        jsr     slot_of
        sta     RB+B_S0
        jsr     @prev
        sta     RB+B_S1
        jsr     @prev
        sta     RB+B_S2
        jsr     @prev
        sta     RB+B_S3
        lda     RB+B_S0
        clc
        adc     RB+B_Y
        clc
        adc     #3
        tay
        ldx     RB+B_N
        sep     #$20
        .a8
        lda     #0
@z:     sta     [P_COV],y
        iny
        dex
        bne     @z
        rep     #$20
        .a16
        rts
@prev:  bne     @p
        lda     #4 * COVCOL
@p:     sec
        sbc     #COVCOL
        rts

; up_floor (X = entry * 2 of rq[]): carry set if that tile holds a full
; floor that is seen
up_floor:
        lda     _rd_rqx,x
        clc
        adc     RB+B_X
        cmp     RB+B_MX
        bcs     no
        lda     _rd_rqy,x
        clc
        adc     RB+B_Y
        cmp     RB+B_MY
        bcs     no
        lda     _rd_roofoff,x
        clc
        adc     RB+B_IDX
; floor_at (A = tile index)
floor_at:
        sta     ft
        asl     a
        asl     a
        tay
        lda     [P_MAP],y
        and     #$00FF
        beq     no
        tax
        lda     hasseen
        beq     @s
        ldy     ft
        lda     [P_SEEN],y
        and     #SEEN
        beq     no
@s:     txa
        asl     a
        asl     a
        asl     a
        asl     a
        ora     #15                     ; the record's byte 15 (or_sprite's high)
        tay
        lda     [P_MCD],y
        and     #$0080
        beq     no
        sec
        rts
no:     clc
        rts

; roofed: carry set if full floors of the level above cover the tile
roofed: ldx     #0
@l:     phx
        jsr     up_floor
        plx
        bcc     @r
        inx
        inx
        cpx     #13 * 2
        bne     @l
        sec
@r:     rts

; scatter: the tile's (tofs) walls' and object's cover masks into the cover map
scatter:
        lda     RB+B_OCC
        bne     @on
@r:     rts
@on:    stz     cx
        ldx     #3
        ldy     tofs
@k:     iny
        lda     [P_MAP],y
        and     #$00FF
        beq     @kn
        phy
        asl     a
        asl     a
        asl     a
        asl     a
        ora     #14
        tay
        lda     [P_MCD],y
        ora     cx
        sta     cx
        ply
@kn:    dex
        bne     @k
        lda     cx
        beq     @r
        and     #$00FF
        sta     ccl
        lda     cx
        xba
        and     #$00FF
        sta     cch
        lda     RB+B_Y
        clc
        adc     #3
        sta     y3
        sep     #$20
        .a8
        ; s0: cov[si] |= cl & 15; ch & 20h: cov[si - 1] |= 4
        rep     #$20
        .a16
        lda     RB+B_S0
        clc
        adc     y3
        tay
        sep     #$20
        .a8
        lda     ccl
        and     #15
        ora     [P_COV],y
        sta     [P_COV],y
        lda     cch
        and     #$20
        beq     @a
        dey
        lda     [P_COV],y
        ora     #4
        sta     [P_COV],y
@a:     rep     #$20
        .a16
        ; s1: cov[si - 1] |= cl >> 4; ch & 10h: cov[si] |= 8; ch & 80h: cov[si - 2] |= 4
        lda     RB+B_S1
        clc
        adc     y3
        tay
        sep     #$20
        .a8
        dey
        lda     ccl
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        ora     [P_COV],y
        sta     [P_COV],y
        iny
        lda     cch
        and     #$10
        beq     @b
        lda     [P_COV],y
        ora     #8
        sta     [P_COV],y
@b:     lda     cch
        and     #$80
        beq     @c
        dey
        dey
        lda     [P_COV],y
        ora     #4
        sta     [P_COV],y
@c:     rep     #$20
        .a16
        ; s2: cov[si - 2] |= ch & 15; ch & 40h: cov[si - 1] |= 8
        lda     RB+B_S2
        clc
        adc     y3
        tay
        sep     #$20
        .a8
        dey
        dey
        lda     cch
        and     #15
        ora     [P_COV],y
        sta     [P_COV],y
        iny
        lda     cch
        and     #$40
        beq     @d
        lda     [P_COV],y
        ora     #8
        sta     [P_COV],y
@d:     rep     #$20
        .a16
        rts

; col_late: the column's tiles with walls, objects, units or the cursor into
; late[] (with LATE_HID / LATE_ROOF), their cover masks scattered
col_late:
        lda     RB+B_X
        cmp     RB+B_CURX
        bne     @c0
        lda     RB+B_YEND
        sec
        sbc     RB+B_CURY
        and     #$00FF
        bra     @c1
@c0:    lda     #0
@c1:    sta     curleft
        lda     RB+B_Y
        sta     y0
        lda     RB+B_IDX
        sta     lidx
        stz     li
@loop:  lda     li
        cmp     RB+B_N
        bcc     @tile
        lda     y0
        sta     RB+B_Y
        rts
@tile:  lda     RB+B_N
        sec
        sbc     li
        and     #$00FF
        sta     left
        lda     lidx
        asl     a
        asl     a
        sta     tofs
        tay
        iny
        lda     [P_MAP],y               ; parts 1, 2
        sta     t123
        iny
        iny
        lda     [P_MAP],y               ; part 3 (and the next byte)
        and     #$00FF
        ora     t123
        sta     t123
        stz     uat
        lda     hasunit
        beq     @u
        ldy     lidx
        lda     [P_UNIT],y
        and     #$00FF
        sta     uat
@u:     lda     left
        cmp     curleft
        beq     @keep
        lda     t123
        ora     uat
        bne     @keep
        jmp     @next
@keep:  lda     y0
        clc
        adc     li
        sta     RB+B_Y
        lda     lidx
        sta     RB+B_IDX
        stz     hidden
        lda     hasseen
        beq     @h
        ldy     lidx
        lda     [P_SEEN],y
        and     #SEEN
        bne     @h
        inc     hidden
@h:     lda     left
        cmp     curleft
        bne     @notcur
        lda     hidden                  ; the cursor's tile
        beq     @cv
        lda     #LATEHID
        sta     dxf
        bra     @add
@cv:    jsr     scatter
        stz     dxf
        bra     @add
@notcur:
        lda     hidden
        bne     @next
        lda     t123
        beq     @nosc
        jsr     scatter
@nosc:  stz     dxf
        lda     RB+B_UP1
        beq     @add
        jsr     roofed
        bcc     @add
        lda     #LATEROOF
        sta     dxf
@add:   lda     RB+B_NLATE
        cmp     #MAXLATE
        bcc     @room
        stz     RB+B_COVON
        bra     @next
@room:  asl     a
        tay
        lda     RB+B_X
        xba
        and     #$FF00
        sta     tmp
        lda     RB+B_Y
        and     #$00FF
        ora     tmp
        ora     dxf
        sta     [P_LATE],y
        inc     RB+B_NLATE
@next:  lda     lidx
        clc
        adc     RB+B_MX
        sta     lidx
        inc     li
        jmp     @loop

; col_floors: the column's seen floors drawn
col_floors:
        lda     RB+B_X
        jsr     slot_of
        sta     RB+B_SF
        lda     RB+B_IDX
        sta     lidx
        lda     RB+B_Y
        sta     y0
        stz     li
@loop:  lda     li
        cmp     RB+B_N
        bcc     @tile
        rts
@tile:  lda     lidx
        asl     a
        asl     a
        tay
        lda     [P_MAP],y
        and     #$00FF
        beq     @next
        sta     rec
        lda     hasseen
        beq     @s
        ldy     lidx
        lda     [P_SEEN],y
        and     #SEEN
        beq     @next
@s:     lda     y0
        clc
        adc     li
        sta     RB+B_Y
        lda     lidx
        sta     RB+B_IDX
        jsr     floor_draw
@next:  lda     lidx
        clc
        adc     RB+B_MX
        sta     lidx
        inc     li
        bra     @loop

; box: the tile's box (b.sx, b.sy)
box:    lda     RB+B_X
        sec
        sbc     RB+B_Y
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     RB+B_CAMX
        sta     RB+B_SX
        lda     RB+B_X
        clc
        adc     RB+B_Y
        asl     a
        asl     a
        asl     a
        sec
        sbc     RB+B_ZY
        sta     RB+B_SY
        rts

; floor_draw (rec): the tile's floor
floor_draw:
        lda     rec
        asl     a
        asl     a
        asl     a
        asl     a
        sta     mofs
        ora     #14
        tay
        lda     [P_MCD],y
        and     #$7FFF
        cmp     #$7FFF
        bne     @or
        jsr     box
        jmp     @sprite
@or:    sta     RB+B_ORSPR
        lda     RB+B_COVON
        beq     @open
        lda     RB+B_SF
        clc
        adc     RB+B_Y
        clc
        adc     #3
        tay
        lda     [P_COV],y
        eor     #$FFFF
        and     #15
        beq     @covered
        sta     open
        lda     RB+B_UP1
        beq     @open
        ldx     #13 * 2                 ; the quads' owners above: rq[13 + q]
@q:     lsr     open
        bcc     @qn
        phx
        jsr     up_floor
        plx
        bcs     @qn
        lda     RB+B_UP2                ; a quad open on the level above
        beq     @open
        ldx     #17 * 2                 ; the tile two levels up
        jsr     up_floor
        bcs     @covered
        bra     @open
@qn:    inx
        inx
        cpx     #17 * 2
        bne     @q
@covered:
        inc     _g_occ_count
        rts
@open:  jsr     box
        lda     RB+B_Z
        beq     @z0
        jmp     @sprite
@rt:    rts
@z0:    lda     RB+B_ORSPR              ; the ground floor's OR picture
        asl     a
        asl     a
        tay
        lda     [P_SPR],y
        sta     TS
        iny
        iny
        lda     [P_SPR],y
        sta     TS+2
        lda     [TS]                    ; first row, rows
        tax
        and     #$00FF
        clc
        adc     RB+B_SY
        sta     r0
        txa
        xba
        and     #$00FF
        clc
        adc     r0
        sta     r1
        sec                             ; r1 <= cy0 || r0 >= cy1: nothing
        sbc     RB+B_CY0
        beq     @rt
        bmi     @rt
        lda     r0
        sec
        sbc     RB+B_CY1
        bpl     @rt
        lda     RB+B_SX                 ; clipped: gfx_sprite_or
        sec
        sbc     RB+B_CX0
        bmi     @clip
        lda     RB+B_CX1
        sec
        sbc     RB+B_SX
        bmi     @clip
        lda     r0
        sec
        sbc     RB+B_CY0
        bmi     @clip
        lda     RB+B_CY1
        sec
        sbc     r1
        bmi     @clip
        lda     RB+B_SY                 ; sy * 80 + (sx >> 2)
        asl     a
        asl     a
        asl     a
        asl     a
        sta     tmp
        asl     a
        asl     a
        clc
        adc     tmp
        sta     dst
        lda     RB+B_SX
        cmp     #$8000
        ror     a
        cmp     #$8000
        ror     a
        clc
        adc     dst
        sta     dst
        pea     $FFFF                   ; plat_bb_sprite(s, 1, dest, 0, FFFF, 0, FFFF)
        pea     0
        pea     $FFFF
        pea     0
        pha
        pea     1
        lda     TS+2
        pha
        lda     TS
        pha
        CALL    _plat_bb_sprite
        tax
        tsc
        clc
        adc     #16
        tcs
        txa
        bne     @ret
        lda     dst                     ; (no blitter) blitc_or(s, bufseg, dest)
        pha
        lda     RB+B_BSEG
        pha
        lda     TS+2
        pha
        lda     TS
        pha
        CALL    _blitc_or
        tsc
        clc
        adc     #8
        tcs
@ret:   rts
@clip:  lda     RB+B_SY                 ; gfx_sprite_or(orspr, sx, sy)
        pha
        lda     RB+B_SX
        pha
        lda     RB+B_ORSPR
        pha
        CALL    _gfx_sprite_or
        tsc
        clc
        adc     #6
        tcs
        rts
@sprite:
        ldy     mofs                    ; gfx_sprite(sprite, sx, sy - p_level)
        iny
        iny
        iny
        lda     [P_MCD],y
        and     #$00FF
        sta     tmp
        lda     RB+B_SY
        sec
        sbc     tmp
        pha
        lda     RB+B_SX
        pha
        ldy     mofs
        lda     [P_MCD],y
        pha
        CALL    _gfx_sprite
        tsc
        clc
        adc     #6
        tcs
        rts
