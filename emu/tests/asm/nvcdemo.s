; emu816 NVC + blitter test: custom palette ramp, reset-palette hue bars, all five blitter
; operations (FILL, COPY, COPY_KEY, EXPAND, EXPAND_KEY, plus a BACKWARDS overlapping
; copy), the hardware pointer, and the 60 Hz VBLANK interrupt timing.
; Check the picture with: emu816 --shot out.ppm nvcdemo.bin
        .include "common.inc"

NV_CTRL   = $00D900
NV_BASE   = $00D901
NV_STRIDE = $00D904
PAL_IDX   = $00D910
PAL_R     = $00D911
PAL_G     = $00D912
PAL_B     = $00D913
PTR_X     = $00D920
PTR_Y     = $00D922
PTR_HOT   = $00D924
PTR_IMG   = $00D925
PTR_C1    = $00D928
BL        = $00DA00
BL_CTRL   = $00DA13
FB        = $200000             ; 640 x 360 x 8 framebuffer
PTRBUF    = $240000
GLYPHS    = $240100             ; "816" as a 24 x 8 1 bpp bitmap, 3 bytes per line
t0        = $20                 ; direct page
bl        = $30

        ; src, src stride, dst, dst stride, width, height, fg, bg, key, op, flags
        .macro  BLT src, sstr, dst, dstr, w, h, fg, bg, key, op, flags
        .faraddr src
        .word   sstr
        .faraddr dst
        .word   dstr
        .word   w, h
        .byte   fg, bg, key, op, flags
        .endmacro

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

; palette entries $F0-$FF: a ramp from blue to orange
        lda     #$F0
        sta     f:PAL_IDX
        ldx     #0
:       txa
        asl
        asl
        asl
        asl
        sta     f:PAL_R                 ; R = 16 i
        lsr
        sta     f:PAL_G                 ; G = 8 i
        txa
        asl
        asl
        asl
        asl
        eor     #$FF
        sta     f:PAL_B                 ; B = 255 - 16 i, commits and increments
        inx
        cpx     #16
        bne     :-
        lda     f:PAL_IDX               ; wrapped to 0
        bne     fail1

; copy the pointer image and the glyphs out to RAM
        ldx     #0
:       lda     ptrimg,x
        sta     f:PTRBUF,x
        inx
        cpx     #256
        bne     :-
        ldx     #0
:       lda     glyphs,x
        sta     f:GLYPHS,x
        inx
        cpx     #24
        bne     :-

; display: 640x360x8 at FB (NV_STRIDE resets to 640), pointer on
        lda     #<FB
        sta     f:NV_BASE
        lda     #>.loword(FB)
        sta     f:NV_BASE+1
        lda     #^FB
        sta     f:NV_BASE+2
        lda     #$09                    ; ENABLE + POINTER_EN, mode 0
        sta     f:NV_CTRL

; blits
        ldx     #.loword(BL)            ; [bl],y reaches the blitter registers
        stx     bl
        lda     #^BL
        sta     bl+2
        ldx     #.loword(blits)
bloop:  cpx     #.loword(bend)
        beq     bdone
        ldy     #0
:       lda     a:0,x
        sta     [bl],y
        inx
        iny
        cpy     #19
        bne     :-
        lda     #$01                    ; START
        sta     f:BL_CTRL
@busy:  lda     f:BL_CTRL               ; wait while BUSY (REV $08)
        and     #$01
        bne     @busy
        bra     bloop
fail1:  print   m_fail
        stp
bdone:

; pointer at (500, 250), colours white / yellow / black
        rep     #$20
        .a16
        lda     #500
        sta     f:PTR_X
        lda     #250
        sta     f:PTR_Y
        sep     #$20
        .a8
        lda     #$00
        sta     f:PTR_HOT
        lda     #<PTRBUF
        sta     f:PTR_IMG
        lda     #>.loword(PTRBUF)
        sta     f:PTR_IMG+1
        lda     #^PTRBUF
        sta     f:PTR_IMG+2
        lda     #$0F
        sta     f:PTR_C1
        lda     #$1E
        sta     f:PTR_C1+1
        lda     #$00
        sta     f:PTR_C1+2

