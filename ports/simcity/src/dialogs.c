/* dialogs.c - the menus and windows, drawn on the window page (framebuffer rows 384-695,
 * shown from screen line 48 instead of the map, over a copy of it): the menu bar's menus,
 * the budget, the evaluation, the graphs, the overview map with its overlays, loading and
 * saving cities, a new city from the terrain generator, the scenarios, the query tool's
 * report, messages. Upstream's windows were Tcl/Tk (res/*.tcl); these follow them.
 * Copyright (C) 2026 the Atari816 project. GPL-3 with EA's additional terms. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <dirent.h>
#include <horizon.h>
#include "sim.h"
#include "hooks.h"
#include "ui.h"

int dlg;
static int dlg_arg;
char query_text[6][48];
char eval_strs[18][40];
unsigned char eval_valid;
void view_copy_to_page(void);

/* ---------------------------------------------------------------- drawing */

struct btn { short x, y, w, h, id; };
static struct btn btns[64];
static int nbtn;
static int wx, wy, ww, wh;              /* the window */

static void begin(void)
{
    nbtn = 0;
    hg_origin(0, PAGE_FB);
}

static void end(void)
{
    hg_origin(0, 0);
}

static void frame(int x, int y, int w, int h, const char *title)
{
    wx = x; wy = y; ww = w; wh = h;
    hg_fill(x + w, y + 3, 3, h, C_BLACK);       /* a shadow (right, below: a redraw */
    hg_fill(x + 3, y + h, w, 3, C_BLACK);       /* never shows a black window) */
    hg_fill(x, y, w, h, C_WIN);
    hg_rect(x, y, w, h, C_TEXT);
    if (title) {
        hg_fill(x + 1, y + 1, w - 2, 12, C_TITLE);
        hg_text(x + (w - (int)strlen(title) * 8) / 2, y + 2, title, C_WHITE);
    }
}

static void button(int x, int y, int w, int h, const char *label, int id, int on)
{
    hg_fill(x, y, w, h, on ? C_SEL : C_PANEL);
    hg_hline(x, y, w, on ? C_SHADOW : C_LIGHT);
    hg_vline(x, y, h, on ? C_SHADOW : C_LIGHT);
    hg_hline(x, y + h - 1, w, on ? C_LIGHT : C_SHADOW);
    hg_vline(x + w - 1, y, h, on ? C_LIGHT : C_SHADOW);
    hg_text(x + (w - (int)strlen(label) * 8) / 2, y + (h - 10) / 2 + 1, label,
            on ? C_SELTEXT : C_TEXT);
    if (nbtn < 64) {
        btns[nbtn].x = (short)x; btns[nbtn].y = (short)y;
        btns[nbtn].w = (short)w; btns[nbtn].h = (short)h;
        btns[nbtn].id = (short)id;
        ++nbtn;
    }
}

static void text(int x, int y, const char *s, int ink)
{
    hg_text(x, y, s, ink);
}

static int hit(int x, int y)
{
    int i;
    for (i = nbtn - 1; i >= 0; i--)
        if (x >= btns[i].x && x < btns[i].x + btns[i].w && y >= btns[i].y &&
            y < btns[i].y + btns[i].h)
            return btns[i].id;
    return -1;
}

/* ---------------------------------------------------------------- menus */

static const char *const menu_items[5][9] = {
    { "New city...    Ctrl+N", "Load city...   Ctrl+O", "Save city      Ctrl+S",
      "Save city as...", "Scenarios...", "Quit", NULL },
    { "Pause / go      Space", "Slow               F2", "Medium             F3",
      "Fast               F4", NULL },
    { "Fire", "Flood", "Tornado", "Earthquake", "Monster", "Nuclear meltdown",
      "Air crash", NULL },
    { "Budget              B", "Evaluation          V", "Graphs              G",
      "Overview map        M", "Zoom in/out         Z", NULL },
    { "Auto budget", "Auto bulldoze", "Disasters", "Sound", "Auto go-to",
      "Animation", NULL },
};
static const int menu_x[] = { 4, 52, 108, 196, 268 };
extern short autoGo;

