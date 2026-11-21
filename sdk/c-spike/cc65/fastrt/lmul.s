; lmul.s (65816) - cc65's 32-bit multiply (tos * eax, low 32 bits), with 16-bit registers
; inside. Same entry points, inputs, outputs, zero page use and stack effect as
; libsrc/runtime/lmul.s (cc65 knows these as clobbering every register).
;
; a = TOS (4 bytes, dropped), b = A/X/sreg. Low 32 bits of a * b =
;   aL * bL (full 32) + ((aL * bH + aH * bL) mod 2^16) << 16
; three 16 x 16 shift-add multiplies of 16 steps (the cross terms skipped when 0), instead
; of one 32-step loop shifting 8 bytes.

        .p816
        .smart  off

        .export         tosumul0ax, tosumuleax, tosmul0ax, tosmuleax
        .importzp       c_sp, sreg, tmp1, tmp3, ptr1, ptr3, ptr4

; mp * mc (16-bit words in the direct page): A = high word, mp = low word. Needs a16/i16.
.macro  MUL16   mp, mc
        .local  mloop, mskip
        lda     #0
        ldx     #16
        lsr     mp
mloop:  bcc     mskip
        clc
        adc     mc
mskip:  ror     a
        ror     mp
        dex
        bne     mloop
.endmacro

        .segment "CODE"
        .a8
        .i8

tosmul0ax:
tosumul0ax:
        stz     sreg
        stz     sreg+1
tosmuleax:
tosumuleax:
        sta     ptr1
        stx     ptr1+1                  ; bL = ptr1, bH = sreg
        rep     #$30
        .a16
        .i16
        lda     (c_sp)
        sta     ptr3                    ; aL
        ldy     #2
        lda     (c_sp),y
        sta     ptr4                    ; aH
        lda     c_sp                    ; drop TOS
        clc
        adc     #4
        sta     c_sp

        stz     tmp3                    ; the cross terms, mod 2^16
        lda     sreg                    ; aL * bH (bH consumed)
        beq     lm_c2
        lda     ptr3
        beq     lm_c2
        MUL16   sreg, ptr3
        lda     sreg
        sta     tmp3
lm_c2:  lda     ptr4                    ; aH * bL
        beq     lm_c3
        lda     ptr1
        beq     lm_c3
        sta     tmp1
        MUL16   tmp1, ptr4
        lda     tmp1
        clc
        adc     tmp3
        sta     tmp3
lm_c3:  MUL16   ptr1, ptr3              ; aL * bL: A = high word, ptr1 = low word
        clc
        adc     tmp3
        sta     sreg
        sep     #$30
        .a8
        .i8
        lda     ptr1
        ldx     ptr1+1
        rts
