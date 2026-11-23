#include "data/roads.h"
#include "data/compression.h"

RoadDescriptor analyze_road_descriptor(uint16_t value)
{
    const uint8_t low_byte = (uint8_t)(value & 0x00FF);
    const uint8_t high_byte = (uint8_t)(value >> 8);
    RoadDescriptor d;
    d.raw = value;
    d.low_byte = low_byte;
    d.high_byte = high_byte;
    d.dispatch_kind = high_byte & 0x0F;
    d.dispatch_variant_low3 = high_byte & 0x07;
    d.high_flags = high_byte >> 4;
    return d;
}

RoadsArchive load_roads_lzs_bytes(const Bytes *data)
{
    const uint16_t first_offset = read_u16(data, 0);
    unsigned entry_count, index;
    RoadEntry SR_FAR *roads;
    RoadsArchive archive;

    if (first_offset % 4 != 0)
        sr_fail("unexpected ROADS header size %u", first_offset);

    entry_count = first_offset / 4;
    roads = (RoadEntry SR_FAR *)plat_alloc((uint32_t)SR_MAX(entry_count, 1) * sizeof(RoadEntry));
    for (index = 0; index < entry_count; ++index) {
        const uint32_t offset = read_u16(data, index * 4);
        const uint16_t unpacked_size = read_u16(data, index * 4 + 2);
        const uint32_t next_offset =
            (index + 1 < entry_count) ? read_u16(data, (index + 1) * 4) : data->size;
        uint32_t blob_size, value_count, base;
        CompressionWidths widths;
        DecompressResult decoded;
        Bytes raw_tiles;
        RoadRow SR_FAR *rows;
        RoadEntry road;

        if (next_offset < offset || next_offset > data->size)
            sr_fail("road %u has invalid slice bounds", index);
        /* C: the C++ copied the road's slice (road_blob) and read it from 0; here the
         * same reads at offset + n */
        blob_size = next_offset - offset;
        if (blob_size < 225)
            sr_fail("road %u is too small to contain metadata and compression widths", index);

        road.gravity = read_u16(data, offset + 0);
        road.fuel = read_u16(data, offset + 2);
        road.oxygen = read_u16(data, offset + 4);
        road.palette_vga = bytes_slice(data, offset + 6, 222 - 6);
        road.widths[0] = at(data, offset + 222);
        road.widths[1] = at(data, offset + 223);
        road.widths[2] = at(data, offset + 224);
        widths.w1 = road.widths[0];
        widths.w2 = road.widths[1];
        widths.w3 = road.widths[2];
        /* the C++ decoded from the slice: its end of data is the blob's end. A sized
         * stream never reads past what it needs, so the whole buffer gives the same
         * bytes; the stream's file offset is offset + 225. */
        decoded = decompress_stream(data, offset + 225, true, unpacked_size, widths);
        raw_tiles = decoded.output;

        if (raw_tiles.size % 2 != 0)
            sr_fail("road %u decompressed to an odd number of bytes", index);
        value_count = raw_tiles.size / 2;
        if (value_count % ROAD_COLUMNS != 0)
            sr_fail("road %u decompressed to %lu cells, not a multiple of 7", index,
                    (unsigned long)value_count);

        road.index = index;
        road.offset = (uint16_t)offset;
        road.compressed_size = blob_size;
        road.unpacked_size = unpacked_size;

        road.row_count = (unsigned)(value_count / ROAD_COLUMNS);
        rows = road.row_count ? (RoadRow SR_FAR *)plat_alloc((uint32_t)road.row_count *
                                                              sizeof(RoadRow))
                              : 0;
        /* (C, round 2: the tiles are little-endian u16s, as RoadRow holds them on the
         * Atari816 and the PC: one copy, not a loop of 2 bytes a tile) */
        if (road.row_count)
            sr_copy_from(rows, &raw_tiles, 0, (uint32_t)road.row_count * sizeof(RoadRow));
        (void)base;
        road.rows = rows;
        road.raw_tiles = raw_tiles;
        roads[index] = road;
    }

    archive.source_len = data->size;
    archive.roads = roads;
    archive.road_count = entry_count;
    return archive;
}

RoadsArchive load_roads_lzs_path(const char *path)
{
    Bytes data = read_file(path);
    RoadsArchive a = load_roads_lzs_bytes(&data);
    free_bytes(&data);
    return a;
}
