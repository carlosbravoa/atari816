/* hz_main.c - SkyRoads on Horizon: the program's main loop (upstream's was
 * src/platform/main.cpp, on SDL).
 *
 * The game ticks at 36 Hz (the DOS timer: 180.02 Hz / 5); the screen at 60.03. Each
 * vertical blank the ticks that came due run (from the frame counter: 3600 ticks every
 * 6003 frames), then the last tick's scene is drawn into a free page and shown.
 *
 * /BENCH: the phase-1 experiment: the attract demo, each frame's simulation and drawing
 * repeated 10 times and timed (hz_uptime, 10 ms steps: 1 ms resolution), a line a frame.
 * /NORUNS: the road's spans by the CPU even where Horizon has fill_runs (0.30). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <hgame.h>
#include <horizon.h>

#include "core/app.h"
#include "data/level.h"
#include "data/byteio.h"
#include "data/roads.h"
#include "platform.h"
#include "renderer/renderer.h"
#include "hz_plat.h"

static Renderer renderer;
static AttractModeApp app, scratch_app;
static RoadsArchive roads;
static DemoRecording demo;
static Level *levels;
static char root[128];
static PlaySceneCache cache;
static bool nofile_prep;                /* /NOPREP: make it all here, as before round 2 */
static RenderedFrame fr;

static void load_game(void)
{
    unsigned g, groups = 0;
    unsigned long t0 = (unsigned long)hz_uptime();
    roads = load_roads_lzs_path(plat_asset_path(root, "ROADS.LZS"));
    demo = load_demo_rec_path(plat_asset_path(root, "DEMO.REC"));
    levels = levels_from_roads_archive(&roads);
    {
        /* (round 2) TREKDAT's spans and the ship's sprites from SKYPREP.DAT (srtool prepare)
         * when it is there; else made here (about 20 s) */
        Bytes prep;
        if (!nofile_prep && plat_read_file(plat_asset_path(root, "SKYPREP.DAT"), &prep)) {
            attract_mode_assets_load(&renderer.assets_, root, false);
            if (!renderer_init_prepared(&renderer, &prep))
                sr_fail("SKYPREP.DAT is not one (srtool prepare makes it)");
            free_bytes(&prep);
        } else {
            attract_mode_assets_load_from_root(&renderer.assets_, root);
            renderer_init(&renderer);
        }
    }
    app_init(&app, levels, roads.road_count, &demo);
    for (g = 0; g < renderer.assets_.anim.frame_count; ++g)
        if (renderer.assets_.anim.frames[g].count)
            groups++;
    app_set_intro_anim_group_count(&app, groups);
    if (archive_has_frame(&renderer.assets_.dashboard, 0))
        hzv_register_fragment(archive_front(&renderer.assets_.dashboard, 0), 0x5C);
    if (renderer.dash_cache_ok)
        hzv_register_fragment(&renderer.dash_top, 0x5C);
    printf("skyroads: dashboard cache %s, sprite fast path %s\n",
           renderer.dash_cache_ok ? "on" : "off", renderer.car_atlas_.keyed_ok ? "on" : "off");
    hzv_underlay(&cache);
    printf("skyroads: loaded in %lu ms, %u banks\n", (unsigned long)hz_uptime() - t0,
           hzp_banks_used);
}

/* the palette shown: sent when the renderer's copy changed (RenderedFrame.palette_stamp) */
static unsigned shown_stamp = 0xFFFF;
static void show_palette(void)
{
    if (fr.palette_stamp != shown_stamp) {
        hzv_palette(&fr.palette);
        shown_stamp = fr.palette_stamp;
    }
}

static void draw_play(const DemoPlaybackState *scene, unsigned page)
{
    fr.frame = hzv_page[page];
    renderer_render_play_scene_incremental(&renderer, &fr, &cache, &hzv_prime[page], scene);
    fb_ops.sync(&fr.frame);
}

