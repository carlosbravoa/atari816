#include <assert.h>

#include "core/gameplay.h"

/* (host test simcheck counts the paths it took: COVER(name)) */
#ifndef COVER
#define COVER(name) ((void)0)
#endif

static int32_t abs32(int32_t v) { return v < 0 ? -v : v; }

/* C: divisions of the tick in forms the 65816 does quickly, each exactly C's division
 * (truncating toward zero): a 32-bit divide is a call of about 1,000 cycles on the 65816; a
 * 16-bit one by a constant is inline (cc816), by a variable a call. */
/* v / 2^k */
#define SDIV_POW2(v, k) ((v) >= 0 ? (v) >> (k) : -((-(v)) >> (k)))

/* C (round 2): v * f / 5 for f in 0..5 (interp's step), C's truncation: |v| <= 6553 makes
 * v * f fit an int, and a 16-bit divide by the constant 5 is inline; else the 32-bit form
 * (host test simcheck: against the C++'s sdiv_small(v * f, 5) on random and edge values) */
static int32_t fifths(int32_t v, unsigned f)
{
    int p;
    if (v < -6553 || v > 6553)
        return v * (int32_t)f / 5;
    switch (f) {
    case 0: return 0;
    case 1: p = (int)v; break;
    case 2: p = (int)v * 2; break;
    case 3: p = (int)v * 3; break;
    case 4: p = (int)v * 4; break;
    default: return v;          /* v * 5 / 5 */
    }
    return (int32_t)(p / 5);
}

/* the bounce's v * -5 / 10 (sdiv_small(-(v * 5), 10) of the C++ port): 16 bits when
 * |v * 5| fits */
static int32_t bounce_velocity(int32_t v)
{
    if (v >= -6553 && v <= 6553)
        return (int32_t)(-((int)v * 5) / 10);
    return -(v * 5) / 10;
}

static bool in_range_inclusive(int32_t value, int32_t lo, int32_t hi)
{
    return value >= lo && value <= hi;
}

static void push_event(GameplayEvents *events, GameplayEvent e)
{
    if (events->count < GAMEPLAY_MAX_EVENTS)
        events->e[events->count++] = (uint8_t)e;
}

ControllerState controller_neutral(void)
{
    ControllerState c;
    c.turn_input = 0;
    c.accel_input = 0;
    c.jump_input = false;
    return c;
}

ControllerState controller_make(int8_t turn_input, int8_t accel_input, bool jump_input)
{
    ControllerState c;
    assert(turn_input >= -1 && turn_input <= 1);
    assert(accel_input >= -1 && accel_input <= 1);
    c.turn_input = turn_input;
    c.accel_input = accel_input;
    c.jump_input = jump_input;
    return c;
}

void ship_init(Ship *s)
{
    s->x_position_128 = LEVEL_CENTER_X_128;
    s->y_position_128 = GROUND_Y_128;
    s->z_position_fp16 = (int32_t)3 << 16;
    s->slide_amount_128 = 0;
    s->sliding_accel = 0;
    s->x_movement_base_128 = 0;
    s->y_velocity_128 = 0;
    s->z_velocity_fp16 = 0;
    s->fuel_remaining = 0x7530;
    s->oxygen_remaining = 0x7530;
    s->offset_at_which_not_inside_tile = 0;
    s->is_on_ground = true;
    s->is_going_up = false;
    s->has_run_jump_o_master = false;
    s->jump_o_master_velocity_delta_fp16 = 0;
    s->jump_o_master_in_use = false;
    s->jumped_from_y_position_128 = 0;
    s->state = ShipState_Alive;
}

static int32_t clamp_z_velocity(int32_t z_velocity_in_fp16)
{
    return SR_CLAMP(z_velocity_in_fp16, 0, 0x2AAA);
}

static void run_jump_o_master(Ship *s, ControllerState controls, const Level *level);

/* EXE (@0x17fd-0x18d0): each substep position is pos + (delta * fifths) / 5
 * per axis, with the idiv/ldiv truncation toward zero. The double form floored
 * `pos + delta * (fifths / 5.0)` instead, which differs for negative deltas
 * that are not multiples of 5 (and 0.2 is not exact in binary anyway); the
 * EXE's truncating form is authoritative.
 * C (round 2): the deltas taken once (interp of a copy of the ship was the C++'s form) */

/* the collision probe (level_is_inside_tile_128) depends on z only through z's row (a
 * negative z: no row, never inside): the z walk asks for the same row again and again */
typedef struct {
    const Level *level;
    int32_t x, y;
    int32_t row;                /* the row last asked for (-2: none) */
    bool inside;
} ZProbe;

static bool zprobe(ZProbe *p, int32_t z)
{
    const int32_t row = z < 0 ? -1 : (int32_t)((uint32_t)z >> 16);
    if (row != p->row) {
        p->row = row;
        p->inside = level_probe(p->level, p->x, p->y, z);
    }
    return p->inside;
}

/* C (round 2): move_to in 16-bit arithmetic, for the moves where every probe it makes lies
 * in level_probe16's range: both ends' x in 6272..57855 and y in -20000..32767 (every point
 * probed lies between the ends), z >= 0 moving forward by at most 65,535. The steps:
 *  - interp: trunc(d * k / 5) of a delta d = +-m is +-(a * k + floor(b * k / 5)) with m = 5a + b
 *    (FIFTH[b][k]), a * k kept as a running sum: one divide by 5 an axis;
 *  - the z walk in strides as move_to's, the probe asked by row;
 *  - the x and y walks on 16-bit positions (a position stays between its ends).
 * false: not in that range, move_to's own way. (host test simcheck) */
static const uint8_t FIFTH[5][6] = {
    {0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 0, 1}, {0, 0, 0, 1, 1, 2}, {0, 0, 1, 1, 2, 3}, {0, 0, 1, 2, 3, 4},
};
static const uint16_t WALK[4] = {0x7D, 25, 5, 1};
static const int32_t ZGRAN[4] = {0x1000, 0x100, 0x10, 1};

