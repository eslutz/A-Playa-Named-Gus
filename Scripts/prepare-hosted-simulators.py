#!/usr/bin/env python3
"""Remove only unavailable, shut-down device stubs on GitHub-hosted runners."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def device_inventory(raw):
    inventory = json.loads(raw)
    if not isinstance(inventory, dict) or not isinstance(inventory.get("devices"), dict):
        raise ValueError("Simulator inventory must contain a devices object")
    devices = {}
    for runtime, entries in inventory["devices"].items():
        if not isinstance(runtime, str) or not runtime or not isinstance(entries, list):
            raise ValueError("Malformed simulator runtime/device list")
        for device in entries:
            if not isinstance(device, dict):
                raise ValueError("Malformed simulator device")
            identifier = device.get("udid")
            if not isinstance(identifier, str) or not re.fullmatch(
                r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", identifier
            ):
                raise ValueError("Simulator device has an invalid UUID")
            identifier = identifier.upper()
            if identifier in devices:
                raise ValueError("Simulator inventory contains a duplicate UUID")
            if type(device.get("isAvailable")) is not bool:
                raise ValueError("Simulator availability must be a Boolean")
            if not isinstance(device.get("state"), str) or not device["state"]:
                raise ValueError("Simulator state is missing or malformed")
            devices[identifier] = device
    return devices


def simctl(arguments, directory, stem):
    command = ["xcrun", "simctl", *arguments]
    print("Running: " + " ".join(command), flush=True)
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired as error:
        def text(value):
            return value.decode(errors="replace") if isinstance(value, bytes) else (value or "")
        result = subprocess.CompletedProcess(command, 124, text(error.stdout), text(error.stderr))
    (directory / f"{stem}.stdout.txt").write_text(result.stdout)
    (directory / f"{stem}.stderr.txt").write_text(result.stderr)
    # Keep tool diagnostics visible to the existing warning-free wrapper.
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr, flush=True)
    if arguments[0] != "list" or result.returncode:
        print(result.stdout, end="", flush=True)
    if result.returncode:
        raise RuntimeError(f"simctl {arguments[0]} failed with exit {result.returncode}")
    return result.stdout


def prepare(environ):
    if environ.get("GITHUB_ACTIONS") != "true" or environ.get("GUS_RUNNER_ENVIRONMENT") != "github-hosted":
        raise RuntimeError("Simulator cleanup requires GitHub Actions on a github-hosted runner")
    temporary = Path(environ.get("RUNNER_TEMP", ""))
    if not temporary.is_absolute() or not temporary.is_dir():
        raise RuntimeError("RUNNER_TEMP must be an existing absolute directory")
    directory = Path(tempfile.mkdtemp(prefix="gus-simulator-inventory-", dir=temporary))
    print(f"Simulator inventory evidence: {directory}", flush=True)
    before_raw = simctl(["list", "--json"], directory, "before")
    (directory / "before.json").write_text(before_raw)
    print("Simulator inventory before cleanup:\n" + before_raw, flush=True)
    before = device_inventory(before_raw)
    selected = sorted(identifier for identifier, device in before.items()
                      if device["isAvailable"] is False and device["state"] == "Shutdown")
    (directory / "selected.json").write_text(json.dumps(selected, indent=2) + "\n")
    for number, identifier in enumerate(selected, 1):
        simctl(["delete", identifier], directory, f"delete-{number:03d}")
    after_raw = simctl(["list", "--json"], directory, "after")
    (directory / "after.json").write_text(after_raw)
    print("Simulator inventory after cleanup:\n" + after_raw, flush=True)
    after = device_inventory(after_raw)
    if set(after) != set(before) - set(selected):
        raise RuntimeError("Post-cleanup inventory does not match exactly the selected UUID removals")
    result = {"deletedDeviceIDs": selected, "beforeCount": len(before), "afterCount": len(after)}
    (directory / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"Verified removal of {len(selected)} unavailable, shut-down simulator device(s).", flush=True)
    return directory


def main():
    try:
        prepare(os.environ)
    except (OSError, ValueError, RuntimeError) as error:
        print(f"Hosted simulator preparation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
