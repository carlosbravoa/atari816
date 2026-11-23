#include "data/dashboard.h"

const RgbColor DASHBOARD_COLORS[3] = {{0, 0, 0}, {97, 0, 93}, {113, 0, 101}};

HudFragmentPack load_dashboard_dat_bytes(const Bytes *data)
{
    uint16_t probe, header_words;
    uint32_t cursor;
    unsigned pass, count = 0;
    HudFragment SR_FAR *fragments = 0;
    HudFragmentPack pack;

    if (data->size < 4)
        sr_fail("dashboard DAT is too small to contain a header");

    probe = read_u16(data, 2);
    header_words = (probe == 0x2C) ? 0x22 : 0x0A;
    if ((uint32_t)header_words * 2 > data->size)
        sr_fail("dashboard DAT header exceeds source length");

    pack.source_len = data->size;
    pack.header_words = header_words;

    /* C: two passes, the first counting (the C++ pushed onto a vector) */
    for (pass = 0; pass < 2; ++pass) {
        cursor = (uint32_t)header_words * 2;
        count = 0;
        while (cursor < data->size) {
            uint16_t position;
            uint8_t width, height;
            uint32_t pixel_count;
            if (cursor + 4 > data->size)
                sr_fail("dashboard DAT fragment header is truncated");
            position = read_u16(data, cursor);
            width = at(data, cursor + 2);
            height = at(data, cursor + 3);
            cursor += 4;
            pixel_count = (uint32_t)width * (uint32_t)height;
            if (cursor + pixel_count > data->size)
                sr_fail("dashboard DAT fragment payload is truncated");
            if (pass == 1) {
                HudFragment f;
                f.position = position;
                f.x = (uint16_t)(position % SCREEN_WIDTH);
                f.y = (uint16_t)(position / SCREEN_WIDTH);
                f.width = width;
                f.height = height;
                f.pixels = bytes_slice(data, cursor, pixel_count);
                fragments[count] = f;
            }
            count++;
            cursor += pixel_count;
        }
        if (pass == 0)
            fragments = (HudFragment SR_FAR *)plat_alloc((uint32_t)SR_MAX(count, 1) *
                                                         sizeof(HudFragment));
    }
    pack.fragments = fragments;
    pack.fragment_count = count;
    return pack;
}

HudFragmentPack load_dashboard_dat_path(const char *path)
{
    Bytes data = read_file(path);
    HudFragmentPack p = load_dashboard_dat_bytes(&data);
    free_bytes(&data);
    return p;
}
