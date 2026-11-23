/* horizon/compat/sys/stat.h - stat and mkdir for SDLPoP's file checks (horizon/hz_sys.c) */
#ifndef HZ_SYS_STAT_H
#define HZ_SYS_STAT_H
#define S_IFMT  0xF000
#define S_IFDIR 0x4000
#define S_IFREG 0x8000
#define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)
#define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
struct stat {
    unsigned st_mode;
    long st_size;
};
int stat(const char *path, struct stat *st);
int mkdir(const char *path, ...);
#endif
