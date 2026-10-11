# External local validation harnesses

These files preserve the exact additional checks and final orchestration used for this
execution. The maintained core entry point is `Scripts/validate-release.py --phase all`.
The external scripts reference the recorded `/tmp/gus-staged-candidate` and output paths
and standard simulator UUIDs; restore/materialize that reviewed candidate or update
those paths/UUIDs to equivalent available runtimes before replay. `xcodegen generate`
creates the standalone state project. Its tests activate the installed final Gus bundle.

The localhost Jellyfin fixture must be the rights-cleared demo, with the documented demo
account; the state fixture contains only demo item identities and an unused local port.
Start the bounded slow server only for pending-Connect cancellation. No API key, server
auth token or real account credential is stored here. Runtime fixture tokens are private
and ephemeral. Never point these debug launch routes at a production server.

Core and all Xcode lanes run sequentially against one DerivedData cache. Additional
scripts continue through failed lanes to collect evidence; the final acceptance check
rejects every failed/skipped/expected/empty lane. A script process returning zero alone
is not acceptance. Preserve each unique result bundle and its source/command manifest.

Candidate 11 reruns static and all Release archives after a Release-only source fix
and the launch-helper path correction. Retained candidate-10 Debug results are justified
by an exact active-DEBUG-token proof; their original source manifests are unchanged.
The launch-correction script is a superseded historical attempt that stopped when
archive-content inspection failed, not an accepted final execution. Actual corrected-helper
launch measurements precede the bounded profile attempts. The Vision observer only reads native simulator pixels and
records capture timing; inspect the rendered state independently rather than equating
its times with unsupported XCTest screenshot timestamps. Restore simulator appearance,
accessibility settings and boot state, and stop only the audit-owned local services.

The separate Vision capture project reuses the maintained audio/detail assertions against the same installed app and waits synchronously for native simulator IO screenshots via its audit-owned loopback bridge. Core observer detail captures that arrived after scene closure are not accepted design evidence. The created Gus-owned SE simulator closes the 375×667 geometry gap; other projects' simulators are untouched.

The final driver completed the core phases and sanitizer lanes, then stopped on a
Shutdown appearance configuration. Its first Release metric attempt compiled without
testability and ran no tests. `resume-final.py` records the actual corrected execution:
optimized Release metrics with `ENABLE_TESTABILITY=YES` and code coverage off, explicit
simulator boot/known appearance baseline, then expanded UI/state/launch/profiling. These
flags are harness-only and do not alter the shipping Release archives. Failed attempts
remain under historical evidence and are excluded from accepted lane counts.

The additional AX5 audio project uses its own DerivedData cache. Its accepted check uses the actual player ScrollView, validates the enlarged native Pause frame, taps to Play and validates reopening. A helper-placement compile failure and an empty-root application-gesture runtime failure are preserved as historical attempts. Native macOS UI startup was also attempted; its precise outcome is recorded separately.

The connection recovery fixture refuses an unused localhost port. The client retains its configured 90-second resource budget and Cancel; the final test waits at most 120 seconds for the stable public error prefix and requires enabled Connect/no Cancel. The initial 30-second test deadline was too short and is preserved, not accepted.

The standard SwiftUI template fails unsupported simulator Hitches. Compatible attached and launch-time traces exit zero but report no SwiftUI data; the exported update table is empty. Both Leaks attempts exit zero but export no allocation/leak tables. These instrumentation lanes remain inconclusive, with raw traces retained. Time Profiler primary data contains actual CPU samples, summarized without inventing a utilization budget.

Native macOS UI startup was bounded at five minutes and stopped with SIGINT after 311 seconds. The result contains a canceled-runner error and zero completed app assertions. No permission/signing root cause or Mac UI pass is claimed. The final cancellation was an execution-time bound; it does not modify shipping source.
