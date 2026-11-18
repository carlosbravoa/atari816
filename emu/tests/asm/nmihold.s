; NMI hold (a816_sys.sv nmi_hold): an entry out of user mode holds the NMI until the kernel
; writes FR_CTRL, because the first kernel instructions still run on the task's S.
; A user task points S into kernel memory ($00:9000) and spins. TIMER0 interrupts it, and
; the watchdog NMI fires 3 us later, during the IRQ handler's first 200 us. The handler
; moves to its own stack, checks that the NMI is latched but not taken, then writes
; FR_CTRL: the NMI must be taken right after that write. The canary at the task's S must
; be untouched (the IRQ entry's pushes are refused in user mode, and the NMI never pushes
; to the task's S).
        .include "common.inc"

FR_CTRL    = $00D800
PT_INDEX   = $00D801
PT_DATA    = $00D802
CUR_TASK   = $00D803
B0WIN      = $00D808
NMI_STATUS = $00DE0A
TM0_RELOAD = $00DE10
TM0_CTRL   = $00DE13
WATCHDOG   = $00DE1C
KSTACK     = $BFFF
TARGET     = $9000
TMR        = 2000000 - 3        ; TIMER0 fires 3 ticks before the watchdog

        .a8
        .i16
start:  clc
        xce
        rep     #$10
        sep     #$20
        ldx     #KSTACK
        txs
        phk
        plb
        print   m_hello
        lda     #$5C                    ; IRQ and NMI trampolines
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
        lda     #$5555                  ; canary at the task's stack
        sta     f:TARGET-3
        sta     f:TARGET-1
        lda     #.loword(TMR)
        sta     f:TM0_RELOAD
        sep     #$20
        .a8
        lda     #^TMR
        sta     f:TM0_RELOAD+2
        ldx     #0                      ; bank 0 kernel, bank 1 shared read-only
:       txa
        sta     f:PT_INDEX
        lda     ptab,x
        sta     f:PT_DATA
        inx
        cpx     #2
        bne     :-
        lda     #1
        sta     f:CUR_TASK
        lda     #$05
        sta     f:B0WIN
        lda     #$04
        sta     f:IRQ_EN
        lda     #$5A                    ; watchdog: NMI in 2,000,000 us
        sta     f:WATCHDOG
        lda     #$01                    ; TIMER0 one shot, 3 us earlier
        sta     f:TM0_CTRL
        lda     #$07                    ; PROT_EN + USER_ARM + B0WIN_EN
        sta     f:FR_CTRL
        lda     #$01
        pha
        ldx     #.loword(user)
        phx
        lda     #$20                    ; a8 i16, interrupts enabled
        pha
        rti

ptab:   .byte   $80, $BF

user:   ldx     #TARGET
        txs
:       bra     :-

; IRQ out of user mode: S is still the task's ($9000 minus nothing: the pushes were refused)
irq_h:  ldx     #KSTACK                 ; first: a stack of our own
        txs
        lda     #$01                    ; DBR = 1 (no stack needed)
        pha
        plb
        lda     #$FF
        sta     f:IRQ_STATUS
        ldx     #580                    ; ~200 us: the watchdog fires in here
:       dex
        bne     :-
        lda     nmis                    ; not taken yet
        sta     before
        lda     f:NMI_STATUS            ; but latched
        sta     status
        lda     #$00                    ; any FR_CTRL write releases the NMI
        sta     f:FR_CTRL
        nop
        nop
        lda     nmis
        sta     after
        print   m_before
        lda     before
        jsr     puthex
        print   m_status
        lda     status
        jsr     puthex
        print   m_after
        lda     after
        jsr     puthex
        print   m_mem
        ldx     #0
:       lda     f:TARGET-3,x
        jsr     puthex
        inx
        cpx     #4
        bne     :-
        jsr     crlf
        lda     before
        bne     bad
        lda     status
        cmp     #$02
        bne     bad
        lda     after
        cmp     #$01
        bne     bad
        rep     #$20
        .a16
        lda     f:TARGET-3
        cmp     #$5555
        bne     bad16
        lda     f:TARGET-1
        cmp     #$5555
        bne     bad16
        sep     #$20
        .a8
        print   m_ok
        stp
bad16:  sep     #$20
bad:    print   m_fail
        stp

nmi_h:  pha
        lda     f:NMI_STATUS
        sta     f:NMI_STATUS
        lda     f:nmis
        inc
        sta     f:nmis
        pla
        rti

m_hello:  .byte "NMIHOLD", 10, 0
m_before: .byte "NMIS BEFORE FR_CTRL ", 0
m_status: .byte " STATUS ", 0
m_after:  .byte " AFTER ", 0
m_mem:    .byte " KERNEL $8FFD-$9000 ", 0
m_ok:     .byte "OK", 10, 0
m_fail:   .byte "FAIL", 10, 0
nmis:     .byte 0
before:   .byte 0
status:   .byte 0
after:    .byte 0