/* (round 2) a hash of the demo session's whole state (both ships, the session's flags):
 * host srtool demo-state prints the same, tick by tick */
static unsigned long state_hash(const GameplaySession *g)
{
    const Ship *sh[2];
    unsigned long h = 5381;
    unsigned k;
    sh[0] = &g->ship;
    sh[1] = &g->expected_ship;
#define MIX(v) (h = (h << 5) + h + (unsigned long)(long)(v))
    for (k = 0; k < 2; ++k) {
        const Ship *s = sh[k];
        MIX(s->x_position_128); MIX(s->y_position_128); MIX(s->z_position_fp16);
        MIX(s->slide_amount_128); MIX(s->sliding_accel); MIX(s->x_movement_base_128);
        MIX(s->y_velocity_128); MIX(s->z_velocity_fp16); MIX(s->fuel_remaining);
        MIX(s->oxygen_remaining); MIX(s->offset_at_which_not_inside_tile);
        MIX(s->is_on_ground); MIX(s->is_going_up); MIX(s->has_run_jump_o_master);
        MIX(s->jump_o_master_velocity_delta_fp16); MIX(s->jump_o_master_in_use);
        MIX(s->jumped_from_y_position_128); MIX(s->state);
    }
    MIX(g->did_win); MIX(g->has_death_frame_index); MIX(g->death_frame_index);
    MIX(g->frame_index_);
#undef MIX
    return h;
}

/* the experiment (round 2: one run, hz_uptime_us): each demo tick's simulation and the
 * drawing of its frame, a line a frame "f N SIM_US DRAW_US RUNS GROUPS", then the summary */
static int bench(void)
{
    AppInput none;
    AppTickResult t;
    unsigned n = 0, worst_sim_f = 0, worst_f = 0, busy_n = 0;
    unsigned long sum_sim = 0, sum_ren = 0, worst_sim = 0, worst_ren = 0, sum_runs = 0;
    unsigned long busy_sum = 0, busy_worst = 0, busy_runs = 0;
    memset(&none, 0, sizeof none);
    for (;;) {
        unsigned long t0, t1, t2, sim, ren, runs, groups;
        unsigned page;
        hg_poll();
        t0 = (unsigned long)hz_uptime_us();
        app_tick_logic(&app, none, &t);
        t1 = (unsigned long)hz_uptime_us();
        if (t.mode != AppMode_DemoPlayback) {
            if (n)
                break;
            continue;
        }
        page = hzv_free_page();
        runs = hzv_runs;
        groups = hzv_groups;
        t2 = (unsigned long)hz_uptime_us();
        app_scene(&app, &t);            /* (the scene: counted as drawing) */
        draw_play(&t.render_scene.play, page);
        ren = (unsigned long)hz_uptime_us() - t2;
        sim = t1 - t0;
        runs = (unsigned)(hz_span_total - (unsigned)runs);
        groups = hzv_groups - groups;
        show_palette();
        hzv_show(page, 20);
        if (n) {        /* (frame 0 builds the underlay) */
            sum_sim += sim;
            sum_ren += ren;
            sum_runs += runs;
            if (sim > worst_sim) { worst_sim = sim; worst_sim_f = n; }
            if (ren > worst_ren) { worst_ren = ren; worst_f = n; }
            if (n >= 700 && n < 1100) {
                busy_n++;
                busy_sum += ren;
                busy_runs += runs;
                if (ren > busy_worst) busy_worst = ren;
            }
        }
        printf("f %u %lu %lu %lu %lu\n", n, sim, ren, runs, groups);
        n++;
    }
    printf("skyroads: bench %u frames: sim %lu us average, %lu worst (tick %u); "
           "draw %lu us average, %lu worst (frame %u); runs %lu a frame\n",
           n, sum_sim / (n - 1), worst_sim, worst_sim_f, sum_ren / (n - 1), worst_ren, worst_f,
           sum_runs / (n - 1));
    printf("skyroads: bench frames 700-1099: draw %lu us average, %lu worst; runs %lu a frame\n",
           busy_sum / busy_n, busy_worst, busy_runs / busy_n);
    return 0;
}

