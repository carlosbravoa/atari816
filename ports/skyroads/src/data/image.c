#include <string.h>

#include "data/image.h"
#include "data/compression.h"

/* C: the most frames an image-set archive (CMAP/PICT chunks) holds here; the shipped ones
 * have at most 11 */
#define IMAGE_SET_MAX_FRAMES 64

/* the reference design `u8::saturating_mul(4)` used to widen 6-bit VGA palette values. */
static uint8_t saturating_mul4(uint8_t value)
{
    const unsigned scaled = (unsigned)value * 4u;
    return scaled > 255u ? 255u : (uint8_t)scaled;
}

static bool starts_with(const Bytes *data, const char *tag)
{
    const uint32_t len = (uint32_t)strlen(tag);
    uint32_t i;
    if (data->size < len)
        return false;
    for (i = 0; i < len; ++i)
        if (at(data, i) != (uint8_t)tag[i])
            return false;
    return true;
}

static bool ident_is(const Bytes *data, uint32_t offset, const char *tag)
{
    if (offset + 4 > data->size)
        sr_fail("unexpected end of data: image chunk ident");
    return at(data, offset) == (uint8_t)tag[0] && at(data, offset + 1) == (uint8_t)tag[1] &&
           at(data, offset + 2) == (uint8_t)tag[2] && at(data, offset + 3) == (uint8_t)tag[3];
}

/* Returns the palette plus the number of bytes consumed after the 4-byte tag. */
static ImagePalette parse_cmap(const Bytes *data, uint32_t offset, uint32_t *consumed)
{
    uint32_t color_count, colors_start, colors_end, aux_end, index;
    ImagePalette palette;
    RgbColor SR_FAR *colors;

    if (offset >= data->size)
        sr_fail("unexpected end of data: CMAP count");
    color_count = at(data, offset);
    colors_start = offset + 1;
    colors_end = colors_start + color_count * 3;
    aux_end = colors_end + color_count * 2;
    if (aux_end > data->size)
        sr_fail("unexpected end of data: CMAP payload");

    colors = color_count ? (RgbColor SR_FAR *)plat_alloc(color_count * 3) : 0;
    for (index = 0; index < color_count; ++index) {
        const uint32_t base = colors_start + index * 3;
        colors[index] = rgb(saturating_mul4(at(data, base)), saturating_mul4(at(data, base + 1)),
                            saturating_mul4(at(data, base + 2)));
    }
    palette.colors = colors;
    palette.color_count = (unsigned)color_count;
    palette.aux_data = bytes_slice(data, colors_end, aux_end - colors_end);
    *consumed = 1 + color_count * 5;
    return palette;
}

/* Returns the frame plus bytes consumed after the 4-byte tag. */
static ImageFrame parse_pict(const Bytes *data, uint32_t offset, ImagePalette palette,
                             ImagePalette palette_start, uint32_t *consumed)
{
    uint16_t screen_offset, height, width, actual_height;
    CompressionWidths widths;
    uint32_t pixel_count;
    DecompressResult decoded;
    ImageFrame frame;

    if (offset + 9 > data->size)
        sr_fail("unexpected end of data: PICT header");

    screen_offset = read_u16(data, offset);
    height = read_u16(data, offset + 2);
    width = read_u16(data, offset + 4);
    widths.w1 = at(data, offset + 6);
    widths.w2 = at(data, offset + 7);
    widths.w3 = at(data, offset + 8);
    pixel_count = (uint32_t)(width < 1 ? 1 : width) * (uint32_t)(height < 1 ? 1 : height);
    decoded = decompress_stream(data, offset + 9, true, pixel_count, widths);
    actual_height = height == 0 ? 1 : height;

    frame.offset = screen_offset;
    frame.x_offset = (uint16_t)(screen_offset % SCREEN_WIDTH);
    frame.y_offset = (uint16_t)(screen_offset / SCREEN_WIDTH);
    frame.width = width;
    frame.height = actual_height;
    frame.pixels = decoded.output;
    frame.palette = palette;
    frame.palette_start = palette_start;
    frame.transparent_zero = true;
    *consumed = 9 + decoded.consumed;
    return frame;
}

