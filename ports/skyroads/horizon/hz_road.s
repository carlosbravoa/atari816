; hz_road.s - one pointer row of the TREKDAT road pass (renderer.c's draw_dos_pointer_row
; with draw_dos_cell and draw_dos_type_0..5), for the Atari816: the renderer's
; FbOps.road_row. The C in renderer.c is the reference; this does the same, cell by cell
; and shape by shape, and appends the same SpanJobs. (In C it took 12 ms a frame.)
;
; unsigned hz_road_row(const uint16_t __far *ptr24, const uint16_t *current, const uint16_t *nearer,
;                      const PreparedShape __far *prepared, unsigned shape_count,
;                      SpanJob *jobs)
;   ptr24: the pointer row's 24 shape indexes (4 cells x 6), $FFFF none
;   current, nearer: the rows' 7 descriptors (byte 0 low, byte 1 high; round 2: far, the
;   road's own rows)
;   prepared: the record's shapes {spans far ptr, u16 count, u8 colour} (7 bytes each)
;   jobs: where the jobs go {shape far ptr, u8 index, u8 right} (6 bytes each)
; -> the number of jobs written (at most 96)
        .p816
        .a16
        .i16
        .smart  +
        .include "model.inc"
        .importzp __rg, __h0, __h1, __h2, __rv
        .import _DOS_SHADE_LUT_FORWARD, _DOS_SHADE_LUT_REVERSE
        .export _hz_road_row

ptrs    = __rg+0                ; long: the pointer row (4 bytes)
curp    = __rg+4                ; long: the current row (round 2: the road's own, far)
nearp   = __rg+8                ; long: the nearer row
prep    = __rg+12               ; long: the prepared shapes (4 bytes)
count   = __rg+16               ; shapes in the record
jobp    = __rg+18               ; near: the next job
job0    = __rg+20               ; near: the first job
side    = __rg+22               ; 0 left, 1 right
slot    = __rg+24
cw      = __rg+26               ; the cell's descriptor
iw      = __rg+28               ; the inward cell's
nw      = __rg+30               ; the nearer cell's
cellp   = __rg+32               ; long: the cell's 6 pointers (4 bytes)
cur     = __rg+36               ; the cursor: a shape index, $FFFF none
shd     = __rg+38               ; the emit's shade ($FFFF: the shape's own colour)
idx     = __rg+40
shp     = __rg+42               ; long: the shape (4 bytes)
basec   = __rg+46               ; the base colour (low nibble of byte 0)
ovr     = __h0                  ; high nibble of byte 0, or $3D
tmp     = __h0+2
        .segment "BSS"
gmode:  .res 2                  ; 0: jobs (hz_road_row), 1: groups (hz_road_pass), $FFFF full
gend:   .res 2                  ; (groups: where out ends)
istop:  .res 2                  ; the emit is a cell's top face (type0's first)
lvalid: .res 2                  ; this pointer row's left slot 3 drew its top face: lpos, lcol
lpos:   .res 2                  ;   its group
lcol:   .res 2                  ;   its colour
cpo:    .res 2                  ; the pointer row's entry in the centre merges (* 7)
        .segment "CODE"

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
        sta     curp+2
        lda     ARGS+8,s
        sta     nearp
        lda     ARGS+10,s
        sta     nearp+2
        lda     ARGS+12,s
        sta     prep
        lda     ARGS+14,s
        sta     prep+2
        lda     ARGS+16,s
        sta     count
        lda     ARGS+18,s
        sta     jobp
        sta     job0
        stz     gmode
        jsr     rowcells
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

; (round 2) unsigned hz_road_pass(const RoadPass *p, void *out, unsigned cap): a whole pass of
; the road, its pointer rows one after the other, each as hz_road_row does it, the shapes
; written straight as fill_runs groups (FR_GROUPS: the shape's PreparedSpan array in the
; job's colour, as hz_span_groups made them of the jobs) to out -> how many; $FFFF when
; more than cap (8 bytes each) were needed. RoadPass (renderer.h):
;   +0 prepared (far), +4 the record's pointer_shape (far), +8 the road's rows (far: 7 words
;   each), +12 shape_count, +14 r0, +16 rn: the scene's rows r0 .. r0 + rn - 1 (any other
;   row reads as zero_row), +18 zero_row (far), +22 n, +24 n x {pointer row, row}
        .export _hz_road_pass
        .import _hz_span_total
