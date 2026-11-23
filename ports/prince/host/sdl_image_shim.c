/* host/sdl_image_shim.c - IMG_Load_RW for paletted PNGs (zlib), IMG_SavePNG as a 24-bit
 * PNG writer. See SDL2/SDL_image.h. Host only (the reference build). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>
#include "SDL2/SDL_image.h"

static unsigned be32(const unsigned char *p)
{
    return (unsigned)p[0] << 24 | (unsigned)p[1] << 16 | (unsigned)p[2] << 8 | p[3];
}

static int paeth(int a, int b, int c)
{
    int p = a + b - c, pa = abs(p - a), pb = abs(p - b), pc = abs(p - c);
    if (pa <= pb && pa <= pc) return a;
    return pb <= pc ? b : c;
}

static SDL_Surface *decode(const unsigned char *d, size_t n)
{
    static const unsigned char sig[8] = {137, 'P', 'N', 'G', 13, 10, 26, 10};
    unsigned w = 0, h = 0, depth = 0, ctype = 0, inter = 0, npal = 0;
    unsigned char pal[768];
    unsigned char *idat = NULL;
    size_t idat_n = 0, pos = 8;
    SDL_Surface *s = NULL;

    if (n < 8 || memcmp(d, sig, 8)) {
        SDL_SetError("not a PNG");
        return NULL;
    }
    while (pos + 12 <= n) {
        unsigned len = be32(d + pos);
        const unsigned char *type = d + pos + 4, *body = d + pos + 8;
        if (pos + 12 + len > n)
            break;
        if (!memcmp(type, "IHDR", 4)) {
            w = be32(body);
            h = be32(body + 4);
            depth = body[8];
            ctype = body[9];
            inter = body[12];
        } else if (!memcmp(type, "PLTE", 4)) {
            npal = len / 3;
            memcpy(pal, body, npal * 3 > 768 ? 768 : npal * 3);
        } else if (!memcmp(type, "IDAT", 4)) {
            idat = realloc(idat, idat_n + len);
            memcpy(idat + idat_n, body, len);
            idat_n += len;
        } else if (!memcmp(type, "IEND", 4)) {
            break;
        }
        pos += 12 + len;
    }
    if (ctype != 3 || inter || !(depth == 1 || depth == 2 || depth == 4 || depth == 8) || !w || !h) {
        SDL_SetError("PNG: only paletted, not interlaced (type %u depth %u)", ctype, depth);
        free(idat);
        return NULL;
    }
    {
        size_t stride = (w * depth + 7) / 8;
        uLongf rawn = (uLongf)((stride + 1) * h);
        unsigned char *raw = malloc(rawn), *prev = calloc(1, stride), *line = malloc(stride);
        unsigned x, y;
        if (uncompress(raw, &rawn, idat, idat_n) != Z_OK || rawn != (stride + 1) * h) {
            SDL_SetError("PNG: bad image data");
            goto out;
        }
        s = SDL_CreateRGBSurface(0, (int)w, (int)h, 8, 0, 0, 0, 0);
        if (!s)
            goto out;
        for (y = 0; y < h; y++) {
            const unsigned char *src = raw + y * (stride + 1);
            unsigned f = src[0];
            size_t i;
            ++src;
            for (i = 0; i < stride; i++) {
                int a = i ? line[i - 1] : 0, b = prev[i], c = i ? prev[i - 1] : 0, v = src[i];
                switch (f) {
                case 1: v += a; break;
                case 2: v += b; break;
                case 3: v += (a + b) / 2; break;
                case 4: v += paeth(a, b, c); break;
                }
                line[i] = (unsigned char)v;
            }
            for (x = 0; x < w; x++) {
                unsigned bit = x * depth, v = line[bit / 8];
                v = (v >> (8 - depth - bit % 8)) & ((1u << depth) - 1);
                ((unsigned char *)s->pixels)[y * s->pitch + x] = (unsigned char)v;
            }
            memcpy(prev, line, stride);
        }
        {
            SDL_Color c[256];
            unsigned i;
            for (i = 0; i < npal && i < 256; i++) {
                c[i].r = pal[3 * i];
                c[i].g = pal[3 * i + 1];
                c[i].b = pal[3 * i + 2];
                c[i].a = 255;
            }
            SDL_SetPaletteColors(s->format->palette, c, 0, (int)npal);
            s->format->palette->ncolors = (int)npal;   /* as SDL_image: the file's count */
        }
