; calc_data.s - the Calculator's tables, fonts, test cases and variables (included by calc.s).

MAXDIG  = 15                            ; digits typed at most

; a key: x, y, w, h, code, style, label (a string, or an icon 1-10)
.macro  key     kx, ky, kw, kh, kcode, ksty, klbl
        .word   kx, ky, kw, kh
        .byte   kcode, ksty
        .addr   klbl
.endmacro
; Standard: 5 columns of 36 (40 apart) from x 8, 6 rows of 24 (28 apart) from y 60
.macro  sk      c, r, kcode, ksty, klbl
        key     8 + 40 * c, 60 + 28 * r, 36, 24, kcode, ksty, klbl
.endmacro
; Programmer: 6 columns of 40 (44 apart), rows from y 106
.macro  pk      c, r, kcode, ksty, klbl
        key     8 + 44 * c, 96 + 28 * r, 40, 24, kcode, ksty, klbl
.endmacro
; icon parts: a filled rectangle / a line, around the key's centre
.macro  ifill   ax, ay, aw, ah
        .byte   WD_FILL, <(ax), <(ay), <(aw), <(ah)
.endmacro
.macro  iline   ax, ay, ax2, ay2
        .byte   WD_LINE, <(ax), <(ay), <(ax2), <(ay2)
.endmacro
; a glyph row: '#' = ink, the first character is bit 7
gv      .set    0
.macro  grow    gs
        gv      .set    0
        .repeat .strlen(gs), I
        .if     .strat(gs, I) = '#'
        gv      .set    gv | ($80 >> I)
        .endif
        .endrepeat
        .byte   gv
.endmacro

I_PLUS  = 1
I_MINUS = 2
I_TIMES = 3
I_DIV   = 4
I_EQ    = 5
I_PM    = 6
I_SQRT  = 7
I_BACK  = 8
I_SQR   = 9
I_DOT   = 10

        .segment "RODATA"
menus:  .byte   "Edit", 0, "Copy", 9, "Ctrl+C", 0, "Paste", 9, "Ctrl+V", 0, 0
        .byte   "View", 0, MS_STATE | MS_CHECK, "Standard", 0, MS_STATE, "Programmer", 0, 0, 0
        .res    128 - (* - menus)
pmenus: .byte   "Edit", 0, "Copy", 9, "Ctrl+C", 0, "Paste", 9, "Ctrl+V", 0, 0
        .byte   "View", 0, MS_STATE, "Standard", 0, MS_STATE | MS_CHECK, "Programmer", 0, 0, 0
        .res    128 - (* - pmenus)
t_title: .byte  "Calculator", 0

skeys:  sk      0, 0, 'k', ST_FN, l_mc
        sk      1, 0, 'r', ST_FN, l_mr
        sk      2, 0, 'p', ST_FN, l_mp
        sk      3, 0, 'm', ST_FN, l_mm
        sk      4, 0, 'B', ST_FN, I_BACK
        sk      0, 1, 'C', ST_CLR, l_c
        sk      1, 1, 'E', ST_CLR, l_ce
        sk      2, 1, 'N', ST_FN, I_PM
        sk      3, 1, 'Q', ST_FN, I_SQRT
        sk      4, 1, 'I', ST_FN, l_inv
        sk      0, 2, '7', ST_DIG, l_7
        sk      1, 2, '8', ST_DIG, l_8
        sk      2, 2, '9', ST_DIG, l_9
        sk      3, 2, '/', ST_OP, I_DIV
        sk      4, 2, '%', ST_FN, l_pct
        sk      0, 3, '4', ST_DIG, l_4
        sk      1, 3, '5', ST_DIG, l_5
        sk      2, 3, '6', ST_DIG, l_6
        sk      3, 3, '*', ST_OP, I_TIMES
        sk      4, 3, 'S', ST_FN, I_SQR
        sk      0, 4, '1', ST_DIG, l_1
        sk      1, 4, '2', ST_DIG, l_2
        sk      2, 4, '3', ST_DIG, l_3
        sk      3, 4, '-', ST_OP, I_MINUS
        key     8 + 40 * 4, 60 + 28 * 4, 36, 52, '=', ST_EQ, I_EQ
        key     8, 60 + 28 * 5, 76, 24, '0', ST_DIG, l_0
        sk      2, 5, '.', ST_DIG, I_DOT
        sk      3, 5, '+', ST_OP, I_PLUS
        .word   0, 0, 0, 0

