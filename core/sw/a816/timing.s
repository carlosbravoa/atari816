; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
;
; Atari816: CPU timing by instruction mix, for calibrating emu816's time model against the board.
; python3 tools/atari.py run816 sw/a816/TIMING.BIN --seconds 40   (then restore /A816.BIN)
; emu816 --sd DIR TIMING.BIN
;
; Every test is a loop of a known instruction mix, timed with UPTIME. The emulator's time is
; the ideal cycle count (UPTIME = 32 x cycles / 459), so board / emulator per test gives the
; stall cycles of that kind of access. Four passes:
;   P0  classic machine frozen, Marga off
;   P1  frozen, Marga mode 0 640x360x8, stride 1024 (the desktop)
;   P2  classic machine running, Marga mode 0 (the video fetch then uses 8-byte bursts)
;   P3  frozen, Marga mode 2 320x180x8 (full-screen games)
;   P5  P1 with the pointer on and KB_ROUTE = 0 (keys to the 65C816), as Horizon's desktop
;   P6  P1 with protection on and the bank 0 window (bank $60) holding the stack and direct page,
;       and the framebuffer at $6A0000 (where Horizon's tasks and desktop are)
;   P4  P0 again (the I/O processor is busier during P0, just after the restart)
; Four passes, P0 again as P4, then P5 and P6.
; Each line: "Tnn name HHHHHHHH" = microseconds (hex). Then TIMING DONE.
        .p816
        .smart  -

SYS_REV     = $00DE01
SV_CTRL     = $00DC00
SV_STATUS   = $00DC01
IRQ_STATUS  = $00DE08
IRQ_EN      = $00DE09
TM0_RELOAD  = $00DE10
TM0_CTRL    = $00DE13
UPTIME      = $00DE18
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1
NV_CTRL     = $00D900
NV_BASE     = $00D901
NV_STRIDE   = $00D904
BL_SRC      = $00DA00
BL_SSTR     = $00DA03
BL_DST      = $00DA05
BL_DSTR     = $00DA08
BL_W        = $00DA0A
BL_H        = $00DA0C
BL_FG       = $00DA0E
BL_KEY      = $00DA10
BL_OP       = $00DA11
BL_FLAGS    = $00DA12
BL_CTRL     = $00DA13
MB_REQ_BASE = $00DD00
MB_REQ_HEAD = $00DD03
MB_RSP_BASE = $00DD05
MB_RSP_HEAD = $00DD08
MB_RSP_TAIL = $00DD09
MB_STATUS   = $00DD0A
REQ_RING    = $0E0000
RSP_RING    = $0E1000
KB_ROUTE    = $00DE20
FR_CTRL     = $00D800
PT_INDEX    = $00D801
PT_DATA     = $00D802
B0WIN       = $00D808
FB          = $200000           ; framebuffer, banks $20-$25

; direct page
dpv     = $20                   ; scratch for DP tests
t0      = $30                   ; 4
t1      = $34                   ; 4
cnt     = $38                   ; 2
pass    = $3A                   ; 1
nirq    = $3C                   ; 2
tmp     = $3E                   ; 2
mbok    = $40                   ; 1
ptr     = $44                   ; 3
sv      = $48                   ; 2

        .segment "CODE"
        .a8
        .i16
start:  clc
        xce
        rep     #$10
        sep     #$20
        .a8
        ldx     #$0EFF                  ; stack and direct page away from the code's cache lines
        txs
        phk
        plb
        rep     #$20
        .a16
        lda     #$0F00
        tcd
        sep     #$20
        .a8
        ldx     #.loword(m_hello)
        jsr     puts
        lda     f:SYS_REV
        jsr     puthex
        jsr     crlf
        jsr     vecinit
        jsr     quiet
        jsr     mbinit
        jsr     hiinit
        ; clear the framebuffer (Ali)
        lda     f:SYS_REV
        cmp     #$08
        bcc     :+
        lda     #$00
        sta     f:BL_FG
        sta     f:BL_OP
        sta     f:BL_FLAGS
        rep     #$20
        .a16
        lda     #.loword(FB)
        sta     f:BL_DST
        lda     #1024
        sta     f:BL_DSTR
        lda     #640
        sta     f:BL_W
        lda     #360
        sta     f:BL_H
        sep     #$20
        .a8
        lda     #^FB
        sta     f:BL_DST+2
        lda     #1
        sta     f:BL_CTRL
        jsr     bwait
:
        stz     pass
ploop:  lda     #'P'
        jsr     putc
        lda     pass
        jsr     puthex
        jsr     crlf
        jsr     setcfg
        ldx     #0
tloop:  stx     tmp
        lda     tests+3,x
        beq     pdone                   ; end of table (name pointer high byte 0)
        rep     #$20
        .a16
        lda     tests+2,x               ; name
        tax
        sep     #$20
        .a8
        jsr     puts
        lda     #' '
        jsr     putc
        ldx     tmp
        jsr     tstart
        jsr     (tests,x)
        jsr     tstop
        ldx     tmp
        inx
        inx
        inx
        inx
        bra     tloop
pdone:  inc     pass
        lda     pass
        cmp     #7
        bcs     :+
        jmp     ploop
:       lda     #0
        sta     f:FR_CTRL
        sta     f:NV_CTRL
        sta     f:SV_CTRL
        lda     #1
        sta     f:KB_ROUTE
        ldx     #.loword(m_done)
        jsr     puts
        stp

; pass configuration
setcfg: lda     pass
        cmp     #6
        bne     setcf2
        ; P6: P1 with FREDDIE II's protection on and the bank 0 window at bank $10 (as Horizon's
        ; tasks: direct page and stack in the window)
        ldx     #0
