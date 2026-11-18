; MOUSE - prints the pointer position and buttons for every mouse event, and wheel
; movements, until a key is pressed.
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  sys     SYS_ICLAIM              ; ours, or lent by the shell
        print   "mouse: move it; any key ends\n"
@loop:  sys     SYS_IREAD
        jcs     @end
        cmp     #$0200
        jeq     @wheel
        cmp     #$0100
        jcc     @key
        and     #$0007
        sta     z:btn
        stx     z:px
        sty     z:py
        print   "mouse x "
        lda     z:px
        jsr     put_dec
        print   " y "
        lda     z:py
        jsr     put_dec
        print   " buttons "
        lda     z:btn
        jsr     put_dec
        jsr     put_nl
        brl     @loop
@wheel: stx     z:px
        print   "wheel "
        lda     z:px
        bpl     :+
        pha
        lda     #'-'
        jsr     out_char
        pla
        eor     #$FFFF
        inc     a
:       jsr     put_dec
        jsr     put_nl
        brl     @loop
@key:   cpx     #$0100                  ; key down ends it
        jcc     @loop
@end:   exit    0

        .segment "ZEROPAGE"
btn:    .res    2
px:     .res    2
py:     .res    2
