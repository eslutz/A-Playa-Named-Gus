import Foundation
import JellyfinAPI
import Observation

struct PlaybackStreamSelection: Equatable {
    static let none = PlaybackStreamSelection(audioStreamIndex: nil, subtitleStreamIndex: nil)

    var audioStreamIndex: Int?
    var subtitleStreamIndex: Int?
}

struct PlaybackStreamOption: Identifiable, Equatable {
    let id: Int
    let title: String
    let isDefault: Bool
}

enum PlaybackStreamCatalog {
    static func audioOptions(for item: BaseItemDto) -> [PlaybackStreamOption] {
        streamOptions(for: item, type: .audio)
    }

    static func subtitleOptions(for item: BaseItemDto) -> [PlaybackStreamOption] {
        streamOptions(for: item, type: .subtitle)
    }

    private static func streamOptions(for item: BaseItemDto, type: MediaStreamType) -> [PlaybackStreamOption] {
        (item.mediaStreams ?? [])
            .filter { $0.type == type }
            .compactMap { stream in
                guard let index = stream.index else { return nil }
                return PlaybackStreamOption(
                    id: index,
                    title: stream.displayTitle ?? stream.title ?? stream.language ?? "\(type.rawValue) \(index)",
                    isDefault: stream.isDefault == true
                )
            }
    }
}

struct PlaybackChapter: Identifiable, Equatable {
    let id: Int
    let title: String
    let startPositionTicks: Int

    var seconds: Double {
        PlaybackTime.seconds(fromTicks: startPositionTicks)
    }

    static func seekTargets(for item: BaseItemDto) -> [PlaybackChapter] {
        (item.chapters ?? [])
            .compactMap { chapter -> (ChapterInfo, Int)? in
                guard let ticks = chapter.startPositionTicks else { return nil }
                return (chapter, ticks)
            }
            .sorted { $0.1 < $1.1 }
            .enumerated()
            .map { offset, value in
                PlaybackChapter(
                    id: offset,
                    title: value.0.name?.isEmpty == false ? value.0.name! : String(localized: "Chapter \(offset + 1)", comment: "Fallback chapter title"),
                    startPositionTicks: value.1
                )
            }
    }
}

func resolvePlaybackURL(local: URL?, remote: URL) -> URL {
    local ?? remote
}

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
    let streamSelection: PlaybackStreamSelection

    func stateInfo(positionTicks: Int, isPaused: Bool) -> PlaybackStateInfo {
        PlaybackStateInfo(
            audioStreamIndex: streamSelection.audioStreamIndex,
            canSeek: true,
            isMuted: false,
            isPaused: isPaused,
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playMethod: playMethod,
            playSessionID: playSessionID,
            positionTicks: positionTicks,
            subtitleStreamIndex: streamSelection.subtitleStreamIndex
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
