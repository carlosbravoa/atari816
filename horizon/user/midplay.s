; midplay.s - Standard MIDI File (SMF 0 & 1) OPL2 (YM3812) replayer library.
; Linked into /SYSTEM/MUSICD.PRG (API in user/midplay.inc).
;
; Features:
;   - SMF Format 0 and Format 1, up to 32 simultaneous tracks, arbitrary file size in
;     consecutive 64 KB banks (e_b0..).
;   - Full 128 General MIDI melodic patches + 47 GM percussion patches (Channel 10)
;     in 9-voice OPL2 melodic mode with waveform select ($01 = $20).
;   - Dynamic 9-voice allocator with release-preserving key-off (no pitch-drop clicks),
;     hi-hat choke group (closed/pedal chokes open), sustain pedal (CC 64), channel
;     volume (CC 7), expression (CC 11), master volume (0-64), and smooth ±2-semitone
;     pitch bend ($En).
;   - Exact rational tick accumulator at 200 Hz (5000 us) for zero tempo drift, plus
;     fast pre-scan for exact song duration (mm:ss) and fast-forward seek (0..255).

        .include "horizon.inc"

        .export mid_open, mid_play, mid_tick, mid_pause, mid_resume, mid_stop, mid_setvol
        .export mid_release, mid_cue
        .export mid_bank_init, mid_load_wopl
        .export mid_buf, mid_len, mid_loop
        .export mid_ntrks, mid_bpm, mid_tot_tenths, mid_tenths, mid_frac, mid_lev, mid_state
        .export mid_title

MID_US    = 5000        ; 200 Hz MIDI tick period (5 ms)
MIDF_END  = 2           ; mid_tick result: song ended
MIDS_STOP = 0
MIDS_PLAY = 1
MIDS_PAUSE = 2

MAX_TRK   = 32
NVOICE    = 9
NCHAN     = 16
EMS_FMT   = $FE
MIDS_SIL_SCAN = 1
MIDS_SIL_SEEK = 2
MAX_CHUNKS = 16384      ; (0.27) md_add_dt_us chunks of 1024 ticks in one silent run

        .segment "ZEROPAGE"
md_p:     .res    4             ; 24-bit current read pointer (lo16, bank16)
md_q:     .res    4             ; 24-bit scratch pointer
md_t0:    .res    2
md_t1:    .res    2
md_t2:    .res    2
md_t3:    .res    2

        .segment "CODE"
        .a16
        .i16

; ============================================================================
; Public API
; ============================================================================

; mid_open: parse SMF header + tracks in mid_buf (length mid_len), pre-scan duration.
; Returns C clear on success, or C set with A = ENODEV / EMS_FMT.
mid_open:
        ; Probe OPL2 hardware (REV $0C+)
        lda     #$FFFE
        ldx     #0
        sys     SYS_OPLW
        bcc     :+
        lda     #ENODEV
        sec
        rts
:       stz     mid_state
        stz     mid_ntrks
        stz     mid_tot_tenths
        stz     mid_tenths
        stz     mid_frac
        stz     mid_title
        lda     #120
        sta     mid_bpm
        lda     #64
        sta     md_mvol

        ; Compute file end address (md_fend_lo, md_fend_bk)
        lda     mid_len
        sta     md_fend_lo
        lda     mid_buf+2
        and     #$00FF
        clc
        adc     mid_len+2
        sta     md_fend_bk

        ; Need at least 14 bytes for MThd
        lda     mid_len+2
        bne     :+
        lda     mid_len
        cmp     #14
        bcs     :+
        jmp     @bad
:       ; Set md_p = mid_buf
        lda     mid_buf
        sta     z:md_p
        lda     mid_buf+2
        and     #$00FF
        sta     z:md_p+2

        ; Check "MThd"
        jsr     md_getb
        cmp     #'M'
        jne     @bad
        jsr     md_getb
        cmp     #'T'
        jne     @bad
        jsr     md_getb
        cmp     #'h'
        jne     @bad
        jsr     md_getb
        cmp     #'d'
        jne     @bad

        ; Header length (big-endian u32, must be >= 6)
        jsr     md_get32be
        lda     md_u32_hi
        jne     @bad
        lda     md_u32_lo
        cmp     #6
        jcc     @bad
        sec
        sbc     #6
        sta     md_hdr_extra

        ; Format (0 or 1)
        jsr     md_get16be
        cmp     #2
        jcs     @bad
        sta     md_fmt

        ; Number of tracks (1..MAX_TRK; extra tracks beyond MAX_TRK ignored cleanly)
        jsr     md_get16be
        jeq     @bad
        sta     md_hdr_trks

        ; Division (PPQN or SMPTE)
        jsr     md_get16be
        jeq     @bad
        bpl     @ppqn
        ; SMPTE: high byte = -fps (signed), low byte = subframes
        pha
        and     #$00FF
        sta     z:md_t0
        pla
        xba
        and     #$00FF
        eor     #$00FF
        inc     a               ; fps (24, 25, 29, 30)
        ldx     z:md_t0
        beq     @bad_smpte
        jsr     md_mul8_8
        sta     md_div
        lda     #1
        sta     md_smpte
        bra     @skip_hdr
@bad_smpte:
        jmp     @bad
@ppqn:  sta     md_div
        stz     md_smpte

@skip_hdr:
        ; Skip any extra header bytes beyond 6
        lda     md_hdr_extra
        beq     @chunks
        clc
        adc     z:md_p
        sta     z:md_p
        bcc     @chunks
        inc     z:md_p+2

@chunks:
        ; Walk chunks, recording up to MAX_TRK MTrk chunks
        stz     mid_ntrks
@cloop: ; Check at least 8 bytes left before file end
        jsr     md_frem_lt8
        bcs     @cdone
        jsr     md_get32be              ; chunk ID in md_u32_hi/lo
        lda     md_u32_hi
        sta     z:md_t2
        lda     md_u32_lo
        sta     z:md_t3
        jsr     md_get32be              ; chunk length in md_u32_lo/hi
        ; Compute chunk end = md_p + len, clamped to file end
        lda     z:md_p
        clc
        adc     md_u32_lo
        sta     md_cend_lo
        lda     z:md_p+2
        adc     md_u32_hi
        sta     md_cend_bk
        bcs     @cclamp                 ; (0.27) past 16 bits of banks: the file's end
        ; Clamp chunk end to file end
        cmp     md_fend_bk
        bcc     @cok
        bne     @cclamp
        lda     md_cend_lo
        cmp     md_fend_lo
        bcc     @cok
        beq     @cok
@cclamp:
        lda     md_fend_lo
        sta     md_cend_lo
        lda     md_fend_bk
        sta     md_cend_bk
@cok:   ; Is it "MTrk"? ('M'<<8|'T' in hi, 'r'<<8|'k' in lo)
        lda     z:md_t2
        cmp     #('M' << 8) | 'T'
        bne     @cnext
        lda     z:md_t3
        cmp     #('r' << 8) | 'k'
        bne     @cnext
        lda     mid_ntrks
        cmp     #MAX_TRK
        bcs     @cnext
        asl     a
        tax
        lda     z:md_p
        sta     tr_slo,x
        lda     z:md_p+2
        sta     tr_sbk,x
        lda     md_cend_lo
        sta     tr_elo,x
        lda     md_cend_bk
        sta     tr_ebk,x
        inc     mid_ntrks
@cnext: lda     md_cend_lo
        sta     z:md_p
        lda     md_cend_bk
        sta     z:md_p+2
        jmp     @cloop

@cdone: lda     mid_ntrks
        beq     @bad

        ; Precompute md_step = MID_US * md_div (32-bit)
        lda     md_div
        sta     md_m0
        stz     md_m1
        lda     #MID_US
        jsr     md_mul32_16
        lda     md_m0
        sta     md_step_lo
        lda     md_m1
        sta     md_step_hi

        ; Pre-scan all tracks silently for exact duration, initial BPM, and title
        jsr     md_prescan

        clc
        rts

@bad:   lda     #EMS_FMT
        sec
        rts

; ----------------------------------------------------------------------------
; mid_play: A = starting position in 256ths (0..255).
; Takes the OPL2 (reset once, 0.27) or keys its notes off, resets tracks, fast-forwards to
; target if A > 0, starts playing. C set, A = EAGAIN: another program owns the OPL2.
mid_play:
        stz     md_cue
md_play2:
        and     #$00FF
        sta     md_seek_pos
        jsr     opl_hw_init
        bcc     :+
        rts
:       jsr     md_reset_state
        lda     md_seek_pos
        beq     @go
        ; target_tenths = (pos * mid_tot_tenths) / 256
        lda     mid_tot_tenths
        beq     @go
        sta     md_m0
        stz     md_m1
        lda     md_seek_pos
        jsr     md_mul32_16
        ; Shift right 8 bits
        lda     md_m0
        xba
        and     #$00FF
        sta     z:md_t0
        lda     md_m1
        xba
        and     #$FF00
        ora     z:md_t0
        beq     @go
        sta     md_target_t
        jsr     md_fastfwd
@go:    stz     md_silent
        lda     md_cue                  ; (0.27) mid_cue: paused here
        beq     :+
        lda     #MIDS_PAUSE
        sta     mid_state
        clc
        rts
