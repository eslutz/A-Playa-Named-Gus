#!/usr/bin/env python3
"""Reject alpha-bearing default iOS/Watch icons before App Store upload."""
import json
from pathlib import Path
import struct
import sys

root = Path(__file__).resolve().parent.parent
folders = [
    root / "Resources/Assets.xcassets/AppIcon.appiconset",
    root / "Resources/Watch/Assets.xcassets/AppIcon.appiconset",
]
checked = 0
for folder in folders:
    for image in json.loads((folder / "Contents.json").read_text())["images"]:
        if image.get("platform") not in ("ios", "watchos"):
            continue
        # Apple supports transparent dark appearances; the store requires the
        # default full-color icon and Watch store icon to have no alpha channel.
        if image.get("appearances"):
            continue
        path = folder / image["filename"]
        data = path.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            sys.exit(f"App icon is not a PNG: {path.relative_to(root)}")
        offset, header, transparency = 8, None, False
        while offset + 12 <= len(data):
            length, kind = struct.unpack(">I4s", data[offset:offset + 8])
            payload = data[offset + 8:offset + 8 + length]
            if kind == b"IHDR":
                header = struct.unpack(">IIBBBBB", payload)
            transparency |= kind == b"tRNS"
            offset += length + 12
            if kind == b"IEND":
                break
        if header is None or header[:2] != (1024, 1024):
            sys.exit(f"App icon must be 1024 square: {path.relative_to(root)}")
        if header[3] in (4, 6) or transparency:
            sys.exit(f"App Store icon must have no alpha channel: {path.relative_to(root)}")
        checked += 1
print(f"Verified {checked} opaque default iOS/Watch app icons; appearance variants and Mac artwork are preserved.")
