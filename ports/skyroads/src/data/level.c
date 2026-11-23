#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "data/level.h"

const LevelCell LEVEL_CELL_EMPTY;

const uint8_t TUNNEL_CEILS[38] = {
    0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
    0x20, 0x20, 0x20, 0x20, 0x1F, 0x1F, 0x1F, 0x1F, 0x1F, 0x1E, 0x1E, 0x1E, 0x1D,
    0x1D, 0x1D, 0x1C, 0x1B, 0x1A, 0x19, 0x18, 0x16, 0x14, 0x12, 0x11, 0x0E,
};
/* C: 38 entries where the C++ has 30. is_inside_tile_y_128 lets the index reach 37 (the
 * CEILS check) and reads TUNNEL_LOWS[30..37] past its end; in the C++'s own binary
 * (level.cpp.o, gcc) the bytes there are the .rodata padding before TUNNEL_CEILS: zeros.
 * The 8 zeros make every build read what that one read (PORTING-NOTES: upstream faults). */
const uint8_t TUNNEL_LOWS[38] = {
    0x10, 0x10, 0x10, 0x10, 0x0F, 0x0E, 0x0D, 0x0B, 0x08, 0x07,
    0x06, 0x05, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x02, 0x01,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

static TouchEffect effect_for_color_index(uint8_t index)
{
    switch (index) {
    case 10: return TouchEffect_Accelerate;
    case 12: return TouchEffect_Kill;
    case 9: return TouchEffect_RefillOxygen;
    case 8: return TouchEffect_Slide;
    case 2: return TouchEffect_Decelerate;
    default: return TouchEffect_None;
    }
}

static void cell_from_descriptor(uint16_t raw_descriptor, LevelCell SR_FAR *out)
{
    const uint8_t color_raw = (uint8_t)(raw_descriptor & 0x00FF);
    const uint8_t flags = (uint8_t)(raw_descriptor >> 8);
    const uint8_t color_index_low = color_raw & 0x0F;
    const uint8_t color_index_high = color_raw >> 4;
    LevelCell cell;

    cell.has_cube_height = false;
    cell.cube_height = 0;
    switch (flags & 0x06) {
    case 0x00: break;
    case 0x02: cell.has_cube_height = true; cell.cube_height = 100; break;
    case 0x04: cell.has_cube_height = true; cell.cube_height = 120; break;
    default:
        sr_fail("unexpected cube height flag bits");
    }

    cell.raw_descriptor = raw_descriptor;
    cell.color_index_low = color_index_low;
    cell.color_index_high = color_index_high;
    cell.flags = flags;
    cell.has_tunnel = (flags & 0x01) != 0;
    cell.has_tile = color_index_low > 0;
    cell.tile_effect = (uint8_t)effect_for_color_index(color_index_low);
    cell.cube_effect = (uint8_t)effect_for_color_index(color_index_high);
    *out = cell; /* (C: into the level's row: the C++ returned the cell) */
}

/* ---- integer fixed-point collision core --------------------------------------
 * The exact integer images of the double probes above, in the DOS EXE's own
 * units (x/y 1/128, z 16.16). The simulation tick runs only on these; the
 * double versions remain for the renderer and the reference tests. Every value
 * the tick produces is a multiple of 1/128 (or 1/65536 for z), which doubles
 * represent exactly, so for on-grid inputs these return bit-identical answers. */

#define EMPTY_COLLISION_MIN_Y_128 ((int32_t)0x1E80)
#define EMPTY_COLLISION_MAX_Y_128 ((int32_t)80 * 128)
#define TUNNEL_ENTRY_MIN_Y_128 ((int32_t)0x2180)
#define TUNNEL_BASE_Y_128 ((int32_t)68 * 128)
#define PROBE_RADIUS_X_128 ((int32_t)14 * 128)

typedef struct {
    int32_t distance_128;
    int32_t var_a_128;
} DistanceFromCenter128;

/* Integer image of distance_from_center: C++ `%` truncates toward zero exactly
 * like fmod, and "1.0 - distance" is 128 raw.
 * C: a value of 0..65535 takes the 16-bit remainder (the same number: C's `%` of a
 * non-negative value), anything else the 32-bit one, as upstream. */
/* C: floor(v / 46) for v in 0..511, from a table (a 16-bit divide is a call of 1,000
 * cycles on the 65816, and the tick makes hundreds of these probes) */
uint8_t level_div46[512];
#define div46 level_div46
bool level_is_inside_tile_128_ref(const Level *level, int32_t x_128, int32_t y_128,
                                  int32_t z_fp16);

static void div46_init(void)
{
    unsigned v;
    for (v = 0; v < 512; ++v)
        div46[v] = (uint8_t)(v / 46);
}

static DistanceFromCenter128 distance_from_center_128(int32_t x_128)
{
    const int32_t v = x_128 - 49 * 128;
    int32_t rem, distance, var_a = -46 * 128;
    DistanceFromCenter128 r;
    if (v >= 0 && v <= 0xFFFF) {
        /* v % 5888 with v / 5888 = (v / 128) / 46 (nested floors) */
        const uint16_t u = (uint16_t)v;
        rem = (int32_t)(uint16_t)(u - (uint16_t)div46[u >> 7] * (uint16_t)(46 * 128));
    } else {
        rem = v % (46 * 128);
    }
    distance = 23 * 128 - rem;
    if (distance < 0) {
        distance = 128 - distance;
        var_a = -var_a;
    }
    r.distance_128 = distance;
    r.var_a_128 = var_a;
    return r;
}

/* std::round is half away from zero; every distance that reaches these checks
 * is non-negative, so `(d + 64) >> 7` reproduces it. */
static bool is_inside_tile_y_128(int32_t y_128, int32_t distance_128, CellRef cell)
{
    const int32_t distance_index = (distance_128 + 64) >> 7;
    int32_t y2;
    bool has_cube;
    if (distance_index > 37)
        return false;
    y2 = y_128 - TUNNEL_BASE_Y_128;
    has_cube = cell->has_cube_height;
    if (cell->has_tunnel && !has_cube) {
        return y2 > (int32_t)TUNNEL_LOWS[distance_index] * 128 &&
               y2 < (int32_t)TUNNEL_CEILS[distance_index] * 128;
    }
    if (!cell->has_tunnel && has_cube)
        return y_128 < (int32_t)cell->cube_height * 128;
    if (cell->has_tunnel && has_cube) {
        return y2 > (int32_t)TUNNEL_LOWS[distance_index] * 128 &&
               y_128 < (int32_t)cell->cube_height * 128;
    }
    return false;
}

static bool is_inside_tunnel_y_128(int32_t y_128, int32_t distance_128, CellRef cell)
{
    const int32_t distance_index = (distance_128 + 64) >> 7;
    int32_t y2;
    if (distance_index > 29)
        return false;
    y2 = y_128 - TUNNEL_BASE_Y_128;
    return cell->has_tunnel && cell->has_tile &&
           y2 < (int32_t)TUNNEL_LOWS[distance_index] * 128 && y_128 >= 80 * 128;
}

/* The DOS form is a straight integer division; the double `floor(g * 0x1680 /
 * 0x190)` lands on the same value for every 16-bit gravity (the exact quotient
 * g * 14.4 is never within double rounding error of an integer unless it IS
 * one, i.e. g a multiple of 5). */
int32_t level_gravity_acceleration_128(const Level *level)
{
    /* (C: the last answer kept: a 32-bit divide is a call of 1,000 cycles, and the tick
     * asks several times) */
    static uint16_t last_gravity = 0xFFFF;
    static int32_t last;
    if (level->gravity != last_gravity) {
        last = -((int32_t)level->gravity * 0x1680 / 0x190);
        last_gravity = level->gravity;
    }
    return last;
}

CellRef level_cell_at_indices(const Level *level, unsigned x_index, unsigned z_index)
{
    if (z_index < level->length && x_index < ROAD_COLUMNS)
        return &level->cells[z_index].c[x_index];
    return &LEVEL_CELL_EMPTY;
}

/* EXE @0x4c0: x is brought to whole units with a /0x80 and offset by -95, and z
 * to a row with `z / 0x2000` then `/ 8` -- the same double-floor the double
 * version does as floor(floor(z*8)/8); the composition of the two positive-
 * divisor floors is floor(z_fp16 / 0x10000).
 * C: written as that composition: a negative z is no row (upstream: z_row < 0 -> empty),
 * else z >> 16; and x (0 .. 322 * 65536 here) / (46 * 65536) as (x >> 16) / 46, the same
 * floor in 16 bits (32-bit divides are calls of 100 us on the Atari816, and the tick makes
 * hundreds of these probes). */
CellRef level_get_cell_fp16(const Level *level, int32_t x_fp16, int32_t z_fp16)
{
    const int32_t x = x_fp16 - (int32_t)95 * 65536;
    if (!(x >= 0 && x <= (int32_t)322 * 65536))
        return &LEVEL_CELL_EMPTY;
    if (z_fp16 < 0)
        return &LEVEL_CELL_EMPTY;
    return level_cell_at_indices(level, div46[(uint16_t)(x >> 16)],
                                 (unsigned)(uint16_t)((uint32_t)z_fp16 >> 16));
}

/* x_128 * 512 - 95 * 65536 = 512 * (x_128 - 95 * 128): in 0 .. 322 * 65536 when
 * x_128 - 12160 is in 0 .. 322 * 128, and its >> 16 is that difference >> 7 */
CellRef level_get_cell_128(const Level *level, int32_t x_128, int32_t z_fp16)
{
    const int32_t d = x_128 - (int32_t)95 * 128;
    unsigned x_index, z_index;
    if (!(d >= 0 && d <= (int32_t)322 * 128))
        return &LEVEL_CELL_EMPTY;
    if (z_fp16 < 0)
        return &LEVEL_CELL_EMPTY;
    x_index = div46[(uint16_t)d >> 7];
    z_index = (unsigned)(uint16_t)((uint32_t)z_fp16 >> 16);
    if (z_index < level->length && x_index < ROAD_COLUMNS)
        return &level->cells[z_index].c[x_index];
    return &LEVEL_CELL_EMPTY;
}

/* C: the probe in 16-bit arithmetic, for the positions the game has (x from 6272 to
 * 57855, y in 16 bits, z >= 0): the same steps as below, on unsigned / int (cc816's 32-bit
 * code made a probe cost about 4,000 cycles, and a tick makes up to 80). */
static const LevelCell SR_FAR *cell16(const LevelRow SR_FAR *row, uint16_t x)
{
    /* level_get_cell_128 with d = x - 95 * 128 */
    uint16_t d, col;
    if (!row || x < 95u * 128u)
        return &LEVEL_CELL_EMPTY;
    d = x - 95u * 128u;
    if (d > 322u * 128u)
        return &LEVEL_CELL_EMPTY;
    col = div46[d >> 7];
    if (col >= ROAD_COLUMNS)
        return &LEVEL_CELL_EMPTY;
    return &row->c[col];
}

static bool tile_y16(int y, unsigned distance, CellRef cell)
{
    /* is_inside_tile_y_128 */
    const unsigned distance_index = (distance + 64) >> 7;
    int y2;
    bool has_cube;
    if (distance_index > 37)
        return false;
    y2 = y - (int)TUNNEL_BASE_Y_128;
    has_cube = cell->has_cube_height;
    if (cell->has_tunnel && !has_cube)
        return y2 > (int)TUNNEL_LOWS[distance_index] * 128 &&
               y2 < (int)TUNNEL_CEILS[distance_index] * 128;
    if (!cell->has_tunnel && has_cube)
        return (long)y < (long)cell->cube_height * 128;
    if (cell->has_tunnel && has_cube)
        return y2 > (int)TUNNEL_LOWS[distance_index] * 128 &&
               (long)y < (long)cell->cube_height * 128;
    return false;
}

static bool inside_tile16(const Level *level, uint16_t x, int y, int32_t z_fp16)
{
    const uint16_t zrow = (uint16_t)((uint32_t)z_fp16 >> 16);
    const LevelRow SR_FAR *row = zrow < level->length ? &level->cells[zrow] : 0;
    CellRef left_tile = cell16(row, x - (uint16_t)PROBE_RADIUS_X_128);
    CellRef right_tile = cell16(row, x + (uint16_t)PROBE_RADIUS_X_128);
    uint16_t v, rem;
    unsigned distance;
    bool far_side;
    if (cell_is_empty(left_tile) && cell_is_empty(right_tile))
        return false;
    if (y < (int)EMPTY_COLLISION_MAX_Y_128 && y > (int)EMPTY_COLLISION_MIN_Y_128)
        return true;
    if (y < (int)TUNNEL_ENTRY_MIN_Y_128)
        return false;
    /* distance_from_center_128 (v >= 0 here) */
    v = x - 49u * 128u;
    rem = v - (uint16_t)div46[v >> 7] * (uint16_t)(46 * 128);
    far_side = rem > 23u * 128u;
    distance = far_side ? 128u + (rem - 23u * 128u) : 23u * 128u - rem;
    if (tile_y16(y, distance, cell16(row, x)))
        return true;
    return tile_y16(y, 47u * 128u - distance,
                    cell16(row, far_side ? x + (uint16_t)(46 * 128) : x - (uint16_t)(46 * 128)));
}

bool (*level_probe)(const Level *level, int32_t x_128, int32_t y_128, int32_t z_fp16) =
    level_is_inside_tile_128;

/* C (round 2): the probe for x 6272..57855, y -20000..32767 and the row of a z >= 0 */
bool level_probe16_c(const Level *level, uint16_t x_128, int y_128, unsigned zrow)
{
    return zrow < level->length && inside_tile16(level, x_128, y_128, (int32_t)zrow << 16);
}

bool (*level_probe16)(const Level *level, uint16_t x_128, int y_128, unsigned zrow) =
    level_probe16_c;

bool level_is_inside_tile_128(const Level *level, int32_t x_128, int32_t y_128,
                              int32_t z_fp16)
{
    if (x_128 >= 6272 && x_128 <= 57855 && y_128 >= -20000 && y_128 <= 32767 && z_fp16 >= 0)
        return inside_tile16(level, (uint16_t)x_128, (int)y_128, z_fp16);
    return level_is_inside_tile_128_ref(level, x_128, y_128, z_fp16);
}

bool level_is_inside_tile_128_ref(const Level *level, int32_t x_128, int32_t y_128,
                                  int32_t z_fp16)
{
    CellRef left_tile = level_get_cell_128(level, x_128 - PROBE_RADIUS_X_128, z_fp16);
    CellRef right_tile = level_get_cell_128(level, x_128 + PROBE_RADIUS_X_128, z_fp16);
    DistanceFromCenter128 d;
    CellRef center_tile, adjacent_tile;

    if (cell_is_empty(left_tile) && cell_is_empty(right_tile))
        return false;
    if (y_128 < EMPTY_COLLISION_MAX_Y_128 && y_128 > EMPTY_COLLISION_MIN_Y_128)
        return true;
    if (y_128 < TUNNEL_ENTRY_MIN_Y_128)
        return false;

    d = distance_from_center_128(x_128);
    center_tile = level_get_cell_128(level, x_128, z_fp16);
    if (is_inside_tile_y_128(y_128, d.distance_128, center_tile))
        return true;
    adjacent_tile = level_get_cell_128(level, x_128 + d.var_a_128, z_fp16);
    return is_inside_tile_y_128(y_128, 47 * 128 - d.distance_128, adjacent_tile);
}

bool level_is_inside_tunnel_128(const Level *level, int32_t x_128, int32_t y_128,
                                int32_t z_fp16)
{
    CellRef left_tile = level_get_cell_128(level, x_128 - PROBE_RADIUS_X_128, z_fp16);
    CellRef right_tile = level_get_cell_128(level, x_128 + PROBE_RADIUS_X_128, z_fp16);
    DistanceFromCenter128 d;
    CellRef center_tile, adjacent_tile;

    if (cell_is_empty(left_tile) && cell_is_empty(right_tile))
        return false;

    d = distance_from_center_128(x_128);
    center_tile = level_get_cell_128(level, x_128, z_fp16);
    if (is_inside_tunnel_y_128(y_128, d.distance_128, center_tile))
        return true;
    adjacent_tile = level_get_cell_128(level, x_128 + d.var_a_128, z_fp16);
    return is_inside_tunnel_y_128(y_128, 47 * 128 - d.distance_128, adjacent_tile);
}

static uint8_t up(uint8_t v)
{
    const unsigned s = (unsigned)v * 4u;
    return s > 255u ? 255u : (uint8_t)s;
}

/* C (round 2): a level's header (name, constants, palette, the road's rows), its cells built
 * later by level_build (lazily: a level's cells cost 0.2 s on the Atari816, 31 levels
 * 5.5 s at the start) */
static Level level_header(const RoadEntry SR_FAR *road)
{
    Level level;
    unsigned color_count, i;
    RgbColor SR_FAR *palette;

    if (div46[46] == 0)
        div46_init();
    memset(&level, 0, sizeof level);
    level.road_index = road->index;
    if (road->index == 0)
        sprintf(level.name, "Demo Level");
    else
        sprintf(level.name, "Level %u", road->index);
    level.gravity = road->gravity;
    level.fuel = road->fuel;
    level.oxygen = road->oxygen;
    /* Scale the road's 6-bit VGA palette to 8-bit (saturating x4). */
    color_count = (unsigned)(road->palette_vga.size / 3);
    palette = (RgbColor SR_FAR *)plat_alloc((uint32_t)color_count * 3);
    for (i = 0; i < color_count; ++i)
        palette[i] = rgb(up(road->palette_vga.data[i * 3]), up(road->palette_vga.data[i * 3 + 1]),
                         up(road->palette_vga.data[i * 3 + 2]));
    level.palette = palette;
    level.palette_count = color_count;
    level.length = road->row_count;
    level.raw_rows = road->rows;
    /* (C, round 2: the tick's constants, as handle_oxygen_and_fuel and
     * level_gravity_acceleration_128 computed them every tick) */
    level.gravity_acc_128 = -((int32_t)level.gravity * 0x1680 / 0x190);
    level.oxygen_dec = level.oxygen > 0 ? 0x7530 / (0x24 * (int32_t)level.oxygen) : 0x7530;
    level.fuel_q = level.fuel > 0 ? 0x7530 / (int32_t)level.fuel : -1;
    level.built = false;
    return level;
}

void level_build(Level *level)
{
    unsigned r;
    LevelRow SR_FAR *cells;
    const RoadRow SR_FAR *rows = level->raw_rows;
    if (level->built)
        return;
    cells = level->length ? (LevelRow SR_FAR *)plat_alloc((uint32_t)level->length *
                                                          sizeof(LevelRow))
                          : 0;
    for (r = 0; r < level->length; ++r) {
        unsigned column;
        for (column = 0; column < ROAD_COLUMNS; ++column)
            cell_from_descriptor(rows[r].c[column], &cells[r].c[column]);
    }
    level->cells = cells;
    {
        uint8_t SR_FAR *mask = (uint8_t SR_FAR *)plat_alloc(level->length ? level->length : 1);
        uint8_t SR_FAR *bits = (uint8_t SR_FAR *)plat_alloc((uint32_t)level->length * 8u + 8u);
        for (r = 0; r < level->length; ++r) {
            unsigned column, m = 0;
            for (column = 0; column < ROAD_COLUMNS; ++column) {
                const LevelCell SR_FAR *c = &cells[r].c[column];
                uint8_t b = 0;
                if (!cell_is_empty(c)) {
                    m |= 1u << column;
                    b = 1;
                }
                if (c->has_tunnel)
                    b |= 2;
                if (c->has_cube_height)
                    b |= c->cube_height == 120 ? 12 : 4;     /* (100 or 120: cell_from_descriptor) */
                bits[r * 8u + column] = b;
                if (b & 6)
                    bits[r * 8u + 7] = 0x10;    /* (the row has a tunnel or a cube) */
            }
            mask[r] = (uint8_t)m;
        }
        level->row_mask = mask;
        level->cell_bits = bits;
    }
    level->built = true;
}

Level level_from_road_entry(const RoadEntry SR_FAR *road)
{
    Level level = level_header(road);
    level_build(&level);
    return level;
}

Level *levels_from_roads_archive(const RoadsArchive *roads)
{
    Level *levels = (Level *)malloc(sizeof(Level) * SR_MAX(roads->road_count, 1));
    unsigned i;
    if (!levels)
        sr_fail("out of memory (levels)");
    for (i = 0; i < roads->road_count; ++i)
        levels[i] = level_header(&roads->roads[i]);     /* (C, round 2: built when played) */
    return levels;
}
