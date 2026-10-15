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
        shutil.copy2(SOURCE.parent.parent / "Config/Architecture.xcconfig", self.root / "Config/Architecture.xcconfig")
        self.env["XCODE_XCCONFIG_FILE"] = str((self.root / "Config/Architecture.xcconfig").resolve())

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


    def run_pre_build(self, platform="macOS", action="build-for-testing"):
        scripts = SOURCE.parent
        for name in ("ci_pre_xcodebuild.sh", "gus-macos-unit.entitlements"):
            shutil.copy2(scripts / name, self.root / "ci_scripts" / name)
        env = {**self.env, "CI_PRODUCT_PLATFORM": platform, "CI_XCODEBUILD_ACTION": action}
        return subprocess.run(["/bin/sh", "ci_pre_xcodebuild.sh"], cwd=self.root / "ci_scripts",
                              env=env, capture_output=True, text=True)

    def test_cloud_test_execution_does_not_require_checkout_or_build_configuration(self):
        # Cloud distributes compiled products and ci_scripts to separate test runners.
        # Neither the repository nor its global build configuration is needed there.
        shutil.rmtree(self.root / "Config")
        self.env["CI_PRIMARY_REPOSITORY_PATH"] = str(self.root / "absent-checkout")
        for platform in ("iOS", "macOS", "tvOS", "visionOS"):
            for configuration in (None, str(self.root / "Config/Architecture.xcconfig")):
                with self.subTest(platform=platform, configuration=configuration):
                    if configuration is None:
                        self.env.pop("XCODE_XCCONFIG_FILE", None)
                    else:
                        self.env["XCODE_XCCONFIG_FILE"] = configuration
                    result = self.run_pre_build(platform=platform, action="test-without-building")
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertFalse((self.root / "Config/Local.xcconfig").exists())

    def test_cloud_compilation_actions_still_require_architecture_configuration(self):
        self.env.pop("XCODE_XCCONFIG_FILE")
        for platform in ("iOS", "macOS", "tvOS", "visionOS"):
            for action in ("build", "build-for-testing", "archive", "analyze"):
                with self.subTest(platform=platform, action=action):
                    result = self.run_pre_build(platform=platform, action=action)
                    self.assertEqual(result.returncode, 65)
                    self.assertIn("Apple Silicon enforcement missing", result.stderr)

    def test_cloud_rejects_wrong_global_configuration(self):
        self.env["XCODE_XCCONFIG_FILE"] = "/tmp/other.xcconfig"
        self.assertEqual(self.run_pre_build(platform="iOS").returncode, 65)

    def test_cloud_rejects_missing_architecture_file(self):
        (self.root / "Config/Architecture.xcconfig").unlink()
        self.assertEqual(self.run_pre_build(action="archive").returncode, 65)

    def test_global_configuration_excludes_intel_and_preserves_watch_arm(self):
        config = (self.root / "Config/Architecture.xcconfig").read_text()
        self.assertIn("ARCHS = arm64", config)
        self.assertIn("EXCLUDED_ARCHS = x86_64 x86_64h i386", config)
        self.assertIn("ARCHS[sdk=watchos*] = $(ARCHS_STANDARD)", config)

    def test_cloud_rejects_missing_global_architecture_configuration(self):
        self.env.pop("XCODE_XCCONFIG_FILE")
        self.assertEqual(self.run_pre_build(platform="iOS").returncode, 65)

    def test_cloud_mac_unit_host_uses_unrestricted_sandbox_entitlements(self):
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(self.run_pre_build().returncode, 0)
        config = (self.root / "Config/Local.xcconfig").read_text()
        self.assertIn("gus-macos-unit.entitlements", config)
        import plistlib
        values = plistlib.loads((self.root / "ci_scripts/gus-macos-unit.entitlements").read_bytes())
        self.assertEqual(values, {"com.apple.security.app-sandbox": True,
                                 "com.apple.security.network.client": True,
                                 "com.apple.security.network.server": True})

    def test_cloud_archives_keep_production_signing(self):
        self.assertEqual(self.run_script().returncode, 0)
        before = (self.root / "Config/Local.xcconfig").read_bytes()
        self.assertEqual(self.run_pre_build(action="archive").returncode, 0)
        self.assertEqual((self.root / "Config/Local.xcconfig").read_bytes(), before)

    def test_cloud_ios_tests_keep_platform_signing(self):
        self.assertEqual(self.run_script().returncode, 0)
        before = (self.root / "Config/Local.xcconfig").read_bytes()
        self.assertEqual(self.run_pre_build(platform="iOS").returncode, 0)
        self.assertEqual((self.root / "Config/Local.xcconfig").read_bytes(), before)

    def test_cloud_mac_test_preparation_requires_bootstrap(self):
        self.assertEqual(self.run_pre_build().returncode, 66)


if __name__ == "__main__":
    unittest.main()
