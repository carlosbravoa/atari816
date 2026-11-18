/* The internet through the PC link (step 2, Docs/04-pc-link.md "Channels 4 and 5"), as the
 * 65C816 sees it through the mailbox: URL paths, stream handles 4-7, deferred answers, $E4 NET.
 * Net (tcp://) uses real host sockets (--net); Fetch (http://, https://, ftp://) is served from
 * a host folder (--net-root). */
#ifndef NET_H
#define NET_H
#include <stdint.h>

#define NET_HANDLES 4               /* stream handles 4-7 */
#define NET_H0      4

extern int         mailbox_net;         /* --net: the Net service (tcp://) */
extern const char *mailbox_net_root;    /* --net-root DIR: the Fetch service (NULL: absent) */
extern double      mailbox_net_delay;   /* --net-delay MS: added to URL OPEN / STAT answers */

/* a request taken from the ring: 0 not a stream request (the files' code serves it);
 * 1 answered now (msg holds the answer); 2 put aside (its answer comes from net_output) */
int  net_take(uint8_t *msg, uint64_t now);
/* sockets, arrivals, link drops; keeps emulated time from running ahead of the host's while a
 * connection is open */
void net_tick(uint64_t now);
/* one deferred answer or $E4 event that is due: 1 and e filled, else 0 */
int  net_output(uint8_t *e, uint64_t now);
/* close every stream (sockets closed). answer = 1: requests put aside answer $88; 0: forgotten */
void net_close_all(int answer);
/* a path naming a URL: letters, then "://" */
int  net_is_url(const char *p);

/* helpers from mailbox.c */
int      mbx_get(uint32_t n, uint8_t *dst, uint32_t len);
int      mbx_put(uint32_t n, const uint8_t *src, uint32_t len);
int      mbx_path(uint32_t n, char *dst, int max);
int      mbx_link_up(void);
uint8_t  mbx_link_session(void);
uint32_t mbx_pc_fat_now(void);
int      mbx_resolve_in(const char *root, const char *fat, char *out, unsigned long n);

#endif
