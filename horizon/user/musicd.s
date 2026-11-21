; musicd.s - (0.26) the music engine, /SYSTEM/MUSICD.PRG: plays a ProTracker module (the replayer
; library user/modplay.s) or a WAV file on Lau, steadily, whatever the other programs do: it runs
; at priority 0 and is woken by the music timer (SYS_STIMER: TIMER1, a port message every tick),
; so a tick comes within a fraction of a millisecond of its time; between ticks it sleeps in
; recv. Its client (Music, or any program) drives it with port messages (user/music.inc).
;
;   musicd -p PORT        engine for a client: HELLO to PORT, then commands (spawned at prio 0)
;   musicd [-l] FILE      from the shell: starts itself at priority 0 (-x) and waits; it plays
;                         FILE once (-l: again and again) and ends (ctrl-C stops it)
;   musicd -x [-l] FILE   (that child)
; Either way it ends within a second when the task that started it has ended.

        .include "horizon.inc"
        .include "music.inc"
        .include "modplay.inc"
        .include "midplay.inc"

HBUF    = 1084                          ; the head of a file read first
CHUNK   = 16384                         ; read in pieces of 16 KB (progress between them)
IDLE_US = 200000                        ; the timer while nothing plays (the parent check)
WAV_US  = 20000                         ; the WAV tick (status, position)
KIND_MOD = 1
KIND_WAV = 2
KIND_MID = 3

        .segment "ZEROPAGE"
e_p:    .res    4                       ; pointers
e_q:    .res    4
e_r:    .res    4
e_s:    .res    4

        .segment "CODE"
        .a16
        .i16
start:  jsr     args_init
        stz     e_loop
        stz     e_mode
@arg:   ldx     #.loword(e_abuf)
        ldy     #^e_abuf
        lda     #128
        jsr     next_arg
        bcs     @args
        lda     e_abuf
        cmp     #'-' | 'p' << 8
        bne     :+
        lda     #2                      ; -p PORT
        sta     e_mode
        jsr     parse_dec
        sta     e_cport
        bra     @arg
:       cmp     #'-' | 'x' << 8
        bne     :+
        lda     #1
        sta     e_mode
        bra     @arg
:       cmp     #'-' | 'l' << 8
        bne     :+
        lda     #1
        sta     e_loop
        bra     @arg
:       ldx     #0                      ; the path
:       lda     e_abuf,x
        sta     e_path,x
        inx
        inx
        cpx     #128
        bcc     :-
        bra     @arg
@args:  lda     e_mode
        jne     engine
        ; ---- the shell's command: start the engine at priority 0 and wait for it ----
        lda     e_path
        and     #$00FF
        bne     :+
        print   "usage: musicd [-l] FILE (a MOD or WAV file)\n"
        exit    1
:       ldx     #0                      ; "-x [-l] PATH"
        lda     #'-' | 'x' << 8
        sta     e_abuf
        lda     #' '
        sta     e_abuf+2
        ldy     #3
        lda     e_loop
        beq     :+
        lda     #'-' | 'l' << 8
        sta     e_abuf+3
        lda     #' '
        sta     e_abuf+5
        ldy     #6
:       sep     #$20
        .a8
        lda     #'"'
        sta     e_abuf,y
        iny
:       lda     e_path,x
        beq     :+
        sta     e_abuf,y
        inx
        iny
        cpy     #124
        bcc     :-
:       lda     #'"'
        sta     e_abuf,y
        lda     #0
        sta     e_abuf+1,y
        rep     #$20
        .a16
        lda     #.loword(e_abuf)
        sta     z:u_arg
        lda     #^e_abuf
        sta     z:u_arg+2
        ldx     #.loword(p_self)
        ldy     #^p_self
        lda     #0
        jsr     spawn
        bcc     :+
        print   "musicd: cannot start the engine\n"
        exit    1
:       sys     SYS_WAIT
        jsr     exit_a

; ---------------------------------------------------------------- the engine
engine: sys     SYS_GETPID
        sta     e_pid
        jsr     find_parent
        sys     SYS_PCREATE
        bcc     :+
        lda     #1
        jsr     exit_a
:       sta     e_port
        lda     #MST_EMPTY
        sta     e_state
        stz     e_kind
        lda     #64
        sta     e_vol
        lda     #32
        sta     e_sep
        lda     e_mode
        cmp     #2
        bne     :+
        lda     #MS_HELLO               ; the client learns our port
        sta     e_sbuf
        lda     e_port
        sta     e_sbuf+1
        jsr     to_client
:       sys     SYS_SSTAT               ; Lau?
        jcc     :++
        lda     e_mode
        cmp     #2
        beq     :+
        print   "musicd: this machine has no Lau, the sample player (hardware revision $0A or later)\n"
        exit    1
:       lda     #ENODEV                 ; a client gets the error, then the engine ends
        jsr     set_err
        jsr     send_status
        exit    1
:       lda     e_mode                  ; the level meters: for a client only
        lsr     a
        sta     mp_meter
        lda     #SPF_KEEP
        sta     mp_keep
        lda     e_loop
        sta     mp_loop
        sta     mid_loop
        jsr     idle_timer
        sys     SYS_UPTIME
        sta     e_ms
        lda     e_mode
        cmp     #1
        bne     loop
        ; from the shell: load and play the file
        jsr     e_load
        bcc     :+
        jsr     print_err
        exit    1
:       print   "Playing "
        ldx     #.loword(e_path)
        ldy     #^e_path
        jsr     out_str
        lda     e_kind
        cmp     #KIND_MOD
        bne     :+
        print   ": "
        jsr     print_title
:       print   "\n"
        jsr     out_flush
        lda     #0
        jsr     e_play

; ---- the main loop: everything comes as a message ----
loop:   lda     e_port
        ldx     #.loword(e_msg)
        ldy     #^e_msg
        sys     SYS_RECV
        bcc     :+
        lda     #1
        jsr     exit_a
:       lda     e_msg
        and     #$00FF
        cmp     #$FF
        bne     :+
        jsr     on_tick
        bra     loop
:       jsr     on_cmd
        bra     loop

; a timer message: the ticks due (the count may have jumped: at most 8 at once), the parent
on_tick:
        lda     e_msg+1
        and     #$00FF
        cmp     e_gen
        beq     :+
        rts
:       lda     e_endp
        beq     :+
        jsr     end_tick
        jmp     send_status
:       lda     e_msg+2
        sec
        sbc     e_tcnt
        sta     e_n
        lda     e_msg+2
        sta     e_tcnt
        lda     e_n
        beq     @chk
        cmp     #9
        bcc     :+
        lda     #8
        sta     e_n
:       lda     e_state
        cmp     #MST_PLAYING
        bne     @chk
@t:     lda     e_kind
        cmp     #KIND_WAV
        bne     :+
        jsr     wav_tick
        bra     :+++
:       cmp     #KIND_MID
        bne     :+
        jsr     mid_tick_step
        bra     :++
:       jsr     mod_tick
:       lda     e_state
        cmp     #MST_PLAYING
        bne     :+
        dec     e_n
        bne     @t
:       ; For MIDI (200 Hz), throttle status messages to 50 Hz unless state changed
        lda     e_kind
        cmp     #KIND_MID
        bne     @sstat
        lda     e_state
        cmp     #MST_PLAYING
        bne     @sstat
        inc     e_msdiv
        lda     e_msdiv
        and     #3
        bne     @chk
@sstat: lda     #1                      ; (a tick's status may be dropped)
        sta     e_drop
        jsr     send_status
        stz     e_drop
@chk:   jsr     flush_pend              ; a message that did not fit before
        inc     e_chk                   ; once a second: is the parent still there?
        lda     e_chk                   ; (the clock asked every 4th message only)
        and     #3
        bne     @x
        sys     SYS_UPTIME
        sec
        sbc     e_ms
        cmp     #1000
        bcc     @x
        clc
        adc     e_ms
        sta     e_ms
        jsr     parent_alive
        bcc     @x
        jsr     quit