:       lda     #MIDS_PLAY
        sta     mid_state
        ; Dispatch tick-0 events right away
        jsr     md_dispatch_due
        clc
        rts

; mid_cue: (0.27) A = position in 256ths: as mid_play, but paused there (no notes sound
; before mid_resume; the events due at that tick come with the first mid_tick)
mid_cue:
        ldx     #1
        stx     md_cue
        bra     md_play2

; ----------------------------------------------------------------------------
; mid_release: (0.27) stop and give the OPL2 back (SYS_OPLW $FFFD), if it is ours
mid_release:
        jsr     mid_stop
        lda     md_own
        beq     @x
        stz     md_own
        lda     #$FFFD
        ldx     #0
        sys     SYS_OPLW
@x:     rts

; ----------------------------------------------------------------------------
; mid_pause: silence active voices cleanly (preserve song position)
mid_pause:
        lda     mid_state
        cmp     #MIDS_PLAY
        bne     @x
        lda     #MIDS_PAUSE
        sta     mid_state
        jsr     opl_all_keyoff
@x:     rts

; ----------------------------------------------------------------------------
; mid_resume: resume from pause
mid_resume:
        lda     mid_state
        cmp     #MIDS_PAUSE
        bne     @x
        lda     #MIDS_PLAY
        sta     mid_state
@x:     rts

; ----------------------------------------------------------------------------
; mid_stop: silence OPL2 and reset song position
mid_stop:
        lda     #MIDS_STOP
        sta     mid_state
        jsr     opl_all_keyoff
        stz     mid_tenths
        stz     mid_frac
        jsr     md_clr_meters
        rts

; ----------------------------------------------------------------------------
; mid_setvol: A = master volume (0..64); refresh sounding voices immediately
mid_setvol:
        cmp     #65
        bcc     :+
        lda     #64
:       sta     md_mvol
        lda     mid_state
        cmp     #MIDS_PLAY
        bne     @x
        ldx     #0
@vl:    lda     v_state,x
        cmp     #1
        bne     @vn
        phx
        stx     md_v
        jsr     opl_update_vol
        plx
@vn:    inx
        inx
        cpx     #NVOICE * 2
        bcc     @vl
@x:     rts

; ----------------------------------------------------------------------------
; mid_tick: called every MID_US (5000 us = 200 Hz).
; Returns A = MIDF_END if song ended (and stopped when mid_loop = 0), else 0.
mid_tick:
        lda     mid_state
        cmp     #MIDS_PLAY
        beq     :+
        lda     #0
        rts
:       ; Advance rational tick accumulator: md_sub += md_step
        lda     md_sub_lo
        clc
        adc     md_step_lo
        sta     md_sub_lo
        lda     md_sub_hi
        adc     md_step_hi
        sta     md_sub_hi

        ; While md_sub >= md_tempo: md_sub -= md_tempo; md_tick++
@adv:   lda     md_sub_hi
        cmp     md_tempo_hi
        bcc     @adv_done
        bne     @sub
        lda     md_sub_lo
        cmp     md_tempo_lo
        bcc     @adv_done
@sub:   lda     md_sub_lo
        sec
        sbc     md_tempo_lo
        sta     md_sub_lo
        lda     md_sub_hi
        sbc     md_tempo_hi
        sta     md_sub_hi
        inc     md_tick_lo
        bne     @adv
        inc     md_tick_hi
        bra     @adv

@adv_done:
        ; Dispatch all track events due at <= md_tick
        jsr     md_dispatch_due

        ; Release countdown for voices in state 2 (releasing)
        ldx     #0
@rl:    lda     v_state,x
        cmp     #2
        bne     @rn
        dec     v_rel,x
        bne     @rn
        stz     v_state,x
@rn:    inx
        inx
        cpx     #NVOICE * 2
        bcc     @rl

        ; Decay level meters every 4 ticks (20 ms = 50 Hz)
        inc     md_mdiv
        lda     md_mdiv
        and     #3
        bne     @tm
        ldx     #0
@ml:    sep     #$20
        .a8
        lda     mid_lev,x
        beq     :+
        sec
        sbc     #2
        bpl     :+
        lda     #0
:       sta     mid_lev,x
        rep     #$20
        .a16
        inx
        cpx     #8
        bcc     @ml

@tm:    ; Update elapsed tenths of a second (20 x 5 ms = 0.1 s)
        inc     md_sub5
        lda     md_sub5
        cmp     #20
        bcc     @chk_end
        stz     md_sub5
        inc     mid_tenths
        jsr     md_upd_frac

@chk_end:
        ; All tracks finished?
        lda     md_active
        bne     @not_end
        lda     mid_loop
        beq     @stop_end
        ; Loop cleanly from start
        jsr     opl_all_keyoff
        jsr     md_reset_state
        jsr     md_dispatch_due
        lda     #0
        rts
@stop_end:
        lda     #MIDS_STOP
        sta     mid_state
        lda     #MIDF_END
        rts
@not_end:
        lda     #0
        rts

; ============================================================================
; Pre-scan, Fast-forward, Reset, Dispatch
; ============================================================================

; Reset all tracks, channels, voice tables, tempo, and clock to tick 0.
md_reset_state:
        stz     md_tick_lo
        stz     md_tick_hi
        stz     md_sub_lo
        stz     md_sub_hi
        stz     md_sub5
        stz     md_mdiv
        stz     mid_tenths
        stz     mid_frac
        stz     md_age
        stz     md_us_lo
        stz     md_us_hi
        jsr     md_clr_meters

        ; Default tempo: 500,000 us (120 BPM) or 1,000,000 us for SMPTE
        lda     md_smpte
        bne     @smpte_t
        lda     #.loword(500000)
        sta     md_tempo_lo
        lda     #.hiword(500000)
        sta     md_tempo_hi
        bra     @ch_rst
@smpte_t:
        lda     #.loword(1000000)
        sta     md_tempo_lo
        lda     #.hiword(1000000)
        sta     md_tempo_hi

@ch_rst:
        ; Reset 16 MIDI channels
        ldx     #0
@cl:    stz     ch_prog,x
        lda     #100
        sta     ch_vol,x
        lda     #127
        sta     ch_expr,x
        stz     ch_sust,x
        stz     ch_bend,x
        inx
        inx
        cpx     #NCHAN * 2
        bcc     @cl

        ; Reset 9 OPL2 voice slots
        ldx     #0
@vl:    stz     v_state,x
        stz     v_sust,x
        stz     v_b0,x
        lda     #$FFFF
        sta     v_patch,x
        inx
        inx
        cpx     #NVOICE * 2
        bcc     @vl

        ; Reset tracks and read each track's initial delta-time
        stz     md_active
        ldx     #0
@tl:    cpx     #MAX_TRK * 2
        bcs     @td
        txa
        lsr     a
        cmp     mid_ntrks
        bcs     @td
        stx     md_trk
        lda     tr_slo,x
        sta     tr_plo,x
        sta     z:md_p
        lda     tr_sbk,x
        sta     tr_pbk,x
        sta     z:md_p+2
        stz     tr_rstat,x
        stz     tr_done,x
        jsr     md_tr_eof
        bcs     @tempty
        jsr     md_getvlq
        ldx     md_trk
        bcs     @tempty
        lda     md_vlq_lo
        sta     tr_nlo,x
        lda     md_vlq_hi
        sta     tr_nhi,x
        lda     z:md_p
        sta     tr_plo,x
        lda     z:md_p+2
        sta     tr_pbk,x
        inc     md_active
        bra     @tnext
@tempty:
        ldx     md_trk
        lda     #1
        sta     tr_done,x
@tnext: inx
        inx
        bra     @tl
@td:    rts

; ----------------------------------------------------------------------------
; Pre-scan silently for exact duration (mid_tot_tenths), initial BPM, and title.
md_prescan:
        lda     #MIDS_SIL_SCAN
        sta     md_silent
        stz     md_got_bpm
        stz     md_got_title
        jsr     md_reset_state
        jsr     md_run_silent
        lda     mid_tenths
        sta     mid_tot_tenths
        stz     mid_tenths
        stz     md_silent
        rts

; Fast-forward silently to md_target_t tenths (applying patches/CCs/tempo).
md_fastfwd:
        lda     #MIDS_SIL_SEEK
        sta     md_silent
        jsr     md_run_silent
        jsr     md_upd_frac
        stz     md_silent
        rts

; Jump event-to-event across all tracks in silent mode (1 = scan, 2 = seek).
md_run_silent:
        stz     md_evcap
        stz     md_evcap+2
        stz     md_chunks
@lp:    lda     md_active
        beq     @done
        lda     mid_tenths              ; (0.27) an hour or the time budget: the end
        cmp     #35999
        bcs     @done
        lda     md_chunks
        cmp     #MAX_CHUNKS
        bcs     @done
        ; In seek mode, stop once mid_tenths >= md_target_t
        lda     md_silent
        cmp     #MIDS_SIL_SEEK
        bne     :+
        lda     mid_tenths
        cmp     md_target_t
        bcs     @done
:       ; Safety cap: 262,144 events
        inc     md_evcap
        bne     :+
        inc     md_evcap+2
        lda     md_evcap+2
        cmp     #4
        bcs     @done
