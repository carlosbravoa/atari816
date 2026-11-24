; SPDX-License-Identifier: GPL-3.0-or-later
; hz_lit.s - the night lights' loops on the Atari816 (the C is the host's, the reference:
; engine/src/vlit.c stamp and the cells' levels, plat/vgabat.c lit_recs; -DLITCHECK
; compares lit_recs with hz_lit_recs on every present).
;
; void hz_lit_stamp(unsigned char far *m, unsigned stride, const unsigned char far *disc,
;                   unsigned w, unsigned h)
;   h rows of w bytes (rows stride apart) at m: each the most of it and disc's (19 bytes a
;   row; a byte of disc 0: nothing)
; void hz_lit_rows(unsigned char far *d, const unsigned char far *s, unsigned stride,
;                  unsigned w, unsigned h)
;   h rows of w bytes from s to d (both rows stride apart)
; int hz_lit_cells(unsigned char far *lev, const unsigned char far *lmap,
;                  const unsigned short far *rowoff, unsigned mw, unsigned mh, int a0, int b0,
;                  int c0, int c1, int r0, int r1)
;   the levels of cells c0 .. c1 - 1 of rows r0 .. r1 - 1 (of 20 x 18; vlit.c cells): 1 when
;   one changed
; unsigned hz_lit_recs(PlatRec far *o, const unsigned char far *lev, unsigned char far *sh,
;                      unsigned short far *wk, unsigned x0, unsigned y0, unsigned x1,
;                      unsigned y1, unsigned all, unsigned sheets, unsigned far *fl)
;   a night present's records (plat/vgabat.c lit_recs)
        .p816
        .a16
        .i16
        .include "model.inc"
        .importzp __rg

SUN     = 5                             ; vlit.h VL_SUN

; ---------------------------------------------------------------- hz_lit_stamp, hz_lit_rows
PM      = __rg+0
PD      = __rg+4
stride  = __rg+8
cnt     = __rg+10
wlast   = __rg+12

        FUNC    _hz_lit_stamp
        lda     ARGS,s
        sta     PM
        lda     ARGS+2,s
        sta     PM+2
        lda     ARGS+4,s
        sta     stride
        lda     ARGS+6,s
        sta     PD
        lda     ARGS+8,s
        sta     PD+2
        lda     ARGS+10,s               ; w (1-19)
        beq     @x
        dec     a
        sta     wlast
        lda     ARGS+12,s               ; h
        beq     @x
        sta     cnt
@row:   sep     #$20
        .a8
        ldy     wlast
@px:    lda     [PD],y
        beq     @n
        cmp     [PM],y
        bcc     @n
        beq     @n
        sta     [PM],y
@n:     dey
        bpl     @px
        rep     #$20
        .a16
        lda     PM
        clc
        adc     stride
        sta     PM
        bcc     :+
        inc     PM+2
:       lda     PD
        clc
        adc     #19                     ; (a disc's rows)
        sta     PD
        bcc     :+
        inc     PD+2
:       dec     cnt
        bne     @row
@x:     RET

        FUNC    _hz_lit_rows
        lda     ARGS,s
        sta     PM
        lda     ARGS+2,s
        sta     PM+2
        lda     ARGS+4,s
        sta     PD
        lda     ARGS+6,s
        sta     PD+2
        lda     ARGS+8,s
        sta     stride
        lda     ARGS+10,s               ; w
        beq     @x
        dec     a
        sta     wlast
        lda     ARGS+12,s               ; h
        beq     @x
        sta     cnt
@row:   sep     #$20
        .a8
        ldy     wlast
@px:    lda     [PD],y
        sta     [PM],y
        dey
        bpl     @px
        rep     #$20
        .a16
        lda     PM
        clc
        adc     stride
        sta     PM
        bcc     :+
        inc     PM+2
:       lda     PD
        clc
        adc     stride
        sta     PD
        bcc     :+
        inc     PD+2
:       dec     cnt
        bne     @row
@x:     RET

