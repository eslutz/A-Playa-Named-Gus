import SwiftUI

/// Toolbar symbols remain native, with their full spoken names retained.
/// Other platforms keep the original Label presentation.
/// Set the accessible name on the enclosing Button or Menu as well: native
/// tvOS toolbar containers do not always promote a child image label.
struct GusToolbarLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tvSystemImage: String?

    init(_ title: LocalizedStringKey, systemImage: String, tvSystemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.tvSystemImage = tvSystemImage
    }

    var body: some View {
        #if os(tvOS)
            Image(systemName: tvSystemImage ?? systemImage).accessibilityLabel(Text(title))
        #else
            Label(title, systemImage: systemImage)
        #endif
    }
}

extension View {
    @ViewBuilder func gusTVNativeControls() -> some View {
        #if os(tvOS)
            if #available(tvOS 27.0, *) {
                self
            } else {
                buttonStyle(.bordered).tint(nil)
            }
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVToolbarIcon() -> some View {
        #if os(tvOS)
            labelStyle(.iconOnly).gusTVNativeControls()
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVHomeTitle() -> some View {
        #if os(tvOS)
            navigationTitle("Home")
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

    func gusTVNextUpHero(entries: [NextUpEntry]) -> some View {
        self
    }

    func gusTVFallbackHero(items: [MediaItem], enabled: Bool) -> some View {
        self
    }

    @ViewBuilder func gusTVBrowsingBackdrop() -> some View {
        #if os(tvOS)
            gusTVCanvas()
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVCanvas() -> some View {
        #if os(tvOS)
            modifier(TVOpaqueCanvas())
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
            gusTVCanvas()
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

    @ViewBuilder func gusTVSingleContentTitle() -> some View {
        #if os(tvOS)
            navigationTitle("")
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVDetailTitle() -> some View {
        #if os(tvOS)
            toolbar(.hidden, for: .navigationBar)
        #else
            self
        #endif
    }

    @ViewBuilder func gusTVContentHeading(_ title: String) -> some View {
        #if os(tvOS)
            VStack(alignment: .leading, spacing: 32) {
                Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                self
            }
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
            labelStyle(.iconOnly)
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
        var ids = ["play", "nextUp", "favorite"]
        ids += ["more", "synopsis"]
        return gusTVFocus(id: id, section: "detail:" + ItemRef(item: item).id, ids: ids, initial: initial, item: item)
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
                .task(id: root.tvFocus.restorationRequest(context: context)) {
                    // Realize the native link before requesting a saved focus target.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    if root.tvFocus.restoredID(section: section, context: context, ids: ids, initial: initial) == id {
                        focused = false
                        await Task.yield()
                        guard !Task.isCancelled else { return }
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

#endif

#if os(tvOS)
    private struct TVOpaqueCanvas: ViewModifier {
        @Environment(\.colorScheme) private var colorScheme

        func body(content: Content) -> some View {
            content.background {
                (colorScheme == .dark ? Color.black : Color.white).ignoresSafeArea()
            }
        }
    }
#endif

@MainActor extension RootNavigationState {
    func restoreTVDetailFocus(item: MediaItem) {
        #if os(tvOS)
            let context = "detail:" + ItemRef(item: item).id
            tvFocus.remember(id: "more", index: 3, section: context, context: context)
            tvFocus.requestRestoration(context: context)
        #endif
    }
}
