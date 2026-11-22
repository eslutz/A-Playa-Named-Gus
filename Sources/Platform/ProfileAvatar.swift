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
    let hasServerPicture: Bool
    @Binding var picture: ProfilePictureChange
    @Binding var isLoading: Bool
    @State private var choosing = false
    #if !os(tvOS)
        @State private var selection: PhotosPickerItem?
        @State private var errorMessage: String?
    #endif

    var body: some View {
        Menu {
            Button("Choose Photo", systemImage: "photo") { choosing = true }
            if picture.preview(current: current) != nil || (picture == .unchanged && hasServerPicture) {
                Button("Remove Photo", systemImage: "trash", role: .destructive) {
                    picture = hasServerPicture ? .remove : .unchanged
                }
            }
        } label: {
            ProfileAvatar(data: picture.preview(current: current))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.background, .primary)
                        .background(.background, in: Circle())
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Change Profile Picture")
        .accessibilityIdentifier("Profile.picture")
        .disabled(isLoading)
        #if os(tvOS)
            .navigationDestination(isPresented: $choosing) { TVProfilePhotos(picture: $picture) }
        #else
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
                    picture = .replace(jpeg)
                } catch {
                    if !Task.isCancelled {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        #endif
        #if !os(tvOS)
            if isLoading {
                ProgressView()
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.secondary)
            }
        #endif
    }
}

#if os(tvOS)
    /// tvOS has no system Photos picker. Offer the signed-in user's Jellyfin photos.
    private struct TVProfilePhotos: View {
        @Environment(SessionStore.self) private var session
        @Environment(\.dismiss) private var dismiss
        @Binding var picture: ProfilePictureChange
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
                    picture = try .replace(CollectionArtwork.jpeg(from: jpeg, maxPixelSize: 1024))
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
