import SwiftUI

extension View {
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
            background { TVBrowsingBackdrop() }
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVPagePadding() -> some View {
        #if os(tvOS)
            padding(.horizontal, 64).padding(.vertical, 32)
        #else
            padding()
        #endif
    }

    @ViewBuilder func gusTVRailPadding() -> some View {
        #if os(tvOS)
            padding(.vertical, 32).padding(.horizontal, 24).scrollClipDisabled()
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

    @ViewBuilder func gusTVPosterTitle() -> some View {
        #if os(tvOS)
            lineLimit(2)
        #else
            lineLimit(1)
        #endif
    }

    @ViewBuilder func gusTVArtworkStatus(item: MediaItem?) -> some View {
        #if os(tvOS)
            overlay(alignment: .topTrailing) {
                if item?.userData?.isWatched == true {
                    Image(systemName: "checkmark.circle.fill").padding(8)
                        .background(.regularMaterial, in: Capsule()).padding(12).accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottom) {
                if let progress = item?.playbackProgress, progress > 0, progress < 1 {
                    ProgressView(value: progress).padding(12).background(.black.opacity(0.75)).accessibilityHidden(true)
                }
            }
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVPosterStatusValue(item: MediaItem?) -> some View {
        #if os(tvOS)
            if let progress = item?.playbackProgress, progress > 0, progress < 1 {
                accessibilityValue(Text("Playback progress \(Int(progress * 100))%"))
            } else if let watched = item?.userData?.isWatched {
                accessibilityValue(watched ? Text("Watched") : Text("Unwatched"))
            } else {
                self
            }
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVActionLabel() -> some View {
        #if os(tvOS)
            labelStyle(.titleAndIcon)
        #else
            labelStyle(.iconOnly)
        #endif
    }
}

#if os(tvOS)
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
                .task {
                    // Realize the native link before requesting a saved focus target.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    if root.tvFocus.restoredID(section: section, context: context, ids: ids, initial: initial) == id {
                        focused = true
                    }
                }
                .onChange(of: focused) { _, value in
                    guard value, let index = ids.firstIndex(of: id) else { return }
                    root.tvFocus.remember(id: id, index: index, section: section, context: context)
                    root.scrollAnchors[section] = id
                }
        }
    }

    /// Focus changes drive decoration only; ordering and navigation remain in HomeStore.
    private struct TVNextUpHero<Content: View>: View {
        @Environment(SessionStore.self) private var session
        @Environment(RootNavigationState.self) private var root
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @FocusedValue(\.gusTVEntry) private var focusedEntry
        @FocusedValue(\.gusTVMedia) private var focusedMedia
        @State private var selectedID: String?
        @State private var backgroundItem: MediaItem?
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
                        Text(entry.playlist?.name ?? entry.item?.seriesName ?? entry.item?.displayTitle ?? String(localized: "Next Up"))
                            .font(.largeTitle.bold()).lineLimit(2)
                        if let item = entry.item {
                            if item.type == .episode {
                                Text([item.episodeLocator, item.displayTitle].compactMap { $0 }.joined(separator: " · "))
                                    .font(.title3).lineLimit(2)
                            }
                            HeroMetadataRow(item: item)
                            if let overview = item.overview?.trimmedNilIfEmpty {
                                Text(overview).font(.body).lineLimit(3)
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(24)
                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: 900, minHeight: 260, alignment: .bottomLeading)
                    // Cards carry the same title/state; decoration must not repeat speech.
                    .accessibilityHidden(true)
                }
                content()
            }
            .padding(.top, 48)
            .background {
                GeometryReader { geometry in
                    AsyncPoster(url: backgroundItem.flatMap { session.mediaProvider.backdropImageURL(for: $0, maxWidth: 1920) }, placeholderSymbol: "play.rectangle")
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .overlay {
                            LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.7), .black], startPoint: .top, endPoint: .bottom)
                        }
                        .accessibilityHidden(true)
                }
            }
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
            .task(id: selected?.item?.id) {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { backgroundItem = selected?.item }
            }
        }
    }

    private struct TVBrowsingBackdrop: View {
        @Environment(SessionStore.self) private var session
        @FocusedValue(\.gusTVMedia) private var focusedItem
        @State private var item: MediaItem?

        var body: some View {
            GeometryReader { geometry in
                AsyncPoster(url: item.flatMap { session.mediaProvider.backdropImageURL(for: $0, maxWidth: 1920) }, placeholderSymbol: "play.rectangle")
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .blur(radius: 30)
                    .overlay(.black.opacity(0.8))
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            .task(id: focusedItem?.id) {
                guard let focusedItem else { return }
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                guard !Task.isCancelled else { return }
                item = focusedItem
            }
        }
    }
#endif
