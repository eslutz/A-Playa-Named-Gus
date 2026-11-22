import AppIntents
import Foundation

/// Handoff/user-activity vocabulary: viewing an item's detail and playing an item.
/// Declared in `Info.plist` (`NSUserActivityTypes`); published by the detail and player
/// surfaces and continued by mapping back onto a `ContentLink`.
enum GusUserActivity {
    static let itemDetail = "dev.ericslutz.gus.item-detail"
    static let playback = "dev.ericslutz.gus.playback"

    private static let itemIDKey = "itemID"
    private static let serverIDKey = "serverID"
    private static let userIDKey = "userID"
    private static let playbackIntentKey = "playbackIntent"

    /// Handoff preserves sanitized source, track, and resume intent. File locations,
    /// artwork, stream URLs and credentials never leave the signed-in device.
    static func configure(
        _ activity: NSUserActivity,
        item: MediaItem,
        serverID: String,
        userID: String,
        includeOnscreenContext: Bool = false,
        playbackRequest: PlaybackRequest? = nil
    ) {
        guard let id = item.id, !id.isEmpty, !serverID.isEmpty, !userID.isEmpty, ContentRatingGate.admitsStored(item) else {
            activity.appEntityIdentifier = nil
            activity.title = nil
            activity.isEligibleForHandoff = false
            activity.userInfo = nil
            activity.requiredUserInfoKeys = nil
            activity.resignCurrent()
            return
        }
        activity.appEntityIdentifier = nil
        if includeOnscreenContext {
            let identifier = GusIntentID.make(resource: "media", id: id, provider: item.providerKind, scope: AccountScope(serverID: serverID, userID: userID))
            activity.appEntityIdentifier = EntityIdentifier(for: GusMediaEntity.self, identifier: identifier)
        }
        activity.title = item.displayTitle
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        var userInfo: [String: Any] = [itemIDKey: id, serverIDKey: serverID, userIDKey: userID]
        if let playbackRequest, let data = try? JSONEncoder().encode(playbackRequest.sharingIntent) {
            userInfo[playbackIntentKey] = data
        }
        activity.userInfo = userInfo
        activity.requiredUserInfoKeys = Set(userInfo.keys)
    }

    static func account(from activity: NSUserActivity) -> SessionCredential? {
        guard let serverID = activity.userInfo?[serverIDKey] as? String, !serverID.isEmpty,
              let userID = activity.userInfo?[userIDKey] as? String, !userID.isEmpty else { return nil }
        return SessionCredential(serverID: serverID, userID: userID)
    }

    /// Maps a continued activity back onto a content link, refusing payloads from a
    /// different server/user than the active session (when one exists) so an item id
    /// never resolves against the wrong account.
    static func contentLink(
        from activity: NSUserActivity,
        currentServerID: String?,
        currentUserID: String?
    ) -> ContentLink? {
        guard let userInfo = activity.userInfo, let account = account(from: activity),
              let itemID = userInfo[itemIDKey] as? String, !itemID.isEmpty,
              currentServerID == nil || currentServerID == account.serverID,
              currentUserID == nil || currentUserID == account.userID else { return nil }
        switch activity.activityType {
        case playback:
            var request: PlaybackRequest?
            if let payload = userInfo[playbackIntentKey] {
                guard let data = payload as? Data, let decoded = PlaybackRequest.decodeSharingIntent(data),
                      decoded.item.id == itemID, decoded.item.providerKind == .jellyfin else { return nil }
                request = decoded
            }
            return .play(id: itemID, serverID: account.serverID, provider: .jellyfin, request: request)
        case itemDetail:
            guard userInfo[playbackIntentKey] == nil else { return nil }
            return .item(id: itemID, serverID: account.serverID, provider: .jellyfin)
        default:
            return nil
        }
    }
}
