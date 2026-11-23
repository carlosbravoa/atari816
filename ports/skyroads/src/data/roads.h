/* ROADS.LZS: the 31 roads (road 0 is the demo's), their gravity, fuel, oxygen, palette
 * and the 7-column grid of tile descriptors.
 * C translation: the descriptor catalog, dispatch_kind_counts and descriptor_count of the
 * C++ (summaries for the `summary` CLI and its tests, built with std::map/std::set) are
 * left out; nothing in the game reads them. */
#ifndef DATA_ROADS_H
#define DATA_ROADS_H

#include "data/byteio.h"

#define ROAD_COLUMNS 7u
typedef struct {
    uint16_t c[ROAD_COLUMNS];
} RoadRow;

typedef struct {
    uint16_t raw;
    uint8_t low_byte;
    uint8_t high_byte;
    uint8_t dispatch_kind;
    uint8_t dispatch_variant_low3;
    uint8_t high_flags;
} RoadDescriptor;

typedef struct {
    unsigned index;
    uint16_t offset;
    uint32_t compressed_size;
    uint16_t unpacked_size;
    uint16_t gravity;
    uint16_t fuel;
    uint16_t oxygen;
    Bytes palette_vga;
    uint8_t widths[3];
    Bytes raw_tiles;
    const RoadRow SR_FAR *rows;
    unsigned row_count;
} RoadEntry;

typedef struct {
    uint32_t source_len;
    RoadEntry SR_FAR *roads;
    unsigned road_count;
} RoadsArchive;

RoadDescriptor analyze_road_descriptor(uint16_t value);
RoadsArchive load_roads_lzs_bytes(const Bytes *data);
RoadsArchive load_roads_lzs_path(const char *path);

#endif
