import SwiftUI

/// This view exists only for an explicitly submitted query and retires with that submission.
struct SeerrInterpretedResults: View {
    @Environment(SessionStore.self) private var session
    let submission: DiscoverSubmission
    let store: SeerrStore
    let isCurrentSubmission: () -> Bool
    let useKeyword: () -> Void
    @State private var catalog: SeerrCatalogStore?
    @State private var message: String?

    private var isCurrent: Bool {
        session.isActive && session.seerr === store && store.isConnected && store.revision == submission.connection &&
            store.restrictionRevision == submission.restrictions && isCurrentSubmission()
    }

    var body: some View {
        Group {
            if let catalog, case let .natural(intent) = catalog.source {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: intent.filterDescription)
                        .font(.subheadline).bold()
                    Text("Matches from a limited set of Seerr results.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if catalog.isValid(for: store), catalog.state == .loaded, catalog.items.isEmpty {
                        ContentUnavailableView {
                            Label("No Verified Matches", systemImage: "magnifyingglass")
                        } description: {
                            Text("Seerr’s available metadata did not confirm a match in the searched results.")
                        }
                    } else {
                        SeerrCatalogResults(catalog: catalog, store: store)
                    }
                }
            } else if let message {
                ContentUnavailableView {
                    Label("Natural Language Search Unavailable", systemImage: "magnifyingglass")
                } description: {
                    Text(verbatim: message)
                }
            } else {
                ProgressView("Searching Discover")
            }
        }
        .task {
            guard isCurrent, !Task.isCancelled else { return }
            if let catalog {
                await catalog.load(store: store)
                return
            }
            guard message == nil else { return }
            do {
                let allowed = try await session.intelligenceAccess.requestSearchAccess()
                try Task.checkCancellation()
                guard isCurrent else { return }
                guard allowed else { throw GusIntelligenceError.useKeyword }
                let intent = try await GusIntelligenceModel(session: session).interpretDiscover(submission.text)
                try Task.checkCancellation()
                guard isCurrent else { return }
                guard intent.isSupported else {
                    let missing = intent.unsupported.prefix(4).map { String($0.prefix(100)) }.joined(separator: ", ")
                    message = missing.isEmpty
                        ? String(localized: "Seerr cannot verify all the requested conditions. Try a title, genre, or release year.")
                        : String(localized: "Seerr cannot verify the requested condition ‘\(missing)’.")
                    return
                }
                let results = SeerrCatalogStore(source: .natural(intent))
                catalog = results
                await results.load(store: store)
            } catch GusIntelligenceError.useKeyword {
                guard !Task.isCancelled, isCurrent else { return }
                useKeyword()
            } catch {
                guard !Task.isCancelled, isCurrent else { return }
                message = error.localizedDescription
            }
        }
    }
}
