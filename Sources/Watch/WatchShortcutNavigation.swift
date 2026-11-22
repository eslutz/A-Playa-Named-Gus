import AppIntents
import Observation

enum GusWatchPage: Hashable {
    case remote, resume, browse, downloads, settings
}

@MainActor @Observable
final class WatchShortcutNavigation {
    static let shared = WatchShortcutNavigation()
    var page: GusWatchPage = .remote
    private var selection: (recordID: String, lease: SessionLease)?
    private(set) var playRequest = 0

    func open(url: URL) {
        guard url.scheme == "gus", url.path.isEmpty else { return }
        switch url.host {
        case "home": page = .resume
        case "search": page = .browse
        case "downloaded": page = .downloads
        default: return
        }
    }

    func play(_ record: OfflineDownloadRecord, for session: SessionStore) {
        selection = (record.id, session.lease)
        page = .downloads
        playRequest += 1
    }

    func take(in session: SessionStore, downloads: OfflineDownloadStore) -> OfflineDownloadRecord? {
        defer { selection = nil }
        guard let selection, session.isActive, selection.lease == session.lease else { return nil }
        return downloads.completedRecords(serverID: session.server.id, userID: session.user.id).first {
            $0.id == selection.recordID && $0.item.isAudioPlayable && $0.isAdmitted(by: { ContentRatingGate.admitsStored($0) })
        }
    }
}

struct WatchAudioDownloadEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Downloaded Audio")
    static let defaultQuery = WatchAudioDownloadQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct WatchAudioDownloadQuery: EntityStringQuery {
    @MainActor
    static func library() async throws -> (SessionStore, [OfflineDownloadRecord]) {
        let app = AppModel.shared
        await app.restoreLastSession()
        guard let session = app.currentSession, session.isActive, !app.isTransitioning else { throw GusError.unauthorized }
        let downloads = OfflineDownloadStore.shared
        downloads.load(serverID: session.server.id, userID: session.user.id)
        let records = downloads.completedRecords(serverID: session.server.id, userID: session.user.id).filter {
            $0.item.isAudioPlayable && $0.isAdmitted(by: { ContentRatingGate.admitsStored($0) })
        }
        return (session, records)
    }

    @MainActor
    private func entities() async throws -> [WatchAudioDownloadEntity] {
        let (session, records) = try await Self.library()
        return entities(records, session: session)
    }

    @MainActor
    private func entities(_ records: [OfflineDownloadRecord], session: SessionStore) -> [WatchAudioDownloadEntity] {
        records.map { record in
            WatchAudioDownloadEntity(id: GusIntentID.make(resource: "watch-download", id: record.id, provider: session.server.providerKind, scope: session.references.scope), title: record.item.displayTitle)
        }
    }

    func entities(for identifiers: [String]) async throws -> [WatchAudioDownloadEntity] {
        let available = try await entities()
        return identifiers.compactMap { id in available.first { $0.id == id } }
    }

    func entities(matching string: String) async throws -> [WatchAudioDownloadEntity] {
        try await entities().filter { $0.title.localizedStandardContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [WatchAudioDownloadEntity] {
        let app = AppModel.shared
        guard let current = app.currentSession, current.isActive, !app.isTransitioning,
              current.systemSurfacePreferences.personalHistoryEnabled,
              let (session, records) = try? await Self.library(), session === current,
              current.isActive, app.currentSession === current, !app.isTransitioning,
              current.systemSurfacePreferences.personalHistoryEnabled else { return [] }
        return entities(Array(records.prefix(8)), session: current)
    }
}

struct PlayWatchDownloadIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Downloaded Audio"
    static let supportedModes: IntentModes = .foreground
    @Parameter(title: "Downloaded Audio") var download: WatchAudioDownloadEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let (session, records) = try await WatchAudioDownloadQuery.library()
        guard let id = GusIntentID.value(download.id, resource: "watch-download", provider: session.server.providerKind, scope: session.references.scope),
              let record = records.first(where: { $0.id == id }) else { throw GusError.notFound }
        WatchShortcutNavigation.shared.play(record, for: session)
        return .result()
    }
}

struct GusWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayWatchDownloadIntent(), phrases: ["Play downloaded audio in \(.applicationName)"], shortTitle: "Play Downloaded Audio", systemImageName: "headphones")
    }
}
