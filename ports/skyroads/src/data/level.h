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
    /* The road's 72-entry VGA palette (already scaled 6-bit -> 8-bit). The DOS
     * road renderer indexes this by TREKDAT colour code for exact road/wall hues. */
    const RgbColor SR_FAR *palette;
    unsigned palette_count;
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
/* C: a platform's version of the 16-bit probe for the row at z (NULL: the C) */
extern bool (*level_inside_tile16_fast)(const LevelRow SR_FAR *row, uint16_t x, int y);
/* (the 32-bit form, which the 16-bit one must equal: host test probecheck) */
bool level_is_inside_tile_128_ref(const Level *level, int32_t x_128, int32_t y_128,
                                  int32_t z_fp16);
bool level_is_inside_tunnel_128(const Level *level, int32_t x_128, int32_t y_128,
                                int32_t z_fp16);

Level level_from_road_entry(const RoadEntry SR_FAR *road);
/* levels_from_roads_archive: an array of roads.road_count levels (plat_alloc) */
Level *levels_from_roads_archive(const RoadsArchive *roads);

#endif
