/* sr.h - what every file of the C translation shares: fixed-width types, the far
 * qualifier, the byte buffer, failure.
 *
 * The C++ original (SDL-skyroads) keeps assets in std::vector and reports malformed data
 * by throwing data::Error. In C:
 *   - a byte buffer is `Bytes` (a pointer and a size); the loaders read it through
 *     `at()` and `read_u16()` exactly where the C++ read `data[i]` / `read_u16(data, i)`;
 *   - asset memory comes from the platform (`plat_alloc`), and on a machine with 16-bit
 *     data pointers (the Atari816, cc816) it lives in other 64 KB banks: every pointer to
 *     asset data is `SR_FAR` (`__far` there, nothing on a PC);
 *   - an Error that upstream lets reach main ends the program: `sr_fail()` prints it as
 *     upstream's main did ("error: ...") and exits. The one place that CATCHES an error
 *     (the decoder's end of stream, a TREKDAT shape that does not parse) tests a result
 *     instead.
 */
#ifndef SR_H
#define SR_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#if defined(__CC816__)
#define SR_FAR __far
#else
#define SR_FAR
#endif

/* std::vector<uint8_t>. `data` may be a buffer larger than one 64 KB bank on the
 * Atari816 (a whole file in consecutive banks): read it with at() / read_u16() then, never
 * with data[i]. An object the game itself indexes (pixels, a record) is at most 65,535
 * bytes and inside one bank. */
typedef struct {
    uint8_t SR_FAR *data;
    uint32_t size;
} Bytes;

/* ends the program with "error: <message>" (upstream's main printed a data::Error so) */
void sr_fail(const char *fmt, ...);

/* asset memory (never freed while the game runs: upstream kept every asset for the
 * program's life). plat_alloc(n): n bytes (n <= 65535), inside one bank; fails with
 * sr_fail when there is none. */
void SR_FAR *plat_alloc(uint32_t n);
/* a scratch buffer for a whole file (may be bigger than a bank), freed again */
void SR_FAR *plat_alloc_big(uint32_t n);
void plat_free_big(void SR_FAR *p);

/* byte b of a buffer that may span banks (byteio.h's at() is built on it) */
#if defined(__CC816__)
#define SR_BYTE(base, off) (*(const uint8_t SR_FAR *)((uint32_t)(base) + (uint32_t)(off)))
#else
#define SR_BYTE(base, off) ((base)[off])
#endif

/* copy n bytes (n <= 65535) out of a buffer that may span banks */
void sr_copy_from(void SR_FAR *dst, const Bytes *src, uint32_t offset, uint32_t n);

#define SR_MIN(a, b) ((a) < (b) ? (a) : (b))
#define SR_MAX(a, b) ((a) > (b) ? (a) : (b))
#define SR_CLAMP(v, lo, hi) ((v) < (lo) ? (lo) : (v) > (hi) ? (hi) : (v))

#endif
