/* hz_snd.c - Xargon's sound on Horizon: upstream's music.c (Tim Sweeney's "unified sound
 * unit" over the WORX Sound Blaster library) with the same interface, on the Atari816's
 * sound chips:
 *
 *   effects  the Sound Blaster's digital effects (AUDIO.XRn: 8-bit at 6,250 Hz, one at a
 *            time, a new one cutting the one playing when its priority is as high:
 *            upstream's rule) on Lau, the sample player: XSOUND.XRn (tools/mkdata.py)
 *            loaded into far memory at the start
 *   music    the CMF songs (the Sound Blaster's FM music) on the OPL2: SONG_n.OPn, the
 *            register streams tools/mkdata.py made of them, played by hgame (hg_opl_play)
 *            from far memory, loaded at each change of song
 *   texts    the help and story texts kept in AUDIO.XRn, read when shown (text_get)
 *
 * The PC speaker's version of the effects (soundmac, AUDIO.EPC) is not needed: Lau is on
 * every board with the sample player, the OPL2 on REV $0C. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <hgame.h>
#include <horizon.h>
#include "music.h"
#include "io.h"
#include "hz_plat.h"

/* music.h's names that upstream's files use (the PC speaker's and the WORX library's are
 * not needed) */
int vocflag = 1, musicflag = 1, soundf = 1;
char *textmsg;
int textmsglen;

static char vocname[16];
static hg_sound snd[num_samps];
static unsigned long sndbase;           /* XSOUND's samples in far memory */
static int voice = -1, oldpri;
static unsigned endf;                   /* the frame the effect playing ends */
static unsigned long songbuf;           /* two banks for a song */
static char cursong[16];

/* n bytes of file fd into far memory at a (in pieces that do not cross a bank, of 16 KB
 * at most: hz_read's result is an int) */
static int farread(int fd, unsigned long a, unsigned long n)
{
    hz_io io;
    unsigned k;
    int r;
    while (n) {
        k = 0x4000;
        if ((unsigned long)k > n)
            k = (unsigned)n;
        if ((unsigned)a + k < (unsigned)a && (unsigned)a + k != 0)
            k = (unsigned)(0x10000UL - (a & 0xFFFF));
        io.handle = (unsigned char)(fd - 3);
        io.buf.off = (unsigned short)a;
        io.buf.bank = (unsigned char)(a >> 16);
        io.len = k;
        r = hz_read(&io);
        if (r <= 0)
            return -1;
        a += (unsigned)r;
        n -= (unsigned)r;
    }
    return 0;
}

/* "audio.xr1" -> "XSOUND.XR1" */
static void xname(char *out, const char *pre, const char *orig)
{
    const char *e = strrchr(orig, '.');
    strcpy(out, pre);
    strcat(out, e ? e : "");
}

static unsigned rd16(const unsigned char *p)
{
    return p[0] | (unsigned)p[1] << 8;
}

static unsigned long rd32(const unsigned char *p)
{
    return rd16(p) | (unsigned long)rd16(p + 2) << 16;
}

void snd_init(char *voclib)
{
    int fd, i;
    long size;
    unsigned char h[6 + num_samps * 8];
    char name[16];

    textmsg = NULL;
    strcpy(vocname, voclib);
    if (!hg_has_lau())
        vocflag = 0;
    if (!hg_has_opl())
        musicflag = 0;
    /* the effects */
    xname(name, "XSOUND", voclib);
    fd = vocflag ? open(name, O_RDONLY) : -1;
    if (fd < 0) {
        vocflag = 0;
    } else {
        size = filelength(fd);
        if (read(fd, h, sizeof h) == (int)sizeof h && !memcmp(h, "XSN1", 4) &&
            (sndbase = (unsigned long)hg_banks((unsigned)((size + 0xFFFF) >> 16)) << 16) != 0) {
            lseek(fd, 0, SEEK_SET);
            if (farread(fd, sndbase, (unsigned long)size) == 0) {
                for (i = 0; i < num_samps && i < (int)rd16(h + 4); i++) {
                    snd[i].addr = sndbase + rd32(h + 6 + i * 8);
                    snd[i].len = rd16(h + 10 + i * 8);
                    snd[i].rate = rd16(h + 12 + i * 8);
                    snd[i].bits = 8;
                    snd[i].loop = 0;
                }
            } else
                vocflag = 0;
        } else
            vocflag = 0;
        close(fd);
    }
    if (musicflag) {
        songbuf = (unsigned long)hg_banks(2) << 16;
        if (!songbuf)
            musicflag = 0;
    }
}

