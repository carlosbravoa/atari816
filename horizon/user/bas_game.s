; bas_game.s - (2.0) the games statements: pictures (SHAPE, GET, PUT, COPY), sprites
; (SPRITE, HIT), full screen (SCREEN 1 / 2, SCROLL, PANEL, RASTER), the draw list, VSYNC
; and FRAME. The language is in BASIC.md, "Games".
;
; Pictures 0-63, up to 64 x 64 pixels, are kept 8 bpp with a stride of 64 (4 KB each, 16
; to a bank: pbk). SHAPE makes 16-colour ones (values 0-15) from text, GET 256-colour ones
; from the screen. A sprite shows a picture through a hardware image made from it when
; needed (the sprite bank scbk, 512 bytes a picture): 4 bpp for a 16-colour picture, and for
; a 256-colour one wider than 16 whose colours share one palette bank; else 8 bpp. 16 or 32
; wide, 16 or 32 tall.
;
; Sprites: the 16 are allocated for the graphics window at the first SPRITE. BASIC keeps
; their spr_set entries in the window bank (WIN_SPR) and hands all 16 to the kernel in one
; spr_set when one changed: at VSYNC (so the changes of a frame show together), else at
; the periodic flush. END, STOP, errors and Break free them (CONT takes them again).
;
; Full screen: the drawing area is BASIC's own framebuffer (consecutive banks, a stride of
; 512 or more, a power of two: the row table works as for the window), its w x h rows and
; 64 more for a panel, so every drawing statement works in it. The graphics window stays
; open and shows the top left of the drawing area whenever the full screen is not shown.
; There PUT, COPY, FRECT and GCLS become draw list records for Ali (WIN_DL), sent at VSYNC
; (the first record waits for the vertical blank), when the list is full, and before the CPU
; draws (dl_sync: a drawing statement of the CPU waits for Ali's list).

        .segment "CODE"
        .a16
        .i16
NPIC    = 64
PK_DEF  = 1                     ; pick: the picture is defined
PK_16   = 2                     ;   16 colours (values 0-15: SHAPE)
PK_SPR  = 4                     ;   its sprite image is made
DLMAX   = 128
FS_PANEL = 64                   ; rows of panel below the drawing area

; ---------------------------------------------------------------- extended statements
st_x:   lda     [tp]
        and     #$00FF
        inc     z:tp
        cmp     #X_N
        bcs     :+
        asl     a
        tax
        jmp     (stab2,x)
:       err     E_SYNTAX
g_bad:  err     E_ARG

; a picture number -> A
eval_pic:
        jsr     eval_u16
        cmp     #NPIC
        bcs     g_bad
        rts
; ... that is defined -> A, X = A * 2
eval_dpic:
        jsr     eval_pic
        asl     a
        tax
        lda     pick,x
        lsr     a
        bcc     :+
        txa
        lsr     a
        rts
:       err     E_NOPIC

; z:cp = the pixels of picture A (its bank taken when first needed)
pic_addr:
        pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        asl     a
        tax
        lda     pbk,x
        bne     :+
        sys     SYS_BALLOC
        bcc     @got
        pla
        err     E_MEM
@got:   sta     pbk,x
:       sta     z:cp+2
        pla
        and     #$000F
        xba
        asl     a
        asl     a
        asl     a
        asl     a
        sta     z:cp
        rts

; picture A emptied (z:cp its pixels)
pic_clear:
        pha
        jsr     pic_addr
        pla
        asl     a
        tax
        stz     picw,x
        stz     pich,x
        stz     pick,x
        ldy     #4096 - 2
        lda     #0
:       sta     [cp],y
        dey
        dey
        bpl     :-
        rts

; picture A changed: its sprite image is made again, and the sprites showing it follow
pic_changed:
        sta     pc_p
        asl     a
        tax
        lda     pick,x
        and     #$FFFF ^ PK_SPR
        sta     pick,x
        ldy     #0
@l:     tya
        asl     a
        tax
        lda     spic,x
        cmp     pc_p
        bne     @n
        tya
        jsr     sp_off
        tax
        lda     f:WIN_SPR,x
        and     #SPR_EN << 8
        beq     @n
        phy
        tya
        jsr     spr_entry
        ply
@n:     iny
        cpy     #16
        bcc     @l
        rts

; ---------------------------------------------------------------- SHAPE p, row, a$ ...
; text art: each character a pixel ('.' or ' ' or '0' clear, '1'-'9' and 'A'-'F' the
; colours 1-15); row 0 starts a new picture
st_shape:
        jsr     eval_pic
        sta     sh_p
        lda     #','
        jsr     expect
        jsr     eval_u16
        cmp     #64
        jcs     g_bad
        sta     sh_r
        lda     sh_p
        asl     a
        tax
        lda     pick,x
        and     #PK_DEF | PK_16
        cmp     #PK_DEF | PK_16
        bne     :+
        lda     sh_r
        bne     @row
:       lda     sh_p                    ; a new 16-colour picture
        jsr     pic_clear
        lda     sh_p
        asl     a
        tax
        lda     #PK_DEF | PK_16
        sta     pick,x
@row:   lda     #','
        jsr     expect
        jsr     eval_str
        lda     sh_r
        cmp     #64
        jcs     g_bad
        lda     flen
        cmp     #65
        jcs     g_bad
        lda     flo
        sta     z:bp
        lda     fhi
        sta     z:bp+2
        lda     sh_p
        jsr     pic_addr
        lda     sh_r                    ; the row: + row * 64
        xba
        lsr     a
        lsr     a
        clc
        adc     z:cp
        sta     z:cp
        ldy     #0
@ch:    cpy     flen
        bcs     @done
        lda     [bp],y
        and     #$00FF
        cmp     #'.'
        beq     @zero
        cmp     #' '
        beq     @zero
        jsr     tk_isdigit
        bcc     :+
        sbc     #'0'
        bra     @put
:       and     #$00DF
        cmp     #'A'
        bcc     @bad
        cmp     #'F' + 1
        bcs     @bad
        sbc     #'A' - 10 - 1
        bra     @put
@zero:  lda     #0
@put:   a8
        sta     [cp],y
        a16
        iny
        bra     @ch
@bad:   err     E_ARG
@done:  lda     sh_p                    ; the size: the longest row, the last row
        asl     a
        tax
        lda     flen
        cmp     picw,x
        bcc     :+
        sta     picw,x
:       lda     sh_r
        inc     a
        sta     sh_r
        cmp     pich,x
        bcc     :+
        sta     pich,x
:       jsr     peek
        cmp     #','
        jeq     @row
        lda     sh_p
        jsr     pic_changed
        jmp     stmt_end

; ---------------------------------------------------------------- blocks of pixels
; the rectangle bx, by, bw, bh against the drawing area -> its columns bc0 .. bc1 and rows
; br0 .. br1 that lie inside (exclusive ends); C set: none
blk_clip:
        lda     bx
        eor     #$FFFF
        inc     a
        bpl     :+
        lda     #0
:       sta     bc0
        lda     gwid
        sec
        sbc     bx
        bmi     @none
        cmp     bw
        bcc     :+
        lda     bw
:       sta     bc1
        cmp     bc0
        bcc     @none
        beq     @none
        lda     by
        eor     #$FFFF
        inc     a
        bpl     :+
        lda     #0
:       sta     br0
        lda     ghgt
        sec
        sbc     by
        bmi     @none
        cmp     bh
        bcc     :+
        lda     bh
:       sta     br1
        cmp     br0
        bcc     @none
        beq     @none
        clc
        rts
@none:  sec
        rts

; z:gq = the drawing area at row A (by + A), column bx + bc0
blk_dst:
        clc
        adc     by
        asl     a
        tax
        lda     bx
        clc
        adc     bc0
        clc
        adc     f:WIN_ROWO,x
        sta     z:gq
        lda     f:WIN_ROWB,x
        adc     #0
        sta     z:gq+2
        rts
; z:gr = picture z:cp at row A, column bc0
blk_src:
        xba
        lsr     a
        lsr     a
        clc
        adc     z:cp
        clc
        adc     bc0
        sta     z:gr
        lda     z:cp+2
        sta     z:gr+2
        rts
; the part drawn (bx + bc0 .. bx + bc1, by + br0 .. by + br1) marked dirty
blk_dirty:
        lda     bx
        clc
        adc     bc0
        sta     z:t0
        lda     bx
        clc
        adc     bc1
        sta     z:t2
        lda     by
        clc
        adc     br0
        sta     z:t1
        lda     by
        clc
        adc     br1
        sta     z:t3
        jmp     dirty

; GET p, x, y, w, h: a 256-colour picture from the drawing area (outside it: colour 0)
st_get:
        jsr     gfx_cpu
        jsr     eval_pic
        sta     gt_p
        lda     #','
        jsr     expect
        jsr     two_args
        lda     z:t0
        sta     bx
        lda     z:t1
        sta     by
        lda     #','
        jsr     expect
        jsr     two_args
        lda     z:t0
        beq     @bad
        cmp     #65
        bcs     @bad
        sta     bw
        lda     z:t1
        beq     @bad
        cmp     #65
        bcs     @bad
        sta     bh
        lda     gt_p
        jsr     pic_clear
        lda     gt_p
        asl     a
        tax
        lda     bw
        sta     picw,x
        lda     bh
        sta     pich,x
        lda     #PK_DEF
        sta     pick,x
        jsr     blk_clip
        bcs     @done
        lda     br0
        sta     gt_r
@row:   lda     gt_r
        cmp     br1
        bcs     @done
        jsr     blk_dst
        lda     gt_r
        jsr     blk_src
        lda     bc1
        sec
        sbc     bc0
        sta     z:t0
        ldy     #0
        a8
:       lda     [gq],y
        sta     [gr],y
        iny
        cpy     z:t0
        bcc     :-
        a16
        inc     gt_r
        bra     @row
@done:  lda     gt_p
        jsr     pic_changed
        jmp     stmt_end
@bad:   err     E_ARG

; PUT p, x, y [, c]: picture p drawn at x, y (c: a colour left out, seen through)
st_put:
        jsr     gfx_need
        jsr     eval_dpic
        sta     gt_p
        lda     picw,x
        sta     bw
        lda     pich,x
        sta     bh
        lda     #','
        jsr     expect
        jsr     two_args
        lda     z:t0
        sta     bx
        lda     z:t1
        sta     by
        lda     #$FFFF
        sta     pt_key
        jsr     peek
        cmp     #','
        bne     :+
        inc     z:tp
        jsr     byte_arg
        sta     pt_key
:       jsr     blk_clip
        jcs     stmt_end
        lda     gt_p
        jsr     pic_addr
        lda     fsact                   ; (full screen shown: Ali)
        bne     @fs
        lda     br0                     ; a window: the CPU, into the shadow
        sta     gt_r
@row:   lda     gt_r
        cmp     br1
        bcs     @done
        jsr     blk_dst
        lda     gt_r
        jsr     blk_src
        lda     bc1
        sec
        sbc     bc0
        sta     z:t0
        ldy     #0
        lda     pt_key
        bpl     @key
        a8
:       lda     [gr],y
        sta     [gq],y
        iny
        cpy     z:t0
        bcc     :-
        a16
        bra     @next
@key:   a8
:       lda     [gr],y
        cmp     pt_key
        beq     :+
        sta     [gq],y
:       iny
        cpy     z:t0
        bcc     :--
        a16
@next:  inc     gt_r
        bra     @row
@done:  jsr     blk_dirty
        jmp     stmt_end
@fs:    jsr     blk_dirty               ; full screen: a record for Ali
        lda     #LS_COPY
        ldx     pt_key
        bmi     :+
        lda     #LS_KEY
:       sta     dl_rec                  ; op, flags 0
        lda     pt_key                  ; c1 0, c2 the key
        xba
        and     #$FF00
        sta     dl_rec+LR_C1
        lda     bx
        sta     dl_rec+LR_X
        lda     by
        sta     dl_rec+LR_Y
        lda     bw
        sta     dl_rec+LR_W
        lda     bh
        sta     dl_rec+LR_H
        lda     z:cp
        sta     dl_rec+LR_SRC
        lda     z:cp+2
        sta     dl_rec+LR_SRC+2
        lda     #64
        sta     dl_rec+LR_STRIDE
        stz     dl_rec+18
        jsr     dl_push
        jmp     stmt_end

; COPY x, y, w, h TO x2, y2: a rectangle of the drawing area moved (overlap-safe; what
; lies outside on either side is left out of both)
st_copy:
        jsr     gfx_need
        jsr     two_args
        lda     z:t0
        sta     cx
        lda     z:t1
        sta     cy
        lda     #','
        jsr     expect
        jsr     two_args
        lda     z:t0
        sta     bw
        lda     z:t1
        sta     bh
        lda     #TK_TO
        jsr     expect
        jsr     two_args
        lda     z:t0
        sta     bx
        lda     z:t1
        sta     by
        lda     bw
        dec     a
        bmi     @end
        lda     bh
        dec     a
        bmi     @end
        lda     fsact
        jeq     @cpu
        lda     bw                      ; full screen shown: one record, Ali's MOVE
        ldx     bh
        jsr     umul16
        cpx     #7                      ; (460,800 pixels at most)
        bcc     :+
        bne     @bad
        cmp     #$0801
        bcs     @bad
:       lda     #LS_MOVE
        sta     dl_rec
        stz     dl_rec+LR_C1
        lda     bx
        sta     dl_rec+LR_X
        lda     by
        sta     dl_rec+LR_Y
        lda     bw
        sta     dl_rec+LR_W
        lda     bh
        sta     dl_rec+LR_H
        lda     cx
        sta     dl_rec+12
        lda     cy
        sta     dl_rec+14
        stz     dl_rec+16
        stz     dl_rec+18
        jsr     dl_push
        stz     bc0
        stz     br0
        lda     bw
        sta     bc1
        lda     bh
        sta     br1
        jsr     blk_cdirty
@end:   jmp     stmt_end
@bad:   err     E_ARG
@cpu:   lda     cx                      ; the window: cut both to the area
        jsr     @lo
        lda     bx
        jsr     @lo
        lda     cy
        jsr     @to
        lda     by
        jsr     @to
        lda     bw
        dec     a
        bmi     @end
        lda     bh
        dec     a
        bmi     @end
        lda     gwid
        sec
        sbc     cx
        jsr     @wmax
        lda     gwid
        sec
        sbc     bx
        jsr     @wmax
        lda     ghgt
        sec
        sbc     cy
        jsr     @hmax
        lda     ghgt
        sec
        sbc     by
        jsr     @hmax
        lda     bw
        dec     a
        bmi     @end
        lda     bh
        dec     a
        bmi     @end
        stz     bc0
        stz     br0
        lda     bw
        sta     bc1
        lda     bh
        sta     br1
        stz     gt_r                    ; rows: from the bottom when moving down
        lda     #1
        sta     cp_dir
        lda     by
        cmp     cy
        beq     @r
        bmi     @r
        lda     bh
        dec     a
        sta     gt_r
        lda     #$FFFF
        sta     cp_dir
@r:     lda     gt_r                    ; a row
        bmi     @fin
        cmp     bh
        bcs     @fin
        clc
        adc     cy
        asl     a
        tax
        lda     cx
        clc
        adc     f:WIN_ROWO,x
        sta     z:gr
        lda     f:WIN_ROWB,x
        adc     #0
        sta     z:gr+2
        lda     gt_r
        jsr     blk_dst
        lda     by                      ; the same row, to the right: from its end
        cmp     cy
        bne     @fwd
        lda     bx
        cmp     cx
        beq     @fwd
        bmi     @fwd
        ldy     bw
        a8
:       dey
        lda     [gr],y
        sta     [gq],y
        cpy     #0
        bne     :-
        a16
        bra     @nr
@fwd:   ldy     #0
        a8
:       lda     [gr],y
        sta     [gq],y
        iny
        cpy     bw
        bcc     :-
        a16
@nr:    lda     gt_r
        clc
        adc     cp_dir
        sta     gt_r
        bra     @r
@fin:   jsr     blk_dirty
        jmp     stmt_end
; (a start below 0 moves both starts on: A = the start)
@lo:    eor     #$FFFF
        inc     a
        bmi     :+
        beq     :+
        pha
        clc
        adc     cx
        sta     cx
        lda     1,s
        clc
        adc     bx
        sta     bx
        lda     bw
        sec
        sbc     1,s
        sta     bw
        pla
:       rts
@to:    eor     #$FFFF
        inc     a
        bmi     :+
        beq     :+
        pha
        clc
        adc     cy
        sta     cy
        lda     1,s
        clc
        adc     by
        sta     by
        lda     bh
        sec
        sbc     1,s
        sta     bh
        pla
:       rts
@wmax:  bpl     :+
        lda     #0
:       cmp     bw
        bcs     :+
        sta     bw
:       rts
@hmax:  bpl     :+
        lda     #0
:       cmp     bh
        bcs     :+
        sta     bh
:       rts
; (full screen: the destination box, clipped, marked dirty)
blk_cdirty:
        jsr     blk_clip
        bcs     :+
        jmp     blk_dirty
:       rts

; ---------------------------------------------------------------- the draw list
; dl_rec (20 bytes) -> the list; a full list, or one over 460,800 pixels, is sent first
dl_push:
        lda     dl_rec+LR_W
        ldx     dl_rec+LR_H
        jsr     umul16
        sta     dl_pa
        stx     dl_pa+2
        clc
        adc     dl_px
        tay
        lda     dl_pa+2
        adc     dl_px+2
        cmp     #7                      ; 460,800 = $70800
        bcc     :+
        bne     @send
        cpy     #$0801
        bcc     :+
@send:  lda     #0
        jsr     dl_submit
:       lda     dl_n
        cmp     #DLMAX
        bcc     :+
        lda     #0
        jsr     dl_submit
:       ldx     dl_off
        ldy     #0
:       lda     dl_rec,y
        sta     f:WIN_DL,x
        inx
        inx
        iny
        iny
        cpy     #20
        bcc     :-
        stx     dl_off
        inc     dl_n
        lda     dl_px
        clc
        adc     dl_pa
        sta     dl_px
        lda     dl_px+2
        adc     dl_pa+2
        sta     dl_px+2
        rts

; the list to Ali (A = the first record's flags: LS_VBL at VSYNC); it runs on its own
dl_submit:
        ldx     dl_n
        beq     @out
        a8
        ora     f:WIN_DL+LR_FLAGS
        sta     f:WIN_DL+LR_FLAGS
        a16
        lda     dl_n
        xba
        ora     gwin
        ldx     #WIN_DL
        ldy     #0
        sys     SYS_DRAWLIST
        php
        stz     dl_n
        stz     dl_off
        stz     dl_px
        stz     dl_px+2
        plp
        bcs     @err
        lda     #1
        sta     dl_run
        lda     gfocus                  ; (the window shows the picture when the full
        bne     @out                    ; screen is not shown)
        jsr     dirty_all
@out:   rts
@err:   err     E_ARG

; Ali's list sent and done (before the CPU draws or reads)
dl_sync:
        lda     dl_n
        beq     :+
        lda     #0
        jsr     dl_submit
:       lda     dl_run
        beq     :+
        stz     dl_run
        lda     #0
        sys     SYS_LISTWAIT
:       rts
; the records not sent are dropped, a running list waited for
dl_drop:
        stz     dl_n
        stz     dl_off
        stz     dl_px
        stz     dl_px+2
        bra     :--

; full screen: the box t0, t1, t2, t3 (clipped, exclusive) filled in gc_col by Ali, in
; bands of 200 rows (keeps t0-t3)
fs_fill:
        jsr     dirty
        lda     z:t1
        sta     ff_y
@band:  lda     ff_y
        cmp     z:t3
        bcs     @out
        lda     z:t3
        sec
        sbc     ff_y
        cmp     #200
        bcc     :+
        lda     #200
:       sta     dl_rec+LR_H
        lda     #LS_FILL
        sta     dl_rec
        lda     gc_col
        and     #$00FF
        sta     dl_rec+LR_C1
        lda     z:t0
        sta     dl_rec+LR_X
        lda     ff_y
        sta     dl_rec+LR_Y
        lda     z:t2
        sec
        sbc     z:t0
        sta     dl_rec+LR_W
        stz     dl_rec+12
        stz     dl_rec+14
        stz     dl_rec+16
        stz     dl_rec+18
        jsr     dl_push
        lda     ff_y
        clc
        adc     dl_rec+LR_H
        sta     ff_y
        bra     @band
@out:   rts

; ---------------------------------------------------------------- sprites
; A (0-15) * 10: its entry's offset in WIN_SPR
sp_off: asl     a
        sta     sp_t
        asl     a
        asl     a
        clc
        adc     sp_t
        rts

; SPRITE n, x, y [, p [, f]], SPRITE n OFF, SPRITE OFF
st_sprite:
        jsr     peek
        cmp     #TK_OFF
        bne     @one
        inc     z:tp                    ; all hidden
        ldx     #0
:       lda     f:WIN_SPR,x
        and     #$FFFF ^ (SPR_EN << 8)
        sta     f:WIN_SPR,x
        txa
        clc
        adc     #10
        tax
        cpx     #160
        bcc     :-
        bra     @dirty
@one:   jsr     eval_u16
        cmp     #16
        jcs     g_bad
        sta     sp_n
        jsr     sp_off
        sta     sp_o
        jsr     peek
        cmp     #TK_OFF
        bne     @at
        inc     z:tp
        ldx     sp_o
        lda     f:WIN_SPR,x
        and     #$FFFF ^ (SPR_EN << 8)
        sta     f:WIN_SPR,x
@dirty: lda     #1
        sta     sp_dirty
        jmp     stmt_end
@at:    jsr     gfx_need
        lda     sp_first
        bpl     :+
        jsr     sp_alloc
        bcc     :+
        cmp     #ENODEV
        bne     @busy
        err     E_NODEV
@busy:  err     E_INUSE
:       lda     #','
        jsr     expect
        jsr     two_args
        ldx     sp_o
        lda     z:t0
        sta     f:WIN_SPR+SE_X,x
        lda     z:t1
        sta     f:WIN_SPR+SE_Y,x
        jsr     peek
        cmp     #','
        bne     @show
        inc     z:tp
        jsr     eval_pic
        pha
        lda     sp_n
        asl     a
        tax
        pla
        sta     spic,x
        stz     sflg,x
        jsr     peek
        cmp     #','
        bne     :+
        inc     z:tp
        jsr     byte_arg
        pha
        lda     sp_n
        asl     a
        tax
        pla
        sta     sflg,x
:       lda     sp_n
        jsr     spr_entry
        bra     @dirty
@show:  lda     sp_n                    ; (its picture must be known)
        asl     a
        tax
        lda     spic,x
        cmp     #NPIC
        bcc     :+
        err     E_NOPIC
:       ldx     sp_o
        lda     f:WIN_SPR,x
        ora     #SPR_EN << 8
        sta     f:WIN_SPR,x
        jmp     @dirty

; the 16 sprites for the graphics window -> C set, A = the error (ENODEV, EAGAIN)
sp_alloc:
        lda     #16
        ldx     gwin
        sys     SYS_SPRALLOC
        bcc     :+
        rts
:       sta     sp_first
        jsr     sc_bank
        ldx     #0                      ; each entry: its sprite; an image in our memory
        ldy     #0
@l:     lda     f:WIN_SPR,x
        and     #$FF00
        ora     sp_first
        sta     z:t7
        tya
        clc
        adc     z:t7
        sta     f:WIN_SPR,x
        lda     f:WIN_SPR+SE_IMAGE+1,x
        and     #$FF00
        bne     :+
        lda     #0
        sta     f:WIN_SPR+SE_IMAGE,x
        lda     scbk
        a8
        sta     f:WIN_SPR+SE_IMAGE+2,x
        a16
:       txa
        clc
        adc     #10
        tax
        iny
        cpy     #16
        bcc     @l
        lda     #1
        sta     sp_dirty
        clc
        rts

; the sprite image bank (taken when first needed) -> A
sc_bank:
        lda     scbk
        bne     :+
        sys     SYS_BALLOC
        bcc     @got
        err     E_MEM
@got:   sta     scbk
:       rts

; sprite A's entry from its picture and flags (the image made when needed); shown
spr_entry:
        sta     se_n
        asl     a
        tax
        lda     sflg,x
        sta     se_f
        lda     spic,x
        cmp     #NPIC
        jcs     @nopic
        sta     se_p
        asl     a
        tax
        lda     pick,x
        lsr     a
        jcc     @nopic
        and     #PK_SPR >> 1
        bne     :+
        lda     se_p
        jsr     spc_build
:       lda     se_f                    ; flags: 1 HFLIP, 2 VFLIP, 4 MAG, 8 BEHIND
        and     #7
        asl     a
        sta     z:t7
        lda     se_f
        and     #8
        beq     :+
        lda     #SPR_BEHIND
        tsb     z:t7
:       lda     se_p
        asl     a
        tax
        lda     spcc,x
        and     #$00FF
        ora     z:t7
        ora     #SPR_EN
        sta     se_c
        lda     se_f                    ; the palette bank: given (f / 16), or the picture's
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        bne     :+
        lda     spcc,x
        xba
        and     #$00FF
:       sta     se_pal
        lda     se_n
        jsr     sp_off
        tax
        lda     f:WIN_SPR,x
        and     #$00FF
        sta     z:t7
        lda     se_c
        xba
        ora     z:t7
        sta     f:WIN_SPR,x
        lda     se_p                    ; the image: scbk : p * 512
        xba
        asl     a
        sta     f:WIN_SPR+SE_IMAGE,x
        a8
        lda     scbk
        sta     f:WIN_SPR+SE_IMAGE+2,x
        lda     se_pal
        sta     f:WIN_SPR+SE_PAL,x
        a16
        lda     #1
        sta     sp_dirty
        rts
@nopic: err     E_NOPIC

; the sprite image of picture A (scbk : A * 512); Bad argument if larger than 32 x 32, or
; wider than 16 with colours from more than one palette bank
spc_build:
        sta     sb_p
        jsr     sc_bank
        lda     sb_p
        asl     a
        tax
        lda     picw,x
        sta     sb_w
        lda     pich,x
        sta     sb_h
        lda     pick,x
        sta     sb_k
        stz     sb_c
        stz     sb_bk
        lda     #16
        sta     sb_hh
        sta     sb_hw
        lda     sb_h
        cmp     #33
        jcs     @bad
        cmp     #17
        bcc     :+
        lda     #SPR_TALL
        tsb     sb_c
        lda     #32
        sta     sb_hh
:       lda     sb_k
        and     #PK_16
        beq     :+
        lda     #SPR_BPP4
        tsb     sb_c
:       lda     sb_w
        cmp     #33
        bcs     @bad
        cmp     #17
        bcc     @pix
        lda     #SPR_WIDE | SPR_BPP4
        tsb     sb_c
        lda     #32
        sta     sb_hw
        lda     sb_k                    ; 256 colours, 4 bpp: one palette bank for all
        and     #PK_16
        bne     @pix
        lda     sb_p
        jsr     pic_addr
        lda     #$FFFF
        sta     sb_bk
        stz     sb_r
@br:    lda     sb_r
        cmp     sb_h
        bcs     @bdone
        ldy     #0
@bc:    cpy     sb_w
        bcs     @bnext
        lda     [cp],y
        and     #$00FF
        beq     @bn
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        ldx     sb_bk
        bmi     :+
        cmp     sb_bk
        bne     @bad
:       sta     sb_bk
@bn:    iny
        bra     @bc
@bnext: lda     z:cp
        clc
        adc     #64
        sta     z:cp
        inc     sb_r
        bra     @br
@bdone: lda     sb_bk
        bpl     @pix
        stz     sb_bk
        bra     @pix
@bad:   err     E_ARG
@pix:   lda     sb_p                    ; the image, row by row
        jsr     pic_addr
        lda     sb_p
        xba
        asl     a
        sta     z:gr
        lda     scbk
        sta     z:gr+2
        stz     sb_r
@row:   lda     sb_r
        cmp     sb_hh
        bcs     @done
        ldy     #0
        lda     sb_c
        and     #SPR_BPP4
        bne     @four
:       jsr     @px                     ; 8 bpp: 16 bytes
        a8
        sta     [gr]
        a16
        inc     z:gr
        iny
        cpy     #16
        bcc     :-
        bra     @nrow
@four:  jsr     @px                     ; 4 bpp: two pixels a byte, the left one high
        and     #$000F
        asl     a
        asl     a
        asl     a
        asl     a
        sta     sb_t
        iny
        jsr     @px
        and     #$000F
        ora     sb_t
        a8
        sta     [gr]
        a16
        inc     z:gr
        iny
        cpy     sb_hw
        bcc     @four
@nrow:  lda     z:cp
        clc
        adc     #64
        sta     z:cp
        inc     sb_r
        bra     @row
@done:  lda     sb_p
        asl     a
        tax
        lda     pick,x
        ora     #PK_SPR
        sta     pick,x
        lda     sb_bk
        xba
        ora     sb_c
        sta     spcc,x
        rts
; (the pixel at row sb_r, column Y; 0 outside the picture)
@px:    lda     sb_r
        cmp     sb_h
        bcs     :+
        cpy     sb_w
        bcs     :+
        lda     [cp],y
        and     #$00FF
        rts
:       lda     #0
        rts

; the entries to the kernel (one spr_set for all 16), when one changed
spr_flush:
        lda     sp_dirty
        beq     :+
        lda     sp_first
        bmi     :+
        stz     sp_dirty
        lda     #16
        ldx     #WIN_SPR
        ldy     #0
        sys     SYS_SPRSET
:       rts

; HIT(a): the first other sprite that touches sprite a, -1 for none; HIT(a, b): -1 when
; sprites a and b touch, else 0; HIT(a, x, y, w, h): -1 when sprite a touches that box.
; Boxes are the pictures' sizes (twice with flag 4); hidden sprites touch nothing.
f_hit:  lda     #'('
        jsr     expect
        jsr     eval_u16
        cmp     #16
        jcs     g_bad
        sta     ht_a
        jsr     peek
        cmp     #')'
        jeq     @any
        lda     #','
        jsr     expect
        jsr     eval_s16
        sta     ht_b
        jsr     peek
        cmp     #')'
        beq     @two
        lda     ht_b                    ; a box
        sta     hb_x0+8
        lda     #','
        jsr     expect
        jsr     eval_s16
        sta     hb_y0+8
        lda     #','
        jsr     expect
        jsr     eval_s16
        clc
        adc     hb_x0+8
        sta     hb_x1+8
        lda     #','
        jsr     expect
        jsr     eval_s16
        clc
        adc     hb_y0+8
        sta     hb_y1+8
        lda     #')'
        jsr     expect
        lda     ht_a
        ldx     #0
        jsr     sp_box
        bcs     @no
        jsr     hb_touch
        bcs     @no
        bra     @yes
@two:   inc     z:tp
        lda     ht_b
        cmp     #16
        jcs     g_bad
        lda     ht_a
        ldx     #0
        jsr     sp_box
        bcs     @no
        lda     ht_b
        cmp     ht_a
        beq     @no
        ldx     #8
        jsr     sp_box
        bcs     @no
        jsr     hb_touch
        bcs     @no
@yes:   lda     #$FFFF
        tax
        jmp     ret_int
@no:    lda     #0
        jmp     ret_u16
@any:   inc     z:tp
        lda     ht_a
        ldx     #0
        jsr     sp_box
        bcs     @none
        stz     ht_b
@l:     lda     ht_b
        cmp     ht_a
        beq     @n
        ldx     #8
        jsr     sp_box
        bcs     @n
        jsr     hb_touch
        bcs     @n
        lda     ht_b
        jmp     ret_u16
@n:     inc     ht_b
        lda     ht_b
        cmp     #16
        bcc     @l
@none:  lda     #$FFFF
        tax
        jmp     ret_int

; the boxes hb_*+0 and hb_*+8 overlap? -> C clear
hb_touch:
        lda     hb_x0
        sec
        sbc     hb_x1+8
        bpl     @no
        lda     hb_x0+8
        sec
        sbc     hb_x1
        bpl     @no
        lda     hb_y0
        sec
        sbc     hb_y1+8
        bpl     @no
        lda     hb_y0+8
        sec
        sbc     hb_y1
        bpl     @no
        clc
        rts
@no:    sec
        rts

; the box of sprite A -> hb_x0, hb_y0, hb_x1, hb_y1 + X (0 or 8; ends exclusive);
; C set: it is not shown
sp_box: stx     hb_i
        sta     z:t6
        asl     a
        tay
        lda     spic,y
        cmp     #NPIC
        jcs     @no
        asl     a
        tay
        lda     z:t6
        jsr     sp_off
        tax
        lda     f:WIN_SPR,x
        xba
        and     #$00FF
        sta     z:t5                    ; ctrl
        and     #SPR_EN
        beq     @no
        lda     picw,y
        sta     z:t3
        lda     pich,y
        sta     z:t4
        lda     #16                     ; the image's size (flips mirror all of it)
        sta     z:t1
        sta     z:t2
        lda     z:t5
        and     #SPR_WIDE
        beq     :+
        asl     z:t1
:       lda     z:t5
        and     #SPR_TALL
        beq     :+
        asl     z:t2
:       stz     z:t6                    ; the picture's offset in it
        stz     z:t7
        lda     z:t5
        and     #SPR_HFLIP
        beq     :+
        lda     z:t1
        sec
        sbc     z:t3
        sta     z:t6
:       lda     z:t5
        and     #SPR_VFLIP
        beq     :+
        lda     z:t2
        sec
        sbc     z:t4
        sta     z:t7
:       lda     z:t5
        and     #SPR_MAG
        beq     :+
        asl     z:t3
        asl     z:t4
        asl     z:t6
        asl     z:t7
:       lda     f:WIN_SPR+SE_X,x
        clc
        adc     z:t6
        ldy     hb_i
        sta     hb_x0,y
        clc
        adc     z:t3
        sta     hb_x1,y
        lda     f:WIN_SPR+SE_Y,x
        clc
        adc     z:t7
        sta     hb_y0,y
        clc
        adc     z:t4
        sta     hb_y1,y
        clc
        rts
@no:    sec
        rts

; ---------------------------------------------------------------- full screen
; SCREEN m [, w, h] (sc_w = m): 1 = 320 x 180, 2 = 640 x 360, a drawing area of w x h (at
; least the screen, w up to 2048, h up to 960), and 64 rows of panel below it
fs_screen:
        lda     sc_w
        sta     fs_m
        ldx     #320
        ldy     #180
        cmp     #1
        beq     :+
        ldx     #640
        ldy     #360
:       stx     fs_sw
        stx     sc_w
        sty     fs_sh
        sty     sc_h
        jsr     peek
        cmp     #','
        bne     @go
        inc     z:tp
        jsr     eval_u16
        sta     sc_w
        lda     #','
        jsr     expect
        jsr     eval_u16
        sta     sc_h
@go:    lda     sc_w
        cmp     fs_sw
        bcc     @bad
        cmp     #2049
        bcs     @bad
        lda     sc_h
        cmp     fs_sh
        bcc     @bad
        cmp     #961
        bcc     :+
@bad:   err     E_ARG
:       jsr     gfx_close
        lda     sc_w                    ; the stride: the width, a multiple of 16
        clc
        adc     #15
        and     #$FFF0
        sta     gstride
        sta     gwid
        lda     sc_h
        sta     fs_vh
        clc
        adc     #FS_PANEL
        sta     ghgt
        ldx     gstride                 ; banks: stride x rows, rounded up
        jsr     umul16
        cmp     #1
        txa
        adc     #0
        jsr     fs_balloc
        jsr     fs_rows
        lda     fs_sw                   ; the window: the screen's size, at most 636 x 324
        cmp     #GMAXW + 1
        bcc     :+
        lda     #GMAXW
:       sta     gww
        sta     sc_w
        lda     fs_sh
        cmp     #GMAXH + 1
        bcc     :+
        lda     #GMAXH
:       sta     gwh
        sta     sc_h
        jsr     gfx_corner
        jsr     gfx_wopen
        lda     fs_m
        sta     gmode
        lda     #FS_320X8               ; the block for fs_enter
        ldx     fs_m
        cpx     #1
        beq     :+
        lda     #FS_640X8
:       sta     fsblk                   ; mode, flags 0 (640 x 360: FS_PTR, the pointer)
        cmp     #FS_640X8
        bne     :+
        lda     #FS_640X8 | (FS_PTR << 8)
        sta     fsblk
:
        lda     gstride
        sta     fsblk+2
        lda     ghgt
        sta     fsblk+4
        stz     fsblk+6
        lda     gbk
        sta     fsblk+8                 ; (the base's bank, then 0)
        lda     gwin
        ptr     fsblk
        sys     SYS_FSENTER
        bcc     :+
        pha
        jsr     gfx_close
        pla
        cmp     #EAGAIN
        jne     g_bad
        err     E_INUSE
:       lda     #1
        sta     fsact
        lda     #0                      ; black (Ali's fills)
        jsr     gfx_clear
        jmp     dl_sync

; the row table of the framebuffer: row r at gbk + r x stride (a row may run into the next
; bank)
fs_rows:
        stz     z:t0                    ; the offset
        lda     gbk
        sta     z:t1                    ; the bank
        ldx     #0
:       lda     z:t0
        sta     f:WIN_ROWO,x
        lda     z:t1
        sta     f:WIN_ROWB,x
        lda     z:t0
        clc
        adc     gstride
        sta     z:t0
        bcc     :+
        inc     z:t1
:       inx
        inx
        txa
        lsr     a
        cmp     ghgt
        bcc     :--
        rts

; the window shows the top left of the framebuffer: gdx0 .. gdx1 of the rows gf_y .. gdy1,
; a blit a row (a row that runs into the next bank: two)
fs_flush:
@row:   lda     gf_y
        cmp     gdy1
        bcs     @out
        asl     a
        tax
        lda     gdx1
        sec
        sbc     gdx0
        sta     gblk+8
        lda     gdx0
        sta     gblk+4
        lda     f:WIN_ROWO,x
        clc
        adc     gdx0
        sta     gblk+12
        lda     f:WIN_ROWB,x
        adc     #0
        sta     gblk+14
        lda     gblk+12                 ; the bytes to the bank's end (0: all of it)
        eor     #$FFFF
        inc     a
        beq     @one
        cmp     gblk+8
        bcs     @one
        sta     gblk+8                  ; this bank's part, then the next bank's
        jsr     @blit
        lda     gblk+4
        clc
        adc     gblk+8
        sta     gblk+4
        lda     gdx1
        sec
        sbc     gblk+4
        sta     gblk+8
        stz     gblk+12
        inc     gblk+14
@one:   jsr     @blit
        inc     gf_y
        bra     @row
@out:   rts
@blit:  lda     #WD_SBLIT
        sta     gblk
        lda     gstride
        sta     gblk+1
        a8
        stz     gblk+3
        a16
        lda     gf_y
        sta     gblk+6
        lda     #1
        sta     gblk+10
        lda     gwin
        ptr     gblk
        sys     SYS_WDRAW
        rts

; A consecutive banks for the framebuffer -> gbk, gnb (Out of memory). The banks that are
; not next to the others are set aside meanwhile (WIN_ORPH), then given back.
fs_balloc:
        sta     fb_n
        stz     gnb
        stz     fb_no
@next:  sys     SYS_BALLOC
        bcs     @fail
        sta     z:t0
        ldx     gnb
        beq     @take
        dec     a
        cmp     gbk-2,x
        beq     @take
        ldy     #0                      ; not the next one: the run set aside, a new run
:       cpy     gnb
        bcs     :+
        lda     gbk,y
        ldx     fb_no
        sta     f:WIN_ORPH,x
        inx
        inx
        stx     fb_no
        iny
        iny
        bra     :-
:       stz     gnb
        lda     fb_no
        cmp     #256 - 2 * GBANKS
        bcs     @fail
@take:  lda     z:t0
        ldx     gnb
        sta     gbk,x
        inx
        inx
        stx     gnb
        txa
        lsr     a
        cmp     fb_n
        bcc     @next
        jmp     fb_orph
@fail:  jsr     fb_orph
        jsr     gfx_free
        err     E_MEM
; the banks set aside given back
fb_orph:
        ldx     #0
:       cpx     fb_no
        bcs     :+
        lda     f:WIN_ORPH,x
        phx
        sys     SYS_BFREE
        plx
        inx
        inx
        bra     :-
:       stz     fb_no
        rts

; full screen only (Full screen only)
fs_need:
        lda     gmode
        beq     :+
        lda     gwin
        bmi     :+
        rts
:       err     E_NOFS

; the full screen left for the desktop (END, STOP, errors, Break, INPUT): the window shows
; the picture; the framebuffer stays (CONT and the end of INPUT come back to it)
fs_suspend:
        lda     fsact
        beq     :+
        jsr     dl_sync
        lda     gwin
        sys     SYS_FSLEAVE
        stz     fsact
        jsr     dirty_all
:       rts

; ... and back (with the palette, the scroll set and the raster table)
fs_resume:
        lda     gmode
        beq     @out
        lda     fsact
        bne     @out
        lda     gwin
        bmi     @out
        ptr     fsblk
        sys     SYS_FSENTER
        bcs     @out
        lda     gwin                    ; (its window in front: shown at once)
        sys     SYS_WFRONT
        lda     #1
        sta     fsact
        sta     sc_dirty
        sta     r_dirty
        ldx     #0                      ; the palette entries the program set
@p:     lda     palchg,x
        and     #$00FF
        beq     @np
        phx
        txa
        asl     a
        adc     1,s
        tax
        lda     f:WIN_FSPAL+2,x
        and     #$00FF
        tay
        lda     f:WIN_FSPAL,x
        tax
        lda     1,s
        sys     SYS_WSPAL
        plx
@np:    inx
        cpx     #256
        bcc     @p
@out:   rts

; the full screen's own state forgotten (its window closed)
fs_forget:
        ldx     #0
:       stz     palchg,x
        inx
        inx
        cpx     #256
        bcc     :-
        stz     fsact
        stz     rcnt
        stz     fs_pnl
        stz     scx
        stz     scy
        stz     sc_ok
        stz     r_ok
        stz     sc_dirty
        stz     r_dirty
        rts

; SCROLL x, y: the drawing area shown from (x, y), a ring both ways (x modulo its width,
; y modulo its height)
st_scroll:
        jsr     fs_need
        jsr     eval_int
        lda     gwid
        jsr     acc_mod
        sta     scx
        lda     #','
        jsr     expect
        jsr     eval_int
        lda     fs_vh
        jsr     acc_mod
        sta     scy
        jsr     sc_set
        jmp     stmt_end
; the integer acc modulo A (> 0), 0 .. A - 1 also for a negative one -> A
acc_mod:
        sta     m_b
        stz     m_b+2
        lda     fhi
        sta     z:t7
        bpl     :+
        jsr     negate
:       lda     flo
        sta     m_a
        lda     fhi
        sta     m_a+2
        jsr     udiv32
        lda     m_a
        beq     :+
        ldx     z:t7
        bpl     :+
        lda     m_b
        sec
        sbc     m_a
:       rts

; PANEL n: the bottom n rows of the screen (n < 0: the top -n) show the panel, rows h to
; h + 63 of the drawing area, not scrolled; PANEL 0: none
st_panel:
        jsr     fs_need
        jsr     eval_int
        lda     flo
        clc
        adc     #FS_PANEL
        cmp     #FS_PANEL * 2 + 1
        jcs     g_bad
        lda     fhi
        bne     :+
        lda     flo
        bra     :++
:       cmp     #$FFFF
        jne     g_bad
        lda     flo
:       sta     fs_pnl
        jsr     r_check
        jsr     sc_set
        jmp     stmt_end

; the scroll set changed: sent at VSYNC (the first time at once: its errors here)
sc_set: lda     #1
        sta     sc_dirty
        lda     sc_ok
        bne     :+
        jsr     sc_flush
        lda     #1
        sta     sc_ok
:       rts

; lines a row: 2 in 320 x 180 -> A
fs_lpr: lda     #1
        ldx     fs_m
        cpx     #1
        bne     :+
        inc     a
:       rts

; the split line of the panel -> A (0: none)
fs_split:
        lda     fs_pnl
        beq     @out
        bmi     @top
        lda     fs_sh                   ; at the bottom: (rows - n) lines a row
        sec
        sbc     fs_pnl
        bra     @x
@top:   eor     #$FFFF
        inc     a
@x:     ldx     fs_m
        cpx     #1
        bne     @out
        asl     a
@out:   rts

; fs_scroll with the scroll set and the panel (while the full screen is left for the
; desktop: later, but for the first one, whose ENODEV is wanted at once)
sc_flush:
        lda     sc_dirty
        beq     @out
        lda     fsact
        bne     :+
        lda     sc_ok
        bne     @out
:       lda     scx
        sta     scb
        lda     scy
        sta     scb+2
        stz     scb+4
        stz     scb+6
        lda     fs_vh
        sta     scb+8
        jsr     fs_split
        sta     scb+10
        lda     #FSC_HWRAP
        sta     scb+12
        lda     fs_pnl
        beq     @go
        lda     #FSC_HWRAP | FSC_SPLIT
        sta     scb+12
        lda     fs_vh                   ; the panel's set: its rows, not wrapped
        sta     scb+6
        lda     fs_pnl
        bpl     @go
        stz     scb                     ; at the top: the panel first, the playfield second
        lda     fs_vh
        sta     scb+2
        lda     scx
        sta     scb+4
        lda     scy
        sta     scb+6
@go:    ptr     scb
        sys     SYS_FSSCROLL
        jsr     fs_res
        bcs     @out
        stz     sc_dirty
@out:   rts

; the result of fs_scroll or fs_raster: ENODEV: Not available; another error while the full
; screen is left: C set (later); else Bad argument
fs_res: bcc     @ok
        cmp     #ENODEV
        bne     :+
        err     E_NODEV
:       lda     fsact
        jne     g_bad
        sec
@ok:    rts

; RASTER row, i, r, g, b: from that row of the screen on, colour i is r, g, b (every frame
; starts with the palette's own); RASTER OFF: none. 16 at most; with a panel only from the
; split on (the panel at the bottom: rows in it; at the top: below it)
st_raster:
        jsr     fs_need
        jsr     peek
        cmp     #TK_OFF
        bne     :+
        inc     z:tp
        stz     rcnt
        jmp     @set
:       jsr     eval_u16
        sta     ra_l
        jsr     fs_lpr                  ; the line: row * lines a row
        cmp     #2
        bne     :+
        asl     ra_l
:       lda     ra_l
        jeq     @bad
        cmp     #360
        jcs     @bad
        jsr     fs_split
        cmp     ra_l
        beq     :+
        jcs     @bad
:       lda     #','
        jsr     expect
        jsr     byte_arg
        sta     ra_i
        lda     #','
        jsr     expect
        jsr     byte_arg
        sta     ra_c
        lda     #','
        jsr     expect
        jsr     byte_arg
        sta     ra_c+1
        lda     #','
        jsr     expect
        jsr     byte_arg
        sta     ra_c+2
        ldx     #0                      ; the same line and colour: replaced
        ldy     #0
@f:     cpy     rcnt
        bcs     @ins
        lda     rtab,x
        cmp     ra_l
        bne     :+
        lda     rtab+2,x
        and     #$00FF
        cmp     ra_i
        beq     @put
:       txa
        clc
        adc     #6
        tax
        iny
        bra     @f
@ins:   lda     rcnt                    ; a new one, after those of its line or before
        cmp     #16
        bcs     @bad
        asl     a
        adc     rcnt
        asl     a
        tax                             ; X = the end
:       cpx     #0
        beq     :+
        lda     rtab-6,x
        cmp     ra_l
        beq     :+
        bcc     :+
        lda     rtab-6,x                ; moved up one
        sta     rtab,x
        lda     rtab-4,x
        sta     rtab+2,x
        lda     rtab-2,x
        sta     rtab+4,x
        txa
        sec
        sbc     #6
        tax
        bra     :-
:       inc     rcnt
@put:   lda     ra_l
        sta     rtab,x
        lda     ra_i
        a8
        sta     rtab+2,x
        lda     ra_c
        sta     rtab+3,x
        lda     ra_c+1
        sta     rtab+4,x
        lda     ra_c+2
        sta     rtab+5,x
        a16
@set:   lda     #1
        sta     r_dirty
        lda     r_ok
        bne     :+
        jsr     r_flush
        lda     #1
        sta     r_ok
:       jmp     stmt_end
@bad:   err     E_ARG

; PANEL: the raster lines must still lie past the split
r_check:
        jsr     fs_split
        sta     z:t0
        ldx     #0
        ldy     #0
:       cpy     rcnt
        bcs     :+
        lda     rtab,x
        cmp     z:t0
        jcc     g_bad
        txa
        clc
        adc     #6
        tax
        iny
        bra     :-
:       lda     #1
        sta     r_dirty
        rts

; fs_raster with the table
r_flush:
        lda     r_dirty
        beq     @out
        lda     fsact
        bne     :+
        lda     r_ok
        bne     @out
:       lda     rcnt
        ptr     rtab
        sys     SYS_FSRASTER
        jsr     fs_res
        bcs     @out
        stz     r_dirty
@out:   rts

; ---------------------------------------------------------------- frames
; VSYNC: the frame's changes (the window's pixels, sprites, scroll, raster, Ali's list,
; whose first record waits for the vertical blank) sent, then the wait for that blank
st_vsync:
        jsr     gfx_flush
        jsr     spr_flush
        jsr     sc_flush
        jsr     r_flush
        lda     #LS_VBL
        jsr     dl_submit
        sys     SYS_VSYNC
        stz     dl_run                  ; (vsync waits for the list too)
        sys     SYS_UPTIME
        sta     vs_last
        lda     #1
        sta     vs_on
        jmp     stmt_end

; FRAME: the frame counter (60 a second, wraps at 65536)
f_frame:
        jsr     noargs
        sys     SYS_FRAME
        jmp     ret_u16

; the changes waiting, sent (flush_all) unless VSYNC paces the program (one in the last
; 100 ms)
game_flush:
        lda     vs_on
        beq     :+
        sys     SYS_UPTIME
        sec
        sbc     vs_last
        cmp     #100
        bcc     @out
        stz     vs_on
:       jsr     spr_flush
        jsr     sc_flush
        jsr     r_flush
        lda     #0
        jmp     dl_submit
@out:   rts

; END, STOP, errors, Break: sprites hidden (their table kept for CONT), the full screen left,
; the keys typed for the program (a game's arrows) not passed on to the command line
game_stop:
        lda     krh
        sta     krt
        jsr     dl_drop
        lda     sp_first
        bmi     :+
        lda     #$FFFF
        sys     SYS_SPRFREE
        lda     #$FFFF
        sta     sp_first
        sta     sp_dirty
:       stz     vs_on
        jmp     fs_suspend

; CONT: the full screen and the sprites shown again (their window in front)
game_resume:
        jsr     fs_resume
        lda     gwin
        bmi     @out
        lda     sp_first
        bpl     @out
        ldx     #0
:       lda     f:WIN_SPR,x
        and     #SPR_EN << 8
        bne     :+
        txa
        clc
        adc     #10
        tax
        cpx     #160
        bcc     :-
@out:   rts
:       lda     gwin
        sys     SYS_WFRONT
        jmp     sp_alloc

; RUN, NEW, LOAD: everything given back: sprites, pictures, samples, the full screen
game_reset:
        jsr     game_stop
        lda     gmode
        beq     :+
        jsr     gfx_close
:       ldx     #0
:       lda     pbk,x
        beq     :+
        phx
        sys     SYS_BFREE
        plx
        stz     pbk,x
:       inx
        inx
        cpx     #8
        bcc     :--
        lda     scbk
        beq     :+
        sys     SYS_BFREE
        stz     scbk
:       ldx     #0
:       stz     pick,x
        inx
        inx
        cpx     #NPIC * 2
        bcc     :-
        ldx     #0
        lda     #$FFFF
:       sta     spic,x
        stz     sflg,x
        inx
        inx
        cpx     #32
        bcc     :-
        ldx     #0
        lda     #0
:       sta     f:WIN_SPR,x
        inx
        inx
        cpx     #160
        bcc     :-
        jmp     snd_reset

        .segment "RODATA"
stab2:  .addr   st_sprite, st_shape, st_get, st_put, st_copy, st_wave, st_play, st_scroll
        .addr   st_panel, st_raster

        .segment "DATA"
sp_first: .word $FFFF                   ; the first of our 16 sprites ($FFFF: none)

        .segment "BSS"
pbk:    .res    8                       ; the picture banks (16 pictures each)
picw:   .res    NPIC * 2
pich:   .res    NPIC * 2
pick:   .res    NPIC * 2                ; PK_*
spcc:   .res    NPIC * 2                ; the sprite image's ctrl bits | palette bank << 8
scbk:   .res    2                       ; the sprite image bank
spic:   .res    32                      ; each sprite's picture ($FFFF: none)
sflg:   .res    32                      ; ... and flags
sp_dirty: .res  2
sp_n:   .res    2
sp_o:   .res    2
sp_t:   .res    2
se_n:   .res    2
se_p:   .res    2
se_f:   .res    2
se_c:   .res    2
se_pal: .res    2
sb_p:   .res    2
sb_w:   .res    2
sb_h:   .res    2
sb_k:   .res    2
sb_c:   .res    2
sb_bk:  .res    2
sb_hw:  .res    2
sb_hh:  .res    2
sb_r:   .res    2
sb_t:   .res    2
pc_p:   .res    2
sh_p:   .res    2
sh_r:   .res    2
gt_p:   .res    2
gt_r:   .res    2
pt_key: .res    2
bx:     .res    2
by:     .res    2
bw:     .res    2
bh:     .res    2
bc0:    .res    2
bc1:    .res    2
br0:    .res    2
br1:    .res    2
cx:     .res    2
cy:     .res    2
cp_dir: .res    2
ht_a:   .res    2
ht_b:   .res    2
hb_i:   .res    2
hb_x0:  .res    2                       ; two boxes: + 0, + 8
hb_y0:  .res    2
hb_x1:  .res    2
hb_y1:  .res    2
        .res    8
dl_rec: .res    20
dl_n:   .res    2
dl_off: .res    2
dl_px:  .res    4
dl_pa:  .res    4
dl_run: .res    2
ff_y:   .res    2
fs_m:   .res    2                       ; 1 or 2 (gmode while in full screen)
fs_sw:  .res    2                       ; the screen: 320 x 180 or 640 x 360
fs_sh:  .res    2
fs_vh:  .res    2                       ; the drawing area's height (the panel below it)
fsact:  .res    2                       ; fs_enter in effect
fsblk:  .res    10
fb_n:   .res    2
fb_no:  .res    2
scx:    .res    2
scy:    .res    2
fs_pnl:    .res    2
sc_ok:  .res    2
sc_dirty: .res  2
scb:    .res    14
rcnt:   .res    2
rtab:   .res    16 * 6
r_ok:   .res    2
r_dirty: .res   2
ra_l:   .res    2
ra_i:   .res    2
ra_c:   .res    4
vs_last: .res   2
vs_on:  .res    2
