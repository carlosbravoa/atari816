; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816 test of Lau, the sample player (REV $0A). Self-checking; ca65 -D SIM for the testbench.
;
;   REGS     reset values (AU_MASTER $C0), AU_IRQ_EN / AU_SEL read back
;   RATE     voice 0 at pitch $4000 and $2000: AU_POS advances 48 / 24 samples per ms (UPTIME),
;            once with the classic machine frozen and once running
;   END      voice 1, 200 samples, no loop: the AUDIO interrupt comes once, about 4,167 us after
;            KEYON; AU_END bit 1, PLAYING bit 1 clear
;   LOOP     voice 2, LEN 64, LOOP 16, pitch $8000: keeps playing, AU_POS always in 16..63,
;            one AU_END interrupt per 24 output samples (500 us)
;   MIX      constant samples: AU_OUT_L / AU_OUT_R are the values the spec's formula gives
;   LATE     8 voices of 16-bit samples at pitch $FFFF (a new 8-byte block for every voice almost
;            every output sample) while the blitter runs a long list and Marga shows
;            640x360x8: AU_LATE must stay 0
; Output ends with "SAMPLER PASS" or "SAMPLER FAIL nn", then DONE.
        .p816
        .smart  -

AU_KEYON    = $00DB20
AU_KEYOFF   = $00DB21
AU_PLAYING  = $00DB22
AU_END      = $00DB23
AU_IRQEN    = $00DB24
AU_MASTER   = $00DB25
AU_LATE     = $00DB26
AU_SEL      = $00DB27
AU_POS      = $00DB28
AU_OUT      = $00DB2C
AU_V        = $00DB80
BL_CTRL     = $00DA13
BL_LIST     = $00DA14
BL_COUNT    = $00DA17
NV_CTRL     = $00D900
NV_BASE     = $00D901
NV_LATE     = $00D90B
SV_CTRL     = $00DC00
SYS_REV     = $00DE01
IRQ_STATUS  = $00DE08
IRQ_EN      = $00DE09
UPTIME      = $00DE18
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1

SMP         = $060000           ; samples
LIST        = $020000
FB          = $080000

p0          = $20               ; 4
t0          = $24               ; 4
t1          = $28               ; 4
nfail       = $2C               ; 2
n_aud       = $2E               ; 2: AUDIO interrupts
tmp         = $30               ; 2
pos0        = $32               ; 2
lo          = $34               ; 2: expected range
hi          = $36               ; 2
t_irq       = $38               ; 4: UPTIME in the first AUDIO interrupt
cnt         = $3C               ; 2

.macro print msg
        ldx     #.loword(msg)
        jsr     puts
.endmacro

; voice parameter block: START, LEN, LOOP, PITCH, VOL_L, VOL_R, CTRL (14 bytes)
.macro VP start, len, loop, pitch, vl, vr, ctl
        .faraddr start
        .faraddr len
        .faraddr loop
        .word   pitch
        .byte   vl, vr, ctl
.endmacro

        .segment "CODE"
        .a8
        .i16
start:  clc
        xce
        rep     #$10
        sep     #$20
        ldx     #$BFFF
        txs
        pea     $0000
        pld
        phk
        plb
        print   m_hello
        lda     f:SYS_REV
        jsr     puthex
        jsr     nl
        rep     #$20
        .a16
        stz     nfail
        stz     n_aud
        sep     #$20
        .a8
        jsr     irqinit
        jsr     fillsmp
        jsr     t_regs
        lda     #$04                    ; frozen
        sta     f:SV_CTRL
        jsr     t_rate
        lda     #$00                    ; running
        sta     f:SV_CTRL
        jsr     t_rate
        lda     #$04
        sta     f:SV_CTRL
        jsr     t_end
        jsr     t_loop
        jsr     t_mix
        jsr     t_late
        sei
        lda     #$FF
        sta     f:AU_KEYOFF
        lda     #0
        sta     f:IRQ_EN
        sta     f:NV_CTRL
        sta     f:SV_CTRL
        lda     nfail
        bne     @f
        print   m_pass
        bra     @d
