/* The deterministic ship simulation, in the DOS EXE's own integer fixed-point:
 * x/y positions and velocities are 1/128 units ("_128" fields), z and the z
 * velocity are 16.16 ("_fp16" fields), fuel/oxygen are the EXE's 16-bit words.
 * The double-precision reference implementation this replaced emulated exactly
 * these quantities (every value it produced was a multiple of 1/128 or
 * 1/65536), so the integer form is bit-identical to it except at the few
 * decimal-division sites, which now use the EXE's own integer formulas (cited
 * by @0x address at each site). The target console has no FPU; the per-tick
 * path performs no float/double operation at all -- doubles appear only at the
 * render/snapshot boundary.
 *
 * C translation: Ship's methods are ship_*() functions taking the ship first; the
 * session holds a pointer to its Level (the C++ held a copy); the events of a step are
 * a small fixed array; GameSnapshot keeps the raw integers (the C++'s doubles were
 * these divided by 128, 65536 or 0x7530: whoever prints them divides). */
#ifndef CORE_GAMEPLAY_H
#define CORE_GAMEPLAY_H

#include "data/demo.h"
#include "data/level.h"

typedef struct {
    int8_t turn_input;
    int8_t accel_input;
    bool jump_input;
} ControllerState;

ControllerState controller_neutral(void);
/* Mirrors the reference's `ControllerState::new`, which asserts each axis is in -1..=1. */
ControllerState controller_make(int8_t turn_input, int8_t accel_input, bool jump_input);

typedef enum {
    ShipState_Alive,
    ShipState_Exploded,
    ShipState_Fallen,
    ShipState_OutOfFuel,
    ShipState_OutOfOxygen,
} ShipState;

typedef enum {
    GameplayEvent_ShipBumpedWall,
    GameplayEvent_ShipExploded,
    GameplayEvent_ShipBounced,
    GameplayEvent_ShipRefilled,
} GameplayEvent;

/* std::vector<GameplayEvent> (a step raises at most a handful) */
#define GAMEPLAY_MAX_EVENTS 8
typedef struct {
    uint8_t e[GAMEPLAY_MAX_EVENTS];
    unsigned count;
} GameplayEvents;

typedef struct {
    /* DOS globals, in their native units: _128 fields are 1/128 fixed point
     * (ds:0xaf2c x, ds:0xaf3c y, ds:0x9342 y velocity, ds:0x4576 x movement
     * base, ds:0x54a2 slide), _fp16 fields are 16.16 (ds:0x9628 z, ds:0x54b8
     * z velocity). Fuel/oxygen are the EXE's words (full tank 0x7530). */
    int32_t x_position_128;
    int32_t y_position_128;
    int32_t z_position_fp16;
    int32_t slide_amount_128;
    int16_t sliding_accel;
    int32_t x_movement_base_128;
    int32_t y_velocity_128;
    int32_t z_velocity_fp16;
    int32_t fuel_remaining;
    int32_t oxygen_remaining;
    int16_t offset_at_which_not_inside_tile;
    bool is_on_ground;
    bool is_going_up;
    bool has_run_jump_o_master;
    int32_t jump_o_master_velocity_delta_fp16;
    bool jump_o_master_in_use;
    int32_t jumped_from_y_position_128;
    uint8_t state;                      /* ShipState */
} Ship;

void ship_init(Ship *ship);
/* Advances one fixed step. `expected` is the DOS "expected" scratch ship,
 * carried across frames exactly as the reference does. Returns the events
 * raised this step, in order. */
void ship_update(Ship *ship, const Level *level, Ship *expected, ControllerState controls,
                 GameplayEvents *events);

/* the C++'s doubles, as their raw integers (see above) */
typedef struct {
    int32_t x_position_128;
    int32_t y_position_128;
    int32_t z_position_fp16;
    int32_t z_velocity_fp16;            /* z velocity + jump-o-master delta */
    uint8_t craft_state;
    int32_t oxygen_remaining;           /* oxygen_percent = this / 0x7530 */
    int32_t fuel_remaining;             /* fuel_percent = this / 0x7530 */
    bool jump_o_master_in_use;
    int32_t jump_o_master_velocity_delta_fp16;
} GameSnapshot;

typedef struct {
    unsigned frame_index;
    ControllerState controls;
    GameSnapshot snapshot;
    GameplayEvents events;
    bool did_win;
    unsigned road_row_index;
} GameplayFrameResult;

/* How long the game keeps simulating after the ship dies, so the death plays out
 * on screen (EXE @0x2200, re/NOTES.md Update 9). A crash runs the explosion
 * counter ds:0x4578 for 42 ticks (14 sprites x 3 ticks each) and then ends
 * immediately; every other death instead dwells on ds:0x4566 until 108 ticks,
 * which is what lets a ship that fell off the road drop out of view. */
#define EXPLOSION_DEATH_TICKS 42u
#define OTHER_DEATH_TICKS 108u
/* Falling off the road uses the same dwell as any non-explosion death. There is no
 * separate value in the EXE and there never was: @0x223c tests ds:0x4566 >= 0x6c for
 * every outcome that is not the explosion. */
#define FALL_DEATH_TICKS OTHER_DEATH_TICKS

typedef struct {
    const Level *level;
    Ship ship;
    Ship expected_ship;
    bool did_win;
    /* `pub(crate)` in the reference design; public here so the host/tests can seed state. */
    ControllerState last_controls;
    bool has_death_frame_index;         /* std::optional<std::size_t> death_frame_index */
    unsigned death_frame_index;
    unsigned frame_index_;
} GameplaySession;

void gameplay_session_init(GameplaySession *s, const Level *level);
/* True once the ship is dead AND its death animation has run its course, i.e.
 * when the original would stop simulating and report the outcome. */
bool gameplay_death_animation_finished(const GameplaySession *s);
void gameplay_run_frame(GameplaySession *s, ControllerState controls, GameplayFrameResult *out);
void gameplay_run_demo_frame(GameplaySession *s, const DemoRecording *demo,
                             GameplayFrameResult *out);

/* the reference design returns Option<&DemoInput>; a nullable pointer models it here. */
const DemoInput SR_FAR *sample_demo_input_for_ship(const DemoRecording *demo, const Ship *ship);
ControllerState controller_state_from_demo_input(const DemoInput SR_FAR *input);

#endif
