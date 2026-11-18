; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816: blitter command lists and raster events (REV $09). Self-checking.
;
;   LIST     the records of the table below run once as a command list (area A) and once
;            one by one through the registers (area B, the same records $4000 higher); both
;            areas start with the same bytes and must end equal. Also: one interrupt, DONE,
;            BL_LIST / BL_COUNT after the list, the registers hold the last record.
;   EMPTY    LIST with BL_COUNT 0 finishes at once, with its interrupt
;   ABORT    a list of 30 large fills: register writes while BUSY are ignored, ABORT stops it
;            (BUSY drops, ABORTED, no interrupt), then a single blit works
;   VBL      three records with WAIT_VBL: NV_FRAME advances by 3, the last blit runs at line 360
;   RASTER   VBLANK and LINE interrupts: LINE at line 100 reads NV_LINE 100 every time, one LINE
;            per frame, NV_FRAME counts VBLANKs; frame time from UPTIME; modes 0 and 2
;   SPEED    100 keyed 16x16 copies: one by one from the CPU, then as one list (times printed)
; Output ends with "BLITLIST PASS" or "BLITLIST FAIL nn", then DONE.
; ca65 -D SIM: shorter waits for the Verilator testbench.
        .p816
        .smart  -

BL_SRC      = $00DA00
BL_DST      = $00DA05
BL_W        = $00DA0A
BL_OP       = $00DA11
BL_CTRL     = $00DA13
BL_LIST     = $00DA14
BL_COUNT    = $00DA17
CACHE_FLUSH = $00D80A
NV_CTRL     = $00D900
NV_BASE     = $00D901
NV_LINE     = $00D906
NV_CMP      = $00D908
NV_FRAME    = $00D90C
SV_CTRL     = $00DC00
SYS_REV     = $00DE01
IRQ_STATUS  = $00DE08
IRQ_EN      = $00DE09
UPTIME      = $00DE18
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1

LIST        = $020000           ; command records
AREA        = $030000           ; area A $03:0000-$03:3FFF, area B $03:4000-$03:7FFF
SPR         = $040000           ; 16x16 sprite for SPEED
FB          = $050000           ; 640-wide destination for SPEED and ABORT
NREC        = (tab_end - tab) / 24

; direct page
p0          = $20               ; 4: pointer
p1          = $24               ; 4: pointer
t0          = $28               ; 4: UPTIME
t1          = $2C               ; 4
nfail       = $30               ; 2
lfsr        = $32               ; 2
cnt         = $34               ; 2
n_blit      = $36               ; 2: BLITTER interrupts
n_vbl       = $38               ; 2: VBLANK interrupts
n_line      = $3A               ; 2: LINE interrupts
n_badline   = $3C               ; 2: NV_LINE read in a LINE interrupt was not NV_LINE_CMP
cmpv        = $3E               ; 2: the current NV_LINE_CMP
f0          = $40               ; 2: NV_FRAME
tmp         = $42               ; 2
seenw       = $44               ; 1: WAITING seen

.macro R op, fl, src, sstr, dst, dstr, w, h, fg, bg, key, rf
        .faraddr src
        .word   sstr
        .faraddr dst
        .word   dstr, w, h
        .byte   fg, bg, key, op, fl, rf, 0, 0, 0, 0
.endmacro

.macro print msg
        ldx     #.loword(msg)
        jsr     puts
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
        stz     n_blit
        stz     n_vbl
        stz     n_line
        stz     n_badline
        lda     #511
        sta     cmpv
        sep     #$20
        .a8
        lda     #$04                    ; freeze the classic machine (16-byte bursts)
        sta     f:SV_CTRL
        jsr     irqinit
        jsr     t_list
        jsr     t_empty
        jsr     t_abort
        jsr     t_vbl
        jsr     t_raster
        jsr     t_speed
        sei
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

; ── interrupts: count BLITTER, VBLANK, LINE; LINE also checks NV_LINE ─────────
irqinit:
        sei
        lda     #$5C                    ; trampoline at $00:E008: JML irq_h
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
        lda     #$FF
        sta     f:IRQ_STATUS
        lda     #$13                    ; BLITTER, LINE, VBLANK
        sta     f:IRQ_EN
        cli
        rts