@f:     print   m_fail
        lda     nfail
        jsr     puthex
        jsr     nl
@d:     print   m_done
        stp

failinc:
        rep     #$20
        inc     nfail
        sep     #$20
        rts

irqinit:
        sei
        lda     #$5C
        sta     f:$00E008
        rep     #$20
        .a16
        lda     #.loword(irq_h)
        sta     f:$00E009
        lda     #$E008
        sta     f:$00FFEE
        sep     #$20
        .a8
        lda     #^irq_h
        sta     f:$00E00B
        lda     #$20                    ; AUDIO
        sta     f:IRQ_EN
        cli
        rts

; AUDIO: count, remember the time of the first one, clear AU_END
irq_h:  rep     #$30
        .a16
        .i16
        pha
        sep     #$20
        .a8
        lda     n_aud
        ora     n_aud+1
        bne     :+
        lda     f:UPTIME
        sta     t_irq
        lda     f:UPTIME+1
        sta     t_irq+1
        lda     f:UPTIME+2
        sta     t_irq+2
        lda     f:UPTIME+3
        sta     t_irq+3
:       rep     #$20
        .a16
        inc     n_aud
        sep     #$20
        .a8
        lda     f:AU_END
        sta     f:AU_END
        rep     #$30
        pla
        rti
        .a8

; voice X (0-7) <- parameter block at Y (in this bank)
setv:   rep     #$21
        .a16
        txa
        asl
        asl
        asl
        asl
        tax
        sep     #$20
        .a8
        lda     #14
        sta     cnt
:       lda     a:0,y
        sta     f:AU_V,x
        inx
        iny
        dec     cnt
        bne     :-
        rts

; samples: SMP+$0000 8-bit ramp (i & $FF) for 64 KB; SMP+$10000: 8-bit $40 x 256;
; SMP+$10100: 16-bit $1234 x 256; SMP+$10400: 16-bit noise x 16 K
fillsmp:
        rep     #$20
        .a16
        lda     #.loword(SMP)
        sta     p0
        sep     #$20
        .a8
        lda     #^SMP
        sta     p0+2
        ldy     #0
:       tya
        sta     [p0],y
        iny
        bne     :-
        inc     p0+2
        ldy     #0
:       lda     #$40
        sta     [p0],y
        iny
        cpy     #$100
        bne     :-
        rep     #$20
        .a16
:       lda     #$1234
        sta     [p0],y
        iny
        iny
        cpy     #$300
        bne     :-
        ldy     #$400
        lda     #$ACE1
:       lsr
        bcc     :+
        eor     #$B400
:       sta     [p0],y
        iny
        iny
        cpy     #$8400
        bne     :--
        sep     #$20
        .a8
        rts

; ── REGS ─────────────────────────────────────────────────────────────────────
t_regs: lda     f:AU_MASTER
        cmp     #$C0
        bne     @bad
        lda     f:AU_PLAYING
        ora     f:AU_LATE
        bne     @bad
        lda     #$5A
        sta     f:AU_IRQEN
        lda     f:AU_IRQEN
        cmp     #$5A
        bne     @bad
        lda     #$06
        sta     f:AU_IRQEN
        lda     f:AU_IRQEN
        cmp     #$06
        bne     @bad
        lda     #0
        sta     f:AU_IRQEN
        lda     #$0D
        sta     f:AU_SEL
        lda     f:AU_SEL
        cmp     #$05
        bne     @bad
        print   m_regok
        rts
@bad:   print   m_fregs
        jmp     failinc

