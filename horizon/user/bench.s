; BENCH - console speed: clears the screen, writes 40 lines of 64 characters (no
; scrolling), then 200 more lines (scrolling all the way), one puts per line, and prints
; characters per second for each part (uptime, 10 ms resolution).
; "bench FILE": copies FILE to the console like cat (63-byte reads) and times that.
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  cmp     #0
        beq     :+
        jmp     file
:       ldx     #0                      ; a 64-character line + LF
:       txa
        and     #$3F
        clc
        adc     #' ' + 1
        sta     line,x
        inx
        cpx     #64
        bne     :-
        lda     #10                     ; LF, terminator
        sta     line + 64
        lda     #12
        jsr     out_char
        jsr     out_flush
        lda     #40
        jsr     burst
        sta     z:t1
        lda     #200
        jsr     burst
        sta     z:t2
        print   "bench: plain "
        lda     #40 * 65
        ldx     z:t1
        jsr     rate
        print   " chars/s, scrolling "
        lda     #200 * 65
        ldx     z:t2
        jsr     rate
        print   " chars/s\n"
        exit    0

; write A lines; returns A = milliseconds taken
burst:  sta     z:n
        sys     SYS_UPTIME
        sta     z:t0
:       ldx     #.loword(line)
        ldy     #^line
        sys     SYS_PUTS
        dec     z:n
        bne     :-
        sys     SYS_UPTIME
        sec
        sbc     z:t0
        rts

; print A characters / X ms as characters per second (A * 100 / (X / 10))
rate:   sta     z:n
        stz     z:r
        stz     z:r + 2
        txa
        jsr     div10                   ; centiseconds
        bne     :+
        inc     a
:       sta     z:t0
        lda     #0                      ; q = n * 100 / t0, by repeated subtraction of t0
        sta     z:q                     ; from n*100 (32-bit n*100 kept as 16x16 loop)
        ldx     #100
@mul:   lda     z:r
        clc
        adc     z:n
        sta     z:r
        bcc     :+
        inc     z:r + 2
:       dex
        bne     @mul
@div:   lda     z:r + 2                 ; r >= t0 ?
        bne     @sub
        lda     z:r
        cmp     z:t0
        bcc     @out
@sub:   lda     z:r
        sec
        sbc     z:t0
        sta     z:r
        bcs     :+
        dec     z:r + 2
:       inc     z:q
        bra     @div
@out:   lda     z:q
        jmp     put_dec

file:   stx     z:fpath
        lda     #0
        sys     SYS_OPEN                ; X = offset, Y = 0: the argument string
        bcc     :+
        print   "bench: cannot open\n"
        exit    1
:       sta     blk
        lda     #.loword(buf)
        sta     blk + 1
        sep     #$20
        .a8
        lda     #^buf
        sta     blk + 3
        rep     #$20
        .a16
        lda     #63
        sta     blk + 4
        stz     z:total
        sys     SYS_UPTIME
        sta     z:t1
@rd:    ldx     #.loword(blk)
        ldy     #^blk
        sys     SYS_READ
        bcs     @eof
        cmp     #0
        beq     @eof
        tax
        clc
        adc     z:total
        sta     z:total
        sep     #$20
        .a8
        stz     buf,x
        rep     #$20
        .a16
        ldx     #.loword(buf)
        ldy     #^buf
        sys     SYS_PUTS
        bra     @rd
@eof:   sys     SYS_UPTIME
        sec
        sbc     z:t1
        sta     z:t2
        lda     blk
        and     #$00FF
        sys     SYS_CLOSE
        print   "bench: "
        lda     z:total
        jsr     put_dec
        print   " bytes, "
        lda     z:total
        ldx     z:t2
        jsr     rate
        print   " chars/s\n"
        exit    0

        .segment "BSS"
blk:    .res    6
buf:    .res    64
line:   .res    66
        .segment "ZEROPAGE"
n:      .res    2
t0:     .res    2
t1:     .res    2
t2:     .res    2
q:      .res    2
fpath:  .res    2
total:  .res    2
r:      .res    4
