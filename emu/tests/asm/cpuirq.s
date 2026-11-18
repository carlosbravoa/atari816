; emu816 interrupt test (what SingleStepTests cannot cover): native COP and BRK frames,
; an MVN interrupted many times by a 50 us timer IRQ (one byte per iteration, resumed
; after RTI), WAI with I clear servicing the IRQ, and the NMI edge rule.
        .include "common.inc"

TM0_RELOAD = $00DE10
TM0_CTRL   = $00DE13
NMI_STATUS = $00DE0A
WATCHDOG   = $00DE1C
SRC        = $030000
DST        = $040000
LEN        = $2000

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
        ; trampolines $00:E000 COP, E004 BRK, E008 IRQ, E00C NMI
        ldx     #0
:       lda     tramp,x
        sta     f:$00E000,x
        inx
        cpx     #16
        bne     :-
        rep     #$20
        .a16
        lda     #$E000
        sta     f:$00FFE4
        lda     #$E004
        sta     f:$00FFE6
        lda     #$E008
        sta     f:$00FFEE
        lda     #$E00C
        sta     f:$00FFEA
        sep     #$20
        .a8

; ── COP: signature byte, stacked P/PC/PBR, D cleared, I set ──
        print   m_cop
        sed
        cli
        lda     #$77
        cop     #$42
        .a8
        cld
        sei
        cmp     #$77                    ; A preserved by the handler
        bne     cop_bad
        lda     sig
        cmp     #$42
        bne     cop_bad
        lda     pflag                   ; P inside the handler: I set, D clear
        and     #$0C
        cmp     #$04
        bne     cop_bad
        lda     spbr
        cmp     #$01
        bne     cop_bad
        print   m_ok
        bra     t_brk
cop_bad: print  m_fail

; ── BRK: native vector $FFE6 ──
t_brk:  print   m_brk
        stz     sig
        brk     #$99
        lda     sig
        cmp     #$99
        bne     :+
        print   m_ok
        bra     t_mvn
:       print   m_fail

; ── MVN interrupted by a 50 us repeating timer ──
t_mvn:  print   m_mvn
        rep     #$30
        .a16
        ldx     #0
:       txa
        eor     #$5AA5
        sta     f:SRC,x
        lda     #0
        sta     f:DST,x
        inx
        inx
        cpx     #LEN
        bne     :-
        sep     #$20
        .a8
        stz     ticks
        stz     ticks+1
        rep     #$20
        .a16
        lda     #50
        sta     f:TM0_RELOAD
        sep     #$20
        .a8
        lda     #0
        sta     f:TM0_RELOAD+2
        lda     #$04
        sta     f:IRQ_EN
        lda     #$03
        sta     f:TM0_CTRL
        cli
        rep     #$30
        .a16
        lda     #LEN-1
        ldx     #.loword(SRC)
        ldy     #.loword(DST)
        mvn     #^DST, #^SRC
        sep     #$20
        .a8
        sei
        phk
        plb
        lda     #$00
        sta     f:TM0_CTRL
        rep     #$30
        .a16
        ldx     #0
:       lda     f:SRC,x
        cmp     f:DST,x
        bne     mvn_bad16
        inx
        inx
        cpx     #LEN
        bne     :-
        lda     ticks                   ; 8192 bytes x 7 cycles + a write and 1/8 fill each (the
        cmp     #150                    ; classic machine runs: about 17 cycles a byte, 10 ms):
        bcc     mvn_bad16               ; ~180 ticks (79 with ideal cycles, --ideal-timing)
        cmp     #210
        bcs     mvn_bad16
        sep     #$20
        .a8
        print   m_ok
        bra     t_wai
mvn_bad16:
        sep     #$20
        .a8
        print   m_fail

; ── WAI with I clear: the IRQ is taken, then execution continues after WAI ──
t_wai:
        print   m_wai
        stz     ticks
        lda     #$01                    ; one shot
        sta     f:TM0_CTRL
        cli
        wai
        sei
        lda     ticks
        cmp     #1
        bne     :+
        print   m_ok
        bra     t_nmi
:       print   m_fail

; ── NMI: taken on the edge; a still-set NMI_STATUS does not re-trigger ──
t_nmi:  print   m_nmi
        stz     nmis
        lda     #$5A                    ; watchdog fires after 2 s
        sta     f:WATCHDOG
:       lda     nmis
        beq     :-
        ldx     #2000                   ; spin a while: no second NMI while status stays set
:       dex
        bne     :-
        lda     nmis
        cmp     #1
        bne     :+
        lda     #$03
        sta     f:NMI_STATUS            ; clear it now
        print   m_ok
        bra     fin
:       print   m_fail
fin:    print   m_done
        stp

; ── handlers (native, a8/i16 on entry as interrupted code) ──
cop_h:  pha                             ; 1,s A  2,s P  3,s PC  5,s PBR
        php
        pla
        sta     f:pflag                 ; P as the handler sees it
        lda     5,s
        sta     f:spbr
        rep     #$20
        .a16
        lda     3,s                     ; return address = after the signature byte
        dec
        sta     f:tmpw
        sep     #$20
        .a8
        phb
        lda     #$01
        pha
        plb
        ldx     tmpw
        lda     a:0,x                   ; the signature byte
        sta     sig
        plb
        pla
        rti

brk_h:  pha
        phx
        phb
        lda     #$01
        pha
        plb
        rep     #$20
        .a16
        lda     6,s                     ; 1,s B  2,s X  4,s A  5,s P  6,s PC
        dec
        tax
        sep     #$20
        .a8
        lda     a:0,x
        sta     sig
        plb
        plx
        pla
        rti

irq_h:  rep     #$20
        .a16
        pha
        sep     #$20
        .a8
        lda     f:IRQ_STATUS
        sta     f:IRQ_STATUS
        rep     #$20
        .a16
        lda     f:ticks
        inc
        sta     f:ticks
        pla
        rti
        .a8

nmi_h:  pha
        lda     f:nmis
        inc
        sta     f:nmis
        pla
        rti                             ; NMI_STATUS left set on purpose

tramp:  jml     cop_h
        jml     brk_h
        jml     irq_h
        jml     nmi_h

m_hello: .byte "CPUIRQ", 10, 0
m_cop:   .byte "COP ", 0
m_brk:   .byte "BRK ", 0
m_mvn:   .byte "MVN+IRQ ", 0
m_wai:   .byte "WAI ", 0
m_nmi:   .byte "NMI EDGE ", 0
m_ok:    .byte "OK", 10, 0
m_fail:  .byte "FAIL", 10, 0
m_done:  .byte "DONE", 10, 0
sig:     .byte 0
pflag:   .byte 0
spbr:    .byte 0
tmpw:    .word 0
ticks:   .word 0
nmis:    .byte 0
