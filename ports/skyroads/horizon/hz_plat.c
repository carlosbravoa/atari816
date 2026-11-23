/* hz_plat.c - platform.h and sr.h on Horizon: asset memory in far banks, files, the
 * pre-decoded LZ streams.
 *
 * Memory: plat_alloc is a bump allocator over banks from hz_far_alloc (an object never
 * crosses a bank); plat_alloc_big takes consecutive banks (hg_banks) for a whole file,
 * read through SR_BYTE's 24-bit addresses.
 *
 * The LZ streams: decoding ROADS.LZS alone takes about 10 s on the 65816 (the decoder
 * reads bit by bit), all the files a minute. `srtool predecode` (the same decoder, on a
 * PC) writes, for each NAME.LZS, NAME.DEC: every stream the loaders decode, in the order
 * they decode them, as {"LZD\0", u24 offset, u16 size, u24 consumed} and the bytes.
 * While NAME.LZS is being loaded, decompress_stream takes the next one from NAME.DEC
 * (decompress_fetch_hook) instead of decoding; the loaders themselves are upstream's. */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <hgame.h>
#include <horizon.h>

#include "platform.h"
#include "data/compression.h"
#include "hz_plat.h"

void sr_fail(const char *fmt, ...)
{
    va_list ap;
    printf("skyroads: error: ");
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    printf("\n");
    exit(1);
}

/* ---------------------------------------------------------------- memory */

static unsigned cur_bank;               /* the bank being filled, 0 = none */
static uint32_t cur_off;
unsigned hzp_banks_used;

void SR_FAR *plat_alloc(uint32_t n)
{
    void SR_FAR *p;
    if (n == 0)
        n = 1;
    if (n > 65536UL)
        sr_fail("plat_alloc(%lu): one object is at most 64 KB", (unsigned long)n);
    /* (Horizon 0.30) objects stay below offset $FF00 of a bank when they fit (fill_runs
     * reads the spans of a group there: hz_video.c) */
    if (!cur_bank || cur_off + n > (n <= 65280UL ? 65280UL : 65536UL)) {
        void SR_FAR *b = hz_far_alloc();
        if (!b)
            sr_fail("out of memory (%u banks taken)", hzp_banks_used);
        cur_bank = HZ_BANK(b);
        cur_off = 0;
        hzp_banks_used++;
    }
    p = hz_farptr(cur_bank, (unsigned)cur_off);
    hz_far_set(p, 0, (unsigned)n);
    cur_off += n;
    if (cur_off & 1)
        cur_off++;
    return p;
}

/* the big buffers: consecutive banks */
static struct { unsigned bank, n; } bigs[4];

void SR_FAR *plat_alloc_big(uint32_t n)
{
    unsigned nb = (unsigned)((n + 65535UL) >> 16), b, i;
    if (nb == 0)
        nb = 1;
    b = hg_banks(nb);
    if (!b)
        sr_fail("out of memory (%u consecutive banks)", nb);
    for (i = 0; i < 4; ++i)
        if (!bigs[i].bank) {
            bigs[i].bank = b;
            bigs[i].n = nb;
            break;
        }
    return hz_farptr(b, 0);
}

static void dec_close(void);

void plat_free_big(void SR_FAR *p)
{
    unsigned b = HZ_BANK(p), i, k;
    dec_close();                        /* (the file's load is over) */
    for (i = 0; i < 4; ++i)
        if (bigs[i].bank == b) {
            for (k = 0; k < bigs[i].n; ++k)
                hz_far_free(hz_farptr(b + k, 0));
            bigs[i].bank = 0;
            return;
        }
}

void sr_copy_from(void SR_FAR *dst, const Bytes *src, uint32_t offset, uint32_t n)
{
    uint32_t a = (uint32_t)src->data + offset;
    uint8_t SR_FAR *d = (uint8_t SR_FAR *)dst;
    while (n) {
        uint32_t k = 65536UL - (a & 0xFFFF);
        if (k > n)
            k = n;
        if (k > 0xFFFF)
            k = 0xFFFF;
        hz_far_copy(d, (const void SR_FAR *)a, (unsigned)k);
        d += (unsigned)k;
        a += k;
        n -= k;
    }
}

void plat_fill(uint8_t SR_FAR *dst, uint8_t value, unsigned n)
{
    if (n)
        hz_far_set(dst, value, n);
}

