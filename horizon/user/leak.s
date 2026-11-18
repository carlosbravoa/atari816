; LEAK - does the kernel release everything a program leaves behind? "leak [n]" (default
; 200) starts the window system if nobody runs it, counts what is free (banks, window
; slots, ports, file handles, task slots), then starts itself n times as a child ("leak c"):
; the child opens a window with a menu and a timer, takes the pointer shape and the hold,
; puts something on the clipboard, opens two files, allocates two banks and a port, then
; exits without giving anything back (odd runs), or waits for events until LEAK kills it
; (even runs). Then everything is counted again and must be the same:
;   leak: 200 runs: banks 76 -> 76, windows 14 -> 14, ports 16 -> 16, files 4 -> 4,
;     tasks 13 -> 13: PASS
        .include "horizon.inc"

        .segment "CODE"
        .a16
        .i16
start:  jsr     args_init
        lda     [u_p]
        and     #$00FF
        cmp     #'c'
        jeq     child
        lda     #200
        sta     z:runs
        jsr     parse_dec
        bcs     :+
        sta     z:runs
:       sys     SYS_WSSTART
        jcs     nows
        sta     z:wsown
        ptr     clblk                   ; the clipboard's bank exists from now on
        sys     SYS_CLPUT
        jsr     count
        ldx     #0
:       lda     cnt,x
        sta     cnt0,x
        inx
        inx
        cpx     #10
        bcc     :-
        stz     z:k
@run:   lda     z:k
        cmp     z:runs
        jcs     @done
        lda     z:k                     ; even runs wait (killed), odd runs exit
        lsr     a
        lda     #.loword(a_cwait)
        bcc     :+
        lda     #.loword(a_cexit)
:       sta     z:u_arg
        lda     #^a_cwait
        sta     z:u_arg+2
        ptr     p_self
        lda     #2
        jsr     spawn
        jcs     @serr
        sta     z:id
        lda     z:k
        and     #1
        bne     :+
        lda     #3                      ; even: it waits for events: killed
        sys     SYS_SLEEP               ; (give it the time to open everything)
        lda     z:id
        sys     SYS_KILL
:       lda     z:id
        sys     SYS_WAIT
        inc     z:k
        bra     @run
@done:  jsr     count
        print   "leak: "
        lda     z:runs
        jsr     put_dec
        print   " runs:"
        stz     z:bad
        ldx     #0
@show:  phx
        lda     names,x
        tax
        ldy     #^names
        jsr     out_str
        plx
        phx
        lda     cnt0,x
        jsr     put_dec
        print   " -> "
        plx
        phx
        lda     cnt,x
        jsr     put_dec
        plx
        lda     cnt,x
        cmp     cnt0,x
        beq     :+
        inc     z:bad
:       inx
        inx
        cpx     #10
        bcc     @show
        lda     z:bad
        bne     :+
        print   ": PASS\n"
        bra     @end
:       print   ": FAIL\n"
@end:   jsr     out_flush
        lda     z:wsown
        beq     :+
        sys     SYS_WSSTOP
:       lda     z:bad
        jmp     exit_a
@serr:  pha
        print   "leak: spawn error $"
        pla
        jsr     put_hex8
        jsr     put_nl
        lda     #1
        jmp     exit_a
nows:   print   "leak: no window system\n"
        exit    1

; what is free -> cnt: banks, window slots, ports, file handles, task slots
count:  sys     SYS_MINFO
        sta     cnt
        stz     z:n                     ; windows: open until refused, then close them
@w:     ptr     wblk
        sys     SYS_WOPEN
        bcs     :+
        ldx     z:n
        sta     tmp,x
        inx
        inx
        stx     z:n
        bra     @w
:       ldx     z:n
        txa
        lsr     a
        sta     cnt+2
:       cpx     #0
        beq     :+
        dex
        dex
        phx
        lda     tmp,x
        sys     SYS_WCLOSE
        plx
        bra     :-
:       stz     z:n                     ; ports
@p:     sys     SYS_PCREATE
        bcs     :+
        ldx     z:n
        sta     tmp,x
        inx
        inx
        stx     z:n
        bra     @p
:       ldx     z:n
        txa
        lsr     a
        sta     cnt+4
:       cpx     #0
        beq     :+
        dex
        dex
        phx
        lda     tmp,x
        sys     SYS_PCLOSE
        plx
        bra     :-
:       stz     z:n                     ; file handles
@f:     ptr     p_self
        lda     #O_READ
        sys     SYS_OPEN
        bcs     :+
        ldx     z:n
        sta     tmp,x
        inx
        inx
        stx     z:n
        cpx     #16
        bcc     @f
:       ldx     z:n
        txa
        lsr     a
        sta     cnt+6
:       cpx     #0
        beq     :+
        dex
        dex
        phx
        lda     tmp,x
        sys     SYS_CLOSE
        plx
        bra     :-
:       stz     cnt+8                   ; free task slots
        stz     z:n
:       lda     z:n
        ptr     info
        sys     SYS_TINFO
        lda     info
        and     #$00FF
        bne     :+
        inc     cnt+8
:       inc     z:n
        lda     z:n
        cmp     #16
        bcc     :--
        rts

; ---- the child: takes everything it can and never gives it back ----
child:  ptr     wblk
        sys     SYS_WOPEN
        bcs     @win
        sta     z:win
        ptr     menu
        sys     SYS_WMENU
        lda     z:win
        ldx     #5
        sys     SYS_WTIMER
        lda     #1
        sys     SYS_WSHOLD
        lda     #PTR_DRAG
        sys     SYS_WPTR
@win:   ptr     clblk
        sys     SYS_CLPUT
        ptr     p_self
        lda     #O_READ
        sys     SYS_OPEN
        ptr     p_self
        lda     #O_READ
        sys     SYS_OPEN
        sys     SYS_BALLOC
        sys     SYS_BALLOC
        sys     SYS_PCREATE
        jsr     args_init
        ldy     #1                      ; "cw": wait (until killed), "ce": exit
        lda     [u_p],y
        and     #$00FF
        cmp     #'w'
        bne     @out
:       lda     #0                      ; wait for events (until killed); the timer ticks
        ptr     ev
        sys     SYS_WEVENT
        bra     :-
@out:   lda     #0
        sys     SYS_EXIT

        .segment "RODATA"
p_self: .byte   "/SYSTEM/TESTS/LEAK.PRG", 0
a_cwait: .byte  "cw", 0
a_cexit: .byte  "ce", 0
wblk:   .word   40, 40, 100, 60
        .faraddr t_win
        .byte   0
t_win:  .byte   "Leak", 0
menu:   .byte   "Leak", 0, "Item", 0, 0, 0
        .res    40
clblk:  .faraddr t_win
        .word   4
names:  .addr   n0, n1, n2, n3, n4
n0:     .byte   " banks ", 0
n1:     .byte   ", windows ", 0
n2:     .byte   ", ports ", 0
n3:     .byte   ", files ", 0
n4:     .byte   ", task slots ", 0

        .segment "BSS"
cnt0:   .res    10
cnt:    .res    10
tmp:    .res    64
info:   .res    16
ev:     .res    8

        .segment "ZEROPAGE"
runs:   .res    2
k:      .res    2
id:     .res    2
n:      .res    2
bad:    .res    2
wsown:  .res    2
win:    .res    2
