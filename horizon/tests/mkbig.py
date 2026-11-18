#!/usr/bin/env python3
"""mkbig.py FILE SIZE - (0.21) a file of SIZE pseudo-random bytes (always the same ones), for
the tests of long copies (tests/pccopy.src, tests/cpstop.keys)."""
import random, sys
random.seed(816)
open(sys.argv[1], 'wb').write(random.randbytes(int(sys.argv[2])))
