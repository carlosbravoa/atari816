# PC Link tools

Talk to the Atari816 over the board's own USB-C. Since the PC link (Docs/04-pc-link.md) the
serial port carries framed packets; these tools send their requests on the link's developer
channel: through the gateway (`../../tools/atari816-link`) when it runs, so the PC volume
stays served meanwhile, or straight over the port when it does not.

- **`atari_link.py`**: the developer side (class `AtariLink`), on top of `../../tools/pclink.py`.
- **`atari.py`**: CLI: `ports` `ping` `log` `send` `run` `eject` `key` `reset`
  `status` `screen` `peek` `poke` `fwpeek`, and for the 65C816 `run816` `shot816` `peek816`;
  `hdmidiag [--watch S]`: the HDMI diagnostic counters (`../KNOWN_ISSUES.md`, "The picture
  is lost now and then").
- **`atari_gui.py`**: desktop app (Linux/Windows): send and run files, reset, log, printer output.
- **`a816_screen.py`**: the screenshot decoder that `shot816` uses.
- **`dotmatrix_pdf.py`**: turns printer output into a PDF (used by the app's Printer tab).
- **`intest.py`**: a small test of the link.

The old tools for removed firmware features (H:, R:, the modem, the network, typing text as
keys) are gone.

> Tools and firmware must come from the same release.

## Setup

```bash
pip install pyserial
sudo apt install python3-tk        # GUI only (Windows: included with python.org builds)
sudo modprobe ftdi_sio             # Linux, if no /dev/ttyUSB* appears
python3 tools/atari_gui.py         # or tools/atari.py <command>
```

Windows: the FTDI VCP driver arrives via Windows Update automatically; the tools
auto-pick the right COM port (the second of the board's port pair).

Packaging single-file executables: `pyinstaller --onefile tools/atari_gui.py`
(planned as a CI artifact per release).