cen     = __rv                  ; long: the record's centre merges (RoadPass +56), 0: none
pp      = __h1                  ; the HzPass (near)
rp      = __h2                  ; rowptr's answer (4 bytes)
pe      = __h1+2                ; its entry * 4
_hz_road_pass:
        lda     ARGS,s
        sta     pp
        ldy     #0
        lda     (pp),y
        sta     prep
        ldy     #2
        lda     (pp),y
        sta     prep+2
        ldy     #6
        lda     (pp),y
        sta     ptrs+2
        sta     cellp+2
        ldy     #12
        lda     (pp),y
        sta     count
        ldy     #56
        lda     (pp),y
        sta     cen
        ldy     #58
        lda     (pp),y
        sta     cen+2
        lda     ARGS+2,s
        sta     jobp
        sta     job0
        lda     ARGS+4,s        ; the end: out + cap * 8
        asl     a
        asl     a
        asl     a
        clc
        adc     job0
        sta     gend
        lda     #1
        sta     gmode
        stz     pe
@entry: lda     pe
        lsr     a
        lsr     a
        ldy     #22
        cmp     (pp),y
        bcs     @done
        ; the pointer row: pointer_shape + prow * 48
        lda     pe
        clc
        adc     #24
        tay
        lda     (pp),y          ; the pointer row
        sta     tmp
        asl     a
        asl     a
        asl     a
        sec
        sbc     tmp
        sta     a:cpo           ; (* 7: its centre merge)
        lda     tmp
        asl     a
        asl     a
        asl     a
        asl     a
        sta     tmp
        asl     a
        clc
        adc     tmp             ; * 48
        ldy     #4
        clc
        adc     (pp),y
        sta     ptrs
        ; the rows: row and row - 1
        lda     pe
        clc
        adc     #26
        tay
        lda     (pp),y
        jsr     rowptr
        lda     rp
        sta     curp
        lda     rp+2
        sta     curp+2
        lda     pe
        clc
        adc     #26
        tay
        lda     (pp),y
        dec     a
        jsr     rowptr
        lda     rp
        sta     nearp
        lda     rp+2
        sta     nearp+2
        jsr     rowcells
        lda     pe
        clc
        adc     #4
        sta     pe
        bra     @entry
@done:  lda     gmode
        bmi     @full
        lda     jobp            ; the groups written: (jobp - job0) / 8
        sec
        sbc     job0
        lsr     a
        lsr     a
        lsr     a
        RET
@full:  lda     #$FFFF
        RET