/* /SIM: the demo's ticks alone (no drawing), twice: the first time timed as a whole (the
 * average without the clock's own cost, about 0.1 ms a reading), the second tick by tick
 * (the worst), for the profiler */
static int sim_only(unsigned repeat_tick)
{
    AppInput none;
    AppTickResult t;
    unsigned n = 0, worst_f = 0, pass;
    unsigned long sum = 0, worst = 0, t0 = 0;
    memset(&none, 0, sizeof none);
    printf("skyroads: sim start\n");
    for (pass = 0; pass < 2; ++pass) {
        n = 0;
        for (;;) {
            unsigned long u0 = 0, d;
            if (pass)
                u0 = (unsigned long)hz_uptime_us();
            if (pass && repeat_tick && n == repeat_tick) {
                /* (the profiler's: that tick 300 times over) */
                unsigned r;
                for (r = 0; r < 300; ++r) {
                    scratch_app = app;
                    app_tick_logic(&scratch_app, none, &t);
                }
                u0 = (unsigned long)hz_uptime_us();
            }
            app_tick_logic(&app, none, &t);
            if (t.mode != AppMode_DemoPlayback) {
                if (n)
                    break;
                continue;
            }
            if (n == 0 && !pass)
                t0 = (unsigned long)hz_uptime_us();
            if (pass) {
                d = (unsigned long)hz_uptime_us() - u0;
                if (d > worst) { worst = d; worst_f = n; }
            }
            n++;
        }
        if (!pass)
            sum = (unsigned long)hz_uptime_us() - t0;
    }
    printf("skyroads: sim %u ticks: %lu us average, %lu worst (tick %u)\n", n, sum / (n - 1), worst,
           worst_f);
    return 0;
}

/* /CHECK: every frame of the demo drawn, its checksum printed (tests/framesum.py makes the
 * same of the C++ original's frames): "c FRAME PIXELS PALETTE" */
static unsigned dump_frame;

static int check(void)
{
    AppInput none;
    AppTickResult t;
    unsigned n = 0;
    memset(&none, 0, sizeof none);
    for (;;) {
        unsigned page;
        hg_poll();
        app_tick(&app, none, &t);
        if (t.mode != AppMode_DemoPlayback) {
            if (n)
                break;
            continue;
        }
        page = hzv_free_page();
        draw_play(&t.render_scene.play, page);
        printf("c %u %08lx %08lx\n", n, hz_sum(hzv_page[page].pixels, 32000),
               hz_sum(fr.palette.colors, 384));
        printf("s %u %08lx\n", n, state_hash(&app.demo_session_));
        if (n == dump_frame && dump_frame) {
            /* the frame as a file (tests: compare a frame byte for byte) */
            static unsigned char row[320];
            char path[140];
            int h;
            unsigned y;
            hz_io io;
            sprintf(path, "%sFRAME.RAW", root);
            h = hz_open(path, HZ_O_CREATE);
            for (y = 0; y < 200 && h >= 0; ++y) {
                hz_far_copy(row, hzv_page[page].pixels + y * 320u, 320);
                io.handle = (unsigned char)h;
                HZ_U24(io.buf, row);
                io.len = 320;
                hz_write(&io);
            }
            if (h >= 0) {
                io.handle = (unsigned char)h;
                HZ_U24(io.buf, fr.palette.colors);
                io.len = 768;
                hz_write(&io);
                hz_close((unsigned)h);
            }
        }
        show_palette();
        hzv_show(page, 20);
        n++;
    }
    printf("skyroads: check %u frames\n", n);
    return 0;
}

