; str.s - C strings for routines that read them from the code bank (DBR): a string
; elsewhere (a local on the stack in bank 0, a far bank) is copied to one of three scratch
; buffers of 256 bytes for the call, and an output buffer copied back after it.
        .p816
        .smart  off
        .include "horizon.inc"
        .include "ui.inc"
        .include "huidefs.inc"

        .segment "BSS"
hui_slots: .res 3 * 256

        .segment "CODE"
        .a16
        .i16

; z:hui_s = a C pointer, X = scratch buffer 0-2 -> A = the string's offset in the code
; bank: its own when it is there, 0 for NULL, else the buffer with a copy (at most 255
; characters, zero-terminated)
hui_instr:
        lda     z:hui_s+2
        cmp     #^hui_slots
        beq     @own
        ora     z:hui_s
        beq     @out                    ; NULL: 0
        jsr     slot
        tax
        ldy     #0
        sep     #$20
        .a8
@c:     lda     [hui_s],y
        sta     a:0,x
        beq     @end
        inx
        iny
        cpy     #255
        bcc     @c
        lda     #0
        sta     a:0,x
@end:   rep     #$20
        .a16
        lda     z:hui_d
@out:   rts
@own:   lda     z:hui_s
        rts

; X = 0-2 -> A = z:hui_d = that buffer's address
slot:   txa
        xba
        and     #$FF00
        clc
        adc     #.loword(hui_slots)
        sta     z:hui_d
        rts

; z:hui_s = the C pointer given to hui_instr, X = the same buffer: when the string was
; copied, the buffer's string (and its 0) is copied back there
hui_outstr:
        lda     z:hui_s+2
        cmp     #^hui_slots
        beq     @out
        ora     z:hui_s
        beq     @out
        jsr     slot
        tax
        ldy     #0
        sep     #$20
        .a8
@c:     lda     a:0,x
        sta     [hui_s],y
        beq     @end
        inx
        iny
        cpy     #255
        bcc     @c
        lda     #0
        sta     [hui_s],y
@end:   rep     #$20
        .a16
@out:   rts