static int opt_value(int i)
{
    switch (i) {
    case 0: return autoBudget;
    case 1: return autoBulldoze;
    case 2: return !NoDisasters;
    case 3: return sound_on;
    case 4: return autoGo;
    case 5: return DoAnimation;
    }
    return 0;
}

static void draw_menu(int m)
{
    int i, n = 0, w = 0, x, y;
    char buf[40];
    for (i = 0; menu_items[m][i]; i++) {
        int l = (int)strlen(menu_items[m][i]) + (m == 4 ? 4 : 0);
        if (l > w) w = l;
        ++n;
    }
    w = w * 8 + 16;
    x = menu_x[m];
    frame(x, 0, w, n * 14 + 4, NULL);
    for (i = 0; i < n; i++) {
        y = 2 + i * 14;
        if (m == 4)
            sprintf(buf, "[%c] %s", opt_value(i) ? 'x' : ' ', menu_items[m][i]);
        else
            strcpy(buf, menu_items[m][i]);
        if (nbtn < 64) {
            btns[nbtn].x = (short)(x + 1); btns[nbtn].y = (short)y;
            btns[nbtn].w = (short)(w - 2); btns[nbtn].h = 14; btns[nbtn].id = (short)(m * 16 + i);
            ++nbtn;
        }
        hg_text(x + 8, y + 2, buf, C_TEXT);
    }
}

void menu_open(int m)
{
    dlg_open(DLG_MENU, m);
}

static void menu_pick(int id)
{
    int m = id >> 4, i = id & 15;
    dlg_close();
    switch (m) {
    case 0:
        if (i == 0) dlg_open(DLG_NEW, 0);
        else if (i == 1) dlg_open(DLG_LOAD, 0);
        else if (i == 2) dlg_open(DLG_SAVE, 1);
        else if (i == 3) dlg_open(DLG_SAVE, 0);
        else if (i == 4) dlg_open(DLG_SCEN, 0);
        else dlg_open(DLG_QUIT, 0);
        break;
    case 1:
        game_speed(i);
        break;
    case 2:
        game_disaster(i);
        break;
    case 3:
        if (i == 0) dlg_open(DLG_BUDGET, 0);
        else if (i == 1) dlg_open(DLG_EVAL, 0);
        else if (i == 2) dlg_open(DLG_GRAPH, 0);
        else if (i == 3) dlg_open(DLG_MAP, 0);
        else view_zoom(!zoom8), panel_dirty = 1;
        break;
    case 4:
        if (i == 0) autoBudget = !autoBudget;
        else if (i == 1) autoBulldoze = !autoBulldoze;
        else if (i == 2) NoDisasters = !NoDisasters;
        else if (i == 3) sound_on = !sound_on;
        else if (i == 4) autoGo = !autoGo;
        else DoAnimation = !DoAnimation;
        MustUpdateOptions = 1;
        break;
    }
}

/* ---------------------------------------------------------------- the budget */

extern QUAD roadMaxValue, policeMaxValue, fireMaxValue;
extern QUAD RoadFund, PoliceFund, FireFund, TaxFund, RoadSpend, PoliceSpend, FireSpend;
static unsigned char budget_wait;       /* opened by the year's end (the game paused) */

static void money(char *out, QUAD v)
{
    char num[16];
    if (v < 0) {
        sprintf(num, "%ld", (long)-v);
        makeDollarDecimalStr(num, out + 1);
        out[0] = '-';
    } else {
        sprintf(num, "%ld", (long)v);
        makeDollarDecimalStr(num, out);
    }
}

static void set_percent(int k, int p)
{
    if (p < 0) p = 0;
    if (p > 100) p = 100;
    /* as upstream's sim commands (w_sim.c SimCmdRoadFund and its sisters) */
    if (k == 0) {
        roadPercent = p / 100.0;
        RoadSpend = (roadMaxValue * p) / 100;
    } else if (k == 1) {
        policePercent = p / 100.0;
        PoliceSpend = (policeMaxValue * p) / 100;
    } else {
        firePercent = p / 100.0;
        FireSpend = (fireMaxValue * p) / 100;
    }
    UpdateFundEffects();
}

