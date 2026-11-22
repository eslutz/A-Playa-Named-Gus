#if os(iOS)
    import Foundation
    import NowPlaying

    /// Only transient presentation values cross into the remote session extension.
    @available(iOS 27, *)
    struct GusRemotePlaybackAttributes: RemoteMediaSessionAttributes, Sendable {
        var id: String
        var deviceID: String
        var deviceType: MediaDevice.DeviceType
        var contentID: String
        var title: String?
        var isAudio: Bool
        var isPaused: Bool
        var duration: TimeInterval?
        var elapsed: TimeInterval?
        var observedAt: Date

        func isFresh(at date: Date) -> Bool {
            (0 ..< 45).contains(date.timeIntervalSince(observedAt))
        }
    }
#endif
