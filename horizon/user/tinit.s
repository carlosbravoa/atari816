; TINIT - INIT of the test SD card: runs /SYSTEM/TESTS/SELFTEST.PRG, waits for it and exits, so the
; run ends with "[halt] no tasks".
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  stz     z:u_arg
        stz     z:u_arg+2
        ptr     path
        lda     #1
        jsr     spawn
        jcs     @err
        sys     SYS_WAIT
        pha
        print   "tinit: selftest exit "
        pla
        jsr     put_hex16
        jsr     put_nl
        exit    0
@err:   pha
        print   "tinit: cannot start selftest, error "
        pla
        jsr     put_hex8
        jsr     put_nl
        exit    1

        .segment "RODATA"
path:   .byte   "/SYSTEM/TESTS/SELFTEST.PRG", 0
