# Screenshots and TestFlight

**Current policy (October 12):** protected main requires PRs and all GitHub checks. The saved main-only Cloud release tests iPhone/iPad/Duo, Mac, TV and Vision before internal distribution. Native Icon Composer source is restored and Cloud Build 8 passed without issues; CI run 38242041231 retained one iPad native audio completion failure. Tester availability remains unconfirmed until the new gates pass. [Pipeline policy](pipeline-policy.md), [release status](internal-testflight-release.md).


## Current internal beta preparation

Internal distribution and access for the existing account are authorized. The
manual workflow archives iOS/macOS/tvOS/visionOS for internal-only testing, with
Watch embedded in iOS and four `Gus Internal` group post-actions. Runtime code
passed CI `38230709289` **13/13** and warning-free Cloud BUILD validation.

Build 7 produced signed exports but iOS preparation rejected alpha-bearing
icons, so all distribution post-actions were skipped. The default iOS/Watch
catalog repair is published at `64b9de6`; its new pipeline and signed retry are
pending. Watch provisioning/export and Mac/tvOS/visionOS upload processing passed
in Build 7. Membership remains distinct from build/install access: the latest
pre-retry group snapshot has one account tester, `NOT_INVITED`, and no builds.
[Icon diagnosis](icon-upload-repair.md), [release report](internal-testflight-release.md).
Marketing version remains **1.0.0**; Cloud assigns the integer build number.

## Automated Capture

`Scripts/screenshots.sh` captures App Store screenshots from simulators. The script
builds the app, boots the required simulator, installs, launches, waits for the app to
settle, and captures a PNG to `Screenshots/<platform>/` (git-ignored).

```sh
Scripts/screenshots.sh --list    # show resolved destinations and UDIDs
Scripts/screenshots.sh iphone    # iPhone 6.9" only
Scripts/screenshots.sh ipad      # iPad 13" only
Scripts/screenshots.sh tv        # Apple TV 1080p only
Scripts/screenshots.sh vision    # Apple Vision Pro only
Scripts/screenshots.sh watch     # Apple Watch companion only
Scripts/screenshots.sh mac       # print manual macOS instructions
Scripts/screenshots.sh           # all simulator platforms
```

Run `xcodegen generate` before the script if the Xcode project is stale.

**Without a live server**, the script captures only the Connect screen for each
platform. **With `Scripts/demo-server.sh` running**, it signs in via
`--gus-demo-server` and also captures the signed-in scenes automatically: Home,
Libraries, and Settings, plus deep-linked content scenes (movie detail, music album,
book detail, and full-screen video playback) through `--gus-route` with
`gus://item/<id>` / `gus://play/<id>` content links. The watch captures its Connect
screen plus the signed-in Remote glance. See the scenes table below.

## Screenshot Size Matrix

App Store Connect requires screenshots matching specific device display sizes.
The script targets these automatically:

| Platform | Device | Resolution | Script target |
|---|---|---|---|
| iPhone | iPhone 17 Pro Max | 1320×2868 (@3x, 6.9") | `iphone` |
| iPad | iPad Pro 13-inch (M5) | 2064×2752 (@2x, 13") | `ipad` |
| Apple TV | Apple TV 4K 3rd gen (1080p) | 1920×1080 | `tv` |
| Apple Vision Pro | Apple Vision Pro | 2980×2980 | `vision` |
| Apple Watch | Apple Watch Ultra 3 (49mm) | 410×502 | `watch` |
| Mac | Manual (see below) | 1280×800 or 2560×1600 | `mac` |

> **Note:** The script resolves UDIDs from the simulators installed on the current
> machine by device name, preferring the newest runtime. If Xcode is updated or
> simulators are re-created, verify the configured device names and resolved
> destinations rather than editing hardcoded UDIDs. Confirm with:
> `xcodebuild -showdestinations -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus'`

## Required Scenes

Capture these scenes for each platform. Auto = script captures it with no server;
Auto-demo = script captures it when the local demo server is running; Manual =
requires capturing by hand.

| Scene | iPhone | iPad | TV | Vision | Watch | Mac | Notes |
|---|---|---|---|---|---|---|---|
| Connect screen | Auto | Auto | Auto | Auto | Auto | Manual | First impression |
| Home (libraries + Continue Watching) | Auto-demo | Auto-demo | Auto-demo | Auto-demo | — | Manual | Shows main content |
| Libraries / Settings | Auto-demo | Auto-demo | Auto-demo | Auto-demo | — | Manual | Appearance + Navigation + Restrictions |
| Item Detail (movie, album, book) | Auto-demo | Auto-demo | Auto-demo | Auto-demo | — | Manual | Via `gus://item/<id>` deep link |
| Playback (full-screen) | Auto-demo | Auto-demo | Auto-demo | Auto-demo | — | Manual | Via `gus://play/<id>` deep link |
| Remote glance | — | — | — | — | Auto-demo | — | Watch companion highlight |
| TV-series / Live TV scenes | — | — | — | — | — | — | Blocked on demo data (no series/tuner) |
| Gus Cinema | — | — | — | Manual | — | — | visionOS immersive highlight |

> Avoid personal server URLs and real usernames. Use non-sensitive media and
> artwork authorized for the intended publication in the demo server.

## macOS Screenshots (Manual)

App Store Connect accepts macOS screenshots at: **1280×800**, 1440×900, 2560×1600,
or 2880×1800.

```sh
Scripts/screenshots.sh mac    # prints step-by-step instructions
```

Steps:
1. Build and run the `Debug` or `Release` scheme on macOS in Xcode.
2. Resize the A Playa Named Gus window to 1280×800 (hold Option and drag the resize handle
   for exact sizing, or use a window-sizing utility).
3. Press **Cmd+Shift+4 → Space → click the A Playa Named Gus window** to capture just the
   window.
4. Repeat for each required scene.
5. Move the resulting PNGs to `Screenshots/mac/` (git-ignored).

On a Retina display you will get a @2x PNG (2560×1600) which App Store Connect
accepts for the 2560×1600 slot.

## TestFlight Checklist

For the requested internal beta:

- [x] App record, account-wide API authentication, and initial Cloud onboarding verified.
- [x] Shared project, 16 dependency pins, and reviewed source published on `main`
      through `64505d9`.
- [x] The BUILD-validation workflow runs the committed Cloud bootstrap with automatic
      signing Team ID `QS3GC3CT43`; Build 3 passed all four actions.
- [x] Main app `ITSAppUsesNonExemptEncryption = false` is present in `Resources/Info.plist`.
- [x] Required pipelines passed for published `64505d9` before Build 4; the later Mac
      metadata revision `2546563` awaits hosted acceptance.
- [x] Configure the separate manual Release ARCHIVE actions with an internal-only
      audience and the intended internal group/post-action; preserve validation-only CI.
- [x] Register exact embedded Watch bundle `dev.ericslutz.gus.watchkitapp`
      (`X7N8FKWCC6`); this does not establish its generated distribution profile.
- [x] Add the existing eligible App Store Connect account to `Gus Internal`.
- [ ] Verify required pipelines for the corrected release candidate.
- [ ] Xcode Cloud signed archives build for iOS/iPadOS, tvOS, visionOS, and macOS.
- [ ] Xcode Cloud validation passes for the archives intended for TestFlight upload.
- [ ] Confirm main app and embedded Watch/Top Shelf signatures, profiles, entitlements,
      and matching marketing/build versions. No ad-hoc Mac-unit signing fixture belongs
      in a distribution archive.
- [ ] Confirm uploads finish processing and export compliance permits internal testing.
- [ ] Verify each processed build is accessible to the internal group and the
      tester receives access; the last snapshot remained `NOT_INVITED`.
- [ ] Verify the actual TestFlight build installs and launches on supported devices.

Earlier development signing/physical checks used **1.0.0 (11)**; they do not establish
the later candidate's TestFlight installation. Cloud automatic signing does not require
a new local device build. `Scripts/validate-release.py` deliberately produces unsigned
local archives and cannot validate distribution signing or upload a beta.

Create the internal group before configuring a Cloud internal TestFlight post-action.
The group must contain eligible App Store Connect users; selecting the user's existing
account avoids assuming an email-only external tester is an internal team member.
Cloud builds do not automatically join every group's automatic-distribution feed:
configure the explicit post-action or add the processed builds to the group manually.
See [Apple's Cloud distribution guide](https://developer.apple.com/documentation/xcode/distributing-your-xcode-cloud-builds-through-testflight)
and [internal tester instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers).

The following public/external release preparation remains separate from the current
internal-only request; internal testing does not require Beta App Review:

- [ ] App Privacy answers complete in App Store Connect (source: `privacy-labels.md`).
- [ ] Privacy policy URL added for iOS/iPadOS/macOS/visionOS.
- [ ] tvOS privacy policy text added.
- [ ] Accessibility URL added and App Store accessibility disclosures completed
      (source: `accessibility.md`).
- [ ] Beta app description, features-to-test note, feedback email entered.

Core flows to test on each shipped platform:
- Connect to a server (HTTP and HTTPS).
- Sign in with username/password and with Quick Connect.
- Browse libraries; search.
- Open item detail; play media.
- Verify Now Playing on lock screen / Control Center.
- Test AirPlay routing (requires AirPlay-capable device).
- Test Picture in Picture backgrounding (iOS/iPadOS/macOS).
- Download an item; play offline; delete (iOS/iPadOS/macOS/visionOS).
- Sign out; switch accounts.
- visionOS: enter and exit Gus Cinema during playback.

Run the accessibility Release Checklist in `accessibility.md` before release.

Track crashes, sessions, and tester feedback in App Store Connect -> TestFlight.