bool gameplay_move16_c(Ship *s, const Ship *dest, const Level *level)
{
    const int32_t X0 = s->x_position_128, Y0 = s->y_position_128, Z0 = s->z_position_fp16;
    const int32_t X1 = dest->x_position_128, Y1 = dest->y_position_128, Z1 = dest->z_position_fp16;
    uint16_t x, y, mx, my, mz, ax, ay, az, accx = 0, accy = 0, accz = 0, qx, qy, qz, tx, ty;
    unsigned bx, by, bz, k, iter = 6, zrow, memo_row;
    bool nx, ny, memo = false;
    int32_t z;

    if (X0 < 6272 || X0 > 57855 || X1 < 6272 || X1 > 57855 || Y0 < -20000 || Y0 > 32767 ||
        Y1 < -20000 || Y1 > 32767 || Z0 < 0 || Z1 < Z0 || Z1 - Z0 > 0xFFFF)
        return false;
    x = (uint16_t)X0;
    y = (uint16_t)(int16_t)Y0;          /* (y as its 16-bit pattern: sums wrap back exactly) */
    tx = (uint16_t)X1;
    ty = (uint16_t)(int16_t)Y1;
    nx = X1 < X0;
    ny = Y1 < Y0;
    mx = nx ? x - tx : tx - x;
    my = ny ? y - ty : ty - y;
    mz = (uint16_t)(Z1 - Z0);
    ax = mx / 5u;
    bx = mx - ax * 5u;
    ay = my / 5u;
    by = my - ay * 5u;
    az = mz / 5u;
    bz = mz - az * 5u;
    for (k = 1; k <= 5; ++k) {
        accx += ax;
        accy += ay;
        accz += az;
        qx = accx + FIFTH[bx][k];
        qy = accy + FIFTH[by][k];
        qz = accz + FIFTH[bz][k];
        if (level_probe16(level, nx ? x - qx : x + qx, (int)(int16_t)(ny ? y - qy : y + qy),
                          (unsigned)(((uint32_t)Z0 + qz) >> 16))) {
            iter = k;
            accx -= ax;
            accy -= ay;
            accz -= az;
            break;
        }
    }
    z = Z0;
    if (iter > 1) {
        k = iter - 1;
        qx = accx + FIFTH[bx][k];
        qy = accy + FIFTH[by][k];
        qz = accz + FIFTH[bz][k];
        x = nx ? x - qx : x + qx;
        y = ny ? y - qy : y + qy;
        z += qz;
    }

    /* the z walk (move_to's), by row */
    memo_row = 0xFFFF;
    for (k = 0; k < 4; ++k) {
        const int32_t gran = ZGRAN[k];
        while (Z1 - z >= gran) {
            const int32_t nz = z + gran;
            const unsigned row = (unsigned)((uint32_t)nz >> 16);
            int32_t limit;
            if (row != memo_row) {
                memo_row = row;
                memo = level_probe16(level, x, (int)(int16_t)y, row);
            }
            if (memo)
                break;
            limit = nz | 0xFFFF;
            if (Z1 < limit)
                limit = Z1;
            z += (limit - z) & -gran;   /* (whole strides: limit - z >= gran > 0) */
        }
    }
    zrow = (unsigned)((uint32_t)z >> 16);

    /* the x and y walks */
    if (tx != x) {
        const bool up = !nx;
        for (k = 0; k < 4; ++k) {
            const uint16_t g = WALK[k];
            if (up)
                while ((uint16_t)(tx - x) >= g && !level_probe16(level, x + g, (int)(int16_t)y, zrow))
                    x += g;
            else
                while ((uint16_t)(x - tx) >= g && !level_probe16(level, x - g, (int)(int16_t)y, zrow))
                    x -= g;
        }
    }
    if (ty != y) {
        const bool up = !ny;
        for (k = 0; k < 4; ++k) {
            const uint16_t g = WALK[k];
            if (up)
                while ((uint16_t)(ty - y) >= g && !level_probe16(level, x, (int)(int16_t)(y + g), zrow))
                    y += g;
            else
                while ((uint16_t)(y - ty) >= g && !level_probe16(level, x, (int)(int16_t)(y - g), zrow))
                    y -= g;
        }
    }
    s->x_position_128 = (int32_t)x;
    s->y_position_128 = (int32_t)(int16_t)y;
    s->z_position_fp16 = z;
    return true;
}

bool (*gameplay_move16)(Ship *s, const Ship *dest, const Level *level) = gameplay_move16_c;

/* the first i of 1..14 where the probe at (x + i * step, y, zrow) is not inside, 0 if none
 * (every x probed in 6272..57855) */
unsigned gameplay_scan16_c(const Level *level, uint16_t x, int y, unsigned zrow, int step)
{
    unsigned i;
    for (i = 1; i <= 0xE; ++i) {
        x += (uint16_t)step;
        if (!level_probe16(level, x, y, zrow))
            return i;
    }
    return 0;
}

unsigned (*gameplay_scan16)(const Level *level, uint16_t x, int y, unsigned zrow, int step) =
    gameplay_scan16_c;