@x:     rts

; one module tick
mod_tick:
        jsr     mp_tick
        sta     e_t
        and     #MPF_TEMPO
        beq     :+
        jsr     mod_timer
:       lda     e_t
        and     #MPF_END
        beq     @x
        lda     mp_state
        bne     @x                      ; it goes on (loop)
        lda     #MST_ENDED              ; the voices stop at the next tick (end_tick)
        sta     e_state
        lda     #1
        sta     e_endp
@x:     rts

; one MIDI tick (5000 us = 200 Hz)
mid_tick_step:
        jsr     mid_tick
        and     #MIDF_END
        beq     @x
        lda     mid_state
        bne     @x                      ; looped
        lda     #MST_ENDED
        sta     e_state
        lda     #1
        sta     e_endp
@x:     rts

; the tick after a song's end: its voices stop; from the shell: done
end_tick:
        stz     e_endp
        lda     e_state                 ; (still at its end: not played again meanwhile)
        cmp     #MST_ENDED
        beq     :+
        rts
:       lda     e_kind
        cmp     #KIND_MID
        bne     :+
        jsr     mid_stop
        bra     :++
:       jsr     mp_stop
:       jsr     idle_timer
        lda     e_mode
        cmp     #1
        bne     :+
        print   "Ended\n"
        exit    0
:       rts

mod_timer:
        lda     e_port
        ldx     mp_tickus
        ldy     mp_tickus+2
        sys     SYS_STIMER
        rts
idle_timer:
        ldx     #.loword(IDLE_US)
        ldy     #^IDLE_US
; the timer (re)started with the period X, Y: its first message one period from now; the
; messages of before (another generation) are ignored
timer_start:
        phx
        phy
        lda     #$FFFF
        sys     SYS_STIMER
        ply
        plx
        lda     e_port
        sys     SYS_STIMER
        and     #$00FF
        sta     e_gen
        stz     e_tcnt
        rts
mod_start:
        ldx     mp_tickus
        ldy     mp_tickus+2
        bra     timer_start
wav_timer:
        ldx     #WAV_US
        ldy     #0
        bra     timer_start
mid_timer:
        ldx     #MID_US
        ldy     #0
        bra     timer_start

; ---- commands ----
on_cmd: lda     e_msg+1
        and     #$00FF
        sta     e_arg
        lda     e_msg
        and     #$00FF
        cmp     #MC_QUIT + 1
        bcs     @x
        asl     a
        tax
        jmp     (ctab,x)
@x:     rts
ctab:   .word   c_nop, c_path, c_load, c_play, c_pause, c_stop, c_seek, c_vol, c_sep, c_read
        .word   c_loop, quit
c_nop:  rts

c_path: lda     e_arg                   ; 14 characters at offset [1]
        cmp     #114
        bcs     c_nop
        tay
        ldx     #0
        sep     #$20
        .a8
:       lda     e_msg+2,x
        sta     e_path,y
        iny
        inx
        cpx     #14
        bcc     :-
        lda     #0
        sta     e_path+127
        rep     #$20
        .a16
        rts

c_load: jsr     e_load
        bcc     :+
        jmp     send_status             ; MST_ERROR
:       lda     e_arg
        and     #MCL_PLAY
        beq     :+
        lda     #0
        jmp     e_play
:       jmp     send_status

c_play: lda     e_state
        cmp     #MST_PAUSED
        bne     :+
        lda     e_arg
        cmp     #$FF
        bne     :+
        jmp     e_resume
:       lda     e_state
        cmp     #MST_STOPPED
        bcc     c_nop                   ; nothing loaded (or loading)
        cmp     #MST_ERROR
        bcs     c_nop
        lda     e_arg
        cmp     #$FF
        bne     :+
        lda     #0
:       jmp     e_play

c_pause:
        lda     e_state
        cmp     #MST_PLAYING
        bne     c_nop
        lda     #MST_PAUSED
        sta     e_state
        lda     e_kind
        cmp     #KIND_WAV
        bne     :+
        jsr     wav_hold
        bra     :+++
:       cmp     #KIND_MID
        bne     :+
        jsr     mid_pause
        bra     :++
:       jsr     mp_pause
:       jsr     idle_timer
        jmp     send_status

c_stop: lda     e_state
        cmp     #MST_PLAYING
        beq     :+
        cmp     #MST_PAUSED
        beq     :+
        cmp     #MST_ENDED
        bne     c_nop2
:       jsr     e_stop
        jmp     send_status

c_seek: lda     e_state
        cmp     #MST_PLAYING
        beq     :+
        cmp     #MST_PAUSED
        bne     c_nop2
:       lda     e_kind
        cmp     #KIND_WAV
        bne     :+
        jmp     wav_seek
:       cmp     #KIND_MID
        bne     @sk_mod
        lda     e_arg
        jsr     mid_play
        lda     e_state
        cmp     #MST_PAUSED
        bne     :+
        jsr     mid_pause
        jmp     send_status
:       jsr     mid_timer
        jmp     send_status
@sk_mod:
        lda     e_arg
        jsr     mp_seek
        lda     e_state
        cmp     #MST_PLAYING
        bne     :+
        jsr     mp_tick                 ; its first tick at once
        jsr     mod_start
:       jmp     send_status
c_nop2: rts

c_vol:  lda     e_arg
        cmp     #65
        bcc     :+
        lda     #64
:       sta     e_vol
        jsr     mp_setvol
        lda     e_kind
        cmp     #KIND_MID
        bne     :+
        lda     e_vol
        jmp     mid_setvol
:       cmp     #KIND_WAV
        bne     c_nop2
        lda     e_state
        cmp     #MST_PLAYING
        bne     c_nop2
        jmp     wav_vols
c_sep:  lda     e_arg
        sta     e_sep
        jmp     mp_setsep
c_loop: lda     e_arg
        and     #1
        sta     e_loop
        sta     mp_loop
        sta     mid_loop
        rts

; [1] length, [2..4] offset, [5] area -> MS_DATA
c_read: lda     #MS_DATA
        sta     e_sbuf
        lda     e_arg
        jeq     @none
        cmp     #15
        jcs     @none
        sta     e_n
        lda     e_msg+5
        and     #$00FF
        bne     @info
        lda     e_kind                  ; area 0: the module (or MIDI title) in memory
        cmp     #KIND_MID
        bne     @a0_mod
        lda     e_msg+4
        and     #$00FF
        jne     @none
        lda     e_msg+2
        clc
        adc     e_n
        cmp     #21
        jcs     @none
        lda     #.loword(mid_title)
        clc
        adc     e_msg+2
        sta     e_p
        lda     #^mid_title
        sta     e_p+2
        bra     @copy
@a0_mod:
        cmp     #KIND_MOD
        jne     @none
        lda     e_msg+2                 ; offset + length <= mp_mlen
        clc
        adc     e_n
        sta     e_t
        lda     e_msg+4
        and     #$00FF
        adc     #0
        cmp     mp_mlen+2
        bcc     @ok
        bne     @none
        lda     e_t
        cmp     mp_mlen
        beq     @ok
        bcs     @none
@ok:    lda     mp_mod
        clc
        adc     e_msg+2
        sta     e_p
        lda     e_msg+4
        and     #$00FF
        adc     mp_mod+2
        and     #$00FF
        sta     e_p+2
        bra     @copy
