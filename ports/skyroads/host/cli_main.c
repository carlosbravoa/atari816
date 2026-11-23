/* cli_main.c - the C translation of src/cli/main.cpp (skyroads-cli), plus the tools the
 * port's tests use. On a PC.
 *
 *   srtool demo-sim DIR [frames]      the per-frame ship state of the demo, the very text
 *                                     upstream's `skyroads-cli demo-sim` prints
 *   srtool demo-frames DIR OUT [incr] every frame of the attract demo (the intro let run
 *                                     out), 64000 pixels + 768 palette bytes each, by the
 *                                     pure or the incremental renderer
 *   srtool script DIR OUT FILE TICKS  frames of a run driven by a key script
 *   srtool predecode DIR OUT          every LZ stream of the game's files, decoded, into
 *                                     OUT/NAME.DEC (for the Atari816: horizon/hz_data.c)
 *   srtool fadecheck                  the integer fades against the C++'s floats
 *   srtool prepare DIR OUT            (round 2) SKYPREP.DAT: TREKDAT's clipped spans and the
 *                                     ship's sprites as renderer_init makes them, for the
 *                                     Atari816 to read (renderer_init_prepared)
 *   srtool demo-frames DIR OUT incr PREP  the frames with the renderer from PREP
 * (upstream's `summary` printed the inspection catalogs this translation leaves out.) */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "core/app.h"
#include "core/gameplay.h"
#include "data/compression.h"
#include "data/demo.h"
#include "data/level.h"
#include "data/muzax.h"
#include "data/roads.h"
#include "platform.h"
#include "renderer/renderer.h"

static const char *ship_state_name(unsigned state)
{
    switch (state) {
    case ShipState_Alive: return "Alive";
    case ShipState_Exploded: return "Exploded";
    case ShipState_Fallen: return "Fallen";
    case ShipState_OutOfFuel: return "OutOfFuel";
    case ShipState_OutOfOxygen: return "OutOfOxygen";
    }
    return "?";
}

static void join_events(const GameplayEvents *events, char *out)
{
    unsigned i;
    if (events->count == 0) {
        strcpy(out, "-");
        return;
    }
    out[0] = 0;
    for (i = 0; i < events->count; ++i) {
        static const char *names[] = {"ShipBumpedWall", "ShipExploded", "ShipBounced",
                                      "ShipRefilled"};
        if (i)
            strcat(out, ",");
        strcat(out, names[events->e[i]]);
    }
}

static int demo_sim(const char *root, unsigned frame_count)
{
    RoadsArchive roads = load_roads_lzs_path(plat_asset_path(root, "ROADS.LZS"));
    DemoRecording demo = load_demo_rec_path(plat_asset_path(root, "DEMO.REC"));
    Level level = level_from_road_entry(&roads.roads[0]);
    GameplaySession session;
    unsigned i;
    gameplay_session_init(&session, &level);

    printf("SkyRoads Demo Simulation\n");
    printf("source_root: %s\n", root);
    printf("level: %s (index %u)\n", level.name, level.road_index);
    printf("gravity: %u fuel: %u oxygen: %u\n", level.gravity, level.fuel, level.oxygen);
    printf("frames: %u\n\n", frame_count);

    for (i = 0; i < frame_count; ++i) {
        GameplayFrameResult frame;
        char events[256];
        gameplay_run_demo_frame(&session, &demo, &frame);
        join_events(&frame.events, events);
        printf("frame=%04u turn=%+d accel=%+d jump=%d row=%u "
               "pos=(%.6f,%.6f,%.6f) zvel=%.6f oxygen=%.6f fuel=%.6f state=%s "
               "events=%s\n",
               frame.frame_index, frame.controls.turn_input, frame.controls.accel_input,
               frame.controls.jump_input ? 1 : 0, frame.road_row_index,
               frame.snapshot.x_position_128 / 128.0, frame.snapshot.y_position_128 / 128.0,
               frame.snapshot.z_position_fp16 / 65536.0, frame.snapshot.z_velocity_fp16 / 65536.0,
               frame.snapshot.oxygen_remaining / (double)0x7530,
               frame.snapshot.fuel_remaining / (double)0x7530,
               ship_state_name(frame.snapshot.craft_state), events);
    }
    return 0;
}