static void move_to(Ship *s, const Ship *dest, const Level *level)
{
    int32_t dx, dy, dz, x_gran, y_gran;
    unsigned step, iter = 6, k;
    ZProbe zp;
    static const int16_t GRANS[4] = {0x7D, 25, 5, 1};   /* 0x7D, then / 5 truncated */

    if (s->x_position_128 == dest->x_position_128 &&
        s->y_position_128 == dest->y_position_128 &&
        s->z_position_fp16 == dest->z_position_fp16)
        return;
    if (gameplay_move16(s, dest, level)) {
        COVER(move16);
        return;
    }
    COVER(move32);

    dx = dest->x_position_128 - s->x_position_128;
    dy = dest->y_position_128 - s->y_position_128;
    dz = dest->z_position_fp16 - s->z_position_fp16;
    for (step = 1; step <= 5; ++step) {
        if (level_probe(level, s->x_position_128 + fifths(dx, step),
                                     s->y_position_128 + fifths(dy, step),
                                     s->z_position_fp16 + fifths(dz, step))) {
            iter = step;
            break;
        }
    }
    if (iter > 1) {
        s->x_position_128 += fifths(dx, iter - 1);
        s->y_position_128 += fifths(dy, iter - 1);
        s->z_position_fp16 += fifths(dz, iter - 1);
    }

    /* @0x18d4-0x1956: z granularity walk, 0x1000 shrinking by /16 (floor; the
     * value stays non-negative, so the reference's floor32 was the same shift).
     * C (round 2): `while (dest - z >= gran && !inside(z + gran)) z += gran` in strides: the
     * probe answers the same for every z of a row, so the steps that stay in the row of
     * z + gran (and at most at dest) are taken at once; the next probe is the next row's. */
    zp.level = level;
    zp.x = s->x_position_128;
    zp.y = s->y_position_128;
    zp.row = -2;
    zp.inside = false;
    for (k = 12;; k -= 4) {
        const int32_t gran = (int32_t)1 << k;
        while (dest->z_position_fp16 - s->z_position_fp16 >= gran) {
            const int32_t nz = s->z_position_fp16 + gran;
            int32_t limit;
            COVER(zstride);
            if (zprobe(&zp, nz))
                break;
            limit = nz < 0 ? -1 : (nz | 0xFFFF);        /* the row's last z */
            if (dest->z_position_fp16 < limit)
                limit = dest->z_position_fp16;
            s->z_position_fp16 += ((limit - s->z_position_fp16) >> k) << k;
        }
        if (k == 0)
            break;
    }

    /* X/Y granularity walks: 0x7D shrinking by a truncating /5 (the
     * reference's s_floor(gran / 5.0 * 128.0) is exactly raw/5 truncated:
     * 125 -> 25 -> 5 -> 1 -> 0). */
    if (dest->x_position_128 != s->x_position_128) {
        const bool up = dest->x_position_128 > s->x_position_128;
        for (k = 0; k < 4; ++k) {
            x_gran = up ? GRANS[k] : -GRANS[k];
            while (abs32(dest->x_position_128 - s->x_position_128) >= GRANS[k] &&
                   !level_probe(level, s->x_position_128 + x_gran,
                                             s->y_position_128, s->z_position_fp16))
                s->x_position_128 += x_gran;
        }
    }

    if (dest->y_position_128 != s->y_position_128) {
        const bool up = dest->y_position_128 > s->y_position_128;
        for (k = 0; k < 4; ++k) {
            y_gran = up ? GRANS[k] : -GRANS[k];
            while (abs32(dest->y_position_128 - s->y_position_128) >= GRANS[k] &&
                   !level_probe(level, s->x_position_128,
                                             s->y_position_128 + y_gran, s->z_position_fp16))
                s->y_position_128 += y_gran;
        }
    }
}

/* (called when z differs from expected's) */
static void handle_bumps(Ship *s, Ship *expected, const Level *level, GameplayEvents *events)
{
    if (level_probe(level, s->x_position_128, s->y_position_128,
                                 expected->z_position_fp16)) {
        const int32_t bump_off = 0x3A0; /* @0x272f/@0x276c */
        if (!level_probe(level, s->x_position_128 - bump_off, s->y_position_128,
                                      expected->z_position_fp16)) {
            s->x_position_128 -= bump_off;
            expected->z_position_fp16 = s->z_position_fp16;
            push_event(events, GameplayEvent_ShipBumpedWall);
        } else if (!level_probe(level, s->x_position_128 + bump_off,
                                             s->y_position_128, expected->z_position_fp16)) {
            s->x_position_128 += bump_off;
            expected->z_position_fp16 = s->z_position_fp16;
            push_event(events, GameplayEvent_ShipBumpedWall);
        }
    }
}

/* C (round 2): the two scans of handle_bounce when y - 1 lies in the band 0x1E80 < y < 0x2800
 * where the probe is "inside unless the cells at x - 14 and x + 14 units are both empty"
 * (level_is_inside_tile_128_ref's first two tests). A cell at x_128 is the row's column
 * div46[(x_128 - 95 * 128) >> 7] when 0 <= x_128 - 95 * 128 < 65,536 (beyond 322 * 128 the
 * column is 7 or more: no cell), so whole units u = (x_128 - 1792 - 12160) >> 7 step by one
 * with i, the right cell's is u + 28; the row's cells' emptiness is Level.row_mask. */
#define EMPTY_COLLISION_MIN_Y_128 ((int32_t)0x1E80)
#define EMPTY_COLLISION_MAX_Y_128 ((int32_t)80 * 128)
extern uint8_t level_div46[512];

static bool band_inside(unsigned mask, int u)
{
    return ((unsigned)u < 512u && ((mask >> level_div46[u]) & 1u)) ||
           ((unsigned)(u + 28) < 512u && ((mask >> level_div46[u + 28]) & 1u));
}

static void bounce_scan_band(Ship *s, const Level *level)
{
    const int32_t z = s->z_position_fp16;
    const int32_t d = s->x_position_128 - (1792 + 95 * 128);
    unsigned mask = 0;
    int u0, i;
    if (z >= 0 && (uint32_t)z >> 16 < level->length)
        mask = level->row_mask[(unsigned)((uint32_t)z >> 16)];
    /* u0 = floor(d / 128), held in an int: beyond +-2000 every unit the scans reach (u0 - 14
     * .. u0 + 42) lies outside 0..511 either way */
    if (d < -2000L * 128)
        u0 = -2000;
    else if (d > 2000L * 128)
        u0 = 2000;
    else if (d >= 0)
        u0 = (int)(d >> 7);
    else
        u0 = -(int)((-d + 127) >> 7);
    for (i = 1; i <= 0xE; ++i)
        if (!band_inside(mask, u0 + i)) {
            s->sliding_accel += 1;
            s->offset_at_which_not_inside_tile = (int16_t)i;
            break;
        }
    for (i = 1; i <= 0xE; ++i)
        if (!band_inside(mask, u0 - i)) {
            s->sliding_accel -= 1;
            s->offset_at_which_not_inside_tile = (int16_t)i;
            break;
        }
}

