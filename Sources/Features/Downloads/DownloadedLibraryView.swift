import SwiftUI

/// Browses saved metadata and verified completed files, including with an offline server.
struct DownloadedLibraryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(RootNavigationState.self) private var rootState
    @Environment(SessionStore.self) private var session
    @Environment(OfflineDownloadStore.self) private var downloads

    @FocusState private var isSearchFocused: Bool
    @State private var playerItem: ItemRef?
    @State private var missingFile = false
    @StoredContentPolicy private var contentPolicy

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
        _ = contentPolicy
        return DownloadedLibrary.sections(records: completed, filter: filter, search: search)
    }

    var body: some View {
        let visibleSections = sections
        List {
            if !visibleSections.isEmpty {
                if case let .failed(message) = downloads.loadState {
                    Text(message).foregroundStyle(.secondary)
                    Button("Try Again", action: reload)
                } else if downloads.loadState == .loading {
                    ProgressView().accessibilityLabel("Refreshing")
                }
            }
            downloadRows(visibleSections)
        }
        .overlay {
            if visibleSections.isEmpty {
                LoadingStateView(state: downloads.loadState, retryAction: reload) {
                    ContentUnavailableView {
                        Label(search.isEmpty ? "No Downloads" : "No Results", systemImage: "arrow.down.circle")
                    } description: {
                        Text(search.isEmpty ? "Completed downloads available on this device appear here." : "Try another title, series, or artist.")
                    }
                }
            }
        }
        .task { reload() }
        .refreshable { reload() }
        .navigationTitle("Downloads")
        .modifier(DownloadsSearchField(text: Bindable(rootState).projectedValue.downloadSearch, isPresented: Bindable(rootState).projectedValue.isDownloadSearchPresented, isFocused: $isSearchFocused))
        .onChange(of: rootState.pendingLocalSearchFocus, initial: true) { _, section in
            guard section == NavigationSectionPreference.downloadedID else { return }
            rootState.pendingLocalSearchFocus = nil
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
                Menu("Downloads Options", systemImage: "ellipsis") {
                    NavigationLink("Manage Downloads", value: GusRoute.screen(.downloads))
                }
                .accessibilityIdentifier("Downloads.options")
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

    private func downloadRows(_ sections: [DownloadedLibrarySection]) -> some View {
        ForEach(sections) { section in
            Section(section.title) {
                ForEach(section.records) { record in
                    let item = record.playbackItem
                    Button { play(record) } label: {
                        HStack(spacing: ContentSpacing.card) {
                            OfflineArtwork(url: downloads.localArtworkURL(
                                for: item, serverID: session.server.id, userID: session.user.id
                            ), systemImage: item.isAudioPlayable ? "music.note" : item.type == .book ? "book" : "film")
                                .frame(width: 48, height: 64)
                            VStack(alignment: .leading, spacing: ContentSpacing.caption) {
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
