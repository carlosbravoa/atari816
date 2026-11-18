; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816 test of Marga's sprites and fine scrolling (REV $0B). Self-checking; ca65 -D SIM for
; the testbench, which also compares every pixel of the picture with its own model.
;
;   REGS     scroll registers and NV_SPR_CTRL read back
;   PEEK     the 128 record bytes read back through NV_SPR_PEEK; without COMMIT the set in use
;            stays as it was (all 0 after the reset)
;   COMMIT   a COMMIT made at line 100 is still PENDING at line 300 and done in vertical blank,
;            and then the set in use is the one written; a COMMIT made in vertical blank is
;            done within 50 us
;   LIMIT    9 sprites of 64 pixels on the same lines set OVERFLOW (budget 512), 8 do not
;   LOAD     640x360x8, all 16 sprites on the same 32 lines (32 x 32 at 4 bpp: the full
;            budget), a long blitter list and 8 voices of Lau at pitch $FFFF: AU_LATE, NV_LATE
;            and sprite LATE stay 0; the list's time with sprites off and on is printed
;   SCENES   (SIM only) random scenes in all three modes: positions over every edge, flips,
;            sizes, 4/8 bpp, BEHIND, scrolling, wrap, split; the testbench checks the pixels
; Output ends with "SPRTEST PASS" or "SPRTEST FAIL nn", then DONE.
        .p816
        .smart  -

NV_CTRL     = $00D900
NV_BASE     = $00D901
NV_STRIDE   = $00D904
NV_LINE     = $00D906
NV_LINE_CMP = $00D908
NV_LATE     = $00D90B
PTR_X       = $00D920
PTR_Y       = $00D922
PTR_HOT     = $00D924
PTR_IMG     = $00D925
NV_SCROLLX  = $00D930
NV_SCROLLY  = $00D932
NV_SCROLLX2 = $00D934
NV_SCROLLY2 = $00D936
NV_VHEIGHT  = $00D938
NV_SCTL     = $00D93A
NV_SPR_CTRL = $00D940
NV_COMMIT   = $00D941
NV_SPR_STAT = $00D942
NV_PEEK     = $00D943
NV_PEEKD    = $00D944
NV_SPR      = $00D980
AU_KEYON    = $00DB20
AU_KEYOFF   = $00DB21
AU_LATE     = $00DB26
AU_V        = $00DB80
BL_CTRL     = $00DA13
BL_LIST     = $00DA14
BL_COUNT    = $00DA17
SV_CTRL     = $00DC00
SYS_REV     = $00DE01
UPTIME      = $00DE18
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1

LIST        = $020000
PIMG        = $030000           ; pointer image
SIMG        = $040000           ; sprite images, 512 bytes each
SMP         = $060000           ; samples for LOAD
FB          = $080000           ; bitmap, up to 1024 x 400

p0          = $20               ; 4
t0          = $24               ; 4
t1          = $28               ; 4
nfail       = $2C               ; 2
tmp         = $30               ; 2
cnt         = $32               ; 2
seed        = $34               ; 2
k           = $36               ; 2
t_off       = $38               ; 4: list time, sprites off
scene       = $3C               ; 2
rec         = $40
xmask       = $48
xoff        = $4A
ymask       = $4C
yoff        = $4E
mode        = $50               ; 8: one record being built

.macro print msg
        ldx     #.loword(msg)
        jsr     puts
.endmacro

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
        lda     #$ACE1
        sta     seed
        sep     #$20
        .a8
        lda     f:SYS_REV
        cmp     #$0B
        bcs     :+
        print   m_norev
        jsr     failinc
        jmp     finish
:       lda     #$04                    ; classic machine frozen: 16-byte bursts
        sta     f:SV_CTRL
        jsr     t_regs
        jsr     t_peek
        jsr     t_commit
        jsr     t_limit
        jsr     t_load
.ifdef SIM
        jsr     t_scenes
.endif
finish: lda     #0
        sta     f:NV_CTRL
        sta     f:NV_SPR_CTRL
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

