#!/usr/bin/env python3
"""Shim — use generate_test_fixtures.py for full TDD corpus."""

import subprocess
import sys
from pathlib import Path

if __name__ == "__main__":
    script = Path(__file__).resolve().parent / "generate_test_fixtures.py"
    sys.exit(subprocess.call([sys.executable, str(script)]))
