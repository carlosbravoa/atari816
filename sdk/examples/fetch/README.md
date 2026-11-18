# Fetch

A console program for Horizon 0.22 (Atari816): it prints a web page, or any URL, on the
console. It shows that **a URL is a path**: the program opens it with the normal file
calls, exactly as it would open a file on the card.

```
> fetch http://example.com/
<!doctype html>
...
fetch: 1256 bytes
```

- The argument is the URL: `http://`, `https://` or `ftp://` (127 characters at most).
  A path on the card works too (`fetch /README.TXT`).
- `open` (mode 0) waits until the server has answered. Then `read` asks for 512 bytes at a
  time; a read that gives fewer bytes is the end. Then `close`.
- CR bytes are left out, so pages with CR LF line ends look right.
- Every error has its own message (the `E_*` names of `horizon.inc`). For an HTTP error
  (`E_HTTP`, status 400 or more) the failed `open` returns the status in X, and Fetch
  prints it: `fetch: HTTP status 404`.
- On the real machine the PC must run the gateway, `tools/atari816-link`, and the Atari816
  must be connected to it. Without it Fetch says `no PC link`; with a gateway started with
  `--no-net` it says `no internet service`.

## Build, run, test

```
make                     # FETCH.PRG
make run                 # fetches the test page in the emulator; screenshot in build/run/
make test                # three runs, below
make clean
```

The emulator has no real web: `--net-root DIR` serves `http://host/path` from the file
`DIR/host/path` (a missing file is HTTP status 404). The Makefile makes
`build/www/example.test/hello.txt`, 40 lines, 1080 bytes. `make test` runs:

1. `fetch http://example.test/hello.txt`: the first and last lines and `fetch: 1080 bytes`
   must be on the console (three reads: 512, 512 and a short one of 56).
2. `fetch http://example.test/missing.txt`: `fetch: HTTP status 404`.
3. The same with `--net` only (connections, but no web service): `fetch: no internet
   service` (E_NOSVC).

See `docs/reference/internet.md` for the rules.
