/* dirent.c - opendir / readdir / closedir over SYS_READDIR (dirent.h).
 *
 * Horizon's readdir fills a buffer with packed entries and can skip a number of them,
 * so a DIR holds a buffer of entries and reads the next batch (skipping those already
 * seen) when it is empty. No handle is used: any number of DIRs can be open.
 */
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <dirent.h>
#include <horizon.h>

int __hz_seterrno(void);

/* the next batch of entries into d->buf: > 0 entries, 0 the end, -1 an error */
static int fill(DIR *d)
{
    hz_readdirblk b;
    int n;
    HZ_U24(b.path, d->path);
    HZ_U24(b.buf, d->buf);
    b.len = sizeof(d->buf);
    b.skip = d->seen;
    n = hz_readdir(&b);
    if (n <= 0) {
        d->done = 1;
        return n < 0 ? __hz_seterrno() : 0;
    }
    d->n = n;
    d->next = 0;
    d->pos = 0;
    return n;
}

DIR *opendir(const char *path)
{
    DIR *d = malloc(sizeof(DIR) + strlen(path) + 1);
    if (!d) {
        errno = ENOMEM;
        return 0;
    }
    d->path = (char *)(d + 1);
    strcpy(d->path, path);
    d->seen = 0;
    d->n = d->next = d->pos = 0;
    d->done = 0;
    if (fill(d) < 0) {                  /* no such folder (or not a folder) */
        free(d);
        return 0;
    }
    return d;
}

struct dirent *readdir(DIR *d)
{
    const unsigned char *e;
    const hz_dirent *h;
    unsigned nl;
    if (!d)
        return 0;
    if (d->next >= d->n && (d->done || fill(d) <= 0))
        return 0;
    e = (const unsigned char *)d->buf + d->pos;
    h = (const hz_dirent *)e;
    d->ent.d_size = h->size;
    d->ent.d_attr = h->attr;
    nl = h->namelen;
    if (nl > sizeof(d->ent.d_name) - 1)
        nl = sizeof(d->ent.d_name) - 1;
    memcpy(d->ent.d_name, e + sizeof(hz_dirent), nl);
    d->ent.d_name[nl] = 0;
    d->pos += sizeof(hz_dirent) + h->namelen;
    d->next++;
    d->seen++;
    return &d->ent;
}

void rewinddir(DIR *d)
{
    if (d) {
        d->seen = 0;
        d->n = d->next = 0;
        d->done = 0;
    }
}

int closedir(DIR *d)
{
    free(d);
    return 0;
}
