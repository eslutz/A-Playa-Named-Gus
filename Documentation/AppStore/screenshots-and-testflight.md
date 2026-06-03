# Screenshots and TestFlight

## Screenshot Matrix

Apple's screenshot specifications currently require screenshots for each shipped platform.
Relevant sizes include Mac 16:10 screenshots such as 1280x800, 1440x900, 2560x1600, or
2880x1800; Apple TV 1920x1080 or 3840x2160; and Apple Vision Pro 3840x2160.

| Platform | Capture target | Required scenes |
|---|---|---|
| iPhone | iPhone 17 simulator or current App Store required iPhone sizes | Connect, Home, Item Detail, Player, Settings |
| iPad | iPad Pro 11-inch (M5) or current App Store required iPad sizes | Split home/library, Item Detail, Player, Settings |
| Apple TV | Apple TV 4K simulator, 1920x1080 | Home, library grid, item detail, player |
| Apple Vision Pro | Apple Vision Pro simulator, 3840x2160 | Windowed app, item detail, player, Gus Cinema |
| Mac | Mac app window at accepted 16:10 size | Sidebar, home/library, item detail, player/downloads |

## Capture TODO

- Seed a demo Jellyfin server with non-sensitive sample media.
- Script repeatable simulator launch and screenshot capture where possible.
- Confirm any platform-specific App Store Connect replacement rules before upload.
- Avoid showing personal server URLs, user names, or copyrighted artwork without rights.

## TestFlight Checklist

- Provide beta app description, features to test, feedback email, and export compliance.
- Upload a signed build to App Store Connect.
- Invite internal testers first.
- Invite external testers after the first beta review if needed.
- Test connect, sign in, browse, search, detail, playback, Now Playing, AirPlay/PiP, local
  downloads on supported platforms, deletion, and sign-out.
- Track crashes, sessions, and tester feedback in App Store Connect.
