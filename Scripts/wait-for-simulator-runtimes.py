#!/usr/bin/env python3
"""Wait for coherent, stable runtime mounts before Xcode discovers simulators."""
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

spec = importlib.util.spec_from_file_location("simulator_diagnostics", Path(__file__).with_name("simulator-diagnostics.py"))
diagnostics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostics)

COMMANDS = {
    "images": ["xcrun", "simctl", "runtime", "list", "--json"],
    "runtimes": ["xcrun", "simctl", "list", "runtimes", "--json"],
}


def readiness(images, inventory, probe=diagnostics.path_status):
    if not isinstance(images, dict) or not images or not isinstance(inventory, dict) or not isinstance(inventory.get("runtimes"), list) or not inventory["runtimes"]:
        raise ValueError("Empty or malformed runtime image/inventory snapshot")
    reasons, paths, ready, available = [], {}, {}, {}

    def key(record, identifier, build):
        if not isinstance(record, dict) or not all(isinstance(record.get(field), str) and record[field] for field in (identifier, build)):
            raise ValueError("Runtime identity/build is missing or malformed")
        return record[identifier], record[build]

    def status(path):
        if not isinstance(path, str) or not Path(path).is_absolute():
            raise ValueError("Runtime path is missing or not absolute")
        if path not in paths:
            paths[path] = probe(path)
        return paths[path]

    def readable(path, mounted=False):
        value = status(path)
        fields = ("exists", "isDirectory", "readable", "searchable") + (("isMount",) if mounted else ())
        if not all(value.get(field) is True for field in fields) or not all(type(value.get(field)) is int for field in ("deviceID", "inode")):
            reasons.append(f"Runtime path not ready: {path}")
        return value.get("deviceID"), value.get("inode")

    for runtime in inventory["runtimes"]:
        identity = key(runtime, "identifier", "buildversion")
        if type(runtime.get("isAvailable")) is not bool:
            raise ValueError("Runtime availability must be Boolean")
        if runtime["isAvailable"]:
            if identity in available:
                reasons.append(f"Duplicate available runtime: {identity}")
            available[identity] = runtime
    for image_id, image in images.items():
        identity = key(image, "runtimeIdentifier", "build")
        if image.get("state") == "Unusable":
            continue
        architectures = image.get("supportedArchitectures")
        if not isinstance(architectures, list) or not all(isinstance(value, str) for value in architectures):
            raise ValueError("Runtime image architectures must be a string array")
        if image.get("state") != "Ready" or "arm64" not in architectures:
            reasons.append(f"Runtime image not Ready/arm64: {image_id}")
            continue
        if identity in ready:
            reasons.append(f"Multiple Ready images: {identity}")
        ready[identity] = image
        mount = readable(image.get("mountPath"), mounted=True)
        bundle = readable(image.get("runtimeBundlePath"))
        root_path = str(Path(image["runtimeBundlePath"]) / "Contents/Resources/RuntimeRoot")
        root = readable(root_path)
        runtime = available.get(identity)
        if runtime is None:
            reasons.append(f"Ready image missing from available runtime inventory: {identity}")
        else:
            if readable(runtime.get("bundlePath")) != bundle or readable(runtime.get("runtimeRoot")) != root:
                reasons.append(f"Runtime inventory/image paths disagree: {identity}")
        if mount[0] != bundle[0] or mount[0] != root[0]:
            reasons.append(f"Runtime content is not on its reported mount: {identity}")
    if not ready:
        reasons.append("No Ready runtime images")
    for identity in available.keys() - ready.keys():
        reasons.append(f"Available runtime has no Ready image: {identity}")
    for image in images.values():
        if image.get("state") == "Unusable" and image.get("unusableSubstate") == "Cryptex Mount Preferred":
            identity = key(image, "runtimeIdentifier", "build")
            # https://github.com/actions/runner-images/issues/14946
            # Some successful jobs share this initial shape. Wait for retirement
            # of the live old mount; Unusable alone does not establish failure.
            if identity not in ready or status(image.get("mountPath")).get("isMount") is not False:
                reasons.append(f"Cryptex-preferred alias mount not retired: {identity}")
    fingerprint = {
        "images": sorted((identifier, image["runtimeIdentifier"], image["build"], image.get("state"), image.get("unusableSubstate"), image.get("mountPath"), image.get("runtimeBundlePath")) for identifier, image in images.items()),
        "runtimes": sorted((identity, runtime.get("bundlePath"), runtime.get("runtimeRoot")) for identity, runtime in available.items()),
        "paths": sorted((path, value.get("exists"), value.get("isMount"), value.get("deviceID"), value.get("inode")) for path, value in paths.items()),
    }
    digest = hashlib.sha256(json.dumps(fingerprint, sort_keys=True).encode()).hexdigest()
    return {"ready": not reasons, "reasons": reasons, "fingerprint": digest, "paths": paths}


