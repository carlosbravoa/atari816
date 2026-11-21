; mu_data.s - Music's tables, texts and variables (included by music.s).

        .segment "RODATA"
; the menus (items counting separators)
;   File: 0 Open..., 1 Open folder..., 2 Open location..., 4 Remove, 5 Clear, 7 Quit
;   Play: 0 Play / Pause, 1 Stop, 3 Previous, 4 Next, 5 Back, 6 Forward, 8 Shuffle,
;         9 Repeat off, 10 Repeat all, 11 Repeat one, 13 Louder, 14 Softer
;   View: 0 Playlist, 1 Samples          Help: 0 Keys..., 1 About Music Player...
menus:  .byte   "File", 0
        .byte   "Open...", 9, "Ctrl+O", 0
        .byte   "Open folder...", 0
        .byte   "Open location...", 9, "Ctrl+L", 0
        .byte   "-", 0
        .byte   MS_STATE, "Remove from playlist", 9, "Del", 0
        .byte   MS_STATE, "Clear playlist", 0
        .byte   "-", 0
        .byte   "Quit", 9, "Ctrl+Q", 0, 0
        .byte   "Play", 0
        .byte   "Play / Pause", 9, "Space", 0
        .byte   "Stop", 9, "Esc", 0
        .byte   "-", 0
        .byte   "Previous song", 9, "PgUp", 0
        .byte   "Next song", 9, "PgDn", 0
        .byte   "Back", 9, "Left", 0
        .byte   "Forward", 9, "Right", 0
        .byte   "-", 0
        .byte   MS_STATE, "Shuffle", 0
        .byte   MS_STATE, "Repeat off", 0
        .byte   MS_STATE, "Repeat all", 0
        .byte   MS_STATE, "Repeat one", 0
        .byte   "-", 0
        .byte   "Louder", 9, "+", 0
        .byte   "Softer", 9, "-", 0, 0
        .byte   "View", 0
        .byte   MS_STATE, "Playlist", 9, "Ctrl+P", 0
        .byte   MS_STATE, "Samples", 9, "Ctrl+I", 0, 0
        .byte   "Help", 0, "Keys...", 0, "About Music Player...", 0, 0, 0
mfile:  .addr   a_open, a_folder, a_url, m_none, a_remove, a_clear, m_none, m_quit
mplay:  .addr   a_toggle, a_stop, m_none, a_prev, a_next, m_back, m_fwd, m_none
        .addr   m_shuffle, m_roff, m_rall, m_rone, m_none, m_louder, m_softer
mhelp:  .addr   m_keys, m_about
btnact: .addr   a_prev, a_play, a_pause, a_stop, a_next

; the buttons' pictures: {dx, dy, w, h} fills from the button's top left, $FFFF
glyphs: .addr   g_prev, g_play, g_pause, g_stop, g_next
.macro  TRI_L   x0
        .repeat 6, K
        .word   x0 + K, 10 - K, 1, 1 + 2 * K
        .endrepeat
.endmacro
.macro  TRI_R   x0
        .repeat 6, K
        .word   x0 + K, 5 + K, 1, 11 - 2 * K
        .endrepeat
.endmacro
g_prev: .word   8, 5, 2, 11
        TRI_L   11
        TRI_L   17
        .word   $FFFF
g_play: TRI_R   12
        .word   $FFFF
g_pause: .word  10, 5, 3, 11, 17, 5, 3, 11, $FFFF
g_stop: .word   10, 6, 9, 9, $FFFF
g_next: TRI_R   8
        TRI_R   14
        .word   20, 5, 2, 11, $FFFF

; the settings file's keys (upper case: compared ignoring case) and their readers
cfgkeys: .addr  s_kvolu, cv_vol, s_ksepu, cv_sep, s_krepu, cv_rep, s_kshufu, cv_shuf
        .addr   s_kcuru, cv_cur, 0
