; sound.s - REV $07 sound: POKEY 2 ($00:DB00-$DB0F, write only) and four 8-bit DACs
; ($00:DB10-$DB13; 0, 1 left, 2, 3 right). The hardware takes these writes only while the
; classic machine is frozen (FREEZE_REQ), so the kernel silences them before every unfreeze.
;
; (0.15) Ownership: every register a program writes (sound_write, beep) is kept in a shadow
; copy, and each channel (AUDFn / AUDCn), each DAC and the rest (AUDCTL, SKCTL, ...) records
; the task that wrote it last. When that task ends (exit, kill, crash) its channels and DACs
; are silenced, and AUDCTL / SKCTL go back to 0 / 3.
;
; The chime (sound_chime, the alerts and the error beep of the user interface): two soft
; notes on one POKEY 2 channel, pure tone, the volume falling every 10 ms tick. It borrows
; a channel no program owns (4, 3, 2, 1, one that AUDCTL leaves alone); only when every
; channel is taken does it borrow channel 4 (and AUDCTL's bits for it, 15 kHz base clock
; included). The program's writes to a borrowed channel go to the shadow meanwhile, and at
; the end of the chime (0.2 s) the channel (and AUDCTL) get the program's values back.

SND_BASE    = $00DB00
SND_AUDCTL  = $00DB08
SND_SKCTL   = $00DB0F
SND_DAC     = $00DB10
SND_NREG    = $14

CH_T1       = 7                         ; the chime: ticks of note 1 (its last one silent),
CH_T2       = 15                        ; of note 2

; at boot (the classic machine is frozen): POKEY 2 out of reset, silent
snd_init:
        stz     snd_left
        lda     #NONE
        sta     ch_n
        a8
        lda     f:SYS_REV
        a16
        and     #$00FF
        sta     k_rev
        cmp     #$07
        bcc     @out
        a8
        lda     #$03                    ; SKCTL: leave reset (once)
        sta     f:SND_SKCTL
        lda     #0
        sta     f:SND_AUDCTL
        a16
        lda     #$03
        sta     snd_sh + $0F * 2
        jsr     snd_silence
@out:   jmp     au_init                 ; (0.17) Lau

; AUDC1-4 = 0, DACs = 0 (keeps A, X, Y); a chime stops
snd_silence:
        jsr     au_silence              ; (0.17) Lau's voices too
        pha
        lda     k_rev
        cmp     #$07
        bcc     @out
        stz     snd_left
        lda     #NONE
        sta     ch_n
        a8
        lda     #0
        sta     f:SND_BASE+1
        sta     f:SND_BASE+3
        sta     f:SND_BASE+5
        sta     f:SND_BASE+7
        sta     f:SND_DAC
        sta     f:SND_DAC+1
        sta     f:SND_DAC+2
        sta     f:SND_DAC+3
        a16
@out:   pla
        rts

; from the tick: a beep's time is up; the chime's next step
snd_tick:
        lda     snd_left
        beq     @ch
        dec     snd_left
        bne     @ch
        stz     snd_sh + 1 * 2          ; (AUDC1)
        ldx     #1
        lda     #0
        jsr     snd_hw
@ch:    lda     ch_n
        bmi     @out
        jmp     ch_step
@out:   rts

; register X (0-$13) = A, written to the hardware unless the chime borrows it (AUDCTL: the
; borrowed bits stay clear meanwhile)
snd_hw: pha
        lda     ch_n
        bmi     @w
        cpx     #8
        bcs     :+
        txa
        and     #$FFFE
        cmp     ch_n
        beq     @skip
        bra     @w
:       cpx     #8
        bne     @w
        pla
        and     ch_amask
        pha
@w:     pla
        a8
        sta     f:SND_BASE,x
        a16
        rts
@skip:  pla
        rts

; ---- the chime: A = kind (CH_INFO 0, CH_WARN 1, CH_QUESTION 2, CH_ERROR 3), X = volume
; 0-15 (0: none). Peak = volume * 3 / 4.
k_chime:
        and     #3
        sta     kt0
        txa
        and     #$000F
        bne     :+
        rts
:       sta     kt1
        lda     k_rev
        cmp     #$07
        bcs     :+
        rts
