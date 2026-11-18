; COUNT - argument: a letter. Prints "count <letter> <n>" five times, sleeping 30 ms
; between lines. Two instances at once interleave their lines.
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  jsr     args_init
        lda     [u_p]
        and     #$00FF
        bne     :+
        lda     #'?'
:       sta     z:letter
        lda     #1
        sta     z:n
@loop:  print   "count "
        lda     z:letter
        jsr     put_char
        lda     #' '
        jsr     put_char
        lda     z:n
        jsr     put_dec
        jsr     put_nl
        lda     #30
        sys     SYS_SLEEP
        inc     z:n
        lda     z:n
        cmp     #6
        bcc     @loop
        exit    0

        .segment "ZEROPAGE"
letter: .res    2
n:      .res    2
