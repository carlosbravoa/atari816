; SPDX-License-Identifier: GPL-3.0-or-later
; hz_path.s - the path search on the Atari816: upstream's path_search_c
; (vbench.c: Dijkstra with cost buckets, every tile within max_tu) with
; path.c's path_step_idx, move_blocked, wall_blocks, step_part and air4, step
; for step (the C is the reference: the host runs it, BENCH compares the two:
; "path search ... C n ms, asm n ms, match"). In C it was about 85 % of an
; alien turn. plat/way.c hz_path_search fills hz_ph (the tables' far
; pointers, the map's sizes, the search's parameters) and calls hz_path_run.
        .p816
        .a16
        .i16
        .include "model.inc"
        .importzp __rg
        .import _hz_ph
        .export _hz_path_run

; hz_ph (plat/way.c struct HzPath)
H_N     = _hz_ph+32
H_MX    = _hz_ph+34
H_MY    = _hz_ph+36
H_MZ    = _hz_ph+38
H_MXY   = _hz_ph+40
H_START = _hz_ph+42
H_MAXTU = _hz_ph+44
H_OCC   = _hz_ph+46
H_FLY   = _hz_ph+48
H_DOFF  = _hz_ph+50             ; int[8]
H_DDX   = _hz_ph+66             ; int[8]
H_DDY   = _hz_ph+82             ; int[8]

PWH     = __rg+0                ; long pointers: walk tables
PWF     = __rg+4
PWC     = __rg+8
PWD     = __rg+12
PCO     = __rg+16               ; search tables
PFR     = __rg+20
PNX     = __rg+24               ; u16 a tile
PBK     = __rg+28               ; u16 a cost

WF_WEST = $01
WF_NORTH = $02
WF_SOLID = $04
WF_LIFT = $08
WF_AIR  = $20
WF_BIG  = $80
FR_Q    = $40

        .segment "BSS"
cc:     .res 2                  ; the bucket (cost) being expanded
idx:    .res 2                  ; the tile expanded: index, x, y, z, cost, height
tx:     .res 2
ty:     .res 2
tz:     .res 2
g:      .res 2
hh:     .res 2
dir:    .res 2
nc:     .res 2
ocost:  .res 2
kq:     .res 2
nidx:   .res 2                  ; a step: destination, its level, ...
bz:     .res 2
bidx:   .res 2
bdh:    .res 2
drop:   .res 2
base:   .res 2
sdx:    .res 2
sdy:    .res 2
t:      .res 2
mi:     .res 2
ix:     .res 2
iy:     .res 2
cz:     .res 2
ni:     .res 2
src2:   .res 2
dz:     .res 2
ps:     .res 2                  ; step_part: s, d, its cost, a, b
pd:     .res 2
pc:     .res 2
pa:     .res 2
pb:     .res 2
sum:    .res 2
pss:    .res 2

        .segment "CODE"

_hz_path_run:
        ldx     #30
@cp:    lda     _hz_ph,x
        sta     __rg,x
        dex
        dex
        bpl     @cp
        ldy     #0                      ; cost[] = FF (n bytes)
        lda     #$FFFF
@c1:    cpy     H_N
        bcs     @c2
        sta     [PCO],y
        iny
        iny
        bra     @c1
@c2:    ldy     #0                      ; bucket[] = FFFF
@c3:    sta     [PBK],y
        iny
        iny
        cpy     #512
        bne     @c3
        ldy     H_START
        sep     #$20
        .a8
        lda     #0
        sta     [PCO],y
        lda     #$FF
        sta     [PFR],y
        rep     #$20
        .a16
        tya
        sta     [PBK]
        asl     a
        tay
        lda     #$FFFF
        sta     [PNX],y
        stz     cc
@cl:    lda     H_MAXTU
        cmp     cc
        bcs     @wl
        RET
@nextc: inc     cc
        bra     @cl
@wl:    lda     cc                      ; while (bucket[c] != NONE)
        asl     a
        tax
        txy
        lda     [PBK],y
        cmp     #$FFFF
        beq     @nextc
        sta     idx
        asl     a
        tay
        lda     [PNX],y
        txy
        sta     [PBK],y                 ; bucket[c] = next[idx]
        ldy     idx
        sep     #$20
        .a8
        lda     [PFR],y
        and     #<~FR_Q
        sta     [PFR],y
        rep     #$20
        .a16
        lda     [PCO],y
        and     #$00FF
        sta     g
        lda     idx                     ; z, y, x
        ldx     #0
@dz:    cmp     H_MXY
        bcc     @dzd
        sbc     H_MXY
        inx
        bra     @dz
@dzd:   stx     tz
        ldx     #0
@dy:    cmp     H_MX
        bcc     @dyd
        sbc     H_MX
        inx
        bra     @dy
@dyd:   sta     tx
        stx     ty
        ldy     idx                     ; h: the standing height, or z * 24
        lda     [PWH],y
        and     #$00FF
        beq     @h0
        dec     a
        bra     @h1
