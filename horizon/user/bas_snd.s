; bas_snd.s - (2.0) samples through Lau, the sample player: WAVE (a waveform made, or a
; sound file loaded), PLAY (a sample on a voice, at a note), NOTE. The language is in
; BASIC.md, "Samples".
;
; Samples 0-31, signed 8- or 16-bit, in banks of their own (sm_bks, filled from the bottom;
; a sample defined again keeps its place when it fits there). A sample's natural pitch is
; note 0: a WAVE is C4 (261.63 Hz) at 16,000 samples a second, a file plays at its own rate.
; PLAY s, n plays it n semitones higher (pitch x 2^(n/12)), or at a named note ("C#5").
; Without Lau (REV < $0A) WAVE still makes samples, PLAY says "Not available on this
; machine"; PLAY OFF does nothing.

        .segment "CODE"
        .a16
        .i16
NSMP    = 32
SM_DEF  = 1                     ; sm_flg: defined
SM_LOOP = 2                     ;   looped (from sm_lp to the end)
SM_16   = 4                     ;   16-bit samples
SMBANKS = 16
WPITCH  = $1555                 ; 16,000 samples a second (2.14 steps of Lau's 48 kHz)
WSTEP   = 1071                  ; C4's phase step at 16 kHz (261.63 x 65536 / 16000)
WLOOP   = 979                   ; a looped wave: 16 cycles of C4

; ---------------------------------------------------------------- WAVE
; WAVE s, shape [, ms [, half]]: shape 0 sine, 1 square, 2 triangle, 3 saw, 4 noise; ms long
; (default 400, up to 4000; 0: a loop that plays until stopped); half: the sound halves
; every half ms (0: no decay). WAVE s, "file": a .WAV (PCM, mono, 8 or 16 bits) or raw
; signed 8-bit samples at 16 kHz.
st_wave:
        jsr     eval_u16
        cmp     #NSMP
        jcs     @bad
        sta     wv_s
        lda     #','
        jsr     expect
        jsr     eval
        lda     ft
        cmp     #T_STR
        jeq     wave_file
        jsr     acc_round
        lda     fhi
        bne     @bad
        lda     flo
        cmp     #5
        bcs     @bad
        sta     wv_sh
        lda     #400
        sta     wv_ms
        stz     wv_hl
        jsr     peek
        cmp     #','
        bne     @go
        inc     z:tp
        jsr     eval_u16
        cmp     #4001
        bcs     @bad
        sta     wv_ms
        jsr     peek
        cmp     #','
        bne     @go
        inc     z:tp
        jsr     eval_u16
        cmp     #4001
        bcs     @bad
        sta     wv_hl
@go:    jsr     wave_make
        jmp     stmt_end
@bad:   err     E_ARG

; the samples of a WAVE (wv_s, wv_sh, wv_ms, wv_hl)
wave_make:
        lda     wv_ms                   ; n samples: 16 a millisecond
        bne     :+
        lda     #WLOOP
        bra     :++
:       asl     a
        asl     a
        asl     a
        asl     a
:       sta     wv_n
        jsr     smp_alloc
        lda     wv_s
        asl     a
        tax
        lda     wv_n
        sta     sm_len,x
        stz     sm_lp,x
        lda     #WPITCH
        sta     sm_pit,x
        lda     #SM_DEF
        ldy     wv_ms
        bne     :+
        ora     #SM_LOOP
:       sta     sm_flg,x
        stz     wv_ph
        lda     #$ACE1
        sta     wv_rnd
        stz     wv_k
        stz     wv_a
        lda     wv_hl                   ; the half-life in samples
        asl     a
        asl     a
        asl     a
        asl     a
        sta     wv_hs
        lda     #256
        sta     wv_env
        ldy     #0
@s:     cpy     wv_n
        jcs     @out
        tya                             ; every 32 samples: the envelope
        and     #31
        bne     :+
        phy
        jsr     wv_envelope
        ply
:       lda     wv_ph                   ; the waveform at this phase -> a signed byte
        xba
        and     #$00FF
        sta     z:t0
        ldx     wv_sh
        cpx     #1
        beq     @sq
        cpx     #2
        beq     @tri
        cpx     #3
        beq     @saw
        cpx     #4
        beq     @noise
        and     #$003F                  ; sine: a quarter wave mirrored
        tax
        lda     z:t0
        and     #$0040
        beq     :+
        txa
        eor     #$003F
        inc     a
        tax
:       lda     qsin,x
        and     #$00FF
        bit     z:t0-1                  ; (bit 7 of t0: the second half)
        bpl     @val
        eor     #$FFFF
        inc     a
        bra     @val
@sq:    lda     #96
        bit     z:t0-1
        bpl     @val
        lda     #$10000 - 96
        bra     @val
@tri:   asl     a                       ; 0..510: rising, then falling
        sec
        sbc     #127
        cmp     #128
        bcc     @val
        cmp     #$8000
        bcs     @val
        eor     #$FFFF                  ; 128 .. 383 -> 127 .. -128
        clc
        adc     #256
        bra     @val
@saw:   sec
        sbc     #128
        bra     @val
@noise: lda     wv_ph                   ; a new random value 16 times a C4 cycle (8 steps
        eor     wv_lph                  ; of a 16-bit LFSR)
        and     #$F000
        beq     @nold
        ldx     #8
        lda     wv_rnd
:       lsr     a
        bcc     :+
        eor     #$B400
:       dex
        bne     :--
        sta     wv_rnd
@nold:  lda     wv_rnd
        and     #$00FF
        sec
        sbc     #128
@val:   ldx     wv_env                  ; times the envelope (256: as it is)
        cpx     #256
        beq     :+
        jsr     wv_mul
:       a8
        sta     [cp],y
        a16
        lda     wv_ph
        sta     wv_lph
        clc
        adc     #WSTEP
        sta     wv_ph
        iny
        jmp     @s
@out:   rts

; A (signed) * wv_env / 256 -> A
wv_mul: sta     z:t1
        bpl     :+
        eor     #$FFFF
        inc     a
:       sta     z:t2                    ; |A|
        stz     z:t3
        lda     wv_env
        sta     z:t4
@l:     lda     z:t4
        beq     @d
        lsr     z:t4
        bcc     :+
        lda     z:t3
        clc
        adc     z:t2
        sta     z:t3
:       asl     z:t2
        bra     @l
@d:     lda     z:t3
        xba
        and     #$00FF
        ldx     z:t1
        bpl     :+
        eor     #$FFFF
        inc     a
:       rts

; the envelope for the 32 samples from Y: a 2 ms rise, the decay (halved every wv_hs
; samples, straight between the halvings), a 10 ms fall at the end; a loop has none
wv_envelope:
        sty     z:t5
        lda     #256
        sta     wv_env
        lda     wv_ms
        jeq     @out
        lda     wv_hs                   ; the decay: 256 >> k, less a part of the next half
        beq     @rise
        lda     wv_k
        cmp     #9
        bcc     :+
        stz     wv_env
        rts
:       tax
        lda     #256
:       cpx     #0
        beq     :+
        lsr     a
        dex
        bra     :-
:       sta     wv_env
        ldx     wv_a                    ; - e * a / hs / 2
        jsr     umul16
        sta     m_a
        stx     m_a+2
        lda     wv_hs
        asl     a
        sta     m_b
        stz     m_b+2
        bcc     :+
        inc     m_b+2
:       jsr     udiv32
        lda     wv_env
        sec
        sbc     m_r
        sta     wv_env
        lda     wv_a                    ; on 32 samples
        clc
        adc     #32
        sta     wv_a
:       lda     wv_a
        cmp     wv_hs
        bcc     @rise
        sbc     wv_hs
        sta     wv_a
        inc     wv_k
        bra     :-
@rise:  lda     z:t5                    ; the first 32 samples: half
        bne     :+
        lsr     wv_env
:       lda     wv_n                    ; the last 160: down to 0
        sec
        sbc     z:t5
        cmp     #160
        bcs     @out
        sta     z:t6                    ; env * left / 160
        lda     wv_env
        ldx     z:t6
        jsr     umul16
        sta     m_a
        stx     m_a+2
        lda     #160
        sta     m_b
        stz     m_b+2
        jsr     udiv32
        lda     m_r
        sta     wv_env
@out:   rts

; space for sample wv_s, A bytes (rounded up to even): its old place if it fits, else the
; end of the last sample bank or a new bank -> z:cp, sm_bank, sm_off
smp_alloc:
        inc     a
        and     #$FFFE
        sta     sa_n
        lda     wv_s
        asl     a
        tax
        lda     sm_cap,x
        beq     @new
        cmp     sa_n
        bcs     @at
@new:   lda     sm_nb
        beq     @bank
        lda     sm_top
        clc
        adc     sa_n
        bcs     @bank
        ldy     sm_nb
        lda     sm_bks-2,y
        sta     sm_bank,x
        lda     sm_top
        sta     sm_off,x
        clc
        adc     sa_n
        sta     sm_top
        bra     @cap
@bank:  lda     sm_nb
        cmp     #SMBANKS * 2
        bcs     @mem
        phx
        sys     SYS_BALLOC
        plx
        bcs     @mem
        ldy     sm_nb
        sta     sm_bks,y
        iny
        iny
        sty     sm_nb
        sta     sm_bank,x
        stz     sm_off,x
        lda     sa_n
        sta     sm_top
@cap:   lda     sa_n
        sta     sm_cap,x
@at:    lda     sm_off,x
        sta     z:cp
        lda     sm_bank,x
        sta     z:cp+2
        rts
@mem:   err     E_MEM

; WAVE s, "file": a .WAV file's sound, or raw signed 8-bit samples at 16 kHz (at most
; 65,534 bytes of sound: longer ones are cut)
wave_file:
        jsr     acc_path0
        ptr     abuf
        lda     #O_READ
        sys     SYS_OPEN
        bcc     :+
        jmp     wf_err
