#include <string.h>

#include "data/config.h"
#include "platform.h"

#define CONFIG_WORDS (CONFIG_BYTES / 2)

static void to_words(const GameConfig *config, uint16_t *words)
{
    unsigned i;
    words[0] = 0; /* checksum slot, filled in by the caller */
    words[1] = config->setting_a;
    words[2] = config->setting_b;
    for (i = 0; i < CONFIG_ROAD_COUNT; ++i)
        words[3 + i] = config->road_completions[i];
}

/* Checksum @0x56c3. Note the original advances its pointer only once, before the
 * loop, so all 32 iterations read the SAME word (the one after the checksum) and
 * accumulate it XOR-ed with the loop counter. That is faithfully reproduced here:
 * getting it "right" instead would produce files the original game rejects. */
uint16_t game_config_checksum(const GameConfig *config)
{
    uint16_t words[CONFIG_WORDS];
    uint16_t sum = 0, i;
    to_words(config, words);
    for (i = 1; i < 33; ++i)
        sum = (uint16_t)(sum + (words[1] ^ i));
    return sum;
}

GameConfig load_game_config(const char *path)
{
    GameConfig config, loaded;
    Bytes raw;
    unsigned i;
    memset(&config, 0, sizeof config);
    if (!plat_read_file(path, &raw))
        return config; /* absent -> zeroed, as the original does */
    if (raw.size < CONFIG_BYTES) {
        plat_free_big(raw.data);
        return config;
    }
#define WORD_AT(i) ((uint16_t)(raw.data[(i) * 2] | ((uint16_t)raw.data[(i) * 2 + 1] << 8)))
    loaded.setting_a = WORD_AT(1);
    loaded.setting_b = WORD_AT(2);
    for (i = 0; i < CONFIG_ROAD_COUNT; ++i)
        loaded.road_completions[i] = WORD_AT(3 + i);
    /* A bad checksum resets everything, matching @0x574e-0x5759. */
    if (WORD_AT(0) != game_config_checksum(&loaded)) {
        plat_free_big(raw.data);
        return config;
    }
#undef WORD_AT
    plat_free_big(raw.data);
    return loaded;
}

bool save_game_config(const char *path, const GameConfig *config)
{
    uint16_t words[CONFIG_WORDS];
    uint8_t raw[CONFIG_BYTES];
    unsigned i;
    to_words(config, words);
    words[0] = game_config_checksum(config);
    for (i = 0; i < CONFIG_WORDS; ++i) {
        raw[i * 2] = (uint8_t)(words[i] & 0xFF);
        raw[i * 2 + 1] = (uint8_t)((words[i] >> 8) & 0xFF);
    }
    return plat_write_file(path, raw, CONFIG_BYTES);
}
