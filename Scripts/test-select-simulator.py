#!/usr/bin/env python3
"""Offline regressions for CI simulator family and SDK selection."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("select_simulator", Path(__file__).with_name("select-simulator.py"))
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)


def fixture(versions, runtime_family="tvOS"):
    inventory = {"runtimes": [], "devices": {}}
    for number, (version, name) in enumerate(versions, 1):
        identifier = f"com.apple.CoreSimulator.SimRuntime.{runtime_family}-" + version.replace(".", "-")
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

    def test_watch_uses_latest_available_sdk_compatible_uuid(self):
        inventory = fixture([("26.5", "Apple Watch Series 11"), ("27.2", "Apple Watch Series 12"), ("27.3", "Apple Watch Ultra 4")], "watchOS")
        self.assertEqual(selector.select_destination(inventory, "27.2", "watchOS"), "platform=watchOS Simulator,id=00000000-0000-0000-0000-000000000002")
        with self.assertRaises(ValueError):
            selector.select_destination(fixture([("27.3", "Apple Watch")], "watchOS"), "27.2", "watchOS")

    def test_vision_maps_xros_runtime_to_visionos_destination(self):
        inventory = fixture([("26.5", "Apple Vision Pro"), ("27.2", "Apple Vision Pro")], "xrOS")
        self.assertEqual(selector.select_destination(inventory, "27.2", "visionOS"), "platform=visionOS Simulator,id=00000000-0000-0000-0000-000000000002")
        with self.assertRaises(ValueError):
            selector.select_destination(fixture([("27.2", "Apple Vision Pro")], "visionOS"), "27.2", "visionOS")

    def test_watch_rejects_other_runtime_families_and_device_types(self):
        for family, name in (("tvOS", "Apple Watch"), ("iOS", "Apple Watch"), ("watchOS", "Apple TV")):
            with self.subTest(family=family, name=name), self.assertRaises(ValueError):
                selector.select_destination(fixture([("27.2", name)], family), "27.2", "watchOS")

    def test_watch_unavailable_old_runtime_and_invalid_uuid_are_excluded(self):
        inventory = fixture([("26.5", "Apple Watch"), ("27.2", "Apple Watch"), ("27.3", "Apple Watch")], "watchOS")
        inventory["runtimes"][1]["isAvailable"] = False
        inventory["devices"][inventory["runtimes"][2]["identifier"]][0]["isAvailable"] = False
        self.assertTrue(selector.select_destination(inventory, "27.3", "watchOS").endswith("000000000001"))
        inventory["devices"][inventory["runtimes"][0]["identifier"]][0]["udid"] = "invalid"
        with self.assertRaises(ValueError):
            selector.select_destination(inventory, "27.3", "watchOS")
        with self.assertRaises(ValueError):
            selector.select_destination(fixture([("25.0", "Apple Watch")], "watchOS"), "27.2", "watchOS")

    def test_invalid_platform_or_sdk_has_no_generic_fallback(self):
        with self.assertRaises(ValueError):
            selector.select_destination(fixture([]), "27.2", "iOS")
        with self.assertRaises(ValueError):
            selector.select_destination(fixture([]), "invalid", "watchOS")


if __name__ == "__main__":
    unittest.main()