/* ---- the app, as upstream's host builds it */

/* (round 2) the demo session's whole state as one number: horizon/hz_main.c's state_hash */
static unsigned long state_hash(const GameplaySession *g)
{
    const Ship *sh[2];
    uint32_t h = 5381;
    unsigned k;
    sh[0] = &g->ship;
    sh[1] = &g->expected_ship;
#define MIX(v) (h = (h << 5) + h + (uint32_t)(int32_t)(v))
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

static Renderer renderer;
static AttractModeApp app;
static RoadsArchive roads;
static DemoRecording demo;
static Level *levels;

static void load_game(const char *root)
{
    unsigned g, groups = 0;
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
}

static void load_game_prepared(const char *root, const char *prep);

static void put_frame(FILE *f, const RenderedFrame *r)
{
    unsigned i;
    fwrite(r->frame.pixels, 1, 64000, f);
    for (i = 0; i < 256; ++i) {
        fputc(r->palette.colors[i].r, f);
        fputc(r->palette.colors[i].g, f);
        fputc(r->palette.colors[i].b, f);
    }
}

static int demo_frames(const char *root, const char *outpath, bool incremental, const char *prep)
{
    static uint8_t pixels[64000], under[64000], dash[64000];
    RenderedFrame fr;
    PlaySceneCache cache;
    PagePrime prime;
    AppTickResult t;
    AppInput none;
    unsigned n = 0;
    unsigned long spans = 0, span_px = 0, worst = 0, worst_px = 0;
    FILE *out = fopen(outpath, "wb");
    if (!out)
        sr_fail("cannot write %s", outpath);
    if (prep)
        load_game_prepared(root, prep);
    else
        load_game(root);
    memset(&none, 0, sizeof none);
    memset(&fr, 0, sizeof fr);
    memset(&cache, 0, sizeof cache);
    memset(&prime, 0, sizeof prime);
    fr.frame.width = 320;
    fr.frame.height = 200;
    fr.frame.pixels = pixels;
    cache.underlay = fr.frame;
    cache.underlay.pixels = under;
    cache.dash = fr.frame;
    cache.dash.pixels = dash;
    for (;;) {
        app_tick(&app, none, &t);
        if (t.mode != AppMode_DemoPlayback) {
            if (n)
                break;
            continue;
        }
        renderer_span_count = renderer_span_pixels = 0;
        if (incremental)
            renderer_render_play_scene_incremental(&renderer, &fr, &cache, &prime, &t.render_scene.play);
        else
            renderer_render_scene(&renderer, &fr, &t.render_scene);
        spans += renderer_span_count;
        span_px += renderer_span_pixels;
        if (renderer_span_count > worst)
            worst = renderer_span_count;
        if (renderer_span_pixels > worst_px)
            worst_px = renderer_span_pixels;
        put_frame(out, &fr);
        if (getenv("SR_STATS"))
            printf("%u %lu %lu\n", n, renderer_span_count, renderer_span_pixels);
        n++;
    }
    fclose(out);
    fprintf(stderr, "dashboard cache %s; ", renderer.dash_cache_ok ? "on" : "off");
    fprintf(stderr, "%u frames; spans a frame: %lu on average, %lu at most; their pixels %lu, %lu\n",
            n, spans / n, worst, span_px / n, worst_px);
    return 0;
}

/* demo-state: "s N HASH" for every demo tick, as /CHECK prints them (the state after the
 * tick, the frame it draws) */
static int demo_state(const char *root)
{
    AppTickResult t;
    AppInput none;
    unsigned n = 0;
    load_game(root);
    memset(&none, 0, sizeof none);
    for (;;) {
        app_tick(&app, none, &t);
        if (t.mode != AppMode_DemoPlayback) {
            if (n)
                break;
            continue;
        }
        printf("s %u %08lx\n", n, state_hash(&app.demo_session_));
        n++;
    }
    return 0;
}

/* the script's key list for a tick ("up,+left,") holds this key */
static bool has_key(const char *list, const char *key)
{
    const size_t n = strlen(key);
    const char *p = list;
    while (*p) {
        const char *e = strchr(p, ',');
        size_t len = e ? (size_t)(e - p) : strlen(p);
        if (len == n && strncmp(p, key, n) == 0)
            return true;
        if (!e)
            break;
        p = e + 1;
    }
    return false;
}

static int script_frames(const char *root, const char *outpath, const char *script, unsigned total)
{
    static char keys[20000][64];
    static uint8_t pixels[64000];
    char line[256];
    RenderedFrame fr;
    unsigned t;
    FILE *s = fopen(script, "r"), *out = fopen(outpath, "wb");
    if (!s || !out)
        sr_fail("cannot open the script or the output");
    while (fgets(line, sizeof line, s)) {
        unsigned tick;
        char k[200];
        if (sscanf(line, "%u %199s", &tick, k) == 2 && tick < 20000) {
            strncat(keys[tick], k, 60 - strlen(keys[tick]));
            strncat(keys[tick], ",", 63 - strlen(keys[tick]));
        }
    }
    fclose(s);
    load_game(root);
    memset(&fr, 0, sizeof fr);
    fr.frame.width = 320;
    fr.frame.height = 200;
    fr.frame.pixels = pixels;
    for (t = 0; t < total; ++t) {
        AppInput in;
        AppTickResult r;
        const char *k = t < 20000 ? keys[t] : "";
#define HAS(n) has_key(k, n)
        memset(&in, 0, sizeof in);
        in.up = HAS("up"); in.down = HAS("down"); in.left = HAS("left"); in.right = HAS("right");
        in.enter = HAS("enter"); in.escape = HAS("escape"); in.space = HAS("space");
        in.up_held = HAS("+up"); in.down_held = HAS("+down"); in.left_held = HAS("+left");
        in.right_held = HAS("+right"); in.enter_held = HAS("+enter"); in.space_held = HAS("+space");
        app_tick(&app, in, &r);
        renderer_render_scene(&renderer, &fr, &r.render_scene);
        put_frame(out, &fr);
    }
    fclose(out);
    return 0;
}

/* ---- prepare: SKYPREP.DAT, what renderer_init makes (renderer.c renderer_init_prepared) */
static void put16(FILE *f, unsigned v) { fputc((int)(v & 255), f); fputc((int)((v >> 8) & 255), f); }

/* (round 2, the spans' merge) the centre tile's two halves: pointer slot 3's top face drawn
 * on the left (left offsets) and again on the right (right offsets), the same shape, the
 * same colour (the side tables are the identity below 0x1F). One group of both, its spans
 * joined where they meet, drawn where the left half was, is the same picture when the right
 * half's pixels meet none of the shapes drawn between: the left cell's others and the right
 * side's cells 0..2 (every shape draw_dos_type_0..5 can reach from a cell's pointer k: the
 * cursor goes at most 2, 0, 1, 2, 7, 2 shapes on from pointers 0..5; but column 4's inward
 * face, which needs column 3 without a tile).
 * centre_merge -> its spans (offset, width; both offsets the same) or 0 */
typedef struct { unsigned o, w; } OW;
static int cmp_ow(const void *a, const void *b) { return (int)((const OW *)a)->o - (int)((const OW *)b)->o; }

static unsigned centre_merge(const Renderer *r, unsigned ri, unsigned prow, OW *out)
{
    static unsigned char mark[64000];
    const TrekdatRecord *rec = &r->assets_.trekdat.records[ri];
    const uint16_t *ptr = &rec->pointer_shape[prow * TREKDAT_POINTER_COLUMNS];
    const unsigned s = ptr[3 * 6];
    const PreparedShape *top;
    unsigned k, j, i, slot, n = 0, x;
    int ok = 1;
    OW all[512];
    if (s == TREKDAT_NO_SHAPE || s >= rec->shape_count)
        return 0;
    top = &r->prepared[ri][s];
    if (top->count == 0)
        return 0;
    memset(mark, 0, sizeof mark);
    for (i = 0; i < top->count; ++i)
        for (x = 0; x < top->spans[i].width; ++x)
            mark[top->spans[i].right + x] = 1;
    /* the shapes drawn between: left slot 3's (but its top's own first drawing), right 0..2 */
    for (slot = 0; slot < 4 && ok; ++slot) {
        const int right = slot < 3;
        const unsigned cs = right ? slot : 3;
        for (k = 0; k < 6 && ok; ++k) {
            const unsigned p0 = ptr[cs * 6 + k];
            if (p0 == TREKDAT_NO_SHAPE)
                continue;
            static const unsigned MAXJ[6] = {2, 0, 1, 2, 7, 2};
            for (j = 0; j <= MAXJ[k] && p0 + j < rec->shape_count && ok; ++j) {
                const PreparedShape *sh = &r->prepared[ri][p0 + j];
                if (!right && k == 0 && j == 0)
                    continue;           /* (the left half itself, its first drawing) */
                if (right && slot == 2 && k == 0 && j == 1)
                    continue;           /* (column 4's inward face: drawn only when column 3
                                         * has no tile, and then it has no top face) */
                for (i = 0; i < sh->count && ok; ++i) {
                    const unsigned o = right ? sh->spans[i].right : sh->spans[i].left;
                    for (x = 0; x < sh->spans[i].width; ++x)
                        if (mark[o + x])
                            ok = 0;
                }
            }
        }
    }
    if (!ok)
        return 0;
    if (top->count * 2 > 512)
        return 0;
    for (i = 0; i < top->count; ++i) {
        all[2 * i].o = top->spans[i].left;
        all[2 * i].w = top->spans[i].width;
        all[2 * i + 1].o = top->spans[i].right;
        all[2 * i + 1].w = top->spans[i].width;
    }
    qsort(all, top->count * 2, sizeof(OW), cmp_ow);
    for (i = 0; i < top->count * 2; ++i) {
        if (n && out[n - 1].o + out[n - 1].w == all[i].o && out[n - 1].w + all[i].w <= 255) {
            out[n - 1].w += all[i].w;
            continue;
        }
        if (n && out[n - 1].o + out[n - 1].w > all[i].o)
            return 0;               /* (the halves overlap: left as they are) */
        out[n++] = all[i];
    }
    return n;
}

static int prepare(const char *root, const char *outpath)
{
    static uint8_t chunk[16][65280];
    static unsigned chunk_size[16];
    static unsigned shape_chunk[16][TREKDAT_SHAPE_ROWS + 64], shape_index[16][TREKDAT_SHAPE_ROWS + 64];
    static unsigned cm_chunk[16][TREKDAT_POINTER_ROWS], cm_index[16][TREKDAT_POINTER_ROWS],
        cm_count[16][TREKDAT_POINTER_ROWS];
    static OW cm[512];
    unsigned nchunks = 0, r, sh, k, i, p, merged = 0, before = 0, after = 0;
    const TrekdatArchive *t;
    FILE *f;
    load_game(root);
    t = &renderer.assets_.trekdat;
    if (t->record_count > 16)
        sr_fail("prepare: %u records", t->record_count);
#define NEWCHUNK(bytes) do { if (nchunks == 0 || chunk_size[nchunks - 1] + (bytes) > 65280u) { \
        if (nchunks == 16) sr_fail("prepare: too many spans"); chunk_size[nchunks++] = 0; } } while (0)