pkeys:  pk      0, 0, '&', ST_OP, l_and
        pk      1, 0, '|', ST_OP, l_or
        pk      2, 0, '^', ST_OP, l_xor
        pk      3, 0, '~', ST_FN, l_not
        pk      4, 0, '<', ST_OP, l_shl
        pk      5, 0, '>', ST_OP, l_shr
        pk      0, 1, 'L', ST_FN, l_rol
        pk      1, 1, 'R', ST_FN, l_ror
        pk      2, 1, '%', ST_OP, l_mod
        pk      3, 1, 'N', ST_FN, I_PM
        pk      4, 1, 'B', ST_FN, I_BACK
        pk      5, 1, 'C', ST_CLR, l_clr
        pk      0, 2, 'a', ST_DIG, l_a
        pk      1, 2, 'b', ST_DIG, l_b
        pk      2, 2, '7', ST_DIG, l_7
        pk      3, 2, '8', ST_DIG, l_8
        pk      4, 2, '9', ST_DIG, l_9
        pk      5, 2, '/', ST_OP, I_DIV
        pk      0, 3, 'c', ST_DIG, l_cc
        pk      1, 3, 'd', ST_DIG, l_d
        pk      2, 3, '4', ST_DIG, l_4
        pk      3, 3, '5', ST_DIG, l_5
        pk      4, 3, '6', ST_DIG, l_6
        pk      5, 3, '*', ST_OP, I_TIMES
        pk      0, 4, 'e', ST_DIG, l_e
        pk      1, 4, 'f', ST_DIG, l_f
        pk      2, 4, '1', ST_DIG, l_1
        pk      3, 4, '2', ST_DIG, l_2
        pk      4, 4, '3', ST_DIG, l_3
        pk      5, 4, '-', ST_OP, I_MINUS
        key     8, 96 + 28 * 5, 84, 24, 'E', ST_CLR, l_ce
        key     8 + 44 * 2, 96 + 28 * 5, 84, 24, '0', ST_DIG, l_0
        pk      4, 5, '=', ST_EQ, I_EQ
        pk      5, 5, '+', ST_OP, I_PLUS
        .word   0, 0, 0, 0

l_mc:   .byte   "MC", 0
l_mr:   .byte   "MR", 0
l_mp:   .byte   "M+", 0
l_mm:   .byte   "M-", 0
l_c:    .byte   "C", 0
l_ce:   .byte   "CE", 0
l_inv:  .byte   "1/x", 0
l_pct:  .byte   "%", 0
l_0:    .byte   "0", 0
l_1:    .byte   "1", 0
l_2:    .byte   "2", 0
l_3:    .byte   "3", 0
l_4:    .byte   "4", 0
l_5:    .byte   "5", 0
l_6:    .byte   "6", 0
l_7:    .byte   "7", 0
l_8:    .byte   "8", 0
l_9:    .byte   "9", 0
l_a:    .byte   "A", 0
l_b:    .byte   "B", 0
l_cc:   .byte   "C", 0
l_d:    .byte   "D", 0
l_e:    .byte   "E", 0
l_f:    .byte   "F", 0
l_and:  .byte   "And", 0
l_or:   .byte   "Or", 0
l_xor:  .byte   "Xor", 0
l_not:  .byte   "Not", 0
l_shl:  .byte   "<<", 0
l_shr:  .byte   ">>", 0
l_rol:  .byte   "RoL", 0
l_ror:  .byte   "RoR", 0
l_mod:  .byte   "Mod", 0
l_clr:  .byte   "Clr", 0

icons:  .addr   ic_plus, ic_minus, ic_times, ic_div, ic_eq, ic_pm, ic_sqrt, ic_back, ic_sqr
        .addr   ic_dot
