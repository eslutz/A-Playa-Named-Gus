import Foundation
import Observation

struct PlaybackStreamSelection: Hashable, Codable, Sendable {
    static let none = PlaybackStreamSelection(audioStreamIndex: nil, subtitleStreamIndex: nil)

    var audioStreamIndex: Int?
    var subtitleStreamIndex: Int?
    var mediaSourceID: String? = nil
}

/// Menu checkmarks describe requested intent, independently of AVKit's effective
/// default track. An unavailable explicit choice checks no unrelated menu entry.
enum PlaybackTrackMenuSelection: Hashable {
    case automatic
    case off
    case stream(Int)

    @MainActor
    static func audio(for request: PlaybackRequest, source: MediaSource?) -> PlaybackTrackMenuSelection? {
        if request.audioTrack == nil, request.streamSelection.audioStreamIndex == nil {
            return .automatic
        }
        guard request.audioTrack == nil || source != nil,
              let index = source.map({ request.selection(in: $0).audioStreamIndex }) ?? request.streamSelection.audioStreamIndex,
              index >= 0 else { return nil }
        if let source, !source.mediaStreams.contains(where: { $0.type == .audio && $0.index == index }) {
            return nil
        }
        return .stream(index)
    }

    @MainActor
    static func subtitle(for request: PlaybackRequest, source: MediaSource?) -> PlaybackTrackMenuSelection? {
        switch request.subtitleIntent {
        case .automatic: return .automatic
        case .off: return .off
        case .explicit:
            guard request.subtitleTrack == nil || source != nil,
                  let index = source.map({ request.selection(in: $0).subtitleStreamIndex }) ?? request.streamSelection.subtitleStreamIndex,
                  index >= 0 else { return nil }
            if let source, !source.mediaStreams.contains(where: { $0.type == .subtitle && $0.index == index }) {
                return nil
            }
            return .stream(index)
        }
    }
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

    private static func fallbackTitle(kind: MediaStreamKind, index: Int) -> String {
        switch kind {
        case .audio: String(localized: "Audio \(index.formatted())")
        case .subtitle: String(localized: "Subtitle \(index.formatted())")
        default: String(localized: "Track \(index.formatted())")
        }
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
                    title: stream.displayTitle ?? stream.title ?? stream.language ?? fallbackTitle(kind: type, index: index),
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

    static func accessibilityDuration(seconds: Double) -> String {
        let roundedSeconds = max(0, Int(seconds.rounded()))
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = roundedSeconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(roundedSeconds)) ?? String(localized: "0 seconds", comment: "Zero duration fallback")
    }

    static func accessibilityProgressValue(currentSeconds: Double, durationSeconds: Double) -> String {
        let current = accessibilityDuration(seconds: currentSeconds)
        let duration = accessibilityDuration(seconds: durationSeconds)
        return String(localized: "\(current) of \(duration)", comment: "Accessibility value for elapsed media playback time")
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

/// One queue belongs to one immutable credential session and is shared by audio/video.
/// Only pending progress may be replaced; start/stop boundaries remain ordered.
@MainActor
final class PlaybackReportQueue {
    enum Kind: Int { case start, progress, stop }
    private struct Job {
        let kind: Kind
        let sessionID: UUID
        let operation: @MainActor () async throws -> Void
        let onFailure: @MainActor (Error) -> Void
        let completion: @MainActor (_ reportSucceeded: Bool) async -> Void
    }

    private let timeout: Duration
    private var jobs: [Job] = []
    private var openSessions: Set<UUID> = []
    var hasActivePlayback: Bool {
        !openSessions.isEmpty
    }

    private var worker: Task<Void, Never>?
    private(set) var succeededCount = 0
    private(set) var failedCount = 0
    private(set) var timedOutCount = 0

    init(timeout: Duration = .seconds(5)) {
        self.timeout = timeout
    }

    func enqueue(_ kind: Kind, sessionID: UUID, onFailure: @escaping @MainActor (Error) -> Void = { _ in }, completion: @escaping @MainActor (_ reportSucceeded: Bool) async -> Void = { _ in }, operation: @escaping @MainActor () async throws -> Void) {
        switch kind {
        case .start:
            guard openSessions.insert(sessionID).inserted else { return }
        case .progress:
            guard openSessions.contains(sessionID) else { return }
            jobs.removeAll { $0.sessionID == sessionID && $0.kind == .progress }
        case .stop:
            guard openSessions.remove(sessionID) != nil else { return }
            jobs.removeAll { $0.sessionID == sessionID && $0.kind == .progress }
        }
        jobs.append(Job(kind: kind, sessionID: sessionID, operation: operation, onFailure: onFailure, completion: completion))
        guard worker == nil else { return }
        worker = Task { [self] in
            while !jobs.isEmpty {
                let job = jobs.removeFirst()
                var outcome = 0
                do {
                    try await PlaybackDeadline.run(for: timeout, operation: job.operation)
                    succeededCount += 1
                } catch {
                    if error is PlaybackDeadline.Timeout {
                        timedOutCount += 1; outcome = 2
                    } else {
                        failedCount += 1; outcome = 1
                    }
                    job.onFailure(error)
                }
                await job.completion(outcome == 0)
                DiagnosticsHub.shared.record(.playbackReportResult(kind: job.kind.rawValue, outcome: outcome))
            }
            worker = nil
        }
    }

    func flush() async {
        await worker?.value
    }
}
