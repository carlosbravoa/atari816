; fc_data.s - FreeCell's tables, texts and variables (included by freecell.s).

        .segment "RODATA"
crank:  .repeat 52, I                   ; a card's rank (ace 0 .. king 12), suit, red
        .byte   I .mod 13
        .endrepeat
csuit:  .repeat 52, I                   ; clubs 0, diamonds 1, hearts 2, spades 3
        .byte   I / 13
        .endrepeat
cred:   .repeat 52, I
        .byte   (I / 13 = 1) | (I / 13 = 2)
        .endrepeat
; the opposite colour's suits of each suit (for the safe rule)
opp1:   .byte   1, 0, 0, 1
opp2:   .byte   2, 3, 3, 2
; the x of each column (top row and cascades)
colx:   .repeat 8, I
        .word   COLX0 + I * PITCH
        .endrepeat
noctls: .addr   0

; the menus (items counting separators: Game 0 New, 1 Restart, 2 Select, 4 Undo,
; 6 Statistics, 8 Quit; Help 0 How to play, 1 About)
menus:  .byte   "Game", 0, "New game", 9, "N", 0, "Restart this game", 9, "R", 0
        .byte   "Select game...", 9, "G", 0, "-", 0, "Undo", 9, "Ctrl+Z", 0, "-", 0
        .byte   "Statistics...", 0, "-", 0, "Quit", 0, 0
        .byte   "Help", 0, "How to play...", 0, "About FreeCell...", 0, 0, 0
gtab:   .addr   m_new, m_restart, m_select, loop, m_undo, loop, m_stats, loop, quit
htab:   .addr   m_help, m_about

t_title: .byte  "FreeCell", 0
s_game: .byte   "Game ", 0
s_test: .byte   "Test position", 0
s_moves: .byte  "Moves ", 0
s_time: .byte   "Time ", 0
s_left: .byte   "Cards left ", 0
s_gap:  .byte   "   ", 0
s_stuck: .byte  "No moves left", 0
s_won1: .byte   "You won!", 0
s_won3: .byte   "N: a new game", 0
s_in:   .byte   " in ", 0
s_mvs:  .byte   " moves, time ", 0
p_dat:  .byte   "/BIN/FREECELL.DAT", 0
p_sfx:  .byte   "/BIN/FREECELL.SFX", 0
b_ok:   .byte   "OK", 0
b_cancel: .byte "Cancel", 0
b_reset: .byte  "Reset", 0
b_yes:  .byte   "Reset", 0

; Game > Select game...
t_sel:  .byte   "Select game", 0
t_snum: .byte   "Game number (1-65535):", 0
dg_sel: .addr   t_sel
        .word   260, 84
        .addr   ls_sel
        .word   0
ls_sel: .addr   lb_sel, fd_sel, bt_scancel, bt_sok, 0
lb_sel: .byte   UT_LABEL, 0
        .word   12, 14, 150, UI_LINE, 0
        .addr   t_snum

; Game > Statistics...
t_stats: .byte  "Statistics", 0
dg_stats: .addr t_stats
        .word   236, 132
        .addr   ls_stats
        .word   0
ls_stats: .addr lb_st1, lb_st2, lb_st3, lb_st4, lb_st5, bt_streset, bt_stok, 0
lb_st1: .byte   UT_LABEL, 0
        .word   16, 12, 204, UI_LINE, 0
        .addr   stl1
lb_st2: .byte   UT_LABEL, 0
        .word   16, 28, 204, UI_LINE, 0
        .addr   stl2
lb_st3: .byte   UT_LABEL, 0
        .word   16, 44, 204, UI_LINE, 0
        .addr   stl3
lb_st4: .byte   UT_LABEL, 0
        .word   16, 60, 204, UI_LINE, 0
        .addr   stl4
lb_st5: .byte   UT_LABEL, 0
        .word   16, 76, 204, UI_LINE, 0
        .addr   stl5
s_st1:  .byte   "Games played:  ", 0
s_st2:  .byte   "Games won:  ", 0
s_st3:  .byte   "Current streak:  ", 0
s_st4:  .byte   "Best streak:  ", 0
s_st5:  .byte   "Best time:  ", 0
s_none: .byte   "none yet", 0
s_pc:   .byte   "%)", 0
s_op:   .byte   "  (", 0
al_reset: .word AL_QUESTION
        .addr   t_stats, s_rq, b_yes, b_cancel, 0
