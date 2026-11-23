; hz_road.s - one pointer row of the TREKDAT road pass (renderer.c's draw_dos_pointer_row
; with draw_dos_cell and draw_dos_type_0..5), for the Atari816: the renderer's
; FbOps.road_row. The C in renderer.c is the reference; this does the same, cell by cell
; and shape by shape, and appends the same SpanJobs. (In C it took 12 ms a frame.)
;
; unsigned hz_road_row(const uint16_t __far *ptr24, const uint16_t *current, const uint16_t *nearer,
;                      const PreparedShape __far *prepared, unsigned shape_count,
;                      SpanJob *jobs)
;   ptr24: the pointer row's 24 shape indexes (4 cells x 6), $FFFF none
;   current, nearer: the rows' 7 descriptors (byte 0 low, byte 1 high)
;   prepared: the record's shapes {spans far ptr, u16 count, u8 colour} (7 bytes each)
;   jobs: where the jobs go {shape far ptr, u8 index, u8 right} (6 bytes each)
; -> the number of jobs written (at most 96)
        .p816
        .a16
        .i16
        .smart  +
        .include "model.inc"
        .importzp __rg
        .import _DOS_SHADE_LUT_FORWARD, _DOS_SHADE_LUT_REVERSE
        .export _hz_road_row

ptrs    = __rg+0                ; long: the pointer row (4 bytes)
curp    = __rg+4                ; near: the current row
nearp   = __rg+6                ; near: the nearer row
prep    = __rg+8                ; long: the prepared shapes (4 bytes)
count   = __rg+12               ; shapes in the record
jobp    = __rg+14               ; near: the next job
job0    = __rg+16               ; near: the first job
side    = __rg+18               ; 0 left, 1 right
slot    = __rg+20
cw      = __rg+22               ; the cell's descriptor
iw      = __rg+24               ; the inward cell's
nw      = __rg+26               ; the nearer cell's
cellp   = __rg+28               ; long: the cell's 6 pointers (4 bytes)
cur     = __rg+32               ; the cursor: a shape index, $FFFF none
shd     = __rg+34               ; the emit's shade ($FFFF: the shape's own colour)
idx     = __rg+36
shp     = __rg+38               ; long: the shape (4 bytes)
basec   = __rg+42               ; the base colour (low nibble of byte 0)
ovr     = __rg+44               ; high nibble of byte 0, or $3D
tmp     = __rg+46

NONE    = $FFFF

        .segment "CODE"

_hz_road_row:
        lda     ARGS,s
        sta     ptrs
        lda     ARGS+2,s
        sta     ptrs+2
        sta     cellp+2
        lda     ARGS+4,s
        sta     curp
        lda     ARGS+6,s
        sta     nearp
        lda     ARGS+8,s
        sta     prep
        lda     ARGS+10,s
        sta     prep+2
        lda     ARGS+12,s
        sta     count
        lda     ARGS+14,s
        sta     jobp
        sta     job0
        stz     side
@side:  stz     slot
@slot:  ; column = side ? 6 - slot : slot; inward = side ? max(col - 1, 0) : min(col + 1, 6)
        lda     side
        bne     @rc
        lda     slot
        sta     tmp             ; column
        inc     a
        cmp     #7
        bcc     @iw
        lda     #6
        bra     @iw
@rc:    lda     #6
        sec
        sbc     slot
        sta     tmp
        beq     @iw             ; (column 0 -> inward 0)
        dec     a
@iw:    asl     a
        tay
        lda     (curp),y
        sta     iw
        lda     tmp
        asl     a
        tay
        lda     (curp),y
        sta     cw
        lda     (nearp),y
        sta     nw
        ; the cell's pointers: ptrs + slot * 12
        lda     slot
        asl     a
        asl     a
        sta     tmp
        asl     a
        clc
        adc     tmp
        clc
        adc     ptrs
        sta     cellp
        ; base colour, override colour
        lda     cw
        and     #$000F
        sta     basec
        lda     cw
        and     #$00F0
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        bne     :+
        lda     #$3D
:       sta     ovr
        ; dispatch kind
        lda     cw
        xba
        and     #$000F
        cmp     #6
        bcs     @next
        asl     a
        tax
        jsr     (kinds,x)
@next:  inc     slot
        lda     slot
        cmp     #4
        bcc     @slot
        inc     side
        lda     side
        cmp     #2
        bcc     @side
        ; the jobs written: (jobp - job0) / 6
        lda     jobp
        sec
        sbc     job0
        ldx     #0
@div:   cmp     #6
        bcc     @dd
        sbc     #6
        inx
        bra     @div
@dd:    txa
        RET

kinds:  .addr   type0, type1, type2, type3, type4, type5

