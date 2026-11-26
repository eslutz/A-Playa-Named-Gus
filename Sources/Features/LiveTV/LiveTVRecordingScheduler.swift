import Foundation

/// Both the Guide and Shortcuts use the same DVR write and readback rules.
@MainActor
struct LiveTVRecordingScheduler {
    enum Review {
        case ready, unconfirmed, scheduled
    }

    let session: SessionStore
    let guide: any LiveTVGuideProviding
    let validate: @MainActor () throws -> Void

    private var journal: GusRecordingJournal {
        GusRecordingJournal(scope: session.references.scope)
    }

    func review(_ selected: LiveTVGuideProgram) async throws -> Review {
        let current = try await revalidate(selected)
        if try await isScheduled(current) {
            try clearAttempt(current)
            return .scheduled
        }
        return try journal.contains(current.id) ? .unconfirmed : .ready
    }

    func schedule(_ selected: LiveTVGuideProgram, confirm: @MainActor (Bool) async throws -> Void) async throws -> ActionOutcome {
        let key = GusIntentID.make(
            resource: "epg", id: Self.normalizedID(selected.id), provider: session.server.providerKind, scope: session.references.scope
        )
        return try await GusAutomationWrite.perform(key: key) {
            switch try await review(selected) {
            case .scheduled: return .confirmed
            case .ready: try await confirm(false)
            case .unconfirmed: try await confirm(true)
            }
            let current = try await revalidate(selected)
            if try await isScheduled(current) {
                try clearAttempt(current)
                return .confirmed
            }

            var transmitted = false
            var acknowledged = false
            do {
                try await guide.scheduleLiveTVProgram(current) {
                    try validate()
                    guard current.admitted, current.end > .now else { throw GusError.notFound }
                    try journal.set(current.id, expires: current.end)
                    transmitted = true
                }
                acknowledged = true
            } catch {
                let failure = GusError(from: error)
                guard transmitted else { throw failure }
                if [.forbidden, .unauthorized, .notFound].contains(failure) {
                    try clearAttempt(current)
                    throw failure
                }
            }

            try validate()
            if (try? await isScheduled(current)) == true {
                try clearAttempt(current)
                return .confirmed
            }
            try validate()
            return acknowledged ? .accepted : .uncertain
        }
    }

    static func hasMatchingTimer(for program: LiveTVGuideProgram, in timers: [LiveTVTimer]) -> Bool {
        matchingTimers(for: program, in: timers).contains { $0.activeRecording == true }
    }

    private func revalidate(_ selected: LiveTVGuideProgram) async throws -> LiveTVGuideProgram {
        try validate()
        guard selected.admitted, selected.end > .now else { throw GusError.notFound }
        guard try await guide.canManageRecordings() else { throw GusError.forbidden }
        let current = try await guide.liveTVProgram(id: selected.id)
        try validate()
        guard current.admitted, current.end > .now else { throw GusError.notFound }
        guard selected.isSameAiring(as: current) else {
            throw GusError.server(String(localized: "The airing changed. Choose the program again."))
        }
        return current
    }

    private func isScheduled(_ program: LiveTVGuideProgram) async throws -> Bool {
        let timers = try await session.mediaProvider.liveTVTimers()
        try validate()
        guard program.admitted else { throw GusError.forbidden }
        let matches = Self.matchingTimers(for: program, in: timers)
        if matches.contains(where: { $0.activeRecording == true }) {
            return true
        }
        guard program.timerID == nil, matches.allSatisfy({ $0.activeRecording == false }) else {
            throw GusError.server(String(localized: "The DVR reports an existing recording for this airing. Review the schedule before trying again."))
        }
        return false
    }

    private func clearAttempt(_ program: LiveTVGuideProgram) throws {
        if try journal.contains(program.id) {
            try journal.set(program.id, expires: nil)
        }
    }

    private static func matchingTimers(for program: LiveTVGuideProgram, in timers: [LiveTVTimer]) -> [LiveTVTimer] {
        timers.filter { timer in
            timer.id == program.timerID || timer.programID.map(normalizedID) == normalizedID(program.id)
        }
    }

    private static func normalizedID(_ id: String) -> String {
        ServerMediaListID.uuid(id)?.uuidString ?? id
    }
}
