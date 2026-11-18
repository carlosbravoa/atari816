# tools

The PC side of the Atari816's PC link (protocol: [`../Docs/04-pc-link.md`](../Docs/04-pc-link.md)).

- **`atari816-link`**: the gateway. Shares one folder of the PC with the Atari816 (the volume
  `/PC:` there), gives it the time, and lets the developer tools reach the board while it runs.
  How to use it: the root [`README.md`](../README.md), "The PC link".
- **`pclink.py`**: the protocol (frames, sessions, the shared folder, the developer channel),
  used by the gateway and by the developer tools in [`../core/tools/`](../core/tools/).

Needs Python 3 and pyserial (`pip install pyserial`). A host test of the firmware's side of the
protocol against this code is in `../core/test/pclink_host/` (`./run_tests.py`).
