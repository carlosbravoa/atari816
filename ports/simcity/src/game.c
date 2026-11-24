/* game.c - Micropolis on the Atari816: the start, the main loop (the simulation's ticks
 * between frames, the view, the panel, the windows), the mouse and the keys, the tools,
 * new cities, loading and saving, the front end's side of upstream's Tcl commands.
 *
 *   MICROPOL.PRG [FILE.CTY | city FILE | scen N | seed N] [paused] [level N]
 *
 * Copyright (C) 2026 the Atari816 project. GPL-3 with Electronic Arts' additional terms
 * (engine/README). Micropolis is a registered trademark of Micropolis Corporation
 * (Micropolis GmbH) and is licensed here as a courtesy of the owner.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <horizon.h>
#include "sim.h"
#include "hooks.h"
#include "ui.h"

unsigned char quit_game;
char app_dir[128];
unsigned last_seed;
long frames_late;
void dlg_message(const char *a, const char *b, const char *c, const char *d);
void view_resend(void);
extern short autoGo;
SimView *port_view_tool(void);

static unsigned long ticks_run, tick_ms;

/* ---------------------------------------------------------------- the engine's hooks */

static char *args[20];
static char argbuf[440];

/* upstream's Tcl command line into words ({...} one word) */
static int split(const char *cmd)
{
    int n = 0;
    char *o = argbuf;
    while (*cmd && n < 20 && o < argbuf + sizeof argbuf - 64) {
        while (*cmd == ' ')
            ++cmd;
        if (!*cmd)
            break;
        args[n++] = o;
        if (*cmd == '{') {
            int depth = 1;
            ++cmd;
            while (*cmd && depth) {
                if (*cmd == '{') ++depth;
                else if (*cmd == '}' && --depth == 0) break;
                *o++ = *cmd++;
            }
            if (*cmd) ++cmd;
        } else
            while (*cmd && *cmd != ' ')
                *o++ = *cmd++;
        *o++ = 0;
    }
    return n;
}

static void copy(char *dst, const char *src, unsigned n)
{
    strncpy(dst, src, n - 1);
    dst[n - 1] = 0;
}

/* the sounds of upstream's UIDidTool* procedures (micropolis.tcl): a vowel at a speed */
static void tool_sound(const char *t)
{
    static const char *const tab[] = {
        "Res", "O", "6", "Com", "A", "6", "Ind", "E", "6", "Fire", "O", "5", "Qry", "E", "12",
        "Pol", "E", "5", "Wire", "O", "3", "Dozr", "Rumble", "0", "Rail", "O", "0", "Road", "E",
        "0", "Stad", "O", "-2", "Park", "A", "5", "Seap", "E", "-2", "Coal", "O", "-5", "Nuc",
        "E", "-5", "Airp", "A", "-2", NULL
    };
    int i;
    for (i = 0; tab[i]; i += 3)
        if (strcmp(t, tab[i]) == 0) {
            snd_play(tab[i + 1], atoi(tab[i + 2]));
            return;
        }
}

void port_eval(const char *cmd)
{
    int n = split(cmd), i;
    const char *c = n ? args[0] : "";

    if (strcmp(c, "UISetMessage") == 0 && n > 1) {
        panel_message(args[1]);
        printf("micropolis: message %s\n", args[1]);
    } else if (strcmp(c, "UISetFunds") == 0 && n > 1) {
        copy(funds_str, args[1], sizeof funds_str);
        panel_dirty = 1;
    } else if (strcmp(c, "UISetDate") == 0 && n > 1) {
        copy(date_str, args[1], sizeof date_str);
        panel_dirty = 1;
    } else if (strcmp(c, "UISetDemand") == 0 && n > 3) {
        demand_r = atoi(args[1]);
        demand_c = atoi(args[2]);
        demand_i = atoi(args[3]);
        panel_dirty = 1;
    } else if (strcmp(c, "UISetCityName") == 0 && n > 1) {
        copy(city_name, args[1], sizeof city_name);
        panel_dirty = 1;
    } else if (strcmp(c, "UISetSpeed") == 0) {
        panel_dirty = 1;
    } else if (strcmp(c, "UIShowBudgetAndWait") == 0) {
        dlg_open(DLG_BUDGET, 1);
    } else if (strcmp(c, "UISetEvaluation") == 0 && n > 18) {
        for (i = 0; i < 18; i++)
            copy(eval_strs[i], args[1 + i], sizeof eval_strs[i]);
        eval_valid = 1;
    } else if (strcmp(c, "UIShowZoneStatus") == 0 && n > 6) {
        for (i = 0; i < 6; i++)
            copy(query_text[i], args[1 + i], sizeof query_text[i]);
        printf("micropolis: query %s\n", query_text[0]);
        dlg_open(DLG_QUERY, 0);
    } else if (strcmp(c, "UIAutoGoto") == 0 && n > 2) {
        if (dlg == DLG_NONE)
            view_center(atoi(args[1]), atoi(args[2]));
    } else if (strcmp(c, "UILoseGame") == 0) {
        dlg_message("The citizens have had enough of you:", "they ran you out of office.",
                    "", "You lost.");
    } else if (strcmp(c, "UIWinGame") == 0) {
        dlg_message("Congratulations!", "The citizens are delighted with you:",
                    "you met the scenario's goal.", "");
    } else if (strcmp(c, "UIEarthQuake") == 0) {
        view_shake();
    } else if (strncmp(c, "UIDidTool", 9) == 0) {
        tool_sound(c + 9);
    } else if (strcmp(c, "UIDidntLoadCity") == 0 && n > 1) {
        panel_message("That city could not be loaded.");
    } else if (strcmp(c, "UIPopUpMessage") == 0 && n > 1) {
        dlg_message(args[1], "", "", "");
    } else if (strcmp(c, "UISaveCityAs") == 0) {
        dlg_open(DLG_SAVE, 0);
    }
}

