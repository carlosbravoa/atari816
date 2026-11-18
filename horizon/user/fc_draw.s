; fc_draw.s - FreeCell's drawing (included by freecell.s).
;
; The images: made once at the start by the CPU from the art (user/fc_art.inc) in three banks:
; cards 0-25 side by side in ibank0 (1040 x 56), cards 26-51 in ibank1, and in xbank the six
; places one under the other (40 x 336: an empty free cell, the empty foundation of each suit
; with its suit's outline, an empty column). Each is a sheet (sheet_new), so a card on the
; window is one record of a sheet_draw list. Their corners are KEYC (skipped: SH_KEY).
;
; Drawing: `draw_region` draws a rectangle of the table from the game (the felt, then the
; places and cards that touch it, then the selection's frame and the cards of the win),
; every record cut to the rectangle here, so a list never draws outside what changed. The
; records gather in rbuf and go in one sheet_draw (flush; 128 a call), the first of a frame
; with SH_VBL (it starts in the vertical blank). A pile that changed is its region redrawn.
;
; Dragging and flying: the cards carried are "floating": hidden in their pile (hid_p, hid_i)
; and drawn on top at fl_x, fl_y. To move them (float_to) one list draws the parts of the old
; rectangle the new one does not cover (up to four strips: draw_region each) and the floating
; cards at the new place: every pixel is written once a frame, nothing flickers, and the
; cost follows what changed: a few records a frame.

; ---------------------------------------------------------------- the palette
; one entry a colour (pal_alloc, first free one each time); none left: the nearest system
; colour (fc_fb). Local 0 is the key.
pal_take:
        lda     #KEYC
        sta     cmapw
        lda     #1
        sta     z:g0
@c:     lda     #1
        ldx     #$FFFF
        sys     SYS_PALALLOC
        bcs     @fb
        sta     z:g1
        lda     z:g0                    ; its colour: rgb at (g0 - 1) * 3
        dec     a
        sta     z:t0
        asl     a
        adc     z:t0
        tax
        lda     fc_rgb+2,x
        and     #$00FF
        tay
        lda     fc_rgb,x
        tax
        lda     z:g1
        sys     SYS_WSPAL
        lda     z:g1
        bra     @set
@fb:    ldx     z:g0
        lda     fc_fb-1,x
        and     #$00FF
@set:   pha
        lda     z:g0
        asl     a
        tax
        pla
        sta     cmapw,x
        inc     z:g0
        lda     z:g0
        cmp     #NCOLS + 1
        bcc     @c
        rts

; ---------------------------------------------------------------- the images
mkimages:
        ldx     #0                      ; the templates in palette entries
:       lda     t_card,x
        jsr     @tr
        sep     #$20
        .a8
        sta     tcard,x
        rep     #$20
        .a16
        lda     t_slot,x
        jsr     @tr
        sep     #$20
        .a8
        sta     tslot,x
        rep     #$20
        .a16
        inx
        cpx     #CARDW * CARDH
        bcc     :-
        stz     z:g0                    ; the 52 faces
:       lda     z:g0
        jsr     mkface
        inc     z:g0
        lda     z:g0
        cmp     #52
        bcc     :-
        lda     #CARDW                  ; the places
        sta     z:istride
        lda     xbank
        sta     z:ip+2
        stz     z:ip
        ldx     #.loword(tslot)         ; an empty free cell
        jsr     blank
        lda     cmapw+2*FC_FELTL
        sta     z:ink
        stz     z:g0
@f:     lda     z:ip                    ; the foundations
        clc
        adc     #CARDW * CARDH
        sta     z:ip
        ldx     #.loword(tslot)
        jsr     blank
        lda     z:g0
        asl     a
        tax
        lda     mt_sb,x
        tax
        lda     #(CARDW - 18) / 2
        sta     z:ax
        lda     #24
        sta     z:ay
        jsr     pmask
        inc     z:g0
        lda     z:g0
        cmp     #4
        bcc     @f
        lda     z:ip                    ; an empty column: the outline only
        clc
        adc     #CARDW * CARDH
        sta     z:ip
        ldx     #.loword(tslot)
        jsr     blank
        lda     cmapw+2*FC_FELTD
        sta     z:t0
        ldy     #CARDW * CARDH - 1
        sep     #$20
        .a8
:       lda     [ip],y
        cmp     z:t0
        bne     :+
        lda     #KEYC
        sta     [ip],y
:       dey
        bpl     :--
        rep     #$20
        .a16
        rts
@tr:    and     #$00FF
        asl     a
        tay
        lda     cmapw,y
        rts

; A = card: its face (the same numbers as tools/mkfcart.py's face())
mkface: sta     z:g1
        jsr     cardimg                 ; -> rs, rsx, cbank
        lda     z:cbank
        sta     z:ip+2
        lda     z:rsx
        sta     z:ip
        lda     #ISTRIDE
        sta     z:istride
        ldx     #.loword(tcard)
        jsr     blank
        ldx     z:g1
        lda     cred,x
        and     #$00FF
        beq     :+
        lda     cmapw+2*FC_RED
        bra     :++
:       lda     cmapw+2*FC_INK
:       sta     z:ink
        lda     crank,x
        and     #$00FF
        sta     z:g3                    ; rank
        lda     csuit,x
        and     #$00FF
        asl     a
        sta     z:g4                    ; suit * 2
        lda     z:g3                    ; the rank at 3, 3
        asl     a
        tax
        lda     mt_rank,x
        tax
        lda     #3
        sta     z:ax
        sta     z:ay
        phx
        jsr     pmask
        plx
        lda     a:0,x                   ; the small suit after it
        and     #$00FF
        clc
        adc     #5
        sta     z:ax
        lda     #3
        sta     z:ay
        ldx     z:g4
        lda     mt_ss,x
        tax
        jsr     pmask
        lda     z:g3
        bne     :+
        ldx     z:g4                    ; an ace: the very big suit
        lda     mt_sa,x
        tax
        lda     #(CARDW - 26) / 2
        sta     z:ax
        lda     #22
        sta     z:ay
        jmp     pmask
:       cmp     #10
        bcs     @court
        ldx     z:g4                    ; 2-10: the big suit
        lda     mt_sb,x
        tax
        lda     #(CARDW - 18) / 2
        sta     z:ax
        lda     #24
        sta     z:ay
        jmp     pmask
@court: lda     #5                      ; J Q K: a frame, the letter, the medium suit
        sta     z:ax
        lda     #16
        sta     z:ay
        lda     #CARDW - 10
        sta     z:aw
        lda     #1
        sta     z:ah
        jsr     irect
        lda     #CARDH - 5
        sta     z:ay
        jsr     irect
        lda     #16
        sta     z:ay
        lda     #1
        sta     z:aw
        lda     #CARDH - 20
        sta     z:ah
        jsr     irect
        lda     #CARDW - 6
        sta     z:ax
        jsr     irect
        lda     z:g3
        sec
        sbc     #10
        asl     a
        tax
        lda     mt_cl,x
        tax
        lda     a:0,x                   ; centred
        and     #$00FF
        eor     #$FFFF
        sec
        adc     #CARDW
        lsr     a
        sta     z:ax
        lda     #20
        sta     z:ay
        jsr     pmask
        ldx     z:g4
        lda     mt_sm,x
        tax
        lda     #(CARDW - 10) / 2
        sta     z:ax
        lda     #41
        sta     z:ay
        jmp     pmask

; A = card -> rs = its sheet, rsx = its x there, cbank = its bank (keeps X, Y)
cardimg:
        cmp     #26
        bcc     :+
        sbc     #26
        pha
        lda     sh1
        sta     z:rs
        lda     ibank1
        bra     :++
:       pha
        lda     sh0
        sta     z:rs
        lda     ibank0
:       sta     z:cbank
        pla
        asl     a                       ; * 40
        asl     a
        asl     a
        sta     z:rsx
        asl     a
        asl     a
        clc
        adc     z:rsx
        sta     z:rsx
        rts

; the template X (40 x 56 in palette entries) into the image ip (rows istride apart)
blank:  stx     z:t0
        lda     z:ip
        sta     z:rp
        lda     z:ip+2
        sta     z:rp+2
        lda     #CARDH
        sta     z:t1
@r:     ldx     z:t0
        ldy     #0
        sep     #$20
        .a8
:       lda     a:0,x
        sta     [rp],y
        inx
        iny
        cpy     #CARDW
        bcc     :-
        rep     #$20
        .a16
        stx     z:t0
        lda     z:rp
        clc
        adc     z:istride
        sta     z:rp
        dec     z:t1
        bne     @r
        rts

; rp = the image ip's pixel ax, ay
imgxy:  lda     z:ay
        ldx     z:istride
        jsr     umul16
        clc
        adc     z:ip
        clc
        adc     z:ax
        sta     z:rp
        lda     z:ip+2
        sta     z:rp+2
        rts

; the mask X at ax, ay of the image ip in colour ink
pmask:  lda     a:0,x
        pha
        and     #$00FF
        sta     z:mw
        clc
        adc     #7
        lsr     a
        lsr     a
        lsr     a
        sta     z:mb
        pla
        xba
        and     #$00FF
        sta     z:mh
        inx
        inx
        stx     z:mk
        jsr     imgxy
@row:   ldx     z:mk
        ldy     #0
@col:   tya
        and     #7
        bne     :+
        lda     a:0,x                   ; the next byte, its bit 7 into bit 15
        inx
        xba
        and     #$FF00
        sta     z:t0
:       asl     z:t0
        bcc     :+
        lda     z:ink
        sep     #$20
        .a8
        sta     [rp],y
        rep     #$20
        .a16
:       iny
        cpy     z:mw
        bcc     @col
        lda     z:mk
        clc
        adc     z:mb
        sta     z:mk
        lda     z:rp
        clc
        adc     z:istride
        sta     z:rp
        dec     z:mh
        bne     @row
        rts

; the rectangle ax, ay, aw x ah of the image ip in colour ink
irect:  jsr     imgxy
        lda     z:ah
        sta     z:t1
@r:     ldy     #0
        lda     z:ink
        sep     #$20
        .a8
:       sta     [rp],y
        iny
        cpy     z:aw
        bcc     :-
        rep     #$20
        .a16
        lda     z:rp
        clc
        adc     z:istride
        sta     z:rp
        dec     z:t1
        bne     @r
        rts

; the three sheets -> C set: not made
mksheets:
        lda     ibank0
        ldx     #ISTRIDE
        ldy     #CARDH
        jsr     @new
        bcs     @out
        sta     sh0
        lda     ibank1
        ldx     #ISTRIDE
        ldy     #CARDH
        jsr     @new
        bcs     @out
        sta     sh1
        lda     xbank
        ldx     #CARDW
        ldy     #6 * CARDH
        jsr     @new
        bcs     @out
        sta     shx
@out:   rts
@new:   sta     shnb+2                  ; bank A, offset 0, stride = width X, height Y
        stz     shnb
        stx     shnb+4
        stx     shnb+6
        sty     shnb+8
        ptr     shnb
        sys     SYS_SHEETNEW
        rts

; ---------------------------------------------------------------- records
; begin a frame: its first record waits for the vertical blank (REV $09+: with Ali's command
; lists; on REV $08 the kernel starts the records one by one: there it does not wait, as
; Quabricks; the kernel's old trouble with that wait is fixed in Horizon 0.25)
frame:  lda     vblok
        sta     rvbl
        rts

; a copy keyed: sheet rs, from rsx, rsy, aw x ah, to ax, ay; cut to the clip
rec_img:
        jsr     clip
        bcc     @out
        lda     #SH_KEY
        ora     rvbl
        xba
        ora     z:rs
        sta     rbuf+SD_SHEET,x
        lda     #KEYC
        sta     rbuf+SD_C,x
        lda     z:t0
        sec
        sbc     z:ax
        clc
        adc     z:rsx
        sta     rbuf+SD_SX,x
        lda     z:t2
        sec
        sbc     z:ay
        clc
        adc     z:rsy
        sta     rbuf+SD_SY,x
        jmp     rec_end
@out:   rts

; a fill of colour A: ax, ay, aw x ah cut to the clip
rec_fill:
        sta     z:t5
        jsr     clip
        bcc     @out
        lda     #SH_FILL
        ora     rvbl
        xba
        and     #$FF00
        sta     rbuf+SD_SHEET,x
        lda     z:t5
        and     #$00FF
        sta     rbuf+SD_C,x
        jmp     rec_end
@out:   rts

; the record at X: its size and place from the clip's numbers; counted (a full buffer goes)
rec_end:
        lda     z:t1
        sec
        sbc     z:t0
        sta     rbuf+SD_W,x
        lda     z:t3
        sec
        sbc     z:t2
        sta     rbuf+SD_H,x
        lda     z:t0
        sta     rbuf+SD_X,x
        lda     z:t2
        sta     rbuf+SD_Y,x
        stz     rvbl
        inc     rn
        lda     rn
        cmp     #128
        bcc     :+
        jmp     flush
:       rts

; ax, ay, aw, ah cut to the clip -> C set: t0 .. t1, t2 .. t3 (x, y), X = the next record
clip:   lda     z:ax
        cmp     z:clx0
        bpl     :+
        lda     z:clx0
:       sta     z:t0
        lda     z:ax
        clc
        adc     z:aw
        cmp     z:clx1
        bmi     :+
        lda     z:clx1
:       sta     z:t1
        sec
        sbc     z:t0
        beq     @no
        bmi     @no
        lda     z:ay
        cmp     z:cly0
        bpl     :+
        lda     z:cly0
:       sta     z:t2
        lda     z:ay
        clc
        adc     z:ah
        cmp     z:cly1
        bmi     :+
        lda     z:cly1
:       sta     z:t3
        sec
        sbc     z:t2
        beq     @no
        bmi     @no
        lda     rn
        asl     a
        asl     a
        asl     a
        asl     a
        tax
        sec
        rts
@no:    clc
        rts

; the records gathered: one sheet_draw
flush:  lda     rn
        beq     @out
        xba
        ora     win
        ptr     rbuf
        sys     SYS_SHEETDRAW
        stz     rn
@out:   rts

; ---------------------------------------------------------------- the table
; the whole table
draw_all:
        jsr     frame
        stz     z:rx
        stz     z:ry
        lda     #WW
        sta     z:rw
        lda     #STATY
        sta     z:rh
        jsr     draw_region
        jmp     flush

; A = pile: its region (with the selection's frame) redrawn (not flushed)
redraw_pile:
        pha
        jsr     pilexy
        pla
        lda     z:ax
        sec
        sbc     #3
        sta     z:rx
        lda     #CARDW + 6
        sta     z:rw
        lda     z:ay
        sec
        sbc     #3
        sta     z:ry
        lda     z:ay
        cmp     #CY0
        bcc     :+
        lda     #CBOT + 3 - (CY0 - 3)
        bra     :++
:       lda     #CARDH + 6
:       sta     z:rh
        lda     rvbl                    ; (a frame of its own unless one is begun)
        bne     :+
        lda     rn
        bne     :+
        jsr     frame
:       jmp     draw_region

; A = pile -> ax, ay: its place (a column's first card)
pilexy: cmp     #P_CASC
        bcc     :+
        sbc     #P_CASC
        asl     a
        tax
        lda     colx,x
        sta     z:ax
        lda     #CY0
        sta     z:ay
        rts
:       asl     a
        tax
        lda     colx,x
        sta     z:ax
        lda     #TOPY
        sta     z:ay
        rts

; A = pile -> A = the step between its cards (a column: smaller when it is long)
pstep:  cmp     #P_CASC
        bcc     @d
        asl     a
        tax
        lda     pcnt,x
        cmp     #2
        bcc     @d
        dec     a
        sta     z:t6
        ldx     #DSTEP                  ; (n - 1) * DSTEP fits?
        jsr     umul16
        cmp     #CBOT - CY0 - CARDH + 1
        bcc     @d
        lda     #CBOT - CY0 - CARDH
        ldx     z:t6
        jsr     udiv16
        cmp     #MINSTEP
        bcs     :+
        lda     #MINSTEP
:       rts
@d:     lda     #DSTEP
        rts

; A = pile, X = index -> ax, ay: where that card lies
cardpos:
        phx
        pha
        jsr     pilexy
        pla
        cmp     #P_CASC
        bcc     @top
        jsr     pstep
        plx
        jsr     umul16
        clc
        adc     #CY0
        sta     z:ay
        rts
@top:   plx
        rts

; the region rx, ry, rw x rh of the table (cut to it) drawn from the game into the list
draw_region:
        lda     z:rx
        bpl     :+
        lda     #0
:       sta     z:clx0
        lda     z:rx
        clc
        adc     z:rw
        cmp     #WW
        bmi     :+
        lda     #WW
:       sta     z:clx1
        lda     z:ry
        bpl     :+
        lda     #0
:       sta     z:cly0
        lda     z:ry
        clc
        adc     z:rh
        cmp     #STATY
        bmi     :+
        lda     #STATY
:       sta     z:cly1
        lda     z:clx0
        sta     z:ax
        lda     z:cly0
        sta     z:ay
        lda     z:clx1
        sec
        sbc     z:clx0
        jmi     @out
        jeq     @out
        sta     z:aw
        lda     z:cly1
        sec
        sbc     z:cly0
        jmi     @out
        jeq     @out
        sta     z:ah
        lda     cmapw+2*FC_FELT         ; the felt
        jsr     rec_fill
        lda     z:cly0                  ; the top row
        cmp     #TOPY + CARDH
        bcs     @cols
        stz     z:g0
:       lda     z:g0
        jsr     drawtop
        inc     z:g0
        lda     z:g0
        cmp     #P_CASC
        bcc     :-
@cols:  lda     z:cly1
        cmp     #CY0 + 1
        bcc     @sel
        lda     #P_CASC
        sta     z:g0
:       lda     z:g0
        jsr     drawcol
        inc     z:g0
        lda     z:g0
        cmp     #NP
        bcc     :-
@sel:   jsr     drawsel
        lda     celeb
        beq     @out
        jsr     drawdisp
@out:   rts

; A = pile 0-7 (a free cell or a foundation): its place or its top card
drawtop:
        sta     z:g1
        jsr     pilexy
        lda     z:ax                    ; (outside the clip: nothing)
        clc
        adc     #CARDW
        cmp     z:clx0
        bmi     @out
        beq     @out
        lda     z:ax
        cmp     z:clx1
        bpl     @out
        lda     z:g1
        asl     a
        tax
        lda     pcnt,x
        ldy     z:g1
        cpy     hid_p
        bne     :+
        lda     hid_i
:       cmp     #0
        beq     @empty
        dec     a
        sta     z:t6
        lda     celeb                   ; (the win: a foundation shows its king to the end)
        beq     :+
        lda     z:g1
        cmp     #P_FOUND
        bcc     :+
        sec
        sbc     #P_FOUND
        sta     z:t6
        asl     a
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:t6
        sbc     z:t6
        sbc     z:t6
        clc
        adc     #12
        bra     @card
:       lda     z:g1
        jsr     pofs
        txa
        clc
        adc     z:t6
        tax
        lda     pcards,x
        and     #$00FF
@card:  jsr     cardimg
        stz     z:rsy
        lda     #CARDW
        sta     z:aw
        lda     #CARDH
        sta     z:ah
        jmp     rec_img
@empty: lda     z:g1                    ; a cell: place 0; a foundation: 1 + its suit
        cmp     #P_FOUND
        bcc     :+
        sbc     #P_FOUND - 1
        bra     :++
:       lda     #0
:       jsr     place
        jmp     rec_img
@out:   rts

; A = place 0-5 -> rs, rsx, rsy, aw, ah
place:  ldx     #CARDH
        jsr     umul16
        sta     z:rsy
        stz     z:rsx
        lda     shx
        sta     z:rs
        lda     #CARDW
        sta     z:aw
        lda     #CARDH
        sta     z:ah
        rts

; A = column pile: its cards (or its empty place)
drawcol:
        sta     z:g1
        jsr     pilexy
        lda     z:ax
        clc
        adc     #CARDW
        cmp     z:clx0
        jmi     @out
        jeq     @out
        lda     z:ax
        cmp     z:clx1
        jmi     :+
        jmp     @out
:
        lda     z:g1
        asl     a
        tax
        lda     pcnt,x
        ldy     z:g1
        cpy     hid_p
        bne     :+
        lda     hid_i
:       sta     z:g2                    ; the cards shown
        cmp     #0
        bne     :+
        lda     celeb                   ; (no empty places under the win's display)
        jne     @out
        lda     #5
        jsr     place
        jmp     rec_img
:       lda     z:g1
        jsr     pstep
        sta     z:g3
        lda     z:g1
        jsr     pofs
        stx     z:g4                    ; its first card's offset
        stz     z:g5                    ; index
@c:     lda     z:ay                    ; below the clip: done
        cmp     z:cly1
        jmi     :+
        jmp     @out
:
        lda     z:g5
        inc     a
        cmp     z:g2
        beq     @last
        lda     z:g3                    ; covered: its top part (and the next one's corner)
        inc     a
        inc     a
        bra     :+
@last:  lda     #CARDH
:       sta     z:ah
        clc
        adc     z:ay
        cmp     z:cly0                  ; above the clip: the next one
        bmi     @n
        beq     @n
        ldx     z:g4
        lda     pcards,x
        and     #$00FF
        jsr     cardimg
        stz     z:rsy
        lda     #CARDW
        sta     z:aw
        jsr     rec_img
@n:     inc     z:g4
        lda     z:ay
        clc
        adc     z:g3
        sta     z:ay
        inc     z:g5
        lda     z:g5
        cmp     z:g2
        bcc     @c
@out:   rts

; the selection's frame (2 pixels round the selected cards, 1 pixel away)
drawsel:
        lda     sel_p
        jmi     @out
        ldx     sel_i
        jsr     cardpos
        lda     sel_p                   ; height: to the bottom of the last card
        cmp     #P_CASC
        bcc     @one
        jsr     pstep
        pha
        lda     sel_p
        asl     a
        tax
        lda     pcnt,x
        dec     a
        sec
        sbc     sel_i
        tax
        pla
        jsr     umul16
        clc
        adc     #CARDH
        bra     :+
@one:   lda     #CARDH
:       sta     z:g2                    ; h
        lda     z:ax
        sec
        sbc     #3
        sta     z:ax
        sta     z:g0
        lda     z:ay
        sec
        sbc     #3
        sta     z:ay
        sta     z:g1
        lda     #CARDW + 6              ; top
        sta     z:aw
        lda     #2
        sta     z:ah
        jsr     @f
        lda     z:g1                    ; bottom
        clc
        adc     z:g2
        adc     #4
        sta     z:ay
        jsr     @f
        lda     z:g1                    ; left
        clc
        adc     #2
        sta     z:ay
        lda     #2
        sta     z:aw
        lda     z:g2
        clc
        adc     #2
        sta     z:ah
        jsr     @f
        lda     z:g0                    ; right
        clc
        adc     #CARDW + 4
        sta     z:ax
@f:     lda     cmapw+2*FC_SEL
        jmp     rec_fill
@out:   rts

; ---------------------------------------------------------------- floating cards
; A = pile, X = index: the cards from there float (hidden in the pile, drawn by float_to);
; nothing is drawn yet (they are where they were)
lift:   sta     hid_p
        stx     hid_i
        stx     z:t6
        jsr     cardpos
        lda     z:ax
        sta     fl_x
        lda     z:ay
        sta     fl_y
        lda     hid_p
        jsr     pstep
        sta     fl_step
        lda     hid_p
        asl     a
        tax
        lda     pcnt,x
        sec
        sbc     hid_i
        sta     fl_n
        lda     hid_p
        jsr     pofs
        txa
        clc
        adc     hid_i
        tax
        ldy     #0
        sep     #$20
        .a8
:       lda     pcards,x
        sta     fl_cards,y
        inx
        iny
        cpy     fl_n
        bcc     :-
        rep     #$20
        .a16
        lda     fl_n
        dec     a
        ldx     fl_step
        jsr     umul16
        clc
        adc     #CARDH
        sta     fl_h
        lda     #1
        sta     fl_on
        rts

; the floating cards to A = x, X = y (kept on the table): one list, the old place's strips
; that the new one leaves, then the cards
float_to:
        bpl     :+
        lda     #0
:       cmp     #WW - CARDW
        bmi     :+
        lda     #WW - CARDW
:       sta     z:g0                    ; new x
        txa
        bpl     :+
        lda     #0
:       sta     z:g1
        lda     #STATY
        sec
        sbc     fl_h
        cmp     z:g1
        bpl     :+
        sta     z:g1                    ; new y
:       lda     z:g0
        cmp     fl_x
        bne     :+
        lda     z:g1
        cmp     fl_y
        bne     :+
        rts
:       jsr     frame
        lda     fl_x                    ; the old rectangle q
        sta     z:qx
        lda     fl_y
        sta     z:qy
        lda     #CARDW
        sta     z:qw
        lda     fl_h
        sta     z:qh
        lda     z:g0
        sta     fl_x
        lda     z:g1
        sta     fl_y
        ; above the new one
        lda     fl_y
        cmp     z:qy
        bmi     @below
        beq     @below
        lda     z:qx
        sta     z:rx
        lda     z:qy
        sta     z:ry
        lda     #CARDW
        sta     z:rw
        lda     z:qy                    ; min(new y, old bottom) - old y
        clc
        adc     z:qh
        cmp     fl_y
        bmi     :+
        lda     fl_y
:       sec
        sbc     z:qy
        sta     z:rh
        jsr     draw_region
@below: lda     fl_y                    ; below the new one: from max(new bottom, old y)
        clc
        adc     fl_h
        sta     z:t7
        lda     z:qy
        clc
        adc     z:qh
        sec
        sbc     z:t7
        bmi     @mid
        beq     @mid
        lda     z:t7
        cmp     z:qy
        bpl     :+
        lda     z:qy
:       sta     z:ry
        lda     z:qy
        clc
        adc     z:qh
        sec
        sbc     z:ry
        sta     z:rh
        lda     z:qx
        sta     z:rx
        lda     #CARDW
        sta     z:rw
        jsr     draw_region
@mid:   lda     fl_y                    ; the rows of both: y0 = max(tops), y1 = min(bottoms)
        cmp     z:qy
        bpl     :+
        lda     z:qy
:       sta     z:fy0
        lda     fl_y
        clc
        adc     fl_h
        sta     z:t7
        lda     z:qy
        clc
        adc     z:qh
        cmp     z:t7
        bmi     :+
        lda     z:t7
:       sec
        sbc     z:fy0
        bmi     @cards
        beq     @cards
        sta     z:fh0
        lda     fl_x                    ; left of the new one
        cmp     z:qx
        bmi     @right
        beq     @right
        lda     z:qx
        sta     z:rx
        lda     fl_x
        sec
        sbc     z:qx
        cmp     #CARDW
        bmi     :+
        lda     #CARDW
:       sta     z:rw
        lda     z:fy0
        sta     z:ry
        lda     z:fh0
        sta     z:rh
        jsr     draw_region
@right: lda     z:qx                    ; right of it
        cmp     fl_x
        bmi     @cards
        beq     @cards
        lda     fl_x
        clc
        adc     #CARDW
        cmp     z:qx
        bpl     :+
        lda     z:qx
:       sta     z:rx
        lda     z:qx
        clc
        adc     #CARDW
        sec
        sbc     z:rx
        sta     z:rw
        lda     z:fy0
        sta     z:ry
        lda     z:fh0
        sta     z:rh
        jsr     draw_region
@cards: jsr     drawfloat
        jmp     flush

; the floating cards at fl_x, fl_y (clip: the table)
drawfloat:
        stz     z:clx0
        stz     z:cly0
        lda     #WW
        sta     z:clx1
        lda     #STATY
        sta     z:cly1
        lda     fl_x
        sta     z:ax
        lda     fl_y
        sta     z:ay
        stz     z:g5
@c:     lda     z:g5
        inc     a
        cmp     fl_n
        beq     @last
        lda     fl_step
        inc     a
        inc     a
        bra     :+
@last:  lda     #CARDH
:       sta     z:ah
        lda     #CARDW
        sta     z:aw
        ldx     z:g5
        lda     fl_cards,x
        and     #$00FF
        jsr     cardimg
        stz     z:rsy
        jsr     rec_img
        lda     z:ay
        clc
        adc     fl_step
        sta     z:ay
        inc     z:g5
        lda     z:g5
        cmp     fl_n
        bcc     @c
        rts

; the floating cards land: shown in their piles again; the old place redrawn
float_end:
        lda     fl_on
        beq     @out
        stz     fl_on
        lda     #$FFFF
        sta     hid_p
        jsr     frame
        lda     fl_x
        sta     z:rx
        lda     fl_y
        sta     z:ry
        lda     #CARDW
        sta     z:rw
        lda     fl_h
        sta     z:rh
        jsr     draw_region
@out:   rts

; the floating cards fly to A = x, X = y: a frame each step (more steps for longer ways)
fly:    sta     z:g2                    ; (g0, g1: float_to's)
        stx     z:g3
        sec
        sbc     fl_x
        sta     z:qx                    ; dx
        txa
        sec
        sbc     fl_y
        sta     z:qy                    ; dy
        lda     fl_x
        sta     z:rx                    ; the start (rx, ry: not used by float_to's caller)
        lda     fl_y
        sta     z:ry
        lda     z:qx                    ; steps: |dx| + |dy| over 24, 3 .. 12
        bpl     :+
        eor     #$FFFF
        inc     a
:       sta     z:t7
        lda     z:qy
        bpl     :+
        eor     #$FFFF
        inc     a
:       clc
        adc     z:t7
        ldx     #24
        jsr     udiv16
        cmp     #3
        bcs     :+
        lda     #3
:       cmp     #13
        bcc     :+
        lda     #12
:       ldx     flyn                    ; (or as many as asked)
        beq     :+
        txa
:       sta     z:mw                    ; (pmask's: free here)
        lda     #1
        sta     z:mh
        lda     z:rx
        sta     z:mk                    ; the start x
        lda     z:ry
        sta     z:mb                    ; and y
@s:     lda     z:qx                    ; x = x0 + dx * k / n
        ldx     z:mh
        jsr     smuldiv
        clc
        adc     z:mk
        pha
        lda     z:qy
        ldx     z:mh
        jsr     smuldiv
        clc
        adc     z:mb
        tax
        pla
        pei     (qx)
        pei     (qy)
        jsr     float_to
        pla
        sta     z:qy
        pla
        sta     z:qx
        sys     SYS_VSYNC
        inc     z:mh
        lda     z:mh
        cmp     z:mw
        bcc     @s
        beq     @s
        rts

; A (signed) * X / mw -> A (signed; small numbers)
smuldiv:
        stz     z:t7                    ; the sign
        cmp     #0
        bpl     :+
        eor     #$FFFF
        inc     a
        inc     z:t7
:       jsr     umul16
        ldx     z:mw
        jsr     udiv16
        ldx     z:t7
        beq     :+
        eor     #$FFFF
        inc     a
:       rts

; the move checked by can_move (ms, mi, md, mn), flags mf: the cards fly there (lifted
; first unless they float already), the move is made, both piles are drawn
animove:
        lda     z:mf                    ; the player's move: the game counts, the clock reads
        and     #MF_AUTO                ; (the win's time: what the player took, not the
        bne     :+                      ; cards flying home after it)
        jsr     firstmove
        jsr     clock
        lda     secs
        sta     secs0
:       lda     fl_on
        bne     :+
        lda     z:ms
        ldx     z:mi
        jsr     lift
:       lda     z:md                    ; where the first card lands
        asl     a
        tax
        lda     pcnt,x
        tax
        lda     z:md
        cmp     #P_CASC
        bcs     :+
        ldx     #0
:       jsr     cardpos
        lda     z:ax
        ldx     z:ay
        jsr     fly
        jsr     do_move
        jsr     float_end               ; (begins the frame)
        lda     z:ms
        jsr     redraw_pile
        lda     z:md
        jsr     redraw_pile
        jsr     flush
        jmp     placesnd

; ---------------------------------------------------------------- the win
; The 52 cards leave the foundations one by one (the aces first) and fly to a display: four
; rows, one a suit, ace to king fanned out. A key or a click shows the end at once.
DSX     = 28                            ; the display: the ace of clubs, the steps
DSY     = 82
DSDX    = 28
DSDY    = 52
winanim:
        lda     #1
        sta     celeb
        stz     dn
        lda     #4                      ; (4 frames a card: about 3.5 s in all)
        sta     flyn
        jsr     draw_all                ; (the empty places go)
@k:     lda     dn                      ; card k: rank k / 4, suit k mod 4
        lsr     a
        lsr     a
        sta     z:g4
        lda     dn
        and     #3
        sta     z:g5
        sta     z:t6                    ; c = suit * 13 + rank
        asl     a
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:t6
        sbc     z:t6
        sbc     z:t6
        clc
        adc     z:g4
        sep     #$20
        .a8
        sta     fl_cards
        rep     #$20
        .a16
        lda     #1
        sta     fl_n
        sta     fl_on
        lda     #DSTEP
        sta     fl_step
        lda     #CARDH
        sta     fl_h
        lda     z:g5                    ; from its foundation
        clc
        adc     #P_FOUND
        pha
        asl     a
        tax
        dec     pcnt,x
        pla
        jsr     pilexy
        lda     z:ax
        sta     fl_x
        lda     z:ay
        sta     fl_y
        lda     z:g4                    ; to its place on display
        ldx     #DSDX
        jsr     umul16
        clc
        adc     #DSX
        pha
        lda     z:g5
        ldx     #DSDY
        jsr     umul16
        clc
        adc     #DSY
        tax
        pla
        jsr     fly
        inc     dn
        jsr     float_end
        jsr     flush
        lda     #1                      ; a key or a click: the end at once
        jsr     ui_getev
        bcs     :+
        lda     ui_ev
        and     #$00FF
        cmp     #WE_KEY
        beq     @end
        cmp     #WE_BUTTON
        beq     @end
:       lda     dn
        cmp     #52
        jcc     @k
        stz     flyn
        rts
@end:   stz     flyn
        lda     #52
        sta     dn
        ldx     #6
:       stz     pcnt+2*P_FOUND,x
        dex
        dex
        bpl     :-
        jmp     draw_all

; the cards on display (dn of them, in the order they came), cut to the clip
drawdisp:
        stz     z:g5                    ; suit (row)
@r:     stz     z:g4                    ; rank
@c:     lda     z:g4                    ; came yet? (k = rank * 4 + suit < dn)
        asl     a
        asl     a
        clc
        adc     z:g5
        cmp     dn
        bcs     @n
        lda     z:g4
        ldx     #DSDX
        jsr     umul16
        clc
        adc     #DSX
        sta     z:ax
        lda     z:g5
        ldx     #DSDY
        jsr     umul16
        clc
        adc     #DSY
        sta     z:ay
        lda     #CARDW
        sta     z:aw
        lda     #CARDH
        sta     z:ah
        lda     z:g5
        sta     z:t6
        asl     a
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:t6
        sbc     z:t6
        sbc     z:t6
        clc
        adc     z:g4
        jsr     cardimg
        stz     z:rsy
        jsr     rec_img
@n:     inc     z:g4
        lda     z:g4
        cmp     #13
        bcc     @c
        inc     z:g5
        lda     z:g5
        cmp     #4
        bcc     @r
        rts

; ---------------------------------------------------------------- hit test
; the pointer at ex, ey -> C set: hpl = the pile there, hix = the card under it ($FFFF: the
; pile's place, empty or below its cards)
hittest:
        lda     z:ex                    ; the column: (x - COLX0) / PITCH, inside a card's width
        sec
        sbc     #COLX0
        jmi     @no
        ldx     #PITCH
        jsr     udiv16
        cmp     #8
        jcs     @no
        sta     z:t5
        asl     a
        tax
        lda     z:ex
        sec
        sbc     colx,x
        cmp     #CARDW
        bcs     @no
        lda     z:ey
        cmp     #CY0
        bcs     @col
        sec                             ; the top row
        sbc     #TOPY
        bcc     @no
        cmp     #CARDH
        bcs     @no
        lda     z:t5
        sta     z:hpl
        asl     a
        tax
        lda     pcnt,x
        dec     a
        sta     z:hix
        sec
        rts
@col:   lda     z:t5
        clc
        adc     #P_CASC
        sta     z:hpl
        asl     a
        tax
        lda     pcnt,x
        sta     z:t4                    ; n
        lda     #$FFFF
        sta     z:hix
        lda     z:t4
        beq     @yes
        lda     z:hpl
        jsr     pstep
        sta     z:t6
        lda     z:hpl                   ; (n again: pstep took t4)
        asl     a
        tax
        lda     pcnt,x
        sta     z:t4
        lda     z:ey                    ; the last card whose top is above the pointer
        sec
        sbc     #CY0
        ldx     z:t6
        jsr     udiv16
        cmp     z:t4
        bcc     :+
        lda     z:t4
        dec     a
:       sta     z:t5
        ldx     z:t6                    ; inside it?
        jsr     umul16
        clc
        adc     #CY0 + CARDH
        cmp     z:ey
        bcc     @yes
        beq     @yes
        lda     z:t5
        sta     z:hix
@yes:   sec
        rts
@no:    clc
        rts
