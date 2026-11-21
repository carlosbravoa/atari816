; midplay.inc - Standard MIDI File (SMF 0 & 1) OPL2 (YM3812) replayer library
; (user/midplay.s -> build/midplay.o, linked into /SYSTEM/MUSICD.PRG).
;
; Use (all routines a16 i16; clobber A, X, Y; DBR = program's code bank):
;   1. Put the SMF file's u24 address in mid_buf (bank in mid_buf+2, offset 0) and its
;      length in bytes in mid_len (u24); jsr mid_open -> C set: error A (ENODEV or EMS_FORMAT)
;   2. jsr mid_play with A = start position in 256ths (0..255) -> C set: A = EAGAIN, another
;      program owns the OPL2 (0.27; mid_play takes it, mid_release gives it back)
;   3. Call mid_tick every MID_US (5000 us = 200 Hz). Returns A = MIDF_* flags:
;      MIDF_END = reached end of song (if mid_loop = 0, stopped; else restarted from 0).
;   4. mid_pause / mid_resume / mid_stop / mid_setvol (A = 0..64); (0.27) mid_release: stop
;      and give the OPL2 back; mid_cue (A = position) the same as mid_play when paused: it
;      stays paused, nothing sounds before mid_resume

        .import mid_open, mid_play, mid_tick, mid_pause, mid_resume, mid_stop, mid_setvol
        .import mid_release, mid_cue
        .import mid_bank_init, mid_load_wopl
        .import mid_buf, mid_len, mid_loop
        .import mid_ntrks, mid_bpm, mid_tot_tenths, mid_tenths, mid_frac, mid_lev, mid_state
        .import mid_title

MID_US    = 5000        ; 200 Hz MIDI tick period (5 ms)
MIDF_END  = 2           ; mid_tick result: song ended
MIDS_STOP = 0
MIDS_PLAY = 1
MIDS_PAUSE = 2
