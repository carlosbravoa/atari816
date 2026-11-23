/* TREKDAT.LZS: the road's precomputed perspective, eight records (one per eighth of a
 * tile of scroll), each a pointer table (13 rows x 24) into 0x410 shapes of horizontal
 * spans.
 *
 * C translation: the C++ kept the pointer table's shapes in a std::map and memoised the
 * chained ones (shape_ref / next_shape_offset_fast, its "RVSTACK" decode-once accessors).
 * The record is 0x410 shapes one after the other (expand_trekdat_record writes them so),
 * so here every shape is parsed once at load into an array in record order: a shape is an
 * index, the next shape is the next index, and the pointer table's entries are looked up
 * once (pointer_shape). The inspection helpers (total_span_count, pointer_min/max,
 * dos_pointer_layout's copy, shape_at_offset) became that table or were left out. */
#ifndef DATA_TREKDAT_H
#define DATA_TREKDAT_H

#include "data/byteio.h"

#define TREKDAT_POINTER_ROWS 13u
#define TREKDAT_POINTER_COLUMNS 24u
#define TREKDAT_POINTER_COUNT (TREKDAT_POINTER_ROWS * TREKDAT_POINTER_COLUMNS)
#define TREKDAT_POINTER_TABLE_BYTES (TREKDAT_POINTER_COUNT * 2u)
#define TREKDAT_DOS_DRAW_ROWS 11u
#define TREKDAT_DOS_DRAW_COLUMNS 4u
#define TREKDAT_DOS_POINTERS_PER_CELL 6u
#define TREKDAT_SHAPE_ROWS 0x410u
#define TREKDAT_SHAPE_BASE 10240u
#define TREKDAT_VIEWPORT_WIDTH 320u
#define TREKDAT_VIEWPORT_HEIGHT 200u

typedef struct {
    uint16_t x;
    uint16_t y;
    uint8_t width;
    uint8_t offset;
} TrekdatSpan;

typedef struct {
    uint16_t x0;
    uint16_t y0;
    uint16_t x1;
    uint16_t y1;
    uint16_t width;
    uint16_t height;
} TrekdatBbox;

typedef struct {
    uint16_t start_offset;
    uint16_t size;
    uint8_t color;
    uint32_t base_ptr;
    uint16_t span_count;
    uint16_t nonzero_padding_count;
    bool has_bbox;
    TrekdatBbox bbox;
    const TrekdatSpan SR_FAR *spans;
} TrekdatShape;

/* no shape (std::nullopt) */
#define TREKDAT_NO_SHAPE 0xFFFFu

typedef struct {
    unsigned index;
    uint32_t file_offset;
    uint32_t next_file_offset;
    uint32_t compressed_size;
    uint16_t load_buff_end;
    uint16_t bytes_to_read;
    uint16_t load_offset;
    uint8_t widths[3];
    Bytes expanded;
    uint16_t pointer_table[TREKDAT_POINTER_COUNT];
    /* C: every shape of the record, in order (see above) */
    TrekdatShape SR_FAR *shapes;
    unsigned shape_count;
    /* the shape index of each pointer_table entry */
    uint16_t pointer_shape[TREKDAT_POINTER_COUNT];
} TrekdatRecord;

/* the shape that starts at start_offset, or TREKDAT_NO_SHAPE (shape_ref returning
 * nullptr) */
uint16_t trekdat_shape_index(const TrekdatRecord SR_FAR *record, uint16_t start_offset);
/* next_shape_offset_fast, as an index: TREKDAT_NO_SHAPE when the next offset is past
 * the record (std::nullopt) */
uint16_t trekdat_next_shape(const TrekdatRecord SR_FAR *record, uint16_t shape_index);

typedef struct {
    uint32_t source_len;
    TrekdatRecord SR_FAR *records;
    unsigned record_count;
} TrekdatArchive;

TrekdatArchive load_trekdat_lzs_bytes(const Bytes *data);
TrekdatArchive load_trekdat_lzs_path(const char *path);

#endif