void port_sound(const char *channel, const char *sound)
{
    (void)channel;
    snd_play(sound, 0);
}

long port_ticks(void)
{
    return (long)((unsigned long)hz_uptime() * 6 / 100);
}

static unsigned fixed_seed;            /* "seed N" given: every seed from it (tests) */

unsigned port_seed(void)
{
    return fixed_seed ? fixed_seed : (unsigned)hz_uptime();
}

void MAPFAR *port_far_alloc(unsigned size)
{
    unsigned char __far *p = hz_far_alloc();
    if (!p)
        port_fatal("no free memory bank for the maps");
    hz_far_set(p, 0, size);
    return p;
}

void port_fatal(const char *why)
{
    printf("micropolis: fatal: %s\n", why);
    exit(2);
}

/* ---------------------------------------------------------------- the game's actions */

void game_tool(int state)
{
    cur_tool = state;
    panel_dirty = 1;
}

void game_speed(int s)
{
    if (s == 0) {
        if (sim_paused) Resume();
        else Pause();
    } else {
        if (sim_paused)
            Resume();
        setSpeed((short)s);
    }
    panel_dirty = 1;
    printf("micropolis: speed %d%s\n", SimMetaSpeed, sim_paused ? " paused" : "");
}

void game_disaster(int d)
{
    switch (d) {
    case 0: MakeFire(); break;
    case 1: MakeFlood(); break;
    case 2: MakeTornado(); break;
    case 3: MakeEarthquake(); break;
    case 4: MakeMonster(); break;
    case 5: MakeMeltdown(); break;
    case 6: MakeAirCrash(); break;
    }
    printf("micropolis: disaster %d\n", d);
}

/* where the view starts: the city's centre of mass (PopDenScan's CCx, CCy), or for an
 * empty map the driest place near the middle */
static void start_view(void)
{
    extern short CCx, CCy;
    int bx = WORLD_X / 2, by = WORLD_Y / 2, best = -1, x, y, i, j;
    if (TotalZPop || ResZPop + ComZPop + IndZPop) {
        view_center(CCx, CCy);
        return;
    }
    for (y = 10; y < WORLD_Y - 10; y += 5)
        for (x = 16; x < WORLD_X - 16; x += 6) {
            int n = 0, d = (x > 60 ? x - 60 : 60 - x) + (y > 50 ? y - 50 : 50 - y);
            for (i = -12; i < 12; i += 3)
                for (j = -6; j < 6; j += 2)
                    n += (Map[x + i][y + j] & LOMASK) == DIRT;
            n = n * 4 - d;
            if (n > best) {
                best = n;
                bx = x;
                by = y;
            }
        }
    view_center(bx, by);
}

static void after_new_city(void)
{
    eval_valid = 0;
    view_invalidate();
    start_view();
    panel_dirty = 1;
    DoUpdateHeads();
}

void game_new_city(unsigned seed, int level)
{
    setSpeed(0);
    last_seed = seed;
    GenerateSomeCity((unsigned QUAD)seed);
    SetGameLevelFunds((short)level);
    CityTax = 7;
    setAnyCityName("NEWCITY");
    setSpeed(0);
    after_new_city();
    printf("micropolis: new city %u\n", seed);
}