ic_plus: ifill  -5, -1, 10, 2
        ifill   -1, -5, 2, 10
        .byte   0
ic_minus: ifill -5, -1, 10, 2
        .byte   0
ic_times: iline -4, -4, 3, 3
        iline   -3, -4, 4, 3
        iline   -4, 3, 3, -4
        iline   -3, 3, 4, -4
        .byte   0
ic_div: ifill   -5, -1, 10, 2
        ifill   -1, -5, 2, 2
        ifill   -1, 3, 2, 2
        .byte   0
ic_eq:  ifill   -5, -3, 10, 2
        ifill   -5, 2, 10, 2
        .byte   0
ic_pm:  ifill   -3, -2, 7, 1
        ifill   0, -5, 1, 7
        ifill   -3, 4, 7, 1
        .byte   0
ic_sqrt: iline  -7, 0, -5, 4
        iline   -5, 4, -2, -5
        iline   -2, -5, 6, -5
        iline   0, -2, 4, 2
        iline   0, 2, 4, -2
        .byte   0
ic_back: iline  -5, 0, 5, 0
        iline   -5, 0, -2, -3
        iline   -5, 0, -2, 3
        .byte   0
ic_sqr: iline   -5, -2, -1, 2
        iline   -5, 2, -1, -2
        ifill   1, -5, 3, 1
        ifill   3, -4, 1, 1
        ifill   1, -3, 3, 1
        ifill   1, -2, 1, 1
        ifill   1, -1, 3, 1
        .byte   0
ic_dot: ifill   -1, 2, 3, 3
        .byte   0

; key colours by style: fill | pressed fill << 8; ink
kfill:  .word   C_WHITE | (C_LIGHT << 8), C_LIGHT | (C_MID << 8), C_BODY | (C_MID << 8)
        .word   C_SELECT | (C_TITLE << 8), C_BODY | (C_MID << 8)
kink:   .word   C_BLACK, C_BLACK, C_BLACK, C_WHITE, C_RED

; keyboard: (key, code) pairs; for both views, Standard, Programmer
ktab_c: .byte   13, '=', 27, 'C', 8, 'B', KEY_DEL, 'E', '.', '.', ',', '.', '+', '+', '-', '-'
        .byte   '*', '*', '/', '/', '=', '=', '%', '%', 'n', 'N', 0
ktab_s: .byte   'r', 'I', '@', 'Q', 'q', 'S', 'c', 'C', 0
ktab_p: .byte   '&', '&', '|', '|', '^', '^', '~', '~', '<', '<', '>', '>', 0

; calc_key's routines
stab:   .byte   '+'
        .addr   s_binop
        .byte   '-'
        .addr   s_binop
        .byte   '*'
        .addr   s_binop
        .byte   '/'
        .addr   s_binop
        .byte   '='
        .addr   s_equal
        .byte   '%'
        .addr   s_pct
        .byte   'C'
        .addr   s_clear
        .byte   'E'
        .addr   s_ce
        .byte   'B'
        .addr   s_back
        .byte   'N'
        .addr   s_neg
        .byte   'Q'
        .addr   s_sqrt
        .byte   'I'
        .addr   s_inv
        .byte   'S'
        .addr   s_sqr
        .byte   'k'
        .addr   s_mc
        .byte   'r'
        .addr   s_mr
        .byte   'p'
        .addr   s_mplus
        .byte   'm'
        .addr   s_mplus
        .byte   'V'
        .addr   s_toprog
        .byte   0
ptab:   .byte   '+'
        .addr   p_binop
        .byte   '-'
        .addr   p_binop
        .byte   '*'
        .addr   p_binop
        .byte   '/'
        .addr   p_binop
        .byte   '%'
        .addr   p_binop
        .byte   '&'
        .addr   p_binop
        .byte   '|'
        .addr   p_binop
        .byte   '^'
        .addr   p_binop
        .byte   '<'
        .addr   p_binop
        .byte   '>'
        .addr   p_binop
        .byte   '='
        .addr   p_equal
        .byte   'C'
        .addr   s_clear
        .byte   'E'
        .addr   p_ce
        .byte   'B'
        .addr   p_back
        .byte   'N'
        .addr   p_neg
        .byte   '~'
        .addr   p_not
        .byte   'L'
        .addr   p_rol
        .byte   'R'
        .addr   p_ror
        .byte   'H'
        .addr   p_base
        .byte   'D'
        .addr   p_base
        .byte   'O'
        .addr   p_base
        .byte   'Y'
        .addr   p_base
        .byte   'W'
        .addr   p_tostd
        .byte   0

