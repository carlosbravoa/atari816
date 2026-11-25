# Internet (Horizon 0.22)

The Atari816 reaches the internet through the **PC link**: the PC it is connected to by USB
runs the gateway, `tools/atari816-link`, and does the network work for it. There are no new
syscalls: **a URL is a path**, used with the normal file calls ([files.md](files.md)).

- **The gateway must run** on the PC (`tools/atari816-link`; see the repository's
  `Docs/04-pc-link.md`). Without a PC link every URL call fails with `E_NOLINK`. A gateway
  started with `--no-net` (or an older one) gives `E_NOSVC`.
- **Programs on the Atari816 can reach whatever the PC can reach, including the home
  network** (other computers, the router, a NAS). Keep that in mind before you run a
  program you do not trust.
- **127 characters.** The whole URL, with its scheme, must fit in 127 characters (Horizon's
  path limit; longer: `EINVAL`). The kernel passes a URL on as it is: no current folder is
  put in front of it and `.`, `..`, `//` are not touched.
- **Handles 4 to 7.** URLs and connections have their own four handles for the whole system,
  so they never take a file's handle (0-3). When all four are in use, open fails with
  `E_NSTREAM`. They are closed when the program ends.

## URLs as files: http://, https://, ftp://

These open as **read-only files**:

- open: mode 0 only (`O_READ`; another mode: $47 denied). Blocks until the server's
  response arrives or the request fails. Out: A = handle 4-7.
- stat: size: the size the server sent, else 0. Attribute $21 (a read-only file). Time:
  the PC's clock now.
- read: blocks until the requested length has arrived, or the end. **Fewer bytes than
  requested = the end**, as with a file.
- close: ends the request.
- seek: $C2 (not possible).
- write, delete, mkdir, rename: $47 (denied).
- readdir, spawn: $C2.

- An `ftp://` URL that ends with `/` reads as the folder's listing: text, one name per line.
- A stat and then an open of the same URL within 15 s make one request (the shell's `cp`
  and `get` do this: the size first, then the data).
- An HTTP error (status 400 or more) is `E_HTTP`; **open and stat then return the status in
  X** (404, 403, 500, ...).
- An open or read that blocks on the network does not delay other programs' file calls.

```asm
        ptr     url
        lda     #O_READ
        sys     SYS_OPEN        ; -> A = handle 4-7
        bcc     @ok
        cmp     #E_HTTP
        bne     @err            ; another error: see the table below
        txa                     ; X = the HTTP status (404 ...)
        jsr     put_dec
        rts
@ok:    sta     z:fh            ; then read until a short read, then close
@err:   rts
url:    .byte   "https://example.com/index.html", 0
```

The example [examples/fetch](../../examples/fetch) prints any URL on the console.

## Connections: tcp:// and tls://

`tcp://host:port` opens a TCP connection; `tls://host:port` the same with TLS (done by the
PC). The host is a name or an address; the port 1-65535.

- open: blocks until connected or failed (at most about 20 s). Out: A = handle 4-7. The
  mode is not used (pass 0).
- read: **never blocks.** Returns the bytes that have arrived, up to the requested
  length. A = 0: nothing yet. After the other end closed and every byte was read:
  `E_CLOSED`.
- write: **never blocks.** Accepts what fits and returns that count, perhaps 0: write
  the rest a little later. After the end: `E_CLOSED`.
- close: ends the connection.
- seek, stat: $C2.

There is no separate status call: the result of a read gives the status (bytes, 0, or an
error).

```asm
@again: ptr     iob             ; {u8 handle, u24 buffer, u16 length}
        sys     SYS_READ        ; -> A = bytes that had come
        bcs     @err            ; E_CLOSED: the other end closed
        cmp     #0              ; (a syscall does not set Z from A)
        bne     @got
        lda     #10             ; nothing yet: a program without windows sleeps a little
        sys     SYS_SLEEP
        bra     @again
@got:   rts
@err:   rts
```

The example [examples/echo](../../examples/echo) connects, sends a line and prints the
reply.

## WE_NET or polling

- **A window program** handles **`WE_NET` (17)** in its event loop. The event goes to the
  program's **first window** (the lowest window number it owns). `a` = a bit mask of the
  program's handles with activity (bit n = handle n: bit 4 for handle 4, ...). Activity
  is: bytes arrived, the connection ended, or it failed. Read the handle then, until a
  read returns 0.
- A handle gets a new `WE_NET` only after the program has read from it since the last one,
  so the queue never fills up with them.
- **A program without windows polls**: read, and if nothing arrived, sleep (10 ms is a
  good step) and read again. Count the steps to stop after a time-out of your own.

| Type | Value | a | b | c |
| --- | --- | --- | --- | --- |
| `WE_NET` | 17 | handles (4-7) with activity, bit mask | - | - |

```asm
        cmp     #WE_NET         ; (the event type, in a win_event loop)
        bne     @other
        lda     ev+2            ; a: the handles with news
        and     #$0010          ; handle 4?
        beq     @other
        ; read handle 4 until it gives 0 (or E_CLOSED)
@other: rts
```

## Errors

`horizon.inc` defines them. Open, stat, read and write can return any of them.

| Name | Code | Meaning |
| --- | --- | --- |
| `E_NOLINK` | $C7 | No PC link (the gateway is not running, or the cable is out) |
| `E_LOST` | $C8 | The PC link was lost |
| `E_NOSVC` | $CA | No such service (below) |
| `E_BADADDR` | $CB | Bad address (URL, host or port) |
| `E_NONAME` | $CC | Name not found (no such host) |
| `E_REFUSED` | $CD | Refused or unreachable (also an FTP login refused or a missing FTP file) |
| `E_TIMEOUT` | $CE | Timeout |
| `E_HTTP` | $CF | HTTP status 400 or more (status in X) |
| `E_CLOSED` | $D0 | The connection was closed (a read after the end, or a write) |
| `E_TLS` | $D1 | TLS failed (a bad certificate) |
| `E_PCBUSY` | $D2 | Too many connections on the PC |
| `E_NET` | $D3 | Another network error |
| `E_NSTREAM` | $52 | All four stream handles are in use |

`E_NOSVC`: an older gateway, or one started with `--no-net`. An older firmware returns
$46 (bad name) instead. `E_HTTP`: open and stat return the HTTP status in X.

## In the emulator

emu816 has the PC link's internet too (`tools/run816.py` passes these on):

- `--net`: `tcp://` URLs become real connections of the PC running the emulator (`tls://`
  returns `E_TLS`: TLS is not modelled).
- `--net-root DIR`: `http://host/path` (also `https://`, `ftp://`) is the file
  `DIR/host/path`; a folder gives its listing; a missing file is HTTP status 404; a missing
  host folder is `E_NONAME`.
- With only one of them, the other kind of URL gives `E_NOSVC`; with neither, `E_NOLINK`.