static void draw_budget(void)
{
    static const char *const names[] = { "Transportation", "Police", "Fire" };
    char b1[24], b2[24], line[64];
    int k, y;
    QUAD want, got, total = 0;
    frame(120, 40, 400, 210, "Budget");
    sprintf(line, "Tax rate: %d%%", CityTax);
    text(136, 62, line, C_TEXT);
    button(296, 58, 24, 16, "-", 1, 0);
    button(324, 58, 24, 16, "+", 2, 0);
    money(b1, TaxFund);
    sprintf(line, "Taxes collected: %s", b1);
    text(136, 82, line, C_TEXT);
    text(136, 102, "Funding        requested      paid", C_SHADOW);
    for (k = 0; k < 3; k++) {
        float pc = k == 0 ? roadPercent : k == 1 ? policePercent : firePercent;
        int p = (int)(pc * 100.0 + 0.5);
        want = k == 0 ? roadMaxValue : k == 1 ? policeMaxValue : fireMaxValue;
        got = (QUAD)(want * pc);
        total += got;
        y = 118 + k * 22;
        money(b1, want);
        money(b2, got);
        sprintf(line, "%-14s %-9s %3d%% %s", names[k], b1, p, b2);
        text(136, y + 3, line, C_TEXT);
        button(448, y, 24, 16, "-", 10 + k, 0);
        button(476, y, 24, 16, "+", 20 + k, 0);
    }
    money(b1, TaxFund - total);
    sprintf(line, "Cash flow: %s", b1);
    text(136, 188, line, C_TEXT);
    money(b2, TotalFunds);
    sprintf(line, "Funds: %s", b2);
    text(136, 204, line, C_TEXT);
    button(136, 224, 120, 18, autoBudget ? "[x] Auto" : "[ ] Auto", 30, 0);
    button(384, 224, 120, 18, "Continue", 31, 1);
}

static void budget_click(int id)
{
    int k;
    if (id == 1 && CityTax > 0) --CityTax;
    else if (id == 2 && CityTax < 20) ++CityTax;
    else if (id >= 10 && id < 13) {
        k = id - 10;
        set_percent(k, (int)((k == 0 ? roadPercent : k == 1 ? policePercent : firePercent) * 100.0 + 0.5) - 10);
    } else if (id >= 20 && id < 23) {
        k = id - 20;
        set_percent(k, (int)((k == 0 ? roadPercent : k == 1 ? policePercent : firePercent) * 100.0 + 0.5) + 10);
    } else if (id == 30) {
        autoBudget = !autoBudget;
        MustUpdateOptions = 1;
    } else if (id == 31) {
        dlg_close();
        return;
    }
    panel_dirty = 1;
    begin();
    draw_budget();
    end();
}

/* ---------------------------------------------------------------- the evaluation */

static void draw_eval(void)
{
    char line[64];
    int i;
    if (!eval_valid)
        doScoreCard();
    frame(100, 20, 440, 260, eval_strs[17]);
    text(116, 40, "Is the mayor doing a good job?", C_TEXT);
    sprintf(line, "Yes: %s   No: %s", eval_strs[15], eval_strs[16]);
    text(132, 54, line, C_TEXT);
    text(116, 74, "What are the worst problems?", C_TEXT);
    for (i = 0; i < 4; i++) {
        if (eval_strs[2 + i][0] == ' ' && eval_strs[2 + i][1] == 0)
            continue;
        sprintf(line, "%-16s %s", eval_strs[2 + i], eval_strs[6 + i]);
        text(132, 88 + i * 12, line, C_TEXT);
    }
    sprintf(line, "Population:       %s", eval_strs[10]);
    text(116, 146, line, C_TEXT);
    sprintf(line, "Net migration:    %s", eval_strs[11]);
    text(116, 158, line, C_TEXT);
    sprintf(line, "Assessed value:   %s", eval_strs[12]);
    text(116, 170, line, C_TEXT);
    sprintf(line, "Category:         %s", eval_strs[13]);
    text(116, 182, line, C_TEXT);
    sprintf(line, "Game level:       %s", eval_strs[14]);
    text(116, 194, line, C_TEXT);
    sprintf(line, "Overall city score (0 - 1000): %s", eval_strs[1]);
    text(116, 214, line, C_TEXT);
    sprintf(line, "Annual change: %s", eval_strs[0]);
    text(116, 226, line, C_TEXT);
    button(420, 252, 100, 18, "OK", 1, 1);
}

