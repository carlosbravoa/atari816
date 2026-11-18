; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816: FREDDIE II test (ABORT, user mode, bank table, bank 0 window).
; Loaded at $01:0000 by the I/O processor, entered from the reset stub at $00:FF00.
; A small "kernel" sets up the table, drops to user mode with RTI, and the user code
; pokes at things it may not touch. The ABORT handler logs every fault; a COP ends the
; user run and the kernel compares the log and the memory against what must have happened.
        .p816
        .smart  -

FR_CTRL   = $00D800         ; 0 PROT_EN, 1 USER_ARM, 2 B0WIN_EN, 3 WP_VEC
PT_INDEX  = $00D801
PT_DATA   = $00D802         ; 7 VALID, 6 WRITE, 5..0 OWNER
CUR_TASK  = $00D803
AB_ADDR   = $00D804
AB_CAUSE  = $00D807         ; 0 WRITE, 1 NOT_OWNER, 2 NOT_VALID, 3 IO_PAGE, 4 WP_VEC
B0WIN     = $00D808
RAM_BANKS = $00D809
SYS_REV   = $00DE01
DBG_OUT   = $00DEF0
DBG_STAT  = $00DEF1

KSTACK    = $BFFF           ; kernel stack, above the bank 0 window
WINBANK   = $05             ; the user task's private bank 0 area
RESUME    = $F0             ; user direct page: where the handler sends the task after a fault
RETRY     = $F2             ; user direct page: non-zero = grant bank 3 and re-run instead

        .segment "CODE"
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

        ldx     #.loword(m_hello)
        jsr     puts
        lda     f:SYS_REV
        jsr     puthex
        ldx     #.loword(m_banks)
        jsr     puts
        lda     f:RAM_BANKS
        jsr     puthex
        jsr     crlf

; trampolines in bank 0 and the native COP / ABORT vectors
        lda     #$5C                    ; JML
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
        sep     #$20
        .a8

; ── 1. protected vectors: a supervisor write to $00:E000-FFFF aborts with WP_VEC ──
        lda     #$11
        sta     f:$00E100
        lda     #$08                    ; WP_VEC
        sta     f:FR_CTRL
        lda     #$22
        sta     f:$00E100               ; must abort, handler resumes at wp_resume
        nop
wp_resume:
        lda     #$00
        sta     f:FR_CTRL
        ldx     #.loword(m_wp)
        jsr     puts
        ldx     logn
        cpx     #4
        bne     wp_bad
        lda     log
        cmp     #$11                    ; WP_VEC + WRITE
        bne     wp_bad
        ldx     log+1
        cpx     #$E100
        bne     wp_bad
        lda     f:$00E100
        cmp     #$11
        bne     wp_bad
        jsr     ok
        bra     t2
wp_bad: jsr     dumplog

; ── 2. user mode ──
t2:     ldx     #0
        stx     logn
        ; memory the user must not be able to change
        lda     #$44
        sta     f:$018000
        lda     #$A5
        sta     f:$030000
        lda     #$33
        sta     f:$030010
        lda     #$66
        sta     f:$030030
        lda     #$EE
        sta     f:$000080
        sta     f:$000081
        lda     #$00
        ldx     #$000F
:       sta     f:$020000,x
        dex
        bpl     :-
        ; bank table: 0 kernel, 1 shared read-only (this code), 2 task 1, 3 task 2, 4 invalid
        ldx     #0
:       txa
        sta     f:PT_INDEX
        lda     ptab,x
        sta     f:PT_DATA
        inx
        cpx     #6
        bne     :-
        lda     #1
        sta     f:CUR_TASK
        lda     #WINBANK
        sta     f:B0WIN
        lda     #1
        sta     phase
        lda     #$07                    ; PROT_EN + USER_ARM + B0WIN_EN
        sta     f:FR_CTRL
        lda     #$01                    ; RTI frame: PBR, PC, P (a8, i16, I set)
        pha
        ldx     #.loword(user)
        phx
        lda     #$24
        pha
        rti

ptab:   .byte   $80, $BF, $C1, $C2, $00, $80

