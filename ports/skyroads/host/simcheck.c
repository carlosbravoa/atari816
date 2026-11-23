/* simcheck.c - the simulation of round 2 (src/core/gameplay.c, included here with its static
 * functions) against the one before it (ref_gameplay.c: gameplay.c of commit 2784ebf), on
 * a PC.
 *
 *   srsimcheck DIR [TRIALS]
 *
 * 1. Each function whose arithmetic was narrowed, against the expression it replaces, over
 *    every value of its fast range and its edges (fifths, bounce_velocity, the bounce scan's
 *    band test against the probe itself).
 * 2. Whole ticks: random ships (positions, velocities, tanks, flags, controls; the edges of
 *    every fast path's range and far beyond them; states that run the jump-o-master) on all
 *    31 roads, each ship_update'd by both and compared field by field, events too; and
 *    each such ship run on for 40 ticks with random controls, compared after every tick.
 * Exit status 0 when nothing differs. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned long cover_bounce_band, cover_bounce_probes, cover_land_slow, cover_land_fast,
    cover_zstride, cover_jom_variants, cover_move16, cover_move32, cover_bounce_probes16, cover_land_closed;
#define COVER(name) (cover_##name++)
#include "../src/core/gameplay.c"

#include "data/roads.h"
#include "platform.h"

void ship_update_ref(Ship *ship, const Level *level, Ship *expected, ControllerState controls,
                     GameplayEvents *events);

static unsigned long rng_state = 12345;
static uint32_t rnd(void)
{
    rng_state = rng_state * 6364136223846793005ULL + 1442695040888963407ULL;
    return (uint32_t)(rng_state >> 33);
}
static int32_t rr(int32_t lo, int32_t hi) { return lo + (int32_t)(rnd() % (uint32_t)(hi - lo + 1)); }

static int32_t sdiv_small_ref(int32_t v, int d)
{
    if (v >= -32767 && v <= 32767)
        return (int32_t)((int)v / d);
    return v / d;
}

static unsigned long fails;
#define CHECK(cond, ...) do { if (!(cond)) { if (fails++ < 20) { printf(__VA_ARGS__); printf("\n"); } } } while (0)

static void check_helpers(const Level *levels, unsigned nlev)
{
    int32_t v;
    unsigned f, k;
    unsigned long n = 0;
    for (v = -200000; v <= 200000; ++v) {
        for (f = 0; f <= 5; ++f)
            CHECK(fifths(v, f) == sdiv_small_ref(v * (int32_t)f, 5), "fifths(%d, %u)", v, f);
        CHECK(bounce_velocity(v) == sdiv_small_ref(-(v * 5), 10), "bounce_velocity(%d)", v);
        n += 7;
    }
    for (k = 0; k < 2000000; ++k) {
        static const int32_t big[] = {INT32_MIN / 8, -100000000, -70000, 70000, 100000000, INT32_MAX / 8};
        v = big[rnd() % 6] + rr(-1000, 1000);
        f = rnd() % 6;
        CHECK(fifths(v, f) == sdiv_small_ref(v * (int32_t)f, 5), "fifths(%d, %u)", v, f);
        CHECK(bounce_velocity(v) == sdiv_small_ref(-(v * 5), 10), "bounce_velocity(%d)", v);
        n += 2;
    }
    printf("simcheck: fifths, bounce_velocity: %lu values\n", n);

    /* the bounce scan's band test: band_inside(mask, u0 +- i) against the probe at
     * (x +- 128 i, y in the band, z) */
    n = 0;
    for (k = 0; k < 3000000; ++k) {
        const Level *l = &levels[rnd() % nlev];
        const int32_t x = (rnd() & 3) ? rr(-3000, 70000) : rr(-400000, 400000);
        const int32_t y = rr(0x1E81, 0x27FF);
        const int32_t z = rr(-3 * 65536, ((int32_t)l->length + 3) * 65536);
        const int32_t d = x - (1792 + 95 * 128);
        unsigned mask = 0;
        int u0, i;
        if (z >= 0 && (uint32_t)z >> 16 < l->length)
            mask = l->row_mask[(uint32_t)z >> 16];
        if (d < -2000L * 128)
            u0 = -2000;
        else if (d > 2000L * 128)
            u0 = 2000;
        else if (d >= 0)
            u0 = (int)(d >> 7);
        else
            u0 = -(int)((-d + 127) >> 7);
        for (i = -14; i <= 14; ++i) {
            const bool want = level_is_inside_tile_128_ref(l, x + i * 128, y, z);
            CHECK(band_inside(mask, u0 + i) == want, "band_inside x %d y %d z %d i %d", x, y, z, i);
            n++;
        }
    }
    printf("simcheck: the bounce scan's band test: %lu probes\n", n);
}

