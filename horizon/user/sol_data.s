; sol_data.s - Solitaire's tables and variables (included by solitair.s).

        .segment "RODATA"
crank:  .repeat 52, I                   ; a card's rank (ace 0 .. king 12), suit, red
        .byte   I .mod 13
        .endrepeat
csuit:  .repeat 52, I
        .byte   I / 13
        .endrepeat
cred:   .repeat 52, I
        .byte   (I / 13 = 1) | (I / 13 = 2)
        .endrepeat
backcol: .word  (16 + 3) | ((16 + 36 + 12 + 5) << 8)            ; blue: dark, light
        .word   (16 + 36 * 3) | ((16 + 36 * 5 + 6 * 2 + 1) << 8) ; red
        .word   (16 + 6 * 2 + 2) | ((16 + 36 + 6 * 4 + 3) << 8) ; green
; the win: where the cards land (an ellipse round the middle of the table)
ring:
        .word   178, 60, 196, 61, 214, 63, 231, 66, 248, 71, 263, 77
        .word   277, 84, 290, 92, 301, 101, 311, 110, 318, 121, 324, 132
        .word   327, 143, 328, 154, 327, 165, 324, 176, 318, 187, 311, 198
        .word   301, 207, 290, 216, 277, 224, 263, 231, 248, 237, 231, 242
        .word   214, 245, 196, 247, 178, 248, 160, 247, 142, 245, 125, 242
        .word   108, 237, 93, 231, 79, 224, 66, 216, 55, 207, 45, 198
        .word   38, 187, 32, 176, 29, 165, 28, 154, 29, 143, 32, 132
        .word   38, 121, 45, 110, 55, 101, 66, 92, 79, 84, 93, 77
        .word   108, 71, 125, 66, 142, 63, 160, 61
noctls: .addr   0
; the menus: a byte 1-7 before an item: a choice, its check mark set by setmenus (mchk)
mtmpl:  .byte   "Game", 0, "New game", 9, "F2", 0, "Restart this deal", 0, "Choose deal...", 0
        .byte   "-", 0, 1, "Klondike", 0, 2, "FreeCell", 0, "-", 0, "Close", 0, 0
        .byte   "Edit", 0, "Undo", 9, "Ctrl+Z", 0, 0
        .byte   "Options", 0, 3, "Draw one card", 0, 4, "Draw three cards", 0, "-", 0
        .byte   5, "Blue back", 0, 6, "Red back", 0, 7, "Green back", 0, 0, 0
mchk:   .addr   c_kl, c_fc, c_d1, c_d3, c_b0, c_b1, c_b2
mtab:   .addr   m_game, m_edit, m_opt
gtab:   .addr   m_new, m_restart, m_deal, loop, m_kl, m_fc, loop, m_close
otab:   .addr   m_d1, m_d3, loop, m_b0, m_b1, m_b2
t_title: .byte  "Solitaire", 0
s_kl:   .byte   "Klondike", 0
s_fc:   .byte   "FreeCell", 0
s_dr1:  .byte   ", draw one", 0
s_dr3:  .byte   ", draw three", 0
s_none: .byte   0
s_deal: .byte   "   Deal ", 0
s_score: .byte  "Score ", 0
s_moves: .byte  "Moves ", 0
s_gap:  .byte   "    ", 0
s_time: .byte   "Time ", 0
s_won:  .byte   "Well done: all the cards are home!", 0
s_again: .byte  "F2: another deal", 0
s_replay: .byte "replay", 0
t_deal: .byte   "Choose deal", 0
t_dnum: .byte   "Deal number (1-65535):", 0
b_ok:   .byte   "OK", 0
b_cancel: .byte "Cancel", 0
; the deal dialog
dg_deal: .addr  t_deal
        .word   260, 84
        .addr   ls_deal
        .word   0
ls_deal: .addr  lb_deal, fd_deal, bt_dcancel, bt_dok, 0
lb_deal: .byte  UT_LABEL, 0
        .word   12, 14, 150, UI_LINE, 0
        .addr   t_dnum
        .segment "DATA"
fd_deal: .byte  UT_FIELD, 0
        .word   168, 10, 80, UI_FLDH, UF_FOCUS
        .addr   dbuf
        .word   8, 0, 0, 0, 0
bt_dok: .byte   UT_BUTTON, 0
        .word   184, 52, 64, UI_BTNH, UF_DEFAULT
        .addr   b_ok
