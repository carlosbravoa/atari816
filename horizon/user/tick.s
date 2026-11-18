; TICK - sleeps 50 ms three times and prints each wake-up (with SPIN running at the same
; priority, this only works if SPIN is preempted).
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  sys     SYS_UPTIME
        sta     z:t0
        lda     #1
        sta     z:n
@loop:  lda     #50
        sys     SYS_SLEEP
        print   "tick "
        lda     z:n
        jsr     put_dec
        jsr     put_nl
        inc     z:n
        lda     z:n
        cmp     #4
        bcc     @loop
        sys     SYS_UPTIME              ; at least 150 ms by the clock, and not 1 s
        sec
        sbc     z:t0
        cmp     #150
        jcc     @bad
        cmp     #1000
        jcs     @bad
        print   "tick: uptime agrees\n"
        exit    0
@bad:   print   "tick: uptime WRONG\n"
        exit    1

        .segment "ZEROPAGE"
n:      .res    2
t0:     .res    2