static void handle_bounce(Ship *s, const Ship *expected, const Level *level)
{
    s->is_on_ground = false;
    if (s->y_velocity_128 < 0 && expected->y_position_128 != s->y_position_128) {
        int32_t i;
        s->z_velocity_fp16 += s->jump_o_master_velocity_delta_fp16;
        s->jump_o_master_velocity_delta_fp16 = 0;
        s->has_run_jump_o_master = false;
        s->jump_o_master_in_use = false;
        s->is_going_up = false;
        s->is_on_ground = true;
        s->sliding_accel = 0;

        /* @0x2958-0x29e9: probe x +/- i whole units at y - 1/128. */
        if (s->y_position_128 - 1 > EMPTY_COLLISION_MIN_Y_128 &&
            s->y_position_128 - 1 < EMPTY_COLLISION_MAX_Y_128) {
            COVER(bounce_band);
            bounce_scan_band(s, level);
        } else if (s->x_position_128 >= 6272 + 14 * 128 &&
                   s->x_position_128 <= 57855 - 14 * 128 && s->y_position_128 > -20000 &&
                   s->y_position_128 <= 32767 && s->z_position_fp16 >= 0) {
            /* (C, round 2: every point probed in level_probe16's range: gameplay_scan16) */
            const uint16_t x = (uint16_t)s->x_position_128;
            const int y = (int)s->y_position_128 - 1;
            const unsigned row = (unsigned)((uint32_t)s->z_position_fp16 >> 16);
            unsigned k;
            COVER(bounce_probes16);
            k = gameplay_scan16(level, x, y, row, 128);
            if (k) {
                s->sliding_accel += 1;
                s->offset_at_which_not_inside_tile = (int16_t)k;
            }
            k = gameplay_scan16(level, x, y, row, -128);
            if (k) {
                s->sliding_accel -= 1;
                s->offset_at_which_not_inside_tile = (int16_t)k;
            }
        } else {
            COVER(bounce_probes);
            for (i = 1; i <= 0xE; ++i) {
                if (!level_probe(level, s->x_position_128 + i * 128,
                                              s->y_position_128 - 1, s->z_position_fp16)) {
                    s->sliding_accel += 1;
                    s->offset_at_which_not_inside_tile = (int16_t)i;
                    break;
                }
            }

            for (i = 1; i <= 0xE; ++i) {
                if (!level_probe(level, s->x_position_128 - i * 128,
                                              s->y_position_128 - 1, s->z_position_fp16)) {
                    s->sliding_accel -= 1;
                    s->offset_at_which_not_inside_tile = (int16_t)i;
                    break;
                }
            }
        }

        if (s->sliding_accel != 0)
            s->slide_amount_128 += 0x11 * s->sliding_accel; /* @0x29f7 */
        else
            s->slide_amount_128 = 0;
    }
}

static bool is_on_nothing(const Level *level, int32_t x_pos_fp16, int32_t z_pos_fp16)
{
    CellRef cell = level_get_cell_fp16(level, x_pos_fp16, z_pos_fp16);
    return cell_is_empty(cell) || (cell->has_tile && cell->tile_effect == TouchEffect_Kill);
}

static bool will_land_on_tile(const Ship *self, ControllerState controls, const Ship *ship,
                              const Level *level)
{
    /* The EXE's landing predictor (@0x1c20-0x1d49). x runs at 16.16 precision
     * here: the reference accumulated the exact product x_movement_base *
     * x_rate * 128 (a multiple of 1/65536) without requantizing, and
     * x_128 * 512 == x_fp16 keeps that bit-exact. */
    int32_t x_fp16 = ship->x_position_128 * 512;
    int32_t y_128 = ship->y_position_128;
    int32_t z_fp16 = ship->z_position_fp16;
    const int32_t x_velocity_128 = ship->x_movement_base_128;
    int32_t y_velocity_l = ship->y_velocity_128;
    int32_t z_velocity_l = ship->z_velocity_fp16;
    const int32_t gravity_128 = level->gravity_acc_128;

    for (;;) {
        const int32_t current_x_fp16 = x_fp16;
        /* (the C++ read the slide of `this`, not of the ship copy: the same here) */
        const int32_t current_slide_128 = self->slide_amount_128;
        const int32_t current_z_fp16 = z_fp16;
        int32_t x_rate_fp16;

        y_velocity_l += gravity_128;
        z_fp16 += z_velocity_l;

        x_rate_fp16 = z_velocity_l + 0x618;
        x_fp16 += x_velocity_128 * x_rate_fp16 + current_slide_128 * 512;
        if (!in_range_inclusive(x_fp16, LEVEL_MIN_X_128 * 512, LEVEL_MAX_X_128 * 512))
            return false;

        y_128 += y_velocity_l;
        z_velocity_l = clamp_z_velocity(z_velocity_l + (int32_t)controls.accel_input * 0x4B);

        if (y_128 <= GROUND_Y_128)
            return !is_on_nothing(level, current_x_fp16, current_z_fp16) &&
                   !is_on_nothing(level, x_fp16, z_fp16);
    }
}

/* C (round 2): will_land_on_tile, faster and the same. Its loop runs until y comes down to
 * the road, and y does not depend on x or z: the number of steps is the same for the
 * start and every variant of run_jump_o_master (land_steps, once). Then a step is two
 * 32-bit additions and the range test; x's increment x_movement_base * (z_vel + 0x618) +
 * slide * 512 changes only with z_vel (a 16 x 16-bit multiply then). For an x movement
 * outside an int or a z velocity outside 0..0x2AAA, or more than LAND_MAX steps, the loop
 * above. (host test simcheck: random ships against the C++ port's ship_update) */