s_kvolu: .byte  "VOLUME=", 0
s_ksepu: .byte  "SEPARATION=", 0
s_krepu: .byte  "REPEAT=", 0
s_kshufu: .byte "SHUFFLE=", 0
s_kcuru: .byte  "CURRENT=", 0
s_off:  .byte   "OFF", 0
s_all:  .byte   "ALL", 0
s_one:  .byte   "ONE", 0
s_on:   .byte   "ON", 0
s_cfghead: .byte "# Music Player: the settings and the playlist (one path or address a line)", 10, 0
s_kvol: .byte   "volume=", 0
s_ksep: .byte   "separation=", 0
s_krep: .byte   "repeat=", 0
s_kshuf: .byte  "shuffle=", 0
s_kcur: .byte   "current=", 0
w_off:  .byte   "off", 0
w_all:  .byte   "all", 0
w_one:  .byte   "one", 0
w_on:   .byte   "on", 0
repkw:  .addr   w_off, w_all, w_one

p_engine: .byte "/SYSTEM/MUSICD.PRG", 0
p_cfg:  .byte   "/SYSTEM/MUSIC.CFG", 0
p_req:  .byte   "/SYSTEM/OPEN.REQ", 0
p_self: .byte   "/BIN/MUSIC.PRG", 0     ; (upper case: compared ignoring case)
hexd:   .byte   "0123456789ABCDEF"

t_title: .byte  "Music Player", 0
t_open: .byte   "Open a MOD or WAV file", 0
s_ok:   .byte   "OK", 0
s_cancel: .byte "Cancel", 0
s_add:  .byte   "Add", 0
s_openb: .byte  "Open", 0
s_clear: .byte  "Clear", 0
s_volume: .byte "Volume", 0
s_stereo: .byte "Stereo", 0
s_tpl:  .byte   "Playlist", 0
s_tsm:  .byte   "Samples", 0
s_songs: .byte  " songs", 0
s_song1: .byte  " song", 0
s_smps2: .byte  " samples", 0
s_songn: .byte  "Song ", 0
s_plempty: .byte "The playlist is empty", 0
s_plnone: .byte "Nothing playing", 0
s_soundoff: .byte "The sound is off (Settings, Sound volume)", 0
s_shuf: .byte   "Shuffle, ", 0
reptxt: .addr   s_rpoff, s_rpall, s_rpone
s_rpoff: .byte  "repeat off", 0
s_rpall: .byte  "repeat all", 0
s_rpone: .byte  "repeat one", 0
s_wav:  .byte   "WAV, ", 0
s_mid:  .byte   "MIDI (OPL2), ", 0
s_trks: .byte   " tracks, ", 0
s_bpm:  .byte   " BPM, ", 0
s_hz:   .byte   " Hz, ", 0
s_bit:  .byte   "-bit ", 0
s_mono: .byte   "mono", 0
s_stereo2: .byte "stereo", 0
s_comma: .byte  ", ", 0
s_chans: .byte  " channels, ", 0
s_smps: .byte   " samples", 0
s_order: .byte  "Order ", 0
s_of:   .byte   " of ", 0
s_pat:  .byte   ", pattern ", 0
s_row:  .byte   ", row ", 0
s_paused1: .byte "Paused", 0
s_slash: .byte  " / ", 0
m_idle: .byte   "No song loaded", 0
m_hint0: .byte  "Open a MOD or WAV file: File > Open...", 0
m_hint1: .byte  "Double click a song of the playlist to play it.", 0
m_loading: .byte "Loading...", 0
m_notdir: .byte "% is not a folder.", 0
m_nosongs: .byte "There are no MOD or WAV files in", 10, "%.", 0

; the load errors (MST_ERROR): code, text
errtab: .word   $44, e_nofile, $45, e_nopath, $46, e_name, $47, e_denied, $41, e_io
        .word   $52, e_nfiles, $C2, e_nosup
        .word   E_NOLINK, e_nolink, E_LOST, e_lost, E_NOSVC, e_nosvc, E_BADADDR, e_badaddr
        .word   E_NONAME, e_noname, E_REFUSED, e_refused, E_TIMEOUT, e_timeout
        .word   E_HTTP, e_http, E_CLOSED, e_closed, E_TLS, e_tls, E_PCBUSY, e_pcbusy
        .word   E_NET, e_net, ENOMEM, e_nomem, ENODEV, e_nodev, EMS_FORMAT, e_format
        .word   EMS_NOOPL, e_noopl, EMS_OPLBUSY, e_oplbusy, 0      ; (0.27) MIDI