s_rq:   .byte   "Reset the statistics to zero?", 0

; Help > How to play...
t_help: .byte   "How to play FreeCell", 0
dg_help: .addr  t_help
        .word   392, 12 + 14 * 14 + 32
        .addr   ls_help
        .word   0
ls_help: .addr  lb_h1, lb_h2, lb_h3, lb_h4, lb_h5, lb_h6, lb_h7, lb_h8, lb_h9, lb_h10
        .addr   lb_h11, lb_h12, lb_h13, lb_h14, bt_hok, 0
.macro  hline   n, txt
.ident(.sprintf("lb_h%d", n)):
        .byte   UT_LABEL, 0
        .word   16, 12 + (n - 1) * 14, 364, UI_LINE, 0
        .addr   :+
:       .byte   txt, 0
.endmacro
        hline   1, "Goal: move all 52 cards to the four foundations (top right),"
        hline   2, "one pile for each suit, from the ace up to the king."
        hline   3, "In the eight columns a card goes on a card one rank higher"
        hline   4, "of the other colour: a red 7 on a black 8."
        hline   5, "The four free cells (top left) hold one card each. Any card"
        hline   6, "may go into a free cell or into an empty column."
        hline   7, "A run in order moves as a whole when there is room for it:"
        hline   8, "(free cells + 1) x 2 for each empty column."
        hline   9, "Mouse: drag a card or a run, or click it and then its place."
        hline   10, "Double click or right click: the card goes home if it can,"
        hline   11, "else into a free cell. Safe cards go home by themselves."
        hline   12, "Keys: U or Ctrl+Z undo, N new game, R restart this game,"
        hline   13, "G choose a game number. The same number is the same deal."
        hline   14, "Esc lets go of a selected card."

t_about: .byte  "About FreeCell", 0
s_about: .byte  "FreeCell for the Atari816, version 1.0", 10
        .byte   "Games 1-65535: each number is always the same deal.", 0
al_about: .word AL_INFO
        .addr   t_about, s_about, b_ok, 0, 0

        .segment "DATA"
fd_sel: .byte   UT_FIELD, 0
        .word   168, 10, 80, UI_FLDH, UF_FOCUS
        .addr   dbuf
        .word   8, 0, 0, 0, 0
bt_sok: .byte   UT_BUTTON, 0
        .word   184, 52, 64, UI_BTNH, UF_DEFAULT
        .addr   b_ok
bt_scancel: .byte UT_BUTTON, 0
        .word   112, 52, 64, UI_BTNH, UF_CANCEL
        .addr   b_cancel
bt_stok: .byte  UT_BUTTON, 0
        .word   160, 104, 64, UI_BTNH, UF_DEFAULT | UF_CANCEL
        .addr   b_ok
bt_streset: .byte UT_BUTTON, 0
        .word   88, 104, 64, UI_BTNH, 0
        .addr   b_reset
bt_hok: .byte   UT_BUTTON, 0
        .word   392 - 64 - 12, 12 + 14 * 14 + 4, 64, UI_BTNH, UF_DEFAULT | UF_CANCEL
        .addr   b_ok
wopen:  .word   (640 - WW - 2) / 2, 20, WW, WH
        .faraddr t_title
        .byte   0
shnb:   .faraddr 0                      ; sheet_new's block: address, 0, stride, width, height
        .byte   0
        .word   0, 0, 0
spb:    .res    16                      ; sample_play's block
iob:    .res    6                       ; read / write block

        .segment "BSS"
