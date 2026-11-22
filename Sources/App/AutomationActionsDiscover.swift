import AppIntents
import CryptoKit
import Foundation

struct GusDiscoverTitleEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Discover Title"
    static let defaultQuery = GusDiscoverQuery()
    var id: String
    @Property(title: "Title") var title: String
    @Property(title: "Year") var year: String
    var isSeries: Bool
    var displayRepresentation: DisplayRepresentation {
        isSeries ? .init(title: "\(title)", subtitle: "TV Series · \(year)") : .init(title: "\(title)", subtitle: "Movie · \(year)")
    }

    init(id: String, title: SeerrTitle) {
        self.id = id
        self.isSeries = title.mediaType == .tv
        self.title = title.displayTitle
        self.year = title.releaseYear ?? ""
    }
}

@MainActor private struct GusDiscoverSession {
    let session: SessionStore
    let client: SeerrClient
    let revision: UUID
    let restrictions: String
    let resource: String

    init(session: SessionStore) async throws {
        self.session = session
        let store = session.seerr
        await store.restore()
        try GusIntentRuntime.validate(session)
        self.client = try store.requireClient()
        self.revision = store.revision
        self.restrictions = store.restrictionRevision
        guard let url = store.serverURL, let user = store.user else { throw SeerrConnectionError.signInRequired }
        // A library profile can reconnect to another Seerr account. Bind saved
        // references to both identities without exposing its service URL.
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        self.resource = "discover/\(digest)/\(user.id)"
    }

    func validate() throws {
        try GusIntentRuntime.validate(session)
        guard session.seerr.revision == revision else { throw SeerrConnectionError.signInRequired }
        guard session.seerr.restrictionRevision == restrictions else { throw SeerrConnectionError.eligibilityChanged }
    }

    func entity(_ title: SeerrTitle) -> GusDiscoverTitleEntity? {
        guard [.movie, .tv].contains(title.mediaType), title.id > 0, session.seerr.admits(title) else { return nil }
        let id = GusIntentID.make(resource: resource, id: title.seerrCatalogID, provider: session.server.providerKind, scope: session.references.scope)
        return GusDiscoverTitleEntity(id: id, title: title)
    }

    func resolve(id: String) async throws -> SeerrTitle? {
        guard let raw = GusIntentID.value(id, resource: resource, provider: session.server.providerKind, scope: session.references.scope) else { return nil }
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let type = SeerrMediaType(rawValue: String(parts[0])), type == .movie || type == .tv,
              let number = Int(parts[1]), number > 0 else { return nil }
        let detail = try await client.details(mediaType: type, id: number)
        try validate()
        guard detail.id == number, detail.mediaType == type, session.seerr.admits(detail) else { return nil }
        return detail
    }
}

struct GusDiscoverQuery: EntityStringQuery {
    func suggestedEntities() async throws -> [GusDiscoverTitleEntity] {
        []
    }

    @MainActor func entities(for identifiers: [String]) async throws -> [GusDiscoverTitleEntity] {
        let context = try await GusDiscoverSession(session: GusIntentRuntime.session())
        var results = [GusDiscoverTitleEntity]()
        for identifier in identifiers {
            do {
                if let title = try await context.resolve(id: identifier), let entity = context.entity(title) {
                    results.append(entity)
                }
            } catch SeerrClientError.notFound { continue }
        }
        try context.validate()
        return results
    }

    @MainActor func entities(matching string: String) async throws -> [GusDiscoverTitleEntity] {
        guard let search = string.trimmedNilIfEmpty else { return [] }
        let context = try await GusDiscoverSession(session: GusIntentRuntime.session())
        let page = try await context.client.search(query: search)
        try context.validate()
        let candidates = page.results.filter { $0.mediaType == .movie || $0.mediaType == .tv }
        let titles = try await context.session.seerr.admitted(candidates)
        try context.validate()
        return titles.compactMap(context.entity)
    }
}

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct FindGusDiscoverTitlesIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Discover Titles"
    static let description = IntentDescription("Searches movies and TV series on the connected Seerr service.", categoryName: "Discover")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Search") var query: String

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[GusDiscoverTitleEntity]> {
        try .result(value: await GusDiscoverQuery().entities(matching: query))
    }
}

enum GusRequestQuality: String, AppEnum {
    case standard, ultraHD
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Request Quality"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.standard: "Standard", .ultraHD: "4K"]
}

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppIntent(.tool)
#endif
struct RequestGusDiscoverTitleIntent: AppIntent {
    static let title: LocalizedStringResource = "Request Discover Title"
    static let description = IntentDescription("Reviews the title, quality, and TV seasons before sending a Seerr request. An empty season selection includes all eligible seasons.", categoryName: "Discover")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Discover Title") var item: GusDiscoverTitleEntity
    @Parameter(title: "Quality", default: .standard) var quality: GusRequestQuality
    @Parameter(title: "Season Numbers") var seasons: [Int]?

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<GusActionStatus> {
        let context = try await GusDiscoverSession(session: GusIntentRuntime.session())
        let store = context.session.seerr
        guard let detail = try await context.resolve(id: item.id) else { throw GusError.notFound }
        let status: GusActionStatus = try await GusAutomationWrite.perform(key: item.id) {
            let sharedDraft = store.requestDraft(for: detail)
            guard sharedDraft.phase != .uncertain else { return .uncertain }
            guard sharedDraft.phase != .submitting else { return .inProgress }
            // Keep a shortcut's parameters independent of an editor open in Gus.
            // Both entry points must acquire the same durable Seerr journal slot.
            let draft = SeerrRequestDraft(title: detail)
            draft.is4K = quality == .ultraHD
            await draft.load(store: store)
            try context.validate()
            guard store.admits(draft.title), draft.is4K == (quality == .ultraHD) else { throw SeerrConnectionError.notPermitted }
            let selection = Set(seasons ?? [])
            if detail.mediaType == .tv {
                draft.selectedSeasons = selection.isEmpty ? Set(draft.eligibleSeasons) : selection
            } else if !selection.isEmpty {
                throw GusError.server(String(localized: "Season numbers apply only to a TV series."))
            }
            guard draft.canSubmit else { throw GusError.server(draft.message ?? SeerrConnectionError.eligibilityChanged.localizedDescription) }
            if detail.mediaType == .tv {
                let numbers = draft.selectedSeasons.sorted().map(String.init).joined(separator: ", ")
                try await requestConfirmation(dialog: "Request \(detail.displayTitle), seasons \(numbers), in \(quality)?")
            } else {
                try await requestConfirmation(dialog: "Request \(detail.displayTitle) in \(quality)?")
            }
            try context.validate()
            guard store.admits(draft.title) else { throw SeerrConnectionError.notPermitted }
            await draft.submit(store: store)
            try context.validate()
            return try GusActionStatus(draft.actionOutcome, failure: draft.message)
        }
        return .result(value: status)
    }
}