; ── helpers ──────────────────────────────────────────────────────────────────
; A16 <- NV_LINE
getline:
        rep     #$20
        .a16
        lda     f:NV_LINE
        sep     #$20
        .a8
        rts
; wait until NV_LINE = tmp (16-bit)
waitln: jsr     getline
        rep     #$20
        .a16
        cmp     tmp
        sep     #$20
        .a8
        bne     waitln
        rts
; wait for the start of the next vertical blank (NV_LINE becomes 360)
waitvbl:
:       jsr     getline
        rep     #$20
        .a16
        cmp     #360
        sep     #$20
        .a8
        bcs     :-
:       jsr     getline
        rep     #$20
        .a16
        cmp     #360
        sep     #$20
        .a8
        bcc     :-
        rts
; wait for X frames
frames: phx
        jsr     waitvbl
        plx
        dex
        bne     frames
        rts
; A16 <- next pseudo-random number (xorshift16)
rnd:    rep     #$20
        .a16
        lda     seed
        asl
        asl
        asl
        asl
        asl
        asl
        asl
        eor     seed
        sta     seed
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        eor     seed
        sta     seed
        xba
        and     #$FF00
        eor     seed
        sta     seed
        sep     #$20
        .a8
        rts
; write the 128 record bytes from the table at p0
wrrecs: ldy     #0
        tyx
:       lda     [p0],y
        sta     f:NV_SPR,x
        iny
        inx
        cpx     #128
        bne     :-
        rts
; A <- record byte X (0-255) through NV_SPR_PEEK
peek:   txa
        sta     f:NV_PEEK
        nop
        lda     f:NV_PEEKD
        rts
; commit and wait until it has been done (C = 1 if it took over 2 frames)
commitw:
        sta     f:NV_COMMIT
        ldx     #0
:       lda     f:NV_COMMIT
        lsr
        bcc     :+
        dex
        bne     :-
        sec
        rts
:       clc
        rts

; ── REGS ─────────────────────────────────────────────────────────────────────
t_regs: ldx     #0
:       lda     regv,x
        sta     f:NV_SCROLLX,x
        inx
        cpx     #11
        bne     :-
        ldx     #0
:       lda     f:NV_SCROLLX,x
        cmp     regr,x
        bne     @bad
        inx
        cpx     #11
        bne     :-
        lda     #$FF
        sta     f:NV_SPR_CTRL
        lda     f:NV_SPR_CTRL
        cmp     #$01
        bne     @bad
        lda     #0
        sta     f:NV_SPR_CTRL
        ldx     #0
:       sta     f:NV_SCROLLX,x
        inx
        cpx     #11
        bne     :-
        lda     f:NV_SPR_STAT
        and     #$03
        bne     @bad
        print   m_regok
        rts
@bad:   print   m_fregs
        txa
        jsr     puthex
        jsr     nl
        jmp     failinc
regv:   .byte   $BC, $FA, $F5, $FE, $34, $F2, $07, $FD, $77, $F1, $FF
regr:   .byte   $BC, $0A, $F5, $02, $34, $02, $07, $01, $77, $01, $03

; ── PEEK ─────────────────────────────────────────────────────────────────────
; records <- k * 7 + 3 (CTRL bytes then have EN set; SPR_EN stays 0 here)
t_peek: ldx     #0
        lda     #3
:       sta     f:NV_SPR,x
        clc
        adc     #7
        inx
        cpx     #128
        bne     :-
        ldx     #0
        lda     #3
        sta     tmp
:       jsr     peek
        cmp     tmp
        bne     @bad
        lda     tmp
        clc
        adc     #7
        sta     tmp
        inx
        cpx     #128
        bne     :-
        ldx     #2
        jsr     frames
        ldx     #128                    ; the set in use: still 0
:       jsr     peek
        bne     @bad
        inx
        cpx     #256
        bne     :-
        print   m_peekok
        rts
@bad:   print   m_fpeek
        txa
        xba
        txa
        jsr     puthex
        jsr     nl
        jmp     failinc

