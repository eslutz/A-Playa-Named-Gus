#!/usr/bin/env python3
"""Offline regressions for CI's tvOS simulator selection."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("select_simulator", Path(__file__).with_name("select-simulator.py"))
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)


def fixture(versions):
    inventory = {"runtimes": [], "devices": {}}
    for number, (version, name) in enumerate(versions, 1):
        identifier = "com.apple.CoreSimulator.SimRuntime.tvOS-" + version.replace(".", "-")
        inventory["runtimes"].append({"identifier": identifier, "version": version, "isAvailable": True})
        inventory["devices"][identifier] = [{"name": name, "isAvailable": True, "udid": f"00000000-0000-0000-0000-{number:012d}"}]
    return inventory


class SimulatorSelectionTests(unittest.TestCase):
    def test_new_runtime_with_renamed_device_uses_uuid(self):
        inventory = fixture([("27.0", "Apple TV 4K (3rd generation)"), ("27.2", "Apple TV 4K (4th generation)")])
        self.assertEqual(selector.select_destination(inventory), "platform=tvOS Simulator,id=00000000-0000-0000-0000-000000000002")

    def test_newer_runtime_than_sdk_is_excluded(self):
        inventory = fixture([("27.0", "Apple TV 4K (3rd generation)"), ("27.2", "Apple TV 4K (4th generation)")])
        self.assertTrue(selector.select_destination(inventory, "27.1").endswith("000000000001"))
        self.assertTrue(selector.select_destination(inventory, "27.2").endswith("000000000002"))

    def test_no_sdk_compatible_runtime_fails_closed(self):
        with self.assertRaises(ValueError):
            selector.select_destination(fixture([("27.3", "Apple TV")]), "27.2")
        with self.assertRaises(ValueError):
            selector.select_destination(fixture([]), "invalid")

    def test_versions_sort_numerically(self):
        inventory = fixture([("27.9", "Apple TV"), ("27.10", "Apple TV")])
        self.assertTrue(selector.select_destination(inventory).endswith("000000000002"))

    def test_unavailable_runtime_and_device_are_excluded(self):
        inventory = fixture([("27.0", "Apple TV"), ("27.2", "Apple TV"), ("27.3", "Apple TV")])
        inventory["runtimes"][1]["isAvailable"] = False
        inventory["devices"][inventory["runtimes"][2]["identifier"]][0]["isAvailable"] = False
        self.assertTrue(selector.select_destination(inventory).endswith("000000000001"))

    def test_prefers_full_resolution_4k(self):
        inventory = fixture([("27.2", "Apple TV 4K (4th generation)")])
        devices = next(iter(inventory["devices"].values()))
        devices.append({"name": "Apple TV 4K (4th generation) (at 1080p)", "isAvailable": True, "udid": "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"})
        self.assertTrue(selector.select_destination(inventory).endswith("000000000001"))

    def test_old_runtime_or_invalid_uuid_fails_closed(self):
        inventory = fixture([("25.0", "Apple TV"), ("27.2", "Apple TV")])
        inventory["devices"][inventory["runtimes"][1]["identifier"]][0]["udid"] = "not-a-uuid"
        with self.assertRaisesRegex(ValueError, "No available Apple TV"):
            selector.select_destination(inventory)

    def test_other_platform_is_not_selected(self):
        inventory = fixture([("27.2", "Apple TV")])
        inventory["runtimes"][0]["identifier"] = "com.apple.CoreSimulator.SimRuntime.iOS-27-2"
        with self.assertRaises(ValueError):
            selector.select_destination(inventory)


if __name__ == "__main__":
    unittest.main()