; ── RATE ─────────────────────────────────────────────────────────────────────
.ifdef SIM
RT_US   = 2000
.else
RT_US   = 20000
.endif
t_rate: ldx     #0
        ldy     #.loword(vp_rate)
        jsr     setv
        lda     #0
        sta     f:AU_SEL
        lda     #$01
        sta     f:AU_KEYON
        rep     #$20
        .a16
        lda     #RT_US * 48 / 1000 - 3
        sta     lo
        lda     #RT_US * 48 / 1000 + 3
        sta     hi
        sep     #$20
        .a8
        jsr     measure
        bcs     @bad
        lda     #$20                    ; pitch $2000
        sta     f:AU_V+10
        rep     #$20
        .a16
        lda     #RT_US * 24 / 1000 - 3
        sta     lo
        lda     #RT_US * 24 / 1000 + 3
        sta     hi
        sep     #$20
        .a8
        jsr     measure
        bcs     @bad
        lda     #$01
        sta     f:AU_KEYOFF
        print   m_rateok
        rts
@bad:   lda     #$01
        sta     f:AU_KEYOFF
        print   m_frate
        rep     #$20
        .a16
        lda     tmp
        sep     #$20
        .a8
        xba
        jsr     puthex
        xba
        jsr     puthex
        jsr     nl
        jmp     failinc

; AU_POS of voice 0 advances by lo..hi in RT_US microseconds? C = 1 if not (tmp = advance)
measure:
        ldx     #200                    ; let it settle
:       dex
        bne     :-
        jsr     rdpos
        .a16
        sta     pos0
        sep     #$20
        .a8
        jsr     rdup
        rep     #$21
        .a16
        lda     t1
        adc     #RT_US
        sta     t0
        sep     #$20
        .a8
:       jsr     rdup
        rep     #$20
        .a16
        lda     t1
        cmp     t0
        sep     #$20
        .a8
        bmi     :-
        jsr     rdpos
        .a16
        sec
        sbc     pos0
        sta     tmp
        cmp     lo
        bcc     @no
        cmp     hi
        bcs     @no
        sep     #$20
        .a8
        clc
        rts
        .a16
@no:    sep     #$21
        .a8
        rts

; A(16) <- AU_POS low 16 bits (8-bit mode on return, value in A/B)
rdpos:  lda     f:AU_POS
        xba
        lda     f:AU_POS+1
        xba
        rep     #$20
        .a16
        rts
        .a8

rdup:   lda     f:UPTIME
        sta     t1
        lda     f:UPTIME+1
        sta     t1+1
        lda     f:UPTIME+2
        sta     t1+2
        lda     f:UPTIME+3
        sta     t1+3
        rts

vp_rate: VP SMP, $FFFFFF, 0, $4000, 0, 0, 0

; ── END ──────────────────────────────────────────────────────────────────────
t_end:  ldx     #1
        ldy     #.loword(vp_end)
        jsr     setv
        rep     #$20
        .a16
        stz     n_aud
        sep     #$20
        .a8
        lda     #$FF
        sta     f:AU_END
        lda     #$02
        sta     f:AU_IRQEN
        jsr     rdup
        rep     #$20
        .a16
        lda     t1
        sta     t0
        lda     t1+2
        sta     t0+2
        sep     #$20
        .a8
        lda     #$02
        sta     f:AU_KEYON
        rep     #$20
        .a16
        lda     #20000
        sta     cnt
:       dec     cnt                     ; about 14 ms
        bne     :-
        sep     #$20
        .a8
        lda     n_aud
        cmp     #1
        bne     @bad
        lda     f:AU_PLAYING
        and     #$02
        bne     @bad
        rep     #$20
        .a16
        sec
        lda     t_irq
        sbc     t0
        sta     tmp
        cmp     #4167 - 150
        bcc     @bad16
        cmp     #4167 + 150
        bcs     @bad16
        sep     #$20
        .a8
        lda     #0
        sta     f:AU_IRQEN
        print   m_endok
        rts
