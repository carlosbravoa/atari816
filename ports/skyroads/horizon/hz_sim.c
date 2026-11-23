/* hz_sim.c - the simulation's fast paths on Horizon (round 2): the near tables of
 * hz_probe.s (the collision probe), built for the level being played. */
#include <string.h>

#include "core/gameplay.h"
#include "data/level.h"
#include "hz_plat.h"

const Level *hzp_level;                 /* the level hz_probe reads (NULL: none yet) */
unsigned hzp_len;                       /* its rows */
const uint8_t SR_FAR *hzp_bits;         /* its cell_bits */
uint16_t hzp_unitcol[416];              /* unit u = (x - 95 * 128) >> 7 -> its column, 7: none */
uint16_t hzp_m5888[416];                /* unit u = (x - 49 * 128) >> 7 -> floor(u / 46) * 5888 */
uint16_t hzp_lows[38], hzp_ceils[38];   /* TUNNEL_LOWS, TUNNEL_CEILS * 128 */
uint16_t hzp_div5[511];                 /* n -> n / 5 | (n % 5) * 12 << 8 (hz_move16's div5) */
uint16_t hzp_mul51[256];                /* 51 n */
uint16_t hzp_fifth[30];                 /* [b * 6 + k]: floor(b * k / 5) */

extern const uint8_t TUNNEL_CEILS[38];
extern const uint8_t TUNNEL_LOWS[38];

void hzp_tables(void)
{
    unsigned u;
    for (u = 0; u < 416; ++u) {
        const unsigned col = u / 46u;
        hzp_unitcol[u] = (uint16_t)(col < 7 ? col : 7);
        hzp_m5888[u] = (uint16_t)(col * 5888u);
    }
    for (u = 0; u < 38; ++u) {
        hzp_lows[u] = (uint16_t)(TUNNEL_LOWS[u] * 128u);
        hzp_ceils[u] = (uint16_t)(TUNNEL_CEILS[u] * 128u);
    }
    for (u = 0; u < 511; ++u)
        hzp_div5[u] = (uint16_t)(u / 5u | (u % 5u) * 12u << 8);
    for (u = 0; u < 256; ++u)
        hzp_mul51[u] = (uint16_t)(51u * u);
    for (u = 0; u < 30; ++u)
        hzp_fifth[u] = (uint16_t)((u / 6u) * (u % 6u) / 5u);
}

static void hzp_take(const Level *level)
{
    if (hzp_unitcol[415] == 0)
        hzp_tables();
    hzp_bits = level->cell_bits;
    hzp_len = level->length;
    hzp_level = level;
}

/* hz_probe's way out for a level it was not given yet: take it, answer by the C */
bool hzp_newlevel(const Level *level, int32_t x_128, int32_t y_128, int32_t z_fp16)
{
    hzp_take(level);
    return level_is_inside_tile_128_ref(level, x_128, y_128, z_fp16);
}

bool hzm_newlevel(Ship *s, const Ship *dest, const Level *level)
{
    hzp_take(level);
    return gameplay_move16_c(s, dest, level);
}

unsigned hzs_newlevel(const Level *level, uint16_t x, int y, unsigned zrow, int step)
{
    hzp_take(level);
    return gameplay_scan16_c(level, x, y, zrow, step);
}

bool hzp_newlevel16(const Level *level, uint16_t x_128, int y_128, unsigned zrow)
{
    hzp_take(level);
    return level_probe16_c(level, x_128, y_128, zrow);
}

/* /PROBECHECK: hz_probe against level_is_inside_tile_128_ref at n random points of every
 * level (as host srtool probecheck does for the C) -> the points that differ */
