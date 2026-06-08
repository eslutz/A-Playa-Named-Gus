# ADR 0007: HEVC HLS transcoding evidence gate

## Status

Accepted

## Context

A Playa Named Gus keeps playback AVKit-first. Direct-play HEVC is already advertised for AVKit-native containers (`mp4`, `m4v`, `mov`), while the reliable HLS fallback transcodes to H.264/AAC MPEG-TS. HEVC inside the existing MPEG-TS HLS fallback is not enabled because it can produce streams that AVPlayer on iOS or tvOS may reject.

## Evidence

# HEVC HLS Evidence

## PlaybackInfo

- TranscodingUrl: https://jellyfin.example.com:8096/videos/REDACTED_ITEM_ID/master.m3u8?&DeviceId=REDACTED&MediaSourceId=REDACTED&VideoCodec=hevc&AudioCodec=aac&AudioStreamIndex=1&SubtitleStreamIndex=8&VideoBitrate=119616000&AudioBitrate=384000&MaxFramerate=23.976025&SegmentContainer=mp4&MinSegments=2&BreakOnNonKeyFrames=False&PlaySessionId=REDACTED&ApiKey=REDACTED&TranscodingMaxAudioChannels=2&RequireAvc=false&EnableAudioVbrEncoding=true&Tag=REDACTED&SubtitleMethod=Encode&hevc-level=150&hevc-videobitdepth=10&hevc-profile=main10&TranscodeReasons=ContainerNotSupported,SubtitleCodecNotSupported&api_key=REDACTED
- TranscodingContainer: mp4
- TranscodingSubProtocol: hls

## Playlist

- CODECS line: #EXT-X-STREAM-INF:BANDWIDTH=13591037,AVERAGE-BANDWIDTH=13591037,VIDEO-RANGE=SDR,CODECS="hvc1.2.4.L150.B0,mp4a.40.2",RESOLUTION=3840x2160,FRAME-RATE=23.976
- Contains HEVC codec: true
- Contains EXT-X-MAP: true
- First media segment: hls1/main/0.mp4?&DeviceId=REDACTED&MediaSourceId=REDACTED&VideoCodec=hevc&AudioCodec=aac&AudioStreamIndex=1&SubtitleStreamIndex=8&VideoBitrate=119616000&AudioBitrate=384000&MaxFramerate=23.976025&SegmentContainer=mp4&MinSegments=2&BreakOnNonKeyFrames=False&PlaySessionId=REDACTED&ApiKey=REDACTED&TranscodingMaxAudioChannels=2&RequireAvc=false&EnableAudioVbrEncoding=true&Tag=REDACTED&SubtitleMethod=Encode&hevc-level=150&hevc-videobitdepth=10&hevc-profile=main10&TranscodeReasons=ContainerNotSupported,SubtitleCodecNotSupported&api_key=REDACTED&runtimeTicks=0&actualSegmentLengthTicks=30030000
- First media segment looks fMP4: true

## Evidence Gate

- Automated gate passed: true
- Manual iOS playback passed: true
- Manual tvOS playback passed: true

## Raw PlaybackInfo Keys

MediaSources, PlaySessionId

## Decision

Do not enable production HEVC HLS transcoding until the evidence gate passes on both iOS and tvOS. If the automated playlist gate passes but either manual playback check fails, keep the production profile H.264-only and leave direct-play HEVC unchanged.

The evidence gate passed, so A Playa Named Gus advertises a separate HEVC/AAC fMP4 HLS profile before the existing H.264/AAC MPEG-TS fallback. The H.264 TS profile remains unchanged, and direct-play HEVC remains available for compatible sources.

## Consequences

- Direct-play HEVC remains available for compatible sources.
- H.264/AAC MPEG-TS remains the reliable HLS fallback.
- HEVC transcoding is introduced only as a separate fMP4 HLS profile, not by adding `hevc` to the existing `ts` profile.
