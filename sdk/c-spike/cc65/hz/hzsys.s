; hzsys.s - the Horizon syscall gate for cc65 C (65816 native, C runs with 8-bit regs).
;
; C sets the 16-bit argument registers in hz_a / hz_x / hz_y (globals in the code bank)
; and calls hz_sys(n). The gate switches to 16-bit registers, loads A/X/Y, executes
; COP #n (the operand byte is patched: one gate for every syscall), stores A/X/Y back,
; returns to 8-bit registers. Carry set = error: hz_err = the error code, else 0.
; Pointers: X = offset, Y = bank; hz_bank holds the code bank for that (see horizon.h).

        .p816
        .smart  off

        .export         _hz_sys, _hz_sysl
        .export         _hz_a, _hz_x, _hz_y, _hz_err
        .importzp       sreg

        .segment "CODE"

; unsigned __fastcall__ hz_sys(unsigned char n);   -> A (16 bits)
        .a8
        .i8
_hz_sys:
        sta     @op+1                   ; patch the COP signature byte
        rep     #$30
        .a16
        .i16
        lda     _hz_a
        ldx     _hz_x
        ldy     _hz_y
@op:    cop     $00
        sta     _hz_a
        stx     _hz_x
        sty     _hz_y
        sep     #$30                    ; carry is kept
        .a8
        .i8
        bcs     @err
        lda     #0
        sta     _hz_err
        sta     _hz_err+1
        lda     _hz_a
        ldx     _hz_a+1
        rts
@err:   lda     _hz_a
        sta     _hz_err
        ldx     _hz_a+1
        stx     _hz_err+1
        rts

; unsigned long __fastcall__ hz_sysl(unsigned char n);   -> A | X << 16 (uptime, ...)
_hz_sysl:
        jsr     _hz_sys
        ldy     _hz_x
        sty     sreg
        ldy     _hz_x+1
        sty     sreg+1
        rts

        .segment "BSS"
_hz_a:  .res    2
_hz_x:  .res    2
_hz_y:  .res    2
_hz_err: .res   2
