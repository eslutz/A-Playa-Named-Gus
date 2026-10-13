# Warning-free build and release policy

Requested October 13, 2026. A build with any warning or error is not accepted,
even when Xcode or Xcode Cloud reports success.

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
- Required GitHub checks must pass on the fix commit. After its reviewed merge,
  Xcode Cloud must report zero warnings and errors in every test and archive
  action for iOS, macOS, tvOS and visionOS, including embedded Watch and Top Shelf.
  Successful signed export and TestFlight processing remain separate gates.

## Build 16 findings

Build 16 succeeded but had 16 warning occurrences across its eight build/test
jobs. The occurrences reduce to three distinct diagnostics:

1. `HomeView.swift`: the closure passed to `Optional.map` in a `guard` was
   ambiguous with the guard body. Parenthesize the closure argument.
2. `LibraryStoreTests.swift`: the test URL protocol declared an unchecked
   conformance despite Foundation marking its inherited Sendable conformance
   unavailable. Remove that conformance from the Foundation subclass.
3. The same test captured the nonsendable protocol in an asynchronous Sendable
   task. Keep the protocol at the Foundation boundary and serialize delayed
   response delivery/cancellation through a separately synchronized weak handle.

The local Xcode 27.1 matrix additionally exposed Watch metadata extraction without
an AppIntents.framework dependency. Link the system framework explicitly, as the
other targets do; do not disable metadata extraction to hide the warning.

Verify both normal responses and cancellation/filter replacement through the
existing serialized `LibraryStoreTests` suite. Preserve complete concurrency
checking. Cloud Build 16 remains historical evidence of the warnings, not proof
that the fix has passed Cloud.

## Local verification of the fix

Xcode 27.1 RC (27A9275) compiled the app and unit-test targets for macOS, iOS,
tvOS and visionOS with zero emitted warnings or errors. The iOS lane includes
the Watch companion; tvOS includes Top Shelf. The final iOS rerun was clean after
adding Watch's framework dependency. Eight LibraryStoreTests passed with zero
failures/skips. Six warning-gate regression tests, thirteen Cloud bootstrap tests,
and all eight static release checks passed.

Hosted required CI and a new provisioned Xcode Cloud run must still verify the
reviewed fix commit. Local compilation does not qualify a Cloud release.
