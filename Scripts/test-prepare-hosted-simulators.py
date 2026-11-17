#!/usr/bin/env python3
"""Offline safety regressions; never invoke simctl or delete real devices."""
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("prepare_simulators", Path(__file__).with_name("prepare-hosted-simulators.py"))
preparation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preparation)

AVAILABLE = "00000000-0000-0000-0000-000000000001"
UNAVAILABLE = "00000000-0000-0000-0000-000000000002"
BOOTED = "00000000-0000-0000-0000-000000000003"


def inventory():
    return {"runtimes": [{"identifier": "com.apple.CoreSimulator.SimRuntime.watchOS-27-0", "version": "27.0", "isAvailable": False}],
            "devices": {"com.apple.CoreSimulator.SimRuntime.watchOS-27-0": [
        {"udid": AVAILABLE, "isAvailable": True, "state": "Shutdown"},
        {"udid": UNAVAILABLE, "isAvailable": False, "state": "Shutdown"},
        {"udid": BOOTED, "isAvailable": False, "state": "Booted"},
    ]}}


class HostedSimulatorPreparationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.environ = {"GITHUB_ACTIONS": "true", "GUS_RUNNER_ENVIRONMENT": "github-hosted", "RUNNER_TEMP": temporary.name}
        self.stdout = io.StringIO()
        self.stderr = io.StringIO()
        contexts = contextlib.ExitStack()
        self.addCleanup(contexts.close)
        contexts.enter_context(contextlib.redirect_stdout(self.stdout))
        contexts.enter_context(contextlib.redirect_stderr(self.stderr))
        self.runner = contexts.enter_context(patch.object(preparation.subprocess, "run"))

    def response(self, value="", code=0, stderr=""):
        return subprocess.CompletedProcess([], code, json.dumps(value) if isinstance(value, dict) else value, stderr)

    def test_only_exact_unavailable_shutdown_uuid_is_deleted_and_inventories_saved(self):
        before = inventory()
        after = copy.deepcopy(before)
        after["devices"][next(iter(after["devices"]))].pop(1)
        self.runner.side_effect = [self.response(before), self.response(), self.response(after)]
        evidence = preparation.prepare(self.environ)
        self.assertEqual([call.args[0] for call in self.runner.call_args_list], [
            ["xcrun", "simctl", "list", "--json"],
            ["xcrun", "simctl", "delete", UNAVAILABLE],
            ["xcrun", "simctl", "list", "--json"],
        ])
        self.assertEqual(json.loads((evidence / "before.json").read_text()), before)
        self.assertEqual(json.loads((evidence / "after.json").read_text()), after)
        self.assertEqual(json.loads((evidence / "result.json").read_text())["deletedDeviceIDs"], [UNAVAILABLE])
        self.assertIn('"runtimes":', self.stdout.getvalue())
        self.assertIn('"version": "27.0"', self.stdout.getvalue())
        self.assertIn("Simulator inventory before cleanup:", self.stdout.getvalue())
        self.assertIn("Simulator inventory after cleanup:", self.stdout.getvalue())

    def test_nonhosted_and_nonactions_environments_fail_before_tool_or_file_actions(self):
        for key, value in (("GUS_RUNNER_ENVIRONMENT", "self-hosted"), ("GUS_RUNNER_ENVIRONMENT", ""), ("GITHUB_ACTIONS", "false")):
            with self.subTest(key=key, value=value), self.assertRaises(RuntimeError):
                preparation.prepare({**self.environ, key: value})
        self.runner.assert_not_called()
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_missing_runner_temp_fails_before_tool_actions(self):
        with self.assertRaises(RuntimeError):
            preparation.prepare({**self.environ, "RUNNER_TEMP": ""})
        self.runner.assert_not_called()

    def test_available_devices_are_preserved_without_delete_calls(self):
        before = inventory()
        for device in next(iter(before["devices"].values())):
            device["isAvailable"] = True
        self.runner.side_effect = [self.response(before), self.response(before)]
        preparation.prepare(self.environ)
        self.assertTrue(all(call.args[0][2] == "list" for call in self.runner.call_args_list))

    def test_malformed_inventory_fails_before_any_delete(self):
        invalid = [None, {}, {"devices": []}, {"devices": {"runtime": {}}}]
        for field, value in (("udid", "all"), ("udid", "--help"), ("isAvailable", "false"), ("isAvailable", None), ("state", None)):
            value_inventory = inventory()
            next(iter(value_inventory["devices"].values()))[1][field] = value
            invalid.append(value_inventory)
        duplicate = inventory()
        next(iter(duplicate["devices"].values()))[1]["udid"] = AVAILABLE.lower()
        invalid.append(duplicate)
        for value in invalid:
            self.runner.reset_mock()
            self.runner.side_effect = [self.response(json.dumps(value))]
            with self.subTest(value=value), self.assertRaises(ValueError):
                preparation.prepare(self.environ)
            self.assertEqual(self.runner.call_count, 1)

    def test_mutation_error_stops_without_further_deletion(self):
        self.runner.side_effect = [self.response(inventory()), self.response("delete failed\n", 1, "device error\n")]
        with self.assertRaises(RuntimeError):
            preparation.prepare(self.environ)
        self.assertEqual(self.runner.call_count, 2)
        self.assertIn("device error", self.stderr.getvalue())
        self.assertIn("delete failed", self.stdout.getvalue())

    def test_selected_device_remaining_or_unrelated_device_removed_fails(self):
        for remove_index in (None, 0):
            after = inventory()
            if remove_index is not None:
                next(iter(after["devices"].values())).pop(remove_index)
            self.runner.side_effect = [self.response(inventory()), self.response(), self.response(after)]
            with self.subTest(remove_index=remove_index), self.assertRaises(RuntimeError):
                preparation.prepare(self.environ)

    def test_inventory_errors_and_diagnostics_are_not_suppressed(self):
        self.runner.return_value = self.response("not JSON", 1, "warning: inventory issue\n")
        with self.assertRaises(RuntimeError):
            preparation.prepare(self.environ)
        self.assertEqual(self.runner.call_count, 1)
        self.assertIn("warning: inventory issue", self.stderr.getvalue())
        evidence = next(self.directory.iterdir())
        self.assertEqual((evidence / "before.stderr.txt").read_text(), "warning: inventory issue\n")

    def test_timeout_preserves_diagnostics_and_stops_before_mutation(self):
        self.runner.side_effect = subprocess.TimeoutExpired("simctl", 30, output=b"partial inventory", stderr=b"service stalled\n")
        with self.assertRaisesRegex(RuntimeError, "exit 124"):
            preparation.prepare(self.environ)
        self.assertEqual(self.runner.call_count, 1)
        evidence = next(self.directory.iterdir())
        self.assertEqual((evidence / "before.stdout.txt").read_text(), "partial inventory")
        self.assertEqual((evidence / "before.stderr.txt").read_text(), "service stalled\n")


if __name__ == "__main__":
    unittest.main()