def wait(sample, clock=time.monotonic, sleep=time.sleep, emit=print):
    deadline = clock() + 120
    stable_since, previous = None, None
    while clock() < deadline:
        result = sample(deadline)
        now = clock()
        if now >= deadline:
            break
        if result["ready"]:
            if previous != result["fingerprint"]:
                stable_since = now
            previous = result["fingerprint"]
        else:
            stable_since, previous = None, None
        result["stableSeconds"] = 0 if stable_since is None else now - stable_since
        emit(json.dumps(result, sort_keys=True))
        if clock() >= deadline:
            break
        if stable_since is not None and now - stable_since >= 10:
            return result
        sleep(min(2, max(0, deadline - clock())))
    raise RuntimeError("Simulator runtimes did not become coherent and stable within 120 seconds")


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("GUS_RUNNER_ENVIRONMENT") != "github-hosted":
        print("Runtime startup gate requires a GitHub-hosted Actions job", file=sys.stderr)
        return 1
    directory = Path(tempfile.mkdtemp(prefix="gus-runtime-readiness-", dir=os.environ["RUNNER_TEMP"]))
    print(f"Runtime readiness evidence: {directory}", flush=True)
    number = 0

    def sample(deadline):
        nonlocal number
        number += 1
        data = {}
        for name, command in COMMANDS.items():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError("Runtime readiness deadline reached before next query")
            started = datetime.now(timezone.utc).isoformat()
            try:
                result = subprocess.run(command, capture_output=True, text=True, timeout=min(30, remaining))
            except (OSError, subprocess.TimeoutExpired) as error:
                def text(value):
                    return value.decode(errors="replace") if isinstance(value, bytes) else (value or "")
                result = subprocess.CompletedProcess(command, 124, text(getattr(error, "stdout", None)), text(getattr(error, "stderr", None)) + str(error))
            record = {"argv": command, "startedAt": started, "finishedAt": datetime.now(timezone.utc).isoformat(), "exitCode": result.returncode, "stdout": result.stdout, "stderr": result.stderr}
            (directory / f"{number:03d}-{name}.json").write_text(json.dumps(record, indent=2) + "\n")
            print(json.dumps(record), flush=True)
            if result.stderr:
                print(result.stderr, end="", file=sys.stderr, flush=True)
            if result.returncode:
                print(result.stdout, end="", flush=True)
                raise RuntimeError(f"Runtime readiness query failed: {name}, exit {result.returncode}")
            data[name] = json.loads(result.stdout)
        return readiness(data["images"], data["runtimes"])

    try:
        result = wait(sample, emit=lambda line: print(line, flush=True))
        result["accepted"] = True
    except (OSError, ValueError, RuntimeError) as error:
        result = {"accepted": False, "error": str(error)}
    (directory / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result), flush=True)
    return 0 if result["accepted"] else 1


if __name__ == "__main__":
    sys.exit(main())