:       ; Find active track with minimum next tick
        jsr     md_find_min
        bcs     @done
        ; Compute dt = min_tick - md_tick (accumulate microseconds)
        ldx     md_trk
        lda     tr_nlo,x
        sec
        sbc     md_tick_lo
        sta     md_dt_lo
        lda     tr_nhi,x
        sbc     md_tick_hi
        sta     md_dt_hi
        ; Update md_tick = min_tick
        lda     tr_nlo,x
        sta     md_tick_lo
        lda     tr_nhi,x
        sta     md_tick_hi
        ; Add elapsed us for md_dt ticks (if non-zero)
        lda     md_dt_lo
        ora     md_dt_hi
        beq     @ev
        jsr     md_add_dt_us
        ; In seek mode, if jumping to this event crosses target_t, stop before it
        lda     md_silent
        cmp     #MIDS_SIL_SEEK
        bne     @ev
        lda     mid_tenths
        cmp     md_target_t
        bcs     @done
@ev:    jsr     md_proc_event
        bra     @lp
@done:  rts

; Accumulate md_dt_lo:md_dt_hi ticks at current md_tempo / md_div into md_us & mid_tenths.
; Processes in chunks of <= 1024 ticks so (chunk * md_tempo) never overflows 32 bits.
; (0.27) It stops at an hour (mid_tenths 35999) and after MAX_CHUNKS chunks in a run (a
; garbled delta of up to 2^28 ticks would take minutes); the rest of the delta is dropped.
md_add_dt_us:
@ck:    lda     mid_tenths
        cmp     #35999
        jcs     @done
        lda     md_chunks
        cmp     #MAX_CHUNKS
        jcs     @done
        inc     md_chunks
        lda     md_dt_hi
        bne     @big
        lda     md_dt_lo
        jeq     @done
        cmp     #1025
        bcc     @small
@big:   lda     #1024
        sta     z:md_t0
        lda     md_dt_lo
        sec
        sbc     #1024
        sta     md_dt_lo
        lda     md_dt_hi
        sbc     #0
        sta     md_dt_hi
        bra     @calc
@small: sta     z:md_t0
        stz     md_dt_lo
@calc:  ; (md_tempo * chunk) / md_div
        lda     md_tempo_lo
        sta     md_m0
        lda     md_tempo_hi
        sta     md_m1
        lda     z:md_t0
        jsr     md_mul32_16
        ldx     md_div
        jsr     md_div32_16
        ; md_us += md_m0:md_m1
        lda     md_us_lo
        clc
        adc     md_m0
        sta     md_us_lo
        lda     md_us_hi
        adc     md_m1
        sta     md_us_hi
        ; Convert every 100,000 us ($0001:86A0) into mid_tenths
@t10:   lda     md_us_hi
        cmp     #.hiword(100000)
        bcc     @ck
        bne     @sub10
        lda     md_us_lo
        cmp     #.loword(100000)
        jcc     @ck
@sub10: lda     md_us_lo
        sec
        sbc     #.loword(100000)
        sta     md_us_lo
        lda     md_us_hi
        sbc     #.hiword(100000)
        sta     md_us_hi
        lda     mid_tenths
        cmp     #35999                  ; cap at ~1 hour
        bcs     @t10
        inc     mid_tenths
        bra     @t10
@done:  rts

; ----------------------------------------------------------------------------
; Dispatch all due track events with tr_next <= md_tick (in chronological order).
md_dispatch_due:
        lda     #256                    ; per-tick safety limit
        sta     md_evlim
@lp:    lda     md_active
        beq     @done
        jsr     md_find_min
        bcs     @done
        ldx     md_trk
        ; Check tr_next[x] <= md_tick
        lda     tr_nhi,x
        cmp     md_tick_hi
        bcc     @go
        bne     @done
        lda     tr_nlo,x
        cmp     md_tick_lo
        bcc     @go
        bne     @done
@go:    jsr     md_proc_event
        dec     md_evlim
        bne     @lp
@done:  rts

; Find active track with smallest (tr_nhi:tr_nlo). Returns md_trk = best*2, C=0; or C=1 if none.
md_find_min:
        lda     #$FFFF
        sta     z:md_t0                 ; best lo
        sta     z:md_t1                 ; best hi
        sta     md_trk
        ldx     #0
        lda     mid_ntrks
        asl     a
        sta     z:md_t2                 ; limit = ntrks * 2
@lp:    cpx     z:md_t2
        bcs     @done
        lda     tr_done,x
        bne     @nx
        lda     md_trk
        bmi     @take                   ; first active track
        lda     tr_nhi,x
        cmp     z:md_t1
        bcc     @take
        bne     @nx
        lda     tr_nlo,x
        cmp     z:md_t0
        bcs     @nx
@take:  lda     tr_nlo,x
        sta     z:md_t0
        lda     tr_nhi,x
        sta     z:md_t1
        stx     md_trk
@nx:    inx
        inx
        bra     @lp
@done:  lda     md_trk
        bmi     @none
        clc
        rts
@none:  sec
        rts

; ============================================================================
; Event Parser & Dispatcher (operates on track md_trk)
; ============================================================================
md_proc_event:
        ldx     md_trk
        lda     tr_plo,x
        sta     z:md_p
        lda     tr_pbk,x
        sta     z:md_p+2

        jsr     md_getb_chk
        jcs     @end_trk
        bit     #$0080
        bne     @new_stat
        ; Running status: A is first data byte
        sta     md_d1
        ldx     md_trk
        lda     tr_rstat,x
        and     #$00FF
        jeq     @end_trk                ; invalid running status
        sta     md_stat
        bra     @have_d1

@new_stat:
        sta     md_stat
        cmp     #$00F0
        jcs     @sys_or_meta
        ; Channel status $80..$EF: save running status
        ldx     md_trk
        sta     tr_rstat,x
        jsr     md_getb_chk
        jcs     @end_trk
        sta     md_d1

@have_d1:
        ; Split status into high nibble (cmd) and low nibble (ch)
        lda     md_stat
        and     #$000F
        asl     a                       ; ch * 2
        sta     md_ch
        lda     md_stat
        and     #$00F0
        cmp     #$00C0                  ; Program Change (1 data byte)
        beq     @do_prog
        cmp     #$00D0                  ; Channel Pressure (1 data byte)
        jeq     @next_dt
        ; All other channel events ($80, $90, $A0, $B0, $E0) have 2 data bytes
        jsr     md_getb_chk
        jcs     @end_trk
        sta     md_d2
        lda     md_stat
        and     #$00F0
        cmp     #$0080
        beq     @do_noff
        cmp     #$0090
        beq     @do_non
        cmp     #$00B0
        beq     @do_cc
        cmp     #$00E0
        beq     @do_bend
        jmp     @next_dt                ; $A0 poly aftertouch: ignore

@do_prog:
        lda     md_silent
        cmp     #MIDS_SIL_SCAN
        jeq     @next_dt
        ldx     md_ch
        lda     md_d1
        and     #$007F
        sta     ch_prog,x
        jmp     @next_dt

@do_noff:
        lda     md_silent
        jne     @next_dt
        jsr     md_note_off
        jmp     @next_dt

@do_non:
        lda     md_silent
        jne     @next_dt
        lda     md_d2
        and     #$007F
        beq     @do_noff                ; vel 0 = Note Off
        sta     md_d2
        jsr     md_note_on
        jmp     @next_dt

@do_cc:
        lda     md_silent
        cmp     #MIDS_SIL_SCAN
        jeq     @next_dt
        jsr     md_cc
        jmp     @next_dt

@do_bend:
        lda     md_silent
        cmp     #MIDS_SIL_SCAN
        jeq     @next_dt
        jsr     md_bend
        jmp     @next_dt

@sys_or_meta:
        ; SMF: SysEx and Meta cancel running status; (0.27) kept anyway (tolerant: some
        ; files continue a running status after a meta event)
        lda     md_stat
        cmp     #$00FF
        beq     @meta
        cmp     #$00F0
        beq     @sysex
        cmp     #$00F7
        beq     @sysex
        ; Unexpected realtime/system byte: ignore
        jmp     @next_dt

@sysex: jsr     md_getvlq
        jcs     @end_trk
        jsr     md_skip_vlq
        jmp     @next_dt

@meta:  jsr     md_getb_chk             ; meta type
        jcs     @end_trk
        sta     md_mtype
        jsr     md_getvlq               ; meta length
        jcs     @end_trk
        lda     md_mtype
        cmp     #$002F                  ; End of Track
        jeq     @end_trk
        cmp     #$0051                  ; Set Tempo (3 bytes)
        beq     @tempo
        cmp     #$0003                  ; Track Name (capture during pre-scan)
        jeq     @tname
        jsr     md_skip_vlq
        jmp     @next_dt

