#!/usr/bin/env python3
"""Prove release validation rejects diagnostics even when the tool exits zero."""
import importlib.util
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest

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
        for message in ("file.swift:12: warning: ambiguous closure", "ld: warning: duplicate library", "warning: asset issue", "2026-10-13 appintentsmetadataprocessor[1:2] warning: metadata issue"):
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


if __name__ == "__main__":
    unittest.main()