; ── user task (task 1) ──
user:   ldx     #$7FFF
        txs
        lda     #$02
        pha
        plb                             ; DBR = own bank
        stz     RETRY
        ; own bank: read and write work
        lda     #$5A
        sta     f:$020000
        lda     f:$020000
        sta     a:$0001
        ; shared read-only bank: write refused                       01 018000
        ldx     #.loword(r3)
        stx     RESUME
        lda     #$EE
        sta     f:$018000
r3:     ; other task's bank: read refused, A untouched               02 030000
        ldx     #.loword(r4)
        stx     RESUME
        lda     #$77
        lda     f:$030000
r4:     sta     a:$0002
        ; other task's bank: write refused                           03 030010
        ldx     #.loword(r5)
        stx     RESUME
        lda     #$EE
        sta     f:$030010
r5:     ; invalid bank                                               04 040000
        ldx     #.loword(r6)
        stx     RESUME
        lda     f:$040000
r6:     ; I/O page read                                              08 00DE00
        ldx     #.loword(r7)
        stx     RESUME
        lda     f:$00DE00
r7:     ; I/O page write (must not print)                            09 00DEF0
        ldx     #.loword(r8)
        stx     RESUME
        lda     #'X'
        sta     f:DBG_OUT
r8:     ; kernel part of bank 0                                      02 009000
        ldx     #.loword(r9)
        stx     RESUME
        lda     f:$009000
r9:     ; the window: direct page and stack are the task's own
        rep     #$20
        .a16
        lda     #$1234
        sta     $80
        sep     #$20
        .a8
        jsr     usub
        ; read-modify-write on a foreign bank                        02 030010
        lda     #$03
        pha
        plb
        ldx     #.loword(r11)
        stx     RESUME
        inc     a:$0010
r11:    lda     #$02
        pha
        plb
        ; block move into a foreign bank: A, X, Y, DBR come back     03 030030
        ldx     #.loword(r12)
        stx     RESUME
        rep     #$30
        .a16
        lda     #$0003
        ldx     #$0020
        ldy     #$0030
        .byte   $54, $03, $02           ; MVN  dst $03, src $02
r12:    sta     a:$0004
        stx     a:$0006
        sty     a:$0008
        sep     #$20
        .a8
        ; run code in a foreign bank                                 02 030000
        ldx     #.loword(r13)
        stx     RESUME
        jml     $030000
r13:    ; fault, kernel grants the bank, the same instruction runs again   02 030000
        lda     #$01
        sta     RETRY
        lda     #$00
        lda     f:$030000
        sta     a:$000A
        cop     #$00
usub:   rts

explog: .byte   $01, $00, $80, $01
        .byte   $02, $00, $00, $03
        .byte   $03, $10, $00, $03
        .byte   $04, $00, $00, $04
        .byte   $08, $00, $DE, $00
        .byte   $09, $F0, $DE, $00
        .byte   $02, $00, $90, $00
        .byte   $02, $10, $00, $03
        .byte   $03, $30, $00, $03
        .byte   $02, $00, $00, $03
        .byte   $02, $00, $00, $03
EXPLEN  = * - explog
expmem: .byte   $5A, $5A, $77, $00, $03, $00, $20, $00, $30, $00, $A5
EXPMEM  = * - expmem

; ── COP: end of the user run. Back on the kernel stack, checks ──
cop_h:  sep     #$20
        rep     #$10
        ldx     #KSTACK
        txs
        lda     f:FR_CTRL
        sta     f:ctrl                  ; DBR is still the user's
        lda     #$00
        sta     f:FR_CTRL
        sta     f:phase
        lda     #$01
        pha
        plb

        ldx     #.loword(m_mode)        ; COP came from user mode: USER_ARM set, MODE clear
        jsr     puts
        lda     ctrl
        cmp     #$07
        bne     :+
        jsr     ok
        bra     c2
:       jsr     puthex
        jsr     fail

c2:     ldx     #.loword(m_flt)
        jsr     puts
        ldx     logn
        cpx     #EXPLEN
        bne     flt_bad
        ldx     #0
:       lda     log,x
        cmp     explog,x
        bne     flt_bad
        inx
        cpx     #EXPLEN
        bne     :-
        jsr     ok
        bra     c3
flt_bad:
        jsr     dumplog

c3:     ldx     #.loword(m_mem)
        jsr     puts
        ldx     #0
