; sol_art.s - Solitaire's pixel art (included by solitair.s), all original: the corner
; ranks, the suits (small for corners and pips, large for aces and court cards), the court
; cards' headgear, the empty stock's ring. Each piece: u8 width, u8 height, then a byte per
; pixel: 0 clear, $FF the ink given when painting (the suit's colour), else a colour.

.macro  arow    rs
        .repeat .strlen(rs), I
        .if     .strat(rs, I) = '.'
        .byte   0
        .elseif .strat(rs, I) = '#'
        .byte   $FF
        .elseif .strat(rs, I) = 'y'
        .byte   C_YELLOW
        .elseif .strat(rs, I) = 'o'
        .byte   C_ORANGE
        .elseif .strat(rs, I) = 'r'
        .byte   C_RED
        .elseif .strat(rs, I) = 'b'
        .byte   C_SELECT
        .elseif .strat(rs, I) = 'w'
        .byte   C_WHITE
        .elseif .strat(rs, I) = 'k'
        .byte   C_SHADOW
        .elseif .strat(rs, I) = 'g'
        .byte   C_MID
        .else
        .error  "bad art character"
        .endif
        .endrepeat
.endmacro

        .segment "RODATA"
; ranks A 2-10 J Q K: 9 x 9 (10 uses all 9 columns)
a_rank: .addr   r_a, r_2, r_3, r_4, r_5, r_6, r_7, r_8, r_9, r_10, r_j, r_q, r_k
r_a:    .byte   9, 9
        arow    "..###...."
        arow    ".##.##..."
        arow    "##...##.."
        arow    "##...##.."
        arow    "#######.."
        arow    "##...##.."
        arow    "##...##.."
        arow    "##...##.."
        arow    "##...##.."
r_2:    .byte   9, 9
        arow    ".#####..."
        arow    "##...##.."
        arow    ".....##.."
        arow    "....##..."
        arow    "...##...."
        arow    "..##....."
        arow    ".##......"
        arow    "##......."
        arow    "#######.."
r_3:    .byte   9, 9
        arow    "######..."
        arow    ".....##.."
        arow    ".....##.."
        arow    "..####..."
        arow    ".....##.."
        arow    ".....##.."
        arow    ".....##.."
        arow    "##...##.."
        arow    ".#####..."
r_4:    .byte   9, 9
        arow    "....##..."
        arow    "...###..."
        arow    "..####..."
        arow    ".##.##..."
        arow    "##..##..."
        arow    "#######.."
        arow    "....##..."
        arow    "....##..."
        arow    "....##..."
r_5:    .byte   9, 9
        arow    "#######.."
        arow    "##......."
        arow    "##......."
        arow    "######..."
        arow    ".....##.."
        arow    ".....##.."
        arow    ".....##.."
        arow    "##...##.."
        arow    ".#####..."
r_6:    .byte   9, 9
        arow    "..####..."
        arow    ".##......"
        arow    "##......."
        arow    "######..."
        arow    "##...##.."
        arow    "##...##.."
        arow    "##...##.."
        arow    "##...##.."
        arow    ".#####..."
r_7:    .byte   9, 9
        arow    "#######.."
        arow    ".....##.."
        arow    "....##..."
        arow    "....##..."
        arow    "...##...."
        arow    "...##...."
        arow    "..##....."
        arow    "..##....."
        arow    "..##....."
r_8:    .byte   9, 9
        arow    ".#####..."
        arow    "##...##.."
        arow    "##...##.."
        arow    ".#####..."
        arow    "##...##.."
        arow    "##...##.."
        arow    "##...##.."
        arow    "##...##.."
        arow    ".#####..."
r_9:    .byte   9, 9
        arow    ".#####..."
        arow    "##...##.."
        arow    "##...##.."
        arow    "##...##.."
        arow    ".######.."
        arow    ".....##.."
        arow    ".....##.."
        arow    "....##..."
        arow    ".####...."
r_10:   .byte   9, 9
        arow    ".##..###."
        arow    "###.##.##"
        arow    ".##.##.##"
        arow    ".##.##.##"
        arow    ".##.##.##"
        arow    ".##.##.##"
        arow    ".##.##.##"
        arow    ".##.##.##"
        arow    "####.###."
r_j:    .byte   9, 9
        arow    "...####.."
        arow    ".....##.."
        arow    ".....##.."
        arow    ".....##.."
        arow    ".....##.."
        arow    ".....##.."
        arow    "##...##.."
        arow    "##...##.."
        arow    ".#####..."
r_q:    .byte   9, 9
        arow    ".#####..."
        arow    "##...##.."
        arow    "##...##.."
        arow    "##...##.."
        arow    "##...##.."
        arow    "##...##.."
        arow    "##.#.##.."
        arow    "##..##..."
        arow    ".###.##.."
r_k:    .byte   9, 9
        arow    "##...##.."
        arow    "##..##..."
        arow    "##.##...."
        arow    "####....."
        arow    "###......"
        arow    "####....."
        arow    "##.##...."
        arow    "##..##..."
        arow    "##...##.."

; suits: clubs, diamonds, hearts, spades; small 7 x 7, large 13 x 13
a_small: .addr  s_c, s_d, s_h, s_s
s_c:    .byte   7, 7
        arow    "..###.."
        arow    "..###.."
        arow    "##.#.##"
        arow    "#######"
        arow    "##.#.##"
        arow    "...#..."
        arow    "..###.."
s_d:    .byte   7, 7
        arow    "...#..."
        arow    "..###.."
        arow    ".#####."
        arow    "#######"
        arow    ".#####."
        arow    "..###.."
        arow    "...#..."
s_h:    .byte   7, 7
        arow    ".##.##."
        arow    "#######"
        arow    "#######"
        arow    "#######"
        arow    ".#####."
        arow    "..###.."
        arow    "...#..."
s_s:    .byte   7, 7
        arow    "...#..."
        arow    "..###.."
        arow    ".#####."
        arow    "#######"
        arow    "#######"
        arow    "...#..."
        arow    "..###.."
a_big:  .addr   b_c, b_d, b_h, b_s
b_c:    .byte   13, 13
        arow    "....#####...."
        arow    "...#######..."
        arow    "...#######..."
        arow    "...#######..."
        arow    ".##.#####.##."
        arow    "#####.#.#####"
        arow    "#############"
        arow    "#############"
        arow    "#####.#.#####"
        arow    ".###..#..###."
        arow    "......#......"
        arow    ".....###....."
        arow    "...#######..."
b_d:    .byte   13, 13
        arow    "......#......"
        arow    ".....###....."
        arow    "....#####...."
        arow    "...#######..."
        arow    "..#########.."
        arow    ".###########."
        arow    "#############"
        arow    ".###########."
        arow    "..#########.."
        arow    "...#######..."
        arow    "....#####...."
        arow    ".....###....."
        arow    "......#......"
b_h:    .byte   13, 13
        arow    "..###...###.."
        arow    ".#####.#####."
        arow    "#############"
        arow    "#############"
        arow    "#############"
        arow    "#############"
        arow    ".###########."
        arow    "..#########.."
        arow    "...#######..."
        arow    "....#####...."
        arow    ".....###....."
        arow    "......#......"
        arow    "............."
b_s:    .byte   13, 13
        arow    "......#......"
        arow    ".....###....."
        arow    "....#####...."
        arow    "...#######..."
        arow    "..#########.."
        arow    ".###########."
        arow    "#############"
        arow    "#############"
        arow    "#############"
        arow    ".####.#.####."
        arow    "......#......"
        arow    ".....###....."
        arow    "...#######..."

; the court cards' headgear (11 x 9): jack's cap, queen's coronet, king's crown
a_head: .addr   h_j, h_q, h_k
h_j:    .byte   11, 9
        arow    "........kk."
        arow    ".......krrk"
        arow    "....kkkkrk."
        arow    "...k###kk.."
        arow    "..k#####k.."
        arow    ".k#######k."
        arow    "k#########k"
        arow    "kyyyyyyyyyk"
        arow    "kkkkkkkkkkk"
h_q:    .byte   11, 9
        arow    ".....k....."
        arow    "....kyk...."
        arow    ".k..kyk..k."
        arow    "kyk.kyk.kyk"
        arow    "kyykyyykyyk"
        arow    "kyyyyryyyyk"
        arow    "kyyyrwryyyk"
        arow    "kyyyyryyyyk"
        arow    "kkkkkkkkkkk"
h_k:    .byte   11, 9
        arow    "k....k....k"
        arow    "kk..kyk..kk"
        arow    "kyk.kyk.kyk"
        arow    "kyykyyykyyk"
        arow    "kyyyyyyyyyk"
        arow    "kyrybywyryk"
        arow    "kyyyyyyyyyk"
        arow    "koooooooook"
        arow    "kkkkkkkkkkk"

; the empty stock: a ring (turn the waste over)
a_ring: .byte   13, 13
        arow    "....#####...."
        arow    "..##.....##.."
        arow    ".#.........#."
        arow    ".#.........#."
        arow    "#...........#"
        arow    "#...........#"
        arow    "#...........#"
        arow    "#...........#"
        arow    "#...........#"
        arow    ".#.........#."
        arow    ".#.........#."
        arow    "..##.....##.."
        arow    "....#####...."

; pip centres for 1-10 (x, y in the card), ranks 2-10; the ace has the large suit
pips:   .addr   p_2, p_3, p_4, p_5, p_6, p_7, p_8, p_9, p_10
p_2:    .byte   2, 17, 17, 17, 41
p_3:    .byte   3, 17, 17, 17, 29, 17, 41
p_4:    .byte   4, 10, 17, 24, 17, 10, 41, 24, 41
p_5:    .byte   5, 10, 17, 24, 17, 10, 41, 24, 41, 17, 29
p_6:    .byte   6, 10, 17, 24, 17, 10, 29, 24, 29, 10, 41, 24, 41
p_7:    .byte   7, 10, 17, 24, 17, 10, 29, 24, 29, 10, 41, 24, 41, 17, 23
p_8:    .byte   8, 10, 17, 24, 17, 10, 29, 24, 29, 10, 41, 24, 41, 17, 23, 17, 35
p_9:    .byte   9, 10, 17, 24, 17, 10, 25, 24, 25, 10, 33, 24, 33, 10, 41, 24, 41, 17, 29
p_10:   .byte   10, 10, 17, 24, 17, 10, 25, 24, 25, 10, 33, 24, 33, 10, 41, 24, 41, 17, 21
        .byte   17, 37
