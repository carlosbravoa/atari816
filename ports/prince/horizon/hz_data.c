/* hz_data.c - Prince of Persia's data on the Atari816: tools/mkdata.py's POP.DAT (the
 * directory: images, palettes, levels, binary resources), POP.GFX (the atlas) and POP.MSK
 * (the 1-bit masks), loaded into far memory at the start, and upstream's seg009 calls
 * that find resources: open_dat / close_dat (the chain of open DAT files, searched from
 * the last one opened, as upstream searches them), load_sprites_from_file, load_image,
 * load_from_opendats_alloc / _to_area. */
#include <string.h>
#include <stdio.h>
#include <hgame.h>
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

#define HDR 22                          /* POP.DAT's header (version 2): the table after it */

/* The loading: every file opened once and read whole, straight into far memory in pieces
 * of up to 32,767 bytes (the most one read moves; a piece never crosses a bank). On the
 * board's card each request costs a few ms whatever its size: the 512-byte reads through a
 * buffer this replaced took 4,320 requests and 35 s in the emulator's model of the card,
 * these 88 and 9.6 s (4 s at the board's 580 KB/s). hzd_loaded / hzd_total: the
 * progress bar (hzv_loading). */
unsigned long hzd_loaded, hzd_total;

static int open_data(const char *name)
{
    char path[160];
    strcpy(path, hz_prog);
    strcat(path, name);
    return hz_open(path, HZ_O_READ);
}

/* n bytes (or to the end) of the open file h into far memory from addr -> bytes read */
long hzd_read_far(int h, unsigned long addr, unsigned long n)
{
    unsigned long total = 0;
    hz_io io;
    while (total < n) {
        unsigned long a = addr + total, room = 0x10000UL - (a & 0xFFFF), left = n - total;
        unsigned want = (unsigned)(left < room ? (left < 32767UL ? left : 32767UL)
                                               : (room < 32767UL ? room : 32767UL));
        int got;
        io.handle = (unsigned char)h;
        HZ_U24B(io.buf, (unsigned)(a >> 16), (unsigned)a);
        io.len = want;
        got = hz_read(&io);
        if (got <= 0)
            break;
        total += (unsigned)got;
        hzd_loaded += (unsigned)got;
        hzv_loading(hzd_loaded, hzd_total);
        if ((unsigned)got < want)
            break;
    }
    return (long)total;
}

/* a whole file of n bytes into far memory from addr -> 0, or -1 */
static int load_file(const char *name, unsigned long addr, unsigned long n)
{
    int h = open_data(name), ok;
    if (h < 0)
        return -1;
    ok = hzd_read_far(h, addr, n) == (long)n;
    hz_close((unsigned)h);
    return ok ? 0 : -1;
}

static int fail(const char *what)
{
    printf("prince: %s (the game's data: see README.md, make data)\n", what);
    return -1;
}

unsigned long hzd_snd_size;             /* (hz_sound.c loads POP.SND) */

int hzd_init(void)
{
    long n, gsz;
    unsigned b, nb, k;
    unsigned long msk_size;
    int h;
    dir = hz_far_alloc();
    if (!dir)
        return fail("no memory for POP.DAT");
    h = open_data("POP.DAT");
    if (h < 0)
        return fail("no POP.DAT");
    hzd_total = 0xFFFFUL;               /* (the bar: POP.DAT is a small part) */
    n = hzd_read_far(h, (unsigned long)dir, 0xFFFFUL);
    hz_close((unsigned)h);
    if (n < HDR || dir[0] != 'P' || dir[3] != 'D')
        return fail("no POP.DAT");
    if (*(unsigned __far *)(dir + 4) != 2)
        return fail("POP.DAT of an older version");
    ndir = *(unsigned __far *)(dir + 6);
    hzd_atlas_w = *(unsigned __far *)(dir + 8);
    hzd_atlas_h = *(unsigned __far *)(dir + 10);
    hzd_part = *(unsigned __far *)(dir + 12);
    msk_size = *(unsigned long __far *)(dir + 14);
    hzd_snd_size = *(unsigned long __far *)(dir + 18);
    hzd_total = (unsigned long)n + (unsigned long)hzd_atlas_w * hzd_atlas_h + msk_size + hzd_snd_size;
    /* the atlas: each part in banks of its own (consecutive within the part), the parts one
     * after the other in POP.GFX: read in one go */
    hzd_nparts = (hzd_atlas_h + hzd_part - 1) / hzd_part;
    if (hzd_nparts > HZD_PARTS || hzd_part != 256)
        return fail("POP.GFX has too many parts, or parts not of 256 rows");
    h = open_data("POP.GFX");
    if (h < 0)
        return fail("no POP.GFX");
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
            hz_close((unsigned)h);
            return fail("not enough memory for the atlas");
        }
        hzd_part_addr[k] = (unsigned long)b << 16;
        if (hzd_read_far(h, hzd_part_addr[k], (unsigned long)gsz) != gsz) {
            hz_close((unsigned)h);
            return fail("POP.GFX is missing or damaged");
        }
    }
    hz_close((unsigned)h);
    nb = (unsigned)((msk_size + 0xFFFF) >> 16);
    b = hg_banks(nb);
    if (!b)
        return fail("not enough memory for the masks");
    hzd_masks = (unsigned long)b << 16;
    if (load_file("POP.MSK", hzd_masks, msk_size) < 0)
        return fail("POP.MSK is missing or damaged");
    return 0;
}

