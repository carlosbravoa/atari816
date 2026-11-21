/* misc.c - small helpers over the syscalls. */
#include <horizon.h>

int hz_spawn_path(const char *path, const char *args, unsigned prio)
{
    hz_spawnblk b;
    HZ_U24(b.path, path);
    if (args) {
        HZ_U24(b.args, args);
    } else {
        b.args.off = 0;
        b.args.bank = 0;
    }
    b.prio = (unsigned char)prio;
    return hz_spawn(&b);
}

int hz_stat_path(const char *path, hz_fileinfo *st)
{
    hz_statblk b;
    HZ_U24(b.path, path);
    HZ_U24(b.out, st);
    return hz_stat(&b) == -1 && hz_errno ? -1 : 0;
}

void __far *hz_far_alloc(void)
{
    unsigned b = hz_bank_alloc();
    if (hz_errno)
        return 0;
    return HZ_FARPTR(b, 0);
}

void hz_far_free(void __far *p)
{
    hz_bank_free(HZ_BANK(p));
}