basecode: .byte "HDOY"
bases:  .word   16, 10, 8, 2
s_hex:  .byte   "HEX", 0, "DEC", 0, "OCT", 0, "BIN", 0
s_m:    .byte   "M", 0
errmsg: .addr   e_div, e_ovf, e_inv
e_div:  .byte   "Cannot divide by zero", 0
e_ovf:  .byte   "Overflow", 0
e_inv:  .byte   "Invalid input", 0
opnames: .byte  '+', o_plus - opstr, '-', o_minus - opstr, '*', o_times - opstr
        .byte   '/', o_div - opstr, '%', o_mod - opstr, '&', o_and - opstr
        .byte   '|', o_or - opstr, '^', o_xor - opstr, '<', o_shl - opstr, '>', o_shr - opstr
opstr:
o_plus: .byte   "+", 0
o_minus: .byte  "-", 0
o_times: .byte  "*", 0
o_div:  .byte   "/", 0
o_mod:  .byte   "MOD", 0
o_and:  .byte   "AND", 0
o_or:   .byte   "OR", 0
o_xor:  .byte   "XOR", 0
o_shl:  .byte   "<<", 0
o_shr:  .byte   ">>", 0
n_one:  .word   0, 0                    ; 1
        .byte   1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
t_rej:  .byte   "rejected", 0

