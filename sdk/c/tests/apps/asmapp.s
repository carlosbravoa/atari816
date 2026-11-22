; ASMAPP - (Horizon 0.29) the apps test's assembly program (tests/run.py "apps"): HZ_NEEDS
; (it needs Horizon 0.29 and Lau, the sample player), then one line on the console.
; Assembled with ca65 -I horizon/user, linked with ulib.o; packed with hzapp.py.
        .include "horizon.inc"
        .include "needs.inc"
        .segment "CODE"
        .a16
        .i16
start:  HZ_NEEDS "ASMAPP", 0, 29, 0, NEED_LAU, 0
        print   "asmapp: running\n"
        exit    0
