; fc_snd.s - FreeCell's sounds (included by freecell.s). With Lau (REV $0A) and
; /BIN/FREECELL.SFX (tools/mkfcsfx.py): each effect is one SYS_SPLAY of its sample (16 kHz,
; 8-bit, any free voice); Lau's master volume follows the sound volume setting. Without
; either: a short POKEY 2 tone (SYS_BEEP: it stops by itself) at the sound volume setting,
; the win the information chime.

SFX_PICK  = 0                           ; a card taken
SFX_PLACE = 1                           ; put down
SFX_HOME  = 2                           ; put on a foundation
SFX_BAD   = 3                           ; not allowed
SFX_WIN   = 4
SFX_DEAL  = 5
NSFX      = 6
SFXRATE   = $1555                       ; 16 kHz

snd_init:
        stz     lau
        stz     sbank
        sys     SYS_SSTAT               ; Lau? (ENODEV: no)
        bcs     @out
        sys     SYS_BALLOC              ; the samples into a bank of their own
        bcs     @out
        sta     sbank
        lda     #O_READ
        ptr     p_sfx
        sys     SYS_OPEN
        bcs     @free
        sta     z:g0
        sep     #$20
        .a8
        sta     iob
        rep     #$20
        .a16
        stz     iob+1
        lda     sbank
        sep     #$20
        .a8
        sta     iob+3
        rep     #$20
        .a16
        lda     #$FFFF
        sta     iob+4
        ptr     iob
        sys     SYS_READ
        php
        pha
        lda     z:g0
        sys     SYS_CLOSE
        pla
        plp
        bcs     @free
        cmp     #6 + 4 * NSFX
        bcc     @free
        lda     sbank                   ; "FSFX", the count
        sta     z:hp+2
        stz     z:hp
        lda     [hp]
        cmp     #$5346                  ; "FS"
        bne     @free
        ldy     #2
        lda     [hp],y
        cmp     #$5846                  ; "FX"
        bne     @free
        ldy     #4
        lda     [hp],y
        and     #$00FF
        cmp     #NSFX
        bne     @free
        lda     #1
        sta     lau
@out:   rts
@free:  lda     sbank
        sys     SYS_BFREE
        stz     sbank
        rts

; effect A
sfx:    ldx     lau
        beq     pk_sfx
        asl     a                       ; its entry: offset, length at 6 + 4 id
        asl     a
        clc
        adc     #6
        tay
        lda     sbank
        sta     z:hp+2
        stz     z:hp
        lda     [hp],y
        sta     spb                     ; address: the bank's offset, the bank
        lda     sbank
        sta     spb+2
        iny
        iny
        lda     [hp],y
        sta     spb+3                   ; the length
        stz     spb+5                   ; (its high byte, the loop start 0)
        stz     spb+7
        lda     #SFXRATE
        sta     spb+9
        lda     #$D0D0                  ; volumes
        sta     spb+11
        lda     #SP_ANY << 8            ; no loop, 8-bit; any voice
        sta     spb+13
        stz     spb+15
        ptr     spb
        sys     SYS_SPLAY
        rts

; POKEY 2: one tone at the sound volume (the win: the information chime)
pk_sfx: pha
        lda     #4
        ldx     #$FFFF
        sys     SYS_SETTING
        sta     z:t0
        pla
        ldx     z:t0
        beq     @out
        cmp     #SFX_WIN
        bne     :+
        lda     #CH_INFO
        sys     SYS_CHIME
        rts
:       asl     a
        tax
        lda     pktone,x                ; pitch | ticks << 8
        pha
        and     #$00FF
        sta     z:t1
        pla
        xba
        and     #$00FF
        tax
        ldy     z:t0
        lda     z:t1
        sys     SYS_BEEP
@out:   rts
        .segment "RODATA"
pktone: .byte   30, 1, 50, 2, 24, 5, 140, 8, 0, 0, 70, 3
        .segment "CODE"

; everything quiet
snd_stop:
        lda     lau
        beq     :+
        lda     #$FFFF
        sys     SYS_SSTOP
:       rts
