# Signing and Capabilities

**Current policy (October 12):** protected main requires PRs and all GitHub checks. The saved main-only Cloud release tests iPhone/iPad/Duo, Mac, TV and Vision before internal distribution. Native Icon Composer source is restored and Cloud Build 8 passed without issues; CI run 38242041231 retained one iPad native audio completion failure. Tester availability remains unconfirmed until the new gates pass. [Pipeline policy](pipeline-policy.md), [release status](internal-testflight-release.md).


## Current State

Simulator and local macOS builds use ad-hoc signing (`CODE_SIGN_IDENTITY = -`,
`CODE_SIGNING_REQUIRED = NO`) so GitHub PR builds work without provisioning profiles.
The bundle ID `dev.ericslutz.gus` and paid Apple Developer Program Team ID
`QS3GC3CT43` are set in `Config/Shared.xcconfig`. Entitlements and capability
declarations cover the currently wired release surface; CarPlay audio remains pending a
manual Apple grant and is intentionally not advertised in App Store metadata until it is
granted and wired.

The current Cloud toolchain is **Xcode 27.1 RC (`27A9275`)**; GitHub uses the hosted
27.1 toolchain and rejects an iOS simulator SDK below 27.1. Duo arrangement APIs
require that SDK even though runtime use is availability-guarded. Deployment targets
remain `iOS 18`, `tvOS 18`, `visionOS 2`, `macOS 15`, and `watchOS 11`. Newer features
use availability checks or fail closed when the required framework/entitlement is
absent. Exact minimum-OS execution remains a separate acceptance gate.

Local device builds use the git-ignored `Config/Local.xcconfig` override to switch to
automatic signing. Distributable build signing, provisioning, TestFlight upload, and
App Store archives belong in Xcode Cloud, not GitHub Actions.

Cloud Build 6 accepted all four required BUILD actions with zero issues after the
six iOS/one Mac compiler warnings were repaired. Runtime code passed required CI
`38230709289` **13/13**. The separate `Gus Internal TestFlight` workflow has four
required internal-only Release ARCHIVE actions and four group post-actions; the
existing account is its one selected tester.

Build 7 produced signed App Store exports. iOS main/Watch and tvOS main/Top Shelf
versions, signatures and matching distribution profiles were verified. The Mac
signed app/package passed inspection with its sandbox and approved inbound/outbound
network entitlements, and required category/copyright metadata is present. Mac,
tvOS and visionOS uploads processed as VALID/READY_FOR_BETA_TESTING. iOS failed
later App Store preparation; independent Apple validation identified default
iOS/Watch icon alpha channels as the concrete rejection. All post-actions were
skipped; the group still had zero builds and tester state NOT_INVITED.

Opaque default-icon repair `64b9de6` and its semantic artwork assertion correction
`f354c7a` are published. Corrected CI `38237504737`, the signed retry and group
availability remain pending. [Signing proof and release status](internal-testflight-release.md),
[icon diagnosis](icon-upload-repair.md), [warning repair](build-warning-repairs.md).

## Capabilities — Declared Implementation

The table records source configuration, not proof that distribution provisioning
profiles include every entitlement. Verify the signed archives, embedded Watch/Top
Shelf components, and App Store Connect processing before claiming distribution
acceptance. CarPlay remains unwired and is outside the requested internal beta.

