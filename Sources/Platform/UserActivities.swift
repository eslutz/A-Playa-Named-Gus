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

    /// Fills an activity for Handoff. The payload carries only ids — never tokens or
    /// titles beyond the visible activity title. Resume position is intentionally not
    /// carried: playback progress reports to the server every few seconds, so the
    /// continuing device resumes from server-side position.
    static func configure(
        _ activity: NSUserActivity,
        item: MediaItem,
        serverID: String,
        userID: String
    ) {
        guard ContentRatingGate.admitsStored(item) else {
            activity.resignCurrent()
            return
        }
        activity.title = item.displayTitle
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        activity.requiredUserInfoKeys = [itemIDKey]
        var userInfo: [String: Any] = [serverIDKey: serverID, userIDKey: userID]
        if let id = item.id {
            userInfo[itemIDKey] = id
        }
        activity.addUserInfoEntries(from: userInfo)
    }

    /// Maps a continued activity back onto a content link, refusing payloads from a
    /// different server/user than the active session (when one exists) so an item id
    /// never resolves against the wrong account.
    static func contentLink(
        from activity: NSUserActivity,
        currentServerID: String?,
        currentUserID: String?
    ) -> ContentLink? {
        guard let userInfo = activity.userInfo,
              let itemID = userInfo[itemIDKey] as? String
        else { return nil }

        if let currentServerID, let currentUserID,
           let serverID = userInfo[serverIDKey] as? String,
           let userID = userInfo[userIDKey] as? String,
           serverID != currentServerID || userID != currentUserID
        {
            return nil
        }

        switch activity.activityType {
        case playback:
            return .play(id: itemID)
        case itemDetail:
            return .item(id: itemID)
        default:
            return nil
        }
    }
}
