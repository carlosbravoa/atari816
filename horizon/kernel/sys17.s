; sys17.s - (0.17) Lau, the sample player ($00:DB20, hardware REV $0A): sample playback for
; programs. Lau reads RAM by itself, behind FREDDIE II's protection, so the kernel checks every
; sample range here: it must lie in memory the calling task owns (its window, its code bank, banks
; it allocated). Each voice remembers the task that started it and the banks its sample lies in:
;   - the task ends (exit, kill, crash): its voices stop (before its banks are freed);
;   - the task frees a bank (bank_free): its voices reading that bank stop first;
;   - the classic machine is shown (F12): every voice stops (snd_silence).
; The master volume (AU_MASTER) follows the volume setting (setting 1, Settings' alert volume):
; volume * 17 (0 silent, 8 = 136, 15 = 255). On REV < $0A every call returns ENODEV, so a
; program can fall back to POKEY 2.
;
;   $68 sample_play  X, Y = 16-byte block -> A = the voice
;   $69 sample_stop  A = voice 0-7, or $FFFF: every voice of the caller
;   $6A sample_stat  -> A = the caller's voices playing (bits), X = all voices playing
;   $6B sample_set   A = voice, X = pitch, Y = left volume | right volume << 8 (a playing voice)

AU_KEYON    = $00DB20
AU_KEYOFF   = $00DB21
AU_PLAYING  = $00DB22
AU_END      = $00DB23
AU_IRQEN    = $00DB24
AU_MASTER   = $00DB25
AU_VOICE    = $00DB80                   ; 16 bytes per voice
ENODEV      = 9

; the block of sample_play
SB_ADDR     = 0                         ; u24 the first sample
SB_LEN      = 3                         ; u24 length in samples (1 ..)
SB_LOOP     = 6                         ; u24 loop start in samples (with SPF_LOOP)
SB_PITCH    = 9                         ; u16 2.14: $4000 = one sample per 48 kHz output sample
SB_VOLL     = 11                        ; u8 left volume 0-255
SB_VOLR     = 12                        ; u8 right volume
SB_FLAGS    = 13                        ; u8 bit 0 loop, bit 1 16-bit samples
SB_VOICE    = 14                        ; u8 0-7, $FF: any free one
SPF_LOOP    = 1
SPF_16      = 2

; at boot (after snd_init): every voice off, no interrupt, the master volume
au_init:
        lda     k_rev
        cmp     #$0A
        bcc     @out
        ldx     #14
:       stz     au_own,x
        dex
        dex
        bpl     :-
        a8
        lda     #$FF
        sta     f:AU_KEYOFF
        sta     f:AU_END
        lda     #0
        sta     f:AU_IRQEN
        a16
        jmp     au_master
@out:   rts

; AU_MASTER = volume setting * 17 (keeps X, Y)
au_master:
        lda     k_rev
        cmp     #$0A
        bcc     @out
        a8
        lda     smp_vol                 ; (0.18: its own setting, 4)
        and     #$0F
        pha
        asl     a
        asl     a
        asl     a
        asl     a
        ora     1,s
        sta     f:AU_MASTER
        pla
        a16
@out:   rts

; every voice off (snd_silence: before the classic machine runs); keeps A, X, Y
au_silence:
        pha
        lda     k_rev
        cmp     #$0A
        bcc     :+
        a8
        lda     #$FF
        sta     f:AU_KEYOFF
        a16
:       pla
        rts

; voice X (0-14, *2) off and free
au_off: lda     #0
        sta     au_own,x
        txa
        lsr     a
        tay
        lda     au_bit,y
        a8
        sta     f:AU_KEYOFF
        a16
        rts

; (do_exit, before the banks are freed) the current task's voices stop
au_task_exit:
        lda     k_rev
        cmp     #$0A
        bcc     @out
        lda     cur
        inc     a
        sta     kt0
        ldx     #14
@v:     lda     au_own,x
        cmp     kt0
        bne     :+
        jsr     au_off
:       dex
        dex
        bpl     @v
@out:   rts

; (bank_free by the task) bank A is going: the current task's voices that read it stop
; (keeps A)
au_bank_gone:
        pha
        sta     kt1
        lda     k_rev
        cmp     #$0A
        bcc     @out
        lda     cur
        inc     a
        sta     kt0
        ldx     #14
@v:     lda     au_own,x
        cmp     kt0
        bne     @n
        lda     kt1
        cmp     au_b0,x
        bcc     @n
        lda     au_b1,x
        cmp     kt1
        bcc     @n
        jsr     au_off
@n:     dex
        dex
        bpl     @v
@out:   pla
        rts

; voice in A (any value) -> X = voice * 2, C set if it is not one of the caller's (EINVAL)
au_mine:
        cmp     #8
        bcs     @no
        asl     a
        tax
        lda     cur
        inc     a
        cmp     au_own,x
        bne     @no
        clc
        rts
@no:    sec
        rts

; ---- $68 sample_play(X, Y = block) -> A = voice ----
sys_splay:
        lda     k_rev
        cmp     #$0A
        bcs     :+
        lda     #ENODEV
        jmp     set_err
:       ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #16
        sta     kt2
        stz     kt3
        jsr     uaccess
        bcc     :+
        jmp     err_fault
:       lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        ldy     #14
:       lda     [kp1],y
        sta     au_blk,y
        dey
        dey
        bpl     :-
        ; the length in bytes (kt2:kt3), the sample's first byte (kt0 offset, kt1 bank)
        lda     au_blk+SB_LEN
        sta     kt2
        lda     au_blk+SB_LEN+2
        and     #$00FF
        sta     kt3
        ora     kt2
        bne     :+
        jmp     err_inval               ; (no samples)
:       lda     au_blk+SB_FLAGS
        and     #SPF_16
        beq     :+
        asl     kt2
        rol     kt3
        lda     au_blk+SB_ADDR          ; 16-bit samples start on an even address
        lsr     a
        bcc     :+
        jmp     err_inval
:       lda     au_blk+SB_ADDR
        sta     kt0
        lda     au_blk+SB_ADDR+2
        and     #$00FF
        sta     kt1
        bne     @banks
        ; bank 0: inside the window $0000-$7FFF
        lda     kt3
        bne     @fault
        lda     kt0
        clc
        adc     kt2
        bcs     @fault
        cmp     #$8001
        bcs     @fault
        ldx     cur
        lda     t_wbank,x
        sta     kt1                     ; the window's physical bank
        sta     au_t                    ; first and last bank
        sta     au_t+2
        bra     @loop
@fault: jmp     err_fault
@banks: ; the last byte: kt1:kt0 + bytes - 1 (24 bits, within the 16 MB)
        lda     kt1
        sta     au_t
        lda     kt0
        clc
        adc     kt2
        tax
        lda     kt1
        adc     kt3
        cpx     #0                      ; (end - 1)
        bne     :+
        dec     a
:       cmp     #$0100
        bcs     @fault
        sta     au_t+2
        ldx     cur                     ; every bank from the first to the last: the caller's
        lda     t_id,x
        sta     kt4
        ldx     au_t
:       lda     bank_st,x
        and     #$00FF
        cmp     kt4
        bne     @fault
        inx
        cpx     au_t+2
        bcc     :-
        beq     :-
@loop:  lda     au_blk+SB_FLAGS         ; a loop: start < length, at least 4 samples long
        and     #SPF_LOOP
        beq     @voice
        lda     au_blk+SB_LEN+2         ; length - loop start (24 bits) >= 4
        and     #$00FF
        sta     kt5
        lda     au_blk+SB_LOOP+2
        and     #$00FF
        sta     kt6
        lda     au_blk+SB_LEN
        sec
        sbc     au_blk+SB_LOOP
        tax
        lda     kt5
        sbc     kt6                     ; (with the low word's borrow)
        bmi     @inval
        bne     @voice                  ; >= 65536
        cpx     #4
        bcs     @voice
@inval: jmp     err_inval
@voice: lda     au_blk+SB_VOICE
        and     #$00FF
        cmp     #$FF
        beq     @auto
        cmp     #8
        bcs     @inval
        asl     a
        tax
        lda     au_own,x                ; another task's voice that still plays: busy
        beq     @take
        lda     cur
        inc     a
        cmp     au_own,x
        beq     @take
        txa
        lsr     a
        tay
        a8
        lda     f:AU_PLAYING
        and     au_bit,y
        a16
        beq     @take
@busy:  lda     #EAGAIN
        jmp     set_err
@auto:  a8                              ; a voice that is not playing
        lda     f:AU_PLAYING
        a16
        and     #$00FF
        sta     kt5
        ldx     #0
        ldy     #0
:       lda     au_bit,y
        and     kt5
        and     #$00FF
        beq     @take
        inx
        inx
        iny
        cpy     #8
        bcc     :-
        lda     cur                     ; none: the caller's voice started first
        inc     a
        sta     kt5
        stz     kt6
        ldy     #NONE
        ldx     #14
:       lda     au_own,x
        cmp     kt5
        bne     :+
        lda     au_cnt                  ; its age: plays since cnt - seq starts
        sec
        sbc     au_seq,x
        cmp     kt6
        bcc     :+
        sta     kt6
        txy
:       dex
        dex
        bpl     :--
        cpy     #NONE
        beq     @busy
        tyx
@take:  ; X = voice * 2: off, its registers, END cleared, on
        stx     kt7
        txa
        lsr     a
        tay
        lda     au_bit,y
        sta     kt6
        a8
        sta     f:AU_KEYOFF
        a16
        txa                             ; the register block: AU_VOICE + voice * 16
        asl     a
        asl     a
        asl     a
        tax
        a8
        lda     kt0                     ; V_START: the physical address
        sta     f:AU_VOICE,x
        lda     kt0+1
        sta     f:AU_VOICE+1,x
        lda     kt1
        sta     f:AU_VOICE+2,x
        lda     au_blk+SB_LEN           ; V_LEN, V_LOOP, V_PITCH, V_VOL_L, V_VOL_R
        sta     f:AU_VOICE+3,x
        lda     au_blk+SB_LEN+1
        sta     f:AU_VOICE+4,x
        lda     au_blk+SB_LEN+2
        sta     f:AU_VOICE+5,x
        lda     au_blk+SB_LOOP
        sta     f:AU_VOICE+6,x
        lda     au_blk+SB_LOOP+1
        sta     f:AU_VOICE+7,x
        lda     au_blk+SB_LOOP+2
        sta     f:AU_VOICE+8,x
        lda     au_blk+SB_PITCH
        sta     f:AU_VOICE+9,x
        lda     au_blk+SB_PITCH+1
        sta     f:AU_VOICE+10,x
        lda     au_blk+SB_VOLL
        sta     f:AU_VOICE+11,x
        lda     au_blk+SB_VOLR
        sta     f:AU_VOICE+12,x
        lda     au_blk+SB_FLAGS
        and     #SPF_LOOP | SPF_16
        sta     f:AU_VOICE+13,x
        lda     kt6
        sta     f:AU_END
        sta     f:AU_KEYON
        a16
        ldx     kt7
        lda     cur
        inc     a
        sta     au_own,x
        lda     au_t
        sta     au_b0,x
        lda     au_t+2
        sta     au_b1,x
        inc     au_cnt
        lda     au_cnt
        sta     au_seq,x
        txa
        lsr     a
        jmp     set_ok

; ---- $69 sample_stop(A = voice, $FFFF: all of the caller's) ----
sys_sstop:
        lda     k_rev
        cmp     #$0A
        bcs     :+
        lda     #ENODEV
        jmp     set_err
:       ldx     cur
        lda     t_a,x
        cmp     #$FFFF
        bne     :+
        jsr     au_task_exit
        bra     @ok
:       jsr     au_mine
        bcc     :+
        jmp     err_inval
:       jsr     au_off
@ok:    lda     #0
        jmp     set_ok

; ---- $6A sample_stat -> A = the caller's voices playing, X = all voices playing ----
sys_sstat:
        lda     k_rev
        cmp     #$0A
        bcs     :+
        lda     #ENODEV
        jmp     set_err
:       a8
        lda     f:AU_PLAYING
        a16
        and     #$00FF
        sta     kt5
        ldx     cur
        sta     t_x,x
        lda     cur
        inc     a
        sta     kt4
        stz     kt6
        ldx     #14
        ldy     #7
:       lda     au_own,x
        cmp     kt4
        bne     :+
        lda     au_bit,y
        and     #$00FF
        tsb     kt6
:       dex
        dex
        dey
        bpl     :--
        lda     kt6
        and     kt5
        jmp     set_ok

; ---- $6B sample_set(A = voice, X = pitch, Y = left | right << 8): a voice of the caller ----
sys_sset:
        lda     k_rev
        cmp     #$0A
        bcs     :+
        lda     #ENODEV
        jmp     set_err
:       ldx     cur
        lda     t_a,x
        jsr     au_mine
        bcc     :+
        jmp     err_inval
:       txa                             ; X = voice * 16
        asl     a
        asl     a
        asl     a
        tay
        ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        tyx
        a8
        lda     kt0
        sta     f:AU_VOICE+9,x
        lda     kt0+1
        sta     f:AU_VOICE+10,x
        lda     kt1
        sta     f:AU_VOICE+11,x
        lda     kt1+1
        sta     f:AU_VOICE+12,x
        a16
        lda     #0
        jmp     set_ok

au_bit: .byte   1, 2, 4, 8, 16, 32, 64, 128, 0