@h0:    lda     tz
        asl     a
        clc
        adc     tz
        asl     a
        asl     a
        asl     a
@h1:    sta     hh
        stz     dir
@dl:    lda     dir
        cmp     #8
        bcc     @do
        cmp     #10
        bcs     @wl2
        lda     H_FLY                   ; lifts: none here and no flight: done
        bne     @do
        ldy     idx
        lda     [PWF],y
        and     #WF_LIFT
        bne     @do
@wl2:   jmp     @wl
@do:    jsr     step
        bcs     @dn
        clc
        adc     g
        sta     nc
        lda     H_MAXTU
        cmp     nc
        bcc     @dn                     ; nc > max_tu
        ldy     nidx
        lda     [PCO],y
        and     #$00FF
        sta     ocost
        cmp     nc
        bcc     @dn
        beq     @dn                     ; cost[nidx] <= nc
        lda     [PWF],y
        and     H_OCC
        and     #$00FF
        bne     @dn
        stz     kq                      ; waiting in a list: it stays there
        lda     ocost
        cmp     #$FF
        beq     @k0
        lda     [PFR],y
        and     #FR_Q
        sta     kq
@k0:    lda     tz
        asl     a
        asl     a
        asl     a
        asl     a
        ora     dir
        ora     #FR_Q
        sep     #$20
        .a8
        sta     [PFR],y
        lda     nc
        sta     [PCO],y
        rep     #$20
        .a16
        lda     kq
        bne     @dn
        lda     nc
        cmp     cc
        bcs     @ge
        lda     cc
@ge:    asl     a
        tax
        txy
        lda     [PBK],y                 ; next[nidx] = bucket[nc]
        pha
        lda     nidx
        asl     a
        tay
        pla
        sta     [PNX],y
        txy
        lda     nidx
        sta     [PBK],y                 ; bucket[nc] = nidx
@dn:    inc     dir
        jmp     @dl

; step (path_step_idx of idx, tx, ty, tz, dir; hh): carry set: none; else A
; the cost, nidx the destination
step:   lda     dir
        cmp     #8
        bcs     @lift
        jmp     horiz
@lift:  bne     @down
        lda     tz                      ; up
        inc     a
        cmp     H_MZ
        bcs     @fail
        lda     idx
        clc
        adc     H_MXY
        bra     @t
@down:  lda     tz
        beq     @fail
        lda     idx
        sec
        sbc     H_MXY
@t:     sta     t
        ldy     idx
        lda     [PWF],y
        and     #WF_LIFT
        beq     @nl
        ldy     t
        lda     [PWF],y
        and     #WF_LIFT
        bne     @ok
@nl:    lda     H_FLY
        beq     @fail
        ldy     t
        lda     [PWF],y
        and     #WF_SOLID
        bne     @fail
        lda     dir
        cmp     #8
        bne     @ai
        lda     t
        bra     @a4
@ai:    lda     idx
@a4:    jsr     air4
        bcc     @fail
@ok:    lda     t
        sta     nidx
        lda     #8
        clc
        rts
@fail:  sec
        rts

