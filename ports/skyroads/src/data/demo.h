/* DEMO.REC: one input byte per 0x666 of z.
 * C translation: the per-value counts (accelerate_decelerate_counts, left_right_counts,
 * jump_counts: summaries for the CLI) are left out. */
#ifndef DATA_DEMO_H
#define DATA_DEMO_H

#include "data/byteio.h"

/* 0x10000 / 0x666 indexing factor: one demo byte per fixed-point tile step. */
#define DEMO_TILE_POSITION_STEP_FP16 ((uint32_t)0x0666)

typedef struct {
    uint16_t index;
    uint8_t byte;
    int8_t accelerate_decelerate;
    int8_t left_right;
    bool jump;
    uint32_t tile_position_fp16;
} DemoInput;

typedef struct {
    uint32_t source_len;
    Bytes raw;
    const DemoInput SR_FAR *entries;
    unsigned entry_count;
} DemoRecording;

DemoRecording load_demo_rec_bytes(const Bytes *data);
DemoRecording load_demo_rec_path(const char *path);

#endif
