# cc816 - our own C compiler for Horizon (Atari816), feasibility spike.
#
#   make                 HELLO.PRG, CWIN.PRG, CBENCH.PRG in build/
#   make run-hello       run them in emu816 (sdk/tools/run816.py), output in build/run-*
#   make run-window
#   make run-bench
#   make check           the regression set (tests/check.sh): the three programs, the
#                        c-testsuite if CTS=<checkout> is given, 600 random programs
#   make sdk             compile (not run) every C file of the vbcc-based SDK (sdk/c)
#   make cts CTS=dir     the c-testsuite (git clone https://github.com/c-testsuite/c-testsuite)
#
# Needs only Python 3 and ca65/ld65/ar65 (cc65). The compiler is cc816.py (no build step);
# pycparser and pcpp are vendored in vendor/ (BSD licences).

CC      := python3 cc816.py
B       := build
RUN     := tests/run.sh

all: $(B)/HELLO.PRG $(B)/CWIN.PRG $(B)/CBENCH.PRG

$(B)/HELLO.PRG: tests/hello/hello.c | $(B)
	$(CC) $< -o $@
$(B)/CWIN.PRG: tests/window/window.c | $(B)
	$(CC) $< -o $@
$(B)/CBENCH.PRG: tests/bench/bench_hz.c tests/bench/bench.c | $(B)
	$(CC) $^ -o $@ -m $(B)/CBENCH.map

$(B):
	mkdir -p $@

run-hello: $(B)/HELLO.PRG
	$(RUN) hello $< --mode shell --args 'one "two words" three' --seconds 3 \
	    --expect '&local passed: 42 (42)  local array: 6 (6)  global: 100 (100)' \
	    --expect 'sum 124716 (124716)' --expect 'ok'
run-window: $(B)/CWIN.PRG
	$(RUN) window $< --script tests/window/test.script --expect 'CWIN: closed'
run-bench: $(B)/CBENCH.PRG
	$(RUN) bench $< --mode shell --seconds 40 --expect 'bench done' \
	    --expect 'check 1899' --expect 'check 27824' --expect 'check 1071602483' \
	    --expect 'check 17711' --expect 'check 3160' --expect 'check 4275534039'

check:
	tests/check.sh
sdk:
	python3 tests/sdkcompile.py
cts:
	python3 tests/conform/conform.py --out $(B)/cts $(CTS)/tests/single-exec/*.c

clean:
	rm -rf $(B)

.PHONY: all run-hello run-window run-bench check sdk cts clean