bt_dcancel: .byte UT_BUTTON, 0
        .word   112, 52, 64, UI_BTNH, UF_CANCEL
        .addr   b_cancel
wopen:  .word   123, 22, SW, WH
        .faraddr t_title
        .byte   0

        .segment "BSS"
argl:   .res    2
argx:   .res    2
wsown:  .res    2
win:    .res    2
tmode:  .res    2                       ; -t
smode:  .res    2                       ; -s
hbank:  .res    2                       ; banks: the history (keep this order)
sbank0: .res    2                       ;   the scene's two halves
sbank1: .res    2
ibank0: .res    2                       ;   the card images
ibank1: .res    2
wbank:  .res    2                       ;   carrying and flying
game:   .res    2                       ; 0 Klondike, 1 FreeCell
draw3:  .res    2
back:   .res    2                       ; the card back 0-2
deal_no: .res   2
nrng:   .res    4                       ; the generator of new deal numbers
npiles: .res    2
pcnt:   .res    2 * NPMAX
ptype:  .res    2 * NPMAX
pxs:    .res    2 * NPMAX
pys:    .res    2 * NPMAX
pcards: .res    PMAX * NPMAX
ycache: .res    PMAX * NPMAX            ; tableau: each card's y from TABY
deck:   .res    52
rng:    .res    4
ia32:   .res    4
ib32:   .res    4
r32:    .res    4
hcount: .res    2
score:  .res    2
moves:  .res    2
won:    .res    2
dirty:  .res    2
secs:   .res    2
timing: .res    2
lcpile: .res    2                       ; the last click (a double click)
lcidx:  .res    2
lctime: .res    2
wn:     .res    2
rowlo:  .res    2 * TH
sblk:   .res    16
mbuf:   .res    256
sbuf:   .res    80
numbuf: .res    8
dbuf:   .res    8
pv16:   .res    2
shx:    .res    2
tstart: .res    4                       ; the clock: the first move (ms)
noslots: .res   2
bestp:   .res    2
besta:   .res    2
sl:      .res    2
grx:     .res    2
gry:     .res    2
px0:     .res    2
py0:     .res    2
ppile:   .res    2
pidx:    .res    2
tfail:  .res    2
tsec:   .res    2
tsecbad: .res   2
tptr:   .res    2
tcmd:   .res    2
tname:  .res    2
tstep:  .res    2
tnmov:  .res    2
tnbad:  .res    2
tnundo: .res    2
trng:   .res    4
trmov:  .res    2
trund:  .res    2
trdeal: .res    2
trbad:  .res    2
trsum0: .res    2
tseen:  .res    64

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
g8:     .res    2
g9:     .res    2
ms:     .res    2                       ; a move: source, index, destination, count, card,
mi:     .res    2                       ;   a card turned up
md:     .res    2
mn:     .res    2
mc:     .res    2
mf:     .res    2
bs:     .res    2
bi:     .res    2
bd:     .res    2
fe:     .res    2
jv:     .res    2
hp:     .res    4                       ; the history: a record, the start
hbase:  .res    4
ip:     .res    4                       ; drawing: an image, a scene row, the work bank
sp4:    .res    4
wp:     .res    4
wq:     .res    4
ap:     .res    2                       ; art
ink:    .res    2
ax:     .res    2                       ; a rectangle (image, scene, window)
ay:     .res    2
aw:     .res    2
ah:     .res    2
bx:     .res    2
by:     .res    2
bw:     .res    2
bh:     .res    2
qx:     .res    2
qy:     .res    2
qw:     .res    2
qh:     .res    2
pp:     .res    2                       ; a pile being drawn: its number, cards, type, index
plim:   .res    2
ptyv:   .res    2
pi:     .res    2
cx:     .res    2                       ; a card's place
cy:     .res    2
ex:     .res    2                       ; the pointer
ey:     .res    2
hpl:    .res    2                       ; hit: pile, index
hi:     .res    2
ds:     .res    2                       ; carried: pile, index, count, height, place
di:     .res    2
dn:     .res    2
dh:     .res    2
dx:     .res    2
dy:     .res    2
nx:     .res    2
ny:     .res    2
fx:     .res    2                       ; a flight
fy:     .res    2
fx0:    .res    2
fy0:    .res    2
ff:     .res    2
frames: .res    2
arc:    .res    2
pressed: .res   2                       ; the mouse: a press on a card, a drag
dragging: .res  2