; the display's big font: 8 x 14, advance 10 ('.' 5)
bigch:  .byte   "0123456789ABCDEF-.e+"
NBIG    = 20
DOTIDX  = 17
bigfont:
        grow    "..####.."              ; 0
        grow    ".##..##."
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    ".##..##."
        grow    "..####.."
        grow    "...##..."              ; 1
        grow    "..###..."
        grow    ".####..."
        grow    "##.##..."
        grow    "...##..."
        grow    "...##..."
        grow    "...##..."
        grow    "...##..."
        grow    "...##..."
        grow    "...##..."
        grow    "...##..."
        grow    "...##..."
        grow    "...##..."
        grow    ".######."
        grow    "..####.."              ; 2
        grow    ".##..##."
        grow    "##....##"
        grow    "......##"
        grow    "......##"
        grow    ".....##."
        grow    "....##.."
        grow    "...##..."
        grow    "..##...."
        grow    ".##....."
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "########"
        grow    "..####.."              ; 3
        grow    ".##..##."
        grow    "##....##"
        grow    "......##"
        grow    "......##"
        grow    ".....##."
        grow    "...###.."
        grow    ".....##."
        grow    "......##"
        grow    "......##"
        grow    "......##"
        grow    "##....##"
        grow    ".##..##."
        grow    "..####.."
        grow    ".....##."              ; 4
        grow    "....###."
        grow    "...####."
        grow    "..##.##."
        grow    ".##..##."
        grow    "##...##."
        grow    "##...##."
        grow    "########"
        grow    ".....##."
        grow    ".....##."
        grow    ".....##."
        grow    ".....##."
        grow    ".....##."
        grow    ".....##."
        grow    "########"              ; 5
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##.###.."
        grow    "###..##."
        grow    "......##"
        grow    "......##"
        grow    "......##"
        grow    "......##"
        grow    "......##"
        grow    "##....##"
        grow    ".##..##."
        grow    "..####.."
        grow    "...###.."              ; 6
        grow    "..##...."
        grow    ".##....."
        grow    "##......"
        grow    "##......"
        grow    "##.###.."
        grow    "###..##."
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    ".##..##."
        grow    "..####.."
        grow    "########"              ; 7
        grow    "......##"
        grow    "......##"
        grow    ".....##."
        grow    ".....##."
        grow    "....##.."
        grow    "....##.."
        grow    "...##..."
        grow    "...##..."
        grow    "..##...."
        grow    "..##...."
        grow    "..##...."
        grow    "..##...."
        grow    "..##...."
        grow    "..####.."              ; 8
        grow    ".##..##."
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    ".##..##."
        grow    "..####.."
        grow    ".##..##."
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    ".##..##."
        grow    "..####.."
        grow    "..####.."              ; 9
        grow    ".##..##."
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    ".##..###"
        grow    "..###.##"
        grow    "......##"
        grow    "......##"
        grow    ".....##."
        grow    "....##.."
        grow    "..###..."
        grow    "...##..."              ; A
        grow    "..####.."
        grow    ".##..##."
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "########"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "######.."              ; B
        grow    "##...##."
        grow    "##....##"
        grow    "##....##"
        grow    "##...##."
        grow    "######.."
        grow    "##...##."
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##...##."
        grow    "######.."
        grow    "..####.."              ; C
        grow    ".##..##."
        grow    "##....##"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##....##"
        grow    ".##..##."
        grow    "..####.."
        grow    "#####..."              ; D
        grow    "##..##.."
        grow    "##...##."
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##....##"
        grow    "##...##."
        grow    "##..##.."
        grow    "#####..."
        grow    "########"              ; E
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "######.."
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "########"
        grow    "########"              ; F
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "######.."
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        grow    "##......"
        .repeat 7                       ; -
        .byte   0
        .endrepeat
        grow    ".######."
        grow    ".######."
        .repeat 5
        .byte   0
        .endrepeat
        .repeat 12                      ; .
        .byte   0
        .endrepeat
        grow    "##......"
        grow    "##......"
        .repeat 5                       ; e
        .byte   0
        .endrepeat
        grow    "..####.."
        grow    ".##..##."
        grow    "##....##"
        grow    "########"
        grow    "##......"
        grow    "##......"
        grow    "##....##"
        grow    ".##..##."
        grow    "..####.."
        .repeat 5                       ; +
        .byte   0
        .endrepeat
        grow    "...##..."
        grow    "...##..."
        grow    ".######."
        grow    ".######."
        grow    "...##..."
        grow    "...##..."
        .repeat 3
        .byte   0
        .endrepeat

