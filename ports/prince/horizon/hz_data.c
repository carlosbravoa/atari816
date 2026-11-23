/* hz_data.c - Prince of Persia's data on the Atari816: tools/mkdata.py's POP.DAT (the
 * directory: images, palettes, levels, binary resources), POP.GFX (the atlas) and POP.MSK
 * (the 1-bit masks), loaded into far memory at the start, and upstream's seg009 calls
 * that find resources: open_dat / close_dat (the chain of open DAT files, searched from
 * the last one opened, as upstream searches them), load_sprites_from_file, load_image,
 * load_from_opendats_alloc / _to_area. */
#include <string.h>
#include <stdio.h>
#include <hgame.h>
#include <fcntl.h>
#include <unistd.h>
#include "common.h"
#include "hz_plat.h"

static const char *const folders[] = {
    "PRINCE", "KID", "GUARD", "FAT", "SKEL", "VIZIER", "SHADOW", "GUARD1", "GUARD2",
    "VDUNGEON", "VPALACE", "PV", "TITLE", "LEVELS", "font", "IBM_SND1", "IBM_SND2",
    "DIGISND1", "DIGISND2", "DIGISND3", "MIDISND1", "MIDISND2"};
#define NFOLDERS (sizeof folders / sizeof folders[0])
#define KIND_PAL 1
#define KIND_IMG 2
#define KIND_BIN 3

unsigned long hzd_part_addr[HZD_PARTS], hzd_masks;
unsigned hzd_atlas_w, hzd_atlas_h, hzd_part, hzd_nparts;
unsigned char __far *hzd_dir;           /* POP.DAT, a bank of its own */
#define dir hzd_dir
unsigned char hzd_buf[512];
static unsigned ndir;

/* read max bytes (or to the end) of a file from offset into consecutive far memory from
 * addr -> the length read */
static long load_far(const char *name, unsigned long addr, unsigned long max, long offset)
{
    unsigned char *buf = hzd_buf;
    char path[160];
    int fd;
    long total = 0;
    strcpy(path, hz_prog);
    strcat(path, name);
    fd = open(path, O_RDONLY);
    if (fd < 0)
        return -1;
    if (offset && lseek(fd, offset, SEEK_SET) != offset) {
        close(fd);
        return -1;
    }
    for (;;) {
        unsigned want = max - (unsigned long)total > sizeof hzd_buf ? sizeof hzd_buf :
                        (unsigned)(max - (unsigned long)total);
        int n = want ? read(fd, buf, want) : 0;
        unsigned long a = addr + (unsigned long)total;
        unsigned room;
        if (n <= 0)
            break;
        room = (unsigned)(0x10000UL - (a & 0xFFFF));
        if ((unsigned)n <= room) {
            hz_far_copy((void __far *)a, buf, (unsigned)n);
        } else {                        /* across a bank's end */
            hz_far_copy((void __far *)a, buf, room);
            hz_far_copy((void __far *)(a + room), buf + room, (unsigned)n - room);
        }
        total += n;
    }
    close(fd);
    return total;
}

static long file_size(const char *name)
{
    char path[160];
    hz_fileinfo st;
    strcpy(path, hz_prog);
    strcat(path, name);
    if (hz_stat_path(path, &st) < 0)
        return -1;
    return (long)st.size;
}

static int fail(const char *what)
{
    printf("prince: %s (the game's data: see README.md, make data)\n", what);
    return -1;
}

