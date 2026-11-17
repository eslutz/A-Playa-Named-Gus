# A Playa Named Gus

A Playa Named Gus is an Apple-first, multiplatform Jellyfin client for iOS,
iPadOS, tvOS, visionOS, and macOS, with a watchOS companion app. It is built
with SwiftUI, Observation, AVKit, and the Jellyfin Swift SDK, plus Readium on
iOS/iPadOS for EPUB reading, with a project
rule of preferring Apple/system frameworks over custom or third-party runtime
code.

The documentation home is the [GitHub wiki](https://github.com/eslutz/A-Playa-Named-Gus/wiki);
this README stays intentionally short.

## Quick Start

Use Xcode 27.1 or newer: the availability-guarded Duo arrangement APIs require
the 27.1 SDK to compile. The minimum OS version is 26.0 on iOS/iPadOS, tvOS, visionOS, macOS, and
watchOS. Use OS 27.x features when available, with OS 26-compatible fallbacks.
An SDK build does not establish minimum-OS execution.

```sh
brew install xcodegen
xcodegen generate
xcodebuild -onlyUsePackageVersionsFromResolvedFile -resolvePackageDependencies -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus'
xcodebuild -showdestinations -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus'
```

Mac builds support Apple Silicon only. Intel compilation is excluded for all
app, extension, simulator, and test targets; physical Watch builds retain their
SDK-supported ARM variants.

`project.yml` is the source of truth for the generated Xcode project.
Regenerate `A Playa Named Gus.xcodeproj` after adding, renaming, or deleting
source and resource files.

Changes to `main` require a PR and five GitHub checks: Validation Scope, Lint,
Docs and Config, Build macOS, and Test macOS. Simulator builds and tests run locally;
hosted native macOS unit tests have an explicit exception. Server-side main protection
is currently disabled; the PR/check requirement remains project policy.
[Pipeline policy](Documentation/AppStore/pipeline-policy.md).

The native Icon Composer source is restored at `Resources/AppIcon.icon`.
Historical Cloud results do not establish current release or tester access.
Release qualification requires exact-candidate local simulator evidence, current
PR checks, and authorized native archive/signing/distribution gates. Old Cloud
workflows containing simulator actions must not be started.
[Release report](Documentation/AppStore/internal-testflight-release.md).

## Designs

The [iPhone design](Design/Gus-iPhone.sketch), [iPadOS design](Design/Gus-iPadOS.sketch), and [shared library](Design/Gus-Shared-Library.sketch) each contain their Light and Dark content in one editable document. See [design organization and appearance coverage](Design/README.md). Historical design material is retained in the local, Git-ignored `Design/Archive/`. Design coverage does not establish runtime acceptance.

## Contributing

Use the [issues page](https://github.com/eslutz/A-Playa-Named-Gus/issues) for bugs and
feature requests. Use
[Discussions](https://github.com/eslutz/A-Playa-Named-Gus/discussions) for questions,
support, and design/development conversations that are not yet actionable
issues.

See the [Contributing wiki page](https://github.com/eslutz/A-Playa-Named-Gus/wiki/Contributing)
for contribution details.

## Discover with Seerr

Connect a Seerr 3 account to browse and request movies and series, track requests, review permitted manager actions, and manage supported issues and preferences. The connection stays scoped to this Gus account and device. See the [Discover guide](https://github.com/eslutz/A-Playa-Named-Gus/wiki/Discover) and [verified API contracts](Documentation/Seerr-api-contract.md).
