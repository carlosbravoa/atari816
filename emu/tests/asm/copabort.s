; Protection check: a user task points S into kernel memory and executes COP. COP's first
; push is refused. Before the RTL fix, COP's vector pull still entered supervisor mode, so
; the ABORT entry pushed PBR/PC/P into kernel memory and the handler saw USER_ARM = 0
; (printed "FR_CTRL 05 ... A4C10001"). Fixed in a816_sys.sv (vpull ignored while wr_block):
; now FR_CTRL 07 and the canary $55555555 is intact.
        .include "common.inc"

FR_CTRL   = $00D800
PT_INDEX  = $00D801
PT_DATA   = $00D802
CUR_TASK  = $00D803
AB_CAUSE  = $00D807
B0WIN     = $00D808
KSTACK    = $BFFF
TARGET    = $9000               ; kernel part of bank 0

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
        lda     #$5C                    ; COP and ABORT trampolines
        sta     f:$00E000
        sta     f:$00E004
        lda     #$01
        sta     f:$00E003
        sta     f:$00E007
        rep     #$20
        .a16
        lda     #.loword(cop_h)
        sta     f:$00E001
        lda     #.loword(abort_h)
        sta     f:$00E005
        lda     #$E000
        sta     f:$00FFE4
        lda     #$E004
        sta     f:$00FFE8
        lda     #$5555                  ; canary in kernel memory
        sta     f:TARGET-3
        sta     f:TARGET-1
        sep     #$20
        .a8
        ldx     #0                      ; bank 0 kernel, bank 1 shared read-only, bank 5 window
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
        lda     #$07                    ; PROT_EN + USER_ARM + B0WIN_EN
        sta     f:FR_CTRL
        lda     #$01
        pha
        ldx     #.loword(user)
        phx
        lda     #$24
        pha
        rti

ptab:   .byte   $80, $BF

user:   ldx     #TARGET                 ; any task can load S
        txs
        cop     #$00

abort_h:
        lda     f:FR_CTRL               ; first thing: what does the handler see?
        sta     f:ctrl
        lda     f:AB_CAUSE
        sta     f:cause
        ldx     #KSTACK
        txs
        lda     #$00
        sta     f:FR_CTRL
        phk
        plb
        print   m_ctrl
        lda     ctrl
        jsr     puthex
        print   m_cause
        lda     cause
        jsr     puthex
        print   m_mem
        ldx     #0
:       lda     f:TARGET-3,x
        jsr     puthex
        inx
        cpx     #4
        bne     :-
        jsr     crlf
        stp

cop_h:  print   m_cop                   ; not reached: the COP itself is aborted
        stp

m_hello: .byte "COPABORT", 10, 0
m_ctrl:  .byte "FR_CTRL ", 0
m_cause: .byte " CAUSE ", 0
m_mem:   .byte " KERNEL $8FFD-$9000 ", 0
m_cop:   .byte "COP HANDLER", 10, 0
ctrl:    .byte 0
cause:   .byte 0
