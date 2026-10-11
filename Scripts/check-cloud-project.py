#!/usr/bin/env python3
"""Check the shared XcodeGen snapshot without modifying the working project."""
import json
import xml.etree.ElementTree as ET
from pathlib import Path
import shutil
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parent.parent
project_name = "A Playa Named Gus.xcodeproj"
project = root / project_name
with tempfile.TemporaryDirectory(prefix="gus-cloud-project-") as directory:
    scratch = Path(directory)
    shutil.copy2(root / "project.yml", scratch / "project.yml")
    for name in ("Sources", "Tests", "Resources", "Config"):
        shutil.copytree(root / name, scratch / name,
                        ignore=shutil.ignore_patterns("Local.xcconfig", "*.p8"))
    subprocess.run(["xcodegen", "generate"], cwd=scratch, check=True,
                   stdout=subprocess.DEVNULL)
    generated = scratch / project_name
    files = [Path("project.pbxproj"), Path("project.xcworkspace/contents.xcworkspacedata")]
    files += [p.relative_to(generated) for p in
              (generated / "xcshareddata/xcschemes").glob("*.xcscheme")]
    actual_schemes = {p.name for p in (project / "xcshareddata/xcschemes").glob("*.xcscheme")}
    expected_schemes = {p.name for p in (generated / "xcshareddata/xcschemes").glob("*.xcscheme")}
    def contents(path):
        if path.suffix != ".xcscheme":
            return path.read_bytes()
        scheme = ET.parse(path).getroot()
        # Xcode updates scheme-format metadata and explicit default values on open.
        scheme.attrib.pop("LastUpgradeVersion", None)
        scheme.attrib.pop("version", None)
        for node in scheme.iter():
            for attribute in ("runPostActionsOnFailure", "onlyGenerateCoverageForSpecifiedTargets", "parallelizable"):
                if node.get(attribute) == "NO":
                    node.attrib.pop(attribute)
            # Product naming in xcconfig is resolved by Xcode after generation;
            # target IDs and container references still must match exactly.
            if node.tag == "BuildableReference":
                node.attrib.pop("BuildableName", None)
                node.attrib.pop("BlueprintName", None)
        for parent in scheme.iter():
            for node in list(parent):
                if node.tag in ("CommandLineArguments", "EnvironmentVariables") and not len(node) and not node.attrib:
                    parent.remove(node)
            if parent.text and not parent.text.strip():
                parent.text = None
            if parent.tail and not parent.tail.strip():
                parent.tail = None
        return ET.tostring(scheme)
    drift = [str(p) for p in files if not (project / p).is_file()
             or contents(project / p) != contents(generated / p)]
    if actual_schemes != expected_schemes:
        drift.append("shared scheme inventory")
    if drift:
        sys.exit("Regenerate with xcodegen generate and include the shared project changes: "
                 + ", ".join(drift))

lock = json.loads((project / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())
pins = lock.get("pins", [])
if not pins or len({p["identity"] for p in pins}) != len(pins):
    sys.exit("Package.resolved must contain unique dependency pins")
for pin in pins:
    if not pin.get("state", {}).get("revision"):
        sys.exit("Every dependency must pin a revision")
print(f"Cloud project matches project.yml; {len(expected_schemes)} shared schemes and {len(pins)} dependency pins verified.")
