; hz_probe.s - the collision probe (level.c's inside_tile16: is_inside_tile_128 for the
; positions the game has) for the Atari816: the simulation's hot spot. level.c's C is the
; reference (and srtool probecheck checks it against the 32-bit form).
;
; bool hz_inside_tile(const LevelRow __far *row, unsigned x, int y)
;   row: the level's row at z (7 LevelCells of 12 bytes: +5 has_tunnel, +6 has_tile,
;   +8 has_cube_height, +9 cube_height); x 6272..57855; y -20000..32767 -> A = 0 / 1
        .p816
        .a16
        .i16
        .smart  +
        .include "model.inc"
        .importzp __rg
        .import _level_div46, _TUNNEL_LOWS, _TUNNEL_CEILS
        .export _hz_inside_tile

row     = __rg+0                ; long (4)
px      = __rg+4
py      = __rg+6
cl      = __rg+8                ; long: a cell (4)
emp     = __rg+12               ; that cell is empty (no cell)
dist    = __rg+14
far     = __rg+16
tmp     = __rg+18
lt      = __rg+20               ; the left cell's "something" bits
cy2     = __rg+22

        .segment "CODE"

_hz_inside_tile:
        lda     ARGS,s
        sta     row
        lda     ARGS+2,s
        sta     row+2
        sta     cl+2
        lda     ARGS+4,s
        sta     px
        lda     ARGS+6,s
        sta     py
        ; left and right: empty both -> 0
        lda     px
        sec
        sbc     #1792
        jsr     cell
        jsr     something
        sta     lt
        lda     px
        clc
        adc     #1792
        jsr     cell
        jsr     something
        ora     lt
        bne     @hit
        jmp     no
@hit:   ; 0x1E80 < y < 0x2800 -> 1 (signed)
        lda     py
        sec
        sbc     #$2800
        bvc     :+
        eor     #$8000
:       bpl     @n1
        lda     py
        sec
        sbc     #$1E81
        bvc     :+
        eor     #$8000
:       bmi     @n1
        jmp     yes
@n1:    ; y < 0x2180 -> 0
        lda     py
        sec
        sbc     #$2180
        bvc     :+
        eor     #$8000
:       bpl     @n2
        jmp     no
@n2:    ; v = x - 6272; rem = v - div46[v >> 7] * 5888
        lda     px
        sec
        sbc     #6272
        sta     tmp
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        tax
        lda     a:_level_div46,x
        and     #$00FF
        asl     a
        tax
        lda     tmp
        sec
        sbc     mul5888,x
        ; far side: rem > 2944
        cmp     #2945
        bcc     @near
        sbc     #2944-128       ; 128 + rem - 2944 (carry set)
        sta     dist
        lda     #1
        sta     far
        bra     @c
@near:  sta     tmp
        lda     #2944
        sec
        sbc     tmp
        sta     dist
        stz     far
@c:     lda     px
        jsr     cell
        lda     dist
        jsr     tiley
        bne     yes
        lda     far
        beq     @l
        lda     px
        clc
        adc     #5888
        bra     @a
@l:     lda     px
        sec
        sbc     #5888
@a:     jsr     cell
        lda     #6016
        sec
        sbc     dist
        jsr     tiley
        bne     yes
no:     lda     #0
        RET
yes:    lda     #1
        RET

mul5888:
        .repeat 12, I
        .word   I * 5888
        .endrepeat

; A = x -> cl = &row->c[col], emp = 0; or emp = 1 (LevelCell::empty())
cell:   sec
        sbc     #12160
        bcc     @e              ; x < 95 * 128
        cmp     #41217
        bcs     @e              ; past 322 * 128
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        tax
        lda     a:_level_div46,x
        and     #$00FF
        cmp     #7
        bcs     @e
        asl     a
        asl     a
        sta     tmp             ; col * 4
        asl     a
        clc
        adc     tmp             ; col * 12
        clc
        adc     row
        sta     cl
        stz     emp
        rts
@e:     lda     #1
        sta     emp
        rts

; A = non-zero when the cell is not empty (has_tunnel, has_tile or has_cube_height)
something:
        lda     emp
        beq     @c
        lda     #0
        rts
@c:     ldy     #8
        lda     [cl],y          ; has_cube_height (and cube_height's low byte)
        and     #$00FF
        sta     tmp
        ldy     #5
        lda     [cl],y          ; has_tunnel | has_tile << 8
        ora     tmp
        rts

; is_inside_tile_y_128(y, distance = A, the cell cl / emp) -> A = 0 / 1 (Z from it)
tiley:  clc
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
        tax
        lda     emp
        bne     @f              ; (an empty cell: neither tunnel nor cube)
        lda     py
        sec
        sbc     #68 * 128
        sta     cy2
        ldy     #5
        lda     [cl],y
        and     #$00FF
        sta     tmp             ; has_tunnel
        ldy     #8
        lda     [cl],y
        and     #$00FF
        beq     @nocube
        ; a cube: (tunnel: y2 > LOWS * 128) && y < cube_height * 128
        lda     tmp
        beq     @cube
        jsr     lowt
        bcc     @f
@cube:  ldy     #9
        lda     [cl],y          ; cube_height (100 or 120)
        xba
        and     #$FF00
        lsr     a               ; * 128
        sta     tmp
        lda     py
        sec
        sbc     tmp
        bvc     :+
        eor     #$8000
:       bpl     @f
        bra     @t
@nocube: lda    tmp
        beq     @f              ; neither
        jsr     lowt            ; y2 > LOWS * 128
        bcc     @f
        lda     a:_TUNNEL_CEILS,x
        and     #$00FF
        xba
        lsr     a
        sta     tmp
        lda     cy2             ; y2 < CEILS * 128
        sec
        sbc     tmp
        bvc     :+
        eor     #$8000
:       bpl     @f
@t:     lda     #1
        rts
@f:     lda     #0
        rts

; carry set when y2 > TUNNEL_LOWS[X] * 128 (signed)
lowt:   lda     a:_TUNNEL_LOWS,x
        and     #$00FF
        xba
        lsr     a
        sta     tmp
        lda     tmp
        sec
        sbc     cy2             ; LOWS*128 - y2 < 0 <=> y2 > LOWS*128
        bvc     :+
        eor     #$8000
:       bmi     @y
        clc
        rts
@y:     sec
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
