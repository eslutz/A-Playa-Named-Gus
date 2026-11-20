# Warning-free build and release policy

Reject warnings and errors even when the build tool exits successfully.

## Required checks

- All Gus app, Watch, extension, unit-test and UI-test targets inherit
  `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` and `GCC_TREAT_WARNINGS_AS_ERRORS = YES`
  from the project-level settings in `project.yml`, in Debug and Release.
- Do not suppress warnings, weaken concurrency checks, or disable these settings.
  Fix the cause. Do not force command-line warning flags onto Swift package
  targets: Xcode supplies package warning flags independently, and its built-in
  suppression flag conflicts with a global Swift warnings-as-errors override.
- Local release validation rejects every emitted `warning:` or `error:` in raw
  command logs, including noncompiler diagnostics and tools that exit zero.
  `Scripts/test-release-warning-gate.py` checks that rejection explicitly.
- GitHub package resolution, build and test commands stream through
  `Scripts/run-warning-free.py`, which applies the same diagnostic gate and
  preserves the command's failure status.
- Verify required PR checks and exact-candidate evidence under the
  [pipeline policy](pipeline-policy.md). For an authorized native archive,
  inspect raw archive/export logs as well as Xcode Cloud issues. Empty issue
  lists, successful upload, TestFlight processing, and tester installation
  establish different outcomes.

## Authorized hosted simulator-discovery exception

This exception is limited to the observed Xcode `DVTiPhoneSimulator.m:661` warning
immediately followed by a nil SimDevice architecture detail with a null simulator
runtime is waived. Native hosted macOS commands must explicitly opt in and select
`platform=macOS,arch=arm64`. Each occurrence and the final count remain in raw logs.
Unknown/malformed assertions, compiler/linker/asset warnings, errors, Intel output,
and nonzero tool exits still fail. Local validation and archives retain strict gates;
this exception does not authorize hosted simulator builds or tests.