:       txa
        sta     f:PT_INDEX
        lda     #$FF                    ; VALID, WRITE, owner 63
        sta     f:PT_DATA
        inx
        cpx     #256
        bne     :-
        rep     #$30
        .a16
        lda     #$7FFF                  ; the window's contents: bank 0's
        ldx     #0
        ldy     #0
        mvn     #$00, #$60
        sep     #$20
        .a8
        phk
        plb
        lda     #$60
        sta     f:B0WIN
        lda     #$05                    ; PROT_EN, B0WIN_EN
        sta     f:FR_CTRL
        lda     #1
        sta     pass
        jsr     setcf2
        lda     #6
        sta     pass
        lda     #$6A
        sta     f:NV_BASE+2
        rts
setcf2: lda     #0
        sta     f:NV_CTRL
        lda     pass
        cmp     #2
        beq     :+
        lda     #$04                    ; freeze
        bra     :++
:       lda     #$00                    ; run
:       sta     f:SV_CTRL
        lda     pass
        beq     @off
        cmp     #4
        beq     @off
        rep     #$20
        .a16
        lda     #1024
        sta     f:NV_STRIDE
        sep     #$20
        .a8
        lda     #0
        sta     f:NV_BASE
        lda     #>.loword(FB)
        sta     f:NV_BASE+1
        lda     #^FB
        sta     f:NV_BASE+2
        lda     pass
        cmp     #3
        beq     :+
        cmp     #5
        beq     :++
        lda     #$01                    ; ENABLE, mode 0
        bra     :+++
:       lda     #$05                    ; ENABLE, mode 2
        bra     :++
:       lda     #0                      ; P5: as the desktop: pointer on, keys to the 65C816
        sta     f:KB_ROUTE
        lda     #$09                    ; ENABLE, mode 0, POINTER_EN
:       sta     f:NV_CTRL
@off:   ; settle: two frames
        ldx     #40000
:       dex
        bne     :-
        ldx     #.loword(m_frz)         ; SV_STATUS bit 0: the classic machine is frozen (the
        jsr     puts                    ; video fetch then uses 16-byte bursts)
        lda     f:SV_STATUS
        jsr     puthex
        jmp     crlf

