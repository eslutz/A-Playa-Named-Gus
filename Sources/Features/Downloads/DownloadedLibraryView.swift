import SwiftUI

/// Browses saved metadata and verified completed files, including with an offline server.
struct DownloadedLibraryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(RootNavigationState.self) private var rootState
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads
    @Environment(AppNavigationModel.self) private var navigation

    @FocusState private var isSearchFocused: Bool
    @State private var playerItem: ItemRef?
    @State private var missingFile = false
    @AppStorage(ContentRatingGate.limitDefaultsKey) private var ratingLimit = "off"
    @AppStorage(ContentRatingGate.hideUnratedDefaultsKey) private var hideUnrated = false

    private var filter: DownloadedLibraryFilter {
        rootState.downloadFilter
    }

    private var search: String {
        rootState.downloadSearch
    }

    private var completed: [OfflineDownloadRecord] {
        downloads.completedRecords(serverID: session.server.id, userID: session.user.id)
    }

    private var sections: [DownloadedLibrarySection] {
        _ = ratingLimit
        _ = hideUnrated
        return DownloadedLibrary.sections(records: completed, filter: filter, search: search)
    }

    var body: some View {
        LoadingStateView(
            state: downloads.loadState,
            retryAction: { reload() },
            preservesContent: !sections.isEmpty
        ) {
            libraryContent
        }
        .task { reload() }
        .refreshable { reload() }
        .navigationTitle("Downloaded")
        .gusSearchable(text: Bindable(rootState).projectedValue.downloadSearch, isPresented: Bindable(rootState).projectedValue.isDownloadSearchPresented, isFocused: $isSearchFocused, prompt: Text("Search Downloaded"))
        .onChange(of: navigation.searchFocusRequest) { _, request in
            guard request > 0 else { return }
            rootState.isDownloadSearchPresented = true
            isSearchFocused = true
        }
        .safeAreaInset(edge: .top) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    mediaTypePicker.pickerStyle(.menu)
                } else {
                    mediaTypePicker.pickerStyle(.segmented)
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem {
                NavigationLink(value: GusRoute.screen(.downloads)) {
                    Label("Manage Downloads", systemImage: "arrow.down.circle").frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .playerPresentation(item: $playerItem)
        .downloadErrorAlert(downloads)
        .alert("Download Unavailable", isPresented: $missingFile) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The downloaded file is missing. Manage Downloads to download it again.")
        }
    }

    @ViewBuilder private var libraryContent: some View {
        if sections.isEmpty {
            ContentUnavailableView {
                Label(search.isEmpty ? "No Downloaded Media" : "No Results", systemImage: "arrow.down.circle")
            } description: {
                Text(search.isEmpty ? "Completed downloads available on this device appear here." : "Try another title, series, or artist.")
            } actions: {
                NavigationLink("Manage Downloads", value: GusRoute.screen(.downloads))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
        } else {
            List {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.records) { record in
                            let item = record.playbackItem
                            Button { play(record) } label: {
                                HStack(spacing: 12) {
                                    OfflineArtwork(url: downloads.localArtworkURL(
                                        for: item, serverID: session.server.id, userID: session.user.id
                                    ), systemImage: item.isAudioPlayable ? "music.note" : item.type == .book ? "book" : "film")
                                        .frame(width: 48, height: 64)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.displayTitle).font(.headline)
                                        if let episode = DownloadedLibrary.episodeLabel(item) {
                                            Text(episode).font(.subheadline).foregroundStyle(.secondary)
                                        } else if let artist = record.item.albumArtist ?? record.item.artists.first {
                                            Text(artist).font(.subheadline).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: item.type == .book ? "book" : "play.fill")
                                        .accessibilityHidden(true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(item.mediaAccessibility.label)
                            .accessibilityValue([item.mediaAccessibility.value, String(localized: "Downloaded")].filter { !$0.isEmpty }.joined(separator: ", "))
                            .gusDownloadSwipeDelete {
                                downloads.delete(record, serverID: session.server.id, userID: session.user.id)
                            }
                            .accessibilityHint(item.type == .book ? "Opens the downloaded book" : "Plays the downloaded file")
                        }
                    }
                }
            }
        }
    }

    private func reload() {
        downloads.load(serverID: session.server.id, userID: session.user.id)
    }

    private var mediaTypePicker: some View {
        Picker("Media Type", selection: Bindable(rootState).projectedValue.downloadFilter) {
            ForEach(DownloadedLibraryFilter.allCases) { value in Text(value.title).tag(value) }
        }
    }

    private func play(_ record: OfflineDownloadRecord) {
        let request = record.playbackRequest
        let item = request.item
        guard ContentRatingGate.admitsStored(item) else { return }
        guard downloads.localFileURL(for: item, serverID: session.server.id, userID: session.user.id, mediaSourceID: record.mediaSourceID) != nil else {
            missingFile = true
            return
        }
        playerItem = ItemRef(item: item, localOnly: true, serverID: session.server.id, userID: session.user.id, playbackRequest: request)
    }
}
