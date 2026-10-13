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
    def run_tool(self, message):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        output = Path(temporary.name)
        results = []
        command = [sys.executable, "-c", "import sys; print(sys.argv[1])", message]
        return command, output, results

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
