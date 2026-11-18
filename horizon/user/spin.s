; SPIN - a CPU hog: about 400 ms of pure computation, no syscall in between.
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  print   "spin: start\n"
        lda     #18
        sta     z:outer
@o:     ldx     #0
@i:     dex
        bne     @i
        dec     z:outer
        bne     @o
        print   "spin: done\n"
        exit    0

        .segment "ZEROPAGE"
outer:  .res    2
