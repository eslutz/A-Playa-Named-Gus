import Foundation

struct LiveTVGuideWindow: Equatable {
    let day: Date
    let start: Date
    let end: Date

    static func days(from now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    init(day: Date, now: Date, calendar: Calendar) {
        let interval = calendar.dateInterval(of: .day, for: day) ?? .init(start: day, duration: 86400)
        self.day = interval.start
        end = interval.end
        if interval.contains(now) {
            let elapsed = now.timeIntervalSince(interval.start)
            start = interval.start.addingTimeInterval((elapsed / 1800).rounded(.down) * 1800)
        } else {
            start = interval.start
        }
    }

    func overlaps(_ program: LiveTVGuideProgram) -> Bool {
        program.end > start && program.start < end
    }
}

@MainActor
@Observable
final class LiveTVGuideStore {
    private(set) var window: LiveTVGuideWindow?
    private(set) var state: LoadState = .idle
    private(set) var programs: [LiveTVGuideProgram] = []
    private(set) var canRecord = false
    private(set) var recordingOutcomes: [String: ActionOutcome] = [:]
    private var generation = 0

    func load(_ window: LiveTVGuideWindow, session: SessionStore) async {
        generation += 1
        let request = generation
        if self.window != window {
            programs = []
        }
        self.window = window
        state = .loading
        guard let provider = session.mediaProvider as? any LiveTVGuideProviding else {
            state = .loaded
            return
        }
        do {
            let collected = try await Self.collect(window) { offset, limit in
                try await provider.liveTVPrograms(from: window.start, until: window.end, channelID: nil, offset: offset, limit: limit)
            }
            try Self.validate(session)
            guard generation == request else { return }
            programs = collected
            state = .loaded
        } catch {
            guard generation == request, session.isActive else { return }
            let failure = GusError(from: error)
            state = failure.isCancellation ? (programs.isEmpty ? .idle : .loaded) : .failed(failure.localizedDescription)
            failure.handleIfUnauthorized(session: session)
        }
    }

    func loadRecordingPermission(session: SessionStore) async {
        guard let provider = session.mediaProvider as? any LiveTVGuideProviding else { return }
        do {
            let permitted = try await provider.canManageRecordings()
            try Self.validate(session)
            canRecord = permitted
        } catch {
            let failure = GusError(from: error)
            if !failure.isCancellation {
                canRecord = false
                failure.handleIfUnauthorized(session: session)
            }
        }
    }

    func review(_ program: LiveTVGuideProgram, session: SessionStore) async throws -> LiveTVRecordingScheduler.Review {
        let scheduler = try scheduler(session)
        return try await scheduler.review(program)
    }

    func record(_ program: LiveTVGuideProgram, retry: Bool, session: SessionStore) async throws {
        guard recordingOutcomes[program.id] != .pending else { return }
        let scheduler = try scheduler(session)
        let previous = recordingOutcomes[program.id]
        recordingOutcomes[program.id] = .pending
        do {
            let outcome = try await scheduler.schedule(program) { requiresRetry in
                if requiresRetry, !retry {
                    throw GusError.server(String(localized: "The previous recording request is unconfirmed. Review it before trying again."))
                }
            }
            try Self.validate(session)
            recordingOutcomes[program.id] = outcome
        } catch {
            recordingOutcomes[program.id] = previous
            throw error
        }
    }

    func reconcile(timers: [LiveTVTimer]) {
        for program in programs {
            let confirmed = LiveTVRecordingScheduler.hasMatchingTimer(for: program, in: timers)
            switch recordingOutcomes[program.id] {
            case .confirmed where !confirmed: recordingOutcomes[program.id] = nil
            case .accepted where confirmed, .uncertain where confirmed: recordingOutcomes[program.id] = .confirmed
            default: break
            }
        }
    }

    private func scheduler(_ session: SessionStore) throws -> LiveTVRecordingScheduler {
        guard canRecord, let provider = session.mediaProvider as? any LiveTVGuideProviding else { throw GusError.forbidden }
        return LiveTVRecordingScheduler(session: session, guide: provider) { try Self.validate(session) }
    }

    private static func validate(_ session: SessionStore) throws {
        try Task.checkCancellation()
        guard session.isActive else { throw GusError.cancelled }
        guard !ContentRatingGate.storedPolicy().awaitingRequiredRange else { throw GusError.forbidden }
    }

    static func collect(_ window: LiveTVGuideWindow, page: (Int, Int) async throws -> LiveTVGuidePage) async throws -> [LiveTVGuideProgram] {
        let limit = 200
        var offset = 0
        var total: Int?
        var seenPages = Set<[String]>()
        var seen = Set<String>()
        var programs: [LiveTVGuideProgram] = []
        while true {
            try Task.checkCancellation()
            let result = try await page(offset, limit)
            try Task.checkCancellation()
            total = result.total ?? total
            if result.rawCount == 0 {
                guard total.map({ offset >= $0 }) ?? true else {
                    throw GusError.server(String(localized: "The server returned an incomplete program guide."))
                }
                return programs
            }
            let ids = (result.rawIDs ?? result.programs.map { Optional($0.id) }).compactMap { $0 }
            if !ids.isEmpty, !seenPages.insert(ids).inserted {
                throw GusError.server(String(localized: "The server did not advance to the next page. Try again."))
            }
            programs += result.programs.filter { window.overlaps($0) && seen.insert($0.id).inserted }
            offset += result.rawCount
            if total.map({ offset >= $0 }) ?? (result.rawCount < limit) {
                return programs
            }
            if ids.isEmpty, total == nil {
                throw GusError.server(String(localized: "The server returned an incomplete program guide."))
            }
        }
    }
}