#define PUT5(off_l, off_r, w) do { uint8_t *o_ = &chunk[nchunks - 1][chunk_size[nchunks - 1]]; \
        o_[0] = (uint8_t)(off_l); o_[1] = (uint8_t)((off_l) >> 8); o_[2] = (uint8_t)(off_r); \
        o_[3] = (uint8_t)((off_r) >> 8); o_[4] = (uint8_t)(w); chunk_size[nchunks - 1] += 5; } while (0)
    for (r = 0; r < t->record_count; ++r) {
        for (sh = 0; sh < t->records[r].shape_count; ++sh) {
            const PreparedShape *ps = &renderer.prepared[r][sh];
            if (sh >= TREKDAT_SHAPE_ROWS + 64)
                sr_fail("prepare: too many shapes");
            if (ps->count == 0) {
                shape_chunk[r][sh] = 0;
                shape_index[r][sh] = 0;
                continue;
            }
            NEWCHUNK(ps->count * 5u);
            shape_chunk[r][sh] = nchunks - 1;
            shape_index[r][sh] = chunk_size[nchunks - 1] / 5u;
            for (k = 0; k < ps->count; ++k)
                PUT5(ps->spans[k].left, ps->spans[k].right, ps->spans[k].width);
        }
        for (p = 0; p < TREKDAT_POINTER_ROWS; ++p) {
            const unsigned n = centre_merge(&renderer, r, p, cm);
            cm_count[r][p] = n;
            if (!n)
                continue;
            merged++;
            before += 2 * renderer.prepared[r][t->records[r].pointer_shape[p * TREKDAT_POINTER_COLUMNS + 18]].count;
            after += n;
            NEWCHUNK(n * 5u);
            cm_chunk[r][p] = nchunks - 1;
            cm_index[r][p] = chunk_size[nchunks - 1] / 5u;
            for (k = 0; k < n; ++k)
                PUT5(cm[k].o, cm[k].o, cm[k].w);
        }
    }
    f = fopen(outpath, "wb");
    if (!f)
        sr_fail("cannot write %s", outpath);
    fwrite("SKP2", 1, 4, f);
    put16(f, t->record_count);
    for (r = 0; r < t->record_count; ++r) {
        put16(f, t->records[r].shape_count);
        for (k = 0; k < TREKDAT_POINTER_COUNT; ++k)
            put16(f, t->records[r].pointer_shape[k]);
    }
    put16(f, nchunks);
    for (i = 0; i < nchunks; ++i) {
        put16(f, chunk_size[i]);
        put16(f, 0);
        fwrite(chunk[i], 1, chunk_size[i], f);
    }
    for (r = 0; r < t->record_count; ++r)
        for (sh = 0; sh < t->records[r].shape_count; ++sh) {
            const PreparedShape *ps = &renderer.prepared[r][sh];
            put16(f, ps->count);
            fputc(ps->color, f);
            fputc((int)shape_chunk[r][sh], f);
            put16(f, shape_index[r][sh]);
        }
    fputc(renderer.car_atlas_.keyed_ok, f);
    fputc(renderer.car_atlas_.valid, f);
    put16(f, 77);
    for (i = 0; i < 77; ++i) {
        const ImageFrame *fr = i < 14 ? &renderer.car_atlas_.explosion_frames[i]
                                      : &renderer.car_atlas_.exact_ship_frames[i - 14];
        put16(f, fr->width);
        put16(f, fr->height);
        fwrite(fr->pixels.data, 1, (size_t)fr->width * fr->height, f);
    }
    /* the centre merges: a record's 13 pointer rows, {u16 count (0: none), u8 0, u8 chunk,
     * u16 index} */
    for (r = 0; r < t->record_count; ++r)
        for (p = 0; p < TREKDAT_POINTER_ROWS; ++p) {
            put16(f, cm_count[r][p]);
            fputc(0, f);
            fputc(cm_count[r][p] ? (int)cm_chunk[r][p] : 0, f);
            put16(f, cm_count[r][p] ? cm_index[r][p] : 0);
        }
    fclose(f);
    fprintf(stderr, "prepare: %u records, %u chunks of spans, %u centre merges (%u spans -> %u), %s\n",
            t->record_count, nchunks, merged, before, after, outpath);
    return 0;
}

