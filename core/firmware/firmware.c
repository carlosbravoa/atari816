// Simple firmware for Tang Atari 800
// Adapted from SNESTang firmware for Atari 800 core
// Nand2mario & Google DeepMind team, 2026

#include <stdbool.h>
#include "picorv32.h"
#include "fatfs/ff.h"
#include "firmware.h"
#include "xex_loader.h"   // 6502 binary-load boot loader image (virtual D1: disk)
#include "pclink.h"       // the PC link (Docs/04-pc-link.md)
#include "pcnet.h"        // the internet through it: URLs and connections (step 2)
#include "prnconv.h"      // (step 3) the classic Atari's printer output as text
#include "fdisk.h"        // (step 3) a folder as a DOS 2 disk
#include "bas_loader.h"   // (step 3) the boot program of "Run in Atari"

uint32_t CORE_ID;
#define HOT_FN __attribute__((section(".text.hot")))   // runs from block RAM (baremetal.ld)

void uart_keyboard_poll(void);
static void bridge_poll(void);   // PC link and mailbox servicing (defined below)
DWORD fat_from2000(uint32_t t);  // seconds since 2000 -> FAT time (defined below)


#define OPTION_FILE "/atari.ini"
#define OPTION_INVALID 2

int option_arrow_joystick = 0;              // 1 = arrow keys drive Joystick 1 (Left-Alt = fire)
int option_scanline_level = 0;              // 0=off,1=25%,2=50%,3=75% scanline brightness
int option_h_offset = 0;                    // horizontal pan: capture-skip pixels (0..48)
int option_stereo = 0;                      // 1 = dual-POKEY stereo (POKEY2 @ $D210 -> right); default mono
int option_kbd_layout = 0;                  // 0 = Atari-positional keys (default), 1 = US-PC symbolic
int option_folderdrive = 0;                  // (step 3) "folderdrive=N": the folder disk on DN: (0 none)
static char option_folder[128] __attribute__((section(".sdbuf")));   // "folder=PATH"

// Classic machine RAM sizes (/atari.ini "ram"). code = core RAM_SELECT; kb = the ini value.
// The core has only these two (Atari816: capped at 320 KB, the larger RAMBO/Compy schemes
// were removed). No key = 128 KB; any other value = 320 KB, with a log line.
static const struct { unsigned char code; int kb; } ram_opts[] = {
    {1, 128}, {3, 320}
};
#define N_RAM_OPTS 2
int option_ram_idx = 0;                      // index into ram_opts; 0 = 128 KB (default)

int option_boot_ash = 0;                     // OSD Options "Boot: BASIC/ASH" = atari.ini boot=ash.
                                             // 1 = /ASH.CAR is the DEFAULT CARTRIDGE: loaded at
                                             // power-on and whenever a cold boot finds the cart
                                             // slot empty (see load_default_cart). Default OFF =
                                             // power-on READY, byte-for-byte as before.
#define ASH_CART_FILE "/ASH.CAR"
char mounted_cart_name[16] = "None";         // OSD "Cart:" line
int mount_silent = 0;                        // boot-time/bridge automount: no interactive popups
                                             // cleared on every cold boot (load_system_roms)
uint32_t cart_sclust = 0;                    // FAT start cluster of the attached cart image (guard)

// Push the input-related options into the hardware config register (0xA4):
// bit 8 = USB-host-keyboard enable (permanently 0: keyboard is UART/CH9350 only),
// bit 9 = arrow-keys-as-joystick mode.
static inline void apply_input_options(void) {
    kv_set1((option_arrow_joystick ? 0x200 : 0x000));
}

// Push video options into the hardware config registers.
static inline void apply_video_options(void) {
    reg_video_opts = (option_scanline_level & 0x3)  // 0x B4 [1:0] scanline level
                   | ((option_stereo & 1) << 2)     //      [2]   dual-POKEY stereo enable
                   | ((option_kbd_layout & 1) << 3); //      [3]   keyboard: PC symbolic layout
    reg_h_offset   = option_h_offset & 0xFF;        // 0x B8 [7:0] horizontal position
}

// RAM size only takes effect when the core boots, so this is written before the
// core is released at boot and again inside cold_boot_atari() (RAM changes in the
// OSD cold-boot the machine). 0x BC [2:0] = core RAM_SELECT.
static inline void apply_machine_options(void) {
    reg_ram_select = ram_opts[option_ram_idx].code;
}

FATFS fs;

// ATR Disk Emulator state
#define ATR_DRIVES 4            // D1:-D4: (0x31-0x34); D3/D4 have no menu UI —
                                // they are config/bridge-managed (hdd= auto-mount)
FIL atr_file[ATR_DRIVES];
bool atr_mounted[ATR_DRIVES] = {false, false, false, false};
bool atr_readonly[ATR_DRIVES] = {false, false, false, false};  // write-open failed even after AM_RDO strip
uint16_t atr_sector_size[ATR_DRIVES] = {128, 128, 128, 128};
// Byte offset of sector 1 in the image: 16 for .atr (header), 0 for raw .xfd.
uint16_t atr_hdr_off[ATR_DRIVES] = {16, 16, 16, 16};
// DD images come in two layouts: standard packs boot sectors 1-3 as 128 B
// (data area at +384); "full-boot" stores them as 256-B slots (MyDOS images in
// the wild use this). Detected at mount; wrong guess = sectors 4+ off by 384.
bool atr_dd_fullboot[ATR_DRIVES] = {false, false, false, false};

// XEX (Atari binary executable) state — served as a virtual bootable disk on D1:
// only. When xex_active, D1: STATUS/READ are answered from the baked-in 6502 boot
// loader (sectors 1..XEX_BLDCNT) + the raw .xex file bytes (XEX_FIRSTSEC..).
bool     xex_active = false;
FIL      xex_file;
uint32_t xex_len = 0;

static uint8_t sio_sector_buf[256] __attribute__((aligned(4)));

// ── Step 3: memory the I/O processor takes in the classic machine's part of the SDRAM ──────
// Physical 0x110000-0x1EFFFF is free: the classic machine's RAM ends at 0x050000 (320 KB at most)
// and its ROMs start at 0x1F0000; the 65C816 never maps it (Horizon's pool is banks $02-$0F,
// $12-$1F, $40-$7F). The firmware sees physical 0x1xxxxx at 0x3xxxxx.
#define FD_IMG    ((uint8_t *)0x00380000)   // the folder disk: 720 x 128 = 92,160 bytes (phys 0x180000)
#define FD_ST     ((fd_t *)0x00396800)      // its state (about 7 KB)
#define INI_BUF   ((char *)0x0039C000)      // /atari.ini being rewritten (2 x 4 KB)
#define PRN_RAW   ((uint8_t *)0x0039E000)   // what the printer got, as it came: a ring of records
#define PRN_RING  8192
#define PRN_TXT   ((uint8_t *)0x003A0000)   // a classic print job's text (192 KB; more goes to the card)
#define PRN_TMAX  0x30000
#define RUN_IMG   ((uint8_t *)0x003D0000)   // the "Run in Atari" disk (128 KB, up to the BASIC ROM)
#define RUN_MAX   0x20000

// Disks served from that memory (hot: the SIO service): 1 the folder disk (read and write; what
// the Atari writes is saved into the folder later, fdisk.c), 2 the "Run in Atari" disk (read only)
static uint8_t  rd_kind[ATR_DRIVES];
static uint8_t *rd_base[ATR_DRIVES];
static uint16_t rd_nsec[ATR_DRIVES];
volatile uint32_t fd_act;                   // the Atari's accesses to the folder disk
static uint8_t  fd_wr, fd_fail;             // it wrote (a save is due); the last save failed
static uint32_t fd_tl;                      // its last access
static __attribute__((section(".text.hot"))) int rd_read(int slot, uint32_t sector, uint8_t *buf) {
    if (!sector || sector > rd_nsec[slot]) return -5;
    const uint32_t *q = (const uint32_t *)(rd_base[slot] + (sector - 1) * 128);
    uint32_t *d = (uint32_t *)buf;
    for (int i = 0; i < 32; i++) d[i] = q[i];
    if (rd_kind[slot] == 1) { fd_act++; fd_tl = time_millis(); }
    return 0;
}
static __attribute__((section(".text.hot"))) int rd_write(int slot, uint32_t sector, const uint8_t *buf) {
    if (rd_kind[slot] != 1 || !sector || sector > FD_NSEC) return -5;
    uint32_t *d = (uint32_t *)(FD_IMG + (sector - 1) * 128);
    const uint32_t *q = (const uint32_t *)buf;
    for (int i = 0; i < 32; i++) d[i] = q[i];
    FD_ST->dirty[sector >> 3] |= 1 << (sector & 7);
    FD_ST->pending = 1;
    fd_act++; fd_tl = time_millis(); fd_wr = 1;
    return 0;
}
// The printer (P1:-P4:): each record as it comes into a ring (a length byte, then the bytes); the
// main loop turns them into the job's text (prn_service, cold)
static uint32_t prn_head, prn_tail, prn_t;  // the ring (free-running byte counts); the last record
static uint8_t  prn_job;                    // a classic print job is open
static __attribute__((section(".text.hot"))) int prn_put(const uint8_t *b, int n) {
    uint32_t h = prn_head;
    if (h - prn_tail + n + 1 > PRN_RING) return -1;   // full: 'E', the OS tries again
    PRN_RAW[h++ & (PRN_RING - 1)] = n;
    for (int i = 0; i < n; i++) PRN_RAW[h++ & (PRN_RING - 1)] = b[i];
    prn_head = h;
    prn_t = time_millis();
    return 0;
}
static uint8_t sio_cmd_buf[5];
static int     sio_cmd_idx = 0;
static uint32_t sio_cmd_timeout = 0;   // millis timestamp of first byte in current frame

// SIO Diagnostics variables
uint8_t dbg_last_sio_cmd = 0;
uint16_t dbg_last_sio_sector = 0;
int dbg_last_sio_status = 0;
uint32_t dbg_sio_err_count = 0;
// (2026-10-13: the never-displayed SIO counters / command history / rx capture
// buffers were removed for image size — only the four shown on the OSD triage
// line and in bridge STATUS remain.)
// The on-screen menu (OSD) is gone (Atari816): what it used to show in a pop-up or on its
// status line goes to the serial log instead. Never waits for a key.
void status(char *msg) { uart_printf("%s\n", msg); }
void message(char *msg, int center) { (void)center; uart_printf("msg: %s\n", msg); }

// return 0: success, 1: no option file found, 2: option file corrupt,
// -1: transient SD/FS error (card not ready / disk error) -> caller should retry.
// The distinction matters at boot: load_option() is the FIRST real SD access (f_mount
// is lazy), so a mid-state card (common after a warm S1 reset) makes f_open fail. A
// genuinely-absent file (FR_NO_FILE, first run) must NOT trigger a retry storm.
int load_option()  {
    FIL f;
    int r = 0;
    char buf[1024];
    char *line, *key, *value;
    option_folder[0] = 0;                        // (in SDRAM: not cleared at start)
    FRESULT fr = f_open(&f, OPTION_FILE, FA_READ);
    if (fr != FR_OK)
        return (fr == FR_NO_FILE || fr == FR_NO_PATH) ? 1 : -1;
    while (f_gets(buf, 1024, &f)) {
        line = trimwhitespace(buf);
        if (line[0] == '\0' || line[0] == '[' || line[0] == ';' || line[0] == '#')
            continue;
        // find '='
        char *s = strchr(line, '=');
        if (!s) {
            r = OPTION_INVALID;
            goto load_option_close;
        }
        *s='\0';
        key = trimwhitespace(line);
        value = trimwhitespace(s+1);
        uart_printf("key=%s, value=%s\n", key, value);

        if (strcmp(key, "joystick") == 0) {
            option_arrow_joystick = (atoi(value) != 0);
        }
        if (strcmp(key, "scanlines") == 0) {
            option_scanline_level = atoi(value) & 0x3;
        }
        if (strcmp(key, "hpos") == 0) {
            int v = atoi(value);
            if (v < 0) v = 0;
            if (v > 48) v = 48;
            option_h_offset = v;
        }
        if (strcmp(key, "stereo") == 0) {
            option_stereo = (atoi(value) != 0);
        }
        if (strcmp(key, "kbdlayout") == 0) {
            option_kbd_layout = (atoi(value) != 0);
        }
        if (strcmp(key, "folder") == 0) {             // (step 3) the folder disk
            strncpy(option_folder, value, sizeof option_folder - 1);
            option_folder[sizeof option_folder - 1] = 0;
        }
        if (strcmp(key, "folderdrive") == 0) {
            option_folderdrive = atoi(value);
        }
        if (strcmp(key, "boot") == 0) {
            option_boot_ash = (strcmp(value, "ash") == 0);   // anything else = basic
        }
        if (strcmp(key, "ram") == 0) {
            int kb = atoi(value);
            option_ram_idx = 1;   // 320 KB unless the value is exactly 128
            if (kb == 128) option_ram_idx = 0;
            else if (kb != 320) uart_printf("ram=%s not supported, using 320\n", value);
        }
    }

load_option_close:
    f_close(&f);
    return r;
}

// ── Cartridge loading ────────────────────────────────────────────────────────
// The Atari core's CartLogic reads cart data from SDRAM; tang_top remaps those
// accesses into the 4 MB window at physical 0x400000-0x7FFFFF (= same address in
// the firmware's view, banks 2-3 pass through the iosys swap unchanged), so we just
// f_read the image straight into SDRAM there, set the mapper code in reg_cart_mode,
// and cold-boot. BASIC/OS were relocated out of this window (to 0x1F0000/0x1F4000).
#define CART_SDRAM_BASE 0x00400000u
#define CART_MAX_SIZE   0x00400000u

// CAR header type -> core CartLogic mode (see rtl/common/a8core/cart_logic.vhd).
// Pairs of {CAR type, mode}; unknown types are rejected with an error message.
// Atari816: the core keeps only the common schemes (standard 8/16 KB, OSS, XEGS and
// switchable XEGS, Atarimax, SIC, MegaCart); raw .rom 2/4 KB use modes 0x16 / 0x17.
static const uint8_t car_type_map[][2] = {
    {1,0x01},  {2,0x21},                                              // standard 8K, 16K
    {15,0x04}, {44,0x05}, {45,0x06},                                  // OSS
    {12,0x30}, {13,0x31}, {14,0x32}, {23,0x33}, {24,0x34}, {25,0x35}, // XEGS
    {33,0x38}, {34,0x39}, {35,0x3A}, {36,0x3B}, {37,0x3C}, {38,0x3D}, // switchable XEGS
    {41,0x02}, {42,0x03}, {75,0x10},                                  // Atarimax 1 / 8 Mbit
    {54,0x24}, {55,0x25}, {56,0x26},                                  // SIC 128 / 256 / 512 KB
    {26,0x28}, {27,0x29}, {28,0x2A}, {29,0x2B}, {30,0x2C}, {31,0x2D}, {32,0x2E},
    {64,0x2F}, {63,0x20},                                             // MegaCart 16 KB - 4 MB
    {57,0x16}, {58,0x17},                                             // 2 KB, 4 KB
};

// returns 0 on success (reg_cart_mode set, data in SDRAM), nonzero on error
uint32_t cart_bytes;                         // the image loaded last (valid while reg_cart_mode != 0)
char     cart_path[128];
int load_cartridge(char *filepath) {
    FIL f;
    unsigned int br;
    int r = f_open(&f, filepath, FA_READ);
    if (r != FR_OK) {
        uart_printf("cart: open '%s' failed %d\n", filepath, r);
        if (!mount_silent) message("Cannot open cartridge", 1);
        return r;                           // FatFs code (> 0); callers only test != 0
    }
    uint32_t fsize = f_size(&f);
    uint32_t sclust = f.obj.sclust;         // recorded for the write guard only on success
    uint32_t data_size = fsize;
    uint8_t mode = 0;
    uint32_t car_type = 0;                  // 0 = raw .rom (no header)

    char *ext = strrchr(filepath, '.');
    if (ext && strcasecmp(ext, ".car") == 0) {
        uint8_t hdr[16];
        if (f_read(&f, hdr, 16, &br) != FR_OK || br != 16 ||
            hdr[0] != 'C' || hdr[1] != 'A' || hdr[2] != 'R' || hdr[3] != 'T') {
            f_close(&f);
            if (!mount_silent) message("Not a valid .CAR file", 1);
            return -2;
        }
        car_type = ((uint32_t)hdr[4] << 24) | ((uint32_t)hdr[5] << 16) |
                   ((uint32_t)hdr[6] << 8)  |  (uint32_t)hdr[7];
        for (unsigned i = 0; i < sizeof(car_type_map)/2; i++)
            if (car_type_map[i][0] == car_type) { mode = car_type_map[i][1]; break; }
        if (mode == 0) {
            f_close(&f);
            uart_printf("cart: unsupported CAR type %d\n", (int)car_type);
            char m[40];
            strcpy(m, "Unsupported CAR type ");
            char *e = m + strlen(m);
            if (car_type >= 100) *e++ = '0' + (car_type / 100) % 10;
            if (car_type >= 10)  *e++ = '0' + (car_type / 10) % 10;
            *e++ = '0' + car_type % 10;
            *e = '\0';
            if (!mount_silent) message(m, 1);
            return -3;
        }
        data_size = fsize - 16;
    } else {
        // raw .rom dump: pick the mapper from the size
        switch (fsize) {
            case 2048:  mode = 0x16; break;
            case 4096:  mode = 0x17; break;
            case 8192:  mode = 0x01; break;
            case 16384: mode = 0x21; break;
            default:
                f_close(&f);
                if (!mount_silent) message("Raw .ROM must be 2/4/8/16K\nuse a .CAR instead", 1);
                return -4;
        }
    }
    if (data_size > CART_MAX_SIZE) {
        f_close(&f);
        if (!mount_silent) message("Cartridge too large (>4MB)\ndoes not fit 8MB SDRAM", 1);
        return -5;
    }

    status("Loading cartridge...");
    r = f_read(&f, (void *)CART_SDRAM_BASE, data_size, &br);
    f_close(&f);
    if (r != FR_OK || br != data_size) {
        uart_printf("cart: read failed %d (br=%d/%d)\n", r, (int)br, (int)data_size);
        if (!mount_silent) message("Cartridge read error", 1);
        return -6;
    }
    reg_cart_mode = mode;
    cart_sclust = sclust;                   // phase 2b guard: never write the attached image
    cart_bytes = data_size;                 // CLASSIC_STATE ($1E) tells Horizon
    strncpy(cart_path, filepath, sizeof cart_path - 1);
    cart_path[sizeof cart_path - 1] = 0;
    uart_printf("cart: '%s' loaded, %d bytes, CAR type %d, mode 0x%b\n", filepath, (int)data_size, car_type, mode);   // printf has no %u/%02x: %d + %b
    return 0;
}