/* the demo at the game's speed: how many of its ticks get a frame of their own */
static int paced(unsigned shot_every)
{
    AppInput none;
    AppTickResult t;
    unsigned start, done = 0, drawn = 0, merged = 0, n = 0, vsyncs = 0;
    unsigned long t_sim = 0, t_draw = 0, t_rest = 0, t0, t1, t2, t3;
    bool in_demo = false;
    memset(&none, 0, sizeof none);
    start = hz_frame();
    for (;;) {
        unsigned long due_total;
        unsigned due, page;
        if (!hg_poll())
            break;
        due_total = (unsigned long)(unsigned)(hz_frame() - start) * 3600UL / 6003UL;
        due = (unsigned)(due_total - done);
        if (due == 0) {
            if (in_demo)
                vsyncs++;
            hz_vsync();
            continue;
        }
        t0 = (unsigned long)hz_uptime();
        if (due > 4) {
            merged += due - 4;
            done += due - 4;
            due = 4;
        }
        merged += due - 1;
        while (due--) {
            app_tick_logic(&app, none, &t);
            done++;
            if (t.mode == AppMode_DemoPlayback) {
                in_demo = true;
                n++;
            } else if (in_demo)
                goto end;
        }
        if (!in_demo) {
            merged = 0;
            continue;
        }
        t1 = (unsigned long)hz_uptime();
        page = hzv_free_page();
        app_scene(&app, &t);
        draw_play(&t.render_scene.play, page);
        t2 = (unsigned long)hz_uptime();
        show_palette();
        hzv_show(page, 20);
        t3 = (unsigned long)hz_uptime();
        t_sim += t1 - t0;
        t_draw += t2 - t1;
        t_rest += t3 - t2;
        drawn++;
        if (shot_every && n % shot_every == 0)
            printf("skyroads: frame %u\n", n);
    }
end:
    printf("skyroads: paced demo: %u ticks, %u drawn, %u ticks without a frame of their own\n",
           n, drawn, merged);
    printf("skyroads: paced: %u waits for a blank; ms in all: ticks %lu, drawing %lu, showing %lu\n",
           vsyncs, t_sim, t_draw, t_rest);
    {
        extern unsigned long hzv_wait_ms, hzv_syncs;
        printf("skyroads: paced: waiting for Ali %lu ms in %lu waits; %lu blits\n", hzv_wait_ms,
               hzv_syncs, hzv_blits);
    }
    return 0;
}

/* (round 2) /BEAT [RATE]: the demo at 36 ticks a second, its frames shown on a steady beat:
 * RATE 36 (a frame every 27.8 ms, every tick), 24 (every 41.7 ms: ticks 0, 1, 3, 4, 6, ...:
 * the tick due at that time) or 18 (every 55.6 ms, every second tick); or 0 (the default):
 * the highest of those the drawing keeps up with, stepping down at once when frames come
 * late and up again only after a long clean stretch with room to spare (no fluttering).
 * Frame k is drawn after frame k - 1 is shown and shown at the first blank after its time
 * (base + k periods); finished after that time it is late (shown at once, and the beat's
 * slots that went by are skipped). Timed by hz_uptime_us. Prints the frames, the late ones,
 * the rate held. */
static unsigned long beat_us(unsigned rate, unsigned k)  /* k periods, in us */
{
    return rate == 36 ? (unsigned long)k * 250000UL / 9UL
         : rate == 24 ? (unsigned long)k * 125000UL / 3UL
                      : (unsigned long)k * 500000UL / 9UL;
}

static unsigned beat_ticks(unsigned rate, unsigned k)   /* the ticks k periods make */
{
    return rate == 36 ? k : rate == 24 ? k * 3u / 2u : k * 2u;
}

/* the frame drawn and kept until its slot's time (hzv_held), shown by beat_poll */
static unsigned long held_due;
static bool debug_beat;

static void beat_poll(void)
{
    if (hzv_held != 0xFFFF && (long)((unsigned long)hz_uptime_us() - held_due) >= 0) {
        hzv_flip(hzv_held, 20);
        hzv_held = 0xFFFF;
    }
}

