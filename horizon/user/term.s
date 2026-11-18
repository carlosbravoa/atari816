; TERM - a terminal window running the shell (/BIN/TERM.PRG; the shell is /SYSTEM/SH.PRG). The window is a kernel
; terminal (WF_TERM, 76 x 24 cells of the 8x12 font); the shell is attached to it
; (SYS_WTERM, inherited), so it and every program it starts print there and read their
; keys there, unchanged. The close box ends the shell; when the shell ends, the window
; closes. Without a Desktop it starts the window system itself (and stops it at the end).
        .include "horizon.inc"

        .segment "CODE"
        .a16
        .i16
start:  sys     SYS_WSSTART
        jcs     fail
        sta     z:own
        sys     SYS_GETPID              ; a little offset per terminal: x 11 or 19, y 24-48
        pha                             ; (610 x 305 outside: always fully on screen)
        and     #1
        asl     a
        asl     a
        asl     a
        clc
        adc     #11
        sta     wblk
        pla
        and     #3
        asl     a
        asl     a
        asl     a
        clc
        adc     #24
        sta     wblk+2
        ptr     wblk
        sys     SYS_WOPEN
        jcs     fail2
        sta     z:win
        sys     SYS_WTERM               ; attach: the shell inherits it
        jcs     fail2
        stz     z:u_arg
        stz     z:u_arg+2
        ptr     p_sh
        lda     #1
        jsr     spawn
        jcs     fail2
        sta     z:pid
        ldx     #0                      ; its keys (ctrl-C belongs to the shell)
        sys     SYS_ILEND
        lda     #$FF                    ; detach this task
        sys     SYS_WTERM
        lda     z:win                   ; look after the shell twice a second
        ldx     #50
        sys     SYS_WTIMER

loop:   lda     #0
        ptr     ev
        sys     SYS_WEVENT
        bcs     loop
        lda     ev
        and     #$00FF
        cmp     #WE_CLOSE
        beq     @close
        cmp     #WE_TICK
        bne     loop
        jsr     alive
        bcs     loop
        bra     @reap
@close: lda     z:pid
        sys     SYS_KILL
@reap:  lda     z:pid
        sys     SYS_WAIT
        lda     z:win
        sys     SYS_WCLOSE
        lda     z:own
        beq     :+
        sys     SYS_WSSTOP
:       exit    0

fail2:  lda     z:own
        beq     fail
        sys     SYS_WSSTOP
fail:   print   "term: cannot open a terminal\n"
        exit    1

; C set while the shell runs (it is in the task table and not a zombie)
alive:  stz     z:t
@s:     lda     z:t
        ptr     info
        sys     SYS_TINFO
        bcs     @n
        lda     info
        and     #$00FF
        cmp     z:pid
        bne     @n
        lda     info+1
        and     #$00FF
        cmp     #4
        beq     @dead
        sec
        rts
@n:     inc     z:t
        lda     z:t
        cmp     #16
        bcc     @s
@dead:  clc
        rts

        .segment "RODATA"
p_sh:   .byte   "/SYSTEM/SH.PRG", 0
t_term: .byte   "Terminal", 0

        .segment "DATA"
wblk:   .word   8, 24, 76 * 8, 24 * 12  ; 610 x 305 outside: fits below the bar
        .faraddr t_term
        .byte   WF_TERM

        .segment "BSS"
ev:     .res    8
info:   .res    16

        .segment "ZEROPAGE"
own:    .res    2
win:    .res    2
pid:    .res    2
t:      .res    2