/* ---------------------------------------------------------------- the graphs */

extern unsigned char *History10[], *History120[];
static hg_image *gimg;
static unsigned char graph_mask = 63, graph_120;
static const char *const gnames[] = { "Residential", "Commercial", "Industrial",
                                      "Cash flow", "Crime", "Pollution" };

static void plot_graph(void)
{
    unsigned char __far *p;
    unsigned char *row = scratch;
    int k, x, y, prev, v;
    if (!gimg)
        gimg = hg_image_new(240, 130, 1);
    if (!gimg)
        return;
    hg_flush(1);                        /* (the image is not in a list being drawn) */
    p = hg_image_pixels(gimg, 0);
    memset(row, C_WHITE, 240);
    for (y = 0; y < 130; y++)
        hz_far_copy(p + (unsigned)y * 240, row, 240);
    for (x = 0; x < 240; x += 20)       /* a grid: the years */
        for (y = 0; y < 130; y += 2)
            p[(unsigned)y * 240 + x] = C_PANEL;
    for (k = 0; k < 6; k++) {
        unsigned char *h = graph_120 ? History120[k] : History10[k];
        if (!(graph_mask & (1 << k)) || !h)
            continue;
        prev = -1;
        for (x = 0; x < 120; x++) {
            v = 128 - (h[x] >> 1);
            if (prev < 0) prev = v;
            for (y = (prev < v ? prev : v); y <= (prev < v ? v : prev); y++) {
                p[(unsigned)y * 240 + 2 * x] = (unsigned char)(C_GRAPH + k);
                p[(unsigned)y * 240 + 2 * x + 1] = (unsigned char)(C_GRAPH + k);
            }
            prev = v;
        }
    }
}

static void draw_graph(void)
{
    int k;
    frame(140, 30, 360, 230, graph_120 ? "Graphs: 120 years" : "Graphs: 10 years");
    plot_graph();
    if (gimg)
        hg_draw(gimg, 0, 150, 50);
    for (k = 0; k < 6; k++) {
        button(400, 50 + k * 20, 92, 16, gnames[k], 10 + k, (graph_mask >> k) & 1);
        hg_fill(392, 54 + k * 20, 6, 8, C_GRAPH + k);
    }
    button(150, 190, 112, 18, "10 years", 1, !graph_120);
    button(270, 190, 112, 18, "120 years", 2, graph_120);
    button(400, 234, 92, 18, "OK", 3, 1);
}

/* ---------------------------------------------------------------- the overview map */

static hg_image *mimg[2];
#define MAPX 8
#define MAPY 6
static int map_mode;
static const char *const mapmodes[] = {
    "City", "Residential", "Commercial", "Industrial", "Power", "Transport",
    "Population", "Growth", "Traffic", "Pollution", "Crime", "Land value", "Fire",
    "Police"
};

static unsigned char ramp(int v, int max)
{
    if (v <= 0) return 0;
    v = v * 15 / max;
    if (v > 15) v = 15;
    return (unsigned char)(C_RAMP + v);
}

