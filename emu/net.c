/* The internet through the PC link (step 2): what the 65C816 sees through the mailbox
 * (Docs/04-pc-link.md, "65C816 interface for the internet").
 *
 * - A path that starts with letters and "://" is a URL. http://, https://, ftp:// are the Fetch
 *   service (--net-root DIR: scheme://host[:port]/path is served from the host file
 *   DIR/host/path; a folder gives a listing, "name\n" per entry). tcp://host:port is the Net
 *   service (--net: a real host TCP socket, connected asynchronously); tls:// answers $91.
 * - Streams take the handles 4-7, apart from the files' 0-3.
 * - An OPEN or STAT of a URL, and a READ of a URL that waits for its data, are put aside: the
 *   request ring moves on and the answer comes later (matched by TAG). READ and WRITE on a
 *   connection never wait.
 * - $E4 NET (ARG0 = the handle) when something new happens on a connection (bytes, its end, an
 *   error) and its program has read from it since the last event (or since OPEN).
 * - The link drops (--pc-drop-at) end every stream: $88.
 * While a connection is open (or connecting), emulated time is kept from running ahead of the
 * host's clock, so a remote program answers within the emulated time it would on the board.
 */
#include "machine.h"
#include "net.h"
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

int         mailbox_net;
const char *mailbox_net_root;
double      mailbox_net_delay;

enum { NR_OK = 0, NR_DENIED = 7, NR_TOO_MANY = 18, NR_BAD_HANDLE = 0x80, NR_BAD_RAM = 0x81, NR_UNSUPPORTED = 0x82,
       NR_NO_PC = 0x87, NR_LOST = 0x88, NR_NO_SERVICE = 0x8A, NR_BAD_URL = 0x8B, NR_NO_NAME = 0x8C,
       NR_REFUSED = 0x8D, NR_TIMEOUT = 0x8E, NR_HTTP = 0x8F, NR_CLOSED = 0x90, NR_TLS = 0x91, NR_OTHER = 0x93 };

#define RXMAX     4096              /* the firmware keeps 4 KB per stream */
#define TXMAX     4096              /* the gateway's first send credit */
#define NPEND     16
#define FETCH_MAX (64u << 20)
#define CONNECT_S 15.0              /* Net: name lookup and connection (host seconds) */
#define KEEP_S    15.0              /* a STAT's stream is kept this long for an OPEN */

enum { K_FETCH = 1, K_TCP = 2 };
enum { S_NONE, S_HTTP, S_FTP, S_TCP, S_TLS };

typedef struct {
    int      used, kind, ready, dead;
    uint8_t  sess;
    /* Fetch: the whole body, the read position, the bytes arrived so far */
    uint8_t *data;
    uint32_t size, pos;
    double   arrived;
    uint64_t last;
    /* Net */
    int      fd, conn_res, last_err;    /* conn_res: -1 connecting, 0 connected, else the result */
    struct addrinfo *ai, *cur;
    double   t_conn;
    uint8_t  rx[RXMAX], tx[TXMAX];
    uint32_t rxn, txn;
    int      eof, err, armed, evp;
} Stream;

typedef struct {
    int      used, fixed, h, has_out;
    uint8_t  msg[16], sess;
    uint64_t due;
    uint32_t res, val;
} Pend;

static Stream st[NET_HANDLES];
static Pend   pend[NPEND];
static struct { int valid; uint8_t sess; char url[128]; uint64_t t; } kept;
static int    anchored;
static double a_host, a_emu;

