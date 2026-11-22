#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    import AppIntents
    import SwiftUI

    extension GusMediaEntity: SnippetRepresentableEntity {
        static var authenticationPolicy: IntentAuthenticationPolicy {
            .requiresAuthentication
        }

        static var snippet: some EntitySnippetContent<Self> {
            CardSnippet(supportedFamilies: [.standard]) { item, _ in
                VStack(alignment: .leading) {
                    Text(verbatim: item.title).font(.headline)
                    Text(verbatim: item.subtitle).font(.subheadline)
                }
                .privacySensitive()
            }
        }
    }
#endif

#if GUS_SIRI_AI_PREVIEW && (os(iOS) || os(macOS) || os(visionOS))
    @AppEntity(.generable)
    struct GusMovieSearchDescription: TransientAppEntity {
        static let typeDisplayRepresentation: TypeDisplayRepresentation = "Movie Search"
        @Property(title: "Genre", description: "A genre to match in the current library.") var genre: String?
        @Property(title: "Earliest Year") var earliestYear: Int?
        @Property(title: "Latest Year") var latestYear: Int?
        @Property(title: "Maximum Minutes") var maximumMinutes: Int?
        var displayRepresentation: DisplayRepresentation {
            "Movie Search"
        }

        init() {}
    }

    @AppIntent(.tool)
    struct FindGusMoviesByDescription: AppIntent {
        static let title: LocalizedStringResource = "Find Movies by Description"
        static let description = IntentDescription("Find movies that match the supplied genre, release years and duration in the current Jellyfin library.")
        static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
        @Parameter(title: "Movie Search") var filter: GusMovieSearchDescription

        @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[GusMediaEntity]> {
            let action = FilterGusLibraryIntent()
            action.mediaType = .movie
            action.genre = filter.genre
            action.earliestYear = filter.earliestYear
            action.latestYear = filter.latestYear
            action.maximumMinutes = filter.maximumMinutes
            let criteria = try action.filters()
            let session = try await GusIntentRuntime.session()
            let rows = try await session.libraryIntelligence.search(criteria)
            try GusIntentRuntime.validate(session)
            return .result(value: rows.compactMap { GusIntentRuntime.entity($0, in: session) })
        }
    }
#endif
