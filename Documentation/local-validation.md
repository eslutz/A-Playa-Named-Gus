# Local validation guide

Use this guide from the Gus checkout root to validate a change on a local Mac.
Run the smallest checks that can establish the claim you need to make. The
[agent rules](../AGENTS.md) define repository constraints;
[`project.yml`](../project.yml) and [shared build settings](../Config/Shared.xcconfig)
define targets and settings. The [pipeline policy](AppStore/pipeline-policy.md)
owns hosted checks and release gates. Run local automated app tests and runtime
verification on Apple simulators only, one at a time. Record any behavior that
requires physical hardware or a live device entitlement as **unverified**.

## Choose a validation path

| Change | Run locally | Record |
| --- | --- | --- |
| Documentation only | Review changed text, relative links and anchors, and whitespace; validate syntax if config also changed. Skip XcodeGen, app builds, and tests. | Checks performed and config scope. |
| Routine code | Lint relevant code; build affected targets and run focused local simulator tests where appropriate. | Target, OS, test scope, and outcomes. |
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
3. **Select the target.** Match the scheme’s destination against
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
   Record the revision, target/scheme, simulator OS/UDID, and exact checks. Build
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

Run `xcodegen generate` only when inputs affecting the generated project change.
Review the generated project diff. The shared project snapshot and
`Package.resolved` are tracked for Xcode Cloud. Verify them with
`python3 Scripts/check-cloud-project.py` when affected. If dependency resolution
is needed, use `xcodebuild -resolvePackageDependencies` with the project and scheme
below and check for unintended lockfile changes.

Use `swiftformat Sources Tests --lint` for a read-only lint check.
`Scripts/format.sh` rewrites source and tests; run it only when formatting changes
are in scope. To check edited localized strings, run
`jq empty Resources/Localizable.xcstrings`.

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

```sh
python3 Scripts/run-warning-free.py xcodebuild \
  -project "$PROJECT" -scheme 'Gus iOS Unit Tests' -destination "$DESTINATION" \
  -derivedDataPath "$EVIDENCE/DerivedData" \
  -resultBundlePath "$EVIDENCE/ios-unit.xcresult" test >"$EVIDENCE/ios-unit.log" 2>&1
```

### Fixtures, UI tests, and captures

For authenticated Jellyfin flows, start the [demo server](demo-server.md)
with `Scripts/demo-server.sh start`. It needs a running Docker engine and
rights-cleared local sample media. Use the demo account, not production credentials.
Seerr regressions use the separate `Scripts/discover-fixture-server.py` fixture
when the scenario needs it. Choose the applicable scheme (e.g. `Gus iOS UI Tests`,
`Gus tvOS Tests`, `Gus visionOS Tests`, or `Gus watchOS Tests`) and capture
results using the same destination and evidence approach as the unit recipe.

`Scripts/screenshots.sh --list` shows the capture destinations; verify those
against the tools above. `Scripts/screenshots.sh iphone` builds and captures
predefined scenes; other selectors are `ipad`, `tv`, `vision`, and `watch`.
Signed-in captures need the demo server; its default library does not cover
series or Live TV. The script writes to Git-ignored `Screenshots/`; move retained
evidence outside the checkout. This is not an interaction or device-acceptance
test. See the [review workflow](Reviews/README.md#reproducing-an-iphone-design-comparison)
for matching before/after captures.

## Manual and release handoffs

Native local macOS runtime tests and physical-device acceptance are outside
current scope. List them separately when still needed. Don't start hosted jobs,
archives, signing or distribution as a substitute for a missing local check.

If choosing the [release helper](../Scripts/validate-release.py), review the
selected phase and use an explicit external `--output` directory. Do not use
`tests` for local simulator-only validation (it also runs native macOS), or
`all` for routine work (it also runs UI tests and archives). Use the
[pipeline policy](AppStore/pipeline-policy.md) to decide when to hand off an exact
candidate and which release actions need separate authorization.