/* POP.SND (hz_sound.c): its size from POP.DAT, read like the others -> its address, or 0 */
unsigned long hzd_load_snd(void)
{
    unsigned nb = (unsigned)((hzd_snd_size + 0xFFFF) >> 16), b;
    if (!hzd_snd_size || (b = hg_banks(nb)) == 0)
        return 0;
    if (load_file("POP.SND", (unsigned long)b << 16, hzd_snd_size) < 0)
        return 0;
    return (unsigned long)b << 16;
}

/* the directory's record of (folder, kind, res) -> its offset in POP.DAT, or 0 */
static unsigned find(unsigned folder, unsigned kind, unsigned res)
{
    unsigned lo = 0, hi = ndir;
    while (lo < hi) {
        unsigned mid = (lo + hi) >> 1;
        const unsigned char __far *e = dir + HDR + mid * 8;
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

/* a palette record -> upstream's dat_shpl_type: n_images and the palette */
static void shpl_from(dat_shpl_type *s, const unsigned char __far *p)
{
    unsigned i;
    memset(s, 0, sizeof *s);
    s->n_images = p[0];
    s->palette.n_colors = 16;
    for (i = 0; i < 16; i++) {
        s->palette.vga[i].r = p[50 + 3 * i];
        s->palette.vga[i].g = p[51 + 3 * i];
        s->palette.vga[i].b = p[52 + 3 * i];
    }
}

void *load_from_opendats_alloc(int resource, const char *extension, data_location *out_result,
                               int *out_size)
{
    unsigned o, n;
    void *m;
    if (out_result)
        *out_result = data_none;
    if (!strcmp(extension, "pal")) {
        dat_shpl_type *s;
        o = find_chain(KIND_PAL, (unsigned)resource);
        if (!o)
            return NULL;
        s = hz_malloc_or_quit(sizeof(dat_shpl_type));
        shpl_from(s, dir + o);
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
    m = hz_malloc_or_quit(n ? n : 1);
    hz_far_copy(m, dir + o + 2, n);
    if (out_size)
        *out_size = (int)n;
    if (out_result)
        *out_result = data_directory;
    return m;
}

/* straight from POP.DAT's copy in far memory into the area: no heap (the level, 2,305
 * bytes, was malloc'd and copied before; once the heap had less than that in one piece
 * the level silently stayed empty: the kid started in room 0 and died) */
int load_from_opendats_to_area(int resource, void *area, int length, const char *extension)
{
    unsigned o, n;
    if (!strcmp(extension, "pal")) {
        dat_shpl_type s;
        o = find_chain(KIND_PAL, (unsigned)resource);
        if (!o)
            return 0;
        shpl_from(&s, dir + o);
        memcpy(area, &s, sizeof s < (unsigned)length ? sizeof s : (unsigned)length);
        return 0;
    }
    o = find_chain(KIND_BIN, (unsigned)resource);
    if (!o) {
        printf("prince: no resource %d in POP.DAT\n", resource);
        return 0;
    }
    n = *(const unsigned __far *)(dir + o);
    hz_far_copy(area, dir + o + 2, n < (unsigned)length ? n : (unsigned)length);
    return 0;
}

void load_font(void)
{
    dat_type *dathandle = open_dat("font", 1);
    hc_font.chtab = load_sprites_from_file(1000, 1 << 1, 0);
    close_dat(dathandle);
}