@tempo: lda     md_smpte                ; (0.27) SMPTE division: the tempo stays fixed
        jne     @tskip
        lda     md_vlq_hi
        jne     @tskip
        lda     md_vlq_lo
        cmp     #3
        jne     @tskip
        ; Read 24-bit big-endian microseconds per quarter note (committed once all three are read)
        jsr     md_getb_chk
        jcs     @end_trk
        sta     z:md_t1                 ; top byte (bits 23..16)
        jsr     md_getb_chk
        jcs     @end_trk
        xba
        sta     z:md_t0
        jsr     md_getb_chk
        jcs     @end_trk
        ora     z:md_t0
        sta     md_tempo_lo
        lda     z:md_t1
        sta     md_tempo_hi
        ; Clamp tempo to [60000, 3000000] so corrupt files cannot stall
        lda     md_tempo_hi
        bne     @chk_hi
        lda     md_tempo_lo
        cmp     #60000
        bcs     @t_ok
        lda     #60000
        sta     md_tempo_lo
        bra     @t_ok
@chk_hi:
        cmp     #.hiword(3000000)
        bcc     @t_ok
        lda     #.loword(3000000)
        sta     md_tempo_lo
        lda     #.hiword(3000000)
        sta     md_tempo_hi
@t_ok:  ; On pre-scan, record initial BPM once: 60,000,000 / tempo_us
        lda     md_silent
        cmp     #MIDS_SIL_SCAN
        jne     @next_dt
        lda     md_got_bpm
        jne     @next_dt
        inc     md_got_bpm
        ; Approximate BPM = 60,000,000 / tempo_us = (60000000 >> 8) / (tempo_us >> 8)
        ; 60,000,000 >> 8 = 234,375 ($0003:9387)
        lda     #.loword(234375)
        sta     md_m0
        lda     #.hiword(234375)
        sta     md_m1
        ; X = tempo_us >> 8 (always 234..11718, fits in 16 bits!)
        lda     md_tempo_lo
        xba
        and     #$00FF
        sta     z:md_t0
        lda     md_tempo_hi
        xba
        and     #$FF00
        ora     z:md_t0
        tax
        beq     @next_dt
        jsr     md_div32_16
        lda     md_m0
        cmp     #1
        bcs     :+
        lda     #1
:       cmp     #255
        bcc     :+
        lda     #255
:       sta     mid_bpm
        bra     @next_dt

@tskip: jsr     md_skip_vlq
        bra     @next_dt

@tname: ; Capture first non-empty Meta $03 Track Name during pre-scan (up to 20 chars)
        lda     md_silent
        cmp     #MIDS_SIL_SCAN
        bne     @tskip
        lda     md_got_title
        bne     @tskip
        lda     md_vlq_hi
        bne     @tskip
        lda     md_vlq_lo
        beq     @tskip
        sta     z:md_t2                 ; total length
        ldy     #0
@tnl:   cpy     z:md_t2
        bcs     @tnd
        phy
        jsr     md_getb_chk
        ply
        bcs     @end_trk
        cpy     #20
        bcs     @tn_nx
        cmp     #$20
        bcc     @tn_nx
        cmp     #$7F
        bcs     @tn_nx
        sep     #$20
        .a8
        sta     mid_title,y
        rep     #$20
        .a16
@tn_nx: iny
        bra     @tnl
@tnd:   cpy     #20
        bcc     :+
        ldy     #20
:       sep     #$20
        .a8
        lda     #0
        sta     mid_title,y
        rep     #$20
        .a16
        lda     mid_title
        and     #$00FF
        beq     @next_dt
        inc     md_got_title
        bra     @next_dt

@next_dt:
        ; Read next event's delta-time and add to tr_next[md_trk]
        jsr     md_tr_eof
        bcs     @end_trk
        jsr     md_getvlq
        bcs     @end_trk
        ldx     md_trk
        lda     tr_nlo,x
        clc
        adc     md_vlq_lo
        sta     tr_nlo,x
        lda     tr_nhi,x
        adc     md_vlq_hi
        sta     tr_nhi,x
        lda     z:md_p
        sta     tr_plo,x
        lda     z:md_p+2
        sta     tr_pbk,x
        rts

@end_trk:
        ldx     md_trk
        lda     tr_done,x
        bne     :+
        lda     #1
        sta     tr_done,x
        dec     md_active
:       rts

; ============================================================================
; MIDI Control Change & Pitch Bend
; ============================================================================
md_cc:  ldx     md_ch
        lda     md_d1
        and     #$007F
        cmp     #7                      ; Channel Volume
        beq     @cc_vol
        cmp     #11                     ; Expression
        beq     @cc_expr
        cmp     #64                     ; Sustain Pedal
        beq     @cc_sust
        cmp     #120                    ; All Sound Off
        jeq     @cc_alloff
        cmp     #123                    ; All Notes Off
        jeq     @cc_alloff
        cmp     #121                    ; Reset All Controllers
        jeq     @cc_rst
        rts

@cc_vol:
        lda     md_d2
        and     #$007F
        sta     ch_vol,x
        bra     @upd_ch_vol

@cc_expr:
        lda     md_d2
        and     #$007F
        sta     ch_expr,x
@upd_ch_vol:
        lda     md_silent
        bne     @cc_x
        ; Refresh volume of all active voices on channel md_ch
        ldx     #0
@vl:    lda     v_state,x
        cmp     #1
        bne     @vn
        lda     v_ch,x
        cmp     md_ch
        bne     @vn
        phx
        stx     md_v
        jsr     opl_update_vol
        plx
@vn:    inx
        inx
        cpx     #NVOICE * 2
        bcc     @vl
@cc_x:  rts

@cc_sust:
        lda     md_d2
        and     #$007F
        cmp     #64
        bcs     @sust_on
@sust_off:
        stz     ch_sust,x
        lda     md_silent
        bne     @cc_x
        ; Release all voices on md_ch held by sustain pedal
        ldx     #0
@sl:    lda     v_state,x
        cmp     #1
        bne     @sn
        lda     v_ch,x
        cmp     md_ch
        bne     @sn
        lda     v_sust,x
        beq     @sn
        phx
        stx     md_v
        jsr     opl_release_v
        plx
@sn:    inx
        inx
        cpx     #NVOICE * 2
        bcc     @sl
        rts
@sust_on:
        lda     #1
        sta     ch_sust,x
        rts

@cc_alloff:
        stz     ch_sust,x
        lda     md_silent
        bne     @cc_x
        ldx     #0
@al:    lda     v_state,x
        cmp     #1
        bne     @an
        lda     v_ch,x
        cmp     md_ch
        bne     @an
        phx
        stx     md_v
        jsr     opl_release_v
        plx
@an:    inx
        inx
        cpx     #NVOICE * 2
        bcc     @al
        rts

@cc_rst:
        lda     #127
        sta     ch_expr,x
        stz     ch_bend,x
        lda     md_silent
        bne     @rs_x
        ; (0.27) the sounding voices of md_ch: expression and (melodic) bend applied
        ldx     #0
@rsl:   lda     v_state,x
        cmp     #1
        bne     @rsn
        lda     v_ch,x
        cmp     md_ch
        bne     @rsn
        phx
        stx     md_v
        jsr     opl_update_vol
        lda     md_ch
        cmp     #9 * 2
        beq     :+
        jsr     opl_update_pitch
:       plx
@rsn:   inx
        inx
        cpx     #NVOICE * 2
        bcc     @rsl
@rs_x:  ldx     md_ch                   ; the pedal up: the voices it held released
        jmp     @sust_off

        ; Pitch Bend: md_d1 = LSB (7-bit), md_d2 = MSB (7-bit) -> signed -8192..+8191
md_bend:
        lda     md_d1
        and     #$007F
        sta     z:md_t0
        lda     md_d2
        and     #$007F
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        ora     z:md_t0                 ; 0..16383 (center 8192)
        sec
        sbc     #8192                   ; signed -8192..+8191
        ldx     md_ch
        sta     ch_bend,x
        lda     md_silent
        bne     @bx
        ; Update pitch on all active melodic voices of channel md_ch
        lda     md_ch
        cmp     #9 * 2
        beq     @bx
        ldx     #0
@bl:    lda     v_state,x
        cmp     #1
        bne     @bn
        lda     v_ch,x
        cmp     md_ch
        bne     @bn
        phx
        stx     md_v
        jsr     opl_update_pitch
        plx
@bn:    inx
        inx
        cpx     #NVOICE * 2
        bcc     @bl
@bx:    rts

; ============================================================================
; OPL2 Voice Allocator & Synthesizer
; ============================================================================

; Note On: md_ch = ch*2, md_d1 = note (0..127), md_d2 = vel (1..127)
md_note_on:
        lda     md_d1
        and     #$007F
        sta     md_note
        ; Channel 9 (GM channel 10): percussion!
        lda     md_ch
        cmp     #9 * 2
        beq     @drum

        ; Melodic patch: patch_id = ch_prog[md_ch] (0..127)
        ldx     md_ch
        lda     ch_prog,x
        and     #$007F
        sta     md_pid
        jsr     md_patch_ptr            ; -> z:md_q = address of 12-byte patch in RODATA
        ; Effective note = md_note + signed byte patch[11]
        ldy     #11
        lda     [md_q],y
        and     #$00FF
        bit     #$0080
        beq     :+
        ora     #$FF00
:       clc
        adc     md_note
        bpl     :+
        lda     #0
:       cmp     #128
        bcc     :+
        lda     #127
:       sta     md_enote
        bra     @alloc

