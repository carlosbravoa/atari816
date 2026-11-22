/* hz_kbd.c - Xargon's keyboard on Horizon: upstream's keyboard.c (its interrupt 9 handler,
 * which keeps keydown[] by PC scan code, and the BIOS's int 16h calls) from hgame's keys.
 *
 * k_read gives what the BIOS gave: the ASCII code, or for a key without one 128 + its PC
 * scan code (the arrows 200, 203, 205, 208, F1 187 ...: keyboard.h's k_ names). Horizon's
 * keys are HID usages: the table below gives each its PC scan code (set 1). Keys come in
 * order from hg_key_next (with the key repeat, as the BIOS's typematic). keydown[0][scan]
 * is kept for the keys upstream polls (the arrows and the keypad's). */
#include <hgame.h>
#include "keyboard.h"
#include "hz_plat.h"

char k_rshift, k_lshift, k_shift, k_ctrl, k_alt, k_numlock;
unsigned char keydown[2][256];

/* HID usage $04-$63 -> PC scan code (0: none) */
static const unsigned char scan[0x64] = {
    0, 0, 0, 0,
    0x1E, 0x30, 0x2E, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17, 0x24, 0x25, 0x26,   /* a-l */
    0x32, 0x31, 0x18, 0x19, 0x10, 0x13, 0x1F, 0x14, 0x16, 0x2F, 0x11, 0x2D,   /* m-x */
    0x15, 0x2C,                                                               /* y z */
    0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B,               /* 1-0 */
    0x1C, 0x01, 0x0E, 0x0F, 0x39, 0x0C, 0x0D, 0x1A, 0x1B, 0x2B, 0x2B, 0x27,   /* ent..; */
    0x28, 0x29, 0x33, 0x34, 0x35, 0x3A,                                       /* ' ` , . / caps */
    0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x43, 0x44, 0x57, 0x58,   /* F1-F12 */
    0x37, 0x46, 0x45, 0x52, 0x47, 0x49, 0x53, 0x4F, 0x51,                     /* prt..pgdn */
    0x4D, 0x4B, 0x50, 0x48,                                                   /* arrows */
    0x45, 0x35, 0x37, 0x4A, 0x4E, 0x1C,                                       /* keypad */
    0x4F, 0x50, 0x51, 0x4B, 0x4C, 0x4D, 0x47, 0x48, 0x49, 0x52, 0x53          /* kp 1-9 0 . */
};

#define QN 32
static unsigned q[QN];
static unsigned char qh, qn;

void k_status(void)
{
    k_lshift = (char)hg_key(0xE1);
    k_rshift = (char)hg_key(0xE5);
    k_shift = (char)(k_lshift | k_rshift);
    k_ctrl = (char)(hg_key(0xE0) | hg_key(0xE4));
    k_alt = (char)(hg_key(0xE2) | hg_key(0xE6));
    k_numlock = 1;
}

/* after each frame: the keys pressed into the queue, the polled keys' state */
void hzk_frame(void)
{
    unsigned k, u, c, code;
    while ((k = hg_key_next()) != 0) {
        u = k & 0xFF;
        c = k >> 8;
        if (c && c < 0x80)
            code = c;                   /* ASCII (ctrl + letter: 1-26) */
        else if (u < sizeof scan && scan[u])
            code = 0x80 | scan[u];      /* none: 128 + the scan code */
        else
            continue;
        if (qn < QN) {
            q[(qh + qn) % QN] = code;
            ++qn;
        }
    }
    keydown[0][0x48] = (unsigned char)(hg_key(0x52) | hg_key(0x60));   /* up, keypad 8 */
    keydown[0][0x50] = (unsigned char)(hg_key(0x51) | hg_key(0x5A));   /* down, 2 */
    keydown[0][0x4B] = (unsigned char)(hg_key(0x50) | hg_key(0x5C));   /* left, 4 */
    keydown[0][0x4D] = (unsigned char)(hg_key(0x4F) | hg_key(0x5E));   /* right, 6 */
}

int k_pressed(void)
{
    return qn ? (int)q[qh] : 0;
}

int k_read(void)
{
    unsigned c;
    while (!qn)
        hzf_pump();                     /* (the BIOS waits for a key) */
    c = q[qh];
    qh = (unsigned char)((qh + 1) % QN);
    --qn;
    return (int)c;
}

void installhandler(unsigned char status)
{
    (void)status;
}

void removehandler(void)
{
}

void enablebios(void)
{
    qn = 0;                             /* (upstream empties the BIOS's buffer) */
}

void disablebios(void)
{
}

int biosstatus(void)
{
    return 1;
}
