; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816 bring-up 1 test program. Loaded at $01:0000 by the I/O processor,
; entered in native mode from the reset stub at $00:FF00.
; Build: make   (SIM=1 shortens the RAM test for simulation)
        .p816
        .smart  -

SYS_ID    = $00DE00
SYS_REV   = $00DE01
RAM_BANKS = $00D809
UPTIME    = $00DE18
DBG_OUT   = $00DEF0
DBG_STAT  = $00DEF1

.ifdef SIM
TEST_LEN   = $0200          ; bytes tested per bank
LAST_BANK  = $03
BENCH_LEN  = $0400
.else
TEST_LEN   = $0000          ; 0 = the whole 64 KB
LAST_BANK  = $0F            ; banks $02-$0F are free RAM; higher banks hold other things
BENCH_LEN  = $8000
.endif
FIRST_BANK = $02

; direct page variables ($00:0010..)
ptr     = $10               ; 24-bit pointer
bank    = $13
tmp     = $14
lastb   = $15
errs    = $16               ; 16-bit
t0      = $18               ; 32-bit
t1      = $1C               ; 32-bit

        .segment "CODE"
        .a8
        .i16
start:  clc
        xce
        rep     #$10
        sep     #$20
        ldx     #$01FF
        txs
        phk
        plb

        ldx     #.loword(m_hello)
        jsr     puts
        lda     f:SYS_ID
        jsr     puthex
        ldx     #.loword(m_rev)
        jsr     puts
        lda     f:SYS_REV
        jsr     puthex
        ldx     #.loword(m_banks)
        jsr     puts
        lda     f:RAM_BANKS
        jsr     puthex
        jsr     crlf

        lda     f:RAM_BANKS
        cmp     #LAST_BANK
        bcc     :+
        lda     #LAST_BANK
:       sta     lastb

; ── RAM test: write every bank, then verify every bank (catches aliasing) ──
        stz     errs
        stz     errs+1
        lda     #FIRST_BANK
        sta     bank
wbank:  jsr     setptr
        ldy     #0
wloop:  jsr     pat
        sta     [ptr],y
        iny
        cpy     #TEST_LEN
        bne     wloop
        lda     bank
        cmp     lastb
        beq     wdone
        inc     bank
        bra     wbank
wdone:
        lda     #FIRST_BANK
        sta     bank
vbank:  jsr     setptr
        ldy     #0
vloop:  jsr     pat
        cmp     [ptr],y
        beq     :+
        rep     #$20
        .a16
        inc     errs
        sep     #$20
        .a8
:       iny
        cpy     #TEST_LEN
        bne     vloop
        lda     bank
        cmp     lastb
        beq     vdone
        inc     bank
        bra     vbank
vdone:  ldx     #.loword(m_ram)
        jsr     puts
        lda     errs+1
        jsr     puthex
        lda     errs
        jsr     puthex
        jsr     crlf

; ── Benchmark 1: 65536 x (DEX, BNE) = 327,680 cycles, all in two cache lines ──
        jsr     tstart
        ldx     #0
b1:     dex
        bne     b1
        ldx     #.loword(m_b1)
        jsr     tprint

; ── Benchmark 2: sequential read of BENCH_LEN bytes in bank 2 (one miss per line) ──
        lda     #FIRST_BANK
        sta     bank
        jsr     setptr
        jsr     tstart
        ldy     #0
        lda     #0
b2:     eor     [ptr],y
        iny
        cpy     #BENCH_LEN
        bne     b2
        ldx     #.loword(m_b2)
        jsr     tprint

; ── Benchmark 3: MVN copy of BENCH_LEN bytes inside bank 2 (read + write-through) ──
        jsr     tstart
        rep     #$20
        .a16
        lda     #BENCH_LEN-1
        ldx     #$0000
        ldy     #$8000
        mvn     #FIRST_BANK, #FIRST_BANK
        sep     #$20
        .a8
        phk
        plb
        ldx     #.loword(m_b3)
        jsr     tprint

        ldx     #.loword(m_done)
        jsr     puts
halt:   bra     halt

; ── helpers ──
setptr: lda     bank
        sta     ptr+2
        stz     ptr
        stz     ptr+1
        rts

pat:    rep     #$20            ; A = lo(Y) ^ hi(Y) ^ bank
        .a16
        tya
        xba
        sep     #$20
        .a8
        sta     tmp
        tya
        eor     tmp
        eor     bank
        rts

tstart: ldx     #0
:       lda     f:UPTIME,x      ; reading +0 latches +1..+3
        sta     t0,x
        inx
        cpx     #4
        bne     :-
        rts

tprint: phx                     ; X = message; prints elapsed microseconds (hex)
        ldx     #0
:       lda     f:UPTIME,x
        sta     t1,x
        inx
        cpx     #4
        bne     :-
        plx
        jsr     puts
        rep     #$20
        .a16
        sec
        lda     t1
        sbc     t0
        sta     t1
        lda     t1+2
        sbc     t0+2
        sta     t1+2
        sep     #$20
        .a8
        lda     t1+3
        jsr     puthex
        lda     t1+2
        jsr     puthex
        lda     t1+1
        jsr     puthex
        lda     t1
        jsr     puthex
crlf:   lda     #10
putc:   pha
:       lda     f:DBG_STAT
        bmi     :-
        pla
        sta     f:DBG_OUT
        rts

puts:   lda     a:0,x           ; DBR = program bank
        beq     :+
        jsr     putc
        inx
        bra     puts
:       rts

puthex: pha
        lsr
        lsr
        lsr
        lsr
        jsr     nib
        pla
        and     #$0F
nib:    cmp     #10
        bcc     :+
        adc     #6
:       adc     #'0'
        bra     putc

m_hello: .byte "ATARI816 BRING-UP 1", 10, "ID ", 0
m_rev:   .byte " REV ", 0
m_banks: .byte " BANKS-1 ", 0
m_ram:   .byte "RAM ERRORS ", 0
m_b1:    .byte "LOOP US ", 0
m_b2:    .byte "READ US ", 0
m_b3:    .byte "MVN US ", 0
m_done:  .byte "DONE", 10, 0