#define LAND_MAX 2000u
static unsigned land_steps(const Ship *ship, const Level *level)
{
    int32_t y = ship->y_position_128, yv = ship->y_velocity_128;
    const int32_t g = level->gravity_acc_128;
    unsigned n;
    for (n = 1; n <= LAND_MAX; ++n) {
        yv += g;
        y += yv;
        if (y <= GROUND_Y_128)
            return n;
    }
    return 0;
}

/* v * m for m <= 126 and a product that fits (shifts and adds, modulo 2^32) */
static int32_t times(int32_t v, unsigned m)
{
    uint32_t r = 0, u = (uint32_t)v;
    while (m) {
        if (m & 1)
            r += u;
        u <<= 1;
        m >>= 1;
    }
    return (int32_t)r;
}

static bool will_land(const Ship *s, ControllerState controls, const Level *level, unsigned n)
{
    int32_t x, z, cx, cz, inc;
    const int32_t xmb = s->x_movement_base_128, slide512 = s->slide_amount_128 * 512;
    const int a = (int)controls.accel_input * 0x4B;
    int zv;
    if (n == 0 || xmb < -32767 || xmb > 32767 || s->z_velocity_fp16 < 0 ||
        s->z_velocity_fp16 > 0x2AAA) {
        COVER(land_slow);
        return will_land_on_tile(s, controls, s, level);
    }
    COVER(land_fast);
    x = s->x_position_128 * 512;
    z = s->z_position_fp16;
    zv = (int)s->z_velocity_fp16;
    inc = (int32_t)(int)xmb * (zv + 0x618) + slide512;
    for (;;) {
        int nzv = zv + a;
        if (nzv < 0)
            nzv = 0;
        else if (nzv > 0x2AAA)
            nzv = 0x2AAA;
        if (nzv == zv && n <= 127 && inc >= -0xFFFFFFL && inc <= 0xFFFFFFL) {
            /* the rest of the way at one velocity: x moves by inc a step, so its first
             * and last steps are its extremes (no sum overflows: |inc| * 127 < 2^31) */
            const int32_t xl = x + times(inc, n - 1), x1 = x + inc, xn = xl + inc;
            COVER(land_closed);
            if (x1 < LEVEL_MIN_X_128 * 512 || x1 > LEVEL_MAX_X_128 * 512 ||
                xn < LEVEL_MIN_X_128 * 512 || xn > LEVEL_MAX_X_128 * 512)
                return false;
            cz = z + times(zv, n - 1);
            return !is_on_nothing(level, xl, cz) && !is_on_nothing(level, xn, cz + zv);
        }
        cx = x;
        cz = z;
        z += zv;
        x += inc;
        if (x < LEVEL_MIN_X_128 * 512 || x > LEVEL_MAX_X_128 * 512)
            return false;
        if (--n == 0)
            return !is_on_nothing(level, cx, cz) && !is_on_nothing(level, x, z);
        if (nzv != zv) {        /* (zv's clamp(zv + accel * 0x4B), from above) */
            /* inc = xmb * (zv + 0x618) + slide * 512 again: by xmb * 0x4B when the whole
             * accel step was taken (a multiply by the constant), else multiplied */
            if (nzv - zv == 0x4B)
                inc += (int32_t)(int)xmb * 0x4B;
            else if (nzv - zv == -0x4B)
                inc -= (int32_t)(int)xmb * 0x4B;
            else
                inc = (int32_t)(int)xmb * (nzv + 0x618) + slide512;
            zv = nzv;
        }
    }
}

static void run_jump_o_master(Ship *s, ControllerState controls, const Level *level)
{
    int32_t z_velocity_start, x_movement_base_start;
    int32_t xs_i = 0, zs_i = 0;     /* start * i, kept as i steps */
    unsigned i, n;
    bool small, smallz;
    bool success = false;

    n = land_steps(s, level);
    if (will_land(s, controls, level, n))
        return;

    z_velocity_start = s->z_velocity_fp16;
    x_movement_base_start = s->x_movement_base_128;
    /* (the variants' start * i / 10 with i <= 6 in 16 bits: an x start of |start| <= 5461,
     * a z start of 0..10922 unsigned; a 16-bit divide by 10 is inline) */
    small = x_movement_base_start >= -5461 && x_movement_base_start <= 5461;
    smallz = z_velocity_start >= 0 && z_velocity_start <= 10922;
    for (i = 1; i <= 6; ++i) {
        int32_t zv2, xd, zd;
        COVER(jom_variants);
        xs_i += x_movement_base_start;
        zs_i += z_velocity_start;
        xd = small ? (int32_t)((int)xs_i / 10) : x_movement_base_start * (int32_t)i / 10;
        zd = smallz ? (int32_t)((unsigned)zs_i / 10u) : z_velocity_start * (int32_t)i / 10;
        /* EXE (@0x1d9b-0x1dea): both x-movement variants are start +/-
         * (start * i) / 10 with idiv truncation. The double form floored the
         * sum instead, which differs for the negative (turning-left) base. */
        s->x_movement_base_128 = x_movement_base_start + xd;
        if (will_land(s, controls, level, n)) {
            success = true;
            break;
        }

        s->x_movement_base_128 = x_movement_base_start - xd;
        if (will_land(s, controls, level, n)) {
            success = true;
            break;
        }

        s->x_movement_base_128 = x_movement_base_start;

        /* @0x1e1c-0x1e42: same truncating scale for the z-velocity variants
         * (z_vel >= 0, so this matches the reference's floor32 exactly),
         * then the clamp; a clamped-away variant is skipped. */
        zv2 = z_velocity_start + zd;
        s->z_velocity_fp16 = clamp_z_velocity(zv2);
        if (s->z_velocity_fp16 == zv2 && will_land(s, controls, level, n)) {
            success = true;
            break;
        }

        zv2 = z_velocity_start - zd;
        s->z_velocity_fp16 = clamp_z_velocity(zv2);
        if (s->z_velocity_fp16 == zv2 && will_land(s, controls, level, n)) {
            success = true;
            break;
        }

        s->z_velocity_fp16 = z_velocity_start;
    }

    s->jump_o_master_velocity_delta_fp16 = z_velocity_start - s->z_velocity_fp16;
    if (success)
        s->jump_o_master_in_use = true;
}