:       lda     kt1                     ; peak = (volume * 3 + 2) / 4
        asl     a
        adc     kt1
        inc     a
        inc     a
        lsr     a
        lsr     a
        sta     ch_pk
        lda     kt0
        asl     a
        tax
        lda     ch_notes,x
        sta     ch_f
        lda     ch_n                    ; playing already: again on the same channel
        bpl     @go
        jsr     ch_pick                 ; -> ch_n, ch_amask
        lda     snd_sh + 8 * 2          ; AUDCTL without the bits that would change it
        and     ch_amask
        a8
        sta     f:SND_AUDCTL
        a16
@go:    stz     ch_t
        jmp     ch_step

; the chime's channel: 3, 2, 1, 0 - the first one no program owns and AUDCTL leaves
; alone; else channel 3 (with AUDCTL's bits for it cleared meanwhile)
ch_pick:
        ldx     #6
@c:     lda     snd_own,x
        bne     @n
        lda     snd_sh + 8 * 2
        and     ch_abits,x
        beq     @got
@n:     dex
        dex
        bpl     @c
        ldx     #6
@got:   stx     ch_n                    ; (register AUDFn = channel * 2)
        lda     ch_abits,x
        eor     #$FFFF
        sta     ch_amask
        rts

; one tick of the chime: note 1 (CH_T1 ticks, the last one silent), note 2 (CH_T2 ticks)
ch_step:
        lda     ch_t
        cmp     #CH_T1 + CH_T2
        bcs     ch_end
        tax
        cmp     #CH_T1
        bcc     :+
        lda     ch_f+1                  ; note 2
        bra     :++
:       lda     ch_f                    ; note 1
:       and     #$00FF
        cpx     #0
        beq     @f
        cpx     #CH_T1
        bne     @v
@f:     ldy     ch_n                    ; AUDFn at each note's start
        phx
        tyx
        a8
        sta     f:SND_BASE,x
        a16
        plx
@v:     lda     ch_env,x                ; volume = (peak * env + 8) / 16
        and     #$00FF
        tay
        lda     #8
        cpy     #0
        beq     :++
:       clc
        adc     ch_pk
        dey
        bne     :-
:       lsr     a
        lsr     a
        lsr     a
        lsr     a
        ora     #$A0                    ; pure tone
        ldx     ch_n
        a8
        sta     f:SND_BASE+1,x
        a16
        inc     ch_t
        rts
; the chime ends: the channel (and AUDCTL) as the program left them
ch_end: ldx     ch_n                    ; (AUDFn = channel * 2: also its owner's index)
        lda     #NONE
        sta     ch_n
        lda     snd_own,x
        beq     @off
        txa
        asl     a
        tay                             ; (the shadow: register * 2)
        lda     snd_sh,y
        a8
        sta     f:SND_BASE,x
        a16
        lda     snd_sh + 2,y
        bra     :+
@off:   lda     #0
:       a8
        sta     f:SND_BASE+1,x
        a16
        lda     snd_sh + 8 * 2
        a8
        sta     f:SND_AUDCTL
        a16
        rts

; the notes of each kind (AUDF at the 64 kHz clock: 63921 / (2 (N + 1)) Hz): note 1, note 2
ch_notes:
        .byte   35, 47                  ; information: A5 then E5 (falling fourth)
        .byte   35, 35                  ; warning: A5 twice
        .byte   47, 35                  ; question: E5 then A5 (rising fourth)
        .byte   47, 60                  ; error: E5 then C5 (falling major third)
; the envelope, sixteenths of the peak per tick: note 1 (its last tick silent), note 2
ch_env: .byte   16, 14, 12, 11, 10, 9, 0
        .byte   16, 14, 12, 10, 9, 8, 7, 6, 5, 4, 3, 2, 2, 1, 1
; AUDCTL bits that change channel 1, 2, 3, 4 (bit 0, the 15 kHz clock, changes them all)
ch_abits:
        .word   $51, $13, $2D, $0B

; the error beep of the user interface (and a terminal's BEL): the error chime
k_errbeep:
        lda     #3
        ldx     snd_vol                 ; (setting 1; 0 = silent)
        jmp     k_chime

; (do_exit) the current task ends: its channels and DACs are silenced, AUDCTL and SKCTL
; go back to 0 and 3 if it wrote them
snd_task_exit:
        lda     k_rev
        cmp     #$07
        bcs     :+
        rts
:       lda     cur
        inc     a
        sta     kt0
        ldy     #0                      ; channels 1-4: AUDCn = 0
@c:     lda     snd_own,y
        cmp     kt0
        bne     @nc
        lda     #0
        sta     snd_own,y
        tya
        asl     a
        tax
        lda     #0
        sta     snd_sh + 2,x
        phy
        txa
        lsr     a
        inc     a
        tax                             ; (register AUDCn = channel * 2 + 1)
        lda     #0
        jsr     snd_hw
        ply
        cpy     #0                      ; (channel 1: a beep stops too)
        bne     @nc
        stz     snd_left
@nc:    iny
        iny
        cpy     #8
        bne     @c
        lda     snd_own + 8             ; the rest: AUDCTL 0, SKCTL 3
        cmp     kt0
        bne     :+
        stz     snd_own + 8
        stz     snd_sh + 8 * 2
        ldx     #8
        lda     #0
        jsr     snd_hw
        lda     #3
        sta     snd_sh + $0F * 2
        ldx     #$0F
        jsr     snd_hw
:       ldy     #10                     ; the DACs: 0
@d:     lda     snd_own,y
        cmp     kt0
        bne     @nd
        lda     #0
        sta     snd_own,y
        tya
        clc
        adc     #$10 * 2 - 10
        tax
        stz     snd_sh,x
        txa
        lsr     a
        tax
        lda     #0
        jsr     snd_hw
@nd:    iny
        iny
        cpy     #18
        bne     @d
        rts

; register X (0-$13) written by the current task: owner and shadow (A = value)
snd_mine:
        pha
        phx
        txa
        asl     a
        tax
        lda     3,s
        and     #$00FF
        sta     snd_sh,x
        lda     1,s
        cmp     #8
        bcc     @ch
        cmp     #$10
        bcc     @rest
        sec                             ; DACs: 10-16
        sbc     #$10 - 5
        bra     @set
@rest:  lda     #4                      ; AUDCTL and the rest: 8
        bra     @set
@ch:    lsr     a                       ; channel: register / 2
@set:   asl     a
        tax
        lda     cur
        inc     a
        sta     snd_own,x
        plx
        pla
        rts

; ---- $65 beep(A = pitch, X = duration in 10 ms ticks (0 = silence), Y = volume 0-15) ----
; Channel 1, pure tone, stopped by the tick; X = 0 silences channel 1.
sys_beep:
        lda     k_rev
        cmp     #$07
        bcc     @ok
        ldx     cur
        lda     t_x,x
        bne     :+
        stz     snd_left                ; silence: AUDC1 = 0
        lda     #0
        ldx     #1
        jsr     snd_mine
        jsr     snd_hw
        bra     @ok
:       sta     snd_left
        ldx     cur
        lda     t_a,x
        ldx     #0
        jsr     snd_mine
        jsr     snd_hw
        ldx     cur
        lda     t_y,x
        and     #$0F
        ora     #$A0                    ; pure tone, volume
        ldx     #1
        jsr     snd_mine
        jsr     snd_hw
@ok:    lda     #0
        jmp     set_ok

; ---- $66 sound_write(A = register 0-$13, X = value): $00-$0F POKEY 2, $10-$13 DACs ----
sys_sndw:
        ldx     cur
        lda     t_a,x
        cmp     #SND_NREG
        bcc     :+
        jmp     err_inval
:       ldy     k_rev
        cpy     #$07
        bcc     @ok
        pha
        lda     t_x,x
        and     #$00FF
        plx
        jsr     snd_mine
        jsr     snd_hw
@ok:    lda     #0
        jmp     set_ok

; ---- $67 sound_chime(A = kind, X = volume 0-15, $FFFF: the beep volume setting) ----
; (0.15) The chime of the user interface: CH_INFO 0, CH_WARN 1, CH_QUESTION 2, CH_ERROR 3.
sys_chime:
        ldx     cur
        lda     t_a,x
        cmp     #4
        bcc     :+
        jmp     err_inval
:       pha
        lda     t_x,x
        bpl     :+
        lda     snd_vol
:       tax
        pla
        jsr     k_chime
        lda     #0
        jmp     set_ok
