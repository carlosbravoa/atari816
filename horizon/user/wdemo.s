; WDEMO - window system demo (stage 1): starts the window system and opens three windows:
; "Shapes" (rectangles, frames, lines), "Text" (the UI font and the 8x12 font) and
; "Palette" (the 256 system colours). Close boxes close windows; a key closes the top
; window; when none is left the window system stops and WDEMO ends.
; "wdemo bench" measures instead: a full repaint, a window move step, a text line, and
; prints the figures on the console log (DBG_OUT), then ends.
; "wdemo copy" tests win_draw's copy (WD_COPY) instead: one window with a pattern, then
; moves inside it in every direction (overlapping) and partly outside it; a key ends it.
; make test freezes its picture: the same with the blitter and with the CPU.
; "wdemo menu" (0.13) opens one window "Menus" with two menus showing item states (a check
; mark, a dimmed item: win_mstate) and shortcut texts; Options > Grid / Snap toggle their
; check marks, Window > Enable Print dims / enables Print, Quit or the close box ends it.
; Works in the Desktop too (the window system already running).
; "wdemo draw" (0.14) tests the 1 bpp expand (WD_EXPAND: opaque, transparent, from a bit
; offset, clipped) and the keyed blit with a source stride (WD_KSBLIT, clipped); a "g"
; then moves and resizes the window with SYS_WGEOM and draws it all again; another key
; ends it. make test freezes its pictures: the same with the blitter and with the CPU.
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  sta     z:alen
        sys     SYS_WSSTART
        jcs     fail
        lda     z:alen
        beq     :+
        lda     f:0,x                   ; (the argument, in the window)
        and     #$00DF
        cmp     #'C'
        jeq     copytest
        cmp     #'M'
        jeq     menutest
        cmp     #'D'
        jeq     drawtest
:       ptr     wa
        sys     SYS_WOPEN
        sta     z:wina
        ptr     wb
        sys     SYS_WOPEN
        sta     z:winb
        ptr     wc
        sys     SYS_WOPEN
        sta     z:winc
        lda     #3
        sta     z:open
        jsr     shapes
        jsr     texts
        jsr     palette
        lda     z:alen
        jne     bench

loop:   lda     #0                      ; wait for an event
        ptr     ev
        sys     SYS_WEVENT
        bcs     loop
        lda     ev
        and     #$00FF
        cmp     #WE_CLOSE
        beq     @close
        cmp     #WE_KEY
        bne     @btn
        lda     ev+4                    ; key down closes that window
        and     #$0100
        beq     loop
        bra     @close
@btn:   cmp     #WE_BUTTON              ; a click in Shapes draws a small square there
        bne     loop
        lda     ev+1
        and     #$00FF
        cmp     z:wina
        bne     loop
        lda     ev+6
        and     #1
        beq     loop
        lda     #WD_FILL | (C_RED << 8)
        sta     blk
        lda     ev+2
        sec
        sbc     #3
        sta     blk+4
        lda     ev+4
        sec
        sbc     #3
        sta     blk+6
        lda     #7
        sta     blk+8
        sta     blk+10
        lda     z:wina
        jsr     draw
        bra     loop
@close: lda     ev+1
        and     #$00FF
        sys     SYS_WCLOSE
        dec     z:open
        bne     loop
        sys     SYS_WSSTOP
        exit    0

fail:   print   "wdemo: no window system\n"
        exit    1

; win_draw A with the block blk
draw:   ldx     #.loword(blk)
        ldy     #^blk
        sys     SYS_WDRAW
        rts

; op A (low) | colour (high) rectangle x, y, w, h (X, Y, kx, ky) in window wina..
rect:   sta     blk
        stx     blk+4
        sty     blk+6
        lda     z:kx
        sta     blk+8
        lda     z:ky
        sta     blk+10
        lda     z:cw
        jmp     draw

