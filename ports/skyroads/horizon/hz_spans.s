; hz_spans.s - the road's spans into a page of the framebuffer (the renderer's FbOps.spans
; on Horizon; renderer.c's c_spans is the same in C).
;
; void hz_spans(const PreparedSpan __far *spans, unsigned count, unsigned right,
;               unsigned index, unsigned bank, unsigned base)
;   spans: count records of 5 bytes {u16 left, u16 right, u8 width} (renderer.h)
;   right: 0 = the left offsets, else the mirrored (right) ones
;   index: the colour; bank, base: the page (its pixel (0, 0) at bank:base)
;
; Each span is a jump into an unrolled run of 16-bit stores (`sta a:N,x`, N = 2k down to
; 0), entered k + 1 stores from its end; an odd width stores its first byte alone. DBR is
; the page's bank while it runs (the stores are absolute,X); the records are read through
; a long pointer. cc816, both code models (model.inc).
        .p816
        .a16
        .i16
        .smart  +
        .include "model.inc"
        .importzp __rg
        .export _hz_spans

sp_     = __rg+0                ; long pointer: the next record
cnt     = __rg+4                ; records left
col     = __rg+6                ; the colour in both bytes
pairs   = __rg+8                ; the span's pairs of bytes
jv      = __rg+10               ; where to enter the run
base    = __rg+12               ; the page's offset

        .export _hz_span_jobs
jobs    = __rg+16               ; long pointer: the next job
njobs   = __rg+20
shp     = __rg+22               ; long pointer: the job's PreparedShape
pbank   = __rg+26               ; the page's bank

        .segment "CODE"

_hz_spans:
        lda     ARGS+4,s        ; count
        bne     @go
        RET
@go:    sta     cnt
        lda     ARGS,s
        sta     sp_
        lda     ARGS+2,s
        sta     sp_+2
        lda     ARGS+8,s        ; index
        jsr     setcol
        lda     ARGS+12,s       ; base
        sta     base
        lda     ARGS+6,s        ; right?
        tax
        lda     ARGS+10,s       ; the page's bank -> DBR
        phb
        sep     #$20
        .a8
        pha
        plb
        rep     #$20
        .a16
        txa
        jsr     shape
        plb
        RET

; void hz_span_jobs(const SpanJob __far *jobs, unsigned n, unsigned bank, unsigned base)
;   SpanJob: {const PreparedShape __far *shape; u8 index; u8 right} (6 bytes);
;   PreparedShape: {const PreparedSpan __far *spans; u16 count} (6 bytes)
_hz_span_jobs:
        lda     ARGS+4,s
        bne     @go
        RET
@go:    sta     njobs
        lda     ARGS,s
        sta     jobs
        lda     ARGS+2,s
        sta     jobs+2
        lda     ARGS+8,s
        sta     base
        lda     ARGS+6,s
        sta     pbank
        phb
        sep     #$20
        .a8
        pha
        plb
        rep     #$20
        .a16
@job:   ldy     #0
        lda     [jobs],y        ; the shape
        sta     shp
        iny
        iny
        lda     [jobs],y
        sta     shp+2
        ldy     #0
        lda     [shp],y         ; its spans
        sta     sp_
        iny
        iny
        lda     [shp],y
        sta     sp_+2
        iny
        iny
        lda     [shp],y         ; their count
        beq     @next
        sta     cnt
        ldy     #4
        lda     [jobs],y        ; index, right
        pha
        jsr     setcol
        pla
        and     #$FF00
        jsr     shape
@next:  lda     jobs
        clc
        adc     #6
        sta     jobs
        dec     njobs
        bne     @job
        plb
        RET

;(0.30) unsigned hz_span_groups(const SpanJob __far *jobs, unsigned n, void __far *out)
; The jobs as groups for Horizon's fill_runs (FR_GROUPS: the blitter fills them, hz_video.c):
; a job is its shape's PreparedSpan array as it is, {u24 the spans, u8 colour (the job's
; index), u16 count, u8 stride 5, u8 fields: the offset at 0 (left) or 2 (right), the width
; at 4}; jobs of no spans are left out. -> the groups written (8 bytes each, at out: one bank)
        .export _hz_span_groups, _hz_span_total
        .segment "BSS"
_hz_span_total: .res 2           ; (the runs sent: the measurements)
        .segment "CODE"
_hz_span_groups:
        lda     ARGS+4,s
        sta     njobs
        stz     cnt
        lda     ARGS,s
        sta     jobs
        lda     ARGS+2,s
        sta     jobs+2
        lda     ARGS+6,s        ; out: X, its bank DBR
        tax
        lda     ARGS+8,s
        phb
        sep     #$20
        .a8
        pha
        plb
        rep     #$20
        .a16
        lda     njobs
        beq     @done
