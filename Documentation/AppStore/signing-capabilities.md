# Signing and Capabilities

Status: not complete. Current local builds use development/ad-hoc signing only.

## Current State

- Bundle ID: `dev.ericslutz.gus`.
- Local simulator builds sign to run locally.
- No App Store team, distribution certificate, provisioning profile, or archive validation
  has been completed in this branch.

## Required Before Submission

- Select the final Apple Developer Program team.
- Confirm bundle ID availability and ownership.
- Enable automatic signing or commit explicit App Store signing configuration.
- Archive and validate release builds for iOS/iPadOS, tvOS, visionOS, and macOS.

## Capability Review

- Background audio: required for playback/PiP behavior.
- Local network: required for optional Jellyfin discovery.
- Keychain: required for Jellyfin access tokens.
- App Sandbox on macOS: review entitlements before archive.
- Optic ID / Face ID usage string: present; confirm it matches actual platform behavior.
- Offline downloads: no extra capability expected for foreground Application Support
  storage.
