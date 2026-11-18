; REGS - checks that the kernel preserves the whole user context: 8-bit A (and the hidden
; B), 8-bit X/Y, D = $0040, a DBR that is not the code bank, decimal mode, across about
; 40 preemptions (run next to SPIN) and across syscalls.
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  print   "regs: start\n"
        sys     SYS_BALLOC              ; a data bank for DBR
        jcs     bad
        sta     z:bank
        lda     #$C3C3                  ; marker at window $0040 (= D:0000)
        sta     z:$40
        ; across syscalls: X, Y, D, DBR, M/X flags and the decimal flag survive a COP
        lda     #$0040
        tcd
        sep     #$20
        .a8
        lda     z:bank - $40            ; (direct page, D = $0040)
        pha
        plb                             ; DBR = data bank
        sep     #$18                    ; 8-bit X/Y, decimal
        .i8
        ldx     #$12
        ldy     #$34
        cop     SYS_GETPID
        php
        cpx     #$12
        jne     bad8
        cpy     #$34
        jne     bad8
        pla
        and     #$38                    ; M, X, D still set, carry clear
        cmp     #$38
        jne     bad8
        phb
        pla
        cmp     z:bank - $40
        jne     bad8
        lda     z:0                     ; D still $0040
        cmp     #$C3
        jne     bad8
        ; across preemption: spin on memory, check the registers on every round
        lda     #3                      ; 3 x 65536 rounds, about 400 ms
        sta     z:cnt - $40 + 2
        stz     z:cnt - $40 + 1
        stz     z:cnt - $40
        lda     #$A5
        xba
        lda     #$5A
        ldx     #$12
        ldy     #$34
loop:   cmp     #$5A
        jne     bad8
        cpx     #$12
        jne     bad8
        cpy     #$34
        jne     bad8
        xba
        cmp     #$A5
        jne     bad8
        xba
        dec     z:cnt - $40
        bne     loop
        dec     z:cnt - $40 + 1
        bne     loop
        dec     z:cnt - $40 + 2
        bne     loop
        php
        pla
        and     #$38
        cmp     #$38
        jne     bad8
        cld
        rep     #$30
        .a16
        .i16
        lda     #0
        tcd
        phk
        plb
        print   "regs: context preserved\n"
        exit    0
        .a8
        .i8
bad8:   cld
        rep     #$30
        .a16
        .i16
bad:    lda     #0
        tcd
        phk
        plb
        print   "regs: FAILED\n"
        exit    1

        .segment "ZEROPAGE"
bank:   .res    2
cnt:    .res    4
