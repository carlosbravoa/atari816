# tools

The PC side of the Atari816's PC link (protocol: [`../Docs/04-pc-link.md`](../Docs/04-pc-link.md)).

- **`atari816-link`**: the gateway. Shares one folder of the PC with the Atari816 (the volume
  `/PC:` there), gives it the time and the internet (URLs and TCP connections, made by the PC;
  `--no-net` switches that off), and lets the developer tools reach the board while it runs.
  How to use it: the root [`README.md`](../README.md), "PC link".
- **`pclink.py`**: the protocol (frames, sessions, the shared folder, the developer channel,
  the internet), used by the gateway and by the developer tools in [`../core/tools/`](../core/tools/).

Needs Python 3 and pyserial (`pip install pyserial`).

Tests, without a board and without the internet (each takes a few seconds):

```
python3 tools/test_pclink.py     # frames, the parser, the shared folder's safety rules
python3 tools/test_netgw.py      # the internet: HTTP, HTTPS, FTP and TCP against servers on 127.0.0.1
python3 tools/test_pdfprint.py   # (step 3) print jobs as PDF files (uses pdftotext if installed)
```

`pdfprint.py` (step 3) turns the Atari816's print jobs into PDF files: a job the board writes to
`Printouts/NAME.pdf` in the shared folder, marked as a job, is a PDF on the PC (A4, Courier;
only the Python standard library).

A host test of the firmware's side of the protocol against this code is in
`../core/test/pclink_host/` (`./run_tests.py`).