int mount_atr(char *filepath, int slot) {
    if (atr_mounted[slot]) {
        f_close(&atr_file[slot]);
        atr_mounted[slot] = false;
    }
    if (slot == 0 && xex_active) {   // an ATR takes D1: back from a mounted XEX
        f_close(&xex_file);
        xex_active = false;
    }

    atr_readonly[slot] = false;
    int r = f_open(&atr_file[slot], filepath, FA_READ | FA_WRITE);
    if (r != FR_OK) {
        // Most common cause: FAT read-only attribute inherited from a PC copy.
        // Strip it and retry before giving up on write access.
        f_chmod(filepath, 0, AM_RDO);
        r = f_open(&atr_file[slot], filepath, FA_READ | FA_WRITE);
    }
    if (r != FR_OK) {
        // Fall back to read-only, but LOUDLY: the slot is flagged, the menu shows
        // "(RO)", STATUS reports write-protect, and writes return 'E' (error 144) —
        // never a silent mount whose writes then fail as a bare error 139.
        r = f_open(&atr_file[slot], filepath, FA_READ);
        if (r != FR_OK) {
            uart_printf("atr open %s %d\n", filepath, r);
            return r;
        }
        atr_readonly[slot] = true;
        uart_printf("atr RO\n");
    }

    // VOLUME-CORRUPTION GUARD: the same file open for WRITE on both slots is
    // illegal in FatFs with FF_FS_LOCK=0 (two FILs with divergent cluster/size
    // state write inconsistent FAT/dir updates -> can destroy the whole volume,
    // HW-confirmed 2026-07: SD card FAT wiped after same-ATR-on-D1+D2 testing).
    // Detect by start cluster and demote THIS mount to read-only.
    if (!atr_readonly[slot]) {
        for (int o = 0; o < ATR_DRIVES; o++) {
            if (o == slot || !atr_mounted[o]) continue;
            if (atr_file[slot].obj.sclust == atr_file[o].obj.sclust) {
                f_close(&atr_file[slot]);
                r = f_open(&atr_file[slot], filepath, FA_READ);
                if (r != FR_OK) return r;
                atr_readonly[slot] = true;
                break;
            }
        }
    }

    char *ext = strrchr(filepath, '.');
    if (ext && strcasecmp(ext, ".xfd") == 0) {
        // .xfd = raw sector dump, no header. Geometry inferred from file size.
        // SD = 92160 (720x128), ED = 133120 (1040x128), DD = 183936 (sectors 1-3 are
        // 128 B, 4+ are 256 B — same boot-sector quirk as ATR). Any other 128-multiple
        // is treated as a 128-B-sector image (offset math is size-independent there).
        uint32_t fsz = f_size(&atr_file[slot]);
        if (fsz == 183936) {
            atr_sector_size[slot] = 256;
        } else if (fsz >= 128 && (fsz % 128) == 0) {
            atr_sector_size[slot] = 128;
        } else {
            uart_printf("bad xfd %d\n", (int)fsz);
            if (!mount_silent) message("Unsupported .xfd size", 1);
            f_close(&atr_file[slot]);
            return -3;
        }
        atr_hdr_off[slot] = 0;
        // 183936 = 384 + 717*256 = the packed layout; a full-boot DD dump would
        // be 184320 and lands in the 128-B branch above (harmless: unmountable
        // geometry either way — keep .xfd behavior unchanged).
        atr_dd_fullboot[slot] = false;
        uart_printf("XFD D%d %s ss %d\n", slot+1, filepath, atr_sector_size[slot]);
        atr_mounted[slot] = true;
        if (atr_readonly[slot] && !mount_silent)
            message("Disk is read-only\nWrites will fail (144)", 1);
        return 0;
    }

    // Read ATR 16-byte header
    uint8_t header[16];
    unsigned int br;
    r = f_read(&atr_file[slot], header, 16, &br);
    if (r != FR_OK || br != 16) {
        uart_printf("atr hdr err %d\n", r);
        f_close(&atr_file[slot]);
        return -1;
    }

    // Verify magic
    uint16_t magic = header[0] | (header[1] << 8);
    if (magic != 0x0296) {
        uart_printf("atr magic %w\n", magic);
        f_close(&atr_file[slot]);
        return -2;
    }

    atr_sector_size[slot] = header[4] | (header[5] << 8);
    if (atr_sector_size[slot] != 128 && atr_sector_size[slot] != 256) {
        uart_printf("bad ss %d\n", atr_sector_size[slot]);
        f_close(&atr_file[slot]);
        return -3;
    }
    atr_hdr_off[slot] = 16;
    // DD layout detection (Altirra's heuristic): data bytes % 256 == 0 means the
    // boot sectors occupy full 256-B slots; the packed layout leaves rem 128.
    atr_dd_fullboot[slot] = (atr_sector_size[slot] == 256) &&
                            ((f_size(&atr_file[slot]) - 16) % 256 == 0);

    uart_printf("ATR D%d %s ss %d%s\n", slot+1, filepath, atr_sector_size[slot],
                atr_dd_fullboot[slot] ? " fullboot" : "");
    atr_mounted[slot] = true;
    if (atr_readonly[slot] && !mount_silent)
        message("Disk is read-only\nWrites will fail (144)", 1);
    return 0;
}

// Sector -> file offset + wire length for the mounted image. DD boot sectors
// 1-3 are 128 B on the wire AND stored packed in the first 384 file bytes in
// BOTH layouts (HW-proven on a real MyDOS 4.5 image: slot-start boot reads
// froze its loader; packed reads run it). atr_dd_fullboot only moves the
// data-area origin: a 768-B boot area (384 used + 384 pad) vs packed 384.
static uint32_t atr_sector_offset(int slot, uint32_t sector_num, int *len) {
    uint32_t base = atr_hdr_off[slot];   // 16 for .atr, 0 for .xfd
    if (atr_sector_size[slot] == 128 || sector_num <= 3) {
        *len = 128;
        return base + (sector_num - 1) * 128;
    }
    *len = 256;
    return base + (atr_dd_fullboot[slot] ? (sector_num - 1) * 256
                                         : 384 + (sector_num - 4) * 256);
}

int atr_read_sector(int slot, uint32_t sector_num, uint8_t *buf, int *sector_len) {
    if (!atr_mounted[slot]) return -1;

    int len;
    uint32_t offset = atr_sector_offset(slot, sector_num, &len);
    *sector_len = len;

    // Out-of-range = error like a real drive. CRITICAL: never f_lseek past
    // EOF — on a writable FIL FatFs ALLOCATES the gap (one stray sector
    // number grew an ATR 92 KB -> 8.4 MB and dirtied the volume; host-proven).
    if (sector_num == 0 || offset + len > f_size(&atr_file[slot])) return -5;

    int r = f_lseek(&atr_file[slot], offset);
    if (r != FR_OK) {
        return r;
    }
    
    unsigned int br;
    r = f_read(&atr_file[slot], buf, len, &br);
    if (r != FR_OK || br != len) {
        uart_printf("rd fail %d got %d\n", sector_num, br);
        return -2;
    }

    return 0;
}

// Mount a .xex as the virtual boot disk on D1:.  Validates the $FFFF header and
// patches the 24-bit byte length into the baked-in loader image so it knows how
// many bytes to pull over SIO.
int mount_xex(char *filepath) {
    if (xex_active) {
        f_close(&xex_file);
        xex_active = false;
    }
    int r = f_open(&xex_file, filepath, FA_READ);
    if (r != FR_OK) {
        uart_printf("xex open %s %d\n", filepath, r);
        // mount_silent: a blocking popup on a BRIDGE-initiated mount parks
        // main() in message()'s key-wait — remote control wedges until a
        // physical Enter (HW-hit 2026-07-20). Remote callers report over
        // serial instead; OSD attach keeps the popup.
        if (!mount_silent) message("Cannot open XEX file", 1);
        return r;
    }
    xex_len = f_size(&xex_file);
    // Sanity: a binary-load file must begin with the $FFFF header word.
    uint8_t h[2];
    unsigned int br;
    if (f_read(&xex_file, h, 2, &br) != FR_OK || br != 2 ||
        h[0] != 0xFF || h[1] != 0xFF) {
        f_close(&xex_file);
        if (!mount_silent) message("Not a valid .XEX\n(missing $FFFF header)", 1);
        return -1;
    }
    // Patch the 24-bit remaining-byte length into the loader's init code.
    xex_loader_img[XEX_REMLO_OFF]  =  xex_len        & 0xFF;
    xex_loader_img[XEX_REMMID_OFF] = (xex_len >> 8)  & 0xFF;
    xex_loader_img[XEX_REMHI_OFF]  = (xex_len >> 16) & 0xFF;
    // Take over D1: from any mounted ATR.
    if (atr_mounted[0]) {
        f_close(&atr_file[0]);
        atr_mounted[0] = false;
    }
    atr_sector_size[0] = 128;   // virtual disk is single density
    xex_active = true;
    uart_printf("xex %s %d\n", filepath, (int)xex_len);
    return 0;
}

// Serve one 128-byte sector of the virtual XEX disk into buf.
int xex_read_sector(uint32_t sector_num, uint8_t *buf, int *sector_len) {
    *sector_len = 128;
    if (sector_num >= 1 && sector_num <= XEX_BLDCNT) {
        // Boot loader image.
        uint32_t base = (sector_num - 1) * 128;
        for (int i = 0; i < 128; i++) buf[i] = xex_loader_img[base + i];
        return 0;
    }
    if (sector_num >= XEX_FIRSTSEC) {
        // Raw .xex bytes, 128 per sector; zero-pad the final partial sector.
        uint32_t off = (sector_num - XEX_FIRSTSEC) * 128;
        for (int i = 0; i < 128; i++) buf[i] = 0;
        if (off < xex_len) {
            unsigned int br;
            uint32_t n = xex_len - off;
            if (n > 128) n = 128;
            if (f_lseek(&xex_file, off) != FR_OK) return -1;
            if (f_read(&xex_file, buf, n, &br) != FR_OK) return -2;
        }
        return 0;
    }
    return -1;   // sector 0 is invalid
}

int atr_write_sector(int slot, uint32_t sector_num, const uint8_t *buf, int len) {
    if (!atr_mounted[slot]) return -1;

    int expect_len;
    uint32_t offset = atr_sector_offset(slot, sector_num, &expect_len);
    if (len != expect_len) return -6;    // caller/geometry disagree — never corrupt

    // same out-of-range guard as atr_read_sector (see comment there)
    if (sector_num == 0 || offset + len > f_size(&atr_file[slot])) return -5;

    int r = f_lseek(&atr_file[slot], offset);
    if (r != FR_OK) {
        return r;
    }
    
    unsigned int bw;
    r = f_write(&atr_file[slot], buf, len, &bw);
    if (r != FR_OK || bw != len) {
        uart_printf("wr fail %d bw %d\n", sector_num, bw);
        return -2;
    }

    f_sync(&atr_file[slot]);
    return 0;
}

// SIO FORMAT: zero-fill the mounted image's whole data area (a freshly formatted
// disk from the drive's point of view; DOS then writes its own FS structures).
// Sequential f_write with a single f_sync — per-sector sync would take ~700x longer.
int atr_format(int slot) {
    if (!atr_mounted[slot] || atr_readonly[slot]) return -1;
    uint32_t base = atr_hdr_off[slot];
    uint32_t total = f_size(&atr_file[slot]);
    if (total < base) return -1;
    uint32_t remaining = total - base;
    if (f_lseek(&atr_file[slot], base) != FR_OK) return -2;
    uint8_t zeros[128];
    memset(zeros, 0, sizeof(zeros));
    while (remaining > 0) {
        unsigned int chunk = remaining > 128 ? 128 : remaining;
        unsigned int bw;
        if (f_write(&atr_file[slot], zeros, chunk, &bw) != FR_OK || bw != chunk) {
            return -3;
        }
        remaining -= chunk;
    }
    if (f_sync(&atr_file[slot]) != FR_OK) return -4;
    return 0;
}

#define SD_PATH_MAX 160                           // parent path + a long file name (FF_LFN_BUF 128)

// PC Link PUT guard: never overwrite a file the firmware holds open (a mounted ATR, the
// virtual .xex, the attached cart image), compared by FAT START CLUSTER so every spelling
// of a path (case, 8.3 alias) is caught. p = scratch FIL for the probe.
// (The H: device and the ASH sd: XIOs that also used this were removed, Atari816.)
static int sd_guarded_p(const char *path, FIL *p) {
    if (f_open(p, path, FA_READ)) return 0;    // missing, or a directory: nothing open on it
    uint32_t c = p->obj.sclust;
    f_close(p);
    for (int s = 0; s < ATR_DRIVES; s++)
        if (atr_mounted[s] && atr_file[s].obj.sclust == c) return 1;
    if (xex_active && xex_file.obj.sclust == c) return 1;
    // Only while a cart is actually mapped (an ejected cart image may be replaced).
    if ((reg_cart_mode & 0xff) && cart_sclust == c) return 1;
    return 0;
}

// ── Boot watchdog (INVESTIGATE #21: the "6502 never returns" cold-boot lottery) ──────
// load_system_roms() writes a sentinel into RTCLOK ($12-$14) while the core is still held in
// reset, then arms this check on release. A cold-starting OS overwrites RTCLOK within
// milliseconds (RAM clear, then the VBI counts), so if the sentinel is still there 1.5 s AND
// 2.5 s later the 6502 never ran its cold start. (COLDST/RTCLOK-frozen would misfire: a disk
// game that takes over early leaves COLDST=1 and may own the VBI.) On a stall the same long
// reset is re-issued with the same OPTION state the caller used (bounded), logged and counted.
static uint32_t bootwd_t0 = 0, bootwd_kbd = 0;
#define BOOTWD_SENTINEL 0xA5C3A5u
static uint8_t  bootwd_state = 0, bootwd_warm = 0;
uint8_t         boot_retries = 0;
uint32_t        virt_key_release_at = 0;     // deferred release for bridge KEY (see joy_get)
static inline uint32_t atari_rtclok(void) {
    volatile uint8_t *z = (volatile uint8_t *)0x00200000;
    return ((uint32_t)z[0x12] << 16) | ((uint32_t)z[0x13] << 8) | z[0x14];
}
static void bootwd_arm(void) { bootwd_t0 = time_millis(); bootwd_kbd = kv0; bootwd_state = 1; bootwd_warm = 0; }
static void bootwd_sentinel(void) {           // call while the core is held in reset
    volatile uint8_t *z = (volatile uint8_t *)0x00200000;
    z[0x12] = 0xA5; z[0x13] = 0xC3; z[0x14] = 0xA5;
}
// Warm start (F9 / OSD Soft Reset / bridge WARM): COLDST=0 + the 20 ms reset pulse, with the
// watchdog armed the same way as a cold boot (a warm-started OS advances RTCLOK within a
// frame, so the sentinel test holds). A stalled warm reset is retried with the same pulse.
void warm_reset(void) {
    *(volatile uint8_t *)(0x00200000 + 0x0244) = 0;   // COLDST = 0
    reg_romload_ctrl = 1;
    delay(20);
    bootwd_sentinel();
    reg_romload_ctrl = 0;
    bootwd_arm();
    bootwd_warm = 1;
}

int load_system_roms(void) {
    FIL f;
    unsigned int br;
    int r;
    
    // Hold Atari core in reset
    reg_romload_ctrl = 1;
    delay(10);

    // Power-cycle the emulated cartridge. The core's CartLogic bank latch is NOT
    // reset by the system reset (faithful: the XL cart port has no reset line,
    // so a real cart keeps its bank/enable across RESET - Altirra F5 matches).
    // Its only reset is a cart_mode CHANGE, so without this a cold boot with a
    // multicart that had disabled itself (e.g. Atarimax "Turbo Oro", .car type
    // 75) came up with no cart -> BASIC / Self Test instead of the cart menu.
    // A real power cycle (and Altirra Shift+F5) restores bank 0 + enabled; do
    // the same here while the core is held in reset.
    {
        uint32_t cart_mode = reg_cart_mode & 0xff;
        if (cart_mode != 0) {
            reg_cart_mode = 0;
            delay(1);
            reg_cart_mode = cart_mode;
            delay(1);
        }
    }

    // Force cold boot on next boot
    *(volatile uint8_t *)(0x00200000 + 0x0244) = 1; // COLDST = 1
    
    // Load OS.ROM
    r = f_open(&f, "/ATARIXL.ROM", FA_READ);
    if (r != FR_OK) {
        r = f_open(&f, "/atarixl.rom", FA_READ);
    }
    if (r != FR_OK) {
        uart_printf("Failed to open OS.ROM\n");
        status("Failed to open OS.ROM");
        reg_romload_ctrl = 0;
        return (1 << 8) | r;
    }
    
    // Load OS.ROM into SDRAM at the address the Atari core's address_decoder expects:
    // SDRAM_OS_ROM_ADDR (XL/XE mode, low_memory=0) = physical 0x1F4000, at the top of
    // physical bank 0 so the RAM region below can grow to 1088 KB. Firmware addr
    // 0x003F4000 -> physical 0x1F4000 via the iosys bank-0/1 swap. Keep in sync with
    // address_decoder.vhdl.
    volatile uint8_t *os_rom_ptr = (volatile uint8_t *)0x003F4000;
    r = f_read(&f, (void *)os_rom_ptr, 16384, &br);
    f_close(&f);
    if (r != FR_OK || br != 16384) {
        uart_printf("Failed to read OS.ROM\n");
        status("Failed to read OS.ROM");
        reg_romload_ctrl = 0;
        return (2 << 8) | r;
    }
    uart_printf("os rom ok %d\n", br);
    
    // Load BASIC.ROM
    r = f_open(&f, "/BASIC.ROM", FA_READ);
    if (r != FR_OK) {
        r = f_open(&f, "/basic.rom", FA_READ);
    }
    if (r != FR_OK) {
        uart_printf("Failed to open BASIC.ROM\n");
        status("Failed to open BASIC.ROM");
        reg_romload_ctrl = 0;
        return (3 << 8) | r;
    }
    
    // Load BASIC.ROM into SDRAM at the address the Atari core's address_decoder expects:
    // SDRAM_BASIC_ROM_ADDR (low_memory=0) = physical 0x1F0000, at the top of physical
    // bank 0 (above the 1088 KB RAM region). Firmware addr 0x003F0000 -> physical
    // 0x1F0000 via the iosys bank-0/1 swap. Keep in sync with address_decoder.vhdl.
    volatile uint8_t *basic_rom_ptr = (volatile uint8_t *)0x003F0000;
    r = f_read(&f, (void *)basic_rom_ptr, 8192, &br);
    f_close(&f);
    if (r != FR_OK || br != 8192) {
        uart_printf("Failed to read BASIC.ROM\n");
        status("Failed to read BASIC.ROM");
        reg_romload_ctrl = 0;
        return (4 << 8) | r;
    }
    uart_printf("basic rom ok %d\n", br);
    
    // Release reset (sentinel first, while the 6502 is still held)
    bootwd_sentinel();
    reg_romload_ctrl = 0;
    bootwd_arm();
    status("ROMs loaded successfully");
    // Give the SD card SPI bus a moment to settle before ATR file operations resume.
    sio_delay(50);
    return 0;
}

bool sio_rx_empty(void) {
    return (reg_sio_rx_stat & 0x100) != 0;
}

__attribute__((section(".coldtext"))) void sio_init(void) {   // once at boot: cold
    reg_sio_divisor = 0x5D; // divisor 93 — matches the Atari's measured bit period
                            // (the WIP regressed this to 94 / 0x5E; measured rate is 93)
    
    // Flush RX FIFO (up to 1024 bytes maximum to prevent hangs if status is stuck)
    for (int i = 0; i < 1024 && !sio_rx_empty(); i++) {
        (void)reg_sio_rx;
    }
    
    sio_cmd_idx = 0;
    sio_cmd_timeout = 0;

    dbg_last_sio_cmd = 0;
    dbg_last_sio_sector = 0;
    dbg_last_sio_status = 0;
    dbg_sio_err_count = 0;
}

void delay_us(uint32_t us) {
    uint32_t start = reg_cycle;
    uint32_t cycles = us * 27; // 27 MHz clock
    while (reg_cycle - start < cycles) {
        // busy wait
    }
}

void delay_ms(uint32_t ms) {
    delay_us(ms * 1000);
}

void sio_delay(int ms) {
    uint32_t start = time_millis();
    while (time_millis() - start < ms) {
        sio_poll();
        in_tick();
    }
}

static void bootwd_poll(void) {
    uint32_t now = time_millis();
    // A classic machine frozen by Horizon (keymod bit 9) never overwrites the sentinel:
    // hold the timer instead of retrying a machine that is only paused.
    if (reg_a816_keymod & 0x200) { bootwd_t0 = now; return; }
    if (bootwd_state == 1) {
        if (now - bootwd_t0 < 1500) return;
        if (atari_rtclok() != BOOTWD_SENTINEL) { bootwd_state = 0; return; }   // OS ran: done
        bootwd_t0 = now; bootwd_state = 2;
    } else if (bootwd_state == 2) {
        if (now - bootwd_t0 < 1000) return;
        bootwd_state = 0;
        if (atari_rtclok() == BOOTWD_SENTINEL && boot_retries < 6) {
            boot_retries++;
            uart_printf("boot: watchdog retry %d\n", boot_retries);
            if (bootwd_warm) { warm_reset(); return; }
            uint32_t kbd = bootwd_kbd;
            kv_set0(kbd);             // same OPTION state as the boot that stalled
            load_system_roms();               // long clean reset + release; re-arms the check
            if (kbd) { sio_delay(400); kv_set0(0); }
        }
    }
}

void sio_tx_byte(uint8_t b) {
    while (reg_sio_tx_stat & 0x200) {
        // Wait until TX FIFO is not full
    }
    reg_sio_tx = b;
}

void sio_wait_tx_empty(void) {
    // Bounded: if the p2s ever stops draining (e.g. POKEY_ENABLE stalls), this must
    // NOT hang the firmware forever, or the main loop can't service the menu key.
    uint32_t start = reg_cycle;
    while (!(reg_sio_tx_stat & 0x100)) {
        if ((uint32_t)(reg_cycle - start) > 27u * 20000u) break; // 20 ms safety cap
    }
    // Wait for the last byte to finish serializing on wire (520us @ 19200)
    delay_us(600);
}

