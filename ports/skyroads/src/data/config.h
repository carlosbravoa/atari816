/* skyroads.cfg: the original's saved settings and per-road progress. The game
 * writes 0x42 = 66 bytes from ds:0x4524 (save @0x5770, load @0x571b), laid out as
 * 33 little-endian words: word 0 is a checksum, words 1-2 are settings, and words
 * 3..32 are the number of times each of the 30 roads has been completed. A missing
 * file or a failed checksum resets the whole block to zero (@0x5744-0x5759). */
#ifndef DATA_CONFIG_H
#define DATA_CONFIG_H

#include "sr.h"

#define CONFIG_ROAD_COUNT 30u
#define CONFIG_BYTES 66u

typedef struct {
    /* The two setting words the original keeps alongside progress. We do not
     * interpret them, but we preserve them so a file stays usable by the game. */
    uint16_t setting_a;
    uint16_t setting_b;
    uint16_t road_completions[CONFIG_ROAD_COUNT];
} GameConfig;

/* Returns a zeroed config when the file is absent, short, or fails its checksum,
 * which is what the original does. */
GameConfig load_game_config(const char *path);
bool save_game_config(const char *path, const GameConfig *config);

/* Exposed for tests: the checksum the original computes over the block. */
uint16_t game_config_checksum(const GameConfig *config);

#endif
