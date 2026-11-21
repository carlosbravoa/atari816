; music.inc - (0.26) the music engine's messages: /SYSTEM/MUSICD.PRG, which plays a module (MOD)
; or a WAV file on Lau for another program (Music, BASIC's MUSIC, a game) or from the shell.
; ABI.md, "Music (0.26)" has the whole story. All messages are 16 bytes (send / recv).
;
; Starting it: spawn "/SYSTEM/MUSICD.PRG" with the arguments "-p PORT" at priority 0, where
; PORT is a port the caller created (port_create): the engine creates its own port and sends
; MS_HELLO to PORT, then waits for commands. It ends at MC_QUIT, or by itself within a second
; when its parent (the caller) has ended. From the shell: "musicd [-l] FILE" plays FILE (once,
; or -l: again and again) and returns at its end (ctrl-C stops it).
;
; The engine sends MS_STATUS after every tick while it plays (50 a second at 125 BPM) and at
; every change of state; a client reads them with recv | RV_POLL (no waiting) until EAGAIN and
; keeps the last one. When the client's queue is full, statuses are dropped (no harm).

; ---- commands: client -> engine (byte 0) ----
MC_PATH  = 1    ; [1] offset 0, 14, 28, ... 112; [2..15] 14 characters of the path (zero-terminated
                ;   in the last piece; at most 127 characters, a URL or /PC: path too)
MC_LOAD  = 2    ; load the path sent; [1] MCL_PLAY: start playing when loaded. Stops what plays
MCL_PLAY = 1
MC_PLAY  = 3    ; [1] order to start from (MOD; WAV: 0); $FF: resume after a pause / go on
MC_PAUSE = 4    ; pause (the voices hold their place: pitch 0, volume 0); MC_PLAY $FF resumes
MC_STOP  = 5    ; stop; the next MC_PLAY starts from [1]
MC_SEEK  = 6    ; [1] MOD: order 0 .. song length - 1; WAV: position in 256ths of the length
MC_VOL   = 7    ; [1] the music volume 0-64 (default 64; Lau's master volume = the system's sound
                ;   volume setting, on top)
MC_SEP   = 8    ; [1] stereo separation 0-64 (0 mono, 64 hard left/right; default 32)
MC_READ  = 9    ; [1] length 1-14, [2..4] u24 offset, [5] area: 0 the module as loaded (MOD: its
                ;   header and patterns, always in the 31-sample layout), 1 the info block (MI_*)
                ;   -> MS_DATA
MC_LOOP  = 10   ; [1] 1: at the song's end start again (default), 0: stop (MST_ENDED)
MC_QUIT  = 11   ; stop and end

; ---- messages: engine -> client (byte 0) ----
MS_STATUS = 1   ; [1] state MST_*, [2] order (WAV: position in 256ths), [3] row, [4] pattern,
                ; [5] MST_LOADING: percent loaded; MST_ERROR: the error code; else the speed,
                ; [6..7] u16 time played in tenths of a second, [8..15] the level of channels
                ; 0..7 (0-64; WAV: left, right)
MS_DATA  = 2    ; [1] bytes that follow (0 = nothing there), [2..15] the data (MC_READ)
MS_HELLO = 3    ; [1] the engine's port

MST_EMPTY   = 0 ; nothing loaded
MST_LOADING = 1
MST_STOPPED = 2 ; loaded, not playing
MST_PLAYING = 3
MST_PAUSED  = 4
MST_ENDED   = 5 ; played to its end (MC_LOOP 0)
MST_ERROR   = 6 ; the load failed: [5] = the error (a file error $40+, ENOMEM, ENODEV no Lau,
                ;   EMS_FORMAT not a module or WAV file it can play, (0.27) EMS_NOOPL a MIDI
                ;   file without the OPL2, EMS_OPLBUSY a MIDI file whose play found the OPL2
                ;   taken by another program)
EMS_FORMAT  = $FE
EMS_NOOPL   = $FD ; (0.27) MIDI needs the OPL2 (hardware REV $0C)
EMS_OPLBUSY = $FC ; (0.27) another program owns the OPL2

; ---- the info block (MC_READ area 1) ----
MI_KIND   = 0   ; u8 0 nothing, 1 MOD, 2 WAV, 3 MIDI (OPL2, REV $0C+)
MI_NCHAN  = 1   ; u8 MOD: channels 1-8; WAV: 1 or 2; MIDI: 8 (meters)
MI_SLEN   = 2   ; u8 MOD: song length (orders)
MI_NSMP   = 3   ; u8 MOD: 15 or 31 samples
MI_RATE   = 4   ; u16 WAV: samples a second
MI_BITS   = 6   ; u8 WAV: 8 or 16
MI_SPEED  = 7   ; u8 MOD: the speed now
MI_FRAMES = 8   ; u32 WAV: sample frames
MI_SIZE   = 12  ; u32 the file's size
MI_TENTHS = 16  ; u16 WAV/MIDI: its length in tenths of a second
MI_BPM    = 18  ; u8 MOD/MIDI: the tempo now
MI_NPAT   = 19  ; u8 MOD: patterns; MIDI: tracks
MI_TAG    = 20  ; 4 characters: "M.K.", "8CHN", ... ("" for 15 samples), "WAV ", "MIDI"
MI_SIZEOF = 24
