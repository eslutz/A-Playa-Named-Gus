import Observation
import SwiftUI

@MainActor @Observable
private final class SeerrPersonStore {
    private(set) var person: SeerrPerson?
    private(set) var cast: [SeerrTitle] = []
    private(set) var crew: [SeerrTitle] = []
    private(set) var state: LoadState = .idle
    private(set) var creditsState: LoadState = .idle
    private(set) var revision: UUID?
    private(set) var restrictions: String?
    private var generation = UUID()

    func load(id: Int, store: SeerrStore) async {
        generation = UUID()
        let operation = generation
        let revision = store.revision
        let restrictions = String(describing: store.restrictionRevision)
        self.revision = revision
        self.restrictions = restrictions
        person = nil
        cast = []
        crew = []
        state = .loading
        creditsState = .idle
        do {
            let result = try await store.requireClient().person(id: id)
            guard isCurrent(operation, revision: revision, restrictions: restrictions, store: store) else { return }
            person = result
            state = .loaded
        } catch {
            guard isCurrent(operation, revision: revision, restrictions: restrictions, store: store) else { return }
            store.handle(error)
            state = .failed(error.localizedDescription)
            return
        }
        await loadCredits(id: id, store: store)
    }

    func loadCredits(id: Int, store: SeerrStore) async {
        let operation = generation
        let revision = store.revision
        let restrictions = String(describing: store.restrictionRevision)
        creditsState = .loading
        do {
            let credits = try await store.requireClient().personCredits(id: id)
            let cast = try await store.admitted(credits.cast)
            let crew = try await store.admitted(credits.crew)
            guard isCurrent(operation, revision: revision, restrictions: restrictions, store: store) else { return }
            self.cast = deduplicated(cast)
            self.crew = deduplicated(crew)
            creditsState = .loaded
        } catch {
            guard isCurrent(operation, revision: revision, restrictions: restrictions, store: store) else { return }
            store.handle(error)
            creditsState = .failed(error.localizedDescription)
        }
    }

    private func isCurrent(_ operation: UUID, revision: UUID, restrictions: String, store: SeerrStore) -> Bool {
        !Task.isCancelled && generation == operation && store.revision == revision
            && String(describing: store.restrictionRevision) == restrictions
    }

    private func deduplicated(_ values: [SeerrTitle]) -> [SeerrTitle] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.seerrCatalogID).inserted }
    }
}

/// People lead to their actual typed movie/TV credits and never expose Request or Play.
struct SeerrPersonView: View {
    let personID: Int
    let displayName: String
    let store: SeerrStore
    @State private var model = SeerrPersonStore()
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var contentLimitRawValue = ContentRatingGate.Limit.off.rawValue
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnratedContent = false

    private var accessRevision: String {
        "\(store.revision):\(contentLimitRawValue):\(hideUnratedContent)"
    }

    var body: some View {
        LoadingStateView(state: model.state, retryAction: { Task { await model.load(id: personID, store: store) } }) {
            if model.revision == store.revision, model.restrictions == store.restrictionRevision, let person = model.person {
                content(person)
            }
        }
        .navigationTitle(model.revision == store.revision ? model.person?.name ?? String(localized: "Person") : String(localized: "Person"))
        .task(id: accessRevision) { await model.load(id: personID, store: store) }
    }

    private func content(_ person: SeerrPerson) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SeerrArtworkView(path: person.profilePath, aspectRatio: 4.0 / 5.0, symbol: "person")
                    .frame(maxWidth: 240)
                Text(person.name).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                if let birthplace = person.placeOfBirth?.trimmedNilIfEmpty {
                    Text(birthplace).font(.subheadline).foregroundStyle(.secondary)
                }
                if let biography = person.biography?.trimmedNilIfEmpty {
                    Text(biography).font(.body).fixedSize(horizontal: false, vertical: true)
                }
                credits
            }
            .padding()
            .frame(maxWidth: PageContentMetrics.maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .lookToScroll()
        .refreshable { await model.load(id: personID, store: store) }
    }

    @ViewBuilder private var credits: some View {
        if model.creditsState == .loading {
            ProgressView("Loading credits")
        } else if case let .failed(message) = model.creditsState {
            Text(message).foregroundStyle(.secondary)
            Button("Retry Credits") { Task { await model.loadCredits(id: personID, store: store) } }
        } else if model.creditsState == .loaded {
            if model.cast.isEmpty && model.crew.isEmpty {
                Text("No credits available").foregroundStyle(.secondary)
            }
            if !model.cast.isEmpty {
                SeerrPersonCreditSection(title: String(localized: "Acting"), titles: model.cast, store: store)
            }
            if !model.crew.isEmpty {
                SeerrPersonCreditSection(title: String(localized: "Crew"), titles: model.crew, store: store)
            }
        }
    }
}

private struct SeerrPersonCreditSection: View {
    let title: String
    let titles: [SeerrTitle]
    let store: SeerrStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            if dynamicTypeSize.isAccessibilitySize {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(titles.filter { store.admits($0) }, id: \.seerrCatalogID) { title in
                        credit(title, usesList: true)
                    }
                }
            } else {
                LazyVGrid(columns: PosterGrid.columns, alignment: .leading, spacing: 24) {
                    ForEach(titles.filter { store.admits($0) }, id: \.seerrCatalogID) { title in
                        credit(title, usesList: false)
                    }
                }
            }
        }
    }

    private func credit(_ title: SeerrTitle, usesList: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SeerrResultLink(title: title, store: store, usesList: usesList)
            if let role = (title.character ?? title.job)?.trimmedNilIfEmpty {
                Text(role).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
