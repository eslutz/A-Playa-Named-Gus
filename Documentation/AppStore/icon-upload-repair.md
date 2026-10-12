# App Store icon upload repair

Cloud Build 7 produced correctly signed iOS and embedded Watch App Store exports,
but failed the later generic App Store Connect preparation step. Independent
Apple `altool --validate-app` validation of that exact IPA returned three concrete
rejections: `90396` for a Watch icon alpha channel and `90717` for the Watch and
iOS large app icons. The export/session-proxy warning is not the established cause.

The current generated project compiles `AppIcon.appiconset` PNGs. No Icon Composer
`.icon` package is present in this checkout or its companion repositories. Apple's
[Icon Composer integration](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
uses the saved `.icon` directly in Xcode and supersedes the earlier asset catalog.
This does not establish whether an original Composer file exists elsewhere.

`Scripts/flatten-app-icon-background.swift` uses Core Graphics/ImageIO to preserve
the existing full-color iOS and Watch artwork on an opaque deep-teal canvas. Both
PNGs are RGB without an alpha channel. Native pixel comparison found zero changes
in the previously opaque artwork; only the transparent rounded corners are filled.
The filenames, dimensions, asset mappings, runtime code, and package pins remain
unchanged. Mac icons retain native transparency, and iOS appearance variants retain
their supported transparency, per Apple's
[asset-catalog guidance](https://developer.apple.com/documentation/xcode/configuring-your-app-icon).

`Scripts/check-app-icons.py` now runs in Docs and Config CI. It rejected the original
default iOS PNG and accepts the repaired iOS/Watch assets. It reads PNG metadata
without an extra imaging dependency. Shared-project consistency and formatting
passed. Full corrected-source CI and the signed release retry remain pending.
