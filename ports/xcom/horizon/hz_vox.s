; SPDX-License-Identifier: GPL-3.0-or-later
; hz_vox.s - the voxel line on the Atari816: plat/voxrun.c's run (upstream's
; src/voxasm.asm vox_run, OpenXcom's TileEngine::calculateLine with voxel
; checks), step for step on vox.c's block. The C in voxrun.c is the reference
; (the host runs it; BENCH's 720 lines, every shot and sight line of make test
; compare the two). The same walk: the line in OpenXcom's frame (major axis,
; two minor ones, Bresenham drifts), each voxel it enters checked against the
; LOFT shapes of the tile's four parts and the unit there, R_CALL where C must
; fill in a unit or a lift (vox.c tile_info), then resumed at that voxel.
;
; Two differences in how, not in what (each multiply or divide costs hundreds
; of cycles here, and the C's skip does two of each per axis):
; - a minor axis's drift r (r -= d each main step, a move and r += d0 when it
;   goes below 0) is kept as t, the main steps to its next move (r / d + 1),
;   and b = r mod d: a step is t - 1, a move reloads t from the line's q =
;   d0 / d and rem = d0 mod d (b += rem; t = q + 1 and b -= d when b reaches
;   d, else t = q): the same moves at the same steps, one divide per minor
;   axis per line (setup), r = (t - 1) d + b back in the block at a return;
; - where the C passes the voxels of a tile's empty layers in one go (skip:
;   the main steps that keep every axis in its room, by a multiply and a divide
;   per axis), this takes the same steps from move to move of the minor axes
;   (the steps between them at once), stopping at the first step the C's
;   limits would not have taken (a minor axis's moves past its room): the same
;   position, drifts and counts after it, none of the passed voxels checked.
;
; int hz_vox_run(struct VoxRun *block, int resume)
;   the block must be in the main bank (voxrun.c checks it): X holds its
;   offset throughout (V_* below are its fields, always a:V_*,x: ca65 takes a
;   constant below 256 for a direct-page address); DBR the main bank. The
;   long pointers to the voxel blob, the map, the MCD records and the unit
;   table come from hz_vx (voxrun.c). Returns 0-3 a part, 4 a unit, R_OUT,
;   R_CALL, -1 the end.
        .p816
        .a16
        .i16
        .include "model.inc"
        .importzp __rg, __h0, __h1, __h2, __h3
        .import _hz_vx
        .export _hz_vox_run

R_OUT   = 5
R_CALL  = 6

; struct VoxRun (vox.c, voxrun.c)
V_MCDOFF  = 8
V_BASE    = 10
V_COLS    = 12
V_TMASK   = 14
V_TVAL    = 16
V_GEN     = 18
V_ROWS    = 20
V_MX      = 22
V_MY      = 24
V_MZ      = 26
V_MXY     = 28
V_EXCL    = 30                  ; byte
V_PHASE   = 31                  ; byte
V_TX      = 32
V_TY      = 34
V_TZ      = 36
V_TI      = 38
V_OX      = 40                  ; bytes: ox, oy, oz, tfl
V_OY      = 41
V_OZ      = 42
V_TFL     = 43
V_COL     = 44                  ; 4 words
V_MOVE    = 52                  ; 3 words
V_AXIS    = 58                  ; 3 bytes
V_N       = 62
V_D0      = 64
V_D1      = 66
V_D2      = 68
V_R1      = 70
V_R2      = 72
V_K       = 74
V_UBOT    = 78
V_UTOP    = 80
V_UTPL    = 82                  ; byte
V_LMASK   = 84
V_RV      = 86                  ; 4 words
V_RVA     = 94
V_URV     = 96
V_KEY     = 98                  ; byte
V_UKEY    = 99                  ; byte
V_O       = 100                 ; 3 words
V_T       = 106
V_F0      = 112
V_HIT     = 118

TF_CALL   = 1
TF_PARTS  = 2
TF_UNIT   = 4
TF_LIFT   = 8
MCD_GRAVLIFT = $20

; direct page: the long pointers, then the run's hot fields (copied from the
; block at the start, back at every return)
PVOX    = __rg+0
PMAP    = __rg+4
PMCD    = __rg+8
PUN     = __rg+12
zox     = __rg+16               ; words (the block's are bytes)
zoy     = __rg+18
zoz     = __rg+20
ztfl    = __rg+22
zn      = __rg+24
zt1v    = __rg+26               ; minor 1, 2: the main steps to the next move
zt2v    = __rg+28
zk      = __rg+30
zd0     = __rg+32
zd1     = __rg+34
zd2     = __rg+36
zkey    = __rg+38
zukey   = __rg+40
zt0     = __rg+42               ; scratch
zt1     = __rg+44
zt2     = __rg+46
zL      = __h0                  ; skip: the steps, a minor axis's room, the
zrm     = __h0+2                ;   step of its next move, its b, its moves
zpos    = __h1
zbb     = __h1+2
zm      = __h2

        .segment "RODATA"
; bit n, and bit 15 - n
ybit:   .word 1, 2, 4, 8, $10, $20, $40, $80, $100, $200, $400, $800, $1000, $2000, $4000, $8000
upmask: .word $FFE, $FFC, $FF8, $FF0, $FE0, $FC0, $F80, $F00, $E00, $C00, $800, 0
dnmask: .word 0, 1, 3, 7, $F, $1F, $3F, $7F, $FF, $1FF, $3FF, $7FF
xbit:   .word $8000, $4000, $2000, $1000, $800, $400, $200, $100, $80, $40, $20, $10, 8, 4, 2, 1

        .segment "BSS"
zres:   .res 2                  ; resume, then the result
zphase: .res 2
zcx:    .res 2                  ; check: the voxel's bit in a row
zlay:   .res 2                  ; rows: the layer
ztt:    .res 2                  ; trow: the template
tu:     .res 2
tv:     .res 2
excl:   .res 2                  ; enter_tile: the excluded unit + 1
zh:     .res 2                  ; check: the voxel's height
c0:     .res 2                  ; setup: the roles' axis codes
c1:     .res 2
c2:     .res 2
sb1:    .res 2                  ; the minor axes: r mod d, d0 / d, d0 mod d,
sb2:    .res 2                  ;   t while C runs (a resumed run)
sq1:    .res 2
sq2:    .res 2
srm1:   .res 2
srm2:   .res 2
st1:    .res 2
st2:    .res 2

        FUNC    _hz_vox_run
        ldx     #14
@cp:    lda     _hz_vx,x
        sta     __rg,x
        dex
        dex
        bpl     @cp
        lda     ARGS+4,s
        sta     zres
        lda     ARGS,s
        tax
        lda     zres
        bne     @res
        jsr     setup
        jmp     loop
@res:   jsr     load
        lda     zphase
        cmp     #1
        bne     @r2
        jmp     chk1
@r2:    cmp     #2
        bne     @r0
        jmp     chk2
@r0:    jmp     chk0

; the hot fields from the block (a resumed run)
load:   lda     a:V_OX,x
        and     #$00FF
        sta     zox
        lda     a:V_OY,x
        and     #$00FF
        sta     zoy
        lda     a:V_OZ,x
        and     #$00FF
        sta     zoz
        lda     a:V_TFL,x
        and     #$00FF
        sta     ztfl
        lda     a:V_KEY,x
        and     #$00FF
        sta     zkey
        lda     a:V_UKEY,x
        and     #$00FF
        sta     zukey
        lda     a:V_PHASE,x
        and     #$00FF
        sta     zphase
        lda     a:V_N,x
        sta     zn
        lda     st1
        sta     zt1v
        lda     st2
        sta     zt2v
        lda     a:V_K,x
        sta     zk
        lda     a:V_D0,x
        sta     zd0
        lda     a:V_D1,x
        sta     zd1
        lda     a:V_D2,x
        sta     zd2
        rts

; ---------------------------------------------------------------- the walk
loop:   stz     zphase
        lda     ztfl                    ; a tile with nothing: skip, an empty voxel
        bne     @lt
        jsr     skip
        bra     chk0e
@lt:    and     #TF_CALL | TF_UNIT | TF_LIFT    ; a plain tile's empty layer: skip
        bne     chk0
        lda     zoz
        and     #$FFFE                  ; (layer * 2)
        tay
        lda     a:V_LMASK,x
        and     ybit,y
        bne     chk0
        jsr     skip
chk0:   jsr     check
        bcs     fin
chk0e:  lda     zn
        bne     @go
        lda     #$FFFF
        bra     fin
@go:    dec     zn
        dec     zt2v                    ; (r2 -= d2: a move pending at 0)
        dec     zt1v                    ; r1 -= d1, below 0: a move
        bne     m2
        jsr     reload1
        lda     a:V_AXIS+1,x
        jsr     move
        bcs     out
        lda     #1
        sta     zphase
chk1:   jsr     check
        bcs     fin
m2:     lda     zt2v
        bne     m0
        jsr     reload2
        lda     a:V_AXIS+2,x
        jsr     move
        bcs     out
        lda     #2
        sta     zphase
chk2:   jsr     check
        bcs     fin
m0:     inc     zk
        lda     a:V_AXIS,x
        jsr     move
        bcs     out
        jmp     loop
out:    lda     #R_OUT
fin:    sta     zres
        lda     a:V_TX,x                  ; the voxel where it stopped
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     zox
        sta     a:V_HIT,x
        lda     a:V_TY,x
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     zoy
        sta     a:V_HIT+2,x
        lda     a:V_TZ,x                  ; tz * 24 + oz (tz may be -1)
        asl     a
        asl     a
        asl     a
        sta     zt0
        asl     a
        clc
        adc     zt0
        clc
        adc     zoz
        sta     a:V_HIT+4,x
        lda     zt1v                    ; the drifts: r = (t - 1) d + b
        sta     st1
        dec     a
        sta     zt0
        lda     zd1
        sta     zt1
        jsr     mul
        clc
        adc     sb1
        sta     a:V_R1,x
        lda     zt2v
        sta     st2
        dec     a
        sta     zt0
        lda     zd2
        sta     zt1
        jsr     mul
        clc
        adc     sb2
        sta     a:V_R2,x
        lda     zn                      ; the hot fields back
        sta     a:V_N,x
        lda     zk
        sta     a:V_K,x
        sep     #$20
        .a8
        lda     zox
        sta     a:V_OX,x
        lda     zoy
        sta     a:V_OY,x
        lda     zoz
        sta     a:V_OZ,x
        lda     ztfl
        sta     a:V_TFL,x
        lda     zkey
        sta     a:V_KEY,x
        lda     zukey
        sta     a:V_UKEY,x
        lda     zphase
        sta     a:V_PHASE,x
        rep     #$20
        .a16
        lda     zres
        RET

; ---------------------------------------------------------------- moves
; move: one voxel along axis code A (low byte: 2 * axis + backwards); carry
; set when it left the map (the position is then the one outside, as the C's)
move:   and     #$00FF
        cmp     #2
        bcc     @x
        cmp     #4
        bcc     @y
        bne     @zm
        inc     zoz                     ; z+
        lda     zoz
        cmp     #24
        bcs     @zp
        rts                             ; (carry clear)
@zp:    stz     zoz
        lda     a:V_TI,x
        clc
        adc     a:V_MXY,x
        sta     a:V_TI,x
        inc     a:V_TZ,x
        lda     a:V_TZ,x
        cmp     a:V_MZ,x
        bcs     @r1
        jmp     enter_tile              ; (it returns with carry clear)
@r1:    rts
@zm:    dec     zoz                     ; z-
        bmi     @zn
        clc
        rts
@zn:    lda     #23
        sta     zoz
        lda     a:V_TI,x
        sec
        sbc     a:V_MXY,x
        sta     a:V_TI,x
        dec     a:V_TZ,x
        bmi     @o2
        jmp     enter_tile
@o2:    sec
        rts
@x:     lsr     a
        bcs     @xm
        inc     zox                     ; x+
        lda     zox
        cmp     #16
        bcs     @xn
        rts
@xn:    stz     zox
        inc     a:V_TX,x
        inc     a:V_TI,x
        lda     a:V_TX,x
        cmp     a:V_MX,x
        bcs     @r3
        jmp     enter_tile
@r3:    rts
@xm:    dec     zox                     ; x-
        bmi     @xo
        clc
        rts
@xo:    lda     #15
        sta     zox
        dec     a:V_TI,x
        dec     a:V_TX,x
        bmi     @o4
        jmp     enter_tile
@o4:    sec
        rts
@y:     lsr     a
        bcs     @ym
        inc     zoy                     ; y+
        lda     zoy
        cmp     #16
        bcs     @yn
        rts
@yn:    stz     zoy
        lda     a:V_TI,x
        clc
        adc     a:V_MX,x
        sta     a:V_TI,x
        inc     a:V_TY,x
        lda     a:V_TY,x
        cmp     a:V_MY,x
        bcs     @r5
        jmp     enter_tile
@r5:    rts
@ym:    dec     zoy                     ; y-
        bmi     @yo
        clc
        rts
@yo:    lda     #15
        sta     zoy
        lda     a:V_TI,x
        sec
        sbc     a:V_MX,x
        sta     a:V_TI,x
        dec     a:V_TY,x
        bmi     @o6
        jmp     enter_tile
@o6:    sec
        rts

; shift: zt0 voxels along axis code A within the tile (no edge passed)
shift:  and     #$00FF
        lsr     a
        bcs     @back
        beq     @xp
        cmp     #1
        beq     @yp
        lda     zoz
        clc
        adc     zt0
        sta     zoz
        rts
@xp:    lda     zox
        clc
        adc     zt0
        sta     zox
        rts
@yp:    lda     zoy
        clc
        adc     zt0
        sta     zoy
        rts
@back:  beq     @xm
        cmp     #1
        beq     @ym
        lda     zoz
        sec
        sbc     zt0
        sta     zoz
        rts
@xm:    lda     zox
        sec
        sbc     zt0
        sta     zox
        rts
@ym:    lda     zoy
        sec
        sbc     zt0
        sta     zoy
        rts

; room: the moves along axis code A that stay in the tile and, for z, in its
; empty layers (the voxel's own layer is empty)
room:   and     #$00FF
        cmp     #4
        bcs     @z
        lsr     a
        bcs     @m
        bne     @yp
        lda     #15
        sec
        sbc     zox
        rts
@yp:    lda     #15
        sec
        sbc     zoy
        rts
@m:     bne     @ym
        lda     zox
        rts
@ym:    lda     zoy
        rts
@z:     bne     @zm
        lda     zoz                     ; up: to the top, or below the first
        and     #$FFFE                  ; filled layer j above: 2 j - 1 - oz
        tay
        lda     a:V_LMASK,x
        and     upmask,y
        bne     @us
        lda     #23
        sec
        sbc     zoz
        rts
@us:    sta     zt1
@u:     iny
        iny
        lda     zt1
        and     ybit,y
        beq     @u
        tya
        clc
        sbc     zoz
        rts
@zm:    lda     zoz                     ; down: to the bottom, or above the
        and     #$FFFE                  ; first filled layer j below: oz - 2 j - 2
        tay
        lda     a:V_LMASK,x
        and     dnmask,y
        bne     @ds
        lda     zoz
        rts
@ds:    sta     zt1
@d:     dey
        dey
        lda     zt1
        and     ybit,y
        beq     @d
        sty     zt1
        lda     zoz
        sec
        sbc     zt1
        dec     a
        dec     a
        rts

; skip: the main steps the C's skip passes at once (voxrun.c): L, the major
; axis's room (at most n), cut by each minor axis's room when its moves reach
; it (limit), then each minor axis's moves in those L steps (advance)
.macro  LIMIT   t, b, q, rem, d, ax
        .local  lp0, lp, mv, sm, nx, out
        lda     t                       ; no move within L: no limit
        cmp     zL
        beq     lp0
        bcs     out
lp0:    lda     a:ax,x
        jsr     room
        sta     zrm
        lda     t
        sta     zpos
        lda     b
        sta     zbb
        stz     zm
lp:     lda     zm                      ; a move at zpos: past the room?
        cmp     zrm
        bne     mv
        lda     zpos
        dec     a
        sta     zL
        bra     out
mv:     inc     zm
        lda     zbb                     ; the step of the next move
        clc
        adc     rem
        cmp     d
        bcc     sm
        sbc     d
        sta     zbb
        lda     zpos
        sec                             ; (q + 1)
        adc     q
        bra     nx
sm:     sta     zbb
        lda     zpos
        clc
        adc     q
nx:     sta     zpos
        cmp     zL
        bcc     lp
        beq     lp
out:
.endmacro

.macro  ADVANCE t, b, q, rem, d, ax
        .local  lp, mv, sm, done
        lda     zL
        sta     zpos                    ; the steps left
        stz     zm
lp:     lda     t
        cmp     zpos
        beq     mv
        bcs     done
mv:     lda     zpos                    ; the move at step t
        sec
        sbc     t
        sta     zpos
        inc     zm
        lda     b
        clc
        adc     rem
        cmp     d
        bcc     sm
        sbc     d
        sta     b
        lda     q
        inc     a
        sta     t
        bra     lp
sm:     sta     b
        lda     q
        sta     t
        bra     lp
done:   lda     t
        sec
        sbc     zpos
        sta     t
        lda     zm
        beq     :+
        sta     zt0
        lda     a:ax,x
        jsr     shift
:
.endmacro

; ADVLIM: minor 1 over the L steps, stopping before a move past its room (L
; then the steps before it): the busier axis in one pass
.macro  ADVLIM  t, b, q, rem, d, ax
        .local  lp, mv, mv1, sm, stop, done
        lda     zL
        sta     zpos                    ; the steps left
        stz     zm
        lda     #$FFFF                  ; its room: not looked at yet
        sta     zrm
lp:     lda     t
        cmp     zpos
        beq     mv
        bcs     done
mv:     lda     zrm                     ; a move at step t: within the room?
        cmp     #$FFFF
        bne     mv1
        lda     a:ax,x
        jsr     room
        sta     zrm
mv1:    lda     zm
        cmp     zrm
        beq     stop
        lda     zpos
        sec
        sbc     t
        sta     zpos
        inc     zm
        lda     b
        clc
        adc     rem
        cmp     d
        bcc     sm
        sbc     d
        sta     b
        lda     q
        inc     a
        sta     t
        bra     lp
sm:     sta     b
        lda     q
        sta     t
        bra     lp
stop:   lda     zL                      ; the steps taken: L - left + t - 1
        sec
        sbc     zpos
        clc
        adc     t
        dec     a
        sta     zL
        lda     #1                      ; its move is the next step's
        sta     t
        bra     :+
done:   lda     t
        sec
        sbc     zpos
        sta     t
:       lda     zm
        beq     :+
        sta     zt0
        lda     a:ax,x
        jsr     shift
:
.endmacro

skip:   lda     a:V_AXIS,x
        jsr     room
        cmp     zn
        bcc     sk0
        lda     zn
sk0:    sta     zL
        tay                             ; (sets Z: no room, no step)
        bne     sk1
        rts
sk1:    LIMIT   zt2v, sb2, sq2, srm2, zd2, V_AXIS+2
        lda     zL
        bne     sk2
        rts
sk2:    ADVLIM  zt1v, sb1, sq1, srm1, zd1, V_AXIS+1
        lda     zL
        bne     sk3
        rts
sk3:    lda     zn
        sec
        sbc     zL
        sta     zn
        lda     zk
        clc
        adc     zL
        sta     zk
        lda     zL
        sta     zt0
        lda     a:V_AXIS,x
        jsr     shift
        ADVANCE zt2v, sb2, sq2, srm2, zd2, V_AXIS+2
        rts

; reload1, reload2: minor 1 / 2 moves: t for the next move (b += rem; b >= d:
; b -= d, t = q + 1; else t = q)
reload1:
        lda     sb1
        clc
        adc     srm1
        cmp     zd1
        bcc     @s
        sbc     zd1
        sta     sb1
        lda     sq1
        inc     a
        sta     zt1v
        rts
@s:     sta     sb1
        lda     sq1
        sta     zt1v
        rts
reload2:
        lda     sb2
        clc
        adc     srm2
        cmp     zd2
        bcc     @s
        sbc     zd2
        sta     sb2
        lda     sq2
        inc     a
        sta     zt2v
        rts
@s:     sta     sb2
        lda     sq2
        sta     zt2v
        rts

; mul: A = zt0 * zt1 (16 bits)
mul:    lda     #0
@l:     lsr     zt0
        bcc     @n
        clc
        adc     zt1
@n:     asl     zt1
        ldy     zt0
        bne     @l
        rts

; div: zt0 / zt1: zt0 the quotient, A the remainder (zt1 below 32768)
div:    lda     zt1                     ; k: d << k above n (n < 32768)
        ldy     #0
@s:     cmp     zt0
        beq     @e
        bcs     @t
        asl     a
        iny
        bra     @s
@e:     asl     a
        iny
@t:     sta     zt2                     ; then k quotient bits
        lda     zt0
        stz     zt0
@l:     dey
        bmi     @r
        lsr     zt2
        asl     zt0
        cmp     zt2
        bcc     @l
        sbc     zt2
        inc     zt0
        bra     @l
@r:     rts

; ---------------------------------------------------------------- the tile
; enter_tile: the parts' columns of tile V_TI and whether C must add to them
.macro  PART    p
        .local  none, next
        ldy     zt0
        .if p > 0
        .repeat p
        iny
        .endrep
        .endif
        lda     [PMAP],y
        and     #$00FF
        beq     none
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     a:V_MCDOFF,x
        clc
        adc     #6
        tay
        lda     [PMCD],y                ; the record's column (Mcd.vcol)
        and     #$00FF
        beq     none
        asl     a
        asl     a
        clc
        adc     a:V_COLS,x
        tay
        lda     [PVOX],y
        clc
        adc     a:V_BASE,x
        sta     a:V_COL+2*p,x
        iny
        iny
        lda     [PVOX],y                ; its layers
        ora     a:V_LMASK,x
        sta     a:V_LMASK,x
        lda     #TF_PARTS
        tsb     zt2
        bra     next
none:   stz     a:V_COL+2*p,x
next:
.endmacro

enter_tile:
        lda     #$FFFF
        sta     zkey
        sta     zukey
        stz     zt2                     ; the flags
        stz     a:V_LMASK,x
        lda     a:V_TI,x
        asl     a
        asl     a
        sta     zt0
        tay
        lda     [PMAP],y
        iny
        iny
        ora     [PMAP],y
        bne     et_parts
        stz     a:V_COL,x                 ; open air
        stz     a:V_COL+2,x
        stz     a:V_COL+4,x
        stz     a:V_COL+6,x
        jmp     et_units
et_parts: PART    0
        PART    1
        PART    2
        PART    3
        ldy     zt0                     ; a grav lift's floor: C decides
        lda     [PMAP],y
        and     #$00FF
        beq     et_units
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     a:V_MCDOFF,x
        clc
        adc     #8
        tay
        lda     [PMCD],y
        and     #MCD_GRAVLIFT
        beq     et_units
        lda     #TF_CALL
        tsb     zt2
        bra     et_done
et_units: lda     a:V_EXCL,x                ; a unit here or below: C decides
        and     #$00FF
        cmp     #$FF
        beq     et_done
        sta     excl
        ldy     a:V_TI,x
        lda     [PUN],y
        and     #$00FF
        beq     et_below
        cmp     excl
        beq     et_done
        bra     et_call
et_below: lda     a:V_TZ,x
        beq     et_done
        lda     a:V_TI,x
        sec
        sbc     a:V_MXY,x
        tay
        lda     [PUN],y
        and     #$00FF
        beq     et_done
        cmp     excl
        beq     et_done
et_call:  lda     #TF_CALL
        tsb     zt2
et_done:  lda     zt2
        sta     ztfl
        clc                             ; (move's tail calls)
        rts

; ---------------------------------------------------------------- checks
; trow: row y (zoy) of template A (low byte) -> A
trow:   and     #$00FF
        beq     @z
        sta     ztt
        asl     a
        clc
        adc     a:V_TMASK,x
        tay
        lda     zoy
        asl     a
        sta     tu
        lda     [PVOX],y
        ldy     tu
        and     ybit,y
        beq     @z
        lda     ztt
        clc
        adc     a:V_TVAL,x
        tay
        lda     [PVOX],y
        and     #$00FF
        bit     #$80
        beq     @g
        and     #$7F                    ; a general template: row (al & 7F) * 16 + y
        asl     a
        asl     a
        asl     a
        asl     a
        sta     tu
        clc
        adc     zoy
        and     #$00FF
        sta     tv
        lda     tu
        and     #$FF00
        ora     tv
        clc
        adc     a:V_GEN,x
        tay
        lda     [PVOX],y
        and     #$00FF
@g:     asl     a
        clc
        adc     a:V_ROWS,x
        tay
        lda     [PVOX],y
        rts
@z:     lda     #0
        rts

; rows: the four parts' rows at the voxel's layer and y, and all ORed
.macro  ROW     p
        .local  rw, rf, rz, rs
        lda     a:V_COL+2*p,x
        beq     rz
        tay
rw:      lda     [PVOX],y
        and     #$00FF
        cmp     zlay
        bcs     rf
        iny
        iny
        bra     rw
rf:      iny
        lda     [PVOX],y
        jsr     trow
        bra     rs
rz:      lda     #0
rs:      sta     a:V_RV+2*p,x
        ora     a:V_RVA,x
        sta     a:V_RVA,x
.endmacro

rows:   lda     zoz
        lsr     a
        sta     zlay
        stz     a:V_RVA,x
        ROW     0
        ROW     1
        ROW     2
        ROW     3
        rts

; check: carry clear: the voxel is empty; else A what the run stops with (0-3
; a part, 4 a unit, 0 a lift's floor, R_CALL)
check:  lda     ztfl
        bit     #TF_CALL
        beq     @c1
        lda     #R_CALL
        sec
        rts
@c1:    bit     #TF_PARTS | TF_UNIT | TF_LIFT
        bne     @c2
@e:     clc
        rts
@c2:    bit     #TF_LIFT
        beq     @c3
        lda     zoz
        cmp     #2
        bcs     @c3
        lda     #0
        sec
        rts
@c3:    lda     zox
        asl     a
        tay
        lda     xbit,y
        sta     zcx
        lda     ztfl
        bit     #TF_PARTS
        beq     @unit
        lda     zoz                     ; (layer * 2) * 8 + y, as the C's key
        and     #$00FE
        asl     a
        asl     a
        asl     a
        ora     zoy
        cmp     zkey
        beq     @k
        sta     zkey
        jsr     rows
@k:     lda     a:V_RVA,x
        and     zcx
        beq     @unit
        lda     a:V_RV,x
        and     zcx
        beq     @p1
        lda     #0
        sec
        rts
@p1:    lda     a:V_RV+2,x
        and     zcx
        beq     @p2
        lda     #1
        sec
        rts
@p2:    lda     a:V_RV+4,x
        and     zcx
        beq     @p3
        lda     #2
        sec
        rts
@p3:    lda     #3
        sec
        rts
@unit:  lda     ztfl
        bit     #TF_UNIT
        beq     @ue
        lda     a:V_TZ,x                  ; h = (u8)tz * 24 + oz
        and     #$00FF
        asl     a
        asl     a
        asl     a
        sta     zh
        asl     a
        clc
        adc     zh
        clc
        adc     zoz
        sta     zh
        sec                             ; h <= ubot: empty (signed)
        sbc     a:V_UBOT,x
        beq     @ue
        bvc     @v1
        eor     #$8000
@v1:    bmi     @ue
        lda     a:V_UTOP,x                ; h > utop: empty
        sec
        sbc     zh
        bvc     @v2
        eor     #$8000
@v2:    bmi     @ue
        lda     zoy
        cmp     zukey
        beq     @u
        sta     zukey
        lda     a:V_UTPL,x
        jsr     trow
        sta     a:V_URV,x
@u:     lda     a:V_URV,x
        and     zcx
        beq     @ue
        lda     #4
        sec
        rts
@ue:    clc
        rts

; drift: a minor axis of delta A from r = d0 / 2: A = t, Y = b, zt0 = q, zt2 =
; rem (d0 = q d + rem; q even: r = (q / 2) d + rem / 2, odd: ((q - 1) / 2) d +
; (d + rem) / 2, the last below d: t = q / 2 + 1 either way). No delta: no
; move ever (t FFFF), b = r (r = (t - 1) * 0 + b)
drift:  sta     zt1
        tay
        bne     @d
        lda     zd0
        lsr     a
        tay
        lda     #$FFFF
        rts
@d:     lda     zd0
        sta     zt0
        jsr     div
        sta     zt2                     ; rem
        lda     zt0
        lsr     a
        bcc     @ev
        lda     zt1                     ; q odd: b = (d + rem) / 2
        clc
        adc     zt2
        ror     a
        bra     @b
@ev:    lda     zt2                     ; q even: b = rem / 2
        lsr     a
@b:     tay
        lda     zt0
        lsr     a
        inc     a
        rts

; ---------------------------------------------------------------- setup
; the line in OpenXcom's frame: the roles' axes and deltas, the drifts, the
; origin's tile (the extension of a line past its target: voxrun.c, before)
.macro  DELTA   i, d, c
        ldy     #2*i                    ; d = |t - o|, the code 2 i + (t < o)
        lda     a:V_T+2*i,x
        sec
        sbc     a:V_O+2*i,x
        bpl     :+
        eor     #$FFFF
        inc     a
        iny
:       sta     d
        sty     c
.endmacro
.macro  F0      i, c
        lda     c                       ; f0[i] = o[axis[i] >> 1]
        and     #$FFFE
        sta     zt0
        txa
        clc
        adc     zt0
        tay
        lda     a:V_O,y
        sta     a:V_F0+2*i,x
.endmacro

setup:  DELTA   0, zd0, c0
        DELTA   1, zd1, c1
        DELTA   2, zd2, c2
        lda     zd1                     ; the major axis: the longest
        cmp     zd0
        beq     @s2
        bcc     @s2
        ldy     zd0
        sta     zd0
        sty     zd1
        lda     c0
        ldy     c1
        sta     c1
        sty     c0
@s2:    lda     zd2
        cmp     zd0
        beq     @s3
        bcc     @s3
        ldy     zd0
        sta     zd0
        sty     zd2
        lda     c0
        ldy     c2
        sta     c2
        sty     c0
@s3:    lda     zd0
        sta     a:V_D0,x
        sta     zn
        lda     zd1
        sta     a:V_D1,x
        lda     zd2
        sta     a:V_D2,x
        lda     c0                      ; move[i] = axis[i]
        sta     a:V_MOVE,x
        lda     c1
        sta     a:V_MOVE+2,x
        lda     c2
        sta     a:V_MOVE+4,x
        sep     #$20
        .a8
        lda     c0
        sta     a:V_AXIS,x
        lda     c1
        sta     a:V_AXIS+1,x
        lda     c2
        sta     a:V_AXIS+2,x
        rep     #$20
        .a16
        F0      0, c0
        F0      1, c1
        F0      2, c2
        stz     zk
        lda     zd1                     ; the minor axes' t, b, q, rem from r = d0 / 2
        jsr     drift
        sta     zt1v
        sty     sb1
        lda     zt0
        sta     sq1
        lda     zt2
        sta     srm1
        lda     zd2
        jsr     drift
        sta     zt2v
        sty     sb2
        lda     zt0
        sta     sq2
        lda     zt2
        sta     srm2
        lda     a:V_O,x                   ; the origin's voxel and tile
        and     #15
        sta     zox
        lda     a:V_O,x
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     a:V_TX,x
        lda     a:V_O+2,x
        and     #15
        sta     zoy
        lda     a:V_O+2,x
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     a:V_TY,x
        lda     a:V_O+4,x                 ; tz = o2 / 24, oz = o2 % 24 (unsigned)
        ldy     #0
@z:     cmp     #24
        bcc     @zd
        sbc     #24
        iny
        bra     @z
@zd:    sta     zoz
        tya
        sta     a:V_TZ,x
        lda     a:V_TY,x                  ; ti = tz * mxy + ty * mx + tx (16 bits)
        sta     zt0
        lda     a:V_MX,x
        sta     zt1
        lda     #0
@m:     lsr     zt0
        bcc     @m1
        clc
        adc     zt1
@m1:    asl     zt1
        ldy     zt0
        bne     @m
        clc
        adc     a:V_TX,x
        ldy     a:V_TZ,x
@mz:    beq     @md
        clc
        adc     a:V_MXY,x
        dey
        bra     @mz
@md:    sta     a:V_TI,x
        jmp     enter_tile