@info:  lda     e_msg+2                 ; area 1: the info block
        clc
        adc     e_n
        cmp     #MI_SIZEOF + 1
        bcs     @none
        lda     #.loword(e_info)
        clc
        adc     e_msg+2
        sta     e_p
        lda     #^e_info
        sta     e_p+2
        lda     e_kind
        cmp     #KIND_MOD
        bne     @copy
        lda     mp_speed                ; the live values (MOD only)
        sep     #$20
        .a8
        sta     e_info+MI_SPEED
        lda     mp_bpm
        sta     e_info+MI_BPM
        rep     #$20
        .a16
@copy:  lda     e_n
        sta     e_sbuf+1
        ldy     #0
        sep     #$20
        .a8
:       lda     [e_p],y
        sta     e_sbuf+2,y
        iny
        cpy     e_n
        bcc     :-
        rep     #$20
        .a16
        bra     @send
@none:  stz     e_sbuf+1
@send:  jmp     to_client

; MC_QUIT (or the parent is gone)
quit:   jsr     e_stop
        lda     #0
        jsr     exit_a

; ---------------------------------------------------------------- play, stop
; A = the first order (MOD) / position in 256ths (WAV, MIDI)
e_play: sta     e_t
        stz     e_endp
        lda     e_kind
        cmp     #KIND_WAV
        bne     :+
        lda     #MST_PLAYING
        sta     e_state
        lda     e_t
        sta     e_arg
        jmp     wav_seek
:       cmp     #KIND_MID
        bne     :+
        lda     #MST_PLAYING
        sta     e_state
        stz     e_msdiv
        lda     e_t
        jsr     mid_play
        jsr     mid_timer
        jmp     send_status
:       lda     #MST_PLAYING
        sta     e_state
        jsr     mp_reset125             ; the timer runs from the first tick (at 125 BPM) ...
        jsr     mod_start
        lda     e_t
        jsr     mp_play                 ; its first tick has run
        lda     mp_tickus               ; ... unless that tick set another tempo
        cmp     #20000
        bne     :+
        lda     mp_tickus+2
        beq     :++
:       jsr     mod_start
:       jmp     send_status
mp_reset125:
        lda     #.loword(20000)
        sta     mp_tickus
        stz     mp_tickus+2
        rts

e_resume:
        lda     #MST_PLAYING
        sta     e_state
        lda     e_kind
        cmp     #KIND_WAV
        bne     :+
        jsr     wav_vols
        jsr     wav_timer
        jmp     send_status
:       cmp     #KIND_MID
        bne     :+
        jsr     mid_resume
        jsr     mid_timer
        jmp     send_status
:       jsr     mp_resume
        jsr     mod_start
        jmp     send_status

e_stop: lda     e_kind
        cmp     #KIND_WAV
        bne     :+
        lda     #$FFFF
        sys     SYS_SSTOP
        stz     e_wpos
        stz     e_wpos+2
        stz     e_tenths
        bra     :+++
:       cmp     #KIND_MID
        bne     :+
        jsr     mid_stop
        bra     :++
:       cmp     #KIND_MOD
        bne     :+
        jsr     mp_stop
        lda     #0
        jsr     mp_seek
        stz     mp_tenths
:       lda     e_kind
        beq     :+
        lda     #MST_STOPPED
        sta     e_state
:       jmp     idle_timer

; ---------------------------------------------------------------- status
send_status:
        lda     e_mode
        cmp     #2
        jne     @x
        lda     #MS_STATUS
        sta     e_sbuf
        lda     e_state
        sta     e_sbuf+1
        stz     e_sbuf+8
        stz     e_sbuf+10
        stz     e_sbuf+12
        stz     e_sbuf+14
        lda     e_kind
        cmp     #KIND_WAV
        beq     @wav
        cmp     #KIND_MID
        beq     @mid
        lda     mp_order
        sta     e_sbuf+2
        lda     mp_row
        sta     e_sbuf+3
        lda     mp_pat
        sta     e_sbuf+4
        lda     mp_speed
        sta     e_sbuf+5
        lda     mp_tenths
        sta     e_sbuf+6
        lda     e_state
        cmp     #MST_PLAYING
        bne     @spec
        lda     mp_lev
        sta     e_sbuf+8
        lda     mp_lev+2
        sta     e_sbuf+10
        lda     mp_lev+4
        sta     e_sbuf+12
        lda     mp_lev+6
        sta     e_sbuf+14
        bra     @spec
@mid:   lda     mid_frac
        sta     e_sbuf+2
        stz     e_sbuf+3
        stz     e_sbuf+4
        lda     mid_tenths
        sta     e_sbuf+6
        lda     e_state
        cmp     #MST_PLAYING
        bne     @spec
        lda     mid_lev
        sta     e_sbuf+8
        lda     mid_lev+2
        sta     e_sbuf+10
        lda     mid_lev+4
        sta     e_sbuf+12
        lda     mid_lev+6
        sta     e_sbuf+14
        bra     @spec
@wav:   lda     e_wfrac
        sta     e_sbuf+2
        stz     e_sbuf+3
        stz     e_sbuf+4
        lda     e_tenths
        sta     e_sbuf+6
        lda     e_state
        cmp     #MST_PLAYING
        bne     @spec
        lda     e_wlev
        sta     e_sbuf+8
@spec:  lda     e_state                 ; [5]: the error, the percent loaded
        cmp     #MST_ERROR
        beq     :+
        cmp     #MST_LOADING
        bne     @send
:       lda     e_err
        sep     #$20
        .a8
        sta     e_sbuf+5
        rep     #$20
        .a16
@send:  jmp     to_client
@x:     rts

; e_sbuf -> the client. A full queue: a tick's status (e_drop) is dropped; any other message
; (a change of state, MS_DATA) waits in e_pend and is sent again at the next timer message
to_client:
        lda     e_mode
        cmp     #2
        bne     @x
        jsr     flush_pend
        lda     e_np
        bne     @keep                   ; (keep the order)
        lda     e_cport
        ldx     #.loword(e_sbuf)
        ldy     #^e_sbuf
        sys     SYS_SEND
        bcc     @x
@keep:  lda     e_drop
        bne     @x
        lda     e_np                    ; 4 waiting at most (the last ones are kept)
        cmp     #4 * 16
        bcc     :+
        jsr     pend_shift
:       ldx     e_np
        ldy     #0
:       lda     e_sbuf,y
        sta     e_pend,x
        inx
        inx
        iny
        iny
        cpy     #16
        bcc     :-
        stx     e_np
@x:     rts
; the waiting messages, in order, while the client's queue takes them
flush_pend:
:       lda     e_np
        beq     @x
        lda     e_cport
        ldx     #.loword(e_pend)
        ldy     #^e_pend
        sys     SYS_SEND
        bcs     @x
        jsr     pend_shift
        bra     :-
@x:     rts
pend_shift:
        ldx     #0
:       lda     e_pend+16,x
        sta     e_pend,x
        inx
        inx
        cpx     #3 * 16
        bcc     :-
        lda     e_np
        sec
        sbc     #16
        sta     e_np
        rts

; A = error: state MST_ERROR
set_err:
        sta     e_err
        lda     #MST_ERROR
        sta     e_state
        stz     e_kind
        rts

; ---------------------------------------------------------------- the parent
find_parent:
        stz     e_ppid
        ldx     #0
@l:     phx
        txa
        ldx     #.loword(e_ti)
        ldy     #^e_ti
        sys     SYS_TINFO
        plx
        lda     e_ti
        and     #$00FF
        cmp     e_pid
        bne     :+
        lda     e_ti+4
        and     #$00FF
        sta     e_ppid
        rts
:       inx
        cpx     #16
        bcc     @l
        rts
; -> C set when the parent has ended
parent_alive:
        lda     e_ppid
        beq     @gone
        ldx     #0
@l:     phx
        txa
        ldx     #.loword(e_ti)
        ldy     #^e_ti
        sys     SYS_TINFO
        plx
        lda     e_ti
        and     #$00FF
        cmp     e_ppid
        bne     :+
        lda     e_ti+1
        and     #$00FF
        cmp     #4                      ; a zombie has ended
        beq     @gone
        clc
        rts