@bad16: sep     #$20
@bad:   lda     #0
        sta     f:AU_IRQEN
        print   m_fend
        lda     n_aud
        jsr     puthex
        lda     tmp+1
        jsr     puthex
        lda     tmp
        jsr     puthex
        jsr     nl
        jmp     failinc

vp_end: VP SMP, 200, 0, $4000, 0, 0, 0

; ── LOOP ─────────────────────────────────────────────────────────────────────
t_loop: ldx     #2
        ldy     #.loword(vp_loop)
        jsr     setv
        lda     #2
        sta     f:AU_SEL
        rep     #$20
        .a16
        stz     n_aud
        sep     #$20
        .a8
        lda     #$FF
        sta     f:AU_END
        lda     #$04
        sta     f:AU_IRQEN
        sta     f:AU_KEYON
        jsr     rdup
        rep     #$21
        .a16
        lda     t1
        adc     #10000
        sta     t0
        stz     tmp                     ; bad positions
        sep     #$20
        .a8
        ldx     #$4000                  ; let it pass the first wrap (667 us)
:       dex
        bne     :-
@w:     jsr     rdpos
        .a16
        cmp     #16
        bcc     @bp
        cmp     #64
        bcc     @gp
@bp:    inc     tmp
@gp:    sep     #$20
        .a8
        jsr     rdup
        rep     #$20
        .a16
        lda     t1
        cmp     t0
        sep     #$20
        .a8
        bmi     @w
        lda     #0
        sta     f:AU_IRQEN
        lda     f:AU_PLAYING
        and     #$04
        beq     @bad
        lda     #$04
        sta     f:AU_KEYOFF
        lda     tmp
        bne     @bad
        lda     n_aud                   ; about 20 wraps in 10 ms
        cmp     #18
        bcc     @bad
        cmp     #23
        bcs     @bad
        print   m_loopok
        rts
@bad:   lda     #$04
        sta     f:AU_KEYOFF
        print   m_floop
        lda     n_aud
        jsr     puthex
        lda     tmp
        jsr     puthex
        jsr     nl
        jmp     failinc

vp_loop: VP SMP, 64, 16, $8000, 0, 0, 1

; ── MIX ──────────────────────────────────────────────────────────────────────
t_mix:  lda     #$FF
        sta     f:AU_MASTER
        ldx     #3
        ldy     #.loword(vp_c8)
        jsr     setv
        lda     #$08
        sta     f:AU_KEYON
        jsr     settle
        rep     #$20
        .a16
        lda     f:AU_OUT
        cmp     #8128
        bne     @bad
        lda     f:AU_OUT+2
        cmp     #4080
        bne     @bad
        sep     #$20
        .a8
        ldx     #4
        ldy     #.loword(vp_c16)
        jsr     setv
        lda     #$10
        sta     f:AU_KEYON
        jsr     settle
        rep     #$20
        .a16
        lda     f:AU_OUT
        cmp     #10439
        bne     @bad
        sep     #$20
        .a8
        lda     #$18
        sta     f:AU_KEYOFF
        jsr     settle
        rep     #$20
        .a16
        lda     f:AU_OUT
        ora     f:AU_OUT+2
        bne     @bad
        sep     #$20
        .a8
        lda     #$C0
        sta     f:AU_MASTER
        print   m_mixok
        rts
        .a16
@bad:   sta     tmp
        sep     #$20
        .a8
        lda     #$18
        sta     f:AU_KEYOFF
        lda     #$C0
        sta     f:AU_MASTER
        print   m_fmix
        lda     tmp+1
        jsr     puthex
        lda     tmp
        jsr     puthex
        jsr     nl
        jmp     failinc

settle: ldx     #1000                   ; > 8 output samples
:       dex
        bne     :-
        rts

vp_c8:  VP SMP+$10000, 256, 0, $4000, 255, 128, 1
vp_c16: VP SMP+$10100, 256, 0, $4000, 255, 0, 3

