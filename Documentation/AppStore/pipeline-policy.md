# Pull request and release gates

Changes to `main` require a PR and all five current GitHub checks: **Validation
Scope**, **Lint**, **Docs and Config**, **Build macOS**, and **Test macOS**. Keep
conversations resolved and the intended source revision explicit before merging.
This is project policy: server-side main branch protection is currently disabled,
and this correction does not restore or change remote enforcement. Verify the live
required-check configuration separately rather than inferring it from workflow YAML.

GitHub CI runs on PRs targeting main, with read-only repository permissions and
cancellation of superseded runs. It performs static/configuration checks and native
Apple Silicon macOS build/unit validation. Hosted native macOS unit execution has
an explicit exception. Simulator builds and tests are prohibited in GitHub and Xcode Cloud.

## Local qualification

Run all iOS/iPadOS, tvOS, visionOS and watchOS simulator builds and tests locally.
Retain exact source, compiled-input, artifact, native test-identity and raw-log
provenance outside Git. Existing results keep their original revision/artifact labels;
reuse requires an explicit unchanged-source scope, not a claim that they were rerun.
Requalify affected behavior when source changes or unresolved failures require it.
Local native macOS runtime and physical-device testing remain outside the current
validation scope; the hosted macOS exception does not authorize either.

The warning-free and Apple Silicon policies remain mandatory. Do not suppress build
or tool diagnostics, weaken architecture/concurrency settings, or substitute a passing
older run for the intended candidate. Native macOS unit-host signing retains its
sandbox/network entitlements; distribution signatures remain a separate gate.

## Native archives and distribution

Release qualification combines exact-candidate local simulator evidence, the five
current PR checks, and separately authorized native archives. Verify archive source,
architecture, complete signatures/profiles, raw diagnostics and export/upload outcomes.
App Store Connect processing, beta-group association and actual tester installation
are distinct acceptance steps; no release availability follows from compilation alone.

Cloud archive actions may be used only after explicit authorization and configuration
review. Preserve the global `XCODE_XCCONFIG_FILE` architecture override for compilation
and the normal warning/signing gates. A saved workflow or API template is not evidence
of current successful execution.

## Superseded hosted simulator configuration

Earlier 13/14-job GitHub matrices and the manual **Gus Validation** single-iPhone
workflow are superseded. **Gus Internal TestFlight** uses four internal-only device
archives and four distributions to Gus Internal after all five required GitHub checks
pass for the release inputs. GitHub's explicit-arm64 native macOS tests supply the
native test gate; Cloud does not repeat them. Apple's Cloud test runner used an
ambiguous Mac destination and emitted an unwaived warning, so its duplicate test
action was removed without expanding the warning exception.
Its former iOS, tvOS and visionOS simulator test actions have also been removed. Keep the
workflow manual, main-only and clean, with the global architecture override intact.
Do not start the stale Gus Validation workflow. Re-read remote actions and distribution
groups before every authorized archive run. The Cloud pre-build hook
rejects non-macOS build/test actions while retaining native macOS and archive support
when Cloud selects a source revision containing the hook.
The visionOS archive uses Apple's `CI_PRODUCT_PLATFORM=xrOS` identifier; the
pre-build guard accepts its archive/analysis actions and rejects its simulator
build/test actions. Rejections log only the platform and action identifiers.

Prior dated CI/Cloud outcomes are historical, revision-scoped evidence, not current
pipeline instructions or release acceptance. See [release history](internal-testflight-release.md).

## Authorized hosted simulator-discovery exception

The owner waived CI simulator-related warnings on November 17, 2026. The implemented
exception is narrower: only the observed Xcode `DVTiPhoneSimulator.m:661` warning
immediately followed by a nil SimDevice architecture detail with a null simulator
runtime is waived. Native hosted macOS commands must explicitly opt in and select
`platform=macOS,arch=arm64`. Each occurrence and the final count remain in raw logs.
Unknown/malformed assertions, compiler/linker/asset warnings, errors, Intel output,
and nonzero tool exits still fail. Local validation and archives retain strict gates;
this exception does not authorize hosted simulator builds or tests.
