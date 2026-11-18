# Atari816: the PC link (step 1)

Nov 18, 2026 (step 3: printing)

The PC link connects the Atari816 to a PC (or a Raspberry Pi) through the board's USB cable.
A small program on the PC, the **gateway** (`tools/atari816-link`), shares one folder of the PC
with the Atari816, gives it the time, and lets the developer tools reach the board. Later
steps add the internet (step 2) and printing and a bridge for the classic Atari (step 3) on the
same link.

This document is the protocol. It is meant to be enough to write a second gateway.

## The pieces

```
65C816 (Horizon) --mailbox--> I/O processor (PicoRV32 firmware) --serial--> BL616 --USB--> PC (gateway)
                                     |                                                    |
                                     SD card                                  the shared folder,
                                                                              the tools' socket
```

- The **firmware** (`core/firmware/pclink.c`, `firmware.c`) ends the protocol on the board. It
  shows the shared folder to the 65C816 as a second volume, `/PC:`, through the normal file
  operations of the mailbox (`02-register-spec.md`, "I/O processor mailbox").
- The **gateway** (`tools/atari816-link`, `tools/pclink.py`) ends it on the PC.
- The **developer tools** (`core/tools/atari.py`) send their requests through the gateway when
  it runs (a Unix socket), or open the serial port themselves when it does not.

## Physical layer

| Item | Value |
| --- | --- |
| Port | The second serial port of the board's USB pair (the BL616 shows two FT2232-style ports: 0 is JTAG, 1 is the UART) |
| Rate | **1,500,000 baud**, 8 data bits, no parity, 1 stop bit, no flow control |
| On the board | Receive: 27 MHz / 18, a 2048-byte FIFO in block RAM. Send: 27 MHz / 18 |

The rate is fixed: the firmware uses it from the moment it starts, and a gateway opens the port
at it. No baud rate is negotiated.