/* load_game, the renderer's part from SKYPREP.DAT (as the Atari816 does) */
static void load_game_prepared(const char *root, const char *prep)
{
    unsigned g, groups = 0;
    Bytes b;
    roads = load_roads_lzs_path(plat_asset_path(root, "ROADS.LZS"));
    demo = load_demo_rec_path(plat_asset_path(root, "DEMO.REC"));
    levels = levels_from_roads_archive(&roads);
    attract_mode_assets_load(&renderer.assets_, root, false);
    if (!plat_read_file(prep, &b) || !renderer_init_prepared(&renderer, &b))
        sr_fail("%s: not a SKYPREP.DAT", prep);
    app_init(&app, levels, roads.road_count, &demo);
    for (g = 0; g < renderer.assets_.anim.frame_count; ++g)
        if (renderer.assets_.anim.frames[g].count)
            groups++;
    app_set_intro_anim_group_count(&app, groups);
}

/* ---- predecode: every stream the loaders decode, in order, with what they consumed */

static FILE *dec_out;
static void store_hook(uint32_t offset, const DecompressResult *r)
{
    uint8_t h[12];
    h[0] = 'L'; h[1] = 'Z'; h[2] = 'D'; h[3] = 0;
    h[4] = (uint8_t)offset; h[5] = (uint8_t)(offset >> 8); h[6] = (uint8_t)(offset >> 16);
    h[7] = (uint8_t)r->output.size; h[8] = (uint8_t)(r->output.size >> 8);
    h[9] = (uint8_t)r->consumed; h[10] = (uint8_t)(r->consumed >> 8);
    h[11] = (uint8_t)(r->consumed >> 16);
    fwrite(h, 1, 12, dec_out);
    fwrite(r->output.data, 1, r->output.size, dec_out);
}