// Wait until the Atari deasserts the SIO command line (reg_sio_diag bit13 = 1),
// i.e. the command frame is over and the computer is turning around to receive.
// Lets us send the ACK as early as possible without sending it too early (while
// the Atari is still transmitting / not yet listening). Bounded so we never hang.
void sio_wait_cmd_high(void) {
    uint32_t start = reg_cycle;
    while (((reg_sio_diag >> 13) & 1) == 0) {
        if ((uint32_t)(reg_cycle - start) > 27u * 4000u) break; // 4 ms safety cap
    }
}

// Atari SIO checksum: 8-bit sum with END-AROUND CARRY (NOT plain mod-256).
// Every overflow out of bit 7 is added back into bit 0. A plain (sum & 0xFF)
// is wrong whenever the running sum carries, which makes the Atari reject our
// STATUS/READ data frames (their sums almost always carry) -> "no disk".
static uint8_t sio_checksum(const uint8_t *buf, int len) {
    uint8_t sum = 0;
    for (int i = 0; i < len; i++) {
        uint16_t t = (uint16_t)sum + buf[i];
        sum = (uint8_t)((t & 0xFF) + (t >> 8)); // fold the carry back in
    }
    return sum;
}

int sio_rx_data_frame(uint8_t *buf, int len) {
    int idx = 0;
    uint8_t checksum = 0;
    uint32_t start_time = time_millis();
    
    while (idx < len + 1) {
        if ((time_millis() - start_time) > 1000) { // 1 second timeout
            uart_printf("rx timeout idx %d\n", idx);
            return -1;
        }
        if (!sio_rx_empty()) {
            uint16_t rx_val = reg_sio_rx;
            uint8_t byte = rx_val & 0xFF;
            uint8_t cmd_count = (rx_val >> 8) & 0x7F;
            
            if (cmd_count != 0) {
                uart_printf("cmd during rx idx %d\n", cmd_count);
                return -2;
            }
            
            if (idx < len) {
                buf[idx] = byte;
                uint16_t t = (uint16_t)checksum + byte;
                checksum = (uint8_t)((t & 0xFF) + (t >> 8)); // end-around carry
            } else {
                if (checksum == byte) {
                    return 0; // Success
                } else {
                    uart_printf("data cksum %b != %b\n", checksum, byte);
                    return -3;
                }
            }
            idx++;
        }
    }
    return -4;
}

extern int bridge_req;
extern char bridge_req_path[SD_PATH_MAX];

// the cartridge's name (16 B, mounted_cart_name) = basename of an SD path
static void name_from_path(char *dst, const char *path) {
    const char *base = strrchr(path, '/');
    strncpy(dst, base ? base + 1 : path, 16);
    dst[15] = '\0';
}

void sio_process_command(void) {
    // NOTE: auto-baud tuning removed (T2) — it read reg_sio_divisor, which is a
    // *different* (measured-receive) register than the TX divisor it writes, and
    // could silently corrupt the TX baud. TX divisor stays fixed (set in sio_init).

    uint8_t device = sio_cmd_buf[0];
    uint8_t cmd = sio_cmd_buf[1];
    uint8_t aux1 = sio_cmd_buf[2];
    uint8_t aux2 = sio_cmd_buf[3];
    uint8_t checksum = sio_cmd_buf[4];
    
    // Verify checksum of command frame (end-around carry, same as the Atari)
    uint8_t calc_sum = sio_checksum(sio_cmd_buf, 4);
    if (calc_sum != checksum) {
        uart_printf("cmd cksum %b != %b\n", checksum, calc_sum);
        dbg_sio_err_count++;
        return;
    }
    
    // (H: 0x72 was removed, Atari816.) (Step 3) P1:-P4: ($40-$43) are the printer: STATUS and
    // WRITE only; the records become print jobs (prn_put, prn_service).
    // Respond to D1:-D4: (Device IDs 0x31-0x34; D3/D4 = config/bridge drives)
    int prn = (device & 0xFC) == 0x40;
    if (!prn && (device < 0x31 || device > 0x30 + ATR_DRIVES)) {
        return;
    }
    int slot = prn ? 0 : device - 0x31;
    if (prn && cmd != 0x53 && cmd != 0x57) cmd = 0;     // (anything else: NAK)

    // An EMPTY drive slot stays SILENT — no drive on the bus. Answering 'E' to
    // the OS's boot probe makes it loop "BOOT ERROR" instead of falling through
    // to BASIC (HW-hit 2026-07-18 when the sio_poll mounted-gate moved to make
    // the printer reachable; the gate belongs per-device, not globally).
    if (!prn && !atr_mounted[slot] && !(slot == 0 && xex_active) && !rd_kind[slot])
        return;

    uint16_t sector = aux1 | (aux2 << 8);
    dbg_last_sio_cmd = cmd;
    dbg_last_sio_sector = sector;
    dbg_last_sio_status = 0;

    // Send the ACK as early as the protocol allows: wait only until the Atari
    // releases the command line (it's then turning around to receive), instead
    // of a fixed multi-ms delay. On this fast machine the ACK window is narrow,
    // so minimizing response latency is what lets the ACK land inside it.
    sio_wait_cmd_high();

    switch (cmd) {
        case 0x53: { // Status command
            // 1. Send ACK (with command-to-ACK SIO delay)
            delay_us(250);
            sio_tx_byte(0x41); // 'A'
            sio_wait_tx_empty();
            
            // 2. Prepare status block (4 bytes)
            uint8_t status_block[4];
            status_block[0] = prn ? 0 : 0x10; // Drive active (bit 4)
            if (!prn && atr_sector_size[slot] == 256) {
                status_block[0] |= 0x20; // Double density (bit 5)
            }
            if (!prn && atr_readonly[slot]) {
                status_block[0] |= 0x08; // Write protected (bit 3)
            }
            
            status_block[1] = 0xFF; // Hardware status
            status_block[2] = 0xE0; // Timeout
            status_block[3] = 0x00;
            
            // Calculate status block checksum (Atari end-around carry)
            uint8_t sum = sio_checksum(status_block, 4);

            // 3. Delay 1ms (ACK-to-Complete delay)
            delay_us(250);

            // 4. Send Complete (must precede the data frame for reads/status)
            sio_tx_byte(0x43); // 'C'
            sio_wait_tx_empty();

            // 5. Delay 1ms (Complete-to-Data delay)
            delay_us(250);

            // 6. Send status bytes
            for (int i = 0; i < 4; i++) {
                sio_tx_byte(status_block[i]);
            }

            // 7. Send checksum
            sio_tx_byte(sum);
            sio_wait_tx_empty();
            break;
        }
        
        case 0x52: { // Read sector command
            // NO per-sector uart_printf here: a working DOS reads hundreds of
            // sectors and the log flood crash-loops the BL616's FT2232-emu USB
            // stack (HW-proven 2026-07-20: first successful MyDOS boot = serial
            // link started flapping). dbg_sio_read_count / dbg_last_sio_sector
            // carry the same info to STATUS and the OSD debug line.
            uint8_t *sector_buf = sio_sector_buf;
            int sector_len = 128;
            
            // 1. Send ACK first to satisfy the tight 16ms command-to-ACK window
            delay_us(250);
            sio_tx_byte(0x41); // 'A' (ACK)
            sio_wait_tx_empty();
            
            // 2. Perform the slow read from the SD card (takes several milliseconds)
            int r = (slot == 0 && xex_active)
                        ? xex_read_sector(sector, sector_buf, &sector_len)
                        : rd_kind[slot] ? rd_read(slot, sector, sector_buf)
                        : atr_read_sector(slot, sector, sector_buf, &sector_len);
            if (r == 0) {
                // Calculate checksum of sector data (Atari end-around carry)
                uint8_t sum = sio_checksum(sector_buf, sector_len);

                // 3. Delay 1ms (ACK-to-Complete delay)
                delay_us(250);

                // 4. Send Complete (must precede the data frame for reads)
                sio_tx_byte(0x43); // 'C' (Complete)
                sio_wait_tx_empty();

                // 5. Delay 1ms (Complete-to-Data delay)
                delay_us(250);

                // 6. Send sector data
                for (int i = 0; i < sector_len; i++) {
                    sio_tx_byte(sector_buf[i]);
                }

                // 7. Send checksum
                sio_tx_byte(sum);
                sio_wait_tx_empty();
            } else {
                uart_printf("rd %d fail\n", sector);
                dbg_last_sio_status = r;
                dbg_sio_err_count++;
                delay_us(250);
                sio_tx_byte(0x45); // 'E' (Error)
            }
            break;
        }
        
        case 0x57:   // Write sector command (with verify)
        case 0x50: { // Write sector command (without verify)
            // no per-sector log — see READ (BL616 flood)
            uint8_t *sector_buf = sio_sector_buf;
            int sector_len = prn ? (aux1 == 'S' ? 29 : aux1 == 'D' ? 20 : 40)   // (prn_reclen)
                           : (atr_sector_size[slot] == 128 || sector <= 3) ? 128 : 256;

            // Send ACK (with command-to-ACK SIO delay)
            delay_us(250);
            sio_tx_byte(0x41); // 'A'
            sio_wait_tx_empty();

            // Read data frame from computer
            int r = sio_rx_data_frame(sector_buf, sector_len);
            if (r == 0) {
                // Data frame verified: ACK it IMMEDIATELY — the computer's window for
                // this ACK is tight (sub-16 ms), and the SD write + f_sync below can
                // take tens of ms (FAT update, card GC). Doing the write before the
                // ACK made the OS time out and retry, leaving multi-sector operations
                // (data+VTOC+directory) half-applied = a corrupted filesystem. The
                // slow operation belongs between ACK and 'C'/'E', which is what the
                // long OS timeout is for.
                delay_us(250);
                sio_tx_byte(0x41); // 'A'
                sio_wait_tx_empty();

                int wr = prn ? prn_put(sector_buf, sector_len)
                          : atr_readonly[slot] ? -9
                          : rd_kind[slot] ? rd_write(slot, sector, sector_buf)
                          : atr_write_sector(slot, sector, sector_buf, sector_len);
                delay_us(250);
                if (wr == 0) {
                    sio_tx_byte(0x43); // 'C'
                } else {
                    // Post-ACK failures report 'E' (OS error 144), like a real drive
                    // with a write-protected/failing disk. NAK is only valid in the
                    // ACK slot.
                    uart_printf("wr %d fail %d\n", sector, wr);
                    dbg_last_sio_status = wr;
                    dbg_sio_err_count++;
                    sio_tx_byte(0x45); // 'E'
                }
            } else {
                uart_printf("rx frame sec %d err %d\n", sector, r);
                dbg_last_sio_status = r;
                dbg_sio_err_count++;
                delay_us(250);
                sio_tx_byte(0x4E); // 'N' (NAK) — asks the OS to resend the frame
            }
            break;
        }

        case 0x21:   // Format disk (image's own geometry)
        case 0x22: { // Format enhanced/medium density (1050 ED only)
            uart_printf("SIO FORMAT %b\n", cmd);
            uint8_t *sector_buf = sio_sector_buf;
            int sector_len = (atr_sector_size[slot] == 256) ? 256 : 128;
            uint32_t data_size = atr_mounted[slot]
                ? f_size(&atr_file[slot]) - atr_hdr_off[slot] : 0;
            // NAK what we can't do: empty/read-only drive, or 0x22 on a non-ED
            // image (DOS 2.5 probes 0x22 and falls back to 0x21 on NAK).
            if (!atr_mounted[slot] || atr_readonly[slot] ||
                (cmd == 0x22 && data_size != 1040u * 128u)) {
                dbg_last_sio_status = -9;
                dbg_sio_err_count++;
                delay_us(250);
                sio_tx_byte(0x4E); // 'N'
                break;
            }
            delay_us(250);
            sio_tx_byte(0x41); // 'A'
            sio_wait_tx_empty();

            // Zero-fill the image (may take seconds — the OS format timeout is long).
            int r = atr_format(slot);
            if (r != 0) {
                uart_printf("Format failed (%d)\n", r);
                dbg_last_sio_status = r;
                dbg_sio_err_count++;
            }
            // 'C'/'E' + data frame: the bad-sector table, all $FF = no bad sectors.
            // The frame is sent after 'E' too — the OS reads it either way.
            memset(sector_buf, 0xFF, sector_len);
            uint8_t sum = sio_checksum(sector_buf, sector_len);
            delay_us(250);
            sio_tx_byte(r == 0 ? 0x43 : 0x45); // 'C' / 'E'
            sio_wait_tx_empty();
            delay_us(250);
            for (int i = 0; i < sector_len; i++) {
                sio_tx_byte(sector_buf[i]);
            }
            sio_tx_byte(sum);
            sio_wait_tx_empty();
            break;
        }
        
        default:
            uart_printf("SIO? %b\n", cmd);
            dbg_sio_err_count++;
            delay_us(250);
            sio_tx_byte(0x4E); // 'N' (NAK)
            break;
    }
}

// sio_poll() — call as frequently as possible from the main loop.
#ifndef SIO_SW_FALLBACK
// Phase B: hardware command-frame capture path (DEFAULT; build -DSIO_SW_FALLBACK for the
// old software-assembly path).
// The 5-byte command frame is assembled in the FPGA (sio_handler snoop); we poll a
// ready flag + seq counter, read the bytes, flush the command bytes the snoop left
// in the RX FIFO, then dispatch exactly as the software path does. The real-time SIO
// timing lives in hardware so a busy firmware loop can no longer miss a command.
static uint8_t sio_hw_last_seq = 0;
static void sio_poll_hwcapture(void) {
    // (no mounted-gate: the P: printer must answer even with no disks attached)

    uint32_t b = reg_siocmd_b;
    uint8_t status = (b >> 8) & 0xff;        // b0=ready b1=error b2=active b3=overrun
    uint8_t seq    = (b >> 16) & 0xff;
    if (!(status & 0x01)) return;            // no command ready
    if (seq == sio_hw_last_seq) return;      // already serviced this frame
    sio_hw_last_seq = seq;

    uint32_t a = reg_siocmd_a;
    sio_cmd_buf[0] = a & 0xff;               // device
    sio_cmd_buf[1] = (a >> 8) & 0xff;        // command
    sio_cmd_buf[2] = (a >> 16) & 0xff;       // aux1
    sio_cmd_buf[3] = (a >> 24) & 0xff;       // aux2
    sio_cmd_buf[4] = b & 0xff;               // checksum
    reg_siocmd_b = 0;                        // ack / re-arm

    // The snoop left the 5 command bytes in the RX FIFO. The data frame (for write
    // commands) only arrives after we ACK, so the FIFO holds exactly those 5 now —
    // drain them so the upcoming data phase starts clean.
    while (!sio_rx_empty()) { (void)reg_sio_rx; }

    sio_process_command();
    sio_cmd_idx = 0;
    while (!sio_rx_empty()) { (void)reg_sio_rx; }
}
#endif

// Accumulates SIO command frame bytes using cmd_count from the FIFO word:
//   cmd_count == 1..5: byte is part of a command frame (1=first, 5=checksum)
//   cmd_count == 0:    data-phase byte (handled inside sio_process_command)
// We reset if too much time passes without completing a frame (line glitch recovery).
void sio_poll(void) {
#ifndef SIO_SW_FALLBACK
    sio_poll_hwcapture();
    return;
#endif
    if (!atr_mounted[0] && !atr_mounted[1] && !xex_active) return;

    // Timeout: if a partial frame sits for >200 ms, reset accumulator
    if (sio_cmd_idx > 0 && (time_millis() - sio_cmd_timeout) > 200) {
        uart_printf("SIO: frame timeout, resetting (had %d bytes)\n", sio_cmd_idx);
        sio_cmd_idx = 0;
    }

    for (int i = 0; i < 256 && !sio_rx_empty(); i++) {
        uint16_t rx_val  = reg_sio_rx;
        uint8_t  byte      = rx_val & 0xFF;
        uint8_t  cmd_active = (rx_val >> 8) & 1;

        if (!cmd_active) {
            // Data-phase byte — not expected here; ignore
            continue;
        }

        // A command frame starts if we were idle (sio_cmd_idx == 0) or if a timeout occurred (>50ms gap)
        if (sio_cmd_idx == 0 || (time_millis() - sio_cmd_timeout) > 50) {
            sio_cmd_idx     = 0;
            sio_cmd_timeout = time_millis();
        } else {
            sio_cmd_timeout = time_millis();
        }

        // Accept byte if it's the next expected one
        if (sio_cmd_idx < 5) {
            sio_cmd_buf[sio_cmd_idx++] = byte;
        }

        if (sio_cmd_idx == 5) {
            sio_process_command();
            sio_cmd_idx = 0;

            // Anti-lag resync: the response above blocks for several ms, during
            // which the Atari may fire off command retries that pile up in the RX
            // FIFO. Those are stale — answering them puts us permanently a step
            // behind the Atari (its ACK window has already closed). Discard them
            // and let the NEXT sio_poll catch the Atari's current, fresh command.
            while (!sio_rx_empty()) { (void)reg_sio_rx; }
            break;
        }
    }
}

// Cold-boot the Atari. Caller flips booted/overlay.
// Uses load_system_roms()'s LONG clean reset (core held down for the full ROM
// reload), NOT a short reg_romload_ctrl pulse: the 20 ms pulse was an
// intermittent-stall lottery — the 6502 sometimes never came back (black
// screen, RTCLOK frozen, COLDST still 1; HW-autopsied 2026-07-19 after a
// cart detach). Identical to the fix that cured xex attach-auto-boot (#2)
// and Boot OS (#3): every cold-boot flow now shares the proven sequence.
// Default cartridge (Options "Boot: ASH" / atari.ini boot=ash). Called from the power-on
// path and from cold_boot_atari(): when a cold boot finds the cart slot EMPTY, /ASH.CAR
// goes in. So power-on, Hard Reset, Cart->Detach and a bridge cold reset all come back
// to the shell; a game cart attached from the OSD is only "borrowed" (its mode is set
// before the cold boot, never overridden); Boot to OS / Boot to BASIC bypass this (they
// call load_system_roms directly). Missing or bad file = silent fallback to BASIC (the
// HDD.ATR rule): the OSD Cart line stays "None" and the uart log says why.
static void load_default_cart(void) {
    if (!option_boot_ash || (reg_cart_mode & 0xff) != 0) return;
    mount_silent = 1;
    if (load_cartridge(ASH_CART_FILE) == 0)
        strcpy(mounted_cart_name, "ASH.CAR");
    else
        uart_printf("boot: no %s -> BASIC\n", ASH_CART_FILE);
    mount_silent = 0;
}

// Take the ASH cart OUT for one boot: Boot to BASIC, and every .xex boot (an enabled
// cartridge takes the boot before the OS ever looks at D1:, so `atari.py run` and OSD
// Attach .xex would otherwise land in the shell). A game cart stays in, as today.
// The next Hard Reset / Detach / bridge cold boot puts ASH back (load_default_cart).
static void drop_default_cart(void) {
    if (strcmp(mounted_cart_name, "ASH.CAR") != 0) return;
    reg_cart_mode = 0;
    strcpy(mounted_cart_name, "None");
}

static void classic_cold_hooks(void);          // (step 3) print job ended, folder disk saved and built again
static int cold_boot_atari(void) {             // returns load_system_roms() (0 = OK)
    classic_cold_hooks();
    kv_set0(0x00000000);
    apply_machine_options();                        // RAM_SELECT stable before core leaves reset
    sio_init();
    load_default_cart();                            // boot=ash and slot empty -> /ASH.CAR
    *(volatile uint8_t *)(0x00200000 + 0x0244) = 1; // COLDST = 1 (Cold start)
    return load_system_roms();                      // long clean reset + release
}

// Cold-boot the virtual XEX disk on D1: with OPTION held (BASIC disabled), then
// keep servicing SIO so the boot loader's sector reads are answered during boot.
static int cold_boot_xex(void) {               // returns load_system_roms() (0 = OK)
    classic_cold_hooks();
    drop_default_cart();                            // the xex must get the boot, not ASH
    kv_set0(0x00410000);                    // hold OPTION (disable BASIC)
    sio_init();                                     // SIO ready before the core is released
    // Use the SAME reliable sequence as the "Boot OS" menu item, which boots an attached
    // .xex correctly. load_system_roms() holds the core in reset for the full ROM reload
    // (a long, clean hold) and sets COLDST=1, then releases. The previous short
    // reg_romload_ctrl pulse (delay 20) left the attach-auto-boot intermittently stuck while
    // "Boot OS" always worked (HW-observed 2026-06-30: attach->stuck, Hard->stuck, Boot OS->loads).
    int r = load_system_roms();
   
    sio_delay(600);                                 // serve boot reads while OPTION held + UNMASKED
    kv_set0(0x00000000);                    // release OPTION
    return r;
}

