#!/usr/bin/env python3
"""Offline runtime transition and deadline regressions; never invoke simctl."""
import copy
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("runtime_readiness", Path(__file__).with_name("wait-for-simulator-runtimes.py"))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


def fixture(retired=False):
    identifier, build = "com.apple.CoreSimulator.SimRuntime.watchOS-27-0", "24R362"
    old = "/Library/Developer/CoreSimulator/Volumes/watchOS_24R362"
    new = "/private/var/run/com.apple.security.cryptexd/mnt/watchOS_24R362"
    mount = new if retired else old
    bundle = mount + "/Library/Developer/CoreSimulator/Profiles/Runtimes/watchOS 27.0.simruntime"
    images = {"ready-id": {"runtimeIdentifier": identifier, "build": build, "state": "Ready", "supportedArchitectures": ["arm64"],
                           "signatureState": "Unknown", "mountPath": mount, "runtimeBundlePath": bundle},
              "alias-id": {"runtimeIdentifier": identifier, "build": build, "state": "Unusable", "unusableSubstate": "Cryptex Mount Preferred", "mountPath": old}}
    inventory = {"runtimes": [{"identifier": identifier, "buildversion": build, "isAvailable": True, "bundlePath": bundle,
                                "runtimeRoot": bundle + "/Contents/Resources/RuntimeRoot"}]}

    def probe(path):
        exists = not (retired and path == old)
        return {"exists": exists, "isDirectory": exists, "readable": exists, "searchable": exists,
                "isMount": exists and path in (old, new), "deviceID": 1 if exists else None, "inode": len(path) if exists else None}
    return images, inventory, probe


