# Echo

A small TCP client for Horizon 0.22 (Atari816): it connects to `tcp://host:port`, sends one
line, waits for the answer, prints it and closes the connection.

```
> echo tcp://192.168.1.20:7007 "Hello there"
echo: connected to tcp://192.168.1.20:7007
sent: Hello there
answer: Hello there
```

- The first argument is the address, the second (optional) the text to send
  (default: `Hello from the Atari816`). Quote text with spaces.
- `open` makes the connection (it waits until connected or failed). After that `read` and
  `write` **never wait**: `write` takes what fits and returns the count (perhaps 0: try
  again a little later), `read` gives what has come (0 = nothing yet) and fails with
  `E_CLOSED` once the other end has closed.
- Echo has no window, so it **polls**: it reads, and when nothing has come it sleeps 10 ms
  and reads again. It gives up after 5 s. A window program would wait for the `WE_NET`
  event instead.
- The connection is made by the PC (the gateway, `tools/atari816-link`). The Atari816 can
  reach whatever the PC can reach, on the internet or the home network. `tls://host:port`
  works the same way, with TLS done by the PC.
- Every error has its own message (`refused or unreachable`, `name not found`, ...).

## Build, run, test

```
make                     # ECHO.PRG
make run                 # against an echo server on this PC; screenshot in build/run/
make test                # two runs, below
make clean
```

`echoserver.py` is a small echo server (every line comes back unchanged). Run it alone
(`python3 echoserver.py`, port 7007) to try Echo on the real machine. `make test` uses
`echoserver.py --run` to serve on a free port while the emulator runs with `--net` (its
`tcp://` connections are real connections of the PC):

1. `echo tcp://127.0.0.1:PORT "Hello there"`: `answer: Hello there` must be on the console.
2. `echo tcp://127.0.0.1:1` (nobody listens): `echo: refused or unreachable`.

See `docs/reference/internet.md` for the rules.
