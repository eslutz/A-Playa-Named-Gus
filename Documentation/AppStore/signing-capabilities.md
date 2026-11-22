# Signing and Capabilities

See [pipeline policy](pipeline-policy.md) for current PR, qualification, and authorized distribution gates. This page describes signing inputs and capabilities, not current release status.

## Current State

The project defaults to ad hoc signing for simulator work. The GitHub arm64 macOS compile check uses `CODE_SIGNING_ALLOWED=NO`. The hosted native Mac unit host and its widget use their test-specific entitlements.
The bundle ID `dev.ericslutz.gus` and paid Apple Developer Program Team ID
`QS3GC3CT43` are set in `Config/Shared.xcconfig`. Entitlements and capability
declarations cover the currently wired surface. Apple granted CarPlay Audio.
The CarPlay candidate needs signed provisioning and device acceptance before public release.

Use the toolchain and deployment targets in project configuration; review the
currently selected Cloud toolchain before an authorized archive. Local simulator
builds do not qualify distribution signing. Local device signing, when separately
authorized, uses the Git-ignored `Config/Local.xcconfig` override.

## Optional Private Cloud Compute

The default build uses the on-device Foundation Models API on eligible iPhone, iPad, Mac and Vision Pro hardware. A separately provisioned OS 27 build can also offer Private Cloud Compute, including on Watch. Track qualification in [issue 50](https://github.com/eslutz/A-Playa-Named-Gus/issues/50).

After Apple grants the managed capability, add `com.apple.developer.private-cloud-compute` to the signing entitlements for the approved Gus and GusWatch destinations, preserve their existing capabilities, and regenerate the matching profiles. Set `GUS_PCC_ENTITLED = YES` only for the approved app targets and configurations. This setting exposes the runtime availability check. Apple enforces the signed entitlement and user quota. For an authorized archive, inspect the entitlements and embedded profiles of the app and its Watch companion before enabling distribution. [Apple’s entitlement requirements](https://developer.apple.com/private-cloud-compute/)

Exercise consent, quota exhaustion and network loss with local simulator fixtures.
Report which responses were simulated. Live Private Cloud Compute service access
remains unverified when the simulator cannot exercise it.

The Gus Internal TestFlight archive hook adds PCC to the existing iOS, macOS
and visionOS signing entitlements and gives the embedded Watch app its own
PCC entitlement. Enable the managed capability for both App IDs in Apple
Developer before running this workflow. Before the TestFlight post-actions, the Cloud hook checks the signed
TestFlight export for the entitlement, provisioning profile, and runtime flag
on each applicable bundle.

## Capabilities — Declared Implementation

The table records source configuration, not proof that distribution provisioning
profiles include every entitlement. Verify the signed host, its embedded extensions and companion, and App Store Connect processing for each destination. The CarPlay section below tracks the additional device and signing checks.

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
| Widgets and Watch complications | iOS / iPadOS / macOS / visionOS / watchOS | `group.dev.ericslutz.gus` in the host and its widget extension | ✓ |
| Download Live Activities | iOS / iPadOS | `NSSupportsLiveActivities` and the widget extension’s ActivityKit configuration | ✓ |
| Remote Now Playing status | iOS / iPadOS 27 and later | ExtensionKit extension point `com.apple.nowplaying.remote-media` | ✓ |
| Watch companion | watchOS | `GusWatch` and its widget share the App Group. The PCC archive hook preserves this entitlement when adding PCC. | ✓ |

**Universal Links / Shared with You:** Gus claims `applinks:gus.ericslutz.dev` and
supports `/item/<id>` and `/play/<id>`. The required associated-domains file is documented
in `Documentation/universal-links.md` and
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

## CarPlay audio and Siri

Gus declares the granted `com.apple.developer.carplay-audio` entitlement and the
standard `com.apple.developer.siri` entitlement in the iOS signing file.
The iOS TestFlight export check verifies both keys in the app signature and
embedded profile. The archive hook copies the canonical iOS entitlements before
adding Private Cloud Compute.

- Verify **CarPlay Audio** and **Siri** are enabled for the explicit
  `dev.ericslutz.gus` App ID. Confirm the grant covers development and App Store
  distribution. Use a refreshed development profile for a separately authorized
  connected-iPhone check. [Apple CarPlay provisioning](https://developer.apple.com/documentation/carplay/preparing-your-ios-app-for-carplay-development)
- On iOS 26, use the local Simulator CarPlay external display where available.
  On iOS 27, Apple specifies a connected iPhone and **Device Hub → Device →
  CarPlay Simulator**. Verify locked launch, live Siri, offline playback,
  interruptions, reconnect, and route loss on an authorized iPhone and head unit
  before advertising availability. [Apple CarPlay Simulator](https://developer.apple.com/documentation/carplay/testing-your-app-in-carplay-simulator)
- Track signing, simulator, and physical acceptance in [issue #70](https://github.com/eslutz/A-Playa-Named-Gus/issues/70).

## Declared Age Range

The post-sign-in age range check and Settings → Content Restrictions → Check Age
Range use Apple's DeclaredAgeRange framework on iPhone, iPad and Mac with the
`com.apple.developer.declared-age-range` entitlement. OS 26.4 and later reports
`requiredRegulatoryFeatures`; 26.2–26.3 exposes the earlier eligibility API. On
26.0–26.1 the system request is offered without a regional eligibility preflight.
See [family safety](../family-safety-brief.md) for offline behavior and privacy.

Device acceptance should exercise Apple's optional, required, declined and error
paths with provisioned accounts and sandbox age configurations. tvOS, visionOS
and watchOS do not expose the system request.

## watchOS Companion

The standalone-capable `GusWatch` app (`dev.ericslutz.gus.watchkitapp`) ships within the iOS archive and shares a single App Store record with Gus. Its nested WidgetKit extension (`dev.ericslutz.gus.watchkitapp.widgets`) and the Watch app both need the App Group. The Watch app uses URLSession, the data-protection Keychain, WatchConnectivity and the long-form audio policy. Verify the companion, its embedded extension and their provisioning profiles in the signed iOS export. [Watch companion scope](../watchos-brief.md)

When a Watch profile is missing, verify the exact embedded bundle identifier is
registered to the same team, and confirm the generated profile, signature and
version in the signed iOS export. Registration alone does not qualify a build.
If preparation rejects the default icon alpha channel, see the
[icon guide](icon-composer-source.md#diagnose-default-png-upload-rejections).

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

For hosted jobs and release ownership, see the [pipeline policy](pipeline-policy.md).

`ci_scripts/ci_post_clone.sh` accepts
only the verified Cloud account UUID or legacy Developer Team ID and always writes
signing Team ID `QS3GC3CT43` into a temporary automatic-signing `Config/Local.xcconfig`.
The account UUID never becomes a signing Team ID. It requires the committed shared Xcode project and
`Package.resolved`. Generate the project locally from `project.yml`; Cloud does not
regenerate it. See [API preparation](app-store-connect.md#api-access-and-cloud-workflow-discovery).

## Remaining Distribution and Submission Steps

- **CarPlay audio and Siri** — verify signed provisioning and connected-iPhone behavior.
- **Declared Age Range device verification** — verify on an OS 26 device that the system
  sheet presents and maps back to Gus's content limit.
- Verify the iOS app’s widget, remote Now Playing extension, Watch companion and nested Watch widget. Check the tvOS Top Shelf extension and the native Mac and Vision Pro widgets in their respective archives.
- Register each embedded bundle identifier with the same team. Let Xcode Cloud manage the App Store profiles and verify each signed bundle’s capabilities before distribution.
- Review per-platform capabilities in Xcode Signing & Capabilities and App Store Connect
  for any provisioning-profile additions (e.g. Push Notifications if added later).
- Confirm macOS App Sandbox entitlements pass the archive-validation step (no unexpected
  file/network access).
- Use the [pipeline policy](pipeline-policy.md) for archive and TestFlight acceptance.

## Playlist and Next Up iCloud synchronization

The unified Next Up branch adds supplemental CloudKit private-database synchronization
through `iCloud.dev.ericslutz.gus`. Jellyfin owns playlist and Collection/BoxSet names,
IDs, membership, playlist order and permissions. Native list definitions and queued
server edits stay with Jellyfin and the account-scoped device cache; CloudKit carries
Gus resume cursors, saved Next Up intent and activity.

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

## For You iCloud synchronization

iPhone can share ranked For You item IDs with Apple TV through the same private container. The snapshots use an isolated record zone and reuse the existing `SavedMediaRecord` type and `payload` field. Check that this schema exists in Production and that the signed iOS and tvOS apps have access to the same container before evaluating TestFlight delivery. The Apple TV path reads picks without model access. Check foreground delivery, account isolation, withdrawal and seven-day display expiry on the signed builds before claiming production iCloud acceptance.

## Siri actions and system extensions

The Shortcuts candidate embeds `dev.ericslutz.gus.widgets` on iOS, macOS and visionOS. Watch uses the nested identifier listed above. Provision each host and widget for `group.dev.ericslutz.gus`. The Mac widget also requires App Sandbox. Compare the exported signatures and provisioning profiles with the target’s entitlements.

Personal system suggestions and Next Up snapshots require consent for the active account on the device. Widgets read an expiring local title or progress snapshot. iOS and Watch omit titles from the snapshot until the user enables them. The system can further redact privacy-sensitive views. The Apple TV Top Shelf extension uses a separate rating-filtered snapshot under the same account preference.

The iOS 27 ExtensionKit target `dev.ericslutz.gus.remote-now-playing` publishes status for an explicitly selected controllable player on the active user’s account while Gus is open. The extension receives presentation values and has no account credentials, artwork URLs or command transport. Device qualification includes the foreground-to-background transition and removal of the session from Control Center. [Apple remote session documentation](https://developer.apple.com/documentation/nowplaying/publishing-remote-media-sessions)

App Shortcuts and structured audio use App Intents. Existing SiriKit audio on iPhone continues to use the Siri entitlement and music/audiobook categories. Keep the optional Siri AI developer-preview configuration limited to development-signed builds or Internal TestFlight. It requires the 27.3 SDK and an eligible device. [Apple’s preview requirements](https://developer.apple.com/documentation/appintents/siri-ai-developer-preview)