static int predecode(const char *root, const char *outdir)
{
    static const char *names[] = {"ROADS.LZS", "TREKDAT.LZS", "MUZAX.LZS", "INTRO.LZS",
                                  "ANIM.LZS", "MAINMENU.LZS", "HELPMENU.LZS", "SETMENU.LZS",
                                  "GOMENU.LZS", "CARS.LZS", "DASHBRD.LZS", "WORLD0.LZS",
                                  "WORLD1.LZS", "WORLD2.LZS", "WORLD3.LZS", "WORLD4.LZS",
                                  "WORLD5.LZS", "WORLD6.LZS", "WORLD7.LZS", "WORLD8.LZS",
                                  "WORLD9.LZS"};
    unsigned i;
    decompress_store_hook = store_hook;
    for (i = 0; i < sizeof names / sizeof names[0]; ++i) {
        char path[1024];
        char dec[1024];
        snprintf(path, sizeof path, "%s", plat_asset_path(root, names[i]));
        snprintf(dec, sizeof dec, "%s/%.*s.DEC", outdir, (int)(strlen(names[i]) - 4), names[i]);
        dec_out = fopen(dec, "wb");
        if (!dec_out)
            sr_fail("cannot write %s", dec);
        if (strcmp(names[i], "ROADS.LZS") == 0)
            load_roads_lzs_path(path);
        else if (strcmp(names[i], "TREKDAT.LZS") == 0)
            load_trekdat_lzs_path(path);
        else if (strcmp(names[i], "MUZAX.LZS") == 0)
            load_muzax_lzs_path(path);
        else
            load_image_archive_path(path);
        fclose(dec_out);
    }
    return 0;
}

