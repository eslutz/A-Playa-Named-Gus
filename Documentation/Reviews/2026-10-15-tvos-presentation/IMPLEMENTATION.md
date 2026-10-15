# tvOS presentation repair

The seven physical-TV photographs show an inset canvas exposing bright background edges, default padded button surrounds on media cards, unreadable focused Play text, and compact cast/About sections.

The repair uses native `CardButtonStyle` for media links and native bordered hero actions, with focus-controlled foreground color. TV browsing gets one full-screen artwork canvas with a dark scrim; detail gets a black canvas and a full-bleed hero. Cast portraits and About cards use TV-specific dimensions. Progress overlays follow a rounded capsule and titles reserve two lines. Shared touch/pointer layouts retain their existing metrics and action foreground styling.

The app's existing native navigation, focus memory, remote controls, accessibility labels and context actions are retained. The UI regression traverses Play, More, synopsis and About using `XCUIRemote`, and captures actual loaded screens from the rights-cleared local Jellyfin fixture. Unsigned simulator UI fixtures use the existing `--gus-disable-cloud-sync` launch flag; this does not establish signed CloudKit acceptance.

Validation used Xcode 27.1 RC and ARM destinations:

| Gate | Result |
| --- | --- |
| tvOS unit tests and remote UI regression | 452 unit-test results and 1 targeted remote UI test passed; 0 failures, 0 skipped |
| tvOS build, iOS/iPadOS universal build, macOS, visionOS, watchOS builds | Passed with zero warnings or errors |
| SwiftFormat, generated-project consistency, whitespace | Passed |

The UI regression verifies Play focus, native More focus, synopsis presentation/dismissal, navigation into About, and Home card focus after relaunch. Screenshots were inspected after the passing run.

Evidence: [Home](evidence/tv-home-cards.png), [Play focused](evidence/tv-detail-play-focused.png), [More focused](evidence/tv-detail-more-focused.png), [About focused](evidence/tv-about-focused.png), [full synopsis](evidence/tv-full-synopsis.png). [Test results](evidence/tvos-tests.json), [platform builds](evidence/platform-builds.json), and [changed source hashes](evidence/source-manifest.json) record the candidate. Full logs and result bundles remain under `/tmp/gus-branch-cleanup-20261015/`.

The final candidate includes the playback remux fix from PR #27 and the asynchronous seek-readiness test correction from PR #26. All platform builds and the full tvOS unit suite plus targeted remote UI regression were repeated on that combined source tree. The affected preparation suite also passed five repetitions each on iPhone and visionOS (35 result cases per platform). Main is updated to `ab233d5`; all 367 tracked build inputs in the working tree match the validated candidate. The presentation repair is prepared for PR review; hosted validation and merge are separate from the local results above. Physical Apple TV viewing-distance and remote acceptance remain separate from simulator evidence. No TestFlight availability is claimed.


References: [Apple card button style](https://developer.apple.com/documentation/swiftui/cardbuttonstyle), [Apple layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout).