:       sta     wf_h
        lda     fbank                   ; the start of the file -> fbank:0000
        stz     wf_blk+1
        sta     wf_blk+3
        lda     #4096
        sta     wf_blk+4
        lda     wf_h
        a8
        sta     wf_blk
        a16
        ptr     wf_blk
        sys     SYS_READ
        jcs     wf_ferr
        sta     wf_got
        stz     wf_off
        stz     wf_off+2
        lda     #$FFFE
        sta     wf_len
        stz     wf_len+2
        lda     #16000
        sta     wf_rate
        stz     wf_rate+2
        stz     wf_bits                 ; 0: raw signed 8-bit
        lda     wf_got
        cmp     #44
        jcc     @raw
        lda     [fbp]                   ; "RIFF" .... "WAVE"
        cmp     #'R' | ('I' << 8)
        jne     @raw
        ldy     #2
        lda     [fbp],y
        cmp     #'F' | ('F' << 8)
        jne     @raw
        ldy     #8
        lda     [fbp],y
        cmp     #'W' | ('A' << 8)
        jne     @raw
        ldy     #10
        lda     [fbp],y
        cmp     #'V' | ('E' << 8)
        jne     @raw
        ldy     #12                     ; the chunks
@ck:    tya
        clc
        adc     #8
        bcs     @bad
        cmp     wf_got
        beq     :+
        bcs     @bad
