; CAT - prints /README.TXT through open, read (40-byte chunks) and close; then shows the
; error for a file that does not exist.
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  ptr     path
        lda     #O_READ
        sys     SYS_OPEN
        jcs     err
        sta     z:blk                   ; block: handle, buffer (u24), length
        lda     #.loword(buf)
        sta     z:blk+1
        sep     #$20
        .a8
        lda     #^buf
        sta     z:blk+3
        rep     #$20
        .a16
        lda     #40
        sta     z:blk+4
@more:  ldx     #blk                    ; the block is on the direct page = window, bank 0
        ldy     #0
        sys     SYS_READ
        jcs     err
        cmp     #0
        beq     @eof
        tax
        sep     #$20
        .a8
        stz     buf,x
        rep     #$20
        .a16
        ptr     buf
        jsr     out_str
        bra     @more
@eof:   lda     z:blk
        and     #$00FF
        sys     SYS_CLOSE
        jcs     err
        ptr     nopath
        lda     #O_READ
        sys     SYS_OPEN
        bcc     err0
        pha
        print   "cat: /NOPE.TXT error $"
        pla
        jsr     put_hex8
        jsr     put_nl
        exit    0
err0:   lda     #0
err:    pha
        print   "cat: error $"
        pla
        jsr     put_hex8
        jsr     put_nl
        exit    1

        .segment "RODATA"
path:   .byte   "/README.TXT", 0
nopath: .byte   "/NOPE.TXT", 0
        .segment "BSS"
buf:    .res    41
        .segment "ZEROPAGE"
blk:    .res    6
