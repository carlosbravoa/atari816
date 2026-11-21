/* main.c - Glimmer: a firefly in a dark cave collects the sparks and keeps away from the
 * bats. An example of hgame's full-screen path, in C (sdk/docs/c/games.md):
 *
 *   - full screen 320 x 180 with the game's own palette (hg_screen, hg_palette);
 *   - a tile map of 80 x 24 tiles scrolled by Marga with wrap: only the column or row of
 *     tiles that comes into view is drawn (hg_map, hg_camera), and a fixed panel at the
 *     top (the split);
 *   - hardware sprites for the firefly, the sparks and the bats (hg_sprite_*), behind the
 *     rock (HG_BEHIND: they show over colour 0, the cave's air);
 *   - a raster table: the air darker towards the bottom of the screen (hg_raster);
 *   - samples on Lau made at the start (hg_sound_make), music from the card by Horizon's
 *     music engine (hg_music_play), if the module is there;
 *   - 60 frames a second: one step of the rules a frame (hg_frame).
 *
 * Arrows, W A S D or joystick 1 fly; Esc ends. Alt+Tab / Alt+Esc / F12: the desktop (the
 * game pauses by itself and goes on when its window has the focus again).
 */
#include <stdio.h>
#include <string.h>
#include <hgame.h>
#include "art/tiles.h"
#include "art/fly.h"
#include "art/spark.h"
#include "art/bat.h"

#define MW      80                      /* the map in tiles */
#define MH      24
#define TS      16
#define PANEL   16                      /* rows of the panel at the top */
#define T_AIR   0                       /* tiles: frames of tiles.h */
#define T_ROCK  1
#define T_MOSS  2
#define T_VEIN  3
#define MAXS    16                      /* sparks */
#define MAXB    8                       /* bats */
#define LIGHT   4                       /* hits a firefly can take */

static const char cave[MH][MW + 1] = {
"################################################################################",
"#S.....#######.............######....................####........*.........#####",
"#......######......*........####.........B...........###....................####",
"#..........#.........................................##........#####.........###",
"##...*.....#.........######..................####......................######..#",
"###........%......B..#######.........*......######..........*.........#######..#",
"####......##.........######.........###.....#####.....###.............######...#",
"###.......##.........#####.........#####......#......#####...B..........##.....#",
"##........###.........###.........#######...........#######....................#",
"#.........####...................%#######..........#########.......*.........###",
"#....*....#####......*..........#########.....*.....#######..................###",
"#........#######...............######...............#####.........####.......###",
"##.......########.........##...........B...............#.........######........#",
"###.......######.........####..................###..............########......*#",
"####.......####.........######.......*........#####......*.......######........#",
"####.................B..#######..............#######...............##..........#",
"###.............................................#####..........................#",
"##.....######.........*.............######.......###.........B.........####....#",
"#.....########...................B.#########.....................*....######...#",
"#..*.##########..........####.....###########..........####..........########..#",
"#....###########........######....###########.........######........##########.#",
"##..#############......########...############.......########......#############",
"###%##############....##########.#############%.....##########....##############",
"################################################################################",
};

/* the palette: 0 the air, 1 the panel, 2 text, 3-5 rock, 6-7 moss, 8-10 the firefly,
 * 11-12 sparks, 13-14 bats, 15 dim text, 16 the air's specks */
static const unsigned char pal[17 * 3] = {
    8, 10, 28,     20, 24, 52,    236, 236, 220, 52, 44, 52,    76, 64, 72,
    108, 92, 96,   40, 104, 48,   88, 160, 72,   48, 40, 24,    248, 220, 64,
    255, 255, 200, 64, 220, 240,  220, 255, 255, 120, 56, 132,  240, 48, 48,
    140, 140, 150, 24, 28, 56
};

/* the air darker towards the bottom (lines of 360; entry 0) */
static const hz_raster shade[5] = {
    { 120, 0, 7, 9, 26 }, { 180, 0, 6, 8, 22 }, { 240, 0, 5, 6, 18 },
    { 300, 0, 4, 5, 14 }, { 340, 0, 3, 4, 10 }
};

