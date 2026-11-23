#include "data/demo.h"

DemoRecording load_demo_rec_bytes(const Bytes *data)
{
    DemoRecording demo;
    DemoInput SR_FAR *entries;
    unsigned index;

    demo.source_len = data->size;
    demo.raw = bytes_slice(data, 0, data->size);
    entries = (DemoInput SR_FAR *)plat_alloc((uint32_t)SR_MAX(data->size, 1) * sizeof(DemoInput));

    for (index = 0; index < data->size; ++index) {
        const uint8_t value = at(data, index);
        DemoInput input;
        /* Two-bit fields decode to {-1, 0, 1}; jump is a single bit. */
        input.index = (uint16_t)index;
        input.byte = value;
        input.accelerate_decelerate = (int8_t)((int8_t)(value & 0x03) - 1);
        input.left_right = (int8_t)((int8_t)((value >> 2) & 0x03) - 1);
        input.jump = ((value >> 4) & 0x01) != 0;
        input.tile_position_fp16 = (uint32_t)index * DEMO_TILE_POSITION_STEP_FP16;
        entries[index] = input;
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
