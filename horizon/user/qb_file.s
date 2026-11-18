; qb_file.s - Quabricks' high scores and settings (included by quabrick.s).
; /BIN/QUABRICK.DAT, 188 bytes: "QBK1", u8 sound on, u8 mode, u8 starting level, u8 0, then
; the two tables (Marathon, Time Attack), 5 entries each, best first, 18 bytes an entry:
; name (10 characters, zero-terminated in 11 bytes), u32 score, u8 level, u16 lines (an empty
; entry: score 0). Read at the start (missing or not ours: empty tables, sound on), written
; whenever a table or a setting changes; a card that cannot be written is fine.

HSN      = 5
HSZ      = 18
HS_SCORE = 11
HS_LEVEL = 15
HS_LINES = 16
NAMEMAX  = 10
DATLEN   = 8 + 2 * HSN * HSZ

loaddat:
        lda     #1
        sta     sndon
        stz     mode
        lda     #1
        sta     startlv
        lda     #O_READ
        ptr     p_dat
        qsys    SYS_OPEN
        bcs     @out
        sta     z:g0
        jsr     iofile
        qsys    SYS_READ
        php
        pha
        lda     z:g0
        qsys    SYS_CLOSE
        pla
        plp
        bcs     @out
        cmp     #DATLEN
        bne     @out
        lda     fbuf
        cmp     #$4251                  ; "QB"
        bne     @out
        lda     fbuf+2
        cmp     #$314B                  ; "K1"
        bne     @out
        lda     fbuf+4
        and     #1
        sta     sndon
        lda     fbuf+5
        and     #1
        sta     mode
        lda     fbuf+6
        and     #$00FF
        beq     :+
        cmp     #MAXSTART + 1
        bcs     :+
        sta     startlv
:       ldx     #2 * HSN * HSZ - 2
:       lda     fbuf+8,x
        sta     hs_tab,x
        dex
        dex
        bpl     :-
@out:   rts

savedat:
        lda     #$4251
        sta     fbuf
        lda     #$314B
        sta     fbuf+2
        lda     sndon
        sep     #$20
        .a8
        sta     fbuf+4
        lda     mode
        sta     fbuf+5
        lda     startlv
        sta     fbuf+6
        stz     fbuf+7
        rep     #$20
        .a16
        ldx     #2 * HSN * HSZ - 2
:       lda     hs_tab,x
        sta     fbuf+8,x
        dex
        dex
        bpl     :-
        lda     #O_CREATE
        ptr     p_dat
        qsys    SYS_OPEN
        bcs     @out
        sta     z:g0
        jsr     iofile
        qsys    SYS_WRITE
        lda     z:g0
        qsys    SYS_CLOSE
@out:   rts
; the read / write block: handle g0, fbuf, DATLEN -> X, Y
iofile: lda     z:g0
        sep     #$20
        .a8
        sta     iob
        rep     #$20
        .a16
        lda     #.loword(fbuf)
        sta     iob+1
        lda     pbank
        sep     #$20
        .a8
        sta     iob+3
        rep     #$20
        .a16
        lda     #DATLEN
        sta     iob+4
        ptr     iob
        rts

; X = entry g7 of the table of vmode
hs_entry:
        lda     vmode
        asl     a
        asl     a
        adc     vmode                   ; mode * 5
        clc
        adc     z:g7
        sta     z:g0
        asl     a                       ; * 18 = * 16 + * 2
        asl     a
        asl     a
        asl     a
        sta     z:g1
        lda     z:g0
        asl     a
        clc
        adc     z:g1
        adc     #.loword(hs_tab)
        tax
        rts

; does the score enter mode's table? -> C set (and g7 = its place)
hs_qualifies:
        lda     score
        ora     score+2
        beq     @no
        lda     mode
        sta     vmode
        stz     z:g7
:       jsr     hs_entry
        lda     score+2                 ; score > the entry's?
        cmp     a:HS_SCORE+2,x
        bcc     @n
        bne     @yes
        lda     score
        cmp     a:HS_SCORE,x
        beq     @n
        bcs     @yes
@n:     inc     z:g7
        lda     z:g7
        cmp     #HSN
        bcc     :-
@no:    clc
        rts
@yes:   sec
        rts

; the score, level, lines and nbuf into mode's table at its place -> hrank
hs_insert:
        jsr     hs_qualifies
        jcc     @out
        lda     z:g7
        sta     hrank
        lda     #HSN - 1                ; the rest down by one
        sta     z:g7
@sh:    lda     z:g7
        cmp     hrank
        beq     @put
        bcc     @put
        jsr     hs_entry                ; entry g7 = entry g7 - 1
        txa
        sec
        sbc     #HSZ
        tay
        lda     #HSZ / 2
        sta     z:g1
:       lda     a:0,y
        sta     a:0,x
        inx
        inx
        iny
        iny
        dec     z:g1
        bne     :-
        dec     z:g7
        bra     @sh
@put:   lda     hrank
        sta     z:g7
        jsr     hs_entry
        stx     z:g0
        ldy     #0                      ; the name ("---" when none)
        lda     nlen
        bne     :+
        lda     #'-' | ('-' << 8)
        sta     nbuf
        sta     nbuf+1
        stz     nbuf+3
:       lda     nbuf,y
        sep     #$20
        .a8
        sta     (g0),y
        rep     #$20
        .a16
        iny
        cpy     #NAMEMAX + 1
        bcc     :-
        ldx     z:g0
        sep     #$20
        .a8
        stz     a:NAMEMAX,x
        rep     #$20
        .a16
        lda     score
        sta     a:HS_SCORE,x
        lda     score+2
        sta     a:HS_SCORE+2,x
        lda     level
        sep     #$20
        .a8
        sta     a:HS_LEVEL,x
        rep     #$20
        .a16
        lda     lines
        sta     a:HS_LINES,x
@out:   rts
