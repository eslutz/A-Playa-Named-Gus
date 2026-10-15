import Foundation
import Observation

/// A stable native window target; playback commands remain transient.
struct PlayerWindowRef: Hashable, Codable {
    let fallback: ItemRef

    init(_ request: ItemRef) {
        var restored = request
        restored.playbackStart = .automatic
        restored.playlistEntryID = nil
        restored.playlistFromBeginning = nil
        fallback = restored
    }

    private var target: String {
        fallback.playlistID.map { "playlist-\($0)" } ?? fallback.id
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.target == rhs.target && lhs.fallback.serverID == rhs.fallback.serverID
            && lhs.fallback.userID == rhs.fallback.userID
            && (lhs.fallback.localOnly == true) == (rhs.fallback.localOnly == true)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(target)
        hasher.combine(fallback.serverID)
        hasher.combine(fallback.userID)
        hasher.combine(fallback.localOnly == true)
    }
}

struct PlayerWindowRequest {
    let id = UUID()
    let ref: ItemRef
}

/// Repeated restart commands replace the player inside its existing native window.
@MainActor @Observable final class PlayerWindowRequests {
    private(set) var requests: [PlayerWindowRef: PlayerWindowRequest] = [:]
    @ObservationIgnored private var active: Set<PlayerWindowRef> = []

    func request(_ ref: ItemRef) -> PlayerWindowRef {
        let window = PlayerWindowRef(ref)
        let restart = ref.playbackStart == .fromBeginning || ref.playlistFromBeginning == true
        if !active.contains(window) || restart {
            requests[window] = PlayerWindowRequest(ref: ref)
        }
        return window
    }

    func activate(_ window: PlayerWindowRef) {
        active.insert(window)
    }

    func deactivate(_ window: PlayerWindowRef) {
        active.remove(window)
        requests[window] = nil
    }
}