:       lda     [fbp],y                 ; "fmt "
        cmp     #'f' | ('m' << 8)
        bne     @data
        iny
        iny
        lda     [fbp],y
        dey
        dey
        cmp     #'t' | (' ' << 8)
        bne     @data
        phy
        tya
        clc
        adc     #8
        tay
        lda     [fbp],y                 ; PCM, mono
        cmp     #1
        bne     @badp
        iny
        iny
        lda     [fbp],y
        cmp     #1
        bne     @badp
        iny
        iny
        lda     [fbp],y                 ; the rate
        sta     wf_rate
        iny
        iny
        lda     [fbp],y
        sta     wf_rate+2
        tya
        clc
        adc     #8
        tay
        lda     [fbp],y                 ; bits
        cmp     #8
        beq     :+
        cmp     #16
        bne     @badp
:       sta     wf_bits
        ply
        bra     @next
@badp:  ply
@bad:   lda     wf_h
        sys     SYS_CLOSE
        err     E_ARG
@data:  lda     [fbp],y                 ; "data"
        cmp     #'d' | ('a' << 8)
        bne     @next
        iny
        iny
        lda     [fbp],y
        dey
        dey
        cmp     #'t' | ('a' << 8)
        bne     @next
        lda     wf_bits                 ; (after "fmt ")
        beq     @bad
        tya
        clc
        adc     #8
        sta     wf_off
        iny
        iny
        iny
        iny
        lda     [fbp],y
        sta     wf_len
        iny
        iny
        lda     [fbp],y                 ; (65,536 or more: cut)
        beq     @load
        lda     #$FFFE
        sta     wf_len
        bra     @load