// (step 3) "Run in Atari": the boot disk on D1: with Atari BASIC enabled (no OPTION held, the
// default cartridge out for this boot, as for an executable)
static int cold_boot_basic(void) {
    classic_cold_hooks();
    drop_default_cart();
    kv_set0(0x00000000);
    apply_machine_options();
    sio_init();
    *(volatile uint8_t *)(0x00200000 + 0x0244) = 1; // COLDST = 1
    return load_system_roms();
}

// ── PC link (Docs/04-pc-link.md; engine in pclink.c) ─────────────────────────────────
// The serial port to the PC carries framed packets: the firmware's log (channel 1), the PC
// volume (channel 2, a816_mailbox below) and the developer channel (channel 3: the PC tools
// send files to the card, restart the 65C816, read memory, press keys; pl_dev_request below).
// RUN / COLD / WARM are queued (bridge_req) and executed by the main loop.

static FIL bridge_file;
int bridge_req = 0;                     // 1 = run xex, 2 = cold boot, 3 = warm
char bridge_req_path[SD_PATH_MAX];      // full path, subfolders allowed (sd_resolve'd names too)
int bridge_boot_stage = 0;   // 0 start, 1 sd ok, 2 options, 3 roms tried, 4 running
int bridge_rom_ok = -1;

// FS half of PUT — kept protocol-free so test/fatfs_host extracts and
// exercises them against a disk image before any hardware run.
// Create every missing directory along "/A/B/NAME" (mkdir /A, then /A/B).
int bridge_mkdirs(char *path) {
    for (char *p = path + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            FRESULT r = f_mkdir(path);
            *p = '/';
            if (r != FR_OK && r != FR_EXIST) return -1;
        }
    }
    return 0;
}
int bridge_put_open(const char *path) {
    // Never overwrite a file the firmware holds open (a mounted ATR, the virtual
    // .xex, an H: handle, the attached cart): the same-file-open-twice case that
    // wiped a card in 2026-07. Names (ROMs, atari.ini) are NOT guarded here — the
    // PC link is the ROM-rescue path. The PC gets a NAK; ashterm reports it.
    if (sd_guarded_p(path, &bridge_file)) return -1;
    return f_open(&bridge_file, path, FA_CREATE_ALWAYS | FA_WRITE);
}
// 0 ok, else the FRESULT (FR_DENIED if the card took fewer bytes than asked).
int bridge_put_chunk(const uint8_t *buf, unsigned int len) {
    unsigned int bw;
    FRESULT r = f_write(&bridge_file, buf, len, &bw);
    if (r != FR_OK) return (int)r;
    return bw != len ? (int)FR_DENIED : 0;
}
int bridge_put_close(void) {
    return f_close(&bridge_file) == FR_OK ? 0 : -1;
}

// ── Atari816 bring-up 1 ─────────────────────────────────────────────────────
// The 65C816's native $00:0000-$0F:FFFF sits at firmware address 0x100000 + native
// (physical SDRAM 0x300000). Its cache is only flushed while RUN = 0, so every write
// to that memory from here must happen with the CPU held.
#define A816_MEM ((volatile uint8_t *)0x00100000)

HOT_FN void in_mouse(int btn, int dx, int dy, int wheel);
static void a816_poll(void) {        // 65C816 debug bytes -> serial log, one line at a time
    static char ln[64];
    static uint8_t n;
    uint32_t v;
    while ((v = reg_a816_dbg) & 0x100) {
        reg_a816_dbg = 0;
        if ((v & 0xFF) == 10 || n == sizeof ln - 1) { ln[n] = 0; n = 0; uart_printf("816: %s\n", ln); }
        else ln[n++] = (char)v;
    }
}

static void a816_mailbox(void);
static uint8_t mb_synced;            // 1 after SYS_SYNC ($1C): volume unmounted until a restart
static void fs_remount(void) {       // undo SYS_SYNC: lazy mount, the card is re-initialised on use
    if (!mb_synced) return;
    f_mount(&fs, "", 0);
    mb_synced = 0;
    uart_printf("sys: card mounted again\n");
}
static void a816_start(int test) {   // test: /A816.BIN only (run816)
          // load /SYSTEM/HORIZON.SYS (or /A816.BIN) to $01:0000, write the reset stub, run
    static const uint8_t stub[] = { 0x18, 0xFB, 0x5C, 0x00, 0x00, 0x01 };   // CLC XCE JML $010000
    FIL f;
    UINT br = 0;
    reg_a816_ctrl = 0;
    reg_a816_mbi = 0;
    a816_mailbox();                                           // closes the old run's files
    fs_remount();                                             // after SYS_SYNC
    if ((test || f_open(&f, "/SYSTEM/HORIZON.SYS", FA_READ)) && f_open(&f, "/A816.BIN", FA_READ)) return;
    f_read(&f, (void *)(A816_MEM + 0x10000), 0xFF00, &br);
    f_close(&f);
    for (int i = 0; i < 6; i++) A816_MEM[0xFF00 + i] = stub[i];
    A816_MEM[0xFF10] = 0xDB;                                  // STP: every other vector
    for (int i = 0xFFE0; i < 0x10000; i += 2) { A816_MEM[i] = 0x10; A816_MEM[i + 1] = 0xFF; }
    A816_MEM[0xFFFC] = 0x00;                                  // RESET -> $FF00
    uart_printf("816: loaded %d bytes, run\n", (int)br);
    reg_a816_ctrl = 1;
}

// ── Atari816 I/O processor mailbox (register spec, "I/O processor mailbox") ──
// Two rings of 16-byte messages in the 65C816's RAM. One request is served per call.
// Result codes: 0 OK, 1..19 FatFs FRESULT, $80 bad handle, $81 bad address, $82 unsupported,
// $83-$85 see ops $18-$1A, $86 refused: the card was synced (SYS_SYNC) and not mounted again,
// $87 no PC link, $88 PC link lost, $89 RENAME between the card and the PC.
// The PC volume: a path "/PC:" or "/PC:/..." (any case) is a file or folder in the folder the
// gateway on the PC shares (Docs/04-pc-link.md); the same ops and the same 4 handles work on
// it. Without a gateway such ops answer $87 at once. "/" lists a folder "PC:" last while the
// PC volume is there, and STAT "/PC:" gives the PC's clock as the time.
// Ops: $01-$0A files, $10 LOAD, $18-$1A classic machine, $1B SYS_RESTART, $1C SYS_SYNC,
// $1D SYS_TIME, $1E CLASSIC_STATE.
// When data reaches the card (FatFs, FF_FS_TINY, one shared 512-byte sector window): a WRITE
// sends every whole 512-byte sector it covers straight to the card; a partial last sector and
// the FAT changes stay in the window until FatFs needs it for another sector (any later access)
// or the file is closed. The directory entry (size, first cluster) and FSINFO are written only
// by CLOSE (f_close = f_sync), by MKDIR/DELETE/RENAME, and by SYS_SYNC. Each sector write waits
// until the card has finished programming it. So a file still open for writing at power-off is
// left with its old size and lost clusters: close files (or SYS_SYNC) before power-off.
// Formats the spec leaves open:
//   STAT     BUF <- { u32 size, u8 attr (bit 4 = directory), u32 time (fdate << 16 | ftime) }
//   READDIR  ARG0 = entries to skip; BUF <- packed { u32 size, u8 attr, u8 namelen, name }
#define MB_FILES 4
static uint32_t clk_base, clk_ms;       // SYS_TIME ($1D): seconds since 2000 at time_millis() clk_ms
static uint8_t  clk_set;   // keys a816_mailbox found nothing new in
static FIL     mb_fil[MB_FILES];
static uint8_t mb_open;                 // bit n = handle n in use
// PC volume (paths "/PC:..."): a handle can be a file on the PC, served by the gateway
static uint8_t  mb_pc;                  // bit n = handle n is a PC file
static uint8_t  mb_prn;                 // (step 3) bit n = handle n is a print job (/PRN:)
// ---- step 3 (defined after the mailbox) ----
static int      spec_path(const char *p);       // 1 "/PRN:", 2 "/PRN:...", 3-6 "/D1:"-"/D4:", 0 other
static int      prn_hopen(int h, const char *name);   // a print job on handle h
static uint32_t prn_hclose(int h);
static uint32_t prn_count;                      // print jobs finished
static int      mount_folder(const char *path, int slot, int remember);
static int      mount_run(const char *path);
static void     rd_drop(int slot, int forget);
static void     fd_flush(void);
static void     prn_end(void);
static int      cold_boot_basic(void);
static uint8_t  mb_pch[MB_FILES];       // the gateway's handle
static uint32_t mb_pcep[MB_FILES];      // the link session (pl_epoch) it was opened in

static inline __attribute__((always_inline)) uint32_t rd2(volatile uint32_t *r) {   // a register clocked by the 65C816
    uint32_t a, b = *r;
    do { a = b; b = *r; } while (a != b);
    return a;
}

// 65C816 address -> pointer here, and how many bytes are contiguous from it (0 = no access)
static uint8_t *mb_ptr(uint32_t n, uint32_t *room) {
    if (n >= 0x800000 || (n >> 16) == 0x10) { *room = 0; return 0; }
    *room = 0x100000 - (n & 0xFFFFF);
    return (uint8_t *)(n < 0x400000 ? n ^ 0x100000 : n ^ 0x300000);   // see a816_physical_addr in tang_top.sv
}

static int mb_get(uint32_t n, uint8_t *dst, uint32_t len) {
    while (len) {
        uint32_t room;
        volatile uint8_t *p = mb_ptr(n, &room);
        if (!room) return 0;
        if (room > len) room = len;
        for (uint32_t i = 0; i < room; i++) dst[i] = p[i];
        n += room; dst += room; len -= room;
    }
    return 1;
}

static int mb_put(uint32_t n, const uint8_t *src, uint32_t len) {
    while (len) {
        uint32_t room;
        volatile uint8_t *p = mb_ptr(n, &room);
        if (!room) return 0;
        if (room > len) room = len;
        for (uint32_t i = 0; i < room; i++) p[i] = src[i];
        n += room; src += room; len -= room;
    }
    return 1;
}

static int mb_path(uint32_t n, char *dst, int max) {            // zero-terminated string
    for (int i = 0; i < max; i++) {
        if (!mb_get(n + i, (uint8_t *)dst + i, 1)) return 0;
        if (!dst[i]) return 1;
    }
    return 0;
}

// file <-> 65C816 memory, straight through FatFs. wr = 0 file -> memory.
static uint32_t mb_xfer(FIL *f, uint32_t n, uint32_t len, int wr, uint32_t *res) {
    uint32_t done = 0;
    *res = 0;
    while (len) {
        uint32_t room;
        UINT got = 0;
        uint8_t *p = mb_ptr(n, &room);
        if (!room) { *res = 0x81; break; }
        if (room > len) room = len;
        if (room > 0x8000) room = 0x8000;
        *res = wr ? f_write(f, p, room, &got) : f_read(f, p, room, &got);
        done += got; n += got; len -= got;
        if (*res || got < room) break;
    }
    return done;
}


// ---- the PC volume (Docs/04-pc-link.md, "The PC volume") ----
// "/PC:" or "/PC:/..." (any case) -> the path on the PC ("/" or "/..."), else 0
static const char *pc_path(const char *p) {
    if (p[0] != '/' || (p[1] | 0x20) != 'p' || (p[2] | 0x20) != 'c' || p[3] != ':') return 0;
    if (p[4] == 0) return "/";
    return p[4] == '/' ? p + 4 : 0;
}
static uint8_t pc_args[264];                             // two paths of 127 + 2 + a header
static int pc_args_path(int at, const char *path) {     // path into pc_args at `at` -> length
    int n = strlen(path) + 1;
    if (at + n > (int)sizeof pc_args) return -1;
    memcpy(pc_args + at, path, n);
    return at + n;
}
// A response stream into 65C816 memory (READ, LOAD, READDIR's entries).
typedef struct { uint32_t dst, n, skip, err; uint8_t hdr[16]; } pc_sink_t;
// (hot: it runs for every frame of a READ or LOAD) block RAM -> 65C816 memory, in 32-bit
// stores where it can: an SDRAM access costs the I/O processor much more than a byte
// from block RAM. 0 = an address the I/O processor cannot reach.
static int pc_put816(uint32_t n, const uint8_t *s, uint32_t len) {
    while (len) {
        if (n >= 0x800000 || (n >> 16) == 0x10) return 0;
        uint32_t room = 0x100000 - (n & 0xFFFFF);
        uint8_t *d = (uint8_t *)(n < 0x400000 ? n ^ 0x100000 : n ^ 0x300000);   // see mb_ptr
        if (room > len) room = len;
        uint32_t k = room;
        while (k && ((uint32_t)d & 3)) { *d++ = *s++; k--; }
        uint32_t *w = (uint32_t *)d;
        for (; k >= 4; k -= 4, s += 4) *w++ = s[0] | s[1] << 8 | s[2] << 16 | (uint32_t)s[3] << 24;
        d = (uint8_t *)w;
        while (k--) *d++ = *s++;
        n += room; len -= room;
    }
    return 1;
}
static void pc_to816(const uint8_t *p, uint32_t n, void *ctx) {
    pc_sink_t *k = ctx;
    while (n && k->skip) {                               // a header first (READDIR: the count)
        k->hdr[sizeof k->hdr - k->skip] = *p++; n--; k->skip--;
    }
    if (n && !k->err && !pc_put816(k->dst + k->n, p, n)) k->err = 0x81;
    k->n += n;
}
static void pc_tohdr(const uint8_t *p, uint32_t n, void *ctx) {   // a small answer (OPEN, STAT)
    pc_sink_t *k = ctx;
    for (uint32_t i = 0; i < n && k->n < sizeof k->hdr; i++) k->hdr[k->n++] = p[i];
}
static uint32_t le32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static int pc_live(int h) { return pl_files() && mb_pcep[h] == pl_epoch(); }
static uint32_t pc_close(int h) {        // the gateway's handle is closed (if still alive), slot free
    uint32_t r = 0;
    if (pc_live(h)) {
        uint8_t a[4] = { mb_pch[h], 0, 0, 0 };
        pc_sink_t k = { 0 };
        r = pl_call(2, a, 4, 0, 0, pc_tohdr, &k);
        if (r == PL_E_LOST || r == PL_E_NOLINK) r = 0;   // gone with the session anyway
    }
    mb_open &= ~(1 << h);
    mb_pc &= ~(1 << h);
    return r;
}

static uint32_t mb_close_all(void) {    // close every mailbox handle; first error, or 0
    uint32_t res = 0;
    for (int i = 0; i < MB_FILES; i++) {
        if (!(mb_open & (1 << i))) continue;
        FRESULT r = (mb_pc & (1 << i)) ? pc_close(i) : (mb_prn & (1 << i)) ? prn_hclose(i) : f_close(&mb_fil[i]);
        if (r && !res) res = r;
    }
    mb_open = 0;
    mb_pc = 0;
    ns_close_all();                                      // (step 2) every URL and connection
    return res;
}

// ---- (step 2) what pcnet.c needs from the mailbox side ----
int ns_put816(uint32_t dst, const uint8_t *src, uint32_t n) { return pc_put816(dst, src, n); }
const volatile uint8_t *ns_ptr816(uint32_t a, uint32_t n) {
    uint32_t room;
    uint8_t *p = mb_ptr(a, &room);
    return (p && room >= n) ? p : 0;
}
uint32_t ns_fattime(void) { return fat_from2000(pl_pc_time()); }
void ns_event(int handle);                               // (below, with the input queue)
// an answer of a request put aside -> the response ring (it needs one free slot)
static uint8_t sys_restart;
int ns_answer(uint8_t *m16) {
    uint32_t q = rd2(&reg_a816_mbq), r = rd2(&reg_a816_mbr), iop = reg_a816_mbi;
    uint32_t rbase = r & 0xFFFFFF;
    uint8_t rtail = r >> 24, rhead = iop >> 8;
    if (!(q & 0xFFFFFF) || !rbase || !(iop & 0x10000) || sys_restart) return 1;   // gone: dropped
    if ((uint8_t)(rhead + 1) == rtail) return 0;         // full: later
    if (!mb_put(rbase + rhead * 16, m16, 16)) return 1;
    reg_a816_mbi = (reg_a816_mbi & 0x300FF) | (uint8_t)(rhead + 1) << 8;
    return 1;
}

// SYS_RESTART ($1B) runs after its reply was read (or 500 ms later): 1 = Horizon only, 2 = full
static uint8_t  sys_restart;
static uint32_t sys_restart_t0;
static void sys_do_restart(int full) {
    reg_a816_ctrl = 0;                                   // hold the 65C816 before anything else
    mb_close_all();
    fs_remount();
    if (full) {
        uart_printf("sys: full restart\n");
        // power-on defaults, then /atari.ini (keys left out of the file go back to default)
        option_arrow_joystick = 0; option_scanline_level = 0; option_h_offset = 0;
        option_stereo = 0; option_kbd_layout = 0; option_ram_idx = 0; option_boot_ash = 0;
        int r = load_option();
        for (int a = 0; r < 0 && a < 5; a++) {
            delay(50); f_mount(0, "", 0); delay(20);
            if (f_mount(&fs, "", 0) == FR_OK) r = load_option();
        }
        apply_input_options();
        apply_video_options();
        apply_machine_options();
        // classic media out, as at power-on (the default cartridge and /HDD.ATR come back below)
        for (int i = 0; i < ATR_DRIVES; i++) {
            if (atr_mounted[i]) { f_close(&atr_file[i]); atr_mounted[i] = false; }
        }
        if (xex_active) { f_close(&xex_file); xex_active = false; }
        for (int i = 0; i < ATR_DRIVES; i++) if (rd_kind[i]) rd_drop(i, 0);   // (step 3)
        reg_cart_mode = 0;
        strcpy(mounted_cart_name, "None");
        int rom = cold_boot_atari();                     // boot=ash: /ASH.CAR; ROMs; long reset
        for (int a = 0; rom && a < 3; a++) {
            delay(50); f_mount(0, "", 0); delay(20);
            if (f_mount(&fs, "", 0) == FR_OK) rom = cold_boot_atari();
        }
        bridge_rom_ok = rom;
        if (!rom) {
            mount_silent = 1;
            mount_atr("/HDD.ATR", 3);
            mount_silent = 0;
            if (option_folderdrive >= 1 && option_folderdrive <= ATR_DRIVES && option_folder[0])   // (step 3)
                mount_folder(option_folder, option_folderdrive - 1, 0);
        }
        uart_printf("boot: roms %d\n", rom);
    }
    a816_start(0);
}


// ── Keyboard and mouse events for Horizon (KEY $E0, MOUSE $E1) ───────────────────────────
// Hot (block RAM) and called often: from the main loop, from every wait of the PC link
// (pl_idle), from the SD card driver between sectors and while the card is busy, and from
// delay(). So events keep flowing while a long mailbox request is served (a big card READ or
// WRITE, a /PC: request, a developer upload): the pointer moves and no key is lost.
//  - Keys: the state is the firmware's own copy of the keyboard (kv0/kv1: the CH9350 reports,
//    parsed in order from the UART, and the developer KEY/TYPE injections). After every change
//    the difference to what Horizon was told is queued, one event per change (releases first,
//    then modifiers, then presses), so a short tap is never merged away.
//  - Mouse: motion with the same buttons is added up until it is sent; a button change first
//    queues the motion before it (with the old buttons), so a click is never lost.
//  - The queue goes into the response ring whenever it has 2 free slots (one stays free for
//    the answer of the request in progress, written by a816_mailbox after the events).
//  - Not while the keyboard belongs to the classic machine: held keys are reported released,
//    motion is dropped. Nothing while the rings are not set up or a restart is pending.
#define EQN 32
typedef struct { uint8_t op, b8, b9, b10, b12, b13; } inev_t;
static inev_t  eq[EQN];
static uint8_t eq_h, eq_n;
uint32_t kv0, kv1;
static uint8_t k_held[4] __attribute__((aligned(4)));   // the keys Horizon was told are down
static uint8_t k_mods, k_ready;
static int16_t ms_dx, ms_dy, ms_wheel;
static uint8_t ms_btn, ms_btn_q;                 // buttons now / of the motion being added up
static uint32_t in_t;                             // reg_cycle at the last in_service
volatile uint32_t in_gap, in_nev;                 // meters (INFO): longest gap in cycles, events sent
// the input generator (developer op INJECT, a board test): key taps and mouse reports at a
// steady rate, entering where the CH9350's reports do, with the loss a full UART FIFO causes
#define UART_FIFO 64                              // simpleuart.v's receive FIFO, bytes
#define KB_FRAME 15                               // bytes of a CH9350 keyboard report
#define MS_FRAME 11                               // bytes of a mouse report
static uint16_t gk_n, gk_per, gm_n;
static uint8_t  gm_per, gk_down, gk_key;
static uint32_t gk_t, gm_t;
volatile uint32_t gk_sent, gm_sent, gk_lost, gm_lost;