shapes: lda     z:wina
        sta     z:cw
        lda     #36                     ; colour bars
        sta     z:kx
        lda     #60
        sta     z:ky
        ldx     #8
        ldy     #8
        lda     #WD_FILL | (C_RED << 8)
        jsr     rect
        ldx     #50
        ldy     #8
        lda     #WD_FILL | (C_YELLOW << 8)
        jsr     rect
        ldx     #92
        ldy     #8
        lda     #WD_FILL | (C_GREEN << 8)
        jsr     rect
        ldx     #134
        ldy     #8
        lda     #WD_FILL | (C_SELECT << 8)
        jsr     rect
        ldx     #176
        ldy     #8
        lda     #WD_FILL | (C_ORANGE << 8)
        jsr     rect
        ldx     #218
        ldy     #8
        lda     #WD_FILL | ((16 + 36 * 5 + 2) << 8)
        jsr     rect
        lda     #240                    ; frames
        sta     z:kx
        lda     #40
        sta     z:ky
        ldx     #8
        ldy     #76
        lda     #WD_FRAME | (C_BLACK << 8)
        jsr     rect
        lda     #224
        sta     z:kx
        lda     #24
        sta     z:ky
        ldx     #16
        ldy     #84
        lda     #WD_FRAME | (C_DARK << 8)
        jsr     rect
        lda     #0                      ; a fan of lines from (130, 176)
        sta     z:i
@fan:   lda     #WD_LINE | (C_TITLE << 8)
        sta     blk
        lda     #130
        sta     blk+4
        lda     #176
        sta     blk+6
        lda     z:i
        sta     blk+8
        lda     #124
        sta     blk+10
        lda     z:wina
        jsr     draw
        lda     z:i
        clc
        adc     #20
        sta     z:i
        cmp     #261
        bcc     @fan
        rts

texts:  lda     z:winb
        sta     z:cw
        lda     #0
        sta     z:i
@l:     lda     z:i                     ; UI font lines, then fixed font lines
        asl     a
        tax
        lda     tlines,x
        beq     @out
        sta     blk+12
        lda     #^tl1
        sta     blk+14
        lda     #WD_TEXT | (C_BLACK << 8)
        sta     blk
        lda     #$FF                    ; transparent paper, UI font
        sta     blk+2
        lda     z:i
        cmp     #4
        bcc     :+
        lda     #$FF | ($01 << 8)       ; the fixed font, dark blue
        sta     blk+2
        lda     #WD_TEXT | (C_TITLE << 8)
        sta     blk
:       lda     #8
        sta     blk+4
        lda     z:i                     ; y = 8 + 16 * i
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #8
        sta     blk+6
        lda     z:winb
        jsr     draw
        inc     z:i
        bra     @l
@out:   lda     #WD_TEXT | (C_WHITE << 8)   ; white on red, the UI font
        sta     blk
        lda     #C_RED
        sta     blk+2
        lda     #8
        sta     blk+4
        lda     #146
        sta     blk+6
        lda     #.loword(tl9)
        sta     blk+12
        lda     #^tl9
        sta     blk+14
        lda     z:winb
        jmp     draw

palette:
        lda     z:winc
        sta     z:cw
        lda     #15
        sta     z:kx
        lda     #7
        sta     z:ky
        stz     z:i
@c:     lda     z:i                     ; colour i at (16 (i & 15), 8 (i >> 4))
        and     #$000F
        asl     a
        asl     a
        asl     a
        asl     a
        tax
        lda     z:i
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        asl     a
        asl     a
        asl     a
        tay
        lda     z:i
        xba
        ora     #WD_FILL
        jsr     rect
        inc     z:i
        lda     z:i
        cmp     #256
        bcc     @c
        rts

; ---- bench: figures on the console log, for each drawing mode ----
bench:  sys     SYS_WSSYNC
        print   "wdemo bench\n"
        stz     z:mode
@mode:  lda     z:mode
        asl     a
        tax
        lda     modes,x
        sta     z:cfg
        sys     SYS_WSCONFIG
        sta     z:t0
        lda     z:cfg
        and     #1
        bne     :+                      ; a blitter mode without a blitter: skip
        lda     z:t0
        jeq     @nextm