class RuntimeReadinessTests(unittest.TestCase):
    def test_saved_before_shape_waits_despite_ready_mounted_images(self):
        result = gate.readiness(*fixture())
        self.assertFalse(result["ready"])
        self.assertTrue(any("alias mount not retired" in reason for reason in result["reasons"]))

    def test_retired_alias_with_coherent_replacement_is_allowed(self):
        self.assertTrue(gate.readiness(*fixture(retired=True))["ready"])

    def test_old_volume_path_without_live_alias_is_not_rejected_by_prefix(self):
        images, inventory, probe = fixture()
        del images["alias-id"]
        self.assertTrue(gate.readiness(images, inventory, probe)["ready"])

    def test_pending_missing_architecture_mapping_and_path_are_not_ready(self):
        images, inventory, probe = fixture(retired=True)
        for field, value in (("state", "Mounting"), ("supportedArchitectures", ["x86_64"])):
            changed = copy.deepcopy(images)
            changed["ready-id"][field] = value
            with self.subTest(field=field):
                self.assertFalse(gate.readiness(changed, inventory, probe)["ready"])
        changed = copy.deepcopy(inventory)
        changed["runtimes"][0]["bundlePath"] += "/wrong"
        self.assertFalse(gate.readiness(images, changed, probe)["ready"])
        def missing(path):
            return {**probe(path), "readable": False}
        self.assertFalse(gate.readiness(images, inventory, missing)["ready"])

    def test_empty_malformed_and_relative_data_fail_closed(self):
        for images, inventory in (({}, {"runtimes": []}), ([], {}), ({"id": None}, {"runtimes": [{}]})):
            with self.subTest(images=images), self.assertRaises(ValueError):
                gate.readiness(images, inventory)
        images, inventory, probe = fixture(retired=True)
        images["ready-id"]["mountPath"] = "relative"
        with self.assertRaises(ValueError):
            gate.readiness(images, inventory, probe)

    def test_malformed_architecture_and_no_ready_images_cannot_pass(self):
        images, inventory, probe = fixture(retired=True)
        images["ready-id"]["supportedArchitectures"] = "arm64"
        with self.assertRaises(ValueError):
            gate.readiness(images, inventory, probe)
        del images["ready-id"]
        self.assertFalse(gate.readiness(images, inventory, probe)["ready"])

    def test_local_execution_is_refused_before_query_or_file_creation(self):
        with patch.dict(gate.os.environ, {}, clear=True), patch.object(gate.subprocess, "run") as query, contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(gate.main(), 1)
        query.assert_not_called()

    def run_wait(self, samples):
        now, deadlines, emitted = [0], [], []
        def sample(deadline):
            deadlines.append(deadline)
            value = samples(now)
            return dict(value)
        result = gate.wait(sample, clock=lambda: now[0], sleep=lambda duration: now.__setitem__(0, now[0] + duration), emit=emitted.append)
        return result, now[0], deadlines, emitted

    def test_ten_seconds_of_health_are_required_and_changes_reset_stability(self):
        result, elapsed, deadlines, _ = self.run_wait(lambda now: {"ready": True, "fingerprint": "old" if now[0] < 8 else "new"})
        self.assertEqual(elapsed, 18)
        self.assertEqual(result["stableSeconds"], 10)
        self.assertTrue(all(value == 120 for value in deadlines))

    def test_unhealthy_sample_resets_stability(self):
        _, elapsed, _, _ = self.run_wait(lambda now: {"ready": now[0] != 8, "fingerprint": "same"})
        self.assertEqual(elapsed, 20)

    def test_deadline_includes_query_time_and_never_passes_late_result(self):
        now = [0]
        def slow_sample(deadline):
            self.assertEqual(deadline, 120)
            now[0] = 121
            return {"ready": True, "fingerprint": "same"}
        with self.assertRaisesRegex(RuntimeError, "120 seconds"):
            gate.wait(slow_sample, clock=lambda: now[0], sleep=lambda _: self.fail("must not sleep"), emit=lambda _: None)

    def test_emitting_ready_sample_after_deadline_cannot_pass(self):
        now = [0]
        def emit(_):
            if now[0] == 10:
                now[0] = 121
        with self.assertRaisesRegex(RuntimeError, "120 seconds"):
            gate.wait(lambda _: {"ready": True, "fingerprint": "same"}, clock=lambda: now[0],
                      sleep=lambda duration: now.__setitem__(0, now[0] + duration), emit=emit)

    def failed_query(self, response, code, stdout, stderr):
        with tempfile.TemporaryDirectory() as temporary:
            environment = {"GITHUB_ACTIONS": "true", "GUS_RUNNER_ENVIRONMENT": "github-hosted", "RUNNER_TEMP": temporary}
            output, errors = io.StringIO(), io.StringIO()
            with patch.dict(gate.os.environ, environment, clear=True), patch.object(gate, "wait", side_effect=lambda sample, emit: sample(107)), \
                    patch.object(gate.time, "monotonic", return_value=100), patch.object(gate.subprocess, "run", side_effect=[response]) as query, \
                    contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                self.assertEqual(gate.main(), 1)
            query.assert_called_once_with(gate.COMMANDS["images"], capture_output=True, text=True, timeout=7)
            evidence = next(Path(temporary).iterdir())
            record = json.loads((evidence / "001-images.json").read_text())
            self.assertEqual(record["exitCode"], code)
            self.assertEqual(record["stdout"], stdout)
            self.assertTrue(record["stderr"].startswith(stderr))
            self.assertIn(stderr, errors.getvalue())
            self.assertFalse(json.loads((evidence / "result.json").read_text())["accepted"])

    def test_main_command_error_preserves_diagnostics_and_stops(self):
        self.failed_query(subprocess.CompletedProcess([], 1, "partial output\n", "warning: query failed\n"),
                          1, "partial output\n", "warning: query failed\n")

    def test_main_timeout_uses_remaining_budget_and_preserves_partial_bytes(self):
        self.failed_query(subprocess.TimeoutExpired(gate.COMMANDS["images"], 7, output=b"partial JSON", stderr=b"warning: stalled query\n"),
                          124, "partial JSON", "warning: stalled query\n")

    def test_persistent_conflict_times_out_without_build_or_mutation_commands(self):
        with self.assertRaisesRegex(RuntimeError, "120 seconds"):
            self.run_wait(lambda _: {"ready": False, "fingerprint": "conflict"})
        self.assertEqual(list(gate.COMMANDS.values()), [["xcrun", "simctl", "runtime", "list", "--json"],
                                                       ["xcrun", "simctl", "list", "runtimes", "--json"]])


if __name__ == "__main__":
    unittest.main()
