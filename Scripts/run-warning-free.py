#!/usr/bin/env python3
"""Stream a build command and fail on diagnostics even when the tool exits zero."""
import importlib.util
import os
import signal
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
    try:
        command = validation.apple_silicon_command(sys.argv[1:])
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 64
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
    diagnostics = []
    for line in process.stdout:
        print(line, end="", flush=True)
        diagnostics.extend(validation.diagnostic_lines(line))
        if validation.intel_build_line(line) and process.poll() is None:
            # Stop only this command's process group, including compiler children.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    code = process.wait()
    if diagnostics:
        print(f"Rejected {len(diagnostics)} build diagnostic(s).", file=sys.stderr)
    return code if code else int(bool(diagnostics))


if __name__ == "__main__":
    sys.exit(main())
