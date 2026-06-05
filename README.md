# Gus

Gus is an Apple-first, multiplatform Jellyfin client for iOS, iPadOS, tvOS,
visionOS, and macOS. It is built with SwiftUI, Observation, AVKit, and the
Jellyfin Swift SDK, with a project rule of preferring Apple/system frameworks
over custom or third-party runtime code.

The repository is private while early development continues. The public
documentation home is the GitHub wiki; this README stays intentionally short.

## Quick Start

```sh
brew install xcodegen
xcodegen generate
xcodebuild -resolvePackageDependencies -project Gus.xcodeproj -scheme Gus
xcodebuild -showdestinations -project Gus.xcodeproj -scheme Gus
```

`project.yml` is the source of truth for the generated Xcode project.
Regenerate `Gus.xcodeproj` after adding, renaming, or deleting source and
resource files.

## Contributing

Use the issue forms for bugs and feature requests. Use Discussions for
questions, support, and design/development conversations that are not yet
actionable issues.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution checklist and
[AGENTS.md](AGENTS.md) for the project architecture, conventions, and native API
mandate.