| Capability | Platform | Declared in | Status |
|---|---|---|---|
| Background audio | iOS / iPadOS / tvOS / visionOS | `UIBackgroundModes: [audio]` in `Info.plist` | ✓ |
| Outbound network | macOS | `com.apple.security.network.client` in `Config/Gus.entitlements` | ✓ |
| Discovery replies | macOS | Approved `com.apple.security.network.server` in `Config/Gus.entitlements` permits the ephemeral UDP receive socket | ✓ |
| App Sandbox | macOS | `com.apple.security.app-sandbox` in `Config/Gus.entitlements` | ✓ |
| User Management | tvOS | `com.apple.developer.user-management` in `Config/Gus-tvOS.entitlements` | ✓ |
| SharePlay / Group Activities | iOS / iPadOS / tvOS / visionOS / macOS | `com.apple.developer.group-session` in the app entitlements | ✓ |
| Universal Links / Associated Domains | iOS / iPadOS / tvOS / visionOS / macOS | `com.apple.developer.associated-domains: applinks:gus.ericslutz.dev` in the app entitlements | ✓ |
| Shared with You | iOS / iPadOS / tvOS / macOS | `SharedWithYou.framework` plus Universal Links | ✓ |
| Declared Age Range | iOS / iPadOS / macOS | `com.apple.developer.declared-age-range` in `Config/Gus-iOS.entitlements` and `Config/Gus.entitlements` | ✓ |
| tvOS App Group / Top Shelf snapshot | tvOS app + Top Shelf extension | `com.apple.security.application-groups: group.dev.ericslutz.gus` in tvOS app and extension entitlements | ✓ |
| Local network usage | iOS / iPadOS / visionOS | `NSLocalNetworkUsageDescription` in `Info.plist` | ✓ |
| Keychain | All | Keychain Services via `SecItem*` — no capability entry required | ✓ |
| Non-exempt encryption declaration | Main app, all primary platforms | `ITSAppUsesNonExemptEncryption = false` in `Resources/Info.plist`; confirm processed-build compliance | ✓ |
| Offline downloads | iOS / iPadOS / macOS / visionOS / watchOS (audio) | Application Support storage — no extra capability required | ✓ |
| Watch companion | watchOS | `GusWatch` target embedded in the iOS archive — no extra capability required | ✓ |

Do not move CarPlay into this table, release metadata, or wired
entitlements until Apple grants it and an archive has been validated with the granted
capability.

**Universal Links / Shared with You:** Gus claims `applinks:gus.ericslutz.dev` and
supports `/item/<id>` and `/play/<id>`. The required associated-domains file is documented
in `Documentation/AppStore/universal-links.md` and
`Documentation/AppStore/apple-app-site-association.json`.

**Removed:** `NSFaceIDUsageDescription` was present but `LocalAuthentication` is never
called in A Playa Named Gus source code. A false usage description is an App Review red
flag; the key has been removed. The same reasoning covers visionOS Optic ID
(`NSOpticIDUsageDescription`): Keychain items use plain
`kSecAttrAccessibleAfterFirstUnlock` with no `kSecAccessControl` biometry, so no Optic ID
prompt can occur and no usage string is required. Add the string only if
biometry-protected Keychain access or `LocalAuthentication` is introduced.

**Not needed for the current discovery implementation:** `NSBonjourServices`.
`ServerDiscoveryStore` calls `JellyfinClient.discover`; the pinned Jellyfin SDK's
`ServerDiscovery.swift` uses SwiftNIO `DatagramBootstrap`, UDP broadcast on port
7359, and an ephemeral receive socket. SwiftNIO remains a transitive SDK dependency;
this is not Bonjour/mDNS discovery. `NSLocalNetworkUsageDescription` is already
present for the native local-network prompt; permission/network reachability and
sandbox receive access are separate runtime concerns.

**tvOS profile isolation:** A Playa Named Gus declares User Management with
`runs-as-current-user-with-user-independent-keychain`, but does not store Jellyfin tokens
with `kSecUseUserIndependentKeychain`. This keeps each Apple TV profile's saved Jellyfin
session separate.

**macOS account isolation:** A Playa Named Gus uses the macOS sandbox, user-domain
Application Support, `UserDefaults`, and the login user's Keychain. Separate macOS login
accounts therefore get separate app server lists, session restore state, and Jellyfin
tokens without an extra capability.

## CarPlay (Pending Apple Grant)

**Current state:** `CPTemplateApplicationSceneSessionRoleApplication` is declared in
`Info.plist` and `Sources/CarPlay/CarPlaySceneDelegate.swift` is compiled into the iOS
target, but `com.apple.developer.carplay-audio` has **not** been granted by Apple and is
**not** wired into signing. The scene declaration is inert without the entitlement — iOS
will not activate it at runtime. Earlier local archives were unsigned; signed
archive/upload acceptance remains unverified.

The CarPlay audio companion (`Sources/CarPlay/`) is implemented and its template scene
is declared in `Info.plist`, but `com.apple.developer.carplay-audio` requires an Apple
entitlement grant. Until granted, `Config/Gus-CarPlay.entitlements` stays **unwired**;
the CarPlay scene never activates without the entitlement. The internal TestFlight
request does not enable CarPlay.