/* the colour of an overlay at tile (x, y), 0 for the city's own */
static unsigned char overlay(int x, int y, unsigned tile)
{
    unsigned t = tile & LOMASK;
    switch (map_mode) {
    case 1: return (t >= RESBASE && t < COMBASE) ? 0 : (t >= ROADBASE ? C_SHADOW : 1);
    case 2: return (t >= COMBASE && t < INDBASE) ? 0 : (t >= ROADBASE ? C_SHADOW : 1);
    case 3: return ((t >= INDBASE && t < PORTBASE) || (t >= TELEBASE && t <= TELELAST)) ? 0 :
                   (t >= ROADBASE ? C_SHADOW : 1);
    case 4:
        if (t >= POWERBASE && t <= LASTPOWER) return C_YELLOW;
        if (tile & CONDBIT) return (tile & PWRBIT) ? C_GREEN : C_RED;
        return 1;
    case 5: return (t >= ROADBASE && t <= LASTRAIL) ? (t >= RAILBASE && t < RESBASE ? C_TEXT : C_SHADOW) : 1;
    case 6: return ramp(PopDensity[x >> 1][y >> 1], 255);
    case 7: { int v = RateOGMem[x >> 3][y >> 3];
              return v > 0 ? ramp(v, 100) : v < 0 ? C_RED : 1; }
    case 8: return ramp(TrfDensity[x >> 1][y >> 1], 255);
    case 9: return ramp(PollutionMem[x >> 1][y >> 1], 255);
    case 10: return ramp(CrimeMem[x >> 1][y >> 1], 255);
    case 11: return ramp(LandValueMem[x >> 1][y >> 1], 250);
    case 12: return ramp(FireRate[x >> 3][y >> 3], 1000);
    case 13: return ramp(PoliceMapEffect[x >> 3][y >> 3], 1000);
    }
    return 0;
}

static void plot_map(void)
{
    unsigned char (*rows)[360] = (unsigned char (*)[360])scratch;
    unsigned char __far *p;
    int x, y, k, i;
    for (k = 0; k < 2; k++)
        if (!mimg[k])
            mimg[k] = hg_image_new(360, 150, 1);
    if (!mimg[0] || !mimg[1])
        return;
    hg_flush(1);
    for (y = 0; y < WORLD_Y; y++) {
        for (x = 0; x < WORLD_X; x++) {
            unsigned tile = (unsigned short)Map[x][y], t = tile & LOMASK;
            unsigned char o = map_mode ? overlay(x, y, tile) : 0;
            const unsigned char __far *m;
            if (t >= TILE_COUNT) t -= TILE_COUNT;
            m = mini_tiles + t * 9;
            for (k = 0; k < 3; k++)
                for (i = 0; i < 3; i++) {
                    unsigned char c = m[k * 3 + i];
                    if (o == 1)         /* dimmed: what the overlay does not show */
                        c = (unsigned char)(((x + y + k + i) & 1) ? C_DIM : c);
                    else if (o)
                        c = (k + i) == 2 && map_mode >= 6 ? c : o;
                    rows[k][x * 3 + i] = c;
                }
        }
        p = hg_image_pixels(mimg[y >= 50], 0);
        for (k = 0; k < 3; k++)
            hz_far_copy(p + (unsigned)((y % 50) * 3 + k) * 360, rows[k], 360);
    }
}

static void draw_map(void)
{
    int k;
    frame(0, 0, 640, 312, NULL);
    hg_text(390, 4, "Overview map", C_TITLE);
    plot_map();
    if (mimg[0] && mimg[1]) {
        hg_draw(mimg[0], 0, MAPX, MAPY);
        hg_draw(mimg[1], 0, MAPX, MAPY + 150);
    }
    /* the view's place */
    {
        int t = (int)tile_px, x0 = cam_x / t, y0 = cam_y / t;
        hg_rect(MAPX + x0 * 3, MAPY + y0 * 3, (VIEW_W / t) * 3, (VIEW_H / t) * 3, C_WHITE);
    }
    for (k = 0; k < 14; k++)
        button(386 + (k & 1) * 120, 22 + (k >> 1) * 20, 114, 17, mapmodes[k], 10 + k, map_mode == k);
    text(388, 166, "A click on the map", C_SHADOW);
    text(388, 178, "goes there.", C_SHADOW);
    button(506, 284, 114, 18, "Close", 1, 1);
}

/* ---------------------------------------------------------------- files */

#define NFILES 40
static char files[NFILES][20];
static int nfiles;
static char save_name[16];

static void scan_dir(const char *dir, const char *prefix)
{
    DIR *d = opendir(dir);
    struct dirent *e;
    if (!d)
        return;
    while ((e = readdir(d)) != NULL && nfiles < NFILES) {
        int l = (int)strlen(e->d_name);
        if (l > 4 && l < 13 && (strcmp(e->d_name + l - 4, ".CTY") == 0 ||
                                strcmp(e->d_name + l - 4, ".cty") == 0)) {
            sprintf(files[nfiles++], "%s%s", prefix, e->d_name);
        }
    }
    closedir(d);
}

