# A Playa Named Gus

A Playa Named Gus is an Apple-first, multiplatform Jellyfin client for iOS,
iPadOS, tvOS, visionOS, and macOS, with a watchOS companion app. It is built
with SwiftUI, Observation, AVKit, and the Jellyfin Swift SDK, with a project
rule of preferring Apple/system frameworks over custom or third-party runtime
code.

The repository is private while early development continues. The public
documentation home is the [GitHub wiki](https://github.com/eslutz/A-Playa-Named-Gus/wiki);
this README stays intentionally short.

## Quick Start

```sh
brew install xcodegen
xcodegen generate
xcodebuild -resolvePackageDependencies -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus'
xcodebuild -showdestinations -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus'
```

`project.yml` is the source of truth for the generated Xcode project.
Regenerate `A Playa Named Gus.xcodeproj` after adding, renaming, or deleting
source and resource files.

## Contributing

Use the [issues page](https://github.com/eslutz/A-Playa-Named-Gus/issues) for bugs and
feature requests. Use
[Discussions](https://github.com/eslutz/A-Playa-Named-Gus/discussions) for questions,
support, and design/development conversations that are not yet actionable
issues.

See the [Contributing wiki page](https://github.com/eslutz/A-Playa-Named-Gus/wiki/Contributing)
for contribution details.
