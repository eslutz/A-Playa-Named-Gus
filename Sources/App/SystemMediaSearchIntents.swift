import AppIntents

#if !os(tvOS)
    @available(iOS, obsoleted: 27)
    @available(macOS, obsoleted: 27)
    @available(visionOS, obsoleted: 27)
#endif
struct SearchGusLibraryIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Show Library Search Results"
    static let searchScopes: [StringSearchScope] = [.general, .movies, .tv, .freeformVideo]
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Search") var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        let session = try await GusIntentRuntime.session()
        AppNavigationModel.shared.openLibrarySearch(criteria.term, for: session)
        return .result()
    }
}

#if !os(tvOS)
    @available(iOS 27, macOS 27, visionOS 27, *)
    @AppIntent(schema: .system.searchInApp)
    struct GusSystemLibrarySearch: ShowInAppSearchResultsIntent {
        static let searchScopes: [StringSearchScope] = [.general, .movies, .tv, .freeformVideo]
        var criteria: StringSearchCriteria

        @MainActor func perform() async throws -> some IntentResult {
            let session = try await GusIntentRuntime.session()
            AppNavigationModel.shared.openLibrarySearch(criteria.term, for: session)
            return .result()
        }
    }
#endif

struct PlayGusVideoIntent: PlayVideoIntent {
    static let title: LocalizedStringResource = "Play Library Video"
    static let supportedCategories: [VideoCategory] = [.movies, .tv, .freeform]
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Title") var term: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let session = try await GusIntentRuntime.session()
        let page = try await GusIntentRuntime.search(term, in: session, types: [.movie, .episode, .video, .trailer, .recording])
        let exact = page.items.filter { $0.displayTitle.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        if exact.count == 1, let item = exact.first, page.totalRecordCount.map({ $0 <= 50 }) == true {
            try GusIntentRuntime.open(item, in: session, play: true)
        } else {
            // Search results allow a person to choose an edition or episode when names overlap.
            AppNavigationModel.shared.openLibrarySearch(term, for: session)
        }
        return .result()
    }
}
