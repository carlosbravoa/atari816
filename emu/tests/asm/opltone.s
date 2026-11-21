; emu816 OPL2 sound test (REV $0C): a 440 Hz sine on channel 0 for one second, then the key
; released, then one second more. run_tests.sh records it with --wav and checks the pitch, the
; level (one operator at total level 0: 4,084 on the board's JTOPL, channel 0 at 0 dB), the
; length and that the release decays to silence. 440 Hz: F-number 579, block 4 at the board's
; 49,803 Hz sample rate (579 x 49,803 / 2^16 = 440.0 Hz). No delays between OPL writes: the
; emulator needs none.
        .include "common.inc"

OPL_ADDR   = $00DB30
OPL_DATA   = $00DB31
SYS_REV    = $00DE01

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
        ldx     #0
:       lda     regs,x                  ; the voice, then the key-on
        ldy     regs+1,x
        jsr     opw
        inx
        inx
        cpx     #regs_end - regs
        bne     :-
        print   m_on
        jsr     second
        lda     #$B0                    ; key off (block and F-number kept)
        ldy     #$12
        jsr     opw
        print   m_off
        jsr     second
        print   m_done
        stp

regs:   .byte   $01, $20                ; waveform select enable
        .byte   $20, $01                ; modulator: multiple 1
        .byte   $40, $3F                ; ... total level 63: silent (the carrier is a pure sine)
        .byte   $60, $F0, $80, $0F
        .byte   $23, $21                ; carrier: sustained, multiple 1
        .byte   $43, $00                ; ... total level 0
        .byte   $63, $F0                ; ... attack 15, decay 0
        .byte   $83, $08                ; ... sustain level 0, release 8
        .byte   $E3, $00                ; ... sine
        .byte   $C0, $00                ; FM, no feedback
        .byte   $A0, $43                ; F-number 579 ($243), low byte
        .byte   $B0, $32                ; key on, block 4, F-number bits 8-9
regs_end:

; OPL register A = Y (low byte); preserves X
opw:    sta     f:OPL_ADDR
        tya
        sta     f:OPL_DATA
        rts
; wait one second (40 x 25 ms)
second: ldy     #40
:       ldx     #25000
        jsr     wait
        dey
        bne     :-
        rts
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

m_hello:  .byte "OPL2 TONE TEST REV ", 0
m_on:     .byte "KEY ON", 10, 0
m_off:    .byte "KEY OFF", 10, 0
m_done:   .byte "DONE", 10, 0
