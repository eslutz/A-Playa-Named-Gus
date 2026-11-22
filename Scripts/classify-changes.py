#!/usr/bin/env python3
"""Select full validation unless every changed path is documentation-only."""
import argparse
import re
import subprocess
from pathlib import PurePosixPath


def requires_full_validation(paths):
    runtime_roots = ("Sources/", "Tests/", "Resources/", "SiriPreview/", "Config/", "Scripts/", "ci_scripts/", ".github/")
    for path in paths:
        if path.startswith(runtime_roots):
            return True
        if path in {"project.yml", ".swiftformat"} or ".xcodeproj/" in path or ".xcworkspace/" in path or path.endswith("Package.resolved"):
            return True
        # Unknown file types default to full validation. Only contributor prose
        # is excluded; fixture Markdown under Tests still exercises the matrix.
        if PurePosixPath(path).suffix.lower() != ".md":
            return True
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", required=True)
    args = parser.parse_args()
    for revision in (args.base, args.head):
        if not re.fullmatch(r"[0-9a-fA-F]{40,64}", revision):
            parser.error("base/head must be full commit hashes")
    data = subprocess.check_output(["git", "diff", "--name-only", "--no-renames", "-z", args.base + "..." + args.head])
    paths = [path for path in data.decode("utf-8").split("\0") if path]
    print("full=" + str(requires_full_validation(paths)).lower())


if __name__ == "__main__":
    main()
