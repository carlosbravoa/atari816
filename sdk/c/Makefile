# The Horizon C SDK (vbcc 65816).
#
#   make            the C library for both memory models (build/lib/), if needed
#   make gen        include/hzsys.h again from horizon.inc, ABI.md, tools/syscalls.tab
#   make check      include/hzsys.h against horizon.inc and ABI.md (count, numbers, names)
#   make test       make check, then every test in the emulator (tests/run.py: PASS or
#                   FAIL per test and model), the examples and the c-console template
#   make clean
#
# The toolchain first: tools/get-toolchain.sh (docs/c/getting-started.md).
# HORIZON: the Horizon tree (default: the repository's); make test needs it built.

HORIZON ?= $(abspath ../../horizon)
export HORIZON
PYTHON  ?= python3
EXAMPLES := examples/hello examples/window examples/wc ../templates/c-console

all:
	$(PYTHON) bin/hcc --build-lib

gen:
	$(PYTHON) tools/gensys.py --horizon $(HORIZON)

check:
	$(PYTHON) tools/gensys.py --check --horizon $(HORIZON)

test: check
	$(PYTHON) tests/run.py --horizon $(HORIZON)
	@set -e; for p in $(EXAMPLES); do echo "== $$p"; \
	  $(MAKE) --no-print-directory -C $$p test HORIZON=$(HORIZON); done
	@echo "C SDK: ALL TESTS PASSED"

clean:
	rm -rf build
	@for p in $(EXAMPLES); do $(MAKE) --no-print-directory -C $$p clean; done

.PHONY: all gen check test clean