e_nofile: .byte "File not found.", 0
e_nopath: .byte "Folder not found.", 0
e_name: .byte   "Not a valid file name.", 0
e_denied: .byte "The file cannot be read (access denied).", 0
e_io:   .byte   "The card could not be read.", 0
e_nfiles: .byte "Too many files are open.", 0
e_nosup: .byte  "This cannot be opened here.", 0
e_nolink: .byte "No PC link: start the gateway on the PC.", 0
e_lost: .byte   "The PC link was lost.", 0
e_nosvc: .byte  "No internet: the PC's gateway does not offer it.", 0
e_badaddr: .byte "Bad address (the URL, the host or the port).", 0
e_noname: .byte "Server not found.", 0
e_refused: .byte "Refused or unreachable, or not on the server.", 0
e_timeout: .byte "Timeout: the server did not answer.", 0
e_http: .byte   "The server answered with an error (not found?).", 0
e_closed: .byte "The server closed the connection.", 0
e_tls:  .byte   "TLS failed: the server's certificate is not valid.", 0
e_pcbusy: .byte "Too many connections on the PC.", 0
e_net:  .byte   "Network error.", 0
e_nomem: .byte  "Not enough memory for this song.", 0
e_nodev: .byte  "No Lau: the sample player is not there.", 0
e_format: .byte "Not a module (MOD) or a WAV file Music Player can play.", 0
e_noopl: .byte  "MIDI needs the OPL2 (hardware revision $0C).", 0
e_oplbusy: .byte "The OPL2 is in use by another program.", 0

; alerts
al_nolau: .word AL_INFO
        .addr   t_title, m_nolau, s_ok, 0, 0
m_nolau: .byte  "Music Player needs Lau, the Atari816's sample player", 10
        .byte   "(hardware revision $0A or later).", 0
al_noport: .word AL_ERROR
        .addr   t_title, m_noport, s_ok, 0, 0
m_noport: .byte "Music Player cannot start: no message port is free.", 10
        .byte   "Close a program and try again.", 0
al_noeng: .word AL_ERROR
        .addr   t_title, m_noeng, s_ok, 0, 0
m_noeng: .byte  "Music Player cannot start: its engine,", 10
        .byte   "/SYSTEM/MUSICD.PRG, is not on the card.", 0
al_nohello: .word AL_ERROR
        .addr   t_title, m_nohello, s_ok, 0, 0
m_nohello: .byte "Music Player cannot start: its engine,", 10
        .byte   "/SYSTEM/MUSICD.PRG, did not answer.", 0
al_dead: .word  AL_ERROR
        .addr   t_title, m_dead, s_ok, 0, 0
m_dead: .byte   "The music engine has stopped.", 10
        .byte   "Close Music Player and start it again.", 0
al_full: .word  AL_WARN
        .addr   t_title, m_full, s_ok, 0, 0
m_full: .byte   "The playlist is full (256 songs).", 0
al_nourl: .word AL_WARN
        .addr   t_title, m_nourl, s_ok, 0, 0
m_nourl: .byte  "Not an address: it starts with http://,", 10
        .byte   "https:// or ftp://.", 0
al_clear: .word AL_QUESTION
        .addr   t_title, m_clear, s_clear, s_cancel, 0
m_clear: .byte  "Take every song out of the playlist?", 10
        .byte   "(The files stay on the card.)", 0
al_about: .word AL_INFO
        .addr   t_about, m_abtxt, s_ok, 0, 0
t_about: .byte  "About Music Player", 0
m_abtxt: .byte  "Music Player for the Atari816, version 1.0", 10
        .byte   "Plays MOD modules (4 to 8 channels) and WAV files", 10
        .byte   "on Lau. The engine: /SYSTEM/MUSICD.PRG.", 0
al_path: .word  AL_WARN
        .addr   t_title, albuf, s_ok, 0, 0

; File > Open folder..., Open location...
ak_fold: .addr  t_fold, m_fold, fbuf
        .word   PATHMAX
        .addr   s_add
