; console.s - kernel console on DBG_OUT ($00:DEF0) and the screen (screen.s). DBG_STAT bit 7 is busy for a while
; after each byte (about 90 us on the board while the log is read, sometimes milliseconds)
; and a byte written while busy is lost.
;
; Task output goes through a console lock: a whole puts (or a whole "[kill]" line) is
; written while holding it, so it is never spliced with another task's output. While the
; console is busy the writer services interrupts, and gives the CPU away (keeping the lock)
; when a reschedule is due, so slow output never holds interrupts off or starves others.
; Raw output (kputc with kout = 0) busy-waits with interrupts masked: only for the boot
; banner, panics and "[halt]". With kout != 0, kputc appends to that bank $01 buffer
; instead (used to build the [kill] line).
; Routines keep A X Y unless noted; kputc and kputs_inline work with any D/DBR.

        .a16
        .i16

kputc:  php
        rep     #$30
        pha
        lda     f:KDPL+kout
        beq     @raw
        phx
        tax
        lda     3,s
        a8
        sta     f:$010000,x
        a16
        inx
        txa
        sta     f:KDPL+kout
        plx
        pla
        plp
        rts
@raw:   a8
:       lda     f:DBG_STAT
        bmi     :-
        lda     1,s
        sta     f:DBG_OUT
        a16
        lda     1,s
        jsr     scr_putc                ; (scr_coop = 0: no yielding here)
        pla
        plp
        rts

; ---- console lock (task context only; may block) ----
con_lock:
        lda     cur
        inc     a
        cmp     con_owner
        beq     @out                    ; already ours
        lda     con_owner
        beq     @take
        lda     #W_CONS
        ldy     #0
        jsr     k_block
        bra     con_lock
@take:  lda     cur
        inc     a
        sta     con_owner
@out:   rts

con_unlock:
        stz     con_owner
        lda     #W_CONS
        ldy     #0
        jmp     k_wake_all

; write byte A (lock held). May yield; clobbers X Y.
con_byte:
        pha
@wait:  a8
        lda     f:DBG_STAT
        a16
        bpl     @put
        jsr     irq_poll
        lda     need_resched
        beq     @wait
        jsr     k_yield
        bra     @wait
@put:   pla
        a8
        sta     f:DBG_OUT
        a16
        ldx     #1                      ; the screen too; it may yield between rows
        stx     scr_coop
        jsr     scr_putc
        stz     scr_coop
        rts

; write the zero-terminated string at bank $01 offset A (lock held). Clobbers A X Y.
con_write:
        pha
        jsr     scr_hide                ; the cursor goes once per string
@loop:  lda     1,s
        tax
        lda     f:$010000,x
        and     #$00FF
        beq     @end
        jsr     con_byte
        lda     1,s
        inc     a
        sta     1,s
        bra     @loop
@end:   pla
        jmp     scr_show

; lock, write the string at bank $01 offset A, unlock
con_print:
        pha
        jsr     con_lock
        pla
        jsr     con_write
        jmp     con_unlock

; user putc: one byte under the lock
uputc:  pha
        jsr     con_lock
        jsr     scr_hide
        pla
        jsr     con_byte
        jsr     scr_show
        jmp     con_unlock

; string after the JSR (kprint macro)
kputs_inline:
        php
        a16i16
        pha
        phx
        lda     6,s                     ; return address = string - 1
        tax
@loop:  inx
        lda     f:$010000,x
        and     #$00FF
        beq     @end
        jsr     kputc
        bra     @loop
@end:   txa
        sta     6,s                     ; RTS goes to the byte after the terminator
        plx
        pla
        plp
        rts

kputhex16:
        pha
        xba
        jsr     kputhex8
        xba
        jsr     kputhex8
        pla
        rts

kputhex8:
        pha
        pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     @nib
        pla
        jsr     @nib
        pla
        rts
@nib:   and     #$000F
        cmp     #10
        bcc     :+
        adc     #6
:       adc     #'0'
        jmp     kputc

; A = unsigned 16-bit, in decimal
kputdec:
        pha
        phx
        phy
        ldy     #0                      ; digits pushed
:       ldx     #10
        jsr     udiv16
        pha                             ; quotient
        txa
        clc
        adc     #'0'
        tax
        pla
        phx
        iny
        cmp     #0
        bne     :-
:       pla
        jsr     kputc
        dey
        bne     :-
        ply
        plx
        pla
        rts

; name of the current task (8 characters, trailing spaces dropped)
kputname:
        pha
        phx
        phy
        lda     cur
        asl     a
        asl     a
        tax                             ; slot*8
        ldy     #8
        txa                             ; find the last non-space
        clc
        adc     #8
        sta     pv0
:       ldx     pv0
        dex
        lda     f:t_name,x
        and     #$00FF
        cmp     #' '
        bne     :+
        stx     pv0
        dey
        bne     :-
:       lda     cur
        asl     a
        asl     a
        tax
:       cpy     #0
        beq     :+
        lda     f:t_name,x
        jsr     kputc
        inx
        dey
        bra     :-
:       ply
        plx
        pla
        rts