int game_load(const char *path)
{
    static char p[64];
    copy(p, path, sizeof p);
    if (!LoadCity(p)) {
        printf("micropolis: cannot load %s\n", path);
        return 0;
    }
    if (!sim_paused)
        setSpeed(3);
    after_new_city();
    printf("micropolis: loaded %s\n", path);
    return 1;
}

int game_save(const char *path)
{
    static char p[64];
    copy(p, path, sizeof p);
    if (!saveFile(p)) {
        panel_message("The city could not be saved (the card full?).");
        printf("micropolis: cannot save %s\n", path);
        return 0;
    }
    if (CityFileName != p) {
        if (CityFileName)
            free(CityFileName);
        CityFileName = malloc(strlen(p) + 1);
        if (CityFileName)
            strcpy(CityFileName, p);
    }
    printf("micropolis: saved %s\n", path);
    panel_message("The city is saved.");
    return 1;
}

void game_scenario(int n)
{
    static const char *const intro[8][3] = {
        { "Dullsville, USA 1900:", "nothing ever happens here. Make it grow", "into a big city in 30 years." },
        { "San Francisco, CA 1906:", "an earthquake. Rebuild the city", "within 5 years." },
        { "Hamburg, Germany 1944:", "fire bombs fall. Rebuild the city", "within 5 years." },
        { "Bern, Switzerland 1965:", "traffic chokes the city.", "Fix it within 10 years." },
        { "Tokyo, Japan 1957:", "a monster attacks the city.", "Rebuild within 5 years." },
        { "Detroit, MI 1972:", "crime and decay.", "Lower the crime within 10 years." },
        { "Boston, MA 2010:", "a nuclear meltdown.", "Rebuild within 5 years." },
        { "Rio de Janeiro, Brazil 2047:", "the sea is rising: floods.", "Save the city in 10 years." },
    };
    LoadScenario((short)n);
    after_new_city();
    printf("micropolis: scenario %d\n", n);
    if (n >= 1 && n <= 8)
        dlg_message(intro[n - 1][0], intro[n - 1][1], intro[n - 1][2], "");
}

/* ---------------------------------------------------------------- input */

static int mouse_down, last_mx, last_my;

static void key_global(unsigned key, unsigned ch, unsigned mods)
{
    if (mods & HG_MOD_CTRL) {
        if (key == HG_KEY_A + ('N' - 'A')) dlg_open(DLG_NEW, 0);
        else if (key == HG_KEY_A + ('O' - 'A')) dlg_open(DLG_LOAD, 0);
        else if (key == HG_KEY_A + ('S' - 'A')) dlg_open(DLG_SAVE, 1);
        else if (key == HG_KEY_A + ('Q' - 'A')) dlg_open(DLG_QUIT, 0);
        return;
    }
    switch (key) {
    case HG_KEY_LEFT: view_scroll(-64, 0); return;
    case HG_KEY_RIGHT: view_scroll(64, 0); return;
    case HG_KEY_UP: view_scroll(0, -64); return;
    case HG_KEY_DOWN: view_scroll(0, 64); return;
    case HG_KEY_SPACE: game_speed(0); return;
    case HG_KEY_F1 + 1: game_speed(1); return;
    case HG_KEY_F1 + 2: game_speed(2); return;
    case HG_KEY_F1 + 3: game_speed(3); return;
    case HG_KEY_ESC: dlg_open(DLG_QUIT, 0); return;
    }
    if (ch >= 'a' && ch <= 'z')
        ch -= 32;
    switch (ch) {
    case 'D': game_tool(dozeState); break;
    case 'R': game_tool(roadState); break;
    case 'T': game_tool(rrState); break;
    case 'W': game_tool(wireState); break;
    case 'K': game_tool(parkState); break;
    case '1': game_tool(residentialState); break;
    case '2': game_tool(commercialState); break;
    case '3': game_tool(industrialState); break;
    case 'P': game_tool(policeState); break;
    case 'F': game_tool(fireState); break;
    case 'S': game_tool(stadiumState); break;
    case 'E': game_tool(seaportState); break;
    case 'O': game_tool(powerState); break;
    case 'N': game_tool(nuclearState); break;
    case 'A': game_tool(airportState); break;
    case 'Q': game_tool(queryState); break;
    case 'B': dlg_open(DLG_BUDGET, 0); break;
    case 'V': dlg_open(DLG_EVAL, 0); break;
    case 'G': dlg_open(DLG_GRAPH, 0); break;
    case 'M': dlg_open(DLG_MAP, 0); break;
    case 'Z': view_zoom(!zoom8); panel_dirty = 1; break;
    }
}