static void draw_load(void)
{
    int i;
    frame(40, 10, 560, 290, "Load a city");
    if (nfiles == 0) {
        nfiles = 0;
        scan_dir(".", "");
        scan_dir("CITIES", "CITIES/");
    }
    for (i = 0; i < nfiles; i++) {
        const char *s = strchr(files[i], '/');
        char name[16];
        strncpy(name, s ? s + 1 : files[i], 15);
        name[15] = 0;
        if (strchr(name, '.')) *strchr(name, '.') = 0;
        button(52 + (i % 4) * 136, 30 + (i / 4) * 20, 130, 17, name, 100 + i, s == NULL);
    }
    text(52, 276, "Your cities: blue; upstream's: grey", C_SHADOW);
    button(476, 274, 112, 18, "Cancel", 1, 0);
}

static void draw_save(void)
{
    char line[48];
    frame(160, 100, 320, 100, "Save the city as");
    text(176, 124, "Name (letters, digits):", C_TEXT);
    hg_fill(176, 140, 160, 14, C_WHITE);
    hg_rect(176, 140, 160, 14, C_SHADOW);
    sprintf(line, "%s_", save_name);
    text(180, 142, line, C_TEXT);
    text(340, 142, ".CTY", C_SHADOW);
    button(176, 172, 120, 18, "Save", 1, 1);
    button(344, 172, 120, 18, "Cancel", 2, 0);
}

/* ---------------------------------------------------------------- a new city */

static int new_level;

static void draw_new(void)
{
    char line[48];
    frame(0, 0, 640, 312, NULL);
    hg_text(390, 4, "A new city", C_TITLE);
    if (!mimg[0] || dlg_arg == 0) {
        map_mode = 0;
        dlg_arg = 1;
    }
    plot_map();
    if (mimg[0] && mimg[1]) {
        hg_draw(mimg[0], 0, MAPX, MAPY);
        hg_draw(mimg[1], 0, MAPX, MAPY + 150);
    }
    sprintf(line, "Terrain %u", last_seed);
    text(390, 22, line, C_TEXT);
    button(390, 40, 228, 20, "Generate another", 1, 0);
    text(390, 76, "Difficulty:", C_TEXT);
    button(390, 92, 72, 18, "Easy", 10, new_level == 0);
    button(468, 92, 72, 18, "Medium", 11, new_level == 1);
    button(546, 92, 72, 18, "Hard", 12, new_level == 2);
    text(390, 120, "Funds: $20,000 / $10,000 /", C_SHADOW);
    text(390, 132, "$5,000", C_SHADOW);
    button(390, 160, 228, 20, "Load a city...", 3, 0);
    button(390, 186, 228, 20, "Play a scenario...", 4, 0);
    button(390, 270, 228, 24, "Play this map", 2, 1);
}

static const char *const scen_names[] = {
    "Dullsville 1900", "San Francisco 1906", "Hamburg 1944", "Bern 1965",
    "Tokyo 1957", "Detroit 1972", "Boston 2010", "Rio de Janeiro 2047"
};
static const char *const scen_text[] = {
    "Boredom: make the town grow.", "The earthquake: rebuild.",
    "Fire bombs: rebuild the city.", "Traffic: fix the roads.",
    "The monster attacks.", "Crime and decay.", "A nuclear meltdown.",
    "Floods from the rising sea."
};

static void draw_scen(void)
{
    int i;
    frame(80, 20, 480, 270, "Scenarios");
    for (i = 0; i < 8; i++) {
        button(96, 40 + i * 28, 180, 22, scen_names[i], 10 + i, 0);
        text(284, 46 + i * 28, scen_text[i], C_TEXT);
    }
    button(432, 264, 112, 18, "Cancel", 1, 0);
}

/* ---------------------------------------------------------------- small windows */

static char msg_text[4][64];