static HOT_FN int eq_push(uint8_t op, uint8_t b8, uint8_t b9, uint8_t b10, uint8_t b12, uint8_t b13) {
    if (eq_n == EQN) return 0;
    inev_t *e = &eq[(uint8_t)(eq_h + eq_n) % EQN];
    e->op = op; e->b8 = b8; e->b9 = b9; e->b10 = b10; e->b12 = b12; e->b13 = b13;
    eq_n++;
    return 1;
}
static HOT_FN int clamp127(int v) { return v > 127 ? 127 : v < -127 ? -127 : v; }
// the motion added up so far -> queued events (with the buttons it was made with)
static HOT_FN int ms_queue(void) {
    while (ms_dx || ms_dy || ms_wheel || ms_btn_q != ms_btn) {
        int dx = clamp127(ms_dx), dy = clamp127(ms_dy), dw = clamp127(ms_wheel);
        uint8_t b = (dx || dy || dw) ? ms_btn_q : ms_btn;
        if (!eq_push(0xE1, dx, dy, dw, b, 0)) return 0;
        ms_dx -= dx; ms_dy -= dy; ms_wheel -= dw; ms_btn_q = b;
    }
    return 1;
}
void ns_event(int handle) { eq_push(0xE4, handle, 0, 0, 0, 0); }   // $E4 NET (step 2)
HOT_FN void in_mouse(int btn, int dx, int dy, int wheel) {
    if (btn != ms_btn) { ms_queue(); ms_btn = btn; }
    ms_dx += dx; ms_dy += dy; ms_wheel += wheel;
}
static HOT_FN int kb_ours(void) {
    uint32_t a, b = reg_a816_keymod;
    do { a = b; b = reg_a816_keymod; } while (a != b);
    return (a >> 8) & 1;
}
// queue the differences between the keys held (kv0, kv1) and what Horizon was told
static HOT_FN void in_keys(void) {
    if (!k_ready) return;
    uint8_t now[4] = { kv0 >> 8, kv0 >> 16, kv0 >> 24, kv1 }, nm = kv0;
    if (!kb_ours()) { now[0] = now[1] = now[2] = now[3] = 0; nm = 0; }
    while (eq_n < EQN) {
        uint8_t usage = 0, down = 0;
        for (int i = 0; i < 4 && !usage; i++) {          // releases first
            int still = 0;
            for (int j = 0; j < 4; j++) if (k_held[i] && k_held[i] == now[j]) still = 1;
            if (k_held[i] && !still) { usage = k_held[i]; k_held[i] = 0; }
        }
        for (int i = 0; i < 8 && !usage; i++)
            if ((k_mods ^ nm) & (1 << i)) { usage = 0xE0 + i; down = (nm >> i) & 1; k_mods ^= 1 << i; }
        for (int i = 0; i < 4 && !usage; i++) {
            int known = 0, slot = -1;
            for (int j = 0; j < 4; j++) { if (k_held[j] == now[i]) known = 1; if (!k_held[j]) slot = j; }
            if (now[i] > 3 && !known && slot >= 0) { usage = now[i]; down = 1; k_held[slot] = usage; }
        }
        if (!usage) return;
        eq_push(0xE0, usage, 0, 0, k_mods, down);
    }
}
HOT_FN void kv_set0(uint32_t v) { kv0 = v; reg_virt_kbd_0 = v; in_keys(); }
HOT_FN void kv_set1(uint32_t v) { kv1 = v; reg_virt_kbd_1 = v; in_keys(); }

// the queue -> the response ring
static HOT_FN void in_flush(void) {
    if (k_ready && !eq_n && !(ms_dx | ms_dy | ms_wheel | k_mods | *(uint32_t *)k_held)
        && ms_btn_q == ms_btn) return;                  // nothing to say: cheap
    uint32_t q = rd2(&reg_a816_mbq), r = rd2(&reg_a816_mbr), iop = reg_a816_mbi;
    if (!(q & 0xFFFFFF) || !(r & 0xFFFFFF) || !(iop & 0x10000) || sys_restart) {
        if (!sys_restart) {                              // not set up: start again when it is
            eq_n = 0; k_ready = 0;
            k_held[0] = k_held[1] = k_held[2] = k_held[3] = 0; k_mods = 0;
            ms_dx = ms_dy = ms_wheel = 0; ms_btn_q = ms_btn;
        }
        return;
    }
    if (!k_ready) { k_ready = 1; in_keys(); }
    if (!kb_ours()) { ms_dx = ms_dy = ms_wheel = 0; ms_btn_q = ms_btn; in_keys(); }
    uint32_t rbase = r & 0xFFFFFF;
    uint8_t rtail = r >> 24, rhead = iop >> 8, h0 = rhead;
    if (rbase >= 0x800000 || (rbase >> 16) == 0x10) return;
    for (;;) {
        if ((uint8_t)(rtail - rhead - 1) < 2) break;     // keep one slot for an answer
        if (!eq_n && !ms_queue()) break;
        if (!eq_n) break;
        inev_t *e = &eq[eq_h];
        uint32_t n = rbase + rhead * 16;
        volatile uint32_t *d = (volatile uint32_t *)(n < 0x400000 ? n ^ 0x100000 : n ^ 0x300000);
        d[0] = e->op; d[1] = 0;
        d[2] = e->b8 | e->b9 << 8 | e->b10 << 16;
        d[3] = e->b12 | e->b13 << 8;
        eq_h = (eq_h + 1) % EQN; eq_n--;
        rhead++;
        in_nev++;
    }
    if (rhead != h0) reg_a816_mbi = (iop & 0x300FF) | (uint32_t)rhead << 8;
}

// one step of the input generator: the reports due since the last call, as the UART's FIFO
// would hold them (what does not fit is lost, as on the wire). Cold (SDRAM): a test only.
void ch_frame(const uint8_t *f, int n);
// a key report as the CH9350 sends it (57 AB 88 0B, type, modifiers, 0, 6 keys, serial, sum), fed
// through the same parser: the type alternates $10 / $11 and the checksum both forms (with or
// without the type byte), as keyboards send them
static void in_genkey(uint8_t key) {
    static uint8_t serial;
    uint8_t f[15] = { 0x57, 0xAB, 0x88, 11, 0x10 | (gk_sent & 1), 0, 0, key, 0, 0, 0, 0, 0, serial++, 0 };
    uint8_t sum = 0;
    for (int i = 5; i < 14; i++) sum += f[i];
    if (gk_sent & 2) sum += f[4];
    f[14] = sum;
    ch_frame(f, 15);
}
static __attribute__((noinline)) void in_gen(void) {
    uint32_t now = time_millis(), bytes = 0;
    for (;;) {
        int k = gk_n && (int32_t)(now - gk_t) >= 0, m = gm_n && (int32_t)(now - gm_t) >= 0;
        if (k && m) { if ((int32_t)(gm_t - gk_t) < 0) k = 0; else m = 0; }
        if (k) {                                         // a key report: press or release
            gk_t += gk_per / 2;
            if ((bytes += KB_FRAME) > UART_FIFO) gk_lost++;
            else in_genkey(gk_down ? 0 : 0x04 + gk_key);
            if (gk_down) { gk_n--; gk_key = (gk_key + 1) % 26; }
            gk_down ^= 1;
            gk_sent++;
        } else if (m) {
            gm_t += gm_per;
            gm_n--;
            if ((bytes += MS_FRAME) > UART_FIFO) gm_lost++;
            else in_mouse(ms_btn, 1, 0, 0);
            gm_sent++;
        } else break;
    }
}
void in_inject(uint16_t keys, uint16_t key_ms, uint16_t mice, uint8_t mouse_ms) {
    uint32_t now = time_millis();
    gk_n = keys; gk_per = key_ms < 2 ? 2 : key_ms; gk_t = now; gk_down = 0; gk_key = 0;
    gm_n = mice; gm_per = mouse_ms ? mouse_ms : 1; gm_t = now;
    gk_sent = gm_sent = gk_lost = gm_lost = 0;
}

HOT_FN void in_service(void) {
    static uint8_t busy;
    if (busy) return;
    busy = 1;
    uint32_t c = reg_cycle;
    if (in_t && c - in_t > in_gap) in_gap = c - in_t;
    in_t = c;
    uart_keyboard_poll();                                // CH9350 reports -> kv0 / in_mouse
    if (gk_n | gm_n) in_gen();
    in_flush();
    busy = 0;
}
HOT_FN void in_tick(void) {
    if (reg_cycle - in_t >= 13500) in_service();         // 0.5 ms
}