static unsigned char map[MW * MH];
static hg_image *tileimg, *flyimg, *sparkimg, *batimg;
static hg_sound *ding, *thud;
static int px, py, sx0, sy0, face;      /* the firefly (world pixels), its start */
static int spx[MAXS], spy[MAXS], nspark, got;
static unsigned char spgot[MAXS];
static int bx0[MAXB], by0[MAXB], bx[MAXB], by[MAXB], nbat;
static unsigned light, hurt, t, nsprites, panel_dirty, ended;

static void loadcave(void)
{
    unsigned r, c;
    char ch;
    for (r = 0; r < MH; r++)
        for (c = 0; c < MW; c++) {
            ch = cave[r][c];
            map[r * MW + c] = ch == '#' ? T_ROCK : ch == '%' ? T_VEIN : T_AIR;
            if (ch == '*' && nspark < MAXS) {
                spx[nspark] = (int)c * TS;
                spy[nspark++] = (int)r * TS;
            } else if (ch == 'B' && nbat < MAXB) {
                bx0[nbat] = (int)c * TS;
                by0[nbat++] = (int)r * TS;
            } else if (ch == 'S') {
                sx0 = (int)c * TS;
                sy0 = (int)r * TS;
            }
        }
    for (r = 1; r < MH; r++)            /* moss on rock under air */
        for (c = 0; c < MW; c++)
            if (map[r * MW + c] == T_ROCK && map[(r - 1) * MW + c] == T_AIR)
                map[r * MW + c] = T_MOSS;
}

/* rock under the world pixel? */
static int rock(int x, int y)
{
    if (x < 0 || y < 0 || x >= MW * TS || y >= MH * TS)
        return 1;
    return map[(unsigned)(y >> 4) * MW + (unsigned)(x >> 4)] != T_AIR;
}

/* the firefly's box (inset by 3) at (x, y) touches rock */
static int blocked(int x, int y)
{
    return rock(x + 3, y + 3) || rock(x + 12, y + 3) || rock(x + 3, y + 12) ||
           rock(x + 12, y + 12);
}

static void panel(void)
{
    char line[48];
    unsigned i;
    hg_origin(0, hg_panel_y);           /* the panel's rows (below the ring) */
    hg_fill(0, 0, 320, PANEL, 1);
    sprintf(line, "SPARKS %02d/%02d", got, nspark);
    hg_text(8, 3, line, 2);
    hg_text(176, 3, "LIGHT", 15);
    for (i = 0; i < LIGHT; i++)
        hg_fill(224 + (int)i * 12, 5, 8, 6, i < light ? 9 : 3);
    if (ended)
        hg_text(8, 3, got == nspark ? "ALL SPARKS FOUND!  Esc: the end" :
                "OUT OF LIGHT...   back to the start", 2);
    hg_origin(0, 0);
    panel_dirty = 0;
}

static void restart(void)
{
    px = sx0;
    py = sy0;
    light = LIGHT;
    hurt = 0;
    ended = 0;
    panel_dirty = 1;
}

/* one frame of the rules */
static void step(void)
{
    unsigned j = hg_p1(), i;
    int dx = 0, dy = 0, sp;

    ++t;
    if (ended) {
        if (ended > 1 && --ended == 1) {        /* out of light: start again */
            restart();
        }
        return;
    }
    if (j & HG_LEFT)
        dx = -2;
    if (j & HG_RIGHT)
        dx = 2;
    if (j & HG_UP)
        dy = -2;
    if (j & HG_DOWN)
        dy = 2;
    if (dx)
        face = dx < 0;
    if (dx && !blocked(px + dx, py))
        px += dx;
    if (dy && !blocked(px, py + dy))
        py += dy;
    if (hurt)
        --hurt;
    /* sparks */
    for (i = 0; i < (unsigned)nspark; i++)
        if (!spgot[i] && HG_ABS(spx[i] - px) < 11 && HG_ABS(spy[i] - py) < 11) {
            spgot[i] = 1;
            ++got;
            panel_dirty = 1;
            hg_play_ex(ding, 200, (spx[i] - hg_cam_x - 160) / 2, (int)got);
            printf("GLIMMER: spark %d\n", got);
            if (got == (unsigned)nspark) {
                ended = 1;
                printf("GLIMMER: all sparks\n");
            }
        }
    /* bats: to and fro around their place, bobbing */
    for (i = 0; i < (unsigned)nbat; i++) {
        sp = (int)(t + i * 37);
        bx[i] = bx0[i] + (hg_sin((unsigned)sp) * 40 >> 8);
        by[i] = by0[i] + (hg_sin((unsigned)sp * 3) * 6 >> 8);
        if (!hurt && HG_ABS(bx[i] - px) < 11 && HG_ABS(by[i] - py) < 10) {
            hurt = 90;
            hg_play(thud, 255);
            panel_dirty = 1;
            printf("GLIMMER: bat, light %u\n", (unsigned)(light - 1));
            if (--light == 0) {
                ended = 120;                    /* 2 s, then the start again */
                printf("GLIMMER: out of light\n");
            }
        }
    }
}

