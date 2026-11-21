/* main.c - Gem Run in C on hgame, the C SDK's game library: a small but complete game to
 * grow from (the same game as sdk/templates/game, the assembly template: the same rules,
 * art and sounds).
 *
 * Collect every gem in the maze; the blob bounces around and costs a life when it touches
 * you. Arrow keys (or W A S D, or joystick 1) move; a click sends the player towards the
 * pointer; Space, a click or the trigger starts; Esc goes back to the title (and from the
 * title quits).
 *
 * What it shows (sdk/docs/c/games.md explains each):
 *   - a game in a window (hg_window): a 16-line status strip over a 320 x 192 playfield;
 *   - the frame loop (hg_frame, 60 a second) with the rules on a fixed step of 50 a second
 *     (hg_steps), so the game runs at the same speed whatever the frame rate;
 *   - a tile map drawn by the CPU into a background image (hg_map_image), shown once;
 *   - blitter sprites (bobs) over that background: the library puts back what was under
 *     them and draws them in the vertical blank, so nothing flickers;
 *   - input: player 1's keys and joystick (hg_p1), the mouse, the window's menu;
 *   - POKEY sound effects with envelopes (hg_sfx);
 *   - states: title, play, game over.
 * The art is text in art/*.txt, made into art/*.h by sdk/tools/img2c.py (make).
 */
#include <stdio.h>
#include <string.h>
#include <hgame.h>
#include "art/tiles.h"
#include "art/player.h"
#include "art/enemy.h"

#define TS      16                      /* tile size */
#define MW      20                      /* the map in tiles */
#define MH      12
#define PW      (MW * TS)               /* playfield 320 x 192 */
#define PH      (MH * TS)
#define HUDH    16                      /* the status strip above it */
#define T_FLOOR 0                       /* tiles (frames of tiles.h) */
#define T_WALL  1
#define T_GEM   2
#define C_HUD   (16 + 36 * 0 + 6 * 0 + 1)       /* status strip: cube 0 0 1 */
#define C_PANEL (16 + 36 * 0 + 6 * 1 + 2)       /* title / game over panel */
#define LIVES   3

enum { TITLE, PLAY, OVER };

/* the level: # wall, . floor, * gem, P the player's start, E the blob's */
static const char map0[MH][MW + 1] = {
    "####################",
    "#P.....*....*.....*#",
    "#.###.####.####.##.#",
    "#.#*...........*.#.#",
    "#.#.###.####.###.#.#",
    "#*....#..E...#....*#",
    "#.###.#.####.#.###.#",
    "#...#..........#...#",
    "###.#.###..###.#.###",
    "#*....*........*...#",
    "#....####*.####...*#",
    "####################",
};

static hg_image *tileimg, *playerimg, *enemyimg, *bg;
static unsigned char map[MH * MW];      /* the level's tiles now */
static int state, quit;
static unsigned tick, score, lives, level, gems, invul;
static int px, py, pfr, tx, ty, tgt;    /* the player, its frame, the mouse target */
static int ex, ey, edx, edy, efr;       /* the blob */
static int startx, starty, estx, esty;

/* ---------------------------------------------------------------- sound */

/* a pure tone at volume 12, falling by 1 a tick, for 11 ticks (20 ms each) */
static void sfx(unsigned voice, unsigned pitch, int step)
{
    hg_sfx(voice, pitch, step, 12, 1, 11, HG_TONE);
}

static void sfx_gem(void)   { sfx(0, 60, -4); }        /* a rising blip */
static void sfx_level(void) { hg_sfx(0, 120, -3, 12, 1, 39, HG_TONE); }
static void sfx_hit(void)   { hg_sfx(1, 40, 3, 12, 1, 11, HG_NOISE); }   /* a noise burst */
static void sfx_over(void)  { hg_sfx(0, 80, 4, 12, 1, 59, HG_TONE); }    /* falling, long */

/* ---------------------------------------------------------------- drawing */

/* "SCORE 00120   LIVES 3   LEVEL 1", white on blue */
static void hud(void)
{
    char line[40];
    sprintf(line, "SCORE %05u   LIVES %u   LEVEL %u", score, lives, level);
    hg_fill(0, 0, PW, HUDH, C_HUD);
    hg_text(8, 3, line, C_WHITE);
}

/* the title / game over panel: a framed box in the middle of the playfield */
static void panel(void)
{
    hg_fill(40, HUDH + 48, PW - 80, 96, C_PANEL);
    hg_rect(40, HUDH + 48, PW - 80, 96, C_YELLOW);
}