Measured on the board (`03-bringup1-log.md`, step 21): the wire is error-free in both directions at
1, 1.5, 2 and 3 Mbaud. Board to PC, the BL616 forwards at most about 83 KB/s whatever the
rate; a burst longer than about 50 KB at a higher rate loses bytes in the BL616. The link's
frames are at most 1,051 bytes and the board waits for an acknowledgement after each, so this never happens.
PC to board, the firmware's receive loop takes about 100 to 150 KB/s. 1.5 Mbaud is the fastest
rate that is exact on both sides (27 MHz / 18 here, 12 MHz / 8 in the BL616's FT2232 model)
with a margin of a factor of two in bit time to the highest rate tested.

## Frames

All multi-byte numbers are little-endian.

| Offset | Size | Field | Meaning |
| --- | --- | --- | --- |
| 0 | 1 | SOF0 | $A8 |
| 1 | 1 | SOF1 | $16 |
| 2 | 2 | LEN | Payload length, 0 to 1040 |
| 4 | 1 | CHAN | Channel, 0 to 15 |
| 5 | 1 | SEQ | Sequence number of a DATA frame (1 to 255), else 0 |
| 6 | 1 | ACK | With the ACK flag: the SEQ acknowledged (same channel, other direction) |
| 7 | 1 | FLAGS | Bit 0 DATA, bit 1 ACK; the other bits are 0 |
| 8 | 1 | HCHK | Low byte of the CRC of bytes 2 to 7 |
| 9 | LEN | Payload | |
| 9 + LEN | 2 | CRC | CRC of bytes 2 to 8 + LEN (header, HCHK and payload) |

The CRC is CRC-16/CCITT-FALSE: polynomial $1021, initial value $FFFF, no reflection, no final
XOR (Python: `binascii.crc_hqx(data, 0xFFFF)`; check value for "123456789": $29B1).

**Kinds of frames.**

- **DATA** (flag DATA): a payload that must arrive exactly once and in order. The receiver
  answers with an ACK.
- **ACK** (flag ACK, LEN 0): acknowledges the DATA frame SEQ = ACK of the same channel. Any
  frame may carry the ACK flag; both implementations send plain ACK frames.
- **Datagram** (no flag, LEN > 0): delivered at most once, never acknowledged. Used for the
  control channel and the log.

**Receiving.** Look for SOF0 SOF1. Read the 7 header bytes; if HCHK is wrong, LEN is above
1040 or CHAN above 15, it is not a frame: go on searching from the byte after SOF0. Read the
payload and the CRC; if the CRC is wrong, go on searching from the byte after SOF0. The board
also forgets a half-received frame after 100 ms without a byte. A receiver must accept a
frame that comes right after garbage.

## Reliability

Every channel has, in each direction, its own sequence of DATA frames: SEQ runs 1, 2, ... 255,
1, ... (0 is never used). The counters start again from 0 (the first frame is 1) when a session
starts.

- **Sender:** at most **two** unacknowledged DATA frames per channel and direction. If no ACK
  comes within 250 ms for the oldest one, send it and every frame after it again (the same
  SEQs: "go back N"). An ACK also acknowledges every frame before it (it is cumulative).
  - The board sends one frame at a time and waits for its ACK (stop and wait). It tries 14
    times (3.5 s), then ends the session.
  - The gateway sends the frames of a long PC volume response two at a time, everything else
    one at a time. It keeps trying, every 250 ms and then up to every second, as long as the
    session lives (frames come from the board), and gives up a frame after 60 s: the board
    may hold back an ACK on purpose (below).
- **Receiver:** a DATA frame is taken only if its SEQ is the next one (the last one taken + 1,
  after 255 comes 1): deliver it, remember SEQ, send the ACK. With SEQ equal to the last one
  taken (its ACK was lost): send the ACK again, do not deliver it again. Any other SEQ (a
  frame before it was lost): drop it, no ACK; the sender goes back.
- The board sends an ACK as soon as it accepts a frame. While the firmware is busy waiting for
  the PC (a PC volume request in progress), it keeps one developer frame and acknowledges it;
  a second one gets no ACK until the first is done (the PC sends it again). The frame kept is
  always served before any later developer frame (step 3: before, a later frame could overtake
  it when it arrived just as the firmware became free, and a SINK test lost 1 KB).
- Different channels never wait for each other.

## Sessions (channel 0)

Channel 0 carries only datagrams. Their first payload byte is an op.

| Op | Name | Direction | Payload after the op |
| --- | --- | --- | --- |
| $01 | HELLO | PC to board | u8 protocol version (1), u32 nonce, u32 time, u8 services, the gateway's name (ASCII, up to 32 bytes) |
| $02 | HELLO_ACK | board to PC | u8 protocol version (1), u32 nonce (copied), u16 largest payload (1040), the firmware's name (ASCII) |
| $03 | PING | PC to board | u32 nonce |
| $04 | PONG | board to PC | u32 nonce (copied) |
| $05 | BYE | either | none: the sender leaves; the session ends |
| $06 | NOSESSION | board to PC | none: a DATA frame or a PING came, but there is no session |
| $07 | BOOT | board to PC | none: the firmware has just started |

- **time**: the PC's local time in seconds since 2000-01-01 00:00 (the clock the Atari816
  uses; no time zone, no daylight saving: it is the PC's wall clock).
- **services**: bit 0 FILES (the PC serves the PC volume, channel 2), bit 1 DEV (the PC may
  send developer requests, channel 3), bit 2 NET (the PC makes TCP connections, channel 4),
  bit 3 FETCH (the PC fetches URLs, channel 5), bit 4 PRINT (step 3: the PC turns print jobs
  into PDF files, "Printing" below). A gateway started with `--no-net` leaves bits 2 and 3
  clear.

**Starting.** The PC sends HELLO (a new random nonce each time) once a second until a
HELLO_ACK with its nonce comes back. The session is up. A HELLO always starts a new session
on the board, also when one is running: the board forgets every sequence number and every
file of the old session (its open PC files become stale, below).

**Keeping it.** While the session is up the PC sends PING once a second, and the board answers
PONG. A side that hears nothing from the other for 3.5 s ends the session; the PC then sends
HELLO again once a second.

**Ending.** BYE ends it at once (the gateway sends it when it stops). After the board starts
(power, reset, a new bitstream) it sends BOOT, and NOSESSION to anything but a HELLO: the PC
sends HELLO at once.

**Old frames.** When the PC opens the port, the BL616 may deliver bytes it kept from before
(frames of an old session, log lines). They are skipped: nothing is accepted before the
HELLO_ACK with the right nonce.

**Without a PC** the firmware works exactly as it would without a link: nothing waits for the
PC at start, and PC volume requests answer "no PC link" at once.

## Channels

| Channel | Name | Who asks | Status |
| --- | --- | --- | --- |
| 0 | Control | | Sessions (above) |
| 1 | Log | | The firmware's log: datagrams, board to PC, one line of text each (no newline) |
| 2 | Files | the board | The PC volume (below) |
| 3 | Developer | the PC | The developer tools (below) |
| 4 | Net | the board | Step 2: outgoing TCP connections (below) |
| 5 | Fetch | the board | Step 2: fetch a URL: HTTP, HTTPS, FTP (below) |
| 6 | | | Reserved (step 3 needed no channel: printing goes through channel 2) |
| 7 | | | Reserved (step 3: the classic Atari talks only to the board, never to the PC) |
| 8-15 | | | Reserved |

A receiver acknowledges DATA frames on a channel it does not know, and drops them.

### Requests and responses (channels 2 and 3)

Every DATA payload on these channels starts with a 4-byte header:

| Byte | Field | Meaning |
| --- | --- | --- |
| 0 | OP | The operation; in a response OP + $80 |
| 1 | TAG | Chosen by the side that asks (1-255), copied into the response |
| 2 | FLAGS | Bit 0 MORE: more frames of this request (or response) follow |
| 3 | RESULT | Response: 0 OK, or an error code (the last frame has it). Request: 0 |

A request may take several frames (the same OP and TAG; MORE set on all but the last). A
response may too; the receiver joins the data of its frames (everything after the header):
that is the **response stream**. One request at a time per channel and direction.

## Channel 2: the PC volume

The board asks, the gateway answers. Paths are relative to the shared folder, begin with `/`
(`/` is the folder itself), use `/` between parts, and end with a zero byte. Names are bytes
(UTF-8 on the PC). Numbers are little-endian.

| Op | Name | Request data | Response stream |
| --- | --- | --- | --- |
| $01 | OPEN | u8 mode, 3 x 0, path | u8 handle, 3 x 0, u32 size |
| $02 | CLOSE | u8 handle, 3 x 0 | none |
| $03 | READ | u8 handle, 3 x 0, u32 length | the bytes read (fewer at the end of the file) |
| $04 | WRITE | u8 handle, 3 x 0, then the bytes; one frame per 1024 bytes, each with the 4 bytes first | u32 bytes written |
| $05 | SEEK | u8 handle, 3 x 0, u32 position | u32 new position |
| $06 | STAT | path | u32 size, u8 attributes, 3 x 0, u32 FAT time |
| $07 | READDIR | u16 skip, u16 room, path | u32 count, then the entries |
| $08 | MKDIR | path | none |
| $09 | DELETE | path (a file, or an empty folder) | none |
| $0A | RENAME | old path, new path (each zero-terminated) | none |
| $10 | LOAD | path | the whole file (at most 16 MB) |

- **mode**: 0 read; 1 read and write, the file must exist; 2 create (or empty it), read and
  write; 3 append: write, created if missing, the position at its end.
- **attributes**: $10 folder; else $01 read-only or $20.
- **FAT time**: date << 16 | time, as FAT stores them: bits 25-31 year - 1980, 21-24 month,
  16-20 day, 11-15 hour, 5-10 minute, 0-4 seconds / 2. Local time of the PC.
- **READDIR**: entries `u32 size, u8 attributes, u8 name length, name` (no terminator), in
  name order (not caring about case), without `.`, `..` and names starting with `.`. `skip`
  entries are left out first; entries are added while their total stays within `room` bytes;
  `count` says how many.
- **Names** are found ignoring case when the exact name is not there; new files get the case
  given.
- **Results** are FatFs codes, as the card's: 0 OK, 1 other error, 4 no file, 5 no path, 6
  invalid name, 7 denied, 8 exists, 18 too many open files, $80 bad handle, $82 unknown op.
- **Safety** (the gateway): nothing outside the shared folder is ever opened, listed, created,
  renamed or deleted. `.` and `..` parts and names starting with `.` are refused (6). Anything
  whose real path (links followed) is outside the folder is refused (7); files are opened
  without following a link in the last part. `--read-only` refuses every change (7). A
  session has at most 16 open files; all are closed when the session ends.
- **Unfinished files**: a file opened with mode 2 is written under a temporary name in the
  hidden folder `.atari816-partial` (at the top of the shared folder). At CLOSE the gateway
  moves it onto its real name in one step. Until then nothing changes under that name: an
  old file stays as it was. If the session ends with the file still open (the copy was
  cancelled, the cable came out, the board was reset, the gateway was stopped), the
  temporary file is deleted and an old file of that name is left as it was. If the gateway
  crashed or was killed (SIGKILL, power cut), the next gateway deletes what is left in
  `.atari816-partial` when it starts. Modes 1 and 3 write in place: a cut-off update or
  append stays as far as it got (and mode 3 may leave a new file it created).

### What the 65C816 sees

The firmware turns the mailbox ops into these requests (`02-register-spec.md`, "Operations").

- A path whose first four characters are `/PC:` (any case), followed by the end or `/`, is on
  the PC volume; the rest is the path sent to the gateway. `:` cannot be in a FAT name, so no
  card folder is hidden by it.
- OPEN, CLOSE, READ, WRITE, SEEK, STAT, READDIR, MKDIR, DELETE, RENAME and LOAD work on it;
  the 4 mailbox handles are shared by both volumes.
- READDIR of `/` (the card's root) lists one more folder at the end, `PC:`, while a gateway
  with the files service is connected.
- STAT of `/PC:` itself answers at once (no request): a folder, as its time the PC's clock now
  (the time from HELLO, counted on; Horizon sets its clock from it), and (step 3) as its size
  the services of HELLO (before step 3: 0).
- New mailbox results: **$87** no PC link (no gateway, or one without the files service:
  answered at once), **$88** PC link lost (the session ended during the request, or a handle
  of an ended session; CLOSE of such a handle frees it and answers 0), **$89** RENAME between
  the card and the PC volume (copy, then delete).
- CLASSIC_MOUNT of a `/PC:` path answers $87 or $82 (not in step 1). SYS_SYNC closes the PC
  files too.
- A request with no answer from the gateway for 30 s answers $88.
- The PC's time from HELLO also dates the files the firmware writes on the card, until Horizon
  gives its time again (SYS_TIME).

## Channel 3: the developer channel

The PC asks (through the gateway, or a tool on its own), the board answers. Payload header as
above.

| Op | Name | Request data | Response stream |
| --- | --- | --- | --- |
| $01 | INFO | none | One text line: the firmware's state and the link counters |
| $02 | PUT | frame 1: u32 size, path on the card; then frames of u32 offset + data (MORE on all but the last) | none; RESULT after the last frame |
| $03 | RESTART816 | [u8 1 = start /A816.BIN, not /SYSTEM/HORIZON.SYS] | none |
| $04 | RUN | path of a .xex on the card (step 3: or of a BASIC program, .BAS or .LST: as "Run in Atari") | none (mounted and cold booted after the answer) |
| $05 | COLD | none | none (the classic machine is cold booted) |
| $06 | WARM | none | none (warm start) |
| $07 | EJECT | none | none (the virtual .xex disk is ejected) |
| $08 | KEY | u8 modifiers (bit 0 Ctrl, bit 1 Shift), u8 HID usage, u8 hold time in 10 ms | none |
| $09 | MOUSE | s8 dx, s8 dy, s8 wheel, u8 buttons | none (a MOUSE event for Horizon) |
| $0A | (TYPE) | | Removed (step 2, to free block RAM): answers $82 |
| $0B | PEEK | u16 address, u16 length (up to 1024) | classic machine memory |
| $0C | POKE | u16 address, bytes | none |
| $0D | FWPEEK | u32 address, u16 length (up to 1024) | the I/O processor's memory |
| $0E | PEEK816 | u32 address, u16 width, u16 rows, u32 stride, u8 flags | the data, then u16 sum of the raw bytes |
| $0F | ECHO | bytes | the same bytes |
| $10 | SOURCE | u32 length | length bytes, byte i = i & $FF (speed test) |
| $11 | SINK | frames of bytes (MORE) | u32 bytes received (speed test) |
| $12 | INJECT | u16 keys, u16 key period (ms), u16 mouse reports, u8 mouse period (ms) | none (a board test, below) |

- PUT creates the folders on the way, refuses a file the firmware has open (a mounted disk
  image, the cartridge image) with 7, and deletes a file whose transfer failed. The offsets
  must follow each other.
- PEEK816 reads 65C816 memory as the CPU sees it, `rows` rows of `width` bytes, `stride` apart.
  Flags: bit 0 RLE (a header byte h: 0-127 = h + 1 bytes follow as they are; 128-255 = the
  next byte repeated h - 125 times, 3 to 130), bit 1 XOR2 (from the third byte of each row a
  byte is sent XORed with the raw byte two before it; applied before RLE), bit 2 only the sum.
- INJECT starts the firmware's input generator: `keys` key taps (a press, then its release
  half a period later; the letters A to Z in turn) and `mouse reports` of dx = +1, one each
  period. They enter where the keyboard's and the mouse's reports enter, and only as often
  as the firmware looks at its keyboard input: reports that would not have fitted in the
  keyboard UART's 64-byte receive FIFO since the last look are counted as lost, as they
  would be on the wire. INFO shows the reports made and lost (`ksent`, `klost`: a press and a release are two; `msent`, `mlost`), the
  longest time in microseconds between two looks (`gap`) and the events sent to Horizon
  (`ev`); INFO starts `gap` and `ev` again. `core/tools/intest.py` with
  `sw/a816/INTEST.BIN` uses it.
- Results: 0, FatFs codes, $82 unknown op, $83 bad arguments.
- Requests are served by the firmware's main loop; while it serves a PC volume request
  they wait.

## Channels 4 and 5: the internet (step 2)

The PC makes the Atari816's connections for it: **Net** (channel 4) is outgoing TCP, with TLS
on the PC if asked; **Fetch** (channel 5) gets a URL (`http://`, `https://`, `ftp://`) and
streams its body. The PC does the name lookup, TLS and its certificates, HTTP redirects and the
FTP dialogue; the board sees only bytes. **Programs on the Atari816 can reach whatever the PC
can reach, including the home network.** The gateway connects outwards only: it never listens.

Both channels carry **streams**. They are not request / response channels: either side sends
DATA frames whenever it has something to say, all with the same 4-byte payload header:

| Byte | Field | Meaning |
| --- | --- | --- |
| 0 | OP | Below |
| 1 | SID | The stream (1-255), chosen by the board at OPEN; the PC keeps one table per channel |
| 2 | FLAGS | 0 |
| 3 | RESULT | 0, or an error code (OPENED, END) |

**Board to PC**

| Op | Name | Data |
| --- | --- | --- |
| $01 | OPEN | u16 window (the bytes the board can take before it gives more credit), then Net: u16 port, u8 flags (bit 0 TLS), host (zero-terminated, at most 100 bytes); Fetch: u16 0, the URL (zero-terminated, at most 255 bytes) |
| $02 | SEND | (Net) 1 to 1024 bytes for the connection, never more than the send credit |
| $03 | CREDIT | u16: the board takes that many bytes more |
| $04 | CLOSE | none: the PC closes the stream and forgets the SID; it sends nothing more for it |

**PC to board**

| Op | Name | Data |
| --- | --- | --- |
| $81 | OPENED | RESULT 0 or an error. u32 size (Fetch: Content-Length or the FTP SIZE when known, else $FFFFFFFF; Net: $FFFFFFFF), u16 status (HTTP: the final status, also on an HTTP error; else 0), u16 send credit (Net: the bytes the board may SEND; Fetch: 0). After an error nothing more comes for the SID |
| $82 | DATA | 1 to 1024 bytes of the stream. The PC never sends more than the credit: the window of OPEN plus every CREDIT, minus the bytes sent so far |
| $83 | SCREDIT | (Net) u16: the board may SEND that many bytes more |
| $84 | END | RESULT 0: the end of the stream (Fetch: the whole body; Net: the other end closed), else an error. Nothing more comes for the SID; the PC has closed it |

- A SID is any number 1-255 the board does not use at that moment. OPEN with a SID still open
  on the PC first closes the old stream there. The board ignores frames for a SID it does not
  know (they can cross a CLOSE).
- The board gives credit back (CREDIT) as its programs read; it never grows the window beyond
  what it can hold, so it is never flooded. The firmware keeps 4 KB per stream and gives credit
  in steps of 1 KB.
- When the session ends every stream ends on both sides (the PC closes its sockets).
- At most 8 streams per channel on the PC; one more is refused with $92.

**Results** (RESULT of OPENED and END; the board passes them on as mailbox results, below)

| Code | Meaning |
| --- | --- |
| $8A | No such service: the gateway does not offer it (an older gateway, or `--no-net`). The board answers this itself |
| $8B | Bad address: a URL or host the PC cannot use, an unknown scheme, a port of 0 |
| $8C | Name not found (DNS) |
| $8D | Refused or unreachable (connection refused, no route, FTP login refused, FTP file not found) |
| $8E | Timeout |
| $8F | HTTP status 400 or more (the status is in OPENED) |
| $90 | (board only) The connection was closed: reading after END 0 of a Net stream, or writing after it |
| $91 | TLS failed (certificate not valid for the name, handshake failed) |
| $92 | Too many streams on the PC |
| $93 | Other network error (the connection was reset, a broken HTTP answer, ...) |

**The gateway's rules.**

- Fetch: name lookup, connection, TLS and the answer's headers must take less than 20 s in
  all, and the body may pause at most 30 s ($8E). Up to 5 redirects (HTTP 301, 302, 303, 307,
  308). Certificates are checked against the system's store. The request has only `Host`,
  `User-Agent: Atari816-link/1`, `Accept: */*`, `Accept-Encoding: identity`,
  `Connection: close`: nothing about the user or the PC.
- FTP (Fetch): `ftp://[user[:password]@]host[:port]/path`, passive mode, binary; anonymous
  when no user is given. Size from SIZE when the server answers it. A URL that ends with `/`
  gives the folder's listing as text, one entry per line (`name`, or with MLSD
  `name<TAB>size<TAB>YYYY-MM-DD HH:MM`, folders ending in `/`), lines ending in LF. Read only.
  Passwords are never written to the gateway's output.
