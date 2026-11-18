#!/usr/bin/env python3
"""Run the shared Seerr fixture for the Apple TV remote tests with --port 5059."""

import runpy
from pathlib import Path


if __name__ == "__main__":
    runpy.run_path(str(Path(__file__).with_name("discover-fixture-server.py")), run_name="__main__")
