; modplay.inc - (0.26) the MOD replayer library (user/modplay.s -> build/modplay.o; the SDK's
; lib/modplay.o). It plays a ProTracker module that lies in the program's own memory on Lau's
; voices (one voice per channel: voices 8 - N .. 7 for N channels, so 4-channel music leaves
; voices 0-3 to the program's sound effects (SP_ANY takes the lowest free voice)).
;
; Use (all routines a16 i16; they clobber A, X, Y; DBR = the program's code bank):
;   1. put the module's u24 address in mp_mod and its length in bytes in mp_mlen (u24), and
;      optionally a 64 KB bank of scratch memory in mp_cbuf (u24, 0 = none; used for a sample
;      offset 9xx into a sample's loop); jsr mp_open -> C set: not a module (A = MPE_*)
;   2. jsr mp_play with A = the first order: the first tick runs at once
;   3. call mp_tick every mp_tickus microseconds (u24): the best is the music timer
;      (SYS_STIMER: a port message every period, read by a priority-0 task, as MUSICD does);
;      a game may instead call it from its frame loop when mp_due says a tick is due.
;      mp_tick returns A = MPF_* flags: MPF_TEMPO the tempo changed (give the timer the new
;      mp_tickus), MPF_END the song reached its end (mp_loop 0: it has stopped).
;   4. mp_pause / mp_resume / mp_stop, mp_seek (A = order), mp_setvol (A = 0-64),
;      mp_setsep (A = 0-64).
; The voices are started with SPF_KEEP | mp_keep... (mp_flags bit MPO_KEEP): music plays on while
; the classic Atari is shown.

        .import mp_open, mp_play, mp_tick, mp_pause, mp_resume, mp_stop, mp_seek
        .import mp_setvol, mp_setsep
        .import mp_mod, mp_mlen, mp_cbuf, mp_loop, mp_meter, mp_keep
        .import mp_nch, mp_slen, mp_npat, mp_nsmp, mp_order, mp_row, mp_pat, mp_speed, mp_bpm
        .import mp_tickus, mp_tenths, mp_lev, mp_state, mp_tag

MPF_TEMPO = 1           ; mp_tick result: give the timer mp_tickus
MPF_END   = 2           ;   the song ended (mp_loop = 0: stopped; else it goes on from the start)
MPE_FORMAT = $FE        ; mp_open: not a module it can play
MPS_STOP  = 0           ; mp_state
MPS_PLAY  = 1
MPS_PAUSE = 2