t_fold: .byte   "Open folder", 0
m_fold: .byte   "Add every MOD and WAV file of the folder:", 0
ak_url: .addr   t_url, m_url, ubuf
        .word   PATHMAX
        .addr   s_openb
t_url:  .byte   "Open location", 0
m_url:  .byte   "The address of a MOD or WAV file (http, https, ftp):", 0

; Help > Keys...
t_keys: .byte   "Music Player: keys", 0
KEYSN   = 9
dg_keys: .addr  t_keys
        .word   420, 12 + KEYSN * 14 + 32
        .addr   ls_keys
        .word   0
ls_keys: .addr  lb_k1, lb_k2, lb_k3, lb_k4, lb_k5, lb_k6, lb_k7, lb_k8, lb_k9, bt_kok, 0
.macro  kline   n, txt
.ident(.sprintf("lb_k%d", n)):
        .byte   UT_LABEL, 0
        .word   16, 12 + (n - 1) * 14, 392, UI_LINE, 0
        .addr   :+
:       .byte   txt, 0
.endmacro
        kline   1, "Space: play or pause.    Esc: stop."
        kline   2, "Left, Right: back or forward (a module's order, 5 s of a WAV)."
        kline   3, "Page Up, Page Down (or Ctrl+Left, Right): the previous, next song."
        kline   4, "Up, Down and Enter, or a double click: play a song of the list."
        kline   5, "Delete: the selected song out of the playlist.    + -: louder, softer."
        kline   6, "Ctrl+O open a file, Ctrl+L open an address (http, https, ftp)."
        kline   7, "Ctrl+P the playlist, Ctrl+I the module's samples (its texts)."
        kline   8, "Click the position bar to go there. Drop files or folders here."
        kline   9, "The sound volume of Settings is the loudness of all sound."

        .segment "DATA"
wopen:  .word   (640 - WW - 2) / 2, 60, WW, WH
        .faraddr t_title
        .byte   0
ctl_pl: .addr   lst_pl, 0
ctl_sm: .addr   lst_sm, 0
lst_pl: .byte   UT_LIST, 0
        .word   M, LSY, WW - 2 * M, LSH, UF_FOCUS
        .word   0, $FFFF, 0, lsrow_pl, MKW, 0
        .res    SB_SIZE
lst_sm: .byte   UT_LIST, 0
        .word   M, LSY, WW - 2 * M, LSH, UF_FOCUS
        .word   0, $FFFF, 0, lsrow_sm, SNW, 0
        .res    SB_SIZE
bt_kok: .byte   UT_BUTTON, 0
        .word   420 - 64 - 12, 12 + KEYSN * 14 + 4, 64, UI_BTNH, UF_DEFAULT | UF_CANCEL
        .addr   s_ok
al_engerr: .word AL_ERROR
        .addr   t_title, m_engerr, s_ok, 0, 0
m_engerr: .byte "Music Player cannot start its engine,", 10
        .byte   "/SYSTEM/MUSICD.PRG (error $"
m_engerr_h: .byte "00).", 0
m_errn: .byte   "Error $"
m_errn_h: .byte "00.", 0
eargs:  .byte   "-p ", 0, 0, 0, 0, 0, 0
ubuf:   .byte   "http://", 0
        .res    PATHMAX - 8
myport: .word   $FFFF
vol:    .word   64
msep:   .word   32
mrep:   .word   RP_ALL
cur:    .word   $FFFF
btnp:   .word   $FFFF
tink:   .word   C_DARK | (C_BODY << 8)
fink:   .word   C_DARK

        .segment "BSS"