; ── COMMIT ───────────────────────────────────────────────────────────────────
t_commit:
        rep     #$20
        .a16
        lda     #100
        sta     tmp
        sep     #$20
        .a8
        jsr     waitln
        sta     f:NV_COMMIT
        lda     f:NV_COMMIT
        cmp     #$01
        bne     @bad1
        rep     #$20
        .a16
        lda     #300
        sta     tmp
        sep     #$20
        .a8
        jsr     waitln
        lda     f:NV_COMMIT
        cmp     #$01
        bne     @bad2
        jsr     waitvbl
        ldx     #400                    ; ~ 0.3 ms
:       dex
        bne     :-
        lda     f:NV_COMMIT
        bne     @bad3
        ldx     #128                    ; the set in use is the pattern now
        lda     #3
        sta     tmp
:       jsr     peek
        cmp     tmp
        bne     @bad4
        lda     tmp
        clc
        adc     #7
        sta     tmp
        inx
        cpx     #256
        bne     :-
        ; in vertical blank: done at once
        ldx     #0
        lda     #0
:       sta     f:NV_SPR,x
        inx
        cpx     #128
        bne     :-
        jsr     waitvbl
        sta     f:NV_COMMIT
        ldx     #150                    ; about 50 us
:       dex
        bne     :-
        lda     f:NV_COMMIT
        bne     @bad5
        ldx     #128
:       jsr     peek
        bne     @bad6
        inx
        cpx     #256
        bne     :-
        print   m_commitok
        rts
@bad1:  lda     #1
        bra     @bad
@bad2:  lda     #2
        bra     @bad
@bad3:  lda     #3
        bra     @bad
@bad4:  lda     #4
        bra     @bad
@bad5:  lda     #5
        bra     @bad
@bad6:  lda     #6
@bad:   pha
        print   m_fcommit
        pla
        jsr     puthex
        jsr     nl
        jmp     failinc

; ── LIMIT ────────────────────────────────────────────────────────────────────
; sprites 0-8: 32 x 32, 4 bpp, magnified (64 x 64 on screen) at (i * 34, 100)
t_limit:
        jsr     fillimg
        lda     #<(FB >> 8)
        sta     f:NV_BASE+1
        lda     #^FB
        sta     f:NV_BASE+2
        lda     #$01
        sta     f:NV_CTRL
        sta     f:NV_SPR_CTRL
        ldx     #0                      ; record index * 8
        ldy     #0                      ; sprite index
@r:     rep     #$20
        .a16
        tya
        asl
        sta     tmp
        asl
        asl
        asl
        asl
        clc
        adc     tmp                     ; i * 50 ... (i * 34 is enough)
        sta     f:NV_SPR,x
        lda     #100
        sta     f:NV_SPR+2,x
        lda     #.loword(SIMG)
        sta     f:NV_SPR+4,x
        sep     #$20
        .a8
        lda     #^SIMG
        sta     f:NV_SPR+6,x
        lda     #$00
        cpy     #9
        bcs     :+
        lda     #$79                    ; EN MAG WIDE TALL BPP4
:       sta     f:NV_SPR+7,x
        rep     #$21
        .a16
        txa
        adc     #8
        tax
        sep     #$20
        .a8
        iny
        cpy     #16
        bne     @r
        jsr     commitw
        ldx     #2
        jsr     frames
        lda     f:NV_SPR_STAT
        and     #$03
        cmp     #$01                    ; OVERFLOW, not LATE
        bne     @bad1
        lda     #$00                    ; sprite 8 off: 8 x 64 = 512 fits
        sta     f:NV_SPR+8*8+7
        jsr     commitw
        jsr     waitvbl
        lda     #$03
        sta     f:NV_SPR_STAT
        lda     f:NV_SPR_STAT
        bne     @bad2
        ldx     #2
        jsr     frames
        lda     f:NV_SPR_STAT
        bne     @bad3
        print   m_limitok
        rts
