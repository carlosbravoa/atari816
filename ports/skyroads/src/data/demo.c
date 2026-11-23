#include <string.h>

#include "data/demo.h"
#include "platform.h"

DemoRecording load_demo_rec_bytes(const Bytes *data)
{
    DemoRecording demo;
    DemoInput SR_FAR *entries;
    unsigned index;

    demo.source_len = data->size;
    demo.raw = bytes_slice(data, 0, data->size);
    entries = (DemoInput SR_FAR *)plat_alloc((uint32_t)SR_MAX(data->size, 1) * sizeof(DemoInput));

    {
        /* (C, round 2: the bytes from a near copy, the entry's fields written in place, the
         * position summed: the same entries, about 10 times sooner on the Atari816) */
        uint8_t buf[32];
        DemoInput part[32];
        uint32_t pos = 0;
        for (index = 0; index < data->size; ++index) {
            uint8_t value;
            DemoInput *e = &part[index & 31u];
            if ((index & 31u) == 0)
                sr_copy_from(buf, data, index, SR_MIN(32u, (unsigned)(data->size - index)));
            value = buf[index & 31u];
            /* Two-bit fields decode to {-1, 0, 1}; jump is a single bit. */
            memset(e, 0, sizeof *e);
            e->index = (uint16_t)index;
            e->byte = value;
            e->accelerate_decelerate = (int8_t)((int8_t)(value & 0x03) - 1);
            e->left_right = (int8_t)((int8_t)((value >> 2) & 0x03) - 1);
            e->jump = ((value >> 4) & 0x01) != 0;
            e->tile_position_fp16 = pos;    /* index * DEMO_TILE_POSITION_STEP_FP16 */
            pos += DEMO_TILE_POSITION_STEP_FP16;
            if ((index & 31u) == 31u || index + 1 == data->size)
                plat_copy((uint8_t SR_FAR *)&entries[index & ~31u], (const uint8_t *)part,
                          ((index & 31u) + 1u) * (unsigned)sizeof(DemoInput));
        }
    }
    demo.entries = entries;
    demo.entry_count = (unsigned)data->size;
    return demo;
}

DemoRecording load_demo_rec_path(const char *path)
{
    Bytes data = read_file(path);
    DemoRecording d = load_demo_rec_bytes(&data);
    free_bytes(&data);
    return d;
}
