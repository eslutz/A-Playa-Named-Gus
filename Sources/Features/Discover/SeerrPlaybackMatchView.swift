import SwiftUI

struct SeerrPlaybackMatchView: View {
    @Environment(SessionStore.self) private var session
    @Environment(SeerrStore.self) private var store
    let title: SeerrTitle
    var seasonNumber: Int? = nil
    @State private var matches: [MediaItem] = []
    @State private var loading = false
    @State private var checked = false
    @State private var message: String?
    @State private var lookup: Task<Void, Never>?
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var restriction = "off"
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !checked || loading || message != nil {
                Button {
                    lookup?.cancel()
                    lookup = Task { await find() }
                } label: {
                    HStack {
                        Label(loading ? "Checking Jellyfin…" : "Find in Gus", systemImage: "play.rectangle"); if loading {
                            ProgressView()
                        }
                    }
                }.disabled(loading)
            }
            ForEach(matches.filter { ContentRatingGate.admitsStored($0) }, id: \.id) { item in
                NavigationLink(value: ItemRef(item: item)) {
                    Label(matches.count > 1 ? item.displayTitle : String(localized: "Open in Gus"), systemImage: "play.circle")
                }
            }
            if checked, matches.isEmpty, !loading, message == nil {
                Text("No matching title is accessible in this Jellyfin account.").font(.callout).foregroundStyle(.secondary)
            }
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .onDisappear { lookup?.cancel() }
        .onChange(of: store.revision) { _, _ in clear() }
        .onChange(of: restriction) { _, _ in clear() }
        .onChange(of: hideUnrated) { _, _ in clear() }
    }

    private func clear() {
        lookup?.cancel(); matches = []; checked = false; loading = false; message = nil
    }

    private func find() async {
        loading = true; message = nil
        let expected = store.revision, restriction = store.restrictionRevision
        defer { loading = false }
        do {
            guard store.admits(title) else { throw SeerrConnectionError.notPermitted }
            let result = try await SeerrPlaybackResolver.matches(title: title, provider: session.mediaProvider, seasonNumber: seasonNumber)
            guard !Task.isCancelled, expected == store.revision, restriction == store.restrictionRevision else { return }
            matches = result; checked = true
        } catch {
            guard !Task.isCancelled, expected == store.revision else { return }
            message = error.localizedDescription
        }
    }
}
