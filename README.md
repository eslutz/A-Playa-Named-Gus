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
the 27.1 SDK to compile. Deployment targets remain iOS/tvOS 18, visionOS 2,
macOS 15, and watchOS 11; an SDK build does not establish minimum-OS execution.

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

Changes now require a pull request into protected `main`, with all 13 GitHub
checks passing. Xcode Cloud tests merged `main` on iPhone, iPad, Duo, Mac, Apple TV
and Vision before internal TestFlight distribution. The old compile-only Cloud
workflow is deleted. [Pipeline policy](Documentation/AppStore/pipeline-policy.md).

The native Icon Composer source is restored at `Resources/AppIcon.icon` and
passed four-platform Cloud Build 8 with zero issues. Its GitHub matrix passed
12/13 jobs; iPad retained the recurring native audio end-notification failure.
The failure is recorded and a successful PR/Cloud release gate is still required
before tester installation access is claimed.
[Release report](Documentation/AppStore/internal-testflight-release.md).

## Contributing

Use the [issues page](https://github.com/eslutz/A-Playa-Named-Gus/issues) for bugs and
feature requests. Use
[Discussions](https://github.com/eslutz/A-Playa-Named-Gus/discussions) for questions,
support, and design/development conversations that are not yet actionable
issues.

See the [Contributing wiki page](https://github.com/eslutz/A-Playa-Named-Gus/wiki/Contributing)
for contribution details.