/* wait for the kept frame's time, and show it */
static void beat_flush(void)
{
    while (hzv_held != 0xFFFF)
        beat_poll();
}

static int beat(unsigned fixed)
{
    AppInput none;
    AppTickResult t;
    /* (adaptive: from 24, the rate the busy stretch holds; it goes up to 36 by the rule below
     * when the drawing leaves room) */
    unsigned rate = fixed ? fixed : 24, n = 0, drawn = 0, late = 0, changes = 0, k = 0;
    unsigned base_tick = 0, win_frames = 0, win_late = 0, clean = 0, ri;
    unsigned at_rate[3] = {0, 0, 0}, late_at[3] = {0, 0, 0}, busy_drawn = 0, busy_late = 0;
    unsigned long base = 0, sum_work = 0, d_max = 0, d_sum = 0;
    bool ended = false;
    memset(&none, 0, sizeof none);
    /* the intro's ticks (nothing drawn) up to the demo's first */
    for (;;) {
        app_tick_logic(&app, none, &t);
        if (t.mode == AppMode_DemoPlayback)
            break;
    }
    hzv_poll_hook = beat_poll;
    base = (unsigned long)hz_uptime_us();       /* slot 0: tick 0, now */
    while (!ended && hg_poll()) {
        unsigned long now, due, w0, d0;
        unsigned f, page;
        long slack;
        bool is_late;
        /* the next slot not gone by yet (the beat's base may lie ahead: frames are drawn
         * ahead of their time) */
        now = (unsigned long)hz_uptime_us() - base;
        if ((long)now > 0)
            while (drawn && beat_us(rate, k) + 4000UL < now)
                k++;
        f = base_tick + beat_ticks(rate, k);
        w0 = (unsigned long)hz_uptime_us();
        while (n < f) {             /* the ticks up to f (n: the tick the state is at) */
            beat_poll();
            app_tick_logic(&app, none, &t);
            n++;
            if (t.mode != AppMode_DemoPlayback) {
                ended = true;
                break;
            }
        }
        if (ended)
            break;
        beat_poll();
        page = hzv_free_page();
        d0 = (unsigned long)hz_uptime_us();
        app_scene(&app, &t);
        draw_play(&t.render_scene.play, page);
        beat_poll();
        hzv_ready(page);
        now = (unsigned long)hz_uptime_us();
        if (now - d0 > d_max)
            d_max = now - d0;
        d_sum += now - d0;
        sum_work += now - w0;
        due = base + beat_us(rate, k);
        slack = (long)(due - now);
        is_late = slack < 0;
        /* the frame before it first (and its palette with it: the palette changes only with
         * the road), then this one: now if its time has come, else kept for beat_poll (the
         * next frame is drawn meanwhile: a heavy frame borrows the time a light one left) */
        beat_flush();
        show_palette();
        if (is_late)
            hzv_flip(page, 20);
        else {
            hzv_held = page;
            held_due = due;
        }
        drawn++;
        ri = rate == 36 ? 0 : rate == 24 ? 1 : 2;
        at_rate[ri]++;
        if (f >= 700 && f < 1100) {
            busy_drawn++;
            busy_late += is_late;
        }
        if (is_late) {
            late++;
            late_at[ri]++;
        }
        k++;
        /* the rate: down at once after 2 late frames in a window of 12; up after 72 frames
         * in a row on time when their drawing (a frame drawn early lends its room to the next)
         * would fit the higher rate's period with its ticks (2.2 ms each: 1.5 a frame at 24,
         * 1 at 36) and some 5 ms to spare: on average 33 ms and at most 41 ms for 24, 21 and
         * 25 ms for 36 */
        if (is_late) {
            win_late++;
            clean = 0;
            d_max = d_sum = 0;
        } else
            clean++;
        if (++win_frames == 12)
            win_frames = win_late = 0;
        if (debug_beat && (drawn % 24) == 0)
            printf("beat f %u rate %u slack %ld dmax %lu clean %u\n", f, rate, slack, d_max, clean);
        if (!fixed) {
            unsigned nrate = rate;
            if (win_late >= 2 && rate > 18)
                nrate = rate == 36 ? 24 : 18;
            else if (clean >= 72 && rate < 36 &&
                     d_max <= (rate == 18 ? 41000UL : 25000UL) &&
                     d_sum / clean <= (rate == 18 ? 33000UL : 21000UL))
                nrate = rate == 18 ? 24 : 36;
            else if (clean >= 72) {     /* (a new stretch of 72 to judge by) */
                clean = 0;
                d_max = d_sum = 0;
            }
            if (nrate != rate) {
                /* the new beat starts from the last slot shown */
                base += beat_us(rate, k - 1);
                base_tick += beat_ticks(rate, k - 1);
                rate = nrate;
                k = 1;
                changes++;
                win_frames = win_late = 0;
                clean = 0;
                d_max = d_sum = 0;
            }
        }
    }
    beat_flush();
    hzv_poll_hook = 0;
    printf("skyroads: beat demo: %u ticks, %u frames shown, %u late; frames at 36/24/18: %u/%u/%u "
           "(late %u/%u/%u); %u rate changes; frames 700-1099: %u shown, %u late; "
           "work %lu us a frame\n",
           n, drawn, late, at_rate[0], at_rate[1], at_rate[2], late_at[0], late_at[1], late_at[2],
           changes, busy_drawn, busy_late, sum_work / (drawn ? drawn : 1));
    return 0;
}