; ── tests: each returns with A8, I16, DBR = $01, D = 0 ──
tests:  .word   .loword(t_reg), .loword(n_reg)
        .word   .loword(t_dpr), .loword(n_dpr)
        .word   .loword(t_dpw), .loword(n_dpw)
        .word   .loword(t_dpw16), .loword(n_dpw16)
        .word   .loword(t_lrhit), .loword(n_lrhit)
        .word   .loword(t_lrseq), .loword(n_lrseq)
        .word   .loword(t_lrmiss), .loword(n_lrmiss)
        .word   .loword(t_lwseq), .loword(n_lwseq)
        .word   .loword(t_lw16), .loword(n_lw16)
        .word   .loword(t_stack), .loword(n_stack)
        .word   .loword(t_jsr), .loword(n_jsr)
        .word   .loword(t_mvn), .loword(n_mvn)
        .word   .loword(t_mvn0), .loword(n_mvn0)
        .word   .loword(t_ior), .loword(n_ior)
        .word   .loword(t_iow), .loword(n_iow)
        .word   .loword(t_codehi), .loword(n_codehi)
        .word   .loword(t_icmiss), .loword(n_icmiss)
        .word   .loword(t_irq), .loword(n_irq)
        .word   .loword(t_cop), .loword(n_cop)
        .word   .loword(t_bfill), .loword(n_bfill)
        .word   .loword(t_bcopy), .loword(n_bcopy)
        .word   .loword(t_bkey), .loword(n_bkey)
        .word   .loword(t_mbox), .loword(n_mbox)
        .word   .loword(t_sieve), .loword(n_sieve)
        .word   .loword(t_wn0), .loword(n_wn0)
        .word   .loword(t_wn1), .loword(n_wn1)
        .word   .loword(t_wn2), .loword(n_wn2)
        .word   .loword(t_wn3), .loword(n_wn3)
        .word   .loword(t_wn4), .loword(n_wn4)
        .word   .loword(t_wn5), .loword(n_wn5)
        .word   .loword(t_wn6), .loword(n_wn6)
        .word   .loword(t_wn8), .loword(n_wn8)
        .word   .loword(t_fn0), .loword(n_fn0)
        .word   .loword(t_fn2), .loword(n_fn2)
        .word   .loword(t_fn4), .loword(n_fn4)
        .word   .loword(t_fn8), .loword(n_fn8)
        .word   .loword(t_wr1), .loword(n_wr1)
        .word   .loword(t_wr2), .loword(n_wr2)
        .word   .loword(t_cbw), .loword(n_cbw)
        .word   .loword(t_cbr), .loword(n_cbr)
        .word   .loword(t_cbt), .loword(n_cbt)
        .word   .loword(t_x1), .loword(n_x1)
        .word   .loword(t_x2), .loword(n_x2)
        .word   .loword(t_al0), .loword(n_al0)
        .word   .loword(t_al1), .loword(n_al1)
        .word   .loword(t_al2), .loword(n_al2)
        .word   .loword(t_al3), .loword(n_al3)
        .word   .loword(t_al4), .loword(n_al4)
        .word   .loword(t_al5), .loword(n_al5)
        .word   .loword(t_al6), .loword(n_al6)
        .word   .loword(t_al7), .loword(n_al7)
        .word   0, 0

n_reg:   .byte "T01 REG", 0
n_dpr:   .byte "T02 DPR", 0
n_dpw:   .byte "T03 DPW", 0
n_dpw16: .byte "T04 DPW16", 0
n_lrhit: .byte "T05 LRHIT", 0
n_lrseq: .byte "T06 LRSEQ", 0
n_lrmiss: .byte "T07 LRMISS", 0
n_lwseq: .byte "T08 LWSEQ", 0
n_lw16:  .byte "T09 LW16", 0
n_stack: .byte "T10 STACK", 0
n_jsr:   .byte "T11 JSR", 0
n_mvn:   .byte "T12 MVN", 0
n_mvn0:  .byte "T13 MVN0", 0
n_ior:   .byte "T14 IOR", 0
n_iow:   .byte "T15 IOW", 0
n_codehi: .byte "T16 CODEHI", 0
n_icmiss: .byte "T17 ICMISS", 0
n_irq:   .byte "T18 IRQ", 0
n_cop:   .byte "T19 COP", 0
n_bfill: .byte "T20 BFILL", 0
n_bcopy: .byte "T21 BCOPY", 0
n_bkey:  .byte "T22 BKEY", 0
n_mbox:  .byte "T23 MBOX", 0
n_sieve: .byte "T24 SIEVE", 0
n_al0:   .byte "TA0 DPWALIGN", 0
n_al1:   .byte "TA1 DPWALIGN", 0
n_al2:   .byte "TA2 DPWALIGN", 0
n_al3:   .byte "TA3 DPWALIGN", 0
n_al4:   .byte "TA4 DPWALIGN", 0
n_al5:   .byte "TA5 DPWALIGN", 0
n_al6:   .byte "TA6 DPWALIGN", 0
n_al7:   .byte "TA7 DPWALIGN", 0
n_x1:    .byte "TX1 WRFILL", 0
n_x2:    .byte "TX2 INCMISS", 0
n_cbw:   .byte "TC1 DPW+FILL", 0
n_cbr:   .byte "TC2 LRMISS+FILL", 0
n_cbt:   .byte "TC3 FILLALONE", 0
n_wn0:   .byte "TW0 WNOP", 0
n_wn1:   .byte "TW1 WNOP", 0
n_wn2:   .byte "TW2 WNOP", 0
n_wn3:   .byte "TW3 WNOP", 0
n_wn4:   .byte "TW4 WNOP", 0
n_wn5:   .byte "TW5 WNOP", 0
n_wn6:   .byte "TW6 WNOP", 0
n_wn8:   .byte "TW8 WNOP", 0
n_fn0:   .byte "TF0 FNOP", 0
n_fn2:   .byte "TF2 FNOP", 0
n_fn4:   .byte "TF4 FNOP", 0
n_fn8:   .byte "TF8 FNOP", 0
n_wr1:   .byte "TR1 WLDA", 0
n_wr2:   .byte "TR2 WLDA", 0

