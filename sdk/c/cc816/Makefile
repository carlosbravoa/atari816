# cc816 - the Horizon C SDK's own C compiler (Python 3, emits ca65 assembly).
#
#   make check           the regression set (tests/check.py): the messages (tests/diag/*.c,
#                        tests/diag.py, no emulator), tests/regress/*.c, tests/lang/*.c,
#                        the random programs (fuzz/genfuzz.py, seeds 1, 2 and 3: 200 x seed
#                        programs; SEEDS=1,2 to change) and the random floating-point
#                        programs (100 x seed) in emu816, and the c-testsuite when
#                        CTS=<checkout> is given
#   make diag            the messages only (a few seconds)
#   make quick           the same with 50 random programs a seed (25 float ones)
#   make sdk             compile (not run) every C file of the SDK (tests/sdkcompile.py)
#   make clean
#
# A program: sdk/c/bin/hcc -o PROG.PRG main.c (hcc's default compiler is cc816).
# The compiler alone: python3 cc816.py [-S|-c|-E] [-O0|-O1|-O2] [-I dir] [-D name] [-U name]
#                     [-w|-Wall|-Werror|-Wno-NAME] [-fsigned-char] file.c
# Needs Python 3 and ca65/ld65/ar65 (cc65); pycparser and pcpp are vendored in vendor/
# (BSD licences). The runs need a built Horizon card (HORIZON, default ../../../horizon).

PYTHON ?= python3
CTS    ?=
SEEDS  ?= 1,2,3

check:
	$(PYTHON) tests/check.py --seeds $(SEEDS) $(if $(CTS),--cts $(CTS))
quick:
	$(PYTHON) tests/check.py --quick $(if $(CTS),--cts $(CTS))
diag:
	$(PYTHON) tests/diag.py
sdk:
	$(PYTHON) tests/sdkcompile.py
clean:
	rm -rf ../build/cc816

.PHONY: check quick diag sdk clean
