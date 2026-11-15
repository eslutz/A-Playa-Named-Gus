import AVFoundation
import Foundation
import GroupActivities
import OSLog

/// The SharePlay payload for one Gus playback item.
///
/// The activity carries sanitized playback intent and display metadata only. Jellyfin access tokens, stream URLs, and
/// server credentials stay local to each participant's signed-in Gus session.
struct GusPlaybackActivity: Codable, GroupActivity, Hashable {
    enum ActivityKind: String, Codable {
        case watch
        case listen
        case read
    }

    let request: PlaybackRequest
    let itemID: String

    let title: String
    let subtitle: String?
    let serverID: String
    let activityKind: ActivityKind

    @MainActor init?(request: PlaybackRequest, session: SessionStore) {
        let item = request.item
        guard let itemID = item.id, session.isActive else { return nil }
        self.itemID = itemID
        self.request = request.sharingIntent
        title = item.displayTitle
        subtitle = item.yearText
        serverID = session.server.id
        activityKind = Self.activityKind(for: item)
    }

    var metadata: GroupActivityMetadata {
        get async {
            var metadata = GroupActivityMetadata()
            metadata.type = activityType
            metadata.title = title
            metadata.subtitle = subtitle ?? String(localized: "A Playa Named Gus", comment: "SharePlay activity subtitle fallback")
            metadata.supportsContinuationOnTV = true
            metadata.fallbackURL = ContentLink.play(id: itemID, serverID: serverID, provider: request.item.providerKind, request: request).url
            metadata.lifetimePolicy = .endsWhenInitiatorLeaves
            return metadata
        }
    }

    private var activityType: GroupActivityMetadata.ActivityType {
        switch activityKind {
        case .listen:
            return .listenTogether
        case .read:
            return .readTogether
        case .watch:
            return .watchTogether
        }
    }

    private static func activityKind(for item: MediaItem) -> ActivityKind {
        switch item.type {
        case .audio, .audioBook:
            return .listen
        case .book:
            return .read
        default:
            return .watch
        }
    }
}

@MainActor
@Observable
final class SharePlayCoordinator {
    /// Requires the Group Activities entitlement:
    /// `com.apple.developer.group-session`.
    static let shared = SharePlayCoordinator()

    private let logger = Logger(subsystem: Logger.subsystem, category: "SharePlay")
    private var listenerTask: Task<Void, Never>?
    private var currentSession: GroupSession<GusPlaybackActivity>?
    private var coordinatedPlayer: AVPlayer?
    private var coordinatedItemID: String?

    private(set) var isSharing = false
    var errorMessage: String?

    private init() {}

    nonisolated static func canShare(_ item: MediaItem) -> Bool {
        guard item.id != nil else { return false }
        switch item.type {
        case .movie, .episode, .video, .trailer, .audio, .audioBook, .book, .recording:
            return true
        default:
            return false
        }
    }

    func startListening(appModel: AppModel, navigation: AppNavigationModel) {
        guard listenerTask == nil else { return }
        listenerTask = Task { @MainActor [weak self] in
            for await session in GusPlaybackActivity.sessions() {
                self?.join(session, appModel: appModel, navigation: navigation)
            }
        }
    }

    func activity(for request: PlaybackRequest, session: SessionStore) -> GusPlaybackActivity? {
        guard Self.canShare(request.item),
              let activity = GusPlaybackActivity(request: request, session: session)
        else {
            return nil
        }
        return activity
    }

    func attachPlayer(_ player: AVPlayer?, request: PlaybackRequest, session: SessionStore) {
        guard let player,
              let itemID = request.item.id,
              session.isActive,
              let currentSession,
              currentSession.activity.serverID == session.server.id,
              currentSession.activity.request.item.providerKind == session.server.providerKind,
              currentSession.activity.itemID == itemID,
              currentSession.activity.request.streamSelection.mediaSourceID == nil || currentSession.activity.request.streamSelection.mediaSourceID == request.streamSelection.mediaSourceID
        else { return }

        if coordinatedPlayer !== player || coordinatedItemID != itemID {
            player.playbackCoordinator.coordinateWithSession(currentSession)
            coordinatedPlayer = player
            coordinatedItemID = itemID
            session.onInvalidation(of: self) { owner in owner.leaveCurrentSession() }
        }
    }

    func leaveCurrentSession() {
        currentSession?.leave()
        clearCurrentSession()
    }

    func detachPlayer(_ player: AVPlayer) {
        guard coordinatedPlayer === player else { return }
        leaveCurrentSession()
    }

    private func join(
        _ session: GroupSession<GusPlaybackActivity>,
        appModel: AppModel,
        navigation: AppNavigationModel
    ) {
        if currentSession !== session {
            currentSession?.leave()
        }
        currentSession = session
        coordinatedPlayer = nil
        coordinatedItemID = nil
        isSharing = true

        let activity = session.activity
        guard activity.request.item.id == activity.itemID, Self.canShare(activity.request.item) else {
            session.leave()
            clearCurrentSession()
            return
        }
        if let activeServerID = appModel.currentSession?.server.id,
           activeServerID != activity.serverID
        {
            errorMessage = String(localized: "This SharePlay session is for a different server.", comment: "SharePlay error when the current server does not match the activity")
            logger.info("Ignoring SharePlay session for a different server")
            session.leave()
            clearCurrentSession()
            return
        }

        appModel.currentSession?.onInvalidation(of: self) { owner in owner.leaveCurrentSession() }
        session.join()
        navigation.open(.play(id: activity.itemID, serverID: activity.serverID, provider: activity.request.item.providerKind, request: activity.request))
    }

    private func clearCurrentSession() {
        currentSession = nil
        coordinatedPlayer = nil
        coordinatedItemID = nil
        isSharing = false
    }
}
