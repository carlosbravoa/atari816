; emu816 test (Horizon 0.30): Ali's time for a command list of many one-line fills, what
; Horizon's fill_runs gives it (2,688 records of 23-pixel runs and less). Checks emu/blitter.c's
; model against what a816_blit.sv does for such a list:
;   - each record is read as three 8-byte bursts through the blitter's port, one after the
;     other, each followed by 8 clk_core of loading its bytes (L_RD, L_WT, L_LD), then L_CHK,
;     L_GO and the line set-up: REC_CYC = 30 CPU cycles (60 clk_core with an idle port);
;   - the blit: 8 + 2 per line, plus the 32-bit words it writes (a fill writes aligned words
;     with a byte mask: a run that starts or ends inside a word pays for the whole word), at
;     the board's measured clk_core per pixel x 4 a word (classic machine running, Marga off:
;     2.56 clk_core a pixel: 5.12 CPU cycles a word).
; Records: 1000 fills, 23 pixels (6 words when the run starts on a word: at $03:0000 +
; 32 k), then 1000 more of 23 pixels starting 1 byte into a word (still 6 words), then 1000
; of 2 pixels across a word boundary (2 words). Prints the microseconds of each list (the
; time from the LIST write until BUSY drops) and checks the pixels.
;   1000 x (30 + 8 + 2 + 6 x 4 x 256 / 200 = 30.72 -> 30) = 70,000 cycles = 4,889 us ($1319)
;   1000 x (30 + 8 + 2 + 2 x 4 x 256 / 200 = 10.24 -> 10) = 50,000 cycles = 3,492 us ($0DA4)
        .include "common.inc"

CACHE_FLUSH = $00D80A
BL_CTRL  = $00DA13
BL_LIST  = $00DA14
BL_COUNT = $00DA17
LISTA    = $020000              ; the records (24,000 bytes)
DSTB     = $03                  ; the pixels: bank $03

t1      = $20
t2      = $22
k       = $24
ofs     = $26                   ; the first run's offset in its 32-byte slot
wid     = $28
bad     = $2A

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
        stz     bad
        lda     #0
        ldx     #23
        jsr     list
        print   m_a
        jsr     elapsed
        lda     #1
        ldx     #23
        jsr     list
        print   m_b
        jsr     elapsed
        lda     #3
        ldx     #2
        jsr     list
        print   m_c
        jsr     elapsed
        lda     bad
        bne     :+
        print   m_pass
        stp
:       print   m_fail
        stp

; 1000 fills of X pixels at $03:0000 + 32 k + A, colour k (low byte), timed; then their
; pixels checked (the byte before and after each run untouched: 0)
list:   rep     #$20
        .a16
        and     #$00FF
        sta     ofs
        stx     wid
        ldx     #0                      ; the destination cleared, the records zeroed
:       lda     #0
        sta     f:DSTB << 16,x
        inx
        inx
        cpx     #32000
        bcc     :-
        ldx     #0
:       sta     f:LISTA,x
        inx
        inx
        cpx     #24000
        bcc     :-
        ldx     #0
        stz     k
@r:     lda     k                       ; DST = $03:0000 + 32 k + ofs
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     ofs
        sta     f:LISTA+5,x
        lda     #DSTB
        sta     f:LISTA+7,x
        lda     wid
        sta     f:LISTA+10,x
        lda     #1
        sta     f:LISTA+12,x
        lda     k
        and     #$00FF
        ora     #$0100                  ; (FG k, BG 1: not used)
        sta     f:LISTA+14,x
        txa
        clc
        adc     #24
        tax
        inc     k
        lda     k
        cmp     #1000
        bcc     @r
        lda     #.loword(LISTA)
        sta     f:BL_LIST
        lda     #1000
        sta     f:BL_COUNT
        sep     #$20
        .a8
        lda     #^LISTA
        sta     f:BL_LIST+2
        rep     #$20
        .a16
        lda     f:UPTIME
        sta     t1
        sep     #$20
        .a8
        lda     #4                      ; LIST
        sta     f:BL_CTRL
:       lda     f:BL_CTRL
        lsr
        bcs     :-
        rep     #$20
        .a16
        lda     f:UPTIME
        sta     t2
        sep     #$20
        .a8
        sta     f:CACHE_FLUSH           ; (the CPU then sees what Ali wrote)
        rep     #$20
        .a16
        ldx     #0                      ; the pixels: k's run, nothing around it
        stz     k
@c:     txa
        clc
        adc     ofs
        tax
        sep     #$20
        .a8
        lda     k
        ldy     wid
:       cmp     f:DSTB << 16,x
        beq     :+
        inc     bad
:       inx
        dey
        bne     :--
        lda     f:DSTB << 16,x          ; the byte after: 0
        beq     :+
        inc     bad
:       rep     #$20
        .a16
        inc     k
        lda     k
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        tax
        lda     k
        cmp     #1000
        bcc     @c
        sep     #$20
        .a8
        rts

elapsed:
        rep     #$20
        .a16
        lda     t2
        sec
        sbc     t1
        tax
        sep     #$20
        .a8
        jsr     puthex16
        jmp     crlf

m_hello: .byte "ALI RUN LISTS", 10, 0
m_a:     .byte "23 PX ALIGNED US ", 0
m_b:     .byte "23 PX AT +1 US ", 0
m_c:     .byte "2 PX ACROSS A WORD US ", 0
m_pass:  .byte "PIXELS OK", 10, "DONE", 10, 0
m_fail:  .byte "PIXELS WRONG", 10, "DONE", 10, 0
