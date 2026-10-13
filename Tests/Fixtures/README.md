# Offline playlist video fixture

`OfflinePlaylist.mov` is an owned, generated four-second black H.264 video: 32 × 32 pixels, 16 frames at four frames per second, no audio. It contains no library or user media. It is packaged into unit-test bundles through `Scripts/package-test-fixtures.sh`; it is not a production app resource.

It was generated once with the native `AVAssetWriter` helper previously in `VideoPlaylistPlaybackTests.swift` at commit `e28d248`. AVFoundation verified duration 4 seconds, one H.264 video track and `isPlayable == true`. SHA-256: `7c607fd3aea14aee885f2a36d4896b4724238a497de8f7229dbd6f55f77d6171`.

The integration test copies this immutable fixture into its temporary download store and still requires real AVPlayer readiness, one-second seeking, a durable cursor after cache reload and zero provider requests. It must not encode media at test runtime: the iPad CI simulator failed at AVAssetWriter input readiness before any playback assertion. A packaged fixture also works when Xcode Cloud's test worker has no source checkout.