; 65536 x (DEX, BNE): pure cache hits, no data access
t_reg:  ldx     #0
:       dex
        bne     :-
        rts

; 4096 x 8 direct-page reads (bank 0)
t_dpr:  ldy     #4096
:       lda     dpv
        lda     dpv
        lda     dpv
        lda     dpv
        lda     dpv
        lda     dpv
        lda     dpv
        lda     dpv
        dey
        bne     :-
        rts

t_dpw:  ldy     #4096
:       sta     dpv
        sta     dpv
        sta     dpv
        sta     dpv
        sta     dpv
        sta     dpv
        sta     dpv
        sta     dpv
        dey
        bne     :-
        rts

t_dpw16: rep    #$20
        .a16
        ldy     #4096
:       sta     dpv
        sta     dpv
        sta     dpv
        sta     dpv
        sta     dpv
        sta     dpv
        sta     dpv
        sta     dpv
        dey
        bne     :-
        sep     #$20
        .a8
        rts

; 4096 x 8 long reads of one address in bank 2 (hits)
t_lrhit: ldy    #4096
:       lda     f:$024440
        lda     f:$024440
        lda     f:$024440
        lda     f:$024440
        lda     f:$024440
        lda     f:$024440
        lda     f:$024440
        lda     f:$024440
        dey
        bne     :-
        rts

; 32 KB read sequentially in bank 2: one line fill per 8 reads
t_lrseq: ldx    #0
:       lda     f:$020000,x
        lda     f:$020001,x
        lda     f:$020002,x
        lda     f:$020003,x
        lda     f:$020004,x
        lda     f:$020005,x
        lda     f:$020006,x
        lda     f:$020007,x
        rep     #$21
        .a16
        txa
        adc     #8
        tax
        sep     #$20
        .a8
        cpx     #$8000
        bne     :-
        rts

; 4096 reads 8 bytes apart in bank 2: every read a line fill
t_lrmiss: ldx   #0
:       lda     f:$020000,x
        lda     f:$020008,x
        lda     f:$020010,x
        lda     f:$020018,x
        lda     f:$020020,x
        lda     f:$020028,x
        lda     f:$020030,x
        lda     f:$020038,x
        rep     #$21
        .a16
        txa
        adc     #64
        tax
        sep     #$20
        .a8
        cpx     #$8000
        bne     :-
        rts

; 32 KB written sequentially in bank 3 (8-bit stores)
t_lwseq: ldx    #0
:       sta     f:$030000,x
        sta     f:$030001,x
        sta     f:$030002,x
        sta     f:$030003,x
        sta     f:$030004,x
        sta     f:$030005,x
        sta     f:$030006,x
        sta     f:$030007,x
        rep     #$21
        .a16
        txa
        adc     #8
        tax
        sep     #$20
        .a8
        cpx     #$8000
        bne     :-
        rts

; 32 KB written with 16-bit stores in bank 3
t_lw16: rep     #$20
        .a16
        ldx     #0
:       sta     f:$030000,x
        sta     f:$030002,x
        sta     f:$030004,x
        sta     f:$030006,x
        txa
        clc
        adc     #8
        tax
        cpx     #$8000
        bne     :-
        sep     #$20
        .a8
        rts

; 4096 x 4 (PHA, PLA)
t_stack: ldy    #4096
:       pha
        pla
        pha
        pla
        pha
        pla
        pha
        pla
        dey
        bne     :-
        rts

; 4096 x 4 (JSR, RTS)
t_jsr:  ldy     #4096
:       jsr     j_rts
        jsr     j_rts
        jsr     j_rts
        jsr     j_rts
        dey
        bne     :-
        rts
j_rts:  rts

; MVN 32 KB, bank 2 -> bank 3
t_mvn:  rep     #$30
        .a16
        lda     #$7FFF
        ldx     #$0000
        ldy     #$0000
        mvn     #$02, #$03
        sep     #$20
        .a8
        phk
        plb
        rts

; MVN 16 KB inside bank 0
t_mvn0: rep     #$30
        .a16
        lda     #$3FFF
        ldx     #$2000
        ldy     #$6000
        mvn     #$00, #$00
        sep     #$20
        .a8
        phk
        plb
        rts

; 4096 x 8 I/O reads (SYS_REV)
t_ior:  ldy     #4096
:       lda     f:SYS_REV
        lda     f:SYS_REV
        lda     f:SYS_REV
        lda     f:SYS_REV
        lda     f:SYS_REV
        lda     f:SYS_REV
        lda     f:SYS_REV
        lda     f:SYS_REV
        dey
        bne     :-
        rts

