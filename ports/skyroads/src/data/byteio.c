#include "data/byteio.h"
#include "platform.h"

Bytes read_file(const char *path)
{
    Bytes data;
    if (!plat_read_file(path, &data))
        sr_fail("failed to open %s", path);
    return data;
}

void free_bytes(Bytes *b)
{
    if (b->data)
        plat_free_big(b->data);
    b->data = 0;
    b->size = 0;
}

uint16_t read_u16(const Bytes *data, uint32_t offset)
{
    if (offset + 2 > data->size)
        sr_fail("unexpected end of data: u16");
    return (uint16_t)(SR_BYTE(data->data, offset) |
                      ((uint16_t)SR_BYTE(data->data, offset + 1) << 8));
}

uint8_t at(const Bytes *data, uint32_t offset)
{
    if (offset >= data->size)
        sr_fail("index %lu out of range (%lu bytes)", (unsigned long)offset,
                (unsigned long)data->size);
    return SR_BYTE(data->data, offset);
}

Bytes bytes_new(uint32_t n)
{
    Bytes b;
    b.data = n ? (uint8_t SR_FAR *)plat_alloc(n) : 0;
    b.size = n;
    return b;
}

Bytes bytes_slice(const Bytes *data, uint32_t offset, uint32_t n)
{
    Bytes b = bytes_new(n);
    if (offset + n > data->size)
        sr_fail("unexpected end of data: slice");
    sr_copy_from(b.data, data, offset, n);
    return b;
}
