# Performance Baselines

Initial baselines for the flows required by
[diagnostics-reliability.md](diagnostics-reliability.md). Three measurement layers exist:

1. **XCTest `measure` measurements** in `Tests/APlayaNamedGusTests/PerformanceBaselineTests.swift`
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
| Media item mapping (2000 DTOs) | XCTest `testMediaItemMapperThroughputMeasurement` | iPhone 17 simulator, Debug, Xcode 26.5, macOS 26 host | avg 0.010 s | > +50% vs baseline |
| Server URL normalization (2000 inputs) | XCTest `testServerURLNormalizationMeasurement` | iPhone 17 simulator, Debug | avg 0.006 s | > +50% vs baseline |
| Histogram math (10k buckets) | XCTest `testHistogramMathMeasurement` | iPhone 17 simulator, Debug | avg 0.005 s | > +50% vs baseline |
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
  `measured [Time, seconds]` lines for `PerformanceMeasurementTests`.
- Cold launch: `Scripts/measure-launch-baseline.sh "iPhone 17" 5`.
- Flow intervals: profile the app in Instruments → `os_signpost`, run the flow against a
  local server, read the interval durations listed above.
- MetricKit summaries: inspect `diagnostic-summaries.json` in the app's Application
  Support directory on a device that has been running a TestFlight/release build.

Update the table (and note the environment) whenever a measurement is repeated; record
significant improvements or regressions in release notes per the regression-monitoring
process in `diagnostics-reliability.md`.


## October 10–11 local measurements

Xcode 27.0 (`27A266a`), Swift 6.4, macOS 27.0.1, arm64. These are optimized
macOS Release **test-enabled** measurements, with code coverage disabled only for
the harness. Shipping archives retain their normal Release settings. The initial
no-testability attempt executed zero tests and is historical; the corrected run
passes three tests, each with ten actual wall-clock samples. No production performance
budget is asserted or enforced by these measurements.

| Flow | Mean | Samples | Configuration |
|---|---|---|---|
| Histogram math (10k buckets) | 0.00006324 s | 10 | macOS Release, testability enabled, coverage off |
| Media item mapping (2000 DTOs) | 0.00353525 s | 10 | macOS Release, testability enabled, coverage off |
| URL normalization (2000 inputs) | 0.00614148 s | 10 | macOS Release, testability enabled, coverage off |

Raw samples and median/range are retained in the final review's
`evidence/final/sanitizers-performance/release-metrics.json`. These differ in
platform, toolchain and configuration from the older Xcode 26.5/iPhone Debug
measurements above and should not be compared as a release regression percentage.

The corrected launch helper resolves the observed `A Playa Named Gus.app` product.
Five actual iPhone 17e/iOS 27 Debug simulator process-spawn runs after warm-up recorded
301, 281, 260, 264 and 248 ms (rounded; mean 271 ms). This measures the process launch
command, not first usable frame or a cold disk-cache launch.

The bounded 20.85-second attached Time Profiler trace exported 2,968 raw samples,
including 988 main-thread samples. A movie-detail route was requested and allowed a
two-second settle; loaded rendering was not asserted separately for every trace.
Sample counts do not establish CPU utilization, navigation responsiveness or a release
budget. One auxiliary table reported an unavailable input source; primary time samples
were successfully exported. The standard SwiftUI template's Hitches instrument is
unsupported on this simulator. Compatible attached and launch-time SwiftUI-plus-Time-Profiler attempts warned of
no SwiftUI data; the attached update export has zero rows. SwiftUI runtime profiling
is inconclusive. Both attached and launch-time Leaks attempts lack allocation/leak
tables and are also inconclusive. Their inventories are retained in the final review. An instrument exiting successfully without allocation/leak data is inconclusive,
not evidence of zero leaks. Physical navigation peaks, playback soak, memory, thermal,
energy and MetricKit first-draw acceptance remain open.