int main(int argc, char **argv)
{
    bool do_bench = argc > 1 && strcmp(argv[1], "/BENCH") == 0;
    bool do_check = argc > 1 && strcmp(argv[1], "/CHECK") == 0;
    bool do_sim = argc > 1 && strcmp(argv[1], "/SIM") == 0;
    int i;
    for (i = 1; i < argc; ++i)
        if (strcmp(argv[i], "/NOFAST") == 0)
            hzv_nofast = true;
        else if (strcmp(argv[i], "/NORUNS") == 0)
            hzv_noruns = true;
        else if (strcmp(argv[i], "/DEBUG") == 0)
            debug_beat = true;
        else if (strcmp(argv[i], "/NOPREP") == 0)
            nofile_prep = true;
        else if (strncmp(argv[i], "/DUMP:", 6) == 0)
            dump_frame = (unsigned)atoi(argv[i] + 6);
    if (hz_prog_dir(root, sizeof root) < 0)
        strcpy(root, "/");
    if (hzv_init() < 0) {
        printf("skyroads: no full screen\n");
        return 1;
    }
    hg_autopause(0);
    load_game();
    if (do_bench)
        return bench();
    if (do_check)
        return check();
    if (do_sim)
        return sim_only(argc > 2 ? (unsigned)atoi(argv[2]) : 0);
    if (argc > 1 && strcmp(argv[1], "/BEAT") == 0)
        return beat(argc > 2 ? (unsigned)atoi(argv[2]) : 0);
    if (argc > 1 && (strcmp(argv[1], "/MOVECHECK") == 0 || strcmp(argv[1], "/PROBECHECK") == 0)) {
        unsigned l;
        for (l = 0; l < roads.road_count; ++l)
            level_build(&levels[l]);
    }
    if (argc > 1 && strcmp(argv[1], "/MOVECHECK") == 0) {
        printf("skyroads: movecheck: %lu of %lu moves and scans differ\n",
               hzm_check(levels, roads.road_count, 1000), roads.road_count * 2000UL);
        return 0;
    }
    if (argc > 1 && strcmp(argv[1], "/PROBECHECK") == 0) {
        printf("skyroads: probecheck: %lu of %lu points differ\n",
               hzp_check(levels, roads.road_count, 5000), roads.road_count * 5000UL);
        return 0;
    }
    return paced(argc > 2 ? (unsigned)atoi(argv[2]) : 0);
}