irq_h:  rep     #$30
        .a16
        .i16
        pha
        phb
        phk
        plb
        sep     #$20
        .a8
        lda     f:IRQ_STATUS
        sta     f:IRQ_STATUS            ; W1C what we saw
        bit     #$02
        beq     @nl
        pha
        lda     f:NV_LINE
        xba
        lda     f:NV_LINE+1
        xba
        rep     #$20
        .a16
        cmp     cmpv
        beq     :+
        inc     n_badline
:       inc     n_line
        sep     #$20
        .a8
        pla
@nl:    bit     #$01
        beq     @nv
        rep     #$20
        inc     n_vbl
        sep     #$20
@nv:    bit     #$10
        beq     @nb
        rep     #$20
        inc     n_blit
        sep     #$20
@nb:    rep     #$30
        plb
        pla
        rti
        .a8

waitbl: lda     f:BL_CTRL
        lsr
        bcs     waitbl
        rts

; short pause (X loops)
pause:  dex
        bne     pause
        rts

; ── LIST: the table as a list on area A, one by one on area B ────────────────
t_list:
        jsr     areainit
        ; build the list: the table with SRC / DST in area A (bank $03)
        rep     #$20
        .a16
        lda     #.loword(LIST)
        sta     p0
        sep     #$20
        .a8
        lda     #^LIST
        sta     p0+2
        ldx     #0
        txy
@b:     lda     tab,x
        sta     [p0],y
        inx
        iny
        cpy     #NREC*24
        bne     @b
        ldy     #2
@bk:    lda     #^AREA
        sta     [p0],y                  ; SRC bank (offsets are below $4000: bank only)
        iny
        iny
        iny
        iny
        iny
        sta     [p0],y                  ; DST bank
        rep     #$21
        .a16
        tya
        adc     #19
        tay
        sep     #$20
        .a8
        cpy     #NREC*24+2
        bne     @bk
        ; one by one on area B
        ldx     #0
@r:     phx
        ldy     #0
@rr:    lda     tab,x
        cpy     #1                      ; SRC and DST + $4000, bank $03
        beq     @m
        cpy     #6
        bne     @nm
@m:     ora     #$40
@nm:    cpy     #2
        beq     @bnk
        cpy     #7
        bne     @w
@bnk:   lda     #^AREA
@w:     phx
        tyx
        sta     f:BL_SRC,x
        plx
        inx
        iny
        cpy     #19
        bne     @rr
        lda     #$01
        sta     f:BL_CTRL
        jsr     waitbl
        rep     #$21
        .a16
        pla
        adc     #24
        tax
        sep     #$20
        .a8
        cpx     #NREC*24
        bne     @r
        ; the list on area A, with its interrupt
        rep     #$20
        .a16
        stz     n_blit
        sep     #$20
        .a8
        lda     #0
        sta     f:BL_LIST
        sta     f:BL_LIST+1
        lda     #^LIST
        sta     f:BL_LIST+2
        lda     #NREC
        sta     f:BL_COUNT
        lda     #0
        sta     f:BL_COUNT+1
        lda     #$06                    ; LIST, IRQ_EN
        sta     f:BL_CTRL
        lda     f:BL_CTRL
        and     #$05
        cmp     #$05                    ; BUSY and LIST at once
        beq     :+
        print   m_flb
        jsr     failinc
:       jsr     waitbl
        ldx     #200
        jsr     pause
        lda     f:BL_CTRL
        cmp     #$12                    ; IRQ_EN, DONE
        bne     @bad
        lda     n_blit
        cmp     #1
        bne     @bad
        lda     f:BL_COUNT
        ora     f:BL_COUNT+1
        bne     @bad
        lda     f:BL_LIST               ; NREC * 24 past the start
        cmp     #<(NREC*24)
        bne     @bad
        lda     f:BL_LIST+1
        cmp     #>(NREC*24)
        bne     @bad
        lda     f:BL_W                  ; registers: the last record
        cmp     tab_end-24+10
        bne     @bad
        lda     f:BL_OP
        cmp     tab_end-24+17
        bne     @bad
        ; compare A and B
        sta     f:CACHE_FLUSH
        rep     #$20
        .a16
        lda     #.loword(AREA)
        sta     p0
        lda     #.loword(AREA+$4000)
        sta     p1
        sep     #$20
        .a8
        lda     #^AREA
        sta     p0+2
        sta     p1+2
        ldy     #0