@bad1:  ldx     #1
        bra     @bad
@bad2:  ldx     #2
        bra     @bad
@bad3:  ldx     #3
@bad:   pha
        print   m_flimit
        txa
        jsr     puthex
        pla
        jsr     puthex
        jsr     nl
        jmp     failinc

; sprite images at SIMG: 16 x 512 bytes of pseudo-random bytes, about a quarter of the
; pixels 0 (transparent)
fillimg:
        rep     #$20
        .a16
        lda     #.loword(SIMG)
        sta     p0
        sep     #$20
        .a8
        lda     #^SIMG
        sta     p0+2
        ldy     #0
:       jsr     rnd
        lda     seed+1
        and     #$03
        bne     :+
        lda     seed                    ; one pixel in four: both nibbles 0
        and     #$00
        bra     :++
:       lda     seed
        ora     #$11                    ; never 0 in either nibble
:       sta     [p0],y
        iny
        cpy     #8192
        bne     :---
        rts

; ── LOAD ─────────────────────────────────────────────────────────────────────
.ifdef SIM
LD_REC  = 2
.else
LD_REC  = 20
.endif
t_load:
        ; 16 sprites on lines 50-81, 4 bpp 32 x 32 (16 x 32 = 512 pixels: the whole budget)
        ldx     #0
        ldy     #0
@r:     rep     #$20
        .a16
        tya
        asl
        asl
        asl
        sta     tmp
        asl
        asl
        clc
        adc     tmp
        sec
        sbc     #8
        sta     f:NV_SPR,x              ; x = i * 40 - 8
        lda     #50
        sta     f:NV_SPR+2,x
        lda     #.loword(SIMG)
        sta     f:NV_SPR+4,x
        sep     #$20
        .a8
        lda     #^SIMG
        sta     f:NV_SPR+6,x
        lda     #$71                    ; EN WIDE TALL BPP4
        sta     f:NV_SPR+7,x
        rep     #$21
        .a16
        txa
        adc     #8
        tax
        sep     #$20
        .a8
        iny
        cpy     #16
        bne     @r
        jsr     commitw
        ; the list: LD_REC copies of 640 x 180 inside FB
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
:       lda     lrec,x
        sta     [p0],y
        iny
        inx
        cpx     #24
        bne     :-
        cpy     #LD_REC*24
        bne     @b
        jsr     fillsmp
        lda     #0
        sta     f:NV_SPR_CTRL
        jsr     runlist                 ; sprites off, no voices
        rep     #$20
        .a16
        lda     t1
        sta     t_off
        lda     t1+2
        sta     t_off+2
        sep     #$20
        .a8
        lda     #$01
        sta     f:NV_SPR_CTRL
        jsr     waitvbl
        lda     #$03
        sta     f:NV_SPR_STAT
        jsr     runlist                 ; sprites on
        print   m_loff
        ldx     #t_off
        jsr     put32
        print   m_lon
        ldx     #t1
        jsr     put32
        jsr     nl
        ldx     #0                      ; and now with 8 voices
:       phx
        ldy     #.loword(vp_load)
        jsr     setv
        plx
        inx
        cpx     #8
        bne     :-
        sta     f:AU_LATE
        sta     f:NV_LATE
        lda     #$FF
        sta     f:AU_KEYON
        jsr     runlist
        lda     #$FF
        sta     f:AU_KEYOFF
        print   m_lvoice
        ldx     #t1
        jsr     put32
        print   m_aul
        lda     f:AU_LATE
        jsr     puthex
        print   m_nvl
        lda     f:NV_LATE
        jsr     puthex
        print   m_sst
        lda     f:NV_SPR_STAT
        jsr     puthex
        jsr     nl
        lda     f:AU_LATE
        ora     f:NV_LATE
        bne     @bad
        lda     f:NV_SPR_STAT
        and     #$03
        bne     @bad
        print   m_loadok
        rts
@bad:   jmp     failinc

