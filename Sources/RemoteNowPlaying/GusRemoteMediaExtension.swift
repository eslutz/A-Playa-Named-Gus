import ExtensionFoundation
import Foundation
import NowPlaying

@main
struct GusRemoteMediaExtension: RemoteMediaSessionExtension {
    var configuration: RemoteMediaSessionExtensionConfiguration<Self> {
        RemoteMediaSessionExtensionConfiguration(extension: self)
    }

    func session(_ attributes: GusRemotePlaybackAttributes) async throws -> GusRemoteMediaStatus {
        GusRemoteMediaStatus(attributes: attributes)
    }
}

@MainActor
final class GusRemoteMediaStatus: RemoteMediaSessionRepresentable {
    private var attributes: GusRemotePlaybackAttributes
    let id: String

    init(attributes: GusRemotePlaybackAttributes) {
        id = attributes.id
        self.attributes = attributes
    }

    func update(_ attributes: GusRemotePlaybackAttributes) {
        self.attributes = attributes
    }

    var content: (any MediaContentRepresentable)? {
        guard attributes.isFresh(at: .now) else { return nil }
        var item = GenericContent(
            id: attributes.contentID, title: attributes.title ?? String(localized: "Remote Playback"),
            type: attributes.isAudio ? .audio : .video, duration: attributes.duration.map(MediaDuration.finite), artwork: nil
        )
        item.isExcludedFromSuggestions = true
        return item
    }

    var playbackSnapshot: MediaPlaybackSnapshot? {
        guard attributes.isFresh(at: .now) else { return nil }
        return MediaPlaybackSnapshot(
            state: attributes.isPaused ? .paused : .playing(),
            elapsedTime: attributes.elapsed, timestamp: attributes.observedAt
        )
    }

    /// The extension has no credentials or authenticated command transport. The
    /// foreground app owns commands and resolves controllable sessions before use.
    var commands: [MediaCommand] {
        []
    }

    var devices: [MediaDevice] {
        []
    }
}