/* the world pixel (16 a tile, upstream's) under screen (x, y) */
static int wpx(int x) { return (cam_x + x) * (zoom8 ? 2 : 1); }
static int wpy(int y) { return (cam_y + y - PANEL_H) * (zoom8 ? 2 : 1); }

static void input(void)
{
    unsigned k, clicked;
    int mx = hg_mouse_x, my = hg_mouse_y, w;

    while ((k = hg_key_next()) != 0) {
        unsigned key = k & 0xFF, ch = k >> 8, mods = hg_key_mods;
        if (key == HG_KEY_F1 + 8) {     /* F9: the state and a picture (the tests) */
            char b[160];
            FILE *f;
            port_state_line(b);
            printf("micropolis: state %s\n", b);
            if (mods & HG_MOD_SHIFT) {          /* Shift+F9: the whole state to STATE.TXT */
                f = fopen("STATE.TXT", "w");
                if (f) {
                    port_dump(f);
                    fclose(f);
                }
            }
            printf("micropolis: shot\n");
            continue;
        }
        if (dlg != DLG_NONE)
            dlg_key(key, ch, mods);
        else
            key_global(key, ch, mods);
    }
    clicked = hg_mouse_clicked();
    w = hg_mouse_wheel();
    if (dlg != DLG_NONE) {
        mouse_down = 0;
        if (clicked & 1) {
            if (my < PANEL_H) {
                if (dlg == DLG_MENU || my >= 12)
                    dlg_close();
                panel_click(mx, my);
            } else
                dlg_click(mx, my - PANEL_H, 1);
        }
        view_cursor(0, 0, 0, 0);
        return;
    }
    if (w)
        view_scroll(0, -w * 48);
    /* the edges of the screen scroll the map */
    if (my >= PANEL_H && !mouse_down) {
        int dx = mx <= 1 ? -8 : mx >= 638 ? 8 : 0, dy = my >= 358 ? 8 : my <= PANEL_H + 1 ? -8 : 0;
        if (dx || dy)
            view_scroll(dx, dy);
    }
    if (clicked & 1) {
        if (my < PANEL_H) {
            panel_click(mx, my);
        } else {
            mouse_down = 1;
            /* (each call to the engine's tools on the log: tests/check.sh gives the same
               calls to simtest on the PC and compares the states) */
            printf("micropolis: tool down %d %d %d\n", cur_tool, wpx(mx), wpy(my));
            ToolDown(port_view_tool(), wpx(mx), wpy(my));
            DoUpdateHeads();
        }
    } else if (mouse_down && (hg_mouse_b & 1)) {
        if (mx != last_mx || my != last_my) {
            if (my < PANEL_H) my = PANEL_H;
            printf("micropolis: tool drag %d %d %d\n", cur_tool, wpx(mx), wpy(my));
            ToolDrag(port_view_tool(), wpx(mx), wpy(my));
            DoUpdateHeads();
        }
    } else if (mouse_down) {
        mouse_down = 0;
        printf("micropolis: tool up %d %d %d\n", cur_tool, wpx(mx), wpy(my < PANEL_H ? PANEL_H : my));
        ToolUp(port_view_tool(), wpx(mx), wpy(my < PANEL_H ? PANEL_H : my));
        DoUpdateHeads();
    }
    if ((clicked & 2) && my >= PANEL_H) {       /* the right button: what is there? */
        SimView *v = port_view();
        do_tool(v, queryState, (short)wpx(mx), (short)wpy(my), 1);
    }
    last_mx = mx;
    last_my = my;
    if (my >= PANEL_H) {
        extern short toolSize[], toolOffset[];
        int tx = (cam_x + mx) / (int)tile_px, ty = (cam_y + my - PANEL_H) / (int)tile_px;
        view_cursor(tx - toolOffset[cur_tool], ty - toolOffset[cur_tool], toolSize[cur_tool], 1);
    } else
        view_cursor(0, 0, 0, 0);
}

/* the view the tools act through, its state the current tool */
SimView *port_view_tool(void)
{
    SimView *v = port_view();
    v->tool_state = (short)cur_tool;
    return v;
}

/* ---------------------------------------------------------------- the loop */

