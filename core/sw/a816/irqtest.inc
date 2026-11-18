; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; System block test: timers, IRQ, user-mode preemption, watchdog NMI.
; Included by freddie2.s; entered at irqtest in kernel state (a8 i16, DBR = program bank,
; FR_CTRL = 0, kernel stack).
IRQ_STATUS = $00DE08
IRQ_EN     = $00DE09
NMI_STATUS = $00DE0A
TM0_RELOAD = $00DE10
TM0_CTRL   = $00DE13
UPTIME     = $00DE18
WATCHDOG   = $00DE1C

        .a8
        .i16
irqtest:
        sei
        lda     #$5C                    ; trampolines: IRQ at $00:E008, NMI at $00:E00C
        sta     f:$00E008
        sta     f:$00E00C
        lda     #$01
        sta     f:$00E00B
        sta     f:$00E00F
        rep     #$20
        .a16
        lda     #.loword(irq_h)
        sta     f:$00E009
        lda     #.loword(nmi_h)
        sta     f:$00E00D
        lda     #$E008
        sta     f:$00FFEE
        lda     #$E00C
        sta     f:$00FFEA
        sep     #$20
        .a8

; ── one-shot timer, 1000 us, woken from WAI ──
        ldx     #.loword(m_tmr)
        jsr     puts
        stz     ticks
        ldx     #1000
        jsr     set_tm0
        lda     #$04                    ; TIMER0
        sta     f:IRQ_EN
        jsr     gettime
        rep     #$20
        .a16
        lda     now
        sta     t0
        sep     #$20
        .a8
        lda     #$01                    ; RUN, no repeat
        sta     f:TM0_CTRL
        cli
        wai
        sei
        jsr     elapsed                 ; X = microseconds since t0
        cpx     #1000
        bcc     tm_bad
        cpx     #1200
        bcs     tm_bad
        lda     ticks
        cmp     #1
        bne     tm_bad
        lda     f:TM0_CTRL              ; a one-shot stops itself
        bne     tm_bad
        jsr     ok
        bra     t_rep
tm_bad: jsr     prx
        jsr     fail

; ── repeating timer, 10 x 500 us ──
t_rep:  ldx     #.loword(m_rep)
        jsr     puts
        stz     ticks
        ldx     #500
        jsr     set_tm0
        jsr     gettime
        rep     #$20
        .a16
        lda     now
        sta     t0
        sep     #$20
        .a8
        lda     #$03
        sta     f:TM0_CTRL
        cli
:       wai
        lda     ticks
        cmp     #10
        bcc     :-
        sei
        lda     #$00
        sta     f:TM0_CTRL
        jsr     elapsed
        cpx     #5000
        bcc     rep_bad
        cpx     #5300
        bcs     rep_bad
        jsr     ok
        bra     t_pre
rep_bad:
        jsr     prx
        jsr     fail

; ── preemption: a user task that never yields is interrupted three times ──
t_pre:  ldx     #.loword(m_pre)
        jsr     puts
        stz     ticks
        stz     uflag
        stz     irqctl
        ldx     #0
        stx     logn
        ldx     #1000
        jsr     set_tm0
        lda     #$03
        sta     f:TM0_CTRL
        lda     #2
        sta     phase
        lda     #1
        sta     f:CUR_TASK
        lda     #$07                    ; PROT_EN + USER_ARM + B0WIN_EN
        sta     f:FR_CTRL
        lda     #$01
        pha
        ldx     #.loword(user2)
        phx
        lda     #$20                    ; a8, i16, interrupts enabled
        pha
        rti

user2:  ldx     #$7FFF
        txs
        lda     #$02
        pha
        plb
        ldx     #0
:       inx
        stx     a:$0020
        lda     f:uflag                 ; set by the IRQ handler after three ticks
        beq     :-
        stx     a:$0022
        lda     f:$00DE00               ; still in user mode: this must abort

; the ABORT handler jumps here in phase 2, back on the kernel stack with FR_CTRL = 0
pre_check:
        lda     #$00
        sta     f:TM0_CTRL
        sta     phase
        lda     ticks
        cmp     #3
        bne     pre_bad
        lda     irqctl                  ; FR_CTRL seen by the IRQ handler: came from user mode
        cmp     #$07
        bne     pre_bad
        lda     log
        cmp     #$08                    ; IO_PAGE
        bne     pre_bad
        rep     #$20
        .a16
        lda     f:$020022
        beq     pre_bad16
        cmp     f:$020020
        bne     pre_bad16
        sep     #$20
        .a8
        jsr     ok
        bra     t_wd
pre_bad16:
        sep     #$20
pre_bad:
        lda     ticks
        jsr     puthex
        lda     irqctl
        jsr     puthex
        lda     log
        jsr     puthex
        jsr     fail

; ── watchdog: armed and left alone, it raises an NMI ──
t_wd:   ldx     #.loword(m_wd)
        jsr     puts
        stz     nmist
        jsr     gettime
        rep     #$20
        .a16
        lda     now
        sta     t0
        lda     now+2
        sta     t0+2
        sep     #$20
        .a8
        lda     #$5A
        sta     f:WATCHDOG
        wai                             ; I is set: only the NMI ends this
        jsr     gettime
        rep     #$20
        .a16
        sec
        lda     now
        sbc     t0
        sta     t0
        lda     now+2
        sbc     t0+2
        sta     t0+2
        sep     #$20
        .a8
        lda     t0+3
        jsr     puthex
        lda     t0+2
        jsr     puthex
        lda     t0+1
        jsr     puthex
        lda     t0
        jsr     puthex
        lda     #' '
        jsr     putc
        lda     nmist
        cmp     #$02
        bne     :+
        jsr     ok
        jmp     irq_done
:       jsr     fail
        jmp     irq_done

; ── helpers ──
set_tm0:                                ; X = microseconds
        rep     #$20
        .a16
        txa
        sta     f:TM0_RELOAD
        sep     #$20
        .a8
        lda     #$00
        sta     f:TM0_RELOAD+2
        rts

gettime:                                ; now = UPTIME (reading the low byte latches the rest)
        lda     f:UPTIME
        sta     now
        lda     f:UPTIME+1
        sta     now+1
        lda     f:UPTIME+2
        sta     now+2
        lda     f:UPTIME+3
        sta     now+3
        rts

elapsed:                                ; X = low 16 bits of (UPTIME - t0)
        jsr     gettime
        rep     #$20
        .a16
        sec
        lda     now
        sbc     t0
        tax
        sep     #$20
        .a8
        rts

prx:    rep     #$20                    ; print X as 4 hex digits
        .a16
        txa
        sep     #$20
        .a8
        xba
        jsr     puthex
        xba
        jmp     puthex

irq_h:  rep     #$30
        .a16
        pha
        phx
        sep     #$20
        .a8
        lda     f:IRQ_STATUS
        sta     f:IRQ_STATUS
        lda     f:FR_CTRL
        sta     f:irqctl
        lda     f:ticks
        inc
        sta     f:ticks
        cmp     #3
        bcc     :+
        lda     #1
        sta     f:uflag
:       rep     #$30
        plx
        pla
        rti

nmi_h:  sep     #$20
        pha
        lda     f:NMI_STATUS
        sta     f:nmist
        sta     f:NMI_STATUS
        pla
        rti

m_tmr:  .byte "TIMER ", 0
m_rep:  .byte "REPEAT ", 0
m_pre:  .byte "PREEMPT ", 0
m_wd:   .byte "WDOG US ", 0
ticks:  .byte 0
uflag:  .byte 0
irqctl: .byte 0
nmist:  .byte 0
now:    .res 4
t0:     .res 4
