import Foundation
import JellyfinAPI
import Observation

enum PlaybackTime {
    static let ticksPerSecond = 10_000_000

    static func ticks(fromSeconds seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int((seconds * Double(ticksPerSecond)).rounded())
    }

    static func seconds(fromTicks ticks: Int) -> Double {
        guard ticks > 0 else { return 0 }
        return Double(ticks) / Double(ticksPerSecond)
    }

    static func resumePositionTicks(for item: BaseItemDto) -> Int? {
        guard let ticks = item.userData?.playbackPositionTicks, ticks > 0 else { return nil }
        return ticks
    }
}

struct PlaybackReportContext {
    let itemID: String
    let mediaSourceID: String?
    let playSessionID: String?
    let playMethod: PlayMethod

    func stateInfo(positionTicks: Int, isPaused: Bool) -> PlaybackStateInfo {
        PlaybackStateInfo(
            canSeek: true,
            isMuted: false,
            isPaused: isPaused,
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playMethod: playMethod,
            playSessionID: playSessionID,
            positionTicks: positionTicks
        )
    }

    func stopInfo(positionTicks: Int) -> PlaybackStopInfo {
        PlaybackStopInfo(
            isFailed: false,
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playSessionID: playSessionID,
            positionTicks: positionTicks
        )
    }
}

@MainActor
@Observable
final class PlaybackRefreshStore {
    private(set) var revision = 0

    func markPlaybackProgressChanged() {
        revision += 1
    }
}