; ---------------------------------------------------------------- hz_lit_cells
PLV     = __rg+0
PMAP    = __rg+4
PROW    = __rg+8
mw      = __rg+12
mh      = __rg+14
ca      = __rg+16
cb      = __rg+18
chg     = __rg+20
cols    = __rg+22
rows    = __rg+24
a0      = __rg+26
idx     = __rg+28
tmp     = __rg+30
sr      = __rg+32
tr      = __rg+34
xm      = __rg+36
ym      = __rg+38
ncols   = __rg+40
rowi    = __rg+42

        FUNC    _hz_lit_cells
        lda     ARGS,s
        sta     PLV
        lda     ARGS+2,s
        sta     PLV+2
        lda     ARGS+4,s
        sta     PMAP
        lda     ARGS+6,s
        sta     PMAP+2
        lda     ARGS+8,s
        sta     PROW
        lda     ARGS+10,s
        sta     PROW+2
        lda     ARGS+12,s
        sta     mw
        lda     ARGS+14,s
        sta     mh
        stz     chg
        lda     ARGS+22,s               ; columns c0 .. c1, rows r0 .. r1
        sec
        sbc     ARGS+20,s
        beq     @none
        bmi     @none
        sta     ncols
        lda     ARGS+26,s
        sec
        sbc     ARGS+24,s
        beq     @none
        bmi     @none
        sta     rows
        lda     ARGS+20,s               ; A of column c0: a0 + 16 c0
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     ARGS+16,s
        sta     a0
        lda     ARGS+24,s               ; B of row r0: b0 + 16 r0
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     ARGS+18,s
        sta     cb
        lda     ARGS+24,s               ; the cell: r0 * 20 + c0
        asl     a
        asl     a
        sta     tmp
        asl     a
        asl     a
        clc
        adc     tmp
        clc
        adc     ARGS+20,s
        sta     rowi
        bra     @row
@none:  lda     #0
        RET
        ; a row: x = (A + B + 16) >> 5 (floor) and its remainder; y = (B - A + 16) >> 5;
        ; along the row A grows by 16: the remainders by 16 and -16, x and y step when
        ; they wrap
@row:   lda     a0
        clc
        adc     cb
        clc
        adc     #16
        tax
        and     #31
        sta     sr
        txa
        cmp     #$8000
        ror     a
        cmp     #$8000
        ror     a
        cmp     #$8000
        ror     a
        cmp     #$8000
        ror     a
        cmp     #$8000
        ror     a
        clc
        adc     #9
        sta     xm
        lda     cb
        sec
        sbc     a0
        clc
        adc     #16
        tax
        and     #31
        sta     tr
        txa
        cmp     #$8000
        ror     a
        cmp     #$8000
        ror     a
        cmp     #$8000
        ror     a
        cmp     #$8000
        ror     a
        cmp     #$8000
        ror     a
        clc
        adc     #9
        sta     ym
        lda     rowi
        sta     idx
        lda     ncols
        sta     cols
@cell:  lda     xm
        cmp     mw
        bcs     @dark                   ; (out of the map and its margin: no light)
        lda     ym
        cmp     mh
        bcs     @dark
        asl     a
        tay
        lda     [PROW],y
        clc
        adc     xm
        tay
        lda     [PMAP],y
        and     #$00FF
        cmp     #SUN
        bcs     @lit
@dark:  lda     #SUN
@lit:   eor     #$FFFF                  ; the level: 15 - the light
        sec
        adc     #15
        ldy     idx
        sep     #$20
        .a8
        cmp     [PLV],y
        beq     @same
        sta     [PLV],y
        lda     #1
        sta     chg
@same:  rep     #$20
        .a16
        inc     idx
        lda     sr                      ; the next cell
        clc
        adc     #16
        cmp     #32
        bcc     :+
        sbc     #32
        inc     xm
:       sta     sr
        lda     tr
        sec
        sbc     #16
        bpl     :+
        adc     #32
        dec     ym
:       sta     tr
        dec     cols
        beq     :+
        jmp     @cell
:       lda     rowi
        clc
        adc     #20
        sta     rowi
        lda     cb
        clc
        adc     #16
        sta     cb
        dec     rows
        beq     :+
        jmp     @row
:       lda     chg
        and     #$00FF
        RET

; ---------------------------------------------------------------- hz_lit_recs
PO      = __rg+0
PL      = __rg+4
PS      = __rg+8
PW      = __rg+12
rx0     = __rg+16
ry0     = __rg+18
rx1     = __rg+20
ry1     = __rg+22
c0      = __rg+24
c1      = __rg+26
r0      = __rg+28
r1      = __rg+30
nrun    = __rg+32                       ; runs
fl      = __rg+34
kk      = __rg+36                       ; records
cur     = __rg+38                       ; the table loaded in this call ($FFFF: none)
gl      = __rg+40                       ; the level of the records being made
t1      = __rg+42
t2      = __rg+44
sheets  = __rg+46
WK_SORT = 3 * 360 * 2                   ; (bytes) the runs' places by level
WK_JX   = 4 * 360 * 2                   ; (bytes) the level's last record at x / 4

        .segment "BSS"
