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
| Offline downloads | iOS / iPadOS / macOS / visionOS | Application Support storage — no extra capability required | ✓ |

**Removed:** `NSFaceIDUsageDescription` was present but `LocalAuthentication` is never
called in A Playa Named Gus source code. A false usage description is an App Review red
flag; the key has been removed.

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
3. For local manual Release archive experiments only, set the profile specifier variables
   from `Config/Local.xcconfig.example`:
   ```
   CODE_SIGN_STYLE = Manual
   CODE_SIGN_IDENTITY = Apple Distribution
   GUS_IOS_PROVISIONING_PROFILE_SPECIFIER = <iOS app profile name>
   GUS_TVOS_PROVISIONING_PROFILE_SPECIFIER = <tvOS app profile name>
   GUS_TOPSHELF_TVOS_PROVISIONING_PROFILE_SPECIFIER = <tvOS Top Shelf profile name>
   GUS_VISIONOS_PROVISIONING_PROFILE_SPECIFIER = <visionOS app profile name>
   GUS_MACOS_PROVISIONING_PROFILE_SPECIFIER = <macOS app profile name>
   ```

## CI Signing Ownership

GitHub Actions builds and tests unsigned simulator/macOS outputs to protect the codebase.
It should not hold Apple Distribution certificates or provisioning profiles for Gus.

Xcode Cloud owns signed iOS, iPadOS, tvOS, visionOS, and macOS archives, provisioning,
TestFlight builds, App Store release archives, notarized Mac app builds, UI/device
matrix testing, and release-candidate validation. `ci_scripts/ci_post_clone.sh` validates
that Xcode Cloud is running under Team ID `QS3GC3CT43`, writes a temporary automatic
signing `Config/Local.xcconfig`, and regenerates `A Playa Named Gus.xcodeproj` from
`project.yml` before Xcode Cloud builds.

Local archive command:

```sh
Scripts/archive-release.sh ios tvos visionos macos
```

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