static double host_sec(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

int net_is_url(const char *p)
{
    int i = 0;
    while (isalpha((unsigned char)p[i])) i++;
    return i > 0 && !strncmp(p + i, "://", 3);
}

static int scheme(const char *p)
{
    size_t n = strcspn(p, ":");
    if (n == 4 && !strncasecmp(p, "http", 4)) return S_HTTP;
    if (n == 5 && !strncasecmp(p, "https", 5)) return S_HTTP;
    if (n == 3 && !strncasecmp(p, "ftp", 3)) return S_FTP;
    if (n == 3 && !strncasecmp(p, "tcp", 3)) return S_TCP;
    if (n == 3 && !strncasecmp(p, "tls", 3)) return S_TLS;
    return S_NONE;
}

static void stream_free(int h)
{
    Stream *s = &st[h];
    if (!s->used) return;
    if (s->fd >= 0) close(s->fd);
    if (s->ai) freeaddrinfo(s->ai);
    free(s->data);
    memset(s, 0, sizeof *s);
    s->fd = -1;
}

static int stream_alloc(int kind)
{
    for (int h = 0; h < NET_HANDLES; h++)
        if (!st[h].used) {
            memset(&st[h], 0, sizeof st[h]);
            st[h].used = 1;
            st[h].kind = kind;
            st[h].fd = -1;
            st[h].conn_res = -1;
            st[h].sess = mbx_link_session();
            return h;
        }
    return -1;
}

/* the time the PC takes to answer an OPEN or STAT: --net-delay, + 6 ms with --pc-kbps */
static uint64_t open_delay(void)
{
    double ms = mailbox_net_delay;
    if (mailbox_pc_kbps[0] || mailbox_pc_kbps[1]) ms += 6.0;
    return (uint64_t)(ms * CPU_HZ / 1000.0);
}

static Pend *pend_add(const uint8_t *msg, int h, uint64_t due, int fixed, uint32_t res, uint32_t val)
{
    for (int i = 0; i < NPEND; i++)
        if (!pend[i].used) {
            Pend *p = &pend[i];
            memset(p, 0, sizeof *p);
            p->used = 1; p->fixed = fixed; p->h = h; p->due = due; p->res = res; p->val = val;
            p->sess = mbx_link_session();
            memcpy(p->msg, msg, 16);
            return p;
        }
    return NULL;
}

static void put_answer(uint8_t *out, const uint8_t *msg, uint32_t res, uint32_t val)
{
    memcpy(out, msg, 16);
    out[0] |= 0x80;
    out[8] = res; out[9] = res >> 8; out[10] = res >> 16; out[11] = res >> 24;
    out[12] = val; out[13] = val >> 8; out[14] = val >> 16; out[15] = val >> 24;
}

/* ── Fetch: a URL served from --net-root ── */
static int unhex(int c) { return isdigit(c) ? c - '0' : isxdigit(c) ? (tolower(c) - 'a' + 10) : -1; }

static int pct_decode(const char *in, size_t n, char *out, size_t on)
{
    size_t o = 0;
    for (size_t i = 0; i < n; i++) {
        int c = (unsigned char)in[i];
        if (c == '%' && i + 2 < n && unhex(in[i + 1]) >= 0 && unhex(in[i + 2]) >= 0) {
            c = unhex(in[i + 1]) << 4 | unhex(in[i + 2]);
            i += 2;
            if (!c) return 1;
        }
        if (o + 1 >= on) return 1;
        out[o++] = c;
    }
    out[o] = 0;
    return 0;
}

static int cmpstr(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }

/* the body of a URL: 0 and *data / *size, or a result (*status: the HTTP status for $8F) */
static int fetch_load(const char *url, int ftp, uint8_t **data, uint32_t *size, uint32_t *status)
{
    *data = NULL; *size = 0; *status = 0;
    const char *a = strstr(url, "://") + 3;
    size_t al = strcspn(a, "/?#");
    char auth[128];
    if (al >= sizeof auth) return NR_BAD_URL;
    memcpy(auth, a, al);
    auth[al] = 0;
    char *host = strrchr(auth, '@');                   /* (user[:password]@) */
    host = host ? host + 1 : auth;
    if (*host == '[') {                                 /* [IPv6]: a name with ':' is no folder */
        char *e = strchr(host, ']');
        if (!e) return NR_BAD_URL;
        e[1] = 0;
    } else {
        char *c = strchr(host, ':');                    /* the port is ignored */
        if (c) *c = 0;
    }
    if (!*host) return NR_BAD_URL;
    const char *p = a + al;
    char path[256];
    if (pct_decode(p, strcspn(p, "?#"), path, sizeof path)) return NR_BAD_URL;
    if (!path[0]) strcpy(path, "/");
    int want_dir = path[strlen(path) - 1] == '/';

    char fat[512], hp[4096];
    struct stat sb;
    snprintf(fat, sizeof fat, "/%s", host);
    if (mbx_resolve_in(mailbox_net_root, fat, hp, sizeof hp) || stat(hp, &sb) || !S_ISDIR(sb.st_mode))
        return NR_NO_NAME;                               /* no such host */
    snprintf(fat, sizeof fat, "/%s%s", host, path);
    int nf = 0;
    if (mbx_resolve_in(mailbox_net_root, fat, hp, sizeof hp) || stat(hp, &sb)) nf = 1;
    else if (S_ISDIR(sb.st_mode)) {                     /* the folder's listing */
        DIR *d = opendir(hp);
        if (!d) return NR_OTHER;
        char **names = NULL;
        size_t nn = 0, cap = 0, total = 0;
        struct dirent *de;
        while ((de = readdir(d))) {
            if (de->d_name[0] == '.') continue;
            if (nn == cap) names = realloc(names, (cap = cap ? 2 * cap : 64) * sizeof *names);
            names[nn++] = strdup(de->d_name);
            total += strlen(de->d_name) + 1;
        }
        closedir(d);
        if (nn) qsort(names, nn, sizeof *names, cmpstr);
        uint8_t *b = malloc(total + 1);
        size_t o = 0;
        for (size_t i = 0; i < nn; i++) {
            size_t l = strlen(names[i]);
            memcpy(b + o, names[i], l);
            b[o + l] = '\n';
            o += l + 1;
            free(names[i]);
        }
        free(names);
        *data = b; *size = (uint32_t)o;
        return NR_OK;
    } else if (want_dir || !S_ISREG(sb.st_mode)) nf = 1;
    else {
        if ((uint64_t)sb.st_size > FETCH_MAX) return NR_OTHER;
        FILE *f = fopen(hp, "rb");
        if (!f) nf = 1;
        else {
            uint8_t *b = malloc(sb.st_size + 1);
            size_t got = fread(b, 1, sb.st_size, f);
            fclose(f);
            *data = b; *size = (uint32_t)got;
            return NR_OK;
        }
    }
    if (nf && ftp) return NR_REFUSED;                    /* FTP: file not found */
    *status = 404;
    return NR_HTTP;
}

/* ── Net: tcp://host:port ── */
static int tcp_parse(const char *url, char *host, size_t hn, char *port)
{
    const char *a = strstr(url, "://") + 3, *e;
    if (*a == '[') { a++; e = strchr(a, ']'); if (!e) return 1; }
    else e = a + strcspn(a, ":/");
    size_t l = e - a;
    if (!l || l > 100 || l >= hn) return 1;
    memcpy(host, a, l);
    host[l] = 0;
    if (*e == ']') e++;
    if (*e != ':') return 1;
    e++;
    unsigned v = 0;
    int nd = 0;
    while (isdigit((unsigned char)*e) && nd < 6) v = v * 10 + (*e++ - '0'), nd++;
    if (!nd || v < 1 || v > 65535) return 1;
    if (*e == '/') e++;
    if (*e) return 1;
    sprintf(port, "%u", v);
    return 0;
}

static int errno_net(int e)
{
    switch (e) {
    case ECONNREFUSED: case ENETUNREACH: case EHOSTUNREACH: case EADDRNOTAVAIL: case ENETDOWN: return NR_REFUSED;
    case ETIMEDOUT: return NR_TIMEOUT;
    }
    return NR_OTHER;
}

/* start connecting to the current address, or the next ones; conn_res set when done or failed */
static void tcp_try(Stream *s)
{
    for (; s->cur; s->cur = s->cur->ai_next) {
        int fd = socket(s->cur->ai_family, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
        if (fd < 0) { s->last_err = errno; continue; }
        int one = 1;
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
        if (!connect(fd, s->cur->ai_addr, s->cur->ai_addrlen)) { s->fd = fd; s->conn_res = 0; return; }
        if (errno == EINPROGRESS) { s->fd = fd; return; }
        s->last_err = errno;
        close(fd);
    }
    s->conn_res = errno_net(s->last_err);
}

/* ── completing a request put aside: 1 and its answer in out (the Pend freed) ── */
static int try_complete(Pend *p, uint64_t now, uint8_t *out)
{
    if (now < p->due) return 0;
    uint8_t op = p->msg[0];
    uint32_t len = p->msg[2] | p->msg[3] << 8, buf = p->msg[4] | p->msg[5] << 8 | p->msg[6] << 16;
    if (!p->fixed) {
        Stream *s = &st[p->h];
        if (op == 0x01) {                               /* OPEN tcp: connected or failed */
            if (s->conn_res == -1) return 0;
            p->res = s->conn_res;
            if (p->res) { p->val = 0; stream_free(p->h); }
            else {
                p->val = NET_H0 + p->h;
                s->ready = 1;
                s->armed = 1;
                if (s->rxn || s->eof || s->err) { s->evp = 1; s->armed = 0; }
            }
        } else {                                        /* READ of a URL: LEN bytes, or the end */
            uint32_t need = s->pos + len > s->size ? s->size : s->pos + len;
            if (s->arrived < need) return 0;
            uint32_t n = need - s->pos;
            if (n && !mbx_put(buf, s->data + s->pos, n)) { p->res = NR_BAD_RAM; p->val = 0; }
            else { s->pos += n; p->res = 0; p->val = n; }
        }
    } else if (op == 0x01 && p->h >= 0) {               /* OPEN of a URL, answered */
        if (p->res) stream_free(p->h);
        else st[p->h].ready = 1;
    } else if (op == 0x06 && p->has_out && !p->res) {   /* STAT: size, $21, the PC's clock now */
        uint32_t t = mbx_pc_fat_now(), sz = p->val;
        uint8_t o[9] = { sz, sz >> 8, sz >> 16, sz >> 24, 0x21, t, t >> 8, t >> 16, t >> 24 };
        if (!mbx_put(buf, o, 9)) { p->res = NR_BAD_RAM; }
    }
    put_answer(out, p->msg, p->res, p->val);
    p->used = 0;
    return 1;
}

/* a request put aside, or answered now when it is already due */
static int defer(uint8_t *msg, Pend *p, uint64_t now)
{
    if (!p) { put_answer(msg, msg, NR_OTHER, 0); return 1; }
    if (try_complete(p, now, msg)) return 1;
    return 2;
}

/* ── requests on a URL path ── */
static int url_op(uint8_t *msg, const char *path, uint64_t now)
{
    uint8_t op = msg[0];
    int sc = scheme(path);
    uint32_t res = 0;
    if (!mbx_link_up()) res = NR_NO_PC;
    else if (op == 0x07 || op == 0x10 || op == 0x18) res = NR_UNSUPPORTED;   /* READDIR, LOAD, CLASSIC_MOUNT */
    else if (op == 0x08 || op == 0x09 || op == 0x0A) res = NR_DENIED;        /* MKDIR, DELETE, RENAME */
    else if (sc == S_NONE) res = NR_BAD_URL;
    else if ((sc == S_HTTP || sc == S_FTP) ? !mailbox_net_root : !mailbox_net) res = NR_NO_SERVICE;
    else if (op == 0x06) {                                                  /* STAT */
        if (sc == S_TCP || sc == S_TLS) res = NR_UNSUPPORTED;
        else {
            uint8_t *d;
            uint32_t sz, status;
            int r = fetch_load(path, sc == S_FTP, &d, &sz, &status);
            free(d);
            uint64_t due = now + open_delay();
            Pend *p = pend_add(msg, -1, due, 1, r, r ? status : sz);
            if (p) p->has_out = 1;
            if (!r) {                                   /* kept for an OPEN of the same URL */
                kept.valid = 1;
                kept.sess = mbx_link_session();
                kept.t = due;
                snprintf(kept.url, sizeof kept.url, "%s", path);
            }
            return defer(msg, p, now);
        }
    } else if (sc == S_TLS) res = NR_TLS;                                    /* (TLS is not modelled) */
    else if (sc == S_TCP) {                                                 /* OPEN tcp://host:port */
        char host[128], port[8];
        if (tcp_parse(path, host, sizeof host, port)) res = NR_BAD_URL;
        else {
            int h = stream_alloc(K_TCP);
            if (h < 0) res = NR_TOO_MANY;
            else {
                struct addrinfo hints = { .ai_family = AF_UNSPEC, .ai_socktype = SOCK_STREAM }, *ai;
                if (getaddrinfo(host, port, &hints, &ai)) { stream_free(h); res = NR_NO_NAME; }
                else {
                    Stream *s = &st[h];
                    s->ai = s->cur = ai;
                    s->t_conn = host_sec();
                    tcp_try(s);
                    return defer(msg, pend_add(msg, h, now + open_delay(), 0, 0, 0), now);
                }
            }
        }
    } else {                                                                /* OPEN of a URL (Fetch) */
        if (msg[7]) res = NR_DENIED;                     /* read only: mode 0 */
        else {
            int h = stream_alloc(K_FETCH);
            if (h < 0) res = NR_TOO_MANY;
            else {
                Stream *s = &st[h];
                int reuse = kept.valid && kept.sess == mbx_link_session() && !strcmp(kept.url, path)
                            && now >= kept.t && now - kept.t <= (uint64_t)(KEEP_S * CPU_HZ);
                uint64_t due = reuse ? now : now + open_delay();
                uint32_t status;
                int r = fetch_load(path, sc == S_FTP, &s->data, &s->size, &status);
                if (reuse) kept.valid = 0;
                s->last = reuse ? kept.t : due;          /* the body comes from when the server answered */
                Pend *p = pend_add(msg, h, due, 1, r, r ? status : (uint32_t)(NET_H0 + h));
                if (!p) stream_free(h);
                return defer(msg, p, now);
            }
        }
    }
    put_answer(msg, msg, res, 0);
    return 1;
}

/* ── requests on a stream handle (4-7) ── */
static int handle_op(uint8_t *msg, int h, uint64_t now)
{
    Stream *s = &st[h];
    uint8_t op = msg[0];
    uint32_t len = msg[2] | msg[3] << 8, buf = msg[4] | msg[5] << 8 | msg[6] << 16;
    uint32_t res = 0, val = 0;
    if (!s->used || !s->ready) res = NR_BAD_HANDLE;
    else if (op == 0x02) {                              /* CLOSE: requests still waiting on it end */
        for (int i = 0; i < NPEND; i++)
            if (pend[i].used && pend[i].h == h) { pend[i].fixed = 1; pend[i].res = NR_BAD_HANDLE; pend[i].val = 0; pend[i].h = -1; pend[i].due = now; }
        stream_free(h);
    } else if (op == 0x05) res = NR_UNSUPPORTED;         /* SEEK */
    else if (s->dead) res = NR_LOST;
    else if (s->kind == K_FETCH) {
        if (op == 0x04) res = NR_DENIED;
        else if (len) return defer(msg, pend_add(msg, h, now, 0, 0, 0), now);
    } else if (op == 0x03) {                            /* READ tcp: what has come, never waits */
        s->armed = 1;
        uint32_t n = len < s->rxn ? len : s->rxn;
        if (n) {
            if (!mbx_put(buf, s->rx, n)) res = NR_BAD_RAM;
            else { memmove(s->rx, s->rx + n, s->rxn - n); s->rxn -= n; val = n; }
        } else if (s->err) res = s->err;
        else if (s->eof) res = NR_CLOSED;
    } else {                                            /* WRITE tcp: as much as the credit takes */
        if (s->err) res = s->err;
        else if (s->eof) res = NR_CLOSED;
        else {
            uint32_t n = TXMAX - s->txn;
            if (n > len) n = len;
            if (n && !mbx_get(buf, s->tx + s->txn, n)) res = NR_BAD_RAM;
            else {
                s->txn += n;
                val = n;
                if (s->txn && s->fd >= 0) {
                    ssize_t w = send(s->fd, s->tx, s->txn, MSG_NOSIGNAL);
                    if (w > 0) { memmove(s->tx, s->tx + w, s->txn - w); s->txn -= w; }
                }
            }
        }
    }
    put_answer(msg, msg, res, val);
    return 1;
}

int net_take(uint8_t *msg, uint64_t now)
{
    static char path[128], to[128];
    uint8_t op = msg[0];
    uint32_t buf = msg[4] | msg[5] << 8 | msg[6] << 16;
    uint32_t arg0 = msg[8] | msg[9] << 8 | msg[10] << 16 | (uint32_t)msg[11] << 24;
    switch (op) {
    case 0x02: case 0x03: case 0x04: case 0x05:
        if (arg0 < NET_H0 || arg0 >= NET_H0 + NET_HANDLES) return 0;
        return handle_op(msg, arg0 - NET_H0, now);
    case 0x01: case 0x06: case 0x07: case 0x08: case 0x09: case 0x0A: case 0x10: case 0x18:
        if (!mbx_path(buf, path, sizeof path)) return 0;
        if (!net_is_url(path)) {
            if (op != 0x0A || !mbx_path(buf + strlen(path) + 1, to, sizeof to) || !net_is_url(to)) return 0;
        }
        return url_op(msg, path, now);
    }
    return 0;
}

/* ── the link dropped: every stream of the old session ends ── */
static void kill_stream(int h)
{
    Stream *s = &st[h];
    s->dead = 1;
    if (s->fd >= 0) { close(s->fd); s->fd = -1; }
    free(s->data);
    s->data = NULL;
    s->size = s->pos = 0;
    s->rxn = s->txn = 0;
    if (s->kind == K_TCP && s->ready) s->evp = 1;       /* the program learns it at once */
}

void net_tick(uint64_t now)
{
    if (!mailbox_net && !mailbox_net_root) return;     /* no stream can exist */
    int up = mbx_link_up();
    uint8_t ses = mbx_link_session();
    for (int h = 0; h < NET_HANDLES; h++)
        if (st[h].used && !st[h].dead && (!up || st[h].sess != ses)) kill_stream(h);
    for (int i = 0; i < NPEND; i++) {
        Pend *p = &pend[i];
        if (p->used && (!up || p->sess != ses) && !(p->fixed && p->res == NR_LOST)) {
            p->fixed = 1; p->res = NR_LOST; p->val = 0; p->due = now;
            if (p->msg[0] != 0x01) p->h = -1;           /* (an OPEN still frees its handle) */
        }
    }
    if (kept.valid && (!up || kept.sess != ses)) kept.valid = 0;

    /* connections: wait for them, as far as emulated time is ahead of the host's */
    struct pollfd pf[NET_HANDLES];
    int idx[NET_HANDLES], np = 0;
    for (int h = 0; h < NET_HANDLES; h++) {
        Stream *s = &st[h];
        if (!s->used || s->kind != K_TCP || s->fd < 0) continue;
        pf[np].fd = s->fd;
        pf[np].events = s->conn_res == -1 ? POLLOUT : (short)((s->rxn < RXMAX ? POLLIN : 0) | (s->txn ? POLLOUT : 0));
        pf[np].revents = 0;
        idx[np++] = h;
    }
    if (!np) { anchored = 0; }
    else {
        double hs = host_sec(), es = now / CPU_HZ;
        if (!anchored) { anchored = 1; a_host = hs; a_emu = es; }
        double ahead = (es - a_emu) - (hs - a_host);
        int ms = ahead > 0 ? (int)(ahead * 1000.0) : 0;
        if (ms > 50) ms = 50;
        poll(pf, np, ms);
    }
    for (int k = 0; k < np; k++) {
        Stream *s = &st[idx[k]];
        if (s->conn_res == -1) {
            if (pf[k].revents) {
                int e = 0;
                socklen_t el = sizeof e;
                getsockopt(s->fd, SOL_SOCKET, SO_ERROR, &e, &el);
                if (!e) s->conn_res = 0;
                else {
                    close(s->fd); s->fd = -1;
                    s->last_err = e;
                    s->cur = s->cur ? s->cur->ai_next : NULL;
                    tcp_try(s);
                }
            } else if (host_sec() - s->t_conn > CONNECT_S) {
                close(s->fd); s->fd = -1;
                s->conn_res = NR_TIMEOUT;
            }
            continue;
        }
        int news = 0;
        while (s->rxn < RXMAX) {
            ssize_t r = recv(s->fd, s->rx + s->rxn, RXMAX - s->rxn, 0);
            if (r > 0) { s->rxn += r; news = 1; continue; }
            if (r == 0) { s->eof = 1; news = 1; }
            else if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) { s->err = NR_OTHER; news = 1; }
            break;
        }
        if (s->txn && !s->eof && !s->err) {
            ssize_t w = send(s->fd, s->tx, s->txn, MSG_NOSIGNAL);
            if (w > 0) { memmove(s->tx, s->tx + w, s->txn - w); s->txn -= w; }
            else if (w < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) { s->err = NR_OTHER; news = 1; }
        }
        if (s->eof || s->err) { close(s->fd); s->fd = -1; s->txn = 0; }
        if (news && s->ready && s->armed) { s->evp = 1; s->armed = 0; }
    }

    /* Fetch bodies arrive at the --pc-kbps read rate (else at once); while no READ waits the
     * firmware's 4 KB buffer limits what comes */
    double rate = mailbox_pc_kbps[0] * 1024.0;
    for (int h = 0; h < NET_HANDLES; h++) {
        Stream *s = &st[h];
        if (!s->used || s->kind != K_FETCH || !s->ready || s->dead) continue;
        int waiting = 0;
        for (int i = 0; i < NPEND; i++) if (pend[i].used && !pend[i].fixed && pend[i].h == h) waiting = 1;
        double cap = waiting ? s->size : (s->pos + (double)RXMAX < s->size ? s->pos + (double)RXMAX : s->size);
        if (rate <= 0) s->arrived = cap;
        else if (now > s->last) s->arrived += (now - s->last) / CPU_HZ * rate;
        if (s->arrived > cap) s->arrived = cap;
        if (now > s->last) s->last = now;
    }
}

int net_output(uint8_t *e, uint64_t now)
{
    for (int i = 0; i < NPEND; i++)
        if (pend[i].used && try_complete(&pend[i], now, e)) return 1;
    for (int h = 0; h < NET_HANDLES; h++)
        if (st[h].used && st[h].evp) {
            st[h].evp = 0;
            memset(e, 0, 16);
            e[0] = 0xE4;
            e[8] = NET_H0 + h;
            return 1;
        }
    return 0;
}

void net_close_all(int answer)
{
    for (int i = 0; i < NPEND; i++) {
        if (!pend[i].used) continue;
        if (answer) { pend[i].fixed = 1; pend[i].res = NR_LOST; pend[i].val = 0; pend[i].h = -1; pend[i].due = 0; }
        else pend[i].used = 0;
    }
    for (int h = 0; h < NET_HANDLES; h++) stream_free(h);
    kept.valid = 0;
    anchored = 0;
}
