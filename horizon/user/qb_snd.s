; qb_snd.s - Quabricks' sound (included by quabrick.s). With Lau (REV $0A) and
; /BIN/QUABRICK.SFX: each effect is one SYS_SPLAY of its sample (16 kHz, 8-bit; any free voice,
; the kernel takes the program's oldest when all eight play). Without either: short POKEY 2
; sequences on channels 1 and 2, a step every frame (2 SYS_SNDW a channel while one plays).

SFX_MOVE   = 0
SFX_ROTATE = 1
SFX_SOFT   = 2
SFX_HARD   = 3
SFX_LOCK   = 4
SFX_CLEAR1 = 5                          ; 5-8: 1-4 lines
SFX_LEVEL  = 9
SFX_OVER   = 10
SFX_MMOVE  = 11
SFX_MSEL   = 12
SFX_HOLD   = 13
SFX_PAUSE  = 14
NSFX       = 15
SFXRATE    = $1555                      ; 16 kHz: $4000 * 16000 / 48000

snd_init:
        stz     lau
        stz     sbank
        stz     pk_on
        stz     pk_p
        stz     pk_p+2
        lda     #1
        sta     sndok
        qsys    SYS_SSTAT               ; Lau? (ENODEV: no)
        bcs     @out
        qsys    SYS_BALLOC              ; the samples into a bank of their own
        bcs     @out
        sta     sbank
        lda     #O_READ
        ptr     p_sfx
        qsys    SYS_OPEN
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
        qsys    SYS_READ
        php
        pha
        lda     z:g0
        qsys    SYS_CLOSE
        pla
        plp
        bcs     @free
        cmp     #6 + 4 * NSFX
        bcc     @free
        lda     sbank                   ; "QSFX", the count
        sta     z:p+2
        stz     z:p
        lda     [p]
        cmp     #$5351                  ; "QS"
        bne     @free
        ldy     #2
        lda     [p],y
        cmp     #$5846                  ; "FX"
        bne     @free
        ldy     #4
        lda     [p],y
        and     #$00FF
        cmp     #NSFX
        bne     @free
        lda     #1
        sta     lau
@out:   rts
@free:  lda     sbank
        qsys    SYS_BFREE
        stz     sbank
        rts

; effect A (when the sound is on)
sfx:    ldx     sndok
        beq     @out
        ldx     sndon
        beq     @out
        ldx     lau
        beq     pk_start
        asl     a                       ; its entry: offset, length at 6 + 4 id
        asl     a
        clc
        adc     #6
        tay
        lda     sbank
        sta     z:p+2
        stz     z:p
        lda     [p],y
        sta     spb                     ; address: the bank's offset, the bank
        lda     sbank
        sta     spb+2                   ; (and the length's low byte: next)
        iny
        iny
        lda     [p],y
        sta     spb+3
        stz     spb+5                   ; (length high byte, loop start 0)
        stz     spb+7
        lda     #SFXRATE
        sta     spb+9
        lda     #$E0E0                  ; volumes
        sta     spb+11
        lda     #SP_ANY << 8            ; no loop, 8-bit; any voice
        sta     spb+13
        stz     spb+15
        ptr     spb
        qsys    SYS_SPLAY
@out:   rts

; POKEY 2: effect A's sequence on its channel
pk_start:
        asl     a
        tax
        lda     pkseq,x
        tax
        lda     a:0,x                   ; the channel
        and     #$00FF
        asl     a
        tay
        inx
        txa
        sta     pk_p,y
        lda     #0
        sta     pk_n,y
        lda     #1
        sta     pk_on
        rts

; a frame of the POKEY sequences: segments {frames, AUDF, AUDF step, volume x 4, its fall a
; frame, distortion}; frames 0 ends
sfx_frame:
        lda     pk_on
        jeq     @out
        stz     pk_on
        ldy     #0
@ch:    lda     pk_p,y
        jeq     @next
        inc     pk_on
        lda     pk_n,y
        bne     @play
        ldx     pk_p,y                  ; the next segment
        lda     a:0,x
        and     #$00FF
        bne     :+
        lda     #0                      ; the end: silent
        sta     pk_p,y
        phy
        tya
        inc     a                       ; AUDC1 / AUDC2 = register 1 / 3
        ldx     #0
        qsys    SYS_SNDW
        ply
        bra     @next
:       sta     pk_n,y
        lda     a:1,x
        and     #$00FF
        sta     pk_f,y
        lda     a:2,x
        and     #$00FF
        cmp     #$80
        bcc     :+
        ora     #$FF00
:       sta     pk_fs,y
        lda     a:3,x
        and     #$00FF
        asl     a
        asl     a
        sta     pk_v,y
        lda     a:4,x
        and     #$00FF
        sta     pk_vd,y
        lda     a:5,x
        and     #$00FF
        sta     pk_d,y
        txa
        clc
        adc     #6
        sta     pk_p,y
@play:  phy
        tya                             ; AUDF (register 0 / 2)
        ldx     pk_f,y
        qsys    SYS_SNDW
        ply
        phy
        lda     pk_v,y
        lsr     a
        lsr     a
        ora     pk_d,y
        tax
        tya
        inc     a                       ; AUDC
        qsys    SYS_SNDW
        ply
        lda     pk_f,y
        clc
        adc     pk_fs,y
        sta     pk_f,y
        lda     pk_v,y
        sec
        sbc     pk_vd,y
        bpl     :+
        lda     #0
:       sta     pk_v,y
        lda     pk_n,y
        dec     a
        sta     pk_n,y
@next:  iny
        iny
        cpy     #4
        jcc     @ch
@out:   rts

; everything quiet
snd_stop:
        lda     lau
        beq     :+
        lda     #$FFFF
        qsys    SYS_SSTOP
:       lda     pk_p
        ora     pk_p+2
        beq     :+
        stz     pk_p
        stz     pk_p+2
        stz     pk_on
        lda     #1
        ldx     #0
        qsys    SYS_SNDW
        lda     #3
        ldx     #0
        qsys    SYS_SNDW
:       rts