; ---- the cursor
; at k: cur = cellp[k]
.macro  AT      k
        ldy     #(k) * 2
        lda     [cellp],y
        sta     cur
.endmacro
; skip: the next shape
.macro  SKIP
        jsr     skip
.endmacro
; emit with the shade in A ($FFFF: the shape's own colour)
.macro  EMITA
        jsr     emit
.endmacro
.macro  EMITC   c
        lda     #(c)
        jsr     emit
.endmacro
.macro  EMITS
        lda     #NONE
        jsr     emit
.endmacro
; the nearer / inward cell's byte 1 below n: branch to label if NOT
.macro  NEAR_LT n, label
        lda     nw
        xba
        and     #$00FF
        cmp     #(n)
        bcs     label
.endmacro
.macro  INW_LT  n, label
        lda     iw
        xba
        and     #$00FF
        cmp     #(n)
        bcs     label
.endmacro

skip:   lda     cur
        cmp     #NONE
        beq     @s
        inc     a
        cmp     count
        bcc     :+
        lda     #NONE
:       sta     cur
@s:     rts

; PrimitiveCursor::emit + renderer.c's emit()
emit:   sta     shd
        lda     cur
        cmp     #NONE
        beq     @out
        sta     idx
        inc     a
        cmp     count
        bcc     :+
        lda     #NONE
:       sta     cur
        lda     idx             ; the shape: prep + idx * 7
        asl     a
        asl     a
        asl     a
        sec
        sbc     idx
        clc
        adc     prep
        sta     shp
        lda     prep+2
        sta     shp+2
        ldy     #4
        lda     [shp],y         ; its spans in the band
        beq     @out
        lda     shd
        bpl     @lut            ; an override
        ldy     #6
        lda     [shp],y
        and     #$00FF          ; the shape's colour
@lut:   cmp     #$4A            ; (DOS_SHADE_LUT_SIZE: past it the shade is the index)
        bcs     @job
        tax
        lda     side
        bne     @rev
        lda     a:_DOS_SHADE_LUT_FORWARD,x
        bra     @lu
@rev:   lda     a:_DOS_SHADE_LUT_REVERSE,x
@lu:    and     #$00FF
@job:   sta     tmp
        ldx     jobp
        lda     shp
        sta     a:0,x
        lda     shp+2
        sta     a:2,x
        lda     side
        xba
        ora     tmp
        sta     a:4,x
        txa
        clc
        adc     #6
        sta     jobp
@out:   rts

; ---- draw_dos_type_0..5
type0:  lda     basec
        beq     @t0done
        AT      0
        lda     basec
        EMITA
        lda     iw
        and     #$000F
        bne     @t0skip
        lda     basec
        clc
        adc     #$1E
        EMITA
        bra     @t0near
@t0skip: SKIP
@t0near: lda    nw
        and     #$000F
        bne     @t0done
        lda     basec
        clc
        adc     #$0F
        EMITA
@t0done: rts

type1:  jsr     type0
        NEAR_LT 1, @t1a
        AT      1
        EMITC   $43
@t1a:   AT      4
        EMITS
        EMITS
        EMITS
        EMITS
        EMITS
        EMITS
        NEAR_LT 1, @t1b
        EMITS
        EMITS
@t1b:   rts

type2:  jsr     type0
        NEAR_LT 2, @t2a
        AT      3
        EMITS
@t2a:   AT      2
        lda     ovr
        EMITA
        INW_LT  2, @t2b
        EMITS
@t2b:   rts

type3:  jsr     type0
        NEAR_LT 2, @t3a
        AT      1
        EMITC   $41
@t3a:   AT      2
        lda     ovr
        EMITA
        INW_LT  2, @t3b
        EMITS
@t3b:   NEAR_LT 2, @t3c
        AT      3
        SKIP
        EMITS
        EMITS
@t3c:   rts

type4:  jsr     type0
        NEAR_LT 2, @t4a
        AT      3
        EMITS
@t4a:   AT      2
        SKIP
        INW_LT  2, @t4b
        EMITS
@t4b:   AT      5
        lda     ovr
        EMITA
        INW_LT  4, @t4c
        EMITS
        bra     @t4d
@t4c:   SKIP
@t4d:   NEAR_LT 4, @t4e
        EMITS
@t4e:   rts

type5:  jsr     type0
        NEAR_LT 2, @t5a
        AT      1
        EMITC   $41
@t5a:   AT      2
        SKIP
        INW_LT  2, @t5b
        EMITS
@t5b:   NEAR_LT 2, @t5c
        AT      3
        SKIP
        EMITS
        EMITS
@t5c:   AT      5
        lda     ovr
        EMITA
        INW_LT  4, @t5d
        EMITS
        bra     @t5e
@t5d:   SKIP
@t5e:   NEAR_LT 4, @t5f
        EMITS
@t5f:   rts
