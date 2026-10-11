#!/usr/bin/env python3
"""Exercise Apple's ci_scripts working directory and bootstrap failure boundaries."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parent.parent / "ci_scripts/ci_post_clone.sh"


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gus-bootstrap-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "ci_scripts").mkdir()
        (self.root / "Config").mkdir()
        shutil.copy2(SOURCE, self.root / "ci_scripts/ci_post_clone.sh")
        self.project = self.root / "A Playa Named Gus.xcodeproj"
        self.project.mkdir()
        (self.project / "project.pbxproj").write_text("fixture project")
        self.lock = self.project / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        self.lock.parent.mkdir(parents=True)
        self.lock.write_text("fixture pins")
        tools = self.root / "bin"
        tools.mkdir()
        for tool in ("xcodegen", "brew"):
            script = tools / tool
            script.write_text('#!/bin/sh\nprintf "%s" "$PWD" > invoked-tool\n')
            script.chmod(0o755)
        self.env = {**os.environ, "CI_XCODE_CLOUD": "TRUE", "CI_TEAM_ID": "QS3GC3CT43",
                    "PATH": f"{tools}:/usr/bin:/bin"}
        self.env.pop("CI_PRIMARY_REPOSITORY_PATH", None)

    def run_script(self):
        return subprocess.run(["/bin/sh", "ci_post_clone.sh"], cwd=self.root / "ci_scripts",
                              env=self.env, capture_output=True, text=True)

    def test_cloud_from_scripts_directory_preserves_project_and_pins(self):
        self.assertEqual(self.run_script().returncode, 0)
        config = (self.root / "Config/Local.xcconfig").read_text()
        self.assertIn("CODE_SIGNING_ALLOWED = YES", config)
        self.assertIn("DEVELOPMENT_TEAM = QS3GC3CT43", config)
        self.assertEqual((self.project / "project.pbxproj").read_text(), "fixture project")
        self.assertEqual(self.lock.read_text(), "fixture pins")
        self.assertFalse((self.root / "invoked-tool").exists())

    def test_explicit_repository_path(self):
        self.env["CI_PRIMARY_REPOSITORY_PATH"] = str(self.root)
        self.assertEqual(self.run_script().returncode, 0)

    def test_cloud_team_uuid_keeps_developer_signing_team(self):
        self.env["CI_TEAM_ID"] = "1f3fb703-e0b0-42fc-bc0b-d00a3bfdf58e"
        self.assertEqual(self.run_script().returncode, 0)
        config = (self.root / "Config/Local.xcconfig").read_text()
        self.assertIn("DEVELOPMENT_TEAM = QS3GC3CT43", config)
        self.assertNotIn(self.env["CI_TEAM_ID"], config)
        self.assertEqual((self.project / "project.pbxproj").read_text(), "fixture project")
        self.assertEqual(self.lock.read_text(), "fixture pins")
        self.assertFalse((self.root / "invoked-tool").exists())

    def test_wrong_team_rejected_before_signing_write(self):
        self.env["CI_TEAM_ID"] = "WRONGTEAM"
        self.assertEqual(self.run_script().returncode, 65)
        self.assertFalse((self.root / "Config/Local.xcconfig").exists())

    def test_wrong_cloud_uuid_rejected_before_signing_write(self):
        self.env["CI_TEAM_ID"] = "00000000-0000-4000-8000-000000000001"
        self.assertEqual(self.run_script().returncode, 65)
        self.assertFalse((self.root / "Config/Local.xcconfig").exists())

    def test_missing_cloud_team_rejected_before_signing_write(self):
        self.env.pop("CI_TEAM_ID")
        self.assertEqual(self.run_script().returncode, 65)
        self.assertFalse((self.root / "Config/Local.xcconfig").exists())

    def test_missing_lock_rejected(self):
        self.lock.unlink()
        self.assertEqual(self.run_script().returncode, 66)
        self.assertFalse((self.root / "Config/Local.xcconfig").exists())

    def test_missing_project_rejected(self):
        (self.project / "project.pbxproj").unlink()
        self.assertEqual(self.run_script().returncode, 66)

    def test_local_generation_uses_repository_root(self):
        self.env.pop("CI_XCODE_CLOUD")
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(Path((self.root / "invoked-tool").read_text()).resolve(), self.root.resolve())


if __name__ == "__main__":
    unittest.main()
