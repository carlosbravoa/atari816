/* dirent.h - reading a folder (Horizon C SDK; lib/dirent.c).
 *
 *   DIR *d = opendir("/APPS");
 *   struct dirent *e;
 *   while ((e = readdir(d)) != NULL)
 *       printf("%s %lu%s\n", e->d_name, e->d_size, e->d_attr & HZ_ATTR_DIR ? " <dir>" : "");
 *   closedir(d);
 *
 * Entries come without "." and "..", in the card's order (the emulator: by name). No
 * file handle is used. HZ_ATTR_DIR, HZ_ATTR_RDONLY: horizon.h.
 */
#ifndef DIRENT_H
#define DIRENT_H

struct dirent {
    char d_name[128];           /* the name (long names up to 127 characters) */
    unsigned long d_size;       /* bytes */
    unsigned char d_attr;       /* HZ_ATTR_DIR, HZ_ATTR_RDONLY, $20 archive */
};

typedef struct {
    char *path;
    unsigned seen;              /* entries handed out */
    unsigned n, next, pos;      /* entries in buf, the next one, its offset */
    unsigned char done;
    struct dirent ent;
    char buf[512];              /* the kernel copies the path here first, then entries */
} DIR;

DIR *opendir(const char *path);
struct dirent *readdir(DIR *d);
void rewinddir(DIR *d);
int closedir(DIR *d);

#endif
