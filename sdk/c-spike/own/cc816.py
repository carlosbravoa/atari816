#!/usr/bin/env python3
"""cc816 - a C compiler for the Atari816 / Horizon (65C816), output ca65 assembly.
See cc816/driver.py for the options."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cc816.driver import main   # noqa: E402
sys.exit(main())
