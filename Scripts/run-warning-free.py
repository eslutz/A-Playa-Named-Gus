#!/usr/bin/env python3
"""Stream a build command and fail on diagnostics even when the tool exits zero."""
import importlib.util
from pathlib import Path
import subprocess
import sys

spec = importlib.util.spec_from_file_location("release_validation", Path(__file__).with_name("validate-release.py"))
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


def main():
    if len(sys.argv) < 2:
        print("Usage: run-warning-free.py command [arguments...]", file=sys.stderr)
        return 64
    process = subprocess.Popen(sys.argv[1:], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    diagnostics = []
    for line in process.stdout:
        print(line, end="", flush=True)
        diagnostics.extend(validation.diagnostic_lines(line))
    code = process.wait()
    if diagnostics:
        print(f"Rejected {len(diagnostics)} build diagnostic(s).", file=sys.stderr)
    return code if code else int(bool(diagnostics))


if __name__ == "__main__":
    sys.exit(main())