@c:     lda     [p0],y
        cmp     [p1],y
        bne     @diff
        iny
        cpy     #$4000
        bne     @c
        print   m_listok
        rts
@diff:  print   m_fdiff
        rep     #$20
        .a16
        tya
        sep     #$20
        .a8
        xba
        jsr     puthex
        xba
        jsr     puthex
        jsr     nl
        jmp     failinc
@bad:   print   m_flist
        lda     f:BL_CTRL
        jsr     puthex
        lda     n_blit
        jsr     puthex
        jsr     nl
        jmp     failinc

; both areas: the same pseudo-random bytes (values $20-$27: keys and EXPAND bits both hit)
areainit:
        rep     #$20
        .a16
        lda     #.loword(AREA)
        sta     p0
        lda     #$ACE1
        sta     lfsr
        sep     #$20
        .a8
        lda     #^AREA
        sta     p0+2
        ldy     #0
@i:     rep     #$20
        .a16
        lda     lfsr
        lsr
        bcc     :+
        eor     #$B400
:       sta     lfsr
        sep     #$20
        .a8
        and     #$07
        ora     #$20
        sta     [p0],y
        iny
        cpy     #$4000
        bne     @i
        ldy     #0                      ; copy A to B
@k:     lda     [p0],y
        pha
        rep     #$21
        .a16
        tya
        adc     #$4000
        tax
        sep     #$20
        .a8
        pla
        phy
        txy
        sta     [p0],y
        ply
        iny
        cpy     #$4000
        bne     @k
        rts

; ── EMPTY: BL_COUNT 0 ────────────────────────────────────────────────────────
t_empty:
        rep     #$20
        .a16
        stz     n_blit
        sep     #$20
        .a8
        lda     #0
        sta     f:BL_COUNT
        sta     f:BL_COUNT+1
        lda     #$06
        sta     f:BL_CTRL
        ldx     #100
        jsr     pause
        lda     f:BL_CTRL
        cmp     #$12
        bne     @bad
        lda     n_blit
        cmp     #1
        bne     @bad
        print   m_emptyok
        rts
@bad:   print   m_fempty
        jmp     failinc

; ── ABORT ────────────────────────────────────────────────────────────────────
; 30 records: FILL 640 x 40 at FB (about 2 ms each)
t_abort:
        rep     #$20
        .a16
        lda     #.loword(LIST)
        sta     p0
        stz     n_blit
        sep     #$20
        .a8
        lda     #^LIST
        sta     p0+2
        ldy     #0
@b:     ldx     #0
:       lda     fillrec,x
        sta     [p0],y
        iny
        inx
        cpx     #24
        bne     :-
        cpy     #30*24
        bne     @b
        lda     #0
        sta     f:BL_LIST
        sta     f:BL_LIST+1
        sta     f:BL_COUNT+1
        lda     #^LIST
        sta     f:BL_LIST+2
        lda     #30
        sta     f:BL_COUNT
        lda     #$06
        sta     f:BL_CTRL
:       lda     f:BL_COUNT              ; wait until the third record runs
        cmp     #28
        bcs     :-
        lda     #$55                    ; ignored while BUSY
        sta     f:BL_W
        sta     f:BL_COUNT
        lda     f:BL_COUNT
        sta     tmp
        lda     #$0A                    ; ABORT (IRQ_EN stays set)
        sta     f:BL_CTRL
        ldx     #0
:       lda     f:BL_CTRL
        lsr
        bcc     @stopped
        inx
        cpx     #20
        bne     :-
        print   m_fab1                  ; BUSY did not drop within 20 reads
        jmp     failinc