:       lda     z:mode
        asl     a
        tax
        lda     mnames,x
        tax
        ldy     #^mn0
        sys     SYS_PUTS
        jsr     onemode
@nextm: inc     z:mode
        lda     z:mode
        cmp     #3
        jcc     @mode
        lda     #0
        sys     SYS_WSCONFIG
        sys     SYS_WSSTOP
        exit    0

onemode:
        sys     SYS_WSREDRAW            ; 1. the whole screen
        sys     SYS_WSSYNC
        print   "  full repaint: "
        jsr     stat
        lda     z:winb                  ; 2. a window move step (8, 4), and back
        ldx     #208
        ldy     #114
        sys     SYS_WMOVE
        sys     SYS_WSSYNC
        print   "  move step (Text, 302x187): "
        jsr     stat
        lda     z:winb
        ldx     #200
        ldy     #110
        sys     SYS_WMOVE
        sys     SYS_WSSYNC
        lda     #WD_TEXT | (C_BLACK << 8)   ; 3. one 60-character text line, drawn 20
        sta     blk                         ; times, then shown
        lda     #C_BODY
        sta     blk+2
        lda     #4
        sta     blk+4
        lda     #120
        sta     blk+6
        lda     #.loword(tl60)
        sta     blk+12
        lda     #^tl60
        sta     blk+14
        sys     SYS_UPTIME
        sta     z:t0
        ldy     #20
:       phy
        lda     z:winb
        jsr     draw
        ply
        dey
        bne     :-
        sys     SYS_UPTIME
        sec
        sbc     z:t0
        sta     z:t0
        print   "  text line draw (60 characters, 20 times): "
        lda     z:t0
        jsr     put_dec
        print   " ms\n"
        sys     SYS_WSSYNC
        print   "  text line repaint: "
        jmp     stat

; print the last repaint time: "N us"
stat:   sys     SYS_WSSTATS
        stx     z:t0                    ; (A low 16 bits, X high)
        jsr     put_dec
        print   " us"
        lda     z:t0
        beq     :+
        print   " + "
        lda     z:t0
        jsr     put_dec
        print   " x 65536"
:       jmp     put_nl

        .segment "RODATA"
wa:     .word   16, 24, 260, 180
        .faraddr t_a
        .byte   0                       ; flags
wb:     .word   200, 110, 300, 170
        .faraddr t_b
        .byte   0
wc:     .word   360, 20, 256, 128
        .faraddr t_c
        .byte   0
t_a:    .byte   "Shapes", 0
t_b:    .byte   "Text", 0
t_c:    .byte   "Palette", 0
tlines: .addr   tl1, tl2, tl3, tl4, tl5, tl6, tl7, 0
tl1:    .byte   "Horizon window system, stage 1.", 0
tl2:    .byte   "The quick brown fox jumps over the lazy dog.", 0
tl3:    .byte   "ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789", 0
tl4:    .byte   "abcdefghijklmnopqrstuvwxyz !?.,:;()[]{}", 0
tl5:    .byte   "Fixed 8x12: for terminals.", 0
tl6:    .byte   "$ cd disks; ls -> 42 files", 0
tl7:    .byte   "0123456789 ABCDEF abcdef", 0
tl9:    .byte   " Click in Shapes. Keys close windows. ", 0
tl60:   .byte   "A sixty character line of text for the window system bench.", 0
modes:  .word   1, 0, 2                 ; ws_config: software, blitter (poll), blitter (interrupt)
mnames: .addr   mn0, mn1, mn2
mn0:    .byte   "software:", 10, 0
mn1:    .byte   "blitter, polling BUSY:", 10, 0
mn2:    .byte   "blitter, sleeping on its interrupt:", 10, 0

        .segment "CODE"
; ---- copy: a pattern of 10 x 6 cells and a diagonal, then the moves in cps ----
CW_     = 200
CH_     = 120
copytest:
        ptr     wcp
        sys     SYS_WOPEN
        sta     z:wina
        stz     z:ky