; air4 (A = i): carry set when tile i (and a 2x2 flyer's other quarters) has
; no floor
air4:   tay
        lda     [PWF],y
        and     #WF_AIR
        beq     @no
        lda     H_OCC
        and     #WF_BIG
        beq     @yes
        iny
        lda     [PWF],y
        sta     sum
        tya
        clc
        adc     H_MX
        tay
        lda     [PWF],y                 ; i + mx + 1
        and     sum
        sta     sum
        dey
        lda     [PWF],y                 ; i + mx
        and     sum
        and     #WF_AIR
        beq     @no
@yes:   sec
        rts
@no:    clc
        rts

horiz:  asl     a
        tax
        lda     tx
        clc
        adc     H_DDX,x
        cmp     H_MX
        bcs     @fail
        lda     ty
        clc
        adc     H_DDY,x
        cmp     H_MY
        bcs     @fail
        lda     H_DDX,x
        sta     sdx
        lda     H_DDY,x
        sta     sdy
        lda     idx
        clc
        adc     H_DOFF,x
        sta     base
        lda     #$FFFF
        sta     bz
        lda     #99
        sta     bdh
        stz     drop
        ldy     base
        lda     [PWH],y
        and     #$00FF
        beq     @nowh
        dec     a                       ; drop = wh - 1 - h + 8
        sec
        sbc     hh
        clc
        adc     #8
        sta     drop
        cmp     #17
        bcc     @level
        bra     @ud
@fail:  sec
        rts
@nowh:  lda     H_FLY
        beq     @ud
        lda     [PWF],y
        and     #WF_SOLID
        bne     @ud
@level: lda     idx
        jsr     mblk
        bcs     @fail
        lda     tz
        sta     bz
        lda     base
        sta     bidx
        jmp     cost
@ud:    lda     tz                      ; one down, then one up
        dec     a
        sta     cz
        lda     base
        sec
        sbc     H_MXY
        sta     ni
        lda     idx
        sec
        sbc     H_MXY
        sta     src2
        jsr     tryz
        lda     tz
        inc     a
        sta     cz
        lda     base
        clc
        adc     H_MXY
        sta     ni
        lda     idx
        clc
        adc     H_MXY
        sta     src2
        jsr     tryz
        lda     bz
        bpl     cost
        lda     drop                    ; down more than 8: a drop
        bmi     @level
        sec
        rts

; tryz: level cz (tile ni, the source's tile there src2) if closer
tryz:   lda     cz
        cmp     H_MZ
        bcs     @r
        ldy     ni
        lda     [PWH],y
        and     #$00FF
        beq     @r
        dec     a
        sec
        sbc     hh
        bpl     @p
        eor     #$FFFF
        inc     a
@p:     cmp     #9
        bcs     @r
        cmp     bdh
        bcs     @r
        sta     pa
        lda     idx
        jsr     mblk
        bcs     @r
        lda     src2
        jsr     mblk
        bcs     @r
        lda     cz
        sta     bz
        lda     pa
        sta     bdh
        lda     ni
        sta     bidx
@r:     rts

; cost: the step's TU (step_part; a 2x2 unit's four parts' average)
cost:   lda     bidx
        sta     nidx
        lda     bz
        sec
        sbc     tz
        sta     dz
        lda     idx
        sta     ps
        lda     bidx
        sta     pd
        jsr     spart
        sta     sum
        lda     H_OCC
        and     #WF_BIG
        beq     @one
        inc     ps
        inc     pd
        jsr     spart
        clc
        adc     sum
        sta     sum
        lda     idx
        clc
        adc     H_MX
        sta     ps
        lda     bidx
        clc
        adc     H_MX
        sta     pd
        jsr     spart
        clc
        adc     sum
        sta     sum
        inc     ps
        inc     pd
        jsr     spart
        clc
        adc     sum
        lsr     a
        lsr     a
        clc
        rts
@one:   lda     sum
        clc
        rts

; spart: step_part(ps, pd, dir, dz) -> A
spart:  ldy     pd
        lda     [PWC],y
        and     #$00FF
        ldx     dz
        beq     @n
        bmi     @n
        inc     a                       ; a climb: one more
@n:     sta     pc
        lda     ps
        ldx     dz
        beq     @n2
        bmi     @n2
        clc
        adc     H_MXY                   ; (the walls one level up)
@n2:    sta     pss
        lda     dir
        and     #1
        beq     @s
        lda     pc                      ; diagonal: x 1.5
        asl     a
        clc
        adc     pc
        lsr     a
        sta     pc
@s:     stz     pb                      ; b: the west walls
        lda     sdx
        beq     @b2
        bpl     @b1
        ldy     pss
        lda     [PWD],y
        and     #15
        sta     pb
        bra     @b2
@b1:    lda     dz
        bmi     @b2
        ldy     pd
        lda     [PWD],y
        and     #15
        sta     pb
@b2:    stz     pa                      ; a: the north walls
        lda     sdy
        beq     @a2
        bpl     @a1
        ldy     pss
        lda     [PWD],y
        and     #$00F0
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     pa
        bra     @a2
@a1:    lda     dz
        bmi     @a2
        ldy     pd
        lda     [PWD],y
        and     #$00F0
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     pa
@a2:    lda     dir
        cmp     #3
        bne     @sw
        ldx     pa                      ; south-east: the other way round
        lda     pb
        sta     pa
        stx     pb
@sw:    lda     pa
        beq     @nb
        lda     pb
        lsr     a
        clc
        adc     pa
        clc
        adc     pc
        rts
@nb:    lda     pb
        clc
        adc     pc
        rts

; mblk (move_blocked(A = i, sdx, sdy)): carry set when blocked
mblk:   sta     mi
        lda     sdx
        beq     @orth
        lda     sdy
        bne     @diag
@orth:  lda     mi
        ldx     sdx
        bne     wbx
        bra     wby
@diag:  lda     mi
        jsr     wbx
        bcs     @r
        lda     mi
        jsr     wby
        bcs     @r
        lda     mi
        clc
        adc     sdx
        sta     ix
        jsr     wby
        bcs     @r
        lda     sdy
        bmi     @up
        lda     mi
        clc
        adc     H_MX
        bra     @iy
@up:    lda     mi
        sec
        sbc     H_MX
@iy:    sta     iy
        jsr     wbx
        bcs     @r
        ldy     ix
        lda     [PWF],y
        ldy     iy
        ora     [PWF],y
        and     #WF_SOLID
        beq     @r                      ; (carry clear from the last wbx)
        sec
@r:     rts

; wbx (A = i): the west wall crossed by sdx; wby: the north wall by sdy
wbx:    ldx     sdx
        bmi     @t
        inc     a
@t:     tay
        lda     [PWF],y
        and     #WF_WEST
        beq     no
        sec
        rts
wby:    ldx     sdy
        bmi     @t
        clc
        adc     H_MX
@t:     tay
        lda     [PWF],y
        and     #WF_NORTH
        beq     no
        sec
        rts
no:     clc
        rts