:       lda     f:$020000,x
        cmp     expmem,x
        bne     mem_bad
        inx
        cpx     #EXPMEM
        bne     :-
        lda     f:$018000
        cmp     #$44
        bne     mem_bad
        lda     f:$030010
        cmp     #$33
        bne     mem_bad
        lda     f:$030030
        cmp     #$66
        bne     mem_bad
        jsr     ok
        bra     c4
mem_bad:
        txa
        jsr     puthex
        jsr     fail

c4:     ldx     #.loword(m_win)
        jsr     puts
        rep     #$20
        .a16
        lda     f:WINBANK*$10000+$80
        cmp     #$1234
        bne     win_bad
        lda     f:$000080
        cmp     #$EEEE
        bne     win_bad
        sep     #$20
        .a8
        jsr     ok
        bra     done
win_bad:
        sep     #$20
        jsr     fail

done:   jmp     irqtest                 ; comes back at irq_done (it resets the stack on the way)
irq_done:
        jmp     mbtest
mb_done:
        ldx     #.loword(m_done)
        jsr     puts
        stp

        .include "irqtest.inc"
        .include "mbtest.inc"

; ── ABORT handler ──
; On entry the stack holds P, PC, PBR of the aborted instruction. Logs cause + address.
        .a8
        .i16
abort_h:
        rep     #$30
        .a16
        pha
        phx                             ; 1,s X  3,s A  5,s P  6,s PC  8,s PBR
        lda     f:logn
        tax
        clc
        adc     #4
        sta     f:logn
        sep     #$20
        .a8
        lda     f:AB_CAUSE
        sta     f:log,x
        sta     f:AB_CAUSE              ; write 1 to clear
        lda     f:AB_ADDR
        sta     f:log+1,x
        lda     f:AB_ADDR+1
        sta     f:log+2,x
        lda     f:AB_ADDR+2
        sta     f:log+3,x
        lda     f:phase
        beq     ab_sup
        cmp     #2
        bne     :+
        ldx     #KSTACK                 ; phase 2 (preemption test): the kernel takes over
        txs
        lda     #$00
        sta     f:FR_CTRL
        lda     #$01
        pha
        plb
        jml     pre_check
:
        lda     RETRY                   ; user direct page, through the window
        beq     ab_skip
        stz     RETRY
        lda     #3                      ; give bank 3 to task 1; RTI re-runs the instruction
        sta     f:PT_INDEX
        lda     #$C1
        sta     f:PT_DATA
        bra     ab_out
ab_skip:
        rep     #$20
        .a16
        lda     RESUME
        sta     6,s
        sep     #$20
        .a8
        lda     #$01
        sta     8,s
        bra     ab_out
ab_sup: rep     #$20
        .a16
        lda     #.loword(wp_resume)
        sta     6,s
ab_out: rep     #$30
        plx
        pla
        rti

; ── helpers (kernel, a8 i16, DBR = program bank) ──
        .a8
        .i16
ok:     ldx     #.loword(m_ok)
        bra     puts
fail:   ldx     #.loword(m_fail)
        bra     puts
dumplog:
        ldx     #.loword(m_fail)
        jsr     puts
        ldx     #0
:       cpx     logn
        bcs     :+
        cpx     #48
        bcs     :+
        lda     log,x
        phx
        jsr     puthex
        plx
        inx
        bra     :-
:       jmp     crlf

crlf:   lda     #10
putc:   pha
:       lda     f:DBG_STAT
        bmi     :-
        pla
        sta     f:DBG_OUT
        rts

puts:   lda     a:0,x
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

m_hello: .byte "ATARI816 SELF TEST", 10, "REV ", 0
m_banks: .byte " BANKS-1 ", 0
m_wp:    .byte "WPVEC ", 0
m_mode:  .byte "MODE ", 0
m_flt:   .byte "FAULTS ", 0
m_mem:   .byte "MEMORY ", 0
m_win:   .byte "WINDOW ", 0
m_ok:    .byte "OK", 10, 0
m_fail:  .byte "FAIL ", 10, 0
m_done:  .byte "DONE", 10, 0

phase:  .byte 0
ctrl:   .byte 0
logn:   .word 0
log:    .res 64
