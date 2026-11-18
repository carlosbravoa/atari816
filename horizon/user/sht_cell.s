; sht_cell.s - Sheet: cell storage (part of sheet.s).
;
; A cell index ci = column * 1024 + row (column 0-25 = A-Z, row 0-998 = 1-999).
; The index: two banks of their own.
;   IXL  entry ci at offset 2 ci: the offset of the cell's record (16 bits)
;   IXB  entry ci at offset ci:   the bank of the record (0 = an empty cell)
; Records live in a heap of up to MAXHB banks, filled from the bottom; a record that no
; longer fits its block moves to a new one and the old one becomes garbage. When the heap
; is full, the live records are copied into fresh banks in index order (compaction) and the
; old banks are freed. A record (never crossing a bank):
;   +0  u16 its block size        +2  u8 type (T_NUM, T_TEXT, T_FORM)
;   +3  u8  formula result: 0 a number, 1 an error (the code in the value's low byte)
;   +4  u16 recalculation epoch   +6  u8 flags (RF_ACTIVE on the work stack, RF_CYCLE)
;   +8  8 bytes: the number (T_NUM) or the formula's result
;   +16 u16 text length tl        +18 u16 code length cl
;   +20 u16 the epoch in which its value last changed (or it was typed: the next one)
;   +22 the text (T_TEXT: the text; T_FORM: the formula as typed, "=" first)
;   +22 + tl the formula's code (sht_fx.s)
; colcnt counts the cells of each column (empty columns are skipped by the scans).
NCOL    = 26
NROW    = 999
CPC     = 1024
.ifndef MAXHB
MAXHB   = 16
.endif
T_NUM   = 1
T_TEXT  = 2
T_FORM  = 3
R_CAP   = 0
R_TYPE  = 2
R_VT    = 3
R_EPO   = 4
R_FL    = 6
R_VAL   = 8
R_TLEN  = 16
R_CLEN  = 18
R_CHG   = 20
R_TEXT  = 22
RF_ACTIVE = 1                           ; on the recalculation's stack
RF_CYCLE = 2                            ; it found a cycle
RF_DEP  = 4                             ; something it uses changed in this pass

        .segment "CODE"

; the index banks and an empty heap -> C set: no memory
cell_init:
        sys     SYS_BALLOC
        bcs     @out
        sta     z:ixl+2
        stz     z:ixl
        sys     SYS_BALLOC
        bcs     @out
        sta     z:ixb+2
        stz     z:ixb
        stz     hbn
        jsr     cell_wipe
        clc
@out:   rts

; every cell gone, the heap's banks freed (a new sheet)
cell_wipe:
        ldy     #0                      ; IXB: 26 K
        lda     #0
:       sta     [ixb],y
        iny
        iny
        cpy     #NCOL * CPC
        bcc     :-
:       ldx     hbn
        beq     :+
        dex
        stx     hbn
        txa
        asl     a
        tax
        lda     hb,x
        sys     SYS_BFREE
        bra     :-
:       stz     hbn
        stz     hoff
        stz     garb
        stz     garb+2
        stz     maxrow
        ldx     #NCOL * 2
:       stz     colcnt,x
        dex
        dex
        bpl     :-
        lda     #1
        sta     fullcalc
        rts

; A = ci -> C clear: gp = the record; C set: empty. Keeps X.
cell_get:
        tay
        lda     [ixb],y
        and     #$00FF
        beq     @no
        sta     z:gp+2
        tya
        asl     a
        tay
        lda     [ixl],y
        sta     z:gp
        clc
        rts
@no:    sec
        rts

; A = ci: the cell emptied
cell_clear:
        sta     c_ci
        jsr     cell_get
        bcs     @out
        ldy     #R_CAP                  ; its block is garbage now
        lda     [gp],y
        clc
        adc     garb
        sta     garb
        bcc     :+
        inc     garb+2
:       ldy     c_ci
        sep     #$20
        .a8
        lda     #0
        sta     [ixb],y
        rep     #$20
        .a16
        lda     #1                      ; (formulas using it: computed again)
        sta     fullcalc
        jsr     c_col
        dec     colcnt,x
@out:   rts

; c_ci's column * 2 -> X
c_col:  lda     c_ci
        xba
        lsr     a
        and     #$003F * 2
        tax
        rts

; colcnt counted again (after columns moved)
cnt_rebuild:
        ldx     #NCOL * 2
:       stz     colcnt,x
        dex
        dex
        bpl     :-
        stz     c_ci
@l:     lda     c_ci
        tay
        lda     [ixb],y
        and     #$00FF
        beq     :+
        jsr     c_col
        inc     colcnt,x
:       inc     c_ci
        lda     c_ci
        cmp     #NCOL * CPC
        bcc     @l
        rts

; set cell c_ci: type c_type, the value na (T_NUM), the text tbuf (c_tlen bytes, T_TEXT and
; T_FORM), the code cbuf (c_clen bytes, T_FORM) -> C set: out of memory (the cell unchanged)
cell_put:
        lda     #R_TEXT + 1             ; the size needed (even)
        clc
        adc     c_tlen
        clc
        adc     c_clen
        and     #$FFFE
        sta     c_need
        lda     c_ci
        jsr     cell_get
        bcs     @new
        ldy     #R_CAP                  ; the old block, if it is large enough
        lda     [gp],y
        cmp     c_need
        bcc     @move
        lda     z:gp
        sta     z:hp
        lda     z:gp+2
        sta     z:hp+2
        bra     @fill
@move:  pha                             ; (garbage once the new one is there)
        jsr     halloc
        pla
        jcs     @out
        clc
        adc     garb
        sta     garb
        bcc     @blk
        inc     garb+2
        bra     @blk
@new:   jsr     halloc
        jcs     @out
        jsr     c_col
        inc     colcnt,x
@blk:   lda     c_need
        sta     [hp]
@fill:  ldy     #R_TYPE
        lda     c_type
        and     #$00FF                  ; type, result 0
        sta     [hp],y
        ldy     #R_EPO
        lda     #0
        sta     [hp],y
        ldy     #R_FL
        sta     [hp],y
        lda     c_type                  ; (a formula's value: 0 until computed)
        cmp     #T_NUM
        beq     :+
        jsr     n_zero
:       ldy     #R_VAL
        lda     z:na
        sta     [hp],y
        iny
        iny
        lda     z:na+2
        sta     [hp],y
        iny
        iny
        lda     z:na+4
        sta     [hp],y
        iny
        iny
        lda     z:na+6
        sta     [hp],y
        ldy     #R_TLEN
        lda     c_tlen
        sta     [hp],y
        ldy     #R_CLEN
        lda     c_clen
        sta     [hp],y
        ldy     #R_CHG                  ; changed: in the next recalculation
        lda     epoch
        inc     a
        sta     [hp],y
        ldx     #0                      ; the text
        ldy     #R_TEXT
        sep     #$20
        .a8
:       cpx     c_tlen
        bcs     :+
        lda     tbuf,x
        sta     [hp],y
        inx
        iny
        bra     :-
:       ldx     #0                      ; the code
:       cpx     c_clen
        bcs     :+
        lda     cbuf,x
        sta     [hp],y
        inx
        iny
        bra     :-
:       rep     #$20
        .a16
        lda     c_ci                    ; into the index
        tay
        lda     z:hp+2
        sep     #$20
        .a8
        sta     [ixb],y
        rep     #$20
        .a16
        tya
        asl     a
        tay
        lda     z:hp
        sta     [ixl],y
        lda     c_ci                    ; the rows in use
        and     #CPC - 1
        inc     a
        cmp     maxrow
        bcc     :+
        sta     maxrow
:       clc
@out:   rts

; a block of c_need bytes -> hp; C set: out of memory
halloc: stz     hretry
@try:   lda     hbn
        beq     @bank
        lda     hoff
        clc
        adc     c_need
        bcs     @bank                   ; (past the bank's end)
        lda     hbn
        dec     a
        asl     a
        tax
        lda     hb,x
        sta     z:hp+2
        lda     hoff
        sta     z:hp
        clc
        adc     c_need
        sta     hoff
        clc
        rts
@bank:  lda     hbn                     ; the rest of this bank is garbage
        beq     :+
        lda     #0
        sec
        sbc     hoff
        clc
        adc     garb
        sta     garb
        bcc     :+
        inc     garb+2
:       lda     hbn
        cmp     #MAXHB
        bcs     @full
        sys     SYS_BALLOC
        bcs     @full
        pha
        lda     hbn
        asl     a
        tax
        pla
        sta     hb,x
        inc     hbn
        stz     hoff
        bra     @try
@full:  lda     hretry                  ; compact once, then try again
        bne     @no
        inc     hretry
        lda     garb+2                  ; worth it: at least 64 KB of garbage
        beq     @no
        jsr     compact
        bcs     @no
        bra     @try
@no:    sec
        rts

; copy the live records into fresh banks (the old ones freed) -> C set: no banks for it
compact:
        ldx     #0                      ; the old banks aside
:       cpx     #MAXHB * 2
        bcs     :+
        lda     hb,x
        sta     ohb,x
        inx
        inx
        bra     :-
:       lda     hbn
        sta     ohbn
        stz     hbn
        stz     hoff
        stz     garb
        stz     garb+2
        stz     c_ci
@l:     lda     c_ci
        jsr     cell_get
        bcs     @next
        ldy     #R_TLEN                 ; its size now
        lda     [gp],y
        ldy     #R_CLEN
        clc
        adc     [gp],y
        clc
        adc     #R_TEXT + 1
        and     #$FFFE
        sta     c_need
        jsr     @alloc
        bcs     @fail
        lda     c_need
        sta     [hp]
        ldy     #2
        sep     #$20
        .a8
:       lda     [gp],y
        sta     [hp],y
        iny
        cpy     c_need
        bcc     :-
        rep     #$20
        .a16
        ldy     c_ci
        lda     z:hp+2
        sep     #$20
        .a8
        sta     [ixb],y
        rep     #$20
        .a16
        tya
        asl     a
        tay
        lda     z:hp
        sta     [ixl],y
@next:  inc     c_ci                    ; the next cell (rows 0 .. NROW - 1 of each column)
        lda     c_ci
        and     #CPC - 1
        cmp     #NROW
        bcc     @l
        lda     c_ci
        clc
        adc     #CPC - NROW
        sta     c_ci
        cmp     #NCOL * CPC
        bcc     @l
:       ldx     ohbn                    ; free the old banks
        beq     :+
        dex
        stx     ohbn
        txa
        asl     a
        tax
        lda     ohb,x
        sys     SYS_BFREE
        bra     :-
:       clc
        rts
@fail:  ; (no bank: the records copied so far are in new banks, the rest in old ones;
        ; keep both sets, as the heap: nothing is lost, the space is not regained)
        ldx     #0
:       cpx     ohbn
        bcs     :+
        txa
        asl     a
        tay
        lda     ohb,y
        pha
        lda     hbn
        asl     a
        tay
        pla
        sta     hb,y                    ; (hbn + ohbn <= MAXHB always: see @alloc)
        inc     hbn
        inx
        bra     :-
:       lda     #$FFFF                  ; the last one is full: no more from it
        sta     hoff
        sec
        rts
; (compaction's own allocation: fresh banks only, leaving room to keep the old ones)
@alloc: lda     hbn
        beq     @ab
        lda     hoff
        clc
        adc     c_need
        bcs     @ab
        lda     hbn
        dec     a
        asl     a
        tax
        lda     hb,x
        sta     z:hp+2
        lda     hoff
        sta     z:hp
        clc
        adc     c_need
        sta     hoff
        clc
        rts
@ab:    lda     hbn
        clc
        adc     ohbn
        cmp     #MAXHB
        bcs     @af
        sys     SYS_BALLOC
        bcs     @af
        pha
        lda     hbn
        asl     a
        tax
        pla
        sta     hb,x
        inc     hbn
        stz     hoff
        bra     @alloc
@af:    sec
        rts

; ---------------------------------------------------------------- moving rows and columns
; insert an empty row before row A (every column; what was in row 998 is lost)
row_ins:
        sta     c_r
        stz     c_c
@col:   lda     c_c                     ; drop row NROW-1 of this column
        xba
        asl     a
        asl     a
        ora     #NROW - 1
        jsr     cell_clear
        lda     c_c                     ; entries r .. 997 -> r + 1 .. 998, from the end
        xba
        asl     a
        asl     a
        ora     #NROW - 2
        sta     c_ci
@mv:    lda     c_ci
        and     #CPC - 1
        cmp     c_r
        bcc     @e
        lda     c_ci
        jsr     ix_copy1                ; entry ci -> ci + 1
        lda     c_ci
        and     #CPC - 1
        beq     @e
        dec     c_ci
        bra     @mv
@e:     lda     c_c                     ; row r empty
        xba
        asl     a
        asl     a
        ora     c_r
        jsr     ix_zero
        inc     c_c
        lda     c_c
        cmp     #NCOL
        bcc     @col
        lda     maxrow
        cmp     #NROW
        bcs     :+
        inc     maxrow
:       rts

; delete row A (its cells freed; the rows below move up)
row_del:
        sta     c_r
        stz     c_c
@col:   lda     c_c
        xba
        asl     a
        asl     a
        ora     c_r
        sta     c_ci
        jsr     cell_clear
@mv:    lda     c_ci                    ; entries r + 1 .. 998 -> r .. 997
        and     #CPC - 1
        cmp     #NROW - 1
        bcs     @e
        lda     c_ci
        inc     a
        jsr     ix_copym1               ; entry ci + 1 -> ci
        inc     c_ci
        bra     @mv
@e:     lda     c_ci                    ; row 998 empty
        jsr     ix_zero
        inc     c_c
        lda     c_c
        cmp     #NCOL
        bcc     @col
        rts

; insert an empty column before column A (what was in Z is lost)
col_ins:
        sta     c_c
        lda     #NCOL - 1               ; Z goes
        jsr     col_clear
        lda     #NCOL - 2
        sta     c_r                     ; (the column being moved)
@l:     lda     c_r
        bmi     @e
        cmp     c_c
        bcc     @e
        jsr     col_move1               ; column r -> r + 1
        dec     c_r
        bra     @l
@e:     lda     c_c
        jsr     col_zero
        jmp     cnt_rebuild

; delete column A
col_del:
        sta     c_c
        jsr     col_clear
        lda     c_c
        sta     c_r
@l:     lda     c_r
        cmp     #NCOL - 1
        bcs     @e
        inc     a                       ; column r + 1 -> r
        jsr     col_movel
        inc     c_r
        bra     @l
@e:     lda     #NCOL - 1
        jsr     col_zero
        jmp     cnt_rebuild

; free every cell of column A
col_clear:
        xba
        asl     a
        asl     a
        sta     c_ci
        clc
        adc     #NROW
        sta     c_end
:       lda     c_ci
        jsr     cell_clear
        inc     c_ci
        lda     c_ci
        cmp     c_end
        bcc     :-
        rts

; the index entries of column A all empty (the cells are not freed)
col_zero:
        xba
        asl     a
        asl     a
        sta     c_ci
        clc
        adc     #NROW
        sta     c_end
:       lda     c_ci
        jsr     ix_zero
        inc     c_ci
        lda     c_ci
        cmp     c_end
        bcc     :-
        rts

; column A -> A + 1 (the entries copied)
col_move1:
        xba
        asl     a
        asl     a
        sta     c_ci
        clc
        adc     #NROW
        sta     c_end
:       lda     c_ci
        jsr     ix_copyc
        inc     c_ci
        lda     c_ci
        cmp     c_end
        bcc     :-
        rts
; column A -> A - 1
col_movel:
        xba
        asl     a
        asl     a
        sta     c_ci
        clc
        adc     #NROW
        sta     c_end
:       lda     c_ci
        jsr     ix_copycl
        inc     c_ci
        lda     c_ci
        cmp     c_end
        bcc     :-
        rts

; index entry A -> A + 1 / A -> A - 1 / A -> A + CPC / A -> A - CPC
ix_copy1:
        ldx     #1
        bra     ix_cp
ix_copym1:
        ldx     #$FFFF
        bra     ix_cp
ix_copyc:
        ldx     #CPC
        bra     ix_cp
ix_copycl:
        ldx     #$10000 - CPC
ix_cp:  stx     c_d
        tay                             ; bank byte
        lda     [ixb],y
        pha
        tya
        clc
        adc     c_d
        tay
        pla
        sep     #$20
        .a8
        sta     [ixb],y
        rep     #$20
        .a16
        tya                             ; offset word
        sec
        sbc     c_d
        asl     a
        tay
        lda     [ixl],y
        pha
        tya
        clc
        adc     c_d
        clc
        adc     c_d
        tay
        pla
        sta     [ixl],y
        rts

; index entry A empty (not freed)
ix_zero:
        tay
        sep     #$20
        .a8
        lda     #0
        sta     [ixb],y
        rep     #$20
        .a16
        rts

        .segment "BSS"
hb:     .res    MAXHB * 2               ; the heap's banks
ohb:    .res    MAXHB * 2
hbn:    .res    2
ohbn:   .res    2
hoff:   .res    2                       ; the next free byte in the last bank
garb:   .res    4                       ; garbage bytes
hretry: .res    2
maxrow: .res    2                       ; rows in use: the last one + 1 (an upper bound)
colcnt: .res    NCOL * 2 + 2            ; cells per column
fullcalc: .res  2                       ; 1: the next recalculation evaluates every formula
c_ci:   .res    2
c_type: .res    2
c_tlen: .res    2
c_clen: .res    2
c_need: .res    2
c_r:    .res    2
c_c:    .res    2
c_d:    .res    2
c_end:  .res    2

        .segment "ZEROPAGE"
ixl:    .res    4
ixb:    .res    4
gp:     .res    4
hp:     .res    4

        .segment "CODE"