argl:   .res    2
argx:   .res    2
pbank:  .res    2                       ; the program's bank
wsown:  .res    2
win:    .res    2
winok:  .res    2                       ; the window is open
plbank: .res    2                       ; the playlist's paths
tmode:  .res    2                       ; -t
eport:  .res    2                       ; the engine's port
etask:  .res    2
dead:   .res    2                       ; the engine went away (said once)
phase:  .res    2                       ; PH_*
estate: .res    2                       ; the state shown (MST_*)
lstate: .res    2                       ; the state of the last status taken
ended:  .res    2                       ; the song ended (MST_ENDED came)
gotst:  .res    2
pct:    .res    2                       ; loading: percent
lerr:   .res    2                       ; the load's error
infodirty: .res 2                       ; the format line to be made again
st:     .res    16                      ; the last status
info:   .res    MI_SIZEOF + 2           ; the info block (MI_*)
nsmp:   .res    2                       ; the module's samples
mtitle: .res    24                      ; its title
smp:    .res    NSMPB + 4               ; its sample headers
rd_ph:  .res    2                       ; reading: the part, offset, bytes left, where,
rd_off: .res    2                       ;   the area, frames or ticks waited
rd_left: .res   2
rd_dst: .res    2
rd_area: .res   2
rd_wait: .res   2
pl_n:   .res    2                       ; the playlist: rows, each row's slot
pl_idx: .res    2 * MAXPL + 2
shuf:   .res    2
view:   .res    2                       ; 0 the playlist, 1 the samples
dirty:  .res    2                       ; the settings changed
sysv:   .res    2                       ; the sound volume setting
rng:    .res    2
reqt:   .res    2
vblon:  .res    2
nch:    .res    2                       ; the meters: channels, a bar's width, their x
mbw:    .res    2
mbx:    .res    16
lv_t:   .res    16                      ; the levels: the status's, shown, drawn (height)
lv_d:   .res    16
lv_s:   .res    16
mn:     .res    2
vischk: .res    2                       ; frames to the next look; the box seen
mvis:   .res    2
wibuf:  .res    8
mrec:   .res    16 * 32                 ; the meters' fills
bar_n:  .res    2                       ; the position bar: filled, colour; drawn
bar_c:  .res    2
bar_px: .res    2
bar_pc: .res    2
btnin:  .res    2                       ; the pointer on the button held
drag:   .res    2                       ; DR_*
kctrl:  .res    2
kshift: .res    2
tabx1:  .res    2                       ; the tabs' ends
tabx2:  .res    2
tright: .res    2
posforce: .res  2
cfh:    .res    2                       ; files: the handle, the line read, written
lnl:    .res    2
wrn:    .res    2
wsink:  .res    2                       ; the writer: 0 the file, 1 the console
msg:    .res    16                      ; to the engine, from it
rmsg:   .res    16
spblk:  .res    8
rwb:    .res    6
sblk:   .res    6
stb:    .res    10
rdb:    .res    10
sl:     .res    2
SBUFL   = 160
sbuf:   .res    SBUFL
numbuf: .res    8
dtmp:   .res    8
tstr:   .res    PATHMAX                 ; the texts shown, and the last drawn
fstr:   .res    96
pstr:   .res    64
pstr_o: .res    64
tmstr:  .res    24
tmstr_o: .res   24
tbuf:   .res    PATHMAX + 4
pbuf:   .res    PATHMAX + 4
nbuf:   .res    PATHMAX + 4
abuf:   .res    PATHMAX + 4
fbuf:   .res    PATHMAX + 4
lbuf:   .res    PATHMAX + 4
rowbuf: .res    32
albuf:  .res    256
IOBL    = 512
iobuf:  .res    IOBL + 2
DBUFL   = 1024
dbuf:   .res    DBUFL

        .segment "ZEROPAGE"
t0:     .res    2
t1:     .res    2
t2:     .res    2
t3:     .res    2
t4:     .res    2
t5:     .res    2
t6:     .res    2
t7:     .res    2
g0:     .res    2
g1:     .res    2
g2:     .res    2
g3:     .res    2
g4:     .res    2
g5:     .res    2
g6:     .res    2
g7:     .res    2
p0:     .res    4                       ; long pointers (the playlist's bank)
p1:     .res    4
ex:     .res    2                       ; the pointer
ey:     .res    2
mh:     .res    2                       ; a meter bar: its height, channel, x
mc:     .res    2
mx:     .res    2
za:     .res    2                       ; a zone: from, to, colours
zb:     .res    2
zc:     .res    2
bi:     .res    2                       ; a button: its number, x, down, ink
bx:     .res    2
bdn:    .res    2
bink:   .res    2
