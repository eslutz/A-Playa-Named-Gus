# Diagnostics & Reliability

Status: required App Store readiness work before public release.

A Playa Named Gus should use Apple-native diagnostics and reporting wherever possible.
The goal is to improve stability, performance, and supportability without adding
third-party analytics platforms, advertising identifiers, behavioral tracking, or
diagnostic collection unrelated to application health.

## Principles

- Prefer Apple-provided diagnostics: App Store Connect, Xcode Organizer, MetricKit,
  Instruments, unified logging, and TestFlight feedback.
- Keep diagnostics focused on app health: crashes, hangs, launch performance,
  responsiveness, memory, CPU, energy, disk writes, network transfer volume where
  available, and playback startup reliability.
- Do not collect usage analytics, advertising identifiers, behavioral tracking data, or
  product analytics unless a future roadmap item explicitly approves that scope.
- Keep App Store privacy answers, `Documentation/AppStore/privacy-labels.md`,
  `Documentation/AppStore/privacy-policy.md`, the hosted `/privacy` page, and
  `Resources/PrivacyInfo.xcprivacy` aligned with the implemented behavior.

## Native Crash Reporting

- Ensure release and TestFlight builds produce symbolicated crash diagnostics in Xcode
  Organizer and App Store Connect.
- Establish a crash triage workflow covering owner, cadence, severity, affected platform,
  reproduction notes, linked issue, and release-note impact.
- Verify App Store privacy disclosures account for any crash or diagnostics data made
  available to the developer through Apple tooling.

### dSYM / symbolication path (Xcode Cloud)

Release builds use `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` (Xcode default for
archives), and Xcode Cloud archive actions upload dSYMs to App Store Connect
automatically with each build. Verification per release: open the build in Xcode
Organizer → Crashes and confirm frames symbolicate; if a crash shows raw addresses,
download dSYMs for that build from App Store Connect → TestFlight → Build Metadata and
re-symbolicate locally with `symbolicatecrash`/`atos`.

## MetricKit Integration

Integrate MetricKit where Apple supports it across Gus's shipped platforms. Document any
platform limitations instead of falling back to a third-party analytics SDK.

Implementation: `MetricKitCollector` (`Sources/Services/MetricKitCollector.swift`)
subscribes to `MXMetricManager` and normalizes payloads into `DiagnosticSummary` records
persisted by `DiagnosticSummaryStore`. Platform coverage:

| Platform | MetricKit support |
|---|---|
| iOS / iPadOS | Metric + diagnostic payloads. |
| visionOS | Metric + diagnostic payloads. |
| macOS | Diagnostic payloads only (Apple does not deliver `MXMetricPayload` on macOS). |
| tvOS | Not available — Apple ships no MetricKit on tvOS. Crash visibility relies on Xcode Organizer / App Store Connect; no third-party SDK substitutes. |

Collect and review available MetricKit payloads for:

- Crash diagnostics.
- Hang diagnostics.
- App launch performance.
- Responsiveness metrics.
- Memory usage metrics.
- CPU usage metrics.
- Energy impact metrics.
- Disk write metrics.
- Network transfer metrics where available.

The internal diagnostics abstraction is `DiagnosticsHub`
(`Sources/Services/DiagnosticsHub.swift`): feature code records privacy-safe lifecycle
markers (launch, server connection attempt, library load start/finish, playback startup
start/finish, search request, download state transitions) and signpost intervals there,
never against MetricKit directly. Redaction is structural — `DiagnosticEvent` cases carry
only numeric/boolean payloads, so no person, server, media title, token, password, or
private library value can enter the diagnostics stream.

## Performance Baselines

Establish and document baselines for:

- Initial launch.
- Cold start.
- Warm start.
- Server connection.
- Library loading.
- Media playback startup.
- Navigation responsiveness.
- Search performance.

Baseline reports should identify platform, OS version, device or simulator class, build
configuration, data set, network condition, measurement tool, and acceptable regression
thresholds. Prefer XCTest measurements, Instruments, MetricKit payload review, and
repeatable local scripts over custom telemetry services.

## Regression Monitoring

Add reporting that makes regressions visible over time:

- Store baseline summaries in source-controlled documentation or generated artifacts that
  can be compared between releases.
- Record significant performance improvements and regressions in release notes and project
  planning.
- For playback-specific regressions, track startup delay, stream-selection path, direct
  play versus transcode behavior, and platform affected without recording private media
  titles or server URLs.

## Review Process

After major releases, TestFlight builds, and App Store releases, review all metric
categories in the MetricKit Integration section above, plus playback startup and
playback reliability regressions.

Prioritize fixes by:

- Frequency.
- User impact.
- Platform affected.
- Severity.
- Whether the issue blocks App Review, TestFlight, or a public release.

Each recurring issue should have a linked issue or planning note, a target release, and a
decision about whether it belongs in a hotfix, the next minor release, or a future
milestone.

## Privacy Requirements

- MetricKit summaries and app-owned diagnostic markers must avoid Jellyfin tokens,
  passwords, exact server URLs, private media titles, usernames, and other sensitive data.
- Privacy labels and privacy policy text must describe diagnostic collection accurately
  once implemented, including whether Apple-provided crash/diagnostics reports are visible
  to the developer.
- User-initiated diagnostic export remains outside this initial implementation and is
  tracked as a Future Features item.

## Acceptance Checklist

- [ ] Crash diagnostics are available through Xcode Organizer and App Store Connect for
      TestFlight or release builds. *(Requires TestFlight builds — blocked on Xcode Cloud
      signing and upload.)*
- [x] dSYM / symbolication workflow is documented for Xcode Cloud archives.
- [x] MetricKit is integrated where supported across iOS, iPadOS, tvOS, visionOS, and
      macOS, with any platform gaps documented. *(`MetricKitCollector`; tvOS gap and
      macOS diagnostics-only limit documented above.)*
- [ ] Crash, hang, launch, responsiveness, memory, CPU, energy, disk write, and available
      network-transfer diagnostics are reviewed through Apple-native tooling. *(Recurring
      post-TestFlight review activity.)*
- [x] Internal diagnostics abstraction exists and feature code is not directly coupled to
      third-party analytics or tracking services. *(`DiagnosticsHub` + structural
      redaction; no third-party SDK.)*
- [x] All performance baselines in the Performance Baselines section are documented.
      *(`Documentation/AppStore/performance-baselines.md`: XCTest + launch-script numbers
      recorded; live-flow signpost baselines defined with collection plan against the
      demo server.)*
- [x] Regression review cadence and triage process are documented. *(Review Process and
      Regression Monitoring sections above.)*
- [x] Privacy labels, privacy policy, and hosted `/privacy` page are updated to match the
      implemented diagnostic behavior. *(privacy-labels.md Diagnostics section and
      privacy-policy.md Diagnostics section; the hosted `/privacy` page adapts from
      privacy-policy.md when published.)*