@job:   ldy     #0
        lda     [jobs],y        ; the shape
        sta     shp
        ldy     #2
        lda     [jobs],y
        sta     shp+2
        ldy     #4
        lda     [shp],y         ; its spans' count
        beq     @next
        sta     a:4,x
        clc
        adc     f:_hz_span_total
        sta     f:_hz_span_total    ; (DBR: the groups' bank here)
        ldy     #0
        lda     [shp],y         ; the spans
        sta     a:0,x
        ldy     #2
        lda     [shp],y
        and     #$00FF
        sta     col
        ldy     #4
        lda     [jobs],y        ; index | right << 8
        xba
        and     #$FF00
        ora     col
        sta     a:2,x           ; bank, colour
        lda     [jobs],y
        and     #$FF00          ; right: the offset at 2
        beq     :+
        lda     #$4205 - $4005
:       clc
        adc     #$4005          ; stride 5, fields $40 / $42
        sta     a:6,x
        txa
        clc
        adc     #8
        tax
        inc     cnt
@next:  lda     jobs
        clc
        adc     #6
        sta     jobs
        dec     njobs
        bne     @job
@done:  plb
        lda     cnt
        RET

; col = A's low byte in both bytes
setcol: and     #$00FF
        sta     col
        xba
        ora     col
        sta     col
        rts

; cnt spans from [sp_] (Y = 0 at the record), the left offsets if A = 0 else the right.
; Each span: X = its first byte, then a call into the unrolled stores at the entry for its
; width (entries[width]: even widths end with 16-bit stores at X+0, odd ones with one
; 8-bit store at X+0 after the 16-bit ones at X+1 ..).
off     = __rg+14
shape:  ldy     #0
        tax
        bne     @right

@lloop: lda     [sp_],y         ; left offset
        clc
        adc     base
        sta     off
        iny
        iny
        iny
        iny
        lda     [sp_],y         ; width (and the next record's first byte)
        iny
        and     #$00FF
        asl     a
        tax
        lda     f:entries,x     ; (DBR is the page's bank)
        sta     jv
        ldx     off
        lda     col
        jsr     run1
        dec     cnt
        bne     @lloop
        rts

@right: iny
        iny
@rloop: lda     [sp_],y         ; right offset
        clc
        adc     base
        sta     off
        iny
        iny
        lda     [sp_],y         ; width
        iny
        iny
        iny
        and     #$00FF
        asl     a
        tax
        lda     f:entries,x     ; (DBR is the page's bank)
        sta     jv
        ldx     off
        lda     col
        jsr     run1
        dec     cnt
        bne     @rloop
        rts

run1:   jmp     (jv)

; even widths: 127 stores, the k-th from the end writes bytes 2k, 2k + 1
run:
        .repeat 127, I
        sta     a:252 - I * 2,x
        .endrepeat
tend:   rts
; odd widths: 16-bit stores at 2k + 1, then the byte at 0
orun:
        .repeat 127, I
        sta     a:253 - I * 2,x
        .endrepeat
otail:  sep     #$20
        .a8
        sta     a:0,x
        rep     #$20
        .a16
        rts

entries:
        .repeat 256, W
        .if (W .mod 2) = 0
        .addr   tend - 3 * (W / 2)
        .else
        .addr   otail - 3 * (W / 2)
        .endif
        .endrepeat

; void hz_keyed(const uint8_t __far *src, unsigned sstride, uint8_t __far *dst,
;               unsigned rows, unsigned cols, unsigned add)
; rows x cols pixels: each non-zero source byte p goes to the destination as p + add (the
; ship's sprite: draw_sprite of renderer.c); the destination's rows are 320 bytes apart.
; Neither block crosses a bank.
        .export _hz_keyed
ksrc    = __rg+0
kdst    = __rg+4
kss     = __rg+8
krows   = __rg+10
kcols   = __rg+12
kadd    = __rg+14

_hz_keyed:
        lda     ARGS+10,s       ; rows
        beq     @done
        sta     krows
        lda     ARGS+12,s       ; cols
        beq     @done
        sta     kcols
        lda     ARGS,s
        sta     ksrc
        lda     ARGS+2,s
        sta     ksrc+2
        lda     ARGS+4,s
        sta     kss
        lda     ARGS+6,s
        sta     kdst
        lda     ARGS+8,s
        sta     kdst+2
        lda     ARGS+14,s
        sta     kadd
@row:   ldy     #0
        sep     #$20
        .a8
@px:    lda     [ksrc],y
        beq     @skip
        clc
        adc     kadd
        sta     [kdst],y
@skip:  iny
        cpy     kcols
        bne     @px
        rep     #$20
        .a16
        lda     ksrc
        clc
        adc     kss
        sta     ksrc
        lda     kdst
        clc
        adc     #320
        sta     kdst
        dec     krows
        bne     @row
@done:  RET

; unsigned long hz_sum(const void __far *p, unsigned nwords)
; a Fletcher-like checksum of nwords 16-bit words in one bank: a = the sum of the words,
; b = the sum of the running a's, both mod 65536 -> (b << 16) | a (the tests compare
; frames with it: tests/framesum.py)
        .export _hz_sum
sptr    = __rg+0
sa      = __rg+4
sb      = __rg+6
sn      = __rg+8
_hz_sum:
        lda     ARGS,s
        sta     sptr
        lda     ARGS+2,s
        sta     sptr+2
        stz     sa
        stz     sb
        lda     ARGS+4,s
        beq     @end
        sta     sn
        ldy     #0
@w:     lda     [sptr],y
        clc
        adc     sa
        sta     sa
        clc
        adc     sb
        sta     sb
        iny
        iny
        dec     sn
        bne     @w
@end:   lda     sa
        ldx     sb
        RET
