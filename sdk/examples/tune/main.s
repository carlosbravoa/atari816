; Tune - play a module with the replayer library (Horizon 0.26, Atari816): TUNE FILE.MOD
; The module is read into one bank (up to 64 KB), the music timer ticks a port, mp_tick plays.
        .include "horizon.inc"
        .include "modplay.inc"
        .segment "CODE"
        .a16
        .i16
start:  jsr     args_init
        ldx     #.loword(path)
        ldy     #^path
        lda     #128
        jsr     next_arg                ; the file's name
        sys     SYS_BALLOC              ; a bank for the module (Lau reads it from there)
        sta     mp_mod+2
        sta     rblk+3
        ldx     #.loword(path)
        ldy     #^path
        lda     #O_READ
        sys     SYS_OPEN
        bcs     fail
        sta     rblk
        ptr     rblk
        sys     SYS_READ                ; read it whole: A = its length
        sta     mp_mlen
        lda     rblk
        sys     SYS_CLOSE
        jsr     mp_open                 ; a ProTracker module?
        bcs     fail
        sys     SYS_PCREATE             ; the port the music timer ticks
        sta     port
        lda     #0
        jsr     mp_play                 ; from order 0: its first tick has run
tempo:  lda     port                    ; every mp_tickus microseconds a message
        ldx     mp_tickus
        ldy     mp_tickus+2
        sys     SYS_STIMER
        bcs     fail                    ; (ENODEV: no Lau)
wait:   lda     port
        ptr     msg
        sys     SYS_RECV                ; the next tick
        jsr     mp_tick
        bit     #MPF_END
        bne     done
        bit     #MPF_TEMPO
        bne     tempo
        bra     wait
done:   print   "tune: the end\n"
        exit    0
fail:   print   "tune: cannot play it\n"
        exit    1
rblk:   .byte   0                       ; read: handle, u24 buffer (the bank, offset 0),
        .faraddr 0                      ; u16 length
        .word   $FFFF
        .segment "BSS"
path:   .res    128
port:   .res    2
msg:    .res    16