; 4096 x 8 I/O writes (BL_KEY, harmless)
t_iow:  ldy     #4096
:       sta     f:BL_KEY
        sta     f:BL_KEY
        sta     f:BL_KEY
        sta     f:BL_KEY
        sta     f:BL_KEY
        sta     f:BL_KEY
        sta     f:BL_KEY
        sta     f:BL_KEY
        dey
        bne     :-
        rts

; the DPR loop, run from bank 5
t_codehi:
        jsl     $050000
        phk
        plb
        rts

; 4 x a 16 KB straight run of LDA dp in bank 6 (an instruction-cache miss every 4)
t_icmiss:
        jsl     $060000
        jsl     $060000
        jsl     $060000
        jsl     $060000
        rts

; 65536 x (DEX, BNE) with TIMER0 interrupting every 25 us
t_irq:  stz     nirq
        stz     nirq+1
        rep     #$20
        .a16
        lda     #25
        sta     f:TM0_RELOAD
        sep     #$20
        .a8
        lda     #0
        sta     f:TM0_RELOAD+2
        lda     #$04
        sta     f:IRQ_EN
        lda     #$03                    ; RUN, REPEAT
        sta     f:TM0_CTRL
        cli
        ldx     #0
:       dex
        bne     :-
        sei
        lda     #0
        sta     f:TM0_CTRL
        sta     f:IRQ_EN
        lda     #$04
        sta     f:IRQ_STATUS
        rts

; 1024 x 8 COP with an RTI handler
t_cop:  ldy     #1024
:       cop     $00
        cop     $00
        cop     $00
        cop     $00
        cop     $00
        cop     $00
        cop     $00
        cop     $00
        dey
        bne     :-
        rts

; Ali: 4 fills of 640 x 200 (stride 1024) in bank 8, waiting for each
t_bfill: lda    f:SYS_REV
        cmp     #$08
        bcs     :+
        rts
:       lda     #0
        sta     f:BL_OP
        sta     f:BL_FLAGS
        lda     #$55
        sta     f:BL_FG
        rep     #$20
        .a16
        lda     #1024
        sta     f:BL_DSTR
        lda     #640
        sta     f:BL_W
        lda     #200
        sta     f:BL_H
        lda     #0
        sta     f:BL_DST
        sep     #$20
        .a8
        lda     #$08
        sta     f:BL_DST+2
        ldy     #4
:       lda     #1
        sta     f:BL_CTRL
        jsr     bwait
        dey
        bne     :-
        rts

; Ali: 4 copies of 320 x 100 from bank 2 to bank 8
t_bcopy: lda    f:SYS_REV
        cmp     #$08
        bcs     :+
        rts
:       lda     #1
        sta     f:BL_OP
        lda     #0
        sta     f:BL_FLAGS
        rep     #$20
        .a16
        lda     #1024
        sta     f:BL_DSTR
        lda     #320
        sta     f:BL_SSTR
        sta     f:BL_W
        lda     #100
        sta     f:BL_H
        lda     #0
        sta     f:BL_DST
        sta     f:BL_SRC
        sep     #$20
        .a8
        lda     #$08
        sta     f:BL_DST+2
        lda     #$02
        sta     f:BL_SRC+2
        ldy     #4
:       lda     #1
        sta     f:BL_CTRL
        jsr     bwait
        dey
        bne     :-
        rts

; Ali: 256 keyed 16 x 16 copies, one after the other (DST and START written per blit)
t_bkey: lda     f:SYS_REV
        cmp     #$08
        bcs     :+
        rts
:       lda     #2
        sta     f:BL_OP
        lda     #0
        sta     f:BL_FLAGS
        sta     f:BL_KEY
        rep     #$20
        .a16
        lda     #1024
        sta     f:BL_DSTR
        lda     #16
        sta     f:BL_SSTR
        sta     f:BL_W
        sta     f:BL_H
        lda     #0
        sta     f:BL_SRC
        sep     #$20
        .a8
        lda     #$02
        sta     f:BL_SRC+2
        lda     #$08
        sta     f:BL_DST+2
        ldx     #0
:       jsr     bwait
        rep     #$20
        .a16
        txa
        asl
        asl
        asl
        asl
        sta     f:BL_DST
        sep     #$20
        .a8
        lda     #1
        sta     f:BL_CTRL
        inx
        cpx     #256
        bne     :-
        jsr     bwait
        rts

bwait:  lda     f:BL_CTRL
        lsr
        bcs     bwait
        rts

