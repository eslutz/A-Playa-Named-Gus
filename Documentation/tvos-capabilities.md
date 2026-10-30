# Apple TV presentation and service boundaries

Apple TV follows Gus's shared navigation state, feature stores, profile client, media-provider operations and playback coordinator. TV presentation and focus adaptations live in `Sources/Platform/TV`; they retain native SwiftUI navigation, keyboards and AVKit transport.

Browsing uses readable headings and bounded artwork. Details separate artwork from metadata/actions and place episodes or tracks below. Secondary playlist/collection actions use More. Ordinary details retain the selected section's stack and focus history. Multi-field authentication and editing tasks occupy the TV viewport; selection sheets remain native. Closing prepared audio returns to Now Playing without stopping it; Stop remains explicit. Photos reserve title/count space outside the image.

Theme and appearance are independent, device-local preferences. Gus Default, Apple Default and Custom use the existing storage format. Custom accents offer named presets and optional six-digit sRGB hex entry. Save commits an accent draft; Cancel discards it. Native focus treatment remains system-owned. iPhone/iPad retain their system color picker and existing presentation.

## Isolated validation

Use a newly created TV simulator identified by UDID, never `booted` or a shared device. The fixture script supports `GUS_DEMO_CONTAINER`, `GUS_DEMO_PORT` and `GUS_DEMO_MEDIA_DIR` so a separate container and configuration/cache volumes can serve the existing sample media read-only. Defaults retain the standard developer fixture.

Start the synthetic Seerr API with `python3 Scripts/tvos-seerr-fixture.py --port 5059` for the TV setup/request test. It accepts only the documented fixture account, binds to loopback and keeps mutations in memory.

Pass `TEST_RUNNER_GUS_DEMO_URL=http://127.0.0.1:<port>` to authenticated Xcode tests. The runner forwards this to the app's DEBUG-only `GUS_DEMO_URL` override. The app permits loopback HTTP URLs only; release authentication is unchanged. Wait for observable loading/focus states and use `XCUIRemote`, including containing Cells or anonymous native focus wrappers. After modal dismissal, wait for native focus to return before asserting its destination. Coordinate tapping is not a TV acceptance path.

Keep screenshots, result bundles and comparison manifests outside Git. Preserve original app/Sketch images when adding implementation captures to the private TV report. Capture coverage, action acceptance and physical-device acceptance are recorded separately.

## Capability limits

No new backend or runtime dependency is required. Respect existing provider permissions, restriction gates and mutation reconciliation. Requests with uncertain outcomes require readback before retry. Populated Live TV requires tuner/guide/channel data, subtitle switching requires subtitle-bearing media, and output routing/Top Shelf require suitable system or physical-device conditions. tvOS continues to exclude downloads and an EPUB reader; unsupported list/album toggles and nonexistent member-removal confirmations are not implied by presentation consistency.

The deployment floor remains tvOS 26.0. Simulator results do not establish physical television rendering, Siri Remote acceptance, exact minimum-OS behavior or signed distribution readiness.
