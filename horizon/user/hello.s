; HELLO - prints a greeting with its task id, and its argument string if it has one.
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  sta     z:alen
        jsr     args_init
        print   "Hello from task "
        sys     SYS_GETPID
        jsr     put_dec
        print   ", Horizon user mode"
        lda     z:alen
        beq     :+
        print   ", args \""
        ldx     z:u_p
        ldy     #0
        jsr     out_str
        lda     #'"'
        jsr     out_char
:       jsr     put_nl
        exit    0

        .segment "ZEROPAGE"
alen:   .res    2