:       inx
        cpx     #16
        bcc     @l
@gone:  sec
        rts

; ---------------------------------------------------------------- loading
; e_path -> C clear: loaded (MST_STOPPED), else C set (MST_ERROR, e_err)
e_load: jsr     e_stop
        jsr     unload
        lda     #MST_LOADING
        sta     e_state
        stz     e_err
        jsr     send_status
        ldx     #MI_SIZEOF - 2          ; the info block cleared
:       stz     e_info,x
        dex
        dex
        bpl     :-
        ; the size (0: not known, a URL may not say)
        lda     #.loword(e_path)
        sta     e_stb
        lda     #^e_path
        sta     e_stb+2
        lda     #.loword(e_stat)
        sta     e_stb+3
        lda     #^e_stat
        sta     e_stb+5
        ldx     #.loword(e_stb)
        ldy     #^e_stb
        sys     SYS_STAT
        bcc     :+
        jmp     lfail
:       lda     e_stat
        sta     e_size
        sta     e_info+MI_SIZE
        lda     e_stat+2
        sta     e_size+2
        sta     e_info+MI_SIZE+2
        ldx     #.loword(e_path)
        ldy     #^e_path
        lda     #O_READ
        sys     SYS_OPEN
        bcc     :+
        jmp     lfail
:       sta     e_fh
        lda     #1
        sta     e_open
        ; the head
        stz     e_hpos
        lda     #.loword(e_hbuf)
        sta     e_rb+1
        lda     #^e_hbuf
        sta     e_rb+3
        lda     #HBUF
        jsr     rd_file
        bcc     :+
        jmp     lfail
:       sta     e_hn
        stz     e_got
        stz     e_got+2
        lda     e_hn                    ; WAV: "RIFF" .... "WAVE"
        cmp     #12
        bcc     :+
        lda     e_hbuf
        cmp     #'R' | 'I' << 8
        bne     :+
        lda     e_hbuf+2
        cmp     #'F' | 'F' << 8
        bne     :+
        lda     e_hbuf+8
        cmp     #'W' | 'A' << 8
        bne     :+
        jmp     wav_load
:       lda     e_hn                    ; MIDI: "MThd"
        cmp     #14
        bcc     :+
        lda     e_hbuf
        cmp     #'M' | 'T' << 8
        bne     :+
        lda     e_hbuf+2
        cmp     #'h' | 'd' << 8
        bne     :+
        jmp     mid_load
:       jmp     mod_load

; the load failed with A: the file closed, the memory freed
lfail:  pha
        jsr     fclose
        jsr     unload
        pla
        jsr     set_err
        sec
        rts
fmt_bad:
        lda     #EMS_FORMAT
        bra     lfail
nomem:  lda     #ENOMEM
        bra     lfail

fclose: lda     e_open
        beq     :+
        stz     e_open
        lda     e_fh
        sys     SYS_CLOSE
:       rts

; every bank of the song freed
unload: lda     e_nb
        beq     @c
:       dec     e_nb
        lda     e_b0
        clc
        adc     e_nb
        sys     SYS_BFREE
        lda     e_nb
        bne     :-
@c:     lda     e_cb
        beq     :+
        sys     SYS_BFREE
        stz     e_cb
:       stz     e_kind
        stz     mp_mod
        stz     mp_mod+2
        rts

; read A bytes from the file to e_rb's buffer (e_rb+1: u24) -> A = bytes (C set: error)
rd_file:
        sta     e_rb+4
        lda     e_fh
        sep     #$20
        .a8
        sta     e_rb
        rep     #$20
        .a16
        ldx     #.loword(e_rb)
        ldy     #^e_rb
        sys     SYS_READ
        rts

; A = banks wanted -> a run of consecutive banks (e_b0, e_nb); C set: not enough memory
alloc_run:
        sta     e_want
        stz     e_nb
        stz     e_nsp
@l:     lda     e_nb
        cmp     e_want
        bcs     @ok
        sys     SYS_BALLOC
        bcs     @fail
        ldx     e_nb
        beq     @new
        tax                             ; X = the bank
        sec
        sbc     e_nb
        cmp     e_b0                    ; the next one of the run?
        bne     @gap
        inc     e_nb
        bra     @l
@gap:   phx
        jsr     @spare                  ; the run so far is put aside
        pla
@new:   sta     e_b0
        lda     #1
        sta     e_nb
        bra     @l
@ok:    jsr     @free
        clc
        rts
@fail:  jsr     @free
        jsr     @spare
        jsr     @free
        stz     e_nb
        sec
        rts
@spare: lda     e_nb                    ; e_b0 .. + nb - 1 onto the spare list
        beq     :++
:       dec     e_nb
        lda     e_b0
        clc
        adc     e_nb
        ldx     e_nsp
        cpx     #128
        bcs     :+
        sta     e_spare,x
        inx
        inx
        stx     e_nsp
        lda     e_nb
        bne     :-
:       rts
@free:  ldx     e_nsp                   ; the spare banks back
        beq     :+
        dex
        dex
        stx     e_nsp
        lda     e_spare,x
        sys     SYS_BFREE
        bra     @free
:       rts

; banks for A:X bytes (+ 1 bank of headroom when the size is not known) -> e_b0, e_nb
banks_for:
        cpx     #0                      ; ceil(bytes / 65536)
        beq     :+
        inc     a
:       cmp     #0
        bne     :+
        lda     #1
:       jmp     alloc_run

; copy e_n bytes from the head (e_hbuf + e_hpos) to [e_q] (keeps it in the bank) -> e_q moved
; on, e_hpos too
hd_copy:
        lda     e_n
        beq     @x
        ldx     e_hpos
        ldy     #0
        sep     #$20
        .a8
:       lda     e_hbuf,x
        sta     [e_q],y
        inx
        iny
        cpy     e_n
        bcc     :-
        rep     #$20
        .a16
        stx     e_hpos
        tya
        clc
        adc     e_q
        sta     e_q
@x:     rts

