# Xcode Cloud dependency onboarding diagnosis

Assessment date: **2026-10-11**. Initial Gus Cloud onboarding with package references
requires connections for public upstream packages and keeps **Next** disabled. This
was reproduced with Xcode 27.0 and 27.1 RC. A disposable local project without package
references subsequently completed onboarding against Gus's existing app and primary
repository. This bypasses the failing dependency-connection step; the internal Apple cause is
**not confirmed**. The complete repairs were published directly on `origin/main`;
Cloud Build 1 verified the source commit but stopped at a bootstrap identity comparison.
That comparison is being repaired before a second validation run. Final build acceptance
is pending.

## Observed failure and expected behavior

1. Open `A Playa Named Gus.xcodeproj` with the signed-in Apple Account.
2. Start **Integrate → Create Workflow** and select Gus's existing app record.
3. Continue to the repository/dependency connection step. The primary repository is
   connected, but upstream packages such as `apple/swift-collections` and `readium/Fuzi`
   require **Connect**.
4. Click **Connect**. Apple's browser flow asks to install/authorize access under the
   upstream organization. GitHub offers the user's own account/organizations, not
   administrator access to `apple` or `readium`.
5. Return to Xcode: dependencies remain unconnected and **Next** remains disabled.
   An approved wizard restart and retry in the other Xcode version did not resolve it.

Apple's [Making dependencies available to Xcode Cloud](https://developer.apple.com/documentation/xcode/making-dependencies-available-to-xcode-cloud)
says publicly accessible Swift packages and Git submodules require no separate
configuration. Its provider authorization process applies to private dependencies.
The observed permission requirement therefore appears to treat these public packages
as repositories needing private-access authorization. This is a diagnosis of the
visible behavior, not proof of a particular server or Xcode implementation defect.
Obtaining upstream organization administrator rights is not a valid recovery path.

## Verified local dependency graph

Gus declares **two direct packages** in `project.yml`: Jellyfin SDK (`from: 2.1.0`) and
Readium (`from: 3.9.0`). The shared project and committed `Package.resolved` contain
**16 unique resolved package identities**:

| Repository | Pinned version | Source |
|---|---|---|
| `jellyfin/jellyfin-sdk-swift` | 2.1.0 | Direct |
| `readium/swift-toolkit` | 3.9.0 | Direct |
| `kean/Get` | 2.2.1 | Jellyfin |
| `apple/swift-nio-transport-services` | 1.28.0 | Jellyfin |
| `apple/swift-nio` | 2.100.0 | NIO Transport Services |
| `apple/swift-atomics` | 1.3.0 | NIO / NIO Transport Services |
| `apple/swift-collections` | 1.5.1 | NIO |
| `apple/swift-system` | 1.6.4 | NIO |
| `krzyzanowskim/CryptoSwift` | 1.10.0 | Readium |
| `marmelroy/Zip` | 2.1.2 | Readium |
| `ra1028/DifferenceKit` | 1.3.0 | Readium |
| `readium/Fuzi` | 4.0.0 | Readium |
| `readium/GCDWebServer` | 4.0.1 | Readium |
| `readium/ZIPFoundation` | 3.0.1 | Readium |
| `scinfu/SwiftSoup` | 2.13.5 | Readium |
| `stephencelis/SQLite.swift` | 0.16.0 | Readium |

Gus's unused `ReadiumAdapterGCDWebServer` linked product was removed and the generated
project updated. GCDWebServer remains resolved because Readium 3.9 declares it; this
is not a stale pin. Package resolution can include optional products not linked by Gus.

Read-only checks found no local explanation for the permission requirement:

- All 16 pin locations use normal HTTPS GitHub URLs. SwiftPM workspace state agrees
  with the committed pins, including the exact `swift-collections` and Fuzi URLs.
- No Git `insteadOf`/`pushInsteadOf` URL rewrites, submodules, package mirrors,
  project SCM blueprints, or additional workspace references were found.
- The workspace references only `self:`; build caches and user workspace state are
  ignored. SwiftPM checkout origins point to its local bare caches, whose origins are
  the expected upstream HTTPS URLs.
- A normal `.git` suffix variation for Jellyfin does not produce a duplicate identity
  and does not explain the failures for `swift-collections` or Fuzi.

## Isolated onboarding experiment

**Succeeded:** a disposable local clone outside the current build caches, with package
references removed only in that copy, completed Xcode 27.1 RC onboarding immediately.
The wizard recognized the existing `dev.ericslutz.gus` app and primary repository,
did not require upstream connections, and showed **Setup Complete** with a **Default**
workflow. No Git commits or pushes were made. The package-free project was not published.

This confirms that primary-repository authorization can complete and that bypassing
the package-connection step permits onboarding. Because the copy also has fresh local
workspace state, this experiment does not distinguish a local discovery-state defect
from a server visibility defect. It does not yet prove that Cloud can resolve/build the
full package graph. The authenticated API subsequently confirmed Gus product
`f2e5bb18-7cd2-44ab-b88c-9d54ac63b512`, primary repository
`af9d4248-65b2-413a-a7bd-25a8885ff13e`, and workflow
`A15758DF-3577-4ED3-99F5-4B549E19BD8F` with four BUILD actions: iOS, macOS, tvOS,
and visionOS. The real project’s saved workflow configuration is verified by the API: manual starts only, Xcode 27.1 RC (27A9275), and compatible macOS GoldenGate 27.2 beta 2 (26B5091g). It has no distribution audience or post-actions. The real remote build reached the bootstrap; its repair and a successful build remain the acceptance check.

