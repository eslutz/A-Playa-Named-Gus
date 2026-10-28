#!/usr/bin/env python3
"""Append unedited iPad XCTest captures to the existing external Sketch report.

Export each result bundle with `xcresulttool export attachments` first. This tool
keeps before/Sketch images intact and refuses incomplete coverage unless requested.
Capture coverage is deliberately separate from visual/behavioral acceptance.
"""

import argparse
import hashlib
import html
import json
import re
import shutil
import struct
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report-root", required=True, type=Path)
    parser.add_argument("--attachments", required=True, type=Path, nargs="+")
    parser.add_argument("--allow-partial", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    root = args.report_root.resolve()
    scenarios = json.loads((root / "design-index.json").read_text())
    captures = {}
    for directory in args.attachments:
        for test in json.loads((directory / "manifest.json").read_text()):
            for attachment in test.get("attachments", []):
                match = re.fullmatch(r"design-(.+)_\d+_[A-Fa-f0-9-]+\.png", attachment.get("suggestedHumanReadableName", ""))
                if not match or not attachment.get("deviceName", "").startswith("iPad"):
                    continue
                name = match[1]
                if name not in scenarios:
                    continue
                if name in captures and captures[name][1]["timestamp"] >= attachment["timestamp"]:
                    continue
                captures[name] = (directory, attachment, test["testIdentifier"])
    missing = sorted(set(scenarios) - captures.keys())
    print(json.dumps({"captured": len(captures), "expected": len(scenarios), "missing": missing}, indent=2))
    if missing and not args.allow_partial:
        raise SystemExit("Incomplete implementation captures; report was not changed.")
    if args.dry_run:
        return

    protected = {p: digest(p) for folder in ("before", "before-compact", "design", "design-extras")
                 for p in (root / folder).glob("*.png")}
    output = root / "implementation"
    images = output / "images"
    images.mkdir(parents=True, exist_ok=True)
    records = {}
    for name, (directory, attachment, test) in captures.items():
        source = directory / attachment["exportedFileName"]
        data = source.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"Not a PNG: {source}")
        width, height = struct.unpack(">II", data[16:24])
        destination = images / (name + ".png")
        shutil.copyfile(source, destination)
        records[name] = {"file": str(destination.relative_to(root)), "sha256": digest(destination),
                         "width": width, "height": height, "test": test,
                         "device": attachment["deviceName"], "timestamp": attachment["timestamp"],
                         "acceptance": "captured; visual and behavior review recorded separately"}
    (output / "capture-index.json").write_text(json.dumps({"scenarios": records, "missing": missing}, indent=2) + "\n")

    page = root / "index.html"
    markup = page.read_text()
    markup = re.sub(r"<!-- implementation-status:start -->.*?<!-- implementation-status:end -->", "", markup, flags=re.S)
    status = (f'<!-- implementation-status:start --><section><h2>iPad implementation comparison</h2>'
              f'<p>{len(records)}/{len(scenarios)} implementation captures. Images are unedited XCTest attachments. '
              'Capture coverage does not establish interaction or physical-device acceptance. '
              '<a href="implementation/capture-index.json">Capture provenance and remaining scenarios</a> · '
              '<a href="implementation/implementation-checklist.json">Implementation acceptance checklist</a></p>'
              '</section><!-- implementation-status:end -->')
    markup = markup.replace('<section id="delivery">', status + '<section id="delivery">', 1)
    markup = re.sub(r"<!-- implementation-image:start -->.*?<!-- implementation-image:end -->", "", markup, flags=re.S)
    for name, record in records.items():
        pattern = r'(<section data-name="' + re.escape(name) + r'" id="' + re.escape(name) + r'">.*?)(</div>\s*</section>)'
        image = (f'<!-- implementation-image:start --><figure><figcaption>Implemented iPad app</figcaption>'
                 f'<a href="{record["file"]}"><img loading="lazy" src="{record["file"]}" '
                 f'alt="{html.escape(name)} implementation"></a><small>Unedited simulator capture · '
                 f'{record["width"]} × {record["height"]}</small></figure><!-- implementation-image:end -->')
        markup, count = re.subn(pattern, lambda match: match[1] + image + match[2], markup, count=1, flags=re.S)
        if count != 1:
            raise ValueError(f"Report section missing: {name}")
    markup = markup.replace('grid-template-columns:1fr 1fr;', 'grid-template-columns:repeat(auto-fit,minmax(min(100%,340px),1fr));')
    if any(digest(path) != expected for path, expected in protected.items()):
        raise ValueError("A protected before/Sketch image changed")
    page.write_text(markup)


if __name__ == "__main__":
    main()