; the rest of the file into e_q (u24) onwards, pieces that keep inside a bank; e_size (or 0)
; for the progress -> C set: error A; e_got = bytes read (+ the head's)
rd_rest:
@l:     lda     e_q                     ; room to the end of this bank
        eor     #$FFFF
        inc     a
        beq     :+
        cmp     #CHUNK
        bcc     :++
:       lda     #CHUNK
:       sta     e_n
        lda     e_lim                   ; no more than e_lim bytes in all
        sec
        sbc     e_got
        tax
        lda     e_lim+2
        sbc     e_got+2
        bne     :+
        txa
        beq     @eof
        cmp     e_n
        bcs     :+
        sta     e_n
:       ; past the memory we have? (e_q bank > the last bank)
        lda     e_q+2
        sec
        sbc     e_b0
        cmp     e_nb
        bcc     :+
        lda     #ENOMEM                 ; the file is longer than said
        sec
        rts
:       lda     e_q
        sta     e_rb+1
        lda     e_q+2
        sta     e_rb+3
        lda     e_n
        jsr     rd_file
        bcc     :+
        rts
:       sta     e_t
        clc
        adc     e_got
        sta     e_got
        bcc     :+
        inc     e_got+2
:       lda     e_t
        clc
        adc     e_q
        sta     e_q
        bcc     :+
        inc     e_q+2
:       lda     e_t                     ; a full piece: more may come
        cmp     e_n
        php
        jsr     progress
        plp
        beq     @l
@eof:   clc                             ; the end of the file
        rts

; MST_LOADING with the percent of e_got / e_size
progress:
        lda     e_size+2                ; percent = (got >> 8) * 100 / (size >> 8)
        ora     e_size
        beq     @x
        lda     e_got+1
        sta     d_n
        lda     e_got+3
        and     #$00FF
        sta     d_n+2
        lda     #100
        jsr     mul32
        lda     e_size+1
        sta     d_d
        lda     e_size+3
        and     #$00FF
        beq     :+
        lsr     a                       ; (larger than 16 MB: never)
        ror     d_d
:       lda     d_d
        bne     :+
        inc     d_d
:       jsr     div32
        lda     d_n
        cmp     #100
        bcc     :+
        lda     #100
:       sta     e_err
        jmp     send_status
@x:     rts

; d_n (u32) * A (u16, small) -> d_n
mul32:  sta     m_t
        lda     d_n
        sta     m_r
        lda     d_n+2
        sta     m_r+2
        stz     d_n
        stz     d_n+2
@l:     lsr     m_t
        bcc     :+
        lda     d_n
        clc
        adc     m_r
        sta     d_n
        lda     d_n+2
        adc     m_r+2
        sta     d_n+2
:       asl     m_r
        rol     m_r+2
        lda     m_t
        bne     @l
        rts

; d_n (u32) / d_d (u16) -> d_n quotient, d_r remainder
div32:  stz     d_r
        ldx     #32
@l:     asl     d_n
        rol     d_n+2
        rol     d_r
        bcs     :+
        lda     d_r
        cmp     d_d
        bcc     @n
:       lda     d_r
        sec
        sbc     d_d
        sta     d_r
        inc     d_n
@n:     dex
        bne     @l
        rts

; ---------------------------------------------------------------- MOD
mod_load:
        lda     e_hn
        cmp     #600 + 4
        bcs     :+
        jmp     fmt_bad
:       lda     #KIND_MOD
        sta     e_kind
        ; 31 samples: a known tag at 1080
        stz     e_m15
        lda     e_hn
        cmp     #HBUF
        bcc     @old
        lda     e_hbuf+1080
        sta     mp_tag
        lda     e_hbuf+1082
        sta     mp_tag+2
        ldx     #0
:       lda     tags,x
        beq     :+
        cmp     e_hbuf+1080
        bne     @nt
        lda     tags+2,x
        cmp     e_hbuf+1082
        beq     @new
@nt:    inx
        inx
        inx
        inx
        bra     :-
:       lda     e_hbuf+1081             ; "nCHN"
        cmp     #'C' | 'H' << 8
        bne     @old
        lda     e_hbuf+1083
        and     #$00FF
        cmp     #'N'
        beq     @new
@old:   lda     #1                      ; 15 samples: song length 1-128, orders below 64
        sta     e_m15
        lda     e_hbuf+470
        and     #$00FF
        beq     @bad
        cmp     #129
        bcs     @bad
        ldx     #0
:       lda     e_hbuf+472,x
        and     #$00FF
        cmp     #64
        bcs     @bad
        inx
        cpx     #128
        bcc     :-
        bra     @new
@bad:   jmp     fmt_bad
@new:   ; memory: the file (+ 484 for the 15-sample header made 31) in a run of banks
        lda     #$FFFF                  ; (read to the end)
        sta     e_lim
        sta     e_lim+2
        lda     e_size
        ora     e_size+2
        bne     :+
        lda     #16                     ; size not known: up to 1 MB
        ldx     #0
        bra     :++
:       lda     e_size
        clc
        adc     #484
        tax
        lda     e_size+2
        adc     #0
:       jsr     banks_for
        bcc     :+
        jmp     nomem
:       sys     SYS_BALLOC              ; the copy buffer (a sample offset into a loop)
        bcc     :+
        jmp     nomem
:       sta     e_cb
        sta     mp_cbuf+2
        stz     mp_cbuf
        stz     mp_mod
        lda     e_b0
        sta     mp_mod+2
        sta     e_q+2
        stz     e_q
        lda     e_m15
        bne     @m15
        lda     #HBUF                   ; the head as it is
        sta     e_n
        jsr     hd_copy
        bra     @rest
@m15:   lda     #470                    ; title and 15 samples
        sta     e_n
        jsr     hd_copy
        lda     #480                    ; samples 16-31: nothing
        sta     e_n
        ldy     #0
        lda     #0
:       sta     [e_q],y
        iny
        iny
        cpy     e_n
        bcc     :-
        lda     e_q
        clc
        adc     #480
        sta     e_q
        lda     #130                    ; song length, restart, orders
        sta     e_n
        jsr     hd_copy
        lda     #'M' | '.' << 8         ; the tag of a 4-channel module
        sta     [e_q]
        ldy     #2
        lda     #'K' | '.' << 8
        sta     [e_q],y
        lda     e_q
        clc
        adc     #4
        sta     e_q
        lda     e_hn                    ; the rest of the head: patterns
        sec
        sbc     e_hpos
        sta     e_n
        jsr     hd_copy
@rest:  lda     e_q                     ; bytes so far
        sta     e_got
        stz     e_got+2
        jsr     rd_rest
        bcc     :+
        jmp     lfail
:       jsr     fclose
        lda     e_q                     ; the length in memory
        sta     mp_mlen
        lda     e_q+2
        sec
        sbc     e_b0
        sta     mp_mlen+2
        jsr     mp_open
        bcc     :+
        jmp     lfail
:       lda     e_vol
        jsr     mp_setvol
        lda     e_sep
        jsr     mp_setsep
        lda     e_loop
        sta     mp_loop
        sep     #$20                    ; the info block
        .a8
        lda     #KIND_MOD
        sta     e_info+MI_KIND
        lda     mp_nch
        sta     e_info+MI_NCHAN
        lda     mp_slen
        sta     e_info+MI_SLEN
        lda     mp_npat
        sta     e_info+MI_NPAT
        lda     #31
        ldx     e_m15
        beq     :+
        lda     #15
:       sta     e_info+MI_NSMP
        rep     #$20
        .a16
        lda     e_m15
        bne     :+
        lda     mp_tag
        sta     e_info+MI_TAG
        lda     mp_tag+2
        sta     e_info+MI_TAG+2
:       lda     #MST_STOPPED
        sta     e_state
        jsr     send_status
        clc
        rts

; ---------------------------------------------------------------- MIDI (SMF on OPL2)
mid_load:
        ; Check OPL2 hardware before allocating/reading
        lda     #$FFFE
        ldx     #0
        sys     SYS_OPLW
        bcc     :+
        lda     #ENODEV
        jmp     lfail
:       ; Allocate consecutive banks for the file (unknown size: 4 banks = 256 KB)
        lda     e_size
        ora     e_size+2
        bne     @known
        lda     #4
        jsr     alloc_run
        jcs     nomem
        stz     e_lim
        lda     #4
        sta     e_lim+2
        bra     @rd
@known: lda     e_size+2
        ldx     e_size
        jsr     banks_for
        jcs     nomem
        lda     e_size
        sta     e_lim
        lda     e_size+2
        sta     e_lim+2
@rd:    stz     e_q
        lda     e_b0
        sta     e_q+2
        stz     e_hpos
        lda     e_hn
        sta     e_n
        jsr     hd_copy
        lda     e_q
        sta     e_got
        stz     e_got+2
        jsr     rd_rest
        jcs     lfail
        jsr     fclose
        ; Parse SMF header + tracks and pre-scan duration
        stz     mid_buf
        lda     e_b0
        sta     mid_buf+2
        lda     e_got
        sta     mid_len
        lda     e_got+2
        sta     mid_len+2
        jsr     mid_open
        jcs     lfail
        lda     #KIND_MID
        sta     e_kind
        lda     e_vol
        jsr     mid_setvol
        lda     e_loop
        sta     mid_loop
        sep     #$20
        .a8
        lda     #KIND_MID
        sta     e_info+MI_KIND
        lda     #8
        sta     e_info+MI_NCHAN
        lda     mid_ntrks
        sta     e_info+MI_NPAT
        lda     mid_bpm
        sta     e_info+MI_BPM
        rep     #$20
        .a16
        lda     mid_tot_tenths
        sta     e_info+MI_TENTHS
        lda     #'M' | 'I' << 8
        sta     e_info+MI_TAG
        lda     #'D' | 'I' << 8
        sta     e_info+MI_TAG+2
        lda     #MST_STOPPED
        sta     e_state
        jsr     send_status
        clc
        rts

; ---------------------------------------------------------------- WAV
; RIFF chunks: "fmt " (PCM 8/16-bit, 1-2 channels) and "data"
wav_load:
        lda     #12
        sta     e_hpos
@ch:    lda     e_hpos                  ; a chunk header in the head?
        clc
        adc     #8
        cmp     e_hn
        bcc     :+
        beq     :+
        jmp     fmt_bad
:       ldx     e_hpos
        lda     e_hbuf+4,x              ; its size
        sta     e_t
        lda     e_hbuf+6,x
        sta     e_t+2
        lda     e_hbuf,x
        cmp     #'f' | 'm' << 8
        bne     @nf
        lda     e_hbuf+2,x
        cmp     #'t' | ' ' << 8
        bne     @nf
        lda     e_hbuf+8,x              ; format 1 (PCM) or $FFFE (extensible)
        cmp     #1
        beq     :+
        cmp     #$FFFE
        jne     fmt_bad
:       lda     e_hbuf+10,x
        sta     e_wch
        lda     e_hbuf+12,x
        sta     e_wrate
        lda     e_hbuf+14,x
        jne     fmt_bad                 ; (above 65535 a second)
        lda     e_hbuf+22,x
        sta     e_wbits
        bra     @nx
@nf:    lda     e_hbuf,x
        cmp     #'d' | 'a' << 8
        bne     @nx
        lda     e_hbuf+2,x
        cmp     #'t' | 'a' << 8
        beq     @data
@nx:    lda     e_t+2                   ; the next chunk (even size)
        bne     @far
        lda     e_t
        inc     a
        and     #$FFFE
        clc
        adc     #8
        bcs     @far
        adc     e_hpos
        bcs     @far
        sta     e_hpos
        jmp     @ch
@far:   jmp     fmt_bad
@data:  txa
        clc
        adc     #8
        sta     e_hpos
        lda     e_wch                   ; 1 or 2 channels, 8 or 16 bits, a rate
        beq     @far
        cmp     #3
        bcs     @far
        lda     e_wbits
        cmp     #8
        beq     :+
        cmp     #16
        bne     @far
:       lda     e_wrate
        cmp     #1000
        bcc     @far
        ; the data's size: no more than the file holds
        lda     e_t
        sta     e_wdata
        lda     e_t+2
        sta     e_wdata+2
        lda     e_size
        ora     e_size+2
        beq     :+
        lda     e_size                  ; file - start of data
        sec
        sbc     e_hpos
        tax
        lda     e_size+2
        sbc     #0
        cmp     e_wdata+2
        bcc     :++
        bne     :+
        cpx     e_wdata
        bcs     :+
        stx     e_wdata
:       bra     :++
:       sta     e_wdata+2
        stx     e_wdata
:       ; frames = data / (channels * bytes)
        lda     e_wch
        sta     e_t
        lda     e_wbits
        cmp     #16
        bne     :+
        asl     e_t
:       lda     e_wdata                 ; whole frames only
        sta     d_n
        lda     e_wdata+2
        sta     d_n+2
        lda     e_t
        sta     d_d
        jsr     div32
        lda     d_n
        sta     e_wfr
        sta     e_info+MI_FRAMES
        lda     d_n+2
        sta     e_wfr+2
        sta     e_info+MI_FRAMES+2
        ora     e_wfr
        bne     :+
        jmp     fmt_bad
:       lda     d_n                     ; data = frames * frame bytes
        sta     e_wdata
        lda     d_n+2
        sta     e_wdata+2
        lda     e_t
        jsr     mul32w
        ; pitch = rate * 16384 / 48000 = rate * 1024 / 3000
        lda     e_wrate
        sta     d_n
        stz     d_n+2
        lda     #1024
        jsr     mul32
        lda     #3000
        sta     d_d
        jsr     div32
        lda     d_n+2
        jne     fmt_bad                 ; above 196 kHz
        lda     d_n
        sta     e_wpitch
        ; tenths = frames * 10 / rate
        lda     e_wfr
        sta     d_n
        lda     e_wfr+2
        sta     d_n+2
        lda     #10
        jsr     mul32
        lda     e_wrate
        sta     d_d
        jsr     div32
        lda     d_n
        sta     e_info+MI_TENTHS
        ; memory: the data (stereo: left then right, each frames * bytes a sample)
        lda     e_wdata+2
        ldx     e_wdata
        jsr     banks_for
        bcc     :+
        jmp     nomem
:       sys     SYS_BALLOC              ; a bank to read stereo pieces into
        bcc     :+
        jmp     nomem
:       sta     e_cb
        lda     #KIND_WAV
        sta     e_kind
        stz     e_q
        lda     e_b0
        sta     e_q+2
        stz     e_got
        stz     e_got+2
        lda     e_wch
        cmp     #2
        beq     @st
        ; mono: straight into memory (the head's part first)
        lda     e_hn
        sec
        sbc     e_hpos
        jsr     @hcap
        jsr     hd_copy
        lda     e_q
        sta     e_got
        lda     e_wdata
        sta     e_lim
        lda     e_wdata+2
        sta     e_lim+2
        jsr     rd_rest
        bcc     :+
        jmp     lfail
:       jsr     fclose
        lda     e_wbits                 ; 8-bit: unsigned -> signed
        cmp     #8
        jne     @done
        lda     e_wdata
        sta     e_t
        lda     e_wdata+2
        sta     e_t+2
        jsr     flip_all
        jmp     @done
@st:    ; stereo: pieces into the bank e_cb, split into the two halves
        lda     e_wfr                   ; the right half starts at frames * bytes
        sta     d_n
        lda     e_wfr+2
        sta     d_n+2
        lda     e_wbits
        lsr     a
        lsr     a
        lsr     a
        jsr     mul32
        lda     d_n
        sta     e_r
        lda     d_n+2
        clc
        adc     e_b0
        sta     e_r+2                   ; e_q left, e_r right
        lda     e_hn
        sec
        sbc     e_hpos
        jsr     @hcap
        sta     e_n
        stz     e_p
        lda     e_cb
        sta     e_p+2
        jsr     hd_copyp                ; the head's part to the bank's start
        lda     e_n
        sta     e_t
@sl:    lda     e_t                     ; whole frames: the rest waits for the next piece
        jsr     split
        jsr     progress
        lda     e_got+2                 ; all frames?
        cmp     e_wdata+2
        bcc     :+
        lda     e_got
        cmp     e_wdata
        bcs     @sd
:       lda     e_left                  ; the bytes left over to the bank's start, then a piece
        sta     e_t
        lda     e_cb
        sta     e_rb+3
        lda     e_left
        sta     e_rb+1
        lda     #CHUNK
        jsr     rd_file
        bcc     :+
        jmp     lfail
:       cmp     #0
        beq     @sd
        clc
        adc     e_t
        sta     e_t
        bra     @sl
@sd:    jsr     fclose
@done:  lda     e_cb                    ; the bank is not needed any more
        sys     SYS_BFREE
        stz     e_cb
        sep     #$20
        .a8
        lda     #KIND_WAV
        sta     e_info+MI_KIND
        lda     e_wch
        sta     e_info+MI_NCHAN
        lda     e_wbits
        sta     e_info+MI_BITS
        rep     #$20
        .a16
        lda     e_wrate
        sta     e_info+MI_RATE
        lda     #'W' | 'A' << 8
        sta     e_info+MI_TAG
        lda     #'V' | ' ' << 8
        sta     e_info+MI_TAG+2
        stz     e_wpos
        stz     e_wpos+2
        stz     e_tenths
        stz     e_wfrac
        lda     #MST_STOPPED
        sta     e_state
        jsr     send_status
        clc
        rts
; A = bytes in the head -> A = at most the data's size
@hcap:  sta     e_n
        lda     e_wdata+2
        bne     :+
        lda     e_wdata
        cmp     e_n
        bcs     :+
        sta     e_n
:       lda     e_n
        rts

; d_n * A -> e_wdata... (frames * frame bytes: e_wdata = d_n * A)
mul32w: jsr     mul32
        lda     d_n
        sta     e_wdata
        lda     d_n+2
        sta     e_wdata+2
        rts

; copy e_n head bytes to [e_p]
hd_copyp:
        lda     e_n
        beq     @x
        ldx     e_hpos
        ldy     #0
        sep     #$20
        .a8
:       lda     e_hbuf,x
        sta     [e_p],y
        inx
        iny
        cpy     e_n
        bcc     :-
        rep     #$20
        .a16
        stx     e_hpos
@x:     rts

; A = bytes at the start of bank e_cb: the whole frames go to [e_q] (left) and [e_r] (right),
; e_got counts them (no more than e_wdata); e_left = the bytes of a cut frame, moved to the start
split:  sta     e_t
        lda     e_wdata                 ; not past the data
        sec
        sbc     e_got
        tax
        lda     e_wdata+2
        sbc     e_got+2
        bne     :+
        cpx     e_t
        bcs     :+
        stx     e_t
:       stz     e_p
        lda     e_cb
        sta     e_p+2
        lda     e_wbits
        cmp     #16
        beq     @w
@b:     lda     e_t                     ; 8-bit frames: 2 bytes
        cmp     #2
        bcc     @rest
        lda     [e_p]
        eor     #$8080                  ; unsigned -> signed
        sep     #$20
        .a8
        sta     [e_q]
        xba
        sta     [e_r]
        rep     #$20
        .a16
        jsr     @inq
        jsr     @inr
        inc     e_p
        inc     e_p
        dec     e_t
        dec     e_t
        lda     e_got
        clc
        adc     #2
        sta     e_got
        bcc     @b
        inc     e_got+2
        bra     @b
@w:     lda     e_t                     ; 16-bit frames: 4 bytes
        cmp     #4
        bcc     @rest
        lda     [e_p]
        sta     [e_q]
        ldy     #2
        lda     [e_p],y
        sta     [e_r]
        jsr     @inq
        jsr     @inq
        jsr     @inr
        jsr     @inr
        lda     e_p
        clc
        adc     #4
        sta     e_p
        lda     e_t
        sec
        sbc     #4
        sta     e_t
        lda     e_got
        clc
        adc     #4
        sta     e_got
        bcc     @w
        inc     e_got+2
        bra     @w
@rest:  lda     e_t                     ; 0-3 bytes of a cut frame to the bank's start
        sta     e_left
        beq     :++
        stz     e_s
        lda     e_cb
        sta     e_s+2
        ldy     #0
        sep     #$20
        .a8
:       lda     [e_p],y
        sta     [e_s],y
        iny
        cpy     e_left
        bcc     :-
        rep     #$20
        .a16
:       rts
@inq:   inc     e_q
        bne     :+
        inc     e_q+2
:       rts
@inr:   inc     e_r
        bne     :+
        inc     e_r+2
:       rts

; e_t (u32) bytes from e_b0:0000: xor $80 (8-bit unsigned -> signed)
flip_all:
        stz     e_p
        lda     e_b0
        sta     e_p+2
@l:     lda     e_t+2
        bne     :+
        lda     e_t
        beq     @x
        cmp     #2
        bcc     @one
:       lda     [e_p]
        eor     #$8080
        sta     [e_p]
        lda     e_t
        sec
        sbc     #2
        sta     e_t
        bcs     :+
        dec     e_t+2
:       lda     e_p
        clc
        adc     #2
        sta     e_p
        bcc     @l
        inc     e_p+2
        bra     @l
@one:   sep     #$20
        .a8
        lda     [e_p]
        eor     #$80
        sta     [e_p]
        rep     #$20
        .a16
@x:     rts

; ---- WAV playing: voices 7 (mono) or 6 and 7 (left, right) ----
; e_arg = the position in 256ths: the voices start there
wav_seek:
        lda     e_arg                   ; frames = (frames >> 8) * arg
        and     #$00FF
        sta     e_wfrac
        lda     e_wfr+1
        sta     d_n
        lda     e_wfr+3
        and     #$00FF
        sta     d_n+2
        lda     e_wfrac
        jsr     mul32
        lda     d_n
        sta     e_wpos
        lda     d_n+2
        sta     e_wpos+2
        stz     e_wrem
        lda     e_wpos                  ; the time there
        sta     d_n
        lda     e_wpos+2
        sta     d_n+2
        lda     #10
        jsr     mul32
        lda     e_wrate
        sta     d_d
        jsr     div32
        lda     d_n
        sta     e_tenths
        lda     e_state
        cmp     #MST_PLAYING
        beq     :+
        cmp     #MST_PAUSED
        bne     @x
:       jsr     wav_start
        lda     e_state
        cmp     #MST_PAUSED
        bne     :+
        jsr     wav_hold
        jmp     send_status
:       jsr     wav_timer
@x:     jmp     send_status

; both voices from e_wpos
wav_start:
        lda     #$FFFF
        sys     SYS_SSTOP
        lda     e_wpos                  ; the sample's offset: pos * bytes
        sta     d_n
        lda     e_wpos+2
        sta     d_n+2
        lda     e_wbits
        lsr     a
        lsr     a
        lsr     a
        jsr     mul32
        lda     e_wfr                   ; samples left
        sec
        sbc     e_wpos
        sta     e_sp+3
        lda     e_wfr+2
        sbc     e_wpos+2
        sep     #$20
        .a8
        sta     e_sp+5
        rep     #$20
        .a16
        ora     e_sp+3
        jeq     @x
        stz     e_sp+6
        stz     e_sp+7
        lda     e_wpitch
        sta     e_sp+9
        lda     #SPF_KEEP
        ldx     e_wbits
        cpx     #16
        bne     :+
        ora     #SPF_16
:       sta     e_sp+13                 ; (+14 the voice below)
        jsr     wav_lr
        lda     d_n                     ; left (or mono): e_b0:0000 + offset
        sta     e_sp
        lda     d_n+2
        clc
        adc     e_b0
        sep     #$20
        .a8
        sta     e_sp+2
        lda     e_wl
        sta     e_sp+11
        lda     e_wr
        ldx     e_wch
        cpx     #2
        bne     :+
        lda     #0
:       sta     e_sp+12
        lda     #7
        cpx     #2
        bne     :+
        lda     #6
:       sta     e_sp+14
        stz     e_sp+15
        rep     #$20
        .a16
        ldx     #.loword(e_sp)
        ldy     #^e_sp
        sys     SYS_SPLAY
        lda     e_wch
        cmp     #2
        bne     @x
        lda     e_wfr                   ; right: + frames * bytes
        sta     e_t
        lda     e_wfr+2
        sta     e_t+2
        lda     e_wbits
        cmp     #16
        bne     :+
        asl     e_t
        rol     e_t+2
:       lda     e_sp
        clc
        adc     e_t
        sta     e_sp
        lda     e_sp+2
        and     #$00FF
        adc     e_t+2
        sep     #$20
        .a8
        sta     e_sp+2
        lda     #0
        sta     e_sp+11
        lda     e_wr
        sta     e_sp+12
        lda     #7
        sta     e_sp+14
        rep     #$20
        .a16
        ldx     #.loword(e_sp)
        ldy     #^e_sp
        sys     SYS_SPLAY
@x:     rts

; the volumes: mono 3 * vol each side, stereo 4 * vol on its side (at most 255)
wav_lr: lda     e_vol
        asl     a
        ldx     e_wch
        cpx     #2
        beq     :+
        clc
        adc     e_vol
        bra     :++
:       asl     a
:       cmp     #256
        bcc     :+
        lda     #255
:       sta     e_wl
        sta     e_wr
        rts

; the voices hold (pause)
wav_hold:
        lda     #7
        ldx     #0
        ldy     #0
        sys     SYS_SSET
        lda     #6
        ldx     #0
        ldy     #0
        sys     SYS_SSET
        stz     e_wlev
        rts
; their pitch and volumes back (resume, a new volume)
wav_vols:
        jsr     wav_lr
        lda     e_wch
        cmp     #2
        beq     :+
        lda     e_wr
        xba
        ora     e_wl
        tay
        lda     #7
        ldx     e_wpitch
        sys     SYS_SSET
        rts
:       lda     e_wl
        tay
        lda     #6
        ldx     e_wpitch
        sys     SYS_SSET
        lda     e_wr
        xba
        tay
        lda     #7
        ldx     e_wpitch
        sys     SYS_SSET
        rts

; every 20 ms: the position (rate / 50 frames), the time, the level, the end
wav_tick:
        lda     e_wrate                 ; rate / 50, the remainder carried
        sta     d_n
        stz     d_n+2
        lda     #50
        sta     d_d
        jsr     div32
        lda     d_n
        clc
        adc     e_wpos
        sta     e_wpos
        bcc     :+
        inc     e_wpos+2
:       lda     e_wrem
        clc
        adc     d_r
        cmp     #50
        bcc     :+
        sbc     #50
        inc     e_wpos
        bne     :+
        inc     e_wpos+2
:       sta     e_wrem
        lda     e_wus                   ; tenths: every 5 ticks
        inc     a
        cmp     #5
        bcc     :+
        inc     e_tenths
        lda     #0
:       sta     e_wus
        ; the end?
        lda     e_wpos+2
        cmp     e_wfr+2
        bcc     @pos
        bne     @end
        lda     e_wpos
        cmp     e_wfr
        bcc     @pos
@end:   lda     e_loop
        beq     :+
        stz     e_arg                   ; again from the start
        jmp     wav_seek
:       lda     #MST_ENDED
        sta     e_state
        stz     e_wlev
        jsr     idle_timer
        lda     e_mode
        cmp     #1
        bne     @x
        print   "Ended\n"
        exit    0
@x:     rts
@pos:   lda     e_wpos                  ; [2]: the position in 256ths
        sta     d_n
        lda     e_wpos+2
        sta     d_n+2
        lda     e_wfr+1
        sta     d_d
        lda     e_wfr+3
        and     #$00FF
        beq     :+
        lsr     a
        ror     d_d
        lsr     d_n+2
        ror     d_n
:       lda     d_d
        bne     :+
        inc     d_d
:       jsr     div32
        lda     d_n
        cmp     #256
        bcc     :+
        lda     #255
:       sta     e_wfrac
        ; the level: the sample at the place (left / mono), times the volume
        lda     e_wpos
        sta     d_n
        lda     e_wpos+2
        sta     d_n+2
        lda     e_wbits
        lsr     a
        lsr     a
        lsr     a
        jsr     mul32
        lda     d_n
        sta     e_p
        lda     d_n+2
        clc
        adc     e_b0
        sta     e_p+2
        lda     e_wbits
        cmp     #16
        bne     :+
        inc     e_p                     ; the high byte of a 16-bit sample
        bne     :+
        inc     e_p+2
:       lda     [e_p]
        and     #$00FF
        cmp     #$80
        bcc     :+
        eor     #$00FF
        inc     a
:       lsr     a                       ; 0-64
        sta     e_t
        lda     e_vol                   ; * vol / 64
        sta     e_t+2
        lda     #0
        ldx     e_t+2
        beq     :++
:       clc
        adc     e_t
        dex
        bne     :-
:       lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     e_wlev
        xba
        ora     e_wlev
        sta     e_wlev                  ; (both channels the same: a cheap meter)
        rts

; ---------------------------------------------------------------- the shell's text
print_title:
        lda     mp_mod
        sta     e_p
        lda     mp_mod+2
        and     #$00FF
        sta     e_p+2
        ldy     #0
:       lda     [e_p],y
        and     #$00FF
        beq     @x
        cmp     #32
        bcs     :+
        lda     #'.'
:       phy
        jsr     out_char
        ply
        iny
        cpy     #20
        bcc     :--
@x:     rts

print_err:
        print   "musicd: "
        lda     e_err
        cmp     #EMS_FORMAT
        bne     :+
        print   "not a module or WAV file it can play\n"
        rts
:       cmp     #ENOMEM
        bne     :+
        print   "not enough memory\n"
        rts
:       pha
        print   "error $"
        pla
        jsr     put_hex8
        print   "\n"
        rts

        .segment "RODATA"
p_self: .byte   "/SYSTEM/MUSICD.PRG", 0
tags:   .byte   "M.K.M!K!M&K!N.T.FLT4FLT84CHN6CHN8CHNCD81OKTAOCTA"
        .word   0

        .segment "BSS"
e_mode: .res    2                       ; 0 the shell's command, 1 its engine (-x), 2 a client's
e_loop: .res    2
e_cport: .res   2                       ; the client's port
e_port: .res    2                       ; ours
e_pid:  .res    2
e_ppid: .res    2
e_ms:   .res    2
e_state: .res   2
e_kind: .res    2
e_err:  .res    2
e_arg:  .res    2
e_vol:  .res    2
e_sep:  .res    2
e_t:    .res    4
e_n:    .res    2
e_tcnt: .res    2
e_tenths: .res  2
e_msg:  .res    16
e_sbuf: .res    16
e_sp:   .res    16                      ; a sample_play block (WAV)
e_ti:   .res    16
e_info: .res    MI_SIZEOF + 2
e_fh:   .res    2
e_open: .res    2
e_rb:   .res    8                       ; read's block
e_stb:  .res    6                       ; stat's block
e_stat: .res    10
e_size: .res    4
e_got:  .res    4
e_hn:   .res    2
e_hpos: .res    2
e_m15:  .res    2
e_b0:   .res    2                       ; the run of banks
e_nb:   .res    2
e_cb:   .res    2                       ; one more bank (copy buffer / stereo pieces)
e_want: .res    2
e_nsp:  .res    2
e_spare: .res   128
e_left: .res    2
e_lim:  .res    4
e_gen:  .res    2
e_endp: .res    2
e_msdiv: .res   2                       ; MIDI 200 Hz -> 50 Hz status divider
e_chk:  .res    2
e_drop: .res    2
e_np:   .res    2                       ; bytes waiting in e_pend
e_pend: .res    4 * 16
e_wch:  .res    2                       ; WAV: channels, rate, bits, frames, data bytes
e_wrate: .res   2
e_wbits: .res   2
e_wfr:  .res    4
e_wdata: .res   4
e_wpitch: .res  2
e_wpos: .res    4
e_wrem: .res    2
e_wus:  .res    2
e_wfrac: .res   2
e_wl:   .res    2
e_wr:   .res    2
e_wlev: .res    2
d_n:    .res    4
m_r:    .res    4                       ; mul32's
m_t:    .res    2
d_d:    .res    2
d_r:    .res    2
e_abuf: .res    130
e_path: .res    130
e_hbuf: .res    HBUF + 4