static bool ships_equal(const Ship *a, const Ship *b)
{
    return a->x_position_128 == b->x_position_128 && a->y_position_128 == b->y_position_128 &&
           a->z_position_fp16 == b->z_position_fp16 && a->slide_amount_128 == b->slide_amount_128 &&
           a->sliding_accel == b->sliding_accel && a->x_movement_base_128 == b->x_movement_base_128 &&
           a->y_velocity_128 == b->y_velocity_128 && a->z_velocity_fp16 == b->z_velocity_fp16 &&
           a->fuel_remaining == b->fuel_remaining && a->oxygen_remaining == b->oxygen_remaining &&
           a->offset_at_which_not_inside_tile == b->offset_at_which_not_inside_tile &&
           a->is_on_ground == b->is_on_ground && a->is_going_up == b->is_going_up &&
           a->has_run_jump_o_master == b->has_run_jump_o_master &&
           a->jump_o_master_velocity_delta_fp16 == b->jump_o_master_velocity_delta_fp16 &&
           a->jump_o_master_in_use == b->jump_o_master_in_use &&
           a->jumped_from_y_position_128 == b->jumped_from_y_position_128 && a->state == b->state;
}

static void print_ship(const char *what, const Ship *s)
{
    printf("  %s x %d y %d z %d slide %d sa %d xmb %d yv %d zv %d fuel %d oxy %d off %d g%d u%d r%d "
           "jd %d ju %d jf %d st %u\n",
           what, s->x_position_128, s->y_position_128, s->z_position_fp16, s->slide_amount_128,
           s->sliding_accel, s->x_movement_base_128, s->y_velocity_128, s->z_velocity_fp16,
           s->fuel_remaining, s->oxygen_remaining, s->offset_at_which_not_inside_tile,
           s->is_on_ground, s->is_going_up, s->has_run_jump_o_master,
           s->jump_o_master_velocity_delta_fp16, s->jump_o_master_in_use,
           s->jumped_from_y_position_128, s->state);
}

/* a value near the typical ones, now and then at a fast path's edge or far outside it */
static int32_t pick(int32_t lo, int32_t hi, const int32_t *edges, unsigned nedges)
{
    const uint32_t r = rnd() % 100;
    if (r < 70)
        return rr(lo, hi);
    if (r < 90 && nedges)
        return edges[rnd() % nedges] + rr(-3, 3);
    return (int32_t)(rnd() % 2000001) - 1000000;
}

static void random_ship(Ship *s, const Level *l)
{
    static const int32_t X_EDGES[] = {6272, 57855, 12160, 12160 + 41216, 0x2F80, 0xD080, 32767, 32768, 65535, 65536, 0};
    static const int32_t Y_EDGES[] = {0x1E80, 0x2800, 0x2180, 68 * 128, 100 * 128, 120 * 128, -20000, 32767, 0, 110 * 128};
    static const int32_t V_EDGES[] = {0, 0x2AAA, 6553, -6553, 13107, 32767, -32767, 65535, 5461, -5461};
    const int32_t zmax = ((int32_t)l->length + 2) * 65536;
    memset(s, 0, sizeof *s);
    s->x_position_128 = pick(0x2F80 - 3000, 0xD080 + 3000, X_EDGES, 11);
    switch (rnd() % 4) {
    case 0: s->y_position_128 = rr(0x2800 - 300, 0x2800 + 300); break;
    case 1: s->y_position_128 = rr(100 * 128 - 300, 120 * 128 + 300); break;
    case 2: s->y_position_128 = rr(0x1E00, 0x3800); break;
    default: s->y_position_128 = pick(-5000, 20000, Y_EDGES, 10); break;
    }
    s->z_position_fp16 = (rnd() % 10) ? rr(-65536, zmax) : pick(-200000, zmax, 0, 0);
    s->slide_amount_128 = (rnd() % 3) ? 0 : (rnd() % 3) ? 0x11 * rr(-6, 6) : pick(-3000, 3000, V_EDGES, 10);
    s->sliding_accel = (int16_t)rr(-3, 3);
    s->x_movement_base_128 = (rnd() % 2) ? 0x1D * rr(-1, 1) : pick(-60, 60, V_EDGES, 10);
    s->y_velocity_128 = pick(-300, 0x480 + 200, V_EDGES, 10);
    s->z_velocity_fp16 = (rnd() % 5) ? rr(0, 0x2AAA) : pick(-500, 0x2AAA + 500, V_EDGES, 10);
    s->fuel_remaining = rr(-100, 0x7530 + 100);
    s->oxygen_remaining = rr(-100, 0x7530 + 100);
    s->offset_at_which_not_inside_tile = (int16_t)rr(0, 15);
    s->is_on_ground = rnd() & 1;
    s->is_going_up = rnd() & 1;
    s->has_run_jump_o_master = rnd() & 1;
    s->jump_o_master_velocity_delta_fp16 = (rnd() % 2) ? 0 : rr(-0x2AAA, 0x2AAA);
    s->jump_o_master_in_use = rnd() & 1;
    s->jumped_from_y_position_128 = s->y_position_128 - rr(-2000, 6000);
    s->state = (uint8_t)((rnd() % 3) ? 0 : rnd() % 5);
    if (rnd() % 4 == 0) {
        /* about to run the jump-o-master */
        s->is_going_up = true;
        s->has_run_jump_o_master = false;
        s->y_position_128 = rr(110 * 128, 140 * 128);
        s->y_velocity_128 = rr(-200, 0x480);
        s->state = 0;
    }
}

