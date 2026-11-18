; qb_data.s - Quabricks' tables, texts and variables (included by quabrick.s).

        .segment "RODATA"
        .include "qb_art.inc"           ; (build/: tools/mkqbart.py)

; the pieces as 4 x 4 masks, turns 0-3 (O, I, J, L, S, Z, T; the SDL2 version's table)
piecedb:
        .word   %0000011001100000, %0000011001100000, %0000011001100000, %0000011001100000
        .word   %0100010001000100, %0000111100000000, %0010001000100010, %0000000011110000
        .word   %0110010001000000, %0000111000100000, %0100010011000000, %1000111000000000
        .word   %0100010001100000, %0000111010000000, %1100010001000000, %0010111000000000
        .word   %0110110000000000, %0100011000100000, %0000011011000000, %1000110001000000
        .word   %1100011000000000, %0010011001000000, %0000110001100000, %0100110010000000
        .word   %0100111000000000, %0100011001000000, %0000111001000000, %0100110001000000
pnames: .byte   "OIJLSZT"
pbits:  .byte   1, 2, 4, 8, 16, 32, 64
; the wall kicks after a turn that does not fit: left, right, up; the long piece two more
kicks:  .word   $FFFF, 0, 1, 0, 0, $FFFF, $FFFE, 0, 2, 0, $7F
rowofs: .repeat SH, I
        .word   I * SW
        .endrepeat
rowy:   .repeat SH, I                   ; a row's place in the window
        .word   WY + I * CELL
        .endrepeat
rowh:   .repeat SH + 1, I               ; n rows' height
        .word   I * CELL
        .endrepeat
; (1.1) the speed of levels 1 .. NLV (above: the last): frames a row, rows a frame, the lock
; delay in frames. About x 0.8 a level down to a row a frame at 16; 2, 3, 5, 10 rows a frame
; at 17-20, at once (20 rows: the whole well) from 21; the lock delay 2 frames shorter each
; level from 21, 10 frames from 30 on.
sp_f:   .byte   60, 48, 38, 30, 24, 19, 15, 12, 10, 8, 6, 5, 4, 3, 2
        .byte   1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
sp_r:   .byte   1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
        .byte   1, 2, 3, 5, 10, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20
sp_l:   .byte   30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30
        .byte   30, 30, 30, 30, 30, 28, 26, 24, 22, 20, 18, 16, 14, 12, 10
pts_line: .word 0, 100, 300, 500, 800
pts_spin: .word 400, 800, 1200, 1600, 1600
pts_mini: .word 100, 200
ta_bonus: .word 0, 2, 4, 6, 10
; the stick (up 1, down 2, left 4, right 8) as game keys: up is the hard drop
joymap: .repeat 16, I
        .byte   ((I & 1) * K_HARD) | ((I & 2) / 2 * K_DOWN) | ((I & 4) / 4 * K_LEFT) | ((I & 8) / 8 * K_RIGHT)
        .endrepeat
; the game keys: HID usage, K_* bit
gkeys:  .byte   $50, K_LEFT, $4F, K_RIGHT, $51, K_DOWN, $52, K_HARD, $2C, K_HARD
        .byte   $1D, K_CCW, $1B, K_CW, $06, K_HOLD, $E1, K_HOLD, $E5, K_HOLD
GKEYN = (* - gkeys) / 2
keytab: .addr   k_title, k_setup, k_none, k_pause, k_none, k_name, k_over, k_scores, k_help
gtab:   .addr   m_new, m_pause, m_scores, m_sound, k_none, quit
ptab:   .addr   m_pause, m_new, m_scores, m_sound, quit
; the menus (setmenus copies them and sets the sound's check mark)
mtmpl:  .byte   "Game", 0, "New game", 9, "F2", 0, "Pause", 9, "Enter", 0, "High scores", 0
msnd:   .byte   MS_STATE, "Sound", 0, "-", 0, "Quit", 0, 0
        .byte   "Help", 0, "How to play", 0, "About Quabricks...", 0, 0, 0
mend:
MSOUND = msnd - mtmpl
MTMPLN = mend - mtmpl
s_pausei: .byte "Pause", 0
s_resume: .byte "Resume", 0
s_newg: .byte   "New game", 0
s_hsc:  .byte   "High scores", 0
s_noscore: .byte "No scores yet: play a game!", 0
s_sound: .byte  "Sound", 0
s_quit: .byte   "Quit", 0
tilep:  .addr   t_e14, t_b14_0, t_b14_1, t_b14_2, t_b14_3, t_b14_4, t_b14_5, t_b14_6
        .addr   t_g14_0, t_g14_1, t_g14_2, t_g14_3, t_g14_4, t_g14_5, t_g14_6, t_s14
; (1.2) the same tiles as rows of the tiles' sheet (t_b14_0 .. t_s14, one after the other)
tilesy: .byte   14 * CELL, 0, CELL, 2 * CELL, 3 * CELL, 4 * CELL, 5 * CELL, 6 * CELL
        .byte   7 * CELL, 8 * CELL, 9 * CELL, 10 * CELL, 11 * CELL, 12 * CELL, 13 * CELL, 15 * CELL
        .assert t_e14 - t_b14_0 = 14 * CELL * CELL && t_s14 - t_b14_0 = 15 * CELL * CELL, error, "the tiles' sheet: one after the other"
slot_y: .word   52, 104, 152, 200, 248
stat_y: .word   STATY + 8, STATY + 34, STATY + 60
stat_lab: .addr s_level, s_lines, s_nextlv, s_time, s_lines, s_level
r_hold: .word   LX, 8, LW, 72
r_holdin: .word LX + 4, 24, LW - 8, 52
r_score: .word  LX, 88, LW, 50
r_stats: .word  LX, STATY, LW, 150
r_next: .word   NX, 8, NW, 288
r_frame: .word  FRX, FRY, FRW, FRH
r_pause: .word  WX + 6, WY + 98, SW * CELL - 12, 70
r_lvbox: .word  CW / 2 - 40, 158, 80, 46
r_name: .word   CW / 2 - 104, 170, 208, 30
btn_x:  .word   CW / 2 - 156, CW / 2 + 6
mode_names: .addr s_mar, s_ta
deco:   .word   26, 24,  338, 40,  58, 250,  306, 256,  352, 128,  20, 132,  200, 266,  96, 236
        .word   286, 228,  150, 30,  250, 18,  12, 300
NDECO = (* - deco) / 4
arr_l:  .byte   $01, $03, $07, $0F, $1F, $3F, $7F, $FF, $FF, $7F, $3F, $1F, $0F, $07, $03, $01
arr_r:  .byte   $80, $C0, $E0, $F0, $F8, $FC, $FE, $FF, $FF, $FE, $FC, $F8, $F0, $E0, $C0, $80
; the POKEY 2 effects (no Lau): the channel (0 / 1), then segments {frames, AUDF, AUDF step a
; frame, volume, its fall a frame in quarters, distortion}, 0
pkseq:  .addr   pk_move, pk_rot, pk_soft, pk_hard, pk_lock, pk_c1, pk_c2, pk_c3, pk_c4
        .addr   pk_lvl, pk_over, pk_mmove, pk_msel, pk_hold, pk_pause
pk_move: .byte  0, 2, 44, 0, 6, 8, $A0, 0
pk_rot: .byte   0, 4, 62, 6, 6, 4, $A0, 0
pk_soft: .byte  0, 2, 114, 0, 4, 6, $A0, 0
pk_hard: .byte  0, 2, 20, 0, 8, 8, $80, 8, 150, 12, 8, 4, $A0, 0
pk_lock: .byte  0, 3, 60, 0, 6, 8, $80, 0
pk_c1:  .byte   1, 5, 53, 0, 7, 4, $A0, 9, 40, 0, 7, 3, $A0, 0
pk_c2:  .byte   1, 4, 53, 0, 7, 4, $A0, 4, 40, 0, 7, 4, $A0, 10, 31, 0, 7, 3, $A0, 0
pk_c3:  .byte   1, 4, 53, 0, 7, 4, $A0, 4, 40, 0, 7, 4, $A0, 4, 31, 0, 7, 4, $A0, 12, 26, 0, 8, 3, $A0, 0
pk_c4:  .byte   1, 4, 53, 0, 8, 4, $A0, 4, 40, 0, 8, 4, $A0, 4, 31, 0, 8, 4, $A0, 4, 26, 0, 8, 4, $A0
        .byte   16, 19, 0, 9, 2, $A0, 0
pk_lvl: .byte   1, 4, 47, 0, 7, 3, $A0, 4, 35, 0, 7, 3, $A0, 4, 28, 0, 7, 3, $A0, 12, 23, 0, 7, 2, $A0, 0
pk_over: .byte  1, 10, 64, 0, 8, 1, $A0, 10, 81, 0, 8, 1, $A0, 10, 96, 0, 8, 1, $A0, 24, 128, 0, 8, 1, $A0, 0
pk_mmove: .byte 0, 2, 50, 0, 5, 8, $A0, 0
pk_msel: .byte  0, 3, 47, 0, 6, 4, $A0, 5, 31, 0, 6, 4, $A0, 0
pk_hold: .byte  0, 4, 58, $FB, 6, 4, $A0, 0
pk_pause: .byte 1, 6, 60, 6, 6, 3, $A0, 0
spinmsg: .addr  s_mini0, s_mini1, s_mini1, s_mini1, s_spin0, s_spin1, s_spin2, s_spin3
wopen:  .word   127, 27, CW, CH
        .faraddr t_title
        .byte   0
p_sfx:  .byte   "/BIN/QUABRICK.SFX", 0
p_dat:  .byte   "/BIN/QUABRICK.DAT", 0
t_title: .byte  "Quabricks", 0
s_tname: .byte  "Quabricks", 0
s_hold: .byte   "HOLD", 0
s_score: .byte  "SCORE", 0
s_next: .byte   "NEXT", 0
s_level: .byte  "LEVEL", 0
s_lines: .byte  "LINES", 0
s_nextlv: .byte "LV UP IN", 0
s_time: .byte   "TIME", 0
s_epause: .byte "Enter: pause", 0
s_quad: .byte   "QUAD!", 0
s_mini0: .byte  "MINI SPIN", 0
s_mini1: .byte  "MINI SPIN SINGLE", 0
s_spin0: .byte  "SPIN", 0
s_spin1: .byte  "SPIN SINGLE", 0
s_spin2: .byte  "SPIN DOUBLE", 0
s_spin3: .byte  "SPIN TRIPLE", 0
s_b2b:  .byte   "BACK-TO-BACK", 0
s_combo: .byte  "COMBO ", 0
s_paused: .byte "PAUSED", 0
s_resume2: .byte "Enter: resume", 0
s_tomenu: .byte "Esc: to the title", 0
s_edition: .byte "ATARI816 EDITION", 0
s_press: .byte  "PRESS ENTER TO PLAY", 0
s_keys1: .byte  "Left / Right move    Down soft drop    Up / Space hard drop", 0
s_keys2: .byte  "Z / X turn    C / Shift hold    Enter pause", 0
s_best: .byte   "BEST   ", 0
s_gap:  .byte   "   ", 0
s_esc:  .byte   "Esc to quit", 0
s_setup: .byte  "GAME SETUP", 0
s_mode: .byte   "MODE", 0
s_mar:  .byte   "MARATHON", 0
s_ta:   .byte   "TIME ATTACK", 0
s_stlv: .byte   "STARTING LEVEL", 0
s_setkeys: .byte "Up / Down mode     Left / Right level     Enter start     Esc back", 0
s_dmar: .byte   "Marathon: clear lines, level up, chase a high score.", 0
s_dta:  .byte   "Time Attack: 60 s on the clock; clear lines to earn seconds.", 0
s_record: .byte "NEW RECORD!", 0
s_final: .byte  "FINAL SCORE", 0
s_yname: .byte  "ENTER YOUR NAME", 0
s_save: .byte   "Press Enter to save", 0
s_gover: .byte  "GAME OVER", 0
s_tup:  .byte   "TIME'S UP!", 0
s_level2: .byte "Level ", 0
s_dot:  .byte   "   -   ", 0
s_lines2: .byte " lines", 0
s_pt:   .byte   ".", 0
s_hsm:  .byte   "HIGH SCORES  -  MARATHON", 0
s_hst:  .byte   "HIGH SCORES  -  TIME ATTACK", 0
s_overkeys: .byte "Enter: to the title     F2: play again", 0
s_hscores: .byte "HIGH SCORES", 0
s_hshead: .byte "Name, level, lines, score", 0
s_hskeys: .byte "Left / Right: the other mode     Enter: back", 0
s_howto: .byte  "HOW TO PLAY", 0
help:   .addr   h1, h2, hs1, hs2, h3, h4, h5, h6, h7, h8, h9, h10, h11, h12, h13, h14, h15, h16, h17, h18, 0
h1:     .byte   "*Fill rows with the falling pieces: a full row clears.", 0
h2:     .byte   "Marathon: a level every 10 lines, and the pieces fall faster:", 0
hs1:    .byte   "a row in 60, 24, 8, 2, 1 frames at level 1, 5, 10, 15, 16;", 0
hs2:    .byte   "17-20: 2-10 rows a frame; 21 on: at once, less time to slide.", 0
h3:     .byte   "Time Attack: 60 seconds; 1, 2, 3, 4 lines add 2, 4, 6, 10 s.", 0
h4:     .byte   " ", 0
h5:     .byte   "*Keys", 0
h6:     .byte   "Left, Right: move", 9, "Down: soft drop", 0
h7:     .byte   "Up, Space: hard drop", 9, "Z, X: turn left, right", 0
h8:     .byte   "C, Shift: hold", 9, "Enter: pause; Esc: back", 0
h9:     .byte   "Joystick 1: move and soft drop, up hard drop, fire turns.", 0
h10:    .byte   " ", 0
h11:    .byte   "*Points (times the level)", 0
h12:    .byte   "1, 2, 3 lines: 100, 300, 500", 9, "4 lines, a Quad: 800", 0
h13:    .byte   "Spin (a T turned into a slot): 400, 800, 1200, 1600", 0
h14:    .byte   "Mini spin: 100, 200", 9, "Soft drop 1, hard drop 2 a row", 0
h15:    .byte   "A Quad or spin right after another: back-to-back, x 1.5", 0
h16:    .byte   "Pieces clearing lines in a row: a combo, + 50 x combo", 0
h17:    .byte   " ", 0
h18:    .byte   "*Any key: back", 0
s_about: .byte  "Quabricks for the Atari816, version 1.2", 10
        .byte   "A falling-block game after the SDL2 Quabricks (MIT).", 10
        .byte   "Sound: Lau samples, or POKEY 2 without Lau.", 0
s_aboutt: .byte "About Quabricks", 0
s_ok:   .byte   "OK", 0
al_about: .word AL_INFO
        .addr   s_aboutt, s_about, s_ok, 0, 0

; the self test's cases: name, rows 16-19 (bit 0 = column 0), piece, turn, x, y ($FFFF: where
; it falls), up to 3 more cells (column | row << 8), the last action a turn, the points
.macro  qcase     name, r16, r17, r18, r19, tp, tr, tx, ty, c1, c2, c3, rot, ex
        .addr   name
        .word   r16, r17, r18, r19, tp, tr, tx, ty, c1, c2, c3, rot, ex
.endmacro
tc_single: qcase  n_single, 0, 0, 0, $3FE, I_PIECE, 0, $FFFF, $FFFF, 0, 0, 0, 0, 100
tc_double: qcase  n_double, 0, 0, $3FE, $3FE, I_PIECE, 0, $FFFF, $FFFF, 0, 0, 0, 0, 300
tc_triple: qcase  n_triple, 0, $3FE, $3FE, $3FE, I_PIECE, 0, $FFFF, $FFFF, 0, 0, 0, 0, 500
tc_quad: qcase    n_quad, $3FE, $3FE, $3FE, $3FE, I_PIECE, 0, $FFFF, $FFFF, 0, 0, 0, 0, 800
tc_quad3: qcase   n_quad, $3FE, $3FE, $3FE, $3FE, I_PIECE, 0, $FFFF, $FFFF, 0, 0, 0, 0, 2400
tc_spin2: qcase   n_spin2, 0, 0, $3C7, $3EF, T_PIECE, 2, 3, 17, $1103, 0, 0, 1, 1200
tc_spin0: qcase   n_spin0, 0, 0, $1C7, $1EF, T_PIECE, 2, 3, 17, $1103, 0, 0, 1, 400
tc_mini: qcase    n_mini, 0, 0, 0, 0, T_PIECE, 0, 3, 18, $1302, $1306, $1104, 1, 100
tc_tdrop: qcase   n_tdrop, 0, 0, $3C7, $3EF, T_PIECE, 2, 3, 17, $1103, 0, 0, 0, 300
tc_none: qcase    n_none, 0, 0, 0, 0, 0, 0, 0, $FFFF, 0, 0, 0, 0, 0
tb_q1:  qcase     n_quad, $3FE, $3FE, $3FE, $3FE, I_PIECE, 0, $FFFF, $FFFF, 0, 0, 0, 0, 800
tb_q2:  qcase     n_b2bc, $3FE, $3FE, $3FE, $3FE, I_PIECE, 0, $FFFF, $FFFF, 0, 0, 0, 0, 1250
tb_q3:  qcase     n_b2b, $3FE, $3FE, $3FE, $3FE, I_PIECE, 0, $FFFF, $FFFF, 0, 0, 0, 0, 1200
tb_s1:  qcase     n_s1, 0, 0, 0, $3FE, I_PIECE, 0, $FFFF, $FFFF, 0, 0, 0, 0, 300
tb_s2:  qcase     n_s2, 0, 0, 0, $3FE, I_PIECE, 0, $FFFF, $FFFF, 0, 0, 0, 0, 400
tb_q4:  qcase     n_q4, $3FE, $3FE, $3FE, $3FE, I_PIECE, 0, $FFFF, $FFFF, 0, 0, 0, 0, 1900
tb_sp:  qcase     n_sp, 0, 0, $3C7, $3EF, T_PIECE, 2, 3, 17, $1103, 0, 0, 1, 4000
tb_ta2: qcase     n_double, 0, 0, $3FE, $3FE, I_PIECE, 0, $FFFF, $FFFF, 0, 0, 0, 0, 300
tb_ta4: qcase     n_qc1, $3FE, $3FE, $3FE, $3FE, I_PIECE, 0, $FFFF, $FFFF, 0, 0, 0, 0, 850
tb_d3:  qcase     n_dc2, 0, 0, $3FE, $3FE, I_PIECE, 0, $FFFF, $FFFF, 0, 0, 0, 0, 400
n_single: .byte "single", 0
n_double: .byte "double", 0
n_triple: .byte "triple", 0
n_quad: .byte   "Quad", 0
n_spin2: .byte  "spin double", 0
n_spin0: .byte  "spin, no lines", 0
n_mini: .byte   "mini spin", 0
n_tdrop: .byte  "T dropped into the slot (no turn): a double", 0
n_none: .byte   "nothing cleared", 0
n_b2bc: .byte   "Quad, back-to-back, combo 1", 0
n_b2b:  .byte   "Quad, back-to-back (level 2 from here)", 0
n_s1:   .byte   "single, combo 1", 0
n_s2:   .byte   "single, combo 2", 0
n_q4:   .byte   "Quad (no back-to-back after singles), combo 3", 0
n_sp:   .byte   "spin double, back-to-back, combo 4", 0
n_qc1:  .byte   "Quad, combo 1", 0
n_dc2:  .byte   "double, combo 2", 0

        .segment "BSS"
argl:   .res    2
argx:   .res    2
wsown:  .res    2
win:    .res    2
pbank:  .res    2
tmode:  .res    2
mflag:  .res    2
qforce: .res    2                       ; the forced pieces: where, the first game's
qfirst: .res    2
qlist:  .res    64
seed:   .res    4
sfixed: .res    2
rng:    .res    4
pcells: .res    7 * 4 * 8
pbox:   .res    7 * 4
pool:   .res    8
bag:    .res    8
bagn:   .res    2
stage:  .res    SW * SH + 2
stage0: .res    SW * SH + 2
queue:  .res    6
hold:   .res    2
holdused: .res  2
score:  .res    4
lines:  .res    2
level:  .res    2
startlv: .res   2
nextlv: .res    2
combo:  .res    2
b2b:    .res    2
over:   .res    2
timeup: .res    2
dasd:   .res    2
dast:   .res    2
npieces: .res   2
tsec:   .res    2
tfr:    .res    2
speed:  .res    2
srows:  .res    2
lockd:  .res    2
gfn:    .res    2
lowest: .res    2
lastrot: .res   2
lockt:  .res    2
lres:   .res    2
grav:   .res    2
kpress: .res    2
kheld:  .res    2
kheldk: .res    2
jheld:  .res    2
mode:   .res    2
vmode:  .res    2
state:  .res    2
backst: .res    2
gflags: .res    2
bonusf: .res    2
spin:   .res    2
lockout: .res   2
nclr:   .res    2
clr:    .res    8
lastpts: .res   4
r32:    .res    4
flashn: .res    2
shaken: .res    2
msgt:   .res    2
sweepn: .res    2
blink:  .res    2
nlen:   .res    2
nbuf:   .res    NAMEMAX + 2
caretx: .res    2
hrank:  .res    2
sndon:  .res    2
sndok:  .res    2
lau:    .res    2
sbank:  .res    2
pk_on:  .res    2
pk_p:   .res    4
pk_n:   .res    4
pk_f:   .res    4
pk_fs:  .res    4
pk_v:   .res    4
pk_vd:  .res    4
pk_d:   .res    4
spb:    .res    18
iob:    .res    6
fbuf:   .res    DATLEN + 2
hs_tab: .res    2 * HSN * HSZ
mbuf:   .res    256
msgbuf: .res    80
numbuf: .res    16
bigbuf: .res    24 * 3 * 21
db:     .res    18
cmap:   .res    258                     ; (1.1) local colour -> palette entry
nruns:  .res    2                       ; the runs of entries: first, end, local, count
runfirst: .res  2 * NCOLS
runend: .res    2 * NCOLS
runloc: .res    2 * NCOLS
runcnt: .res    2 * NCOLS
palbuf: .res    3 * NCOLS
lhw:    .res    2                       ; (1.1) Ali runs command lists (REV $09+)
lon:    .res    2                       ; (1.1) the frame's draw list: on, LS_VBL for the next
lvbl:   .res    2                       ; record, records, sent and maybe running, arena used
lcnt:   .res    2
lpend:  .res    2
laren:  .res    2
ltqn:   .res    2
lsh:    .res    2                       ; (1.2) the sheets: tiles, erow / srow (0: none)
lsh2:   .res    2
lall:   .res    2                       ;   every record so far can be a sheet record
lshn:   .res    2                       ;   the next record's sheet (1 tiles, 2 rows) | sy << 8
lsv:    .res    LMAX * 2                ;   each record's: 0 none, 1, 2 | sy << 8, $FF a fill
lsvt:   .res    2
lshb:   .res    10                      ;   sheet_new's block
lc_i:   .res    2                       ;   lconv: the record, its fields
lc_x:   .res    2
lc_y:   .res    2
lc_w:   .res    2
lc_h:   .res    2
lc_c:   .res    2
lc_op:  .res    2
lc_sv:  .res    2
lc_sh:  .res    2
lbuf:   .res    LMAX * 20
larena: .res    LARENA
ltq:    .res    LTQN * LTQSZ
shown:  .res    SW * SH + 2
ov:     .res    SW * SH + 2
oc:     .res    16
noc:    .res    2
oldc:   .res    16
dpx:    .res    2
dpy:    .res    2
dpr:    .res    2
dpt:    .res    2
erow:   .res    SW * CELL * CELL
srow:   .res    SW * CELL * CELL
cposx:  .res    SW * SH * 2
cposy:  .res    SW * SH * 2
nsys:   .res    2
mt0:    .res    2
mbusy:  .res    4
mframes: .res   2
mdrop:  .res    2
mvbl:   .res    2
mvok:   .res    2
msys0:  .res    2
msysmax: .res   2
shtop:  .res    2
tfail:  .res    2
tcp:    .res    2
tsave:  .res    4
tlv:    .res    2

        .segment "ZEROPAGE"
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
px:     .res    2                       ; the piece: place, turn, type
py:     .res    2
pr:     .res    2
pt:     .res    2
tx:     .res    2                       ; a place being tried
ty:     .res    2
tr:     .res    2
vn:     .res    2
vx:     .res    2
rx:     .res    2                       ; a rectangle to draw
ry:     .res    2
rw:     .res    2
rh:     .res    2
svx:    .res    2
svy:    .res    2
svw:    .res    2
svh:    .res    2
cx:     .res    2
cy:     .res    2
bk:     .res    2                       ; the big font: scale, colours, string, length, ...
bink:   .res    2
bs:     .res    2
bn:     .res    2
bstr:   .res    2
bwid:   .res    2
n0:     .res    2
n1:     .res    2
dsrc:   .res    2
tt:     .res    2
csz:    .res    2
ku:     .res    2
kd:     .res    2
nold:   .res    2
p:      .res    4
rq:     .res    2
xct:    .res    2
bbase:  .res    2
lop:    .res    2
lfl:    .res    2
