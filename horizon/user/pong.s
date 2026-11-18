; PONG - started by PING with PING's port number as its argument string. Creates its own port, says hello, then
; answers every ping with value * 2 until it gets 'Q'.
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  jsr     args_init
        jsr     parse_dec
        sta     z:peer
        sys     SYS_PCREATE
        jcs     @bad
        sta     z:myport
        lda     #'H'
        sta     msg
        lda     z:myport
        sta     msg+2
        jsr     reply
@loop:  lda     z:myport
        ptr     msg
        sys     SYS_RECV
        jcs     @bad
        lda     msg
        cmp     #'Q'
        beq     @quit
        lda     #'R'
        sta     msg
        lda     msg+2
        asl     a
        sta     msg+2
        jsr     reply
        bra     @loop
@quit:  exit    0
@bad:   exit    1

reply:  lda     z:peer
        ptr     msg
        sys     SYS_SEND
        rts

        .segment "BSS"
msg:    .res    16
        .segment "ZEROPAGE"
myport: .res    2
peer:   .res    2
