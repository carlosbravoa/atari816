/* hz_main.c - SkyRoads on Horizon: the program's main loop (upstream's was
 * src/platform/main.cpp, on SDL).
 *
 * The game ticks at 36 Hz (the DOS timer: 180.02 Hz / 5); the screen at 60.03. Each
 * vertical blank the ticks that came due run (from the frame counter: 3600 ticks every
 * 6003 frames), then the last tick's scene is drawn into a free page and shown.
 *
 * /BENCH: the phase-1 experiment: the attract demo, each frame's simulation and drawing
 * repeated 10 times and timed (hz_uptime, 10 ms steps: 1 ms resolution), a line a frame. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <hgame.h>
#include <horizon.h>

#include "core/app.h"
#include "data/level.h"
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
static RenderedFrame fr;

static void load_game(void)
{
    unsigned g, groups = 0;
    unsigned long t0 = (unsigned long)hz_uptime();
    roads = load_roads_lzs_path(plat_asset_path(root, "ROADS.LZS"));
    demo = load_demo_rec_path(plat_asset_path(root, "DEMO.REC"));
    levels = levels_from_roads_archive(&roads);
    attract_mode_assets_load_from_root(&renderer.assets_, root);
    renderer_init(&renderer);
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

static void draw_play(const DemoPlaybackState *scene, unsigned page)
{
    fr.frame = hzv_page[page];
    renderer_render_play_scene_incremental(&renderer, &fr, &cache, &hzv_prime[page], scene);
    fb_ops.sync(&fr.frame);
}

/* the phase-1 experiment */
static int bench(void)
{
    enum { R = 10 };
    AppInput none;
    AppTickResult t;
    unsigned n = 0, k, worst_sim = 0, worst_ren = 0, worst_f = 0;
    unsigned long sum_sim = 0, sum_ren = 0;
    memset(&none, 0, sizeof none);
    for (;;) {
        unsigned long t0, t1, t2;
        unsigned sim, ren, page;
        hg_poll();
        t0 = (unsigned long)hz_uptime();
        for (k = 0; k < R; ++k) {
            scratch_app = app;
            app_tick(&scratch_app, none, &t);
        }
        t1 = (unsigned long)hz_uptime();
        app_tick(&app, none, &t);
        if (t.mode != AppMode_DemoPlayback) {
            if (n)
                break;
            continue;
        }
        page = hzv_free_page();
        draw_play(&t.render_scene.play, page);   /* (the first frame of a road builds the underlay) */
        renderer_span_count = 0;
        t2 = (unsigned long)hz_uptime();
        for (k = 0; k < R; ++k)
            draw_play(&t.render_scene.play, page);
        ren = (unsigned)((unsigned long)hz_uptime() - t2);   /* ms for R frames = 0.1 ms units */
        sim = (unsigned)(t1 - t0);
        hzv_palette(&fr.palette);
        hzv_show(page, 20);
        if (n) {
            sum_sim += sim;
            sum_ren += ren;
            if (sim > worst_sim) worst_sim = sim;
            if (ren > worst_ren) { worst_ren = ren; worst_f = n; }
        }
        printf("f %u sim %u.%u ren %u.%u spans %lu\n", n, sim / 10, sim % 10, ren / 10, ren % 10,
               renderer_span_count / R);
        n++;
    }
    printf("skyroads: bench %u frames: sim %lu.%lu ms average, %u.%u worst; draw %lu.%lu ms average, "
           "%u.%u worst (frame %u)\n",
           n, sum_sim / (n - 1) / 10, sum_sim / (n - 1) % 10, worst_sim / 10, worst_sim % 10,
           sum_ren / (n - 1) / 10, sum_ren / (n - 1) % 10, worst_ren / 10, worst_ren % 10, worst_f);
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
        hzv_palette(&fr.palette);
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
            app_tick(&app, none, &t);
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
        draw_play(&t.render_scene.play, page);
        t2 = (unsigned long)hz_uptime();
        hzv_palette(&fr.palette);
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

int main(int argc, char **argv)
{
    bool do_bench = argc > 1 && strcmp(argv[1], "/BENCH") == 0;
    bool do_check = argc > 1 && strcmp(argv[1], "/CHECK") == 0;
    int i;
    for (i = 1; i < argc; ++i)
        if (strcmp(argv[i], "/NOFAST") == 0)
            hzv_nofast = true;
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
    return paced(argc > 2 ? (unsigned)atoi(argv[2]) : 0);
}