static ImageArchive load_image_set_archive(const Bytes *data)
{
    uint32_t cursor = 0;
    bool have_palette = false;
    ImagePalette current_palette, previous_palette;
    /* A PICT preceded by two CMAPs takes the earlier one as its starting palette. */
    unsigned palettes_since_frame = 0;
    ImageFrameList SR_FAR *frames =
        (ImageFrameList SR_FAR *)plat_alloc(IMAGE_SET_MAX_FRAMES * sizeof(ImageFrameList));
    unsigned frame_count = 0;
    ImageArchive archive;

    memset(&current_palette, 0, sizeof current_palette);
    memset(&previous_palette, 0, sizeof previous_palette);
    while (cursor < data->size) {
        uint32_t consumed;
        if (ident_is(data, cursor, "CMAP")) {
            ImagePalette palette = parse_cmap(data, cursor + 4, &consumed);
            previous_palette = current_palette;
            current_palette = palette;
            have_palette = true;
            palettes_since_frame += 1;
            cursor += 4 + consumed;
        } else if (ident_is(data, cursor, "PICT")) {
            ImageFrame SR_FAR *fragment;
            if (!have_palette)
                sr_fail("PICT chunk appeared before CMAP");
            if (frame_count == IMAGE_SET_MAX_FRAMES)
                sr_fail("image archive has more than %u pictures", IMAGE_SET_MAX_FRAMES);
            fragment = (ImageFrame SR_FAR *)plat_alloc(sizeof(ImageFrame));
            *fragment = parse_pict(data, cursor + 4, current_palette,
                                   palettes_since_frame >= 2 ? previous_palette
                                                             : current_palette,
                                   &consumed);
            frames[frame_count].fragments = fragment;
            frames[frame_count].count = 1;
            frame_count++;
            palettes_since_frame = 0;
            cursor += 4 + consumed;
        } else {
            sr_fail("unexpected image chunk at offset %lu", (unsigned long)cursor);
        }
    }

    archive.source_len = data->size;
    archive.kind.tag = IMAGE_ARCHIVE_IMAGE_SET;
    archive.kind.declared_frame_count = 0;
    archive.frames = frames;
    archive.frame_count = frame_count;
    return archive;
}

static ImageArchive load_anim_archive(const Bytes *data)
{
    uint16_t declared_frame_count;
    uint32_t cursor, consumed;
    ImagePalette palette;
    ImageFrameList SR_FAR *frames;
    unsigned frame_index;
    ImageArchive archive;

    if (data->size < 10)
        sr_fail("ANIM archive is truncated");
    declared_frame_count = read_u16(data, 4);
    cursor = 6;
    if (!ident_is(data, cursor, "CMAP"))
        sr_fail("ANIM archive does not contain CMAP after header");
    palette = parse_cmap(data, cursor + 4, &consumed);
    cursor += 4 + consumed;

    frames = (ImageFrameList SR_FAR *)plat_alloc(
        (uint32_t)SR_MAX(declared_frame_count, 1) * sizeof(ImageFrameList));
    for (frame_index = 0; frame_index < declared_frame_count; ++frame_index) {
        unsigned part_count, p;
        ImageFrame SR_FAR *fragments;
        if (cursor + 2 > data->size)
            sr_fail("ANIM frame %u is truncated", frame_index);
        part_count = read_u16(data, cursor);
        cursor += 2;
        fragments = part_count ? (ImageFrame SR_FAR *)plat_alloc(
                                     (uint32_t)part_count * sizeof(ImageFrame))
                               : 0;
        for (p = 0; p < part_count; ++p) {
            uint32_t pict_consumed;
            if (!ident_is(data, cursor, "PICT"))
                sr_fail("ANIM frame %u expected PICT", frame_index);
            fragments[p] = parse_pict(data, cursor + 4, palette, palette, &pict_consumed);
            cursor += 4 + pict_consumed;
        }
        frames[frame_index].fragments = fragments;
        frames[frame_index].count = part_count;
    }

    archive.source_len = data->size;
    archive.kind.tag = IMAGE_ARCHIVE_ANIMATION;
    archive.kind.declared_frame_count = declared_frame_count;
    archive.frames = frames;
    archive.frame_count = declared_frame_count;
    return archive;
}

ImageArchive load_image_archive_bytes(const Bytes *data)
{
    if (starts_with(data, "ANIM"))
        return load_anim_archive(data);
    if (starts_with(data, "CMAP"))
        return load_image_set_archive(data);
    sr_fail("image archive does not begin with CMAP or ANIM");
    return load_image_set_archive(data); /* (not reached) */
}

ImageArchive load_image_archive_path(const char *path)
{
    Bytes data = read_file(path);
    ImageArchive a = load_image_archive_bytes(&data);
    free_bytes(&data);
    return a;
}