lcnt:   .res    32                      ; runs of each level, then where they go
lr:     .res    2
lc:     .res    2
lcell:  .res    2
lax:    .res    2
lay:    .res    2
law:    .res    2
lah:    .res    2
llv:    .res    2
lyhl:   .res    2
lopen:  .res    2
lrin:   .res    2
ln6:    .res    2                       ; nrun * 6
li:     .res    2

        FUNC    _hz_lit_recs
        lda     ARGS,s
        sta     PO
        lda     ARGS+2,s
        sta     PO+2
        lda     ARGS+4,s
        sta     PL
        lda     ARGS+6,s
        sta     PL+2
        lda     ARGS+8,s
        sta     PS
        lda     ARGS+10,s
        sta     PS+2
        lda     ARGS+12,s
        sta     PW
        lda     ARGS+14,s
        sta     PW+2
        lda     ARGS+16,s
        sta     rx0
        lda     ARGS+18,s
        sta     ry0
        lda     ARGS+20,s
        sta     rx1
        lda     ARGS+22,s
        sta     ry1
        lda     ARGS+26,s
        sta     sheets
        lda     ARGS+24,s               ; all: every cell
        beq     @rect
        stz     c0
        stz     r0
        lda     #20
        sta     c1
        lda     #18
        sta     r1
        bra     @go
@rect:  lda     rx0
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     c0
        lda     rx1
        clc
        adc     #15
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     c1
        lda     ry0
        lsr     a
        lsr     a
        lsr     a
        sta     r0
        lda     ry1
        clc
        adc     #7
        lsr     a
        lsr     a
        lsr     a
        sta     r1
@go:    ldx     #30
@clr:   stz     lcnt,x
        dex
        dex
        bpl     @clr
        stz     nrun
        stz     ln6
        stz     fl
        ; ---- pass 1: the runs (wk: x, w, y | h << 8 | level << 12)
        lda     ARGS+24,s               ; the whole view, every cell: by rows (@full)
        beq     @gen
        lda     rx0
        ora     ry0
        bne     @gen
        lda     rx1
        cmp     #320
        bne     @gen
        lda     ry1
        cmp     #144
        bne     @gen
        jmp     @full
@gen:   lda     r0
        sta     lr
@rl:    lda     lr
        cmp     r1
        bcc     :+
        jmp     @p1done
:       asl     a
        asl     a
        sta     t1                      ; r * 4
        asl     a
        asl     a                       ; r * 16
        clc
        adc     t1
        clc
        adc     c0
        sta     lcell                   ; r * 20 + c0
        stz     lopen
        lda     lr
        asl     a
        asl     a
        asl     a
        sta     lay
        stz     lrin                    ; the row meets the rectangle?
        cmp     ry1
        bcs     :+
        clc
        adc     #8
        cmp     ry0
        beq     :+
        bcc     :+
        inc     lrin
:       lda     c0
        sta     lc
@cl:    lda     lc
        cmp     c1
        bcc     :+
        jmp     @rn
:       ldy     lcell                   ; (the cells not shown: as soon as possible)
        sep     #$20
        .a8
        lda     [PL],y
        cmp     [PS],y
        rep     #$20
        .a16
        bne     @whole1
        lda     lrin
        bne     :+
        jmp     @skip
:       lda     lc
        asl     a
        asl     a
        asl     a
        asl     a
        sta     lax
        lda     lr
        asl     a
        asl     a
        asl     a
        sta     lay
        lda     #16
        sta     law
        lda     #8
        sta     lah
        lda     [PL],y
        and     #$00FF
        sta     llv
        jmp     @same
@whole1:
        lda     lc
        asl     a
        asl     a
        asl     a
        asl     a
        sta     lax
        lda     lr
        asl     a
        asl     a
        asl     a
        sta     lay
        lda     #16
        sta     law
        lda     #8
        sta     lah
        lda     [PL],y
        and     #$00FF
        sta     llv
        lda     lax                     ; whole: outside the rectangle?
        cmp     rx0
        bcc     @out
        clc
        adc     #16
        cmp     rx1
        beq     :+
        bcs     @out
:       lda     lay
        cmp     ry0
        bcc     @out
        clc
        adc     #8
        cmp     ry1
        beq     :+
        bcs     @out
:       jmp     @take
@out:   lda     fl
        ora     #1
        sta     fl
        lda     lc
        cmp     #18
        bcs     :+
        jmp     @take
:       lda     fl
        ora     #2
        sta     fl
        jmp     @take
@skip:  stz     lopen
        jmp     @next
