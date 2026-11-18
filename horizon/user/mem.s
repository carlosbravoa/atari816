; MEM - allocates banks until ENOMEM, writes and reads back the second one, frees them
; all, and checks that a bank it does not own cannot be freed.
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  stz     z:n
@alloc: sys     SYS_BALLOC
        bcs     @full
        ldx     z:n
        sta     banks,x
        inx
        inx
        stx     z:n
        bra     @alloc
@full:  sta     z:err
        print   "mem: got "
        lda     z:n
        lsr     a
        jsr     put_dec
        print   " banks, then error "
        lda     z:err
        jsr     put_dec
        jsr     put_nl
        lda     z:n                     ; second bank: write and read back
        cmp     #4
        bcc     @free
        stz     z:p
        lda     banks+2
        sta     z:p+2
        lda     #$A55A
        sta     [p]
        ldy     #$FFFE
        lda     #$1234
        sta     [p],y
        lda     [p]
        cmp     #$A55A
        beq     *+5
        jmp     @bad
        lda     [p],y
        cmp     #$1234
        beq     *+5
        jmp     @bad
        print   "mem: bank $"
        lda     banks+2
        jsr     put_hex8
        print   " is writable\n"
@free:  ldx     z:n
        beq     @fin
        dex
        dex
        stx     z:n
        lda     banks,x
        sys     SYS_BFREE
        bcc     @free
        bra     @bad
@fin:   lda     #$01                    ; the kernel's bank
        sys     SYS_BFREE
        jcc     @bad
        sys     SYS_BALLOC              ; everything came back
        jcs     @bad
        sys     SYS_BFREE
        print   "mem: all freed, bank_free($01) refused\n"
        exit    0
@bad:   print   "mem: FAILED\n"
        exit    1

        .segment "BSS"
banks:  .res    256
        .segment "ZEROPAGE"
n:      .res    2
err:    .res    2
p:      .res    4
