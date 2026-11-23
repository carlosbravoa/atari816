; hz_probe.s - the simulation's hot spots for the Atari816 (round 2): the collision probe
; (level.c's level_is_inside_tile_128), gameplay.c's move_to16 and the bounce's scans. The C
; is the reference: srtool probecheck and srsimcheck check it on the PC against the code
; before round 2; /PROBECHECK and /MOVECHECK check this file against that C on the Atari816.
;
; The cells: the level's cell_bits (a byte a cell: bit 0 not empty, 1 tunnel, 2 cube, 3 cube
; 120 high; 8 a row, the 8th 0: no cell); hz_sim.c's near tables take a whole unit of x
; (128) to its column (7: none) and to its 46-unit tile's start (* 5888).
;
; bool hz_probe(const Level *level, int32_t x, int32_t y, int32_t z)
;   level_is_inside_tile_128: for x 6272..57855 and y -20000..32767 (the 16-bit form's range)
;   worked out here; any other x or y goes to level_is_inside_tile_128_ref (the same
;   arguments: a tail jump), a level hz_sim.c has not taken yet to hzp_newlevel.
; bool hz_probe16(const Level *level, uint16_t x, int y, unsigned zrow)
;   the same for x 6272..57855, y -20000..32767 and the row of a z >= 0 (level_probe16)
; bool hz_move16(Ship *s, const Ship *dest, const Level *level)
;   gameplay.c's gameplay_move16_c: false (nothing done) outside its range
; unsigned hz_scan16(const Level *level, uint16_t x, int y, unsigned zrow, int step)
;   the first i of 1..14 where the probe at x + i * step is outside, 0 if none (the bounce's
;   two scans: step +-128; every x probed in 6272..57855)
        .p816
        .a16
        .i16
        .smart  +
        .include "model.inc"
        .importzp __rg
        .import _hzp_level, _hzp_len, _hzp_bits, _hzp_unitcol, _hzp_m5888, _hzp_lows, _hzp_ceils
        .import _hzp_div5, _hzp_mul51, _hzp_fifth
        .import _hzp_newlevel, _hzp_newlevel16, _hzm_newlevel, _hzs_newlevel
        .import _level_is_inside_tile_128_ref
        .export _hz_probe, _hz_probe16, _hz_move16, _hz_scan16
        .export _hzq_pcore, _hzq_tiles, _hzq_cellb, _hzq_tiley, _hzq_qpos, _hzq_div5

; the probe's registers
rowb    = __rg+0                ; the row's first byte in cell_bits
px      = __rg+2
py      = __rg+4
lt      = __rg+6
dist    = __rg+8
adjx    = __rg+10               ; the adjacent tile's x
cb      = __rg+12
y2      = __rg+14
bits    = __rg+16               ; long: cell_bits (4)
; hz_move16's and hz_scan16's
sps     = __rg+20               ; the ship
spd     = __rg+22               ; dest
mx_     = __rg+24               ; x now (16 bits)
my_     = __rg+26               ; y now
mtx     = __rg+28               ; dest's x, y
mty     = __rg+30
zlo     = __rg+32               ; z now (32 bits)
zhi     = __rg+34
dd      = __rg+36               ; dest's z - z (16 bits)
kk      = __rg+38               ; a step * 2 (the FIFTH tables' index)
gran    = __rg+40
tmp     = __rg+42
mrow    = __rg+44               ; the z walk's last row probed, its answer
mans    = __rg+46

        .segment "BSS"
nx:     .res 2                  ; x moves down (dest < x): $FFFF, else 0
ny:     .res 2
ax:     .res 2                  ; |delta| / 5 an axis
ay:     .res 2
az:     .res 2
fx:     .res 2                  ; (|delta| % 5) * 12: the axis' row of hzp_fifth
fy:     .res 2
fz:     .res 2
accx:   .res 2                  ; ax * step, ...
accy:   .res 2
accz:   .res 2
z0lo:   .res 2
z0hi:   .res 2
z1lo:   .res 2
sx0:    .res 2                  ; x, y at the start
sy0:    .res 2
qzlo:   .res 2                  ; qpos's z
qzhi:   .res 2

        .segment "CODE"

; ---- the probe: A = the row, px, py, bits set -> carry set when inside
_hzq_pcore:
pcore:  cmp     a:_hzp_len
        bcs     @no             ; past the road
        asl     a
        asl     a
        asl     a
        sta     rowb
        lda     px              ; the cells 14 units left and right: both empty -> no
        sec
        sbc     #1792
        jsr     cellb
        sta     lt
        lda     px
        clc
        adc     #1792
        jsr     cellb
        ora     lt
        lsr     a               ; (bit 0: not empty)
        bcc     @no
        lda     py              ; 0x1E80 < y < 0x2800: inside; y <= 0x1E80: not
        bmi     @no
        cmp     #$2800
        bcs     tiles
        cmp     #$1E81          ; (carry set: y > 0x1E80)
        rts
@no:    clc
        rts

_hzq_tiles:
tiles:  ; y >= 0x2800 here: y and y2 = y - 68 * 128 are positive (unsigned compares). Above
        ; 120 * 128 nothing is inside (the tunnels' ceilings are below 100 * 128, the cubes'
        ; tops at 100 or 120); nor in a row of neither tunnels nor cubes (bit 4 of its 8th byte)
        cmp     #120 * 128
        bcs     @out
        tax
        lda     rowb
        ora     #7
        tay
        lda     [bits],y
        and     #$0010
        beq     @out
        txa
        sec
        sbc     #68 * 128
        sta     y2
        ; v = x - 6272, rem = v - floor(v / 5888) * 5888 (by whole units: nested floors)
        lda     px
        sec
        sbc     #6272
        sta     dist
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        and     #$FFFE
        tax
        lda     dist
        sec
        sbc     a:_hzp_m5888,x
        cmp     #2945           ; the far side: rem > 2944
        bcc     @near
        sbc     #2816           ; 128 + rem - 2944 (carry set)
        sta     dist
        lda     px
        clc
        adc     #5888
        bra     @c
@near:  sta     dist
        lda     #2944
        sec
        sbc     dist
        sta     dist
        lda     px
        sec
        sbc     #5888
@c:     sta     adjx
        lda     px
        jsr     cellb
        jsr     tiley
        bcc     @in
        lda     #6016
        sec
        sbc     dist
        cmp     #4800           ; (d + 64) >> 7 > 37: never inside
        bcs     @out
        sta     dist
        lda     adjx
        jsr     cellb
        jsr     tiley
        bcc     @in
@out:   clc
        rts
@in:    sec
        rts

; A = x (a 16-bit 1/128 position) -> A = the cell's byte in the row (0: no cell / empty)
_hzq_cellb:
cellb:  sec
        sbc     #12160
        bcc     @e              ; x < 95 * 128
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        and     #$FFFE          ; the unit * 2
        tax
        lda     a:_hzp_unitcol,x
        clc
        adc     rowb
        tay
        lda     [bits],y
        and     #$00FF
        rts
@e:     lda     #0
        rts

; is_inside_tile_y_128(y, dist, the cell's byte A) -> carry CLEAR when inside
_hzq_tiley:
tiley:  bit     #6              ; tunnel or cube?
        beq     @f
        sta     cb
        lda     dist
        clc
        adc     #64
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        cmp     #38
        bcs     @f              ; distance_index > 37
        asl     a
        tax
        lda     cb
        bit     #4
        beq     @tun            ; a tunnel alone
        bit     #2
        beq     @cube
        lda     a:_hzp_lows,x   ; tunnel and cube: y2 > LOWS * 128 first
        cmp     y2
        bcs     @f
        lda     cb
@cube:  bit     #8              ; y < cube_height * 128
        bne     @h120
        lda     py
        cmp     #100 * 128
        rts                     ; (carry clear: below it, inside)
@h120:  lda     py
        cmp     #120 * 128
        rts
@tun:   lda     a:_hzp_lows,x   ; LOWS * 128 < y2 < CEILS * 128
        cmp     y2
        bcs     @f
        lda     y2
        cmp     a:_hzp_ceils,x
        rts
@f:     sec                     ; not inside
        rts

; bits = the level's cell_bits
setbits:
        lda     a:_hzp_bits
        sta     bits
        lda     a:_hzp_bits+2
        sta     bits+2
        rts

; ---- the C entries

_hz_probe16:
        lda     ARGS,s
        cmp     a:_hzp_level
        bne     @new
        jsr     setbits
        lda     ARGS+2,s
        sta     px
        lda     ARGS+4,s
        sta     py
        lda     ARGS+6,s        ; the row
        jsr     pcore
        lda     #0
        rol     a
        RET
@new:   TAILJ   _hzp_newlevel16

_hz_probe:
        lda     ARGS,s
        cmp     a:_hzp_level
        beq     :+
        TAILJ   _hzp_newlevel
:       lda     ARGS+12,s       ; z's high word: the row
        bmi     @no             ; z < 0: no row, nothing inside
        lda     ARGS+4,s        ; x: 6272 .. 57855
        bne     @slow
        lda     ARGS+2,s
        cmp     #6272
        bcc     @slow
        cmp     #57856
        bcs     @slow
        sta     px
        lda     ARGS+8,s        ; y: -20000 .. 32767
        beq     @ypos
        inc     a
        bne     @slow
        lda     ARGS+6,s
        cmp     #$B1E0          ; -20000
        bcc     @slow
        bra     @yok
@ypos:  lda     ARGS+6,s
        bmi     @slow
@yok:   sta     py
        jsr     setbits
        lda     ARGS+12,s
        jsr     pcore
        lda     #0
        rol     a
        RET
@no:    lda     #0
        RET
@slow:  TAILJ   _level_is_inside_tile_128_ref

_hz_scan16:
        lda     ARGS,s
        cmp     a:_hzp_level
        beq     :+
        TAILJ   _hzs_newlevel
:       jsr     setbits
        lda     ARGS+2,s
        sta     mx_
        lda     ARGS+4,s
        sta     py
        lda     #1
        sta     kk
@next:  lda     mx_
        clc
        adc     ARGS+8,s        ; x + i * step
        sta     mx_
        sta     px
        lda     ARGS+6,s
        jsr     pcore
        bcc     @found
        lda     kk
        inc     a
        sta     kk
        cmp     #15
        bcc     @next
        lda     #0
        RET
@found: lda     kk
        RET

; ---- hz_move16: gameplay_move16_c (gameplay.c) in assembly
ret0:   lda     #0
        RET

_hz_move16:
        lda     ARGS+4,s
        cmp     a:_hzp_level
        beq     :+
        TAILJ   _hzm_newlevel
:       lda     ARGS,s
        sta     sps
        lda     ARGS+2,s
        sta     spd
        ; the range: x 6272..57855 and y -20000..32767 at both ends, z >= 0, 0 <= dz <= 65535
        ldy     #2
        lda     (sps),y
        bne     ret0
        lda     (sps)
        cmp     #6272
        bcc     ret0
        cmp     #57856
        bcs     ret0
        sta     mx_
        lda     (spd),y
        bne     ret0
        lda     (spd)
        cmp     #6272
        bcc     ret0
        cmp     #57856
        bcs     ret0
        sta     mtx
        ldy     #6
        lda     (sps),y
        beq     @y0p
        inc     a
        bne     ret0
        ldy     #4
        lda     (sps),y
        cmp     #$B1E0          ; -20000
        bcc     ret0
        bra     @y0
@y0p:   ldy     #4
        lda     (sps),y
        bmi     ret0
@y0:    sta     my_
        ldy     #6
        lda     (spd),y
        beq     @y1p
        inc     a
        bne     ret0
        ldy     #4
        lda     (spd),y
        cmp     #$B1E0
        bcc     ret0
        bra     @y1
@y1p:   ldy     #4
        lda     (spd),y
        bmi     ret0
@y1:    sta     mty
        ldy     #10
        lda     (sps),y
        bpl     :+
        jmp     ret0
:       sta     z0hi
        ldy     #8
        lda     (sps),y
        sta     z0lo
        lda     (spd),y
        sta     z1lo
        sec
        sbc     z0lo
        sta     tmp             ; dz's low word
        ldy     #10
        lda     (spd),y
        sbc     z0hi
        beq     :+
        jmp     ret0            ; dz < 0 or > 65535
:
        jsr     setbits
        ; each axis: its sign, |delta| / 5, (|delta| % 5) * 12
        lda     tmp
        jsr     div5
        sta     az
        stx     fz
        stz     nx
        lda     mtx
        sec
        sbc     mx_
        bcs     :+
        dec     nx              ; dest's x below
        eor     #$FFFF
        inc     a
:       jsr     div5
        sta     ax
        stx     fx
        stz     ny
        lda     mty             ; dest's y - y (signed, may overflow 16 bits: N xor V)
        sec
        sbc     my_
        bvc     @nov
        eor     #$8000          ; (the sign the true difference has)
@nov:   bpl     @yup
        dec     ny
        lda     my_
        sec
        sbc     mty
        bra     @yd
@yup:   lda     mty
        sec
        sbc     my_
@yd:    jsr     div5
        sta     ay
        stx     fy
        lda     mx_
        sta     sx0
        lda     my_
        sta     sy0
        ; interp: steps 1..5 until a probe is inside
        stz     accx
        stz     accy
        stz     accz
        lda     #2
        sta     kk
@step:  lda     accx
        clc
        adc     ax
        sta     accx
        lda     accy
        clc
        adc     ay
        sta     accy
        lda     accz
        clc
        adc     az
        sta     accz
        jsr     qpos            ; px, py, A = the row of this step's point
        jsr     pcore
        bcs     @hit
        lda     kk
        cmp     #10
        bcs     @all            ; (step 5: none inside; the position is step 5's)
        inc     a
        inc     a
        sta     kk
        bra     @step
@hit:   lda     accx            ; the position: step - 1's
        sec
        sbc     ax
        sta     accx
        lda     accy
        sec
        sbc     ay
        sta     accy
        lda     accz
        sec
        sbc     az
        sta     accz
        lda     kk
        dec     a
        dec     a
        sta     kk
        beq     @stay           ; (inside at step 1: no move)
@all:   jsr     qpos
        lda     px
        sta     mx_
        lda     py
        sta     my_
        lda     qzlo
        sta     zlo
        lda     qzhi
        sta     zhi
        bra     @zwalk
@stay:  lda     z0lo
        sta     zlo
        lda     z0hi
        sta     zhi

@zwalk: ; the z walk (move_to's, by row): while dest - z >= g and z + g's row is not inside,
        ; z goes on to that row's end or dest, in whole g
        lda     z1lo
        sec
        sbc     zlo
        sta     dd              ; (0..65535)
        lda     #$FFFF
        sta     mrow
        lda     mx_
        sta     px
        lda     my_
        sta     py
        lda     #$1000
        sta     gran
@zg:    lda     dd
        cmp     gran
        bcc     @zn             ; dest - z < g
        lda     zlo
        clc
        adc     gran
        lda     zhi
        adc     #0              ; z + g's row
        cmp     mrow
        beq     @zm
        sta     mrow
        jsr     pcore
        lda     #0
        rol     a
        sta     mans
@zm:    lda     mans
        bne     @zn             ; inside: the next g
        lda     zlo
        clc
        adc     gran
        bcs     @zc             ; z + g in the next row: as far as dest
        lda     #$FFFF          ; the row's end - z
        sec
        sbc     zlo
        cmp     dd
        bcc     @zs
@zc:    lda     dd
@zs:    sta     tmp
        lda     gran            ; whole g: & -g
        eor     #$FFFF
        inc     a
        and     tmp
        sta     tmp
        clc
        adc     zlo
        sta     zlo
        bcc     :+
        inc     zhi
:       lda     dd
        sec
        sbc     tmp
        sta     dd
        bra     @zg
@zn:    lda     gran
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     gran
        bne     @zg

        ; the x walk: 0x7D, 25, 5, 1 toward dest while not inside
        lda     mtx
        cmp     mx_
        beq     @yw
        lda     #$7D
        sta     gran
        lda     my_
        sta     py
@xg:    bit     nx
        bmi     @xdn
        lda     mtx
        sec
        sbc     mx_
        cmp     gran
        bcc     @xn
        lda     mx_
        clc
        adc     gran
        bra     @xp
@xdn:   lda     mx_
        sec
        sbc     mtx
        cmp     gran
        bcc     @xn
        lda     mx_
        sec
        sbc     gran
@xp:    sta     px
        lda     zhi
        jsr     pcore
        bcs     @xn
        lda     px
        sta     mx_
        bra     @xg
@xn:    jsr     next5
        bne     @xg

@yw:    ; the y walk, the same
        lda     mty
        cmp     my_
        beq     @done
        lda     #$7D
        sta     gran
        lda     mx_
        sta     px
@yg:    bit     ny
        bmi     @ydn
        lda     mty
        sec
        sbc     my_
        cmp     gran
        bcc     @yn
        lda     my_
        clc
        adc     gran
        bra     @yp
@ydn:   lda     my_
        sec
        sbc     mty
        cmp     gran
        bcc     @yn
        lda     my_
        sec
        sbc     gran
@yp:    sta     py
        lda     zhi
        jsr     pcore
        bcs     @yn
        lda     py
        sta     my_
        bra     @yg
@yn:    jsr     next5
        bne     @yg

@done:  ; back into the ship
        lda     mx_
        sta     (sps)
        ldy     #2
        lda     #0
        sta     (sps),y
        ldy     #4
        lda     my_
        sta     (sps),y
        ldy     #6
        lda     #0
        bit     my_
        bpl     :+
        dec     a
:       sta     (sps),y
        ldy     #8
        lda     zlo
        sta     (sps),y
        ldy     #10
        lda     zhi
        sta     (sps),y
        lda     #1
        RET

; gran: 0x7D -> 25 -> 5 -> 1 -> 0 (Z: 0)
next5:  lda     gran
        cmp     #$7D
        bne     :+
        lda     #25
        bra     @s
:       cmp     #25
        bne     :+
        lda     #5
        bra     @s
:       cmp     #5
        bne     :+
        lda     #1
        bra     @s
:       lda     #0
@s:     sta     gran
        rts

; A = m -> A = m / 5, X = (m % 5) * 12 (m = 256 hi + lo = 255 hi + (hi + lo): 51 hi plus
; (hi + lo) / 5 from hzp_div5, whose high byte is the remainder * 12)
_hzq_div5:
div5:   sta     tmp
        and     #$00FF
        sta     cb
        lda     tmp
        xba
        and     #$00FF
        asl     a
        tax
        lda     a:_hzp_mul51,x
        sta     y2
        txa
        lsr     a
        clc
        adc     cb              ; hi + lo
        asl     a
        tax
        lda     a:_hzp_div5,x
        tax
        and     #$00FF
        clc
        adc     y2
        pha
        txa
        xba
        and     #$00FF
        tax
        pla
        rts

; the interp point at step kk / 2 (accx = ax * step, ...): px, py, qzlo/qzhi and A = its row
_hzq_qpos:
qpos:   lda     fx
        clc
        adc     kk
        tax
        lda     accx
        clc
        adc     a:_hzp_fifth,x  ; qx
        bit     nx
        bmi     @xm
        clc
        adc     sx0
        bra     @xs
@xm:    eor     #$FFFF          ; x - qx
        sec
        adc     sx0
@xs:    sta     px
        lda     fy
        clc
        adc     kk
        tax
        lda     accy
        clc
        adc     a:_hzp_fifth,x
        bit     ny
        bmi     @ym
        clc
        adc     sy0
        bra     @ys
@ym:    eor     #$FFFF
        sec
        adc     sy0
@ys:    sta     py
        lda     fz
        clc
        adc     kk
        tax
        lda     accz
        clc
        adc     a:_hzp_fifth,x
        clc
        adc     z0lo
        sta     qzlo
        lda     z0hi
        adc     #0
        sta     qzhi
        rts

; void hz_shadow(uint8_t __far *page, const uint32_t *mask, int left, int top)
; renderer.c's draw_ship_shadow after its checks: the 9 rows of the 29-column mask (bit 0
; the leftmost) at (left, top), rows 24..137 and columns 0..319 only; each pixel under a
; bit remapped by dos_shadow_shade (0x3D -> 0x40, 1..0x0F -> + 0x2D, others kept).
        .export _hz_shadow
spg     = __rg+24               ; long: the page (4)
smask   = __rg+28               ; near: the mask
sleft   = __rg+30
stop    = __rg+32
srow    = __rg+34
sbits   = __rg+36
shigh   = __rg+38
scol    = __rg+40
sline   = __rg+42               ; long: the row (4)

_hz_shadow:
        lda     ARGS,s
        sta     spg
        lda     ARGS+2,s
        sta     spg+2
        sta     sline+2
        lda     ARGS+4,s
        sta     smask
        lda     ARGS+6,s
        sta     sleft
        lda     ARGS+8,s
        sta     stop
        stz     srow
@row:   lda     stop
        clc
        adc     srow            ; py
        bmi     @next
        cmp     #24
        bcc     @next
        cmp     #138
        bcs     @next
        ; the row's address: page + py * 320
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a               ; py * 64
        sta     sline
        asl     a
        asl     a               ; py * 256
        clc
        adc     sline
        clc
        adc     spg
        sta     sline
        lda     srow
        asl     a
        asl     a
        tay
        lda     (smask),y
        sta     sbits
        iny
        iny
        lda     (smask),y
        sta     shigh
        stz     scol
@col:   lsr     sbits
        bcc     @skip
        lda     sleft
        clc
        adc     scol            ; px
        cmp     #320            ; (unsigned: px < 0 too)
        bcs     @skip
        tay
        sep     #$20
        .a8
        lda     [sline],y
        cmp     #$3D
        bne     @lo
        lda     #$40
        bra     @put
@lo:    cmp     #$10
        bcs     @keep
        cmp     #0
        beq     @keep
        clc
        adc     #$2D
@put:   sta     [sline],y
@keep:  rep     #$20
        .a16
@skip:  inc     scol
        lda     scol
        cmp     #16
        bne     :+
        lda     shigh
        sta     sbits
        lda     scol
:       cmp     #29
        bcc     @col
@next:  inc     srow
        lda     srow
        cmp     #9
        bcc     @row
        RET