/* the 16-bit probe against the 32-bit one, on every level, at random points */
static int probecheck(const char *root)
{
    RoadsArchive r = load_roads_lzs_path(plat_asset_path(root, "ROADS.LZS"));
    Level *lv = levels_from_roads_archive(&r);
    unsigned long n = 0, bad = 0;
    unsigned i;
    for (i = 0; i < r.road_count; ++i)
        level_build(&lv[i]);
    srand(1);
    for (i = 0; i < 4000000; ++i) {
        const Level *l = &lv[rand() % r.road_count];
        const int32_t x = (rand() % 80000) - 8000;
        const int32_t y = (rand() % 60000) - 30000;
        const int32_t z = (int32_t)(((uint32_t)rand() << 8) % ((uint32_t)(l->length + 4) << 16)) - 65536;
        if (level_is_inside_tile_128(l, x, y, z) != level_is_inside_tile_128_ref(l, x, y, z))
            bad++;
        n++;
    }
    printf("probecheck: %lu points, %lu differ\n", n, bad);
    return bad != 0;
}

int main(int argc, char **argv)
{
    const char *command = argc > 1 ? argv[1] : "";
    if (strcmp(command, "demo-sim") == 0 && argc > 2)
        return demo_sim(argv[2], argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 60);
    if (strcmp(command, "demo-frames") == 0 && argc > 3)
        return demo_frames(argv[2], argv[3], argc > 4 && strcmp(argv[4], "incr") == 0,
                           argc > 5 ? argv[5] : NULL);
    if (strcmp(command, "prepare") == 0 && argc > 3)
        return prepare(argv[2], argv[3]);
    if (strcmp(command, "script") == 0 && argc > 5)
        return script_frames(argv[2], argv[3], argv[4], (unsigned)strtoul(argv[5], NULL, 10));
    if (strcmp(command, "demo-state") == 0 && argc > 2)
        return demo_state(argv[2]);
    if (strcmp(command, "probecheck") == 0 && argc > 2)
        return probecheck(argv[2]);
    if (strcmp(command, "predecode") == 0 && argc > 3)
        return predecode(argv[2], argv[3]);
    fprintf(stderr, "usage: %s demo-sim|demo-frames|script|predecode ...\n", argv[0]);
    return 2;
}