@next:  iny                             ; the next chunk: 8 + its size (even)
        iny
        iny
        iny
        lda     [fbp],y
        inc     a
        and     #$FFFE
        sta     z:t0
        iny
        iny
        lda     [fbp],y
        bne     @bad
        tya
        sec
        adc     #1
        bcs     @bad
        clc
        adc     z:t0
        bcs     @bad
        tay
        jmp     @ck
@raw:   stz     wf_off
@load:  lda     wf_len                  ; at most 65,534 bytes
        bne     :+
        jmp     @bad
:       cmp     #$FFFE
        bcc     :+
        lda     #$FFFE
        sta     wf_len
:       lda     wf_len
        jsr     smp_alloc
        lda     wf_h                    ; to the sound and into the sample's place
        ldx     wf_off
        ldy     #0
        sys     SYS_SEEK
        jcs     wf_ferr
        lda     z:cp
        sta     wf_blk+1
        lda     z:cp+2
        a8
        sta     wf_blk+3
        a16
        lda     wf_len
        sta     wf_blk+4
        ptr     wf_blk
        sys     SYS_READ
        jcs     wf_ferr
        and     #$FFFE
        sta     wf_got
        lda     wf_h
        sys     SYS_CLOSE
        lda     wf_got
        jeq     @empty
        lda     wf_bits                 ; 8-bit WAV: unsigned -> signed
        cmp     #8
        bne     :++
        ldy     #0
:       lda     [cp],y
        eor     #$8080
        sta     [cp],y
        iny
        iny
        cpy     wf_got
        bcc     :-
:       lda     wv_s
        asl     a
        tax
        lda     #SM_DEF
        ldy     wf_bits
        cpy     #16
        bne     :+
        ora     #SM_16
:       sta     sm_flg,x
        stz     sm_lp,x
        lda     wf_got
        sta     sm_len,x
        lda     wf_rate                 ; the pitch: rate * 16384 / 48000 = rate * 1024 / 3000
        sta     m_a
        lda     wf_rate+2
        sta     m_a+2
        ldx     #10
:       asl     m_a
        rol     m_a+2
        dex
        bne     :-
        lda     #3000
        sta     m_b
        stz     m_b+2
        jsr     udiv32
        lda     m_r+2
        bne     @max
        lda     m_r
        bne     :+
        inc     a
        bra     :+
@max:   lda     #$FFFF
:       pha
        lda     wv_s
        asl     a
        tax
        pla
        sta     sm_pit,x
        jmp     stmt_end
@empty: err     E_ARG
wf_ferr:
        pha
        lda     wf_h
        sys     SYS_CLOSE
        pla
wf_err: cmp     #$44
        beq     :+
        cmp     #$45
        beq     :+
        err     E_FILE
:       err     E_NOFILE

; ---------------------------------------------------------------- PLAY
; PLAY s [, note [, volume [, pan [, voice]]]]: note a number of semitones (0: as made) or
; a name ("C4", "F#3", "Bb5"); volume 0-15 (15); pan -15 left .. 15 right (0); voice 0-7
; (any free one). PLAY OFF [voice]: all of BASIC's voices (or one) stopped.
st_play:
        jsr     peek
        cmp     #TK_OFF
        bne     @play
        inc     z:tp
        lda     #$FFFF
        sta     py_v
        jsr     at_end
        beq     :+
        jsr     eval_u16
        cmp     #8
        jcs     @bad
        sta     py_v
:       lda     py_v
        sys     SYS_SSTOP
        jmp     stmt_end
@play:  jsr     eval_u16
        cmp     #NSMP
        jcs     @bad
        sta     py_s
        asl     a
        tax
        lda     sm_flg,x
        and     #SM_DEF
        bne     :+
        err     E_NOSMP
:       stz     py_n
        lda     #15
        sta     py_vol
        stz     py_pan
        lda     #SP_ANY
        sta     py_v
        jsr     peek
        cmp     #','
        jne     @go
        inc     z:tp
        jsr     eval
        lda     ft
        cmp     #T_STR
        bne     :+
        jsr     note_parse
        jcs     @bad
        bra     @n
:       jsr     acc_round
        lda     flo
        clc
        adc     #96
        cmp     #193
        jcs     @bad
        lda     flo
@n:     sta     py_n
        jsr     peek
        cmp     #','
        bne     @go
        inc     z:tp
        jsr     eval_u16
        cmp     #16
        jcs     @bad
        sta     py_vol
        jsr     peek
        cmp     #','
        bne     @go
        inc     z:tp
        jsr     eval_int
        clc
        adc     #15
        cmp     #31
        jcs     @bad
        lda     flo
        sta     py_pan
        jsr     peek
        cmp     #','
        bne     @go
        inc     z:tp
        jsr     eval_u16
        cmp     #8
        jcs     @bad
        sta     py_v
@go:    jsr     play_pitch
        jsr     play_vol
        lda     py_s                    ; the block
        asl     a
        tax
        lda     sm_off,x
        sta     pyb
        lda     sm_bank,x
        sta     pyb+2                   ; (bank, then the length's low byte)
        lda     sm_len,x
        ldy     sm_flg,x
        sta     z:t0
        tya
        and     #SM_16
        beq     :+
        lsr     z:t0
:       lda     z:t0
        a8
        sta     pyb+3
        xba
        sta     pyb+4
        a16
        stz     pyb+5
        lda     sm_lp,x
        sta     pyb+6
        stz     pyb+8
        lda     py_pit
        sta     pyb+9
        lda     py_l
        a8
        sta     pyb+11
        lda     py_r
        sta     pyb+12
        tya                             ; (flags: loop, 16-bit)
        lsr     a
        and     #SPF_LOOP | SPF_16
        sta     pyb+13
        lda     py_v
        sta     pyb+14
        stz     pyb+15
        a16
        ptr     pyb
        sys     SYS_SPLAY
        bcc     :+
        cmp     #ENODEV
        bne     @busy
        err     E_NODEV
@busy:  cmp     #EAGAIN
        bne     @bad
        err     E_INUSE
:       jmp     stmt_end
@bad:   err     E_ARG

; the pitch of sample py_s at note py_n (-96 .. 96) -> py_pit: its own x 2^(n/12)
play_pitch:
        lda     py_n                    ; n + 120 = 12 o + k (o: octaves up from -10)
        clc
        adc     #120
        ldx     #0
:       cmp     #12
        bcc     :+
        sbc     #12
        inx
        bra     :-
:       stx     z:t1
        asl     a
        tax
        lda     semis,x
        pha
        lda     py_s
        asl     a
        tax
        lda     sm_pit,x
        plx
        jsr     umul16                  ; pitch * 2^(k/12) * 32768
        sta     z:t2
        stx     z:t3
        lda     z:t1                    ; then * 2^(o - 10) / 32768
        sec
        sbc     #10 + 15
@sh:    cmp     #0
        beq     @done
        bmi     @right
        asl     z:t2
        rol     z:t3
        bcs     @big
        dec     a
        bra     @sh
@right: lsr     z:t3
        ror     z:t2
        inc     a
        bra     @sh
@done:  lda     z:t3
        bne     @big
        lda     z:t2
        bne     :+
        inc     a
:       sta     py_pit
        rts
@big:   err     E_ARG

; the volumes: v = volume x 17; left v (15 - pan) / 15 for pan > 0, right v (15 + pan)
; / 15 for pan < 0
play_vol:
        lda     py_vol
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     py_vol
        sta     py_l
        sta     py_r
        lda     py_pan
        beq     @out
        bmi     @left
        lda     #15
        sec
        sbc     py_pan
        jsr     @part
        sta     py_l
        rts
@left:  clc
        adc     #15
        jsr     @part
        sta     py_r
@out:   rts
@part:  ldx     py_l
        jsr     umul16
        sta     m_a
        stz     m_a+2
        lda     #15
        sta     m_b
        stz     m_b+2
        jsr     udiv32
        lda     m_r
        rts

; NOTE(s$): the note named by s$ in semitones from C4 ("C4" 0, "A4" 9, "C#5" 13, "Bb3" -2)
f_note: jsr     arg1s
        jsr     note_parse
        bcs     :+
        jmp     ret_s16
:       err     E_ARG

; the string in acc as a note: a letter A-G, then # or B (flat), then an octave 0-8
; (default 4) -> A (semitones from C4), C set: not a note
note_parse:
        lda     flo
        sta     z:bp
        lda     fhi
        sta     z:bp+2
        lda     flen
        beq     @no
        sta     z:t0
        lda     [bp]
        and     #$00DF
        sec
        sbc     #'A'
        cmp     #7
        bcs     @no
        tax
        lda     nbase,x
        and     #$00FF
        sta     z:t1
        ldy     #1
        cpy     z:t0
        bcs     @oct
        lda     [bp],y
        and     #$00FF
        cmp     #'#'
        bne     :+
        inc     z:t1
        iny
        bra     @oct
:       and     #$00DF
        cmp     #'B'
        bne     @oct
        dec     z:t1
        iny
@oct:   lda     #4
        cpy     z:t0
        bcs     :+
        lda     [bp],y
        and     #$00FF
        sec
        sbc     #'0'
        cmp     #9
        bcs     @no
        iny
        cpy     z:t0
        bne     @no
:       sec                             ; (octave - 4) * 12 + the note
        sbc     #4
        sta     z:t2
        asl     a
        clc
        adc     z:t2
        asl     a
        asl     a
        clc
        adc     z:t1
        clc
        rts
@no:    sec
        rts

; every sample gone, their banks back (RUN, NEW)
snd_reset:
        ldx     #0
:       cpx     sm_nb
        bcs     :+
        lda     sm_bks,x
        phx
        sys     SYS_BFREE
        plx
        inx
        inx
        bra     :-
:       stz     sm_nb
        ldx     #0
:       stz     sm_flg,x
        stz     sm_cap,x
        inx
        inx
        cpx     #NSMP * 2
        bcc     :-
        rts

        .segment "RODATA"
semis:  .word   32768, 34716, 36781, 38968, 41285, 43740, 46341, 49097, 52016, 55109, 58386, 61858
nbase:  .byte   9, 11, 0, 2, 4, 5, 7    ; A B C D E F G
qsin:   .byte   0, 3, 6, 9, 12, 16, 19, 22, 25, 28, 31, 34, 37, 40, 43, 46, 49, 51, 54, 57, 60
        .byte   63, 65, 68, 71, 73, 76, 78, 81, 83, 85, 88, 90, 92, 94, 96, 98, 100, 102, 104
        .byte   106, 107, 109, 111, 112, 113, 115, 116, 117, 118, 120, 121, 122, 122, 123, 124
        .byte   125, 125, 126, 126, 126, 127, 127, 127, 127

        .segment "BSS"
sm_bank: .res   NSMP * 2
sm_off: .res    NSMP * 2
sm_len: .res    NSMP * 2                ; bytes
sm_cap: .res    NSMP * 2                ; the bytes its place holds
sm_flg: .res    NSMP * 2                ; SM_*
sm_lp:  .res    NSMP * 2                ; the loop's start (in samples)
sm_pit: .res    NSMP * 2                ; the natural pitch (Lau's 2.14 step)
sm_bks: .res    SMBANKS * 2
sm_nb:  .res    2
sm_top: .res    2
sa_n:   .res    2
wv_s:   .res    2
wv_sh:  .res    2
wv_ms:  .res    2
wv_hl:  .res    2
wv_hs:  .res    2
wv_n:   .res    2
wv_ph:  .res    2
wv_lph: .res    2
wv_rnd: .res    2
wv_env: .res    2
wv_k:   .res    2
wv_a:   .res    2
wf_h:   .res    2
wf_blk: .res    6
wf_got: .res    2
wf_off: .res    4
wf_len: .res    4
wf_rate: .res   4
wf_bits: .res   2
py_s:   .res    2
py_n:   .res    2
py_vol: .res    2
py_pan: .res    2
py_v:   .res    2
py_pit: .res    2
py_l:   .res    2
py_r:   .res    2
pyb:    .res    16
