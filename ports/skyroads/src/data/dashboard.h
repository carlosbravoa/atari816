/* OXY_DISP.DAT, FUL_DISP.DAT, SPEED.DAT: the gauges' segments. */
#ifndef DATA_DASHBOARD_H
#define DATA_DASHBOARD_H

#include "data/image.h"

/* Index 0 is transparent; 1/2 are the two purple HUD shades. */
extern const RgbColor DASHBOARD_COLORS[3];

typedef struct {
    uint16_t position;
    uint16_t x;
    uint16_t y;
    uint8_t width;
    uint8_t height;
    Bytes pixels;
} HudFragment;

typedef struct {
    uint32_t source_len;
    uint16_t header_words;
    const HudFragment SR_FAR *fragments;
    unsigned fragment_count;
} HudFragmentPack;

HudFragmentPack load_dashboard_dat_bytes(const Bytes *data);
HudFragmentPack load_dashboard_dat_path(const char *path);

#endif
