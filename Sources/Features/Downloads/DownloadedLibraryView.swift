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
        Group {
            if sections.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty ? "No Downloaded Media" : "No Results", systemImage: "arrow.down.circle")
                } description: {
                    Text(search.isEmpty ? "Completed downloads available on this device appear here." : "Try another title, series, or artist.")
                } actions: {
                    NavigationLink("Manage Downloads", value: AppScreen.downloads)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            } else {
                List {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.records) { record in
                                Button { play(record.item) } label: {
                                    HStack(spacing: 12) {
                                        OfflineArtwork(url: downloads.localArtworkURL(
                                            for: record.item, serverID: session.server.id, userID: session.user.id
                                        ), systemImage: record.item.isAudioPlayable ? "music.note" : record.item.type == .book ? "book" : "film")
                                            .frame(width: 48, height: 64)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(record.item.displayTitle).font(.headline)
                                            if let episode = DownloadedLibrary.episodeLabel(record.item) {
                                                Text(episode).font(.subheadline).foregroundStyle(.secondary)
                                            } else if let artist = record.item.albumArtist ?? record.item.artists.first {
                                                Text(artist).font(.subheadline).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: record.item.type == .book ? "book" : "play.fill")
                                            .accessibilityHidden(true)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(record.item.type == .book ? "Opens the downloaded book" : "Plays the downloaded file")
                            }
                        }
                    }
                }
            }
        }
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
                NavigationLink(value: AppScreen.downloads) {
                    Label("Manage Downloads", systemImage: "arrow.down.circle").frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .playerPresentation(item: $playerItem)
        .alert("Download Unavailable", isPresented: $missingFile) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The downloaded file is missing. Manage Downloads to download it again.")
        }
    }

    private var mediaTypePicker: some View {
        Picker("Media Type", selection: Bindable(rootState).projectedValue.downloadFilter) {
            ForEach(DownloadedLibraryFilter.allCases) { value in Text(value.title).tag(value) }
        }
    }

    private func play(_ item: MediaItem) {
        guard ContentRatingGate.admitsStored(item) else { return }
        guard downloads.localFileURL(for: item, serverID: session.server.id, userID: session.user.id) != nil else {
            missingFile = true
            return
        }
        playerItem = ItemRef(item: item, localOnly: true, serverID: session.server.id, userID: session.user.id)
    }
}