- Net: name lookup and connection (and TLS) within 15 s ($8E); then no time limit: an idle
  connection stays open. The send credit starts at 4 KB; the gateway gives more (SCREDIT) as
  it hands the bytes to the socket. Small sends go out at once (TCP_NODELAY), for interactive
  use.
- `--no-net` switches both services off (HELLO without bits 2 and 3).

### What the 65C816 sees (step 2)

A **URL is a path**: the normal file operations of the mailbox take it. The scheme (any case)
picks the service; `:` cannot be in a FAT name, so no card name is hidden by it. The whole
path must fit in 127 bytes (Horizon's path limit).

| Path | Service |
| --- | --- |
| `http://...`, `https://...`, `ftp://...` | Fetch: a read-only file |
| `tcp://host:port`, `tls://host:port` | Net: a connection (port 1-65535; `tls://` = TLS on the PC) |

- **Handles.** The firmware has 4 more mailbox handles for streams, **4 to 7** (0 to 3 stay the
  files'), so a connection never takes a file's handle.
- **A URL (Fetch).** OPEN (mode 0; other modes: 7 denied) answers when the server has answered
  (or failed); STAT answers the same way: size = the size if known, else 0; attributes $21
  (a read-only file); time = the PC's clock now. A STAT and then an OPEN of the same URL within
  15 s make one request to the PC (the STAT's stream is kept for the OPEN). READ answers when
  LEN bytes have come or the stream ended: fewer than LEN = the end, as with a file. WRITE: 7.
  SEEK: $82. MKDIR, DELETE, RENAME: 7. READDIR, LOAD, CLASSIC_MOUNT: $82.
- **A connection (Net).** OPEN answers when it is connected or failed (at most 20 s). READ
  never waits: it gives the bytes that have come (up to LEN; 0 = none yet); after the other end
  closed and every byte was read it answers $90. WRITE never waits: it takes as many bytes as
  the send credit allows (perhaps 0: try again later) and answers that count; after the end:
  $90. SEEK, STAT: $82.
- **Waiting.** Whenever something new happens on a connection (bytes came, it ended, it
  failed) and its program has read from it since the last time, the firmware sends the event
  **$E4 NET** (ARG0 = the handle). Horizon turns it into a window event.
- **Waiting requests do not stop the I/O processor.** An OPEN, a STAT or a READ that waits for
  the internet is put aside: the request ring moves on and its answer comes later (answers are
  matched by TAG). Other programs' file requests go on meanwhile, and keys and the mouse keep
  coming. If no answer comes from the PC within 40 s the request answers $8E.
- **Results** as above, and: $87 no PC link; $88 the link was lost (during the request, or on
  a handle of an ended session; CLOSE frees it and answers 0); $8A no such service; 18 too many
  streams (all four handles in use). In an answer with $8F, ARG1 is the HTTP status.
- CLOSE sends CLOSE to the PC and frees the handle. SYS_SYNC and a 65C816 restart close every
  stream.

## Printing (step 3)

Printing needs no channel of its own: a print job reaches the PC as a file of the PC volume
(channel 2), and the gateway turns it into a PDF. The PC keeps only the PDF.

- The board writes the job (OPEN mode 2, WRITE, CLOSE) as `/Printouts/NAME.pdf`: in the folder
  `Printouts` at the top of the shared folder (any case), the name ending in `.pdf`. Horizon's
  program PRINTD does this (`horizon/ABI.md`, "Printing"), only when HELLO had bit 4 (PRINT).
- The file starts with a marker, then a small header, then the text:

  ```
  1B "A816PRINT 1" 0A        (13 bytes)
  title=TEXT 0A              the job's name (the program, "Atari", ...)
  date=YYYY-MM-DD HH:MM 0A   when it was printed
  0A                         the end of the header
  the text                   Latin-1; LF or CR LF line ends; FF ($0C) starts a new page
  ```

- At CLOSE (before the unfinished file gets its name, "Unfinished files" above) a gateway with
  the PRINT service replaces such a file's content by a PDF: A4, the built-in Courier font at
  10 points (80 columns, 58 lines a page), margins of 2 cm, a header line on every page (the
  title, the date, "Page n of m"); long lines are wrapped, a tab goes to the next multiple of 8,
  a form feed starts a new page, characters Courier cannot show become `?`
  (`tools/pdfprint.py`, only the Python standard library). Files without the marker, and marked
  files elsewhere, are kept as written.
- A gateway without the service (before step 3) would keep the marked text under the `.pdf`
  name; Horizon therefore sends jobs only when HELLO had bit 4 (STAT of `/PC:` tells it).

## The gateway

`tools/atari816-link [FOLDER] [--port P] [--read-only] [--no-net] [--log FILE] [-v]`

- Shares FOLDER (default `~/Atari816`, created if missing). Only the Python standard library
  and pyserial.
- Gives the Atari816 the internet (channels 4 and 5) unless started with `--no-net`.
  Programs on the Atari816 can reach whatever the PC can reach, including the home network.
  `-v` writes every connection and URL opened and how it ended (never a password).
- Finds the port by itself (the second port of a pair with the same USB VID:PID), and keeps
  trying when the board is not there, is unplugged or reset: it reopens the port and starts a
  new session.
- Opens **no network port**. For the tools it listens on a Unix socket,
  `$XDG_RUNTIME_DIR/atari816-link.sock` (else `/tmp/atari816-<uid>/`), readable only by the
  user. Messages there: u32 length (type and data), u8 type, data. Types: `R` (tool to gateway)
  one frame payload of a developer request; `P` (gateway to tool) one frame payload of the
  response; `S` send me the log; `L` one log line; `E` the request failed (text); `I` the link
  state. One tool's request at a time; the gateway passes the frames on unchanged.
- Stop it before loading a bitstream with openFPGALoader (both use the board's USB).