; the small font: 5 x 7, advance 6 ('*' is a times sign, '/' a divide sign)
minch:  .byte   "0123456789ABCDEFHILMNORTX.-+*/=<>%e"
NMIN    = 35
minfont:
        grow    ".###."                 ; 0
        grow    "#...#"
        grow    "#..##"
        grow    "#.#.#"
        grow    "##..#"
        grow    "#...#"
        grow    ".###."
        grow    "..#.."                 ; 1
        grow    ".##.."
        grow    "..#.."
        grow    "..#.."
        grow    "..#.."
        grow    "..#.."
        grow    ".###."
        grow    ".###."                 ; 2
        grow    "#...#"
        grow    "....#"
        grow    "...#."
        grow    "..#.."
        grow    ".#..."
        grow    "#####"
        grow    "#####"                 ; 3
        grow    "...#."
        grow    "..#.."
        grow    "...#."
        grow    "....#"
        grow    "#...#"
        grow    ".###."
        grow    "...#."                 ; 4
        grow    "..##."
        grow    ".#.#."
        grow    "#..#."
        grow    "#####"
        grow    "...#."
        grow    "...#."
        grow    "#####"                 ; 5
        grow    "#...."
        grow    "####."
        grow    "....#"
        grow    "....#"
        grow    "#...#"
        grow    ".###."
        grow    "..##."                 ; 6
        grow    ".#..."
        grow    "#...."
        grow    "####."
        grow    "#...#"
        grow    "#...#"
        grow    ".###."
        grow    "#####"                 ; 7
        grow    "....#"
        grow    "...#."
        grow    "..#.."
        grow    ".#..."
        grow    ".#..."
        grow    ".#..."
        grow    ".###."                 ; 8
        grow    "#...#"
        grow    "#...#"
        grow    ".###."
        grow    "#...#"
        grow    "#...#"
        grow    ".###."
        grow    ".###."                 ; 9
        grow    "#...#"
        grow    "#...#"
        grow    ".####"
        grow    "....#"
        grow    "...#."
        grow    ".##.."
        grow    ".###."                 ; A
        grow    "#...#"
        grow    "#...#"
        grow    "#####"
        grow    "#...#"
        grow    "#...#"
        grow    "#...#"
        grow    "####."                 ; B
        grow    "#...#"
        grow    "#...#"
        grow    "####."
        grow    "#...#"
        grow    "#...#"
        grow    "####."
        grow    ".###."                 ; C
        grow    "#...#"
        grow    "#...."
        grow    "#...."
        grow    "#...."
        grow    "#...#"
        grow    ".###."
        grow    "###.."                 ; D
        grow    "#..#."
        grow    "#...#"
        grow    "#...#"
        grow    "#...#"
        grow    "#..#."
        grow    "###.."
        grow    "#####"                 ; E
        grow    "#...."
        grow    "#...."
        grow    "####."
        grow    "#...."
        grow    "#...."
        grow    "#####"
        grow    "#####"                 ; F
        grow    "#...."
        grow    "#...."
        grow    "####."
        grow    "#...."
        grow    "#...."
        grow    "#...."
        grow    "#...#"                 ; H
        grow    "#...#"
        grow    "#...#"
        grow    "#####"
        grow    "#...#"
        grow    "#...#"
        grow    "#...#"
        grow    ".###."                 ; I
        grow    "..#.."
        grow    "..#.."
        grow    "..#.."
        grow    "..#.."
        grow    "..#.."
        grow    ".###."
        grow    "#...."                 ; L
        grow    "#...."
        grow    "#...."
        grow    "#...."
        grow    "#...."
        grow    "#...."
        grow    "#####"
        grow    "#...#"                 ; M
        grow    "##.##"
        grow    "#.#.#"
        grow    "#.#.#"
        grow    "#...#"
        grow    "#...#"
        grow    "#...#"
        grow    "#...#"                 ; N
        grow    "##..#"
        grow    "#.#.#"
        grow    "#..##"
        grow    "#...#"
        grow    "#...#"
        grow    "#...#"
        grow    ".###."                 ; O
        grow    "#...#"
        grow    "#...#"
        grow    "#...#"
        grow    "#...#"
        grow    "#...#"
        grow    ".###."
        grow    "####."                 ; R
        grow    "#...#"
        grow    "#...#"
        grow    "####."
        grow    "#.#.."
        grow    "#..#."
        grow    "#...#"
        grow    "#####"                 ; T
        grow    "..#.."
        grow    "..#.."
        grow    "..#.."
        grow    "..#.."
        grow    "..#.."
        grow    "..#.."
        grow    "#...#"                 ; X
        grow    "#...#"
        grow    ".#.#."
        grow    "..#.."
        grow    ".#.#."
        grow    "#...#"
        grow    "#...#"
        grow    "....."                 ; .
        grow    "....."
        grow    "....."
        grow    "....."
        grow    "....."
        grow    ".##.."
        grow    ".##.."
        grow    "....."                 ; -
        grow    "....."
        grow    "....."
        grow    "#####"
        grow    "....."
        grow    "....."
        grow    "....."
        grow    "....."                 ; +
        grow    "..#.."
        grow    "..#.."
        grow    "#####"
        grow    "..#.."
        grow    "..#.."
        grow    "....."
        grow    "....."                 ; * (times)
        grow    "#...#"
        grow    ".#.#."
        grow    "..#.."
        grow    ".#.#."
        grow    "#...#"
        grow    "....."
        grow    "....."                 ; / (divide)
        grow    "..#.."
        grow    "....."
        grow    "#####"
        grow    "....."
        grow    "..#.."
        grow    "....."
        grow    "....."                 ; =
        grow    "....."
        grow    "#####"
        grow    "....."
        grow    "#####"
        grow    "....."
        grow    "....."
        grow    "...#."                 ; <
        grow    "..#.."
        grow    ".#..."
        grow    "#...."
        grow    ".#..."
        grow    "..#.."
        grow    "...#."
        grow    ".#..."                 ; >
        grow    "..#.."
        grow    "...#."
        grow    "....#"
        grow    "...#."
        grow    "..#.."
        grow    ".#..."
        grow    "##..#"                 ; %
        grow    "##.#."
        grow    "...#."
        grow    "..#.."
        grow    ".#..."
        grow    ".#.##"
        grow    "#..##"
        grow    "....."                 ; e
        grow    "....."
        grow    ".###."
        grow    "#...#"
        grow    "#####"
        grow    "#...."
        grow    ".###."