@stopped:
        ldx     #2000
        jsr     pause
        lda     f:BL_CTRL
        cmp     #$22                    ; IRQ_EN, ABORTED
        bne     @bad
        lda     n_blit                  ; no interrupt
        bne     @bad
        lda     f:BL_W
        cmp     fillrec+10
        bne     @bad
        lda     f:BL_COUNT
        cmp     tmp
        bne     @bad
        cmp     #28
        bcs     @bad
        ; a single blit afterwards: fill 8 x 1 at FB with $3C, without IRQ_EN
        lda     #8
        sta     f:BL_W
        lda     #0
        sta     f:BL_W+1
        lda     #1
        sta     f:BL_W+2
        lda     #$3C
        sta     f:BL_W+4                ; BL_FG
        lda     #$01
        sta     f:BL_CTRL
        jsr     waitbl
        lda     f:BL_CTRL
        cmp     #$10                    ; DONE only
        bne     @bad
        sta     f:CACHE_FLUSH
        lda     f:FB+7
        cmp     #$3C
        bne     @bad
        print   m_abortok
        rts
@bad:   print   m_fabort
        lda     f:BL_CTRL
        jsr     puthex
        lda     n_blit
        jsr     puthex
        lda     f:BL_COUNT
        jsr     puthex
        jsr     nl
        jmp     failinc

fillrec: R 0, 0, 0, 0, FB, 640, 640, 40, $11, 0, 0, 0

; ── VBL: three WAIT_VBL records ──────────────────────────────────────────────
t_vbl:
        rep     #$20
        .a16
        lda     #.loword(LIST)
        sta     p0
        sep     #$20
        .a8
        lda     #^LIST
        sta     p0+2
        ldy     #0
@b:     ldx     #0
:       lda     vblrec,x
        sta     [p0],y
        iny
        inx
        cpx     #24
        bne     :-
        cpy     #3*24
        bne     @b
        lda     #0
        sta     f:BL_LIST
        sta     f:BL_LIST+1
        sta     f:BL_COUNT+1
        lda     #^LIST
        sta     f:BL_LIST+2
        lda     #3
        sta     f:BL_COUNT
        jsr     rdframe
        sta     f0
        stz     seenw
        lda     #$04                    ; LIST, no interrupt
        sta     f:BL_CTRL
:       lda     f:BL_CTRL
        bit     #$08
        beq     :+
        sta     seenw
:       lsr
        bcs     :--
        jsr     rdframe
        sec
        sbc     f0
        cmp     #3
        bne     @bad
        lda     f:NV_LINE               ; the last blit ran right after VBLANK
        cmp     #<360
        bne     @bad
        lda     seenw
        beq     @bad
        print   m_vblok
        rts
@bad:   print   m_fvbl
        jmp     failinc

vblrec: R 0, 0, 0, 0, FB, 640, 4, 1, $22, 0, 0, 1

rdframe:
        lda     f:NV_FRAME
        xba
        lda     f:NV_FRAME+1
        xba
        rts

; ── RASTER: VBLANK and LINE ──────────────────────────────────────────────────
.ifdef SIM
NFR = 3
.else
NFR = 60
.endif
t_raster:
        lda     #100                    ; LINE at line 100
        sta     cmpv
        stz     cmpv+1
        sta     f:NV_CMP
        lda     #0
        sta     f:NV_CMP+1
        jsr     frames                  ; NV_CTRL 0: the events run with Marga off
        bne     @bad
        print   m_frames
        lda     #NFR
        jsr     puthex
        print   m_us
        lda     t1+3
        jsr     puthex
        lda     t1+2
        jsr     puthex
        lda     t1+1
        jsr     puthex
        lda     t1
        jsr     puthex
        jsr     nl
        lda     #<(FB >> 8)             ; mode 2 (320x180) on, from FB
        sta     f:NV_BASE+1
        lda     #^FB
        sta     f:NV_BASE+2
        lda     #$05
        sta     f:NV_CTRL
        jsr     frames
        bne     @bad
        lda     #0
        sta     f:NV_CTRL
        lda     #<511
        sta     f:NV_CMP
        lda     #>511
        sta     f:NV_CMP+1
        sta     cmpv+1
        print   m_rasterok
        rts
@bad:   print   m_fraster
        rep     #$20
        .a16
        lda     n_line
        sep     #$20
        .a8
        jsr     puthex
        lda     n_badline
        jsr     puthex
        lda     n_vbl
        jsr     puthex
        jsr     nl
        jmp     failinc

; NFR frames from one VBLANK to another: NFR LINE events, all at line 100, NFR VBLANKs,
; NV_FRAME + NFR. t1 = microseconds. Z = 1 if all good.
frames: jsr     waitvbl
        jsr     rdup
        rep     #$20
        .a16
        lda     t1
        sta     t0
        lda     t1+2
        sta     t0+2
        stz     n_line
        stz     n_badline
        stz     n_vbl
        sep     #$20
        .a8
        jsr     rdframe
        sta     f0
