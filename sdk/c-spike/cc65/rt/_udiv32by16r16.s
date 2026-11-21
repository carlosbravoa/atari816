;
; Ullrich von Bassewitz, 2009-11-04
;
; CC65 library: 32by16 => 16 unsigned division
;

        .export         _udiv32by16r16
        .import         udiv32by16r16m, incsp4

        .include        "zeropage.inc"


;---------------------------------------------------------------------------
; 32by16 division.

.proc   _udiv32by16r16

        sta     ptr3
        stx     ptr3+1                  ; Store rhs

; Copy from stack to zeropage. This assumes ptr1 and ptr2 are adjacent.

; Atari816/Horizon: "sta ptr1,y" is absolute,y (no zp,y form), which reaches DBR:00xx
; instead of the direct page under the 65816 with DBR <> 0. Unrolled with zp stores.
        ldy     #3
        lda     (c_sp),y
        sta     ptr1+3
        dey
        lda     (c_sp),y
        sta     ptr1+2
        dey
        lda     (c_sp),y
        sta     ptr1+1
        dey
        lda     (c_sp),y
        sta     ptr1

        lda     #4
        clc
        adc     c_sp
        sta     c_sp
        bcc     @L2
        inc     c_sp+1

@L2:    jmp     udiv32by16r16m

.endproc