; 32 mailbox round trips of an unknown op (answered $82 at once)
t_mbox: lda     mbok
        bne     :+
        rts
:       ldy     #32
@l:     phy
        rep     #$20
        .a16
        lda     f:MB_REQ_HEAD
        and     #$00FF
        asl
        asl
        asl
        asl
        tax
        sep     #$20
        .a8
        lda     #$7E                    ; no such op
        sta     f:REQ_RING,x
        lda     #0
        ldy     #15
:       inx
        sta     f:REQ_RING,x
        dey
        bne     :-
        lda     f:MB_REQ_HEAD
        inc
        sta     f:MB_REQ_HEAD
:       lda     f:MB_RSP_HEAD
        cmp     f:MB_RSP_TAIL
        beq     :-
        lda     f:MB_RSP_TAIL
        inc
        sta     f:MB_RSP_TAIL
        ply
        dey
        bne     @l
        rts

;  sieve of Eratosthenes over 8192 bytes in bank 4, 4 times (a realistic mix)
t_sieve: lda    #4
        sta     cnt
@rep:   rep     #$30
        .a16
        ldx     #8190
        lda     #$0101
:       sta     f:$040000,x
        dex
        dex
        bpl     :-
        ldx     #2
@i:     stx     sv
        lda     f:$040000,x
        and     #$00FF
        beq     @nx
        txa
        asl
        tay                             ; j = 2i
@j:     cpy     #8192
        bcs     @nx
        tyx
        sep     #$20
        .a8
        lda     #0
        sta     f:$040000,x
        rep     #$21
        .a16
        tya
        adc     sv
        tay
        bra     @j
@nx:    ldx     sv
        inx
        cpx     #8192
        bcc     @i
        sep     #$20
        .a8
        dec     cnt
        bne     @rep
        rts

; 4096 x 8 (STA dp + 0 NOP)
t_wn0:  ldy     #4096
:       .repeat 8
        sta     dpv
        .repeat 0
        nop
        .endrepeat
        .endrepeat
        dey
        beq     :+
        jmp     :-
:       rts

; 4096 x 8 (STA dp + 1 NOP)
t_wn1:  ldy     #4096
:       .repeat 8
        sta     dpv
        .repeat 1
        nop
        .endrepeat
        .endrepeat
        dey
        beq     :+
        jmp     :-
:       rts

; 4096 x 8 (STA dp + 2 NOP)
t_wn2:  ldy     #4096
:       .repeat 8
        sta     dpv
        .repeat 2
        nop
        .endrepeat
        .endrepeat
        dey
        beq     :+
        jmp     :-
:       rts

; 4096 x 8 (STA dp + 3 NOP)
t_wn3:  ldy     #4096
:       .repeat 8
        sta     dpv
        .repeat 3
        nop
        .endrepeat
        .endrepeat
        dey
        beq     :+
        jmp     :-
:       rts

; 4096 x 8 (STA dp + 4 NOP)
t_wn4:  ldy     #4096
:       .repeat 8
        sta     dpv
        .repeat 4
        nop
        .endrepeat
        .endrepeat
        dey
        beq     :+
        jmp     :-
:       rts

; 4096 x 8 (STA dp + 5 NOP)
t_wn5:  ldy     #4096
:       .repeat 8
        sta     dpv
        .repeat 5
        nop
        .endrepeat
        .endrepeat
        dey
        beq     :+
        jmp     :-
:       rts

; 4096 x 8 (STA dp + 6 NOP)
t_wn6:  ldy     #4096
:       .repeat 8
        sta     dpv
        .repeat 6
        nop
        .endrepeat
        .endrepeat
        dey
        beq     :+
        jmp     :-
:       rts

; 4096 x 8 (STA dp + 8 NOP)
t_wn8:  ldy     #4096
:       .repeat 8
        sta     dpv
        .repeat 8
        nop
        .endrepeat
        .endrepeat
        dey
        beq     :+
        jmp     :-
:       rts

; 4096 reads 8 bytes apart in bank 2, each + 0 NOP
t_fn0:  ldx     #0
:       .repeat 8, I
        lda     f:$020000+I*8,x
        .repeat 0
        nop
        .endrepeat
        .endrepeat
        rep     #$21
        .a16
        txa
        adc     #64
        tax
        sep     #$20
        .a8
        cpx     #$8000
        beq     :+
        jmp     :-
:       rts

; 4096 reads 8 bytes apart in bank 2, each + 2 NOP
t_fn2:  ldx     #0
:       .repeat 8, I
        lda     f:$020000+I*8,x
        .repeat 2
        nop
        .endrepeat
        .endrepeat
        rep     #$21
        .a16
        txa
        adc     #64
        tax
        sep     #$20
        .a8
        cpx     #$8000
        beq     :+
        jmp     :-
