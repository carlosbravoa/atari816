; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816 self-checking OPL2 (YM3812) test (REV $0C).
;   1. STAT   : OPL_STAT ($00:DB30) idle == $06 (standard YM3812 signature)
;   2. TIMER  : AdLib Timer A detect sequence ($04=$60, $04=$80, $02=$FF, $04=$21 -> status $C6),
;               plus AUDIO IRQ bit 5 asserted in IRQ_STATUS
;   3. TONE   : Program channel 0 (pure sine on carrier, fast attack, 440 Hz), key-on,
;               verify OPL_OUT ($00:DB32-$DB33) produces both positive and negative samples.
        .p816
        .smart  -

OPL_ADDR    = $00DB30
OPL_STAT    = $00DB30
OPL_DATA    = $00DB31
OPL_OUT_LO  = $00DB32
OPL_OUT_HI  = $00DB33
SYS_REV     = $00DE01
IRQ_STATUS  = $00DE08
UPTIME      = $00DE18
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1

nfail       = $20
got_pos     = $22
got_neg     = $23
t0          = $24               ; 4 bytes
cnt         = $28               ; 2 bytes

        .segment "CODE"
        .a8
        .i16
start:  clc
        xce
        rep     #$10
        sep     #$20
        ldx     #$BFFF
        txs
        phk
        plb

        stz     nfail
        stz     got_pos
        stz     got_neg

        ldx     #.loword(m_hdr)
        jsr     puts
        lda     f:SYS_REV
        jsr     puthex
        lda     #10
        jsr     putc

        ; 1. Idle status == $06
        lda     f:OPL_STAT
        cmp     #$06
        beq     stat_ok
        inc     nfail
        ldx     #.loword(m_sfail)
        jsr     puts
        jsr     puthex
        lda     #10
        jsr     putc
        bra     t_timer
stat_ok:
        ldx     #.loword(m_sok)
        jsr     puts

        ; 2. AdLib Timer A detection + IRQ_STATUS bit 5
t_timer:
        lda     #$04
        ldy     #$0060          ; mask T1 & T2
        jsr     opl_wr
        lda     #$04
        ldy     #$0080          ; reset IRQ
        jsr     opl_wr
        lda     #$02
        ldy     #$00FF          ; Timer A = $FF (1 tick = 80 us)
        jsr     opl_wr
        lda     #$04
        ldy     #$0021          ; unmask T1, start T1
        jsr     opl_wr

        ldy     #200            ; wait 200 us (> 80 us)
        jsr     wait_us

        lda     f:OPL_STAT
        and     #$E0
        cmp     #$C0            ; IRQ | T1
        bne     tm_fail
        lda     f:IRQ_STATUS
        and     #$20            ; bit 5 = AUDIO
        beq     tm_fail

        ; clear timer and verify IRQ drops
        lda     #$04
        ldy     #$0060
        jsr     opl_wr
        lda     #$04
        ldy     #$0080
        jsr     opl_wr
        lda     f:OPL_STAT
        cmp     #$06
        bne     tm_fail

        ldx     #.loword(m_tok)
        jsr     puts
        bra     t_tone
tm_fail:
        inc     nfail
        ldx     #.loword(m_tfail)
        jsr     puts

        ; 3. Play 440 Hz FM tone on channel 0 and sample OPL_OUT