/* a world object on the screen? -> its screen position in *x, *y */
static int onscreen(int wx, int wy, int *x, int *y)
{
    *x = hg_screen_x(wx);
    *y = hg_screen_y(wy);
    return *x > -16 && *x < 320 && *y > hg_play_y - 16 && *y < 180;
}

/* the sprites: 0 the firefly, then the sparks and bats that are on the screen */
static void sprites(void)
{
    unsigned n = 1, i, fr = (t >> 3) & 1;
    int x, y;
    hg_sprite_set(0, flyimg, fr, HG_BEHIND | (face ? HG_HFLIP : 0) |
                  ((hurt & 4) ? HG_HIDE : 0));
    hg_sprite_pos(0, hg_screen_x(px), hg_screen_y(py));
    for (i = 0; i < (unsigned)nspark && n < nsprites; i++)
        if (!spgot[i] && onscreen(spx[i], spy[i], &x, &y)) {
            hg_sprite_set(n, sparkimg, ((t >> 4) + i) & 1, HG_BEHIND);
            hg_sprite_pos(n++, x, y);
        }
    for (i = 0; i < (unsigned)nbat && n < nsprites; i++)
        if (onscreen(bx[i], by[i], &x, &y)) {
            hg_sprite_set(n, batimg, (t >> 2) & 1, HG_BEHIND);
            hg_sprite_pos(n++, x, y);
        }
    while (n < nsprites)
        hg_sprite_show(n++, 0);
}

int main(void)
{
    int s;
    if (hg_screen(HG_320X180, "Glimmer") < 0)
        return 1;
    hg_palette_black();                         /* while the first screen is drawn */
    tileimg = hg_image_from(tiles, TILES_W, TILES_H, TILES_N, HG_NONE);
    flyimg = hg_image_from(fly, FLY_W, FLY_H, FLY_N, 0);
    sparkimg = hg_image_from(spark, SPARK_W, SPARK_H, SPARK_N, 0);
    batimg = hg_image_from(bat, BAT_W, BAT_H, BAT_N, 0);
    if (!tileimg || !flyimg || !sparkimg || !batimg)
        return 1;
    loadcave();
    if (hg_map(map, MW, MH, tileimg, PANEL) < 0)
        return 1;
    s = hg_sprites(16);
    if (s < 0)
        s = hg_sprites(8);                      /* other programs hold some */
    if (s < 0)
        return 1;
    nsprites = (unsigned)s;
    ding = hg_sound_make(HG_SINE, 1320, 180, 70);
    thud = hg_sound_make(HG_NOISE_WAVE, 900, 250, 90);
    if (hg_has_lau())
        printf("GLIMMER: sound on Lau\n");
    if (hg_music_play("/Music/HORIZON.MOD", 1) == 0)   /* (returns once it plays) */
        printf("GLIMMER: music\n");
    hg_music_volume(32);
    restart();
    hg_camera(px - 152, py - 74);
    panel();
    hg_flush(1);
    hg_palette(0, 17, pal);
    hg_raster(5, shade);
    printf("GLIMMER: flying\n");
    while (hg_frame()) {
        if (hg_key_pressed(HG_KEY_ESC))
            break;
        step();
        hg_camera(px - 152, py - 74);
        if (panel_dirty)
            panel();
        sprites();
    }
    hg_stats("GLIMMER");
    return 0;
}