; the self test: K keys -> the display; P text pasted (Q: in the Programmer view)
.macro  tc      tkind, tkey, twant
        .byte   tkind, tkey, 0, twant, 0
.endmacro
ttab:   tc      'K', "0.1+0.2=", "0.3"
        tc      'K', "0.1+0.7=", "0.8"
        tc      'K', "4.35*100=", "435"
        tc      'K', "1.005*1000=", "1005"
        tc      'K', "1-0.9=", "0.1"
        tc      'K', "1.1*1.1=", "1.21"
        tc      'K', "2+3*4=", "20"
        tc      'K', "2+*4=", "8"
        tc      'K', "8-10=", "-2"
        tc      'K', "10/4=", "2.5"
        tc      'K', "1/3=", "0.333333333333333"
        tc      'K', "2/3=", "0.666666666666667"
        tc      'K', "1/3*3=", "1"
        tc      'K', "1/7=*7=", "1"
        tc      'K', "2+3===", "11"
        tc      'K', "2*=", "4"
        tc      'K', "5+N=", "0"
        tc      'K', "2+3E4=", "6"
        tc      'K', "50+10%", "5"
        tc      'K', "50+10%=", "55"
        tc      'K', "200*15%=", "30"
        tc      'K', "2Q", "1.4142135623731"
        tc      'K', "9Q", "3"
        tc      'K', "0.0004Q", "0.02"
        tc      'K', "2QS", "2"
        tc      'K', "1000000*1000000=", "1000000000000"
        tc      'K', "999999999999999+1=", "1e+15"
        tc      'K', "99999999999999*99999999999999=", "1e+28"
        tc      'K', "123456789*987654321=", "1.21932631113e+17"
        tc      'K', "0.000001*0.000001=", "1e-12"
        tc      'K', "0.00001*1=", "0.00001"
        tc      'K', "1/3/100000=", "3.33333333333e-6"
        tc      'K', "12345678901234567", "123456789012345"
        tc      'K', "0.1234567890123456", "0.12345678901234"
        tc      'K', "4I", "0.25"
        tc      'K', "7I", "0.142857142857143"
        tc      'K', "3N", "-3"
        tc      'K', "3NN", "3"
        tc      'K', "0N", "0"
        tc      'K', "1.5N", "-1.5"
        tc      'K', "123B", "12"
        tc      'K', "1.5BB", "1"
        tc      'K', "5NB", "0"
        tc      'K', "1..2.3", "1.23"
        tc      'K', "007", "7"
        tc      'K', "5p3pCr", "8"
        tc      'K', "7mr", "-7"
        tc      'K', "5pkr", "0"
        tc      'K', "1/0=", "Cannot divide by zero"
        tc      'K', "0I", "Cannot divide by zero"
        tc      'K', "1/0=5+1=", "6"
        tc      'K', "1/0=C", "0"
        tc      'K', "1/0=+", "Cannot divide by zero"
        tc      'K', "5NQ", "Invalid input"
        tc      'K', "100000000SSSS", "Overflow"
        tc      'K', "100000000SSS", "1e+64"
        tc      'K', "V255H", "FF"
        tc      'K', "VHff+1=", "100"
        tc      'K', "V5N", "-5"
        tc      'K', "V5NH", "FFFFFFFB"
        tc      'K', "VY1011&110=", "10"
        tc      'K', "VY1011|110=", "1111"
        tc      'K', "VY1011^110=", "1101"
        tc      'K', "V1<4=", "16"
        tc      'K', "V256N>2=", "-64"
        tc      'K', "V1<40=", "0"
        tc      'K', "V7%3=", "1"
        tc      'K', "V7N%3=", "-1"
        tc      'K', "V7/2=", "3"
        tc      'K', "V7N/2=", "-3"
        tc      'K', "V1/0=", "Cannot divide by zero"
        tc      'K', "V2147483647+1=", "-2147483648"
        tc      'K', "V21474836479", "2147483647"
        tc      'K', "VHffffffff1", "FFFFFFFF"
        tc      'K', "V5~", "-6"
        tc      'K', "VH80000000L", "1"
        tc      'K', "VH1R", "80000000"
        tc      'K', "V3.7", "37"
        tc      'K', "12.7V", "12"
        tc      'K', "12.7NV", "-12"
        tc      'K', "V12NW", "-12"
        tc      'K', "V123BB", "1"
        tc      'K', "VH1f3B", "1F"
        tc      'K', "VO17+1=", "20"
        tc      'K', "V6*7=", "42"
        tc      'K', "V65536*65536=", "0"
        tc      'K', "V1000000*3000=", "-1294967296"
        tc      'K', "VH9", "9"
        tc      'K', "VYa12", "1"
        tc      'P', " 1,234.5 ", "1234.5"
        tc      'P', "-2.5e3", "-2500"
        tc      'P', "0.000000000000000000001", "1e-21"
        tc      'P', "abc", "rejected"
        tc      'P', "1e100", "rejected"
        tc      'P', "1.2.3", "rejected"
        tc      'Q', "-42", "-42"
        tc      'Q', "ff", "rejected"
        .byte   0

        .segment "DATA"