static void draw_query(void)
{
    static const char *const lab[] = { "Density:", "Value:", "Crime:", "Pollution:",
                                       "Growth:" };
    char line[64];
    int i;
    frame(180, 80, 280, 130, "Zone status");
    text(196, 100, query_text[0], C_TEXT);
    for (i = 0; i < 5; i++) {
        sprintf(line, "%-11s %s", lab[i], query_text[1 + i]);
        text(196, 120 + i * 12, line, C_TEXT);
    }
    button(340, 186, 100, 18, "OK", 1, 1);
}

static void draw_msg(void)
{
    int i;
    frame(100, 90, 440, 120, dlg_arg == 1 ? "Quit" : "Micropolis");
    for (i = 0; i < 4; i++)
        text(116, 112 + i * 12, msg_text[i], C_TEXT);
    if (dlg_arg == 1) {
        button(116, 182, 120, 18, "Save and quit", 2, 0);
        button(244, 182, 120, 18, "Quit", 3, 0);
        button(404, 182, 120, 18, "Cancel", 1, 1);
    } else
        button(420, 182, 100, 18, "OK", 1, 1);
}

void dlg_message(const char *a, const char *b, const char *c, const char *d)
{
    strncpy(msg_text[0], a ? a : "", 52); msg_text[0][52] = 0;
    strncpy(msg_text[1], b ? b : "", 52); msg_text[1][52] = 0;
    strncpy(msg_text[2], c ? c : "", 52); msg_text[2][52] = 0;
    strncpy(msg_text[3], d ? d : "", 52); msg_text[3][52] = 0;
    dlg_open(DLG_MSG, 0);
}

/* ---------------------------------------------------------------- open, close, input */

static unsigned long opened_ms;

static void redraw(void)
{
    begin();
    switch (dlg) {
    case DLG_MENU: draw_menu(dlg_arg); break;
    case DLG_BUDGET: draw_budget(); break;
    case DLG_EVAL: draw_eval(); break;
    case DLG_GRAPH: draw_graph(); break;
    case DLG_MAP: draw_map(); break;
    case DLG_LOAD: draw_load(); break;
    case DLG_SAVE: draw_save(); break;
    case DLG_NEW: draw_new(); break;
    case DLG_SCEN: draw_scen(); break;
    case DLG_QUERY: draw_query(); break;
    case DLG_MSG: case DLG_QUIT: draw_msg(); break;
    }
    end();
}

void dlg_open(int which, int arg)
{
    if (dlg != DLG_NONE)
        dlg_close();
    view_copy_to_page();
    dlg = which;
    dlg_arg = arg;
    if (which == DLG_LOAD)
        nfiles = 0;
    if (which == DLG_SAVE) {
        if (arg == 1 && CityFileName) {         /* Save: the file it came from */
            if (game_save(CityFileName)) {
                dlg = DLG_NONE;
                return;
            }
        }
        strncpy(save_name, city_name, 8);
        save_name[8] = 0;
    }
    if (which == DLG_BUDGET && arg == 1)
        budget_wait = 1;
    if (which == DLG_QUIT) {
        dlg = DLG_MSG;
        dlg_arg = 1;
        strcpy(msg_text[0], "Quit Micropolis?");
        msg_text[1][0] = msg_text[2][0] = msg_text[3][0] = 0;
    }
    view_page(1);
    opened_ms = (unsigned long)hz_uptime();
    redraw();
    printf("micropolis: window %d\n", dlg);
}

void dlg_close(void)
{
    if (dlg == DLG_BUDGET && budget_wait) {
        budget_wait = 0;
        Resume();
    }
    if (dlg == DLG_NEW)
        game_speed(3);
    dlg = DLG_NONE;
    view_page(0);
    panel_dirty = 1;
}

