#!/usr/bin/env python3
"""Capture read-only Xcode/runtime state; never repair or manage simulators."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

COMMANDS = {
    "selected-xcode": ["xcode-select", "-p"],
    "xcode-version": ["xcodebuild", "-version"],
    "first-launch-status": ["xcodebuild", "-checkFirstLaunchStatus"],
    "inventory": ["xcrun", "simctl", "list", "--json"],
    "runtime-images": ["xcrun", "simctl", "runtime", "list", "--json"],
    "runtime-matches": ["xcrun", "simctl", "runtime", "match", "list", "--json"],
}


def observed_paths(inventory, images):
    if not isinstance(inventory, dict) or not isinstance(inventory.get("runtimes"), list) or not isinstance(images, dict):
        raise ValueError("Unexpected simulator inventory/runtime-image schema")
    paths = []
    records = [(record, ("bundlePath", "runtimeRoot")) for record in inventory["runtimes"]]
    records += [(record, ("mountPath", "runtimeBundlePath", "parentMountPath", "path")) for record in images.values()]
    for record, fields in records:
        if not isinstance(record, dict):
            raise ValueError("Unexpected runtime record")
        for field in fields:
            value = record.get(field)
            if value is None:
                continue
            if not isinstance(value, str) or not Path(value).is_absolute():
                raise ValueError(f"Unexpected runtime {field}")
            paths.append({"identifier": record.get("identifier"), "runtimeIdentifier": record.get("runtimeIdentifier"), "field": field, "path": value})
    return paths


def path_status(value):
    path = Path(value)
    result = {"path": value, "readable": os.access(path, os.R_OK), "searchable": os.access(path, os.X_OK)}
    try:
        result.update(exists=path.exists(), isDirectory=path.is_dir(), isMount=path.is_mount())
        status = path.stat()
        result.update(deviceID=status.st_dev, inode=status.st_ino)
    except OSError as error:
        result["statError"] = str(error)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", required=True, choices=("before-resolve", "after-failure"))
    args = parser.parse_args()
    directory = Path(tempfile.mkdtemp(prefix=f"gus-simulator-{args.phase}-", dir=os.environ["RUNNER_TEMP"]))
    report = {"phase": args.phase, "runnerEnvironment": os.environ.get("GUS_RUNNER_ENVIRONMENT"),
              "configuredXcode": os.environ.get("XCODE_APP"), "developerDirectory": os.environ.get("DEVELOPER_DIR"),
              "installedXcodes": sorted(str(path) for path in Path("/Applications").glob("Xcode*.app")), "commands": {}}
    print(f"Simulator diagnostic evidence: {directory}", flush=True)
    outputs = {}
    for name, command in COMMANDS.items():
        started = datetime.now(timezone.utc).isoformat()
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired) as error:
            def text(value):
                return value.decode(errors="replace") if isinstance(value, bytes) else (value or "")
            result = subprocess.CompletedProcess(command, 124, text(getattr(error, "stdout", None)), text(getattr(error, "stderr", None)) + str(error))
        report["commands"][name] = {"argv": command, "startedAt": started, "finishedAt": datetime.now(timezone.utc).isoformat(), "exitCode": result.returncode}
        outputs[name] = result.stdout
        for stream in ("stdout", "stderr"):
            value = getattr(result, stream)
            (directory / f"{name}.{stream}.txt").write_text(value)
            print(f"--- {name} {stream} (exit {result.returncode}) ---\n{value}", flush=True)
    if report["commands"]["selected-xcode"]["exitCode"] == 0:
        report["selectedXcodePath"] = path_status(outputs["selected-xcode"].strip())
    try:
        report["runtimePaths"] = [{**entry, **path_status(entry["path"])} for entry in observed_paths(json.loads(outputs["inventory"]), json.loads(outputs["runtime-images"]))]
    except (ValueError, TypeError) as error:
        report["runtimePathParseError"] = str(error)
    (directory / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)
    # Nonzero command statuses are evidence, not a new runtime readiness policy.
    return 0


if __name__ == "__main__":
    sys.exit(main())