## Main publication and first remote build

The complete local app/UI/download/playback/chapter repairs, shared generated project,
root-safe Cloud bootstrap, and all 16 dependency pins were pushed directly to
`origin/main` as `755ff09c9d69872a945fcd1f464aa7a7ea701153`. The package-free experiment
was not committed or published.

The guarded API preflight verified the enabled, clean, manual-only four-platform
workflow and canonical `main` reference. The single `POST /v1/ciBuildRuns` request
returned HTTP 405 `METHOD_NOT_ALLOWED`; a subsequent read confirmed zero runs. This
unexpected response does not establish a key-permission or request-body defect.
No key rotation, permission expansion, or blind POST retry was performed.

App Store Connect's **Start Build** dialog then successfully started **Build 1**
using **Gus Multiplatform Validation → main**. Run ID:
`5c1749b4-56a3-461c-a93c-4f3b8fe17b9c`. Authenticated API verification confirms its
actual source commit exactly matches the published SHA above. It used
Xcode 27.1 RC and the configured compatible macOS image. All four required BUILD
actions failed in `ci_post_clone.sh` before compilation or package-build acceptance. This is a validation workflow with no
distribution or TestFlight action.

### Build 1 bootstrap failure and focused repair

The expanded Cloud log identifies the shared exit-65 cause:
`CI_TEAM_ID` was `1f3fb703-e0b0-42fc-bc0b-d00a3bfdf58e`, the verified App Store Connect
account/team UUID, while the script compared it with signing Team ID `QS3GC3CT43`.
This is the correct configured account, not evidence of an unexpected team.
Apple's [environment-variable reference](https://developer.apple.com/documentation/xcode/environment-variable-reference)
describes a ten-character development-team example; the actual current run supplied
the Cloud team UUID instead. The repaired bootstrap passes nine focused checks, including both expected identities,
wrong/missing accounts, signing output, preserved pins, and working directory.
It distinguishes the two known identities,
accepts either expected form, and continues rejecting an unrelated account before
writing signing configuration. `DEVELOPMENT_TEAM` remains `QS3GC3CT43`.

[Actual failed bootstrap log](cloud-onboarding-evidence/build-1-bootstrap-failure.jpg),
[Build 1 summary](cloud-onboarding-evidence/run-1/summary.json), and
[failed overview](cloud-onboarding-evidence/build-1-failed-overview.jpg) preserve the
failure. Source fetching and project configuration checks passed in the sampled iOS
log; a successful complete build is still required.

## Recovery and acceptance

Keep the isolated project local and discard it after the experiment. Configure the workflow against the real
repository, real shared scheme, and appropriate Xcode version. Cloud must build the
complete committed Gus project with its original package declarations and pins.
Do not publish a package-free project, force automatic package resolution, or add
unnecessary upstream repository permissions to make the setup appear complete.

If isolation still fails, capture the precise failing step and use Apple's supported
Cloud connection recovery/support path. Completion requires an authenticated API/UI
check that Gus has a Cloud product and workflow, followed by a build using the real
repository. A connected primary repository alone is not acceptance.

## Evidence and status caveat

Durable sanitized evidence: [created product and workflow](cloud-onboarding-evidence/product-created.json),
[blocked dependency wizard](cloud-onboarding-evidence/cloud-public-repository-blocker.png),
and [successful setup](cloud-onboarding-evidence/cloud-setup-complete.png).
Original project, pins, and project.yml hashes still match the pre-experiment baseline.

- Configuration: `project.yml`, `A Playa Named Gus.xcodeproj/project.pbxproj`, and
  `A Playa Named Gus.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- Local resolver evidence: `build/duo-validation/SourcePackages/workspace-state.json`
  and the pinned package manifests under its `checkouts/` directory.
- Temporary screenshots: `/tmp/gus-device-repair/cloud-dependency-stall.png`,
  `/tmp/gus-device-repair/cloud-public-dependency-approval.png`, and
  `/tmp/gus-device-repair/cloud-public-repository-blocker.png`; successful isolated
  setup: `/tmp/gus-device-repair/cloud-setup-complete.png`.
- Original project/pins/configuration hash baseline:
  `/tmp/gus-cloud-original-hashes.txt`. Recheck it before closing the experiment.
- Read-only API snapshots: `/tmp/gus-device-repair/asc-gus-inspect.json` and
  `/tmp/gus-device-repair/asc-onboarding-current.json` report Gus app ID `6778382140`
  with an empty Cloud product list. These are earlier diagnostic snapshots, not proof
  of current state after subsequent retries; repeat `swift Scripts/app-store-connect.swift inspect`
  before reporting final onboarding status.
- Temporary files and ignored build caches are local evidence, not durable release
  artifacts. No key material or bearer tokens are included in this report.