:       rts

; 4096 reads 8 bytes apart in bank 2, each + 4 NOP
t_fn4:  ldx     #0
:       .repeat 8, I
        lda     f:$020000+I*8,x
        .repeat 4
        nop
        .endrepeat
        .endrepeat
        rep     #$21
        .a16
        txa
        adc     #64
        tax
        sep     #$20
        .a8
        cpx     #$8000
        beq     :+
        jmp     :-
:       rts

; 4096 reads 8 bytes apart in bank 2, each + 8 NOP
t_fn8:  ldx     #0
:       .repeat 8, I
        lda     f:$020000+I*8,x
        .repeat 8
        nop
        .endrepeat
        .endrepeat
        rep     #$21
        .a16
        txa
        adc     #64
        tax
        sep     #$20
        .a8
        cpx     #$8000
        beq     :+
        jmp     :-
:       rts

; 4096 x 8 (STA dp + 1 LDA dp)
t_wr1:  ldy     #4096
:       .repeat 8
        sta     dpv
        .repeat 1
        lda     dpv+1
        .endrepeat
        .endrepeat
        dey
        beq     :+
        jmp     :-
:       rts

; 4096 x 8 (STA dp + 2 LDA dp)
t_wr2:  ldy     #4096
:       .repeat 8
        sta     dpv
        .repeat 2
        lda     dpv+1
        .endrepeat
        .endrepeat
        dey
        beq     :+
        jmp     :-
:       rts

;  the CPU and Ali together: a 640 x 360 fill (bank 8) started, then DPW (TC1) or
;  LRMISS (TC2) timed while it runs; TC3 = the same fill alone. The fill's end is waited for
;  after the CPU loop, so TC1/TC2's line is the CPU loop's time; ffill prints the whole time.
bigfill: lda    f:SYS_REV
        cmp     #$08
        bcs     :+
        clc
        rts
:       lda     #0
        sta     f:BL_OP
        sta     f:BL_FLAGS
        lda     #$33
        sta     f:BL_FG
        rep     #$20
        .a16
        lda     #1024
        sta     f:BL_DSTR
        lda     #640
        sta     f:BL_W
        lda     #360
        sta     f:BL_H
        lda     #0
        sta     f:BL_DST
        sep     #$20
        .a8
        lda     #$08
        sta     f:BL_DST+2
        lda     #1
        sta     f:BL_CTRL
        sec
        rts
t_cbw:  jsr     bigfill
        jsr     t_dpw
        jsr     tstop
        ldx     #.loword(m_fill)
        jsr     puts
        jsr     bwait
        rts
t_cbr:  jsr     bigfill
        jsr     t_lrmiss
        jsr     tstop
        ldx     #.loword(m_fill)
        jsr     puts
        jsr     bwait
        rts
t_cbt:  jsr     bigfill
        jsr     bwait
        rts
m_fill: .byte   "  +FILL END ", 0

; 4 x a 16 KB straight run of STA dp in bank 7: every 4th opcode fetch a fill right after a write
t_x1:   jsl     $070000
        jsl     $070000
        jsl     $070000
        jsl     $070000
        rts

; 4096 x INC abs,X 8 bytes apart in bank 2 (a fill, then the write two cycles later)
t_x2:   lda     #$02
        pha
        plb
        ldx     #0
:       .repeat 8, I
        inc     a:I*8,x
        .endrepeat
        rep     #$21
        .a16
        txa
        adc     #64
        tax
        sep     #$20
        .a8
        cpx     #$8000
        beq     :+
        jmp     :-
:       phk
        plb
        rts