t_tone:
        lda     #$01
        ldy     #$0020          ; waveform select enable
        jsr     opl_wr
        lda     #$20
        ldy     #$0001          ; mod: mult=1
        jsr     opl_wr
        lda     #$40
        ldy     #$003F          ; mod: max attenuation (pure carrier sine)
        jsr     opl_wr
        lda     #$60
        ldy     #$00F0          ; mod: fast attack
        jsr     opl_wr
        lda     #$80
        ldy     #$000F          ; mod: sustain=0, release=15
        jsr     opl_wr
        lda     #$23
        ldy     #$0021          ; car: sustain, mult=1
        jsr     opl_wr
        lda     #$43
        ldy     #$0000          ; car: max volume (0 dB)
        jsr     opl_wr
        lda     #$63
        ldy     #$00F0          ; car: fastest attack
        jsr     opl_wr
        lda     #$83
        ldy     #$000F          ; car: sustain=0, release=15
        jsr     opl_wr
        lda     #$C0
        ldy     #$0001          ; ch0: additive (mod + car)
        jsr     opl_wr
        lda     #$A0
        ldy     #$0041          ; F-num low (~440 Hz in block 4)
        jsr     opl_wr
        lda     #$B0
        ldy     #$0031          ; key-on, block=4, F-num hi=1
        jsr     opl_wr

        ; Poll OPL_OUT_HI over ~3 ms (more than 1 full 440 Hz period = 2.27 ms)
        ldx     #300
samp_lp:
        ldy     #15             ; 15 us step -> 4.5 ms total
        jsr     wait_us
        lda     f:OPL_OUT_HI
        beq     samp_nx
        bmi     is_neg
        cmp     #$04            ; >= +1024
        bcc     samp_nx
        inc     got_pos
        bra     samp_nx
is_neg:
        cmp     #$FC            ; <= -1024
        bcs     samp_nx
        inc     got_neg
samp_nx:
        dex
        bne     samp_lp

        ; key-off
        lda     #$B0
        ldy     #$0011
        jsr     opl_wr

        lda     got_pos
        beq     tone_fail
        lda     got_neg
        beq     tone_fail
        ldx     #.loword(m_fok)
        jsr     puts
        bra     done
tone_fail:
        inc     nfail
        ldx     #.loword(m_ffail)
        jsr     puts

done:   lda     nfail
        bne     failed
        ldx     #.loword(m_pass)
        jsr     puts
        bra     halt
failed: ldx     #.loword(m_fail)
        jsr     puts
halt:   ldx     #.loword(m_done)
        jsr     puts
        stp

; write OPL2 register A = low byte of Y, with proper YM3812 delays (4 us + 24 us)
opl_wr: sta     f:OPL_ADDR
        phy
        ldy     #5
        jsr     wait_us
        ply
        tya
        sta     f:OPL_DATA
        ldy     #26
        jsr     wait_us
        rts

; wait Y microseconds (UPTIME low 16 bits)
wait_us:
        lda     f:UPTIME
        sta     t0
        lda     f:UPTIME+1
        sta     t0+1
        rep     #$20
        .a16
        tya
        clc
        adc     t0
        sta     t0
        sep     #$20
        .a8
w_lp:   lda     f:UPTIME
        sta     t0+2
        lda     f:UPTIME+1
        sta     t0+3
        rep     #$20
        .a16
        lda     t0+2
        sec
        sbc     t0
        sep     #$20
        .a8
        bmi     w_lp
        rts

puts:   lda     f:$010000,x
        beq     puts_d
        jsr     putc
        inx
        bra     puts
puts_d: rts

putc:   pha
pc_w:   lda     f:DBG_STAT
        bmi     pc_w
        pla
        sta     f:DBG_OUT
        rts

puthex: pha
        lsr
        lsr
        lsr
        lsr
        jsr     putnib
        pla
        and     #$0F
putnib: cmp     #10
        bcc     pn1
        adc     #6
pn1:    adc     #'0'
        jmp     putc

m_hdr:   .byte "OPL2 TEST REV ", 0
m_sok:   .byte "STAT OK", 10, 0
m_sfail: .byte "STAT FAIL ", 0
m_tok:   .byte "TIMER OK", 10, 0
m_tfail: .byte "TIMER FAIL", 10, 0
m_fok:   .byte "TONE OK", 10, 0
m_ffail: .byte "TONE FAIL", 10, 0
m_pass:  .byte "OPL2 PASS", 10, 0
m_fail:  .byte "OPL2 FAIL", 10, 0
m_done:  .byte "DONE", 10, 0