@same:  lda     lax                     ; in the rectangle?
        cmp     rx1
        bcs     @skip
        clc
        adc     #16
        cmp     rx0
        beq     @skip
        bcc     @skip
        lda     lay
        cmp     ry1
        bcs     @skip
        clc
        adc     #8
        cmp     ry0
        beq     @skip
        bcc     @skip
        lda     lax                     ; the part in it
        cmp     rx0
        bcs     @cx1
        lda     rx0
        sec
        sbc     lax
        sta     t1
        lda     law
        sec
        sbc     t1
        sta     law
        lda     rx0
        sta     lax
@cx1:   lda     lax
        clc
        adc     law
        cmp     rx1
        bcc     @cy0
        beq     @cy0
        lda     rx1
        sec
        sbc     lax
        sta     law
@cy0:   lda     lay
        cmp     ry0
        bcs     @cy1
        lda     ry0
        sec
        sbc     lay
        sta     t1
        lda     lah
        sec
        sbc     t1
        sta     lah
        lda     ry0
        sta     lay
@cy1:   lda     lay
        clc
        adc     lah
        cmp     ry1
        bcc     @take
        beq     @take
        lda     ry1
        sec
        sbc     lay
        sta     lah
@take:  ldy     lcell
        sep     #$20
        .a8
        lda     llv
        sta     [PS],y
        rep     #$20
        .a16
        lda     llv                     ; y | h << 8 | level << 12
        xba
        asl     a
        asl     a
        asl     a
        asl     a
        sta     t1
        lda     lah
        xba
        ora     t1
        ora     lay
        sta     lyhl
        lda     lopen                   ; joined to the run before?
        beq     @new
        lda     ln6
        sec
        sbc     #2
        tay
        lda     [PW],y                  ; its y | h | level
        cmp     lyhl
        bne     @new
        dey
        dey
        lda     [PW],y                  ; its w
        sta     t1
        dey
        dey
        lda     [PW],y                  ; its x
        clc
        adc     t1
        cmp     lax
        bne     @new
        iny
        iny
        lda     t1
        clc
        adc     law
        sta     [PW],y
        bra     @next
@new:   ldy     ln6
        lda     lax
        sta     [PW],y
        iny
        iny
        lda     law
        sta     [PW],y
        iny
        iny
        lda     lyhl
        sta     [PW],y
        tya
        clc
        adc     #2
        sta     ln6
        inc     nrun
        lda     llv
        asl     a
        tax
        inc     lcnt,x
        lda     #1
        sta     lopen
@next:  inc     lcell
        inc     lc
        jmp     @cl
@rn:    inc     lr
        jmp     @rl
        ; ---- the whole view: the levels shown, each row's runs of one level
@full:  ldy     #0
@fcp:   lda     [PL],y
        sta     [PS],y
        iny
        iny
        cpy     #360
        bcc     @fcp
        stz     lcell
        stz     lay