out:
        free(raw);
        free(prev);
        free(line);
    }
    free(idat);
    return s;
}

SDL_Surface *IMG_Load_RW(SDL_RWops *src, int freesrc)
{
    Sint64 n = SDL_RWsize(src);
    unsigned char *buf;
    SDL_Surface *s;
    if (n <= 0) {
        if (freesrc) SDL_RWclose(src);
        SDL_SetError("IMG_Load_RW: empty");
        return NULL;
    }
    buf = malloc((size_t)n);
    SDL_RWread(src, buf, 1, (size_t)n);
    if (freesrc)
        SDL_RWclose(src);
    s = decode(buf, (size_t)n);
    free(buf);
    return s;
}

SDL_Surface *IMG_Load(const char *file)
{
    SDL_RWops *rw = SDL_RWFromFile(file, "rb");
    if (!rw)
        return NULL;
    return IMG_Load_RW(rw, 1);
}

/* ---------------------------------------------------------------- writing */

static void put32(unsigned char *p, unsigned v)
{
    p[0] = (unsigned char)(v >> 24); p[1] = (unsigned char)(v >> 16);
    p[2] = (unsigned char)(v >> 8); p[3] = (unsigned char)v;
}

static void chunk(FILE *f, const char *type, const unsigned char *body, unsigned len)
{
    unsigned char h[8];
    uLong crc = crc32(0, (const Bytef *)type, 4);
    put32(h, len);
    memcpy(h + 4, type, 4);
    fwrite(h, 1, 8, f);
    if (len)
        fwrite(body, 1, len, f);
    crc = crc32(crc, body, len);
    put32(h, (unsigned)crc);
    fwrite(h, 1, 4, f);
}

int IMG_SavePNG(SDL_Surface *surface, const char *file)
{
    static const unsigned char sig[8] = {137, 'P', 'N', 'G', 13, 10, 26, 10};
    SDL_Surface *rgb = SDL_ConvertSurfaceFormat(surface, SDL_PIXELFORMAT_RGB24, 0);
    unsigned w, h, y;
    unsigned char ihdr[13], *raw, *z;
    uLongf zn;
    FILE *f;
    if (!rgb)
        return -1;
    w = (unsigned)rgb->w;
    h = (unsigned)rgb->h;
    raw = malloc((w * 3 + 1) * h);
    for (y = 0; y < h; y++) {
        raw[y * (w * 3 + 1)] = 0;
        memcpy(raw + y * (w * 3 + 1) + 1, (unsigned char *)rgb->pixels + y * rgb->pitch, w * 3);
    }
    zn = compressBound((w * 3 + 1) * h);
    z = malloc(zn);
    compress(z, &zn, raw, (w * 3 + 1) * h);
    f = fopen(file, "wb");
    if (!f) {
        free(raw); free(z); SDL_FreeSurface(rgb);
        return -1;
    }
    fwrite(sig, 1, 8, f);
    put32(ihdr, w);
    put32(ihdr + 4, h);
    ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = ihdr[11] = ihdr[12] = 0;
    chunk(f, "IHDR", ihdr, 13);
    chunk(f, "IDAT", z, (unsigned)zn);
    chunk(f, "IEND", NULL, 0);
    fclose(f);
    free(raw);
    free(z);
    SDL_FreeSurface(rgb);
    return 0;
}
