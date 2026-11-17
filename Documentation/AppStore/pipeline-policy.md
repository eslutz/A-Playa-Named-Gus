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
workflow are superseded. The saved **Gus Internal TestFlight** workflow also contained
simulator test actions. Do not start either stale Cloud configuration. This correction
starts no Cloud workflow and changes no live Cloud settings; re-read and reconcile the
remote actions before any future authorized archive run. The Cloud pre-build hook
rejects non-macOS build/test actions while retaining native macOS and archive support
when Cloud selects a source revision containing the hook. Unmerged main does not yet
contain this correction.

Prior dated CI/Cloud outcomes are historical, revision-scoped evidence, not current
pipeline instructions or release acceptance. See [release history](internal-testflight-release.md).