; the DPW loop at each offset in a cache line (the code's alignment)
        .align  8
        .res    0, $EA
t_al0:  ldy     #4096
:       .repeat 8
        sta     dpv
        .endrepeat
        dey
        bne     :-
        rts
        .align  8
        .res    1, $EA
t_al1:  ldy     #4096
:       .repeat 8
        sta     dpv
        .endrepeat
        dey
        bne     :-
        rts
        .align  8
        .res    2, $EA
t_al2:  ldy     #4096
:       .repeat 8
        sta     dpv
        .endrepeat
        dey
        bne     :-
        rts
        .align  8
        .res    3, $EA
t_al3:  ldy     #4096
:       .repeat 8
        sta     dpv
        .endrepeat
        dey
        bne     :-
        rts
        .align  8
        .res    4, $EA
t_al4:  ldy     #4096
:       .repeat 8
        sta     dpv
        .endrepeat
        dey
        bne     :-
        rts
        .align  8
        .res    5, $EA
t_al5:  ldy     #4096
:       .repeat 8
        sta     dpv
        .endrepeat
        dey
        bne     :-
        rts
        .align  8
        .res    6, $EA
t_al6:  ldy     #4096
:       .repeat 8
        sta     dpv
        .endrepeat
        dey
        bne     :-
        rts
        .align  8
        .res    7, $EA
t_al7:  ldy     #4096
:       .repeat 8
        sta     dpv
        .endrepeat
        dey
        bne     :-
        rts

; ── setup ──
; whatever ran before (a game) may have left sprites, scrolling or Lau voices on: all off
quiet:  lda     f:SYS_REV
        cmp     #$0A
        bcc     :+
        lda     #$FF
        sta     f:$00DB21               ; AU_KEYOFF: every voice
:       lda     f:SYS_REV
        cmp     #$0B
        bcc     :++
        lda     #0
        sta     f:$00D940               ; NV_SPR_CTRL
        ldx     #0
:       sta     f:$00D980,x             ; the records
        sta     f:$00D930,x             ; the scroll registers ($D930-$D93F)
        inx
        cpx     #16
        bne     :-
        ldx     #16
:       sta     f:$00D980,x
        inx
        cpx     #128
        bne     :-
        sta     f:$00D941               ; NV_SPR_COMMIT
:       rts


; bank 0 vectors: native COP ($FFE4) -> $E000, native IRQ ($FFEE) -> $E004 (JML trampolines)
vecinit: sei
        lda     #$5C
        sta     f:$00E000
        sta     f:$00E004
        rep     #$20
        .a16
        lda     #.loword(cop_h)
        sta     f:$00E001
        lda     #.loword(irq_h)
        sta     f:$00E005
        lda     #$E000
        sta     f:$00FFE4
        lda     #$E004
        sta     f:$00FFEE
        sep     #$20
        .a8
        lda     #^cop_h
        sta     f:$00E003
        sta     f:$00E007
        rts

cop_h:  rti
irq_h:  pha
        lda     #$04
        sta     f:IRQ_STATUS
        rep     #$20
        .a16
        inc     nirq
        sep     #$20
        .a8
        pla
        rti

; the bank 5 routine (DPR loop) and the bank 6 straight run
hiinit: ldx     #0
:       lda     hiloop,x
        sta     f:$050000,x
        inx
        cpx     #hiend-hiloop
        bne     :-
        ldx     #0
:       lda     #$A5                    ; LDA dp
        sta     f:$060000,x
        inx
        lda     #dpv
        sta     f:$060000,x
        inx
        cpx     #$4000
        bne     :-
        lda     #$6B                    ; RTL
        sta     f:$060000,x
        ldx     #0
:       lda     #$85                    ; STA dp
        sta     f:$070000,x
        inx
        lda     #dpv
        sta     f:$070000,x
        inx
        cpx     #$4000
        bne     :-
        lda     #$6B
        sta     f:$070000,x
        rts

hiloop: ldy     #4096
:       lda     dpv
        lda     dpv
        lda     dpv
        lda     dpv
        lda     dpv
        lda     dpv
        lda     dpv
        lda     dpv
        dey
        bne     :-
        rtl
hiend:

; mailbox rings at $0E:0000 / $0E:1000
mbinit: stz     mbok
        lda     #$00
        sta     f:MB_REQ_BASE
        sta     f:MB_RSP_BASE
        lda     #>.loword(REQ_RING)
        sta     f:MB_REQ_BASE+1
        lda     #>.loword(RSP_RING)
        sta     f:MB_RSP_BASE+1
        lda     #^REQ_RING
        sta     f:MB_REQ_BASE+2
        sta     f:MB_RSP_BASE+2
        ldx     #0
:       lda     f:MB_STATUS
        and     #$01
        bne     :+
        dex
        bne     :-
        rts
:       inc     mbok
        rts

; ── output ──
tstart: lda     f:UPTIME
        sta     t0
        lda     f:UPTIME+1
        sta     t0+1
        lda     f:UPTIME+2
        sta     t0+2
        lda     f:UPTIME+3
        sta     t0+3
        rts

tstop:  lda     f:UPTIME
        sta     t1
        lda     f:UPTIME+1
        sta     t1+1
        lda     f:UPTIME+2
        sta     t1+2
        lda     f:UPTIME+3
        sta     t1+3
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

m_hello: .byte "TIMING REV ", 0
m_done:  .byte "TIMING DONE", 10, 0
m_frz:   .byte "FROZEN ", 0