void plat_copy(uint8_t SR_FAR *dst, const uint8_t SR_FAR *src, unsigned n)
{
    if (n)
        hz_far_copy(dst, src, n);
}

uint8_t plat_random_byte(void) { return (uint8_t)hg_rand(); }

/* ---------------------------------------------------------------- files */

const char *plat_asset_path(const char *root, const char *name)
{
    static char buf[128];
    snprintf(buf, sizeof buf, "%s%s", root, name);
    return buf;
}

/* n bytes of handle h into far memory at linear address a (pieces of 16 KB inside a
 * bank: hz_read's result is an int) */
static bool read_far(int h, uint32_t a, uint32_t n)
{
    while (n) {
        hz_io io;
        uint32_t k = 65536UL - (a & 0xFFFF);
        if (k > n)
            k = n;
        if (k > 0x4000)
            k = 0x4000;
        io.handle = (unsigned char)h;
        HZ_U24B(io.buf, (unsigned)(a >> 16), (unsigned)a);
        io.len = (unsigned short)k;
        if (hz_read(&io) != (int)k)
            return false;
        a += k;
        n -= k;
    }
    return true;
}

static int dec_handle = -1;

static void dec_close(void)
{
    if (dec_handle >= 0)
        hz_close((unsigned)dec_handle);
    dec_handle = -1;
}

static bool fetch_hook(uint32_t offset, uint32_t expected_size, DecompressResult *result)
{
    unsigned char h[12];
    hz_io io;
    uint32_t off, size, consumed;
    if (dec_handle < 0)
        return false;
    io.handle = (unsigned char)dec_handle;
    HZ_U24(io.buf, h);
    io.len = 12;
    if (hz_read(&io) != 12 || h[0] != 'L' || h[1] != 'Z' || h[2] != 'D')
        sr_fail("damaged .DEC file (no stream at %lu)", (unsigned long)offset);
    off = h[4] | ((uint32_t)h[5] << 8) | ((uint32_t)h[6] << 16);
    size = h[7] | ((uint32_t)h[8] << 8);
    consumed = h[9] | ((uint32_t)h[10] << 8) | ((uint32_t)h[11] << 16);
    if (off != offset || size != expected_size)
        sr_fail(".DEC file does not match its .LZS (stream at %lu: %lu, want %lu, %lu)",
                (unsigned long)off, (unsigned long)size, (unsigned long)offset,
                (unsigned long)expected_size);
    result->output.data = size ? (uint8_t SR_FAR *)plat_alloc(size) : 0;
    result->output.size = size;
    result->consumed = consumed;
    if (size && !read_far(dec_handle, (uint32_t)result->output.data, size))
        sr_fail(".DEC file is short");
    return true;
}

bool plat_read_file(const char *path, Bytes *out)
{
    hz_statblk sb;
    unsigned char info[9];
    long size;
    int h;
    unsigned n = (unsigned)strlen(path);

    dec_close();
    HZ_U24(sb.path, path);
    HZ_U24(sb.out, info);
    size = hz_stat(&sb);
    if (size < 0)
        return false;
    h = hz_open(path, HZ_O_READ);
    if (h < 0)
        return false;
    out->size = (uint32_t)size;
    out->data = (uint8_t SR_FAR *)plat_alloc_big(out->size);
    if (!read_far(h, (uint32_t)out->data, out->size)) {
        hz_close((unsigned)h);
        return false;
    }
    hz_close((unsigned)h);

    /* NAME.LZS: its streams from NAME.DEC */
    if (n > 4 && strcmp(path + n - 4, ".LZS") == 0) {
        char dec[128];
        strcpy(dec, path);
        strcpy(dec + n - 4, ".DEC");
        dec_handle = hz_open(dec, HZ_O_READ);
        decompress_fetch_hook = fetch_hook;
    }
    return true;
}

bool plat_write_file(const char *path, const void *data, unsigned n)
{
    hz_io io;
    int h = hz_open(path, HZ_O_CREATE);
    int w;
    if (h < 0)
        return false;
    io.handle = (unsigned char)h;
    HZ_U24(io.buf, data);
    io.len = (unsigned short)n;
    w = hz_write(&io);
    hz_close((unsigned)h);
    return w == (int)n;
}
