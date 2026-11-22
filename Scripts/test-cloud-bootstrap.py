#!/usr/bin/env python3
"""Exercise Apple's ci_scripts working directory and bootstrap failure boundaries."""
import os
import plistlib
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
        self.assertIn("GUS_WATCH_DEBUG_DYLIB = NO", config)
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
        for name in ("ci_pre_xcodebuild.sh", "gus-macos-unit.entitlements", "gus-widget-macos-unit.entitlements"):
            shutil.copy2(scripts / name, self.root / "ci_scripts" / name)
        env = {**self.env, "CI_PRODUCT_PLATFORM": platform, "CI_XCODEBUILD_ACTION": action}
        return subprocess.run(["/bin/sh", "ci_pre_xcodebuild.sh"], cwd=self.root / "ci_scripts",
                              env=env, capture_output=True, text=True)

    def test_pcc_archives_preserve_platform_and_watch_entitlements(self):
        self.env["CI_WORKFLOW"] = "Gus Internal TestFlight"
        capability = "com.apple.developer.private-cloud-compute"
        fixtures = {
            "iOS": ("iphoneos", "Gus-iOS", True),
            "macOS": ("macosx", "Gus", False),
            "xrOS": ("xros", "Gus-SharePlay", False),
            "watchOS": ("watchos", None, True),
            "tvOS": ("appletvos", None, False),
        }
        config_dir = self.root / "Config"
        generated_dir = self.root / "build/pcc-signing"
        for platform, (sdk, base, watch) in fixtures.items():
            with self.subTest(platform=platform):
                self.assertEqual(self.run_script().returncode, 0)
                for file in generated_dir.glob("*-PCC.entitlements"):
                    file.unlink()
                if watch:
                    shutil.copy2(SOURCE.parent.parent / "Config/GusWidgets.entitlements", config_dir)
                if base:
                    shutil.copy2(SOURCE.parent.parent / "Config" / f"{base}.entitlements", config_dir)
                result = self.run_pre_build(platform=platform, action="archive")
                self.assertEqual(result.returncode, 0, result.stderr)
                config = (config_dir / "Local.xcconfig").read_text()
                if platform == "tvOS":
                    self.assertNotIn("GUS_PCC_ENTITLED", config)
                    self.assertEqual(list(generated_dir.glob("*-PCC.entitlements")), [])
                    continue
                self.assertIn(f"GUS_PCC_ENTITLED[sdk={sdk}*] = YES", config)
                if base:
                    existing = plistlib.loads((config_dir / f"{base}.entitlements").read_bytes())
                    archive = plistlib.loads((generated_dir / f"{base}-PCC.entitlements").read_bytes())
                    self.assertEqual(archive, {**existing, capability: True})
                    self.assertIn(f"CODE_SIGN_ENTITLEMENTS[sdk={sdk}*] = build/pcc-signing/{base}-PCC.entitlements", config)
                if watch:
                    archive = plistlib.loads((generated_dir / "Gus-Watch-PCC.entitlements").read_bytes())
                    existing = plistlib.loads((config_dir / "GusWidgets.entitlements").read_bytes())
                    self.assertEqual(archive, {**existing, capability: True})
                    self.assertIn("GUS_PCC_ENTITLED[sdk=watchos*] = YES", config)
                    self.assertIn("GUS_WATCH_CODE_SIGN_ENTITLEMENTS = build/pcc-signing/Gus-Watch-PCC.entitlements", config)
                else:
                    self.assertNotIn("GUS_WATCH_CODE_SIGN_ENTITLEMENTS", config)

    def test_cloud_mac_test_execution_does_not_require_checkout_or_build_configuration(self):
        # Cloud distributes compiled products and ci_scripts to separate test runners.
        # Neither the repository nor its global build configuration is needed there.
        shutil.rmtree(self.root / "Config")
        self.env["CI_PRIMARY_REPOSITORY_PATH"] = str(self.root / "absent-checkout")
        for configuration in (None, str(self.root / "Config/Architecture.xcconfig")):
            with self.subTest(configuration=configuration):
                if configuration is None:
                    self.env.pop("XCODE_XCCONFIG_FILE", None)
                else:
                    self.env["XCODE_XCCONFIG_FILE"] = configuration
                result = self.run_pre_build(action="test-without-building")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse((self.root / "Config/Local.xcconfig").exists())

    def test_cloud_simulator_execution_is_rejected_without_a_checkout(self):
        shutil.rmtree(self.root / "Config")
        self.env["CI_PRIMARY_REPOSITORY_PATH"] = str(self.root / "absent-checkout")
        self.env.pop("XCODE_XCCONFIG_FILE")
        for platform in ("iOS", "tvOS", "xrOS", "visionOS", "watchOS", ""):
            with self.subTest(platform=platform):
                result = self.run_pre_build(platform=platform, action="test-without-building")
                self.assertEqual(result.returncode, 65)
                self.assertIn("Simulator builds and tests must run locally", result.stderr)
                self.assertNotIn("absent-checkout", result.stderr)

    def test_cloud_simulator_builds_and_tests_are_rejected_before_signing_changes(self):
        self.assertEqual(self.run_script().returncode, 0)
        before = (self.root / "Config/Local.xcconfig").read_bytes()
        for platform in ("iOS", "tvOS", "xrOS", "visionOS", "watchOS"):
            for action in ("build", "build-for-testing", "test", "test-without-building"):
                with self.subTest(platform=platform, action=action):
                    result = self.run_pre_build(platform=platform, action=action)
                    self.assertEqual(result.returncode, 65)
                    self.assertIn("Simulator builds and tests must run locally", result.stderr)
                    self.assertEqual((self.root / "Config/Local.xcconfig").read_bytes(), before)

    def test_cloud_unknown_action_or_platform_is_rejected(self):
        for platform, action in (("", "archive"), ("unknown", "archive"), ("visionOS", "archive"), ("macOS", ""), ("macOS", "unknown")):
            with self.subTest(platform=platform, action=action):
                result = self.run_pre_build(platform=platform, action=action)
                self.assertEqual(result.returncode, 65)
                self.assertIn("Simulator builds and tests must run locally", result.stderr)

    def test_local_pre_build_does_not_restrict_simulator_actions(self):
        self.env.pop("CI_XCODE_CLOUD")
        self.env.pop("XCODE_XCCONFIG_FILE")
        self.assertEqual(self.run_pre_build(platform="iOS").returncode, 0)

    def test_cloud_compilation_actions_still_require_architecture_configuration(self):
        self.env.pop("XCODE_XCCONFIG_FILE")
        for platform in ("iOS", "macOS", "tvOS", "xrOS", "watchOS"):
            actions = ("build", "build-for-testing", "test", "archive", "analyze") if platform == "macOS" else ("archive", "analyze")
            for action in actions:
                with self.subTest(platform=platform, action=action):
                    result = self.run_pre_build(platform=platform, action=action)
                    self.assertEqual(result.returncode, 65)
                    self.assertIn("Apple Silicon enforcement missing", result.stderr)

    def test_cloud_rejects_wrong_global_configuration(self):
        self.env["XCODE_XCCONFIG_FILE"] = "/tmp/other.xcconfig"
        result = self.run_pre_build()
        self.assertEqual(result.returncode, 65)
        self.assertIn("Apple Silicon enforcement missing", result.stderr)

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
        result = self.run_pre_build()
        self.assertEqual(result.returncode, 65)
        self.assertIn("Apple Silicon enforcement missing", result.stderr)

    def test_cloud_mac_unit_host_uses_unrestricted_sandbox_entitlements(self):
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(self.run_pre_build().returncode, 0)
        config = (self.root / "Config/Local.xcconfig").read_text()
        self.assertIn("gus-macos-unit.entitlements", config)
        self.assertIn("GUS_WIDGET_MAC_ENTITLEMENTS =", config)
        widget = self.root / "ci_scripts/gus-widget-macos-unit.entitlements"
        self.assertEqual(plistlib.loads(widget.read_bytes()), {"com.apple.security.app-sandbox": True})
        values = plistlib.loads((self.root / "ci_scripts/gus-macos-unit.entitlements").read_bytes())
        self.assertEqual(values, {"com.apple.security.app-sandbox": True,
                                 "com.apple.security.network.client": True,
                                 "com.apple.security.network.server": True})

    def test_cloud_archives_keep_production_signing(self):
        self.assertEqual(self.run_script().returncode, 0)
        before = (self.root / "Config/Local.xcconfig").read_bytes()
        # Cloud uses xrOS rather than the visionOS display name.
        for platform in ("iOS", "macOS", "tvOS", "xrOS", "watchOS"):
            for action in ("archive", "analyze"):
                with self.subTest(platform=platform, action=action):
                    self.assertEqual(self.run_pre_build(platform=platform, action=action).returncode, 0)
                    self.assertEqual((self.root / "Config/Local.xcconfig").read_bytes(), before)

    def test_cloud_mac_test_preparation_requires_bootstrap(self):
        self.assertEqual(self.run_pre_build().returncode, 66)


if __name__ == "__main__":
    unittest.main()
