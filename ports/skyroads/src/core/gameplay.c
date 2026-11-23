#include <assert.h>

#include "core/gameplay.h"

static int32_t abs32(int32_t v) { return v < 0 ? -v : v; }

/* C: divisions of the tick in forms the 65816 does quickly, each exactly C's division
 * (truncating toward zero): cc816 makes every 32-bit divide a call of about 1,000 cycles,
 * also by 16 or 512, and a 16-bit one by a constant too (PORTING-NOTES: SDK wishes). */
/* v / 2^k */
#define SDIV_POW2(v, k) ((v) >= 0 ? (v) >> (k) : -((-(v)) >> (k)))
/* v / d with v and d small enough for 16 bits: the 16-bit divide */
static int32_t sdiv_small(int32_t v, int d)
{
    if (v >= -32767 && v <= 32767)
        return (int32_t)((int)v / d);
    return v / d;
}

/* The reference compares position deltas against 0.01 to separate "really
 * moved" from float fuzz. On the 1/128 grid the smallest nonzero |delta|
 * exceeding 0.01 is 2/128, exactly. */
static bool differs_by_more_than_hundredth_128(int32_t a_128, int32_t b_128)
{
    return abs32(a_128 - b_128) >= 2;
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

static void clamp_global_z_velocity(Ship *s)
{
    s->z_velocity_fp16 = clamp_z_velocity(s->z_velocity_fp16);
}

static bool is_different_height(const Ship *s, const Ship *other)
{
    return differs_by_more_than_hundredth_128(other->y_position_128, s->y_position_128);
}

static TouchEffect get_touch_effect(const Ship *s, CellRef cell)
{
    int32_t y_units;
    if (!s->is_on_ground)
        return TouchEffect_None;
    y_units = s->y_position_128 >> 7; /* floor(y); y >= 0 on ground */
    if (y_units == GROUND_Y_128 / 128 && cell->has_tile)
        return (TouchEffect)cell->tile_effect;
    if (y_units > GROUND_Y_128 / 128 && cell->has_cube_height &&
        cell->cube_height == (uint16_t)y_units)
        return (TouchEffect)cell->cube_effect;
    return TouchEffect_None;
}

static void apply_touch_effect(Ship *s, TouchEffect effect, GameplayEvents *events)
{
    switch (effect) {
    case TouchEffect_Accelerate: /* @0x1b2f */
        s->z_velocity_fp16 += 0x12F;
        break;
    case TouchEffect_Decelerate: /* @0x1b17 */
        s->z_velocity_fp16 -= 0x12F;
        break;
    case TouchEffect_Kill:
        if (s->state != ShipState_Exploded)
            push_event(events, GameplayEvent_ShipExploded);
        s->state = ShipState_Exploded;
        break;
    case TouchEffect_RefillOxygen:
        if (s->state == ShipState_Alive) {
            if (s->fuel_remaining < 0x6978 || s->oxygen_remaining < 0x6978)
                push_event(events, GameplayEvent_ShipRefilled);
            s->fuel_remaining = 0x7530;
            s->oxygen_remaining = 0x7530;
        }
        break;
    case TouchEffect_Slide:
    case TouchEffect_None:
        break;
    }
    clamp_global_z_velocity(s);
}

static void update_y_velocity(Ship *s, const Ship *expected, const Level *level,
                              GameplayEvents *events)
{
    if (is_different_height(s, expected)) {
        if (s->slide_amount_128 == 0 || s->offset_at_which_not_inside_tile >= 2) {
            /* EXE (@0x243c-0x244d): the bounce threshold is the INTEGER
             * quotient (0x104 * gravity) / 8, and the comparison is |y_vel| >=
             * threshold ("jae"). The double form compared against the unfloored
             * gravity * 0x104 / 8.0 with a strict >, which differs only when
             * |y_vel| lands exactly on the (floored) threshold. */
            const int32_t threshold = (0x104 * (int32_t)level->gravity) >> 3; /* (>= 0) */
            if (abs32(s->y_velocity_128) >= threshold) {
                if (s->y_velocity_128 < 0)
                    push_event(events, GameplayEvent_ShipBounced);
                /* EXE (@0x2485): bounce = -(y_vel_raw * 5) / 10 on the raw
                 * 1/128 fixed-point value, with integer truncation -- not float
                 * -0.5*v. */
                s->y_velocity_128 = sdiv_small(-(s->y_velocity_128 * 5), 10);
            } else {
                s->y_velocity_128 = 0;
            }
        } else {
            s->y_velocity_128 = 0;
        }
    }
}

static void update_z_velocity(Ship *s, bool can_control, int8_t accel_input)
{
    /* @0x24a8-0x24bd: z_vel += accel * 0x4B, then the 0..0x2AAA clamp. */
    s->z_velocity_fp16 += (can_control ? (int32_t)accel_input : 0) * 0x4B;
    clamp_global_z_velocity(s);
}

static void update_x_velocity(Ship *s, bool can_control, int8_t turn_input,
                              bool is_on_sliding_tile, bool is_above_nothing)
{
    if (!is_on_sliding_tile) {
        const bool can_control_1 =
            (s->is_going_up || is_above_nothing) && s->x_movement_base_128 == 0 &&
            s->y_velocity_128 > 0 &&
            (s->y_position_128 - s->jumped_from_y_position_128) < 30 * 128; /* @0x2544 */
        const bool can_control_2 = !s->is_going_up && !is_above_nothing;
        if (can_control_1 || can_control_2)
            s->x_movement_base_128 = can_control ? (int32_t)turn_input * 0x1D : 0;
    }
}

static void run_jump_o_master(Ship *s, ControllerState controls, const Level *level);

static void update_jump(Ship *s, bool can_control, bool is_above_nothing, bool jump_input,
                        const Level *level)
{
    if (!s->is_going_up && !is_above_nothing && jump_input && level->gravity < 0x14 &&
        can_control) {
        s->y_velocity_128 = 0x480; /* @0x257a */
        s->is_going_up = true;
        s->jumped_from_y_position_128 = s->y_position_128;
    }
}

static void update_jump_o_master(Ship *s, ControllerState controls, const Level *level)
{
    if (s->is_going_up && !s->has_run_jump_o_master &&
        s->y_position_128 >= 110 * 128) { /* @0x25ac: 0x3700 */
        run_jump_o_master(s, controls, level);
        s->has_run_jump_o_master = true;
    }
}

static void update_gravity(Ship *s, int32_t gravity_acceleration_128)
{
    /* EXE (@0x25c9): threshold is y >= 0x2800 (raw) = GROUND_Y (80.0); the port
     * had 0x28 (40.0), a dropped-digit transcription. Terminal fall velocity is
     * -106 (0xff96), not -105. The gravity acceleration is integer raw 1/128
     * already, so the reference's post-add s_floor was a no-op and is gone. */
    if (s->y_position_128 >= GROUND_Y_128)
        s->y_velocity_128 += gravity_acceleration_128;
    else if (s->y_velocity_128 > -106)
        s->y_velocity_128 = -106;
}

static void attempt_motion(Ship *s, bool on_decel_pad)
{
    int32_t motion_vel = s->z_velocity_fp16;
    int32_t x_motion_512;
    if (!on_decel_pad)
        motion_vel += 0x618; /* @0x2646 */
    /* @0x265a-0x2681: expected_x = x + (x_movement_base * motion_vel) / 0x200
     * + slide. The divide helper @0x5e1c takes the absolute value of both
     * operands, does an unsigned div and re-applies the sign, i.e. it TRUNCATES
     * toward zero. C++ integer division does the same, so this is a plain /. */
    x_motion_512 = s->x_movement_base_128 * motion_vel;
    s->x_position_128 += s->slide_amount_128 + SDIV_POW2(x_motion_512, 9);
    /* Motion keeps being integrated after death: the EXE's motion integrator
     * (@0x1900..0x1a9b) has no death-code gate, which is what lets a ship that
     * fell off the road keep dropping out of view. Only the *inputs* are cut
     * (can_control), so x_movement_base decays to 0 on its own. */
    s->y_position_128 += s->y_velocity_128;
    s->z_position_fp16 += s->z_velocity_fp16;
}

/* EXE (@0x17fd-0x18d0): each substep position is pos + (delta * fifths) / 5
 * per axis, with the idiv/ldiv truncation toward zero. The double form floored
 * `pos + delta * (fifths / 5.0)` instead, which differs for negative deltas
 * that are not multiples of 5 (and 0.2 is not exact in binary anyway); the
 * EXE's truncating form is authoritative. */
static void interp(Ship *s, const Ship *dest, int32_t fifths)
{
    s->x_position_128 += sdiv_small((dest->x_position_128 - s->x_position_128) * fifths, 5);
    s->y_position_128 += sdiv_small((dest->y_position_128 - s->y_position_128) * fifths, 5);
    s->z_position_fp16 += sdiv_small((dest->z_position_fp16 - s->z_position_fp16) * fifths, 5);
}

static void move_to(Ship *s, const Ship *dest, const Level *level)
{
    Ship fake;
    int32_t iter = 1, step, z_gran, x_gran, y_gran;

    if (s->x_position_128 == dest->x_position_128 &&
        s->y_position_128 == dest->y_position_128 &&
        s->z_position_fp16 == dest->z_position_fp16)
        return;

    for (step = 1; step <= 5; ++step) {
        fake = *s;
        interp(&fake, dest, step);
        if (level_is_inside_tile_128(level, fake.x_position_128, fake.y_position_128,
                                     fake.z_position_fp16)) {
            iter = step;
            break;
        }
        iter = step + 1;
    }

    interp(s, dest, iter - 1);

    /* @0x18d4-0x1956: z granularity walk, 0x1000 shrinking by /16 (floor; the
     * value stays non-negative, so the reference's floor32 was the same shift). */
    z_gran = 0x1000;
    while (z_gran != 0) {
        if (dest->z_position_fp16 - s->z_position_fp16 >= z_gran &&
            !level_is_inside_tile_128(level, s->x_position_128, s->y_position_128,
                                      s->z_position_fp16 + z_gran))
            s->z_position_fp16 += z_gran;
        else
            z_gran >>= 4; /* (z_gran >= 0: / 16) */
    }

    /* X/Y granularity walks: 0x7D shrinking by a truncating /5 (the
     * reference's s_floor(gran / 5.0 * 128.0) is exactly raw/5 truncated:
     * 125 -> 25 -> 5 -> 1 -> 0). */
    x_gran = dest->x_position_128 > s->x_position_128 ? 0x7D : -0x7D;
    while (x_gran != 0) {
        if (abs32(dest->x_position_128 - s->x_position_128) >= abs32(x_gran) &&
            !level_is_inside_tile_128(level, s->x_position_128 + x_gran, s->y_position_128,
                                      s->z_position_fp16))
            s->x_position_128 += x_gran;
        else
            x_gran = sdiv_small(x_gran, 5);
    }

    y_gran = dest->y_position_128 > s->y_position_128 ? 0x7D : -0x7D;
    while (y_gran != 0) {
        if (abs32(dest->y_position_128 - s->y_position_128) >= abs32(y_gran) &&
            !level_is_inside_tile_128(level, s->x_position_128, s->y_position_128 + y_gran,
                                      s->z_position_fp16))
            s->y_position_128 += y_gran;
        else
            y_gran = sdiv_small(y_gran, 5);
    }
}

static void handle_bumps(Ship *s, Ship *expected, const Level *level, GameplayEvents *events)
{
    if (s->z_position_fp16 != expected->z_position_fp16 &&
        level_is_inside_tile_128(level, s->x_position_128, s->y_position_128,
                                 expected->z_position_fp16)) {
        const int32_t bump_off = 0x3A0; /* @0x272f/@0x276c */
        if (!level_is_inside_tile_128(level, s->x_position_128 - bump_off, s->y_position_128,
                                      expected->z_position_fp16)) {
            s->x_position_128 -= bump_off;
            expected->z_position_fp16 = s->z_position_fp16;
            push_event(events, GameplayEvent_ShipBumpedWall);
        } else if (!level_is_inside_tile_128(level, s->x_position_128 + bump_off,
                                             s->y_position_128, expected->z_position_fp16)) {
            s->x_position_128 += bump_off;
            expected->z_position_fp16 = s->z_position_fp16;
            push_event(events, GameplayEvent_ShipBumpedWall);
        }
    }
}

static void handle_collision(Ship *s, const Ship *expected, GameplayEvents *events)
{
    if (abs32(s->z_position_fp16 - expected->z_position_fp16) >= 656) {
        /* EXE (@0x27ae): survivable if z_vel < 0xE38 -- the raw third of
         * 0x2AAA, already truncated. The double (1/3) * 0x2AAA/65536 landed a
         * whisker above it, so only an exact z_vel of 0xE38 decides
         * differently (the EXE explodes; the double form bumped). */
        if (s->z_velocity_fp16 < 0xE38) {
            s->z_velocity_fp16 = 0;
            push_event(events, GameplayEvent_ShipBumpedWall);
        } else if (s->state != ShipState_Exploded) {
            s->state = ShipState_Exploded;
            push_event(events, GameplayEvent_ShipExploded);
        }
    }
}

static void handle_slide_collision(Ship *s, Ship *expected)
{
    if (differs_by_more_than_hundredth_128(s->x_position_128, expected->x_position_128)) {
        s->x_movement_base_128 = 0;
        if (s->slide_amount_128 != 0) {
            expected->x_position_128 = s->x_position_128;
            s->slide_amount_128 = 0;
        }
        s->z_velocity_fp16 -= 0x97; /* @0x2862 */
        clamp_global_z_velocity(s);
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
        for (i = 1; i <= 0xE; ++i) {
            if (!level_is_inside_tile_128(level, s->x_position_128 + i * 128,
                                          s->y_position_128 - 1, s->z_position_fp16)) {
                s->sliding_accel += 1;
                s->offset_at_which_not_inside_tile = (int16_t)i;
                break;
            }
        }

        for (i = 1; i <= 0xE; ++i) {
            if (!level_is_inside_tile_128(level, s->x_position_128 - i * 128,
                                          s->y_position_128 - 1, s->z_position_fp16)) {
                s->sliding_accel -= 1;
                s->offset_at_which_not_inside_tile = (int16_t)i;
                break;
            }
        }

        if (s->sliding_accel != 0)
            s->slide_amount_128 += 0x11 * s->sliding_accel; /* @0x29f7 */
        else
            s->slide_amount_128 = 0;
    }
}

static void handle_oxygen_and_fuel(Ship *s, const Level *level)
{
    /* Oxygen burns on TIME (a fixed slice of the tank every tick) and fuel
     * burns on DISTANCE (proportional to forward speed), so a stationary ship
     * still suffocates but uses no fuel. Both are pure 16-bit integer math in
     * the EXE (@0x2a23-0x2a85): the per-tick decrements are the truncated
     * quotients below, and the "went past empty" test is an unsigned-underflow
     * clamp. The double form kept fractional tanks; the integer one drains
     * oxygen slightly slower (e.g. 13 vs 13.888../tick on the demo road) and
     * does not drain fuel at all until z_vel reaches 0x10000 / (0x7530 /
     * level.fuel) raw -- both exactly as the original. */
    const int32_t oxygen_dec =
        level->oxygen > 0 ? 0x7530 / (0x24 * (int32_t)level->oxygen) : 0x7530;
    const int32_t fuel_dec =
        level->fuel > 0 ? ((0x7530 / (int32_t)level->fuel) * s->z_velocity_fp16) >> 16
                        : 0x7530;
    s->oxygen_remaining -= oxygen_dec;
    if (s->oxygen_remaining <= 0)
        s->oxygen_remaining = 0;

    s->fuel_remaining -= fuel_dec;
    if (s->fuel_remaining <= 0)
        s->fuel_remaining = 0;

    /* The EXE assigns the outcome unconditionally in the order fuel then oxygen
     * (@0x2ab0, @0x2ac0), so when both empty on the same tick OXYGEN is the one
     * that sticks. Keep that order; it decides which dashboard label flashes. */
    if (s->fuel_remaining <= 0)
        s->state = ShipState_OutOfFuel;
    if (s->oxygen_remaining <= 0)
        s->state = ShipState_OutOfOxygen;
}

static void handle_fall_below_ground(Ship *s)
{
    /* @0x2a95-0x2aa0, in full:  if (y < 0x2800) outcome = 3.
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
    const int32_t gravity_128 = level_gravity_acceleration_128(level);

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

static void run_jump_o_master(Ship *s, ControllerState controls, const Level *level)
{
    int32_t z_velocity_start, x_movement_base_start, i;
    bool success = false;

    if (will_land_on_tile(s, controls, s, level))
        return;

    z_velocity_start = s->z_velocity_fp16;
    x_movement_base_start = s->x_movement_base_128;
    for (i = 1; i <= 6; ++i) {
        int32_t zv2;
        /* EXE (@0x1d9b-0x1dea): both x-movement variants are start +/-
         * (start * i) / 10 with idiv truncation. The double form floored the
         * sum instead, which differs for the negative (turning-left) base. */
        s->x_movement_base_128 = x_movement_base_start + x_movement_base_start * i / 10;
        if (will_land_on_tile(s, controls, s, level)) {
            success = true;
            break;
        }

        s->x_movement_base_128 = x_movement_base_start - x_movement_base_start * i / 10;
        if (will_land_on_tile(s, controls, s, level)) {
            success = true;
            break;
        }

        s->x_movement_base_128 = x_movement_base_start;

        /* @0x1e1c-0x1e42: same truncating scale for the z-velocity variants
         * (z_vel >= 0, so this matches the reference's floor32 exactly),
         * then the clamp; a clamped-away variant is skipped. */
        zv2 = z_velocity_start + z_velocity_start * i / 10;
        s->z_velocity_fp16 = clamp_z_velocity(zv2);
        if (s->z_velocity_fp16 == zv2 && will_land_on_tile(s, controls, s, level)) {
            success = true;
            break;
        }

        zv2 = z_velocity_start - z_velocity_start * i / 10;
        s->z_velocity_fp16 = clamp_z_velocity(zv2);
        if (s->z_velocity_fp16 == zv2 && will_land_on_tile(s, controls, s, level)) {
            success = true;
            break;
        }

        s->z_velocity_fp16 = z_velocity_start;
    }

    s->jump_o_master_velocity_delta_fp16 = z_velocity_start - s->z_velocity_fp16;
    if (success)
        s->jump_o_master_in_use = true;
}

