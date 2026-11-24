; SPDX-License-Identifier: GPL-3.0-or-later
; hz_fan.s - the fog of war's walk on the Atari816: plat/losfan.c walk_from (one
; sight ray on one level, tile by tile, until its end, a wall or an object; each
; tile it reaches, and the one under it where it has no floor, becomes seen) step
; for step; the C is the reference (the host runs it; -DFANCHECK compares the
; two on every fan). About 80 % of a fan's time was this loop in C, each of its
; table reads a far pointer's. plat/losfan.c copies the walk's state into hz_fw
; (struct HzFan) and back.
;
; int hz_fan_walk(int wall_al)
;   wall_al >= 0: entered at the C's "wall" (the tile at si, flags wall_al, seen
;   through a wall or floor, ends the ray); returns 1 when the ray stopped before
;   its end, 0 at p_end
        .p816
        .a16
        .i16
        .include "model.inc"
        .importzp __rg
        .import _hz_fw
        .export _hz_fan_walk

; struct HzFan (plat/losfan.c)
F_LF    = _hz_fw+0              ; const u8 far *: the sight flags
F_SN    = _hz_fw+4              ; u8 far *: the seen table
F_SI    = _hz_fw+8              ; u16s
F_DXR   = _hz_fw+10
F_BPR   = _hz_fw+12
F_CXR   = _hz_fw+14
F_PADD  = _hz_fw+16
F_PADDD = _hz_fw+18
F_PA1   = _hz_fw+20
F_PA2   = _hz_fw+22
F_PA3   = _hz_fw+24
F_PB1   = _hz_fw+26
F_PB2   = _hz_fw+28
F_PB3   = _hz_fw+30
F_BL    = _hz_fw+32             ; u8s
F_BH    = _hz_fw+33
F_AH    = _hz_fw+34
F_PNEG  = _hz_fw+35
F_PPOS  = _hz_fw+36
F_PEND  = _hz_fw+37
F_PMSTEP = _hz_fw+38
F_PLIM  = _hz_fw+39
F_PH    = _hz_fw+40
F_PH2   = _hz_fw+41
F_PA1B  = _hz_fw+42
F_PA3B  = _hz_fw+43
F_PB1B  = _hz_fw+44
F_PB3B  = _hz_fw+45
F_KEY   = _hz_fw+46
F_ZCUR  = _hz_fw+47
F_REV   = _hz_fw+48             ; set to 1 when a tile became seen
F_BOX   = _hz_fw+50             ; u8[6]: x0 x1 y0 y1 z0 z1

LF_OBJECT = $04
LF_FLOOR = $08
SEEN    = $10

PLF     = __rg+0                ; long pointers
PSN     = __rg+4

        .segment "BSS"
al_:    .res 2
dh:     .res 2
under:  .res 2
sisave: .res 2
bx:     .res 2
by:     .res 2

        FUNC    _hz_fan_walk
        lda     F_LF
        sta     PLF
        lda     F_LF+2
        sta     PLF+2
        lda     F_SN
        sta     PSN
        lda     F_SN+2
        sta     PSN+2
        ldy     F_SI
        lda     ARGS,s
        bmi     @step
        sep     #$20
        .a8
        sta     al_
        bra     @wall

        .a16
@step:  lda     F_DXR                   ; dxr += bpr; a carry: the diagonal step
        clc
        adc     F_BPR
        sta     F_DXR
        sep     #$20
        .a8
        lda     F_BL                    ; bl += ah (lda leaves the carry)
        bcc     @nd
        jmp     @diag
@nd:    clc
        adc     F_AH
        sta     F_BL
        lda     [PLF],y                 ; the wall behind: the ray stops
        and     F_PNEG
        bne     @ret1
        rep     #$20
        .a16
        tya
        clc
        adc     F_PADD
        tay
        sep     #$20
        .a8
        lda     [PLF],y
        sta     al_
        and     F_PPOS
        beq     @mark
@wall:  lda     al_
        ora     #LF_OBJECT
        sta     al_
@mark:  lda     [PSN],y                 ; seen now
        and     #SEEN
        bne     @m1
        stz     under
        jsr     seen_new
@m1:    lda     al_                     ; no floor: the tile under it too
        and     #LF_FLOOR
        bne     @m2
        rep     #$20
        .a16
        lda     F_CXR
        beq     @m2a
        sty     sisave
        tya
        sec
        sbc     F_CXR
        tay
        sep     #$20
        .a8
        lda     [PSN],y
        and     #SEEN
        bne     @m3
        lda     #1
        sta     under
        jsr     seen_new