int hzd_init(void)
{
    long n, gsz;
    unsigned b, nb, k;
    dir = hz_far_alloc();
    if (!dir)
        return fail("no memory for POP.DAT");
    n = load_far("POP.DAT", (unsigned long)dir, 0xFFFFUL, 0);
    if (n < 16 || dir[0] != 'P' || dir[3] != 'D')
        return fail("no POP.DAT");
    ndir = *(unsigned __far *)(dir + 6);
    hzd_atlas_w = *(unsigned __far *)(dir + 8);
    hzd_atlas_h = *(unsigned __far *)(dir + 10);
    hzd_part = *(unsigned __far *)(dir + 12);
    /* the atlas: each part in banks of its own (consecutive within the part) */
    hzd_nparts = (hzd_atlas_h + hzd_part - 1) / hzd_part;
    if (hzd_nparts > HZD_PARTS)
        return fail("POP.GFX has too many parts");
    for (k = 0; k < hzd_nparts; k++) {
        unsigned rows = hzd_atlas_h - k * hzd_part < hzd_part ? hzd_atlas_h - k * hzd_part : hzd_part;
        gsz = (long)hzd_atlas_w * rows;
        nb = (unsigned)((gsz + 0xFFFF) >> 16);
        b = hg_banks(nb);
        if (!b) {
            unsigned m = nb;
            while (m > 1 && !hg_banks(m))
                --m;
            printf("prince: %u banks free, at most %u together; the atlas wants %u\n",
                   hz_mem_info(), m, nb);
            return fail("not enough memory for the atlas");
        }
        hzd_part_addr[k] = (unsigned long)b << 16;
        if (load_far("POP.GFX", hzd_part_addr[k], (unsigned long)gsz,
                     (long)hzd_atlas_w * hzd_part * k) != gsz)
            return fail("POP.GFX is missing or damaged");
    }
    n = file_size("POP.MSK");
    if (n <= 0)
        return fail("no POP.MSK");
    nb = (unsigned)((n + 0xFFFF) >> 16);
    b = hg_banks(nb);
    if (!b)
        return fail("not enough memory for the masks");
    hzd_masks = (unsigned long)b << 16;
    if (load_far("POP.MSK", hzd_masks, (unsigned long)nb << 16, 0) != n)
        return fail("POP.MSK is damaged");
    return 0;
}

/* the directory's record of (folder, kind, res) -> its offset in POP.DAT, or 0 */
static unsigned find(unsigned folder, unsigned kind, unsigned res)
{
    unsigned lo = 0, hi = ndir;
    while (lo < hi) {
        unsigned mid = (lo + hi) >> 1;
        const unsigned char __far *e = dir + 14 + mid * 8;
        unsigned ef = e[0], er = *(const unsigned __far *)(e + 2), ek = e[1];
        int c = ef != folder ? (ef < folder ? -1 : 1) :
                er != res ? (er < res ? -1 : 1) : ek != kind ? (ek < kind ? -1 : 1) : 0;
        if (c == 0)
            return *(const unsigned __far *)(e + 4);
        if (c < 0)
            lo = mid + 1;
        else
            hi = mid;
    }
    return 0;
}

static int folder_of(const dat_type *d)
{
    char name[16];
    unsigned i;
    strncpy(name, d->filename, sizeof name - 1);
    name[sizeof name - 1] = 0;
    {
        char *dot = strchr(name, '.');
        if (dot)
            *dot = 0;
    }
    for (i = 0; i < NFOLDERS; i++)
        if (!strcasecmp(name, folders[i]))
            return (int)i;
    return -1;
}

/* the chain, searched from the DAT opened last */
static unsigned find_chain(unsigned kind, unsigned res)
{
    const dat_type *d;
    for (d = dat_chain_ptr; d; d = d->next_dat) {
        int f = folder_of(d);
        unsigned o;
        if (f < 0)
            continue;
        o = find((unsigned)f, kind, res);
        if (o)
            return o;
    }
    return 0;
}

dat_type *open_dat(const char *filename, int optional)
{
    dat_type *p = calloc(1, sizeof(dat_type));
    (void)optional;
    if (!p) {
        printf("prince: no memory\n");
        quit(1);
    }
    strncpy(p->filename, filename, sizeof p->filename - 1);
    p->next_dat = dat_chain_ptr;
    dat_chain_ptr = p;
    return p;
}

void close_dat(dat_type *pointer)
{
    dat_type **prev = &dat_chain_ptr, *curr = dat_chain_ptr;
    while (curr != NULL) {
        if (curr == pointer) {
            *prev = curr->next_dat;
            free(curr);
            return;
        }
        prev = &curr->next_dat;
        curr = curr->next_dat;
    }
}

/* an image of the directory -> a surface (into s, or malloc) */
static image_type *image_at(unsigned o, image_type *s)
{
    const unsigned __far *r = (const unsigned __far *)(dir + o);
    if (s == NULL && (s = malloc(sizeof(image_type))) == NULL)
        return NULL;
    s->w = (int)r[0];
    s->h = (int)r[1];
    s->a = o;
    s->b = HZS_IMAGE;
    return s;
}

/* (load_one_optgraf's single images: freed by free_chtab as not in its block) */
image_type *load_image(int resource_id, dat_pal_type *palette)
{
    unsigned o = find_chain(KIND_IMG, (unsigned)resource_id);
    (void)palette;
    return o ? image_at(o, NULL) : NULL;
}