static void a816_mailbox(void) {
    static char path[128];
    uint32_t q = rd2(&reg_a816_mbq), r = rd2(&reg_a816_mbr), iop = reg_a816_mbi;
    uint32_t qbase = q & 0xFFFFFF, rbase = r & 0xFFFFFF;
    uint8_t  qhead = q >> 24, rtail = r >> 24, qtail = iop, rhead = iop >> 8;
    uint8_t  m[16];
    uint32_t res = 0, val = 0;
    static uint8_t busy;                                 // FatFs waits can poll the bridge again
    if (busy) return;

    if (sys_restart) {                                   // SYS_RESTART answered: wait until the
        if (rtail != rhead && time_millis() - sys_restart_t0 < 500) return;   // 65C816 read it
        int full = sys_restart == 2;
        sys_restart = 0;
        busy = 1;
        sys_do_restart(full);
        busy = 0;
        return;
    }

    if (!qbase || !rbase) {                              // 65C816 reset or not set up
        if (iop) {
            mb_close_all();
            reg_a816_mbi = 0;
        }
        return;
    }
    if (!(iop & 0x10000)) { reg_a816_mbi = 0x10000; return; }   // IOP_READY, rings empty
    if ((uint8_t)(rhead + 1) == rtail) return;           // no room for an answer or an event

    if (qhead == qtail) return;                          // nothing to do
    if (!mb_get(qbase + qtail * 16, m, 16)) { reg_a816_mbi = iop | 0x20000; return; }   // IOP_ERROR

    busy = 1;
    uint32_t len  = m[2] | m[3] << 8;
    uint32_t buf  = m[4] | m[5] << 8 | m[6] << 16;
    uint32_t arg0 = m[8] | m[9] << 8 | m[10] << 16 | (uint32_t)m[11] << 24;
    uint32_t arg1 = m[12] | m[13] << 8 | m[14] << 16 | (uint32_t)m[15] << 24;
    FIL *f = (arg0 < MB_FILES && (mb_open & (1 << arg0))) ? &mb_fil[arg0] : 0;
    int pch = f && (mb_pc & (1 << arg0));                // a handle of a PC file
    const char *pcp = 0;                                 // the PC path of a path op
    pc_sink_t k = { 0 };
    int later = NS_NOW;                                  // (step 2) the answer comes later
    int nsh = arg0 - NS_H0 < NS_N;                       // (step 2) a stream handle (4-7)

    // after SYS_SYNC every op below $1B (files, LOAD, classic machine) is refused with $86
    switch (mb_synced && m[0] < 0x1B ? 0x7F : m[0]) {
    case 0x7F:
        res = 0x86;
        break;
    case 0x01: {                                         // OPEN
        static const uint8_t mode[4] = { FA_READ, FA_READ | FA_WRITE,
                                         FA_READ | FA_WRITE | FA_CREATE_ALWAYS,
                                         FA_WRITE | FA_OPEN_APPEND };
        int h = 0;
        while (h < MB_FILES && (mb_open & (1 << h))) h++;
        if (!mb_path(buf, path, sizeof path)) res = 0x81;
        else if (ns_kind(path)) later = ns_open(path, m, &res, &val);   // a URL, a connection
        else if (h == MB_FILES) res = FR_TOO_MANY_OPEN_FILES;
        else if (spec_path(path) == 1 || spec_path(path) == 2) {   // (step 3) a print job
            if (!(res = prn_hopen(h, path + 5))) { mb_open |= 1 << h; mb_prn |= 1 << h; val = h; }
        }
        else if ((pcp = pc_path(path))) {                // a file on the PC
            pc_args[0] = m[7] & 3; pc_args[1] = pc_args[2] = pc_args[3] = 0;
            int na = pc_args_path(4, pcp);
            if (na < 0) { res = FR_INVALID_NAME; break; }
            if (!(res = pl_call(1, pc_args, na, 0, 0, pc_tohdr, &k))) {
                mb_pch[h] = k.hdr[0]; mb_pcep[h] = pl_epoch();
                mb_open |= 1 << h; mb_pc |= 1 << h; val = h;
            }
        }
        else if (!(res = f_open(&mb_fil[h], path, mode[m[7] & 3]))) { mb_open |= 1 << h; val = h; }
        break;
    }
    case 0x02:                                           // CLOSE
        if (nsh) res = ns_close(arg0);
        else if (!f) res = 0x80;
        else if (pch) res = pc_close(arg0);
        else if (mb_prn & (1 << arg0)) res = prn_hclose(arg0);   // (step 3) the job is done
        else { res = f_close(f); mb_open &= ~(1 << arg0); }
        break;
    case 0x03: case 0x04:                                // READ, WRITE
        if (nsh) {
            if (m[0] == 0x03) later = ns_read(arg0, buf, len, m, &res, &val);
            else ns_write(arg0, buf, len, &res, &val);
        }
        else if (!f) res = 0x80;
        else if (pch) {
            uint8_t a[8] = { mb_pch[arg0], 0, 0, 0, len, len >> 8, 0, 0 };
            uint32_t room;
            uint8_t *p = mb_ptr(buf, &room);
            if (!pc_live(arg0)) res = PL_E_LOST;
            else if (len && (!room || room < len)) res = 0x81;
            else if (m[0] == 0x03) {
                k.dst = buf;
                res = pl_call(3, a, 8, 0, 0, pc_to816, &k);
                val = k.n;
                if (!res) res = k.err;
            } else {
                res = pl_call(4, a, 4, p, len, pc_tohdr, &k);
                if (!res) val = le32(k.hdr);
            }
        }
        else val = mb_xfer(f, buf, len, m[0] == 0x04, &res);
        break;
    case 0x05:                                           // SEEK
        if (nsh) res = 0x82;                             // (a stream: no seek)
        else if (!f) res = 0x80;
        else if (pch) {
            uint8_t a[8] = { mb_pch[arg0], 0, 0, 0, arg1, arg1 >> 8, arg1 >> 16, arg1 >> 24 };
            if (!pc_live(arg0)) res = PL_E_LOST;
            else if (!(res = pl_call(5, a, 8, 0, 0, pc_tohdr, &k))) val = le32(k.hdr);
        }
        else { res = f_lseek(f, arg1); val = f_tell(f); }
        break;
    case 0x06: {                                         // STAT
        FILINFO fi;
        uint8_t o[9];
        if (!mb_path(buf, path, sizeof path)) { res = 0x81; break; }
        if (ns_kind(path)) { later = ns_stat(path, buf, m, &res, &val); break; }
        int sp = spec_path(path);
        if (sp == 1 || sp >= 3) {                        // (step 3) "/PRN:": the jobs finished;
            uint32_t sz = prn_count, t = get_fattime(), at = 0x10;   // "/Dn:": the folder disk
            if (sp >= 3) {
                if (rd_kind[sp - 3] != 1) { res = FR_NO_FILE; break; }
                sz = FD_ST->shown | FD_ST->skipped << 8 | (uint32_t)FD_ST->nfree << 16;
                at |= FD_ST->pending ? 1 : 0;
                t = FD_ST->t_saved;
            }
            o[0] = sz; o[1] = sz >> 8; o[2] = sz >> 16; o[3] = sz >> 24; o[4] = at;
            o[5] = t; o[6] = t >> 8; o[7] = t >> 16; o[8] = t >> 24;
            if (!mb_put(buf, o, 9)) res = 0x81;
            val = sz;
            break;
        }
        if (sp == 2) { res = 0x82; break; }
        if ((pcp = pc_path(path))) {
            if (!pl_files()) { res = PL_E_NOLINK; break; }
            if (pcp[1] == 0) {                           // its root: a folder, the PC's clock now
                uint32_t t = fat_from2000(pl_pc_time());
                o[0] = pl_svc(); o[1] = o[2] = o[3] = 0; o[4] = 0x10;   // (step 3) size: the services
                o[5] = t; o[6] = t >> 8; o[7] = t >> 16; o[8] = t >> 24;
            } else {
                if (pc_args_path(0, pcp) < 0) { res = FR_INVALID_NAME; break; }
                if ((res = pl_call(6, pc_args, strlen(pcp) + 1, 0, 0, pc_tohdr, &k))) break;
                for (int i = 0; i < 5; i++) o[i] = k.hdr[i];
                for (int i = 0; i < 4; i++) o[5 + i] = k.hdr[8 + i];
            }
            if (!mb_put(buf, o, 9)) res = 0x81;
            val = le32(o);
            break;
        }
        if ((res = f_stat(path, &fi))) break;
        uint32_t t = (uint32_t)fi.fdate << 16 | fi.ftime;
        o[0] = fi.fsize; o[1] = fi.fsize >> 8; o[2] = fi.fsize >> 16; o[3] = fi.fsize >> 24;
        o[4] = fi.fattrib;
        o[5] = t; o[6] = t >> 8; o[7] = t >> 16; o[8] = t >> 24;
        if (!mb_put(buf, o, 9)) res = 0x81;
        val = fi.fsize;
        break;
    }
    case 0x07: {                                         // READDIR
        DIR d;
        FILINFO fi;
        uint32_t off = 0;
        int full = 0;
        if (!mb_path(buf, path, sizeof path)) { res = 0x81; break; }
        if (ns_kind(path) || spec_path(path)) { res = 0x82; break; }
        if ((pcp = pc_path(path))) {                     // skip u16, room u16, path
            pc_args[0] = arg0; pc_args[1] = arg0 >> 8; pc_args[2] = len; pc_args[3] = len >> 8;
            int na = pc_args_path(4, pcp);
            if (na < 0) { res = FR_INVALID_NAME; break; }
            k.dst = buf; k.skip = 4;                     // the count first, then the entries
            res = pl_call(7, pc_args, na, 0, 0, pc_to816, &k);
            if (!res) res = k.err;
            val = k.hdr[12] | k.hdr[13] << 8;
            break;
        }
        if ((res = f_opendir(&d, path))) break;
        for (;;) {
            if ((res = f_readdir(&d, &fi)) || !fi.fname[0]) break;
            if (arg0) { arg0--; continue; }
            uint32_t nl = strlen(fi.fname);
            uint8_t  h[6] = { fi.fsize, fi.fsize >> 8, fi.fsize >> 16, fi.fsize >> 24, fi.fattrib, nl };
            if (off + 6 + nl > len) { full = 1; break; }
            if (!mb_put(buf + off, h, 6) || !mb_put(buf + off + 6, (uint8_t *)fi.fname, nl)) { res = 0x81; break; }
            off += 6 + nl;
            val++;
        }
        f_closedir(&d);
        // the card's root ends with the PC volume, a folder "PC:", while it is there
        if (!res && !full && path[0] == '/' && !path[1] && pl_files()) {
            static const uint8_t e[9] = { 0, 0, 0, 0, 0x10, 3, 'P', 'C', ':' };
            if (arg0) arg0--;
            else if (off + 9 <= len) { if (mb_put(buf + off, e, 9)) val++; else res = 0x81; }
        }
        break;
    }
    case 0x08: case 0x09:                                // MKDIR, DELETE
        if (!mb_path(buf, path, sizeof path)) res = 0x81;
        else if (ns_kind(path)) res = FR_DENIED;
        else if (spec_path(path)) res = 0x82;
        else if ((pcp = pc_path(path))) {
            if (pc_args_path(0, pcp) < 0) res = FR_INVALID_NAME;
            else res = pl_call(m[0], pc_args, strlen(pcp) + 1, 0, 0, pc_tohdr, &k);
        }
        else res = m[0] == 0x08 ? f_mkdir(path) : f_unlink(path);
        break;
    case 0x0A: {                                         // RENAME "old\0new"
        static char to[128];
        const char *pct;
        if (!mb_path(buf, path, sizeof path) || !mb_path(buf + strlen(path) + 1, to, sizeof to)) res = 0x81;
        else if (ns_kind(path) || ns_kind(to)) res = FR_DENIED;
        else if (spec_path(path) || spec_path(to)) res = 0x82;
        else if ((pcp = pc_path(path)) && (pct = pc_path(to))) {
            int na = pc_args_path(0, pcp);
            if (na < 0 || (na = pc_args_path(na, pct)) < 0) res = FR_INVALID_NAME;
            else res = pl_call(0x0A, pc_args, na, 0, 0, pc_tohdr, &k);
        }
        else if (pcp || pc_path(to)) res = pl_files() ? PL_E_XVOL : PL_E_NOLINK;
        else res = f_rename(path, to);
        break;
    }
    case 0x10: {                                         // LOAD whole file to ARG0
        FIL lf;
        if (!mb_path(buf, path, sizeof path)) { res = 0x81; break; }
        if (ns_kind(path) || spec_path(path)) { res = 0x82; break; }
        if ((pcp = pc_path(path))) {
            if (pc_args_path(0, pcp) < 0) { res = FR_INVALID_NAME; break; }
            k.dst = arg0 & 0xFFFFFF;
            res = pl_call(0x10, pc_args, strlen(pcp) + 1, 0, 0, pc_to816, &k);
            if (!res) res = k.err;
            val = k.n;
            break;
        }
        if ((res = f_open(&lf, path, FA_READ))) break;
        val = mb_xfer(&lf, arg0 & 0xFFFFFF, f_size(&lf), 0, &res);
        f_close(&lf);
        break;
    }
    // ── Classic machine (Atari 8-bit core) software, ops $18-$1A ──
    // Request:
    //   $18 CLASSIC_MOUNT  BUF   = path (zero-terminated, as OPEN/LOAD)
    //                      FLAGS = kind: 0 by extension (.ATR/.XFD disk, .XEX/.COM/.EXE
    //                              executable, .CAR/.ROM/.BIN cartridge), 1 disk image,
    //                              2 executable, 3 cartridge, (step 3) 4 a BASIC program to
    //                              run ("Run in Atari": the boot disk on D1:, answered as 2),
    //                              5 a folder as a DOS 2 disk on drive ARG0 (answered as 1)
    //                      ARG0  = drive slot 0..3 (D1:..D4:), disk images only; an
    //                              executable always becomes the virtual boot disk on D1:
    //                      Mount only, no reset. The new image replaces the slot's old
    //                      one (also: a disk on slot 0 replaces a mounted executable and
    //                      vice versa). A cartridge is mapped at once (reg_cart_mode), so
    //                      a classic machine left RUNNING sees it immediately: freeze it
    //                      or follow with CLASSIC_BOOT.
    //   $19 CLASSIC_EJECT  FLAGS = kind: 1 disk (slot 0 also ejects the executable),
    //                              2 executable, 3 cartridge
    //                      ARG0  = drive slot 0..3 (disk only). Ejecting an empty slot = OK.
    //   $1A CLASSIC_BOOT   no arguments. Cold boot with what is mounted, as the OSD menu
    //                      does: executable mounted -> OPTION held (BASIC off), else plain
    //                      cold boot (boot=ash puts /ASH.CAR in an empty cart slot).
    //                      Horizon must unfreeze the machine AND route the keyboard to it
    //                      first: the held OPTION goes through the keyboard path, which
    //                      is masked while Horizon has the keyboard.
    // Response: ARG0 = result, ARG1 = MOUNT: kind mounted (1..3); BOOT: 2 = executable
    //   boot, 0 = other; EJECT: 0.
    // Results: 0 OK, 1..19 FatFs (e.g. 4 no file), $81 bad path address, $83 bad kind,
    //   slot or unknown extension, $84 not a valid/supported image (bad ATR header, odd
    //   .XFD size, no $FFFF header, unsupported CAR type, cart > 4 MB, ROM files bad),
    //   $85 refused: the OSD menu is open (try again later).
    // Time (the reply comes when done; other requests and key events wait): MOUNT disk/xex
    //   a few SD accesses (~10-50 ms); MOUNT cartridge reads the whole image (8-16 KB fast,
    //   multi-MB carts take seconds); EJECT immediate; BOOT ~0.2 s (ROM reload), ~0.8 s for
    //   an executable (OPTION held 600 ms while its boot sectors are served).
    case 0x18: case 0x19: case 0x1A: {
        int kind = m[7], r = 0, s = kind == 1 || kind == 5 ? arg0 : 0;   // ($85 "OSD open" is no longer returned)
        if (m[0] == 0x1A) {
            val = xex_active || rd_kind[0] == 2 ? 2 : 0;
            r = xex_active ? cold_boot_xex() : rd_kind[0] == 2 ? cold_boot_basic() : cold_boot_atari();
            res = !r ? 0 : (r & 0xFF) ? (r & 0xFF) : 0x84;
            break;
        }
        if (m[0] == 0x18) {
            if (!mb_path(buf, path, sizeof path)) { res = 0x81; break; }
            if (pc_path(path)) { res = pl_files() ? 0x82 : PL_E_NOLINK; break; }   // not in step 1
            if (ns_kind(path) || spec_path(path)) { res = 0x82; break; }
            char *e = strrchr(path, '.');
            if (!kind && e && strlen(e) == 4)
                for (int i = 0; i < 8; i++) {
                    int j = 0;
                    while (j < 3 && (e[1 + j] & 0xDF) == "ATRXFDXEXCOMEXECARROMBIN"[i * 3 + j]) j++;
                    if (j == 3) { kind = i < 2 ? 1 : i < 5 ? 2 : 3; break; }
                }
        }
        // (step 3) kind 4: a BASIC program to run ("Run in Atari": the boot disk on D1:, answered
        // as an executable, 2); kind 5: a folder as a DOS 2 disk on drive ARG0 (answered as 1)
        if (kind < 1 || kind > 5 || (m[0] == 0x19 && kind > 3) || (uint32_t)s >= ATR_DRIVES) { res = 0x83; break; }
        if (m[0] == 0x19) {                              // EJECT
            if (kind == 3) { reg_cart_mode = 0; strcpy(mounted_cart_name, "None"); break; }
            if (!s && xex_active) { f_close(&xex_file); xex_active = false; }
            if (!s && rd_kind[0] == 2) rd_drop(0, 0);   // (the Run in Atari disk)
            if (kind == 1 && atr_mounted[s]) { f_close(&atr_file[s]); atr_mounted[s] = false; }
            if (kind == 1 && rd_kind[s] == 1) rd_drop(s, 1);   // (the folder disk: saved, forgotten)
            break;
        }
        if ((kind == 1 || kind == 5) && rd_kind[s]) rd_drop(s, kind == 1);   // (what was there)
        if ((kind == 2 || kind == 4) && rd_kind[0]) rd_drop(0, 1);
        mount_silent = 1;                                // MOUNT: no OSD popups
        r = kind == 1 ? mount_atr(path, s) : kind == 2 ? mount_xex(path) : kind == 3 ? load_cartridge(path)
          : kind == 4 ? mount_run(path) : mount_folder(path, s, 1);
        mount_silent = 0;
        val = kind == 4 ? 2 : kind == 5 ? 1 : kind;
        res = !r ? 0 : r > 0 ? r : r == -6 ? FR_DISK_ERR : 0x84;
        if (kind == 3 && !r) name_from_path(mounted_cart_name, path);
        break;
    }
    // ── System, ops $1B-$1C ──
    //   $1B SYS_RESTART  ARG0 = 0: reload /SYSTEM/HORIZON.SYS (else /A816.BIN) and restart the
    //                    65C816 (as the PC link's restart816). The classic machine is left as it is.
    //                    ARG0 = 1: full restart: options back to their defaults, /atari.ini read
    //                    again and applied, every classic image ejected, classic machine cold
    //                    booted (ROMs reloaded, boot=ash puts /ASH.CAR back, /HDD.ATR on D4:),
    //                    then Horizon reloaded and restarted. Allowed after SYS_SYNC (mounts the
    //                    card again first).
    //                    Response: ARG0 = result, ARG1 = 0. The OK reply is written BEFORE the
    //                    restart: the 65C816 is held in reset as soon as it has advanced
    //                    MB_RSP_TAIL past the reply (at most 500 ms after the reply if it never
    //                    does). After sending the request Horizon should do nothing that matters:
    //                    wait for the reply, take it, then spin (no file ops; nothing more is
    //                    answered and no KEY/MOUSE events are sent while the restart is pending).
    //                    An error reply means no restart happened and Horizon keeps running.
    //                    Results: 0 OK, $83 ARG0 not 0 or 1, 1..19 FatFs (e.g. 4: neither
    //                    /SYSTEM/HORIZON.SYS nor /A816.BIN is on the card, 3: card not ready).
    //                    Time to Horizon's first instruction: ~0.2 s (mode 0); ~1 s (mode 1).
    //   $1C SYS_SYNC     no arguments. Closes every mailbox file handle (pending data and the
    //                    directory entries written), closes the classic disk images and the
    //                    virtual executable disk (unmounted: D1:-D4: answer no drive), then
    //                    unmounts the FAT volume. When the reply comes everything is on the card
    //                    and the card is idle: it may be removed or the power cut.
    //                    Response: ARG0 = first error from closing a file (0 = OK; the rest are
    //                    closed anyway), ARG1 = number of mailbox handles that were open.
    //                    Until the next restart (SYS_RESTART, or the PC link's restart816) every
    //                    op below $1B (files, LOAD, CLASSIC_*) answers $86 "card synced" and does
    //                    nothing; SYS_SYNC again answers OK. A mounted cartridge stays (it is in
    //                    SDRAM). PC link file transfers fail (NAK) until the restart too.
    case 0x1B: {
        FILINFO fi;
        if (arg0 > 1) { res = 0x83; break; }
        fs_remount();
        if ((res = f_stat("/SYSTEM/HORIZON.SYS", &fi)) && (res = f_stat("/A816.BIN", &fi))) break;
        sys_restart = 1 + arg0;
        sys_restart_t0 = time_millis();
        uart_printf("sys: restart %d\n", (int)arg0);
        break;
    }
    case 0x1C:
        fd_flush();                                      // (step 3) the folder disk saved, then off
        for (int i = 0; i < ATR_DRIVES; i++) if (rd_kind[i] == 1) rd_drop(i, 0);
        if (prn_job) prn_end();                          //   and a classic print job finished
        for (int i = 0; i < MB_FILES; i++) if (mb_open & (1 << i)) val++;
        res = mb_close_all();
        for (int i = 0; i < ATR_DRIVES; i++) {
            if (atr_mounted[i]) { FRESULT r = f_close(&atr_file[i]); if (r && !res) res = r; atr_mounted[i] = false; }
        }
        if (xex_active) { f_close(&xex_file); xex_active = false; }
        if (!mb_synced) f_mount(0, "", 0);
        mb_synced = 1;
        uart_printf("sys: sync, %d files closed, result %d\n", (int)val, (int)res);
        break;
    // ── $1D-$1E ──
    //   $1D SYS_TIME     ARG0 = the time Horizon knows, in seconds since 2000-01-01 00:00:00
    //                    (local time: the clock the user set, or the last one saved plus the
    //                    uptime). The firmware counts on from it with its own millisecond
    //                    timer, and FatFs stamps files with it (get_fattime). Until it is given
    //                    files get the build date. Horizon sends it at start and when the clock
    //                    is set. Response: 0.
    //   $1E CLASSIC_STATE ARG0 = 5: the cartridge. ARG1 = the size of the cartridge image in
    //                    bytes (0 = none), BUF (LEN bytes, LEN 0 = none) <- its path, zero
    //                    terminated (cut to LEN - 1). Also a cartridge the firmware loaded by
    //                    itself (boot=ash at power-on or at a full restart): Horizon reserves
    //                    its banks at start. $83 for another ARG0.
    case 0x1D:
        clk_base = arg0;
        clk_ms = time_millis();
        clk_set = 1;
        break;
    case 0x1E:
        if (arg0 != 5) { res = 0x83; break; }
        if ((reg_cart_mode & 0xFF) == 0) break;
        val = cart_bytes;
        if (len) {
            uint32_t n = strlen(cart_path);
            if (n > len - 1) n = len - 1;
            if (!mb_put(buf, (const uint8_t *)cart_path, n) || !mb_put(buf + n, (const uint8_t *)"", 1)) res = 0x81;
        }
        break;
    default:
        res = 0x82;
    }

    if (later == NS_LATER) {                             // put aside: only the request ring moves
        busy = 0;
        iop = reg_a816_mbi;
        reg_a816_mbi = (iop & 0x3FF00) | (uint8_t)(qtail + 1);
        return;
    }
    m[0] |= 0x80;
    m[8]  = res; m[9]  = res >> 8; m[10] = res >> 16; m[11] = res >> 24;
    m[12] = val; m[13] = val >> 8; m[14] = val >> 16; m[15] = val >> 24;
    busy = 0;
    in_service();                                        // (events first; one slot stays free)
    iop = reg_a816_mbi;                                  // events may have moved RSP_HEAD
    rhead = iop >> 8;
    if (!mb_put(rbase + rhead * 16, m, 16)) { reg_a816_mbi = iop | 0x20000; return; }
    reg_a816_mbi = (iop & 0x30000) | (uint8_t)(rhead + 1) << 8 | (uint8_t)(qtail + 1);
}

// ── The clock for file dates (SYS_TIME, $1D) ─────────────────────────────────────────────
// FatFs (FF_FS_NORTC = 0) asks get_fattime() whenever it stamps a file. Before Horizon has
// given the time: the build date, 00:00. (From a PC link session start the gateway's clock
// is used until Horizon gives the time again.)
DWORD fat_from2000(uint32_t t) {         // seconds since 2000-01-01 -> FAT date << 16 | time
    static const uint8_t mdays[12] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    uint32_t y, mo, h, mi, sec;
    sec = t % 60; t /= 60; mi = t % 60; t /= 60; h = t % 24; t /= 24;   // t = days since 2000
    for (y = 2000;; y++) {
        uint32_t n = (y & 3) ? 365 : 366;
        if (t < n) break;
        t -= n;
    }
    for (mo = 0; mo < 11; mo++) {
        uint32_t n = mdays[mo] + (mo == 1 && !(y & 3));
        if (t < n) break;
        t -= n;
    }
    return (y - 1980) << 25 | (mo + 1) << 21 | (t + 1) << 16 | h << 11 | mi << 5 | sec / 2;
}

DWORD get_fattime(void) {
    uint32_t y, mo, d;
    if (!clk_set) {                                      // __DATE__ = "Nov 17 2026"
        static const char mn[] = "JanFebMarAprMayJunJulAugSepOctNovDec";
        const char *b = __DATE__;
        mo = 1;
        for (int i = 0; i < 12; i++)
            if (b[0] == mn[i * 3] && b[1] == mn[i * 3 + 1] && b[2] == mn[i * 3 + 2]) mo = i + 1;
        d = (b[4] == ' ' ? 0 : b[4] - '0') * 10 + b[5] - '0';
        y = (b[7] - '0') * 1000 + (b[8] - '0') * 100 + (b[9] - '0') * 10 + b[10] - '0';
        return (y - 1980) << 25 | mo << 21 | d << 16;
    }
    return fat_from2000(clk_base + (time_millis() - clk_ms) / 1000);
}

// ── Step 3: printing, the folder disk, "Run in Atari" (cold) ──────────────────────────────

// "/PRN:" 1, "/PRN:..." 2, "/D1:"-"/D4:" exactly 3-6, else 0 (any case)
static int spec_path(const char *p) {
    if (p[0] != '/') return 0;
    if ((p[1] | 0x20) == 'p' && (p[2] | 0x20) == 'r' && (p[3] | 0x20) == 'n' && p[4] == ':') return p[5] ? 2 : 1;
    if ((p[1] | 0x20) == 'd' && p[2] >= '1' && p[2] <= '0' + ATR_DRIVES && p[3] == ':' && !p[4]) return 3 + p[2] - '1';
    return 0;
}

// ---- print jobs ----
// A job is written as "/Printouts/.YYYY-MM-DD HH.MM.SS NAME.txt" and renamed to the name without
// the dot when it is complete, so a job is whole when it appears.
static char prn_hname[MB_FILES][96] __attribute__((section(".sdbuf")));   // a /PRN: handle's job
static char prn_cname[96] __attribute__((section(".sdbuf")));             // the classic job's
static FIL  prn_fil;                      // the classic job's file (open once its text passed 192 KB)
static uint8_t prn_fopen;
static prn_conv_t prn_cv;
static uint32_t prn_n, prn_secs;

static uint32_t now_secs(void) {          // seconds since 2000 (0 before the clock was given)
    return clk_set ? clk_base + (time_millis() - clk_ms) / 1000 : 0;
}
static char *put_n(char *d, uint32_t v, int w) {   // v as w decimal digits
    for (int i = w - 1; i >= 0; i--) { d[i] = '0' + v % 10; v /= 10; }
    return d + w;
}
// a new job's file: final name (the shown one) -> final, the open file (under the dotted name).
// name: the job's name (the program, "Atari"); secs: when it started. 0 or a FatFs code.
static int prn_create(FIL *f, const char *name, uint32_t secs, char *final) {
    char t[96], nm[25];
    int k = 0;
    while (*name == ' ' || *name == '.') name++;
    for (; *name && k < 24; name++) {
        char c = *name;
        if ((uint8_t)c < 32 || strchr("\\/:*?\"<>|", c)) c = '_';
        nm[k++] = c;
    }
    while (k && (nm[k - 1] == ' ' || nm[k - 1] == '.')) k--;
    nm[k] = 0;
    if (!k) strcpy(nm, "Job");
    uint32_t ft = secs ? fat_from2000(secs) : get_fattime();
    FRESULT r = f_mkdir("/Printouts");
    if (r && r != FR_EXIST) return r;
    for (int n = 1; n < 100; n++) {
        char *d = final;
        strcpy(d, "/Printouts/");
        d += 11;
        d = put_n(d, (ft >> 25) + 1980, 4); *d++ = '-';
        d = put_n(d, ft >> 21 & 15, 2); *d++ = '-';
        d = put_n(d, ft >> 16 & 31, 2); *d++ = ' ';
        d = put_n(d, ft >> 11 & 31, 2); *d++ = '.';
        d = put_n(d, ft >> 5 & 63, 2); *d++ = '.';
        d = put_n(d, secs ? secs % 60 : (ft & 31) * 2, 2); *d++ = ' ';
        strcpy(d, nm);
        d += strlen(d);
        if (n > 1) { *d++ = ' '; if (n > 9) *d++ = '0' + n / 10; *d++ = '0' + n % 10; }
        strcpy(d, ".txt");
        strcpy(t, "/Printouts/.");
        strcat(t, final + 11);
        FILINFO fi;
        if (f_stat(final, &fi) == FR_OK) continue;      // taken (also by a job being written)
        r = f_open(f, t, FA_CREATE_NEW | FA_WRITE | FA_READ);
        if (r == FR_EXIST) continue;
        return r;
    }
    return FR_EXIST;
}
static uint32_t prn_done(FIL *f, const char *final) {   // the job's file closed and given its name
    char t[96];
    uint32_t r = f_close(f);
    strcpy(t, "/Printouts/.");
    strcat(t, final + 11);
    if (!r) r = f_rename(t, final);
    if (!r) prn_count++;
    uart_printf("print: %s %d\n", final + 11, (int)r);
    return r;
}
// a /PRN: handle: name = what follows "/PRN:"
static int prn_hopen(int h, const char *name) { return prn_create(&mb_fil[h], name, now_secs(), prn_hname[h]); }
static uint32_t prn_hclose(int h) {
    uint32_t r = prn_done(&mb_fil[h], prn_hname[h]);
    mb_open &= ~(1 << h);
    mb_prn &= ~(1 << h);
    return r;
}

// the classic job: its text so far into its file (opened at the first time)
static void prn_flush(void) {
    UINT bw;
    if (!prn_fopen) {
        if (prn_create(&prn_fil, "Atari", prn_secs, prn_cname)) { prn_n = 0; return; }   // (lost: the card)
        prn_fopen = 1;
    }
    f_write(&prn_fil, PRN_TXT, prn_n, &bw);
    prn_n = 0;
}
static void prn_end(void) {
    uint8_t out[2];
    int k = prn_finish(&prn_cv, out);
    for (int i = 0; i < k; i++) PRN_TXT[prn_n++] = out[i];
    if (prn_n || !prn_fopen) prn_flush();
    if (prn_fopen) prn_done(&prn_fil, prn_cname);
    prn_fopen = 0;
    prn_job = 0;
}
// the records in the ring -> text; the end of the job (3 s without data, the machine frozen)
static void prn_service(void) {
    uint8_t rec[48], out[48 + 256];
    while (prn_tail != prn_head) {
        uint32_t t = prn_tail;
        int n = PRN_RAW[t++ & (PRN_RING - 1)];
        for (int i = 0; i < n; i++) rec[i < 48 ? i : 47] = PRN_RAW[t++ & (PRN_RING - 1)];
        prn_tail = t;
        if (n > 48) n = 48;
        if (!prn_job) {
            prn_job = 1; prn_n = 0; prn_fopen = 0;
            memset(&prn_cv, 0, sizeof prn_cv);
            prn_secs = now_secs();
        }
        int k = prn_record(&prn_cv, rec, n, out);
        if (prn_n + k > PRN_TMAX) prn_flush();
        for (int i = 0; i < k; i++) PRN_TXT[prn_n++] = out[i];
    }
    if (prn_job && (time_millis() - prn_t > 3000 || (reg_a816_keymod & 0x200))) prn_end();
}