/* C (round 2): the C++'s small steps (get_touch_effect, apply_touch_effect, update_*_velocity,
 * update_jump, update_jump_o_master, update_gravity, attempt_motion, handle_collision,
 * handle_slide_collision, handle_oxygen_and_fuel, handle_fall_below_ground) written out in
 * here, in their order: cc816 makes every call of a function (it inlines none), and the tick
 * made 25 of them. Each step is its function's code; host test simcheck runs the C++ port's
 * ship_update beside this one. */
#define PUSH_EVENT(ev) do { if (events->count < GAMEPLAY_MAX_EVENTS) \
        events->e[events->count++] = (uint8_t)(ev); } while (0)
#define CLAMP_ZV(s) do { if ((s)->z_velocity_fp16 < 0) (s)->z_velocity_fp16 = 0; \
        else if ((s)->z_velocity_fp16 > 0x2AAA) (s)->z_velocity_fp16 = 0x2AAA; } while (0)

/* oxygen and fuel's fuel_dec: ((0x7530 / fuel) * z_vel) >> 16 (see ship_update), kept from
 * the tick before: the velocity stays the same for long stretches */
static int32_t fuel_decrement(const Level *level, int32_t z_vel)
{
    static int32_t last_q = -2, last_zv, last_dec;
    if (level->fuel_q < 0)
        return 0x7530;
    if (level->fuel_q != last_q || z_vel != last_zv) {
        last_dec = z_vel >= 0 && z_vel <= 0xFFFF
                       ? (int32_t)(((uint32_t)(uint16_t)level->fuel_q * (uint16_t)z_vel) >> 16)
                       : (level->fuel_q * z_vel) >> 16;
        last_q = level->fuel_q;
        last_zv = z_vel;
    }
    return last_dec;
}

