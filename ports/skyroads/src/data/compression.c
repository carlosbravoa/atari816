#include "data/compression.h"

void (*decompress_store_hook)(uint32_t offset, const DecompressResult *result);
bool (*decompress_fetch_hook)(uint32_t offset, uint32_t expected_size,
                              DecompressResult *result);

/* Mirrors the reference `BitReader`: MSB-first within each byte. */
typedef struct {
    const Bytes *data_;
    uint32_t byte_offset_;
    uint8_t bit_offset_;
    bool eof_;          /* C: Error::unexpected_eof("compressed bitstream") was raised */
} BitReader;

/* Reads `count` bits MSB-first. Sets eof_ past the buffer (upstream threw UnexpectedEof),
 * which the caller turns into a clean stream end when size is unbounded. */
static uint32_t read_bits(BitReader *r, uint8_t count)
{
    uint32_t value = 0;
    uint8_t i;
    for (i = 0; i < count; ++i) {
        uint8_t bit;
        if (r->byte_offset_ >= r->data_->size) {
            r->eof_ = true;
            return 0;
        }
        bit = (uint8_t)((SR_BYTE(r->data_->data, r->byte_offset_) >> (7 - r->bit_offset_)) & 1u);
        value = (value << 1) | (uint32_t)bit;
        r->bit_offset_ += 1;
        if (r->bit_offset_ == 8) {
            r->bit_offset_ = 0;
            r->byte_offset_ += 1;
        }
    }
    return value;
}

static uint32_t bytes_consumed(const BitReader *r, uint32_t start_offset)
{
    const uint32_t extra = r->bit_offset_ != 0 ? 1 : 0;
    return (r->byte_offset_ + extra) - start_offset;
}

/* the growing output (std::vector::push_back) */
typedef struct {
    uint8_t SR_FAR *buf;
    uint32_t size;
    uint32_t cap;
} Out;

static void out_push(Out *o, uint8_t v)
{
    if (o->size >= o->cap)
        sr_fail("decompressed stream larger than %lu bytes", (unsigned long)o->cap);
    o->buf[o->size++] = v;
}

static void copy_from_history(Out *output, uint32_t distance, uint32_t count, uint32_t limit)
{
    uint32_t i;
    if (distance == 0 || distance > output->size)
        sr_fail("invalid back-reference distance %lu", (unsigned long)distance);
    for (i = 0; i < count; ++i) {
        uint32_t source_index;
        if (output->size >= limit)
            break;
        source_index = output->size - distance;
        out_push(output, output->buf[source_index]);
    }
}

DecompressResult decompress_stream(const Bytes *data, uint32_t offset,
                                   bool has_expected_size, uint32_t expected_size,
                                   CompressionWidths widths)
{
    const uint8_t width1 = widths.w1;
    const uint8_t width2 = widths.w2;
    const uint8_t width3 = widths.w3;
    BitReader reader;
    Out output;
    DecompressResult result;

    if (decompress_fetch_hook && has_expected_size &&
        decompress_fetch_hook(offset, expected_size, &result))
        return result;

    reader.data_ = data;
    reader.byte_offset_ = offset;
    reader.bit_offset_ = 0;
    reader.eof_ = false;
    /* C: one allocation of the final size (a stream is one object: at most 65,535 bytes) */
    output.cap = has_expected_size ? expected_size : 65535u;
    output.buf = output.cap ? (uint8_t SR_FAR *)plat_alloc(output.cap) : 0;
    output.size = 0;

    for (;;) {
        uint32_t prefix, distance, count, limit;
        uint8_t literal;
        if (has_expected_size && output.size >= expected_size)
            break;

        /* Unbounded streams end when the bitstream runs dry; every other
         * error (and any EOF on a sized stream) propagates, matching the
         * the reference design match arm. */
#define BITS(n, v) do { v = read_bits(&reader, (n)); if (reader.eof_) goto eof; } while (0)
        BITS(1, prefix);
        if (prefix == 0) {
            BITS(width2, distance);
            distance += 2;
            BITS(width1, count);
            count += 2;
            limit = has_expected_size ? expected_size : output.size + count;
            copy_from_history(&output, distance, count, limit);
            continue;
        }

        BITS(1, prefix);
        if (prefix == 0) {
            BITS(width3, distance);
            distance += 2 + ((uint32_t)1 << width2);
            BITS(width1, count);
            count += 2;
            limit = has_expected_size ? expected_size : output.size + count;
            copy_from_history(&output, distance, count, limit);
            continue;
        }

        BITS(8, prefix);
        literal = (uint8_t)prefix;
        out_push(&output, literal);
        continue;
eof:
        if (!has_expected_size)
            break;
        sr_fail("unexpected end of data: compressed bitstream");
#undef BITS
    }

    result.output.data = output.buf;
    result.output.size = output.size;
    result.consumed = bytes_consumed(&reader, offset);
    if (decompress_store_hook)
        decompress_store_hook(offset, &result);
    return result;
}
