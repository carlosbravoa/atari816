#include "data/trekdat.h"
#include "data/compression.h"

static Bytes expand_trekdat_record(uint16_t load_buff_end, const Bytes *payload,
                                   uint16_t *load_offset_out)
{
    /* C: the C++ built `working` = load_offset zero bytes + the payload and read it from
     * src_ptr = load_offset on; that is the payload read from 0, which is what this does */
    uint16_t load_offset, src, row;
    const uint8_t SR_FAR *pl = payload->data;
    uint16_t psize;
    uint8_t SR_FAR *o;
    Bytes output;
    uint16_t n = 0;

    if (payload->size > load_buff_end)
        sr_fail("TREKDAT record expands to a negative load offset");
    load_offset = (uint16_t)(load_buff_end - payload->size);
    psize = (uint16_t)payload->size;
    output = bytes_new(load_buff_end);
    o = output.data;

    if (TREKDAT_POINTER_TABLE_BYTES > payload->size)
        sr_fail("TREKDAT record is too short for its pointer table");
    for (src = 0; src < TREKDAT_POINTER_TABLE_BYTES; ++src)
        o[n++] = pl[src];

#define OUT(v) do { if (n >= load_buff_end) sr_fail("TREKDAT expanded size mismatch"); \
                    o[n++] = (v); } while (0)
    for (row = 0; row < TREKDAT_SHAPE_ROWS; ++row) {
        unsigned k;
        if ((uint32_t)src + 3 > psize)
            sr_fail("TREKDAT record ended while copying shape headers");
        for (k = 0; k < 3; ++k)
            OUT(pl[src + k]);
        src += 3;

        for (;;) {
            uint8_t value;
            if (src >= psize)
                sr_fail("TREKDAT record ended while copying shape spans");
            value = pl[src];
            OUT(value);
            src += 1;
            if (value == 0xFF)
                break;
            if (src >= psize)
                sr_fail("TREKDAT record ended while copying span width");
            OUT(pl[src]);
            src += 1;
            OUT(0);
        }
    }
#undef OUT

    if (n != load_buff_end)
        sr_fail("TREKDAT expanded size mismatch");
    *load_offset_out = load_offset;
    return output;
}

static void parse_pointer_table(const Bytes *expanded, unsigned record_index,
                                uint16_t SR_FAR *pointer_table)
{
    uint32_t entry_offset;
    for (entry_offset = 0; entry_offset < TREKDAT_POINTER_TABLE_BYTES; entry_offset += 2) {
        const uint16_t pointer = read_u16(expanded, entry_offset);
        if ((uint32_t)pointer < TREKDAT_POINTER_TABLE_BYTES)
            sr_fail("TREKDAT record %u contains a pointer into the table area", record_index);
        if ((uint32_t)pointer >= expanded->size)
            sr_fail("TREKDAT record %u contains an out-of-range pointer", record_index);
        pointer_table[entry_offset / 2] = pointer;
    }
}

/* parse_trekdat_shape; false where the C++ threw (the shape does not parse).
 * C: x = ptr2 % 320, y = ptr2 / 320 of ptr2 = base + 320 k - offset are kept as they go
 * (the base's row and column once, then one row a span; an offset below 256 moves the
 * column back by less than a row), not divided each time: a 32-bit divide is a call of a
 * thousand cycles on the 65816. The same numbers. */