static void random_controls(ControllerState *c)
{
    c->turn_input = (int8_t)rr(-1, 1);
    c->accel_input = (int8_t)rr(-1, 1);
    c->jump_input = (rnd() % 4) == 0;
}

static bool one(const Level *l, Ship *a, Ship *ea, Ship *b, Ship *eb, ControllerState c,
                unsigned long trial, unsigned tick)
{
    GameplayEvents eva, evb;
    const Ship sa = *a, sea = *ea;
    ship_update(a, l, ea, c, &eva);
    ship_update_ref(b, l, eb, c, &evb);
    if (!ships_equal(a, b) || !ships_equal(ea, eb) || eva.count != evb.count ||
        memcmp(eva.e, evb.e, eva.count) != 0) {
        if (fails++ < 10) {
            printf("simcheck: trial %lu tick %u differs (road %u, controls %d %d %d)\n", trial, tick,
                   l->road_index, c.turn_input, c.accel_input, c.jump_input);
            print_ship("before", &sa);
            print_ship("expected before", &sea);
            print_ship("new", a);
            print_ship("ref", b);
            print_ship("new expected", ea);
            print_ship("ref expected", eb);
        }
        return false;
    }
    return true;
}

int main(int argc, char **argv)
{
    RoadsArchive roads;
    Level *levels;
    unsigned long trials, t, ticks = 0, jom = 0;
    if (argc < 2) {
        fprintf(stderr, "usage: srsimcheck DIR [TRIALS]\n");
        return 2;
    }
    trials = argc > 2 ? strtoul(argv[2], NULL, 10) : 200000;
    roads = load_roads_lzs_path(plat_asset_path(argv[1], "ROADS.LZS"));
    levels = levels_from_roads_archive(&roads);
    for (t = 0; t < roads.road_count; ++t)
        level_build(&levels[t]);
    check_helpers(levels, roads.road_count);
    for (t = 0; t < trials; ++t) {
        const Level *l = &levels[rnd() % roads.road_count];
        Ship a, ea, b, eb;
        ControllerState c;
        unsigned k;
        random_ship(&a, l);
        if (rnd() % 2) {
            ea = a;
            ea.y_position_128 += rr(-200, 200);
            ea.x_position_128 += rr(-200, 200);
            ea.z_position_fp16 += rr(-0x3000, 0x3000);
        } else {
            random_ship(&ea, l);
        }
        b = a;
        eb = ea;
        if (a.is_going_up && !a.has_run_jump_o_master && a.y_position_128 >= 110 * 128)
            jom++;
        for (k = 0; k < 40; ++k) {
            random_controls(&c);
            ticks++;
            if (!one(l, &a, &ea, &b, &eb, c, t, k))
                break;
        }
    }
    printf("simcheck: %lu ships, %lu ticks (%lu starting a jump-o-master), %lu differences\n", trials,
           ticks, jom, fails);
    printf("simcheck: paths taken: bounce scans %lu in the band, %lu by 16-bit probes, %lu by probes; landing tests %lu "
           "fast, %lu by the loop; z walk strides %lu; jump-o-master variant rounds %lu; "
           "moves %lu in 16 bits, %lu in 32; landings closed %lu\n",
           cover_bounce_band, cover_bounce_probes16, cover_bounce_probes, cover_land_fast, cover_land_slow, cover_zstride,
           cover_jom_variants, cover_move16, cover_move32, cover_land_closed);
    return fails != 0;
}
