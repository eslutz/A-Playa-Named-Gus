# Local validation guide

Use this guide from the Gus checkout root to validate a change on a local Mac.
Run the smallest checks that can establish the claim you need to make. The
[agent rules](../AGENTS.md) define repository constraints;
[`project.yml`](../project.yml) and [shared build settings](../Config/Shared.xcconfig)
define targets and settings. The [pipeline policy](AppStore/pipeline-policy.md)
owns hosted checks and release gates. Run macOS tests and runtime verification
natively on a local Apple Silicon Mac. For the other platforms, use local Apple
simulators one at a time. Record behavior that requires unavailable hardware or
entitlements as **unverified**.

## Choose a validation path

| Change | Run locally | Record |
| --- | --- | --- |
| Documentation only | Review changed text, relative links and anchors, and whitespace; validate syntax if config also changed. Skip XcodeGen, app builds, and tests. | Checks performed and config scope. |
| Routine code | Lint relevant code, build affected targets, and run focused local tests where appropriate. | Target, OS, test scope, and outcomes. |
| Project inputs | Regenerate when generator config or the source/resource file set changes. Review the generated diff and verify the tracked snapshot and pins. Then use the routine or UI path as applicable. | Input change, generated changes, and snapshot check. |
| UI, server, or Watch behavior | Use the relevant installed simulator, test scheme, and approved fixtures. Exercise the affected behavior; use screenshots when useful. | Simulator, fixture, scenarios, and observed behavior. |
| Exact release candidate | Follow [local qualification](AppStore/pipeline-policy.md#local-qualification) for the intended revision and affected platforms. Hand off signing, archives, and distribution separately. | Exact revision and artifact, raw logs and test evidence, and unresolved gates. |

## Workflow

1. **Scope the change.** Read the diff and choose a path. Don't run a full matrix
   just because a command exists. Ask before any action outside the requested scope.
2. **Preflight.** Record the revision and whether the checkout has local changes.
   Check the active Xcode against the repository's required version. Simulator work
   needs a local Apple Silicon Mac, full Xcode, and the relevant runtime and
   destination. Install XcodeGen or SwiftFormat only when needed. Server-backed
   UI work also needs the local fixture prerequisites.
3. **Select the target.** Use `platform=macOS,arch=arm64` for native Mac tests.
   For simulator tests, match the scheme’s destination against
   `xcrun simctl list devices available`. Pass the explicit simulator platform
   and UDID, for example `platform=iOS Simulator,id=<simulator UDID>`.
   A connected phone or Watch may also appear in Xcode’s destination list.
   Only a simulator entry qualifies for these checks.
4. **Run scoped checks.** Keep simulator builds and tests local. Preserve the
   [warning gate](AppStore/warning-policy.md); don't apply the hosted macOS exception
   locally. Stop if you cannot verify the target, fixture, toolchain, or permission.
   Report warning-gate failures, setup blockers, and missing runtimes rather than
   substituting a hosted simulator or a different test environment.
5. **Report evidence.** For each check, say **passed**, **failed** (with the first
   meaningful error), **blocked** (with the missing prerequisite), or **not run**.
   Record the revision, target/scheme, OS, simulator UDID where applicable, and exact checks. Build
   success does not establish launch; launch does not establish behavior. Keep raw
   logs, result bundles, and retained screenshots outside Git and the checkout.

## Commands

### Preflight, project generation, and lint

```sh
git rev-parse --short HEAD
git status --short
git diff HEAD --check
xcodebuild -version
xcode-select -p
```

Run `SWIFT_DETERMINISTIC_HASHING=1 xcodegen generate` only when inputs affecting the generated project change. The environment setting keeps the generated copy-phase IDs stable.
Review the generated project diff. The shared project snapshot and
`Package.resolved` are tracked for Xcode Cloud. Verify them with
`python3 Scripts/check-cloud-project.py` when affected. If dependency resolution
is needed, use `xcodebuild -resolvePackageDependencies` with the project and scheme
below and check for unintended lockfile changes.

Use `swiftformat Sources Tests --lint` for a read-only lint check.
`Scripts/format.sh` rewrites source and tests; run it only when formatting changes
are in scope. To check edited localized strings, run
`jq empty Resources/Localizable.xcstrings`.

### Reuse existing simulators

Use an existing, generically named Apple device such as **iPhone 17e** for the
required model and OS runtime. Reuse it across apps, branches, and test runs.
Do not create or clone simulators for an app, test, ticket, or validation run.
Select an available device by its UDID and coordinate with anyone already
using it. Keep each required OS/device combination and any active Watch pair.
If a required combination is missing, report it before provisioning a reusable
generic device. Run one simulator at a time and disable parallel XCTest
destinations with `-parallel-testing-enabled NO`.

### Build, launch, and test an explicit simulator

Use one shell from the checkout root. This recipe is for iPhone; for iPad choose
an iPad UDID (same Xcode destination platform). Use the matching platform and
scheme for other simulators.

```sh
PROJECT='A Playa Named Gus.xcodeproj'
APP_SCHEME='A Playa Named Gus'
xcodebuild -project "$PROJECT" -scheme "$APP_SCHEME" -showdestinations
xcrun simctl list devices available
printf 'Installed iPhone simulator UDID: '
read -r SIMULATOR_ID
DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"
EVIDENCE="$(mktemp -d /tmp/gus-validation.XXXXXX)"
printf 'Evidence directory: %s\n' "$EVIDENCE"
```

Build with the warning wrapper. If this fails, stop before installing or testing;
review the captured build log. For other platforms, discover destinations using
the scheme you will run. A generic Watch simulator build is compilation only,
not proof of companion launch or behavior.

```sh
python3 Scripts/run-warning-free.py xcodebuild \
  -project "$PROJECT" -scheme "$APP_SCHEME" -destination "$DESTINATION" \
  -derivedDataPath "$EVIDENCE/DerivedData" build >"$EVIDENCE/build.log" 2>&1
```

For a manual launch check, boot the selected device if needed. Wait for it to
finish booting, then install and launch the product from that same build.

```sh
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl install "$SIMULATOR_ID" \
  "$EVIDENCE/DerivedData/Build/Products/Debug-iphonesimulator/A Playa Named Gus.app"
xcrun simctl launch "$SIMULATOR_ID" dev.ericslutz.gus
```

Run the relevant unit test scheme; this example uses iOS. For a single Swift
Testing case, add an `-only-testing:GusTests/<Suite>/<Test>` filter with actual
suite and test names. The TV and Vision unit schemes are `Gus tvOS Unit Tests`
and `Gus visionOS Unit Tests`.

Use a signed-out generic simulator for the full iOS unit suite. A saved Gus
session with an unresolved age check can block synthetic playback fixtures.
Select a generic device with suitable test state. If every suitable device
holds someone’s session, defer the run until one is available. Preserve existing
accounts, restrictions and other apps’ data.

```sh
python3 Scripts/run-warning-free.py xcodebuild \
  -project "$PROJECT" -scheme 'Gus iOS Unit Tests' -destination "$DESTINATION" \
  -derivedDataPath "$EVIDENCE/DerivedData" \
  -parallel-testing-enabled NO -resultBundlePath "$EVIDENCE/ios-unit.xcresult" test >"$EVIDENCE/ios-unit.log" 2>&1
```

### Test native macOS on Apple Silicon

Run the native unit scheme from the checkout root. The temporary signing
configuration gives the unit host App Sandbox and networking and gives the widget App Sandbox. It leaves the checkout's signing settings in place for other builds.

```sh
EVIDENCE="$(mktemp -d /tmp/gus-macos-validation.XXXXXX)"
printf 'GUS_APP_MAC_ENTITLEMENTS = %s\nGUS_WIDGET_MAC_ENTITLEMENTS = %s\nCODE_SIGN_STYLE = Manual\nCODE_SIGN_IDENTITY = -\nPROVISIONING_PROFILE_SPECIFIER =\n' \
  "$PWD/ci_scripts/gus-macos-unit.entitlements" "$PWD/ci_scripts/gus-widget-macos-unit.entitlements" >"$EVIDENCE/MacUnit.xcconfig"
XCODE_XCCONFIG_FILE="$EVIDENCE/MacUnit.xcconfig" \
  python3 Scripts/run-warning-free.py xcodebuild \
  -project 'A Playa Named Gus.xcodeproj' -scheme 'Gus macOS Unit Tests' \
  -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
  -derivedDataPath "$EVIDENCE/DerivedData" \
  -resultBundlePath "$EVIDENCE/macos-unit.xcresult" test >"$EVIDENCE/macos-unit.log" 2>&1
```

For macOS UI tests, use the `Gus macOS Tests` scheme with the same native
destination and the signing and fixtures required by the scenario.

### Fixtures, UI tests, and captures

For authenticated Jellyfin flows, start the [demo server](demo-server.md)
with `Scripts/demo-server.sh start`. It needs a running Docker engine and
rights-cleared local sample media. Use the demo account, not production credentials.
Seerr regressions use the separate `Scripts/discover-fixture-server.py` fixture
when the scenario needs it. Choose the applicable scheme (e.g. `Gus iOS UI Tests`,
`Gus tvOS Tests`, `Gus visionOS Tests`, or `Gus watchOS Tests`) and capture
results using the same destination and evidence approach as the unit recipe.

Run `Gus iOS App Intent Tests` on an iOS 27 or later simulator to exercise
the installed app through Apple's App Intents Testing framework. The scheme
also contains the Siri AI evaluation, which requires the developer-preview
configuration, a compatible SDK, and an eligible physical device.
The regular `Gus iOS UI Tests` scheme continues to support the iOS 26 floor.

Use `Gus watchOS App Intent Tests` on watchOS 27.2 or later to run the
Downloads control through the Watch app’s installed intent definitions. Start
the loopback sign-in fixture with `python3 Scripts/book-details-fixture.py --navigation`.
The ordinary Watch browsing tests continue to support watchOS 26.

For navigation UI tests, run `python3 Scripts/book-details-fixture.py --genres`
for related results and paging (port 5061). Run the same script with
`--navigation` (port 5062) for Profile editing and load failures, staged photo
removal, Quick Connect approval and rejection, Client Logs navigation, sidebar
library selection, unavailable Next Up entries, video preparation and failure,
and season switching. Both fixtures bind to loopback.

For the Discover-to-Jellyfin handoff tests in `GusSeerrUITests`, run the Seerr
fixture and the navigation Jellyfin fixture together. These tests enable the
matching movie and season through Seerr's fixture reset endpoint. They verify
each native Back step and the position of a title loaded on a later catalog page.

`Scripts/screenshots.sh --list` shows the capture destinations; verify those
against the tools above. `Scripts/screenshots.sh iphone` builds and captures
predefined scenes; other selectors are `ipad`, `tv`, `vision`, and `watch`.
Signed-in captures need the demo server; its default library does not cover
series or Live TV. The script writes to Git-ignored `Screenshots/`; move retained
evidence outside the checkout. This is not an interaction or device-acceptance
test. See the [review workflow](Reviews/README.md#reproducing-an-iphone-design-comparison)
for matching before/after captures.

## Manual and release handoffs

Record physical-device acceptance separately from local app tests. Follow the
release gates for signing, archives, and distribution.

If choosing the [release helper](../Scripts/validate-release.py), review the
selected phase and use an explicit external `--output` directory. Do not use
`tests` for local simulator-only validation (it also runs native macOS), or
`all` for routine work (it also runs UI tests and archives). Use the
[pipeline policy](AppStore/pipeline-policy.md) to decide when to hand off an exact
candidate and which release actions need separate authorization.
