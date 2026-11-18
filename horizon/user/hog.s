; HOG - fills memory deterministically, for the out-of-memory tests: "hog [n]" allocates
; banks until only n (default 0) are left free, says so, and holds them until it is
; killed (or ctrl-C in the foreground). Run it in the background: "hog 2 &".
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  jsr     args_init
        stz     z:keep
        jsr     parse_dec
        bcs     :+
        sta     z:keep
:       stz     z:n
@alloc: sys     SYS_MINFO
        cmp     z:keep
        beq     @full
        bcc     @full
        sys     SYS_BALLOC
        bcs     @full
        inc     z:n
        bra     @alloc
@full:  print   "hog: holding "
        lda     z:n
        jsr     put_dec
        print   " banks, "
        sys     SYS_MINFO
        jsr     put_dec
        print   " free\n"
        jsr     out_flush
:       lda     #10000
        sys     SYS_SLEEP
        bra     :-

        .segment "ZEROPAGE"
keep:   .res    2
n:      .res    2