; run the list once (one frame boundary first), t1 <- its time in us
runlist:
        lda     #0
        sta     f:BL_LIST
        sta     f:BL_LIST+1
        sta     f:BL_COUNT+1
        lda     #^LIST
        sta     f:BL_LIST+2
        lda     #LD_REC
        sta     f:BL_COUNT
        jsr     waitvbl
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
; print the 32-bit value at direct page X
put32:  lda     3,x
        jsr     puthex
        lda     2,x
        jsr     puthex
        lda     1,x
        jsr     puthex
        lda     0,x
        jmp     puthex

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
; SMP: 16-bit noise x 16 K
fillsmp:
        rep     #$20
        .a16
        lda     #.loword(SMP)
        sta     p0
        sep     #$20
        .a8
        lda     #^SMP
        sta     p0+2
        rep     #$20
        .a16
        ldy     #0
        lda     #$ACE1
:       lsr
        bcc     :+
        eor     #$B400
:       sta     [p0],y
        iny
        iny
        cpy     #$8000
        bne     :--
        sep     #$20
        .a8
        rts

lrec:   .faraddr FB
        .word   640
        .faraddr FB + 640*180
        .word   640, 640, 180
        .byte   0, 0, 0, 1, 0, 0, 0, 0, 0, 0
vp_load: VP SMP, 16384, 0, $FFFF, 32, 32, $03

; ── SCENES (SIM) ─────────────────────────────────────────────────────────────
.ifdef SIM
NSCENE  = 12
t_scenes:
        ; pointer image: 32 rows of 8 bytes of random 2-bit pixels
        rep     #$20
        .a16
        lda     #.loword(PIMG)
        sta     p0
        sep     #$20
        .a8
        lda     #^PIMG
        sta     p0+2
        ldy     #0
:       jsr     rnd
        sta     [p0],y
        iny
        cpy     #256
        bne     :-
        lda     #<PIMG
        sta     f:PTR_IMG
        lda     #>PIMG
        sta     f:PTR_IMG+1
        lda     #^PIMG
        sta     f:PTR_IMG+2
        lda     #$55
        sta     f:PTR_HOT
        rep     #$20
        .a16
        stz     scene
        sep     #$20
        .a8
@s:     print   m_scene
        lda     scene
        jsr     puthex
        jsr     nl
        jsr     waitvbl                 ; set the scene in vertical blank, taken at line 0
        ; mode, pointer
        jsr     rnd
        lda     seed
        and     #$03
        cmp     #$03
        bne     :+
        lda     #$00
:       sta     mode
        stz     mode+1
        asl
        ora     #$09                    ; ENABLE, POINTER_EN
        sta     f:NV_CTRL
        sta     tmp
        stz     tmp+1
        rep     #$20
        .a16
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed
        and     #$01FF
        sta     f:PTR_X
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed
        and     #$00FF
        clc
        adc     #20
        sta     f:PTR_Y
        ; bitmap: stride 1024 in 8 bpp, 512 otherwise
        lda     #1024
        ldx     tmp
        cpx     #$09
        beq     :+
        lda     #512
:       sta     f:NV_STRIDE
        sta     k                       ; stride
        lda     #.loword(FB)
        sta     f:NV_BASE
        sep     #$20
        .a8
        lda     #^FB
        sta     f:NV_BASE+2
        ; scroll: X anywhere in the row (in pixels: stride, or 2 x stride in 4 bpp)
        jsr     rnd
        rep     #$20
        .a16
        lda     seed
        and     #$03FF
        sta     f:NV_SCROLLX
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed
        and     #$03FF
        sta     f:NV_SCROLLX2
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed
        and     #$00FF
        sta     f:NV_SCROLLY
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed
        and     #$01FF
        sta     f:NV_SCROLLY2
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed                    ; VHEIGHT 0 (half the time) or 256-383
        and     #$017F
        cmp     #$0100
        bcs     :+
        lda     #0
