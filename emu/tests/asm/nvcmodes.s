; emu816 NVC modes: 640x360x4 (default build) or 320x180x8 at 4x (ca65 -D MODE2), drawn
; with blitter fills; then the LINE interrupt: NV_LINE_CMP = 100, WAI, NV_LINE must read 100.
        .include "common.inc"

NV_CTRL     = $00D900
NV_BASE     = $00D901
NV_STRIDE   = $00D904
NV_LINE     = $00D906
NV_LINE_CMP = $00D908
NV_STATUS   = $00D90A
BL          = $00DA00
BL_CTRL     = $00DA13
FB          = $300000
bl          = $30

        .macro  FILL dst, dstr, w, h, fg
        .faraddr 0
        .word   0
        .faraddr dst
        .word   dstr
        .word   w, h
        .byte   fg, 0, 0, 0, 0
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
        lda     #<FB
        sta     f:NV_BASE
        lda     #>.loword(FB)
        sta     f:NV_BASE+1
        lda     #^FB
        sta     f:NV_BASE+2
        lda     f:NV_STATUS             ; BASE_PENDING until the next vertical blank
        and     #$02
        bne     :+
        jmp     fail
:       rep     #$20
        .a16
        lda     #320                    ; both modes: 320 bytes per line
        sta     f:NV_STRIDE
        sep     #$20
        .a8
.ifdef MODE2
        lda     #$05                    ; ENABLE, mode 2 (320x180x8)
.else
        lda     #$03                    ; ENABLE, mode 1 (640x360x4)
.endif
        sta     f:NV_CTRL
        ldx     #.loword(BL)
        stx     bl
        lda     #^BL
        sta     bl+2
        ldx     #.loword(fills)
floop:  cpx     #.loword(fend)
        beq     fdone
        ldy     #0
:       lda     a:0,x
        sta     [bl],y
        inx
        iny
        cpy     #19
        bne     :-
        lda     #$01
        sta     f:BL_CTRL
:       lda     f:BL_CTRL               ; registers only while BUSY = 0 (REV $08)
        and     #$01
        bne     :-
        bra     floop
fdone:
        ; LINE interrupt at line 100 (I set: WAI just resumes)
        sei
        rep     #$20
        .a16
        lda     #100
        sta     f:NV_LINE_CMP
        sep     #$20
        .a8
        lda     #$FF
        sta     f:IRQ_STATUS
        lda     #$02
        sta     f:IRQ_EN
        ldy     #2                      ; twice: the second one is after a vertical blank
lwait:  wai
        lda     f:IRQ_STATUS
        and     #$02
        beq     lwait
        sta     f:IRQ_STATUS
        dey
        bne     lwait
        lda     f:NV_LINE               ; reading the low byte latches the high byte
        sta     tmp
        lda     f:NV_LINE+1
        sta     tmp+1
        print   m_line
        ldx     tmp
        jsr     puthex16
        jsr     crlf
        lda     f:NV_STATUS             ; vertical blank has passed since: base taken
        and     #$02
        bne     fail
        print   m_done
        stp
fail:   print   m_fail
        stp

fills:
        FILL    FB, 320, 320, 360, $00          ; clear: 320 bytes x 360 lines
.ifdef MODE2
        ; 320x180 at 8 bpp: 16 vertical stripes of hue i, luminance 8, a white box
        .repeat 16, i
        FILL    FB + i * 20, 320, 20, 180, i * 16 + 8
        .endrepeat
        FILL    FB + 80 * 320 + 140, 320, 40, 20, $0F
.else
        ; 640x360 at 4 bpp (two pixels per byte): 16 bands of colour pairs, then a box
        ; where every byte is $1E (pixel 1 left, pixel 14 right: fine vertical stripes)
        .repeat 16, i
        FILL    FB + i * 22 * 320, 320, 320, 22, i * 16 + ((i + 8) & 15)
        .endrepeat
        FILL    FB + 150 * 320 + 100, 320, 120, 60, $1E
.endif
fend:

m_hello: .byte "NVCMODES", 10, 0
m_line:  .byte "LINE ", 0
m_done:  .byte "DONE", 10, 0
m_fail:  .byte "FAIL", 10, 0
tmp:     .word 0
