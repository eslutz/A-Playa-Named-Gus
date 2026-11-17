#!/usr/bin/env python3
"""Stream a build command and fail on diagnostics even when the tool exits zero."""
import importlib.util
import os
import re
import signal
from pathlib import Path
import subprocess
import sys

spec = importlib.util.spec_from_file_location("release_validation", Path(__file__).with_name("validate-release.py"))
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


FLAG = "--waive-ci-simulator-discovery"
HEADER = re.compile(r"^\d{4}-\d\d-\d\d [\d:.]+ xcodebuild\[\d+:\d+\] (?:\[MT\] )?DVTAssertions: Warning in DVTiOSFrameworks/IDEiOSSupportCore/DVTiPhoneSimulator\.m:661$")
DETAIL = re.compile(r"^Details:  SimDevice native architecture is nil\. Device: SimDevice : [^\n]+ runtime=\{ com\.apple\.CoreSimulator\.SimRuntime\.(?:iOS|tvOS|watchOS|xrOS)-[\d-]+: \(null\) \}, supportedArches: \($")


def waiver_context(command, environment):
    return (environment.get("GITHUB_ACTIONS") == "true"
            and environment.get("RUNNER_ENVIRONMENT") == "github-hosted"
            and bool(command) and command[0] == "xcodebuild"
            and any(action in command for action in ("build", "test", "-resolvePackageDependencies"))
            and not any(action in command for action in ("archive", "analyze", "-exportArchive", "-exportNotarizedApp"))
            and command.count("-destination") == 1
            and command[command.index("-destination") + 1:] != []
            and command[command.index("-destination") + 1] == "platform=macOS,arch=arm64"
            and not any("simulator" in arg.lower() for arg in command))


def waived_pair(header, detail):
    return bool(HEADER.fullmatch(header.rstrip("\n")) and DETAIL.fullmatch(detail.rstrip("\n")))


def main():
    if len(sys.argv) < 2:
        print("Usage: run-warning-free.py command [arguments...]", file=sys.stderr)
        return 64
    arguments = sys.argv[1:]
    waive = arguments[0] == FLAG
    if waive:
        arguments = arguments[1:]
        if not arguments or not waiver_context(arguments, os.environ):
            print("Simulator discovery waiver requires hosted native macOS xcodebuild.", file=sys.stderr)
            return 64
    try:
        command = validation.apple_silicon_command(arguments)
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 64
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
    diagnostics = []
    pending = None
    waived = 0
    for line in process.stdout:
        print(line, end="", flush=True)
        if pending is not None:
            if waived_pair(pending, line):
                waived += 1
                print("WAIVED CI simulator discovery diagnostic: DVTiPhoneSimulator.m:661 / nil SimDevice architecture", flush=True)
            else:
                diagnostics.extend(validation.diagnostic_lines(pending))
            pending = None
        if waive and HEADER.fullmatch(line.rstrip("\n")):
            pending = line
        else:
            diagnostics.extend(validation.diagnostic_lines(line))
        if validation.intel_build_line(line) and process.poll() is None:
            # Stop only this command's process group, including compiler children.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    if pending is not None:
        diagnostics.extend(validation.diagnostic_lines(pending))
    code = process.wait()
    if waive:
        print(f"CI simulator discovery waiver: {waived} occurrence(s); raw diagnostics retained.", flush=True)
    if diagnostics:
        print(f"Rejected {len(diagnostics)} build diagnostic(s).", file=sys.stderr)
    return code if code else int(bool(diagnostics))


if __name__ == "__main__":
    sys.exit(main())
