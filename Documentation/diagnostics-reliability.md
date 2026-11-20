# Diagnostics and reliability

Use Apple-native tooling for app health, not product analytics, tracking, or
advertising. Keep the [App Store disclosures](AppStore/review-and-disclosures.md#app-store-privacy-answers),
[user-facing privacy policy](AppStore/privacy-policy.md), deployed policy, and
privacy manifest aligned with actual data practices.

## App-owned markers and privacy

Feature code records structured lifecycle events and signposts through
DiagnosticsHub, not directly through MetricKit. Codable event cases carry bounded
numeric or boolean values, not credentials, exact server URLs, private media
titles, usernames, or raw framework errors. Playback diagnostics cover preparation,
first playing/render observation, stalls, buffer/wait state, and cleanup; a client
marker does not prove what reached a display or that the server released a resource.

This redaction applies to Gus-owned events and normalized summaries, not to the
contents of separate Apple system crash reports. Gus does not automatically upload
its client export; the user decides whether and where to share it.

## MetricKit coverage

MetricKitCollector normalizes Apple payloads into DiagnosticSummaryStore. Use the
platform and available fields when interpreting a summary; absent fields do not
mean zero.

| Platform | What Gus normalizes |
| --- | --- |
| iOS, iPadOS, visionOS | First-draw launch, hang duration, peak memory, CPU, disk writes and network transfer totals when supplied; diagnostic counts for crash, hang, CPU and disk-write exceptions. |
| macOS | Diagnostic counts only; no app-owned MetricKit performance metric payloads. |
| tvOS, watchOS | No Gus MetricKit collector. Use the appropriate Apple diagnostics or the app's supported event export. |

Energy and other diagnostic categories may be investigated in Apple tools, but
Gus does not currently include a normalized energy metric in its summaries.

## Client log export and companion transfer

Settings → Developer → Client Logs prepares a bounded JSON export on iPhone,
iPad, Mac and Vision Pro, with up to 200 app events and 60 normalized summaries
where collected. It is not the full system log. Watch has no export screen.

- A paired Watch supplies events only when requested by iPhone. Capture and
  receipt timestamps are distinct because delivery can be delayed. A cached
  snapshot is not evidence of current Watch state.
- Apple TV sends a sanitized events-only snapshot to the chosen iPhone through
  Apple's DeviceDiscoveryUI/application-service connection, not an arbitrary LAN
  endpoint or cloud upload. iPhone shares through the system share sheet.
- Received snapshots pass byte/count limits and an event-field allowlist. Only
  one replaceable received snapshot is retained per companion.

iOS/Apple TV transfer depends on matching application-service declarations,
the same universal app and applicable Apple device, network and iCloud/Family
Sharing requirements. A matching bundle ID, clean build, or simulator result
does not verify actual discovery, transfer, reconnect/retry or TestFlight
eligibility. Verify paired iPhone/TV/Watch where separately authorized.

## Symbols and per-build triage

For each relevant authorized TestFlight/release archive, verify matching dSYMs
and whether the chosen export/upload included them. In Xcode Organizer or App
Store Connect, confirm observed crash frames symbolicate for that exact build.
If not, locate the matching dSYM and symbolicate locally with Apple tools such
as atos. Do not assume symbols are present because archive or upload succeeded.

Triage recurring crash, hang, responsiveness or playback problems by frequency,
impact, severity and platform. Record affected revision/build, reproduction,
and an issue with a clear next action. Check the current privacy disclosures
against any Apple-provided crash/diagnostics visibility before making claims.

## Measuring performance

- Use focused performance XCTest cases on an allowed lane. Compare matching
  platform, OS, configuration, toolchain, hardware, fixture and network
  conditions. Record thresholds and raw inputs externally.
- Instruments signposts under dev.ericslutz.gus include ServerConnect,
  LibraryLoad, PlaybackStartup and Search. Measure with the local demo server.
- Scripts/measure-launch-baseline.sh measures the simulator launch command, not
  first draw or the first usable frame. MetricKit's first-draw/hang summaries
  are separate evidence. Missing trace tables make the measurement inconclusive.
- Keep measurements, traces, screenshots and other evidence outside Git.
  Version procedures and stable decision thresholds, not dated run results.
  Follow [local validation](local-validation.md) and
  [release policy](AppStore/pipeline-policy.md) for scope and acceptance.
