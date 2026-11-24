/* simtest.c - the simulator without a screen, the same program in every build: the
 * Atari816 (SIMTEST.PRG, from the shell) and the PC's two twins (build/host16/simtest:
 * the engine with a 16-bit int as the Atari816's; build/host32/simtest: upstream's types).
 * The same city, the same random seed and the same ticks must give the same state in all
 * three: its checksum (hooks.c, port_checksum) every K ticks.
 *
 *   simtest [res DIR] (gen SEED | load FILE | scen N) [build] [speed S] [ticks N]
 *           [every K] [tool NAME X Y]... [save FILE] [dump FILE]
 *
 *   res DIR      where snro.NNN are (default: the current folder)
 *   gen SEED     a new city from the terrain generator, seeded (0 to 65,535)
 *   load FILE    a city file (.cty)
 *   scen N       scenario N (1 Dullsville ... 8 Rio de Janeiro)
 *   build        lay a small city with the tools (roads, zones, a power plant, wires):
 *                a generated city has none, and an empty one does not change
 *   speed S      upstream's speeds: 1 slow, 2 medium, 3 fast (default 3)
 *   ticks N      ticks to run (default 1000); every K: a line each K ticks (default 100)
 *   tool NAME X Y  a tool used at tile (X, Y) before the run (names as w_tool.c's states:
 *                res com ind fire query police wire doze rail road stadium park seaport
 *                coal nuclear airport)
 *   save FILE    the city saved at the end (upstream's .cty format)
 *   dump FILE    the whole state as text at the end
 *
 * Output: "sim: start <state>", "sim: tick N <state>", "sim: end N <state>" with <state>
 * = port_state_line's "crc XXXXXXXX time T funds F pop P r R c C i I score S valves ...".
 *
 * Copyright (C) 2026 the Atari816 project. GPL-3 with EA's additional terms.
 */
#include "sim.h"
#include "hooks.h"
#if defined(__CC816__)
#include <horizon.h>
#endif

static long ticks;
static unsigned seed_value;
static int quiet = 1;

/* ---------------------------------------------------------------- the front end's hooks */

void port_eval(const char *cmd)
{
    /* the messages, for a reader of the log; nothing depends on them */
    if (!quiet || strncmp(cmd, "UISetMessage", 12) == 0)
        printf("eval: %s\n", cmd);
}

void port_sound(const char *channel, const char *sound)
{
    (void)channel;
    (void)sound;
}

long port_ticks(void)
{
    return ticks * 3;           /* (a tick is 50 ms at upstream's default delay) */
}

unsigned port_seed(void)
{
    return seed_value;
}

#if defined(__CC816__)
void MAPFAR *port_far_alloc(unsigned size)
{
    unsigned char __far *p = hz_far_alloc();
    if (!p)
        port_fatal("no free bank for the maps");
    hz_far_set(p, 0, size);
    return p;
}
#else
void *port_far_alloc(unsigned size)
{
    void *p = calloc(1, size);
    if (!p)
        port_fatal("no memory for the maps");
    return p;
}
#endif

void port_fatal(const char *why)
{
    printf("sim: fatal: %s\n", why);
    exit(2);
}

/* ---------------------------------------------------------------- the tools */

static const char *const toolnames[] = {
    "res", "com", "ind", "fire", "query", "police", "wire", "doze", "rail", "road",
    "chalk", "eraser", "stadium", "park", "seaport", "coal", "nuclear", "airport",
    "network", NULL
};

static int tool_state(const char *name)
{
    int i;
    for (i = 0; toolnames[i]; i++)
        if (strcmp(toolnames[i], name) == 0)
            return i;
    return -1;
}

static int tool(int state, int x, int y)
{
    SimView *v = port_view();
    v->tool_state = state;
    return do_tool(v, state, x << 4, y << 4, 1);
}

/* a small city with the tools: two rows of zones between three roads, a coal power
 * plant at their left end, a wire to the second row, a police and a fire station */
static int dry(int x0, int y0)
{
    int x, y, t;
    for (x = x0 - 6; x < x0 + 36; x++)
        for (y = y0 - 4; y < y0 + 13; y++) {
            if (x < 0 || y < 0 || x >= WORLD_X || y >= WORLD_Y)
                return 0;
            t = Map[x][y] & LOMASK;
            if (t >= RIVER && t <= LASTRIVEDGE)
                return 0;
        }
    return 1;
}

static void build(void)
{
    int x0 = 48, y0 = 40, k, x;

    /* dry land for it: of the places without water, the one nearest the middle */
    {
        int bx = -1, by = -1, best = 32767, cx, cy, d;
        for (cy = 6; cy < WORLD_Y - 14; cy += 2)
            for (cx = 8; cx < WORLD_X - 37; cx += 2) {
                d = (cx > 42 ? cx - 42 : 42 - cx) + (cy > 44 ? cy - 44 : 44 - cy);
                if (d < best && dry(cx, cy)) {
                    best = d;
                    bx = cx;
                    by = cy;
                }
            }
        if (bx >= 0) {
            x0 = bx;
            y0 = by;
        }
    }
    printf("sim: build at %d %d\n", x0, y0);

    SetFunds(100000L);
    autoBulldoze = 1;
    tool(powerState, x0 - 3, y0 + 2);              /* 4 x 4: x0-4 .. x0-1, y0+1 .. y0+4 */
    for (x = x0 - 6; x < x0 + 33; x++) {
        tool(roadState, x, y0);
        tool(roadState, x, y0 + 4);
        tool(roadState, x, y0 + 8);
    }
    for (k = 0; k < 10; k++) {
        int st = k % 3 == 0 ? residentialState : k % 3 == 1 ? commercialState :
                 industrialState;
        tool(st, x0 + 1 + 3 * k, y0 + 2);
        tool(k % 3 == 2 ? residentialState : st, x0 + 1 + 3 * k, y0 + 6);
    }
    for (k = 5; k < 8; k++)
        tool(wireState, x0 - 1, y0 + k);
    tool(policeState, x0 + 32, y0 + 2);
    tool(fireState, x0 + 32, y0 + 6);
    for (x = y0 - 4; x < y0 + 13; x++)
        tool(roadState, x0 + 34, x);
    SetFunds(20000L);
}

