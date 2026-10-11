#!/usr/bin/env python3
"""Local, keyless release validation. Never uploads, signs for distribution or pushes.

Run --phase static, builds, tests, ui or archives; --phase all runs them in order.
All Xcode lanes are sequential, pinned to Package.resolved, and have unique results.
Use --root with a materialized staged candidate to exclude ignored local overrides.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import platform as host_platform
import re
import subprocess
import sys
import time


def run(command, root, output, name, results, env=None, timeout=3600):
    print(f"Starting {name}", flush=True)
    started = time.monotonic()
    log = output / f"{name}.log"
    with log.open("w") as stream:
        try:
            result = subprocess.run(command, cwd=root, stdout=stream,
                                    stderr=subprocess.STDOUT, env=env, timeout=timeout)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 124
    entry = dict(name=name, command=command, exitCode=code,
                 seconds=round(time.monotonic() - started, 2), log=log.name)
    if "-resultBundlePath" in command:
        bundle = Path(command[command.index("-resultBundlePath") + 1])
        if code == 0 and not (bundle / "Info.plist").exists():
            code = entry["exitCode"] = 1
        if (bundle / "Info.plist").exists():
            summary = json.loads(subprocess.check_output([
                "xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle), "--compact"
            ], text=True))
            (output / f"{name}-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
            entry["tests"] = {key: summary.get(key) for key in (
                "totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures", "result")}
            if code == 0 and (summary.get("skippedTests", 0) or summary.get("expectedFailures", 0)
                              or summary.get("failedTests", 0) or not summary.get("totalTestCount", 0)):
                code = entry["exitCode"] = 1
    results.append(entry)
    (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print(f"{name}: {'PASS' if code == 0 else 'FAIL'} ({entry['seconds']} s)", flush=True)
    if code:
        raise RuntimeError(f"{name} failed; inspect {log}")


def source_hashes(root):
    paths = [root / "project.yml", *root.glob("Config/*.xcconfig")]
    for folder in ("Sources", "Tests", "Resources", "Scripts", "ci_scripts", ".github"):
        paths.extend(p for p in (root / folder).rglob("*") if p.is_file())
    paths.extend(p for p in (root / "A Playa Named Gus.xcodeproj").rglob("*")
                 if p.is_file() and "xcuserdata" not in p.parts)
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(set(paths)) if p.name != "Local.xcconfig" and "__pycache__" not in p.parts}


def static_checks(root, output, results):
    for folder in ("Resources", "Config", "Documentation/AppStore/api-templates"):
        for path in (root / folder).rglob("*"):
            if not path.is_file():
                continue
            if path.suffix in (".json", ".xcstrings"):
                json.loads(path.read_text())
            if path.suffix in (".plist", ".entitlements", ".xcprivacy"):
                plistlib.loads(path.read_bytes())
    for path in [*root.glob("*.md"), *(root / "Documentation").rglob("*.md")]:
        text = path.read_bytes().decode("utf-8")
        if "\r" in text or re.search(r"^(<<<<<<< |=======|>>>>>>> )", text, re.M):
            raise RuntimeError(f"Invalid Markdown/conflict marker: {path}")
    for path in (root / "Scripts").glob("*.py"):
        compile(path.read_text(), str(path), "exec")
    manifest = plistlib.loads((root / "Resources/PrivacyInfo.xcprivacy").read_bytes())
    reasons = {entry["NSPrivacyAccessedAPIType"]: entry["NSPrivacyAccessedAPITypeReasons"]
               for entry in manifest["NSPrivacyAccessedAPITypes"]}
    assert "E174.1" in reasons["NSPrivacyAccessedAPICategoryDiskSpace"]
    assert "CA92.1" in reasons["NSPrivacyAccessedAPICategoryUserDefaults"]
    config = (root / "Config/Shared.xcconfig").read_text()
    assert re.search(r"^MARKETING_VERSION = 1\.0\.0$", config, re.M)
    assert "SWIFT_STRICT_CONCURRENCY = complete" in config
    commands = [
        ("format", ["swiftformat", "Sources", "Tests", "--lint", "--cache", "ignore"]),
        ("api-format", ["swiftformat", "Scripts/app-store-connect.swift", "--lint", "--cache", "ignore"]),
        ("cloud-bootstrap", ["python3", "Scripts/test-cloud-bootstrap.py"]),
        ("project-pins", ["python3", "Scripts/check-cloud-project.py"]),
        ("asc-self-test", ["swift", "Scripts/app-store-connect.swift", "self-test"]),
        ("whitespace", ["git", "diff", "--check"]),
        ("yaml", ["ruby", "-ryaml", "-e", "(Dir['.github/workflows/*.yml'] + ['project.yml']).each { |p| YAML.load_file(p) }"]),
    ]
    for name, command in commands:
        run(command, root, output, name, results, timeout=300)


def destinations():
    data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
    chosen = {}
    for runtime, devices in data["devices"].items():
        match = re.search(r"(iOS|tvOS|watchOS|visionOS|xrOS)-(\d+)-(\d+)", runtime)
        if not match:
            continue
        platform, major, minor = match.groups()
        platform = "visionOS" if platform == "xrOS" else platform
        version = (int(major), int(minor))
        minimum = {"iOS": 18, "tvOS": 18, "watchOS": 11, "visionOS": 2}[platform]
        if version[0] < minimum:
            continue
        for device in devices:
            if not device.get("isAvailable", True):
                continue
            name = device["name"]
            kind = "ipad" if name.startswith("iPad") else "ios" if name.startswith("iPhone") else {
                "tvOS": "tv", "watchOS": "watch", "visionOS": "vision"}.get(platform)
            # Never operate on other projects' named audit simulators.
            if kind is None or not name.startswith(("iPhone", "iPad", "Apple TV", "Apple Watch", "Apple Vision")):
                continue
            score = (version, "Pro" not in name, "40mm" in name)
            if kind not in chosen or score > chosen[kind][0]:
                chosen[kind] = (score, device, runtime)
    for kind in ("ios", "ipad", "tv", "watch", "vision"):
        if kind not in chosen:
            raise RuntimeError(f"No compatible {kind} simulator; cannot substitute an OS below deployment target")
    return {k: dict(udid=v[1]["udid"], name=v[1]["name"], runtime=v[2]) for k, v in chosen.items()}


def archive_inventory(output):
    inventory = []
    for archive in output.glob("*.xcarchive"):
        apps = list((archive / "Products/Applications").glob("*.app"))
        if len(apps) != 1:
            raise RuntimeError(f"Unexpected archive products: {archive}")
        app = apps[0]
        bundles = [app, *app.rglob("*.app"), *app.rglob("*.appex")]
        for bundle in bundles:
            plist = bundle / "Info.plist"
            if not plist.exists():
                plist = bundle / "Contents/Info.plist"
            info = plistlib.loads(plist.read_bytes())
            assert info["CFBundleShortVersionString"] == "1.0.0", bundle
            assert str(info["CFBundleVersion"]).isdigit(), bundle
            resources = bundle / "Contents/Resources" if "Contents" in plist.parts else bundle
            identifier = info["CFBundleIdentifier"]
            privacy = []
            for manifest_path in bundle.rglob("*.xcprivacy"):
                manifest = plistlib.loads(manifest_path.read_bytes())
                privacy.append(dict(path=str(manifest_path.relative_to(bundle)),
                                    accessedAPIs=manifest.get("NSPrivacyAccessedAPITypes", []),
                                    tracking=manifest.get("NSPrivacyTracking", False)))
            if identifier in ("dev.ericslutz.gus", "dev.ericslutz.gus.watchkitapp"):
                owned_manifest = resources / "PrivacyInfo.xcprivacy"
                assert owned_manifest.exists(), bundle
                owned = plistlib.loads(owned_manifest.read_bytes())
                reasons = {entry["NSPrivacyAccessedAPIType"]: entry["NSPrivacyAccessedAPITypeReasons"]
                           for entry in owned["NSPrivacyAccessedAPITypes"]}
                assert "E174.1" in reasons["NSPrivacyAccessedAPICategoryDiskSpace"], bundle
                assert "CA92.1" in reasons["NSPrivacyAccessedAPICategoryUserDefaults"], bundle
            executable = bundle / info["CFBundleExecutable"]
            if "Contents" in plist.parts:
                executable = bundle / "Contents/MacOS" / info["CFBundleExecutable"]
            binary = executable.read_bytes()
            for debug_flag in (b"--gus-demo-server", b"--gus-skip-session-restore", b"--gus-route"):
                assert debug_flag not in binary, f"Debug launch route in {bundle}"
            inventory.append(dict(archive=archive.name, bundle=str(bundle.relative_to(archive)),
                                  identifier=identifier, version=info["CFBundleShortVersionString"],
                                  build=info["CFBundleVersion"],
                                  binarySHA256=hashlib.sha256(binary).hexdigest(),
                                  manifests=privacy))
    (output / "archive-inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--derived-data", type=Path, help="Shared cache for sequential lanes; never uses ignored source overrides")
    parser.add_argument("--phase", choices=("static", "builds", "tests", "ui", "archives", "all"), default="static")
    args = parser.parse_args()
    root = args.root.resolve()
    output = (args.output or root / "build/release-validation" / args.phase).resolve()
    output.mkdir(parents=True, exist_ok=True)
    initial = source_hashes(root)
    (output / "source-hashes.json").write_text(json.dumps(initial, indent=2) + "\n")
    results = []
    phases = ("static", "builds", "tests", "ui", "archives") if args.phase == "all" else (args.phase,)
    try:
        if "static" in phases:
            static_checks(root, output, results)
        if any(p in phases for p in ("builds", "tests", "ui")):
            devices = destinations()
            (output / "destinations.json").write_text(json.dumps(devices, indent=2) + "\n")
        developer = subprocess.check_output(["xcodebuild", "-version"], text=True)
        (output / "toolchain.txt").write_text(developer)
        if not developer.startswith("Xcode 27."):
            raise RuntimeError("Select an Xcode 27 toolchain before release validation")
        common = ["xcodebuild", "-project", "A Playa Named Gus.xcodeproj",
                  "-derivedDataPath", str((args.derived_data or output / "DerivedData").resolve()),
                  "-onlyUsePackageVersionsFromResolvedFile", "ONLY_ACTIVE_ARCH=YES",
                  "-collect-test-diagnostics", "never"]
        generic = {"ios": "generic/platform=iOS Simulator", "ipad": "platform=iOS Simulator,id=" + devices["ipad"]["udid"] if 'devices' in locals() else "",
                   "mac": "platform=macOS", "tv": "generic/platform=tvOS Simulator",
                   "vision": "generic/platform=visionOS Simulator", "watch": "generic/platform=watchOS Simulator"}
        concrete = {k: "platform=" + {"ios": "iOS", "ipad": "iOS", "tv": "tvOS", "watch": "watchOS", "vision": "visionOS"}[k]
                    + " Simulator,id=" + v["udid"] for k, v in devices.items()} if 'devices' in locals() else {}
        concrete["mac"] = "platform=macOS"
        if "builds" in phases:
            for lane, destination in generic.items():
                scheme = "Gus watchOS" if lane == "watch" else "A Playa Named Gus"
                signing = ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO"] if lane == "mac" else []
                run(common + ["-scheme", scheme, "-destination", destination, "ARCHS=" + host_platform.machine()] + signing + ["build"], root, output, "build-" + lane, results)
        if "tests" in phases:
            for lane, platform in (("ios", "iOS"), ("mac", "macOS"), ("tv", "tvOS"), ("vision", "visionOS")):
                signing = ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO"] if lane == "mac" else []
                run(common + ["-scheme", f"Gus {platform} Unit Tests", "-destination", concrete[lane],
                              "-parallel-testing-enabled", "NO", "-resultBundlePath", str(output / f"unit-{lane}.xcresult")] + signing + ["test"], root, output, "unit-" + lane, results)
        if "ui" in phases:
            # Authenticated tests use only the isolated local demo service.
            import urllib.request
            with urllib.request.urlopen("http://127.0.0.1:8096/System/Info/Public", timeout=10) as response:
                if json.load(response).get("ProductName") not in ("Jellyfin", "Jellyfin Server"):
                    raise RuntimeError("The localhost UI fixture is not a Jellyfin server")
            for lane, platform in (("ios", "iOS"), ("ipad", "iOS"), ("tv", "tvOS"), ("vision", "visionOS"), ("watch", "watchOS")):
                run(common + ["-scheme", f"Gus {platform} Tests", "-destination", concrete[lane],
                              "-parallel-testing-enabled", "NO", "-only-testing:" + {"iOS": "GusUITests", "tvOS": "GusTVOSUITests", "visionOS": "GusVisionOSUITests", "watchOS": "GusWatchUITests"}[platform],
                              "-resultBundlePath", str(output / f"ui-{lane}.xcresult"), "test"], root, output, "ui-" + lane, results)
        if "archives" in phases:
            for lane, destination in (("ios", "iOS"), ("tv", "tvOS"), ("vision", "visionOS"), ("mac", "macOS")):
                run(common + ["-scheme", "A Playa Named Gus", "-destination", "generic/platform=" + destination,
                              "-configuration", "Release", "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
                              "-archivePath", str(output / f"{lane}.xcarchive"), "archive"], root, output, "archive-" + lane, results)
            archive_inventory(output)
        if source_hashes(root) != initial:
            raise RuntimeError("Candidate source changed during validation; rerun affected gates")
    except (RuntimeError, AssertionError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print("Requested validation phases passed. Device/assistive/portal acceptance remains separate.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