:       lda     n_vbl
        cmp     #NFR
        bne     :-
        jsr     rdup
        jsr     rdframe
        sec
        sbc     f0
        cmp     #NFR
        bne     @r
        lda     n_line
        cmp     #NFR
        bne     @r
        lda     n_badline
        bne     @r
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
        lda     #0
@r:     rts

waitvbl:
        lda     n_vbl
:       cmp     n_vbl
        beq     :-
        rts

rdup:   lda     f:UPTIME
        sta     t1
        lda     f:UPTIME+1
        sta     t1+1
        lda     f:UPTIME+2
        sta     t1+2
        lda     f:UPTIME+3
        sta     t1+3
        rts

; ── SPEED: 100 keyed 16x16 copies to FB ──────────────────────────────────────
t_speed:
        ; the sprite: a disc of colour $40+ (key 0 around it)
        rep     #$20
        .a16
        lda     #.loword(SPR)
        sta     p0
        sep     #$20
        .a8
        lda     #^SPR
        sta     p0+2
        ldy     #0
@s:     tya
        and     #$0F
        sec
        sbc     #8
        bpl     :+
        eor     #$FF
:       sta     tmp
        tya
        lsr
        lsr
        lsr
        lsr
        sec
        sbc     #8
        bpl     :+
        eor     #$FF
:       clc
        adc     tmp
        cmp     #9
        lda     #0
        bcs     :+
        tya
        ora     #$40
:       sta     [p0],y
        iny
        cpy     #256
        bne     @s
        ; the list: 100 records
        rep     #$20
        .a16
        lda     #.loword(LIST)
        sta     p0
        sep     #$20
        .a8
        lda     #^LIST
        sta     p0+2
        ldy     #0
        stz     cnt
        stz     cnt+1
@l:     ldx     #0
:       lda     sprrec,x
        sta     [p0],y
        iny
        inx
        cpx     #24
        bne     :-
        rep     #$21
        .a16
        lda     cnt                     ; DST = FB + cnt * 324 (half a line and 4 pixels on)
        xba
        and     #$FF00
        sta     tmp                     ; 256 * cnt
        lda     cnt
        asl
        asl
        asl
        asl
        asl
        asl
        adc     tmp
        sta     tmp                     ; + 64 * cnt
        lda     cnt
        asl
        asl
        adc     tmp                     ; + 4 * cnt
        phy
        pha
        tya
        sec
        sbc     #19                     ; back to the record's DST (offset 5)
        tay
        pla
        sta     [p0],y
        ply
        sep     #$20
        .a8
        inc     cnt
        lda     cnt
        cmp     #100
        bne     @l
        ; one by one: the common fields once, then DST and START per copy
        ldx     #0
:       lda     sprrec,x
        phx
        sta     f:BL_SRC,x
        plx
        inx
        cpx     #19
        bne     :-
        jsr     rdup
        rep     #$20
        .a16
        lda     t1
        sta     t0
        lda     t1+2
        sta     t0+2
        lda     #.loword(LIST+5)
        sta     p1
        sep     #$20
        .a8
        lda     #^LIST
        sta     p1+2
        ldx     #100
@o:     lda     f:BL_CTRL
        lsr
        bcs     @o
        rep     #$20
        .a16
        lda     [p1]
        sta     f:BL_DST
        sep     #$20
        .a8
        ldy     #2
        lda     [p1],y
        sta     f:BL_DST+2
        lda     #$01
        sta     f:BL_CTRL
        rep     #$21
        .a16
        lda     p1
        adc     #24
        sta     p1
        sep     #$20
        .a8
        dex
        bne     @o
        jsr     waitbl
        jsr     rdup
        jsr     usdiff
        print   m_one
        jsr     put32
        ; the list
        jsr     rdup
        rep     #$20
        .a16
        lda     t1
        sta     t0
        lda     t1+2
        sta     t0+2
        sep     #$20
        .a8
        lda     #0
        sta     f:BL_LIST
        sta     f:BL_LIST+1
        sta     f:BL_COUNT+1
        lda     #^LIST
        sta     f:BL_LIST+2
        lda     #100
        sta     f:BL_COUNT
        lda     #$04
        sta     f:BL_CTRL
        jsr     waitbl
        jsr     rdup
        jsr     usdiff
        print   m_lst
        jsr     put32
        rts

