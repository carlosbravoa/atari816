/* hg_image.c - hgame: images in far memory (registered as sheets when the kernel can),
 * blits of frames and parts, image-to-image drawing by the CPU, .HGI files. */
#include <stdlib.h>
#include <string.h>
#include "hg_int.h"


static void close_images(void)
{
    hz_sheet_free(0xFFFF);
}

static hg_image *newimg(unsigned w, unsigned h, unsigned n, unsigned key, unsigned bpp)
{
    hg_image *img;
    unsigned long size;
    unsigned stride = bpp == 4 ? (w + 1) / 2 : w;

    if (w == 0 || h == 0 || n == 0 || w > 4096 || h > 1024) {
        hg__fail("hg_image", "size: 1-4096 x 1-1024, 1 frame at least");
        return 0;
    }
    size = (unsigned long)stride * h * n;
    img = (hg_image *)malloc(sizeof *img);
    if (!img) {
        hg__fail("hg_image", "no memory");
        return 0;
    }
    memset(img, 0, sizeof *img);
    img->addr = hg__farmem(size);
    if (!img->addr) {
        hg__fail("hg_image", "no far memory (banks) left");
        free(img);
        return 0;
    }
    img->w = w;
    img->h = h;
    img->n = n;
    img->stride = stride;
    img->key = key;
    img->bpp = (unsigned char)bpp;
    hg__hook_close_images = close_images;
    /* a sheet: the kernel then checks only numbers for each blit from it */
    if (bpp == 8 && (unsigned long)h * n <= 1024) {
        hz_sheetnew sn;
        int s;
        HZ_U24(sn.addr, HG__PTR(img->addr));
        sn.zero = 0;
        sn.stride = stride;
        sn.w = w;
        sn.h = h * n;
        s = hz_sheet_new(&sn);
        if (s > 0 && s <= 32) {
            img->sheet = (unsigned char)s;
            hg__sheet_addr[s] = img->addr;
            hg__sheet_stride[s] = stride;
        }
    }
    return img;
}

/* copy n bytes between 24-bit addresses, split where either crosses a bank */
static void farcopy(unsigned long dst, unsigned long src, unsigned long n)
{
    unsigned long k, a, b;
    while (n) {
        a = 0x10000UL - (dst & 0xFFFF);
        b = 0x10000UL - (src & 0xFFFF);
        k = n < a ? n : a;
        if (b < k)
            k = b;
        if (k > 0xFFF0UL)
            k = 0xFFF0UL;
        hz_far_copy(HG__PTR(dst), HG__PTR(src), (unsigned)k);
        dst += k;
        src += k;
        n -= k;
    }
}

hg_image *hg_image_new(unsigned w, unsigned h, unsigned n)
{
    return newimg(w, h, n, HG_NONE, 8);
}

hg_image *hg_image_from(const unsigned char *pixels, unsigned w, unsigned h, unsigned n,
                        unsigned key)
{
    hg_image *img;
    if (!pixels) {
        hg__fail("hg_image_from", "no pixels");
        return 0;
    }
    img = newimg(w, h, n, key, 8);
    if (img)
        farcopy(img->addr, (unsigned long)pixels, (unsigned long)w * h * n);
    return img;
}

void hg_image_free(hg_image *img)
{
    if (!img)
        return;
    if (img->sheet) {
        if (hg__listrun) {
            hz_list_wait(0);
            hg__listrun = 0;
        }
        hz_sheet_free(img->sheet);
    }
    if (img->pal)
        free(img->pal);
    free(img);
}

void hg_image_palette(const hg_image *img)
{
    if (img && img->paln && img->pal)
        hg_palette(img->palbase, img->paln, img->pal);
}

unsigned long hg_image_addr(const hg_image *img, unsigned frame)
{
    if (!img || frame >= img->n) {
        hg__fail("hg_image_addr", "no image, or no such frame");
        return 0;
    }
    return img->addr + hg__umul(frame * img->h, img->stride);
}

unsigned char __far *hg_image_pixels(const hg_image *img, unsigned frame)
{
    return HG__PTR(hg_image_addr(img, frame));
}

/* ---------------------------------------------------------------- .HGI files */

typedef struct {
    char magic[4];              /* "HGI1" */
    unsigned short w, h, n, key;
    unsigned char bpp, zero;
    unsigned short palbase, paln;
    unsigned char spare[14];
} hgi_head;
HZ_STATIC_ASSERT(sizeof(hgi_head) == 32, hgi_head);

static int rd(int fh, unsigned long addr, unsigned long n)
{
    hz_io io;
    unsigned long k, a;
    int got;
    while (n) {
        a = 0x10000UL - (addr & 0xFFFF);
        k = n < a ? n : a;
        if (k > 0x8000UL)
            k = 0x8000UL;
        io.handle = (unsigned char)fh;
        HZ_U24(io.buf, HG__PTR(addr));
        io.len = (unsigned short)k;
        got = hz_read(&io);
        if (got != (int)k)
            return -1;
        addr += k;
        n -= k;
    }
    return 0;
}