void ship_update(Ship *s, const Level *level, Ship *expected, ControllerState controls,
                 GameplayEvents *events)
{
    /* The reference re-quantized ("sanitized") its doubles here and after every
     * motion step; integer fields are on-grid by construction, so the only
     * surviving quantization is the explicit round in attempt_motion. */
    const bool can_control = s->state == ShipState_Alive;
    CellRef cell = level_get_cell_128(level, s->x_position_128, s->z_position_fp16);
    const bool is_above_nothing = cell_is_empty(cell);
    const TouchEffect touch_effect = get_touch_effect(s, cell);
    const bool is_on_sliding_tile = touch_effect == TouchEffect_Slide;
    const bool is_on_decel_pad = touch_effect == TouchEffect_Decelerate;

    events->count = 0;
    apply_touch_effect(s, touch_effect, events);
    update_y_velocity(s, expected, level, events);
    update_z_velocity(s, can_control, controls.accel_input);
    update_x_velocity(s, can_control, controls.turn_input, is_on_sliding_tile, is_above_nothing);
    update_jump(s, can_control, is_above_nothing, controls.jump_input, level);
    update_jump_o_master(s, controls, level);
    update_gravity(s, level_gravity_acceleration_128(level));

    *expected = *s;
    attempt_motion(expected, is_on_decel_pad);
    move_to(s, expected, level);
    handle_bumps(s, expected, level, events);
    handle_collision(s, expected, events);
    handle_slide_collision(s, expected);
    handle_bounce(s, expected, level);
    handle_oxygen_and_fuel(s, level);
    handle_fall_below_ground(s);
}

void gameplay_session_init(GameplaySession *g, const Level *level)
{
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

void gameplay_run_frame(GameplaySession *g, ControllerState controls, GameplayFrameResult *result)
{
    GameplayEvents events;
    int32_t row;
    g->last_controls = controls;
    ship_update(&g->ship, g->level, &g->expected_ship, controls, &events);
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

    result->frame_index = g->frame_index_;
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
    result->events = events;
    result->did_win = g->did_win;
    row = g->ship.z_position_fp16 >> 16;
    result->road_row_index = (unsigned)(row > 0 ? row : 0);
    g->frame_index_ += 1;
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
    uint32_t index;
    if (ship->z_position_fp16 < 0)
        return 0;
    index = (uint32_t)ship->z_position_fp16 / 0x666;
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
