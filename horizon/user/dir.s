; DIR - lists / with READDIR, 48 bytes at a time (continuing with skip).
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  stz     z:skip
        print   "dir /\n"
@call:  lda     #.loword(root)          ; block: path, buffer, length, skip
        sta     z:blk
        lda     #.loword(buf)
        sta     z:blk+3
        sep     #$20
        .a8
        lda     #^root
        sta     z:blk+2
        lda     #^buf
        sta     z:blk+5
        rep     #$20
        .a16
        lda     #48
        sta     z:blk+6
        lda     z:skip
        sta     z:blk+8
        ldx     #blk
        ldy     #0
        sys     SYS_READDIR
        bcc     *+5
        jmp     @err
        cmp     #0
        beq     @done
        sta     z:n
        clc
        adc     z:skip
        sta     z:skip
        ldx     #0                      ; entries: u32 size, u8 attr, u8 len, name
@ent:   stx     z:pos
        print   "  "
        ldx     z:pos
        lda     buf+5,x
        and     #$00FF
        sta     z:len
        ldy     #0
:       lda     buf+6,x
        phx
        phy
        jsr     put_char
        ply
        plx
        inx
        iny
        cpy     z:len
        bne     :-
        ldx     z:pos
        lda     buf+4,x
        and     #$10
        beq     :+
        print   " <DIR>\n"
        bra     @next
:       print   " "
        ldx     z:pos
        lda     buf,x
        jsr     put_dec
        jsr     put_nl
@next:  lda     z:pos
        clc
        adc     #6
        adc     z:len
        tax
        dec     z:n
        bne     @ent
        brl     @call
@done:  exit    0
@err:   pha
        print   "dir: error $"
        pla
        jsr     put_hex8
        jsr     put_nl
        exit    1

        .segment "RODATA"
root:   .byte   "/", 0
        .segment "BSS"
buf:    .res    48
        .segment "ZEROPAGE"
blk:    .res    10
skip:   .res    2
n:      .res    2
pos:    .res    2
len:    .res    2