wopen:  .word   200, 64, SW, SH
        .faraddr t_title
        .byte   0

        .segment "BSS"
argl:   .res    2
argx:   .res    2
wsown:  .res    2
win:    .res    2
dbank:  .res    2
mode:   .res    2                       ; 0 Standard, 1 Programmer
base:   .res    2                       ; Programmer: the input's base
err:    .res    2                       ; an error shown (E_*)
entering: .res  2                       ; a number is being typed
fresh:  .res    2                       ; X was given since the last operation key
pendop: .res    2                       ; the operation waiting for its second number
lastop: .res    2                       ; the last one done (= again)
ebuf:   .res    32                      ; the number typed
dstr:   .res    48                      ; the display: the number
xstr:   .res    64                      ;   the pending operation
nx:     .res    NSZ
nacc:   .res    NSZ
nmem:   .res    NSZ
nlast:  .res    NSZ
px:     .res    4
pacc:   .res    4
plast:  .res    4
keys:   .res    2                       ; the layout's key table
dw:     .res    2                       ; the display picture's size
dh:     .res    2
bigy:   .res    2
presk:  .res    2                       ; the key drawn pressed under the pointer
presk_was: .res 2                       ; the key the press began on
kblk:   .res    16
winfo:  .res    8
wgeo:   .res    8                       ; (0.15) win_geom: a new view's size
clipblk: .res   6
pbuf:   .res    66
gstr:   .res    48
gx:     .res    2
gy:     .res    2
gc:     .res    2
tcount: .res    2
tfail:  .res    2
tptr:   .res    2
ttype:  .res    2
tkeys:  .res    2
texp:   .res    2
pflag:  .res    2
fkey:   .res    2                       ; a key flashed / released
fcode:  .res    2
kgbuf:  .res    8 * 14                  ; a key digit

        .segment "ZEROPAGE"
t0:     .res    2
t1:     .res    2
t2:     .res    2
t3:     .res    2
t4:     .res    2
t5:     .res    2
t6:     .res    2
t7:     .res    2
p1:     .res    2
p2:     .res    2
cy:     .res    2
dq:     .res    2
bl:     .res    2
kc:     .res    2
jv:     .res    2
bp:     .res    4
gp:     .res    2
gh:     .res    2
gb:     .res    2
sptr:   .res    2
