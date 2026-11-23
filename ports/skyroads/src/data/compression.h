/* The shared SkyRoads LZ bitstream decoder. This is the single most
 * fidelity-critical routine in the whole port: every asset format funnels
 * through it, so the bit ordering, back-reference math, and EOF behaviour must
 * match the reference design (and thus the DOS build) exactly. */
#ifndef DATA_COMPRESSION_H
#define DATA_COMPRESSION_H

#include "data/byteio.h"

typedef struct {
    Bytes output;
    uint32_t consumed;
} DecompressResult;

typedef struct {
    uint8_t w1;
    uint8_t w2;
    uint8_t w3;
} CompressionWidths;

/* `expected_size` maps to the reference's `Option<usize>`: when has_expected_size,
 * decoding stops once the output reaches that length; when not, decoding runs until the
 * bitstream is exhausted (an EOF mid-token ends the stream cleanly instead of erroring). */
DecompressResult decompress_stream(const Bytes *data, uint32_t offset,
                                   bool has_expected_size, uint32_t expected_size,
                                   CompressionWidths widths);

/* C translation: two hooks around the decoder (not in the C++). A machine too slow to
 * decode at load time (the Atari816: about 10 s for ROADS.LZS alone) gets every stream
 * decoded beforehand, by this same decoder on a PC: `store` sees each stream as it is
 * decoded (in the order the loaders ask for them), `fetch` hands one back instead of
 * decoding it. NULL (the default): decode. */
extern void (*decompress_store_hook)(uint32_t offset, const DecompressResult *result);
extern bool (*decompress_fetch_hook)(uint32_t offset, uint32_t expected_size,
                                     DecompressResult *result);

#endif
