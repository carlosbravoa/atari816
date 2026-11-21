; ludiv.s (65816) - cc65's 32-bit unsigned division, with 16-bit registers inside. Same
; entry points and contract as libsrc/runtime/ludiv.s (lmod, lumod, ldiv and
; _time_t_to_tm call udiv32 directly):
;   udiv32: ptr1:sreg / ptr3:ptr4 -> quotient ptr1:sreg, remainder ptr2:tmp3:tmp4,
;           A = remainder byte 0, Y = 0; tmp1/tmp2 untouched (ldiv keeps the signs there).
; A divisor below 65536 (x / 7) takes two 16-step loops on a 16-bit remainder; otherwise
; one 32-step loop on 16-bit words.

        .p816
        .smart  off

        .export         tosudiv0ax, tosudiveax, getlop, udiv32
        .import         addysp1
        .importzp       c_sp, sreg, tmp3, tmp4, ptr1, ptr2, ptr3, ptr4

        .segment "CODE"
        .a8
        .i8

tosudiv0ax:
        stz     sreg
        stz     sreg+1
tosudiveax:
        jsr     getlop                  ; Get the parameters
        jsr     udiv32                  ; Do the division
        lda     ptr1                    ; Result is in ptr1:sreg
        ldx     ptr1+1
        rts

; (unchanged from cc65) right operand A/X/sreg -> ptr3:ptr4, left from the stack -> ptr1:sreg
getlop: sta     ptr3
        stx     ptr3+1
        lda     sreg
        sta     ptr4
        lda     sreg+1
        sta     ptr4+1
        lda     (c_sp)
        ldy     #1
        sta     ptr1
        lda     (c_sp),y
        sta     ptr1+1
        iny
        lda     (c_sp),y
        sta     sreg
        iny
        lda     (c_sp),y
        sta     sreg+1
        jmp     addysp1

udiv32: rep     #$30
        .a16
        .i16
        lda     ptr4
        bne     long
        ; 16-bit divisor d = ptr3: high word, then low word, remainder in A
        ldy     #16
        lda     #0
h0:     asl     sreg
        rol     a
        bcs     h1                      ; the remainder passed 16 bits: >= d
        cmp     ptr3
        bcc     h2
h1:     sbc     ptr3                    ; (carry set)
        inc     sreg
h2:     dey
        bne     h0
        ldy     #16
l0:     asl     ptr1
        rol     a
        bcs     l1
        cmp     ptr3
        bcc     l2
l1:     sbc     ptr3
        inc     ptr1
l2:     dey
        bne     l0
        sta     ptr2
        stz     tmp3                    ; (tmp3, tmp4)
        bra     done

        ; 32-bit divisor: remainder ptr2:tmp3 (16-bit words)
long:   stz     ptr2
        stz     tmp3
        ldy     #32
g0:     asl     ptr1
        rol     sreg
        rol     ptr2
        rol     tmp3
        lda     ptr2
        sec
        sbc     ptr3
        tax
        lda     tmp3
        sbc     ptr4
        bcc     g1
        sta     tmp3
        stx     ptr2
        inc     ptr1
g1:     dey
        bne     g0
done:   sep     #$30
        .a8
        .i8
        lda     ptr2
        ldy     #0
        rts
