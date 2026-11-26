import AppIntents
import CryptoKit
import Foundation

struct GusRecordingTimerEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Scheduled Recording"
    static let defaultQuery = GusTimerQuery()
    var id: String
    @Property(title: "Program") var name: String
    @Property(title: "Channel") var channel: String?
    @Property(title: "Start Time") var start: Date?
    var displayRepresentation: DisplayRepresentation {
        let detail = [channel, start?.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · ")
        return .init(title: "\(name)", subtitle: "\(detail)")
    }

    init(id: String, timer: LiveTVTimer) {
        self.id = id
        name = timer.name
        channel = timer.channelName
        start = timer.startDate
    }
}

struct GusTimerQuery: EntityStringQuery {
    func suggestedEntities() async throws -> [GusRecordingTimerEntity] {
        []
    }

    @MainActor func entities(for identifiers: [String]) async throws -> [GusRecordingTimerEntity] {
        let all = try await timers(in: GusIntentRuntime.session())
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    @MainActor func entities(matching string: String) async throws -> [GusRecordingTimerEntity] {
        try await timers(in: GusIntentRuntime.session()).filter { $0.name.localizedStandardContains(string) }
    }

    @MainActor fileprivate func timers(in session: SessionStore) async throws -> [GusRecordingTimerEntity] {
        guard ContentRatingGate.admitsStored(MediaItem(type: .liveProgram)), try await session.mediaProvider.liveTVAvailability() == .enabled else { return [] }
        let result = try await session.mediaProvider.liveTVTimers()
        try GusIntentRuntime.validate(session)
        guard ContentRatingGate.admitsStored(MediaItem(type: .liveProgram)) else { return [] }
        return result.map { timer in
            let id = GusIntentID.make(resource: "timer", id: timer.id, provider: session.server.providerKind, scope: session.references.scope)
            return GusRecordingTimerEntity(id: id, timer: timer)
        }
    }
}

struct GetGusRecordingTimersIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Scheduled Recordings"
    static let description = IntentDescription("Returns visible scheduled Live TV recordings from the active server.", categoryName: "Live TV")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[GusRecordingTimerEntity]> {
        try .result(value: await GusTimerQuery().timers(in: GusIntentRuntime.session()))
    }
}

struct CancelGusRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Cancel Scheduled Recording"
    static let description = IntentDescription("Confirms before canceling an existing recording on the household DVR.", categoryName: "Live TV")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Recording") var recording: GusRecordingTimerEntity

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<GusActionStatus> {
        let session = try await GusIntentRuntime.session()
        guard let id = GusIntentID.value(recording.id, resource: "timer", provider: session.server.providerKind, scope: session.references.scope) else { throw GusError.notFound }
        let query = GusTimerQuery()
        guard let selected = try await query.timers(in: session).first(where: { $0.id == recording.id }) else { throw GusError.notFound }
        let time = selected.start?.formatted(date: .abbreviated, time: .shortened) ?? ""
        try await requestConfirmation(dialog: "Cancel the recording of \(selected.name) \(time)?")
        let status = try await GusAutomationWrite.perform(key: recording.id) {
            guard let fresh = try await query.timers(in: session).first(where: { $0.id == recording.id }),
                  fresh.name == selected.name, fresh.channel == selected.channel, fresh.start == selected.start else { throw GusError.notFound }
            guard let guide = session.mediaProvider as? any LiveTVGuideProviding, try await guide.canManageRecordings() else { throw GusError.forbidden }
            try GusIntentRuntime.validate(session)
            guard ContentRatingGate.admitsStored(MediaItem(type: .liveProgram)) else { throw GusError.forbidden }
            let store = LiveTVStore(session: session)
            await store.cancelTimer(id: id)
            try GusIntentRuntime.validate(session)
            return try GusActionStatus(store.cancellationOutcomes[id], failure: store.actionErrorMessage)
        }
        return .result(value: status)
    }
}

struct GusGuideProgramEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Live TV Program"
    static let defaultQuery = GusGuideQuery()
    var id: String
    @Property(title: "Program") var name: String
    @Property(title: "Channel") var channel: String?
    @Property(title: "Start Time") var start: Date
    @Property(title: "End Time") var end: Date
    var displayRepresentation: DisplayRepresentation {
        let detail = [channel, start.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · ")
        return .init(title: "\(name)", subtitle: "\(detail)")
    }

    @MainActor init(program: LiveTVGuideProgram, session: SessionStore) {
        id = GusIntentID.make(resource: "epg", id: program.id, provider: session.server.providerKind, scope: session.references.scope)
        name = program.name
        channel = program.channelName
        start = program.start
        end = program.end
    }
}

struct GusGuideQuery: EntityStringQuery {
    func suggestedEntities() async throws -> [GusGuideProgramEntity] {
        []
    }

    @MainActor func entities(for identifiers: [String]) async throws -> [GusGuideProgramEntity] {
        guard !identifiers.isEmpty else { return [] }
        let session = try await GusIntentRuntime.session()
        let guide = try await guide(in: session)
        var models = [LiveTVGuideProgram]()
        for identifier in identifiers {
            do {
                try models.append(await resolve(identifier, in: session, guide: guide))
            } catch where GusError(from: error) == .notFound { continue }
        }
        try GusIntentRuntime.validate(session)
        return models.filter(\.admitted).map { GusGuideProgramEntity(program: $0, session: session) }
    }

    @MainActor func entities(matching string: String) async throws -> [GusGuideProgramEntity] {
        try await find(title: string, channel: nil, from: .now)
    }

