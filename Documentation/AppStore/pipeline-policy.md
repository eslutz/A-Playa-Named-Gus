# Pull request and release gates

Changes to `main` require a PR and four GitHub checks (**Validation Scope**,
**Lint**, **Docs and Config**, and **Build macOS**). Record relevant local test
results in the PR. Keep conversations resolved and the intended source revision
explicit before merging.
This is project policy. Verify live branch protection and required-check
configuration separately; workflow YAML does not establish remote enforcement.

GitHub CI runs on PRs targeting main, with read-only repository permissions and
cancellation of superseded runs. It performs static/configuration checks and native
Apple Silicon macOS compile validation. App tests and simulator builds run locally.

## Local qualification

Run macOS tests natively on a local Apple Silicon Mac with
`platform=macOS,arch=arm64`. Run iOS/iPadOS, tvOS, visionOS and watchOS
simulator builds and tests locally, one simulator at a time.
See the [local guide](../local-validation.md).
Retain exact source, compiled-input, artifact, native test-identity and raw-log
provenance outside Git. Existing results keep their original revision/artifact labels;
reuse requires an explicit unchanged-source scope, not a claim that they were rerun.
Requalify affected behavior when source changes or unresolved failures require it.
Record checks that need unavailable hardware or entitlements as unverified.

The warning-free and Apple Silicon policies remain mandatory. Do not suppress build
or tool diagnostics, weaken architecture/concurrency settings, or substitute a passing
older run for the intended candidate. Native macOS unit-host signing retains its
sandbox/network entitlements; distribution signatures remain a separate gate.

## Native archives and distribution

Release qualification combines exact-candidate local test evidence, the four
current PR checks, and separately authorized native archives. Verify archive source,
architecture, complete signatures/profiles, raw diagnostics and export/upload outcomes.
App Store Connect processing, beta-group association and actual tester installation
are distinct acceptance steps; no release availability follows from compilation alone.

Cloud archive actions may be used only after explicit authorization and configuration
review. Preserve the global `XCODE_XCCONFIG_FILE` architecture override for compilation
and the normal warning/signing gates. A saved workflow or API template is not evidence
of current successful execution.

## Cloud workflow boundaries

Use the manual, main-only internal TestFlight workflow only after verifying
its live configuration. Its four native archive and group distribution actions
must not include simulator actions. The Cloud pre-build hook rejects non-macOS
build/test actions but does not replace inspecting the live workflow; preserve
the global architecture override and use Apple’s `xrOS` identifier for visionOS.
Do not start the old Gus Validation workflow.

## Authorized hosted simulator-discovery exception

See the [warning policy](warning-policy.md#authorized-hosted-simulator-discovery-exception)
for the exact hosted native macOS exception. It authorizes no simulator work.

## Cloud project and package recovery

Keep the generated shared project, scheme and package pins in the repository.
Check them locally with `python3 Scripts/check-cloud-project.py`. For a dependency
wizard failure, verify the real repository, shared scheme, toolchain and pinned
package graph before escalating through Apple’s supported connection or support
path. A repository connection alone does not establish that Cloud can fetch
packages and archive the intended project. Do not publish a package-free project,
force automatic dependency resolution, or grant unnecessary repository access
to work around onboarding. See [API preparation](app-store-connect.md#api-access-and-cloud-workflow-discovery) for read-only
workflow inspection and [signing](signing-capabilities.md) for distribution setup.