/* ---------------------------------------------------------------- the run */

static void line(const char *what, long t)
{
    char buf[160];
    port_state_line(buf);
    if (t < 0)
        printf("sim: %s %s\n", what, buf);
    else
        printf("sim: %s %" PRIQ " %s\n", what, t, buf);
}

int main(int argc, char **argv)
{
    long n = 1000, every = 100, t;
    int speed = 3, i, built = 0;
    char *save = NULL, *dump = NULL;
    static char path[160];
#if defined(__CC816__)
    unsigned long t0, t1;
#endif

    port_init();
    ResourceDir = ".";
    autoBudget = 1;             /* the budget is not asked for (it would pause) */
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "res") == 0 && i + 1 < argc) {
            ResourceDir = argv[++i];
        } else if (strcmp(argv[i], "seed") == 0 && i + 1 < argc) {
            seed_value = (unsigned)strtol(argv[++i], NULL, 10);   /* RandomlySeedRand's */
        } else if (strcmp(argv[i], "gen") == 0 && i + 1 < argc) {
            seed_value = (unsigned)strtol(argv[++i], NULL, 10);
            GenerateSomeCity((unsigned QUAD)seed_value);
        } else if (strcmp(argv[i], "load") == 0 && i + 1 < argc) {
            strncpy(path, argv[++i], sizeof path - 1);
            if (!LoadCity(path)) {
                printf("sim: cannot load %s\n", argv[i]);
                return 1;
            }
        } else if (strcmp(argv[i], "scen") == 0 && i + 1 < argc) {
            LoadScenario((short)atoi(argv[++i]));
        } else if (strcmp(argv[i], "build") == 0) {
            built = 1;
        } else if (strcmp(argv[i], "speed") == 0 && i + 1 < argc) {
            speed = atoi(argv[++i]);
        } else if (strcmp(argv[i], "ticks") == 0 && i + 1 < argc) {
            n = strtol(argv[++i], NULL, 10);
        } else if (strcmp(argv[i], "every") == 0 && i + 1 < argc) {
            every = strtol(argv[++i], NULL, 10);
        } else if (strcmp(argv[i], "tool") == 0 && i + 3 < argc) {
            int st = tool_state(argv[i + 1]);
            int r = st < 0 ? -9 : tool(st, atoi(argv[i + 2]), atoi(argv[i + 3]));
            printf("sim: tool %s %s %s -> %d\n", argv[i + 1], argv[i + 2], argv[i + 3], r);
            i += 3;
        } else if (strcmp(argv[i], "down") == 0 && i + 3 < argc) {
            /* the game's own calls (its log's "tool down S X Y", "tool drag S X Y", "tool
               up S X Y": the tool, world pixels), as the game makes them */
            SimView *v = port_view();
            v->tool_state = (short)atoi(argv[i + 1]);
            ToolDown(v, atoi(argv[i + 2]), atoi(argv[i + 3]));
            DoUpdateHeads();
            i += 3;
        } else if (strcmp(argv[i], "drag") == 0 && i + 3 < argc) {
            SimView *v = port_view();
            v->tool_state = (short)atoi(argv[i + 1]);
            ToolDrag(v, atoi(argv[i + 2]), atoi(argv[i + 3]));
            DoUpdateHeads();
            i += 3;
        } else if (strcmp(argv[i], "up") == 0 && i + 3 < argc) {
            SimView *v = port_view();
            v->tool_state = (short)atoi(argv[i + 1]);
            ToolUp(v, atoi(argv[i + 2]), atoi(argv[i + 3]));
            DoUpdateHeads();
            i += 3;
        } else if (strcmp(argv[i], "save") == 0 && i + 1 < argc) {
            save = argv[++i];
        } else if (strcmp(argv[i], "dump") == 0 && i + 1 < argc) {
            dump = argv[++i];
        } else if (strcmp(argv[i], "rand") == 0 && i + 1 < argc) {
            int k, m = atoi(argv[++i]);
            SeedRand(seed_value);
            for (k = 0; k < m; k++)
                printf("rand %d %u %d %d\n", k, Rand16(), Rand(99), Rand16Signed());
        } else if (strcmp(argv[i], "verbose") == 0) {
            quiet = 0;
        } else {
            printf("sim: what is '%s'?\n", argv[i]);
            return 1;
        }
    }
    if (built)
        build();
    setSpeed((short)speed);
    line("start", -1);
#if defined(__CC816__)
    t0 = hz_uptime();
#endif
    for (t = 1; t <= n; t++) {
        ++ticks;
        port_tick();
        if (every > 0 && t % every == 0 && t != n)
            line("tick", t);
    }
#if defined(__CC816__)
    t1 = hz_uptime();
#endif
    line("end", n);
#if defined(__CC816__)
    printf("sim: %ld ticks in %lu ms\n", n, (t1 - t0));
#endif
    if (save) {
        if (saveFile(save))
            printf("sim: saved %s\n", save);
        else
            printf("sim: cannot save %s\n", save);
    }
    if (dump) {
        FILE *f = fopen(dump, "w");
        if (f) {
            port_dump(f);
            fclose(f);
            printf("sim: dumped %s\n", dump);
        }
    }
    return 0;
}