; A = a row -> rp = its descriptors (far): the road's row when it is one of the scene's
; rows (r0 .. r0 + rn - 1, renderer.c's row_raw), else zero_row
rowptr: sec
        ldy     #14
        sbc     (pp),y          ; row - r0
        bmi     @zero
        ldy     #16
        cmp     (pp),y
        bcs     @zero
        ldy     #14
        clc
        adc     (pp),y          ; the row again
        asl     a
        sta     rp
        asl     a
        asl     a
        asl     a
        sec
        sbc     rp              ; * 14
        ldy     #8
        clc
        adc     (pp),y
        sta     rp
        ldy     #10
        lda     (pp),y
        sta     rp+2
        rts
@zero:  ldy     #18
        lda     (pp),y
        sta     rp
        ldy     #20
        lda     (pp),y
        sta     rp+2
        rts

; the 8 cells of a pointer row (ptrs, curp, nearp set): their shapes as jobs or groups
rowcells:
        stz     a:lvalid
        stz     side
@side:  stz     slot
@slot:  ; column = side ? 6 - slot : slot; inward = side ? max(col - 1, 0) : min(col + 1, 6)
        ; (round 2: the cell's own descriptor first: a cell that draws nothing, a no-op kind
        ; or a type 0 without a tile, is passed over at once, as draw_dos_pointer_row does)
        lda     slot
        ldx     side
        beq     :+
        eor     #$FFFF
        clc
        adc     #7              ; 6 - slot
:       sta     tmp             ; column
        asl     a
        tay
        lda     [curp],y
        sta     cw
        xba
        and     #$000F
        cmp     #6
        bcs     @next           ; a no-op kind
        bne     @draw
        lda     cw
        and     #$000F
        beq     @next           ; type 0 without a tile
@draw:  lda     [nearp],y
        sta     nw
        lda     side
        bne     @rc
        lda     tmp
        inc     a
        cmp     #7
        bcc     @iw
        lda     #6
        bra     @iw
@rc:    lda     tmp
        beq     @iw             ; (column 0 -> inward 0)
        dec     a
@iw:    asl     a
        tay
        lda     [curp],y
        sta     iw
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
        asl     a
        tax
        jsr     (kinds,x)
@next:  inc     slot
        lda     slot
        cmp     #4
        bcs     :+
        jmp     @slot
:       inc     side
        lda     side
        cmp     #2
        bcs     :+
        jmp     @side
:       rts

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
        lda     gmode
        bne     @grp
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
@grp:   ; a group: {u24 the spans, u8 colour, u16 count, u8 stride 5, u8 the offset at 0 / 2,
        ; the width at 4} (hz_spans.s hz_span_groups)
        cpx     a:gend
        bcc     :+
        lda     #$FFFF          ; (no room: the pass is drawn the other way)
        sta     a:gmode
        rts
:       lda     a:istop         ; (round 2) the centre tile's two top halves as one group
        beq     @gw
        lda     slot
        cmp     #3
        bne     @gw
        lda     side
        bne     @rtop
        stx     a:lpos          ; the left half: its group and colour, for the right half
        lda     tmp
        sta     a:lcol
        lda     #1
        sta     a:lvalid
        bra     @gw
@rtop:  lda     a:lvalid        ; the right half: the left one's group made the merge
        beq     @gw
        stz     a:lvalid
        lda     tmp
        cmp     a:lcol
        bne     @gw
        lda     cen
        ora     cen+2
        beq     @gw
        lda     a:cpo
        clc
        adc     #4
        tay
        lda     [cen],y         ; its spans (0: no merge for this pointer row)
        beq     @gw
        ldx     a:lpos
        sec
        sbc     a:4,x           ; (the runs sent: the measurements)
        clc
        adc     a:_hz_span_total
        sta     a:_hz_span_total
        lda     [cen],y
        sta     a:4,x           ; the count
        ldy     a:cpo
        lda     [cen],y
        sta     a:0,x           ; the spans
        iny
        iny
        lda     [cen],y
        sep     #$20
        .a8
        sta     a:2,x           ; (their bank; the colour byte stays)
        rep     #$20
        .a16
        rts                     ; (the right half itself is not drawn)
@gw:    ldx     jobp
        ldy     #0
        lda     [shp],y
        sta     a:0,x
        ldy     #2
        lda     [shp],y
        and     #$00FF
        sta     a:2,x
        lda     tmp
        sep     #$20
        .a8
        sta     a:3,x
        rep     #$20
        .a16
        ldy     #4
        lda     [shp],y
        sta     a:4,x
        clc                     ; (the runs sent: the measurements)
        adc     a:_hz_span_total
        sta     a:_hz_span_total
        lda     side
        beq     :+
        lda     #$4205 - $4005
:       clc
        adc     #$4005
        sta     a:6,x
        txa
        clc
        adc     #8
        sta     jobp
        rts

; ---- draw_dos_type_0..5
type0:  lda     basec
        beq     @t0done
        AT      0
        lda     #1
        sta     a:istop
        lda     basec
        EMITA
        stz     a:istop
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