@drum:  ; Percussion: MIDI notes 35..87 (53 entries)
        lda     md_note
        cmp     #35
        bcc     @dr_ign
        cmp     #88
        bcs     @dr_ign
        ; Hi-hat choke: Closed (42) or Pedal (44) chokes Open Hi-Hat (46)
        cmp     #42
        beq     @choke
        cmp     #44
        bne     @dr_ok
@choke: ldx     #0
@chl:   lda     v_state,x
        beq     @chn
        lda     v_ch,x
        cmp     #9 * 2
        bne     @chn
        lda     v_note,x
        cmp     #46
        bne     @chn
        phx
        stx     md_v
        jsr     opl_release_v
        plx
@chn:   inx
        inx
        cpx     #NVOICE * 2
        bcc     @chl
@dr_ok: lda     md_note
        sec
        sbc     #35
        clc
        adc     #128                    ; drum patch IDs are 128..174
        sta     md_pid
        jsr     md_patch_ptr
        ldy     #11
        lda     [md_q],y
        and     #$00FF
        sta     md_enote
        bra     @alloc
@dr_ign:
        rts

@alloc: ; Allocate OPL2 voice (0..8 -> md_v = v*2)
        jsr     md_alloc_voice
        ldx     md_v

        ; Key-off the voice before retrigger / patch load, whatever its state (0.27: a
        ; drum freed by its release count may still be keyed on), keeping its pitch
        lda     v_b0,x
        beq     :+
        and     #$00DF
        tay
        lda     md_v
        lsr     a
        clc
        adc     #$00B0
        tyx
        sys     SYS_OPLW
        ldx     md_v

:       ; Record voice metadata
        lda     #1
        sta     v_state,x
        lda     md_ch
        sta     v_ch,x
        lda     md_note
        sta     v_note,x
        lda     md_enote
        sta     v_enote,x
        lda     md_d2
        sta     v_vel,x
        stz     v_sust,x
        inc     md_age
        lda     md_age
        sta     v_age,x

        ; Load static OPL2 patch registers if patch changed on this voice
        lda     v_patch,x
        cmp     md_pid
        beq     @same_p
        lda     md_pid
        sta     v_patch,x
        jsr     opl_load_patch
@same_p:
        ; Apply velocity / channel vol / expression / master vol
        jsr     opl_update_vol
        ; Compute pitch (with bend for melodic) and Key-On!
        jsr     opl_update_pitch
        ; (0.27) A drum gets no Note Off: it is releasing at once (free after ~300 ms), so
        ; the allocator takes drums before it steals a melodic note
        lda     md_ch
        cmp     #9 * 2
        bne     :+
        ldx     md_v
        lda     #2
        sta     v_state,x
        lda     #60
        sta     v_rel,x
:

        ; Update level meter (map voice 0..7 -> meter 0..7, voice 8 -> meter 7)
        lda     md_v
        lsr     a
        cmp     #8
        bcc     :+
        lda     #7
:       tax
        sep     #$20
        .a8
        lda     md_last_gain
        cmp     mid_lev,x
        bcc     :+
        sta     mid_lev,x
:       rep     #$20
        .a16
        rts

; Note Off: md_ch = ch*2, md_d1 = note (0..127)
md_note_off:
        ; Ignore Note Off for percussion (drums decay naturally)
        lda     md_ch
        cmp     #9 * 2
        beq     @nx
        lda     md_d1
        and     #$007F
        sta     md_note
        ldx     #0
@lp:    lda     v_state,x
        cmp     #1
        bne     @nn
        lda     v_ch,x
        cmp     md_ch
        bne     @nn
        lda     v_note,x
        cmp     md_note
        bne     @nn
        ; Sustain pedal held?
        ldy     md_ch
        lda     ch_sust,y
        beq     @rel
        lda     #1
        sta     v_sust,x
        bra     @nn
@rel:   phx
        stx     md_v
        jsr     opl_release_v
        plx
@nn:    inx
        inx
        cpx     #NVOICE * 2
        bcc     @lp
@nx:    rts

; Voice allocator -> sets md_v (v*2)
; Priority: 1. same (ch, note)  2. free (state 0)  3. oldest releasing (state 2)
;           4. oldest active (state 1)
md_alloc_voice:
        ; 1. Same (ch, note)?
        ldx     #0
@p1:    lda     v_state,x
        beq     @p1n
        lda     v_ch,x
        cmp     md_ch
        bne     @p1n
        lda     v_note,x
        cmp     md_note
        bne     @p1n
        stx     md_v
        rts
@p1n:   inx
        inx
        cpx     #NVOICE * 2
        bcc     @p1

        ; 2. Any free voice (state == 0)?
        ldx     #0
@p2:    lda     v_state,x
        bne     @p2n
        stx     md_v
        rts
@p2n:   inx
        inx
        cpx     #NVOICE * 2
        bcc     @p2

        ; 3. Oldest releasing voice (state == 2)?
        lda     #$FFFF
        sta     md_v
        stz     z:md_t0                 ; max age delta
        ldx     #0
@p3:    lda     v_state,x
        cmp     #2
        bne     @p3n
        lda     md_age
        sec
        sbc     v_age,x
        cmp     z:md_t0
        bcc     @p3n
        sta     z:md_t0
        stx     md_v
@p3n:   inx
        inx
        cpx     #NVOICE * 2
        bcc     @p3
        lda     md_v
        bpl     @got

        ; 4. Steal oldest active voice (largest md_age - v_age[x])
        stz     md_v
        stz     z:md_t0
        ldx     #0
@p4:    lda     md_age
        sec
        sbc     v_age,x
        cmp     z:md_t0
        bcc     @p4n
        sta     z:md_t0
        stx     md_v
@p4n:   inx
        inx
        cpx     #NVOICE * 2
        bcc     @p4
@got:   rts

; ============================================================================
; OPL2 Register Helpers (operate on voice md_v = v*2)
; ============================================================================

; Take the OPL2 and reset it (0.27: only when it is not ours yet; when it is, its voices are
; keyed off), enable waveform select ($01 = $20), and set bank $BD AM/VIB depth.
; C set, A = EAGAIN: another program owns it.
opl_hw_init:
        lda     md_own
        beq     :+
        jsr     opl_all_keyoff
        bra     @regs
:       lda     #$FFFF
        ldx     #0
        sys     SYS_OPLW
        bcc     :+
        rts
:       lda     #1
        sta     md_own
@regs:  lda     #$0001
        ldx     #$0020
        sys     SYS_OPLW
        lda     #$00BD
        ldx     md_bd_flags
        sys     SYS_OPLW
        clc
        rts

; Key-off all 9 OPL2 voices cleanly (keeping pitch in $B0+v)
opl_all_keyoff:
        ldx     #0
@lp:    phx
        stx     md_v
        jsr     opl_release_v
        plx
        stz     v_state,x
        inx
        inx
        cpx     #NVOICE * 2
        bcc     @lp
        rts

; Release voice md_v: write $B0+v = v_b0 (key-off keeping pitch), state = 2
opl_release_v:
        ldx     md_v
        lda     v_b0,x
        and     #$00DF                  ; ensure key-on bit 5 is 0
        tay
        lda     md_v
        lsr     a
        clc
        adc     #$00B0
        tyx
        sys     SYS_OPLW
        ldx     md_v
        lda     #2
        sta     v_state,x
        stz     v_sust,x
        lda     #40                     ; ~200 ms release window before free
        sta     v_rel,x
        rts

; Set z:md_q to the 12-byte patch in RAM bank for A = patch_id (0..127 melodic, 128..180 drum)
md_patch_ptr:
        cmp     #128
        bcs     @drm
        ; offset = idx * 12 = (idx << 2) + (idx << 3)
        asl     a
        asl     a
        sta     z:md_t0
        asl     a
        clc
        adc     z:md_t0
        clc
        adc     #.loword(ram_mel)
        sta     z:md_q
        lda     #^ram_mel
        sta     z:md_q+2
        rts
@drm:   sec
        sbc     #128
        asl     a
        asl     a
        sta     z:md_t0
        asl     a
        clc
        adc     z:md_t0
        clc
        adc     #.loword(ram_drm)
        sta     z:md_q
        lda     #^ram_drm
        sta     z:md_q+2
        rts

; ============================================================================
; Soundbank Management (built-in default + WOPL v1/v2/v3 runtime loader)
; ============================================================================

; Initialize RAM patch bank from built-in opl_gm.inc defaults.
mid_bank_init:
        stz     md_bd_flags
        ; Copy 128 melodic patches (1536 bytes)
        ldx     #0
@cm:    lda     gm_mel,x
        sta     ram_mel,x
        inx
        inx
        cpx     #128 * 12
        bcc     @cm
        ; Copy 47 built-in drum patches (notes 35..81 = 564 bytes)
        ldx     #0
@cd:    lda     gm_drm,x
        sta     ram_drm,x
        inx
        inx
        cpx     #47 * 12
        bcc     @cd
        ; Fill extra drum slots 82..87 (6 slots) by repeating slot 81 (Triangle)
        ldx     #47 * 12
@cx:    lda     ram_drm - 12,x
        sta     ram_drm,x
        inx
        inx
        cpx     #53 * 12
        bcc     @cx
        rts