static void colours(void)
{
    static const unsigned char ui[][3] = {
        { 0, 0, 0 }, { 255, 255, 255 }, { 192, 192, 192 }, { 96, 96, 96 }, { 240, 240, 240 },
        { 16, 16, 16 }, { 40, 80, 200 }, { 255, 255, 255 }, { 252, 248, 232 }, { 32, 64, 140 },
        { 220, 30, 30 }, { 30, 170, 40 }, { 40, 90, 230 }, { 230, 200, 20 }, { 255, 255, 255 },
        { 110, 110, 110 },
        /* the graphs */
        { 30, 170, 40 }, { 40, 90, 230 }, { 210, 180, 0 }, { 0, 150, 150 }, { 220, 30, 30 },
        { 140, 90, 30 }
    };
    unsigned i;
    for (i = 0; i < sizeof ui / 3; i++)
        hg_color(C_BLACK + i, ui[i][0], ui[i][1], ui[i][2]);
    for (i = 0; i < 16; i++)            /* the overlays: green, yellow, red */
        hg_color(C_RAMP + i, i < 8 ? 40 + i * 26 : 240, i < 8 ? 200 : 240 - (i - 8) * 28, 30);
}

int main(int argc, char **argv)
{
    int i, start_paused = 0, level = 0, scen = 0;
    unsigned seed = 0, pauses = 0, frame = 0;
    char *city = NULL;
    unsigned long t0, t1;

    if (hz_prog_dir(app_dir, sizeof app_dir) >= 0) {
        int l = (int)strlen(app_dir);
        if (l > 1 && app_dir[l - 1] == '/')
            app_dir[l - 1] = 0;
        hz_chdir(app_dir);
    }
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "paused") == 0) start_paused = 1;
        else if (strcmp(argv[i], "seed") == 0 && i + 1 < argc)
            fixed_seed = seed = (unsigned)atoi(argv[++i]);
        else if (strcmp(argv[i], "scen") == 0 && i + 1 < argc) scen = atoi(argv[++i]);
        else if (strcmp(argv[i], "level") == 0 && i + 1 < argc) level = atoi(argv[++i]);
        else if (strcmp(argv[i], "city") == 0 && i + 1 < argc) city = argv[++i];
        else city = argv[i];            /* a .CTY opened from the Desktop */
    }
    port_init();
    ResourceDir = ".";
    autoBudget = 1;                     /* upstream's defaults (micropolis.tcl) */
    autoGo = 1;
    if (hg_screen_fb(HG_640X360 | HG_POINTER, "Micropolis", FB_STRIDE, FB_ROWS) < 0)
        return 1;
    if (data_load() < 0) {
        printf("micropolis: the game's files are missing in %s\n", app_dir);
        return 1;
    }
    colours();                          /* (after the file's palette: 16-255) */
    view_init();
    panel_message("Welcome to Micropolis.");
    if (!seed)
        seed = port_seed() & 0x7FFF;
    if (city && !game_load(city))
        city = NULL;
    if (!city)
        game_new_city(seed, level);
    if (scen)
        game_scenario(scen);
    else if (!city)
        dlg_open(DLG_NEW, 0);
    if (start_paused) {
        if (dlg == DLG_NEW)
            dlg_close();
        setSpeed(3);
        Pause();
    } else if (city) {
        setSpeed(3);
    }
    printf("micropolis: ready\n");
    while (!quit_game && hg_frame()) {
        ++frame;
        if (hg_pauses != pauses) {      /* back from the Desktop: our view again */
            pauses = hg_pauses;
            view_resend();
        }
        input();
        if (quit_game)
            break;
        /* the simulation: a tick a frame at the fast speed, every other one slower
           (upstream's SimFrame then runs a sixteenth of a pass every 1st, 3rd or 5th) */
        if (SimSpeed && dlg != DLG_NEW && dlg != DLG_MENU && dlg != DLG_SAVE &&
            dlg != DLG_LOAD && dlg != DLG_SCEN && dlg != DLG_MSG &&
            (SimMetaSpeed >= 3 || (frame & 1) == 0)) {
            t0 = (unsigned long)hz_uptime();
            port_tick();
            t1 = (unsigned long)hz_uptime();
            ++ticks_run;
            tick_ms += t1 - t0;
            if ((ticks_run & 511) == 0) {
                printf("micropolis: %lu ticks, %lu ms a tick, %lu tiles drawn\n", ticks_run,
                       tick_ms / 512, view_draws);
                tick_ms = 0;
            }
            if (ShakeNow)
                ShakeNow = 0;
        }
        if (dlg == DLG_NONE)
            view_update();
        else {
            dlg_tick();
            view_update();              /* (the sprites hidden; no tiles drawn) */
        }
        panel_draw();
        view_send();
    }
    hg_stats("MICROPOLIS");
    return 0;
}