// ---- the folder disk ----
static int8_t fd_slot = -1;
void fd_poll(void) { in_tick(); sio_poll(); }
uint32_t fd_fattime(void) { return get_fattime(); }
// a file the firmware or Horizon has open: not replaced now (compared by its first cluster, or,
// for an empty file, by its directory entry)
int fd_busy(const char *path) {
    FIL p;
    if (f_open(&p, path, FA_READ)) return 0;
    uint32_t c = p.obj.sclust, ds = p.dir_sect, dp = p.dir_ptr - fs.win;
    f_close(&p);
    for (int h = 0; h < MB_FILES; h++) {
        FIL *f = &mb_fil[h];
        if (!(mb_open & (1 << h)) || (mb_pc & (1 << h))) continue;
        if (c ? f->obj.sclust == c : (f->dir_sect == ds && (uint32_t)(f->dir_ptr - fs.win) == dp)) return 1;
    }
    for (int s = 0; s < ATR_DRIVES; s++)
        if (atr_mounted[s] && c && atr_file[s].obj.sclust == c) return 1;
    if (xex_active && c && xex_file.obj.sclust == c) return 1;
    return 0;
}
static void fd_service(void) {
    fd_sync(FD_ST, FD_IMG);
    fd_fail = FD_ST->fail;
    if (!FD_ST->pending) fd_wr = 0;
    fd_tl = time_millis();
}
static void fd_flush(void) {               // everything the Atari closed saved (a few tries)
    if (fd_slot < 0) return;
    for (int k = 0; k < 5 && FD_ST->pending; k++) fd_sync(FD_ST, FD_IMG);
    if (!FD_ST->pending) fd_wr = 0;
}
// /atari.ini: the folder disk remembered (drive 1-4) or forgotten (0): the lines "folder=" and
// "folderdrive=" replaced, every other line kept
static void ini_folder(const char *path, int drive) {
    if (drive == option_folderdrive && (!drive || !strcmp(path, option_folder))) return;
    FIL f;
    UINT n = 0, bw;
    char *in = INI_BUF, *out = INI_BUF + 4096;
    uint32_t o = 0;
    int crlf = 0;
    if (!f_open(&f, OPTION_FILE, FA_READ)) { f_read(&f, in, 4095, &n); f_close(&f); }
    in[n] = 0;
    for (char *l = in; *l; ) {
        char *e = l;
        while (*e && *e != '\n') e++;
        if (e > l && e[-1] == '\r') crlf = 1;
        char *k = l;
        while (*k == ' ' || *k == '\t') k++;
        int skip = (!memcmp(k, "folder", 6) && (k[6] == '=' || k[6] == ' ')) ||
                   (!memcmp(k, "folderdrive", 11) && (k[11] == '=' || k[11] == ' '));
        if (*e) e++;
        if (!skip) while (l < e) out[o++] = *l++;
        l = e;
    }
    if (o && out[o - 1] != '\n') { if (crlf) out[o++] = '\r'; out[o++] = '\n'; }
    if (drive) {
        char *d = out + o;
        strcpy(d, "folder="); strcat(d, path); strcat(d, crlf ? "\r\nfolderdrive=" : "\nfolderdrive=");
        o += strlen(d);
        out[o++] = '0' + drive;
        if (crlf) out[o++] = '\r';
        out[o++] = '\n';
    }
    if (!f_open(&f, OPTION_FILE, FA_CREATE_ALWAYS | FA_WRITE)) { f_write(&f, out, o, &bw); f_close(&f); }
    option_folderdrive = drive;
    strcpy(option_folder, drive ? path : "");
}
static int mount_folder(const char *path, int slot, int remember) {
    for (int i = 0; i < ATR_DRIVES; i++) if (rd_kind[i] == 1) rd_drop(i, 0);   // one folder disk
    if (atr_mounted[slot]) { f_close(&atr_file[slot]); atr_mounted[slot] = false; }
    if (!slot && xex_active) { f_close(&xex_file); xex_active = false; }
    if (rd_kind[slot]) rd_drop(slot, 0);
    int r = fd_build(FD_ST, FD_IMG, path);
    uart_printf("folder disk: %s on D%d: %d files, %d left out, %d free (%d)\n", path, slot + 1,
                FD_ST->shown, FD_ST->skipped, FD_ST->nfree, r);
    if (r) { FD_ST->dir[0] = 0; return r; }
    rd_kind[slot] = 1; rd_base[slot] = FD_IMG; rd_nsec[slot] = FD_NSEC;
    atr_readonly[slot] = false; atr_sector_size[slot] = 128;
    fd_slot = slot; fd_wr = 0; fd_fail = 0;
    if (remember) ini_folder(path, slot + 1);
    return 0;
}
// the memory disk on slot out: the folder disk saved first (forget: and /atari.ini forgets it)
static void rd_drop(int slot, int forget) {
    if (rd_kind[slot] == 1) {
        fd_flush();
        FD_ST->dir[0] = 0;
        fd_slot = -1; fd_wr = 0;
        if (forget) ini_folder("", 0);
    }
    rd_kind[slot] = 0;
    atr_readonly[slot] = false;
}
// "Run in Atari": a BASIC program (a listing, or a SAVE file) as the boot disk on D1:
static int mount_run(const char *path) {
    FIL f;
    UINT br;
    int r = f_open(&f, path, FA_READ);
    if (r) return r;
    uint32_t n = f_size(&f);
    uint8_t *raw = RUN_IMG + 0x8000, *o = RUN_IMG + (BAS_DATASEC - 1) * 128;
    if (!n || n > RUN_MAX - 0x8000) { f_close(&f); return -1; }
    r = f_read(&f, raw, n, &br);
    f_close(&f);
    if (r || br != n) return r ? r : -6;
    int tok = n >= 14 && !raw[0] && !raw[1] && !raw[2] && raw[3] == 1;   // LOMEM 0, VNTP $0100
    uint32_t m = 0;
    if (tok) for (; m < n; m++) o[m] = raw[m];
    else {                                     // LF, CR LF, CR -> $9B; TAB -> blank
        for (uint32_t i = 0; i < n; i++) {
            uint8_t c = raw[i];
            if (c == '\r') { c = 0x9B; if (i + 1 < n && raw[i + 1] == '\n') i++; }
            else if (c == '\n') c = 0x9B;
            else if (c == '\t') c = ' ';
            o[m++] = c;
        }
        if (m && o[m - 1] != 0x9B) o[m++] = 0x9B;
        while (m && o[m - 1] == 0x9B) {         // trailing empty lines, and a last RUN (it runs anyway)
            uint32_t b = m - 1;
            while (b && o[b - 1] != 0x9B) b--;
            uint32_t a = b, e = m - 1;
            while (a < e && o[a] == ' ') a++;
            while (e > a && o[e - 1] == ' ') e--;
            int run = e - a == 3 && (o[a] | 0x20) == 'r' && (o[a + 1] | 0x20) == 'u' && (o[a + 2] | 0x20) == 'n';
            if (e != a && !run) break;
            m = b;
        }
    }
    for (int i = 0; i < BAS_NSEC * 128; i++) RUN_IMG[i] = bas_loader_img[i];
    for (int i = BAS_NSEC * 128; i < (BAS_DATASEC - 1) * 128; i++) RUN_IMG[i] = 0;
    RUN_IMG[BAS_P_LEN] = m; RUN_IMG[BAS_P_LEN + 1] = m >> 8; RUN_IMG[BAS_P_LEN + 2] = m >> 16;
    RUN_IMG[BAS_P_MODE] = tok;
    for (uint32_t i = m; i & 127; i++) o[i] = 0;
    if (atr_mounted[0]) { f_close(&atr_file[0]); atr_mounted[0] = false; }
    if (xex_active) { f_close(&xex_file); xex_active = false; }
    rd_kind[0] = 2; rd_base[0] = RUN_IMG; rd_nsec[0] = BAS_DATASEC - 1 + (m + 127) / 128;
    atr_readonly[0] = true; atr_sector_size[0] = 128;
    uart_printf("run: %s, %d bytes, %s\n", path, (int)m, tok ? "SAVE file" : "listing");
    return 0;
}
// a cold start of the classic machine: its print job ends; the folder disk is saved, then built
// again from the folder (so it shows what Horizon changed meanwhile)
static void classic_cold_hooks(void) {
    if (prn_job) prn_end();
    if (fd_slot >= 0) {
        char d[128];
        int s = fd_slot;
        fd_flush();
        strcpy(d, FD_ST->dir);
        rd_kind[s] = 0;
        fd_slot = -1;
        if (!fd_build(FD_ST, FD_IMG, d)) { rd_kind[s] = 1; fd_slot = s; fd_wr = 0; }
    }
}

// Is there anything for a816_mailbox to do? It runs from SDRAM (cold), and the PicoRV32's
// accesses there come before the 65C816's, Marga's and Ali's: calling it on every loop of
// the main loop took 10-20 % of the 65C816's memory time while Horizon ran (measured with
// core/sw/a816/timing.s). This check is hot and reads only registers.
static int a816_mb_wanted(void) {
    uint32_t q = rd2(&reg_a816_mbq), r = rd2(&reg_a816_mbr), iop = reg_a816_mbi;
    if (sys_restart || !(q & 0xFFFFFF) || !(r & 0xFFFFFF) || !(iop & 0x10000)) return 1;
    return (uint8_t)(q >> 24) != (uint8_t)iop;                        // a request waits
}

// ── The developer channel (PC link channel 3; ops in Docs/04-pc-link.md) ─────────────────
// Requests come from the PC tools (core/tools/atari.py), one at a time; the answer is sent
// when the request is done (TYPE: when the text is typed). Frame payloads: op, tag, flags,
// result, then data. Big answers (PEEK816) are sent as several frames (flag MORE).
#define D_INFO 0x01
#define D_PUT 0x02
#define D_RESTART816 0x03
#define D_RUN 0x04
#define D_COLD 0x05
#define D_WARM 0x06
#define D_EJECT 0x07
#define D_KEY 0x08
#define D_MOUSE 0x09
#define D_TYPE 0x0A          // (removed: typing text on the classic keyboard; answers $82)
#define D_PEEK 0x0B
#define D_POKE 0x0C
#define D_FWPEEK 0x0D
#define D_PEEK816 0x0E
#define D_ECHO 0x0F
#define D_SOURCE 0x10
#define D_SINK 0x11
#define D_INJECT 0x12
void in_inject(uint16_t keys, uint16_t key_ms, uint16_t mice, uint8_t mouse_ms);

static uint8_t dv_out[1024] __attribute__((section(".sdbuf")));   // an answer being built
static uint32_t dv_n;
static uint8_t dv_hdr[4];                // op | $80, tag, flags, result
static int dv_fail;                      // the link went down while answering

static void dv_begin(const uint8_t *p) { dv_hdr[0] = p[0] | 0x80; dv_hdr[1] = p[1]; dv_hdr[2] = 0; dv_hdr[3] = 0; dv_n = 0; dv_fail = 0; }
static void dv_flush(int more) {
    dv_hdr[2] = more ? PL_RQ_MORE : 0;
    if (!dv_fail && pl_send(PL_CH_DEV, dv_hdr, dv_out, dv_n)) dv_fail = 1;
    dv_n = 0;
}
static void dv_put(uint8_t b) { dv_out[dv_n++] = b; if (dv_n == sizeof dv_out) dv_flush(1); }
static void dv_end(uint8_t res) { dv_hdr[3] = res; dv_flush(0); }
static void dv_reply(const uint8_t *p, uint8_t res) { dv_begin(p); dv_end(res); }

// print into the answer (INFO): uart_printf with its output caught (picorv32.c, uart_putchar)
extern char *uart_catch;
extern int uart_catch_n, uart_catch_max;

// PUT: frame 1 = size u32, path; then frames of offset u32 + data; the answer after the last
static uint8_t  put_on, put_tag;
static uint32_t put_size, put_done, put_err;
static char     put_path[SD_PATH_MAX];

static void dev_put(const uint8_t *p, uint32_t n) {
    int last = !(p[2] & PL_RQ_MORE);
    if (!put_on || p[1] != put_tag) {                    // the first frame of a PUT
        if (put_on) bridge_put_close();
        put_on = 1; put_tag = p[1]; put_done = 0; put_err = 0;
        put_size = n >= 8 ? le32(p + 4) : 0;
        uint32_t k = 0;
        put_path[k++] = '/';
        for (uint32_t i = 8; i < n && p[i] && k < sizeof put_path - 1; i++)
            if (!(k == 1 && p[i] == '/')) put_path[k++] = p[i];
        put_path[k] = 0;
        if (mb_synced || bridge_mkdirs(put_path) || bridge_put_open(put_path)) {   // (after SYS_SYNC: refused)
            put_err = FR_DENIED; put_on = 2;             // refused: data is ignored
        }
    } else if (put_on == 1 && !put_err) {
        if (n < 8 || le32(p + 4) != put_done) put_err = FR_INT_ERR;
        else {
            int r = bridge_put_chunk(p + 8, n - 8);
            if (r) put_err = r;
            put_done += n - 8;
        }
    }
    if (!last) return;
    int opened = put_on == 1;
    put_on = 0;
    if (opened) {
        int cr = bridge_put_close();
        if (!put_err && (cr || put_done != put_size)) put_err = FR_INT_ERR;
        // after a card-level error leave the partial file rather than touch the volume again
        if (put_err && put_err != FR_DISK_ERR && put_err != FR_INT_ERR) f_unlink(put_path);
        else if (put_err && put_done != put_size && put_err == FR_INT_ERR) f_unlink(put_path);
    }
    uart_printf("put %s %d%s\n", put_path, (int)put_done, put_err ? " failed" : "");
    dv_reply(p, put_err);
}

// PEEK816 addr u32, width u16, rows u16, stride u32, flags u8: 65C816 memory as the CPU sees
// it (mb_ptr's map), rows of `width` bytes `stride` apart (a framebuffer = a screenshot).
// Bytes the I/O processor cannot reach (bank $10, $80 and up) read 0. The answer stream is
// the data and then sum16 (of the raw bytes, little-endian). Flags bit 0 = RLE: packets, h
// 0-127 = h + 1 literal bytes follow, 128-255 = the next byte repeated h - 125 (3-130) times;
// bit 1 = XOR2: from the third byte of each row on, a byte is sent XORed with the raw byte
// two before it (dithered desktop pattern -> zeros; before RLE); bit 2 = the sum only.
// The SDRAM always holds what the CPU and the blitter wrote (write-through cache), so this
// never disturbs the 65C816. Requests of up to 1 MB; the tools ask for about 64 KB at a time.
static uint8_t  pk_lit[128];
static uint32_t pk_nl;
static void pk_flush_lit(void) {
    if (!pk_nl) return;
    dv_put((uint8_t)(pk_nl - 1));
    for (uint32_t i = 0; i < pk_nl; i++) dv_put(pk_lit[i]);
    pk_nl = 0;
}
static void pk_run(uint32_t run_n, uint8_t run_b) {
    if (run_n >= 3) { pk_flush_lit(); dv_put((uint8_t)(run_n + 125)); dv_put(run_b); }
    else while (run_n--) { pk_lit[pk_nl++] = run_b; if (pk_nl == 128) pk_flush_lit(); }
}
static __attribute__((noinline)) void dev_peek816(const uint8_t *p, uint32_t n) {
    if (n < 4 + 13) { dv_reply(p, 0x83); return; }
    uint32_t addr = le32(p + 4) & 0xFFFFFF;
    uint32_t width = p[8] | p[9] << 8, rows = p[10] | p[11] << 8, stride = le32(p + 12);
    int c = p[16], rle = c & 1, x2 = c & 2, quiet = c & 4;
    if (!width || !rows || width * rows > 0x100000) { dv_reply(p, 0x83); return; }
    dv_begin(p);
    uint32_t run_n = 0, sum = 0;
    uint8_t run_b = 0;
    pk_nl = 0;
    for (uint32_t r = 0; r < rows && !dv_fail; r++, addr += stride) {
        uint8_t b1 = 0, b2 = 0;                          // raw bytes x - 1, x - 2
        uint32_t wa = 1, wv = 0;                         // the 32-bit word last read
        for (uint32_t x = 0; x < width; x++) {
            uint32_t a = (addr + x) & 0xFFFFFF, room;
            if ((a & ~3u) != wa) {                       // (mb_ptr's map, inline: this is hot)
                wa = a & ~3u;
                room = !(wa >= 0x800000 || (wa >> 16) == 0x10);
                wv = room ? *(volatile uint32_t *)(wa < 0x400000 ? wa ^ 0x100000 : wa ^ 0x300000) : 0;
            }
            uint8_t b = (uint8_t)(wv >> ((a & 3) * 8));
            sum += b;
            if (quiet) continue;
            uint8_t raw = b;
            if (x2 && x >= 2) b ^= b2;
            b2 = b1; b1 = raw;
            if (!rle) { dv_put(b); continue; }
            if (run_n && b == run_b && run_n < 130) { run_n++; continue; }
            pk_run(run_n, run_b);
            run_b = b; run_n = 1;
        }
    }
    if (rle && !quiet) { pk_run(run_n, run_b); pk_flush_lit(); }
    dv_put(sum & 0xFF);
    dv_put((sum >> 8) & 0xFF);
    dv_end(0);
}

// the most stack ever used, in bytes (main() painted it; the top is 0x8000)
static int stack_used(void) {
    extern char _ebss[];
    uint32_t *w = (uint32_t *)_ebss + 1;
    while ((uint32_t)w < 0x8000 && *w == 0x5AC3A55Au) w++;
    return 0x8000 - (int)(uint32_t)w;
}

