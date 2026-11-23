; SPDX-License-Identifier: GPL-3.0-or-later
; hz_adpcm.s - plat/sb.c's sample decoding on the Atari816 (the C there, sb_decode, is
; the reference and the host's): the Sound Blaster blocks made into signed 8-bit samples
; for Lau, once per effect when the engine has loaded them (horizon/hz_snd.c
; plat_sfx_preload). The C took about 160 ms an effect (3.7 s for the 23): 4 s more
; before the first geoscape.
;
; void hz_adpcm(signed char far *out, const unsigned char far *src, unsigned bytes)
;   Creative 4-bit ADPCM with its reference byte (DSP command 75h): src[0] the first
;   sample, then bytes - 1 bytes of two samples each (the high nibble first): 2 * bytes - 1
;   samples (the unsigned value - 128); bytes >= 1
; void hz_pcm8(signed char far *out, const unsigned char far *src, unsigned bytes)
;   8-bit unsigned PCM (14h): each byte - 128
        .p816
        .a16
        .i16
        .include "model.inc"
        .importzp __rg

PD      = __rg+0
PS      = __rg+4
cnt     = __rg+8
ref     = __rg+10
step    = __rg+11
cur     = __rg+12

        FUNC    _hz_adpcm
        lda     ARGS,s
        sta     PD
        lda     ARGS+2,s
        sta     PD+2
        lda     ARGS+4,s
        sta     PS
        lda     ARGS+6,s
        sta     PS+2
        lda     ARGS+8,s
        bne     :+
        RET
:       dec     a
        sta     cnt                     ; the bytes of nibbles
        phb                             ; DBR = this bank: the tables below
        phk
        plb
        sep     #$30
        .a8
        .i8
        stz     step
        lda     [PS]                    ; the reference byte: the first sample
        sta     ref
        eor     #$80
        sta     [PD]
        jsr     inc_pd
        inc     PS
        bne     @loop
        inc     PS+1
@loop:  lda     cnt
        ora     cnt+1
        beq     @done
        lda     [PS]
        sta     cur
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     nib
        lda     cur
        and     #$0F
        jsr     nib
        inc     PS
        bne     :+
        inc     PS+1
:       lda     cnt
        bne     :+
        dec     cnt+1
:       dec     cnt
        bra     @loop
@done:  rep     #$30
        .a16
        .i16
        plb
        RET

        .a8
        .i8
; one nibble (A): the next sample (the DSP's rule, sb.c adpcm_nib)
nib:    clc
        adc     step
        cmp     #64
        bcc     :+
        lda     #63
:       tax
        lda     scale4,x
        bmi     @neg
        clc
        adc     ref
        bcc     @st
        lda     #$FF                    ; (above 255)
        bra     @st
@neg:   clc
        adc     ref                     ; ref - |s|: carry clear when below 0
        bcs     @st
        lda     #0
@st:    sta     ref
        eor     #$80
        sta     [PD]
        jsr     inc_pd
        lda     step
        clc
        adc     adjust4,x
        sta     step
        rts

inc_pd: inc     PD
        bne     :+
        inc     PD+1
:       rts

scale4: .byte   0, 1, 2, 3, 4, 5, 6, 7, 0, <-1, <-2, <-3, <-4, <-5, <-6, <-7
        .byte   1, 3, 5, 7, 9, 11, 13, 15, <-1, <-3, <-5, <-7, <-9, <-11, <-13, <-15
        .byte   2, 6, 10, 14, 18, 22, 26, 30, <-2, <-6, <-10, <-14, <-18, <-22, <-26, <-30
        .byte   4, 12, 20, 28, 36, 44, 52, 60, <-4, <-12, <-20, <-28, <-36, <-44, <-52, <-60
adjust4:
        .byte   0, 0, 0, 0, 0, 16, 16, 16, 0, 0, 0, 0, 0, 16, 16, 16
        .byte   <-16, 0, 0, 0, 0, 16, 16, 16, <-16, 0, 0, 0, 0, 16, 16, 16
        .byte   <-16, 0, 0, 0, 0, 16, 16, 16, <-16, 0, 0, 0, 0, 16, 16, 16
        .byte   <-16, 0, 0, 0, 0, 0, 0, 0, <-16, 0, 0, 0, 0, 0, 0, 0

        .a16
        .i16
        FUNC    _hz_pcm8
        lda     ARGS,s
        sta     PD
        lda     ARGS+2,s
        sta     PD+2
        lda     ARGS+4,s
        sta     PS
        lda     ARGS+6,s
        sta     PS+2
        lda     ARGS+8,s
        beq     @x
        sta     cnt
        ldy     #0
        sep     #$20
        .a8
:       lda     [PS],y
        eor     #$80
        sta     [PD],y
        iny
        cpy     cnt
        bne     :-
        rep     #$20
        .a16
@x:     RET
