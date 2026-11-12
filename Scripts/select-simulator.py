#!/usr/bin/env python3
"""Pick an available tvOS test destination by UUID, never by OS=latest/name."""
import argparse
import json
import re
import sys
import uuid


def select_destination(inventory, sdk_version=None):
    ceiling = None
    if sdk_version is not None:
        if not re.fullmatch(r"\d+(?:\.\d+)*", sdk_version):
            raise ValueError("Invalid tvOS SDK version")
        ceiling = tuple(int(part) for part in sdk_version.split("."))
    candidates = []
    for runtime in inventory.get("runtimes", []):
        identifier = runtime.get("identifier", "")
        if not identifier.startswith("com.apple.CoreSimulator.SimRuntime.tvOS-"):
            continue
        if runtime.get("isAvailable") is not True:
            continue
        version_text = runtime.get("version", "")
        if not re.fullmatch(r"\d+(?:\.\d+)*", version_text):
            continue
        version = tuple(int(part) for part in version_text.split("."))
        if version < (26,) or (ceiling is not None and version > ceiling):
            continue
        for device in inventory.get("devices", {}).get(identifier, []):
            if device.get("isAvailable") is not True:
                continue
            name = device.get("name", "")
            if not name.startswith("Apple TV"):
                continue
            try:
                device_id = str(uuid.UUID(device.get("udid", ""))).upper()
            except (ValueError, TypeError, AttributeError):
                continue
            # Newest available runtime first; prefer full-resolution 4K, then a
            # stable UUID tie-breaker. Device generation names may change in Xcode.
            candidates.append((version, "4K" in name, "1080p" not in name, device_id))
    if not candidates:
        raise ValueError("No available Apple TV simulator with tvOS 26 or later compatible with the selected SDK found")
    return "platform=tvOS Simulator,id=" + max(candidates)[-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-version", help="Exclude runtimes newer than the selected Xcode tvOS SDK")
    args = parser.parse_args()
    try:
        print(select_destination(json.load(sys.stdin), args.sdk_version))
    except (ValueError, TypeError, KeyError) as error:
        print(f"Simulator selection failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
