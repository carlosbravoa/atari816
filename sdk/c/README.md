# The Horizon C SDK

C for the Atari816 and Horizon, on the vbcc 65816 compiler.

```
sdk/c/tools/get-toolchain.sh          # once: download and install vbcc (Linux x86-64)
sdk/c/bin/hcc -o HELLO.PRG hello.c    # a Horizon program from C, in one command
make -C sdk/c test                    # the SDK's tests in the emulator
```

| | |
| --- | --- |
| [bin/hcc](bin/hcc) | the driver: compile, link (three times), make the o65 program; sizes checked |
| [c.mk](c.mk) | make rules: a program's Makefile is `NAME := x`, `SDK ?= ...`, `include $(SDK)/c/c.mk` |
| [include/horizon.h](include/horizon.h) | every syscall as a C function (`hzsys.h`, generated), the parameter blocks, the helpers; [include/dirent.h](include/dirent.h) |
| [lib/](lib), [rt/](rt), [fastrt/](fastrt) | the C library on Horizon (stdio with files, argv, time, far memory, errno), the startup and linker scripts, the tuned runtime |
| [tools/](tools) | `get-toolchain.sh`, `gensys.py` (hzsys.h from horizon.inc / ABI.md / `syscalls.tab`), `mko65.py`, `hzc.py` |
| [examples/](examples) | `hello`, `window` (raw window calls), `wc` (a file tool): `make`, `make run`, `make test` |
| [tests/](tests) | `run.py`: libc, syscalls, compiler faults, float, stack, benchmark, runtime tables |
| docs | [getting started](../docs/c/getting-started.md), [reference](../docs/c/reference.md), [porting](../docs/c/porting.md) |

vbcc is free for non-commercial use and may be redistributed only unmodified: it is
downloaded, not included. Template: [../templates/c-console](../templates/c-console).
