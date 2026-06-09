# Signing and Capabilities

## Current State

Simulator and local macOS builds use ad-hoc signing (`CODE_SIGN_IDENTITY = -`,
`CODE_SIGNING_REQUIRED = NO`) so they work without an Apple Developer Program account.
The bundle ID `dev.ericslutz.gus` is set in `Config/Shared.xcconfig`. Entitlements and
capability declarations are complete; only the Team ID and distribution credentials are
account-blocked.

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

`DEVELOPMENT_TEAM` is intentionally blank in `Config/Shared.xcconfig` so the repo stays
account-agnostic. To build for a device or archive for the App Store:

1. Create `Config/Local.xcconfig` (git-ignored):
   ```
   DEVELOPMENT_TEAM = XXXXXXXXXX
   CODE_SIGN_STYLE = Automatic
   CODE_SIGN_IDENTITY = Apple Development
   CODE_SIGNING_REQUIRED = YES
   CODE_SIGNING_ALLOWED = YES
   ```
2. `Config/Shared.xcconfig` already includes `Config/Local.xcconfig` when present.
3. For Release archives with manual profiles, set the profile specifier variables from
   `Config/Local.xcconfig.example`:
   ```
   CODE_SIGN_STYLE = Manual
   CODE_SIGN_IDENTITY = Apple Distribution
   GUS_IOS_PROVISIONING_PROFILE_SPECIFIER = <iOS app profile name>
   GUS_TVOS_PROVISIONING_PROFILE_SPECIFIER = <tvOS app profile name>
   GUS_TOPSHELF_TVOS_PROVISIONING_PROFILE_SPECIFIER = <tvOS Top Shelf profile name>
   GUS_VISIONOS_PROVISIONING_PROFILE_SPECIFIER = <visionOS app profile name>
   GUS_MACOS_PROVISIONING_PROFILE_SPECIFIER = <macOS app profile name>
   ```

## CI Archive Workflow

`.github/workflows/archive-release.yml` is a manual `workflow_dispatch` workflow that:

- imports an Apple Distribution `.p12` certificate into a temporary keychain;
- installs iOS, tvOS, tvOS Top Shelf, visionOS, and macOS provisioning profiles;
- writes a temporary `Config/Local.xcconfig` with the Team ID and profile names;
- runs `Scripts/archive-release.sh`; and
- uploads the resulting `.xcarchive` bundles as workflow artifacts.

Required GitHub Actions secrets:

| Secret | Purpose |
|---|---|
| `APPLE_DEVELOPMENT_TEAM_ID` | 10-character Apple Developer Team ID |
| `APPLE_DISTRIBUTION_CERTIFICATE_BASE64` | Base64-encoded Apple Distribution `.p12` |
| `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` | Password for the `.p12` |
| `APPLE_PROVISIONING_PROFILE_IOS_BASE64` | Base64 iOS App Store provisioning profile |
| `APPLE_PROVISIONING_PROFILE_TVOS_BASE64` | Base64 tvOS app provisioning profile |
| `APPLE_PROVISIONING_PROFILE_TOPSHELF_TVOS_BASE64` | Base64 tvOS Top Shelf extension profile |
| `APPLE_PROVISIONING_PROFILE_VISIONOS_BASE64` | Base64 visionOS App Store provisioning profile |
| `APPLE_PROVISIONING_PROFILE_MACOS_BASE64` | Base64 macOS App Store provisioning profile |

Local archive command:

```sh
Scripts/archive-release.sh ios tvos visionos macos
```

## Remaining Submission Steps (Account-Blocked)

- Select the Apple Developer Program team and confirm bundle ID ownership.
- Create App Store provisioning profiles for the app plus the tvOS Top Shelf extension.
- Review per-platform capabilities in Xcode Signing & Capabilities for any
  provisioning-profile additions (e.g. Push Notifications if added later).
- Archive and validate Release builds for iOS/iPadOS, tvOS, visionOS, and macOS.
- Confirm macOS App Sandbox entitlements pass the archive-validation step (no unexpected
  file/network access).
