# Performance Baselines

Initial baselines for the flows required by
[diagnostics-reliability.md](diagnostics-reliability.md). Two measurement layers exist:

1. **XCTest `measure` baselines** in `Tests/APlayaNamedGusTests/PerformanceBaselineTests.swift`
   cover hot pure-logic paths and run with the normal unit-test schemes on every platform.
2. **`DiagnosticsHub` signpost intervals** cover the live flows (server connect, library
   load, playback startup, search). Profile in Instruments with the `os_signpost`
   instrument filtered to subsystem `dev.ericslutz.gus`, category `Diagnostics`. Interval
   names: `ServerConnect`, `LibraryLoad`, `PlaybackStartup`, `Search`.
3. **Cold launch** is measured with `Scripts/measure-launch-baseline.sh` (coarse,
   repeatable simulator wall time) and, for precise device numbers, MetricKit's
   `histogrammedTimeToFirstDraw` summaries stored by `MetricKitCollector`.

## Recorded baselines

| Flow | Tool | Environment | Baseline | Regression threshold |
|---|---|---|---|---|
| Media item mapping (2000 DTOs) | XCTest `testMediaItemMapperThroughputBaseline` | iPhone 17 simulator, Debug, Xcode 26.5, macOS 26 host | avg 0.010 s | > +50% vs baseline |
| Server URL normalization (2000 inputs) | XCTest `testServerURLNormalizationBaseline` | iPhone 17 simulator, Debug | avg 0.006 s | > +50% vs baseline |
| Histogram math (10k buckets) | XCTest `testHistogramMathBaseline` | iPhone 17 simulator, Debug | avg 0.005 s | > +50% vs baseline |
| Cold launch (process spawn) | `Scripts/measure-launch-baseline.sh` | iPhone 17 simulator, Debug, 2026-06-10 | avg 351 ms (5 runs, post-warm-up) | > +25% vs last recorded run |
| Initial launch / warm start (time to first draw) | MetricKit `histogrammedTimeToFirstDraw` | TestFlight/device builds | collected post-TestFlight | reviewed per release |
| Server connection | Instruments signpost `ServerConnect` | local Jellyfin server (see `Scripts/demo-server`) | collected per release | reviewed per release |
| Library loading | Instruments signpost `LibraryLoad` | local Jellyfin server, demo library | collected per release | reviewed per release |
| Media playback startup | Instruments signpost `PlaybackStartup` | local Jellyfin server, demo library | collected per release | reviewed per release |
| Search | Instruments signpost `Search` | local Jellyfin server, demo library | collected per release | reviewed per release |
| Navigation responsiveness | MetricKit hang-time summaries + manual pass | device builds | collected post-TestFlight | reviewed per release |

Debug-configuration simulator numbers are relative baselines for catching regressions
between changes, not absolute performance claims; device/TestFlight numbers come from the
MetricKit summaries once builds flow through TestFlight.

## How to re-measure

- XCTest baselines: `xcodebuild test -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus
  iOS Unit Tests' -destination 'platform=iOS Simulator,name=iPhone 17'` and read the
  `measured [Time, seconds]` lines for `PerformanceBaselineTests`.
- Cold launch: `Scripts/measure-launch-baseline.sh "iPhone 17" 5`.
- Flow intervals: profile the app in Instruments → `os_signpost`, run the flow against a
  local server, read the interval durations listed above.
- MetricKit summaries: inspect `diagnostic-summaries.json` in the app's Application
  Support directory on a device that has been running a TestFlight/release build.

Update the table (and note the environment) whenever a measurement is repeated; record
significant improvements or regressions in release notes per the regression-monitoring
process in `diagnostics-reliability.md`.
