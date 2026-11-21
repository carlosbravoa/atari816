; emu816 OPL2 test (REV $0C, $00:DB30-$DB33): what core/sw/a816/opltest.s does not measure.
; The idle status and the output registers, the periods of timers A and B, a masked flag that
; still sets (JTOPL) and shows when unmasked, IRQ_STATUS bit 5 (AUDIO) waking WAI, a new
; timer value taking effect at the next overflow, a stopped timer, and the sound page: with
; the classic machine frozen $DB00 is written and $DB10 (a DAC before REV $0C) is not, which
; run_tests.sh checks with --log-sound. No delays between OPL writes: the emulator needs none
; (the YM3812 wants 3.3 us after the select and 23 us after the data).
        .include "common.inc"

OPL_ADDR   = $00DB30
OPL_STAT   = $00DB30
OPL_DATA   = $00DB31
OPL_OUT_LO = $00DB32
OPL_OUT_HI = $00DB33
SYS_REV    = $00DE01
SV_CTRL    = $00DC00

t1      = $20                           ; 2 bytes
t2      = $22                           ; 2 bytes
t3      = $24                           ; 2 bytes

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
        print   m_hello
        lda     f:SYS_REV
        jsr     puthex
        jsr     crlf

; ── idle: status $06, $DB31-$DB33 read 0 ──
        print   m_stat
        lda     f:OPL_STAT
        jsr     puthex
        print   m_out
        lda     f:OPL_DATA
        ora     f:OPL_OUT_LO
        ora     f:OPL_OUT_HI
        jsr     puthex
        jsr     crlf

; ── timer A, value $F0: 16 steps of 288 chip clocks = 18,432 CPU cycles = 1,285 us ──
        lda     #$02
        ldy     #$F0
        jsr     opw
        lda     #$04
        ldy     #$80
        jsr     opw
        lda     #$04
        ldy     #$21                    ; mask B, start A
        jsr     opw
        lda     #$40
        jsr     poll                    ; the first overflow: any phase of the prescaler
        jsr     now
        stx     t1
        jsr     clr
        lda     #$40
        jsr     poll
        jsr     now
        print   m_ta
        jsr     elapsed
        print   m_stat2
        lda     f:OPL_STAT
        jsr     puthex
        jsr     crlf

; ── timer B, value $F0: 16 steps of 1,152 chip clocks = 73,728 CPU cycles = 5,140 us ──
        lda     #$03
        ldy     #$F0
        jsr     opw
        lda     #$04
        ldy     #$42                    ; mask A, start B, stop A
        jsr     opw
        lda     #$20
        jsr     poll
        jsr     now
        stx     t1
        jsr     clr
        lda     #$20
        jsr     poll
        jsr     now
        print   m_tb
        jsr     elapsed
        print   m_stat2
        lda     f:OPL_STAT
        jsr     puthex
        jsr     crlf

; ── a masked flag still sets (jtopl_timers.v: flag_A = pre_A & flagen_A) ──
        lda     #$04
        ldy     #$00                    ; stop both
        jsr     opw
        jsr     clr
        lda     #$04
        ldy     #$41                    ; mask A, start A
        jsr     opw
        ldx     #3000
        jsr     wait
        print   m_mask
        lda     f:OPL_STAT
        jsr     puthex
        lda     #$04
        ldy     #$01                    ; unmask (bit 6 clear: no flag clear)
        jsr     opw
        print   m_unmask
        lda     f:OPL_STAT
        jsr     puthex
        jsr     crlf

; ── the IRQ: IRQ_STATUS bit 5 wakes WAI (I set), at the overflows ──
        lda     #$20
        sta     f:IRQ_EN
        sei
        jsr     clr
        wai                             ; the next overflow, any phase
        jsr     now
        stx     t1
        jsr     clr
        wai
        jsr     now
        print   m_irq
        lda     f:IRQ_STATUS
        and     #$20
        jsr     puthex
        print   m_wai
        jsr     elapsed0
        jsr     clr
        print   m_clr
        lda     f:IRQ_STATUS
        and     #$20
        jsr     puthex
        jsr     crlf

; ── a new value: the running count finishes (16 steps), then 32 steps ($E0) ──
        wai
        jsr     now
        stx     t1
        lda     #$02
        ldy     #$E0
        jsr     opw
        jsr     clr
        wai
        jsr     now
        jsr     clr
        print   m_reload
        jsr     elapsed0
        ldx     t2
        stx     t1
        wai
        jsr     now
        lda     #' '
        jsr     putc
        jsr     elapsed
        lda     #0
        sta     f:IRQ_EN

; ── stopped: no flag ──
        lda     #$04
        ldy     #$00
        jsr     opw
        jsr     clr
        ldx     #6000
        jsr     wait
        print   m_stop
        lda     f:OPL_STAT
        jsr     puthex
        jsr     crlf

; ── sound page, frozen: $DB00 taken, $DB10 not (REV $0C: no DACs) ──
        lda     #$04
        sta     f:SV_CTRL
        lda     #$12
        sta     f:$00DB00
        lda     #$34
        sta     f:$00DB10
        lda     #0
        sta     f:SV_CTRL
        print   m_done
        stp

; OPL register A = Y (low byte)
opw:    sta     f:OPL_ADDR
        tya
        sta     f:OPL_DATA
        rts
; clear both flags ($04 = $80: IRQ reset, the timers keep running)
clr:    lda     #$04
        ldy     #$80
        bra     opw
; wait until a status bit in A is set
poll:   sta     t3
:       lda     f:OPL_STAT
        and     t3
        beq     :-
        rts
; X = t2 = UPTIME (low 16 bits)
now:    rep     #$20
        .a16
        lda     f:UPTIME
        sta     t2
        tax
        sep     #$20
        .a8
        rts
; print t2 - t1 (X = t2) as 4 hex digits, then a newline (elapsed0: no newline)
elapsed0:
        rep     #$20
        .a16
        lda     t2
        sec
        sbc     t1
        tax
        sep     #$20
        .a8
        jmp     puthex16
elapsed:
        jsr     elapsed0
        jmp     crlf
; wait X microseconds
wait:   rep     #$20
        .a16
        stx     t3
        lda     f:UPTIME
        clc
        adc     t3
        sta     t3
:       lda     f:UPTIME
        sec
        sbc     t3
        bmi     :-
        sep     #$20
        .a8
        rts

m_hello:  .byte "OPL2 EMU TEST REV ", 0
m_stat:   .byte "STAT ", 0
m_out:    .byte " DB31-DB33 ", 0
m_ta:     .byte "TIMER A F0 US ", 0
m_tb:     .byte "TIMER B F0 US ", 0
m_stat2:  .byte "STAT AT OVERFLOW ", 0
m_mask:   .byte "MASKED ", 0
m_unmask: .byte " UNMASKED ", 0
m_irq:    .byte "IRQ_STATUS ", 0
m_wai:    .byte " WAI TO WAI US ", 0
m_clr:    .byte " CLEARED ", 0
m_reload: .byte "NEW VALUE US ", 0
m_stop:   .byte "STOPPED ", 0
m_done:   .byte "DONE", 10, 0