; 3 VBLANK interrupts (WAI with I set): 3 x 238,944 cycles = 49,975 us (60.03 Hz)
        sei
        lda     #$FF
        sta     f:IRQ_STATUS
        lda     #$01
        sta     f:IRQ_EN
        jsr     vbl                     ; sync to a frame start
        jsr     gettime
        ldx     t0
        stx     t0+4
        ldx     t0+2
        stx     t0+6
        ldy     #3
:       jsr     vbl
        dey
        bne     :-
        jsr     gettime
        rep     #$20
        .a16
        sec
        lda     t0
        sbc     t0+4
        tax
        sep     #$20
        .a8
        phx
        print   m_vbl
        plx
        jsr     puthex16
        cpx     #49975 - 3
        bcc     :+
        cpx     #49975 + 3
        bcs     :+
        print   m_ok
        bra     fin
:       print   m_fail
fin:    print   m_done
        stp

vbl:    wai
        lda     f:IRQ_STATUS
        and     #$01
        beq     vbl
        sta     f:IRQ_STATUS
        rts

gettime:
        lda     f:UPTIME
        sta     t0
        lda     f:UPTIME+1
        sta     t0+1
        lda     f:UPTIME+2
        sta     t0+2
        lda     f:UPTIME+3
        sta     t0+3
        rts

blits:  ; background blue $94, a grey frame, then the inside black
        BLT     0, 0, (FB + (0) * 640 + (0)), 640, 640, 360, $94, 0, 0, 0, 0
        BLT     0, 0, (FB + (16) * 640 + (16)), 640, 608, 328, $0A, 0, 0, 0, 0
        BLT     0, 0, (FB + (20) * 640 + (20)), 640, 600, 320, $00, 0, 0, 0, 0
        ; custom ramp $F0-$FF: 16 bars 36 x 40
        .repeat 16, i
        BLT     0, 0, (FB + (32) * 640 + (32 + i * 36)), 640, 34, 40, $F0 + i, 0, 0, 0, 0
        .endrepeat
        ; reset palette: 16 hues x 8 luminances, 36 x 12 each
        .repeat 16, h
        .repeat 8, l
        BLT     0, 0, (FB + (84 + l * 12) * 640 + (32 + h * 36)), 640, 34, 11, h * 16 + l * 2, 0, 0, 0, 0
        .endrepeat
        .endrepeat
        ; EXPAND "816" (white on dark blue) and EXPAND_KEY (yellow, background kept)
        BLT     GLYPHS, 3, (FB + (200) * 640 + (40)), 640, 24, 8, $0F, $92, 0, 3, $70
        BLT     GLYPHS, 3, (FB + (212) * 640 + (40)), 640, 24, 8, $1E, 0, 0, 4, $70
        ; EXPAND starting at bit 3 of each line: shows "16" plus the right half of "8"
        BLT     GLYPHS, 3, (FB + (224) * 640 + (40)), 640, 20, 8, $0F, $46, 0, 3, $30
        ; COPY the 3 rows of glyphs 4x along the line
        .repeat 4, i
        BLT     (FB + (200) * 640 + (40)), 640, (FB + (200) * 640 + (80 + i * 32)), 640, 24, 32, 0, 0, 0, 1, 0
        .endrepeat
        ; COPY_KEY the hue bars onto the black area: key = colour $00 skips nothing visible,
        ; key $44 punches the red bars out
        BLT     (FB + (84) * 640 + (32)), 640, (FB + (196) * 640 + (240)), 640, 360, 96, 0, 0, $44, 2, 0
        ; BACKWARDS overlapping move: the ramp bars slide right by 6 pixels
        BLT     (FB + (32) * 640 + (32)), 640, (FB + (32) * 640 + (38)), 640, 574, 40, 0, 0, 0, 1, 1
bend:

glyphs: .byte   $3C, $18, $3C
        .byte   $66, $38, $60
        .byte   $66, $18, $7C
        .byte   $3C, $18, $66
        .byte   $66, $18, $66
        .byte   $66, $18, $66
        .byte   $3C, $7E, $3C
        .byte   $00, $00, $00

        .include "pointer.inc"

m_hello: .byte "NVCDEMO", 10, 0
m_vbl:   .byte "3 FRAMES US ", 0
m_ok:    .byte " OK", 10, 0
m_fail:  .byte " FAIL", 10, 0
m_done:  .byte "DONE", 10, 0