void dlg_click(int x, int y, int button_)
{
    int id = hit(x, y);
    (void)button_;
    switch (dlg) {
    case DLG_MENU:
        if (id < 0) {
            dlg_close();
            return;
        }
        menu_pick(id);
        return;
    case DLG_BUDGET:
        if (id >= 0) budget_click(id);
        return;
    case DLG_EVAL: case DLG_QUERY:
        if (id == 1 || id < 0) dlg_close();
        return;
    case DLG_GRAPH:
        if (id == 3 || (id < 0 && (x < wx || x >= wx + ww || y < wy || y >= wy + wh))) {
            dlg_close();
            return;
        }
        if (id == 1) graph_120 = 0;
        else if (id == 2) graph_120 = 1;
        else if (id >= 10) graph_mask ^= (unsigned char)(1 << (id - 10));
        else return;
        redraw();
        return;
    case DLG_MAP:
        if (x >= MAPX && x < MAPX + 360 && y >= MAPY && y < MAPY + 300) {
            dlg_close();
            view_center((x - MAPX) / 3, (y - MAPY) / 3);
            return;
        }
        if (id == 1) dlg_close();
        else if (id >= 10) {
            map_mode = id - 10;
            redraw();
        }
        return;
    case DLG_LOAD:
        if (id >= 100) {
            char path[32];
            strcpy(path, files[id - 100]);
            dlg_close();
            game_load(path);
        } else if (id == 1)
            dlg_close();
        return;
    case DLG_SAVE:
        if (id == 1) dlg_key(HG_KEY_ENTER, '\n', 0);
        else if (id == 2) dlg_close();
        return;
    case DLG_NEW:
        if (id == 1) {
            game_new_city((unsigned)(port_seed() ^ (last_seed * 7919u)) & 0x7FFF, new_level);
            redraw();
        } else if (id >= 10 && id <= 12) {
            new_level = id - 10;
            SetGameLevelFunds((short)new_level);
            redraw();
        } else if (id == 2)
            dlg_close();
        else if (id == 3)
            dlg_open(DLG_LOAD, 0);
        else if (id == 4)
            dlg_open(DLG_SCEN, 0);
        return;
    case DLG_SCEN:
        if (id >= 10) {
            dlg_close();
            game_scenario(id - 9);
        } else if (id == 1)
            dlg_close();
        return;
    case DLG_MSG:
        if (dlg_arg == 1) {
            if (id == 2) {
                dlg_close();
                if (CityFileName && game_save(CityFileName)) quit_game = 1;
                else dlg_open(DLG_SAVE, 0);
            } else if (id == 3) {
                quit_game = 1;
            } else if (id == 1)
                dlg_close();
        } else if (id == 1 || id < 0)
            dlg_close();
        return;
    }
}

void dlg_key(unsigned key, unsigned ch, unsigned mods)
{
    (void)mods;
    if (key == HG_KEY_ESC) {
        if (dlg == DLG_SAVE && dlg_arg == 2)
            return;
        dlg_close();
        return;
    }
    if (dlg == DLG_SAVE) {
        int l = (int)strlen(save_name);
        if (key == HG_KEY_ENTER) {
            char path[24];
            if (!l) return;
            sprintf(path, "%s.CTY", save_name);
            dlg_close();
            if (game_save(path))
                panel_message("Saved.");
            return;
        }
        if (key == HG_KEY_BKSP && l) save_name[l - 1] = 0;
        else if (l < 8 && ((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') ||
                           (ch >= '0' && ch <= '9')))
            save_name[l] = (char)(ch >= 'a' ? ch - 32 : ch), save_name[l + 1] = 0;
        redraw();
        return;
    }
    if (key == HG_KEY_ENTER && dlg != DLG_NEW && dlg != DLG_LOAD && dlg != DLG_SCEN &&
        dlg != DLG_MENU)
        dlg_close();
}

/* while a window is open: its values again now and then */
void dlg_tick(void)
{
    static unsigned long last;
    unsigned long now = (unsigned long)hz_uptime();
    if (now - last < 2000)
        return;
    last = now;
    if ((dlg == DLG_EVAL || dlg == DLG_BUDGET) && SimSpeed && !sim_paused)
        redraw();
    else if ((dlg == DLG_MAP || dlg == DLG_GRAPH) && now - opened_ms > 2000 && !sim_paused &&
             SimSpeed) {
        static unsigned n;
        if (++n % 5 == 0)               /* (the map costs a fifth of a second) */
            redraw();
    }
}
