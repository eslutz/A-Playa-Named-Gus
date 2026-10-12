# App Store icon upload repair

Cloud Build 7 produced correctly signed iOS and embedded Watch App Store exports,
but failed the later generic App Store Connect preparation step. Independent
Apple `altool --validate-app` validation of that exact IPA returned three concrete
rejections: `90396` for a Watch icon alpha channel and `90717` for the Watch and
iOS large app icons. The export/session-proxy warning is not the established cause.

Build 7 compiled `AppIcon.appiconset` PNGs and had no Icon Composer source.
The user could not locate the original, so an editable native package was recreated
in Apple Icon Composer and published at `f1a387f`. See [source and previews](icon-composer-source.md). Apple's
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
passed. The corrected PNG source passed all 13 CI checks in run `38237504737`.
The recreated native source passed Cloud Build 8 with zero issues. Its separate
CI run `38242041231` passed 12/13 jobs; iPad failed its native audio completion case,
while the icon and EPUB assertions passed. Signed upload acceptance is still required.

The first repaired-asset matrix (`38236570835`) exposed an older test requiring byte-identical iOS and visionOS PNG files. That conflicts with their supported platform formats. Commit `f354c7a` compares full decoded RGBA artwork on the same native deep-teal canvas instead, retaining Watch byte equality and all stale-artwork hash checks. Independent native rendering found zero differences across the complete rendered canvases. The failed Mac attempt is retained in [the diagnostic record](cloud-onboarding-evidence/github-ci/run-38236570835-macos-icon-assertion-failure.json); the superseded matrix was cancelled, and corrected CI `38237504737` passed all 13 checks. No failed test is counted as a passing gate.

The exact revised Swift Testing assertion/helper also passed compiler-only Xcode 27.1 RC verification with Swift 6, complete concurrency checking, and warnings as errors after supplying Xcode's Testing framework and macro plugin. This is a bounded compiler check; full platform execution subsequently passed in CI `38237504737`.