argl:   .res    2
argx:   .res    2
wsown:  .res    2
win:    .res    2
pbank:  .res    2                       ; the program's bank
tmode:  .res    2                       ; -t
wmode:  .res    2                       ; -w (the test position)
mflag:  .res    2                       ; -m (measure dragging)
ibank0: .res    2                       ; banks: cards 0-25, cards 26-51, the places and
ibank1: .res    2                       ;   the history, the samples (keep this order)
xbank:  .res    2
sbank:  .res    2
sh0:    .res    2                       ; their sheets
sh1:    .res    2
shx:    .res    2
cmapw:  .res    2 * (NCOLS + 1)         ; local colour -> palette entry
tcard:  .res    CARDW * CARDH           ; the templates in palette entries
tslot:  .res    CARDW * CARDH
game_no: .res   2                       ; the game (0: the test position)
nrng:   .res    4                       ; the generator of new game numbers
rng:    .res    4                       ; the deal's generator
deck:   .res    52
pcnt:   .res    2 * NP                  ; the piles: counts, cards
pcards: .res    PMAX * NP
hcount: .res    2                       ; the history's records
moves:  .res    2
won:    .res    2
stuck:  .res    2
started: .res   2                       ; a move was made in this game (it counts)
stsave: .res    2                       ; the statistics to be saved
focused: .res   2
running: .res   2                       ; the clock
wasrun: .res    2                       ; (it ran when a dialog opened)
tacc:   .res    2                       ; seconds before the running span
tstart: .res    4                       ; its start (ms)
secs:   .res    2
secs0:  .res    2                       ; at the player's last move
hid_p:  .res    2                       ; cards lifted: pile ($FFFF none), first index
hid_i:  .res    2
sel_p:  .res    2                       ; the selection: pile ($FFFF none), first index
sel_i:  .res    2
fl_on:  .res    2                       ; the floating cards (dragged or flying)
fl_n:   .res    2
fl_step: .res   2
fl_x:   .res    2
fl_y:   .res    2
fl_h:   .res    2
fl_cards: .res  PMAX
flyn:   .res    2                       ; a flight's frames (0: by its length)
celeb:  .res    2                       ; the win: cards on display
dn:     .res    2
btns:   .res    2                       ; the buttons last seen
pressed: .res   2                       ; a left press on a card
dragging: .res  2
pp:     .res    2                       ; the press: pile, index, where
pix:    .res    2
px0:    .res    2
py0:    .res    2
grx:    .res    2                       ; the grip in the floating cards
gry:    .res    2
lcpile: .res    2                       ; the last click (double clicks)
lcidx:  .res    2
lctime: .res    2
rn:     .res    2                       ; the records of the list being made
rvbl:   .res    2
vblok:  .res    2                       ; SH_VBL on REV $09+, else 0
rbuf:   .res    16 * 128
mt_t:   .res    2                       ; measuring: frames, ms
mt_ms:  .res    2
mt_t0:  .res    2
lau:    .res    2                       ; samples: Lau and the file there
st_played: .res 2                       ; statistics (keep this order: the file)
st_won: .res    2
st_streak: .res 2
st_best: .res   2
st_btime: .res  2
fbuf:   .res    16
sl:     .res    2
sbuf:   .res    96
sbuf2:  .res    96
numbuf: .res    8
dbuf:   .res    8
pv16:   .res    2
umask:  .res    2                       ; undo: the piles changed, the one being drawn
uidx:   .res    2
stl1:   .res    40
stl2:   .res    40
stl3:   .res    40
stl4:   .res    40
stl5:   .res    40
tfail:  .res    2                       ; the self test
tcnt:   .res    2
tsum:   .res    2

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
ms:     .res    2                       ; a move: source pile, index, destination, count,
mi:     .res    2                       ;   the first card moved, flags (MF_*)
md:     .res    2
mn:     .res    2
mc:     .res    2
mf:     .res    2
hp:     .res    4                       ; the history's record
ip:     .res    4                       ; drawing an image: its first byte, a row
rp:     .res    4
istride: .res   2
ink:    .res    2
mk:     .res    2                       ; a mask: its row, width, height, bytes a row
mw:     .res    2
mh:     .res    2
mb:     .res    2
ax:     .res    2                       ; a rectangle
ay:     .res    2
aw:     .res    2
ah:     .res    2
rx:     .res    2                       ; a region to draw
ry:     .res    2
rw:     .res    2
rh:     .res    2
clx0:   .res    2                       ; the clip
cly0:   .res    2
clx1:   .res    2
cly1:   .res    2
cbank:  .res    2                       ; a card image's bank
rs:     .res    2                       ; a record's sheet and source
rsx:    .res    2
rsy:    .res    2
ex:     .res    2                       ; the pointer
ey:     .res    2
hpl:    .res    2                       ; hit: pile, index
hix:    .res    2
qx:     .res    2                       ; the old rectangle of the floating cards
qy:     .res    2
qw:     .res    2
qh:     .res    2
fy0:    .res    2                       ; the rows both rectangles have
fh0:    .res    2
