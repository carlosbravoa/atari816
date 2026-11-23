/* CMAP/PICT image containers and the ANIM wrapper. `ImageArchiveKind` is a
 * payload-carrying the reference design enum; here it is a small tagged struct. */
#ifndef DATA_IMAGE_H
#define DATA_IMAGE_H

#include "data/byteio.h"

#define SCREEN_WIDTH 320u
#define SCREEN_HEIGHT 200u

typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
} RgbColor;

static inline RgbColor rgb(uint8_t r, uint8_t g, uint8_t b)
{
    RgbColor c;
    c.r = r;
    c.g = g;
    c.b = b;
    return c;
}

static inline bool rgb_eq(RgbColor a, RgbColor b)
{
    return a.r == b.r && a.g == b.g && a.b == b.b;
}

/* std::vector<RgbColor> colors + aux_data */
typedef struct {
    const RgbColor SR_FAR *colors;
    unsigned color_count;
    Bytes aux_data;
} ImagePalette;

typedef struct {
    uint16_t offset;
    uint16_t x_offset;
    uint16_t y_offset;
    uint16_t width;
    uint16_t height;
    Bytes pixels;
    ImagePalette palette;
    /* When a PICT is preceded by TWO CMAPs, the game shows the picture in the first
     * one and then fades the hardware palette across to the second (the intro applies
     * it at @0x483a / @0x49a8 and fades with @0x4315). With a single CMAP the two are
     * identical. */
    ImagePalette palette_start;
    bool transparent_zero;
} ImageFrame;

/* the reference design: `enum ImageArchiveKind { ImageSet, Animation { declared_frame_count } }` */
typedef enum { IMAGE_ARCHIVE_IMAGE_SET, IMAGE_ARCHIVE_ANIMATION } ImageArchiveTag;
typedef struct {
    ImageArchiveTag tag;
    uint16_t declared_frame_count; /* valid only when tag == Animation */
} ImageArchiveKind;

/* one frame: a list of fragments (image-set frames hold a single one) */
typedef struct {
    ImageFrame SR_FAR *fragments;
    unsigned count;
} ImageFrameList;

typedef struct {
    uint32_t source_len;
    ImageArchiveKind kind;
    /* Each frame is a list of fragments (image-set frames hold a single one). */
    ImageFrameList SR_FAR *frames;
    unsigned frame_count;
} ImageArchive;

/* frames[i] has at least one fragment: its first (C: `!frames[i].empty()` then
 * `frames[i].front()`) */
static inline bool archive_has_frame(const ImageArchive *a, unsigned i)
{
    return i < a->frame_count && a->frames[i].count > 0;
}
static inline const ImageFrame SR_FAR *archive_front(const ImageArchive *a, unsigned i)
{
    return &a->frames[i].fragments[0];
}

ImageArchive load_image_archive_bytes(const Bytes *data);
ImageArchive load_image_archive_path(const char *path);

#endif
