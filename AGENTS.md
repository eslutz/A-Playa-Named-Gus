# AGENTS.md

## Repo map

Gus is an Apple-first, multiplatform SwiftUI Jellyfin client for iOS, iPadOS,
tvOS, visionOS, and macOS, with a focused watchOS companion (`GusWatch`).
The app bundle ID is `dev.ericslutz.gus`.

- `Sources/App`, `Features`, and `SharedUI`: app entry, screens, and reusable views.
- `Sources/Models`, `Providers`, `Services`, and `Stores`: model, provider,
  transport/persistence, and observable state boundaries.
- `Sources/Platform`: substantial platform differences. `Watch`, `TopShelf`,
  `Immersive`, and `CarPlay` hold platform-specific features under `Sources`.
- `project.yml` and `Config/`: canonical project and build settings.
  `A Playa Named Gus.xcodeproj` and its shared dependency pins are tracked for
  Xcode Cloud discovery. User workspace state is not tracked.
- `Tests/` and `Scripts/`: test suites and validation/maintenance tools.
  See the [engineering guide](Documentation/engineering-guide.md).

## Non-negotiables

- Prefer native Apple frameworks and adaptive system UI over bespoke or
  third-party code. Preserve native appearance and behaviors. If native APIs
  cannot meet the requirement, explain the exception in the change.
- Runtime dependencies are limited to the Jellyfin SDK and Readium for iOS/iPadOS
  EPUB reading. Do not add runtime dependencies without an explicit ADR.
  Match the [ADRs](Documentation/adr/) and the version pins in project settings.
- Study Swiftfin patterns and SDK call shapes as reference only; **never copy
  its code**. Implement with Gus’s own native stack.
- Preserve OS 26 compatibility on every target, including Watch and Top Shelf.
  Use Xcode 27.2 or later, guard newer OS 27 APIs, and preserve useful OS 26
  fallbacks. The exact deployment and language settings live in project files;
  successful compilation does not establish old-OS runtime acceptance.
- Build only for Apple Silicon. Keep arm64 for simulator/macOS targets and the
  SDK-required ARM device variants for Watch. Do not add Intel or universal Mac
  builds or weaken existing architecture/concurrency settings.
- Use SwiftUI Observation (`@MainActor @Observable`, `@Environment`) and
  structured async code rather than Combine. Put substantial platform behavior
  behind `Sources/Platform/`; small guarded view modifiers may stay inline.
  Guard availability and capabilities per platform.
- Keep credentials in Keychain and state account-scoped. Use privacy-safe
  `OSLog`, not `print`; do not add analytics or log credentials/private data.
- Put user-visible text in `Resources/Localizable.xcstrings`. Preserve
  accessibility and native loading, empty, and error states.
- For UI work use the current Sketch handoff and Apple design guidance.
  Do not claim verified native Liquid Glass fidelity from approximations or
  infer runtime acceptance from design coverage.

## Xcode MCP

- For Apple API/platform research, use `DocumentationSearch` on the `xcode` MCP
  server first when available. Also use relevant research sources or tools
  explicitly included in the request, alongside Xcode MCP when requested.
  If Xcode MCP is unavailable, fails, or is insufficient, use official
  [Apple Developer documentation](https://developer.apple.com/documentation/).
  Cite Apple sources, disclose fallback, and separate documented behavior from
  inference on each affected platform.
- Do not open a workspace or invoke build, test, or edit tools solely for a
  docs lookup when the search can run without them or the fallback is sufficient.
- For project-aware work, call `XcodeListWorkspaces` and match the absolute
  path to the current checkout. If needed, use `XcodeOpenWorkspace` to open
  that checkout’s `A Playa Named Gus.xcodeproj` when the tool is available.
  With an already-enabled headless server, `xcrun mcp-server open "<absolute project path>"`
  is another option; otherwise ask the user to open the matching project in Xcode.
  Use its returned workspace identifier for project tools. Report unavailable
  tools or permission blocks rather than changing access or using another checkout.

## Build and validation

- Docs-only changes need relevant documentation/configuration checks, not
  XcodeGen, app builds, or simulator tests.
- Run `xcodegen generate` if changes affect generation inputs, including adding,
  removing, or moving source/resources or editing generator configuration.
  Include affected tracked project changes; verify pins/snapshot with
  `python3 Scripts/check-cloud-project.py` when relevant.
- For routine code changes run focused lint, build, and test checks for the
  affected code and platforms. Discover installed destinations before using them;
  report exactly what ran, what passed, and what remains unverified.
- **Run app tests and runtime verification locally.** Use native Apple Silicon
  for macOS (`platform=macOS,arch=arm64`). For iOS, iPadOS, tvOS, visionOS and
  watchOS, use Apple simulators one at a time with an explicit platform and
  simulator UDID. Record behavior that requires other physical devices or
  unavailable entitlements as unverified.
- GitHub validation covers static/configuration checks and the native arm64
  macOS build. Keep app tests and simulator builds out of GitHub CI and
  Xcode Cloud.
- Keep builds warning-free. Never suppress diagnostics to obtain a pass.
  The only exception is the documented, explicitly logged hosted native arm64
  macOS simulator-discovery warning; it does not apply to archives or local
  validation. See the [warning policy](Documentation/AppStore/warning-policy.md).
- Keep raw logs, result bundles, screenshots, exports, and validation artifacts
  outside Git. Do not present older evidence as a run for the current candidate.

## Review and release

- Changes to `main` go through a PR with Validation Scope, Lint, Docs and Config,
  and Build macOS passing. Record relevant local test results in the PR.
  Verify live enforcement separately.
  Follow the [PR checklist](.github/pull_request_template.md).
- Release qualification is separate from routine validation: require
  exact-candidate local test evidence, the required checks, and separately
  authorized native archives. Verify live Xcode Cloud actions, signing, raw
  diagnostics, and distribution scope before running an authorized release.
  Archive/export, TestFlight processing/group availability, and tester
  installation are distinct outcomes.
- Use the [pipeline policy](Documentation/AppStore/pipeline-policy.md) and
  [signing capability guide](Documentation/AppStore/signing-capabilities.md).
  Do not re-enable or start superseded hosted simulator workflows.
- Track actionable work and scope changes in [GitHub issues](https://github.com/eslutz/A-Playa-Named-Gus/issues).
  Update the sibling `Gus.wiki` for user-visible behavior and the sibling
  `Gus.website` when public claims, screenshots, support, privacy, accessibility,
  age suitability, or brand assets change. Keep relevant updates with the app
  change; follow the [contributor guide](CONTRIBUTING.md).

## Task-specific links

Start with the [documentation index](Documentation/README.md) for the full map.

- [Local build, test, demo, and capture commands](Documentation/local-validation.md)
- [Architecture and platform boundaries](Documentation/engineering-guide.md)
  and [behavior and regression guide](Documentation/behavior-and-regression-guide.md)
- [Sketch maintenance and handoffs](Design/README.md) and
  [iPad client capabilities](Documentation/ipad-capabilities.md)
- [Icon Composer and brand sources](Documentation/AppStore/icon-composer-source.md),
  [demo server](Documentation/demo-server.md), and
  [diagnostics and reliability](Documentation/diagnostics-reliability.md)
- [Review decisions and comparison workflow](Documentation/Reviews/README.md)