void ship_update(Ship *s, const Level *level, Ship *expected, ControllerState controls,
                 GameplayEvents *events)
{
    /* The reference re-quantized ("sanitized") its doubles here and after every
     * motion step; integer fields are on-grid by construction, so the only
     * surviving quantization is the explicit round in attempt_motion. */
    const bool can_control = s->state == ShipState_Alive;
    CellRef cell = level_get_cell_128(level, s->x_position_128, s->z_position_fp16);
    const bool is_above_nothing = !cell->has_tunnel && !cell->has_tile && !cell->has_cube_height;
    TouchEffect touch_effect = TouchEffect_None;
    int32_t d;

    /* get_touch_effect */
    if (s->is_on_ground) {
        const int32_t y_units = s->y_position_128 >> 7; /* floor(y); y >= 0 on ground */
        if (y_units == GROUND_Y_128 / 128 && cell->has_tile)
            touch_effect = (TouchEffect)cell->tile_effect;
        else if (y_units > GROUND_Y_128 / 128 && cell->has_cube_height &&
                 cell->cube_height == (uint16_t)y_units)
            touch_effect = (TouchEffect)cell->cube_effect;
    }

    events->count = 0;
    /* apply_touch_effect */
    switch (touch_effect) {
    case TouchEffect_Accelerate: /* @0x1b2f */
        s->z_velocity_fp16 += 0x12F;
        break;
    case TouchEffect_Decelerate: /* @0x1b17 */
        s->z_velocity_fp16 -= 0x12F;
        break;
    case TouchEffect_Kill:
        if (s->state != ShipState_Exploded)
            PUSH_EVENT(GameplayEvent_ShipExploded);
        s->state = ShipState_Exploded;
        break;
    case TouchEffect_RefillOxygen:
        if (s->state == ShipState_Alive) {
            if (s->fuel_remaining < 0x6978 || s->oxygen_remaining < 0x6978)
                PUSH_EVENT(GameplayEvent_ShipRefilled);
            s->fuel_remaining = 0x7530;
            s->oxygen_remaining = 0x7530;
        }
        break;
    case TouchEffect_Slide:
    case TouchEffect_None:
        break;
    }
    CLAMP_ZV(s);

    /* update_y_velocity. The reference compares position deltas against 0.01 to separate
     * "really moved" from float fuzz. On the 1/128 grid the smallest nonzero |delta|
     * exceeding 0.01 is 2/128, exactly. */
    d = expected->y_position_128 - s->y_position_128;
    if (d >= 2 || d <= -2) {
        if (s->slide_amount_128 == 0 || s->offset_at_which_not_inside_tile >= 2) {
            /* EXE (@0x243c-0x244d): the bounce threshold is the INTEGER
             * quotient (0x104 * gravity) / 8, and the comparison is |y_vel| >=
             * threshold ("jae"). The double form compared against the unfloored
             * gravity * 0x104 / 8.0 with a strict >, which differs only when
             * |y_vel| lands exactly on the (floored) threshold. */
            const int32_t threshold = (0x104 * (int32_t)level->gravity) >> 3; /* (>= 0) */
            if (abs32(s->y_velocity_128) >= threshold) {
                if (s->y_velocity_128 < 0)
                    PUSH_EVENT(GameplayEvent_ShipBounced);
                /* EXE (@0x2485): bounce = -(y_vel_raw * 5) / 10 on the raw
                 * 1/128 fixed-point value, with integer truncation -- not float
                 * -0.5*v. */
                s->y_velocity_128 = bounce_velocity(s->y_velocity_128);
            } else {
                s->y_velocity_128 = 0;
            }
        } else {
            s->y_velocity_128 = 0;
        }
    }

    /* update_z_velocity. @0x24a8-0x24bd: z_vel += accel * 0x4B, then the 0..0x2AAA clamp. */
    if (can_control)
        s->z_velocity_fp16 += (int32_t)controls.accel_input * 0x4B;
    CLAMP_ZV(s);

    /* update_x_velocity */
    if (touch_effect != TouchEffect_Slide) {
        const bool can_control_1 =
            (s->is_going_up || is_above_nothing) && s->x_movement_base_128 == 0 &&
            s->y_velocity_128 > 0 &&
            (s->y_position_128 - s->jumped_from_y_position_128) < 30 * 128; /* @0x2544 */
        const bool can_control_2 = !s->is_going_up && !is_above_nothing;
        if (can_control_1 || can_control_2)
            s->x_movement_base_128 = can_control ? (int32_t)controls.turn_input * 0x1D : 0;
    }

    /* update_jump */
    if (!s->is_going_up && !is_above_nothing && controls.jump_input && level->gravity < 0x14 &&
        can_control) {
        s->y_velocity_128 = 0x480; /* @0x257a */
        s->is_going_up = true;
        s->jumped_from_y_position_128 = s->y_position_128;
    }

    /* update_jump_o_master */
    if (s->is_going_up && !s->has_run_jump_o_master &&
        s->y_position_128 >= 110 * 128) { /* @0x25ac: 0x3700 */
        run_jump_o_master(s, controls, level);
        s->has_run_jump_o_master = true;
    }

    /* update_gravity. EXE (@0x25c9): threshold is y >= 0x2800 (raw) = GROUND_Y (80.0); the
     * port had 0x28 (40.0), a dropped-digit transcription. Terminal fall velocity is
     * -106 (0xff96), not -105. The gravity acceleration is integer raw 1/128
     * already, so the reference's post-add s_floor was a no-op and is gone. */
    if (s->y_position_128 >= GROUND_Y_128)
        s->y_velocity_128 += level->gravity_acc_128;
    else if (s->y_velocity_128 > -106)
        s->y_velocity_128 = -106;

    *expected = *s;
    /* attempt_motion (on expected) */
    {
        int32_t motion_vel = expected->z_velocity_fp16;
        int32_t x_motion_512;
        if (touch_effect != TouchEffect_Decelerate)
            motion_vel += 0x618; /* @0x2646 */
        /* @0x265a-0x2681: expected_x = x + (x_movement_base * motion_vel) / 0x200
         * + slide. The divide helper @0x5e1c takes the absolute value of both
         * operands, does an unsigned div and re-applies the sign, i.e. it TRUNCATES
         * toward zero. C++ integer division does the same, so this is a plain /.
         * (C, round 2: the turn's base is 0 or +-0x1D unless the jump-o-master scaled it:
         * a multiply by the constant, inline, for those) */
        if (expected->x_movement_base_128 == 0)
            x_motion_512 = 0;
        else if (expected->x_movement_base_128 == 0x1D)
            x_motion_512 = motion_vel * 0x1D;
        else if (expected->x_movement_base_128 == -0x1D)
            x_motion_512 = motion_vel * -0x1D;
        else
            x_motion_512 = expected->x_movement_base_128 * motion_vel;
        expected->x_position_128 += expected->slide_amount_128 + SDIV_POW2(x_motion_512, 9);
        /* Motion keeps being integrated after death: the EXE's motion integrator
         * (@0x1900..0x1a9b) has no death-code gate, which is what lets a ship that
         * fell off the road keep dropping out of view. Only the *inputs* are cut
         * (can_control), so x_movement_base decays to 0 on its own. */
        expected->y_position_128 += expected->y_velocity_128;
        expected->z_position_fp16 += expected->z_velocity_fp16;
    }
    move_to(s, expected, level);
    if (s->z_position_fp16 != expected->z_position_fp16)
        handle_bumps(s, expected, level, events);

    /* handle_collision */
    d = s->z_position_fp16 - expected->z_position_fp16;
    if (d >= 656 || d <= -656) {
        /* EXE (@0x27ae): survivable if z_vel < 0xE38 -- the raw third of
         * 0x2AAA, already truncated. The double (1/3) * 0x2AAA/65536 landed a
         * whisker above it, so only an exact z_vel of 0xE38 decides
         * differently (the EXE explodes; the double form bumped). */
        if (s->z_velocity_fp16 < 0xE38) {
            s->z_velocity_fp16 = 0;
            PUSH_EVENT(GameplayEvent_ShipBumpedWall);
        } else if (s->state != ShipState_Exploded) {
            s->state = ShipState_Exploded;
            PUSH_EVENT(GameplayEvent_ShipExploded);
        }
    }

    /* handle_slide_collision */
    d = s->x_position_128 - expected->x_position_128;
    if (d >= 2 || d <= -2) {
        s->x_movement_base_128 = 0;
        if (s->slide_amount_128 != 0) {
            expected->x_position_128 = s->x_position_128;
            s->slide_amount_128 = 0;
        }
        s->z_velocity_fp16 -= 0x97; /* @0x2862 */
        CLAMP_ZV(s);
    }

    handle_bounce(s, expected, level);

    /* handle_oxygen_and_fuel. Oxygen burns on TIME (a fixed slice of the tank every tick)
     * and fuel burns on DISTANCE (proportional to forward speed), so a stationary ship
     * still suffocates but uses no fuel. Both are pure 16-bit integer math in
     * the EXE (@0x2a23-0x2a85): the per-tick decrements are the truncated
     * quotients below, and the "went past empty" test is an unsigned-underflow
     * clamp. The double form kept fractional tanks; the integer one drains
     * oxygen slightly slower (e.g. 13 vs 13.888../tick on the demo road) and
     * does not drain fuel at all until z_vel reaches 0x10000 / (0x7530 /
     * level.fuel) raw -- both exactly as the original.
     * (C, round 2: the level's quotients taken once: Level.oxygen_dec and .fuel_q) */
    s->oxygen_remaining -= level->oxygen_dec;
    if (s->oxygen_remaining <= 0)
        s->oxygen_remaining = 0;

    s->fuel_remaining -= fuel_decrement(level, s->z_velocity_fp16);
    if (s->fuel_remaining <= 0)
        s->fuel_remaining = 0;

    /* The EXE assigns the outcome unconditionally in the order fuel then oxygen
     * (@0x2ab0, @0x2ac0), so when both empty on the same tick OXYGEN is the one
     * that sticks. Keep that order; it decides which dashboard label flashes. */
    if (s->fuel_remaining <= 0)
        s->state = ShipState_OutOfFuel;
    if (s->oxygen_remaining <= 0)
        s->state = ShipState_OutOfOxygen;

    /* handle_fall_below_ground. @0x2a95-0x2aa0, in full:  if (y < 0x2800) outcome = 3.
     *
     * That is the WHOLE of it. Nothing is zeroed, nothing is clamped. The port
     * used to also null y_velocity, z_velocity, x_movement_base, the slide and
     * the jump-o-master delta, and pin y to the road -- so the moment you went
     * over an edge the world froze and the ship dropped straight down on the
     * spot. In the original you keep every bit of the speed you had: z carries
     * you on past the end of the road while update_gravity, seeing y below the
     * road, pins the fall to terminal velocity (-106). That is the long,
     * committed plunge away from the camera, and it is what makes falling read
     * as falling rather than as the game stopping. */
    if (s->state == ShipState_Alive && s->y_position_128 < GROUND_Y_128)
        s->state = ShipState_Fallen;
}

