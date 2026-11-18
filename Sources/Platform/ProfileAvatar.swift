import SwiftUI
#if os(tvOS)
    import JellyfinAPI
#else
    import PhotosUI
#endif

struct ProfileAvatar: View {
    let data: Data?
    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64).clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var image: Image? {
        guard let data else { return nil }
        #if os(macOS)
            return NSImage(data: data).map { Image(nsImage: $0) }
        #else
            return UIImage(data: data).map { Image(uiImage: $0) }
        #endif
    }
}

struct ProfilePicturePicker: View {
    let current: Data?
    @Binding var picture: Data?
    @Binding var isLoading: Bool
    #if !os(tvOS)
        @State private var choosing = false
        @State private var selection: PhotosPickerItem?
        @State private var errorMessage: String?
    #endif

    var body: some View {
        #if os(tvOS)
            NavigationLink {
                TVProfilePhotos(picture: $picture)
            } label: {
                label
            }
        #else
            Button { choosing = true } label: { label }
                .photosPicker(isPresented: $choosing, selection: $selection, matching: .images)
                .task(id: selection) {
                    guard let selectedPhoto = selection else { return }
                    isLoading = true
                    errorMessage = nil
                    defer {
                        if !Task.isCancelled {
                            isLoading = false
                            selection = nil
                        }
                    }
                    do {
                        guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                            throw GusError.server(String(localized: "This image could not be opened."))
                        }
                        let jpeg = try await Task.detached { try CollectionArtwork.jpeg(from: data, maxPixelSize: 1024) }.value
                        try Task.checkCancellation()
                        picture = jpeg
                    } catch {
                        if !Task.isCancelled {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.secondary)
            }
        #endif
    }

    private var label: some View {
        HStack {
            ProfileAvatar(data: picture ?? current)
            Text("Change Profile Picture")
            if isLoading {
                ProgressView()
            }
        }
    }
}

#if os(tvOS)
    /// tvOS has no system Photos picker. Offer the signed-in user's Jellyfin photos.
    private struct TVProfilePhotos: View {
        @Environment(SessionStore.self) private var session
        @Environment(\.dismiss) private var dismiss
        @Binding var picture: Data?
        @State private var library: LibraryStore?
        @State private var selectedID: String?
        @State private var errorMessage: String?

        var body: some View {
            LoadingStateView(
                state: library?.state ?? .idle,
                isEmpty: library?.items.isEmpty == true,
                emptyTitle: String(localized: "No Jellyfin Photos"),
                emptySymbol: "photo",
                retryAction: { Task { await library?.load() } }
            ) {
                if let library {
                    List {
                        if let errorMessage {
                            Text(errorMessage)
                        }
                        ForEach(library.items, id: \.id) { photo in
                            Button { selectedID = photo.id } label: {
                                HStack {
                                    ArtworkTile(url: session.mediaProvider.primaryImageURL(for: photo, maxWidth: 160), aspectRatio: 1)
                                        .frame(width: 72, height: 72).accessibilityHidden(true)
                                    Text(photo.displayTitle)
                                    if selectedID == photo.id {
                                        ProgressView()
                                    }
                                }
                            }
                        }
                        if let error = library.pageError {
                            Text(error)
                        }
                        if library.canLoadMore {
                            Button("Load More") { Task { await library.continueSearching() } }
                                .disabled(library.isLoadingNextPage)
                        }
                    }
                    .disabled(selectedID != nil)
                }
            }
            .navigationTitle("Choose a Jellyfin Photo")
            .task {
                let library = LibraryStore(scope: .photoLibrary(parentID: nil, albums: false), session: session)
                self.library = library
                await library.load()
            }
            .task(id: selectedID) {
                guard let selectedID else { return }
                do {
                    let jpeg = try await session.client.send(Paths.getItemImage(
                        itemID: selectedID,
                        imageType: "Primary",
                        parameters: .init(maxWidth: 1024, maxHeight: 1024, format: .jpg)
                    )).value
                    try Task.checkCancellation()
                    picture = try CollectionArtwork.jpeg(from: jpeg, maxPixelSize: 1024)
                    dismiss()
                } catch {
                    if !Task.isCancelled {
                        errorMessage = GusError(from: error).localizedDescription
                        self.selectedID = nil
                    }
                }
            }
        }
    }
#endif