@m3:    ldy     sisave
        bra     @m2
@m2a:   sep     #$20
@m2:    lda     al_                     ; an object: the end
        and     #LF_OBJECT
        bne     @ret1
        lda     F_BL
        cmp     F_PEND
        rep     #$20
        .a16
        beq     @r0
        jmp     @step
@r0:    sty     F_SI
        lda     #0
        RET
@ret1:  rep     #$20
        .a16
        sty     F_SI
        lda     #1
        RET

        .a8
@diag:  clc                             ; (A = bl)
        adc     F_AH
        sta     F_BL
        lda     F_BH                    ; bh += p_mstep: out of the map, the end
        clc
        adc     F_PMSTEP
        sta     F_BH
        cmp     F_PLIM
        bcs     @ret1
        sty     sisave
        lda     F_DXR+1
        sta     dh
        cmp     F_PH                    ; dh > p_h: route b
        beq     @ra
        bcs     @rb
@ra:    rep     #$20                    ; route a: lf[si + a1] & a1b, [si + a2] an
        .a16                            ; object, [si + a3] & a3b
        lda     sisave
        clc
        adc     F_PA1
        tay
        sep     #$20
        .a8
        lda     [PLF],y
        and     F_PA1B
        bne     @ahit
        rep     #$20
        .a16
        lda     sisave
        clc
        adc     F_PA2
        tay
        sep     #$20
        .a8
        lda     [PLF],y
        and     #LF_OBJECT
        bne     @ahit
        rep     #$20
        .a16
        lda     sisave
        clc
        adc     F_PA3
        tay
        sep     #$20
        .a8
        lda     [PLF],y
        and     F_PA3B
        bne     @ahit
        stz     al_                     ; open
        bra     @to
@ahit:  lda     dh                      ; closed, unless dh == p_h2: route b
        cmp     F_PH2
        beq     @rb
        lda     #LF_OBJECT
        sta     al_
        bra     @to
@rb:    rep     #$20
        .a16
        lda     sisave
        clc
        adc     F_PB1
        tay
        sep     #$20
        .a8
        lda     [PLF],y
        and     F_PB1B
        bne     @bc
        rep     #$20
        .a16
        lda     sisave
        clc
        adc     F_PB2
        tay
        sep     #$20
        .a8
        lda     [PLF],y
        and     #LF_OBJECT
        bne     @bc
        rep     #$20
        .a16
        lda     sisave
        clc
        adc     F_PB3
        tay
        sep     #$20
        .a8
        lda     [PLF],y
        and     F_PB3B
        bne     @bc
        stz     al_
        bra     @to
@bc:    lda     #LF_OBJECT
        sta     al_
@to:    rep     #$20                    ; si += p_addd; al |= lf[si]
        .a16
        lda     sisave
        clc
        adc     F_PADDD
        tay
        sep     #$20
        .a8
        lda     [PLF],y
        ora     al_
        sta     al_
        jmp     @mark

; seen_new (A 8 bits, Y = the tile, under): seen, and the box (x, y, z: bl, bh,
; or the other way round in odd octants; z the ray's level or the one under it)
        .a8
seen_new:
        lda     [PSN],y
        ora     #SEEN
        sta     [PSN],y
        lda     #1
        sta     F_REV
        lda     F_KEY
        and     #1
        bne     @sw
        lda     F_BL
        sta     bx
        lda     F_BH
        sta     by
        bra     @b
@sw:    lda     F_BH
        sta     bx
        lda     F_BL
        sta     by
@b:     lda     bx
        cmp     F_BOX
        bcs     @1
        sta     F_BOX
@1:     cmp     F_BOX+1
        beq     @2
        bcc     @2
        sta     F_BOX+1
@2:     lda     by
        cmp     F_BOX+2
        bcs     @3
        sta     F_BOX+2
@3:     cmp     F_BOX+3
        beq     @4
        bcc     @4
        sta     F_BOX+3
@4:     lda     F_ZCUR
        sec
        sbc     under
        cmp     F_BOX+4
        bcs     @5
        sta     F_BOX+4
@5:     cmp     F_BOX+5
        beq     @6
        bcc     @6
        sta     F_BOX+5
@6:     rts