; Parse a WOPL3-BANK file in bank A (offset 0, length X <= 65535) into ram_mel/ram_drm.
; Returns C clear on success, C set if invalid header or truncated.
mid_load_wopl:
        sta     md_wbk
        stx     md_wlen
        stz     z:md_p
        sta     z:md_p+2
        ; Need at least 19 bytes header
        cpx     #19
        jcc     @bad
        ; Check magic "WOPL3-BANK\0" (11 bytes)
        ldy     #0
@mag:   sep     #$20
        .a8
        lda     [md_p],y
        cmp     wopl_magic,y
        rep     #$20
        .a16
        jne     @bad
        iny
        cpy     #11
        bcc     @mag

        ; Version (little-endian u16 at offset 11): 1, 2, or 3
        ldy     #11
        lda     [md_p],y
        jeq     @bad
        cmp     #4
        jcs     @bad
        sta     md_wver

        ; Instrument size: 66 if ver >= 3, else 62
        cmp     #3
        bcc     :+
        lda     #66
        bra     :++
:       lda     #62
:       sta     md_wisize

        ; nb_mel (big-endian u16 at offset 13), nb_perc (big-endian u16 at offset 15)
        ldy     #13
        lda     [md_p],y
        xba
        jeq     @bad
        sta     md_wnmel
        ldy     #15
        lda     [md_p],y
        xba
        sta     md_wnprc

        ; Global flags at offset 17: bit 0 = deep AM ($80), bit 1 = deep VIB ($40)
        ; (0.27: into md_wbdf, taken only once the bank is known to fit)
        ldy     #17
        lda     [md_p],y
        and     #$00FF
        stz     md_wbdf
        bit     #$0001
        beq     :+
        lda     #$0080
        tsb     md_wbdf
        lda     [md_p],y
        and     #$00FF
:       bit     #$0002
        beq     :+
        lda     #$0040
        tsb     md_wbdf

:       ; Melodic bank 0 offset = 19 + (ver >= 2 ? 34 * (nb_mel + nb_perc) : 0)
        lda     #19
        sta     md_wmoff
        lda     md_wver
        cmp     #2
        bcc     @parse_mel
        lda     md_wnmel
        clc
        adc     md_wnprc
        sta     md_m0
        stz     md_m1
        lda     #34
        jsr     md_mul32_16
        lda     md_m1
        jne     @bad
        lda     md_m0
        clc
        adc     #19
        jcs     @bad
        sta     md_wmoff

@parse_mel:
        ; Verify melodic bank 0 fits in md_wlen: md_wmoff + 128 * md_wisize <= md_wlen
        lda     md_wisize
        sta     md_m0
        stz     md_m1
        lda     #128
        jsr     md_mul32_16
        lda     md_m0
        sta     md_wbsz                 ; bytes per 128-instrument bank (7936 or 8448)
        clc
        adc     md_wmoff
        jcs     @bad
        cmp     md_wlen
        beq     :+
        jcs     @bad
:       lda     md_wbdf                 ; the bank fits: its depths
        sta     md_bd_flags
        ; Convert 128 melodic instruments (bank 0) -> ram_mel
        lda     md_wmoff
        sta     z:md_p
        lda     md_wbk
        sta     z:md_p+2
        lda     #.loword(ram_mel)
        sta     z:md_q
        lda     #^ram_mel
        sta     z:md_q+2
        stz     md_widx                 ; 0..127
@ml:    jsr     wopl_conv_mel
        lda     z:md_p
        clc
        adc     md_wisize
        sta     z:md_p
        lda     z:md_q
        clc
        adc     #12
        sta     z:md_q
        inc     md_widx
        lda     md_widx
        cmp     #128
        bcc     @ml

        ; Parse percussion bank 0 (notes 35..87) if nb_perc >= 1 and within md_wlen
        lda     md_wnprc
        jeq     @ok
        ; perc0_off = md_wmoff + md_wnmel * md_wbsz
        lda     md_wbsz
        sta     md_m0
        stz     md_m1
        lda     md_wnmel
        jsr     md_mul32_16
        lda     md_m1
        jne     @ok
        lda     md_m0
        clc
        adc     md_wmoff
        jcs     @ok
        sta     md_wpoff
        ; Need perc0_off + 88 * md_wisize <= md_wlen
        lda     md_wisize
        sta     md_m0
        stz     md_m1
        lda     #88
        jsr     md_mul32_16
        lda     md_m0
        clc
        adc     md_wpoff
        bcs     @ok
        cmp     md_wlen
        beq     :+
        bcs     @ok
:       ; Start at note 35: md_p = md_wpoff + 35 * md_wisize
        lda     md_wisize
        sta     md_m0
        stz     md_m1
        lda     #35
        jsr     md_mul32_16
        lda     md_m0
        clc
        adc     md_wpoff
        sta     z:md_p
        lda     md_wbk
        sta     z:md_p+2
        lda     #.loword(ram_drm)
        sta     z:md_q
        lda     #^ram_drm
        sta     z:md_q+2
        lda     #35
        sta     md_widx                 ; note 35..87
@dl:    jsr     wopl_conv_drm
        lda     z:md_p
        clc
        adc     md_wisize
        sta     z:md_p
        lda     z:md_q
        clc
        adc     #12
        sta     z:md_q
        inc     md_widx
        lda     md_widx
        cmp     #88
        bcc     @dl
@ok:    clc
        rts
@bad:   sec
        rts

; Convert one WOPL melodic instrument at [md_p] -> 12-byte patch at [md_q]
wopl_conv_mel:
        ldy     #39                     ; (0.27) blank: the built-in patch stays
        lda     [md_p],y
        and     #$0004
        bne     @skip
        jsr     wopl_conv_ops
        ; Melodic note offset: signed byte at [md_p]+33
        sep     #$20
        .a8
        ldy     #33
        lda     [md_p],y
        ldy     #11
        sta     [md_q],y
        rep     #$20
        .a16
@skip:  rts

; Convert one WOPL drum instrument at [md_p] -> 12-byte patch at [md_q]
wopl_conv_drm:
        ; If blank flag (bit 2 of [md_p]+39) is set, leave built-in fallback intact
        ldy     #39
        lda     [md_p],y
        and     #$0004
        bne     @skip
        jsr     wopl_conv_ops
        ; Percussion fixed note at [md_p]+38 (if 0, use md_widx)
        sep     #$20
        .a8
        ldy     #38
        lda     [md_p],y
        bne     :+
        lda     md_widx
:       ldy     #11
        sta     [md_q],y
        rep     #$20
        .a16
@skip:  rts

; Copy WOPL carrier (42..46), modulator (47..51), and fb/conn (40) into [md_q] (0..10)
wopl_conv_ops:
        sep     #$20
        .a8
        ldy     #47                     ; mod $20
        lda     [md_p],y
        ldy     #0
        sta     [md_q],y
        ldy     #42                     ; car $20
        lda     [md_p],y
        ldy     #1
        sta     [md_q],y
        ldy     #48                     ; mod $40
        lda     [md_p],y
        ldy     #2
        sta     [md_q],y
        ldy     #43                     ; car $40
        lda     [md_p],y
        ldy     #3
        sta     [md_q],y
        ldy     #49                     ; mod $60
        lda     [md_p],y
        ldy     #4
        sta     [md_q],y
        ldy     #44                     ; car $60
        lda     [md_p],y
        ldy     #5
        sta     [md_q],y
        ldy     #50                     ; mod $80
        lda     [md_p],y
        ldy     #6
        sta     [md_q],y
        ldy     #45                     ; car $80
        lda     [md_p],y
        ldy     #7
        sta     [md_q],y
        ldy     #51                     ; mod $E0 (clamp to OPL2 0..3)
        lda     [md_p],y
        and     #$03
        ldy     #8
        sta     [md_q],y
        ldy     #46                     ; car $E0 (clamp to OPL2 0..3)
        lda     [md_p],y
        and     #$03
        ldy     #9
        sta     [md_q],y
        ldy     #40                     ; $C0 FB | CNT
        lda     [md_p],y
        and     #$0F
        ldy     #10
        sta     [md_q],y
        rep     #$20
        .a16
        rts

        .segment "RODATA"
wopl_magic:
        .byte   "WOPL3-BANK", 0
        .segment "CODE"

