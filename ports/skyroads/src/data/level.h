/* Level geometry plus the DOS collision probes, in two exactly-equivalent
 * forms: the double reference (constants as exact `hex / 0x80` ratios) used by
 * the renderer and tests, and the integer fixed-point core the simulation tick
 * runs on (the target console has no FPU).
 *
 * C translation: only the integer core. The double probes (get_cell, is_inside_tile,
 * is_inside_tunnel, gravity_acceleration) were used by upstream's tests alone; the
 * renderer's few double constants are kept as the _128 integers it is derived from. */
#ifndef DATA_LEVEL_H
#define DATA_LEVEL_H

#include "data/image.h"
#include "data/roads.h"

/* The same landmarks in the DOS EXE's own fixed-point units: x/y are 16-bit
 * words in 1/128 units ("_128"), z is a 32-bit 16.16 value ("_fp16"). The
 * simulation runs entirely on these; the doubles above serve the renderer and
 * the reference implementation. */
#define LEVEL_TILE_STRIDE_X 46
#define LEVEL_CENTER_X_128 ((int32_t)0x8000)
#define LEVEL_MIN_X_128 ((int32_t)0x2F80)
#define LEVEL_MAX_X_128 ((int32_t)0xD080)
#define GROUND_Y_128 ((int32_t)0x2800)

typedef enum {
    TouchEffect_None,
    TouchEffect_Accelerate,
    TouchEffect_Decelerate,
    TouchEffect_Kill,
    TouchEffect_Slide,
    TouchEffect_RefillOxygen,
} TouchEffect;

typedef struct {
    uint16_t raw_descriptor;
    uint8_t color_index_low;
    uint8_t color_index_high;
    uint8_t flags;
    bool has_tunnel;
    bool has_tile;
    uint8_t tile_effect;            /* TouchEffect */
    bool has_cube_height;           /* std::optional<uint16_t> cube_height */
    uint16_t cube_height;
    uint8_t cube_effect;            /* TouchEffect */
} LevelCell;

/* LevelCell::empty() */
extern const LevelCell LEVEL_CELL_EMPTY;

static inline bool cell_is_empty(const LevelCell SR_FAR *c)
{
    return !c->has_tunnel && !c->has_tile && !c->has_cube_height;
}

typedef struct {
    LevelCell c[ROAD_COLUMNS];
} LevelRow;

typedef struct {
    unsigned road_index;
    char name[16];
    uint16_t gravity;
    uint16_t fuel;
    uint16_t oxygen;
    const LevelRow SR_FAR *cells;
    unsigned length;                /* cells.size() */
    const RoadRow SR_FAR *raw_rows; /* C (round 2): the road's own rows (raw descriptors) */
    /* The road's 72-entry VGA palette (already scaled 6-bit -> 8-bit). The DOS
     * road renderer indexes this by TREKDAT colour code for exact road/wall hues. */
    const RgbColor SR_FAR *palette;
    unsigned palette_count;
    /* C (round 2): what the tick derives from the road's constants, once (each was a 32-bit
     * divide a tick): level_gravity_acceleration_128, the oxygen burnt a tick, 0x7530 / fuel
     * (-1: fuel 0); and a byte a row, bit c set when cell c is not empty */
    int32_t gravity_acc_128;
    int32_t oxygen_dec;
    int32_t fuel_q;
    const uint8_t SR_FAR *row_mask;
    /* 8 bytes a row, a byte a cell: bit 0 not empty, 1 tunnel, 2 cube, 3 the cube 120 high
     * (else 100); the 8th byte (no cell) only bit 4: the row has a tunnel or a cube. What
     * the collision probe reads (horizon/hz_probe.s) */
    const uint8_t SR_FAR *cell_bits;
    bool built;                     /* C (round 2): cells, row_mask, cell_bits made */
} Level;

/* C: the cell probes return a pointer to the cell (the C++ returned a copy of the
 * 12-byte structure; through far memory on the Atari816 that copy cost more than the
 * probe). The empty cell is LEVEL_CELL_EMPTY. */
typedef const LevelCell SR_FAR *CellRef;

/* Integer fixed-point collision probes for the simulation tick: no
 * float/double operations anywhere inside (the target console has no FPU).
 * x here is 16.16 because will_land_on_tile accumulates x at that
 * precision; a 1/128 caller passes `x_128 * 512`. y is 1/128, z is 16.16.
 * Bit-exact images of the double probes above for on-grid inputs. */
int32_t level_gravity_acceleration_128(const Level *level);
CellRef level_cell_at_indices(const Level *level, unsigned x_index, unsigned z_index);
CellRef level_get_cell_fp16(const Level *level, int32_t x_fp16, int32_t z_fp16);
/* C: level_get_cell_fp16(level, x_128 * 512, z_fp16), the same cell without the shift (a
 * call on the 65816; the C++ wrote `x_128 * 512` at each probe) */
CellRef level_get_cell_128(const Level *level, int32_t x_128, int32_t z_fp16);
bool level_is_inside_tile_128(const Level *level, int32_t x_128, int32_t y_128,
                              int32_t z_fp16);
/* C (round 2): the probe the simulation calls: level_is_inside_tile_128, or a platform's
 * own of the same arguments and result (horizon/hz_probe.s) */
extern bool (*level_probe)(const Level *level, int32_t x_128, int32_t y_128, int32_t z_fp16);
/* the same for x 6272..57855, y -20000..32767 and z >= 0 given as its row (z >> 16): the
 * answer of level_is_inside_tile_128(level, x, y, z) (level_probe16_c, or a platform's) */
bool level_probe16_c(const Level *level, uint16_t x_128, int y_128, unsigned zrow);
extern bool (*level_probe16)(const Level *level, uint16_t x_128, int y_128, unsigned zrow);
/* (the 32-bit form, which the 16-bit one must equal: host test probecheck) */
bool level_is_inside_tile_128_ref(const Level *level, int32_t x_128, int32_t y_128,
                                  int32_t z_fp16);
bool level_is_inside_tunnel_128(const Level *level, int32_t x_128, int32_t y_128,
                                int32_t z_fp16);

Level level_from_road_entry(const RoadEntry SR_FAR *road);
/* levels_from_roads_archive: an array of roads.road_count levels (malloc). C (round 2): their
 * cells are built by level_build when a level is played (gameplay_session_init does it) */
Level *levels_from_roads_archive(const RoadsArchive *roads);
void level_build(Level *level);

#endif