static int playing(void)
{
    return voice >= 0 && (int)(hz_frame() - endf) < 0;
}

void snd_play(int priority, int num)
{
    hg_sound *s;
    if (vocflag && soundf) {
        if (!playing() || priority >= oldpri) {
            s = (num >= 0 && num < num_samps) ? &snd[num] : 0;
            if (s && s->len) {
                if (voice >= 0)
                    hg_stop(voice);     /* (the Sound Blaster plays one at a time) */
                voice = hg_play(s, 255);
                endf = hz_frame() + (unsigned)((s->len * 60UL) / s->rate) + 1;
            }
            oldpri = priority;
        }
    }
}

void snd_do(void)
{
}

/* after each frame */
void hzs_frame(void)
{
}

/* text n of AUDIO.XRn: its place and length from the file's header (after the sounds'
 * 400 bytes: num_text places, then num_text lengths; upstream kept them in textposn[] and
 * textlen[], 240 bytes the main bank has not got), then the text, in the heap (never
 * NULL: hz_heap.h). The heap's room is taken with the file closed: its read-ahead (512
 * bytes of the heap) would otherwise lie where the help's 4,313 bytes must go. */
void text_get(int n)
{
    int fd, len = 0;
    long at = 0;
    textmsg = NULL;
    if (n < 0 || n >= num_text)
        return;
    fd = open(vocname, O_RDONLY);
    if (fd < 0)
        return;
    if (lseek(fd, num_samps * 8L + n * 4L, SEEK_SET) < 0 || read(fd, &at, 4) != 4 ||
        lseek(fd, num_samps * 8L + num_text * 4L + n * 2L, SEEK_SET) < 0 || read(fd, &len, 2) != 2)
        len = 0;
    close(fd);
    if (len <= 0)
        return;
    textmsglen = len;
    textmsg = malloc(textmsglen);
    hz_heap_report("with", n == 1 ? "the help" : "a text");    /* (tests/check.sh) */
    fd = open(vocname, O_RDONLY);
    if (fd < 0 || lseek(fd, at, SEEK_SET) < 0 || read(fd, textmsg, textmsglen) < 0) {
        free(textmsg);
        textmsg = NULL;
    }
    if (fd >= 0)
        close(fd);
}

void snd_exit(void)
{
    sb_shutup();
    if (voice >= 0)
        hg_stop(voice);
}

void music_init(void)
{
}

int sb_playing(void)
{
    return 1;                           /* (as upstream: the WORX library loops the song) */
}

void sb_shutup(void)
{
    if (musicflag)
        hg_opl_stop();
    cursong[0] = 0;
}

void sb_update(void)
{
}

/* "song_3.xr1" -> SONG_3.OP1, loaded into far memory and played, again and again */
void sb_playtune(char *filename)
{
    char name[16];
    char *e;
    int fd;
    long n;
    unsigned long t0;
    if (!musicflag)
        return;
    sb_shutup();
    if (strlen(filename) > 12)
        return;
    strcpy(name, filename);
    e = strrchr(name, '.');
    if (e && (e[1] == 'x' || e[1] == 'X') && (e[2] == 'r' || e[2] == 'R')) {
        e[1] = 'O';
        e[2] = 'P';
    }
    fd = open(name, O_RDONLY);
    if (fd < 0)
        return;
    n = filelength(fd);
    t0 = hz_uptime();
    if (n > 0 && n <= 0x20000L && farread(fd, songbuf, (unsigned long)n) == 0) {
        if (hzf_stats)
            printf("xargon: song %s: %ld bytes in %lu ms\n", name, n,
                   (unsigned long)hz_uptime() - t0);
        hg_opl_play((const void __far *)songbuf, (unsigned long)n, 560, 1);
        strcpy(cursong, filename);
    }
    close(fd);
}