:       sta     f:NV_VHEIGHT
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed
        and     #$00FF
        clc
        adc     #40
        sta     f:NV_LINE_CMP           ; split line 40-295
        sep     #$20
        .a8
        lda     seed+1
        and     #$03
        sta     f:NV_SCTL
        ; sprite positions over every edge: x -96..927, y -80..431 (320x180: half)
        rep     #$20
        .a16
        lda     #$03FF
        sta     xmask
        lda     #96
        sta     xoff
        lda     #$01FF
        sta     ymask
        lda     #80
        sta     yoff
        lda     mode
        cmp     #2
        bne     :+
        lsr     xmask
        lsr     xoff
        lsr     ymask
        lsr     yoff
:       sep     #$20
        .a8
        ; 16 random records
        ldx     #0
@rec:   phx
        jsr     rnd                     ; X: -96..927
        rep     #$20
        .a16
        lda     seed
        and     xmask
        sec
        sbc     xoff
        sta     rec
        jsr     rnd
        .a8
        rep     #$20
        .a16
        lda     seed
        and     ymask
        sec
        sbc     yoff
        sta     rec+2                   ; Y: -80..431
        pla
        pha
        asl                             ; image (i * 512) + 4 bits of PAL
        asl
        asl
        asl
        asl
        asl
        and     #$1E00
        clc
        adc     #.loword(SIMG)
        sta     rec+4
        jsr     rnd
        .a8
        lda     seed
        and     #$0F
        ora     rec+4
        sta     rec+4
        lda     #^SIMG
        sta     rec+6
        lda     seed+1                  ; CTRL: random, EN 7 times in 8
        sta     rec+7
        and     #$0E
        bne     :+
        lda     rec+7
        and     #$FE
        bra     :++
:       lda     rec+7
        ora     #$01
:       sta     rec+7
        plx
        stx     k
        ldx     #0
:       lda     rec,x                   ; (direct page; rec,y would be absolute, bank $01)
        phx
        ldx     k
        sta     f:NV_SPR,x
        inx
        stx     k
        plx
        inx
        cpx     #8
        bne     :-
        ldx     k
        cpx     #128
        bne     @rec
        lda     #$01
        sta     f:NV_SPR_CTRL
        sta     f:NV_COMMIT
        ldx     #2
        jsr     frames
        rep     #$20
        .a16
        inc     scene
        lda     scene
        cmp     #NSCENE
        sep     #$20
        .a8
        beq     :+
        jmp     @s
:       lda     #$0
        sta     f:NV_SCTL
        lda     f:NV_SPR_STAT
        and     #$02                    ; LATE
        beq     :+
        print   m_scnlate
        jmp     failinc
:       print   m_scenesok
        rts
.endif

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

m_hello:   .byte "SPRITE AND SCROLL TEST REV ", 0
m_norev:   .byte "FAIL REV: NEEDS 0B", 10, 0
m_regok:   .byte "REGS OK", 10, 0
m_fregs:   .byte "FAIL REGS ", 0
m_peekok:  .byte "PEEK OK", 10, 0
m_fpeek:   .byte "FAIL PEEK ", 0
m_commitok: .byte "COMMIT OK", 10, 0
m_fcommit: .byte "FAIL COMMIT ", 0
m_limitok: .byte "LIMIT OK", 10, 0
m_flimit:  .byte "FAIL LIMIT ", 0
m_loff:    .byte "LIST US SPRITES OFF ", 0
m_lon:     .byte " ON ", 0
m_lvoice:  .byte "WITH 8 VOICES ", 0
m_aul:     .byte " AU_LATE ", 0
m_nvl:     .byte " NV_LATE ", 0
m_sst:     .byte " SPR_STATUS ", 0
m_loadok:  .byte "LOAD OK", 10, 0
m_scene:   .byte "SCENE ", 0
m_scnlate: .byte "FAIL SCENES LATE", 10, 0
m_scenesok: .byte "SCENES OK", 10, 0
m_pass:    .byte "SPRTEST PASS", 10, 0
m_fail:    .byte "SPRTEST FAIL ", 0
m_done:    .byte "DONE", 10, 0
