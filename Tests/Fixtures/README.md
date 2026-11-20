# Media test fixtures

## Offline playlist

`OfflinePlaylist.mov` is an owned, generated four-second black H.264 video: 32 × 32 pixels, 16 frames at four frames per second, no audio. It contains no library or user media. It is packaged into unit-test bundles through `Scripts/package-test-fixtures.sh`; it is not a production app resource.

It was generated once with the native `AVAssetWriter` helper previously in `VideoPlaylistPlaybackTests.swift` at commit `e28d248`. AVFoundation verified duration 4 seconds, one H.264 video track and `isPlayable == true`. SHA-256: `7c607fd3aea14aee885f2a36d4896b4724238a497de8f7229dbd6f55f77d6171`.

The integration test copies this immutable fixture into its temporary download store and still requires real AVPlayer readiness, one-second seeking, a durable cursor after cache reload and zero provider requests. Keep the fixture immutable and bundled. Do not encode media at test runtime: encoder readiness is not the playback behavior these tests verify.

## Related-search backdrop

The loopback genre scenario in [book-details-fixture.py](../../Scripts/book-details-fixture.py)
serves `RelatedMovieBackdrop.jpg` directly from the checkout for The Lantern House.
Unlike the MOV, the JPEG is not bundled into unit tests. Night Radio intentionally
has no artwork to exercise the fallback. The still comes from the public-domain
1896 film *The Kiss*. [Library of Congress film record](https://www.loc.gov/item/00694131/)

SHA-256: `4a598a79fb367d8684b504b6ad9c75c0bb8d8cd63aa7bda69d1e2afda386d916`.

From the checkout root, verify both files with
`shasum -a 256 Tests/Fixtures/OfflinePlaylist.mov Tests/Fixtures/RelatedMovieBackdrop.jpg`.
Update the provenance, checksum, and affected consumers if replacing a fixture.
