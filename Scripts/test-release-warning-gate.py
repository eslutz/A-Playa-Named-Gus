#!/usr/bin/env python3
"""Prove release validation rejects diagnostics even when the tool exits zero."""
import importlib.util
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release_validation", Path(__file__).with_name("validate-release.py"))
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


class WarningGateTests(unittest.TestCase):
    def test_xcode_commands_exclude_intel_without_affecting_watch_arm_variants(self):
        command = validation.apple_silicon_command(["xcodebuild", "ARCHS=arm64_32", "archive"])
        self.assertIn("EXCLUDED_ARCHS=x86_64 i386", command)
        self.assertIn("ARCHS=arm64_32", command)
        self.assertIn("GUS_WATCH_DEBUG_DYLIB=NO", command)
        self.assertEqual(validation.apple_silicon_command(["python3", "test.py"]), ["python3", "test.py"])

    def test_explicit_intel_architecture_is_rejected(self):
        for arguments in (["ARCHS=x86_64"], ["ARCHS=arm64 x86_64"], ["-arch", "x86_64"]):
            with self.subTest(arguments=arguments), self.assertRaises(RuntimeError):
                validation.apple_silicon_command(["xcodebuild"] + arguments + ["build"])

    def run_tool(self, message):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        output = Path(temporary.name)
        results = []
        command = [sys.executable, "-c", "import sys; print(sys.argv[1])", message]
        return command, output, results

    def test_intel_compilation_is_rejected_even_when_the_tool_exits_zero(self):
        for message in ("SwiftCompile normal x86_64 file.swift", "SwiftDriver Package normal x86_64 com.apple.swift.compiler", "CompileC file.o file.c normal i386", "Ld App normal x86_64"):
            with self.subTest(message=message):
                command, output, results = self.run_tool(message)
                with self.assertRaises(RuntimeError):
                    validation.run(command, output, output, "intel", results)

    def test_ci_wrapper_rejects_unexpected_intel_compilation(self):
        wrapper = Path(__file__).with_name("run-warning-free.py")
        result = subprocess.run([sys.executable, str(wrapper), sys.executable, "-c", "print('SwiftCompile normal x86_64 file.swift', flush=True)"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)

    def test_clean_zero_exit_passes(self):
        command, output, results = self.run_tool("BUILD SUCCEEDED")
        validation.run(command, output, output, "clean", results)
        self.assertEqual(results[0]["exitCode"], 0)
        self.assertEqual(results[0]["diagnostics"], [])

    def test_runtime_service_log_is_not_a_build_diagnostic(self):
        command, output, results = self.run_tool(
            '2026-10-13 16:11:51.123 app[123:456] [Connection] service error: Error Domain=NSCocoaErrorDomain Code=4097'
        )
        validation.run(command, output, output, "runtime", results)
        self.assertEqual(results[0]["exitCode"], 0)

    def test_warning_zero_exit_fails(self):
        for message in ("file.swift:12: warning: ambiguous closure", "ld: warning: duplicate library",
                        "/path/Gus.xcodeproj: GusUITests: ld: warning: framework requires a newer deployment target", "warning: asset issue", "2026-10-13 appintentsmetadataprocessor[1:2] warning: metadata issue",
                        "2026-11-16 04:54:51.263 xcodebuild[9535:28731] [MT] DVTAssertions: Warning in DVTiPhoneSimulator.m:661",
                        "2026-11-16 05:39:37.000 Gus[123:456] No symbol named 'person.crop.circle.badge.gearshape' found in system symbol set"):
            with self.subTest(message=message):
                command, output, results = self.run_tool(message)
                with self.assertRaises(RuntimeError):
                    validation.run(command, output, output, "reject-warning", results)
                self.assertEqual(results[0]["exitCode"], 1)
                self.assertEqual(results[0]["diagnostics"], [message])

    def test_ci_wrapper_rejects_zero_exit_warning(self):
        wrapper = Path(__file__).with_name("run-warning-free.py")
        result = subprocess.run([sys.executable, str(wrapper), sys.executable, "-c",
                                 "print('warning: compiler diagnostic')"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("warning: compiler diagnostic", result.stdout)

    def test_ci_wrapper_rejects_timestamped_xcode_assertion_warning(self):
        wrapper = Path(__file__).with_name("run-warning-free.py")
        message = "2026-11-16 04:54:51.263 xcodebuild[9535:28731] [MT] DVTAssertions: Warning in DVTiPhoneSimulator.m:661"
        result = subprocess.run([sys.executable, str(wrapper), sys.executable, "-c",
                                 "import sys; print(sys.argv[1])", message], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn(message, result.stdout)

    def test_ci_wrapper_rejects_intel_before_launching_xcode(self):
        wrapper = Path(__file__).with_name("run-warning-free.py")
        result = subprocess.run([sys.executable, str(wrapper), "xcodebuild", "ARCHS=x86_64", "build"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 64)
        self.assertIn("Intel builds are unsupported", result.stderr)

    def test_ci_wrapper_preserves_failure_exit(self):
        wrapper = Path(__file__).with_name("run-warning-free.py")
        result = subprocess.run([sys.executable, str(wrapper), sys.executable, "-c", "raise SystemExit(7)"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 7)

    def test_error_zero_exit_fails(self):
        command, output, results = self.run_tool("error: export failed")
        with self.assertRaises(RuntimeError):
            validation.run(command, output, output, "reject-error", results)
        self.assertEqual(results[0]["exitCode"], 1)


class SimulatorSelectionTests(unittest.TestCase):
    def inventory(self, version):
        return {"devices": {
            f"com.apple.CoreSimulator.SimRuntime.iOS-{version}-0": [
                {"name": "iPhone 17", "udid": f"phone-{version}"},
                {"name": "iPad Pro", "udid": f"ipad-{version}"},
            ],
            f"com.apple.CoreSimulator.SimRuntime.tvOS-{version}-0": [
                {"name": "Apple TV 4K", "udid": f"tv-{version}"},
            ],
            f"com.apple.CoreSimulator.SimRuntime.watchOS-{version}-0": [
                {"name": "Apple Watch 40mm", "udid": f"watch-{version}"},
            ],
            f"com.apple.CoreSimulator.SimRuntime.xrOS-{version}-0": [
                {"name": "Apple Vision Pro", "udid": f"vision-{version}"},
            ],
        }}

    def test_older_installed_runtimes_cannot_satisfy_os26_floor(self):
        with patch.object(validation.subprocess, "check_output", return_value=json.dumps(self.inventory(25)).encode()):
            with self.assertRaisesRegex(RuntimeError, "below deployment target"):
                validation.destinations()

    def test_os26_is_eligible_without_selecting_other_projects_simulators(self):
        inventory = self.inventory(25)
        inventory["devices"].update(self.inventory(26)["devices"])
        inventory["devices"]["com.apple.CoreSimulator.SimRuntime.iOS-27-0"] = [
            {"name": "PumpSync Audit iPhone", "udid": "unrelated"},
        ]
        with patch.object(validation.subprocess, "check_output", return_value=json.dumps(inventory).encode()):
            selected = validation.destinations()
        self.assertEqual({key: item["udid"] for key, item in selected.items()}, {
            "ios": "phone-26", "ipad": "ipad-26", "tv": "tv-26", "watch": "watch-26", "vision": "vision-26",
        })


class SimulatorWaiverTests(unittest.TestCase):
    def setUp(self):
        import io
        self.io = io
        spec = importlib.util.spec_from_file_location("warning_wrapper", Path(__file__).with_name("run-warning-free.py"))
        self.wrapper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.wrapper)
        self.header = "2026-11-17 13:50:38.097 xcodebuild[4126:15620] [MT] DVTAssertions: Warning in DVTiOSFrameworks/IDEiOSSupportCore/DVTiPhoneSimulator.m:661\n"
        self.detail = "Details:  SimDevice native architecture is nil. Device: SimDevice : Apple TV (00000000-0000-0000-0000-000000000001) : state={ Shutdown } runtime={ com.apple.CoreSimulator.SimRuntime.tvOS-27-0: (null) }, supportedArches: (\n"
        self.command = ["xcodebuild", "-destination", "platform=macOS,arch=arm64", "build"]
        self.env = {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted"}

    def invoke(self, output, code=0, enabled=True, command=None, env=None):
        from unittest.mock import Mock
        process = Mock(stdout=self.io.StringIO(output))
        process.wait.return_value = code
        process.poll.return_value = code
        args = ["wrapper"] + ([self.wrapper.FLAG] if enabled else []) + (command or self.command)
        stream = self.io.StringIO()
        with patch.object(sys, "argv", args), patch.dict(self.wrapper.os.environ, self.env if env is None else env, clear=True), patch.object(self.wrapper.subprocess, "Popen", return_value=process) as launch, patch("sys.stdout", stream), patch("sys.stderr", stream):
            result = self.wrapper.main()
        return result, stream.getvalue(), launch.called

    def test_known_pair_is_logged_and_waived_only_with_opt_in(self):
        result, log, launched = self.invoke(self.header + self.detail)
        self.assertEqual(result, 0)
        self.assertTrue(launched)
        self.assertIn(self.header, log)
        self.assertIn(self.detail, log)
        self.assertIn("waiver: 1 occurrence", log)
        self.assertEqual(self.invoke(self.header + self.detail, enabled=False)[0], 1)

    def test_unrelated_warnings_errors_and_intel_remain_fatal(self):
        for diagnostic in ("warning: compiler problem", "ld: warning: library problem", "error: test failure", "SwiftCompile normal x86_64 file.swift"):
            with self.subTest(diagnostic=diagnostic):
                self.assertEqual(self.invoke(self.header + self.detail + diagnostic + "\n")[0], 1)

    def test_unknown_assertions_and_incomplete_pairs_remain_fatal(self):
        for output in (self.header, self.header + "Details: another assertion\n", self.header.replace(":661", ":662") + self.detail, self.header.replace("Warning", "Error") + self.detail, self.header + self.detail.replace("(null)", "ready")):
            with self.subTest(output=output):
                self.assertEqual(self.invoke(output)[0], 1)

    def test_tool_failure_is_never_waived(self):
        self.assertEqual(self.invoke(self.header + self.detail, code=65)[0], 65)

    def test_local_or_non_native_commands_are_rejected_before_launch(self):
        for command in (["python3", "fixture.py"], ["xcodebuild", "build"], ["xcodebuild", "-destination"], ["xcodebuild", "-destination", "platform=iOS Simulator,name=iPhone 17"], self.command + ["archive"], self.command + ["-destination", "platform=macOS"]):
            with self.subTest(command=command):
                result, _, launched = self.invoke("", command=command)
                self.assertEqual(result, 64)
                self.assertFalse(launched)
        for env in ({}, {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "self-hosted"}):
            result, _, launched = self.invoke("", env=env)
            self.assertEqual(result, 64)
            self.assertFalse(launched)

    def test_multiple_occurrences_are_counted(self):
        result, log, _ = self.invoke((self.header + self.detail) * 2)
        self.assertEqual(result, 0)
        self.assertIn("waiver: 2 occurrence", log)


if __name__ == "__main__":
    unittest.main()
