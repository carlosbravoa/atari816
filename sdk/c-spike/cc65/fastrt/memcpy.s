; memcpy.s (65816) - cc65's memcpy / memcpy_upwards / memcpy_getparams with MVN.
; Same entry points and contract as libsrc/common/memcpy.s (memmove and lz4 call
; memcpy_upwards with Y = 0, ptr1 = src, ptr2 = dest, ptr3 = n; it returns dest from popax).
; MVN copies upwards one byte at a time, reading each byte just before writing it, as the
; original loop does: overlapping copies (lz4's match at distance 1) give the same result.
; Both banks are the code bank: "^memcpy_getparams" is a bank byte that the Horizon loader
; relocates (o65 SEG entries), so no self-modifying code is needed.
; emu816, 100 x 4 KB: cc65's loop 590 ms, this 350 ms (about 12 cycles a byte); a 16-bit
; word loop with a 16-bit Y was tried too: 500 ms.

        .p816
        .smart  off

        .export         _memcpy, memcpy_upwards, memcpy_getparams
        .import         popax, popptr1
        .importzp       c_sp, ptr1, ptr2, ptr3

        .segment "CODE"
        .a8
        .i8

_memcpy:
        jsr     memcpy_getparams
memcpy_upwards:
        rep     #$30
        .a16
        .i16
        lda     ptr3
        beq     @none
        dec     a                       ; MVN moves A + 1 bytes
        ldx     ptr1
        ldy     ptr2
        phb                             ; (MVN leaves DBR = the destination bank)
        .byte   $54, ^memcpy_getparams, ^memcpy_getparams   ; MVN: dest bank, src bank
        plb
@none:  sep     #$30
        .a8
        .i8
        jmp     popax                   ; dest as the result

memcpy_getparams:                       ; (unchanged from cc65) leaves with Y = 0
        sta     ptr3
        stx     ptr3+1
        jsr     popptr1
        iny
        lda     (c_sp),y
        tax
        stx     ptr2+1
        dey
        lda     (c_sp),y
        sta     ptr2
        rts