void pl_dev_request(const uint8_t *p, uint32_t n) {
    if (n < 4) return;
    const uint8_t *a = p + 4;
    uint32_t na = n - 4;
    switch (p[0]) {
    case D_INFO: {                       // one text line: the firmware's state (old STATUS)
        extern char _ebss[];
        dv_begin(p);
        uart_catch = (char *)dv_out; uart_catch_n = 0; uart_catch_max = sizeof dv_out;
        uart_printf("ST u:%d bs:%d rom:%d x:%d m:%d%d%d%d c:%b s:%d st:%d e:%d cn:%d br:%d"
                    " link rx:%d bad:%d retry:%d pc:%d"
                    " in gap:%d ev:%d ksent:%d klost:%d msent:%d mlost:%d stk:%d"
                    " prn:%d fd:%d/%d/%d\n",
                    (int)time_millis(), bridge_boot_stage, bridge_rom_ok, xex_active ? 1 : 0,
                    atr_mounted[0] ? 1 : 0, atr_mounted[1] ? 1 : 0,
                    atr_mounted[2] ? 1 : 0, atr_mounted[3] ? 1 : 0,
                    dbg_last_sio_cmd, dbg_last_sio_sector, dbg_last_sio_status,
                    (int)dbg_sio_err_count,
                    (*(volatile uint32_t *)_ebss != 0x53544B21u) ? 1 : 0, boot_retries,
                    (int)pl_rx_bytes(), (int)pl_rx_bad(), (int)pl_retries(), pl_files(),
                    (int)(in_gap / 27), (int)in_nev, (int)gk_sent, (int)gk_lost,
                    (int)gm_sent, (int)gm_lost, stack_used(),
                    (int)prn_count, fd_slot + 1, fd_slot >= 0 ? FD_ST->pending : 0, fd_slot >= 0 ? (int)FD_ST->conflicts : 0);
        in_gap = 0; in_nev = 0;                         // (the meters start again)
        dv_n = uart_catch_n;
        uart_catch = 0;
        dv_end(0);
        break;
    }
    case D_PUT: dev_put(p, n); break;
    case D_RESTART816:                   // a = 0: Horizon (or /A816.BIN); 1: /A816.BIN only
        a816_start(na && a[0] == 1);
        dv_reply(p, 0);
        break;
    case D_RUN: {                        // path of a .xex: mount it, cold boot (main loop)
        uint32_t k = 0;
        bridge_req_path[k++] = '/';
        for (uint32_t i = 0; i < na && a[i] && k < SD_PATH_MAX - 1; i++)
            if (!(k == 1 && a[i] == '/')) bridge_req_path[k++] = a[i];
        bridge_req_path[k] = 0;
        bridge_req = 1;
        dv_reply(p, 0);
        break;
    }
    case D_COLD: bridge_req = 2; dv_reply(p, 0); break;
    case D_WARM: bridge_req = 3; dv_reply(p, 0); break;
    case D_EJECT:                        // the virtual .xex boot disk (D1:)
        if (xex_active) { f_close(&xex_file); xex_active = false; }
        dv_reply(p, 0);
        break;
    case D_KEY:                          // mod, HID usage, hold (10 ms units): a raw key press
        if (na < 3) { dv_reply(p, 0x83); break; }
        kv_set0(((uint32_t)a[1] << 8) | a[0]);
        // released later by joy_get(): the main loop must see the key down (F12, F9)
        virt_key_release_at = time_millis() + (a[2] ? a[2] * 10 : 100);
        dv_reply(p, 0);
        break;
    case D_MOUSE:                        // dx, dy, wheel (signed), buttons: a MOUSE event
        if (na < 4) { dv_reply(p, 0x83); break; }
        in_mouse(a[3], (int8_t)a[0], (int8_t)a[1], (int8_t)a[2]);
        dv_reply(p, 0);
        break;
    case D_PEEK: {                       // addr u16, len u16: classic machine memory
        uint32_t ad = a[0] | a[1] << 8, len = a[2] | a[3] << 8;
        if (na < 4 || len > 1024) { dv_reply(p, 0x83); break; }
        dv_begin(p);
        for (uint32_t i = 0; i < len; i++) dv_put(*(volatile uint8_t *)(0x00200000u + ((ad + i) & 0xFFFFu)));
        dv_end(0);
        break;
    }
    case D_POKE: {                       // addr u16, bytes
        uint32_t ad = a[0] | a[1] << 8;
        if (na < 2) { dv_reply(p, 0x83); break; }
        for (uint32_t i = 2; i < na; i++) *(volatile uint8_t *)(0x00200000u + ((ad + i - 2) & 0xFFFFu)) = a[i];
        dv_reply(p, 0);
        break;
    }
    case D_FWPEEK: {                     // addr u32, len u16: the I/O processor's own memory
        uint32_t ad = le32(a), len = a[4] | a[5] << 8;
        if (na < 6 || len > 1024) { dv_reply(p, 0x83); break; }
        dv_begin(p);
        for (uint32_t i = 0; i < len; i++) dv_put(*(volatile uint8_t *)(ad + i));
        dv_end(0);
        break;
    }
    case D_PEEK816: dev_peek816(p, n); break;
    case D_ECHO:
        dv_begin(p);
        for (uint32_t i = 0; i < na; i++) dv_put(a[i]);
        dv_end(0);
        break;
    case D_SOURCE: {                     // len u32: that many bytes (i & $FF) back (speed test)
        uint32_t len = na >= 4 ? le32(a) : 0;
        dv_begin(p);
        for (uint32_t i = 0; i < len && !dv_fail; i++) dv_put((uint8_t)i);
        dv_end(0);
        break;
    }
    case D_INJECT:                       // keys u16, key period u16 (ms), mice u16, mouse period u8
        if (na < 7) { dv_reply(p, 0x83); break; }
        in_inject(a[0] | a[1] << 8, a[2] | a[3] << 8, a[4] | a[5] << 8, a[6]);
        dv_reply(p, 0);
        break;
    case D_SINK: {                       // frames of data, thrown away (speed test); answer: count
        static uint32_t got;
        got += na;
        if (p[2] & PL_RQ_MORE) break;
        dv_begin(p);
        for (int i = 0; i < 4; i++) dv_put(got >> (8 * i));
        got = 0;
        dv_end(0);
        break;
    }
    default:
        dv_reply(p, 0x82);
    }
}

// a link session started or ended. At the start the PC's clock dates the files on the card
// (Horizon gives its own time again when its clock is set).
void pl_session(int up) {
    if (up) { clk_base = pl_pc_time(); clk_ms = time_millis(); clk_set = 1; }
    ns_session(up);                                      // (step 2) streams of an old session end
    uart_printf("link: %s\n", up ? "PC connected" : "PC gone");
}

// while the firmware waits for the PC: keep the keyboard and the classic disks served
void pl_idle(void) {
    in_service();
    sio_poll();
}

// while frames keep coming during a wait (a long READ or LOAD from the PC): input only
void pl_busy(void) { in_tick(); }

static uint32_t ns_t;
static void bridge_poll(void) {
    static int busy = 0;             // re-entry guard
    if (busy) return;
    busy = 1;
    in_service();
    a816_poll();
    if ((reg_a816_mbq | reg_a816_mbi) && a816_mb_wanted()) a816_mailbox();
    pl_poll();
    if (ns_work) ns_service();                            // (step 2) answers put aside, credit
    else if (ns_npend && time_millis() - ns_t > 250) { ns_t = time_millis(); ns_service(); }   // their timeouts
    // (step 3) the printer's records, the end of a print job (3 s without data, or the classic
    // machine frozen); the folder disk saved after 1.5 s without the Atari using it (10 s after
    // a failed save). Only flags and the clock here: nothing from SDRAM while idle.
    if (prn_head != prn_tail || (prn_job && (time_millis() - prn_t > 3000 || (reg_a816_keymod & 0x200)))) prn_service();
    if (fd_wr && time_millis() - fd_tl > (fd_fail ? 10000u : 1500u)) fd_service();
    busy = 0;
}
// Stack canary at the very bottom of the stack region (= _ebss, no heap in this
// firmware). The linker guarantees >= 4 KB between _ebss and STACK_TOP; if the
// stack ever reaches the canary it has (nearly) collided with the top of bss —
// which holds the FatFs volume pointer, atr_mounted[], the OSD cursor... (=
// exactly the "everything FS goes weird after a write" corruption pattern).
// Checked on every main-menu paint: '!' appended to the SIO debug line.
extern char _ebss[];
#define STACK_CANARY_MAGIC 0x53544B21u   // "STK!"
static inline void stack_canary_arm(void)  { *(volatile uint32_t *)_ebss = STACK_CANARY_MAGIC; }
static inline int  stack_canary_dead(void) { return *(volatile uint32_t *)_ebss != STACK_CANARY_MAGIC; }

// ── Hot/cold split (Atari816) ───────────────────────────────────────────────
// Only boot code and the time-critical paths (SIO, SD, FatFs read/write, UART) live in
// the 32 KB block RAM; baremetal.ld lists them. Everything else is the "cold" image:
// it sits in SPI flash at COLD_FLASH_ADDR and is copied to SDRAM at 0x10000 here, before
// anything cold is called. cold_sig is patched by mkcold.py with the length and CRC-32 of
// the cold image this hot image was linked against, so a stale flash copy is refused.
#define COLD_FLASH_ADDR 0x500000
#define COLD_MAGIC      0x444C4F43u            // "COLD"
extern uint8_t _cold_start[];
const volatile uint32_t cold_sig[2] __attribute__((section(".coldsig"), used)) = { 0, 0 };

static uint32_t crc32_upd(uint32_t c, const volatile uint8_t *p, uint32_t n) {
    while (n--) {
        c ^= *p++;
        for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & -(c & 1));
    }
    return c;
}

static int cold_load(void) {
    uint32_t hdr[3];
    uint8_t buf[256];
    uint32_t len = cold_sig[0];
    spiflash_read(COLD_FLASH_ADDR, (uint8_t *)hdr, 12);
    if (hdr[0] != COLD_MAGIC) return 1;
    if (hdr[1] != len || hdr[2] != cold_sig[1]) return 2;
    for (uint32_t off = 0; off < len; off += 256) {
        uint32_t n = len - off < 256 ? len - off : 256;
        spiflash_read(COLD_FLASH_ADDR + 12 + off, buf, n);
        for (uint32_t i = 0; i < n; i++) _cold_start[off + i] = buf[i];
    }
    return (~crc32_upd(~0u, _cold_start, len) == cold_sig[1]) ? 0 : 3;
}

int main_app(void);

int main() {
    {                                          // paint the free stack (INFO's "stk": the most used)
        extern char _ebss[];
        uint32_t sp;
        __asm__ volatile ("mv %0, sp" : "=r"(sp));
        for (uint32_t *w = (uint32_t *)_ebss + 1; (uint32_t)w < sp - 64; w++) *w = 0x5AC3A55Au;
    }
    pl_init();                                 // the PC link: its rate, the log (hot)
    uart_printf("boot: hot\n");
    for (;;) {
        int r = cold_load();
        if (r == 0) break;
        uart_printf("boot: cold image error %d (flash cold.bin at 0x500000)\n", r);
        delay(1000);
    }
    uart_printf("boot: cold ok\n");
    return main_app();
}

int main_app() {
    stack_canary_arm();
    delay(200); // Give SD card time to stabilize power on startup
    CORE_ID = reg_core_id;


    // Initialize SD Card
    int mounted = 0;
    while(!mounted) {
        for (int attempts = 0; attempts < 255; attempts++) {
            if (f_mount(&fs, "", 0) == FR_OK) {
                mounted = 1;
                break;
            }
            bridge_poll();           // stay reachable while waiting for the card
        }
        if (!mounted)
{ message("Insert SD card", 1); delay(1000); }
    }

    bridge_boot_stage = 1;
    uart_printf("boot: sd ok\n");
   

    // load_option() is the first real SD access (f_mount above is lazy). On a warm
    // reset the card is mid-state and this first read can fail transiently — retry with
    // a full remount, exactly like the ROM loader below. Without this, a glitched first
    // read silently reverts ALL options to defaults while the ROM loader still recovers,
    // i.e. "settings saved fine but boot comes up with defaults". (-1 = transient.)
    int opt_r = load_option();
    for (int attempt = 0; opt_r < 0 && attempt < 5; attempt++) {
        uart_printf("load_option failed (transient), remount+retry %d\n", attempt + 1);
        delay(50);
        f_mount(0, "", 0);                       // unmount (deinit volume)
        delay(20);
        if (f_mount(&fs, "", 0) != FR_OK) { delay(80); continue; }
        opt_r = load_option();
    }
    // Initialize USB Host enable state based on loaded option (0 = UART, 1 = USB)
   
    apply_input_options();
    apply_video_options();
    apply_machine_options();   // set RAM_SELECT before the core is released below
    sio_init();
   

    bridge_boot_stage = 2;

    // Auto-load system ROMs on boot. On a warm reset (S1) the SD card is left
    // mid-state and FatFs reads can fail transiently (e.g. FR_INT_ERR on the 2nd
    // file). Retry with a full unmount/re-mount (resets FatFs state + forces a
    // fresh SD re-init on the next access) before giving up.
    load_default_cart();          // boot=ash: /ASH.CAR into the slot before the ROMs go in
    int rom_ok = load_system_roms();
    for (int attempt = 0; rom_ok != 0 && attempt < 5; attempt++) {
        uart_printf("ROM load failed (0x%x), remount+retry %d\n", rom_ok, attempt + 1);
        delay(50);
        f_mount(0, "", 0);                       // unmount (deinit volume)
        delay(20);
        if (f_mount(&fs, "", 0) != FR_OK) { delay(80); continue; }
        rom_ok = load_system_roms();
    }
    bridge_boot_stage = 3;
    bridge_rom_ok = rom_ok;
    a816_start(0);                // Atari816 bring-up: no-op without /A816.BIN
    uart_printf("boot: roms %d\n", rom_ok);
   
    if (rom_ok != 0) {
        // No on-screen menu any more: report on the serial log and stay reachable over the
        // PC Link (files can still be sent; COLD/WARM/RUN leave this loop and are executed
        // by the main loop below). S1 resets the whole firmware.
        uart_printf("ROM load error 0x%x (op %d: 1=OpOS 2=RdOS 3=OpBas 4=RdBas, FatFs %d)\n",
                    rom_ok, rom_ok >> 8, rom_ok & 0xFF);
        uart_printf("Check /ATARIXL.ROM and /BASIC.ROM on the SD card, then press S1\n");
        for (;;) {
            bridge_poll();
            if (bridge_req) break;
        }
    }

    // Rung-1 "hard drive": if /HDD.ATR exists it auto-mounts on D4: at every
    // boot (convention over configuration — no menu, no ini key). Create one
    // with the OSD's New-blank-disk + rename, or copy any big MyDOS ATR.
    if (rom_ok == 0) {
        mount_silent = 1;
        if (mount_atr("/HDD.ATR", 3) == 0) uart_printf("boot: hdd mounted on D4\n");
        mount_silent = 0;
        if (option_folderdrive >= 1 && option_folderdrive <= ATR_DRIVES && option_folder[0])   // (step 3)
            uart_printf("boot: folder disk %s on D%d: %d\n", option_folder, option_folderdrive,
                        mount_folder(option_folder, option_folderdrive - 1, 0));
    }
   
    if (rom_ok == 0) {
        bridge_boot_stage = 4;
        uart_printf("boot: running\n");
    }
    int f9_prev = 0;             // F9 soft-reset hotkey edge detector
    int f11_prev = 0;            // F11 arrows<->joystick live-toggle edge detector

    for (;;) {
        {
            bootwd_poll();               // cold-boot watchdog (no-op once the OS is running)
            int joy1, joy2;
            joy_get(&joy1, &joy2);
            // F9 = soft reset hotkey (same warm start as the menu's Soft Reset)
            int f9 = (joy1 & 0x4);
            if (f9 && !f9_prev) {
                kv_set0(0x00000000);
                warm_reset();
                delay(300);
            }
            f9_prev = f9;

            // F11 = quick LIVE toggle: arrow keys drive Joystick 1 <-> normal
            // typing (the same option_arrow_joystick the OSD "Arrow keys" item
            // sets, applied live via reg_virt_kbd_1). Live-only: it is NOT written
            // to atari.ini, so it reverts to the saved default on the next reboot
            // (use OSD Options -> Save changes to make a preference permanent).
            int f11 = (joy1 & 0x400);            // rv_joy1 bit 10 = F11
            if (f11 && !f11_prev) {
                option_arrow_joystick = !option_arrow_joystick;
                apply_input_options();
                delay(200);                      // debounce the keypress
            }
            f11_prev = f11;

            // Background polling loop — service SIO (bounded per call).
            sio_poll();
            sio_poll();
            sio_poll();
            // (frame_rate_sample() retired 2026-09-20: its result was never displayed; image size)
            bridge_poll();
            if (bridge_req) {        // deferred bridge actions (RUN/COLD/WARM)
                int r = bridge_req;
                bridge_req = 0;
                if (r == 1) {
                    // Remote mount: never popup (mount_silent), and retry once —
                    // a fresh f_open right after the PUT's f_close failed
                    // transiently on HW (same FatFs mid-state family as
                    // load_option's documented remount-retry).
                    mount_silent = 1;
                    char *e = strrchr(bridge_req_path, '.');   // (step 3) .BAS / .LST: Run in Atari
                    int bas = e && (!strcasecmp(e, ".bas") || !strcasecmp(e, ".lst"));
                    if (rd_kind[0]) rd_drop(0, 1);
                    int mr = bas ? mount_run(bridge_req_path) : mount_xex(bridge_req_path);
                    if (mr != 0) {
                        delay(100);
                        mr = bas ? mount_run(bridge_req_path) : mount_xex(bridge_req_path);
                    }
                    mount_silent = 0;
                    if (mr == 0 && bas) {
                        cold_boot_basic();
                    } else if (mr == 0) {
                        cold_boot_xex();
                    } else {
                        uart_printf("run: mount failed %d\n", mr);
                    }
                } else if (r == 2) {
                    cold_boot_atari();
                } else if (r == 3) {
                    kv_set0(0x00000000);
                    warm_reset();
                }
            }
        }
    }
}

#define CH9350_STATE_IDLE 0
#define CH9350_STATE_AB   1
#define CH9350_STATE_CMD  2
#define CH9350_STATE_LEN  3
#define CH9350_STATE_DATA 4

static int ch_state = CH9350_STATE_IDLE;
static uint8_t ch_cmd = 0;
static uint8_t ch_len = 0;
static uint8_t ch_buf[16];
static uint8_t ch_idx = 0;
static uint32_t last_kbd_time = 0;
uint8_t ch_raw[64];          // last raw bytes from the CH9350 (diagnosis, read with fwpeek)
uint8_t ch_raw_i;

// one byte of the CH9350's stream (the UART, or the INJECT test generator's reports)
HOT_FN void ch_byte(uint8_t b) {
    switch (ch_state) {
        case CH9350_STATE_IDLE:
            if (b == 0x57) {
                ch_state = CH9350_STATE_AB;
            }
            break;
        case CH9350_STATE_AB:
            if (b == 0xAB) {
                ch_state = CH9350_STATE_CMD;
            } else if (b != 0x57) {
                ch_state = CH9350_STATE_IDLE;
            }
            break;
        case CH9350_STATE_CMD:
            ch_cmd = b;
            ch_state = CH9350_STATE_LEN;
            break;
        case CH9350_STATE_LEN:
            ch_len = b;
            ch_idx = 0;
            if (ch_len > 0 && ch_len <= 16) {
                ch_state = CH9350_STATE_DATA;
            } else {
                ch_state = CH9350_STATE_IDLE;
            }
            break;
        case CH9350_STATE_DATA:
            ch_buf[ch_idx++] = b;
            if (ch_idx >= ch_len) {
                // Packet fully received! Verify checksum.
                uint8_t sum = 0;
                // the sum covers the report and the serial byte, not the type byte
                // (measured: 57 AB 88 07 20 00 F3 03 00 14 0A)
                for (int i = 1; i < ch_len - 1; i++) {
                    sum += ch_buf[i];
                }
                // (as the hardware decoder uart_kbd_ch9350.sv: the sum with or without the
                // type byte; keyboard reports of type $10 or $11)
                if (sum == ch_buf[ch_len - 1] || (uint8_t)(sum + ch_buf[0]) == ch_buf[ch_len - 1]) {
                    // Checksum ok. Extract keyboard reports.
                    if ((ch_cmd == 0x88 || ch_cmd == 0x83) && (ch_buf[0] & 0xFE) == 0x10) {
                        uint8_t modifier = ch_buf[1];
                        uint8_t key1 = ch_buf[3]; // ch_buf[2] is reserved
                        uint8_t key2 = ch_buf[4];
                        uint8_t key3 = ch_buf[5];
                        uint8_t key4 = ch_buf[6];
                        
                        kv_set0(modifier | (key1 << 8) | (key2 << 16) | (key3 << 24));
                        kv_set1((option_arrow_joystick ? 0x200 : 0x000) | key4);
                        last_kbd_time = time_millis();
                    } else if ((ch_cmd == 0x88 || ch_cmd == 0x83) && (ch_buf[0] & 0xF0) == 0x20 && ch_len >= 5) {
                        // relative mouse report: buttons, dx, dy, wheel (57 AB 88 07 2x btn dx dy wheel serial sum)
                        in_mouse(ch_buf[1], (int8_t)ch_buf[2], (int8_t)ch_buf[3], ch_len >= 7 ? (int8_t)ch_buf[4] : 0);
                    }
                }
                ch_state = CH9350_STATE_IDLE;
            }
            break;
    }
}

// a whole report from the test generator, through the parser with a state of its own (so it
// never mixes with a real report half received from the UART)
void ch_frame(const uint8_t *f, int n) {
    int st = ch_state;
    uint8_t cmd = ch_cmd, len = ch_len, idx = ch_idx, buf[16];
    memcpy(buf, ch_buf, 16);
    ch_state = CH9350_STATE_IDLE;
    for (int i = 0; i < n; i++) ch_byte(f[i]);
    ch_state = st; ch_cmd = cmd; ch_len = len; ch_idx = idx;
    memcpy(ch_buf, buf, 16);
}

void uart_keyboard_poll(void) {
    // Process pending bytes in the UART receiver, but BOUNDED: a continuous RX
    // stream (e.g. noise on a repurposed/floating UART pin) must not spin here
    // forever, or the main loop never reaches the S2/F12 menu-key check and the
    // menu becomes unreachable. 64 bytes/call drains real CH9350 packets fine;
    // the state machine (ch_state) persists across calls.
    for (int _n = 0; _n < 64; _n++) {
        uint32_t val = reg_uart_data;
        if (val == 0xFFFFFFFF) {
            break;
        }
        uint8_t b = val & 0xFF;
        ch_raw[ch_raw_i++ & 63] = b;
        ch_byte(b);
    }

    // Safety timeout: if no keyboard packet received for 1 second, clear keys
    if (last_kbd_time != 0 && (time_millis() - last_kbd_time) > 1000) {
        kv_set0(0);
        apply_input_options();
        last_kbd_time = 0;
    }
}

void backup_process(void) {
    // Stub to satisfy picorv32 dependency
}