@y:     stz     z:kx
@x:     lda     z:kx                    ; cell (kx, ky): 20 x 20 at (20 kx, 20 ky)
        jsr     @m20
        sta     blk+4
        lda     z:ky
        jsr     @m20
        sta     blk+6
        lda     #20
        sta     blk+8
        sta     blk+10
        lda     z:kx                    ; colour 16 + (7 kx + 13 ky) mod 128
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:kx
        sta     z:t0
        lda     z:ky
        asl     a
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:ky
        sec
        sbc     z:ky
        sec
        sbc     z:ky
        clc
        adc     z:t0
        and     #$7F
        clc
        adc     #16
        xba
        ora     #WD_FILL
        sta     blk
        lda     z:wina
        jsr     draw
        inc     z:kx
        lda     z:kx
        cmp     #10
        bne     @x
        inc     z:ky
        lda     z:ky
        cmp     #6
        bne     @y
        lda     #WD_LINE | (C_BLACK << 8)
        sta     blk
        stz     blk+4
        stz     blk+6
        lda     #CW_ - 1
        sta     blk+8
        lda     #CH_ - 1
        sta     blk+10
        lda     z:wina
        jsr     draw
        ldx     #0                      ; the moves: {x, y, w, h, to x, to y}
@c:     lda     cps,x
        cmp     #$7FFF
        beq     @wait
        sta     blk+4
        lda     cps+2,x
        sta     blk+6
        lda     cps+4,x
        sta     blk+8
        lda     cps+6,x
        sta     blk+10
        lda     cps+8,x
        sta     blk+1                   ; (c1 | c2 << 8: to x)
        lda     cps+10,x
        sta     blk+12                  ; (the pointer's low word: to y)
        lda     #WD_COPY
        sep     #$20                    ; (the op byte only: c1 is set)
        sta     blk
        rep     #$20
        phx
        lda     z:wina
        jsr     draw
        plx
        txa
        clc
        adc     #12
        tax
        bra     @c
@wait:  lda     #0
        ptr     ev
        sys     SYS_WEVENT
        bcs     @wait
        lda     ev
        and     #$00FF
        cmp     #WE_KEY
        bne     @wait
        lda     ev+4                    ; (a key down)
        and     #$0100
        beq     @wait
        sys     SYS_WSSTOP
        exit    0
@m20:   asl     a                       ; A * 20
        asl     a
        sta     z:t0
        asl     a
        asl     a
        clc
        adc     z:t0
        rts
        .segment "RODATA"
wdr:    .word   60, 40, 240, 140
        .faraddr tdr
        .byte   WF_RESIZE
tdr:    .byte   "Draw", 0
wgeo:   .word   200, 120, 300, 180              ; (SYS_WGEOM: x, y, content w, h)
; the draw ops: {op | c1 << 8, c2 | font << 8, x, y, w, h, ptr (low word), stride}
dops:   .word   WD_EXPAND | (C_RED << 8), C_YELLOW, 8, 8, 32, 16, dbm, 4       ; opaque
        .word   WD_EXPAND | (C_BLACK << 8), $FF, 48, 8, 32, 16, dbm, 0         ; transparent (stride 0: 4)
        .word   WD_EXPAND | (C_TITLE << 8), C_WHITE | (3 << 8), 88, 8, 21, 12, dbm, 4 ; from bit 3
        .word   WD_EXPAND | (C_GREEN << 8), $FF, $FFF6, 30, 32, 16, dbm, 4    ; cut at the left
        .word   WD_EXPAND | (C_RED << 8), C_WHITE, 220, 120, 32, 16, dbm, 4   ; cut at the right, bottom
        .word   WD_KSBLIT | (0 << 8), $FF, 30, 50, 16, 16, dimg, 32            ; keyed, stride 32
        .word   WD_KSBLIT | (0 << 8), $FF, 50, 50, 16, 16, dimg + 16, 32       ; its right half
        .word   WD_KSBLIT | (0 << 8), $FF, 230, 70, 32, 16, dimg, 0            ; cut at the right (stride 0: w)
        .word   WD_KSBLIT | (0 << 8), $FF, 80, $FFFA, 32, 16, dimg, 32         ; cut at the top
        .word   WD_EXPAND | (C_SELECT << 8), C_BODY, 120, 50, 64, 16, dbm, 4    ; wider than a row: 2 rows of bits
        .word   0
dbm:
        .byte   $FF, $FF, $FF, $FF
        .byte   $82, $00, $08, $01
        .byte   $84, $00, $0C, $01
        .byte   $88, $00, $0E, $01
        .byte   $90, $00, $0F, $01
        .byte   $A0, $00, $0F, $81
        .byte   $8F, $FF, $FF, $C1
        .byte   $8F, $FF, $FF, $F1
        .byte   $8F, $FF, $FF, $F1
        .byte   $8F, $FF, $FF, $C1
        .byte   $88, $00, $0F, $81
        .byte   $90, $00, $0F, $01
        .byte   $A0, $00, $0E, $01
        .byte   $80, $80, $0C, $01
        .byte   $81, $00, $08, $01
        .byte   $FF, $FF, $FF, $FF
dimg:
        .byte   $FF, $FF, $FF, $FF, $FF, $FF, $58, $59, $5A, $5B, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $C8, $C9, $C4, $C5, $FF, $FF, $FF, $FF, $FF, $FF
        .byte   $FF, $FF, $FF, $FF, $5C, $5D, $58, $59, $5A, $5B, $5C, $5D, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $C6, $C7, $C8, $C9, $C4, $C5, $C6, $C7, $FF, $FF, $FF, $FF
        .byte   $FF, $FF, $FF, $5B, $5C, $5D, $58, $59, $5A, $5B, $5C, $5D, $58, $FF, $FF, $FF, $FF, $FF, $FF, $C5, $C6, $C7, $C8, $C9, $C4, $C5, $C6, $C7, $C8, $FF, $FF, $FF
        .byte   $FF, $FF, $60, $61, $62, $63, $5E, $5F, $60, $61, $62, $63, $5E, $5F, $FF, $FF, $FF, $FF, $CA, $CB, $CC, $CD, $CE, $CF, $CA, $CB, $CC, $CD, $CE, $CF, $FF, $FF
        .byte   $FF, $5F, $60, $61, $62, $63, $5E, $5F, $60, $61, $62, $63, $5E, $5F, $60, $FF, $FF, $CF, $CA, $CB, $CC, $CD, $CE, $CF, $CA, $CB, $CC, $CD, $CE, $CF, $CA, $FF
        .byte   $FF, $5F, $60, $61, $62, $63, $FF, $FF, $FF, $FF, $62, $63, $5E, $5F, $60, $FF, $FF, $CF, $CA, $CB, $CC, $CD, $FF, $FF, $FF, $FF, $CC, $CD, $CE, $CF, $CA, $FF
        .byte   $64, $65, $66, $67, $68, $FF, $FF, $FF, $FF, $FF, $FF, $69, $64, $65, $66, $67, $D4, $D5, $D0, $D1, $D2, $FF, $FF, $FF, $FF, $FF, $FF, $D3, $D4, $D5, $D0, $D1
        .byte   $64, $65, $66, $67, $68, $FF, $FF, $FF, $FF, $FF, $FF, $69, $64, $65, $66, $67, $D4, $D5, $D0, $D1, $D2, $FF, $FF, $FF, $FF, $FF, $FF, $D3, $D4, $D5, $D0, $D1
        .byte   $64, $65, $66, $67, $68, $FF, $FF, $FF, $FF, $FF, $FF, $69, $64, $65, $66, $67, $D4, $D5, $D0, $D1, $D2, $FF, $FF, $FF, $FF, $FF, $FF, $D3, $D4, $D5, $D0, $D1
        .byte   $6A, $6B, $6C, $6D, $6E, $FF, $FF, $FF, $FF, $FF, $FF, $6F, $6A, $6B, $6C, $6D, $DA, $DB, $D6, $D7, $D8, $FF, $FF, $FF, $FF, $FF, $FF, $D9, $DA, $DB, $D6, $D7
        .byte   $FF, $6B, $6C, $6D, $6E, $6F, $FF, $FF, $FF, $FF, $6E, $6F, $6A, $6B, $6C, $FF, $FF, $DB, $D6, $D7, $D8, $D9, $FF, $FF, $FF, $FF, $D8, $D9, $DA, $DB, $D6, $FF
        .byte   $FF, $6B, $6C, $6D, $6E, $6F, $6A, $6B, $6C, $6D, $6E, $6F, $6A, $6B, $6C, $FF, $FF, $DB, $D6, $D7, $D8, $D9, $DA, $DB, $D6, $D7, $D8, $D9, $DA, $DB, $D6, $FF
        .byte   $FF, $FF, $72, $73, $74, $75, $70, $71, $72, $73, $74, $75, $70, $71, $FF, $FF, $FF, $FF, $DC, $DD, $DE, $DF, $E0, $E1, $DC, $DD, $DE, $DF, $E0, $E1, $FF, $FF
        .byte   $FF, $FF, $FF, $73, $74, $75, $70, $71, $72, $73, $74, $75, $70, $FF, $FF, $FF, $FF, $FF, $FF, $DD, $DE, $DF, $E0, $E1, $DC, $DD, $DE, $DF, $E0, $FF, $FF, $FF
        .byte   $FF, $FF, $FF, $FF, $74, $75, $70, $71, $72, $73, $74, $75, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $DE, $DF, $E0, $E1, $DC, $DD, $DE, $DF, $FF, $FF, $FF, $FF
        .byte   $FF, $FF, $FF, $FF, $FF, $FF, $76, $77, $78, $79, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $E6, $E7, $E2, $E3, $FF, $FF, $FF, $FF, $FF, $FF
wcp:    .word   100, 100, CW_, CH_
        .faraddr tcp
        .byte   0
tcp:    .byte   "Copy", 0
cps:    .word   10, 10, 60, 40, 17, 10          ; right and down, overlapping
        .word   100, 5, 50, 30, 107, 5          ; right by 7, the same lines
        .word   120, 50, 60, 30, 115, 50        ; left by 5, the same lines
        .word   20, 60, 70, 50, 23, 51          ; up by 9, right by 3
        .word   30, 20, 50, 40, 28, 24          ; down by 4, left by 2
        .word   $FFF6, 90, 40, 20, 150, 95      ; the source cut at the left
        .word   170, 0, 40, 30, 180, $FFF6      ; the destination cut at the top, right
        .word   $7FFF

; ---- wdemo draw (0.14): WD_EXPAND, WD_KSBLIT, SYS_WGEOM ----
drawtest:
        ptr     wdr
        sys     SYS_WOPEN
        sta     z:wina
        jsr     drawops
@wait:  lda     #0
        ptr     ev
        sys     SYS_WEVENT
        bcs     @wait
        lda     ev
        and     #$00FF
        cmp     #WE_KEY
        bne     @wait
        lda     ev+4                    ; (a key down)
        and     #$0100
        beq     @wait
        lda     ev+2
        cmp     #$0A                    ; "g": moved and resized, drawn again
        bne     @end
        lda     z:wina
        ptr     wgeo
        sys     SYS_WGEOM
        jsr     drawops
        bra     @wait
@end:   sys     SYS_WSSTOP
        exit    0

; the test pattern: a checker background, then the ops (see the table dops)
drawops:
        lda     #WD_DITHER | (C_LIGHT << 8)
        sta     blk
        lda     #C_MID
        sta     blk+2
        stz     blk+4
        stz     blk+6
        lda     #400
        sta     blk+8
        sta     blk+10
        lda     z:wina
        jsr     draw
        ldx     #0
@op:    lda     dops,x                  ; {op | c1 << 8, c2 | font << 8, x, y, w, h, ptr, stride}
        beq     @out
        sta     blk
        lda     dops+2,x
        sta     blk+2
        lda     dops+4,x
        sta     blk+4
        lda     dops+6,x
        sta     blk+6
        lda     dops+8,x
        sta     blk+8
        lda     dops+10,x
        sta     blk+10
        lda     dops+12,x
        sta     blk+12
        lda     #^dbm
        sta     blk+14
        lda     dops+14,x
        sta     blk+15
        phx
        lda     z:wina
        jsr     draw
        plx
        txa
        clc
        adc     #16
        tax
        bra     @op
@out:   rts

; ---- wdemo menu: menu item states and shortcuts ----
        .segment "CODE"
menutest:
        ptr     wm
        sys     SYS_WOPEN
        jcs     fail
        sta     z:wina
        ptr     mmenus
        sys     SYS_WMENU
        lda     #WD_TEXT | (C_BLACK << 8)
        sta     blk
        lda     #$FF
        sta     blk+2
        lda     #10
        sta     blk+4
        sta     blk+6
        lda     #.loword(tmhelp)
        sta     blk+12
        lda     #^tmhelp
        sta     blk+14
        lda     z:wina
        jsr     draw
        lda     #MS_CHECK               ; Grid checked, Print dimmed
        sta     z:kx
        lda     #MS_DIM
        sta     z:ky
@ev:    lda     #0
        ptr     ev
        sys     SYS_WEVENT
        bcs     @ev
        lda     ev
        and     #$00FF
        cmp     #WE_CLOSE
        beq     @quit
        cmp     #WE_MENU
        bne     @ev
        lda     ev+4                    ; item | menu << 8
        xba
        ora     ev+2
        xba
        cmp     #$0004                  ; Options > Quit
        beq     @quit
        cmp     #$0002
        bcs     :+
        tax                             ; Options > Grid, Snap: toggle the check mark
        lda     z:kx
        eor     #MS_CHECK
        cpx     #0
        beq     @set
        lda     z:mode
        eor     #MS_CHECK
        sta     z:mode
        ldy     z:mode
        bra     @st
@set:   sta     z:kx
        tay
@st:    txa
        xba                             ; X = menu 0 | item << 8
        tax
        bra     @ms
:       cmp     #$0100                  ; Window > Enable Print: Print dimmed / enabled
        bne     @ev
        lda     z:ky
        eor     #MS_DIM
        sta     z:ky
        tay
        ldx     #3 << 8
@ms:    lda     z:wina
        sys     SYS_WMSTATE
        bra     @ev
@quit:  lda     z:wina
        sys     SYS_WCLOSE
        sys     SYS_WSSTOP              ; (in the Desktop: not ours, refused)
        exit    0
        .segment "RODATA"
wm:     .word   180, 120, 280, 90
        .faraddr tmt
        .byte   0
tmt:    .byte   "Menus", 0
tmhelp: .byte   "F10, Alt or Alt+O, W: the menus", 0
mmenus: .byte   "Options", 0
        .byte   MS_STATE | MS_CHECK, "Grid", 9, "Ctrl+G", 0
        .byte   MS_STATE, "Snap", 9, "Ctrl+B", 0
        .byte   "-", 0
        .byte   MS_STATE | MS_DIM, "Print", 9, "Ctrl+P", 0
        .byte   "Quit", 9, "Ctrl+Q", 0
        .byte   0
        .byte   "Window", 0
        .byte   "Enable Print", 0
        .byte   0
        .byte   0

        .segment "BSS"
blk:    .res    18
ev:     .res    8

        .segment "ZEROPAGE"
alen:   .res    2
wina:   .res    2
winb:   .res    2
winc:   .res    2
open:   .res    2
cw:     .res    2
kx:     .res    2
ky:     .res    2
i:      .res    2
t0:     .res    2
mode:   .res    2
cfg:    .res    2