/* a palette record: n_images, row, 16 x 3 image colours, 16 x 3 .pal colours (6 bits) */
chtab_type *load_sprites_from_file(int resource, int palette_bits, int quit_on_error)
{
    unsigned o = find_chain(KIND_PAL, (unsigned)resource), n, i, row;
    chtab_type *chtab;
    const unsigned char __far *p;
    if (!o) {
        printf("Can't load sprites from resource %d.\n", resource);
        if (quit_on_error)
            quit(1);
        return NULL;
    }
    p = dir + o;
    n = p[0];
    row = palette_bits ? (unsigned)find_first_pal_row(palette_bits) : p[1];
    /* the image set, its pointers and its images in one block (a malloc each would cost
     * the main bank's heap 4 bytes an image more) */
    {
        unsigned have = 0, sz;
        image_type *blk;
        for (i = 1; i <= n; i++)
            if (find_chain(KIND_IMG, (unsigned)resource + i))
                ++have;
        sz = sizeof(chtab_type) + sizeof(image_type *) * n + sizeof(image_type) * have;
        chtab = malloc(sz);
        if (!chtab) {
            printf("prince: no memory for %u images (%u bytes free)\n", n, hz_heap_largest());
            quit(1);
        }
        memset(chtab, 0, sz);
        blk = (image_type *)&chtab->images[n];
        chtab->n_images = (word)n;
        chtab->chtab_palette_bits = (word)palette_bits;
        chtab->has_palette_bits = 1;
        chtab_palette_bits |= (word)palette_bits;
        for (i = 1; i <= n; i++) {
            unsigned io = find_chain(KIND_IMG, (unsigned)resource + i);
            if (io)
                chtab->images[i - 1] = image_at(io, blk++);
        }
    }
    /* the row's colours (set_loaded_palette): as the images show them */
    if (palette_bits) {
        for (i = 0; i < 16; i++)
            set_pal((int)(row * 16 + i), p[2 + 3 * i], p[3 + 3 * i], p[4 + 3 * i]);
    }
    return chtab;
}

void free_chtab(chtab_type *chtab_ptr)
{
    word id;
    chtab_palette_bits &= ~chtab_ptr->chtab_palette_bits;
    {
        const char *lo = (const char *)&chtab_ptr->images[chtab_ptr->n_images];
        for (id = 0; id < chtab_ptr->n_images; ++id) {
            const char *im = (const char *)chtab_ptr->images[id];
            if (im && (im < (const char *)chtab_ptr || im >= lo + sizeof(image_type) * chtab_ptr->n_images))
                free(chtab_ptr->images[id]);    /* (load_one_optgraf's) */
        }
    }
    free(chtab_ptr);
}

void *load_from_opendats_alloc(int resource, const char *extension, data_location *out_result,
                               int *out_size)
{
    unsigned o, n;
    void *m;
    if (out_result)
        *out_result = data_none;
    if (!strcmp(extension, "pal")) {
        /* a dat_shpl_type: n_images and the palette */
        dat_shpl_type *s;
        const unsigned char __far *p;
        unsigned i;
        o = find_chain(KIND_PAL, (unsigned)resource);
        if (!o)
            return NULL;
        p = dir + o;
        s = calloc(1, sizeof(dat_shpl_type));
        if (!s)
            return NULL;
        s->n_images = p[0];
        s->palette.n_colors = 16;
        for (i = 0; i < 16; i++) {
            s->palette.vga[i].r = p[50 + 3 * i];
            s->palette.vga[i].g = p[51 + 3 * i];
            s->palette.vga[i].b = p[52 + 3 * i];
        }
        if (out_size)
            *out_size = (int)sizeof(dat_shpl_type);
        if (out_result)
            *out_result = data_directory;
        return s;
    }
    o = find_chain(KIND_BIN, (unsigned)resource);
    if (!o)
        return NULL;
    n = *(const unsigned __far *)(dir + o);
    m = malloc(n ? n : 1);
    if (!m)
        return NULL;
    hz_far_copy(m, dir + o + 2, n);
    if (out_size)
        *out_size = (int)n;
    if (out_result)
        *out_result = data_directory;
    return m;
}

int load_from_opendats_to_area(int resource, void *area, int length, const char *extension)
{
    int size = 0;
    void *m = load_from_opendats_alloc(resource, extension, NULL, &size);
    if (!m)
        return 0;
    memcpy(area, m, size < length ? (unsigned)size : (unsigned)length);
    free(m);
    return 0;
}

void load_font(void)
{
    dat_type *dathandle = open_dat("font", 1);
    hc_font.chtab = load_sprites_from_file(1000, 1 << 1, 0);
    close_dat(dathandle);
}