    @MainActor fileprivate func guide(in session: SessionStore) async throws -> any LiveTVGuideProviding {
        guard let guide = session.mediaProvider as? any LiveTVGuideProviding,
              try await session.mediaProvider.liveTVAvailability() == .enabled else { throw GusError.forbidden }
        try GusIntentRuntime.validate(session)
        return guide
    }

    @MainActor fileprivate func resolve(_ identifier: String, in session: SessionStore, guide: any LiveTVGuideProviding) async throws -> LiveTVGuideProgram {
        guard let raw = GusIntentID.value(identifier, resource: "epg", provider: session.server.providerKind, scope: session.references.scope) else { throw GusError.notFound }
        let program = try await guide.liveTVProgram(id: raw)
        try GusIntentRuntime.validate(session)
        guard program.id == raw, program.end > .now, program.admitted else { throw GusError.notFound }
        return program
    }

    @MainActor fileprivate func find(title: String?, channel: GusMediaEntity?, from: Date) async throws -> [GusGuideProgramEntity] {
        let session = try await GusIntentRuntime.session()
        let guide = try await guide(in: session)
        var channelID: String?
        if let channel {
            let current = try await GusIntentRuntime.resolve(channel, in: session)
            guard current.type == .liveChannel, let id = current.id else { throw GusError.notFound }
            channelID = id
        }
        let from = max(from, .now)
        let until = from.addingTimeInterval(24 * 60 * 60)
        var programs = [LiveTVGuideProgram]()
        var seen = Set<String>()
        var lastPage: [String]?
        var offset = 0
        let term = title?.trimmedNilIfEmpty
        while programs.count < 50 {
            let page = try await guide.liveTVPrograms(from: from, until: until, channelID: channelID, offset: offset, limit: 200)
            try GusIntentRuntime.validate(session)
            if page.rawCount == 0 {
                guard page.total.map({ offset >= $0 }) ?? true else { throw GusError.server(String(localized: "The server returned an incomplete program guide.")) }
                break
            }
            let ids = page.programs.map(\.id)
            guard lastPage != ids || (ids.isEmpty && page.total != nil) else { throw GusError.server(String(localized: "The server did not advance to the next page. Try again.")) }
            lastPage = ids
            for program in page.programs where program.end > from && program.start <= until && program.admitted &&
                (channelID == nil || channelID == program.channelID) && (term.map(program.name.localizedStandardContains) ?? true)
            {
                if seen.insert(program.id).inserted {
                    programs.append(program)
                }
            }
            offset += page.rawCount
            if page.total.map({ offset >= $0 }) ?? (page.rawCount < 200) {
                break
            }
        }
        return programs.filter(\.admitted).prefix(50).map { GusGuideProgramEntity(program: $0, session: session) }
    }
}

struct FindGusGuideProgramsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Live TV Programs"
    static let description = IntentDescription("Searches a 24-hour guide window and returns up to 50 matching airings in time order.", categoryName: "Live TV")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Program Title") var query: String?
    @Parameter(title: "Channel") var channel: GusMediaEntity?
    @Parameter(title: "Starting At") var start: Date?

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[GusGuideProgramEntity]> {
        try .result(value: await GusGuideQuery().find(title: query, channel: channel, from: start ?? .now))
    }
}

/// Persist the transmission boundary before POST. A lost response or terminated
/// app turns the next invocation into a readback, never an unattended repeat.
struct GusRecordingJournal {
    let file: URL

    init(scope: AccountScope, directory: URL = AppStorageLocation.appDirectory().appendingPathComponent("RecordingAttempts", isDirectory: true)) {
        let bytes = Data("\(scope.serverID.utf8.count)/\(scope.serverID)\(scope.userID)".utf8)
        let key = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        file = directory.appendingPathComponent(key + ".json")
    }

    private func attempts(now: Date) throws -> [String: Date] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        return try JSONDecoder().decode([String: Date].self, from: Data(contentsOf: file)).filter { $0.value > now }
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    func contains(_ id: String, now: Date = .now) throws -> Bool {
        try attempts(now: now)[id] != nil
    }

    func set(_ id: String, expires: Date?, now: Date = .now) throws {
        var current = try attempts(now: now)
        current[id] = expires
        if current.isEmpty {
            try clear()
            return
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(current).write(to: file, options: .atomic)
    }
}

struct ScheduleGusRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Schedule Live TV Recording"
    static let description = IntentDescription("Reviews one guide airing and schedules it on the household DVR.", categoryName: "Live TV")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Program") var program: GusGuideProgramEntity

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<GusActionStatus> {
        let session = try await GusIntentRuntime.session()
        let query = GusGuideQuery()
        let guide = try await query.guide(in: session)
        let selected = try await query.resolve(program.id, in: session, guide: guide)
        guard try await guide.canManageRecordings() else { throw GusError.forbidden }
        try GusIntentRuntime.validate(session)
        guard selected.admitted else { throw GusError.forbidden }
        let scheduler = LiveTVRecordingScheduler(session: session, guide: guide) {
            try GusIntentRuntime.validate(session)
        }
        let outcome = try await scheduler.schedule(selected) { retry in
            let channel = selected.channelName ?? String(localized: "Unknown Channel")
            let time = selected.start.formatted(date: .abbreviated, time: .shortened)
            if retry {
                try await requestConfirmation(dialog: "The previous request for \(selected.name) on \(channel) at \(time) is unconfirmed. The DVR currently lists no timer. Send another request?")
            } else {
                try await requestConfirmation(dialog: "Record \(selected.name) on \(channel) at \(time)?")
            }
        }
        return try .result(value: GusActionStatus(outcome))
    }
}