; ── LATE ─────────────────────────────────────────────────────────────────────
; list: 20 copies of 640 x 180 (a whole half screen) inside FB
.ifdef SIM
LT_REC  = 2
.else
LT_REC  = 20
.endif
t_late: rep     #$20
        .a16
        lda     #.loword(LIST)
        sta     p0
        sep     #$20
        .a8
        lda     #^LIST
        sta     p0+2
        ldy     #0
@b:     ldx     #0
:       lda     lrec,x
        sta     [p0],y
        iny
        inx
        cpx     #24
        bne     :-
        cpy     #LT_REC*24
        bne     @b
        lda     #<(FB >> 8)
        sta     f:NV_BASE+1
        lda     #^FB
        sta     f:NV_BASE+2
        lda     #$01
        sta     f:NV_CTRL
        sta     f:NV_LATE
        ldx     #0
:       phx
        ldy     #.loword(vp_late)
        jsr     setv
        plx
        inx
        cpx     #8
        bne     :-
        sta     f:AU_LATE
        lda     #$FF
        sta     f:AU_KEYON
        lda     #0
        sta     f:BL_LIST
        sta     f:BL_LIST+1
        sta     f:BL_COUNT+1
        lda     #^LIST
        sta     f:BL_LIST+2
        lda     #LT_REC
        sta     f:BL_COUNT
        jsr     rdup
        rep     #$20
        .a16
        lda     t1
        sta     t0
        lda     t1+2
        sta     t0+2
        sep     #$20
        .a8
        lda     #$04
        sta     f:BL_CTRL
:       lda     f:BL_CTRL
        lsr
        bcs     :-
        jsr     rdup
        lda     #$FF
        sta     f:AU_KEYOFF
        lda     #0
        sta     f:NV_CTRL
        print   m_late
        lda     f:AU_LATE
        jsr     puthex
        print   m_nvlate
        lda     f:NV_LATE
        jsr     puthex
        print   m_us
        rep     #$20
        .a16
        sec
        lda     t1
        sbc     t0
        sta     t1
        lda     t1+2
        sbc     t0+2
        sep     #$20
        .a8
        xba
        jsr     puthex
        xba
        jsr     puthex
        lda     t1+1
        jsr     puthex
        lda     t1
        jsr     puthex
        jsr     nl
        lda     f:AU_LATE
        bne     @bad
        print   m_lateok
        rts
@bad:   jmp     failinc

lrec:   .faraddr FB
        .word   640
        .faraddr FB + 640*180
        .word   640, 640, 180
        .byte   0, 0, 0, 1, 0, 0, 0, 0, 0, 0
vp_late: VP SMP+$10400, 16384, 0, $FFFF, 32, 32, $03

; ── output ───────────────────────────────────────────────────────────────────
nl:     lda     #10
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
:       adc     #$30
        bra     putc

m_hello:  .byte "SAMPLE PLAYER TEST REV ", 0
m_regok:  .byte "REGS OK", 10, 0
m_fregs:  .byte "FAIL REGS", 10, 0
m_rateok: .byte "RATE OK", 10, 0
m_frate:  .byte "FAIL RATE ", 0
m_endok:  .byte "END OK", 10, 0
m_fend:   .byte "FAIL END ", 0
m_loopok: .byte "LOOP OK", 10, 0
m_floop:  .byte "FAIL LOOP ", 0
m_mixok:  .byte "MIX OK", 10, 0
m_fmix:   .byte "FAIL MIX ", 0
m_late:   .byte "8 VOICES + LIST: AU_LATE ", 0
m_nvlate: .byte " NV_LATE ", 0
m_us:     .byte " US ", 0
m_lateok: .byte "LATE OK", 10, 0
m_pass:   .byte "SAMPLER PASS", 10, 0
m_fail:   .byte "SAMPLER FAIL ", 0
m_done:   .byte "DONE", 10, 0