static void ptext(int y, const char *s)
{
    hg_text((PW - (int)hg_text_width(s)) / 2, HUDH + 48 + 6 + y, s, C_WHITE);
}

/* map index -> that tile into the background image, and onto the screen */
static void drawtile(unsigned i)
{
    int x = (int)(i % MW) * TS, y = (int)(i / MW) * TS;
    hg_image_draw(bg, tileimg, map[i], x, y);
    hg_draw_part(bg, (unsigned)x, (unsigned)y, TS, TS, x, y + HUDH);
}

/* the level from map0: the working copy, the gems counted, the starts found, every tile
 * drawn into the background image */
static void loadmap(void)
{
    unsigned r, c, i;
    char ch;
    gems = 0;
    for (r = 0; r < MH; r++)
        for (c = 0; c < MW; c++) {
            i = r * MW + c;
            ch = map0[r][c];
            map[i] = ch == '#' ? T_WALL : ch == '*' ? T_GEM : T_FLOOR;
            if (ch == '*')
                ++gems;
            if (ch == 'P') {
                startx = (int)c * TS;
                starty = (int)r * TS;
            }
            if (ch == 'E') {
                estx = (int)c * TS;
                esty = (int)r * TS;
            }
        }
    hg_map_image(bg, map, MW, MH, tileimg);
}

static void showall(void)
{
    hg_draw(bg, 0, 0, HUDH);
}

/* the sprites: the blob below, the player over it (blinking while it cannot be hurt) */
static void sprites(void)
{
    hg_bob(0, enemyimg, (unsigned)efr, ex, ey + HUDH);
    if (invul & 4)
        hg_bob_hide(1);
    else
        hg_bob(1, playerimg, (unsigned)pfr, px, py + HUDH);
}

/* ---------------------------------------------------------------- the rules */

/* (x, y) a sprite's top left: its box, inset by 2, touches a wall or leaves the field */
static int blocked(int x, int y)
{
    static const signed char cx[4] = { 2, TS - 3, 2, TS - 3 };
    static const signed char cy[4] = { 2, 2, TS - 3, TS - 3 };
    unsigned k;
    if ((unsigned)x > PW - TS || (unsigned)y > PH - TS)
        return 1;
    for (k = 0; k < 4; k++)
        if (map[((y + cy[k]) >> 4) * MW + ((x + cx[k]) >> 4)] == T_WALL)
            return 1;
    return 0;
}

/* a position moved 2 pixels (1 at the end) towards the nearest multiple of 16 when it is
 * at most 6 away: helps the player turn into corridors */
static int nudge(int a)
{
    int m = a & (TS - 1);
    if (m == 0 || (m >= 7 && m < 10))
        return a;
    if (m < 7)
        return m < 2 ? a - 1 : a - 2;
    return m < TS - 1 ? a + 2 : a + 1;
}

/* -1, 0 or 1 towards the target (0 within a pixel) */
static int sgn(int target, int pos)
{
    int d = target - pos;
    return d >= 2 ? 1 : d <= -2 ? -1 : 0;
}

/* a new direction for the blob: one of four, at its speed (1 + level / 2, at most 3) */
static void newdir(void)
{
    int sp = (int)level / 2 + 1;
    if (sp > 3)
        sp = 3;
    edx = edy = 0;
    switch (hg_rand() & 3) {
    case 0: edx = sp; break;
    case 1: edx = -sp; break;
    case 2: edy = sp; break;
    default: edy = -sp; break;
    }
}

static void title(void)
{
    state = TITLE;
    hg_sound_off();
    hg_bob_hide(0);
    hg_bob_hide(1);
    loadmap();
    showall();
    panel();
    ptext(8, "G E M   R U N");
    ptext(40, "Collect every gem.");
    ptext(56, "Arrows / WASD / mouse: move");
    ptext(72, "Space or click: start");
    score = 0;
    lives = LIVES;
    level = 1;
    hud();
    printf("GEMRUN: title\n");
}

static void newlevel(void)
{
    loadmap();
    showall();
    state = PLAY;
    tgt = 0;
    px = startx;
    py = starty;
    ex = estx;
    ey = esty;
    newdir();
    pfr = efr = 0;
    invul = 0;
    sprites();
    hud();
    printf("GEMRUN: level %u\n", level);
}

static void newgame(void)
{
    score = 0;
    lives = LIVES;
    level = 1;
    newlevel();
}

static void gameover(void)
{
    state = OVER;
    panel();
    ptext(8, "GAME OVER");
    ptext(40, "Space or click: again");
    sfx_over();
    printf("GEMRUN: game over, score %u\n", score);
}

