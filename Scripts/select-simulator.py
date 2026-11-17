#!/usr/bin/env python3
"""Pick an available TV, Watch, or Vision simulator by UUID."""
import argparse
import json
import re
import sys
import uuid


PLATFORMS = {"tvOS": ("tvOS", "Apple TV"), "watchOS": ("watchOS", "Apple Watch"), "visionOS": ("xrOS", "Apple Vision Pro")}


def select_destination(inventory, sdk_version=None, platform="tvOS"):
    if platform not in PLATFORMS:
        raise ValueError("Unsupported simulator platform")
    runtime_family, device_prefix = PLATFORMS[platform]
    ceiling = None
    if sdk_version is not None:
        if not re.fullmatch(r"\d+(?:\.\d+)*", sdk_version):
            raise ValueError(f"Invalid {platform} SDK version")
        ceiling = tuple(int(part) for part in sdk_version.split("."))
    candidates = []
    for runtime in inventory.get("runtimes", []):
        identifier = runtime.get("identifier", "")
        if not identifier.startswith(f"com.apple.CoreSimulator.SimRuntime.{runtime_family}-"):
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
            if not name.startswith(device_prefix):
                continue
            try:
                device_id = str(uuid.UUID(device.get("udid", ""))).upper()
            except (ValueError, TypeError, AttributeError):
                continue
            # Newest runtime first; retain TV's full-resolution 4K preference.
            # Other families use a stable UUID tie-breaker, independent of names.
            candidates.append((version, platform == "tvOS" and "4K" in name,
                               platform != "tvOS" or "1080p" not in name, device_id))
    if not candidates:
        raise ValueError(f"No available {device_prefix} simulator with {platform} 26 or later compatible with the selected SDK found")
    return f"platform={platform} Simulator,id=" + max(candidates)[-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=tuple(PLATFORMS), default="tvOS")
    parser.add_argument("--sdk-version", help="Exclude runtimes newer than the selected platform SDK")
    args = parser.parse_args()
    try:
        print(select_destination(json.load(sys.stdin), args.sdk_version, args.platform))
    except (ValueError, TypeError, KeyError) as error:
        print(f"Simulator selection failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