hg_image *hg_image_load(const char *path)
{
    hgi_head hd;
    hg_image *img = 0;
    int fh;

    fh = hz_open(path, HZ_O_READ);
    if (fh < 0) {
        hg__fail("hg_image_load", hz_strerror(hz_errno));
        return 0;
    }
    if (rd(fh, (unsigned long)(void *)&hd, sizeof hd) || memcmp(hd.magic, "HGI1", 4) ||
        (hd.bpp != 8 && hd.bpp != 4) || hd.paln > 256) {
        hg__fail("hg_image_load", "not an .HGI file (sdk/tools/img2c.py makes them)");
        goto out;
    }
    img = newimg(hd.w, hd.h, hd.n, hd.key, hd.bpp);
    if (!img)
        goto out;
    if (hd.paln) {
        img->pal = (unsigned char *)malloc(hd.paln * 3);
        if (!img->pal || rd(fh, (unsigned long)(void *)img->pal, hd.paln * 3UL))
            goto bad;
        img->palbase = hd.palbase;
        img->paln = hd.paln;
    }
    if (rd(fh, img->addr, (unsigned long)img->stride * img->h * img->n))
        goto bad;
out:
    hz_close(fh);
    return img;
bad:
    hg__fail("hg_image_load", "the file is short");
    hg_image_free(img);
    hz_close(fh);
    return 0;
}

/* ---------------------------------------------------------------- blits */

static void blit(const hg_image *img, unsigned sx, unsigned sy, unsigned w, unsigned h,
                 int x, int y)
{
    hz_drawrec __far *r;
    unsigned char four = hg__mode == FS_640X4 && hg__kind == HG__FULL;

    if ((img->bpp == 4) != four) {
        hg__fail("hg_draw", img->bpp == 4 ? "a 16-colour image outside HG_640X360X4"
                 : "HG_640X360X4 needs 16-colour images (img2c.py --bpp 4)");
        return;
    }
    r = hg__rec(img->key != HG_NONE ? LS_KEY : LS_COPY, x, y, w, h);
    if (!r)
        return;
    sx += (unsigned)hg__cutx;
    sy += (unsigned)hg__cuty;
    if (four) {
        r->c2 = (unsigned char)((img->key & 15) * 17);
        sx >>= 1;
    } else
        r->c2 = (unsigned char)img->key;
    *(unsigned long __far *)&r->u.s = img->addr + hg__umul(sy, img->stride) + sx;
    r->stride = img->stride;
}

void hg__draw_c(const hg_image *img, unsigned frame, int x, int y)
{
    if (!img || frame >= img->n) {
        hg__fail("hg_draw", img ? "no such frame" : "no image (NULL)");
        return;
    }
    blit(img, 0, frame * img->h, img->w, img->h, x, y);
}

void hg__draw_part_c(const hg_image *img, unsigned sx, unsigned sy, unsigned w,
                     unsigned h, int x, int y)
{
    if (!img) {
        hg__fail("hg_draw_part", "no image (NULL)");
        return;
    }
    if (sx >= img->w || sy >= img->h * img->n)
        return;
    if (w > img->w - sx)
        w = img->w - sx;
    if (h > img->h * img->n - sy)
        h = img->h * img->n - sy;
    blit(img, sx, sy, w, h, x, y);
}

/* ---------------------------------------------------------------- the CPU: image to image */

/* hg_fast.s: the CPU, memory to memory (rows may cross banks) */
void hg__blitmem(unsigned long dst, unsigned dstride, unsigned long src, unsigned sstride,
                 unsigned w, unsigned h, unsigned key);
void hg__fillmem(unsigned long dst, unsigned dstride, unsigned w, unsigned h, unsigned c);

void hg_image_draw(hg_image *dst, const hg_image *src, unsigned frame, int x, int y)
{
    unsigned w, h, sx = 0, sy = 0;
    unsigned long da, sa;

    if (!dst || !src || frame >= src->n || dst->bpp != 8 || src->bpp != 8) {
        hg__fail("hg_image_draw", "no image, no such frame, or not 8 bpp");
        return;
    }
    w = src->w;
    h = src->h;
    if (x < 0) {
        if ((unsigned)-x >= w)
            return;
        sx = (unsigned)-x;
        w -= sx;
        x = 0;
    }
    if (y < 0) {
        if ((unsigned)-y >= h)
            return;
        sy = (unsigned)-y;
        h -= sy;
        y = 0;
    }
    if ((unsigned)x >= dst->w || (unsigned)y >= dst->h)
        return;
    if (w > dst->w - (unsigned)x)
        w = dst->w - (unsigned)x;
    if (h > dst->h - (unsigned)y)
        h = dst->h - (unsigned)y;
    if (hg__listrun) {                  /* (a list may be reading dst) */
        hz_list_wait(0);
        hg__listrun = 0;
    }
    da = dst->addr + hg__umul((unsigned)y, dst->stride) + (unsigned)x;
    sa = src->addr + hg__umul(frame * src->h + sy, src->stride) + sx;
    hg__blitmem(da, dst->stride, sa, src->stride, w, h, src->key);
}

void hg_image_fill(hg_image *dst, int x, int y, unsigned w, unsigned h, unsigned c)
{
    unsigned long da;
    if (!dst || dst->bpp != 8) {
        hg__fail("hg_image_fill", "no image, or not 8 bpp");
        return;
    }
    if (x < 0) {
        if ((unsigned)-x >= w)
            return;
        w -= (unsigned)-x;
        x = 0;
    }
    if (y < 0) {
        if ((unsigned)-y >= h)
            return;
        h -= (unsigned)-y;
        y = 0;
    }
    if ((unsigned)x >= dst->w || (unsigned)y >= dst->h * dst->n)
        return;
    if (w > dst->w - (unsigned)x)
        w = dst->w - (unsigned)x;
    if (h > dst->h * dst->n - (unsigned)y)
        h = dst->h * dst->n - (unsigned)y;
    if (hg__listrun) {
        hz_list_wait(0);
        hg__listrun = 0;
    }
    da = dst->addr + hg__umul((unsigned)y, dst->stride) + (unsigned)x;
    hg__fillmem(da, dst->stride, w, h, c);
}