Steps to enable (none are code work — the implementation is complete):

- [ ] **Request the entitlement from Apple** via the
  [CarPlay developer request page](https://developer.apple.com/contact/carplay/),
  describing the audio (music/audiobook) use case. This is a manual Apple review/grant
  and is the long pole — it can take weeks.
- [ ] Once granted, **add `com.apple.developer.carplay-audio` to the App ID /
  provisioning profile** in the Developer portal.
- [ ] **Merge the granted CarPlay entitlement** into the iOS signing entitlements,
  preserving Associated Domains, Declared Age Range, and Group Activities. Do not
  replace `Config/Gus-iOS.entitlements` with the standalone CarPlay draft and silently
  drop those existing capabilities. Regenerate/validate the shared project if its
  signing-file references change.
- [ ] **Verify** in the CarPlay simulator (Simulator app → I/O → External Displays →
  CarPlay) and on real CarPlay hardware.

## Declared Age Range

The family-safety "Set from Age Range" action (`Sources/Features/Settings/
AgeRangeDefaults.swift`, OS 26+ only) uses Apple's DeclaredAgeRange framework, which
requires the `com.apple.developer.declared-age-range` entitlement at runtime. The
entitlement is wired for iOS/iPadOS and macOS; the code still self-disables if the runtime
or provisioning profile does not make the service available. Settings shows a graceful
status message while the manual rating picker keeps working. Scope and privacy rules:
`Documentation/family-safety-brief.md`.

Remaining validation:

- [ ] **Verify on an iOS 26 / macOS 26 device** that Settings → Content Restrictions →
  "Set from Age Range" presents the system sheet and maps the result to a limit
  (simulators may not surface the system sheet). visionOS/tvOS/watchOS do not expose the
  framework — the button is correctly absent there.

## watchOS Companion

The `GusWatch` target (bundle id `dev.ericslutz.gus.watchkitapp`) ships **inside the iOS
app archive** — no separate App Store record — and is standalone-capable
(`WKRunsIndependentlyOfCompanionApp`). It needs no extra entitlement today: it uses
`URLSession`, the data-protection Keychain, and WatchConnectivity (no capability entry
required). Long-form on-watch audio uses `AVAudioSession`'s `.longFormAudio` policy.
Xcode Cloud signs/provisions it as part of the iOS app; confirm the watch app and its
provisioning are included when the iOS archive is validated. Scope:
`Documentation/watchos-brief.md`.

Build 4's App Store export failed because Cloud could not auto-register
`dev.ericslutz.gus.watchkitapp` or find its matching App Store provisioning profile.
The exact identifier is now registered through Apple's Developer UI as `Gus Watch`,
resource `X7N8FKWCC6`, platform `UNIVERSAL`, Team `QS3GC3CT43`. The API snapshot
returns only the default `IN_APP_PURCHASE` capability; no extra Watch entitlement
or in-app purchase implementation was added. Build 7 now verifies matching App Store profile generation, signed export, and
embedded Watch signatures/version. iOS upload still awaits the repaired default
icons; profile/export acceptance does not establish tester installation. Registration proof,
confirmed failure.

## Setting Your Team ID (Local Override)

`DEVELOPMENT_TEAM = QS3GC3CT43` is committed in `Config/Shared.xcconfig`; the Team ID is
not a signing secret. To build locally for a device:

1. Create `Config/Local.xcconfig` (git-ignored):
   ```
   DEVELOPMENT_TEAM = QS3GC3CT43
   CODE_SIGN_STYLE = Automatic
   CODE_SIGN_IDENTITY = Apple Development
   CODE_SIGNING_REQUIRED = YES
   CODE_SIGNING_ALLOWED = YES
   ```
2. `Config/Shared.xcconfig` already includes `Config/Local.xcconfig` when present.

## CI Signing Ownership

GitHub Actions builds and tests simulator/ad-hoc macOS outputs to protect the codebase.
It should not hold Apple Distribution certificates or provisioning profiles for Gus.

Xcode Cloud is the distribution signing/provisioning owner for iOS/iPadOS, tvOS,
visionOS, and macOS archives and TestFlight uploads. The existing validation workflow
is build-only; the separate internal archive/distribution workflow is configured,
with corrected-run acceptance pending. Native
UI/device acceptance and public release validation remain separate work.
`ci_scripts/ci_post_clone.sh` accepts
only the verified Cloud account UUID or legacy Developer Team ID and always writes
signing Team ID `QS3GC3CT43` into a temporary automatic-signing `Config/Local.xcconfig`.
The account UUID never becomes a signing Team ID. It requires the committed shared Xcode project and
`Package.resolved`. Generate the project locally from `project.yml`; Cloud does not
regenerate it. See [API preparation](api-access.md).

## Remaining Distribution and Submission Steps

- **Optional future CarPlay audio entitlement** — request, grant-wait, wire, and verify
  (see the CarPlay section above); it is not a prerequisite for the current unwired
  internal beta.
- **Declared Age Range device verification** — verify on an OS 26 device that the system
  sheet presents and maps back to Gus's content limit.
- Complete a corrected run of the configured manual internal-only archive/distribution
  workflow. Keep the successful BUILD-validation workflow intact.
  Watch ships inside the iOS archive and Top Shelf inside the tvOS archive; they do
  not require separate store records/distribution workflows.
- Let Xcode Cloud manage App Store provisioning profiles for the main app, registered
  Watch companion, and tvOS Top Shelf extension; verify the resulting signed products.
- Review per-platform capabilities in Xcode Signing & Capabilities and App Store Connect
  for any provisioning-profile additions (e.g. Push Notifications if added later).
- Archive and validate Release builds for iOS/iPadOS, tvOS, visionOS, and macOS in
  Xcode Cloud.
- Confirm macOS App Sandbox entitlements pass the archive-validation step (no unexpected
  file/network access).
- Confirm each uploaded build is processed/eligible for internal testing and assigned
  to `Gus Internal`, whose existing-account membership is already verified. Account
  membership, build access, and actual
  TestFlight installation are distinct results.

## Playlist and Next Up iCloud synchronization

The unified Next Up branch adds supplemental CloudKit private-database synchronization
through `iCloud.dev.ericslutz.gus`. Jellyfin owns playlist and Collection/BoxSet names,
IDs, membership, playlist order and permissions. Native list definitions and queued
server edits stay with Jellyfin and the account-scoped device cache; CloudKit carries
Gus resume cursors, saved Next Up intent and activity. Legacy Gus-owned playlist records
remain preserved for explicit import into Jellyfin; they are not silently migrated.
Legacy lists with repeated media items cannot be imported until duplicates are
explicitly removed, because Jellyfin 10.11.11 deduplicates native playlist membership.

All four main-app platform entitlement files declare CloudKit, silent remote
notifications and that container; `project.yml` explicitly links the system framework.
Watch and Top Shelf do not independently activate playlist sync.

Register the container with team `QS3GC3CT43`, enable iCloud/CloudKit and Push Notifications for the main
`dev.ericslutz.gus` App ID, associate the container, and regenerate the main app's
development/distribution profiles. Deploy the `SavedMedia-v1` private zone's
`SavedMediaRecord` schema (Data field `payload`) from Development to Production
before testing TestFlight. Xcode Cloud remains the distribution signing owner.

Existing local macOS profiles were checked during implementation and do **not**
include this capability. An unsigned build/unit run does not prove signing,
container availability, production schema deployment, or cross-device sync.
Record independent signed iPhone/Apple TV acceptance before release claims.

Silent CloudKit change notifications keep CKSyncEngine current; no user-facing APNs event product from issue #12 is added. Development push environment is declared in source; distribution signing must resolve the production push environment.

Automatic provisioning was attempted on Xcode 27.1 RC. Its first attempt reported
`No Accounts`; the configured team API-key attempt reported authentication failure.
The same key still succeeds for App Store Connect reads. Provisioning authority is
therefore not established by that read access. Sign into the selected Xcode's
Accounts settings (or provide working provisioning authentication), enable the
listed capabilities/container, then regenerate profiles and run signed acceptance.
No successful capability grant, profile refresh, production schema deployment or
physical sync is claimed by these attempts.

Native-list ownership and current validation are tracked in [the implementation ledger](../Reviews/README.md). The signed provisioning and physical sync gates above remain open.
