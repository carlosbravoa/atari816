/* Shared little-endian readers and file slurp. The reference design modules each defined a
 * private `read_u16`; here they share one helper with identical bounds/EOF
 * semantics.
 * (C translation of data/byteio.hpp: Bytes is in sr.h.) */
#ifndef DATA_BYTEIO_H
#define DATA_BYTEIO_H

#include "sr.h"

/* Reads a whole file into memory. Fails (Error::Io) when it cannot. The buffer comes from
 * plat_alloc_big: give it back with free_bytes. */
Bytes read_file(const char *path);
void free_bytes(Bytes *b);

/* Little-endian u16 with the same "u16" EOF context string the reference helpers use. */
uint16_t read_u16(const Bytes *data, uint32_t offset);

/* Byte accessor with the same panic-on-out-of-range contract as the reference design
 * indexing. */
uint8_t at(const Bytes *data, uint32_t offset);

/* A new Bytes of n bytes (plat_alloc), and a copy of data[offset .. offset + n) */
Bytes bytes_new(uint32_t n);
Bytes bytes_slice(const Bytes *data, uint32_t offset, uint32_t n);

#endif
