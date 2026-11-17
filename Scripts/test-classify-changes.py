#!/usr/bin/env python3
"""Protect CI coverage when non-source changes affect the app or its checks."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("changes", Path(__file__).with_name("classify-changes.py"))
changes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(changes)


class ClassificationTests(unittest.TestCase):
    def test_every_build_input_requires_matrix(self):
        paths = ["Sources/Player.swift", "Tests/Fixtures/README.md", "Resources/Localizable.xcstrings",
                 "Config/Shared.xcconfig", "Scripts/validate-release.py", "ci_scripts/ci_post_clone.sh",
                 ".github/workflows/ci.yml", "project.yml", ".swiftformat", "Package.resolved",
                 "A Playa Named Gus.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"]
        for path in paths:
            with self.subTest(path=path):
                self.assertTrue(changes.requires_full_validation([path]))

    def test_prose_only_still_runs_lightweight_jobs(self):
        self.assertFalse(changes.requires_full_validation(["README.md", "Documentation/adr/decision.md"]))

    def test_mixed_and_unknown_inputs_default_to_full(self):
        self.assertTrue(changes.requires_full_validation(["README.md", "Tests/new.swift"]))
        self.assertTrue(changes.requires_full_validation(["new-build-setting.json"]))


if __name__ == "__main__":
    unittest.main()