static bool parse_trekdat_shape(const Bytes *expanded, uint16_t start_offset,
                                TrekdatShape *shape)
{
    const uint16_t start = start_offset;
    const uint8_t SR_FAR *e = expanded->data;
    const uint16_t size = (uint16_t)expanded->size;
    uint16_t cursor, pass, base_x, base_row;
    uint32_t base_ptr;
    uint16_t min_x = TREKDAT_VIEWPORT_WIDTH, max_x = 0;
    uint16_t min_y = TREKDAT_VIEWPORT_HEIGHT, max_y = 0;
    bool saw_any_span = false;
    unsigned nonzero_padding_count = 0, span_count = 0;
    TrekdatSpan SR_FAR *spans = 0;

    if ((uint32_t)start + 3 > expanded->size)
        return false;                   /* "TREKDAT shape offset is out of range" */

    base_ptr = TREKDAT_SHAPE_BASE + (uint16_t)(e[start + 1] | ((uint16_t)e[start + 2] << 8));
    base_row = (uint16_t)(base_ptr / TREKDAT_VIEWPORT_WIDTH);
    base_x = (uint16_t)(base_ptr % TREKDAT_VIEWPORT_WIDTH);
    /* C: two passes, the first counting the spans (the C++ pushed onto a vector) */
    for (pass = 0; pass < 2; ++pass) {
        uint16_t row = base_row;
        cursor = start + 3;
        span_count = 0;
        for (;;) {
            uint8_t offset, width, padding;
            uint16_t x, y;
            if (cursor >= size)
                return false;           /* "TREKDAT shape is truncated" */
            offset = e[cursor];
            cursor += 1;
            if (offset == 0xFF)
                break;
            if (cursor + 2 > size)
                return false;           /* "TREKDAT span is truncated" */
            width = e[cursor];
            padding = e[cursor + 1];
            cursor += 2;
            /* (ptr < offset: never, ptr >= 10240) */
            if (offset <= base_x) {
                x = (uint16_t)(base_x - offset);
                y = row;
            } else {
                x = (uint16_t)(base_x + TREKDAT_VIEWPORT_WIDTH - offset);
                y = (uint16_t)(row - 1);
            }
            if (pass == 1) {
                spans[span_count].x = x;
                spans[span_count].y = y;
                spans[span_count].width = width;
                spans[span_count].offset = offset;
                if (padding != 0)
                    nonzero_padding_count += 1;
                if (width > 0) {
                    const uint16_t x1 = (uint16_t)(x + width - 1);
                    if (!saw_any_span) {
                        min_x = x;
                        max_x = x1;
                        min_y = y;
                        max_y = y;
                        saw_any_span = true;
                    } else {
                        min_x = SR_MIN(min_x, x);
                        max_x = SR_MAX(max_x, x1);
                        min_y = SR_MIN(min_y, y);
                        max_y = SR_MAX(max_y, y);
                    }
                }
            }
            span_count += 1;
            row += 1;                   /* ptr += TREKDAT_VIEWPORT_WIDTH */
        }
        if (pass == 0 && span_count)
            spans = (TrekdatSpan SR_FAR *)plat_alloc((uint32_t)span_count * sizeof(TrekdatSpan));
    }

    shape->start_offset = start_offset;
    shape->size = (uint16_t)(cursor - start);
    shape->color = e[start];
    shape->base_ptr = base_ptr;
    shape->span_count = (uint16_t)span_count;
    shape->nonzero_padding_count = (uint16_t)nonzero_padding_count;
    shape->has_bbox = saw_any_span;
    if (saw_any_span) {
        shape->bbox.x0 = min_x;
        shape->bbox.y0 = min_y;
        shape->bbox.x1 = max_x;
        shape->bbox.y1 = max_y;
        shape->bbox.width = (uint16_t)(max_x - min_x + 1);
        shape->bbox.height = (uint16_t)(max_y - min_y + 1);
    }
    shape->spans = spans;
    return true;
}

uint16_t trekdat_shape_index(const TrekdatRecord SR_FAR *record, uint16_t start_offset)
{
    unsigned lo = 0, hi = record->shape_count;
    while (lo < hi) {
        const unsigned mid = (lo + hi) / 2;
        const uint16_t s = record->shapes[mid].start_offset;
        if (s == start_offset)
            return (uint16_t)mid;
        if (s < start_offset)
            lo = mid + 1;
        else
            hi = mid;
    }
    return TREKDAT_NO_SHAPE;
}