; Program static OPL2 registers ($20, $60, $80, $E0 mod & car, $C0) for voice md_v
; Assumes z:md_q points to 12-byte patch!
opl_load_patch:
        lda     md_v
        lsr     a
        tax
        lda     opl_mod_off,x
        and     #$00FF
        sta     md_mop
        lda     opl_car_off,x
        and     #$00FF
        sta     md_cop

        ; Modulator: $20, $60, $80, $E0
        ldy     #0
        lda     [md_q],y
        and     #$00FF
        tax
        lda     md_mop
        clc
        adc     #$0020
        sys     SYS_OPLW

        ldy     #4
        lda     [md_q],y
        and     #$00FF
        tax
        lda     md_mop
        clc
        adc     #$0060
        sys     SYS_OPLW

        ldy     #6
        lda     [md_q],y
        and     #$00FF
        tax
        lda     md_mop
        clc
        adc     #$0080
        sys     SYS_OPLW

        ldy     #8
        lda     [md_q],y
        and     #$00FF
        tax
        lda     md_mop
        clc
        adc     #$00E0
        sys     SYS_OPLW

        ; Carrier: $20, $60, $80, $E0
        ldy     #1
        lda     [md_q],y
        and     #$00FF
        tax
        lda     md_cop
        clc
        adc     #$0020
        sys     SYS_OPLW

        ldy     #5
        lda     [md_q],y
        and     #$00FF
        tax
        lda     md_cop
        clc
        adc     #$0060
        sys     SYS_OPLW

        ldy     #7
        lda     [md_q],y
        and     #$00FF
        tax
        lda     md_cop
        clc
        adc     #$0080
        sys     SYS_OPLW

        ldy     #9
        lda     [md_q],y
        and     #$00FF
        tax
        lda     md_cop
        clc
        adc     #$00E0
        sys     SYS_OPLW

        ; Feedback / Connection: $C0+v
        ldy     #10
        lda     [md_q],y
        and     #$00FF
        tax
        lda     md_v
        lsr     a
        clc
        adc     #$00C0
        sys     SYS_OPLW
        rts

; Compute velocity/volume attenuation for voice md_v and write $40+mod, $40+car
opl_update_vol:
        ldx     md_v
        lda     v_patch,x
        bpl     :+
        rts
:       jsr     md_patch_ptr
        lda     md_v
        lsr     a
        tax
        lda     opl_mod_off,x
        and     #$00FF
        sta     md_mop
        lda     opl_car_off,x
        and     #$00FF
        sta     md_cop

        ; gain = (((vel * ch_vol) >> 7) * ch_expr >> 7) * md_mvol >> 7  (0..63)
        ldx     md_v
        lda     v_ch,x
        tay                             ; Y = ch*2
        lda     v_vel,x
        ldx     ch_vol,y
        jsr     md_mul8_8
        asl     a                       ; >> 7 = (<< 1) >> 8
        xba
        and     #$00FF
        ldx     ch_expr,y
        jsr     md_mul8_8
        asl     a
        xba
        and     #$00FF
        ldx     md_mvol
        jsr     md_mul8_8
        asl     a
        xba
        and     #$00FF
        cmp     #64
        bcc     :+
        lda     #63
:       sta     md_last_gain
        tax
        lda     mid_atten,x
        and     #$00FF
        sta     md_att                  ; 0..63 attenuation steps

        ; Carrier $40: preserve KSL (bits 7:6), add atten to TL (clamp 63)
        ldy     #3
        lda     [md_q],y
        and     #$00FF
        pha
        and     #$003F
        clc
        adc     md_att
        cmp     #64
        bcc     :+
        lda     #63
:       sta     z:md_t0
        pla
        and     #$00C0
        ora     z:md_t0
        tax
        lda     md_cop
        clc
        adc     #$0040
        sys     SYS_OPLW

        ; Modulator $40: if additive (CNT=1) apply full atten, else gentle atten >> 3
        ldy     #10
        lda     [md_q],y
        and     #$0001
        bne     @m_add
        lda     md_att
        lsr     a
        lsr     a
        lsr     a
        bra     @m_set
@m_add: lda     md_att
@m_set: sta     z:md_t1
        ldy     #2
        lda     [md_q],y
        and     #$00FF
        pha
        and     #$003F
        clc
        adc     z:md_t1
        cmp     #64
        bcc     :+
        lda     #63
:       sta     z:md_t0
        pla
        and     #$00C0
        ora     z:md_t0
        tax
        lda     md_mop
        clc
        adc     #$0040
        sys     SYS_OPLW
@x:     rts

; Compute F-Num + Block for voice md_v (applying pitch bend for melodic) and write $A0/$B0 (Key-On)
opl_update_pitch:
        ldx     md_v
        lda     v_enote,x
        sta     z:md_t2                 ; base note 0..127
        ldy     v_ch,x
        cpy     #9 * 2
        beq     @no_bend
        lda     ch_bend,y
        beq     @no_bend

        ; Signed bend (-8192..+8191) = ±2 semitones:
        ;   semi_shift = bend >> 12 (arithmetic: -2, -1, 0, +1)
        ;   frac       = (bend >> 4) & $FF (0..255 toward next semitone)
        pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        and     #$00FF
        sta     z:md_t3                 ; frac (0..255)
        pla
        ; Arithmetic shift right 12 bits
        bpl     @bp
        xba
        ora     #$FF00
        bra     @bs
@bp:    xba
        and     #$00FF
@bs:    ; Now A is signed (bend >> 8); shift right 4 more with sign extension
        cmp     #$8000
        ror     a
        cmp     #$8000
        ror     a
        cmp     #$8000
        ror     a
        cmp     #$8000
        ror     a
        clc
        adc     z:md_t2                 ; n0 = note + semi_shift
        bpl     :+
        lda     #0
:       cmp     #126
        bcc     :+
        lda     #126
:       sta     z:md_t2                 ; n0 (0..126)

        ; Look up fnum[n0], blk[n0] and fnum[n0+1], blk[n0+1]
        tax
        lda     mid_blk,x
        and     #$00FF
        sta     md_blk_tmp
        lda     mid_blk+1,x
        and     #$00FF
        sta     z:md_t1
        txa
        asl     a
        tax
        lda     mid_fnum,x
        sta     z:md_t0                 ; f0
        lda     mid_fnum+2,x            ; f1
        ldy     z:md_t1
        cpy     md_blk_tmp
        beq     :+
        asl     a                       ; octave crossed: double f1 before interp
:       sec
        sbc     z:md_t0                 ; df = f1 - f0 (always 0..100)
        ldx     z:md_t3                 ; frac (0..255)
        jsr     md_mul8_8               ; df * frac
        xba
        and     #$00FF                  ; >> 8
        clc
        adc     z:md_t0                 ; f = f0 + ((df * frac) >> 8)
        cmp     #1024
        bcc     @write
        lsr     a
        inc     md_blk_tmp
        bra     @write

@no_bend:
        ldx     z:md_t2
        lda     mid_blk,x
        and     #$00FF
        sta     md_blk_tmp
        txa
        asl     a
        tax
        lda     mid_fnum,x

@write: sta     z:md_t0                 ; final 10-bit F-Num
        ; Handle block overflow safely if bend crossed above block 7
        lda     md_blk_tmp
        cmp     #8
        bcc     :+
        lda     #7
        sta     md_blk_tmp
        lda     #1023
        sta     z:md_t0
:       ; Write $A0+v = fnum_lo
        lda     z:md_t0
        and     #$00FF
        tax
        lda     md_v
        lsr     a
        clc
        adc     #$00A0
        sys     SYS_OPLW

        ; Build $B0 value = (blk << 2) | (fnum >> 8)
        lda     md_blk_tmp
        asl     a
        asl     a
        sta     z:md_t1
        lda     z:md_t0
        xba
        and     #$0003
        ora     z:md_t1
        ldx     md_v
        sta     v_b0,x                  ; save pitch without key-on for clean release
        ora     #$0020                  ; set Key-On bit 5
        tax
        lda     md_v
        lsr     a
        clc
        adc     #$00B0
        sys     SYS_OPLW
        rts

; ============================================================================
; File Reading & Math Helpers
; ============================================================================

; Check if file remaining from z:md_p to md_fend is < 8 bytes (C set if < 8)
md_frem_lt8:
        lda     md_fend_lo
        sec
        sbc     z:md_p
        tax
        lda     md_fend_bk
        sbc     z:md_p+2
        bcc     @lt                     ; already past end
        bne     @ge                     ; >= 65536 bytes left
        cpx     #8
        bcc     @lt
@ge:    clc
        rts
@lt:    sec
        rts

; Check if z:md_p >= tr_end[md_trk] -> C set if at/past track end
md_tr_eof:
        ldx     md_trk
        lda     z:md_p+2
        cmp     tr_ebk,x
        bcc     @no
        bne     @yes
        lda     z:md_p
        cmp     tr_elo,x
        bcs     @yes
@no:    clc
        rts
@yes:   sec
        rts

; Read 1 byte at [md_p] and advance 24-bit md_p -> A (0..255)
md_getb:
        sep     #$20                    ; (0.27: one byte; the next may be in a bank not ours)
        .a8
        lda     [md_p]
        rep     #$20
        .a16
        and     #$00FF
        inc     z:md_p
        bne     :+
        inc     z:md_p+2
:       rts

; Checked byte read against tr_end[md_trk] -> C clear & A = byte, or C set on EOF
md_getb_chk:
        jsr     md_tr_eof
        bcs     @eof
        jsr     md_getb
        clc
        rts
@eof:   sec
        rts

; Read 16-bit big-endian -> A
md_get16be:
        jsr     md_getb
        xba
        sta     z:md_t0
        jsr     md_getb
        ora     z:md_t0
        rts

; Read 32-bit big-endian -> md_u32_hi (top 16), md_u32_lo (low 16)
md_get32be:
        jsr     md_get16be
        sta     md_u32_hi
        jsr     md_get16be
        sta     md_u32_lo
        rts

