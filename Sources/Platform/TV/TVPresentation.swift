import SwiftUI

extension View {
    @ViewBuilder func gusTVHomeTitle() -> some View {
        #if os(tvOS)
            navigationTitle("")
        #else
            navigationTitle("Home")
        #endif
    }

    /// Keep TV presentation and focus divergence outside the shared feature views.
    @ViewBuilder func gusTVFocus(id: String, section: String, ids: [String], initial: Bool = false, item: MediaItem? = nil, entry: NextUpEntry? = nil, context: String? = nil) -> some View {
        #if os(tvOS)
            modifier(TVFocusModifier(id: id, section: section, ids: ids, initial: initial, item: item, entry: entry, context: context ?? section))
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVNextUpHero(entries: [NextUpEntry]) -> some View {
        #if os(tvOS)
            TVNextUpHero(entries: entries) { self }
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVFallbackHero(items: [MediaItem], enabled: Bool) -> some View {
        #if os(tvOS)
            if enabled {
                TVNextUpHero(entries: items.compactMap { item in
                    NextUpBuilder.mediaID(item).map { NextUpEntry(id: $0, item: item, reasons: [], activityAt: nil) }
                }) { self }
            } else {
                self
            }
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVBrowsingBackdrop() -> some View {
        #if os(tvOS)
            background { TVBrowsingBackdrop().ignoresSafeArea() }
        #else
            self
        #endif
    }

    /// Read-only rails still need native focus targets so the remote can scroll to them.
    @ViewBuilder func gusTVFocusableInfo() -> some View {
        #if os(tvOS)
            accessibilityElement(children: .combine)
                .hoverEffect(.highlight)
                .focusable()
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVDetailCanvas() -> some View {
        #if os(tvOS)
            background { Rectangle().fill(.background).ignoresSafeArea() }
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVPagePadding() -> some View {
        #if os(tvOS)
            padding(.horizontal, 64).padding(.vertical, 32)
        #else
            gusPhonePagePadding()
        #endif
    }

    @ViewBuilder func gusTVRailPadding() -> some View {
        #if os(tvOS)
            padding(.vertical, 32).padding(.horizontal, 24)
        #else
            padding(.vertical, 4)
        #endif
    }

    @ViewBuilder func gusTVDetailTitle() -> some View {
        #if os(tvOS)
            toolbar(.hidden, for: .navigationBar)
        #else
            self
        #endif
    }

    /// Inset labels within native artwork cards without adding a bezel around the image.
    @ViewBuilder func gusTVCardCaption() -> some View {
        #if os(tvOS)
            padding(.horizontal, 16).padding(.bottom, 16)
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVPosterTitle() -> some View {
        #if os(tvOS)
            lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        #else
            lineLimit(1)
        #endif
    }

    /// All platforms anchor progress to the artwork, never to variable-height captions.
    func gusTVArtworkStatus(item: MediaItem?, progressID: String = "") -> some View {
        overlay(alignment: .bottom) {
            if let progress = item?.playbackProgress, progress > 0, progress < 1 {
                ProgressView(value: progress)
                    .tint(.white)
                    .padding(8)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(12)
                    .accessibilityLabel("Playback progress")
                    .accessibilityIdentifier(progressID)
            }
        }
    }

    @ViewBuilder func gusTVBrowseViewport() -> some View {
        #if os(tvOS)
            ignoresSafeArea(.container, edges: .horizontal)
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVRailViewport() -> some View {
        #if os(tvOS)
            scrollClipDisabled()
        #else
            self
        #endif
    }

    @ViewBuilder func gusDetailActionLabel() -> some View {
        #if os(tvOS)
            labelStyle(TVActionLabelStyle())
        #else
            labelStyle(.iconOnly)
        #endif
    }

    @ViewBuilder func gusTVPosterStatusValue(item: MediaItem?) -> some View {
        if let progress = item?.playbackProgress, progress > 0, progress < 1 {
            accessibilityValue(Text("Playback progress \(Int(progress * 100))%"))
        } else if let watched = item?.userData?.isWatched {
            accessibilityValue(watched ? Text("Watched") : Text("Unwatched"))
        } else {
            self
        }
    }

    /// Share focus order across the primary action, common icons, overflow and synopsis.
    func gusTVDetailActionFocus(id: String, item: MediaItem, initial: Bool = false) -> some View {
        var ids = ["play", "nextUp", "favorite", "watched"]
        if item.type == .movie || item.type == .episode {
            ids.append("playlist")
        }
        ids += ["more", "synopsis"]
        return gusTVFocus(id: id, section: "detail:" + ItemRef(item: item).id, ids: ids, initial: initial, item: item)
    }
}

#if os(tvOS)
    private struct TVActionLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            VStack(spacing: 10) {
                configuration.icon.font(.title3).frame(height: 48)
                configuration.title.font(.caption2)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 140)
        }
    }

    private struct TVFocusedMediaKey: FocusedValueKey { typealias Value = MediaItem }
    private struct TVFocusedEntryKey: FocusedValueKey { typealias Value = NextUpEntry }
    extension FocusedValues {
        var gusTVMedia: MediaItem? {
            get { self[TVFocusedMediaKey.self] }
            set { self[TVFocusedMediaKey.self] = newValue }
        }

        var gusTVEntry: NextUpEntry? {
            get { self[TVFocusedEntryKey.self] }
            set { self[TVFocusedEntryKey.self] = newValue }
        }
    }

    private struct TVFocusModifier: ViewModifier {
        @Environment(RootNavigationState.self) private var root
        @FocusState private var focused: Bool
        let id: String
        let section: String
        let ids: [String]
        let initial: Bool
        let item: MediaItem?
        let entry: NextUpEntry?
        let context: String

        func body(content: Content) -> some View {
            content
                .focused($focused)
                .focusedValue(\.gusTVMedia, item)
                .focusedValue(\.gusTVEntry, entry)
                .task(id: root.tvFocus.restorationRequest(context: context)) {
                    // Realize the native link before requesting a saved focus target.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    if root.tvFocus.restoredID(section: section, context: context, ids: ids, initial: initial) == id {
                        focused = true
                    }
                }
                .onChange(of: focused) { _, value in
                    guard value, let index = ids.firstIndex(of: id) else { return }
                    if root.tvFocus.remember(id: id, index: index, section: section, context: context, ids: ids) {
                        root.scrollAnchors[section] = id
                    }
                }
        }
    }

    /// Focus changes drive decoration only; ordering and navigation remain in HomeStore.
    private struct TVNextUpHero<Content: View>: View {
        @Environment(RootNavigationState.self) private var root
        @FocusedValue(\.gusTVEntry) private var focusedEntry
        @FocusedValue(\.gusTVMedia) private var focusedMedia
        @State private var selectedID: String?
        let entries: [NextUpEntry]
        @ViewBuilder let content: () -> Content

        private var selected: NextUpEntry? {
            let id = selectedID ?? root.tvFocus.bookmarks["home.next"]?.restoredID(in: entries.map(\.id))
            return entries.first { $0.id == id } ?? entries.first
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                if let entry = selected {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(entry.playlist?.name.trimmedNilIfEmpty ?? entry.item?.seriesName?.trimmedNilIfEmpty ?? entry.item?.displayTitle ?? String(localized: "Next Up"))
                            .font(.largeTitle.bold()).lineLimit(2)
                        if let item = entry.item {
                            if item.type == .episode {
                                Text([item.episodeLocator, item.displayTitle].compactMap { $0 }.joined(separator: " · "))
                                    .font(.title3).lineLimit(2)
                            }
                            HeroMetadataRow(item: item, foreground: .primary)
                            if let overview = item.overview?.trimmedNilIfEmpty {
                                Text(overview).font(.body).lineLimit(3)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 900, minHeight: 260, alignment: .bottomLeading)
                    // Cards carry the same title/state; decoration must not repeat speech.
                    .accessibilityHidden(true)
                }
                content()
            }
            .padding(.top, 48)
            .onChange(of: focusedEntry) { _, entry in
                if let entry, entries.contains(where: { $0.id == entry.id }) {
                    selectedID = entry.id
                }
            }
            .onChange(of: focusedMedia) { _, item in
                if let id = entries.first(where: { $0.item?.id == item?.id })?.id {
                    selectedID = id
                }
            }
        }
    }

    private struct TVBrowsingBackdrop: View {
        @Environment(\.colorScheme) private var colorScheme
        @Environment(SessionStore.self) private var session
        @FocusedValue(\.gusTVMedia) private var focusedItem
        @State private var item: MediaItem?

        private var canvas: Color {
            colorScheme == .dark ? .black : .white
        }

        var body: some View {
            GeometryReader { geometry in
                ZStack {
                    canvas
                    if let item {
                        AsyncPoster(url: session.mediaProvider.backdropImageURL(for: item, maxWidth: 1920), placeholderSymbol: "play.rectangle")
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .overlay {
                                LinearGradient(colors: [canvas.opacity(0.8), canvas.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
                            }
                            .overlay {
                                LinearGradient(colors: [.clear, canvas.opacity(0.85), canvas], startPoint: .top, endPoint: .bottom)
                            }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
            .accessibilityHidden(true)
            .task(id: focusedItem?.id) {
                guard let focusedItem else { return }
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                guard !Task.isCancelled else { return }
                item = focusedItem
            }
        }
    }
#endif