unsigned long hzp_check(const Level *levels, unsigned count, unsigned long n)
{
    unsigned long k, bad = 0, seed = 1;
    unsigned li;
    for (li = 0; li < count; ++li) {
        const Level *l = &levels[li];
        for (k = 0; k < n; ++k) {
            int32_t x, y, z;
            seed = seed * 1103515245UL + 12345UL;
            x = (int32_t)((seed >> 8) % 80000UL) - 8000;
            seed = seed * 1103515245UL + 12345UL;
            y = (int32_t)((seed >> 8) % 60000UL) - 30000;
            if ((k & 1) == 0)   /* (half of them near the road's heights) */
                y = 0x1E00 + (int32_t)((seed >> 4) % 0x2400UL);
            seed = seed * 1103515245UL + 12345UL;
            z = (int32_t)((seed >> 4) % ((uint32_t)(l->length + 4) << 16)) - 65536;
            if ((hz_probe(l, x, y, z) != 0) != level_is_inside_tile_128_ref(l, x, y, z))
                bad++;
            if (x >= 6272 && x <= 57855 && y >= -20000 && y <= 32767 && z >= 0 &&
                (hz_probe16(l, (uint16_t)x, (int)y, (unsigned)((uint32_t)z >> 16)) != 0) !=
                    level_is_inside_tile_128_ref(l, x, y, z))
                bad++;
        }
    }
    return bad;
}

/* /MOVECHECK: hz_move16 and hz_scan16 against gameplay.c's C (which srsimcheck checks against
 * the simulation before round 2) at n random moves and scans a level -> how many differ */
static unsigned long mc_seed = 7;
static int32_t mc_rr(int32_t lo, int32_t hi)
{
    mc_seed = mc_seed * 1103515245UL + 12345UL;
    return lo + (int32_t)((mc_seed >> 4) % (uint32_t)(hi - lo + 1));
}

unsigned long hzm_check(const Level *levels, unsigned count, unsigned long n)
{
    unsigned long k, bad = 0;
    unsigned li;
    for (li = 0; li < count; ++li) {
        const Level *l = &levels[li];
        const int32_t zmax = ((int32_t)l->length + 2) * 65536;
        for (k = 0; k < n; ++k) {
            Ship a, b, d;
            bool ra, rb;
            unsigned sa, sb;
            uint16_t x;
            int y, step;
            memset(&a, 0, sizeof a);
            a.x_position_128 = (k & 7) ? mc_rr(6000, 58200) : mc_rr(-70000, 140000);
            a.y_position_128 = (k & 1) ? mc_rr(0x1E00, 0x4000) : mc_rr(-21000, 33000);
            a.z_position_fp16 = (k & 15) ? mc_rr(-3000, zmax) : mc_rr(-200000, zmax);
            d = a;
            d.x_position_128 += (k & 3) ? mc_rr(-1500, 1500) : mc_rr(-60000, 60000);
            d.y_position_128 += (k & 3) ? mc_rr(-1200, 1200) : mc_rr(-40000, 40000);
            d.z_position_fp16 += (k & 7) ? mc_rr(-50, 0x3000) : mc_rr(-70000, 70000);
            if ((k & 31) == 5)
                d.x_position_128 = a.x_position_128;
            if ((k & 31) == 6)
                d.y_position_128 = a.y_position_128;
            b = a;
            ra = hz_move16(&a, &d, l);
            rb = gameplay_move16_c(&b, &d, l);
            if (ra != rb || (ra && (a.x_position_128 != b.x_position_128 ||
                                    a.y_position_128 != b.y_position_128 ||
                                    a.z_position_fp16 != b.z_position_fp16)))
                bad++;
            x = (uint16_t)mc_rr(8064, 56063);
            y = (k & 1) ? (int)mc_rr(0x1E00, 0x4000) : (int)mc_rr(-20000, 32767);
            step = (k & 2) ? 128 : -128;
            {
                const unsigned row = (unsigned)mc_rr(0, (int32_t)l->length + 2);
                sa = hz_scan16(l, x, y, row, step);
                sb = gameplay_scan16_c(l, x, y, row, step);
                if (sa != sb)
                    bad++;
            }
        }
    }
    return bad;
}
