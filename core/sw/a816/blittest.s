; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816 test of Ali, the blitter ($00:DA00-$DA13).
;
; Every test in the table runs twice: once on the blitter in the work area WA, and once by a
; byte-by-byte 65C816 reference in the reference area RA (same layout, $02:0000 higher), in the
; order of the emulator's model (emu/blitter.c). Both areas get the same pseudo-random bytes
; first, over the span the test touches plus 16 bytes on each side; the two spans are then
; compared after CACHE_FLUSH (the blitter writes behind the 65C816's cache).
; The whole table runs four times:
;   run 0  classic machine running (8-byte bursts), NVC off; then the BUSY / IRQ test
;   run 1  classic machine frozen (16-byte bursts), NVC off
;   run 2  frozen, NVC showing 640x360x8 from FB: NV_LATE must stay 0
;   run 3  running, NVC showing 640x360x8 (NV_LATE only reported: 8 bpp needs 16-byte bursts)
; Tests with mode bit 0 make the CPU hammer memory while the blit runs (a write and a read
; that misses the cache every few cycles), and check what it wrote.
; Output: one line per failing test ("FAIL Tnn ..."), a line per run, and at the end
; "BLITTER PASS" or "BLITTER FAIL nnnn", then DONE. BUSY is never seen set on the emulator
; (its blits complete inside the START write); that is reported, not failed.
        .p816
        .smart  -

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
CACHE_FLUSH = $00D80A
NV_CTRL     = $00D900
NV_BASE     = $00D901
NV_LATE     = $00D90B
SV_CTRL     = $00DC00
IRQ_STATUS  = $00DE08
IRQ_EN      = $00DE09
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1

WA          = $030000           ; work area: the blitter's (offsets up to $1FFFF)
RA          = $050000           ; reference area: the CPU's
SCR         = $070000           ; hammer: written $07:0000-7FFF, read $07:8000-FFFF
FB          = $080000           ; NVC framebuffer during runs 2 and 3
REC         = 21                ; bytes per test record

; direct page
t_rec       = $20               ; the current test record
t_op        = t_rec+0
t_flags     = t_rec+1
t_src       = t_rec+2           ; 3 bytes, offset in the area
t_sstr      = t_rec+5
t_dst       = t_rec+7           ; 3 bytes
t_dstr      = t_rec+10
t_w         = t_rec+12
t_h         = t_rec+14
t_fg        = t_rec+16
t_bg        = t_rec+17
t_key       = t_rec+18
t_pm        = t_rec+19          ; pattern mask for the initial bytes
t_mode      = t_rec+20          ; bit 0: CPU hammers memory during the blit
lo          = $40               ; 4: span start (offset)
hi          = $44               ; 4: span end (offset, exclusive)
v1          = $48               ; 4
v2          = $4C               ; 4
pw          = $50               ; 4: WA + lo
pr          = $54               ; 4: RA + lo
psrc        = $58               ; 4: reference: source line
pdst        = $5C               ; 4: reference: destination line
cnt         = $60               ; 2: span length
seed        = $62               ; 2
tnum        = $64               ; 2
nfail       = $66               ; 2
xx          = $68               ; 2: pixels left in the line
xs          = $6A               ; 2: pixel x
yy          = $6C               ; 2
bitn        = $6E               ; 2
hcnt        = $70               ; 2: bytes the hammer wrote
tmp         = $72               ; 2
run         = $74               ; 1
busy_seen   = $75               ; 1
irqflag     = $76               ; 1
irqbusy     = $77               ; 1
rptr        = $78               ; 4: current record
phs         = $7C               ; 4: SCR
phq         = $80               ; 4: SCR + $8000
tout        = $84               ; 2

.macro T op, fl, src, sstr, dst, dstr, w, h, fg, bg, key, pm, mode
        .byte   op, fl
        .faraddr src
        .word   sstr
        .faraddr dst
        .word   dstr, w, h
        .byte   fg, bg, key, pm, mode
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
        ldx     #.loword(m_hello)
        jsr     puts
        rep     #$20
        .a16
        stz     nfail
        lda     #$ACE1
        sta     seed
        lda     #.loword(SCR)
        sta     phs
        lda     #^SCR
        sta     phs+2
        lda     #.loword(SCR+$8000)
        sta     phq
        lda     #^SCR
        sta     phq+2
        sep     #$20
        .a8
        stz     busy_seen
        jsr     regtest
        stz     run
@run:   jsr     setrun
        jsr     runtable
        lda     run
        and     #$02
        beq     @nolate
        ldx     #.loword(m_late)
        jsr     puts
        lda     f:NV_LATE
        pha
        jsr     puthex
        jsr     nl
        pla
        beq     @nolate
        lda     run
        cmp     #2
        bne     @nolate
        ldx     #.loword(m_flate)
        jsr     puts
        jsr     failinc
@nolate:
        lda     run
        bne     @next
        jsr     irqtest
@next:  inc     run
        lda     run
        cmp     #4
        bne     @run

        lda     #$00
        sta     f:NV_CTRL
        sta     f:SV_CTRL
        lda     busy_seen
        bne     :+
        ldx     #.loword(m_nobusy)
        jsr     puts
:       rep     #$20
        .a16
        lda     nfail
        sep     #$20
        .a8
        bne     @bad
        ldx     #.loword(m_pass)
        jsr     puts
        bra     @done
@bad:   ldx     #.loword(m_fail)
        jsr     puts
        lda     nfail+1
        jsr     puthex
        lda     nfail
        jsr     puthex
        jsr     nl
@done:  ldx     #.loword(m_done)
        jsr     puts
        stp

; ── run setup: run 0..3 ─────────────────────────────────────────────────────────
setrun: ldx     #.loword(m_run)
        jsr     puts
        lda     run
        jsr     puthex
        lda     run
        eor     #$03                    ; runs 1 and 2: frozen
        cmp     #$01
        beq     :+
        cmp     #$02
        beq     :+
        lda     #$00
        bra     :++
:       lda     #$04
:       sta     f:SV_CTRL
        ldx     #.loword(m_long)
        jsr     puts
        lda     f:SV_CTRL
        lsr
        lsr
        and     #$01
        jsr     puthex
        ldx     #.loword(m_nvc)
        jsr     puts
        lda     #$00
        sta     f:NV_BASE
        sta     f:NV_BASE+1
        lda     #^FB
        sta     f:NV_BASE+2
        lda     run
        lsr
        and     #$01                    ; runs 2 and 3: NVC on, 640x360x8
        sta     f:NV_CTRL
        sta     f:NV_LATE               ; any write clears it
        jsr     puthex
        jmp     nl

; ── the table ────────────────────────────────────────────────────────────────
runtable:
        lda     #^tests
        sta     rptr+2
        ldx     #.loword(tests)
        stx     rptr
        ldx     #1
        stx     tnum
@next:  lda     [rptr]
        cmp     #$FF
        bne     :+
        rts
:       ldy     #0
:       lda     [rptr],y
        tyx
        sta     t_rec,x
        iny
        cpy     #REC
        bne     :-
        jsr     span
        jsr     initarea
        jsr     hwblit
        jsr     refblit
        lda     #$00
        sta     f:CACHE_FLUSH
        jsr     compare
        lda     t_mode
        lsr
        bcc     :+
        jsr     hamcheck
:       rep     #$20
        .a16
        clc
        lda     rptr
        adc     #REC
        sta     rptr
        inc     tnum
        sep     #$20
        .a8
        bra     @next

; span: lo = min(src, dst) - 16, hi = max(src + (h-1)*sstr, dst + (h-1)*dstr) + w + 16
span:   rep     #$20
        .a16
        lda     t_src
        sta     v1
        lda     t_src+2
        and     #$00FF
        sta     v1+2
        lda     t_dst
        sta     v2
        lda     t_dst+2
        and     #$00FF
        sta     v2+2
        ; lo = min(v1, v2) - 16
        lda     v1+2
        cmp     v2+2
        bcc     @l1
        bne     @l2
        lda     v1
        cmp     v2
        bcc     @l1
@l2:    lda     v2
        sta     lo
        lda     v2+2
        sta     lo+2
        bra     @l3
@l1:    lda     v1
        sta     lo
        lda     v1+2
        sta     lo+2
@l3:    sec
        lda     lo
        sbc     #16
        sta     lo
        lda     lo+2
        sbc     #0
        sta     lo+2
        lda     t_h
        beq     @hd
        dec
        sta     tmp
@hl:    beq     @hd
        clc
        lda     v1
        adc     t_sstr
        sta     v1
        lda     v1+2
        adc     #0
        sta     v1+2
        clc
        lda     v2
        adc     t_dstr
        sta     v2
        lda     v2+2
        adc     #0
        sta     v2+2
        dec     tmp
        bra     @hl
@hd:    ; hi = max(v1, v2) + w + 16
        lda     v1+2
        cmp     v2+2
        bcc     @h2
        bne     @h1
        lda     v1
        cmp     v2
        bcc     @h2
@h1:    lda     v1
        sta     hi
        lda     v1+2
        sta     hi+2
        bra     @h3
@h2:    lda     v2
        sta     hi
        lda     v2+2
        sta     hi+2
@h3:    clc
        lda     hi
        adc     t_w
        sta     hi
        lda     hi+2
        adc     #0
        sta     hi+2
        clc
        lda     hi
        adc     #16
        sta     hi
        lda     hi+2
        adc     #0
        sta     hi+2
        sec
        lda     hi
        sbc     lo
        sta     cnt                     ; spans stay below 64 KB
        clc
        lda     lo
        adc     #.loword(WA)
        sta     pw
        lda     lo+2
        adc     #^WA
        sta     pw+2
        clc
        lda     lo
        adc     #.loword(RA)
        sta     pr
        lda     lo+2
        adc     #^RA
        sta     pr+2
        sep     #$20
        .a8
        rts

initarea:
        ldy     #0
:       jsr     rnd
        and     t_pm
        sta     [pw],y
        sta     [pr],y
        iny
        cpy     cnt
        bne     :-
        rts

; 16-bit Galois LFSR; returns a byte in A (a8)
rnd:    rep     #$20
        .a16
        lda     seed
        lsr
        bcc     :+
        eor     #$B400
:       sta     seed
        sep     #$20
        .a8
        eor     seed+1
        rts

; ── the blitter ──────────────────────────────────────────────────────────────
setregs:
        rep     #$20
        .a16
        clc
        lda     t_src
        adc     #.loword(WA)
        sta     f:BL_SRC
        sep     #$20
        .a8
        lda     t_src+2
        adc     #^WA
        sta     f:BL_SRC+2
        rep     #$20
        .a16
        clc
        lda     t_dst
        adc     #.loword(WA)
        sta     f:BL_DST
        sep     #$20
        .a8
        lda     t_dst+2
        adc     #^WA
        sta     f:BL_DST+2
        rep     #$20
        .a16
        lda     t_sstr
        sta     f:BL_SSTR
        lda     t_dstr
        sta     f:BL_DSTR
        lda     t_w
        sta     f:BL_W
        lda     t_h
        sta     f:BL_H
        lda     t_fg                    ; FG and BG
        sta     f:BL_FG
        sep     #$20
        .a8
        lda     t_key
        sta     f:BL_KEY
        lda     t_op
        sta     f:BL_OP
        lda     t_flags
        sta     f:BL_FLAGS
        rts

hwblit: jsr     setregs
        lda     #$01
        sta     f:BL_CTRL
        lda     f:BL_CTRL
        and     #$01
        tsb     busy_seen
        lda     t_mode
        lsr
        bcs     hammer
waitbl: lda     f:BL_CTRL
        lsr
        bcs     waitbl
        rts

; write SCR+i = i and read SCR+$8000+8i while the blit runs
hammer: ldy     #0
@h:     tya
        sta     [phs],y
        rep     #$21
        .a16
        tya
        asl
        asl
        asl
        sta     tmp
        sep     #$20
        .a8
        phy
        ldy     tmp
        lda     [phq],y
        ply
        iny
        cpy     #$8000
        beq     @w
        lda     f:BL_CTRL
        lsr
        bcs     @h
@w:     sty     hcnt
        bra     waitbl

; after the flush: the hammer's bytes must all be there
hamcheck:
        ldy     #0
@v:     cpy     hcnt
        beq     @ok
        tya
        cmp     [phs],y
        bne     @bad
        iny
        bra     @v
@ok:    rts
@bad:   ldx     #.loword(m_fham)
        jsr     puts
        lda     tnum
        jsr     puthex
        jsr     nl
        jmp     failinc

; ── reference blit on RA, a byte at a time, in the emulator's order ──────────
refblit:
        lda     t_op
        cmp     #5
        bcc     :+
        rts
:       rep     #$20
        .a16
        lda     t_w
        beq     @ret
        lda     t_h
        beq     @ret
        clc
        lda     t_src
        adc     #.loword(RA)
        sta     psrc
        lda     t_src+2
        and     #$00FF
        adc     #^RA
        sta     psrc+2
        clc
        lda     t_dst
        adc     #.loword(RA)
        sta     pdst
        lda     t_dst+2
        and     #$00FF
        adc     #^RA
        sta     pdst+2
        lda     t_flags
        lsr
        bcc     @fwd
        lda     t_h                     ; BACKWARDS: start at the last line
        dec
        sta     yy
@adv:   beq     @fwd
        jsr     addline
        dec     yy
        bra     @adv
@fwd:   lda     t_h
        sta     yy
@line:  jsr     refline
        .a16
        dec     yy
        beq     @ret
        lda     t_flags
        lsr
        bcs     @up
        jsr     addline
        bra     @line
@up:    jsr     subline
        bra     @line
@ret:   sep     #$20
        .a8
        rts

        .a16
addline:
        clc
        lda     psrc
        adc     t_sstr
        sta     psrc
        lda     psrc+2
        adc     #0
        sta     psrc+2
        clc
        lda     pdst
        adc     t_dstr
        sta     pdst
        lda     pdst+2
        adc     #0
        sta     pdst+2
        rts
subline:
        sec
        lda     psrc
        sbc     t_sstr
        sta     psrc
        lda     psrc+2
        sbc     #0
        sta     psrc+2
        sec
        lda     pdst
        sbc     t_dstr
        sta     pdst
        lda     pdst+2
        sbc     #0
        sta     pdst+2
        rts

; one line; entered and left with a16
refline:
        lda     t_w
        sta     xx
        lda     t_flags
        lsr
        lda     #0
        bcc     :+
        lda     t_w
        dec
:       sta     xs
@pix:   sep     #$20
        .a8
        ldy     xs
        lda     t_op
        beq     @fill
        cmp     #3
        bcs     @exp
        cmp     #2
        beq     @ckey
        lda     [psrc],y
        bra     @st
@ckey:  lda     [psrc],y
        cmp     t_key
        beq     @next
        bra     @st
@fill:  lda     t_fg
        bra     @st
@exp:   rep     #$20
        .a16
        lda     t_flags
        and     #$0070
        lsr
        lsr
        lsr
        lsr
        eor     #$0007                  ; 7 - SRC_BIT: bits before the first one
        clc
        adc     xs
        sta     bitn
        lsr
        lsr
        lsr
        tay
        lda     bitn
        and     #$0007
        tax
        sep     #$20
        .a8
        lda     [psrc],y
        and     f:bitmask,x
        bne     @on
        lda     t_op
        cmp     #4
        beq     @next
        lda     t_bg
        bra     @st2
@on:    lda     t_fg
@st2:   ldy     xs
@st:    sta     [pdst],y
@next:  rep     #$20
        .a16
        lda     t_flags
        lsr
        bcc     @inc
        dec     xs
        bra     @cnt
@inc:   inc     xs
@cnt:   dec     xx
        bne     @pix
        rts

        .a8
compare:
        ldy     #0
        cpy     cnt
        beq     @ok
@l:     lda     [pw],y
        cmp     [pr],y
        bne     @bad
        iny
        cpy     cnt
        bne     @l
@ok:    rts
@bad:   sty     tmp
        ldx     #.loword(m_ft)
        jsr     puts
        lda     tnum
        jsr     puthex
        ldx     #.loword(m_at)
        jsr     puts
        rep     #$21
        .a16
        lda     tmp
        adc     lo
        sta     v1
        lda     lo+2
        adc     #0
        sep     #$20
        .a8
        jsr     puthex
        lda     v1+1
        jsr     puthex
        lda     v1
        jsr     puthex
        ldx     #.loword(m_got)
        jsr     puts
        ldy     tmp
        lda     [pw],y
        jsr     puthex
        ldx     #.loword(m_want)
        jsr     puts
        ldy     tmp
        lda     [pr],y
        jsr     puthex
        jsr     nl
failinc:
        rep     #$20
        .a16
        inc     nfail
        sep     #$20
        .a8
        rts

; ── registers read back ──────────────────────────────────────────────────────
regtest:
        ldx     #0
:       txa
        eor     #$A5
        sta     f:BL_SRC,x
        inx
        cpx     #$13
        bne     :-
        ldx     #0
:       txa
        eor     #$A5
        cmp     f:BL_SRC,x
        bne     @bad
        inx
        cpx     #$13
        bne     :-
        lda     #$02                    ; IRQ_EN without START
        sta     f:BL_CTRL
        lda     f:BL_CTRL
        cmp     #$02
        bne     @bad
        lda     #$00
        sta     f:BL_CTRL
        lda     f:BL_CTRL
        bne     @bad
        ldx     #.loword(m_regok)
        jmp     puts
@bad:   ldx     #.loword(m_freg)
        jsr     puts
        jmp     failinc

; ── BUSY and the BLITTER interrupt ───────────────────────────────────────────
irqtest:
        sei
        lda     #$5C                    ; IRQ trampoline at $00:E008: JML irq_h
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
        lda     #^tests                 ; the speed test fill 320x8
        sta     rptr+2
        ldx     #.loword(irqrec)
        stx     rptr
        ldy     #0
:       lda     [rptr],y
        tyx
        sta     t_rec,x
        iny
        cpy     #REC
        bne     :-
        ; without IRQ_EN: IRQ_STATUS.BLITTER stays 0
        lda     #$10
        sta     f:IRQ_STATUS
        jsr     setregs
        lda     #$01
        sta     f:BL_CTRL
        jsr     waitbl
        lda     f:IRQ_STATUS
        and     #$10
        bne     @bad
        ; with IRQ_EN: the interrupt comes once, after BUSY has dropped
        stz     irqflag
        lda     #$FF
        sta     irqbusy
        lda     #$10
        sta     f:IRQ_EN
        cli
        lda     #$03
        sta     f:BL_CTRL
        ldx     #0
:       lda     irqflag
        bne     @got
        dex
        bne     :-
        bra     @bad                    ; no interrupt within ~65536 loops
@got:   ldx     #2000                   ; and no second one
:       dex
        bne     :-
        sei
        lda     #$00
        sta     f:IRQ_EN
        lda     irqflag
        cmp     #1
        bne     @bad
        lda     irqbusy                 ; BL_CTRL read in the handler: IRQ_EN, not BUSY
        and     #$03                    ; (REV $09: bit 4 DONE is set too)
        cmp     #$02
        bne     @bad
        lda     #$00
        sta     f:BL_CTRL
        ldx     #.loword(m_irqok)
        jmp     puts
@bad:   sei
        lda     #$00
        sta     f:IRQ_EN
        sta     f:BL_CTRL
        ldx     #.loword(m_firq)
        jsr     puts
        jmp     failinc

irq_h:  php
        sep     #$20
        .a8
        pha
        lda     f:BL_CTRL
        sta     irqbusy
        lda     #$10
        sta     f:IRQ_STATUS
        inc     irqflag
        pla
        plp
        rti

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

bitmask: .byte  $80, $40, $20, $10, $08, $04, $02, $01
m_hello: .byte  "BLITTER TEST", 10, 0
m_regok: .byte  "REGISTERS OK", 10, 0
m_freg:  .byte  "FAIL REGISTERS", 10, 0
m_irqok: .byte  "IRQ OK", 10, 0
m_firq:  .byte  "FAIL IRQ", 10, 0
m_run:   .byte  "RUN ", 0
m_long:  .byte  " LONG ", 0
m_nvc:   .byte  " NVC ", 0
m_late:  .byte  "LATE ", 0
m_flate: .byte  "FAIL NVC LATE", 10, 0
m_ft:    .byte  "FAIL T", 0
m_at:    .byte  " AT +", 0
m_got:   .byte  " GOT ", 0
m_want:  .byte  " WANT ", 0
m_fham:  .byte  "FAIL HAMMER T", 0
m_nobusy: .byte "BUSY NEVER SEEN (EMULATOR?)", 10, 0
m_pass:  .byte  "BLITTER PASS", 10, 0
m_fail:  .byte  "BLITTER FAIL ", 0
m_done:  .byte  "DONE", 10, 0

tests:
; generated table: op, flags, src, sstr, dst, dstr, w, h, fg, bg, key, pattern mask, mode (bit 0 = CPU hammers)
        T 0, $00, $001000, 0, $001000, 37, 1, 3, $01, $A5, $02, $FF, 0   ; 01 fill w1
        T 0, $00, $001001, 0, $001001, 38, 2, 3, $12, $A5, $02, $FF, 0   ; 02 fill w2
        T 0, $00, $001002, 0, $001002, 39, 3, 3, $23, $A5, $02, $FF, 0   ; 03 fill w3
        T 0, $00, $001003, 0, $001003, 40, 4, 3, $34, $A5, $02, $FF, 0   ; 04 fill w4
        T 0, $00, $001000, 0, $001000, 41, 5, 3, $45, $A5, $02, $FF, 0   ; 05 fill w5
        T 0, $00, $001001, 0, $001001, 42, 7, 3, $56, $A5, $02, $FF, 0   ; 06 fill w7
        T 0, $00, $001002, 0, $001002, 43, 8, 3, $67, $A5, $02, $FF, 0   ; 07 fill w8
        T 0, $00, $001003, 0, $001003, 44, 9, 3, $78, $A5, $02, $FF, 0   ; 08 fill w9
        T 0, $00, $001000, 0, $001000, 45, 15, 3, $89, $A5, $02, $FF, 0   ; 09 fill w15
        T 0, $00, $001001, 0, $001001, 46, 16, 3, $9A, $A5, $02, $FF, 0   ; 0A fill w16
        T 0, $00, $001002, 0, $001002, 47, 17, 3, $AB, $A5, $02, $FF, 0   ; 0B fill w17
        T 0, $00, $001003, 0, $001003, 48, 33, 3, $BC, $A5, $02, $FF, 0   ; 0C fill w33
        T 0, $01, $001003, 0, $001003, 41, 17, 4, $77, $A5, $02, $FF, 0   ; 0D fill backwards
        T 0, $00, $001001, 0, $001001, 1, 5, 7, $5A, $A5, $02, $FF, 0   ; 0E fill, stride 1
        T 1, $00, $001000, 50, $001201, 37, 1, 3, $5A, $A5, $02, $FF, 0   ; 0F copy w1 src+0 dst+1
        T 1, $00, $001001, 51, $001200, 38, 2, 3, $5A, $A5, $02, $FF, 0   ; 10 copy w2 src+1 dst+0
        T 1, $00, $001002, 52, $001203, 39, 3, 3, $5A, $A5, $02, $FF, 0   ; 11 copy w3 src+2 dst+3
        T 1, $00, $001003, 53, $001202, 40, 4, 3, $5A, $A5, $02, $FF, 0   ; 12 copy w4 src+3 dst+2
        T 1, $00, $001000, 54, $001201, 41, 5, 3, $5A, $A5, $02, $FF, 0   ; 13 copy w5 src+0 dst+1
        T 1, $00, $001001, 50, $001200, 42, 7, 3, $5A, $A5, $02, $FF, 0   ; 14 copy w7 src+1 dst+0
        T 1, $00, $001002, 51, $001203, 43, 8, 3, $5A, $A5, $02, $FF, 0   ; 15 copy w8 src+2 dst+3
        T 1, $00, $001003, 52, $001202, 44, 9, 3, $5A, $A5, $02, $FF, 0   ; 16 copy w9 src+3 dst+2
        T 1, $00, $001000, 53, $001201, 45, 15, 3, $5A, $A5, $02, $FF, 0   ; 17 copy w15 src+0 dst+1
        T 1, $00, $001001, 54, $001200, 46, 16, 3, $5A, $A5, $02, $FF, 0   ; 18 copy w16 src+1 dst+0
        T 1, $00, $001002, 50, $001203, 47, 17, 3, $5A, $A5, $02, $FF, 0   ; 19 copy w17 src+2 dst+3
        T 1, $00, $001003, 51, $001202, 48, 33, 3, $5A, $A5, $02, $FF, 0   ; 1A copy w33 src+3 dst+2
        T 1, $00, $001000, 48, $001200, 64, 16, 3, $5A, $A5, $02, $FF, 0   ; 1B copy aligned w16
        T 1, $00, $001000, 48, $001200, 64, 33, 3, $5A, $A5, $02, $FF, 0   ; 1C copy aligned w33
        T 1, $00, $001000, 48, $001200, 64, 64, 3, $5A, $A5, $02, $FF, 0   ; 1D copy aligned w64
        T 1, $01, $001002, 45, $001201, 39, 1, 4, $5A, $A5, $02, $FF, 0   ; 1E copy backwards w1
        T 1, $01, $001002, 45, $001201, 39, 5, 4, $5A, $A5, $02, $FF, 0   ; 1F copy backwards w5
        T 1, $01, $001002, 45, $001201, 39, 17, 4, $5A, $A5, $02, $FF, 0   ; 20 copy backwards w17
        T 1, $01, $001002, 45, $001201, 39, 33, 4, $5A, $A5, $02, $FF, 0   ; 21 copy backwards w33
        T 2, $00, $001001, 40, $001202, 44, 3, 3, $5A, $A5, $02, $03, 0   ; 22 copy_key w3
        T 2, $00, $001002, 40, $001203, 44, 9, 3, $5A, $A5, $02, $03, 0   ; 23 copy_key w9
        T 2, $00, $001003, 40, $001204, 44, 33, 3, $5A, $A5, $02, $03, 0   ; 24 copy_key w33
        T 2, $01, $001004, 40, $001205, 44, 17, 3, $5A, $A5, $02, $03, 0   ; 25 copy_key w17
        T 2, $01, $001005, 40, $001206, 44, 8, 3, $5A, $A5, $02, $03, 0   ; 26 copy_key w8
        T 3, $00, $001000, 5, $001200, 41, 1, 3, $C3, $3C, $02, $FF, 0   ; 27 expand bit0 w1
        T 3, $10, $001001, 6, $001201, 41, 3, 3, $C3, $3C, $02, $FF, 0   ; 28 expand bit1 w3
        T 3, $20, $001002, 7, $001202, 41, 9, 3, $C3, $3C, $02, $FF, 0   ; 29 expand bit2 w9
        T 3, $30, $001003, 8, $001203, 41, 17, 3, $C3, $3C, $02, $FF, 0   ; 2A expand bit3 w17
        T 3, $40, $001004, 9, $001200, 41, 33, 3, $C3, $3C, $02, $FF, 0   ; 2B expand bit4 w33
        T 3, $50, $001005, 10, $001201, 41, 15, 3, $C3, $3C, $02, $FF, 0   ; 2C expand bit5 w15
        T 3, $60, $001006, 11, $001202, 41, 8, 3, $C3, $3C, $02, $FF, 0   ; 2D expand bit6 w8
        T 3, $70, $001007, 12, $001203, 41, 16, 3, $C3, $3C, $02, $FF, 0   ; 2E expand bit7 w16
        T 4, $70, $001003, 6, $001201, 43, 9, 4, $E1, $A5, $02, $FF, 0   ; 2F expand_key bit7
        T 4, $00, $001003, 6, $001202, 43, 33, 4, $E1, $A5, $02, $FF, 0   ; 30 expand_key bit0
        T 4, $30, $001003, 6, $001203, 43, 4, 4, $E1, $A5, $02, $FF, 0   ; 31 expand_key bit3
        T 4, $50, $001003, 6, $001204, 43, 13, 4, $E1, $A5, $02, $FF, 0   ; 32 expand_key bit5
        T 3, $21, $001000, 4, $001202, 40, 19, 3, $5A, $A5, $02, $FF, 0   ; 33 expand backwards
        T 4, $61, $001001, 5, $001203, 40, 23, 3, $5A, $A5, $02, $FF, 0   ; 34 expand_key backwards
        T 1, $00, $002000, 64, $001FFF, 64, 33, 4, $5A, $A5, $02, $FF, 0   ; 35 overlap forwards -1
        T 1, $00, $002000, 64, $001FFD, 64, 17, 3, $5A, $A5, $02, $FF, 0   ; 36 overlap forwards -3
        T 1, $00, $002000, 64, $001FC0, 64, 33, 5, $5A, $A5, $02, $FF, 0   ; 37 overlap forwards -64
        T 1, $00, $002000, 64, $001FBD, 64, 20, 5, $5A, $A5, $02, $FF, 0   ; 38 overlap forwards -67
        T 1, $00, $002000, 64, $001FC5, 64, 17, 4, $5A, $A5, $02, $FF, 0   ; 39 overlap forwards -59
        T 1, $00, $002000, 64, $001FFC, 64, 16, 3, $5A, $A5, $02, $FF, 0   ; 3A overlap forwards -4
        T 1, $00, $002000, 64, $001F81, 64, 40, 6, $5A, $A5, $02, $FF, 0   ; 3B overlap forwards -127
        T 1, $01, $002000, 64, $002001, 64, 33, 4, $5A, $A5, $02, $FF, 0   ; 3C overlap backwards +1
        T 1, $01, $002000, 64, $002003, 64, 17, 3, $5A, $A5, $02, $FF, 0   ; 3D overlap backwards +3
        T 1, $01, $002000, 64, $002040, 64, 33, 5, $5A, $A5, $02, $FF, 0   ; 3E overlap backwards +64
        T 1, $01, $002000, 64, $002042, 64, 20, 5, $5A, $A5, $02, $FF, 0   ; 3F overlap backwards +66
        T 1, $01, $002000, 64, $00203B, 64, 17, 4, $5A, $A5, $02, $FF, 0   ; 40 overlap backwards +59
        T 1, $01, $002000, 64, $002004, 64, 16, 3, $5A, $A5, $02, $FF, 0   ; 41 overlap backwards +4
        T 1, $01, $002000, 64, $00207F, 64, 40, 6, $5A, $A5, $02, $FF, 0   ; 42 overlap backwards +127
        T 1, $01, $002000, 64, $002005, 64, 9, 1, $5A, $A5, $02, $FF, 0   ; 43 overlap backwards +5
        T 2, $01, $002000, 64, $002041, 64, 25, 4, $5A, $A5, $01, $03, 0   ; 44 copy_key overlap backwards
        T 2, $00, $002000, 64, $001FBF, 64, 25, 4, $5A, $A5, $01, $03, 0   ; 45 copy_key overlap forwards
        T 0, $00, $00FF03, 0, $00FF03, 100, 33, 6, $99, $A5, $02, $FF, 0   ; 46 fill across a bank
        T 1, $00, $00FF81, 120, $010F02, 90, 37, 5, $5A, $A5, $02, $FF, 0   ; 47 copy from across a bank
        T 1, $01, $00FFC0, 100, $00FFF1, 100, 33, 4, $5A, $A5, $02, $FF, 0   ; 48 copy backwards across a bank
        T 3, $50, $00FFFC, 3, $00FFE0, 200, 21, 6, $5A, $A5, $02, $FF, 0   ; 49 expand across a bank
        T 1, $00, $00FFFB, 64, $00FFF7, 64, 17, 3, $5A, $A5, $02, $FF, 0   ; 4A lines crossing the bank
        T 0, $00, $001000, 0, $001000, 40, 0, 3, $5A, $A5, $02, $FF, 0   ; 4B width 0
        T 1, $00, $001000, 40, $001000, 40, 5, 0, $5A, $A5, $02, $FF, 0   ; 4C height 0
        T 5, $00, $001000, 40, $001000, 40, 5, 3, $5A, $A5, $02, $FF, 0   ; 4D op 5
        T 1, $00, $001000, 1000, $001803, 1003, 9, 3, $5A, $A5, $02, $FF, 0   ; 4E large strides
        T 1, $00, $004001, 320, $004A03, 330, 160, 10, $5A, $A5, $02, $FF, 1   ; 4F copy, CPU hammering
        T 0, $00, $004002, 0, $004002, 330, 250, 10, $5A, $A5, $02, $FF, 1   ; 50 fill, CPU hammering
        T 3, $30, $004000, 30, $004201, 330, 230, 10, $5A, $A5, $02, $FF, 1   ; 51 expand, CPU hammering
        T 1, $01, $004000, 320, $004283, 320, 200, 10, $5A, $A5, $02, $FF, 1   ; 52 overlap backwards, CPU hammering
irqrec:
        T 0, $00, $010A00, 0, $010A00, 640, 320, 8, $5A, $A5, $02, $FF, 0   ; 53 speed: fill 320x8
        T 1, $00, $010000, 320, $010A00, 640, 320, 8, $5A, $A5, $02, $FF, 0   ; 54 speed: copy aligned 320x8
        T 1, $00, $010001, 320, $010A03, 640, 320, 8, $5A, $A5, $02, $FF, 0   ; 55 speed: copy unaligned 320x8
        T 3, $70, $010000, 40, $010A00, 640, 320, 8, $5A, $A5, $02, $FF, 0   ; 56 speed: expand 320x8
        .byte   $FF