sprrec: R 2, 0, SPR, 16, FB, 640, 16, 16, 0, 0, 0, 0

usdiff: rep     #$20
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
        rts

put32:  lda     t1+3
        jsr     puthex
        lda     t1+2
        jsr     puthex
        lda     t1+1
        jsr     puthex
        lda     t1
        jsr     puthex
        jmp     nl

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

m_hello:   .byte "BLITTER LIST TEST REV ", 0
m_listok:  .byte "LIST OK", 10, 0
m_flist:   .byte "FAIL LIST ", 0
m_flb:     .byte "FAIL LIST NOT BUSY", 10, 0
m_fdiff:   .byte "FAIL LIST DIFFERS AT +", 0
m_emptyok: .byte "EMPTY OK", 10, 0
m_fempty:  .byte "FAIL EMPTY", 10, 0
m_abortok: .byte "ABORT OK", 10, 0
m_fabort:  .byte "FAIL ABORT ", 0
m_fab1:    .byte "FAIL ABORT BUSY", 10, 0
m_vblok:   .byte "VBL WAIT OK", 10, 0
m_fvbl:    .byte "FAIL VBL WAIT", 10, 0
m_frames:  .byte "FRAMES ", 0
m_us:      .byte " US ", 0
m_rasterok: .byte "RASTER OK", 10, 0
m_fraster: .byte "FAIL RASTER ", 0
m_one:     .byte "100 BLITS ONE BY ONE US ", 0
m_lst:     .byte "100 BLITS AS A LIST US ", 0
m_pass:    .byte "BLITLIST PASS", 10, 0
m_fail:    .byte "BLITLIST FAIL ", 0
m_done:    .byte "DONE", 10, 0

; ── the LIST table: offsets in the 16 KB area, bank filled in ─────────────────
; op 0 FILL, 1 COPY, 2 COPY_KEY, 3 EXPAND, 4 EXPAND_KEY; flags bit 0 BACKWARDS, 6:4 SRC_BIT
tab:
        R 0, $00, $0000, 0,   $0101, 64, 13, 7, $41, 0, 0, 0          ; fill
        R 1, $00, $1003, 50,  $0203, 48, 33, 9, 0, 0, 0, 0            ; copy
        R 2, $00, $1100, 40,  $0302, 44, 17, 8, 0, 0, $23, 0          ; copy_key
        R 3, $70, $2000, 4,   $0400, 64, 29, 6, $51, $52, 0, 0        ; expand from bit 7
        R 4, $30, $2010, 5,   $0501, 64, 31, 5, $53, 0, 0, 0          ; expand_key from bit 3
        R 1, $00, $0100, 64,  $0110, 64, 40, 10, 0, 0, 0, 0           ; copy over the fill (overlap, forward)
        R 1, $01, $0100, 64,  $0102, 64, 40, 12, 0, 0, 0, 1           ; backwards overlap, WAIT_VBL
        R 0, $00, $0000, 0,   $0607, 1, 1, 1, $5F, 0, 0, 0            ; 1 x 1
        R 2, $01, $0200, 48,  $0700, 40, 21, 6, 0, 0, $25, 0          ; copy_key backwards
        R 0, $01, $0000, 0,   $0803, 33, 30, 4, $60, 0, 0, 0          ; fill backwards
        R 1, $00, $0700, 40,  $0900, 64, 64, 3, 0, 0, 0, 0            ; copies an earlier result
        R 3, $10, $2100, 3,   $0A05, 70, 17, 4, $61, $62, 0, 0        ; expand from bit 1
        R 9, $00, $0000, 0,   $0B00, 64, 8, 8, $63, 0, 0, 0           ; OP 9: does nothing
        R 0, $00, $0000, 0,   $0C00, 64, 0, 8, $64, 0, 0, 0           ; WIDTH 0: does nothing
        R 1, $00, $0B00, 1,   $0D00, 1, 1, 200, 0, 0, 0, 0            ; stride 1 column
tab_end:
