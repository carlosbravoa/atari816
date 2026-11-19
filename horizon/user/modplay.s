; modplay.s - (0.26) the MOD replayer library: ProTracker modules (M.K. and friends: 4, 6 or 8
; channels, FLT4/FLT8, xCHN up to 8; the old 15-sample format) played on Lau, the 8-voice sample
; player, through the kernel's sample calls. API: modplay.inc. Behaviour: ProTracker 2.3, written
; down in horizon/README.md ("Music") and checked tick by tick against tests/modref.py.
;
; How it maps onto Lau:
;   - one voice per channel: voices 8 - N .. 7 (N channels); a voice another program took makes
;     the channel ask for any free one (SP_ANY);
;   - the Amiga period becomes Lau's pitch through a table: 3546894.6 Hz (the PAL Paula clock
;     7093789.2 / 2) / period * 16384 / 48000 = 1210673.29 / period;
;   - volume and pan: Lau's two volumes per voice (channels L R R L, a separation 0-64);
;   - loops: Lau starts a voice at position 0 and loops from LOOP to LEN, which is exactly a MOD
;     sample's "play to the loop end, then repeat the loop" (the part after the loop end is never
;     played, as in most players). A sample offset (9xx) into the loop is the one case Lau cannot
;     start directly (its loop start would lie before the start): the piece from the offset to
;     the loop end and then the loop are copied into a small buffer (mp_cbuf, 2 KB at most a
;     channel, MVN: about 1 ms) and played from there with its own loop; a longer one starts at
;     the loop start;
;   - pause: pitch 0 and volume 0 (the voices keep their place), resume writes them back.
; All routines a16 i16, DBR = the program's code bank; A, X, Y clobbered.

        .include "horizon.inc"

        .export mp_open, mp_play, mp_tick, mp_pause, mp_resume, mp_stop, mp_seek
        .export mp_setvol, mp_setsep
        .export mp_mod, mp_mlen, mp_cbuf, mp_loop, mp_meter, mp_keep
        .export mp_nch, mp_slen, mp_npat, mp_nsmp, mp_order, mp_row, mp_pat, mp_speed, mp_bpm
        .export mp_tickus, mp_tenths, mp_lev, mp_state, mp_tag

NCH     = 8
MPF_TEMPO = 1
MPF_END   = 2
MPE_FORMAT = $FE
MPS_STOP  = 0
MPS_PLAY  = 1
MPS_PAUSE = 2
CBUFW   = 1024                          ; words copied at most (2 KB; the buffers are 4 KB apart)

        .segment "ZEROPAGE"
mp_p:   .res    4                       ; the row: channels 0-3
mp_q:   .res    4                       ;   channels 4-7
mp_s:   .res    4                       ; a source
mp_d:   .res    4                       ; a destination
mp_cx:  .res    2                       ; the channel * 2
mp_t:   .res    2
mp_u:   .res    2
mp_ma:  .res    2                       ; mul16
mp_mb:  .res    4
mp_mr:  .res    4
mp_b0:  .res    2                       ; the 4 bytes of a channel's cell
mp_b1:  .res    2
mp_b2:  .res    2
mp_b3:  .res    2

        .segment "BSS"
; ---- inputs and the public state ----
mp_mod:   .res  4                       ; u24 the module
mp_mlen:  .res  4                       ; u24 its length
mp_cbuf:  .res  4                       ; u24 64 KB of scratch, 0 = none
mp_loop:  .res  2                       ; 1: at the song's end go on from the start
mp_meter: .res  2                       ; 1: compute mp_lev every tick
mp_keep:  .res  2                       ; sample_play flags added (SPF_KEEP)
mp_nch:   .res  2
mp_slen:  .res  2
mp_npat:  .res  2
mp_nsmp:  .res  2
mp_order: .res  2
mp_row:   .res  2
mp_pat:   .res  2
mp_speed: .res  2
mp_bpm:   .res  2
mp_tickus: .res 4                       ; u24 microseconds a tick
mp_tenths: .res 2                       ; time played, tenths of a second
mp_lev:   .res  NCH                     ; levels 0-64 (bytes)
mp_state: .res  2
mp_tag:   .res  4
; ---- the module ----
mp_rst:   .res  2                       ; restart order
mp_flt8:  .res  2
mp_ordp:  .res  4                       ; u24 the order table
mp_patp:  .res  4                       ; u24 the first pattern
mp_nch2:  .res  2                       ; channels * 2
mp_nch4:  .res  2                       ; bytes a row
mp_spt:   .res  2                       ; output samples a tick (meters)
mp_usacc: .res  4                       ; microseconds towards the next tenth
mp_tk:    .res  2                       ; the tick in the row
mp_rep:   .res  2                       ; 1: a repeat of the row (EEx)
mp_pdel:  .res  2                       ; repeats still to come
mp_jflag: .res  2                       ; Bxx / Dxx: a new order after this row
mp_jord:  .res  2                       ;   Bxx's order ($FFFF: the next one)
mp_brow:  .res  2                       ;   the row there
mp_lflag: .res  2                       ; E6x: back to mp_lrow in this order
mp_lrow:  .res  2
mp_lj:    .res  2
mp_wrap:  .res  2
mp_f00:   .res  2
mp_res:   .res  2                       ; mp_tick's result
mp_pitch: .res  2                       ; output: this channel's pitch, volumes
mp_vl:    .res  2
mp_vr:    .res  2
mp_mvol:  .res  2                       ; music volume 0-64
mp_sep:   .res  2                       ; separation 0-64
mp_blk:   .res  16                      ; sample_play's block
mp_lpw:   .res  2                       ;   its loop start (words), flags
mp_flg:   .res  2
mp_seen:  .res  1024                    ; rows played: order * 8 + row / 8, bit row & 7
vt_near:  .res  65 * 2                  ; Lau volume of the near side / far side by volume 0-64
vt_far:   .res  65 * 2
; ---- samples 1-31 (index * 2; lengths in words) ----
s_alo:  .res    64                      ; u24 address: low word
s_ahi:  .res    64                      ;   bank
s_len:  .res    64
s_lps:  .res    64                      ; loop start
s_lpl:  .res    64                      ; loop length (0: no loop)
s_lpe:  .res    64                      ; loop end
s_vol:  .res    64
s_ft:   .res    64
; ---- channels (index * 2) ----
c_smp:  .res    NCH*2                   ; its sample
c_vol:  .res    NCH*2
c_per:  .res    NCH*2                   ; its period
c_ft:   .res    NCH*2
c_note: .res    NCH*2
c_cmd:  .res    NCH*2
c_par:  .res    NCH*2
c_rnote: .res   NCH*2                   ; the period in this row's cell (0: none)
c_tgt:  .res    NCH*2                   ; tone portamento: the target, 0 = none
c_pspd: .res    NCH*2
c_vpos: .res    NCH*2
c_vspd: .res    NCH*2
c_vdep: .res    NCH*2
c_vwav: .res    NCH*2
c_tpos: .res    NCH*2
c_tspd: .res    NCH*2
c_tdep: .res    NCH*2
c_twav: .res    NCH*2
c_gls:  .res    NCH*2
c_offs: .res    NCH*2                   ; 9xx memory (words)
c_lrow: .res    NCH*2                   ; E6x
c_lcnt: .res    NCH*2
c_dly:  .res    NCH*2                   ; EDx: the tick of the delayed start, 0 = none
c_pout: .res    NCH*2                   ; to the hardware this tick: period, volume
c_vout: .res    NCH*2
c_trig: .res    NCH*2                   ; 1 start the sample (c_toff), 2 stop the voice
c_toff: .res    NCH*2
c_voice: .res   NCH*2
c_side: .res    NCH*2                   ; 0 left, 1 right
c_wp:   .res    NCH*2                   ; last written pitch, left, right ($FFFF: unknown)
c_wl:   .res    NCH*2
c_wr:   .res    NCH*2
c_mact: .res    NCH*2                   ; meter: the sample sounds
c_mpos: .res    NCH*2                   ;   where (words)
c_chz:  .res    0

        .segment "CODE"
        .a16
        .i16

; ---------------------------------------------------------------- open
; mp_mod, mp_mlen (, mp_cbuf) -> C clear, or C set with A = MPE_FORMAT
mp_open:
        stz     mp_state
        lda     #64
        sta     mp_mvol
        lda     #32
        sta     mp_sep
        jsr     vt_build
        lda     mp_mlen+2               ; at least the 15-sample header and one pattern
        and     #$00FF
        bne     :+
        lda     mp_mlen
        cmp     #600 + 1024
        jcc     @bad
:       lda     mp_mod
        sta     mp_p
        lda     mp_mod+2
        and     #$00FF
        sta     mp_p+2
        ldy     #1080
        lda     [mp_p],y
        sta     mp_tag
        iny
        iny
        lda     [mp_p],y
        sta     mp_tag+2
        stz     mp_flt8
        jsr     tag_chan
        sta     mp_nch
        cmp     #0
        beq     @m15
        lda     mp_mlen+2
        and     #$00FF
        bne     :+
        lda     mp_mlen
        cmp     #1084 + 256
        jcc     @bad
:       lda     #31
        sta     mp_nsmp
        lda     #950
        bra     @hdr
@m15:   lda     #4                      ; no tag: the old format, 15 samples, 4 channels
        sta     mp_nch
        stz     mp_tag
        stz     mp_tag+2
        lda     #15
        sta     mp_nsmp
        lda     #470
@hdr:   tay                             ; Y = the song length's offset
        lda     [mp_p],y
        and     #$00FF
        sta     mp_slen
        jeq     @bad
        cmp     #129
        jcs     @bad
        iny
        lda     [mp_p],y
        and     #$00FF
        sta     mp_rst
        iny                             ; the order table
        tya
        clc
        adc     mp_mod
        sta     mp_ordp
        lda     mp_mod+2
        and     #$00FF
        adc     #0
        sta     mp_ordp+2
        tya                             ; the patterns: 128 orders and the tag on
        clc
        adc     #128
        ldx     mp_nsmp
        cpx     #31
        bne     :+
        clc
        adc     #4
:       clc
        adc     mp_mod
        sta     mp_patp
        lda     mp_mod+2
        and     #$00FF
        adc     #0
        sta     mp_patp+2
        ; the highest pattern number of all 128 orders
        lda     mp_ordp
        sta     mp_s
        lda     mp_ordp+2
        sta     mp_s+2
        stz     mp_t
        ldy     #127
:       lda     [mp_s],y
        and     #$00FF
        cmp     mp_t
        bcc     :+
        sta     mp_t
:       dey
        bpl     :--
        lda     mp_t                    ; validate the order table: patterns below 128
        cmp     #128
        bcs     @bad
        lda     mp_nch
        asl     a
        sta     mp_nch2
        asl     a
        sta     mp_nch4
        lda     mp_flt8
        beq     @norm
        lda     mp_t                    ; FLT8: (highest | 1) + 1 blocks of 4 channels
        ora     #1
        inc     a
        sta     mp_u                    ; blocks
        lsr     a
        sta     mp_npat
        lda     mp_u                    ; bytes = blocks * 1024
        bra     @kb
@bad:   lda     #MPE_FORMAT
        sec
        rts
@norm:  lda     mp_t
        inc     a
        sta     mp_npat
        ; bytes = npat * nch * 256: npat * nch (up to 1024) * 256
        ldx     mp_nch
        lda     #0
:       clc
        adc     mp_npat
        dex
        bne     :-
        sta     mp_u                    ; npat * nch
        xba                             ; * 256 as u24: low word, bank part
        and     #$FF00
        sta     mp_s
        lda     mp_u
        xba
        and     #$00FF
        sta     mp_s+2
        bra     @samp
@kb:    asl     a                       ; blocks * 1024 = blocks * 4 * 256
        asl     a
        sta     mp_u
        xba
        and     #$FF00
        sta     mp_s
        lda     mp_u
        xba
        and     #$00FF
        sta     mp_s+2
@samp:  ; mp_d = the offset of the first sample from the module's start (u24)
        lda     mp_patp
        sec
        sbc     mp_mod
        clc
        adc     mp_s
        sta     mp_d
        lda     mp_s+2
        adc     #0
        sta     mp_d+2
        ; the sample table: header entries at 20 + 30 i
        ldx     #2                      ; sample 1
        lda     #20
        sta     mp_t                    ; header offset
@sl:    txa
        lsr     a
        cmp     mp_nsmp
        beq     :+
        bcc     :+
        jmp     @zero
:       ldy     mp_t
        iny
        iny
        iny
        iny
        iny
        iny
        iny
        iny
        iny
        iny
        iny
        iny
        iny
        iny
        iny
        iny
        iny
        iny
        iny
        iny
        iny
        iny                             ; +22 length (big-endian words)
        lda     [mp_p],y
        xba
        sta     s_len,x
        iny
        iny
        lda     [mp_p],y                ; +24 finetune, +25 volume
        pha
        and     #$000F
        sta     s_ft,x
        pla
        xba
        and     #$00FF
        cmp     #65
        bcc     :+
        lda     #64
:       sta     s_vol,x
        iny
        iny
        lda     [mp_p],y                ; +26 loop start
        xba
        sta     s_lps,x
        iny
        iny
        lda     [mp_p],y                ; +28 loop length
        xba
        sta     s_lpl,x
        ; its address: mp_mod + mp_d
        lda     mp_mod
        clc
        adc     mp_d
        sta     s_alo,x
        lda     mp_mod+2
        and     #$00FF
        adc     mp_d+2
        sta     s_ahi,x
        ; what is in memory of it: (mlen - d) / 2 words at most
        lda     mp_mlen
        sec
        sbc     mp_d
        sta     mp_u
        lda     mp_mlen+2
        and     #$00FF
        sbc     mp_d+2
        bcc     @none                   ; past the end
        bne     @fits                   ; >= 64 KB left: any length fits... unless > 128 KB
        lda     mp_u
        lsr     a
        cmp     s_len,x
        bcs     @fits
        sta     s_len,x                 ; cut
        bra     @fits
@none:  stz     s_len,x
@fits:  ; d += length * 2
        lda     s_len,x
        asl     a
        pha
        lda     #0
        rol     a
        sta     mp_u                    ; the high part
        pla
        clc
        adc     mp_d
        sta     mp_d
        lda     mp_d+2
        adc     mp_u
        sta     mp_d+2
        ; the loop: length > 1 word, inside the sample
        lda     s_lpl,x
        cmp     #2
        bcc     @noloop
        lda     s_lps,x
        cmp     s_len,x
        bcs     @noloop
        clc
        adc     s_lpl,x
        bcs     :+
        cmp     s_len,x
        bcc     :++
:       lda     s_len,x                 ; the loop runs past the end: cut it
        sec
        sbc     s_lps,x
        sta     s_lpl,x
        cmp     #2
        bcc     @noloop
:       lda     s_lps,x
        clc
        adc     s_lpl,x
        sta     s_lpe,x
        bra     @next
@noloop:
        stz     s_lpl,x
        lda     s_len,x
        sta     s_lpe,x
        bra     @next
@zero:  stz     s_len,x
        stz     s_lpl,x
        stz     s_lpe,x
        stz     s_vol,x
        stz     s_ft,x
@next:  lda     mp_t
        clc
        adc     #30
        sta     mp_t
        inx
        inx
        cpx     #64
        jcc     @sl
        lda     #125
        sta     mp_bpm
        lda     #6
        sta     mp_speed
        jsr     set_tempo
        clc
        rts

; the tag (mp_tag) -> A = channels (0: none, the old format), mp_flt8
tag_chan:
        ldx     #0
@l:     lda     tags,x
        beq     @x
        cmp     mp_tag
        bne     :+
        lda     tags+2,x
        cmp     mp_tag+2
        bne     :+
        lda     tags+4,x
        and     #$00FF
        cmp     #9
        bcc     @ok
        lda     #1
        sta     mp_flt8
        lda     #8
@ok:    rts
:       txa
        clc
        adc     #5
        tax
        bra     @l
@x:     lda     mp_tag+1                ; "nCHN", n = 1 .. 8
        cmp     #'C' | 'H' << 8
        bne     @no
        lda     mp_tag+3
        and     #$00FF
        cmp     #'N'
        bne     @no
        lda     mp_tag
        and     #$00FF
        sec
        sbc     #'1'
        cmp     #8
        bcs     @no
        inc     a
        rts
@no:    lda     #0
        rts

; mp_bpm -> mp_tickus = round(2500000 / bpm), mp_spt = round(120000 / bpm)
set_tempo:
        lda     mp_bpm
        sec
        sbc     #32
        bcs     :+
        lda     #0
:       cmp     #224
        bcc     :+
        lda     #223
:       sta     mp_t
        asl     a
        tax
        lda     spt_tab,x
        sta     mp_spt
        txa
        clc
        adc     mp_t                    ; * 3
        tax
        lda     us_tab,x
        sta     mp_tickus
        lda     us_tab+2,x
        and     #$00FF
        sta     mp_tickus+2
        rts

; ---------------------------------------------------------------- volume
; A = music volume 0-64
mp_setvol:
        cmp     #65
        bcc     :+
        lda     #64
:       sta     mp_mvol
        bra     vt_new
; A = separation 0-64
mp_setsep:
        cmp     #65
        bcc     :+
        lda     #64
:       sta     mp_sep
vt_new: jsr     vt_build
        ldx     #0                      ; written again at the next tick
        lda     #$FFFF
:       sta     c_wl,x
        inx
        inx
        cpx     #NCH*2
        bne     :-
        rts

; the tables: amp = vol * mvol / 16; near = 128 + 2 sep, far = 256 - near; Lau = amp * side / 256
vt_build:
        ldx     #0
        stz     mp_u                    ; vol * mvol
@l:     lda     mp_u
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     mp_t                    ; amp
        lda     mp_sep
        asl     a
        clc
        adc     #128
        jsr     @side
        sta     vt_near,x
        lda     mp_sep
        asl     a
        eor     #$FFFF
        sec
        adc     #128                    ; 128 - 2 sep
        jsr     @side
        sta     vt_far,x
        lda     mp_u
        clc
        adc     mp_mvol
        sta     mp_u
        inx
        inx
        cpx     #65 * 2
        bne     @l
        rts
@side:  sta     mp_mb
        stz     mp_mb+2
        lda     mp_t
        sta     mp_ma
        phx
        jsr     mul16
        plx
        lda     mp_mr+1
        cmp     #256
        bcc     :+
        lda     #255
:       rts

; mp_ma * mp_mb (u16 each; mp_mb+2 = 0) -> mp_mr (u32); mp_ma, mp_mb used up
mul16:  stz     mp_mr
        stz     mp_mr+2
        stz     mp_mb+2
@l:     lsr     mp_ma
        bcc     :+
        lda     mp_mr
        clc
        adc     mp_mb
        sta     mp_mr
        lda     mp_mr+2
        adc     mp_mb+2
        sta     mp_mr+2
:       lda     mp_ma
        beq     @x
        asl     mp_mb
        rol     mp_mb+2
        bra     @l
@x:     rts

; ---------------------------------------------------------------- play, stop, seek
; A = the first order -> A = mp_tick's flags | MPF_TEMPO (the first tick has run)
mp_play:
        cmp     mp_slen
        bcc     :+
        lda     #0
:       sta     mp_order
        jsr     mp_stop
        lda     #6
        sta     mp_speed
        lda     #125
        sta     mp_bpm
        jsr     set_tempo
        stz     mp_tenths
        stz     mp_usacc
        stz     mp_usacc+2
        ldx     #c_chz - c_smp - 2      ; every channel variable 0
:       stz     c_smp,x
        dex
        dex
        bpl     :-
        ldx     #0                      ; voices 8 - N .. 7, sides L R R L, nothing written
        lda     #8
        sec
        sbc     mp_nch
        sta     mp_t
@ch:    lda     mp_t
        sta     c_voice,x
        inc     mp_t
        txa
        lsr     a
        inc     a
        and     #2                      ; channel c: (c + 1) & 2 -> 0 for 0, 3 (L), 2 for 1, 2 (R)
        lsr     a
        sta     c_side,x
        lda     #$FFFF
        sta     c_wp,x
        sta     c_wl,x
        sta     c_wr,x
        inx
        inx
        cpx     #NCH*2
        bne     @ch
        jsr     seen_clr
        stz     mp_row
        jsr     newpos
        jsr     seen_mark
        lda     #MPS_PLAY
        sta     mp_state
        jsr     mp_tick
        ora     #MPF_TEMPO
        rts

; every voice of the music stops; the song stays where it is
mp_stop:
        stz     mp_state
        ldx     #0
:       stx     mp_cx
        jsr     v_stop
        ldx     mp_cx
        stz     c_mact,x
        inx
        inx
        cpx     mp_nch2
        bcc     :-
        jsr     lev_clr
        stz     mp_tk
        stz     mp_rep
        stz     mp_pdel
        stz     mp_jflag
        stz     mp_lflag
        stz     mp_f00
        lda     #$FFFF
        sta     mp_jord
        rts

; X = channel * 2: its voice stops (once it started one)
v_stop: lda     c_wp,x
        cmp     #$FFFF
        beq     :+
        lda     #$FFFF
        sta     c_wp,x
        sta     c_wl,x
        lda     c_voice,x
        sys     SYS_SSTOP
:       rts

lev_clr:
        ldx     #NCH - 2
:       stz     mp_lev,x
        dex
        dex
        bpl     :-
        rts

; A = order: playing goes on from its row 0 (the voices stop)
mp_seek:
        cmp     mp_slen
        bcc     :+
        lda     #0
:       pha
        lda     mp_state
        pha
        jsr     mp_stop
        pla
        sta     mp_state
        pla
        sta     mp_order
        stz     mp_row
        jsr     seen_clr
        lda     mp_order                ; the orders before it count as played: a jump back
        asl     a                       ; to one of them is the song's end, as when played
        asl     a                       ; from the start
        asl     a
        tax
        lda     #$FFFF
        bra     :++
:       dex
        dex
        sta     mp_seen,x
:       cpx     #0
        bne     :--
        jsr     newpos
        jmp     seen_mark

; pause: every voice holds (pitch 0, volume 0)
mp_pause:
        lda     mp_state
        cmp     #MPS_PLAY
        bne     @x
        lda     #MPS_PAUSE
        sta     mp_state
        ldx     #0
:       stx     mp_cx
        lda     c_wp,x
        cmp     #$FFFF
        beq     :+
        lda     #$FFFF
        sta     c_wl,x                  ; written again at resume
        lda     c_voice,x
        ldx     #0
        ldy     #0
        sys     SYS_SSET
:       ldx     mp_cx
        inx
        inx
        cpx     mp_nch2
        bcc     :--
        jsr     lev_clr
@x:     rts

; resume: the voices get their pitch and volume back at once
mp_resume:
        lda     mp_state
        cmp     #MPS_PAUSE
        bne     :+
        lda     #MPS_PLAY
        sta     mp_state
        jmp     output
:       rts

; ---------------------------------------------------------------- positions
; mp_order, mp_row -> mp_pat, mp_p, mp_q
newpos: lda     mp_ordp
        sta     mp_s
        lda     mp_ordp+2
        sta     mp_s+2
        ldy     mp_order
        lda     [mp_s],y
        and     #$00FF
        sta     mp_pat
        lda     mp_flt8
        bne     @f8
        ldx     mp_nch                  ; pattern * nch * 256 + row * nch * 4
        lda     #0
:       clc
        adc     mp_pat
        dex
        bne     :-
        sta     mp_u
        xba
        and     #$FF00
        sta     mp_t
        lda     mp_u
        xba
        and     #$00FF
        sta     mp_u                    ; mp_u:mp_t = pattern offset
        ldx     mp_row
        lda     #0
        cpx     #0
        beq     @add
:       clc
        adc     mp_nch4
        dex
        bne     :-
@add:   clc
        adc     mp_t
        sta     mp_t
        lda     mp_u
        adc     #0
        sta     mp_u
        lda     #16                     ; channels 4-7 follow 0-3 in the row
        bra     @set
@f8:    lda     mp_pat                  ; (pattern & ~1) * 1024 + row * 16
        and     #$FFFE
        asl     a
        asl     a                       ; * 4: as * 256 below
        sta     mp_u
        xba
        and     #$FF00
        sta     mp_t
        lda     mp_u
        xba
        and     #$00FF
        sta     mp_u
        lda     mp_row
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     mp_t
        sta     mp_t
        lda     mp_u
        adc     #0
        sta     mp_u
        lsr     mp_pat                  ; the 8-channel pattern's number
        lda     #1024
@set:   pha
        lda     mp_patp
        clc
        adc     mp_t
        sta     mp_p
        lda     mp_patp+2
        adc     mp_u
        sta     mp_p+2
        pla
        clc
        adc     mp_p
        sta     mp_q
        lda     mp_p+2
        adc     #0
        sta     mp_q+2
        rts

seen_clr:
        ldx     #1022
:       stz     mp_seen,x
        dex
        dex
        bpl     :-
        rts

; Y = the byte of (mp_order, A = row), A = its bit
seen_at:
        pha
        lda     mp_order
        asl     a
        asl     a
        asl     a
        sta     mp_t
        pla
        pha
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     mp_t
        tay
        pla
        and     #7
        tax
        lda     bits,x
        and     #$00FF
        rts

seen_mark:
        lda     mp_row
        jsr     seen_at
        sep     #$20
        .a8
        ora     mp_seen,y
        sta     mp_seen,y
        rep     #$20
        .a16
        rts

; ---------------------------------------------------------------- the tick
; -> A = MPF_* flags
mp_tick:
        stz     mp_res
        lda     mp_state
        cmp     #MPS_PLAY
        beq     :+
        lda     #0
        rts
:       lda     mp_tk
        ora     mp_rep
        bne     @eff
        jsr     read_row
        bra     @out
@eff:   ldx     #0
:       stx     mp_cx
        jsr     ch_tick
        ldx     mp_cx
        inx
        inx
        cpx     mp_nch2
        bcc     :-
@out:   jsr     output
        lda     mp_meter                ; the meters: every second tick (25 a second at 125 BPM)
        beq     :+
        eor     #$8000
        sta     mp_meter
        bmi     :+
        jsr     meters
:       lda     mp_usacc                ; the time
        clc
        adc     mp_tickus
        sta     mp_usacc
        lda     mp_usacc+2
        adc     mp_tickus+2
        sta     mp_usacc+2
        cmp     #^100000
        bcc     @adv
        bne     :+
        lda     mp_usacc
        cmp     #.loword(100000)
        bcc     @adv
:       lda     mp_usacc
        sec
        sbc     #.loword(100000)
        sta     mp_usacc
        lda     mp_usacc+2
        sbc     #^100000
        sta     mp_usacc+2
        inc     mp_tenths
@adv:   lda     mp_f00                  ; F00: the end
        beq     :+
        stz     mp_f00
        stz     mp_tk
        jmp     song_end0
:       inc     mp_tk
        lda     mp_tk
        cmp     mp_speed
        bcc     :+
        stz     mp_tk
        jsr     next_row
:       lda     mp_res
        rts

; after the row's last tick: the next row (EEx repeats, E6x loops, Bxx, Dxx, the song's end)
next_row:
        lda     mp_pdel
        beq     :+
        dec     mp_pdel
        lda     #1
        sta     mp_rep
        rts
:       stz     mp_rep
        stz     mp_lj
        stz     mp_wrap
        lda     mp_lflag
        beq     @nol
        stz     mp_lflag                ; E6x: back to the loop row, the rows since then unplayed
        stz     mp_jflag
        lda     #$FFFF
        sta     mp_jord
:       lda     mp_row
        jsr     seen_at
        eor     #$FFFF
        sep     #$20
        .a8
        and     mp_seen,y
        sta     mp_seen,y
        rep     #$20
        .a16
        lda     mp_row
        cmp     mp_lrow
        beq     :+
        bcc     :+
        dec     mp_row
        bra     :-
:       lda     mp_lrow
        sta     mp_row
        inc     mp_lj
        bra     @set
@nol:   lda     mp_jflag
        beq     @inc
        stz     mp_jflag
        lda     mp_brow
        sta     mp_row
        stz     mp_brow
        lda     mp_jord
        bmi     @nx
        sta     mp_order
        lda     #$FFFF
        sta     mp_jord
        bra     @chk
@nx:    inc     mp_order
        bra     @chk
@inc:   inc     mp_row
        lda     mp_row
        cmp     #64
        bcc     @set
        stz     mp_row
        inc     mp_order
@chk:   lda     mp_order
        cmp     mp_slen
        bcc     @set
        lda     mp_rst                  ; past the last order: the restart position
        cmp     mp_slen
        bcc     :+
        lda     #0
:       sta     mp_order
        inc     mp_wrap
@set:   lda     mp_lj
        bne     @mark
        lda     mp_wrap
        bne     song_end
        lda     mp_row
        jsr     seen_at
        and     mp_seen,y
        bne     song_end
@mark:  jsr     newpos
        jmp     seen_mark

; the song is at its end (a row played again, or past the end): stop, or go on from there
song_end:
        lda     mp_res
        ora     #MPF_END
        sta     mp_res
        lda     mp_loop
        bne     :+
        stz     mp_state                ; (the voices ring on: the program stops them, mp_stop)
        rts
:       jsr     seen_clr
        jsr     newpos
        jmp     seen_mark
; F00: the same, from the restart position
song_end0:
        lda     mp_rst
        cmp     mp_slen
        bcc     :+
        lda     #0
:       sta     mp_order
        stz     mp_row
        stz     mp_rep
        stz     mp_pdel
        stz     mp_jflag
        stz     mp_lflag
        jsr     song_end
        lda     mp_res
        rts

; ---------------------------------------------------------------- tick 0: a new row
read_row:
        ldx     #0
@l:     stx     mp_cx
        txa
        asl     a                       ; channel * 4
        cmp     #16
        bcs     @hi
        tay
        lda     [mp_p],y
        sta     mp_b0
        iny
        iny
        lda     [mp_p],y
        bra     @got
@hi:    sec
        sbc     #16
        tay
        lda     [mp_q],y
        sta     mp_b0
        iny
        iny
        lda     [mp_q],y
@got:   pha
        and     #$00FF
        sta     mp_b2
        pla
        xba
        and     #$00FF
        sta     mp_b3
        lda     mp_b0
        xba
        and     #$00FF
        sta     mp_b1
        lda     mp_b0
        and     #$00FF
        sta     mp_b0
        jsr     ch_row
        ldx     mp_cx
        inx
        inx
        cpx     mp_nch2
        bcc     @l
        rts

; X = channel * 2, mp_b0..b3 its cell
ch_row: lda     mp_b0                   ; the period
        and     #$000F
        xba
        ora     mp_b1
        sta     c_rnote,x
        lda     mp_b2                   ; the effect
        and     #$000F
        sta     c_cmd,x
        lda     mp_b3
        sta     c_par,x
        lda     mp_b2                   ; the sample number
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     mp_t
        lda     mp_b0
        and     #$00F0
        ora     mp_t
        beq     @nos
        cmp     mp_nsmp
        beq     :+
        bcs     @nos
:       sta     c_smp,x
        asl     a
        tay
        lda     s_vol,y
        sta     c_vol,x
        lda     s_ft,y
        sta     c_ft,x
@nos:   stz     c_dly,x
        lda     c_cmd,x                 ; 9xx: its memory first
        cmp     #9
        bne     :+
        lda     c_par,x
        beq     :+
        xba
        lsr     a                       ; * 128 words = * 256 bytes
        sta     c_offs,x
:       lda     c_rnote,x
        jeq     eff0
        lda     c_cmd,x                 ; E5x: the finetune for this note
        cmp     #$0E
        bne     :+
        lda     c_par,x
        and     #$00F0
        cmp     #$0050
        bne     :+
        lda     c_par,x
        and     #$000F
        sta     c_ft,x
:       lda     c_rnote,x
        ldy     #0
        jsr     ft_index
        sta     c_note,x
        jsr     ft_per
        ldy     c_cmd,x
        cpy     #3
        beq     @tp
        cpy     #5
        beq     @tp
        sta     c_per,x
        cpy     #$0E                    ; EDx, x > 0: the start comes later
        bne     @trig
        lda     c_par,x
        and     #$00F0
        cmp     #$00D0
        bne     @trig
        lda     c_par,x
        and     #$000F
        beq     @trig
        sta     c_dly,x
        jmp     eff0
@trig:  lda     c_vwav,x
        and     #4
        bne     :+
        stz     c_vpos,x
:       lda     c_twav,x
        and     #4
        bne     :+
        stz     c_tpos,x
:       lda     #0
        cpy     #9
        bne     :+
        lda     c_offs,x
:       jsr     trigger
        jmp     eff0
@tp:    cmp     c_per,x                 ; tone portamento: only the target
        bne     :+
        lda     #0
:       sta     c_tgt,x
        jmp     eff0

; X = channel * 2, A = offset in words: the sample starts at this tick's output
trigger:
        sta     c_toff,x
        lda     c_smp,x
        asl     a
        tay
        lda     s_len,y
        beq     @stop
        lda     #1
        sta     c_trig,x
        lda     c_toff,x
        sta     c_mpos,x
        lda     #1
        sta     c_mact,x
        rts
@stop:  lda     #2
        sta     c_trig,x
        stz     c_mact,x
        rts

; tick 0 effects of the new row (PT's CheckMoreEfx), then this tick's output values
eff0:   lda     c_cmd,x
        cmp     #$0B
        bne     @d
        lda     c_par,x
        sta     mp_jord
        stz     mp_brow
        lda     #1
        sta     mp_jflag
        bra     @out
@d:     cmp     #$0D
        bne     @c
        lda     c_par,x
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     mp_t                    ; tens * 10
        asl     a
        asl     a
        clc
        adc     mp_t
        asl     a
        sta     mp_t
        lda     c_par,x
        and     #$000F
        clc
        adc     mp_t
        cmp     #64
        bcc     :+
        lda     #0
:       sta     mp_brow
        lda     #1
        sta     mp_jflag
        bra     @out
@c:     cmp     #$0C
        bne     @f
        lda     c_par,x
        cmp     #65
        bcc     :+
        lda     #64
:       sta     c_vol,x
        bra     @out
@f:     cmp     #$0F
        bne     @e
        lda     c_par,x
        bne     :+
        lda     #1
        sta     mp_f00
        bra     @out
:       cmp     #32
        bcs     :+
        sta     mp_speed
        bra     @out
:       sta     mp_bpm
        jsr     set_tempo
        ldx     mp_cx
        lda     mp_res
        ora     #MPF_TEMPO
        sta     mp_res
        bra     @out
@e:     cmp     #$0E
        bne     @out
        jsr     ecmd
@out:   ldx     mp_cx
        lda     c_per,x
        sta     c_pout,x
        lda     c_vol,x
        sta     c_vout,x
        rts

; E commands (X = channel * 2), at any tick (mp_tk; on a repeat of the row only some of them)
ecmd:   lda     c_par,x
        and     #$000F
        sta     mp_u                    ; x
        lda     c_par,x
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        asl     a                       ; sub * 2
        tay
        lda     etab,y
        sta     mp_t
        jmp     (mp_t)

etab:   .word   e_nop, e_fup, e_fdn, e_gls, e_vwav, e_ft, e_loop, e_twav
        .word   e_nop, e_rtg, e_fvu, e_fvd, e_cut, e_dly, e_pdel, e_nop

; tick 0 only (new rows and repeats)
e_fup:  lda     mp_tk
        bne     e_nop
        lda     c_per,x
        beq     e_nop
        sec
        sbc     mp_u
        jmp     clamp_lo
e_fdn:  lda     mp_tk
        bne     e_nop
        lda     c_per,x
        beq     e_nop
        clc
        adc     mp_u
        jmp     clamp_hi
e_fvu:  lda     mp_tk
        bne     e_nop
        lda     c_vol,x
        clc
        adc     mp_u
        cmp     #65
        bcc     :+
        lda     #64
:       sta     c_vol,x
e_nop:  rts
e_fvd:  lda     mp_tk
        bne     e_nop
        lda     c_vol,x
        sec
        sbc     mp_u
        bcs     :+
        lda     #0
:       sta     c_vol,x
        rts
; new rows only
e_gls:  lda     mp_rep
        ora     mp_tk
        bne     e_nop
        lda     mp_u
        sta     c_gls,x
        rts
e_vwav: lda     mp_rep
        ora     mp_tk
        bne     e_nop
        lda     mp_u
        sta     c_vwav,x
        rts
e_twav: lda     mp_rep
        ora     mp_tk
        bne     e_nop
        lda     mp_u
        sta     c_twav,x
        rts
e_ft:   lda     mp_rep
        ora     mp_tk
        bne     e_nop
        lda     mp_u
        sta     c_ft,x
        rts
e_loop: lda     mp_rep
        ora     mp_tk
        bne     e_nop
        lda     mp_u
        bne     :+
        lda     mp_row                  ; E60: the loop row
        sta     c_lrow,x
        rts
:       lda     c_lcnt,x
        bne     :+
        lda     mp_u                    ; first time: x more
        sta     c_lcnt,x
        bra     @jmp
:       dec     c_lcnt,x
        beq     e_nop2
@jmp:   lda     c_lrow,x
        sta     mp_lrow
        lda     #1
        sta     mp_lflag
e_nop2: rts
e_pdel: lda     mp_rep
        ora     mp_tk
        bne     e_nop2
        lda     mp_u
        sta     mp_pdel
        rts
; any tick
e_rtg:  lda     mp_u
        beq     e_nop2
        lda     mp_tk
        bne     :+
        lda     c_rnote,x               ; tick 0 with a note: it started anyway
        bne     e_nop2
        lda     #0
        jmp     trigger
:       sec                             ; tick % x
:       sbc     mp_u
        bcs     :-
        adc     mp_u
        bne     e_nop2
        jmp     trigger                 ; (A = 0: offset 0)
e_cut:  lda     mp_tk
        cmp     mp_u
        bne     e_nop2
        stz     c_vol,x
        rts
e_dly:  lda     c_dly,x
        beq     e_nop2
        cmp     mp_tk
        bne     e_nop2
        stz     c_dly,x
        lda     #0
        jmp     trigger

; A = period: limited to 113 (as a slide up does; A may have gone below 0)
clamp_lo:
        bmi     :+
        cmp     #113
        bcs     :++
:       lda     #113
:       sta     c_per,x
        rts
clamp_hi:
        cmp     #857
        bcc     :+
        lda     #856
:       sta     c_per,x
        rts

; ---------------------------------------------------------------- ticks > 0 (and EEx repeats)
ch_tick:
        lda     c_per,x
        sta     c_pout,x
        lda     c_vol,x
        sta     c_vout,x
        lda     c_cmd,x
        asl     a
        tax
        jmp     (ttab,x)

ttab:   .word   t_arp, t_up, t_down, t_porta, t_vib, t_portvol, t_vibvol, t_trem
        .word   t_nop, t_nop, t_vol, t_nop, t_nop, t_nop, t_e, t_nop

t_e:    ldx     mp_cx
        jsr     ecmd
        ldx     mp_cx
        lda     c_per,x                 ; (a fine slide changed them)
        sta     c_pout,x
        lda     c_vol,x
        sta     c_vout,x
t_nop:  rts

t_arp:  ldx     mp_cx
        lda     c_par,x
        beq     t_nop
        lda     mp_tk                   ; tick % 3
:       sec
        sbc     #3
        bcs     :-
        adc     #3
        beq     t_nop
        cmp     #1
        bne     :+
        lda     c_par,x
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        bra     :++
:       lda     c_par,x
        and     #$000F
:       sta     mp_u
        lda     c_per,x
        ldy     c_ft,x
        jsr     ft_index_y
        clc
        adc     mp_u
        cmp     #36
        bcc     :+
        lda     #35
:       jsr     ft_per
        sta     c_pout,x
        rts

t_up:   ldx     mp_cx
        lda     c_per,x
        beq     t_nop
        sec
        sbc     c_par,x
        jsr     clamp_lo
        sta     c_pout,x
        rts
t_down: ldx     mp_cx
        lda     c_per,x
        beq     t_nop2
        clc
        adc     c_par,x
        jsr     clamp_hi
        sta     c_pout,x
t_nop2: rts

t_porta:
        ldx     mp_cx
        lda     c_par,x
        beq     porta
        sta     c_pspd,x
porta:  lda     c_tgt,x
        beq     @x
        lda     c_per,x
        cmp     c_tgt,x
        beq     @x
        bcs     @dn
        clc                             ; up to the target (a lower note)
        adc     c_pspd,x
        cmp     c_tgt,x
        bcc     @set
        bra     @at
@dn:    sec
        sbc     c_pspd,x
        bcc     @at
        cmp     c_tgt,x
        beq     @at
        bcs     @set
@at:    lda     c_tgt,x
        stz     c_tgt,x
@set:   sta     c_per,x
        sta     c_pout,x
        lda     c_gls,x
        beq     @x
        lda     c_per,x                 ; glissando: the note at or above
        ldy     c_ft,x
        jsr     ft_index_y
        jsr     ft_per
        sta     c_pout,x
@x:     rts

t_vib:  ldx     mp_cx
        lda     c_par,x
        and     #$000F
        beq     :+
        sta     c_vdep,x
:       lda     c_par,x
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        beq     vib
        sta     c_vspd,x
vib:    lda     c_vpos,x
        ldy     c_vwav,x
        jsr     wave
        ldy     c_vdep,x
        jsr     depth                   ; A = value * depth
        lsr     a                       ; >> 7
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     mp_u
        lda     c_vpos,x
        cmp     #32
        lda     c_per,x
        bcs     :+
        clc
        adc     mp_u
        bra     :++
:       sec
        sbc     mp_u
:       sta     c_pout,x
        lda     c_vpos,x
        clc
        adc     c_vspd,x
        and     #63
        sta     c_vpos,x
        rts

t_trem: ldx     mp_cx
        lda     c_par,x
        and     #$000F
        beq     :+
        sta     c_tdep,x
:       lda     c_par,x
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        beq     :+
        sta     c_tspd,x
:       lda     c_tpos,x
        ldy     c_twav,x
        jsr     wave
        ldy     c_tdep,x
        jsr     depth
        lsr     a                       ; >> 6
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     mp_u
        lda     c_tpos,x
        cmp     #32
        lda     c_vol,x
        bcs     :+
        clc
        adc     mp_u
        cmp     #65
        bcc     :++
        lda     #64
        bra     :++
:       sec
        sbc     mp_u
        bcs     :+
        lda     #0
:       sta     c_vout,x
        lda     c_tpos,x
        clc
        adc     c_tspd,x
        and     #63
        sta     c_tpos,x
        rts

t_portvol:
        ldx     mp_cx
        jsr     porta
        bra     volslide
t_vibvol:
        ldx     mp_cx
        jsr     vib
        bra     volslide
t_vol:  ldx     mp_cx
volslide:
        lda     c_par,x
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        beq     @dn
        clc
        adc     c_vol,x
        cmp     #65
        bcc     @set
        lda     #64
        bra     @set
@dn:    lda     c_par,x
        and     #$000F
        sta     mp_u
        lda     c_vol,x
        sec
        sbc     mp_u
        bcs     @set
        lda     #0
@set:   sta     c_vol,x
        sta     c_vout,x
        rts

; A = pos 0-63, Y = waveform -> A = 0-255
wave:   sta     mp_t
        tya
        and     #3
        cmp     #1
        beq     @ramp
        cmp     #2
        beq     @sq
        lda     mp_t                    ; sine (3, random: sine too)
        and     #31
        tay
        lda     sine,y
        and     #$00FF
        rts
@ramp:  lda     mp_t
        and     #31
        asl     a
        asl     a
        asl     a
        ldy     mp_t
        cpy     #32
        bcc     :+
        eor     #$00FF                  ; 255 - v
:       rts
@sq:    lda     #255
        rts

; A = value 0-255, Y = depth 0-15 -> A = value * depth
depth:  sta     mp_t
        lda     #0
        cpy     #0
        beq     @x
:       clc
        adc     mp_t
        dey
        bne     :-
@x:     rts

; ---------------------------------------------------------------- period tables
; A = period, Y = 0: the finetune-0 table -> A = the first note index whose period is <= A (35)
ft_index:
        ldy     #0
; A = period, Y = finetune
ft_index_y:
        sta     mp_t
        tya
        asl     a
        tay
        lda     ft_off,y
        tay
        phx
        ldx     #0
:       lda     ft_tab,y
        cmp     mp_t
        beq     @f
        bcc     @f
        iny
        iny
        inx
        cpx     #35
        bcc     :-
@f:     txa
        plx
        rts

; A = note index 0-35, X = channel * 2 -> A = the period in the channel's finetune table
ft_per: asl     a
        sta     mp_t
        lda     c_ft,x
        asl     a
        tay
        lda     ft_off,y
        clc
        adc     mp_t
        tay
        lda     ft_tab,y
        rts

; ---------------------------------------------------------------- output to Lau
output: ldx     #0
@l:     stx     mp_cx
        lda     c_pout,x                ; the pitch
        cmp     #1024
        bcc     :+
        lda     #1023
:       asl     a
        tay
        lda     pitch_tab,y
        sta     mp_pitch
        lda     c_vout,x                ; the volumes
        asl     a
        tay
        lda     c_side,x
        bne     @r
        lda     vt_near,y
        sta     mp_vl
        lda     vt_far,y
        sta     mp_vr
        bra     @v
@r:     lda     vt_far,y
        sta     mp_vl
        lda     vt_near,y
        sta     mp_vr
@v:     lda     c_trig,x
        beq     @set
        stz     c_trig,x
        cmp     #1
        beq     @play
        jsr     v_stop
        bra     @n
@play:  jsr     ch_play
        bra     @n
@set:   lda     c_wp,x                  ; nothing started: write what changed
        cmp     #$FFFF
        beq     @n                      ; (no voice of ours yet, or stopped)
        lda     mp_pitch
        cmp     c_wp,x
        bne     :+
        lda     mp_vl
        cmp     c_wl,x
        bne     :+
        lda     mp_vr
        cmp     c_wr,x
        beq     @n
:       lda     mp_pitch
        sta     c_wp,x
        lda     mp_vl
        sta     c_wl,x
        lda     mp_vr
        sta     c_wr,x
        xba
        ora     mp_vl
        tay
        lda     c_voice,x
        ldx     mp_pitch
        sys     SYS_SSET
@n:     ldx     mp_cx
        inx
        inx
        cpx     mp_nch2
        jcc     @l
        rts

; X = channel * 2: start its sample (c_smp, c_toff words) with mp_pitch, mp_vl, mp_vr
ch_play:
        lda     c_smp,x
        asl     a
        tay
        lda     c_toff,x
        sta     mp_u                    ; o
        lda     s_lpl,y
        beq     @one
        lda     mp_u                    ; looped
        cmp     s_lpe,y
        bcs     @atl
        cmp     s_lps,y
        beq     @bef
        bcc     @bef
        ; inside the loop: [o, end) then the loop, copied (4 KB at most)
        lda     s_lpe,y
        sec
        sbc     mp_u
        sta     mp_t                    ; words to the end
        clc
        adc     s_lpl,y
        cmp     #CBUFW + 1
        bcs     @atl
        lda     mp_cbuf+2
        and     #$00FF
        ora     mp_cbuf
        beq     @atl
        jmp     ch_copy
@atl:   lda     s_lps,y                 ; the loop alone
        sta     mp_u
        lda     s_lpl,y
        sta     mp_t
        lda     #0
        bra     @lp
@bef:   lda     s_lpe,y                 ; from o: to the loop end, the loop from loop start - o
        sec
        sbc     mp_u
        sta     mp_t
        lda     s_lps,y
        sec
        sbc     mp_u
@lp:    sta     mp_lpw
        lda     #SPF_LOOP
        bra     @go
@one:   lda     mp_u
        cmp     s_len,y
        bcc     :+
        jmp     v_stop                  ; past the end: silence
:       lda     s_len,y
        sec
        sbc     mp_u
        sta     mp_t
        stz     mp_lpw
        lda     #0
@go:    ora     mp_keep
        sta     mp_flg
        lda     mp_u                    ; the address: sample + o * 2
        jsr     w2s
        clc
        adc     s_alo,y
        sta     mp_blk
        lda     mp_s
        adc     s_ahi,y
        sep     #$20
        .a8
        sta     mp_blk+2
        rep     #$20
        .a16
        lda     mp_t                    ; the length
        jsr     w2s
        sta     mp_blk+3
        lda     mp_s
        sep     #$20
        .a8
        sta     mp_blk+5
        rep     #$20
        .a16
        lda     mp_lpw                  ; the loop start
        jsr     w2s
        sta     mp_blk+6
        lda     mp_s
        sep     #$20
        .a8
        sta     mp_blk+8
        lda     mp_flg
        sta     mp_blk+13
        rep     #$20
        .a16
; the rest of the block and the call (mp_blk 0-8 and 13 set)
ch_go:  lda     mp_pitch
        sta     mp_blk+9
        sep     #$20
        .a8
        lda     mp_vl
        sta     mp_blk+11
        lda     mp_vr
        sta     mp_blk+12
        lda     c_voice,x
        sta     mp_blk+14
        stz     mp_blk+15
        rep     #$20
        .a16
        ldx     #.loword(mp_blk)
        ldy     #^mp_blk
        sys     SYS_SPLAY
        bcc     @ok
        cmp     #EAGAIN                 ; its voice is another program's: any free one
        bne     @fail
        sep     #$20
        .a8
        lda     #SP_ANY
        sta     mp_blk+14
        rep     #$20
        .a16
        ldx     #.loword(mp_blk)
        ldy     #^mp_blk
        sys     SYS_SPLAY
        bcs     @fail
@ok:    ldx     mp_cx
        sta     c_voice,x
        lda     mp_pitch
        sta     c_wp,x
        lda     mp_vl
        sta     c_wl,x
        lda     mp_vr
        sta     c_wr,x
        rts
@fail:  ldx     mp_cx
        stz     c_mact,x
        rts

; A = words -> A = samples low word, mp_s = the high part (0 or 1); keeps X, Y
w2s:    asl     a
        pha
        lda     #0
        rol     a
        sta     mp_s
        pla
        rts

; the offset lies inside the loop: copy [o, end) and the loop into the channel's buffer
; (X = channel * 2, Y = sample * 2, mp_u = o, mp_t = words to the end)
ch_copy:
        lda     mp_cx                   ; the buffer: mp_cbuf + channel * 4096
        xba
        asl     a
        asl     a
        asl     a                       ; cx * 2048
        clc
        adc     mp_cbuf
        sta     mp_d
        sta     mp_blk
        lda     mp_cbuf+2
        and     #$00FF
        adc     #0
        sta     mp_d+2
        sep     #$20
        .a8
        sta     mp_blk+2
        rep     #$20
        .a16
        lda     mp_u                    ; from sample + o * 2: to the loop end
        jsr     w2s
        clc
        adc     s_alo,y
        pha
        lda     mp_s
        adc     s_ahi,y
        sta     mp_s+2
        pla
        sta     mp_s
        phy
        lda     mp_t
        jsr     cpw
        ply
        lda     mp_t                    ; then the loop from its start
        asl     a
        clc
        adc     mp_d
        sta     mp_d
        lda     mp_d+2
        adc     #0
        sta     mp_d+2
        lda     s_lps,y
        jsr     w2s
        clc
        adc     s_alo,y
        pha
        lda     mp_s
        adc     s_ahi,y
        sta     mp_s+2
        pla
        sta     mp_s
        phy
        lda     s_lpl,y
        jsr     cpw
        ply
        lda     mp_t                    ; LEN = to the end + the loop, LOOP = to the end
        clc
        adc     s_lpl,y
        asl     a
        sta     mp_blk+3
        lda     mp_t
        asl     a
        sta     mp_blk+6
        sep     #$20
        .a8
        stz     mp_blk+5
        stz     mp_blk+8
        lda     #SPF_LOOP
        ora     mp_keep
        sta     mp_blk+13
        rep     #$20
        .a16
        ldx     mp_cx
        jmp     ch_go

; A = words: [mp_s] -> [mp_d]: MVN when neither side crosses a bank, else word by word
cpw:    asl     a
        beq     @x
        sta     mp_u
        dec     a                       ; neither range crosses its bank's end?
        clc
        adc     mp_s
        bcs     @slow
        lda     mp_u
        dec     a
        clc
        adc     mp_d
        bcs     @slow
        sep     #$20
        .a8
        lda     mp_s+2
        sta     @mv+2                   ; MVN dst, src: the banks are its operands
        lda     mp_d+2
        sta     @mv+1
        rep     #$20
        .a16
        phb
        lda     mp_u
        dec     a
        ldx     mp_s
        ldy     mp_d
@mv:    .byte   $54, 0, 0               ; mvn (patched)
        plb
        ldx     mp_cx
        rts
@slow:  ldy     #0
:       lda     [mp_s],y
        sta     [mp_d],y
        iny
        iny
        cpy     mp_u
        bcc     :-
@x:     rts

; ---------------------------------------------------------------- level meters
; per channel: where its sample is now (pitch * output samples a tick), the larger of two of its
; bytes there, times its volume
meters: ldx     #0
@l:     stx     mp_cx
        lda     c_mact,x
        jeq     @zero
        lda     c_wp,x
        cmp     #$FFFF
        beq     @zero
        sta     mp_mb
        lda     mp_spt                  ; (two ticks: the meters run every second one)
        asl     a
        sta     mp_ma
        jsr     mul16                   ; samples moved = pitch * spt / 16384; words: / 32768
        lda     mp_mr+2
        asl     a
        sta     mp_t
        lda     mp_mr
        asl     a
        lda     #0
        rol     a
        ora     mp_t
        sta     mp_t                    ; words moved this tick
        ldx     mp_cx
        lda     c_smp,x
        asl     a
        tay
        lda     c_mpos,x
        clc
        adc     mp_t
        bcs     @end
        sta     c_mpos,x
        cmp     s_lpe,y
        bcc     @pk
        lda     s_lpl,y                 ; past the loop end (or the end)
        beq     @end
:       lda     c_mpos,x
        sec
        sbc     s_lpl,y
        sta     c_mpos,x
        cmp     s_lpe,y
        bcs     :-
@pk:    lda     c_mpos,x                ; its bytes at the place and half a tick on
        jsr     @peek
        sta     mp_u
        lsr     mp_t
        lda     c_mpos,x
        clc
        adc     mp_t
        bcs     :+
        cmp     s_len,y
        bcs     :+
        jsr     @peek
        cmp     mp_u
        bcc     :+
        sta     mp_u
:       lda     mp_u                    ; level = peak (0-128) * volume / 128
        sta     mp_ma
        lda     c_vout,x
        sta     mp_mb
        jsr     mul16
        lda     mp_mr
        asl     a
        xba
        and     #$00FF
        bra     @set
@end:   stz     c_mact,x
@zero:  lda     #0
@set:   ldx     mp_cx
        pha
        txa
        lsr     a
        tax
        pla
        sep     #$20
        .a8
        sta     mp_lev,x
        rep     #$20
        .a16
        ldx     mp_cx
        inx
        inx
        cpx     mp_nch2
        jcc     @l
        rts
; A = word position (Y = sample * 2) -> A = |byte| 0-128
@peek:  asl     a
        pha
        lda     #0
        rol     a
        sta     mp_s+2
        pla
        clc
        adc     s_alo,y
        sta     mp_s
        lda     mp_s+2
        adc     s_ahi,y
        sta     mp_s+2
        lda     [mp_s]
        and     #$00FF
        cmp     #$80
        bcc     :+
        eor     #$00FF
        inc     a
:       rts

        .segment "RODATA"
        .assert CBUFW * 2 <= 4096, error, "a channel's copy fits its 4 KB"
tags:   .byte   "M.K.", 4, "M!K!", 4, "M&K!", 4, "N.T.", 4, "FLT4", 4, "4CHN", 4, "6CHN", 6, "8CHN", 8
        .byte   "CD81", 8, "OKTA", 8, "OCTA", 8, "FLT8", 9
        .word   0
bits:   .byte   1, 2, 4, 8, 16, 32, 64, 128
sine:   .byte   0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253
        .byte   255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24
ft_off: .repeat 16, I
        .word   I * 72
        .endrepeat
; the ProTracker period table: finetunes 0 .. 7, -8 .. -1, notes C-1 .. B-3
ft_tab: .word   856,808,762,720,678,640,604,570,538,508,480,453,428,404,381,360,339,320,302,285,269,254,240,226,214,202,190,180,170,160,151,143,135,127,120,113
        .word   850,802,757,715,674,637,601,567,535,505,477,450,425,401,379,357,337,318,300,284,268,253,239,225,213,201,189,179,169,159,150,142,134,126,119,113
        .word   844,796,752,709,670,632,597,563,532,502,474,447,422,398,376,355,335,316,298,282,266,251,237,224,211,199,188,177,167,158,149,141,133,125,118,112
        .word   838,791,746,704,665,628,592,559,528,498,470,444,419,395,373,352,332,314,296,280,264,249,235,222,209,198,187,176,166,157,148,140,132,125,118,111
        .word   832,785,741,699,660,623,588,555,524,495,467,441,416,392,370,350,330,312,294,278,262,247,233,220,208,196,185,175,165,156,147,139,131,124,117,110
        .word   826,779,736,694,655,619,584,551,520,491,463,437,413,390,368,347,328,309,292,276,260,245,232,219,206,195,184,174,164,155,146,138,130,123,116,109
        .word   820,774,730,689,651,614,580,547,516,487,460,434,410,387,365,345,325,307,290,274,258,244,230,217,205,193,183,172,163,154,145,137,129,122,115,109
        .word   814,768,725,684,646,610,575,543,513,484,457,431,407,384,363,342,323,305,288,272,256,242,228,216,204,192,181,171,161,152,144,136,128,121,114,108
        .word   907,856,808,762,720,678,640,604,570,538,508,480,453,428,404,381,360,340,321,303,286,270,254,240,226,214,202,190,180,170,160,151,143,135,127,120
        .word   900,850,802,757,715,675,636,601,567,535,505,477,450,425,401,379,357,337,318,300,284,268,253,238,225,212,200,189,179,169,159,150,142,134,126,119
        .word   894,844,796,752,709,670,632,597,563,532,502,474,447,422,398,376,355,335,316,298,282,266,251,237,223,211,199,188,177,167,158,149,141,133,125,118
        .word   887,838,791,746,704,665,628,592,559,528,498,470,444,419,395,373,352,332,314,296,280,264,249,235,222,209,198,187,176,166,157,148,140,132,125,118
        .word   881,832,785,741,699,660,623,588,555,524,494,467,441,416,392,370,350,330,312,294,278,262,247,233,220,208,196,185,175,165,156,147,139,131,123,117
        .word   875,826,779,736,694,655,619,584,551,520,491,463,437,413,390,368,347,328,309,292,276,260,245,232,219,206,195,184,174,164,155,146,138,130,123,116
        .word   868,820,774,730,689,651,614,580,547,516,487,460,434,410,387,365,345,325,307,290,274,258,244,230,217,205,193,183,172,163,154,145,137,129,122,115
        .word   862,814,768,725,684,646,610,575,543,513,484,457,431,407,384,363,342,323,305,288,272,256,242,228,216,203,192,181,171,161,152,144,136,128,121,114
; Lau's pitch for periods 0 .. 1023: round(1210673.29 / period)
pitch_tab:
        .word   0
        .repeat 1023, I
        .if (121067329 / (I + 1) + 50) / 100 > 65535
        .word   65535
        .else
        .word   (121067329 / (I + 1) + 50) / 100
        .endif
        .endrepeat
; the tick for 32 .. 255 BPM: round(2500000 / bpm) microseconds (u24), round(120000 / bpm) samples
us_tab: .repeat 224, I
        .faraddr (2500000 * 2 / (I + 32) + 1) / 2
        .endrepeat
spt_tab: .repeat 224, I
        .word   (120000 * 2 / (I + 32) + 1) / 2
        .endrepeat