@frow:  ldy     lcell
        lda     [PL],y
        and     #$00FF
        sta     llv
        stz     lax                     ; the run's first column (pixels)
        lda     #16
        sta     law
        sta     lc                      ; (the next cell's x)
@fc:    iny
        lda     lc
        cmp     #320
        bcs     @fend
        lda     [PL],y
        and     #$00FF
        cmp     llv
        bne     @frun
        lda     law
        clc
        adc     #16
        sta     law
        lda     lc
        clc
        adc     #16
        sta     lc
        bra     @fc
@frun:  pha
        jsr     frun
        pla
        sta     llv
        lda     lc
        sta     lax
        clc
        adc     #16
        sta     lc
        lda     #16
        sta     law
        bra     @fc
@fend:  jsr     frun
        lda     lcell
        clc
        adc     #20
        sta     lcell
        lda     lay
        clc
        adc     #8
        sta     lay
        cmp     #144
        bcc     @frow
@p1done:
        ; ---- by level: where each level's runs go
        ldx     #0
        stz     t1
@pf:    lda     lcnt,x
        sta     t2
        lda     t1
        sta     lcnt,x
        clc
        adc     t2
        sta     t1
        inx
        inx
        cpx     #32
        bcc     @pf
        stz     li                      ; li: the run's offset (6 i)
@pl:    lda     li
        cmp     ln6
        bcs     @pdone
        clc
        adc     #4
        tay
        lda     [PW],y
        xba
        lsr     a
        lsr     a
        lsr     a
        and     #$001E                  ; level * 2
        tax
        lda     lcnt,x
        inc     lcnt,x
        asl     a
        clc
        adc     #WK_SORT
        tay
        lda     li
        sta     [PW],y
        lda     li
        clc
        adc     #6
        sta     li
        bra     @pl
@pdone:
        ; ---- pass 2: the records
        stz     kk
        lda     #$FFFF
        sta     cur
        sta     gl
        stz     li
@p2:    lda     li
        cmp     nrun
        bcc     :+
        jmp     @done
:       asl     a
        clc
        adc     #WK_SORT
        tay
        lda     [PW],y
        tay
        lda     [PW],y
        sta     lax
        iny
        iny
        lda     [PW],y
        sta     law
        iny
        iny
        lda     [PW],y
        and     #$00FF
        sta     lay
        lda     [PW],y
        xba
        and     #$000F
        sta     lah
        lda     [PW],y
        xba
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        and     #$000F
        sta     llv
        cmp     gl
        beq     @join
        sta     gl
        ldy     #WK_JX                  ; a new level: no record at any column
        ldx     #80
        lda     #$FFFF
@cj:    sta     [PW],y
        iny
        iny
        dex
        bne     @cj
        bra     @emit
@join:  lda     lax                     ; right under its level's last record at x?
        lsr     a
        clc
        adc     #WK_JX
        tay
        lda     [PW],y
        cmp     #$FFFF
        beq     @emit
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #8                      ; w
        tay
        lda     [PO],y
        cmp     law
        bne     @emit
        iny
        iny
        lda     [PO],y                  ; h
        sta     t1
        iny
        iny
        iny
        iny
        lda     [PO],y                  ; y
        clc
        adc     t1
        cmp     lay
        bne     @emit
        dey
        dey
        dey
        dey
        lda     t1
        clc
        adc     lah
        sta     [PO],y
        jmp     @n2
@emit:  lda     kk
        and     #127
        bne     :+
        lda     #$FFFF                  ; (a call's start: no table yet)
        sta     cur
:       lda     llv
        beq     @copy
        cmp     cur
        beq     @copy
@tbl:   jsr     put_table
        lda     kk
        and     #127
        beq     @tbl                    ; (it ended a call: again at the next one's start)
        lda     llv
        sta     cur
@copy:  lda     kk
        asl     a
        asl     a
        asl     a
        asl     a
        tay
        lda     sheets
        and     #$00FF
        sta     t1
        lda     llv
        beq     :+
        lda     #$4100                  ; PR_COPY | PR_REMAP
        bra     :++
:       lda     #$0100                  ; PR_COPY
:       ora     t1
        sta     [PO],y
        iny
        iny
        lda     #0
        sta     [PO],y
        iny
        iny
        lda     lax
        sta     [PO],y
        iny
        iny
        lda     lay
        sta     [PO],y
        iny
        iny
        lda     law
        sta     [PO],y
        iny
        iny
        lda     lah
        sta     [PO],y
        iny
        iny
        lda     lax
        sta     [PO],y
        iny
        iny
        lda     lay
        sta     [PO],y
        lda     lax                     ; its level's last record at x
        lsr     a
        clc
        adc     #WK_JX
        tay
        lda     kk
        sta     [PW],y
        inc     kk
@n2:    inc     li
        jmp     @p2
@done:  lda     ARGS+28,s               ; *fl
        sta     PL
        lda     ARGS+30,s
        sta     PL+2
        lda     fl
        sta     [PL]
        lda     kk
        RET

; a table record at o[kk] (level llv), kk + 1
put_table:
        lda     kk
        asl     a
        asl     a
        asl     a
        asl     a
        tay
        lda     sheets
        xba
        and     #$00FF
        ora     #$0300                  ; PR_TABLE
        sta     [PO],y
        iny
        iny
        lda     #0
        sta     [PO],y                  ; c, zero
        iny
        iny
        sta     [PO],y                  ; sx
        iny
        iny
        lda     llv
        sta     [PO],y                  ; sy: the level
        iny
        iny
        lda     #256
        sta     [PO],y                  ; w
        iny
        iny
        lda     #1
        sta     [PO],y                  ; h
        iny
        iny
        lda     #0
        sta     [PO],y                  ; x
        iny
        iny
        sta     [PO],y                  ; y
        inc     kk
        rts

; a run of the whole view (lax, law, lay, llv: 8 rows) into wk, its level counted; keeps Y
frun:   phy
        lda     llv
        xba
        asl     a
        asl     a
        asl     a
        asl     a
        ora     #$0800                  ; h 8
        ora     lay
        sta     t1
        ldy     ln6
        lda     lax
        sta     [PW],y
        iny
        iny
        lda     law
        sta     [PW],y
        iny
        iny
        lda     t1
        sta     [PW],y
        iny
        iny
        sty     ln6
        inc     nrun
        lda     llv
        asl     a
        tax
        inc     lcnt,x
        ply
        rts
