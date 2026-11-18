; CRASH - argument: the mode number; does one forbidden thing. Every mode except 8 and 9 must
; be killed by the kernel with a "[kill]" line; the system carries on.
;   1 write kernel memory ($00:9000)       5 BRK
;   2 read another task's bank ($03 =      6 switch to emulation mode, wait for an IRQ
;     INIT's code bank)                    7 jump into a bank nobody owns ($7B)
;   3 write an I/O register (DBG_OUT)      8 puts with a pointer into the kernel: EFAULT
;   4 S into kernel memory, then COP       9 sleep forever (INIT kills it)
;  11 S into kernel memory, then wait for the timer IRQ (entry frame lost)
;  12 S = $0002, then wait for the timer IRQ (frame half outside the window)
;  13 SEI and loop forever: only the watchdog NMI can stop it (cause $23)
;  10 take all 4 file handles, a port and 3 banks, then BRK: the kernel must give
;     everything back (CAT, PING and MEM later depend on it)
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  jsr     args_init
        jsr     parse_dec
        cmp     #14
        bcc     :+
        lda     #0
:       sta     z:mode
        print   "crash "
        lda     z:mode
        jsr     put_dec
        jsr     put_nl
        jsr     out_flush
        lda     z:mode
        asl     a
        tax
        jmp     (modes,x)

modes:  .addr   m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13

m1:     sep     #$20
        .a8
        lda     #$55
        sta     f:$009000
        .a16
        brl     survived
m2:     lda     f:$030100
        brl     survived
m3:     sep     #$20
        .a8
        lda     #'X'
        sta     f:$00DEF0
        .a16
        brl     survived
m4:     ldx     #$9000
        txs
        sys     SYS_GETPID
        brl     survived
m5:     brk     $00
        brl     survived
m6:     sec
        xce
:       bra     :-
m7:     jml     $7B0000
m8:     ldx     #$9000
        ldy     #0
        sys     SYS_PUTS
        jcc     survived
        cmp     #EFAULT
        jne     survived
        print   "crash 8: EFAULT, still alive\n"
        exit    0
m9:     lda     #1000
        sys     SYS_SLEEP
        bra     m9
m10:    lda     #4
        sta     z:cnt
:       ptr     readme
        lda     #O_READ
        sys     SYS_OPEN
        jcs     survived
        dec     z:cnt
        bne     :-
        ptr     readme                  ; a fifth one must fail
        lda     #O_READ
        sys     SYS_OPEN
        jcc     survived
        sys     SYS_PCREATE
        jcs     survived
        sys     SYS_BALLOC
        sys     SYS_BALLOC
        sys     SYS_BALLOC
        jcs     survived
        print   "crash 10: holding 4 files, a port, 5 banks\n"
        jsr     out_flush
        brk     $00
m11:    ldx     #$9000
        txs
:       bra     :-
m12:    ldx     #$0002
        txs
:       bra     :-
m13:    sei
:       bra     :-
m0:
survived:
        rep     #$30
        print   "crash: NOT KILLED\n"
        exit    1

        .segment "RODATA"
readme: .byte   "/README.TXT", 0
        .segment "ZEROPAGE"
mode:   .res    2
cnt:    .res    2