/* one step of the rules (50 a second) */
static void step(void)
{
    unsigned joy, i;
    int dx = 0, dy = 0, nx, ny;

    ++tick;
    joy = hg_p1();
    if (invul)
        --invul;
    /* the player: 2 pixels a step, each axis on its own (so it slides along walls) */
    if (joy & HG_LEFT)
        --dx;
    if (joy & HG_RIGHT)
        ++dx;
    if (joy & HG_UP)
        --dy;
    if (joy & HG_DOWN)
        ++dy;
    if (joy & (HG_UP | HG_DOWN | HG_LEFT | HG_RIGHT))
        tgt = 0;                                /* a key cancels the mouse target */
    else if (tgt) {
        dx = sgn(tx, px);
        dy = sgn(ty, py);
        if (!dx && !dy)
            tgt = 0;                            /* arrived */
    }
    if (dx) {
        nx = px + 2 * dx;
        if (!blocked(nx, py))
            px = nx;
        else if (!dy && !blocked(px, ny = nudge(py)))
            py = ny;                            /* near a corridor: slide into it */
    }
    if (dy) {
        ny = py + 2 * dy;
        if (!blocked(px, ny))
            py = ny;
        else if (!dx && !blocked(nx = nudge(px), py))
            px = nx;
    }
    if ((dx || dy) && !(tick & 7))
        pfr ^= 1;                               /* walking: the next frame every 8 steps */
    /* a gem under the player's centre */
    i = (unsigned)((py + TS / 2) >> 4) * MW + (unsigned)((px + TS / 2) >> 4);
    if (map[i] == T_GEM) {
        map[i] = T_FLOOR;
        drawtile(i);
        score += 10;
        sfx_gem();
        hud();
        printf("GEMRUN: gem, score %u\n", score);
        if (--gems == 0) {
            ++level;                            /* every gem: the next level */
            sfx_level();
            newlevel();
            return;
        }
    }
    /* the blob: straight on, a new random direction at a wall */
    if (blocked(ex + edx, ey + edy))
        newdir();
    else {
        ex += edx;
        ey += edy;
    }
    if (!(tick & 15))
        efr ^= 1;
    /* touching it */
    if (!invul && HG_ABS(px - ex) < 12 && HG_ABS(py - ey) < 12) {
        sfx_hit();
        --lives;
        hud();
        printf("GEMRUN: touched, %u lives left\n", lives);
        if (!lives) {
            gameover();
            return;
        }
        px = startx;                            /* back to the start, safe for 2 s */
        py = starty;
        tgt = 0;
        invul = 100;
    }
}

/* ---------------------------------------------------------------- input */

static void input(void)
{
    unsigned click = hg_mouse_clicked();
    int m = hg_menu();

    if (m == 0)                                 /* Game: New game (0), -, Quit (2) */
        newgame();
    else if (m == 2)
        quit = 1;
    if (hg_key_pressed(HG_KEY_ESC)) {
        if (state == TITLE)
            quit = 1;
        else {
            hg_stats("GEMRUN");
            title();
        }
        return;
    }
    if (state != PLAY) {
        if ((hg_p1_pressed() & HG_FIRE) || (click & 1))
            newgame();
        return;
    }
    if (click & 1) {                            /* walk towards the pointer */
        tx = hg_mouse_x - TS / 2;
        ty = hg_mouse_y - HUDH - TS / 2;
        tgt = 1;
    }
}

int main(void)
{
    unsigned n;

    if (hg_window(PW, PH + HUDH, "Gem Run") < 0)
        return 1;
    hg_window_menu("Game\0New game\tSpace\0-\0Quit\tEsc\0\0");
    tileimg = hg_image_from(tiles, TILES_W, TILES_H, TILES_N, HG_NONE);
    playerimg = hg_image_from(player, PLAYER_W, PLAYER_H, PLAYER_N, PLAYER_KEY);
    enemyimg = hg_image_from(enemy, ENEMY_W, ENEMY_H, ENEMY_N, ENEMY_KEY);
    bg = hg_image_new(PW, PH, 1);
    if (!tileimg || !playerimg || !enemyimg || !bg)
        return 1;
    hg_bob_background(bg, 0, HUDH);
    hg_frame();
    title();
    while (hg_frame() && !quit) {
        input();
        if (state == PLAY) {
            n = hg_steps(50);                   /* the rules at 50 steps a second */
            while (n-- && state == PLAY)
                step();
            if (state == PLAY)
                sprites();
        }
    }
    hg_stats("GEMRUN");
    return 0;
}
