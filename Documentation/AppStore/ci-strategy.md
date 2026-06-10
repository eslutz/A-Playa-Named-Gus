# CI Strategy

GitHub Actions protects source quality. Xcode Cloud produces distributable Apple
builds.

## GitHub Actions

Run on every pull request and every push to `main`:

| Task | Owner |
|---|---|
| PR build checks (iOS, iPadOS, tvOS, visionOS, macOS, watchOS) | GitHub Actions |
| Unit tests | GitHub Actions |
| SwiftFormat lint | GitHub Actions |
| String catalog validation | GitHub Actions |
| Markdown/docs validation | GitHub Actions |
| Plist, entitlement, and workflow syntax validation | GitHub Actions |
| Swift package dependency resolution | GitHub Actions |
| GitHub issue/PR automation | GitHub Actions |
| AI coding-agent validation loops | GitHub Actions |
| Cross-platform or non-Apple tooling | GitHub Actions |
| Backend/API test jobs | GitHub Actions |

Secret scanning should stay in GitHub's repository security settings rather than
as a signing workflow. Do not store Apple signing certificates or provisioning
profiles as GitHub Actions secrets for Gus release builds.

## Xcode Cloud

Use Xcode Cloud for Apple-distributable work:

| Task | Owner |
|---|---|
| Signed iOS, iPadOS, tvOS, visionOS, and macOS builds (watch ships in the iOS archive) | Xcode Cloud |
| Code signing and provisioning | Xcode Cloud |
| Internal TestFlight builds | Xcode Cloud |
| External beta TestFlight builds | Xcode Cloud |
| App Store release archives | Xcode Cloud |
| Notarized Mac app builds | Xcode Cloud |
| Apple device and simulator matrix testing | Xcode Cloud |
| UI tests on Apple targets | Xcode Cloud |
| Release candidate validation | Xcode Cloud |

`ci_scripts/ci_post_clone.sh` installs XcodeGen when needed, validates that Xcode Cloud
is using Team ID `QS3GC3CT43`, writes a temporary automatic-signing override, and
regenerates `A Playa Named Gus.xcodeproj` before Xcode Cloud builds. Keep the generated
project out of git.

## Default Triggers

- Every PR: GitHub Actions.
- Every merge to `main`: GitHub Actions, plus optional Xcode Cloud build.
- Every tagged beta or release candidate: Xcode Cloud.
- Every TestFlight or App Store build: Xcode Cloud.
