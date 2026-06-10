# Signing and Capabilities

## Current State

Simulator and local macOS builds use ad-hoc signing (`CODE_SIGN_IDENTITY = -`,
`CODE_SIGNING_REQUIRED = NO`) so GitHub PR builds work without provisioning profiles.
The bundle ID `dev.ericslutz.gus` and paid Apple Developer Program Team ID
`QS3GC3CT43` are set in `Config/Shared.xcconfig`. Entitlements and capability
declarations are complete.

Local device builds use the git-ignored `Config/Local.xcconfig` override to switch to
automatic signing. Distributable build signing, provisioning, TestFlight upload, and
App Store archives belong in Xcode Cloud, not GitHub Actions.

## Capabilities — Confirmed Ready

| Capability | Platform | Declared in | Status |
|---|---|---|---|
| Background audio | iOS / iPadOS / tvOS / visionOS | `UIBackgroundModes: [audio]` in `Info.plist` | ✓ |
| Outbound network | macOS | `com.apple.security.network.client` in `Config/Gus.entitlements` | ✓ |
| App Sandbox | macOS | `com.apple.security.app-sandbox` in `Config/Gus.entitlements` | ✓ |
| User Management | tvOS | `com.apple.developer.user-management` in `Config/Gus-tvOS.entitlements` | ✓ |
| Local network usage | iOS / iPadOS / visionOS | `NSLocalNetworkUsageDescription` in `Info.plist` | ✓ |
| Keychain | All | Keychain Services via `SecItem*` — no capability entry required | ✓ |
| No-exempt encryption | All | `ITSAppUsesNonExemptEncryption = false` in `Info.plist` | ✓ |
| Offline downloads | iOS / iPadOS / macOS / visionOS / watchOS (audio) | Application Support storage — no extra capability required | ✓ |
| Watch companion | watchOS | `GusWatch` target embedded in the iOS archive — no extra capability required | ✓ |

**Removed:** `NSFaceIDUsageDescription` was present but `LocalAuthentication` is never
called in A Playa Named Gus source code. A false usage description is an App Review red
flag; the key has been removed. The same reasoning covers visionOS Optic ID
(`NSOpticIDUsageDescription`): Keychain items use plain
`kSecAttrAccessibleAfterFirstUnlock` with no `kSecAccessControl` biometry, so no Optic ID
prompt can occur and no usage string is required. Add the string only if
biometry-protected Keychain access or `LocalAuthentication` is introduced.

**Not needed:** `NSBonjourServices` — Jellyfin discovery uses UDP broadcast on port 7359
via swift-nio sockets, not Bonjour/mDNS. `NSLocalNetworkUsageDescription` (already
present) is sufficient for the iOS 14+ local-network prompt.

**tvOS profile isolation:** A Playa Named Gus declares User Management with
`runs-as-current-user-with-user-independent-keychain`, but does not store Jellyfin tokens
with `kSecUseUserIndependentKeychain`. This keeps each Apple TV profile's saved Jellyfin
session separate.

**macOS account isolation:** A Playa Named Gus uses the macOS sandbox, user-domain
Application Support, `UserDefaults`, and the login user's Keychain. Separate macOS login
accounts therefore get separate app server lists, session restore state, and Jellyfin
tokens without an extra capability.

## CarPlay (Pending Apple Grant)

The CarPlay audio companion (`Sources/CarPlay/`) is implemented and its template scene
is declared in `Info.plist`, but `com.apple.developer.carplay-audio` requires an Apple
entitlement grant (request via the CarPlay developer page). Until granted,
`Config/Gus-CarPlay.entitlements` stays **unwired** so archives keep validating; the
CarPlay scene never activates without the entitlement. Once granted, wire it in
`Config/Shared.xcconfig`:

```
CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*] = Config/Gus-CarPlay.entitlements
CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*] = Config/Gus-CarPlay.entitlements
```

Verify with the CarPlay simulator (Simulator app → I/O → External Displays → CarPlay).

## Declared Age Range (Pending Entitlement)

The family-safety "Set from Age Range" action (`Sources/Features/Settings/
AgeRangeDefaults.swift`, OS 26+ only) uses Apple's DeclaredAgeRange framework, which
requires the `com.apple.developer.declared-age-range` entitlement at runtime. The code
self-disables without it: the request throws and Settings shows a graceful status
message while the manual rating picker keeps working. Request the entitlement together
with App Store Connect setup, then add it to the iOS/macOS entitlements files and wire
them per-SDK like CarPlay above. Scope and privacy rules:
`Documentation/family-safety-brief.md`.

## watchOS Companion

The `GusWatch` target (bundle id `dev.ericslutz.gus.watchkitapp`) ships **inside the iOS
app archive** — no separate App Store record — and is standalone-capable
(`WKRunsIndependentlyOfCompanionApp`). It needs no extra entitlement today: it uses
`URLSession`, the data-protection Keychain, and WatchConnectivity (no capability entry
required). Long-form on-watch audio uses `AVAudioSession`'s `.longFormAudio` policy.
Xcode Cloud signs/provisions it as part of the iOS app; confirm the watch app and its
provisioning are included when the iOS archive is validated. Scope:
`Documentation/watchos-brief.md`.

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

GitHub Actions builds and tests unsigned simulator/macOS outputs to protect the codebase.
It should not hold Apple Distribution certificates or provisioning profiles for Gus.

Xcode Cloud owns signed iOS, iPadOS, tvOS, visionOS, and macOS archives, provisioning,
TestFlight builds, App Store release archives, notarized Mac app builds, UI/device
matrix testing, and release-candidate validation. `ci_scripts/ci_post_clone.sh` validates
that Xcode Cloud is running under Team ID `QS3GC3CT43`, writes a temporary automatic
signing `Config/Local.xcconfig`, and regenerates `A Playa Named Gus.xcodeproj` from
`project.yml` before Xcode Cloud builds.

## Remaining Submission Steps (Account-Blocked)

- Create/configure the Xcode Cloud workflow for `dev.ericslutz.gus` and the tvOS Top
  Shelf extension.
- Let Xcode Cloud manage App Store provisioning profiles for the app plus the tvOS Top
  Shelf extension.
- Review per-platform capabilities in Xcode Signing & Capabilities and App Store Connect
  for any provisioning-profile additions (e.g. Push Notifications if added later).
- Archive and validate Release builds for iOS/iPadOS, tvOS, visionOS, and macOS in
  Xcode Cloud.
- Confirm macOS App Sandbox entitlements pass the archive-validation step (no unexpected
  file/network access).
