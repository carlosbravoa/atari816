# SDK maintenance tools

Notes for maintainers of the SDK and its manual. This file is not part of the published
manual. The tools a programmer uses are documented in [../docs/tools.md](../docs/tools.md).

## Manual

- `mkmanual.py` builds the manual as a static site from the Markdown pages listed in its
  `MANIFEST` (labels and order of the sidebar). `python3 sdk/tools/mkmanual.py -o DIR
  --check` builds it and fails on any broken internal link or anchor. It also fails when a
  page holds a name from its `PRIVATE` list. `.github/workflows/pages.yml` builds and
  publishes the site. The stylesheet is `manual/style.css`.
- `doccheck.py` fails when a public function or macro of the SDK's headers, a public
  header, an option of `hcc`, `cc816.py`, `run816.py`, `hzapp.py`, `host16.py`,
  `inputscript.py` or `emu816`, or a tool of the SDK is named nowhere under `sdk/docs`,
  and when `sdk/docs/c/syscalls.md` is not what `hzsys.h` generates
  (`--write-syscalls` regenerates it). Maintenance tools (this file's) are exempt.
- `make -C sdk/c check` runs both (the site goes to `sdk/c/build/manual`).
- The coding-agent skill has the reverse check: every name, option and path it mentions
  must exist (`sdk/skill/atari-816-dev/examples/check.py`, run by `make -C sdk/c test`).

## Reference checks

- `abicheck.py` checks the assembly reference against the kernel's tables (115 syscalls,
  147 constants at Horizon 0.31).
- `snippets.py` assembles and links the reference's examples (149 in 17 files).
- `make -C sdk check` runs both. `make -C sdk test` runs them, then every template and
  example, then the C SDK's tests.

## Full verification run

Build from a fresh tree so that no stale object can make a test pass: copy the repository
without `.git` and without any `build` folder, build from nothing (`make -C emu`,
`make -C horizon`, `make -C sdk/c`), then run every suite listed in
`Docs/architecture/verification.md`. The ports that need game files take them from an
earlier tree's `data/` folders.

Reference run at release 0.31 (16-thread Linux PC, limited to 8 CPUs with `taskset`),
all suites passing, about 42 minutes in total:

- `make -C emu test`: 52 passed, 1 skipped (SingleStepTests sample not downloaded), 22 s.
- `make -C horizon test`: 175 passed, 168 s.
- `make -C sdk/c/cc816 check`: all pass in 3 configurations, 1,309 s. The c-testsuite was
  not run (no `CTS=` checkout).
- `make -C sdk test`: 318 PASS, 287 s.
- `make -C ports/digger test`: 19 passed, 140 s.
- `make -C ports/simcity test`: 10 passed, 152 s.
- `make -C ports/prince test`: 21 passed, 94 s.
- `make -C ports/xargon test`: 16 passed, 36 s.
- `make -C ports/xcom test JOBS=6`: 114 passed, 235 s.
- `make -C ports/skyroads check`: 1,708 of 1,708 frames, 58 s.

## Build tools not in the manual

- `sdk/c/tools/genrt.py`: generates the C runtime's assembly helpers.
- `sdk/c/tools/hzc816.py`: the compile step that `hcc` runs for each C file.
- `sdk/c/game/hgbuild.py`: builds the hgame library in its three configurations.
- `sdk/c/game/tools/mkfont.py`: converts hgame's built-in font.
