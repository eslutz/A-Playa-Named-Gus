import Foundation
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
    static func audioOptions(for item: MediaItem) -> [PlaybackStreamOption] {
        streamOptions(for: item, type: .audio)
    }

    static func subtitleOptions(for item: MediaItem) -> [PlaybackStreamOption] {
        streamOptions(for: item, type: .subtitle)
    }

    /// Options come from the first media source only — playback resolves against the
    /// server's default source, and stream indexes are per-source, so flattening every
    /// source would surface duplicate/mismatched indexes for multi-version items.
    private static func streamOptions(for item: MediaItem, type: MediaStreamKind) -> [PlaybackStreamOption] {
        (item.mediaSources.first?.mediaStreams ?? [])
            .filter { $0.type == type }
            .compactMap { stream in
                guard let index = stream.index else { return nil }
                return PlaybackStreamOption(
                    id: index,
                    title: stream.displayTitle ?? stream.title ?? stream.language ?? "\(type.rawValue.capitalized) \(index)",
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

    static func seekTargets(for item: MediaItem) -> [PlaybackChapter] {
        item.chapters
            .compactMap { chapter -> (MediaChapterInfo, Int)? in
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

    static func resumePositionTicks(for item: MediaItem) -> Int? {
        guard let ticks = item.userData?.playbackPositionTicks, ticks > 0 else { return nil }
        return ticks
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