void gameplay_session_init(GameplaySession *g, const Level *level)
{
    /* (C, round 2: the level's cells are made the first time it is played) */
    if (!level->built)
        level_build((Level *)level);
    g->level = level;
    ship_init(&g->ship);
    g->expected_ship = g->ship;
    g->did_win = false;
    g->last_controls = controller_neutral();
    g->has_death_frame_index = false;
    g->death_frame_index = 0;
    g->frame_index_ = 0;
}

bool gameplay_death_animation_finished(const GameplaySession *g)
{
    unsigned elapsed, needed;
    if (g->ship.state == ShipState_Alive)
        return false;
    /* Dead but the death tick has not been stamped yet: the animation has not even
     * started, so it certainly has not finished. */
    if (!g->has_death_frame_index)
        return false;
    elapsed = g->frame_index_ - g->death_frame_index;
    needed = OTHER_DEATH_TICKS;
    if (g->ship.state == ShipState_Exploded)
        needed = EXPLOSION_DEATH_TICKS;
    else if (g->ship.state == ShipState_Fallen)
        needed = FALL_DEATH_TICKS;
    return elapsed >= needed;
}

void gameplay_step(GameplaySession *g, ControllerState controls, GameplayEvents *events)
{
    g->last_controls = controls;
    ship_update(&g->ship, g->level, &g->expected_ship, controls, events);
    /* Stamp the tick the ship died on, which drives the death animation. Keyed on
     * "dead and not yet stamped" rather than on the Alive->dead edge so that a
     * session seeded into a dead state still animates. */
    if (g->ship.state != ShipState_Alive && !g->has_death_frame_index) {
        g->has_death_frame_index = true;
        g->death_frame_index = g->frame_index_;
    }
    if (g->ship.z_position_fp16 >= (int32_t)g->level->length * 65536 - 32768 &&
        level_is_inside_tunnel_128(g->level, g->ship.x_position_128, g->ship.y_position_128,
                                   g->ship.z_position_fp16))
        g->did_win = true;
    g->frame_index_ += 1;
}

void gameplay_run_frame(GameplaySession *g, ControllerState controls, GameplayFrameResult *result)
{
    int32_t row;
    gameplay_step(g, controls, &result->events);
    result->frame_index = g->frame_index_ - 1;
    result->controls = controls;
    /* The one place per tick doubles appear: the render/HUD snapshot. (C: raw.) */
    result->snapshot.x_position_128 = g->ship.x_position_128;
    result->snapshot.y_position_128 = g->ship.y_position_128;
    result->snapshot.z_position_fp16 = g->ship.z_position_fp16;
    result->snapshot.z_velocity_fp16 =
        g->ship.z_velocity_fp16 + g->ship.jump_o_master_velocity_delta_fp16;
    result->snapshot.craft_state = g->ship.state;
    result->snapshot.oxygen_remaining = g->ship.oxygen_remaining;
    result->snapshot.fuel_remaining = g->ship.fuel_remaining;
    result->snapshot.jump_o_master_in_use = g->ship.jump_o_master_in_use;
    result->snapshot.jump_o_master_velocity_delta_fp16 =
        g->ship.jump_o_master_velocity_delta_fp16;
    result->did_win = g->did_win;
    row = g->ship.z_position_fp16 >> 16;
    result->road_row_index = (unsigned)(row > 0 ? row : 0);
}

void gameplay_run_demo_frame(GameplaySession *g, const DemoRecording *demo,
                             GameplayFrameResult *out)
{
    gameplay_run_frame(g, controller_state_from_demo_input(sample_demo_input_for_ship(demo, &g->ship)),
                       out);
}

const DemoInput SR_FAR *sample_demo_input_for_ship(const DemoRecording *demo, const Ship *ship)
{
    /* One demo entry per 0x666 of raw z (the planner's
     * DEMO_TILE_POSITION_STEP_FP16); a plain truncating division, where the
     * double form multiplied by the inexact 65536.0 / 0x666. */
    /* C (round 2): the index of z's stretch kept from the call before (z moves less than a
     * stretch a tick): the 32-bit divide only after a jump; the same quotient */
    static uint32_t lo = 0, index = 0;     /* lo = index * 0x666 */
    uint32_t z;
    if (ship->z_position_fp16 < 0)
        return 0;
    z = (uint32_t)ship->z_position_fp16;
    if (z < lo || z - lo >= 16u * 0x666u) {
        index = z / 0x666;
        lo = index * 0x666;
    } else {
        const unsigned q = (unsigned)(z - lo) / 0x666u;     /* (16 bits: inline) */
        index += q;
        lo += (uint32_t)(q * 0x666u);
    }
    if (index >= demo->entry_count)
        return 0;
    return &demo->entries[(unsigned)index];
}

ControllerState controller_state_from_demo_input(const DemoInput SR_FAR *input)
{
    if (input == 0)
        return controller_neutral();
    return controller_make(input->left_right, input->accelerate_decelerate, input->jump);
}