uint16_t trekdat_next_shape(const TrekdatRecord SR_FAR *record, uint16_t shape_index)
{
    const TrekdatShape SR_FAR *shape = &record->shapes[shape_index];
    const uint32_t next_offset = (uint32_t)shape->start_offset + shape->size;
    if (next_offset + 3 > record->expanded.size)
        return TREKDAT_NO_SHAPE;
    /* the shapes are consecutive: the next offset is the next shape's start */
    return shape_index + 1 < record->shape_count ? (uint16_t)(shape_index + 1)
                                                 : TREKDAT_NO_SHAPE;
}

TrekdatArchive load_trekdat_lzs_bytes(const Bytes *data)
{
    /* C: at most 8 records here (the shipped file has 8) */
    enum { MAX_RECORDS = 16 };
    TrekdatRecord SR_FAR *records;
    uint32_t offset = 0;
    unsigned record_index = 0;
    TrekdatArchive archive;

    if (data->size < 7)
        sr_fail("TREKDAT.LZS is too small to contain the observed TREKDAT header");
    records = (TrekdatRecord SR_FAR *)plat_alloc(MAX_RECORDS * sizeof(TrekdatRecord));

    while (offset < data->size) {
        TrekdatRecord SR_FAR *record;
        uint16_t load_buff_end, bytes_to_read, load_offset, pos;
        CompressionWidths widths;
        DecompressResult decoded;
        Bytes expanded;
        unsigned i;

        if (offset + 7 > data->size)
            sr_fail("TREKDAT record %u is truncated", record_index);
        if (record_index == MAX_RECORDS)
            sr_fail("TREKDAT.LZS has more than %u records", MAX_RECORDS);
        record = &records[record_index];
        load_buff_end = read_u16(data, offset);
        bytes_to_read = read_u16(data, offset + 2);
        widths.w1 = at(data, offset + 4);
        widths.w2 = at(data, offset + 5);
        widths.w3 = at(data, offset + 6);
        decoded = decompress_stream(data, offset + 7, true, bytes_to_read, widths);
        expanded = expand_trekdat_record(load_buff_end, &decoded.output, &load_offset);
        parse_pointer_table(&expanded, record_index, record->pointer_table);

        record->index = record_index;
        record->file_offset = offset;
        record->next_file_offset = offset + 7 + decoded.consumed;
        record->compressed_size = record->next_file_offset - offset;
        record->load_buff_end = load_buff_end;
        record->bytes_to_read = bytes_to_read;
        record->load_offset = load_offset;
        record->widths[0] = widths.w1;
        record->widths[1] = widths.w2;
        record->widths[2] = widths.w3;
        record->expanded = expanded;

        /* every shape, in order */
        record->shapes = (TrekdatShape SR_FAR *)plat_alloc(TREKDAT_SHAPE_ROWS * sizeof(TrekdatShape));
        record->shape_count = 0;
        pos = TREKDAT_POINTER_TABLE_BYTES;
        while (record->shape_count < TREKDAT_SHAPE_ROWS) {
            TrekdatShape shape;
            if (!parse_trekdat_shape(&expanded, pos, &shape))
                break;
            record->shapes[record->shape_count++] = shape;
            pos = (uint16_t)(pos + shape.size);
        }
        for (i = 0; i < TREKDAT_POINTER_COUNT; ++i) {
            record->pointer_shape[i] = trekdat_shape_index(record, record->pointer_table[i]);
            /* the C++ parsed the pointer table's shapes at load and threw if one did
             * not parse */
            if (record->pointer_shape[i] == TREKDAT_NO_SHAPE)
                sr_fail("TREKDAT record %u: pointer %u is not a shape's start", record_index,
                        record->pointer_table[i]);
        }

        offset = record->next_file_offset;
        record_index += 1;
    }

    archive.source_len = data->size;
    archive.records = records;
    archive.record_count = record_index;
    return archive;
}

TrekdatArchive load_trekdat_lzs_path(const char *path)
{
    Bytes data = read_file(path);
    TrekdatArchive a = load_trekdat_lzs_bytes(&data);
    free_bytes(&data);
    return a;
}
