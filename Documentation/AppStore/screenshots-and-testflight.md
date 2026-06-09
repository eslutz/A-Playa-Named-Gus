# Screenshots and TestFlight

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
Scripts/screenshots.sh mac       # print manual macOS instructions
Scripts/screenshots.sh           # all simulator platforms
```

Run `xcodegen generate` before the script if the Xcode project is stale.

**Without a live server**, the script captures only the Connect screen for each
platform. Signed-in scenes (Home, Item Detail, Player, Downloads, Gus Cinema) require
a real or demo Jellyfin server. See the manual scenes table below.

## Screenshot Size Matrix

App Store Connect requires screenshots matching specific device display sizes.
The script targets these automatically:

| Platform | Device | Resolution | Script target |
|---|---|---|---|
| iPhone | iPhone 17 Pro Max | 1320×2868 (@3x, 6.9") | `iphone` |
| iPad | iPad Pro 13-inch (M4) | 2064×2752 (@2x, 13") | `ipad` |
| Apple TV | Apple TV 4K 3rd gen (1080p) | 1920×1080 | `tv` |
| Apple Vision Pro | Apple Vision Pro | 2980×2980 | `vision` |
| Mac | Manual (see below) | 1280×800 or 2560×1600 | `mac` |

> **Note:** The script resolves UDIDs from the simulators installed on the current
> machine. If Xcode is updated or simulators are re-created, update the UDIDs at
> the top of `Scripts/screenshots.sh`. Confirm with:
> `xcodebuild -showdestinations -project 'A Playa Named Gus.xcodeproj' -scheme 'A Playa Named Gus'`

## Required Scenes

Capture these scenes for each platform. Automated = script captures it with no
server; Manual = requires a connected Jellyfin server.

| Scene | iPhone | iPad | TV | Vision | Mac | Notes |
|---|---|---|---|---|---|---|
| Connect screen | Auto | Auto | Auto | Auto | Auto | First impression |
| Home (libraries + Continue Watching) | Manual | Manual | Manual | Manual | Manual | Shows main content |
| Item Detail | Manual | Manual | Manual | Manual | Manual | Metadata + Play button |
| Playback (full-screen) | Manual | Manual | Manual | Manual | Manual | Core feature |
| Downloads / Settings | Manual | Manual | — | Manual | Manual | tvOS has no downloads |
| Gus Cinema | — | — | — | Manual | — | visionOS immersive highlight |

> Avoid personal server URLs, real usernames, or copyrighted artwork. Seed a
> demo server with non-sensitive or rights-cleared sample media before capture.

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

Before uploading to TestFlight:
- [ ] Local device signing works with the real Apple Developer Team in
      `Config/Local.xcconfig`.
- [ ] Xcode Cloud workflow exists and runs `ci_scripts/ci_post_clone.sh` to generate the
      Xcode project and automatic-signing override for Team ID `QS3GC3CT43`.
- [ ] Xcode Cloud signed archives build for iOS/iPadOS, tvOS, visionOS, and macOS.
- [ ] Xcode Cloud validation passes for the archives intended for TestFlight upload.
- [ ] `ITSAppUsesNonExemptEncryption = false` confirmed in `Info.plist`.
- [ ] App Privacy answers complete in App Store Connect (source: `privacy-labels.md`).
- [ ] Privacy policy URL added for iOS/iPadOS/macOS/visionOS.
- [ ] tvOS privacy policy text added.
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

Track crashes, sessions, and tester feedback in App Store Connect -> TestFlight.
