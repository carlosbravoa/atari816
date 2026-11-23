/* host_plat.c - the PC back end's platform.h and sr.h parts: stdio files, malloc. */
#include <ctype.h>
#include <dirent.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "platform.h"

void sr_fail(const char *fmt, ...)
{
    va_list ap;
    fprintf(stderr, "error: ");
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fprintf(stderr, "\n");
    exit(1);
}

unsigned long plat_allocated;

void *plat_alloc(uint32_t n)
{
    void *p;
    /* (a PC pads structures: a table that is 64,000 bytes on the Atari816 can be more
     * here; the Atari816's own allocator checks the 64 KB limit) */
    if (n > 131072u)
        sr_fail("plat_alloc(%lu): too big for one object", (unsigned long)n);
    p = calloc(1, n ? n : 1);
    if (!p)
        sr_fail("out of memory");
    plat_allocated += n;
    return p;
}

void *plat_alloc_big(uint32_t n)
{
    void *p = malloc(n ? n : 1);
    if (!p)
        sr_fail("out of memory");
    return p;
}

void plat_free_big(void *p) { free(p); }

void sr_copy_from(void *dst, const Bytes *src, uint32_t offset, uint32_t n)
{
    memcpy(dst, src->data + offset, n);
}

void plat_fill(uint8_t *dst, uint8_t value, unsigned n) { memset(dst, value, n); }
void plat_copy(uint8_t *dst, const uint8_t *src, unsigned n) { memmove(dst, src, n); }

uint8_t plat_random_byte(void) { return (uint8_t)(rand() & 0xFF); }

static int file_exists(const char *path)
{
    struct stat info;
    return stat(path, &info) == 0 && S_ISREG(info.st_mode);
}

/* asset_path of the C++ (data/assets.cpp): the exact name, else a case-insensitive
 * match in the folder */
const char *plat_asset_path(const char *root, const char *name)
{
    static char buf[1024];
    DIR *dir;
    struct dirent *e;
    snprintf(buf, sizeof buf, "%s/%s", root, name);
    if (file_exists(buf))
        return buf;
    dir = opendir(root);
    if (!dir)
        return buf;
    while ((e = readdir(dir)) != NULL) {
        if (strcasecmp(e->d_name, name) == 0) {
            snprintf(buf, sizeof buf, "%s/%s", root, e->d_name);
            break;
        }
    }
    closedir(dir);
    return buf;
}

bool plat_read_file(const char *path, Bytes *out)
{
    FILE *f = fopen(path, "rb");
    long n;
    if (!f)
        return false;
    fseek(f, 0, SEEK_END);
    n = ftell(f);
    fseek(f, 0, SEEK_SET);
    out->data = plat_alloc_big((uint32_t)n);
    out->size = (uint32_t)n;
    if (fread(out->data, 1, (size_t)n, f) != (size_t)n) {
        fclose(f);
        return false;
    }
    fclose(f);
    return true;
}

bool plat_write_file(const char *path, const void *data, unsigned n)
{
    FILE *f = fopen(path, "wb");
    size_t w;
    if (!f)
        return false;
    w = fwrite(data, 1, n, f);
    fclose(f);
    return w == n;
}