; Read MIDI VLQ (up to 4 bytes) -> md_vlq_lo, md_vlq_hi; C set on EOF
md_getvlq:
        stz     md_vlq_lo
        stz     md_vlq_hi
        ldy     #4
@lp:    phy
        jsr     md_getb_chk
        ply
        bcs     @eof
        pha
        ; Shift md_vlq (32-bit) left by 7 bits
        ldx     #7
@sh:    asl     md_vlq_lo
        rol     md_vlq_hi
        dex
        bne     @sh
        pla
        pha
        and     #$007F
        ora     md_vlq_lo
        sta     md_vlq_lo
        pla
        bit     #$0080
        beq     @ok
        dey
        bne     @lp
@ok:    clc
        rts
@eof:   sec
        rts

; Advance z:md_p by (md_vlq_lo, md_vlq_hi), clamped to track end
md_skip_vlq:
        lda     z:md_p
        clc
        adc     md_vlq_lo
        sta     z:md_p
        lda     z:md_p+2
        adc     md_vlq_hi
        sta     z:md_p+2
        jsr     md_tr_eof
        bcc     :+
        ldx     md_trk
        lda     tr_elo,x
        sta     z:md_p
        lda     tr_ebk,x
        sta     z:md_p+2
:       rts

; Clear 8 level meter bytes
md_clr_meters:
        stz     mid_lev
        stz     mid_lev+2
        stz     mid_lev+4
        stz     mid_lev+6
        rts

; Update mid_frac = min(255, mid_tenths * 256 / mid_tot_tenths)
md_upd_frac:
        lda     mid_tot_tenths
        beq     @z
        lda     mid_tenths
        xba
        and     #$FF00
        sta     md_m0
        lda     mid_tenths
        xba
        and     #$00FF
        sta     md_m1
        ldx     mid_tot_tenths
        jsr     md_div32_16
        lda     md_m1
        bne     @cap
        lda     md_m0
        cmp     #256
        bcc     @set
@cap:   lda     #255
@set:   sta     mid_frac
        rts
@z:     stz     mid_frac
        rts

; Unsigned 8x8 -> 16-bit multiply: (A & $FF) * (X & $FF) -> A (preserves Y)
md_mul8_8:
        and     #$00FF
        sta     md_mul_a
        txa
        and     #$00FF
        sta     md_mul_b
        lda     #0
        ldx     #8
@lp:    lsr     md_mul_b
        bcc     :+
        clc
        adc     md_mul_a
:       asl     md_mul_a
        dex
        bne     @lp
        rts

; Unsigned 32x16 -> 32-bit multiply: (md_m0:md_m1) * A -> (md_m0:md_m1)
md_mul32_16:
        sta     md_mul_b
        lda     md_m0
        sta     md_r0
        lda     md_m1
        sta     md_r1
        stz     md_m0
        stz     md_m1
        ldx     #16
@lp:    lsr     md_mul_b
        bcc     :+
        lda     md_m0
        clc
        adc     md_r0
        sta     md_m0
        lda     md_m1
        adc     md_r1
        sta     md_m1
:       asl     md_r0
        rol     md_r1
        dex
        bne     @lp
        rts

; Unsigned 32/16 -> 32-bit quotient in (md_m0:md_m1), remainder in A; divisor in X
md_div32_16:
        stx     md_div_d
        lda     #0
        ldx     #32
@lp:    asl     md_m0
        rol     md_m1
        rol     a
        bcs     @sub
        cmp     md_div_d
        bcc     @nx
@sub:   sec
        sbc     md_div_d
        inc     md_m0
@nx:    dex
        bne     @lp
        rts

; ============================================================================
; General MIDI OPL2 Patch Bank & Tables
; ============================================================================
        .include "opl_gm.inc"

; ============================================================================
; Variables (BSS)
; ============================================================================
        .segment "BSS"

; Public interface variables
mid_buf:        .res    4       ; u24 address (offset 0, bank at +2)
mid_len:        .res    4       ; u24 file length in bytes
mid_loop:       .res    2       ; 1 = loop at end, 0 = stop
mid_ntrks:      .res    2       ; active track count (1..32)
mid_bpm:        .res    2       ; initial tempo in BPM
mid_tot_tenths: .res    2       ; total song duration in tenths of a second
mid_tenths:     .res    2       ; elapsed time in tenths of a second
mid_frac:       .res    2       ; position in 256ths (0..255)
mid_lev:        .res    8       ; 8 channel activity meters (0..63)
mid_state:      .res    2       ; MIDS_*
mid_title:      .res    24      ; optional extracted MIDI track name (NUL-terminated)

; File & parser state
md_fend_lo:     .res    2
md_fend_bk:     .res    2
md_cend_lo:     .res    2
md_cend_bk:     .res    2
md_hdr_extra:   .res    2
md_hdr_trks:    .res    2
md_fmt:         .res    2
md_div:         .res    2
md_smpte:       .res    2
md_u32_lo:      .res    2
md_u32_hi:      .res    2
md_vlq_lo:      .res    2
md_vlq_hi:      .res    2

; Timing state
md_step_lo:     .res    2       ; MID_US * md_div
md_step_hi:     .res    2
md_tempo_lo:    .res    2       ; microseconds per quarter note
md_tempo_hi:    .res    2
md_sub_lo:      .res    2       ; rational tick accumulator
md_sub_hi:      .res    2
md_tick_lo:     .res    2       ; current MIDI tick
md_tick_hi:     .res    2
md_sub5:        .res    2       ; 5 ms counter (0..19 -> 0.1 s)
md_mdiv:        .res    2       ; meter decay divider
md_us_lo:       .res    2       ; pre-scan/seek microsecond remainder
md_us_hi:       .res    2
md_dt_lo:       .res    2
md_dt_hi:       .res    2

; Playback / scan control
md_silent:      .res    2       ; 0 = play, 1 = pre-scan, 2 = fast-forward seek
md_got_bpm:     .res    2
md_got_title:   .res    2
md_seek_pos:    .res    2
md_target_t:    .res    2
md_evcap:       .res    4
md_chunks:      .res    2       ; (0.27) md_add_dt_us chunks in this silent run
md_own:         .res    2       ; (0.27) 1: the OPL2 is ours (taken by mid_play)
md_cue:         .res    2       ; (0.27) 1: mid_cue (stay paused)
md_evlim:       .res    2
md_active:      .res    2       ; number of tracks not yet ended
md_trk:         .res    2       ; current track index * 2
md_stat:        .res    2
md_ch:          .res    2       ; channel * 2
md_d1:          .res    2
md_d2:          .res    2
md_mtype:       .res    2
md_mvol:        .res    2       ; master volume 0..64

; OPL2 synth scratch
md_v:           .res    2       ; voice index * 2
md_pid:         .res    2       ; patch id (0..174)
md_note:        .res    2
md_enote:       .res    2
md_mop:         .res    2
md_cop:         .res    2
md_att:         .res    2
md_last_gain:   .res    2
md_blk_tmp:     .res    2
md_age:         .res    2

; Math scratch
md_m0:          .res    2
md_m1:          .res    2
md_r0:          .res    2
md_r1:          .res    2
md_mul_a:       .res    2
md_mul_b:       .res    2
md_div_d:       .res    2

; Per-track tables (MAX_TRK = 32)
tr_slo:         .res    MAX_TRK * 2
tr_sbk:         .res    MAX_TRK * 2
tr_elo:         .res    MAX_TRK * 2
tr_ebk:         .res    MAX_TRK * 2
tr_plo:         .res    MAX_TRK * 2
tr_pbk:         .res    MAX_TRK * 2
tr_nlo:         .res    MAX_TRK * 2
tr_nhi:         .res    MAX_TRK * 2
tr_rstat:       .res    MAX_TRK * 2
tr_done:        .res    MAX_TRK * 2

; Per-MIDI-channel state (16 channels)
ch_prog:        .res    NCHAN * 2
ch_vol:         .res    NCHAN * 2
ch_expr:        .res    NCHAN * 2
ch_sust:        .res    NCHAN * 2
ch_bend:        .res    NCHAN * 2

; Per-OPL2-voice state (9 voices)
v_state:        .res    NVOICE * 2
v_ch:           .res    NVOICE * 2
v_note:         .res    NVOICE * 2
v_enote:        .res    NVOICE * 2
v_vel:          .res    NVOICE * 2
v_patch:        .res    NVOICE * 2
v_b0:           .res    NVOICE * 2
v_sust:         .res    NVOICE * 2
v_age:          .res    NVOICE * 2
v_rel:          .res    NVOICE * 2

; Soundbank state & active RAM patch tables (default built-in, overridden by /SYSTEM/OPL2.WOPL)
md_bd_flags:    .res    2       ; $BD AM/VIB depth flags ($00 or $C0)
md_wbk:         .res    2
md_wbdf:        .res    2       ; (0.27) the file's depth flags until the bank is known to fit
md_wlen:        .res    2
md_wver:        .res    2
md_wisize:      .res    2
md_wnmel:       .res    2
md_wnprc:       .res    2
md_wmoff:       .res    2
md_wpoff:       .res    2
md_wbsz:        .res    2
md_widx:        .res    2
ram_mel:        .res    128 * 12
ram_drm:        .res    53 * 12
